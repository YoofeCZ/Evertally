# Evertally 0.9.53 (addon)

- **Nápověda u staré knihovny.** Když knihovna hudby ještě nemá skladby playlistů (zapsala ji aplikace starší než 0.9.17), tooltip playlistu řekne, co udělat: stisknout **Obnovit knihovnu**, počkat na oznámení aplikace ve Windows a stisknout **Načíst knihovnu (reload)**. Dřív psal jen „Dvojklik: přehrát.“ a nebylo poznat, proč playlist nejde rozkliknout.

Aplikace beze změny (0.9.17). Bez nového souboru v TOC: stačí `/reload`.

## Ověřeno

- Načtení skladeb playlistů z YouTube Music skriptem aplikace 0.9.17 na skutečném účtu: 10 playlistů za 3 s, se skladbami (100, 71, 100, 96, 41, 19, 13, 5; dva automatické playlisty YouTube 1 a 0).
- Lua testy hudby a rozložení oken prošly.
- Ve hře po obnovení knihovny zatím neověřeno.
