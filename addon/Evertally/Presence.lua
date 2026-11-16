local _, A = ...
-- "Online with Evertally": players who chose to be seen tell the other Evertally players that they are online, with an
-- invisible addon message in the #Evertally chat room (Chat.lua joins it for everyone). The message carries only the class,
-- the level and the zone (an area, never a position); the server supplies the sender's name, so nobody can announce
-- somebody else. Off by default. Receiving needs no consent: only players who opted in are ever listed.
local P = {peers = {}}
A.Presence = P
local words = {
    en = {presence = "Show me to other Evertally players (name, class, level, zone; never a position)",
        peopleCatOnline = "Online with Evertally", peopleFlag_online = "online", presenceSeen = "%d min ago",
        chatInvite = "Invite to group", chatAddFriend = "Add friend", chatInvited = "Invitation sent.", chatFriendAdded = "Friend request sent.",
        setupPresenceSub = "Players outside your friends, group and guild see that you are online, with your class, level and zone. Your exact position stays with friends and group."},
    cs = {presence = "Ukázat mě ostatním hráčům s Evertally (jméno, třída, level, zóna; nikdy poloha)",
        peopleCatOnline = "Online s Evertally", peopleFlag_online = "online", presenceSeen = "před %d min",
        chatInvite = "Pozvat do skupiny", chatAddFriend = "Přidat do přátel", chatInvited = "Pozvánka odeslána.", chatFriendAdded = "Žádost o přátelství odeslána.",
        setupPresenceSub = "Hráči mimo přátele, skupinu a cech uvidí, že jsi online, s tvou třídou, levelem a zónou. Přesná poloha zůstává jen pro přátele a skupinu."},
}
for lang, entries in pairs(words) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local PREFIX, FORGET, EVERY, GAP, MAX = "EvtlyHere", 900, 300, 30, 200

local function text(v, max) v = A.Plain(v); if type(v) == "string" and v ~= "" then return v:sub(1, max or 255) end end
-- "Bran", "Bran-Realm" and Forever's "Bran Realm" are one player
local function key(name) name = text(name, 80); return name and (name:match("^[^%- ]+") or name):lower() end
local function me() return key(A.Text(A.Call(UnitName, "player"), 60)) end

function P.Enabled() return A.db ~= nil and A.db.settings.presence == true end
local function channel()
    local id = A.Call(GetChannelName, "Evertally"); id = A.Number(id)
    if id and id > 0 then return id end
end
local function send(message)
    local id = channel()
    if not id or not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then return false end
    return (pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, "CHANNEL", id))
end

function P.Payload()
    local _, _, classId = A.Call(UnitClass, "player")
    local level = A.Number(A.Call(UnitLevel, "player"), 1, 200) or 0
    local map = C_Map and A.Number(A.Call(C_Map.GetBestMapForUnit, "player"), 1, 1000000) or 0
    return string.format("P|1|%d|%d|%d", A.Number(classId, 1, 100) or 0, level, map)
end
-- force: a zone change or a level up; still at most one message per GAP seconds
function P.Announce(force)
    if not P.Enabled() or (A.Chat and not A.Chat.Enabled()) then return false end
    local now = A.Monotonic()
    if P.lastSent and now - P.lastSent < (force and GAP or EVERY - 5) then return false end
    if send(P.Payload()) then P.lastSent = now; return true end
    return false
end
function P.SetEnabled(on)
    if not A.db then return end
    local was = P.Enabled()
    A.db.settings.presence = on == true
    if on then P.lastSent = nil; P.Announce(true)
    elseif was then send("P|0") end   -- the others drop this player at once instead of after FORGET
    if A.RefreshUI then A.RefreshUI() end
end

function P.Receive(prefix, message, _, sender)
    if text(prefix, 20) ~= PREFIX then return end
    message = text(message, 60); sender = text(sender, 80)
    local who = key(sender); if not message or not who or who == me() then return end
    if message == "P|0" then P.peers[who] = nil; return true end
    local class, level, map = message:match("^P|1|(%d+)|(%d+)|(%d+)$")
    if not class then return end
    P.peers[who] = {name = sender, class = A.Number(tonumber(class), 1, 100), level = A.Number(tonumber(level), 1, 200),
        map = A.Number(tonumber(map), 1, 1000000), seen = A.Now()}
    if A.NoteEvertallyUser then pcall(A.NoteEvertallyUser, sender) end
    -- bounded: the oldest go first
    local n, oldest = 0, nil
    for k, peer in pairs(P.peers) do n = n + 1; if not oldest or peer.seen < P.peers[oldest].seen then oldest = k end end
    if n > MAX and oldest then P.peers[oldest] = nil end
    return true
end

function P.List()
    local now, out = A.Now(), {}
    for k, peer in pairs(P.peers) do
        if now - peer.seen > FORGET then P.peers[k] = nil else out[#out + 1] = peer end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end
function P.Get(name) local peer = P.peers[key(name) or ""]; if peer and A.Now() - peer.seen <= FORGET then return peer end end

-- Group invite and friend request from the chat window, in the player's own click.
function P.Invite(name)
    name = text(name, 80); if not name then return false end
    local fn = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
    return type(fn) == "function" and (pcall(fn, name)) or false
end
function P.AddFriend(name)
    name = text(name, 80); if not name then return false end
    local fn = C_FriendList and C_FriendList.AddFriend or AddFriend
    return type(fn) == "function" and (pcall(fn, name)) or false
end

A.On("PLAYER_LOGIN", function()
    if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
end)
A.On("PLAYER_ENTERING_WORLD", function()
    if P.started then return end; P.started = true
    -- after Chat.lua has joined #Evertally (6 s after loading)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(12, function() pcall(P.Announce, true) end)
        if type(C_Timer.NewTicker) == "function" then C_Timer.NewTicker(EVERY, function() pcall(P.Announce) end) end
    end
end)
A.On("ZONE_CHANGED_NEW_AREA", function() P.Announce(true) end)
A.On("PLAYER_LEVEL_UP", function() P.Announce(true) end)
A.On("PLAYER_LOGOUT", function() if P.Enabled() then send("P|0") end end)
-- An open People page follows new players, repainted at most every five seconds however many announce.
A.On("CHAT_MSG_ADDON", function(...)
    if P.Receive(...) and A.RefreshUI and A.Monotonic() - (P.lastRefresh or -10) >= 5 then P.lastRefresh = A.Monotonic(); pcall(A.RefreshUI) end
end)
