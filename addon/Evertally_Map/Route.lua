local _, M = ...
local A = _G.Evertally
-- The navigator's remaining journey, or the journey preview: solid connected strokes on BOTH maps.
-- Positions use the same HereBeDragons world coordinates as Pins.lua. OpenMap's public API projects
-- them onto its stitched canvas; nothing is written to another addon's settings or waypoint state.
-- Terrain searches retain every bend. A change of continent is a break, never a line across the sea.
local HBD = LibStub("HereBeDragons-2.0", true)
local COLORS = {walk = {0.55, 0.92, 0.78}, flight = {0.45, 0.8, 1}, boat = {0.72, 0.65, 1}, zeppelin = {0.95, 0.75, 0.4}, default = {0.95, 0.9, 0.55}}
local CONTINENTS = {kalimdor = 1414, kingdoms = 1415}

M.route = nil          -- the plan the player asked to see (the journey tab); a navigation in progress takes precedence
local shownKey, segments = nil, {}
local geometryRevision = 0
local edgeCache = setmetatable({}, {__mode = "k"})
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
local function number(v) return A.Number(v) ~= nil end
local function validStep(step)
    return type(step) == "table" and number(step.fu) and number(step.fv) and number(step.tu) and number(step.tv)
end

-- ---------------------------------------------------------------- walking legs along the terrain
local function legKey(step) return string.format("%.3f:%.3f:%.3f:%.3f", step.fu, step.fv, step.tu, step.tv) end

--- The search entry of a walking step (started the first time it is asked for), or nil for any other kind of step.
local function legOf(step)
    if not validStep(step) or step.routePath or step.mode ~= "walk" or not M.Terrain then return nil end
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
        if job and not entry.uv and not entry.failed then
            if job.state == "pending" then M.Terrain.Step(job) end
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
        if validStep(step) and step.mode == "walk" then keep[legKey(step)] = true end
    end
    for key, entry in pairs(legs) do
        if not keep[key] then
            if entry.job and entry.job.state == "pending" and M.Terrain then M.Terrain.Cancel(entry.job) end
            legs[key] = nil
        end
    end
end

--- The way of one step as {u, v}: every terrain bend, otherwise a straight approach.
local function polyOf(step)
    if step.routePath then return step.routePath end
    local path = M.RouteLegPath(step)
    if path then return path end
    if step.mode == "walk" and M.Terrain and M.Terrain.RoadBacked then
        local c = M.ToYards(step.fu, step.fv)
        if M.Terrain.RoadBacked(c) then return {} end
    end
    return {{step.fu, step.fv}, {step.tu, step.tv}}
end
M.RoutePoly = polyOf

local function read(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil end
    return A.Call(object[method], object, ...)
end
local function apiRead(api, method, ...)
    if type(api) ~= "table" or type(api[method]) ~= "function" then return nil end
    return A.Call(api[method], ...)
end

-- HBD world coordinates are (west, north); the planner and C_Map/OpenMap use (north, west).
-- Ask HBD through the same map coordinates as Pins.lua, retaining the native pair for OpenMap.
local function worldPoint(u, v)
    local c, north, west = M.ToYards(u, v)
    if c == nil or not number(north) or not number(west) then return nil end
    local map, x, y = placeOf(u, v)
    if HBD and map then
        local wx, wy, instance = read(HBD, "GetWorldCoordinatesFromZone", x, y, map)
        if number(wx) and number(wy) and number(instance) then return instance, wx, wy, c, north, west end
        return nil
    end
    return c, west, north, c, north, west
end

--- Actual polyline edges, with Azeroth fractions and world yards. No resampling loses a terrain bend.
--- Separate legs and invalid/cross-continent points are never joined.
function M.RouteSegments(plan, reuse)
    local out = {}
    if type(plan) ~= "table" or type(plan.steps) ~= "table" then return out end
    for index, step in ipairs(plan.steps) do
        if validStep(step) then
            local poly = polyOf(step)
            local cacheKey = step.routeGeometry or poly
            local cached = reuse and edgeCache[cacheKey]
            if reuse and not cached then cached = {}; edgeCache[cacheKey] = cached end
            for i = 2, #poly do
                local a, b = poly[i - 1], poly[i]
                if a and b and number(a[1]) and number(a[2]) and number(b[1]) and number(b[2]) then
                    local previous = cached and cached[i]
                    if previous and previous.fu == a[1] and previous.fv == a[2] and previous.tu == b[1] and previous.tv == b[2] then
                        previous.mode, previous.color, previous.leg = step.mode, colorOf(step.mode), index
                        out[#out + 1] = previous
                    else
                        local c1, x1, y1, continent, north1, west1 = worldPoint(a[1], a[2])
                        local c2, x2, y2, other, north2, west2 = worldPoint(b[1], b[2])
                        if c1 ~= nil and c1 == c2 and continent == other and (x1 ~= x2 or y1 ~= y2) then
                            local edge = {fu = a[1], fv = a[2], tu = b[1], tv = b[2],
                                x1 = x1, y1 = y1, x2 = x2, y2 = y2, instance = c1,
                                continent = continent, north1 = north1, west1 = west1, north2 = north2, west2 = west2,
                                mode = step.mode, color = colorOf(step.mode), leg = index}
                            out[#out + 1] = edge
                            if cached then cached[i] = edge end
                        elseif cached then cached[i] = nil end
                    end
                end
            end
        end
    end
    return out
end

local function signature(plan)
    -- Route paths are immutable apart from the navigator's first (player) point.
    -- Inspect a small fixed record per leg, never stringify thousands of bends.
    if type(plan) ~= "table" or type(plan.steps) ~= "table" then return nil end
    local key = {ready = M.routeReady}
    for i, step in ipairs(plan.steps) do
        key[i] = {step.mode, step.fu, step.fv, step.tu, step.tv, step.routePath, step.routePath and #step.routePath, step.routeRevision}
    end
    return key
end
local function sameKey(a, b)
    if not a or not b or a.ready ~= b.ready or #a ~= #b then return false end
    for i = 1, #a do for j = 1, 8 do if a[i][j] ~= b[i][j] then return false end end end
    return true
end
local function sameView(owner, ...)
    local values = {...}
    local old = owner.view
    if old and #old == #values then
        local same = true
        for i = 1, #values do if old[i] ~= values[i] then same = false; break end end
        if same then return true end
    end
    owner.view = values
    return false
end

-- ---------------------------------------------------------------- clipping and painting
-- Clip whole edges, including one whose TWO endpoints are outside the viewport.
local function clipRect(x1, y1, x2, y2, left, top, right, bottom)
    local dx, dy, low, high = x2 - x1, y2 - y1, 0, 1
    local function axis(start, delta, minimum, maximum)
        if delta == 0 then return start >= minimum and start <= maximum end
        local a, b = (minimum - start) / delta, (maximum - start) / delta
        low, high = math.max(low, math.min(a, b)), math.min(high, math.max(a, b))
        return high > low
    end
    if not axis(x1, dx, left, right) or not axis(y1, dy, top, bottom) then return nil end
    return x1 + low * dx, y1 + low * dy, x1 + high * dx, y1 + high * dy
end
M.ClipRouteRect = clipRect

-- The minimap mask is round. Intersect the edge with its inset unit circle.
local function clipCircle(x1, y1, x2, y2, radius)
    local dx, dy = x2 - x1, y2 - y1
    local a = dx * dx + dy * dy
    if a <= 0 then return nil end
    local b, c = 2 * (x1 * dx + y1 * dy), x1 * x1 + y1 * y1 - radius * radius
    local d = b * b - 4 * a * c
    if d <= 0 then return nil end
    local root = math.sqrt(d)
    local low, high = math.max(0, (-b - root) / (2 * a)), math.min(1, (-b + root) / (2 * a))
    if high <= low then return nil end
    return x1 + low * dx, y1 + low * dy, x1 + high * dx, y1 + high * dy
end
M.ClipRouteCircle = clipCircle

local world, mini, loading
local LIMIT, THICKNESS = 4096, 2.5
local function hide(owner)
    if not owner then return end
    if not owner.used and not owner.view then return end
    for i = 1, owner.used do local pair = owner.lines[i]; pair[1]:Hide(); pair[2]:Hide(); pair.visible = false end
    owner.used = 0
    owner.view, owner.geometry = nil, nil
    owner.frame:Hide()
end
local function layer(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent); frame:EnableMouse(false)
    return {frame = frame, parent = parent, lines = {}, used = 0}
end
local function lineRegion(owner, sublevel)
    local f = owner.frame
    if f.CreateLine then
        local region = f:CreateLine(nil, "ARTWORK", nil, sublevel)
        if region then region:SetColorTexture(1, 1, 1, 1); return region, true end
    end
    -- Blizzard DrawLine is also used by Questie's waypoint renderer. It uses a solid texture
    -- strip with proper rotated UVs; rotating an ordinary rectangular texture cannot do this.
    if type(_G.DrawLine) == "function" then
        local region = f:CreateTexture(nil, "ARTWORK", nil, sublevel)
        -- DrawLine rotates texture coordinates beyond 0..1. Transparent border wrapping is
        -- essential: an unbounded color texture would fill the diagonal's entire bounding box.
        region:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
        return region, false
    end
end
local function stroke(owner, x1, y1, x2, y2, color, scale, leg)
    if owner.used >= LIMIT or (x1 == x2 and y1 == y2) then return end
    local i = owner.used + 1
    local pair = owner.lines[i]
    if not pair then
        local under, native = lineRegion(owner, -1)
        local core = lineRegion(owner, 0)
        if not under or not core then return end
        pair = {under, core, native = native}; owner.lines[i] = pair
    end
    owner.used = i
    pair.leg = leg
    if pair.x1 == x1 and pair.y1 == y1 and pair.x2 == x2 and pair.y2 == y2 and pair.color == color and pair.scale == scale
        and pair.visible then return end
    pair.x1, pair.y1, pair.x2, pair.y2, pair.color, pair.scale, pair.visible = x1, y1, x2, y2, color, scale, true
    for n = 1, 2 do
        local region, width = pair[n], (n == 1 and THICKNESS + 2 or THICKNESS) / scale
        if pair.native then
            region:SetThickness(width)
            region:SetStartPoint("TOPLEFT", owner.frame, x1, -y1)
            region:SetEndPoint("TOPLEFT", owner.frame, x2, -y2)
        else
            _G.DrawLine(region, owner.frame, x1, -y1, x2, -y2, width, 1, "TOPLEFT")
        end
        if n == 1 then region:SetVertexColor(0.06, 0.04, 0.02, 0.85)
        else region:SetVertexColor(color[1], color[2], color[3], 1) end
        region:Show()
    end
end
local function begin(owner, level)
    owner.previousUsed, owner.used = owner.used, 0
    if not read(owner.frame, "IsShown") then owner.frame:Show() end
    if number(level) then owner.frame:SetFrameLevel(level) end
end
local function finish(owner)
    for i = owner.used + 1, owner.previousUsed or 0 do
        owner.lines[i][1]:Hide(); owner.lines[i][2]:Hide(); owner.lines[i].visible = false
    end
    owner.geometry = geometryRevision
end
local function scaleOf(frame)
    local scale = read(frame, "GetEffectiveScale")
    return number(scale) and scale > 0 and scale or 1
end

local function drawWorld()
    local map = _G.WorldMapFrame
    if not HBD or not read(map, "IsShown") then hide(world); return 0 end
    local canvas, id = read(map, "GetCanvas"), read(map, "GetMapID")
    local view = map.ScrollContainer or map
    local w, h = read(view, "GetWidth"), read(view, "GetHeight")
    local cw, ch = read(canvas, "GetWidth"), read(canvas, "GetHeight")
    local cl, ct, vl, vt = read(canvas, "GetLeft"), read(canvas, "GetTop"), read(view, "GetLeft"), read(view, "GetTop")
    if not (number(id) and number(w) and number(h) and number(cw) and number(ch)
        and number(cl) and number(ct) and number(vl) and number(vt) and w > 0 and h > 0) then hide(world); return 0 end
    if not world or world.parent ~= view then hide(world); world = layer(view) end
    local scale, cs = scaleOf(view), scaleOf(canvas)
    local api = _G.OpenMapAPI
    local stitched = type(api) == "table" and api.major == 1 and (api.version or 0) >= 2 and apiRead(api, "IsStitched") == true
    local art = stitched and apiRead(api, "ArtTopLevel") or nil
    local viewU, viewV, viewZoom
    if stitched then viewU, viewV, viewZoom = apiRead(api, "GetView") end
    local baseLevel = read(canvas, "GetFrameLevel")
    if sameView(world, id, w, h, cw, ch, cl, ct, vl, vt, scale, cs, stitched, art or 0, baseLevel or 0,
        number(viewU) and viewU or false, number(viewV) and viewV or false, number(viewZoom) and viewZoom or false)
        and world.geometry == geometryRevision then return world.used end
    begin(world, (number(art) and art or (number(baseLevel) and baseLevel or 5)) + 3)
    local function point(segment, last)
        local u, v
        if stitched then
            u, v = apiRead(api, "CanvasFromWorldPos", segment.continent,
                last and segment.north2 or segment.north1, last and segment.west2 or segment.west1)
        else
            u, v = read(HBD, "GetZoneCoordinatesFromWorldInstance",
                last and segment.x2 or segment.x1, last and segment.y2 or segment.y1, segment.instance, id, true)
        end
        if not number(u) or not number(v) then return nil end
        return (cl * cs - vl * scale + u * cw * cs) / scale,
            (vt * scale - ct * cs + v * ch * cs) / scale
    end
    local inset = (THICKNESS + 2) / scale / 2
    for _, segment in ipairs(segments) do
        local x1, y1 = point(segment, false)
        local x2, y2 = point(segment, true)
        if x1 and x2 then
            x1, y1, x2, y2 = clipRect(x1, y1, x2, y2, inset, inset, w - inset, h - inset)
            if x1 then stroke(world, x1, y1, x2, y2, segment.color, scale, segment.leg) end
        end
    end
    finish(world)
    return world.used
end

-- Classic zoom diameters from bundled HBD-Pins, only for clients without GetViewRadius.
local DIAMETERS = {outdoor = {[0] = 466 + 2/3, 400, 333 + 1/3, 266 + 2/6, 200, 133 + 1/3},
    indoor = {[0] = 300, 240, 180, 120, 80, 50}}
local function drawMini()
    local map = _G.Minimap
    if not HBD or not read(map, "IsShown") then hide(mini); return 0 end
    local px, py, instance = read(HBD, "GetPlayerWorldPosition")
    local w, h, zoom = read(map, "GetWidth"), read(map, "GetHeight"), read(map, "GetZoom")
    local radius = apiRead(_G.C_Minimap, "GetViewRadius")
    if not number(radius) and GetCVar and number(zoom) then
        local outdoor = tonumber(A.Call(GetCVar, "minimapZoom")) == zoom
        radius = (DIAMETERS[outdoor and "outdoor" or "indoor"][zoom] or 0) / 2
    end
    local rotate = A.Call(GetCVar, "rotateMinimap") == "1"
    local facing = rotate and A.Call(GetPlayerFacing) or (not rotate and 0 or nil)
    if not (number(px) and number(py) and number(instance) and number(radius) and radius > 0
        and number(w) and number(h) and w > 0 and h > 0 and number(facing)) then hide(mini); return 0 end
    if not mini or mini.parent ~= map then hide(mini); mini = layer(map) end
    local scale = scaleOf(map)
    local baseLevel = read(map, "GetFrameLevel")
    local shape = A.Call(GetMinimapShape)
    if sameView(mini, px, py, instance, w, h, radius, facing, scale, baseLevel or 0, shape or "ROUND")
        and mini.geometry == geometryRevision then return mini.used end
    begin(mini, (number(baseLevel) and baseLevel or 5) + 6)
    local cosine, sine = math.cos(facing), math.sin(facing)
    local square = shape == "SQUARE"
    local inset = 1 - (THICKNESS + 2) / scale / math.min(w, h)
    local function point(x, y)
        local dx, dy = px - x, py - y
        return (dx * cosine - dy * sine) / radius, (dx * sine + dy * cosine) / radius
    end
    for _, segment in ipairs(segments) do
        if segment.instance == instance then
            local x1, y1 = point(segment.x1, segment.y1)
            local x2, y2 = point(segment.x2, segment.y2)
            if square then x1, y1, x2, y2 = clipRect(x1, y1, x2, y2, -inset, -inset, inset, inset)
            else x1, y1, x2, y2 = clipCircle(x1, y1, x2, y2, inset) end
            if x1 then stroke(mini, (x1 + 1) * w / 2, (y1 + 1) * h / 2,
                (x2 + 1) * w / 2, (y2 + 1) * h / 2, segment.color, scale, segment.leg) end
        end
    end
    finish(mini)
    return mini.used
end

--- Remove both painters, retaining their bounded pools. Old callers may still use ClearRouteDots.
function M.ClearRouteLines()
    shownKey, segments = nil, {}
    hide(world); hide(mini)
    M.routeLines, M.routeMiniLines, M.routeDots = 0, 0, 0
end
M.ClearRouteDots = M.ClearRouteLines

--- Hit-test only the actually visible clipped strokes. Coordinates are local
--- viewport pixels from its top-left, not canvas fractions or screen pixels.
function M.RouteHitTest(surface, x, y, tolerance)
    local owner = surface == "world" and world or surface == "minimap" and mini
    if not owner then
        if world and world.parent == surface then owner = world elseif mini and mini.parent == surface then owner = mini end
    end
    if not owner or not read(owner.frame, "IsShown") or not number(x) or not number(y) then return false end
    tolerance = number(tolerance) and math.max(0, tolerance) or 6
    local closest, leg
    for i = 1, owner.used do
        local p = owner.lines[i]
        local dx, dy = p.x2 - p.x1, p.y2 - p.y1
        local length = dx * dx + dy * dy
        local t = length > 0 and math.max(0, math.min(1, ((x - p.x1) * dx + (y - p.y1) * dy) / length)) or 0
        local distance = (x - p.x1 - t * dx)^2 + (y - p.y1 - t * dy)^2
        if not closest or distance < closest then closest, leg = distance, p.leg end
    end
    if closest and closest <= tolerance * tolerance then return true, leg, math.sqrt(closest) end
    return false
end

local clickMap
local function registerRouteClicks()
    local map = _G.WorldMapFrame
    if not map or map == clickMap or type(map.AddCanvasClickHandler) ~= "function" then return end
    local ok = pcall(map.AddCanvasClickHandler, map, function(host, button)
        if button ~= "RightButton" or type(M.ShowRouteMenu) ~= "function" then return false end
        local view = host.ScrollContainer or host
        local x, y = A.Call(GetCursorPosition)
        local left, top, scale = read(view, "GetLeft"), read(view, "GetTop"), scaleOf(view)
        if not (number(x) and number(y) and number(left) and number(top)) then return false end
        if M.RouteHitTest("world", x / scale - left, top - y / scale, 6 / scale) then
            return M.ShowRouteMenu() == true
        end
        return false
    end, 1100) -- Before OpenMap's priority-1000 right-click zoom; misses pass through.
    if ok then clickMap = map end
end

--- Geometry is cached separately from projection: movement/zoom/pan never leaves stale strokes.
function M.RefreshRoute(force)
    registerRouteClicks()
    local plan = (M.RoutePlan and M.RoutePlan()) or M.route
    if not plan and not shownKey and next(legs) == nil then return end
    forgetOtherLegs(plan)
    if loading or not plan then M.ClearRouteLines(); return end
    local key = signature(plan)
    if force then edgeCache = setmetatable({}, {__mode = "k"}) end
    if force or not sameKey(key, shownKey) then
        segments, shownKey = M.RouteSegments(plan, true), key
        geometryRevision = geometryRevision + 1
    end
    M.routeLines, M.routeMiniLines, M.routeDots = drawWorld(), drawMini(), 0
end

-- Searches yield every frame; both surfaces follow player, map zoom and OpenMap pans at 10 Hz.
local driver, elapsed = CreateFrame("Frame"), 0
driver:SetScript("OnUpdate", function(_, dt)
    if next(legs) ~= nil then pcall(M.RouteStep) end
    elapsed = elapsed + (dt or 0)
    if elapsed >= 0.1 then elapsed = 0; M.RefreshRoute() end
end)
driver:RegisterEvent("LOADING_SCREEN_ENABLED")
driver:RegisterEvent("LOADING_SCREEN_DISABLED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function(_, event)
    loading = event == "LOADING_SCREEN_ENABLED"
    if loading then M.ClearRouteLines() else M.RefreshRoute(true) end
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
