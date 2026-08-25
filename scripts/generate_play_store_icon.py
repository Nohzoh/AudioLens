"""Regenerates distribution/play-store/icon-512.png (T110, #251).

The original mipmap launcher icon (android/app/src/main/res/mipmap-*/
ic_launcher.png) has transparent corners around a white body — fine for
Android's adaptive-icon masking, but Play Console requires a flat, opaque
icon and flattens transparency to white, producing a stark white square
against the store's dark theme. This draws the same headphone+waveform
glyph (via the shared _headphone_glyph module, also used by
generate_app_icon.py/generate_widget_icon.py — this is the module's
canonical 512px/scale=1.0 resolution, so it's a single source of
proportions across all three) at native 512x512 resolution (crisper
than upscaling the 192px mipmap source).

#251: background is plain white, not the brand purple T110 originally
used — purple was a one-off invented specifically for this asset and
matched nothing else (the real launcher icon's own background is a
white circle, per generate_app_icon.py), which read as an inconsistent
band-aid rather than a deliberate identity choice. White keeps this
icon visually identical to the actual app icon everywhere else it
appears (home screen, widget) — Play Console flattening transparency to
white was never really the problem; a *different* background than the
rest of the app's own icon was.

Usage: python3 scripts/generate_play_store_icon.py
Requires: pip install pillow

Output still needs to be uploaded manually to Play Console — see
AGENTS.md's "Play Store Listing Icon" section.
"""

from pathlib import Path

from PIL import Image, ImageDraw

from _headphone_glyph import draw_headphone_glyph

CANVAS = 512
SCALE = CANVAS / 512  # 1.0 — this *is* the module's canonical resolution
WHITE = (255, 255, 255)
DARK = (26, 26, 46)
BLUE = (74, 144, 217)

OUTPUT = Path(__file__).resolve().parent.parent / "distribution" / "play-store" / "icon-512.png"


def main() -> None:
    img = Image.new("RGB", (CANVAS, CANVAS), WHITE)
    draw = ImageDraw.Draw(img)

    cy = CANVAS / 2 + round(10 * SCALE)
    draw_headphone_glyph(draw, CANVAS / 2, cy, SCALE, DARK, BLUE)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUTPUT)
    print(f"saved {OUTPUT} ({img.size[0]}x{img.size[1]}, {img.mode})")


if __name__ == "__main__":
    main()
