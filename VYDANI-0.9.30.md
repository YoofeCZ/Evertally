# Evertally 0.9.30

Jednotný vzhled oken. Funkce 0.9.29 (Výbava a odpad, Co se naučit, Questový průvodce) zůstávají.

## Co se mění

- **Společné téma oken** (`Theme.lua`, námořnická modř se zlatem): barvy, písma a rozměry má jedno místo a okna z něj čerpají, takže nezávisí na vzhledu jiného addonu.
- **Přepracované vzhledem**: hlavní okno, Přehled, Deník, Žebříček, Fórum, Lidé, jmenovky, průvodce prvním spuštěním, Výbava, Trénink, Questový průvodce, Talenty, mapa a nabídka šipky, Dungeon Journal, Recepty a databáze světa.
- **Dungeon Journal**: větší nadpis dungeonu už se nepřekrývá s řádkem „Level … · lokace“, vyhledávací pole a karty mají sjednocený vzhled.

## Načtení nové verze

Přibyl soubor `Theme.lua` v TOC, proto **WoW úplně ukonči a znovu spusť**. Samotný `/reload` nově přidaný soubor nemusí načíst.

Windows Bridge 0.9.11 addon aktualizuje sám (stačí restart hry).

## Kontroly této verze

- **609 Lua testů prošlo**, včetně testů rozložení všech stránek při výchozí, nejmenší i dříve uložené velikosti okna.
- Rozložení je ověřené **modelem rozvržení**, ne ve hře. Skutečný vzhled a chování oken v klientovi WoW **nebyly ověřeny hraním**.
- Změny jsou převážně vzhledové; funkce se v tomto vydání nepřidávají.
