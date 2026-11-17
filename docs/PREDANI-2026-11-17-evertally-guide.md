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
