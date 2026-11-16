local _, A = ...
-- Music: Spotify or YouTube Music played by the Evertally app for Windows, controlled from the game.
-- An addon cannot reach the network or play a stream. Commands go to the app through the pixel strip (Optical.lua);
-- the library comes back in MusicData.lua, which the app writes and the game reads at login and /reload. The app also
-- shows what is playing over the game, since nothing can reach the game live.
-- Commands: m:toggle m:play m:pause m:next m:prev m:vol+ m:vol- m:duck m:unduck m:src:<spotify|youtube>
--           m:pl:<id> (play a playlist or song from the library), m:pt:<song>@<playlist> (a song inside its playlist),
--           m:find:<text>, m:lib (refresh the library), m:open
local M = {}
A.Music = M
local words = {
    en = {music = "Music", musicEnabled = "Music player: Spotify or YouTube Music through the Evertally app",
        musicDuck = "…lower the music while talking to NPCs", musicTitle = "Music",
        musicBrowse = "Library", musicSearch = "Search Spotify / YouTube Music…", musicFilter = "Filter my library…",
        musicPlaylists = "Playlists", musicLiked = "Liked songs", musicRecent = "Recently played", musicResults = "Search results",
        musicSearching = "Searching for “%s”… When the Evertally app has the results (a few seconds), press Load results.", musicLoadResults = "Load results (reload)",
        musicPrev = "Previous", musicPlayBtn = "Play", musicPause = "Pause", musicNext = "Next", musicVolDown = "Quieter", musicVolUp = "Louder",
        musicRefresh = "Refresh library", musicLoad = "Load library (reload)",
        musicNoLibrary = "No library yet. With the Evertally app running, choose Spotify or YouTube Music above, press Refresh library, wait for the app's Windows notification and press Load library.",
        musicOff = "Music is off: switch on the music player in Settings > Music.",
        musicCheckApp = "Sent to the Evertally app. The app confirms it with a Windows notification within a few seconds. No notification means the app does not see the game: it has to run (icon by the clock, version 0.9.16 or newer), the game should be in Windowed or Windowed (Fullscreen) mode, and nothing may cover the game's top-left corner.",
        musicSource = "Source", musicSpotify = "Spotify", musicYoutube = "YouTube Music",
        musicNeedsApp = "Music needs the Evertally app running on this PC.",
        musicSent = "Sent to the Evertally app.", musicNotSent = "Cannot send: the command has characters the app does not read, or too many are waiting.",
        musicLibraryOf = "Library from %s, %s", musicPlay = "Play",
        musicSpotifyId = "Spotify Client ID", musicSpotifyConnect = "Connect",
        musicSpotifyHelp = "How: 1) Copy the Spotify Dashboard address from its field into your browser and sign in. 2) Create app: any name; Redirect URI: copy it from the field (http://127.0.0.1:8765/callback is your own PC: the Evertally app catches the sign-in there, nothing goes anywhere else); tick Web API; save. 3) Copy the app's Client ID here and press Connect: your browser opens once to sign in to Spotify. Your own app because Spotify lets a new app serve only accounts its owner adds. Starting a chosen playlist needs Premium; without it, it opens in the Spotify app.",
        setupSpotifyHelp = "How: 1) Copy the Spotify Dashboard address from its field into your browser and sign in. 2) Create app: any name; Redirect URI: copy it from the field (http://127.0.0.1:8765/callback is your own PC: the Evertally app catches the sign-in there, nothing goes anywhere else); tick Web API; save. 3) Copy the app's Client ID here. After Finish your browser opens once to sign in to Spotify. Your own app because Spotify lets a new app serve only accounts its owner adds. Starting a chosen playlist needs Premium.",
        musicDashboard = "Spotify Dashboard (click, Ctrl+C)", musicRedirect = "Redirect URI (click, Ctrl+C)",
        musicDashboardShort = "Dashboard", musicRedirectShort = "Redirect URI",
        musicBadId = "A Spotify Client ID has 32 characters (0-9, a-f).", musicSection = "Music", musicOpenWindow = "Open the music player",
        musicIconTip = "Click: show or hide the player. Right-click: the library (service, playlists, search).", musicMini = "Small player",
        musicUntitled = "(untitled)", musicRowOpen = "Click: show or hide its songs. Double-click: play the playlist.",
        musicRowPlay = "Double-click: play.", musicRowSong = "Double-click: play this song; the playlist goes on after it."},
    cs = {music = "Hudba", musicEnabled = "Přehrávač hudby: Spotify nebo YouTube Music přes aplikaci Evertally",
        musicDuck = "…při rozhovoru s NPC hudbu ztišit", musicTitle = "Hudba",
        musicBrowse = "Knihovna", musicSearch = "Hledat na Spotify / YouTube Music…", musicFilter = "Filtrovat moji knihovnu…",
        musicPlaylists = "Playlisty", musicLiked = "Oblíbené skladby", musicRecent = "Naposledy hrané", musicResults = "Výsledky",
        musicSearching = "Hledám „%s“… Až je aplikace Evertally najde (pár vteřin), stiskni Načíst výsledky.", musicLoadResults = "Načíst výsledky (reload)",
        musicPrev = "Předchozí", musicPlayBtn = "Přehrát", musicPause = "Pauza", musicNext = "Další", musicVolDown = "Ztišit", musicVolUp = "Zesílit",
        musicRefresh = "Obnovit knihovnu", musicLoad = "Načíst knihovnu (reload)",
        musicNoLibrary = "Knihovna zatím není. Při spuštěné aplikaci Evertally vyber nahoře Spotify nebo YouTube Music, stiskni Obnovit knihovnu, počkej na oznámení aplikace ve Windows a stiskni Načíst knihovnu.",
        musicOff = "Hudba je vypnutá: zapni Přehrávač hudby v Nastavení > Hudba.",
        musicCheckApp = "Posláno aplikaci Evertally. Aplikace to do pár vteřin potvrdí oznámením ve Windows. Když žádné nepřijde, aplikace hru nevidí: musí běžet (ikona u hodin, verze 0.9.16 nebo novější), hra má být v režimu Okno nebo Okno (celá obrazovka) a levý horní roh hry nesmí nic zakrývat.",
        musicSource = "Zdroj", musicSpotify = "Spotify", musicYoutube = "YouTube Music",
        musicNeedsApp = "Hudba potřebuje na tomto počítači spuštěnou aplikaci Evertally.",
        musicSent = "Posláno aplikaci Evertally.", musicNotSent = "Nejde poslat: příkaz má znaky, které aplikace nepřečte, nebo jich čeká moc.",
        musicLibraryOf = "Knihovna z %s, %s", musicPlay = "Přehrát",
        musicSpotifyId = "Spotify Client ID", musicSpotifyConnect = "Připojit",
        musicSpotifyHelp = "Postup: 1) Adresu Spotify Dashboard zkopíruj z pole do prohlížeče a přihlas se. 2) Create app: libovolný název; Redirect URI zkopíruj z pole (http://127.0.0.1:8765/callback je tvůj vlastní počítač: přihlášení tam zachytí aplikace Evertally, nic nejde jinam); zaškrtni Web API; ulož. 3) Zkopíruj sem Client ID té aplikace a stiskni Připojit: jednou se otevře prohlížeč k přihlášení ke Spotify. Vlastní aplikace proto, že Spotify novou aplikaci pustí jen účtům, které její majitel přidá. Spuštění vybraného playlistu vyžaduje Premium; bez něj se otevře v aplikaci Spotify.",
        setupSpotifyHelp = "Postup: 1) Adresu Spotify Dashboard zkopíruj z pole do prohlížeče a přihlas se. 2) Create app: libovolný název; Redirect URI zkopíruj z pole (http://127.0.0.1:8765/callback je tvůj vlastní počítač: přihlášení tam zachytí aplikace Evertally, nic nejde jinam); zaškrtni Web API; ulož. 3) Zkopíruj sem Client ID té aplikace. Po Dokončit se jednou otevře prohlížeč k přihlášení ke Spotify. Vlastní aplikace proto, že Spotify novou aplikaci pustí jen účtům, které její majitel přidá. Spuštění vybraného playlistu vyžaduje Premium.",
        musicDashboard = "Spotify Dashboard (klikni, Ctrl+C)", musicRedirect = "Redirect URI (klikni, Ctrl+C)",
        musicDashboardShort = "Dashboard", musicRedirectShort = "Redirect URI",
        musicBadId = "Spotify Client ID má 32 znaků (0-9, a-f).", musicSection = "Hudba", musicOpenWindow = "Otevřít přehrávač hudby",
        musicIconTip = "Klik: ukázat nebo skrýt přehrávač. Pravý klik: knihovna (služba, playlisty, hledání).", musicMini = "Mini přehrávač",
        musicUntitled = "(bez názvu)", musicRowOpen = "Klik: ukázat nebo schovat skladby. Dvojklik: přehrát playlist.",
        musicRowPlay = "Dvojklik: přehrát.", musicRowSong = "Dvojklik: přehrát tuhle skladbu, playlist pak hraje dál."},
}
for lang, entries in pairs(words) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local function settings()
    if not A.db then return {} end
    local s = A.db.settings; if type(s.music) ~= "table" then s.music = {} end
    return s.music
end
function M.Enabled() return A.db ~= nil and settings().enabled == true end
function M.SetEnabled(on) settings().enabled = on == true; if on then settings().hidden = nil end; M.Refresh() end
-- Hidden is only the player window; the music and the icon stay. The icon and Settings bring the player back.
function M.PlayerHidden() return settings().hidden == true end
function M.SetPlayerShown(on) settings().hidden = not on or nil; M.Refresh() end
function M.TogglePlayer() if M.Enabled() then M.SetPlayerShown(M.PlayerHidden()) end end
function M.DuckEnabled() return settings().duck ~= false end
function M.SetDuck(on) settings().duck = on == true end

-- Only printable ASCII crosses the pixel strip; accents in a search are dropped to their base letter or left out.
local FOLD = {["á"]="a",["č"]="c",["ď"]="d",["é"]="e",["ě"]="e",["í"]="i",["ň"]="n",["ó"]="o",["ř"]="r",["š"]="s",["ť"]="t",["ú"]="u",["ů"]="u",["ý"]="y",["ž"]="z",
    ["Á"]="A",["Č"]="C",["Ď"]="D",["É"]="E",["Ě"]="E",["Í"]="I",["Ň"]="N",["Ó"]="O",["Ř"]="R",["Š"]="S",["Ť"]="T",["Ú"]="U",["Ů"]="U",["Ý"]="Y",["Ž"]="Z",
    ["ä"]="a",["ö"]="o",["ü"]="u",["ß"]="ss",["Ä"]="A",["Ö"]="O",["Ü"]="U"}
function M.Ascii(text)
    text = tostring(text or "")
    for from, to in pairs(FOLD) do text = text:gsub(from, to) end
    return (text:gsub("[^\32-\126]", ""))
end
function M.Send(command)
    if not A.OpticalSendCommand then return false, "musicNeedsApp" end
    if not M.Enabled() then return false, "musicOff" end
    if not A.OpticalSendCommand(command) then return false, "musicNotSent" end
    return true, "musicSent"
end
--- For a button the player pressed to set something up: sends and says in chat what happened. The first time in a session the
--- message also says how to tell the app heard it (the app answers with a Windows notification).
function M.SendAndTell(command)
    local ok, why = M.Send(command)
    if ok and not M.toldCheck then M.toldCheck = true; why = "musicCheckApp" end
    A.Print(A.L(why))
    return ok
end
function M.Play(id) return M.Send("m:pl:" .. M.Ascii(id):sub(1, 100)) end
--- A song opened from a playlist plays inside it, so the playlist goes on after it; a too long pair plays the song alone.
function M.PlayIn(id, playlist)
    if not playlist then return M.Play(id) end
    local command = "m:pt:" .. M.Ascii(id) .. "@" .. M.Ascii(playlist)
    if #command > 120 then return M.Play(id) end
    return M.Send(command)
end
function M.Search(text)
    text = M.Ascii(text):match("^%s*(.-)%s*$")
    if text == "" then return false end
    return M.Send("m:find:" .. text:sub(1, 100))
end
M.REDIRECT = "http://127.0.0.1:8765/callback"
-- shown as an address to copy: asking the app to open it did not work for every player
M.DASHBOARD = "https://developer.spotify.com/dashboard"
-- The game cannot open a web page; the app opens Spotify's dashboard. Allowed before the player is switched on (the setup).
function M.OpenDashboard()
    if not A.OpticalSendCommand then return false end
    return A.OpticalSendCommand("m:spdev")
end
function M.ConnectSpotify(id)
    id = tostring(id or ""):gsub("%s", ""):lower()
    if not id:match("^%x+$") or #id ~= 32 then return false, "musicBadId" end
    settings().source = "spotify"
    -- kept here too: the game shows it again after a reload (the app keeps its own copy)
    settings().spotifyId = id
    return M.Send("m:spid:" .. id)
end
function M.SetSource(source)
    if source ~= "spotify" and source ~= "youtube" then return false end
    settings().source = source
    return M.Send("m:src:" .. source)
end

-- The library the app wrote (MusicData.lua), checked before use.
function M.Library()
    local data = rawget(_G, "EvertallyMusicData")
    if type(data) ~= "table" or data.schemaVersion ~= 1 then return nil end
    return data
end
-- A name made only of emoji comes from the app empty (the game's font cannot draw them): it is shown as "untitled".
local function entries(list, nested)
    local out = {}
    for _, e in ipairs(type(list) == "table" and list or {}) do
        local id = type(e) == "table" and A.Text(e.id, 120)
        local name = id and A.Text(e.name, 120)
        if id and type(e.name) == "string" and (name or "") == "" then name = A.L("musicUntitled") end
        if id and name and id:find("^[%w:._%-]+$") then
            local row = {id = id, name = name, artist = A.Text(e.artist, 80), count = A.Number(e.count, 0)}
            -- a playlist's songs (the app reads them with the library); a song inside has no songs of its own
            if not nested and type(e.tracks) == "table" then
                row.tracks = entries(e.tracks, true); if #row.tracks == 0 then row.tracks = nil end
            end
            out[#out + 1] = row
        end
    end
    return out
end
--- The rows of one part of the library, filtered by the typed text (case-insensitive, in name and artist).
function M.Rows(part, filter)
    local data = M.Library(); if not data then return {} end
    -- each tab reads its own list only (an `a and nil or b` chain would show the playlists under an empty tab)
    local source = ({liked = data.liked, recent = data.recent, search = data.search, playlists = data.playlists})[part]
    if part == nil then source = data.playlists end
    local list = entries(source)
    -- compared without accents and case: "cecho" finds "Čechomor"
    filter = A.Text(filter, 60); filter = filter and M.Ascii(filter):lower()
    if not filter or filter == "" then return list end
    local function hit(e) return M.Ascii(e.name):lower():find(filter, 1, true) or (e.artist and M.Ascii(e.artist):lower():find(filter, 1, true)) end
    local out = {}
    for _, e in ipairs(list) do
        if hit(e) then out[#out + 1] = e
        elseif e.tracks then
            -- a playlist with matching songs stays, with only those songs, and opens by itself
            local found = {}
            for _, t in ipairs(e.tracks) do if hit(t) then found[#found + 1] = t end end
            if #found > 0 then out[#out + 1] = {id = e.id, name = e.name, artist = e.artist, count = e.count, tracks = found, found = true} end
        end
    end
    return out
end
--- The lines of the list: each entry, and under an opened playlist its songs (`parent` = the playlist).
--- `opened` is what the player opened or closed by clicking; a playlist the filter found songs in is open unless closed.
function M.Lines(part, filter, opened)
    opened = opened or {}
    local out = {}
    for _, e in ipairs(M.Rows(part, filter)) do
        local choice = opened[e.id]
        local open = e.tracks ~= nil and (choice == true or (choice == nil and e.found == true))
        out[#out + 1] = {e = e, open = open}
        if open then for _, t in ipairs(e.tracks) do out[#out + 1] = {e = t, parent = e.id} end end
    end
    return out
end

-- Quieter while an NPC talks: once per conversation, back to normal when its window closes.
local talking = false
local function duck(on)
    if not M.Enabled() or not M.DuckEnabled() or talking == on then return end
    talking = on
    M.Send(on and "m:duck" or "m:unduck")
end
for _, event in ipairs({"GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE"}) do A.On(event, function() duck(true) end) end
for _, event in ipairs({"GOSSIP_CLOSED", "QUEST_FINISHED"}) do A.On(event, function() duck(false) end) end

-- ---------------------------------------------------------------- the mini player and the library window
local function kit() return A.UIKit and A.UIKit() end
local function button(parent, label, width, onClick)
    local k = kit(); local b = k.Button(parent, nil, width, "ghost", onClick); b:SetHeight(24); b.text:SetText(label); return b
end
function M.Player()
    if M.player then return M.player end
    local k = kit(); if not k or type(CreateFrame) ~= "function" then return nil end
    local T = k.C
    local p = CreateFrame("Frame", "EvertallyMusicPlayer", UIParent)
    -- the small player stays where the player puts it (kept in the settings, also over /reload)
    p:SetSize(300, 62); p:SetFrameStrata("MEDIUM")
    M.Place(p)
    p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton"); p:SetClampedToScreen(true)
    p:SetScript("OnDragStart", function(self) self:StartMoving() end)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetLeft(), self:GetBottom()
        if type(x) == "number" and type(y) == "number" then settings().playerAt = {x = math.floor(x + 0.5), y = math.floor(y + 0.5)} end
    end)
    A.NativePanel(p, T)
    p.title = k.label(p, 11, T.bright); p.title:SetPoint("TOPLEFT", 10, -7); p.title:SetPoint("RIGHT", -30, 0); p.title:SetWordWrap(false)
    p.close = button(p, "x", 22, function() M.SetPlayerShown(false) end); p.close:SetHeight(18); p.close:SetPoint("TOPRIGHT", -4, -4)
    -- separate Play and Pause: the game cannot know whether the music plays, so one toggle could not show its state
    local controls = {{"ShapePrev", "m:prev", "musicPrev"}, {"ShapePlay", "m:play", "musicPlayBtn"}, {"ShapePause", "m:pause", "musicPause"},
        {"ShapeNext", "m:next", "musicNext"}, {"-", "m:vol-", "musicVolDown"}, {"+", "m:vol+", "musicVolUp"}}
    p.buttons = {}
    for i, c in ipairs(controls) do
        local command, tip = c[2], c[3]
        local shaped = c[1]:find("^Shape")
        local b = button(p, shaped and "" or c[1], 34, function() local ok, why = M.Send(command); if not ok then A.Print(A.L(why)) end end)
        b:SetPoint("BOTTOMLEFT", 8 + (i - 1) * 38, 8); p.buttons[command] = b
        if shaped then
            b.icon = b:CreateTexture(nil, "OVERLAY"); b.icon:SetSize(14, 14); b.icon:SetPoint("CENTER")
            b.icon:SetTexture("Interface\\AddOns\\Evertally\\Media\\" .. c[1]); b.icon:SetVertexColor(T.bright[1], T.bright[2], T.bright[3], 1)
        end
        b:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(A.L(tip)); GameTooltip:Show() end end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    p.browse = button(p, A.L("musicBrowse"), 52, function() M.ToggleBrowser() end); p.browse:SetPoint("BOTTOMRIGHT", -8, 8)
    M.player = p
    return p
end
-- Where the small player goes: the saved place when it is on the screen, else the top middle.
function M.Place(p)
    p = p or M.player; if not p then return end
    local at = settings().playerAt
    local w = A.Number(A.Call(UIParent.GetWidth, UIParent), 1) or 1920
    local h = A.Number(A.Call(UIParent.GetHeight, UIParent), 1) or 1080
    p:ClearAllPoints()
    if type(at) == "table" and type(at.x) == "number" and type(at.y) == "number" and at.x >= 0 and at.y >= 0 and at.x <= w - 40 and at.y <= h - 30 then
        p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", at.x, at.y)
    else
        settings().playerAt = nil
        p:SetPoint("TOP", UIParent, "TOP", 0, -12)
    end
end

-- The note icon beside the chat buttons (right of the Evertally chat bubble, or of the Social button): click shows or hides
-- the player, right-click opens the library. Shown while the music is on.
function M.Icon()
    if M.icon then return M.icon end
    if type(CreateFrame) ~= "function" then return nil end
    local k = kit(); if not k then return nil end
    local b = CreateFrame("Button", "EvertallyMusicButton", UIParent)
    b:SetSize(26, 26); b:SetFrameStrata("MEDIUM")
    local chat = A.ChatUI and A.ChatUI.button
    if chat then b:SetPoint("LEFT", chat, "RIGHT", 2, 0)
    elseif A.ChatUI and A.ChatUI.Anchor then local target, point, rel, x, y = A.ChatUI.Anchor(); b:SetPoint(point, target, rel, x + (point == "LEFT" and 30 or 0), y)
    else b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 30, 290) end
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); A.Theme.Shape(b.bg, "round"); k.paint(b.bg, k.C.header, 0.9)
    b.note = b:CreateTexture(nil, "ARTWORK"); b.note:SetPoint("TOPLEFT", 3, -3); b.note:SetPoint("BOTTOMRIGHT", -3, 3)
    b.note:SetTexture("Interface\\AddOns\\Evertally\\Media\\ShapeNote"); b.note:SetVertexColor(k.C.gold[1], k.C.gold[2], k.C.gold[3], 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); A.Theme.Shape(hl, "round"); k.paint(hl, {1, 1, 1}, 0.12)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, mouse) if mouse == "RightButton" then M.ToggleBrowser() else M.TogglePlayer() end end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(A.L("musicTitle")); GameTooltip:AddLine(A.L("musicIconTip"), 0.8, 0.8, 0.8, true); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    M.icon = b
    return b
end

function M.Refresh()
    if not A.db then return end
    if not M.Enabled() then
        if M.player then M.player:Hide() end
        if M.browser then M.browser:Hide() end
        if M.icon then M.icon:Hide() end
        return
    end
    local icon = M.Icon(); if icon then icon:Show(); local c = A.Theme.colors[M.PlayerHidden() and "mist" or "gold"]; icon.note:SetVertexColor(c[1], c[2], c[3], 1) end
    if M.PlayerHidden() then
        if M.player then M.player:Hide() end
        if M.browser and M.browser:IsShown() then M.DrawBrowser() end
        return
    end
    local p = M.Player(); if not p then return end
    -- No song title: the game only learns it at /reload, so it would show the wrong song most of the time.
    p.title:SetText(A.L("musicTitle"))
    p.browse.text:SetText(A.L("musicBrowse"))
    p:Show()
    if M.browser and M.browser:IsShown() then M.DrawBrowser() end
end

local PARTS = {"playlists", "liked", "recent", "search"}
function M.ToggleBrowser()
    local w = M.Browser(); if not w then return end
    if w:IsShown() then w:Hide() else w:Show(); M.DrawBrowser() end
end
function M.Browser()
    if M.browser then return M.browser end
    local k = kit(); if not k or type(CreateFrame) ~= "function" then return nil end
    local T = k.C
    local w = CreateFrame("Frame", "EvertallyMusicBrowser", UIParent)
    w:SetSize(460, 420); w:SetPoint("CENTER", UIParent, "CENTER", 260, 0); w:SetFrameStrata("HIGH")
    w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton"); w:SetClampedToScreen(true)
    w:SetScript("OnDragStart", function(self) self:StartMoving() end)
    w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    A.NativeFrame(w, T)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EvertallyMusicBrowser" end
    w.title = k.label(w, 16, T.bright); w.title:SetPoint("TOPLEFT", 16, -14)
    w.close = button(w, "x", 26, function() w:Hide() end); w.close:SetPoint("TOPRIGHT", -10, -10)
    -- the small player stays on screen until it is switched off here (or with the note icon, or its own x)
    w.mini = k.Chip(w, function() M.SetPlayerShown(M.PlayerHidden()); M.DrawBrowser() end); w.mini:SetPoint("RIGHT", w.close, "LEFT", -8, 0)
    w.sources = {}
    for i, source in ipairs({"spotify", "youtube"}) do
        local chip = k.Chip(w, function() M.SetSource(source); M.DrawBrowser() end)
        chip:SetPoint("TOPLEFT", 16 + (i - 1) * 120, -44); w.sources[source] = chip
    end
    w.spid = k.SearchBox(w, 160, nil); w.spid:SetPoint("TOPLEFT", 256, -44); w.spid:SetHeight(24); w.spid:SetMaxLetters(40)
    w.connect = button(w, "", 70, function()
        local ok, why = M.ConnectSpotify(w.spid:GetText())
        if ok and not M.toldCheck then M.toldCheck = true; why = "musicCheckApp" end
        A.Print(A.L(why))
    end); w.connect:SetPoint("LEFT", w.spid, "RIGHT", 4, 0)
    w.connect:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(A.L("musicSpotifyHelp"), 1, 1, 1, 1, true); GameTooltip:Show() end end)
    w.connect:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    w.search = k.SearchBox(w, 300, nil); w.search:SetPoint("TOPLEFT", 16, -76); w.search:SetPoint("RIGHT", w, "RIGHT", -16, 0)
    -- a search: the app fetches the results in the background and writes them into the library file; the game reads
    -- that file only at /reload, so the window says so and opens on the results after the reload
    w.search:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        local ok, why = M.Search(text)
        if not ok and why then A.Print(A.L(why)) end
        if ok then
            if not M.toldCheck then M.toldCheck = true; A.Print(A.L("musicCheckApp")) end
            settings().showResults = true
            w.searching = M.Ascii(text); w.part = "search"; M.DrawBrowser()
        end
        self:ClearFocus()
    end)
    w.filter = k.SearchBox(w, 300, function() M.DrawBrowser() end); w.filter:SetPoint("TOPLEFT", 16, -108); w.filter:SetPoint("RIGHT", w, "RIGHT", -16, 0)
    w.tabs = {}
    local previous
    for _, part in ipairs(PARTS) do
        local chip = k.Chip(w, function() w.part = part; w.offset = 0; M.DrawBrowser() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 16, -142) end
        w.tabs[part] = chip; previous = chip
    end
    w.list = CreateFrame("Frame", nil, w); w.list:SetPoint("TOPLEFT", 16, -174); w.list:SetPoint("BOTTOMRIGHT", -16, 56)
    A.Theme.Surface(w.list, "reader")
    w.list:EnableMouseWheel(true)
    w.list:SetScript("OnMouseWheel", function(_, delta) w.offset = math.max(0, (w.offset or 0) - delta * 3); M.DrawBrowser() end)
    w.rows = {}
    for i = 1, 8 do
        local r = CreateFrame("Button", nil, w.list); r:SetHeight(22)
        r:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 23); r:SetPoint("TOPRIGHT", -8, -6 - (i - 1) * 23)
        local hover = r:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(); A.Theme.Shape(hover, "round"); k.paint(hover, {1, 1, 1}, 0.06)
        r.text = k.label(r, 12, T.text); r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -6, 0); r.text:SetWordWrap(false)
        -- click opens or closes a playlist's songs; double-click plays (a song inside its playlist)
        r:SetScript("OnDoubleClick", function(self) if self.id then M.PlayIn(self.id, self.parent) end end)
        r:SetScript("OnClick", function(self)
            if self.hasTracks then w.opened[self.id] = not self.open end
            w.selected, w.selectedIn = self.id, self.parent; M.DrawBrowser()
        end)
        r:SetScript("OnEnter", function(self)
            if not GameTooltip or not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(A.L(self.hasTracks and "musicRowOpen" or self.parent and "musicRowSong" or "musicRowPlay"), 1, 1, 1, 1, true); GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        w.rows[i] = r
    end
    w.empty = k.label(w.list, 11, T.mist); w.empty:SetPoint("TOPLEFT", 10, -10); w.empty:SetPoint("TOPRIGHT", -10, -10); w.empty:SetWordWrap(true)
    w.play = k.Button(w, nil, 100, "primary", function() if w.selected then M.PlayIn(w.selected, w.selectedIn) end end); w.play:SetHeight(28); w.play:SetPoint("BOTTOMRIGHT", -16, 16)
    w.refresh = button(w, "", 136, function() M.SendAndTell("m:lib") end); w.refresh:SetHeight(28); w.refresh:SetPoint("BOTTOMLEFT", 16, 16)
    w.load = button(w, "", 176, function() if type(ReloadUI) == "function" then ReloadUI() end end); w.load:SetHeight(28); w.load:SetPoint("LEFT", w.refresh, "RIGHT", 6, 0)
    w.part = "playlists"; w.opened = {}
    w:Hide()
    M.browser = w
    return w
end
function M.DrawBrowser()
    local w = M.browser; if not w then return end
    w.title:SetText(A.L("musicTitle"))
    w.mini.SetLabel(A.L("musicMini")); w.mini.SetOn(not M.PlayerHidden())
    local source = settings().source or "spotify"
    for name, chip in pairs(w.sources) do chip.SetLabel(A.L(name == "spotify" and "musicSpotify" or "musicYoutube")); chip.SetOn(name == source) end
    w.spid.hint:SetText(A.L("musicSpotifyId")); w.connect.text:SetText(A.L("musicSpotifyConnect"))
    w.spid:SetShown(source == "spotify"); w.connect:SetShown(source == "spotify")
    if not (w.spid.HasFocus and w.spid:HasFocus()) and (w.spid:GetText() or "") == "" and settings().spotifyId then
        w.spid:SetText(settings().spotifyId); if w.spid.SetCursorPosition then w.spid:SetCursorPosition(0) end
    end
    w.search.hint:SetText(A.L("musicSearch")); w.filter.hint:SetText(A.L("musicFilter"))
    for name, chip in pairs(w.tabs) do
        chip.SetLabel(A.L(name == "liked" and "musicLiked" or name == "recent" and "musicRecent" or name == "search" and "musicResults" or "musicPlaylists")); chip.SetOn(name == w.part)
    end
    local rows = M.Lines(w.part, w.filter:GetText(), w.opened)
    w.offset = math.max(0, math.min(w.offset or 0, math.max(0, #rows - #w.rows)))
    for i, r in ipairs(w.rows) do
        local line = rows[i + w.offset]
        local e = line and line.e
        r.id, r.parent, r.open, r.hasTracks = e and e.id, line and line.parent, line and line.open, e and e.tracks ~= nil
        r:SetShown(e ~= nil)
        if e then
            -- "+" / "-" before a playlist that has songs to open; its songs are indented under it
            local mark = r.hasTracks and (line.open and "-  " or "+  ") or ""
            local label = (line.parent and "      " or "") .. mark .. e.name .. (e.artist and ("  ·  " .. e.artist) or "") .. (e.count and e.count > 0 and ("  (" .. e.count .. ")") or "")
            r.text:SetText(label)
            local chosen = e.id == w.selected and line.parent == w.selectedIn
            local c = chosen and A.Theme.colors.bright or line.parent and A.Theme.colors.mist or A.Theme.colors.text; r.text:SetTextColor(c[1], c[2], c[3])
        end
    end
    local data = M.Library()
    local waiting = w.searching and w.part == "search"
    w.empty:SetText(waiting and string.format(A.L("musicSearching"), w.searching) or A.L("musicNoLibrary"))
    w.empty:SetShown(not data or waiting and #rows == 0)
    w.play.text:SetText(A.L("musicPlay")); w.refresh.text:SetText(A.L("musicRefresh"))
    w.load.text:SetText(A.L(w.searching and "musicLoadResults" or "musicLoad"))
end

-- After a /reload the player must come back. Login can come too early for another addon or the screen size, so the
-- player is drawn again when the world is there and a moment later; an error is counted for /etally diag, never hidden.
function M.SafeRefresh()
    local ok, err = pcall(M.Refresh)
    if not ok then A.errors.music = (A.errors.music or 0) + 1; M.lastError = tostring(err) end
    return ok
end
A.On("PLAYER_ENTERING_WORLD", function()
    M.SafeRefresh()
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(2, M.SafeRefresh) end
end)
A.On("PLAYER_LOGIN", function()
    M.SafeRefresh()
    -- back from the reload after a search: the window opens on the results
    if M.Enabled() and settings().showResults then
        settings().showResults = nil
        local data = M.Library()
        if data and type(data.search) == "table" and #data.search > 0 then
            local w = M.Browser(); if w then w.part = "search"; w:Show(); M.DrawBrowser() end
        end
    end
    -- the app learns which service the player picked
    if M.Enabled() and settings().source then M.Send("m:src:" .. settings().source) end
end)
