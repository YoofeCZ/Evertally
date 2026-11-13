local _, M = ...
local A = _G.Evertally
-- Only the flight master's CURRENT/REACHABLE states prove a learned flight
-- point on Forever. GetTaxiNodesForMap lists unvisited points as well.
local K = {open = false}
M.TravelKnowledge = K

local function store()
    if not A.db then return end
    local character, game = A.Character(), A.Game()
    if not character then return end
    local key = table.concat({game.product, game.region, character.realm, character.id}, ":")
    A.db.travelKnowledge = A.db.travelKnowledge or {}
    local record = A.db.travelKnowledge[key]
    if type(record) ~= "table" then
        record = {known = {}, revision = 0}
        A.db.travelKnowledge[key] = record
    end
    record.known = record.known or {}
    return record, key
end

local function nodeByName(name)
    name = A.Text(name, 200)
    if not name then return end
    local found
    for id, hub in pairs(M.data.hubs) do
        if hub[6] == name then
            local node = tonumber(id:match("^taxi(%d+)$"))
            if node then
                if found and found ~= node then return end -- ambiguous names are not evidence
                found = node
            end
        end
    end
    return found
end

function K.Refresh()
    if not K.open then return false end
    local record = store()
    if not record then return false end
    local changed, hasCurrent, candidates = false, false, {}
    local function learn(id)
        id = A.Number(id, 1, 10000000)
        if id and M.data.hubs["taxi" .. id] and record.known[id] ~= true then
            record.known[id], changed = true, true
        end
    end
    local map = A.Number(A.Call(GetTaxiMapID), 1)
    local list = map and C_TaxiMap and A.Call(C_TaxiMap.GetAllTaxiNodes, map)
    if type(list) == "table" then
        local states = Enum and Enum.FlightPathState or {}
        local current, reachable = states.Current or 0, states.Reachable or 1
        for _, node in pairs(list) do
            local state = A.Field(node, "state")
            if state == current then hasCurrent=true end
            if state == current or state == reachable then
                local id=A.Number(A.Field(node,"nodeID"),1,10000000)
                if id then candidates[id]=true end
            end
        end
    end
    local count = A.Number(A.Call(NumTaxiNodes), 0, 1000)
    for index = 1, count or 0 do
        local state = A.Text(A.Call(TaxiNodeGetType, index), 30)
        if state=="CURRENT" then hasCurrent=true end
        if state == "CURRENT" or state == "REACHABLE" then
            -- Legacy indices are menu slots, never taxi IDs. Match only a unique
            -- complete hub name when the node-ID API is unavailable.
            local id = nodeByName(A.Call(TaxiNodeName, index))
            if id then candidates[id]=true end
        end
    end
    if not hasCurrent then return false end
    for id in pairs(candidates) do learn(id) end
    if changed then
        record.revision = (A.Number(record.revision, 0) or 0) + 1
        record.at = A.Now()
        if M.nav then M.nav.force = true end
        if A.RefreshUI then A.RefreshUI() end
    end
    return changed
end

function K.Options()
    local record, key = store()
    local known = {}
    for id, value in pairs(record and record.known or {}) do
        if value == true and A.Number(id, 1) then known[id] = true end
    end
    return known, (key or "unknown-character") .. ":" .. tostring(record and record.revision or 0)
end

local frame = CreateFrame("Frame")
for _, event in ipairs({"TAXIMAP_OPENED", "TAXIMAP_CLOSED", "TAXI_NODE_STATUS_CHANGED", "NEW_TAXI_PATH", "PLAYER_ENTERING_WORLD"}) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event)
    if event == "TAXIMAP_CLOSED" then K.open = false; return end
    if event == "TAXIMAP_OPENED" then K.open = true end
    if event == "PLAYER_ENTERING_WORLD" then
        K.open = false
        if M.nav then M.nav.force = true end
    end
    K.Refresh()
    if event=="TAXIMAP_OPENED" and C_Timer and C_Timer.After then
        C_Timer.After(0,function() if K.open then K.Refresh() end end)
    end
end)
-- This load-on-demand module may first open while the taxi window is already
-- visible. A valid CURRENT state is still required before learning anything.
local function taxiWindowShown(window)
    return window and A.Call(window.IsShown,window)==true
end
if taxiWindowShown(_G.TaxiFrame) or taxiWindowShown(_G.FlightMapFrame) then
    K.open=true;K.Refresh()
end
