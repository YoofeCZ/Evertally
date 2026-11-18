# Evertally 0.11.2 (addon)

Aplikace zůstává **0.9.19**, nová není potřeba.

## Opravy

- **Chyba při načtení** `QuestTracker.lua:498: attempt to index local 'folded'`: tracker se mohl vykreslit dřív, než se načetla uložená nastavení.
- **Aplikaci stačí ověřit jednou.** Instalace si potvrzení aplikace pamatuje pro celý účet, takže po aktualizaci addonu nebo s vypnutou aplikací už znovu nechce, abys ji spustil.
- **Tmavá hlavní tlačítka** (třeba „Ping sem“, „Uložit build“) jsou zase barevná.
- Velká písmena v nadpisech s diakritikou („ULOŽENÉ“, ne „ULOžENé“).

## Stránky Evertally ve stylu menu průvodce

Stránky v menu vypadají jako zbytek okna: záložky nahoře v liště, vlevo seznam, vpravo detail s obrázkem oblasti, žádné krabice.

- **Deník, Přehled** (Aktivita / Oblasti / Loot, pruh čísel, postava a graf), **Co se naučit**, **Běhy, Profese, Fakta z webu**.
- **Dungeon Journal**: karty po jedné na řádek s obrázkem dungeonu.
- **Žebříček, Recepty, Komunita** (vlákna vlevo, vlákno vpravo).
- **Lidé**: režimy jako záložky, filtry na jednom řádku.
- **Talenty**: záložky **Plánovač** a **Buildy**. V Buildech jsou uložené a doporučené buildy, u každého body po stromech a tlačítko, které ho otevře v Plánovači.
