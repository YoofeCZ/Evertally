# Plán realizace a ověření

Verze 1.0 • 9. listopadu 2026

Tento plán určuje pořadí realizace kompletního produktu. Není potvrzením, že jsou uvedené funkce hotové nebo že konkrétní API bylo otestováno ve hře.

## 1. Pořadí vývoje

### Etapa 0 — ověřit sběr v aktuálním klientu

**Výstup:** malý neveřejný diagnostický addon, matice schopností podle klienta a kontextu, očištěné replay fixtures a první dva validované dungeonové rulesety.

Ověřit přímo ve hře:

- Identitu hry, build, interface, rasu/classu a lokální identitu postavy.
- Quest acceptance/turn-in, odměny, opakovatelný quest a opuštění.
- NPC interakci a přesnost vlastních souřadnic venku, v budově a v instanci.
- Loot s jedním zdrojem, area loot, prázdnou mrtvolu a opakované otevření stejného lootu.
- Vlastní profesní knihu, linknutou cizí knihu, načtení receptů a potvrzený craft.
- Vstup do instance, první použitelný start měření, boss kill, encounter end, reset a odchod.
- Pozorování celé sestavy včetně levelů a změn členů.
- Ingame přenos mimo boj, blokaci/odložení v boji a chování Battle.net transportu.
- Zápis vlastního SavedVariables po `/reload`, logoutu, korektním ukončení a pádu.
- Dostupnost čitelných souhrnů damage metru po boji, bez závislosti základního produktu na této funkci.

**Podmínka pokračování:** víme, které události opravdu dorazí, co se v nich může zpracovat a které údaje chybí. Pokud nelze doložit přesný začátek nebo čerstvost instance, první vydání nabídne osobní měření s pravdivým označením; hlavní soutěžní žebříček se pro daný ruleset ještě nezapne.

### Etapa 1 — samostatný užitečný addon

**Výstup:** instalovatelný addon ZIP a stručný návod.

- Vlastní přehled postav, historie návštěv, dungeonové pokusy a raidová setkání.
- Časovač, mezičasy pro podporované rulesety a počty zaznamenaných dokončení.
- První sběrače questů, NPC, lootu a profesí; přehled pozorovaných herních faktů.
- Základní atlas a vyhledávání s původem každého údaje.
- Nastavení sběru, záloha, limity historie a diagnostika.
- Česká a anglická základní lokalizace; čeština v nadpisech, tooltipech i vstupních polích.
- Web vypnutý, bez vynuceného účtu či externího procesu.

**Podmínka dokončení:** addon samostatně přežije celý večer běžného hraní, reload a další přihlášení, zachová vlastní historii a nezpůsobuje Lua chyby v ověřených scénářích.

### Etapa 2 — sdílení a porovnávání ve hře

**Výstup:** skutečně otestovaná výměna mezi nejméně dvěma nezávislými klienty.

- Přepínače příjemců a vysvětlení sdílených polí.
- Výměna vlastních výsledků a vybraných herních faktů.
- Oddělená peer cache, expirace, aktualizace a žádný automatický osobní relay.
- Ingame žebříčky s viditelným vzorkem, pravidly a stářím dat.
- Fronta s limity a pozastavením podle omezení transportu.
- Kontrola duplicit, protokolu a škodlivých payloadů.

**Podmínka dokončení:** dva klienti mohou sdílet podporovaný běh, třetí člen bez addonu normálně hraje; odmítnutí sdílení funguje a chybějící peer data se nevydávají za nulové výsledky.

### Etapa 3 — dobrovolný web

**Výstup:** provozuschopná testovací webová verze a server; zveřejnění až na zvoleném prostředí.

- Veřejné stránky atlasu a pravidel bez oprávnění k souborům.
- Účet, správa postav a oddělení soukromé historie od veřejného profilu.
- Výběr exportního souboru, náhled, scoped souhlas a idempotentní upload.
- Volitelný folder/file polling v podporovaných prohlížečích.
- Profily, detail běhu a první žebříčky s filtry rasa/classa/level/ruleset/období.
- Revokace grantů, skrytí profilů, mazání a přepočet projekcí.
- Omezený bezpečný datový import zpět do addonu.

**Podmínka dokončení:** přenos je otestovaný z vlastního herního zápisu až do webového výsledku a zpět do přehledu addonu; uživatel bez webového souhlasu zůstane plně použitelný ve hře.

### Etapa 4 — první veřejné vydání

Spojí etapy 1–3. Konečný balíček musí fungovat i při vypnutém API serveru. Veřejně se označí rozsah ověřených dungeonů a datových kategorií.

Povinné výstupy:

1. Addon ZIP, manifest verze a checksum distribuovaného souboru.
2. Web s importem, profily, atlasem a vymezenými žebříčky.
3. Srozumitelný onboarding pro ingame režim i webový režim.
4. Metodika měření a sběru, nastavení souhlasů a informace o datech.
5. Evidence technických a skutečných herních kontrol.
6. Ověřená obnova databáze a postup rollbacku addonu/serveru.
7. Veřejný seznam známých omezení bez tvrzení o úplném pokrytí hry.

### Etapa 5 — celý datový atlas

- Další dungeony a křídla, raidové rulesety a guildovní přehledy.
- Mapové vrstvy, varianty NPC, obchodníci a trenéři.
- Úplnější questové vztahy a podmínky přístupnosti.
- Doložené lootové příležitosti, konflikty a četnosti s definovaným vzorkem.
- Recepty, výroba, cooldowny, řemeslníci a volitelné cenové zdroje.
- Ekonomika, cestování, gathering, fishing a další nezávislé moduly.
- Později volitelný uploader a očištěné logové importy, pokud odstraní skutečné překážky uživatelů.

Nový modul nesmí znefunkčnit základní lokální režim.

## 2. Akceptační scénáře

### Samostatnost a sdílení

| ID | Scénář | Požadovaný výsledek |
| --- | --- | --- |
| A01 | Hráč odmítne web a nemá žádný účet | Vlastní sběr, atlas, timer a historie fungují |
| A02 | Server je nedostupný celý večer | Addon pokračuje; vlastní výsledky se neztratí |
| A03 | Hráč zakáže i ingame sdílení | Nové zprávy s vlastními daty se neposílají; historie zůstane |
| A04 | Přítel není online | Jeho poslední přijaté údaje mají stáří; nevznikne falešný nový stav |
| A05 | Jeden člen skupiny nemá addon | Skupina funguje; nepozorované metriky zůstanou neznámé |
| A06 | Zprávy přijdou v nesprávném pořadí, duplicitně nebo neúplně | Bez pádu, bez násobení výsledků, timeout neúplných přenosů |
| A07 | Klienti mají jiné verze protokolu | Vyjednají podporovanou verzi nebo bezpečně odmítnou přenos |
| A08 | Příjemce podstrčí payload označený jako vlastní | V přijaté cestě vždy peer cache; automatický web export jej odmítne |

### Webové propojení

| ID | Scénář | Požadovaný výsledek |
| --- | --- | --- |
| W01 | Hráč otevře veřejný web | Bez file pickeru a bez tichého čtení místních souborů |
| W02 | Povolí čtení souboru, ale nepotvrdí přenos | Data se zpracují jen lokálně pro náhled; žádný upload herních payloadů |
| W03 | Povolí jen komunitní světová fakta | Osobní historie, identita postavy a peer cache nejsou v requestu ani serverové databázi |
| W04 | Povolí vlastní běhy, profil ponechá soukromý | Dostupná soukromá historie; veřejná jmenná položka nevznikne |
| W05 | Vybere konkrétní veřejnou postavu | Publikují se jen zvolená pole dané postavy |
| W06 | Odešle stejný soubor třikrát | Tytéž eventy se započtou jednou |
| W07 | Hra právě zapisuje soubor | Neúplný stav se neimportuje; použije se poslední platný a retry |
| W08 | Soubor obsahuje Lua funkci nebo útok přes klíče | Nic se nespustí; parser vstup odmítne s vysvětlením |
| W09 | Firefox/Safari nebo odmítnutý folder picker | Funguje ruční import připraveného souboru/kódu |
| W10 | Prohlížeč se zavře nebo usne | Žádný slib nepřetržitého přenosu; po návratu idempotentní navázání |
| W11 | Hráč revokuje webový grant a obnoví starý exportní soubor | Server odmítne starý grant/epoch |
| W12 | Hráč vypne web jen v běžící hře | Nová exportní příprava se zastaví; UI pravdivě vysvětlí starý diskový snapshot a webové okamžité vypnutí |
| W13 | Hráč později znovu povolí přenos | Nový grant, minulá nepovolená historie se neodešle bez výběru |
| W14 | Hráč skryje profil a požádá o smazání | Profil zmizí z veřejné projekce; mazání a přepočet mají sledovatelný stav |
| W15 | Spoluhráč zůstal jen ingame | Upload neobsahuje jeho jméno/GUID ani jeho přijatý peer report |
| W16 | Web vrátí neplatný/chybně velký datový kód | Addon jej bezpečně odmítne bez vykonání kódu |

### Dungeony, raidy a žebříčky

| ID | Scénář | Požadovaný výsledek |
| --- | --- | --- |
| R01 | Kompletní podporovaný dungeon bez přerušení | Jedna návštěva, jeden pokus a podle důkazů jedno dokončení |
| R02 | Dorazí `BOSS_KILL` i `ENCOUNTER_END` pro stejný kill | Jeden boss výsledek |
| R03 | Skupina zabije posledního bosse a přeskočí povinného | Last-boss completion; žádný full-clear rekord |
| R04 | Hráč vstoupí do rozběhnutého dungeonu | `late_join`, žádný falešný celkový čas od jeho vstupu |
| R05 | Hráč zemře, jde ven a vrátí se | Čas nepauzuje; návrat sám nevytvoří nový pokus |
| R06 | Vznikne skutečná nová instance/reset | Nový pokus při dostatečném doložení, starý zůstane v historii |
| R07 | Proběhne reload nebo odpojení | Kontinuita je doložená, nebo je výsledek označen jako přerušený |
| R08 | Změní se systémové hodiny | Délka z monotónního měření se nezmění na falešný rekord |
| R09 | Skupinou projde postava nad levelovou hranicí | Běh nespadne do hlavní neboostované levelové kategorie |
| R10 | Level některého člena není znám | Neúplná sestava; žádné neodůvodněné potvrzení srovnatelnosti |
| R11 | Pět hráčů odešle stejný skupinový běh | Více reportů, jeden canonical run; nejisté sloučení jde do konfliktu |
| R12 | Stejná skupina projde dungeon dvakrát rychle po sobě | Dva skutečné pokusy se neslijí podle hrubého času |
| R13 | Hráč upraví čas ručně | Ruční záznam se neobjeví mezi automaticky měřenými rekordy |
| R14 | Hráč změní class/spec/gear snapshot po běhu | Historická podoba účasti zůstane zachovaná |
| R15 | Běh se účastní Shaman/Tauren | Objeví se v odpovídajícím filtru účastí, čas je označen jako skupinový |
| R16 | Raid pokračuje další den | Nová session navázaná na známý lockout; nevyrobí se jednodenní rekord celého raidu |
| R17 | Změní se ruleset/patch | Výsledky různých pravidel se oddělí a projekce jsou přepočitatelné |
| R18 | Malý vzorek či absence výsledků | Viditelný počet/žádná data, žádný smyšlený serverový percentil |

### Atlas a profese

| ID | Scénář | Požadovaný výsledek |
| --- | --- | --- |
| D01 | Stejný loot se otevře dvakrát | Nevzniknou dvě nezávislé lootové příležitosti |
| D02 | Area loot má více nejednoznačných zdrojů | Zdroj zůstane nejednoznačný, nedoplní se náhodný NPC |
| D03 | Máme jen pozitivní nálezy itemu | Zobrazí se nálezy bez vymyšleného drop procenta |
| D04 | Pět lidí vidí stejnou mrtvolu | Nepočítá se jako pět nezávislých killů do procent |
| D05 | Souřadnice jsou omezené/chybí | Žádný bod 0,0 a žádné kopírování nepoužitelné hodnoty |
| D06 | Stojíme blízko NPC, známe jen polohu hráče | Bod má označení přibližného místa interakce |
| D07 | Obchodník má vyprodáno nebo snapshot není kompletní | Starší doložený vztah prodeje se automaticky nemaže |
| D08 | Opakovatelný quest byl dokončen vícekrát | Samostatné skutečné výskyty, deduplikované jednotlivé události |
| D09 | Otevře se linknutá cizí profesní kniha | Nezískáme tím vlastní naučené recepty |
| D10 | Zrušený craft nebo opožděné bag události | Žádné fiktivní potvrzení výroby z pouhého stisku tlačítka |
| D11 | Cooldown snapshot je starý | Odpočet má stáří a pochybný stav; netvrdí čerstvé ověření |
| D12 | Aukce zmizí | Není automaticky označená jako prodej |
| D13 | Český nadpis, tooltip a jméno s diakritikou | Čitelné znaky bez čtverečků a bez poškozeného UTF-8 uppercase |

## 3. Testovací vrstvy

1. **Deterministické replay scénáře:** změny stavového automatu, pořadí událostí, duplikáty, časové mezery a policy filtry.
2. **Parser a datové kontrakty:** skutečné serializer fixtures, Unicode, limity, poškození a pokusy o spuštění kódu.
3. **Backend integrace:** granty, idempotence, autorizace, deduplikace, projekce a mazání nad testovací databází.
4. **Prohlížeč:** čtení souboru, odvolání oprávnění, upload, retry, zavřená/uspaná stránka a ruční fallback.
5. **Skutečný WoW klient:** herní sběrače, UI, ochrany API, addonové zprávy a zápis historie.
6. **Více klientů:** skutečný přenos a porovnání výsledků. Simulace dvou procesů tuto kontrolu nenahrazuje.
7. **Pilot s hráči:** běžné používání v několika večerech; zjistit chybné dělení běhů, skutečnou frekvenci importu a nejčastěji otevírané pohledy.

Statické kontroly a replay testy neprokazují vizuální správnost, dostupnost konkrétního eventu ani skutečné sdílení mezi hráči.

## 4. Výkonnostní cíle

Následující hodnoty jsou návrhové cíle k měření, nikoli naměřené výsledky:

| Oblast | Počáteční cíl a metoda |
| --- | --- |
| Sběr | Žádné celosvětové skeny za frame; dávkované eventové zpracování |
| Jedna dávka addonu | Na pilotním PC cílit na p95 do 2 ms a práci rozložit při větším snapshotu |
| Lokální úložiště | Měkký rozpočet 25 MiB serializovaných dat; zobrazená velikost a řízené promazání/archivace |
| Příjem peer zpráv | Omezená fronta, čas i rozbalená velikost; zátěž nesmí blokovat ovládání hry |
| Browser import | Parser ve Workeru, průběh a možnost zrušení; test souborů 1/10/25 MiB |
| API upload | Limitované dávky, rychlé přijetí a asynchronní projekce; sledovat skutečný p95 |
| Veřejný žebříček | Cílit na p95 serverové odpovědi do 500 ms při definované zátěži a datové sadě |
| Paměť | Změřit růst při hodině hraní, 100/1000 bězích a zaplněné peer cache |

Pilotní protokol uvede CPU/RAM, klienta, zapnuté moduly, velikost dat a způsob měření. Věta „lehký addon“ bez těchto podkladů nenahradí měření.

## 5. Retence: výchozí návrh

| Data | Návrh pro první provoz |
| --- | --- |
| Peer cache | 30 dní od posledního přijetí, maximálně 100 vybraných profilů; uživatel může snížit nebo smazat |
| Vlastní detailní běhy | Nejnovějších 1000 v mezích kapacity, celoživotní souhrny zvlášť; upozornění a záloha před archivací |
| Opakované světové vzorky | Lokální agregace shodných pozorování se zachováním nezávislého původu |
| Nepotvrzený webový export | Limitovaný kapacitou; bez tichého mazání důležitých výsledků |
| Serverové vstupní podklady | Počátečně 30 dní pro opravy příjmu; dlouhodobě minimalizované projekce podle účelu |
| Technické logy | Počátečně 14 dní, bez herních payloadů a tokenů |
| Zálohy | Počátečně 30 dní; obnovení musí znovu aplikovat seznam smazání |

Před veřejným spuštěním se limity ověří na reálném objemu. Mazání nesmí zanechat veřejný profil jen proto, že je odvozený z již smazaného importu. Hráč vidí, od kdy je historie úplná a co bylo archivováno.

## 6. Rizika a rozhodovací brány

| Riziko | Reakce |
| --- | --- |
| API nedovolí doložit soutěžní čas | Zachovat osobní návštěvy a historii; rankovanou kategorii zapnout až po doložení signálů |
| Souřadnice či bojové metriky jsou chráněné | Označit nedostupnost; neobcházet ji a neblokovat ostatní moduly |
| Na web přichází málo hráčů | Addon musí mít hodnotu s vlastní historií od první instalace |
| Falešné nebo koluzivní výsledky | Plausibility, provenience a moderace; neslibovat anticheat založený na klientském hashi |
| Nejasná deduplikace běhů/lootu | Konfliktní fronta; nepublikovat z ní jistá globální čísla |
| Starý souhlas v souboru | Serverová revokace, epochy a pravdivá komunikace stavu |
| Příliš široký rozsah | Oddělené moduly, postup podle ověřitelných výstupů etap |
| Existující konkurence | Srovnat konkrétní workflow a kvalitu dat; nepoužívat tvrzení „nic takového neexistuje“ |
| Pád nebo poškození historie | Obnovitelná migrace, bounded zápis, vlastní záloha a ověřená obnova |
| Prohlížeč odmítá nebo ztrácí přístup | Ruční import, žádný povinný uploader ani změna zabezpečení |

## 7. Podmínky pro veřejné spuštění

- Je zvolený provozovatel, hosting, doména a způsob přihlášení.
- Je jasné, co se sbírá, co jde ven a jak se spravují souhlasy a mazání.
- Vlastnictví postav se neprezentuje jako ověřené, pokud k tomu nemáme skutečný důkaz.
- Jsou schválené nejméně dva dungeonové rulesety a popsaná jejich omezení.
- Nefungující/neúplné kategorie jsou označené a neprodukují soutěžní rekordy.
- Je ověřen addon bez webu a bez dalšího programu, i víceklientové ingame sdílení.
- Je provedena skutečná end-to-end cesta addon → web → datový import do addonu.
- Čtení předaného Lua souboru nikdy nespouští Lua kód.
- Začátečník zvládne instalaci a odmítnutí webu bez ztráty základních funkcí.
- Prázdný web, malý vzorek i nedostupný server mají srozumitelné stavy.

## 8. Co zbývá rozhodnout při realizaci

Tyto body nebrání dokončení zadání:

1. Finální název a doména po ověření dostupnosti.
2. Dvě první pilotní instance podle levelu a dostupnosti testovací skupiny.
3. Konkrétní poskytovatel webového přihlášení a dostupnost oficiálního ověření Forever postav.
4. Hosting, region uložení dat, provozní rozpočet a dlouhodobá retence.
5. Které části zveřejnit jako open source a jak licencovat vlastní odvozené datové sady.

První realizační úkol je etapa 0. Začít kreslením kompletního webu s fiktivními žebříčky by neověřilo největší nejistotu projektu: zda umíme sbírat potřebné herní události a měřit srovnatelné běhy.
