# Evertally addon 0.8.2 — ovládání cest a souvislá trasa

13. listopadu 2026. Oprava podle herních snímků stránky Cesta a mapy Teldrassilu.

- Navigovat, Ukázat na mapě a Zastavit jsou v patičce nad pergamenem. Seznam cílů se nezakrývá. Výběr ukazuje další krok a ETA; úplný itinerář je rozbalovací.
- Otevření mapy předává všechny tři souřadnice, ne pouze ID mapy.
- Tečky nahradily souvislé barevné čáry s obrysem na mapě i minimapě. Sledují posun, zoom, otáčení a velikost, nepřetékají za mapu.
- Aktivní chůze sdílí terénní cestu šipky a kreslí jen zbývající body od aktuální polohy. Nový cíl automaticky neobnovuje staré předávání do SPF s jeho tečkami; doplňkový SPF zůstává výslovná volba.
- Zastavení odstraní obě čáry, náhled i šipku. Při nedostupných údajích klienta se čára skryje.

Regrese prověřují skutečná tlačítka, jejich rodiče a vrstvy, souřadnice, terénní ohyby, propojené úseky, projekci obou map a úklid při zastavení. Oddělené náhledy zkontrolované v rozměrech 700 × 460 a 1100 × 720 jsou modelem rozložení, nikoli herním snímkem. Výsledek přímo ve hře po načtení opravy zatím není potvrzený.

Stačí /reload. Souborový ani živý protokol se nemění; Windows most a web 0.8.1 jsou kompatibilní.
