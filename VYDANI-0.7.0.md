# Evertally 0.7.0

11. listopadu 2026. Nové herní rozhraní, mapové vrstvy, živé spojení a opravy webové mapy. Tento dokument popisuje výslednou distribuci; testování na napodobeném herním API není potvrzením vzhledu ve WoW.

## Herní addon

- Měnitelná velikost okna, zapamatovaná poloha, stránka a měřítko; kompaktní nabídka při menší šířce.
- Přehled postavy se skutečnými statistikami, grafem aktivity a posledními událostmi. Deník s časovou osou a stavem questů. Žebříčky porovnávají lokální data a hráče, kteří něco sdíleli.
- Sjednocené vnitřní stránky Profesí, Míst, Atlasu, Komunity a Nastavení: metriky, filtry, hledání a rozložení podle dostupné šířky.
- Svět obsahuje Databázi, Cestu, Sbírání a Dungeony/Raidy. Hledání v QuestieDB používá volitelně nainstalovanou knihovnu.
- Sbírání: 70 typů surovin, 32 065 referenčních míst, čtyři skupiny a výběr konkrétní suroviny. Kreslí pouze právě zobrazenou mapu, nejvýše 500 sběrových pinů s počítadlem.
- Dungeony/Raidy: 45 instancí, 41 doložených vchodů. Vyhledání, zobrazení na mapě a navigace; chybějící vchody se nedoplňují odhadem.
- Herní knihovny mají zachované licence; mapový balíček nyní obsahuje úplný text GPLv3 a NOTICE.

## Most a web

- Windows aplikace zůstává mostem vedle hodin. Malé okno obsahuje pouze Web sync, párování a nastavení spojení.
- Živá poloha používá malou datovou značku v levém horním rohu okna hry (verze 4: nejvýš 128 × 6 px, čtyři odstíny mezi černou a 19 % šedi), vlastní oprávnění a spárované zařízení. Starší verze 2 (39 px) a 3 (44 px) se čtou dál. Okno hry musí mít viditelný nezakrytý levý horní roh; funguje i druhý monitor. Historie se dál čte po uložení hry.
- Herní přátelé a parta: addon v tomtéž pásku posílá otisk seznamu vlastních přátel a party/raidu (nejvýš 100 kontaktů, jen podle zapnutých voleb sdílení živé polohy s přáteli a s partou; bez GUID, BattleTagu a poznámek). Web podle toho ukáže hráče, kteří jsou spolu ve hře přátelé nebo ve stejné partě, a to jen když oba mají živou polohu, souhlas a spárované zařízení; ruční webové přátelství k tomu není potřeba. Změna party nebo přátel platí bez dalšího `/reload`. Migrace 0007 (`et_game_connections`) je na ostré databázi od 11. 11. 2026; záloha před ní je v `backups/20261111-release07/production-before-0007.sql`.
- Opraveno míchání postav různých producerů; nejednoznačný klíč se odmítá. Stav rozlišuje serverem přijatý a ignorovaný bod. Při více oknech WoW se zkoušejí další dostupné značky.
- Web má samostatné volby sdílení přátelům, přihlášeným návštěvníkům a veřejnosti. Výchozí stav je vypnuto; existující volby hráčů aktualizace nemění.
- Opraven skutečný reset posunutého panelu: zachycení myši původně přesměrovalo dvojklik mimo záhlaví. Sbalení, rozbalení, přesun, uložení a dvojklikový reset jsou ověřené v odděleném headless prohlížeči.
- Databáze obsahuje 22 881 předmětů, 22 779 má doloženou ikonu. Z klienta přibylo 12 464 dříve chybějících ikon; 102 záznamů zůstává bez ověřené grafiky.

## Co bylo ověřeno

- Skutečně spuštěný most a produkční D1: dne 11. 11. 2026 byl nejnovější bod starý 3 sekundy. Jde o reálný přenos, nikoli zkušební náhled.
- Lua: 180 testů (okno a stránky, mapové vrstvy, terén, herní vztahy, živá značka). Čísla vrstev (70 typů surovin, 32 065 míst, 45 instancí, 41 vchodů) jsem při finálním ověření znovu spočítal přímo z `LayerData.lua`.
- Rust synchronizace: 55 testů a Clippy bez varování; nativní aplikace: 5 testů a 2 testy watcheru, Clippy bez varování.
- Web: 186 testů, TypeScript a ESLint. HTTP test sdílení: 31 kontrol mezi třemi oddělenými zkušebními účty, včetně přátel, výchozích voleb, revokace a návštěvníka bez přihlášení.
- Ostrá databáze obsahuje tabulky z migrací 0005, 0006 a 0007; nová verze ji neinicializuje ani nemaže.

## Praktické ověření po aktualizaci

Kvůli novým Lua souborům je potřeba jednou úplně vypnout a znovu spustit WoW. Potom `/etally` otevře okno. Další pohyb na webu nevyžaduje opakované `/reload`.

Vzhled nových stránek v reálném klientu, skutečný běh dungeonem a úplná výměna mezi dvěma herními klienty se musí ověřit při hraní. Práva k cizím datovým zdrojům a nepřibaleným překladům WowfCZ nejsou tímto technickým vydáním nově vypořádána; jejich původ je popsaný v THIRD_PARTY.md.
