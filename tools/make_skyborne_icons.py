"""Draw race emblems for the two Skyborne races of WoW Forever (race ids 95 and 96).

The website shows a 64x64 race portrait next to each character. The project has the classic
races only, and the game's own Skyborne portraits are not available as files, so these are
Evertally's own simple emblems: a wing in the faction colour. They are not game artwork.

Outputs:
  platform/public/media/identity/races/95.png   High Order Skyborne (Alliance)
  platform/public/media/identity/races/96.png   Windshaper Skyborne (Horde)
"""
from pathlib import Path

import math

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "platform" / "public" / "media" / "identity" / "races"
SIZE = 64
SCALE = 4  # draw large, then shrink for smooth edges

RACES = {
    95: ((24, 48, 96), (61, 127, 224), (226, 236, 255)),   # Alliance blue
    96: ((80, 20, 18), (210, 58, 47), (255, 232, 214)),    # Horde red
}


def emblem(dark, light, wing):
    s = SIZE * SCALE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    # vertical gradient background in the faction colour
    grad = Image.new("RGBA", (s, s))
    px = grad.load()
    for y in range(s):
        t = y / (s - 1)
        c = tuple(int(light[i] * (1 - t) * 0.75 + dark[i] * (t * 0.9 + 0.25 * (1 - t))) for i in range(3))
        for x in range(s):
            px[x, y] = (*c, 255)
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=10 * SCALE, fill=255)
    img.paste(grad, (0, 0), mask)

    # a wing: six feathers fanning up and to the right from the lower left
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    base = (15 * SCALE, 50 * SCALE)
    feathers = [(108, 30), (90, 38), (72, 42), (54, 42), (36, 38), (18, 30)]  # (angle from +x, length)
    for angle, length in feathers:
        a = math.radians(angle)
        tip = (base[0] + math.cos(a) * length * SCALE, base[1] - math.sin(a) * length * SCALE)
        nx, ny = -math.sin(a), -math.cos(a)  # perpendicular, screen coordinates
        w = 5.5 * SCALE
        mid = (base[0] + math.cos(a) * length * SCALE * 0.55, base[1] - math.sin(a) * length * SCALE * 0.55)
        d.polygon([base, (mid[0] + nx * w, mid[1] + ny * w), tip, (mid[0] - nx * w * 0.35, mid[1] - ny * w * 0.35)], fill=(*wing, 255))
    # the wing's shoulder
    d.ellipse([base[0] - 6 * SCALE, base[1] - 6 * SCALE, base[0] + 6 * SCALE, base[1] + 6 * SCALE], fill=(*wing, 255))
    shadow = layer.split()[3].filter(ImageFilter.GaussianBlur(3 * SCALE))
    dark_layer = Image.new("RGBA", (s, s), (0, 0, 0, 150))
    img.paste(dark_layer, (2 * SCALE, 3 * SCALE), Image.composite(shadow, Image.new("L", (s, s), 0), mask))
    img.alpha_composite(layer)
    # thin inner frame
    ImageDraw.Draw(img).rounded_rectangle([SCALE, SCALE, s - 1 - SCALE, s - 1 - SCALE], radius=9 * SCALE,
                                          outline=(255, 255, 255, 60), width=SCALE)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for race, colours in RACES.items():
        path = OUT / f"{race}.png"
        emblem(*colours).save(path)
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
