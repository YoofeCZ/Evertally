local _, A = ...
-- Evertally's settings as pages of Evertally Guide's settings window (the Evertally_Guide add-ons, from Polestar): the
-- group "Evertally" leads its sidebar, beside the guide's own pages (Quality of Life, the arrow, gear, ...), with its
-- search, Reset page, Reload UI, Move frames and Close. The values stay in Evertally's own saved settings: every
-- control reads and writes them through get/set (no key of the guide's). set(nil) is the guide's Reset page: it puts
-- the default back. Without the guide the Settings page in Evertally's own window stays as it was (UI.lua).

local GROUP = "evertally"
local ORDER = 1
-- The pages, in order: key, title (locale key), the guide's icon (its Media/UI). A page of plain controls is made of
-- parts: a tab and/or a section (locale keys) and the function that gives their controls (below). 2026-11-19: sharing,
-- the live position and the website are one page with three tabs (they were three pages), the interface one page in
-- three sections.
local PAGES = {
    -- 2026-11-20: named sections, so that the settings window shows them as tiles in two columns (keys = the
    -- controls of the list, by locale key, in that order)
    {key = "evertallysharing", title = "sharingWebSection", icon = "icon-talk",
        parts = {{tab = "setTabInGame", section = "setSecShare", controls = "sharing", keys = {"share", "group", "guild"}},
            {tab = "setTabInGame", section = "setSecPeople", controls = "sharing", keys = {"socialEnabled", "presence"}},
            {tab = "setTabInGame", section = "setSecAnnounce", controls = "sharing", keys = {"partyAnnounce", "bragPrompt"}},
            {tab = "setTabLive", section = "setSecLive", controls = "live", keys = {"liveParty", "liveGuild", "liveFriends", "mapPins"}},
            {tab = "setTabLive", section = "setSecGather", controls = "live",
                keys = {"setupGather", "setupKind_herb", "setupKind_ore", "setupKind_fishing", "setupKind_container"}},
            {tab = "setTabWebsite", section = "setSecWeb", controls = "web", keys = {"web", "liveWeb"}},
            {tab = "setTabWebsite", section = "setSecApp", controls = "web", keys = {"bridgeAutostart", "setPairRow"}}}},
    {key = "evertallyinterface", title = "interfaceSection", icon = "window",
        parts = {{section = "setSecWindows", controls = "look"}, {section = "setSecQuests", controls = "tracker"},
            {section = "setSecTooltips", controls = "tooltips"}, {section = "setSecChat", controls = "chat"}}},
    -- 2026-11-19: what the setup asks about the bags (et-bags) and what the bag window's gear menu holds, in one place
    -- (2026-11-20: the bags, the meter and the sparkles are add-ons of their own: `needs` = the module's table, a page or
    -- part without it is left out)
    {key = "evertallybags", title = "bagsSection", icon = "icon-treasure", needs = "BagWindow",
        parts = {{section = "bwPickTitle", controls = "bags", keys = {"bwPickLabel"}},
            {section = "setSecLoot", controls = "bags", keys = {"lootWindow"}},
            {section = "setSecTracked", controls = "bags", keys = {"bwTrackHide"}},
            {section = "bwStowTitle", controls = "bags", keys = {"bwAutoStow"}},
            {section = "setSecGear", controls = "bags", keys = {"bagHighlight"}},
            {section = "bwCatsTitle", controls = "bags", keys = {"bwCats"}}}},
    -- 2026-11-20: the damage meter, the threat meter and the loot sparkles (Meter.lua, ThreatMeter.lua, LootSparkles.lua)
    {key = "evertallycombat", title = "combatSection", icon = "icon-kill",
        parts = {{section = "setSecMeter", controls = "combat", keys = {"meterEnabled", "meterLock", "meterShow", "meterResetData"}, needs = "Meter"},
            {section = "setSecThreat", controls = "combat", keys = {"threatEnabled", "threatGroupOnly", "threatShow"}, needs = "ThreatMeter"},
            {section = "setSecSparkles", controls = "combat", keys = {"lootSparkles"}, needs = "LootSparkles"}}},
    {key = "evertallyplates", title = "nameplatesSection", icon = "layers"},
    {key = "evertallymusic", title = "musicSection", icon = "speaker"},
    {key = "evertallyactions", title = "actionsSection", icon = "bolt",
        parts = {{section = "setSecCheck", controls = "actions", keys = {"installVerify", "setupRun"}},
            {section = "setSecSend", controls = "actions", keys = {"send", "export", "confirm"}},
            {section = "setSecTools", controls = "actions", keys = {"drawerEdit"}}}},
    {key = "evertallydiagnostics", title = "diagnostics", icon = "bug"},
}
A.SettingsPages = PAGES
local setText = {
    en = {sharingWebSection = "Sharing & website", setTabInGame = "In game", setTabLive = "Live & map", setTabWebsite = "Website",
        setSecWindows = "Evertally's windows", setSecTooltips = "Tooltips and minimap", setSecChat = "Chat", setSecQuests = "Quests",
        bagsSection = "Bags", bwPickLabel = "Bags to use", uiScaleLabel = "Size of Evertally's window",
        setPairRow = "Pair the app with the website",
        setSecShare = "Sharing with players", setSecPeople = "People", setSecAnnounce = "Announcements", setSecLive = "Live position",
        setSecGather = "Gathering on the map", setSecWeb = "Website", setSecApp = "Evertally app", setSecLoot = "Loot",
        setSecTracked = "Tracked items", setSecGear = "Gear", setSecCheck = "Installation", setSecSend = "Sending and export",
        setSecTools = "Tools"},
    cs = {sharingWebSection = "Sdílení a web", setTabInGame = "Ve hře", setTabLive = "Živě a mapa", setTabWebsite = "Web",
        setSecWindows = "Okna Evertally", setSecTooltips = "Tooltipy a minimapa", setSecChat = "Chat", setSecQuests = "Questy",
        bagsSection = "Batoh", bwPickLabel = "Který batoh používat", uiScaleLabel = "Velikost okna Evertally",
        setPairRow = "Spárovat aplikaci s webem",
        setSecShare = "Sdílení s hráči", setSecPeople = "Lidé", setSecAnnounce = "Oznámení", setSecLive = "Živá poloha",
        setSecGather = "Sbírání na mapě", setSecWeb = "Web", setSecApp = "Aplikace Evertally", setSecLoot = "Loot",
        setSecTracked = "Sledované předměty", setSecGear = "Výbava", setSecCheck = "Instalace", setSecSend = "Odeslání a export",
        setSecTools = "Nástroje"},
}
for lang, entries in pairs(setText) do for k, v in pairs(entries) do A.locale[lang][k] = v end end

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

--- choices: a list of {value, locale key}, or a function -> {{value =, text =}, ...} (worked out each time it opens).
--- default: a value or a function -> value (what Reset page puts back).
local function dropdown(key, choices, get, apply, default, extra)
    local c = {kind = "dropdown", label = label(key), localeKey = key,
        choices = function()
            if type(choices) == "function" then return choices() end
            local out = {}
            for i, ch in ipairs(choices) do out[i] = {value = ch[1], text = A.L(ch[2])} end
            return out
        end,
        get = get,
        set = function(v)
            if v == nil then v = type(default) == "function" and default() or default end
            apply(v); changed(key)
        end}
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

--- A slider over Evertally's settings: get() -> number, apply(number); nil from Reset page means `default`.
local function slider(key, lo, hi, step, fmt, get, apply, default, extra)
    local c = {kind = "slider", label = label(key), localeKey = key, min = lo, max = hi, step = step, format = fmt,
        get = function() return tonumber(get()) or default end,
        set = function(v) if v == nil then v = default end; apply(tonumber(v) or default); changed(key) end}
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

local function button(key, run, extra)
    local c = {kind = "button", label = label(key), localeKey = key, button = A.L(key), onClick = function() run(); changed(key) end}
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

-- ---------- Evertally Guide in Czech ----------

-- Evertally in Czech: Evertally Guide in Czech too (Evertally_Guide_csCZ, generated from tools/polestar-cs). Run when
-- Evertally's settings load (ADDON_LOADED), after the guide's files and before its guide packs: the interface strings
-- fill its L (those read while its files loaded, key binding names among them, stay English), the guide texts register
-- for the language the guide was told. The game's names stay English, as the English client shows them. A change of
-- language takes a /reload. -> true when the Czech folder loaded.
function A.ApplyGuideLanguage()
    local g = guide()
    if not (g and A.db and A.db.settings.language == "cs") then return false end
    if g.EvertallyLanguage == "csCZ" then return true end
    g.EvertallyLanguage = "csCZ"
    if g.GuideTexts and type(g.GuideTexts.UseLanguage) == "function" then g.GuideTexts.UseLanguage("csCZ") end
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if type(load) ~= "function" then return false end
    local ok, loaded = pcall(load, "Evertally_Guide_csCZ")
    if ok and loaded then pcall(A.RelabelGuide, g) end
    return ok and loaded and true or false
end

--- The guide's labels its files read before Czech was chosen (the hub's tabs Home, Browse, Current, Recent; its
--- sections Guides, Database, Rares, Import; the Database's kinds; the Rares' tabs) are English strings in tables:
--- each is translated again from the guide's L, now filled in Czech. A label with no Czech stays as it is.
function A.RelabelGuide(g)
    local L = g and g.L
    if type(L) ~= "table" then return 0 end
    local n = 0
    local function cs(text)
        if type(text) ~= "string" then return nil end
        local t = rawget(L, text)
        return type(t) == "string" and t ~= text and t or nil
    end
    -- a map {key = label}, or a list of entries with a label (or a name) field
    local function fields(t)
        if type(t) ~= "table" then return end
        for k, v in pairs(t) do
            if type(v) == "string" then
                local t2 = cs(v); if t2 then t[k] = t2; n = n + 1 end
            elseif type(v) == "table" then
                for _, field in ipairs({"label", "name"}) do
                    local t2 = cs(v[field]); if t2 then v[field] = t2; n = n + 1 end
                end
                -- a section's search placeholders, longest first
                if type(v.searchPlaceholder) == "table" then
                    for i, text in ipairs(v.searchPlaceholder) do local t2 = cs(text); if t2 then v.searchPlaceholder[i] = t2; n = n + 1 end end
                end
            end
        end
    end
    local UI = g.UI or {}
    local P = UI.Picker or {}
    fields(P.VIEW_LABEL); fields(P.HUB_SEARCH)
    if P.GUIDES then fields({P.GUIDES}) end
    if type(P.Sections) == "function" then local ok, list = pcall(P.Sections); if ok then fields(list) end end
    local LK = UI.Lookup or {}
    fields(LK.KIND); fields(LK.FALLBACK_KINDS); fields(LK.FACTION); fields(LK.STATUS_TEXT)
    if g.Search then fields(g.Search.KINDS) end
    if UI.RaresSection then fields(UI.RaresSection.TABS) end
    return n
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

-- The gathering places on the map (settings.mapLayers.gather, on until switched off) and which kinds
-- (settings.gatherTypes[kind] == false hides one): the same values as the setup's map page and Evertally_Map's panel.
local GATHER_KINDS = {"herb", "ore", "fishing", "container"}
local function gatherOn()
    local l = s().mapLayers
    if type(l) ~= "table" or l.gather == nil then return true end
    return l.gather == true
end
local function gatherControls()
    local list = {toggle("setupGather", gatherOn, function(v)
        if A.map and A.map.SetLayer then A.map.SetLayer("gather", v) end
        if type(s().mapLayers) ~= "table" then s().mapLayers = {} end
        s().mapLayers.gather = v
    end, true, {help = A.L("setupGatherSub")})}
    for _, kind in ipairs(GATHER_KINDS) do
        list[#list + 1] = toggle("setupKind_" .. kind, function()
            local t = s().gatherTypes
            return not (type(t) == "table" and t[kind] == false)
        end, function(v)
            if A.map and A.map.SetGatherType then A.map.SetGatherType(kind, v) end
            if type(s().gatherTypes) ~= "table" then s().gatherTypes = {} end
            s().gatherTypes[kind] = v
        end, true, {child = true, disabled = function() return not gatherOn() end})
    end
    return list
end

local function liveControls()
    local list = {
        toggle("liveParty", function() return s().liveParty end, function(v) A.SetLive("party", v) end, false, {help = A.L("liveHint")}),
        toggle("liveGuild", function() return s().liveGuild end, function(v) A.SetLive("guild", v) end, false),
        toggle("liveFriends", function() return s().liveFriends end, function(v) A.SetLive("friends", v) end, false),
        toggle("mapPins", function() return s().mapPins end, function(v) A.SetMapPins(v) end, false),
    }
    for _, c in ipairs(gatherControls()) do list[#list + 1] = c end
    return list
end

local function webControls()
    local webOff = function() return not s().web end
    local publishOff = function() return not (A.CanPublish and A.CanPublish()) end
    local list = {toggle("web", function() return s().web end, function(v) A.SetWeb(v) end, false, {help = A.L("webHint")})}
    -- (2026-11-18: everything is public, as on raider.io: what is sent and what the website shows is not chosen here any more;
    -- the bags stay behind the player's permission in the game)
    local _ = publishOff
    list[#list + 1] = toggle("liveWeb", function() return s().liveWeb end, function(v)
        s().liveWeb = v; if A.OpticalTick then A.OpticalTick() end; if A.MarkWebChanged then A.MarkWebChanged() end
    end, false, {child = true, disabled = webOff, help = A.L("pageLiveWebHint")})
    list[#list + 1] = toggle("bridgeAutostart", function() return A.BridgeAutostart and A.BridgeAutostart() end,
        function(v) if A.SetBridgeAutostart then A.SetBridgeAutostart(v) end end, false)
    local pair = button("setPairRow", function() if A.RequestPairing then A.RequestPairing() end end,
        {help = A.L("setupPairHelp"), disabled = function() return A.BridgePaired ~= nil and A.BridgePaired() end})
    pair.button = A.L("setupPairButton")
    list[#list + 1] = pair
    return list
end

local function lookControls()
    return {
        dropdown("language", {{"en", "langEnglish"}, {"cs", "langCzech"}}, function() return s().language == "cs" and "cs" or "en" end,
            function(v) A.SetLanguage(v) end, "en"),
        dropdown("uiScheme", {{"guide", "uiSchemeGuide"}, {"night", "uiSchemeNight"}, {"dusk", "uiSchemeDusk"}, {"graphite", "uiSchemeGraphite"}},
            function() return A.Theme.SchemeKey() end, function(v) A.Theme.SetScheme(v) end, "guide"),
        dropdown("uiFont", {{"guide", "uiFontGuide"}, {"game", "uiFontGame"}, {"inter", "uiFontInter"}},
            function() local f = s().uiFont; return f == "inter" and "inter" or f == "game" and "game" or "guide" end,
            function(v) A.SetUIFont(v) end, "guide"),
        slider("uiScaleLabel", 0.6, 1.6, 0.05, function(v) return math.floor((tonumber(v) or 1) * 100 + 0.5) .. " %" end,
            function() return A.GetUIScale and A.GetUIScale() or 1 end, function(v) if A.SetUIScale then A.SetUIScale(v) end end, 1),
    }
end

-- Which quest tracker (et-tracker): the same choice (settings.questTracker.choice), applied at once.
local function trackerControls()
    local QT = function() return A.QuestTracker end
    return {
        dropdown("qtPickTitle", function()
            local out = {}
            local list = QT() and QT().Choices and QT().Choices() or {"evertally", "blizzard"}
            for i, c in ipairs(list) do out[i] = {value = c, text = A.L("qtPick_" .. c), tip = A.L("qtPickSub_" .. c)} end
            return out
        end, function() return QT() and QT().Choice and QT().Choice() or nil end,
        function(v) if A.SetQuestTrackerChoice then A.SetQuestTrackerChoice(v) end end, "evertally", {help = A.L("qtPickBody")}),
    }
end
local function tooltipControls()
    return {
        toggle("rankTooltip", function() return s().rankTooltip ~= false end, function(v) s().rankTooltip = v end, true),
        toggle("minimap", function() return not s().hideMinimap end, function(v) A.SetMinimapButton(v) end, true),
    }
end

-- The bags: which ones (et-bags, settings.bagWindow.choice: Evertally's, the game's or a bag add-on's), the loot
-- window, the tracked items, the gear arrows and the categories (BagWindow.lua, BagCategories.lua, LootWindow.lua).
local function bagControls()
    local BW = function() return A.BagWindow end
    return {
        dropdown("bwPickLabel", function()
            local out = {}
            for i, ch in ipairs(BW() and BW().Choices and BW().Choices() or {}) do out[i] = {value = ch.value, text = ch.name, tip = ch.desc} end
            return out
        end, function() return BW() and BW().Choice and BW().Choice() or nil end,
        function(v)
            if BW() and BW().SetChoice and BW().SetChoice(v) and BW().ReloadIfNeeded then BW().ReloadIfNeeded() end
        end,
        -- Reset page: the bags in use stay (a bag add-on that is loaded, else Evertally's), no add-on is switched
        function() return BW() and BW().OtherBagAddon and BW().OtherBagAddon() or "evertally" end, {help = A.L("bwPickBody")}),
        toggle("lootWindow", function() return A.LootWindow and A.LootWindow.Enabled() end, function(v) if A.LootWindow then A.LootWindow.SetEnabled(v) end end, false,
            {help = A.L("lootWindowHelp")}),
        toggle("bwTrackHide", function() return BW() and BW().TrackHides() end, function(v) if BW() and BW().SetTrackHide then BW().SetTrackHide(v) end end, true),
        toggle("bwAutoStow", function() return BW() and BW().AutoStows and BW().AutoStows() end,
            function(v) if BW() and BW().SetAutoStow then BW().SetAutoStow(v) end end, true, {help = A.L("bwAutoStowHelp")}),
        toggle("bagHighlight", function() return s().bagHighlight ~= false end, function(v) if A.BagHighlight then A.BagHighlight.SetEnabled(v) end end, true,
            {disabled = function() return A.Gear and A.Gear.GuideHas and A.Gear.GuideHas("bagArrows") end, help = A.L("bagHighlightGuide")}),
        button("bwCats", function() if BW() and BW().Categories then BW().Categories.Show() end end),
    }
end
local function chatControls()
    return {
        toggle("chatEnabled", function() return A.Chat and A.Chat.Settings().enabled ~= false end, function(v) if A.Chat then A.Chat.SetEnabled(v) end end, true),
        toggle("chatRedirect", function() return A.Chat and A.Chat.Settings().redirect end, function(v) if A.Chat then A.Chat.SetRedirect(v) end end, false,
            {child = true, disabled = function() return not (A.Chat and A.Chat.Settings().enabled ~= false) end}),
    }
end

local function combatControls()
    local Mt = function() return A.Meter end
    local Th = function() return A.ThreatMeter end
    local ms = function() return Mt() and Mt().Settings() or {} end
    return {
        toggle("meterEnabled", function() return Mt() and Mt().Enabled() end, function(v) if Mt() then Mt().SetEnabled(v) end end, false,
            {help = A.L("meterEnabledHelp")}),
        toggle("meterLock", function() return ms().locked == true end, function(v) if Mt() then Mt().SetLocked(v) end end, false),
        button("meterShow", function() if Mt() then Mt().SetEnabled(true) end end),
        button("meterResetData", function() if Mt() then Mt().Reset(); A.Print(A.L("mtResetDone")) end end, {confirm = true}),
        toggle("threatEnabled", function() return Th() and Th().Enabled() end, function(v) if Th() then Th().SetEnabled(v) end end, false,
            {help = A.L("threatEnabledHelp")}),
        toggle("threatGroupOnly", function() return ms().threatGroupOnly == true end, function(v) ms().threatGroupOnly = v; if Th() then Th().Update() end end, false,
            {child = true, disabled = function() return not (Th() and Th().Enabled()) end}),
        button("threatShow", function() if Th() then Th().SetEnabled(true) end end),
        toggle("lootSparkles", function() return A.LootSparkles and A.LootSparkles.Enabled() end,
            function(v) if A.LootSparkles then A.LootSparkles.SetEnabled(v) end end, true, {help = A.L("lootSparklesHelp")}),
    }
end

local function actionControls()
    return {
        button("installVerify", function() A.VerifyInstallation(); A.ShowRequirements() end, {help = A.L("installLimited")}),
        button("send", function() local ok, err = A.ShareNow(); if not ok then A.Print(err or "sharing_error") end end),
        button("export", function() if A.ShowExportCopy then A.ShowExportCopy() end end),
        button("confirm", function() A.FinishRun("manual", "last_boss") end, {confirm = true}),
        button("setupRun", function() if A.OpenOnboarding then A.OpenOnboarding() end end),
        button("drawerEdit", function() if A.Drawers then A.Drawers.Show() end end),
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

local CONTROLS = {sharing = sharingControls, live = liveControls, web = webControls, look = lookControls,
    tracker = trackerControls, tooltips = tooltipControls, chat = chatControls, bags = bagControls, combat = combatControls, actions = actionControls}
local CUSTOM = {evertallyplates = platesPage, evertallymusic = musicPage, evertallydiagnostics = diagnosticsPage}
local SUBTITLE = {evertallyactions = "pageActionHint"}

--- The specs handed to the guide's RegisterOptions, in order (tests read them too).
function A.SettingsSpecs()
    local specs = {}
    for i, p in ipairs(PAGES) do
        local base = {page = A.L(p.title), key = p.key, icon = p.icon, order = ORDER + i * 0.01, group = GROUP,
            subtitle = SUBTITLE[p.key] and A.L(SUBTITLE[p.key]) or nil}
        if p.needs and A[p.needs] == nil then
            -- the module is not installed: no page
        elseif CUSTOM[p.key] then
            base.custom, base.controls = CUSTOM[p.key], {}
            specs[#specs + 1] = base
        else
            for _, part in ipairs(p.parts) do
              if not (part.needs and A[part.needs] == nil) then
                local spec = {}
                for k, v in pairs(base) do spec[k] = v end
                spec.tab = part.tab and A.L(part.tab) or nil
                spec.section = part.section and A.L(part.section) or nil
                local list = CONTROLS[part.controls]()
                if part.keys then
                    -- the controls named, in that order (each one exactly once on the page: tests check it)
                    local byKey = {}
                    for _, c in ipairs(list) do byKey[c.localeKey] = c end
                    list = {}
                    for _, key in ipairs(part.keys) do if byKey[key] then list[#list + 1] = byKey[key] end end
                end
                spec.controls = list
                specs[#specs + 1] = spec
              end
            end
        end
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
