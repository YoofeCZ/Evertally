# Evertally 0.9.32 — podrobná kronika

Kronika zachovává události během celého hraní, v boji i mimo něj. Záznam pořád vyžaduje zapnutý webový export a „Moje trasa“; podrobný snímek postavy navíc „Moje postava“.

- Běžný souboj s mobem má vlastní začátek, konec, protivníka a otevřitelný detail. Platí i pro PvP a bossy. Ukončení boje samo o sobě není vydáváno za zabití.
- Použití kouzel, začátek a selhání sesílání, příkaz ke skoku, nasednutí/sesednutí a příkazy k použití předmětů mají vlastní časové události i mimo boj. Příkaz k použití předmětu je označený jako pokus: nepotvrzuje spotřebu ani zásah.
- Aury mají získání, obnovení, ztrátu a známý aktivní stav. Nečitelné API se odlišuje od skutečně prázdného seznamu.
- Levý panel ukazuje historický stav skupiny/raidu, postavy, buffů/debuffů, peněz, celkového odehraného času, výbavy, atributů, procentních statistik a všech dostupných dovedností/profesí. Odehraný čas a další pole se zobrazí po skutečně zachycené odpovědi klienta.
- Stará trasa zůstává souvislá a tmavší, včetně předchozích návštěv stejné mapy. Červená označuje skutečně zaznamenané intervaly boje. Neznámé mezery a změny mapy se nespojují.
- Události lze prohledávat a procházet po stránkách; kliknutí zastaví přehrávání na zvolené akci. Souboj má vlastní přehrání, které skončí na jeho konci. Panely fungují i na úzkém displeji.
- Pravý panel obsahuje obtížnost, velikost skupiny, výsledek, skutečný rozpis kouzel a podíl na poškození skupiny, pokud jsou známé. Zabití a předměty se vztahují k vybranému souboji/instanci. Hlášky NPC a bossů mají zachovaný plný text; soukromé zprávy hráčů se nesbírají.
- Malý přehrávač na přehledu běží bez zvuku, opakuje se a kliknutím se rozbalí se zachováním času. Escape vrátí náhled. Prohlížeč bez fullscreen API použije rozbalení přes celou dostupnou plochu.

Nativní souhrny a rozpis kouzel se čtou až po boji. Chybějící poškození a neznámé počty použití zůstávají neznámé; z konečného součtu se nevymýšlí časová řada zásahů. Omezený bojový log se na Forever nezapíná. Celková čísla dungeonu se nevydávají za metriky jednoho bosse.

Staré záznamy se doplňují jen o existující atributy/výbavu a doložené bossové intervaly. Samotný historický řádek „Plainstrider +52 XP“ neobsahuje začátek boje ani seslaná kouzla, takže je zpětně nelze obnovit.

## Aktualizace

Nejdřív web přijímající nové volitelné údaje, potom addon. Databázová migrace pro tuto verzi není potřeba. Přibyl `JourneyDetails.lua` v TOC: po instalaci je nutné WoW úplně ukončit a znovu spustit. Instalátor pořizuje zálohu předchozích souborů a ponechává potvrzení instalace Bridge i hráčova SavedVariables.

## Ověření

Automatické testy sběru, smlouvy, oprávnění, převodu i výpočtů jsou doplněné o podrobnou kroniku. Syntetický klientský průchod používá skutečné Lua handlery a export, který pak projde webovým parserem, validací a skládáním kroniky. Tento soubor byl přehrán v prohlížeči na desktopu i úzkém viewportu.

Nové události a čitelnost API na živém Forever klientovi po restartu ještě vyžadují ověření hráčem. Testovací nativní měřič dokazuje správné zpracování dat, nikoli to, že konkrétní herní verze všechny údaje zpřístupní.
