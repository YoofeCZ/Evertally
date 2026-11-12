local _, A = ...
-- Own game contacts only. Optical v4 carries current contact tokens and their roster hash directly;
-- consent-scoped export metadata supports legacy bridges. Received peer observations never become relationship evidence.
local MAX_ENTRIES = 100

local function trim(value)
    value = A.Text(value, 180)
    if not value then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
end
local function lowerAscii(value)
    return (value:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end
local function bytesLess(a, b)
    for i = 1, math.min(#a, #b) do
        local ac, bc = a:byte(i), b:byte(i)
        if ac ~= bc then return ac < bc end
    end
    return #a < #b
end
local function realmKey(value) return lowerAscii(value:gsub("%s", "")) end
local function identity(name, realm, fallback)
    name = trim(name)
    if not name then return nil end
    local base, suffix = name:match("^([^-]+)%-(.+)$")
    if base then name, realm = trim(base), trim(suffix) end
    realm = trim(realm) or fallback
    if not name or not realm or #name > 100 or #realm > 100 then return nil end
    if name:find("[%z\1-\31\127]") or realm:find("[%z\1-\31\127]") then return nil end
    return name, realm, lowerAscii(name) .. "\0" .. realmKey(realm)
end
local function adler(text)
    local a, b = 1, 0
    for i = 1, #text do a = (a + text:byte(i)) % 65521; b = (b + a) % 65521 end
    return b * 65536 + a
end
local function consent()
    local s = A.db and A.db.settings
    return s and s.web == true and type(s.scopes) == "table" and s.scopes.own_character == true and s.scopes.own_track == true and s
end
local function friendCount(fn, maximum)
    return math.floor(A.Number(A.Call(fn), 0, maximum) or 0)
end

function A.ConnectionsSnapshot()
    local out, text = {}, {}
    local s = consent()
    if not s then return {key = 1, entries = out} end
    local me = A.Character()
    local fallback = trim(me and me.realm) or trim(A.Call(GetRealmName))
    if not fallback then return {key = 1, entries = out} end
    local _, _, selfKey = identity(me and me.name or A.Call(UnitName, "player"), me and me.realm, fallback)
    local known = {}
    local function add(name, realm, kind)
        local cleanName, cleanRealm, key = identity(name, realm, fallback)
        if not key or key == selfKey then return end
        key = kind .. "\0" .. key
        local previous = known[key]
        -- Keep deterministic spelling if adapters return the same identity with different case.
        local spelling = cleanName .. "\0" .. cleanRealm
        if not previous or bytesLess(spelling, previous.name .. "\0" .. previous.realm) then
            known[key] = {name = cleanName, realm = cleanRealm, kind = kind, sortKey = key}
        end
    end
    if s.liveFriends == true then
        local list = rawget(_G, "C_FriendList")
        if type(list) == "table" and type(list.GetNumFriends) == "function" and type(list.GetFriendInfoByIndex) == "function" then
            for i = 1, friendCount(list.GetNumFriends, 500) do
                local info = A.Call(list.GetFriendInfoByIndex, i)
                if type(info) == "table" then add(A.Field(info, "name"), A.Field(info, "realmName"), "friend") end
            end
        elseif type(GetNumFriends) == "function" and type(GetFriendInfo) == "function" then
            for i = 1, friendCount(GetNumFriends, 500) do
                local name = A.Call(GetFriendInfo, i)
                add(name, nil, "friend")
            end
        end
        local battle = rawget(_G, "C_BattleNet")
        if type(battle) == "table" and type(battle.GetFriendAccountInfo) == "function" and type(BNGetNumFriends) == "function" then
            for i = 1, friendCount(BNGetNumFriends, 1000) do
                local account = A.Call(battle.GetFriendAccountInfo, i)
                local game = A.Field(account, "gameAccountInfo")
                if type(game) == "table" and A.Field(game, "clientProgram") == "WoW" then add(A.Field(game, "characterName"), A.Field(game, "realmName"), "friend") end
            end
        end
    end
    if s.liveParty == true then
        local raid = A.Call(IsInRaid) == true
        local count = raid and friendCount(GetNumGroupMembers, 40) or 4
        for i = 1, count do
            local unit = (raid and "raid" or "party") .. i
            if A.Call(UnitExists, unit) == true then
                local name, realm = A.Call(UnitFullName, unit)
                if not trim(name) then name, realm = A.Call(UnitName, unit) end
                add(name, realm, "group")
            end
        end
    end
    for _, entry in pairs(known) do out[#out + 1] = entry end
    -- Keep the current party/raid represented even with a large friends list.
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return a.kind == "group" end
        return bytesLess(a.sortKey, b.sortKey)
    end)
    while #out > MAX_ENTRIES do out[#out] = nil end
    table.sort(out, function(a, b) return bytesLess(a.sortKey, b.sortKey) end)
    for _, entry in ipairs(out) do
        text[#text + 1] = entry.kind .. "\0" .. lowerAscii(entry.name) .. "\0" .. realmKey(entry.realm) .. "\n"
        entry.sortKey = nil
    end
    return {key = adler(table.concat(text)), entries = out}
end

function A.RefreshConnections()
    local store = A.ExportStore and A.ExportStore()
    if not store then return end
    if consent() then store.connections = A.ConnectionsSnapshot() else store.connections = nil end
end

-- Compact live transport: hashed character name + realm, never BattleTags or private notes.
-- Unlike the exported roster, these tokens are encoded directly in the current optical frame.
function A.ConnectionsTokensSnapshot()
    local raw=A.ConnectionsSnapshot();local tokens,lines,seen={},{},{}
    for _,entry in ipairs(raw.entries) do
        local key=adler(lowerAscii(entry.name).."\0"..realmKey(entry.realm))
        local line=entry.kind.."\0"..string.format("%.0f",key).."\n"
        if not seen[line] then seen[line]=true;lines[#lines+1]=line;tokens[#tokens+1]={key=key,kind=entry.kind,line=line} end
    end
    table.sort(tokens,function(a,b)return bytesLess(a.line,b.line) end)
    lines={}
    for _,token in ipairs(tokens) do lines[#lines+1]=token.line;token.line=nil end
    return {key=adler(table.concat(lines)),tokens=tokens}
end

for _, event in ipairs({"PLAYER_LOGIN", "FRIENDLIST_UPDATE", "GROUP_ROSTER_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED"}) do
    A.On(event, A.RefreshConnections)
end
