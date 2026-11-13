# Evertally addon 0.8.4 — dostupné lety a ověření výběru trasy

13. listopadu 2026. Dvě samostatné chyby dřívější navigace: nabídka používala všechny referenční lety bez znalosti postavy; výběr itineráře porovnával odhady chůze vzdušnou čarou a terén řešil až pro kreslení. Proto se mohl vybrat zamčený let nebo špatný přístup k přístavu.

- TravelKnowledge ukládá potvrzené CURRENT/REACHABLE body zvlášť pro GUID/realm/region. Čte jen mapu skutečného letového mistra s bodem CURRENT. Nezaměňuje pořadí tlačítek za ID bodů a nepřijímá obecný seznam neobjevených bodů jako odemčení. Při nedostupných údajích lety bezpečně vynechá.
- Každá letová hrana vyžaduje potvrzený začátek i konec. Grafová cache zahrnuje sadu známých bodů. Otevření mapy mistra aktualizuje znalost a vynutí přepočet navigace.
- Journey porovnává skutečné směrové kolizní náklady pěších alternativ. Levné neověřené dolní odhady se postupně nahradí výsledky podrobného solveru a hledání se opakuje. Podrobná geometrie se dopočítá pro vítězné úseky. Nezobrazuje se předběžná trasa se zamčeným letem ani falešná hotová pěší varianta.
- Zachovávají se jednotlivé validované pěší úseky a jejich geometrie. Rozpracovaná nebo zrušená trasa se po zastavení sama znovu neobjeví.

Skutečná data Dolanaar (1438;55%,60%) → Stormwind: bez známých letů výsledek vede k portálu v Darnassu, po portálu k přístavu Rut’theran a loděmi přes Auberdine. Kontroly ověřují také změny známých letů bez použití staré cache, izolaci postav, nemožnost převzít obecný seznam jako odemčení a zrušení rozpracovaného hledání.

Po instalaci WoW úplně ukončit a znovu spustit (nové soubory v TOC). Potom jednou otevřít mapu u letového mistra, aby addon získal potvrzené body této postavy. Ve hře po instalaci zatím nepotvrzeno; Windows most a web zůstávají 0.8.1 a webový plánovač se tímto vydáním nemění.
