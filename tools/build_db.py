"""Build the Evertally reference database (items, NPCs, quests, zones, dungeons) as small JSON shards.

Sources (all local, no network, no player data):
  * QuestieDB addon (GPL-3)           NPCs, quests, objects, item relations, reference drop chances
  * Forever item cache snapshot       10k items with Wowhead-style tooltips and loot sources
  * DungeonJournal addon (facts only) dungeon levels, bosses, boss loot, quests, entrances
  * AtlasLoot addon (GPL-2, facts only) raid loot tables and measured drop rates
  * SkillUp Forever addon (GPL-3, facts only) profession recipes: reagents, outputs, skill thresholds, trainer fees
  * LibForeverData addon (CC BY 4.0 for quest steps and notes) tips and walkthrough hints per quest
  * shared/assets/world (tools/build_map_data.py) where instance entrances lie, to give raids an entrance
Output: shared/assets/db/**  (mirrored to platform/public/media/db/**)

Run:  python tools/build_db.py
"""
from __future__ import annotations

import json
import re
import shutil
import sys
import time
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db_sources import ROOT, Questie, atlasloot, forever_steps, item_cache, item_sources, journal, recipes  # noqa: E402
from tooltip_parse import parse as parse_tooltip  # noqa: E402

OUT = ROOT / "shared" / "assets" / "db"
PUBLIC = ROOT / "platform" / "public" / "media" / "db"
MEDIA = ROOT / "platform" / "public" / "media"
SHARD = 128  # records per detail shard (npcs, quests)
SHARD_ITEMS = 48  # items carry full tooltips, keep their shards small
MAX_SPAWNS_DETAIL = 60

# QuestieDB stores the classic (mangos) npc_flag bits, not the modern ones:
# 1 gossip, 2 quest giver, 4 vendor, 8 flight master, 16 trainer, 32 spirit healer, 64 spirit guide,
# 128 innkeeper, 256 banker, 2048 battlemaster, 4096 auctioneer, 8192 stable master, 16384 repair.
NPC_FLAGS = [
    (0x4, "vendor"), (0x10, "trainer"), (0x4000, "repair"), (0x8, "flight"), (0x80, "inn"), (0x100, "bank"),
    (0x1000, "auction"), (0x2000, "stable"), (0x800, "battle"), (0x20, "spirit"), (0x40, "spirit"),
]
CLASS_NAMES = {0: "Consumable", 1: "Container", 2: "Weapon", 3: "Gem", 4: "Armor", 5: "Reagent", 6: "Projectile", 7: "Trade Goods", 9: "Recipe", 11: "Quiver", 12: "Quest", 13: "Key", 15: "Miscellaneous"}
RACES = {1: "Human", 2: "Orc", 4: "Dwarf", 8: "Night Elf", 16: "Undead", 32: "Tauren", 64: "Gnome", 128: "Troll", 512: "Blood Elf", 1024: "Draenei"}
CLASSES = {1: "Warrior", 2: "Paladin", 4: "Hunter", 8: "Rogue", 16: "Priest", 64: "Shaman", 128: "Mage", 256: "Warlock", 1024: "Druid"}
ALLIANCE, HORDE = 1 | 4 | 8 | 64, 2 | 16 | 32 | 128
QUEST_SORTS = {
    -1: "Epic", -22: "Seasonal", -24: "Herbalism", -61: "Warlock", -81: "Warrior", -82: "Shaman", -101: "Fishing", -121: "Blacksmithing",
    -141: "Paladin", -161: "Mage", -162: "Rogue", -181: "Alchemy", -182: "Leatherworking", -201: "Engineering", -261: "Hunter",
    -262: "Priest", -263: "Druid", -264: "Tailoring", -304: "Cooking", -324: "First Aid", -371: "Jewelcrafting",
}


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower().replace("'", "")).strip("-")


def write(folder: Path, name: str, value) -> int:
    folder.mkdir(parents=True, exist_ok=True)
    data = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    (folder / name).write_text(data, encoding="utf8")
    return len(data.encode("utf8"))


def ids(value) -> list[int]:
    """Flatten Questie id lists such as [[1,2],[3]] or {1:..., 2:...} into unique positive ints."""
    out: list[int] = []

    def walk(v):
        if isinstance(v, bool):
            return
        if isinstance(v, int):
            if v > 0 and v not in out:
                out.append(v)
        elif isinstance(v, list):
            for x in v:
                walk(x)
        elif isinstance(v, dict):
            for x in v.values():
                walk(x)

    walk(value)
    return out


def coords(pairs) -> list[tuple[float, float]]:
    out = []
    for pair in pairs if isinstance(pairs, list) else []:
        if isinstance(pair, list) and len(pair) >= 2 and all(isinstance(v, (int, float)) for v in pair[:2]) and 0 <= pair[0] <= 100 and 0 <= pair[1] <= 100:
            out.append((round(pair[0], 1), round(pair[1], 1)))
    return out


def _journal_text(text: str) -> str:
    """Strip game colour codes and turn money icons into g/s/c."""
    text = re.sub(r"\|T[^|]*(Gold|Silver|Copper)Icon[^|]*\|t", lambda m: m.group(1)[0].lower(), text)
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)


def build() -> None:
    t0 = time.time()
    icon_manifest = ROOT / "shared/assets/item-icons.json"
    client_icons = json.loads(icon_manifest.read_text(encoding="utf8"))["items"] if icon_manifest.is_file() else {}
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)
    maps = json.loads((MEDIA / "maps" / "manifest.json").read_text(encoding="utf8"))["maps"]
    ui_to_key = {ui: m["key"] for m in maps for ui in m["uiMapIds"]}
    map_names = {m["key"]: m["nameEn"] for m in maps}
    q = Questie()

    def zone_of(area) -> str | None:
        return ui_to_key.get(q.area_to_ui.get(area)) if isinstance(area, int) else None

    # ---------------------------------------------------------------- NPCs
    npcs: dict[int, dict] = {}
    for nid in sorted(q.ids["Npc"]):
        row = q.row("Npc", nid)
        name = row.get(1)
        if not isinstance(name, str) or not name or name.startswith("[DND]"):
            continue
        flags = q.field("Npc", nid, 15, row) or 0
        services = sorted({key for bit, key in NPC_FLAGS if isinstance(flags, int) and flags & bit})
        spawns_raw = q.field("Npc", nid, 7, row) or {}
        spawns: dict[str, list[tuple[float, float]]] = {}
        for area, pts in (spawns_raw.items() if isinstance(spawns_raw, dict) else []):
            key = zone_of(area)
            if key and (points := coords(pts)):
                spawns.setdefault(key, []).extend(points)
        npcs[nid] = {
            "id": nid, "name": name, "sub": q.field("Npc", nid, 14, row) if isinstance(q.field("Npc", nid, 14, row), str) else None,
            "lvl": [row.get(4) or 0, row.get(5) or row.get(4) or 0], "rank": q.field("Npc", nid, 6, row) or 0,
            "services": services, "friendly": q.field("Npc", nid, 13, row) if isinstance(q.field("Npc", nid, 13, row), str) else "",
            "zone": zone_of(q.field("Npc", nid, 9, row)), "starts": ids(q.field("Npc", nid, 10, row)), "ends": ids(q.field("Npc", nid, 11, row)),
            "spawns": spawns,
        }

    # ---------------------------------------------------------------- items
    cache = {i["itemId"]: i for i in item_cache()}
    srcs = item_sources()
    rates = q.drop_rates()
    atlas = atlasloot()
    for npc_id, listing in atlas["rates"].items():
        for item_id, percent in listing.items():
            rates.setdefault(item_id, {}).setdefault(npc_id, percent)
    drops_of_npc: dict[int, list[int]] = defaultdict(list)
    sells_of_npc: dict[int, list[int]] = defaultdict(list)
    quest_rewards: dict[int, list[int]] = defaultdict(list)
    items: dict[int, dict] = {}
    for item_id, raw in cache.items():
        tip = parse_tooltip(raw["tooltipHtml"])
        row = q.row("Item", item_id)
        npc_drops = ids(q.field("Item", item_id, 2, row))
        vendors = ids(q.field("Item", item_id, 14, row))
        rewards = ids(q.field("Item", item_id, 6, row))
        pct = rates.get(item_id, {})
        for npc_id in npc_drops:
            drops_of_npc[npc_id].append(item_id)
        for npc_id in vendors:
            sells_of_npc[npc_id].append(item_id)
        for quest_id in rewards:
            quest_rewards[quest_id].append(item_id)
        quality = None
        title = tip["rows"][0] if tip["rows"] else None
        if title and title[0] == "L" and len(title[1][0]) > 1 and re.fullmatch(r"q[0-9]", title[1][0][1] or ""):
            quality = int(title[1][0][1][1])
        text = " ".join("".join(sp[0] for sp in r[1]) for r in tip["rows"] if r[0] == "L")
        ilvl = re.search(r"Item Level (\d+)", text)
        req = re.search(r"Requires Level (\d+)", text)
        chance = re.search(r"Drop Chance: ([\d.]+)%", raw["tooltipHtml"])
        sources = []
        for key, label, kind in zip(raw.get("sourceKeys", []), raw.get("sourceLabels", []), raw.get("sourceTypes", [])):
            if key.startswith("forever::"):
                sources.append({"k": kind, "n": label, "key": key})
        classic = raw.get("changeFromClassic") or {}
        items[item_id] = {
            "id": item_id, "name": raw["name"], "q": quality, "ilvl": int(ilvl[1]) if ilvl else None, "req": int(req[1]) if req else None,
            "cat": CLASS_NAMES.get(q.field("Item", item_id, 12, row)), "slot": tip["slot"], "sub": tip["sub"], "tip": tip["rows"],
            "icon": raw.get("iconName"), "src": sources, "bosses": raw.get("bossNames") or [],
            "chance": float(chance[1]) if chance else None, "change": classic.get("lines") if classic.get("status") == "updated" else None,
            "status": classic.get("status"), "npcDrops": npc_drops, "objDrops": ids(q.field("Item", item_id, 3, row)), "vendors": vendors,
            "rewards": rewards, "starts": ids(q.field("Item", item_id, 5, row)), "pct": {str(k): v for k, v in pct.items()},
            "wh": raw.get("itemUrl"),
        }

    # Questie knows many more items than the tooltip cache; keep them as "lite" records
    # (name, levels, category and where they come from) so every loot reference resolves.
    for item_id in sorted(q.ids["Item"]):
        if item_id in items:
            continue
        row = q.row("Item", item_id)
        name = row.get(1)
        if not isinstance(name, str) or not name or name.startswith(("[DND]", "OLD")):
            continue
        npc_drops, vendors, rewards = ids(q.field("Item", item_id, 2, row)), ids(q.field("Item", item_id, 14, row)), ids(q.field("Item", item_id, 6, row))
        pct = rates.get(item_id, {})
        for npc_id in npc_drops:
            drops_of_npc[npc_id].append(item_id)
        for npc_id in vendors:
            sells_of_npc[npc_id].append(item_id)
        for quest_id in rewards:
            quest_rewards[quest_id].append(item_id)
        items[item_id] = {
            "id": item_id, "name": name, "q": None, "ilvl": row.get(9) or None, "req": row.get(10) or None, "cat": CLASS_NAMES.get(q.field("Item", item_id, 12, row)),
            "slot": None, "sub": None, "tip": [], "icon": f"client:{client_icons[str(item_id)]}" if str(item_id) in client_icons else None, "src": [], "bosses": [], "chance": None, "change": None, "status": None, "lite": True,
            "npcDrops": npc_drops, "objDrops": ids(q.field("Item", item_id, 3, row)), "vendors": vendors, "rewards": rewards, "starts": ids(q.field("Item", item_id, 5, row)),
            "pct": {str(k): v for k, v in pct.items()}, "wh": f"https://www.wowhead.com/forever/item={item_id}",
        }

    # ---------------------------------------------------------------- quests
    quests: dict[int, dict] = {}
    for qid in sorted(q.ids["Quest"]):
        row = q.row("Quest", qid)
        name = row.get(1)
        if not isinstance(name, str) or not name:
            continue
        started = q.field("Quest", qid, 2, row) or []
        finished = q.field("Quest", qid, 3, row) or []
        objectives = q.field("Quest", qid, 10, row) or []
        zone_raw = q.field("Quest", qid, 17, row)
        races = q.field("Quest", qid, 6, row) or 0
        classes_mask = q.field("Quest", qid, 7, row) or 0
        text = q.field("Quest", qid, 8, row)

        def part(group, index):
            return group[index] if isinstance(group, list) and len(group) > index else None

        quests[qid] = {
            "id": qid, "name": name, "lvl": row.get(5), "req": row.get(4), "zone": zone_of(zone_raw) if isinstance(zone_raw, int) and zone_raw > 0 else None,
            "sort": QUEST_SORTS.get(zone_raw) if isinstance(zone_raw, int) and zone_raw < 0 else None,
            "text": [t for t in text if isinstance(t, str)] if isinstance(text, list) else [],
            "fac": "A" if races and races & ALLIANCE and not races & HORDE else "H" if races and races & HORDE and not races & ALLIANCE else "",
            "races": [n for b, n in RACES.items() if races & b] if isinstance(races, int) and races and races != (ALLIANCE | HORDE) else [],
            "classes": [n for b, n in CLASSES.items() if classes_mask & b] if isinstance(classes_mask, int) and classes_mask else [],
            "startNpc": ids(part(started, 0)), "startObj": ids(part(started, 1)), "startItem": ids(part(started, 2)),
            "endNpc": ids(part(finished, 0)), "endObj": ids(part(finished, 1)),
            "kill": ids(part(objectives, 0)), "objObj": ids(part(objectives, 1)), "need": ids(part(objectives, 2)),
            "pre": ids(q.field("Quest", qid, 12, row)) + ids(q.field("Quest", qid, 13, row)),
            "next": ids(q.field("Quest", qid, 22, row)), "excl": ids(q.field("Quest", qid, 16, row)), "child": ids(q.field("Quest", qid, 14, row)),
            "rewards": quest_rewards.get(qid, []), "src": q.field("Quest", qid, 11, row) if isinstance(q.field("Quest", qid, 11, row), int) else None,
        }

    # quest tips and step hints (LibForeverData forever-db, CC BY 4.0)
    for qid, notes in forever_steps().items():
        if qid in quests:
            quests[qid]["tips"] = notes["tips"][:6]
            quests[qid]["steps"] = notes["steps"][:12]

    # ---------------------------------------------------------------- objects
    objects: dict[int, dict] = {}
    for oid in sorted(q.ids["Object"]):
        row = q.row("Object", oid)
        name = row.get(1)
        if not isinstance(name, str) or not name:
            continue
        spawns_raw = q.field("Object", oid, 4, row) or {}
        spawns: dict[str, list] = {}
        for area, pts in (spawns_raw.items() if isinstance(spawns_raw, dict) else []):
            key = zone_of(area)
            if key and (points := coords(pts)):
                spawns.setdefault(key, []).extend(points)
        objects[oid] = {"id": oid, "name": name, "spawns": spawns, "starts": ids(q.field("Object", oid, 2, row)), "ends": ids(q.field("Object", oid, 3, row))}

    # AtlasLoot also knows who drops what where QuestieDB lists no drop
    added = 0
    for item_id, by_npc in rates.items():
        item = items.get(item_id)
        if not item:
            continue
        for npc_id in by_npc:
            if npc_id in npcs and npc_id not in item["npcDrops"]:
                item["npcDrops"].append(npc_id)
                drops_of_npc[npc_id].append(item_id)
                added += 1
    print(f"drop relations added from AtlasLoot: {added}", flush=True)

    # cross references
    for nid, npc in npcs.items():
        npc["drops"] = sorted(drops_of_npc.get(nid, []), key=lambda i: -(items[i]["pct"].get(str(nid)) or 0))
        npc["sells"] = sells_of_npc.get(nid, [])
        npc["starts"] = [i for i in npc["starts"] if i in quests]
        npc["ends"] = [i for i in npc["ends"] if i in quests]
    npc_kill_quests: dict[int, list[int]] = defaultdict(list)
    for qid, quest in quests.items():
        for nid in quest["kill"]:
            npc_kill_quests[nid].append(qid)
    print(f"loaded: items {len(items)} npcs {len(npcs)} quests {len(quests)} objects {len(objects)}  ({time.time() - t0:.1f}s)", flush=True)

    # ---------------------------------------------------------------- shards
    def shards(kind: str, records: dict[int, dict], slim, size: int = SHARD) -> dict[int, int]:
        order = sorted(records)
        index: dict[int, int] = {}
        for start in range(0, len(order), size):
            chunk = order[start:start + size]
            number = start // size
            write(OUT / kind, f"{number}.json", {str(i): slim(records[i]) for i in chunk})
            for i in chunk:
                index[i] = number
        return index

    def slim_item(it):
        out = {k: it[k] for k in ("id", "name", "q", "ilvl", "req", "cat", "slot", "sub", "tip", "icon", "bosses", "chance", "change", "status", "wh") if it.get(k) not in (None, [], "")}
        out["src"] = it["src"]
        if it.get("lite"):
            out["lite"] = 1
        drops = sorted(it["npcDrops"], key=lambda n: -(it["pct"].get(str(n)) or 0))[:40]
        out["drops"] = [[n, it["pct"].get(str(n))] if it["pct"].get(str(n)) else [n] for n in drops]
        if it["objDrops"]:
            out["objDrops"] = it["objDrops"][:20]
        for key in ("vendors", "rewards", "starts"):
            if it[key]:
                out[key] = it[key][:40]
        return out

    def slim_npc(n):
        out = {"id": n["id"], "name": n["name"], "lvl": n["lvl"]}
        for key in ("sub", "zone", "friendly"):
            if n.get(key):
                out[key] = n[key]
        if n["rank"]:
            out["rank"] = n["rank"]
        for key in ("services", "starts", "ends", "sells"):
            if n[key]:
                out[key] = n[key][:120]
        if n["drops"]:
            out["drops"] = [[i, items[i]["pct"].get(str(n["id"]))] if items[i]["pct"].get(str(n["id"])) else [i] for i in n["drops"][:80]]
        if npc_kill_quests.get(n["id"]):
            out["kills"] = npc_kill_quests[n["id"]][:40]
        out["sp"] = {k: v[:MAX_SPAWNS_DETAIL] for k, v in n["spawns"].items()}
        return out

    def slim_quest(qd):
        out = {k: qd[k] for k in ("id", "name", "lvl", "req", "zone", "sort", "text", "fac", "races", "classes", "startNpc", "startObj", "startItem", "endNpc", "endObj", "kill", "objObj", "need", "pre", "next", "excl", "child", "rewards", "src", "tips", "steps") if qd.get(k) not in (None, [], "")}
        return out

    item_index = shards("items", items, slim_item, SHARD_ITEMS)
    npc_index = shards("npcs", npcs, slim_npc)
    quest_index = shards("quests", quests, slim_quest)

    # ---------------------------------------------------------------- search index
    cats = sorted({it["cat"] for it in items.values() if it["cat"]})
    slots = sorted({it["slot"] for it in items.values() if it["slot"]})
    search = {
        "items": [[i, it["name"], it["q"], it["ilvl"], it["req"], cats.index(it["cat"]) if it["cat"] in cats else -1, slots.index(it["slot"]) if it["slot"] in slots else -1, item_index[i], 1 if it.get("lite") else 0, client_icons.get(str(i))] for i, it in sorted(items.items())],
        "npcs": [[i, n["name"], n["lvl"][0], n["lvl"][1], n["rank"], n["services"], 1 if n["spawns"] else 0, npc_index[i], n["zone"] or (next(iter(n["spawns"])) if n["spawns"] else None)] for i, n in sorted(npcs.items())],
        "quests": [[i, qd["name"], qd["lvl"], qd["req"], qd["zone"] or qd["sort"], qd["fac"], quest_index[i]] for i, qd in sorted(quests.items())],
        "cats": cats, "slots": slots,
    }
    write(OUT, "search.json", search)
    write(OUT, "objects.json", {str(i): [o["name"]] + ([next(iter(o["spawns"])), *o["spawns"][next(iter(o["spawns"]))][0]] if o["spawns"] else []) for i, o in objects.items()})

    # ---------------------------------------------------------------- zones (map points of interest)
    mailbox_ids = {i for i, o in objects.items() if o["name"] == "Mailbox"}
    poi_layers = {"qs": "Quest starters", "qe": "Quest turn-ins", "vendor": "Vendors", "trainer": "Trainers", "flight": "Flight masters", "inn": "Innkeepers", "bank": "Banks", "auction": "Auction houses", "stable": "Stable masters", "battle": "Battlemasters", "repair": "Repairs", "spirit": "Spirit healers", "mail": "Mailboxes"}
    zones: dict[str, dict] = defaultdict(lambda: {"poi": defaultdict(list), "mobs": []})
    for nid, n in npcs.items():
        for zone, points in n["spawns"].items():
            for x, y in points:
                z = zones[zone]
                if n["starts"]:
                    z["poi"]["qs"].append([nid, x, y])
                if n["ends"]:
                    z["poi"]["qe"].append([nid, x, y])
                for svc in n["services"]:
                    z["poi"][svc].append([nid, x, y])
                friendly_both = "A" in n["friendly"] and "H" in n["friendly"]
                if not n["services"] and not friendly_both and n["lvl"][0] and not n["starts"] and not n["ends"]:
                    z["mobs"].append([nid, x, y])
    for oid, o in objects.items():
        for zone, points in o["spawns"].items():
            for x, y in points:
                if oid in mailbox_ids:
                    zones[zone]["poi"]["mail"].append([-oid, x, y])
                elif o["starts"]:
                    zones[zone]["poi"]["qs"].append([-oid, x, y])
                if o["ends"] and oid not in mailbox_ids:
                    zones[zone]["poi"]["qe"].append([-oid, x, y])
    zone_dir = OUT / "zones"
    zone_meta = {}
    for key, z in zones.items():
        names: dict[str, str] = {}
        for layer in z["poi"].values():
            for ident, *_ in layer:
                names[str(ident)] = (npcs[ident]["name"] if ident > 0 else objects[-ident]["name"])
        payload = {"key": key, "poi": {k: v for k, v in z["poi"].items()}, "mobs": z["mobs"], "names": names}
        size = write(zone_dir, f"{key}.json", payload)
        zone_meta[key] = {"name": map_names.get(key, key), "poi": {k: len(v) for k, v in z["poi"].items()}, "mobs": len(z["mobs"]), "bytes": size}

    # ---------------------------------------------------------------- dungeons
    dj = journal()
    entrances = {name: e for name, e in dj["db"].items()}
    by_source: dict[str, list[int]] = defaultdict(list)  # forever instance name -> item ids
    boss_items: dict[str, dict[str, list[int]]] = defaultdict(lambda: defaultdict(list))
    for item_id, it in items.items():
        for s in it["src"]:
            m = re.fullmatch(r"forever::(dungeon|raid)::(.+)", s["key"])
            if m:
                by_source[m.group(2)].append(item_id)
                for boss in it["bosses"]:
                    boss_items[m.group(2)][boss].append(item_id)

    def source_name(dj_name: str) -> str:
        base = dj_name.split(":")[0].strip().lower()
        base = {"excavation site": "excavation site", "lower blackrock spire": "blackrock spire", "upper blackrock spire": "blackrock spire"}.get(base, base)
        if base == "sunken temple":
            base = "the temple of atal'hakkar"
        return base

    npc_by_name: dict[str, list[int]] = defaultdict(list)
    for nid, n in npcs.items():
        npc_by_name[n["name"]].append(nid)
    dungeons = []
    taken: set[str] = set()
    for name, e in sorted(entrances.items()):
        if not e.get("bosses"):
            continue  # quest-item pseudo entries from the journal
        src_key = source_name(name)
        taken.add(src_key)
        levels = re.findall(r"\d+", str(e.get("level") or ""))
        boss_levels = dj["bossLevels"].get(name, {})
        bosses = []
        extras: dict[str, list] = {}
        for b in e.get("bosses") or []:
            loot_rows = []
            for raw_row in b.get("loot") or []:
                if isinstance(raw_row, dict):  # new items: {1: id (0 = unknown), 2: name, 3: slot, 4: quality, tip: [...]}
                    row = [raw_row.get("1"), raw_row.get("2"), raw_row.get("3"), raw_row.get("4")]
                    tip = [_journal_text(" / ".join(t) if isinstance(t, list) else str(t)) for t in (raw_row.get("tip") or [])]
                elif isinstance(raw_row, list) and raw_row:
                    row, tip = raw_row, None
                else:
                    continue
                if not isinstance(row[0], int):
                    continue
                key = row[0] if row[0] > 0 else f"n:{row[1]}"
                if key not in items:
                    extras[str(key)] = [row[1] or f"#{row[0]}", row[2], row[3], tip]
                loot_rows.append([key])
            npc_id = b.get("npcID") if isinstance(b.get("npcID"), int) else None
            if npc_id not in npcs:
                same = [n for n in npc_by_name.get(b.get("name") or "", []) if npcs[n]["spawns"]]
                npc_id = same[0] if len(same) == 1 else None
            bosses.append({"name": b.get("name"), "npc": npc_id, "lvl": boss_levels.get(b.get("name")), "rare": bool(b.get("rare")), "loot": [row[0] for row in loot_rows], "note": b.get("description")})
        in_boss = {i for b in bosses for i in b["loot"] if isinstance(i, int)}
        entrance = e.get("entrance") if isinstance(e.get("entrance"), dict) else None
        zone_key = ui_to_key.get(entrance.get("mapID")) if entrance else None
        dq = []
        for quest in e.get("quests") or []:
            if isinstance(quest, dict) and isinstance(quest.get("id"), int):
                dq.append({"id": quest["id"], "name": quest.get("name"), "lvl": quest.get("level"), "req": quest.get("requires"), "fac": quest.get("faction"), "pickup": quest.get("pickup"), "turnin": quest.get("turnin"), "rewards": [r[0] for r in (quest.get("rewardItems") or []) if isinstance(r, list) and r and r[0] in items], "choice": bool(quest.get("rewardChoice"))})
        dungeons.append({
            "key": slug(name), "name": name, "type": "dungeon", "group": name.split(":")[0].strip() if ":" in name else None,
            "lvl": [int(levels[0]), int(levels[-1])] if levels else None, "location": e.get("location"), "players": 5, "bosses": bosses, "quests": dq,
            "extras": extras, "status": "journal" + (" (partial)" if e.get("fullItemsTBD") or e.get("fullQuestsTBD") else ""),
            "other": [i for i in by_source.get(src_key, []) if i not in in_boss][:60] if len({n for n in entrances if source_name(n) == src_key and entrances[n].get("bosses")}) == 1 else [],
            "entrance": {"zone": zone_key, "x": round(entrance["x"] * 100, 1), "y": round(entrance["y"] * 100, 1), "label": entrance.get("label"), "hint": entrance.get("detail")} if entrance and zone_key and isinstance(entrance.get("x"), (int, float)) else None,
            "source": "DungeonJournal addon (facts), Forever item cache",
        })
    # entrances of instances OpenMap places on the world: zone-relative, like the journal's
    places_file, world_file = ROOT / "shared" / "assets" / "world" / "places.json", ROOT / "shared" / "assets" / "world" / "world.json"
    spots: dict[int, dict] = {}
    if places_file.is_file() and world_file.is_file():
        places = json.loads(places_file.read_text(encoding="utf8"))
        zone_rects = {k: v["rect"] for k, v in json.loads(world_file.read_text(encoding="utf8"))["maps"].items() if v["kind"] in ("zone", "city")}
        for place in places["instances"]:
            candidates = [(((place["u"] - (r[0] + r[1]) / 2) / (r[1] - r[0])) ** 2 + ((place["v"] - (r[2] + r[3]) / 2) / (r[3] - r[2])) ** 2, k, r) for k, r in zone_rects.items() if r[0] <= place["u"] <= r[1] and r[2] <= place["v"] <= r[3]]
            if not candidates:
                continue
            _, zone, r = min(candidates)
            for entry in place["list"]:
                spots[entry["map"]] = {"zone": zone, "x": round((place["u"] - r[0]) / (r[1] - r[0]) * 100, 1), "y": round((place["v"] - r[2]) / (r[3] - r[2]) * 100, 1), "min": entry["min"], "max": entry["max"]}
    RAID_MAPS = {"MoltenCore": 409, "BlackwingLair": 469, "Zul'Gurub": 309, "TheRuinsofAhnQiraj": 509, "TheTempleofAhnQiraj": 531, "OnyxiasLairNew": 249}
    for raid_key, raid in atlas["raids"].items():
        bosses = []
        extras = {}
        for boss in raid["bosses"]:
            npc_id = boss["npc"] if boss["npc"] in npcs else None
            if npc_id is None:
                same = [n for n in npc_by_name.get(boss["name"], []) if npcs[n]["spawns"]]
                npc_id = same[0] if len(same) == 1 else None
            for item_id in boss["loot"]:
                if item_id not in items:
                    extras[str(item_id)] = [f"Item #{item_id}", None, None, None]
            bosses.append({"name": boss["name"], "npc": npc_id, "lvl": None, "rare": False, "loot": [i if i in items else str(i) for i in boss["loot"]], "note": None})
        spot = spots.get(RAID_MAPS.get(raid_key, -1))
        has_loot = any(b["loot"] for b in bosses)
        classic = raid_key in RAID_MAPS and raid_key != "OnyxiasLairNew" or raid_key in ("Naxxramas",)
        dungeons = [d for d in dungeons if d["key"] != slug(raid["name"])]  # replaces the journal-less placeholder
        dungeons.append({
            "key": slug(raid["name"]), "name": raid["name"], "type": "raid", "group": "World Bosses" if raid_key == "WorldBosses" else None,
            "lvl": [spot["min"], spot["max"]] if spot and spot["min"] else [60, 60] if classic or raid_key == "WorldBosses" else None,
            "location": "Open world" if raid_key == "WorldBosses" else None, "players": raid["players"], "bosses": bosses, "quests": [], "extras": extras,
            "status": ("atlas (classic table)" if raid.get("fallback") else "atlas") if has_loot else "pending", "other": [], "source": "AtlasLoot addon (GPL-2.0; loot tables), OpenMap (MIT; entrances)",
            "entrance": {"zone": spot["zone"], "x": spot["x"], "y": spot["y"], "label": f"{raid['name']} entrance", "hint": None} if spot else None,
        })
    write(OUT, "dungeons.json", {"schemaVersion": 2, "entries": dungeons})
    recipe_data = recipes()
    for recipe in recipe_data["recipes"]:  # items the recipes mention must resolve in the index
        recipe["reagents"] = [r for r in recipe["reagents"] if r[0] in items]
    write(OUT, "recipes.json", {"schemaVersion": 1, **recipe_data})

    write(OUT, "meta.json", {
        "schemaVersion": 2, "generatedAt": int(time.time()), "shardSize": {"items": SHARD_ITEMS, "npcs": SHARD, "quests": SHARD},
        "counts": {"items": len(items), "npcs": len(npcs), "quests": len(quests), "objects": len(objects), "zones": len(zone_meta), "dungeons": len(dungeons), "recipes": len(recipe_data["recipes"])},
        "layers": poi_layers, "zones": zone_meta,
        "sources": [
            {"name": "QuestieDB 1.0.13 Forever", "license": "GPL-3.0", "use": "NPCs, quests, objects, spawns, item relations, reference drop chances (quest items)"},
            {"name": "WoW Classic Item Caches (Napalmsteak), Forever snapshot", "license": "see repository", "use": "item tooltips, loot sources, changes from Classic"},
            {"name": "DungeonJournal addon by Exehn", "license": "not stated; facts only (names, ids, levels, coordinates)", "use": "dungeon levels, bosses, boss loot, quests, entrances"},
            {"name": "AtlasLoot Forever (AtlasLootClassic)", "license": "GPL-2.0; facts only (item and NPC IDs, percentages)", "use": "raid loot tables, measured drop rates"},
            {"name": "LibForeverData (forever-db, Polestar contributors)", "license": "CC BY 4.0 (quest steps and notes); database credits: EG Link (Efficient Games, CC BY 4.0), CMaNGOS classic-db, pfQuest (MIT), ForeverTDB", "use": "quest tips and step hints"},
            {"name": "SkillUp Forever (cjber)", "license": "GPL-3.0; facts only (IDs, skill numbers, fees)", "use": "profession recipes, reagents, skill thresholds"},
            {"name": "OpenMap", "license": "MIT (code and data tables)", "use": "instance entrances, floor lists, boats, zeppelins, flights, zone levels"},
            {"name": "Shortest Path Forever", "license": "GPL-3.0; facts only", "use": "flight durations, walking yards between fixed places, transport timetables, portals"},
        ],
    })
    print(f"done in {time.time() - t0:.1f}s", flush=True)
    sizes = sum(p.stat().st_size for p in OUT.rglob("*.json"))
    print(f"files {sum(1 for _ in OUT.rglob('*.json'))}, {sizes / 1e6:.1f} MB raw")


def publish() -> None:
    shutil.rmtree(PUBLIC, ignore_errors=True)
    shutil.copytree(OUT, PUBLIC)
    print("mirrored to", PUBLIC.relative_to(ROOT))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    build()
    publish()
    # The services layer is derived from this DB; publishing must not leave it missing.
    from build_services import main as build_services
    build_services()
