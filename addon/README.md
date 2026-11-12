# Evertally 0.7.0

Samostatný addon pro WoW Forever, interface 16001. Základní deník, přehled, žebříčky a sběr nevyžadují Questie, QuestMaster ani web. Rozšířené hledání NPC/questů/itemů na stránce Svět používá volitelně nainstalovanou QuestieDB. Nové UI má měnitelnou velikost, boční nabídku a sjednocené stránky. Automatické testy nejsou vizuálním ověřením ve WoW; aktuální důkazy a limity uvádí hlavní NAVOD.md a VYDANI-0.7.0.md.

## Instalace

Windows most instaluje `releases/EvertallySetup.exe`; může volitelně nainstalovat také všechny tři addony a zálohovat předchozí verzi. Samostatně lze použít `Install-Addon.ps1` nebo z balíčku zkopírovat tři adresáře vedle sebe:

```text
World of Warcraft/_forever_/Interface/AddOns/
  Evertally/
  Evertally_Export/
  Evertally_Map/
```

Při instalaci/aktualizaci hru sám úplně vypni a spusť, aby načetla nové soubory `.toc`. Pomocný `Evertally_Export` vytváří samostatný exportní soubor; samotný addon může běžet bez něj. Mapový modul se načítá po zapnutí mapy a minimapy; obsahuje i Sbírání a Dungeony/Raidy.

## Ovládání

| Příkaz | Chování |
| --- | --- |
| `/etally` | Otevře devět karet: přehled, běhy, atlas, žebříček, peers, komunitu, profese, místa a nastavení |
| `/etally share on` | Zapne dobrovolné ingame sdílení vlastních souhrnů |
| `/etally share off` | Zastaví nové sdílení, zruší čekající data a zařadí revokaci pro dříve povolené příjemce |
| `/etally share` | Zařadí vlastní aktuální souhrn k odeslání |
| `/etally web on` | Připravuje nové vlastní záznamy pro web; vyžaduje pomocný addon |
| `/etally web off` | Vypne přípravu a vymaže exportní frontu; uloží se po reloadu/odhlášení |
| `/etally export` | Otevře kopírovatelný JSON aktuálně povoleného exportu |
| `/etally finish` | Ručně ukončí návštěvu; nevytvoří automaticky ověřený rekord |
| `/etally diag` | Vypíše verzi klienta a bezpečný přehled diagnostiky |

Jazyk okna je ve výchozím stavu angličtina; tlačítko „English / Čeština“ v okně přepne do češtiny a volba se uloží.

V okně lze zvolit češtinu/angličtinu, skupinu/guildu a webové kategorie. Vlastní font používá vestavěný `Fonts/ARIALN.TTF`.

## Co zaznamenává

- Vlastní postavu a levely.
- Přijetí a odevzdání questů, dostupné XP a peníze.
- NPC při skutečné interakci a oblast; hráčské x/y při interakci se neukládá do nových faktů a z historických projekcí se odstraňuje.
- `zone.visited`: pouze ID a název navštívené oblasti, bez souřadnic hráče.
- Nabídku obchodníka při otevření.
- Vlastní loot podle lokalizovaných self-only hlášení hry, s neznámým zdrojem při nejasnosti.
- Vlastní profesní snapshoty a naučené recepty po otevření profese.
- Výsledek výroby pouze při odpovídající potvrzující crafting události a shodě s receptovým výstupem.
- Dostupné profesní cooldowny.
- Dungeonové a raidové návštěvy, časování, vlastní úmrtí a doložené bossové události.

Sekce Atlas ukazuje vlastní získaná fakta. Žebříček řadí dostupné postavy podle počtu automaticky zaznamenaných dokončení v uložené historii, s rasou/classou a původem údaje. Přehled není úplným serverovým žebříčkem. Ruční dokončení se mezi automatická dokončení nezapočítá.

UI používá ikony class/ras v hlavičce a přehledech. Klikací detail výpravy nabízí dostupné boss časy a splity, obtížnost, vlastní úmrtí, skupinu a časové hranice. Profese mají hledání, recepty a cooldowny. Místa jsou souhrn navštívených oblastí, nikdy hráčské piny nebo živá poloha.

Web má navíc skutečné mapové podklady a oddělený referenční katalog; Windows Bridge je od verze 0.5.0 nemá. Katalogové NPC výskyty nejsou důkazem vlastního pozorování ani součástí hráčského exportu. Aktivita na webu sčítá přispívající účty za 24 hodin až od tří účtů na oblast; nejde o online hráče.

## Dokončení dungeonů

Kandidátní metadata obsahují poslední bossy pro 35 dungeonů/křídel. Dosažení čitelné bossové události se známým jménem nebo skutečně pozorované smrti známého NPC může uzavřít běh jako `last_boss`.

Metadata mají stav **candidate**, nikoli ověřený pravidlový systém. Jde o rozpoznání posledního bosse, ne potvrzení zabití všech povinných bossů. Všechny výsledky proto nesou `rankEligible=false`. NPC ID se nikdy nevydává za encounter ID.

Neznámý dungeon lze ukončit tlačítkem „Potvrdit dokončení (ručně)“; tento výsledek má ruční evidence a zůstává mimo automatický počet dokončení. Další rulesety se mají ověřovat živým herním testem.

Odchod a rychlý návrat do stejného dungeonu zachovává návštěvu; po patnácti minutách mimo instanci se měření uzavře jako přerušené. Neznámý reset nelze zaměnit za jistou novou instanci. Po reloadu se starý běh zachová jako přerušený, aby nevznikl falešně přesný čas.

## Sdílení

Výchozí stav je **ingame vypnuto, web vypnuto**. Zapnuté ingame sdílení posílá vlastní aktuální postavu, nejnovějších pět jejích běhů, počet dokončení její uchované historie a tři poslední světové pozorování. Nevydává historii dalších altů za historii právě hrané postavy.

Transport nyní pokrývá skupinu/raid a volitelně guildu. Battle.net a přímá přátelská synchronizace nejsou v této verzi implementované. Zprávy jsou omezené, dělené a odložené během boje. Odesílání drží rychlost pod limitem klienta (nárazově 8 zpráv, pak 1 za sekundu) a díl odmítnutý kvůli throttlingu zkusí znovu, místo aby se tiše ztratil; skutečný limit Foreveru zatím není změřený. Zprávy nejsou komprimované a jejich parser nespouští kód.

Přijatá data zůstávají v `EvertallyPeersDB` s označením `origin=peer`. Nesdílejí se dál a nejsou zdrojem webového exportu. Peer cache má limit 100 odesílatelů a expiraci 30 dní.

## Export na web

Export začíná až zapnutím. Dřívější historie se automaticky neposílá. Změna povolených kategorií vytvoří novou epoch souhlasu a novou frontu. Běžný reload zachovává již připravenou platnou frontu.

Hra uloží samostatný soubor:

```text
_forever_/WTF/Account/<účet>/SavedVariables/Evertally_Export.lua
```

Jediná proměnná v tomto souboru je `EvertallyExportDB`. Neposílej webu hlavní `Evertally.lua`, `EvertallyPeersDB` ani celou WTF složku.

Soubor po každém zápisu může přenést spárovaná nativní aplikace Evertally (viz `../desktop/README.md`); bez ní jde soubor nahrát ručně na webu. Samotné zapnutí exportu nic na internet neposílá. Webové přihlášení, grant, párování a samotný upload jsou oddělené kroky. Vypnutí pouze uvnitř běžící hry aplikace uvidí až po zápisu souboru; pro okamžité odpojení odvolej grant také na webu. Veřejný web běží na `https://evertally.afstudio.dev`; serverové klíče Discordu jsou nastavené, ověření celého přihlášení ještě čeká na přihlášení uživatele do Discordu.

Bez scope `own_character` se světová/profesní pozorování připravují bez identity postavy. Vlastní běhy používají oddělený lokální pseudonym s classou, rasou a levelem, bez jména a realmu. Profesní data na webu zůstávají dostupná pouze vlastnímu přihlášenému účtu.

## Komunitní import z webu

Na webu v Atlasu zvol Copy for addon / Kopírovat pro addon nebo si stáhni komunitní JSON. Ve hře otevři `/etally` → Community / Komunita → Import data / Načíst data, vlož obsah a potvrď. Seznam podporuje filtr questů, NPC a předmětů a hledání podle názvu či ID; po načtení funguje offline.

Importer přijímá pouze formát `evertally-community`, nejvýše 48 KiB a 150 anonymních entit. Platnost vzorku je nejvýše sedm dní; čas, počty a zastaralost jsou viditelné v rozhraní. Nepoužívá `loadstring` ani nespouští vložený kód. Chyba zachová předchozí cache.

Data jsou pouze v `EvertallyPeersDB.community`, oddělená od vlastních záznamů i ingame peers. Nezapočítají se jako vlastní pozorování, nesdílejí se dál a nevstoupí do webového exportu. Balíček neobsahuje jména postav ani běhy. Přesný pin NPC vyžaduje pozorovanou jednotkovou polohu; místo hráčovy interakce se za něj nevydává.

## Limity této verze

- Dungeonové rulesety a skutečná dostupnost bossových událostí zatím nebyly potvrzeny živým průchodem; starší herní snímky dokládají sběr questů, NPC a lootu.
- Nejde o bojový poradní addon, anticheat ani úplnou serverovou databázi.
- Přesný full clear, Battle.net synchronizace, ekonomické snapshoty a historie gearu/talentů zatím nejsou implementované. Ruční import komunitního webového balíčku je součástí 0.3.0; nepřináší přímé internetové spojení do addonu.
- Lokalizované bossové jméno bez čitelného NPC ID nemusí odpovídat anglickým candidate metadatům.
- Quest abandon nelze potvrdit jen z obecné události odstranění questu; aktuální případná hook cesta je omezená dostupným API.
- Vlastní události mají měkký limit 5000 a export 4000. Po jeho dosažení se zastaví jen opakované snímky (NPC, obchodníci, profese, cooldowny, postava); výsledky běhů, questy a loot se zapisují dál až do tvrdého stropu 6000 / 4800. Běhy mají limit 1000. Při dosažení limitu se objeví varování; nic starého se automaticky nepřemazává.
- Profesní snapshot se zapíše jen při změně dovedností nebo receptů, ne při každém obnovení okna profese.
- UI je vytvořené pomocí nativních framů; mock test není důkaz správného vykreslení v klientu.

## Testy

```powershell
& 'C:\Users\domin\AppData\Local\Programs\Python\Python312\python.exe' 'D:\addon\tests\lua\test_addon.py'
```

Runner používá `lupa.lua51` a umí sáhnout do již existujícího lokálního vendor adresáře. Testy nenačítají skutečné uložené profily hráče a nespouštějí hru. Syntetický export pro integrační testy vzniká v `tests/lua/fixtures` a je výslovně označený jako fiktivní.
