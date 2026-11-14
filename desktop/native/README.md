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

## Linux a macOS

Stejný kód jako na Windows (`sync/` + `desktop/native/`); rozdíly řeší `sync/src/platform.rs`, `shutdown.rs`, `game.rs`, `screen.rs` a `background.rs`.

| Část | Windows | macOS | Linux |
| --- | --- | --- | --- |
| Hra | `Wow.exe` | nativní `World of Warcraft.app` v `_forever_` (nalezeno v `/Applications/World of Warcraft`), případně `Wow.exe` pod Wine/CrossOver/Whisky | `Wow.exe` pod Wine, Lutris, Bottles, Steam/Proton, Heroic |
| Ikona | oznamovací oblast | horní lišta, bez ikony v Docku | systémová lišta (AppIndicator / StatusNotifier) |
| Jedna instance | pojmenovaný mutex | zamykací soubor (`flock`) | totéž |
| Povely mezi procesy (konec, párování…) | pojmenované eventy | signální soubory ve složce nastavení | `$XDG_RUNTIME_DIR` |
| Autostart s WoW | klíč Run | LaunchAgent `dev.afstudio.evertally.background` | `~/.config/autostart/evertally-background.desktop` |
| Token zařízení | Správce pověření | Klíčenka | Secret Service; bez něj soubor `token-*.key` s právy `0600` ve složce nastavení |
| Živá poloha | čtení pixelů přes GDI | snímek zóny obrazovky, vyžaduje oprávnění *Záznam obrazovky* | čtení pixelů okna přes X11 (i XWayland); čisté Wayland okno nejde číst |
| Aktualizace aplikace | tichý instalátor | zatím ne (nový balíček) | zatím ne (nový balíček) |
| Aktualizace addonu | ano | ano | ano |

Živá poloha na Linuxu a macOS čte omezenou zónu v levém horním rohu okna hry (nejvýše 320 × 200 px, jen v RAM) a značku v ní hledá; rámy oken a Retina škálování tak nevadí a kontrolní součet značky brání falešným nálezům.

### Sestavení

```bash
./Build-Release.sh                 # macOS: releases/Evertally-<verze>-macos-<arch>.zip, Linux: ...-linux-<arch>.tar.gz
```

Linux potřebuje vývojové balíčky: `pkg-config libgtk-3-dev libayatana-appindicator3-dev libxdo-dev libxkbcommon-dev libwayland-dev libx11-dev`. Aplikace v `.zip` pro macOS je podepsaná jen ad-hoc; pro šíření mimo vlastní počítač je potřeba podpis Developer ID a notarizace. GNOME zobrazí ikonu v liště jen s rozšířením *AppIndicator and KStatusNotifierItem Support*.

### Co je ověřeno

Měřeno na macOS (arm64): `cargo test` a `cargo clippy --all-targets -- -D warnings` v `sync` i `native`; běh sestavené `Evertally.app` s izolovaným `HOME` (ikona v liště viditelná na snímku, `bridge-status.json`, druhá instance skončí, `--stop` ukončí most); hlídač s falešným nativním procesem v `_forever_` spustí most, po ručním zavření ho při téže hře nespouští znovu a při nové hře ano; platnost `Info.plist` a LaunchAgentu (`plutil -lint`), ad-hoc podpis (`codesign --verify`).

Nově napsaný kód pro Linux (X11 čtení, hledání Wine procesů a instalací, XDG autostart) a Windows kód se v izolovaném crate přeložily pro `x86_64-unknown-linux-gnu` a `x86_64-pc-windows-gnu`, ale na těchto systémech se nespouštěly. Celý Linux build a testy ověří workflow `.github/workflows/desktop.yml`.

Neověřeno: skutečné čtení živé polohy z běžící hry na macOS a Linuxu (potřebuje přidělené oprávnění Záznam obrazovky, resp. hru pod Wine), nativní okno nastavení na macOS/Linuxu při klikání, tray menu na Linuxu, volba „Spouštět s WoW" včetně LaunchAgentu a XDG souboru na skutečném přihlášení.
