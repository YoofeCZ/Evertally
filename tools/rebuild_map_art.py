"""Re-saves the web copies of the zone, continent and world maps without JPEG damage.

build_reference_data.py stores every map as JPEG (quality 88); at the deepest zoom the 8x8 blocks and ringing show. This script
composes the same tiles and explored-area pieces from the installed client (CASC) and writes lossless WebP next to the JPEGs in
platform/public/media/maps, then points the web manifest at them (the shared/ copies the desktop app reads are left alone).
Run after build_reference_data.py:  python tools/rebuild_map_art.py
"""
from __future__ import annotations

import csv
import importlib.util
import io
import json
import math
import re
import sys
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "shared" / "sources"
PUBLIC = ROOT / "platform" / "public" / "media" / "maps"


def load(name: str, file: Path):
    spec = importlib.util.spec_from_file_location(name, file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    world = load("uimap", SOURCE / "tools-uimap.py").World(str(SOURCE))
    casc = load("casc", SOURCE / "tools-casc-casc.py").Casc(r"D:\World of Warcraft", "wowf")
    tiles = list(csv.DictReader((SOURCE / "UiMapArtTile.csv").open(encoding="utf8")))
    with zipfile.ZipFile(SOURCE / "OpenMap-v0.8.2-forever.zip") as z:
        reveal = z.read("OpenMap/Data/Forever/Reveal.lua").decode()
    overlays = {int(k): re.findall(r'\["([\d:]+)"\]\s*=\s*"([\d, ]+)"', body) for k, body in re.findall(r"^\s*\[(\d+)\]\s*=\s*\{(.*)\},", reveal, re.M)}
    manifest_path = PUBLIC / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf8"))
    for entry in manifest["maps"]:
        mid = entry["uiMapIds"][0]
        art, width, height, tw, th = world.art(mid)
        image = Image.new("RGBA", (width, height))
        for row in (r for r in tiles if int(r["UiMapArtID"]) == art and r["LayerIndex"] == "0"):
            tile = Image.open(io.BytesIO(casc.read(int(row["FileDataID"])))).convert("RGBA")
            image.alpha_composite(tile, (int(row["ColIndex"]) * tw, int(row["RowIndex"]) * th))
        for geometry, ids in overlays.get(art, []):
            ow, oh, x, y = map(int, geometry.split(":"))
            cols = math.ceil(ow / 256)
            for index, file_id in enumerate(re.findall(r"\d+", ids)):
                tile = Image.open(io.BytesIO(casc.read(int(file_id)))).convert("RGBA")
                sx, sy = (index % cols) * 256, (index // cols) * 256
                image.alpha_composite(tile.crop((0, 0, min(256, ow - sx), min(256, oh - sy))), (x + sx, y + sy))
        target = PUBLIC / f"{entry['key']}.webp"
        image.convert("RGB").save(target, "WEBP", lossless=True, method=5)
        entry["image"] = f"/media/maps/{entry['key']}.webp"
        print(f"{entry['key']:26s} {target.stat().st_size // 1024:5d} KB", flush=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, separators=(",", ":")), encoding="utf8")
    for old in PUBLIC.glob("*.jpg"):
        old.unlink()
    print("done:", sum(p.stat().st_size for p in PUBLIC.glob("*.webp")) // 1024 // 1024, "MB")


if __name__ == "__main__":
    main()
