# Evertally 0.9.33

- Souboj se během přehrávání automaticky otevře a ukazuje skutečné události postupně, s pauzou a posunem po jednotlivých akcích.
- Konec souboje zůstává otevřený k prohlédnutí; pokračování obnoví cestu. Vysoká rychlost cesty začátek krátkého boje nepřeskočí.
- Boční panely a bojové okno se přizpůsobí skutečné výšce časové osy. Při otevřeném přehrávači se nescrolluje celá stránka a patička webu je skrytá.
- Přehled vybírá skutečnou dostupnou kroniku, včetně vlastních neveřejných záznamů přihlášeného hráče. Prázdná data ani chyba se nenahrazují demem.
- Kouzla dostávají skutečné ikony podle spell ID; protivníci podobiznu podle NPC ID nebo jednoznačného jména u starších záznamů.
- Nové záznamy uchovávají dostupná sesílání protivníků/skupiny, jejich původce, skutečný odeslaný cíl vlastního kouzla a texture ID ikon.

Nezaznamenané zásahy a poškození starých soubojů se zpětně nevytvářejí. Dostupnost nových unit událostí ve skutečném
Forever klientu musí potvrdit herní záznam; automatické testy ověřují veřejné i nepřístupné API hodnoty na fixtures.
