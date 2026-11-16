# Použité cizí podklady a licence

## Přibalená data herních modulů 0.9.29

- **What's Training 11.4.7, tabulky pro Forever (`Classes/Camelot`)** — MIT. Normalizovaný katalog v `addon/Evertally/TrainingData.lua` používá pouze údaje o schopnostech, cenách a podmínkách; logika a rozhraní modulu jsou vlastní Evertally. Generátor je `tools/build_training_data.py`, původní licenční text je přiložen jako `addon/Evertally/TrainingData-LICENSE.txt`. Původní addon není runtime závislostí.
- **QuestieDB pro Forever** — metadata questů a referenční souřadnice používané vlastními katalogy průvodce a trenérů; konkrétní verzi a podklady uvádějí generátory a `addon/Evertally/QuestGuideData-NOTICE.txt`. Zůstávají relevantní licenční podmínky a historické nejistoty QuestieDB popsané níže. Vlastní výpočet postupu nekopíruje cizí kurátorovaný průvodce.

Kód ani texty Matty7500 Quest Guide/Quest Helper, GearQuest Forever nebo Widsith se do těchto modulů nepřebírají.

Stav: 11. listopadu 2026. Platí pro webovou mapu a databázi (složky `platform/`, `tools/`, `shared/`). Zdrojové soubory, ze kterých se data generují, jsou v `shared/sources/` včetně licenčních textů, kde je zdroj dodává.

**Rozsah podkladů:** vedle faktických údajů projekt obsahuje také převzaté nebo odvozené databáze, textové tipy, knihovny a grafiku. Pouhé vlastnictví herního klienta samo o sobě neprokazuje oprávnění tyto soubory dál veřejně šířit. Práva a licenční podmínky je nutné posuzovat podle konkrétního zdroje a způsobu použití.

| Zdroj | Licence | Co z něj bereme | Kde to žije |
| --- | --- | --- | --- |
| [OpenMap](https://github.com/openmap-world/openmap) (openmap-world) | MIT (kód a datové tabulky); mapové umění je Blizzardovo a v repozitáři není | úrovně zón, vchody do instancí, trasy lodí a zeppelínů, seznam pater dungeonů | `shared/sources/openmap/`, `tools/build_map_data.py`, `tools/build_dungeon_floors.py` |
| [Shortest Path Forever](https://github.com/cjber/shortest-path-forever) (cjber) | GPL-3.0 | letištní body a trasy s naměřenými časy letů (zdroj časů InFlight, MIT), pěší vzdálenosti mezi pevnými místy, jízdní řády lodí/zeppelínů/výtahů/Deeprun Tram, portály | `shared/sources/spf/`, `tools/build_travel_data.py` |
| AtlasLoot Forever (AtlasLootClassic) | GPL-2.0 | loot tabulky raidů, změřené šance na drop (jen ID a procenta) | `tools/db_sources.py` → `atlasloot()` |
| SkillUp Forever (cjber) | GPL-3.0 | recepty profesí: suroviny, výstupy, hranice dovednosti, poplatky trenérů | `tools/db_sources.py` → `recipes()` |
| LibForeverData (forever-db, Polestar contributors) | CC BY 4.0 pro kroky a poznámky ke questům; databáze vychází z EG Link (Efficient Games, CC BY 4.0), CMaNGOS classic-db, pfQuest (MIT), ForeverTDB, QuestieDB | tipy a postup ke questům | `tools/db_sources.py` → `forever_steps()` |
| QuestieDB (Forever) | Smíšený historický původ; tým umožňuje kopírování za podmínek GPLv3, výslovně však upozorňuje, že nemůže potvrdit souhlas všech historických přispěvatelů. Viz [licenční prohlášení QuestieDB](https://github.com/Questie/QuestieDB/blob/master/LICENSE.md). | NPC, questy, objekty, výskyty, vazby itemů | `tools/db_sources.py` → `Questie` |
| DungeonJournal (Exehn) | licence neuvedena; jen fakta | úrovně, bossové, loot bossů, questy a vchody dungeonů | `tools/db_sources.py` → `journal()` |
| WoW Classic Item Caches (Napalmsteak) | viz repozitář | tooltipy a zdroje itemů, změny oproti Classicu | `shared/sources/forever-items.json` |
| GatherLite (Wuild) | MIT (původní kód); celý addon se distribuuje jako GPL-3.0-or-later; **souřadnice uzlů vznikly z Wowhead seznamů a jejich licenci GatherLite neurčuje** | souřadnice bylinek, rud, beden a rybářských míst (`forever.lua`) a jména/minimální dovednost (`nodes.lua`); kód ani ikony se nepřebírají | `tools/build_gather.py` → `platform/public/media/gather/gather.json` |
| wago.tools (herní tabulky UiMap, LoadingScreens …) | data Blizzard Entertainment | umístění map na mapě světa, odkazy na umění | `shared/sources/*.csv` |
| Leaflet 1.9.4 | BSD-2-Clause | vykreslování mapy v prohlížeči | `platform/package.json` |
| DockWatch 1.8.1 (Wyveryx) | MIT (text licence je v hlavičce `TransportData.lua`) | jízdní řády lodí a zeppelinů: přístavy, ověřené doby plavby a čekání, délka okruhu a jeden skutečný odjezd na trasu (data 13. 10. 2026); časy se jen dopočítávají, ve hře se nic nesleduje ani neučí | `tools/build_transport_data.py` → `addon/Evertally_Map/TransportData.lua`, `Transports.lua` |
| game-icons.net: „Sailboat“ (Delapouite), „Zeppelin“ (Skoll) | CC BY 3.0 | jen siluety lodi a zeppelinu; odznak, barvy a stínování kreslí náš skript | `shared/sources/game-icons/` → `tools/build_transport_icons.py` → `addon/Evertally_Map/Media/ship.tga`, `zeppelin.tga` |
| HereBeDragons 2.0 + Pins (Nevcairiel) | BSD (podle X-License v jejím TOC) | body na světové mapě a minimapě v addonu; nezměněné kopie přibalené v GatherLite, commit 0547c95 | `addon/Evertally_Map/Libs/` |
| CallbackHandler-1.0 (Ace3) | licence Ace3 (BSD s doložkou o samostatném šíření; zde je vložená do addonu, ne šířená samostatně) | závislost HereBeDragons | `addon/Evertally_Map/Libs/`, text v `Ace3-LICENSE.txt` |
| LibStub | public domain (uvedeno v souboru) | závislost HereBeDragons | `addon/Evertally_Map/Libs/` |
| Shortest Path Forever → `walk.bin` (terén) | GPL-3.0-or-later | maska průchodnosti kontinentů (0 zablokováno, 1 země, 2 voda) z terénních dat v GatherLite (`plugins/routes/navigation/vendor/Nav`, vlastní bake klienta od SPF), zmenšená na 16yardové buňky; z ní se hledají cesty po terénu na webu | `tools/build_walkmask.py` → `platform/public/media/world/walk.bin` |
| QuestieDB (čtení za běhu) | GPL-3.0 | Databázová karta a vrstvy služeb v okně Evertally čtou nainstalovaný addon QuestieDB přes jeho veřejné rozhraní (`LibQuestieDB`: `Npc`, `Quest`, `Item`, zónové tabulky). Nic z jeho dat ani kódu se nekopíruje do Evertally. | `addon/Evertally_Map/WorldDb.lua`, `WorldDbPage.lua` |
| Shortest Path Forever → `addon/Evertally_Map/Data.lua` | GPL-3.0 | tytéž cestovní údaje jako na webu, převedené do Lua pro navigaci ve hře | `tools/build_map_lua.py` |
| Index itemů webu → `platform/lib/item-levels.data.ts` | stejný původ jako index itemů (WoW Classic Item Caches, viz výše) | item level a příznak obouruční zbraně pro průměrný item level v žebříčku (jen čísla, žádné texty) | `tools/build_item_levels.py` |
| ID ras Skyborne (95 High Order, 96 Windshaper) | fakta; ověřeno ve dvou nainstalovaných addonech: QuestieDB (`raceMaskById`, GPL-3.0) a AllTheThings (`ReferenceDB`) | jména a frakce dvou nových ras Forever na webu | `platform/components/evertally/data.ts` |
| Emblémy ras 95 a 96 | vlastní kresba Evertally (křídlo v barvě frakce), ne herní umění | ikona rasy u postav Skyborne na webu | `tools/make_skyborne_icons.py` → `platform/public/media/identity/races/95.png`, `96.png` |

## Co se úmyslně nepoužívá

- **WowfCZ** (české překlady questů, itemů a NPC): licence není uvedena. Bez svolení autora se nebundluje ani nenasazuje. Nabízí se čtení z nainstalovaného addonu přímo v aplikaci (data by neopustila počítač hráče), nebo dohoda s autorem.
- **RareScanner** (All Rights Reserved) a **Leatrix Maps** (bez licence): jen jako inspirace pro chování mapy.
- **Raider.IO**: architektura přenosu dat je popsána v `ZDROJE.md`; jeho data se nepoužívají.

Mapa ve hře je OpenMap (MIT), na které je modul mapy závislý (`## Dependencies: OpenMap`); Evertally z ní nic nepřebírá ani nešíří. Ikony surovin jsou ikony předmětů hry, čtené podle ID souboru (`GatherIcons.lua`, jen čísla).

**Před veřejným vydáním:** data uzlů (GatherLite) mají původ ve Wowheadu a o jejich právním stavu nemám podklad; stejně tak QuestieDB-odvozené polohy trenérů a obchodníků (`tools/build_services.py`). Nasazení těchto vrstev neprokazuje právní vypořádání jejich původu.

Složka `addon/Evertally_Map` obsahuje číselné údaje odvozené z GPL-3.0 zdroje (Shortest Path Forever), takže se šíří jako GPL-3.0-or-later (uvedeno v jejím TOC). Knihovny v `Libs/` si drží své licence, viz `Libs/NOTICE.txt`. Ikony bodů na mapě jsou vlastní (`tools/build_map_icons.py`), nic z nich není z cizích addonů; výjimkou jsou ikony surovin, které jsou ikonami předmětů hry čtenými podle ID souboru (`addon/Evertally_Map/GatherIcons.lua`, jen čísla, vyrobená `tools/build_gather_icons.py` z tabulky předmětů klienta Forever), takže se žádná grafika nepřibaluje. Verze 0.7.0 přibaluje kompaktní TerrainData.lua odvozené z téže masky průchodnosti jako web; obsahuje 4 208 940 buněk v 16yardovém rozlišení. Text GPL-3.0 je přiložen jako addon/Evertally_Map/LICENSE.txt, původ shrnuje NOTICE.txt.

## Licenční poznámka k projektu

Do projektu vstupují podklady s různými podmínkami včetně GPL-3.0, GPL-2.0 a CC BY 4.0. Prohlášení QuestieDB navíc upozorňuje na nevyjasněná historická práva; nelze proto tvrdit, že pro celý obsah stačí pouze zvolit GPL-3.0. U databáze uzlů z Wowheadu ani u herní grafiky se dosud nepodařilo doložit souhlas pro tuto distribuci. Konkrétní stav je potřeba předat právníkovi nebo vyjasnit s držiteli práv.

### Ověření podkladů 10. 11. 2026

Přehrávač kronik navíc načítá metadata ikon kouzel z veřejného Classic tooltip rozhraní Wowhead a ID modelu NPC z
[CMaNGOS ClassicDB z2815](https://github.com/cmangos/classic-db/blob/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz).
Použije jen modelové záznamy s totožným ID a názvem v dosavadní referenční databázi. Obrázky ikon a náhledy modelů se zobrazují přímo ze CDN `wow.zamimg.com`; herní grafika pochází od
Blizzard Entertainment. Vyhledání starších NPC podle jména používá stejná referenční fakta jako stávající databáze NPC
(`tools/build_chronicle_npcs.py`); nejednoznačná jména se nedoplňují.

- Nainstalovaný `QuestieDB/LICENSE.md` i [licence QuestieDB](https://github.com/Questie/QuestieDB/blob/master/LICENSE.md) rozlišují podmínky jednotlivých příspěvků a výslovně uvádějí nejistotu u starších přispěvatelů. Nejde tedy o jednoznačně doloženou licenci všech řádků databáze.
- `GatherLite/plugins/database/data/forever.lua` identifikuje generátor `tools/update_forever_wowhead.py`. Licence kódu GatherLite sama o sobě neprokazuje licenci dat převzatých ze třetí strany.
- Kopie `shared/sources/spf/LICENSE` obsahuje GPL-3.0. U `AtlasLootClassic/LICENSE` je přiložena GPL-2.0; zda se na použité záznamy a případné odvozené soubory vztahuje možnost „nebo novější“, je nutné ověřit u konkrétního zdroje. [GNU vysvětluje kompatibilitu verzí GPL](https://www.gnu.org/licenses/gpl-faq.en.html#v2v3Compatibility).
- WowfCZ používáme jen v prostředí hráče, není součástí webu ani instalačního balíčku Evertally. Licence překladů a svolení autora pro přibalení nejsou doložené.
- Mapové obrázky a ikony pocházejí z herního obsahu Blizzardu. Pro další veřejnou distribuci na webu nebo v instalátoru nebylo v tomto projektu nalezeno samostatné výslovné povolení.
