# Evertally — návod 0.4.0

Zdrojová verze 0.4.0, 9. 11. 2026. Addon sbírá vlastní herní události, nainstalovaná Windows aplikace je čte a volitelně synchronizuje; web zobrazuje povolené záznamy a referenční databázi. Jazyk EN/CS se vybírá samostatně v každé části.

## Co můžeš snadno vyzkoušet sám

1. Po instalaci nových souborů addonu napiš ve hře `/reload`, potom `/etally`. Otevře se okno Evertally; v Nastavení můžeš zapnout mapu a minimapu. Pokud už jsi je zapnul, nepřepínej je znovu.
2. Novou Windows verzi nainstaluješ souborem `releases/EvertallySetup.exe`; před instalací sám zavři běžící Evertally. Otevři ji přes Start a podívej se na **Mapu světa** a **Databázi a návody**.
3. Webovou mapu otevři na `https://evertally.afstudio.dev/#atlas`. Panel **Trasy a skupiny** má samostatné záložky Moje trasa, Skupiny a Cech. Pro zobrazení vlastních dat je potřeba přihlášení a spárovaná aplikace; hra ukládá změny při `/reload` nebo odhlášení.
4. Záznam dungeonu vyzkoušíš až skutečným průchodem; sdílení polohy a skupinové funkce vyžadují dalšího člověka, který má addon a sdílení povolí. Sám tím správnost přenosu neověříš.

Pozvánku `/invite`, `/script` ani diagnostické příkazy pro tyto základní kroky nepotřebuješ. Automatické testy a náhledy nejsou potvrzením, že vše funguje ve hře nebo že jsou všechny slíbené funkce hotové.

## Instalace aplikace

1. Spusť `releases/EvertallySetup.exe`. Instaluje se pro aktuálního uživatele do `%LOCALAPPDATA%\Programs\Evertally`, bez administrátorského účtu.
2. Ponech **Spouštět Evertally automaticky s World of Warcraft Forever**, pokud tuto funkci chceš používat. Zástupce na ploše je volitelný; položka Start a odinstalace jsou součástí.
3. Pro instalaci addonů zaškrtni příslušnou volbu a vyber složku s `Wow.exe` nebo rodiče obsahujícího `_forever_`. Předchozí soubory Evertally se zálohují; SavedVariables se nemění.
4. WoW restartuj sám, aby načetlo nové soubory v `.toc`. Aplikaci otevřeš přes Start → Evertally.

Instalátor obsahuje GUI, `EvertallyBackground.exe`, datové podklady a všechny tři addony. Samostatné EXE a ZIP jsou pomocné varianty; hlavní cesta je instalátor. Existující `config.json` se aktualizací nepřepisuje. Starší localhost přepni v Settings na `https://evertally.afstudio.dev`. Odinstalace je v nastavení Windows → Aplikace nebo nabídce Start. Vlastní herní historie se při ní nemaže.

Aktualizace 10. 11. 2026: instalátor i webové balíčky jsou nově sestavené, tři herní addony jsou nainstalované a web používá migrace 0003–0004. Otevřená desktopová aplikace se sama nepřepsala; novou verzi je nutné nainstalovat ze souboru `releases/EvertallySetup.exe`. Herní ověření šipky a skutečného spouštění s WoW zatím chybí.

## Spouštění s WoW

Per-user Windows Run spouští malý `EvertallyBackground.exe`. Každé čtyři sekundy kontroluje seznam procesů a cestu WoW Forever. Při novém procesu hry jednou otevře aplikaci minimalizovaně a bez aktivace. Nečte paměť hry, nevkládá DLL a neovládá její UI.

Když okno ručně zavřeš, stejná běžící hra ho znovu neotevře. Nový start hry může aplikaci spustit znovu. Vypnutí volby v Settings odstraní Run registraci a zastaví watcher. Samotný build nic nespouští a neprokazuje reálné chování při hře.

## Addon a ukládání

Složky jsou `Interface\AddOns\Evertally` a `Interface\AddOns\Evertally_Export`. Samostatnou instalaci zajišťuje `Install-Addon.ps1` se zálohou a kontrolou hashů; alternativou je `releases/Evertally.zip` rozbalený do AddOns.

- `/etally`: devět karet — přehled, výpravy, atlas, žebříčky, peers, komunita, profese, místa, nastavení.
- `/etally web on` / `web off`: příprava webového exportu, výchozí stav vypnuto.
- `/etally share on` / `share off`: samostatné sdílení ve skupině/guildě.
- `/etally finish`: ruční konec návštěvy, nikoli ověřený rychlostní rekord.
- `/etally diag`: diagnostika; `/etally export`: JSON pro ruční import.
- `/etally terrain`: aktuální navigační cíl předá volitelnému addonu Shortest Path Forever, který může vést cestu po terénu. Nejdřív zapni mapu Evertally a nastav cíl. Předání může nahradit předchozí cestu v Shortest Path Forever; pohybující se cíl předá jako aktuální bod, nikoli živě sledovanou trasu. Bez něj zůstává šipka Evertally vzdušnou čarou. Funkce zatím nebyla ověřena ve hře.

Detail výpravy ukazuje dostupné boss časy/splity, obtížnost, vlastní úmrtí, skupinu a časové hranice. Profese a Místa obsahují recepty, cooldowny a navštívené oblasti. Neznámý údaj není nula.

Hra zapisuje SavedVariables při `/reload`, odhlášení nebo ukončení. Desktop nevidí živé změny před tímto zápisem. Vlastní historii čte z `Evertally.lua`; na web tento soubor neposílá. Pro přenos používá pouze schválený `Evertally_Export.lua`.

## Desktop, mapa a databáze

Devět pohledů: Přehled, Postavy, Deník výprav, Nasbíraná data, Mapa světa, Databáze a návody, Žebříčky a aktivita, Webová synchronizace, Nastavení. Vlastní uložená historie i nainstalované podklady fungují offline. Komunitní údaje načítá samostatné tlačítko; cache není živý stav serveru.

Web a desktop používají stejné podklady:

| Podklad | Rozsah |
| --- | --- |
| Mapy | 60 skutečných herních podkladů s vazbou na C_Map UIMapID |
| Itemy | 22 881 referenčních záznamů; část základních itemů zatím nemá známou ikonu |
| Questy | 5 232 základních záznamů |
| NPC | 12 078 základních záznamů, u dostupných dat referenční výskyty |
| Instance | 45 dungeonových/raidových záznamů |
| Recepty | 2 339 referenčních receptů |
| Návody | Dva vlastní stručné návody k používání Evertally |

Nejde o knihu raidových strategií ani úplně ověřenou databázi aktuálního buildu. NPC/questy jsou základní řádky QuestieDB pro Forever bez runtime oprav. Desktop načítá stejný vyhledávací index a detaily jako web a na mapě Azerothu při přibližování skládá stejné mapové podklady. Ovládání a vrstvy desktopové mapy zatím nejsou totožné s webem. Zdroje a licence jsou v `THIRD_PARTY.md`.

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

**Veřejný profil a komunitní vrstvy nikdy neukazují přesnou polohu hráče, a živé sledování neexistuje.** `zone.visited` ukládá pouze ID/název oblasti bez x/y. Jedinou výjimkou je dobrovolná **Moje trasa** a **Můj cech** (viz níže), vždy vypnuté, dokud je sám nezapneš. Historické hráčské souřadnice při interakci se odstraňují při zpracování addonu, Rust uploaderu i TypeScript projekce; veřejné API a detaily je nezobrazují. Přesné body jsou pouze NPC s metodou `unit_position` nebo oddělená referenční databáze NPC.

Aktivita oblastí znamená různé přispívající účty se zaznamenanou návštěvou za 24 hodin, až od tří účtů na oblast. Veřejný čas návštěvy je hrubý, po dnech. Nejde o online počet hráčů, populaci realmu ani trasu postavy. Profil ukazuje navštívené oblasti a omezené výpravy podle viditelnosti a aktivních souhlasů. Profese jsou soukromé pro vlastní účet. Přijatá peer data nikdy nejsou vlastním webovým exportem.

## Moje trasa a cech (dobrovolné, ve výchozím stavu vypnuté)

V addonu (Nastavení → Webový export) jsou dvě nové oblasti. Obě fungují jen při zapnutém webovém exportu a nikdy zpětně.

- **Moje trasa** (`own_track`): addon každé 4 s zjistí polohu postavy a ukládá body do úseků (jedna mapa, nejvýš 100 bodů; stání na místě přidá jen občasný bod). Do lokální historie addonu se nic nepíše, jde rovnou do výstupní fronty. Body se zaokrouhlují na tři desetinná místa mapy. Fronta drží nejnovějších 500 úseků. Hra soubor zapisuje při `/reload` nebo odhlášení, takže web vidí trasu až potom.
- **Můj cech** (`guild_share`, vyžaduje „Moje postava“): addon pošle jméno cechu a hodnost postavy; **guildmaster** (hodnost 0) navíc seznam členů (jméno, hodnost, level, classa), nejvýš jednou týdně.

Na webu (Mapa → vrstva **Moje trasa**) vidíš svoji trasu podle postavy a období (24 h / 7 dní / 30 dní), můžeš ji skrýt vrstvou, ukázat poslední polohu nebo **smazat**. Trasa je soukromá pro tvůj účet a uchovává se **30 dní** (starší body se smažou při dalším nahrání).

Vrstva **Cech** funguje takhle: člen cechu vidí cech až po **potvrzení na mapě** („Připojit a sdílet“) a zvolí, co sdílí: nic, poslední polohu, nebo poslední polohu i trasu za 72 h. Vidí se jen členové, kteří potvrdili stejný cech a jsou v seznamu, který nahrál guildmaster; kdo ve hře z cechu odejde nebo v dalším seznamu chybí, přestane být vidět. Odvolání souhlasu nebo smazání dat sdílení hned ukončí.

Hranice: server **neumí ověřit hodnost v cechu**, protože addon je jediný svědek. Seznam členů proto vlastní první guildmaster, který ho nahraje (další ho nepřepíše), a každý člen na mapě vidí jméno té postavy, než se připojí. Poloha je vždy z posledního `/reload` nebo odhlášení hráče, ne živá.

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
- **Navigace**: `/etally go <jméno | meet | ping>` (jméno stačí začátkem), `/etally stop`, nebo klik v *Lidé → Živě* a v okně srazu (*Navigovat*). Pod minimapou se ukáže **šipka** a text: kam jít, vzdálenost, a pokud je cíl daleko, **kroky cesty** (dojdi k letišti, leť, nalodění, portál ...) z téhož plánovače jako na webu. Plánovač je přenesený do Lua a hlídá ho test: 1 388 cest dává stejný výsledek jako webový. Plán se každých ~8 s počítá znovu od tvé polohy, takže jde za tebou i za pohybujícím se hráčem. Pravé tlačítko na šipku navigaci zruší, tažením ji přesuneš.
- **Na webu**: u člena cechu nebo skupiny s polohou tlačítko **Trasa k tomuto hráči** (vyjde z tvé poslední známé polohy).
- Příkazy pro ladění: `/etally navdebug` vypíše směr, který počítá addon, a směr podle HereBeDragons, aby šlo ve hře ověřit, že šipka míří správně.

**Skutečné trasy po terénu (jen na webu):** plánovač cest na webu kreslí chůzi **po zemi**, ne vzdušnou čarou. Maska průchodnosti (`walk.bin`, 97 KB, vyrobená skriptem `tools/build_walkmask.py` z terénních dat Shortest Path Forever v GatherLite) ví, kde se dá stát (země, voda, zablokováno) v 16yardových buňkách, a vyhledávání cesty (`db/terrain.ts`, A* po buňkách) obchází pohoří a vodu a vede podél řek a pobřeží. Příklad: z Auberdine do Felwoodu je vzdušnou čarou asi 1 950 yardů, po zemi asi 9 600, protože mezi nimi stojí hory (obrázek s červenou cestou a tenkou bílou přímkou jsem si vykreslil z masky). Masku stáhne stránka jen při prvním plánování a hledání trvá medián asi 8 ms (nejdéle 175 ms).

- **Čas chůze mezi pevnými místy** zůstává upečený (SPF), mění se jen čára. **Čas z a do tvých vlastních bodů** je délka cesty po masce krát **1,18**, což je naměřený medián poměru upečených cest k cestám po masce (`GROUND_FACTOR`, hlídá ho test). Upečené cesty SPF vznikly hierarchickým hledáním, které nenachází vždy nejkratší cestu, takže 1,18 je **kalibrace**, ne tvrzení, že skutečná cesta je o 18 % delší. Je to pořád odhad a jako odhad je označen.
- **Změřeno:** všech 2 781 upečených cest mezi pevnými místy na masce existuje (žádná chybějící); délka po masce je medián 85 % upečené délky (10. percentil 62 %, 90. percentil 95 %); vzdušná čára je medián jen 66 %.
- **Co maska neumí:** neví o útesech mezi sousedními buňkami (stupně v datech SPF) ani o patrech budov a tunelů, takže cesta může být místy optimistická. Druhy chůze (plavání, jízda) nerozlišuje; voda se v hledání cení třikrát.
- **Zůstává vzdušnou čarou:** šipka ve hře. Ukazuje směr k dalšímu kroku, ne po cestě; kroky cesty z plánovače jsou stejné jako na webu, ale bez terénu. Maska má 97 KB, takže by do addonu šla, ale potřebuje rozbalení zlib a A* v Lua po 1 až 3 milionech buněk. Do addonu jsem ji zatím nedal.

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

## Skutečný stav vydání

Web 0.4.0 je veřejně nasazený na `https://evertally.afstudio.dev` (Cloudflare verze `7177013e-11b0-461b-9838-86d61c821a91`). HTTPS kontrola potvrdila status 0.4.0, `auth.discord=true`, `devLogin=false`, 60 map a katalogy. Hashe staženého addonu, aplikace a instalátoru souhlasí s manifesty. Veřejná headless kontrola prošla 11 scénáři: mapa/zoom/NPC piny, aktivita bez hráčských GPS bodů, katalogové ikony a přesné hledání, questy, dungeonový loot, návody, mobilní zobrazení a žádné chyby stránky.

Aplikace je skutečně nainstalovaná v `C:\Users\domin\AppData\Local\Programs\Evertally`, včetně watcheru, resources a odinstalace. Hash GUI a watcheru byl ověřený. Windows Run `EvertallySync` míří na nainstalovaný `EvertallyBackground.exe`; watcher běží bez viditelného okna. Reálné spuštění aplikace při startu WoW zatím nebylo ověřené, protože hra při této kontrole neběžela. Existující vývojová adresa byla přepnutá na veřejný server se soukromou zálohou konfigurace. Aktuální důkazy jsou v `releases/verification.json`, `releases/public-verification.json` a manifestech.

Addon 0.4.0 je souborově nainstalovaný a ověřený hash kontrolou; záloha je `backups/20261109-231144-927`. Nové UI nebylo vizuálně ověřené ve hře. 34 Lua replay testů a technické kontroly nenahrazují skutečné bossové události, přenos mezi hráči nebo ovládání aplikace.

Discord metadata, ikona, callbacky a serverové klíče jsou nastavené; začátek OAuth je ověřený. Celý login zůstává neověřený kvůli hCaptcha. Desktop má 18 CPU náhledů v EN/CS, včetně mapy a databáze, bez spuštění OS okna nebo synchronizace. Tyto snímky neověřují klikání, scrollování ani skutečný automatický start s WoW.
