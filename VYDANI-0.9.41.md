# Evertally 0.9.41

## Online s Evertally

- Nová volba **„Ukázat mě ostatním hráčům s Evertally“** v Nastavení → Sdílení ve hře a v průvodci nastavením (krok sdílení s hráči). Ve výchozím stavu je **vypnutá**.
- Kdo ji zapne, ohlásí se ostatním hráčům s Evertally **neviditelnou addon zprávou v kanálu #Evertally**: po přihlášení, při změně zóny nebo levelu (nejvýš jednou za 30 s) a každých 5 minut. Ohlášení obsahuje jen **třídu, level a zónu** (oblast, ne polohu). Jméno doplní server hry, takže se nikdo nemůže vydávat za jiného. Po vypnutí volby nebo při odhlášení addon ostatním hned řekne, že hráč odešel.
- V **Lidé** přibyla skupina **„Online s Evertally“** (ve Všech i v Evertally): jméno v barvě třídy, level, zóna a před kolika minutami se ozval. Kdo se 15 minut neozve, zmizí. Seznam drží nejvýš 200 hráčů.
- **Klik na hráče** otevře whisper v Evertally chatu. U whisperu jsou nově tlačítka **Pozvat do skupiny** a **Přidat do přátel**.
- Přesná živá poloha zůstává jen pro přátele, skupinu a cech, jako dosud.
- Vidí se jen hráči ze stejného světa, kteří jsou v #Evertally. Tam je každý automaticky, pokud ho sám neopustil.

## Oprava webu (nasazená už dřív)

- Párování aplikace a všechny další akce na webu hlásily „This action must be confirmed on the Evertally website“. Za tunelem na Raspberry Pi server viděl adresu jako http, kdežto prohlížeč posílal https. Kontrola teď porovnává adresu webu a za tunelem https přijme (`platform/lib/origin.ts`).

Nový soubor v TOC (`Presence.lua`): po aktualizaci je potřeba **restart hry**, `/reload` nestačí.

Ve hře zatím vyzkoušené není.
