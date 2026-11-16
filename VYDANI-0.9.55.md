# Evertally 0.9.55 (addon) + web

## Addon 0.9.55

### Spellbook: „Co se můžu naučit?“
- Nová **záložka ve spellbooku** (vpravo od záložek knihy; s nainstalovaným What's Training? za jeho záložkou). Otevře stránku přes knihu:
  - **Dostupné teď** (s cenou), **Brzy** (do dvou úrovní), **Zatím nedostupné** (s úrovní, červeně vyšší než tvoje),
  - nahoře **celková cena**, najetím na kouzlo jeho tooltip a chybějící předpoklad.
- Data jsou z vlastního modelu Evertally (Co se naučit), ne z jiného addonu. Klik na jinou záložku knihy, hledání nebo zavření knihy stránku schová.

### Talenty: Profily a Import / Export v okně talentů
- V okně talentů jsou dvě tlačítka vlevo dole:
  - **Profily**: uložené profily této třídy (klik = nastavit v okně, pravý klik = smazat), **Uložit současné talenty jako profil**, otevření plánovače Evertally.
  - **Import / Export**: kód ETB1 (stejný jako v plánovači), **Exportovat současné talenty**, **Importovat a nastavit**.
- Nastavení profilu talenty **jen připraví** (vrátí body a nakoupí je řadu po řadě); naučí se až tlačítkem okna **Apply Changes**. Zavření okna bez něj nechá talenty jak byly. V boji nejde.

### Looking For Group: Dungeon Journal
- Pod kategoriemi (Quests & Zones, Battlegrounds, Custom) je **Dungeon Journal** se stejným vzhledem; otevře Dungeon Journal Evertally.

### Dungeon Journal: návody, taktiky, podrobné questy
- Nová záložka **Návod** (dungeon se na ní otevírá): **Přehled** (popis, postup, nepřátelé, co čistit, tipy), **Tank**, **Healer**, **DPS**, **Povolání** (tvoje povolání první; tipy podle nepřátel v dungeonu: Shackle na nemrtvé, Banish na elementály, kdo čistí jed/nemoc/kletby…).
- U bosse je před lootem **Taktika** (u některých i rady pro role) a popis z DungeonJournal, je-li.
  - **26 dungeonů z Classicu**: taktiky napsané podle Classicu s poznámkou, že je Forever mohl změnit.
  - **9 nových dungeonů Forever**: taktiky nikde nevyšly; obecné rady z dungeonů stejné úrovně a druhu, u bossů z Dalaranu a Drowned City rady podle popisů v DungeonJournal, a výzva poslat taktiku na **dominik.mracek@afstudio.dev**.
  - Taktiku má 208 z 247 bossů (bez trash a rare); zbylých 39 jsou noví bossové Forever s obecnou radou.
- Quest: **Pozor** (varování), **Poznámka**, **Jen pro povolání**, **začíná uvnitř dungeonu**, **začíná předmětem** a **Nejdřív splň** (předchozí questy) z dat DungeonJournal.

### Pochlubit se
- Lišta **„Pochlubit se?“** už sama nezmizí po 25 s: zůstane, dokud nedáš křížek, Říct do /say, Do guildy nebo Už nenabízet.

Nové soubory v TOC (Evertally i Evertally - Map): po aktualizaci **restart hry**.

## Web: časová osa Kroniky
- Na ose jsou ve výchozím stavu jen **questy, souboje, smrti, dungeony a raidy, lety a levely**. Skoky, kouzla, nasedání a aury jdou zapnout ve filtru.
- **Souboje do minuty od sebe jsou jeden blok** (v pruhu soubojů s počtem a jmény, klik otevře první); jejich značky na ose se ukážou jednou.

## Co je ověřené a co ne

| | Stav |
|---|---|
| Lua testy, celá sada | 761 prošlo (po opravě překrývání textu taktiky v úzkém okně) |
| Jména 35 dungeonů a všech bossů s taktikou proti datům DungeonJournal | sedí (skript) |
| Web: typy, 343 testů, náhled časové osy na demo nahrávce | prošlo |
| Spellbook, okno talentů, LFG ve hře | **neověřeno ve hře**; napojení podle kódu WhatsTraining, QuestMaster, ForeverDungeonJournal a Blizzard_GroupFinder_VanillaStyle |
| Nastavení profilu talentů (C_Traits.PurchaseRank) | **neověřeno ve hře**: API je ve Forever deklarované, ale nevím, jestli okno talentů Forever ukáže připravené body a jestli je Apply Changes uloží |
| Taktiky klasických bossů | podle Classicu, **ne ověřené ve Forever** |
