# Evertally Bridge pro Windows 0.5.0

Instalátor `releases/EvertallySetup.exe` nainstaluje most pro aktuálního uživatele. Po spuštění je vidět jen ikona v oznamovací oblasti vedle hodin Windows, případně pod šipkou nahoru. Mapa, databáze a herní přehledy byly z Windows distribuce odstraněny; jsou na webu a v herním addonu.

Pravým tlačítkem na ikoně otevřeš:

- stav synchronizace a počet nalezených složek účtů WoW;
- synchronizovat teď a otevřít web;
- spárovat / odpojit tento počítač, během párování kód a možnost zrušení;
- spouštění s WoW;
- nastavení spojení (server a cesta k WoW), složku nastavení a ukončení mostu.

Zástupce Start → Evertally — Web sync otevře malé okno s kartami Web sync a Nastavení spojení. Web sync obsahuje párování, párovací kód, stav spojení, synchronizaci, odpojení a uložená oprávnění exportu. Hlavní běžící most zůstává v oznamovací oblasti. Požadavek na párování otevírá schvalovací stránku v prohlížeči; běžný start mostu prohlížeč neotevírá.

`EvertallyBackground.exe` kontroluje cestu nových procesů WoW Forever každé čtyři sekundy a spustí most bez hlavního okna. Jediná instance mostu používá stávající konfiguraci a Windows Credential Manager. Ukončení přes ikonu platí až do dalšího nového startu hry. Vypnutí automatického spouštění odstraní Run registraci a zastaví watcher.

Instalátor před aktualizací požádá watcher, most a nastavení o korektní ukončení přes jejich vlastní pojmenované události. Nekončí hru. Při přechodu ze staré verze 0.4.0 může být nutné staré hlavní okno ručně zavřít; tato verze ještě protokol ukončení mostu nemá. SavedVariables, účty, token a konfigurace se při aktualizaci nemění. Předchozí konfigurace se při uložení nového nastavení zálohuje do `config.json.bak`.

Přenos zatím reaguje na uložení `Evertally_Export.lua` při `/reload` nebo odhlášení. Živý most polohy z běžící hry na web ještě není implementovaný. Ve hře se živé zprávy mezi hráči přenášejí samostatně přes addon kanály.

## Ověření

- `cargo test` a `cargo clippy --all-targets -- -D warnings` v `native`;
- `cargo test --lib` a clippy v `sync`;
- `tests/installer/test-addon-install.ps1` ověřuje izolovanou falešnou instalaci: signál ukončení, uvolnění zamčeného souboru, zálohy a aktualizaci všech tří addonů;
- `Evertally.exe --render-preview <adresář>` vykreslí pouze nastavení na CPU bez OS oken, tokenů, síťových požadavků nebo vstupů do počítače;
- `Build-Release.ps1`, `Build-Installer.ps1 -SkipBuild`, `tools/package_addon.py` sestaví a ověří distribuci bez spuštění mostu.

Nativní tray menu a skutečný start s WoW se těmito kontrolami vizuálně neověřují. Staré soubory desktopových pohledů v `native/src` nejsou součástí sestavovaných binárních souborů; historie zůstává v Gitu.
