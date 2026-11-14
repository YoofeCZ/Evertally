# Evertally — web a API

React (Vinext) na Cloudflare Workers s databází D1 a Drizzle migracemi. Praktický návod: `../NAVOD.md`.

- Přihlášení přes Discord (OAuth2, scope `identify`), relace jako náhodný token v HttpOnly cookie; v databázi jen SHA-256 hash.
- Párování desktopové aplikace Evertally Sync (device flow) a upload s tokenem zařízení.
- Výslovné souhlasy po oblastech dat, odvolání, soukromé profily, mazání vlastních dat.
- Import JSON/Lua `SavedVariables` se jen parsuje; žádný nahraný kód se nespouští.
- Rozhraní v angličtině s češtinou jako volbou (`lib/i18n.ts`). Vzhled podle reference Railway z GradientDeck (`app/evertally.css`).

## Struktura

| Kde | Co |
| --- | --- |
| `lib/api.ts` | Směrování API a kontrola Origin u zápisů |
| `lib/auth.ts`, `lib/auth-core.ts` | Discord login, relace, vývojové přihlášení (jen dev + loopback) |
| `lib/devices.ts` | Párování a upload z aplikace |
| `lib/store.ts`, `lib/policy.ts`, `lib/contracts.ts`, `lib/import.ts` | Data, souhlasy, schéma událostí, parser |
| `components/evertally/` | Webové rozhraní |
| `drizzle/` | Migrace `0000`–`0002` |

## Vývoj a kontroly

```powershell
npm ci
npm run build
# Na nové lokální DB aplikovat SQL soubory z drizzle podle ../NAVOD.md.
npm run dev -- --port 5173
npm test; npm run typecheck; npm run lint
```

Discord přihlášení potřebuje `.dev.vars` (vzor `.dev.vars.example`). Bez něj je lokálně k dispozici jen vývojové přihlášení.

`.openai/hosting.json` a `scripts/vite/sites-vite-plugin.ts` jsou pozůstatek původního hostingu OpenAI Sites; simulace ChatGPT přihlášení je vypnutá (`mockAuth: false`) a kód ji už nepoužívá.
