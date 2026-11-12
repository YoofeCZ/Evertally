"""Compact data for the add-on's guide pages, from what the database build already wrote for the website (run it after build_db.py):

    python tools/build_guide_data.py

Writes addon/Evertally_Map/GuideData.lua with
    M.questRewards[questId] = {itemId, ...}       what a quest rewards (2,004 quests of the 5,232 the website knows)
    M.vendorStock[npcId]    = {itemId, ...}       what a vendor sells (1,107 vendors)
    M.recipeLines[professionId] = "Alchemy"       the twelve professions
    M.recipes = { {id, name, line, skill = {orange, yellow, green, grey}, out = itemId or nil, reagents = {{itemId, count}, ...}, req = skill to learn or nil} }
Also writes quest card metadata and item names/icons. Quest objectives and pickup/turn-in facts retain the provenance of the existing
local reference databases; no external guide articles or artwork are copied. See THIRD_PARTY.md.
"""
from pathlib import Path
import glob
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "platform" / "public" / "media" / "db"
OUT = ROOT / "addon" / "Evertally_Map" / "GuideData.lua"


def lua_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n") + '"'


def lua(value):
    if value is None: return "nil"
    if isinstance(value, bool): return "true" if value else "false"
    if isinstance(value, (int, float)): return str(value)
    if isinstance(value, str): return lua_string(value)
    if isinstance(value, list): return "{" + ",".join(lua(v) for v in value) + "}"
    return "{" + ",".join(k + "=" + lua(v) for k, v in value.items() if v not in (None, "", [])) + "}"


def main() -> None:
    rewards = {}
    stock = {}
    details = {}
    npcs = {}
    for path in sorted((DB / "npcs").glob("*.json")):
        npcs.update(json.loads(path.read_text(encoding="utf8")))
    for path in sorted(glob.glob(str(DB / "quests" / "*.json"))):
        for key, quest in json.load(open(path, encoding="utf8")).items():
            if quest.get("rewards"):
                rewards[int(key)] = [int(i) for i in quest["rewards"]]
            detail = {"name": quest.get("name"), "questLevel": quest.get("lvl"), "requiredLevel": quest.get("req"),
                      "faction": {"A": "Alliance", "H": "Horde"}.get(quest.get("fac"), "Both"),
                      "objective": "\n".join(quest.get("text", [])), "rewards": [[int(i), 1] for i in quest.get("rewards", [])]}
            for key_name, prefix in (("startNpc", "start"), ("endNpc", "turnin")):
                if quest.get(key_name):
                    npc = npcs.get(str(quest[key_name][0]), {})
                    detail[prefix + "Name"] = npc.get("name")
                    detail[prefix + "Location"] = (npc.get("zone") or "").replace("-", " ").title()
            details[int(key)] = detail
    # Preserve the source's distinction between choice and additional fixed rewards. Never infer it from a merged item relation.
    sys.path.insert(0, str(ROOT / "tools"))
    from db_sources import journal
    journal_items = {}
    for dungeon in journal()["db"].values():
        for quest in dungeon.get("quests", []):
            if not quest.get("id"): continue
            detail = details.setdefault(int(quest["id"]), {})
            detail.update({"name": quest.get("name"), "requiredLevel": quest.get("requires"), "questLevel": quest.get("level"),
                           "faction": quest.get("faction"), "objective": quest.get("objective"),
                           "startName": quest.get("pickup"), "turninName": quest.get("turnin"),
                           "xpBase": quest.get("liveXPFallback"), "rewardSummary": quest.get("rewardSummary")})
            main = quest.get("rewardItems") or []
            fixed = quest.get("additionalRewardItems") or []
            def reward_rows(rows):
                out = []
                for item in rows:
                    if not isinstance(item, list) or not item or not isinstance(item[0], int): continue
                    out.append([item[0], 1])
                    if len(item) > 1: journal_items[item[0]] = {"name": item[1], "quality": item[2] if len(item) > 2 else None}
                return out
            main_rows, fixed_rows = reward_rows(main), reward_rows(fixed)
            if main_rows or fixed_rows:
                detail.pop("rewards", None)
                detail["choice"] = main_rows if quest.get("rewardChoice") else []
                detail["guaranteed"] = fixed_rows if quest.get("rewardChoice") else main_rows + fixed_rows
    for path in sorted(glob.glob(str(DB / "npcs" / "*.json"))):
        for key, npc in json.load(open(path, encoding="utf8")).items():
            if npc.get("sells"):
                stock[int(key)] = [int(i) for i in npc["sells"]]
    recipes = json.load(open(DB / "recipes.json", encoding="utf8"))
    lines = ["local _, M = ...",
             "-- Generated from the local website reference database and installed DungeonJournal; see THIRD_PARTY.md. No artwork is copied.",
             "M.questRewards = {"]
    for quest in sorted(rewards):
        lines.append("    [%d] = {%s}," % (quest, ",".join(str(i) for i in rewards[quest])))
    lines += ["}", "M.vendorStock = {"]
    for npc in sorted(stock):
        lines.append("    [%d] = {%s}," % (npc, ",".join(str(i) for i in stock[npc])))
    lines += ["}", "M.recipeLines = {"]
    for key, name in sorted(recipes["professions"].items(), key=lambda kv: int(kv[0])):
        lines.append("    [%d] = %s," % (int(key), lua_string(name)))
    lines += ["}", "M.recipes = {"]
    for recipe in recipes["recipes"]:
        reagents = ",".join("{%d,%d}" % (r[0], r[1]) for r in recipe.get("reagents", []))
        skill = ",".join(str(int(s)) for s in recipe.get("skill", []))
        extra = ""
        if recipe.get("out"):
            extra += ",out=%d" % recipe["out"]
        if recipe.get("req"):
            extra += ",req=%d" % int(recipe["req"]) if isinstance(recipe["req"], int) else ""
        lines.append("    {id=%d,name=%s,line=%d,skill={%s},reagents={%s}%s}," % (recipe["id"], lua_string(recipe["name"]), recipe["line"], skill, reagents, extra))
    lines.append("}")
    lines.append("M.questDetails = {")
    for ident, detail in sorted(details.items()): lines.append("    [%d]=%s," % (ident, lua(detail)))
    lines.append("}")
    items = {}
    for path in sorted((DB / "items").glob("*.json")):
        for key, value in json.loads(path.read_text(encoding="utf8")).items():
            icon = value.get("icon")
            if isinstance(icon, str) and icon.startswith("client:"): icon = int(icon.split(":")[1])
            elif isinstance(icon, str): icon = "Interface\\Icons\\" + icon
            items[int(key)] = {"name": value.get("name"), "icon": icon, "quality": value.get("q")}
    for ident, meta in journal_items.items():
        target = items.setdefault(ident, {})
        for key, value in meta.items():
            if target.get(key) is None and value is not None: target[key] = value
    lines.append("M.itemGuide = {")
    for ident, meta in sorted(items.items()): lines.append("    [%d]=%s," % (ident, lua(meta)))
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf8")
    print(f"quest cards: {len(details)}, item metadata: {len(items)}, vendors: {len(stock)}, recipes: {len(recipes['recipes'])} -> {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
