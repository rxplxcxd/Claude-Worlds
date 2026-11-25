"""The World Council seat ("Concordium von Kalistia") as solids.

Architectural concept (docs/WORLD_COUNCIL_ART_DIRECTION.md):
  * centre-back: the ASSEMBLY ROTUNDA on a stepped podium (+6 m) – drum with
    arched windows, ring colonnade (peristyle), upper drum, patina dome with
    gilded ribs and lantern; a deep temple PORTICO with pediment, gilded
    inscription and acroteria faces the forum,
  * GRAND STAIRS down to the FORUM: paved square with a long water CANAL,
    statues on both sides and the GREAT FOUNTAIN,
  * two STOAS (colonnaded halls) frame the forum,
  * the WATER TERRACES step down from the podium towards the east with
    cascades into a reflecting pool; an AQUEDUCT brings the water from the
    hills in the north-east,
  * L-shaped PALACE WINGS (delegations / diplomacy) with domed corner
    pavilions wrap the back,
  * a sunken open-air THEATRE (hemicycle) for public events in the front
    corner, gardens with cypresses, hedges and flower beds everywhere else.
Stage 1 ("historic site"): weathered, partly broken columns and statues,
fallen drums, a collapsed pavilion dome, dry/murky water, ivy and moss.

Grid: 1 m units, X -> screen right-down, Y -> screen left-down. Site spans
-84..84 in X and Y; the rotunda centre is (-16, -16).
"""
import math
import numpy as np
from isorender import Scene, box, cyl, hcyl, ell, prism_gable, ngon_prism, oriented_box

RC = (-16.0, -16.0)        # rotunda centre
DOMES = {}                 # material name -> centre (ribs per dome)
MOSAICS = {}
PODIUM_Z = 6.0


def niche(solid):
    """Marks a cutter as a shallow niche (shaded stone instead of a dark opening)."""
    solid.data['niche'] = True
    return solid


def column(sc, x, y, z0, h, r, part, mat='column', broken=None, cap=True, rng=None):
    """Classical column: plinth, base ring, fluted shaft, capital, abacus.
    broken = remaining fraction of the shaft (ruin)."""
    sc.add(box(x - r * 1.25, y - r * 1.25, z0, x + r * 1.25, y + r * 1.25, z0 + 0.3, 'marble', part))
    sc.add(cyl(x, y, z0 + 0.3, z0 + 0.6, r * 1.14, 'marble', part))
    shaft = h - 1.25
    if broken is not None:
        top = z0 + 0.6 + shaft * broken
        sc.add(cyl(x, y, z0 + 0.6, top, r, mat, part))
        return top
    sc.add(cyl(x, y, z0 + 0.6, z0 + 0.6 + shaft, r, mat, part))
    if cap:
        sc.add(cyl(x, y, z0 + 0.6 + shaft, z0 + h - 0.3, r * 1.2, 'marble', part))
        sc.add(box(x - r * 1.4, y - r * 1.4, z0 + h - 0.3, x + r * 1.4, y + r * 1.4, z0 + h, 'marble', part))
    return z0 + h


def statue(sc, x, y, z0, part, mat='marble', scale=1.0, broken=False, pedestal=1.4, facing=(1, 1)):
    """Draped figure on a pedestal (robe, shoulders, head)."""
    s = scale
    sc.add(box(x - 0.8 * s, y - 0.8 * s, z0, x + 0.8 * s, y + 0.8 * s, z0 + pedestal * 0.15, 'marble_warm', part))
    sc.add(box(x - 0.65 * s, y - 0.65 * s, z0 + pedestal * 0.15, x + 0.65 * s, y + 0.65 * s, z0 + pedestal, 'marble_warm', part))
    z = z0 + pedestal
    sc.add(ell(x, y, z + 1.05 * s, 0.42 * s, 0.42 * s, 1.1 * s, mat, part, zmin=z))
    if broken:
        return
    sc.add(ell(x, y, z + 1.85 * s, 0.5 * s, 0.38 * s, 0.25 * s, mat, part))
    sc.add(ell(x, y, z + 2.3 * s, 0.22 * s, 0.22 * s, 0.27 * s, mat, part))


def cypress(sc, x, y, z0, h, part, r=None):
    r = r or h * 0.16
    sc.add(ell(x, y, z0 + h * 0.5, r, r, h * 0.55, 'cypress', part, zmin=z0))


def tree(sc, x, y, z0, part, k=1.0, seed=0):
    rng = np.random.default_rng(seed)
    sc.add(cyl(x, y, z0, z0 + 2.2 * k, 0.28 * k, 'bronze', part))
    for i in range(4):
        dx, dy = rng.uniform(-1.2, 1.2, 2) * k
        sc.add(ell(x + dx, y + dy, z0 + (3.4 + rng.uniform(0, 1.3)) * k, 1.9 * k, 1.9 * k, 1.6 * k, 'foliage', part))


def hedge(sc, x0, y0, x1, y1, z0, part, h=1.1):
    sc.add(box(x0, y0, z0, x1, y1, z0 + h, 'foliage', part))


def arch_cutters(axis, along0, along1, spacing, width, z0, spring, depth0, depth1, skip=()):
    """Arched openings (box + half cylinder) along a wall."""
    cuts = []
    n = int(round((along1 - along0) / spacing))
    for k in range(n):
        if k in skip:
            continue
        c = along0 + spacing * (k + 0.5)
        if axis == 'y':   # wall runs along y, openings through x (depth0..depth1 in x)
            cuts.append(box(depth0, c - width / 2, z0, depth1, c + width / 2, spring))
            cuts.append(hcyl('x', depth0, depth1, c, spring, width / 2))
        else:
            cuts.append(box(c - width / 2, depth0, z0, c + width / 2, depth1, spring))
            cuts.append(hcyl('y', depth0, depth1, c, spring, width / 2))
    return cuts


def build(stage: int = 1):
    sc = Scene()
    ruin = stage <= 1
    rng = np.random.default_rng(7)
    rx, ry = RC

    # ---------------------------------------------------------- ground
    theatre_c = (50.0, 50.0)
    theatre_r = 22.0
    hole = cyl(theatre_c[0], theatre_c[1], -8.0, 1.0, theatre_r)
    sc.add(box(-84, -84, -2.0, 84, 84, 0.0, 'grass', 'ground', cuts=[hole]))

    # ---------------------------------------------------------- rotunda
    p = 'assembly_hall'
    for k, (r, z) in enumerate(((37.5, 2.0), (36.3, 4.0), (35.1, PODIUM_Z))):
        sc.add(cyl(rx, ry, 0.0, z, r, 'marble_warm', 'podium'))
    # podium paving ring
    sc.add(cyl(rx, ry, PODIUM_Z, PODIUM_Z + 0.05, 34.6, 'paving', 'podium'))
    # drum with arched windows on the visible side
    cuts = []
    for k in range(24):
        a = 2 * math.pi * k / 24
        if not (-1.2 < a < 2.7 or a > 2 * math.pi - 1.2):
            continue
        cxw = rx + math.cos(a) * 24.0
        cyw = ry + math.sin(a) * 24.0
        cuts.append(oriented_box(cxw, cyw, PODIUM_Z + 3.0, PODIUM_Z + 10.5, 1.6, 1.1, a))
        cuts.append(Solid_arch_top(cxw, cyw, PODIUM_Z + 10.5, 1.1, a))
    sc.add(cyl(rx, ry, PODIUM_Z, PODIUM_Z + 19.0, 24.0, 'marble', p, cuts=cuts))
    # string course + cornice
    sc.add(cyl(rx, ry, PODIUM_Z + 12.0, PODIUM_Z + 12.8, 24.5, 'marble_warm', p))
    # peristyle: ring colonnade on its own stylobate
    sc.add(cyl(rx, ry, PODIUM_Z, PODIUM_Z + 0.7, 31.5, 'marble_warm', 'peristyle'))
    n_col = 32
    for k in range(n_col):
        a = 2 * math.pi * k / n_col
        cx_, cy_ = rx + math.cos(a) * 30.0, ry + math.sin(a) * 30.0
        if abs(math.atan2(math.sin(a - math.pi / 2), math.cos(a - math.pi / 2))) < 0.42:
            continue  # portico in front
        broken = None
        if ruin and k in (3, 4, 29):
            broken = 0.35 + 0.2 * (k % 2)
        column(sc, cx_, cy_, PODIUM_Z + 0.7, 13.5, 0.85, f'peristyle_c{k}', broken=broken)
    # entablature ring (gaps over broken columns are ignored – it is carried by the wall)
    ent_cut = [cyl(rx, ry, PODIUM_Z + 13.0, PODIUM_Z + 17.0, 27.6)]
    sc.add(cyl(rx, ry, PODIUM_Z + 14.2, PODIUM_Z + 15.6, 31.0, 'marble', 'peristyle_roof', cuts=ent_cut))
    sc.add(cyl(rx, ry, PODIUM_Z + 15.6, PODIUM_Z + 16.2, 31.4, 'marble_warm', 'peristyle_roof', cuts=ent_cut))
    sc.add(cyl(rx, ry, PODIUM_Z + 16.2, PODIUM_Z + 16.5, 30.8, 'roof', 'peristyle_roof', cuts=ent_cut))
    # balustrade posts on the peristyle roof
    for k in range(48):
        a = 2 * math.pi * k / 48
        sc.add(cyl(rx + math.cos(a) * 30.2, ry + math.sin(a) * 30.2, PODIUM_Z + 16.5, PODIUM_Z + 17.6, 0.32, 'marble', 'balustrade'))
    sc.add(cyl(rx, ry, PODIUM_Z + 17.6, PODIUM_Z + 18.0, 30.6, 'marble', 'balustrade', cuts=[cyl(rx, ry, PODIUM_Z + 17.0, PODIUM_Z + 19.0, 29.8)]))
    # upper drum + attic windows
    zc = PODIUM_Z + 19.0
    cuts = []
    for k in range(16):
        a = 2 * math.pi * k / 16
        cuts.append(oriented_box(rx + math.cos(a) * 21.0, ry + math.sin(a) * 21.0, zc + 2.0, zc + 4.6, 1.2, 0.8, a))
    sc.add(cyl(rx, ry, zc, zc + 7.0, 21.0, 'marble', 'drum_upper', cuts=cuts))
    sc.add(cyl(rx, ry, zc + 7.0, zc + 7.8, 21.8, 'marble_warm', 'drum_upper'))
    for k in range(16):  # pilasters / buttresses between attic windows
        a = 2 * math.pi * (k + 0.5) / 16
        sc.add(oriented_box(rx + math.cos(a) * 21.2, ry + math.sin(a) * 21.2, zc, zc + 7.0, 0.6, 0.9, a, 'marble_warm', 'drum_upper'))
    # dome
    zd = zc + 7.8
    sc.add(ell(rx, ry, zd, 20.6, 20.6, 17.0, 'dome', 'dome', zmin=zd))
    # lantern
    zl = zd + 16.4
    sc.add(cyl(rx, ry, zl, zl + 0.8, 4.2, 'marble', 'lantern'))
    for k in range(8):
        a = 2 * math.pi * k / 8
        sc.add(cyl(rx + math.cos(a) * 3.3, ry + math.sin(a) * 3.3, zl + 0.8, zl + 5.0, 0.32, 'column', 'lantern'))
    sc.add(cyl(rx, ry, zl + 0.8, zl + 5.0, 2.4, 'dark', 'lantern'))
    sc.add(cyl(rx, ry, zl + 5.0, zl + 5.8, 4.0, 'marble', 'lantern'))
    sc.add(ell(rx, ry, zl + 5.8, 3.4, 3.4, 2.8, 'gold', 'lantern', zmin=zl + 5.8))
    sc.add(cyl(rx, ry, zl + 8.4, zl + 10.5, 0.25, 'gold', 'lantern'))
    sc.add(ell(rx, ry, zl + 10.8, 0.55, 0.55, 0.55, 'gold', 'lantern'))

    # ---------------------------------------------------------- portico (faces +Y)
    p = 'portico'
    px0, px1 = rx - 13.0, rx + 13.0
    py0, py1 = ry + 16.0, ry + 36.0
    sc.add(box(px0 - 1, py0, PODIUM_Z, px1 + 1, py1, PODIUM_Z + 0.9, 'marble_warm', p))
    # cella wall with a great door
    door = [box(rx - 3.2, py0 + 4.0, PODIUM_Z + 0.9, rx + 3.2, py0 + 7.0, PODIUM_Z + 10.0)]
    sc.add(box(px0, py0, PODIUM_Z + 0.9, px1, py0 + 5.0, PODIUM_Z + 15.0, 'marble_shade', p, cuts=door))
    sc.add(box(rx - 3.0, py0 + 4.2, PODIUM_Z + 0.9, rx + 3.0, py0 + 4.6, PODIUM_Z + 9.8, 'bronze', 'portico_door'))
    for i in range(8):
        cx_ = px0 + 1.6 + i * (px1 - px0 - 3.2) / 7
        broken = 0.55 if (ruin and i == 6) else None
        column(sc, cx_, py1 - 1.6, PODIUM_Z + 0.9, 14.1, 1.05, f'portico_c{i}', broken=broken)
        if i in (0, 7):
            for j in (1, 2):
                column(sc, cx_, py1 - 1.6 - j * 4.6, PODIUM_Z + 0.9, 14.1, 1.0, f'portico_c{i}_{j}')
    if ruin:   # fallen drums of the broken column
        sc.add(hcyl('x', px0 + 17.0, px0 + 19.4, py1 + 2.2, 1.05, 1.0, 'column', 'debris'))
        sc.add(hcyl('y', py1 + 4.0, py1 + 6.0, px0 + 21.0, 0.95, 0.95, 'column', 'debris'))
    ze = PODIUM_Z + 15.0
    sc.add(box(px0 - 0.6, py0, ze, px1 + 0.6, py1, ze + 1.2, 'marble', p))
    sc.add(box(px0 - 0.6, py0, ze + 1.2, px1 + 0.6, py1, ze + 2.4, 'inscription', 'portico_frieze'))
    sc.add(box(px0 - 1.0, py0, ze + 2.4, px1 + 1.0, py1 + 0.4, ze + 3.0, 'marble_warm', p))
    # pediment with recessed tympanum and gilded relief
    zp = ze + 3.0
    sc.add(prism_gable(px0 - 1.0, py0, px1 + 1.0, py1 - 0.9, zp, zp + 8.0, 'y', 'roof', 'portico_roof'))

    sc.add(prism_gable(px0 - 0.4, py1 - 1.0, px1 + 0.4, py1 + 0.6, zp, zp + 7.6, 'y', 'marble', 'pediment',
                       cuts=[niche(prism_gable(px0 + 1.4, py1 - 0.2, px1 - 1.4, py1 + 1.0, zp + 0.6, zp + 6.6, 'y'))]))
    # relief: central medallion, standing figures, reclining figures in the corners
    sc.add(hcyl('y', py1 - 0.25, py1 + 0.05, rx, zp + 3.2, 1.6, 'gold', 'relief'))
    for i in (-2, -1, 1, 2):
        t = i / 3.0
        hgt = 4.2 * (1 - abs(t) * 0.8)
        xx = rx + t * 8.0
        sc.add(ell(xx, py1 - 0.1, zp + 0.6 + hgt * 0.42, 0.55, 0.22, hgt * 0.42, 'gold', 'relief', zmin=zp + 0.6))
        sc.add(ell(xx, py1 - 0.1, zp + 0.6 + hgt * 0.9, 0.3, 0.2, 0.3, 'gold', 'relief'))
    for side in (-1, 1):
        sc.add(ell(rx + side * 9.6, py1 - 0.1, zp + 1.05, 1.5, 0.22, 0.42, 'gold', 'relief', zmin=zp + 0.6))
    # acroteria
    sc.add(ell(rx, py1 + 0.2, zp + 8.6, 0.9, 0.6, 1.4, 'gold', 'acroterion'))
    for sx in (px0 - 0.6, px1 + 0.6):
        statue(sc, sx, py1 - 0.6, zp, 'acroterion_s', 'gold', 0.8, pedestal=0.6)

    # ---------------------------------------------------------- grand stairs (+Y)
    p = 'grand_stairs'
    sy0 = py1
    steps = 15
    for i in range(steps):
        z = PODIUM_Z - i * PODIUM_Z / steps
        y = sy0 + i * 0.8
        sc.add(box(rx - 15.0, y, 0.0, rx + 15.0, y + 0.8, z, 'marble_warm', p))
    sy1 = sy0 + steps * 0.8
    # cheek walls with statues, cascades beside the stairs
    for side in (-1, 1):
        xw = rx + side * 16.5
        sc.add(box(xw - 1.5, sy0 - 2, 0.0, xw + 1.5, sy1, PODIUM_Z + 0.8, 'marble', 'stair_cheek'))
        statue(sc, xw, sy1 - 1.5, 0.0, f'stair_statue_{side}', broken=(ruin and side > 0), scale=1.2, pedestal=2.0)
        statue(sc, xw, sy0 + 1.5, PODIUM_Z + 0.8, f'stair_statue_top_{side}', scale=1.1, pedestal=1.2)
        # cascade channel outside the cheek
        xc = rx + side * 21.0
        for i in range(5):
            z = PODIUM_Z - i * 1.2
            y = sy0 + i * 2.4
            sc.add(box(xc - 2.8, y, 0.0, xc + 2.8, y + 2.4, z, 'marble_warm', 'cascade'))
            sc.add(box(xc - 2.2, y + 0.2, z - 0.05, xc + 2.2, y + 2.4, z + 0.02, 'water_murky' if ruin else 'water', 'cascade_water'))
            if not ruin:
                sc.add(box(xc - 2.2, y + 2.35, z - 1.2, xc + 2.2, y + 2.45, z, 'water', 'cascade_fall'))

    # ---------------------------------------------------------- forum
    fx0, fx1 = -52.0, 20.0
    fy0, fy1 = sy1, 80.0
    cx_axis = rx
    canal = (cx_axis - 3.2, sy1 + 4.0, cx_axis + 3.2, fy1 - 6.0)
    fountain_c = (cx_axis, (sy1 + fy1) / 2.0 + 2.0)
    sc.add(box(fx0, fy0, 0.0, fx1, fy1, 0.12, 'paving', 'forum', cuts=[box(*canal[:2], -1, *canal[2:], 1), cyl(fountain_c[0], fountain_c[1], -1, 1, 8.5)]))
    # canal: basin, rim, water
    sc.add(box(canal[0], canal[1], -1.2, canal[2], canal[3], -0.9, 'paving_dark', 'canal'))
    sc.add(box(canal[0], canal[1], -1.2, canal[2], canal[3], 0.06, 'water_murky' if ruin else 'water', 'canal_water'))
    for (a0, a1) in ((canal[0] - 0.6, canal[0]), (canal[2], canal[2] + 0.6)):
        sc.add(box(a0, canal[1] - 0.6, 0.0, a1, canal[3] + 0.6, 0.45, 'marble', 'canal_rim'))
    for (b0, b1) in ((canal[1] - 0.6, canal[1]), (canal[3], canal[3] + 0.6)):
        sc.add(box(canal[0], b0, 0.0, canal[2], b1, 0.45, 'marble', 'canal_rim'))
    # great fountain (stage 1: dry, broken top tier)
    fx, fy = fountain_c
    sc.add(cyl(fx, fy, -0.6, 0.8, 8.5, 'marble', 'great_fountain', cuts=[cyl(fx, fy, 0.0, 2.0, 7.8)]))
    sc.add(cyl(fx, fy, -0.6, 0.1, 7.8, 'water_murky' if ruin else 'water', 'fountain_water'))
    sc.add(cyl(fx, fy, 0.1, 2.0, 1.6, 'marble', 'great_fountain'))
    sc.add(ell(fx, fy, 2.4, 4.2, 4.2, 1.0, 'marble', 'great_fountain', zmin=2.0, cuts=[ell(fx, fy, 3.0, 3.6, 3.6, 0.9)]))
    sc.add(cyl(fx, fy, 2.4, 4.6, 0.9, 'marble', 'great_fountain'))
    if not ruin:
        sc.add(ell(fx, fy, 5.2, 2.4, 2.4, 0.6, 'marble', 'great_fountain', zmin=4.6))
        statue(sc, fx, fy, 5.0, 'fountain_statue', 'gold', 1.1, pedestal=0.8)
    else:
        sc.add(hcyl('x', fx + 3.0, fx + 5.4, fy - 4.5, 0.6, 0.6, 'marble', 'debris'))
        statue(sc, fx, fy, 4.6, 'fountain_statue', 'marble', 1.0, broken=True, pedestal=0.6)
    # mosaic medallion in front of the stairs
    MOSAICS['mosaic_forum'] = (cx_axis, fy0 + 2.6)
    sc.add(cyl(cx_axis, fy0 + 2.6, 0.0, 0.16, 2.4, 'mosaic_forum', 'forum_medallion'))
    # bronze braziers (fire bowls) along the forum
    for i in range(5):
        y = fy0 + 6.0 + i * 11.0
        for x in (fx0 + 4.0, fx1 - 2.5):
            sc.add(box(x - 0.5, y - 0.5, 0.12, x + 0.5, y + 0.5, 0.5, 'marble_warm', 'brazier'))
            sc.add(cyl(x, y, 0.5, 2.6, 0.16, 'bronze', 'brazier'))
            sc.add(ell(x, y, 2.9, 0.75, 0.75, 0.45, 'bronze', 'brazier', zmin=2.6))
    # triumphal gate at the forum's outer end (main approach)
    gy0, gy1 = fy1 - 3.0, fy1 + 1.5
    gcuts = [box(cx_axis - 3.6, gy0 - 1, 0.0, cx_axis + 3.6, gy1 + 1, 8.5), hcyl('y', gy0 - 1, gy1 + 1, cx_axis, 8.5, 3.6)]
    for side in (-1, 1):
        xs = cx_axis + side * 7.6
        gcuts += [box(xs - 1.7, gy0 - 1, 0.0, xs + 1.7, gy1 + 1, 5.0), hcyl('y', gy0 - 1, gy1 + 1, xs, 5.0, 1.7)]
    sc.add(box(cx_axis - 11.0, gy0, 0.0, cx_axis + 11.0, gy1, 15.0, 'marble', 'gate', cuts=gcuts))
    for side in (-1, 1):   # engaged columns on the front
        for xs in (cx_axis + side * 4.8, cx_axis + side * 10.2):
            column(sc, xs, gy1 + 0.5, 0.0, 12.5, 0.55, f'gate_c{side}_{xs:.0f}', mat='column')
    sc.add(box(cx_axis - 11.4, gy0 - 0.3, 12.5, cx_axis + 11.4, gy1 + 1.2, 13.3, 'marble_warm', 'gate'))
    sc.add(box(cx_axis - 10.6, gy0, 13.3, cx_axis + 10.6, gy1 + 0.6, 17.2, 'inscription', 'gate_attic'))
    sc.add(box(cx_axis - 11.0, gy0 - 0.2, 17.2, cx_axis + 11.0, gy1 + 0.8, 17.8, 'marble_warm', 'gate'))
    statue(sc, cx_axis, (gy0 + gy1) / 2, 17.8, 'gate_statue', 'gold' if not ruin else 'bronze', 1.6, pedestal=0.8)
    for side in (-1, 1):
        statue(sc, cx_axis + side * 8.5, (gy0 + gy1) / 2, 17.8, f'gate_statue_{side}', 'marble', 1.1, pedestal=0.6, broken=(ruin and side < 0))
    # approach road from outside
    sc.add(box(cx_axis - 4.0, gy1, 0.0, cx_axis + 4.0, 84.0, 0.1, 'paving_dark', 'road'))
    # statues along the canal
    for i in range(6):
        y = canal[1] + 4.0 + i * (canal[3] - canal[1] - 8.0) / 5.0
        if abs(y - fy) < 10.0:
            continue
        for side in (-1, 1):
            br = ruin and ((i + (side > 0)) % 3 == 0)
            statue(sc, cx_axis + side * 7.5, y, 0.12, f'forum_statue_{i}_{side}', broken=br, scale=1.0, pedestal=1.6)
    # benches / planters along the forum
    for i in range(4):
        y = fy0 + 8 + i * 12.0
        for x in (fx0 + 12.0, fx1 - 6.0):
            sc.add(box(x - 1.4, y - 1.4, 0.12, x + 1.4, y + 1.4, 1.0, 'marble_warm', 'planter'))
            sc.add(ell(x, y, 1.5, 1.4, 1.4, 1.0, 'foliage', 'planter'))

    # ---------------------------------------------------------- stoas
    def stoa(x_back0, x_back1, x_col, y0, y1, facing, name, broken_cols=(), roof_missing=None):
        # stylobate
        xa, xb = sorted((x_back0, x_col + facing * 2.0))
        sc.add(box(xa, y0, 0.0, xb, y1, 1.0, 'marble_warm', name))
        # back wall with niches on the inner side
        niche_x = (x_back1, x_back1 + facing * 0.5) if facing > 0 else (x_back1 - 0.5, x_back1)
        cuts = arch_cutters('y', y0 + 2, y1 - 2, 5.0, 2.0, 2.2, 6.0, min(niche_x), max(niche_x))
        cuts = [niche(c) for c in cuts]
        if facing < 0:  # outer side faces the camera (+X): arched windows through the wall
            cuts = arch_cutters('y', y0 + 2, y1 - 2, 5.0, 1.8, 2.6, 6.4, min(x_back0, x_back1) - 0.1, max(x_back0, x_back1) + 0.1)
        wa, wb = sorted((x_back0, x_back1))
        sc.add(box(wa, y0, 1.0, wb, y1, 10.0, 'marble_shade' if facing > 0 else 'marble', f'{name}_wall', cuts=cuts))
        # ceiling / dark interior band seen between the columns
        ia, ib = sorted((x_back1, x_col))
        sc.add(box(ia, y0, 9.0, ib, y1, 9.6, 'marble_shade', f'{name}_ceiling'))
        n = int((y1 - y0) / 4.0)
        for i in range(n + 1):
            y = y0 + 0.9 + i * (y1 - y0 - 1.8) / n
            br = (0.3 + 0.25 * (i % 2)) if (ruin and i in broken_cols) else None
            column(sc, x_col, y, 1.0, 8.6, 0.55, f'{name}_c{i}', broken=br)
            if br is not None:
                sc.add(hcyl('y', y + 1.0, y + 2.6, x_col + facing * 2.6, 1.55, 0.55, 'column', 'debris'))
        ea, eb = sorted((x_back0, x_col + facing * 0.9))
        segments = [(y0, y1)] if roof_missing is None else [(y0, roof_missing[0]), (roof_missing[1], y1)]
        for (s0, s1) in segments:
            sc.add(box(ea, s0, 9.6, eb, s1, 10.8, 'marble', f'{name}_ent'))
            sc.add(box(ea - 0.3, s0, 10.8, eb + 0.3, s1, 11.3, 'marble_warm', f'{name}_ent'))
            sc.add(prism_gable(ea - 0.3, s0, eb + 0.3, s1, 11.3, 14.2, 'y', 'roof', f'{name}_roof'))
        if roof_missing is not None:
            # exposed beams + rubble
            for k in range(3):
                yb = roof_missing[0] + 1.5 + k * 2.6
                sc.add(box(ea, yb, 10.4, eb, yb + 0.5, 10.9, 'earth', f'{name}_beam'))
            sc.add(ell((ea + eb) / 2, (roof_missing[0] + roof_missing[1]) / 2, 1.0, 2.6, 3.4, 0.9, 'earth', 'debris', zmin=1.0))

    stoa(fx0 - 9.0, fx0 - 7.4, fx0 + 0.6, fy0 - 4.0, fy1, 1, 'stoa_west', broken_cols=(3, 4) if ruin else ())
    stoa(fx1 + 9.0, fx1 + 7.4, fx1 - 0.6, fy0 - 4.0, fy1, -1, 'stoa_east', broken_cols=(2, 7, 8) if ruin else (),
         roof_missing=(fy0 + 18.0, fy0 + 27.0) if ruin else None)

    # ---------------------------------------------------------- water terraces (+X)
    tx0 = rx + 35.0
    ty0, ty1 = ry - 22.0, ry + 22.0
    levels = [(tx0 - 14.0, tx0 + 12.0, 4.4), (tx0 + 12.0, tx0 + 30.0, 2.2), (tx0 + 30.0, 84.0, 0.0)]
    for li, (a, b, z) in enumerate(levels):
        if z > 0:
            sc.add(box(a, ty0, 0.0, b, ty1, z, 'marble_warm', f'terrace_{li}'))
        sc.add(box(a, ty0, z, b, ty1, z + 0.05, 'paving', f'terrace_{li}_top'))
        # side balustrades
        for yy in (ty0, ty1 - 0.5):
            for k in range(int((b - a) / 1.2)):
                sc.add(cyl(a + 0.6 + k * 1.2, yy + 0.25, z, z + 1.0, 0.18, 'marble', f'terrace_{li}_bal'))
            sc.add(box(a, yy, z + 1.0, b, yy + 0.5, z + 1.3, 'marble', f'terrace_{li}_bal'))
        # channel / pool on the axis
        if li < 2:
            sc.add(box(a + 1.0, ry - 3.0, z + 0.05, b, ry + 3.0, z + 0.4, 'marble', f'channel_{li}',
                       cuts=[box(a + 1.6, ry - 2.4, z + 0.1, b + 1, ry + 2.4, z + 1)]))
            sc.add(box(a + 1.6, ry - 2.4, z + 0.1, b, ry + 2.4, z + 0.3, 'water_murky' if ruin else 'water', 'channel_water'))
            # cascade lip
            sc.add(box(b - 0.1, ry - 2.4, levels[li + 1][2], b + 0.25, ry + 2.4, z + 0.3, 'water_murky' if ruin else 'water', 'cascade_fall'))
        else:
            pool = (a + 3.0, ty0 + 5.0, b - 6.0, ty1 - 5.0)
            sc.add(box(pool[0] - 0.8, pool[1] - 0.8, 0.0, pool[2] + 0.8, pool[3] + 0.8, 0.5, 'marble', 'pool_rim',
                       cuts=[box(pool[0], pool[1], -1.0, pool[2], pool[3], 1.0)]))
            sc.add(box(pool[0], pool[1], -0.8, pool[2], pool[3], 0.15, 'water_murky' if ruin else 'water', 'pool_water'))
            # island pavilion (tholos) in the pool
            tcx, tcy = (pool[0] + pool[2]) / 2, (pool[1] + pool[3]) / 2
            sc.add(cyl(tcx, tcy, -0.5, 1.2, 5.0, 'marble_warm', 'tholos'))
            for k in range(10):
                a2 = 2 * math.pi * k / 10
                column(sc, tcx + math.cos(a2) * 4.2, tcy + math.sin(a2) * 4.2, 1.2, 6.2, 0.38, f'tholos_c{k}',
                       broken=(0.4 if (ruin and k in (1, 2)) else None))
            sc.add(cyl(tcx, tcy, 7.4, 8.2, 4.8, 'marble', 'tholos', cuts=[cyl(tcx, tcy, 7, 9, 3.8)] if ruin else []))
            if not ruin:
                DOMES['dome_tholos'] = (tcx, tcy)
                sc.add(ell(tcx, tcy, 8.2, 4.6, 4.6, 3.2, 'dome_tholos', 'tholos', zmin=8.2))
        # cypresses along the terraces
        for k in range(int((b - a) / 5.0)):
            for yy in (ty0 - 2.5, ty1 + 2.5):
                cypress(sc, a + 2.5 + k * 5.0, yy, 0.0, 9.0 + rng.uniform(-1, 1.5), 'cypress')
    # aqueduct from the hills (north-east = grid +X / -Y)
    ay = -76.0
    cuts = arch_cutters('x', 8.0, 84.0, 7.6, 4.6, 0.0, 9.5, ay - 3, ay + 3)
    sc.add(box(8.0, ay - 1.6, 0.0, 84.0, ay + 1.6, 15.0, 'sandstone', 'aqueduct', cuts=cuts))
    sc.add(box(8.0, ay - 2.0, 15.0, 84.0, ay + 2.0, 15.8, 'sandstone', 'aqueduct_top', cuts=[box(7, ay - 0.9, 15.3, 85, ay + 0.9, 17)]))
    if ruin:   # a collapsed span
        sc.add(ell(55.0, ay + 2.0, 0.3, 4.0, 2.5, 1.2, 'sandstone', 'debris'))
    sc.add(cyl(4.0, ay, 0.0, 18.0, 4.5, 'sandstone', 'castellum'))
    sc.add(cyl(4.0, ay, 18.0, 19.0, 5.0, 'marble_warm', 'castellum'))
    sc.add(ell(4.0, ay, 19.0, 4.2, 4.2, 2.6, 'roof', 'castellum', zmin=19.0))

    # ---------------------------------------------------------- palace wings (back L)
    def wing(x0, y0, x1, y1, name, front_axis):
        h = 15.0
        cuts = []
        if front_axis == 'x':   # front faces +X
            cuts += arch_cutters('y', y0 + 1, y1 - 1, 5.0, 2.6, 0.6, 4.6, x1 - 1.2, x1 + 0.1)
            for k in range(int((y1 - y0 - 2) / 5.0)):
                c = y0 + 1 + 5.0 * (k + 0.5)
                cuts.append(box(x1 - 0.8, c - 0.8, 7.0, x1 + 0.1, c + 0.8, 10.0))
                cuts.append(hcyl('x', x1 - 0.8, x1 + 0.1, c, 10.0, 0.8))
        else:                   # front faces +Y
            cuts += arch_cutters('x', x0 + 1, x1 - 1, 5.0, 2.6, 0.6, 4.6, y1 - 1.2, y1 + 0.1)
            for k in range(int((x1 - x0 - 2) / 5.0)):
                c = x0 + 1 + 5.0 * (k + 0.5)
                cuts.append(box(c - 0.8, y1 - 0.8, 7.0, c + 0.8, y1 + 0.1, 10.0))
                cuts.append(hcyl('y', y1 - 0.8, y1 + 0.1, c, 10.0, 0.8))
        sc.add(box(x0, y0, 0.0, x1, y1, 0.6, 'marble_warm', f'{name}_base'))
        sc.add(box(x0, y0, 0.6, x1, y1, h, 'marble', name, cuts=cuts))
        sc.add(box(x0 - 0.3, y0 - 0.3, 5.6, x1 + 0.3, y1 + 0.3, 6.2, 'marble_warm', f'{name}_course'))
        sc.add(box(x0 - 0.5, y0 - 0.5, h, x1 + 0.5, y1 + 0.5, h + 0.8, 'marble_warm', f'{name}_cornice'))
        # balustrade on the roof edge
        if front_axis == 'x':
            for k in range(int((y1 - y0) / 1.1)):
                sc.add(cyl(x1 - 0.1, y0 + 0.5 + k * 1.1, h + 0.8, h + 1.8, 0.2, 'marble', f'{name}_bal'))
            sc.add(box(x1 - 0.4, y0, h + 1.8, x1 + 0.2, y1, h + 2.1, 'marble', f'{name}_bal'))
            for k in range(1, int((y1 - y0) / 12.0)):
                statue(sc, x1 - 0.2, y0 + k * 12.0, h + 0.8, f'{name}_roof_statue_{k}', scale=0.85, pedestal=0.9,
                       broken=(ruin and k % 3 == 1))
        else:
            for k in range(int((x1 - x0) / 1.1)):
                sc.add(cyl(x0 + 0.5 + k * 1.1, y1 - 0.1, h + 0.8, h + 1.8, 0.2, 'marble', f'{name}_bal'))
            sc.add(box(x0, y1 - 0.4, h + 1.8, x1, y1 + 0.2, h + 2.1, 'marble', f'{name}_bal'))
            for k in range(1, int((x1 - x0) / 12.0)):
                statue(sc, x0 + k * 12.0, y1 - 0.2, h + 0.8, f'{name}_roof_statue_{k}', scale=0.85, pedestal=0.9,
                       broken=(ruin and k % 3 == 2))
        # flat roof (terracotta hipped low roof behind the balustrade)
        sc.add(prism_gable(x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5, h + 0.8, h + 4.0,
                           'y' if front_axis == 'x' else 'x', 'roof', f'{name}_roof'))

    wing(-84.0, -84.0, -64.0, 14.0, 'palace_west', 'x')
    wing(-64.0, -84.0, 2.0, -64.0, 'palace_east', 'y')

    def pavilion(cx, cy, name, collapsed=False):
        dm = f'dome_{name}'
        DOMES[dm] = (cx, cy)
        sc.add(box(cx - 9, cy - 9, 0.0, cx + 9, cy + 9, 0.8, 'marble_warm', name))
        cuts = arch_cutters('y', cy - 7.5, cy + 7.5, 5.0, 2.4, 0.8, 5.0, cx + 7.8, cx + 9.1) + \
            arch_cutters('x', cx - 7.5, cx + 7.5, 5.0, 2.4, 0.8, 5.0, cy + 7.8, cy + 9.1)
        sc.add(box(cx - 8.5, cy - 8.5, 0.8, cx + 8.5, cy + 8.5, 19.0, 'marble', name, cuts=cuts))
        sc.add(box(cx - 9.0, cy - 9.0, 19.0, cx + 9.0, cy + 9.0, 20.0, 'marble_warm', name))
        for dx in (-7.6, 7.6):     # corner pilasters
            for dy in (-7.6, 7.6):
                sc.add(box(cx + dx - 1.1, cy + dy - 1.1, 0.8, cx + dx + 1.1, cy + dy + 1.1, 19.0, 'marble_warm', f'{name}_pil'))
        sc.add(ngon_prism(cx, cy, 20.0, 24.0, 6.4, 8, 'marble', f'{name}_drum', rot=math.pi / 8))
        if collapsed:
            sc.add(ell(cx, cy, 24.0, 6.4, 6.4, 5.4, dm, f'{name}_dome', zmin=24.0,
                       cuts=[ell(cx + 3.5, cy + 3.5, 28.0, 4.6, 4.6, 4.0), ell(cx, cy, 24.0, 5.6, 5.6, 4.6)]))
            for k in range(3):
                sc.add(box(cx - 5 + k * 3.5, cy - 4 + k * 2.0, 24.0, cx - 4.2 + k * 3.5, cy + 4 - k, 25.2, 'earth', f'{name}_beam'))
        else:
            sc.add(ell(cx, cy, 24.0, 6.4, 6.4, 5.4, dm, f'{name}_dome', zmin=24.0))
            sc.add(cyl(cx, cy, 29.2, 31.0, 0.2, 'gold', f'{name}_dome'))
            sc.add(ell(cx, cy, 31.2, 0.4, 0.4, 0.4, 'gold', f'{name}_dome'))

    pavilion(-74.0, -74.0, 'pavilion_corner')
    pavilion(-74.0, 22.0, 'pavilion_west', collapsed=ruin)
    pavilion(10.0, -74.0, 'pavilion_north')

    # ---------------------------------------------------------- theatre (front corner)
    tcx, tcy = theatre_c
    sc.add(cyl(tcx, tcy, -8.0, -6.0, theatre_r, 'paving_dark', 'theatre_floor'))
    keep_far = [((1, 1, 0), (tcx + tcy) * 1.0 + 1.5)]   # half facing away from the camera
    for k in range(9):
        r0 = 9.0 + k * 1.45
        top = -6.0 + (k + 1) * 0.68
        sc.add(cyl(tcx, tcy, -6.0, top, r0 + 1.45, 'marble_warm', 'theatre_cavea',
                   cuts=[cyl(tcx, tcy, -7, 3, r0)], extra_planes=keep_far))
    MOSAICS['mosaic_theatre'] = (tcx, tcy)
    sc.add(cyl(tcx, tcy, -6.0, -5.7, 8.6, 'mosaic_theatre', 'theatre_orchestra'))
    # stage (scaena) on the near side, low
    sc.add(oriented_box(tcx + 9.5, tcy + 9.5, -6.0, -4.6, 1.8, 9.0, math.pi / 4, 'marble', 'theatre_stage'))
    # rim wall with arches
    sc.add(cyl(tcx, tcy, -6.0, 0.8, theatre_r + 1.2, 'marble', 'theatre_rim',
               cuts=[cyl(tcx, tcy, -7, 3, theatre_r)], extra_planes=keep_far))

    # ---------------------------------------------------------- paths
    for (x0, y0, x1, y1) in ((fx1 + 9.0, 40.0, 84.0, 43.0), (22.0, ry + 22.0, 25.0, 84.0), (-64.0, 14.0, fx0 - 9.0, 17.0),
                             (-64.0, -64.0, -61.0, 14.0), (-61.0, -64.0, 2.0, -61.0)):
        sc.add(box(x0, y0, 0.0, x1, y1, 0.08, 'paving_dark', 'path'))

    # ---------------------------------------------------------- gardens
    gcuts = []
    # lawn parterres with hedges and flowers beside the theatre and terraces
    for (x0, y0, x1, y1) in ((24.0, 26.0, 84.0, 30.0), (24.0, 74.0, 84.0, 78.0)):
        hedge(sc, x0, y0, x1, y1, 0.0, 'hedge')
    for (x0, y0, x1, y1) in ((26.0, 32.0, 32.0, 72.0),):
        sc.add(box(x0, y0, 0.0, x1, y1, 0.35, 'flowers', 'flower_bed'))
    for k in range(7):
        cypress(sc, 30.0 + k * 8.0, 28.0, 0.0, 10.0 + (k % 2) * 1.5, 'cypress')
    for k, (x, y) in enumerate(((76, 36), (80, 64), (34, 80), (-40, -40), (-50, -30), (-30, -52), (-56, 30), (-58, 50), (-60, 70), (-44, 84))):
        tree(sc, x, y, 0.0, 'tree', k=1.0 + (k % 3) * 0.15, seed=k)
    # back courtyard garden between the wings and the rotunda
    for k in range(6):
        cypress(sc, -58.0, -56.0 + k * 9.0, 0.0, 9.0, 'cypress')
        cypress(sc, -56.0 + k * 9.0, -58.0, 0.0, 9.0, 'cypress')
    # ivy / overgrowth masses on ruined parts
    if ruin:
        for (x, y, z, r) in ((fx1 + 9.0, fy0 + 22.0, 4.0, 2.6), (fx0 - 9.0, fy0 + 30.0, 3.0, 2.2), (-64.0, -20.0, 5.0, 2.8),
                             (-30.0, -64.0, 4.0, 2.5), (rx + 24.0, ry + 8.0, 9.0, 2.0), (70.0, ay + 1.6, 6.0, 3.0)):
            sc.add(ell(x, y, z, r * 0.7, r * 0.7, r * 1.6, 'ivy', 'ivy', zmin=max(0.0, z - r * 1.6)))
        for (x, y) in ((-20, 60), (10, 40), (-40, 36), (14, 70), (44, -10), (64, 10)):
            sc.add(ell(x, y, 0.5, 1.6, 1.6, 0.9, 'foliage', 'weeds', zmin=0.0))
    return sc


def Solid_arch_top(cx, cy, z, half_w, ang):
    """Half-cylinder head of a radial window (axis along the radius)."""
    from isorender import Solid
    ca, sa = math.cos(ang), math.sin(ang)
    # cylinder axis along (ca, sa, 0): approximate with an 8-gon prism around that axis
    planes = []
    for k in range(8):
        a = math.pi * k / 7.0          # upper half-disc
        nz = math.sin(a)
        nt = math.cos(a)               # tangential direction (-sa, ca)
        n = (-sa * nt, ca * nt, nz)
        d = (-sa * nt) * cx + (ca * nt) * cy + nz * z + half_w
        planes.append((n, d))
    planes.append(((0, 0, -1), -z))
    planes.append(((ca, sa, 0), ca * cx + sa * cy + 1.6))
    planes.append(((-ca, -sa, 0), -(ca * cx + sa * cy - 1.6)))
    r = 2.0
    return Solid(planes, None, 'marble', None, (), (np.array([cx - r, cy - r, z]), np.array([cx + r, cy + r, z + half_w])))
