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
def encode(img, buf):
  """Colour (uint8) and depth/ground/water tile data for a rendered image."""
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
  alpha = img[..., 3]
  miss = (~fin & (alpha > 0)).any()
  if miss:
      from scipy import ndimage
      _, (iy, ix) = ndimage.distance_transform_edt(~fin, return_indices=True)
      key = key[iy, ix]
      pos = pos[iy, ix]
  ground = pos[..., 2] <= 0.5
  enc = np.clip((key + 200.0) * 100.0, 0, 65535).astype(np.uint32)
  dimg = np.zeros((H, W, 4), np.uint8)
  dimg[..., 0] = (enc >> 8).astype(np.uint8)
  dimg[..., 1] = (enc & 255).astype(np.uint8)
  mids = buf['mat']
  water_ids = [i for i, n in enumerate(buf['mat_names']) if n.startswith('water')]
  is_water = np.isin(mids, water_ids)
  nz = np.abs(buf['normal'][..., 2])
  if miss:
      is_water = is_water[iy, ix]
      nz = nz[iy, ix]
  code = np.where(is_water & (nz > 0.6), 1, np.where(is_water, 2, 0))
  ink = (np.abs(img[..., :3] - ir.INK[None, None, :]).sum(-1) < 0.05)
  code[ink] = 0
  dimg[..., 2] = np.where(ground, 128, 0) + code
  dimg[..., 3] = np.where(alpha > 0.0, 255, 0)
  return np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8), dimg


if not GRID_ONLY:
  H, W = img.shape[:2]
  sx0, sy1 = buf['origin']
  cimg_full, dimg = encode(img, buf)
  cimg = cimg_full
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


def render_patch(scene, c0, r0, c1, r1):
  """Renders pixels [r0:r1, c0:c1] of the site image exactly on its pixel grid."""
  pad = 2.0
  frame = (sx0 + c0 / px + pad, sy1 - r1 / px + pad, sx0 + c1 / px - pad, sy1 - r0 / px - pad)
  im, bf = ir.render(scene, mats, px, ss=SS, line_px=(1.5, 1.2, 0.8), frame=frame,
                     shade_fn=cm.overgrowth(1.0 if stage <= 1 else (0.35 if stage == 2 else 0.0)), log=lambda m: None)
  return encode(im[:r1 - r0, :c1 - c0], {k: (v[:r1 - r0, :c1 - c0] if isinstance(v, np.ndarray) and v.ndim >= 2 else v) for k, v in bf.items()})


def xray(scene, d):
  """The scene without the parts standing in front of a door (columns,
  statues, trees): what the view shows, faintly, behind ghosted parts."""
  out_n = -np.array(d['inward'] + [0.0][:0], float)[:2]
  h0 = np.array(d['hinges'][0], float)
  zfloor = d['z'][0]
  keep = []
  for so in scene.solids:
      if so.aabb is None:
          keep.append(so)
          continue
      lo, hi = so.aabb
      lo2, hi2 = np.asarray(lo)[:2], np.asarray(hi)[:2]
      c = (lo2 + hi2) / 2.0
      in_front = float(np.dot(c - h0, out_n)) > 0.8 and float(hi[2]) > zfloor + 1.2
      near = np.linalg.norm(np.clip(h0, lo2, hi2) - h0) < 22.0
      if in_front and near and not str(so.part or '').startswith('door_') and so.part != 'ground':
          continue
      keep.append(so)
  x = ir.Scene()
  x.solids = keep
  return x


door_patches = []
if not GRID_ONLY and not os.environ.get('WC_NO_DOORS'):
  ddir = os.path.join(out, 'doors')
  os.makedirs(ddir, exist_ok=True)
  for name, d in wc.DOORS.items():
      hs = [np.array(h + [0.0]) for h in d['hinges']]
      w = d.get('width', 0.0) or float(np.linalg.norm(np.array(d['hinges'][1]) - np.array(d['hinges'][0]))) / 2.0
      pts = []
      for h in hs:
          for dx in (-w - 1.0, w + 1.0):
              for dy in (-w - 1.0, w + 1.0):
                  for z in (d['z'][0] - 0.5, d['z'][1] + 1.6):
                      pts.append(h + np.array([dx, dy, z]))
      uv = np.array([ir.CAM.project(p) for p in pts])
      m = 12
      c0 = max(0, int((uv[:, 0].min() - sx0) * px) - m); c1 = min(W, int((uv[:, 0].max() - sx0) * px) + m)
      r0 = max(0, int((sy1 - uv[:, 1].max()) * px) - m); r1 = min(H, int((sy1 - uv[:, 1].min()) * px) + m)
      M = 16                                   # rendered margin, cropped (contours at the frame edge)
      e = {'name': name, 'x': c0, 'y': r0, 'w': c1 - c0, 'h': r1 - r0, 'frames': len(wc.DOOR_PHASES),
           'hinges': d['hinges'], 'inward': d['inward']}
      for k, ang in enumerate(wc.DOOR_PHASES):
          scn = wc.build(stage, {name: ang})
          for variant, sx in (('', scn), ('_xray', xray(scn, wc.DOORS[name]))):
              cimg_p, dimg_p = render_patch(sx, max(0, c0 - M), max(0, r0 - M), min(W, c1 + M), min(H, r1 + M))
              oc, orr = c0 - max(0, c0 - M), r0 - max(0, r0 - M)
              cimg_p = cimg_p[orr:orr + r1 - r0, oc:oc + c1 - c0]
              dimg_p = dimg_p[orr:orr + r1 - r0, oc:oc + c1 - c0]
              if k == 0 and variant == '':
                  cimg_p = cimg_full[r0:r1, c0:c1]          # identical to the site image
                  dimg_p = dimg[r0:r1, c0:c1]
              Image.fromarray(cimg_p, 'RGBA').save(os.path.join(ddir, f'{name}_{k}{variant}.png'), optimize=True)
              Image.fromarray(dimg_p, 'RGBA').save(os.path.join(ddir, f'{name}_{k}{variant}_depth.png'), optimize=True)
          log(f"door {name}: phase {k} ({ang:.0f}°) {c1 - c0}x{r1 - r0} px")
      door_patches.append(e)
  sc = wc.build(stage)                           # closed doors for the walk grid
elif GRID_ONLY:
  door_patches = site_old.get('doors', [])

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
    "doors": door_patches,
    "removed_plants": len(wc.REMOVED_PLANTS),
    "site_frame": {"x_axis": "east", "y_axis": "south"},
    "points": {"forum": [float(wc.RC[0]) + 6.0, 60.0], "portico": [float(wc.RC[0]), 26.0], "theatre": [44.0, 44.0], "terraces": [40.0, -12.0]},
}
json.dump(site, open(os.path.join(out, "site.json"), "w"))
log(f"walk grid {kind.shape}: walk {np.sum(kind == 0)}, blocked {np.sum(kind == 1)}, water {np.sum(kind == 2)}, green {np.sum(kind == 3)}")
log("done")
