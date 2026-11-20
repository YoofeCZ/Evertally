"""Draw Evertally's UI glyphs, map pins and navigation art with Pillow.

Run from any directory. The textures are straight-alpha, uncompressed 32-bit
TGAs. UI and map glyphs use white so both are tintable by the Lua themes.
"""

import argparse
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


ADDON = Path(__file__).resolve().parents[1] / "addon"
# Shapes are specified on a 24-unit grid. L/P are a round stroke/solid polygon,
# E/D an outlined/solid ellipse, and A an arc (bounding box and angles).
GLYPHS = {
    "bolt": "P 13,2 4,14 10,14 9,22 20,9 14,9 15,2",
    "bug": "E 8,8 16,19; L 7,10 4,8; L 7,14 3,14; L 7,18 4,21; L 17,10 20,8; L 17,14 21,14; L 17,18 20,21; L 9,4 10,7; L 15,4 14,7; L 12,10 12,18",
    "check": "L 4,12 9,17 20,6",
    "chevron-down": "L 5,8 12,15 19,8",
    "chevron-left": "L 15,5 8,12 15,19",
    "chevron-right": "L 9,5 16,12 9,19",
    "chevron-up": "L 5,15 12,8 19,15",
    "close": "L 5,5 19,19; L 19,5 5,19",
    "compact": "L 4,9 4,4 9,4; L 15,4 20,4 20,9; L 20,15 20,20 15,20; L 9,20 4,20 4,15; L 9,9 15,15; L 15,9 9,15",
    "cross": "L 12,4 12,20; L 4,12 20,12",
    "eye": "L 2.5,12 7,7.5 12,6 17,7.5 21.5,12 17,16.5 12,18 7,16.5 2.5,12; D 9.5,9.5 14.5,14.5",
    "flag": "L 5,21 5,4; P 5,5 20,5 16,10 20,15 5,15",
    "gamepad": "L 3,11 6,7 18,7 21,11 21,17 18,19 15,15 9,15 6,19 3,17 3,11; L 6.5,11 10.5,11; L 8.5,9 8.5,13; D 15,10 17,12; D 18,12 20,14",
    "gear": "E 6,6 18,18; L 12,3 12,6; L 12,18 12,21; L 3,12 6,12; L 18,12 21,12; L 5.5,5.5 7.5,7.5; L 16.5,16.5 18.5,18.5; L 18.5,5.5 16.5,7.5; L 7.5,16.5 5.5,18.5; D 10.5,10.5 13.5,13.5",
    "guides": "L 12,6 8,4 3,4 3,18 8,18 12,20 16,18 21,18 21,4 16,4 12,6 12,20; L 6.5,9 8.5,10; L 15.5,10 17.5,9",
    "hourglass": "L 5,3 19,3; L 5,21 19,21; L 7,3 7,7 11,12 7,17 7,21; L 17,3 17,7 13,12 17,17 17,21",
    "hourglass-sand": "P 8,7 16,7 12,11; P 8,20 12,15 16,20",
    "house": "L 3,11 12,3 21,11; L 5.5,10 5.5,20 18.5,20 18.5,10; P 10,14 14,14 14,20 10,20",
    "icon-accept": "L 12,4 12,14; D 10.4,17 13.6,20.2",
    "icon-achieve": "L 7,4 17,4 17,11 15,14 9,14 7,11 7,4; L 7,6 3,6 3,10 7,12; L 17,6 21,6 21,10 17,12; L 12,14 12,20; L 8,20 16,20",
    "icon-boat": "P 3,15 21,15 17,20 7,20; L 12,4 12,14; P 10,5 5,13 10,13; P 14,6 19,13 14,13",
    "icon-bridge": "L 3,9 21,9; L 4,9 4,19; L 20,9 20,19; L 7,17 7,15 10,12 14,12 17,15 17,17; L 6,5 6,9; L 18,5 18,9",
    "icon-buy": "E 3,4 17,18; L 10,8 10,14; L 7,11 13,11; L 15,20 20,20 21,16",
    "icon-cave": "L 2.5,19 6,9 11,4 17,6 21.5,19 2.5,19; L 8,19 8,15 12,11 16,15 16,19",
    "icon-collect": "L 3,11 21,11 18,20 6,20 3,11; L 8,11 12,4 16,11; L 10,14 11,17; L 14,14 13,17",
    "icon-complete": "L 7,12 11,16 17,9; L 14,4 7,4 3,8 3,16 7,20 17,20 21,16 21,9",
    "icon-craft": "P 3,9 21,9 17,13 14,13 14,17 18,17 18,20 6,20 6,17 9,17 9,13 6,13; L 8,5 16,5",
    "icon-dungeon": "L 4,20 4,9 8,4 16,4 20,9 20,20 4,20; L 9,19 9,11 12,8 15,11 15,19",
    "icon-elite": "L 4,15 3,7 8,11 12,4 16,11 21,7 20,15 4,15; L 5,20 19,20",
    "icon-explore": "E 3,3 21,21; P 16.8,7.2 14.3,14.3 7.2,16.8 9.7,9.7; D 10.6,10.6 13.4,13.4",
    "icon-fly": "P 3,6 12,11 21,6 19,12 15,15 12,20 9,15 5,12; L 4,6 9,8; L 20,6 15,8",
    "icon-forever": "L 12,12 8,7 5,7 3,9 3,15 5,17 8,17 16,7 19,7 21,9 21,15 19,17 16,17 12,12",
    "icon-gate": "L 3,20 3,5 21,5 21,20; L 8,20 8,10 16,10 16,20; D 10,2 14,6",
    "icon-getfp": "P 3,5 11,9 21,5 18,11 13,13 11,17 8,13 5,10; L 17,14 17,21; L 14,17.5 20,17.5",
    "icon-goto": "L 12,22 5,13 4,9 6,5 9,3 15,3 18,5 20,9 19,13 12,22; D 9,7 15,13",
    "icon-hearth": "L 6,3 15,3 20,8 20,16 15,21 6,21 3,17 3,8 6,3; L 14,7 10,7 7,10 7,14 10,17 15,17 16,13 12,12 10,14",
    "icon-interact": "L 7,20 3,13 6,12 9,15 9,5 12,3 14,5 14,11 19,11 21,14 19,20 7,20",
    "icon-kill": "P 21,3 20,9 9,19 5,15 15,4; L 4,13 11,20; L 7,17 3,21",
    "icon-learn": "L 3,9 12,4 21,9 12,14 3,9; L 7,12 7,17 12,20 17,17 17,12; L 21,9 21,16",
    "icon-level": "L 4,11 12,4 20,11; L 6,17 12,12 18,17; L 9,21 15,21",
    "icon-lift": "P 4,8 8,3 12,8; P 12,16 16,21 20,16; L 3,12 21,12",
    "icon-mount": "L 4,19 7,15 7,9 10,4 13,7 17,6 21,11 18,15 14,13 13,19 4,19; D 14,8 17,11",
    "icon-note": "L 5,21 5,3 16,3 19,6 19,21 5,21; L 9,8 15,8; L 9,12 15,12; L 9,16 12,16",
    "icon-pass": "L 3,18 8,6 10,11; L 14,10 17,5 21,18; L 10,20 12,15 14,20",
    "icon-rep": "L 4,20 4,14 7,11 10,11 12,14 14,11 17,11 20,14 20,20; E 5,4 11,10; E 13,4 19,10; L 10,20 14,20",
    "icon-repair": "L 18,3 15,6 18,9 21,6 21,10 17,14 13,14 6,21 3,18 10,11 10,7 14,3 18,3",
    "icon-sell": "E 3,4 17,18; L 7,11 13,11; L 15,20 20,20 21,16",
    "icon-sethome": "L 3,11 12,3 21,11; L 5,10 5,20 12,20; L 19,10 19,13; L 13,17 16,20 21,15",
    "icon-skill": "P 4,13 8,13 8,20 4,20; P 10,8 14,8 14,20 10,20; P 16,4 20,4 20,20 16,20",
    "icon-talk": "L 3,5 21,5 21,16 12,16 6,21 6,16 3,16 3,5; D 6,9 9,12; D 10.5,9 13.5,12; D 15,9 18,12",
    "icon-train": "L 5,20 5,4 17,4 17,13; L 9,8 13,8; L 9,12 12,12; L 14,18 17,15 20,18; L 17,16 17,21",
    "icon-treasure": "L 3,20 3,10 7,5 17,5 21,10 21,20 3,20; L 3,12 21,12; P 10,11 14,11 14,16 10,16",
    "icon-turnin": "L 6,7 8,4 14,4 18,7 18,10 12,14; D 10.4,17 13.6,20.2",
    "icon-use": "P 12,2 14.5,9.5 22,12 14.5,14.5 12,22 9.5,14.5 2,12 9.5,9.5",
    "icon-vendor": "L 3,7 6,4 18,4 21,7 21,11 3,11 3,7; L 5,11 5,20 19,20 19,11; L 8,15 16,15",
    "info": "E 3,3 21,21; D 10.5,6.5 13.5,9.5; L 12,12 12,17",
    "layers": "L 3,8 12,3 21,8 12,13 3,8; L 3,12 12,17 21,12; L 3,16 12,21 21,16",
    "lock": "L 6,10 6,7 9,4 15,4 18,7 18,10; L 4,10 20,10 20,21 4,21 4,10; L 12,14 12,17",
    "menu": "L 4,6 20,6; L 4,12 20,12; L 4,18 20,18",
    "pad-circle": "E 4,4 20,20",
    "pad-cross": "L 5,5 19,19; L 19,5 5,19",
    "pad-square": "L 4,4 20,4 20,20 4,20 4,4",
    "pad-triangle": "L 12,4 21,20 3,20 12,4",
    "palette": "L 19,16 15,16 14,20 7,20 3,16 3,9 8,4 16,4 21,9 21,13 19,16; D 6,9 9,12; D 10,6 13,9; D 15,7 18,10",
    "plug": "L 8,4 8,9; L 16,4 16,9; L 4,9 20,9; L 6,9 6,14 9,17 15,17 18,14 18,9; L 12,17 12,21",
    "plus": "L 12,4 12,20; L 4,12 20,12",
    "qol-coin": "E 3,3 21,21; L 12,7 12,17; L 9,9 12,7 15,9; L 9,17 15,17",
    "qol-fly-arrow": "P 12,3 22,19 12,15 2,19",
    "qol-target": "E 5,5 19,19; L 12,3 12,7; L 12,17 12,21; L 3,12 7,12; L 17,12 21,12; D 10,10 14,14",
    "qol-toggles": "L 5,4 5,20; L 12,4 12,20; L 19,4 19,20; D 2,6 8,12; D 9,13 15,19; D 16,7 22,13",
    "qol-upgrade": "P 12,3 21,12 16,12 16,19 8,19 8,12 3,12",
    "record": "E 3,3 21,21; D 7.5,7.5 16.5,16.5",
    "reload": "A 4,4 20,20 15,315; P 14,6 21,4 21,11",
    "reset": "A 4,4 20,20 225,515; P 3,4 10,6 3,11; L 12,8 12,12 15,14",
    "resize": "L 4,20 20,4; L 11,20 20,11; L 17,20 20,17",
    "search": "E 3,3 15,15; L 13,13 20,20",
    "skip": "P 4,5 15,12 4,19; L 19,5 19,19",
    "sliders": "L 4,6 20,6; L 4,12 20,12; L 4,18 20,18; L 8,3 8,9; L 16,9 16,15; L 10,15 10,21",
    "speaker": "P 3,9 7,9 12,4 12,20 7,15 3,15; A 10,6 21,18 -65,65; A 12,9 17,15 -65,65",
    "star": "P 12,2 15,8.5 22,9.5 17,14.2 18.5,21.5 12,18 5.5,21.5 7,14.2 2,9.5 9,8.5",
    "window": "L 3,4 21,4 21,20 3,20 3,4; L 3,9 21,9; L 8,9 8,20",
    "journal": "L 6,3 19,3 19,17 8,17 6,19 8,21 19,21; L 6,3 6,19; L 10,8 16,8; L 10,12 14,12; L 3,7 6,7; L 3,12 6,12",
    "map-fold": "L 3,6 9,3 15,6 21,3 21,18 15,21 9,18 3,21 3,6; L 9,3 9,18; L 15,6 15,21",
    "route": "E 3,14 9,20; E 15,3 21,9; L 9,16 13,16 15,13 12,10 16,8",
    "database": "E 4,3 20,9; A 4,9 20,15 0,180; A 4,15 20,21 0,180; L 4,6 4,18; L 20,6 20,18",
    "recipes": "L 3,7 9,7 9,3 16,3 21,8 21,21 3,21 3,7; L 16,3 16,9 21,9; L 7,13 16,13; L 7,17 14,17",
    "people": "E 4,4 12,12; A 2.5,14 13.5,24 180,360; A 13,4 20,12 -95,95; A 13.5,14 22,24 240,360",
    "armor": "L 7,4 10,6 14,6 17,4 21,7 18,12 16,11 16,21 8,21 8,11 6,12 3,7 7,4; L 11,15 13,15",
    "bag": "L 3,9 21,9 20,20 4,20 3,9; L 8,9 8,6 10,4 14,4 16,6 16,9; L 10,14 14,14",
    "watch": "E 4,6 20,22; L 10,3 14,3; L 12,3 12,6; L 12,10 12,14 16,14",
    "play": "P 6,3 21,12 6,21",
    "pause": "P 6,4 10,4 10,20 6,20; P 14,4 18,4 18,20 14,20",
    "previous": "P 19,4 8,12 19,20; L 5,5 5,19",
    "note": "D 4,15 13,21; L 12,17 12,4 20,7 20,10 12,7",
    "ankh": "E 8,3 16,11; L 12,11 12,21; L 6,14 18,14",
    "auction": "L 6,4 10,4 14,8 10,12 6,12 3,9 6,4; L 12,10 20,18; L 3,19 12,19",
    "bank": "L 3,8 12,3 21,8 3,8; L 5,11 5,17; L 12,11 12,17; L 19,11 19,17; L 3,20 21,20",
    "battlemaster": "L 4,4 8,5 19,17; L 20,4 16,5 5,17; L 15,19 21,14; L 3,14 9,19",
    "skull": "L 8,20 8,17 4,14 4,8 8,4 16,4 20,8 20,14 16,17 16,20 8,20; D 6,9 11,13; D 13,9 18,13; L 12,17 12,20",
    "bed": "L 3,6 3,20; L 3,17 21,17 21,20; L 3,12 8,12 10,15 10,11 18,11 21,14 21,17",
    "mail": "L 3,5 21,5 21,19 3,19 3,5; L 3,6 12,13 21,6",
    "portal": "E 5,3 19,21; L 3,21 21,21; A 9,7 15,17 60,350",
    "stable": "A 4,3 20,19 0,180; L 4,11 4,5 8,5 8,10; L 20,11 20,5 16,5 16,10; A 8,7 16,15 0,180",
    "stop": "P 8,3 16,3 21,8 21,16 16,21 8,21 3,16 3,8",
    "tram": "L 5,18 5,4 19,4 19,18 5,18; L 5,12 19,12; D 7,14 10,17; D 14,14 17,17; L 8,18 6,21; L 16,18 18,21",
    "zeppelin": "L 3,10 5,7 11,5 18,6 21,9 21,11 18,14 11,15 5,13 3,10; L 5,10 19,10; L 10,15 10,19 16,19 16,15",
    "warrior": "L 4,4 20,4 20,13 16,18 12,21 8,18 4,13 4,4; L 12,7 12,16; L 8,11 16,11",
    "heal": "P 9,3 15,3 15,9 21,9 21,15 15,15 15,21 9,21 9,15 3,15 3,9 9,9",
    "key": "E 3,3 13,13; L 11,11 20,20; L 15,15 18,12; L 18,18 21,15",
    "person": "E 8,3 16,11; L 4,20 4,17 8,14 16,14 20,17 20,20",
    "rare": "L 12,2.5 21.5,12 12,21.5 2.5,12 12,2.5; P 12,7.5 16.5,12 12,16.5 7.5,12",
    "target": "E 4,4 20,20; E 8,8 16,16; D 10.5,10.5 13.5,13.5",
    "pin": "P 12,2 22,12 12,22 2,12",
    "arrival-ring": "L 8,3 16,3 21,8 21,16 16,21 8,21 3,16 3,8 8,3",
    "emblem": "L 6,2 18,2 22,6 22,18 18,22 6,22 2,18 2,6 6,2; L 7.6,7 6.6,17; L 10.5,7 9.5,17; L 13.4,7 12.4,17; L 16.3,7 15.3,17; L 5,15.4 19,8.6",
    "emblem-hot": "D 10.4,10.4 13.6,13.6",
}

UI_ALIASES = {
    "quest-kill": "icon-kill", "quest-loot": "bag", "skin-check": "check",
    "icon-skull": "skull", "icon-zeppelin": "zeppelin", "icon-tram": "tram",
}
MAP_GLYPHS = {
    "ankh": "ankh", "auction": "auction", "bank": "bank", "battlemaster": "battlemaster",
    "corpse": "skull", "elevator": "icon-lift", "flightmaster": "icon-fly", "inn": "bed",
    "loot": "bag", "mailbox": "mail", "pin-small": "pin", "pin": "icon-goto",
    "portal": "portal", "quest-available": "icon-accept", "quest-turnin": "icon-turnin",
    "raid": "icon-elite", "rare": "rare", "stable": "stable", "stop": "stop", "target": "target",
    "trainer-class": "icon-learn", "trainer-profession": "icon-craft", "trainer-weapon": "battlemaster",
    "tram": "tram", "zeppelin": "zeppelin",
    **{name: "icon-" + name for name in (
        "boat", "bridge", "cave", "dungeon", "explore", "kill", "pass", "repair", "treasure", "use", "vendor",
    )},
}
NON_GUIDE_UI_GLYPHS = {
    "arrival-ring", "bed", "emblem", "emblem-hot", "mail", "warrior", "heal", "key", "person", "target", "pin",
    "pause", "play", "previous", "note", "ankh", "auction", "bank", "battlemaster", "portal", "stable", "stop", "watch",
}
CORE_GLYPHS = {
    "armor", "bag", "bank", "bed", "bolt", "bug", "check", "close", "database", "eye", "flag", "gear",
    "guides", "heal", "hourglass", "house", "info", "journal", "key", "layers", "lock", "mail", "map-fold",
    "palette", "pause", "people", "person", "plug", "rare", "recipes", "reload", "reset", "resize",
    "route", "search", "sliders", "speaker", "star", "stop", "warrior", "watch", "window",
    "qol-upgrade", "qol-target", "skull",
    "icon-accept", "icon-achieve", "icon-craft", "icon-dungeon", "icon-elite", "icon-explore",
    "icon-fly", "icon-goto", "icon-kill", "icon-learn", "icon-level", "icon-note", "icon-skill",
    "icon-talk", "icon-train", "icon-turnin", "icon-vendor",
    "chevron-down", "chevron-left", "chevron-right", "chevron-up",
}


def glyph(name, size=32, *, color="white", extent=1, weight=2.35):
    """Rasterize one glyph with consistent round line endings and antialiasing."""
    canvas = Image.new("RGBA", (size * 4, size * 4))
    draw = ImageDraw.Draw(canvas)
    scale = size * 4 * extent / 24
    center = size * 2
    pen = round(weight * scale)

    def point(value):
        x, y = map(float, value.split(","))
        return center + (x - 12) * scale, center + (y - 12) * scale

    for command in GLYPHS[name].split("; "):
        kind, *args = command.split()
        if kind == "A":
            start, end = map(float, args[2].split(","))
            draw.arc([point(arg) for arg in args[:2]], start, end, fill=color, width=pen)
            continue
        points = [point(arg) for arg in args]
        if kind == "L":
            draw.line(points, fill=color, width=pen, joint="curve")
            for x, y in points:
                radius = (pen - 1) / 2
                draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)
        elif kind == "P":
            draw.polygon(points, fill=color)
        elif kind == "D":
            draw.ellipse(points, fill=color)
        else:
            draw.ellipse(points, outline=color, width=pen)
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def drawing(size, painter):
    canvas = Image.new("RGBA", (size * 3, size * 3))
    painter(ImageDraw.Draw(canvas), size * 3 / 24)
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def polygon(draw, points, scale, color, outline=None):
    coords = [(x * scale, y * scale) for x, y in points]
    draw.polygon(coords, fill=color)
    if outline:
        draw.line(coords + coords[:1], fill=outline, width=max(1, round(.55 * scale)), joint="curve")


def logo(size):
    def paint(draw, scale):
        polygon(draw, [(6, 2), (18, 2), (22, 6), (22, 18), (18, 22), (6, 22), (2, 18), (2, 6)],
                scale, "#1c1536", "#ae92fb")
        for x in (7.6, 10.5, 13.4, 16.3):
            draw.line((x * scale, 7 * scale, (x - 1) * scale, 17 * scale),
                      fill="#f0eaff", width=round(1.45 * scale))
        draw.line((5 * scale, 15.4 * scale, 19 * scale, 8.6 * scale),
                  fill="#b59bff", width=round(1.85 * scale))
    return drawing(size, paint)


def hearthstone(size):
    def paint(draw, scale):
        stone = [(7, 2), (15, 2.4), (20, 5), (22, 12), (19.2, 19.5), (13, 22), (6, 21),
                 (2, 15), (2.8, 8)]
        polygon(draw, stone, scale, "#aea5c4", "#26213c")
        polygon(draw, [(7, 2), (15, 2.4), (20, 5), (17, 6), (8, 5.4), (5, 9), (2.8, 8)],
                scale, "#e4daea")
        polygon(draw, [(20, 5), (22, 12), (19.2, 19.5), (13, 22), (6, 21), (7.5, 17.8),
                       (13.2, 19), (17.5, 16), (19, 11)], scale, "#716689")
        rune = [(15, 7.5), (10.3, 7.4), (7.2, 10.3), (7.6, 15), (10.5, 17), (15, 15.8),
                (16.1, 12.9), (13.6, 11.2), (11, 12.8)]
        for width, color in ((3.3, "#6444a8"), (2.2, "#b08bff"), (1.15, "#fcf1ff")):
            coords = [(x * scale, y * scale) for x, y in rune]
            draw.line(coords, fill=color, width=round(width * scale), joint="curve")
    return drawing(size, paint)


def founder_emblem(size):
    def paint(draw, scale):
        crest = [(12, 1), (21, 5), (21, 15), (18, 19), (12, 23), (6, 19), (3, 15), (3, 5)]
        polygon(draw, crest, scale, "#241a39", "#d6adf8")
        polygon(draw, [(12, 4), (14, 10), (19, 12), (14, 14), (12, 20), (10, 14), (5, 12), (10, 10)],
                scale, "#ad86e8")
        polygon(draw, [(12, 8), (15.6, 12), (12, 16), (8.4, 12)], scale, "#f5e4ff")
    return drawing(size, paint)


# One faceted compass needle across the map pointer, skins and 3D dial.
# In screen coordinates the nose faces up at heading zero and left at 90°.
NEEDLE = [(0, -9.5), (6.8, 7.7), (0, 4), (-6.8, 7.7)]


def needle(size, degrees=0, tilt=1, layer="body", gold=False, width=1, hollow=False):
    angle = math.radians(degrees)
    sine, cosine = math.sin(angle), math.cos(angle)

    def project(vertices, depth=0):
        return [(12 + u * width * cosine + v * sine, 12 + (v * cosine - u * width * sine) * tilt + depth)
                for u, v in vertices]

    def paint(draw, scale):
        nose, right, tail, left = NEEDLE
        if layer == "body":
            if tilt < 1:
                polygon(draw, project(NEEDLE, 1.25), scale, "#39334d", "#0e0b18")
            polygon(draw, project(NEEDLE), scale, "#d9b4ff" if gold else "#eeeaf5", "#140e23")
            polygon(draw, project([nose, right, tail]), scale, "#805839" if gold else "#807595")
            if gold:
                polygon(draw, project([nose, tail, left]), scale, "#ffcc81")
            polygon(draw, project([(0, -5), (2, 2.8), (0, 1.5), (-2, 2.8)]),
                    scale, "#573b28" if gold else "#352846")
            if hollow:
                polygon(draw, project([(0, -6), (4.3, 4.7), (0, 2), (-4.3, 4.7)]), scale, (0, 0, 0, 0))
        elif layer == "edge":
            rim = [(u * 1.08, v * 1.08) for u, v in NEEDLE]
            coords = [(x * scale, y * scale) for x, y in project(rim)]
            draw.line(coords + coords[:1], fill="white", width=round(.5 * scale), joint="curve")
        else:
            polygon(draw, project([(0, -8.5), (0, -5.9), (-3, 1)]),
                    scale, (255, 255, 255, 230 if layer == "facet" else 110))
    return drawing(size, paint)


def needle_sheets():
    body = Image.new("RGBA", (1024, 1024))
    spec = Image.new("RGBA", body.size)
    for frame in range(100):
        xy = (frame % 10 * 102, frame // 10 * 102)
        degrees = frame * 3.6
        body.paste(needle(102, degrees, .83), xy)
        spec.paste(needle(102, degrees, .83, "spec"), xy)
    return body, spec.resize((512, 512), Image.Resampling.LANCZOS)


def write_tga(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path.with_suffix(".tga"), format="TGA", rle=False)


def build_guide():
    guide = ADDON / "Evertally_Guide" / "Media"
    ui_icons = (set(GLYPHS) - NON_GUIDE_UI_GLYPHS) | set(UI_ALIASES)
    for name in sorted(ui_icons):
        if name in {"quest-kill", "quest-loot"}:
            # Nameplates use these uncropped and in full colour over 3D scenery.
            color = "#ffe0a0" if name == "quest-loot" else "#efe7ff"
            icon = glyph(UI_ALIASES[name], 64, color=color, extent=.86, weight=3.2)
            shadow = glyph(UI_ALIASES[name], 64, color="#2a173a", extent=.86, weight=5.5)
            shadow.alpha_composite(icon)
            icon = shadow
        else:
            icon = glyph(UI_ALIASES.get(name, name), 64 if name == "skin-check" else 32)
        write_tga(icon, guide / "UI" / name)
    for name, symbol in MAP_GLYPHS.items():
        foreground = glyph(symbol, 64, weight=2.7, extent=.85)
        # Expand the silhouette, including filled shapes, for contrast on map art.
        background = Image.new("RGBA", foreground.size, "#17131f")
        background.putalpha(foreground.getchannel("A").filter(ImageFilter.MaxFilter(5)))
        background.alpha_composite(foreground)
        write_tga(background, guide / "Map" / ("icon-" + name))

    write_tga(logo(64), guide / "UI" / "logo")
    write_tga(glyph("emblem", 64, weight=1.5), guide / "UI" / "emblem")
    write_tga(glyph("emblem-hot", 64, color=(255, 244, 250, 150)), guide / "UI" / "emblem-hot")
    write_tga(founder_emblem(64), guide / "UI" / "founder-emblem")
    write_tga(hearthstone(64), guide / "UI" / "hearthstone")
    write_tga(needle(128, layer="body"), guide / "Nav" / "arrow")
    write_tga(needle(128, layer="facet"), guide / "Nav" / "arrow-facet")
    glow_alpha = needle(128).getchannel("A").filter(ImageFilter.GaussianBlur(6))
    glow = Image.new("RGBA", glow_alpha.size, "white")
    glow.putalpha(glow_alpha)
    write_tga(glow, guide / "Nav" / "arrow-glow")
    write_tga(needle(128), guide / "UI" / "dart")
    write_tga(needle(128, layer="edge"), guide / "UI" / "dart-edge")
    write_tga(needle(128, gold=True), guide / "UI" / "dart-gold")
    write_tga(glyph("arrival-ring", 128, extent=.85, weight=1.65), guide / "Nav" / "arrived")
    write_tga(glyph("pin", 64), guide / "Nav" / "sparkle")
    body, spec = needle_sheets()
    write_tga(body, guide / "Nav" / "arrow3d")
    write_tga(spec, guide / "Nav" / "arrow3d-spec")

    # The bundled looks carry their own arrows. Keep their different widths
    # while using the same compass profile as the standard arrow.
    for skin, name, width in (("Hairline", "dart", 1.12), ("Waymark", "needle", .62)):
        media = ADDON / ("Evertally_Guide_Skin_" + skin) / "Media"
        if media.is_dir():
            write_tga(needle(128, width=width, hollow=skin == "Hairline"), media / name)
            write_tga(needle(128, layer="edge", width=width), media / (name + "-edge"))


def build():
    core = ADDON / "Evertally" / "Media"
    maps = ADDON / "Evertally_Map" / "Media"
    for name in sorted(CORE_GLYPHS):
        write_tga(glyph(name), core / "Polestar" / name)
    for name, symbol in {"dot": "pin", "goal": "target", "ping": "qol-target", "flag": "flag",
                         "ship": "icon-boat", "zeppelin": "zeppelin"}.items():
        write_tga(glyph(symbol, 64, weight=2.9), maps / name)
    write_tga(needle(64), maps / "arrow")
    for filename, symbol in {"ShapeArrow": "qol-upgrade", "ShapeNext": "skip", "ShapePrev": "previous",
                             "ShapePlay": "play", "ShapePause": "pause", "ShapeNote": "note"}.items():
        write_tga(glyph(symbol), core / filename)
    write_tga(logo(64), core / "Logo")
    build_guide()


def preview(path):
    image = Image.new("RGB", (960, 613), "#11101a")
    draw = ImageDraw.Draw(image)
    fonts = ADDON / "Evertally" / "Media" / "Fonts"
    font = ImageFont.truetype(fonts / "Inter-Regular.ttf", 15)
    title = ImageFont.truetype(fonts / "Inter-SemiBold.ttf", 29)
    draw.text((40, 32), "EVERTALLY  /  New Icons", fill="#eee8f9", font=title)
    guide = ADDON / "Evertally_Guide" / "Media"
    headings = [
        ("INTERFACE", 98, ["house", "journal", "hourglass", "icon-craft", "icon-learn", "icon-dungeon",
                           "recipes", "star", "route", "icon-talk", "people", "icon-achieve", "plug"]),
        ("GUIDE ACTIONS & STEPS", 198, ["skip", "icon-goto", "bug", "search", "icon-accept", "icon-complete", "icon-turnin",
                              "icon-kill", "icon-collect", "icon-hearth", "icon-sethome", "icon-fly", "icon-repair"]),
        ("WORLD MAP", 298, ["inn", "flightmaster", "mailbox", "bank", "vendor", "trainer-class", "rare",
                                "dungeon", "boat", "zeppelin", "tram", "portal", "treasure"]),
    ]
    for row, (heading, top, names) in enumerate(headings):
        draw.text((42, top), heading, fill="#bda5ff", font=font)
        for i, name in enumerate(names):
            map_icon = row == 2
            asset = guide / ("Map" if map_icon else "UI") / (("icon-" if map_icon else "") + name + ".tga")
            tex = Image.open(asset).convert("RGBA").resize((26, 26), Image.Resampling.LANCZOS)
            x = 40 + i * 66
            draw.rounded_rectangle((x, top + 28, x + 52, top + 80), 10, fill="#201d30", outline="#37314a")
            tint = Image.new("RGB", tex.size, ("#d4c4ff" if i % 3 else "#f0e8fa") if not map_icon else
                             ("#99edc6", "#97d8ff", "#f6ce92")[i % 3])
            image.paste(ImageChops.multiply(tint, tex.convert("RGB")), (x + 13, top + 41), tex.getchannel("A"))
    draw.text((42, 398), "NAVIGATION", fill="#bda5ff", font=font)
    draw.text((590, 398), "HEARTHSTONE", fill="#bda5ff", font=font)
    for i, degrees in enumerate((0, 35, 90, 180, 270)):
        tex = needle(88, degrees, .83)
        tint = Image.new("RGB", tex.size, "#a7efc7" if degrees == 180 else "#bc9cff")
        image.paste(ImageChops.multiply(tex.convert("RGB"), tint), (38 + i * 94, 427), tex.getchannel("A"))
    stone = hearthstone(78)
    image.paste(stone, (592, 434), stone)
    stone = hearthstone(32)
    image.paste(stone, (694, 457), stone)
    draw.rounded_rectangle((40, 544, 884, 586), 8, fill="#201d30", outline="#37314a")
    draw.text((56, 556), "14 px", fill="#958ca7", font=font)
    x = 126
    for name, label in (("skip", "Skip"), ("icon-goto", ""), ("bug", ""), ("search", ""),
                        ("logo", "Evertally"), ("guides", "Guides"), ("database", "Database"), ("rare", "Rare Mobs")):
        tex = Image.open(guide / "UI" / (name + ".tga")).convert("RGBA").resize((14, 14), Image.Resampling.LANCZOS)
        tint = Image.new("RGB", tex.size, "#d2c5ee")
        art = tex.convert("RGB") if name == "logo" else ImageChops.multiply(tint, tex.convert("RGB"))
        image.paste(art, (x, 558), tex.getchannel("A"))
        if label:
            draw.text((x + 20, 556), label, fill="#dfd8ed", font=font)
        x += 32 + (20 + round(font.getlength(label)) if label else 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path, help="also render a PNG showing a sample of the textures")
    args = parser.parse_args()
    build()
    if args.preview:
        preview(args.preview)
