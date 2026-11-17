local _, A = ...
-- Evertally's window is Evertally Guide's hub (the Evertally_Guide add-ons, from Polestar): Evertally is one section on
-- the hub's rail, its sidebar lists Evertally's pages in the menu's groups (a rule between groups), the night band
-- heads them. Without the guide (not installed, switched off, or its hub API missing) nothing changes: UI.lua's own
-- window opens as before.
--
-- One section, not one per group: the rail shows only what fits its height (W.ShellRail stops at the bottom group),
-- and at the hub's 680 px the guide's six sections plus ours are all it holds.

local PAD = 18
local KEY = "Evertally"
local LOGO = "Interface\\AddOns\\Evertally\\Media\\Logo"
-- The sidebar draws the guide's own line icons (its Media/UI), not the game's coloured ones.
local PAGE_ICON = {
    overview = "house", journal = "icon-note", history = "hourglass", places = "icon-explore", facts = "layers",
    professions = "icon-craft", questguide = "icon-accept", gear = "qol-upgrade", training = "icon-train", database = "search",
    dungeons = "icon-dungeon", recipes = "icon-skill", talents = "star", world = "icon-goto", guides = "guides",
    community = "icon-talk", social = "flag", rankings = "icon-achieve", webfacts = "plug", settings = "gear",
}
-- The Leveling page only led to the guide's windows; in the hub they are its neighbours on the rail.
local SKIP = {leveling = true}

local function guideAPI()
    local g = rawget(_G, "EvertallyGuide")
    local UI = type(g) == "table" and g.UI
    local W = type(g) == "table" and g.Widgets
    if type(UI) ~= "table" or type(UI.RegisterSection) ~= "function" or type(UI.ShowPicker) ~= "function"
        or type(UI.Picker) ~= "table" or type(UI.Picker.ShowSection) ~= "function" or type(W) ~= "table" then return nil end
    return g, UI, W
end

--- Puts Evertally's pages into the guide's hub. -> true when it did (A.guideShell is then the window).
function A.InstallGuideShell()
    if A.guideShell then return true end
    local g, UI, W = guideAPI()
    if not g or not A.UIShell then return false end
    local P, shell = UI.Picker, A.UIShell
    local pages = shell.pages
    local views, groups, known = {}, {}, {}
    for _, group in ipairs(shell.NAV) do
        local list = {}
        for _, view in ipairs(group) do
            if not SKIP[view] then views[#views + 1] = view; list[#list + 1] = view; known[view] = true end
        end
        if #list > 0 then groups[#groups + 1] = list end
    end
    local current, hubWin

    local function viewOf()
        if known[current] then return current end
        local saved = A.db and A.db.settings.lastView
        return known[saved] and saved or views[1]
    end

    local section = {key = KEY, label = "Evertally", icon = LOGO, order = 1}
    section.build = function(parent, win)
        hubWin = win
        local inner = CreateFrame("Frame", nil, parent)
        inner:SetPoint("TOPLEFT", PAD, -PAD); inner:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        for _, view in ipairs(views) do
            local page = CreateFrame("Frame", nil, inner); page:SetAllPoints(inner); page:Hide()
            pages[view] = page
            shell.buildPage(view)
        end
    end
    section.render = function()
        local shown = viewOf()
        for _, view in ipairs(views) do if pages[view] then pages[view]:SetShown(view == shown) end end
        if hubWin and W.ShellTitle then pcall(W.ShellTitle, hubWin, A.L(shown), A.L("sub_" .. shown)) end
        shell.refreshPage(shown)
    end
    -- The groups of Evertally's menu, a rule between them.
    section.nav = function()
        local items = {}
        for i, list in ipairs(groups) do
            if i > 1 then items[#items + 1] = {separator = true} end
            for _, view in ipairs(list) do items[#items + 1] = {key = view, label = A.L(view), icon = PAGE_ICON[view] or "compact"} end
        end
        return items, viewOf()
    end
    section.onNav = function(view)
        if not known[view] then return end
        -- Settings are pages of the guide's settings window (EvertallySettings.lua), QoL beside them.
        if view == "settings" and A.ShowGuideSettings and A.ShowGuideSettings() then return end
        current = view
        if A.db then A.db.settings.lastView = view end
        if P.Render then P.Render() end
    end
    if not UI.RegisterSection(section) then return false end

    local function shown()
        local frame = P.frame
        return frame ~= nil and frame:IsShown() and P.Section and P.Section() == KEY
    end

    A.guideShell = {
        section = section,
        views = views,
        --- Opens the hub on a page (default: the one last shown, else the Overview).
        Open = function(view)
            if view == "settings" and A.ShowGuideSettings and A.ShowGuideSettings() then return end
            if known[view] then current = view; if A.db then A.db.settings.lastView = view end end
            P.ShowSection(KEY)
            UI.ShowPicker()
            if P.Render then P.Render() end
        end,
        Hide = function() if P.frame then P.frame:Hide() end end,
        --- Whether the hub shows Evertally (and, given a view, that page).
        Shown = function(view)
            if not shown() then return false end
            return view == nil or viewOf() == view
        end,
        --- Draws the page shown again (A.RefreshUI): only when it is on the screen.
        Refresh = function()
            if not shown() or not A.db then return end
            local v = viewOf()
            if pages[v] then shell.refreshPage(v) end
        end,
    }
    return true
end

-- Evertally_Guide is an optional dependency, so it is loaded before this file; the login is the fallback.
A.InstallGuideShell()
A.On("PLAYER_LOGIN", function() A.InstallGuideShell() end)
