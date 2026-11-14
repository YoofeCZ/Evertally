# Evertally 0.9.22 — jmenovky spojenců

- Vlastní vykreslení jména se stínem a bez obrysu. Vedle jména jsou osobní značky a logo uživatelů Evertally.
- Samostatně nastavitelné velikosti jména, značek a loga, měřítko celé jmenovky a šířka lišt.
- Volitelné buffy, debuffy, jejich počty, odpočty a velikost ikon. Volitelné zdraví a kouzlení včetně sesílání, ikony kouzla a času.
- Každý prvek lze vypnout. Vypnutí vlastních jmenovek vrací původní jméno; vlastní vykreslení nezdvojuje původní značky.
- Nastavení → Jmenovky má záložky Jméno a ikony, Buffy/debuffy a Lišty.
- Stejný editor je v sedmém kroku průvodce `/etally setup`. Úpravy se použijí až tlačítkem Dokončit, Přeskočit je zahodí. Průvodce má nyní devět kroků a nabídne se také hráčům, kteří dokončili starší verzi.

Nový soubor je uveden v TOC: po instalaci úplně ukonči a znovu spusť WoW. Samotný `/reload` nestačí. Jmenovky zapni v průvodci nebo v Nastavení → Jmenovky. Zapnutí přepíná jmenovky spojenců do režimu jen se jménem a lze ho provést mimo boj.

Vlastní vykreslení se týká přátelských hráčů, ke kterým klient poskytuje čitelnou a nechráněnou jmenovku. Nepřístupná data ani chráněné jmenovky nenahrazuje. Buffy a kouzlení zobrazí pouze tehdy, když pro danou jednotku klient poskytne data.

Automatické testy a izolované náhledy ověřují chování a rozložení. Skutečný vzhled nad postavami ve WoW zatím ověřen nebyl.
