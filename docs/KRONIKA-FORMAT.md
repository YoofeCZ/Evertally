# Kronika — formát záznamu cesty (v1)

Tohle je zadání pro toho, kdo píše **zápis záznamu v addonu** (a převod v aplikaci). Webový přehrávač je hotový a umí
přehrát cokoli, co tomuto formátu odpovídá. Chybí zdroj skutečných dat.

**Zdroj pravdy je kód, ne tento text:**

- typy a kontrola souboru: [`platform/lib/chronicle.ts`](../platform/lib/chronicle.ts) (`parseChronicle`, `findProblem`),
- testy: [`platform/tests/chronicle.test.ts`](../platform/tests/chronicle.test.ts),
- přehrávač: [`platform/components/evertally/views/Chronicle*.tsx`](../platform/components/evertally/views/).

Když se tento dokument a kód rozcházejí, platí kód. Příklady v [`docs/kronika/`](kronika/) hlídá test, takže vždy projdou.

## 1. Co je ověřené a co ne

Rozlišuj **změřeno / ověřeno** od **domněnky**. Tabulka u každého zdroje dat říká, v jakém stavu je.

Údaje o herním API jsou ze **zdrojových deklarací Forever 1.60.1.70862** (Blizzard UI, commit `9dc84f0d`), tedy z toho, co
klient *deklaruje*. Nic z toho není vyzkoušené ve hře. Podle pravidel projektu platí: *deklarace není důkaz, že addon k datům
smí a že fungují*.

| Co potřebujeme | Zdroj ve Forever API | Stav |
|---|---|---|
| poloha | `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition` | deklarováno, nevyzkoušeno |
| čas | `GetServerTime`, `GetTime` | deklarováno, nevyzkoušeno |
| quest přijat / odevzdán | `QUEST_ACCEPTED`, `QUEST_TURNED_IN` | deklarováno, nevyzkoušeno |
| quest opuštěn | `QUEST_REMOVED`, `AbandonQuest` | deklarováno, nevyzkoušeno; **neověřeno, jestli jde opuštění odlišit od odevzdání** (`QUEST_REMOVED` přichází pravděpodobně v obou případech) |
| loot, peníze | `CHAT_MSG_LOOT`, `CHAT_MSG_MONEY`, `LOOT_OPENED` | deklarováno, nevyzkoušeno |
| zkušenosti | `CHAT_MSG_COMBAT_XP_GAIN`, `PLAYER_XP_UPDATE` | deklarováno, nevyzkoušeno |
| level | `PLAYER_LEVEL_UP` | deklarováno, nevyzkoušeno |
| dovednosti | `CHAT_MSG_SKILL` (`PLAYER_SKILL_UPDATE` **nenalezen**) | deklarováno, nevyzkoušeno |
| změna zóny | `ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD` | deklarováno, nevyzkoušeno |
| let (letecká cesta) | `TAXIMAP_OPENED`, `TAXIMAP_CLOSED`, `UnitOnTaxi` | deklarováno, nevyzkoušeno |
| skupina | `GROUP_ROSTER_UPDATE` | deklarováno, nevyzkoušeno |
| instance | `GetInstanceInfo`, `UPDATE_INSTANCE_INFO` | deklarováno, nevyzkoušeno |
| bossové | `ENCOUNTER_START`, `ENCOUNTER_END`, `BOSS_KILL` | deklarováno, nevyzkoušeno |
| smrt, boj | `PLAYER_DEAD`, `PLAYER_REGEN_DISABLED/ENABLED` | deklarováno, nevyzkoušeno |
| PvP | `UPDATE_BATTLEFIELD_STATUS`, `UPDATE_BATTLEFIELD_SCORE`, `PVP_MATCH_COMPLETE`, `CHAT_MSG_COMBAT_HONOR_GAIN` | deklarováno, nevyzkoušeno |
| vlastní kouzla | `UNIT_SPELLCAST_SUCCEEDED` | deklarováno, nevyzkoušeno |
| **bojový log** | `COMBAT_LOG_EVENT_UNFILTERED` | deklarováno **s `HasRestrictions: true`**; addon se mu na Forever **záměrně vyhýbá** (komentář v `Combat.lua`, viz níže) |
| `CombatLogGetCurrentEventInfo` | — | **v deklaracích Forever nenalezeno, ověřit** |
| souhrny z vestavěného měřiče | `C_DamageMeter.*` | deklarováno; dotazy na relace jsou označené `SecretWhenInCombat`, tedy za boje mohou vracet **tajné hodnoty** |

### Co už addon dnes dělá (zjištěno čtením kódu 2026-11-15)

Čtením zdrojů v `addon/Evertally/`, ne spuštěním hry. Na tom má Kronika stavět, ne to dělat znovu.

| Co | Kde | Jak |
|---|---|---|
| trasa | `People.lua` (`A.SampleTrack`) | vzorek po **4 s**, souřadnice na 3 desetinná místa, nový bod až po pohybu ≥ 0,002 (jinak tep po 120 s). Úsek se uzavírá při změně mapy, po 60 s bez vzorku a po 100 bodech; odchozí fronta drží nejvýš 500 úseků. Ve výchozím stavu **vypnuto** (oblast `own_track`). V instancích a na načítacích obrazovkách pozice není a úsek končí. |
| formát trasy | událost `track.path` | `{ mapId (uiMapID), mapSystem: "ui_map", startedAt (GetServerTime), points: [[sekundy od startedAt, x, y], …] }` |
| zóny | `Collectors.lua` | `zone.visited` `{ mapId, mapName }` |
| loot | `Collectors.lua` | `loot.received` `{ itemId, name, quantity, sourceNpcId, … }` |
| level | `Collectors.lua` | `character.level` (snímek postavy s `level`) |
| instance a bossové | `Runs.lua` | `instance.entered`, `run.interrupted`; `raid.encounter_finished` `{ encounterId, name, success, durationMs, instanceId, instanceName }` z `ENCOUNTER_START/END` |
| questy | `Collectors.lua`, `QuestGuide.lua` | zachytávají `QUEST_ACCEPTED`, `QUEST_TURNED_IN`; **neověřeno**, jestli z toho vzniká záznam použitelný pro Kroniku |
| souhrny souboje | `Combat.lua` | viz níže |
| obálka každé události | `Core.lua` (`A.Record`) | `{ schemaVersion, eventId: producerId:sessionId:pořadí, producerId, kind, observedAt (= GetServerTime), game, character, payload, evidence }` |

**Nezapisuje se dnes:** peníze, zkušenosti, zabití, dovednosti, smrt (mimo `Combat.lua`), skupina (jen živé spojení), PvP (žádná
událost bojiště), lety, kvalita předmětu.

**Úložiště historie je dimenzované na tisíce událostí** (`MAX_EVENTS` 5 000, tvrdý strop 6 000, odchozí fronta 4 000, trasy 500).
Kronika s tisíci bodů trasy a stovkami událostí na hodinu hraní by to vyčerpala. Potřebuje **vlastní úložiště s vlastními limity**.

`A.sessionId` se vytváří při **každém načtení addonu** (`/reload` i přihlášení), nejde tedy o „hrací sezení“. Pro `sessions`
je potřeba sousední `sessionId` s malou mezerou sloučit (viz bod 3d).

### Bojový log na Forever: addon se mu záměrně vyhýbá

V `Combat.lua` je komentář: *„Forever exposes legacy API stubs, but registering CLEU is restricted and can show
ADDON_ACTION_FORBIDDEN even when RegisterEvent is inside pcall. Only positively identified pre-Forever Classic clients may use it.“*
Kód proto na Forever `COMBAT_LOG_EVENT_UNFILTERED` **vůbec neregistruje**. Místo toho čte `C_DamageMeter` **po boji** (mimo
`InCombatLockdown`), bere jen čitelné hodnoty a nečitelné označí jako `partial`. Odkud komentář pochází (zkušenost ze hry, nebo
četba deklarací), **není zapsáno**.

Z měřiče addon dnes bere jen **součty po hráčích a metrikách** za relaci: `DamageDone`, `HealingDone`, `Absorbs`, `DamageTaken`,
`Interrupts`, `Dispels`, `Deaths`. Po kouzlech (`combatSpells` z `C_DamageMeter.GetCombatSessionSourceFromID`) nečte; **jestli jsou
po boji čitelná, je neověřené**. Časovou osu souboje (kdo kdy co) rozhraní měřiče neobsahuje vůbec.

Důsledek pro formát, tedy co je na Forever **realistické**:

| Údaj | Realisticky na Forever |
|---|---|
| `fights[].me`, `group` (součty) | ano, z měřiče po boji (ve hře neověřeno) |
| `me.dealt`, `healed`, `took` (po kouzlech) | **možná**, jen když se `combatSpells` po boji čte; **ověřit** |
| `series` (graf po 5 s) | **ne**, měřič nemá časovou osu |
| `log` (tah po tahu) | **pravděpodobně ne**, bojový log je na Forever omezený |
| `marks` | částečně: smrt a konec souboje z `PLAYER_DEAD`, `ENCOUNTER_*` |

Přehrávač tomu odpovídá: záložky **Kouzla**, **Průběh** a **Tahy** se zobrazí **jen tehdy, když mají data**. Záznam bez nich
zůstane platný a ukáže Přehled a Skupinu. Záložka Tahy a graf jsou tedy pro Forever **dnes spíš ukázka toho, co by šlo**, než
něco, co addon naplní.

**Jediný ověřovací pokus, který ještě dává smysl:** v testovacím addonu po boji zavolat
`C_DamageMeter.GetCombatSessionSourceFromID` pro vlastní postavu a zjistit, jestli jsou `combatSpells[].spellID` a `totalAmount`
čitelné. Výsledek **zapsat sem** (i záporný).

## 2. Soubor

JSON v UTF-8, jeden objekt. Web ho přijme přetažením na stránku `#chronicle`, limit **40 MB**. Neznámá **pole** se ignorují (nekontrolují),
takže lze přidávat nová volitelná pole. Neznámý **druh události** (`k`) se naopak odmítne: nový druh vyžaduje změnu kódu
na webu. Změna významu stávajícího pole by byla **v2**.

```
{ "v": 1, "character": {...}, "startedAt": 0, "duration": 0, "zones": [...], "path": [...], "events": [...],
  "sessions"?: [...], "stats"?: [...], "skills0"?: {...}, "fights"?: [...] }
```

### Kontrola před odevzdáním

```bash
cd platform
node scripts/check-chronicle.mjs cesta/k/zaznamu.json
```

Výstup `OK ...` se souhrnem, nebo `REJECTED: events[1432]` s místem první chyby. Kód 0 znamená, že web soubor otevře.

### Čas

Všechny časy `t` jsou **sekundy odehraného času od začátku záznamu** (ne hodiny na stěně, ne `GetTime()` surově).
Mezery, kdy hráč nehrál, se do `t` nepočítají. `duration` je délka záznamu v těchto sekundách.

Skutečné datum a čas dává `sessions`: `{ "t": 5400, "at": 1794400000 }` znamená „od odehrané sekundy 5400 platí, že na hodinách
bylo `at` (unix, sekundy)“. Z toho web ukazuje „10. 11. 12:45“ a kalendář dnů. Bez `sessions` platí `startedAt + t`.
Nové sezení = nové přihlášení nebo přestávka delší než několik minut (rozhodnutí je na zapisovači, web ho nevynucuje).

### Záhlaví

| Pole | Typ | Poznámka |
|---|---|---|
| `v` | `1` | povinné |
| `character.name` | text ≤ 64 | povinné |
| `character.classId` | číslo | povinné; 1 Warrior … 11 Druid; podle `CLASSES` v `platform/components/evertally/data.ts` |
| `character.raceId` | celé číslo | volitelné, pro ikonu rasy |
| `character.race`, `faction`, `realm`, `guild` | text ≤ 80 | volitelné |
| `character.level` | číslo | úroveň na začátku záznamu |
| `startedAt` | číslo | unix čas začátku, sekundy |
| `duration` | číslo > 0 | sekundy |
| `zones` | seznam textů, 1 až 500 | klíče map z `platform/public/media/maps/manifest.json`, tvar `^[a-z0-9][a-z0-9-]{0,79}$` (například `darkshore`) |

`zones` jsou **klíče obrázků map**, ne `uiMapID`. Převod `uiMapID → klíč` je v `manifest.json` (`uiMapIds`).
Zóna bez obrázku se na webu zobrazí jako prázdná plocha, ale záznam zůstane platný.

### `path` — trasa

Seznam vzorků `[t, zóna, x, y]`: `t` sekundy, `zóna` index do `zones`, `x` a `y` v rozsahu **0 až 1** uvnitř té zóny
(souřadnice mapy zóny, ne světa). Zaokrouhlit na 4 desetinná místa.

- Vzorek každé **2 s**, když se postava hýbe; nehybná postava vzorky nepotřebuje.
- Mezera delší než 15 s mezi vzorky = postava „stojí“ na posledním místě (web neinterpoluje přes mezeru ani přes změnu zóny).
- `t` neklesá. Nejvýš **400 000** vzorků.
- Změřeno na ukázce: **23 B na vzorek**, 3 014 vzorků za 122 minut.

### `events` — co se stalo

Seznam seřazený podle `t`, nejvýš **200 000**. Každá událost má `t`, `k` (druh) a `text` (≤ 160 znaků).
Volitelná pole: `a` (≤ 24, podtyp), `n`, `max`, `xp` (čísla), `q` (kvalita předmětu 0 až 5), `id` (kladné celé),
`zone` + `x` + `y` (kde, stejně jako ve `path`), `d` (sekundy, ≥ 0), `detail` (≤ 300), `f` (index do `fights`).

| `k` | `a` | Co znamená a která pole se používají |
|---|---|---|
| `quest` | `accept` / `done` / `turnin` / `abandon` | `text` název, `id` questID, `xp` u odevzdání. Do „questů hotovo“ se počítá `turnin`. |
| `kill` | — | `text` jméno, `xp`. V PvP `detail` „Honorable kill“. |
| `loot` | — | `text` název předmětu, `n` počet, `q` kvalita 0 až 5, `id` itemID (podle něj web najde ikonu). |
| `money` | — | `n` **měďáky**, může být záporné (útrata). |
| `level` | — | `n` nová úroveň. |
| `skill` | — | `text` název dovednosti, `n` hodnota, `max` maximum. |
| `zone` | — | vstup do zóny: `zone` je nová zóna. Z nich se počítají „místa“. |
| `death` | — | `text` například „You died“. |
| `dungeon` | `enter` / `leave` | `text` název instance, `detail` například „Dungeon · Normal“, „Raid · 25-player Heroic“, „Battleground“. Dvojice enter/leave tvoří pás na časové ose a kartu instance. |
| `travel` | `flight` / `hearth` / `portal` | `text` popis. |
| `group` | `join` / `leave` | `text`. |
| `emote` | — | `text`. |
| `boss` | `kill` / `wipe` | **uzavírá souboj**: `text` boss, `n` číslo pokusu, `d` délka v sekundách, `f` index do `fights`, `detail` jedna věta. Má být v čase **konce** souboje. |
| `pvp` | `win` / `loss` | totéž pro bojiště nebo arénu. |

Co web dělá s `xp`: sčítá `xp` ze **všech** událostí, které ho mají (zabití i quest). Žádnou událost nezdvojuj, jinak se XP sečte dvakrát.

### `fights` — okno události

Souboj je záznam o jedné události (boss, bojiště). Odkazuje se na něj z `boss` / `pvp` události přes `f`. Seznam musí být seřazený
podle `t` (kontroluje se). Souboje by se **neměly překrývat** (nekontroluje se; přehrávač by pro živý ukazatel vybral jen jeden).
Nejvýš 5 000.

```
{ "t": 10, "d": 30, "kind": "boss"|"pvp", "name": "...", "result": "kill"|"wipe"|"win"|"loss",
  "zone"?, "difficulty"?, "size"?, "attempt"?,
  "me": { "dmg", "heal", "taken", "deaths", "interrupts"?, "dispels"?, "dealt": [SpellRow], "healed": [SpellRow], "took": [SpellRow] },
  "group"?: [Member], "series"?: {...}, "marks"?: [...], "pvp"?: {...},
  "actors"?, "spells"?, "log"? }
```

`t` je začátek souboje (sekundy záznamu), `d` délka.

| Část | Obsah | Limit |
|---|---|---|
| `SpellRow` | `{ name ≤ 60, total, casts, hits?, crits?, max?, school? }`; `school`: `physical`, `nature`, `fire`, `frost`, `shadow`, `arcane`, `holy` | 300 řádků |
| `Member` | `{ name, classId, role?: tank/healer/dps, dmg, heal, taken, deaths?, me? }`; přesně jeden člen má `me: true` | 80 členů |
| `series` | `{ step, dmg[], heal?[], taken? [] }` po `step` sekundách (5), jen za postavu; **součet řady má sedět se součtem v `me`** | 5 000 hodnot |
| `marks` | `{ t (sekundy od začátku souboje), kind: death/cooldown/phase/interrupt/lust, text }` | 500 |
| `pvp` | `{ score?: [naše, jejich], kills, deaths, assists?, objectives?, honor? }` | — |

**Bojový log** (`actors`, `spells`, `log`), pokud ho jde získat:

- `actors`: `{ name ≤ 40, side: "me"|"party"|"enemy", classId?, role?, boss? }`, nejvýš 100. Index v seznamu je identita; `0` je postava.
- `spells`: `{ name ≤ 60, school? }`, nejvýš 1 000; na jeho indexy odkazuje `log`.
- `log`: řádky `[t, kdo, na koho, druh, kouzlo, množství, krit]`:
  - `t` sekundy **od začátku souboje**, neklesající, ≤ `d + 1`,
  - `kdo`, `na koho`: index do `actors`; `na koho` = `-1` = nikdo,
  - `druh`: index do `["dmg","heal","cast","aura","interrupt","dispel","death"]`,
  - `kouzlo`: index do `spells`, `-1` = žádné (smrt),
  - `množství`: číslo ≥ 0 (u `aura` třeba doba trvání), `krit`: `0` nebo `1`.
- Nejvýš **50 000** řádků na souboj a **300 000** v souboru. Změřeno na ukázce: **21 B na řádek**, 6 586 řádků za 5 soubojů.

**Pravidlo konzistence** (web ho nekontroluje, ale přehrávač ukazuje čísla z obou míst vedle sebe): `me.dmg` = součet `dmg` řádků,
kde `kdo = 0`; `me.heal` totéž pro `heal`; `me.taken` = součet `dmg` řádků, kde `na koho = 0`. `dealt`/`healed`/`took` jsou ty samé
řádky sečtené po kouzlech. Ukázka v `platform/lib/chronicle.ts` (`makeFight`) všechno sčítá z logu, takže se nerozchází.
Bez logu se tyto součty berou z jiného zdroje (měřič); pak se záložka **Tahy** na webu nezobrazí.

### `stats`, `skills0`

- `stats`: `[{ t, ilvl?, attrs?: [[název, hodnota]], enh?: [[název, text]] }]`. Levý panel ukazuje poslední snímek ≤ aktuální čas.
  Doporučení: snímek na začátku a při změně úrovně nebo výbavy.
- `skills0`: dovednosti na začátku záznamu, `{ "Herbalism": [41, 150] }`. Změny pak ukazují události `skill`.

## 3. Co web z toho počítá (ať to zapisovač nedělá dvakrát)

- „Zatím“: questy hotovo (počet `quest/turnin`), zabití (počet `kill`), XP (součet `xp`), peníze (součet `money.n`), předměty
  (součet `loot.n`), místa (různé zóny), smrti, úroveň (poslední `level`, jinak `character.level`).
- Kalendář dnů z `sessions`. Souhrn instance z `dungeon` + událostí uvnitř.
- Zvuky a zprávy nad postavou z událostí. Výchozí filtr kvality skrývá loot pod „neobvyklé“ (jen v seznamech).

## 3b. Převod z toho, co addon už zapisuje

Doporučené je **nezakládat druhý záznam téhož**, ale složit Kroniku z existujících událostí a doplnit jen to, co chybí.

**Web to pro vlastní postavy už dělá sám** (od 15. 11. 2026): `GET /api/chronicle?profile=…&days=7|14|30` skládá záznam z událostí, které server už
má (`platform/lib/chronicle-build.ts`, `composeChronicle`), a stránka **Kronika** v menu ho přehraje. Čte jen to, co dovolují souhlasy
majitele (trasa = „Moje trasa“, dungeony a bossové = „Moje běhy“, ostatní = „Moje postava“) a jen jeho vlastní postavy. Doba bez
události delší než 5 minut ukončí sezení. Co server neukládá (zabití, peníze mimo odměny za quest, dovednosti, smrt, kvalita předmětu,
souhrny po bossech), v záznamu **není** a nic se nedomýšlí; `loot` bez kvality se zobrazí bez ohledu na filtr kvality. Vynechané
jsou i `fights[]`, protože server nemá číslování po soubojích. Soubor z addonu (bod 2) tedy **doplňuje** to, co web složí sám.

| Z čeho | Na co | Pravidla |
|---|---|---|
| `track.path` | `path` | `zóna` = index klíče z [`kronika/mapy.json`](kronika/mapy.json) podle `mapId`; mapa bez klíče: úsek vynechat. Bod `[dt, x, y]` → `[t, zóna, x, y]`, kde `t` = čas bodu převedený podle bodu 5. Vzorky po 4 s jsou v pořádku (příklad v dokumentu používá 2 s, web interpoluje). |
| `zone.visited` | `zone` | `text` = „Entered <mapName>“, `zone` = klíč mapy. |
| `loot.received` | `loot` | `itemId`→`id`, `name`→`text`, `quantity`→`n`. **Kvalitu `q` addon nezapisuje**: doplnit při zachycení (`GetItemInfo`, **neověřeno** pro Forever), jinak vynechat (web bere 1 = obyčejný). |
| `character.level` | `level` | jen při změně úrovně, `n` = nová úroveň. |
| `instance.entered` | `dungeon` + `enter` | `text` název, `detail` typ a obtížnost. Konec: `run.interrupted` nebo dokončení běhu → `dungeon` + `leave`. |
| `raid.encounter_finished` | `boss` | `success` → `kill` / `wipe`, `d` = `durationMs / 1000`, `text` = `name`. Spolu s `fights[]` ze součtů `run.combat` (viz bod 2, `fights`). |
| **nově** | `quest`, `kill`, `money`, `skill`, `death`, `group`, `travel`, `pvp` | dnes se nezapisují (viz „Nezapisuje se dnes“). |

## 3c. Tabulky ID

**Třídy** (`character.classId`) a **rasy** (`character.raceId`), tak jak je zná web (`platform/components/evertally/data.ts`):

| classId | třída | | raceId | rasa |
|---|---|---|---|---|
| 1 | Warrior | | 1 Human, 2 Orc, 3 Dwarf, 4 Night Elf | |
| 2 | Paladin | | 5 Undead, 6 Tauren, 7 Gnome, 8 Troll | |
| 3 | Hunter | | 9 Goblin, 10 Blood Elf, 11 Draenei, 22 Worgen | |
| 4 | Rogue | | 24, 25, 26 Pandaren | |
| 5 | Priest | | 95 High Order Skyborne | |
| 6 | Death Knight | | 96 Windshaper Skyborne | |
| 7 | Shaman, 8 Mage, 9 Warlock, 10 Monk | | | |
| 11 | Druid, 12 Demon Hunter, 13 Evoker | | | |

Ikony tříd jsou jen pro 1, 2, 3, 4, 5, 7, 8, 9, 11 a ikony ras jen pro 1 až 9, 95 a 96; ostatní se zobrazí jako otazník.

**Mapy:** [`kronika/mapy.json`](kronika/mapy.json) je tabulka `klíč → uiMapID` z katalogu webu. Generuje ji
`node scripts/write-chronicle-maps.mjs` (ve složce `platform`) a test hlídá, že odpovídá katalogu. Jedna zóna může mít
víc `uiMapID`; `mapId` z `track.path` se hledá v seznamu `uiMapIds`.

## 3d. Sezení, `/reload` a ukládání

- **Čas `t`** je sekundy odehraného času. Skládá se z **hracích sezení**. Jedno hrací sezení je řada po sobě jdoucích načtení
  addonu (`sessionId`), mezi kterými je mezera kratší než **5 minut** (`/reload`, pád hry); delší mezera nebo odhlášení = nové sezení.
  Hodnota 5 minut je **návrh**, ne ověřené.
- `sessions[i].t` = součet délek dřívějších sezení, `sessions[i].at` = `GetServerTime` jeho začátku. Délka sezení = poslední
  `observedAt` minus první.
- **Souboj přerušený `/reload`:** nezapisovat jako `boss`/`pvp` událost s vymyšleným výsledkem. Souboj zahodit (nebo zapsat bez
  události), ostatní události ponechat.
- SavedVariables se ukládají jen při `/reload` a odhlášení (stejně jako dnešní trasa). Při pádu hry se ztratí vše od posledního uložení;
  to je omezení hry, ne zapisovače.
- Zapisovat do vlastního úložiště (vlastní SavedVariables nebo vlastní větev, **ne** do `A.db.events`), s vlastním stropem velikosti.
  Velikost SavedVariables, kterou hra snese, **není změřená**.

## 4. Soukromí

Trasa je **historie pohybu hráče**. Záznam je ve výchozím stavu **jen místní soubor**. Web ho čte v prohlížeči a nic neposílá.
Nahrávání na server (viz otevřené otázky) smí vzniknout jen s výslovným souhlasem hráče a s možností smazání. Do záznamu
nepatří cizí hráči s jejich polohou: protivníci a členové skupiny se objevují **jen jménem a čísly souboje**, ne trasou.
Oblast `own_track` je dnes ve výchozím stavu **vypnutá**; Kronika ji musí respektovat (bez souhlasu s trasou se trasa nezapisuje).

## 5. Velikost

Změřeno na ukázce (122 minut, vygenerovaná data, **ne skutečný hráč**): **299 kB** celkem.
Trasa 67 kB, události 78 kB (913 událostí, 88 B na událost), souboje 152 kB (6 586 řádků logu).
Skutečný záznam bude jiný: u raidu o 25 lidech jsou řádky logu v řádu desítek tisíc na pokus a limit 50 000 se dá překročit.
Odhad skutečných velikostí **neexistuje**, dokud se nezapíše první skutečný záznam.

## 6. Příklady

- [`kronika/priklad-minimalni.json`](kronika/priklad-minimalni.json): nejmenší smysluplný záznam (trasa, quest, zabití, loot, peníze, level).
- [`kronika/priklad-souboj.json`](kronika/priklad-souboj.json): dungeon s bossem, skupina, kouzla, graf, značky, bojový log po tazích, sezení, staty.

## 7. Doporučený postup práce

Stavět od jistého k riskantnímu. Každá fáze je samostatně použitelná a přehrávač ji zobrazí.

| Fáze | Obsah | Závisí na |
|---|---|---|
| **A** | Převod toho, co addon už zapisuje (`track.path`, `zone.visited`, `loot.received`, `character.level`, `instance.entered`): **trasa, zóny, loot, level, instance, sezení**. Žádná nová událost ve hře. | jen na převodu (bod 3b) |
| **B** | Nové zachytávání: `quest` (přijat/odevzdán), `money`, `kill`, `death`, `skill`, `group`, `travel`, kvalita předmětu | události z bodu 1; zabití z textové zprávy o XP bude pravděpodobně záviset na jazyce klienta (**neověřeno**) |
| **C** | `boss` události a `fights[]` **se součty** z `run.combat` / `C_DamageMeter` (okno Přehled a Skupina) | součty z měřiče po boji; kouzla jen po ověření pokusu z bodu 1 |
| ~~D~~ | `fights[].log` a `series` | **pravděpodobně nemožné na Forever** (viz bod 1); nezačínat, dokud to někdo neprokáže |

Poznámky:

- Fáze A nemění nic ve hře, jen přidá převod. Je to nejrychlejší cesta k prvnímu **skutečnému** záznamu a k změření skutečných velikostí.
- Při `/reload` a odhlášení se SavedVariables ukládají; záznam se do souboru dostane až tehdy.
- Zapisovat průběžně do **kruhového bufferu** v paměti a při ukládání ho přesunout do SavedVariables; neukládat každý vzorek zvlášť.

## 7b. Zkušební plán

- **Bez hry:** repo už má opakovatelný vzor, `tests/lua/test_*.py` (například `test_combat_runs.py`) spouští Lua přes `lupa` s falešnými
  událostmi. Pro Kroniku: přehrát vymyšlený průběh (trasa, loot, level, instance, boss), výsledek převést a pustit
  `node scripts/check-chronicle.mjs`. Test, který **sám sebe potvrzuje**, nic nedokazuje: aspoň jednou záměrně rozbít vstup
  (špatná mapa, záporný čas) a vidět, že kontrola spadne.
- **Ve hře:** hodinu normálního hraní, soubor otevřít na `#chronicle`, porovnat „Zatím“ s tím, co hráč skutečně udělal.
- **Zápis do textu práce:** které položky z tabulky v bodě 1 se podařilo ve hře vyzkoušet a které ne.

## 8. Otevřené otázky (potřebují rozhodnutí)

1. **Kdo převádí** existující události (`track.path`, `zone.visited`, …) na tento soubor: addon, nebo Windows aplikace? Aplikace už čte
   export a zná `manifest.json`; addon zná hru. Zatím **nerozhodnuto**.
2. **Kam se záznam dostane** na web? Dnes jen přetažením souboru. Nahrání na server **není navržené ani postavené**. Omezení:
   databáze D1 na bezplatném tarifu Cloudflare povoluje **100 000 zapsaných řádků denně** (limit byl 14. 11. 2026 skutečně
   vyčerpán živou polohou). Záznam by proto musel jít jako **jeden objekt na sezení**, ne jako řádky po událostech.
3. **Retence**: kolik sezení / jak dlouho se drží.
4. **Souhlas a sdílení** (odkaz, přátelé, veřejně): stejný model jako sdílení polohy, ale pro záznam zatím neexistuje.
5. **Výsledek pokusu s `combatSpells` po boji** (bod 1): rozhodne, jestli okno Kouzla bude mít na Forever skutečná data.
6. **Zdroj komentáře o `ADDON_ACTION_FORBIDDEN`** v `Combat.lua`: je to zkušenost ze hry? Pokud ano, je to nejsilnější doklad pro fázi D.
7. **Velikost SavedVariables**, kterou hra snese bez zpomalení načítání, není změřená.

## 9. Přijetí práce na addonu

Hotovo je, když:

- [ ] `node scripts/check-chronicle.mjs` dává `OK` pro záznam z reálné hry (ne ukázku),
- [ ] záznam se otevře na `#chronicle` a přehraje, bez chyb v konzoli,
- [ ] součty „Zatím“ na konci přehrávání sedí s tím, co hráč v té hře skutečně udělal (aspoň namátkou: questy, level, instance),
- [ ] trasa se nezapisuje, když je oblast `own_track` vypnutá,
- [ ] v textu práce je napsáno, co z **tabulky v bodě 1** se podařilo vyzkoušet ve hře a co ne,
- [ ] výsledek pokusu s `combatSpells` je zapsán v bodě 1, i když je záporný.
