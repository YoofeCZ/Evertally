# Evertally

Herní deník, navigace, atlas a komunitní statistiky pro **World of Warcraft Forever**. Projekt spojuje addon ve hře, Windows aplikaci na pozadí a web.

**Aktuální verze:** addon **0.9.29**, Windows Bridge **0.9.10**. Podrobnosti poslední změny: [VYDANI-0.9.29.md](VYDANI-0.9.29.md).

- [Web Evertally](https://evertally.afstudio.dev/)
- [Addon na CurseForge](https://www.curseforge.com/wow/addons/evertally)
- [Windows aplikace a propojení s webem](https://evertally.afstudio.dev/#sync)
- [OpenMap na CurseForge](https://www.curseforge.com/wow/addons/openmap)

## Instalace pro hráče

**OpenMap i aplikace Evertally pro Windows jsou povinné.** První krok nastavení ověří obě instalace; bez ověření se nedá pokračovat. Webový účet, párování počítače a sdílení vlastních dat na web zůstávají volitelné.

1. Nainstaluj a zapni OpenMap pro WoW Forever.
2. Nainstaluj Windows aplikaci Evertally a nastav v ní složku hry.
3. Nainstaluj addon Evertally a po přidání nových souborů úplně restartuj WoW.
4. Ve hře otevři `/etally`, ověř instalaci a projdi nastavením.

Podrobný návod, diagnostika a stav ověření jsou v [NAVOD.md](NAVOD.md).

## Co projekt nabízí

- **Deník a přehled:** questy, loot, úrovně, navštívená místa, nedávná aktivita a historie postavy.
- **Mapa a navigace:** vrstvy OpenMap, souvislá čára trasy, pěší a dopravní úseky, služby, instance a navigační nabídka po pravém kliknutí.
- **Dungeon Journal:** dungeony a raidy, bossové, loot, související questy, odměny a mapy.
- **Databáze a návody:** questy, NPC, předměty, objekty, recepty a postupy přímo ve hře.
- **Talenty:** plánování, ukládání, import a export profilů, doporučené buildy a zoom stromů. Plánovač sám neutratí skutečné talentové body.
- **Výbava a odpad:** porovnání podle třídy a role, vysvětlení skóre, upozornění na upgrade a náhled prodeje se seznamem chráněných předmětů.
- **Co se naučit:** dostupné a budoucí schopnosti, ranky, ceny, podmínky, schopnosti mazlíčka a navigace k trenérovi.
- **Questový průvodce:** vlastní vypočtený postup podle postavy a questových řetězců, stav kroků, přeskočení, pokračování a navigace.
- **Lidé a Armory:** pohled na výbavu, tašky, statistiky, talenty a profese se souhlasem druhého hráče; ve hře také questy a reputace. Každý hráč rozhoduje, co ukáže.
- **Komunita a žebříčky:** fórum, sdílené výsledky a dostupné filtry podle instance, postavy, třídy a rasy. DPS/HPS se zobrazují tam, kde existuje odpovídající záznam.
- **Jmenovky:** vlastní zobrazení spojenců, značky, logo, volitelné buffy, debuffy a lišty s nastavením a náhledem.
- **Windows Bridge:** běží v oznamovací oblasti; zajišťuje párování, Web sync, aktualizace a přenos povolených dat.

Jde o komunitní vzorek dat od uživatelů addonu, nikoli úplný přehled celého serveru. Záznam dungeonu, dokončení a úplné vyčištění nejsou totéž. Přesná živá poloha má vlastní oprávnění; historie a fórum používají odlišný způsob přenosu a mohou vyžadovat `/reload` nebo odhlášení.

Automatické testy a skutečné ověření ve WoW jsou vedené odděleně. Omezení konkrétní verze popisují její poznámky k vydání.

## Zdrojový kód

| Složka | Obsah |
| --- | --- |
| `addon/` | Lua addon, exportní modul a integrace mapy |
| `desktop/native/` | Aktuální Windows Bridge |
| `sync/` | Synchronizace, aktualizace, práce s herními exporty a přenosy |
| `platform/` | Webové rozhraní, API, schéma databáze a SQL migrace |
| `installer/` | Skript instalátoru Inno Setup |
| `tests/lua/` | Automatické testy Lua částí |
| `tools/` | Generátory dat, balení a ověřovací nástroje |

Repozitář obsahuje historii addonu i původně samostatného webového repozitáře. Jejich aktuální zdrojový kód je společně na větvi `main`; web je ve složce `platform/`.

### Web

Požaduje Node.js podle `platform/package.json`:

```powershell
cd platform
npm ci
npm test
npm run typecheck
npm run dev -- --port 5173
```

Další konfigurace a migrace: [platform/README.md](platform/README.md), [platform/deploy/README.md](platform/deploy/README.md). Vzory konfigurace mají prázdné přihlašovací údaje. Skutečné klíče patří do ignorovaných místních souborů nebo do úložiště secrets hostingu.

### Windows aplikace

Požadavky na Rust a build jsou v [desktop/native/README.md](desktop/native/README.md) a [sync/README.md](sync/README.md). Projektové skripty [Build-Release.ps1](Build-Release.ps1) a [Build-Installer.ps1](Build-Installer.ps1) připravují aplikaci a instalátor.

Generované herní assety, kopie zdrojových databází, místní databáze, přihlašovací údaje, zálohy a instalační binární soubory nejsou součástí tohoto Git repozitáře. Čistý checkout je automaticky nedoplní; pro některé generátory, mapy a distribuční buildy je nutné připravit příslušné podklady podle návodu a dokumentace nástrojů.

## Dokumentace a licence

- [Návod a ověření](NAVOD.md)
- [Produktové zadání](ZADANI.md)
- [Technický návrh](TECHNICKY_NAVRH.md)
- [Původ dat a licence jednotlivých částí](THIRD_PARTY.md)
- [Licence mapového modulu GPL-3.0](addon/Evertally_Map/LICENSE.txt)

Původní zadání a technický návrh obsahují také cílové funkce; nejsou samy o sobě seznamem dokončených funkcí. Převzaté knihovny a datové podklady si zachovávají vlastní podmínky. Licenci jedné části nelze vztahovat na všechen obsah projektu.

Evertally je fanouškovský projekt bez spojení s Blizzard Entertainment.
