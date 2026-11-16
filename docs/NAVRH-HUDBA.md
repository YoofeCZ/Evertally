# Návrh: hudba ve hře přes aplikaci Evertally

Stav: **návrh k odsouhlasení**, nic z toho není naprogramované. Datum: 2026-11-15.

## Výchozí bod

Addon WoW nesmí na síť ani spouštět programy a sám hudbu nepřehraje. Existují dva kanály, oba už v Evertally fungují:

| Směr | Jak | Rychlost | V Evertally |
|---|---|---|---|
| hra → aplikace | proužek pixelů v levém horním rohu, aplikace ho čte z obrazovky | živě (desítky ms) | `addon/Evertally/Optical.lua`, čtení v `sync/src/optical.rs` |
| aplikace → hra | soubor ve složce addonu, hra ho načte při přihlášení nebo `/reload` | jen po `/reload` | `RankingData.lua`, `BridgeInstallation.lua` |

Karen's Music Solutions (rozebráno 2026-11-15, verze 1.1.1) to řeší stejně: příkazy z addonu jdou pixely, knihovna jde souborem po `/reload` a vše, co má být „živé“ (výsledky hledání, právě hraje), kreslí jejich aplikace **vlastním oknem přes hru**. Jejich kód je *All Rights Reserved*: přebíráme princip, žádný kód.

## Co by uměl Evertally

### Fáze 1: ovladač a „právě hraje“ (bez účtů, bez Premium)

- **Zdroj:** Windows mediální ovládání (System Media Transport Controls). Funguje s **jakýmkoli** přehrávačem, který se ukazuje ve Windows v mediálním panelu: aplikace Spotify, YouTube Music (aplikace i prohlížeč), Apple Music, VLC…
- **Ve hře:** malý přehrávač ve stylu Evertally (předchozí, play/pauza, další, hlasitost hudby) a klávesové zkratky (Bindings). Příkaz jde pixely do aplikace, aplikace ho předá Windows.
- **„Právě hraje“:** aplikace zná název a interpreta skladby. Do hry se živě dostat nemůže, proto ho ukáže **malou kartou přes hru** (vlastní okno aplikace, vpravo dole, pár sekund, nekrade focus). Vyžaduje režim *Windowed (Fullscreen)*, což je výchozí režim WoW.
- **Ztišení:** při rozhovoru s NPC (questgiver, obchodník) addon pošle „ztiš“ a aplikace sníží hlasitost přehrávače v mixéru Windows, po zavření okna ji vrátí.
- **Nálady (volitelné):** addon zná situaci (boj, dungeon, hospoda, město) a pošle ji aplikaci. V Nastavení se dá ke každé náladě přiřadit playlist (ve fázi 1 jen otevřením odkazu `spotify:` nebo YouTube).

### Fáze 2: knihovna ve hře

- **Spotify:** přihlášení přes Spotify v prohlížeči (PKCE, token v úložišti hesel Windows, `keyring` už aplikace používá).
  - **Limit Spotify:** nová vývojářská aplikace smí mít jen pár ručně přidaných uživatelů a pro rozšíření je potřeba schválení od Spotify (podmínky jsou přísné, ověřit aktuální stav). Karen to obchází tím, že si **každý hráč založí vlastní vývojářský klíč**: je to 5 minut návodu a funguje to hned. Doporučuji stejně, s průvodcem v aplikaci.
  - **Spuštění konkrétního playlistu nebo skladby přes Web API vyžaduje Premium.** Bez Premium jen otevřít ve Spotify.
- **YouTube Music:** oficiální API pro knihovnu nemá. Karen ovládá YouTube Music v samostatném okně prohlížeče přes jeho vývojářské rozhraní (Chrome DevTools Protocol). Funguje, ale je křehké (změny webu YouTube). Doporučuji až po Spotify, nebo vůbec.
- **Ve hře:** prohlížeč knihovny v okně Evertally (playlisty, oblíbené, naposledy hrané, filtr při psaní). Seznam přijde souborem `MusicData.lua`, který aplikace zapíše a hra načte při `/reload` (tlačítko „Načíst knihovnu“). Dvojklik pošle pixely „pusť playlist X“.

### Fáze 3 (volitelná): vyhledávání

- Napíšeš hledaný výraz ve hře, Enter pošle pixely, aplikace ukáže výsledky **ve svém okně přes hru**. Kliknutím se skladba pustí. Hra má dál klávesnici.

## Technicky

- **Pixely:** Optical.lua dnes kreslí jen při zapnuté živé poloze. Přidá se typ paketu „příkaz“ (sekvenční číslo, krátký text, kontrolní součet), který se ukáže na zlomek sekundy. Poloha a příkazy se střídají ve stejném proužku.
- **Pozor na Karen:** Karen kreslí svůj proužek **na stejné místo** (levý horní roh, strata TOOLTIP). Kdo má oba addony, tomu by se proužky překryly a ani jedna aplikace by to nepřečetla. Řešení: Evertally svůj proužek posune nebo se Karen vyhne, když je načtená (`KarensMusicSolutions` v seznamu addonů).
- **Aplikace (Rust):** nový modul `music` v `sync/` (SMTC přes WinRT `Windows.Media.Control`, hlasitost přes `ISimpleAudioVolume`), okénko přes hru v `desktop/native` (eframe už aplikace používá; okno bez rámečku, vždy navrchu, neaktivující).
- **Pravidla Blizzardu:** aplikace nečte paměť hry a neposílá do hry žádné klávesy. Čte jen pixely, které addon sám vykreslí, a zapisuje soubor, který hra načte sama. Stejně jako dnes poloha.

## Odhad práce (odhad, ne měření)

| Fáze | Addon | Aplikace | Celkem |
|---|---|---|---|
| 1: ovladač, právě hraje, ztišení, nálady | 1 den | 2 dny | ~3 dny |
| 2: knihovna Spotify | 1 den | 2 dny | ~3 dny |
| 3: vyhledávání | 0,5 dne | 1,5 dne | ~2 dny |

## Otázky k rozhodnutí

1. Začít fází 1 (funguje s čímkoli, bez účtů), nebo rovnou Spotify knihovnou?
2. Spotify přes vlastní klíč každého hráče (jako Karen), nebo žádat Spotify o schválení jedné aplikace Evertally?
3. YouTube Music knihovnu dělat (křehké), nebo jen ovladač přes Windows?
4. Okénko „právě hraje“ přes hru: ano, nebo jen ve hře po `/reload`?
