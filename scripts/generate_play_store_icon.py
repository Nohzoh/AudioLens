"""Regenerates distribution/play-store/icon-512.png (T110).

The original mipmap launcher icon (android/app/src/main/res/mipmap-*/
ic_launcher.png) has transparent corners around a white body — fine for
Android's adaptive-icon masking, but Play Console requires a flat, opaque
icon and flattens transparency to white, producing a stark white square
against the store's dark theme. This draws the same headphone+waveform
glyph procedurally at native 512x512 resolution (crisper than upscaling
the 192px mipmap source) on the app's brand purple background instead
(matches AudioGuideApp's ColorScheme.fromSeed(0xFF6B4EFF) in
lib/main.dart, and the docs/ landing page).

Usage: python3 scripts/generate_play_store_icon.py
Requires: pip install pillow

Output still needs to be uploaded manually to Play Console — see
AGENTS.md's "Play Store Listing Icon" section.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

CANVAS = 512
BRAND_PURPLE = (107, 78, 255)
DARK = (26, 26, 46)
BLUE = (74, 144, 217)

OUTPUT = Path(__file__).resolve().parent.parent / "distribution" / "play-store" / "icon-512.png"


def main() -> None:
    img = Image.new("RGB", (CANVAS, CANVAS), BRAND_PURPLE)
    draw = ImageDraw.Draw(img)

    cx, cy = CANVAS // 2, CANVAS // 2 + 10

    # Headphone band: a thick arc (top half of a ring), with round caps
    # (PIL's arc() has flat caps by default, so cap circles are added).
    band_r = 130
    band_w = 34
    bbox = [cx - band_r, cy - band_r - 20, cx + band_r, cy + band_r - 20]
    draw.arc(bbox, start=200, end=340, fill=DARK, width=band_w)
    for ang in (200, 340):
        rad = math.radians(ang)
        px = cx + band_r * math.cos(rad)
        py = (cy - 20) + band_r * math.sin(rad)
        draw.ellipse(
            [px - band_w / 2, py - band_w / 2, px + band_w / 2, py + band_w / 2],
            fill=DARK,
        )

    # Ear cups: two rounded rectangles.
    cup_w, cup_h = 62, 108
    cup_y = cy + 30
    left_cup = [
        cx - band_r - cup_w / 2 + 8, cup_y - cup_h / 2,
        cx - band_r + cup_w / 2 + 8, cup_y + cup_h / 2,
    ]
    right_cup = [
        cx + band_r - cup_w / 2 - 8, cup_y - cup_h / 2,
        cx + band_r + cup_w / 2 - 8, cup_y + cup_h / 2,
    ]
    draw.rounded_rectangle(left_cup, radius=28, fill=DARK)
    draw.rounded_rectangle(right_cup, radius=28, fill=DARK)

    # Waveform bars: 5 vertical rounded bars, short-tall-tallest-tall-short.
    heights = [46, 84, 130, 84, 46]
    bar_w = 22
    gap = 14
    total_w = bar_w * 5 + gap * 4
    start_x = cx - total_w / 2
    for i, h in enumerate(heights):
        x0 = start_x + i * (bar_w + gap)
        x1 = x0 + bar_w
        y0 = cy + 30 - h / 2
        y1 = cy + 30 + h / 2
        draw.rounded_rectangle([x0, y0, x1, y1], radius=bar_w / 2, fill=BLUE)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUTPUT)
    print(f"saved {OUTPUT} ({img.size[0]}x{img.size[1]}, {img.mode})")


if __name__ == "__main__":
    main()
