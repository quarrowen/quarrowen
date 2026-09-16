#!/usr/bin/env python3
"""Draws the Quarrowen app icon: a grass-topped voxel block over a night-sky gradient.

    python3 tools/generate_icon.py            # writes assets/icon.png (1024) and icon.svg-free .icns on macOS

A quarry cut into rock with a small lit home in it: the name, and what the game is about (digging a
world and settling it). Deliberately not a grass-topped cube, which is Minecraft's mark, not ours.

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
STONE_TOP = (138, 146, 160)
STONE_TOP_LIT = (158, 167, 182)
STONE_LEFT = (92, 99, 112)
STONE_RIGHT = (68, 74, 86)
WINDOW = (255, 206, 120)


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


def terrace(draw: ImageDraw.ImageDraw, cx: float, cy: float, w: float, h: float, top, left, right) -> None:
    """One stepped block of the quarry: an isometric slab with a lit top and two shaded sides."""
    half = h * 0.55
    top_face = [(cx, cy - half * 2), (cx + w, cy - half), (cx, cy), (cx - w, cy - half)]
    draw.polygon([(cx - w, cy - half), (cx, cy), (cx, cy + h), (cx - w, cy - half + h)], fill=left)
    draw.polygon([(cx + w, cy - half), (cx, cy), (cx, cy + h), (cx + w, cy - half + h)], fill=right)
    draw.polygon(top_face, fill=top)


def cube(img: Image.Image) -> None:
    """The quarry: three stepped terraces cut into stone, with a lit window in the lowest step."""
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse([SIZE * 0.22, SIZE * 0.70, SIZE * 0.78, SIZE * 0.86], fill=(8, 10, 20, 120))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(SIZE * 0.05)))

    draw = ImageDraw.Draw(img)
    steps = [
        (0.50, 0.70, 0.30, 0.10, STONE_TOP, STONE_LEFT, STONE_RIGHT),
        (0.50, 0.55, 0.22, 0.09, STONE_TOP_LIT, STONE_LEFT, STONE_RIGHT),
        (0.50, 0.41, 0.14, 0.08, STONE_TOP_LIT, STONE_LEFT, STONE_RIGHT),
    ]
    for fx, fy, fw, fh, top, left, right in steps:
        terrace(draw, SIZE * fx, SIZE * fy, SIZE * fw, SIZE * fh, top, left, right)

    # The home: a small lit window cut into the front of the middle step.
    wx, wy = SIZE * 0.50, SIZE * 0.605
    ww, wh = SIZE * 0.045, SIZE * 0.055
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([wx - ww * 3, wy - wh * 3, wx + ww * 3, wy + wh * 3], fill=(255, 196, 92, 90))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(SIZE * 0.02)))
    draw.polygon([(wx - ww, wy - wh * 0.4), (wx, wy - wh), (wx + ww, wy - wh * 0.4), (wx + ww, wy + wh * 0.6),
                  (wx, wy + wh), (wx - ww, wy + wh * 0.6)], fill=WINDOW)

    # A few loose blocks quarried out, resting beside the cut.
    for fx, fy, fw in [(0.22, 0.60, 0.045), (0.80, 0.52, 0.036), (0.74, 0.70, 0.030)]:
        terrace(draw, SIZE * fx, SIZE * fy, SIZE * fw, SIZE * fw * 0.8, STONE_TOP, STONE_LEFT, STONE_RIGHT)


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
