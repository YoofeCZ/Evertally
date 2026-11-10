"""Readers for the local reference sources used by build_db.py. No network, no player data.

QuestieDB  : installed addon (GPL-3), rows stored as CBOR inside the TOC file.
Item cache : shared/sources/forever-items.json (Wowhead-style tooltip HTML per item).
DungeonJournal: installed addon, loaded in a Lua sandbox with stubs; only facts are used.
"""
from __future__ import annotations

import base64
import csv
import json
import re
import sys
from pathlib import Path

import cbor2

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "shared" / "sources"
ADDONS = Path(r"D:\World of Warcraft\_forever_\Interface\AddOns")
QUESTIE = ADDONS / "QuestieDB"
JOURNAL = ADDONS / "ForeverDungeonJournal"


def _clean(value):
    if isinstance(value, bytes):
        return value.decode("utf8", "replace")
    if isinstance(value, list):
        return [_clean(v) for v in value]
    if isinstance(value, dict):
        return {_clean(k): _clean(v) for k, v in value.items()}
    return value


class Questie:
    """Lazy accessor for `X-<Kind>-<id>-<field>` rows. Field `S` holds the scalar columns."""

    def __init__(self) -> None:
        toc = (QUESTIE / "QuestieDB_Forever.toc").read_text(encoding="utf8")
        self.meta = {k: v for k, v in re.findall(r"^## (X-[^:]+): (.*)$", toc, re.M)}
        self.ids: dict[str, set[int]] = {"Item": set(), "Npc": set(), "Quest": set(), "Object": set()}
        for key in self.meta:
            m = re.fullmatch(r"X-(Item|Npc|Quest|Object)-(\d+)-S", key)
            if m:
                self.ids[m.group(1)].add(int(m.group(2)))
        self._row_cache: dict[str, object] = {}
        self.area_to_ui = self._area_to_ui()

    def raw(self, key: str):
        if key in self._row_cache:
            return self._row_cache[key]
        raw = self.meta.get(key)
        if raw and raw.startswith("~"):
            raw = "".join(self.meta[f"{key}-{i}"] for i in range(1, int(raw.strip("~")) + 1))
        value = _clean(cbor2.loads(base64.b64decode(raw))) if raw else None
        self._row_cache[key] = value
        return value

    def row(self, kind: str, ident: int) -> dict:
        row = self.raw(f"X-{kind}-{ident}-S")
        return row if isinstance(row, dict) else {}

    def field(self, kind: str, ident: int, index: int, row: dict | None = None):
        """One column: from the scalar row when present, else from its own key."""
        row = row if row is not None else self.row(kind, ident)
        if index in row:
            return row[index]
        return self.raw(f"X-{kind}-{ident}-{index}")

    def _area_to_ui(self) -> dict[int, int]:
        lua = (QUESTIE / "support/Forever/Zones/areaIdToUiMapId.lua").read_text(encoding="utf8")
        mapping = {int(a): int(b) for a, b in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", lua)}
        with (SOURCE / "UiMapAssignment.csv").open(encoding="utf8") as handle:
            for row in csv.DictReader(handle):
                if int(row["AreaID"]) > 0:
                    mapping.setdefault(int(row["AreaID"]), int(row["UiMapID"]))
        return mapping

    def drop_rates(self) -> dict[int, dict[int, float]]:
        """Reference drop chances (percent) for quest-relevant items: item -> npc -> percent."""
        text = (QUESTIE / "support/Forever/DropTables/classicItemDrops.lua").read_text(encoding="utf8")
        rates: dict[int, dict[int, float]] = {}
        for item, body in re.findall(r"\[(\d+)\]\s*=\s*\{([^{}]*)\}", text):
            rates[int(item)] = {int(npc): float(p) for npc, p in re.findall(r"\[(\d+)\]\s*=\s*([\d.]+)", body)}
        return rates


def item_cache() -> list[dict]:
    return json.loads((SOURCE / "forever-items.json").read_text(encoding="utf8"))


def item_sources() -> dict[str, dict]:
    raw = json.loads((SOURCE / "itemSources.json").read_text(encoding="utf8"))
    if isinstance(raw, dict):
        raw = list(raw.values())
    return {s["key"]: s for s in raw}


def journal() -> dict:
    """Dungeon facts from the installed DungeonJournal addon (Lua tables -> dict)."""
    from lupa.lua51 import LuaRuntime

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        local function stub()
          local t = {}
          return setmetatable(t, {__index=function(self,k) local s=stub(); rawset(self,k,s); return s end, __call=function() return stub() end})
        end
        FDJ = stub(); FDJ.Constants = setmetatable({}, {__index=function() return {} end})
        """
    )
    ns = lua.eval("FDJ")
    # SharedLoot.lua and QuestUpdates.lua need the live game (they edit lists or build frames).
    for name in ("Dungeons.lua", "Bosses.lua", "DungeonEntrances.lua", "QuestChains.lua", "QuestMaps.lua", "QuestRewards.lua"):
        fn = lua.eval("loadstring")((JOURNAL / "Data" / name).read_text(encoding="utf8"), name)
        if isinstance(fn, tuple):
            raise RuntimeError(f"cannot compile {name}: {fn}")
        fn("ForeverDungeonJournal", ns)
    dump = lua.eval(
        """function(root)
          local seen = {}
          local function conv(v, depth)
            if type(v) == "table" then
              if seen[v] or depth > 9 then return nil end
              seen[v] = true
              local out = {}
              for k, x in pairs(v) do
                if type(k) == "string" or type(k) == "number" then out[k] = conv(x, depth + 1) end
              end
              seen[v] = nil
              return out
            elseif type(v) == "string" or type(v) == "number" or type(v) == "boolean" then return v end
            return nil
          end
          return conv(root, 0)
        end"""
    )

    def to_py(t):
        if hasattr(t, "items"):
            items = dict(t.items())
            if items and all(isinstance(k, int) for k in items):
                return [to_py(items[k]) for k in sorted(items)]
            return {str(k): to_py(v) for k, v in items.items()}
        return t

    return {"db": to_py(dump(ns["DB"])), "bossLevels": to_py(dump(ns["BOSS_LEVELS"]))}


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    import time

    start = time.time()
    q = Questie()
    print({k: len(v) for k, v in q.ids.items()}, "keys", len(q.meta), f"{time.time() - start:.1f}s")
    npc = sorted(q.ids["Npc"])[1500]
    print("npc", npc, q.row("Npc", npc), q.field("Npc", npc, 7))
    quest = sorted(q.ids["Quest"])[100]
    print("quest", quest, q.row("Quest", quest), q.field("Quest", quest, 2), q.field("Quest", quest, 10))
    item = 3041
    print("item", item, q.row("Item", item), q.field("Item", item, 2), q.field("Item", item, 14), q.field("Item", item, 6))
    obj = sorted(q.ids["Object"])[200]
    print("object", obj, q.row("Object", obj), q.field("Object", obj, 4))
    print("drop rates", len(q.drop_rates()))


ATLASLOOT = ADDONS / "AtlasLootClassic_DungeonsAndRaids"
_ATLAS_PRELUDE = r"""
local Dummy
Dummy = setmetatable({}, {
  __index = function() return Dummy end, __call = function() return Dummy end, __tostring = function() return "" end,
  __concat = function(a, b) if type(a) == "string" then return a elseif type(b) == "string" then return b end return "" end,
  __lt = function() return false end, __le = function() return false end, __len = function() return 0 end,
  __add = function(a, b) if type(a) == "number" then return a elseif type(b) == "number" then return b end return 0 end,
  __sub = function(a, b) if type(a) == "number" then return a elseif type(b) == "number" then return -b end return 0 end,
  __mul = function() return 0 end, __div = function() return 0 end, __mod = function() return 0 end, __unm = function() return 0 end,
})
local data, tokens = {}, 0
setmetatable(data, { __index = function() return function(self, name) tokens = tokens + 1; return { id = tokens, name = type(name) == "string" and name or "?" } end end })
local AL = setmetatable({}, { __index = function(_, k) return k end })
local AtlasLoot = setmetatable({
  ItemDB = { Add = function() return data end }, Locales = AL, CLASSIC_VERSION_NUM = 1,
  ReturnForGameVersion = function(...) for i = 1, select("#", ...) do local v = select(i, ...); if v ~= nil then return v end end end,
}, { __index = function() return Dummy end })
local G = setmetatable({ AtlasLoot = AtlasLoot, UnitFactionGroup = function() return "Alliance" end, string = string, table = table, math = math, pairs = pairs, ipairs = ipairs,
  type = type, select = select, tostring = tostring, tonumber = tonumber, setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
  unpack = table.unpack, next = next, format = string.format, print = function() end }, { __index = function() return Dummy end })
G._G = G
G.getfenv = function() return G end
return function(src, file)
  local f = assert(load(src, "@" .. file, "t", G))
  f("AtlasLootClassic_DungeonsAndRaids")
  return data
end
"""
ATLAS_RAIDS = {  # AtlasLoot key -> (name, group size)
    "MoltenCore": ("Molten Core", 40), "BlackwingLair": ("Blackwing Lair", 40), "Zul'Gurub": ("Zul'Gurub", 20),
    "TheRuinsofAhnQiraj": ("Ruins of Ahn'Qiraj", 20), "TheTempleofAhnQiraj": ("Temple of Ahn'Qiraj", 40), "Naxxramas": ("Naxxramas", 40),
    "MountHyjal": ("Hyjal Summit", 20), "BarrowDeepsRaid": ("Barrow Deeps", 20), "OnyxiasLairNew": ("Onyxia's Lair", 40), "WorldBosses": ("World Bosses", 40),
}


def atlasloot() -> dict:
    """Raid loot tables and measured drop rates from the installed AtlasLoot addon (GPL-2.0; only facts: item IDs, NPC IDs, percentages).

    Returns {"raids": {key: {"name", "players", "bosses": [{"name", "npc", "loot": [item ids]}]}}, "rates": {npc: {item: percent}}}.
    """
    import lupa

    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    run = lua.execute(_ATLAS_PRELUDE)
    data = run((ATLASLOOT / "data.lua").read_text(encoding="utf8"), "data.lua")

    def table(value):
        return value if lupa.lua_type(value) == "table" else None

    raids: dict[str, dict] = {}
    for key, (name, players) in ATLAS_RAIDS.items():
        instance = table(data[key])
        if not instance:
            continue
        bosses = []
        for index in range(1, len(table(instance["items"])) + 1):
            boss = table(instance["items"][index])
            if not boss:
                continue
            loot: list[int] = []
            for diff in boss.keys():
                rows = table(boss[diff])
                if lupa.lua_type(diff) != "table" or not rows:
                    continue  # only the per-difficulty loot lists are keyed by a difficulty token
                for i in range(1, len(rows) + 1):
                    row = table(rows[i])
                    item = row[2] if row else None
                    if isinstance(item, (int, float)) and item >= 100 and int(item) not in loot:
                        loot.append(int(item))
            label = boss["name"]
            bosses.append({"name": label if isinstance(label, str) else f"Boss {index}", "npc": int(boss["npcID"]) if isinstance(boss["npcID"], (int, float)) else None, "loot": loot})
        raids[key] = {"name": name, "players": players, "bosses": bosses}
    # the Forever Onyxia has no loot rows yet: show the classic table, marked as such
    classic = table(data["Onyxia"])
    if classic and "OnyxiasLairNew" in raids and not any(b["loot"] for b in raids["OnyxiasLairNew"]["bosses"]):
        loot = [int(table(row)[2]) for diff in table(classic["items"][1]).keys() if lupa.lua_type(diff) == "table" for row in table(classic["items"][1][diff]).values() if table(row) and isinstance(table(row)[2], (int, float)) and table(row)[2] >= 100]
        raids["OnyxiasLairNew"]["bosses"][0]["loot"] = list(dict.fromkeys(loot))
        raids["OnyxiasLairNew"]["fallback"] = "classic table"

    rates: dict[int, dict[int, float]] = {}
    text = (ATLASLOOT / "droprate.lua").read_text(encoding="utf8")
    for npc, body in re.findall(r"\[(\d+)\] = \{([^{}]*)\}", text):
        pairs = {int(item): float(p) for item, p in re.findall(r"\[(\d+)\] = ([\d.]+)", body)}
        if pairs:
            rates[int(npc)] = pairs
    return {"raids": raids, "rates": rates}


FOREVER_DATA = ADDONS / "LibForeverData" / "Data"


def forever_steps() -> dict[int, dict[str, list]]:
    """Quest notes and step hints from the LibForeverData addon (forever-db, CC BY 4.0 for its quest steps and notes).

    quest id -> {"tips": [text], "steps": [[type, text]]}; types: accept, turnin, loot, kill, craft, ... ("gotcha" rows become tips).
    """
    import urllib.parse

    text = (FOREVER_DATA / "Steps.lua").read_text(encoding="utf8")
    out: dict[int, dict[str, list]] = {}
    for line in text.splitlines():
        match = re.match(r"^(\d+)\t(.+)$", line)
        if not match:
            continue
        entry = out.setdefault(int(match.group(1)), {"tips": [], "steps": []})
        for raw in match.group(2).split("|"):
            parts = raw.split(":")
            if len(parts) < 8:
                continue
            kind, note = parts[2], urllib.parse.unquote(parts[7]).strip()
            if not note:
                continue
            if kind == "gotcha":
                entry["tips"].append(note)
            else:
                entry["steps"].append([kind, note])
    return {q: v for q, v in out.items() if v["tips"] or v["steps"]}


SKILLUP = ADDONS / "SkillUpForever" / "Data"


def recipes() -> dict:
    """Profession recipes from the installed SkillUp Forever addon (GPL-3.0; facts only: spell and item IDs, skill numbers, fees).

    Returns {"professions": {line: name}, "recipes": [{id, name, line, skill: [orange, yellow, green, grey], reagents: [[item, qty]],
    out: item or None, qty, fee, req, scroll: [item, skill]}]}.
    """
    import lupa

    def load(file: str, *names: str) -> dict:
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        ns = lua.eval("{}")
        lua.eval("function(src, ns) local f = assert(load(src, '@d')); return f('addon', ns) end")((SKILLUP / file).read_text(encoding="utf8"), ns)

        def py(value):
            if lupa.lua_type(value) != "table":
                return value
            keys = list(value.keys())
            if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
                return [py(value[k]) for k in sorted(keys)]
            return {str(k): py(value[k]) for k in keys}

        return {n: py(ns[n]) for n in names}

    thresholds_text = (SKILLUP / "Thresholds.lua").read_text(encoding="utf8")
    professions = {int(i): n for n, i, emitted in re.findall(r"^-- ([A-Za-z ]+) \((\d+)\): (\d+) emitted", thresholds_text, re.M) if int(emitted) > 0}
    names = {int(spell): (name.strip(), [int(a), int(b), int(c), int(d)])
             for spell, a, b, c, d, name in re.findall(r"^\t\[(\d+)\] = \{ (\d+), (\d+), (\d+), (\d+) \}, -- (.+)$", thresholds_text, re.M)}
    data = load("Recipes.lua", "RecipeData", "RecipeScrolls")["RecipeData"]
    scrolls = load("Recipes.lua", "RecipeScrolls")["RecipeScrolls"]
    fees = load("Trainer.lua", "TrainerFees")["TrainerFees"]
    out = []
    for spell, (name, skill) in names.items():
        row = data.get(str(spell))
        if not row:
            continue
        output = row.get("output")
        item = output.get("itemID") if isinstance(output, dict) else None
        quantity = output.get("quantity") if isinstance(output, dict) else None
        recipe = {"id": spell, "name": name, "line": int(row["skillLine"]), "skill": skill,
                  "reagents": [[int(r["itemID"]), int(r["quantity"])] for r in row.get("reagents") or [] if isinstance(r, dict)]}
        if item:
            recipe["out"] = int(item)
            if quantity and quantity != 1:
                recipe["qty"] = round(float(quantity), 2)
        if str(spell) in fees:
            recipe["fee"], recipe["req"] = int(fees[str(spell)][0]), int(fees[str(spell)][1])
        if str(spell) in scrolls:
            recipe["scroll"] = [int(scrolls[str(spell)][0]), int(scrolls[str(spell)][1])]
        out.append(recipe)
    return {"professions": professions, "recipes": out}
