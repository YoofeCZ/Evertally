"use client";
// English is the primary language; Czech is optional. The choice lives in localStorage.
import { useCallback, useSyncExternalStore } from "react";

export type Lang = "en" | "cs";
const STORAGE_KEY = "et_lang";
const CHANGE_EVENT = "et-lang-change";

const detailText = {
  en: {
    "nav.database": "Database", "nav.professions": "Professions", "prof.title": "Your professions", "prof.lead": "Private profession snapshots, observed crafting and recipe cooldowns.",
    "prof.signInTitle": "Your crafting journal is private", "prof.signInText": "Sign in to see the profession data you chose to share. Other players cannot browse this page's data.",
    "prof.character": "Character / source", "prof.anonymous": "Unnamed source {number}", "prof.emptyTitle": "No profession observations yet", "prof.emptyText": "Open your profession book in game with profession export enabled, then /reload or log out and sync your approved export.",
    "prof.freshness": "Snapshots describe the moment they were recorded. Earlier crafting and recipes that were never observed are not reconstructed.",
    "prof.sample": "Showing {sample} of {total} retained profession observations.", "prof.truncated": "This response is limited in size. The page shows a recent sample, not your complete crafting history.",
    "prof.skill": "Observed skill", "prof.recorded": "Recorded", "prof.search": "Recipe name or recipe/item ID…", "prof.learnedOnly": "Learned recipes only", "prof.recipes": "Observed recipes", "prof.learned": "Learned", "prof.notLearned": "Not learned", "prof.learning": "Learning state", "prof.recipe": "Recipe", "prof.recipeCount": "Showing {count} of {total} matching recipes.", "prof.noRecipes": "No recipes in this snapshot match your search.",
    "prof.crafts": "Crafting observations", "prof.units": "Known crafted units", "prof.craftNote": "Counts cover the retained observations, not lifetime production. Missing quantities remain unknown.", "prof.recentCrafts": "Recent recorded crafting", "prof.output": "Observed output item", "prof.noCrafts": "No matching crafting observations in this sample.",
    "prof.cooldowns": "Recipe cooldowns", "prof.remaining": "Remaining from snapshot", "prof.readyAt": "Recorded ready time", "prof.ready": "Ready according to snapshot", "prof.cooldownNote": "This countdown uses the last saved ready time and your device clock. Crafting again or a game change can make that snapshot outdated.", "prof.noCooldowns": "No matching cooldown observations in this sample.", "prof.refresh": "Refresh saved data",
    "runs.period": "Period", "runs.allTime": "All saved history", "runs.week": "Last 7 days", "runs.month": "Last 30 days", "runs.quarter": "Last 90 days",
    "runs.minLevel": "Minimum level", "runs.maxLevel": "Maximum level", "runs.finish": "Finish type", "runs.allFinishes": "All finish types", "runs.difficulty": "Difficulty", "runs.allDifficulties": "All difficulties",
    "runs.statVisits": "Recorded participations", "runs.statCompleted": "Recorded finishes", "runs.statUnfinished": "Interrupted / manual", "runs.statBest": "Best observed time", "runs.statMedian": "Typical observed time",
    "runs.statsNote": "These are player participations; several players can report the same group visit. Counts follow your current filters.",
    "runs.timingGuide": "Times are summarized only for one instance, difficulty and finish type. Missing or interrupted measurements are excluded.",
    "runs.timingSample": "Time sample: {count} completed observations. Typical time is the median, not a verified speed ranking.",
    "result.abandoned": "Abandoned", "result.completed_unknown": "Finished · clear unknown",
    "detail.open": "Show details for {name}", "detail.runTitle": "Run record", "detail.entityTitle": "World sighting details",
    "detail.runNote": "This is an addon observation. A final-boss finish does not prove a full clear; race and class describe the participant, not group performance.",
    "detail.started": "Started", "detail.ended": "Ended", "detail.instanceId": "Instance ID", "detail.difficulty": "Difficulty ID", "detail.groupSize": "Observed group size", "detail.groupLevels": "Observed group levels", "detail.deaths": "Recorded deaths", "detail.ruleset": "Ruleset", "detail.evidence": "Recorded through", "detail.characterLevel": "Level at this visit", "detail.realm": "Realm", "detail.build": "Game build",
    "detail.apiEvent": "Game event", "detail.apiSnapshot": "API snapshot", "detail.manual": "Manual action", "detail.bossTimeline": "Recorded bosses and splits", "detail.sinceStart": "since recorded start", "detail.noBosses": "No boss events are available in this record.", "detail.unnamedBoss": "Unnamed boss",
    "detail.entityNote": "Fields come from the latest retained sighting. Missing details are unknown; vendor stock and positions can change.",
    "detail.sightings": "Recorded sightings", "detail.mapId": "Map ID", "detail.coordinates": "Coordinates", "detail.positionMethod": "Position method", "detail.playerLocation": "Player position during interaction", "detail.unitLocation": "Observed unit position", "detail.questGiver": "Observed quest NPC ID", "detail.questXp": "Observed quest XP", "detail.questMoney": "Observed reward", "detail.npcLevel": "Observed NPC level", "detail.quantity": "Quantity", "detail.lootSource": "Observed source type", "detail.sourceNpc": "Source NPC ID", "detail.sourceCertain": "Source confirmed by collector", "detail.yes": "Yes", "detail.no": "No", "detail.corpse": "Corpse", "detail.object": "World object", "detail.gathering": "Gathering", "detail.craft": "Crafting", "detail.vendorStock": "Latest observed vendor stock", "detail.price": "Observed price", "detail.unlimited": "Unlimited", "detail.firstHundred": "Showing the first 100 items from this vendor snapshot.",
    "community.copy": "Copy for the addon", "community.download": "Download JSON", "community.copied": "Copied. Open /etally → Community → Import data and paste this package.", "community.manualCopy": "Copy this package manually, then open /etally → Community → Import data.", "community.package": "Community package", "community.help": "This package contains shared world facts for the addon's Community tab. It stays separate from your own observations.",
  },
  cs: {
    "nav.database": "Databáze", "nav.professions": "Profese", "prof.title": "Tvoje profese", "prof.lead": "Soukromé snímky profesí, pozorovaná výroba a cooldowny receptů.",
    "prof.signInTitle": "Tvůj řemeslnický deník je soukromý", "prof.signInText": "Přihlas se k údajům o profesích, jejichž sdílení jsi povolil. Ostatní hráči si data této stránky prohlížet nemohou.",
    "prof.character": "Postava / zdroj", "prof.anonymous": "Nepojmenovaný zdroj {number}", "prof.emptyTitle": "Zatím žádná pozorování profesí", "prof.emptyText": "Ve hře otevři knihu profese se zapnutým exportem profesí, dej /reload nebo se odhlas a synchronizuj povolený export.",
    "prof.freshness": "Snímky popisují okamžik záznamu. Starší výrobu a recepty, které nebyly pozorovány, zpětně nedopočítáváme.",
    "prof.sample": "Zobrazeno {sample} z {total} uchovaných pozorování profesí.", "prof.truncated": "Velikost odpovědi je omezená. Stránka ukazuje nedávný vzorek, nikoli úplnou historii výroby.",
    "prof.skill": "Pozorovaná dovednost", "prof.recorded": "Zaznamenáno", "prof.search": "Název receptu nebo ID receptu/předmětu…", "prof.learnedOnly": "Pouze naučené recepty", "prof.recipes": "Pozorované recepty", "prof.learned": "Naučeno", "prof.notLearned": "Nenaučeno", "prof.learning": "Stav naučení", "prof.recipe": "Recept", "prof.recipeCount": "Zobrazeno {count} z {total} odpovídajících receptů.", "prof.noRecipes": "Žádný recept tohoto snímku neodpovídá hledání.",
    "prof.crafts": "Pozorování výroby", "prof.units": "Známé vyrobené kusy", "prof.craftNote": "Počty zahrnují uchovaná pozorování, nikoli celoživotní výrobu. Chybějící množství zůstává neznámé.", "prof.recentCrafts": "Poslední zaznamenaná výroba", "prof.output": "Pozorovaný výsledný předmět", "prof.noCrafts": "V tomto vzorku nejsou odpovídající pozorování výroby.",
    "prof.cooldowns": "Cooldowny receptů", "prof.remaining": "Zbývá podle snímku", "prof.readyAt": "Zaznamenaný čas dokončení", "prof.ready": "Připraveno podle snímku", "prof.cooldownNote": "Odpočet používá poslední uložený čas dokončení a hodiny zařízení. Další výroba či změna ve hře může snímek zneaktuálnit.", "prof.noCooldowns": "V tomto vzorku nejsou odpovídající pozorování cooldownů.", "prof.refresh": "Načíst uložená data",
    "runs.period": "Období", "runs.allTime": "Celá uložená historie", "runs.week": "Posledních 7 dnů", "runs.month": "Posledních 30 dnů", "runs.quarter": "Posledních 90 dnů",
    "runs.minLevel": "Minimální level", "runs.maxLevel": "Maximální level", "runs.finish": "Typ dokončení", "runs.allFinishes": "Všechny typy dokončení", "runs.difficulty": "Obtížnost", "runs.allDifficulties": "Všechny obtížnosti",
    "runs.statVisits": "Zaznamenané účasti", "runs.statCompleted": "Zaznamenaná dokončení", "runs.statUnfinished": "Přerušené / ruční", "runs.statBest": "Nejlepší pozorovaný čas", "runs.statMedian": "Obvyklý pozorovaný čas",
    "runs.statsNote": "Jde o účasti hráčů; jednu skupinovou návštěvu může zaznamenat více hráčů. Počty odpovídají aktuálním filtrům.",
    "runs.timingGuide": "Časy shrnujeme pouze pro jednu instanci, obtížnost a typ dokončení. Chybějící a přerušená měření vynecháváme.",
    "runs.timingSample": "Počet dokončených pozorování ve vzorku časů: {count}. Obvyklý čas je medián, nikoli ověřený rychlostní žebříček.",
    "result.abandoned": "Opuštěno", "result.completed_unknown": "Ukončeno · vyčištění neznámé",
    "detail.open": "Zobrazit podrobnosti: {name}", "detail.runTitle": "Záznam výpravy", "detail.entityTitle": "Podrobnosti pozorování světa",
    "detail.runNote": "Jde o pozorování addonu. Dokončení posledního bosse nedokládá úplné vyčištění; rasa a classa popisují účastníka, nikoli výkon skupiny.",
    "detail.started": "Začátek", "detail.ended": "Konec", "detail.instanceId": "ID instance", "detail.difficulty": "ID obtížnosti", "detail.groupSize": "Pozorovaná velikost skupiny", "detail.groupLevels": "Pozorované levely skupiny", "detail.deaths": "Zaznamenaná úmrtí", "detail.ruleset": "Pravidlový systém", "detail.evidence": "Způsob záznamu", "detail.characterLevel": "Level při této návštěvě", "detail.realm": "Realm", "detail.build": "Build hry",
    "detail.apiEvent": "Herní událost", "detail.apiSnapshot": "Snímek API", "detail.manual": "Ruční akce", "detail.bossTimeline": "Zaznamenaní bossové a mezičasy", "detail.sinceStart": "od zaznamenaného začátku", "detail.noBosses": "V tomto záznamu nejsou dostupné žádné události bossů.", "detail.unnamedBoss": "Boss bez názvu",
    "detail.entityNote": "Údaje pocházejí z posledního uchovaného pozorování. Chybějící podrobnosti nejsou známé; nabídka obchodníka i polohy se mohou měnit.",
    "detail.sightings": "Zaznamenaná pozorování", "detail.mapId": "ID mapy", "detail.coordinates": "Souřadnice", "detail.positionMethod": "Způsob určení polohy", "detail.playerLocation": "Poloha hráče při interakci", "detail.unitLocation": "Pozorovaná poloha jednotky", "detail.questGiver": "ID pozorovaného úkolového NPC", "detail.questXp": "Pozorované zkušenosti z úkolu", "detail.questMoney": "Pozorovaná odměna", "detail.npcLevel": "Pozorovaný level NPC", "detail.quantity": "Množství", "detail.lootSource": "Pozorovaný typ zdroje", "detail.sourceNpc": "ID zdrojového NPC", "detail.sourceCertain": "Zdroj potvrzený sběračem", "detail.yes": "Ano", "detail.no": "Ne", "detail.corpse": "Mrtvola", "detail.object": "Herní objekt", "detail.gathering": "Sběr", "detail.craft": "Výroba", "detail.vendorStock": "Poslední pozorovaná nabídka obchodníka", "detail.price": "Pozorovaná cena", "detail.unlimited": "Neomezeně", "detail.firstHundred": "Zobrazeno prvních 100 předmětů tohoto snímku obchodníka.",
    "community.copy": "Kopírovat pro addon", "community.download": "Stáhnout JSON", "community.copied": "Zkopírováno. Otevři /etally → Komunita → Načíst data a vlož tento balíček.", "community.manualCopy": "Zkopíruj balíček ručně a otevři /etally → Komunita → Načíst data.", "community.package": "Komunitní balíček", "community.help": "Balíček obsahuje sdílená fakta o světě pro kartu Komunita v addonu. Zůstává oddělený od tvých vlastních pozorování.",
  },
} as const;

const en = {
  ...detailText.en,
  "nav.overview": "Overview", "nav.runs": "Runs", "nav.rankings": "Rankings", "nav.atlas": "Map", "nav.sync": "Sync", "nav.account": "Account",
  "nav.signIn": "Sign in with Discord", "nav.signOut": "Sign out", "nav.devSignIn": "Dev sign-in", "nav.language": "Language",
  "brand.tagline": "Dungeon history, world atlas and community rankings for WoW Forever",
  "hero.tag": "Built for World of Warcraft Forever",
  "hero.title": "Every run, every discovery,", "hero.titleAccent": "kept on the record.",
  "hero.subtitle": "The Evertally addon records your dungeons, quests and finds in game. The desktop app brings them here, quietly, after every session.",
  "hero.download": "Get the addon", "hero.sync": "Set up auto sync",
  "board.title": "Community board", "board.runs": "RUNS", "board.characters": "HEROES", "board.observations": "SIGHTINGS", "board.updated": "Last data",
  "board.note": "Counts come from players who chose to share. Not a full picture of the realm.",
  "chapter.runs.tag": "Dungeons & raids", "chapter.runs.title": "Your runs, timed and remembered.",
  "chapter.runs.lead": "Bosses, deaths, group size and duration for every visit. Interrupted measurements stay marked, never dressed up as records.",
  "triad.boss.title": "Last boss detection", "triad.boss.text": "Killing the final boss closes the run automatically, marked as a candidate until verified in game.",
  "triad.clear.title": "Full clear", "triad.clear.text": "All required bosses down. Counted separately from a last-boss finish.",
  "triad.honest.title": "Honest timing", "triad.honest.text": "A /reload or disconnect breaks the timer. Such runs stay in history, never in records.",
  "chapter.atlas.tag": "World atlas", "chapter.atlas.title": "A map of Azeroth, built from sightings.",
  "chapter.atlas.lead": "Quests, NPCs, vendors and loot seen by players. A count of sightings is not a drop rate, and we never pretend it is.",
  "chapter.community.tag": "Community", "chapter.community.title": "Rankings with context.",
  "chapter.community.lead": "Time belongs to the whole group. Race and class are filters, not a measure of skill.",
  "chapter.privacy.title": "Yours in game. On the web only if you say so.",
  "chapter.privacy.lead": "Without an account the addon still works fully. Data received from other players is never forwarded to the web.",
  "cta.title": "Your expedition starts in game.", "cta.subtitle": "Install the addon, pair the desktop app once, and play.", "cta.button": "Start now",
  "common.learnMore": "Learn more", "common.viewAll": "View all", "common.loading": "Loading…", "common.close": "Close", "common.cancel": "Cancel",
  "common.noData": "No data yet", "common.unknown": "Unknown", "common.private": "Private character", "common.search": "Search",
  "runs.title": "Runs", "runs.lead": "Recorded participations in dungeons and raids.", "runs.community": "Community", "runs.mine": "My history",
  "runs.searchPlaceholder": "Dungeon or character…", "runs.dungeon": "Dungeon", "runs.character": "Character", "runs.date": "Date", "runs.time": "Time", "runs.result": "Result",
  "runs.allInstances": "All instances", "runs.allClasses": "All classes", "runs.allRaces": "All races", "runs.class": "Class", "runs.race": "Race",
  "runs.emptyTitle": "The first run is yet to come", "runs.emptyText": "Public runs appear here once players share them. One group run can produce several reports.",
  "runs.noMatch": "No run matches these filters", "runs.boss.one": "boss", "runs.boss.few": "bosses", "runs.boss.many": "bosses",
  "result.full_clear": "Full clear", "result.last_boss": "Last boss", "result.interrupted": "Interrupted", "result.manual": "Manual", "result.visiting": "Visit",
  "rankings.title": "Rankings", "rankings.lead": "Completed runs of public characters.", "rankings.count": "Completions", "rankings.time": "Fastest times",
  "rankings.sample": "Sample", "rankings.rank": "Rank", "rankings.timeEmpty": "Speed records need a ruleset verified in game. Personal times stay in your history.",
  "rankings.countEmpty": "Rankings fill up as players share completed runs.",
  "atlas.title": "World atlas", "atlas.lead": "Things players have seen in the world.", "atlas.searchPlaceholder": "Name, quest, item or game ID…",
  "atlas.all": "Everything", "atlas.quest": "Quests", "atlas.npc": "NPCs", "atlas.item": "Items", "atlas.sightings": "Sightings", "atlas.lastSeen": "Last seen",
  "atlas.emptyTitle": "Azeroth awaits its first sighting", "atlas.emptyText": "Quests, NPCs and loot shared by players build the atlas over time.",
  "atlas.dropNote": "A sighting count is not a drop rate.", "atlas.snapshot": "Download data snapshot",
  "sync.title": "Sync", "sync.lead": "WoW addons cannot reach the internet. The game saves your data to a file when you /reload or log out; the desktop app picks it up from there.",
  "sync.app.tag": "Background bridge", "sync.app.title": "Evertally Bridge for Windows", "sync.app.text": "A small bridge in the Windows notification area connects your addon to the website. Open Web sync from its icon to pair this PC and manage the connection. Map, database and player tools are here on the web.",
  "sync.app.download": "Download Windows installer", "sync.app.step1": "Install Evertally. The installer can also install the addon and enable Start with WoW. Web sharing remains optional.",
  "sync.app.step2": "Find Evertally next to the Windows clock (or under the up arrow). Open Web sync and choose Pair this PC.", "sync.app.step3": "Sign in with Discord, choose what to share and approve.",
  "sync.app.step4": "Play. After each /reload or logout new records arrive here automatically.",
  "sync.manual.title": "Manual import", "sync.manual.text": "No app? Choose the export file yourself. It is read in your browser first; nothing is sent until you confirm.",
  "sync.manual.choose": "Choose export file", "sync.manual.where": "Evertally_Export.lua is in _forever_/WTF/Account/<account>/SavedVariables.",
  "sync.manual.loaded": "{count} records loaded locally. Nothing has been sent yet.", "sync.manual.consent": "I agree to send the selected records of my own to Evertally.",
  "sync.manual.send": "Send selected", "sync.manual.signIn": "Sign in to send data. The preview works without an account.",
  "sync.manual.result": "Accepted {accepted}, already stored {duplicates}.", "sync.manual.disabled": "Web sharing is turned off in this export. Enable it in game first.",
  "scope.world_facts": "World sightings", "scope.world_facts.help": "Quests, NPCs, vendors and loot you saw.",
  "scope.own_runs": "My runs", "scope.own_runs.help": "Dungeon times, bosses and results.",
  "scope.own_character": "My characters", "scope.own_character.help": "Name, realm, level, race and class. Profiles stay private until you publish them.",
  "scope.own_professions": "My professions", "scope.own_professions.help": "Recipes, crafting and cooldowns.",
  "scope.own_track": "My route", "scope.own_track.help": "Where your characters walked, as map points. Only you see it, unless you also share with your guild. Kept for 30 days.",
  "scope.guild_share": "My guild", "scope.guild_share.help": "Which guild your character is in and, for a guild master, the member list. Needs the character scope. Nothing is shown to the guild until you confirm it on the map.",
  "link.title": "Pair Evertally Sync", "link.lead": "Confirm the code shown by the app on your computer.", "link.code": "Pairing code", "link.check": "Continue",
  "link.device": "Device", "link.choose": "What may this app send?", "link.approve": "Approve and pair", "link.deny": "Decline",
  "link.approved": "Paired. You can close this tab; the app will continue on its own.", "link.denied": "Pairing declined.",
  "link.signIn": "Sign in with Discord to pair the app.", "link.mismatch": "Make sure the code matches the one in the app. Never approve a code someone sent you.",
  "account.title": "Account", "account.lead": "Your characters, paired apps and consents.", "account.profiles": "Character visibility",
  "account.profilesEmpty": "Your characters appear here after you share character details.", "account.public": "Public", "account.private": "Private",
  "account.devices": "Paired apps", "account.devicesEmpty": "No app is paired yet.", "account.lastSeen": "Last upload", "account.unpair": "Disconnect",
  "account.grants": "Consents", "account.grantsEmpty": "No active consent.", "account.revoke": "Revoke",
  "account.delete": "Delete my web data", "account.deleteTitle": "Delete your web data?",
  "account.deleteText": "Your uploaded records, web profiles, consents and paired apps are removed. Your history in the game addon stays untouched.",
  "account.deleteConfirm": "Delete web data", "account.deleted": "Your web data was deleted.",
  "account.signInTitle": "Sign in to manage your data", "account.signInText": "Evertally uses Discord only to know who you are. We never see your Discord messages or friends.",
  "footer.note": "Community observations, not the full state of the server. Fan project, not affiliated with Blizzard Entertainment.",
  "footer.status": "Evertally {version} · data only from players who opted in",
  "auth.discord_not_configured": "Discord sign-in is not configured on this server yet.", "auth.discord_denied": "Discord sign-in was cancelled.",
  "auth.invalid_state": "The sign-in link expired. Try again.", "auth.discord_token": "Discord did not confirm the sign-in. Try again.", "auth.discord_profile": "Could not read your Discord profile.",
  "error.generic": "Something went wrong. Try again.", "error.unauthorized": "Sign in first.", "error.code_expired": "This code expired. Start pairing again in the app.",
  "error.code_used": "This code was already used.", "error.invalid_code": "That is not a valid code.", "error.service_unavailable": "The database is not available right now.",
  "error.invalid_scopes": "Choose at least one kind of data.",
} as const;

export type Key = keyof typeof en;

const cs: Record<Key, string> = {
  ...detailText.cs,
  "nav.overview": "Přehled", "nav.runs": "Běhy", "nav.rankings": "Žebříčky", "nav.atlas": "Mapa", "nav.sync": "Synchronizace", "nav.account": "Účet",
  "nav.signIn": "Přihlásit přes Discord", "nav.signOut": "Odhlásit", "nav.devSignIn": "Vývojové přihlášení", "nav.language": "Jazyk",
  "brand.tagline": "Historie dungeonů, atlas světa a komunitní žebříčky pro WoW Forever",
  "hero.tag": "Pro World of Warcraft Forever",
  "hero.title": "Každý běh, každý objev,", "hero.titleAccent": "zapsaný napořád.",
  "hero.subtitle": "Addon Evertally zaznamenává ve hře tvoje dungeony, questy a nálezy. Desktopová aplikace je sem po každém hraní potichu přenese.",
  "hero.download": "Stáhnout addon", "hero.sync": "Nastavit automatickou synchronizaci",
  "board.title": "Komunitní tabule", "board.runs": "BĚHY", "board.characters": "HRDINOVÉ", "board.observations": "POZOROVÁNÍ", "board.updated": "Poslední data",
  "board.note": "Počty pocházejí od hráčů, kteří se rozhodli sdílet. Nejde o úplný obraz serveru.",
  "chapter.runs.tag": "Dungeony & raidy", "chapter.runs.title": "Tvoje běhy, změřené a zapamatované.",
  "chapter.runs.lead": "Bossové, smrti, velikost skupiny a délka každé návštěvy. Přerušené měření zůstane označené a nikdy se nevydává za rekord.",
  "triad.boss.title": "Detekce posledního bosse", "triad.boss.text": "Zabití posledního bosse běh automaticky uzavře; do ověření ve hře je označený jako kandidát.",
  "triad.clear.title": "Full clear", "triad.clear.text": "Všichni povinní bossové padli. Počítá se zvlášť od dokončení posledním bossem.",
  "triad.honest.title": "Poctivé měření", "triad.honest.text": "/reload nebo odpojení přeruší měření. Takový běh zůstane v historii, nikdy v rekordech.",
  "chapter.atlas.tag": "Atlas světa", "chapter.atlas.title": "Mapa Azerothu složená z pozorování.",
  "chapter.atlas.lead": "Questy, NPC, obchodníci a loot, které hráči viděli. Počet pozorování není drop rate a nikdy to tak nevydáváme.",
  "chapter.community.tag": "Komunita", "chapter.community.title": "Žebříčky s kontextem.",
  "chapter.community.lead": "Čas patří celé skupině. Rasa a classa jsou filtry, ne měřítko dovednosti.",
  "chapter.privacy.title": "Ve hře tvoje. Na webu, jen když chceš.",
  "chapter.privacy.lead": "Bez účtu addon funguje naplno. Data přijatá od ostatních hráčů se na web nikdy nepřeposílají.",
  "cta.title": "Tvoje výprava začíná ve hře.", "cta.subtitle": "Nainstaluj addon, jednou spáruj desktopovou aplikaci a hraj.", "cta.button": "Začít",
  "common.learnMore": "Více", "common.viewAll": "Zobrazit vše", "common.loading": "Načítám…", "common.close": "Zavřít", "common.cancel": "Zrušit",
  "common.noData": "Zatím žádná data", "common.unknown": "Neznámé", "common.private": "Soukromá postava", "common.search": "Hledat",
  "runs.title": "Běhy", "runs.lead": "Zaznamenané účasti v dungeonech a raidech.", "runs.community": "Komunita", "runs.mine": "Moje historie",
  "runs.searchPlaceholder": "Dungeon nebo postava…", "runs.dungeon": "Dungeon", "runs.character": "Postava", "runs.date": "Datum", "runs.time": "Čas", "runs.result": "Výsledek",
  "runs.allInstances": "Všechny instance", "runs.allClasses": "Všechny classy", "runs.allRaces": "Všechny rasy", "runs.class": "Classa", "runs.race": "Rasa",
  "runs.emptyTitle": "První běh teprve přijde", "runs.emptyText": "Veřejné běhy se tu objeví, jakmile je hráči nasdílí. Jeden skupinový běh může mít více záznamů.",
  "runs.noMatch": "Těmto filtrům neodpovídá žádný běh", "runs.boss.one": "boss", "runs.boss.few": "bossové", "runs.boss.many": "bossů",
  "result.full_clear": "Full clear", "result.last_boss": "Poslední boss", "result.interrupted": "Přerušeno", "result.manual": "Ručně", "result.visiting": "Návštěva",
  "rankings.title": "Žebříčky", "rankings.lead": "Dokončené běhy veřejných postav.", "rankings.count": "Dokončení", "rankings.time": "Nejrychlejší časy",
  "rankings.sample": "Vzorek", "rankings.rank": "Pořadí", "rankings.timeEmpty": "Rychlostní rekordy potřebují ruleset ověřený ve hře. Osobní časy zůstávají v historii.",
  "rankings.countEmpty": "Žebříčky se plní, jak hráči sdílí dokončené běhy.",
  "atlas.title": "Atlas světa", "atlas.lead": "Co hráči ve světě viděli.", "atlas.searchPlaceholder": "Jméno, quest, předmět nebo herní ID…",
  "atlas.all": "Vše", "atlas.quest": "Questy", "atlas.npc": "NPC", "atlas.item": "Předměty", "atlas.sightings": "Pozorování", "atlas.lastSeen": "Naposledy",
  "atlas.emptyTitle": "Azeroth čeká na první pozorování", "atlas.emptyText": "Questy, NPC a loot sdílené hráči postupně skládají atlas.",
  "atlas.dropNote": "Počet pozorování není drop rate.", "atlas.snapshot": "Stáhnout datový snapshot",
  "sync.title": "Synchronizace", "sync.lead": "Addony ve WoW nesmí na internet. Hra uloží data do souboru při /reload nebo odhlášení; odtud je vyzvedne desktopová aplikace.",
  "sync.app.tag": "Most na pozadí", "sync.app.title": "Evertally Bridge pro Windows", "sync.app.text": "Malý most vedle hodin Windows propojí addon s webem. Z jeho ikony otevřeš Web sync pro párování a správu spojení. Mapa, databáze a hráčské nástroje jsou tady na webu.",
  "sync.app.download": "Stáhnout instalátor pro Windows", "sync.app.step1": "Nainstaluj Evertally. Instalátor umí přidat addon a zapnout spouštění s WoW. Webové sdílení zůstává dobrovolné.",
  "sync.app.step2": "Najdi Evertally vedle hodin Windows nebo pod šipkou nahoru. Otevři Web sync a vyber Spárovat tento počítač.", "sync.app.step3": "Přihlas se přes Discord, vyber, co se smí posílat, a potvrď.",
  "sync.app.step4": "Hraj. Po každém /reload nebo odhlášení sem nové záznamy dorazí samy.",
  "sync.manual.title": "Ruční import", "sync.manual.text": "Bez aplikace? Vyber exportní soubor sám. Nejdřív se přečte v prohlížeči; nic se neodešle, dokud to nepotvrdíš.",
  "sync.manual.choose": "Vybrat exportní soubor", "sync.manual.where": "Evertally_Export.lua najdeš v _forever_/WTF/Account/<účet>/SavedVariables.",
  "sync.manual.loaded": "Načteno {count} místně. Zatím se nic neodeslalo.", "sync.manual.consent": "Souhlasím s odesláním vybraných vlastních záznamů do Evertally.",
  "sync.manual.send": "Odeslat vybrané", "sync.manual.signIn": "Pro odeslání se přihlas. Náhled funguje i bez účtu.",
  "sync.manual.result": "Přijato {accepted}, už uloženo {duplicates}.", "sync.manual.disabled": "V tomto exportu je webové sdílení vypnuté. Nejdřív ho zapni ve hře.",
  "scope.world_facts": "Pozorování světa", "scope.world_facts.help": "Questy, NPC, obchodníci a loot, které jsi viděl.",
  "scope.own_runs": "Moje běhy", "scope.own_runs.help": "Časy dungeonů, bossové a výsledky.",
  "scope.own_character": "Moje postavy", "scope.own_character.help": "Jméno, realm, level, rasa a classa. Profily zůstanou soukromé, dokud je nezveřejníš.",
  "scope.own_professions": "Moje profese", "scope.own_professions.help": "Recepty, výroba a cooldowny.",
  "scope.own_track": "Moje trasa", "scope.own_track.help": "Kudy tvoje postavy šly, jako body na mapě. Vidíš ji jen ty, pokud ji navíc nesdílíš s cechem. Uchovává se 30 dní.",
  "scope.guild_share": "Můj cech", "scope.guild_share.help": "V jakém cechu je postava a u guildmastera seznam členů. Vyžaduje oblast postav. Cechu se nic nezobrazí, dokud to nepotvrdíš na mapě.",
  "link.title": "Spárovat Evertally Sync", "link.lead": "Potvrď kód, který ukazuje aplikace na tvém počítači.", "link.code": "Párovací kód", "link.check": "Pokračovat",
  "link.device": "Zařízení", "link.choose": "Co smí tahle aplikace posílat?", "link.approve": "Potvrdit a spárovat", "link.deny": "Odmítnout",
  "link.approved": "Spárováno. Kartu můžeš zavřít, aplikace pokračuje sama.", "link.denied": "Párování odmítnuto.",
  "link.signIn": "Pro spárování aplikace se přihlas přes Discord.", "link.mismatch": "Ověř, že kód odpovídá kódu v aplikaci. Nikdy nepotvrzuj kód, který ti někdo poslal.",
  "account.title": "Účet", "account.lead": "Tvoje postavy, spárované aplikace a souhlasy.", "account.profiles": "Viditelnost postav",
  "account.profilesEmpty": "Postavy se tu objeví, až nasdílíš údaje postavy.", "account.public": "Veřejná", "account.private": "Soukromá",
  "account.devices": "Spárované aplikace", "account.devicesEmpty": "Zatím není spárovaná žádná aplikace.", "account.lastSeen": "Poslední upload", "account.unpair": "Odpojit",
  "account.grants": "Souhlasy", "account.grantsEmpty": "Žádný aktivní souhlas.", "account.revoke": "Odvolat",
  "account.delete": "Smazat moje webová data", "account.deleteTitle": "Smazat tvoje webová data?",
  "account.deleteText": "Odstraní se nahrané záznamy, webové profily, souhlasy a spárované aplikace. Historie v herním addonu zůstane beze změny.",
  "account.deleteConfirm": "Smazat webová data", "account.deleted": "Tvoje webová data byla smazána.",
  "account.signInTitle": "Pro správu dat se přihlas", "account.signInText": "Evertally používá Discord jen k tomu, aby věděl, kdo jsi. Tvoje zprávy ani přátele nevidíme.",
  "footer.note": "Komunitní pozorování, ne úplný stav serveru. Fanouškovský projekt, bez vazby na Blizzard Entertainment.",
  "footer.status": "Evertally {version} · data jen od hráčů, kteří sdílení povolili",
  "auth.discord_not_configured": "Přihlášení přes Discord zatím není na serveru nastavené.", "auth.discord_denied": "Přihlášení přes Discord bylo zrušeno.",
  "auth.invalid_state": "Přihlašovací odkaz vypršel. Zkus to znovu.", "auth.discord_token": "Discord přihlášení nepotvrdil. Zkus to znovu.", "auth.discord_profile": "Nepodařilo se načíst tvůj Discord profil.",
  "error.generic": "Něco se pokazilo. Zkus to znovu.", "error.unauthorized": "Nejdřív se přihlas.", "error.code_expired": "Kód vypršel. Spusť párování v aplikaci znovu.",
  "error.code_used": "Tento kód už byl použitý.", "error.invalid_code": "Tohle není platný kód.", "error.service_unavailable": "Databáze teď není dostupná.",
  "error.invalid_scopes": "Vyber aspoň jeden druh dat.",
};

const dictionaries: Record<Lang, Record<Key, string>> = { en, cs };

function readLang(): Lang {
  try {
    return window.localStorage.getItem(STORAGE_KEY) === "cs" ? "cs" : "en";
  } catch {
    return "en";
  }
}

function subscribe(onChange: () => void) {
  window.addEventListener(CHANGE_EVENT, onChange);
  window.addEventListener("storage", onChange);
  return () => {
    window.removeEventListener(CHANGE_EVENT, onChange);
    window.removeEventListener("storage", onChange);
  };
}

export function translate(lang: Lang, key: Key, vars?: Record<string, string | number>): string {
  let text = dictionaries[lang][key] ?? en[key];
  if (vars) for (const [name, value] of Object.entries(vars)) text = text.replaceAll(`{${name}}`, String(value));
  return text;
}

export function useI18n() {
  // The server always renders English; the stored choice applies right after hydration.
  const lang = useSyncExternalStore(subscribe, readLang, () => "en" as Lang);
  const setLang = useCallback((next: Lang) => {
    try { window.localStorage.setItem(STORAGE_KEY, next); } catch { /* private mode */ }
    document.documentElement.lang = next;
    window.dispatchEvent(new Event(CHANGE_EVENT));
  }, []);
  const t = useCallback((key: Key, vars?: Record<string, string | number>) => translate(lang, key, vars), [lang]);
  /** Czech has one / few (2–4) / many forms; English uses one / many. Keys: `${base}.one|few|many`. */
  const plural = useCallback((count: number, base: "runs.boss") => {
    const form = count === 1 ? "one" : lang === "cs" && count >= 2 && count <= 4 ? "few" : "many";
    return translate(lang, `${base}.${form}` as Key);
  }, [lang]);
  const locale = lang === "cs" ? "cs-CZ" : "en-GB";
  const num = useCallback((value?: number | null) => new Intl.NumberFormat(locale).format(value ?? 0), [locale]);
  const date = useCallback((value?: number | null) => value
    ? new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(value < 1e12 ? value * 1000 : value))
    : "—", [locale]);
  return { lang, setLang, t, plural, num, date };
}

export function hasKey(key: string): key is Key {
  return key in en;
}
