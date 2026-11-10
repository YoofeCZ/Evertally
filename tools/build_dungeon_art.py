"""Build one banner image per dungeon: platform/public/media/dungeons/<key>.jpg and an art manifest.

Source priority per dungeon:
  1. client      Blizzard loading screen read from the installed Forever client (CASC)
  2. journal     art shipped in the installed DungeonJournal addon (originally Blizzard artwork)
  3. floor       Blizzard's own map of the instance's first floor (tools/build_dungeon_floors.py)
  4. map         a crop of the entrance area from our own zone map (always available)
Run after build_db.py:  python tools/build_dungeon_art.py
"""
from __future__ import annotations

import csv
import importlib.util
import io
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "platform" / "public" / "media" / "dungeons"
MEDIA = ROOT / "platform" / "public" / "media"
JOURNAL_MEDIA = Path(r"D:\World of Warcraft\_forever_\Interface\AddOns\ForeverDungeonJournal\Media")
WIDTH = 1024

CLIENT = {  # dungeon key -> LoadingScreens.MainImageFileDataID (from Wago LoadingScreens, build 1.60.1.70291)
    "hall-of-thanes": 7963781, "ruins-of-lordaeron": 7963782, "city-of-dalaran": 7963775, "excavation-site-wetlands": 7963777,
}
JOURNAL = {
    "alcaz-prison": "AlcazPrisonHome", "blackmaw-hold": "BlackmawHoldHome", "blackrock-depths": "BlackrockDepthsHome",
    "lower-blackrock-spire": "BlackrockSpireHome", "upper-blackrock-spire": "UpperBlackrockSpireHome",
    "dire-maul-east": "DireMaulHome", "dire-maul-north": "DireMaulNorthHome", "dire-maul-west": "DireMaulWestHome",
    "the-drowned-city": "DrownedCityHome", "kroldok-stronghold": "KroldokHome", "maraudon": "MaraudonHome",
    "razorfen-downs": "RazorfenDownsHome", "scarlet-monastery-armory": "ScarletMonasteryArmoryHome",
    "scarlet-monastery-cathedral": "ScarletMonasteryCathedralHome", "scarlet-monastery-graveyard": "ScarletMonasteryGraveyardHome",
    "scarlet-monastery-library": "ScarletMonasteryLibraryHome", "scholomance": "ScholomanceHome", "shapers-terrace": "ShapersTerraceHome",
    "stratholme-living": "StratholmeHome", "stratholme-undead": "StratholmeUndeadHome", "sunken-temple": "SunkenTempleHome",
    "uldaman": "UldamanHome", "zulfarrak": "ZulFarrakHome",
}


def fit(image: Image.Image) -> Image.Image:
    """Crop to 2:1 around the centre and scale to the banner width."""
    image = image.convert("RGB")
    target = 2.0
    w, h = image.size
    if w / h > target:
        new_w = int(h * target)
        image = image.crop(((w - new_w) // 2, 0, (w - new_w) // 2 + new_w, h))
    else:
        new_h = int(w / target)
        image = image.crop((0, (h - new_h) // 2, w, (h - new_h) // 2 + new_h))
    return image.resize((WIDTH, WIDTH // 2), Image.LANCZOS)


def content_box(image: Image.Image) -> Image.Image:
    """Loading screens ship with letterbox bars: transparent, or a flat grey baked into the pixels."""
    if image.mode == "RGBA":
        box = image.getchannel("A").point(lambda v: 255 if v > 128 else 0).getbbox()
        if box and box != (0, 0, *image.size):
            return image.crop(box)
    rgb = np.asarray(image.convert("RGB")).astype(int)
    flat = (np.abs(rgb - rgb[0, 0]).max(axis=2) < 4)  # pixels equal to the corner colour
    rows = np.where(~flat.all(axis=1))[0]
    cols = np.where(~flat.all(axis=0))[0]
    if rows.size and cols.size:
        return image.crop((int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1))
    return image


def casc():
    spec = importlib.util.spec_from_file_location("casc", ROOT / "shared" / "sources" / "tools-casc-casc.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.Casc(r"D:\World of Warcraft", "wowf")


def map_crop(entrance: dict) -> Image.Image | None:
    path = MEDIA / "maps" / f"{entrance['zone']}.webp"
    if not path.is_file():
        return None
    zone = Image.open(path).convert("RGB")
    w, h = zone.size
    crop_w = int(w * 0.34)
    crop_h = crop_w // 2
    cx, cy = entrance["x"] / 100 * w, entrance["y"] / 100 * h
    left = max(0, min(w - crop_w, int(cx - crop_w / 2)))
    top = max(0, min(h - crop_h, int(cy - crop_h / 2)))
    image = zone.crop((left, top, left + crop_w, top + crop_h)).resize((WIDTH, WIDTH // 2), Image.LANCZOS)
    image = image.filter(ImageFilter.GaussianBlur(0.8))
    return ImageEnhance.Brightness(image).enhance(0.85)


def floor_crop(map_id: int) -> Image.Image | None:
    path = MEDIA / "world" / "floors" / f"{map_id}-0.webp"
    if not path.is_file():
        return None
    return fit(Image.open(path))


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    dungeons = json.loads((ROOT / "shared" / "assets" / "db" / "dungeons.json").read_text(encoding="utf8"))["entries"]
    OUT.mkdir(parents=True, exist_ok=True)
    client = None
    manifest: dict[str, dict] = {}
    floors_file = ROOT / "shared" / "assets" / "world" / "floors.json"
    floor_keys = json.loads(floors_file.read_text(encoding="utf8"))["keys"] if floors_file.is_file() else {}
    for entry in dungeons:
        key = entry["key"]
        image = None
        source = None
        if key in CLIENT:
            try:
                client = client or casc()
                image = fit(content_box(Image.open(io.BytesIO(client.read(CLIENT[key])))))
                source = "client"
            except (KeyError, OSError, ValueError) as error:
                print("client art unavailable for", key, type(error).__name__)
        if image is None and key in JOURNAL:
            path = JOURNAL_MEDIA / f"{JOURNAL[key]}.tga"
            if path.is_file():
                image = fit(Image.open(path))
                source = "journal"
        if image is None and key in floor_keys:
            image = floor_crop(floor_keys[key])
            source = "floor" if image else None
        if image is None and entry.get("entrance"):
            image = map_crop(entry["entrance"])
            source = "map" if image else None
        if image is None:
            continue
        image.save(OUT / f"{key}.jpg", quality=84, optimize=True)
        manifest[key] = {"image": f"/media/dungeons/{key}.jpg", "source": source}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf8")
    counts = {s: sum(1 for m in manifest.values() if m["source"] == s) for s in ("client", "journal", "floor", "map")}
    missing = [e["key"] for e in dungeons if e["key"] not in manifest]
    print(f"{len(manifest)} banners {counts}; without image: {missing}")
    total = sum(p.stat().st_size for p in OUT.glob("*.jpg"))
    print(f"{total / 1024:.0f} KB total")


if __name__ == "__main__":
    main()
