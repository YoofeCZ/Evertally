local _, M = ...
local A = _G.Evertally
-- The database tab: search NPCs, quests and items in QuestieDB (the add-on you already have installed; nothing is copied here) and
-- show where they are on the map. QuestieDB is read only through its public library object (LibQuestieDB): entity.GetAllIds,
-- entity.GetAll and its zone table, the same way Shortest Path Forever reads it. Every part is checked before it is used, so a
-- different version of QuestieDB makes this tab say so instead of failing.
local CONTRACT = 2
local KINDS = {"npc", "quest", "item", "object"}
local ENTITY = {npc = "Npc", quest = "Quest", item = "Item", object = "Object"}
local OPTIONAL = {object = true}   -- (a QuestieDB without objects still gives the rest)
local FIELDS = {
    npc = {"name", "minLevel", "maxLevel", "spawns", "subName", "questStarts", "questEnds"},
    quest = {"name", "questLevel", "requiredLevel", "startedBy", "finishedBy", "objectivesText", "zoneOrSort", "preQuestSingle", "preQuestGroup", "nextQuestInChain",
        "objectives", "sourceItemId"},
    item = {"name", "npcDrops", "questRewards", "objectDrops", "vendors", "startQuest", "itemLevel", "requiredLevel"},
    object = {"name", "spawns", "questStarts", "questEnds"},
}
local CHUNK, MAX_RESULTS, MAX_NAME_INDEX = 1500, 400, 60000

local text = {
    en = {
        worldDb_npc = "NPCs", worldDb_quest = "Quests", worldDb_item = "Items", worldDb_object = "Objects", worldDbSearch = "Search",
        worldDbCount = "%d entries. Type to narrow them down.", worldDbKill = "Kill", worldDbUse = "Use", worldDbCollect = "Collect", worldDbZone = "Zone",
        worldDbPrereq = "Do first", worldDbNext = "Next in the chain", worldDbGives = "Gives you", worldDbSoldBy = "Sold by", worldDbFromObjects = "Found in",
        worldDbStartsQuest = "Starts the quest", worldDbQuestStarts = "Gives the quests", worldDbQuestEnds = "Takes in the quests", worldDbRequires = "Needs level %s",
        worldDbUnknown = "Not in the database", worldDbUnknownSub = "This record has no entry there (a quest added by this server is often missing).",
        worldDbOpen = "Open in the database", worldDbItemLevel = "Item level %s", worldDbSells = "Sells", worldDbRewardItems = "Reward",
        worldDbMissing = "QuestieDB is not installed or is not the version this tab was written for.",
        worldDbIndexing = "Reading the database… %d %%", worldDbNone = "Nothing found.", worldDbHint = "Type at least two letters.",
        worldDbShow = "Show on map", worldDbGo = "Navigate to the nearest", worldDbBack = "Back to the list",
        worldDbLevel = "Level %s", worldDbWhere = "Where", worldDbNoPlace = "No place is known.", worldDbStarts = "Starts at", worldDbEnds = "Ends at",
        worldDbObjectives = "What to do", worldDbDrops = "Dropped by", worldDbRewards = "Reward of", worldDbMore = "… and %d more", worldDbNoMapFor = "That place is not on a map I can show.",
    },
    cs = {
        worldDb_npc = "NPC", worldDb_quest = "Questy", worldDb_item = "Itemy", worldDb_object = "Objekty", worldDbSearch = "Hledat",
        worldDbCount = "Záznamů: %d. Piš a zúžíš je.", worldDbKill = "Zabít", worldDbUse = "Použít", worldDbCollect = "Sebrat", worldDbZone = "Oblast",
        worldDbPrereq = "Nejdřív udělej", worldDbNext = "Další v řetězu", worldDbGives = "Dá ti", worldDbSoldBy = "Prodává", worldDbFromObjects = "Najdeš v",
        worldDbStartsQuest = "Spouští quest", worldDbQuestStarts = "Dává questy", worldDbQuestEnds = "Přijímá questy", worldDbRequires = "Potřebuje úroveň %s",
        worldDbUnknown = "V databázi není", worldDbUnknownSub = "Tenhle záznam tam nemá položku (quest přidaný tímto serverem tam často chybí).",
        worldDbOpen = "Otevřít v databázi", worldDbItemLevel = "Úroveň předmětu %s", worldDbSells = "Prodává", worldDbRewardItems = "Odměna",
        worldDbMissing = "QuestieDB není nainstalovaná, nebo není ve verzi, pro kterou je tahle karta napsaná.",
        worldDbIndexing = "Čtu databázi… %d %%", worldDbNone = "Nic nenalezeno.", worldDbHint = "Napiš aspoň dvě písmena.",
        worldDbShow = "Ukázat na mapě", worldDbGo = "Navigovat k nejbližšímu", worldDbBack = "Zpět na seznam",
        worldDbLevel = "Úroveň %s", worldDbWhere = "Kde", worldDbNoPlace = "Žádné místo není známé.", worldDbStarts = "Začíná u", worldDbEnds = "Končí u",
        worldDbObjectives = "Co udělat", worldDbDrops = "Padá z", worldDbRewards = "Odměna za", worldDbMore = "… a dalších %d", worldDbNoMapFor = "To místo není na mapě, kterou umím ukázat.",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local Db = {kinds = KINDS, fields = FIELDS, index = {}}
M.Db = Db

-- ---------------------------------------------------------------- QuestieDB, checked
local function zoneTable(source)
    local chunk = type(source) == "string" and loadstring(source)
    if not chunk then return nil end
    setfenv(chunk, {})
    local ok, value = pcall(chunk)
    return ok and type(value) == "table" and value or nil
end

--- {lib, area, override} or nil and why ("missing" or "failed").
function Db.Open()
    local lib = rawget(_G, "LibQuestieDB")
    if lib == nil then return nil, "missing" end
    if type(lib) ~= "table" or type(lib.RequireContract) ~= "function" then return nil, "failed" end
    local called, fits = pcall(lib.RequireContract, CONTRACT)
    if not (called and fits) then return nil, "failed" end
    local has = {}
    for _, kind in ipairs(KINDS) do
        local entity = lib[ENTITY[kind]]
        local fine = type(entity) == "table" and type(entity.GetAll) == "function" and type(entity.GetAllIds) == "function"
        if not fine and not OPTIONAL[kind] then return nil, "failed" end
        has[kind] = fine
    end
    local area, override = {}, {}
    local support = lib.Support
    if type(support) == "table" and type(support.Get) == "function" then
        local answered, zones = pcall(support.Get, "ZoneDB")
        local private = answered and type(zones) == "table" and zones.private or nil
        if type(private) == "table" then
            area = zoneTable(private.areaIdToUiMapId) or area
            override = zoneTable(private.areaIdToUiMapIdOverride) or override
        end
    end
    return {lib = lib, area = area, override = override, has = has}
end

--- The map a QuestieDB area id is shown on, nil when it has none (the override can say 0: not shown).
function Db.MapOf(db, areaId)
    if type(areaId) ~= "number" then return nil end
    local map = db.override[areaId]
    if map == nil then map = db.area[areaId] end
    if type(map) ~= "number" or map <= 0 then return nil end
    return map
end

--- The named fields of one entity as {name = value}, nil when it is unknown.
function Db.Get(db, kind, id)
    local entity = db.lib[ENTITY[kind]]
    local ok, values = pcall(entity.GetAll, id, FIELDS[kind])
    if not ok or type(values) ~= "table" then return nil end
    local out = {}
    for i, key in ipairs(FIELDS[kind]) do out[key] = values[i] end
    return out
end

--- Where an NPC stands: {{map, x, y}, ...} on maps the window can show (QuestieDB coordinates are 0..100).
function Db.Spots(db, spawns)
    local out = {}
    if type(spawns) ~= "table" then return out end
    for area, points in pairs(spawns) do
        local map = Db.MapOf(db, area)
        if map and type(points) == "table" then
            for _, spot in ipairs(points) do
                local x, y = spot[1], spot[2]
                if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then out[#out + 1] = {map = map, x = x / 100, y = y / 100} end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------- the name index, built a little at a time
--- Starts reading the names of one kind (a slice per call of Db.Step); safe to call again.
function Db.StartIndex(db, kind)
    local entry = Db.index[kind]
    if entry then return entry end
    local ok, ids = pcall(db.lib[ENTITY[kind]].GetAllIds)
    entry = {ids = ok and type(ids) == "table" and ids or {}, at = 1, names = {}, found = {}}
    if #entry.ids > MAX_NAME_INDEX then entry.ids = {unpack(entry.ids, 1, MAX_NAME_INDEX)} end
    Db.index[kind] = entry
    return entry
end
--- Reads the next slice of names, at most CHUNK of them and at most `budgetMs` of time when the game can measure it, so the
--- window does not stutter. Returns whether the whole kind has been read, and how far it is (0..1).
function Db.Step(db, kind, budgetMs)
    local entry = Db.StartIndex(db, kind)
    local entity = db.lib[ENTITY[kind]]
    local last = math.min(#entry.ids, entry.at + CHUNK - 1)
    local started = budgetMs and type(debugprofilestop) == "function" and debugprofilestop() or nil
    for i = entry.at, last do
        local id = entry.ids[i]
        local ok, values = pcall(entity.GetAll, id, {"name"})
        local name = ok and type(values) == "table" and values[1] or nil
        if type(name) == "string" and name ~= "" then entry.found[#entry.found + 1] = id; entry.names[#entry.found] = name:lower() end
        if started and i % 25 == 0 and debugprofilestop() - started > budgetMs then last = i; break end
    end
    entry.at = last + 1
    return entry.at > #entry.ids, #entry.ids == 0 and 1 or math.min(1, (entry.at - 1) / #entry.ids)
end
function Db.Reset() Db.index = {}; Db.scan = nil end

-- ---------------------------------------------------------------- services on the map: trainers, vendors, innkeepers
-- The NPCs with these flags (Classic NPC flag bits) that this character can use, read from QuestieDB a slice at a time into
-- Db.scan.lists = {trainer = {{name, map, x, y}}, vendor = {...}, inn = {...}}; the map tab draws the ones on the shown map.
Db.SERVICE_FLAGS = {trainer = 16, vendor = 128, inn = 65536}
local SERVICE_FIELDS = {"name", "spawns", "friendlyToFaction", "npcFlags", "subName"}
local function hasFlag(value, bit)
    return type(value) == "number" and math.floor(value / bit) % 2 == 1
end

--- Reads the next slice of NPCs (at most CHUNK, at most `budgetMs`); returns whether all of them have been read, and how far (0..1).
function Db.ScanServices(db, budgetMs, side)
    if not Db.scan then
        local ok, ids = pcall(db.lib.Npc.GetAllIds)
        Db.scan = {ids = ok and type(ids) == "table" and ids or {}, at = 1, lists = {trainer = {}, vendor = {}, inn = {}}}
    end
    local scan = Db.scan
    local last = math.min(#scan.ids, scan.at + CHUNK - 1)
    local started = budgetMs and type(debugprofilestop) == "function" and debugprofilestop() or nil
    for i = scan.at, last do
        local ok, values = pcall(db.lib.Npc.GetAll, scan.ids[i], SERVICE_FIELDS)
        if ok and type(values) == "table" then
            local name, spawns, friendly, flags = values[1], values[2], values[3], values[4]
            if type(name) == "string" and type(flags) == "number" and (friendly == "AH" or friendly == side) then
                for kind, bit in pairs(Db.SERVICE_FLAGS) do
                    if hasFlag(flags, bit) then
                        for _, spot in ipairs(Db.Spots(db, spawns)) do
                            local list = scan.lists[kind]
                            list[#list + 1] = {name = name, title = type(values[5]) == "string" and values[5] ~= "" and values[5] or nil, map = spot.map, x = spot.x, y = spot.y}
                        end
                    end
                end
            end
        end
        if started and i % 25 == 0 and debugprofilestop() - started > budgetMs then last = i; break end
    end
    scan.at = last + 1
    scan.done = scan.at > #scan.ids
    return scan.done, #scan.ids == 0 and 1 or math.min(1, (scan.at - 1) / #scan.ids)
end

--- Every entity of a kind whose name has been read, by name (the list the window shows before anything is typed). While the names are still
--- being read it is what has been read so far, in the order of the ids; the sorted list is made once the reading is done.
function Db.Sorted(kind)
    local entry = Db.index[kind]
    if not entry then return {} end
    if entry.at <= #entry.ids then return entry.found end
    if entry.sorted and entry.sortedSize == #entry.found then return entry.sorted end
    local order = {}
    for i = 1, #entry.found do order[i] = i end
    table.sort(order, function(a, b) local x, y = entry.names[a], entry.names[b]; if x ~= y then return x < y end return entry.found[a] < entry.found[b] end)
    local out = {}
    for i, at in ipairs(order) do out[i] = entry.found[at] end
    entry.sorted, entry.sortedSize = out, #entry.found
    return out
end

--- Entities whose name contains the query (case-insensitive), the ones that start with it first. Works on what is read so far.
function Db.Search(db, kind, query, limit)
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local entry = Db.index[kind]
    if #query < 2 or not entry then return {} end
    local starts, contains = {}, {}
    for i, name in ipairs(entry.names) do
        local at = name:find(query, 1, true)
        if at == 1 then starts[#starts + 1] = entry.found[i] elseif at then contains[#contains + 1] = entry.found[i] end
        if #starts >= (limit or MAX_RESULTS) then break end
    end
    local out = {}
    for _, id in ipairs(starts) do if #out < (limit or MAX_RESULTS) then out[#out + 1] = id end end
    for _, id in ipairs(contains) do if #out < (limit or MAX_RESULTS) then out[#out + 1] = id end end
    return out
end
