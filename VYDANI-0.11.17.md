# Evertally 0.11.17 (addon) + aplikace 0.9.20

**Aplikace 0.9.20**
- **Stahování bez časového limitu:** addon (58 MB) se stahoval s limitem 25 s a na pomalejším připojení aplikace hlásila „timeout: global“ a addon se nenainstaloval. Limit je pryč (zůstává jen 20 s na spojení se serverem a 30 s na jeho první odpověď).
- **Průvodce při prvním spuštění:** Vítej → složka WoW → párování s webem → kdy se spouštět → aktualizace → hotovo. Dá se přeskočit a znovu spustit v Nastavení spojení.
- **Volba „Automaticky stahovat aktualizace (addon i tuto aplikaci)“** v průvodci i v Nastavení spojení (`prefs.json`). Vypnuté = nic se nestáhne samo; „Zkontrolovat aktualizace“ v nabídce ikony funguje vždy.

**Addon 0.11.17**
- **Aplikace a OpenMap už nejsou povinné.** Addon funguje i bez nich; instalace, shrnutí, Dokončit a Nastavení řeknou, že bez nich to není plnohodnotný zážitek: neuvidíš spoluhráče ve hře, nebudeš mít osobní kroniku na webu, nezapíšeš se do žebříčku a nefunguje nic dalšího online.
- **Nastavení:** sekce jako dlaždice ve dvou sloupcích; stránky Evertally rozdělené na pojmenované sekce.
- **Damage meter** (`/etally meter`, Nastavení → Souboj): poškození, DPS, léčení, HPS, absorpce, přijaté poškození, poškození, kterému šlo uhnout, nepřátelé (adds), přerušení, dispely a smrti; aktuální souboj, celkem a uložené souboje; klik na hráče = rozpad podle kouzel. Data dává vestavěný meter hry; za boje jen pruhy a čísla, procenta a rozpady po boji.
- **Threat meter** (`/etally threat`): agro na tvém cíli pro tebe, mazlíčka a skupinu; tank zvýrazněný, kdo se blíží tankovi, zčervená.
- **Jiskřičky na lootu:** questové předměty k sebrání jiskří i po změně grafické předvolby (výchozí zapnuto).
