"""Regenerates the quick-capture home-screen widget's icon.

#150: the widget previously drew a camera glyph, unrelated to the app's
actual headphone+waveform launcher icon (mipmap ic_launcher.png) — the
two just didn't read as the same app. This draws the same headphone+
waveform glyph (same colors as generate_play_store_icon.py) on a WHITE
background — ic_launcher.png itself has no baked-in background (fully
transparent corners), and what the launcher actually shows is a plain
white circle behind the glyph, so white is what the app icon really
looks like day to day, not the brand purple. A small "+" badge (brand
purple, a bit of shine on it) in the bottom-right corner signals "start
a new capture" at a glance.

Usage: python3 scripts/generate_widget_icon.py
Requires: pip install pillow
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

CANVAS = 192
BRAND_PURPLE = (107, 78, 255, 255)
DARK = (26, 26, 46, 255)
BLUE = (74, 144, 217, 255)
WHITE = (255, 255, 255, 255)
SHINE = (255, 255, 255, 110)

OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "android" / "app" / "src" / "main" / "res" / "drawable-nodpi" / "widget_quick_capture.png"
)


def _draw_headphone_glyph(draw: ImageDraw.ImageDraw, cx: float, cy: float) -> None:
    # Proportions scaled down from generate_play_store_icon.py's 512px
    # version (same glyph, same colors — that's the point).
    band_r = 49
    band_w = 13
    bbox = [cx - band_r, cy - band_r - 8, cx + band_r, cy + band_r - 8]
    draw.arc(bbox, start=200, end=340, fill=DARK, width=band_w)
    for ang in (200, 340):
        rad = math.radians(ang)
        px = cx + band_r * math.cos(rad)
        py = (cy - 8) + band_r * math.sin(rad)
        draw.ellipse(
            [px - band_w / 2, py - band_w / 2, px + band_w / 2, py + band_w / 2],
            fill=DARK,
        )

    cup_w, cup_h = 23, 41
    cup_y = cy + 11
    left_cup = [
        cx - band_r - cup_w / 2 + 3, cup_y - cup_h / 2,
        cx - band_r + cup_w / 2 + 3, cup_y + cup_h / 2,
    ]
    right_cup = [
        cx + band_r - cup_w / 2 - 3, cup_y - cup_h / 2,
        cx + band_r + cup_w / 2 - 3, cup_y + cup_h / 2,
    ]
    draw.rounded_rectangle(left_cup, radius=10, fill=DARK)
    draw.rounded_rectangle(right_cup, radius=10, fill=DARK)

    heights = [17, 32, 49, 32, 17]
    bar_w = 8
    gap = 5
    total_w = bar_w * 5 + gap * 4
    start_x = cx - total_w / 2
    for i, h in enumerate(heights):
        x0 = start_x + i * (bar_w + gap)
        x1 = x0 + bar_w
        y0 = cy + 11 - h / 2
        y1 = cy + 11 + h / 2
        draw.rounded_rectangle([x0, y0, x1, y1], radius=bar_w / 2, fill=BLUE)


def _draw_capture_badge(img: Image.Image, badge_cx: float, badge_cy: float, r: float) -> None:
    draw = ImageDraw.Draw(img)
    # A thin white ring separates the badge from the white background
    # behind it, so its edge doesn't disappear against it.
    draw.ellipse(
        [badge_cx - r - 4, badge_cy - r - 4, badge_cx + r + 4, badge_cy + r + 4],
        fill=WHITE,
    )
    draw.ellipse(
        [badge_cx - r, badge_cy - r, badge_cx + r, badge_cy + r], fill=BRAND_PURPLE
    )
    plus_w, plus_len = 8, 32
    draw.rounded_rectangle(
        [badge_cx - plus_len / 2, badge_cy - plus_w / 2,
         badge_cx + plus_len / 2, badge_cy + plus_w / 2],
        radius=plus_w / 2, fill=WHITE,
    )
    draw.rounded_rectangle(
        [badge_cx - plus_w / 2, badge_cy - plus_len / 2,
         badge_cx + plus_w / 2, badge_cy + plus_len / 2],
        radius=plus_w / 2, fill=WHITE,
    )

    # A small specular highlight so the badge reads as a shiny "action"
    # button rather than a flat static icon — drawn on its own layer so
    # its partial transparency composites over the badge/glyph beneath.
    shine = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shine).ellipse(
        [badge_cx - r * 0.55, badge_cy - r * 0.75,
         badge_cx + r * 0.05, badge_cy - r * 0.15],
        fill=SHINE,
    )
    img.alpha_composite(shine)


def main() -> None:
    img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    draw.rounded_rectangle([0, 0, CANVAS, CANVAS], radius=40, fill=WHITE)

    _draw_headphone_glyph(draw, CANVAS / 2, CANVAS / 2 + 2)

    badge_r = 32
    _draw_capture_badge(img, CANVAS - badge_r - 4, CANVAS - badge_r - 4, badge_r)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUTPUT)
    print(f"saved {OUTPUT} ({img.size[0]}x{img.size[1]}, {img.mode})")


if __name__ == "__main__":
    main()
