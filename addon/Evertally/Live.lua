local _, A = ...
-- Live position between players who chose to share it, pings on the map, and the switch for the map add-on.
--
--  * "Live position" is opt-in per channel (party / raid, guild and friends), off by default. While it is on, your map, your position
--    on it (0..1 of the zone map) and your class go out as one small addon message about every 5 seconds, only while you move.
--    Others see it only if they run the addon; nothing is sent to the website and nothing is saved.
--  * A ping is a single point sent once to your group or guild, shown for 5 minutes.
--  * What is drawn on the world map and the minimap, and navigation, lives in Evertally_Map: a load-on-demand add-on that
--    loads only after "Map and minimap" is switched on, so a player who never switches it on never runs any of it.
local L = {peers = {}, pings = {}, lastSent = {}, seen = {}}
A.live = L
local BEACON_GAP, HEARTBEAT, MOVED, PEER_TTL, PING_TTL = 5, 30, 0.003, 120, 300
local MAX_PEERS, MAX_PINGS, PEER_GAP, PING_GAP = 120, 20, 2, 5
local CHANNELS = {PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true}
local floor = math.floor

local function settings() return A.db and A.db.settings end
local function base(name) return (A.Text(name, 150) or ""):match("^[^-]+") or "" end
local function myName() return A.Text(A.Call(UnitName, "player"), 80) or "" end
local function isMe(sender) local b = base(sender):lower(); return b ~= "" and b == base(myName()):lower() end
local function clean(text, max) return A.SocialClean and A.SocialClean(text, max) or "" end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function fields(message) local out = {}; for part in message:gmatch("[^|]+") do out[#out + 1] = part end; return out end
local function zoneName(mapId)
    local info = C_Map and A.Call(C_Map.GetMapInfo, mapId)
    return A.Text(A.Field(info, "name"), 80) or (A.L("map") .. " #" .. tostring(mapId))
end

-- ---------------------------------------------------------------- sending
local function groupChannel()
    if A.Call(IsInRaid) == true then return "RAID" end
    if A.Call(IsInGroup) == true then return "PARTY" end
end
-- Friends: the friends on your own friends list (character friends, and Battle.net friends who are in WoW). The same beacons
-- are whispered to the ones who are online (at most MAX_FRIEND_TARGETS); a whispered beacon is accepted only from someone on
-- YOUR friends list, so a stranger cannot put a dot on your map, and both sides have to have each other.
local FRIEND_REFRESH, MAX_FRIEND_TARGETS = 20, 12
local friendCache = {at = -1000, names = {}, targets = {}}
local blockedFriends = {}
local function realmKey(realm) return (A.Text(realm, 100) or ""):gsub("%s", ""):lower() end
local function whisperName(name, realm)
    name = A.Text(name, 150)
    if not name then return nil end
    local short, suffix = name:match("^([^-]+)%-(.+)$")
    if short then name, realm = short, suffix end
    -- Character names cannot contain spaces, punctuation, digits or control bytes.
    if #name < 2 or #name > 48 or name:find("[^%a\128-\255]") then return nil end
    local ownRealm = realmKey(A.Call(GetRealmName))
    if ownRealm == "" or (realm and realm ~= "" and realmKey(realm) ~= ownRealm) then return nil end
    if isMe(name) then return nil end
    return name
end
local function friends()
    local now = A.Monotonic()
    if now - friendCache.at < FRIEND_REFRESH then return friendCache end
    local names, targets, seen = {}, {}, {}
    local function add(name, realm, online)
        name = whisperName(name, realm)
        if not name then return end
        local key = name:lower()
        names[key] = true
        if online == true and not seen[key] and not blockedFriends[key] and #targets < MAX_FRIEND_TARGETS then
            seen[key] = true
            targets[#targets + 1] = name
        end
    end
    if C_FriendList and type(C_FriendList.GetNumFriends) == "function" and type(C_FriendList.GetFriendInfoByIndex) == "function" then
        for i = 1, A.Number(A.Call(C_FriendList.GetNumFriends), 0, 500) or 0 do
            local info = A.Call(C_FriendList.GetFriendInfoByIndex, i)
            if type(info) == "table" then add(A.Field(info, "name"), A.Field(info, "realmName"), A.Field(info, "connected") == true) end
        end
    elseif type(GetNumFriends) == "function" and type(GetFriendInfo) == "function" then
        for i = 1, A.Number(A.Call(GetNumFriends), 0, 500) or 0 do
            local name, _, _, _, connected = A.Call(GetFriendInfo, i)
            add(name, nil, connected == true)
        end
    end
    if C_BattleNet and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends then
        for i = 1, A.Number(A.Call(BNGetNumFriends), 0, 1000) or 0 do
            local info = A.Call(C_BattleNet.GetFriendAccountInfo, i)
            local game = A.Field(info, "gameAccountInfo")
            -- A Battle.net friend's other WoW product/realm is not a character-whisper address.
            -- Only a proven same-project, same-realm character can use this transport.
            local project = A.Number(A.Field(game, "wowProjectID"), 1, 1000)
            local ownProject = A.Number(rawget(_G, "WOW_PROJECT_ID"), 1, 1000)
            if type(game) == "table" and A.Field(game, "clientProgram") == "WoW" and project and project == ownProject and realmKey(A.Field(game, "realmName")) == realmKey(A.Call(GetRealmName)) then
                add(A.Field(game, "characterName"), A.Field(game, "realmName"), A.Field(game, "isOnline") == true)
            end
        end
    end
    friendCache = {at = now, names = names, targets = targets}
    return friendCache
end
local function friendTargets()
    local s = settings()
    if not s or s.liveFriends ~= true then return {} end
    local out = {}
    for _, target in ipairs(friends().targets) do
        local raid = A.Call(UnitInRaid, target)
        local grouped = s.liveParty == true and (A.Call(UnitInParty, target) == true or raid ~= nil and raid ~= false)
        if not blockedFriends[target:lower()] and not grouped then out[#out + 1] = target end
    end
    return out
end
-- Rechecked by the shared queue before sending a deferred live-friend message.
-- It does not apply to inspect/trade or other manually requested social messages.
function A.LiveWhisperAllowed(target, ending)
    local name = whisperName(target)
    local s = settings()
    if not name or blockedFriends[name:lower()] or not s or (s.liveFriends ~= true and ending ~= true) then return false end
    for _, candidate in ipairs(friends().targets) do if candidate:lower() == name:lower() then return true end end
    return false
end
-- Invalidate cached online states immediately. A server-rejected target stays blocked for
-- this addon session, including toggles, so stale friend APIs cannot restart the error flood.
for _, event in ipairs({"FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED", "GROUP_ROSTER_UPDATE"}) do
    A.On(event, function() friendCache.at = -1000 end)
end
local function playerNotFound(message)
    message = A.Text(message, 300)
    local format = A.Text(rawget(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S"), 300)
    if not message or not format then return end
    local prefix, suffix = format:match("^(.-)%%s(.*)$")
    if not prefix or message:sub(1, #prefix) ~= prefix or (#suffix > 0 and message:sub(-#suffix) ~= suffix) then return end
    local target = message:sub(#prefix + 1, #message - #suffix)
    target = whisperName(target)
    if not target or not friends().names[target:lower()] then return end
    blockedFriends[target:lower()] = true
    friendCache.at = -1000
end
A.On("CHAT_MSG_SYSTEM", playerNotFound)
A.On("UI_ERROR_MESSAGE", function(_, message) playerNotFound(message) end)
local function liveChannels()
    local s, out = settings(), {}
    if not s then return out end
    if s.liveParty == true then local c = groupChannel(); if c then out[#out + 1] = c end end
    if s.liveGuild == true and A.Call(IsInGuild) == true then out[#out + 1] = "GUILD" end
    return out
end

--- One beacon per channel (and per online friend) when it is due: you moved (at most every 5 s) or 30 s passed. Newer ones replace queued older ones.
function A.LiveTick()
    local channels, targets = liveChannels(), friendTargets()
    if #channels == 0 and #targets == 0 then return end
    local map, x, y = A.PlayerPosition()
    if not map or not x or not y then return end -- instances and loading screens have no map position
    local now = A.Monotonic()
    local character = A.Character()
    local class = character and character.classId or 0
    local text = string.format("S|L|%d|%d|%d|%d", map, floor(x * 1000 + 0.5), floor(y * 1000 + 0.5), class)
    local function send(key, channel, target)
        local last = L.lastSent[key]
        local moved = not last or last.map ~= map or math.abs(x - last.x) + math.abs(y - last.y) >= MOVED
        local due = not last or (moved and now - last.at >= BEACON_GAP) or now - last.at >= HEARTBEAT
        if due and A.QueueSocial(text, channel, target, "L:" .. key) then L.lastSent[key] = {map = map, x = x, y = y, at = now} end
    end
    for _, channel in ipairs(channels) do send(channel, channel, nil) end
    for _, target in ipairs(targets) do send("F:" .. target:lower(), "WHISPER", target) end
end

--- which = "party" (party / raid), "guild" or "friends".
function A.SetLive(which, enabled)
    local s = settings()
    if not s then return end
    local key = which == "guild" and "liveGuild" or which == "friends" and "liveFriends" or "liveParty"
    enabled = enabled == true
    if (s[key] == true) == enabled then return end
    s[key] = enabled
    if A.RefreshConnections then A.RefreshConnections() end
    if enabled then
        A.Print(A.L(which == "guild" and "liveOnGuild" or which == "friends" and "liveOnFriends" or "liveOnParty"))
    elseif which == "friends" then
        -- tell the friends at once too
        friendCache.at = -1000
        for _, target in ipairs(friends().targets) do
            local friendKey = "F:" .. target:lower()
            L.lastSent[friendKey] = nil
            A.QueueSocial("S|E", "WHISPER", target, "L:" .. friendKey)
        end
    else
        -- tell the others at once instead of leaving a stale dot for two minutes
        for _, channel in ipairs(which == "guild" and {"GUILD"} or {"PARTY", "RAID"}) do
            L.lastSent[channel] = nil
            if channel == "GUILD" and A.Call(IsInGuild) == true or (channel ~= "GUILD" and groupChannel() == channel) then A.QueueSocial("S|E", channel, nil, "L:" .. channel) end
        end
    end
    A.Changed()
end
function A.LiveActive() local s = settings(); return s ~= nil and (s.liveParty == true or s.liveGuild == true or s.liveFriends == true) end

-- ---------------------------------------------------------------- receiving
local function prune()
    local now = A.Now()
    for k, p in pairs(L.peers) do if now - p.at > PEER_TTL then L.peers[k] = nil end end
    for k, g in pairs(L.pings) do if now - g.at > PING_TTL then L.pings[k] = nil end end
end

-- a group or guild channel, or a whisper from someone on my own friends list
local function accepted(channel, sender)
    if CHANNELS[channel] then return true end
    return channel == "WHISPER" and friends().names[base(sender):lower()] == true
end
A.socialHandlers.L = function(channel, sender, message)
    if not accepted(channel, sender) or not A.db or isMe(sender) then return end
    local f = fields(message)
    local map, x, y, class = A.Number(tonumber(f[3]), 1, 100000), A.Number(tonumber(f[4]), 0, 1000), A.Number(tonumber(f[5]), 0, 1000), A.Number(tonumber(f[6]), 0, 100)
    if not map or not x or not y then return end
    local key, now = base(sender):lower(), A.Monotonic()
    if key == "" or (L.seen[key] and now - L.seen[key] < PEER_GAP) then return end -- a sender cannot flood
    L.seen[key] = now
    if not L.peers[key] then prune(); if count(L.peers) >= MAX_PEERS then return end end
    L.peers[key] = {name = base(sender), full = A.Text(sender, 150), map = floor(map), x = x / 1000, y = y / 1000, class = (class and class > 0) and floor(class) or nil, at = A.Now(), channel = channel}
end
A.socialHandlers.E = function(channel, sender)
    local peer = L.peers[base(sender):lower()]
    if peer and peer.channel == channel then L.peers[base(sender):lower()] = nil end
end

--- Everyone whose beacon arrived in the last two minutes, by name.
function A.LivePeers()
    prune()
    local out = {}
    for _, p in pairs(L.peers) do out[#out + 1] = p end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end
--- One of them by name: exact, or the only one the name is the start of.
function A.LivePeer(name)
    prune()
    local want = base(name):lower()
    if want == "" then return nil end
    if L.peers[want] then return L.peers[want] end
    local found
    for key, p in pairs(L.peers) do if key:sub(1, #want) == want then if found then return nil end; found = p end end
    return found
end

-- ---------------------------------------------------------------- pings
local function remember(ping)
    prune()
    local key = ping.id .. ":" .. ping.name:lower()
    if not L.pings[key] and count(L.pings) >= MAX_PINGS then
        local oldest, oldestKey
        for k, g in pairs(L.pings) do if not oldest or g.at < oldest then oldest, oldestKey = g.at, k end end
        if oldestKey then L.pings[oldestKey] = nil end
    end
    L.pings[key] = ping
end
function A.LivePings()
    prune()
    local out = {}
    for _, g in pairs(L.pings) do out[#out + 1] = g end
    table.sort(out, function(a, b) return a.at > b.at end)
    return out
end

A.socialHandlers.P = function(channel, sender, message)
    if not CHANNELS[channel] or not A.db or isMe(sender) then return end
    local f = fields(message)
    local id, map, x, y = f[3], A.Number(tonumber(f[4]), 1, 100000), A.Number(tonumber(f[5]), 0, 1000), A.Number(tonumber(f[6]), 0, 1000)
    if not id or #id ~= 6 or not id:match("^%x+$") or not map or not x or not y then return end
    local key, now = "P:" .. base(sender):lower(), A.Monotonic()
    if L.seen[key] and now - L.seen[key] < PING_GAP then return end
    L.seen[key] = now
    local label = clean(f[7] or "", 60)
    remember({id = id, name = base(sender), map = floor(map), x = x / 1000, y = y / 1000, label = label, at = A.Now(), channel = channel})
    A.Print(string.format(A.L("pingChat"), base(sender), label ~= "" and label or zoneName(floor(map))))
end

local function pingChannel() return groupChannel() or (A.Call(IsInGuild) == true and "GUILD" or nil) end
--- A point to your group (or guild when you are not in a group). With no map given it is where you stand.
function A.SendPing(label, map, x, y, channel)
    channel = channel or pingChannel()
    if not channel then return false, "no_channel" end
    if not map then map, x, y = A.PlayerPosition() end
    map, x, y = A.Number(tonumber(map), 1, 100000), A.Number(tonumber(x), 0, 1), A.Number(tonumber(y), 0, 1)
    if not map or not x or not y then return false, "no_position" end
    local id = string.format("%06x", math.random(0, 16777215))
    label = clean(label or "", 60)
    if not A.QueueSocial(string.format("S|P|%s|%d|%d|%d|%s", id, floor(map), floor(x * 1000 + 0.5), floor(y * 1000 + 0.5), label), channel) then return false, "queue_full" end
    remember({id = id, name = myName(), map = floor(map), x = floor(x * 1000 + 0.5) / 1000, y = floor(y * 1000 + 0.5) / 1000, label = label, at = A.Now(), channel = channel, mine = true})
    return true
end

-- ---------------------------------------------------------------- the map add-on
--- True when OpenMap, which the map module is built on, is not installed (when the game cannot tell, it is taken to be there).
function A.OpenMapMissing()
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if type(info) ~= "function" then return false end
    local ok, found = pcall(info, "OpenMap")
    return ok and (found == nil or (type(found) == "table" and found.name == nil))
end
function A.LoadMap()
    if A.RequirementsReady and not A.RequirementsReady() then return false,"dependencies_required" end
    local s = settings()
    if not s or s.mapPins ~= true then return false, "disabled" end
    if A.OpenMapMissing() then A.Print(A.L("mapNeedsOpenMap")); return false, "openmap_missing" end
    if A.map then return true end
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if type(loader) ~= "function" then return false, "no_loader" end
    local ok, loaded, reason = pcall(loader, "Evertally_Map")
    if ok and loaded == false and (reason == "DEP_DISABLED" or reason == "DEP_MISSING" or reason == "DEP_DEMAND_LOADED") then
        A.Print(A.L("mapNeedsOpenMap")); return false, "openmap_missing"   -- OpenMap is there but switched off (or gone)
    end
    if not ok or (loaded == false) or not A.map then
        A.errors.map_load = (A.errors.map_load or 0) + 1
        return false, A.Text(not ok and loaded or reason, 80) or "load_failed"
    end
    return true
end
--- Loads the add-on the guide pages (database, dungeon journal, journeys) live in, whether or not "Map and minimap" is on and OpenMap is there.
function A.LoadGuide()
    if A.map then return true end
    local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if type(loader) ~= "function" then return false, "no_loader" end
    local ok, loaded, reason = pcall(loader, "Evertally_Map")
    if not ok or loaded == false or not A.map then
        A.errors.map_load = (A.errors.map_load or 0) + 1
        return false, A.Text(not ok and loaded or reason, 80) or "load_failed"
    end
    return true
end
function A.SetMapPins(enabled)
    local s = settings()
    if not s then return end
    s.mapPins = enabled == true
    if s.mapPins then
        local ok, why = A.LoadMap()
        if ok and A.map and A.map.Enable then A.map.Enable() end
        if ok or why ~= "openmap_missing" then A.Print(A.L(ok and "mapOn" or "mapFail")) end   -- (the missing OpenMap has said so already)
    elseif A.map then
        A.map.Disable(); A.Print(A.L("mapOff"))
    end
    A.Changed()
end

--- Navigates to a player (live position), "meet" (the newest received meet) or "ping" (the newest ping).
function A.NavigateByName(name)
    name = clean(name or "", 80)
    if name == "" then return false, "no_target" end
    local s = settings()
    if not s or s.mapPins ~= true then return false, "map_off" end
    local ok, reason = A.LoadMap()
    if not ok then return false, "map_fail" end
    local keyword = name:lower()
    if keyword == "meet" or keyword == "sraz" then
        local m = A.social and A.social.meets[1]
        if not m then return false, "no_meet" end
        return A.map.Navigate({kind = "point", map = m.mapId, x = m.x, y = m.y, label = m.label ~= "" and m.label or A.L("meetDefault"), source = {view = "people"}})
    elseif keyword == "ping" then
        local g = A.LivePings()[1]
        if not g then return false, "no_ping" end
        return A.map.Navigate({kind = "point", map = g.map, x = g.x, y = g.y, label = g.label ~= "" and g.label or A.L("pingTitle"), source = {view = "people"}})
    end
    local peer = A.LivePeer(name)
    if not peer then return false, "unknown_player" end
    return A.map.Navigate({kind = "player", name = peer.name})
end
--- source (optional): where the goal comes from, so that a click on the arrow can open it: {tab = "db", kind, id} / {tab = "gather" | "services" |
--- "instances", key} / {tab = "plan", name} (a tab of the World page) or {view = "people"} (a page of the window).
function A.NavigateToPoint(label, map, x, y, source)
    local s = settings()
    if not s or s.mapPins ~= true then return false, "map_off" end
    if not A.LoadMap() then return false, "map_fail" end
    return A.map.Navigate({kind = "point", map = map, x = x, y = y, label = label, source = type(source) == "table" and source or nil})
end
--- /etally arrow: shows or hides the navigation arrow (the navigation goes on).
function A.ToggleArrow()
    if not A.map or not A.map.SetArrowShown then return false end
    local on = not A.map.ArrowShown()
    A.map.SetArrowShown(on)
    A.Print(A.L(on and "arrowShown" or "arrowHidden"))
    return on
end
function A.StopNavigation() if A.map then A.map.Stop() end end

-- ---------------------------------------------------------------- keybindings (Bindings.xml)
BINDING_HEADER_EVERTALLY = "Evertally"
BINDING_NAME_EVERTALLY_PING = "Ping at the map cursor / my position"
BINDING_NAME_EVERTALLY_STOPNAV = "Stop navigation"
--- With the world map open and the cursor on it the ping lands there, otherwise where you stand.
--- The place under the cursor while the world map is open: map id, x, y (0..1), or nil.
function A.MapCursorPosition()
    if not WorldMapFrame or A.Call(WorldMapFrame.IsShown, WorldMapFrame) ~= true then return nil end
    local cx, cy = A.Call(WorldMapFrame.GetNormalizedCursorPosition, WorldMapFrame)
    local id = A.Call(WorldMapFrame.GetMapID, WorldMapFrame)
    if cx and cy and id and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then return id, cx, cy end
    return nil
end
function Evertally_Ping()
    if not A.db then return end
    local map, x, y
    if WorldMapFrame and A.Call(WorldMapFrame.IsShown, WorldMapFrame) == true then
        local cx, cy = A.Call(WorldMapFrame.GetNormalizedCursorPosition, WorldMapFrame)
        local id = A.Call(WorldMapFrame.GetMapID, WorldMapFrame)
        if cx and cy and id and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then map, x, y = id, cx, cy end
    end
    local ok, err = A.SendPing("", map, x, y)
    A.Print(ok and A.L("pingSent") or A.L("pingErr_" .. tostring(err)))
end
function Evertally_StopNav() A.StopNavigation() end

-- ---------------------------------------------------------------- housekeeping
A.On("PLAYER_LOGIN", function()
    local s = A.db.settings
    if s.liveParty == nil then s.liveParty = false end
    if s.liveGuild == nil then s.liveGuild = false end
    if s.liveFriends == nil then s.liveFriends = false end
    if s.mapPins == nil then s.mapPins = false end
    if s.liveWeb == nil then s.liveWeb = false end
    if s.language == "cs" then
        BINDING_NAME_EVERTALLY_PING = "Ping na kurzoru mapy / na mé poloze"
        BINDING_NAME_EVERTALLY_STOPNAV = "Zrušit navigaci"
    end
    if s.mapPins and C_Timer and type(C_Timer.After) == "function" then C_Timer.After(2, function() A.LoadMap() end) end
end)
if C_Timer and type(C_Timer.NewTicker) == "function" then C_Timer.NewTicker(2, function() local ok = pcall(A.LiveTick); if not ok then A.errors.live_tick = (A.errors.live_tick or 0) + 1 end end) end

-- ---------------------------------------------------------------- texts
local text = {
    en = {
        liveSection = "Live position and map", liveParty = "Share my live position with party / raid", liveGuild = "Share my live position with my guild",
        liveFriends = "Share my live position with my friends (friends list, both sides need the add-on)",
        mapPins = "Map and minimap: show people, meets, pings and navigation",
        liveWeb = "Live position on the website (draws a small marker in the screen corner)",
        liveHint = "Live position sends where you are (zone, spot, class) to the group or guild while you move, to players with this addon. It is never uploaded or saved. The map option loads a second add-on (Evertally_Map) that adds pins to the world map and minimap.",
        liveOnParty = "Live position: sharing with your party / raid. Turn it off in Settings.", liveOnGuild = "Live position: sharing with your guild. Turn it off in Settings.",
        liveOnFriends = "Live position: sharing with your friends. Turn it off in Settings.",
        mapOn = "Map and minimap: on.", mapOff = "Map and minimap: pins removed. Reload the UI to unload the map library.", mapFail = "Map and minimap could not be loaded (is the Evertally_Map folder installed?).",
        livePill = "LIVE", agoNow = "just now", agoMinutes = "%d min ago", meetDefault = "Meet", pingTitle = "Ping", navYou = "you",
        terrainMapOff = "Turn on Map and minimap in the Evertally settings and start navigation first.", terrainStarted = "Journey handed to Shortest Path Forever for terrain guidance.", terrainErr_missing = "Shortest Path Forever is not available.", terrainErr_no_target = "Start Evertally navigation to a place first.", terrainErr_refused = "Shortest Path Forever could not start the journey; check its journey setting and combat state.",
        pingChat = "%s pinged the map: %s (Evertally > People).", pingSent = "Ping sent.", pingErr_no_channel = "Join a group or guild first.", pingErr_no_position = "No map position here.", pingErr_queue_full = "Too many messages are waiting.",
        navMode_walk = "Walk", navMode_flight = "Flight", navMode_boat = "Boat", navMode_zeppelin = "Zeppelin", navMode_airship = "Airship", navMode_lift = "Lift", navMode_tram = "Tram", navMode_portal = "Portal", navMode_passage = "Passage",
        navWalk = "Walk to %s (%s)", navFly = "Fly: %s to %s (%s)", navShip = "%s: %s to %s (wait ~%s)", navOther = "%s: %s to %s", navThen = "Then:", navTotal = "Total ~%s",
        navLost = "No position for this target.", navNoMap = "That place is not on a map I know.", navNoPosition = "Your position is unknown here.", navArrived = "You are there.", navDirect = "Straight line: %s", navNoRoute = "No route known.",
        navHint = "Right-click to stop.", navEstimate = "Estimate.", terrainButton = "Terrain", terrainOn = "Terrain: on",
        navErr_no_target = "Type a name, \"meet\" or \"ping\".", navErr_map_off = "Turn on \"Map and minimap\" in Settings first.", navErr_map_fail = "The map add-on did not load.", navErr_unknown_player = "No live position from that player. They must share it with you.",
        navErr_no_meet = "No meet received yet.", navErr_no_ping = "No ping yet.", navErr_unknown_map = "That place is not on a map I know.", navStarted = "Navigating to %s. Right-click the arrow to stop.", navStopped = "Navigation stopped.",
        socialTab_live = "People", liveNone = "Nobody shares a position with you right now.", liveRowSub = "%s  ·  %s", socialPing = "Ping here", socialStopNav = "Stop navigation", liveOffNote = "Your live position is off (Settings).",
        meetNavigate = "Navigate", pingNavigate = "Navigate",
    },
    cs = {
        liveSection = "Živá poloha a mapa", liveParty = "Sdílet mou živou polohu s partou / raidem", liveGuild = "Sdílet mou živou polohu s cechem",
        liveFriends = "Sdílet mou živou polohu s přáteli (seznam přátel, oba musíte mít addon)",
        mapPins = "Mapa a minimapa: ukazovat lidi, srazy, pingy a navigaci",
        liveWeb = "Živá poloha na webu (kreslí malý bod v rohu obrazovky)",
        liveHint = "Živá poloha posílá, kde jsi (zóna, místo, classa), partě nebo cechu, dokud se hýbeš, hráčům s tímto addonem. Nikdy se nenahrává ani neukládá. Volba mapy načte druhý addon (Evertally_Map), který přidá body na světovou mapu a minimapu.",
        liveOnParty = "Živá poloha: sdílíš s partou / raidem. Vypneš v Nastavení.", liveOnGuild = "Živá poloha: sdílíš s cechem. Vypneš v Nastavení.",
        liveOnFriends = "Živá poloha: sdílíš s přáteli. Vypneš v Nastavení.",
        mapOn = "Mapa a minimapa: zapnuto.", mapOff = "Mapa a minimapa: body odstraněny. Knihovnu mapy uvolníš po /reload.", mapFail = "Mapu a minimapu se nepodařilo načíst (je nainstalovaná složka Evertally_Map?).",
        livePill = "ŽIVĚ", agoNow = "právě teď", agoMinutes = "před %d min", meetDefault = "Sraz", pingTitle = "Ping", navYou = "ty",
        terrainMapOff = "Nejdřív zapni Mapu a minimapu v nastavení Evertally a navigaci k cíli.", terrainStarted = "Cíl předán Shortest Path Forever pro navigaci po terénu.", terrainErr_missing = "Addon Shortest Path Forever není dostupný.", terrainErr_no_target = "Nejdřív spusť navigaci Evertally k cíli.", terrainErr_refused = "Shortest Path Forever cestu nespustil; zkontroluj jeho nastavení navigace a boj.",
        pingChat = "%s pingl mapu: %s (Evertally > Lidé).", pingSent = "Ping odeslán.", pingErr_no_channel = "Nejdřív vstup do skupiny nebo cechu.", pingErr_no_position = "Tady není poloha na mapě.", pingErr_queue_full = "Čeká příliš mnoho zpráv.",
        navMode_walk = "Pěšky", navMode_flight = "Let", navMode_boat = "Loď", navMode_zeppelin = "Zeppelin", navMode_airship = "Vzducholoď", navMode_lift = "Výtah", navMode_tram = "Tram", navMode_portal = "Portál", navMode_passage = "Průchod",
        navWalk = "Jdi k: %s (%s)", navFly = "Let: %s do %s (%s)", navShip = "%s: %s do %s (čekání ~%s)", navOther = "%s: %s do %s", navThen = "Pak:", navTotal = "Celkem ~%s",
        navLost = "Pro tento cíl není poloha.", navNoMap = "To místo není na mapě, kterou znám.", navNoPosition = "Tvoje poloha tady není známá.", navArrived = "Jsi na místě.", navDirect = "Vzdušnou čarou: %s", navNoRoute = "Cesta není známá.",
        navHint = "Pravým tlačítkem zrušíš.", navEstimate = "Odhad.", terrainButton = "Terén", terrainOn = "Terén: zap.",
        navErr_no_target = "Napiš jméno, \"meet\" nebo \"ping\".", navErr_map_off = "Nejdřív zapni \"Mapa a minimapa\" v Nastavení.", navErr_map_fail = "Addon mapy se nenačetl.", navErr_unknown_player = "Ten hráč neposílá živou polohu. Musí ji s tebou sdílet.",
        navErr_no_meet = "Zatím žádný sraz.", navErr_no_ping = "Zatím žádný ping.", navErr_unknown_map = "To místo není na mapě, kterou znám.", navStarted = "Naviguji k: %s. Pravým tlačítkem na šipku zrušíš.", navStopped = "Navigace zrušena.",
        socialTab_live = "Lidé", liveNone = "Nikdo s tebou teď nesdílí polohu.", liveRowSub = "%s  ·  %s", socialPing = "Ping sem", socialStopNav = "Zrušit navigaci", liveOffNote = "Tvoje živá poloha je vypnutá (Nastavení).",
        meetNavigate = "Navigovat", pingNavigate = "Navigovat",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end
