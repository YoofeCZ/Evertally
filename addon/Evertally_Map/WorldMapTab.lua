local _, M = ...
local A = _G.Evertally
-- The "Map" tab of the World page: what Evertally adds to the map (OpenMap's, which this module is built on), as switches, and the way into the
-- list of resources. The same switches are in OpenMap's own menu (section Evertally); this is the place that shows all of it in one view.
local text = {
    en = {
        worldTab_map = "Map", mapIntro = "The map is OpenMap's. Switch on what Evertally adds to it. The same switches are in OpenMap's menu (tab On the map, section Evertally).",
        mapIntroNoOpenMap = "Evertally's map layers are built on OpenMap, which is not installed. Install and enable it (free, CurseForge) and reload.",
        mapOpen = "Open the map", mapClear = "Clear marked places", mapResources = "Choose resources…", mapOn = "ON", mapOff = "OFF", mapMarked = "%d marked places (from the database or the journey)",
        mapSub_travel = "Flight masters, boats, zeppelins", mapSub_trainer = "From QuestieDB, your side only", mapSub_vendor = "From QuestieDB, your side only", mapSub_inn = "Where to set your hearthstone",
        mapSub_gather = "Everything below at once", mapSub_instances = "Dungeons and raids with a known entrance",
        mapKindCount = "%d of %d shown",
        mapIntroOpenMap = "OpenMap is your map: Evertally works inside it. Switch on what Evertally adds to it: the places where herbs, ore, fishing pools and chests can be. The same switches are in OpenMap's menu (tab On the map, section Evertally).",
        mapOwned = "OpenMap draws this itself (its menu, tab On the map)",
    },
    cs = {
        worldTab_map = "Mapa", mapIntro = "Mapou je OpenMap. Zapni, co k ní Evertally přidává. Stejné přepínače jsou i v menu OpenMap (karta On the map, sekce Evertally).",
        mapIntroNoOpenMap = "Vrstvy mapy Evertally jsou postavené na OpenMap, která není nainstalovaná. Nainstaluj a zapni ji (zdarma, CurseForge) a načti znovu.",
        mapOpen = "Otevřít mapu", mapClear = "Smazat označená místa", mapResources = "Vybrat suroviny…", mapOn = "ZAP", mapOff = "VYP", mapMarked = "Označených míst: %d (z databáze nebo cesty)",
        mapSub_travel = "Létající mistři, lodě, vzducholodě", mapSub_trainer = "Z QuestieDB, jen tvoje strana", mapSub_vendor = "Z QuestieDB, jen tvoje strana", mapSub_inn = "Kde si nastavit hearthstone",
        mapSub_gather = "Všechno níž najednou", mapSub_instances = "Dungeony a raidy se známým vchodem",
        mapKindCount = "Zobrazeno %d z %d",
        mapIntroOpenMap = "OpenMap je tvoje mapa: Evertally pracuje uvnitř ní. Zapni, co k ní Evertally přidává: místa, kde mohou být bylinky, rudy, rybářská místa a truhly. Stejné přepínače jsou i v menu OpenMap (karta On the map, sekce Evertally).",
        mapOwned = "Tohle kreslí sama OpenMap (její menu, karta On the map)",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local DOT = {travel = {0.3, 0.9, 0.45}, trainer = {0.4, 0.8, 1}, vendor = {1, 0.78, 0.3}, inn = {0.9, 0.55, 0.9}, gather = {0.75, 0.92, 0.3}, instances = {1, 0.45, 0.35},
    herb = {0.3, 0.92, 0.42}, ore = {0.92, 0.65, 0.3}, fishing = {0.25, 0.7, 1}, container = {1, 0.84, 0.22}}
local KINDS = {"herb", "ore", "fishing", "container"}
local ROW_H, GAP = 38, 6

--- The switches this tab shows: the layers that are Evertally's (with OpenMap, only gathering) and gathering by kind.
local function rowSpecs()
    local out = {}
    for _, key in ipairs(M.layerKeys) do
        if not M.OpenMapOwns(key) then out[#out + 1] = {key = key, layer = true} end
    end
    for _, kind in ipairs(KINDS) do out[#out + 1] = {key = kind, kind = kind} end
    return out
end

local function counts(kind)
    local shown, total = 0, 0
    for _, node in ipairs(M.layerData and M.layerData.nodes or {}) do
        if node[3] == kind then total = total + 1; if M.GatherShown(node[1]) then shown = shown + 1 end end
    end
    return shown, total
end

local function build(frame, kit)
    local C = kit.C
    local s = {rows = {}}
    frame.mapTab = s
    s.intro = kit.label(frame, 11, C.mist); s.intro:SetPoint("TOPLEFT", 4, -4); s.intro:SetPoint("TOPRIGHT", -4, -4)
    local specs = rowSpecs()
    -- two columns, three when there are many switches, so everything fits even in the smallest window
    local perRow = #specs > 6 and 3 or 2
    local gridRows = math.ceil(#specs / perRow)
    local weights = {}
    for c = 1, perRow do weights[c] = 1 end
    local grid = {}
    for r = 1, gridRows do
        local cols = kit.Columns(frame, weights, 8)
        local y = -66 - (r - 1) * (ROW_H + GAP)
        cols:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y); cols:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, y); cols:SetHeight(ROW_H)
        grid[r] = cols
    end
    for i, spec in ipairs(specs) do
        local cell = grid[math.ceil(i / perRow)].cells[(i - 1) % perRow + 1]
        local row = CreateFrame("Button", nil, cell)
        row:SetAllPoints(cell)
        row.bg = kit.fill(row, C.card, 1); row.bg:SetAlpha(0.7)
        local hover = row:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(row); kit.paint(hover, {1, 1, 1}, 0.06)
        row.dot = row:CreateTexture(nil, "ARTWORK"); row.dot:SetSize(spec.kind and 22 or 10, spec.kind and 22 or 10); row.dot:SetPoint("LEFT", spec.kind and 8 or 14, 0)
        if spec.kind and M.gatherKindIcons and M.gatherKindIcons[spec.kind] then row.dot:SetTexture(M.gatherKindIcons[spec.kind]); row.dot:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else kit.paint(row.dot, DOT[spec.key] or C.lilac) end
        row.title = kit.label(row, 13, C.text); row.title:SetPoint("TOPLEFT", 40, -6); row.title:SetPoint("TOPRIGHT", -62, -6); row.title:SetWordWrap(false)
        row.sub = kit.label(row, 10, C.mist); row.sub:SetPoint("BOTTOMLEFT", 40, 6); row.sub:SetPoint("BOTTOMRIGHT", -62, 6); row.sub:SetWordWrap(false)
        row.track = row:CreateTexture(nil, "ARTWORK"); row.track:SetSize(34, 18); row.track:SetPoint("RIGHT", -14, 0)
        row.knob = row:CreateTexture(nil, "OVERLAY"); row.knob:SetSize(14, 14); kit.paint(row.knob, C.text)
        row.key, row.spec = spec.key, spec
        row:SetScript("OnClick", function()
            if spec.kind then M.SetGatherType(spec.kind, not M.GatherTypeOn(spec.kind))
            elseif not M.OpenMapOwns(spec.key) then M.SetLayer(spec.key, not M.LayerOn(spec.key)) end
            M.WorldMapTabRefresh(frame)
        end)
        s.rows[i] = row
    end
    local below = -66 - gridRows * (ROW_H + GAP) - 6
    s.open = kit.Button(frame, "mapOpen", 170, "primary", function()
        local id = C_Map and A.Number(A.Call(C_Map.GetBestMapForUnit, "player"), 1, 100000)
        if not (id and A.OpenRecordedMap and A.OpenRecordedMap({mapId = id})) and type(ToggleWorldMap) == "function" then pcall(ToggleWorldMap) end
    end)
    s.open:SetPoint("TOPLEFT", 0, below)
    s.resources = kit.Button(frame, "mapResources", 190, "ghost", function() if M.OpenWorldTab then M.OpenWorldTab("gather") end end)
    s.resources:SetPoint("LEFT", s.open, "RIGHT", 8, 0)
    s.clear = kit.Button(frame, "mapClear", 190, "ghost", function() M.ClearExtra(); M.WorldMapTabRefresh(frame) end)
    s.clear:SetPoint("LEFT", s.resources, "RIGHT", 8, 0)
    s.marked = kit.label(frame, 11, C.mist); s.marked:SetPoint("TOPLEFT", s.open, "BOTTOMLEFT", 2, -10); s.marked:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, below - 40)
end

function M.WorldMapTabRefresh(frame)
    local s = frame.mapTab
    if not s then return end
    local C = frame.kitColors or {}
    s.intro:SetText(A.L(M.OpenMap() and "mapIntroOpenMap" or "mapIntroNoOpenMap"))
    for _, row in ipairs(s.rows) do
        local spec = row.spec
        local on = spec.kind and M.GatherTypeOn(spec.kind) or M.LayerOn(spec.key)
        if spec.kind then
            row.title:SetText(A.L("gather_" .. spec.kind))
            local shown, total = counts(spec.kind)
            row.sub:SetText(string.format(A.L("mapKindCount"), shown, total))
        else
            row.title:SetText(A.L("layer_" .. spec.key)); row.sub:SetText(A.L("mapSub_" .. spec.key))
        end
        local lilac, off = C.lilac or {0.655, 0.545, 0.98}, C.off or {0.26, 0.25, 0.31}
        local c = on and lilac or off
        if row.track.SetColorTexture then row.track:SetColorTexture(c[1], c[2], c[3], 1) end
        row.knob:ClearAllPoints(); row.knob:SetPoint("LEFT", row.track, "LEFT", on and 18 or 2, 0)
        row.bg:SetAlpha(on and 1 or 0.7)
    end
    local marked = #M.extra
    s.clear:SetShown(marked > 0)
    s.marked:SetText(marked > 0 and string.format(A.L("mapMarked"), marked) or "")
end

M.worldTabs.map = {build = function(frame, kit) frame.kitColors = kit.C; build(frame, kit) end, refresh = M.WorldMapTabRefresh}
