"""Draw the Evertally logo (tally marks in a roundel) and write every icon the project needs.

Outputs:
  addon/Evertally/Media/Logo.tga        addon list / minimap icon (64x64 TGA)
  desktop/src-tauri/icons/icon.ico      Windows app icon (16..256 px)
  desktop/src-tauri/icons/*.png         bundle icons
No third-party packages: shapes are signed-distance functions rasterised with 4x4 supersampling.
"""
from pathlib import Path
import math
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
SS = 4


def seg(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def rounded_box(px, py, center=32.0, half=32.0, radius=14.0):
    qx, qy = abs(px - center) - (half - radius), abs(py - center) - (half - radius)
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - radius


# Shapes in a 64-unit design space (same geometry as platform/public/favicon.svg).
LAYERS = [
    ((0x13, 0x11, 0x1C), 1.0, lambda x, y: rounded_box(x, y)),
    ((0xF7, 0xF7, 0xF8), 0.35, lambda x, y: abs(math.hypot(x - 32, y - 32) - 24) - 1.0),
    ((0xF7, 0xF7, 0xF8), 1.0, lambda x, y: min(seg(x, y, lx, 20, lx, 44) for lx in (22, 29, 36, 43)) - 1.6),
    ((0xA7, 0x8B, 0xFA), 1.0, lambda x, y: seg(x, y, 17, 39, 48, 24) - 1.8),
]


def render(size):
    """Return rows of straight-alpha RGBA pixels, top row first."""
    scale = 64.0 / size
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            r = g = b = a = 0.0
            for color, opacity, sdf in LAYERS:
                hits = 0
                for sy in range(SS):
                    for sx in range(SS):
                        if sdf((x + (sx + 0.5) / SS) * scale, (y + (sy + 0.5) / SS) * scale) <= 0:
                            hits += 1
                cover = hits / (SS * SS) * opacity
                out = cover + a * (1 - cover)
                if out > 0:
                    r = (color[0] * cover + r * a * (1 - cover)) / out
                    g = (color[1] * cover + g * a * (1 - cover)) / out
                    b = (color[2] * cover + b * a * (1 - cover)) / out
                a = out
            row.append((round(r), round(g), round(b), round(a * 255)))
        rows.append(row)
    return rows


def png(rows):
    size = len(rows)
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def tga(rows):
    size = len(rows)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)  # bottom-left origin
    data = b"".join(bytes((b, g, r, a)) for row in reversed(rows) for (r, g, b, a) in row)
    return header + data


def ico(images):
    """ICO container with PNG-compressed entries (supported since Windows Vista)."""
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries, blobs = b"", b""
    for size, data in images:
        dim = 0 if size >= 256 else size
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    return header + entries + blobs


def main():
    media = ROOT / "addon" / "Evertally" / "Media"
    media.mkdir(parents=True, exist_ok=True)
    (media / "Logo.tga").write_bytes(tga(render(64)))

    icons = ROOT / "desktop" / "src-tauri" / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    sizes = [16, 24, 32, 48, 64, 128, 256]
    rendered = {size: png(render(size)) for size in sizes}
    (icons / "icon.ico").write_bytes(ico([(s, rendered[s]) for s in sizes]))
    (icons / "32x32.png").write_bytes(rendered[32])
    (icons / "128x128.png").write_bytes(rendered[128])
    (icons / "128x128@2x.png").write_bytes(rendered[256])
    (icons / "icon.png").write_bytes(rendered[256])
    print("icons written:", ", ".join(str(p.relative_to(ROOT)) for p in [media / "Logo.tga", *sorted(icons.iterdir())]))


if __name__ == "__main__":
    main()
