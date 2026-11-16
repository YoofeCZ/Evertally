"""Draws the white shape textures Evertally tints with its theme colours (Media/Shape*.tga): a rounded rectangle, its
outline, a pill and a dot. Uncompressed 32-bit TGA, anti-aliased by 8x8 supersampling. Run again after changing a radius."""
from pathlib import Path
import struct

MEDIA = Path(__file__).resolve().parents[1] / "addon" / "Evertally" / "Media"
SS = 8


def coverage(width, height, inside):
    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            hit = 0
            for sy in range(SS):
                for sx in range(SS):
                    if inside(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS):
                        hit += 1
            row.append(round(255 * hit / (SS * SS)))
        rows.append(row)
    return rows


def rounded(width, height, radius, inset=0.0):
    def inside(px, py):
        left, top, right, bottom = inset, inset, width - inset, height - inset
        r = max(0.0, radius - inset)
        cx = min(max(px, left + r), right - r)
        cy = min(max(py, top + r), bottom - r)
        if not (left <= px <= right and top <= py <= bottom):
            return False
        return (px - cx) ** 2 + (py - cy) ** 2 <= r * r
    return inside


def arrow(px, py):
    """An upward arrow: a triangle head over a short stem, with a dark rim drawn by the tint's contrast."""
    if 2.5 <= py <= 17.5:
        half = (py - 2.5) / 15 * 14
        return abs(px - 16) <= half
    return 17.5 < py <= 29.5 and 10.5 <= px <= 21.5


def note(px, py):
    """An eighth note: a tilted oval head, a stem and a flag."""
    dx, dy = px - 11, py - 24
    head = (dx * 0.8 + dy * 0.6) ** 2 / 36 + (-dx * 0.6 + dy * 0.8) ** 2 / 16 <= 1
    stem = 15.5 <= px <= 18 and 4 <= py <= 24
    flag = 18 <= px <= 26 and 4 <= py <= 14 and (py - 4) >= (px - 18) * 0.55 and (py - 4) <= (px - 18) * 0.55 + 5
    return head or stem or flag


def triangle(px, py, left, right, top, bottom):
    """A triangle pointing right: its tip at (right, middle)."""
    if not (left <= px <= right):
        return False
    half = (bottom - top) / 2 * (right - px) / (right - left)
    middle = (top + bottom) / 2
    return middle - half <= py <= middle + half


def play(px, py):
    return triangle(px, py, 9, 26, 5, 27)


def pause(px, py):
    return 5 <= py <= 27 and (8 <= px <= 13.5 or 18.5 <= px <= 24)


def skip_next(px, py):
    return triangle(px, py, 5, 22, 6, 26) or (22 <= px <= 26 and 6 <= py <= 26)


def write(name, width, height, alpha):
    # bottom-left origin and 8 alpha bits, the same header as Logo.tga, which the game is known to load
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x08)
    body = bytearray()
    for row in reversed(alpha):
        for a in row:
            body += bytes((255, 255, 255, a))
    (MEDIA / name).write_bytes(header + bytes(body))


def main():
    write("ShapeRound.tga", 64, 64, coverage(64, 64, rounded(64, 64, 7)))
    outer, inner = rounded(64, 64, 7), rounded(64, 64, 7, inset=1.25)
    write("ShapeRing.tga", 64, 64, coverage(64, 64, lambda x, y: outer(x, y) and not inner(x, y)))
    write("ShapePill.tga", 64, 32, coverage(64, 32, rounded(64, 32, 16)))
    write("ShapeDot.tga", 32, 32, coverage(32, 32, rounded(32, 32, 16)))
    write("ShapeArrow.tga", 32, 32, coverage(32, 32, arrow))
    write("ShapeNote.tga", 32, 32, coverage(32, 32, note))
    write("ShapePlay.tga", 32, 32, coverage(32, 32, play))
    write("ShapePause.tga", 32, 32, coverage(32, 32, pause))
    write("ShapeNext.tga", 32, 32, coverage(32, 32, skip_next))
    write("ShapePrev.tga", 32, 32, coverage(32, 32, lambda x, y: skip_next(32 - x, y)))
    print("written to", MEDIA)


if __name__ == "__main__":
    main()
