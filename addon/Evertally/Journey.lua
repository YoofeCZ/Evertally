local _, A = ...
-- The moments of the player's journey that no other recorded event carries: kills (from the experience message), money gained or spent,
-- skill-ups, deaths, joining or leaving a group, and flights. They are written to the web outbox in BATCHES ("journey.chunk", one event per
-- few minutes of play, so a long session costs the website a handful of rows, not thousands), under the same consent as the route
-- ("own_track"), and never into the local history list. Quests, loot, zones, levels, dungeons and bosses are recorded by their own events.
local J = {}
A.Journey = J
local MAX_MOMENTS, BATCH_SECONDS, MAX_BATCH_BYTES = 128, 300, 180 * 1024
local current

local function active()
    local s = A.db and A.db.settings
    return s ~= nil and s.web == true and type(s.scopes) == "table" and s.scopes.own_track == true and A.ExportStore() ~= nil
end
local function round(v) return math.floor(v * 1000 + 0.5) / 1000 end

function J.Flush()
    local batch = current; current = nil
    if not batch or #batch.events == 0 or not active() then return end
    A.Record("journey.chunk", {startedAt = batch.startedAt, events = batch.events}, "api_snapshot", nil, true)
end
function A.ResetJourney() current = nil end

local function add(kind, fields, at)
    if not active() then current = nil; return end
    local now = at or A.Now()
    if current and (now < current.startedAt or now - current.startedAt >= BATCH_SECONDS or #current.events >= MAX_MOMENTS) then J.Flush() end
    current = current or {startedAt = now, events = {}, bytes = 64}
    local moment = fields or {}
    moment.t, moment.k = now - current.startedAt, kind
    local map, x, y = moment.mapId, moment.x, moment.y
    if not map and not at then map, x, y = A.PlayerPosition() end
    if map and x and y then moment.mapId, moment.x, moment.y = map, round(x), round(y) end
    if (kind == "kill" or kind == "death") and J.CurrentFightId then moment.fightId = J.CurrentFightId() end
    local encoded = A.Encode(moment)
    if not encoded or #encoded > MAX_BATCH_BYTES - 256 then A.errors["journey.oversize"] = (A.errors["journey.oversize"] or 0) + 1; return end
    if current.bytes + #encoded + 1 > MAX_BATCH_BYTES then
        J.Flush(); current = {startedAt = now, events = {}, bytes = 64}; moment.t = 0; encoded = A.Encode(moment)
    end
    current.events[#current.events + 1] = moment
    current.bytes = current.bytes + #encoded + 1
end
J.Add = add

-- Blizzard's own message templates, in the client's language ("%s dies, you gain %d experience."), turned into patterns.
-- A template this client does not have is skipped, and a message that matches none of them is ignored.
local function pattern(key)
    local format = A.Text(_G[key], 1000)
    if not format then return end
    local p = format:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return p:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
end
local XP_KEYS = {"COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "COMBATLOG_XPGAIN_FIRSTPERSON_RAID"}
-- A kill is the message that names what died; "You gain N experience." (a quest, exploring) names nothing and is not a kill.
A.On("CHAT_MSG_COMBAT_XP_GAIN", function(message)
    message = A.Text(message, 512)
    if not message then return end
    for _, key in ipairs(XP_KEYS) do
        local p = pattern(key)
        local name, xp = nil, nil
        if p then name, xp = message:match("^" .. p) end
        xp = tonumber(xp)
        if name and xp and xp > 0 and xp < 1e7 then if J.NoteKill then J.NoteKill(name) end; add("kill", {text = A.Text(name, 100), xp = xp}); return end
    end
end)

-- Money: the change since the last look. Gold spent is a moment too.
local money
local function purse() return A.Number(A.Call(GetMoney), 0) end
local function look()
    local now = purse()
    if not now then return end
    if money and now ~= money then add("money", {n = now - money, text = now > money and "Money" or "Spent"}) end
    money = now
end
A.On("PLAYER_MONEY", look)

-- Skills: "Your skill in %s has increased to %d."; the maximum comes from the skill list when the client has one.
local function skillMax(name)
    local count = A.Number(A.Call(GetNumSkillLines), 0, 300) or 0
    for i = 1, count do
        local skill, header, _, _, _, _, maxRank = A.Call(GetSkillLineInfo, i)
        if skill == name and header ~= true then return A.Number(maxRank, 1, 100000) end
    end
end
A.On("CHAT_MSG_SKILL", function(message)
    message = A.Text(message, 512)
    local p = message and pattern("SKILL_RANK_UP")
    local name, value = nil, nil
    if p then name, value = message:match("^" .. p) end
    value = tonumber(value)
    if name and value then add("skill", {text = A.Text(name, 100), n = value, max = skillMax(name)}) end
end)

A.On("PLAYER_DEAD", function() add("death", {text = "You died"}) end)

-- A group: joining and leaving, not every change of its members.
local grouped
local function groupState() return A.Call(IsInGroup) == true end
A.On("GROUP_ROSTER_UPDATE", function()
    local now = groupState()
    if grouped ~= nil and now ~= grouped then
        if now then add("group", {a = "join", text = "Joined a group of " .. tostring(A.Number(A.Call(GetNumGroupMembers), 1, 40) or 2)})
        else add("group", {a = "leave", text = "Left the group"}) end
    end
    grouped = now
end)

A.On("PLAYER_ENTERING_WORLD", function() money = purse(); grouped = groupState() end)
A.On("PLAYER_LOGOUT", J.Flush)

-- Flights have no event: the state is looked at every two seconds, and an old batch is closed here as well.
local onTaxi
if C_Timer and type(C_Timer.NewTicker) == "function" then
    C_Timer.NewTicker(2, function()
        local on = A.Call(UnitOnTaxi, "player") == true
        if onTaxi ~= nil and on and not onTaxi then add("travel", {a = "flight", text = "Took a flight"}) end
        onTaxi = on
        if current and A.Now() - current.startedAt >= BATCH_SECONDS then J.Flush() end
    end)
end
