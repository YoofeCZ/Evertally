local _, M = ...
local A = _G.Evertally
-- The way of a journey drawn on the map as a dotted line: walking, flights, boats and portals one after the other, each kind in its own
-- colour, with a bigger dot where one leg ends and the next begins. It is the plan of the navigator while you navigate, else the one
-- you asked to see in the journey tab (M.route). Dots are HereBeDragons pins like everything else here, so they sit on OpenMap's map in
-- whatever zone they fall.
-- A WALKING leg follows the terrain: the same 16-yard mask and the same cooperative search (Terrain.lua) that make the arrow turn at bends
-- find the way round water and walls, a few hundred nodes a frame, and the line is drawn along it as soon as it is found (until then
-- straight). Flights, boats and portals are straight lines between the places the planner names.
local Pins = LibStub("HereBeDragons-Pins-2.0")
local REF = "EvertallyRoute"
local MEDIA = "Interface\\AddOns\\Evertally_Map\\Media\\"
local WORLD_FLAG = _G.HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2
local MAX_DOTS, MIN_SPACING = 420, 0.004      -- Azeroth's map is 1 wide: a dot at least every 0.4 % of it, never more than 420 in all
local COLORS = {walk = {0.55, 0.92, 0.78}, flight = {0.45, 0.8, 1}, boat = {0.72, 0.65, 1}, zeppelin = {0.95, 0.75, 0.4}, default = {0.95, 0.9, 0.55}}
local CONTINENTS = {kalimdor = 1414, kingdoms = 1415}

M.route = nil          -- the plan the player asked to see (the journey tab); a navigation in progress takes precedence
local pool, shownKey = {}, nil
local legs = {}        -- the walking legs searched: key -> {job, c, uv = [{u, v}] when found, failed}
M.routeReady = 0       -- counts the legs that were found (the line is drawn again when it changes)

--- A point of Azeroth's map (u, v) as a place on a game map: the zone or city round it, else its continent (the sea between).
local function placeOf(u, v)
    if type(u) ~= "number" or type(v) ~= "number" then return nil end
    local map, x, y = M.Locate(u, v)
    if map then return map, x, y end
    local id = u < 0.46 and CONTINENTS.kalimdor or CONTINENTS.kingdoms   -- (the same split the planner uses)
    local m = M.data and M.data.maps and M.data.maps[id]
    if not m or m[2] <= m[1] or m[4] <= m[3] then return nil end
    x, y = (u - m[1]) / (m[2] - m[1]), (v - m[3]) / (m[4] - m[3])
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return id, x, y
end
M.RoutePlace = placeOf

local function colorOf(mode) return COLORS[mode] or COLORS.default end

-- ---------------------------------------------------------------- walking legs along the terrain
local function legKey(step) return string.format("%.3f:%.3f:%.3f:%.3f", step.fu, step.fv, step.tu, step.tv) end

--- The search entry of a walking step (started the first time it is asked for), or nil for any other kind of step.
local function legOf(step)
    if step.mode ~= "walk" or type(step.fu) ~= "number" or type(step.tu) ~= "number" or not M.Terrain then return nil end
    local key = legKey(step)
    local entry = legs[key]
    if entry then return entry end
    local c1, x1, y1 = M.ToYards(step.fu, step.fv)
    local c2, x2, y2 = M.ToYards(step.tu, step.tv)
    if c1 ~= c2 or not M.Terrain.maps[c1] then
        entry = {failed = true}
    else
        entry = {job = M.Terrain.Begin(c1, x1, y1, x2, y2), c = c1}
    end
    legs[key] = entry
    return entry
end

--- The way found for a walking step as a list of {u, v} on Azeroth's map, or nil while it is searched for (or when there is none).
function M.RouteLegPath(step)
    local entry = legOf(step)
    return entry and entry.uv or nil
end

--- Advances the searches a little (called every frame by the driver below; tests call it in a loop).
function M.RouteStep()
    for key, entry in pairs(legs) do
        local job = entry.job
        if job and job.state == "pending" then
            M.Terrain.Step(job)
            if job.state == "ready" and job.result then
                local frame = M.data and M.data.yards and M.data.yards[entry.c]
                if frame then
                    local uv = {}
                    for _, point in ipairs(job.result.points) do uv[#uv + 1] = {frame[1] + point[2] * frame[2], frame[3] + point[1] * frame[4]} end
                    entry.uv = uv
                    M.routeReady = M.routeReady + 1
                else entry.failed = true end
            elseif job.state ~= "pending" then entry.failed = true end
            return true      -- (one search at a time: the frame stays cheap)
        end
    end
    return false
end

local function forgetOtherLegs(plan)
    local keep = {}
    for _, step in ipairs(plan and plan.steps or {}) do
        if step.mode == "walk" and type(step.fu) == "number" and type(step.tu) == "number" then keep[legKey(step)] = true end
    end
    for key, entry in pairs(legs) do
        if not keep[key] then
            if entry.job and entry.job.state == "pending" and M.Terrain then M.Terrain.Cancel(entry.job) end
            legs[key] = nil
        end
    end
end

-- ---------------------------------------------------------------- the dots
local function lengthOf(poly)
    local total = 0
    for i = 2, #poly do total = total + math.sqrt((poly[i][1] - poly[i - 1][1]) ^ 2 + (poly[i][2] - poly[i - 1][2]) ^ 2) end
    return total
end

--- The way of one step as a list of {u, v}: along the terrain for a walk that was found, else a straight line from where it starts to where it ends.
local function polyOf(step)
    return M.RouteLegPath(step) or {{step.fu, step.fv}, {step.tu, step.tv}}
end
M.RoutePoly = polyOf

--- Points along a line (a list of {u, v}) every `spacing`, the first one at its start (its end is the start of the next leg).
local function sample(poly, spacing)
    local points, nextAt, walked = {}, 0, 0
    for i = 2, #poly do
        local ax, ay, bx, by = poly[i - 1][1], poly[i - 1][2], poly[i][1], poly[i][2]
        local piece = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        if piece > 0 then
            while nextAt < walked + piece do
                local t = (nextAt - walked) / piece
                points[#points + 1] = {ax + (bx - ax) * t, ay + (by - ay) * t}
                nextAt = nextAt + spacing
            end
            walked = walked + piece
        end
    end
    if #points == 0 and poly[1] then points[1] = {poly[1][1], poly[1][2]} end
    return points
end

--- The dots of a plan: {map, x, y, color, size}, along each leg and bigger where a leg begins.
function M.RouteDots(plan)
    local out = {}
    if type(plan) ~= "table" or type(plan.steps) ~= "table" then return out end
    local shapes, total = {}, 0
    for _, step in ipairs(plan.steps) do
        if type(step.fu) == "number" and type(step.tu) == "number" then
            local poly = polyOf(step)
            local len = lengthOf(poly)
            shapes[#shapes + 1] = {step = step, poly = poly, len = len}
            total = total + len
        end
    end
    if total <= 0 then return out end
    local spacing = math.max(MIN_SPACING, total / (MAX_DOTS - #shapes))
    for index, shape in ipairs(shapes) do
        local color = colorOf(shape.step.mode)
        for j, point in ipairs(sample(shape.poly, spacing)) do
            local map, x, y = placeOf(point[1], point[2])
            if map then out[#out + 1] = {map = map, x = x, y = y, color = color, size = (j == 1 and index > 1) and 10 or 5} end
        end
    end
    return out
end

local function signature(plan)
    if type(plan) ~= "table" or type(plan.steps) ~= "table" then return "none" end
    local parts = {tostring(M.routeReady)}
    for _, step in ipairs(plan.steps) do
        parts[#parts + 1] = string.format("%s:%.3f:%.3f:%.3f:%.3f", tostring(step.mode), step.fu or 0, step.fv or 0, step.tu or 0, step.tv or 0)
    end
    return table.concat(parts, "|")
end

local function dotFrame(i)
    local f = pool[i]
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(5, 5)
    f.tex = f:CreateTexture(nil, "OVERLAY"); f.tex:SetAllPoints(); f.tex:SetTexture(MEDIA .. "dot")
    pool[i] = f
    return f
end

--- Takes the line off the map.
function M.ClearRouteDots()
    shownKey = nil
    pcall(Pins.RemoveAllWorldMapIcons, Pins, REF)
    for _, f in ipairs(pool) do f:Hide() end
    M.routeDots = 0
end

--- Draws the route that should be on the map now (cheap when nothing changed: it compares a short signature).
function M.RefreshRoute(force)
    local plan = (M.RoutePlan and M.RoutePlan()) or M.route
    if M.SpfDrawsRoute and M.SpfDrawsRoute() then       -- Shortest Path Forever draws its own line for the journey it was handed
        if shownKey ~= "spf" then M.ClearRouteDots(); shownKey = "spf" end
        return
    end
    forgetOtherLegs(plan)
    local key = signature(plan)
    if not force and key == shownKey then return end
    M.ClearRouteDots()
    shownKey = key
    if not plan then return end
    local dots = M.RouteDots(plan)
    for i, dot in ipairs(dots) do
        local f = dotFrame(i)
        f:SetSize(dot.size, dot.size)
        f.tex:SetVertexColor(dot.color[1], dot.color[2], dot.color[3])
        pcall(Pins.AddWorldMapIconMap, Pins, REF, f, dot.map, dot.x, dot.y, WORLD_FLAG)
    end
    M.routeDots = #dots
end

-- the searches go on every frame while there is a walking leg waiting, and the line is redrawn when one is found
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
    if next(legs) == nil then return end
    local before = M.routeReady
    pcall(M.RouteStep)
    if M.routeReady ~= before then pcall(M.RefreshRoute) end
end)

--- Shows a journey on the map: the line, the place it leads to, and the view moved so that both ends are in it.
function M.ShowRoute(plan, places)
    M.route = plan
    local goal = places and places[1]
    local function fit(api)
        local first, last = plan and plan.steps and plan.steps[1], plan and plan.steps and plan.steps[#plan.steps]
        if not (first and first.fu and last and last.tu) then return end
        local function toWorld(u, v)
            local map, x, y = placeOf(u, v)
            if not map then return end
            local a, b = A.Call(api.WorldFromMap, map, x, y)
            if A.Number(a) and A.Number(b) then return a, b end
        end
        local au, av = toWorld(first.fu, first.fv)
        local bu, bv = toWorld(last.tu, last.tv)
        if not au or not bu then return end
        local span = math.max(math.abs(au - bu), math.abs(av - bv), 0.04)
        return (au + bu) / 2, (av + bv) / 2, math.max(1, math.min(6, 0.8 / span))
    end
    local shown = M.ShowOnWorldMap(places or {}, goal and goal.map, fit)
    M.RefreshRoute(true)
    return shown
end

function M.ClearRoute()
    M.route = nil
    M.RefreshRoute(true)
end
