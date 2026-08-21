"""Regenerates the quick-capture home-screen widget's icon (new feature).

A camera glyph (not the app's headphone logo — a camera icon reads
"tap to capture" more directly at 1x1 widget size) on the app's brand
purple background, matching the rounded-square silhouette of the
launcher icon. Used as both the widget's ImageView source and its
Android 12+ widget-picker preview image.

Usage: python3 scripts/generate_widget_icon.py
Requires: pip install pillow
"""

from pathlib import Path

from PIL import Image, ImageDraw

CANVAS = 192
BRAND_PURPLE = (107, 78, 255, 255)
WHITE = (255, 255, 255, 255)

OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "android" / "app" / "src" / "main" / "res" / "drawable-nodpi" / "widget_quick_capture.png"
)


def main() -> None:
    img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    draw.rounded_rectangle([0, 0, CANVAS, CANVAS], radius=40, fill=BRAND_PURPLE)

    cx, cy = CANVAS // 2, CANVAS // 2 + 4

    body_w, body_h = 108, 78
    body = [cx - body_w / 2, cy - body_h / 2 + 6, cx + body_w / 2, cy + body_h / 2 + 6]
    draw.rounded_rectangle(body, radius=14, fill=WHITE)

    bump_w, bump_h = 40, 16
    bump = [
        cx - 6 - bump_w / 2, body[1] - bump_h + 6,
        cx - 6 + bump_w / 2, body[1] + 6,
    ]
    draw.rounded_rectangle(bump, radius=6, fill=WHITE)

    lens_r = 22
    draw.ellipse(
        [cx - lens_r, cy + 6 - lens_r, cx + lens_r, cy + 6 + lens_r], fill=BRAND_PURPLE
    )
    inner_r = 14
    draw.ellipse(
        [cx - inner_r, cy + 6 - inner_r, cx + inner_r, cy + 6 + inner_r], fill=WHITE
    )
    core_r = 7
    draw.ellipse(
        [cx - core_r, cy + 6 - core_r, cx + core_r, cy + 6 + core_r], fill=BRAND_PURPLE
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUTPUT)
    print(f"saved {OUTPUT} ({img.size[0]}x{img.size[1]}, {img.mode})")


if __name__ == "__main__":
    main()
