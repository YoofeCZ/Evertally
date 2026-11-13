# Evertally — addon 0.8.2, web a Windows Bridge 0.8.1

Addon 0.8.2, web a Windows most 0.8.1, 13. 11. 2026. Addon sbírá vlastní herní události, nainstalovaný Windows most je čte a volitelně synchronizuje; web zobrazuje povolené záznamy a referenční databázi. Jazyk EN/CS se vybírá samostatně v každé části. Změny addonu a ověření shrnuje VYDANI-0.8.2.md; předchozí opravy VYDANI-0.8.1.md.

Windows Bridge běží vedle hodin. Z ikony otevřeš malé okno s kartami Web sync a Nastavení spojení: párování, kód, stav spojení, synchronizace, odpojení a oprávnění exportu. Mapa a databáze jsou na webu. Verze 0.6.0 přidává živou vlastní polohu přes barevný datový proužek addonu; historie dál používá uložení hry.

## Přestavba 0.8.0

Questy nyní otevřeš jako pergamenovou stránku s cílem, zadáním, odevzdáním, odměnami s ikonami a XP. Stejná karta je v Databázi, Deníku a Dungeon Journalu. Návody se čtou přímo ve hře: 26 kapitol, hledání, kategorie, přečtené kapitoly a interní přechody na recepty a materiály. Talenty jsou plánovač aktuální třídy: levý klik přidá bod, pravý odebere, můžeš změnit plánovaný level, načíst skutečné rozdělení a uložit build. Skutečné herní body tím nerozdělíš.

Starší stránky mají přestavěné rozložení a Nastavení vlastní kategorie. Při přechodu z 0.7.1 stačí `/reload`; nové soubory v TOC nepřibyly. Starší instalace vyžaduje jednorázový restart hry. Podrobnosti a hranice ověření: VYDANI-0.8.0.md.

## Co můžeš snadno vyzkoušet sám

1. Po instalaci nových souborů addonu hru jednou úplně vypni a znovu spusť, potom napiš `/etally`. Otevře se nové okno Evertally; v Nastavení můžeš zapnout mapu a minimapu. Pokud už jsi je zapnul, nepřepínej je znovu. Pro následný živý pohyb žádný další restart ani `/reload` nepotřebuješ.
2. Nový most nainstaluješ souborem `releases/EvertallySetup.exe`. Staré hlavní okno Evertally před aktualizací zavři; nové mosty a watcher dostávají žádost o korektní ukončení přímo od instalátoru. Menu mostu otevřeš pravým tlačítkem na ikoně vedle hodin nebo pod šipkou nahoru. Přes Start → Evertally — Web sync otevřeš spojení a párování.
3. V addonu zapni **Webový export**, **Moji postavu**, **Moji trasu** a **Živá poloha na webu** (poslední je výchozí vypnutá; bez ní addon nekreslí nic). Spárovaný most čte značku každé dvě sekundy, když je levý horní roh WoW viditelný a nezakrytý (i na druhém monitoru). Postava musí být aspoň jednou v souboru exportu (`/reload` nebo odhlášení), jinak most napíše, že tu postavu ještě nezná. Na webové mapě `https://evertally.afstudio.dev/#atlas` zapni **Moje trasa** a klikni na **Ukázat živou polohu**. Pohyb se objeví bez dalšího `/reload`, obvykle během několika sekund. Samotné zapnutí mapy/minimapy tato exportní oprávnění nezapíná.
4. Záznam dungeonu vyzkoušíš až skutečným průchodem; sdílení polohy a skupinové funkce vyžadují dalšího člověka, který má addon a sdílení povolí. Sám tím správnost přenosu neověříš.

Pozvánku `/invite`, `/script` ani diagnostické příkazy pro tyto základní kroky nepotřebuješ. Automatické testy a náhledy nejsou potvrzením, že vše funguje ve hře nebo že jsou všechny slíbené funkce hotové.

## Nově: kdo vidí tvoji polohu, mapa ve hře, panely na webu

**Kdo vidí tvoji živou polohu (web, panel Trasy a skupiny → Kdo mě vidí).** Tři volby, každá vypnutá, dokud ji nezapneš, a po vypnutí platí hned: **Moji přátelé** (oba souhlasíte; požádáš podle Discord jména, druhý potvrdí; kdokoli to může ukončit), **Všichni přihlášení** a **Úplně všichni, i nepřihlášení**. Ukazuje se jen živá poloha (ne trasa, ne starší polohy), jen když je hra zapnutá, most běží a máš souhlas s trasou a postavou. Nepřihlášený návštěvník vidí jméno, classu, úroveň a místo, nic, co by identifikovalo účet. Na mapě je vrstva **Hráči online**. Server: `et_sharing`, `et_friends` (migrace `0006_sharing.sql`), `/api/sharing`, `/api/friends`, `/api/public-live`. Migrace 0006 je na produkci přítomná (ověřeno 11. 11. 2026).

**Přátelé ve hře (Nastavení → Živá poloha a mapa → „Sdílet mou živou polohu s přáteli“).** Vypnuto. Poloha se šeptá přátelům ze seznamu přátel (postavy i Battle.net přátelé ve WoW), kteří jsou online a mají addon, nejvýš 12 najednou. Přijme se jen od někoho, kdo je v tvém vlastním seznamu přátel, takže cizí člověk ti nepoloží tečku na mapu. Vypnutí pošle přátelům konec.

**Přátelé a parta se poznají sami (verze 0.7).** Když je zapnutá živá poloha na webu a v Nastavení volby sdílení s přáteli a s partou, addon v tomtéž pásku pixelů posílá otisk seznamu tvých přátel (postavy i Battle.net přátelé ve WoW) a party nebo raidu, nejvýš 100 kontaktů, bez GUID, BattleTagu a poznámek. Web podle toho ukáže hráče, kteří jsou spolu ve hře přátelé nebo ve stejné partě, a to jen když oba mají zapnutou živou polohu a souhlas; ruční webové přátelství k tomu není potřeba. Změna party nebo přátel platí hned, bez `/reload`. Bez nové verze mostu se tohle nepřenese: **addon 0.7 a most 0.7 patří k sobě**, starší most pásek verze 4 nečte. Nainstaluj proto nový `EvertallySetup.exe` a WoW jednou úplně vypni a spusť.

**Mapa je OpenMap, Evertally pracuje uvnitř ní.** OpenMap je potřeba pro mapu a minimapu. V TOC je volitelná, aby se Databáze, Dungeon Journal a Recepty načetly i bez ní. Bez OpenMap se mapové funkce nespustí a addon to vysvětlí; tvoje volby zůstanou uložené. Vlastní mapové okno Evertally nemá; starý pokus zůstává v `archive/ownmap-2026-11-12/`.

**Kde jsou nastavení Evertally v OpenMap.** Na mapě otevři menu OpenMap (tlačítko menu u mapy). Evertally má v něm jen to, co OpenMap sama nemá (její vlastní Vendors, Class trainers, Profession trainers a spol. v sekci Townsfolk Evertally nenabízí podruhé). Všechny řádky Evertally jsou **anglicky**, protože celé menu OpenMap je anglické a jeho písmo nemá české znaky č, ř, š, ž, ě, ů (česky tam byly čtverečky):
- karta **On the map**, sekce **Evertally**: **Gathering (reference locations)**, **Gathering: herbs / ore / fishing pools / chests and containers** (druhy), **Gathering: all resources** (všechny suroviny najednou) a **Places marked from the database or the journey**;
- karta **On the map**, sekce **Evertally: herbs / ore / fishing pools / chests**: **každá surovina zvlášť** (70 řádků, každý s ikonou suroviny); zaškrtnutí jedné ji ukáže a zapne i druh a vrstvu, takže stačí „všechny suroviny“ odškrtnout a zaškrtnout jen tu, kterou hledáš;
- karta **On the map**, sekce **Evertally: trainers** a **Evertally: merchants**: **trenéři a obchodníci po druzích**, např. „Herbalism trainers“, „Warrior trainers“, „Alchemy Supplies“, „Reagent Vendor“ (u trenérů všechny druhy, u obchodníků druhy s aspoň šesti místy; úplný seznam je v okně). Druhy jsou z titulků NPC v QuestieDB (Journeyman Alchemist, Expert Alchemist a Alchemy Trainer jsou jeden druh „Alchemy trainers“). Řádky se objeví, až se databáze NPC jednou přečte (na pozadí, pár minut po zapnutí „Mapy a minimapy“); seznam se pak uloží a příště je v menu hned;
- karta **More**, sekce **Evertally**: **Evertally: choose resources…** (otevře okno Evertally), **Search the database** a **Plan a journey**.

Řádky se v menu objeví, až se načte modul mapy, tedy když je v Evertally zapnutá **Mapa a minimapa** (Nastavení nebo průvodce). Stejné volby jsou i v okně Evertally: **Svět → Mapa** (přepínače), **Svět → Sbírání** (každá surovina s ikonou a zaškrtávátkem, **Show all / Hide all** pro to, co hledání zrovna ukazuje) a **Svět → Služby** (trenéři a obchodníci po druzích s hledáním, zaškrtávátkem a **Show all / Hide all**; potřebuje QuestieDB). Piny lidí, srazů, pingů a cíle navigace jsou na mapě od zapnutí „Mapy a minimapy“ a kreslí se jen pro mapu, která je právě vidět. Místa sbírání jsou **zapnutá od začátku** (první, k čemu se mapa používá).

**Cesta a souvislá čára (addon 0.8.2).** Otevři **Mapa a cesty → Cesta**, napiš město nebo oblast, vyber výsledek a klikni **Navigovat**. Trasa se kreslí jako souvislá čára na mapě i minimapě; šipka ukazuje následující bod terénní cesty. Detail obsahuje cíl, odhad času a další krok, celý itinerář otevře **Všechny kroky**. **Ukázat na mapě** zobrazí náhled bez spuštění šipky; **Zastavit** zruší šipku i náhled čáry. Ovládání má vlastní patičku nad pergamenem a nezakrývá ho čtecí panel. Čára sleduje pohyb, natočení a zoom minimapy i posun mapy; prošlé body aktivní chůze mizí. Chůze používá zabalenou terénní masku a výsledky hledání stejné jako šipka, do nalezení trasy ukazuje přímou spojnici. Bez terénních dat zůstává přímá; maska nezná všechna patra a útesy. Let a loď jsou spojnice příslušných zastávek; kontinenty se nespojují jednou čárou přes celý atlas. QuestMaster předává cíl API Shortest Path Forever, které vlastní body veřejným API nevrací a vykresluje i tečky. Evertally proto vykresluje svou souvislou čáru přímo do OpenMap a minimapy. SPF lze výslovně spustit jako doplňkovou navigaci v nabídce šipky; nová běžná navigace jeho tečky automaticky nezapíná. Aktualizaci existujícího addonu načte **`/reload`**; Windows most ani web kvůli tomu aktualizaci nepotřebují.

**Ikony surovin.** Každá ze 70 surovin má vlastní ikonu: ID souboru ikony předmětu ve hře (list bylinky, kus rudy, jantar, škeble…), tedy žádná grafika se nepřibaluje. Pin na mapě je ta ikona (13 px) v tenkém barevném kroužku podle druhu (bylinka zelený, ruda oranžový, rybaření modrý, truhla žlutý). První verze měla 20 px a po prvním pohledu ve hře zakrývala mapu; velikost je teď o třetinu menší, ale **jestli to stačí, se ukáže až ve hře**. V **Svět → Sbírání** má každá surovina vpravo **zaškrtávátko**, kterým ji na mapě skryješ nebo ukážeš (zapamatuje se). Ikony **nebyly ve hře ověřeny**: náhled mimo hru umí ukázat jen číslo souboru.

**Nastavení při prvním spuštění (a kdykoli: `/etally setup`, nebo Nastavení → „Spustit nastavení znovu“).** Pár sekund po vstupu do světa (nikdy v boji, jednou za hru) se otevře průvodce o osmi krocích: **1 Jazyk** (čeština nebo angličtina, platí hned), **2 Web** (příprava dat pro tvoji stránku: rychlá volba Jen tady / Doporučené / Všechno, nebo jednotlivé přepínače), **3 Živá poloha** (party/raid, cech, přátelé a poloha na webu; zapnutí polohy na webu zapne i data pro web, postavu a trasu, a řekne to), **4 Sdílení s hráči** (souhrny a žádosti o pohled do výbavy), **5 Mapa a sbírání** (OpenMap je mapa; zapnutí míst sbírání a výběr druhů bylinky / rudy / rybářská místa / truhly, „lidé, srazy a pingy na mapě“ a věta, kde to v OpenMap najdeš; bez OpenMap krok napíše, že ji je potřeba nainstalovat, a volby se zachovají), **6 Okno** (tlačítko u minimapy, velikost okna), **7 Co potřebuješ** (aplikace Evertally pro Windows se stáhne na webu, na stránce Stažení; OpenMap je addon na CurseForge; obě adresy jsou v polích ke zkopírování, protože hra neumí otevřít odkaz: klikni, Ctrl+C, vlož do prohlížeče; u OpenMap krok ukáže, jestli je nainstalovaná) a **8 Shrnutí** s tlačítkem Dokončit. Nic se nezapne za tebe: všechno, co něco někam posílá, je na začátku vypnuté a použije se až při **Dokončit** (stejnými funkcemi jako Nastavení, takže se zvedne souhlas jen u toho, co se opravdu změnilo). **Zatím přeskočit** nic nepoužije a průvodce se sám znovu neotevře. Kdo už addon používal, vidí průvodce také jednou, s dosavadními volbami.

**OpenMap a Evertally, kdo co kreslí.** OpenMap má ručně malované podklady (autor Santiago Reyes, použité s jeho svolením) a ty nesmíme rozšiřovat ani je nejde napodobit z grafiky hry; proto je OpenMap závislost a ne něco, co bychom nahrazovali.
- Co OpenMap kreslí sama (létající mistři a lodě, trenéři, obchodníci, hostinští, vchody do dungeonů, kreslení perem, přátelé a cech podle zóny), Evertally nekreslí podruhé.
- Evertally přidává to, k čemu OpenMap vrstvu nemá: **místa sbírání s ikonami**, **živé hráče**, **srazy a pingy**, **navigaci a plánování cesty** a **hledání v databázi**. Zobrazení místa pak OpenMap sama doveze na správné místo a vrstvy se kreslí i v sousedních zónách, které máš v pohledu. Na mapě nevisí druhé tlačítko Evertally.
- `/etally map` otevře mapu (OpenMap).

**Menu v okně (přeskládané):** tři skupiny podle toho, o čem stránka je. **Moje historie**: Přehled, Deník, Běhy, Místa, Atlas, Profese (jen to, co jsi hrál; nic z toho není návod). **Průvodce**: **Databáze**, **Dungeon Journal**, **Mapa a cesty** (co hra ví, ne co jsi dělal). **Komunita**: Komunita, Lidé, Žebříček. Nastavení je dole.

**Databáze** (samostatná stránka, ne karta mapy; **každý řádek v detailu je odkaz**: quest → NPC, který ho dává → jeho další questy → item → kdo ho prodává; řádky mají ikony a pod jménem úroveň nebo titulek; nepotřebuje zapnutou „Mapu a minimapu“ ani OpenMap, čte QuestieDB, kterou máš): čtyři druhy, **NPC, Questy, Itemy a Objekty**. Bez psaní ukáže **celý seznam podle abecedy** (kolečkem se listuje, u tisíců záznamů rychleji), po zadání aspoň dvou písmen hledá. Detail se posouvá a ukazuje: u **questu** úroveň a potřebnou úroveň, oblast, co se má udělat (text i „Zabít / Použít / Sebrat“ se jmény), kdo ho dává a kdo přijímá (s místy), co udělat nejdřív, další quest v řetězu a předmět, který dá; u **NPC** titulek, úroveň, kde stojí a které questy dává a přijímá; u **itemu** ikonu s **tooltipem hry**, úroveň, **kdo ho prodává**, kdo ho dropí, v jakých objektech je, který quest spouští a za které je odměnou; u **objektu** místa a questy. **Ukázat na mapě** a **Navigovat k nejbližšímu** fungují jako dřív. Z **Deníku** otevřeš záznam questu, NPC nebo itemu a v okně je **co to byl za quest** (z databáze; quest, který tam chybí, se hledá v datech Dungeon Journalu, a když není nikde, řekne to) a tlačítko **Otevřít v databázi**. Šipka navigace vede levým klikem do téhle stránky na quest, NPC nebo item, ke kterému jdeš.

**Dungeon Journal** (samostatná stránka, postavená podle hotového addonu DungeonJournal): **mřížka karet s bannerem dungeonu** (umění čteme z addonu DungeonJournal podle cesty k souboru, nic se nekopíruje), název, úroveň a počet questů; hledání podle názvu nebo místa. Po otevření dungeonu jsou tři záložky: **Bossové** (seznam s úrovní a portrétem; loot bosse jako řádky s ikonou, **názvem v barvě kvality** a slotem, tooltip hry, klik otevře item v databázi), **Questy** (seznam; detail s cílem, kdo quest dává, kde se odevzdá, odměnami k výběru s ikonami a XP) a **Mapa** (mapa dungeonu s očíslovanými značkami bossů). Dole jsou tlačítka **Ukázat vchod na mapě** a **Navigovat ke vchodu**. Data jsou z addonu DungeonJournal (`ForeverDungeonJournal_NS`); bez něj stránka vypíše instance, které Evertally zná, a řekne, co chybí. **Ve hře neověřeno** (testy jedou na napodobenině dat).

**Stránka Mapa a cesty** (potřebuje zapnutou „Mapu a minimapu“ a OpenMap) má pět karet:
- **Mapa:** přepínače toho, co Evertally přidává do OpenMap: **Sbírání** a čtyři druhy (bylinky, rudy, rybářská místa, truhly, u každého kolik jich je zobrazeno) a tlačítka **Otevřít mapu**, **Vybrat suroviny…** a **Smazat označená místa**. Vrstvy, které OpenMap kreslí sama, tu nejsou.
- **Cesta:** vybereš zónu, město nebo létajícího mistra a uvidíš kroky z tvé polohy s časy (stejný plánovač jako na webu). **Navigovat** spustí šipku, **Ukázat na mapě** otevře světovou mapu.
- **Sbírání:** 70 druhů surovin, 32 065 referenčních míst, filtry bylinky/rudy/rybaření/truhly, hledání a výběr konkrétní suroviny; u každé její ikona a zaškrtávátko (zobrazit na mapě). Na právě otevřené mapě se vykreslí nejvýše 500 rovnoměrně vybraných pinů; počítadlo odlišuje zobrazená místa od celkového počtu. Referenční místo neznamená, že je surovina právě dostupná.
- **Dungeony/Raidy:** 45 instancí, z toho 41 s doloženým vchodem. Hledání, filtr dungeon/raid, zobrazení na mapě a navigace. U neznámého vchodu se navigace nenabízí.

**Okno addonu (nový vzhled).** Okno se dá **roztáhnout i zmenšit tažením za pravý dolní roh** (nejmenší 700 × 460, největší podle obrazovky); velikost i stránka, na které jsi skončil, se pamatují. Tlačítka **-** a **+** v záhlaví (nebo Ctrl + kolečko) mění měřítko 60 až 160 %. Když okno zúžíš pod zhruba 860 px, menu vlevo zůstane jen s ikonami (název ukáže po najetí). Kdyby okno uteklo mimo obrazovku nebo bylo divné, `/etally reset` vrátí velikost i polohu. Když některá stránka nejde vykreslit, ostatní fungují dál a poslední chybu ukáže `/etally diag`.

Menu je ve skupinách:
- **Postava:** **Přehled** (postava, zkušenosti a peníze, čtyři čísla, sloupcový graf aktivity za 14 dní; vpravo přepínač **Aktivita** (poslední události), **Oblasti** (kde jsi toho dělal nejvíc) a **Loot** (poslední předměty jako ikony); banner postavy má barvu třídy), **Deník** (časová osa po dnech s filtry Vše, Questy, Loot, Místa, Levely, Dungeony a hledáním; filtr Questy je přehled questů, jeden řádek na quest: rozpracováno, splněno, opuštěno), **Běhy** (čtyři čísla a filtr Vše / Dokončené / Přerušené), **Profese**, **Místa**.
- **Svět:** **Svět** (databáze a cesta), **Atlas**, **Komunita**.
- **Lidé:** **Lidé** (vlevo hráči v okolí: tvůj cíl, skupina, ti, kdo sdílejí polohu, přátelé online, členové cechu online a ti, kdo ti ukázali věci (kliknutím se jméno vyplní do žádosti); vpravo žádost o pohled do hráče a to, co ti ukázali; dál živá poloha, výměny, srazy a soukromí) a **Žebříček** (Dokončené dungeony, Úroveň, Nejrychlejší běh a Nejlepší čas v dungeonu; první tři mají vlastní kartu s medailí; řadí hráče, jejichž addon s tebou sdílel, a tebe, ne celý server).
- **Nastavení.**

**Pohled do hráče** se otevře, když ti někdo ukáže své věci: výbava a tašky jsou **mřížka ikon** (barevný rámeček podle kvality, po najetí popis předmětu). Kliknutím na předmět ho označíš jako chtěný (znovu = celý stack, znovu = zrušit); vpravo vybereš z vlastních tašek, co nabízíš, a pošleš návrh výměny. Profese a zlato jsou řádky.

**Panely na webové mapě** se dají přesouvat za záhlaví (dvojklik je vrátí) a nepřekrývají otevřený seznam vrstev. Vrstva **Hráči online** a nastavení **Kdo mě vidí** jsou v panelu Trasy a skupiny.

## Instalace aplikace

1. Spusť `releases/EvertallySetup.exe`. Instaluje se pro aktuálního uživatele do `%LOCALAPPDATA%\Programs\Evertally`, bez administrátorského účtu.
2. Ponech **Spouštět Evertally automaticky s World of Warcraft Forever**, pokud tuto funkci chceš používat. Zástupce na ploše je volitelný; položka Start a odinstalace jsou součástí.
3. Pro instalaci addonů zaškrtni příslušnou volbu a vyber složku s `Wow.exe` nebo rodiče obsahujícího `_forever_`. Předchozí soubory Evertally se zálohují; SavedVariables se nemění.
4. WoW restartuj sám, pokud přibyly nové soubory v `.toc`. Most najdeš vedle hodin Windows; v nabídce Start je Web sync a odinstalace.

Instalátor obsahuje tray most, `EvertallyBackground.exe` a všechny tři addony. Mapové a databázové podklady se pro Windows už nebalí. Samostatné EXE a ZIP jsou pomocné varianty; hlavní cesta je instalátor. Existující `config.json`, token a soubory hry se aktualizací nepřepisují. Starší localhost přepni v Nastavení spojení na `https://evertally.afstudio.dev`. Uložení nastavení zálohuje předchozí konfiguraci do `config.json.bak`.

Produkční databáze obsahuje migrace 0005 (živý bod) i 0006 (volby sdílení a přátelé); jejich přítomnost byla ověřena 11. 11. 2026. Skutečný most odesílal nové body a ostrá databáze měla bod starý tři sekundy. Nové soubory addonu načti jednorázově úplným restartem hry. Toto měření nepotvrzuje vzhled nového UI, průchod dungeonem, správnost každé šipky ani všechny scénáře startu s WoW.

## Spouštění s WoW

Per-user Windows Run spouští malý `EvertallyBackground.exe`. Každé čtyři sekundy kontroluje seznam procesů a cestu WoW Forever. Při novém procesu hry jednou spustí tray most bez hlavního okna a bez otevření prohlížeče. Nečte paměť hry, nevkládá DLL a neovládá její UI.

Když v menu ikony vybereš Ukončit, stejná běžící hra most znovu nespustí. Nový start hry ho může spustit znovu. Vypnutí automatického spouštění odstraní Run registraci a zastaví watcher. Samotný build neprokazuje reálné chování při hře.

## Addon a ukládání

Složky jsou `Interface\AddOns\Evertally` a `Interface\AddOns\Evertally_Export`. Samostatnou instalaci zajišťuje `Install-Addon.ps1` se zálohou a kontrolou hashů; alternativou je `releases/Evertally.zip` rozbalený do AddOns.

- `/etally`: devět karet — přehled, výpravy, atlas, žebříčky, peers, komunita, profese, místa, nastavení.
- `/etally web on` / `web off`: příprava webového exportu, výchozí stav vypnuto.
- `/etally share on` / `share off`: samostatné sdílení ve skupině/guildě.
- `/etally finish`: ruční konec návštěvy, nikoli ověřený rychlostní rekord.
- `/etally diag`: diagnostika; `/etally export`: JSON pro ruční import.
- `/etally terrain`: aktuální navigační cíl předá volitelnému addonu Shortest Path Forever, který může vést cestu po terénu. Nejdřív zapni mapu Evertally a nastav cíl. Předání může nahradit předchozí cestu v Shortest Path Forever; pohybující se cíl předá jako aktuální bod, nikoli živě sledovanou trasu. Bez něj zůstává šipka Evertally vzdušnou čarou. Na navigačním panelu je totéž i jako tlačítko **Terén** (vlevo dole pod šipkou, vidět jen když je Shortest Path Forever nainstalovaný; po spuštění se změní na „Terén: zap.“). Vlastní hledání cesty po terénu Evertally ve hře nemá: ani QuestMaster, ani Questie ho neobsahují, oba předávají cíle právě Shortest Path Forever (QuestMaster přes stejné `ShortestPathForever.API`, Questie přes jeho náhradu TomTomu). Funkce zatím nebyla ověřena ve hře.

Detail výpravy ukazuje dostupné boss časy/splity, obtížnost, vlastní úmrtí, skupinu a časové hranice. Profese a Místa obsahují recepty, cooldowny a navštívené oblasti. Neznámý údaj není nula.

Hra zapisuje SavedVariables při `/reload`, odhlášení nebo ukončení. Historie se přenáší pouze ze schváleného `Evertally_Export.lua`, nikoli z celého `Evertally.lua`. Živá poloha jde odděleně a jen když ji v Nastavení zapneš: addon vykreslí **jeden řádek 39 pixelů** úplně vlevo nahoře ve čtyřech odstínech mezi černou a 19% šedí (první čtyři pixely jsou srovnávací stupnice, zbytek nese 26 bajtů). Spárovaný most čte pouze tento řádek z okna WoW v popředí, dekóduje ho a z exportovaného souboru k němu doplní postavu. Obraz se neukládá ani neposílá. Čtení paměti hry ani ovládání hry se nepoužívá. Alt-tab, minimalizace nebo zakrytí rohu přenos přeruší. Jiná cesta ven ze hry neexistuje: klávesy, logy ani `SendAddonMessageLogged` na disk živě nezapisují (ověřeno 11. 11. 2026).

Web čte živé body každé tři sekundy. Označení ŽIVĚ platí nejvýše 30 sekund bez nového bodu; poté se případně ukáže starší uložený bod s časem. Server uchovává jen poslední živý bod každé postavy, nepřidává každé dvě sekundy historii trasy. Čáru, kudy tvoje postava právě jde, proto **dokresluje prohlížeč** z těchto bodů: začíná od chvíle, kdy stránka postavu poprvé vidí, a uchovává se jen v prohlížeči (2 hodiny, jen pro tvůj účet); uloženou trasu z hry doplní až `/reload` nebo odhlášení. V panelu Trasy a skupiny je přepínač **Zobrazit cesty**, který schová všechny čáry cest (uložené, živé i cesty členů) a nechá na mapě jen hráče; volba se pamatuje v prohlížeči. Přístup kontroluje přihlášení, aktivní zařízení, souhlas a členství ve sdílené skupině/cechu.

## Mapa a databáze na webu

Mapu, databázi, postavy, výpravy, profese a žebříčky otevři na webu. Dřívější desktopové přehledy byly od verze mostu 0.5.0 vyřazeny. Staré zdrojové soubory zůstávají v historii projektu, běžný balíček je nesestavuje.

Web používá tyto podklady:

| Podklad | Rozsah |
| --- | --- |
| Mapy | 60 skutečných herních podkladů s vazbou na C_Map UIMapID |
| Itemy | 22 881 referenčních záznamů; část základních itemů zatím nemá známou ikonu |
| Questy | 5 232 základních záznamů |
| NPC | 12 078 základních záznamů, u dostupných dat referenční výskyty |
| Instance | 45 dungeonových/raidových záznamů |
| Recepty | 2 339 referenčních receptů |
| Návody | Dva vlastní stručné návody k používání Evertally |

Nejde o knihu raidových strategií ani úplně ověřenou databázi aktuálního buildu. NPC/questy jsou základní řádky QuestieDB pro Forever bez runtime oprav. Zdroje a licence jsou v `THIRD_PARTY.md`.

Mapy vznikly z lokálních CASC souborů wowf 1.60.1.70862, mapová metadata z DB2 1.60.1.70291. Databázové NPC výskyty jsou samostatný zdroj, nejsou hráčská pozorování. Neznámé mapové ID se nepřiřazuje odhadem. Race obrázek je symbol rasy; pohlaví postavy se nesbírá.

Databáze nabízí hledání jména/přesného ID, filtry kvality nebo dungeon/raid, stránkování a detail. Odkazy propojují referenční quest/NPC/item ID. Zdroj lootu neznamená změřenou šanci na drop.

## Webová mapa a databáze

**Mapa světa** je jedna plynulá mapa jako v addonu OpenMap: svět → kontinent → zóna → ulice bez klikání dovnitř a ven. Zóny jsou umístěné podle skutečných herních souřadnic a postupně se prolínají. Zadavatelé questů, obchodníci, trenéři, hostinští, banky, aukce, stájníci, bojoví mistři, opravy, léčitelé duší, schránky a tvorové jsou samostatné vrstvy s ikonami; vrstvy se pamatují. Seskupené body se neslučují do čísel: při přiblížení se rozevřou, kliknutím vznikne seznam míst pod kurzorem. Souřadnice kurzoru jsou souřadnice zóny jako ve hře.

- **Hledání** najde oblasti, města, dungeony a raidy, letištní mistry, NPC, questy i itemy. Quest ukáže zadavatele, odevzdání a místa zabití; item ukáže, kdo ho dropuje (s šancí), kdo ho prodává a v jakých zónách.
- **Letištní síť** s časy letů z měření, **lodě, zeppeliny a vzducholodě** s trasami. Klik na letištního mistra ukáže přímá spojení.
- **Plánovač cest** (panel *Naplánovat cestu*): vyber Odkud a Kam (hledáním, klikem na mapu nebo tlačítky *Cestovat odsud/sem* u libovolného bodu). Porovnává chůzi, lety, lodě, zeppelíny, výtahy, **Deeprun Tram** a portály podle frakce a rychlosti. U lodí je průměrné čekání, ne přesný odjezd. Po načtení masky terénu se cena pěších úseků z vlastního bodu zohledňuje již při výběru trasy. Čas je stále odhad; maska nezachycuje všechny překážky a plánovač nezaručuje skutečně nejrychlejší cestu ve hře.
- **Dungeony a raidy**: vchod s úrovní (barva podle *Můj level*), po kliknutí karta s **mapami pater** z klienta, bossové a loot.

**Databáze** má Dungeony a raidy (banner, mapy pater, bossové s lootem a šancemi), Itemy (tooltip jako ve hře, změny oproti Classicu, zdroje, dropy, prodejci, odměny, vyrobí/surovina v receptech), NPC (výskyt na mapě, questy, zboží, dropy), Questy (cíle, řetězce, odměny, tipy a postup z forever-db), **Recepty** (suroviny, barvy dovednosti, kde se učí) a Návody (vybrané komunitní weby).

Data vznikají skripty (každý jen čte lokální soubory, bez sítě): `python tools/build_map_data.py`, `python tools/build_travel_data.py`, `python tools/build_dungeon_floors.py` (čte klient přes CASC), `python tools/build_db.py`, `python tools/build_dungeon_art.py`. Pořadí viz hlavičky skriptů. Zdroje a licence: `THIRD_PARTY.md`.

Hranice: mapy mají nativní rozlišení hry (zoom do cca 4×); poloha NPC a vchodů je z referenčních databází, ne z živého serveru; šance na drop jsou jen tam, kde je zdroj měřil; předměty z raidů nemají tooltip, jen známá fakta; nové Forever instance (Hyjal, Barrow Deeps, nová Onyxia) čekají na vytěžení lootu. Rozhraní nebylo zkontrolováno na dotykovém zařízení. Aktuální webová verze je od 10. 11. 2026 nasazena na evertally.afstudio.dev.

## Soukromí a aktivita oblastí

**Přesná živá poloha je dostupná vlastnímu účtu a dobrovolně zvoleným skupinám a cechu.** Do veřejných profilů a komunitních vrstev se neposílá. `zone.visited` ukládá pouze ID/název oblasti bez x/y. **Moje trasa**, **Můj cech** a skupinové sdílení vyžadují zapnutí příslušných oprávnění. Historické hráčské souřadnice při běžných interakcích se odstraňují při zpracování addonu, Rust uploaderu i TypeScript projekce.

Aktivita oblastí znamená různé přispívající účty se zaznamenanou návštěvou za 24 hodin, až od tří účtů na oblast. Veřejný čas návštěvy je hrubý, po dnech. Nejde o online počet hráčů, populaci realmu ani trasu postavy. Profil ukazuje navštívené oblasti a omezené výpravy podle viditelnosti a aktivních souhlasů. Profese jsou soukromé pro vlastní účet. Přijatá peer data nikdy nejsou vlastním webovým exportem.

## Moje trasa a cech (dobrovolné, ve výchozím stavu vypnuté)

V addonu (Nastavení → Webový export) jsou dvě nové oblasti. Obě fungují jen při zapnutém webovém exportu a nikdy zpětně.

- **Moje trasa** (`own_track`): addon každé 4 s zjistí polohu postavy a ukládá body do úseků (jedna mapa, nejvýš 100 bodů; stání na místě přidá jen občasný bod). Do lokální historie addonu se nic nepíše, jde rovnou do výstupní fronty. Body se zaokrouhlují na tři desetinná místa mapy. Fronta drží nejnovějších 500 úseků. Hra soubor zapisuje při `/reload` nebo odhlášení, takže web vidí trasu až potom.
- **Můj cech** (`guild_share`, vyžaduje „Moje postava“): addon pošle jméno cechu a hodnost postavy; **guildmaster** (hodnost 0) navíc seznam členů (jméno, hodnost, level, classa), nejvýš jednou týdně.

Na webu (Mapa → vrstva **Moje trasa**) vidíš svoji trasu podle postavy a období (24 h / 7 dní / 30 dní), můžeš ji skrýt vrstvou, ukázat poslední polohu nebo **smazat**. Trasa je soukromá pro tvůj účet a uchovává se **30 dní** (starší body se smažou při dalším nahrání).

Vrstva **Cech** funguje takhle: člen cechu vidí cech až po **potvrzení na mapě** („Připojit a sdílet“) a zvolí, co sdílí: nic, poslední polohu, nebo poslední polohu i trasu za 72 h. Vidí se jen členové, kteří potvrdili stejný cech a jsou v seznamu, který nahrál guildmaster; kdo ve hře z cechu odejde nebo v dalším seznamu chybí, přestane být vidět. Odvolání souhlasu nebo smazání dat sdílení hned ukončí.

Hranice: server **neumí ověřit hodnost v cechu**, protože addon je jediný svědek. Seznam členů proto vlastní první guildmaster, který ho nahraje (další ho nepřepíše), a každý člen na mapě vidí jméno té postavy, než se připojí. Aktivní most posílá živou polohu; bez něj zůstává poslední uložený bod s časem.

Ověření: `platform/tests/people.test.ts` (pravidla viditelnosti nad skutečným SQLite), `tools/verify_people_flow.mjs` (HTTP proti lokálnímu D1, tři účty), Lua testy `People.lua`. Ve hře se tohle zatím nezkoušelo.

## Skupiny a srazy

**Skupiny** (panel *Cech a skupiny* → Skupiny): parta, raid nebo pár kamarádů. Založíš ji na webu (jméno + postava), dostaneš **kód pozvánky** a pošleš ho; ostatní ho zadají a **každý sám volí, co sdílí** (nic / poslední polohu / polohu i trasu za 72 h). Člen, který nesdílí nic, je vidět jen jako jméno. Majitel může kód obnovit, člena odebrat nebo skupinu zavřít; odejde-li majitel, přejde skupina na člena, který v ní je nejdéle. Pro polohu platí stejné podmínky jako u cechu (platný souhlas s `own_track` a `own_character`).

**Srazy** (vrstva *Srazy*, nahoře v docku): pravé tlačítko na mapě → *Naplánovat sraz tady*. Druhy: **Sraz**, **Výprava** (dungeon/raid a hledané role tank/healer/damage), **Farmení** (surovina), **Obchod** (co hledám a co nabízím, předměty s počtem), **Událost**, **Poznámka**. Vybereš čas (hned / za 15 min … / vlastní) a délku, **komu je ukázat** (cech, skupina, nebo kdokoli s odkazem) a případně nejvyšší počet lidí. Ostatní odpoví *Jdu / Možná*; sraz ukazuje jen místo, které autor vybral, nikdy kde je.

- **Trasa k srazu**: plánovač z tvé poslední známé polohy; **Kopírovat do hry** dá příkaz `/etally waypoint <mapa> <x> <y> <název>`, který ve hře nastaví waypoint.
- **Spravedlivé místo**: ve formuláři tlačítko *Navrhnout spravedlivé místo* vybere z letištních mistrů ten, kde je nejdelší cesta ze všech známých poloh nejkratší (lety, lodě, chůze; odhad).
- **Kde to sehnat**: u hledaných předmětů v *Obchodu* tlačítka *Obchodníci* (zapne vrstvu a vybere předmět) a *Místa sbírání* (zapne sbírání jen pro tu surovinu).
- Odkaz na sraz: `#atlas?meet=KÓD` (kopíruje se u srazů s odkazem). Skončené srazy se týden po konci mažou.

## Lidé ve hře (addon: stránka *Lidé*)

Jde o věci mezi **dvěma hráči s addonem** (addonové šeptání, ne web).

- **Podívat se na hráče**: napiš jméno (nebo *Můj cíl*), zaškrtni, o co žádáš (výbava a tašky / profese / zlato), *Odeslat žádost*. Druhý hráč dostane okno *„X se chce podívat na…“* s volbou **Povolit / Odmítnout / Blokovat** a políčky, co přesně ukáže (zlato je ve výchozím stavu nezaškrtnuté). Bez jeho odpovědi se **nic neposílá**. Odpověď „nic“ znamená odmítnutí; po odmítnutí 45 s ticho. Funguje i příkazem `/etally inspect <jméno>`; odpovědět jde i v chatu: `/etally allow <id>` / `/etally deny <id>`.
- **Co uvidíš**: nasazené věci podle slotů, tašky (součet podle itemu), zlato, profese s dovedností a znalými recepty (jen ty, které si druhý hráč v addonu už uložil otevřením profese). Tooltip itemu při najetí.
- **Chci toto vyměnit**: v okně klikni na věc = *chci* (znovu = celý stack, znovu = zrušit); vpravo vyber ze svých tašek, co **nabízíš**, přidej zlato a poznámku a *Poslat návrh*. Druhý hráč dostane okno s *Přijmout / Odmítnout*. Je to jen zpráva: samotná výměna proběhne běžným oknem výměny ve hře.
- **Sraz ve hře**: *Lidé → Srazy*, text a tlačítko *Partě / raidu*, *Cechu* nebo *Mému cíli* pošle tvoji aktuální polohu; příjemce dostane okno s tlačítkem *Nastavit waypoint*. Příkazem `/etally meet [text]`.
- **Soukromí**: co ti druhý ukáže, drží jen běžící addon (nikdy se neukládá do `SavedVariables` ani neexportuje; testováno). Addon si jen na krátko pamatuje, komu a co ukázal ty. Ignoruje se: zablokovaný hráč, vypnutá volba v Nastavení, víc než 3 otevřené žádosti, spam.

Hranice: **ve hře to neběželo**. Testy jsou v Lua replay (dvě instance addonu a falešný přenos zpráv, mock okna); skutečné API klienta Forever (tašky, `GetInventoryItemID`, waypointy, šeptání mezi realmy) je neověřené. Přenos je omezený klientem (~1 zpráva za sekundu), takže plný inventář se přenáší desítky sekund.

## Živá poloha, mapa a navigace ve hře

Vše je ve výchozím stavu **vypnuté** a zapíná se v addonu: *Nastavení → Živá poloha a mapa*.

- **Živá poloha** (zvlášť *parta / raid* a *cech*): dokud se hýbeš, addon asi každých 5 s pošle do toho kanálu zprávu `S|L|mapa|x|y|classa` (stání na místě jen občasný signál po 30 s; nové zprávy nahrazují ještě neodeslané). Dostanou ji jen hráči s addonem, nikam se neukládá ani nenahrává. Po vypnutí jde okamžitě `S|E` a body zmizí. Dokud je zapnutá, svítí v hlavičce okna štítek **ŽIVĚ**. Příjemce si bere polohy jen z kanálů party / raid / cech, nejvýš 120 lidí a nejvýš jednu zprávu za 2 s od jednoho odesílatele; po 2 minutách bez signálu zmizí.
- **Mapa a minimapa** (třetí přepínač) načte druhý addon **Evertally_Map** (načítá se na vyžádání, bez zapnutí neběží nic z něj). Kreslí přes knihovnu HereBeDragons-Pins body: lidé v barvě classy (členy tvé party minimapa hry kreslí sama, proto tam jsou jen na světové mapě), **srazy** (vlajka), **pingy** a cíl navigace. Srazy, pingy a cíl na minimapě plavou po okraji, takže je vidět směr.
- **Ping**: klávesová zkratka *Hlavní nabídka → Klávesy → Evertally → Ping* (při otevřené světové mapě a kurzoru na ní padne ping na kurzor, jinak na tvoji polohu), nebo `/etally ping [text]`. Jde partě / raidu, mimo skupinu cechu. Vidí se 5 minut.
- **Navigace**: `/etally go <jméno | meet | ping>` (jméno stačí začátkem), `/etally stop`, nebo klik v *Lidé → Živě* a v okně srazu (*Navigovat*). Pod minimapou se ukáže **velká šipka bez panelu** (**tahem se přesouvá**, **levý klik** otevře to, kam šipka vede: quest, NPC nebo předmět z databáze, surovinu, druh trenéra či obchodníka, instanci nebo místo plánovače v okně Evertally s tou položkou vybranou, u hráče stránku Lidé; **pravý klik** otevře nabídku **Změnit velikost** (objeví se roh, za který táhneš; 0,5× až 3×), **Schovat šipku**, **Vrátit velikost a polohu** a **Zrušit navigaci**; schovanou šipku vrátí `/etally arrow`, navigace přitom běží dál), pod ní **vzdálenost** (v yardech) a název cíle. **Šipka mění barvu podle toho, jak jsi k cíli otočený:** zelená, když míříš k němu, přes oranžovou, když je bokem, po červenou, když je za tebou (barvu počítá `M.ArrowColor`, plynule). Pod tím je text: kam jít, vzdálenost, a pokud je cíl daleko, **kroky cesty** (dojdi k letišti, leť, nalodění, portál ...) z téhož plánovače jako na webu. Plánovač je přenesený do Lua a hlídá ho test: 1 388 cest dává stejný výsledek jako webový. Plán se každých ~8 s počítá znovu od tvé polohy, takže jde za tebou i za pohybujícím se hráčem. Pravé tlačítko na šipku navigaci zruší, tažením ji přesuneš.
- **Na webu**: u člena cechu nebo skupiny s polohou tlačítko **Trasa k tomuto hráči** (vyjde z tvé poslední známé polohy).
- Příkazy pro ladění: `/etally navdebug` vypíše směr, který počítá addon, a směr podle HereBeDragons, aby šlo ve hře ověřit, že šipka míří správně.

**Trasy po terénu (web i addon):** plánovač cest na webu kreslí chůzi **po zemi**, ne vzdušnou čarou. Maska průchodnosti (`walk.bin`, 97 KB, vyrobená skriptem `tools/build_walkmask.py` z terénních dat Shortest Path Forever v GatherLite) ví, kde se dá stát (země, voda, zablokováno) v 16yardových buňkách, a vyhledávání cesty (`db/terrain.ts`, A* po buňkách) obchází pohoří a vodu a vede podél řek a pobřeží. Příklad: z Auberdine do Felwoodu je vzdušnou čarou asi 1 950 yardů, po zemi asi 9 600, protože mezi nimi stojí hory (obrázek s červenou cestou a tenkou bílou přímkou jsem si vykreslil z masky). Masku stáhne stránka jen při prvním plánování a hledání trvá medián asi 8 ms (nejdéle 175 ms).

- **Čas chůze mezi pevnými místy** zůstává upečený (SPF), mění se jen čára. **Čas z a do tvých vlastních bodů** je délka cesty po masce krát **1,18**, což je naměřený medián poměru upečených cest k cestám po masce (`GROUND_FACTOR`, hlídá ho test). Upečené cesty SPF vznikly hierarchickým hledáním, které nenachází vždy nejkratší cestu, takže 1,18 je **kalibrace**, ne tvrzení, že skutečná cesta je o 18 % delší. Je to pořád odhad a jako odhad je označen.
- **Změřeno:** všech 2 781 upečených cest mezi pevnými místy na masce existuje (žádná chybějící); délka po masce je medián 85 % upečené délky (10. percentil 62 %, 90. percentil 95 %); vzdušná čára je medián jen 66 %.
- **Co maska neumí:** neví o útesech mezi sousedními buňkami (stupně v datech SPF) ani o patrech budov a tunelů, takže cesta může být místy optimistická. Druhy chůze (plavání, jízda) nerozlišuje; voda se v hledání cení třikrát.
- **Terén ve hře:** addon obsahuje stejnou masku v TerrainData.lua. Terrain.lua hledá cestu postupně v malých dávkách a šipka vede přes vypočtené body. Během výpočtu nebo mimo pokrytí masky ukazuje přímý směr a tento stav označí; skutečné překážky a patra ve hře musí potvrdit hraní.

**Neověřeno ve hře:** vykreslení bodů na mapě a minimapě, směr šipky (`SetRotation` a `GetPlayerFacing` u klienta Forever), doručování zpráv do cechu a party mezi realmy a **taint**. Knihovna HereBeDragons-Pins při načtení volá `WorldMapFrame:AddDataProvider` a zapisuje do `WorldMapFrame.pinPools`; proto se načítá až po zapnutí. Samotná kontrola okna a mapy nevyžaduje pozvánku do skupiny ani příkaz `/script`. Sdílení mezi hráči vyžaduje dalšího hráče s addonem a jeho zapnuté sdílení.

## Další nápady (nepostavené)

Co by hráči s tím vším mohli dělat a co zatím **není** hotové: sdílená poznámka k bodu v cechu (špendlík se vzkazem); upozornění na blížící se sraz ve hře (addon nemá síť, šlo by přes aplikaci Sync); seznam „kdo v cechu umí vyrobit X“ po souhlasu s profesemi; sledování cen proti obchodníkům u návrhu výměny; sdílená trasa farmení pro skupinu; ověření, že návrh výměny skutečně proběhl (okno výměny addon číst nesmí).

## Trenéři, obchodníci a sbírání

- **Trenéři a obchodníci** (dock → tlačítko s ikonou trenéra): vyber profesi a uvidíš trenéry profese po celém světě; vyber regeant nebo libovolný item (hledání, nebo „Často potřebné“) a uvidíš obchodníky, kteří ho prodávají (kterýkoli z vybraných, nebo všechny). Klik na bod otevře kartu NPC se vším zbožím. Data: `python tools/build_services.py` (z již vytvořené databáze; trenér = služba trenéra + profese v titulu NPC).
- **Sbírání** (dock → list): bylinky, rudy, bedny a rybářská místa; každou surovinu jde zapnout/vypnout zvlášť, jde zadat *Moje dovednost* a skryjí se suroviny, které ještě nemůžeš sbírat. Body se kreslí od zoomu zóny. **Trasa pro farmení**: tlačítko vyhledá v aktuální zóně vybrané suroviny a naplánuje pořadí od tvé poslední polohy (nejbližší soused + 2-opt, nejvýš 40 uzlů, čas pěšky je odhad). Data: `python tools/build_gather.py` (z addonu GatherLite, jen souřadnice a názvy; viz `THIRD_PARTY.md`).
- Neumístitelné: ostrov **Zephras Isle** (nová zóna Forever) není na světové mapě, takže jeho trenéři a uzly se v panelu jen započítají do „na ostrovech, které mapa neukazuje“.

## Kreslení

Při aktivním nástroji kreslí levé tlačítko a **pravé tlačítko táhne mapou** (jako v OpenMap); obyčejné kliknutí pravým stále otevře nabídku. Kresby, značky i trasy leží ve vlastní vrstvě nad uměním zón, takže se po přiblížení neschovají. Starší kresby bez tloušťky a zoomu se při načtení doplní výchozími hodnotami.

## Dobrovolná synchronizace

1. V addonu zapni `/etally web on`, vyber oblasti sdílení a dej `/reload`.
2. V aplikaci Sync → Pair this PC. Na webu potvrď stejný kód a povolený rozsah.
3. Další zápis herních souborů přenese jen nové povolené záznamy. Server odmítá duplicity.

Token je ve Správci pověření Windows. Nastavení, `state.json` a `sync.log` jsou v konfigurační složce Evertally; log neobsahuje tokeny. Změnu souhlasu ve hře vidí aplikace až po zápisu souboru. Pro okamžité odmítnutí odvolej grant/zařízení na webu. Zveřejnění profilu v Account je samostatné; Delete my web data smaže herní data/profily a odvolá přístupy, identita Discordu a revokační záznamy zůstávají.

Bez aplikace: Web → Sync → Manual import → `Evertally_Export.lua`. Před souhlasem se čte lokálně v prohlížeči. Komunitní JSON zpět do hry: Atlas → Copy for addon, potom `/etally` → Komunita → Import. Limit 150 anonymních entit, 48 KiB, platnost nejvýše sedm dní. Cache se neodesílá dál.

## Běhy a žebříčky

Výpravy odlišují přerušené měření, ruční konec, posledního bosse a plný clear. Časové souhrny nesměšují instance, obtížnosti, definice dokončení, realmy ani buildy. Žebříček počítá zaznamenané účasti veřejných postav; více hráčů skupiny může popsat stejnou návštěvu. Rychlostní rekordy jsou vypnuté do herního ověření rulesetů. Classa ani rasa nepředstavují hodnocení schopností.

## Vývoj a ověření

Zdrojový projekt má lokální Git historii v `D:\addon`; web má samostatnou historii v `D:\addon\platform`. Jde o první místní revize, ne o obnovení starší historie. Zálohy, přihlašovací údaje, lokální databáze, sestavení a generované herní podklady nejsou součástí Git historie; zůstávají v existujících složkách a pro úplnou obnovu se musí zálohovat zvlášť.

| Část | Kontrola |
| --- | --- |
| Addon | `python tests/lua/test_addon.py` |
| Web | `npm test`, `npm run typecheck`, `npm run lint`, `npm run build` v `platform` |
| Sync | `cargo test --no-default-features --lib` v `sync` |
| Native | `cargo test`, `cargo clippy --all-targets -- -D warnings` v `desktop/native` |
| Sestavení | `Build-Release.ps1`, `Build-Installer.ps1`; bez spuštění GUI/hry |
| Balení | `python tools/package_addon.py`; hashe v release manifestech |
| CPU náhledy | `Evertally.exe --render-preview <adresář>`; bez oken, HTTP nebo vstupů do PC |
| Watcher | `EvertallyBackground.exe --diagnostics`; bez spuštění GUI |

Vývojový web spouští `Spustit-web.ps1` na `http://127.0.0.1:5173`. Distribuční build míří na veřejný server; přímý Cargo build bez `EVERTALLY_SERVER` používá loopback. Existující config má přednost. Automatická aktualizace aplikace zatím není implementovaná.

Podklady generuje `tools/build_reference_data.py`. Po web buildu spusť v `platform` `node scripts/prepare-production.mjs --check-db --dry-run`. Produkční D1 už má migrace; neopakuj `--init-db`. Tajné hodnoty patří do ignorovaných lokálních souborů a Worker secrets.

## Stav Windows Bridge 0.5.0

Nový most je sestavený jako tray aplikace a má malé okno Web sync a Nastavení spojení. Instalační test běží ve vlastní složce s vlastními pojmenovanými událostmi: ověřuje uvolnění zamčeného souboru, zálohování a aktualizaci addonů. Staré desktopové okno se při běžném spuštění nové verze nevytváří. Sestavení ani tento test neinstalují novou verzi do běžící aplikace uživatele.

Živý přenos polohy na web, nativní tray menu při skutečném běhu, dokončení Discord párování a automatický start se skutečnou hrou zůstávají bez nového runtime ověření. Pro orientaci používej aktuální `desktop/README.md`.

## Historická kontrola vydání 0.4.0 (před přechodem na most)

Web 0.4.0 je veřejně nasazený na `https://evertally.afstudio.dev` (Cloudflare verze `7177013e-11b0-461b-9838-86d61c821a91`). HTTPS kontrola potvrdila status 0.4.0, `auth.discord=true`, `devLogin=false`, 60 map a katalogy. Hashe staženého addonu, aplikace a instalátoru souhlasí s manifesty. Veřejná headless kontrola prošla 11 scénáři: mapa/zoom/NPC piny, aktivita bez hráčských GPS bodů, katalogové ikony a přesné hledání, questy, dungeonový loot, návody, mobilní zobrazení a žádné chyby stránky.

Aplikace je skutečně nainstalovaná v `C:\Users\domin\AppData\Local\Programs\Evertally`, včetně watcheru, resources a odinstalace. Hash GUI a watcheru byl ověřený. Windows Run `EvertallySync` míří na nainstalovaný `EvertallyBackground.exe`; watcher běží bez viditelného okna. Reálné spuštění aplikace při startu WoW zatím nebylo ověřené, protože hra při této kontrole neběžela. Existující vývojová adresa byla přepnutá na veřejný server se soukromou zálohou konfigurace. Aktuální důkazy jsou v `releases/verification.json`, `releases/public-verification.json` a manifestech.

Addon 0.4.0 je souborově nainstalovaný a ověřený hash kontrolou; záloha je `backups/20261109-231144-927`. Nové UI nebylo vizuálně ověřené ve hře. 34 Lua replay testů a technické kontroly nenahrazují skutečné bossové události, přenos mezi hráči nebo ovládání aplikace.

Discord metadata, ikona, callbacky a serverové klíče jsou nastavené; začátek OAuth je ověřený. Celý login zůstává neověřený kvůli hCaptcha. Desktop má 18 CPU náhledů v EN/CS, včetně mapy a databáze, bez spuštění OS okna nebo synchronizace. Tyto snímky neověřují klikání, scrollování ani skutečný automatický start s WoW.
