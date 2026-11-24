#!/usr/bin/env python3
"""Living Assets – loads ORIGINAL source sprites (read-only) for the game keys
of tools/assets/penzilla_selection.json, at source resolution.

Composed RPG buildings (shops, tent) are flattened exactly like the main
import (import_penzilla.compose), so states line up with the game files."""
import io
import json
import os
import sys
import zipfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import import_penzilla  # noqa: E402

PACK_FILES = None


LAYER_RULES = [  # keyword in the RPG layer name -> material (first match wins)
    ("fabric", "fabric"), ("tent", "fabric"), ("brick", "brick"), ("stone", "stone"), ("window", "window"),
    ("roof", "roof"), ("outerwall", "plaster"), ("innerwalls", "plaster"), ("door", "wood"), ("beam", "wood"),
    ("floor", "wood"), ("display", "wood"), ("sign", "wood"), ("storetype", "trim"), ("items", "trim"),
]


def layer_material(name):
    n = name.lower()
    for key, mat in LAYER_RULES:
        if key in n:
            return mat
    return ""


class Sources:
    def __init__(self, src_dir):
        with open(os.path.join(HERE, "penzilla_selection.json"), encoding="utf-8") as f:
            self.sel = json.load(f)
        self.src_dir = src_dir
        self.archives = {}

    def _zip(self, pack):
        if pack not in self.archives:
            self.archives[pack] = zipfile.ZipFile(os.path.join(self.src_dir, self.sel["packs"].get(pack, pack)))
        return self.archives[pack]

    def load(self, key=None, pack=None, path=None):
        """key: game key like 'buildings/house_1' (without .png), or pack+path
        for files not used in the game yet (vehicles, interiors).
        Returns (float32 RGBA array, info dict)."""
        if key is not None:
            rel = key + ".png"
            if rel in self.sel["files"]:
                spec = self.sel["files"][rel]
                pack, path = spec[0], spec[1]
            elif rel in self.sel.get("composed", {}):
                spec = self.sel["composed"][rel]
                archives = {p: self._zip(p) for p in self.sel["packs"] if os.path.exists(os.path.join(self.src_dir, self.sel["packs"][p]))}
                img, anchor = import_penzilla.compose(archives, spec)
                a = np.asarray(img.convert("RGBA")).astype(np.float32) / 255.0
                # Layer names tell the material exactly (e.g. "OuterWall_ClayBrick",
                # "Fabric_Green"): topmost opaque layer per pixel -> material hint.
                hint = np.full(a.shape[:2], "", object)
                for layer in spec["layers"]:
                    one, _ = import_penzilla.compose(archives, dict(spec, layers=[layer]))
                    m = np.asarray(one.getchannel("A")) > 127
                    hint[m[:hint.shape[0], :hint.shape[1]]] = layer_material(layer)
                return a, {"source": spec["pack"] + ":" + spec["dir"] + " (zusammengesetzt)", "pack": spec["pack"], "hint": hint}
            else:
                raise KeyError(key)
        data = self._zip(pack).read(path)
        img = Image.open(io.BytesIO(data)).convert("RGBA")
        return np.asarray(img).astype(np.float32) / 255.0, {"source": pack + ":" + path, "pack": pack}
