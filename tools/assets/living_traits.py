#!/usr/bin/env python3
"""Living Assets – combinable visual traits (step G).

A visual state is NOT one picture per named state. It is a combination of
independent traits (docs/living_assets/STATE_MATRIX.md §2):

  structure   intact | partial | shell | collapsed | ruin   -> base sprite (tier 3)
  wear        0..3   dirt/fading via shader (tier 1); 2–3 add material overlays
  damage      0..2   overlays (cracks, glass, holes, debris)           (tier 2)
  fire        0..2   overlays (soot, partly burnt)                     (tier 2)
  overgrowth  0..2   overlay (weeds, ivy, moss)                        (tier 2)
  repair      0..2   overlay "traces of the past" after a restoration  (tier 2)
  snow        0..1   overlay (weather)                                 (tier 2)

Every overlay is generated against the INTACT original and stored cropped
(only changed pixels). At runtime the composer draws base + overlays and
clips overlay pixels that fall where the base is transparent but the
original was opaque (e.g. soot on a wall that has collapsed). Pixels outside
the original silhouette (rubble, ivy on the ground) are never clipped.

All effects are material-aware (living_materials.MaterialSeg) and keep the
Penzilla style: flat colours, hard edges, #330022 outlines, own palette.
Deterministic: every effect takes a seed.
"""
import math

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

import living_states as LS
from living_materials import MaterialSeg

OUTLINE = LS.OUTLINE
INTERIOR = LS.INTERIOR
SOOT = LS.SOOT
WOOD = LS.WOOD
MOSS, MOSS_DARK = LS.MOSS, LS.MOSS_DARK
BRICK = np.array([0.66, 0.33, 0.24], np.float32)
MORTAR = np.array([0.80, 0.72, 0.62], np.float32)
WOOD_GREY = np.array([0.56, 0.53, 0.50], np.float32)
WOOD_FRESH = np.array([0.86, 0.66, 0.42], np.float32)
ROT = np.array([0.30, 0.27, 0.18], np.float32)
DUST = np.array([0.82, 0.76, 0.66], np.float32)
GRIME = LS.GRIME
BEAM_CHAR = np.array([0.15, 0.12, 0.12], np.float32)

smooth_field = LS.smooth_field
edge_of = LS.edge_of
paint = LS.paint
outline_shape = LS.outline_shape
jagged = LS._jagged_polygon


# --- small helpers -------------------------------------------------------------

def patches(seg, region, share, sigma, seed, opening=2):
    """Flat blobs covering ~`share` of `region` (quantile of a smooth field
    INSIDE the region – independent of canvas size and padding)."""
    if share <= 0 or not region.any():
        return np.zeros(seg.shape, bool)
    # minimum blob size in absolute pixels so small sprites do not get specks
    f = smooth_field(seg.shape, max(5, seg.px(sigma)), seed)
    thr = np.quantile(f[region], 1.0 - min(0.95, share))
    m = (f > thr) & region
    if opening:
        m = ndimage.binary_opening(m, iterations=max(2, seg.px(opening)))
    return m


def poly_mask(shape, pts):
    H, W = shape
    img = Image.new("L", (W, H), 0)
    ImageDraw.Draw(img).polygon([(float(x), float(y)) for x, y in pts], fill=255)
    return np.asarray(img) > 0


def lines_mask(shape, lines, width):
    H, W = shape
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    for pts in lines:
        d.line([(float(x), float(y)) for x, y in pts], fill=255, width=max(1, int(width)), joint="curve")
    return np.asarray(img) > 0


def face_slope(seg, cx):
    """Isometric face direction of a wall at x: left face rises to the left
    (+0.5 in image y per x), right face rises to the right (-0.5)."""
    mid = (seg.bbox[0] + seg.bbox[2]) / 2.0
    return 0.5 if cx < mid else -0.5


def comp_mask(seg, c):
    return c.mask(seg.shape)


def keep(seg, mask, margin=4):
    """Area of a mask away from outlines (effects never paint over contours)."""
    return mask & ~ndimage.binary_dilation(seg.outline, iterations=seg.px(margin))


def recolour(out, mask, rgb, k):
    out[mask, :3] = out[mask, :3] * (1 - k) + rgb * k
    return out


def desat(out, mask, k, lighten=0.0):
    rgb = out[mask, :3]
    g = LS.lum(rgb)[:, None]
    rgb = rgb * (1 - k) + g * k
    out[mask, :3] = np.clip(rgb + lighten, 0, 1)
    return out


def char_colours(rgb):
    l = LS.lum(rgb)[..., None]
    return LS.CHAR + l * np.array([0.42, 0.37, 0.34], np.float32)


# --- material effects: plaster / brick / stone -----------------------------------

def brick_pattern(seg, mask, slope, scale=1.0):
    """Brick courses following the isometric face direction."""
    H, W = seg.shape
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    course = seg.px(16 * scale)
    brick_len = seg.px(34 * scale)
    yp = yy - slope * xx
    row = np.floor(yp / course)
    mortar_h = (yp % course) < max(1, seg.px(3))
    xp = xx + (row % 2) * brick_len * 0.5
    mortar_v = (xp % brick_len) < max(1, seg.px(3))
    return mask & (mortar_h | mortar_v)


def peel_plaster(out, seg, level, seed):
    """Paint/plaster flakes off and the brick underneath shows (outlined)."""
    rng = np.random.default_rng(seed)
    base = keep(seg, seg.m("plaster"), 6) & ~ndimage.binary_dilation(seg.glass, iterations=seg.px(6))
    if not base.any():
        return out
    m = patches(seg, base, level * 0.2, 6, seed + 1)
    if not m.any():
        return out
    lab, n = ndimage.label(m)
    for i in range(1, n + 1):
        p = lab == i
        if p.sum() < seg.px(10) ** 2:
            m &= ~p
            continue
        ys, xs = np.nonzero(p)
        slope = face_slope(seg, xs.mean())
        out[p, :3] = BRICK * rng.uniform(0.9, 1.05)
        joints = brick_pattern(seg, p, slope)
        out[joints, :3] = MORTAR
    rim = edge_of(m, seg.px(3))
    out[rim, :3] = OUTLINE
    return out


def stains(out, seg, region, level, seed):
    """Water stains / grime runs below windows and from the roof edge."""
    H, W = seg.shape
    m = np.zeros(seg.shape, bool)
    rng = np.random.default_rng(seed)
    for c in seg.glass_components():
        if rng.random() > 0.5 + level * 0.2:
            continue
        x0, x1, y1 = c.sl[1].start, c.sl[1].stop, c.sl[0].stop
        w = (x1 - x0) * rng.uniform(0.3, 0.6)
        xc = (x0 + x1) / 2 + rng.uniform(-0.15, 0.15) * (x1 - x0)
        ln = seg.px(40) * (0.6 + level)
        m |= poly_mask(seg.shape, [(xc - w / 2, y1), (xc + w / 2, y1), (xc + w * 0.15, y1 + ln), (xc - w * 0.1, y1 + ln * 0.8)])
    m &= region
    dark = out[..., :3] * 0.72 + GRIME * 0.28
    out[m, :3] = dark[m]
    return out


def cracks_plaster(out, seg, count, seed, from_windows=True):
    """Zigzag cracks; most start at window corners (where real walls crack)."""
    rng = np.random.default_rng(seed)
    region = keep(seg, seg.m("plaster", "stone"), 3)
    if not region.any():
        return out
    starts = []
    if from_windows:
        for c in seg.glass_components():
            y0, y1, x0, x1 = c.sl[0].start, c.sl[0].stop, c.sl[1].start, c.sl[1].stop
            starts += [(x0, y0), (x1, y0), (x0, y1), (x1, y1)]
        rng.shuffle(starts)
    ys, xs = np.nonzero(region)
    lines = []
    for i in range(count):
        if i < len(starts) and rng.random() < 0.75:
            st = starts[i]
            ang = math.atan2(-1 if st[1] == starts[i][1] else 1, 1 if rng.random() < 0.5 else -1)
        else:
            k = rng.integers(0, len(xs))
            st = (float(xs[k]), float(ys[k]))
            ang = None
        main = LS._random_crack(rng, st, seg.px(140), seg.unit, ang)
        lines.append(main)
        if rng.random() < 0.6:
            j = int(rng.integers(1, len(main)))
            lines.append(LS._random_crack(rng, main[j], seg.px(60), seg.unit))
    m = lines_mask(seg.shape, lines, seg.px(6)) & region
    out[m, :3] = OUTLINE
    return out


def cracks_brick(out, seg, count, seed):
    """Stepped cracks along the mortar joints + a few knocked-out bricks."""
    rng = np.random.default_rng(seed)
    region = keep(seg, seg.m("brick"), 3)
    if not region.any():
        return out
    ys, xs = np.nonzero(region)
    course, blen = seg.px(16), seg.px(34)
    lines = []
    for i in range(count):
        k = rng.integers(0, len(xs))
        x, y = float(xs[k]), float(ys[k])
        slope = face_slope(seg, x)
        d = 1 if rng.random() < 0.5 else -1
        pts = [(x, y)]
        for s in range(int(rng.integers(4, 8))):
            x += d * blen * 0.5
            y += d * blen * 0.5 * slope
            pts.append((x, y))
            y += course
            pts.append((x, y))
        lines.append(pts)
    m = lines_mask(seg.shape, lines, seg.px(5)) & region
    out[m, :3] = OUTLINE
    out = missing_bricks(out, seg, region, int(count * 2), rng)
    return out


def missing_bricks(out, seg, region, n, rng):
    ys, xs = np.nonzero(region)
    if len(xs) == 0:
        return out
    course, blen = seg.px(16), seg.px(34)
    for i in range(n):
        k = rng.integers(0, len(xs))
        x, y = float(xs[k]), float(ys[k])
        s = face_slope(seg, x)
        pts = [(x, y), (x + blen, y + blen * s), (x + blen, y + blen * s + course), (x, y + course)]
        m = poly_mask(seg.shape, pts) & region
        out[m, :3] = INTERIOR * 0.9
        out = outline_shape(out, m, m, seg.px(2))
    return out


def chips_stone(out, seg, count, seed):
    """Angular chips knocked off stone/concrete edges."""
    rng = np.random.default_rng(seed)
    region = seg.m("stone")
    edge = region & ndimage.binary_dilation(seg.outline, iterations=seg.px(3))
    ys, xs = np.nonzero(edge)
    if len(xs) == 0:
        return out
    for i in range(count):
        k = rng.integers(0, len(xs))
        r = seg.px(rng.uniform(10, 18))
        m = poly_mask(seg.shape, jagged(rng, xs[k], ys[k], r, r * 0.7, 5, 0.3)) & region
        out[m, :3] = out[m, :3] * 0.62
        out = outline_shape(out, m, m, seg.px(2))
    return out


# --- wood ----------------------------------------------------------------------

def natural_wood(seg):
    """Unpainted wood (brown hue); other 'wood' parts are painted."""
    h, sat = seg.hsv[..., 0], seg.hsv[..., 1]
    return seg.m("wood") & (((h >= 0.02) & (h <= 0.13) & (sat > 0.2)) | (sat < 0.12))


def wood_paint_peel(out, seg, level, seed):
    """Painted wood: the paint flakes off and bare wood shows (outlined)."""
    painted = keep(seg, seg.m("wood") & ~natural_wood(seg), 3)
    if not painted.any():
        return out
    m = patches(seg, painted, level * 0.22, 5, seed)
    l = LS.lum(out[m, :3])[:, None]
    out[m, :3] = WOOD * (0.75 + l * 0.5)
    out = outline_shape(out, m, m, seg.px(2))
    return out


def paint_chips(out, seg, level, seed):
    """Painted metal: chipped paint shows grey bare metal (outlined)."""
    metal = keep(seg, seg.m("metal"), 3)
    sat = seg.hsv[..., 1]
    painted = metal & (sat > 0.25)
    if not painted.any():
        return out
    m = patches(seg, painted, level * 0.16, 4, seed)
    out[m, :3] = np.array([0.62, 0.62, 0.66], np.float32)
    return outline_shape(out, m, m, seg.px(2))


def wood_grey(out, seg, k):
    m = keep(seg, natural_wood(seg), 1)
    l = LS.lum(out[m, :3])[:, None]
    grey = WOOD_GREY * (0.6 + l * 0.8)
    out[m, :3] = out[m, :3] * (1 - k) + grey * k
    return out


def wood_splits(out, seg, count, seed, rot=0.0):
    """Splits along the grain (principal axis of each wooden part)."""
    rng = np.random.default_rng(seed)
    comps = [c for c in seg.comps("wood") if c.area > seg.px(20) ** 2]
    if not comps:
        return out
    lines = []
    rot_m = np.zeros(seg.shape, bool)
    for i in range(count):
        c = comps[int(rng.integers(0, len(comps)))]
        m = comp_mask(seg, c)
        ys, xs = np.nonzero(m)
        k = rng.integers(0, len(xs))
        ax, ay = c.axis
        ln = math.sqrt(c.area) * rng.uniform(0.3, 0.6)
        x, y = xs[k], ys[k]
        lines.append([(x - ax * ln / 2, y - ay * ln / 2), (x + ax * ln * 0.1, y + ay * ln * 0.1 + seg.px(2)), (x + ax * ln / 2, y + ay * ln / 2)])
        if rot > 0 and rng.random() < rot:
            yb = ys.max()
            rot_m |= m & (np.arange(seg.shape[0])[:, None] > yb - (ys.max() - ys.min()) * 0.25) & (smooth_field(seg.shape, seg.px(6), seed + i) > 0.45)
    region = keep(seg, seg.m("wood"), 2)
    if rot_m.any():
        rot_m &= region
        out[rot_m, :3] = out[rot_m, :3] * 0.45 + ROT * 0.55
    sm = lines_mask(seg.shape, lines, seg.px(4)) & region
    out[sm, :3] = OUTLINE
    return out


def wood_broken(out, seg, count, seed):
    """Broken boards: a jagged piece missing (dark behind), splinters outlined."""
    rng = np.random.default_rng(seed)
    comps = sorted([c for c in seg.comps("wood") if c.area > seg.px(24) ** 2], key=lambda c: -c.area)[:4]
    for i in range(min(count, len(comps))):
        c = comps[i % len(comps)]
        m = comp_mask(seg, c)
        ys, xs = np.nonzero(m)
        k = rng.integers(0, len(xs))
        ax, ay = c.axis
        r = max(seg.px(22), math.sqrt(c.area) * rng.uniform(0.22, 0.32))
        pts = []
        for t in np.linspace(0, 2 * math.pi, 10, endpoint=False):
            rr = r * (0.55 if int(t * 10) % 2 else 1.0)
            pts.append((xs[k] + math.cos(t) * rr * (1 + abs(ax)), ys[k] + math.sin(t) * rr * 0.6))
        hole = poly_mask(seg.shape, pts) & keep(seg, m, 2)
        out[hole, :3] = INTERIOR
        out = outline_shape(out, ndimage.binary_dilation(hole, iterations=seg.px(3)) & m, m, seg.px(3))
    return out


def wood_fresh(out, seg, share, seed):
    """Restoration trace: a few replaced boards in fresh, lighter wood."""
    rng = np.random.default_rng(seed)
    comps = [c for c in seg.comps("wood") if c.area > seg.px(16) ** 2]
    rng.shuffle(comps)
    for c in comps[:max(1, int(len(comps) * share))] if comps else []:
        m = keep(seg, comp_mask(seg, c), 2)
        l = LS.lum(out[m, :3])[:, None]
        out[m, :3] = out[m, :3] * 0.55 + WOOD_FRESH * (0.7 + l * 0.4) * 0.45
    return out


# --- glass ---------------------------------------------------------------------

def glass_dirty(out, seg, k, seed):
    m = seg.glass
    film = np.array([0.55, 0.60, 0.60], np.float32)
    out = recolour(out, m, film, k)
    rng = np.random.default_rng(seed)
    for c in seg.glass_components():
        y0, y1, x0, x1 = c.sl[0].start, c.sl[0].stop, c.sl[1].start, c.sl[1].stop
        w = (x1 - x0)
        streak = poly_mask(seg.shape, [(x0 + w * 0.2, y1), (x0 + w * 0.45, y1), (x0 + w * 0.3, y0 + (y1 - y0) * rng.uniform(0.3, 0.6))]) & comp_mask(seg, c)
        out = recolour(out, streak, GRIME, 0.35)
    return out


def glass_cracked(out, seg, share, seed):
    """Star cracks (glass still in place)."""
    rng = np.random.default_rng(seed)
    comps = seg.glass_components()
    rng.shuffle(comps)
    lines = []
    for c in comps[:int(round(len(comps) * share))]:
        y0, y1, x0, x1 = c.sl[0].start, c.sl[0].stop, c.sl[1].start, c.sl[1].stop
        cx, cy = rng.uniform(x0 + (x1 - x0) * 0.3, x1 - (x1 - x0) * 0.3), rng.uniform(y0 + (y1 - y0) * 0.3, y1 - (y1 - y0) * 0.3)
        r = max(x1 - x0, y1 - y0)
        for j in range(int(rng.integers(4, 7))):
            a = rng.uniform(0, 2 * math.pi)
            lines.append([(cx, cy), (cx + math.cos(a) * r * 0.35, cy + math.sin(a) * r * 0.3 + seg.px(2)), (cx + math.cos(a) * r, cy + math.sin(a) * r)])
    m = lines_mask(seg.shape, lines, seg.px(3)) & seg.glass
    out[m, :3] = OUTLINE
    return out


def glass_broken(out, seg, share, seed, pick=None):
    """Jagged hole (dark interior) with shards left in the frame."""
    rng = np.random.default_rng(seed)
    comps = seg.glass_components() if pick is None else pick
    comps = list(comps)
    rng.shuffle(comps)
    for c in comps[:int(round(len(comps) * share))]:
        m = comp_mask(seg, c)
        y0, y1, x0, x1 = c.sl[0].start, c.sl[0].stop, c.sl[1].start, c.sl[1].stop
        cx, cy, rx, ry = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
        hole = poly_mask(seg.shape, jagged(rng, cx, cy, rx * 0.95, ry * 0.95, 13, 0.55)) & m
        out[hole, :3] = INTERIOR
        ring = ndimage.binary_dilation(hole, iterations=seg.px(3)) & ~hole & m
        out[ring, :3] = OUTLINE
    return out


def glass_boarded(out, seg, share, seed):
    """Boarded-up windows: planks nailed across (wood, outlined, nail dots)."""
    rng = np.random.default_rng(seed)
    comps = [c for c in seg.glass_components() if c.area > seg.px(14) ** 2]
    rng.shuffle(comps)
    for c in comps[:int(round(len(comps) * share))]:
        y0, y1, x0, x1 = c.sl[0].start, c.sl[0].stop, c.sl[1].start, c.sl[1].stop
        frame = ndimage.binary_dilation(comp_mask(seg, c), iterations=seg.px(6)) & seg.opaque
        out[comp_mask(seg, c), :3] = INTERIOR
        s = face_slope(seg, (x0 + x1) / 2)
        w = x1 - x0
        hgt = y1 - y0
        pw = max(seg.px(12), hgt * 0.2)
        col = WOOD * rng.uniform(0.85, 1.05)
        planks = []
        for t in (0.3, 0.68):
            yc = y0 + hgt * t
            planks.append([(x0 - seg.px(4), yc - pw / 2 - s * w / 2), (x1 + seg.px(4), yc - pw / 2 + s * w / 2), (x1 + seg.px(4), yc + pw / 2 + s * w / 2), (x0 - seg.px(4), yc + pw / 2 - s * w / 2)])
        d = rng.uniform(-0.2, 0.2)
        planks.append([(x0, y0 + hgt * (0.1 + d) - s * 0), (x0 + pw, y0 + hgt * (0.1 + d)), (x1, y1 - hgt * 0.1), (x1 - pw, y1 - hgt * 0.1)])
        for pts in planks:
            pm = poly_mask(seg.shape, pts) & frame
            out[pm, :3] = col
            out[pm, 3] = 1.0
            out = outline_shape(out, pm, pm, seg.px(3))
            ys, xs = np.nonzero(pm)
            if len(xs):
                for nx in (xs.min() + seg.px(8), xs.max() - seg.px(8)):
                    col_ys = ys[np.abs(xs - nx) < 1]
                    if len(col_ys):
                        ny = int(col_ys.mean())
                        nm = poly_mask(seg.shape, [(nx - seg.px(3), ny - seg.px(3)), (nx + seg.px(3), ny - seg.px(3)), (nx + seg.px(3), ny + seg.px(3)), (nx - seg.px(3), ny + seg.px(3))]) & pm
                        out[nm, :3] = OUTLINE
    return out


# --- roof ----------------------------------------------------------------------

def roof_tiles(out, seg, count, seed, colour_k=0.0, fresh=False):
    """Displaced/odd tiles (parallelograms along the slope). fresh=True:
    new replacement tiles in a slightly different tone (repair trace)."""
    rng = np.random.default_rng(seed)
    region = keep(seg, seg.roof, 4)
    ys, xs = np.nonzero(region)
    if len(xs) == 0:
        return out
    t = seg.px(20)
    patch_m = np.zeros(seg.shape, bool)
    for i in range(count):
        k = rng.integers(0, len(xs))
        x, y = float(xs[k]), float(ys[k])
        s = face_slope(seg, x)
        n = int(rng.integers(2, 5)) if fresh else 1
        for j in range(n):
            for q in range(n if fresh else 1):
                px_, py_ = x + j * t, y + j * t * s + q * t * 0.55
                pts = [(px_, py_), (px_ + t, py_ + t * s), (px_ + t, py_ + t * s + t * 0.55), (px_, py_ + t * 0.55)]
                patch_m |= poly_mask(seg.shape, pts)
    patch_m &= region
    if fresh:
        base = out[patch_m, :3]
        warm = np.array([0.08, 0.02, -0.02], np.float32)
        out[patch_m, :3] = np.clip(base * 1.12 + warm, 0, 1)
    else:
        lab, n = ndimage.label(patch_m)
        for i in range(1, n + 1):
            p = lab == i
            out[p, :3] = np.clip(out[p, :3] * (1.25 if i % 2 else 0.7), 0, 1)
    out = outline_shape(out, patch_m, patch_m, seg.px(2))
    return out


def roof_moss(out, seg, level, seed):
    rng = np.random.default_rng(seed)
    region = keep(seg, seg.roof, 3)
    m = patches(seg, region, 0.12 * level, 9, seed + 3)
    out[m, :3] = MOSS_DARK
    hi = m & ~np.roll(m, seg.px(4), axis=0)
    out[hi, :3] = MOSS
    out = outline_shape(out, m, m, seg.px(2))
    return out


def roof_holes(out, seg, count, seed, charred=False):
    rng = np.random.default_rng(seed)
    clip = ndimage.binary_erosion(seg.roof, iterations=seg.px(12))
    ys, xs = np.nonzero(clip)
    if len(xs) == 0:
        return out
    roof_col = out[seg.roof, :3].mean(0)
    for i in range(count):
        k = rng.integers(0, len(xs))
        cx, cy = xs[k], ys[k]
        r = seg.px(rng.uniform(32, 52))
        hole = poly_mask(seg.shape, jagged(rng, cx, cy, r, r * 0.6, 12, 0.4)) & seg.roof
        rim = ndimage.binary_dilation(hole, iterations=seg.px(9)) & ~hole & seg.roof
        out[rim, :3] = (char_colours(out[rim, :3]) if charred else np.clip(roof_col * 1.45 + 0.05, 0, 1))
        out[hole, :3] = INTERIOR * 0.8
        s = face_slope(seg, cx)
        beams = lines_mask(seg.shape, [[(cx - r, cy - r * s * 0.6 + r * 0.25), (cx + r, cy + r * s * 0.6 + r * 0.25)], [(cx - r, cy - r * s * 0.6 - r * 0.2), (cx + r, cy + r * s * 0.6 - r * 0.2)]], seg.px(10)) & hole
        out[beams, :3] = BEAM_CHAR if charred else WOOD
        out = outline_shape(out, beams, hole, seg.px(3))
        ring = ndimage.binary_dilation(hole, iterations=seg.px(4)) & ~hole & seg.roof
        out[ring, :3] = OUTLINE
        out = outline_shape(out, rim, rim, seg.px(2))
    return out


# --- metal / fabric ---------------------------------------------------------------

def rust_metal(out, seg, level, seed):
    metal = seg.m("metal")
    if not metal.any():
        return out
    near_edge = ndimage.binary_dilation(seg.outline, iterations=seg.px(10)) & metal & ~seg.outline
    m = patches(seg, metal & ~seg.outline, level * 0.18, 5, seed) | patches(seg, near_edge, level * 0.35, 4, seed + 1)
    dark = patches(seg, m, 0.4, 3, seed + 2, opening=0)
    out[m, :3] = LS.RUST
    out[dark, :3] = LS.RUST_DARK
    return out


def dents(out, seg, count, seed):
    rng = np.random.default_rng(seed)
    region = keep(seg, seg.m("metal"), 3)
    ys, xs = np.nonzero(region)
    for i in range(min(count, len(xs))):
        k = rng.integers(0, len(xs))
        r = max(seg.px(rng.uniform(10, 18)), min(seg.w, seg.h) * rng.uniform(0.07, 0.11))
        m = poly_mask(seg.shape, jagged(rng, xs[k], ys[k], r, r * 0.6, 8, 0.2)) & region
        out[m, :3] *= 0.62
        hi = m & ~np.roll(m, -max(2, int(r * 0.25)), axis=1)
        out[hi, :3] = np.clip(out[hi, :3] * 1.7 + 0.05, 0, 1)
        out = outline_shape(out, m & ~hi, m, seg.px(2))
    return out


def fabric_fade(out, seg, k):
    m = keep(seg, seg.m("fabric"), 1)
    return desat(out, m, k, lighten=k * 0.12)


def fabric_tears(out, seg, count, seed, burnt=False):
    """Tears from the lower hem: dark gap + hanging flap, outlined."""
    rng = np.random.default_rng(seed)
    comps = [c for c in seg.comps("fabric") if c.area > seg.px(20) ** 2]
    for i in range(count):
        if not comps:
            break
        c = comps[int(rng.integers(0, len(comps)))]
        m = comp_mask(seg, c)
        ys, xs = np.nonzero(m)
        # lower hem: lowest opaque fabric pixel per column
        x = int(rng.uniform(xs.min() + (xs.max() - xs.min()) * 0.15, xs.max() - (xs.max() - xs.min()) * 0.15))
        col = ys[np.abs(xs - x) < 2]
        if len(col) == 0:
            continue
        yb = col.max()
        w = seg.px(rng.uniform(14, 24))
        hgt = (col.max() - col.min()) * rng.uniform(0.35, 0.7)
        gap = poly_mask(seg.shape, [(x - w, yb + 2), (x + w * 0.2, yb + 2), (x + rng.uniform(-w, w) * 0.4, yb - hgt)]) & m
        out[gap, :3] = INTERIOR * (0.6 if burnt else 1.0)
        out = outline_shape(out, ndimage.binary_dilation(gap, iterations=seg.px(3)) & m, m, seg.px(3))
        if not burnt:
            flap = poly_mask(seg.shape, [(x - w, yb), (x + w * 0.1, yb), (x - w * 0.7, yb + hgt * 0.45)]) & ~seg.opaque
            fc = out[m, :3].mean(0) * 0.78
            out[flap, :3] = fc
            out[flap, 3] = 1.0
            out = outline_shape(out, flap, flap, seg.px(3))
    return out


# --- fire ----------------------------------------------------------------------------

def soot_plumes(out, seg, comps, level, seed):
    rng = np.random.default_rng(seed)
    m = np.zeros(seg.shape, bool)
    for c in comps:
        y0, x0, x1 = c.sl[0].start, c.sl[1].start, c.sl[1].stop
        w = x1 - x0
        pts = []
        for j in range(3):
            cx = x0 + w * (0.25 + 0.25 * j) + rng.uniform(-w * 0.1, w * 0.1)
            hgt = seg.px(110) * level * rng.uniform(0.7, 1.3)
            m |= poly_mask(seg.shape, [(cx - w * 0.3, y0 + seg.px(6)), (cx + w * 0.3, y0 + seg.px(6)), (cx + rng.uniform(-w * 0.25, w * 0.25), y0 - hgt)])
    m = ndimage.binary_dilation(m, iterations=seg.px(4)) & seg.inner & ~seg.glass
    out[m, :3] = out[m, :3] * 0.25 + SOOT * 0.75
    for c in comps:
        g = comp_mask(seg, c)
        out[g, :3] = INTERIOR * 0.55
    return out


def scorch(out, seg, seed):
    """Scorch marks rising from the base on one side (fire put out early)."""
    rng = np.random.default_rng(seed)
    H, W = seg.shape
    x0, y0, x1, y1 = seg.bbox
    cx = rng.uniform(x0 + seg.w * 0.25, x1 - seg.w * 0.25)
    m = np.zeros(seg.shape, bool)
    for j in range(4):
        bx = cx + rng.uniform(-0.15, 0.15) * seg.w
        hgt = seg.h * rng.uniform(0.25, 0.5)
        wd = seg.w * rng.uniform(0.06, 0.1)
        m |= poly_mask(seg.shape, [(bx - wd, y1), (bx + wd, y1), (bx + rng.uniform(-wd, wd), y1 - hgt)])
    m = ndimage.binary_dilation(m, iterations=seg.px(5)) & seg.inner
    out[m, :3] = out[m, :3] * 0.3 + SOOT * 0.7
    core = m & (np.arange(H)[:, None] > y1 - seg.h * 0.12)
    out[core, :3] = char_colours(out[core, :3]) * 0.7
    return out


def side_mask(seg, side, frac):
    """Pixels of one side of the sprite (left/right part, soft jagged edge)."""
    H, W = seg.shape
    x0, x1 = seg.bbox[0], seg.bbox[2]
    cut = x0 + (x1 - x0) * (frac if side < 0 else 1 - frac)
    yy = np.arange(H)[:, None]
    wav = np.sin(yy / max(1, seg.px(30))) * seg.px(18)
    xx = np.arange(W)[None, :]
    return (xx < cut + wav) if side < 0 else (xx > cut + wav)


def burn_part(out, seg, side, frac, seed):
    """Partly burnt: one side charred, its windows black, burnt hole in the
    roof with charred rafters, soot above the openings, fabric burnt."""
    region = side_mask(seg, side, frac) & seg.inner
    f = smooth_field(seg.shape, seg.px(14), seed + 2)
    region |= side_mask(seg, side, frac + 0.12) & seg.inner & (f > 0.55)
    m = region & ~seg.glass
    out[m, :3] = out[m, :3] * 0.2 + char_colours(out[m, :3]) * 0.8
    edge = edge_of(region, seg.px(5)) & seg.inner & ~seg.outline & ~region
    comps = [c for c in seg.glass_components() if region[int(c.cy), int(c.cx)]]
    out = soot_plumes(out, seg, comps, 0.9, seed)
    if seg.roof.any():
        roof_part = seg.roof & region
        if roof_part.sum() > seg.px(40) ** 2:
            tmp = _restricted(seg, roof_part)
            out = roof_holes(out, tmp, 2, seed + 5, charred=True)
    out = fabric_tears(out, _restricted_mat(seg, region), 3, seed + 6, burnt=True)
    return out


class _View:
    """Light-weight view of a MaterialSeg with some masks restricted."""

    def __init__(self, seg, **masks):
        self.__dict__.update({k: getattr(seg, k) for k in ("shape", "opaque", "outline", "inner", "bbox", "h", "w", "unit", "glass", "roof", "components")})
        self._seg = seg
        self._masks = dict(seg.masks)
        for k, v in masks.items():
            setattr(self, k, v)
            if k in self._masks:
                self._masks[k] = v

    def px(self, v):
        return self._seg.px(v)

    def m(self, *names):
        out = np.zeros(self.shape, bool)
        for n in names:
            out |= self._masks[n]
        return out

    def comps(self, *names):
        return [c for c in self._seg.comps(*names) if self.m(*names)[int(c.cy), int(c.cx)]]

    def glass_components(self):
        return [c for c in self._seg.glass_components() if self.glass[int(c.cy), int(c.cx)]]


def _restricted(seg, roof):
    return _View(seg, roof=roof)


def _restricted_mat(seg, region):
    return _View(seg, fabric=seg.masks["fabric"] & region, glass=seg.glass & region)


# --- ground: rubble, beams, plants --------------------------------------------------------

def rubble(out, seg, src, amount, seed, weathered=False, spread=0.22, beams=0):
    """Cartoon rubble from the asset's own colours (walls, roof), outlined.
    weathered: faded and partly grown over with grass."""
    rng = np.random.default_rng(seed)
    H, W = seg.shape
    x0, y0, x1, y1 = seg.bbox
    palette = []
    for name in ("plaster", "brick", "stone", "roof", "wood"):
        mm = seg.m(name)
        if mm.sum() > 50:
            palette.append(src[mm, :3].mean(0))
    palette = palette or [np.array([0.55, 0.5, 0.5], np.float32)]
    layer = out.copy()
    bottom = ground_line(seg)
    count = int(amount * 26 * max(seg.unit, 0.5))
    all_m = np.zeros((H, W), bool)
    for i in range(count):
        cx = rng.uniform(x0 + seg.w * 0.04, x1 - seg.w * 0.04)
        by = bottom[int(cx)] if bottom[int(cx)] >= 0 else y1
        cy = by - rng.uniform(seg.px(4), seg.h * spread)
        r = seg.px(rng.uniform(14, 36))
        m = poly_mask(seg.shape, jagged(rng, cx, cy, r, r * 0.62, 6, 0.35))
        col = palette[int(rng.integers(0, len(palette)))] * rng.uniform(0.78, 1.0)
        if weathered:
            g = LS.lum(col)
            col = col * 0.55 + g * 0.45
        layer[m, :3] = col
        layer[m, 3] = 1.0
        hi = m & ~np.roll(m, seg.px(5), axis=0)
        layer[hi, :3] = np.clip(col * 1.18, 0, 1)
        layer = outline_shape(layer, m, m, seg.px(4))
        all_m |= m
    for i in range(beams):
        cx = rng.uniform(x0 + seg.w * 0.15, x1 - seg.w * 0.15)
        by = bottom[int(cx)] if bottom[int(cx)] >= 0 else y1
        cy = by - rng.uniform(seg.h * 0.05, seg.h * 0.18)
        ln = seg.px(rng.uniform(80, 140))
        a = rng.uniform(-0.9, 0.9)
        wdt = seg.px(12)
        dx, dy = math.cos(a) * ln / 2, math.sin(a) * ln / 2 * 0.7
        nx, ny = -math.sin(a) * wdt / 2, math.cos(a) * wdt / 2
        bm = poly_mask(seg.shape, [(cx - dx + nx, cy - dy + ny), (cx + dx + nx, cy + dy + ny), (cx + dx - nx, cy + dy - ny), (cx - dx - nx, cy - dy - ny)])
        layer[bm, :3] = WOOD * (0.6 if weathered else 0.95)
        layer[bm, 3] = 1.0
        layer = outline_shape(layer, bm, bm, seg.px(3))
        all_m |= bm
    if weathered:
        layer = grass_tufts(layer, seg, all_m, seed + 9)
    return layer


def ground_line(seg):
    """Ground y per column: the front edges of the isometric footprint
    (rising 1:2 from the lowest point), never the underside of an awning."""
    H, W = seg.shape
    ys, xs = np.nonzero(seg.opaque)
    y1 = ys.max()
    xb = xs[ys == y1].mean()
    col = np.full(W, -1)
    np.maximum.at(col, xs, ys)
    iso = y1 - np.abs(np.arange(W) - xb) * 0.5
    return np.maximum(col, iso).astype(int)


def grass_tufts(out, seg, on_mask, seed, count=None):
    rng = np.random.default_rng(seed)
    ys, xs = np.nonzero(on_mask & ~np.roll(on_mask, seg.px(6), axis=0))
    if len(xs) == 0:
        return out
    n = count or int(14 * max(seg.unit, 0.5))
    m = np.zeros(seg.shape, bool)
    for i in range(n):
        k = rng.integers(0, len(xs))
        x, y = xs[k], ys[k]
        for j in range(3):
            dx = (j - 1) * seg.px(7)
            m |= poly_mask(seg.shape, [(x + dx - seg.px(4), y + seg.px(3)), (x + dx + seg.px(4), y + seg.px(3)), (x + dx * 1.6, y - seg.px(rng.uniform(14, 24)))])
    out[m, :3] = MOSS
    out[m, 3] = 1.0
    hi = m & ~np.roll(m, seg.px(3), axis=1)
    out[hi, :3] = np.clip(MOSS * 1.2, 0, 1)
    return outline_shape(out, m, m, seg.px(2))


# --- structure: break line ------------------------------------------------------------

def break_walls(a, seg, frac, seed, side=0, rough=1.0, beams=2, stepped=False):
    """Removes everything above a jagged break line; outlines the break,
    shows the dark interior just below it and broken beams sticking out."""
    rng = np.random.default_rng(seed)
    H, W = seg.shape
    x0, y0, x1, y1 = seg.bbox
    out = a.copy()
    xs = np.arange(W)
    noise = ndimage.gaussian_filter1d(rng.normal(0, 1, W), seg.px(14))
    noise = noise / max(np.abs(noise).max(), 1e-6)
    tilt = rng.uniform(-0.12, 0.12) * seg.h
    cut = y0 + seg.h * frac + noise * seg.px(38) * rough + (xs - (x0 + x1) / 2) / max(seg.w, 1) * tilt
    for n in range(int(rng.integers(4, 8))):
        cxn = rng.uniform(x0, x1)
        wn = seg.px(rng.uniform(16, 30))
        dn = seg.px(rng.uniform(14, 34)) * rough * (1 if rng.random() < 0.5 else -1)
        cut += np.clip(1 - np.abs(xs - cxn) / wn, 0, 1) * dn
    if side != 0:
        t = np.clip((xs - x0) / max(seg.w, 1), 0, 1)
        ramp = t if side > 0 else 1 - t
        ramp = np.clip((ramp - 0.35) / 0.65, 0, 1)
        cut = y0 + (cut - y0) * ramp
    if stepped:
        # old masonry breaks in courses: flat plateaus and steps, one taller corner
        low = ndimage.gaussian_filter1d(rng.normal(0, 1, W), seg.px(45))
        low = low / max(np.abs(low).max(), 1e-6)
        cut = y0 + seg.h * frac + low * seg.h * 0.16
        corner = rng.uniform(x0 + seg.w * 0.3, x1 - seg.w * 0.3)
        cut -= np.clip(1 - np.abs(xs - corner) / (seg.w * 0.12), 0, 1) * seg.h * 0.18
        step = seg.px(26)
        cut = np.round(cut / step) * step
        # run-length smoothing: plateaus at least ~2 steps wide
        cut = ndimage.median_filter(cut, size=max(3, seg.px(40)))
    remove = np.arange(H)[:, None] < cut[None, :]
    out[remove] = 0.0
    kept = seg.opaque & ~remove
    band = kept & (np.arange(H)[:, None] < cut[None, :] + seg.px(26)) & ~seg.outline
    out[band, :3] = out[band, :3] * 0.35 + INTERIOR * 0.65
    top_edge = kept & ndimage.binary_dilation(remove & ~kept, iterations=seg.px(7))
    out[top_edge, :3] = OUTLINE
    out[top_edge, 3] = 1.0
    # broken beams sticking out of the break
    for i in range(beams):
        bx = int(rng.uniform(x0 + seg.w * 0.2, x1 - seg.w * 0.2))
        col_kept = np.nonzero(kept[:, bx])[0]
        if len(col_kept) == 0:
            continue
        by = col_kept.min() + seg.px(10)
        ln = seg.px(rng.uniform(50, 90))
        a_ = rng.uniform(-2.3, -0.8)
        wdt = seg.px(11)
        dx, dy = math.cos(a_) * ln, math.sin(a_) * ln
        nx, ny = -math.sin(a_) * wdt / 2, math.cos(a_) * wdt / 2
        pts = [(bx + nx, by + ny), (bx + dx + nx, by + dy + ny), (bx + dx * 0.92 - nx, by + dy * 1.05 - ny), (bx - nx, by - ny)]
        bm = poly_mask(seg.shape, pts)
        out[bm, :3] = WOOD * 0.9
        out[bm, 3] = 1.0
        out = outline_shape(out, bm, bm, seg.px(3))
    return out


def remove_roof(out, seg, seed, charred=True):
    """Burnt-out roof: the roof surface is gone – you look into the dark,
    burnt interior; charred rafters remain, the roof edge is charred."""
    rng = np.random.default_rng(seed)
    roof = seg.roof
    if not roof.any():
        return out
    border = edge_of(roof, seg.px(14)) | (roof & ndimage.binary_dilation(seg.outline, iterations=seg.px(10)))
    hole = roof & ~border
    out[hole, :3] = INTERIOR * 0.55
    out[border & ~seg.outline, :3] = char_colours(out[border & ~seg.outline, :3]) * 0.8
    ys, xs = np.nonzero(hole)
    if len(xs):
        lines = []
        xa, xb, ya, yb = xs.min(), xs.max(), ys.min(), ys.max()
        n = max(3, int((xb - xa) / seg.px(70)))
        for i in range(n):
            x = xa + (xb - xa) * (i + 0.5) / n + rng.uniform(-1, 1) * seg.px(10)
            s = face_slope(seg, x)
            lines.append([(x - seg.px(40), ya - s * seg.px(40)), (x + seg.px(40), yb + s * seg.px(40))])
        ridge = [(xa, (ya + yb) / 2), (xb, (ya + yb) / 2 - seg.px(10))]
        lines.append(ridge)
        bm = lines_mask(seg.shape, lines, seg.px(10)) & ndimage.binary_dilation(hole, iterations=seg.px(2))
        # some rafters broke: cut random gaps
        f = smooth_field(seg.shape, seg.px(12), seed + 4)
        bm &= f < 0.72
        out[bm, :3] = BEAM_CHAR * 1.6
        out = outline_shape(out, bm, bm, seg.px(3))
    out[edge_of(hole, seg.px(3)) & hole, :3] = OUTLINE
    return out


# --- layer generators ------------------------------------------------------------------
# Each returns a full-canvas RGBA array that differs from the original only
# where the trait changes something (overlay = diff, cut out later).

def wear_layer(a, seg, level, seed):
    """level 2 = vernachlässigt, 3 = stark heruntergekommen (on top of the
    shader). Neglect, not violence: no cracks through walls, no rubble."""
    o = a.copy()
    o = stains(o, seg, seg.m("plaster", "brick", "stone", "wood"), level - 1, seed)
    o = peel_plaster(o, seg, 0.5 if level == 2 else 0.95, seed)
    o = missing_bricks(o, seg, keep(seg, seg.m("brick"), 3), 3 if level == 2 else 8, np.random.default_rng(seed + 3))
    o = wood_grey(o, seg, 0.35 if level == 2 else 0.6)
    o = wood_splits(o, seg, 3 if level == 2 else 7, seed + 4, rot=0.0 if level == 2 else 0.7)
    o = rust_metal(o, seg, 0.4 if level == 2 else 0.75, seed + 5)
    o = fabric_fade(o, seg, 0.35 if level == 2 else 0.6)
    o = glass_dirty(o, seg, 0.35 if level == 2 else 0.55, seed + 6)
    o = roof_tiles(o, seg, 3 if level == 2 else 7, seed + 7)
    if level >= 3:
        o = roof_moss(o, seg, 0.8, seed + 8)
        o = fabric_tears(o, seg, 2, seed + 9)
        o = glass_boarded(o, seg, 0.6, seed + 10)
        o = roof_holes(o, seg, 1, seed + 11)
    return o


def damage_layer(a, seg, level, seed):
    """level 1 = beschädigt (fresh damage), 2 = schwer beschädigt (goes with
    the 'partial' structure)."""
    o = a.copy()
    if level == 1:
        o = glass_cracked(o, seg, 0.35, seed)
        o = glass_broken(o, seg, 0.35, seed + 1)
        o = cracks_plaster(o, seg, 5, seed + 2)
        o = cracks_brick(o, seg, 3, seed + 3)
        o = chips_stone(o, seg, 4, seed + 4)
        o = wood_broken(o, seg, 1, seed + 5)
        o = dents(o, seg, 2, seed + 6)
        o = fabric_tears(o, seg, 1, seed + 7)
        o = roof_holes(o, seg, 1, seed + 8)
        o = rubble(o, seg, a, 0.3, seed + 9, spread=0.08)
    else:
        o = glass_broken(o, seg, 1.0, seed + 1)
        o = cracks_plaster(o, seg, 10, seed + 2)
        o = cracks_brick(o, seg, 6, seed + 3)
        o = chips_stone(o, seg, 8, seed + 4)
        o = wood_broken(o, seg, 3, seed + 5)
        o = dents(o, seg, 4, seed + 6)
        o = fabric_tears(o, seg, 4, seed + 7)
        o = roof_holes(o, seg, 3, seed + 8)
        o = rubble(o, seg, a, 1.0, seed + 9, spread=0.16, beams=2)
    return o


def fire_layer(a, seg, level, seed):
    """level 1 = Rußspuren (a fire was put out), 2 = teilweise ausgebrannt."""
    o = a.copy()
    rng = np.random.default_rng(seed)
    if level == 1:
        comps = seg.glass_components()
        rng.shuffle(comps)
        if comps:
            o = soot_plumes(o, seg, comps[:max(1, len(comps) // 4)], 0.7, seed)
        if len(comps) < 3:
            o = scorch(o, seg, seed + 1)
    else:
        o = burn_part(o, seg, 1 if rng.random() < 0.5 else -1, 0.45, seed)
    return o


def overgrowth_layer(a, seg, level, seed):
    o = LS.overgrowth(a, seg, 0.35 if level == 1 else 0.9, seed)
    if level >= 2:
        o = roof_moss(o, seg, 1.0, seed + 1)
    return o


def fabric_patches(out, seg, count, seed):
    """Sewn-on patches: a slightly different cloth tone, outlined, stitched."""
    rng = np.random.default_rng(seed)
    region = keep(seg, seg.m("fabric"), 6)
    ys, xs = np.nonzero(region)
    if len(xs) == 0:
        return out
    for i in range(count):
        k = rng.integers(0, len(xs))
        cx, cy = xs[k], ys[k]
        r = max(seg.px(26), math.sqrt(region.sum()) * 0.1)
        s_ = face_slope(seg, cx)
        pts = [(cx - r, cy - r * 0.6 - s_ * r), (cx + r, cy - r * 0.6 + s_ * r), (cx + r, cy + r * 0.6 + s_ * r), (cx - r, cy + r * 0.6 - s_ * r)]
        m = poly_mask(seg.shape, pts) & region
        if not m.any():
            continue
        base = out[m, :3].mean(0)
        out[m, :3] = np.clip(base * np.array([1.08, 0.95, 0.85], np.float32) + 0.04, 0, 1)
        out = outline_shape(out, m, m, seg.px(2))
        st = edge_of(m, seg.px(6)) & ~edge_of(m, seg.px(3))
        dash = (np.add.outer(np.arange(seg.shape[0]), np.arange(seg.shape[1])) // max(2, seg.px(6))) % 2 == 0
        out[st & dash, :3] = OUTLINE
    return out


def repair_layer(a, seg, level, seed):
    """Traces after a restoration. level 1 = well restored (subtle but
    visible: a few fresher patches and replaced tiles/boards), level 2 =
    recently and partly repaired (outlined patches, many new boards and tiles,
    one window with new glass)."""
    o = a.copy()
    rng = np.random.default_rng(seed)
    walls = keep(seg, seg.m("plaster", "stone", "brick"), 5) & ~ndimage.binary_dilation(seg.glass, iterations=seg.px(5))
    m = patches(seg, walls, 0.1 if level == 1 else 0.22, 11, seed + 11, opening=3)
    hsv = LS.rgb_to_hsv(o[..., :3])
    hsv[m, 2] = np.clip(hsv[m, 2] * (1.12 if level == 1 else 1.18) + 0.02, 0, 1)
    hsv[m, 1] *= 0.8 if level == 1 else 0.7
    o[..., :3] = np.where(m[..., None], LS.hsv_to_rgb(hsv), o[..., :3])
    o = outline_shape(o, m, m, max(2, seg.px(1 if level == 1 else 2)))
    o = roof_tiles(o, seg, 2 if level == 1 else 4, seed + 12, fresh=True)
    o = wood_fresh(o, seg, 0.2 if level == 1 else 0.4, seed + 13)
    o = fabric_patches(o, seg, 1 if level == 1 else 3, seed + 14)
    if level >= 2:
        comps = seg.glass_components()
        rng.shuffle(comps)
        for c in comps[:max(1, len(comps) // 4)]:
            g = comp_mask(seg, c)
            o[g, :3] = np.clip(o[g, :3] * 0.8 + 0.22, 0, 1)
    return o


def snow_layer(a, seg, level, seed):
    return LS.snow_cap(a, seg, level, seed)


# --- structural bases ------------------------------------------------------------------

def structure_partial(a, seg, seed):
    o = break_walls(a, seg, 0.40, seed, side=1, beams=2)
    return o


def structure_shell(a, seg, seed):
    """Ausgebrannt: walls stand, roof burnt away, everything charred."""
    o = glass_broken(a.copy(), seg, 1.0, seed)
    m = seg.inner & ~seg.glass
    o[m, :3] = o[m, :3] * 0.15 + char_colours(o[m, :3]) * 0.85
    o[seg.glass, :3] = INTERIOR * 0.45
    door = seg.m("wood", "trim") & (np.arange(seg.shape[0])[:, None] > seg.bbox[1] + seg.h * 0.6)
    o[door & ~seg.outline, :3] = INTERIOR * 0.5
    o = remove_roof(o, seg, seed + 1)
    o = soot_plumes(o, seg, seg.glass_components(), 1.0, seed + 2)
    # awnings / tents: charred cloth with burnt holes; the hanging hem is gone
    fab = seg.m("fabric")
    if fab.any():
        fy = np.nonzero(fab)[0]
        hem = fab & (np.arange(seg.shape[0])[:, None] > fy.min() + (fy.max() - fy.min()) * 0.62)
        holes = fab & ~hem & (smooth_field(seg.shape, seg.px(8), seed + 3) > 0.6)
        cloth = fab & ~hem & ~holes
        # nothing is drawn behind an awning in a flat sprite: burnt cloth stays
        # as a charred, opaque remnant (no see-through to the background)
        o[hem, :3] = SOOT * 0.9
        o[cloth, :3] = SOOT * 1.1
        o[holes, :3] = INTERIOR * 0.5
        o = outline_shape(o, holes, fab & ~hem, seg.px(3))
        o = outline_shape(o, ndimage.binary_dilation(hem, iterations=seg.px(5)) & cloth, cloth, seg.px(4))
    o = rubble(o, seg, o, 0.35, seed + 4, spread=0.06, beams=1)
    return o


def structure_collapsed(a, seg, seed):
    """Zerstört: fresh collapse – low wall stumps, big rubble heaps, dust."""
    o = break_walls(a, seg, 0.64, seed, beams=3)
    m = o[..., 3] > 0.5
    o[m, :3] = o[m, :3] * 0.88 + DUST * 0.12
    o = rubble(o, seg, a, 2.0, seed + 1, spread=0.2, beams=4)
    return o


def structure_ruin(a, seg, seed):
    """Ruine: old, weathered remains – irregular walls, no roof, empty
    openings, overgrown rubble, ivy. No soot, no fresh debris."""
    o = a.copy()
    o[seg.glass, :3] = INTERIOR * 0.7
    o = break_walls(o, seg, 0.5, seed + 5, beams=0, stepped=True)
    # no roof survives on a ruin; outline the newly exposed wall tops
    roof_left = seg.roof & (o[..., 3] > 0.5)
    if roof_left.any():
        o[roof_left] = 0.0
        kept = o[..., 3] > 0.5
        rim = kept & ndimage.binary_dilation(roof_left, iterations=seg.px(6))
        o[rim, :3] = OUTLINE
    m = o[..., 3] > 0.5
    o = desat(o, m & ~seg.outline, 0.55)
    o[m & ~seg.outline, :3] *= 0.9
    o = rubble(o, seg, a, 1.0, seed + 6, weathered=True, spread=0.12)
    o = LS.overgrowth(o, MaterialSeg(o, seg.category), 0.9, seed + 7)
    return o


STRUCTURES = {"partial": structure_partial, "shell": structure_shell, "collapsed": structure_collapsed, "ruin": structure_ruin}
LAYERS = {  # name -> (function, level)
    "wear_2": (wear_layer, 2), "wear_3": (wear_layer, 3),
    "damage_1": (damage_layer, 1), "damage_2": (damage_layer, 2),
    "fire_1": (fire_layer, 1), "fire_2": (fire_layer, 2),
    "overgrowth_1": (overgrowth_layer, 1), "overgrowth_2": (overgrowth_layer, 2),
    "repair_1": (repair_layer, 1), "repair_2": (repair_layer, 2),
    "snow_1": (snow_layer, 1),
}
# Overlay order when composing (later = on top).
LAYER_ORDER = ["wear_2", "wear_3", "repair_1", "repair_2", "damage_1", "damage_2", "fire_1", "fire_2", "overgrowth_1", "overgrowth_2", "snow_1"]
# Which overlays make sense on which structural base.
ALLOWED = {
    "intact": set(LAYERS),
    "partial": {"wear_2", "wear_3", "damage_1", "damage_2", "fire_1", "fire_2", "overgrowth_1", "overgrowth_2", "snow_1"},
    "shell": {"overgrowth_1", "overgrowth_2", "snow_1"},
    "collapsed": {"overgrowth_1", "overgrowth_2", "snow_1"},
    "ruin": {"snow_1"},
}

# The 12 named states of the matrix as trait combinations (presets).
# shader = (dirt, fade, darken) for shaders/living_wear.gdshader
PRESETS = [
    ("01_neu", "Neu", {"structure": "intact", "layers": [], "shader": (0.0, 0.0, 0.0), "fresh": True}),
    ("02_gepflegt", "Gepflegt", {"structure": "intact", "layers": [], "shader": (0.12, 0.0, 0.0)}),
    ("03_benutzt", "Normal benutzt", {"structure": "intact", "layers": [], "shader": (0.3, 0.05, 0.0)}),
    ("04_leicht_verschmutzt", "Leicht verschmutzt", {"structure": "intact", "layers": [], "shader": (0.5, 0.1, 0.02)}),
    ("05_vernachlaessigt", "Vernachlässigt", {"structure": "intact", "layers": ["wear_2"], "shader": (0.55, 0.22, 0.04)}),
    ("06_heruntergekommen", "Stark heruntergekommen", {"structure": "intact", "layers": ["wear_3", "overgrowth_1"], "shader": (0.72, 0.4, 0.08)}),
    ("07_beschaedigt", "Beschädigt", {"structure": "intact", "layers": ["damage_1"], "shader": (0.3, 0.05, 0.0)}),
    ("08_schwer_beschaedigt", "Schwer beschädigt", {"structure": "partial", "layers": ["damage_2"], "shader": (0.45, 0.1, 0.03)}),
    ("09_ausgebrannt", "Ausgebrannt", {"structure": "shell", "layers": [], "shader": (0.0, 0.0, 0.0)}),
    ("10_zerstoert", "Zerstört", {"structure": "collapsed", "layers": [], "shader": (0.2, 0.0, 0.0)}),
    ("11_ruine", "Ruine", {"structure": "ruin", "layers": [], "shader": (0.4, 0.0, 0.0)}),
    ("12_restauriert", "Restauriert (Spuren)", {"structure": "intact", "layers": ["repair_1"], "shader": (0.1, 0.0, 0.0)}),
]


# --- preview composition (same rules as the Godot composer) ----------------------------

def overlay_of(variant, original):
    """Changed pixels only (alpha 1), cropped; None if nothing changed."""
    diff = (np.abs(variant - original).max(-1) > 0.02) & (variant[..., 3] > 0.02)
    if not diff.any():
        return None, None
    out = np.zeros_like(variant)
    out[diff] = variant[diff]
    out[diff, 3] = np.maximum(variant[diff, 3], 0.0)
    ys, xs = np.nonzero(diff)
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    return out[box[1]:box[3], box[0]:box[2]], box


def compose(original, base, overlays):
    """overlays: list of (cropped RGBA, (x, y) offset). Overlay pixels are
    dropped where the base is transparent but the original was opaque."""
    out = base.copy()
    H, W = out.shape[:2]
    orig_op = original[..., 3] > 0.5
    for ov, (ox, oy) in overlays:
        h, w = ov.shape[:2]
        if h == 0 or w == 0:
            continue
        sl = (slice(oy, min(H, oy + h)), slice(ox, min(W, ox + w)))
        o = ov[:sl[0].stop - oy, :sl[1].stop - ox]
        allow = (out[sl][..., 3] > 0.5) | ~orig_op[sl]
        al = o[..., 3:4] * allow[..., None]
        out[sl][..., :3] = out[sl][..., :3] * (1 - al) + o[..., :3] * al
        out[sl][..., 3:4] = np.maximum(out[sl][..., 3:4], al)
    return out


def shader_preview(a, dirt, fade, darken, grime, file_scale=0.5, grime_px=180.0):
    """Python twin of shaders/living_wear.gdshader (for contact sheets)."""
    if dirt <= 0 and fade <= 0 and darken <= 0:
        return a.copy()
    H, W = a.shape[:2]
    gh, gw = grime.shape[:2]
    period = grime_px / file_scale
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    gx = ((xx / period) % 1.0 * gw).astype(int) % gw
    gy = ((yy / period) % 1.0 * gh).astype(int) % gh
    field = grime[gy, gx] * 0.75 + (yy / H) * 0.45
    l = LS.lum(a[..., :3])
    line = l <= 0.17
    thr = 1.08 - dirt * 0.62
    patch = (field > thr) & ~line & (dirt > 0.001)
    rim = patch & (field < thr + 0.012)
    dirty = a[..., :3] * 0.70 + GRIME * 0.30
    col = np.where(patch[..., None], dirty, a[..., :3])
    col = np.where(rim[..., None], dirty * 0.9, col)
    g = LS.lum(col)[..., None]
    col = np.where(line[..., None], col, col * (1 - fade) + g * fade)
    col = np.where(line[..., None], col, col * (1 - darken))
    out = a.copy()
    out[..., :3] = col
    return out


# =====================================================================================
# Other categories (same principle: structural bases + independent overlays)
# =====================================================================================

def prop_wear(a, seg, level, seed):
    # small objects need stronger marks to stay readable at game size
    k = 1.0 if seg.h * seg.w > 400 * 400 else 1.35
    o = a.copy()
    o = wood_paint_peel(o, seg, (0.5 if level == 2 else 0.8) * k, seed + 7)
    o = paint_chips(o, seg, (0.07 if level == 2 else 0.2) * k, seed + 8)
    o = wood_grey(o, seg, 0.45 if level == 2 else 0.65)
    o = wood_splits(o, seg, 3 if level == 2 else 6, seed, rot=0.0 if level == 2 else 0.6)
    o = rust_metal(o, seg, (0.5 if level == 2 else 0.8) * k, seed + 1)
    o = fabric_fade(o, seg, 0.35 if level == 2 else 0.6)
    o = glass_dirty(o, seg, 0.4 if level == 2 else 0.6, seed + 2)
    stone = seg.m("stone", "plaster", "brick")
    if stone.any():
        o = stains(o, seg, stone, level - 1, seed + 3)
        m = patches(seg, keep(seg, stone, 2), 0.08 * level, 5, seed + 4)
        o = recolour(o, m, GRIME, 0.3)
    if level >= 3:
        o = fabric_tears(o, seg, 1, seed + 5)
    return o


def prop_damage(a, seg, level, seed):
    o = a.copy()
    o = glass_broken(o, seg, 1.0, seed)
    o = dents(o, seg, 3, seed + 1)
    o = paint_chips(o, seg, 0.6, seed + 8)
    o = wood_broken(o, seg, 2, seed + 2)
    o = wood_splits(o, seg, 3, seed + 3)
    if seg.m("stone", "plaster").any():
        o = cracks_plaster(o, seg, 3, seed + 4, from_windows=False)
    o = chips_stone(o, seg, 3, seed + 5)
    o = fabric_tears(o, seg, 2, seed + 6)
    return o


def prop_broken(a, seg, seed):
    """Zerstört: slim objects fall over, wide ones break apart."""
    if seg.h > seg.w * 1.3:
        return LS.topple(a, seg, seed)
    return LS.break_off(a, seg, seed)


def prop_burnt(a, seg, seed):
    o = a.copy()
    m = seg.inner
    o[m, :3] = o[m, :3] * 0.15 + char_colours(o[m, :3]) * 0.85
    o[seg.glass, :3] = INTERIOR * 0.5
    # charred wood: grey ash on the upper edges and a cracked ("alligator") surface
    top = m & ~np.roll(m, max(2, seg.px(6)), axis=0)
    o[top & ~seg.outline, :3] = np.array([0.55, 0.52, 0.52], np.float32)
    o = wood_splits(o, seg, 8, seed + 3)
    embers = patches(seg, keep(seg, seg.m("wood"), 3), 0.03, 3, seed + 4)
    o[embers, :3] = np.array([0.95, 0.45, 0.12], np.float32)
    fab = seg.m("fabric")   # solid wood/metal objects char but do not get see-through holes
    holes = patches(seg, keep(seg, fab, 3), 0.12, 16, seed, opening=4)
    o[holes] = 0.0
    kept = o[..., 3] > 0.5
    o[kept & ndimage.binary_dilation(holes, iterations=seg.px(3)), :3] = OUTLINE
    return o


def vehicle_wear(a, seg, level, seed):
    o = a.copy()
    o = rust_metal(o, seg, 0.25 if level == 2 else 0.7, seed)
    o = glass_dirty(o, seg, 0.45 if level == 2 else 0.7, seed + 1)
    if level >= 3:   # abandoned: dull paint, one broken window
        m = seg.m("metal")
        o = desat(o, keep(seg, m, 1), 0.45)
        o = glass_broken(o, seg, 0.4, seed + 2)
    return o


def vehicle_damage(a, seg, level, seed):
    o = a.copy()
    o = dents(o, seg, 4, seed)
    o = paint_chips(o, seg, 0.45, seed + 3)
    o = glass_cracked(o, seg, 0.6, seed + 1)
    o = glass_broken(o, seg, 0.5, seed + 2)
    return o


def vehicle_burnt(a, seg, seed):
    o = prop_burnt(a, seg, seed)
    o = rust_metal(o, MaterialSeg(o, "vehicle"), 0.5, seed + 1)
    return o


def vehicle_wreck(a, seg, seed):
    """Wrack: burnt out, roof crushed flat, sitting lower on one side."""
    o = vehicle_burnt(a, seg, seed)
    o = break_walls(o, MaterialSeg(o, "vehicle"), 0.33, seed + 2, beams=0)
    img = LS.to_image(o)
    x0, y0, x1, y1 = seg.bbox
    img = img.rotate(-5, center=((x0 + x1) / 2, y1), resample=Image.BICUBIC)
    return np.asarray(img).astype(np.float32) / 255.0


def crown_mask(seg):
    """Foliage of a plant independent of its colour (green, blossom pink,
    autumn orange): the largest flat-colour area plus its shading spots."""
    if not seg.components:
        return np.zeros(seg.shape, bool)
    big = max(seg.components, key=lambda c: c.area)
    m = big.mask(seg.shape)
    return ndimage.binary_fill_holes(ndimage.binary_closing(m, iterations=max(3, seg.px(12)))) & seg.inner


def veg_dry(a, seg, seed):
    """Dry foliage: clearly yellow-brown (keeps light/dark shading)."""
    o = a.copy()
    leaves = crown_mask(seg)
    l = seg.lum[leaves][:, None]
    lmax = max(float(seg.lum[leaves].max()), 1e-6) if leaves.any() else 1.0
    dry = np.array([0.74, 0.60, 0.30], np.float32) * (0.6 + 0.55 * l / lmax)
    o[leaves, :3] = o[leaves, :3] * 0.3 + dry * 0.7
    return o


def veg_variant(a, seg, state, seed):
    if state in ("abgestorben", "verbrannt"):
        return veg_bare(a, seg, burnt=state == "verbrannt", seed=seed)
    if state == "trocken":
        return veg_dry(a, seg, seed)
    return LS.vegetation_state(a, seg, state, seed)


def veg_bare(a, seg, burnt, seed):
    """Dead / burnt plant without see-through: the crown keeps its silhouette
    but turns grey-brown (dead) or black (burnt); large dark gaps open in the
    foliage and bare branches show inside them. Contours stay intact."""
    rng = np.random.default_rng(seed)
    hsv = seg.hsv
    leaves = crown_mask(seg)
    if not leaves.any():
        return LS.vegetation_state(a, seg, "verbrannt" if burnt else "abgestorben", seed)
    o = a.copy()
    col = np.array([0.56, 0.47, 0.38], np.float32) if not burnt else np.array([0.20, 0.16, 0.17], np.float32)
    l = seg.lum[leaves][:, None]
    o[leaves, :3] = col * (0.65 + 0.6 * l / max(float(seg.lum[leaves].max()), 1e-6))
    ys, xs = np.nonzero(leaves)
    cx, cy = xs.mean(), ys.mean()
    rx, ry = (xs.max() - xs.min()) / 2, (ys.max() - ys.min()) / 2
    line_w = max(3, int(min(rx, ry) * 0.05))
    inner = ndimage.binary_erosion(leaves, iterations=line_w * 2)
    gaps = patches(seg, inner, 0.42 if not burnt else 0.5, 12, seed, opening=4)
    o[gaps, :3] = (np.array([0.24, 0.18, 0.15], np.float32) if not burnt else np.array([0.08, 0.06, 0.07], np.float32))
    o = outline_shape(o, gaps, gaps, max(2, line_w // 2))
    # bare branches forking from the trunk, visible in the gaps
    fork = (cx, cy + ry * 0.35)
    lines = [[(cx, ys.max()), fork]]
    for i in range(6):
        ang = -math.pi / 2 + (i - 2.5) * 0.42 + rng.uniform(-0.15, 0.15)
        ln = rng.uniform(0.7, 0.9)
        mid = (fork[0] + math.cos(ang) * rx * ln * 0.5, fork[1] + math.sin(ang) * ry * ln * 0.55)
        tip = (fork[0] + math.cos(ang + rng.uniform(-0.25, 0.25)) * rx * ln, fork[1] + math.sin(ang) * ry * ln)
        lines.append([fork, mid, tip])
        lines.append([mid, (mid[0] + math.cos(ang + 0.8) * rx * 0.25, mid[1] + math.sin(ang + 0.8) * ry * 0.25)])
    br = lines_mask(seg.shape, lines, max(3, int(min(rx, ry) * 0.08))) & gaps
    bark = np.array([0.42, 0.31, 0.24], np.float32) if not burnt else np.array([0.30, 0.27, 0.27], np.float32)
    o[br, :3] = bark
    o = outline_shape(o, br, br, max(1, line_w // 3))
    if burnt:
        trunk = seg.inner & ~leaves
        o[trunk, :3] = o[trunk, :3] * 0.35
        embers = patches(seg, leaves & ~gaps, 0.03, 3, seed + 5)
        o[embers, :3] = np.array([0.95, 0.45, 0.12], np.float32)
    return o


def tent_collapse(a, seg, seed):
    """Collapsed tent: the cloth lies flat on the ground, a pole snapped."""
    rng = np.random.default_rng(seed)
    x0, y0, x1, y1 = seg.bbox
    spr = LS.to_image(a).crop((x0, y0, x1, y1))
    flat_h = max(4, int(spr.height * 0.36))
    spr = spr.resize((spr.width, flat_h), Image.LANCZOS)
    out = Image.new("RGBA", (a.shape[1], a.shape[0]), (0, 0, 0, 0))
    out.alpha_composite(spr, (x0, y1 - flat_h))
    o = np.asarray(out).astype(np.float32) / 255.0
    cx = x0 + (x1 - x0) * 0.25
    ln = (y1 - y0) * 0.4
    wd = max(seg.px(14), 3)
    pole = poly_mask(seg.shape, [(cx - wd / 2, y1 - flat_h * 0.5), (cx + wd / 2, y1 - flat_h * 0.5), (cx + wd / 2 + ln * 0.35, y1 - flat_h * 0.5 - ln), (cx - wd / 2 + ln * 0.35, y1 - flat_h * 0.5 - ln)])
    o[pole, :3] = WOOD
    o[pole, 3] = 1.0
    return outline_shape(o, pole, pole, max(2, seg.px(4)))


# --- surfaces -------------------------------------------------------------------------------

LEAF_COLOURS = [np.array(c, np.float32) for c in ([0.85, 0.55, 0.15], [0.75, 0.35, 0.12], [0.90, 0.75, 0.25], [0.55, 0.35, 0.18])]


def dark_dirt(out, seg, region, seed):
    """Dark asphalt: dust is LIGHTER than the surface; oil stains with sheen."""
    m = patches(seg, region & ~seg.outline, 0.3, 16, seed, opening=3)
    out[m, :3] = out[m, :3] * 0.6 + DUST * 0.4 * 0.75
    rng = np.random.default_rng(seed + 1)
    ys, xs = np.nonzero(ndimage.binary_erosion(region, iterations=seg.px(40)))
    for i in range(3):
        if len(xs) == 0:
            break
        k = rng.integers(0, len(xs))
        r = seg.px(rng.uniform(26, 40))
        oil = poly_mask(seg.shape, jagged(rng, xs[k], ys[k], r, r * 0.5, 12, 0.25)) & region
        out[oil, :3] = np.array([0.10, 0.09, 0.12], np.float32)
        sheen = oil & poly_mask(seg.shape, jagged(rng, xs[k] - r * 0.2, ys[k] - r * 0.1, r * 0.4, r * 0.18, 8, 0.2))
        out[sheen, :3] = np.array([0.35, 0.30, 0.55], np.float32)
    return out


def potholes_dark(out, seg, region, seed):
    """Potholes in asphalt: dark hole, light broken edge, loose gravel."""
    rng = np.random.default_rng(seed)
    ys, xs = np.nonzero(ndimage.binary_erosion(region, iterations=seg.px(50)))
    base = out[region, :3].mean(0)
    for i in range(int(rng.integers(3, 5))):
        if len(xs) == 0:
            break
        k = rng.integers(0, len(xs))
        cx, cy = xs[k], ys[k]
        r = seg.px(rng.uniform(34, 56))
        hole = poly_mask(seg.shape, jagged(rng, cx, cy, r, r * 0.5, 14, 0.3)) & region
        rim = ndimage.binary_dilation(hole, iterations=seg.px(9)) & ~hole & region
        out[rim, :3] = np.clip(base * 1.45 + 0.08, 0, 1)
        out[hole, :3] = INTERIOR * 0.75
        inner_hl = hole & np.roll(~hole, seg.px(6), axis=0)
        out[inner_hl, :3] = np.clip(base * 0.8, 0, 1)
        out = outline_shape(out, hole, hole, seg.px(3))
        for j in range(5):
            gx, gy = cx + rng.uniform(-1.6, 1.6) * r, cy + rng.uniform(-0.8, 0.8) * r
            g = poly_mask(seg.shape, jagged(rng, gx, gy, seg.px(7), seg.px(5), 5, 0.2)) & region & ~hole
            out[g, :3] = np.array([0.62, 0.6, 0.62], np.float32)
            out = outline_shape(out, g, g, seg.px(2))
    return out


def scatter_shapes(out, seg, region, n, seed, size, colours, kind="leaf"):
    rng = np.random.default_rng(seed)
    ys, xs = np.nonzero(ndimage.binary_erosion(region, iterations=seg.px(10)))
    if len(xs) == 0:
        return out
    for i in range(n):
        k = rng.integers(0, len(xs))
        cx, cy = xs[k], ys[k]
        r = seg.px(size * rng.uniform(0.7, 1.3))
        a_ = rng.uniform(0, math.pi)
        if kind == "leaf":
            pts = [(cx + math.cos(a_) * r, cy + math.sin(a_) * r * 0.5), (cx + math.cos(a_ + 1.6) * r * 0.45, cy + math.sin(a_ + 1.6) * r * 0.25),
                   (cx - math.cos(a_) * r, cy - math.sin(a_) * r * 0.5), (cx - math.cos(a_ + 1.6) * r * 0.45, cy - math.sin(a_ + 1.6) * r * 0.25)]
        elif kind == "paper":
            pts = jagged(rng, cx, cy, r, r * 0.55, 5, 0.25)
        else:  # can / bottle: small capsule
            pts = [(cx - r, cy - r * 0.3), (cx + r, cy - r * 0.6), (cx + r, cy + r * 0.1), (cx - r, cy + r * 0.4)]
        m = poly_mask(seg.shape, pts) & region
        out[m, :3] = colours[int(rng.integers(0, len(colours)))]
        out = outline_shape(out, m, m, seg.px(2))
    return out


def surface_layer(a, seg, state, seed):
    region = LS.top_face(seg)
    dark = float(LS.lum(a[region, :3]).mean()) < 0.4 if region.any() else False
    if dark and state == "verschmutzt":
        return dark_dirt(a.copy(), seg, region, seed)
    if dark and state == "schlagloecher":
        return potholes_dark(a.copy(), seg, region, seed)
    if dark and state == "rissig":
        o = LS.surface_state(a, seg, state, seed, region=region)
        crack = (np.abs(o - a).max(-1) > 0.05) & region
        hl = np.roll(crack, seg.px(3), axis=0) & ~crack & region
        o[hl, :3] = np.clip(a[hl, :3] * 1.5 + 0.06, 0, 1)
        return o
    if state == "laub":
        return scatter_shapes(a.copy(), seg, region, 26, seed, 16, LEAF_COLOURS, "leaf")
    if state == "muell":
        o = scatter_shapes(a.copy(), seg, region, 9, seed, 18, [np.array([0.95, 0.95, 0.9], np.float32), np.array([0.85, 0.82, 0.7], np.float32)], "paper")
        return scatter_shapes(o, seg, region, 5, seed + 1, 12, [np.array([0.75, 0.2, 0.2], np.float32), np.array([0.3, 0.55, 0.75], np.float32), np.array([0.45, 0.6, 0.3], np.float32)], "can")
    if state == "trocken":
        o = a.copy()
        green = region & (seg.hsv[..., 0] > 0.15) & (seg.hsv[..., 0] < 0.45) & (seg.hsv[..., 1] > 0.2)
        hsv = LS.rgb_to_hsv(o[..., :3])
        hsv[green, 0] = hsv[green, 0] * 0.5 + 0.03
        hsv[green, 1] *= 0.8
        o[..., :3] = np.where(green[..., None], LS.hsv_to_rgb(hsv), o[..., :3])
        return o
    if state in ("gefroren", "algen"):
        o = a.copy()
        if state == "algen":
            o = recolour(o, region & ~seg.outline, np.array([0.36, 0.52, 0.30], np.float32), 0.55)
            f = smooth_field(seg.shape, seg.px(10), seed)
            m = region & (f > 0.62) & ~seg.outline
            o[m, :3] = MOSS_DARK
            return outline_shape(o, m, m, seg.px(2))
        o[region & ~seg.outline, :3] = LS.SNOW_SHADE * 0.9 + np.array([0.0, 0.03, 0.06], np.float32)
        hi = region & (smooth_field(seg.shape, seg.px(9), seed) > 0.68) & ~seg.outline
        o[hi, :3] = LS.SNOW
        return LS.cracks(o, seg, 3, seed + 1, region=region & ~seg.outline)
    return LS.surface_state(a, seg, state, seed, region=region)


def water_state(a, seg, state, seed):
    """Fountains/ponds: algae (murky green), drained (dry basin), frozen."""
    o = a.copy()
    w = seg.m("water")
    if not w.any():
        return o
    if state == "algen":
        o = recolour(o, w, np.array([0.36, 0.52, 0.30], np.float32), 0.6)
        f = smooth_field(seg.shape, seg.px(6), seed)
        m = w & (f > 0.6)
        o[m, :3] = MOSS_DARK
        o = outline_shape(o, m, m, seg.px(2))
    elif state == "ausgetrocknet":
        o[w, :3] = np.array([0.62, 0.56, 0.48], np.float32)
        o = LS.cracks(o, seg, 3, seed, region=w)
        o = recolour(o, edge_of(w, seg.px(5)), GRIME, 0.5)
    elif state == "gefroren":
        o[w, :3] = LS.SNOW_SHADE * 0.9 + np.array([0.0, 0.03, 0.06], np.float32)
        hi = w & (smooth_field(seg.shape, seg.px(5), seed) > 0.7)
        o[hi, :3] = LS.SNOW
        o = LS.cracks(o, seg, 2, seed + 1, region=w)
    return o


def interior_variant(a, state, seed):
    return LS.pixel_state(a, state, seed)


# --- profiles: which bases / layers each kind of asset gets ------------------------------------
# Decided by FUNCTION (docs/living_assets/STATE_MATRIX.md): a hydrant does not
# need a 'ruin', a tree does not need 'restored'.

def _b(fn):
    return lambda a, seg, seed: fn(a, seg, seed)


PROFILES = {
    "building": {
        "bases": STRUCTURES,
        "layers": LAYERS,
    },
    "tent": {
        "bases": {"shell": structure_shell, "collapsed": tent_collapse},
        "layers": {k: LAYERS[k] for k in ("wear_2", "wear_3", "damage_1", "fire_1", "repair_1", "snow_1")},
    },
    "prop": {
        "bases": {"broken": prop_broken},
        "layers": {"wear_2": (prop_wear, 2), "wear_3": (prop_wear, 3), "damage_1": (prop_damage, 1), "overgrowth_1": (overgrowth_layer, 1), "snow_1": (snow_layer, 1)},
    },
    "prop_flammable": {
        "bases": {"broken": prop_broken, "burnt": prop_burnt},
        "layers": {"wear_2": (prop_wear, 2), "wear_3": (prop_wear, 3), "damage_1": (prop_damage, 1), "overgrowth_1": (overgrowth_layer, 1), "snow_1": (snow_layer, 1)},
    },
    "lamp": {   # lighting: broken glass = no light (runtime), knocked over
        "bases": {"broken": prop_broken},
        "layers": {"wear_2": (prop_wear, 2), "wear_3": (prop_wear, 3), "damage_1": (prop_damage, 1), "snow_1": (snow_layer, 1)},
    },
    "vehicle": {
        "bases": {"burnt": vehicle_burnt, "wreck": vehicle_wreck},
        "layers": {"wear_2": (vehicle_wear, 2), "wear_3": (vehicle_wear, 3), "damage_1": (vehicle_damage, 1), "snow_1": (snow_layer, 1)},
    },
    "tree": {
        "bases": {"dry": lambda a, s, sd: veg_variant(a, s, "trocken", sd), "dead": lambda a, s, sd: veg_variant(a, s, "abgestorben", sd), "burnt": lambda a, s, sd: veg_variant(a, s, "verbrannt", sd)},
        "layers": {"snow_1": (snow_layer, 1)},
    },
    "crop": {
        "bases": {"dry": lambda a, s, sd: veg_variant(a, s, "trocken", sd), "dead": lambda a, s, sd: veg_variant(a, s, "abgestorben", sd), "burnt": lambda a, s, sd: veg_variant(a, s, "verbrannt", sd)},
        "layers": {},
    },
    "fountain": {
        "bases": {"algae": lambda a, s, sd: water_state(a, s, "algen", sd), "drained": lambda a, s, sd: water_state(a, s, "ausgetrocknet", sd), "frozen": lambda a, s, sd: water_state(a, s, "gefroren", sd)},
        "layers": {"wear_2": (prop_wear, 2), "damage_1": (prop_damage, 1), "overgrowth_1": (overgrowth_layer, 1), "snow_1": (snow_layer, 1)},
    },
}

SURFACE_FAMILIES = {
    # family: layers that make sense on it
    "asphalt": ["verschmutzt", "rissig", "schlagloecher", "pfuetzen", "schnee", "frost", "laub", "muell"],
    "sidewalk": ["verschmutzt", "rissig", "pfuetzen", "schnee", "frost", "laub", "muell"],
    "path": ["pfuetzen", "schlamm", "schnee", "frost", "laub"],
    "grass": ["trocken", "schlamm", "pfuetzen", "schnee", "frost", "laub"],
    "dirt": ["pfuetzen", "schlamm", "schnee", "frost"],
    "water": ["gefroren", "algen"],
}
INTERIOR_STATES = ["abgenutzt", "verschmutzt", "kaputt", "verbrannt"]
