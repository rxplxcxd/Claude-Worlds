"""Materials for the World Council in the Penzilla look: flat three-tone
shading, banded curved surfaces, procedural detail. Each material is a
function (pos, normal, cut) -> rgb. `cut` marks surfaces created by a cutter
(window/door openings, niches) -> deep shadow colour."""
import math
import numpy as np
from isorender import LIGHT, hexc, vnoise, fbm

DARK = hexc('3b2342')        # openings, deep interior (Penzilla plum shadow)
SHADOW = hexc('b8a9a8')


def bright(n, quant=0.0):
    lam = np.clip(n @ LIGHT, -0.2, 1.0)
    b = 0.6 + 0.46 * lam
    if quant:
        b = np.round(b / quant) * quant
    return b


def _is_top(n):
    return n[:, 2] > 0.72


def _vertical_coord(p, n):
    """Horizontal coordinate along a vertical face."""
    return np.where(np.abs(n[:, 0]) > np.abs(n[:, 1]), p[:, 1], p[:, 0])


def _line(v, period, width):
    f = np.mod(v, period)
    return (f < width) | (f > period - width)


def stone(base_hex, course=1.1, block=2.2, joint_dark=0.86, weather=0.10, seed=1):
    base = hexc(base_hex)

    def f(p, n, cut):
        b = bright(n, 0.0)
        col = base[None, :] * b[:, None]
        # per-block tint + weathering stains
        top = _is_top(n)
        h = _vertical_coord(p, n)
        row = np.floor(p[:, 2] / course)
        stag = (row % 2) * block * 0.5
        jy = _line(p[:, 2], course, 0.045)
        jx = _line(h + stag, block, 0.04)
        joint = (~top) & (jy | jx) & (np.abs(n[:, 2]) < 0.4)
        stain = fbm(p, 6.0, seed) > 0.58
        streak = vnoise(p * np.array([1, 1, 0.12]), 1.3, seed + 3) > 0.72
        k = np.ones(len(p))
        k = np.where(stain, 1.0 - weather, k)
        k = np.where(streak & ~top, k * (1.0 - weather * 0.6), k)
        k = np.where(joint, k * joint_dark, k)
        col = col * k[:, None]
        d = cut == 1
        col[d] = DARK * (0.85 + 0.25 * bright(n[d])[:, None])
        col[cut == 2] *= 0.8
        return col
    return f


def flat(base_hex, quant=0.0, cut_dark=True):
    base = hexc(base_hex)

    def f(p, n, cut):
        col = base[None, :] * bright(n, quant)[:, None]
        if cut_dark:
            col[cut == 1] = DARK
            col[cut == 2] *= 0.8
        return col
    return f


def column(base_hex, flutes=20):
    base = hexc(base_hex)

    def f(p, n, cut):
        b = bright(n, 0.07)
        ang = np.arctan2(n[:, 1], n[:, 0])
        fl = (np.mod(ang * flutes / (2 * math.pi), 1.0) < 0.22) & (np.abs(n[:, 2]) < 0.3)
        k = np.where(fl, 0.9, 1.0)
        stain = fbm(p, 4.0, 9) > 0.64
        k = np.where(stain, k * 0.95, k)
        return base[None, :] * (b * k)[:, None]
    return f


def paving(base_hex, slab=2.4, seed=4, moss=0.0):
    base = hexc(base_hex)
    moss_c = hexc('8fa55a')

    def f(p, n, cut):
        b = bright(n)
        top = _is_top(n)
        jx = _line(p[:, 0], slab, 0.06)
        jy = _line(p[:, 1] + np.floor(p[:, 0] / slab) % 2 * slab * 0.5, slab, 0.06)
        ix = np.floor(p[:, 0] / slab)
        iy = np.floor((p[:, 1] + (ix % 2) * slab * 0.5) / slab)
        tint = 0.95 + 0.07 * vnoise(np.stack([ix * 3.1, iy * 2.7, ix * 0 + 1], 1), 1.0, seed)
        k = np.where(top & (jx | jy), 0.84, tint)
        col = base[None, :] * (b * k)[:, None]
        if moss > 0:
            m = top & (fbm(p, 7.0, seed + 2) > 1.0 - moss) & ((jx | jy) | (vnoise(p, 1.1, seed + 5) > 0.6))
            col[m] = moss_c * b[m, None]
        col[cut == 1] = DARK
        col[cut == 2] *= 0.8
        return col
    return f


def mosaic(c1, c2, c3, centre, ring=1.6):
    a, bb, cc = hexc(c1), hexc(c2), hexc(c3)
    cx, cy = centre

    def f(p, n, cut):
        r = np.hypot(p[:, 0] - cx, p[:, 1] - cy)
        ang = np.arctan2(p[:, 1] - cy, p[:, 0] - cx)
        band = np.floor(r / ring).astype(int) % 3
        star = (np.mod(ang * 8 / (2 * math.pi) + r * 0.08, 1.0) < 0.5)
        col = np.where((band == 0)[:, None], a, np.where((band == 1)[:, None], bb, cc))
        col = np.where((star & (band == 2))[:, None], a, col)
        return col * bright(n)[:, None]
    return f


def water(base_hex='4aa6c9', light_hex='a7e0ee', murky=0.0, seed=7):
    base = hexc(base_hex)
    light = hexc(light_hex)
    murk = hexc('4f8a76')

    def f(p, n, cut):
        if murky:
            col = base * (1 - murky) + murk * murky
        else:
            col = base
        col = np.repeat(col[None, :], len(p), 0)
        top = _is_top(n)
        wave = np.sin(p[:, 0] * 1.7 + np.sin(p[:, 1] * 0.9) * 2.0) + np.sin(p[:, 1] * 1.3 + p[:, 0] * 0.4)
        hl = top & (wave > 1.55) & (vnoise(p, 2.0, seed) > 0.45)
        col[hl] = light
        # falling water (vertical sheets): streaks
        vert = ~top
        st = vert & (np.mod((p[:, 0] + p[:, 1]) * 2.3, 1.0) < 0.35)
        col[st] = light
        col[vert & ~st] = base * 1.08
        return col
    return f


def foliage(base_hex='5f9e3f', light_hex='86bf4f', dark_hex='3d7432', scale=1.6, seed=11):
    base, light, dark = hexc(base_hex), hexc(light_hex), hexc(dark_hex)

    def f(p, n, cut):
        lam = n @ LIGHT
        nz = fbm(p, scale, seed, 2)
        v = lam + (nz - 0.5) * 0.9
        col = np.where((v > 0.62)[:, None], light, np.where((v < 0.18)[:, None], dark, base))
        return col
    return f


def grass(base_hex='8cc04f', seed=13):
    base = hexc(base_hex)
    alt = hexc('7db446')
    dry = hexc('b5b768')

    def f(p, n, cut):
        nz = fbm(p, 9.0, seed, 3)
        col = np.where((nz > 0.56)[:, None], alt, base)
        col = np.where((nz < 0.3)[:, None], dry, col)
        tuft = vnoise(p, 0.55, seed + 1) > 0.8
        col = np.where(tuft[:, None], col * 0.9, col)
        return col * bright(n)[:, None]
    return f


def roof_tiles(base_hex='c96a3f', seed=17):
    base = hexc(base_hex)

    def f(p, n, cut):
        b = bright(n)
        # tiles run down the slope: lines across the ridge direction
        along = np.where(np.abs(n[:, 0]) > np.abs(n[:, 1]), p[:, 1], p[:, 0])
        rib = _line(along, 0.9, 0.08)
        course = _line(p[:, 2], 0.55, 0.05)
        k = np.where(rib | course, 0.82, 1.0)
        k *= 0.94 + 0.1 * vnoise(p, 3.0, seed)
        return base[None, :] * (b * k)[:, None]
    return f


def dome(base_hex='5d9f94', rib_hex='e2b23c', centre=(0, 0), ribs=16, rings=(0.0,), rib_w=0.07):
    base = hexc(base_hex)
    rib = hexc(rib_hex)
    cx, cy = centre

    def f(p, n, cut):
        b = bright(n, 0.06)
        ang = np.arctan2(p[:, 1] - cy, p[:, 0] - cx)
        rb = np.mod(ang * ribs / (2 * math.pi), 1.0) < rib_w
        col = base[None, :] * b[:, None]
        col[rb] = rib * b[rb, None]
        # weathering streaks on the patina
        st = vnoise(p * np.array([1, 1, 0.15]), 1.2, 23) > 0.7
        col[st & ~rb] *= 0.9
        return col
    return f


def gold(base_hex='e2b23c'):
    base = hexc(base_hex)
    hi = hexc('fbe7a1')

    def f(p, n, cut):
        lam = n @ LIGHT
        col = base[None, :] * np.where(lam > 0.35, 1.0, 0.8)[:, None]
        col[lam > 0.83] = hi
        return col
    return f


def inscription(base_hex, gold_hex='d9a836', z0=0.0, z1=1.0, seed=31):
    """Entablature band with gilded block letters on vertical faces."""
    base = hexc(base_hex)
    g = hexc(gold_hex)

    def f(p, n, cut):
        b = bright(n)
        col = base[None, :] * b[:, None]
        vert = np.abs(n[:, 2]) < 0.3
        h = _vertical_coord(p, n)
        zz = (p[:, 2] - z0) / max(z1 - z0, 1e-6)
        inband = (zz > 0.3) & (zz < 0.72)
        cell = np.floor(h / 0.42)
        on = (np.mod(h, 0.42) < 0.32) & (vnoise(np.stack([cell, zz * 0 + 3, cell * 0], 1), 1.0, seed) > 0.25)
        strokes = (np.mod(h * 7.1 + np.floor(zz * 3) * 1.7, 1.0) < 0.55)
        m = vert & inband & on & strokes
        col[m] = g * b[m, None]
        return col
    return f


def flowers(seed=41):
    leaf = hexc('5f9e3f')
    cols = [hexc('f2d14b'), hexc('e8697a'), hexc('f4f1ea'), hexc('b57bd6')]

    def f(p, n, cut):
        col = np.repeat(leaf[None, :], len(p), 0) * bright(n)[:, None]
        cell = np.floor(p[:, :2] / 0.45)
        h = vnoise(np.stack([cell[:, 0], cell[:, 1], cell[:, 0] * 0], 1), 1.0, seed)
        f2 = np.mod(p[:, :2] / 0.45, 1.0)
        dot = (np.hypot(f2[:, 0] - 0.5, f2[:, 1] - 0.5) < 0.28) & (h > 0.35)
        pick = (h * 13).astype(int) % 4
        for k in range(4):
            m = dot & (pick == k)
            col[m] = cols[k]
        return col
    return f


def make_materials(centre_dome=(0, 0), forum_centre=(0, 0), moss=0.25, small_domes=None, mosaics=None):
    extra = {}
    for name, c in (small_domes or {}).items():
        extra[name] = dome(centre=c, ribs=12, rib_w=0.09)
    for name, c in (mosaics or {}).items():
        extra[name] = mosaic('efe6d4', 'c99a6b', '9ab7ae', c, ring=1.2)
    return extra | {
        'marble': stone('f3ede1', weather=0.06),
        'marble_warm': stone('ead8b8', weather=0.07, seed=2),
        'sandstone': stone('dcc39a', course=0.9, block=1.8, weather=0.09, seed=3),
        'marble_shade': stone('cdbfb2', weather=0.06, seed=5),
        'column': column('f5f0e6'),
        'column_warm': column('ecdcbf'),
        'paving': paving('e8dcc6', moss=moss),
        'paving_dark': paving('cbbca2', slab=1.6, seed=6, moss=moss),
        'mosaic': mosaic('efe6d4', 'c99a6b', '9ab7ae', forum_centre),
        'water': water(),
        'water_murky': water('3f8fa3', '93cfd9', murky=0.28, seed=8),
        'foliage': foliage(),
        'cypress': foliage('3f6f38', '5d9244', '2a5029', scale=1.1, seed=12),
        'ivy': foliage('4f8a3a', '6aa748', '33612b', scale=0.7, seed=14),
        'grass': grass(),
        'roof': roof_tiles(),
        'dome': dome(centre=centre_dome),
        'gold': gold(),
        'bronze': flat('a8703a', 0.06),
        'dark': flat('3b2342', 0.0, cut_dark=False),
        'flowers': flowers(),
        'earth': flat('a07a52', 0.0),
        'inscription': inscription('efe6d4', z0=0.0, z1=1.0),
    }


STONE = ('marble', 'marble_warm', 'sandstone', 'marble_shade', 'column', 'column_warm', 'paving', 'paving_dark')


def overgrowth(amount=1.0, seed=51):
    """Stage-dependent ivy/moss decal on stone: climbs from the ground and
    hangs from ledges, darker rim around each patch (Penzilla 'overgrown'
    living state)."""
    ivy = hexc('5a9440')
    ivy_l = hexc('7cb34e')
    ivy_d = hexc('35652e')

    def f(pos, nrm, color, mids, names):
        if amount <= 0:
            return color
        stone_ids = [i for i, n in enumerate(names) if n in STONE]
        sel = np.isin(mids, stone_ids)
        if not sel.any():
            return color
        p = pos[sel]
        n = nrm[sel]
        z = p[:, 2]
        base = fbm(p, 3.2, seed, 3)
        ground = np.clip(1.0 - z / 5.0, 0.0, 1.0) * 0.07 - (n[:, 2] > 0.72) * 0.05
        hang = (vnoise(p * np.array([1, 1, 0.22]), 1.4, seed + 4) > 0.9) & (base > 0.56)
        score = base + ground - (0.69 - 0.05 * amount)
        patch = (score > 0.0) | hang
        rim = (score > -0.02) & ~patch
        c = color[sel]
        leaf = vnoise(p, 0.45, seed + 9)
        lam = n @ LIGHT
        tone = np.where((leaf > 0.62)[:, None], ivy_l, np.where((leaf < 0.3)[:, None], ivy_d, ivy))
        tone = tone * (0.85 + 0.2 * np.clip(lam, 0, 1))[:, None]
        c[patch] = tone[patch]
        c[rim] = c[rim] * 0.78
        color[sel] = c
        return color
    return f


FONT = '/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf'


def _text_mask(lines, w_m, h_m, ppm=48):
    """Roman capitals, centred, rendered to a mask (h, w) of 0..1.
    lines: [(text, rel_height)] with rel_height = share of the panel height."""
    from PIL import Image, ImageDraw, ImageFont
    W, H = max(8, int(w_m * ppm)), max(8, int(h_m * ppm))
    im = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(im)
    total = sum(r for _, r in lines)
    y = H * (1 - total) / 2
    for text, rel in lines:
        size = int(H * rel * 0.86)
        font = ImageFont.truetype(FONT, size)
        spaced = ' '.join(text) if len(text) < 12 else text   # wide letter spacing like Roman inscriptions
        tw = d.textlength(spaced, font=font)
        while tw > W * 0.94 and size > 6:
            size -= 1
            font = ImageFont.truetype(FONT, size)
            tw = d.textlength(spaced, font=font)
        bbox = d.textbbox((0, 0), spaced, font=font)
        d.text(((W - tw) / 2, y + (H * rel - (bbox[3] - bbox[1])) / 2 - bbox[1]), spaced, fill=255, font=font)
        y += H * rel
    return np.asarray(im, np.float32) / 255.0


def lettering(base_hex, panels, gold_hex='d9a836', fallback=None):
    """Gilded inscriptions on +Y facing panels (portico frieze, gate attic).
    panels: [{y, x0, x1, z0, z1, lines}] in metres; other faces use `fallback`."""
    base = hexc(base_hex)
    g = hexc(gold_hex)
    shade = hexc('a67a22')
    masks = [(pnl, _text_mask(pnl['lines'], pnl['x1'] - pnl['x0'], pnl['z1'] - pnl['z0'])) for pnl in panels]

    def f(p, n, cut):
        col = fallback(p, n, cut) if fallback else base[None, :] * bright(n)[:, None]
        front = n[:, 1] > 0.9
        for pnl, m in masks:
            sel = front & (np.abs(p[:, 1] - pnl['y']) < 0.08) & (p[:, 0] >= pnl['x0']) & (p[:, 0] <= pnl['x1']) & \
                (p[:, 2] >= pnl['z0']) & (p[:, 2] <= pnl['z1'])
            if not sel.any():
                continue
            h, w = m.shape
            u = np.clip(((p[sel, 0] - pnl['x0']) / (pnl['x1'] - pnl['x0']) * w).astype(int), 0, w - 1)
            v = np.clip(((pnl['z1'] - p[sel, 2]) / (pnl['z1'] - pnl['z0']) * h).astype(int), 0, h - 1)
            a = m[v, u]
            # engraved look: a darker gold edge below/right of each stroke
            a2 = m[np.clip(v - 2, 0, h - 1), np.clip(u - 2, 0, w - 1)]
            c = col[sel]
            edge = (a2 > 0.5) & (a <= 0.5)
            c[edge] = shade
            c[a > 0.5] = g
            col[sel] = c
        return col
    return f
