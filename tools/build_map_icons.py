"""Draw the small white icons of the in-game map pins as TGA files (tinted in the game with SetVertexColor).

    python tools/build_map_icons.py

Uncompressed 32-bit TGA, 64x64, origin bottom-left with 8 alpha bits (the same header as the icons GatherLite ships, which
the Forever client loads). Only original shapes drawn here; nothing is taken from the game or other add-ons.
"""
from __future__ import annotations

import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "addon" / "Evertally_Map" / "Media"
SIZE = 64
SS = 4  # supersampling for smooth edges


def render(shape) -> list[list[tuple[int, int, int, int]]]:
    rows = []
    for py in range(SIZE):
        row = []
        for px in range(SIZE):
            hits = 0
            ring = 0
            for sy in range(SS):
                for sx in range(SS):
                    x = (px + (sx + 0.5) / SS) / SIZE * 2 - 1
                    y = 1 - (py + (sy + 0.5) / SS) / SIZE * 2
                    kind = shape(x, y)
                    if kind == 1:
                        hits += 1
                    elif kind == 2:
                        ring += 1
            total = SS * SS
            alpha = (hits + ring) / total
            if alpha == 0:
                row.append((0, 0, 0, 0))
            else:
                # the ring is dark so every pin reads on any map; the body is white and gets tinted
                body = hits / (hits + ring)
                shade = int(255 * body)
                row.append((shade, shade, shade, int(255 * alpha)))
        rows.append(row)
    return rows


def dot(x, y):
    d = math.hypot(x, y)
    return 1 if d <= 0.62 else 2 if d <= 0.86 else 0


def arrow(x, y):
    # an arrow pointing up: a triangle head over a short shaft, with a dark outline
    def inside(grow):
        head = -0.05 - grow <= y <= 0.9 + grow and abs(x) <= (0.9 + grow - y) * 0.62 + grow * 0.2 and y >= -0.05 - grow
        shaft = -0.82 - grow <= y <= -0.02 + grow and abs(x) <= 0.2 + grow
        return head or shaft
    return 1 if inside(0) else 2 if inside(0.1) else 0


def flag(x, y):
    # a pole with a triangular pennant: vertices (-0.45, 0.9), (0.85, 0.45), (-0.45, 0.0)
    def inside(grow):
        pole = -0.9 - grow <= y <= 0.9 + grow and -0.6 - grow <= x <= -0.45 + grow
        slope = 0.45 / 1.3
        pennant = -0.45 - grow <= x <= 0.85 + grow and (x + 0.45) * slope - grow <= y <= 0.9 - (x + 0.45) * slope + grow
        return pole or pennant
    return 1 if inside(0) else 2 if inside(0.09) else 0


def ping(x, y):
    # concentric rings: an alert ripple
    d = math.hypot(x, y)
    if 0.0 <= d <= 0.22:
        return 1
    if 0.22 < d <= 0.3:
        return 2
    if 0.5 <= d <= 0.66:
        return 1
    if 0.44 <= d < 0.5 or 0.66 < d <= 0.72:
        return 2
    if 0.84 <= d <= 0.92:
        return 1
    return 0


def goal(x, y):
    # a bullseye for the place navigation points at: bold ring, gap, centre dot, dark outline on both sides of each
    d = math.hypot(x, y)
    if d <= 0.24:
        return 1
    if d <= 0.33:
        return 2
    if 0.58 <= d <= 0.8:
        return 1
    if 0.5 <= d < 0.58 or 0.8 < d <= 0.9:
        return 2
    return 0


def write(name: str, shape) -> None:
    rows = render(shape)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x08)
    body = bytearray()
    for row in reversed(rows):  # bottom-left origin: the last picture row comes first
        for r, g, b, a in row:
            body += struct.pack("BBBB", b, g, r, a)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_bytes(header + bytes(body))
    print(f"{name}: {len(header) + len(body)} bytes")


if __name__ == "__main__":
    for name, shape in (("dot.tga", dot), ("arrow.tga", arrow), ("flag.tga", flag), ("ping.tga", ping), ("goal.tga", goal)):
        write(name, shape)
