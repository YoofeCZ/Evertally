local _, A = ...
-- Evertally's setup as pages of Evertally Guide's Install window (UI/Welcome.lua of the guide, its look: the night
-- hero, the switch rows, the option cards, the step dots). One window for both: the guide's welcome first, then
-- Evertally's steps (language, the installation check, the pairing, the website, the public page, position, sharing,
-- the map, the window, nameplates, music), the guide's own (questing, targeting, groups, route, look), Evertally's
-- summary and the guide's finish. The choices are Evertally's draft (Onboarding.lua): nothing is applied until
-- Finish, the installation check and the pairing hold Next back as before. Without the guide Onboarding.lua's own
-- window stays.
local P = {}
A.setupPages = P
local KIND_KEYS = {"herb", "ore", "fishing", "container"}
local SCOPES = {"world_facts", "own_runs", "own_character", "own_professions", "own_track"}   -- (Onboarding.lua's order)
local SCALES = {{"Small", 0.85}, {"Normal", 1}, {"Large", 1.2}}

local text = {
    en = {setupLangTitle = "Language and privacy", setupLangName_en = "English", setupLangName_cs = "Čeština",
        setupLangSub_en = "Interface in English", setupLangSub_cs = "Rozhraní v češtině", setupQuickTitle = "Quick choice",
        setupSizeTitle = "Window size", setupHostSumTitle = "Summary", setupMusicSource = "Played by", setupSpotifyIdTitle = "Your Spotify Client ID"},
    cs = {setupLangTitle = "Jazyk a soukromí", setupLangName_en = "English", setupLangName_cs = "Čeština",
        setupLangSub_en = "Interface in English", setupLangSub_cs = "Rozhraní v češtině", setupQuickTitle = "Rychlá volba",
        setupSizeTitle = "Velikost okna", setupHostSumTitle = "Shrnutí", setupMusicSource = "Přehrává", setupSpotifyIdTitle = "Tvoje Spotify Client ID"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local function guideUI()
    local g = rawget(_G, "EvertallyGuide")
    local UI = type(g) == "table" and g.UI
    if type(UI) == "table" and type(UI.WelcomeHost) == "function" and type(UI.WelcomeKit) == "table" and type(UI.Welcome) == "table" then return UI end
    return nil
end
local function D() return A.SetupDraft() end
local K -- the guide's kit (UI.WelcomeKit), set when the pages register

-- ---------------------------------------------------------------- the parts every page uses
local function changed()
    A.OnboardingNormalize(D())
    K.refresh()
end
-- A switch row of the guide's look on the draft: get() / set(value); disabled() greys it.
local function toggle(p, labelKey, subKey, get, set, disabled, child)
    local row = K.toggleRow(p, A.L(labelKey), nil, subKey and A.L(subKey) or "",
        {get = get, set = function(v) set(v == true); changed() end, child = child})
    row.etLabel, row.etSub = labelKey, subKey
    if disabled then K.W.SetDisabledWhen(row, disabled) end
    return row
end
local function relabel(rows)
    for _, row in ipairs(rows) do
        row.Label:SetText(A.L(row.etLabel))
        row.Desc:SetText(row.etSub and A.L(row.etSub) or "")
    end
end
local function para(p, role, color)
    local fs = K.para(p, role or "note", color or "textMuted", K.CW, 3)
    return fs
end
-- a line of text at y, hidden when empty. -> the y under it
local function line(fs, value, y, gap)
    fs:SetText(value or "")
    local shown = value ~= nil and value ~= ""
    fs:SetShown(shown)
    if not shown then return y end
    K.place(fs, 0, y)
    return y + fs:GetStringHeight() + (gap or 10)
end
local function button(p, onClick, primary)
    return K.W.Button(p, "", onClick, {primary = primary})
end
local function buttonText(b, key) if K.W.SetButtonText then K.W.SetButtonText(b, A.L(key)) elseif b.Label then b.Label:SetText(A.L(key)) end end

-- One page of the window: its hero (title, line), its body (build once; layout(body, P) -> its height) and whether it
-- holds Next back.
local pages = {}
local function page(spec)
    pages[#pages + 1] = {
        key = spec.key, after = spec.after, blocked = spec.blocked,
        build = function(Pg)
            K.compactHero(Pg.Hero, A.L(spec.title), "", false)
            spec.build(Pg.Body, Pg)
        end,
        layout = function(Pg, extra)
            Pg.Hero.Title:SetText(A.L(spec.title))
            local sub = type(spec.sub) == "function" and spec.sub() or spec.sub
            Pg.Hero.Sub:SetText(sub and A.L(sub) or "")
            local heroH = K.layoutCompactHero(Pg.Hero)
            return heroH, spec.layout(Pg.Body, Pg, extra or 0)
        end,
        title = function(Pg) return Pg.Hero.Title:GetText() end,
    }
end

-- ---------------------------------------------------------------- the pages
page({key = "et-language", after = "welcome", title = "setupLangTitle", sub = "setupWelcomeBody",
    build = function(p)
        p.lang = K.optionGroup(p, {title = A.L("setupLanguage"),
            get = function() return D().language end,
            set = function(v) v = v or "en"; D().language = v; if A.SetLanguage then A.SetLanguage(v) end; K.refresh() end,
            choices = function() return {{value = "en", name = A.L("setupLangName_en"), desc = A.L("setupLangSub_en")},
                {value = "cs", name = A.L("setupLangName_cs"), desc = A.L("setupLangSub_cs")}} end})
        p.privacy = para(p, "body", "textDim")
        p.existing = para(p, "note", "warning")
    end,
    layout = function(p)
        p.lang.Title:SetText(A.L("setupLanguage"))
        local y = K.layGroup(p.lang, 0, true) + 16
        y = line(p.privacy, A.L("setupPrivacy"), y)
        return line(p.existing, A.onboarding.existing and A.L("setupExisting") or nil, y)
    end})

page({key = "et-install", after = "et-language", title = "setupGetTitle", sub = "setupGetBody",
    blocked = function() return A.RequirementsReady ~= nil and not A.RequirementsReady() end,
    build = function(p)
        p.holder = CreateFrame("Frame", nil, p); p.holder:SetSize(K.CW, 370)
        p.install = A.BuildInstallationControls(p.holder)
        p.install:SetPoint("TOPLEFT", 0, 0); p.install:SetPoint("BOTTOMRIGHT", 0, 0)
    end,
    layout = function(p)
        K.place(p.holder, 0, 0)
        if p.install.Update then pcall(p.install.Update) end
        return 370
    end})

page({key = "et-pair", after = "et-install", title = "setupPairTitle", sub = "setupPairBody",
    blocked = function() return A.BridgePaired ~= nil and not A.BridgePaired() end,
    build = function(p)
        p.status = para(p, "body", "text")
        p.pair = button(p, function() A.RequestPairing() end, true)
        p.verify = button(p, function()
            if A.Call(InCombatLockdown) == true then A.Print(A.L("markPlatesCombat")); return end
            A.Call(ReloadUI)
        end)
        p.help = para(p)
        p.autostart = toggle(p, "bridgeAutostart", "bridgeAutostartSub", function() return A.BridgeAutostart() == true end, function(on) A.SetBridgeAutostart(on) end)
        p.autostartState = para(p)
    end,
    layout = function(p)
        local state = A.BridgePairing()
        local key = state == "paired" and "setupPairDone" or A.BridgePairingRequested() and "setupPairWaiting" or state == "unknown" and "setupPairOld" or "setupPairNot"
        local y = line(p.status, A.L(key), 0, 12)
        K.W.Color(p.status, state == "paired" and "success" or "warning")
        buttonText(p.pair, "setupPairButton"); buttonText(p.verify, "setupPairVerify")
        p.pair:SetShown(state ~= "paired")
        K.place(p.pair, 0, y); p.verify:ClearAllPoints()
        if state ~= "paired" then p.verify:SetPoint("LEFT", p.pair, "RIGHT", 8, 0) else K.place(p.verify, 0, y) end
        y = y + 40
        y = line(p.help, A.L(state == "paired" and "setupPairDoneHelp" or "setupPairHelp"), y, 8)
        relabel({p.autostart})
        y = K.layRows({p.autostart}, y)
        local reported = A.BridgeAutostartReported()
        return line(p.autostartState, reported ~= nil and string.format(A.L("setupAutostartNow"), A.L(reported and "setupOn" or "setupOff")) or nil, y + 8)
    end})

page({key = "et-website", after = "et-pair", title = "setupWebTitle", sub = "setupWebBody",
    build = function(p)
        p.quick = para(p, "body", "text")
        p.presets = {}
        for _, name in ipairs({"local_only", "recommended", "everything"}) do
            p.presets[#p.presets + 1] = {name = name, button = button(p, function() A.OnboardingPreset(D(), name); changed() end)}
        end
        p.web = toggle(p, "web", nil, function() return D().web end, function(on) D().web = on; if not on then D().liveWeb = false end end)
        p.scopes = {}
        for _, scope in ipairs(SCOPES) do
            p.scopes[#p.scopes + 1] = toggle(p, scope, nil, function() return D().scopes[scope] == true end, function(on) D().scopes[scope] = on end,
                function() return not D().web or (D().liveWeb and (scope == "own_character" or scope == "own_track")) end, true)
        end
        p.missing = para(p, "note", "warning")
    end,
    layout = function(p)
        local y = line(p.quick, A.L("setupQuick"), 0, 8)
        local x = 0
        for _, entry in ipairs(p.presets) do
            buttonText(entry.button, entry.name == "local_only" and "setupPresetLocal" or entry.name == "recommended" and "setupPresetRecommended" or "setupPresetEverything")
            K.place(entry.button, x, y); x = x + (entry.button:GetWidth() or 120) + 8
        end
        y = y + 40
        relabel({p.web}); relabel(p.scopes)
        y = K.layRows({p.web}, y)
        y = K.layRows(p.scopes, y)
        return line(p.missing, A.ExportStore() and "" or A.L("setupWebMissing"), y + 10)
    end})

page({key = "et-public", after = "et-website", title = "setupPublicTitle", sub = "setupPublicBody",
    build = function(p)
        local function public() local d = D(); return d.publish == true and d.web and d.scopes.own_character end
        p.publish = toggle(p, "leaderboard", "setupPublicSub", function() return public() and true or false end,
            function(on) local d = D(); d.publish = on; if on then d.web, d.scopes.own_character = true, true end end)
        p.extras = {}
        for _, entry in ipairs({{"itemLevel", "leaderboardItemLevel"}, {"guildName", "leaderboardGuild"}, {"gear", "leaderboardGear"}}) do
            local key = entry[1]
            p.extras[#p.extras + 1] = toggle(p, entry[2], nil, function() return public() and D()[key] == true end, function(on) D()[key] = on end,
                function() return not public() end, true)
        end
        p.chronicle = K.optionGroup(p, {title = A.L("setupChronicle"),
            get = function() return A.OnboardingChronicle(D()) end,
            set = function(v) v = v or "off"; if v == "off" and D().liveWeb then return end; A.OnboardingSetChronicle(D(), v); changed() end,
            choices = function()
                local out = {}
                for _, mode in ipairs({"off", "private", "public"}) do out[#out + 1] = {value = mode, name = A.L("setupChron_" .. mode), desc = A.L("setupChronSub_" .. mode)} end
                return out
            end})
        p.note = para(p, "note", "warning")
    end,
    layout = function(p)
        relabel({p.publish}); relabel(p.extras)
        local y = K.layRows({p.publish}, 0)
        y = K.layRows(p.extras, y) + 18
        p.chronicle.Title:SetText(A.L("setupChronicle"))
        y = K.layGroup(p.chronicle, y, true) + 12
        return line(p.note, D().liveWeb and A.L("setupChronLocked") or nil, y)
    end})

page({key = "et-live", after = "et-public", title = "setupLiveTitle", sub = "setupLiveBody",
    build = function(p)
        p.rows = {}
        for _, entry in ipairs({{"party", "liveParty"}, {"guild", "liveGuild"}, {"friends", "liveFriends"}}) do
            local which = entry[1]
            p.rows[#p.rows + 1] = toggle(p, entry[2], nil, function() return D().live[which] == true end, function(on) D().live[which] = on end)
        end
        p.web = toggle(p, "setupLiveWeb", "setupLiveWebSub", function() return D().liveWeb == true end, function(on) D().liveWeb = on end)
        p.needs = para(p, "note", "warning")
    end,
    layout = function(p)
        relabel(p.rows); relabel({p.web})
        local y = K.layRows(p.rows, 0)
        y = K.layRows({p.web}, y) + 10
        return line(p.needs, D().liveWeb and A.L("setupLiveWebNeeds") or nil, y)
    end})

page({key = "et-sharing", after = "et-live", title = "setupShareTitle", sub = "setupShareBody",
    build = function(p)
        p.share = toggle(p, "share", nil, function() return D().ingame == true end, function(on) D().ingame = on end)
        p.group = toggle(p, "group", nil, function() return D().group == true end, function(on) D().group = on end, function() return not D().ingame end, true)
        p.guild = toggle(p, "guild", nil, function() return D().guild == true end, function(on) D().guild = on end, function() return not D().ingame end, true)
        p.social = toggle(p, "socialEnabled", nil, function() return D().social == true end, function(on) D().social = on end)
        p.presence = toggle(p, "peopleCatOnline", "setupPresenceSub", function() return D().presence == true end, function(on) D().presence = on end)
    end,
    layout = function(p)
        local rows = {p.share, p.group, p.guild, p.social, p.presence}
        relabel(rows)
        return K.layRows(rows, 0)
    end})

page({key = "et-map", after = "et-sharing", title = "setupMapTitle",
    sub = function() return A.OpenMapInstalled() and "setupMapBodyOpenMap" or "setupMapBodyNone" end,
    build = function(p)
        p.gather = toggle(p, "setupGather", "setupGatherSub", function() return D().layers.gather == true end, function(on) D().layers.gather = on end)
        p.kinds = {}
        for _, kind in ipairs(KIND_KEYS) do
            p.kinds[#p.kinds + 1] = toggle(p, "setupKind_" .. kind, nil, function() return D().kinds[kind] == true end, function(on) D().kinds[kind] = on end,
                function() return not D().layers.gather end, true)
        end
        p.pins = toggle(p, "mapPins", nil, function() return D().mapPins == true end, function(on) D().mapPins = on end)
        p.where = para(p)
    end,
    layout = function(p)
        relabel({p.gather, p.pins}); relabel(p.kinds)
        local y = K.layRows({p.gather}, 0)
        y = K.layRows(p.kinds, y)
        y = K.layRows({p.pins}, y) + 10
        return line(p.where, A.L("setupWhere"), y)
    end})

page({key = "et-window", after = "et-map", title = "setupWindowTitle", sub = "setupWindowBody",
    build = function(p)
        p.minimap = toggle(p, "minimap", nil, function() return D().minimap == true end, function(on) D().minimap = on end)
        p.size = K.optionGroup(p, {title = A.L("setupSizeTitle"),
            get = function()
                for _, entry in ipairs(SCALES) do if math.abs(entry[2] - (D().scale or 1)) < 0.05 then return entry[1] end end
                return "Normal"
            end,
            set = function(v) for _, entry in ipairs(SCALES) do if entry[1] == (v or "Normal") then D().scale = entry[2] end end; K.refresh() end,
            choices = function()
                local out = {}
                for _, entry in ipairs(SCALES) do out[#out + 1] = {value = entry[1], name = A.L("setupSize_" .. entry[1])} end
                return out
            end})
    end,
    layout = function(p)
        relabel({p.minimap})
        local y = K.layRows({p.minimap}, 0) + 18
        p.size.Title:SetText(A.L("setupSizeTitle"))
        return K.layGroup(p.size, y, true)
    end})

page({key = "et-plates", after = "et-window", title = "setupPlatesTitle", sub = "setupPlatesBody",
    build = function(p)
        p.holder = CreateFrame("Frame", nil, p); p.holder:SetSize(K.CW, 430)
        p.plates = A.BuildFriendlyPlateControls(p.holder, {chooseFirst = true,
            changed = function() local d = D(); d.plates = A.FriendlyPlateChoices(); d.friendlyPlates = A.FriendlyPlatesShown() end})
        p.plates:SetPoint("TOPLEFT", 0, 0); p.plates:SetPoint("BOTTOMRIGHT", 0, 0)
        P.plates = p.plates
    end,
    layout = function(p)
        K.place(p.holder, 0, 0)
        if p.plates.Update then pcall(p.plates.Update) end
        return 430
    end})

page({key = "et-music", after = "et-plates", title = "setupMusicTitle", sub = "setupMusicBody",
    build = function(p)
        local kit = A.UIKit()
        p.enable = toggle(p, "setupMusicOn", "setupMusicOnSub", function() return D().music == true end, function(on) D().music = on end)
        p.source = K.optionGroup(p, {title = A.L("setupMusicSource"),
            get = function() return D().musicSource end,
            set = function(v) D().musicSource = v or "spotify"; K.refresh() end,
            choices = function() return {{value = "spotify", name = A.L("musicSpotify"), desc = A.L("setupMusicSpotify")},
                {value = "youtube", name = A.L("musicYoutube"), desc = A.L("setupMusicYoutube")}} end})
        p.idTitle = para(p, "body", "text")
        p.id = kit.SearchBox(p, 300, function(value) D().spotifyId = value end); p.id:SetSize(300, 28); p.id:SetMaxLetters(40)
        p.dashTitle = para(p, "note", "textDim")
        p.dash = kit.LinkBox(p); p.dash:SetSize(K.CW, 28)
        p.redirectTitle = para(p, "note", "textDim")
        p.redirect = kit.LinkBox(p); p.redirect:SetSize(K.CW, 28)
        p.help = para(p)
    end,
    layout = function(p)
        local d = D()
        relabel({p.enable})
        local y = K.layRows({p.enable}, 0) + 16
        p.source.Title:SetText(A.L("setupMusicSource"))
        y = K.layGroup(p.source, y, d.music == true)
        local spotify = d.music == true and d.musicSource ~= "youtube"
        for _, w in ipairs({p.id, p.dash, p.redirect}) do w:SetShown(spotify) end
        if spotify then
            y = line(p.idTitle, A.L("setupSpotifyIdTitle"), y + 14, 6)
            K.place(p.id, 0, y); y = y + 36
            if (p.id:GetText() or "") == "" and (d.spotifyId or "") ~= "" then p.id:SetText(d.spotifyId) end
            p.id.hint:SetText("0123456789abcdef…")
            y = line(p.dashTitle, A.L("musicDashboard"), y, 4)
            p.dash.SetUrl(A.Music and A.Music.DASHBOARD or ""); K.place(p.dash, 0, y); y = y + 34
            y = line(p.redirectTitle, A.L("musicRedirect"), y, 4)
            p.redirect.SetUrl(A.Music and A.Music.REDIRECT or ""); K.place(p.redirect, 0, y); y = y + 36
        else
            line(p.idTitle, nil, y); line(p.dashTitle, nil, y); line(p.redirectTitle, nil, y)
        end
        return line(p.help, d.music and A.L(spotify and "setupSpotifyHelp" or "setupMusicYoutubeHelp") or nil, y + 8)
    end})

-- the summary: before the guide's finish, after its own pages
page({key = "et-summary", after = "look", title = "setupHostSumTitle", sub = "setupSumBody",
    build = function(p)
        p.lines = {}
        for i = 1, 14 do p.lines[i] = para(p, "note", "textDim") end
        p.note = para(p, "note", "warning")
    end,
    layout = function(p)
        local d = D()
        local y = 0
        local lines = A.OnboardingSummary(d)
        for i, fs in ipairs(p.lines) do y = line(fs, lines[i] and ("•  " .. lines[i]) or nil, y, 4) end
        return line(p.note, d.web and not A.ExportStore() and A.L("setupNoteExport") or ((d.web or d.liveWeb) and A.L("setupAppNote") or nil), y + 8)
    end})

--- The keys of the window's pages for Onboarding.lua's steps.
P.KEYS = {welcome = "welcome", install = "et-install", pair = "et-pair", website = "et-website", public = "et-public", live = "et-live",
    sharing = "et-sharing", map = "et-map", window = "et-window", nameplates = "et-plates", music = "et-music", summary = "et-summary"}
P.pages = pages

--- Hands the pages to the guide's Install window. -> true when it took them (the setup is then that window)
function P.Register()
    if A.setupHosted then return true end
    local UI = guideUI()
    if not UI then return false end
    K = UI.WelcomeKit
    for _, spec in ipairs(pages) do
        if not UI.WelcomeHost(spec) then return false end
    end
    UI.WelcomeOwner = "Evertally"
    UI.WelcomeOnFinish = function() return A.OnboardingFinish() end
    UI.WelcomeOnOpen = function()
        if A.SetupResetDraft then A.SetupResetDraft() end
        if P.plates then P.plates.choosing = true end
    end
    A.setupHosted = UI
    return true
end
P.Register()
