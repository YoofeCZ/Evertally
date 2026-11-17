# Evertally 0.11.0 (addon)

Aplikace zůstává **0.9.19**, nová není potřeba.

## Jedno Evertally

- **Okno Evertally je hub Evertally Guide.** Vlevo je lišta sekcí, v ní Evertally se svými stránkami. Nastavení Evertally je v okně nastavení průvodce. Stránky mají vzhled průvodce.
- **Seznam AddOns:** všechny složky jsou pod jednou hlavičkou **Evertally**, s názvy „Evertally - …“, jen anglicky a česky.
- **Čeština v Evertally Guide:**
  - celé rozhraní je česky,
  - většina textů návodů je česky, zbytek zatím anglicky a doplní se v dalším vydání,
  - jména z Warcraftu (NPC, předměty, zóny) zůstávají anglicky jako v klientu.

## Nové

- **Tlačítko u minimapy:**
  - levé tlačítko otevře **menu Evertally**: velké tlačítko EVERTALLY MENU a skupiny Průvodce, Navigace, Hra, Nastavení a Komunita (Discord, nahlášení problému),
  - pravé tlačítko Evertally **skryje nebo zase ukáže**, logo je pak šedé.
- **Okno návodu má nahoře přepínač Návod | Questy.** Questy jsou nový quest tracker:
  - sekce K odevzdání, aktuální zóna, ostatní zóny a Dungeony a skupiny,
  - úroveň questu v barvě obtížnosti, cíle s počty a lištou, vzdálenost, „Odevzdat u: …“, časovač,
  - klik nastaví šipku k nejbližšímu cíli, Shift+klik vloží odkaz do chatu, pravé tlačítko otevře menu (deník, mapa, sdílet, zrušit),
  - sbalování sekcí a questů, řazení podle vzdálenosti, úrovně nebo deníku,
  - tlačítko EVERTALLY MENU.
- **Dungeon Journal, karta „Pro tebe“:**
  - úrovně, kolik úrovní ti dají questy a kolik questů je hotových, v deníku nebo k převzetí,
  - Vyzvednout a Odevzdat questy (návody průvodce),
  - attunementy a klíče krok po kroku s tlačítkem „Proveď mě tím“.
  - Na kartě Questy je u každého questu hotovo / odevzdat / v deníku.
- **Jedno nastavení po instalaci:** kroky Evertally jsou stránkami instalace průvodce. Pořadí: uvítání, jazyk, instalace, párování, web, veřejná stránka, poloha, sdílení, mapa, okno, jmenovky, hudba, pak volby průvodce (questování, zaměřování, skupiny, trasa, vzhled), shrnutí a konec. **Ukáže se každému ještě jednou.**

## Pryč (dělá to průvodce lépe)

- Z hubu zmizely sekce **Dungeons** (je teď v Dungeon Journalu) a **Characters**.
- Z menu Evertally zmizely **Databáze** (místo ní Lookup průvodce), **Výbava a odpad** (rady k výbavě a prodej z průvodce) a **Questový průvodce** (návody průvodce). Odkazy na ně dál fungují.
- Oznámení **„While you're here“** je ve výchozím stavu vypnuté. Zapneš ho v Nastavení.
- Druhé tlačítko u minimapy (průvodce) je ve výchozím stavu vypnuté.

## Opravy

- Discord odkazuje na server Evertally.
- Nastavení Evertally Guide v seznamu AddOns se už neplete s Polestarem (ID, příkazy, klávesové zkratky).

## Po aktualizaci

1. Hru **úplně ukonči a spusť znovu**, protože přibyly nové soubory.
2. Otevře se nastavení. Projdi ho, nebo ho zavři a spusť později přes `/etally setup`.

## Ověřeno

- Lua testy: 832 prošlo.
- Náhledy rozložení offline: menu, Dungeon Journal, okno návodu s kartou Questy, stránky nastavení.
- **Ve hře neověřeno.**
