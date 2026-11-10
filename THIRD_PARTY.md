# Použité cizí podklady a licence

Stav: 10. listopadu 2026. Platí pro webovou mapu a databázi (složky `platform/`, `tools/`, `shared/`). Zdrojové soubory, ze kterých se data generují, jsou v `shared/sources/` včetně licenčních textů, kde je zdroj dodává.

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
| HereBeDragons 2.0 + Pins (Nevcairiel) | BSD (podle X-License v jejím TOC) | body na světové mapě a minimapě v addonu; nezměněné kopie přibalené v GatherLite, commit 0547c95 | `addon/Evertally_Map/Libs/` |
| CallbackHandler-1.0 (Ace3) | licence Ace3 (BSD s doložkou o samostatném šíření; zde je vložená do addonu, ne šířená samostatně) | závislost HereBeDragons | `addon/Evertally_Map/Libs/`, text v `Ace3-LICENSE.txt` |
| LibStub | public domain (uvedeno v souboru) | závislost HereBeDragons | `addon/Evertally_Map/Libs/` |
| Shortest Path Forever → `walk.bin` (terén) | GPL-3.0-or-later | maska průchodnosti kontinentů (0 zablokováno, 1 země, 2 voda) z terénních dat v GatherLite (`plugins/routes/navigation/vendor/Nav`, vlastní bake klienta od SPF), zmenšená na 16yardové buňky; z ní se hledají cesty po terénu na webu | `tools/build_walkmask.py` → `platform/public/media/world/walk.bin` |
| Shortest Path Forever → `addon/Evertally_Map/Data.lua` | GPL-3.0 | tytéž cestovní údaje jako na webu, převedené do Lua pro navigaci ve hře | `tools/build_map_lua.py` |

## Co se úmyslně nepoužívá

- **WowfCZ** (české překlady questů, itemů a NPC): licence není uvedena. Bez svolení autora se nebundluje ani nenasazuje. Nabízí se čtení z nainstalovaného addonu přímo v aplikaci (data by neopustila počítač hráče), nebo dohoda s autorem.
- **RareScanner** (All Rights Reserved) a **Leatrix Maps** (bez licence): jen jako inspirace pro chování mapy.
- **Raider.IO**: architektura přenosu dat je popsána v `ZDROJE.md`; jeho data se nepoužívají.

**Před veřejným vydáním:** data uzlů (GatherLite) mají původ ve Wowheadu a o jejich právním stavu nemám podklad; stejně tak QuestieDB-odvozené polohy trenérů a obchodníků (`tools/build_services.py`). Do ostrého webu to nenasazuj, dokud si to nepotvrdíš (nebo vrstvu Sbírání vypni).

Složka `addon/Evertally_Map` obsahuje číselné údaje odvozené z GPL-3.0 zdroje (Shortest Path Forever), takže se šíří jako GPL-3.0-or-later (uvedeno v jejím TOC). Knihovny v `Libs/` si drží své licence, viz `Libs/NOTICE.txt`. Ikony bodů na mapě jsou vlastní (`tools/build_map_icons.py`), nic z nich není z hry ani cizích addonů. Nejsou přibalená terénní data průchodnosti (12 MB v GatherLite, GPL-3.0).

## Licenční poznámka k projektu

Do projektu vstupují podklady s různými podmínkami včetně GPL-3.0, GPL-2.0 a CC BY 4.0. Prohlášení QuestieDB navíc upozorňuje na nevyjasněná historická práva; nelze proto tvrdit, že pro celý obsah stačí pouze zvolit GPL-3.0. U databáze uzlů z Wowheadu ani u herní grafiky se dosud nepodařilo doložit souhlas pro tuto distribuci. Konkrétní stav je potřeba předat právníkovi nebo vyjasnit s držiteli práv.

### Ověření podkladů 10. 11. 2026

- Nainstalovaný `QuestieDB/LICENSE.md` i [licence QuestieDB](https://github.com/Questie/QuestieDB/blob/master/LICENSE.md) rozlišují podmínky jednotlivých příspěvků a výslovně uvádějí nejistotu u starších přispěvatelů. Nejde tedy o jednoznačně doloženou licenci všech řádků databáze.
- `GatherLite/plugins/database/data/forever.lua` identifikuje generátor `tools/update_forever_wowhead.py`. Licence kódu GatherLite sama o sobě neprokazuje licenci dat převzatých ze třetí strany.
- Kopie `shared/sources/spf/LICENSE` obsahuje GPL-3.0. U `AtlasLootClassic/LICENSE` je přiložena GPL-2.0; zda se na použité záznamy a případné odvozené soubory vztahuje možnost „nebo novější“, je nutné ověřit u konkrétního zdroje. [GNU vysvětluje kompatibilitu verzí GPL](https://www.gnu.org/licenses/gpl-faq.en.html#v2v3Compatibility).
- WowfCZ používáme jen v prostředí hráče, není součástí webu ani instalačního balíčku Evertally. Licence překladů a svolení autora pro přibalení nejsou doložené.
- Mapové obrázky a ikony pocházejí z herního obsahu Blizzardu. Pro další veřejnou distribuci na webu nebo v instalátoru nebylo v tomto projektu nalezeno samostatné výslovné povolení.
