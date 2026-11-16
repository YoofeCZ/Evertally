# Evertally 0.9.49 (aplikace 0.9.15)

## Spotify: tlačítko na Dashboard a Redirect URI ke zkopírování

- V průvodci (krok Hudba) i v Nastavení → Hudba je u Spotify:
  - tlačítko **„Otevřít Spotify Dashboard“**: hra pošle příkaz a **aplikace Evertally otevře developer.spotify.com/dashboard v prohlížeči** (hra sama web otevřít neumí). Funguje i před zapnutím hudby, tedy už v průvodci.
  - pole **Redirect URI** s `http://127.0.0.1:8765/callback`: klikni a zkopíruj Ctrl+C, nemusí se přepisovat.
- Nápověda je jako postup v krocích a vysvětluje, že **127.0.0.1 je hráčův vlastní počítač**: přihlášení ke Spotify tam zachytí aplikace Evertally na jeho PC, nic nejde na server Evertally ani jinam.
- V průvodci nápověda říká „po Dokončit“, v Nastavení „stiskni Připojit“, podle toho, co na obrazovce opravdu je. Dřív průvodce zmiňoval tlačítko Připojit, které v něm nebylo.

Aplikace 0.9.15 umí nový příkaz pro otevření Dashboardu. Se starší aplikací tlačítko nic neudělá.

## Mini přehrávač a hledání

- Mini přehrávač má **zvlášť Přehrát a Pauza** s nakreslenými ikonami, plus Předchozí, Další, Ztišit a Zesílit (s popisky při najetí myší). Dřív bylo jedno tlačítko „>||“, u kterého nešlo poznat, co udělá. Hra neví, jestli hudba hraje, proto dvě jasná tlačítka místo přepínače. Ikony jsou nové textury: načtou se po restartu hry.
- **Hledání plní seznam ve hře:** Enter v poli hledání pošle dotaz aplikaci. Ta výsledky (skladby a playlisty) načte na pozadí ze Spotify nebo YouTube Music a zapíše je do knihovny. **Okno YouTube Music se při hledání nepřepíná, takže hrající skladba neskončí.** V okně hudby se ukáže záložka **Výsledky** se zprávou, že se hledá, a tlačítko **Načíst výsledky (reload)**. Po načtení se okno samo otevře na výsledcích a dvojklik skladbu pustí.
- **Právě hraje:** při každém zápisu knihovny (obnovení, hledání) aplikace doplní aktuální skladbu z ovládání Windows. Mini přehrávač ji ukáže po načtení.
- **Omezení hry:** aplikace nemá jak hře poslat data živě. Hra soubor od aplikace načte jen při přihlášení nebo `/reload`, proto výsledky i „právě hraje“ potřebují načtení. Živé zobrazení by šlo jen okénkem aplikace přes hru (jako Karen's Music Solutions).
- Opraveno: prázdná záložka (třeba Výsledky před prvním hledáním) ukazovala omylem playlisty.

Bez nového souboru v TOC: stačí `/reload`.

Ve hře zatím vyzkoušené není.
