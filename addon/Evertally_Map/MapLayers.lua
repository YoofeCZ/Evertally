local _, M = ...
local A = _G.Evertally
-- Evertally on OpenMap's map (OpenMap is a dependency of this add-on): layers of places, drawn by HereBeDragons like the people and
-- meets, but only for the map that is shown now, so a few hundred pins never wait on maps nobody looks at. They are switched in OpenMap's
-- own menu (OpenMapAPI.RegisterMenuToggle, section Evertally) and on the Map tab of the World page. Layers: gathering (herbs, ore,
-- fishing pools, chests, each resource with its own icon) and the places picked in the database or journey tab ("show on the map").
-- The older layers (travel, trainers, vendors, innkeepers, entrances) are drawn only if OpenMap's interface is missing; the small
-- panel of MapPanel.lua then switches them on the game's own map.
local LAYER_KEYS = {"travel", "trainer", "vendor", "inn", "gather", "instances"}
local LAYER_COLOR = {trainer = {0.4, 0.8, 1}, vendor = {1, 0.78, 0.3}, inn = {0.9, 0.55, 0.9}}
local MAX_TRAVEL_PINS, MAX_SERVICE_PINS = 250, 600
-- With OpenMap installed Evertally uses it as the map. OpenMap draws these itself (flight masters and boat routes: Flights and Routes;
-- trainers, vendors and innkeepers: Townsfolk; dungeon entrances: Dungeons), so Evertally leaves them to it and adds what OpenMap has no
-- layer for: gathering places, live players, meets, pings, navigation and the database.
local OPENMAP_OWNS = {travel = true, trainer = true, vendor = true, inn = true, instances = true}
M.layerKeys = LAYER_KEYS
M.extra = {}                       -- places to show whatever the layers say (set by the database and journey tabs)

local text = {
    en = {layerSection = "Evertally", layer_travel = "Flight masters, boats and the like", layer_trainer = "Trainers", layer_vendor = "Vendors", layer_inn = "Innkeepers", layerReading = "Reading NPCs… %d %%"},
    cs = {layerSection = "Evertally", layer_travel = "Létající mistři, lodě a podobně", layer_trainer = "Trenéři", layer_vendor = "Obchodníci", layer_inn = "Hostinští", layerReading = "Čtu NPC… %d %%"},
}
text.en.layer_gather = "Gathering (reference locations)"
text.cs.layer_gather = "Sbírání (referenční místa)"
text.en.layer_instances = "Dungeon and raid entrances"
text.cs.layer_instances = "Vchody do dungeonů a raidů"
text.en.mapMarkedToggle = "Places marked from the database or the journey"; text.cs.mapMarkedToggle = "Místa označená z databáze nebo cesty"
text.en.omGather_herb = "Gathering: herbs"; text.cs.omGather_herb = "Sbírání: bylinky"
text.en.omGather_ore = "Gathering: ore"; text.cs.omGather_ore = "Sbírání: rudy"
text.en.omGather_fishing = "Gathering: fishing pools"; text.cs.omGather_fishing = "Sbírání: rybářská místa"
text.en.omGather_container = "Gathering: chests and containers"; text.cs.omGather_container = "Sbírání: truhly a schránky"
text.en.omResources = "Evertally: choose resources…"; text.cs.omResources = "Evertally: vybrat suroviny…"
text.en.omAllResources = "Gathering: all resources"; text.cs.omAllResources = "Sbírání: všechny suroviny"
text.en.layerReference = "Possible location from reference data; availability is not known."
text.cs.layerReference = "Možné místo z databáze; aktuální dostupnost není známá."
text.en.layerNavigate = "Click to navigate here."
text.cs.layerNavigate = "Kliknutím sem spustíš navigaci."
text.en.gather_herb = "Herbs"; text.cs.gather_herb = "Bylinky"
text.en.gather_ore = "Ore"; text.cs.gather_ore = "Rudy"
text.en.gather_fishing = "Fishing pools"; text.cs.gather_fishing = "Rybaření"
text.en.gather_container = "Chests and containers"; text.cs.gather_container = "Truhly a schránky"
text.en.layerSkill = "Minimum skill: %d"; text.cs.layerSkill = "Minimální dovednost: %d"
text.en.layerPlayers = "%d players"; text.cs.layerPlayers = "%d hráčů"
text.en.layerGatherCount = "Gathering: %d / %d reference points"; text.cs.layerGatherCount = "Sbírání: %d / %d referenčních bodů"
text.en.instance_dungeon = "Dungeon"; text.cs.instance_dungeon = "Dungeon"
text.en.instance_raid = "Raid"; text.cs.instance_raid = "Raid"
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local function settings() return A.db and A.db.settings end

--- The name of a map, "#id" when the game does not tell.
function M.MapName(mapID)
    local info = C_Map and A.Call(C_Map.GetMapInfo, mapID)
    return A.Text(A.Field(info, "name"), 80) or ("#" .. tostring(mapID))
end

--- Which layers are on: {travel = bool, ...}, kept in the saved settings.
function M.Layers()
    local s = settings()
    if not s then return {} end
    if type(s.mapLayers) ~= "table" then s.mapLayers = {gather = true} end   -- gathering places are what the map is first used for
    return s.mapLayers
end

--- OpenMap's public interface when it is installed, else nil.
local function openMap()
    local api = rawget(_G, "OpenMapAPI")
    return type(api) == "table" and type(api.RegisterMenuToggle) == "function" and api or nil
end
function M.OpenMap() return openMap() end
--- True for a layer OpenMap draws itself (so Evertally does not draw it a second time).
function M.OpenMapOwns(key) return OPENMAP_OWNS[key] == true and openMap() ~= nil end

function M.LayerOn(key) return M.Layers()[key] == true and not M.OpenMapOwns(key) end
--- The layers that are on and are Evertally's to draw: {gather = true, ...}.
function M.ActiveLayers()
    local out = {}
    for _, key in ipairs(LAYER_KEYS) do if M.LayerOn(key) then out[key] = true end end
    return out
end
local function anyService() return M.LayerOn("trainer") or M.LayerOn("vendor") or M.LayerOn("inn") end

local function hostMap()
    local frame = rawget(_G, "WorldMapFrame")
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" or frame:IsShown() ~= true or type(frame.GetMapID) ~= "function" then return nil end
    return A.Number(A.Call(frame.GetMapID, frame), 1, 100000)
end

--- The maps whose places are drawn now: the one the game shows and, when OpenMap's stitched world is up, the zones round its view
--- (found by asking OpenMap which zone lies under nine points of the view), so a place in the next zone is not missing.
function M.VisibleMaps()
    local host = hostMap()
    if not host then return {} end
    local out, seen = {host}, {[host] = true}
    local api = openMap()
    if api and type(api.IsStitched) == "function" and type(api.GetView) == "function" and type(api.MapAt) == "function" and A.Call(api.IsStitched) == true then
        local u, v, zoom = A.Call(api.GetView)
        if A.Number(u) and A.Number(v) then
            local half = 0.45 / math.max(A.Number(zoom, 0.05) or 1, 0.05)   -- the view spans about 1 / zoom of the world
            for _, d in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {1, -1}, {-1, 1}, {1, 1}}) do
                local id = A.Number(A.Call(api.MapAt, u + d[1] * half, v + d[2] * half), 1, 100000)
                if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
            end
            local centre = A.Number(A.Call(api.MapAt, u, v), 1, 100000)
            if centre and not seen[centre] then seen[centre] = true; table.insert(out, 2, centre) end
        end
    end
    return out
end

--- The places of the chosen layers that lie on map `mapId`: hubs of the travel data, and the trainers, vendors and innkeepers
--- read from QuestieDB (zone and city maps only: on a continent there would be thousands).
function M.LayerSpecs(mapId, layers)
    local out = {}
    M.gatherDrawn, M.gatherTotal = 0, 0
    local rect = mapId and M.data and M.data.maps and M.data.maps[mapId]
    if not rect or type(layers) ~= "table" then return out end
    if layers.travel and M.data.hubs and rect[2] > rect[1] and rect[4] > rect[3] then
        for id, hub in pairs(M.data.hubs) do
            local name = type(hub[6]) == "string" and hub[6] or nil
            local u, v = hub[4], hub[5]
            if name and type(u) == "number" and type(v) == "number" and #out < MAX_TRAVEL_PINS then
                local fx, fy = (u - rect[1]) / (rect[2] - rect[1]), (v - rect[3]) / (rect[4] - rect[3])
                if fx >= 0 and fx <= 1 and fy >= 0 and fy <= 1 then
                    local flight = tostring(id):find("^taxi") ~= nil
                    out[#out + 1] = {icon = "dot", color = flight and {0.4, 0.85, 1} or {0.45, 0.6, 1}, map = mapId, x = fx, y = fy, title = name, lines = {}}
                end
            end
        end
    end
    local lists = M.Db and M.Db.scan and M.Db.scan.lists
    if lists and (rect[5] == 1 or rect[5] == 2) then
        local services = 0
        for _, key in ipairs({"trainer", "vendor", "inn"}) do
            if layers[key] then
                for _, entry in ipairs(lists[key]) do
                    if entry.map == mapId and services < MAX_SERVICE_PINS then
                        services = services + 1
                        out[#out + 1] = {icon = "dot", color = LAYER_COLOR[key], map = entry.map, x = entry.x, y = entry.y, title = entry.name, lines = {entry.title or A.L("layer_" .. key)}}
                    end
                end
            end
        end
        if M.ServiceSpecs then for _, spec in ipairs(M.ServiceSpecs(mapId, layers)) do out[#out + 1] = spec end end   -- the kinds ticked one by one
    end
    if layers.gather and M.GatherSpecs then
        local specs, total = M.GatherSpecs(mapId)
        M.gatherDrawn, M.gatherTotal = #specs, total
        for _, spec in ipairs(specs) do out[#out + 1] = spec end
    end
    if layers.instances and M.InstanceSpecs then for _, spec in ipairs(M.InstanceSpecs(mapId)) do out[#out + 1] = spec end end
    return out
end

--- The places to draw on map `mapId`: the layers that are on (the picked places are drawn separately, on top).
function M.MapPlaces(mapId) return M.LayerSpecs(mapId, M.ActiveLayers()) end

--- Switches a layer on or off (kept for next time) and redraws.
function M.SetLayer(key, on)
    local valid = false
    for _, entry in ipairs(LAYER_KEYS) do if entry == key then valid = true; break end end
    if not valid then return false end
    local layers = M.Layers()
    if layers[key] == (on == true) then return end
    layers[key] = on == true
    if M.RefreshLayerPins then M.RefreshLayerPins(true) end
    if M.PanelRefresh then M.PanelRefresh() end
    return true
end

--- Reads the NPCs behind the service layers a few milliseconds at a time (only while a service layer is on).
function M.StepServices()
    if not M.Db then return end
    if not (anyService() or (M.ServiceNeeded and M.ServiceNeeded())) then return end
    if M.Db.scan and M.Db.scan.done then
        M.layerProgress = nil
        if M.ServiceScanDone then M.ServiceScanDone() end
        return
    end
    local now = A.Monotonic and A.Monotonic() or 0
    if M.serviceRetryAt and now < M.serviceRetryAt then return end
    local db = M.dbHandle or M.Db.Open()
    if not db then M.serviceRetryAt = now + 30; return end   -- no NPC database (yet): look again in half a minute
    M.dbHandle = db
    local _, progress = M.Db.ScanServices(db, 4, M.ServiceSide and M.ServiceSide() or (A.Call(UnitFactionGroup, "player") == "Horde" and "H" or "A"))
    M.layerProgress = progress < 1 and progress or nil
    if M.Db.scan and M.Db.scan.done and M.ServiceScanDone then M.ServiceScanDone() end
end

--- Shows places picked in the database or journey tab on the world map: opens the map on `mapId` and keeps the places there.
function M.ShowOnWorldMap(spots, mapId, fit)
    M.extra = {}
    for _, spot in ipairs(spots or {}) do
        if spot.map == mapId then
            M.extra[#M.extra + 1] = {icon = "goal", color = {1, 0.84, 0.1}, map = spot.map, x = spot.x, y = spot.y, title = spot.title, pulse = #M.extra < 12,
                lines = {A.Text(M.MapName(spot.map), 80) or ""}}
        end
    end
    if M.RefreshLayerPins then M.RefreshLayerPins(true) end
    if type(OpenWorldMap) == "function" then pcall(OpenWorldMap, mapId)
    elseif WorldMapFrame and type(ShowUIPanel) == "function" then
        pcall(ShowUIPanel, WorldMapFrame)
        if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapId) end
    end
    local api, first = openMap(), M.extra[1]
    if api and first and type(api.WorldFromMap) == "function" and type(api.ShowWorld) == "function" then
        local function glide()
            local u, v, zoom
            if fit then u, v, zoom = fit(api) end   -- (a journey: the view that holds both ends)
            if not (A.Number(u) and A.Number(v)) then u, v = A.Call(api.WorldFromMap, first.map, first.x, first.y); zoom = 6 end
            if A.Number(u) and A.Number(v) then A.Call(api.ShowWorld, u, v, zoom or 6) end
        end
        glide()
        if C_Timer and C_Timer.After then C_Timer.After(0.3, function() pcall(glide) end) end   -- again once the map has opened
    end
    return #M.extra > 0
end
function M.ClearExtra()
    M.extra = {}
    M.route = nil
    if M.RefreshRoute then M.RefreshRoute(true) end
    if M.RefreshLayerPins then M.RefreshLayerPins(true) end
    if M.PanelRefresh then M.PanelRefresh() end
end

--- Rows for OpenMap's menu, a few at a time (a hundred rows at once would stall a frame, and each one redraws the menu).
local function addRows(rows, register)
    local index, PER = 1, 24
    local function step()
        for _ = 1, PER do
            local row = rows[index]
            if not row then return end
            register(row)
            index = index + 1
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.05, step) else step() end
    end
    step()
end

--- The label of a row in OpenMap's menu: English always (OpenMap's menu is, and its font has no č, ř, š, ž, ě or ů).
local function en(key)
    local t = A.locale and A.locale.en
    return t and t[key] or A.L(key)
end

--- Adds Evertally to OpenMap's menu when OpenMap is there: gathering (all of it, by kind and every single resource), the trainers and
--- merchants picked one kind at a time, the places picked on the map and the way into the database and the journey planner. OpenMap's
--- menu knows only switches, so an action is a switch that acts and stays off. Safe to call again.
function M.RegisterWithOpenMap()
    local api = openMap()
    if not api then return false end
    local section = "Evertally"
    local function add(id, label, tab, get, set, icon, sec)
        pcall(api.RegisterMenuToggle, "Evertally", {id = id, label = label, section = sec or section, tab = tab, get = get, set = set, icon = icon})
    end
    for _, key in ipairs(LAYER_KEYS) do
        if not OPENMAP_OWNS[key] then
            add("evertally_" .. key, en("layer_" .. key), "show", function() return M.LayerOn(key) end, function(on) M.SetLayer(key, on) end)
        end
    end
    -- gathering by kind, each with the picture of its kind
    for _, kind in ipairs({"herb", "ore", "fishing", "container"}) do
        add("evertally_gather_" .. kind, en("omGather_" .. kind), "show", function() return M.GatherTypeOn(kind) end, function(on) M.SetGatherType(kind, on) end,
            M.gatherKindIcons and M.gatherKindIcons[kind])
    end
    add("evertally_gather_all", en("omAllResources"), "show", function() local shown, total = M.GatherShownCount(); return total > 0 and shown == total end,
        function(on) M.SetGatherAll(on); if on then M.SetLayer("gather", true) end end)
    add("evertally_resources", en("omResources"), "more", function() return false end, function(on) if on and M.OpenWorldTab then M.OpenWorldTab("gather") end end)
    add("evertally_marked", en("mapMarkedToggle"), "show", function() return #M.extra > 0 or M.route ~= nil end, function(on) if not on then M.ClearExtra() end end)
    add("evertally_search", en("mapSearch"), "more", function() return false end, function(on) if on and M.OpenWorldTab then M.OpenWorldTab("db") end end)
    add("evertally_journey", en("mapJourney"), "more", function() return false end, function(on) if on and M.OpenWorldTab then M.OpenWorldTab("plan") end end)
    if M.transport then M.transport.RegisterWithOpenMap(api) end
    M.openMapRegistered = true
    -- every single resource, under a heading for its kind, with its own icon
    local rows = {}
    local headings = {herb = "Evertally: herbs", ore = "Evertally: ore", fishing = "Evertally: fishing pools", container = "Evertally: chests"}
    for _, kind in ipairs({"herb", "ore", "fishing", "container"}) do
        local nodes = {}
        for _, node in ipairs(M.layerData and M.layerData.nodes or {}) do if node[3] == kind then nodes[#nodes + 1] = node end end
        table.sort(nodes, function(a, b) return a[2] < b[2] end)
        for _, node in ipairs(nodes) do rows[#rows + 1] = {node = node, kind = kind, section = headings[kind]} end
    end
    addRows(rows, function(row)
        local node = row.node
        add("evertally_res_" .. node[1], node[2], "show", function() return M.GatherShown(node[1]) end,
            function(on)
                M.SetGatherShown(node[1], on)
                if on then M.SetLayer("gather", true); if not M.GatherTypeOn(row.kind) then M.SetGatherType(row.kind, true) end end   -- ticking one is asking to see it
            end, M.GatherIcon(node[1], row.kind), row.section)
    end)
    if M.RegisterServiceRows then M.RegisterServiceRows() end
    return true
end

--- The rows for the kinds of trainers and merchants (once they are known: read from QuestieDB, or kept from the last time).
function M.RegisterServiceRows()
    local api = openMap()
    if not api or not M.ServiceMenuRows then return false end
    local rows = M.ServiceMenuRows()
    addRows(rows, function(row)
        local group = row.group
        pcall(api.RegisterMenuToggle, "Evertally", {id = "evertally_svc_" .. group.key, label = string.format("%s (%d)", group.label, group.count), section = row.section, tab = "show",
            icon = M.serviceIcons and M.serviceIcons[group.kind], get = function() return M.ServicePicked(group.key) end, set = function(on) M.SetServicePicked(group.key, on) end})
    end)
    return #rows > 0
end
