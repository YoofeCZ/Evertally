# Produkční cíl Evertally

Schválený host je **evertally.afstudio.dev**, Worker `evertally`, Cloudflare účet `a355311725afbdb07a231531619a4e01`. Produkční D1 databáze je výhradně `evertally-production`, UUID `33ca048c-b932-44cd-ba58-cf38aed0fd23`, jurisdikce `eu`. Ostatních databází účtu se tyto postupy nedotýkají.

## Konfigurace po každém buildu

V `platform/`:

```powershell
npm run build
node scripts/prepare-production.mjs --check-db --dry-run
```

Generátor přečte `dist/server/wrangler.json` a vedle něj vytvoří `wrangler.production.json`. Zachovává generovaný entry point, relativní cesty assetů, modulová pravidla a ostatní frameworková nastavení. Mění pouze cílový účet/Worker, jedinou D1 vazbu `DB`, vlastní doménu a vypíná `workers_dev` i `preview_urls`.

`--dry-run` pouze sestaví a zkontroluje balíček. **Tento skript nikdy nepublikuje Worker ani neupravuje DNS.** Generovaný adresář se při dalším buildu obnovuje, proto je potřeba produkční konfiguraci vždy vygenerovat znovu.

## První inicializace nové databáze

```powershell
node scripts/prepare-production.mjs --init-db --check-db
```

Příkaz ověří přesné UUID, název, jurisdikci `eu` a prázdný stav nové databáze. Teprve potom provede tři existující migrace `0000`, `0001`, `0002`. Povoleny jsou pouze příkazy vytvářející schéma a `ALTER TABLE`; nástroj neprovádí reset ani mazání. Opakovaná inicializace neprázdné databáze se zastaví před zápisem. Při částečné chybě se má aktuální schéma prohlédnout a opravit konkrétní příčinu, nikoli databáze znovu vytvořit.

Výsledkem je devět aplikačních tabulek a sloupec `atlas_observations.character_data`. Přihlašovací sezení, uživatelé, granty a zařízení začínají prázdné.

## Publikování a Discord

Publikování provádí integrační vlastník až s aktuálními distribučními assety a ověřeným buildem. Použije produkční konfiguraci z posledního buildu. Discord hodnoty se nastavují jako Cloudflare secrets podle `discord-secrets.example.json`; skutečné hodnoty patří do ignorovaného `secrets.local.json` nebo přímo do úložiště secrets. Generátor je nečte ani nevypisuje. Produkční callback je `https://evertally.afstudio.dev/auth/discord/callback`.

Target soubor obsahuje identifikátory infrastruktury, nikoli přihlašovací tokeny. Ověření účtu využívá již existující globální OAuth přihlášení Wrangleru; příprava neotvírá prohlížeč a nevyvolává nové přihlášení.
