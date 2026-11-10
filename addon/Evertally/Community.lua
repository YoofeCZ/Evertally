local _, A = ...

-- Public website facts are a separate, read-only cache. They never become
-- observations, outgoing peer summaries or records in Evertally_Export.
local MAX_BYTES, MAX_ENTITIES, MAX_SAMPLE, WEEK = 49152, 150, 10000, 604800
A.COMMUNITY_MAX_BYTES, A.COMMUNITY_MAX_ENTITIES = MAX_BYTES, MAX_ENTITIES

local rootKeys = {schemaVersion=true,kind=true,scope=true,generatedAt=true,expiresAt=true,game=true,provenance=true,entities=true}
local entityKeys = {kind=true,id=true,name=true,count=true,lastSeen=true,mapId=true,x=true,y=true}
local provenanceKeys = {source=true,countingUnit=true,truncated=true,observationCount=true,entityCount=true}
local kinds = {quest=true,npc=true,item=true}

local function strict(value, keys)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do if type(key) ~= "string" or not keys[key] then return false end end
    return true
end
local function integer(value, low, high)
    return type(value) == "number" and value == value and value >= low and value <= high and value == math.floor(value)
end
local function coordinate(value)
    return type(value) == "number" and value == value and value >= 0 and value <= 1
end
local function text(value)
    if type(value) ~= "string" or #value < 1 or #value > 160 or value:find("[%z\1-\31\127|]") or not value:find("%S") then return false end
    -- Lua 5.1 has no utf8 library. Reject truncated/overlong sequences, surrogate
    -- codepoints and bytes outside Unicode before saving or displaying a name.
    local index = 1
    while index <= #value do
        local byte = value:byte(index)
        local length = byte < 128 and 1 or byte >= 194 and byte <= 223 and 2 or byte >= 224 and byte <= 239 and 3 or byte >= 240 and byte <= 244 and 4
        if not length or index + length - 1 > #value then return false end
        for offset = 1, length - 1 do
            local continuation = value:byte(index + offset)
            if continuation < 128 or continuation > 191 then return false end
        end
        local second = value:byte(index + 1)
        if (byte == 224 and second < 160) or (byte == 237 and second > 159)
            or (byte == 240 and second < 144) or (byte == 244 and second > 143) then return false end
        index = index + length
    end
    return true
end

local function validate(snapshot, allowExpired)
    if not strict(snapshot, rootKeys) or snapshot.schemaVersion ~= 1 or snapshot.kind ~= "evertally-community" or snapshot.scope ~= "world_facts" then return nil, "communityInvalid" end
    if not strict(snapshot.game, {product=true}) or snapshot.game.product ~= "forever" then return nil, "communityInvalid" end
    local now = A.Now()
    if now <= 0 then return nil, "communityClock" end
    if not integer(snapshot.generatedAt, 0, now + 300) or not integer(snapshot.expiresAt, 0, 253402300799)
        or snapshot.expiresAt <= snapshot.generatedAt or snapshot.expiresAt > snapshot.generatedAt + WEEK then return nil, "communityInvalid" end
    if not allowExpired and snapshot.expiresAt <= now then return nil, "communityExpiredImport" end
    local provenance = snapshot.provenance
    if not strict(provenance, provenanceKeys) or provenance.source ~= "community" or provenance.countingUnit ~= "observations"
        or type(provenance.truncated) ~= "boolean" or not integer(provenance.observationCount, 0, MAX_SAMPLE)
        or not integer(provenance.entityCount, 0, MAX_SAMPLE) then return nil, "communityInvalid" end
    if type(snapshot.entities) ~= "table" then return nil, "communityInvalid" end
    local length, highest = 0, 0
    for key in pairs(snapshot.entities) do
        if not integer(key, 1, MAX_ENTITIES) then return nil, "communityInvalid" end
        length, highest = length + 1, math.max(highest, key)
    end
    if length ~= highest or length > provenance.entityCount then return nil, "communityInvalid" end
    local entities, seen, observations = {}, {}, 0
    for index = 1, length do
        local entry = snapshot.entities[index]
        if not strict(entry, entityKeys) or not kinds[entry.kind] or not integer(entry.id, 1, 2147483647)
            or not text(entry.name) or not integer(entry.count, 1, MAX_SAMPLE) or not integer(entry.lastSeen, 0, snapshot.generatedAt + 300) then return nil, "communityInvalid" end
        if entry.mapId ~= nil and not integer(entry.mapId, 1, 2147483647) then return nil, "communityInvalid" end
        if entry.x ~= nil or entry.y ~= nil then
            if not entry.mapId or not coordinate(entry.x) or not coordinate(entry.y) then return nil, "communityInvalid" end
        end
        local key = entry.kind .. ":" .. entry.id
        if seen[key] then return nil, "communityInvalid" end
        seen[key] = true
        observations = observations + entry.count
        entities[index] = {kind=entry.kind,id=entry.id,name=entry.name,count=entry.count,lastSeen=entry.lastSeen,mapId=entry.mapId,x=entry.x,y=entry.y}
    end
    if observations > provenance.observationCount or provenance.entityCount > provenance.observationCount
        or (not provenance.truncated and provenance.entityCount ~= length) then return nil, "communityInvalid" end
    return {schemaVersion=1,kind="evertally-community",scope="world_facts",generatedAt=snapshot.generatedAt,expiresAt=snapshot.expiresAt,
        game={product="forever"},provenance={source="community",countingUnit="observations",truncated=provenance.truncated,
        observationCount=provenance.observationCount,entityCount=provenance.entityCount},entities=entities}
end

function A.ValidateCommunity(snapshot, allowExpired)
    local ok, value, err = pcall(validate, snapshot, allowExpired == true)
    if not ok then return nil, "communityInvalid" end
    return value, err
end

function A.ImportCommunity(encoded)
    local snapshot = A.Decode(encoded, MAX_BYTES)
    if not snapshot then return nil, "communityInvalid" end
    local clean, err = A.ValidateCommunity(snapshot)
    if not clean then return nil, err end
    if type(A.peerDB) ~= "table" then return nil, "communityInvalid" end
    A.peerDB.community = clean
    A.Changed()
    return true, #clean.entities
end

function A.GetCommunity()
    local snapshot = A.peerDB and A.peerDB.community
    if snapshot == nil then return nil end
    local clean, err = A.ValidateCommunity(snapshot, true)
    if not clean then return nil, err end
    return clean, clean.expiresAt <= A.Now()
end

function A.ClearCommunity()
    if A.peerDB then A.peerDB.community = nil end
    A.Changed()
end

local upper = {['Á']='á',['Č']='č',['Ď']='ď',['É']='é',['Ě']='ě',['Í']='í',['Ň']='ň',['Ó']='ó',['Ř']='ř',['Š']='š',['Ť']='ť',['Ú']='ú',['Ů']='ů',['Ý']='ý',['Ž']='ž'}
local function fold(value)
    -- C-library lower() can alter leading UTF-8 bytes under a Windows locale.
    value = value:gsub("[A-Z]", function(letter) return string.char(letter:byte() + 32) end)
    for from, to in pairs(upper) do value = value:gsub(from, to) end
    return value
end
function A.CommunityEntries(kind, query)
    local snapshot = A.GetCommunity()
    if not snapshot then return {} end
    query = fold(A.Text(query, 200) or "")
    local result = {}
    for _, entry in ipairs(snapshot.entities) do
        if (not kind or kind == "" or entry.kind == kind) and (query == "" or fold(entry.name):find(query, 1, true) or tostring(entry.id):find(query, 1, true)) then
            result[#result + 1] = entry
        end
    end
    return result
end
