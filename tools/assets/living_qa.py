#!/usr/bin/env python3
"""Living Assets – quality control for step G (contact sheets + automatic checks).

Output (private QA folder, NOT the repository – it contains Penzilla pixels):
  <qa>/sheet_<asset>.png     original + all states, full size and real game size
  <qa>/materials_<asset>.png material map
  <qa>/qa_report.json        automatic checks per file and per state
The textual summary of the report may be published (no graphics).

Game size = physical pixels per source pixel on the device:
  world 0.25 px per source px × camera zoom × canvas→screen scale (canvas 960×540,
  stretch "expand") × device pixel ratio.
  iPhone 15 Pro Max (932×430 pt, 3×): default zoom 0.95 -> 0.57, min zoom 0.45 -> 0.27
  older iPhone, e.g. SE 2/3 (667×375 pt, 2×):  default zoom      -> 0.33
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

import living_states as LS
import living_traits as T

GAME_SCALES = [("iPhone 15 Pro Max, Standardzoom", 0.57), ("iPhone 15 Pro Max, kleinster Zoom", 0.27), ("älteres iPhone (SE), Standardzoom", 0.33)]
BG = (126, 168, 92)
try:
    from PIL import ImageFont
    FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
except Exception:  # noqa: BLE001
    FONT = None

STATE_LISTS = {
    # label, base, layers, shader(dirt, fade, darken)
    "tent": [("Neu", "intact", [], (0, 0, 0)), ("Benutzt", "intact", [], (0.3, 0.05, 0)), ("Vernachlässigt", "intact", ["wear_2"], (0.5, 0.2, 0.03)),
             ("Heruntergekommen", "intact", ["wear_3"], (0.7, 0.35, 0.06)), ("Beschädigt", "intact", ["damage_1"], (0.3, 0.05, 0)), ("Brandspuren", "intact", ["fire_1"], (0.2, 0, 0)),
             ("Ausgebrannt", "shell", [], (0, 0, 0)), ("Eingestürzt", "collapsed", [], (0.2, 0, 0)), ("Repariert", "intact", ["repair_1"], (0.1, 0, 0)), ("Schnee", "intact", ["snow_1"], (0, 0, 0))],
    "prop": [("Neu", "intact", [], (0, 0, 0)), ("Benutzt", "intact", [], (0.3, 0.05, 0)), ("Verwittert", "intact", ["wear_2"], (0.45, 0.2, 0.03)), ("Heruntergekommen", "intact", ["wear_3"], (0.6, 0.35, 0.06)),
             ("Beschädigt", "intact", ["damage_1"], (0.3, 0.05, 0)), ("Kombi: verwittert + beschädigt", "intact", ["wear_3", "damage_1"], (0.6, 0.3, 0.05)), ("Zerstört", "broken", [], (0.3, 0.1, 0)),
             ("Verbrannt", "burnt", [], (0, 0, 0)), ("Bewachsen", "intact", ["wear_2", "overgrowth_1"], (0.5, 0.25, 0.04)), ("Schnee", "intact", ["snow_1"], (0, 0, 0))],
    "vehicle": [("Normal", "intact", [], (0, 0, 0)), ("Verschmutzt", "intact", [], (0.55, 0.05, 0)), ("Alt/rostig", "intact", ["wear_2"], (0.4, 0.15, 0.02)), ("Verlassen", "intact", ["wear_3"], (0.65, 0.35, 0.06)),
                ("Beschädigt", "intact", ["damage_1"], (0.3, 0, 0)), ("Ausgebrannt", "burnt", [], (0, 0, 0)), ("Wrack", "wreck", [], (0.2, 0, 0)), ("Schnee", "intact", ["snow_1"], (0, 0, 0))],
    "tree": [("Normal", "intact", [], (0, 0, 0)), ("Trocken", "dry", [], (0, 0, 0)), ("Abgestorben", "dead", [], (0, 0, 0)), ("Verbrannt", "burnt", [], (0, 0, 0)), ("Schnee", "intact", ["snow_1"], (0, 0, 0)), ("Abgestorben + Schnee", "dead", ["snow_1"], (0, 0, 0))],
    "crop": [("Normal", "intact", [], (0, 0, 0)), ("Trocken", "dry", [], (0, 0, 0)), ("Verdorrt", "dead", [], (0, 0, 0)), ("Verbrannt", "burnt", [], (0, 0, 0))],
    "fountain": [("Normal", "intact", [], (0, 0, 0)), ("Veralgt", "algae", [], (0.3, 0.05, 0)), ("Ausgetrocknet", "drained", [], (0.4, 0.15, 0)), ("Gefroren", "frozen", [], (0, 0, 0)),
                 ("Verwittert", "intact", ["wear_2"], (0.45, 0.2, 0.03)), ("Beschädigt", "intact", ["damage_1"], (0.3, 0.05, 0)), ("Vernachlässigt + bewachsen", "drained", ["wear_2", "overgrowth_1"], (0.55, 0.3, 0.04)), ("Schnee + gefroren", "frozen", ["snow_1"], (0, 0, 0))],
}
STATE_LISTS["prop_flammable"] = STATE_LISTS["prop"]
STATE_LISTS["lamp"] = [s for s in STATE_LISTS["prop"] if s[1] != "burnt" and "Bewachsen" not in s[0]]


def building_states():
    out = [(lbl, p["structure"], p["layers"], tuple(p["shader"]), p.get("fresh", False)) for _, lbl, p in T.PRESETS]
    out.append(("Kombi: verschmutzt + beschädigt + teilw. ausgebrannt", "intact", ["wear_2", "damage_1", "fire_2"], (0.55, 0.2, 0.04), False))
    out.append(("Kombi: heruntergekommen + Brandspuren", "intact", ["wear_3", "fire_1"], (0.7, 0.35, 0.06), False))
    out.append(("Restauriert, frisch (Spuren deutlich)", "intact", ["repair_2"], (0.1, 0, 0), False))
    out.append(("Schwer beschädigt + Schnee", "partial", ["damage_2", "snow_1"], (0.45, 0.1, 0.03), False))
    out.append(("Ruine + Schnee", "ruin", ["snow_1"], (0.4, 0.0, 0.0), False))
    return out


def render_states(spec, previews, seg, grime):
    a = previews["original"]
    cat = spec["category"]
    res = []
    if cat == "surface":
        res.append(("Normal", a))
        for k, v in previews.items():
            if k.startswith("layer:"):
                res.append((k[6:], T.compose(a, a, [v])))
        return res
    if cat == "interior":
        return [(k if k != "original" else "Normal", v) for k, v in previews.items()]
    prof = spec["profile"]
    states = building_states() if prof == "building" else [(*s, False) for s in STATE_LISTS[prof]]
    for lbl, base, layers, shader, fresh in states:
        b = a if base == "intact" else previews.get("base:" + base)
        if b is None:
            continue
        if fresh:
            b = LS.fresh(a, seg)
        ovs = [previews.get("layer:%s@%s" % (n, base)) or previews["layer:" + n] for n in T.LAYER_ORDER if n in layers and "layer:" + n in previews]
        img = T.compose(a, b, ovs)
        res.append((lbl, T.shader_preview(img, *shader, grime)))
    return res


def to_rgba8(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def scaled(a, f, pixel_art=False):
    im = to_rgba8(a)
    return im.resize((max(1, round(im.width * f)), max(1, round(im.height * f))), Image.NEAREST if pixel_art else Image.LANCZOS)


def flat(im):
    """Composite on the game green to measure what the player sees."""
    bg = Image.new("RGBA", im.size, BG + (255,))
    bg.alpha_composite(im)
    return np.asarray(bg.convert("RGB")).astype(np.float32) / 255.0


def checks_for(key, spec, previews, seg, states):
    a = previews["original"]
    H, W = a.shape[:2]
    op = a[..., 3] > 0.5
    ys, xs = np.nonzero(op)
    bottom = ys.max()
    r = {"asset": key, "files": {}, "states": {}, "issues": []}
    outline = op & (LS.lum(a[..., :3]) < 0.17)
    for name, v in previews.items():
        if name == "original":
            continue
        f = {}
        if name.startswith("base:") or spec["category"] == "interior":
            arr = v
            # same canvas (or symmetric growth) = same anchor in Godot
            f["canvas_ok"] = (arr.shape[0] - H) % 2 == 0 and (arr.shape[1] - W) % 2 == 0
            vop = arr[..., 3] > 0.5
            if vop.any():
                f["lowest_pixel_shift_px"] = int(np.nonzero(vop)[0].max() - bottom)  # info: rubble in front of the base
            border = np.concatenate([vop[0], vop[-1], vop[:, 0], vop[:, -1]]).sum()
            obord = np.concatenate([op[0], op[-1], op[:, 0], op[:, -1]]).sum() if arr.shape == a.shape else 0
            f["clipped_edge_px"] = int(max(0, border - obord))
            soft_new = (arr[..., 3] > 0.05) & (arr[..., 3] < 0.95) & ~((a[..., 3] > 0.05) if arr.shape == a.shape else np.zeros(arr.shape[:2], bool))
            # rotated parts (toppled objects) get the same anti-aliased edge as the original art
            transformed = name == "base:broken" or name == "base:wreck" or (spec.get("profile") == "tent" and name == "base:collapsed")
            f["soft_new_px"] = 0 if transformed else int(soft_new.sum())
            if arr.shape == a.shape:
                changed = np.abs(arr - a).max(-1) > 0.02
            else:
                changed = vop
        else:
            ov, (ox, oy) = v
            full = np.zeros_like(a)
            h, w = ov.shape[:2]
            full[oy:oy + h, ox:ox + w] = ov[:H - oy, :W - ox]
            changed = full[..., 3] > 0.02
            soft_new = (full[..., 3] > 0.05) & (full[..., 3] < 0.95) & (a[..., 3] < 0.05)
            f["soft_new_px"] = int(soft_new.sum())
            new_px = changed & (a[..., 3] < 0.05)
            f["clipped_edge_px"] = int(np.concatenate([new_px[0], new_px[-1], new_px[:, 0], new_px[:, -1]]).sum())
            f["coverage"] = round(float(changed.sum()) / max(1, op.sum()), 3)
            alt = outline & changed & (np.abs(full[..., :3] - a[..., :3]).max(-1) > 0.08)
            f["outline_changed_share"] = round(float(alt.sum()) / max(1, outline.sum()), 3)
        lab, n = ndimage.label(changed)
        if n:
            sizes = np.bincount(lab.ravel())[1:]
            tiny = sizes < max(9, (seg.px(3) if seg is not None else 3) ** 2)
            f["speckle_share"] = round(float(sizes[tiny].sum()) / max(1, float(sizes.sum())), 3)  # share of changed AREA in tiny specks
        r["files"][name] = f
        if not f.get("canvas_ok", True):
            r["issues"].append(f"{name}: Leinwand/Anker")
        if f.get("clipped_edge_px", 0) > 0:
            r["issues"].append(f"{name}: berührt den Bildrand ({f['clipped_edge_px']} px)")
        if f.get("soft_new_px", 0) > 0.002 * op.sum():
            r["issues"].append(f"{name}: weiche neue Randpixel ({f['soft_new_px']})")
        if f.get("speckle_share", 0) > 0.08 and spec["category"] != "interior":
            r["issues"].append(f"{name}: viele Einzelpixel (Rauschen) {f['speckle_share']}")
        if name in ("layer:wear_2", "layer:repair_1", "layer:repair_2") and f.get("outline_changed_share", 0) > 0.05:
            r["issues"].append(f"{name}: Konturen verändert ({f['outline_changed_share']})")
    # Readability at real game size (iPhone 15 Pro Max, default zoom): share of
    # the object's area whose colour visibly changes (max channel diff > 0.1).
    gs = 0.57
    pa = spec["category"] == "interior"

    def small(img):
        im = scaled(img, gs, pa)
        return flat(im), np.asarray(im)[..., 3] > 127

    o_small, o_op = small(a)
    smalls = []
    for lbl, img in states:
        s_, s_op = small(img)
        hh, ww = min(s_.shape[0], o_small.shape[0]), min(s_.shape[1], o_small.shape[1])
        union = (o_op[:hh, :ww] | s_op[:hh, :ww])
        vis = (np.abs(s_[:hh, :ww] - o_small[:hh, :ww]).max(-1) > 0.1) & union
        share = float(vis.sum()) / max(1, float(o_op.sum()))
        r["states"][lbl] = {"visible_change_share": round(share, 4)}
        smalls.append((lbl, s_, s_op))
    pairs = []
    for i in range(len(smalls)):
        for j in range(i + 1, len(smalls)):
            (l1, s1, p1), (l2, s2, p2) = smalls[i], smalls[j]
            hh, ww = min(s1.shape[0], s2.shape[0]), min(s1.shape[1], s2.shape[1])
            union = p1[:hh, :ww] | p2[:hh, :ww]
            vis = (np.abs(s1[:hh, :ww] - s2[:hh, :ww]).max(-1) > 0.1) & union
            pairs.append((round(float(vis.sum()) / max(1, float(union.sum())), 4), l1, l2))
    pairs.sort()
    r["closest_pairs_game_size"] = pairs[:5]
    subtle = {"Neu", "Gepflegt", "Normal benutzt", "Benutzt", "Normal", "Leicht verschmutzt", "Verschmutzt"}
    for lbl, v in r["states"].items():
        if lbl not in subtle and v["visible_change_share"] < 0.01:
            r["issues"].append(f"Zustand '{lbl}' in Spielgröße kaum sichtbar ({v['visible_change_share']:.3f})")
    for share, l1, l2 in pairs:
        if l1 not in subtle and l2 not in subtle and share < 0.01:
            r["issues"].append(f"'{l1}' und '{l2}' in Spielgröße kaum unterscheidbar ({share:.3f})")
    return r


def sheet(key, states, out_path, pixel_art=False):
    cell = 230
    n = len(states)
    cols = min(n, 8)
    W = cols * cell
    rows_full = (n + cols - 1) // cols
    blocks = []
    for title, f in GAME_SCALES:
        ims = [scaled(img, f, pixel_art) for _, img in states]
        # flow layout with wrapping
        lines, line, x = [], [], 6
        for im in ims:
            if line and x + im.width > W - 6:
                lines.append(line)
                line, x = [], 6
            line.append(im)
            x += im.width + 8
        if line:
            lines.append(line)
        blocks.append((title, lines))
    Hh = 30 + rows_full * (cell + 18) + sum(24 + sum(max(i.height for i in ln) + 8 for ln in lines) for _, lines in blocks) + 10
    sh = Image.new("RGB", (W, Hh), BG)
    d = ImageDraw.Draw(sh)
    d.text((6, 6), f"{key}  –  oben: volle Größe (verkleinert) · unten: echte Spielgröße in Gerätepixeln (Reihenfolge wie oben)", fill=(0, 0, 0), font=FONT)
    for i, (lbl, img) in enumerate(states):
        im = scaled(img, 1.0, pixel_art)
        im.thumbnail((cell - 10, cell - 28), Image.NEAREST if pixel_art else Image.LANCZOS)
        x, y = (i % cols) * cell, 30 + (i // cols) * (cell + 18)
        sh.paste(im, (x + 5, y + 22 + (cell - 28 - im.height)), im)
        d.text((x + 4, y + 4), lbl[:34], fill=(0, 0, 0), font=FONT)
    y = 30 + rows_full * (cell + 18)
    for title, lines in blocks:
        d.text((6, y + 4), title, fill=(0, 0, 0), font=FONT)
        y += 24
        for ln in lines:
            x = 6
            hmax = max(i.height for i in ln)
            for im in ln:
                sh.paste(im, (x, y + hmax - im.height), im)
                x += im.width + 8
            y += hmax + 8
    sh.save(out_path, optimize=True)


def run(all_previews, manifest, qa_dir, src):
    os.makedirs(qa_dir, exist_ok=True)
    grime = np.asarray(Image.open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "..", "assets", "vfx", "grime_field.png")).convert("L")).astype(np.float32) / 255.0
    report = {"assets": {}}
    for key, (spec, previews, seg) in all_previews.items():
        states = render_states(spec, previews, seg, grime)
        safe = key.replace("/", "_").replace(":", "_")
        sheet(key, states, os.path.join(qa_dir, f"sheet_{safe}.png"), pixel_art=spec["category"] == "interior")
        if seg is not None:
            Image.fromarray(seg.map_image()).save(os.path.join(qa_dir, f"materials_{safe}.png"), optimize=True)
        report["assets"][key] = checks_for(key, spec, previews, seg, states)
    issues = {k: v["issues"] for k, v in report["assets"].items() if v["issues"]}
    report["summary"] = {"assets": len(report["assets"]), "with_issues": len(issues), "issues": issues}
    with open(os.path.join(qa_dir, "qa_report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False, default=lambda o: o.item() if hasattr(o, "item") else str(o))
    print(f"QA: {len(report['assets'])} assets, {len(issues)} with findings -> {qa_dir}")
    for k, v in issues.items():
        print("  ", k, "|", "; ".join(v[:6]))
