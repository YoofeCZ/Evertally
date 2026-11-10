"""Resource node positions (herbs, ore, containers, fishing pools) for the map's Gathering layer.

Source: the GatherLite addon installed with the game (MIT original code by Wuild). Its plugins/database/data/forever.lua
is generated from Wowhead listings and holds, per object id and UiMap id, normalized x,y pairs; scripts/nodes.lua names
the object ids and gives each resource's minimum skill. Only these facts (ids, names, coordinates) are copied; no code, no
icons. The underlying listing is Wowhead's, which GatherLite does not relicense: see THIRD_PARTY.md before publishing.

    python tools/build_gather.py [path-to-GatherLite]
Writes platform/public/media/gather/gather.json:
    nodes   [{key, name, type, skill, n}]   one entry per resource (all its object ids merged)
    points  {key: {uiMapId: [x1000, y1000, ...]}}  coordinates as integers in thousandths of the map
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = Path(r"D:\World of Warcraft\_forever_\Interface\AddOns\GatherLite")
OUT = ROOT / "platform" / "public" / "media" / "gather" / "gather.json"

INSERT = re.compile(r'InsertObject\(\s*"(\w+)"\s*,\s*\{([^}]*)\}\s*,\s*"([^"]+)"\s*,\s*"[^"]*"\s*,\s*(nil|\{[^}]*\})', re.S)
NAME = re.compile(r"""L\['node\.([^']+)'\]\s*=\s*"([^"]*)\"""")
TOKEN = re.compile(r"\[(\d+)\]\s*=\s*\{|\}|(-?\d*\.\d+|-?\d+)")


def parse_points(text: str) -> dict[int, dict[int, list[tuple[int, int]]]]:
    """[objectId][uiMapId] = { x, y, x, y ... } from the generated Lua table."""
    out: dict[int, dict[int, list[tuple[int, int]]]] = {}
    depth = 0
    obj = amap = None
    numbers: list[float] = []
    # skip the header comment lines so their digits are not read
    body = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("--"))
    for match in TOKEN.finditer(body):
        key, number = match.group(1), match.group(2)
        if key is not None:
            if depth == 0:
                obj = int(key); out.setdefault(obj, {})
            elif depth == 1:
                amap = int(key); numbers = []
            depth += 1
        elif number is not None:
            if depth == 2:
                numbers.append(float(number))
        elif depth > 0:
            depth -= 1
            if depth == 1 and obj is not None and amap is not None:
                pairs = [(round(numbers[i] * 1000), round(numbers[i + 1] * 1000)) for i in range(0, len(numbers) - 1, 2)]
                out[obj].setdefault(amap, []).extend(pairs)
                amap = None
    return out


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    nodes_lua = (root / "scripts" / "nodes.lua").read_text(encoding="utf8")
    names_lua = (root / "scripts" / "locales" / "enUS.lua").read_text(encoding="utf8")
    forever = (root / "plugins" / "database" / "data" / "forever.lua").read_text(encoding="utf8")

    names = dict(NAME.findall(names_lua))
    points = parse_points(forever)
    resources = []
    claimed: set[int] = set()
    for kind, ids, key, levels in INSERT.findall(nodes_lua):
        object_ids = [int(value) for value in re.findall(r"\d+", ids)]
        skill = int(re.findall(r"\d+", levels)[0]) if levels != "nil" and re.findall(r"\d+", levels) else None
        merged: dict[int, set[tuple[int, int]]] = {}
        for oid in object_ids:
            claimed.add(oid)
            for ui_map, pairs in points.get(oid, {}).items():
                merged.setdefault(ui_map, set()).update(pairs)
        if not merged:
            continue
        resources.append({
            "key": f"{kind}:{key}", "name": names.get(key) or key.replace("_", " ").title(), "type": kind, "skill": skill,
            "n": sum(len(v) for v in merged.values()), "maps": {str(m): sorted(v) for m, v in sorted(merged.items())},
        })
    # a name used by two kinds (a chest and a fishing pool) stays two resources, as the key carries the kind
    resources.sort(key=lambda r: (r["type"], r["skill"] if r["skill"] is not None else 9999, r["name"]))
    out = {
        "source": "GatherLite plugins/database/data/forever.lua (MIT; coordinates generated from Wowhead listings)",
        "nodes": [{k: r[k] for k in ("key", "name", "type", "skill", "n")} for r in resources],
        "points": {r["key"]: {m: [c for pair in pairs for c in pair] for m, pairs in r["maps"].items()} for r in resources},
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, separators=(",", ":"), ensure_ascii=False), encoding="utf8")
    unclaimed = sorted(set(points) - claimed)
    total = sum(r["n"] for r in resources)
    print(f"{OUT.relative_to(ROOT)}: {OUT.stat().st_size / 1024:.0f} KiB, {len(resources)} resources, {total} points")
    for kind in sorted({r["type"] for r in resources}):
        print(f"  {kind}: {sum(1 for r in resources if r['type'] == kind)} resources, {sum(r['n'] for r in resources if r['type'] == kind)} points")
    if unclaimed:
        print(f"object ids with points but no node definition (left out): {unclaimed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
