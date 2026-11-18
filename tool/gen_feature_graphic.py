"""Draws the Play Store feature graphic.

Run it from the repo root (it needs Pillow):

    python tool/gen_feature_graphic.py

It writes docs/play/feature-graphic.png: 1024 x 500 px, a 24-bit PNG with no
alpha channel (Play refuses a feature graphic that has one). The icon's slate
background fills the picture, the countdown mark fills its left third, and the
app name and tagline are set at the right in IBM Plex Sans.

The mark is not drawn again here. This script loads tool/gen_launcher_icon.py,
which holds the icon's geometry and its colour tokens, and uses that script's
renderer, so the graphic follows the icon. It runs that script's check of the
launcher vectors first and stops if the check fails. The check looks for each
expected attribute somewhere in the XML, so test/launcher_icon_test.dart, which
pins every attribute on its own element, is the exact guard. The text is the
bundled font from assets/fonts/ibm-plex-sans/, laid out with Pillow's basic
engine so that the output does not depend on whether the machine has libraqm.
Running the script twice writes the same bytes.
"""

import importlib.util
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("This script needs Pillow: pip install Pillow")

# The icon script is loaded by its path: `python -I` leaves this script's folder
# off sys.path. No bytecode is written beside it.
sys.dont_write_bytecode = True
_ICON_SCRIPT = Path(__file__).resolve().parent / "gen_launcher_icon.py"
_spec = importlib.util.spec_from_file_location("gen_launcher_icon", _ICON_SCRIPT)
icon = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(icon)

WIDTH = 1024
HEIGHT = 500
OUTPUT = icon.ROOT / "docs" / "play" / "feature-graphic.png"

FONTS = icon.ROOT / "assets" / "fonts" / "ibm-plex-sans"
TITLE_FONT = FONTS / "IBMPlexSans-SemiBold.ttf"
TAGLINE_FONT = FONTS / "IBMPlexSans-Medium.ttf"

TITLE = "T-Minus"
# "Meeting alarms you can't miss", broken after "alarms" so that it can be set
# large. The apostrophe is the typographic one.
TAGLINE = ("Meeting alarms", "you can\u2019t miss")

# Layout, in pixels of the final picture. One margin runs from the left edge to
# the mark. The mark ends where the left third ends, and the text starts one
# margin after that, so the picture's right margin is about the same.
MARGIN = 72
THIRD = WIDTH // 3
MARK_DIAMETER = THIRD - MARGIN  # the outer diameter of the mark's ring
TITLE_SIZE = 145
TAGLINE_SIZE = 50
TAGLINE_LEADING = 66  # from one tagline baseline to the next
TITLE_TO_TAGLINE = 44  # from the title's baseline to the tagline's cap height

# Text is drawn at 4x and scaled down, like the icon script's shapes, so that
# glyph positions are not rounded to whole pixels.
SUPERSAMPLE = 4


def font(path, size):
    """The font at `size` px of the final picture, loaded at SUPERSAMPLE times that."""
    return ImageFont.truetype(
        str(path), size * SUPERSAMPLE, layout_engine=ImageFont.Layout.BASIC
    )


def ink(face, text):
    """(left, top, right, bottom) of `text` from its baseline, in final pixels."""
    box = face.getbbox(text, anchor="ls")
    return tuple(value / SUPERSAMPLE for value in box)


def place_mark(canvas, colours):
    """Pastes the launcher icon's countdown mark into the left third."""
    ring_dp = 2 * (icon.RADIUS + icon.STROKE / 2)
    side = round(MARK_DIAMETER * icon.VISIBLE_SIZE / ring_dp)
    mark = icon.scale(icon.render(colours), side)
    # The ring is centred in the icon's visible square, so centring the square
    # centres the ring. The square's background is the canvas colour, so it
    # leaves no seam.
    left = round(MARGIN + MARK_DIAMETER / 2 - side / 2)
    top = round(HEIGHT / 2 - side / 2)
    canvas.paste(mark, (left, top))


def draw_text(canvas, colours, left):
    """Sets the title and the tagline from x = `left`, centred in height."""
    title = font(TITLE_FONT, TITLE_SIZE)
    tagline = font(TAGLINE_FONT, TAGLINE_SIZE)

    # The block runs from the title's cap height to the bottom of the last
    # tagline line's ink, and is centred on the picture.
    title_cap = -ink(title, TITLE)[1]
    tag_cap = -ink(tagline, TAGLINE[0])[1]
    last_bottom = ink(tagline, TAGLINE[-1])[3]
    block = (
        title_cap
        + TITLE_TO_TAGLINE
        + tag_cap
        + TAGLINE_LEADING * (len(TAGLINE) - 1)
        + last_bottom
    )
    title_baseline = (HEIGHT - block) / 2 + title_cap
    first_baseline = title_baseline + TITLE_TO_TAGLINE + tag_cap

    def lay(face, text, baseline, colour):
        mask = Image.new("L", (WIDTH * SUPERSAMPLE, HEIGHT * SUPERSAMPLE), 0)
        ImageDraw.Draw(mask).text(
            (left * SUPERSAMPLE, baseline * SUPERSAMPLE),
            text,
            font=face,
            fill=255,
            anchor="ls",
        )
        mask = mask.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
        canvas.paste(colour, mask=mask)

    lay(title, TITLE, title_baseline, colours[icon.MARK])
    for i, line in enumerate(TAGLINE):
        lay(tagline, line, first_baseline + i * TAGLINE_LEADING, colours[icon.ARC])


def main():
    icon.check_vectors()
    colours = icon.read_colours()
    canvas = Image.new("RGB", (WIDTH, HEIGHT), colours[icon.BACKGROUND])
    place_mark(canvas, colours)
    draw_text(canvas, colours, THIRD + MARGIN)
    icon.save(canvas, OUTPUT)


if __name__ == "__main__":
    main()
