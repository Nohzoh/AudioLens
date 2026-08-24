"""Regenerates the quick-capture home-screen widget's icon.

#150: the widget previously drew a camera glyph, unrelated to the app's
actual headphone+waveform launcher icon (mipmap ic_launcher.png) — the
two just didn't read as the same app. This draws the same headphone+
waveform glyph (via the shared _headphone_glyph module, also used by
generate_app_icon.py/generate_play_store_icon.py — a single source of
proportions, so the three can't visually drift apart from each other)
on a white background, matching what the real app icon looks like day
to day (ic_launcher.png has no baked-in background of its own — see
generate_app_icon.py). A small "+" badge (brand purple, a bit of shine
on it) in the bottom-right corner signals "start a new capture" at a
glance — the one deliberate difference from the plain app icon.

Usage: python3 scripts/generate_widget_icon.py
Requires: pip install pillow
"""

from pathlib import Path

from PIL import Image, ImageDraw

from _headphone_glyph import draw_headphone_glyph

CANVAS = 192
SCALE = CANVAS / 512
BRAND_PURPLE = (107, 78, 255, 255)
DARK = (26, 26, 46, 255)
BLUE = (74, 144, 217, 255)
WHITE = (255, 255, 255, 255)
SHINE = (255, 255, 255, 110)

OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "android" / "app" / "src" / "main" / "res" / "drawable-nodpi" / "widget_quick_capture.png"
)


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

    cy = CANVAS / 2 + round(10 * SCALE)
    draw_headphone_glyph(draw, CANVAS / 2, cy, SCALE, DARK, BLUE)

    badge_r = 32
    _draw_capture_badge(img, CANVAS - badge_r - 4, CANVAS - badge_r - 4, badge_r)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUTPUT)
    print(f"saved {OUTPUT} ({img.size[0]}x{img.size[1]}, {img.mode})")


if __name__ == "__main__":
    main()
