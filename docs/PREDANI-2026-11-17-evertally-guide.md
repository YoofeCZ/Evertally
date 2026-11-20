# Předání: Evertally Guide sloučený s Evertally, addon 0.11.0

Dne 2026-11-17. Předávací dokument pro další session: co je hotové, jak je to postavené, jak se to mění a co zbývá.

## Stav

- **Vydáno:** addon **0.11.0** na Pi (`Evertally.zip`, 914 souborů, sha256 `bcf94f30c1babca380466bf3e0e5238ab3d32dda3843db504d1f3b61045567f3`). Ověřeno stažením z `https://evertally.afstudio.dev/downloads/`. Aplikace zůstává **0.9.19**.
- **Záloha 0.10.0 na Pi:** `~/evertally/backups/addon-0.10.0-2026-11-17/` (zip + manifest).
- **Testy:** 832 Lua testů prochází (`cd tests/lua && python -m unittest discover -p "test_*.py"`, asi 3,5 minuty).
- **Ve hře neověřeno nic** z tohoto vydání. Uživatel ho testuje po úplném restartu hry.
- Poznámky k vydání: [VYDANI-0.11.0.md](../VYDANI-0.11.0.md).

## Splněné požadavky uživatele (zadání z 2026-11-17)

| Požadavek | Řešení | Commit |
|---|---|---|
| Pryč oznámení „While you're here“ | výchozí `behavior.whileHere = false` (a `whileHereVendors`) | `4924c19` |
| Discord https://discord.gg/Mjmj8gmAPT | `ns.DiscordURL` ve forku | `4924c19` |
| Seznam AddOns: vše pod Evertally, jen EN a CS | `toc()` v importéru: `## Group/Category: Evertally`, názvy „Evertally - …“, pryč `Title-/Notes-` mimo csCZ | `4a28d7d` |
| Pryč Dungeons a Characters z hubu | registrace sekcí vypnutá, `SHOW_DUNGEON` → Dungeon Journal, `SHOW_ALTS` → Přehled | `c7c4ad5` |
| Informace o dungeonech do Dungeon Journalu | karta „Pro tebe“ (`Evertally_Map/DungeonPrep.lua`) | `607a7f2` |
| Minimapa: levé = vyskakovací okno, pravé = skrýt | `UI.lua` `A.CreateMinimapButton`, tlačítko forku výchozí vypnuté | `75c7a1f` |
| Vlastní menu, víc tlačítek, EVERTALLY MENU | `EvertallyMenu.lua` | `75c7a1f` |
| Nahoře přepínač Guide / Quests, tracker po vzoru QuestMasteru, šipka zůstává | `QuestTracker.lua` a overlay `GuideFrameLayout.lua` | `ba59055` |
| Duplicity: Databáze → Lookup, Výbava a odpad, Questový průvodce | `GuideShell.lua` `HIDE`, `A.OpenDatabaseEntry` → Lookup | `4e0251e` |
| Sloučený onboarding ve **stylu Polestaru** | `SetupPages.lua` a háčky ve `Welcome.lua` forku | `ed5b212` |

Výjimka z pravidla „žádná kopie Polestaru“: pro **okno nastavení** si uživatel styl Polestaru výslovně přál („onboarding chci ale ten styl polestaru tam narvi ty naše onboard nastavení“). Všude jinde platí vlastní vzhled Evertally.

## Jak je fork postavený (nepsat od oka)

- `addon/Evertally_Guide*` (32 složek) **generuje** `tools/import_polestar.py` z nainstalovaného Polestaru 0.4.0.1. **Ručně se neupravuje.** Změny jdou:
  - do `PATCHES` v importéru: klíč je relativní cesta (platí ve všech složkách forku), hodnota `(staré, nové, počet)`, nesedící počet importér zastaví,
  - do `GLOBAL_PATCHES` a `toc()`,
  - nebo do overlay `tools/evertally-guide-overlay/` (celé soubory přes import: `UI/GuideFrameLayout.lua`, `Theme/Widgets.lua`, média).
- **Importér spouštěj z `D:\addon`.** Když shell stojí uvnitř `addon/Evertally_Guide*`, mazání starého výstupu selže v půlce a složka zůstane rozbitá. Oprava: spustit znovu z kořene.
- Velké úpravy s uvozovkami a lomítky piš jako Python skript nástrojem Write, ne přes heredoc.
- Čeština forku: `Evertally_Guide_csCZ` z `tools/polestar-cs/` (`interface.json`, `texts.json`, pravidla `tools/polestar_cs_rules.py`).

### Rozhraní mezi forkem a Evertally

| Ve forku (patch / overlay) | V Evertally |
|---|---|
| `SHOW_DUNGEON` → `Evertally.OpenGuideDungeon(key)` | `WorldHost.lua`, pak `Evertally_Map/DungeonJournal.lua` `M.OpenGuideDungeon` |
| `SHOW_ALTS` → `Evertally.ShowView("overview")` | |
| `SHOW_TALENTS` → stránka Talenty Evertally (fork má „Coming soon“) | |
| `Maps.ShowMenu` → `Evertally.ShowEvertallyMenu(anchor)` | `EvertallyMenu.lua` |
| `maps.minimapButton = false`, `whileHere = false` | tlačítko Evertally u minimapy |
| overlay `GuideFrameLayout.lua`: `layoutQuests`, přepínač | `Evertally.QuestTracker` (`Mode`, `SetMode`, `BuildSwitch`, `Attach`, `Layout`, `Title`) |
| `Welcome.lua`: `UI.WelcomeHost(spec)`, `UI.WelcomeKit`, `pg.blocked()`, `UI.WelcomeOnFinish`, `UI.WelcomeOnOpen`, `UI.WelcomeOwner`, `makePage` (stránka se staví při prvním zobrazení) | `SetupPages.lua` (12 stránek `et-*`), `Onboarding.lua` (`A.SetupDraft`, `A.OpenOnboarding` → okno průvodce; vlastní okno jen bez průvodce) |
| Hub (`UI.RegisterSection`) | `GuideShell.lua`: Evertally je jedna sekce; `SKIP` (Levelování) a `HIDE` (database, gear, questguide: postavené, jen ne v menu) |

Sběr dat pro web (`Collectors.lua`, `Core.lua`, `Armory.lua` → `A.TalentTrees`) zůstává vždy.

## Náhledy (offline, bez hry)

- `PLAYWRIGHT_MODULE='C:/Users/domin/n8n-local/node_modules/playwright'` (v projektu Playwright není; tohle je funkční kopie na disku).
- `python tools/ui_preview/preview.py menu --language cs`: menu Evertally.
- `python tools/ui_preview/preview.py dungeons --tab prep [--prep-attune] --language cs`: karta „Pro tebe“ (testovací data BRD).
- `guide_preview.py` (okno průvodce se skutečným forkem):
  - `QUESTS=1 CS=1 python tools/ui_preview/guide_preview.py Evertally_Guide,Evertally_Guide_SkinAPI,Evertally_Guide_Options,Evertally_Guide_Guides,Evertally_Guide_Guides_Horde,Evertally_Guide_Guides_Scourge --skin`: karta Questy; `QUESTS=guide` ukáže přepínač v režimu Návod,
  - `SETUP=et-website` (stejné argumenty): jedna stránka nastavení, výstup `output/guide-preview/setup-<klíč>.png`.
- Limity náhledů:
  - „?“ znamenají herní ikony, které náhled nemá,
  - harness ztrácí šířku a měřítko okna instalace (obchází to `SetWidth(600)`),
  - mock neumí animační skupiny (`ANIMSTUB`).

## Postup vydání (ověřeno 2026-11-17)

1. Verze ve 4 souborech: `Evertally.toc`, `Locale.lua` (`A.version`), `Evertally_Export.toc`, `Evertally_Map.toc`. Verze v TOC forku je verze Polestaru, ta se nemění.
2. `VYDANI-x.y.z.md`, celé testy, `python -I tools/package_addon.py`.
3. Porovnat `platform/public/downloads/manifest.json` se serverovým: aplikace a instalátor se nesmí změnit, pokud nejsou součástí vydání.
4. Na Pi:
   - záloha do `~/evertally/backups/`,
   - zip přes `scp` jako `.part` do `~/evertally/files/downloads/`, pak `mv`,
   - manifest jako `.part` do `~/evertally/tmp/` (**ne do `dist/`**, wrangler ho sleduje), pak `mv` do `~/evertally/app/dist/client/downloads/`.
5. Ověřit stažením z veřejné adresy: 200, `Content-Type`, hlavička `PK`, sha256, verze v TOC uvnitř zipu.
6. Vydávat **jen po výslovném „ano“ uživatele** pro dané vydání.

## Co zbývá

1. **Test ve hře** (může jen uživatel, po úplném restartu hry):
   - minimapa: levé a pravé tlačítko,
   - menu Evertally,
   - přepínač Návod / Questy a tracker (klik = šipka, Shift+klik, pravé tlačítko),
   - Dungeon Journal, karta „Pro tebe“,
   - instalace `/etally setup`: blokování u instalace a párování, Dokončit uloží,
   - seznam AddOns.
2. **Překlad textů návodů** (dělá jiná session, uživatel: „potom doděláme“). V `texts.json` je vyplněno 7 663 z 10 323, ale importér hlásí „8798 guide texts“. Rozdíl ověřit, než se bude tvrdit, kolik chybí.
3. **Hláška forku o chybějících jazycích:** hráč s německým, francouzským a jiným klientem dostane při přihlášení zprávu, že chybí jazykové soubory (`Core/Locale.lua`, tabulka `LANGUAGE`). Jiné jazyky než EN a CS nevydáváme, takže ji patchem vypnout.
4. **Lookup bez naší karty questu.** Uživateli jsem navrhl počkat, Lookup má vlastní detail questu. Nerozhodnuto.
5. **Alty a instalace průvodce:** s `UI.WelcomeOwner` se okno samo neotevře pro novou postavu. Evertally ho otevírá podle `settings.onboarded ~= VERSION` (8) a `EvertallyDB` je na účet (`## SavedVariables`, ne `SavedVariablesPerCharacter`). Nová postava na účtu, který nastavení prošel, proto stránky průvodce pro postavu (váhy statistik) sama nedostane. Rozhodnout, jestli je otevírat i pro nové postavy (`ns.IsNewCharacter()` forku).
6. **Tlačítko forku u minimapy**, když si ho hráč zapne v nastavení průvodce, má pořád levé = skrýt a pravé = menu, tedy obráceně než tlačítko Evertally.
7. **Na Pi** leží v `~/evertally/app/dist/client/downloads/Evertally.zip` starý balík (6,9 MB z 17. 11. 12:04). Tunel ho překrývá, takže se nestahuje. Nemazal jsem ho.
8. V repu jsou nesledované soubory `QuestMaster-Czech-logo.png` a `platform/tmp/`. Nejsou z této práce, nechal jsem je.

## Pravidla, která platí

- Česky. Nic nevydávat bez „ano“. Ve hře může ověřit jen uživatel.
- Nikdy nepřiřazovat globály Blizzardu (`SlashCmdList = …`).
- Z QuestMasteru jen nápady (jeho LICENSE je „All Rights Reserved“).
- Polestar je GPL-3.0: engine a data přebírat jde, vzhled a texty mají být Evertally (kromě okna instalace).
- Velké vizuální změny nejdřív ukázat v náhledu.

## Po prvním testu 0.11.0 ve hře (2026-11-17, večer) — vydáno jako 0.11.1, necommitnuto

Úpravy podle screenshotů uživatele (patche v `tools/import_polestar.py`, sekce „after the first test of 0.11.0“, a overlay):

| Požadavek | Řešení |
|---|---|
| Pryč hvězdy (instalace i záhlaví oken) | `Theme.Band` bez vrstvy `band-stars`, `dipper` nic nekreslí, paprsek emblému skrytý |
| Jen koncepční vzhled Evertally | `Theme.SkinChoices` vrací jen `evertally`; stránka „Tvůj vzhled“ v instalaci skrytá; `GuideSkin.lua` při přihlášení vrátí uložený jiný vzhled na `evertally` |
| Lookup → Databáze, procházení A–Z po kategoriích | `Search.Browse` (abecedně, bez vyřazených a bezzdrojových položek; první stránka bez řazení celé kategorie), `Lookup.lua` bez hledání ukazuje každou kategorii (5 + „Ukázat vše“, v kategorii stránky po 50); české „Databáze“ přes `EXTRA_CS` v importéru |
| Verze bez BETA | `ns.stage = nil`, `ns.routesBeta = false`; patička hubu ukazuje verzi Evertally (`ns.ShownVersion`), `ns.version` zůstává Polestarova kvůli partě a balíčkům |
| Tracker: Questy první, výška, scroll, vzhled | karta Questy první a výchozí; úchyt vpravo dole táhne i výšku (`ui.maxHeight`, během tažení `GF.dragShare`), nad ní se scrolluje; větší řádky, linky sekcí, akcentní okraj u questu aktuálního kroku |
| Pořadí sekcí | oblast, kde hráč stojí, první (questy aktuálního kroku návodu na jejím začátku, i z jiné oblasti), ostatní oblasti, dungeony, „K odevzdání“ vždy poslední |
| EVERTALLY MENU v Návodu, pryč „…“, spodní lišta i v Questech | `GuideFrameLayout.lua` (overlay): tlačítko EVERTALLY MENU na liště nástrojů v obou kartách, „…“ schované (jeho menu je dlaždice „Možnosti okna návodu“) |
| Synchronizace party v EVERTALLY MENU | dlaždice „Parta“ (panel) a „Synchronizovat s mým návodem“; panel se už sám neotevírá (`party.panel = false`) |
| Rozsypaná čeština v tooltipu | `W.Tooltip` v češtině přepne řádky tooltipu na Inter, při skrytí vrátí herní fonty |

Body z „Co zbývá“: **3** hotovo (`Core/Locale.lua` i kontrola instalace v `Core/Data.lua` jazykové složky nehlásí), **5** rozhodnuto a hotovo (nová postava na účtu, který instalací prošel, dostane krátkou instalaci průvodce jen s věcmi postavy; stránky Evertally mají `shown` podle `UI.WelcomeKit.full` a Dokončit v krátké instalaci nastavení Evertally nemění), **6** hotovo (tlačítko forku u minimapy, plovoucí tlačítko i compartment: levé = menu, pravé = skrýt přes `Evertally.ToggleEvertallyHidden`).

Ověřeno: importér prošel se všemi kontrolami počtů, 833 Lua testů prochází (po úpravě dvou testů trackeru a testu importu na nové chování), náhledy tracker / Návod / stránka Questování bez hvězd. **Neověřeno:** Databáze v hubu (náhled Codex nenačte; logika `Search.Browse` ověřena samostatným Lua testem), dlaždice Parta a Možnosti okna (náhled menu nemá fork), tažení výšky, tooltip — vše jen ve hře. **Vydáno 0.11.1** (zip sha256 `ebcd96ce32d572a9103f343eb2045125013958a40958e944f28a2ecf7089039b`, 914 souborů), ověřeno stažením z veřejné adresy; záloha 0.11.0 v `~/evertally/backups/addon-0.11.0-2026-11-17/`.

## Po testu 0.11.1 (2026-11-17, noc) — NEVYDÁNO (uživatel: „nevydávej, budeme pokračovat“), necommitnuto, verze pořád 0.11.1

- **Tracker česky:** názvy a cíle questů z **WowfCZ** čteného za běhu (`WowfCZ_QuestData`, `WowfCZ_ItemData`; nebundlujeme, viz `THIRD_PARTY.md`), jen když je Evertally česky. `QT.CzechTitle`, `QT.CzechObjective`, anglický název zůstává v `q.titleEn` (odkaz do chatu).
- **Tooltipy questů na mapě česky** (OpenMap i mapa hry, „[14] Název“, „- 4/15 Cíl“): háček `GameTooltip` `OnShow` v `QuestTracker.lua` (`QT.CzechTooltip`), quest pozná podle `owner.data.id` nebo nad mapou podle názvu v deníku; font Evertally, při skrytí se vrátí herní. OpenMap se nemění.
- **Klik na quest v OpenMap (sledování) nastaví šipku:** `hooksecurefunc(C_SuperTrack, "SetSuperTrackedQuestID")` → `QT.ArrowToQuest`. Neověřeno, že Forever klient `C_SuperTrack` má (OpenMap ho volá jen když existuje).
- **Levý klik v trackeru:** šipka + mapa v oblasti questu. **V souboji se mapa neotevře hned**, ale po konci souboje (hláška v chatu): otevření mapy z addonu v combatu mapu taintne (Polestar `Core/Compat.lua`, #92).
- **EVERTALLY MENU v menu:** tlačítko průvodce (`EvertallyGuide.Widgets.Button`, fialové jako na liště okna) místo tlačítka Evertally kitu, které ve hře vypadalo tmavě (příčinu v paletě jsem nedohledal, náhled ho kreslil zlatě).
- **Nastavení, skupina O addonu:** pryč Guiding Stars, Nahrávač a „Zvláštní díky:“ v záhlaví hubu; O addonu začíná odstavcem, že Evertally Guide vychází z Polestaru (engine a návody, GPL-3.0), v Credits řádek o Polestaru, verze Evertally.
- Náhled: `MENU=1 QUESTS=1 CS=1 python tools/ui_preview/guide_preview.py …` kreslí menu s načteným průvodcem (`output/guide-preview/menu-guide.png`).
- Testy: 833+ prochází (nové testy trackeru: čeština z WowfCZ, tooltip mapy, šipka ze sledování, mapa po souboji).

## Stránky Evertally ve stylu hubu Polestaru (2026-11-17, pozdě večer) — NEVYDÁNO, necommitnuto, jen nainstalováno do hry

- Záloha před přestavbou: `backups/pred-polestar-stylem-2026-11-17/` (archiv, patch, HEAD).
- Z menu Evertally skryté Places, Atlas, Guides (`GuideShell.lua` `HIDE`).
- **`addon/Evertally/HubKit.lua`** (nový, v TOC za `Widgets.lua`): stránky z dílů průvodce jako Databáze — `HK.Ready/Bleed` (stránka přes celou plochu sekce, bez staré hlavičky), `HK.List` (složky s fialovou značkou, řádky na jeden řádek), `HK.Details` (pás ZoneArt, fialová hrana, ikona v jamce, fakta, tlačítko dole), `HK.Search`. Záložky stránky jdou do lišty hubu (`page.hubTabs/hubTab/OnHubTab`, volá `GuideShell` render).
- **Deník** přestavěný jako vzor (`Journal.lua` `buildHub`). Ostatní stránky zatím na staré stavbě, jen s plochým povrchem (`A.HubLook`, `A.InHubPage`, `kit.HubPanel/HubReader`) — uživatel to odmítl jako málo podobné; převést je stejně jako Deník, až Deník schválí ve hře.
- Náhled hubu: `HUB=journal QUESTS=1 [CS=1] python tools/ui_preview/guide_preview.py …` → `output/guide-preview/hub-journal.png` (harness nevolá OnSizeChanged: šířka seznamu a placeholder hledání v náhledu nesedí).
- **Hvězdy:** `band-stars.tga` (hvězdy i souhvězdí) nahrazený průhledným v overlay a ručně zkopírovaný do forku. **Importér teď nejde spustit:** Polestar už není v `Interface/AddOns` („Polestar not found“). Pro další import stáhnout Polestar 0.4.0.1 a předat cestu jako argument.
- **Výběr quest trackeru v nastavení** (`et-tracker`, Další čeká na volbu): Evertally / Blizzard / Questie (jen když je načtený). Ostatní se skryjí: Blizzard přes `qol.hideQuestTracker` průvodce, Questie přes jeho `QuestieTracker:Toggle` (zapnutí po /reload), Evertally bez karty Questy (`QT.Enabled`, overlay `GuideFrameLayout.lua`). QuestMaster podporu nemá: není nainstalovaný, jeho API jsem neviděl.
- Aplikace Evertally při běhu přepisuje addon serverovou verzí (byte po bytu, `sync/src/addon_update.rs`), proto je při testu vypnutá.
- Testy: 838 OK.
- **Pokračování (pozdě večer):** Deník schválený ve hře („to vypadá dobře“). Převedeno stejně: **Přehled** (`Dashboard.lua` `buildHub`: záložky Aktivita/Oblasti/Loot, pruh čísel, vpravo postava a graf), **Co se naučit** (`TrainingUI.lua` `buildHub`), **Běhy, Profese, Fakta z webu** přes hub verze `Metrics/Filters/Search/BookList` v `UI.lua` (`hubColumn`, `hubLayout`, `hubPlace`), `HK.Stats` a bloky v detailu (`spec.blocks`).
- **Dungeon Journal:** karty jedna na řádek, 132 px, výřez obrázku drží poměr (`cropArt`). **Vnitřek dungeonu zatím starý** — další krok. Hostované stránky (Dungeon Journal, Recepty, Mapa) mají v hubu odsazení 18 px (`WorldHost.lua`).
- **Zbývá převést:** vnitřek dungeonu, Recepty, Talenty, Mapa a cesty, Komunita (fórum), Lidé, Žebříček.
- Oprava: `QuestTracker.lua` `settings()` bez databáze vracel `{}` → chyba při načtení (karta Questy je teď výchozí). Test `QuestTrackerBeforeLoadTests`.
- Testy 839 OK; vše nainstalované ve hře, nevydané, necommitnuté.
- **Další kolo:** vnitřek dungeonu (záložky v liště hubu přes `page.hubTabs`, tlačítko zpět a nadpis z dílů průvodce, ploché řádky; `DungeonJournal.lua` konec `M.BuildDungeons`), Recepty (vyhledávání a výběr profese z dílů hubu, ploché řádky; konec `M.BuildRecipes`), Žebříček (`Rankings.lua` `buildHub`). Roztahování stránky přes celou plochu jen u stránek z nových dílů (`hubColumn`/`HK.Bleed`); ostatní zůstávají oříznuté s odsazením. Zbývá: **Lidé, Komunita, Talenty, Mapa a cesty**. Vnitřek dungeonu a Recepty náhled v hubu neumí (harness nenačte `Evertally_Map`).
- **Pokračování (noc, nová session):** **Lidé** lehčí převod (režimy v liště hubu přes `HK.ChipsToTabs`, panely posunuté nahoru, plochý povrch; filtry Vše/Evertally/… se před prvním layoutem lámaly po jednom — šířka teď padá na šířku stránky). **Komunita** hotová (prázdný stav jmenuje tlačítko „Nové vlákno“ místo „níže“). **Talenty** (`Talents.lua` `buildHub`): záložky Plánovač | Buildy; Plánovač jsou stromy jako dřív bez řádku uložených buildů, nápověda a zoom uvnitř ořezu; Buildy = `HK.List` (Uložené, Doporučené) + `HK.Details` (body po stromech, úroveň, zdroj, poznámka, Smazat, „Otevřít v Plánovači“ / „Načíst šablonu“). Tlačítko Doporučené buildy v Plánovači přepne na Buildy.
- **Opravy napříč:** primary tlačítka kitu v plochém vzhledu byla tmavá — `Theme.Surface` dává čtvercovému povrchu backdrop v barvě karty, který překryl fialový podklad; `T.Button` ho teď zprůhlední (to byla nedohledaná příčina z bodu o EVERTALLY MENU). `A.Upper` dělá velká písmena jen pro a–z a české mapuje zvlášť; HubKit (složky, nadpisy bloků) a graf Přehledu ho teď používají (dřív „ULOžENé“).
- **Náhled:** fixture hubu volá `A.Theme.ApplyScheme()` (jinak se kreslil starý vzhled s rámečky — ve hře to dělá `PLAYER_LOGIN`), `HUB_TAB=<klíč>` otevře záložku stránky, `HUB_EVAL=<Lua výraz>` vypíše hodnotu na ladění, fixture má jeden uložený build válečníka. `PLAYWRIGHT_MODULE` viz výše.
- **Pozor:** kopie ve hře (`D:\World of Warcraft\_forever_\Interface\AddOns\Evertally`) se od repa liší i u Deníku (nemá `buildHub`, čas 23:21) — nejspíš ji přepsala aplikace serverovou verzí. Před testem ve hře aplikaci vypnout a addon zkopírovat znovu.
- Testy 839 OK. Zbývá převést: **Mapa a cesty**; vnitřek dungeonu a Recepty ověřit ve hře (náhled je neumí).
- **Přepis instalace (ověřeno v `%APPDATA%\Evertally\Evertally Sync\config\sync.log`):** 23:56:34 se spustila Evertally Sync a hned „Addon aktualizován na 0.11.1“ — přepíše addon i za běhu hry, vypnout to v ní nejde. Hra pak načetla směs 0.11.1 + nové soubory (HubKit) a spadla na `QuestTracker.lua:498 folded nil`. **Ta chyba je ve vydané 0.11.1** (`settings()` bez databáze vrací `{}`); v repu opravená, nevydaná. Addon znovu zkopírovaný 2026-11-18 (shoda s repem ověřena), záloha v `~/evertally/backups/addons-ve-hre-2026-11-18/`.

## Vydání 0.11.2 a okno dungeonu na webu (2026-11-18)

- **Addon 0.11.2 vydaný na webu** (zip sha256 `edb1e91f…ee37`, 915 souborů, ověřeno stažením: 200, `application/zip`, `PK`, TOC 0.11.2). Záloha 0.11.1 na Pi v `~/evertally/backups/addon-0.11.1-2026-11-18/`. Poznámky `VYDANI-0.11.2.md`. **CurseForge zatím ne** (nahrává uživatel přes vestavěný prohlížeč).
- Nově v 0.11.2 navíc: **ověření aplikace jen jednou** (`Requirements.lua`: platné potvrzení se uloží do `EvertallyDB.bridgeVerified`; `BridgeInstallation.lua` přepíše každá aktualizace addonu na prázdný). Test `test_app_verified_once_stays_verified_after_the_receipt_is_gone`. Lua testy 840 OK.
- **Web — okno dungeonu/raidu** (`components/evertally/views/ChronicleInstance.tsx`, logika `lib/chronicle-instance.ts`, data `lib/chronicle-instances.data.ts` z `tools/build_chronicle_instances.py`): otevírá se z pruhu dungeonu na časové ose, ze šipky u vstupu v seznamu, z detailu a z karty „V dungeonu“. Záložky Přehled (čísla, souhrn soubojů s bossy a s NPC, parta z rosteru při vstupu), Bossové (podle deníku dungeonu, každý rozbalitelný s každým pokusem: čísla, poškození party, celý souboj), Nepřátelé (běžní NPC zvlášť, souboje s nimi, smrti), Loot, Průběh, Mapa (patra ze hry). Vstup do dungeonu nese `id` instance (builder z `instanceId`).
- **Poloha uvnitř dungeonu se nezaznamenává** (ověřeno v datech RFC: hra hlásí jen „Kalimdor“, žádný `track.path`). Pohyb po mapě dungeonu jen pokud ve hře `/run print(UnitPosition("player"))` uvnitř instance vrátí čísla — neověřeno.
- Web nasazený `deploy/pi/deploy-web.sh` (předchozí verze v `~/evertally/app/dist.old`). Před nasazením ověřeno, že necommitnuté změny v `platform/` mimo moje soubory už na Pi byly (nasazení 16. 11. 22:35). Testy webu 347 OK.
- Necommitnuté: nic z toho není v gitu.

## Další převod do stylu hubu (2026-11-18, odpoledne) — nevydáno
- **`Evertally_Map/GuideKit.lua` `GuideDetail`** v hubu: posuvník průvodce (`W.Scroll`, žádné šipky), písma podle rolí, nadpisy malými kapitálkami v akcentu, ploché řádky. Opravuje detail vnitřku dungeonu, Receptů i katalogu najednou. `A.HubReader` bez fialového gradientu a linky nahoře.
- **Recepty:** detail `HK.Details` (ikona profese, fakta: profese, barvy dovednosti; Vyrobí a Suroviny jako klikací řádky), seznam přes zbytek šířky.
- **Vnitřek dungeonu:** tlačítko zpět a „Ukázat vchod / Navigovat“ jsou tlačítka průvodce.
- **Mapa a cesty:** záložky Mapa/Cesta/Sbírání/Služby/Instance v liště hubu (`WorldPage.lua`); katalogy s `W.SearchBox`, `HK.Details` a tlačítky průvodce (`WorldCatalog.lua`); Cesta s polem průvodce (`WorldPlan.lua`).
- **Všechna `kit.Button` na stránkách v hubu** jsou teď `W.Button` průvodce (`UI.lua` `hubButton`; `b.text` = jeho popisek). `HK.SkinInputs(root)` dá jednořádkovým polím (`InputBoxTemplate`) vzhled pole průvodce (Lidé, Talenty).
- **Lišta sekcí dole** (`Theme/Widgets.lua` v overlay i forku, `RAIL_AT_BOTTOM`): vodorovný pruh pod stránkou vlevo od pravého panelu, sekce zleva, Import a Nastavení zprava; znak u nápisu v pravém panelu; `psRail` = 0, okno o 46 px vyšší.
- Náhled: `MAPADDON=1` načte `Evertally_Map`, `HUB_DO=<Lua>` před snímkem (otevření dungeonu: `Evertally.map.OpenDungeonEntry(...)` + `Evertally.guideShell.Open("dungeons")`; Mapa a cesty potřebuje stuby `RequirementsReady`/`OpenMapMissing` a `mapPins=true`).
- **Na Windows občas selže zápis do `addon/Evertally_Map/*.lua` (`Errno 22`)** — přechodně, opakování pomůže (patch skripty zapisují s opakováním).
- Lua testy 840 OK. Zkopírováno do hry, ale **běží Evertally.exe**, které každých 300 s přepíše addon serverovou 0.11.2 (`sync/src/worker.rs`, `addon_update::check`).
- **Vydáno 0.11.3** (2026-11-18): zip sha256 `1cb31575…8c25`, 915 souborů, ověřeno stažením (200, `application/zip`, `PK`, TOC 0.11.3). Záloha 0.11.2 na Pi v `~/evertally/backups/addon-0.11.2-2026-11-18/`. Poznámky `VYDANI-0.11.3.md`. CurseForge ne. Necommitnuto.

## Všechno veřejné (2026-11-18, rozhodnutí uživatele) — web nasazený, addon nevydaný
- Uživatel: žebříček, kronika, statistiky i Armory veřejně pro všechny (jako raider.io), **i pro hráče, kteří dřív výslovně volili ne**, včetně jmen spoluhráčů z party. **Batoh jen s povolením ve hře** (beze změny).
- **Web (nasazeno):** `lib/publish.ts ALL_PUBLIC`; nové profily vznikají veřejné se vším (`store.ts`, `live.ts`), volby ze hry ani z účtu nic neskryjí (`applyPublishChoices`, `applyAccountChoice`, `setProfileVisibility`); `deviceGrantScopes` bere všechno, co addon pošle; párování už nevybírá druhy dat. Migrace `drizzle/0015_all_public.sql` spuštěná na Pi (15/15 profilů veřejných, 5/5 živých souhlasů s trasou); záloha DB `~/evertally/backups/data-2026-11-18-pred-verejnym/`.
- **Armory:** seznam všech postav s hledáním (`/api/armory-public`), klik otevře postavu (`/api/armory-character/<id>`, bez batohu); batoh jen u vlastních a povolených (`/api/armory`). Nové soubory `app/api/armory-public/route.ts`, `app/api/armory-character/[id]/route.ts` (každá operace API potřebuje vlastní route soubor!).
- **Mapa světa** pryč z menu a z Přehledu; `#atlas/...` odkazy z Databáze a srazů dál fungují.
- Zásady soukromí (`ProjectPolicies.tsx`) a texty webu přepsané (už ne „opt-in“, „soukromé“).
- **Addon (nevydáno):** výchozí web a všechny druhy dat zapnuté, jednorázový převod (`s.allPublic`, nový souhlas jen tomu, kdo měl web vypnutý); instalace bez stránek Web a Veřejné (SetupPages i záložní Onboarding.lua je přeskakuje); v Nastavení zůstal jen hlavní vypínač webu; text trasy „veřejná v kronice“.
- Testy: web 347 OK, Lua 840 OK.
- **Vydáno 0.11.4** (2026-11-18): zip sha256 `3b3eb626…460e`, 915 souborů, ověřeno stažením (200, `application/zip`, `PK`, TOC 0.11.4). Záloha 0.11.3 na Pi v `~/evertally/backups/addon-0.11.3-2026-11-18/`. Poznámky `VYDANI-0.11.4.md`. Ovládání skrytí je pryč všude (web Účet, instalace, Nastavení, žádný příkaz); v kódu zůstala jen vnitřní `A.SetPublish` a `OnboardingApply`. CurseForge ne. Necommitnuto.

## Sekce průvodce Guides / Database / Rares (2026-11-18, večer) — nevydáno
- **Nepřeložené popisky:** soubory průvodce čtou `L[...]` při načtení, ještě než Evertally zvolí češtinu (jazyk je v `EvertallyDB`). Překlady existovaly, jen se nepoužily. `A.RelabelGuide(g)` (`EvertallySettings.lua`, volá ho `ApplyGuideLanguage` po načtení `Evertally_Guide_csCZ`) projde tabulky popisků a přeloží je znovu: záložky Domů/Procházet/Aktuální/Nedávné, sekce (lišta), jejich placeholdery hledání, druhy v Databázi, záložky Rares. Lokální tabulky průvodce zpřístupněné (`P.VIEW_LABEL`, `P.GUIDES`, `P.HUB_SEARCH`, `LK.FACTION`, `LK.FALLBACK_KINDS`, `LK.STATUS_TEXT`) — ve forku i jako `_more(...)` v `tools/import_polestar.py`. Test `tests/lua/test_guide_relabel.py`.
- Doplněné překlady `Database`, `Lookup` → „Databáze“ (`tools/polestar-cs/interface.json` i `Evertally_Guide_csCZ/Interface.lua`).
- **Rares:** seznam 506 px, detail vpravo (jako Databáze), `Rares/View.lua` `LIST_W` (fork + importér).
- „Od Polestar“ u návodů je přiznání autorství návodů — nechané.
- Lua testy 841 OK. Nevydáno, necommitnuto.
- **Vydáno 0.11.5** (2026-11-18): zip sha256 `3f3e672d…3e79`, ověřeno stažením (200, `application/zip`, `PK`, TOC 0.11.5). Záloha 0.11.4 na Pi v `~/evertally/backups/addon-0.11.4-2026-11-18/`. Poznámky `VYDANI-0.11.5.md`. CurseForge ne. Necommitnuto.
- **Kategorie jako záložky (uživatel):** v sekcích průvodce (Návody, Databáze, Vzácní mobové, i další s `nav`) jsou kategorie v řádku záložek nahoře (`Picker.lua` `sectionTabs`, po `s.render()`, protože Databáze si řádek maže); pravý panel ukazuje ve všech sekcích menu Evertally (`evertallyNav`, klik přepne do sekce Evertally na stránku). Návody: Domů / Aktuální / Nedávné + kategorie („Procházet“ odpadl), klíče kategorií `cat:<key>`. `W.ShellTabs`: místo podle šířky řádku, menší písmo a zalomení do 2 řádků (`TabRow` vyšší, `layoutBody` čte jeho výšku) — overlay i fork; Picker přes `_more(...)` v importéru i ve forku. Známé: když Codex chybí, Databáze píše stav Codexu do řádku záložek přes kategorie.

## Vydání 0.11.6 (2026-11-18, noc)
- **Vydáno 0.11.6**: zip sha256 `b33a9892…7d64`, 916 souborů, ověřeno stažením (200, `application/zip`, `PK`, TOC 0.11.6, `BagWindow.lua` v balíku). Záloha 0.11.5 na Pi v `~/evertally/backups/addon-0.11.5-2026-11-18/`. Poznámky `VYDANI-0.11.6.md`. CurseForge ne. Commit `76aaec0`.
- **Batoh Evertally** (`addon/Evertally/BagWindow.lua`, test `tests/lua/test_bag_window.py`, náhled `BAGS=<view> QUESTS=1 python tools/ui_preview/guide_preview.py …`): živé sloty jsou `ContainerFrameItemButtonTemplate` pod rámem s ID tašky; herní klávesy přes `hooksecurefunc` (žádný globál Blizzardu). S jiným addonem na tašky (Baganator) klávesu nepřebírá. Banka a alti jen z `A.db.bagCache`. **Ve hře neověřeno.**
- Předpona chatu průvodce `Evertally:` (`Core/Init.lua` PREFIX, `_more` v importéru).
- Otevřené: „Stezka kopců“ nenalezena (čeká na screenshot); hlášky průvodce napůl anglicky („Spirit Healer stojí 6m resurrection sickness“).

## Vydání 0.11.7 (2026-11-19)
- **Pi:** zip sha256 `530d8f2d…5427`, ověřeno stažením (200, `application/zip`, TOC 0.11.7). Záloha 0.11.6 v `~/evertally/backups/addon-0.11.6-2026-11-19/`. Commit `91fb62d`.
- **CurseForge:** nahráno „Evertally 0.11.7“ (stav Processing při nahrání), changelog anglicky od 0.11.1. Předtím tam byla 0.11.1.
- **Proč chyběla trasa v kronikách** (Maegalin, Volx, Sweden): 0.11.1 z CurseForge měla `own_track=false` ve výchozím stavu, server nepřijal žádné `track.path`. Souhlasy na serveru byly v pořádku. Web teď u kroniky bez trasy říká, že hráč má starou verzi (`noRoute`, Chronicle.tsx).
- 0.11.6 měla pád okna batohu (`Theme.lua:148`, barvení FontStringu jako textury) — opraveno v 0.11.7.

## Nastavení bez duplicit (2026-11-19, večer) — NEVYDÁNO, necommitnuto, nainstalováno do hry
- **Evertally:** 6 stránek místo 8 — Sdílení a web (záložky Ve hře / Živě a mapa / Web), Rozhraní (sekce Okna Evertally / Tooltipy, minimapa a batoh / Chat). `PAGES[].parts` v `EvertallySettings.lua`.
- **Průvodce:** každá volba má jeden domov (`EV_DROP` v `UI/Options.lua`, patch v `tools/import_polestar.py`); sloučené stránky Špendlíky a trasy (`mappins` + `routelines`) a Upozornění a trackery (`alerts` + `trackers`) přes `EV_MERGE`, staré klíče přesměrované v `ALIASES`.
- **Chyba v češtině opravená:** pravidla počítala klíč stránky z přeloženého názvu, takže registrace jen s názvem („Okno návodu“) jimi prošly a 20 voleb zůstalo dvakrát. `evKey` bere klíč z první registrace stránky, která ho dala. Výsledek (naměřeno náhledem): EN i CS 16 stránek, 627 voleb, 0 duplicit.
- Test `GuideOptionsWindowTests` (`tests/lua/test_guide_settings.py`) spouští náhled `DUMP_OPTIONS=<soubor.json> QUESTS=1 [CS=1] guide_preview.py …` v obou jazycích; bez opravy na češtině selže (ověřeno).
- Ve hře: 3 soubory zkopírované, záloha `~/evertally/backups/addons-ve-hre-2026-11-19-settings/`. **Ve hře neověřeno.**
- **Jazyk = reload hned** (uživatel: „při změně jazyka reload hned“): `A.SetLanguage` (`UI.lua`) při skutečné změně uloží jazyk a o snímek později zavolá `ReloadUI` (Dokončit instalace stihne uložit zbytek). Důvod: texty průvodce se čtou při načtení souborů a `Evertally_Guide_csCZ` nejde vyložit — bez reloadu zůstal průvodce anglicky (náhled `SETUP_SWITCH=1 SETUP=<stránka> …` to ukazuje: patička „Skip install“). Test `test_a_new_language_reloads_the_ui_at_once_the_same_one_does_not`.
- **Pozor, Evertally Sync přepisuje addon:** 3 soubory zkopírované do hry v 19:01 byly do pár sekund zpátky na vydané 0.11.7 (log „forum: updated“ každé 3 min). Před testem ve hře aplikaci zavřít.
- **Prázdné texty v instalaci (PC přítelkyně, vydaná 0.11.7):** neprázdný je jen popis (role `note` = Inter Regular) a patička; nadpis (`hero`, semibold) a popisky řádků (`body`, medium 13) prázdné. Zip na serveru fonty má (ověřeno stažením), Sync `.ttf` nepřeskakuje, v náhledu se chyba neukáže. **Příčina nalezena** (výstup `/run` z jejího PC: text nadpisu i font v pořádku, výška 26, alfa nadpisu 1, **alfa stránky 0**, enUS): prolnutí stránky nikdy neproběhlo. `Theme/Anim.lua` má jednu společnou smyčku; když jedna animace spadla, `ns.Safe` chybu spolkl a smyčka se v každém snímku zastavila na stejné animaci — zamrzly všechny. Oprava: vadná animace se vyřadí (skočí na konec), ostatní doběhnou, chyba se nahlásí jednou; `Anim.Stop` volá `pcall(step)`. Patch v `tools/import_polestar.py`, test `tests/lua/test_guide_anim.py` (bez opravy selže). **Která animace na jejím PC padá, nevíme** — oprava to jen přestane šířit.

## Vydání 0.11.8 (2026-11-19, večer)
- **Pi:** zip sha256 `82c7e503…7fca`, 916 souborů, ověřeno stažením (200, `application/zip`, `PK`, TOC 0.11.8). Záloha 0.11.7 v `~/evertally/backups/addon-0.11.7-2026-11-19/`. Aplikace a instalátor beze změny (0.9.19). Poznámky `VYDANI-0.11.8.md`.
- Evertally Sync ji u uživatele nainstalovala v 18:33:53Z (log), soubory ve hře = repo.
- Obsah: oprava zamrzlých animací (prázdné texty v instalaci), reload hned po změně jazyka, sloučené stránky nastavení bez duplicit.
- **CurseForge:** nahráno „Evertally 0.11.8“ (stav Processing File při nahrání), changelog anglicky bez Polestaru, odeslal uživatel. **Ve hře zatím neověřeno.**

## Vydání 0.11.9 (2026-11-19, noc)
- **Pi:** zip sha256 `e1fc7587…d2ef`, 921 souborů, ověřeno stažením (200, `application/zip`, `PK`, TOC 0.11.9). Záloha 0.11.8 v `~/evertally/backups/addon-0.11.8-2026-11-19/`. Aplikace a instalátor beze změny (0.9.19). Sync nainstalovala u uživatele 20:04:23Z. Poznámky `VYDANI-0.11.9.md`. CurseForge ne.
- **Batoh** (`BagWindow.lua`, `BagCategories.lua`): sledované předměty nad patičkou (`BW.TOKENS` ověřená ID z `platform/public/media/db/items`, `settings.bagWindow.tracked`, `trackHide`); vlastní kategorie (`settings.bagWindow.sections` = pořadí vestavěných klíčů a tabulek `{key = "c<n>", name, query, items}`, `itemSection[id]` = přetaženo na nadpis). Přednost: Nové → ruční → vlastní v pořadí → vestavěná pravidla.
- **Okno lootu** (`LootWindow.lua`, `settings.lootWindow`, výchozí vypnuto): herní `LootFrame` jen přestane poslouchat `LOOT_OPENED`; master loot přes jeho vlastní `OnEvent`.
- **Šuplíky** (`DrawerMacro.lua`, `/etally drawer`): `EvertallyDrawerN` = SecureActionButton typu `click` na `SecureHandlerClickTemplate`, AnyUp+AnyDown jako krokové tlačítko průvodce. **Nejrizikovější část, ve hře neověřeno** (dvojí reakce / žádná reakce na `/click`).
- **Jmenovky:** styl „Jako hra“ (`plateStyle`, výchozí) kopíruje font herního jména (`A.GameNameFont`).
- **Questoví mobové:** `Quests/Tooltips.lua` pytel (`Media/UI/quest-loot.tga`) / meč (`quest-kill.tga`) — herní kresby 133639 / 135274 s odříznutým pozadím, uložené i v overlayi; `qol.nameplateIcons` výchozí zapnuto.
- **Auto ranky:** `qol.autoRanks` (výchozí zapnuto) v `QoL/Spells.lua` `CheckRanks` volá `Spells.Upgrade()` jednou na seznam za sezení.
- Lua testy 872 OK; nové `test_loot_window.py`, `test_drawer_macro.py`, `test_guide_plate_icons.py`, `test_guide_auto_ranks.py`, rozšířený `test_bag_window.py`. **Ve hře neověřeno nic z 0.11.9.**

## Vydání 0.11.10 (2026-11-19, noc)
- **Pi:** zip sha256 `fdda5d1b…6280`, 921 souborů, ověřeno stažením (200, `application/zip`, `PK`, TOC 0.11.10). Záloha 0.11.9 v `~/evertally/backups/addon-0.11.9-2026-11-19/`. Sync nainstalovala u uživatele 20:21:00Z. Poznámky `VYDANI-0.11.10.md`. CurseForge ne.
- Služby NPC, hostince a letci ve výchozím stavu na mapě i minimapě (`maps.servicePins`, `serviceMinimap`, `taxiPins`, `innPins`, `travelMinimap` = true; kategorie `on`: repair, mailbox, class, trainer, banker, auctioneer). Herní menu sledování na minimapě (`MENU_MINIMAP_TRACKING`, `Maps.AddServiceMenu`) má nově hostince, letce a ikony cestování. Patche v `tools/import_polestar.py`. Porovnání verzí je číselné (`V.Number`, Sync podle sha256), 0.11.10 > 0.11.9. **Ve hře neověřeno.**

## Vydání 0.11.11 (2026-11-19, noc)
- **Pi:** zip sha256 `d9d3a584…48c3`, 921 souborů, ověřeno stažením (200, `application/zip`, `PK`, TOC 0.11.11). Záloha 0.11.10 v `~/evertally/backups/addon-0.11.10-2026-11-19/`. Sync nainstalovala 20:43:21Z. Poznámky `VYDANI-0.11.11.md`. CurseForge ne.
- Herní ikony sledování: `Maps.GameIcon(kind)` v `Maps/Maps.lua` (tabulka `Maps.GAME_ICONS`, `Interface\Minimap\Tracking\*` + `GossipFrame\VendorGossipIcon` pro obchod; soubor ověřen sondou `SetTexture ~= false`, jinak zůstane `map:` značka), bílá barva `Maps.GAME_WHITE`. Použito v `Services.lua` (kategorie `game`), `ServiceClusters.lua`, `TravelPins.lua` (hostince, letci). **Že je Forever má, nebylo ověřeno** — jen že je používají jiné nainstalované addony (AllTheThings, DialogueUI).
- Evertally menu: první sekce `menuMinimap` (`EvertallyMenu.lua`), dlaždice mají vlastní `text` (popisky z průvodce); zapnutí kategorie zapne i `maps.servicePins` a `serviceMinimap`, hostince/letci `travelMinimap`. Test v `test_evertally_menu.py`.

## Vydání 0.11.12 (2026-11-19, noc)
- **Pi:** zip sha256 `40fdce8f…`, TOC 0.11.12, ověřeno stažením. Záloha 0.11.11 v `~/evertally/backups/addon-0.11.11-2026-11-19/`. Vydáno na výslovné přání uživatele ještě před doběhnutím testů (testy pak 873 OK).
- Oblasti výskytu cílů (`nav.areas`, oblasti kroku a cíle šipky) se na minimapě nekreslí (`minimapAreas = false` v `Nav/Layers.lua`, patch v importéru); na velké mapě zůstávají.
- **CurseForge:** nahráno „Evertally 0.11.12“ (po obnovení seznamu stav „Uploading“, tj. zpracování na straně CurseForge), changelog anglicky od 0.11.8 bez Polestaru. 0.11.8 tam je schválená.

## Nastavení = všechno z instalace (2026-11-19, noc, po 0.11.14) — NEVYDÁNO, necommitnuto
- **Soupis:** z instalace v Nastavení chyběly volba quest trackeru (`et-tracker`), plná volba batohu (`et-bags`, byl jen přepínač `bwReplace`), místa sbírání a jejich druhy (`et-map`), velikost okna (`et-window`, `settings.uiScale`) a tlačítko Spárovat (`et-pair`). Ostatní (jazyk, živá poloha, sdílení, špendlíky, minimapa, jmenovky, hudba, autostart, ověření instalace) tam bylo.
- **Doplněno (`EvertallySettings.lua`):** Rozhraní > nová sekce Questy (dropdown trackeru → `A.SetQuestTrackerChoice`), Okna Evertally > slider velikosti 60–160 % (`A.SetUIScale`), Sdílení a web > Živě a mapa: Místa sbírání + 4 druhy (`settings.mapLayers.gather`, `settings.gatherTypes`, živě přes `A.map.SetLayer/SetGatherType`), Web: Spárovat (`A.RequestPairing`, šedé po spárování). **Nová stránka Batoh** (`evertallybags`): volba batohu (`BW.SetChoice`), okno lootu, sledované předměty (`BW.SetTrackHide`, nové), šipky výbavy (přesunuté z Rozhraní), Upravit kategorie (`BW.Categories.Show()`). Sekce Rozhraní přejmenovaná na „Tooltipy a minimapa“; `bwReplace` z Nastavení pryč (zůstal v menu ozubeného kola okna batohu).
- **Bagnon vedle batohu Evertally (hlášení uživatele):** volba batohu addon jen zakáže (`C_AddOns.DisableAddOn`), což platí až po /reload — setup reload nedělal, takže se otevíraly oba. Teď `BW.Mismatch()` (načtené batohové addony ≠ volba) a `BW.ReloadIfNeeded()`: reload po Dokončit instalace a po změně v Nastavení; při přihlášení s nesouladem se volba použije znovu a vypíše se hláška (`bwPickStill`). **Ve hře neověřeno**, že `DisableAddOn` na Forever Bagnon opravdu vypne (katalog: argument `character` má default "0").
- **Import bez odkazu na Polestar:** `ns.DocsURL()` vracel github.com/fitzforge/polestar (z `X-Website` v TOC). Vypnuto ve forku (`Core/Init.lua`) a prázdný popisek místo „Read more: docs/GUIDE_PACKS.md“ (`UI/Import.lua`, `UI/Packs.lua`); totéž jako `_more(...)` v `tools/import_polestar.py`. Zbývá Polestar v `ns.IssueURL`/Discordu (okno hlášení) a v `Core/Update.lua` (odkaz na vydání) — nekontrolováno, jestli jsou ve hře vidět.
- Testy: nové `test_settings_setup_parity.py` (pokrytí každé stránky instalace, stejné hodnoty jako setup, reload kvůli batohu), `test_guide_no_polestar_links.py`; upravený `test_guide_settings.py`.
- **Vydáno 0.11.15** (2026-11-19, noc): zip sha256 `d188def1…edf2`, 921 souborů, ověřeno stažením (200, `application/zip`, `PK`, sha256, TOC 0.11.15). Záloha 0.11.14 na Pi v `~/evertally/backups/addon-0.11.14-2026-11-19/`. Aplikace a instalátor beze změny (0.9.19). Poznámky `VYDANI-0.11.15.md`. Lua testy 887 OK. CurseForge ne.

## Fórum Evertally místo Discordu/GitHubu Polestaru (2026-11-20) — NEVYDÁNO
- Průvodce posílal hráče Evertally na **Discord Polestaru** (úvod, boční lišta hubu a nastavení, okno Nahlásit problém, poznámka o AI překladu), na **GitHub issue Polestaru** (okno hlášení), na jeho vydání (`U.ReleaseURL`) a na `polestar.guide` (What's new).
- Teď: `ns.DiscordURL` = `https://evertally.afstudio.dev/#forum` (stránka Forum.tsx), kopírovací okno „Fórum Evertally“ s ikonou `icon-talk`, Discord ikona v bočních lištách pryč (`R.SidebarLink`), řádek GitHub v okně hlášení skrytý, návod v okně hlášení přepsaný na fórum, úvod „Fórum Evertally“, `ReleaseURL` a `SITE` na web Evertally. Fork + `_more(...)` v importéru + nové české texty (`EXTRA_CS` i `Evertally_Guide_csCZ/Interface.lua`).
- Zůstává (záměrně): poděkování Polestaru v O addonu (GPL), `ns.IssueURL` a `ns.RepoURL` v kódu (nikde se už neukazují: GitHub řádek skrytý, stránka Guiding Stars vypnutá).
- **Vzhled okna hlášení po skrytí řádku GitHub neověřen** (náhled ani hra). Testy 889 OK (`test_guide_no_polestar_links.py`, upravený `test_polestar_import.py`).
- **Vydáno 0.11.16** (2026-11-20): zip sha256 `f21da4a2…f7f8`, 921 souborů, ověřeno stažením (200, `application/zip`, `PK`, sha256, TOC 0.11.16). Záloha 0.11.15 na Pi v `~/evertally/backups/addon-0.11.15-2026-11-20/`. Sync nainstalovala 18:47:27Z („restartuj WoW (/reload nestačí)“). Poznámky `VYDANI-0.11.16.md`. CurseForge ne.

## Nastavení: sekce jako dlaždice ve 2 sloupcích (2026-11-20) — NEVYDÁNO, necommitnuto
- Uživatel: „překopat kategorie nastavení, jejich vnitřky, ať to má jiné rozložení“; z návrhů vybral **dlaždice ve 2 sloupcích**.
- `Evertally_Guide_Options/UI/Options.lua` `layoutSections`: sekce stránky jsou dlaždice, každá jde do kratšího sloupce; řádky uvnitř dlaždice jsou pod sebou. Přes celou šířku zůstávají výsledky hledání, sekce bez nadpisu, sekce s obrázkovými kartami / `wide` / `columns` a stránka s jedinou sekcí. Dlaždice jen když má sloupec ≥ 330 px (jinak se mačkaly slidery). Patch i jako `_more(...)` v importéru.
- Stránky Evertally rozdělené na pojmenované sekce (`PAGES[].parts[].section` + `keys` = které ovládací prvky): Sdílení a web (Sdílení s hráči, Lidé, Oznámení / Živá poloha, Sbírání na mapě / Web, Aplikace Evertally), Batoh (Batoh, Loot, Sledované předměty, Výbava, Kategorie), Akce (Instalace, Odeslání a export, Nástroje).
- **Záložky zůstaly** (sloučení by rozbilo Základy a skoky „Více“). Ikony v hlavičkách dlaždic nejsou.
- Náhled: `SCREEN="1400, 1000" OPTIONS=<klíč stránky> QUESTS=1 CS=1 OUT=output/x/t.png guide_preview.py …` → `output/x/options.png`; náhled teď registruje i stránky Evertally. Náhled nezalamuje popisky (ve hře `SetWordWrap(true)`), proto v něm dlouhé popisky končí „…“. **Ve hře neověřeno.**
- Testy 890+ OK (nové v `test_settings_setup_parity.py`).

## Aplikace a OpenMap volitelné, aplikace 0.9.20, damage/threat meter (2026-11-20) — NEVYDÁNO, necommitnuto
- **Addon bez povinností:** `A.RequirementsReady()` vrací vždy true (addon běží bez aplikace i OpenMap); `A.RequirementsComplete()` / `A.RequirementsMissing()` říkají, co chybí. Varování `installLimited` (EN/CS) na stránce instalace, ve shrnutí setupu, po Dokončit (chat) a v nápovědě „Ověřit instalaci“. Stránky `et-install` a `et-pair` už neblokují Další. `RequirementsMaybe` nic sám neotevírá. Testy `test_requirements.py` přepsané.
- **Web má aplikaci 0.9.19** (ověřeno: stažené `Evertally.exe` a `EvertallySetup.exe` mají stejný sha256 jako build v repu).
- **Chyba „timeout: global“ (hlášení uživatele):** stahování addonu (58 MB) mělo celkový limit 25 s (`sync/src/addon_update.rs`), instalátor 120 s. Teď `addon_update::download_agent()` bez limitu na stahování (jen 20 s spojení, 30 s první odpověď), použitý pro zip addonu i instalátor.
- **Aplikace 0.9.20:** průvodce při prvním spuštění (`desktop/native/src/bridge_main.rs` `wizard_ui`, 6 kroků, Přeskočit, „Spustit průvodce znovu“ v Nastavení spojení), volba „Automaticky stahovat aktualizace“ (`sync/src/prefs.rs`, `prefs.json`; worker kontroluje jen když je zapnutá nebo při ruční kontrole). První spuštění = bez `prefs.json` i `config.json`; tray pak otevře okno s průvodcem. Náhled: `Evertally.exe --render-preview <složka>` (stránky `wizard0`–`wizard5`). Instalátor sestaven (`Build-Installer.ps1`), **nevydán**. Testy sync 126, desktop 10 OK.
- **Damage meter** (`Meter.lua`, `C_DamageMeter`; Forever nemá pro addony `CombatLogGetCurrentEventInfo`), **threat meter** (`ThreatMeter.lua`, `UnitDetailedThreatSituation`), **jiskřičky** (`LootSparkles.lua`, CVar `outlineModeShowLootEffectWhenDisabled`). Za boje jsou hodnoty secret: addon je jen předává `StatusBar:SetValue` / `AbbreviateNumbers` / `SetText` (vše v `pcall`), nic nepočítá ani neřadí; po boji procenta, rozpad po kouzlech a časy smrtí. Meter zapíná CVar `damageMeterEnabled` (bez ní hra data nesbírá — podle Details, neověřeno ve hře). Herní vestavěné okno meteru se tím může ukázat taky (Edit Mode). Nastavení: stránka **Souboj**. **Nic z toho není ověřené ve hře**, hlavně zobrazení secret hodnot za boje.
- Verze připravené: addon 0.11.17 (`VYDANI-0.11.17.md`), aplikace 0.9.20.
- **Vydáno 2026-11-20 (večer): addon 0.11.17 + aplikace 0.9.20.** Zip sha256 `105e86bf…d9a5`, 980 souborů (včetně nových ikon mapy a minimapy od ChatGPT — uživatel: „ty ikonky tam přidej“), `Evertally.exe` `436c66f1…`, `EvertallySetup.exe` `c6efa690…`; vše ověřeno stažením (200, `PK`/`MZ`, sha256, TOC 0.11.17). Záloha 0.11.16 + 0.9.19 na Pi v `~/evertally/backups/addon-0.11.16-app-0.9.19-2026-11-20/`. Lua testy 910 OK. CurseForge ne.

## Meter jako okna Details, úvod instalace bez Polestaru (2026-11-20, noc) — NEVYDÁNO, necommitnuto
- **Okna meteru** (`Meter.lua`, část „the windows“): libovolný počet (`settings.meter.windows` = `{view, point, width, height, hidden}`; staré nastavení jednoho okna a okna agra se převede). Každé okno: lišta s ikonou a názvem pohledu (klik = menu pohledů po skupinách Poškození / Léčení / Ostatní / Pluginy), tlačítka souboj (`hourglass`), reset, nové okno (`window`), zavřít; dole zámek (všechna okna, `settings.meter.locked`) a úchyt velikosti. Jednoduchý tmavý vzhled, pruhy v barvách tříd.
- **Pluginy** jako pohledy: **Threat** (agro na cíli, `ThreatMeter.lua` dává jen data a přepínače) a **Vanguard** (tanci podle `UnitGroupRolesAssigned`, jejich zdraví; za boje secret → jen předáno pruhu).
- **Tooltip hráče** (najetí myší): kouzla (ikona, množství, za s, %) a cíle (z `combatSpellDetails`), jen mimo boj.
- **Instalace:** nová stránka `et-combat` (damage meter, threat meter, jiskřičky; draft `meter/threat/sparkles` v `Onboarding.lua`).
- **Úvodní stránka instalace** je Evertally (`SetupPages.lua` `P.intro`): logo, pozdrav, šest dlaždic s funkcemi, text o dalších stránkách. Průvodce jen předá stavbu přes `UI.WelcomeIntro` (háček ve forku `UI/Welcome.lua` + `_more` v importéru); když se stránka postavila dřív, než háček byl (náhled), naše `layout` starou schová a postaví svou.
- Náhled: `METER=1|menu QUESTS=1 [CS=1] guide_preview.py …` → `output/guide-preview/meter-*.png`; `SETUP=welcome …` → `setup-welcome.png`. Náhled nekreslí `StatusBar` (pruhy) ani `Logo.tga`.
- Lua testy 915 OK (`test_meter.py` +5 testů oken). **Ve hře neověřeno.**
- **Vydáno 0.11.18** (2026-11-20, noc): zip sha256 `4f1e9e40…21f5`, 980 souborů, ověřeno stažením (200, `application/zip`, `PK`, sha256, TOC 0.11.18). Záloha 0.11.17 na Pi v `~/evertally/backups/addon-0.11.17-2026-11-20/`. Aplikace beze změny (0.9.20). Poznámky `VYDANI-0.11.18.md`. CurseForge ne.
- **Po 0.11.18 (hlášení uživatele):** okno nešlo posunout (horní lišta a nadpis teď berou tažení i se zámkem; zámek drží velikost a řádky); menu pohledů má kategorie s vysouvacím podmenu (`popup(..., level 2)`, `f.menu2`); u hráčů ikonka class (`M.SetClassIcon`: atlas `classicon-<class>`, jinak `UI-CharacterCreate-Classes` + `CLASS_ICON_TCOORDS`). **Meter zapínal herní meter Blizzardu** (`M.Available` nastavoval CVar `damageMeterEnabled` = 1 při každém překreslení) → teď ji jednou vypne (`settings.meter.blizzMeterOff`) a dál ji nechá hráči. Že data `C_DamageMeter` chodí i s vypnutou CVar, je odvozené z Details (vypíná ji a čte dál) — **ve hře neověřeno**. Testy 917 OK. Nevydáno.
- **Vydáno 0.11.19** (2026-11-20, noc): zip sha256 `7cbcfcf5…a2ee`, 980 souborů, ověřeno stažením (200, `application/zip`, `PK`, sha256, TOC 0.11.19). Záloha 0.11.18 na Pi v `~/evertally/backups/addon-0.11.18-2026-11-20/`. Aplikace beze změny (0.9.20). CurseForge ne.
