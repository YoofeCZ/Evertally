local _, A = ...
-- Evertally's settings as pages of Evertally Guide's settings window (the Evertally_Guide add-ons, from Polestar): the
-- group "Evertally" leads its sidebar, beside the guide's own pages (Quality of Life, the arrow, gear, ...), with its
-- search, Reset page, Reload UI, Move frames and Close. The values stay in Evertally's own saved settings: every
-- control reads and writes them through get/set (no key of the guide's). set(nil) is the guide's Reset page: it puts
-- the default back. Without the guide the Settings page in Evertally's own window stays as it was (UI.lua).

local GROUP = "evertally"
local ORDER = 1
-- The pages, in order: key, title (locale key), the guide's icon (its Media/UI).
local PAGES = {
    {key = "evertallysharing", title = "sharingSection", icon = "icon-talk"},
    {key = "evertallylive", title = "liveSection", icon = "eye"},
    {key = "evertallyweb", title = "webSection", icon = "plug"},
    {key = "evertallyinterface", title = "interfaceSection", icon = "window"},
    {key = "evertallyplates", title = "nameplatesSection", icon = "layers"},
    {key = "evertallymusic", title = "musicSection", icon = "speaker"},
    {key = "evertallyactions", title = "actionsSection", icon = "bolt"},
    {key = "evertallydiagnostics", title = "diagnostics", icon = "bug"},
}
A.SettingsPages = PAGES

local function s() return A.db.settings end
local function guide() local g = rawget(_G, "EvertallyGuide"); return type(g) == "table" and g or nil end

-- After a change: rows the guide greys out by a rule look again (its SETTING_CHANGED), and Evertally redraws.
local function changed(name)
    local g = guide()
    if g and g.Fire then pcall(g.Fire, "SETTING_CHANGED", "evertally." .. tostring(name)) end
    if A.RefreshUI then A.RefreshUI() end
end

local function label(key) return function() return A.L(key) end end

--- A toggle over Evertally's settings: get() -> boolean, apply(boolean); nil from Reset page means `default`.
local function toggle(key, get, apply, default, extra)
    local c = {kind = "toggle", label = label(key), localeKey = key,
        get = function() return get() == true end,
        set = function(v) if v == nil then v = default end; apply(v == true); changed(key) end}
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

local function dropdown(key, choices, get, apply, default)
    return {kind = "dropdown", label = label(key), localeKey = key,
        choices = function()
            local out = {}
            for i, ch in ipairs(choices) do out[i] = {value = ch[1], text = A.L(ch[2])} end
            return out
        end,
        get = get,
        set = function(v) if v == nil then v = default end; apply(v); changed(key) end}
end

local function button(key, run, extra)
    local c = {kind = "button", label = label(key), localeKey = key, button = A.L(key), onClick = function() run(); changed(key) end}
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

-- ---------- the pages of plain controls ----------

local function sharingControls()
    local off = function() return not s().ingame end
    return {
        toggle("share", function() return s().ingame end, function(v) A.SetIngame(v) end, false),
        toggle("group", function() return s().group end, function(v) s().group = v end, false, {child = true, disabled = off}),
        toggle("guild", function() return s().guild end, function(v) s().guild = v end, false, {child = true, disabled = off}),
        toggle("socialEnabled", function() return s().social ~= false end, function(v) s().social = v end, true),
        toggle("partyAnnounce", function() return s().partyAnnounce ~= false end, function(v) if A.Announce then A.Announce.SetEnabled(v) end end, true),
        toggle("bragPrompt", function() return s().bragPrompt ~= false end, function(v) if A.Announce then A.Announce.SetBragEnabled(v) end end, true),
        toggle("presence", function() return s().presence == true end, function(v) if A.Presence then A.Presence.SetEnabled(v) end end, false),
    }
end

local function liveControls()
    return {
        toggle("liveParty", function() return s().liveParty end, function(v) A.SetLive("party", v) end, false, {help = A.L("liveHint")}),
        toggle("liveGuild", function() return s().liveGuild end, function(v) A.SetLive("guild", v) end, false),
        toggle("liveFriends", function() return s().liveFriends end, function(v) A.SetLive("friends", v) end, false),
        toggle("mapPins", function() return s().mapPins end, function(v) A.SetMapPins(v) end, false),
    }
end

local function webControls()
    local webOff = function() return not s().web end
    local publishOff = function() return not (A.CanPublish and A.CanPublish()) end
    local list = {toggle("web", function() return s().web end, function(v) A.SetWeb(v) end, false, {help = A.L("webHint")})}
    for _, scope in ipairs({"world_facts", "own_runs", "own_character", "own_professions", "own_track", "guild_share"}) do
        local key = scope
        list[#list + 1] = toggle(key, function() return s().scopes[key] end, function(v) A.SetScope(key, v) end, false, {child = true, disabled = webOff})
    end
    list[#list + 1] = toggle("leaderboard", function() return A.PublishChoice and A.PublishChoice().public end,
        function(v) A.SetPublish("public", v) end, false, {child = true, disabled = publishOff})
    for _, pair in ipairs({{"itemLevel", "leaderboardItemLevel"}, {"guild", "leaderboardGuild"}, {"gear", "leaderboardGear"}, {"chronicle", "leaderboardChronicle"}}) do
        local field, key = pair[1], pair[2]
        list[#list + 1] = toggle(key, function() return A.PublishChoice and A.PublishChoice()[field] end, function(v) A.SetPublish(field, v) end, false,
            {child = true, disabled = function() return publishOff() or A.PublishChoice().public ~= true end})
    end
    list[#list + 1] = toggle("liveWeb", function() return s().liveWeb end, function(v)
        s().liveWeb = v; if A.OpticalTick then A.OpticalTick() end; if A.MarkWebChanged then A.MarkWebChanged() end
    end, false, {child = true, disabled = webOff, help = A.L("pageLiveWebHint")})
    list[#list + 1] = toggle("bridgeAutostart", function() return A.BridgeAutostart and A.BridgeAutostart() end,
        function(v) if A.SetBridgeAutostart then A.SetBridgeAutostart(v) end end, false)
    return list
end

local function interfaceControls()
    return {
        dropdown("language", {{"en", "langEnglish"}, {"cs", "langCzech"}}, function() return s().language == "cs" and "cs" or "en" end,
            function(v) A.SetLanguage(v) end, "en"),
        dropdown("uiScheme", {{"night", "uiSchemeNight"}, {"dusk", "uiSchemeDusk"}, {"graphite", "uiSchemeGraphite"}},
            function() return A.Theme.SchemeKey() end, function(v) A.Theme.SetScheme(v) end, "night"),
        dropdown("uiFont", {{"game", "uiFontGame"}, {"inter", "uiFontInter"}}, function() return s().uiFont == "inter" and "inter" or "game" end,
            function(v) A.SetUIFont(v) end, "game"),
        toggle("rankTooltip", function() return s().rankTooltip ~= false end, function(v) s().rankTooltip = v end, true),
        toggle("minimap", function() return not s().hideMinimap end, function(v) A.SetMinimapButton(v) end, true),
        toggle("bagHighlight", function() return s().bagHighlight ~= false end, function(v) if A.BagHighlight then A.BagHighlight.SetEnabled(v) end end, true),
        toggle("chatEnabled", function() return A.Chat and A.Chat.Settings().enabled ~= false end, function(v) if A.Chat then A.Chat.SetEnabled(v) end end, true),
        toggle("chatRedirect", function() return A.Chat and A.Chat.Settings().redirect end, function(v) if A.Chat then A.Chat.SetRedirect(v) end end, false,
            {child = true, disabled = function() return not (A.Chat and A.Chat.Settings().enabled ~= false) end}),
    }
end

local function actionControls()
    return {
        button("installVerify", function() A.VerifyInstallation(); A.ShowRequirements() end),
        button("send", function() local ok, err = A.ShareNow(); if not ok then A.Print(err or "sharing_error") end end),
        button("export", function() if A.ShowExportCopy then A.ShowExportCopy() end end),
        button("confirm", function() A.FinishRun("manual", "last_boss") end, {confirm = true}),
        button("setupRun", function() if A.OpenOnboarding then A.OpenOnboarding() end end),
    }
end

-- ---------- pages drawn by hand (custom = function(view); view.Refresh() -> height) ----------

-- The nameplate editor (NameplateUI.lua), as it stands in Evertally's own settings.
local function platesPage(view)
    local panel = A.BuildFriendlyPlateControls(view)
    panel:SetPoint("TOPLEFT", view, "TOPLEFT", 24, -16)
    panel:SetPoint("TOPRIGHT", view, "TOPRIGHT", -24, -16)
    panel:SetHeight(560)
    view.Refresh = function() if panel.Update then panel.Update() end; return 600 end
end

-- Music: the switches, where it plays from, and for Spotify the app id and the two addresses to copy.
local function musicPage(view)
    local g = guide(); local W = g.Widgets
    local rows, y = {}, 16
    local function place(row, height)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", view, "TOPLEFT", 24, -y); row:SetPoint("TOPRIGHT", view, "TOPRIGHT", -24, -y)
        rows[#rows + 1] = row; y = y + (height or row:GetHeight() or 36)
    end
    local M = function() return A.Music end
    local on = W.Toggle(view, A.L("musicEnabled"), nil, nil, nil, {get = function() return M() and M().Enabled() end,
        set = function(v) if M() then M().SetEnabled(v == true) end; changed("musicEnabled") end})
    place(on, 40)
    local duck = W.Toggle(view, A.L("musicDuck"), nil, nil, nil, {get = function() return M() and M().DuckEnabled() end,
        set = function(v) if M() then M().SetDuck(v == true) end; changed("musicDuck") end})
    W.SetDisabledWhen(duck, function() return not (M() and M().Enabled()) end)
    place(duck, 40)
    local source = W.Dropdown(view, A.L("musicSource"), nil,
        function() return {{value = "spotify", text = A.L("musicSpotify")}, {value = "youtube", text = A.L("musicYoutube")}} end, nil, nil,
        {get = function() return A.db.settings.music and A.db.settings.music.source or "spotify" end,
         set = function(v) if M() then M().SetSource(v or "spotify") end; changed("musicSource"); if view.Refresh then view.Refresh() end end})
    place(source, 44)
    local idLabel = W.Text(view, "label", "text"); place(idLabel, 22)
    local id = W.SearchBox(view, "0123456789abcdef…", function() end); id:SetMaxLetters(40); place(id, 38)
    local connect = W.Button(view, A.L("musicSpotifyConnect"), function()
        if not M() then return end
        local ok, why = M().ConnectSpotify(id:GetText())
        if ok and not M().toldCheck then M().toldCheck = true; why = "musicCheckApp" end
        A.Print(A.L(why))
    end, {primary = true})
    connect:ClearAllPoints(); connect:SetPoint("TOPLEFT", view, "TOPLEFT", 24, -y); y = y + 40
    local dashLabel = W.Text(view, "label", "text"); place(dashLabel, 22)
    local dash = W.CopyBox(view); place(dash, 38)
    local redirLabel = W.Text(view, "label", "text"); place(redirLabel, 22)
    local redir = W.CopyBox(view); place(redir, 38)
    local help = W.Text(view, "note", "textMuted"); help:SetWordWrap(true); help:SetJustifyH("LEFT"); place(help, 80)
    local open = W.Button(view, A.L("musicOpenWindow"), function() if M() then M().SetEnabled(true); M().ToggleBrowser() end end)
    open:ClearAllPoints(); open:SetPoint("TOPLEFT", view, "TOPLEFT", 24, -y); y = y + 44
    local function copy(box, text) box.psText = text; box:SetText(text) end
    view.Refresh = function()
        local spotify = (A.db.settings.music and A.db.settings.music.source or "spotify") ~= "youtube"
        idLabel:SetText(A.L("musicSpotifyId")); dashLabel:SetText(A.L("musicDashboardShort")); redirLabel:SetText(A.L("musicRedirectShort"))
        for _, w in ipairs({idLabel, id, connect, dashLabel, dash, redirLabel, redir}) do w:SetShown(spotify) end
        copy(dash, M() and M().DASHBOARD or ""); copy(redir, M() and M().REDIRECT or "")
        local saved = A.db.settings.music and A.db.settings.music.spotifyId
        if saved and (id:GetText() or "") == "" and not (id.HasFocus and id:HasFocus()) then id:SetText(saved) end
        help:SetText(A.L(spotify and "musicSpotifyHelp" or "setupMusicYoutubeHelp"))
        for _, w in ipairs({on, duck, source}) do if w.Refresh then w:Refresh() end end
        return y + 16
    end
end

-- The diagnostics: the text /etally diag prints, to read or copy.
local function diagnosticsPage(view)
    local W = guide().Widgets
    local box = W.CopyBox(view, {lines = 12})
    box:SetPoint("TOPLEFT", view, "TOPLEFT", 24, -16); box:SetPoint("TOPRIGHT", view, "TOPRIGHT", -24, -16)
    view.Refresh = function() local text = A.Diagnostics(); box.psText = text; box:SetText(text); return 16 + box:GetHeight() + 24 end
end

-- ---------- registration ----------

local CONTROLS = {evertallysharing = sharingControls, evertallylive = liveControls, evertallyweb = webControls,
    evertallyinterface = interfaceControls, evertallyactions = actionControls}
local CUSTOM = {evertallyplates = platesPage, evertallymusic = musicPage, evertallydiagnostics = diagnosticsPage}
local SUBTITLE = {evertallyactions = "pageActionHint"}

--- The specs handed to the guide's RegisterOptions, in order (tests read them too).
function A.SettingsSpecs()
    local specs = {}
    for i, p in ipairs(PAGES) do
        local spec = {page = A.L(p.title), key = p.key, icon = p.icon, order = ORDER + i * 0.01, group = GROUP,
            subtitle = SUBTITLE[p.key] and A.L(SUBTITLE[p.key]) or nil}
        if CUSTOM[p.key] then spec.custom, spec.controls = CUSTOM[p.key], {} else spec.controls = CONTROLS[p.key]() end
        specs[#specs + 1] = spec
    end
    return specs
end

--- Registers the pages with the guide's settings window. -> true when it did.
function A.InstallGuideSettings()
    if A.guideSettings then return true end
    local g = guide()
    if not (g and type(g.RegisterOptions) == "function" and A.db) then return false end
    local ok = true
    for _, spec in ipairs(A.SettingsSpecs()) do
        local done, err = g.RegisterOptions(spec)
        if not done then ok = false; A.lastUIError = "settings: " .. tostring(err) end
    end
    A.guideSettings = ok
    return ok
end

--- Opens the guide's settings window on Evertally's first page (or the page named). -> true when it did.
function A.ShowGuideSettings(key)
    local g = guide()
    if not (A.guideSettings and g and g.UI and type(g.UI.ShowOptions) == "function") then return false end
    g.UI.ShowOptions(key or PAGES[1].key)
    return true
end

-- Titles and labels are in Evertally's language: registered once its settings are loaded.
A.On("PLAYER_LOGIN", function() A.InstallGuideSettings() end)
