local _, A = ...
-- The Evertally menu: the panel the minimap button's left click opens (its right click hides Evertally), and the
-- tracker's EVERTALLY MENU button. Evertally's own panel, not the guide's list menu: a header with the logo, the big
-- EVERTALLY MENU button that opens Evertally's window, then the groups (Guide, Navigation, Game, Settings,
-- Community) as tiles of two, each with the game's icon; a switch shows its state on the tile. The guide's parts
-- (EvertallyGuide: the guide window, the arrow, pause, Lookup, rares, reports) appear only while it is loaded.
local PAD, TILE_W, TILE_H, GAP = 12, 172, 30, 6
local WIDTH = PAD * 2 + TILE_W * 2 + GAP
local LOGO = "Interface\\AddOns\\Evertally\\Media\\Logo"

local text = {
    en = {menuTitle = "Evertally", menuOpen = "EVERTALLY MENU", menuOpenTip = "Evertally's window: your history, the journal, dungeons, settings",
        menuMinimap = "MINIMAP", menuGuide = "GUIDE", menuNav = "NAVIGATION", menuGame = "GAME", menuSetup = "SETTINGS", menuCommunity = "COMMUNITY",
        menuGuideWindow = "Guide window", menuPickGuide = "Choose a guide", menuLookup = "Database", menuQuests = "Quest tracker",
        menuWindowOptions = "Window options", menuParty = "Party", menuPartySync = "Sync the party",
        menuArrow = "Arrow", menuArrowHidden = "Arrow when hidden", menuStopNav = "Clear the target", menuMap = "World map",
        menuDungeons = "Dungeon Journal", menuTalents = "Talents", menuTraining = "What to learn", menuRecipes = "Recipes",
        menuRares = "Rare mobs", menuBags = "Bags", menuPause = "Pause the guide",
        menuSettings = "Settings", menuSetupAgain = "Run the setup", menuHide = "Hide Evertally", menuShow = "Show Evertally",
        menuDiscord = "Discord", menuReport = "Report a problem", menuForum = "Forum", menuRankings = "Leaderboard",
        menuHint = "Left click: this menu  ·  Right click: hide  ·  Drag: move",
        minimapLeft = "Left click: menu", minimapRight = "Right click: hide Evertally", minimapRightShow = "Right click: show Evertally",
        minimapDrag = "Drag: move around the minimap"},
    cs = {menuTitle = "Evertally", menuOpen = "EVERTALLY MENU", menuOpenTip = "Okno Evertally: tvoje historie, deník, dungeony, nastavení",
        menuMinimap = "MINIMAPA", menuGuide = "PRŮVODCE", menuNav = "NAVIGACE", menuGame = "HRA", menuSetup = "NASTAVENÍ", menuCommunity = "KOMUNITA",
        menuGuideWindow = "Okno návodu", menuPickGuide = "Vybrat návod", menuLookup = "Databáze", menuQuests = "Quest tracker",
        menuWindowOptions = "Možnosti okna", menuParty = "Parta", menuPartySync = "Synchronizovat",
        menuArrow = "Šipka", menuArrowHidden = "Šipka i po skrytí", menuStopNav = "Zrušit cíl", menuMap = "Mapa světa",
        menuDungeons = "Dungeon Journal", menuTalents = "Talenty", menuTraining = "Co se naučit", menuRecipes = "Recepty",
        menuRares = "Vzácní mobové", menuBags = "Batoh", menuPause = "Pozastavit návod",
        menuSettings = "Nastavení", menuSetupAgain = "Spustit nastavení", menuHide = "Skrýt Evertally", menuShow = "Ukázat Evertally",
        menuDiscord = "Discord", menuReport = "Nahlásit problém", menuForum = "Fórum", menuRankings = "Žebříček",
        menuHint = "Levé tlačítko: menu  ·  Pravé: skrýt  ·  Tažení: posunout",
        minimapLeft = "Levé tlačítko: menu", minimapRight = "Pravé tlačítko: skrýt Evertally", minimapRightShow = "Pravé tlačítko: ukázat Evertally",
        minimapDrag = "Tažení: posunout po okraji minimapy"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local function guide()
    local g = rawget(_G, "EvertallyGuide")
    return type(g) == "table" and g or nil
end
local function try(f, ...) if type(f) == "function" then local ok, a = pcall(f, ...); if ok then return a end end end
-- A window of the guide: brought back first when Evertally is hidden.
local function fire(msg)
    return function()
        local g = guide()
        if not g then return end
        try(g.SetHidden, false)
        try(g.Fire, msg)
    end
end
local function view(name) return function() if A.ShowView then A.ShowView(name) end end end

--- Whether Evertally is hidden (the guide's hiding: its windows, the arrow unless kept, and Evertally's window).
function A.EvertallyHidden()
    local g = guide()
    return g ~= nil and try(g.Hidden) == true
end
--- The right click: hide everything Evertally shows, or bring it back.
function A.ToggleEvertallyHidden()
    local g = guide()
    local hide = not A.EvertallyHidden()
    if g and g.SetHidden then try(g.SetHidden, hide) end
    if hide then
        if A.guideShell and A.guideShell.Hide then A.guideShell.Hide() elseif A.CloseUI then A.CloseUI() end
        if A.HideEvertallyMenu then A.HideEvertallyMenu() end
    end
    if A.PaintMinimapHidden then A.PaintMinimapHidden() end
    return hide
end

--- The menu's groups: {head, items = {{key, icon, onClick, get (a switch: its state)}}}. Built each time the menu
--- opens, so what the guide offers right now is what shows.
function A.EvertallyMenuGroups()
    local g = guide()
    local Nav = g and g.Nav
    local GF = g and g.UI and g.UI.GuideFrame
    local PP = g and g.UI and g.UI.PartyPanel
    local Party = g and g.Party
    local groups = {}
    local function group(head, items) local list = {}; for _, item in ipairs(items) do if item then list[#list + 1] = item end end; if #list > 0 then groups[#groups + 1] = {head = head, items = list} end end
    -- What the map and the minimap show (2026-11-19, the user: the filter at the top, under the menu's button): the
    -- guide's inns, flight masters and NPC service categories, in the game's own tracking icons. Turning one on turns
    -- its layer and its minimap icons on too.
    local Maps = g and g.Maps
    if Maps and g.Get and g.Set then
        local GL = g.L or {}
        local function setting(path) return try(g.Get, path) == true end
        local function turn(path, extra)
            local on = not setting(path)
            try(g.Set, path, on)
            if on then for _, p in ipairs(extra) do if not setting(p) then try(g.Set, p, true) end end end
        end
        local function icon(kind, fallback) return (Maps.GameIcon and Maps.GameIcon(kind)) or fallback end
        local items = {
            {key = "menuInns", text = GL["Inns"], icon = icon("inn", "Interface\\Icons\\INV_Misc_Rune_01"),
                get = function() return setting("maps.innPins") end, onClick = function() turn("maps.innPins", {"maps.travelMinimap"}) end},
            {key = "menuFlight", text = GL["Flight masters"], icon = icon("flightmaster", "Interface\\Icons\\Ability_Mount_Wyvern_01"),
                get = function() return setting("maps.taxiPins") end, onClick = function() turn("maps.taxiPins", {"maps.travelMinimap"}) end},
        }
        for _, c in ipairs(Maps.ServiceCategories or {}) do
            local path = "maps.serviceFilters." .. c.key
            items[#items + 1] = {key = "menuService_" .. c.key, text = c.label, icon = c.icon,
                get = function() return setting("maps.servicePins") and setting(path) end,
                onClick = function()
                    if not setting("maps.servicePins") then try(g.Set, "maps.servicePins", true); if not setting(path) then try(g.Set, path, true) end
                    else turn(path, {}) end
                    if setting(path) and not setting("maps.serviceMinimap") then try(g.Set, "maps.serviceMinimap", true) end
                end}
        end
        group("menuMinimap", items)
    end
    group("menuGuide", {
        g and {key = "menuGuideWindow", icon = "Interface\\Icons\\INV_Misc_Book_09", get = function() return try(g.GuideShown) == true end,
            onClick = function() try(g.SetHidden, false); try(g.Fire, "TOGGLE_FRAME") end} or false,
        g and {key = "menuPickGuide", icon = "Interface\\Icons\\INV_Misc_Book_11", onClick = fire("SHOW_PICKER")} or false,
        g and {key = "menuLookup", icon = "Interface\\Icons\\INV_Misc_Spyglass_02", onClick = fire("SHOW_LOOKUP")} or false,
        A.ShowQuestTracker and (not A.QuestTracker or not A.QuestTracker.Enabled or A.QuestTracker.Enabled()) and {key = "menuQuests", icon = "Interface\\Icons\\INV_Letter_15", onClick = function() A.ShowQuestTracker() end} or false,
        -- the guide window's own menu (compact, transparent, lock, reset progress, quick settings...), opened under the
        -- window's EVERTALLY MENU button, where its "..." was
        GF and GF.OpenMenu and {key = "menuWindowOptions", icon = "Interface\\Icons\\INV_Misc_Gear_02", onClick = function()
            local anchor = GF.etMenu
            if anchor and anchor.IsVisible and anchor:IsVisible() then try(GF.OpenMenu, anchor) end
        end} or false,
        -- the party (party sync): its panel, and asking the party to move to your step
        PP and PP.Toggle and {key = "menuParty", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", get = function() local f = try(PP.Frame); return f ~= nil and f:IsShown() end,
            onClick = function() try(PP.Toggle) end} or false,
        Party and Party.RequestSync and {key = "menuPartySync", icon = "Interface\\Icons\\Spell_Holy_PrayerOfSpirit", onClick = function() try(Party.RequestSync) end} or false,
    })
    group("menuNav", {
        Nav and Nav.ToggleArrow and {key = "menuArrow", icon = "Interface\\Icons\\Ability_Hunter_Pathfinding", get = function() return try(g.Get, "nav.arrow") and true or false end,
            onClick = function() try(Nav.ToggleArrow) end} or false,
        g and g.HideKeepsArrow and {key = "menuArrowHidden", icon = "Interface\\Icons\\Ability_Hunter_EagleEye", get = function() return try(g.HideKeepsArrow) == true end,
            onClick = function() try(g.SetHideKeepsArrow, not try(g.HideKeepsArrow)) end} or false,
        Nav and Nav.ClearTarget and {key = "menuStopNav", icon = "Interface\\Icons\\Ability_Seal", onClick = function() try(Nav.ClearTarget) end} or false,
        {key = "menuMap", icon = "Interface\\Icons\\INV_Misc_Map_01", onClick = function() if type(ToggleWorldMap) == "function" then pcall(ToggleWorldMap) end end},
    })
    group("menuGame", {
        A.ToggleBagWindow and {key = "menuBags", icon = "Interface\\Icons\\INV_Misc_Bag_08", get = function() return A.BagWindow and A.BagWindow.Shown() end,
            onClick = function() A.ToggleBagWindow() end} or false,
        {key = "menuDungeons", icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", onClick = view("dungeons")},
        {key = "menuTalents", icon = "Interface\\Icons\\Ability_Marksmanship", onClick = view("talents")},
        {key = "menuTraining", icon = "Interface\\Icons\\INV_Scroll_03", onClick = view("training")},
        {key = "menuRecipes", icon = "Interface\\Icons\\Trade_BlackSmithing", onClick = view("recipes")},
        g and {key = "menuRares", icon = "Interface\\Icons\\Ability_Tracking", onClick = fire("SHOW_RARES")} or false,
        g and g.TogglePaused and {key = "menuPause", icon = "Interface\\Icons\\Spell_Nature_TimeStop", get = function() return try(g.Paused) ~= nil end,
            onClick = function() try(g.TogglePaused) end} or false,
    })
    group("menuSetup", {
        {key = "menuSettings", icon = "Interface\\Icons\\INV_Misc_Gear_01", onClick = function() if not (A.ShowGuideSettings and A.ShowGuideSettings()) then view("settings")() end end},
        {key = "menuSetupAgain", icon = "Interface\\Icons\\INV_Misc_Note_01", onClick = function() if A.OpenOnboarding then A.OpenOnboarding() end end},
        g and {key = "menuHide", icon = "Interface\\Icons\\Ability_Stealth", get = function() return A.EvertallyHidden() end,
            onClick = function() A.ToggleEvertallyHidden() end, keep = true} or false,
    })
    group("menuCommunity", {
        g and {key = "menuDiscord", icon = "Interface\\AddOns\\Evertally_Guide\\Media\\UI\\discord", onClick = fire("SHOW_DISCORD")} or false,
        g and {key = "menuReport", icon = "Interface\\Icons\\INV_Misc_Note_02", onClick = fire("SHOW_REPORT")} or false,
        {key = "menuForum", icon = "Interface\\Icons\\INV_Letter_02", onClick = view("community")},
        {key = "menuRankings", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", onClick = view("rankings")},
    })
    return groups
end

-- ---------------------------------------------------------------- the panel
local menu
local function tile(parent, kit)
    local C = kit.C
    local b = CreateFrame("Button", nil, parent); b:SetSize(TILE_W, TILE_H)
    b.bg = kit.fill(b, C.card, 1)
    kit.outline(b, C.line)
    local hover = b:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(b); kit.paint(hover, C.gold, 0.12)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(20, 20); b.icon:SetPoint("LEFT", 6, 0)
    b.text = kit.label(b, 12, C.text); b.text:SetPoint("LEFT", b.icon, "RIGHT", 7, 0); b.text:SetPoint("RIGHT", -18, 0); b.text:SetWordWrap(false)
    -- a switch: a small lamp at the right edge, lit while on
    b.lamp = b:CreateTexture(nil, "OVERLAY"); b.lamp:SetSize(8, 8); b.lamp:SetPoint("RIGHT", -7, 0); A.Theme.Shape(b.lamp, "dot")
    b:SetScript("OnClick", function(self)
        local item = self.item
        if not item then return end
        pcall(item.onClick)
        if item.get or item.keep then A.RefreshEvertallyMenu() else A.HideEvertallyMenu() end
    end)
    return b
end

local function build()
    if menu then return menu end
    local kit = A.UIKit()
    local C = kit.C
    menu = CreateFrame("Frame", "EvertallyMenuPanel", UIParent)
    menu:SetFrameStrata("DIALOG"); menu:SetClampedToScreen(true); menu:SetWidth(WIDTH); menu:EnableMouse(true)
    A.NativeFrame(menu, C)
    menu.header = menu:CreateTexture(nil, "BORDER"); menu.header:SetPoint("TOPLEFT", 1, -1); menu.header:SetPoint("TOPRIGHT", -1, -1); menu.header:SetHeight(46)
    kit.paint(menu.header, C.header or C.well, 1)
    menu.logo = menu:CreateTexture(nil, "ARTWORK"); menu.logo:SetSize(28, 28); menu.logo:SetPoint("TOPLEFT", PAD, -9); menu.logo:SetTexture(LOGO)
    menu.title = kit.label(menu, 18, C.bright); menu.title:SetPoint("LEFT", menu.logo, "RIGHT", 9, 0)
    menu.version = kit.label(menu, 10, C.faint); menu.version:SetPoint("LEFT", menu.title, "RIGHT", 8, -1)
    menu.close = kit.IconButton(menu, "close", 22, function() A.HideEvertallyMenu() end)
    menu.close:SetPoint("TOPRIGHT", -8, -12)
    local function openWindow() A.HideEvertallyMenu(); if A.OpenUI then A.OpenUI() end end
    -- the guide's own primary button where the guide is loaded (the one on the guide window's tools bar: the same look,
    -- its accent), else Evertally's
    local g = guide()
    local GW = g and g.Widgets
    if GW and GW.Button then
        local ok, b = pcall(GW.Button, menu, A.L("menuOpen"), openWindow, {primary = true, height = 34, width = WIDTH - PAD * 2})
        if ok and b then menu.open = b end
    end
    menu.open = menu.open or kit.Button(menu, "menuOpen", WIDTH - PAD * 2, "primary", openWindow)
    menu.open:SetPoint("TOPLEFT", PAD, -56); menu.open:SetHeight(34)
    menu.heads, menu.tiles = {}, {}
    menu.hint = kit.label(menu, 10, C.faint); menu.hint:SetJustifyH("CENTER"); menu.hint:SetWordWrap(true)
    menu.kit = kit
    menu:Hide()
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EvertallyMenuPanel" end
    return menu
end

--- Lays the groups out again (a switch changed, the language, what the guide offers).
function A.RefreshEvertallyMenu()
    if not menu then return end
    local kit, C = menu.kit, menu.kit.C
    menu.title:SetText(A.L("menuTitle")); menu.version:SetText("v" .. tostring(A.version or ""))
    if menu.open.text then menu.open.text:SetText(A.L("menuOpen")) end
    local y, nh, nt = 56 + 34 + 10, 0, 0
    for _, group in ipairs(A.EvertallyMenuGroups()) do
        nh = nh + 1
        local head = menu.heads[nh] or kit.label(menu, 10, C.gold)
        menu.heads[nh] = head
        head:ClearAllPoints(); head:SetPoint("TOPLEFT", PAD, -y); head:SetText(A.L(group.head)); head:Show()
        y = y + 16
        for i, item in ipairs(group.items) do
            nt = nt + 1
            local b = menu.tiles[nt] or tile(menu, kit)
            menu.tiles[nt] = b
            b.item = item
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", PAD + ((i - 1) % 2) * (TILE_W + GAP), -(y + math.floor((i - 1) / 2) * (TILE_H + GAP)))
            local label = item.key
            if item.key == "menuHide" and A.EvertallyHidden() then label = "menuShow" end
            b.text:SetText(item.text or A.L(label))
            b.icon:SetTexture(item.icon)
            if type(item.icon) == "string" and item.icon:find("^Interface\\Icons\\") then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else b.icon:SetTexCoord(0, 1, 0, 1) end
            local on = item.get and item.get() or false
            b.on = item.get and on or nil
            b.lamp:SetShown(item.get ~= nil)
            if item.get then kit.paint(b.lamp, on and C.green or C.off or C.faint, 1) end
            kit.paint(b.bg, on and (C.raised or C.card) or C.card, 1)
            b:Show()
        end
        y = y + math.ceil(#group.items / 2) * (TILE_H + GAP) + 6
    end
    for i = nh + 1, #menu.heads do menu.heads[i]:Hide() end
    for i = nt + 1, #menu.tiles do menu.tiles[i]:Hide(); menu.tiles[i].item = nil end
    menu.hint:ClearAllPoints(); menu.hint:SetPoint("TOPLEFT", PAD, -y); menu.hint:SetPoint("TOPRIGHT", -PAD, -y); menu.hint:SetText(A.L("menuHint"))
    menu:SetHeight(y + 30)
end

--- Opens the menu beside `anchor` (the minimap button, the tracker's button), or closes it when it is open there.
function A.ShowEvertallyMenu(anchor)
    local f = build()
    if f:IsShown() and (anchor == nil or f.owner == anchor) then f:Hide(); return false end
    f.owner = anchor
    A.RefreshEvertallyMenu()
    f:ClearAllPoints()
    if anchor and anchor.GetCenter then
        local x = anchor:GetCenter()
        local right = x and UIParent and UIParent.GetWidth and x > (UIParent:GetWidth() or 0) / 2
        if right then f:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 4, 4) else f:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", -4, 4) end
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    f:Show()
    return true
end
function A.HideEvertallyMenu() if menu then menu:Hide() end end
function A.EvertallyMenuShown() return menu ~= nil and menu:IsShown() end

-- Hidden by other means (the guide's key binding, its own button): the minimap button greys, an open menu says so.
A.On("PLAYER_LOGIN", function()
    local g = guide()
    if g and g.On then
        pcall(g.On, "EVERTALLYGUIDE_HIDDEN", function()
            if A.PaintMinimapHidden then A.PaintMinimapHidden() end
            if A.EvertallyMenuShown() then A.RefreshEvertallyMenu() end
        end)
    end
end)
