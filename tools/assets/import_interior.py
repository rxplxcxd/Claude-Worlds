#!/usr/bin/env python3
"""Copies the six sheets of Penzilla "Top-Down Retro Interior" into the game.

Usage: python3 -I tools/assets/import_interior.py <dir_with_zips> [<project_root>]

Only the six known PNG sheets are read (names checked, no paths from the
archive are used). Output: assets/penzilla/interior/*.png – purchased art,
git-ignored, never redistributed (assets/penzilla/ is private).
"""
import os
import sys
import zipfile

NAMES = ["TopDownHouse_DoorsAndWindows.png", "TopDownHouse_FloorsAndWalls.png", "TopDownHouse_FloorsAndWalls_OpenDoors.png",
         "TopDownHouse_FurnitureState1.png", "TopDownHouse_FurnitureState2.png", "TopDownHouse_SmallItems.png"]


def main():
    src = os.path.abspath(sys.argv[1])
    root = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out = os.path.join(root, "assets", "penzilla", "interior")
    os.makedirs(out, exist_ok=True)
    z = zipfile.ZipFile(os.path.join(src, "Top-Down_Retro_Interior.zip"))
    members = {os.path.basename(n): n for n in z.namelist() if n.lower().endswith(".png")}
    for name in NAMES:
        if name not in members:
            print("missing in archive:", name)
            continue
        data = z.read(members[name])
        if not data.startswith(b"\x89PNG"):
            raise SystemExit("not a PNG: " + name)
        with open(os.path.join(out, name), "wb") as f:
            f.write(data)
        print("imported", name, len(data), "bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
