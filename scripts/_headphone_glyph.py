"""Shared headphone+waveform glyph, used by every AudioLens icon
generator (app launcher icon, quick-capture widget icon, Play Store
listing icon) so the three can't visually drift apart from each other
by each maintaining their own hand-scaled copy of the same shapes —
exactly the kind of "slightly different rendering" mismatch that
motivated pulling this out (#150 follow-up).

Proportions are expressed relative to a 512-unit canonical canvas
(generate_play_store_icon.py's original resolution, the highest-
fidelity of the three) — callers on a smaller canvas pass
`scale = canvas_size / 512`, and the vertical centering nudge below
scales the same way so the glyph sits proportionally identically
regardless of final resolution.

Requires: pip install pillow
"""

import math

# #214: the glyph read as too small inside its circle/square — every
# proportion below is scaled up by this factor on top of whatever scale
# the caller passes, so the app/widget/Play Store icons all grow together
# without each caller having to change its own scale math. 1.2 is the
# largest factor that still clears the quick-capture widget's '+' badge
# without the right earcup crowding it (checked up to 1.5, where it does).
GLYPH_FILL = 1.2


def draw_headphone_glyph(draw, cx, cy, scale, dark, blue):
    """Draws the glyph centered at (cx, cy) — callers pass their own
    canvas center plus the same proportional nudge (round(10 * scale))
    used everywhere else, so cy is typically canvas_size/2 + round(10*scale).
    """
    scale = scale * GLYPH_FILL
    band_r = 130 * scale
    band_w = 34 * scale
    y_offset = 20 * scale
    bbox = [cx - band_r, cy - band_r - y_offset, cx + band_r, cy + band_r - y_offset]
    draw.arc(bbox, start=200, end=340, fill=dark, width=max(1, round(band_w)))
    for ang in (200, 340):
        rad = math.radians(ang)
        px = cx + band_r * math.cos(rad)
        py = (cy - y_offset) + band_r * math.sin(rad)
        draw.ellipse(
            [px - band_w / 2, py - band_w / 2, px + band_w / 2, py + band_w / 2],
            fill=dark,
        )

    cup_w, cup_h = 62 * scale, 108 * scale
    cup_y = cy + 30 * scale
    cup_nudge = 8 * scale
    left_cup = [
        cx - band_r - cup_w / 2 + cup_nudge, cup_y - cup_h / 2,
        cx - band_r + cup_w / 2 + cup_nudge, cup_y + cup_h / 2,
    ]
    right_cup = [
        cx + band_r - cup_w / 2 - cup_nudge, cup_y - cup_h / 2,
        cx + band_r + cup_w / 2 - cup_nudge, cup_y + cup_h / 2,
    ]
    draw.rounded_rectangle(left_cup, radius=28 * scale, fill=dark)
    draw.rounded_rectangle(right_cup, radius=28 * scale, fill=dark)

    heights = [46, 84, 130, 84, 46]
    bar_w = 22 * scale
    gap = 14 * scale
    total_w = bar_w * 5 + gap * 4
    start_x = cx - total_w / 2
    for i, h in enumerate(heights):
        hh = h * scale
        x0 = start_x + i * (bar_w + gap)
        x1 = x0 + bar_w
        y0 = cup_y - hh / 2
        y1 = cup_y + hh / 2
        draw.rounded_rectangle([x0, y0, x1, y1], radius=bar_w / 2, fill=blue)
