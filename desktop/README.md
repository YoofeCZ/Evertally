# Evertally pro Windows 0.4.0

Hlavní distribuce je `releases/EvertallySetup.exe`. Per-user instalace do `%LOCALAPPDATA%\Programs\Evertally` obsahuje GUI, watcher, mapy/databáze a volitelně addony se zálohou. Součástí je Start a odinstalace; desktopový zástupce je volitelný. Portable ZIP a samostatné EXE nejsou hlavní instalační postup.

Devět pohledů: Přehled, Postavy, Deník výprav, Nasbíraná data, Mapa světa, Databáze a návody, Žebříčky a aktivita, Webová synchronizace, Nastavení. Místní historie a podklady fungují offline. Web a aplikace sdílejí mapové a class/race/item podklady.

**Spouštět s WoW** registruje `EvertallyBackground.exe` v per-user Windows Run. Po čtyřech sekundách kontroluje proces/cestu WoW Forever; při novém procesu jednou otevře aplikaci minimalizovaně. Zavření respektuje do dalšího startu hry. Nečte paměť a neovládá hru. Settings umí registraci i watcher vypnout.

Nová data vidí aplikace až po zápisu SavedVariables při `/reload` či odhlášení. Hlavní `Evertally.lua` zůstává místní; na web jde pouze schválený export po párování. Tlačítko Načíst komunitní data načítá veřejné účasti a aktivitu oblastí. Ta není živá populace: jde o přispívající účty za 24 hodin, minimálně tři na oblast.

Přesné hráčské pozice se nezobrazují ani v surových detailech. U postavy jsou jen navštívené oblasti. Mapové piny jsou NPC `unit_position` nebo oddělené referenční výskyty.

Settings přijímá cestu WoW a server. Distribuce používá `https://evertally.afstudio.dev`, existující `config.json` má přednost a aktualizace jej nepřepisuje. Jazyk je v `desktop.json`, token ve Správci pověření Windows. Automatická aktualizace zatím není implementovaná.

## Sestavení a důkazy

Z kořene `Build-Release.ps1`, potom `Build-Installer.ps1 -SkipBuild`. Konkrétní Inno Setup compiler z NuGet se lokálně rozbalí a ověří podpis; neinstaluje se globálně. Build neotevírá GUI ani WoW. Balení a hashe: `tools/package_addon.py`, `releases/installer-manifest.json`.

V `native` používej `cargo test` a `cargo clippy --all-targets -- -D warnings`. `--render-preview <adresář>` vykresluje panely na CPU bez oken, HTTP, tokenů a vstupů do PC. `--diagnostics` vypíše souhrn bez jmen; watcher má vlastní diagnostiku. To neprokazuje reálné ovládání ani start s WoW.

Aplikace 0.4.0 je skutečně nainstalovaná v `C:\Users\domin\AppData\Local\Programs\Evertally`; hash GUI/watcheru, resources, odinstalace a Run registrace byly zkontrolované. Watcher běží bez viditelného okna. Web 0.4.0 je nasazený a hashe veřejných balíčků ověřené. Skutečný start s běžící hrou, nové ingame UI a celý Discord login zatím nejsou ověřené; poslední blokuje hCaptcha. Aktuální důkazy jsou v release reportech a [NAVOD.md](../NAVOD.md).
