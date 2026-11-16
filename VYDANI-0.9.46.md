# Evertally 0.9.46 (aplikace 0.9.14)

## Hudba: Spotify a YouTube Music ze hry

Nový přehrávač hudby. **Ve výchozím stavu je vypnutý**: zapíná se v Nastavení → Rozhraní → „Přehrávač hudby“ nebo příkazem `/etally music`. Kdo ho nezapne, neuvidí nic nového. Vzhled ani dosavadní proužek polohy se nemění.

**Ve hře:**
- **Mini přehrávač** nahoře uprostřed (dá se přesunout): předchozí, play/pauza, další, hlasitost −/+, tlačítko **Knihovna**.
- **Knihovna:**
  - volba **Spotify / YouTube Music**,
  - u Spotify pole **Client ID** s návodem v tooltipu tlačítka Připojit,
  - **hledání na Spotify / YouTube Music** (Enter),
  - **filtr vlastní knihovny** (bez ohledu na diakritiku),
  - záložky **Playlisty / Oblíbené skladby / Naposledy hrané**; dvojklik spustí položku,
  - tlačítka **Obnovit knihovnu** a **Načíst knihovnu (reload)**.
- **Ztišení:** při rozhovoru s NPC (questgiver, obchodník) se hudba ztiší a po zavření okna vrátí. Vypnout jde v Nastavení.

**Jak to funguje:**
- Hra nesmí na síť ani spouštět programy. Příkazy proto jdou **pixelovým proužkem** v levém horním rohu (stejné tmavé odstíny a místo jako proužek živé polohy, jeden řádek 1 px, na 0,6 s), který **aplikace Evertally** čte několikrát za sekundu.
- Knihovnu aplikace zapíše do `MusicData.lua` a hra ji načte po `/reload` (tlačítko „Načíst knihovnu“). Aktualizace addonu tento soubor nepřepíše.
- **Ovládání** (play, pauza, skok, hlasitost, ztišení) jde přes mediální ovládání Windows. Funguje s **jakýmkoli** přehrávačem: aplikací Spotify, oknem YouTube Music i prohlížečem. Ztišení mění hlasitost jen přehrávače v mixéru Windows, ne hry.
- **Spotify:**
  - Každý hráč si založí vlastní vývojářskou aplikaci (zdarma, 5 minut: developer.spotify.com/dashboard, Redirect URI `http://127.0.0.1:8765/callback`, Web API). Spotify jinak novou aplikaci pustí jen pár ručně přidaným účtům.
  - Client ID se vloží ve hře a prohlížeč se jednou otevře k přihlášení. Přihlášení drží aplikace v úložišti hesel Windows.
  - Spuštění vybraného playlistu vyžaduje **Spotify Premium**. Bez něj se playlist otevře v aplikaci Spotify.
- **YouTube Music:**
  - Aplikace otevře YouTube Music ve **vlastním okně Chrome nebo Edge s odděleným profilem**. Jednou se v něm přihlásíš.
  - Knihovnu čte ze stránky, ke které jsi přihlášený: playlisty, oblíbené, historie. YouTube nemá veřejné API pro osobní knihovnu, takže změna na straně YouTube může rozbít seznam knihovny, ovládání ne.
  - Výběr položky nebo hledání se otevře v tom okně.
- Aplikace **nečte paměť hry a neposílá do hry žádné klávesy**, stejně jako u živé polohy.

**Co zatím chybí:**
- Karta „právě hraje“ přes hru. Ve hře se název skladby ukáže až po načtení knihovny.
- Nálady podle místa (boj, dungeon, hospoda).
- Přihlášení ke Spotify a obnovení knihovny běží ve stejném vlákně jako ovládání, takže během přihlašování (až 5 minut) tlačítka přehrávače čekají.

**Ověřeno:**
- Testy addonu (příkazy, fronta, ztišení, knihovna, okna) i aplikace: parsování příkazů, zápis `MusicData.lua`, PKCE podle příkladu z RFC 7636, čtení knihoven Spotify a YouTube, párování zvukových relací.
- **Dekodér v aplikaci přečte příkaz nakreslený Lua addonem**, i s posunutými odstíny (společný vzorek `tests/lua/fixtures/optical_command.json`).
- **Ve hře ani se skutečným Spotify nebo YouTube Music zatím vyzkoušené není.**

Nové soubory v TOC (`MusicData.lua`, `Music.lua`): po aktualizaci je potřeba **restart hry**. Aplikace se aktualizuje na 0.9.14.
