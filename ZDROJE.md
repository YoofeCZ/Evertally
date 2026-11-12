# Podklady a hranice ověření

Stav rešerše: 9. listopadu 2026. Webové popisy jsou tvrzením daných autorů; neznamenají, že jsme jejich služby otestovali v živé hře.

## 1. Přenos mezi addonem a webem

### Raider.IO

Oficiální dokumentace rozlišuje addon a desktopovou aplikaci. Aplikace aktualizuje datové podklady a používá combat log pro Live Tracking. Současný repozitář také popisuje vlastní pozorování questů, NPC a lootu ukládaná do SavedVariables po reloadu/odhlášení. To dokládá více přenosových cest, nikoli přímé HTTP volání Lua addonu.

- [Oficiální popis addonu a aplikace](https://raider.io/addon)
- [Dokumentace Live Tracking](https://support.raider.io/kb/raider-dot-io-mythic-plus-addon/live-tracking-troubleshooting)
- [Zdrojový repozitář a README](https://github.com/RaiderIO/raiderio-addon)

Použití pro tento návrh: oddělit data na disku, externí upload a zobrazení importovaného přehledu ve hře. Raider.IO se navrhuje jako reference architektury, ne jako zdroj ke zkopírování dat konkurenční služby.

### Wowhead

Wowhead Looter sbírá data v addonu a Wowhead Client je nahrává do databáze. Jde o existující příklad komunitního sběru herních pozorování.

- [Oficiální popis Wowhead Client](https://www.wowhead.com/client)

Použití pro návrh: samostatné sběrače a centrální konsolidace. Přímo z tohoto popisu nelze dovodit dostupnost libovolného požadovaného pole ve Foreveru.

### Prohlížeč

Directory picker má omezenou podporu, vyžaduje vhodný kontext a aktivaci uživatelem. Přístup může být jen pro čtení. Oprávnění se musí ověřovat a uživatel může výběr odmítnout.

- [MDN: showDirectoryPicker](https://developer.mozilla.org/en-US/docs/Web/API/Window/showDirectoryPicker)
- [MDN: File System API](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API)
- [Chrome: File System Access API](https://developer.chrome.com/docs/capabilities/web-apis/file-system-access)
- [Chrome: persistent permissions](https://developer.chrome.com/blog/persistent-permissions-for-the-file-system-access-api)

Použití pro návrh: volitelná cesta přes prohlížeč, bez požadavku dalšího programu, s běžným file-import fallbackem. Nejde o důkaz trvalého běhu zavřené či uspané stránky.

## 2. Existující podobné projekty

### Dungeon Ledger

Autor uvádí osobní dungeonové běhy, časy, souhrny a sdílení s přáteli. Při předchozí kontrole aktuálně nabízeného balíčku `DungeonLedger1.0.zip`, file ID 9286340, byly v `Sync.lua` přímo nalezeny `C_ChatInfo.SendAddonMessage` pro whisper a `C_BattleNet.SendGameData`/`BNSendGameData`. `.toc` deklaruje vlastní SavedVariables. To dokládá ingame přenos. Nebyl proveden živý test jeho funkčnosti.

- [Popis Dungeon Ledgeru](https://www.curseforge.com/wow/addons/dungeonledger)
- [Konkrétní instalační balíček](https://www.curseforge.com/wow/addons/dungeonledger/files/9286340)

Použití pro návrh: lokální historie a sdílení mohou být hodnotné samostatně. Současně nejde o nový, nikým neřešený problém.

### ForeverDB

Autor popisuje addon, uploader, browser import, armory a sběr světových i dungeonových dat. Dokumentace live logů popisuje čtení uživatelem vybrané logové složky přes prohlížeč. Web má také žebříčky. Funkční pokrytí nebylo nezávisle otestováno.

- [ForeverDB Uploader a seznam přenášených oblastí](https://foreverdb.net/uploader)
- [Browser live logging](https://foreverdb.net/live-logs)
- [Žebříčky](https://foreverdb.net/leaderboards)

Použití pro návrh: rozsah produktu má přímou konkurenci. Odlišení navrhujeme ve snadno použitelném samostatném addonu, odděleném souhlasu pro web, průhledném původu dat a srovnatelných pravidlech běhů. Jde o zamýšlené vlastnosti našeho produktu; netvrdíme, že je konkurence nemá.

## 3. Read-only kontrola místních addonů

Instalace: `D:\World of Warcraft\_forever_\Interface\AddOns`.

### QuestMaster

- [QuestMaster_Forever.toc](<D:/World of Warcraft/_forever_/Interface/AddOns/QuestMaster/QuestMaster_Forever.toc:7>) obsahuje interface 16000/16001 a další varianty.
- Stejný soubor uvádí verzi 2.76.0.

Závěr: doklad konfigurace nainstalovaného addonu, nikoli potvrzení buildu právě spuštěného klienta. Do těchto souborů nebylo při přípravě zadání zasahováno.

### ForeverDungeonJournal

- [RPGMode.lua](<D:/World of Warcraft/_forever_/Interface/AddOns/ForeverDungeonJournal/Systems/RPGMode.lua:797>): registrace bossových a questových událostí; zpracování `ENCOUNTER_END` a `BOSS_KILL` přibližně od řádku 873.
- [Stejný soubor, lootové zdroje](<D:/World of Warcraft/_forever_/Interface/AddOns/ForeverDungeonJournal/Systems/RPGMode.lua:2170>): použití `GetLootSourceInfo` v souvislosti s více zdroji lootu.
- [MapMarkers.lua](<D:/World of Warcraft/_forever_/Interface/AddOns/ForeverDungeonJournal/Systems/MapMarkers.lua:124>): guarded čtení vlastní mapové pozice a kontroly dostupnosti.

Závěr: relevantní implementační vzory existují v nainstalovaném zdroji. Samotná registrace události neprokazuje, že dorazí v každé instanci a že všechny její údaje budou čitelné.

### SkillUp Forever

- [SkillUpForever.toc](<D:/World of Warcraft/_forever_/Interface/AddOns/SkillUpForever/SkillUpForever.toc:1>): interface 16001 a verze v1.1.5.
- [Core.lua](<D:/World of Warcraft/_forever_/Interface/AddOns/SkillUpForever/Core/Core.lua:685>): rozlišení vlastního profesního kontextu od linknutého/guildovního.
- [Načítání receptů](<D:/World of Warcraft/_forever_/Interface/AddOns/SkillUpForever/Core/Core.lua:784>): využití `GetAllRecipeIDs` a `GetRecipeInfo`.
- [Prices.lua](<D:/World of Warcraft/_forever_/Interface/AddOns/SkillUpForever/Integrations/Prices.lua:222>): použití receptového schématu.

Závěr: profesní sběr musí respektovat kontext a načtení dat. Výrobu nelze bez dalšího prokázat jen tím, že byl recept v seznamu.

## 4. Co bylo a nebylo ověřeno

| Tvrzení | Stav |
| --- | --- |
| Zadání odpovídá požadavku addon bez povinného webu a volitelné webové přispívání | Rozpracováno v produktových a technických pravidlech |
| Existují služby používající externí přenos z logů/SavedVariables | Doloženo uvedenými primárními popisy |
| Dungeon Ledger má ingame datové transporty | Ověřeno čtením konkrétního balíčku; bez runtime testu |
| Nainstalované addony používají uvedená questová, mapová a profesní rozhraní | Ověřeno zdrojovým čtením |
| Náš addon sbírá, sdílí nebo exportuje skutečné údaje | Implementováno od 0.4.0 a pokryto Lua replay testy (107 v 0.6.0); v živé hře neověřeno |
| Umíme přesně časovat všechny dungeony/raidy | Neověřeno; předpokládá etapa 0 a validace každého rulesetu |
| Máme kompletní spawn místa, drop rate nebo celoserverová data | Ne; návrh takové tvrzení zakazuje bez odpovídajícího podkladu |
| Web a ingame databáze se synchronizují v živém klientu | Částečně od 0.6.0: historie přes uložení hry a Bridge, živá vlastní poloha přes datový proužek; obojí ve hře neověřeno |
| Veřejné výsledky jsou nezfalšovatelné | Ne; klientské reporty takový důkaz neposkytují |
| Název Forever Atlas je dostupný | Ne — používá ho jiný addon na CurseForge (Talexander977). Projekt přejmenován na Evertally (2026-11-09) |

## 5. Pokyny pro navazujícího realizátora

Začít dokumentem [PLAN_A_OVERENI.md](PLAN_A_OVERENI.md), etapou 0. Cizí addony slouží jako read-only evidence dostupných vzorů. Při vlastní implementaci se nekopíruje jejich proprietární kód ani celé databáze; případná použitá knihovna musí mít ověřenou licenci a zachované předepsané attribution.

Před úpravou vlastní produkční instalace si znovu ověřit její cestu a stav. Toto zadání je uložené samostatně v `D:\addon` a existující addonové soubory nemění.

## 10. Podklady pro novou mapu a databázi (10. listopadu 2026)

Seznam zdrojů, licencí a toho, co se z nich bere, je v `THIRD_PARTY.md`. Rešerše addonů nainstalovaných ve hře potvrdila: OpenMap (MIT) má použitelné datové tabulky a chování plynulé mapy; Shortest Path Forever nese jízdní řády a pěší vzdálenosti pro plánování cest; AtlasLoot dodává raidový loot a změřené šance na drop; SkillUp Forever recepty; LibForeverData tipy ke questům. WowfCZ obsahuje české překlady, ale bez licence, takže se nepoužívá bez svolení autora. Platí stejná hranice jako výše: popis autora není test v živé hře.

