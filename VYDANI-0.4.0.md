# Evertally 0.4.0

Hlavní distribuce je Windows instalátor `releases/EvertallySetup.exe`: aplikace, spouštění s WoW, mapy/databáze a volitelná instalace addonů se zálohou. Watcher otevře aplikaci minimalizovaně; ruční zavření respektuje do dalšího startu hry.

- Mapa ve webu i aplikaci: 60 skutečných herních podkladů, výběr oblasti, zoom/posun a oddělené referenční NPC výskyty.
- Katalog: 10 315 itemů s ikonami, 5 232 questů, 12 078 NPC a 32 dungeonových/raidových zdrojů lootu. Zdroje/stáří jsou přiznané; NPC a quest base data nezahrnují runtime opravy QuestieDB.
- Class/race/item ikony, detail výprav a boss časů, profese/recepty/cooldowny, navštívené oblasti. Desktop má devět pohledů, addon devět karet.
- Veřejné profily a žebříčky účastí; aktivita oblastí shrnuje přispívající účty za 24 hodin od tří účtů na zónu.
- Dva vlastní stručné Evertally návody. Rozsáhlé raidové strategie a automatická aktualizace zatím nejsou součástí.

**Přesná poloha hráčů ani živé sledování se nezobrazuje.** Profil ukazuje jen navštívené oblasti; mapové body jsou NPC, nikoli hráči.

Web 0.4.0 je nasazený; veřejné API, katalogy a hashe staženého addonu, aplikace a instalátoru byly ověřené. Aplikace je nainstalovaná v `%LOCALAPPDATA%\Programs\Evertally`, GUI/watcher hashe i Run registrace jsou zkontrolované a watcher běží bez viditelného okna. Addon 0.4.0 je souborově nainstalovaný s hash kontrolou a zálohou `backups/20261109-231144-927`. Nové ingame UI ještě nebylo vizuálně ověřené ve hře. Důkazy jsou v `releases/verification.json`, `releases/public-verification.json` a manifestech.

Veřejný web prošel 11 headless scénáři mapy, databáze a mobilního zobrazení bez chyb stránky. Desktop má 18 CPU náhledů bez OS okna. 34 Lua replay testů a technické kontroly neprokazují všechny herní události, skutečný start s WoW ani živé Discord přihlášení. Nastavení Discordu je připravené, celý login neověřený kvůli hCaptcha. Rychlostní rekordy jsou do ověření rulesetů vypnuté.
