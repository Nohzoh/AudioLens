"""Regenerates the app's launcher icon (ic_launcher.png / ic_launcher_round.png,
every mipmap density).

Previously a flat PNG with no vector/procedural source in the repo — it
appears to have been produced outside the repo at some point (#150's
investigation). Regenerating it via the same shared _headphone_glyph
module the quick-capture widget icon and the Play Store listing icon
use guarantees the three can't visually drift apart from each other the
way hand-scaling a copy of the same shapes invites.

Matches the icon already shipped: a white circle (ic_launcher.png has
no background of its own baked in — what's actually opaque is a plain
white circle inscribed in the canvas; everything else is transparent,
left for the OS/launcher to mask/fill) with the dark/blue headphone+
waveform glyph on top. Deliberately no "+" badge — that signals "start
a new capture", specific to the quick-capture widget, not the app
identity as a whole.

Drawn once at a high-resolution master (512px) and downsampled per
density with LANCZOS resampling, rather than redrawing the vector
shapes at each small size — smoother results, and avoids the small-size
rounding differences that redrawing from scratch at e.g. 48px would
otherwise introduce between densities.

Usage: python3 scripts/generate_app_icon.py
Requires: pip install pillow
"""

from pathlib import Path

from PIL import Image, ImageDraw

from _headphone_glyph import draw_headphone_glyph

MASTER_CANVAS = 512
SCALE = MASTER_CANVAS / 512  # 1.0 — this *is* the canonical resolution
DARK = (26, 26, 46, 255)
BLUE = (74, 144, 217, 255)
WHITE = (255, 255, 255, 255)

# Standard Android mipmap densities.
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

RES_DIR = Path(__file__).resolve().parent.parent / "android" / "app" / "src" / "main" / "res"


def _render_master() -> Image.Image:
    img = Image.new("RGBA", (MASTER_CANVAS, MASTER_CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Full-bleed white circle, matching the icon already shipped —
    # not a rounded square (that's the widget's own look).
    r = MASTER_CANVAS / 2
    draw.ellipse([0, 0, MASTER_CANVAS, MASTER_CANVAS], fill=WHITE)

    cy = MASTER_CANVAS / 2 + round(10 * SCALE)
    draw_headphone_glyph(draw, MASTER_CANVAS / 2, cy, SCALE, DARK, BLUE)

    return img


def main() -> None:
    master = _render_master()

    for density, size in DENSITIES.items():
        resized = master.resize((size, size), Image.LANCZOS)
        density_dir = RES_DIR / f"mipmap-{density}"
        density_dir.mkdir(parents=True, exist_ok=True)
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            out = density_dir / name
            resized.save(out)
            print(f"saved {out} ({size}x{size})")


if __name__ == "__main__":
    main()
