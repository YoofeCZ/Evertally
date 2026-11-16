# Evertally 0.9.35 / Bridge 0.9.13

## Addon

- **Párování v nastavení (onboardingu).** Hned za krokem „Co potřebuješ“ následuje krok Spáruj aplikaci s webem. Dokud aplikace nenahlásí spárování, nastavení dál nepustí.
  - Tlačítko **Spárovat** uloží žádost a znovu načte rozhraní (`/reload`). Běžící aplikace Evertally pak otevře párování v prohlížeči. WoW neumí spustit program, proto musí aplikace běžet (i schovaná u hodin). Když neběží, krok to napíše.
  - Tlačítko **Ověřit** znovu načte rozhraní, aby addon viděl, co aplikace nahlásila.
  - Volba **Spouštět aplikaci Evertally se zapnutím WoW** se pošle aplikaci stejnou cestou. Je i v Nastavení → Web. Krok ukazuje, co aplikace hlásí.
- Nastavení se jednou otevře znovu všem (verze nastavení 6), aby každý prošel párováním.
- **Sdílení kroniky** je v nastavení na kroku Web (zapne i veřejnou stránku, postavu a trasu) a v souhrnu.
- Texty o poloze odpovídají skutečnosti. Pro partu, cech a přátele je poloha živá. Na webu ne: aplikace ji pošle při změně lokace, přihlášení, `/reload`, dotazu „Kde jsi?“ z webu a jinak nejvýš jednou za 5 minut.
- Po změně volby, která se týká webu (web, druhy dat, veřejná stránka, kronika, poloha na webu, spouštění s WoW), se objeví lišta **Uložit a poslat**. Hra totiž změny zapisuje jen při `/reload` nebo odhlášení; tlačítko udělá `/reload` hned.
- Oprava: otevření Junk and Gear (např. s Hearthstone v taškách) padalo na `Gear.lua:104: bad argument #2 to 'tonumber' (base out of range)`.

## Bridge

- Čte z `Evertally.lua` jen tabulku `EvertallyDB.bridgeRequest` (datovým parserem, nic jiného): žádost o spárování (jen čerstvou, do 15 minut, a jen když PC spárované není) a volbu spouštění s WoW. Vyřízené žádosti si pamatuje v `game-requests.json`, takže se neopakují.
- Do `BridgeInstallation.lua` zapisuje navíc `paired` a `autostart` (jen ano/ne, žádný účet ani token).

Nový soubor v TOC (`BridgeLink.lua`): po aktualizaci je potřeba WoW úplně restartovat, `/reload` nestačí.
