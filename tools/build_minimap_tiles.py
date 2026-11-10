"""The game's own minimap, tile by tile, for the deepest zoom of the web map (terrain close up, as OpenMap blends it in).

Tile file IDs come from OpenMap's Minimap table (MIT): [continent][col * 64 + row] = FileDataID, one 533.33-yard tile each
(col runs east, row south). The textures are read from the installed Forever client (CASC) and saved as WebP in
platform/public/media/world/minimap/<continent>/<col>_<row>.webp, with minimap.json describing them.
Run after build_map_data.py:  python tools/build_minimap_tiles.py
"""
from __future__ import annotations

import importlib.util
import io
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_map_data as maps  # noqa: E402

ROOT = maps.ROOT
OUT = ROOT / "platform" / "public" / "media" / "world" / "minimap"
SIZE = 512
QUALITY = 90


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    tiles = maps._lua(maps.SRC / "openmap" / "Minimap.lua", "MapMinimap")
    spec = importlib.util.spec_from_file_location("casc", ROOT / "shared" / "sources" / "tools-casc-casc.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    client = module.Casc(r"D:\World of Warcraft", "wowf")
    world = maps._uimap()
    manifest: dict = {"schema": 1, "size": SIZE, "yardsPerTile": 1600 / 3, "tiles": {}, "yards": {}}
    for continent, entries in tiles.items():
        folder = OUT / continent
        folder.mkdir(parents=True, exist_ok=True)
        # u = au + bu * y (world Y), v = av + bv * x (world X); the first region places the whole continent
        x0, x1, y0, y1, au, bu, av, bv = world.yards(int(continent))[0]
        manifest["yards"][continent] = [au, bu, av, bv]
        done = []
        for key, file_id in sorted(entries.items(), key=lambda kv: int(kv[0])):
            col, row = divmod(int(key), 64)
            path = folder / f"{col}_{row}.webp"
            if not path.exists():
                try:
                    image = Image.open(io.BytesIO(client.read(int(file_id)))).convert("RGB")
                except (KeyError, OSError, ValueError) as error:
                    print("skip", continent, col, row, type(error).__name__)
                    continue
                if image.size != (SIZE, SIZE):
                    image = image.resize((SIZE, SIZE), Image.LANCZOS)
                image.save(path, "WEBP", quality=QUALITY, method=4)
            done.append([col, row])
        manifest["tiles"][continent] = done
        print(f"continent {continent}: {len(done)} tiles", flush=True)
    (OUT.parent / "minimap.json").write_text(json.dumps(manifest, separators=(",", ":")), encoding="utf8")
    total = sum(p.stat().st_size for p in OUT.rglob("*.webp"))
    print(f"{total / 1024 / 1024:.0f} MB")


if __name__ == "__main__":
    main()
