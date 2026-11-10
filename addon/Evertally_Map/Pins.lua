local _, M = ...
-- Pins on the world map and the minimap for the people who share their position with you (party, raid, guild), for meets and
-- pings, and for what navigation points at. Placing is done by HereBeDragons-Pins, the library GatherLite, GatherMate2 and
-- Questie use; this file only decides what to show. It is loaded on demand (Evertally_Map is a load-on-demand add-on), so
-- nothing of this runs unless the player turned "Map and minimap" on in Evertally's settings.
local A = _G.Evertally
local Pins = LibStub("HereBeDragons-Pins-2.0")
local REF = "Evertally"
local MEDIA = "Interface\\AddOns\\Evertally_Map\\Media\\"
local REFRESH = 2
local ICONS = {dot = "dot", flag = "flag", ping = "ping", goal = "flag", next = "arrow"}
local WORLD_FLAG = _G.HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2

local pool, ticker = {}, nil
M.pins = {pool = pool}

local function zoneName(mapId)
    local info = C_Map and A.Call(C_Map.GetMapInfo, mapId)
    return A.Text(A.Field(info, "name"), 80) or ""
end
local function age(at)
    local seconds = math.max(0, A.Now() - (at or 0))
    if seconds < 90 then return A.L("agoNow") end
    return string.format(A.L("agoMinutes"), math.floor(seconds / 60))
end

local function newFrame(spec, size)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(size, size); f:EnableMouse(true)
    f.tex = f:CreateTexture(nil, "OVERLAY"); f.tex:SetAllPoints()
    f:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.spec then return end
        pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.spec.title or "", 1, 1, 1)
            for _, line in ipairs(self.spec.lines or {}) do GameTooltip:AddLine(line, 0.8, 0.8, 0.85) end
            GameTooltip:Show()
        end)
    end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return f
end

local function paint(frame, spec)
    frame.spec = spec
    frame.tex:SetTexture(MEDIA .. (ICONS[spec.icon] or "dot"))
    local c = spec.color or {1, 1, 1}
    frame.tex:SetVertexColor(c[1], c[2], c[3])
end

local function remove(id)
    local entry = pool[id]
    if not entry then return end
    pcall(Pins.RemoveWorldMapIcon, Pins, REF, entry.world)
    pcall(Pins.RemoveMinimapIcon, Pins, REF, entry.mini)
    entry.world:Hide(); entry.mini:Hide()
    pool[id] = nil
end

local function classColor(classId) return classId and A.ClassColor and A.ClassColor(classId) or {0.85, 0.87, 0.92} end
local function inMyGroup(name)
    for _, fn in ipairs({UnitInParty, UnitInRaid}) do
        if type(fn) == "function" then local ok, yes = pcall(fn, name); if ok and yes == true then return true end end
    end
    return false
end

--- Everything that should be on the maps right now: {id = spec}.
local function wanted()
    local out = {}
    for _, peer in ipairs(A.LivePeers()) do
        local distance = M.DistanceTo(peer.map, peer.x, peer.y)
        out["p:" .. peer.name:lower()] = {
            icon = "dot", color = classColor(peer.class), map = peer.map, x = peer.x, y = peer.y, title = peer.name, edge = false,
            -- the game itself already draws the people of your group on the minimap
            skipMini = inMyGroup(peer.name),
            lines = {zoneName(peer.map) .. " · " .. age(peer.at), distance and (string.format("%d yd", math.floor(distance + 0.5))) or nil},
        }
    end
    for _, meet in ipairs(A.social and A.social.meets or {}) do
        if A.Now() <= (meet.at or 0) + (meet.minutes or 0) * 60 + 7200 then
            out["m:" .. tostring(meet.id)] = {icon = "flag", color = {0.9, 0.63, 0.23}, map = meet.mapId, x = meet.x, y = meet.y, title = (meet.label ~= "" and meet.label or A.L("meetDefault")), edge = true,
                lines = {A.Text(meet.sender, 60) or "", zoneName(meet.mapId)}}
        end
    end
    for _, ping in ipairs(A.LivePings()) do
        out["g:" .. tostring(ping.id)] = {icon = "ping", color = {1, 0.82, 0.29}, map = ping.map, x = ping.x, y = ping.y, title = (ping.label ~= "" and ping.label or A.L("pingTitle")), edge = true,
            lines = {(ping.mine and A.L("navYou") or ping.name) .. " · " .. age(ping.at), zoneName(ping.map)}}
    end
    for _, pin in ipairs(M.NavPins()) do
        out["n:" .. pin.id] = {icon = pin.id == "next" and "next" or "goal", color = pin.id == "next" and {0.655, 0.545, 0.98} or {0.37, 0.72, 0.55}, map = pin.map, x = pin.x, y = pin.y, title = pin.title, edge = true,
            lines = {zoneName(pin.map)}}
    end
    return out
end

function M.Refresh()
    local want = wanted()
    for id in pairs(pool) do if not want[id] then remove(id) end end
    for id, spec in pairs(want) do
        local entry = pool[id]
        if not entry then entry = {world = newFrame(spec, 18), mini = newFrame(spec, 14)}; pool[id] = entry end
        paint(entry.world, spec); paint(entry.mini, spec)
        -- re-adding a frame moves it: HereBeDragons keeps one record per frame
        pcall(Pins.AddWorldMapIconMap, Pins, REF, entry.world, spec.map, spec.x, spec.y, WORLD_FLAG)
        if spec.skipMini then pcall(Pins.RemoveMinimapIcon, Pins, REF, entry.mini)
        else pcall(Pins.AddMinimapIconMap, Pins, REF, entry.mini, spec.map, spec.x, spec.y, false, spec.edge) end
    end
end

function M.Disable()
    M.Stop()
    if ticker then ticker:Cancel(); ticker = nil end
    for id in pairs(pool) do remove(id) end
    pcall(Pins.RemoveAllWorldMapIcons, Pins, REF)
    pcall(Pins.RemoveAllMinimapIcons, Pins, REF)
end

function M.Enable()
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(REFRESH, function() local ok = pcall(M.Refresh); if not ok then A.errors.map_refresh = (A.errors.map_refresh or 0) + 1 end end) end
    M.Refresh()
end

M.Enable()
-- last: the main add-on treats "Evertally.map exists" as "loaded completely"
A.map = M
