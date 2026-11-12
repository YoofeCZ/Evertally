# Evertally 0.8.0 — questové stránky, místní knihovna a talentový plánovač

12. listopadu 2026. Toto vydání přestavuje obsah stránek, nejen jejich barevnou paletu.

- **Questy** mají společnou pergamenovou kartu v Databázi, Deníku a Dungeon Journalu: jméno, požadovaný level, frakce, cíl, zadání a odevzdání, odměny s ikonami a kvalitativní barvou, XP. Výběrové a pevné odměny jsou oddělené tam, kde to zdroj dokládá. XP z klienta má přednost; základní referenční XP je označené hvězdičkou. Metadata obsahují 5 261 questů a 22 885 položek pro názvy a ikony bez zahřáté herní cache.
- **Dungeon Journal** má čtecí stránku bosse a lootu, questové karty a samostatnou mapu. Překreslení nevrací zvolenou záložku na Bossové a mapa zůstává nad dolními tlačítky. Rozšířené údaje a mapy pater se čtou z nainstalovaného ForeverDungeonJournal.
- **Návody** jsou místní knihovna 26 kapitol v češtině i angličtině: postup při levelování, dungeon a role, devět tříd a dvanáct profesí. Obsah se čte přímo v addonu, má kategorie, hledání, označení přečtených kapitol a interní odkazy na recepty, materiály, mapu a talenty. Nejde o adresář cizích webů.
- **Výrobní profese** používají 2 339 přibalených receptů pro postup 1–300, série výrob a součty přímých surovin. Náhodné zisky dovednosti jsou označené. Jde o postup podle dovednosti, ne o záruku nejnižší ceny; před výrobou je potřeba recept znát. Mezivýrobky se v součtech nerozkládají na základní materiály.
- **Talenty** jsou interaktivní plánovač aktuální třídy podle skutečných stromů klienta. Levý klik přidává a pravý odebírá bod. Hlídá level, počet bodů, řady i závislosti, umí načíst současné rozdělení a uložit až osm pojmenovaných buildů na třídu. Nemění skutečné talenty postavy. Stromy ostatních tříd nejsou přibalené.
- **Ostatní stránky** mají nové rozložení: Přehled jako knihu postavy a deník aktivity; Deník se seznamem a čtecí stránkou; Běhy s protokolem a časy bossů; Místa s návštěvami; Atlas a Komunita s detailem vybraného záznamu; Profese s recepty a cooldowny; Lidé s kontakty a samostatnou žádostí; Žebříček jako listinu s výběrem dungeonu. Nastavení je rozdělené do šesti přístupných kategorií. Cesta má čitelný itinerář, Recepty nabídku profesí a pergamenový detail.

## Ověření

307 Lua testů prošlo nad napodobeninou herního API. Pokrývají i skutečné přidávání a odebírání talentových bodů v plánu, závislosti, lokální kapitoly, výpočet materiálů, odkazy quest → NPC, rozlišení odměn a zachování stavu Dungeon Journalu. Všech 16 stránek a jejich režimy jsou zkontrolované modelem kotvení při 960 × 620 a 700 × 460. Oddělený prohlížeč vykreslil české náhledy při 1 100 × 720 a 700 × 460. Náhled referenčního questu An Ancient Grudge používá skutečná přibalená data a místní ikony; talentové náhledy mají výslovně testovací data.

Náhled používá model herních rámů, fontů a pozadí. Nejde o snímek běžícího WoW a nepotvrzuje skutečné herní tooltipy ani výkon v klientu. Finální vzhled v klientu je potřeba porovnat po načtení nové verze. Windows most zůstává mostem pro Web sync a párování; jeho chování se tímto redesignem nemění.

## Po instalaci

Zadej `/reload` a otevři `/etally`. Tato verze nepřidává soubory do TOC oproti 0.7.1. Pokud přecházíš ze starší verze, WoW jednou úplně vypni a znovu spusť. Dosavadní historie, souhlasy a párování zůstávají uložené.
