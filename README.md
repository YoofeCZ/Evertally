# Evertally — herní atlas a statistiky pro WoW Forever

Implementace 0.8.1 a původní zadání • 12. listopadu 2026

Název: **Evertally**. Původní pracovní označení „Forever Atlas“ už používá jiný addon na CurseForge, proto bylo 2026-11-09 změněno; u názvu Evertally nenašlo vyhledávání na CurseForge, Wago, WoWInterface ani GitHubu žádný existující projekt (ochranná známka ověřená není).

**Samostatný addon sbírá herní pozorování, ukazuje vlastní historii a umožňuje porovnávání s dalšími uživateli addonu. Kdo se výslovně rozhodne přispívat na web, propojí své vlastní záznamy s komunitní databází a webovými žebříčky.**

Verze 0.8.0 spojuje nové herní okno, deník, přehled, žebříčky a sjednocené stránky profesí, míst, atlasu, komunity a nastavení. Do mapy OpenMap přidává místa sbírání s ikonami surovin, živé hráče, srazy, pingy a navigaci. Databáze a Dungeon Journal se načtou i bez OpenMap; stránka Mapa a cesty obsahuje plánování a mapové katalogy. Rozsáhlá webová databáze má 22 881 předmětů, z nichž 22 779 má doloženou ikonu. Windows Bridge běží vedle hodin a obsahuje pouze spojení, párování a Web sync. **Instalace a skutečný stav ověření jsou v [NAVOD.md](NAVOD.md)**; aktuální vydání shrnuje [VYDANI-0.8.1.md](VYDANI-0.8.1.md).

Web běží na **https://evertally.afstudio.dev**. Skutečný most dne 11. 11. 2026 odesílal živou polohu a produkční databáze přijala bod starý tři sekundy. To potvrzuje tento přenos; neprokazuje průchod dungeonem, správnost každé šipky ani vzhled nových stránek ve WoW. Ověření herního rozhraní a ověření automatickými testy jsou vedená odděleně.

Přesná živá poloha má samostatná oprávnění: vlastní účet, potvrzený cech/skupiny, přátelé, přihlášení návštěvníci a veřejnost podle voleb majitele. Veřejné sdílení je výchozí vypnuté. Komunitní aktivita oblastí je samostatná anonymní statistika se třemi přispívajícími účty za 24 hodin; nejde o počet online hráčů. Referenční NPC piny jsou oddělené od hráčských pozorování.

Níže uvedené dokumenty zachovávají původní produktové zadání. Popisují i cílové funkce, které ještě nejsou implementované; nejsou seznamem dokončených funkcí.

## Dokumenty

| Soubor | Obsah |
| --- | --- |
| [ZADANI.md](ZADANI.md) | Produkt, všechny herní oblasti, obrazovky, režimy použití a pravidla žebříčků |
| [TECHNICKY_NAVRH.md](TECHNICKY_NAVRH.md) | Architektura, sběr dat, datový model, ingame protokol, webová synchronizace a API |
| [PLAN_A_OVERENI.md](PLAN_A_OVERENI.md) | Etapy realizace, kritéria dokončení, herní ověření, výkonnostní cíle a rizika |
| [ZDROJE.md](ZDROJE.md) | Ověřené podklady, existující konkurence a hranice dosavadního ověření |

## Rozhodnutí, na kterých návrh stojí

1. Webový účet, prohlížeč ani aplikace nejsou podmínkou běžného používání addonu.
2. Výchozí nastavení neposílá vlastní data na web. Sdílení ve hře má vlastní přepínač a vysvětlení.
3. Sdílení s ostatními addony funguje přes povolené herní zprávy. Rozsah závisí na dostupných spoluhráčích, přátelích a guildě.
4. Přijatá ingame data se uchovávají odděleně od vlastních záznamů a automaticky se neodesílají na web.
5. Web ukazuje komunitní vzorek, jeho stáří a původ. Neoznačuje jej za úplná data celého serveru.
6. Web nabízí ruční import exportního souboru. Nativní aplikace navíc umí po spárování odesílat nové povolené záznamy; anonymní komunitní vzorek se do addonu načítá ručně přes JSON.
7. Rasy a classy jsou filtry profilů a účastí v bězích. Čas dungeonu patří skupině; není osobním měřením výkonu dané classy či rasy.
8. Záznam běhu, dokončení posledního bosse a úplné vyčištění mají odlišný význam a oddělené statistiky.
9. Každý údaj nese verzi hry, původ, dostupnost a míru doložení. Nedostupný údaj není nula.
10. Vývoj začíná ověřením API v konkrétním klientu. Zjištěná omezení nesmějí vést k obcházení chráněných dat.

## Jak to bude vypadat pro hráče

| Hráč | Co dostane |
| --- | --- |
| Používá jen addon | Vlastní historii, časovače, herní atlas a dostupná data od uživatelů addonu |
| Chce sdílet pouze ve hře | Totéž a porovnání povolených výsledků mezi online uživateli; jeho přijaté peer záznamy nejsou zdrojem webového exportu |
| Povolí webový přenos | Navíc webový přehled a příspěvek vlastních vybraných dat do společné databáze |
| Zveřejní profil postavy | Jeho schválené výsledky se objeví pod zvolenou postavou nebo přezdívkou v žebříčcích |
| Pouze navštíví web | Může prohlížet veřejná data bez udělení přístupu k herním souborům |

## První vydání — původní produktový cíl

První použitelné vydání má zahrnout addon, osobní historii dungeonů a raidových setkání, ingame sdílení, webový import, profily, základní žebříčky a první sběrače questů, NPC, lootu a profesí. Širší atlas, ekonomika a analýzy následují po ověření kvality dat.

Zadání zahrnuje celý cílový produkt. Rozdělení do etap určuje pořadí práce, nikoli vypuštění požadovaných oblastí.
