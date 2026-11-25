#!/usr/bin/env python3
"""Door opening frames for the Penzilla building sprites (WORLDS, own tool).

Usage:
    python3 -I tools/assets/make_doors.py [<project_root>] [--sheet <out.png>]

Reads data/doors/doors.json (hand-measured door seeds and types) and the
game's building sprites (assets/penzilla/buildings/<key>.png), finds each door
leaf by flood fill from its seed (outline and frame excluded, windows inside
the leaf included), and writes per door a horizontal strip of N frames:
frame 0 = closed (transparent – the sprite already shows the closed door),
frame N-1 = fully open. Door types:
  single  – the leaf swings inward around its hinge: it narrows towards the
            hinge along the slope of the wall and darkens as it turns away;
            the dark interior appears behind it
  double  – two leaves, hinged at the outer edges
  sliding – two glass leaves slide apart behind the wall
  roller  – the gate rolls up from the bottom
Output (derived from Penzilla art → private, git-ignored):
  assets/penzilla/doors/<key>_<door>.png + assets/penzilla/doors/doors.json
Requires numpy, scipy, Pillow.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

OUTLINE = np.array([51, 0, 34])          # Penzilla contour colour (#330022)
INTERIOR = np.array([38, 26, 46])        # dark room behind an open door
INTERIOR_FLOOR = np.array([74, 52, 60])  # a little light on the floor


def door_mask(rgba, seed, tol=46, clip=None):
    rgb = rgba[..., :3].astype(int)
    a = rgba[..., 3]
    sx, sy = seed
    ref = rgb[sy, sx]
    close = (np.abs(rgb - ref).sum(axis=2) < tol * 3) & (a > 200)
    # dark contour pixels always separate regions (antialiased outlines leak)
    close &= rgb.sum(axis=2) > 150
    if clip:
        box = np.zeros_like(close)
        box[clip[1]:clip[3], clip[0]:clip[2]] = True
        close &= box
    lab, _ = ndimage.label(close)
    region = lab == lab[sy, sx]
    filled = ndimage.binary_fill_holes(region)
    return filled


def wall_slope(mask):
    ys, xs = np.nonzero(mask)
    cols = {}
    for x, y in zip(xs, ys):
        cols[x] = max(cols.get(x, -1), y)
    xs2 = np.array(sorted(cols))
    if len(xs2) < 4:
        return 0.0
    ys2 = np.array([cols[x] for x in xs2])
    k = max(1, len(xs2) // 6)   # ignore the rounded corners
    return float(np.polyfit(xs2[k:-k], ys2[k:-k], 1)[0]) if len(xs2) > 2 * k + 2 else float(np.polyfit(xs2, ys2, 1)[0])


def outline(alpha, width=2):
    grown = ndimage.binary_dilation(alpha, iterations=width)
    return grown & ~alpha


def render_frame(src, mask, slope, kind, hinge, f):
    """src: RGBA crop of the sprite, mask: door area (bool), f: 0..1 open."""
    h, w = mask.shape
    out = np.zeros((h, w, 4), np.uint8)
    if f <= 0.0:
        return out
    ys, xs = np.nonzero(mask)
    y_top, y_bot = ys.min(), ys.max()
    # interior behind the door: dark, a little lighter towards the floor
    t = np.clip((np.arange(h)[:, None] - y_top) / max(1, y_bot - y_top), 0, 1) * np.ones((1, w))
    room = INTERIOR[None, None, :] * (1 - t[..., None] * 0.6) + INTERIOR_FLOOR[None, None, :] * (t[..., None] * 0.6)
    out[mask, :3] = room[mask].astype(np.uint8)
    out[mask, 3] = 255
    x0, x1 = xs.min(), xs.max()
    leaf = np.zeros((h, w), bool)
    leaf_rgb = np.zeros((h, w, 3), float)

    def swing(xa, xb, hinge_x, open_f, sub):
        # columns of the leaf part [xa, xb] narrow towards hinge_x
        width_f = max(0.16, float(np.cos(open_f * np.radians(78))))
        shade = 1.0 - 0.35 * open_f
        for xt in range(min(xa, xb), max(xa, xb) + 1):
            xs_ = hinge_x + (xt - hinge_x) / width_f
            xi = int(round(xs_))
            if xi < min(xa, xb) or xi > max(xa, xb):
                continue
            dy = slope * (xt - xi)          # keep the leaf on the wall line
            for yt in range(h):
                ysrc = int(round(yt - dy))
                if 0 <= ysrc < h and sub[ysrc, xi]:
                    leaf[yt, xt] = True
                    leaf_rgb[yt, xt] = src[ysrc, xi, :3] * shade

    if kind == "single":
        hx = x0 if hinge == "left" else x1
        swing(x0, x1, hx, f, mask)
    elif kind == "double":
        mid = (x0 + x1) // 2
        left = mask.copy(); left[:, mid + 1:] = False
        right = mask.copy(); right[:, :mid + 1] = False
        swing(x0, mid, x0, f, left)
        swing(mid + 1, x1, x1, f, right)
    elif kind == "sliding":
        mid = (x0 + x1) // 2
        shift = int(round(f * (mid - x0) * 0.92))
        for part, direction in ((np.s_[:, :mid + 1], -1), (np.s_[:, mid + 1:], 1)):
            sub = np.zeros_like(mask); sub[part] = mask[part]
            sy, sx = np.nonzero(sub)
            for y, x in zip(sy, sx):
                xt = x + direction * shift
                yt = int(round(y + slope * direction * shift))
                if 0 <= xt < w and 0 <= yt < h and mask[yt, xt]:
                    leaf[yt, xt] = True
                    leaf_rgb[yt, xt] = src[y, x, :3] * 0.92
    elif kind == "roller":
        rise = f * (y_bot - y_top) * 0.95
        sy, sx = np.nonzero(mask)
        for y, x in zip(sy, sx):
            yt = int(round(y - rise))
            if mask[min(h - 1, max(0, yt)), x] and yt >= 0:
                # only the part that is still in the opening stays visible
                leaf[yt, x] = True
                leaf_rgb[yt, x] = src[y, x, :3]
        # the rolled-up gate disappears into its housing at the top
    edge = outline(leaf, 1) & (mask | ndimage.binary_dilation(mask, iterations=1))
    out[leaf, :3] = np.clip(leaf_rgb[leaf], 0, 255).astype(np.uint8)
    out[leaf, 3] = 255
    out[edge, :3] = OUTLINE
    out[edge, 3] = 255
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = os.path.abspath(args[0]) if args else os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    sheet_out = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
    spec = json.load(open(os.path.join(root, "data", "doors", "doors.json"), encoding="utf-8"))
    n = int(spec.get("frames", 6))
    src_dir = os.path.join(root, "assets", "penzilla", "buildings")
    out_dir = os.path.join(root, "assets", "penzilla", "doors")
    os.makedirs(out_dir, exist_ok=True)
    meta = {"frames": n, "doors": {}}
    previews = []
    for key, doors in spec["buildings"].items():
        path = os.path.join(src_dir, key + ".png")
        if not os.path.exists(path):
            continue
        rgba = np.array(Image.open(path).convert("RGBA"))
        for d in doors:
            if d.get("type") == "none":
                meta["doors"].setdefault(key, []).append({"id": d["id"], "type": "none"})
                continue
            m = door_mask(rgba, d["seed"], int(d.get("tol", 46)), d.get("clip"))
            ys, xs = np.nonzero(m)
            pad = 3
            bx0, by0 = max(0, xs.min() - pad), max(0, ys.min() - pad)
            bx1, by1 = min(rgba.shape[1], xs.max() + pad + 1), min(rgba.shape[0], ys.max() + pad + 1)
            sub_mask = m[by0:by1, bx0:bx1]
            sub_src = rgba[by0:by1, bx0:bx1].astype(float)
            slope = float(d["slope"]) if "slope" in d else wall_slope(sub_mask)
            frames = [render_frame(sub_src, sub_mask, slope, d["type"], d.get("hinge", "left"), i / (n - 1)) for i in range(n)]
            strip = np.concatenate(frames, axis=1)
            name = f"{key}_{d['id']}.png"
            dest = os.path.abspath(os.path.join(out_dir, name))
            if not dest.startswith(out_dir + os.sep):
                raise SystemExit("unsafe path")
            Image.fromarray(strip).save(dest, optimize=True)
            meta["doors"].setdefault(key, []).append({"id": d["id"], "type": d["type"], "file": name,
                "rect": [int(bx0), int(by0), int(bx1 - bx0), int(by1 - by0)], "slope": round(slope, 3),
                "area_px": int(m.sum()), "sprite_size": [int(rgba.shape[1]), int(rgba.shape[0])]})
            if sheet_out:
                prev = []
                for fr in frames:
                    base = Image.fromarray(rgba[by0:by1, bx0:bx1].astype(np.uint8))
                    base.alpha_composite(Image.fromarray(fr))
                    prev.append(base)
                previews.append((f"{key}/{d['id']} {d['type']} slope {slope:.2f} area {int(m.sum())}", prev))
            print(f"{key}/{d['id']}: {d['type']}, {m.sum()} px, rect {bx1 - bx0}x{by1 - by0}, slope {slope:.2f}")
    with open(os.path.join(out_dir, "doors.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1)
    if sheet_out and previews:
        S = 3
        rows = []
        for label, prev in previews:
            w = sum(p.size[0] * S + 8 for p in prev)
            hh = max(p.size[1] for p in prev) * S + 16
            row = Image.new("RGBA", (max(w, 300), hh), (230, 230, 230, 255))
            x = 0
            for p in prev:
                row.alpha_composite(p.resize((p.size[0] * S, p.size[1] * S), Image.NEAREST), (x, 14))
                x += p.size[0] * S + 8
            from PIL import ImageDraw
            ImageDraw.Draw(row).text((2, 1), label, fill=(0, 0, 0, 255))
            rows.append(row)
        W = max(r.size[0] for r in rows)
        sheet = Image.new("RGBA", (W, sum(r.size[1] for r in rows)), (255, 255, 255, 255))
        y = 0
        for r in rows:
            sheet.alpha_composite(r, (0, y)); y += r.size[1]
        sheet.save(sheet_out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
