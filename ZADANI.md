# Zadání produktu: herní atlas a statistiky pro WoW Forever

Verze 1.0 • 9. listopadu 2026 • název Evertally (původně pracovní označení Forever Atlas)

## 1. Účel

Vytvořit addon a propojený web, které z běžného hraní získávají herní pozorování a převádějí je na užitečnou databázi, osobní historii, časovače, mapové přehledy a srovnatelné výsledky.

Hráč má například zjistit:

- Kolikrát dokončil konkrétní dungeon a které běhy addon skutečně zaznamenal.
- Jaký měl nejlepší a obvyklý čas, s jakou skupinou a na jakém levelu.
- Jak si stojí proti dostupným výsledkům ostatních hráčů, přátel nebo guildy.
- Kdo zaznamenal nejvíce dokončení, nejrychlejší běh nebo největší šíři dokončeného obsahu.
- Kde byl pozorován NPC, obchodník, recept nebo zdroj surovin a jak staré je pozorování.
- Jaké questy dokončil, jaké odměny získal a které návaznosti jsou potvrzené.
- Který předmět byl skutečně pozorován v lootu konkrétního zdroje a na kolika úplných pozorováních stojí odhad jeho výskytu.
- Jaké recepty zná, jaké cooldowny mu běží a co lze doložit z jeho výroby.

Samotné sbírání nemá vyžadovat vyplňování formulářů po každém běhu. Ruční doplnění je možné, ale zůstane viditelně označené a nepatří do automaticky měřených rekordů.

## 2. Závazné režimy použití

### 2.1 Samostatně ve hře

- Instalace jednoho addonu; účet na webu není potřeba.
- Sběr podporovaných vlastních pozorování a lokální historie.
- Vlastní přehledy, časovače, rekordy a databáze získaných herních faktů.
- Volitelné ingame sdílení přes povolené addonové zprávy.
- Základní distribuovaná databáze může být součástí vydání addonu. Funguje i při nedostupném webu.
- Nedostupnost webu nesmí zabránit startu addonu, ukončení běhu ani uložení výsledků.

### 2.2 Sdílení mezi uživateli addonu

- Hráč si vybere příjemce: aktuální skupina/raid, guilda a přímí přátelé podle podpory klienta.
- Při prvním nastavení je ingame sdílení zřetelně vysvětlené. Hráč může zvolit pouze vlastní historii.
- Sdílejí se zvolené souhrny výsledků a herní fakta. Soukromé poznámky, chat ani průběžná cesta postavy se neposílají.
- Addon ukazuje výsledky přijaté v minulosti s časem poslední aktualizace.
- Zobrazení uložených výsledků nevyžaduje, aby byl jejich autor právě online. Pro získání nových dat musí proběhnout další povolená výměna.
- Žádné rozesílání dotazů náhodným hráčům na serveru ani zaplavování veřejného chatu.
- V první verzi se cizí osobní výsledky nepřeposílají dalším hráčům. Aktualizaci poskytuje jejich původce.
- Žebříček nese označení „dostupní uživatelé addonu“ a počty zahrnutých hráčů/běhů.

### 2.3 Dobrovolné propojení s webem

- Hráč se na webu přihlásí a povolí konkrétní datové oblasti a postavy.
- Přístup prohlížeče k souboru je technické oprávnění. Odesílání dat a veřejný profil mají samostatné volby.
- Na web lze poslat pouze vlastní vybraná pozorování. Ingame peer cache se z uploadu vždy vyloučí.
- Ve výchozím stavu se zahrnou až data od zapnutí propojení. Starší historie vyžaduje samostatný náhled a volbu období.
- Hráč může povolit komunitní herní fakta a ponechat profil soukromý.
- Veřejný jmenný žebříček vyžaduje další výslovné zveřejnění příslušné postavy.
- Odmítnutí propojení nesmí omezit lokální sběr, vlastní přehledy ani povolenou ingame výměnu.

### 2.4 Důležitá hranice souhlasu

Systém nebude automaticky přenášet cizí soukromé výsledky získané od jiného addonu. Nelze však zaručit, že jiný hráč nikdy ručně nezveřejní screenshot nebo sám nezaznamená stejný společný běh.

Herní fakt jako „NPC byl pozorován v této zóně“ může nezávisle pozorovat více lidí. Vypnutí webu u jednoho hráče neznamená zákaz publikace stejného herního faktu od jiného přispěvatele.

## 3. Matice přístupu

| Funkce | Jen vlastní addon | Ingame sdílení | Webové propojení |
| --- | --- | --- | --- |
| Vlastní běhy a časovač | Ano | Ano | Ano |
| Vlastní atlas a historie | Ano | Ano | Ano |
| Výsledky online spoluhráčů s addonem | Ne | Podle povolených příjemců | Stejně jako ingame režim |
| Veřejný webový žebříček | Lze otevřít v prohlížeči | Lze otevřít v prohlížeči | Vlastní schválené výsledky do něj přispívají |
| Webové údaje uvnitř hry | Poslední distribuovaný/importovaný datový balíček | Totéž a dostupné peer údaje | Totéž; automatická HTTP komunikace addonu se nezavádí |
| Odeslání vlastních dat | Ne | Ne | Podle souhlasu |
| Odeslání přijatých osobních peer dat | Ne | Ne | Ne |
| Povinný program na pozadí | Ne | Ne | Ne; uploader je pozdější volitelná cesta |

## 4. Rozsah herních dat

„Sbírat všechno“ znamená pokrýt následující oblasti pomocí podporovaných rozhraní a jednoznačně ukazovat chybějící pokrytí. Neznamená to získat neveřejný stav serveru nebo bez souhlasu vytvořit databázi všech hráčů.

### 4.1 Postavy a jejich postup

- Identita postavy ve vlastním úložišti: herní identifikátor, jméno, realm, region, frakce.
- Rasa a classa podle stabilních herních ID; názvy jsou lokalizované popisky.
- Level, získané levely, čas pozorování a pokrytí historie.
- Specializace, talenty, výbava, reputace a další postup pouze v rozsahu dostupném příslušnému klientu.
- Snapshot při vstupu a dokončení běhu. Pozdější převlečení nebo přetalentování nesmí přepsat historii běhu.
- Více postav jednoho hráče může být propojeno soukromě. Veřejné propojení altů je volitelné.
- Změna jména/realmu má historii; slučování postav podle samotného jména je zakázané.
- Webová identita uživatele a vlastnictví herní postavy jsou odlišná tvrzení. Import souboru sám o sobě vlastnictví nedokazuje.

### 4.2 Questy

- Přijetí, změna cíle, dosažení stavu k odevzdání, skutečné odevzdání a opuštění.
- Zadavatel a příjemce, pokud je addon mohl identifikovat při interakci.
- Pozorované odměny, zvolená odměna, XP a peníze odděleně od databázového seznamu možností.
- Návaznosti se označují jako známé z dat, pozorované nebo pouze předpokládané.
- Level, classa, rasa a další podmínky se nepovažují za univerzální jen proto, že quest získal jeden hráč.
- Opakovatelné questy mají samostatné výskyty; historie není jen množina dokončených ID.
- Doba od přijetí po odevzdání je uplynulá doba. Aktivní čas strávený řešením se z ní bez dalšího nedovozuje.
- Sběr funguje vedle QuestMasteru/Questie; vlastní quest tracker není součástí prvního vydání.

### 4.3 Polohy, NPC a objekty

- Pozorované NPC ID, název, typ interakce, zóna/mapa/patro a čas.
- Obchodníci, trenéři, questové postavy, pojmenovaní nepřátelé, vzácné výskyty a objekty.
- Surovinové uzly a místa získání suroviny, pokud je zdroj jednoznačný.
- Souřadnice zahrnují souřadnicový systém a metodu získání.
- Poloha hráče při interakci se označuje jako přibližná poloha interakce. Není přesnou polohou NPC.
- Pohyblivý NPC může mít více bodů nebo oblast výskytu. Databáze nesmí nutit všechny záznamy do jednoho bodu.
- Nula nebo chybějící souřadnice znamená neznámou polohu. Zakázané je vykreslit ji jako platný bod v rohu mapy.
- Veřejné mapy ukazují agregované herní lokace. Živá poloha konkrétního hráče a jeho úplná trasa nejsou výchozím veřejným údajem.
- Odhad respawnu lze přidat jen z dostatečně doložených opakovaných pozorování. Zmizení z dohledu není důkaz zabití.

### 4.4 Itemy a loot

- Item ID, varianta/bonusy, počet kusů a dostupný snapshot vlastností.
- Zdroj se rozlišuje: mrtvola, objekt, gathering, výroba, quest, obchodník, pošta, obchod nebo neznámý.
- Viděný obsah loot okna, skutečně sebraný předmět a přidělená odměna jsou různé události.
- U area lootu se uchovává vztah ke zdrojům a jeho jednoznačnost. Nejasný loot se nepřipíše náhodnému NPC.
- Pošta ani obchod se neoznačí jako původní drop; neznámá předchozí cesta předmětu zůstane neznámá.
- Četnosti vycházejí z úplných sledovaných příležitostí daného zdroje. Není-li znám jmenovatel, ukáže se počet nálezů bez procent.
- Odhad „objevil se na 8 ze 120 úplně sledovaných lootů“ musí definovat osobní/skupinový loot a podmínky získání.
- Duplicitní pohled pěti členů skupiny na jednu mrtvolu nesmí vytvořit pět nezávislých vzorků.
- Výsledky jsou rozdělené podle verze hry, režimu, zdroje a případných podmínek lootu.
- Katalog může zobrazovat nalezený item okamžitě. Statistická procenta mají vyšší požadavky na úplnost a deduplikaci.

### 4.5 Dungeony

- Identita instance, dungeon, křídlo, obtížnost a verze pravidel měření.
- Vstup, začátek pokusu, jednotliví bossové, dokončení, opuštění, reset a přerušení měření.
- Celkový čas, mezičasy k bossům, délka doložených boss fightů a nejlepší srovnatelné časy.
- Počet zahájených pokusů, dokončení posledního bosse a úplných vyčištění odděleně.
- Vlastní úmrtí; skupinové deaths/wipes pouze pokud existuje dostatečné pokrytí a jasná definice.
- Levelové rozmezí celé skupiny, velikost skupiny a změny sestavy v průběhu.
- Účast vlastní postavy s rasou, classou a dostupnou rolí/specem. Neznámá role se nedoplňuje odhadem.
- Vlastní XP, peníze a získaný loot; aukční hodnota lootu je oddělený odhad se zdrojem ceny.
- Ručně spuštěné nebo ukončené časování je užitečné pro osobní deník, ale má vlastní kategorii.

### 4.6 Raidy

- Samostatný raidový večer/session a jednotlivé pokusy na bossech.
- Začátek/konec setkání, úspěch, délka pokusu, dostupná sestava a zaznamenaný loot.
- Lockout/reset, pokud je dostupný; jinak výslovně neznámý.
- Postup guildy či skupiny pouze z relevantních doložených účastí. Členství v guildě se neodvozuje jen od jednoho hráče.
- Raid trvající více večerů má návaznost session; osobní „čas strávený uvnitř“ se nevydává za oficiální čas full clearu.
- Bossové a jejich pokusy jsou první raidovou částí produktu. Full-clear žebříček raidu vyžaduje vlastní ověřený ruleset.

### 4.7 Profese a tradeskilly

- Profese vlastní postavy, skill, specializace a skutečně načtené naučené recepty.
- Recept ID, výstup, počty, materiály, požadavky a dostupné varianty receptu.
- Výroba: zahájení, potvrzený výsledek, skutečné spotřeby/výstupy a změna skillu v rozsahu dostupných dat.
- Cooldowny z aktuálního čitelného API, včetně času snapshotu. Po odhlášení jde o odpočet z posledního známého stavu.
- Zdroj receptu: pozorované učení u trenéra, koupený recept nebo jiný doložený zdroj.
- Datum získání receptu se nevyrobí ze dne prvního importu existující knihy receptů.
- Statistiky výroby od začátku sledování; starší nepozorovaná výroba se nedopočítává.
- Známé recepty ostatních hráčů se sdílejí jen podle jejich nastavení. Soukromé bankovní zásoby nejsou součástí veřejného profilu.
- Náklady a výnosy rozlišují cenu nabídky, vlastní nákup, skutečný prodej a odhad. Zisk nelze garantovat z pouhé aukční nabídky.

### 4.8 Ekonomika

- Pozdější modul: vlastní příjmy/výdaje, skutečné nákupy/prodeje a aukční snapshoty podle dostupnosti API.
- Realm, region, frakční trh, pokud je relevantní, čas a měna.
- U aukcí cena za kus, počet, varianta předmětu a stáří dat.
- Ceny obchodníka včetně dalších měn a omezené zásoby jako stav v okamžiku návštěvy.
- Zmizelá aukce není automaticky prodaná aukce.
- Počáteční integrace může číst podporované cenové zdroje existujících addonů. Každý má uvedený původ a čas.

### 4.9 Další rozšiřující oblasti

Battleground výsledky, honor/ranky, reputace, fishing, doby letů a další cestování, world eventy a úspěchy lze přidávat jako oddělené sběrače. Zařadí se až po ověření konkrétních událostí a skutečného přínosu.

Produkt nemá při startu sbírat soukromé chaty, přístupové údaje, BattleTagy jiných lidí ani obsah nesouvisejících addonových souborů.

## 5. Obrazovky addonu

### Přehled

Vlastní postava, poslední běhy, dosažené rekordy, běžící časovače, počet nových pozorování a stav sdílení. Web je prezentovaný jako volba. Žádné opakované vyskakovací pobídky k registraci.

### Dungeony a raidy

Seznam instancí, počet doložených dokončení, nejlepší a typický čas, historie a detail běhu. Detail vysvětluje začátek/konec měření, bossy, přerušení a způsobilost pro žebříček.

Kompaktní časovač má celkový čas a nejbližší známý mezičas. Při chybějícím podkladu nezobrazuje smyšlený „rekord serveru“.

### Žebříčky

Přepínač „vlastní / přijaté ingame / importovaný webový přehled“. Filtry dungeon, křídlo, pravidla, období, levelová kategorie, classa, rasa a realm. Vždy je vidět původ a stáří.

### Atlas

Vyhledávání questů, NPC, objektů, předmětů a receptů. Detail propojuje vztahy: NPC → prodej → recept → materiály → zdroje. Mapové body mají popisek míry přesnosti a počtu nezávislých pozorování.

### Profese

Vlastní známé recepty, zaznamenaná výroba, cooldowny a dostupní sdílející řemeslníci. Hlavní přehledy mohou být doplněné tooltippy; addon nesmí vyžadovat náhradu Blizzardova profesního okna.

### Data a sdílení

Oddělené volby sběru modulů, ingame příjemců, připravovaných webových dat a historie. Náhled vlastních exportovaných dat, velikost úložiště, vymazání peer cache a export zálohy. Stav „web vypnut“ musí být jednoznačný.

### Diagnostika

Verze addonu/klienta, podporované sběrače, naposledy úspěšně načtená data a poslední chyby bez obsahu soukromých událostí. Možnost zkopírovat bezpečný diagnostický souhrn.

## 6. Obrazovky webu

| Stránka | Základní obsah |
| --- | --- |
| Úvod a vyhledávání | Hledání entity, hráče a instance; přehled pokrytí dat |
| Dungeony/raidy | Bossové, vstup, lootové vztahy, časy a zaznamenané běhy |
| Žebříčky | Nejrychlejší platné běhy, počty dokončení, sezóny a filtry |
| Profil postavy | Zveřejněná historie, rekordy, level/rasa/classa a povolené profesní informace |
| Detail běhu | Pravidla, mezičasy, dostupnost důkazů, účasti a případné výhrady |
| Mapa | Herní lokace s vrstvami, časem a přesností pozorování |
| Katalog | Questy, NPC, předměty, recepty, obchodníci a vzájemné odkazy |
| Moje data | Soukromé importy, výběr postav, náhled publikace a mazání |
| Synchronizace | Vybraný soubor/složka, povolené kategorie, poslední přenos, čekající data a stop |
| Metodika | Jak se počítají časy, dropy, počty a spolehlivost |
| Správa dat | Fronta konfliktů, duplicit a podezřelých výsledků pro správce |

Veřejné stránky jsou přístupné bez povolení složky. Web funguje na mobilu pro prohlížení; propojení místních souborů se očekává na počítači s hrou.

## 7. Pravidla časování a dokončení

### 7.1 Osobní návštěva

Začíná pozorovaným vstupem do instance. Slouží jako deník a zahrnuje čekání či pobyt uvnitř. Samotný vstup nevytváří platný soutěžní pokus.

### 7.2 Soutěžní pokus

- Musí odpovídat verzovanému rulesetu daného dungeonu a křídla.
- Preferovaný začátek: první doložené zahájení nepřátelského boje v čerstvé instanci. Použitelnost tohoto signálu je vstupní technická podmínka.
- Pokud čerstvost instance nebo začátek nelze doložit, výsledek zůstane v osobní historii jako nesrovnatelný. Nevydává se za ověřený rekord.
- Čas běží bez pauzy až do úspěšné události požadovaného posledního bosse. Smrt, čekání ani cesta ven ho nezastaví.
- Na rankovaný full clear musí být doloženi všichni povinní bossové. Volitelní bossové a alternativní cesty jsou popsáni rulesetem.
- Samostatná kategorie „poslední boss dokončen“ může přijmout běh bez všech povinných bossů. Nesmí se smíchat s full clearem.
- Ruční start/stop, chybějící začátek, neznámý reset, pozdní příchod, výpadek měření nebo změna obtížnosti zamezí zařazení do hlavního žebříčku.
- Reload může navázat na uložený pokus. Kontinuita a změna časové základny se musí doložit; při nejistotě je běh přerušený.
- Změna sestavy se zaznamená. Hlavní rekordní kategorie vyžaduje stálou sestavu; ostatní výsledky mají vlastní filtr.

Konkrétní boss ID a události se doplní z ověření každého rulesetu. Žádný dungeon se nepovolí pro soutěžní režim jen podle podobnosti názvu s Classicem.

### 7.3 Počet dokončení

- Jedno dokončení jedné konkrétní instance je jeden běh, i když jej pošle více členů skupiny.
- Opakované zabití stejného bosse bez doloženého nového pokusu/resetu nevytváří další clear.
- Účast postavy a existence skupinového běhu jsou oddělené. Výpadek jednoho záznamníku automaticky nevytváří další běh.
- Web i addon ukazují „zaznamenaná dokončení od …“, protože starší historii nelze zpětně znát.

## 8. Žebříčky a statistiky

### 8.1 Povinné žebříčky

1. Nejrychlejší srovnatelný full clear konkrétního dungeonu/křídla.
2. Nejvíce doložených dokončení na postavu v daném období.
3. Nejvíce různých dokončených dungeonů/bossů.
4. Osobní rekordy a zlepšení proti vlastnímu srovnatelnému rekordu.
5. Guildovní/přátelské přehledy, pokud jsou účasti a sdílení doložené.

### 8.2 Povinné filtry

- Hra, patch/content epoch a verze pravidel.
- Region, realm a období: týden, měsíc, sezóna, celá zaznamenaná historie.
- Instance, křídlo, obtížnost a velikost skupiny.
- Levelová kategorie celé skupiny a označení overlevel/boosted/unknown.
- Classa a rasa účastníka; případně role/spec, pokud jsou doložené.
- Původ výsledku a úroveň doložení; oficiálně automaticky měřené a ruční výsledky odděleně.

Filtr „Shaman, Tauren“ znamená běhy s účastí takové postavy. Neříká, že daná rasa nebo classa způsobila dosažený čas. Počet nálezů i vzorek jsou vždy viditelné.

### 8.3 Srovnatelnost

- Hlavní levelový žebříček vylučuje běhy se členem nad určeným maximem dungeonu. Posuzuje se maximum celé sestavy v průběhu, ne pouze level přispěvatele.
- Pokud některého člena nelze vyhodnotit, kategorie je „neúplná sestava“, ne automaticky „bez boostu“.
- Běhy s vyšším levelem mají samostatnou otevřenou kategorii, takže se jejich data neztratí.
- Časy skupin s různou velikostí a odlišnými pravidly se neslévají.
- Medián a percentily se vypočítají jen pro jasně definovaný vzorek. Při malém vzorku se ukáže počet výsledků místo autoritativního percentile ranku.
- Počet nahrávek neznamená počet nezávislých potvrzení.
- Zpráva od dvou addonů není nezfalšovatelný důkaz. Žebříčky jsou komunitní a mají námitkový/moderační proces.
- Jedno univerzální skóre kvality hráče se v první verzi nezavádí.

## 9. Herní časovače

| Časovač | Zdroj a chování |
| --- | --- |
| Aktuální běh | Průběžné vlastní měření, jasně uvedený typ pokusu |
| Boss/mezičas | Konkrétní události a ruleset; dostupné po ověření |
| Profesní cooldown | Snapshot čitelného API a lokální odpočet s uvedením stáří |
| Reset/lockout | Oficiální dostupná hodnota; bez ní „neznámé“ |
| Respawn světa | Pozdější odhad s intervalem nejistoty, nikoli jistý countdown |

Oznámení jsou volitelná a střídmá. Addon nespouští chráněné herní akce na základě timeru.

## 10. Soukromí a publikace

Rozlišují se tři oblasti: komunitní herní fakta, osobní historie a veřejný profil.

- Vlastní výsledky lze uchovávat pouze v addonu nebo soukromě na webu.
- Veřejně pojmenovaný profil vyžaduje výslovnou volbu konkrétní postavy.
- Bez souhlasu dalších účastníků webová projekce běhu neobsahuje jejich jména, GUID, BattleTagy ani odkazy na profily.
- Není povoleno vzít raw combat log se jmény ostatních a běžně jej odeslat v režimu anonymních herních faktů. Sanitizace proběhne před uploadem.
- Třídy a rasy skupiny lze agregovat bez jmen, ale přesné časové údaje mohou stále umožnit rozpoznání konkrétního běhu. Produkt neslibuje absolutní anonymitu.
- Vypnutí budoucího odesílání, skrytí veřejného profilu a smazání již odeslaných dat jsou tři odlišné akce.
- Historická data se po pouhém znovuzapnutí neposílají automaticky.
- Kompletní WTF složka, cizí addonové databáze a soukromé poznámky se nenahrávají.

Přesná pravidla oprávnění, odvolání a retence jsou v technickém návrhu. Právní dokumenty pro veřejný provoz se připraví podle skutečně zvoleného provozovatele, zemí a hostingu; toto zadání není hotovou právní dokumentací.

## 11. Integrace a soužití s dalšími addony

- Nezávislost na QuestMasteru, Questie, SkillUp Forever, Dungeon Ledgeru a damage metrech třetích stran.
- Podporované integrační adaptéry mohou číst veřejná API existujících addonů; jejich odstranění nesmí shodit vlastní addon.
- Žádné přepisování cizích addonových souborů nebo SavedVariables.
- Vlastní fonty musí podporovat češtinu a další cílové jazyky; ověření zahrnuje tooltipy a nadpisy.
- Herní identifikátory a protokol jsou jazykově nezávislé; UI a názvy mají samostatnou lokalizační vrstvu.
- Upozornění na aktualizaci vychází z dostupné verze balíčku či legitimní ingame výměny, nikoli z domnělého HTTP volání addonu.

## 12. Rozsah prvního vydání a dalšího rozvoje

První vydání propojí osobní dungeonovou historii, doložené bossové setkání, ingame sdílení a webový přenos. Současně zavede první sběrače questů, lootů, NPC a profesních snapshotů tak, aby se při běžném hraní začal plnit atlas.

Rozšiřování bude po modulech: další rulesety dungeonů, raidové statistiky, mapové agregace, úplnější questové vztahy, řemeslné přehledy a ekonomika. Každý modul má vlastní indikátor pokrytí a může být vypnut bez ztráty ostatních funkcí.

Úspěchem je využitelná vlastní historie i pro prvního uživatele a kvalitnější společná data s každým dobrovolným přispěvatelem. Počet instalací sám o sobě tento výsledek nedokazuje.
