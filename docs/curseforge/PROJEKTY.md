# Evertally na CurseForge — projekty (2026-11-20)

Evertally je od 0.11.20 rozdělený na **hlavní addon a šest modulů**. Každý je samostatný projekt na CurseForge.
Zipy vyrobí `python -I tools/package_addon.py` do `releases/curseforge/` (`<Projekt>-<verze>.zip`, seznam v `projects.json`).
Aplikace Evertally Sync dál instaluje všechno najednou z jednoho balíku na webu.

## Jak projekty propojit (dělá uživatel na CurseForge)

U projektu **Evertally**: *Relations* → přidat každý modul jako **Required Dependency**. CurseForge app je pak nainstaluje s ním.
U každého modulu: *Relations* → **Evertally** jako **Required Dependency** (modul bez jádra nefunguje).
U Dungeon Journal, Database a Recipes navíc nic: mapa (`Evertally_Map`) je součástí hlavního projektu.

V changelozích ani popisech nesmí být zmínka o Polestaru.

| Projekt | Složky v zipu | Závisí ve hře na |
|---|---|---|
| Evertally | Evertally, Evertally_Export, Evertally_Map, Evertally_Guide* | — |
| Evertally Meter | Evertally_Meter | Evertally |
| Evertally Loot Sparkles | Evertally_LootSparkles | Evertally |
| Evertally Bags | Evertally_Bags | Evertally |
| Evertally Dungeon Journal | Evertally_DungeonJournal | Evertally, Evertally_Map (načítá se s mapou) |
| Evertally Database | Evertally_Database | Evertally, Evertally_Map (načítá se s mapou) |
| Evertally Recipes | Evertally_Recipes | Evertally, Evertally_Map (načítá se s mapou) |

## Popisy (anglicky, pro stránky projektů)

### Evertally Meter
**Summary:** Damage meter, threat meter and tank view for WoW Forever, in clean windows of your own.

Open as many windows as you like, each with its own view: damage done, DPS, damage taken, enemies, avoidable damage,
healing, HPS, absorbs, interrupts, dispels and deaths — plus **Threat** (who has aggro on your target) and **Vanguard**
(your tanks' health). Hover a player for their spells and targets after the fight; click for the full breakdown.
Drag a window by its header, resize it from the corner, lock them all with one click.
Reads the game's own combat data. Part of Evertally — `/etally meter`, `/etally threat`.

### Evertally Loot Sparkles
**Summary:** Never walk past a quest item again — the loot sparkle stays on.

Keeps the sparkle on lootable quest items switched on, also after a graphics preset or the outline mode turns it off.
Switch it off and your own setting comes back. Part of Evertally (Settings → Combat).

### Evertally Bags
**Summary:** Bags in sections with search, #tags, tracked items and a fast loot window.

Your bags sorted into sections (new, quest, consumables, professions, gear, junk) or as a grid or list, with search and
#tags (#sell, #quest, #gear…), your own categories, tracked items next to your gold, Equip best, the bank and your alts
at a glance, and a fast loot window. Works with or instead of the game's bags. Part of Evertally — `/etally bag`.

### Evertally Dungeon Journal
**Summary:** Every dungeon and raid of WoW Forever: bosses, loot, quests, the way in.

Cards for every dungeon and raid, and inside each: the bosses with their abilities and tactics, the loot, the quests
you can take along, how to get there and the floors of the map. Part of Evertally; opens from its menu.

### Evertally Database
**Summary:** Search NPCs, quests, items and objects — and see where they are.

Look up any NPC, quest, item or object: where it is, what it drops or sells, what the quest gives, and show it on the
map or set the arrow to it. Part of Evertally; opens from its menu.

### Evertally Recipes
**Summary:** Every profession recipe of WoW Forever in one place.

All recipes by profession: what each makes, the materials, the skill it needs and turns orange, and where to learn it.
Part of Evertally; opens from its menu.
