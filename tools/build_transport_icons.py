"""Draws the boat and zeppelin pins of the map (addon/Evertally_Map/Media/ship.tga, zeppelin.tga): a round badge in the
style of the game's tracking icons (gold rim, textured coloured face, an embossed silhouette with shading and a shadow).

    python -I tools/build_transport_icons.py

Silhouettes (CC BY 3.0, credited in THIRD_PARTY.md and addon/Evertally_Map/NOTICE.txt, never in the game's UI):
  shared/sources/game-icons/delapouite-sailboat.svg  "Sailboat" by Delapouite, https://game-icons.net
  shared/sources/game-icons/skoll-zeppelin.svg       "Zeppelin" by Skoll, https://game-icons.net
Changed: only the outline shape is used; the badge, colours, texture and shading are drawn here. Chrome renders the SVG (no
SVG library is needed), Pillow draws the rest. The colours are in the picture, so the game shows the texture untinted.
"""
from __future__ import annotations

import math
import random
import struct
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "shared" / "sources" / "game-icons"
OUT = ROOT / "addon" / "Evertally_Map" / "Media"
# name: (silhouette, face colour light, face colour dark)
ICONS = {
    "ship": ("delapouite-sailboat.svg", (64, 132, 196), (14, 38, 78)),
    "zeppelin": ("skoll-zeppelin.svg", (196, 112, 44), (78, 30, 12)),
}
CHROME = [Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
          Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")]
S = 512  # drawn big, scaled to 64 at the end


def render(svg: Path, png: Path) -> None:
    browser = next(p for p in CHROME if p.is_file())
    subprocess.run([str(browser), "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--window-size={S},{S}",
                    "--default-background-color=00000000", f"--screenshot={png}", svg.resolve().as_uri()],
                   check=True, capture_output=True, timeout=60)


def write_tga(img: Image.Image, path: Path) -> None:
    # 32-bit, bottom-left origin, 8 alpha bits: the header the Forever client loads (see build_map_icons.py)
    w, h = img.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    px = img.load()
    body = bytearray()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b, a = px[x, y]
            body += struct.pack("BBBB", b, g, r, a)
    path.write_bytes(header + bytes(body))


def radial(size, inner, outer, centre=(0.42, 0.36)):
    img = Image.new("RGB", (size, size))
    px = img.load()
    cx, cy = centre[0] * size, centre[1] * size
    far = size * 0.78
    for y in range(size):
        for x in range(size):
            t = min(1.0, math.hypot(x - cx, y - cy) / far)
            px[x, y] = tuple(int(inner[i] + (outer[i] - inner[i]) * t) for i in range(3))
    return img


def noise(size, seed, strength=22, blur=1.6):
    rnd = random.Random(seed)
    img = Image.new("L", (size // 4, size // 4))
    img.putdata([128 + rnd.randint(-strength, strength) for _ in range(img.width * img.height)])
    return img.resize((size, size), Image.BICUBIC).filter(ImageFilter.GaussianBlur(blur))


def circle_mask(size, r0, r1=None):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    c = size / 2
    d.ellipse((c - r0, c - r0, c + r0, c + r0), fill=255)
    if r1:
        d.ellipse((c - r1, c - r1, c + r1, c + r1), fill=0)
    return m


def badge(silhouette: Image.Image, light, dark, seed) -> Image.Image:
    size = S
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # soft shadow under the badge
    shadow = circle_mask(size, size * 0.47).filter(ImageFilter.GaussianBlur(10))
    out.paste(Image.new("RGBA", (size, size), (0, 0, 0, 150)), (6, 10), shadow)
    # gold rim: a metallic gradient ring with a darker inner edge
    rim = radial(size, (255, 226, 140), (120, 74, 20), centre=(0.35, 0.28))
    rim = ImageChops.multiply(rim, Image.merge("RGB", [noise(size, seed + 1, 14)] * 3).point(lambda v: min(255, v + 127)))
    out.paste(rim, (0, 0), circle_mask(size, size * 0.46))
    out.paste((60, 36, 10), (0, 0), circle_mask(size, size * 0.385))
    # the face: coloured radial light with a cloudy texture, darker towards the rim
    face = radial(size, light, dark)
    tex = noise(size, seed, 30, 2.4)
    face = ImageChops.overlay(face, Image.merge("RGB", [tex] * 3))
    out.paste(face, (0, 0), circle_mask(size, size * 0.37))
    # inner shadow at the top of the face (the rim stands above it)
    inner = Image.new("L", (size, size), 0)
    ImageDraw.Draw(inner).ellipse((size * 0.13, size * 0.17, size * 0.87, size * 0.91), fill=255)
    inner = ImageChops.subtract(circle_mask(size, size * 0.37), inner).filter(ImageFilter.GaussianBlur(8))
    out.paste(Image.new("RGBA", (size, size), (0, 0, 0, 170)), (0, 0), inner)
    # the silhouette, made to sit inside the face
    sil = silhouette.resize((int(size * 0.64), int(size * 0.64)), Image.LANCZOS)
    a = Image.new("L", (size, size), 0)
    a.paste(sil, ((size - sil.width) // 2, (size - sil.height) // 2 + 4))
    # its shadow, its dark edge, then a shaded fill (ivory at the top, warm grey at the bottom) and a light top edge
    out.paste(Image.new("RGBA", (size, size), (0, 0, 0, 190)), (5, 9), a.filter(ImageFilter.GaussianBlur(5)))
    out.paste((22, 16, 10), (0, 0), a.filter(ImageFilter.MaxFilter(9)))
    fill = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(fill)
    for y in range(size):
        t = y / size
        d.line([(0, y), (size, y)], fill=(int(255 - 70 * t), int(248 - 80 * t), int(228 - 100 * t)))
    fill = ImageChops.multiply(fill, Image.merge("RGB", [noise(size, seed + 2, 10)] * 3).point(lambda v: min(255, v + 120)))
    out.paste(fill, (0, 0), a)
    edge = ImageChops.subtract(a, ImageChops.offset(a, 0, 5)).filter(ImageFilter.GaussianBlur(1))
    out.paste(Image.new("RGBA", (size, size), (255, 255, 255, 200)), (0, 0), edge)
    # a gloss over the upper half of the badge
    gloss = Image.new("L", (size, size), 0)
    ImageDraw.Draw(gloss).ellipse((size * 0.2, size * 0.1, size * 0.8, size * 0.5), fill=46)
    gloss = ImageChops.multiply(gloss.filter(ImageFilter.GaussianBlur(18)), circle_mask(size, size * 0.37))
    out.paste(Image.new("RGBA", (size, size), (255, 255, 255, 255)), (0, 0), gloss)
    return out.resize((64, 64), Image.LANCZOS)


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        for i, (name, (file, light, dark)) in enumerate(ICONS.items()):
            png = Path(tmp) / f"{name}.png"
            render(SOURCES / file, png)
            silhouette = Image.open(png).convert("RGBA").getchannel("A")
            write_tga(badge(silhouette, light, dark, 7 + i * 31), OUT / f"{name}.tga")
            print(f"{name}.tga from {file}")


if __name__ == "__main__":
    main()
