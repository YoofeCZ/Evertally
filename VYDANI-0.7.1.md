# Evertally 0.7.1 — dokončení rozpracovaného průvodce a rozhraní

12. listopadu 2026. Navazuje na lokální práci na databázi, Dungeon Journalu, receptech, návodech a talentech. Verze 0.7.0 je již distribuovaná; nové soubory mají vlastní číslo 0.7.1.

## Co je v této distribuci

- Databáze questů, NPC, předmětů a objektů má proklikatelný detail. Deník otevře odpovídající záznam. Databázový obsah používá nainstalovanou QuestieDB.
- Dungeon Journal má karty instancí, záložky Bossové / Questy / Mapa, loot s ikonami a odměny questů. Rozšířená data a mapy pater čte z volitelného ForeverDungeonJournal; bez něj přizná chybějící obsah.
- Samostatné stránky Recepty, Talenty a Návody. Databáze a průvodce fungují bez zapnuté mapy a bez OpenMap. OpenMap je potřeba pro mapové vrstvy a minimapu.
- Společné karty, tlačítka, filtry i samostatná okna detailu, souhlasu a výbavy používají kámen, bronz a zlaté titulky. České fonty zůstávají zachované. Starší stránky si ponechávají své rozložení.
- Opravené menu při nízkém okně: všech 16 stránek je přístupných kolečkem i šipkami, vybraná položka se dosune do viditelné oblasti. Zápatí není součástí posouvaného seznamu.
- Navigace používá postupně počítanou cestu po terénní masce. Během výpočtu a mimo pokrytí označí přímý směr; maska nezaručuje průchod každou skutečnou překážkou.
- Oprava opakovaných chybných whisperů: validace názvu, realmu a online stavu, zastavení po přesné chybě serveru a nová kontrola již čekající zprávy těsně před odesláním. Ručně vyžádané sociální zprávy zůstávají funkční.
- Živý přenos aktuální party a přátel nepotřebuje další uložení hry. Vzájemná parta se pozná bez webové pozvánky; přátelé potřebují zapnuté sdílení přátelům u obou hráčů. Oba potřebují addon a spárovaný běžící most. Existující volby sdílení se aktualizací nemění.
- Windows aplikace zůstává mostem vedle hodin, s párováním, Web sync a nastavením spojení. Datová značka v4 má nejvýše 128 × 6 fyzických pixelů; potřebuje viditelný nezakrytý roh hry.

## Ověření

- 281 Lua testů prošlo; zahrnují nové stránky, zúžené menu i skutečnou frontu odložených whisperů. Běží na napodobenině API, nikoli ve hře.
- Web: 186 testů, TypeScript a ESLint. Lokální HTTP ověření živé party/přátel a 31 kontrol sdílení prošly nad zkušebními účty.
- Most: 55 Rust testů synchronizace, 5 testů nastavení a 2 testy spouštění; Clippy bez varování. Izolovaný test instalátoru ověřil korektní ukončení vlastního mostu, aktualizaci zamčeného souboru a zálohy všech tří addonů.
- Oddělený headless Edge: pohyb bez reloadu, automatické zobrazení přítele/party při vypnuté obecné vrstvě hráčů, přiblížení na hráče, odchod, expirace, sbalení a přesun/reset panelu; bez JavaScriptových chyb.
- Rozložení hlavního okna, kompaktního menu, nastavení a prohlížeče výbavy bylo vykreslené přes lokální model rámů. Náhradní fonty a textury v těchto náhledech neprokazují přesný herní vzhled.

Skutečný vzhled a ovládání nových obrazovek, odeznění chyby v herním chatu a přenos mezi dvěma skutečnými herními klienty zůstávají k ověření po restartu WoW. Licence a omezení dat jsou popsané v THIRD_PARTY.md; toto vydání nepřidává cizí české překlady ani neověřené ikony.

## Po instalaci

WoW jednou úplně vypni a znovu spusť, protože přibyly soubory v TOC. `/etally` otevře addon. Pro živé změny pohybu a party pak další `/reload` potřeba není. Druhý hráč potřebuje stejnou aktuální distribuci a své zapnuté sdílení.
