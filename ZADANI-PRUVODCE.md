# Zadání: Průvodce v addonu (Databáze, Dungeon Journal) — požadavky a stav

## Aktuální implementace 0.8.0

Questy v Databázi, Deníku a Dungeon Journalu používají společnou plnou pergamenovou kartu podle druhého uživatelského obrázku. Krátký quest se zadáním, odevzdáním, odměnami a XP se vejde do čtecí plochy. Výběrové a pevné odměny se rozlišují pouze při doložených datech; základní XP je označené.

Přehled, Deník, Běhy, Místa, Atlas, Profese, Komunita, Lidé, Žebříček a Nastavení mají přestavěné rozložení. Návody jsou 26 místních kapitol, včetně dvanácti profesí a devíti tříd; výrobní postupy používají skutečné přibalené recepty. Talenty jsou funkční plánovač aktuální třídy s podmínkami, rozpočtem a uloženými buildy. Odkazy na cizí weby již nejsou obsahem těchto stránek.

307 Lua testů prošlo; vykreslené náhledy a kontroly kotvení pokrývají všech 16 stránek a jejich režimy. **Nejde o vizuální přijetí ve hře.** Předchozí záznamy níže popisují historické iterace, nikoli současnou implementaci. Přesný rozsah a omezení: VYDANI-0.8.0.md.

Cíl uživatele (12. 11. 2026, po screenshotech z hry a z webu): **celá databáze je v addonu a vypadá a chová se jako web a jako hotový Dungeon Journal**, ne jako holý seznam s textem. Netýká se jen dungeonů, ale **všeho**: questů, NPC, itemů, objektů. Cíl klient: **Forever 1.60.1** (katalog API: plugin `wow-addon-dev`, build 1.60.1.70862).

Vzory (obrázky od uživatele): web Evertally (Databáze → Dungeony a raidy: banner, štítky, vchod s mapou, bossové s lootem a názvy, questy) a addon DungeonJournal (mřížka karet s bannerem, záložky Mapa / Bossové / Questy, seznam bossů s portréty a úrovní, loot s ikonou, jménem v barvě kvality a slotem, questy s cílem, „Starts at“, „Turn in“, odměnami a XP, mapa s ikonami bossů).

| ID | Požadavek | Stav | Důkaz |
|---|---|---|---|
| G1 | Dungeon Journal: mřížka karet s bannerem (umění z addonu DungeonJournal přes cestu k textuře, nic se nekopíruje), název, úroveň, počet questů | hotovo v kódu, ve hře neověřeno | test + náhled |
| G2 | Detail dungeonu se záložkami **Bossové / Questy / Mapa** | hotovo v kódu, ve hře neověřeno | test + náhled |
| G3 | Bossové: seznam s úrovní, loot jako řádky: ikona, jméno v barvě kvality, slot, tooltip hry | hotovo v kódu, ve hře neověřeno | test + náhled |
| G4 | Questy dungeonu: seznam, detail s cílem, kdo dává, kde odevzdat, odměny (ikony + jména), XP | hotovo v kódu, ve hře neověřeno | test + náhled |
| G5 | Mapa dungeonu s ikonami bossů (data a mapy z addonu DungeonJournal) | hotovo v kódu, ve hře neověřeno | test |
| G6 | Databáze: každý detail (quest, NPC, item, objekt) jako karta se sekcemi a **proklikatelnými řádky** (kdo dává quest → NPC → jeho questy → item → kdo prodává) | hotovo v kódu, ve hře neověřeno | test + náhled |
| G7 | Quest v databázi: cíl, kdo dává, kdo přijímá, oblast, předchozí/další, odměny (ikony) | hotovo v kódu, ve hře neověřeno | test |
| G8 | Řádky seznamů mají ikony (quest „!“, NPC, item s ikonou hry) | hotovo v kódu, ve hře neověřeno | náhled |
| G9 | Záznam v Deníku ukáže, co to byl za quest, a otevře databázi | hotovo (nutno ověřit ve hře) | test |
| G10 | Stránky fungují bez „Mapy a minimapy“ a bez OpenMap | hotovo | test |

**Neověřeno ve hře** (uživatel to musí zkusit): vzhled a rozměry v reálném klientu, výkon, tooltipy, data DungeonJournal. Požadavky G1–G8 se nepovažují za splněné, dokud uživatel neřekne, že vzhled odpovídá vzoru.

**Pravidlo pro příště:** před stavbou obrazovky otevřít vzor (web, hotový addon) a postavit stejnou strukturu; minimální verze „seznam + text“ není hotová práce.

## Navazující opravy 0.7.1 (12. 11. 2026)

- Společné `NativePanel` a `NativeButton` sjednocují karty a ovládací prvky všech stránek; `NativeFrame` se používá také na detail, import komunity, souhlas a prohlížeč výbavy. Má kompatibilní náhradu i pro klienty bez metod backdropu.
- Menu při 700 × 460 už neodřezává spodní stránky. Má vlastní posun kolečkem a šipkami; výběr dosune zvolenou položku. Dvě nové regresní zkoušky procházejí všech 16 stránek a meze posunu.
- Celá aktuální sada má 281 úspěšných Lua testů. Náhledy v `output/ui-preview-final` ukazují rozložení na modelu rámů, nikoli herní textury.
- G11 má nyní společné stavební prvky i dialogy. Rozvržení starších stránek zůstává zachované a skutečný vzhled musí potvrdit klient; vizuální přijetí uživatelem tímto není nahrazené.

## Stav po třetí iteraci (12. 11. 2026, noc)
- **Nový požadavek G11:** celý addon má vypadat jako hotový Dungeon Journal (kámen, bronz, zlaté nadpisy, červená tlačítka), ne jen jedna stránka. **Hotové je jen základ:** paleta (`C` v `UI.lua`), rámec okna (rock + dialogový okraj, `A.NativeFrame`), pruh záhlaví se zlatými linkami, tlačítka (červené primární, bronzové ostatní), zlaté nadpisy stránek. Obsah starších stránek (Přehled, Deník, Běhy, Místa, Atlas, Profese, Komunita, Lidé, Žebříček, Nastavení) má pořád staré rozvržení a vzhled se musí posoudit ve hře. **G11 není splněný**, dokud uživatel nepotvrdí.
- Dungeon Journal je přestavěný podle vzoru (karty s bannery, záložky Bossové / Questy / Mapa, loot s názvy v barvě kvality, mapa s bossy); Databáze má detail s proklikatelnými řádky a ikonami (`GuideKit.lua`).
