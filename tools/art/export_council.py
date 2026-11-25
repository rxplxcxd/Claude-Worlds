"""Exports the World Council for Godot (docs/WORLD_COUNCIL_ART_DIRECTION.md §6).

Writes to <out_dir> (default res://assets/landmarks/world_council/stage<N>/):
  color_<r>_<c>.png   colour tiles (TILE px), empty tiles skipped
  depth_<r>_<c>.png   per-pixel sort key for occlusion:
                      R,G = 16-bit footprint depth (x + y in metres, (d + 200) * 100)
                      B   = 255 for ground-level surfaces (never cover figures)
  site.json           px_per_m, image origin, tiles, walk grid (1 m cells):
                      height (dm) and kind per cell, entrance/spawn points
Usage: python -I export_council.py [stage] [px_per_m] [out_dir]
"""
import sys, os, json, time, base64
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import isorender as ir
import world_council as wc
import council_materials as cm

stage = int(sys.argv[1]) if len(sys.argv) > 1 else 1
px = float(sys.argv[2]) if len(sys.argv) > 2 else 16.0
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(root, 'assets', 'landmarks', 'world_council', f'stage{stage}')
TILE = 512
SS = 2
os.makedirs(out, exist_ok=True)
t0 = time.time()
log = lambda m: print(f"[{time.time() - t0:6.1f}s] {m}", flush=True)

sc = wc.build(stage)
GRID_ONLY = bool(os.environ.get('WC_GRID_ONLY'))
if GRID_ONLY:
    site_old = json.load(open(os.path.join(out, 'site.json')))
mats = cm.make_materials(centre_dome=wc.RC, moss=0.3 if stage <= 1 else 0.0, small_domes=wc.DOMES, mosaics=wc.MOSAICS)
mats['inscription'] = cm.inscription('efe6d4', z0=wc.PODIUM_Z + 16.2, z1=wc.PODIUM_Z + 17.4)
mats['lettering'] = cm.lettering('efe6d4', wc.INSCRIPTIONS, fallback=cm.stone('efe6d4', weather=0.05, seed=9))
if GRID_ONLY:
    img, buf = None, None
else:
  img, buf = ir.render(sc, mats, px, ss=SS, line_px=(1.5, 1.2, 0.8),
                     shade_fn=cm.overgrowth(1.0 if stage <= 1 else (0.35 if stage == 2 else 0.0)), log=log)
if not GRID_ONLY:
  H, W = img.shape[:2]
  sx0, sy1 = buf['origin']
  # world position of each final pixel (from the centre sub-sample's depth)
  depth = buf['depth']
  s = px * SS
  cols = (np.arange(W) * SS + SS // 2 + 0.5) / s + sx0
  rows = sy1 - (np.arange(H) * SS + SS // 2 + 0.5) / s
  cu, rv = np.meshgrid(cols, rows)
  o = cu[..., None] * ir.RIGHT + rv[..., None] * ir.UP - ir.VIEW * 2000.0
  fin = np.isfinite(depth)
  pos = o + np.where(fin, depth, 0)[..., None] * ir.VIEW
  key = pos[..., 0] + pos[..., 1]
  # ink/contour pixels have no own sample when the centre sub-sample missed:
  # give them the key of the nearest covered pixel
  alpha = img[..., 3]
  if (~fin & (alpha > 0)).any():
      from scipy import ndimage
      _, (iy, ix) = ndimage.distance_transform_edt(~fin, return_indices=True)
      key = key[iy, ix]
      pos = pos[iy, ix]
  ground = pos[..., 2] <= 0.5
  enc = np.clip((key + 200.0) * 100.0, 0, 65535).astype(np.uint32)
  dimg = np.zeros((H, W, 4), np.uint8)
  dimg[..., 0] = (enc >> 8).astype(np.uint8)
  dimg[..., 1] = (enc & 255).astype(np.uint8)
  # B = ground flag (128) + water code: 1 still water surface, 2 falling water
  mids = buf['mat']
  water_ids = [i for i, n in enumerate(buf['mat_names']) if n.startswith('water')]
  is_water = np.isin(mids, water_ids)
  if (~fin & (alpha > 0)).any():
      is_water = is_water[iy, ix]
  nz = np.abs(buf['normal'][..., 2])
  if (~fin & (alpha > 0)).any():
      nz = nz[iy, ix]
  code = np.where(is_water & (nz > 0.6), 1, np.where(is_water, 2, 0))
  # ink outlines keep code 0 (contours do not shimmer)
  ink = (np.abs(img[..., :3] - ir.INK[None, None, :]).sum(-1) < 0.05)
  code[ink] = 0
  dimg[..., 2] = np.where(ground, 128, 0) + code
  dimg[..., 3] = np.where(alpha > 0.0, 255, 0)
  cimg = np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8)
  tiles = []
  for r in range(0, H, TILE):
      for c in range(0, W, TILE):
          a = cimg[r:r + TILE, c:c + TILE]
          if a[..., 3].max() == 0:
              continue
          name = f"{r // TILE}_{c // TILE}"
          Image.fromarray(a, 'RGBA').save(os.path.join(out, f"color_{name}.png"), optimize=True)
          Image.fromarray(dimg[r:r + TILE, c:c + TILE], 'RGBA').save(os.path.join(out, f"depth_{name}.png"), optimize=True)
          tiles.append({"name": name, "x": c, "y": r, "w": int(a.shape[1]), "h": int(a.shape[0])})
  log(f"{len(tiles)} tiles")
  # preview (for docs/QA, not loaded by the game)
  Image.fromarray(cimg).resize((W // 4, H // 4), Image.LANCZOS).save(os.path.join(out, "preview.png"), optimize=True)


else:
  sx0, sy1 = site_old['origin_m']
  W, H = site_old['size']
  tiles = site_old['tiles']

# walk grid: top surfaces per 1 m cell
X0, Y0, X1, Y1 = -84, -84, 84, 84
# rays start just below the lowest ceilings (stoa ceilings 9.0, arches),
# so passages under arches and colonnades are walkable; solid buildings
# report their roof and are blocked.
CELL = 0.5
z, nz, mat, part = ir.height_field(sc, X0, Y0, X1, Y1, CELL, z_top=8.9)
# second, low ray (3 m): ground-level passages lower than 8.9 m (doorways,
# arches in walls) – used where the high ray started inside masonry
z2, nz2, mat2, part2 = ir.height_field(sc, X0, Y0, X1, Y1, CELL, z_top=3.0)
low = (z >= 8.85) & (z2 < 2.85)
z = np.where(low, z2, z)
nz = np.where(low, nz2, nz)
mat = np.where(low, mat2, mat)
part = np.where(low, part2, part)
kind = np.zeros(z.shape, np.uint8)            # 0 walk, 1 blocked, 2 water, 3 vegetation
blocked_mats = {'cypress', 'foliage', 'ivy', 'bronze', 'gold', 'flowers', 'dark', 'roof', 'dome', 'earth'}
for k, m in np.ndenumerate(mat):
    if m.startswith('water'):
        kind[k] = 2
    elif m in blocked_mats or m.startswith('dome'):
        kind[k] = 3 if m in ('cypress', 'foliage', 'ivy', 'flowers') else 1
    elif nz[k] < 0.7:
        kind[k] = 1
# statues, columns, walls: much higher than the surrounding floor -> blocked
from scipy import ndimage
# (no extra "much higher than the floor" rule: movement already refuses steps
#  > 0.55 m, so pedestals, walls and drops are not enterable, while terrace
#  edges and stair landings stay usable)
kind[z > 8.8] = 1                              # roofs, entablatures: not reachable
hd = np.clip(np.round(z * 10.0), -100, 2000).astype(np.int16)
site = {
    "landmark_id": "lmk_world_council", "stage": stage, "px_per_m": px,
    "origin_m": [float(sx0), float(sy1)], "size": [W, H], "tile": TILE, "tiles": tiles,
    "view": {"sin_phi": ir.SIN_PHI, "_comment": "screen x = (X - Y) * cos45 * k, screen y = (X + Y) * sin45 * sin_phi * k - Z * cos_phi * k, k = px_per_m"},
    "grid": {"x0": X0, "y0": Y0, "nx": int(z.shape[1]), "ny": int(z.shape[0]), "cell_m": CELL,
             "height_dm": base64.b64encode(hd.astype('<i2').tobytes()).decode(),
             "kind": base64.b64encode(kind.tobytes()).decode()},
    "spawn": [float(wc.RC[0]), 83.4],
    "height_m": float(max(so.aabb[1][2] for so in sc.solids)),
    "fx": wc.FX,
    "removed_plants": len(wc.REMOVED_PLANTS),
    "site_frame": {"x_axis": "east", "y_axis": "south"},
    "points": {"forum": [float(wc.RC[0]) + 6.0, 60.0], "portico": [float(wc.RC[0]), 26.0], "theatre": [44.0, 44.0], "terraces": [40.0, -12.0]},
}
json.dump(site, open(os.path.join(out, "site.json"), "w"))
log(f"walk grid {kind.shape}: walk {np.sum(kind == 0)}, blocked {np.sum(kind == 1)}, water {np.sum(kind == 2)}, green {np.sum(kind == 3)}")
log("done")
