local _, M = ...
local A = _G.Evertally
-- Compact reference coordinates; no resource availability or player observation is inferred from them.
local MAX_GATHER_PINS = 500
local COLORS = {herb = {0.3, 0.92, 0.42}, ore = {0.92, 0.65, 0.3}, fishing = {0.25, 0.7, 1}, container = {1, 0.84, 0.22}}

function M.GatherFilter()
    local s = A.db and A.db.settings
    if not s then return {} end
    if type(s.gatherTypes) ~= "table" then s.gatherTypes = {} end
    return s.gatherTypes
end
function M.GatherTypeOn(kind) return M.GatherFilter()[kind] ~= false end
function M.SetGatherType(kind, on)
    if not COLORS[kind] then return false end
    M.GatherFilter()[kind] = on == true
    if M.RefreshLayerPins then M.RefreshLayerPins(true) end
    if M.PanelRefresh then M.PanelRefresh() end
    return true
end
function M.SetGatherResource(key)
    local s = A.db and A.db.settings
    if not s then return end
    s.gatherResource = type(key) == "string" and key or nil
    if M.RefreshLayerPins then M.RefreshLayerPins(true) end
end
--- The resources the player does not want on the map: {[key] = true} in the settings (all of them are shown until one is hidden).
function M.GatherHidden()
    local s = A.db and A.db.settings
    if not s then return {} end
    if type(s.gatherOff) ~= "table" then s.gatherOff = {} end
    return s.gatherOff
end
function M.GatherShown(key) return M.GatherHidden()[key] ~= true end
function M.SetGatherShown(key, on)
    if type(key) ~= "string" then return false end
    M.GatherHidden()[key] = (on == false) and true or nil
    if M.RefreshLayerPins then M.RefreshLayerPins(true) end
    if M.PanelRefresh then M.PanelRefresh() end
    return true
end
--- Shows or hides every resource of one kind at once ("herb", "ore", "fishing", "container"), or all of them (kind nil).
function M.SetGatherAll(on, kind)
    local hidden = M.GatherHidden()
    for _, node in ipairs(M.layerData and M.layerData.nodes or {}) do
        if not kind or node[3] == kind then hidden[node[1]] = (on == false) and true or nil end
    end
    if M.RefreshLayerPins then M.RefreshLayerPins(true) end
    if M.PanelRefresh then M.PanelRefresh() end
end
--- Shows or hides a list of resources at once (the window's "show all" / "hide all" for what the search lists).
function M.SetGatherKeys(keys, on)
    local hidden = M.GatherHidden()
    for _, key in ipairs(keys) do hidden[key] = (on == false) and true or nil end
    if M.RefreshLayerPins then M.RefreshLayerPins(true) end
    if M.PanelRefresh then M.PanelRefresh() end
end
--- How many resources are shown, of how many there are.
function M.GatherShownCount()
    local shown, total = 0, 0
    for _, node in ipairs(M.layerData and M.layerData.nodes or {}) do
        total = total + 1
        if M.GatherShown(node[1]) then shown = shown + 1 end
    end
    return shown, total
end
--- The picture of a resource: the game's own item icon (GatherIcons.lua, file IDs), else one for its kind.
function M.GatherIcon(key, kind)
    return (M.gatherIcons and M.gatherIcons[key]) or (M.gatherKindIcons and M.gatherKindIcons[kind])
end

local function matches(node, selected)
    return node and M.GatherTypeOn(node[3]) and M.GatherShown(node[1]) and (not selected or selected == node[1])
end
local function gatherGroups(mapId, resource)
    local data = M.layerData
    local out, count = {}, 0
    if not data then return out, count end
    for _, group in ipairs(data.gather[mapId] or {}) do
        local node = data.nodes[group[1]]
        if matches(node, resource) then out[#out + 1] = {node = node, points = group[2]}; count = count + #group[2] / 2 end
    end
    return out, count
end

function M.GatherSpecs(mapId, resource, limit)
    local selected = resource or (A.db and A.db.settings.gatherResource)
    local groups, count = gatherGroups(mapId, selected)
    local out, position = {}, 0
    local step = math.max(1, math.ceil(count / math.max(1, math.min(MAX_GATHER_PINS, limit or MAX_GATHER_PINS))))
    for _, group in ipairs(groups) do
        local node, points = group.node, group.points
        for i = 1, #points, 2 do
            position = position + 1
            if (position - 1) % step == 0 then
                local lines = {A.L("gather_" .. node[3]), A.L("layerReference"), A.L("layerNavigate")}
                if type(node[4]) == "number" then table.insert(lines, 2, string.format(A.L("layerSkill"), node[4])) end
                out[#out + 1] = {kind = "gather", resource = node[1], icon = "dot", iconFile = M.GatherIcon(node[1], node[3]), color = COLORS[node[3]], map = mapId,
                    x = points[i] / 1000, y = points[i + 1] / 1000, title = node[2], lines = lines, navigate = true}
            end
        end
    end
    return out, count
end

function M.GatherResources(query)
    local out, data = {}, M.layerData
    query = tostring(query or ""):lower()
    if not data then return out end
    for index, node in ipairs(data.nodes) do
        if M.GatherTypeOn(node[3]) and (query == "" or node[2]:lower():find(query, 1, true)) then
            local count = 0
            for _, groups in pairs(data.gather) do for _, group in ipairs(groups) do if group[1] == index then count = count + #group[2] / 2 end end end
            out[#out + 1] = {key = node[1], name = node[2], kind = node[3], skill = node[4], count = count, icon = M.GatherIcon(node[1], node[3]), shown = M.GatherShown(node[1])}
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function M.ResourceSpots(key)
    local out, data = {}, M.layerData
    if not data then return out end
    for mapId, groups in pairs(data.gather) do
        for _, group in ipairs(groups) do
            local node = data.nodes[group[1]]
            if node and node[1] == key then
                for i = 1, #group[2], 2 do out[#out + 1] = {map = mapId, x = group[2][i] / 1000, y = group[2][i + 1] / 1000, title = node[2]} end
            end
        end
    end
    return out
end

function M.Instances(query, kind)
    local out = {}
    query = tostring(query or ""):lower()
    for _, item in ipairs(M.layerData and M.layerData.instances or {}) do
        if (not kind or kind == "all" or item.kind == kind) and (query == "" or item.name:lower():find(query, 1, true)) then out[#out + 1] = item end
    end
    return out
end

function M.InstanceSpecs(mapId)
    local out, rect = {}, M.data and M.data.maps[mapId]
    if not rect then return out end
    local kind = A.db and A.db.settings.instanceKind
    for _, item in ipairs(M.Instances(nil, kind)) do
        if item.map then
            local u, v = M.ToUV(item.map, item.x, item.y)
            local x, y = u and (u - rect[1]) / (rect[2] - rect[1]), v and (v - rect[3]) / (rect[4] - rect[3])
            if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                local lines = {A.L("instance_" .. item.kind), string.format(A.L("layerPlayers"), item.players), A.L("layerNavigate")}
                if item.level then table.insert(lines, 2, tostring(item.level[1]) .. "–" .. tostring(item.level[2])) end
                if item.hint ~= "" then lines[#lines + 1] = item.hint end
                out[#out + 1] = {kind = "instance", key = item.key, icon = "flag", color = item.kind == "raid" and {1, 0.35, 0.25} or {0.65, 0.52, 1},
                    map = mapId, x = x, y = y, title = item.name, lines = lines, navigate = true,
                    targetMap = item.map, targetX = item.x, targetY = item.y}
            end
        end
    end
    return out
end

function M.SetInstanceKind(kind)
    if kind ~= "all" and kind ~= "dungeon" and kind ~= "raid" then return false end
    if A.db then A.db.settings.instanceKind = kind end
    if M.RefreshLayerPins then M.RefreshLayerPins(true) end
    return true
end

function M.NearestLayerSpot(spots)
    local pu, pv = M.PlayerPosition()
    if not pu then return nil end
    local pc, px, py = M.ToYards(pu, pv)
    if not pc then return nil end
    local best, distance
    for _, spot in ipairs(spots or {}) do
        local u, v = M.ToUV(spot.map, spot.x, spot.y)
        if u then
            local c, x, y = M.ToYards(u, v)
            if c == pc then
                local d = (x - px) ^ 2 + (y - py) ^ 2
                if not distance or d < distance then best, distance = spot, d end
            end
        end
    end
    return best
end

--- Where a place on the map comes from, for the arrow's click: the tab and what to select in it.
local function sourceOf(spot)
    if type(spot.source) == "table" then return spot.source end
    if spot.kind == "gather" and spot.resource then return {tab = "gather", key = spot.resource} end
    if spot.kind == "service" and spot.groupKey then return {tab = "services", key = spot.groupKey} end
    if spot.kind == "instance" and spot.key then return {tab = "instances", key = spot.key} end
end
function M.NavigateLayerSpot(spot)
    if type(spot) ~= "table" then return false end
    return M.Navigate({kind = "point", map = spot.targetMap or spot.map, x = spot.targetX or spot.x, y = spot.targetY or spot.y, label = spot.title or spot.name, source = sourceOf(spot)})
end
