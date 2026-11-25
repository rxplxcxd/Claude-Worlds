"""Own interior pixel art for WORLDS (docs/INTERIOR_STANDARD.md).

The bought Penzilla "Top-Down Retro Interior" pack and Kenney "Roguelike
Indoors" (CC0) use a straight 3/4 view: square floor tiles of 16 px, x to the
right, south down, height drawn straight up. Everything the packs lack (beds,
wardrobes, bathroom, shop, workshop, clinic, utility and the whole antique
Concordium set) is built here from solids and rendered with the SAME camera:
  * oblique projection, 1 tile = 16 px, height 1 tile = 16 px up,
  * no anti-aliasing, 1-px contour, soft inner creases,
  * colours quantised to the palette of the Penzilla interior sheets (plus a
    few heraldic colours), so the new pieces sit next to the bought ones.
Output: assets/interior/worlds/<id>.png (own art, may be public) and
data/interiors/worlds_items.json (atlas entries: rect, solid = footprint).

Usage: python -I interior_assets.py [sheet_dir_with_penzilla_pngs]
"""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import isorender as ir
from isorender import Scene, box, cyl, hcyl, ell, prism_gable, oriented_box

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'interior', 'worlds')
PX = 16
INK = np.array([0x3b, 0x23, 0x18]) / 255.0        # Penzilla interior contour (dark brown)
EXTRA = ['c9d0d4', 'b4bcc2', '8d8f94', 'e9eef0', '4a4a52', 'a9cdd8', 'f2f0ea', 'b8312f', '2f5d9e', '3f8a4a', 'e0b64a', '6b3f8e', 'f2efe6', '1f2a44', 'c9d8de', '9fc6d6', '4aa6c9', 'e8782e']


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)]) / 255.0


def palette(sheet_dir):
    cols = {}
    for n in ('TopDownHouse_FurnitureState1', 'TopDownHouse_FurnitureState2', 'TopDownHouse_SmallItems',
              'TopDownHouse_FloorsAndWalls', 'TopDownHouse_DoorsAndWindows'):
        p = os.path.join(sheet_dir, n + '.png')
        if not os.path.exists(p):
            continue
        a = np.asarray(Image.open(p).convert('RGBA')).reshape(-1, 4)
        a = a[a[:, 3] > 200][:, :3]
        u, c = np.unique(a, axis=0, return_counts=True)
        for col, cnt in zip(u, c):
            cols[tuple(col)] = cols.get(tuple(col), 0) + cnt
    pal = [np.array(k) / 255.0 for k, v in cols.items() if v >= 12]
    pal += [hexc(h) for h in EXTRA]
    return np.array(pal)


# ---------------------------------------------------------------- materials

def bright(n):
    # oblique view: top faces light, south faces mid, others darker
    top = n[:, 2] > 0.6
    front = n[:, 1] > 0.6
    b = np.where(top, 1.0, np.where(front, 0.8, 0.68))
    curved = ~(top | front) & (np.abs(n[:, 0]) < 0.95)
    lam = np.clip(n @ np.array([-0.3, 0.6, 0.75]), 0, 1)
    b = np.where(curved, np.round((0.62 + 0.4 * lam) * 6) / 6, b)
    return b


def flat(h):
    c = hexc(h)
    def f(p, n, cut):
        col = c[None, :] * bright(n)[:, None]
        col[cut == 1] = hexc('2a1810')
        col[cut == 2] *= 0.78
        return col
    return f


def wood(h, grain=0.35):
    c = hexc(h)
    def f(p, n, cut):
        col = c[None, :] * bright(n)[:, None]
        g = (np.mod(np.floor(p[:, 0] * 5 + np.floor(p[:, 2] * 3) * 1.7), 4) == 0) & (n[:, 1] > 0.6)
        col[g] *= 1 - grain * 0.3
        col[cut == 1] = hexc('2a1810')
        col[cut == 2] *= 0.78
        return col
    return f


def stripes(cols, period=0.25, axis=0):
    cs = [hexc(h) for h in cols]
    def f(p, n, cut):
        k = (np.floor(p[:, axis] / period).astype(int)) % len(cs)
        col = np.stack([cs[i] for i in k]) if len(k) else np.zeros((0, 3))
        return col * bright(n)[:, None]
    return f


def books():
    cs = [hexc(h) for h in ('8a2f2a', '2f4f7a', '3f6a3a', 'b0812e', '5a3a6a', 'c9b38a', '7a4a2a')]
    def f(p, n, cut):
        k = (np.floor(p[:, 0] * 6.4).astype(int) * 7 + np.floor(p[:, 2] * 1.1).astype(int) * 3) % len(cs)
        col = np.stack([cs[i] for i in k]) if len(k) else np.zeros((0, 3))
        return col * bright(n)[:, None]
    return f


def marble(h='efe8dc'):
    c = hexc(h)
    def f(p, n, cut):
        col = c[None, :] * bright(n)[:, None]
        v = np.abs(np.sin(p[:, 0] * 3.1 + p[:, 2] * 2.3 + np.sin(p[:, 1] * 4.0))) < 0.05
        col[v] *= 0.86
        col[cut == 1] = hexc('2a1810')
        col[cut == 2] *= 0.8
        return col
    return f


def fire():
    a, b = hexc('f6c445'), hexc('e8782e')
    def f(p, n, cut):
        return np.where((np.mod(np.floor(p[:, 0] * 8 + p[:, 2] * 5), 3) == 0)[:, None], a, b)
    return f


def dots(base, cols, scale=0.22):
    bc = hexc(base)
    cs = [hexc(h) for h in cols]
    def f(p, n, cut):
        col = np.repeat(bc[None, :], len(p), 0)
        cell = np.floor(p[:, :2] / scale).astype(int)
        h = (cell[:, 0] * 73856093 ^ cell[:, 1] * 19349663) % 997
        for i, c in enumerate(cs):
            m = (h % len(cs) == i) & (h % 3 != 0)
            col[m] = c
        return col * bright(n)[:, None]
    return f


MATS = {
    'wood': wood('9a5f37'), 'wood_dark': wood('6e3f25'), 'wood_light': wood('c99a62'),
    'linen': flat('efe9dc'), 'pillow': flat('f7f3ea'), 'blanket_red': flat('a8443a'), 'blanket_blue': flat('3f6a9e'),
    'blanket_green': flat('6f8a3a'), 'blanket_ochre': flat('c98a3a'), 'canvas': flat('b7a37a'),
    'metal': flat('8d8f94'), 'chrome': flat('c9d0d4'), 'iron': flat('4a4a52'), 'white': flat('f2f0ea'),
    'ceramic': flat('e9eef0'), 'glass': flat('a9cdd8'), 'water': flat('4aa6c9'), 'plant': dots('4f8a3a', ['6aa748', '35652e']),
    'soil': flat('6b4a2e'), 'paper': flat('efe6cf'), 'brick': stripes(['a24a2e', '8a3b25'], 0.33, 2), 'stone': flat('9a948c'),
    'fire': fire(), 'leather': flat('7a3f2a'), 'books': books(), 'bread': dots('c98a46', ['a8682e', 'e0b070']),
    'veg': dots('6f8a3a', ['b8312f', 'e8782e', 'e0b64a', '3f8a4a']), 'goods': dots('c99a62', ['b8312f', '2f5d9e', 'e0b64a', 'f2efe6']),
    'red': flat('b8312f'), 'blue': flat('2f5d9e'), 'green': flat('3f8a4a'), 'purple': flat('6b3f8e'), 'navy': flat('1f2a44'),
    'gold': flat('e0b64a'), 'bronze': flat('a8703a'), 'marble': marble(), 'marble_dark': marble('b9ad9c'),
    'marble_warm': marble('e6d2b0'), 'teal': flat('5f9e93'), 'cork': dots('b8875a', ['f2efe6', 'efe6cf', 'e0b64a']),
    'screen_green': flat('6fbf8a'), 'lamp': flat('f6e7a8'), 'rope': flat('c9a46a'), 'crimson': flat('8a2034'),
}


# ---------------------------------------------------------------- pieces

def chair(sc, x, y, mat='wood', back='n'):
    sc.add(box(x, y + 0.35, 0, x + 0.8, y + 0.95, 0.55, mat))
    if back == 'n':
        sc.add(box(x, y + 0.25, 0.55, x + 0.8, y + 0.4, 1.35, mat))
    else:
        sc.add(box(x, y + 0.9, 0.55, x + 0.8, y + 1.05, 1.35, mat))


def bed(sc, w, blanket, double=False, frame='wood'):
    d = 3.4
    sc.add(box(0, 0, 0, w, 0.3, 1.7, frame))                 # headboard
    sc.add(box(0, 0.3, 0.15, w, d, 0.5, frame))              # frame
    sc.add(box(0.1, 0.3, 0.5, w - 0.1, d - 0.1, 0.8, 'linen'))
    sc.add(box(0.05, 1.3, 0.55, w - 0.05, d - 0.05, 0.92, blanket))
    sc.add(box(0.05, 1.25, 0.8, w - 0.05, 1.55, 0.97, 'linen'))  # turned-down sheet
    for k in range(2 if double else 1):
        cx = w / 2 if not double else (w * (0.27 + 0.46 * k))
        sc.add(ell(cx, 0.75, 0.95, 0.55 if not double else 0.6, 0.35, 0.22, 'pillow'))
    sc.add(box(0, d - 0.15, 0, w, d, 0.75, frame))            # footboard
    return (w, d)


def build_items():
    items = {}

    def item(name, label, fp, fn, wall=False, action=None, pivot=None):
        sc = Scene()
        fn(sc)
        items[name] = {'scene': sc, 'label': label, 'fp': fp, 'wall': wall, 'action': action, 'pivot': pivot}

    # -- bedroom
    for col, nm in (('blanket_red', 'red'), ('blanket_blue', 'blue'), ('blanket_green', 'green'), ('blanket_ochre', 'ochre')):
        item(f'bed_single_{nm}', 'Bett', (1.9, 3.4), lambda sc, c=col: bed(sc, 1.9, c), action='sleep')
        item(f'bed_double_{nm}', 'Doppelbett', (2.9, 3.4), lambda sc, c=col: bed(sc, 2.9, c, True), action='sleep')
    item('mattress_floor', 'Matratze', (1.9, 3.2), lambda sc: (
        sc.add(box(0, 0, 0, 1.9, 3.2, 0.35, 'linen')), sc.add(box(0.05, 1.1, 0.35, 1.85, 3.15, 0.45, 'blanket_ochre')),
        sc.add(ell(0.95, 0.55, 0.42, 0.55, 0.32, 0.15, 'pillow'))), action='sleep')
    item('bed_guest', 'Gästebett', (2.0, 3.4), lambda sc: bed(sc, 2.0, 'crimson', frame='wood_dark'), action='sleep')
    item('cot', 'Feldbett', (1.4, 3.2), lambda sc: (
        [sc.add(box(x, y, 0, x + 0.12, y + 0.12, 0.45, 'metal')) for x in (0.05, 1.23) for y in (0.1, 3.0)],
        sc.add(box(0, 0.1, 0.4, 1.4, 3.2, 0.55, 'canvas')), sc.add(box(0.1, 1.0, 0.55, 1.3, 3.1, 0.68, 'blanket_green')),
        sc.add(ell(0.7, 0.55, 0.65, 0.45, 0.3, 0.16, 'pillow'))), action='sleep')
    item('wardrobe', 'Kleiderschrank', (2.6, 1.1), lambda sc: (
        sc.add(box(0, 0, 0, 2.6, 1.1, 2.8, 'wood')), sc.add(box(0.1, 1.05, 0.25, 1.25, 1.12, 2.6, 'wood_dark', cuts=[])),
        sc.add(box(1.35, 1.05, 0.25, 2.5, 1.12, 2.6, 'wood_dark')), sc.add(box(1.1, 1.1, 1.8, 1.2, 1.18, 2.2, 'gold')),
        sc.add(box(1.4, 1.1, 1.8, 1.5, 1.18, 2.2, 'gold')), sc.add(box(-0.05, -0.05, 2.8, 2.65, 1.15, 2.95, 'wood_dark'))), action='wardrobe')
    item('wardrobe_light', 'Kleiderschrank', (2.6, 1.1), lambda sc: (
        sc.add(box(0, 0, 0, 2.6, 1.1, 2.8, 'wood_light')), sc.add(box(0.1, 1.05, 0.25, 1.25, 1.12, 2.6, 'wood')),
        sc.add(box(1.35, 1.05, 0.25, 2.5, 1.12, 2.6, 'wood')), sc.add(box(1.1, 1.1, 1.8, 1.2, 1.18, 2.2, 'chrome')),
        sc.add(box(1.4, 1.1, 1.8, 1.5, 1.18, 2.2, 'chrome'))), action='wardrobe')
    # -- bathroom
    item('shower_cabin', 'Dusche', (1.9, 1.9), lambda sc: (
        sc.add(box(0, 0, 0, 1.9, 1.9, 0.25, 'ceramic')), sc.add(box(0.1, 0.1, 0.25, 1.8, 0.2, 2.8, 'ceramic')),
        sc.add(box(0.05, 1.8, 0.25, 1.85, 1.9, 2.5, 'glass')), sc.add(box(1.8, 0.1, 0.25, 1.9, 1.9, 2.5, 'glass')),
        sc.add(box(0.85, 0.2, 2.25, 1.05, 0.6, 2.4, 'chrome')), sc.add(cyl(0.95, 0.55, 2.15, 2.25, 0.22, 'chrome'))), action='shower')
    item('bath_cabinet', 'Spiegelschrank', (1.6, 0.4), lambda sc: (
        sc.add(box(0, 0, 0, 1.6, 0.4, 1.3, 'white')), sc.add(box(0.12, 0.38, 0.12, 1.48, 0.42, 1.18, 'glass'))), wall=True)
    item('towel_rack', 'Handtuchhalter', (1.4, 0.3), lambda sc: (
        sc.add(box(0, 0, 0.9, 1.4, 0.15, 1.0, 'chrome')), sc.add(box(0.15, 0.12, 0.0, 0.65, 0.22, 0.95, 'blanket_blue')),
        sc.add(box(0.75, 0.12, 0.15, 1.25, 0.22, 0.95, 'white'))), wall=True)
    item('bath_shelf', 'Badregal', (1.2, 0.8), lambda sc: (
        sc.add(box(0, 0, 0, 1.2, 0.8, 2.6, 'white')), sc.add(box(0.1, 0.75, 0.3, 1.1, 0.82, 0.8, 'blanket_blue')),
        sc.add(box(0.1, 0.75, 1.1, 1.1, 0.82, 1.6, 'white')), sc.add(box(0.1, 0.75, 1.9, 1.1, 0.82, 2.4, 'blanket_red'))))
    # -- kitchen
    item('kitchen_upper', 'Oberschrank', (2.5, 0.6), lambda sc: (
        sc.add(box(0, 0, 0, 2.5, 0.6, 1.3, 'wood')), sc.add(box(0.08, 0.58, 0.1, 1.2, 0.62, 1.2, 'wood_dark')),
        sc.add(box(1.3, 0.58, 0.1, 2.42, 0.62, 1.2, 'wood_dark'))), wall=True)
    item('pot_shelf', 'Topfregal', (2.2, 0.4), lambda sc: (
        sc.add(box(0, 0, 0.0, 2.2, 0.4, 0.12, 'wood_dark')),
        [sc.add(cyl(0.35 + 0.5 * k, 0.2, 0.12, 0.45, 0.2, 'iron' if k % 2 else 'bronze')) for k in range(4)]), wall=True)
    item('dining_set', 'Esstisch', (3.2, 2.6), lambda sc: (
        chair(sc, 0.35, -0.1), chair(sc, 2.05, -0.1),
        sc.add(box(0, 0.7, 0, 3.2, 1.9, 1.1, 'wood_light', cuts=[box(0.2, 0.6, -1, 3.0, 2.0, 0.95)])),
        sc.add(box(0, 0.7, 0.95, 3.2, 1.9, 1.15, 'wood_light')), sc.add(ell(1.6, 1.3, 1.25, 0.35, 0.25, 0.1, 'white')),
        chair(sc, 0.35, 1.7, back='s'), chair(sc, 2.05, 1.7, back='s')), action='eat')
    # -- shops
    item('shop_counter', 'Verkaufstresen', (4.0, 1.3), lambda sc: (
        sc.add(box(0, 0, 0, 4.0, 1.3, 1.6, 'wood')), sc.add(box(-0.05, -0.05, 1.6, 4.05, 1.35, 1.75, 'wood_light')),
        [sc.add(box(0.2 + k * 1.3, 1.28, 0.25, 1.2 + k * 1.3, 1.33, 1.35, 'wood_dark')) for k in range(3)],
        sc.add(box(2.9, 0.3, 1.75, 3.7, 0.9, 2.3, 'metal')), sc.add(box(3.0, 0.35, 2.3, 3.6, 0.5, 2.6, 'screen_green'))), action='browse')
    item('bread_shelf', 'Brotregal', (3.0, 0.9), lambda sc: (
        sc.add(box(0, 0, 0, 3.0, 0.9, 3.2, 'wood', cuts=[box(0.12, 0.2, 0.3, 2.88, 1.0, 3.0)])),
        [sc.add(box(0.12, 0.2, z, 2.88, 0.9, z + 0.08, 'wood_light')) for z in (0.9, 1.7, 2.5)],
        [sc.add(ell(0.45 + k * 0.52, 0.55, z + 0.25, 0.24, 0.3, 0.17, 'bread')) for z in (0.3, 0.98, 1.78, 2.58) for k in range(5)]), action='browse')
    item('goods_shelf', 'Warenregal', (3.0, 0.9), lambda sc: (
        sc.add(box(0, 0, 0, 3.0, 0.9, 3.4, 'wood_dark', cuts=[box(0.12, 0.2, 0.3, 2.88, 1.0, 3.2)])),
        [sc.add(box(0.12, 0.2, z, 2.88, 0.9, z + 0.08, 'wood')) for z in (1.0, 1.9, 2.8)],
        [sc.add(box(0.2 + k * 0.45, 0.35, z + 0.08, 0.55 + k * 0.45, 0.8, z + 0.5 + (k % 2) * 0.15, 'goods')) for z in (0.3, 1.0, 1.9, 2.8) for k in range(6)]), action='browse')
    item('veg_stand', 'Gemüsestand', (3.2, 1.6), lambda sc: (
        sc.add(box(0, 0, 0, 3.2, 1.6, 0.9, 'wood')),
        [sc.add(box(0.1 + k * 1.03, 0.1, 0.9, 1.05 + k * 1.03, 1.5, 1.35, 'wood_light', cuts=[box(0.18 + k * 1.03, 0.2, 1.05, 0.97 + k * 1.03, 1.4, 2)])) for k in range(3)],
        [sc.add(box(0.2 + k * 1.03, 0.22, 1.05, 0.95 + k * 1.03, 1.38, 1.25, 'veg')) for k in range(3)]), action='browse')
    item('bread_oven', 'Backofen', (3.0, 2.0), lambda sc: (
        sc.add(box(0, 0, 0, 3.0, 2.0, 2.4, 'brick', cuts=[box(0.8, 1.6, 0.6, 2.2, 2.2, 1.5), hcyl('y', 1.6, 2.2, 1.5, 1.5, 0.7)])),
        sc.add(box(0.8, 1.7, 0.6, 2.2, 1.8, 1.4, 'fire')), sc.add(prism_gable(0, 0, 3.0, 2.0, 2.4, 3.0, 'x', 'brick')),
        sc.add(box(1.2, 0.4, 3.0, 1.8, 1.0, 3.3, 'brick'))), action='bake')
    item('anvil', 'Amboss', (1.5, 1.0), lambda sc: (
        sc.add(cyl(0.75, 0.5, 0, 0.8, 0.5, 'wood_dark')), sc.add(box(0.25, 0.3, 0.8, 1.25, 0.7, 1.05, 'iron')),
        sc.add(box(0.05, 0.25, 1.05, 1.45, 0.75, 1.3, 'iron'))), action='forge')
    item('forge', 'Esse', (2.8, 2.0), lambda sc: (
        sc.add(box(0, 0, 0, 2.8, 2.0, 1.3, 'brick')), sc.add(box(0.4, 0.4, 1.3, 2.4, 1.6, 1.45, 'fire')),
        sc.add(box(0.2, 0.0, 2.3, 2.6, 1.4, 2.6, 'iron')), sc.add(box(1.0, 0.2, 2.6, 1.8, 0.9, 3.2, 'iron'))), action='forge')
    item('workbench', 'Werkbank', (3.6, 1.5), lambda sc: (
        [sc.add(box(x, y, 0, x + 0.18, y + 0.18, 1.3, 'wood_dark')) for x in (0.1, 3.32) for y in (0.1, 1.22)],
        sc.add(box(0, 0, 1.3, 3.6, 1.5, 1.55, 'wood')), sc.add(box(0.2, 0.5, 0.35, 3.4, 1.3, 0.45, 'wood_dark')),
        sc.add(box(2.7, 1.1, 1.55, 3.3, 1.55, 1.95, 'iron')), sc.add(box(0.6, 0.6, 1.55, 1.6, 0.8, 1.62, 'metal')),
        sc.add(box(1.8, 0.4, 1.55, 2.2, 1.0, 1.75, 'wood_light'))), action='craft')
    item('tool_wall', 'Werkzeugwand', (3.0, 0.2), lambda sc: (
        sc.add(box(0, 0, 0, 3.0, 0.15, 2.0, 'cork')),
        [sc.add(box(0.25 + k * 0.55, 0.12, 0.4, 0.35 + k * 0.55, 0.22, 1.6, 'iron' if k % 2 else 'wood_dark')) for k in range(5)]), wall=True)
    item('barrel', 'Fass', (1.2, 1.2), lambda sc: (
        sc.add(cyl(0.6, 0.6, 0, 1.5, 0.58, 'wood')), sc.add(cyl(0.6, 0.6, 0.3, 0.38, 0.6, 'iron')),
        sc.add(cyl(0.6, 0.6, 1.1, 1.18, 0.6, 'iron')), sc.add(cyl(0.6, 0.6, 1.5, 1.55, 0.5, 'wood_dark'))))
    item('sacks', 'Säcke', (1.8, 1.2), lambda sc: (
        sc.add(ell(0.5, 0.6, 0.5, 0.5, 0.5, 0.55, 'canvas')), sc.add(ell(1.3, 0.65, 0.45, 0.48, 0.48, 0.5, 'canvas')),
        sc.add(ell(0.9, 0.5, 1.05, 0.42, 0.42, 0.42, 'canvas'))))
    item('pallet_rack', 'Lagerregal', (4.0, 1.3), lambda sc: (
        [sc.add(box(x, y, 0, x + 0.15, y + 0.15, 3.6, 'blue')) for x in (0, 3.85) for y in (0, 1.15)],
        [sc.add(box(0, 0, z, 4.0, 1.3, z + 0.12, 'e8782e' and 'metal')) for z in (0.4, 1.6, 2.8)],
        [sc.add(box(0.2 + k * 1.25, 0.2, z + 0.12, 1.25 + k * 1.25, 1.1, z + 0.85, 'wood_light')) for z in (0.4, 1.6, 2.8) for k in range(3)]))
    # -- office / admin
    item('office_desk', 'Schreibtisch', (2.8, 2.2), lambda sc: (
        chair(sc, 1.0, -0.05, 'leather'),
        sc.add(box(0, 0.8, 0, 2.8, 2.2, 1.3, 'wood_dark', cuts=[box(0.7, 0.7, -1, 2.1, 1.9, 1.1)])),
        sc.add(box(-0.05, 0.75, 1.3, 2.85, 2.25, 1.42, 'wood')), sc.add(box(0.3, 1.0, 1.42, 1.2, 1.6, 1.47, 'paper')),
        sc.add(cyl(2.3, 1.2, 1.42, 2.1, 0.06, 'bronze')), sc.add(ell(2.3, 1.2, 2.15, 0.25, 0.25, 0.18, 'lamp'))), action='work')
    item('filing_cabinet', 'Aktenschrank', (1.1, 1.0), lambda sc: (
        sc.add(box(0, 0, 0, 1.1, 1.0, 2.4, 'metal')),
        [sc.add(box(0.1, 0.98, 0.15 + k * 0.75, 1.0, 1.02, 0.8 + k * 0.75, 'chrome')) for k in range(3)]), action='files')
    item('notice_board', 'Aushangtafel', (2.4, 0.2), lambda sc: (
        sc.add(box(0, 0, 0, 2.4, 0.12, 1.5, 'wood_dark')), sc.add(box(0.1, 0.1, 0.1, 2.3, 0.15, 1.4, 'cork'))), wall=True, action='read_notice')
    item('conference_table', 'Konferenztisch', (5.0, 3.0), lambda sc: (
        [chair(sc, 0.45 + k * 1.15, 0.0, 'leather') for k in range(4)],
        sc.add(box(0, 0.9, 0, 5.0, 2.1, 1.1, 'wood_dark', cuts=[box(0.25, 0.8, -1, 4.75, 2.2, 0.95)])),
        sc.add(box(-0.05, 0.85, 0.95, 5.05, 2.15, 1.15, 'wood_dark')),
        [chair(sc, 0.45 + k * 1.15, 1.95, 'leather', back='s') for k in range(4)]), action='meeting')
    item('bench', 'Bank', (3.0, 0.9), lambda sc: (
        sc.add(box(0.1, 0.1, 0, 0.3, 0.8, 0.5, 'wood_dark')), sc.add(box(2.7, 0.1, 0, 2.9, 0.8, 0.5, 'wood_dark')),
        sc.add(box(0, 0.1, 0.5, 3.0, 0.8, 0.65, 'wood'))), action='sit')
    item('waiting_chairs', 'Wartestühle', (3.4, 1.1), lambda sc: [chair(sc, 0.1 + k * 1.1, 0.0, 'blue') for k in range(3)], action='sit')
    item('flag_stand', 'Fahne', (1.0, 1.0), lambda sc: (
        sc.add(cyl(0.5, 0.5, 0, 0.15, 0.4, 'bronze')), sc.add(cyl(0.5, 0.5, 0.15, 3.3, 0.06, 'bronze')),
        sc.add(box(0.55, 0.45, 1.7, 1.9, 0.55, 3.2, 'blue')), sc.add(box(0.55, 0.45, 2.2, 1.9, 0.56, 2.7, 'gold'))))
    # -- clinic
    item('med_bed', 'Behandlungsliege', (1.6, 3.2), lambda sc: (
        [sc.add(box(x, y, 0, x + 0.12, y + 0.12, 0.7, 'chrome')) for x in (0.1, 1.38) for y in (0.2, 3.0)],
        sc.add(box(0, 0.2, 0.7, 1.6, 3.2, 0.95, 'white')), sc.add(box(0.05, 0.2, 0.95, 1.55, 1.0, 1.45, 'teal')),
        sc.add(box(0.05, 1.0, 0.95, 1.55, 3.15, 1.05, 'teal'))), action='lie_down')
    item('med_cabinet', 'Arzneischrank', (1.8, 0.8), lambda sc: (
        sc.add(box(0, 0, 0, 1.8, 0.8, 3.0, 'white')), sc.add(box(0.1, 0.78, 1.6, 1.7, 0.82, 2.9, 'glass')),
        sc.add(box(0.75, 0.8, 0.5, 1.05, 0.85, 1.3, 'red')), sc.add(box(0.5, 0.8, 0.75, 1.3, 0.85, 1.05, 'red'))), action='medicine')
    item('med_screen', 'Sichtschutz', (2.4, 0.5), lambda sc: (
        [sc.add(box(k * 0.8, 0.1, 0, k * 0.8 + 0.78, 0.25, 2.6, 'teal')) for k in range(3)],
        [sc.add(box(k * 0.8, 0.0, 0, k * 0.8 + 0.06, 0.4, 2.7, 'chrome')) for k in range(4)]))
    item('stretcher', 'Trage', (1.2, 3.0), lambda sc: (
        sc.add(box(0.05, 0, 0.2, 0.15, 3.0, 0.3, 'metal')), sc.add(box(1.05, 0, 0.2, 1.15, 3.0, 0.3, 'metal')),
        sc.add(box(0.1, 0.3, 0.25, 1.1, 2.7, 0.32, 'red'))))
    # -- utility buildings
    item('generator', 'Generator', (3.0, 2.0), lambda sc: (
        sc.add(box(0, 0, 0, 3.0, 2.0, 2.2, 'green')), sc.add(box(0.2, 1.95, 0.4, 1.4, 2.05, 1.8, 'iron')),
        sc.add(hcyl('x', -0.2, 3.2, 0.6, 2.5, 0.25, 'metal')), sc.add(cyl(2.3, 1.2, 2.2, 2.9, 0.3, 'iron')),
        sc.add(box(1.7, 1.98, 1.2, 2.7, 2.05, 1.9, 'screen_green'))), action='inspect')
    item('control_panel', 'Schaltpult', (2.4, 1.0), lambda sc: (
        sc.add(box(0, 0, 0, 2.4, 1.0, 2.6, 'metal')), sc.add(box(0.15, 0.98, 1.0, 2.25, 1.02, 2.4, 'navy')),
        [sc.add(box(0.3 + k * 0.4, 1.0, 1.9, 0.5 + k * 0.4, 1.05, 2.1, ['red', 'green', 'gold'][k % 3])) for k in range(5)],
        sc.add(box(0.3, 1.0, 1.15, 2.1, 1.05, 1.6, 'screen_green'))), action='inspect')
    item('water_tank', 'Wassertank', (2.4, 2.4), lambda sc: (
        sc.add(cyl(1.2, 1.2, 0, 3.4, 1.15, 'chrome')), sc.add(cyl(1.2, 1.2, 3.4, 3.6, 1.0, 'metal')),
        sc.add(hcyl('x', 2.0, 2.6, 2.2, 0.6, 0.18, 'blue')), sc.add(box(0.6, 2.32, 1.6, 1.8, 2.36, 2.0, 'blue'))), action='inspect')
    item('pump', 'Pumpe', (2.4, 1.6), lambda sc: (
        sc.add(box(0, 0, 0, 2.4, 1.6, 0.4, 'iron')), sc.add(cyl(0.8, 0.8, 0.4, 1.6, 0.55, 'blue')),
        sc.add(hcyl('x', 1.3, 2.4, 0.8, 1.0, 0.25, 'metal')), sc.add(cyl(1.9, 0.8, 0.4, 1.8, 0.22, 'metal'))), action='inspect')
    item('hose_rack', 'Schlauchhalter', (2.0, 0.3), lambda sc: (
        sc.add(box(0, 0, 0, 2.0, 0.12, 1.6, 'iron')), sc.add(cyl(0.55, 0.25, 0.4, 0.75, 0.42, 'red')),
        sc.add(cyl(1.45, 0.25, 0.4, 0.75, 0.42, 'red'))), wall=True)
    item('equipment_rack', 'Ausrüstung', (3.0, 0.9), lambda sc: (
        sc.add(box(0, 0, 0, 3.0, 0.9, 0.4, 'metal')), sc.add(box(0, 0, 2.9, 3.0, 0.9, 3.0, 'metal')),
        [sc.add(box(0.2 + k * 0.95, 0.3, 1.2, 0.8 + k * 0.95, 0.6, 2.7, 'e8782e' and 'red')) for k in range(3)],
        [sc.add(ell(0.5 + k * 0.95, 0.45, 2.85, 0.3, 0.3, 0.2, 'gold')) for k in range(3)]), action='inspect')
    # -- antique set (Concordium)
    item('column', 'Säule', (1.6, 1.6), lambda sc: (
        sc.add(box(0, 0, 0, 1.6, 1.6, 0.3, 'marble_warm')), sc.add(cyl(0.8, 0.8, 0.3, 0.55, 0.72, 'marble')),
        sc.add(cyl(0.8, 0.8, 0.55, 5.2, 0.6, 'marble')), sc.add(cyl(0.8, 0.8, 5.2, 5.5, 0.74, 'marble_warm')),
        sc.add(box(0, 0, 5.5, 1.6, 1.6, 5.8, 'marble_warm'))))
    item('statue', 'Statue', (1.6, 1.6), lambda sc: (
        sc.add(box(0, 0, 0, 1.6, 1.6, 0.4, 'marble_dark')), sc.add(box(0.15, 0.15, 0.4, 1.45, 1.45, 1.6, 'marble_warm')),
        sc.add(ell(0.8, 0.8, 2.6, 0.42, 0.38, 1.1, 'marble')), sc.add(ell(0.8, 0.8, 3.55, 0.5, 0.35, 0.26, 'marble')),
        sc.add(ell(0.8, 0.85, 4.0, 0.24, 0.24, 0.28, 'marble'))), action='look')
    item('statue_gold', 'Goldene Statue', (1.6, 1.6), lambda sc: (
        sc.add(box(0, 0, 0, 1.6, 1.6, 0.4, 'marble_dark')), sc.add(box(0.15, 0.15, 0.4, 1.45, 1.45, 1.6, 'marble')),
        sc.add(ell(0.8, 0.8, 2.6, 0.42, 0.38, 1.1, 'gold')), sc.add(ell(0.8, 0.8, 3.55, 0.5, 0.35, 0.26, 'gold')),
        sc.add(ell(0.8, 0.85, 4.0, 0.24, 0.24, 0.28, 'gold'))), action='look')
    item('bust', 'Büste', (1.0, 1.0), lambda sc: (
        sc.add(box(0.1, 0.1, 0, 0.9, 0.9, 1.8, 'marble_warm')), sc.add(ell(0.5, 0.5, 2.1, 0.38, 0.28, 0.3, 'marble')),
        sc.add(ell(0.5, 0.55, 2.55, 0.22, 0.22, 0.27, 'marble'))), action='look')
    item('vitrine', 'Vitrine', (1.8, 1.2), lambda sc: (
        sc.add(box(0, 0, 0, 1.8, 1.2, 1.0, 'wood_dark')), sc.add(ell(0.9, 0.6, 1.35, 0.3, 0.3, 0.35, 'gold')),
        sc.add(box(0.05, 0.05, 1.0, 1.75, 1.15, 2.1, 'glass')), sc.add(box(0, 0, 2.1, 1.8, 1.2, 2.2, 'wood_dark'))), action='look')
    item('amphora', 'Amphore', (1.0, 1.0), lambda sc: (
        sc.add(box(0.1, 0.1, 0, 0.9, 0.9, 0.8, 'marble_warm')), sc.add(ell(0.5, 0.5, 1.4, 0.36, 0.36, 0.6, 'e8782e' and 'bronze')),
        sc.add(cyl(0.5, 0.5, 1.9, 2.3, 0.14, 'bronze'))), action='look')
    item('rostrum', 'Rednerpult', (3.2, 2.4), lambda sc: (
        sc.add(box(0, 0, 0, 3.2, 2.4, 0.35, 'marble_warm')), sc.add(box(0.3, 0.3, 0.35, 2.9, 2.1, 0.7, 'marble')),
        sc.add(box(1.0, 1.2, 0.7, 2.2, 1.9, 2.3, 'wood_dark')), sc.add(box(0.9, 1.1, 2.3, 2.3, 2.0, 2.5, 'wood')),
        sc.add(cyl(1.6, 1.92, 1.3, 1.7, 0.32, 'gold'))), action='speak')
    item('delegate_seat', 'Delegiertenplatz', (2.0, 1.6), lambda sc: (
        sc.add(box(0, 0, 0, 2.0, 0.7, 1.2, 'wood_dark')), sc.add(box(-0.02, -0.02, 1.2, 2.02, 0.72, 1.32, 'wood')),
        sc.add(box(0.6, 0.85, 0, 1.4, 1.5, 0.55, 'crimson')), sc.add(box(0.6, 1.4, 0.55, 1.4, 1.6, 1.5, 'crimson')),
        sc.add(cyl(1.75, 0.35, 1.32, 2.2, 0.03, 'bronze')), sc.add(box(1.78, 0.33, 1.8, 2.15, 0.37, 2.15, 'blue'))), action='sit')
    item('presidium', 'Präsidium', (6.0, 2.0), lambda sc: (
        sc.add(box(0, 0, 0, 6.0, 2.0, 0.5, 'marble_warm')),
        [sc.add(box(0.9 + k * 1.6, 0.25, 0.5, 1.6 + k * 1.6, 0.85, 2.1, 'crimson')) for k in range(3)],
        sc.add(box(0.4, 1.0, 0.5, 5.6, 1.9, 1.6, 'wood_dark')), sc.add(box(0.35, 0.95, 1.6, 5.65, 1.95, 1.75, 'wood')),
        sc.add(box(2.6, 1.88, 0.8, 3.4, 1.95, 1.4, 'gold'))), action='look')
    item('gallery_rail', 'Galerie', (4.0, 0.4), lambda sc: (
        sc.add(box(0, 0, 0, 4.0, 0.4, 0.35, 'marble_warm')),
        [sc.add(cyl(0.25 + k * 0.5, 0.2, 0.35, 1.2, 0.12, 'marble')) for k in range(8)],
        sc.add(box(0, 0, 1.2, 4.0, 0.4, 1.4, 'marble_warm'))), wall=True)
    for col in ('red', 'blue', 'green', 'gold', 'purple', 'white'):
        item(f'banner_{col}', 'Banner', (1.4, 0.2), lambda sc, c=col: (
            sc.add(box(-0.1, 0, 3.2, 1.5, 0.12, 3.3, 'bronze')), sc.add(box(0.0, 0.05, 0.4, 1.4, 0.12, 3.2, c)),
            sc.add(box(0.15, 0.1, 1.6, 1.25, 0.14, 2.3, 'gold' if c != 'gold' else 'white'))), wall=True)
    item('brazier', 'Feuerschale', (1.2, 1.2), lambda sc: (
        sc.add(cyl(0.6, 0.6, 0, 0.15, 0.45, 'bronze')), sc.add(cyl(0.6, 0.6, 0.15, 1.6, 0.08, 'bronze')),
        sc.add(ell(0.6, 0.6, 1.75, 0.6, 0.6, 0.35, 'bronze')), sc.add(ell(0.6, 0.6, 2.05, 0.4, 0.4, 0.35, 'fire'))))
    item('candelabrum', 'Kandelaber', (0.9, 0.9), lambda sc: (
        sc.add(cyl(0.45, 0.45, 0, 0.12, 0.38, 'bronze')), sc.add(cyl(0.45, 0.45, 0.12, 3.2, 0.06, 'bronze')),
        sc.add(cyl(0.45, 0.45, 3.2, 3.35, 0.3, 'bronze')), sc.add(ell(0.45, 0.45, 3.55, 0.12, 0.12, 0.2, 'fire'))))
    item('mural', 'Wandgemälde', (4.0, 0.2), lambda sc: (
        sc.add(box(0, 0, 0, 4.0, 0.12, 2.4, 'gold')), sc.add(box(0.12, 0.1, 0.12, 3.88, 0.14, 2.28, 'teal')),
        sc.add(box(0.12, 0.12, 0.12, 3.88, 0.16, 0.8, 'green')), sc.add(ell(1.2, 0.15, 1.2, 0.25, 0.05, 0.6, 'marble_warm')),
        sc.add(ell(2.0, 0.15, 1.3, 0.25, 0.05, 0.7, 'crimson')), sc.add(ell(2.8, 0.15, 1.2, 0.25, 0.05, 0.6, 'blue')),
        sc.add(ell(3.4, 0.15, 2.0, 0.25, 0.05, 0.25, 'gold'))), wall=True, action='look')
    item('emblem', 'Emblem', (1.6, 0.2), lambda sc: (
        sc.add(cyl(0.8, 0.0, 0.0, 0.1, 0.8, 'marble_warm')) if False else None,
        sc.add(hcyl('y', 0.0, 0.12, 0.8, 0.8, 0.78, 'gold')), sc.add(hcyl('y', 0.1, 0.16, 0.8, 0.8, 0.55, 'navy')),
        sc.add(hcyl('y', 0.14, 0.2, 0.8, 0.8, 0.3, 'gold'))), wall=True)
    item('bench_marble', 'Marmorbank', (3.0, 1.0), lambda sc: (
        sc.add(box(0.2, 0.15, 0, 0.6, 0.85, 0.5, 'marble_warm')), sc.add(box(2.4, 0.15, 0, 2.8, 0.85, 0.5, 'marble_warm')),
        sc.add(box(0, 0.1, 0.5, 3.0, 0.9, 0.7, 'marble'))), action='sit')
    item('planter', 'Pflanzkübel', (1.4, 1.4), lambda sc: (
        sc.add(box(0.1, 0.1, 0, 1.3, 1.3, 0.9, 'marble_warm')), sc.add(ell(0.7, 0.7, 1.4, 0.7, 0.7, 0.75, 'plant'))))
    item('fountain_small', 'Brunnen', (2.6, 2.6), lambda sc: (
        sc.add(cyl(1.3, 1.3, 0, 0.7, 1.3, 'marble', cuts=[cyl(1.3, 1.3, 0.3, 1.0, 1.1)])),
        sc.add(cyl(1.3, 1.3, 0.1, 0.55, 1.1, 'water')), sc.add(cyl(1.3, 1.3, 0.55, 1.6, 0.18, 'marble')),
        sc.add(ell(1.3, 1.3, 1.7, 0.55, 0.55, 0.15, 'marble')), sc.add(ell(1.3, 1.3, 1.8, 0.4, 0.4, 0.06, 'water'))), action='drink')
    item('water_station', 'Trinkwasser', (1.6, 1.2), lambda sc: (
        sc.add(box(0, 0, 0, 1.6, 1.2, 0.9, 'stone', cuts=[box(0.2, 0.2, 0.6, 1.4, 1.0, 1.0)])),
        sc.add(box(0.2, 0.2, 0.6, 1.4, 1.0, 0.75, 'water')), sc.add(box(0.6, 0.0, 0.9, 1.0, 0.25, 2.0, 'stone')),
        sc.add(hcyl('y', 0.2, 0.55, 0.8, 1.6, 0.07, 'bronze'))), action='drink')
    item('scroll_shelf', 'Schriftrollenregal', (3.0, 1.0), lambda sc: (
        sc.add(box(0, 0, 0, 3.0, 1.0, 3.6, 'wood_dark', cuts=[box(0.12, 0.25, 0.2, 2.88, 1.1, 3.4)])),
        [sc.add(box(0.12, 0.25, z, 2.88, 1.0, z + 0.08, 'wood')) for z in (1.0, 1.85, 2.7)],
        [sc.add(hcyl('y', 0.3, 0.98, 0.35 + k * 0.38, z + 0.25, 0.16, 'paper')) for z in (0.2, 1.08, 1.93, 2.78) for k in range(7)]), action='read')
    item('archive_cabinet', 'Archivschrank', (2.0, 1.0), lambda sc: (
        sc.add(box(0, 0, 0, 2.0, 1.0, 3.2, 'wood')),
        [sc.add(box(0.1 + c * 0.95, 0.98, 0.2 + r * 0.75, 0.95 + c * 0.95, 1.02, 0.85 + r * 0.75, 'wood_light')) for c in range(2) for r in range(4)]), action='files')
    item('map_wall', 'Weltkarte', (4.0, 0.2), lambda sc: (
        sc.add(box(0, 0, 0, 4.0, 0.12, 2.4, 'wood_dark')), sc.add(box(0.12, 0.1, 0.12, 3.88, 0.14, 2.28, 'water')),
        sc.add(ell(1.0, 0.16, 1.4, 0.6, 0.04, 0.45, 'veg')), sc.add(ell(2.4, 0.16, 0.9, 0.8, 0.04, 0.35, 'veg')),
        sc.add(ell(3.2, 0.16, 1.7, 0.4, 0.04, 0.3, 'veg')), sc.add(ell(2.65, 0.18, 1.15, 0.1, 0.03, 0.1, 'gold'))), wall=True, action='look')
    item('reading_table', 'Lesetisch', (3.0, 1.6), lambda sc: (
        sc.add(box(0.1, 0.1, 0, 0.3, 1.5, 1.1, 'wood_dark')), sc.add(box(2.7, 0.1, 0, 2.9, 1.5, 1.1, 'wood_dark')),
        sc.add(box(0, 0, 1.1, 3.0, 1.6, 1.25, 'wood')), sc.add(box(0.4, 0.4, 1.25, 1.3, 1.1, 1.32, 'paper')),
        sc.add(box(1.6, 0.5, 1.25, 2.2, 1.0, 1.45, 'books')), sc.add(ell(2.6, 0.5, 1.5, 0.15, 0.15, 0.25, 'lamp'))), action='read')
    item('ladder', 'Leiter', (1.0, 0.6), lambda sc: (
        sc.add(box(0.1, 0.1, 0, 0.2, 0.3, 3.6, 'wood')), sc.add(box(0.8, 0.1, 0, 0.9, 0.3, 3.6, 'wood')),
        [sc.add(box(0.1, 0.15, 0.4 + k * 0.6, 0.9, 0.25, 0.48 + k * 0.6, 'wood_light')) for k in range(6)]))
    item('reception_desk', 'Empfang', (4.0, 1.4), lambda sc: (
        sc.add(box(0, 0, 0, 4.0, 1.4, 1.5, 'marble_warm')), sc.add(box(-0.05, -0.05, 1.5, 4.05, 1.45, 1.65, 'marble')),
        sc.add(box(0.3, 1.38, 0.3, 3.7, 1.42, 1.2, 'crimson')), sc.add(box(1.6, 1.4, 0.55, 2.4, 1.45, 0.95, 'gold')),
        sc.add(box(0.4, 0.3, 1.65, 1.0, 0.7, 1.75, 'paper'))), action='ask')
    item('food_counter', 'Essensausgabe', (4.0, 1.3), lambda sc: (
        sc.add(box(0, 0, 0, 4.0, 1.3, 1.4, 'metal')), sc.add(box(-0.05, -0.05, 1.4, 4.05, 1.35, 1.5, 'chrome')),
        [sc.add(cyl(0.7 + k * 1.3, 0.6, 1.5, 1.9, 0.38, 'iron')) for k in range(3)],
        [sc.add(cyl(0.7 + k * 1.3, 0.6, 1.88, 1.92, 0.3, ['veg', 'bread', 'blanket_ochre'][k])) for k in range(3)]), action='eat')
    # -- great council chamber (compact delegate places for > 1000 seats, facing south to the rostrum)
    # seen from behind: the delegates face north, to the presidium and the rostrum
    for cush, nm in (('crimson', ''), ('navy', '_navy'), ('green', '_green')):
        item('delegate_seat_small' + nm, 'Delegiertenplatz', (1.0, 1.1), lambda sc, c=cush: (
            sc.add(box(0.0, 0.0, 0, 1.0, 0.46, 0.78, 'wood')),                       # desk (north), runs on as a bench row
            sc.add(box(-0.03, -0.02, 0.78, 1.03, 0.49, 0.86, 'wood_light')),
            sc.add(box(0.15, 0.07, 0.86, 0.5, 0.3, 0.88, 'paper')),
            sc.add(cyl(0.82, 0.2, 0.86, 1.12, 0.025, 'bronze')), sc.add(ell(0.82, 0.2, 1.14, 0.05, 0.05, 0.04, 'gold')),
            sc.add(box(0.1, 0.52, 0, 0.9, 0.92, 0.45, c)),                           # seat
            sc.add(box(0.06, 0.9, 0.12, 0.94, 1.1, 1.02, c)),                        # upholstered back (south face seen)
            sc.add(box(0.04, 0.88, 1.02, 0.96, 1.12, 1.1, 'wood_dark')),
            sc.add(box(0.42, 1.11, 0.7, 0.58, 1.14, 0.86, 'gold'))), action='sit')
    # the same place turned towards the rostrum: 13 headings (-90..90 degrees, 15-degree steps);
    # collision is a compact 0.75-tile square under the chair, the art is anchored at its pivot
    for cush, nm in (('crimson', ''), ('navy', '_navy')):
        for deg in range(-90, 91, 15):
            item('delegate_seat_r%d%s' % (deg, nm), 'Delegiertenplatz', (0.75, 0.75),
                 lambda sc, c=cush, d=deg: seat_turned(sc, math.radians(d), c), action='sit', pivot=(0.5, 0.55))
    item('presidium_grand', 'Präsidium', (12.0, 3.0), lambda sc: (
        sc.add(box(0, 0, 0, 12.0, 3.0, 0.6, 'marble_warm')), sc.add(box(0.3, 0.3, 0.6, 11.7, 2.7, 0.9, 'marble')),
        [sc.add(box(1.0 + k * 2.1, 0.45, 0.9, 2.2 + k * 2.1, 1.1, 2.9 if k == 2 else 2.4, 'crimson' if k == 2 else 'navy')) for k in range(5)],
        sc.add(box(0.6, 1.35, 0.9, 11.4, 2.55, 2.0, 'wood_dark')), sc.add(box(0.5, 1.3, 2.0, 11.5, 2.6, 2.15, 'wood')),
        [sc.add(box(1.2 + k * 2.1, 2.55, 1.1, 1.9 + k * 2.1, 2.6, 1.8, 'gold')) for k in range(5)],
        sc.add(box(5.6, 2.56, 0.95, 6.4, 2.62, 1.0, 'bronze'))), action='look')
    item('rostrum_grand', 'Rednerpult', (4.0, 3.0), lambda sc: (
        sc.add(cyl(2.0, 1.5, 0, 0.35, 1.95, 'marble_warm')), sc.add(cyl(2.0, 1.5, 0.35, 0.7, 1.6, 'marble')),
        sc.add(box(1.3, 0.9, 0.7, 2.7, 1.8, 2.5, 'marble_warm')), sc.add(box(1.2, 0.8, 2.5, 2.8, 1.9, 2.7, 'marble')),
        sc.add(box(1.5, 1.78, 1.0, 2.5, 1.84, 2.2, 'gold')), sc.add(cyl(2.0, 1.2, 2.7, 3.2, 0.03, 'bronze')),
        sc.add(ell(2.0, 1.2, 3.22, 0.07, 0.07, 0.05, 'iron'))), action='speak')
    item('column_great', 'Säule', (1.6, 1.6), lambda sc: (
        sc.add(box(0, 0, 0, 1.6, 1.6, 0.5, 'marble_dark')), sc.add(cyl(0.8, 0.8, 0.5, 0.75, 0.72, 'marble_warm')),
        sc.add(cyl(0.8, 0.8, 0.75, 6.6, 0.58, 'marble')),
        sc.add(cyl(0.8, 0.8, 1.2, 1.3, 0.6, 'marble_warm')), sc.add(cyl(0.8, 0.8, 6.1, 6.2, 0.6, 'marble_warm')),
        sc.add(cyl(0.8, 0.8, 6.6, 6.9, 0.7, 'marble_warm')), sc.add(ell(0.35, 0.95, 7.0, 0.2, 0.15, 0.18, 'marble')),
        sc.add(ell(1.25, 0.95, 7.0, 0.2, 0.15, 0.18, 'marble')), sc.add(box(0, 0, 7.0, 1.6, 1.6, 7.35, 'marble_warm'))))
    def figure(sc, kind, base=1.1, k=1.45):
        """A standing marble figure (orator with raised arm, or draped goddess with staff), scaled by k."""
        Z = lambda z: base + (z - 1.65) * k
        E = lambda x, y, z, rx, ry, rz, m='marble': sc.add(ell(0.9 + (x - 0.9) * k, 0.95 + (y - 0.95) * k, Z(z), rx * k, ry * k, rz * k, m))
        if kind == 'orator':
            E(0.74, 0.95, 2.1, 0.13, 0.13, 0.5); E(1.06, 0.95, 2.1, 0.13, 0.13, 0.5)
            E(0.9, 0.95, 2.7, 0.36, 0.26, 0.62); E(0.82, 1.06, 2.45, 0.32, 0.12, 0.6, 'marble_warm')
            E(0.58, 0.95, 3.0, 0.09, 0.09, 0.34); E(1.26, 0.95, 3.4, 0.08, 0.08, 0.3); E(1.31, 0.95, 3.75, 0.07, 0.07, 0.08)
            E(0.9, 0.95, 3.42, 0.11, 0.1, 0.1); E(0.9, 0.98, 3.64, 0.16, 0.16, 0.19)
        else:
            sc.add(cyl(0.9, 0.95, base, Z(2.2), 0.42 * k, 'marble'))
            E(0.9, 0.95, 2.5, 0.36, 0.28, 0.75); E(0.9, 1.04, 3.08, 0.29, 0.21, 0.38, 'marble_warm')
            E(0.58, 0.95, 3.02, 0.08, 0.08, 0.34); E(1.24, 1.0, 3.08, 0.08, 0.08, 0.3)
            sc.add(cyl(0.9 + 0.44 * k, 1.0, base, Z(4.15), 0.035, 'gold'))
            E(0.9, 0.95, 3.58, 0.1, 0.1, 0.1); E(0.9, 0.98, 3.8, 0.16, 0.16, 0.19); E(0.9, 0.98, 3.98, 0.19, 0.17, 0.05, 'gold')

    for nm, lab, kind in (('statue_orator', 'Statue eines Redners', 'orator'), ('statue_goddess', 'Statue der Concordia', 'goddess')):
        item(nm, lab, (1.8, 1.8), lambda sc, kind=kind: (
            sc.add(box(0, 0, 0, 1.8, 1.8, 0.3, 'marble_dark')), sc.add(box(0.15, 0.15, 0.3, 1.65, 1.65, 0.95, 'marble_warm')),
            sc.add(box(0.08, 0.08, 0.95, 1.72, 1.72, 1.1, 'marble_dark')), figure(sc, kind)), action='look')
    item('mural_grand', 'Wandgemälde: Die Versammlung der Völker', (8.0, 0.2), lambda sc: (
        sc.add(box(0, 0, 0, 8.0, 0.12, 3.2, 'gold')), sc.add(box(0.15, 0.1, 0.15, 7.85, 0.14, 3.05, 'teal')),
        sc.add(box(0.15, 0.12, 0.15, 7.85, 0.16, 0.9, 'marble_warm')),
        [sc.add(box(0.3 + k * 0.5, 0.14, 0.25, 0.55 + k * 0.5, 0.18, 0.32, 'crimson')) for k in range(15)],          # meander band
        [sc.add(box(0.3 + k * 0.5, 0.14, 0.62, 0.55 + k * 0.5, 0.18, 0.69, 'crimson')) for k in range(15)],
        [(sc.add(ell(0.9 + k * 0.9, 0.16, 1.55, 0.2, 0.04, 0.48, ['crimson', 'blue', 'marble_warm', 'green', 'purple', 'ochre' and 'gold', 'blue', 'crimson'][k])),
          sc.add(ell(0.9 + k * 0.9, 0.17, 2.18, 0.12, 0.04, 0.13, 'marble_warm'))) for k in range(8)],              # figures
        sc.add(ell(4.0, 0.18, 2.7, 0.5, 0.03, 0.22, 'gold'))), wall=True, action='look')
    item('relief_frieze', 'Relief', (6.0, 0.2), lambda sc: (
        sc.add(box(0, 0, 0, 6.0, 0.14, 1.4, 'marble_warm')), sc.add(box(0, 0, 0, 6.0, 0.18, 0.15, 'marble')),
        sc.add(box(0, 0, 1.25, 6.0, 0.18, 1.4, 'marble')),
        [(sc.add(ell(0.5 + k * 0.72, 0.16, 0.65, 0.16, 0.06, 0.4, 'marble')), sc.add(ell(0.5 + k * 0.72, 0.17, 1.1, 0.1, 0.05, 0.1, 'marble'))) for k in range(8)]), wall=True, action='look')
    item('lamp_hanging', 'Hängeleuchter', (1.6, 0.2), lambda sc: (
        sc.add(cyl(0.8, 0.1, 3.3, 4.8, 0.03, 'bronze')), sc.add(box(0.1, 0.06, 3.22, 1.5, 0.14, 3.3, 'bronze')),
        [sc.add(cyl(0.8 + dx, 0.1, 3.0, 3.22, 0.03, 'bronze')) for dx in (-0.6, 0.0, 0.6)],
        [sc.add(ell(0.8 + dx, 0.1, 2.95, 0.17, 0.1, 0.1, 'bronze')) for dx in (-0.6, 0.0, 0.6)],
        [sc.add(ell(0.8 + dx, 0.1, 3.1, 0.07, 0.07, 0.13, 'fire')) for dx in (-0.6, 0.0, 0.6)]), wall=True)
    item('flag_ring', 'Flaggen der Nationen', (6.0, 0.6), lambda sc: (
        [(sc.add(cyl(0.3 + k * 1.08, 0.3, 0, 3.4, 0.04, 'bronze')),
          sc.add(box(0.34 + k * 1.08, 0.28, 2.3, 1.1 + k * 1.08, 0.32, 3.3, ['red', 'blue', 'green', 'gold', 'purple', 'white'][k]))) for k in range(6)]))
    # -- doors and gates in four opening phases (0 closed .. 3 open), 2 resp. 4 tiles wide
    for k in range(4):
        a = math.radians(k * 28)
        item(f'door_antique_{k}', 'Tür', (2.0, 0.4), lambda sc, a=a: door_frame(sc, 2.0, 3.0, 1, a, 'wood_dark'), wall=True)
        item(f'door_double_{k}', 'Doppeltür', (2.0, 0.4), lambda sc, a=a: door_frame(sc, 2.0, 3.0, 2, a, 'bronze'), wall=True)
        item(f'gate_bronze_{k}', 'Bronzetor', (4.0, 0.5), lambda sc, a=a: door_frame(sc, 4.0, 4.6, 2, a, 'bronze', grand=True), wall=True)
    return items


def seat_turned(sc, th, cush):
    """Delegate place (desk north, chair south) rotated by th about its pivot (0.5, 0.55)."""
    px, py = 0.5, 0.55
    ct, st = math.cos(th), math.sin(th)

    def rot(x, y):
        dx, dy = x - px, y - py
        return px + dx * ct - dy * st, py + dx * st + dy * ct

    def B(x0, y0, z0, x1, y1, z1, mat):
        cx, cy = rot((x0 + x1) / 2, (y0 + y1) / 2)
        sc.add(oriented_box(cx, cy, z0, z1, (x1 - x0) / 2, (y1 - y0) / 2, th, mat))
    B(0.0, 0.0, 0, 1.0, 0.46, 0.78, 'wood')
    B(-0.04, -0.03, 0.78, 1.04, 0.5, 0.86, 'wood_light')
    B(0.15, 0.07, 0.86, 0.5, 0.3, 0.88, 'paper')
    mx, my = rot(0.62, 0.2)
    sc.add(cyl(mx, my, 0.86, 1.12, 0.025, 'bronze'))
    sc.add(ell(mx, my, 1.14, 0.05, 0.05, 0.04, 'gold'))
    B(0.1, 0.52, 0, 0.9, 0.92, 0.45, cush)
    B(0.06, 0.9, 0.12, 0.94, 1.1, 1.02, cush)
    B(0.04, 0.88, 1.02, 0.96, 1.12, 1.1, 'wood_dark')


def door_frame(sc, w, h, leaves, a, mat, grand=False):
    """Marble frame with leaves swung inward (north) by angle a, hinge at the jambs."""
    j = 0.28 if grand else 0.2
    sc.add(box(-j, 0, 0, 0, 0.4, h + 0.1, 'marble_warm'))
    sc.add(box(w, 0, 0, w + j, 0.4, h + 0.1, 'marble_warm'))
    sc.add(box(-j - 0.08, -0.02, h, w + j + 0.08, 0.44, h + (0.55 if grand else 0.35), 'marble'))
    sc.add(box(-j - 0.08, -0.7, h, w + j + 0.08, -0.02, h + (0.55 if grand else 0.35), 'marble_warm'))   # wall thickness above
    if grand:
        sc.add(box(-j - 0.15, 0.2, h + 0.55, w + j + 0.15, 0.48, h + 0.7, 'marble_warm'))
        sc.add(ell(w / 2, 0.42, h + 0.32, 0.35, 0.05, 0.2, 'gold'))
    sc.add(box(0, 0.05, 0, w, 0.35, 0.02, 'marble_dark'))                       # threshold
    sc.add(box(0, 0.0, 0.02, w, 0.06, h, 'iron'))                              # dark doorway behind
    lw = w / leaves
    for k in range(leaves):
        hx = 0.0 if k == 0 else w
        sgn = 1.0 if k == 0 else -1.0
        ang = -a if k == 0 else math.pi + a                                    # swing north (y-)
        cx = hx + sgn * 0.0 + math.cos(ang) * lw / 2 * (1 if k == 0 else 1)
        cy = 0.2 + math.sin(ang) * lw / 2
        if k == 1:
            cx = hx + math.cos(ang) * lw / 2
        sc.add(oriented_box(cx, cy, 0.02, h - 0.02, lw / 2 - 0.02, 0.06, ang, mat))
        # panels and studs
        for z0, z1 in ((0.3, h * 0.45), (h * 0.52, h - 0.3)):
            pcx = hx + math.cos(ang) * lw / 2
            pcy = 0.2 + math.sin(ang) * lw / 2
            nx, ny = -math.sin(ang), math.cos(ang)
            if ny < 0:
                nx, ny = -nx, -ny                                              # the face towards the viewer
            sc.add(oriented_box(pcx + nx * 0.07, pcy + ny * 0.07, z0, z1, lw / 2 - 0.22, 0.02, ang, 'gold' if mat == 'bronze' else 'wood'))


# ---------------------------------------------------------------- floors / walls (tileable, 64 px)

def floor_textures():
    T = 64
    out = {}
    yy, xx = np.mgrid[0:T, 0:T]

    def img(rgb):
        a = np.ones((T, T, 1))
        return np.concatenate([rgb, a], 2)

    def col(h):
        return hexc(h)[None, None, :]
    # marble slabs with veins
    base = np.ones((T, T, 3)) * col('ece4d6')
    slab = ((xx // 32) + (yy // 32)) % 2
    base = np.where(slab[..., None] == 1, base * 0.95, base)
    vein = np.abs(np.sin(xx * 0.21 + yy * 0.13 + np.sin(yy * 0.3) * 2)) < 0.06
    base[vein] *= 0.85
    base[(xx % 32 == 0) | (yy % 32 == 0)] = hexc('b9ad9c')
    out['marble_floor'] = img(base)
    # mosaic: border band + rosette pattern
    m = np.ones((T, T, 3)) * col('e6d2b0')
    cx = (xx % 16) - 7.5
    cy = (yy % 16) - 7.5
    r = np.hypot(cx, cy)
    m[(r < 5) & (r > 3)] = hexc('b9653f')
    m[r < 2] = hexc('5d8f9a')
    m[(xx % 16 == 0) | (yy % 16 == 0)] = hexc('c9b38a')
    out['mosaic'] = img(m)
    # stone flags (workshops, smithy)
    s = np.ones((T, T, 3)) * col('8f8a82')
    blk = ((xx // 21) * 7 + (yy // 16) * 3) % 5
    s = s * (0.92 + 0.04 * blk[..., None])
    s[(xx % 21 == 0) | (yy % 16 == 0)] = hexc('5f5a55')
    out['stone_flags'] = img(s)
    # clinic tiles (white/teal)
    c = np.ones((T, T, 3)) * col('eef3f2')
    c[((xx // 8) + (yy // 8)) % 2 == 1] = hexc('dfe9e7')
    c[(xx % 8 == 0) | (yy % 8 == 0)] = hexc('a9c4c0')
    out['clinic_tiles'] = img(c)
    # concrete / metal (utility)
    k = np.ones((T, T, 3)) * col('8d8f94')
    k[(xx % 32 == 0) | (yy % 32 == 0)] = hexc('5d5f64')
    k[((xx % 32) - 16) ** 2 + ((yy % 32) - 16) ** 2 < 2] = hexc('b0b2b6')
    out['metal_plates'] = img(k)
    # walls (64 x 48 = 3 tiles high): marble wall with pilaster + frieze, fresco red, white tiles, brick
    W = np.ones((48, T, 3))
    yy2, xx2 = np.mgrid[0:48, 0:T]
    mw = W * col('e8e0d2')
    mw[(xx2 % 32 < 6)] = hexc('f4eee3')
    mw[(xx2 % 32 == 6) | (xx2 % 32 == 0)] = hexc('b9ad9c')
    mw[(yy2 < 6)] = hexc('d9c9a8')
    mw[(yy2 == 6)] = hexc('a8703a')
    mw[(yy2 >= 40)] = hexc('cdbfb2')
    mw[(yy2 == 40)] = hexc('9a8c7c')
    out['wall_marble'] = np.concatenate([mw, np.ones((48, T, 1))], 2)
    fw = W * col('a8443a')
    fw[(yy2 < 7)] = hexc('e6d2b0')
    fw[(yy2 == 7)] = hexc('e0b64a')
    fw[(yy2 >= 36)] = hexc('3b2342')
    fw[(yy2 == 36)] = hexc('e0b64a')
    fw[((xx2 % 16 - 8) ** 2 + (yy2 - 3) ** 2) < 4] = hexc('5d8f9a')
    out['wall_fresco'] = np.concatenate([fw, np.ones((48, T, 1))], 2)
    tw = W * col('f2f4f2')
    tw[(xx2 % 8 == 0) | (yy2 % 8 == 0)] = hexc('c3d3d0')
    tw[(yy2 >= 30)] = hexc('9fc6d6')
    tw[(yy2 >= 30) & ((xx2 % 8 == 0) | (yy2 % 8 == 0))] = hexc('7aa9b8')
    out['wall_tiles'] = np.concatenate([tw, np.ones((48, T, 1))], 2)
    bw = W * col('a24a2e')
    bw[(yy2 % 6 == 0) | (((xx2 + (yy2 // 6) % 2 * 6) % 12) == 0)] = hexc('7a3520')
    out['wall_brick'] = np.concatenate([bw, np.ones((48, T, 1))], 2)
    return out


def quantise(rgb, pal):
    flat_ = rgb.reshape(-1, 3)
    d = ((flat_[:, None, :] - pal[None, :, :]) ** 2).sum(-1)
    return pal[d.argmin(1)].reshape(rgb.shape)


def main():
    sheet_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'assets', 'penzilla', 'interior')
    pal = palette(sheet_dir)
    print('palette colours', len(pal))
    os.makedirs(OUT, exist_ok=True)
    ir.set_camera(ir.Camera('oblique', 1.0))
    ir.INK[:] = INK
    entries = {}
    for name, it in build_items().items():
        sc = it['scene']
        sc.solids = [s for s in sc.solids if s is not None]
        img, buf = ir.render(sc, MATS, PX, ss=1, line_px=(1.0, 1.0, 1.0), log=lambda m: None)
        a = img[..., 3] > 0.5
        ys, xs = np.nonzero(a)
        anchor = None
        if it.get('pivot'):
            u, v = ir.CAM.project(np.array([it['pivot'][0], it['pivot'][1], 0.0]))
            anchor = [round(float((u - buf['origin'][0]) * PX - xs.min()), 1), round(float((buf['origin'][1] - v) * PX - ys.min()), 1)]
        img = img[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        rgb = img[..., :3]
        ink = np.abs(rgb - INK[None, None, :]).sum(-1) < 0.02
        q = quantise(rgb, pal)
        q[ink] = INK
        out = np.concatenate([q, (img[..., 3:4] > 0.5).astype(float)], 2)
        Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, name + '.png'))
        h, w = out.shape[:2]
        fw, fd = it['fp']
        e = {'sheet': 'worlds/' + name + '.png', 'rect': [0, 0, w, h], 'label': it['label'], 'origin': 'worlds'}
        if it['wall']:
            e['wall'] = True
            e['solid'] = [0, 0, 0, 0]
        else:
            dpx = int(round(fd * PX))
            e['solid'] = [0, max(0, h - dpx), w, min(h, dpx)]
        if it['action']:
            e['action'] = it['action']
        if anchor:
            e['anchor'] = anchor                                  # source px of the pivot (footprint centre) at floor level
            e['footprint'] = list(it['fp'])
        entries[name] = e
    for name, arr in floor_textures().items():
        q = quantise(arr[..., :3], pal)
        Image.fromarray((np.concatenate([q, arr[..., 3:]], 2) * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, name + '.png'))
    json.dump({'_comment': 'Generated by tools/art/interior_assets.py – own WORLDS pixel art in the interior standard (docs/INTERIOR_STANDARD.md).',
               'items': entries,
               'floors': {n: {'sheet': 'worlds/%s.png' % n, 'rect': [0, 0, 64, 64]} for n in ('marble_floor', 'mosaic', 'stone_flags', 'clinic_tiles', 'metal_plates')},
               'walls': {n: {'sheet': 'worlds/%s.png' % n, 'rect': [0, 0, 64, 48]} for n in ('wall_marble', 'wall_fresco', 'wall_tiles', 'wall_brick')}},
              open(os.path.join(ROOT, 'data', 'interiors', 'worlds_items.json'), 'w'), indent=1, ensure_ascii=False)
    print(len(entries), 'items')


if __name__ == '__main__':
    main()
