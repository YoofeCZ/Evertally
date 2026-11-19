# Evertally 0.11.8 (addon)

Aplikace zůstává **0.9.19**, nová není potřeba.

## Instalace a okna průvodce

- **Opravené prázdné texty** v instalaci (chyběl nadpis a popisky voleb, vidět byly jen přepínače). Příčina: když v okně průvodce spadla jedna animace, zamrzly všechny a stránka zůstala průhledná. Teď se vadná animace přeskočí a ostatní doběhnou.

## Jazyk

- **Změna jazyka hned načte rozhraní znovu** (v nastavení i v instalaci). Dřív se čeština v průvodci ukázala až po ručním /reload.

## Nastavení

- **Méně stránek, žádné duplicity:** Sdílení, Živě a Web jsou jedna stránka se třemi záložkami, Rozhraní jedna stránka se třemi sekcemi. V průvodci jsou sloučené Špendlíky a trasy a Upozornění a trackery; každá volba je jen na jednom místě (v angličtině i češtině).

## Ověření

- Lua testy 857 OK. **Ve hře neověřeno** (Evertally Sync přepisovala lokální kopii vydanou verzí).
