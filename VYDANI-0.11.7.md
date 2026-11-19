# Evertally 0.11.7 (addon)

Aplikace zůstává **0.9.19**, nová není potřeba.

## Batoh

- **Opravená chyba**, kvůli které okno batohu při otevření padalo (`Theme.lua:148`) a v hlavičce chybělo jméno a zlato.
- **Banka ve vlastním okně:** u bankéře se otevře okno Banka (a k němu batoh) místo herní banky. Předměty jde přetahovat mezi bankou a batohem, pravým klikem přesouvat. Zavřením okna odejdeš od bankéře. Mimo banku ukáže odkaz „Banka“ poslední banku, kterou jsi viděl.
- **Nasazené tašky** vpravo nad předměty: najetí myší rozsvítí sloty tašky, kliknutím nebo přetažením tašku vezmeš, předmět puštěný na tašku se do ní uloží.
- **Zelené šipky vylepšení** stejné jako v herních taškách (modrá = do prázdného slotu).
- **Výběr batohu v nastavení** (`/etally setup`, stránka Batoh): Evertally, herní batoh, nebo jiný addon (Baganator…). Volba ostatní addony na tašky vypne nebo zapne po /reload.

## Trasa v kronice

- Kdo měl starší verzi (0.11.1 a dřív), neposílal trasu. Po aktualizaci se trasa zapne sama a mapa v kronice se začne plnit.
