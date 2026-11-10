# Evertally Desktop 0.4.0

Nativní Windows aplikace v Rustu a egui/eframe bez WebView. Instaluje se přes `releases/EvertallySetup.exe`, který dodá GUI, `EvertallyBackground.exe`, datové `resources` a volitelně herní addony. Vývojový fallback podkladů je `shared/assets`.

Devět pohledů: Overview, Characters, Dungeon journal, Collected data, World map, Database & guides, Rankings & activity, Web sync, Settings. Mapy a ikony jsou shodné s webem. Vlastní pozorování jsou oddělená od katalogu; NPC/quest base data nezahrnují runtime opravy QuestieDB. Návody jsou dva stručné Evertally postupy, nikoli kompletní raidové strategie.

Přesné hráčské pozice se nezobrazují. Postavy mají navštívené oblasti; mapa ukazuje pouze NPC `unit_position` nebo samostatné referenční výskyty. Aktivita znamená přispívající účty za 24 hodin až od tří účtů, ne online populaci.

Watcher je headless binary s Toolhelp kontrolou úplné cesty procesu po čtyřech sekundách. Pro nový WoW Forever PID jednou spustí GUI s `--wow-start` minimalizovaně a bez aktivace. Ruční zavření respektuje do dalšího procesu hry. Windows Run míří na watcher, ne na GUI. Nečte paměť hry ani neovládá UI.

Uložené místní soubory se kontrolují po deseti sekundách, nové změny však zapisuje hra až při `/reload` či odhlášení. Při neúplném souboru zůstává označený poslední dobrý snímek. Sync používá jen povolený export, nikoli hlavní historii/peers. Veřejná data se načítají samostatným tlačítkem; preview nikdy nezahajuje HTTP.

Distribuční server je `https://evertally.afstudio.dev`; existující config má přednost. Přímý Cargo build bez `EVERTALLY_SERVER` má loopback. EN/CS je uložené v `desktop.json`, token ve Windows Credential Manageru. Autoupdate není implementovaný.

## Vývoj a kontrola

Rust 1.95+ a Windows C++ build tools. V tomto adresáři `cargo test` a `cargo clippy --all-targets -- -D warnings`. Pro distribuci z kořene `Build-Release.ps1`, `Build-Installer.ps1 -SkipBuild`, `python tools/package_addon.py`. Build neotevírá GUI ani hru.

- `Evertally.exe --diagnostics`: souhrn místních dat, bez jmen, GUI a synchronizace.
- `Evertally.exe --render-preview <adresář>`: egui geometrie/fonty/textury na CPU do PNG, bez oken, snímání plochy, vstupů, HTTP a tokenů. Tato větev je před GUI.
- `EvertallyBackground.exe --diagnostics`: kontrola procesu bez spuštění aplikace nebo změny autostartu.
- `tools/verify_complete_flow.mjs`: skutečný Rust upload proti izolovanému lokálnímu serveru se syntetickými daty.

CPU snímky mohou obsahovat vlastní historii a nejsou určeny k automatickému zveřejnění. Neověřují klikání, scrollování nebo skutečný start s WoW. `--screenshot` je jiný režim s viditelným oknem; pro náhledy na pozadí se nepoužívá.

Verze 0.4.0 je veřejně nasazená a aplikace skutečně nainstalovaná v `%LOCALAPPDATA%\Programs\Evertally`; GUI/watcher hashe i Run registrace byly zkontrolované. Watcher běží bez viditelného okna. Osmnáct CPU PNG zachycuje panely v EN/CS včetně mapy/databáze bez OS okna. Skutečný start s WoW, nové ingame UI a celý Discord login dosud nejsou provozně ověřené. Viz release reporty a [NAVOD.md](../../NAVOD.md).
