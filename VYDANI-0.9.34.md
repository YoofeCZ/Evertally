# Evertally 0.9.34 / Bridge 0.9.12

- Bridge posílá kompaktní JSON; velikost přenosu odpovídá velikosti spočítané při dělení. Knihovna už neroztahuje balíky nad limit 1 MiB.
- Odmítnutý export zůstává chybou také při dalším skenu. Stav „Vše odesláno“ se nezobrazí, dokud existuje známý nevyřešený přenos.
- Nedopsaný soubor nebo dočasně neúspěšný přenos se opakuje i bez další změny souboru, po 30 sekundách.
- Ukončení posledního klienta WoW probudí Bridge a vyvolá synchronizaci finálního uložení. Hra se nespouští ani neovládá.
- Addon při odhlášení, `/reload` a normálním vypnutí pořídí poslední dostupnou polohu před uzavřením trasy. Dávka trasy má nejvýš pět minut.
- Bridge zapíše potvrzená ID do existujícího souboru `BridgeInstallation.lua`. Při příštím načtení addon odstraní z čekající fronty pouze potvrzená ID stejného producenta a souhlasu; neodeslaná data i místní historie zůstanou zachované.

SavedVariables se neupravují zvenku. Násilné ukončení hry nebo pád může zabránit jejich uložení; přenést lze pouze data,
která hra skutečně zapsala. Nové soubory v TOC nepřibyly, proto změny addonu načte `/reload`.
