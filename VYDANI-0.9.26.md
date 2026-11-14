# Evertally 0.9.26 (Bridge 0.9.10)

**Lidé ve hře.** Nad seznamem jsou tlačítka kategorií Vše · Evertally · Přátelé · Skupina · Cech s počtem lidí; volba se pamatuje. Kategorie Evertally ukazuje všechny, o kterých addon ví, že Evertally používají: kdo sdílí polohu, koho jsi potkal ve hře za posledních 30 dní a kdo je na veřejném žebříčku webu (data, která most zapisuje do `RankingData.lua`). Hráči z jiného realmu se stejným jménem jsou dvě různé osoby. Hráč, který si veřejný žebříček nezapnul a ve hře se s tebou nepotkal, zůstává skrytý.

**Jeden hráč jen jednou.** WoW Forever posílá jméno odesílatele addonové zprávy jako `Jméno Realm` (s mezerou, změřeno v SavedVariables), skupina ho zná jako `Jméno`. Stránka Lidé teď obojí spojí; dřív se tentýž hráč ukázal dvakrát.

**Žebříček ve hře** načítá i veřejný žebříček webu. Z webu přichází jen souhrn (úroveň, počet dokončených běhů, pořadí), takže tito hráči se řadí v kategoriích Dokončení a Úroveň, ne v časech ani DPS/HPS. Kdo je místně i na webu, je v seznamu jednou.

**Web.** Kategorie žebříčku jsou tlačítka: Úroveň · Dokončení · Nejrychlejší časy · Instance · DPS · HPS. Nová kategorie Instance ukazuje každý dungeon a raid s rekordem; kliknutím se otevře žebříček časů dané instance. Dungeony / Raidy se přepínají tlačítky. Odkaz „Všechny instance“ na Přehledu vede na novou kategorii.

**Bridge 0.9.10.** Poslední stránka instalátoru otevře okno Evertally s návodem „Jak začít“ (spárovat počítač, ve hře zapnout „Připravovat vlastní data pro web“ a „Ukázat mé postavy ve veřejném žebříčku na webu“, hrát) a spolu s ním spustí most. Dřív se most jen tiše schoval k hodinám a noví hráči se nedozvěděli, že mají párovat.

Ověřeno: Lua testy (530 a nové testy kategorií, webového žebříčku a jmen „Jméno Realm“), web 247 testů, `tsc` a `eslint` čisté, Rust `cargo test` a `clippy -D warnings`, náhled okna mostu vykreslený do PNG v češtině i angličtině, webový žebříček proklikaný v prohlížeči. **Neověřeno ve hře:** vzhled tlačítek a nových seznamů. Z 0.9.25 stačí `/reload` (nepřibyly soubory); most addon aktualizuje sám.
