#!/usr/bin/env python3
"""Cooked FX (The Cooked Works, free pack) – PRIVATE evaluation import.

Usage: python3 -I tools/assets/import_cooked_fx.py <Cooked_FX_FREE_Cozy_Chunky.zip> [<project_root>]

License (LICENSE.pdf in the pack, v1.0 Oct 2026): use and modification in
unlimited projects allowed; the files may NOT be redistributed "on their
own, original or modified", including uploads to a repository. Therefore the
output goes to assets/thirdparty/cooked_fx/ which is git-ignored – never
commit it. Inside a finished game build the files are allowed.

The archive is treated as untrusted: only .png/.json/.pdf entries without
absolute paths, '..' or symlinks are read; nothing is executed.

Output per selected effect (Cozy Chunky, PNG_2x sheets downscaled to 1x for
crisp retina rendering):
  raw/<name>.png       original strip (frames left to right)
  adapted/<name>.png   WORLDS adaptation: contour -> Penzilla #330022, soft glow
                       halos removed (Penzilla has none), top-down variants
                       squashed 2:1 onto the isometric ground plane
  fx.json              frames, fps, loop, view, cell size (raw and adapted)
"""
import io
import json
import os
import stat
import sys
import zipfile

import numpy as np
from PIL import Image

THEME = "Cooked_FX_FREE/Cozy_Chunky/"
# effect -> (adaptation) ; selected for WORLDS (no combat/blood/magic)
SELECT = {
    "nature/fire_side": {}, "nature/smoke_side": {}, "nature/smoke_top": {"squash": True},
    "combat/explosion_side": {"deglow": True}, "combat/explosion_top": {"deglow": True, "squash": True},
    "nature/water_side": {}, "nature/water_top": {"squash": True},
    "nature/leaves_side": {}, "nature/leaves_top": {"squash": True},
    "nature/rocks_side": {}, "nature/rocks_top": {"squash": True},
    "movement/dust_side": {}, "movement/dust_top": {"squash": True},
    "movement/poof_side": {}, "movement/footstep_top": {"squash": True},
    "status/burn": {}, "status/sleep": {}, "status/stun": {},
    "combat/hit_side": {"deglow": True},
    "pickup_ui/coins_side": {}, "pickup_ui/coins_top": {"squash": True}, "pickup_ui/star": {"deglow": True},
    "pickup_ui/confetti_side": {}, "pickup_ui/heart": {}, "pickup_ui/level_up": {}, "pickup_ui/pickup": {"deglow": True},
}
OUTLINE = np.array([51, 0, 34], np.float32) / 255.0


def safe_entries(z):
    for i in z.infolist():
        n = i.filename
        mode = (i.external_attr >> 16) & 0o170000
        if n.startswith("/") or ".." in n.split("/") or mode == stat.S_IFLNK:
            raise SystemExit(f"unsafe entry: {n}")
        if not i.is_dir() and os.path.splitext(n)[1].lower() not in (".png", ".json", ".pdf"):
            raise SystemExit(f"unexpected file type: {n}")
    return {i.filename: i for i in z.infolist()}


def adapt(img, cell, frames, squash, deglow):
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = a[..., :3] @ np.array([0.299, 0.587, 0.114], np.float32)
    line = (a[..., 3] > 0.3) & (lum < 0.25)
    a[line, :3] = OUTLINE
    if deglow:
        a[a[..., 3] < 0.75, 3] = 0.0
    out = Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    if squash:
        out = out.resize((out.width, out.height // 2), Image.LANCZOS)
    return out


def main():
    zpath = os.path.abspath(sys.argv[1])
    root = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out = os.path.join(root, "assets", "thirdparty", "cooked_fx")
    os.makedirs(os.path.join(out, "raw"), exist_ok=True)
    os.makedirs(os.path.join(out, "adapted"), exist_ok=True)
    with open(os.path.join(root, "assets", "thirdparty", ".gitignore"), "w") as f:
        f.write("# third-party files that must not be redistributed (licenses forbid repository uploads)\n*\n!.gitignore\n")
    z = zipfile.ZipFile(zpath)
    entries = safe_entries(z)
    anims = json.loads(z.read(THEME + "anims.json"))
    meta = {"source": "Cooked FX – 40 Free Game Effects, theme Cozy Chunky (The Cooked Works)", "license": "LICENSE.pdf v1.0 (Oct 2026): use/modify in unlimited projects, no redistribution of the files (incl. repositories)", "effects": {}}
    for key, opt in SELECT.items():
        a = anims[key]
        n, cell2 = int(a["frames"]), int(a["cell"]) * 2
        raw2 = Image.open(io.BytesIO(z.read(THEME + "PNG_2x/" + key + ".png"))).convert("RGBA")
        raw = raw2.resize((raw2.width // 2, raw2.height // 2), Image.LANCZOS)
        name = key.replace("/", "_")
        raw.save(os.path.join(out, "raw", name + ".png"), optimize=True)
        ad = adapt(raw, a["cell"], n, opt.get("squash", False), opt.get("deglow", False))
        ad.save(os.path.join(out, "adapted", name + ".png"), optimize=True)
        meta["effects"][name] = {"frames": n, "fps": a["fps"], "loop": a["loop"], "view": a["view"], "cell": a["cell"],
                                 "adapted_cell": [a["cell"], a["cell"] // 2 if opt.get("squash") else a["cell"]], "adaptation": opt}
    with open(os.path.join(out, "fx.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1, ensure_ascii=False)
    print(f"{len(meta['effects'])} effects -> {out} (git-ignored)")


if __name__ == "__main__":
    main()
