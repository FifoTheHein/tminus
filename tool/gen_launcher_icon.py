"""Redraws the legacy launcher icons and the Play Store icon.

Run it from the repo root (it needs Pillow):

    python tool/gen_launcher_icon.py

It writes android/app/src/main/res/mipmap-*/ic_launcher.png (the visible inner
72 dp, masked to a circle, for launchers that ignore the adaptive icon) and
docs/play/icon-512.png (the same picture as a full-bleed square, because Play
applies its own mask).

The app draws the icon from the vector drawables: the XML in
res/mipmap-anydpi-v26/ and res/drawable/ is the source of truth. This script
repeats that geometry in pixels, reads the colours by name from
res/values/tminus_colors.xml, and stops if the XML no longer matches the
geometry below.
"""

import math
import re
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("This script needs Pillow: pip install Pillow")

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"
PLAY_ICON = ROOT / "docs" / "play" / "icon-512.png"

# The colour tokens the icon uses, by name in tminus_colors.xml.
BACKGROUND = "tminus_dark_primaryContainer"
TRACK = "tminus_dark_surface"
ARC = "tminus_dark_primary"
MARK = "tminus_dark_onPrimaryContainer"

# Geometry in the 108 dp adaptive-icon canvas. Angles run clockwise from
# 12 o'clock.
CENTRE = 54.0
RADIUS = 26.0  # of the track, and of the arc's centre line
STROKE = 9.0  # the width of both
TRACK_ALPHA = 0.35
ARC_SWEEP = 270.0  # from 12 o'clock clockwise to 9 o'clock, with round caps
# The T- mark as (x, y, width, height): the bar, the stem and the minus.
MARK_RECTS = (
    (38.325, 44.65, 18.7, 4.4),
    (45.475, 44.65, 4.4, 18.7),
    (59.775, 52.35, 9.9, 4.4),
)

# A launcher shows the inner 72 dp of the canvas: dp 18 to 90.
VISIBLE_FROM = 18.0
VISIBLE_SIZE = 72.0

LEGACY_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
PLAY_SIZE = 512

# The picture is drawn at 8x the largest output, then scaled down with LANCZOS.
SUPERSAMPLE = 8
MASTER = PLAY_SIZE * SUPERSAMPLE
PX_PER_DP = MASTER / VISIBLE_SIZE


def point(radius, degrees):
    """The point `degrees` clockwise from 12 o'clock on a circle round the centre, in dp."""
    angle = math.radians(degrees)
    return CENTRE + radius * math.sin(angle), CENTRE - radius * math.cos(angle)


def num(value):
    """A number the way the vector XML writes it: 54, 38.325, 0.35."""
    return f"{round(value, 3):g}"


def path_data():
    """The android:pathData of the track, the arc and the T- mark."""
    top, bottom, end = point(RADIUS, 0), point(RADIUS, 180), point(RADIUS, ARC_SWEEP)
    r = num(RADIUS)
    start = f"M{num(top[0])},{num(top[1])}"
    track = (
        f"{start} A{r},{r} 0 1,1 {num(bottom[0])},{num(bottom[1])}"
        f" A{r},{r} 0 1,1 {num(top[0])},{num(top[1])}"
    )
    large = 1 if ARC_SWEEP > 180 else 0
    arc = f"{start} A{r},{r} 0 {large},1 {num(end[0])},{num(end[1])}"
    mark = " ".join(
        f"M{num(x)},{num(y)}h{num(w)}v{num(h)}h-{num(w)}z" for x, y, w, h in MARK_RECTS
    )
    return track, arc, mark


def read_xml(path):
    """An XML resource as text, without its comments."""
    return re.sub(r"<!--.*?-->", "", path.read_text(encoding="utf-8"), flags=re.S)


def check_vectors():
    """Stops unless the vector XML still describes the geometry drawn below."""
    shapes = [f'android:pathData="{data}"' for data in path_data()]
    expected = {
        "mipmap-anydpi-v26/ic_launcher.xml": [
            f'android:drawable="@color/{BACKGROUND}"',
        ],
        "drawable/ic_launcher_foreground.xml": shapes
        + [
            f'android:strokeColor="@color/{TRACK}"',
            f'android:strokeColor="@color/{ARC}"',
            f'android:fillColor="@color/{MARK}"',
            f'android:strokeAlpha="{num(TRACK_ALPHA)}"',
            f'android:strokeWidth="{num(STROKE)}"',
            'android:strokeLineCap="round"',
        ],
        "drawable/ic_launcher_monochrome.xml": shapes,
    }
    problems = []
    for name, wanted in expected.items():
        xml = read_xml(RES / name)
        problems += [f"  {name} has no {text}" for text in wanted if text not in xml]
    if problems:
        sys.exit(
            "The vector XML no longer matches the geometry in this script. "
            "Change whichever is wrong, then run it again:\n" + "\n".join(problems)
        )


def read_colours():
    """The RGB value of each colour token the icon uses."""
    xml = (RES / "values" / "tminus_colors.xml").read_text(encoding="utf-8")
    hexes = dict(re.findall(r'<color name="(\w+)">#([0-9A-Fa-f]{6})</color>', xml))
    colours = {}
    for name in (BACKGROUND, TRACK, ARC, MARK):
        if name not in hexes:
            sys.exit(f"values/tminus_colors.xml has no colour named {name}")
        colours[name] = tuple(int(hexes[name][i : i + 2], 16) for i in (0, 2, 4))
    return colours


def px(dp):
    """A position on the canvas, in dp, as a pixel position in the master picture."""
    return round((dp - VISIBLE_FROM) * PX_PER_DP)


def disc(draw, x, y, radius, fill):
    """Fills the disc at (x, y) dp with a radius in dp."""
    left, top = px(x - radius), px(y - radius)
    right, bottom = px(x + radius) - 1, px(y + radius) - 1
    draw.ellipse([left, top, right, bottom], fill=fill)


def draw_track(draw, level):
    disc(draw, CENTRE, CENTRE, RADIUS + STROKE / 2, level)
    disc(draw, CENTRE, CENTRE, RADIUS - STROKE / 2, 0)


def draw_arc(draw, level):
    """The arc as a band between its outer and inner edge, with a round cap at each end."""
    half = STROKE / 2
    # Pillow fills a polygon including the pixels on its outline, which would
    # make the band a pixel too thick and half a pixel down and to the right of
    # the discs. So its edges are drawn half a pixel in, and up and to the left.
    nudge = 0.5 / PX_PER_DP

    def edge(radius, degrees):
        x, y = point(radius, degrees)
        return px(x - nudge), px(y - nudge)

    steps = 1440
    angles = [ARC_SWEEP * i / steps for i in range(steps + 1)]
    outer = [edge(RADIUS + half - nudge, a) for a in angles]
    inner = [edge(RADIUS - half + nudge, a) for a in reversed(angles)]
    draw.polygon(outer + inner, fill=level)
    for degrees in (0, ARC_SWEEP):
        x, y = point(RADIUS, degrees)
        disc(draw, x, y, half, level)


def draw_mark(draw, level):
    for x, y, w, h in MARK_RECTS:
        draw.rectangle([px(x), px(y), px(x + w) - 1, px(y + h) - 1], fill=level)


def render(colours):
    """The inner 72 dp of the icon as an opaque RGB picture, MASTER pixels square."""
    picture = Image.new("RGB", (MASTER, MASTER), colours[BACKGROUND])

    def paint(colour, shape, level=255):
        mask = Image.new("L", picture.size, 0)
        shape(ImageDraw.Draw(mask), level)
        picture.paste(colour, mask=mask)

    # Painting through a mask of 89 (0.35 of 255) lays the track over the
    # background at alpha 0.35, as the vector does.
    paint(colours[TRACK], draw_track, round(255 * TRACK_ALPHA))
    paint(colours[ARC], draw_arc)
    paint(colours[MARK], draw_mark)
    return picture


def scale(picture, size):
    return picture.resize((size, size), Image.Resampling.LANCZOS)


def circle_mask(size):
    """A circle that fills a size x size square, with smooth edges."""
    big = size * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, big - 1, big - 1], fill=255)
    return mask.resize((size, size), Image.Resampling.LANCZOS)


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    print(f"wrote {path.relative_to(ROOT).as_posix()} ({image.width}x{image.height})")


def main():
    check_vectors()
    master = render(read_colours())
    for density, size in LEGACY_SIZES.items():
        icon = scale(master, size).convert("RGBA")
        icon.putalpha(circle_mask(size))
        save(icon, RES / f"mipmap-{density}" / "ic_launcher.png")
    save(scale(master, PLAY_SIZE).convert("RGBA"), PLAY_ICON)


if __name__ == "__main__":
    main()
