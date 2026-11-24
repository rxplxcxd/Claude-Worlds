#!/usr/bin/env python3
"""Living Assets – step G production: state bases + overlays for the assets
listed in tools/assets/living_assets.json.

Usage:
  python3 -I tools/assets/make_living_states.py <dir_with_zips> [<project_root>] [--pilot | --only key1,key2] [--qa <dir>]

Reads ORIGINAL Penzilla files (never modified) and writes derived files to
assets/penzilla/states/ (git-ignored: derived Penzilla graphics are not
redistributed) plus states.json (manifest for the Godot composer). With
--qa <dir>: material maps, contact sheets and qa_report.json for review.
Requires numpy, scipy, pillow. Deterministic (fixed seeds per asset).
"""
import json
import os
import sys
import time
import zlib

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import living_states as LS  # noqa: E402
import living_traits as T  # noqa: E402
from living_materials import MaterialSeg  # noqa: E402
from living_sources import Sources  # noqa: E402

FILE_SCALE = 0.5
MANIFEST_VERSION = 2


def seed_of(key, name):
    return zlib.crc32((key + "/" + name).encode()) % 100000


def save_scaled(arr, path):
    img = LS.to_image(arr)
    img = img.resize((max(1, round(img.width * FILE_SCALE)), max(1, round(img.height * FILE_SCALE))), Image.LANCZOS)
    img.save(path, optimize=True)
    return os.path.getsize(path)


def overlay_even(variant, original):
    """Changed pixels cropped to a box with even offsets (exact at scale 0.5)."""
    ov, box = T.overlay_of(variant, original)
    if ov is None:
        return None, None
    x0, y0 = box[0] - box[0] % 2, box[1] - box[1] % 2
    full = np.zeros_like(variant)
    diff = (np.abs(variant - original).max(-1) > 0.02) & (variant[..., 3] > 0.02)
    full[diff] = variant[diff]
    return full[y0:box[3], x0:box[2]], (x0, y0)


def _shift_overrides(rules, p):
    if not rules:
        return rules
    out = []
    for r in rules:
        r = dict(r)
        if "rect" in r:
            x0, y0, x1, y1 = r["rect"]
            r["rect"] = [x0 + p, y0 + p, x1 + p, y1 + p]
        out.append(r)
    return out


def split_items(a):
    """Pixel-art sheets: one box per item (connected opaque area)."""
    from scipy import ndimage
    lab, n = ndimage.label(a[..., 3] > 0.1, structure=np.ones((3, 3)))
    return [sl for sl in ndimage.find_objects(lab) if sl is not None and (sl[0].stop - sl[0].start) * (sl[1].stop - sl[1].start) >= 16]


def produce(key, spec, src, out_root, qa):
    t0 = time.time()
    if "source" in spec:
        a, info = src.load(pack=spec["source"][0], path=spec["source"][1])
    else:
        a, info = src.load(key)
    cat = spec["category"]
    d = os.path.join(out_root, key)
    os.makedirs(d, exist_ok=True)
    entry = {"source": info["source"], "category": cat, "canvas_src": [a.shape[1], a.shape[0]], "bases": {}, "layers": {}}
    previews = {"original": a}
    total = 0
    if cat == "interior":
        entry["profile"] = "interior"
        entry["pixel_art"] = True
        for st in T.INTERIOR_STATES:
            v = a.copy()
            for i, sl in enumerate(split_items(a)):
                v[sl] = T.interior_variant(a[sl], st, seed_of(key, st) + i)
            Image.fromarray((np.clip(v, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(d, st + ".png"), optimize=True)
            entry["bases"][st] = {"file": f"{key}/{st}.png", "scale": 1.0}
            previews[st] = v
        return entry, previews, None, time.time() - t0
    if "source" in spec and cat != "interior":
        # not imported by the game yet: ship the original next to its states
        total += save_scaled(a, os.path.join(d, "original.png"))
        entry["original"] = f"{key}/original.png"
    if cat == "surface":
        seg = MaterialSeg(a, cat)
        entry["materials"] = seg.stats()
        return entry, previews, seg, time.time() - t0
    # Work on a padded canvas so rubble, ivy or a toppled object is never cut
    # off at the border. Overlays may therefore have negative offsets; bases
    # are cropped back to the original canvas whenever their content fits.
    H, W = a.shape[:2]
    P = int((0.08 if cat == "building" else 0.2) * max(H, W)) // 2 * 2
    ap = np.pad(a, ((P, P), (P, P), (0, 0)))
    hint = info.get("hint")
    if hint is not None:
        hint = np.pad(hint, ((P, P), (P, P)), constant_values="")
    seg = MaterialSeg(ap, cat, default_material=spec.get("default_material"), overrides=_shift_overrides(spec.get("overrides"), P), hint=hint)
    entry["materials"] = seg.stats()
    previews = {"original": ap}
    prof = T.PROFILES[spec["profile"]]
    entry["profile"] = spec["profile"]
    for name, fn in prof["bases"].items():
        v = fn(ap, seg, seed_of(key, name))
        dx, dy = (v.shape[1] - W) // 2, (v.shape[0] - H) // 2
        inner = v[dy:dy + H, dx:dx + W]
        if (inner[..., 3] > 0.02).sum() == (v[..., 3] > 0.02).sum():
            saved, pad = inner, [0, 0]
        else:
            saved, pad = v, [dx, dy]
        total += save_scaled(saved, os.path.join(d, "base_" + name + ".png"))
        entry["bases"][name] = {"file": f"{key}/base_{name}.png", "canvas_src": [saved.shape[1], saved.shape[0]], "pad_src": pad}
        previews["base:" + name] = v
    for name, (fn, lv) in prof["layers"].items():
        v = fn(ap, seg, lv, seed_of(key, name))
        ov, off = overlay_even(v, ap)
        if ov is None:
            continue
        total += save_scaled(ov, os.path.join(d, "overlay_" + name + ".png"))
        entry["layers"][name] = {"file": f"{key}/overlay_{name}.png", "offset_src": [int(off[0]) - P, int(off[1]) - P], "size_src": [ov.shape[1], ov.shape[0]], "coverage": round(float((ov[..., 3] > 0.5).sum()) / max(1, float((a[..., 3] > 0.5).sum())), 3)}
        previews["layer:" + name] = (ov, off)
    # Pre-clipped overlays per structural base: overlay pixels that would hang
    # in the air where the base has collapsed are removed at build time, so
    # the runtime only stacks sprites (no per-pixel work, batching intact).
    allowed = T.ALLOWED if spec["profile"] in ("building", "tent") else {}
    for bname in entry["bases"]:
        base = previews["base:" + bname]
        if base.shape != ap.shape:
            continue
        for lname in allowed.get(bname, ()):
            if "layer:" + lname not in previews:
                continue
            if lname == "snow_1":
                # snow lies on the surfaces of THIS base (wall tops of a ruin …)
                bseg = MaterialSeg(base, cat)
                sv = T.snow_layer(base, bseg, 1, seed_of(key, "snow@" + bname))
                sov, soff = overlay_even(sv, base)
                if sov is not None:
                    fn = f"overlay_snow_1@{bname}.png"
                    total += save_scaled(sov, os.path.join(d, fn))
                    entry["layers"]["snow_1"].setdefault("own", {})[bname] = {"file": f"{key}/{fn}", "offset_src": [int(soff[0]) - P, int(soff[1]) - P]}
                    previews["layer:snow_1@" + bname] = (sov, soff)
                continue
            ov, (ox, oy) = previews["layer:" + lname]
            h, w = ov.shape[:2]
            allow = (base[oy:oy + h, ox:ox + w, 3] > 0.5) | (ap[oy:oy + h, ox:ox + w, 3] <= 0.5)
            if allow.all():
                continue
            clipped = ov.copy()
            clipped[~allow] = 0.0
            if not (clipped[..., 3] > 0.02).any():
                entry["layers"][lname].setdefault("skip_on", []).append(bname)
                continue
            fn = f"overlay_{lname}@{bname}.png"
            total += save_scaled(clipped, os.path.join(d, fn))
            entry["layers"][lname].setdefault("clipped", {})[bname] = f"{key}/{fn}"
    entry["bytes"] = total
    return entry, previews, seg, time.time() - t0


def produce_family(fam, members, specs, src, out_root):
    rep = members[0]
    # a representative, plain tile of the family (road_5 / path_5 = straight piece)
    for pref in ("tiles/road_5", "tiles/path_5", "tiles/sidewalk", "tiles/grass", "tiles/dirt", "tiles/water"):
        if pref in members:
            rep = pref
            break
    a, info = src.load(rep)
    seg = MaterialSeg(a, "surface")
    d = os.path.join(out_root, "surfaces", fam)
    os.makedirs(d, exist_ok=True)
    out = {"representative": rep, "members": members, "layers": {}}
    previews = {"original": a}
    for st in T.SURFACE_FAMILIES[fam]:
        v = T.surface_layer(a, seg, st, seed_of(fam, st))
        ov, off = overlay_even(v, a)
        if ov is None:
            continue
        save_scaled(ov, os.path.join(d, "overlay_" + st + ".png"))
        out["layers"][st] = {"file": f"surfaces/{fam}/overlay_{st}.png", "offset_src": [int(off[0]), int(off[1])], "size_src": [ov.shape[1], ov.shape[0]]}
        previews["layer:" + st] = (ov, off)
    return out, previews


def main():
    args = sys.argv[1:]
    qa_dir = None
    if "--qa" in args:
        i = args.index("--qa")
        qa_dir = os.path.abspath(args[i + 1])
        del args[i:i + 2]
    pilot = "--pilot" in args
    only = None
    if "--only" in args:
        i = args.index("--only")
        only = set(args[i + 1].split(","))
        del args[i:i + 2]
    args = [x for x in args if not x.startswith("--")]
    src = Sources(os.path.abspath(args[0]))
    root = os.path.abspath(args[1]) if len(args) > 1 else os.path.dirname(os.path.dirname(HERE))
    out_root = os.path.join(root, "assets", "penzilla", "states")
    os.makedirs(out_root, exist_ok=True)
    with open(os.path.join(HERE, "living_assets.json"), encoding="utf-8") as f:
        cfg = json.load(f)
    keys = cfg["pilot"] if pilot else list(cfg["assets"])
    if only:
        keys = [k for k in keys if k in only]
    man_path = os.path.join(out_root, "states.json")
    manifest = {}
    if os.path.exists(man_path):
        with open(man_path, encoding="utf-8") as f:
            manifest = json.load(f)
    if manifest.get("version") != MANIFEST_VERSION:
        manifest = {"version": MANIFEST_VERSION, "file_scale": FILE_SCALE, "assets": {}, "surface_families": {}}
    manifest["layer_order"] = list(T.LAYER_ORDER)
    manifest["allowed"] = {k: sorted(v) for k, v in T.ALLOWED.items()}
    manifest["presets"] = [{"key": k, "label": lbl, **{kk: (list(vv) if isinstance(vv, tuple) else vv) for kk, vv in p.items()}} for k, lbl, p in T.PRESETS]
    all_previews = {}
    families = {}
    for key in keys:
        spec = cfg["assets"][key]
        if spec["category"] == "surface":
            families.setdefault(spec["family"], []).append(key)
            manifest["assets"][key] = {"category": "surface", "family": spec["family"]}
            continue
        entry, previews, seg, dt = produce(key, spec, src, out_root, qa_dir)
        manifest["assets"][key] = entry
        all_previews[key] = (spec, previews, seg)
        print(f"{key}: {len(entry['bases'])} bases, {len(entry['layers'])} overlays, {dt:.1f} s", flush=True)
    for fam, members in families.items():
        all_members = [k for k, s in cfg["assets"].items() if s.get("category") == "surface" and s.get("family") == fam]
        out, previews = produce_family(fam, all_members, cfg["assets"], src, out_root)
        manifest["surface_families"][fam] = out
        for m in all_members:
            manifest["assets"].setdefault(m, {"category": "surface", "family": fam})
        all_previews["surface:" + fam] = ({"category": "surface", "family": fam}, previews, None)
        print(f"surface family {fam}: {len(out['layers'])} overlays (shared by {len(all_members)} tiles)", flush=True)
    with open(man_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
    total = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(out_root) for fn in fns if fn.endswith(".png"))
    print(f"-> {out_root} ({total / 1e6:.2f} MB PNG)")
    if qa_dir:
        import living_qa
        living_qa.run(all_previews, manifest, qa_dir, src)


if __name__ == "__main__":
    main()
