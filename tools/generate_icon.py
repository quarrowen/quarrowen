#!/usr/bin/env python3
"""Draws the VoxelCraft app icon: a grass-topped voxel block over a night-sky gradient.

    python3 tools/generate_icon.py            # writes assets/icon.png (1024) and icon.svg-free .icns on macOS

The icon is generated rather than drawn by hand so it can be tweaked (colours, angle) in one place and
re-rendered for every size macOS asks for.
"""
from __future__ import annotations

import math
import pathlib
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets"

SKY_TOP = (26, 34, 56)
SKY_BOTTOM = (58, 44, 86)
GRASS_TOP = (126, 200, 96)
GRASS_TOP_LIGHT = (150, 220, 120)
DIRT_LEFT = (132, 94, 62)
DIRT_RIGHT = (104, 72, 46)
GRASS_EDGE_LEFT = (104, 168, 78)
GRASS_EDGE_RIGHT = (86, 142, 66)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def background() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        draw.line([(0, y), (SIZE, y)], fill=lerp(SKY_TOP, SKY_BOTTOM, y / SIZE) + (255,))
    # A soft glow behind the block, so the cube reads even on a dark desktop.
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([SIZE * 0.16, SIZE * 0.2, SIZE * 0.84, SIZE * 0.88], fill=(120, 190, 255, 70))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(SIZE * 0.09)))
    # Stars, brighter near the top.
    rng = 1
    for i in range(90):
        rng = (rng * 1103515245 + 12345) % (1 << 31)
        x = (rng >> 5) % SIZE
        rng = (rng * 1103515245 + 12345) % (1 << 31)
        y = (rng >> 5) % int(SIZE * 0.55)
        rng = (rng * 1103515245 + 12345) % (1 << 31)
        r = 1.5 + (rng % 100) / 100.0 * 2.5
        alpha = int(90 + (1.0 - y / (SIZE * 0.55)) * 120)
        ImageDraw.Draw(img).ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, alpha))
    return img


def voxel(draw: ImageDraw.ImageDraw, cx: float, cy: float, w: float, alpha: int = 255) -> None:
    """A small floating voxel, drawn flat so it reads as part of the same world."""
    h = w * 0.55
    side = w * 0.85
    top = [(cx, cy - h * 2), (cx + w, cy - h), (cx, cy), (cx - w, cy - h)]
    lip = side * 0.3
    draw.polygon([(cx - w, cy - h), (cx, cy), (cx, cy + side), (cx - w, cy - h + side)], fill=DIRT_LEFT + (alpha,))
    draw.polygon([(cx + w, cy - h), (cx, cy), (cx, cy + side), (cx + w, cy - h + side)], fill=DIRT_RIGHT + (alpha,))
    draw.polygon([(cx - w, cy - h), (cx, cy), (cx, cy + lip), (cx - w, cy - h + lip)], fill=GRASS_EDGE_LEFT + (alpha,))
    draw.polygon([(cx + w, cy - h), (cx, cy), (cx, cy + lip), (cx + w, cy - h + lip)], fill=GRASS_EDGE_RIGHT + (alpha,))
    draw.polygon(top, fill=GRASS_TOP + (alpha,))


def cube(img: Image.Image) -> None:
    """One isometric voxel: a grass top and two dirt sides, with a shadow and a few smaller ones around it."""
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([SIZE * 0.28, SIZE * 0.72, SIZE * 0.72, SIZE * 0.82], fill=(8, 10, 20, 105))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(SIZE * 0.045)))

    draw = ImageDraw.Draw(img)
    for fx, fy, fw, fa in [(0.20, 0.40, 0.050, 235), (0.82, 0.34, 0.038, 210), (0.75, 0.68, 0.030, 190)]:
        voxel(draw, SIZE * fx, SIZE * fy, SIZE * fw, fa)

    cx, cy = SIZE * 0.5, SIZE * 0.50
    w = SIZE * 0.26          # half width of the top rhombus
    h = w * 0.55             # half height of the top rhombus
    side = SIZE * 0.23       # how far the sides drop

    top = [(cx, cy - h * 2), (cx + w, cy - h), (cx, cy), (cx - w, cy - h)]
    left = [(cx - w, cy - h), (cx, cy), (cx, cy + side), (cx - w, cy - h + side)]
    right = [(cx + w, cy - h), (cx, cy), (cx, cy + side), (cx + w, cy - h + side)]

    draw.polygon(left, fill=DIRT_LEFT)
    draw.polygon(right, fill=DIRT_RIGHT)
    draw.polygon(top, fill=GRASS_TOP)

    # The grass lip on both side faces.
    lip = side * 0.17
    draw.polygon([(cx - w, cy - h), (cx, cy), (cx, cy + lip), (cx - w, cy - h + lip)], fill=GRASS_EDGE_LEFT)
    draw.polygon([(cx + w, cy - h), (cx, cy), (cx, cy + lip), (cx + w, cy - h + lip)], fill=GRASS_EDGE_RIGHT)

    # Voxel texture: a few lighter patches on the top face, kept inside the rhombus.
    rng = 7
    for i in range(26):
        rng = (rng * 1103515245 + 12345) % (1 << 31)
        u = ((rng >> 7) % 1000) / 1000.0
        rng = (rng * 1103515245 + 12345) % (1 << 31)
        v = ((rng >> 7) % 1000) / 1000.0
        if u + v > 1.0:
            u, v = 1.0 - u, 1.0 - v
        px = cx + (u - v) * w
        py = cy - h * 2 + (u + v) * h
        r = SIZE * 0.012
        draw.ellipse([px - r, py - r, px + r, py + r], fill=GRASS_TOP_LIGHT)

    # Bright edges where the faces meet, for definition.
    for a, b, color in [
        (top[0], top[1], (170, 235, 140)),
        (top[3], top[0], (170, 235, 140)),
        ((cx, cy), (cx, cy + side), (70, 50, 34)),
    ]:
        draw.line([a, b], fill=color, width=max(3, SIZE // 200))


def rounded_mask() -> Image.Image:
    mask = Image.new("L", (SIZE, SIZE), 0)
    # macOS icons sit on a squircle with a margin; keep the art inside it.
    ImageDraw.Draw(mask).rounded_rectangle([SIZE * 0.06, SIZE * 0.06, SIZE * 0.94, SIZE * 0.94],
                                           radius=SIZE * 0.22, fill=255)
    return mask


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    img = background()
    cube(img)
    img.putalpha(rounded_mask())
    png = OUT / "icon.png"
    img.save(png)
    print(f"wrote {png}")

    if sys.platform == "darwin":
        iconset = OUT / "icon.iconset"
        iconset.mkdir(exist_ok=True)
        for size in (16, 32, 64, 128, 256, 512, 1024):
            img.resize((size, size), Image.LANCZOS).save(iconset / f"icon_{size}x{size}.png")
            if size <= 512:
                img.resize((size * 2, size * 2), Image.LANCZOS).save(iconset / f"icon_{size}x{size}@2x.png")
        icns = OUT / "icon.icns"
        if subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)]).returncode == 0:
            print(f"wrote {icns}")
        for leftover in iconset.glob("*.png"):
            leftover.unlink()
        iconset.rmdir()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
