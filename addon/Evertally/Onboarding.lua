local _, A = ...
-- The setup: what a new player is asked on the first start (and anyone, any time, with /etally setup or the button in Settings), in
-- eleven steps: language, required installation, pairing with the app, website, what others see, position, sharing, map, window, nameplates and
-- summary. Nothing is chosen for
-- the player: every switch that sends something anywhere starts off, the wizard only shows what the current choices are (a quick choice for
-- the website sets the switches, and they stay visible). Nameplate choices are live; other choices apply at Finish.
local VERSION = 7   -- 7: the music step (Spotify or YouTube Music), so the setup opens once more for everyone
local W, H, HEADER, FOOTER, PAD = 880, 672, 64, 72, 28
A.DOWNLOAD_URL = "https://evertally.afstudio.dev/#sync"                  -- the Download page of the website (the app for Windows)
A.OPENMAP_URL = "https://www.curseforge.com/wow/addons/openmap"          -- OpenMap on CurseForge
local STEPS = {"welcome", "install", "pair", "website", "public", "live", "sharing", "map", "window", "nameplates", "music", "summary"}
local MUSIC = 11
local INSTALL, PAIR = 2, 3   -- the steps that hold the setup until the installation is verified and the app is paired
A.ONBOARDING_INSTALL_STEP = INSTALL
local SCOPES = {"world_facts", "own_runs", "own_character", "own_professions", "own_track"}
local KINDS = {"herb", "ore", "fishing", "container"}
local SCALES = {{"Small", 0.85}, {"Normal", 1}, {"Large", 1.2}}
local FIRST = 96   -- where the controls of a step start (under its title and text)

local text = {
    en = {
        setupTitle = "Evertally setup", setupStepOf = "Step %d of %d", setupBack = "Back", setupNext = "Next", setupFinish = "Finish", setupSkip = "Skip for now",
        setupOn = "on", setupOff = "off",
        -- 1
        setupWelcomeTitle = "Welcome to Evertally",
        setupWelcomeBody = "Evertally remembers your journey (quests, loot, places, dungeon runs), shows it in a clear window and, only if you want, shares it with your friends, your group and your website. This takes a minute.",
        setupLanguage = "Language", setupExisting = "The choices you have made so far are shown; change what you like.",
        setupPrivacy = "Nothing leaves your game unless you switch it on in the next steps. You can change everything later in Settings, or run this setup again with /etally setup.",
        -- 2
        setupWebTitle = "Your page on the website",
        setupWebBody = "Evertally can prepare your data for your page on the Evertally website. The game saves it when you /reload or log out, and the Evertally app for Windows uploads it. Without that app nothing is uploaded.",
        setupQuick = "Quick choice", setupPresetLocal = "Local only", setupPresetRecommended = "Recommended", setupPresetEverything = "Everything",
        setupWebMissing = "The helper add-on Evertally_Export is not enabled, so the website cannot be used yet. Enable it in the add-on list and reload; this switch will not turn on until then.",
        -- 3
        setupLiveTitle = "Your position",
        setupLiveBody = "Party, guild and friends who have the add-on see where you are while you play. Each switch is for one group of people and stays off until you turn it on.",
        setupLiveWeb = "Show my position on the website", setupLiveWebSub = "Not live: the app sends it when you change zone, log in or /reload, when someone asks “Where are you?” on the website, and otherwise at most every 5 minutes. For the app the game draws a small, near-black strip in its top-left corner.",
        setupLiveWebNeeds = "This also switches on: website data, my character and my route (the website needs them).",
        -- 4
        setupShareTitle = "Sharing with other players",
        setupShareBody = "Other Evertally players nearby can exchange short summaries (completed runs and a few facts). You decide who may get them, and you are asked every time somebody wants to look at your gear.",
        -- 5
        setupMapTitle = "Map and gathering",
        setupMapBodyOpenMap = "OpenMap is your map and Evertally works inside it: it adds the places where herbs, ore, fishing pools and chests can be and, if you allow it, other players, meets and pings.",
        setupMapBodyNone = "Evertally's map features are built on OpenMap, a free map add-on (CurseForge). It is not installed or not enabled. Install and enable it, then /reload; your choices here are kept.",
        setupGather = "Gathering places on the map", setupGatherSub = "Reference places, not live nodes. Every resource has its own picture.",
        setupKinds = "Show", setupKind_herb = "Herbs", setupKind_ore = "Ore", setupKind_fishing = "Fishing pools", setupKind_container = "Chests",
        setupWhere = "You find all of this again on the map: OpenMap's menu, tab On the map, section Evertally. Every single resource, with its picture, is in the Evertally window under World, Gathering.",
        -- 6
        setupWindowTitle = "The window", setupWindowBody = "How Evertally shows itself. You can open the window with /etally or the button at the minimap, and run this setup again with /etally setup.",
        setupSize = "Window size", setupSize_Small = "Small", setupSize_Normal = "Normal", setupSize_Large = "Large",
        -- 7
        setupPlatesTitle = "Friendly nameplates",
        setupPlatesBody = "Choose Blizzard or Evertally (recommended, close to the original look). Activate it, then adjust it with a live preview. Nameplate changes apply immediately.",
        setupSumPlates = "Evertally nameplates: %s; names %d px, marks %d px, logo %d px",
        setupSumMusic = "Music: %s",
        setupMusicTitle = "Music",
        setupMusicBody = "Your Spotify or YouTube Music inside the game: a small player, your playlists and liked songs, search, and quieter music while an NPC talks. The Evertally app on this PC plays it; nothing is sent anywhere else.",
        setupMusicOn = "Music player in the game", setupMusicOnSub = "Off by default. Needs the Evertally app running on this PC.",
        setupMusicSpotify = "The Spotify app. Your own free Client ID (below), Premium to start a chosen playlist.",
        setupMusicYoutube = "An app window of Chrome or Edge. Sign in to YouTube Music in it once.",
        setupMusicYoutubeHelp = "When you finish, the Evertally app opens YouTube Music in a window of its own (Chrome or Edge, with a separate profile). Sign in there once; then press Refresh library in the game's music window and Load library.",
        setupNotePlates = "The game could not switch friendly nameplates. Outside combat, enable them in Settings → Nameplates.",
        -- 8
        setupGetTitle = "What you need",
        setupGetBody = "The Evertally app and OpenMap are required. Verify their installation here at any time.",
        setupGetApp = "Evertally app for Windows",
        setupGetAppSub = "Sends your data and your position (not live) to your page on the website. Download it on the website, on the Download page:",
        setupGetOpenMap = "OpenMap add-on",
        setupGetOpenMapSub = "The map Evertally works in: gathering places with their icons, people, meets, pings and your journeys. Free, on CurseForge:",
        setupGetInstalled = "installed", setupGetMissing = "not installed",
        setupGetHow = "Use the download buttons, then reload the interface and verify the installation.",
        -- 9
        setupSumTitle = "All set", setupSumBody = "Nameplate changes already apply. Finish confirms the other choices below; you can change everything in Settings.",
        setupSumLanguage = "Language: %s", setupSumWeb = "Website: %s", setupSumLive = "Position shared with: %s", setupSumShare = "Sharing with players: %s", setupSumMap = "Map: %s", setupSumGather = "Gathering on the map: %s",
        setupSumPins = "people, meets and pings on the map: %s", setupSumOpenMap = "OpenMap", setupSumNoOpenMap = "OpenMap (not installed yet)", setupSumWindow = "Minimap button: %s, window size: %s", setupSumNothing = "nothing",
        setupSumGuild = "guild", setupSumGroup = "party / raid", setupSumFriends = "friends", setupSumSite = "website",
        setupAppNote = "The app uploads what the game saved at /reload or logout. After Finish a button saves it right away.",
        setupSumChronicle = "Chronicle: %s", setupSumPublic = "Public page and leaderboard: %s",
        setupPublicTitle = "What others see on the website",
        setupPublicBody = "You always see your own data on the website when you sign in. Here you choose what everyone else may see.",
        setupPublicSub = "Your characters get a public page and appear in the website's leaderboards. Without it you are in no leaderboard and nothing below can be public.",
        setupChronicle = "Your chronicle (the journey to replay: route, quests, fights, loot)",
        setupChron_off = "Do not send", setupChronSub_off = "The route is not sent to the website, so there is no chronicle.",
        setupChron_private = "Only for me", setupChronSub_private = "Sent to the website, but only you see it when signed in. It is not in the public list.",
        setupChron_public = "Public", setupChronSub_public = "Anyone can replay it on the website. It needs the public page above, so it switches it on and puts you in the leaderboard.",
        setupChronLocked = "Your position on the website needs the route, so “Do not send” is not available while it is on.", setupSumApp = "App: %s; start with WoW: %s", setupSumPaired = "paired", setupSumUnpaired = "not paired",
        -- 2: pairing
        setupPairTitle = "Pair the app with the website",
        setupPairBody = "Your data reaches your page on the website only through the Evertally app for Windows, paired with your account. The setup continues once the app is paired.",
        setupPairNot = "The app is not paired yet.",
        setupPairWaiting = "Pairing requested. The pairing page opened in your browser (Alt+Tab): sign in with Discord and confirm the code, then press Verify.",
        setupPairOld = "The app did not report whether it is paired. Start the Evertally app (update it if it is older than 0.9.13), then press Verify.",
        setupPairDone = "The app is paired with your account.",
        setupPairButton = "Pair", setupPairVerify = "Verify",
        setupPairHelp = "Pair saves the request and reloads the interface. The running Evertally app (also when it hides by the clock) then opens pairing in your browser. If nothing opens, the app is not running: start it from the Start menu and press Pair again.",
        setupPairDoneHelp = "Nothing more to do here. You can unpair any time in the app.",
        bridgeAutostart = "Start the Evertally app with WoW",
        bridgeAutostartSub = "It waits in the background and starts by itself with the game, and only ever runs in the background. The app gets the choice once the game saves (Verify or /reload).",
        setupAutostartNow = "In the app now: %s",
        setupDone = "Setup finished. Open the window with /etally.", setupSkipped = "Setup skipped. /etally setup opens it again.", setupNoteExport = "The website switch stays off: the helper add-on Evertally_Export is not enabled.",
    },
    cs = {
        setupTitle = "Nastavení Evertally", setupStepOf = "Krok %d z %d", setupBack = "Zpět", setupNext = "Dál", setupFinish = "Dokončit", setupSkip = "Zatím přeskočit",
        setupOn = "zapnuto", setupOff = "vypnuto",
        setupWelcomeTitle = "Vítej v Evertally",
        setupWelcomeBody = "Evertally si pamatuje tvoji cestu (questy, loot, místa, běhy v dungeonech), ukáže ji v přehledném okně a jen když chceš, sdílí ji s přáteli, skupinou a webem. Zabere to minutu.",
        setupLanguage = "Jazyk", setupExisting = "Ukázané jsou tvoje dosavadní volby; změň, co chceš.",
        setupPrivacy = "Z tvé hry nic neodejde, dokud to v dalších krocích nezapneš. Všechno můžeš později změnit v Nastavení nebo toto nastavení spustit znovu příkazem /etally setup.",
        setupWebTitle = "Tvoje stránka na webu",
        setupWebBody = "Evertally umí připravit tvoje data pro tvoji stránku na webu Evertally. Hra je uloží při /reload nebo odhlášení a nahraje je aplikace Evertally pro Windows. Bez té aplikace se nic nenahraje.",
        setupQuick = "Rychlá volba", setupPresetLocal = "Jen tady", setupPresetRecommended = "Doporučené", setupPresetEverything = "Všechno",
        setupWebMissing = "Pomocný addon Evertally_Export není zapnutý, web proto zatím nejde použít. Zapni ho v seznamu addonů a načti znovu; tento přepínač se do té doby nezapne.",
        setupLiveTitle = "Tvoje poloha",
        setupLiveBody = "Parta, cech a přátelé, kteří mají addon, vidí, kde jsi, průběžně při hraní. Každý přepínač je pro jednu skupinu lidí a je vypnutý, dokud ho nezapneš.",
        setupLiveWeb = "Ukazovat moji polohu na webu", setupLiveWebSub = "Není živá: aplikace ji pošle při změně lokace, přihlášení nebo /reload, když se na webu někdo zeptá „Kde jsi?“, a jinak nejvýš jednou za 5 minut. Hra pro aplikaci kreslí malý, skoro černý proužek v levém horním rohu.",
        setupLiveWebNeeds = "Tím se zapne i: data pro web, moje postava a moje trasa (web je potřebuje).",
        setupShareTitle = "Sdílení s ostatními hráči",
        setupShareBody = "Ostatní hráči s Evertally okolo se spolu mohou vyměnit krátké souhrny (dokončené běhy a pár faktů). Ty rozhoduješ, kdo je dostane, a pokaždé se tě zeptáme, když se někdo chce podívat na tvoji výbavu.",
        setupMapTitle = "Mapa a sbírání",
        setupMapBodyOpenMap = "OpenMap je tvoje mapa a Evertally pracuje uvnitř ní: přidává místa, kde mohou být bylinky, rudy, rybářská místa a truhly, a když dovolíš, i další hráče, srazy a pingy.",
        setupMapBodyNone = "Funkce mapy Evertally jsou postavené na OpenMap, zdarma addonu s mapou (CurseForge). Není nainstalovaná nebo zapnutá. Nainstaluj a zapni ji a pak /reload; tvoje volby tady zůstanou.",
        setupGather = "Místa sbírání na mapě", setupGatherSub = "Referenční místa, ne živé uzly. Každá surovina má svůj obrázek.",
        setupKinds = "Ukázat", setupKind_herb = "Bylinky", setupKind_ore = "Rudy", setupKind_fishing = "Rybářská místa", setupKind_container = "Truhly",
        setupWhere = "Všechno tohle najdeš znovu na mapě: menu OpenMap, karta On the map, sekce Evertally. Každá jednotlivá surovina s obrázkem je v okně Evertally ve Svět, Sbírání.",
        setupWindowTitle = "Okno", setupWindowBody = "Jak se Evertally ukazuje. Okno otevřeš příkazem /etally nebo tlačítkem u minimapy a toto nastavení spustíš znovu příkazem /etally setup.",
        setupSize = "Velikost okna", setupSize_Small = "Malé", setupSize_Normal = "Normální", setupSize_Large = "Velké",
        setupPlatesTitle = "Jmenovky spojenců",
        setupPlatesBody = "Vyber Blizzard nebo Evertally (doporučujeme, podobné originálu). Po zapnutí upravíš vzhled se živým náhledem. Volba i úpravy jmenovek platí ihned.",
        setupSumPlates = "Jmenovky Evertally: %s; jména %d px, značky %d px, logo %d px",
        setupSumMusic = "Hudba: %s",
        setupMusicTitle = "Hudba",
        setupMusicBody = "Tvoje Spotify nebo YouTube Music přímo ve hře: malý přehrávač, playlisty a oblíbené skladby, hledání a tišší hudba, když mluví NPC. Přehrává ji aplikace Evertally na tomto počítači; nic se nikam jinam neposílá.",
        setupMusicOn = "Přehrávač hudby ve hře", setupMusicOnSub = "Ve výchozím stavu vypnutý. Potřebuje na tomto počítači spuštěnou aplikaci Evertally.",
        setupMusicSpotify = "Aplikace Spotify. Tvoje vlastní Client ID zdarma (níže), Premium pro spuštění vybraného playlistu.",
        setupMusicYoutube = "Okno Chrome nebo Edge jako aplikace. Jednou se v něm přihlásíš do YouTube Music.",
        setupMusicYoutubeHelp = "Po dokončení aplikace Evertally otevře YouTube Music ve vlastním okně (Chrome nebo Edge, oddělený profil). Jednou se v něm přihlas; pak v okně hudby ve hře stiskni Obnovit knihovnu a Načíst knihovnu.",
        setupNotePlates = "Hra nedovolila přepnout jmenovky spojenců. Mimo boj je zapni v Nastavení → Jmenovky.",
        setupGetTitle = "Co potřebuješ",
        setupGetBody = "Aplikace Evertally a OpenMap jsou vyžadované. Jejich instalaci můžeš tady kdykoli znovu ověřit.",
        setupGetApp = "Aplikace Evertally pro Windows",
        setupGetAppSub = "Posílá tvoje data a tvoji polohu (ne živě) na tvoji stránku na webu. Stáhneš ji na webu, na stránce Stažení:",
        setupGetOpenMap = "Addon OpenMap",
        setupGetOpenMapSub = "Mapa, ve které Evertally pracuje: místa sbírání s ikonami, lidé, srazy, pingy a tvoje cesty. Zdarma, na CurseForge:",
        setupGetInstalled = "nainstalováno", setupGetMissing = "není nainstalováno",
        setupGetHow = "Použij tlačítka pro stažení, potom načti znovu rozhraní a ověř instalaci.",
        setupSumTitle = "Hotovo", setupSumBody = "Změny jmenovek už platí. Dokončit potvrdí ostatní volby níže; všechno můžeš později změnit v Nastavení.",
        setupSumLanguage = "Jazyk: %s", setupSumWeb = "Web: %s", setupSumLive = "Poloha sdílená s: %s", setupSumShare = "Sdílení s hráči: %s", setupSumMap = "Mapa: %s", setupSumGather = "Sbírání na mapě: %s",
        setupSumPins = "lidé, srazy a pingy na mapě: %s", setupSumOpenMap = "OpenMap", setupSumNoOpenMap = "OpenMap (zatím není nainstalovaná)", setupSumWindow = "Tlačítko u minimapy: %s, velikost okna: %s", setupSumNothing = "nic",
        setupSumGuild = "cech", setupSumGroup = "parta / raid", setupSumFriends = "přátelé", setupSumSite = "web",
        setupAppNote = "Aplikace nahraje, co hra uložila při /reload nebo odhlášení. Po Dokončit to uložíš hned tlačítkem.",
        setupSumChronicle = "Kronika: %s", setupSumPublic = "Veřejná stránka a žebříček: %s",
        setupPublicTitle = "Co uvidí ostatní na webu",
        setupPublicBody = "Svoje data na webu vidíš po přihlášení vždycky ty. Tady rozhodneš, co uvidí všichni ostatní.",
        setupPublicSub = "Tvoje postavy dostanou veřejnou stránku a objeví se v žebříčcích na webu. Bez toho nejsi v žádném žebříčku a nic níže nemůže být veřejné.",
        setupChronicle = "Tvoje kronika (cesta k přehrání: trasa, questy, souboje, loot)",
        setupChron_off = "Neposílat", setupChronSub_off = "Trasa se na web neposílá, kronika proto nevznikne.",
        setupChron_private = "Jen pro mě", setupChronSub_private = "Pošle se na web, ale uvidíš ji jen ty po přihlášení. Ve veřejném seznamu není.",
        setupChron_public = "Veřejně", setupChronSub_public = "Kdokoli ji na webu přehraje. Potřebuje veřejnou stránku nahoře, takže ji zapne a objevíš se v žebříčku.",
        setupChronLocked = "Poloha na webu potřebuje trasu, takže „Neposílat“ nejde, dokud je zapnutá.", setupSumApp = "Aplikace: %s; spouštět s WoW: %s", setupSumPaired = "spárovaná", setupSumUnpaired = "nespárovaná",
        setupPairTitle = "Spáruj aplikaci s webem",
        setupPairBody = "Tvoje data se na tvoji stránku na webu dostanou jen přes aplikaci Evertally pro Windows spárovanou s tvým účtem. Nastavení pokračuje, až bude aplikace spárovaná.",
        setupPairNot = "Aplikace zatím není spárovaná.",
        setupPairWaiting = "Žádost odeslaná. V prohlížeči se otevřela stránka párování (Alt+Tab): přihlas se přes Discord a potvrď kód, potom klikni Ověřit.",
        setupPairOld = "Aplikace nenahlásila, jestli je spárovaná. Spusť aplikaci Evertally (je-li starší než 0.9.13, aktualizuj ji) a klikni Ověřit.",
        setupPairDone = "Aplikace je spárovaná s tvým účtem.",
        setupPairButton = "Spárovat", setupPairVerify = "Ověřit",
        setupPairHelp = "Spárovat uloží žádost a znovu načte rozhraní. Běžící aplikace Evertally (i když je schovaná u hodin) pak otevře párování v prohlížeči. Když se nic neotevře, aplikace neběží: spusť ji z nabídky Start a klikni Spárovat znovu.",
        setupPairDoneHelp = "Tady už nic dělat nemusíš. Odpárovat můžeš kdykoli v aplikaci.",
        bridgeAutostart = "Spouštět aplikaci Evertally se zapnutím WoW",
        bridgeAutostartSub = "Čeká na pozadí a zapne se sama, když spustíš hru, a běží vždy jen na pozadí. Aplikace se volbu dozví, až ji hra uloží (Ověřit nebo /reload).",
        setupAutostartNow = "V aplikaci teď: %s",
        setupDone = "Nastavení hotové. Okno otevřeš příkazem /etally.", setupSkipped = "Nastavení přeskočeno. Znovu se otevře příkazem /etally setup.", setupNoteExport = "Přepínač webu zůstává vypnutý: pomocný addon Evertally_Export není zapnutý.",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

-- ---------------------------------------------------------------- the choices, as a table, and what they do
local function scaleName(value)
    for _, entry in ipairs(SCALES) do if math.abs(entry[2] - value) < 0.05 then return entry[1] end end
    return "Normal"
end

--- The player's present choices as a draft the setup edits; nothing is applied until Finish.
function A.OnboardingDraft()
    local s = A.db.settings
    local scopes, kinds = {}, {}
    for _, scope in ipairs(SCOPES) do scopes[scope] = s.scopes and s.scopes[scope] == true end
    local saved = type(s.mapLayers) == "table" and s.mapLayers or nil
    local gather = true   -- gathering places are on until the player says otherwise
    if saved and saved.gather ~= nil then gather = saved.gather == true end
    for _, kind in ipairs(KINDS) do kinds[kind] = not (type(s.gatherTypes) == "table" and s.gatherTypes[kind] == false) end
    local draft = {
        language = s.language == "cs" and "cs" or "en",
        web = s.web == true, scopes = scopes, liveWeb = s.liveWeb == true,
        live = {party = s.liveParty == true, guild = s.liveGuild == true, friends = s.liveFriends == true},
        ingame = s.ingame == true, group = s.group ~= false, guild = s.guild == true, social = s.social ~= false, presence = s.presence == true,
        mapPins = s.mapPins == nil and true or s.mapPins == true, layers = {gather = gather}, kinds = kinds,
        minimap = not s.hideMinimap, scale = A.GetUIScale and A.GetUIScale() or 1,
        publish = A.PublishChoice and A.PublishChoice().public == true,
        chronicle = A.PublishChoice and A.PublishChoice().public == true and A.PublishChoice().chronicle == true,
        itemLevel = A.PublishChoice and A.PublishChoice().itemLevel == true,
        guildName = A.PublishChoice and A.PublishChoice().guild == true,
        gear = A.PublishChoice and A.PublishChoice().gear == true,
        plates = A.FriendlyPlateChoices(s), friendlyPlates = A.FriendlyPlatesShown(),
        music = A.Music ~= nil and A.Music.Enabled(), musicSource = type(s.music) == "table" and s.music.source == "youtube" and "youtube" or "spotify",
        spotifyId = type(s.music) == "table" and type(s.music.spotifyId) == "string" and s.music.spotifyId or "",
    }
    return draft
end

--- Makes the choices agree with each other: the live position on the website needs the website, the character and the route (so switching it on
--- switches those on; switching the website off switches it off, see the switch).
function A.OnboardingNormalize(d)
    if d.liveWeb then d.web, d.scopes.own_character, d.scopes.own_track = true, true, true end
    -- the chronicle is part of the public page and is drawn from the route
    if not (d.web and d.publish and d.scopes.own_character and d.scopes.own_track) then d.chronicle = false end
    return d
end

--- "off" (no route on the website), "private" (the route, seen only by its owner) or "public" (anyone can replay it).
function A.OnboardingChronicle(d)
    if not (d.web and d.scopes.own_track) then return "off" end
    return d.chronicle and "public" or "private"
end
local CHRONICLE = {
    off = function(d) if not d.liveWeb then d.scopes.own_track = false end; d.chronicle = false end,
    private = function(d) d.web, d.scopes.own_track, d.chronicle = true, true, false end,
    public = function(d) d.web, d.scopes.own_character, d.scopes.own_track, d.publish, d.chronicle = true, true, true, true, true end,
}
function A.OnboardingSetChronicle(d, mode) if CHRONICLE[mode] then CHRONICLE[mode](d) end; return A.OnboardingNormalize(d) end

local PRESETS = {
    local_only = function(d) d.web = false; d.liveWeb = false; for _, scope in ipairs(SCOPES) do d.scopes[scope] = false end end,
    recommended = function(d) d.web = true; for _, scope in ipairs(SCOPES) do d.scopes[scope] = scope ~= "own_track" end end,
    everything = function(d) d.web = true; for _, scope in ipairs(SCOPES) do d.scopes[scope] = true end end,
}
function A.OnboardingPreset(d, name) if PRESETS[name] then PRESETS[name](d) end; return A.OnboardingNormalize(d) end

--- Puts the choices into effect, with the functions the Settings page uses. Returns the notes about what could not be done.
function A.OnboardingApply(d)
    if A.RequirementsReady and not A.RequirementsReady() then return {"dependencies_required"} end
    local s = A.db.settings
    local notes = {}
    A.OnboardingNormalize(d)
    A.SetLanguage(d.language)
    -- the website: the data first, the switch last (each change of the data starts a new consent)
    for _, scope in ipairs(SCOPES) do
        if (s.scopes[scope] == true) ~= d.scopes[scope] then A.SetScope(scope, d.scopes[scope]) end
    end
    if (s.web == true) ~= d.web then
        if A.SetWeb(d.web) == false then notes[#notes + 1] = "export_missing"; d.web, d.liveWeb = false, false end
    end
    s.liveWeb = d.liveWeb == true and s.web == true
    -- the public leaderboard needs the website and the character; it is the player's own choice, off by default
    local publish = d.publish == true and s.web == true and s.scopes.own_character == true
    if A.PublishChoice and A.PublishChoice().public ~= publish and (publish or A.PublishChoice().chosenAt) then A.SetPublish("public", publish) end
    local chronicle = d.chronicle == true and publish and s.scopes.own_track == true
    if A.PublishChoice and (A.PublishChoice().chronicle == true) ~= chronicle and (chronicle or A.PublishChoice().chosenAt) then A.SetPublish("chronicle", chronicle) end
    for field, key in pairs({itemLevel = "itemLevel", guild = "guildName", gear = "gear"}) do
        local value = d[key] == true and publish
        if A.PublishChoice and (A.PublishChoice()[field] == true) ~= value and (value or A.PublishChoice().chosenAt) then A.SetPublish(field, value) end
    end
    if A.OpticalTick then A.OpticalTick() end
    -- sharing with players, then the live position for each group
    s.group, s.guild, s.social = d.group, d.guild, d.social
    if A.Presence and (s.presence == true) ~= (d.presence == true) then A.Presence.SetEnabled(d.presence == true) else s.presence = d.presence == true end
    if (s.ingame == true) ~= d.ingame then A.SetIngame(d.ingame) end
    for _, which in ipairs({"party", "guild", "friends"}) do A.SetLive(which, d.live[which]) end
    -- the map is OpenMap's; what Evertally adds to it: gathering (on or off, and which kinds), then the people on the map
    s.ownMap = nil   -- (the setting of the map window Evertally no longer has)
    if type(s.mapLayers) ~= "table" then s.mapLayers = {} end
    s.mapLayers.gather = d.layers.gather == true
    if type(s.gatherTypes) ~= "table" then s.gatherTypes = {} end
    for _, kind in ipairs(KINDS) do s.gatherTypes[kind] = d.kinds[kind] == true end
    if (s.mapPins == true) ~= d.mapPins then A.SetMapPins(d.mapPins) end
    if A.map and A.map.RefreshLayerPins then A.map.RefreshLayerPins(true) end
    -- music: the player on or off, the service, and for Spotify the player's own Client ID (sent to the app)
    if A.Music then
        A.Music.SetEnabled(d.music == true)
        if d.music then
            A.Music.SetSource(d.musicSource == "youtube" and "youtube" or "spotify")
            if d.musicSource ~= "youtube" and d.spotifyId and d.spotifyId ~= "" then
                local ok = A.Music.ConnectSpotify(d.spotifyId)
                if not ok then notes[#notes + 1] = "spotify_id" end
            end
        end
    end
    A.SetMinimapButton(d.minimap)
    if A.SetUIScale then A.SetUIScale(d.scale) end
    if type(d.plates)=="table" then
        local want=d.friendlyPlates==true
        if A.FriendlyPlatesShown()~=want or (want and A.PlateCVar("nameplateShowOnlyNameForFriendlyPlayerUnits")~="1") then
            if not A.SetFriendlyPlates(want) then notes[#notes+1]="nameplates_unavailable" end
        end
        A.ApplyFriendlyPlateChoices(d.plates)
    end
    s.onboarded = VERSION
    A.Changed()
    return notes
end

local function onOff(value) return A.L(value and "setupOn" or "setupOff") end

--- The summary the last step shows: one line per question.
function A.OnboardingSummary(d)
    A.OnboardingNormalize(d)
    local lines = {}
    lines[#lines + 1] = string.format(A.L("setupSumLanguage"), d.language == "cs" and "Čeština" or "English")
    local data = {}
    for _, scope in ipairs(SCOPES) do if d.scopes[scope] then data[#data + 1] = A.L(scope) end end
    lines[#lines + 1] = string.format(A.L("setupSumApp"), A.L(A.BridgePaired and A.BridgePaired() and "setupSumPaired" or "setupSumUnpaired"), onOff(A.BridgeAutostart and A.BridgeAutostart()))
    lines[#lines + 1] = string.format(A.L("setupSumWeb"), d.web and (onOff(true) .. (#data > 0 and (" (" .. table.concat(data, "; ") .. ")") or "")) or onOff(false))
    lines[#lines + 1] = string.format(A.L("setupSumPublic"), onOff(d.publish == true and d.web and d.scopes.own_character))
    lines[#lines + 1] = string.format(A.L("setupSumChronicle"), A.L("setupChron_" .. A.OnboardingChronicle(d)))
    local live = {}
    if d.live.party then live[#live + 1] = A.L("setupSumGroup") end
    if d.live.guild then live[#live + 1] = A.L("setupSumGuild") end
    if d.live.friends then live[#live + 1] = A.L("setupSumFriends") end
    if d.liveWeb then live[#live + 1] = A.L("setupSumSite") end
    lines[#lines + 1] = string.format(A.L("setupSumLive"), #live > 0 and table.concat(live, ", ") or A.L("setupSumNothing"))
    local shared = {}
    if d.ingame then
        if d.group then shared[#shared + 1] = A.L("setupSumGroup") end
        if d.guild then shared[#shared + 1] = A.L("setupSumGuild") end
    end
    lines[#lines + 1] = string.format(A.L("setupSumShare"), d.ingame and (#shared > 0 and table.concat(shared, ", ") or onOff(true)) or onOff(false))
    lines[#lines + 1] = string.format(A.L("setupSumMap"), A.L(A.OpenMapInstalled() and "setupSumOpenMap" or "setupSumNoOpenMap")) .. "; " .. string.format(A.L("setupSumPins"), onOff(d.mapPins))
    local kinds = {}
    for _, kind in ipairs(KINDS) do if d.kinds[kind] then kinds[#kinds + 1] = A.L("setupKind_" .. kind) end end
    lines[#lines + 1] = string.format(A.L("setupSumGather"), d.layers.gather and #kinds > 0 and (onOff(true) .. " (" .. table.concat(kinds, ", ") .. ")") or onOff(false))
    lines[#lines + 1] = string.format(A.L("setupSumWindow"), onOff(d.minimap), A.L("setupSize_" .. scaleName(d.scale)))
    local plates=A.FriendlyPlateChoices(d.plates)
    lines[#lines + 1] = string.format(A.L("setupSumPlates"),onOff(d.friendlyPlates and plates.plateGameLook),plates.plateFontSize,plates.markSize,plates.plateLogoSize)
    lines[#lines + 1] = string.format(A.L("setupSumMusic"), d.music and A.L(d.musicSource == "youtube" and "musicYoutube" or "musicSpotify") or onOff(false))
    return lines
end

-- ---------------------------------------------------------------- the window
local f, pages, draft, step = nil, {}, nil, 1
A.onboarding = {}   -- (state the tests and the layout preview read)

local function place(widget, y, height, indent)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", indent or 0, -y); widget:SetPoint("TOPRIGHT", 0, -y)
    if height then widget:SetHeight(height) end
end

local function refresh()
    if not f then return end
    A.OnboardingNormalize(draft)
    local C = A.UIKit().C
    f.title:SetText(A.L("setupTitle")); f.counter:SetText(string.format(A.L("setupStepOf"), step, #STEPS))
    f.back:SetShown(step > 1); f.next.text:SetText(A.L(step == #STEPS and "setupFinish" or "setupNext")); f.back.text:SetText(A.L("setupBack"))
    local ready=step < A.OnboardingReach() or step == #STEPS
    f.next:SetEnabled(ready);f.next:SetAlpha(ready and 1 or 0.45)
    for i, dot in ipairs(f.dots) do
        local on = i == step
        A.UIKit().paint(dot, on and C.bright or (i < step and C.gold or C.off), on and 1 or 0.75)
    end
    for i, page in ipairs(pages) do page:SetShown(i == step) end
    local page = pages[step]
    if page and page.refresh then page.refresh() end
end
A.RefreshOnboarding=refresh

--- The furthest step the player can reach now: the installation and then the pairing hold the setup.
function A.OnboardingReach()
    if A.RequirementsReady and not A.RequirementsReady() then return INSTALL end
    if not A.BridgePaired() then return PAIR end
    return #STEPS
end
local function go(n)
    step = math.max(1, math.min(A.OnboardingReach(), n))
    refresh()
end

local function newPage(i, titleKey, bodyKey)
    local kit = A.UIKit()
    local page = CreateFrame("Frame", nil, f.body)
    page:SetAllPoints(f.body); page:Hide()
    page.title = kit.label(page, 24, kit.C.bright); page.title:SetPoint("TOPLEFT", 0, 0)
    page.body = kit.label(page, 13, kit.C.mist); page.body:SetPoint("TOPLEFT", 0, -36); page.body:SetPoint("TOPRIGHT", 0, -36)
    page.titleKey, page.bodyKey = titleKey, bodyKey
    pages[i] = page
    return page
end
local function titles(page)
    page.title:SetText(A.L(page.titleKey))
    local key = type(page.bodyKey) == "function" and page.bodyKey() or page.bodyKey
    page.body:SetText(A.L(key))
end

local function build()
    local kit = A.UIKit()
    local C = kit.C
    f = CreateFrame("Frame", "EvertallySetup", UIParent)
    f:SetSize(W, H); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    local scale=A.GetUIScale and A.GetUIScale() or 1
    local screenW=A.Number(A.Call(UIParent.GetWidth,UIParent),1)
    local screenH=A.Number(A.Call(UIParent.GetHeight,UIParent),1)
    if screenW and screenH then scale=math.min(scale,math.max(0.5,math.min((screenW-32)/W,(screenH-32)/H))) end
    f:SetScale(scale)
    A.NativeFrame(f, C)
    local bar = CreateFrame("Frame", nil, f); bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT"); bar:SetHeight(HEADER)
    kit.gradient(kit.fill(bar, C.header), C.header, C.side)
    local headerRule=bar:CreateTexture(nil,"BORDER");headerRule:SetHeight(1);headerRule:SetPoint("BOTTOMLEFT",1,0);headerRule:SetPoint("BOTTOMRIGHT",-1,0);kit.paint(headerRule,C.gold,0.8)
    local logo=bar:CreateTexture(nil,"ARTWORK");logo:SetSize(32,32);logo:SetPoint("LEFT",PAD,0);logo:SetTexture("Interface\\AddOns\\Evertally\\Media\\Logo")
    bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end); bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.title = kit.label(bar, 20, C.bright); f.title:SetPoint("LEFT", logo,"RIGHT",12,0)
    local close = kit.Button(bar, nil, 30, "ghost", function() A.OnboardingClose() end); close:SetPoint("RIGHT", -14, 0); close.text:SetText("x");f.close=close
    f.counter = kit.label(bar, 11, C.mist); f.counter:SetPoint("RIGHT", close, "LEFT", -16, 0); f.counter:SetJustifyH("RIGHT")
    f.body = CreateFrame("Frame", nil, f); f.body:SetPoint("TOPLEFT", PAD, -HEADER - 14); f.body:SetPoint("BOTTOMRIGHT", -PAD, FOOTER)

    -- No skip action: closing never marks setup complete or bypasses installation.
    local footer = CreateFrame("Frame", nil, f); footer:SetPoint("BOTTOMLEFT",1,1); footer:SetPoint("BOTTOMRIGHT",-1,1); footer:SetHeight(FOOTER)
    kit.fill(footer,C.side)
    local rule = footer:CreateTexture(nil, "BORDER"); rule:SetHeight(1); rule:SetPoint("TOPLEFT"); rule:SetPoint("TOPRIGHT"); kit.paint(rule, C.line)
    f.next = kit.Button(footer, nil, 130, "primary", function()
        if step == #STEPS then A.OnboardingFinish() else go(step + 1) end
    end)
    f.next:SetPoint("RIGHT", -PAD, 0)
    f.back = kit.Button(footer, nil, 100, "ghost", function() go(step - 1) end); f.back:SetPoint("RIGHT", f.next, "LEFT", -8, 0)
    f.dots = {}
    for i = 1, #STEPS do
        local dot = footer:CreateTexture(nil, "ARTWORK"); dot:SetSize(18, 3)
        dot:SetPoint("LEFT", footer, "LEFT", PAD+(i-1)*24, 0)
        f.dots[i] = dot
    end

    -- 1: language
    do
    local p = newPage(1, "setupWelcomeTitle", "setupWelcomeBody")
    p.languageLabel = kit.label(p, 12, C.text); p.languageLabel:SetPoint("TOPLEFT", 0, -FIRST + 4)
    local cols = kit.Columns(p, {1, 1}, 12); cols:SetPoint("TOPLEFT", 0, -FIRST - 18); cols:SetPoint("TOPRIGHT", 0, -FIRST - 18); cols:SetHeight(58)
    p.languages = {}
    for i, lang in ipairs({"en", "cs"}) do
        local option = kit.Option(cols.cells[i], function() draft.language = lang; A.SetLanguage(lang); refresh() end, 58)
        option:SetAllPoints(cols.cells[i]); option.SetTexts(lang == "en" and "English" or "Čeština", lang == "en" and "Interface in English" or "Rozhraní v češtině")
        p.languages[lang] = option
    end
    p.privacy = kit.label(p, 12, C.text); p.privacy:SetPoint("TOPLEFT", 0, -FIRST - 100); p.privacy:SetPoint("TOPRIGHT", 0, -FIRST - 100)
    p.existing = kit.label(p, 11, C.peach); p.existing:SetPoint("TOPLEFT", 0, -FIRST - 160); p.existing:SetPoint("TOPRIGHT", 0, -FIRST - 160)
    p.refresh = function()
        titles(p); p.languageLabel:SetText(A.L("setupLanguage")); p.privacy:SetText(A.L("setupPrivacy"))
        for lang, option in pairs(p.languages) do option.Set(draft.language == lang) end
        p.existing:SetText(A.onboarding.existing and A.L("setupExisting") or "")
    end

    end
    -- 2: the website
    do
    local p = newPage(4, "setupWebTitle", "setupWebBody")
    p.quickLabel = kit.label(p, 12, C.text); p.quickLabel:SetPoint("TOPLEFT", 0, -FIRST - 4)
    p.presets = {}
    local previous
    for _, name in ipairs({"local_only", "recommended", "everything"}) do
        local chip = kit.Chip(p, function() A.OnboardingPreset(draft, name); refresh() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 110, -FIRST) end
        p.presets[name] = chip; previous = chip
    end
    p.web = kit.Switch(p, function(on) draft.web = on; if not on then draft.liveWeb = false end; refresh() end, 38); place(p.web, FIRST + 34, 38)
    p.scopes = {}
    for i, scope in ipairs(SCOPES) do
        local sw = kit.Switch(p, function(on) draft.scopes[scope] = on; refresh() end, 34)
        place(sw, FIRST + 34 + 42 + (i - 1) * 38, 34, 24)
        p.scopes[scope] = sw
    end
    p.missing = kit.label(p, 11, C.peach); p.missing:SetPoint("TOPLEFT", 0, -FIRST - 34 - 42 - #SCOPES * 38 - 6); p.missing:SetPoint("TOPRIGHT", 0, -FIRST - 34 - 42 - #SCOPES * 38 - 6)
    p.refresh = function()
        titles(p); p.quickLabel:SetText(A.L("setupQuick") .. ":")
        for name, chip in pairs(p.presets) do chip.SetLabel(A.L(name == "local_only" and "setupPresetLocal" or name == "recommended" and "setupPresetRecommended" or "setupPresetEverything")); chip.SetOn(false) end
        p.web.SetTexts(A.L("web")); p.web.Set(draft.web, true)
        for scope, sw in pairs(p.scopes) do sw.SetTexts(A.L(scope)); sw.Set(draft.scopes[scope], draft.web and not (draft.liveWeb and (scope == "own_character" or scope == "own_track"))) end
        p.missing:SetText(A.ExportStore() and "" or A.L("setupWebMissing"))
    end

    end
    -- 5: what others see: the public page (and the leaderboard), its extras, and the chronicle
    do
    local p = newPage(5, "setupPublicTitle", "setupPublicBody")
    p.publish = kit.Switch(p, function(on)
        draft.publish = on
        if on then draft.web, draft.scopes.own_character = true, true end
        refresh()
    end, 54)
    place(p.publish, FIRST, 54)
    p.extras = {}
    for i, entry in ipairs({{"itemLevel", "leaderboardItemLevel"}, {"guildName", "leaderboardGuild"}, {"gear", "leaderboardGear"}}) do
        local key = entry[1]
        local sw = kit.Switch(p, function(on) draft[key] = on; refresh() end, 34)
        place(sw, FIRST + 60 + (i - 1) * 36, 34, 24)
        sw.localeKey = entry[2]; p.extras[key] = sw
    end
    p.chronicleLabel = kit.label(p, 12, C.text); p.chronicleLabel:SetPoint("TOPLEFT", 0, -FIRST - 178); p.chronicleLabel:SetPoint("TOPRIGHT", 0, -FIRST - 178)
    local cols = kit.Columns(p, {1, 1, 1}, 12); cols:SetPoint("TOPLEFT", 0, -FIRST - 200); cols:SetPoint("TOPRIGHT", 0, -FIRST - 200); cols:SetHeight(100)
    p.chronicle = {}
    for i, mode in ipairs({"off", "private", "public"}) do
        local option = kit.Option(cols.cells[i], function()
            if mode == "off" and draft.liveWeb then return end
            A.OnboardingSetChronicle(draft, mode); refresh()
        end, 100)
        option:SetAllPoints(cols.cells[i]); p.chronicle[mode] = option
    end
    p.note = kit.label(p, 11, C.peach); p.note:SetPoint("TOPLEFT", 0, -FIRST - 310); p.note:SetPoint("TOPRIGHT", 0, -FIRST - 310)
    p.refresh = function()
        titles(p)
        local public = draft.publish == true and draft.web and draft.scopes.own_character
        p.publish.SetTexts(A.L("leaderboard"), A.L("setupPublicSub")); p.publish.Set(public, true)
        for key, sw in pairs(p.extras) do sw.SetTexts(A.L(sw.localeKey)); sw.Set(public and draft[key] == true, public) end
        p.chronicleLabel:SetText(A.L("setupChronicle"))
        local mode = A.OnboardingChronicle(draft)
        for name, option in pairs(p.chronicle) do
            option.SetTexts(A.L("setupChron_" .. name), A.L("setupChronSub_" .. name)); option.Set(mode == name)
            option:SetAlpha(name == "off" and draft.liveWeb and 0.45 or 1)
        end
        p.note:SetText(draft.liveWeb and A.L("setupChronLocked") or "")
    end
    end
    -- 6: position
    do
    local p = newPage(6, "setupLiveTitle", "setupLiveBody")
    p.rows = {}
    for i, which in ipairs({"party", "guild", "friends"}) do
        local sw = kit.Switch(p, function(on) draft.live[which] = on; refresh() end, 40)
        place(sw, FIRST + (i - 1) * 46, 40)
        p.rows[which] = sw
    end
    p.liveWeb = kit.Switch(p, function(on) draft.liveWeb = on; refresh() end, 66); place(p.liveWeb, FIRST + 3 * 46 + 8, 66)
    p.needs = kit.label(p, 11, C.peach); p.needs:SetPoint("TOPLEFT", 0, -FIRST - 3 * 46 - 82); p.needs:SetPoint("TOPRIGHT", 0, -FIRST - 3 * 46 - 82)
    p.refresh = function()
        titles(p)
        p.rows.party.SetTexts(A.L("liveParty")); p.rows.guild.SetTexts(A.L("liveGuild")); p.rows.friends.SetTexts(A.L("liveFriends"))
        for which, sw in pairs(p.rows) do sw.Set(draft.live[which], true) end
        p.liveWeb.SetTexts(A.L("setupLiveWeb"), A.L("setupLiveWebSub")); p.liveWeb.Set(draft.liveWeb, true)
        p.needs:SetText(draft.liveWeb and A.L("setupLiveWebNeeds") or "")
    end

    end
    -- 4: sharing with players
    do
    local p = newPage(7, "setupShareTitle", "setupShareBody")
    p.share = kit.Switch(p, function(on) draft.ingame = on; refresh() end, 40); place(p.share, FIRST, 40)
    p.group = kit.Switch(p, function(on) draft.group = on; refresh() end, 36); place(p.group, FIRST + 46, 36, 24)
    p.guild = kit.Switch(p, function(on) draft.guild = on; refresh() end, 36); place(p.guild, FIRST + 46 + 40, 36, 24)
    p.social = kit.Switch(p, function(on) draft.social = on; refresh() end, 40); place(p.social, FIRST + 46 + 40 + 48, 40)
    p.presence = kit.Switch(p, function(on) draft.presence = on; refresh() end, 66); place(p.presence, FIRST + 46 + 40 + 48 + 46, 66)
    p.refresh = function()
        titles(p)
        p.share.SetTexts(A.L("share")); p.share.Set(draft.ingame, true)
        p.group.SetTexts(A.L("group")); p.group.Set(draft.group, draft.ingame)
        p.guild.SetTexts(A.L("guild")); p.guild.Set(draft.guild, draft.ingame)
        p.social.SetTexts(A.L("socialEnabled")); p.social.Set(draft.social, true)
        p.presence.SetTexts(A.L("peopleCatOnline"), A.L("setupPresenceSub")); p.presence.Set(draft.presence, true)
    end

    end
    -- 5: the map (OpenMap's) and what Evertally adds to it
    do
    local p = newPage(8, "setupMapTitle", function() return A.OpenMapInstalled() and "setupMapBodyOpenMap" or "setupMapBodyNone" end)
    p.gather = kit.Switch(p, function(on) draft.layers.gather = on; refresh() end, 54); place(p.gather, FIRST, 54)
    p.kindsLabel = kit.label(p, 12, C.text); p.kindsLabel:SetPoint("TOPLEFT", 24, -FIRST - 66)
    p.kinds = {}
    local previous
    for _, kind in ipairs(KINDS) do
        local chip = kit.Chip(p, function() draft.kinds[kind] = not draft.kinds[kind]; refresh() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 24, -FIRST - 86) end
        p.kinds[kind] = chip; previous = chip
    end
    p.pins = kit.Switch(p, function(on) draft.mapPins = on; refresh() end, 38); place(p.pins, FIRST + 130, 38)
    p.where = kit.label(p, 11, C.mist); p.where:SetPoint("TOPLEFT", 0, -FIRST - 182); p.where:SetPoint("TOPRIGHT", 0, -FIRST - 182)
    p.refresh = function()
        titles(p)
        p.gather.SetTexts(A.L("setupGather"), A.L("setupGatherSub")); p.gather.Set(draft.layers.gather, true)
        p.kindsLabel:SetText(A.L("setupKinds") .. ":")
        for kind, chip in pairs(p.kinds) do chip.SetLabel(A.L("setupKind_" .. kind)); chip.SetOn(draft.kinds[kind] == true); chip:SetAlpha(draft.layers.gather and 1 or 0.4) end
        p.pins.SetTexts(A.L("mapPins")); p.pins.Set(draft.mapPins, true)
        p.where:SetText(A.L("setupWhere"))
    end

    end
    -- 6: the window
    do
    local p = newPage(9, "setupWindowTitle", "setupWindowBody")
    p.minimap = kit.Switch(p, function(on) draft.minimap = on; refresh() end, 40); place(p.minimap, FIRST, 40)
    p.sizeLabel = kit.label(p, 12, C.text); p.sizeLabel:SetPoint("TOPLEFT", 0, -FIRST - 62)
    p.sizes = {}
    local previous
    for _, entry in ipairs(SCALES) do
        local chip = kit.Chip(p, function() draft.scale = entry[2]; refresh() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 0, -FIRST - 84) end
        p.sizes[entry[1]] = chip; previous = chip
    end
    p.refresh = function()
        titles(p)
        p.minimap.SetTexts(A.L("minimap")); p.minimap.Set(draft.minimap, true)
        p.sizeLabel:SetText(A.L("setupSize"))
        for name, chip in pairs(p.sizes) do chip.SetLabel(A.L("setupSize_" .. name)); chip.SetOn(scaleName(draft.scale) == name) end
    end

    end
    -- 7: explicit provider choice, then live customization. Only the other setup choices wait for Finish.
    do
    local p = newPage(10, "setupPlatesTitle", "setupPlatesBody")
    p.plates=A.BuildFriendlyPlateControls(p,{
        chooseFirst=true,
        changed=function() draft.plates=A.FriendlyPlateChoices();draft.friendlyPlates=A.FriendlyPlatesShown() end,
    })
    p.plates:SetPoint("TOPLEFT",0,-FIRST);p.plates:SetPoint("BOTTOMRIGHT",0,0)
    p.refresh=function() titles(p);p.plates.Update() end
    end
    -- 1: mandatory installation. The same content is opened by every guarded entry.
    do
    local p = newPage(INSTALL, "setupGetTitle", "setupGetBody")
    p.install=A.BuildInstallationControls(p);p.install:SetPoint("TOPLEFT",0,-72);p.install:SetPoint("BOTTOMRIGHT",0,0)
    p.languages={}
    for i,lang in ipairs({"en","cs"}) do
        local choice=lang
        local b=kit.Button(p,nil,32,"ghost",function() A.SetLanguage(choice);draft.language=choice;refresh() end)
        b.text:SetText(lang:upper());b:SetHeight(24);b:SetPoint("TOPRIGHT",-(i-1)*38,0);p.languages[lang]=b
    end
    p.refresh = function()
        titles(p);p.install.Update()
    end
    end
    -- 2: pairing with the app; the setup goes no further until the app reports a pairing
    do
    local p = newPage(PAIR, "setupPairTitle", "setupPairBody")
    p.status = kit.label(p, 14, C.bright); p.status:SetPoint("TOPLEFT", 0, -FIRST); p.status:SetPoint("TOPRIGHT", 0, -FIRST)
    p.pair = kit.Button(p, nil, 170, "primary", function() A.RequestPairing() end); p.pair:SetPoint("TOPLEFT", 0, -FIRST - 36)
    p.verify = kit.Button(p, nil, 170, "ghost", function()
        if A.Call(InCombatLockdown) == true then A.Print(A.L("markPlatesCombat")); return end
        A.Call(ReloadUI)
    end)
    p.verify:SetPoint("TOPLEFT", 180, -FIRST - 36)
    p.help = kit.label(p, 12, C.mist); p.help:SetPoint("TOPLEFT", 0, -FIRST - 86); p.help:SetPoint("TOPRIGHT", 0, -FIRST - 86)
    p.autostart = kit.Switch(p, function(on) A.SetBridgeAutostart(on); refresh() end, 66); place(p.autostart, FIRST + 170, 66)
    p.autostartState = kit.label(p, 11, C.mist); p.autostartState:SetPoint("TOPLEFT", 0, -FIRST - 244); p.autostartState:SetPoint("TOPRIGHT", 0, -FIRST - 244)
    p.refresh = function()
        titles(p)
        local state = A.BridgePairing()
        local key = state == "paired" and "setupPairDone" or A.BridgePairingRequested() and "setupPairWaiting" or state == "unknown" and "setupPairOld" or "setupPairNot"
        p.status:SetText(A.L(key)); p.status:SetTextColor(unpack(state == "paired" and C.green or C.peach))
        p.pair.text:SetText(A.L("setupPairButton")); p.pair:SetShown(state ~= "paired")
        p.verify.text:SetText(A.L("setupPairVerify"))
        p.help:SetText(A.L(state == "paired" and "setupPairDoneHelp" or "setupPairHelp"))
        p.autostart.SetTexts(A.L("bridgeAutostart"), A.L("bridgeAutostartSub")); p.autostart.Set(A.BridgeAutostart(), true)
        local reported = A.BridgeAutostartReported()
        p.autostartState:SetText(reported == nil and "" or string.format(A.L("setupAutostartNow"), onOff(reported)))
    end
    end
    -- 11: music, played by the Evertally app: on or off, Spotify or YouTube Music, Spotify's Client ID
    do
    local p = newPage(MUSIC, "setupMusicTitle", "setupMusicBody")
    p.enable = kit.Switch(p, function(on) draft.music = on; refresh() end, 54); place(p.enable, FIRST, 54)
    local cols = kit.Columns(p, {1, 1}, 12); cols:SetPoint("TOPLEFT", 0, -FIRST - 64); cols:SetPoint("TOPRIGHT", 0, -FIRST - 64); cols:SetHeight(84)
    p.sources = {}
    for i, source in ipairs({"spotify", "youtube"}) do
        local option = kit.Option(cols.cells[i], function() draft.musicSource = source; refresh() end, 84)
        option:SetAllPoints(cols.cells[i]); p.sources[source] = option
    end
    p.idLabel = kit.label(p, 12, C.text); p.idLabel:SetPoint("TOPLEFT", 0, -FIRST - 162)
    p.id = kit.SearchBox(p, 300, function(value) draft.spotifyId = value end); p.id:SetPoint("TOPLEFT", 0, -FIRST - 182); p.id:SetPoint("RIGHT", p, "CENTER", 40, 0); p.id:SetHeight(28); p.id:SetMaxLetters(40)
    p.dashboardLabel = kit.label(p, 12, C.text); p.dashboardLabel:SetPoint("TOPLEFT", p, "TOP", 52, -FIRST - 162)
    p.dashboard = kit.LinkBox(p); p.dashboard:SetPoint("TOPLEFT", p, "TOP", 52, -FIRST - 182); p.dashboard:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    p.redirectLabel = kit.label(p, 12, C.text); p.redirectLabel:SetPoint("TOPLEFT", 0, -FIRST - 220)
    p.redirect = kit.LinkBox(p); p.redirect:SetPoint("TOPLEFT", 0, -FIRST - 240); p.redirect:SetPoint("RIGHT", p, "CENTER", 40, 0)
    p.help = kit.label(p, 11, C.mist); p.help:SetPoint("TOPLEFT", 0, -FIRST - 280); p.help:SetPoint("TOPRIGHT", 0, -FIRST - 280); p.help:SetWordWrap(true); p.help:SetHeight(110)
    p.refresh = function()
        titles(p)
        p.enable.SetTexts(A.L("setupMusicOn"), A.L("setupMusicOnSub")); p.enable.Set(draft.music, true)
        for source, option in pairs(p.sources) do
            option.SetTexts(A.L(source == "youtube" and "musicYoutube" or "musicSpotify"), A.L(source == "youtube" and "setupMusicYoutube" or "setupMusicSpotify"))
            option.Set(draft.musicSource == source); option:SetAlpha(draft.music and 1 or 0.45)
        end
        local spotify = draft.music and draft.musicSource ~= "youtube"
        p.idLabel:SetText(A.L("musicSpotifyId")); p.idLabel:SetShown(spotify); p.id:SetShown(spotify); p.id.hint:SetText("0123456789abcdef…")
        if (p.id:GetText() or "") == "" and draft.spotifyId ~= "" and not (p.id.HasFocus and p.id:HasFocus()) then
            p.id:SetText(draft.spotifyId); if p.id.SetCursorPosition then p.id:SetCursorPosition(0) end
        end
        p.dashboardLabel:SetText(A.L("musicDashboard")); p.dashboardLabel:SetShown(spotify); p.dashboard.SetUrl(A.Music and A.Music.DASHBOARD or ""); p.dashboard:SetShown(spotify)
        p.redirectLabel:SetText(A.L("musicRedirect")); p.redirectLabel:SetShown(spotify); p.redirect.SetUrl(A.Music and A.Music.REDIRECT or ""); p.redirect:SetShown(spotify)
        p.help:SetText(not draft.music and "" or A.L(spotify and "setupSpotifyHelp" or "setupMusicYoutubeHelp"))
    end
    end
    -- 12: the summary
    do
    local p = newPage(12, "setupSumTitle", "setupSumBody")
    p.lines = {}
    for i = 1, 12 do
        local line = kit.label(p, 12, C.text); line:SetPoint("TOPLEFT", 0, -FIRST - (i - 1) * 28); line:SetPoint("TOPRIGHT", 0, -FIRST - (i - 1) * 28)
        p.lines[i] = line
    end
    p.note = kit.label(p, 11, C.mist); p.note:SetPoint("TOPLEFT", 0, -FIRST - 12 * 28 - 6); p.note:SetPoint("TOPRIGHT", 0, -FIRST - 12 * 28 - 6)
    p.refresh = function()
        titles(p)
        local lines = A.OnboardingSummary(draft)
        for i, line in ipairs(p.lines) do line:SetText(lines[i] and ("•  " .. lines[i]) or "") end
        p.note:SetText(draft.web and not A.ExportStore() and A.L("setupNoteExport") or ((draft.web or draft.liveWeb) and A.L("setupAppNote") or ""))
    end
    end
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EvertallySetup" end
    A.onboarding.window, A.onboarding.pages = f, pages
    f:Hide()
end

--- Opens the setup on its first step, with the present choices.
function A.OpenOnboarding(startStep)
    if not A.db then return end
    if not f then build() end
    if A.HideUI then A.HideUI() end
    draft = A.OnboardingDraft()
    A.onboarding.dismissed=false
    pages[10].plates.choosing=true
    A.onboarding.existing = A.db.settings.onboarded ~= nil or A.db.settings.web == true or A.db.settings.ingame == true or A.db.settings.mapPins == true
    f:Show();go(tonumber(startStep) or 1)
end
function A.OnboardingGo(n) go(n) end
function A.OnboardingState() return step, draft end
function A.OnboardingShown() return f ~= nil and f:IsShown() end

--- Applies the choices and closes.
function A.OnboardingFinish()
    if not draft then return {} end
    if A.RequirementsGuard and not A.RequirementsGuard() then return {"dependencies_required"} end
    local notes = A.OnboardingApply(draft)
    if f then f:Hide() end
    A.Print(A.L("setupDone"))
    if A.webChangePending and A.MarkWebChanged then A.MarkWebChanged() end
    for _, note in ipairs(notes) do
        if note == "export_missing" then A.Print(A.L("setupNoteExport"))
        elseif note == "nameplates_unavailable" then A.Print(A.L("setupNotePlates")) end
    end
    return notes
end

--- Closing only hides the window. It does not complete setup or unlock the addon.
function A.OnboardingClose()
    if f then f:Hide();A.onboarding.dismissed=true end
    if A.installationLinkWindow then A.installationLinkWindow:Hide() end
end
A.OnboardingSkip=A.OnboardingClose -- compatibility; no skip button is offered

-- ---------------------------------------------------------------- when it opens by itself: once, a few seconds after the world is there, never in combat
local offered, waiting = false, false
function A.OnboardingMaybe()
    if A.RequirementsReady and not A.RequirementsReady() then A.RequirementsMaybe();return end
    if offered or not A.db or A.db.settings.onboarded == VERSION or type(CreateFrame) ~= "function" then return end
    if A.Call(InCombatLockdown) == true then waiting = true; return end
    offered = true
    -- A failed opening is not "offered": the error is counted for /etally diag and the setup tries again at the next
    -- loading screen or after combat, instead of never showing for this player.
    local function show()
        if not A.db or A.db.settings.onboarded == VERSION or A.onboarding.dismissed or A.OnboardingShown() then return end
        if A.Call(InCombatLockdown) == true then offered, waiting = false, true; return end
        local ok, err = pcall(A.OpenOnboarding)
        if not ok or not A.OnboardingShown() then
            offered = false
            A.errors.onboarding = (A.errors.onboarding or 0) + 1
            A.lastOnboardingError = tostring(err or "not shown")
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(5, show) else show() end
end
A.On("PLAYER_ENTERING_WORLD", function() A.OnboardingMaybe() end)
A.On("PLAYER_REGEN_ENABLED", function() if waiting then waiting = false; A.OnboardingMaybe() end end)
