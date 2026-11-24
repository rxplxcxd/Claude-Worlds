#!/usr/bin/env python3
"""Living Assets – steps C/E: sample state files for the Godot check.

Usage: python3 -I tools/assets/make_living_samples.py <dir_with_zips> [<project_root>]

Reads ORIGINAL Penzilla files from the ZIPs (never modified) and writes
derived sample files to assets/penzilla/states/ (git-ignored – derived
Penzilla graphics are not redistributed). Files are downscaled like the main
import (file_scale 0.5) and keep the original canvas/anchor, so they drop in
for the original sprite.

Three tiers (docs/living_assets/TECHNICAL_INTEGRATION.md):
  tier 1  no file – shader shaders/living_wear.gdshader (dirt, fading)
  tier 2  overlay – only the changed pixels (cracks, glass, roof holes),
          cropped to their bounding box, drawn above the original
  tier 3  full variant – structural states (burnt, destroyed, ruin …)
Requires numpy, scipy, pillow.
"""
import io
import json
import os
import sys
import time
import zipfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import living_states as L  # noqa: E402

SCALE = 0.5
GCB = "GiantCityBuilder.zip"

SAMPLES = {
    # name: (pack, path, category)
    "house_blue": (GCB, "Houses/Blue/House_Type1.png", "building"),
    "tree": (GCB, "Plants/Tree1.png", "vegetation"),
    "bare_tree": (GCB, "Plants/BareTree1.png", "vegetation"),
    "road": (GCB, "Tiles/Road_Tile5.png", "surface"),
    "lamp": (GCB, "DecorItems/StreetLampOff.png", "furniture"),
    "bench": (GCB, "DecorItems/Seat.png", "furniture"),
    "car": (GCB, "Vehicles/CarType1_Red_Front.png", "vehicle"),
}


def damage_only(a, seed):
    """Tier-2 content for buildings: only local damage (no global colour change)."""
    seg = L.Seg(a)
    o = L.peel(a, seg, 0.5, seed)
    o = L.cracks(o, seg, 5, seed + 1)
    o = L.broken_windows(o, seg, 0.6, seed)
    return L.roof_holes(o, seg, 2, seed)


def overlay_of(variant, original):
    diff = np.abs(variant - original).max(-1) > 0.02
    out = np.zeros_like(variant)
    out[diff] = variant[diff]
    out[diff, 3] = 1.0
    ys, xs = np.nonzero(diff)
    if len(xs) == 0:
        return None, None
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    return out[box[1]:box[3], box[0]:box[2]], box


def save_scaled(arr, path):
    img = L.to_image(arr)
    img = img.resize((max(1, round(img.width * SCALE)), max(1, round(img.height * SCALE))), Image.LANCZOS)
    img.save(path, optimize=True)
    return img.size


def main():
    src = os.path.abspath(sys.argv[1])
    root = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(HERE))
    out_dir = os.path.join(root, "assets", "penzilla", "states")
    os.makedirs(out_dir, exist_ok=True)
    zips = {}
    manifest = {"scale": SCALE, "assets": {}}
    for name, (pack, path, cat) in SAMPLES.items():
        zf = zips.setdefault(pack, zipfile.ZipFile(os.path.join(src, pack)))
        a = np.asarray(Image.open(io.BytesIO(zf.read(path))).convert("RGBA")).astype(np.float32) / 255.0
        d = os.path.join(out_dir, name)
        os.makedirs(d, exist_ok=True)
        entry = {"source": path, "category": cat, "src_size": [a.shape[1], a.shape[0]], "files": {}}
        t = time.time()
        save_scaled(a, os.path.join(d, "original.png"))
        if cat == "building":
            ov, box = overlay_of(damage_only(a, 3), a)
            if ov is not None:
                save_scaled(ov, os.path.join(d, "overlay_damage.png"))
                entry["files"]["overlay_damage"] = {"tier": 2, "offset_src": [box[0], box[1]]}
            for key in ("08_schwer_beschaedigt", "09_ausgebrannt", "10_zerstoert", "11_ruine"):
                save_scaled(L.building_state(a, key, 3), os.path.join(d, key + ".png"))
                entry["files"][key] = {"tier": 3}
        elif cat == "vegetation":
            for key, _ in L.VEGETATION_STATES:
                if key in ("normal", "gesund"):
                    continue
                save_scaled(L.vegetation(a, key, 4), os.path.join(d, key + ".png"))
                entry["files"][key] = {"tier": 3}
        elif cat == "surface":
            for key, _ in L.SURFACE_STATES:
                if key == "normal":
                    continue
                v = L.surface(a, key, 4)
                ov, box = overlay_of(v, a)
                if ov is not None:
                    save_scaled(ov, os.path.join(d, "overlay_" + key + ".png"))
                    entry["files"]["overlay_" + key] = {"tier": 2, "offset_src": [box[0], box[1]]}
        elif cat == "furniture":
            for key, _ in L.FURNITURE_STATES:
                if key in ("neu", "normal", "verwittert"):
                    continue  # tier 1 (shader)
                v = L.furniture(a, key, 4)
                p = os.path.join(d, key + ".png")
                save_scaled(v, p)
                entry["files"][key] = {"tier": 3, "canvas": [v.shape[1], v.shape[0]]}
        elif cat == "vehicle":
            for key, _ in L.VEHICLE_STATES:
                if key in ("normal", "verschmutzt"):
                    continue
                save_scaled(L.vehicle(a, key, 4), os.path.join(d, key + ".png"))
                entry["files"][key] = {"tier": 3}
        manifest["assets"][name] = entry
        print(f"{name}: {len(entry['files'])} files, {time.time() - t:.1f} s")
    with open(os.path.join(out_dir, "states.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    total = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(out_dir) for fn in fns)
    print(f"→ {out_dir} ({total / 1e6:.2f} MB)")


if __name__ == "__main__":
    main()
