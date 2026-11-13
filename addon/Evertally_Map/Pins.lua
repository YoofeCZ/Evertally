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
local ICONS = {dot = "dot", flag = "flag", ping = "ping", goal = "goal", next = "arrow"}
-- the place navigation points at is bigger than the rest, pulses and carries its name on the world map (it used to be an
-- 18 px flag that nobody noticed)
local SIZES = {goal = {world = 30, mini = 26}, next = {world = 22, mini = 18}}
local WORLD_FLAG = _G.HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2

local pool, ticker = {}, nil
local REF_LAYERS = "EvertallyLayers"
local layerPool, extraPool, layerKey, layerTicker = {}, {}, nil, nil
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

local function newFrame(spec, size, world, plain)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(size, size); f:EnableMouse(true)
    -- a coloured ring behind a picture (the gathering resources show their own icon, the ring says herb, ore, fishing or chest)
    f.ring = f:CreateTexture(nil, "ARTWORK"); f.ring:SetPoint("TOPLEFT", -1.5, 1.5); f.ring:SetPoint("BOTTOMRIGHT", 1.5, -1.5); f.ring:SetTexture(MEDIA .. "dot"); f.ring:Hide()
    f.tex = f:CreateTexture(nil, "OVERLAY"); f.tex:SetAllPoints()
    if not plain and spec.pulse then
        -- breathing size, not SetScale: the library anchors the pin by its centre and a scaled frame would drift
        f.base = size
        f:SetScript("OnUpdate", function(self)
            local k = 1 + 0.14 * math.sin((GetTime and GetTime() or 0) * 4)
            self:SetSize(self.base * k, self.base * k)
        end)
    end
    if not plain and world and spec.caption then
        f.caption = f:CreateFontString(nil, "OVERLAY")
        f.caption:SetFont(A.FontPath and A.FontPath() or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        f.caption:SetTextColor(1, 0.9, 0.35, 1)
        f.caption:SetPoint("LEFT", f, "RIGHT", 5, 0)
    end
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
    f:SetScript("OnMouseUp", function(self, key)
        if key == "LeftButton" and self.spec and self.spec.navigate and M.NavigateLayerSpot then M.NavigateLayerSpot(self.spec) end
    end)
    return f
end

local function paint(frame, spec)
    frame.spec = spec
    local c = spec.color or {1, 1, 1}
    if spec.iconFile then
        frame.tex:SetTexture(spec.iconFile); frame.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92); frame.tex:SetVertexColor(1, 1, 1)
        if frame.ring then frame.ring:SetVertexColor(c[1], c[2], c[3]); frame.ring:Show() end
    else
        frame.tex:SetTexture(MEDIA .. (ICONS[spec.icon] or "dot")); frame.tex:SetTexCoord(0, 1, 0, 1); frame.tex:SetVertexColor(c[1], c[2], c[3])
        if frame.ring then frame.ring:Hide() end
    end
    if frame.caption then frame.caption:SetText(spec.title or "") end
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
local function nameParts(name)
    name = A.Text(name, 150)
    if not name then return end
    local character, realm = name:match("^([^%-]+)%-?(.*)$")
    return character and character:lower(), realm and realm:lower():gsub("[%s%-]", "")
end
local function unitIdentity(unit)
    local guid = A.Text(A.Call(UnitGUID, unit), 100)
    local name, realm = A.Call(UnitFullName, unit)
    name = A.Text(name, 100) or A.Text(A.Call(UnitName, unit), 100)
    local mine, mineRealm = nameParts(name)
    realm = A.Text(realm, 100)
    if not realm or realm == "" then realm = mineRealm and mineRealm ~= "" and mineRealm or A.Text(A.Call(GetRealmName), 100) end
    return {guid = guid, name = mine, realm = (realm or ""):lower():gsub("[%s%-]", "")}
end
local function samePlayer(peer, identity)
    local peerGuid = A.Text(peer.guid, 100)
    if identity.guid and peerGuid then return identity.guid == peerGuid end
    local other, otherRealm = nameParts(peer.full or peer.name)
    if not identity.name or other ~= identity.name then return false end
    return not otherRealm or otherRealm == "" or identity.realm == otherRealm
end
local function groupUnits()
    local units = {}
    local raid = A.Call(IsInRaid) == true
    local count = A.Number(A.Call(GetNumGroupMembers), 0, 40) or 0
    for i = 1, raid and count or math.max(0, count - 1) do units[#units + 1] = (raid and "raid" or "party") .. i end
    return units
end
local function inMyGroup(peer, units, identities)
    for _, unit in ipairs(units) do if samePlayer(peer, identities[unit]) then return true, unit end end
    -- These APIs return a party/raid index on real clients, not just boolean true.
    for _, spec in ipairs({{UnitInParty, "party"}, {UnitInRaid, "raid"}}) do
        local yes = A.Call(spec[1], peer.full or peer.name)
        local _, realm = nameParts(peer.full or peer.name)
        if (yes == nil or yes == false) and (not realm or realm == "" or realm == identities.player.realm) then yes = A.Call(spec[1], peer.name) end
        if yes == true then return true end
        local index = A.Number(yes, 1, 40)
        if index then return true, spec[2] .. math.floor(index) end
    end
    return false
end
local function nativeWorldGroup(unit)
    if not unit or not C_Map then return false end
    local map = A.Number(A.Call(C_Map.GetBestMapForUnit, unit), 1)
    local position = map and A.Call(C_Map.GetPlayerMapPosition, map, unit)
    local x, y
    local xy = A.Field(position, "GetXY")
    if type(xy) == "function" then x, y = A.Call(xy, position)
    else x, y = A.Field(position, "x"), A.Field(position, "y") end
    x, y = A.Number(x, 0, 1), A.Number(y, 0, 1)
    if not x or not y or x == 0 and y == 0 then return false end
    local api, openMap = rawget(_G, "OpenMapAPI"), rawget(_G, "OpenMap")
    if api and A.Call(api.IsStitched) == true then
        -- OpenMap places every known group member on its stitched map, when its
        -- group layer is enabled. Keep our beacon if it only knows a rough zone.
        local mod = openMap and A.Call(openMap.GetModule, openMap, "worldmap")
        if A.Field(A.Field(mod, "db"), "group") ~= true then return false end
        local u, v = A.Call(A.Field(mod, "ToWorld"), map, x, y)
        return A.Number(u) ~= nil and A.Number(v) ~= nil
    end
    local host = WorldMapFrame and A.Number(A.Call(WorldMapFrame.GetMapID, WorldMapFrame), 1)
    -- Blizzard places group units on the zone/city and its parent maps, but not
    -- on the whole-world view. Do not suppress a beacon on an unrelated map.
    if not host or host == 947 or host == 946 then return false end
    for _ = 1, 10 do
        if map == host then return true end
        map = A.Number(A.Field(A.Call(C_Map.GetMapInfo, map), "parentMapID"), 1)
        if not map then break end
    end
    return false
end

--- Everything that should be on the maps right now: {id = spec}.
local function wanted()
    local out = {}
    local units = groupUnits()
    local identities = {player = unitIdentity("player")}
    for _, unit in ipairs(units) do identities[unit] = unitIdentity(unit) end
    for _, peer in ipairs(A.LivePeers()) do
        if not samePlayer(peer, identities.player) then
        local grouped, unit = inMyGroup(peer, units, identities)
        local distance = M.DistanceTo(peer.map, peer.x, peer.y)
        out["p:" .. peer.name:lower()] = {
            icon = "dot", color = classColor(peer.class), map = peer.map, x = peer.x, y = peer.y, title = peer.name, edge = false,
            -- the game itself already draws the people of your group on the minimap
            skipMini = grouped,
            skipWorld = grouped and nativeWorldGroup(unit),
            lines = {zoneName(peer.map) .. " · " .. age(peer.at), distance and (string.format("%d yd", math.floor(distance + 0.5))) or nil},
        }
        end
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
        local goal = pin.id == "goal"
        out["n:" .. pin.id] = {icon = goal and "goal" or "next", color = goal and {1, 0.84, 0.1} or {0.655, 0.545, 0.98}, map = pin.map, x = pin.x, y = pin.y, title = pin.title, edge = true,
            pulse = goal, caption = goal, lines = {zoneName(pin.map)}}
    end
    return out
end

M.Wanted = wanted -- also what the map in the window draws

function M.Refresh()
    local want = wanted()
    for id in pairs(pool) do if not want[id] then remove(id) end end
    for id, spec in pairs(want) do
        local entry = pool[id]
        if not entry then
            local big = SIZES[spec.icon]
            entry = {world = newFrame(spec, big and big.world or 18, true), mini = newFrame(spec, big and big.mini or 14, false)}
            pool[id] = entry
        end
        paint(entry.world, spec); paint(entry.mini, spec)
        -- re-adding a frame moves it: HereBeDragons keeps one record per frame
        if spec.skipWorld then pcall(Pins.RemoveWorldMapIcon, Pins, REF, entry.world); entry.world:Hide()
        else pcall(Pins.AddWorldMapIconMap, Pins, REF, entry.world, spec.map, spec.x, spec.y, WORLD_FLAG) end
        if spec.skipMini then pcall(Pins.RemoveMinimapIcon, Pins, REF, entry.mini); entry.mini:Hide()
        else pcall(Pins.AddMinimapIconMap, Pins, REF, entry.mini, spec.map, spec.x, spec.y, false, spec.edge) end
    end
end

-- ---------------------------------------------------------------- layers of places on the world map that is shown
local MAX_LAYER_PINS = 900
local function signature(maps)
    local on, scan = M.ActiveLayers(), M.Db and M.Db.scan
    return table.concat({table.concat(maps, ","), on.travel and "t" or "-", on.trainer and "r" or "-", on.vendor and "v" or "-", on.inn and "i" or "-", on.gather and "g" or "-", on.instances and "d" or "-",
        tostring(#M.extra), scan and (scan.done and "done" or tostring(math.floor(scan.at / 3000))) or "none"}, ":")
end

--- Draws the places of the layers that are on, and the places picked on purpose, on the maps the player is looking at: the one the game
--- shows and, in OpenMap's stitched world, the zones round the view. Cheap when nothing changed: it only compares a short signature.
function M.RefreshLayerPins(force)
    local maps = M.VisibleMaps()
    local key = signature(maps)
    if not force and key == layerKey then return end
    layerKey = key
    pcall(Pins.RemoveAllWorldMapIcons, Pins, REF_LAYERS)
    for _, frame in ipairs(layerPool) do frame:Hide() end
    for _, frame in ipairs(extraPool) do frame:Hide() end
    if #maps == 0 then return end
    local visible = {}
    for _, id in ipairs(maps) do visible[id] = true end
    local n, drawn, total = 0, 0, 0
    for _, mapId in ipairs(maps) do
        local specs = M.MapPlaces(mapId)
        drawn, total = drawn + (M.gatherDrawn or 0), total + (M.gatherTotal or 0)
        for _, spec in ipairs(specs) do
            if n >= MAX_LAYER_PINS then break end
            n = n + 1
            local frame = layerPool[n]
            if not frame then frame = newFrame(spec, 12, false, true); layerPool[n] = frame end
            local size = spec.iconFile and 13 or 10
            frame:SetSize(size, size)
            paint(frame, spec)
            pcall(Pins.AddWorldMapIconMap, Pins, REF_LAYERS, frame, spec.map, spec.x, spec.y)
        end
    end
    M.gatherDrawn, M.gatherTotal = drawn, total
    local e = 0
    for _, spec in ipairs(M.extra) do
        if visible[spec.map] then
            e = e + 1
            local frame = extraPool[e]
            if not frame then frame = newFrame({pulse = true, caption = true}, 24, true); extraPool[e] = frame end
            frame:SetSize(24, 24)
            paint(frame, spec)
            pcall(Pins.AddWorldMapIconMap, Pins, REF_LAYERS, frame, spec.map, spec.x, spec.y)
        end
    end
    if M.PanelRefresh then M.PanelRefresh() end
end

function M.Disable()
    M.Stop()
    M.route = nil
    if M.ClearRouteDots then M.ClearRouteDots() end
    if ticker then ticker:Cancel(); ticker = nil end
    if layerTicker then layerTicker:Cancel(); layerTicker = nil end
    layerKey = nil
    pcall(Pins.RemoveAllWorldMapIcons, Pins, REF_LAYERS)
    for _, frame in ipairs(layerPool) do frame:Hide() end
    for _, frame in ipairs(extraPool) do frame:Hide() end
    for id in pairs(pool) do remove(id) end
    pcall(Pins.RemoveAllWorldMapIcons, Pins, REF)
    pcall(Pins.RemoveAllMinimapIcons, Pins, REF)
end

function M.Enable()
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(REFRESH, function() local ok = pcall(M.Refresh); if not ok then A.errors.map_refresh = (A.errors.map_refresh or 0) + 1 end end) end
    -- the layers on the map that is shown, the panel on the world map and the switches in OpenMap's menu
    if not layerTicker and C_Timer and C_Timer.NewTicker then
        layerTicker = C_Timer.NewTicker(0.4, function()
            local ok = pcall(function()
                if not M.panelBuilt then M.panelBuilt = M.BuildMapPanel and M.BuildMapPanel() or false end
                if not M.openMapRegistered and M.RegisterWithOpenMap then M.RegisterWithOpenMap() end
                if M.RefreshRoute then M.RefreshRoute() end
                M.StepServices()
                M.RefreshLayerPins(false)
            end)
            if not ok then A.errors.map_layers = (A.errors.map_layers or 0) + 1 end
        end)
    end
    M.Refresh()
end

-- (the guide pages load this add-on too, without "Map and minimap": then nothing is drawn until that is switched on)
if A.db and A.db.settings.mapPins == true then M.Enable() end
-- last: the main add-on treats "Evertally.map exists" as "loaded completely"
A.map = M
