#!/usr/bin/env python3
"""Builds the modular character layers from Penzilla "Ultimate Protagonist".

Usage:
    python3 -I tools/assets/import_character.py <dir_with_zips> [<project_root>] [anim,anim,...]

Reads AnimationSheets/CustomaizableCharacter/<Animation>/<Layer>.png directly
from Ultimate_Protagonist.zip and writes, per animation and item:
    assets/penzilla/character/layers/<anim>/<item>.png
Each sheet keeps Penzilla's layout (5 direction rows x N frames) but every
frame is cropped to the area any layer actually uses (crop rect from
data/character_catalog.json) and scaled down (file_scale). Colour variants
are NOT exported: the catalog stores Penzilla's exact colour multipliers and
the game tints the white "Blank" layer (verified to match the original
variants within a few colour levels). Families without a Blank layer
(faces, shoes, necklaces) are exported per variant.

Output is git-ignored (purchased asset, no redistribution). Requires Pillow.
"""
import io
import json
import os
import re
import sys
import zipfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_FRAME = 460
BASE = "AnimationSheets/CustomaizableCharacter/"
# Known typos/inconsistencies in the pack's file names.
TYPO = {"sjy": "sky", "whitewood": "whitewood"}


def norm(name):
    n = name.lower().replace(" ", "").replace(".png", "")
    for a, b in TYPO.items():
        n = n.replace(a, b)
    return n


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src_dir = os.path.abspath(sys.argv[1])
    root = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(HERE))
    with open(os.path.join(root, "data", "character_catalog.json"), encoding="utf-8") as f:
        cat = json.load(f)
    frame = cat["frame"]
    scale = float(frame["file_scale"])

    zpath = os.path.join(src_dir, "Ultimate_Protagonist.zip")
    z = zipfile.ZipFile(zpath)
    index = {}
    for full in z.namelist():
        if full.startswith(BASE) and full.endswith(".png"):
            folder, fname = full[len(BASE):].split("/", 1)
            index[(folder, norm(fname))] = full

    out_root = os.path.join(root, "assets", "penzilla", "character", "layers")
    written, missing, repaired = 0, [], []
    total_bytes = 0
    only = set(sys.argv[3].split(",")) if len(sys.argv) > 3 else None
    for anim_id, anim in cat["anims"].items():
        if only and anim_id not in only:
            continue
        folder = anim["source_folder"]
        # per-animation crop (wide tool swings, sitting) – default: the common frame
        crop = anim.get("crop_src", frame["crop_src"])
        cw, ch = crop[2] - crop[0], crop[3] - crop[1]
        out_w, out_h = round(cw * scale), round(ch * scale)
        for item_id, item in cat["items"].items():
            if anim_id not in item.get("anims", list(cat["anims"].keys())):
                continue
            src_names = item["source"].get(anim_id, item["source"]["default"]) if isinstance(item["source"], dict) else item["source"]
            if isinstance(src_names, str):
                src_names = [src_names]
            full = None
            for s in src_names:
                full = index.get((folder, norm(s)))
                if full:
                    break
            if full is None:
                missing.append(f"{anim_id}/{item_id}")
                continue
            img = Image.open(io.BytesIO(z.read(full))).convert("RGBA")
            cols, rows = img.width // SRC_FRAME, img.height // SRC_FRAME
            sheet = Image.new("RGBA", (cols * out_w, rows * out_h))
            for r in range(rows):
                cells = [img.crop((c * SRC_FRAME + crop[0], r * SRC_FRAME + crop[1],
                                   c * SRC_FRAME + crop[2], r * SRC_FRAME + crop[3])) for c in range(cols)]
                filled = [cell.getchannel("A").getbbox() is not None for cell in cells]
                for c in range(cols):
                    cell = cells[c]
                    # Repair single empty frames in otherwise drawn rows (pack
                    # defect, e.g. Beanie Idle NW frame 0) from the nearest frame.
                    # (only a single gap: several empty frames are real occlusion,
                    # e.g. a bow tie hidden while bending down to dig)
                    if not filled[c] and any(filled) and filled.count(False) == 1:
                        src = min((i for i in range(cols) if filled[i]), key=lambda i: abs(i - c))
                        cell = cells[src]
                        repaired.append(f"{anim_id}/{item_id} row {r} frame {c} <- frame {src}")
                    sheet.paste(cell.resize((out_w, out_h), Image.LANCZOS), (c * out_w, r * out_h))
            dest = os.path.abspath(os.path.join(out_root, anim_id, item_id + ".png"))
            if not dest.startswith(out_root + os.sep):
                raise SystemExit("unsafe path")
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            q = sheet.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
            q.save(dest, optimize=True)
            total_bytes += os.path.getsize(dest)
            written += 1
    print(f"character layers: {written} sheets, {total_bytes / 1e6:.1f} MB")
    for line in repaired:
        print("repaired empty frame:", line)
    if missing:
        print(f"not available in pack ({len(missing)}): {', '.join(missing)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
