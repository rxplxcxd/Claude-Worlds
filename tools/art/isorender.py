"""Own isometric renderer for WORLDS monument art in the Penzilla look.

Why: the World Council is far bigger and more ornate than any building in
the Penzilla packs, so it is built from solids (boxes, prisms, cylinders,
ellipsoids, CSG cut-outs) and drawn with the Penzilla rules instead of being
painted by hand:
  * same camera as the Penzilla City Builder tiles (diamond 512 x 292 px,
    i.e. elevation asin(292/512) = 34.8 deg, azimuth 45 deg, orthographic),
  * flat colours, three tones per material (top / left face / right face),
    curved surfaces quantised into bands,
  * thick dark-plum contour around every part, thinner lines at creases,
  * procedural surface detail (stone courses, paving, fluting, roof tiles,
    water ripples, foliage blobs, weathering, ivy).

Pure numpy/scipy, no external programs. Rays are parallel (orthographic), so
every solid is intersected analytically over its own screen rectangle only.

Coordinates: metres. X -> screen right-down, Y -> screen left-down, Z up.
"""
from __future__ import annotations

import math
import numpy as np
from scipy import ndimage

SIN_PHI = 292.0 / 512.0
PHI = math.asin(SIN_PHI)
COS_PHI = math.cos(PHI)
R2 = 1.0 / math.sqrt(2.0)
# camera basis
RIGHT = np.array([R2, -R2, 0.0])
UP = np.array([-SIN_PHI * R2, -SIN_PHI * R2, COS_PHI])
VIEW = np.array([-COS_PHI * R2, -COS_PHI * R2, -SIN_PHI])  # into the scene
LIGHT = np.array([0.35, 0.7, 1.0]) / np.linalg.norm([0.35, 0.7, 1.0])
INK = np.array([0x2b, 0x0f, 0x2a]) / 255.0
EPS = 1e-9


def hexc(h: str) -> np.ndarray:
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)]) / 255.0


# ---------------------------------------------------------------- solids

class Solid:
    """Convex solid = optional quadric (cylinder/ellipsoid) ∩ half-spaces,
    minus a list of convex cutters. `part` groups solids that are outlined
    as one piece; `mat` names the material."""

    def __init__(self, planes=(), quad=None, mat='marble', part=None, cuts=(), aabb=None, data=None):
        self.planes = [(np.asarray(n, float) / np.linalg.norm(n), float(d) / np.linalg.norm(n)) for n, d in planes]
        self.quad = quad
        self.mat = mat
        self.part = part
        self.cuts = list(cuts)
        self.aabb = aabb
        self.data = data or {}

    # interval of the convex body along rays o + t*VIEW
    def interval(self, o):
        n_rays = o.shape[0]
        t0 = np.full(n_rays, -np.inf)
        t1 = np.full(n_rays, np.inf)
        n0 = np.zeros((n_rays, 3))
        n1 = np.zeros((n_rays, 3))
        for n, d in self.planes:
            dn = float(n @ VIEW)
            on = o @ n
            if dn < -EPS:
                t = (d - on) / dn
                m = t > t0
                t0 = np.where(m, t, t0)
                n0[m] = n
            elif dn > EPS:
                t = (d - on) / dn
                m = t < t1
                t1 = np.where(m, t, t1)
                n1[m] = -n
            else:
                bad = on > d
                t0[bad] = np.inf
        if self.quad is not None:
            qa, qb, qn0, qn1 = self._quad(o)
            m = qa > t0
            t0 = np.where(m, qa, t0)
            n0[m] = qn0[m]
            m = qb < t1
            t1 = np.where(m, qb, t1)
            n1[m] = qn1[m]
        return t0, t1, n0, n1

    def _quad(self, o):
        kind = self.quad[0]
        if kind == 'cyl':
            _, ax, c, r = self.quad
            c = np.asarray(c, float)
            idx = [i for i in range(3) if i != ax]
            d0 = o[:, idx[0]] - c[idx[0]]
            d1 = o[:, idx[1]] - c[idx[1]]
            v0, v1 = VIEW[idx[0]], VIEW[idx[1]]
            a = v0 * v0 + v1 * v1
            b = 2.0 * (d0 * v0 + d1 * v1)
            cc = d0 * d0 + d1 * d1 - r * r
            if a < EPS:
                inside = cc <= 0
                ta = np.where(inside, -np.inf, np.inf)
                tb = np.where(inside, np.inf, -np.inf)
                z = np.zeros((o.shape[0], 3))
                return ta, tb, z, z
            disc = b * b - 4 * a * cc
            ok = disc >= 0
            sq = np.sqrt(np.where(ok, disc, 0))
            ta = np.where(ok, (-b - sq) / (2 * a), np.inf)
            tb = np.where(ok, (-b + sq) / (2 * a), -np.inf)
            na = np.zeros((o.shape[0], 3))
            nb = np.zeros((o.shape[0], 3))
            na[:, idx[0]] = (d0 + ta * v0) / r
            na[:, idx[1]] = (d1 + ta * v1) / r
            nb[:, idx[0]] = -(d0 + tb * v0) / r
            nb[:, idx[1]] = -(d1 + tb * v1) / r
            na[~ok] = 0
            nb[~ok] = 0
            return ta, tb, na, nb
        # ellipsoid
        _, c, rad = self.quad
        c = np.asarray(c, float)
        rad = np.asarray(rad, float)
        q = (o - c) / rad
        w = VIEW / rad
        a = float(w @ w)
        b = 2.0 * (q @ w)
        cc = (q * q).sum(1) - 1.0
        disc = b * b - 4 * a * cc
        ok = disc >= 0
        sq = np.sqrt(np.where(ok, disc, 0))
        ta = np.where(ok, (-b - sq) / (2 * a), np.inf)
        tb = np.where(ok, (-b + sq) / (2 * a), -np.inf)
        pa = o + ta[:, None] * VIEW - c
        pb = o + tb[:, None] * VIEW - c
        na = pa / (rad * rad)
        nb = -pb / (rad * rad)
        na /= np.maximum(np.linalg.norm(na, axis=1, keepdims=True), EPS)
        nb /= np.maximum(np.linalg.norm(nb, axis=1, keepdims=True), EPS)
        return ta, tb, na, nb

    def hit(self, o):
        t0, t1, n0, _ = self.interval(o)
        hit = t0 < t1
        t = np.where(hit, t0, np.inf)
        n = n0.copy()
        cut_flag = np.zeros(o.shape[0], np.int8)
        if self.cuts and hit.any():
            ivs = [c.interval(o) for c in self.cuts]
            for _ in range(4):
                moved = np.zeros(o.shape[0], bool)
                for ci, (c0, c1, _, cn1) in enumerate(ivs):
                    inside = hit & (c0 <= t) & (t < c1)
                    if inside.any():
                        t = np.where(inside, c1, t)
                        n[inside] = cn1[inside]
                        cut_flag[inside] = 2 if self.cuts[ci].data.get('niche') else 1
                        moved |= inside
                if not moved.any():
                    break
            gone = t >= t1
            t[gone] = np.inf
        return t, n, cut_flag

    def bounds(self):
        return self.aabb


# ---------------------------------------------------------------- builders

def box(x0, y0, z0, x1, y1, z1, mat='marble', part=None, cuts=(), data=None):
    planes = [((1, 0, 0), x1), ((-1, 0, 0), -x0), ((0, 1, 0), y1), ((0, -1, 0), -y0), ((0, 0, 1), z1), ((0, 0, -1), -z0)]
    return Solid(planes, None, mat, part, cuts, (np.array([x0, y0, z0]), np.array([x1, y1, z1])), data)


def cyl(cx, cy, z0, z1, r, mat='marble', part=None, cuts=(), extra_planes=(), data=None):
    planes = [((0, 0, 1), z1), ((0, 0, -1), -z0)] + list(extra_planes)
    return Solid(planes, ('cyl', 2, (cx, cy, 0), r), mat, part, cuts,
                 (np.array([cx - r, cy - r, z0]), np.array([cx + r, cy + r, z1])), data)


def hcyl(axis, a0, a1, c1, c2, r, mat='marble', part=None, cuts=(), extra_planes=()):
    """Horizontal cylinder along 'x' or 'y' from a0 to a1, centre (c1 = other
    horizontal coordinate, c2 = z)."""
    if axis == 'x':
        planes = [((1, 0, 0), a1), ((-1, 0, 0), -a0)] + list(extra_planes)
        return Solid(planes, ('cyl', 0, (0, c1, c2), r), mat, part, cuts,
                     (np.array([a0, c1 - r, c2 - r]), np.array([a1, c1 + r, c2 + r])))
    planes = [((0, 1, 0), a1), ((0, -1, 0), -a0)] + list(extra_planes)
    return Solid(planes, ('cyl', 1, (c1, 0, c2), r), mat, part, cuts,
                 (np.array([c1 - r, a0, c2 - r]), np.array([c1 + r, a1, c2 + r])))


def ell(cx, cy, cz, rx, ry, rz, mat='foliage', part=None, zmin=None, cuts=(), data=None):
    planes = [((0, 0, -1), -zmin)] if zmin is not None else []
    z0 = cz - rz if zmin is None else max(zmin, cz - rz)
    return Solid(planes, ('ell', (cx, cy, cz), (rx, ry, rz)), mat, part, cuts,
                 (np.array([cx - rx, cy - ry, z0]), np.array([cx + rx, cy + ry, cz + rz])), data)


def prism_gable(x0, y0, x1, y1, z0, z1, ridge_axis, mat='roof', part=None, cuts=()):
    """Gable roof / pediment: triangle cross-section, ridge along ridge_axis."""
    h = z1 - z0
    if ridge_axis == 'x':
        w = (y1 - y0) / 2.0
        yc = (y0 + y1) / 2.0
        planes = [((1, 0, 0), x1), ((-1, 0, 0), -x0), ((0, 0, -1), -z0),
                  ((0, h, w), h * yc + w * z1), ((0, -h, w), -h * yc + w * z1)]
    else:
        w = (x1 - x0) / 2.0
        xc = (x0 + x1) / 2.0
        planes = [((0, 1, 0), y1), ((0, -1, 0), -y0), ((0, 0, -1), -z0),
                  ((h, 0, w), h * xc + w * z1), ((-h, 0, w), -h * xc + w * z1)]
    return Solid(planes, None, mat, part, cuts, (np.array([x0, y0, z0]), np.array([x1, y1, z1])))


def ngon_prism(cx, cy, z0, z1, r, n, mat='marble', part=None, rot=0.0, cuts=()):
    planes = [((0, 0, 1), z1), ((0, 0, -1), -z0)]
    for k in range(n):
        a = rot + 2 * math.pi * k / n
        planes.append(((math.cos(a), math.sin(a), 0), cx * math.cos(a) + cy * math.sin(a) + r))
    return Solid(planes, None, mat, part, cuts, (np.array([cx - r * 1.1, cy - r * 1.1, z0]), np.array([cx + r * 1.1, cy + r * 1.1, z1])))


def oriented_box(cx, cy, z0, z1, half_len, half_w, ang, mat='marble', part=None, cuts=()):
    """Box rotated about z by ang (radians)."""
    ca, sa = math.cos(ang), math.sin(ang)
    u = (ca, sa, 0)
    w = (-sa, ca, 0)
    cu = cx * ca + cy * sa
    cw = -cx * sa + cy * ca
    planes = [(u, cu + half_len), ((-ca, -sa, 0), -(cu - half_len)), (w, cw + half_w), ((sa, -ca, 0), -(cw - half_w)),
              ((0, 0, 1), z1), ((0, 0, -1), -z0)]
    r = math.hypot(half_len, half_w)
    return Solid(planes, None, mat, part, cuts, (np.array([cx - r, cy - r, z0]), np.array([cx + r, cy + r, z1])))


# ---------------------------------------------------------------- noise

def _hash3(ix, iy, iz, seed=0):
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 1442695041) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def vnoise(p, scale, seed=0):
    """Smooth 3D value noise 0..1 for points p (N,3)."""
    q = p / scale
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out = out + w * _hash3(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm(p, scale, seed=0, octaves=3):
    tot = 0.0
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        tot = tot + amp * vnoise(p, scale / (2 ** o), seed + o * 17)
        norm += amp
        amp *= 0.5
    return tot / norm


# ---------------------------------------------------------------- renderer

class Scene:
    def __init__(self):
        self.solids: list[Solid] = []
        self.parts = {}

    def add(self, *ss):
        for s in ss:
            if isinstance(s, (list, tuple)):
                self.add(*s)
            else:
                if s.part is None:
                    s.part = f"p{len(self.solids)}"
                self.solids.append(s)

    def screen_bounds(self):
        mins, maxs = [], []
        for s in self.solids:
            a, b = s.aabb
            corners = np.array([[x, y, z] for x in (a[0], b[0]) for y in (a[1], b[1]) for z in (a[2], b[2])])
            sx = corners @ RIGHT
            sy = corners @ UP
            mins.append((sx.min(), sy.min()))
            maxs.append((sx.max(), sy.max()))
        mins = np.array(mins)
        maxs = np.array(maxs)
        return mins[:, 0].min(), mins[:, 1].min(), maxs[:, 0].max(), maxs[:, 1].max()


def render(scene: Scene, materials: dict, px_per_m: float, ss: int = 2, tile: int = 1024,
           line_px=(1.8, 1.4, 0.9), shade_fn=None, frame=None, log=print):
    """Returns RGBA float image (H, W, 4) at px_per_m (after supersampling)
    plus buffers {depth, part, mat, pos, normal} at final resolution for
    later splitting. frame = (sx0, sy0, sx1, sy1) in metres (screen space)."""
    s = px_per_m * ss
    sx0, sy0, sx1, sy1 = frame if frame else scene.screen_bounds()
    pad = 2.0
    sx0 -= pad; sy0 -= pad; sx1 += pad; sy1 += pad
    W = int(math.ceil((sx1 - sx0) * s))
    H = int(math.ceil((sy1 - sy0) * s))
    W += (-W) % ss
    H += (-H) % ss
    log(f"render {W // ss}x{H // ss} (ss {ss}), {len(scene.solids)} solids")
    depth = np.full((H, W), np.inf, np.float32)
    normal = np.zeros((H, W, 3), np.float32)
    part = np.full((H, W), -1, np.int32)
    matid = np.full((H, W), -1, np.int16)
    cutf = np.zeros((H, W), np.int8)
    mat_names = list(materials.keys())
    mat_index = {m: i for i, m in enumerate(mat_names)}
    part_index = {}
    # screen rects of solids
    rects = []
    for so in scene.solids:
        a, b = so.aabb
        corners = np.array([[x, y, z] for x in (a[0], b[0]) for y in (a[1], b[1]) for z in (a[2], b[2])])
        cx = (corners @ RIGHT - sx0) * s
        cy = (sy1 - corners @ UP) * s
        rects.append((int(math.floor(cx.min())) - 1, int(math.floor(cy.min())) - 1, int(math.ceil(cx.max())) + 1, int(math.ceil(cy.max())) + 1))
        part_index.setdefault(so.part, len(part_index))
    for ty in range(0, H, tile):
        for tx in range(0, W, tile):
            tx1, ty1 = min(W, tx + tile), min(H, ty + tile)
            for k, so in enumerate(scene.solids):
                r = rects[k]
                x0, y0, x1, y1 = max(r[0], tx), max(r[1], ty), min(r[2], tx1), min(r[3], ty1)
                if x0 >= x1 or y0 >= y1:
                    continue
                cols = np.arange(x0, x1)
                rows = np.arange(y0, y1)
                cc, rr = np.meshgrid(cols, rows)
                u = (cc.ravel() + 0.5) / s + sx0
                v = sy1 - (rr.ravel() + 0.5) / s
                o = u[:, None] * RIGHT + v[:, None] * UP - VIEW * 2000.0
                t, n, cf = so.hit(o)
                sub = depth[y0:y1, x0:x1].ravel()
                closer = t < sub
                if not closer.any():
                    continue
                t = t.astype(np.float32)
                dsub = depth[y0:y1, x0:x1]
                m2 = closer.reshape(dsub.shape)
                dsub[m2] = t[closer]
                normal[y0:y1, x0:x1][m2] = n[closer]
                part[y0:y1, x0:x1][m2] = part_index[so.part]
                matid[y0:y1, x0:x1][m2] = mat_index[so.mat]
                cutf[y0:y1, x0:x1][m2] = cf[closer]
    log("geometry done")
    hit = np.isfinite(depth)
    # world positions
    rr, cc = np.nonzero(hit)
    u = (cc + 0.5) / s + sx0
    v = sy1 - (rr + 0.5) / s
    pos = u[:, None] * RIGHT + v[:, None] * UP - VIEW * 2000.0 + depth[rr, cc][:, None] * VIEW
    nrm = normal[rr, cc].astype(float)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), EPS)
    mids = matid[rr, cc]
    color = np.zeros((len(rr), 3))
    for name, mi in mat_index.items():
        sel = mids == mi
        if not sel.any():
            continue
        color[sel] = materials[name](pos[sel], nrm[sel], cutf[rr, cc][sel])
    if shade_fn:
        color = shade_fn(pos, nrm, color, mids, mat_names)
    img = np.zeros((H, W, 4), np.float32)
    img[rr, cc, :3] = np.clip(color, 0, 1)
    img[rr, cc, 3] = 1.0
    # ----- outlines
    lw_sil, lw_part, lw_crease = [w * ss for w in line_px]
    big = np.where(hit, depth, 1e9)
    sil = np.zeros((H, W), bool)
    partl = np.zeros((H, W), bool)
    crease = np.zeros((H, W), bool)
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        a = (slice(0, H - dy), slice(max(0, -dx), W - max(0, dx)))
        b = (slice(dy, H), slice(max(0, dx), W - max(0, -dx)))
        ha, hb = hit[a], hit[b]
        # silhouette: hit next to empty -> mark the hit pixel
        sil[a] |= ha & ~hb
        sil[b] |= hb & ~ha
        both = ha & hb
        da, db = big[a], big[b]
        near_a = da <= db
        diffp = both & (part[a] != part[b])
        dz = np.abs(da - db)
        jump = both & (dz > 0.6)
        pa_mark = (diffp | jump) & near_a
        pb_mark = (diffp | jump) & ~near_a
        partl[a] |= pa_mark
        partl[b] |= pb_mark
        na_, nb_ = normal[a], normal[b]
        dot = (na_ * nb_).sum(-1) / np.maximum(np.linalg.norm(na_, axis=-1) * np.linalg.norm(nb_, axis=-1), EPS)
        cr = both & ~diffp & ~jump & (dot < 0.82)
        crease[a] |= cr & near_a
        crease[b] |= cr & ~near_a

    def dil(mask, w):
        r = max(0.5, w / 2.0)
        k = int(math.ceil(r))
        yy, xx = np.mgrid[-k:k + 1, -k:k + 1]
        disk = (xx * xx + yy * yy) <= r * r + 0.25
        return ndimage.binary_dilation(mask, structure=disk)

    ink = dil(sil, lw_sil * 2 - 1) | dil(partl, lw_part)
    # inner creases: a darker tone of the surface itself (Penzilla draws
    # small inner lines in a deep shade, the plum ink only on contours)
    soft = dil(crease, lw_crease) & ~ink
    img[soft, :3] = img[soft, :3] * 0.5 + INK * 0.22
    img[ink, :3] = INK
    img[ink, 3] = 1.0
    log("outlines done")
    # ----- downsample
    if ss > 1:
        pre = img.copy()
        pre[..., :3] *= pre[..., 3:4]
        pre = pre.reshape(H // ss, ss, W // ss, ss, 4).mean((1, 3))
        a = pre[..., 3:4]
        pre[..., :3] = np.where(a > 0, pre[..., :3] / np.maximum(a, EPS), 0)
        img = pre
        depth = depth[ss // 2::ss, ss // 2::ss]
        part = part[ss // 2::ss, ss // 2::ss]
    origin = (sx0, sy1)  # metres of the image's top-left corner (screen space)
    return img, {"depth": depth, "part": part, "part_names": list(part_index.keys()), "origin": origin, "px_per_m": px_per_m}


def save_png(img, path):
    from PIL import Image
    a = np.clip(img * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(a, 'RGBA').save(path, optimize=True)


def project(p, origin, px_per_m):
    """World metres -> image pixel (x, y) for an image rendered with origin."""
    p = np.asarray(p, float)
    return ((p @ RIGHT - origin[0]) * px_per_m, (origin[1] - p @ UP) * px_per_m)
