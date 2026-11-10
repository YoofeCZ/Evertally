local _, M = ...
-- Journey planner: walking, flights, boats, zeppelins, lifts, the Deeprun Tram and portals as one shortest-path search.
-- A line-by-line port of platform/components/evertally/db/travel.ts (planJourney); tests/lua checks that both give the same
-- journeys. The numbers come from Shortest Path Forever (GPL-3.0) through Data.lua. Everything here is plain arithmetic.
local D = M.data
local DETOUR, BOARDING, START_RADIUS = 1.3, 3, 9000
local sqrt = math.sqrt

local function dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by; return sqrt(dx * dx + dy * dy) end

-- Hubs and walk tables are visited in sorted order so equal-cost journeys always come out the same way.
local hubIds, walkKeys = {}, {}
for id in pairs(D.hubs) do hubIds[#hubIds + 1] = id end
table.sort(hubIds)
for pair in pairs(D.walks) do walkKeys[#walkKeys + 1] = pair end
table.sort(walkKeys)

-- ---------------------------------------------------------------- map coordinates <-> yards
--- Azeroth map (u, v) -> continent, x (north) and y (west) in game yards.
function M.ToYards(u, v)
    local c = u < 0.46 and 1 or 0 -- Kalimdor lies in the left of Azeroth's map, the Eastern Kingdoms in the right
    local y = D.yards[c]
    return c, (v - y[3]) / y[4], (u - y[1]) / y[2]
end

local function landmass(c, x, y)
    for i, l in ipairs(D.landmasses) do
        if l[1] == c and x >= l[2] and x <= l[3] and y >= l[4] and y <= l[5] then return i end
    end
    return -1
end
M.Landmass = landmass

--- A position on a game map (uiMapID, 0..1) -> Azeroth map (u, v); nil for maps the data does not carry.
function M.ToUV(mapId, x, y)
    local m = D.maps[mapId]
    if not m or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return m[1] + x * (m[2] - m[1]), m[3] + y * (m[4] - m[3])
end

local locatable = {}
for id, m in pairs(D.maps) do if m[5] == 1 or m[5] == 2 then locatable[#locatable + 1] = id end end
table.sort(locatable)
--- Azeroth map (u, v) -> the smallest zone or city map around it, with the position on that map.
function M.Locate(u, v)
    local best, area
    for _, id in ipairs(locatable) do
        local m = D.maps[id]
        if u >= m[1] and u <= m[2] and v >= m[3] and v <= m[4] then
            local a = (m[2] - m[1]) * (m[4] - m[3])
            if not area or a < area then best, area = id, a end
        end
    end
    if not best then return nil end
    local m = D.maps[best]
    return best, (u - m[1]) / (m[2] - m[1]), (v - m[3]) / (m[4] - m[3])
end

-- ---------------------------------------------------------------- the graph
local graphs = {}
local function hubPoint(id) local h = D.hubs[id]; if h and h[4] and h[5] then return h[4], h[5] end end

local function buildGraph(options)
    local key = options.side .. ":" .. options.speed .. ":" .. (options.otherSide and 1 or 0)
    if graphs[key] then return graphs[key] end
    local graph = {}
    local function add(from, edge) local list = graph[from]; if not list then list = {}; graph[from] = list end; list[#list + 1] = edge end
    local function allowed(side) return side == nil or side == "" or side == options.side or options.otherSide == true end

    -- baked walks between fixed places; "a b" is sorted, {forward, reverse}
    for _, pair in ipairs(walkKeys) do
        local cost = D.walks[pair]
        local a, b = pair:match("^(%S+) (%S+)$")
        if a and D.hubs[a] and D.hubs[b] then
            local au, av = hubPoint(a); local bu, bv = hubPoint(b)
            if cost[1] ~= nil then add(a, {to = b, mode = "walk", yards = cost[1], seconds = cost[1] / options.speed, fu = au, fv = av, tu = bu, tv = bv}) end
            if cost[2] ~= nil then add(b, {to = a, mode = "walk", yards = cost[2], seconds = cost[2] / options.speed, fu = bu, fv = bv, tu = au, tv = av}) end
        end
    end
    -- the Deeprun Tram's stations and passages sit on a map the baked walks do not cover: straight lines on the same map
    local unwalked = {}
    for _, id in ipairs(hubIds) do local c = D.hubs[id][1]; if c ~= 0 and c ~= 1 and c ~= 2991 then unwalked[#unwalked + 1] = id end end
    for _, a in ipairs(unwalked) do for _, b in ipairs(unwalked) do
        local ha, hb = D.hubs[a], D.hubs[b]
        if a ~= b and ha[1] == hb[1] then
            local d = dist(ha[2], ha[3], hb[2], hb[3])
            add(a, {to = b, mode = "walk", yards = d, seconds = d / options.speed, estimated = true})
        end
    end end
    -- flights
    for _, f in ipairs(D.flights) do
        if allowed(D.flightSide[f[1]]) and allowed(D.flightSide[f[2]]) then
            local ida, idb = "taxi" .. f[1], "taxi" .. f[2]
            local au, av = hubPoint(ida); local bu, bv = hubPoint(idb)
            add(ida, {to = idb, mode = "flight", seconds = f[3] + BOARDING, fu = au, fv = av, tu = bu, tv = bv})
        end
    end
    -- portals and passages
    for _, p in ipairs(D.portals) do
        local au, av = hubPoint(p[3]); local bu, bv = hubPoint(p[4])
        add(p[3], {to = p[4], mode = p[2], seconds = p[5], fu = au, fv = av, tu = bu, tv = bv})
    end
    -- boats, zeppelins, lifts and the tram: the expected wait is half a loop, then the ride
    for _, route in ipairs(D.routes) do
        if allowed(route[3]) then
            local period, stops = route[4], route[5]
            local n = #stops
            for i, stop in ipairs(stops) do
                local dock, depart = stop[1], stop[3]
                for offset = 1, n - 1 do
                    local onward, arrive = stops[(i - 1 + offset) % n + 1][1], stops[(i - 1 + offset) % n + 1][2]
                    if onward ~= dock then
                        local ride = ((arrive - depart) % period) / 1000
                        local au, av = hubPoint(dock); local bu, bv = hubPoint(onward)
                        add(dock, {to = onward, mode = route[2], route = route[1], wait = period / 2000, seconds = period / 2000 + ride, fu = au, fv = av, tu = bu, tv = bv})
                    end
                end
            end
        end
    end
    graphs[key] = graph
    return graph
end

-- ---------------------------------------------------------------- the search
--- from, to = {u=, v=, label=}; options = {side="A"|"H", speed=yards per second, otherSide=bool}.
--- Returns {steps={{mode,from,to,seconds,wait,yards,estimated,fu,fv,tu,tv}...}, seconds=} or nil.
function M.PlanJourney(from, to, options)
    local base = buildGraph(options)
    local ac, ax, ay = M.ToYards(from.u, from.v)
    local bc, bx, by = M.ToYards(to.u, to.v)
    local aMass, bMass = landmass(ac, ax, ay), landmass(bc, bx, by)
    local START, GOAL = "@start", "@goal"
    local start, extra = {}, {}

    -- joining a free point to the nearby fixed places (walking, straight-line estimate)
    local function nearby(c, x, y, mass, into)
        for _, id in ipairs(hubIds) do
            local hub = D.hubs[id]
            if hub[1] == c and hub[1] <= 1 and landmass(hub[1], hub[2], hub[3]) == mass then
                local d = dist(x, y, hub[2], hub[3])
                if d <= START_RADIUS then into(id, d * DETOUR) end
            end
        end
    end
    nearby(ac, ax, ay, aMass, function(hub, yards)
        local hu, hv = hubPoint(hub)
        start[#start + 1] = {to = hub, mode = "walk", yards = yards, seconds = yards / options.speed, estimated = true, fu = from.u, fv = from.v, tu = hu or from.u, tv = hv or from.v}
    end)
    if ac == bc and aMass == bMass then
        local d = dist(ax, ay, bx, by) * DETOUR
        start[#start + 1] = {to = GOAL, mode = "walk", yards = d, seconds = d / options.speed, estimated = true, fu = from.u, fv = from.v, tu = to.u, tv = to.v}
    end
    nearby(bc, bx, by, bMass, function(hub, yards)
        local hu, hv = hubPoint(hub)
        local list = extra[hub] or {}
        list[#list + 1] = {to = GOAL, mode = "walk", yards = yards, seconds = yards / options.speed, estimated = true, fu = hu or to.u, fv = hv or to.v, tu = to.u, tv = to.v}
        extra[hub] = list
    end)

    local function edgesOf(id)
        if id == START then return start end
        local out, a, b = {}, base[id] or {}, extra[id] or {}
        for _, e in ipairs(a) do out[#out + 1] = e end
        for _, e in ipairs(b) do out[#out + 1] = e end
        return out
    end

    local best, via, done = {[START] = 0}, {}, {}
    while true do
        local node, cost
        for id, c in pairs(best) do
            if not done[id] and (not cost or c < cost or (c == cost and id < node)) then node, cost = id, c end
        end
        if not node then break end
        done[node] = true
        if node == GOAL then break end
        for _, edge in ipairs(edgesOf(node)) do
            local nextCost = cost + edge.seconds
            if nextCost < (best[edge.to] or math.huge) then best[edge.to] = nextCost; via[edge.to] = {from = node, edge = edge} end
        end
    end
    if not via[GOAL] then return nil end

    -- walk back, name the places and merge neighbouring walks into one step
    local chain, node = {}, GOAL
    while node ~= START do local step = via[node]; table.insert(chain, 1, {from = step.from, edge = step.edge}); node = step.from end
    local function label(id) if id == START then return from.label or "" elseif id == GOAL then return to.label or "" end; local h = D.hubs[id]; return h and h[6] or id end
    local steps = {}
    for _, link in ipairs(chain) do
        local edge, last = link.edge, steps[#steps]
        if edge.mode == "walk" and last and last.mode == "walk" then
            last.to = label(edge.to); last.seconds = last.seconds + edge.seconds; last.yards = (last.yards or 0) + (edge.yards or 0)
            last.estimated = last.estimated or edge.estimated; last.tu, last.tv = edge.tu, edge.tv
        else
            steps[#steps + 1] = {mode = edge.mode, from = label(link.from), to = label(edge.to), seconds = edge.seconds, wait = edge.wait, yards = edge.yards,
                estimated = edge.estimated, fu = edge.fu, fv = edge.fv, tu = edge.tu, tv = edge.tv}
        end
    end
    -- a walk between two places that are the same spot (a portal's exit and the next flight master) costs nothing worth showing
    local meaningful = {}
    for _, step in ipairs(steps) do if not (step.mode == "walk" and step.seconds < 2) then meaningful[#meaningful + 1] = step end end
    return {steps = meaningful, seconds = best[GOAL]}
end
