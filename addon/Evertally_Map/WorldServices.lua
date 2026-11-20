local _, M = ...
local A = _G.Evertally
-- Trainers and merchants picked one kind at a time: OpenMap draws all vendors or all profession trainers (its Townsfolk section); here the
-- player ticks exactly "Herbalism trainers" or "Alchemy Supplies" and only those are drawn. The kinds are the NPCs' titles from QuestieDB
-- ("Journeyman Alchemist", "Expert Alchemist" and "Alchemy Trainer" are one: "Alchemy trainers"), read by the same scan the service layers
-- use (WorldDb.lua). The list is kept in the settings once read, so OpenMap's menu can show it without reading the database again.
local KINDS = {"trainer", "vendor"}
local GOSSIP = {trainer = A.Theme.ART .. "icon-learn", vendor = A.Theme.ART .. "icon-vendor"}
local COLOR = {trainer = {0.4, 0.8, 1}, vendor = {1, 0.78, 0.3}}
local MAX_PINS = 400
local MENU_MIN_VENDOR_PLACES, MENU_MAX_VENDORS = 6, 60
M.serviceIcons = GOSSIP

-- Titles of profession trainers: "Journeyman Alchemist", "Expert Blacksmith", "Mining Trainer", ... (the website's list, tools/build_services.py)
local PROFESSIONS = {
    {"alchemy", "Alchemy", {"alchem"}}, {"blacksmithing", "Blacksmithing", {"blacksmith", "weaponsmith", "armorsmith", "swordsmith", "hammersmith", "axesmith"}},
    {"cooking", "Cooking", {"%f[%a]cook"}}, {"enchanting", "Enchanting", {"enchant"}}, {"engineering", "Engineering", {"engineer"}},
    {"first-aid", "First Aid", {"first aid"}}, {"fishing", "Fishing", {"fishing", "fisherm"}}, {"herbalism", "Herbalism", {"herbal"}},
    {"leatherworking", "Leatherworking", {"leatherwork"}}, {"mining", "Mining", {"%f[%a]mining%f[%A]", "%f[%a]miner%f[%A]"}},
    {"skinning", "Skinning", {"skinn"}}, {"tailoring", "Tailoring", {"tailor"}},
}
-- a shop that happens to carry the profession's name is not a trainer
local NOT_TRAINER = {"suppl", "vendor", "recipe", "goods", "promoter", "league", "society", "reagent", "& "}
local CLASSES = {warrior = true, hunter = true, priest = true, mage = true, rogue = true, druid = true, warlock = true, shaman = true, paladin = true}
-- what OpenMap draws on its own (Townsfolk): not offered a second time
local OPENMAP_DRAWS = {innkeeper = true, ["stable master"] = true, banker = true, auctioneer = true, ["flight master"] = true, ["spirit healer"] = true}

local function contains(lower, patterns)
    for _, pattern in ipairs(patterns) do if lower:find(pattern) then return true end end
    return false
end

--- The kind a title belongs to: key (short, kept in the settings) and the name shown. nil for no title or one OpenMap draws itself.
local function groupOf(kind, title)
    if type(title) ~= "string" or title == "" then return nil end
    local lower = title:lower()
    if OPENMAP_DRAWS[lower] then return nil end
    if kind == "trainer" then
        local class = title:match("^(%a+) Trainer$")
        if class and CLASSES[class:lower()] then return "class:" .. class:lower(), class .. " trainers" end
        if not contains(lower, NOT_TRAINER) then
            for _, profession in ipairs(PROFESSIONS) do
                if contains(lower, profession[3]) then return "prof:" .. profession[1], profession[2] .. " trainers" end
            end
        end
    end
    return "t:" .. lower, title
end
M.ServiceGroupOf = groupOf

-- ---------------------------------------------------------------- what the player picked
local function settings() return A.db and A.db.settings end

function M.ServicePicks()
    local s = settings()
    if not s then return {} end
    if type(s.servicePicks) ~= "table" then s.servicePicks = {} end
    return s.servicePicks
end
function M.ServicePicked(key) return M.ServicePicks()[key] == true end

local function redraw()
    if M.RefreshLayerPins then M.RefreshLayerPins(true) end
    if M.PanelRefresh then M.PanelRefresh() end
end
function M.SetServicePicked(key, on)
    if type(key) ~= "string" or not key:find("^%a+:") then return false end
    M.ServicePicks()[key] = on and true or nil
    redraw()
    return true
end
--- Picks or drops many at once (the list in the window: "show all" / "hide all" for what the search shows).
function M.SetServiceKeys(keys, on)
    local picks = M.ServicePicks()
    for _, key in ipairs(keys) do picks[key] = on and true or nil end
    redraw()
end
function M.ClearServicePicks()
    local s = settings()
    if s then s.servicePicks = {} end
    redraw()
end

function M.ServiceKind()
    local s = settings()
    return s and s.serviceKind == "vendor" and "vendor" or "trainer"
end
function M.SetServiceKind(kind) local s = settings(); if s and (kind == "trainer" or kind == "vendor") then s.serviceKind = kind end end

function M.ServiceSide() return A.Call(UnitFactionGroup, "player") == "Horde" and "H" or "A" end

-- ---------------------------------------------------------------- the kinds that exist (from the scan, else from what was kept)
local liveCache = {}
local function fromScan(kind)
    local scan = M.Db and M.Db.scan
    local list = scan and scan.lists and scan.lists[kind]
    if not list or #list == 0 then return nil end
    local cache = liveCache[kind]
    if cache and cache.at == scan.at and cache.size == #list then return cache.groups end
    local byKey, groups = {}, {}
    for _, entry in ipairs(list) do
        local gkey, label = groupOf(kind, entry.title)
        if gkey then
            local group = byKey[gkey]
            if not group then group = {key = kind .. ":" .. gkey, label = label, kind = kind, count = 0}; byKey[gkey] = group; groups[#groups + 1] = group end
            group.count = group.count + 1
        end
    end
    table.sort(groups, function(a, b) return a.label:lower() < b.label:lower() end)
    liveCache[kind] = {at = scan.at, size = #list, groups = groups}
    return groups
end

local function kept()
    local s = settings()
    local cache = s and s.serviceCache
    if type(cache) == "table" and cache.v == 1 and cache.side == M.ServiceSide() then return cache end
end
function M.ServiceCacheValid() return kept() ~= nil end

--- The kinds of one sort ("trainer" or "vendor") with the number of places each has: [{key, label, kind, count}].
function M.ServiceGroups(kind)
    local live = fromScan(kind)
    if live then return live end
    local cache = kept()
    return cache and type(cache[kind]) == "table" and cache[kind] or {}
end

function M.ServiceCacheSave()
    local s = settings()
    if not s then return end
    local cache = {v = 1, side = M.ServiceSide()}
    for _, kind in ipairs(KINDS) do
        local out = {}
        for _, group in ipairs(fromScan(kind) or {}) do out[#out + 1] = {key = group.key, label = group.label, kind = kind, count = group.count} end
        cache[kind] = out
    end
    s.serviceCache = cache
end

--- Wanted by the window's list and by what was picked: the scan has to run (it is otherwise left alone once the list is kept).
function M.ServiceNeeded()
    local s = settings()
    if not s then return false end
    if M.wantServices or next(M.ServicePicks()) ~= nil then return true end
    return not M.ServiceCacheValid()
end

--- Called when the scan has read everything: keeps the list and gives OpenMap's menu its rows.
function M.ServiceScanDone()
    local scan = M.Db and M.Db.scan
    if not scan or M.serviceDoneFor == scan then return end
    M.serviceDoneFor = scan
    M.ServiceCacheSave()
    if M.RegisterServiceRows then M.RegisterServiceRows() end
    redraw()
end

-- ---------------------------------------------------------------- places and drawing
--- Where the NPCs of a kind are (all maps): [{map, x, y, title}].
function M.ServiceSpots(key)
    local out = {}
    local kind, gkey = tostring(key):match("^(%a+):(.+)$")
    local list = M.Db and M.Db.scan and M.Db.scan.lists and M.Db.scan.lists[kind]
    for _, entry in ipairs(list or {}) do
        local g = groupOf(kind, entry.title)
        if g and kind .. ":" .. g == key then out[#out + 1] = {map = entry.map, x = entry.x, y = entry.y, title = entry.name} end
    end
    return out
end

--- The places of the picked kinds on map `mapId`, to draw (the layers that draw a whole sort are left out: no place twice).
function M.ServiceSpecs(mapId, layers)
    local out = {}
    local picks = M.ServicePicks()
    if next(picks) == nil then return out end
    local lists = M.Db and M.Db.scan and M.Db.scan.lists
    if not lists then return out end
    for _, kind in ipairs(KINDS) do
        if not (layers and layers[kind]) then
            for _, entry in ipairs(lists[kind] or {}) do
                if entry.map == mapId and #out < MAX_PINS then
                    local gkey = groupOf(kind, entry.title)
                    if gkey and picks[kind .. ":" .. gkey] then
                        out[#out + 1] = {kind = "service", groupKey = kind .. ":" .. gkey, icon = "dot", iconFile = GOSSIP[kind], color = COLOR[kind], map = entry.map, x = entry.x, y = entry.y,
                            title = entry.name, lines = {entry.title or "", A.L("layerNavigate")}, navigate = true}
                    end
                end
            end
        end
    end
    return out
end

--- The list the window shows: the kinds of one sort whose name contains the query.
function M.ServiceItems(query, kind)
    query = tostring(query or ""):lower()
    local out = {}
    for _, group in ipairs(M.ServiceGroups(kind or M.ServiceKind())) do
        if query == "" or group.label:lower():find(query, 1, true) then
            out[#out + 1] = {key = group.key, name = group.label, kind = group.kind, count = group.count, icon = GOSSIP[group.kind]}
        end
    end
    return out
end

--- The rows of OpenMap's menu: every trainer kind, and the merchant kinds with a few places (the window has all of them).
function M.ServiceMenuRows()
    local rows = {}
    for _, group in ipairs(M.ServiceGroups("trainer")) do rows[#rows + 1] = {group = group, section = "Evertally: trainers"} end
    local vendors = {}
    for _, group in ipairs(M.ServiceGroups("vendor")) do if group.count >= MENU_MIN_VENDOR_PLACES then vendors[#vendors + 1] = group end end
    table.sort(vendors, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.label < b.label end)
    for i = 1, math.min(#vendors, MENU_MAX_VENDORS) do rows[#rows + 1] = {group = vendors[i], section = "Evertally: merchants"} end
    table.sort(rows, function(a, b) if a.section ~= b.section then return a.section < b.section end return a.group.label:lower() < b.group.label:lower() end)
    return rows
end

local text = {
    en = {worldTab_services = "Services", servicesKind_trainer = "Trainers", servicesKind_vendor = "Merchants", servicesPlaces = "%d places",
        servicesHint = "From QuestieDB, your side only. Tick one to draw its places on the map; OpenMap's own Townsfolk shows all of a sort at once.",
        servicesReading = "Reading… %d %%", servicesNothing = "Not read yet",
        catalogShowAll = "Show all", catalogHideAll = "Hide all", catalogClearPicks = "Clear picks"},
    cs = {worldTab_services = "Služby", servicesKind_trainer = "Trenéři", servicesKind_vendor = "Obchodníci", servicesPlaces = "Míst: %d",
        servicesHint = "Z QuestieDB, jen tvoje strana. Zaškrtni druh a jeho místa se nakreslí na mapě; Townsfolk v OpenMap ukazuje vždy celý druh najednou.",
        servicesReading = "Čtu… %d %%", servicesNothing = "Zatím nenačteno",
        catalogShowAll = "Zobrazit vše", catalogHideAll = "Skrýt vše", catalogClearPicks = "Zrušit výběr"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end
