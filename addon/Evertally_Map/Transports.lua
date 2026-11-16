local _, M = ...
local A = _G.Evertally
-- Boat and zeppelin timetables on the map: a pin at every dock with the time to the next departure ("~2:14"), and in its tooltip where
-- each boat goes, when it leaves and how long it sails. The times come from TransportData.lua (its source and MIT notice are
-- there and in NOTICE.txt, never in the game's UI): one real departure and the length of the loop per route, so the next
-- departure is that departure plus whole loops. Nothing is learned or watched in game; the
-- "~" says it is worked out, and after a server restart the boats may run at other times until the data is rebuilt.
local Pins = LibStub("HereBeDragons-Pins-2.0")
local REF = "EvertallyDocks"
local MEDIA = "Interface\\AddOns\\Evertally_Map\\Media\\"
-- our own badges (tools/build_transport_icons.py): gold rim, blue for boats, orange for zeppelins; colours are in the picture
local ICONS = {ship = MEDIA .. "ship", zeppelin = MEDIA .. "zeppelin"}
local NEAR = 80                                  -- docks closer than this (yards) share one pin
local MAP_KINDS = {[1] = true, [2] = true, [3] = true}   -- world, continent, zone (a dungeon map may answer for the world outside)
local T = {pool = {}, used = 0, key = nil, shownAt = 0}
M.transport = T

local text = {
    en = {dockToggle = "Boat and zeppelin times", dockShip = "Boat", dockZeppelin = "Zeppelin", dockTo = "%s to %s",
        dockLeaves = "leaves in ~%s", dockInPort = "in port, leaves in ~%s", dockArrives = "arrives at %s ~%s after leaving",
        dockSource = "Worked out, not watched: after a server restart the times can be off.",
        dockFaction_Alliance = "Alliance", dockFaction_Horde = "Horde", dockFaction_both = "everyone"},
    cs = {dockToggle = "Časy lodí a zeppelinů", dockShip = "Loď", dockZeppelin = "Zeppelin", dockTo = "%s do %s",
        dockLeaves = "odjíždí za ~%s", dockInPort = "v přístavu, odjíždí za ~%s", dockArrives = "do %s dorazí ~%s po odjezdu",
        dockSource = "Vypočtené, ne sledované: po restartu serveru můžou časy nesedět.",
        dockFaction_Alliance = "Aliance", dockFaction_Horde = "Horda", dockFaction_both = "všichni"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local OTHER = {a = "b", b = "a"}

--- "2:05" for 125 s, "12:00" for 720 s.
function T.Clock(seconds)
    seconds = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

--- The legs of a route that leave from one end: {from, to, trip, wait, first} (first = one real departure). A route with only one trip
--- is a leg of a circuit boat and leaves only from that end.
function T.Legs(route)
    local out, t, seed = {}, route.times or {}, route.seed or {}
    for _, from in ipairs({"a", "b"}) do
        local to = OTHER[from]
        local trip, wait = t[from .. to], t["w" .. from]
        -- no departure seen here: the same boat leaves here a trip and a wait after it left the other end
        local first = seed[from] or (seed[to] and t[to .. from] and wait and seed[to] + t[to .. from] + wait)
        if trip and first and t.loop and t.loop > 0 then out[#out + 1] = {from = from, to = to, trip = trip, wait = wait or 0, first = first} end
    end
    return out
end

--- When the boat of `leg` next leaves: seconds from `now` (server time) and whether it is waiting in port.
function T.Next(leg, loop, now)
    local k = math.ceil((now - leg.first) / loop)
    local at = leg.first + k * loop
    if at < now then at = at + loop end
    local left = at - now
    return left, left <= leg.wait, at
end

local function playerFaction()
    local faction = A.Call(UnitFactionGroup, "player")
    if faction == "Alliance" or faction == "Horde" then return faction end   -- (anything else: every route)
end

--- The docks to show for `faction` ("Alliance", "Horde", nil = all): {instance, x, y, legs = {{route, leg}, ...}}, near docks merged.
function T.Docks(faction)
    local docks = {}
    for _, route in ipairs(M.transportData and M.transportData.routes or {}) do
        if not faction or route.faction == "both" or route.faction == faction then
            for _, leg in ipairs(T.Legs(route)) do
                local at = route[leg.from]
                local dock
                for _, d in ipairs(docks) do
                    if d.instance == at[1] and (d.x - at[2]) ^ 2 + (d.y - at[3]) ^ 2 < NEAR * NEAR then dock = d; break end
                end
                if not dock then dock = {instance = at[1], x = at[2], y = at[3], legs = {}}; docks[#docks + 1] = dock end
                dock.legs[#dock.legs + 1] = {route = route, leg = leg}
            end
        end
    end
    return docks
end

local function serverNow()
    return A.Number(A.Call(GetServerTime)) or A.Now()
end

--- What a dock's pin says: the soonest departure ("~2:14"), whether that boat is in port, and one tooltip block per boat.
function T.Describe(dock, now)
    local soonest, inPort, lines = nil, false, {}
    for _, entry in ipairs(dock.legs) do
        local route, leg = entry.route, entry.leg
        local left, waiting = T.Next(leg, route.times.loop, now)
        if not soonest or left < soonest then soonest, inPort = left, waiting end
        local kind = A.L(route.vehicle == "zeppelin" and "dockZeppelin" or "dockShip")
        local from, to = route.names[leg.from == "a" and 1 or 2], route.names[leg.to == "a" and 1 or 2]
        lines[#lines + 1] = {left = left, title = string.format(A.L("dockTo"), kind, to) .. " (" .. A.L("dockFaction_" .. route.faction) .. ")",
            when = string.format(A.L(waiting and "dockInPort" or "dockLeaves"), T.Clock(left)),
            trip = string.format(A.L("dockArrives"), to, T.Clock(leg.trip)), from = from, waiting = waiting}
    end
    table.sort(lines, function(a, b) return a.left < b.left end)
    return {left = soonest, inPort = inPort, lines = lines, title = lines[1] and lines[1].from or ""}
end

-- ---------------------------------------------------------------- where a dock lies on a map
local mapInfo = {}
local function mapOf(mapId)
    local info = mapInfo[mapId]
    if info then return info end
    info = {}
    local data = C_Map and A.Call(C_Map.GetMapInfo, mapId)
    info.kind = A.Number(A.Field(data, "mapType"))
    if C_Map and type(C_Map.GetWorldPosFromMapPos) == "function" and type(CreateVector2D) == "function" then
        local ok, instance = pcall(C_Map.GetWorldPosFromMapPos, mapId, CreateVector2D(0.5, 0.5))
        if ok then info.instance = A.Number(instance) end
    end
    mapInfo[mapId] = info
    return info
end

--- The place of a dock on map `mapId` (0..1), or nil when it is not on that map.
function T.MapPos(dock, mapId)
    local info = mapOf(mapId)
    if info.kind and not MAP_KINDS[info.kind] then return nil end
    if info.instance and info.instance ~= dock.instance then return nil end
    if not (C_Map and type(C_Map.GetMapPosFromWorldPos) == "function" and type(CreateVector2D) == "function") then return nil end
    local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, dock.instance, CreateVector2D(dock.x, dock.y), mapId)
    if not ok or type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return nil end
    local x, y = pos:GetXY()
    x, y = A.Number(x), A.Number(y)
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

-- ---------------------------------------------------------------- the pins
local function showTooltip(frame)
    if not GameTooltip or not frame.dock then return end
    local info = T.Describe(frame.dock, serverNow())
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(info.title, 1, 1, 1)
    for _, line in ipairs(info.lines) do
        GameTooltip:AddLine(line.title, 1, 0.86, 0.45)
        if line.waiting then GameTooltip:AddLine(line.when, 0.45, 1, 0.5) else GameTooltip:AddLine(line.when, 0.85, 0.87, 0.92) end
        GameTooltip:AddLine(line.trip, 0.7, 0.72, 0.8)
    end
    GameTooltip:AddLine(A.L("dockSource"), 0.55, 0.57, 0.65, true)
    GameTooltip:Show()
end

local function newPin()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(26, 26); f:EnableMouse(true)
    f.tex = f:CreateTexture(nil, "OVERLAY"); f.tex:SetAllPoints()
    f.caption = f:CreateFontString(nil, "OVERLAY")
    f.caption:SetFont(A.FontPath and A.FontPath() or "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    f.caption:SetPoint("LEFT", f, "RIGHT", 4, 0)
    f:SetScript("OnEnter", function(self) self.hover = true; pcall(showTooltip, self) end)
    f:SetScript("OnLeave", function(self) self.hover = false; if GameTooltip then GameTooltip:Hide() end end)
    return f
end

local function clear()
    pcall(Pins.RemoveAllWorldMapIcons, Pins, REF)
    for _, f in ipairs(T.pool) do f:Hide(); f.dock = nil end
    T.used, T.key = 0, nil
end
T.Clear = clear

function T.Enabled()
    local layers = M.Layers and M.Layers()
    return not layers or layers.docks ~= false
end
function T.SetEnabled(on)
    local layers = M.Layers and M.Layers()
    if layers then layers.docks = on == true end
    T.Refresh(true)
end

local function paintCaptions(now)
    for i = 1, T.used do
        local f = T.pool[i]
        local info = T.Describe(f.dock, now)
        local vehicle = f.dock.legs[1].route.vehicle
        f.tex:SetTexture(ICONS[vehicle] or ICONS.ship)
        f.caption:SetText(info.left and ("~" .. T.Clock(info.left)) or "")
        if info.inPort then f.caption:SetTextColor(0.45, 1, 0.5, 1) else f.caption:SetTextColor(1, 0.9, 0.55, 1) end
        if f.hover then pcall(showTooltip, f) end
    end
end

--- Puts the pins on the maps that are shown (again only when those maps change) and moves the countdowns once a second.
function T.Refresh(force)
    if not T.Enabled() then if T.used > 0 or T.key then clear() end return end
    local maps = M.VisibleMaps and M.VisibleMaps() or {}
    if #maps == 0 then if T.used > 0 then clear() end return end
    local faction = playerFaction()
    local key = table.concat(maps, ",") .. ":" .. tostring(faction)
    if force or key ~= T.key then
        clear(); T.key = key
        for _, dock in ipairs(T.Docks(faction)) do
            for _, mapId in ipairs(maps) do
                local x, y = T.MapPos(dock, mapId)
                if x then
                    T.used = T.used + 1
                    local f = T.pool[T.used]
                    if not f then f = newPin(); T.pool[T.used] = f end
                    f.dock, f.map = dock, mapId
                    pcall(Pins.AddWorldMapIconMap, Pins, REF, f, mapId, x, y)
                    break
                end
            end
        end
        T.shownAt = 0
    end
    local clock = A.Number(A.Call(GetTime)) or 0
    if force or clock - T.shownAt >= 1 then T.shownAt = clock; paintCaptions(serverNow()) end
end

--- The switch in OpenMap's menu (English, like every row there).
function T.RegisterWithOpenMap(api)
    if not api or type(api.RegisterMenuToggle) ~= "function" then return false end
    local label = A.locale and A.locale.en and A.locale.en.dockToggle or A.L("dockToggle")
    pcall(api.RegisterMenuToggle, "Evertally", {id = "evertally_docks", label = label, section = "Evertally", tab = "show", icon = ICONS.ship,
        get = function() return T.Enabled() end, set = function(on) T.SetEnabled(on) end})
    return true
end
