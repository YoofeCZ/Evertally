"""Decode the walkable terrain of the continents from the ground navigation data bundled with GatherLite and write a compact
walk mask for the website, so routes can follow real ground instead of straight lines.

Source: GatherLite/plugins/routes/navigation/vendor/Nav (Shortest Path Forever, GPL-3.0-or-later; its own bake of the client's
terrain). Only the per-cell value is used here: 0 blocked, 1 ground, 2 water. Cliff steps and the floors of tunnels and cities
are not modelled; the mask is a map of where you can stand, and validation compares it with the walking distances SPF baked.

    python tools/build_walkmask.py [path-to-Nav-folder] [--preview]

Writes platform/public/media/world/walk.bin (and, with --preview, PNGs in the scratch folder given by EVERTALLY_SCRATCH).
Format (little endian): "EVWM" u8 version u8 maps; per map: i16 id, f32 x0, f32 y0 (yards of cell 0's corner), f32 cell (yards),
u16 nx, u16 ny, u32 length, then `length` bytes of deflate-compressed rows: nx rows of ny bytes, value 0..2, x major (x = north,
y = west, as in the game's UnitPosition), downsampled by FACTOR from the 8-yard grid.
"""
from __future__ import annotations

import base64
import os
import re
import struct
import sys
import zlib
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_NAV = Path(r"D:\World of Warcraft\_forever_\Interface\AddOns\GatherLite\plugins\routes\navigation\vendor\Nav")
OUT = ROOT / "platform" / "public" / "media" / "world" / "walk.bin"
TILE = 1600 / 3
ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
LOOKUP = np.full(256, 255, dtype=np.uint8)
for i, ch in enumerate(ALPHA):
    LOOKUP[ord(ch)] = i
MAPS = (0, 1, 2991)
FACTOR = 2  # 8 yd -> 16 yd cells


def load(nav: Path, map_id: int):
    meta, grids = None, {}
    for f in sorted(nav.glob(f"Nav{map_id}*.lua")):
        if not re.fullmatch(rf"Nav{map_id}(_\d+)?\.lua", f.name):
            continue
        text = f.read_text(encoding="utf8")
        m = re.search(rf"GatherLiteGroundPathData\[{map_id}\] = \{{(.*?)\n\}}", text, re.S)
        if m:
            meta = {k: float(v) for k, v in re.findall(r"^\s*(\w+) = (-?[\d.]+),", m.group(1), re.M)}
        for k, blocks in re.findall(r"data\.packed\.grid\[(\d+)\] = \{(.*?)\}\n", text, re.S):
            parts = re.findall(r'"([^"]*)"', blocks)
            grids[int(k) - 1] = b"".join(zlib.decompress(base64.b64decode(p)) for p in parts)
    if meta is None:
        raise SystemExit(f"no header found for map {map_id}")
    return meta, grids


def decode_cluster(raw: bytes, cells: int) -> np.ndarray:
    """One cluster's cell values as a (cells, cells) array indexed [tx (x, north), ty (y, west)]."""
    sym = LOOKUP[np.frombuffer(raw, dtype=np.uint8)]
    if (sym == 255).any():
        raise ValueError("unexpected character in a grid")
    start = sym < 48
    counts = np.where(start, 1, sym.astype(np.int64) - 47)
    last = np.maximum.accumulate(np.where(start, np.arange(len(sym)), 0))
    values = (sym[last] // 16).astype(np.uint8)
    flat = np.repeat(values, counts)
    if len(flat) != cells * cells:
        raise ValueError(f"a cluster decoded to {len(flat)} cells, expected {cells * cells}")
    return flat.reshape(cells, cells)


def build_map(nav: Path, map_id: int):
    meta, grids = load(nav, map_id)
    C, nx, ny = int(meta["cells"]), int(meta["nx"]), int(meta["ny"])
    gx, gy = nx * C, ny * C
    fine = np.zeros((gx, gy), dtype=np.uint8)
    for k, raw in grids.items():
        kx, ky = divmod(k, ny)
        fine[kx * C:(kx + 1) * C, ky * C:(ky + 1) * C] = decode_cluster(raw, C)
    x0, y0, cell = meta["cx0"] * TILE, meta["cy0"] * TILE, TILE / C
    return fine, x0, y0, cell


def downsample(fine: np.ndarray) -> np.ndarray:
    """FACTOR x FACTOR blocks -> one cell: blocked only when every fine cell is, water only when no ground is in it."""
    h = fine.shape[0] // FACTOR * FACTOR
    w = fine.shape[1] // FACTOR * FACTOR
    blocks = fine[:h, :w].reshape(h // FACTOR, FACTOR, w // FACTOR, FACTOR).transpose(0, 2, 1, 3).reshape(h // FACTOR, w // FACTOR, FACTOR * FACTOR)
    has_ground = (blocks == 1).any(axis=2)
    has_water = (blocks == 2).any(axis=2)
    out = np.zeros(has_ground.shape, dtype=np.uint8)
    out[has_water] = 2
    out[has_ground] = 1
    return out


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    nav = Path(args[0]) if args else DEFAULT_NAV
    preview = "--preview" in sys.argv
    scratch = Path(os.environ.get("EVERTALLY_SCRATCH", ROOT / "output"))
    payload = bytearray(b"EVWM" + struct.pack("<BB", 1, len(MAPS)))
    for map_id in MAPS:
        fine, x0, y0, cell = build_map(nav, map_id)
        coarse = downsample(fine)
        raw = coarse.tobytes()
        packed = zlib.compress(raw, 9)
        payload += struct.pack("<hfffHHI", map_id, x0, y0, cell * FACTOR, coarse.shape[0], coarse.shape[1], len(packed)) + packed
        share = {v: float((coarse == v).mean()) for v in (0, 1, 2)}
        print(f"map {map_id}: {fine.shape[1]}x{fine.shape[0]} fine cells -> {coarse.shape[1]}x{coarse.shape[0]} of {cell * FACTOR:.1f} yd; "
              f"blocked {share[0]:.0%} ground {share[1]:.0%} water {share[2]:.0%}; {len(packed) / 1024:.0f} KiB packed")
        if preview:
            from PIL import Image
            colors = np.array([[10, 10, 14], [88, 140, 84], [50, 90, 160]], dtype=np.uint8)
            picture = colors[coarse[::-1, ::-1]]  # north up (x grows north), west on the left (y grows west)
            scratch.mkdir(parents=True, exist_ok=True)
            Image.fromarray(picture).save(scratch / f"walk-{map_id}.png")
    OUT.write_bytes(bytes(payload))
    print(f"{OUT.relative_to(ROOT)}: {len(payload) / 1024:.0f} KiB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
