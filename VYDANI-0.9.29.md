# Evertally 0.9.29

Tři vlastní herní moduly: **Výbava a odpad**, **Co se naučit** a **Questový průvodce**. Windows Bridge se nemění.

## Kde je najít

V hlavním okně `/etally` jsou nové stránky v části Průvodce. Přímo je otevřeš příkazy:

- `/etally gear` — Výbava a odpad.
- `/etally train` — Co se naučit.
- `/etally guide` — Questový průvodce.

Nové funkce používají vlastní rozhraní Evertally a přibalené datové katalogy. Nevyžadují nainstalovaný Quest Guide, GearQuest ani What's Training. Povinné OpenMap a Windows Bridge a jejich ověření v prvním kroku instalace zůstávají zachované.

## Rozsah

Výbava se porovnává odhadem podle zvolené role a statistických vah. Výsledek není simulace ani procento skutečného DPS. Neúplná data se nesmějí vydávat za nulovou hodnotu předmětu. Prodej odpadu začíná náhledem, respektuje chráněné předměty a před každou operací znovu ověřuje slot tašky.

Trénink rozlišuje dostupné a budoucí schopnosti, známé ranky, podmínky, pet schopnosti a class questy. Základní ceny a skutečně pozorované ceny trenéra jsou odlišené. Neověřená znalost pet schopností není potvrzení, že se je hráč ještě nenaučil.

Questový průvodce počítá postup z dat pro Forever podle postavy, úrovně a předpokladů. Rozlišuje přijetí, splnění úkolů a odevzdání. Přeskočený krok není splněný předpoklad dalšího questu. Automaticky vypočtená trasa není ručně otestovaný speedrun 1–60.

## Načtení nové verze

Přibyly soubory v TOC, proto **WoW úplně ukonči a znovu spusť**. Samotný `/reload` nemusí nově přidané soubory načíst.

Automatické kontroly a modelované náhledy rozložení jsou oddělené od ověření ve skutečném klientu WoW.

## Kontroly této verze

- **608 Lua testů prošlo**; zahrnují přijetí/splnění/odevzdání questu, předpoklady a rasové masky Forever, výběr trenéra, ceny a ranky, porovnání výbavy i změnu slotu během prodeje.
- Všechny tři nové stránky mají modelované náhledy při 960 × 620 a 700 × 460 bez nalezených přesahů či překryvů.
- Katalog tréninku: 9 tříd, 1 471 schopností a grimoárů, 229 referenčních pozic trenérů a prodejců grimoárů.
- Katalog průvodce: 5 672 questů včetně 318 dungeonových questů; 44 questů s dynamickými podmínkami je označených a bez skutečného quest logu se jejich dostupnost neslibuje.
- Prodej odpadu se spouští výslovně tlačítkem po náhledu. Nenastává automaticky otevřením obchodníka.
- Skutečný prodej, dostupnost questů a chování klientských oken je nutné odlišit od kontrol s napodobeninou API; v této práci nebyly ověřeny hraním.
