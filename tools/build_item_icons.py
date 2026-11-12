"""Fill missing reference item icons from the installed Forever client, without player data.

Metadata: https://wago.tools/db2/Item/csv?build=1.60.1.70862 (Blizzard data).
Run after build_db.py, then rebuild the DB to include the generated manifest.
Deduplicate by IconFileDataID rather than shipping thousands of identical images.
"""
from pathlib import Path
import csv
import hashlib
import importlib.util
import io
import json
import struct
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BUILD = "1.60.1.70862"


def main():
    source = ROOT / "shared/sources" / f"Item-{BUILD}.csv"
    rows = {int(r["ID"]): int(r["IconFileDataID"]) for r in csv.DictReader(source.open(encoding="utf-8-sig"))}
    search = json.loads((ROOT / "shared/assets/db/search.json").read_text(encoding="utf8"))
    target = ROOT / "platform/public/media/identity/client-items"
    target.mkdir(parents=True, exist_ok=True)
    missing = [r[0] for r in search["items"] if not (ROOT / f"platform/public/media/identity/items/{r[0]}.jpg").is_file()]
    spec = importlib.util.spec_from_file_location("client_casc", ROOT / "shared/sources/tools-casc-casc.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    client = module.Casc(r"D:\World of Warcraft", "wowf")
    good, bad = set(), set()
    for file_id in sorted({rows.get(i, 0) for i in missing} - {0}):
        dest = target / f"{file_id}.jpg"
        try:
            if dest.is_file():
                with Image.open(dest) as image:
                    image.verify()
            else:
                raw = client.read(file_id)
                if raw[:4] == b"BLP2" and raw[8] == 3:
                    # BLP2 raw BGRA; Pillow's BLP reader only handles palette/DXT variants.
                    width, height, offset = struct.unpack_from("<III", raw, 12)
                    if not 0 < width <= 1024 or not 0 < height <= 1024 or offset + width * height * 4 > len(raw):
                        raise ValueError("Invalid raw BLP size")
                    image = Image.frombytes("RGBA", (width, height), raw[offset:offset + width * height * 4], "raw", "BGRA").convert("RGB")
                else:
                    image = Image.open(io.BytesIO(raw)).convert("RGB")
                image.save(dest, "JPEG", quality=90)
            good.add(file_id)
        except (KeyError, OSError, ValueError, NotImplementedError):
            bad.add(file_id)
    icons = {str(i): rows[i] for i in missing if rows.get(i) in good}
    report = {"build": BUILD, "source": f"https://wago.tools/db2/Item/csv?build={BUILD}",
              "sourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
              "art": "Blizzard Entertainment; read from installed wowf CASC", "items": icons,
              "missing": [i for i in missing if str(i) not in icons], "unreadableFileIds": sorted(bad)}
    for dest in [ROOT / "shared/assets/item-icons.json", ROOT / "platform/public/media/identity/client-items.json"]:
        dest.write_text(json.dumps(report, separators=(",", ":")), encoding="utf8")
    print(f"Added {len(icons)} item icons using {len(good)} distinct images; missing {len(report['missing'])}; unreadable {len(bad)}")


if __name__ == "__main__":
    main()
