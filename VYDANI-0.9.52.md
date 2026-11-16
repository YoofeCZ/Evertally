# Evertally 0.9.52 (addon) + aplikace 0.9.17

## Addon 0.9.52

- **Playlisty jdou rozkliknout.** V okně Hudba ukazuje `+` před playlistem, že má skladby:
  - **klik** skladby rozbalí pod ním (odsazené), další klik je schová,
  - **dvojklik na skladbu** (nebo vybrat a Přehrát) ji pustí **uvnitř playlistu**, takže playlist pak hraje dál,
  - **dvojklik na playlist** pustí celý playlist jako dřív,
  - **filtr** najde i skladby uvnitř playlistů: playlist se sám rozbalí jen s nalezenými skladbami,
  - nápověda při najetí myší na řádek.
  Skladby přijdou s knihovnou: po aktualizaci je potřeba jednou **Obnovit knihovnu** a pak **Načíst knihovnu (reload)**.
- **Názvy z emoji** (např. „D&B 🔥🔥“) se už neukazují jako čtverečky: herní písmo emoji neumí, aplikace je vynechá. Playlist pojmenovaný jen emoji se jmenuje „(bez názvu)“ a nezmizí.
- Tlačítka **Obnovit knihovnu** a **Načíst knihovnu (reload)** jsou širší, česky už text nenaráží na okraj.
- **Jízdní řády lodí a zeppelinů na mapě** (z DockWatch 1.8.1, Wyveryx, MIT): u každého přístavu je špendlík s časem do dalšího odjezdu („~2:14“), v tooltipu kam loď jede, kdy odjíždí a jak dlouho pluje. Ve výchozím stavu zapnuté; vypíná se v menu OpenMap, sekce Evertally, položka „Boat and zeppelin times“ (OpenMap dostává popisek anglicky). Časy se dopočítávají z jednoho skutečného odjezdu na trasu, ve hře se nic nesleduje ani neučí. Potřebuje modul Evertally - Map (OpenMap).

Nové soubory v TOC modulu mapy (`TransportData.lua`, `Transports.lua`): po aktualizaci **restart hry**, `/reload` nestačí.

## Aplikace 0.9.17

- **Hledání na Spotify zase vrací výsledky.** Spotify v únoru 2026 snížil nejvyšší povolený počet výsledků hledání z 50 na 10 a na náš dotaz s 20 odpovídal chybou (HTTP 400), takže záložka Výsledky zůstala prázdná. Teď se ptáme na 10 skladeb a 10 playlistů.
- **Chyba Spotify v oznámení i v logu má důvod** od Spotify („HTTP 400: Invalid limit“), ne jen číslo.
- **Knihovna obsahuje skladby playlistů** (až 100 z každého z prvních 50 playlistů):
  - Spotify přes nový `/playlists/{id}/items`. Spotify je vývojářské aplikaci (kterou má každý hráč vlastní) dává jen u **vlastních a společných** playlistů; cizí sledované playlisty zůstanou nerozbalitelné, přehrát jdou dál.
  - YouTube Music z té samé přihlášené stránky, po 8 playlistech najednou.
  Obnovení knihovny proto trvá déle (odhad: desítky sekund, neměřeno).
- Počet skladeb u playlistu Spotify se čte z nového pole `items` (dřív `tracks`, Spotify ho přejmenoval).
- Nový příkaz ze hry `m:pt:<skladba>@<playlist>`: Spotify spustí playlist od dané skladby (bez Premium otevře skladbu v aplikaci Spotify), YouTube Music otevře `watch?v=…&list=…`.

## Co je ověřené a co ne

| | Stav |
|---|---|
| Lua testy addonu | celá sada 748: 747 prošlo, 1 spadl (menu OpenMap počítalo přesný seznam položek a nová položka lodí v něm chyběla); test upraven a moduly openmap + lodě + hudba (45 testů) znovu prošly |
| Rust: 119 testů `sync`, clippy bez varování v `music`, `desktop/native` se přeloží | prošlo |
| Limit hledání Spotify | podle changelogu Spotify (únor 2026), **ne** změřeno: na tomhle PC Spotify přihlášený není, chyba v `sync.log` tu nebyla |
| Skladby playlistů ze Spotify a YouTube Music proti skutečným službám | **neověřeno** |
| Rozbalování a přehrávání ve hře | **neověřeno ve hře** (jen testy s napodobeným UI) |
| Časy lodí proti skutečnosti | **neověřeno**: DockWatch počítá od odjezdů z 11. 10. 2026 a podle vlastního popisu platí jen do restartu serveru, takže po restartu můžou časy nesedět. Na tooltipu to stojí. |
