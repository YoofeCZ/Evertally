"""Blizzard's own map of each dungeon/raid floor, read from the installed Forever client (CASC).

Tiles come from OpenMap's DungeonMaps table (MIT, floor tile FileDataIDs, 4 x 3 tiles of 256 px, the picture is
the top-left 1002 x 668 of the 1024 x 768 canvas). Output: platform/public/media/world/floors/<mapID>-<n>.webp
and shared/assets/world/floors.json (floors per instance map + which of our dungeon keys uses which map).
Run after build_map_data.py:  python tools/build_dungeon_floors.py
"""
from __future__ import annotations

import importlib.util
import io
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
WORLD = ROOT / "shared" / "assets" / "world"
PUBLIC = ROOT / "platform" / "public" / "media" / "world"
FLOORS = PUBLIC / "floors"

# our dungeon key -> instance map ID (wings of one instance share its floors; `wing` on a floor says which)
KEY_MAP = {
    "shadowfang-keep": 33, "the-stockade": 34, "the-deadmines": 36, "wailing-caverns": 43, "razorfen-kraul": 47,
    "blackfathom-deeps": 48, "uldaman": 70, "gnomeregan": 90, "razorfen-downs": 129, "scarlet-monastery-armory": 189,
    "scarlet-monastery-cathedral": 189, "scarlet-monastery-graveyard": 189, "scarlet-monastery-library": 189,
    "zulfarrak": 209, "lower-blackrock-spire": 229, "upper-blackrock-spire": 229, "blackrock-depths": 230,
    "scholomance": 289, "maraudon": 349, "stratholme-living": 329, "stratholme-undead": 329, "ragefire-chasm": 389,
    "dire-maul-east": 429, "dire-maul-north": 429, "dire-maul-west": 429, "sunken-temple": 109,
    "onyxias-lair": 249, "molten-core": 409, "blackwing-lair": 469, "zulgurub": 309, "ruins-of-ahnqiraj": 509, "temple-of-ahnqiraj": 531,
}


def casc():
    spec = importlib.util.spec_from_file_location("casc", ROOT / "shared" / "sources" / "tools-casc-casc.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.Casc(r"D:\World of Warcraft", "wowf")


def compose(client, tiles: list[int]) -> Image.Image:
    canvas = Image.new("RGB", (1024, 768))
    for index, file_id in enumerate(tiles):
        tile = Image.open(io.BytesIO(client.read(file_id))).convert("RGB")
        canvas.paste(tile, ((index % 4) * 256, (index // 4) * 256))
    return canvas.crop((0, 0, 1002, 668))


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    source = json.loads((WORLD / "floors-src.json").read_text(encoding="utf8"))["floors"]
    FLOORS.mkdir(parents=True, exist_ok=True)
    client = casc()
    maps: dict[str, list] = {}
    failed: list[str] = []
    for map_id, floors in source.items():
        entries = []
        for index, floor in enumerate(floors):
            name = f"{map_id}-{index}.webp"
            try:
                compose(client, floor["tiles"]).save(FLOORS / name, "WEBP", quality=80, method=6)
            except (KeyError, OSError, ValueError) as error:
                failed.append(f"{name}: {type(error).__name__}")
                continue
            entries.append({"img": f"/media/world/floors/{name}", "name": floor.get("name"), "wing": floor.get("wing")})
        if entries:
            maps[map_id] = entries
        print(f"map {map_id}: {len(entries)}/{len(floors)} floors")
    data = {"schema": 1, "maps": maps, "keys": {k: v for k, v in KEY_MAP.items() if str(v) in maps}, "source": "OpenMap DungeonMaps table (MIT); art: Blizzard Entertainment, read from the game client"}
    text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    (WORLD / "floors.json").write_text(text, encoding="utf8")
    (PUBLIC / "floors.json").write_text(text, encoding="utf8")
    total = sum(p.stat().st_size for p in FLOORS.glob("*.webp"))
    print(f"{sum(len(v) for v in maps.values())} floors, {total / 1024 / 1024:.1f} MB; failed: {failed or 'none'}")


if __name__ == "__main__":
    main()
