local _, M = ...
local A = _G.Evertally
-- A small "Evertally" button on the game's world map and the panel it opens: the layers, the way to the database search, and a
-- button that clears the places picked on the map. It hangs on WorldMapFrame the way other map addons do; if the frame is not
-- there (or an OpenMap-style replacement hides it) nothing breaks, the layers are still in OpenMap's menu.
local button, panel, rows = nil, nil, {}

local text = {
    en = {mapButton = "Evertally", mapPanelTitle = "Evertally on the map", mapSearch = "Search the database…", mapClear = "Clear marked places", mapJourney = "Plan a journey…"},
    cs = {mapButton = "Evertally", mapPanelTitle = "Evertally na mapě", mapSearch = "Hledat v databázi…", mapClear = "Smazat označená místa", mapJourney = "Naplánovat cestu…"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local function label(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(A.FontPath and A.FontPath() or "Fonts\\FRIZQT__.TTF", size, ""); fs:SetTextColor(r, g, b, 1); fs:SetJustifyH("LEFT")
    return fs
end
local function backdrop(frame, r, g, b, a)
    local t = frame:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints()
    if t.SetColorTexture then t:SetColorTexture(r, g, b, a) else t:SetTexture(r, g, b, a) end
    return t
end

function M.PanelRefresh()
    if button then button:SetShown(not (M.OpenMap and M.OpenMap())) end   -- OpenMap's menu carries Evertally's switches instead
    if not panel then return end
    for _, row in ipairs(rows) do
        local on = M.LayerOn(row.key)
        row.box:SetAlpha(on and 1 or 0.35)
        row.text:SetText(A.L("layer_" .. row.key))
        row.text:SetTextColor(on and 1 or 0.7, on and 1 or 0.7, on and 1 or 0.75, 1)
    end
    panel.title:SetText(A.L("mapPanelTitle"))
    panel.search.text:SetText(A.L("mapSearch")); panel.journey.text:SetText(A.L("mapJourney")); panel.clear.text:SetText(A.L("mapClear"))
    panel.clear:SetShown(#M.extra > 0)
    panel.progress:SetText(M.layerProgress and string.format(A.L("layerReading"), math.floor(M.layerProgress * 100)) or
        (M.LayerOn("gather") and string.format(A.L("layerGatherCount"), M.gatherDrawn or 0, M.gatherTotal or 0) or ""))
end

local function actionButton(parent, y, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(204, 26); b:SetPoint("TOPLEFT", 12, y)
    local bg = backdrop(b, 1, 1, 1, 0.08)
    b.text = label(b, 12, 0.95, 0.95, 0.98); b.text:SetPoint("CENTER"); b.text:SetJustifyH("CENTER")
    b:SetScript("OnEnter", function() bg:SetAlpha(0.7) end)
    b:SetScript("OnLeave", function() bg:SetAlpha(1) end)
    b:SetScript("OnClick", onClick)
    return b
end

--- Builds the button and the panel once the world map frame exists.
function M.BuildMapPanel()
    if button then return true end
    if M.OpenMap and M.OpenMap() then return true end   -- with OpenMap there is no second button on its map
    local host = rawget(_G, "WorldMapFrame")
    if type(host) ~= "table" or not host.CreateTexture then return false end
    local anchor = type(host.ScrollContainer) == "table" and host.ScrollContainer or host
    button = CreateFrame("Button", "EvertallyMapButton", host)
    button:SetSize(92, 24); button:SetPoint("TOPLEFT", anchor, "TOPLEFT", 10, -10)
    button:SetFrameLevel((anchor:GetFrameLevel() or 1) + 12)
    backdrop(button, 0.075, 0.067, 0.11, 0.92)
    button.text = label(button, 12, 0.655, 0.545, 0.98); button.text:SetPoint("CENTER"); button.text:SetJustifyH("CENTER")
    button.text:SetText(A.L("mapButton"))

    panel = CreateFrame("Frame", "EvertallyMapPanel", button)
    panel:SetSize(228, 196); panel:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -4)
    panel:SetFrameLevel((button:GetFrameLevel() or 1) + 2); panel:EnableMouse(true); panel:Hide()
    backdrop(panel, 0.075, 0.067, 0.11, 0.96)
    panel.title = label(panel, 13, 0.97, 0.97, 0.97); panel.title:SetPoint("TOPLEFT", 12, -10)
    for i, key in ipairs(M.layerKeys) do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(204, 22); row:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 24)
        row.key = key
        row.box = row:CreateTexture(nil, "ARTWORK"); row.box:SetSize(14, 14); row.box:SetPoint("LEFT", 0, 0)
        if row.box.SetColorTexture then row.box:SetColorTexture(0.655, 0.545, 0.98, 1) else row.box:SetTexture(0.655, 0.545, 0.98, 1) end
        row.text = label(row, 12, 1, 1, 1); row.text:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
        row:SetScript("OnClick", function() M.SetLayer(key, not M.LayerOn(key)) end)
        rows[i] = row
    end
    local actions = -34 - #M.layerKeys * 24
    panel.progress = label(panel, 10, 0.6, 0.6, 0.68); panel.progress:SetPoint("TOPLEFT", 12, actions)
    panel.search = actionButton(panel, actions - 16, function() if M.OpenWorldTab then M.OpenWorldTab("db") end end)
    panel.journey = actionButton(panel, actions - 44, function() if M.OpenWorldTab then M.OpenWorldTab("plan") end end)
    panel.clear = actionButton(panel, actions - 72, function() M.ClearExtra() end)
    panel:SetHeight(-actions + 104)
    button:SetScript("OnClick", function() panel:SetShown(not panel:IsShown()); M.PanelRefresh() end)
    M.PanelRefresh()
    return true
end

--- Opens the Evertally window on one tab of the "World" page (the database or the journey).
function M.OpenWorldTab(tab)
    if tab == "db" then   -- (the database is a page of its own)
        if A.ShowView then A.ShowView("database") end
        local body = A.databaseBody
        if body and M.RefreshDatabase then M.RefreshDatabase(body) end
        return
    end
    if A.ShowView then A.ShowView("world") end
    local body = A.worldBody
    if body then body.mode = tab; if M.RefreshWorld then M.RefreshWorld(body) end end
end
