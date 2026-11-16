# Evertally 0.9.43

## Zprávy do skupiny vždy anglicky

- Zprávy do skupiny „(via Evertally)“ jsou teď **vždy anglicky**, i s addonem v češtině, protože ve skupině můžou být hráči, kteří česky nerozumí. Příklad: „{rt6} Quest done: Finding the Antidote (via Evertally)“. Nastavení a okno zůstávají v jazyce addonu.

## Pochlubit se (/say a guilda na jedno kliknutí)

- Po **novém levelu**, **dokončeném dungeonu** a **osobním rekordu** vyskočí nahoře uprostřed obrazovky lišta **„Pochlubit se?“** s textem zprávy a tlačítky **Říct do /say** a **Do guildy** (jen když jsi v guildě). Po 25 s sama zmizí.
- Zprávy (anglicky, s podpisem):
  - „Just hit level 30! (via Evertally)“
  - „Cleared The Deadmines in 32:15! (via Evertally)“
  - „Cleared The Deadmines in 29:48, a new personal best! (via Evertally)“
  - Když máš na webu veřejnou postavu i Kroniku, přidá se „Follow my journey in my chronicle on evertally.afstudio.dev“.
- **Proč na kliknutí:** hra dovolí addonu napsat do /say v otevřeném světě jen po kliknutí hráče. Sám od sebe Evertally do /say nic nepíše.
- Vypnout jde v Nastavení → Sdílení ve hře → „Po levelu, dungeonu nebo rekordu nabídnout pochlubení…“.

## Questie a QuestMaster se nezdvojují

- Když je v Evertally zapnuté hlášení do skupiny a máš **Questie** nebo **QuestMaster**, Evertally jim vypne jejich zprávy do skupiny a guildy, aby ve skupině nebyly dvakrát:
  - Questie: kanál hlášení questů nastaví na „disabled“,
  - QuestMaster: přijetí, odevzdání a opuštění questu, cíle, předměty, které začínají quest, a level-up do chatu.
- Jejich vlastní zprávy jen pro tebe (QuestMaster level-up řádek, Questie tooltipy…) zůstávají.
- Jejich původní nastavení se uloží. **Když v Evertally hlášení do skupiny vypneš, vrátí se jim.** Při první změně to Evertally napíše do chatu.

## Porovnání výbavy: armor se počítá u všech rolí

- Oprava: útočné a kouzelnické profily (Enhancement, Arms, Combat, Fire…) **vůbec nepočítaly armor** a tank ho měl s tak malou váhou (0,015 za bod), že skoro nic neznamenal. Proto vyšla látková Banshee Armor (26 armoru, +3 Stamina) „lepší“ než nasazená kožená Embossed Leather Vest (62 armoru, +2 Stamina) jen díky jedné Stamině navíc.
- Nové váhy armoru za bod: melee a rogue 0,02, feral 0,03, lovec 0,015, kouzelníci a léčitelé 0,005, tank 0,05. Pro Enhancement teď vesta vyjde lepší (1,94 proti 1,57).
- Enchant na nasazeném kusu se do porovnání nepočítá, stejně jako v porovnání Blizzardu.
- V řádku „Item level 12 → 14“ se místo šipky ukazoval čtvereček (font tooltipu šipku nemá). Teď je tam „12 -> 14“.

Bez nového souboru v TOC: stačí `/reload`.

Ve hře zatím vyzkoušené není.
