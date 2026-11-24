#!/usr/bin/env python3
"""Living Assets – material recognition for Penzilla sprites.

Splits a sprite into flat colour components (Penzilla art is cel-shaded, so
every surface is a handful of flat colours) and classifies each component as
a material. Effects then pick material-appropriate damage and ageing
(docs/living_assets/PRODUCTION_STANDARD.md §4):

  outline  Penzilla contour (#330022 family)       – never changed
  glass    windows, lamp glass                     – breaks, gets dirty, boarded
  roof     pitched or flat roof surfaces           – missing tiles, moss, holes
  plaster  painted / rendered walls                – cracks, peeling (brick shows)
  brick    brick walls (texture of small bricks)   – stepped cracks, chipped bricks
  stone    grey stone / concrete                   – angular chips, moss
  wood     beams, planks, crates, doors            – splits along the grain, greying, rot
  trim     light painted parts (doors, frames)     – chipped paint
  metal    lamps, hydrants, pipes, vehicles        – rust, dents, paint chips
  fabric   awnings, tents, flags                   – tears, fading, sagging
  plant    leaves, grass, planters                 – dries, dies
  water    fountains, ponds                        – algae, ice, dries up

Automatic rules + optional per-asset corrections (`overrides`, see
tools/assets/living_assets.json): colour selectors and rectangles in source
pixels. Deterministic, no randomness.
"""
import numpy as np
from scipy import ndimage

MATERIALS = ["none", "outline", "glass", "roof", "plaster", "brick", "stone", "wood", "trim", "metal", "fabric", "plant", "water"]
MAT = {name: i for i, name in enumerate(MATERIALS)}
# Colours for the material map contact sheets (QA only).
MAP_COLOURS = {
    "none": (0, 0, 0, 0), "outline": (40, 20, 40, 255), "glass": (120, 220, 255, 255), "roof": (150, 40, 40, 255),
    "plaster": (240, 220, 170, 255), "brick": (220, 110, 60, 255), "stone": (150, 150, 160, 255), "wood": (140, 90, 40, 255),
    "trim": (255, 255, 255, 255), "metal": (80, 110, 170, 255), "fabric": (230, 60, 200, 255), "plant": (70, 190, 70, 255),
    "water": (40, 90, 230, 255),
}


def lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    m = d > 1e-6
    safe = np.where(m, d, 1)
    rc = np.where(m, (mx - r) / safe, 0)
    gc = np.where(m, (mx - g) / safe, 0)
    bc = np.where(m, (mx - b) / safe, 0)
    h = np.where(r == mx, bc - gc, np.where(g == mx, 2.0 + rc - bc, 4.0 + gc - rc))
    h = np.where(m, (h / 6.0) % 1.0, 0)
    s = np.where(mx > 1e-6, d / np.where(mx > 1e-6, mx, 1), 0)
    return np.stack([h, s, mx], -1)


def hue_in(h, lo, hi):
    return (lo <= h <= hi) if lo <= hi else (h >= lo or h <= hi)


class Component:
    __slots__ = ("id", "sl", "sub", "area", "share", "cy", "cx", "hsv", "rel_y", "exposure", "material", "axis", "elong", "texture")

    def mask(self, shape):
        m = np.zeros(shape, bool)
        m[self.sl] = self.sub
        return m

    @property
    def kind(self):  # backwards compatible name used by older effects
        return self.material


class MaterialSeg:
    """Segmentation + material map. `category` steers the defaults:
    building, prop, vehicle, vegetation, surface, interior."""

    def __init__(self, a, category="building", default_material=None, overrides=None, hint=None):
        self.a = a
        self.shape = a.shape[:2]
        H, W = self.shape
        self.opaque = a[..., 3] > 0.5
        ys, xs = np.nonzero(self.opaque)
        self.bbox = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1) if len(xs) else (0, 0, W, H)
        self.h = self.bbox[3] - self.bbox[1]
        self.w = self.bbox[2] - self.bbox[0]
        self.unit = max(self.h, self.w) / 540.0
        rgb = a[..., :3]
        self.hsv = rgb_to_hsv(rgb)
        self.lum = lum(rgb)
        self.outline = self.opaque & (self.lum < 0.17)
        self.inner = self.opaque & ~self.outline
        self.category = category
        self._components()
        self._exposure()
        self._classify(default_material)
        if hint is not None:
            self._apply_hint(hint)
        if overrides:
            self._apply_overrides(overrides)
        self._build_map()

    # --- segmentation (bbox-limited labelling: fast on big sprites) ------------
    def _components(self):
        H, W = self.shape
        q = np.round(self.a[..., :3] * 20).astype(np.int32)
        key = q[..., 0] * 441 + q[..., 1] * 21 + q[..., 2]
        keyimg = np.zeros((H, W), np.int32)
        _, inv = np.unique(key[self.inner], return_inverse=True)
        keyimg[self.inner] = inv.reshape(-1) + 1
        self.comp_img = np.zeros((H, W), np.int32)
        self.components = []
        total = max(int(self.inner.sum()), 1)
        y0 = self.bbox[1]
        nid = 0
        st = np.ones((3, 3), bool)
        for idx, sl in enumerate(ndimage.find_objects(keyimg)):
            if sl is None:
                continue
            region = keyimg[sl] == idx + 1
            lab, n = ndimage.label(region, structure=st)
            if n == 0:
                continue
            sizes = np.bincount(lab.ravel())
            for i in range(1, n + 1):
                if sizes[i] < 12:
                    continue
                sub_full = lab == i
                ys, xs = np.nonzero(sub_full)
                sl2 = (slice(sl[0].start + ys.min(), sl[0].start + ys.max() + 1), slice(sl[1].start + xs.min(), sl[1].start + xs.max() + 1))
                sub = sub_full[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
                nid += 1
                c = Component()
                c.id = nid
                c.sl = sl2
                c.sub = sub
                c.area = int(sizes[i])
                c.share = c.area / total
                gy = ys + sl[0].start
                gx = xs + sl[1].start
                c.cy, c.cx = float(gy.mean()), float(gx.mean())
                c.hsv = self.hsv[gy, gx].mean(0)
                c.rel_y = (c.cy - y0) / max(self.h, 1)
                # principal axis (wood grain direction) and elongation
                if c.area > 3:
                    cov = np.cov(np.stack([gx - c.cx, gy - c.cy]))
                    ev, evec = np.linalg.eigh(cov)
                    c.axis = (float(evec[0, 1]), float(evec[1, 1]))
                    c.elong = float(np.sqrt(max(ev[1], 1e-6) / max(ev[0], 1e-6)))
                else:
                    c.axis, c.elong = (1.0, 0.0), 1.0
                c.texture = 0
                c.material = "plaster"
                self.comp_img[sl2][sub] = nid
                self.components.append(c)
        # pixels of tiny components inherit the material of the nearest component
        self.small = self.inner & (self.comp_img == 0)

    def _exposure(self):
        """Share of a component's upper edge that faces the sky (only the
        outline lies between it and transparency): roofs, awnings, tops."""
        H, W = self.shape
        reach = max(2, int(round(9 * self.unit)))
        transparent = ~self.opaque
        # sky_above[y, x]: transparent pixel within `reach` rows above
        sky = np.zeros((H, W), bool)
        for k in range(1, reach + 1):
            sky[k:] |= transparent[:-k]
        sky[:reach] |= True
        for c in self.components:
            sub = c.sub
            top = sub & ~np.vstack([np.zeros((1, sub.shape[1]), bool), sub[:-1]])
            ty, tx = np.nonzero(top)
            if len(ty) == 0:
                c.exposure = 0.0
                continue
            gy = np.clip(ty + c.sl[0].start, 0, H - 1)
            gx = tx + c.sl[1].start
            c.exposure = float(sky[gy, gx].mean())
        # brick texture: many small components of similar hue inside a component's box
        centres = np.array([[c.cy, c.cx, c.hsv[0], c.area] for c in self.components]) if self.components else np.zeros((0, 4))
        for c in self.components:
            if c.share < 0.01 or len(centres) == 0:
                continue
            (ya, yb), (xa, xb) = (c.sl[0].start, c.sl[0].stop), (c.sl[1].start, c.sl[1].stop)
            small = (centres[:, 3] < c.area * 0.02) & (centres[:, 0] >= ya) & (centres[:, 0] < yb) & (centres[:, 1] >= xa) & (centres[:, 1] < xb)
            dh = np.abs(((centres[:, 2] - c.hsv[0]) + 0.5) % 1.0 - 0.5)
            c.texture = int((small & (dh < 0.06)).sum())

    # --- classification ------------------------------------------------------
    def _classify(self, default_material):
        cat = self.category
        for c in self.components:
            h, s, v = c.hsv
            glassy = (0.47 < h < 0.62 and s > 0.25 and v > 0.7) or (v > 0.88 and 0.05 < s < 0.25 and 0.4 < h < 0.7)
            # darker blue panes (e.g. fire station) – buildings only, compact shapes
            if cat == "building" and 0.5 < h < 0.7 and s > 0.3 and v > 0.45 and c.share < 0.012 and c.elong < 4:
                glassy = True
            if c.elong > 6:
                glassy = False   # long thin strips are trim/cornices, not panes
            green = hue_in(h, 0.17, 0.45) and s > 0.3
            brown = hue_in(h, 0.02, 0.12) and 0.28 < s < 0.9 and 0.2 < v < 0.8
            grey = s < 0.16
            light = v > 0.86 and s < 0.22
            m = None
            if cat == "vegetation":
                m = "plant" if (green or (hue_in(h, 0.08, 0.17) and s > 0.3)) else "wood"
            elif cat == "surface":
                m = "plant" if green else "stone"
            elif cat == "vehicle":
                m = "glass" if glassy else ("metal" if not (grey and v < 0.3) else "stone")
            if m is None and cat == "prop" and 0.5 < h < 0.64 and s > 0.35 and v > 0.7 and c.share >= 0.02:
                m = "water"   # fountain basins, troughs
            if m is None:
                # Penzilla greys are tinted (purple/blue): allow more saturation when dark
                greyish = s < 0.16 or (s < 0.3 and v < 0.55 and not brown)
                if glassy and (c.share < 0.035 or (c.area < 2500 * self.unit ** 2 and c.share < 0.12)):
                    m = "glass"
                elif green and c.share < 0.03 and c.exposure < 0.6:
                    m = "plant"
                elif cat == "building" and c.exposure > 0.45 and c.rel_y < 0.8 and c.share > 0.006:
                    m = "fabric" if (s > 0.55 and v > 0.35) else "roof"
                elif cat == "building" and c.rel_y > 0.75 and c.exposure > 0.3 and greyish and c.share > 0.02:
                    m = "stone"   # forecourt / pavement at the base
                elif brown and (cat != "building" or c.share < 0.03):
                    m = "wood"    # doors, beams, crates – big brown walls are paint
                elif light and c.share < 0.06:
                    m = "trim"
                elif cat == "building" and c.rel_y < 0.55 and v < 0.42 and c.share > 0.01:
                    m = "roof"
                elif greyish:
                    m = "metal" if (c.share < 0.025 or cat == "prop") else "stone"
                elif default_material and cat != "building":
                    m = default_material
                else:
                    m = "brick" if (c.texture >= 40 and hue_in(h, 0.95, 0.09) and s > 0.3) else "plaster"
            c.material = m
        if cat == "building":
            self._post_building()

    def _post_building(self):
        """Context pass: (1) texture details (tile lines, brick joints,
        highlights) take the material of the surface they lie in; (2) faces
        with the roof colour are roof (side slopes, dormers)."""
        big = sorted([c for c in self.components if c.share >= 0.012], key=lambda c: -c.area)
        for c in self.components:
            if c.share >= 0.012 or c.material in ("glass", "trim", "plant", "fabric"):
                continue
            for p in big:
                (ya, yb), (xa, xb) = (p.sl[0].start, p.sl[0].stop), (p.sl[1].start, p.sl[1].stop)
                if not (ya <= c.cy < yb and xa <= c.cx < xb):
                    continue
                dh = abs(((c.hsv[0] - p.hsv[0]) + 0.5) % 1.0 - 0.5)
                if (dh < 0.08 or (c.hsv[1] < 0.2 and p.hsv[1] < 0.3)) and abs(c.hsv[2] - p.hsv[2]) < 0.35 and p.material in ("roof", "brick", "plaster", "wood", "stone"):
                    c.material = p.material
                    break
        # (3) light and shaded faces of the same wall get the same material
        walls = sorted([c for c in self.components if c.material in ("plaster", "brick", "wood") and c.share >= 0.012], key=lambda c: -c.area)
        for i, c in enumerate(walls):
            for p in walls[:i]:
                dh = abs(((c.hsv[0] - p.hsv[0]) + 0.5) % 1.0 - 0.5)
                if dh < 0.035 and abs(c.hsv[1] - p.hsv[1]) < 0.2 and p.material != c.material:
                    c.material = p.material
                    break
        roofs = [c for c in self.components if c.material == "roof" and c.share > 0.01]
        for c in self.components:
            if c.material not in ("stone", "metal") or c.rel_y > 0.75:
                continue
            for r in roofs:
                dh = abs(((c.hsv[0] - r.hsv[0]) + 0.5) % 1.0 - 0.5)
                if dh < 0.05 and abs(c.hsv[1] - r.hsv[1]) < 0.12 and abs(c.hsv[2] - r.hsv[2]) < 0.3:
                    c.material = "roof"
                    break

    def _apply_hint(self, hint):
        """Per-pixel material names from layered sources (majority per component).
        'window' = glass where the colour is glassy, wood (frame) elsewhere."""
        for c in self.components:
            vals = hint[c.sl][c.sub]
            vals = vals[vals != ""]
            if len(vals) == 0:
                continue
            names, counts = np.unique(vals, return_counts=True)
            m = str(names[counts.argmax()])
            if m == "window":
                h, sat, v = c.hsv
                m = "glass" if (c.material == "glass" or (v > 0.72 and sat < 0.32)) else "wood"
            elif m == "fabric" and c.material == "wood":
                m = "wood"    # tent poles, awning rods
            elif m == "trim" and c.material == "glass":
                m = "glass"
            c.material = m

    def _apply_overrides(self, overrides):
        """overrides: list of {"material": m, "hsv": [h, s, v], "tol": t}
        (component mean colour within tolerance) and/or "rect": [x0, y0, x1, y1]
        (component centre inside, source pixels; optional "min_share")."""
        for rule in overrides:
            for c in self.components:
                ok = True
                if "hsv" in rule:
                    tol = rule.get("tol", 0.06)
                    dh = abs(((c.hsv[0] - rule["hsv"][0]) + 0.5) % 1.0 - 0.5)
                    ok &= dh < tol and abs(c.hsv[1] - rule["hsv"][1]) < tol * 2.5 and abs(c.hsv[2] - rule["hsv"][2]) < tol * 2.5
                if "rect" in rule:
                    x0, y0, x1, y1 = rule["rect"]
                    ok &= x0 <= c.cx < x1 and y0 <= c.cy < y1
                if "from" in rule:
                    ok &= c.material in rule["from"]
                if ok and c.share >= rule.get("min_share", 0.0):
                    c.material = rule["material"]

    def _build_map(self):
        H, W = self.shape
        lut = np.zeros(len(self.components) + 1, np.int8)
        for c in self.components:
            lut[c.id] = MAT[c.material]
        mat = lut[self.comp_img]
        mat[self.outline] = MAT["outline"]
        # tiny components (highlights, specks): take the most common material around them
        if self.small.any():
            filled = mat.copy()
            known = (mat > 1)
            if known.any():
                _, (iy, ix) = ndimage.distance_transform_edt(~known, return_indices=True)
                filled[self.small] = mat[iy[self.small], ix[self.small]]
            mat = filled
        mat[~self.opaque] = 0
        self.mat = mat
        self.masks = {name: mat == i for name, i in MAT.items()}
        # names used by the older effect functions
        self.glass = self.masks["glass"]
        self.roof = self.masks["roof"]
        self.facade = self.masks["plaster"] | self.masks["brick"] | self.masks["stone"] | self.masks["wood"]
        self.other = self.inner & ~self.glass & ~self.roof & ~self.facade

    # --- helpers ---------------------------------------------------------------
    def m(self, *names):
        out = np.zeros(self.shape, bool)
        for n in names:
            out |= self.masks[n]
        return out

    def comps(self, *names):
        return [c for c in self.components if c.material in names]

    def glass_components(self):
        return [c for c in self.comps("glass") if c.area >= 30]

    def px(self, v):
        return max(1, int(round(v * self.unit)))

    def map_image(self):
        out = np.zeros(self.shape + (4,), np.uint8)
        for name, i in MAT.items():
            out[self.mat == i] = MAP_COLOURS[name]
        return out

    def stats(self):
        tot = max(int(self.opaque.sum()), 1)
        return {n: round(float(self.masks[n].sum()) / tot, 3) for n in MATERIALS[1:] if self.masks[n].any()}
