# Evertally 0.9.45

## Porovnání výbavy: váhy pro každou třídu a talentovou větev

- Místo sedmi obecných profilů má teď **každá třída a větev vlastní váhy**, ve stejném měřítku jako komunitní škály: hlavní stat větve = 1 (Strength u Arms, Agility u lovce a rogue, Intellect u Holy paladina, Spirit u Holy priesta, Spell Power u mága a warlocka, Stamina u tanků…).
- Pořadí důležitosti odpovídá kurátorovaným škálám pro Classic/Forever, které vozí Pawn (HawsJon, `Pawn/ClassicHawsJon.lua`, větev Forever). **Čísla jsou vlastní Evertally:** Pawn je pod licencí CC BY-NC-ND (bez úprav), jeho tabulka se nekopíruje.
- Úprava pro levelování: **melee a tanci počítají armor víc** než raidové škály (melee 0,02, tank 0,04, medvěd 0,08 za bod; raidové škály mají pro DPS 0,005), protože při questování armor rozhoduje, jak často musíš jíst.
- **Enhancement shaman a Retribution paladin počítají Intellect** (0,55 síly; shocky, totemy, pečetě a léčení stojí manu). Lovci také (0,7).
- Příklady ze hry:
  - Thra's Friendship Bracelet (24 armor, +1 Int) proti Lupine Cuffs (28 armor): pro Enhancement je **náramek lepší**, cuffs vyjdou „horší“.
  - Embossed Leather Vest (62 armor, +2 Sta) proti Banshee Armor (26 armor, +3 Sta): **vesta zůstává lepší**.

## Zanedbatelný rozdíl = „zhruba stejné“

- Rozdíl menší než 0,15 (nebo 3 % hodnoty kusu) už neukazuje šipku ani „lepší“, tooltip píše **„zhruba stejné jako nasazené“**.
- Item level rozhoduje jen při úplně stejném skóre.

## Z 0.9.44

Hlášení do skupiny: přijatý quest, každý splněný cíl (8/8), hotové cíle, odevzdání.

Bez nového souboru v TOC: stačí `/reload`.

Ve hře zatím vyzkoušené není.
