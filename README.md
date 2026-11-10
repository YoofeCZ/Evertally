# Evertally — herní atlas a statistiky pro WoW Forever

Implementace 0.4.0 a původní zadání • 9. listopadu 2026

Název: **Evertally**. Původní pracovní označení „Forever Atlas“ už používá jiný addon na CurseForge, proto bylo 2026-11-09 změněno; u názvu Evertally nenašlo vyhledávání na CurseForge, Wago, WoWInterface ani GitHubu žádný existující projekt (ochranná známka ověřená není).

**Samostatný addon sbírá herní pozorování, ukazuje vlastní historii a umožňuje porovnávání s dalšími uživateli addonu. Kdo se výslovně rozhodne přispívat na web, propojí své vlastní záznamy s komunitní databází a webovými žebříčky.**

Aktuální zdroje obsahují addon 0.4.0, web/API a nativní aplikaci s Windows instalátorem. Web i desktop mají 60 skutečných mapových podkladů, herní ikony class/ras/itemů a referenční katalogy itemů, questů, NPC a dungeonového/raidového lootu. **Instalace a skutečný stav ověření jsou v [NAVOD.md](NAVOD.md)**; změny shrnuje [VYDANI-0.4.0.md](VYDANI-0.4.0.md).

Web 0.4.0 běží na **https://evertally.afstudio.dev**; živá HTTPS kontrola ověřila API, katalogy a hashe staženého addonu, aplikace i instalátoru. Instalace v `%LOCALAPPDATA%\Programs\Evertally` a registrace background watcheru jsou ověřené; watcher běží bez viditelného okna. Skutečný automatický start s WoW zatím nebyl ověřený. Addon 0.4.0 je souborově nainstalovaný s kontrolou hashů, nové UI však není vizuálně ověřené ve hře. Discord metadata, ikona a serverové klíče jsou nastavené; celý login zůstává neověřený kvůli hCaptcha. Důkazy a hashe jsou v release reportech.

Veřejný profil ani komunitní vrstvy nikdy neukazují přesné pozice hráčů; profil ukazuje pouze navštívené oblasti. Jedinou výjimkou je dobrovolná, ve výchozím stavu vypnutá **Moje trasa** a **Můj cech** (soukromá trasa tvého účtu, cech jen po potvrzení; viz `NAVOD.md`). Komunitní aktivita počítá přispívající účty za 24 hodin a zveřejňuje až oblasti se třemi účty; nejde o počet online hráčů. Referenční NPC piny jsou oddělené od hráčských pozorování.

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
