# Evertally addon 0.8.3 — kolizní cesty a preference silnic

13. listopadu 2026. Předchozí 16yardová maska exportovala jen typ povrchu, zahodila kolizní hrany, výšky a patra a zvětšováním buněk otevírala překážky. Vyhlazení pak kreslilo nepoužitelné zkratky. Oprava vyžaduje podrobnější data, nikoli jiný vzhled čáry.

- Přibalený izolovaný solver a úplná kolizní data Shortest Path Forever v1.35.0 (GPL), včetně výšek, pater, zakázaných/jednosměrných přechodů a silnic. Nastavení ani běžící trasa jiného addonu se nemění.
- Chůze preferuje silnice původní váhou 1,5× pro pohyb mimo ně. Cesta k cíli může opustit silnici; výhradní pohyb po silnicích toto vydání neslibuje.
- Šipka i souvislá čára používají stejný zbývající výsledek. Pending/failed kolizní hledání už nespadne na přímku přes překážky; asynchronně dokončené náhledy se správně převezmou.
- Pro blízký cíl za zdí nestačí průchozí hrubá buňka. Kolizní režim vyžaduje dosažení cíle do 3 yardů; zatáčky se nevynechávají ze vzdálenosti 5 yardů.
- Zdrojová data, původní GPL licence a přesné hashe dodává Roads/. Regenerace: tools/vendor_roadpath.py.

Skutečná regrese Stormwindu: dva sousední body sever/západ (-8800,600.9950) → (-8800,608.9552) měly v originálu zavřenou hranu; stará maska dovolila přímku 7,96 yd. Nový solver vrací čtyřbodovou objížďku 30,48 yd. Další testy kontrolují vyšší podíl silnic při zapnuté preferenci, jednostranné svahy, patra, rušení a čekání na výsledek.

Přibyly nové Lua soubory: po instalaci WoW úplně ukončit a znovu spustit. Ve hře po instalaci zatím vizuálně nepotvrzeno. Windows most a web zůstávají 0.8.1; webová implementace své terénní masky není součástí této opravy.
