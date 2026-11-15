local _, M = ...
local A = _G.Evertally
-- What you can do with the navigation arrow (the frame itself is in Navigator.lua): drag it to move it; a left click opens what it leads to (the
-- quest, NPC, item, resource, place or person behind the goal); a right click opens a small menu: resize, hide, reset, stop. Resizing is done by
-- dragging a corner that appears when you choose it. The position and size are kept in the settings (navPos in UIParent units, navScale).
local GRIP = 42.4   -- how far the corner handle sits from the arrow's centre when the scale is 1
local MIN_SCALE, MAX_SCALE = 0.5, 3

local text = {
    en = {arrowMenuResize = "Change size", arrowMenuHide = "Hide the arrow", arrowMenuReset = "Reset size and position", arrowMenuStop = "Stop navigation",
        arrowMenuSpfOff = "Additional guidance with SPF", arrowMenuSpfOn = "Stop additional SPF guidance", arrowNoSpf = "Shortest Path Forever is not installed.",
        arrowResizeHint = "Drag the corner of the arrow to change its size.", arrowHiddenNote = "The navigation arrow is hidden. /etally arrow shows it again.",
        arrowShown = "The navigation arrow is shown.", arrowHidden = "The navigation arrow is hidden.",
        routeMenuTitle = "Navigation", routeMenuRecalculate = "Recalculate route", routeMenuStart = "Start navigation",
        routeMenuChange = "Change destination or route", routeMenuDetails = "Destination details", routeMenuShowArrow = "Show the arrow"},
    cs = {arrowMenuResize = "Změnit velikost", arrowMenuHide = "Schovat šipku", arrowMenuReset = "Vrátit velikost a polohu", arrowMenuStop = "Zrušit navigaci",
        arrowMenuSpfOff = "Doplňková navigace přes SPF", arrowMenuSpfOn = "Vypnout doplňkovou navigaci SPF", arrowNoSpf = "Shortest Path Forever není nainstalovaný.",
        arrowResizeHint = "Táhni za roh šipky a změníš její velikost.", arrowHiddenNote = "Šipka navigace je schovaná. /etally arrow ji ukáže znovu.",
        arrowShown = "Šipka navigace je vidět.", arrowHidden = "Šipka navigace je schovaná.",
        routeMenuTitle = "Navigace", routeMenuRecalculate = "Přepočítat trasu", routeMenuStart = "Spustit navigaci",
        routeMenuChange = "Změnit cíl nebo trasu", routeMenuDetails = "Podrobnosti cíle", routeMenuShowArrow = "Zobrazit šipku"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local function settings() return A.db and A.db.settings end
local function clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function centerOf(frame)
    if not frame or type(frame.GetCenter) ~= "function" then return nil end
    local ok, x, y = pcall(frame.GetCenter, frame)
    if ok and type(x) == "number" and type(y) == "number" then return x, y end
end
local function uiScale()
    if type(UIParent) == "table" and type(UIParent.GetEffectiveScale) == "function" then
        local ok, scale = pcall(UIParent.GetEffectiveScale, UIParent)
        if ok and type(scale) == "number" and scale > 0 then return scale end
    end
    return 1
end

-- ---------------------------------------------------------------- size and place
function M.ArrowScale()
    local s = settings()
    return A.Number(s and s.navScale, MIN_SCALE, MAX_SCALE) or 1
end

--- Puts the arrow where it was kept, at the size it was kept (the default: under the minimap, size 1).
function M.ArrowApplyLayout(f)
    local s = settings()
    local scale = M.ArrowScale()
    f:SetScale(scale)
    f:ClearAllPoints()
    local saved = s and s.navPos
    if type(saved) == "table" and A.Number(saved[2], -8000, 8000) and A.Number(saved[3], -8000, 8000) then
        f:SetPoint("CENTER", UIParent, "CENTER", saved[2] / scale, saved[3] / scale)
    elseif Minimap then f:SetPoint("TOP", Minimap, "BOTTOM", 0, -26)
    else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
end

--- Keeps where the arrow is now (after it was dragged, or before it is resized) as the offset of its centre from the screen's.
function M.ArrowSavePosition(f)
    local s = settings()
    local x, y = centerOf(f)
    local ux, uy = centerOf(UIParent)
    if not (s and x and ux) then return end
    local scale = f:GetScale() or 1
    s.navPos = {"CENTER", math.floor(x * scale - ux + 0.5), math.floor(y * scale - uy + 0.5)}
    M.ArrowApplyLayout(f)
end

--- Called while the corner is dragged: the size follows how far the cursor is from the centre of the arrow.
function M.ArrowResizeStep(f)
    if type(GetCursorPosition) ~= "function" then return end
    local s = settings()
    local mx, my = GetCursorPosition()
    local cx, cy = centerOf(f)
    if not (s and mx and cx) then return end
    local k, scale = uiScale(), f:GetScale() or 1
    local distance = math.sqrt((mx / k - cx * scale) ^ 2 + (my / k - cy * scale) ^ 2)
    s.navScale = math.floor(clamp(distance / GRIP, MIN_SCALE, MAX_SCALE) * 100 + 0.5) / 100
    M.ArrowApplyLayout(f)
end

function M.ArrowResizeStart()
    local f = M.NavFrame and M.NavFrame()
    if not f then return false end
    local s = settings()
    if s and not s.navPos then M.ArrowSavePosition(f) end   -- (scaling is round the centre: it has to be a place of its own first)
    f.grip:Show()
    A.Print(A.L("arrowResizeHint"))
    return true
end

function M.ArrowReset()
    local s = settings()
    if s then s.navScale, s.navPos = nil, nil end
    local f = M.NavFrame and M.NavFrame()
    if f then M.ArrowApplyLayout(f) end
end

-- ---------------------------------------------------------------- the menu
local ENTRIES = {
    {key = "arrowMenuResize", run = function() M.ArrowResizeStart() end},
    {key = "arrowMenuHide", run = function() M.SetArrowShown(false); A.Print(A.L("arrowHidden") .. " /etally arrow") end},
    {key = "arrowMenuReset", run = function() M.ArrowReset() end},
    {key = "arrowMenuSpf", label = function() return A.L(M.SpfAuto() and "arrowMenuSpfOn" or "arrowMenuSpfOff") end,
        run = function() if M.SpfInstalled() then M.SetSpfAuto(not M.SpfAuto()) else A.Print(A.L("arrowNoSpf")) end end},
    {key = "arrowMenuStop", run = function() M.Stop() end},
}
local menu, catcher

function M.ArrowMenuClose()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
    if M.RouteMenuClose then M.RouteMenuClose() end
end

local function build()
    local kit = A.UIKit()
    local C = kit.C
    -- a transparent sheet behind the menu: a click anywhere else closes it
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("DIALOG"); catcher:SetFrameLevel(1)
    catcher:RegisterForClicks("AnyUp"); catcher:SetScript("OnClick", M.ArrowMenuClose); catcher:Hide()
    menu = CreateFrame("Frame", "EvertallyArrowMenu", UIParent)
    menu:SetFrameStrata("DIALOG"); menu:SetFrameLevel(10); menu:SetSize(190, #ENTRIES * 30 + 14); menu:EnableMouse(true); menu:SetClampedToScreen(true)
    A.NativePanel(menu,C)
    menu.items = {}
    for i, entry in ipairs(ENTRIES) do
        local button = kit.Button(menu, entry.key, 176, "ghost", function() M.ArrowMenuClose(); entry.run() end)
        button:SetPoint("TOPLEFT", 7, -7 - (i - 1) * 30)
        menu.items[i] = button
    end
    menu:Hide()
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EvertallyArrowMenu" end
end

--- Opens the menu at the cursor.
function M.ArrowMenuOpen()
    if M.RouteMenuClose then M.RouteMenuClose() end
    if not menu then build() end
    for i, entry in ipairs(ENTRIES) do menu.items[i].text:SetText(entry.label and entry.label() or A.L(entry.key)) end
    if type(GetCursorPosition) == "function" then
        local x, y = GetCursorPosition()
        local k = uiScale()
        if x and y then menu:ClearAllPoints(); menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / k - 6, y / k + 6) end
    end
    catcher:Show(); menu:Show()
    return true
end

-- A route uses its own menu: clicking a line should offer route actions rather
-- than arrow resizing. Route.lua consumes only a right-click that hits a stroke.
local routeMenu, routeCatcher
local function activeNavigation() return M.nav and M.nav.target ~= nil end
local function routeGoal()
    local target=M.nav and M.nav.target
    if target then return target.label or target.name end
    local steps=M.route and M.route.steps
    local last=steps and steps[#steps]
    return last and last.to
end
local function recalculateOrStart()
    if activeNavigation() then return M.RecalculateRoute and M.RecalculateRoute() end
    local steps=M.route and M.route.steps
    local last=steps and steps[#steps]
    if not (last and M.RoutePlace and A.NavigateToPoint) then return false end
    local map,x,y=M.RoutePlace(last.tu,last.tv)
    if not map then return false end
    local title=last.to or A.L("routeMenuTitle")
    return A.NavigateToPoint(title,map,x,y,{tab="plan",name=title})
end
local ROUTE_ENTRIES={
    {key="arrowMenuStop",run=function() M.Stop() end},
    {key="routeMenuRecalculate",label=function() return A.L(activeNavigation() and "routeMenuRecalculate" or "routeMenuStart") end,
        run=function() if not recalculateOrStart() then A.Print(A.L("navNoRoute")) end end},
    {key="routeMenuChange",run=function() if M.OpenWorldTab then M.OpenWorldTab("plan") end end},
    {key="routeMenuDetails",run=function()
        if activeNavigation() then M.OpenGoalInfo()
        elseif M.OpenWorldTab then M.OpenWorldTab("plan") end
    end},
    {key="arrowMenuHide",label=function() return A.L(M.ArrowShown() and "arrowMenuHide" or "routeMenuShowArrow") end,
        run=function() M.SetArrowShown(not M.ArrowShown()) end},
}

function M.RouteMenuClose()
    if routeMenu then routeMenu:Hide() end
    if routeCatcher then routeCatcher:Hide() end
end

local function buildRouteMenu()
    local kit=A.UIKit()
    routeCatcher=CreateFrame("Button",nil,UIParent)
    routeCatcher:SetAllPoints(UIParent);routeCatcher:SetFrameStrata("DIALOG");routeCatcher:SetFrameLevel(1)
    routeCatcher:RegisterForClicks("AnyUp");routeCatcher:SetScript("OnClick",M.RouteMenuClose);routeCatcher:Hide()
    routeMenu=CreateFrame("Frame","EvertallyRouteMenu",UIParent)
    routeMenu:SetFrameStrata("DIALOG");routeMenu:SetFrameLevel(10);routeMenu:SetSize(250,40+#ROUTE_ENTRIES*30)
    routeMenu:EnableMouse(true);routeMenu:SetClampedToScreen(true)
    A.NativePanel(routeMenu,kit.C)
    routeMenu.title=kit.label(routeMenu,13,kit.C.bright)
    routeMenu.title:SetPoint("TOPLEFT",12,-10);routeMenu.title:SetPoint("TOPRIGHT",-12,-10);routeMenu.title:SetHeight(16);routeMenu.title:SetWordWrap(false)
    routeMenu.items={}
    for i,entry in ipairs(ROUTE_ENTRIES) do
        local button=kit.Button(routeMenu,entry.key,236,"ghost",function() M.RouteMenuClose();entry.run() end)
        button:SetPoint("TOPLEFT",7,-31-(i-1)*30);routeMenu.items[i]=button
    end
    -- Escape calls Hide via UISpecialFrames; the click catcher must close too.
    routeMenu:SetScript("OnHide",function() routeCatcher:Hide() end)
    routeMenu:Hide()
    if type(UISpecialFrames)=="table" then UISpecialFrames[#UISpecialFrames+1]="EvertallyRouteMenu" end
end

function M.ShowRouteMenu()
    if not activeNavigation() and not M.route then return false end
    M.ArrowMenuClose()
    if not routeMenu then buildRouteMenu() end
    routeMenu.title:SetText(routeGoal() or A.L("routeMenuTitle"))
    for i,entry in ipairs(ROUTE_ENTRIES) do routeMenu.items[i].text:SetText(entry.label and entry.label() or A.L(entry.key)) end
    if type(GetCursorPosition)=="function" then
        local x,y=GetCursorPosition();local k=uiScale()
        if x and y then routeMenu:ClearAllPoints();routeMenu:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",x/k-6,y/k+6) end
    end
    routeCatcher:Show();routeMenu:Show()
    return true
end

-- ---------------------------------------------------------------- what the arrow leads to
local function nameOf(src)
    if src.tab == "gather" then
        for _, node in ipairs(M.layerData and M.layerData.nodes or {}) do if node[1] == src.key then return node[2] end end
    elseif src.tab == "services" then
        local kind = tostring(src.key):match("^(%a+):")
        for _, group in ipairs(M.ServiceGroups and M.ServiceGroups(kind or "trainer") or {}) do if group.key == src.key then return group.label, kind end end
    elseif src.tab == "instances" then
        for _, item in ipairs(M.Instances and M.Instances() or {}) do if item.key == src.key then return item.name end end
    end
end

--- Selects the thing the goal belongs to in the tab that lists it.
local function selectInTab(tab, src)
    if src.tab == "db" and tab.db then
        M.OpenDatabaseEntry(src.kind or tab.db.kind, src.id)
    elseif tab.catalog then
        local s = tab.catalog
        local name, kind = nameOf(src)
        if src.tab == "services" and kind and M.SetServiceKind then M.SetServiceKind(kind) end
        if src.tab == "instances" and M.SetInstanceKind then M.SetInstanceKind("all") end
        s.query, s.offset, s.selected = name or "", 0, {key = src.key}
        if s.box then s.box:SetText(s.query) end
        M.WorldCatalogRefresh(tab)
    elseif src.tab == "plan" and tab.plan then
        local s = tab.plan
        s.query, s.offset = src.name or "", 0
        if s.box then s.box:SetText(s.query) end
        s.chosen = (M.Plan.Search(s.query, 1) or {})[1]
        M.WorldPlanRefresh(tab)
        if s.chosen then M.WorldPlanShow(tab) end
    end
end

--- A left click on the arrow: opens what it leads to. A person: the People page; a quest, NPC, item, resource, kind of trainer or merchant,
--- instance or place of the journey planner: its tab in Evertally's window with it selected; anything else: the map tab.
function M.OpenGoalInfo()
    local target = M.nav and M.nav.target
    if not target then return false end
    if target.kind == "player" then
        if A.ShowView then A.ShowView("people") end
        return true
    end
    local src = target.source
    if type(src) == "table" and src.view and A.ShowView then A.ShowView(src.view); return true end
    if type(src) == "table" and src.dungeon and M.OpenDungeonEntry then M.OpenDungeonEntry(src.dungeon); return true end
    if type(src) == "table" and src.tab and M.OpenWorldTab then
        M.OpenWorldTab(src.tab)
        local body = src.tab == "db" and A.databaseBody or A.worldBody
        local tab = body and body.tabFrames and body.tabFrames[src.tab]
        if tab then pcall(selectInTab, tab, src) end
        return true
    end
    if M.OpenWorldTab then M.OpenWorldTab("map") end
    return true
end

-- ---------------------------------------------------------------- shown or hidden
function M.ArrowShown()
    local s = settings()
    return not (s and s.navArrowHidden)
end

--- Shows or hides the arrow (kept in the settings; the navigation goes on either way).
function M.SetArrowShown(on)
    local s = settings()
    if s then s.navArrowHidden = (not on) or nil end
    local f = M.NavFrame and M.NavFrame()
    if f then
        if on and M.nav and M.nav.target then f:Show() else f:Hide() end
        if not on and f.grip then f.grip:Hide(); f.resizing = false end
    end
end
