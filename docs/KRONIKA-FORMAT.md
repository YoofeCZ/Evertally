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
| **bojový log** | `COMBAT_LOG_EVENT_UNFILTERED` | deklarováno **s `HasRestrictions: true`**, přístup addonu a chování za běhu **neznámé** |
| `CombatLogGetCurrentEventInfo` | — | **v deklaracích Forever nenalezeno, ověřit** |
| souhrny z vestavěného měřiče | `C_DamageMeter.*` | deklarováno; dotazy na relace jsou označené `SecretWhenInCombat`, tedy za boje mohou vracet **tajné hodnoty** |

### Největší riziko: bojový log

Celá záložka **Tahy** (kdo koho čím a kdy) stojí na bojovém logu. Zdrojové deklarace Forever 1.60.1.70862 označují událost logu
jako omezenou (`HasRestrictions`) a u rozhraní vestavěného měřiče používají „tajné hodnoty“ (`SecretWhenInCombat`). Z toho
plyne **možnost**, že data z boje jsou addonu za boje skryta, ne jistota. Dokud se to neověří **ve hře**, nelze slíbit, že se log
dá zapsat.

Proto je formát navržený tak, aby **log byl volitelný** a všechno ostatní fungovalo bez něj (viz fáze v bodě 7).

**Ověřovací pokus před jakoukoli prací na logu** (malý testovací addon, žádný záznam):

1. Zaregistrovat `COMBAT_LOG_EVENT_UNFILTERED` a v průběhu 30 s souboje s mobem spočítat události.
2. Zjistit, jestli jsou pole (zdroj, cíl, kouzlo, částka) **čitelná**, nebo skrytá. Jak se skrytá hodnota pozná, v Forever
   ověřit v dokumentaci (`SecretValue`, `ConditionalSecret`, `NeverSecret` v deklaracích).
3. Totéž za boje a po boji pro `C_DamageMeter.GetCombatSessionFromType` (je v něm `combatSpells` po kouzlech).
4. Výsledek **napsat sem**, i když je negativní.

Možné výsledky a co z nich plyne:

| Výsledek | Co se dá zapsat |
|---|---|
| log je čitelný | plný `log` (tah po tahu) |
| log je skrytý, ale `C_DamageMeter` se po boji čte | součty po kouzlech a po hráčích bez `log` (záložky Přehled, Kouzla, Skupina, Průběh) |
| nic z toho | jen časy souboje, výsledek a vlastní kouzla z `UNIT_SPELLCAST_SUCCEEDED`; bez čísel o poškození |

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

## 4. Soukromí

Trasa je **historie pohybu hráče**. Záznam je ve výchozím stavu **jen místní soubor**. Web ho čte v prohlížeči a nic neposílá.
Nahrávání na server (viz otevřené otázky) smí vzniknout jen s výslovným souhlasem hráče a s možností smazání. Do záznamu
nepatří cizí hráči s jejich polohou: protivníci a členové skupiny se objevují **jen jménem a čísly souboje**, ne trasou.

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
| **A** | `path`, `quest` (přijat/odevzdán), `loot`, `money`, `level`, `skill`, `zone`, `death`, `group`, `dungeon` enter/leave, `sessions` | jen na běžných událostech (tabulka v bodě 1) |
| **B** | `kill` (z XP zprávy nebo z logu), `boss` a `pvp` události se **součty** v `fights` bez `log` | `ENCOUNTER_*`; součty z `C_DamageMeter` po boji, pokud se čtou |
| **C** | `fights[].log` + `actors` + `spells` | výsledek ověřovacího pokusu z bodu 1 |

Poznámky k fázi A/B:

- Zabití z textové zprávy o XP bude pravděpodobně záviset na jazyce klienta (**neověřeno**). Zapisovač to musí mít za lokalizaci, nebo vzít zabití z logu (fáze C).
- Při `/reload` a odhlášení se SavedVariables ukládají; záznam se do souboru dostane až tehdy (stejně jako dnešní trasa).
- Zapisovat průběžně do **kruhového bufferu** v paměti a při ukládání ho přesunout do SavedVariables; neukládat každý vzorek zvlášť.

## 8. Otevřené otázky (potřebují rozhodnutí)

1. **Kdo převádí** surový záznam z addonu na tento soubor? Navržené: addon zapíše úsporný surový tvar do SavedVariables a Windows
   aplikace z něj složí JSON (zná `manifest.json`, převede `uiMapID` na klíče, doplní `sessions`). Alternativa: addon zapisuje
   hotový tvar. Zatím **nerozhodnuto**.
2. **Kam se záznam dostane** na web? Dnes jen přetažením souboru. Nahrání na server **není navržené ani postavené**. Omezení, které to určuje: databáze D1
   na bezplatném tarifu Cloudflare povoluje **100 000 zapsaných řádků denně** (limit byl 14. 11. 2026 skutečně vyčerpán živou polohou).
   Záznam by proto musel jít jako **jeden objekt na sezení**, ne jako řádky po událostech.
3. **Retence**: kolik sezení / jak dlouho se drží.
4. **Souhlas a sdílení** (odkaz, přátelé, veřejně): stejný model jako sdílení polohy, ale pro záznam zatím neexistuje.
5. **Výsledek ověřovacího pokusu s bojovým logem** (bod 1): bez něj nejde rozhodnout o fázi C.

## 9. Přijetí práce na addonu

Hotovo je, když:

- [ ] `node scripts/check-chronicle.mjs` dává `OK` pro záznam z reálné hry (ne ukázku),
- [ ] záznam se otevře na `#chronicle` a přehraje, bez chyb v konzoli,
- [ ] součty „Zatím“ na konci přehrávání sedí s tím, co hráč v té hře skutečně udělal (aspoň namátkou: questy, level, peníze),
- [ ] v textu práce je napsáno, co ze **tabulky v bodě 1** se podařilo vyzkoušet ve hře a co ne,
- [ ] výsledek ověřovacího pokusu s bojovým logem je zapsán v bodě 1, i když je záporný.
