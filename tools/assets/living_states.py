#!/usr/bin/env python3
"""Living Assets – visual state derivation in the Penzilla style.

Library + CLI. Derives state variants (wear, damage, fire, ruin, weather)
from ORIGINAL Penzilla sprites WITHOUT modifying them; results are separate
files. Style rules (docs/living_assets/PRODUCTION_STANDARD.md):
  * flat colour areas with hard edges (cel look) – no photographic noise,
  * new shapes get the Penzilla outline colour (#330022) and stroke width
    proportional to the sprite (≈1.2 % of its height),
  * colours are derived from the asset's own palette (darker/desaturated/
    shifted), plus a small fixed palette for soot, rust, moss, snow, water,
  * isometric perspective is preserved (ellipses squashed 2:1),
  * output keeps the original canvas size and anchor (drop-in in Godot).
Deterministic: every effect takes a seed.

Requires numpy, scipy, pillow (generator only – never part of the game).
"""
import math

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

OUTLINE = np.array([51, 0, 34], np.float32) / 255.0
SOOT = np.array([0.17, 0.14, 0.16], np.float32)
INTERIOR = np.array([0.20, 0.12, 0.20], np.float32)
PLASTER = np.array([0.88, 0.84, 0.76], np.float32)
RUST = np.array([0.66, 0.36, 0.18], np.float32)
RUST_DARK = np.array([0.47, 0.24, 0.13], np.float32)
MOSS = np.array([0.42, 0.62, 0.27], np.float32)
MOSS_DARK = np.array([0.30, 0.47, 0.20], np.float32)
SNOW = np.array([0.95, 0.97, 1.0], np.float32)
SNOW_SHADE = np.array([0.76, 0.84, 0.95], np.float32)
WATER = np.array([0.42, 0.62, 0.82], np.float32)
MUD = np.array([0.42, 0.31, 0.22], np.float32)
WOOD = np.array([0.56, 0.38, 0.23], np.float32)
GRIME = np.array([0.30, 0.23, 0.17], np.float32)
CHAR = np.array([0.20, 0.17, 0.17], np.float32)


# --- io / colour ---------------------------------------------------------------

def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0


def save(a, path):
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path, optimize=True)


def to_image(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rc = np.where(m, (mx - r) / np.where(m, d, 1), 0)
    gc = np.where(m, (mx - g) / np.where(m, d, 1), 0)
    bc = np.where(m, (mx - b) / np.where(m, d, 1), 0)
    h = np.where(r == mx, bc - gc, np.where(g == mx, 2.0 + rc - bc, 4.0 + gc - rc))
    h = (h / 6.0) % 1.0
    h = np.where(m, h, 0)
    s = np.where(mx > 1e-6, d / np.where(mx > 1e-6, mx, 1), 0)
    return np.stack([h, s, mx], -1)


def hsv_to_rgb(hsv):
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    i = np.floor(h * 6.0)
    f = h * 6.0 - i
    p = v * (1 - s)
    q = v * (1 - s * f)
    t = v * (1 - s * (1 - f))
    i = i.astype(int) % 6
    out = np.zeros(h.shape + (3,), np.float32)
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        sel = i == k
        out[sel, 0] = a[sel]
        out[sel, 1] = b[sel]
        out[sel, 2] = c[sel]
    return out


def lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


# --- analysis ----------------------------------------------------------------

class Seg:
    """Penzilla sprite segmentation: outline, glass, roof, facade, other."""

    def __init__(self, a):
        self.a = a
        self.opaque = a[..., 3] > 0.5
        ys, xs = np.nonzero(self.opaque)
        self.bbox = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1) if len(xs) else (0, 0, a.shape[1], a.shape[0])
        self.h = self.bbox[3] - self.bbox[1]
        self.w = self.bbox[2] - self.bbox[0]
        self.unit = max(self.h, self.w) / 540.0  # 1.0 = a typical house sprite
        rgb = a[..., :3]
        self.hsv = rgb_to_hsv(rgb)
        self.lum = lum(rgb)
        self.outline = self.opaque & (self.lum < 0.17)
        inner = self.opaque & ~self.outline
        # Flat colour components.
        q = np.round(rgb * 20).astype(np.int32)
        key = q[..., 0] * 441 + q[..., 1] * 21 + q[..., 2]
        key = np.where(inner, key, -1)
        total = max(int(inner.sum()), 1)
        self.glass = np.zeros_like(inner)
        self.roof = np.zeros_like(inner)
        self.facade = np.zeros_like(inner)
        self.components = []
        y0 = self.bbox[1]
        for k in np.unique(key):
            if k < 0:
                continue
            lab, n = ndimage.label(key == k, structure=np.ones((3, 3)))
            for i in range(1, n + 1):
                m = lab == i
                area = int(m.sum())
                if area < 30:
                    continue
                cy, cx = ndimage.center_of_mass(m)
                hsv = self.hsv[m].mean(0)
                rel_y = (cy - y0) / max(self.h, 1)
                share = area / total
                comp = {"mask": m, "area": area, "share": share, "cy": cy, "cx": cx, "hsv": hsv, "rel_y": rel_y}
                h, s, v = hsv
                is_glassy = (0.47 < h < 0.62 and s > 0.25 and v > 0.7) or (v > 0.88 and s < 0.25 and 0.4 < h < 0.7)
                if is_glassy and (share < 0.035 or (area < 2500 and share < 0.12)):
                    comp["kind"] = "glass"
                    self.glass |= m
                elif v < 0.42 and rel_y < 0.62 and share > 0.01:
                    comp["kind"] = "roof"
                    self.roof |= m
                elif share > 0.02 and v >= 0.35:
                    comp["kind"] = "facade"
                    self.facade |= m
                else:
                    comp["kind"] = "other"
                self.components.append(comp)
        self.other = inner & ~self.glass & ~self.roof & ~self.facade
        self.inner = inner

    def glass_components(self):
        return [c for c in self.components if c["kind"] == "glass"]

    def px(self, v):
        """Size in pixels scaled to the sprite (v given for a 540-px sprite)."""
        return max(1, int(round(v * self.unit)))


def smooth_field(shape, sigma, seed):
    rng = np.random.default_rng(seed)
    f = ndimage.gaussian_filter(rng.random(shape).astype(np.float32), sigma)
    f -= f.min()
    return f / max(f.max(), 1e-6)


def edge_of(mask, width):
    """Ring of `width` px just inside the mask border."""
    if width <= 0:
        return np.zeros_like(mask)
    return mask & ~ndimage.binary_erosion(mask, iterations=width)


def paint(a, mask, rgb, alpha=1.0):
    out = a.copy()
    out[mask, :3] = out[mask, :3] * (1 - alpha) + rgb * alpha
    return out


def outline_shape(a, shape_mask, clip, width):
    """Draws the Penzilla outline along the inside border of a new shape."""
    return paint(a, edge_of(shape_mask, width) & clip, OUTLINE)


# --- generic effects -----------------------------------------------------------

def fresh(a, seg):
    hsv = rgb_to_hsv(a[..., :3])
    m = seg.inner
    hsv[m, 1] = np.clip(hsv[m, 1] * 1.07, 0, 1)
    hsv[m, 2] = np.clip(hsv[m, 2] * 1.04, 0, 1)
    out = a.copy()
    out[..., :3] = np.where(m[..., None], hsv_to_rgb(hsv), a[..., :3])
    return out


def desaturate(a, seg, k, darken=0.0, region=None):
    region = seg.inner if region is None else region
    hsv = rgb_to_hsv(a[..., :3])
    hsv[region, 1] *= (1 - k)
    hsv[region, 2] *= (1 - darken)
    out = a.copy()
    out[..., :3] = np.where(region[..., None], hsv_to_rgb(hsv), a[..., :3])
    return out


def dirt(a, seg, level, seed, region=None, drips=True):
    """Flat, hard-edged grime patches; more at the bottom and under windows."""
    if level <= 0:
        return a
    region = (seg.facade | seg.other) & ~seg.glass if region is None else region
    H, W = seg.opaque.shape
    f = smooth_field((H, W), seg.px(13), seed)
    yy = (np.arange(H)[:, None] - seg.bbox[1]) / max(seg.h, 1)
    f = f * 0.75 + np.clip(yy, 0, 1) * 0.45
    if drips:
        for c in seg.glass_components():
            ys, xs = np.nonzero(c["mask"])
            x0, x1, y1 = xs.min(), xs.max(), ys.max()
            w = int((x1 - x0) * 0.55)
            xc = int((x0 + x1) / 2)
            ln = int(seg.px(70) * (0.6 + level))
            img = Image.new("L", (W, H), 0)
            ImageDraw.Draw(img).rounded_rectangle([xc - w // 2, y1, xc + w // 2, min(H - 1, y1 + ln)], radius=max(1, w // 2), fill=255)
            f = f + (np.asarray(img) > 0) * 0.35
    thr = 1.08 - level * 0.62
    m = (f > thr) & region
    m = ndimage.binary_opening(m, iterations=2)
    # Grime = own colour, darker and blended towards warm brown (RGB blend:
    # rotating the hue would turn blue walls green).
    darker = a[..., :3] * 0.70 + GRIME * 0.30
    out = a.copy()
    out[m, :3] = darker[m]
    # a thin, even darker rim gives the cel-shaded stain edge
    rim = edge_of(m, seg.px(3)) & region
    out[rim, :3] = darker[rim] * 0.9
    return out


def peel(a, seg, level, seed):
    """Peeling paint: plaster showing through, with a dark rim."""
    if level <= 0:
        return a
    light = (seg.hsv[..., 2] > 0.9) & (seg.hsv[..., 1] < 0.15)
    region = seg.facade & ~light & ~ndimage.binary_dilation(seg.outline | seg.glass, iterations=seg.px(5))
    f = smooth_field(seg.opaque.shape, seg.px(4), seed + 1)
    m = (f > 1.0 - level * 0.26) & region
    m = ndimage.binary_opening(m, iterations=1)
    out = a.copy()
    base = a[..., :3]
    out[m, :3] = PLASTER * 0.75 + base[m] * 0.25
    out = outline_shape(out, m, region | m, seg.px(2))
    return out


def _random_crack(rng, start, length, unit, angle=None):
    pts = [start]
    ang = angle if angle is not None else rng.uniform(0.5, 2.6)
    x, y = start
    for k in range(rng.integers(4, 7)):
        ang += (0.9 if k % 2 == 0 else -0.9) * rng.uniform(0.5, 1.0)
        step = length * rng.uniform(0.12, 0.22)
        x += math.cos(ang) * step
        y += math.sin(ang) * step
        pts.append((x, y))
    return pts


def cracks(a, seg, count, seed, region=None):
    """Cracks in outline colour, branching, clipped to the facade."""
    if count <= 0:
        return a
    rng = np.random.default_rng(seed)
    region = seg.facade if region is None else region
    clip = ndimage.binary_erosion(region, iterations=seg.px(4))
    ys, xs = np.nonzero(clip)
    if len(xs) == 0:
        return a
    H, W = seg.opaque.shape
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    width = seg.px(8)
    for i in range(count):
        k = rng.integers(0, len(xs))
        start = (float(xs[k]), float(ys[k]))
        main = _random_crack(rng, start, seg.px(150), seg.unit)
        d.line(main, fill=255, width=width, joint="curve")
        if rng.random() < 0.7:
            j = rng.integers(1, len(main))
            branch = _random_crack(rng, main[j], seg.px(70), seg.unit)
            d.line(branch, fill=255, width=max(1, width - seg.px(2)), joint="curve")
    m = (np.asarray(img) > 0) & clip
    return paint(a, m, OUTLINE)


def _jagged_polygon(rng, cx, cy, rx, ry, points=11, jag=0.45):
    pts = []
    for i in range(points):
        t = 2 * math.pi * i / points + rng.uniform(-0.15, 0.15)
        r = 1.0 - jag * rng.random()
        pts.append((cx + math.cos(t) * rx * r, cy + math.sin(t) * ry * r))
    return pts


def broken_windows(a, seg, share, seed):
    """Glass gets a jagged hole (dark interior) with shards left at the frame."""
    rng = np.random.default_rng(seed)
    comps = seg.glass_components()
    rng.shuffle(comps)
    n = int(round(len(comps) * share))
    out = a.copy()
    H, W = seg.opaque.shape
    for c in comps[:n]:
        ys, xs = np.nonzero(c["mask"])
        cx, cy = xs.mean(), ys.mean()
        rx, ry = (xs.max() - xs.min()) * 0.5, (ys.max() - ys.min()) * 0.5
        img = Image.new("L", (W, H), 0)
        ImageDraw.Draw(img).polygon(_jagged_polygon(rng, cx, cy, rx * 0.95, ry * 0.95, 13, 0.55), fill=255)
        hole = (np.asarray(img) > 0) & c["mask"]
        out[hole, :3] = INTERIOR
        ring = ndimage.binary_dilation(hole, iterations=seg.px(3)) & ~hole & c["mask"]
        out[ring, :3] = OUTLINE
    return out


def roof_holes(a, seg, count, seed):
    """Missing tiles: jagged holes with dark interior and a visible rafter."""
    if count <= 0 or not seg.roof.any():
        return a
    rng = np.random.default_rng(seed)
    clip = ndimage.binary_erosion(seg.roof, iterations=seg.px(10))
    ys, xs = np.nonzero(clip)
    if len(xs) == 0:
        return a
    out = a.copy()
    H, W = seg.opaque.shape
    roof_col = a[seg.roof, :3].mean(0)
    for i in range(count):
        k = rng.integers(0, len(xs))
        cx, cy = xs[k], ys[k]
        r = seg.px(rng.uniform(30, 50))
        img = Image.new("L", (W, H), 0)
        ImageDraw.Draw(img).polygon(_jagged_polygon(rng, cx, cy, r, r * 0.6, 12, 0.4), fill=255)
        hole = (np.asarray(img) > 0) & seg.roof
        rim = ndimage.binary_dilation(hole, iterations=seg.px(9)) & ~hole & seg.roof
        out[rim, :3] = np.clip(roof_col * 1.45 + 0.05, 0, 1)
        out[hole, :3] = INTERIOR * 0.8
        beams = Image.new("L", (W, H), 0)
        bd = ImageDraw.Draw(beams)
        for off in (-0.3, 0.3):
            bd.line([(cx - r, cy + r * (0.35 + off)), (cx + r, cy - r * (0.35 - off))], fill=255, width=seg.px(10))
        bm = (np.asarray(beams) > 0) & hole
        out[bm, :3] = WOOD
        out = outline_shape(out, bm, hole, seg.px(3))
        ring = ndimage.binary_dilation(hole, iterations=seg.px(4)) & ~hole & seg.roof
        out[ring, :3] = OUTLINE
        out = outline_shape(out, rim, rim, seg.px(2))
    return out


def soot(a, seg, level, seed):
    """Flame-shaped soot plumes above openings plus a sooty base."""
    if level <= 0:
        return a
    rng = np.random.default_rng(seed)
    H, W = seg.opaque.shape
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    for c in seg.glass_components():
        ys, xs = np.nonzero(c["mask"])
        x0, x1, y0 = xs.min(), xs.max(), ys.min()
        w = (x1 - x0)
        for j in range(3):
            cx = x0 + w * (0.25 + 0.25 * j) + rng.uniform(-w * 0.1, w * 0.1)
            hgt = seg.px(90) * level * rng.uniform(0.7, 1.3)
            d.polygon([(cx - w * 0.28, y0 + seg.px(6)), (cx + w * 0.28, y0 + seg.px(6)), (cx + rng.uniform(-w * 0.2, w * 0.2), y0 - hgt)], fill=255)
    m = ndimage.binary_dilation(np.asarray(img) > 0, iterations=seg.px(4))
    f = smooth_field((H, W), seg.px(10), seed + 7)
    yy = (np.arange(H)[:, None] - seg.bbox[1]) / max(seg.h, 1)
    m |= (f * 0.6 + yy * 0.6) > (1.25 - level * 0.5)
    m &= seg.inner & ~seg.outline
    out = a.copy()
    out[m, :3] = out[m, :3] * 0.25 + SOOT * 0.75
    return out


def char(a, seg, k=1.0):
    """Burnt palette: dark, desaturated, warm-grey; glass black."""
    m = seg.inner
    l = lum(a[..., :3])[..., None]
    charred = CHAR + l * np.array([0.42, 0.37, 0.34], np.float32)  # keeps light/dark faces apart
    out = a.copy()
    out[m, :3] = a[m, :3] * (1 - k) + charred[m] * k
    out[seg.glass, :3] = INTERIOR * 0.6
    return out


def collapse(a, seg, frac, seed, rubble=True, side=0):
    """Removes everything above a jagged break line at `frac` of the height
    (0 = nothing, 1 = everything), outlines the break and adds rubble."""
    rng = np.random.default_rng(seed)
    H, W = seg.opaque.shape
    x0, y0, x1, y1 = seg.bbox
    out = a.copy()
    base_y = y0 + seg.h * frac
    xs = np.arange(W)
    noise = ndimage.gaussian_filter1d(rng.normal(0, 1, W), seg.px(14))
    noise = noise / max(np.abs(noise).max(), 1e-6)
    tilt = rng.uniform(-0.12, 0.12) * seg.h
    cut = base_y + noise * seg.px(38) + (xs - (x0 + x1) / 2) / max(seg.w, 1) * tilt
    # a few broken-brick notches (V shapes), no single-pixel spikes
    for n in range(int(rng.integers(4, 8))):
        cxn = rng.uniform(x0, x1)
        wn = seg.px(rng.uniform(16, 30))
        dn = seg.px(rng.uniform(14, 30)) * (1 if rng.random() < 0.5 else -1)
        cut += np.clip(1 - np.abs(xs - cxn) / wn, 0, 1) * dn
    if side != 0:
        # corner collapse: only one side breaks, the other keeps its full height
        t = np.clip((xs - x0) / max(seg.w, 1), 0, 1)
        ramp = t if side > 0 else 1 - t
        ramp = np.clip((ramp - 0.35) / 0.65, 0, 1)
        cut = y0 + (cut - y0) * ramp
    remove = np.arange(H)[:, None] < cut[None, :]
    out[remove] = 0.0
    kept = seg.opaque & ~remove
    # exposed interior band just under the break, then the outline
    band = kept & (np.arange(H)[:, None] < cut[None, :] + seg.px(26)) & ~seg.outline
    out[band, :3] = out[band, :3] * 0.35 + INTERIOR * 0.65
    top_edge = kept & ndimage.binary_dilation(remove & ~kept, iterations=seg.px(7))
    out[top_edge, :3] = OUTLINE
    out[top_edge, 3] = 1.0
    if rubble:
        out = add_rubble(out, seg, rng, a)
    return out


def add_rubble(out, seg, rng, src):
    """Cartoon rubble chunks in the asset's own colours, outlined."""
    H, W = seg.opaque.shape
    x0, y0, x1, y1 = seg.bbox
    palette = []
    for c in sorted(seg.components, key=lambda c: -c["area"])[:6]:
        if c["kind"] in ("facade", "roof", "other"):
            palette.append(src[c["mask"]][:, :3].mean(0))
    palette = palette or [np.array([0.5, 0.45, 0.45], np.float32)]
    img_mask = np.zeros((H, W), bool)
    layer = out.copy()
    count = int(22 * max(seg.unit, 0.4))
    for i in range(count):
        cx = rng.uniform(x0 + seg.w * 0.05, x1 - seg.w * 0.05)
        cy = rng.uniform(y1 - seg.h * 0.22, y1 - seg.px(8))
        r = seg.px(rng.uniform(14, 34))
        img = Image.new("L", (W, H), 0)
        ImageDraw.Draw(img).polygon(_jagged_polygon(rng, cx, cy, r, r * 0.62, 6, 0.35), fill=255)
        m = np.asarray(img) > 0
        col = palette[rng.integers(0, len(palette))] * rng.uniform(0.75, 1.0)
        layer[m, :3] = col
        layer[m, 3] = 1.0
        # top highlight
        hi = m & ~np.roll(m, seg.px(5), axis=0)
        layer[hi, :3] = np.clip(col * 1.18, 0, 1)
        layer = outline_shape(layer, m, m, seg.px(4))
        img_mask |= m
    return layer


def overgrowth(a, seg, level, seed):
    """Moss and ivy as outlined leaf clusters (bush shapes) from the base and
    a few ivy strands climbing the walls - Penzilla-like, no noise."""
    if level <= 0:
        return a
    rng = np.random.default_rng(seed)
    H, W = seg.opaque.shape
    x0, y0, x1, y1 = seg.bbox
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    bottom = np.full(W, -1)
    ys_op, xs_op = np.nonzero(seg.opaque)
    np.maximum.at(bottom, xs_op, ys_op)
    # ground = front edges of the isometric footprint (not the underside of an awning)
    yb = ys_op.max()
    xb = xs_op[ys_op == yb].mean()
    bottom = np.maximum(bottom, (yb - np.abs(np.arange(W) - xb) * 0.5).astype(int))
    for i in range(int(6 + 10 * level)):
        x = int(rng.uniform(x0 + seg.w * 0.05, x1 - seg.w * 0.05))
        by = bottom[x] if bottom[x] >= 0 else y1
        for j in range(int(rng.integers(4, 8))):
            r = seg.px(rng.uniform(9, 17))
            cx = x + rng.uniform(-r * 1.6, r * 1.6)
            cy = by - rng.uniform(0, r * 2.2)
            d.ellipse([cx - r, cy - r * 0.85, cx + r, cy + r * 0.85], fill=255)
    for i in range(int(2 + 4 * level)):
        x = rng.uniform(x0 + seg.w * 0.1, x1 - seg.w * 0.1)
        y = bottom[int(x)] if bottom[int(x)] >= 0 else y1
        for j in range(int(rng.integers(5, 10))):
            r = seg.px(rng.uniform(6, 10))
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
            x += rng.uniform(-r, r)
            y -= r * 1.4
    m = (np.asarray(img) > 0) & ndimage.binary_dilation(seg.opaque, iterations=seg.px(12))
    out = a.copy()
    out[m, :3] = MOSS_DARK
    light = m & (smooth_field((H, W), seg.px(5), seed) > 0.5)
    out[light, :3] = MOSS
    hl = m & ~np.roll(m, seg.px(5), axis=0) & ~np.roll(m, seg.px(4), axis=1)
    out[hl, :3] = np.clip(MOSS * 1.25, 0, 1)
    out[m, 3] = 1.0
    return outline_shape(out, m, m, seg.px(3))


# --- category effects ------------------------------------------------------------

def vegetation_state(a, seg, state, seed):
    """Trees and bushes: dry, dead, burnt, snow."""
    rng = np.random.default_rng(seed)
    hsv = rgb_to_hsv(a[..., :3])
    green = seg.inner & (hsv[..., 0] > 0.12) & (hsv[..., 0] < 0.45) & (hsv[..., 1] > 0.25)
    trunk = seg.inner & ~green
    out = a.copy()
    if not green.any():
        # bare trees (Penzilla BareTree*) have no foliage: only burnt / snow apply
        if state == "verbrannt":
            return char(a, seg, 0.9)
        if state == "schnee":
            return snow_cap(a, seg, 1.0, seed)
        return out
    if state == "trocken":
        hsv[green, 0] = hsv[green, 0] * 0.55 + 0.02
        hsv[green, 1] *= 0.85
        out[..., :3] = np.where(green[..., None], hsv_to_rgb(hsv), a[..., :3])
    elif state in ("abgestorben", "verbrannt"):
        dead_col = np.array([0.50, 0.42, 0.33], np.float32) if state == "abgestorben" else np.array([0.16, 0.13, 0.14], np.float32)
        out[green, :3] = dead_col * (0.75 + 0.35 * seg.lum[green, None] / max(seg.lum[green].max(), 1e-6))
        # thinned crown: holes cut into the foliage, outlined
        f = smooth_field(seg.opaque.shape, max(3, int(seg.h * 0.05)), seed)
        holes = green & (f > (0.62 if state == "abgestorben" else 0.55))
        holes = ndimage.binary_opening(holes, iterations=max(1, int(seg.h * 0.012)))
        out[holes] = 0.0
        remaining = green & ~holes
        ring = ndimage.binary_dilation(holes, iterations=max(2, int(seg.h * 0.018))) & remaining
        out[ring, :3] = OUTLINE
        if state == "verbrannt":
            out[trunk & ~seg.outline, :3] = out[trunk & ~seg.outline, :3] * 0.35
    elif state == "schnee":
        out = snow_cap(a, seg, 1.0, seed)
    return out


def snow_cap(a, seg, level, seed):
    """Snow on every upward-facing surface (first opaque rows from above)."""
    H, W = seg.opaque.shape
    rng = np.random.default_rng(seed)
    thick = max(seg.px(16), seg.h * 0.07, 8) * level
    wav = ndimage.gaussian_filter1d(rng.normal(0, 1, W), seg.px(5))
    wav = wav / max(np.abs(wav).max(), 1e-6) * seg.px(5)
    # distance below the nearest "sky" pixel above (transparent or outline top)
    above_free = np.zeros((H, W), np.float32)
    run = np.zeros(W, np.float32)
    for y in range(H):
        row_in = seg.inner[y]
        run = np.where(row_in, run + 1, 0)
        above_free[y] = run
    m = seg.inner & (above_free > 0) & (above_free < thick + wav[None, :])
    m = ndimage.binary_opening(m, iterations=1 if seg.h < 220 else max(2, seg.px(3)))
    out = a.copy()
    out[m, :3] = SNOW
    lower = m & ~np.roll(m, -seg.px(3), axis=0)
    out[lower, :3] = SNOW_SHADE
    return out


def top_face(seg):
    """Isometric top face of a ground tile (diamond, 2:1), wherever the tile
    has its top in the canvas. Side bands below stay untouched."""
    H, W = seg.opaque.shape
    x0, y0, x1, y1 = seg.bbox
    half_w = (x1 - x0) / 2.0
    half_h = half_w * 292.0 / 512.0
    cy = y0 + half_h
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.abs(xx - (x0 + half_w)) / half_w + np.abs(yy - cy) / half_h
    return (d <= 1.0) & seg.opaque


def surface_state(a, seg, state, seed, region=None):
    """Ground/road tiles: dirty, cracks, potholes, puddles, mud, snow, frost."""
    rng = np.random.default_rng(seed)
    H, W = seg.opaque.shape
    if region is None:
        region = top_face(seg)
    out = a.copy()
    if state == "verschmutzt":
        return dirt(a, seg, 0.55, seed, region=region, drips=False)
    if state == "rissig":
        return cracks(a, seg, 7, seed, region=region & ~seg.outline)
    if state in ("schlagloecher", "pfuetzen", "schlamm"):
        for i in range(rng.integers(3, 6) if state != "schlamm" else 6):
            ys, xs = np.nonzero(ndimage.binary_erosion(region, iterations=seg.px(40)))
            if len(xs) == 0:
                break
            k = rng.integers(0, len(xs))
            cx, cy = xs[k], ys[k]
            r = seg.px(rng.uniform(26, 46) if state != "schlamm" else rng.uniform(40, 70))
            img = Image.new("L", (W, H), 0)
            ImageDraw.Draw(img).polygon(_jagged_polygon(rng, cx, cy, r, r * 0.5, 14, 0.25), fill=255)
            m = (np.asarray(img) > 0) & region
            if state == "schlagloecher":
                out[m, :3] = out[m, :3] * 0.45 + INTERIOR * 0.3
                lip = m & ~np.roll(m, seg.px(6), axis=0)
                out[lip, :3] = np.clip(a[lip, :3] * 1.12, 0, 1)
                out = outline_shape(out, m, m, seg.px(3))
            elif state == "pfuetzen":
                out[m, :3] = WATER
                sh = m & np.roll(ndimage.binary_erosion(m, iterations=seg.px(6)), -seg.px(4), axis=1)
                hi = sh & (np.arange(H)[:, None] < cy)
                out[hi, :3] = np.clip(WATER * 1.35, 0, 1)
                out = outline_shape(out, m, m, seg.px(2))
            else:
                out[m, :3] = MUD * rng.uniform(0.85, 1.05)
                out = outline_shape(out, m, m, seg.px(2))
        return out
    if state == "schnee":
        f = smooth_field((H, W), seg.px(14), seed)
        m = (f > 0.32) & region
        out[m, :3] = SNOW
        rim = edge_of(m, seg.px(3))
        out[rim, :3] = SNOW_SHADE
        return out
    if state == "frost":
        # light icy tint over the whole surface + a few larger crystals
        out[region, :3] = out[region, :3] * 0.72 + SNOW_SHADE * 0.28
        f = smooth_field((H, W), seg.px(9), seed)
        m = (f > 0.8) & region & ~seg.outline
        out[m, :3] = out[m, :3] * 0.4 + SNOW * 0.6
        return out
    return out


def rust(a, seg, level, seed):
    """Rust on grey/metal parts: flat orange-brown spots near edges."""
    metal = seg.inner & ~seg.glass
    edge_w = max(2, int(max(seg.h, seg.w) * 0.03))
    near_edge = ndimage.binary_dilation(seg.outline, iterations=edge_w) & metal
    f = smooth_field(seg.opaque.shape, max(2, int(max(seg.h, seg.w) * 0.012)), seed)
    m = ((f > 1.0 - level * 0.4) & metal) | ((f > 0.8 - level * 0.45) & near_edge)
    m = ndimage.binary_opening(m, iterations=1)
    out = a.copy()
    out[m, :3] = np.where((f[m] > 0.7)[:, None], RUST_DARK, RUST)
    return out


def break_off(a, seg, seed, side=None):
    """Breaks a chunk off one side along a jagged, splintered line; the
    broken piece lies on the ground below (outlined)."""
    rng = np.random.default_rng(seed)
    H, W = seg.opaque.shape
    x0, y0, x1, y1 = seg.bbox
    side = side or ("left" if rng.random() < 0.5 else "right")
    ys = np.arange(H)
    cut_x = x0 + seg.w * (0.38 if side == "left" else 0.62)
    slope = rng.uniform(0.25, 0.55) * (1 if side == "left" else -1)
    line = cut_x + (ys - y0) * slope * seg.w / max(seg.h, 1)
    # triangle wave = clean zigzag break (period ~14 % of the height)
    period = max(4.0, seg.h * 0.14)
    tri = np.abs(((ys - y0) / period) % 2.0 - 1.0) * 2.0 - 1.0
    line = line + tri * seg.w * 0.07 * rng.uniform(0.7, 1.0)
    remove = (np.arange(W)[None, :] < line[:, None]) if side == "left" else (np.arange(W)[None, :] > line[:, None])
    remove &= (ys[:, None] < y0 + seg.h * 0.72)
    piece = seg.opaque & remove
    out = a.copy()
    out[remove] = 0.0
    kept = seg.opaque & ~remove
    w = max(2, int(max(seg.h, seg.w) * 0.02))
    edge = kept & ndimage.binary_dilation(piece, iterations=w)
    out[edge, :3] = OUTLINE
    # the fallen piece: rotated by 90°, squashed, lying at the base
    if piece.any():
        pys, pxs = np.nonzero(piece)
        crop = a[pys.min():pys.max() + 1, pxs.min():pxs.max() + 1].copy()
        crop[~piece[pys.min():pys.max() + 1, pxs.min():pxs.max() + 1]] = 0
        img = to_image(crop).rotate(90 if side == "left" else -90, expand=True)
        img = img.resize((max(1, img.width), max(1, int(img.height * 0.55))), Image.LANCZOS)
        layer = to_image(out)
        px = int(x0 - img.width * 0.35) if side == "left" else int(x1 - img.width * 0.65)
        py = int(y1 - img.height)
        layer.alpha_composite(img, (max(4, min(W - img.width - 4, px)), max(4, min(H - img.height - 4, py))))
        out = np.asarray(layer).astype(np.float32) / 255.0
    return out


def topple(a, seg, seed):
    """Knocked over: slim objects (lamp, hydrant, sign) lie on the ground,
    rotated around their base and squashed 2:1 for the isometric floor."""
    rng = np.random.default_rng(seed)
    H, W = seg.opaque.shape
    x0, y0, x1, y1 = seg.bbox
    spr = to_image(a).crop((x0, y0, x1, y1))
    ang = 78 * (1 if rng.random() < 0.5 else -1)
    rot = spr.rotate(ang, expand=True, resample=Image.BICUBIC)
    rot = rot.resize((rot.width, max(1, int(rot.height * 0.62))), Image.LANCZOS)
    cw = max(W, rot.width + 4)
    cw += (cw - W) % 4  # symmetric growth, even per side (exact at file scale 0.5)
    canvas = Image.new("RGBA", (cw, H), (0, 0, 0, 0))
    cx = (x0 + x1) // 2 + (canvas.width - W) // 2
    canvas.alpha_composite(rot, (max(0, min(canvas.width - rot.width, cx - rot.width // 2)), max(0, y1 - rot.height)))
    # The canvas grows symmetrically; the anchor (bottom centre) is unchanged,
    # so the variant still drops in at the same position in Godot.
    return np.asarray(canvas).astype(np.float32) / 255.0


def pixel_state(a, state, seed):
    """Pixel-art interior items (16 px): worn, dirty, broken, burnt.
    Works per pixel without smoothing so the pixel grid stays intact."""
    rng = np.random.default_rng(seed)
    op = a[..., 3] > 0.5
    lumv = lum(a[..., :3])
    outl = op & (lumv < 0.22)
    inner = op & ~outl
    out = a.copy()
    hsv = rgb_to_hsv(a[..., :3])
    if state == "abgenutzt":
        hsv[inner, 1] *= 0.75
        hsv[inner, 2] *= 0.9
        out[..., :3] = np.where(inner[..., None], hsv_to_rgb(hsv), a[..., :3])
    elif state == "verschmutzt":
        r = rng.random(op.shape)
        m = inner & (r < 0.14)
        out[m, :3] *= 0.72
    elif state == "kaputt":
        ys, xs = np.nonzero(inner)
        if len(xs):
            # 1) a crack: a pixel line in outline colour across the item
            k = rng.integers(0, len(xs))
            cx, cy = xs[k], ys[k]
            for i in range(max(6, int(math.sqrt(len(xs))) )):
                cx += rng.integers(-1, 2)
                cy += 1 if rng.random() < 0.7 else 0
                if 0 <= cy < op.shape[0] and 0 <= cx < op.shape[1] and inner[cy, cx]:
                    out[cy, cx, :3] = OUTLINE
            # 2) a chipped corner: a few pixels missing, new edge outlined
            ox, oy = (xs.min(), ys.min()) if rng.random() < 0.5 else (xs.max(), ys.min())
            r = max(2, int(math.sqrt(len(xs)) * 0.18))
            yy, xx = np.mgrid[0:op.shape[0], 0:op.shape[1]]
            chip = op & ((np.abs(xx - ox) + np.abs(yy - oy)) <= r)
            out[chip] = 0.0
            rim = ndimage.binary_dilation(chip, iterations=1) & op & ~chip
            out[rim, :3] = OUTLINE
        hsv[inner, 2] *= 0.88
        out[..., :3] = np.where(inner[..., None] & (out[..., :3] != OUTLINE).any(-1, keepdims=True), hsv_to_rgb(hsv), out[..., :3])
    elif state == "verbrannt":
        hsv[inner, 1] *= 0.15
        hsv[inner, 2] = hsv[inner, 2] * 0.35 + 0.03
        out[..., :3] = np.where(inner[..., None], hsv_to_rgb(hsv), a[..., :3])
    return out


# --- state recipes ------------------------------------------------------------------

BUILDING_STATES = [
    ("01_neu", "Neu"), ("02_gepflegt", "Gepflegt"), ("03_benutzt", "Normal benutzt"), ("04_leicht_verschmutzt", "Leicht verschmutzt"),
    ("05_vernachlaessigt", "Vernachlässigt"), ("06_heruntergekommen", "Stark heruntergekommen"), ("07_beschaedigt", "Beschädigt"),
    ("08_schwer_beschaedigt", "Schwer beschädigt"), ("09_ausgebrannt", "Ausgebrannt"), ("10_zerstoert", "Zerstört"),
    ("11_ruine", "Ruine"), ("12_restauriert", "Restauriert"),
]


def building_state(a, state, seed=1):
    seg = Seg(a)
    s = state
    if s == "01_neu":
        return fresh(a, seg)
    if s == "02_gepflegt":
        return a.copy()
    if s == "03_benutzt":
        return dirt(a, seg, 0.22, seed)
    if s == "04_leicht_verschmutzt":
        return dirt(a, seg, 0.38, seed)
    if s == "05_vernachlaessigt":
        o = desaturate(a, seg, 0.18, 0.04)
        o = dirt(o, seg, 0.5, seed)
        return peel(o, seg, 0.45, seed)
    if s == "06_heruntergekommen":
        o = desaturate(a, seg, 0.32, 0.08)
        o = dirt(o, seg, 0.66, seed)
        o = peel(o, seg, 0.7, seed)
        o = cracks(o, seg, 3, seed)
        o = broken_windows(o, seg, 0.35, seed)
        return roof_holes(o, seg, 1, seed)
    if s == "07_beschaedigt":
        o = dirt(a, seg, 0.34, seed)
        o = cracks(o, seg, 6, seed + 1)
        o = broken_windows(o, seg, 0.6, seed)
        return roof_holes(o, seg, 2, seed)
    if s == "08_schwer_beschaedigt":
        o = desaturate(a, seg, 0.2, 0.05)
        o = dirt(o, seg, 0.45, seed)
        o = cracks(o, seg, 8, seed + 2)
        o = broken_windows(o, seg, 1.0, seed)
        o = roof_holes(o, seg, 3, seed)
        return collapse(o, Seg(o), 0.42, seed, side=1)
    if s == "09_ausgebrannt":
        o = broken_windows(a, seg, 1.0, seed)
        o = char(o, seg, 0.85)
        o = roof_holes(o, Seg(o), 4, seed)
        return soot(o, seg, 0.9, seed)
    if s == "10_zerstoert":
        o = char(a, seg, 0.55)
        o = broken_windows(o, Seg(o), 1.0, seed)
        return collapse(o, Seg(o), 0.5, seed)
    if s == "11_ruine":
        o = desaturate(a, seg, 0.55, 0.1)
        o = dirt(o, seg, 0.55, seed)
        o = broken_windows(o, Seg(o), 1.0, seed)
        o = collapse(o, Seg(o), 0.55, seed + 5, rubble=False)
        return overgrowth(o, Seg(o), 0.7, seed)
    if s == "12_restauriert":
        o = fresh(a, seg)
        # visibly repaired: fresh plaster patches in a slightly different tone
        f = smooth_field(seg.opaque.shape, seg.px(9), seed + 11)
        m = (f > 0.78) & seg.facade & ~ndimage.binary_dilation(seg.outline, iterations=seg.px(4))
        hsv = rgb_to_hsv(o[..., :3])
        hsv[m, 2] = np.clip(hsv[m, 2] * 1.08, 0, 1)
        hsv[m, 1] *= 0.9
        o[..., :3] = np.where(m[..., None], hsv_to_rgb(hsv), o[..., :3])
        return o
    raise ValueError(state)


# --- recipes for the other categories (samples, step C) ---------------------------

VEGETATION_STATES = [("gesund", "Gesund/gepflegt"), ("normal", "Normal"), ("trocken", "Trocken"), ("abgestorben", "Abgestorben"), ("verbrannt", "Verbrannt"), ("schnee", "Schnee")]
SURFACE_STATES = [("normal", "Normal"), ("verschmutzt", "Verschmutzt"), ("rissig", "Risse"), ("schlagloecher", "Schlaglöcher"), ("pfuetzen", "Pfützen"), ("schlamm", "Schlamm"), ("schnee", "Schnee"), ("frost", "Frost")]
FURNITURE_STATES = [("neu", "Neu"), ("normal", "Normal"), ("verwittert", "Verwittert"), ("rostig", "Rostig"), ("beschaedigt", "Beschädigt"), ("zerstoert", "Zerstört")]
VEHICLE_STATES = [("normal", "Normal"), ("verschmutzt", "Verschmutzt"), ("verlassen", "Verlassen"), ("ausgebrannt", "Ausgebrannt"), ("wrack", "Wrack")]
INTERIOR_STATES = [("normal", "Normal"), ("abgenutzt", "Abgenutzt"), ("verschmutzt", "Verschmutzt"), ("kaputt", "Kaputt"), ("verbrannt", "Verbrannt")]


def vegetation(a, state, seed=1):
    seg = Seg(a)
    if state == "gesund":
        return fresh(a, seg)
    if state == "normal":
        return a.copy()
    return vegetation_state(a, seg, state, seed)


def surface(a, state, seed=1):
    seg = Seg(a)
    if state == "normal":
        return a.copy()
    return surface_state(a, seg, state, seed)


def furniture(a, state, seed=1):
    seg = Seg(a)
    if state == "neu":
        return fresh(a, seg)
    if state == "normal":
        return a.copy()
    if state == "verwittert":
        o = desaturate(a, seg, 0.3, 0.05)
        return dirt(o, seg, 0.45, seed, region=seg.inner, drips=False)
    if state == "rostig":
        o = desaturate(a, seg, 0.2)
        return rust(o, seg, 0.65, seed)
    if state == "beschaedigt":
        o = rust(a, seg, 0.4, seed)
        o = broken_windows(o, seg, 1.0, seed)
        return cracks(o, Seg(o), 2, seed, region=seg.inner)
    if state == "zerstoert":
        o = rust(a, seg, 0.5, seed)
        o = broken_windows(o, seg, 1.0, seed)
        if seg.h > seg.w * 1.3:
            o = topple(o, Seg(o), seed)   # slim objects fall over
        else:
            o = break_off(o, Seg(o), seed)  # wide objects break apart
        return char(o, Seg(o), 0.3)
    raise ValueError(state)


def vehicle(a, state, seed=1):
    seg = Seg(a)
    if state == "normal":
        return a.copy()
    if state == "verschmutzt":
        return dirt(a, seg, 0.5, seed, region=seg.inner & ~seg.glass, drips=False)
    if state == "verlassen":
        o = desaturate(a, seg, 0.45, 0.06)
        o = dirt(o, seg, 0.55, seed, region=seg.inner & ~seg.glass, drips=False)
        o = rust(o, Seg(o), 0.55, seed)
        return broken_windows(o, seg, 0.5, seed)
    if state in ("ausgebrannt", "wrack"):
        o = broken_windows(a, seg, 1.0, seed)
        o = char(o, seg, 0.9)
        o = rust(o, Seg(o), 0.4, seed)
        if state == "wrack":
            o = collapse(o, Seg(o), 0.25, seed, rubble=False, side=-1)
        return o
    raise ValueError(state)


def interior(a, state, seed=1):
    if state == "normal":
        return a.copy()
    return pixel_state(a, state, seed)
