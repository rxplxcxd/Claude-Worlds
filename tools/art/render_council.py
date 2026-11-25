"""Renders the World Council (tools/art/world_council.py) to PNG.
Usage: python -I render_council.py <out.png> [px_per_m] [stage] [ss]"""
import sys, os, time, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import isorender as ir
import world_council as wc
import council_materials as cm

out = sys.argv[1]
px = float(sys.argv[2]) if len(sys.argv) > 2 else 4.0
stage = int(sys.argv[3]) if len(sys.argv) > 3 else 1
ss = int(sys.argv[4]) if len(sys.argv) > 4 else 2
t = time.time()
sc = wc.build(stage)
mats = cm.make_materials(centre_dome=wc.RC, moss=0.3 if stage <= 1 else 0.0, small_domes=wc.DOMES, mosaics=wc.MOSAICS)
mats['inscription'] = cm.inscription('efe6d4', z0=wc.PODIUM_Z + 16.2, z1=wc.PODIUM_Z + 17.4)
mats['lettering'] = cm.lettering('efe6d4', wc.INSCRIPTIONS, fallback=cm.stone('efe6d4', weather=0.05, seed=9))
frame = tuple(float(v) for v in os.environ['WC_FRAME'].split(',')) if os.environ.get('WC_FRAME') else None
img, buf = ir.render(sc, mats, px, ss=ss, frame=frame, shade_fn=cm.overgrowth(1.0 if stage <= 1 else (0.35 if stage == 2 else 0.0)), log=lambda m: print(f"[{time.time() - t:6.1f}s] {m}", flush=True))
ir.save_png(img, out)
meta = {"origin_m": list(buf["origin"]), "px_per_m": px, "size": [img.shape[1], img.shape[0]]}
json.dump(meta, open(os.path.splitext(out)[0] + ".json", "w"))
print("saved", out, img.shape, f"{time.time() - t:.1f}s")
