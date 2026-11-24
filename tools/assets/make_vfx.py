#!/usr/bin/env python3
"""Living Assets – own VFX sprites in the Penzilla style (step 8).

Usage: python3 -I tools/assets/make_vfx.py [<project_root>]
Writes assets/vfx/vfx_atlas.png + vfx_atlas.json and assets/vfx/grime_field.png.

Everything here is drawn procedurally by this script (own work, no external
source), so the files may live in the public repository. Style: flat cartoon
shapes with the Penzilla outline colour (#330022), the same saturated palette,
no soft photographic particles (docs/living_assets/VFX_SOURCES.md).
Requires numpy + pillow.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = (51, 0, 34, 255)
HERE = os.path.dirname(os.path.abspath(__file__))
FRAME = 96


def _outlined(draw_fn, size=FRAME, outline=5):
    """Draws a shape set via draw_fn(draw) on a mask, then fills colours and
    puts the Penzilla outline around the union."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    draw_fn(ImageDraw.Draw(layer), ImageDraw.Draw(mask))
    if outline > 0:
        grown = mask.filter(ImageFilter.MaxFilter(outline * 2 + 1))
        base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        base.paste(Image.new("RGBA", (size, size), OUT), (0, 0), grown)
        base.alpha_composite(layer)
        return base
    return layer


def _teardrop(cx, base_y, w, h, sway, rng, n=18):
    pts = []
    for i in range(n + 1):
        t = i / n
        ang = math.pi * t
        r = math.sin(ang)
        y = base_y - h * (1 - math.cos(ang * 0.5)) * 1.0
        x = cx + (r * w * (1 - t * 0.85)) * (1 if i <= n else -1)
        pts.append((x, base_y - h * t))
    left = [(cx - (math.sin(math.pi * (i / n) ** 0.8)) * w * (1 - (i / n) * 0.9) + sway * (i / n) ** 2, base_y - h * (i / n)) for i in range(n + 1)]
    right = [(cx + (math.sin(math.pi * (i / n) ** 0.8)) * w * (1 - (i / n) * 0.9) + sway * (i / n) ** 2, base_y - h * (i / n)) for i in range(n + 1)]
    return left + right[::-1]


def flame_frames(count=8, seed=1):
    rng = np.random.default_rng(seed)
    frames = []
    for f in range(count):
        ph = 2 * math.pi * f / count

        def draw(d, m):
            for k, (col, sc) in enumerate([((255, 122, 40, 255), 1.0), ((255, 196, 58, 255), 0.66), ((255, 244, 190, 255), 0.33)]):
                for j, off in enumerate((-14, 0, 14)):
                    h = (62 + 10 * math.sin(ph + j * 1.7)) * sc * (0.75 if off else 1.0)
                    w = (17 if off == 0 else 12) * sc
                    sway = 9 * math.sin(ph * (1 + j * 0.3) + j)
                    poly = _teardrop(48 + off * sc, 88, w, h, sway, rng)
                    d.polygon(poly, fill=col)
                    if k == 0:
                        m.polygon(poly, fill=255)
        frames.append(_outlined(draw, outline=4))
    return frames


def smoke_frames(count=6, seed=2, dark=True):
    rng = np.random.default_rng(seed)
    blobs = [(rng.uniform(-14, 14), rng.uniform(-10, 10), rng.uniform(12, 20)) for _ in range(6)]
    frames = []
    for f in range(count):
        t = f / (count - 1)
        grow = 0.55 + 0.6 * t
        rise = 30 * t
        col = (72, 62, 74) if dark else (214, 210, 218)
        hi = (98, 86, 100) if dark else (240, 238, 244)

        def draw(d, m):
            for bx, by, r in blobs:
                rr = r * grow
                cx, cy = 48 + bx * grow, 58 + by * grow - rise
                d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=col + (255,))
                m.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=255)
                d.ellipse([cx - rr * 0.6, cy - rr * 0.75, cx + rr * 0.1, cy - rr * 0.1], fill=hi + (255,))
        img = _outlined(draw, outline=3)
        a = np.asarray(img).astype(np.float32)
        a[..., 3] *= (1.0 - t * 0.85)
        frames.append(Image.fromarray(a.astype(np.uint8), "RGBA"))
    return frames


def simple(draw_fn, outline=3):
    return _outlined(draw_fn, outline=outline)


def star(cx, cy, r1, r2, n=5, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = rot + math.pi * i / n
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def build():
    sprites = {}
    sprites["flame"] = flame_frames()
    sprites["smoke_dark"] = smoke_frames(dark=True)
    sprites["smoke_light"] = smoke_frames(seed=5, dark=False)
    sprites["spark"] = [simple(lambda d, m, s=s: (d.polygon(star(48, 48, 14 * s, 5 * s, 4), fill=(255, 220, 90, 255)), m.polygon(star(48, 48, 14 * s, 5 * s, 4), fill=255)), outline=2) for s in (0.6, 1.0, 0.7)]
    sprites["raindrop"] = [simple(lambda d, m: (d.rounded_rectangle([45, 20, 51, 60], 3, fill=(150, 200, 245, 255)), m.rounded_rectangle([45, 20, 51, 60], 3, fill=255)), outline=2)]
    sprites["snowflake"] = [simple(lambda d, m: (d.ellipse([40, 40, 56, 56], fill=(250, 252, 255, 255)), m.ellipse([40, 40, 56, 56], fill=255)), outline=2)]
    sprites["dust"] = [simple(lambda d, m, s=s: [(d.ellipse([48 - r + ox, 60 - r * 0.7 + oy, 48 + r + ox, 60 + r * 0.7 + oy], fill=(214, 190, 150, 255)), m.ellipse([48 - r + ox, 60 - r * 0.7 + oy, 48 + r + ox, 60 + r * 0.7 + oy], fill=255)) for (ox, oy, r) in [(-10 * s, 0, 10 * s), (8 * s, -4 * s, 13 * s), (0, -12 * s, 9 * s)]], outline=3) for s in (0.7, 1.0, 1.3)]
    leaf = [(48, 30), (62, 46), (48, 70), (34, 46)]
    sprites["leaf"] = [simple(lambda d, m: (d.polygon(leaf, fill=(140, 180, 70, 255)), m.polygon(leaf, fill=255), d.line([(48, 34), (48, 66)], fill=(96, 130, 50, 255), width=3)), outline=3)]
    sprites["splash"] = [simple(lambda d, m, s=s: (d.ellipse([48 - 26 * s, 60 - 9 * s, 48 + 26 * s, 60 + 9 * s], outline=(150, 200, 245, 255), width=5), m.ellipse([48 - 26 * s, 60 - 9 * s, 48 + 26 * s, 60 + 9 * s], outline=255, width=5)), outline=2) for s in (0.4, 0.75, 1.1)]
    sprites["repair"] = [simple(lambda d, m, s=s: (d.polygon(star(48, 48, 22 * s, 8 * s, 4, 0.4), fill=(120, 230, 160, 255)), m.polygon(star(48, 48, 22 * s, 8 * s, 4, 0.4), fill=255)), outline=3) for s in (0.5, 1.0, 0.7)]
    sprites["reward_star"] = [simple(lambda d, m, s=s: (d.polygon(star(48, 50, 30 * s, 13 * s), fill=(255, 205, 60, 255)), m.polygon(star(48, 50, 30 * s, 13 * s), fill=255), d.polygon(star(44, 44, 10 * s, 4 * s), fill=(255, 245, 190, 255))), outline=4) for s in (0.6, 1.0, 0.85)]
    sprites["debris"] = [simple(lambda d, m, s=s: (d.polygon([(40, 44), (56, 40), (60, 56), (44, 60)], fill=(150, 130, 140, 255)), m.polygon([(40, 44), (56, 40), (60, 56), (44, 60)], fill=255)), outline=3) for s in (1,)]
    return sprites


def grime_field(size=256, seed=7):
    """Tileable smooth field (0..1) used by shaders/living_wear.gdshader to
    grow flat, hard-edged dirt patches with a threshold (no per-asset data)."""
    rng = np.random.default_rng(seed)
    k = np.fft.fftfreq(size)
    kx, ky = np.meshgrid(k, k)
    spec = (rng.normal(size=(size, size)) + 1j * rng.normal(size=(size, size))) * np.exp(-(kx ** 2 + ky ** 2) / (2 * 0.018 ** 2))
    f = np.real(np.fft.ifft2(spec))
    f = (f - f.min()) / (f.max() - f.min())
    g = np.real(np.fft.ifft2((rng.normal(size=(size, size)) + 1j * rng.normal(size=(size, size))) * np.exp(-(kx ** 2 + ky ** 2) / (2 * 0.05 ** 2))))
    g = (g - g.min()) / (g.max() - g.min())
    img = np.stack([f, g, (f * 0.5 + g * 0.5)], -1)
    return Image.fromarray((img * 255).astype(np.uint8), "RGB")


def main():
    root = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(HERE))
    out_dir = os.path.join(root, "assets", "vfx")
    os.makedirs(out_dir, exist_ok=True)
    sprites = build()
    cols = 8
    total = sum(len(v) for v in sprites.values())
    rows = math.ceil(total / cols)
    atlas = Image.new("RGBA", (cols * FRAME, rows * FRAME), (0, 0, 0, 0))
    meta = {"frame_size": FRAME, "source": "own procedural work (tools/assets/make_vfx.py)", "license": "project-owned (may be redistributed)", "animations": {}}
    i = 0
    for name, frames in sprites.items():
        rects = []
        for fr in frames:
            x, y = (i % cols) * FRAME, (i // cols) * FRAME
            atlas.alpha_composite(fr, (x, y))
            rects.append([x, y, FRAME, FRAME])
            i += 1
        meta["animations"][name] = {"frames": rects, "fps": 12 if name in ("flame",) else 8}
    atlas.save(os.path.join(out_dir, "vfx_atlas.png"), optimize=True)
    with open(os.path.join(out_dir, "vfx_atlas.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1)
    grime_field().save(os.path.join(out_dir, "grime_field.png"), optimize=True)
    print(f"{total} frames → {out_dir}/vfx_atlas.png ({atlas.width}×{atlas.height})")


if __name__ == "__main__":
    main()
