# Sdílený kontrakt implementace 0.4.0

Tento soubor koordinuje addon, browser import a server. Všechny komponenty se musí shodnout; při potřebě změny nejdřív upozornit integračního vlastníka.

## Export

Pomocný addon `Evertally_Export` zapisuje samostatný soubor `Evertally_Export.lua` s jedinou SavedVariable `EvertallyExportDB`. Hlavní addon si může na stejnou tabulku sáhnout jako na optional dependency. Cizí peer cache se do pomocného addonu nikdy nekopíruje.

```json
{
  "schemaVersion": 1,
  "enabled": true,
  "producerId": "installation-random-id",
  "consentEpoch": 1,
  "since": 1794236400,
  "scopes": ["world_facts", "own_runs", "own_character", "own_professions", "own_track", "guild_share"],
  "events": []
}
```

Vypnutý export je `enabled:false, events:[]`. Zapnutí bere nové události, staré jen výslovným výběrem. Časy jsou UTC Unix sekundy, délky běhů milisekundy. Pole navíc jsou odmítnutá. Povolené lokální eventy:

```json
{
  "schemaVersion":1,
  "eventId":"installation:session:sequence",
  "producerId":"installation-random-id",
  "origin":"local_observation",
  "kind":"quest.turned_in",
  "observedAt":1794236400,
  "game":{"product":"forever","build":"unknown","interface":16001,"region":"unknown","realm":"unknown"},
  "character":{"id":"local-character-id","name":"OwnName","realm":"OwnRealm","classId":7,"raceId":6,"level":20},
  "payload":{"questId":182,"xp":100,"money":0},
  "evidence":"api_event"
}
```

`character` je vždy pouze vlastní postava. Server ji před uložením vyřadí z world_facts/own_professions projekce bez own_character scope; soukromý character id může mapovat vlastní účasti. Žádná jména spoluhráčů. `evidence` je api_event / api_snapshot / manual, ne důkaz nefalšovatelnosti.

Povolené kind/payload (pole níže volitelná podle dostupnosti kromě identifikátoru; strict whitelist):

- character.snapshot, character.level: level, classId, raceId, name, realm (identita z own_character; klasické snapshoty nesmí nést peer identity).
- quest.accepted, quest.turned_in, quest.abandoned: questId, title, xp, money, npcId, mapId, x, y.
- npc.observed: npcId, name, mapId, x, y, positionMethod (player_interaction / unit_position / unknown), level.
- vendor.snapshot: npcId, name, items[{itemId,name,price,quantity}], mapId, x, y.
- loot.received: itemId, name, quantity, sourceNpcId, sourceKind (corpse / object / gathering / craft / quest / unknown), sourceCertain.
- profession.snapshot: professionId, name, skill, maxSkill, recipes[{recipeId,name,learned}].
- craft.result: recipeId, itemId, quantity, professionId.
- cooldown.snapshot: recipeId, readyAt.
- instance.entered, run.finished, run.interrupted: runId, instanceId, name, instanceType (party / raid), difficultyId, startedAt, endedAt, durationMs, status (visiting / completed / interrupted / manual / abandoned), completion (unknown / last_boss / full_clear), rankEligible (výchozí false), rulesetId, groupSize, maxLevel, minLevel, deaths, bossCount, bosses[{encounterId,name,killedAt}].
- raid.encounter_finished: encounterId, name, success, durationMs, instanceId, instanceName.

Ingame peers mohou sdílet vlastní souhrny a fakta přes povolený transport; příjem musí vždy vnutit origin peer a oddělit cache. Ranking se u neověřeného rulesetu neaktivuje.

## API pro frontend

- GET /api/status → {version, user:{id,username,displayName,avatarUrl}|null, totalEvents, totalRuns, totalCharacters, latestAt, auth:{discord,devLogin}, capabilities:{...}}. Veřejné počty jen zveřejněná data.
- GET /api/runs?mine=1 nebo bez mine → {runs:[]} řádky {id,name,instanceId,startedAt,durationMs,status,completion,rankEligible,character:{id,name,realm,classId,raceId,level}|null,bossCount,evidence}; bez mine jen veřejné profily.
- GET /api/atlas?kind=&search= → {entities:[]} normalizované {id,kind,name,count,lastSeen,payload}; pouze sdílené facts.
- GET /api/leaderboards?classId=&raceId=&instanceId=&metric=time|count → {entries:[],rulesLabel,sampleSize}; žádné neověřené speed rekordy.
- GET /api/me → {user,grants:[],profiles:[],devices:[],eventCount,runCount}; vyžaduje session.
- POST /api/consents body {producerId,consentEpoch,since,scopes} → {grant:{id,...}}. Zdroj vázat na uživatele, obnovování vyžaduje novou epoch.
- DELETE /api/consents/{id} → {revoked:true}; navždy odmítat danou epoch.
- POST /api/uploads body {grantId,export:<envelope výše>} → {accepted,duplicates,rejected,uploadId}; autorizované, strict, idempotentní.
- PATCH /api/profiles/{id} body {public:boolean} → {profile}; výchozí soukromý.
- DELETE /api/me/data → {deleted:true}; smaže vlastní herní data a profily, odvolá granty a odpojí spárované aplikace; data zmizí z veřejných přehledů. Identita Discordu a revokační záznamy zůstávají.
- GET /api/export?instanceId= → omezený veřejný JSON datový balíček {schemaVersion:1,generatedAt,runs:[],entities:[]}. Tento obecný export není formátem importéru addonu; pro něj slouží `/api/community` níže.

## Komunitní balíček a soukromé profese (0.3.0)

`GET /api/community?kind=quest|npc|item&search=` vrací pouze anonymní světová fakta z dosud aktivních grantů. Není ekvivalentem osobního exportu ani původního `/api/export`:

```json
{"schemaVersion":1,"kind":"evertally-community","scope":"world_facts","generatedAt":1794236400,"expiresAt":1794841200,"game":{"product":"forever"},"provenance":{"source":"community","countingUnit":"observations","truncated":false,"observationCount":1,"entityCount":1},"entities":[{"kind":"npc","id":706,"name":"NPC","count":1,"lastSeen":1794236400,"mapId":1426}]}
```

Nejvýše 150 entit a 49 152 UTF-8 bajtů. Jméno nejvýše 160 UTF-8 bajtů, bez herních řídicích značek. Zdrojový výběr je nejvýše 10 000 pozorování a 2 MiB payloadů. Počty v provenance popisují tento vzorek před ořezem počtu entit; `truncated` označuje omezení. Platnost nejvýše sedm dní. Souřadnicový pin NPC vyžaduje `unit_position`, ID mapy a obě souřadnice v rozsahu 0–1; poloha interakce hráče se nevydává za bod NPC.

Addon bezpečně dekóduje JSON do `EvertallyPeersDB.community`, odděleně od vlastních událostí i `peers`. Import nevytváří žádný `A.Record`, outbox ani relay. Chyba zachová předchozí cache, prošlá cache je označená jako zastaralá. Dovnitř se nedostávají jména postav, běhy ani libovolná původní payload pole.

Webový Atlas nabízí kopírování a stažení tohoto JSON; při nedostupné schránce zobrazí textové pole pro ruční kopii. Addon jej načítá ručně v kartě Community / Komunita, s hledáním jména či ID a filtrem druhu. Přímý HTTP přístup addonu se nepoužívá.

`GET /api/professions` vyžaduje session a ukazuje pouze vlastní profesní snímky, recepty, výrobu a cooldowny. Vrací `{generatedAt,totalObservations,sampledObservations,truncated,characters:[{id,character|null,professions:[],crafts:[],cooldowns:[]}]}`. Zdroj nejvýše 2 000 událostí a 2 MiB; chybějící skill je `null`. Při zakázané identitě se zobrazuje anonymní zdroj, nikoli domyšlená postava. Cooldown je odpočet z posledního snímku, ne živý dotaz do hry.

`/api/runs` navíc zachovává `endedAt,difficultyId,deaths,game,bosses,groupSize,minLevel,maxLevel,rulesetId`. Osobní časové souhrny neslučují různé instance, obtížnosti, definice dokončení, realmy nebo buildy. Rychlostní rekordy zůstávají vypnuté.

Webové detaily běhů zobrazují dostupné bossové časy od začátku, historickou identitu postavy a původ záznamu. Detaily atlasu zobrazují dostupná polohová, questová, lootová a prodejní pole. Chybějící informace se nevydává za nulu ani za nové měření. Profesní stránka používá pouze vlastní `/api/professions`; cooldown je odpočet ze snímku.

## Účty a desktopová aplikace (0.2.0)

- GET /auth/discord?return_to= → přesměrování na Discord OAuth2 (scope `identify`, `state` v HttpOnly cookie). GET /auth/discord/callback → relace `et_session` (HttpOnly, SameSite=Lax, Secure na https), 30 dní; v DB jen SHA-256 hash. POST /auth/logout.
- GET /auth/dev → vývojové přihlášení; jen `import.meta.env.DEV` a loopback, v produkčním buildu neexistuje.
- POST /api/device/start body {name} → {deviceCode,userCode,verificationUri,verificationUriComplete,expiresIn,interval}; bez účtu, kód platí 10 min.
- GET /api/pairing?code= (session) → {userCode,name,expiresAt}. POST /api/pairing body {userCode,scopes,approve} (session + Origin) → potvrzení/odmítnutí.
- POST /api/device/poll body {deviceCode} → {status:"pending",interval} | {status:"approved",token,deviceId,scopes,user}; token se vydá jen jednou (podmíněný UPDATE), uloží se jen jeho hash.
- POST /api/device/upload, `Authorization: Bearer etd_…`, body {export} → jako /api/uploads. Server najde nebo vytvoří grant pro (producerId, consentEpoch) s průnikem oblastí exportu a oblastí povolených při párování, projektuje a ukládá. Odvolaná epocha → `consent_revoked`.
- GET /api/devices, DELETE /api/devices/{id} (session) → seznam a odpojení zařízení.

Chyby {error:{code,message}}; zprávy jsou anglicky, web je překládá podle `code`. Origin check pro zápisy přes cookie; endpointy aplikace cookies nepoužívají.

## Nasazení a ověření 0.4.0

Veřejný cíl `https://evertally.afstudio.dev` je nasazený jako Cloudflare Worker `evertally` s D1 `evertally-production` v jurisdikci EU. Nasazení 0.4.0 má Cloudflare verzi `7177013e-11b0-461b-9838-86d61c821a91`. HTTPS kontrola ověřila status 0.4.0, `auth.devLogin=false`, `auth.discord=true`, mapový manifest/katalogy a hashe staženého addonu, aplikace a instalátoru. Veřejná headless kontrola prošla 11 scénáři mapy/databáze/mobilu bez chyb stránky. Serverové Discord klíče jsou nastavené a HTTP 302 zahajuje OAuth s `identify`, HTTPS callbackem a zabezpečenou state cookie. Celý login kvůli hCaptcha zůstává neověřený; status a přesměrování jej nedokládají.

Distribuční nativní build má výchozí tento veřejný server; uložená konfigurace má přednost. Přímý vývojový Cargo build bez `EVERTALLY_SERVER` používá loopback. Aplikace 0.4.0 je skutečně nainstalovaná v `%LOCALAPPDATA%\Programs\Evertally`, s hash kontrolou GUI/watcheru a Run registrací; watcher běží bez viditelného okna. Addon 0.4.0 je souborově nainstalovaný s hash kontrolou a zálohou `backups/20261109-231144-927`. Nové ingame UI a skutečný automatický start při WoW nejsou provozně ověřené. 18 CPU náhledů a syntetické testy neověřují živý transport, login ani detekci bossů. Podrobné důkazy jsou v release reportech.

## Rozšíření 0.4.0: návštěvy a ochrana polohy

- `zone.visited` používá scope `world_facts` a strict payload `{mapId,mapSystem:"ui_map",mapName?}` bez x/y. Addon zaznamenává změnu oblasti, nikoli trasu hráče.
- Při sběru/exportu addonu, plánování uploadu Rustu a TypeScript projekci se odstraňují hráčské souřadnice při interakci. Veřejná projekce nesmí vrátit přesnou hráčskou polohu; historie s `player_interaction` nevytvoří pin ani v surovém detailu.
- Přesné body mapy jsou jen NPC s `unit_position` nebo oddělená statická data `origin:"catalog"`, `positionMethod:"npc_database"`. Referenční původ nelze získat tvrzením uvnitř hráčského uploadu.
- `GET /api/activity` vrací `{generatedAt,windowHours:24,minContributors:3,zones:[{mapId,mapSystem:"ui_map",contributors,observations,lastSeen?}]}`. Počítá různé přispívající účty s platným souhlasem, skrývá zóny pod třemi účty a zaokrouhluje čas na UTC den. Bez jmen, ID hráčů a souřadnic. Nejde o online populaci.
- `GET /api/profiles/:id` vrací viditelný profil, navštívené oblasti `{mapId,mapName,visits,lastVisited}` a omezené výpravy. Přístup je jen vlastníku nebo k veřejnému profilu s příslušnými aktivními souhlasy. Veřejné časy návštěv jsou po dnech; žádné x/y.

## Sdílené zdroje a instalace 0.4.0

`shared/assets` a webové `/media` používají stejné mapy, identity a katalogy. `maps/manifest.json` má explicitní C_Map UIMapID vazby; neznámé ID se neodhaduje. Podkladů je 60, z CASC wowf 1.60.1.70862 s DB2 metadaty 1.60.1.70291. Katalogy `{schemaVersion:1,entries:[]}` obsahují 10 315 itemů, 5 232 questů, 12 078 NPC, 32 dungeonových/raidových zdrojů a dva vlastní Evertally návody. NPC/quest base řádky nezahrnují QuestieDB runtime opravy; zdrojové notices a licence jsou součástí resources.

Native má devět pohledů a ingame UI devět karet. Databázové reference nejsou vlastní pozorování; filtry a stránkování neznamenají úplnost herních dat. Návody nejsou rozsáhlá kniha raidových strategií.

Primární distribuce je per-user Windows installer `EvertallySetup.exe`: GUI, background watcher, resources, Start/odinstalace a volitelná instalace addonů se zálohou. Windows Run cílí na `EvertallyBackground.exe`. Watcher po čtyřech sekundách kontroluje proces/cestu WoW Forever, jednou pro nový PID spustí GUI minimalizovaně a ruční zavření respektuje. Žádné čtení paměti, DLL injekce nebo vstupy do hry. Build installeru nic nespouští. Autoupdate není implementovaný; skutečné nasazení a provozní ověření nejsou odvozené ze samotné kompilace.

## Odpovědnosti

- Addon worker: `D:\addon\addon`, `D:\addon\tests\lua`, addon README; hlavní UI + sběrače + ingame přenos.
- Backend worker: `D:\addon\platform\app\api`, `platform\lib`, `platform\db`, `platform\drizzle`, backend/parsing testy. Vlastní event schema a parser ve workeru.
- Frontend worker: `D:\addon\platform\app\page.tsx`, `platform\app\globals.css`, `platform\components`, `platform\public` kromě generovaných downloadů. Vlastní vizuální UI a napojení API.
- Root: package setup/install, layout/metadata, hosting, build, propojení, balení, herní instalace a celkové ověření. Každý pracuje vedle ostatních, žádné revertování cizích úprav.


## Moje trasa a cech (0.5, jen lokálně)

- Nové scopes `own_track` a `guild_share`, obě ve výchozím stavu vypnuté. `guild_share` vyžaduje `own_character`: bez něj `projectExport` události cechu zahodí a `validateUpload` vrací `identity_scope_denied`. `own_track` bez `own_character` nese pseudonymní `producerId:own` jako `own_runs`.
- `track.path` `{mapId,mapSystem?,startedAt,points:[[sekundy od startedAt,x,y]…]}`, 1–120 bodů, x/y 0..1, `startedAt` nejvýš 300 s po `observedAt`. `guild.snapshot` `{guildName?,rankIndex?,rankName?,left?,roster?}`; `roster` (≤1000 `{name,rankIndex,level?,classId?}`) jen při `rankIndex===0` a s `guildName`. Prázdný payload se nesmí posílat (Lua prázdná tabulka se čte jako pole), proto `left:true`.
- Úložiště: trasy jsou běžná pozorování (`atlas_observations`, scope `own_track`), platí jen s živým grantem, který scope obsahuje; starší než 30 dní se mažou při nahrání (`pruneTracks`). Soupis cechu se z pozorování odstraňuje a žije v `et_guilds` (`roster` jako `[jméno,hodnost,level,classa]`); členství v `et_guild_members` (PK `guild_id,profile_id`), stavy `pending|active|declined|left`, sdílení `off|last|trail`. Migrace `0003_people.sql`.
- Viditelnost (`lib/people.ts`): člena vidí jiný člen jen když oba mají `active`, jsou v soupisu (nebo jsou jeho vlastník), člen sdílí a pozorování leží v grantu s `own_track` **i** `guild_share`. Trasa člena jen při `share=trail` (≤72 h). Vlastník soupisu = první guildmaster (podmíněný UPDATE); druhý ho nepřepíše.
- API (session + Origin u změn): `GET /api/track?hours=&profile=` (vlastní trasa), `DELETE /api/track?profile=` (smazat), `GET /api/guild`, `POST /api/guild/:id` `{profileId,action:join|share|leave,share?}`, `GET /api/guild/:id/trail?profile=&hours=`. `DELETE /api/me/data` navíc uvolní cech a členství.

## Skupiny, srazy a sociální zprávy v addonu (0.5, jen lokálně)

- Migrace `0004_circles_meets.sql`: `et_circles` (majitel, kód pozvánky, `closed_at`), `et_circle_members` (PK `circle_id,user_id`; `profile_id`, `share off|last|trail`), `et_meets`, `et_meet_rsvps`, `et_meet_access` (kdo otevřel odkaz).
- Skupina: kód 10 znaků (abeceda bez 0/O/1/I/L), nejvýš 40 členů, 5 vlastních a 12 členství na účet. Viditelnost polohy/trasy: oba členy skupiny, člen sdílí a pozorování leží v grantu s `own_track` **i** `own_character` (`lib/circles.ts`). Odchod/odebrání maže odpovědi na srazy skupiny; majitel odchodem předá skupinu nejdéle přítomnému, poslední odchod ji zavře.
- Sraz (`lib/meets.ts`): druh `meet|group|farm|trade|event|note`, místo `mapId,x,y` (UiMap + 0..1), `startsAt` (null = hned), `ends_at`, publikum `guild` (potvrzený člen), `circle` (člen) nebo `link` (kód, `et_meet_access`), kapacita 2–40, `data` `{ref,roles,wanted,offered}` (≤12 položek). Viditelnost se počítá jen z členství a odkazu; **odpověď sama přístup nedává** (oprava po testu: vyhozený člen sraz neviděl, i když odpověděl). Nejvýš 20 otevřených srazů na účet; smazání po týdnu od konce.
- API (session + Origin): `GET /api/guild` vrací `{guilds,circles}`; `POST /api/circles` `{name,profileId,share?}`, `POST /api/circles/join` `{code,profileId,share?}`, `POST /api/circles/:id` `{action:share|character|leave|rotate|close|kick,…}`, `GET /api/circles/:id/trail`; `GET|POST /api/meets` (`?code=` otevře odkaz a vrátí `opened`), `PATCH /api/meets/:id` (autor; `cancel:true`), `POST /api/meets/:id/rsvp` `{status:going|maybe|none,name?}`.
- Addon (`Social.lua`, `SocialUI.lua`), prefix `Evtly1`, zprávy `S|<typ>|…` ≤255 B přes stejnou frontu s limitem (`A.QueueSocial`): `Q|id|kinds` žádost (i/p/g), `N|id` odmítnutí, `A|id|kinds|díly` souhlas, `D|id|i|n|část` data po 200 B (≤60 dílů; `I1;E=slot:id,..;B=id*n,..;G=měď;P=…` nebo `T1;W=..;O=..;G=..;N=poznámka`), `R|id|ok|no|text` odpověď na návrh, `M|id|mapa|x|y|min|popisek` sraz (kanály WHISPER/PARTY/RAID/GUILD). Příjem: data jen na vlastní žádost od téhož hráče; návrhy max 1 za 20 s od hráče; žádosti ≤3 otevřené, TTL 120 s, po odmítnutí 45 s ticho; texty bez `| ; = ~`. Přijatá data jen v paměti (`A.social`), nikdy do `SavedVariables` ani exportu.


## Živá poloha, mapa a navigace v addonu (0.5, jen lokálně)

- Nastavení (výchozí `false`): `liveParty`, `liveGuild`, `mapPins`; `navPos` pozice šipky. Nic z toho se neexportuje ani nenahrává; web o tom neví.
- Zprávy (prefix `Evtly1`, `S|…`, ≤255 B, stejná fronta s limitem; položka fronty má volitelný `key` a novější zpráva se stejným klíčem nahradí čekající): `L|mapa|x1000|y1000|classa` (kanály PARTY, RAID, GUILD; ≥5 s mezi pohyby, 30 s signál), `E` konec sdílení (jen z téhož kanálu, odkud přišel signál), `P|id|mapa|x|y|text` ping (TTL 5 min, ≤20 najednou, ≥5 s od téhož odesílatele). Příjem ověřuje rozsahy (`mapa` 1–100000, `x,y` 0–1000), kanál, odesílatele (ne já), limit 120 lidí a ≥2 s mezi signály jednoho odesílatele; TTL signálu 120 s.
- `Evertally_Map` (`## LoadOnDemand: 1`, `## Dependencies: Evertally`): `Libs/` (LibStub, CallbackHandler, HereBeDragons + Pins), `Data.lua` (generuje `tools/build_map_lua.py` z `travel.json`, `flights.json`, `world.json`), `Planner.lua` (port `travel.ts`; kontrola proti `tests/lua/fixtures/journeys.json`, který generuje `tools/dump_journeys.mjs` a hlídá `platform/tests/planner-fixture.test.ts`), `Navigator.lua`, `Pins.lua`. `A.map` se nastaví až na konci `Pins.lua`; hlavní addon `A.LoadMap()` bere „načteno“ jen s `A.map`.
- Směr šipky: pozice v yardech podle `travel.yards` (x na sever, y na západ); `bearing = atan2(dy, dx)` je proti směru hodin od severu jako `GetPlayerFacing`; `rotace = bearing − facing`, `Texture:SetRotation` (kladné = proti směru hodin).
- Globály, které addon zapisuje (vše nové názvy, žádný Blizzardí): `EvertallyDB`, `EvertallyPeersDB`, `SLASH_EVERTALLY1/2`, `BINDING_HEADER_EVERTALLY`, `BINDING_NAME_EVERTALLY_PING`, `BINDING_NAME_EVERTALLY_STOPNAV`, `Evertally_Ping`, `Evertally_StopNav`; test `test_addon_writes_no_blizzard_global…` seznam hlídá.

## Chůze po terénu na webu (0.5, jen lokálně)

- `platform/public/media/world/walk.bin` (`tools/build_walkmask.py`): `"EVWM"`, u8 verze 1, u8 počet map; pro každou: i16 id mapy (0 Eastern Kingdoms, 1 Kalimdor, 2991 Zephras Isle), f32 `x0`, f32 `y0` (roh buňky 0 v yardech), f32 velikost buňky (≈15,9 yd), u16 `nx`, u16 `ny`, u32 délka, zlib data `nx × ny` bajtů, x-major (x = sever, y = západ jako `UnitPosition`), hodnota 0 zablokováno / 1 země / 2 voda. Z původní mřížky 8 yd; blok 2×2 je země, jakmile v něm je kus země, jinak voda, jinak zablokováno.
- `db/terrain.ts`: `parseWalk` (potřebuje `DecompressionStream`), `findPath(map, [x, y], [x, y])` s oknem 90 buněk, pak 400, pak celá mapa; 8 směrů bez řezání rohů, voda stojí ×3, koncový bod v blokované buňce se přesune na nejbližší volnou do 14 buněk; výsledek `{points, yards (nakreslená vyhlazená čára), grid (délka po buňkách), snapped}`.
- `db/ground.ts`: `groundJourney(journey, travel, walk, options)` doplní pod každou pěší část (`Step.legs`) skutečnou čáru; upečená chůze mezi pevnými místy si drží čas, odhadovaná (z/do volného bodu) dostane `grid × GROUND_FACTOR / rychlost`. `Step.ground` říká, že čára sleduje terén.

