# Evertally 0.10.0 (addon) + aplikace 0.9.19

## Evertally Guide: Polestar je součástí Evertally

- Celý addon **Polestar 0.4.0.1** (GPL-3.0, github.com/fitzforge/polestar) je převzatý jako složky `Evertally_Guide*`:
  - levelovací návody krok za krokem pro všechny rasy a povolání, návody na profese a průzkum,
  - šipka s trasou pěšky, lety i loděmi,
  - Lookup (questy, NPC, předměty, objekty), vzácní mobové, alti, přehled dungeonů s attunementy, rady k výbavě a plán talentů,
  - **všechna vylepšení hraní (QoL)**: automatické questy, prodej šedých a oprava, doplnění zásob, žádosti hráčů, místo v taškách, varování dechu, pomoc po smrti, tempo XP, připomínka jízdy, létání z gossipu a další; každé jde vypnout.
- Vyrábí ho `tools/import_polestar.py` z nainstalovaného Polestaru a dá se kdykoli zopakovat pro novější verzi. Má jiná jména složek, globálů, uložených dat a klávesových zkratek, takže se s nainstalovaným Polestarem nepohádá. Autor návodů zůstává Polestar; zprávy v partě a importní řetězce jsou s Polestarem kompatibilní.
- **Celý Evertally je teď pod GPL-3.0.** Licence a poznámky o změnách (`NOTICE-EVERTALLY.txt`) jsou v každé složce.
- Bez jazykových balíčků Polestaru (němčina, francouzština…); návody jsou anglicky.

## Evertally

- **Nový vzhled okna**: noc a zlatá, schémata Noc, Soumrak a Grafit, ikony skupin v menu, nastavení s hledáním, přepínači a posuvníkem.
- **Stránka Levelování** (menu Průvodce): tlačítka do všech oken Evertally Guide, včetně nastavení QoL.
- **Jedna šipka**: „Navigovat“ kdekoli v Evertally vede šipka Evertally Guide; pohybujícího se hráče sleduje průběžně. Volba `guideArrow` vrací vlastní šipku Evertally.
- **Dungeon Journal**: chybějící questy z Codexu Evertally Guide, i s odměnami, XP, místem začátku a předchozími questy.

## Aplikace 0.9.19

- Aktualizace addonu umí všechny složky `Evertally*`, maže složky, které z balíku zmizely, a přijme větší balík (~58 MB). **Musí vyjít před addonem**, jinak by stará aplikace balík odmítla.

## Po aktualizaci

1. Hru **úplně ukonči a spusť znovu** (přibylo 32 složek addonů).
2. V seznamu addonů zkontroluj, že jsou zapnuté `Evertally_Guide*`.
3. Až to ve hře vyzkoušíš, **odinstaluj Polestar** (jinak budou funkce dvakrát). Nastavení a postup z Polestaru se nepřenáší, Evertally Guide začíná znovu (průvodce nastavením ho provede).

## Ověřeno

- Lua testy: 782 prošlo (nově test importu forku, stránky Levelování, šipky a questů z Codexu).
- Rust: sync 123, aplikace 10 testů.
- **Ve hře neověřeno**: chování forku (návody, šipka, QoL) i nový vzhled.
