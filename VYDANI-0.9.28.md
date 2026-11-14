# Evertally 0.9.28 (Bridge zůstává 0.9.10)

**Pohled na hráče: questy a reputace.** Žádost o pohled má dvě nové volby, které se dají odškrtnout jako všechny ostatní:

- **Questy:** quest log s úrovní questu a postupem úkolů („4/10 Kobold Vermin slain“). Quest se splněnými úkoly má štítek „hotovo“ a text „připraveno k odevzdání“. Bere se z `C_QuestLog` (GetNumQuestLogEntries, GetInfo, GetQuestObjectives, IsComplete); hlavičky a skryté questy se vynechávají.
- **Reputace:** frakce se stupněm podle jazyka hry (`FACTION_STANDING_LABEL1–8`) a postupem v rámci stupně („1200/6000“). Bere se z `C_Reputation` (GetNumFactions, GetFactionDataByIndex); hlavičky bez vlastní reputace se vynechávají.

V okně pohledu jsou nové záložky Questy a Reputace. Výchozí žádost se ptá i na ně (`istpqr`), zlato dál nikdy. Questy a reputace se ukážou jen v okně toho, kdo se dívá: **nikdy se nekopírují na web** (do kopie Armory jde dál jen výbava, statistiky, talenty a profese).

API ověřeno v offline katalogu Forever 1.60.1 (staré `GetQuestLogTitle` a `GetFactionInfo` ve Foreveru nejsou). Starší addon na druhé straně písmena `q` a `r` nezná a odpoví bez nich; nic se nerozbije, ale questy uvidíš jen u hráčů s 0.9.28.

**Omezení:** questy a frakce pod sbalenou hlavičkou se neukážou (addon nic nerozbaluje). Ve hře neověřeno; Lua testy 533 (nové: cesta mezi dvěma hráči, odškrtnutí a web, okno pohledu). Z 0.9.27 stačí `/reload`.
