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

local function label(parent, size, color)
    return A.UIKit().label(parent,size,color)
end

function M.PanelRefresh()
    if button then button:SetShown(not (M.OpenMap and M.OpenMap())) end   -- OpenMap's menu carries Evertally's switches instead
    if not panel then return end
    local C=A.UIKit().C
    for _, row in ipairs(rows) do
        local on = M.LayerOn(row.key)
        row.box:SetAlpha(on and 1 or 0.35)
        row.text:SetText(A.L("layer_" .. row.key))
        row.text:SetTextColor(unpack(on and C.text or C.mist))
    end
    panel.title:SetText(A.L("mapPanelTitle"))
    panel.search.text:SetText(A.L("mapSearch")); panel.journey.text:SetText(A.L("mapJourney")); panel.clear.text:SetText(A.L("mapClear"))
    panel.clear:SetShown(#M.extra > 0)
    panel.progress:SetText(M.layerProgress and string.format(A.L("layerReading"), math.floor(M.layerProgress * 100)) or
        (M.LayerOn("gather") and string.format(A.L("layerGatherCount"), M.gatherDrawn or 0, M.gatherTotal or 0) or ""))
end

local function actionButton(parent, y, onClick)
    local b = A.UIKit().Button(parent,nil,228,"ghost",onClick)
    b:SetHeight(28);b:SetPoint("TOPLEFT",12,y)
    return b
end

--- Builds the button and the panel once the world map frame exists.
function M.BuildMapPanel()
    if button then return true end
    if M.OpenMap and M.OpenMap() then return true end   -- with OpenMap there is no second button on its map
    local host = rawget(_G, "WorldMapFrame")
    if type(host) ~= "table" or not host.CreateTexture then return false end
    local anchor = type(host.ScrollContainer) == "table" and host.ScrollContainer or host
    local kit=A.UIKit();local C=kit.C
    button = CreateFrame("Button", "EvertallyMapButton", host)
    button:SetSize(92, 24); button:SetPoint("TOPLEFT", anchor, "TOPLEFT", 10, -10)
    button:SetFrameLevel((anchor:GetFrameLevel() or 1) + 12)
    A.NativeButton(button,C,false)
    button.text = label(button,12,C.bright);button.text:SetPoint("CENTER");button.text:SetJustifyH("CENTER")
    button.text:SetText(A.L("mapButton"))

    panel = CreateFrame("Frame", "EvertallyMapPanel", button)
    panel:SetSize(252,196);panel:SetPoint("TOPLEFT",button,"BOTTOMLEFT",0,-6)
    panel:SetFrameLevel((button:GetFrameLevel() or 1) + 2); panel:EnableMouse(true); panel:Hide()
    A.NativePanel(panel,C)
    panel.title=label(panel,14,C.bright);panel.title:SetPoint("TOPLEFT",12,-12)
    local rule=panel:CreateTexture(nil,"BORDER");rule:SetHeight(1);rule:SetPoint("TOPLEFT",12,-36);rule:SetPoint("TOPRIGHT",-12,-36);kit.paint(rule,C.line)
    for i, key in ipairs(M.layerKeys) do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(228,24);row:SetPoint("TOPLEFT",12,-44-(i-1)*28)
        row.key = key
        row.box = row:CreateTexture(nil, "ARTWORK"); row.box:SetSize(14, 14); row.box:SetPoint("LEFT", 0, 0)
        kit.paint(row.box,C.gold)
        row.text=label(row,12,C.text);row.text:SetPoint("LEFT",row.box,"RIGHT",8,0);row.text:SetPoint("RIGHT",0,0)
        row:SetScript("OnClick", function() M.SetLayer(key, not M.LayerOn(key)) end)
        rows[i] = row
    end
    local actions = -46 - #M.layerKeys * 28
    panel.progress=label(panel,11,C.mist);panel.progress:SetPoint("TOPLEFT",12,actions);panel.progress:SetPoint("TOPRIGHT",-12,actions)
    panel.search = actionButton(panel, actions - 20, function() if M.OpenWorldTab then M.OpenWorldTab("db") end end)
    panel.journey = actionButton(panel, actions - 52, function() if M.OpenWorldTab then M.OpenWorldTab("plan") end end)
    panel.clear = actionButton(panel, actions - 84, function() M.ClearExtra() end)
    panel:SetHeight(-actions+124)
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
