#!/usr/bin/env python3
"""Builds assets/penzilla/ from the purchased Penzilla ZIP archives.

Usage:
    python3 -I tools/assets/import_penzilla.py <dir_with_zips> [<project_root>]

* Reads only the files listed in tools/assets/penzilla_selection.json directly
  from the ZIPs (no full extraction, archive paths are never used as output
  paths). The original archives are never modified.
* Writes downscaled PNGs (file_scale, default 0.5) to assets/penzilla/ and an
  import_meta.json with the ORIGINAL pixel size and an automatic anchor
  (bottom-centre of the visible content) per file.
* assets/penzilla/ is git-ignored: the purchased assets are not redistributed
  through the public repository. CI regenerates it from a private source.

Requires Pillow.
"""
import io
import json
import os
import sys
import zipfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def content_anchor(img):
    """Bottom-centre of the visible pixels (alpha > 60), in image pixels."""
    alpha = img.getchannel("A").point(lambda v: 255 if v > 60 else 0)
    bbox = alpha.getbbox()
    if bbox is None:
        return [img.width / 2, img.height], [0, 0, img.width, img.height]
    bottom = bbox[3] - 1
    xs = [x for x in range(bbox[0], bbox[2]) if alpha.getpixel((x, bottom))]
    cx = (xs[0] + xs[-1]) / 2 if xs else (bbox[0] + bbox[2]) / 2
    return [cx, float(bbox[3])], list(bbox)


def footprint_bottom(floor):
    """Bottom vertex of an isometric floor layer, in image pixels.

    The RPG packs draw the floor partly hidden behind the front walls, so the
    bottom vertex is reconstructed from the left/right vertices and the slope
    of the (fully visible) back edges."""
    a = floor.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    x0, y0, x1, y1 = a.getbbox()
    def rows(x):
        ys = [y for y in range(y0, y1) if a.getpixel((x, y))]
        return (ys[0] + ys[-1]) / 2
    left, right = (x0 + 1, rows(x0 + 1)), (x1 - 2, rows(x1 - 2))
    cx = (x0 + x1) // 2
    top_y = next(y for y in range(y0, y1) if a.getpixel((cx, y)))
    slope = (left[1] - top_y) / (cx - left[0])
    bx = (right[1] - left[1] + slope * (left[0] + right[0])) / (2 * slope)
    return [bx, left[1] + slope * (bx - left[0])], right[0] - left[0], slope


def compose(archives, spec):
    """Flattens a layered Penzilla building (RPG pack) into one image and
    maps it onto the Giant-City-Builder grid: footprint width -> tiles * 512
    source px, vertical squash so the edge slope matches 292/512."""
    zf = archives[spec["pack"]]
    base = spec["dir"].rstrip("/") + "/"
    layers = [Image.open(io.BytesIO(zf.read(base + name))).convert("RGBA") for name in spec["layers"]]
    img = Image.new("RGBA", layers[0].size, (0, 0, 0, 0))
    for layer in layers:
        img.alpha_composite(layer)
    if "floor" in spec:
        floor = Image.open(io.BytesIO(zf.read(base + spec["floor"]))).convert("RGBA")
        bottom, width, slope = footprint_bottom(floor)
        sx = spec.get("tiles", 1) * 512.0 / width
        sy = sx * (146.0 / 256.0) / slope
    else:
        bottom, bbox = content_anchor(img)
        sx = spec["width_src"] / (bbox[2] - bbox[0])
        sy = sx * spec.get("squash_y", 1.0)
    out = img.resize((round(img.width * sx), round(img.height * sy)), Image.LANCZOS)
    anchor = [bottom[0] * sx, bottom[1] * sy]
    return out, anchor


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src_dir = os.path.abspath(sys.argv[1])
    root = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(HERE))
    with open(os.path.join(HERE, "penzilla_selection.json"), encoding="utf-8") as f:
        sel = json.load(f)
    scale = float(sel.get("file_scale", 0.5))
    out_root = os.path.join(root, "assets", "penzilla")
    os.makedirs(out_root, exist_ok=True)

    archives = {}
    for pack, name in sel["packs"].items():
        path = os.path.join(src_dir, name)
        if os.path.exists(path):
            archives[pack] = zipfile.ZipFile(path)
        else:
            print(f"warning: pack '{pack}' not found ({name})")

    meta = {"file_scale": scale, "files": {}}
    missing = []
    for rel, spec in sel["files"].items():
        pack, inner = spec[0], spec[1]
        file_scale = float(spec[2]) if len(spec) > 2 else scale
        if pack not in archives:
            missing.append(rel)
            continue
        try:
            data = archives[pack].read(inner)
        except KeyError:
            print(f"warning: {inner} not in {pack}")
            missing.append(rel)
            continue
        img = Image.open(io.BytesIO(data)).convert("RGBA")
        anchor, bbox = content_anchor(img)
        out = img.resize((max(1, round(img.width * file_scale)), max(1, round(img.height * file_scale))), Image.LANCZOS)
        dest = os.path.abspath(os.path.join(out_root, rel))
        if not dest.startswith(out_root + os.sep):
            raise SystemExit(f"unsafe output path: {rel}")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if dest.lower().endswith(".jpg"):
            out.convert("RGB").save(dest, quality=82, optimize=True)
        else:
            out.save(dest, optimize=True)
        meta["files"]["res://assets/penzilla/" + rel] = {
            "source_pack": sel["packs"][pack],
            "source_file": inner,
            "size": [img.width, img.height],
            "anchor": anchor,
            "bbox": bbox,
        }
    # Layered buildings composed at import time (Isometric RPG Buildings).
    for rel, spec in sel.get("composed", {}).items():
        if spec["pack"] not in archives:
            missing.append(rel)
            continue
        src, anchor = compose(archives, spec)
        out = src.resize((max(1, round(src.width * scale)), max(1, round(src.height * scale))), Image.LANCZOS)
        dest = os.path.abspath(os.path.join(out_root, rel))
        if not dest.startswith(out_root + os.sep):
            raise SystemExit(f"unsafe output path: {rel}")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        out.save(dest, optimize=True)
        meta["files"]["res://assets/penzilla/" + rel] = {
            "source_pack": sel["packs"][spec["pack"]],
            "source_file": spec["dir"] + " (" + ", ".join(spec["layers"]) + ")",
            "size": [src.width, src.height],
            "anchor": anchor,
            "composed": True,
        }
    with open(os.path.join(out_root, "import_meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    total = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(out_root) for fn in fns)
    print(f"imported {len(meta['files'])} files ({total / 1e6:.1f} MB) into {out_root}")
    if missing:
        print(f"missing {len(missing)}: {missing[:10]}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
