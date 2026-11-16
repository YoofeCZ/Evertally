# Evertally 0.9.51 (addon) + aplikace 0.9.16

## Addon 0.9.51

- **Oznámení nové verze ve hře:** hráči s Evertally si v kanálu #Evertally neviditelně posílají verzi addonu. Když dva různí hráči hlásí novější verzi, do chatu a doprostřed obrazovky přijde „Je venku nový Evertally X (máš Y)“. Jeden hráč sám to vyvolat nemůže. Hráčům se starší verzí se ta naše pošle (nejvýš jednou za 5 minut).
- **Hudba, opravy po hlášení od hráče:**
  - **Spotify Client ID se ukládá** a po reloadu („Načíst knihovnu“) je v poli zas vidět. Dřív si ho pamatovala jen aplikace a pole ve hře bylo po reloadu prázdné.
  - **Vypnutá hudba to řekne.** „Připojit“ dřív hlásilo „Posláno aplikaci Evertally“, i když se při vypnuté hudbě nic neposlalo, a „Obnovit knihovnu“ mlčelo. Teď přijde „Hudba je vypnutá: zapni Přehrávač hudby v Nastavení > Hudba“.
  - **Jak poznat, že aplikace slyší:** první odeslání v sezení (Připojit, Obnovit knihovnu, hledání) vysvětlí, že aplikace odpoví oznámením ve Windows, a co zkontrolovat, když nepřijde (aplikace běží a je 0.9.16+, hra v režimu Okno / Okno (celá obrazovka), levý horní roh hry nezakrytý).
  - **Spotify Dashboard je adresa ke zkopírování**, ne tlačítko: otevření přes aplikaci jiným hráčům nefungovalo. V průvodci i v Nastavení > Hudba jsou pole „Dashboard“ a „Redirect URI“ (klik, Ctrl+C).
  - Text prázdné knihovny už neposílá vybírat zdroj „v aplikaci“ (vybírá se nahoře v okně Hudba).
- Lišta **„Pochlubit se?“** má tlačítko **„Už nenabízet“**: vypne nabídku přímo tam, kde se objevila, a do chatu napíše, že ji zapneš zpátky v Nastavení > Sdílení ve hře.
- **Mini přehrávač po reloadu** se obnoví i po vstupu do světa a ještě jednou za 2 s. Uložená pozice mimo obrazovku se zahodí. Chyba při kreslení je v `/etally diag` („music: …“).
- **Mini přehrávač už neukazuje název skladby** (hra se ho dozvěděla jen při reloadu, takže byl většinou zastaralý).
- **Průvodce při prvním spuštění:** když se otevření nepovede, zkusí se znovu. Chyba je v `/etally diag` („setup: …“). Příčina zatím nebyla ve hře pozorovaná.

Nový soubor v TOC (`Version.lua`): po aktualizaci je potřeba **restart hry**, `/reload` nestačí.

## Aplikace 0.9.16

- **Oznámení ve Windows s průběhem aktualizace:** stahování nového addonu i nové aplikace ukazuje oznámení s ukazatelem průběhu (%), pak „Instaluji…“ a nakonec „Evertally X je nainstalovaný“ / „Aplikace Evertally aktualizována na X“.
- **Hudba potvrzuje příkazy ze hry oznámením:** přihlášení ke Spotify, obnovení knihovny, hledání, změna zdroje → „Evertally slyší hru: …“, po dokončení „Hotovo, ve hře stiskni Načíst knihovnu (reload)“. Chyba (např. nepovedené přihlášení, chybějící Chrome/Edge pro YouTube Music) přijde jako „Evertally: hudba nefunguje“ s důvodem. Dřív šly chyby jen do `sync.log`.
- Instalátor dává zástupci v nabídce Start identitu `AFStudio.Evertally`; bez ní Windows oznámení aplikace nezobrazí. Starší instalace ji dostanou touto aktualizací.

## Co není ověřené

- Oznámení Windows nebyla vidět na vlastní oči před vydáním: potřebují nainstalovaný zástupce s novou identitou, který vznikne až instalací 0.9.16. Ověřit po aktualizaci.
- Proč aplikace kamaráda hru nevidí, zjištěné není. Na tomto PC příkazy dochází (v `sync.log` jsou). Kandidáti: starší aplikace, hra v exkluzivní celé obrazovce (snímek okna bývá černý), zakrytý levý horní roh. Nová oznámení ukážou, jestli příkaz dorazil; `sync.log` je v `%APPDATA%\Evertally\Evertally Sync\config\`.
