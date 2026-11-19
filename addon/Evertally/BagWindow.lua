local _, A = ...
-- Evertally's own bag window: the bags in sections, as one grid, slot by slot or as a list, in Evertally's look.
--   * header: Bags | Bank, the character (alts from their last snapshot), the slots used with a bar, lock, settings, close
--   * a search (an item's name, or a tag: #sell #junk #new #quest #gear #upgrade #consumable #profession) and four views:
--     Exact slots (bag by bag, empty slots too), Sections, Packed grid, List
--   * chips with what waits: to sell, new, junk (a click filters by it)
--   * sections: New, Quest, Equipment, Consumables, Professions, To sell, Junk, Other; laid in three columns, each section
--     into the shortest one
--   * footer: gold, free slots, Sort (the client's own sort)
-- The live bags are the client's own item buttons (ContainerFrameItemButtonTemplate, under a frame that carries the bag's
-- ID), so a click uses, equips, picks up or links an item as in the game's bags. The bank and other characters are a
-- look only, from the snapshot kept when the bank was open (A.db.bagCache, per character).
-- With the window in use (settings.bagWindow.replace; off by default while another bag add-on is loaded) the game's bag
-- keys and buttons open it instead of the game's bags: the toggles are post-hooked (hooksecurefunc, no Blizzard global is
-- written) and the game's container frames for the bags are hidden again.
local BW = {}
A.BagWindow = BW

local SLOT, GAP, PAD = 36, 4, 14
local SECTION_SLOTS, SECTION_COLS, COL_GAP = 5, 3, 20
local COL_W = SECTION_SLOTS * SLOT + (SECTION_SLOTS - 1) * GAP
local CONTENT_W = SECTION_COLS * COL_W + (SECTION_COLS - 1) * COL_GAP
local WIDTH = CONTENT_W + PAD * 2
local GRID_COLS = math.floor((CONTENT_W + GAP) / (SLOT + GAP))
local HEAD_H, TOOL_Y, TOOL_H, CHIP_Y, CHIP_H, BODY_Y, FOOT_H = 46, 54, 30, 92, 22, 124, 76
local TRACK_H, TRACK_MAX = 22, 14
local SECTION_HEAD, ROW_H = 22, 28
local MIN_H, MAX_H = 380, 700
local VIEWS = {"exact", "sections", "packed", "list"}
local SECTIONS = {"new", "quest", "consumable", "profession", "gear", "sell", "junk", "other"}
local OTHER_BAG_ADDONS = {"Baganator", "Bagnon", "AdiBags", "ArkInventory", "BetterBags", "Combuctor", "OneBag3", "Inventorian", "LiteBag", "cargBags_Nivaya"}
local LOGO = "Interface\\AddOns\\Evertally\\Media\\Logo"

local text = {
    en = {bwTitle = "Bags", bwBags = "Bags", bwBank = "Bank", bwSearch = "Search, try #sell", bwView_exact = "Exact slots",
        bwView_sections = "Sections", bwView_packed = "Packed grid", bwView_list = "List",
        bwSec_new = "New", bwSec_quest = "Quest", bwSec_consumable = "Consumables", bwSec_profession = "Professions",
        bwSec_gear = "Equipment", bwSec_sell = "To sell", bwSec_junk = "Junk", bwSec_other = "Other",
        bwChip_sell = "To sell", bwChip_new = "New", bwChip_junk = "Junk", bwChip_upgrade = "Upgrades",
        bwGold = "Gold", bwFree = "%d free", bwSort = "Sort", bwSortTip = "Sorts the bags the way the game does.",
        bwLock = "Lock the window in place", bwUnlock = "Let the window move", bwSettings = "Bag settings", bwClose = "Close",
        bwReplace = "Open these bags instead of the game's", bwClearNew = "Nothing is new any more",
        bwHintMarks = "Ctrl+Alt+click: junk / keep  ·  Shift+click: link", bwHintLook = "A look only: the items stay where they are.",
        bwBankClosed = "The bank as it was when you last opened it.", bwBankNever = "Open the bank once and its items show here.",
        bwAltSeen = "As it was %s.", bwBagHead = "%s  ·  %d/%d", bwBackpack = "Backpack", bwBankSlots = "Bank", bwBagN = "Bag %d",
        bwNothing = "Nothing here.", bwNoMatch = "Nothing matches the search.", bwSlotsTip = "Slots used / all slots in the bags",
        bwBagCmd = "Bags: /etally bag",
        bwPickTitle = "Bags", bwPickBody = "Which bags do you want? The bag key opens the one you pick.",
        bwPick_evertally = "Evertally", bwPickSub_evertally = "Sections, search with #tags, Equip best, the bank and your alts at a glance.",
        bwPick_game = "The game's bags", bwPickSub_game = "The bags as the game draws them.",
        bwPickSub_other = "The bags of the %s add-on.", bwPickReload = "%s: the change takes effect after /reload.", bwEquip = "Equip best", bwEquipN = "Equip best (%d)",
        bwEquipTip = "Puts on what is better than what you wear, one piece at a time:", bwEquipNone = "Nothing in the bags beats what you wear.",
        bwEquipCombat = "The gear goes on when the fight is over.", bwEquipDone = "Put on: %s", bwEquipBind = "Items that bind when worn ask first.", bwAnotherAddon = "%s is loaded: the bag keys open its bags. Evertally's bags: /etally bag, or Bag settings.",
        bwCats = "Edit categories", bwCatsTitle = "Categories", bwCatsHint = "Top to bottom is the order in the bags. A category of your own takes what you drag onto its heading and what matches its search (words of the name, #tags: #consumable #profession #quest #gear #junk).",
        bwCatNew = "New category", bwCatName = "Name", bwCatQuery = "Search, e.g. potion #consumable", bwCatDefault = "My category %d",
        bwCatUp = "Move up", bwCatDown = "Move down", bwCatDelete = "Delete the category", bwCatReset = "Default order",
        bwCatDrop = "Drop an item here: it goes into %s.", bwCatMoved = "%s now goes into %s.", bwCatBuiltin = "built in",
        bwTrackHint = "Drag an item here to count it beside your gold", bwTrackOff = "Right-click: stop counting it", bwTrackAuto = "Counted by itself (tokens, tickets, marks).",
        bwTrackHide = "Tracked items: hide the ones you have none of", bwTrackAdded = "%s is counted beside your gold."},
    cs = {bwTitle = "Batoh", bwBags = "Batoh", bwBank = "Banka", bwSearch = "Hledat, zkus #sell", bwView_exact = "Přesné sloty",
        bwView_sections = "Sekce", bwView_packed = "Mřížka", bwView_list = "Seznam",
        bwSec_new = "Nové", bwSec_quest = "Questy", bwSec_consumable = "Spotřební", bwSec_profession = "Profese",
        bwSec_gear = "Výbava", bwSec_sell = "K prodeji", bwSec_junk = "Junk", bwSec_other = "Ostatní",
        bwChip_sell = "K prodeji", bwChip_new = "Nové", bwChip_junk = "Junk", bwChip_upgrade = "Vylepšení",
        bwGold = "Zlato", bwFree = "%d volných", bwSort = "Seřadit", bwSortTip = "Seřadí tašky tak, jak to dělá hra.",
        bwLock = "Zamknout okno na místě", bwUnlock = "Povolit posouvání okna", bwSettings = "Nastavení batohu", bwClose = "Zavřít",
        bwReplace = "Otevírat tenhle batoh místo herního", bwClearNew = "Nic už není nové",
        bwHintMarks = "Ctrl+Alt+klik: junk / ponechat  ·  Shift+klik: odkaz", bwHintLook = "Jen náhled: předměty zůstávají, kde jsou.",
        bwBankClosed = "Banka tak, jak byla, když jsi ji naposledy otevřel.", bwBankNever = "Otevři jednou banku a její předměty se ukážou tady.",
        bwAltSeen = "Stav z %s.", bwBagHead = "%s  ·  %d/%d", bwBackpack = "Batoh", bwBankSlots = "Banka", bwBagN = "Taška %d",
        bwNothing = "Nic tu není.", bwNoMatch = "Hledání nic nenašlo.", bwSlotsTip = "Obsazené sloty / všechny sloty v taškách",
        bwBagCmd = "Batoh: /etally bag",
        bwPickTitle = "Batoh", bwPickBody = "Jaký batoh chceš? Klávesa batohu otevře ten, který vybereš.",
        bwPick_evertally = "Evertally", bwPickSub_evertally = "Sekce, hledání s #štítky, Nasadit nejlepší, banka a alti na jeden pohled.",
        bwPick_game = "Herní batoh", bwPickSub_game = "Tašky tak, jak je kreslí hra.",
        bwPickSub_other = "Tašky z addonu %s.", bwPickReload = "%s: změna se projeví po /reload.", bwEquip = "Nasadit nejlepší", bwEquipN = "Nasadit nejlepší (%d)",
        bwEquipTip = "Nasadí, co je lepší než to, co máš na sobě, po jednom kusu:", bwEquipNone = "V batohu není nic lepšího, než co máš na sobě.",
        bwEquipCombat = "Výbava se nasadí, až skončí souboj.", bwEquipDone = "Nasazeno: %s", bwEquipBind = "Předměty, které se nasazením naváží, se nejdřív zeptají.", bwAnotherAddon = "Je zapnutý %s: klávesy batohu otevírají jeho tašky. Batoh Evertally: /etally bag, nebo Nastavení batohu.",
        bwCats = "Upravit kategorie", bwCatsTitle = "Kategorie", bwCatsHint = "Pořadí shora dolů je pořadí v batohu. Do vlastní kategorie patří, co přetáhneš na její nadpis, a co odpovídá jejímu hledání (slova z názvu, #tagy: #consumable #profession #quest #gear #junk).",
        bwCatNew = "Nová kategorie", bwCatName = "Název", bwCatQuery = "Hledání, např. lektvar #consumable", bwCatDefault = "Moje kategorie %d",
        bwCatUp = "Posunout výš", bwCatDown = "Posunout níž", bwCatDelete = "Smazat kategorii", bwCatReset = "Výchozí pořadí",
        bwCatDrop = "Pusť sem předmět: bude v kategorii %s.", bwCatMoved = "%s teď patří do %s.", bwCatBuiltin = "vestavěná",
        bwTrackHint = "Přetáhni sem předmět a bude se počítat vedle peněz", bwTrackOff = "Pravý klik: přestat sledovat", bwTrackAuto = "Sleduje se sám (žetony, lístky, známky).",
        bwTrackHide = "Sledované předměty: skrýt ty, které nemáš", bwTrackAdded = "%s se počítá vedle peněz."},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

-- ---------------------------------------------------------------- client access
local function pass(ok, ...) if ok then return ... end return nil end
local function call(f, ...) if type(f) ~= "function" then return nil end return pass(pcall(f, ...)) end
local function cc() local c = rawget(_G, "C_Container"); return type(c) == "table" and c or nil end
local function api(name) local c = cc(); return c and c[name] or rawget(_G, name) end

local function numSlots(bag) return tonumber(call(api("GetContainerNumSlots"), bag)) or 0 end
local function slotInfo(bag, slot)
    local CC = cc()
    if CC and CC.GetContainerItemInfo then
        local info = call(CC.GetContainerItemInfo, bag, slot)
        return type(info) == "table" and info or nil
    end
    local icon, count, locked, quality, _, _, link, _, noValue, id = call(rawget(_G, "GetContainerItemInfo"), bag, slot)
    if not icon then return nil end
    return {iconFileID = icon, stackCount = count, isLocked = locked, quality = quality, hyperlink = link, hasNoValue = noValue, itemID = id}
end
local function itemInstant(item)
    local ci = rawget(_G, "C_Item")
    local id, _, _, equipLoc, icon, classID, subclassID
    if type(ci) == "table" then id, _, _, equipLoc, icon, classID, subclassID = call(ci.GetItemInfoInstant, item) end
    if classID == nil then id, _, _, equipLoc, icon, classID, subclassID = call(rawget(_G, "GetItemInfoInstant"), item) end
    return id, equipLoc, icon, classID, subclassID
end
local function itemName(link)
    local name = call(rawget(_G, "GetItemInfo"), link)
    if type(name) == "string" and name ~= "" then return name end
    return type(link) == "string" and link:match("%[(.-)%]") or nil
end
local function bagFree(bag)
    local free, family = call(api("GetContainerNumFreeSlots"), bag)
    return tonumber(free) or 0, tonumber(family) or 0
end
local function nBagSlots() return tonumber(rawget(_G, "NUM_BAG_SLOTS")) or 4 end
local function nBankBags() return tonumber(rawget(_G, "NUM_BANKBAGSLOTS")) or 6 end
local BANK = tonumber(rawget(_G, "BANK_CONTAINER")) or -1
local function playerBags() local t = {}; for b = 0, nBagSlots() do t[#t + 1] = b end; return t end
local function bankBags() local t = {BANK}; for b = nBagSlots() + 1, nBagSlots() + nBankBags() do t[#t + 1] = b end; return t end

local QUALITY = {[0] = {0.62, 0.62, 0.62}, {1, 1, 1}, {0.12, 1, 0}, {0, 0.44, 0.87}, {0.64, 0.21, 0.93}, {1, 0.5, 0}, {0.9, 0.8, 0.5}, {0, 0.8, 1}}
local function qualityColor(q)
    local c = rawget(_G, "ITEM_QUALITY_COLORS") and ITEM_QUALITY_COLORS[q]
    if type(c) == "table" and c.r then return {c.r, c.g, c.b} end
    return QUALITY[q or 1] or QUALITY[1]
end

local function guide()
    local g = rawget(_G, "EvertallyGuide")
    return type(g) == "table" and g or nil
end

-- ---------------------------------------------------------------- settings and the snapshot
local function settings()
    local s = A.db and A.db.settings
    if not s then return {view = "sections"} end
    if type(s.bagWindow) ~= "table" then s.bagWindow = {} end
    local t = s.bagWindow
    local known = false
    for _, v in ipairs(VIEWS) do if v == t.view then known = true end end
    if not known then t.view = "sections" end
    return t
end
--- The first other bag add-on that is loaded, or nil.
function BW.OtherBagAddon()
    local loaded = (rawget(_G, "C_AddOns") and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    for _, name in ipairs(OTHER_BAG_ADDONS) do
        if call(loaded, name) then return name end
    end
    return nil
end
--- Whether the game's bag keys open this window: the player's choice, else on while no other bag add-on is loaded.
function BW.Replaces()
    local r = settings().replace
    if r ~= nil then return r == true end
    return BW.OtherBagAddon() == nil
end
function BW.SetReplace(on)
    settings().replace = on == true
    if on then BW.HideGameBags() end
end

-- An add-on on disk (C_AddOns.GetAddOnInfo knows it and it is not missing), whether it is loaded and enabled for this
-- character.
local function addonInfo(name)
    local C_AddOns = rawget(_G, "C_AddOns")
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or rawget(_G, "GetAddOnInfo")
    local got, title, _, _, reason = call(info, name)
    if not got or reason == "MISSING" then return nil end
    local loaded = call((C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded"), name) and true or false
    local state = call((C_AddOns and C_AddOns.GetAddOnEnableState) or rawget(_G, "GetAddOnEnableState"), name, call(rawget(_G, "UnitName"), "player"))
    -- enabled for the next load (what /reload brings); without the client's answer, whether it is loaded now
    local enabled = state ~= nil and (tonumber(state) or 0) > 0 or (state == nil and loaded)
    return {name = name, title = type(title) == "string" and title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or name, loaded = loaded, enabled = enabled}
end
local function setAddon(name, on)
    local C_AddOns = rawget(_G, "C_AddOns")
    local f = on and ((C_AddOns and C_AddOns.EnableAddOn) or rawget(_G, "EnableAddOn")) or ((C_AddOns and C_AddOns.DisableAddOn) or rawget(_G, "DisableAddOn"))
    return pcall(f, name)
end
--- The bags to choose from: Evertally's, the game's, then every other bag add-on on disk.
function BW.Choices()
    local out = {{value = "evertally", name = A.L("bwPick_evertally"), desc = A.L("bwPickSub_evertally")},
        {value = "game", name = A.L("bwPick_game"), desc = A.L("bwPickSub_game")}}
    for _, name in ipairs(OTHER_BAG_ADDONS) do
        local a = addonInfo(name)
        if a then out[#out + 1] = {value = name, name = a.title, desc = string.format(A.L("bwPickSub_other"), a.title)} end
    end
    return out
end
--- The player's choice, or nil before the setup asked.
function BW.Choice() return settings().choice end
--- Kept and applied: Evertally's or the game's bags turn the other bag add-ons off, one of those turns it on (both after
--- /reload, as the client loads add-ons only then); the bag key follows at once.
function BW.SetChoice(choice)
    local known = false
    for _, c in ipairs(BW.Choices()) do if c.value == choice then known = true end end
    if not known then return false end
    settings().choice = choice
    BW.SetReplace(choice == "evertally")
    local changed = {}
    for _, name in ipairs(OTHER_BAG_ADDONS) do
        local a = addonInfo(name)
        if a then
            local want = name == choice
            if a.enabled ~= want and setAddon(name, want) then changed[#changed + 1] = a.title end
        end
    end
    if #changed > 0 and A.Print then A.Print(string.format(A.L("bwPickReload"), table.concat(changed, ", "))) end
    return true
end

local function charKey()
    local name = call(rawget(_G, "UnitName"), "player")
    local realm = call(rawget(_G, "GetRealmName"))
    if type(name) ~= "string" then return nil end
    return name .. "-" .. tostring(realm or "")
end
local function cacheRoot()
    if not A.db then return nil end
    if type(A.db.bagCache) ~= "table" then A.db.bagCache = {} end
    return A.db.bagCache
end
local function readBags(bags)
    local list = {}
    for _, bag in ipairs(bags) do
        for slot = 1, numSlots(bag) do
            local info = slotInfo(bag, slot)
            if info and (info.hyperlink or info.itemID) then
                list[#list + 1] = {bag, slot, info.hyperlink or ("item:" .. tostring(info.itemID)), tonumber(info.stackCount) or 1,
                    tonumber(info.quality), info.iconFileID}
            end
        end
    end
    return list
end
local function slotCounts(bags)
    local used, total, free = 0, 0, 0
    for _, bag in ipairs(bags) do
        local n = numSlots(bag)
        local f, family = bagFree(bag)
        if family == 0 then total = total + n; free = free + f; used = used + (n - f) end
    end
    return used, total, free
end
--- Keeps this character's bags (and the bank while it is open) for the alts view and the bank tab.
function BW.Snapshot(withBank)
    local root, key = cacheRoot(), charKey()
    if not (root and key) then return end
    local e = root[key] or {}
    root[key] = e
    local _, classFile = call(rawget(_G, "UnitClass"), "player")
    e.name = call(rawget(_G, "UnitName"), "player"); e.class = classFile
    e.money = tonumber(call(rawget(_G, "GetMoney"))) or e.money
    e.time = tonumber(call(rawget(_G, "time"))) or e.time
    e.bags = readBags(playerBags())
    e.bagIcons = {}
    for _, bag in ipairs(playerBags()) do e.bagIcons[bag] = BW.BagIcon and BW.BagIcon(bag) or nil end
    local used, total = slotCounts(playerBags())
    e.used, e.total = used, total
    if withBank then
        e.bank = readBags(bankBags())
        e.bankBagIcons = {}
        for _, bag in ipairs(bankBags()) do e.bankBagIcons[bag] = BW.BagIcon and BW.BagIcon(bag) or nil end
        e.bankTime = e.time
        local bu, bt = slotCounts(bankBags())
        e.bankUsed, e.bankTotal = bu, bt
    end
end

-- ---------------------------------------------------------------- the sections: built in and the player's own
-- settings.sections: the order the sections are drawn in, the built-in keys and the player's own categories
-- ({key = "c<n>", name, query, items = {[itemID] = true}}). settings.itemSection[itemID]: the section an item was dragged
-- onto (its heading). Where an item lands: New first; then where it was put by hand; then the player's categories in
-- their order (an item put there, or one matching its search, #tags too); then the built-in rule (junk, to sell, quest,
-- equipment, consumables, professions, other).
local BUILTIN = {}
for _, key in ipairs(SECTIONS) do BUILTIN[key] = true end
local SECTION_ORDER = {}
local function isProfession(classID) return classID == 7 or classID == 9 or classID == 5 or classID == 3 end
local function sectionKey(e) return type(e) == "table" and e.key or e end
--- The sections in their order (the player's list, the built-in ones it lacks added at the end).
function BW.Sections()
    local s = settings()
    local list, have = {}, {}
    if type(s.sections) == "table" then
        for _, e in ipairs(s.sections) do
            local key = sectionKey(e)
            if type(key) == "string" and not have[key] and (BUILTIN[key] or (type(e) == "table" and key:match("^c%d+$"))) then
                have[key] = true
                list[#list + 1] = e
            end
        end
    end
    for _, key in ipairs(SECTIONS) do if not have[key] then list[#list + 1] = key end end
    s.sections = list
    for k in pairs(SECTION_ORDER) do SECTION_ORDER[k] = nil end
    for i, e in ipairs(list) do SECTION_ORDER[sectionKey(e)] = i end
    return list
end
function BW.Section(key)
    for i, e in ipairs(BW.Sections()) do if sectionKey(e) == key then return e, i end end
end
function BW.SectionName(key)
    local e = BW.Section(key)
    if type(e) == "table" then return (type(e.name) == "string" and e.name:match("%S")) and e.name or key end
    return A.L("bwSec_" .. tostring(key))
end
--- A new category of the player's, first in the order. -> its key
function BW.AddSection(name, query)
    local s, list = settings(), BW.Sections()
    local n = 1
    while BW.Section("c" .. n) do n = n + 1 end
    local e = {key = "c" .. n, name = name or string.format(A.L("bwCatDefault"), n), query = query or "", items = {}}
    table.insert(list, 1, e)
    s.sections = list
    BW.Sections()
    return e.key
end
function BW.RemoveSection(key)
    local _, i = BW.Section(key)
    if not i or BUILTIN[key] then return false end
    table.remove(settings().sections, i)
    local by = settings().itemSection
    if type(by) == "table" then for id, k in pairs(by) do if k == key then by[id] = nil end end end
    BW.Sections()
    return true
end
--- Moves a section up (-1) or down (+1) in the order.
function BW.MoveSection(key, delta)
    local _, i = BW.Section(key)
    local list = settings().sections   -- (the list BW.Section left: each call builds it anew)
    local j = i and i + delta
    if not j or j < 1 or j > #list then return false end
    list[i], list[j] = list[j], list[i]
    BW.Sections()
    return true
end
function BW.ResetSections()
    local s = settings()
    local mine = {}
    for _, e in ipairs(BW.Sections()) do if type(e) == "table" then mine[#mine + 1] = e end end
    for _, key in ipairs(SECTIONS) do mine[#mine + 1] = key end
    s.sections = mine
    BW.Sections()
end
--- Puts an item into a section by hand (dragged onto its heading); nil takes it back to the rules.
function BW.PutItem(id, key)
    id = tonumber(id)
    if not id then return false end
    local s = settings()
    if type(s.itemSection) ~= "table" then s.itemSection = {} end
    if key ~= nil and (key == "new" or not BW.Section(key)) then return false end
    s.itemSection[id] = key
    return true
end
--- The section of an item described (its flags set).
function BW.Assign(it)
    if it.new then return "new" end
    local list = BW.Sections()
    local by = type(settings().itemSection) == "table" and it.id and settings().itemSection[it.id]
    if by and SECTION_ORDER[by] then return by end
    for _, e in ipairs(list) do
        if type(e) == "table" then
            if (type(e.items) == "table" and it.id and e.items[it.id])
                or (type(e.query) == "string" and e.query:match("%S") and BW.Matches(it, e.query)) then return e.key end
        end
    end
    if it.junk then return "junk" elseif it.sell then return "sell" elseif it.quest then return "quest"
    elseif it.gear then return "gear" elseif it.classID == 0 then return "consumable"
    elseif isProfession(it.classID) then return "profession" end
    return "other"
end

-- ---------------------------------------------------------------- the tracked items (beside the gold)
-- Tokens, tickets, marks and coins are counted beside the gold by themselves while you have them (the ids from the
-- Forever item data, platform/public/media/db/items); any other item dragged onto the row is counted too
-- (settings.tracked, in the order added; right-click takes it off). settings.trackHide (on by default): a tracked
-- item you have none of is left out.
local TOKENS = {
    19182,                          -- Darkmoon Faire Prize Ticket
    20558, 20559, 20560, 274895,    -- Marks of Honor: Warsong Gulch, Arathi Basin, Alterac Valley, Darkspear Islands
    12844, 22523, 22524,            -- Argent Dawn Valor Token, Insignia of the Dawn, of the Crusade
    19698, 19699, 19700, 19701, 19702, 19703, 19704, 19705, 19706,   -- the Zandalar coins
    21100, 21815, 23247,            -- Coin of Ancestry, Love Token, Burning Blossom (holidays)
    274026, 208823, 220775,         -- Extravagant Extravaganza Coin, Offering Coin, Engineering Exchange Ticket
    232454, 232455, 232456, 232457, 275009,   -- the emblems
}
local TOKEN = {}
for _, id in ipairs(TOKENS) do TOKEN[id] = true end
BW.TOKENS = TOKENS
local function trackedList()
    local s = settings()
    if type(s.tracked) ~= "table" then s.tracked = {} end
    return s.tracked
end
function BW.Track(id)
    id = tonumber(id)
    if not id then return false end
    for _, v in ipairs(trackedList()) do if v == id then return false end end
    table.insert(trackedList(), id)
    return true
end
function BW.Untrack(id)
    id = tonumber(id)
    for i, v in ipairs(trackedList()) do if v == id then table.remove(trackedList(), i); return true end end
    return false
end
function BW.TrackHides() return settings().trackHide ~= false end
--- What the row shows for a list of items (one view's): {id, count, icon, pinned}, the tokens first.
function BW.Tracked(items)
    local count, icon = {}, {}
    for _, it in ipairs(items or {}) do
        if it.id then count[it.id] = (count[it.id] or 0) + (it.count or 1); icon[it.id] = icon[it.id] or it.icon end
    end
    local out, have = {}, {}
    for _, id in ipairs(TOKENS) do
        if (count[id] or 0) > 0 then out[#out + 1] = {id = id, count = count[id], icon = icon[id]}; have[id] = true end
    end
    for _, id in ipairs(trackedList()) do
        if not have[id] and ((count[id] or 0) > 0 or not BW.TrackHides()) then
            out[#out + 1] = {id = id, count = count[id] or 0, icon = icon[id] or call(rawget(_G, "GetItemIcon"), id), pinned = true}
            have[id] = true
        elseif have[id] then
            for _, e in ipairs(out) do if e.id == id then e.pinned = true end end
        end
    end
    return out
end

-- ---------------------------------------------------------------- what an item is
local seen          -- itemID -> count, when the window was last closed: more than that is new
local function countById(list)
    local t = {}
    for _, it in ipairs(list) do t[it.id] = (t[it.id] or 0) + (it.count or 1) end
    return t
end
local function markOf(id)
    local g = guide()
    local M = g and g.QoL and g.QoL.Marks
    return M, g
end
local function isJunkMarked(id)
    local M = markOf(id)
    return M and M.Junk and call(M.Junk, id) == true or false
end
local function isProtected(id)
    local M = markOf(id)
    return M and M.Protected and call(M.Protected, id) == true or false
end
local function questNeeds(id, bag, slot)
    local CC = cc()
    if bag and CC and CC.GetContainerItemQuestInfo then
        local q = call(CC.GetContainerItemQuestInfo, bag, slot)
        if type(q) == "table" and (q.isQuestItem or q.questID) then return true end
    end
    local g = guide()
    local Q = g and g.QuestDB
    return Q and Q.IsItemNeeded and call(Q.IsItemNeeded, id) == true or false
end
local function upgradeOf(link)
    local g = guide()
    local GB = g and g.Gear and g.Gear.Bags
    if GB and GB.IsOn and call(GB.IsOn) then
        if call(GB.IsUpgrade, link) then
            local fills = g.Gear.FillsEmptySlot and call(g.Gear.FillsEmptySlot, link)
            return fills and not call(g.Gear.IsUpgrade, link) and "empty" or "upgrade"
        end
        return nil
    end
    local B = A.BagHighlight
    if B and B.Assess then
        local empty, up = call(B.Assess, link)
        if empty or up then return empty and "empty" or "upgrade" end
    end
    local g = guide()
    local G = g and g.Gear
    if G and G.IsUpgrade and call(G.IsUpgrade, link) == true then return "upgrade" end
    return nil
end

--- One item of the list the views draw: where it is, what it is and its section.
local function describe(bag, slot, link, count, quality, icon, live, locked, isNew)
    local id, equipLoc, instIcon, classID = itemInstant(link)
    id = id or tonumber(type(link) == "string" and link:match("item:(%d+)"))
    local it = {bag = bag, slot = slot, link = link, id = id, count = count or 1, quality = quality, icon = icon or instIcon,
        classID = classID, equipLoc = equipLoc, live = live, locked = locked, name = itemName(link) or ""}
    if it.quality == nil then local _, _, q = call(rawget(_G, "GetItemInfo"), link); it.quality = tonumber(q) end
    local protected = id and isProtected(id)
    it.junk = it.quality == 0 and not protected
    it.sell = not it.junk and id ~= nil and isJunkMarked(id)
    it.quest = classID == 12 or (live and id and questNeeds(id, bag, slot)) or false
    it.gear = (classID == 2 or classID == 4) and type(equipLoc) == "string" and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG"
    it.upgrade = it.gear and live and upgradeOf(link) or nil
    it.new = isNew or false
    it.section = BW.Assign(it)
    return it
end

local function liveItems(bags)
    local list = {}
    for _, bag in ipairs(bags) do
        for slot = 1, numSlots(bag) do
            local info = slotInfo(bag, slot)
            if info and (info.hyperlink or info.itemID) then
                local link = info.hyperlink or ("item:" .. tostring(info.itemID))
                local newFlag = rawget(_G, "C_NewItems") and C_NewItems.IsNewItem and call(C_NewItems.IsNewItem, bag, slot) == true
                list[#list + 1] = describe(bag, slot, link, tonumber(info.stackCount), tonumber(info.quality), info.iconFileID, true, info.isLocked, newFlag)
            end
        end
    end
    -- more of an item than when the window was last closed: new (the client's own flag counts too)
    if seen then
        local now = countById(list)
        local grown = {}
        for id, n in pairs(now) do if n > (seen[id] or 0) then grown[id] = true end end
        for _, it in ipairs(list) do
            if not it.new and grown[it.id] then it.new = true; it.section = "new" end
        end
    end
    return list
end
local function cachedItems(entries)
    local list = {}
    for _, e in ipairs(entries or {}) do list[#list + 1] = describe(e[1], e[2], e[3], e[4], e[5], e[6], false) end
    return list
end

local function byKind(a, b)
    if a.section ~= b.section then return (SECTION_ORDER[a.section] or 99) < (SECTION_ORDER[b.section] or 99) end
    if (a.quality or 1) ~= (b.quality or 1) then return (a.quality or 1) > (b.quality or 1) end
    if (a.classID or 99) ~= (b.classID or 99) then return (a.classID or 99) < (b.classID or 99) end
    if a.name ~= b.name then return a.name < b.name end
    if a.count ~= b.count then return a.count > b.count end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

-- A search: words match the name, #tags what the item is.
local TAGS = {
    sell = function(it) return it.sell or it.junk end, junk = function(it) return it.junk end, new = function(it) return it.new end,
    quest = function(it) return it.quest end, gear = function(it) return it.gear end, upgrade = function(it) return it.upgrade ~= nil end,
    consumable = function(it) return it.classID == 0 end, profession = function(it) return isProfession(it.classID) end,
}
local function lower(s) return A.Lower and A.Lower(s) or string.lower(s or "") end
function BW.Matches(it, query)
    if type(query) ~= "string" or query:match("^%s*$") then return true end
    local name = lower(it.name)
    for word in query:gmatch("%S+") do
        local tag = word:match("^#(%w+)$")
        if tag then
            local f = TAGS[lower(tag)]
            if f and not f(it) then return false end
        elseif not name:find(lower(word), 1, true) then return false end
    end
    return true
end
BW.Describe, BW.LiveItems = describe, liveItems

-- ---------------------------------------------------------------- equip best
-- What goes on: each bag item the guide's gear advice would wear (Equip.Placement, the rule its quest rewards and loot
-- offers follow: the weaker ring or trinket, a one-hander against a worn two-hander), the best per slot. Without the
-- guide, Evertally's own verdict (BagHighlight: an upgrade or an empty slot) and the client's choice of slot.
-- Never an item marked junk or one a later step keeps.
function BW.EquipPlan()
    local g = guide()
    local G = g and g.Gear
    local QoL = g and g.QoL
    local place = QoL and QoL.Equip and QoL.Equip.Placement
    local best, order = {}, {}
    for _, it in ipairs(liveItems(playerBags())) do
        local kept = it.id and QoL and QoL.Kept and call(QoL.Kept, it.id)
        if it.gear and it.id and not it.junk and not it.sell and not kept then
            local slot, pct
            if G and place then slot, pct = call(place, G, it.link)
            elseif it.upgrade then pct = 0 end
            if slot or (not (G and place) and it.upgrade) then
                local key = slot or it.equipLoc
                local cur = best[key]
                if not cur then order[#order + 1] = key end
                if not cur or (tonumber(pct) or 0) > (tonumber(cur.pct) or 0) then
                    best[key] = {link = it.link, slot = slot, pct = tonumber(pct), name = it.name, id = it.id, quality = it.quality}
                end
            end
        end
    end
    local plan = {}
    for _, key in ipairs(order) do plan[#plan + 1] = best[key] end
    table.sort(plan, function(a, b) return (a.pct or 0) > (b.pct or 0) end)
    return plan
end

local equipping
local function equipLink(link, slot)
    local ci = rawget(_G, "C_Item")
    local f = type(ci) == "table" and ci.EquipItemByName or rawget(_G, "EquipItemByName")
    if type(f) ~= "function" then return false end
    return pcall(f, link, slot)
end
--- Puts the plan on, one piece at a time: each next piece is weighed against what is worn once the last went on, so a
--- second ring takes the weaker finger. Stops when nothing is better, when a piece did not go on (its bind confirmation
--- was declined) or after twenty.
function BW.EquipBest()
    if call(rawget(_G, "InCombatLockdown")) then
        if A.Print then A.Print(A.L("bwEquipCombat")) end
        BW.equipAfterFight = true
        return false
    end
    if equipping then return false end
    local tried, done, steps = {}, {}, 0
    local function nextPiece()
        steps = steps + 1
        local plan = steps <= 20 and BW.EquipPlan() or {}
        local piece
        for _, p in ipairs(plan) do if not tried[p.link] then piece = p; break end end
        if not piece then
            equipping = nil
            if A.Print then
                if #done > 0 then A.Print(string.format(A.L("bwEquipDone"), table.concat(done, ", ")))
                else A.Print(A.L("bwEquipNone")) end
            end
            BW.Request()
            return
        end
        tried[piece.link] = true
        if equipLink(piece.link, piece.slot) then done[#done + 1] = piece.link end
        -- the client swaps the piece and then tells the gear advice; the next one is weighed after that
        if rawget(_G, "C_Timer") and C_Timer.After then C_Timer.After(0.6, nextPiece) else nextPiece() end
    end
    equipping = true
    nextPiece()
    return true
end
A.On("PLAYER_REGEN_ENABLED", function() if BW.equipAfterFight then BW.equipAfterFight = false; BW.EquipBest() end end)

-- ---------------------------------------------------------------- the windows
-- Two windows from one body: the bags (BW.bags) and the bank (BW.bank, at the banker in place of the game's bank, and a
-- look at the last bank you saw away from it). Each keeps its own buttons, pools and state.
local kit, C
local bankOpen = false
local function paint(t, c, a)
    if t.SetTextColor and not t.SetTexture then t:SetTextColor(c[1], c[2], c[3], a or c[4] or 1); return end
    kit.paint(t, c, a)
end
local function money(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = string.format("|cffe6c35c%d|r|cffb08d3dg|r", g) end
    if g > 0 or s > 0 then out[#out + 1] = string.format("|cffd8dde3%d|r|cff9aa3abs|r", s) end
    out[#out + 1] = string.format("|cffe0a070%d|r|cffa8683ac|r", c)
    return table.concat(out, " ")
end
local function tip(owner, fn)
    if not GameTooltip then return end
    pcall(function() GameTooltip:SetOwner(owner, "ANCHOR_RIGHT"); fn(GameTooltip); GameTooltip:Show() end)
end
local function hideTip() if GameTooltip then GameTooltip:Hide() end end

-- The look every item button gets: a dark well, the icon, the count, a quality edge, and the marks.
local function dressButton(b)
    if b.etDressed then return b end
    b.etDressed = true
    local name = b.GetName and b:GetName()
    for _, part in ipairs({"IconTexture", "Count", "IconQuestTexture", "Stock", "NewItemTexture", "SearchOverlay"}) do
        local r = name and _G[name .. part]
        if r and r.Hide then r:Hide(); if r.SetText then r:SetText("") end end
    end
    for _, key in ipairs({"icon", "Count", "IconBorder", "NewItemTexture", "BattlepayItemTexture", "searchOverlay", "IconQuestTexture"}) do
        local r = rawget(b, key)
        if type(r) == "table" and r.Hide then r:Hide() end
    end
    if b.GetNormalTexture then local n = b:GetNormalTexture(); if n then n:SetAlpha(0) end end
    b.etWell = b:CreateTexture(nil, "BACKGROUND"); b.etWell:SetAllPoints(b); paint(b.etWell, C.well or C.card, 1)
    b.etIcon = b:CreateTexture(nil, "ARTWORK"); b.etIcon:SetPoint("TOPLEFT", 2, -2); b.etIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.etIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.etEdge = {}
    for i, side in ipairs({{"TOPLEFT", "TOPRIGHT", nil, 1}, {"BOTTOMLEFT", "BOTTOMRIGHT", nil, 1}, {"TOPLEFT", "BOTTOMLEFT", 1, nil}, {"TOPRIGHT", "BOTTOMRIGHT", 1, nil}}) do
        local t = b:CreateTexture(nil, "BORDER"); t:SetPoint(side[1]); t:SetPoint(side[2])
        if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
        b.etEdge[i] = t
    end
    -- the marks sit on a frame above the button's own (cooldown, highlight)
    local o = CreateFrame("Frame", nil, b); o:SetAllPoints(b)
    if o.SetFrameLevel and b.GetFrameLevel then o:SetFrameLevel((b:GetFrameLevel() or 1) + 3) end
    b.etOver = o
    b.etCount = kit.label(o, 11, C.text); b.etCount:SetPoint("BOTTOMRIGHT", -3, 3); b.etCount:SetJustifyH("RIGHT")
    if b.etCount.SetShadowOffset then b.etCount:SetShadowOffset(1, -1); b.etCount:SetShadowColor(0, 0, 0, 1) end
    b.etMark = kit.label(o, 13, C.gold); b.etMark:SetPoint("TOPRIGHT", -4, -1)
    local g = guide()
    local art = g and g.Theme and g.Theme.Media and call(g.Theme.Media, "qol-upgrade")
    if art then
        b.etArrow = o:CreateTexture(nil, "OVERLAY", nil, 3); b.etArrow:SetSize(18, 18); b.etArrow:SetPoint("TOPLEFT", -1, 1)
        b.etArrow:SetTexture(art); b.etArrow.etArt = true
    else
        b.etArrow = A.Theme.Glyph(o, "chevron-up", 12, C.green, "OVERLAY"); b.etArrow:SetPoint("TOPRIGHT", -1, -1)
    end
    b.etCoin = o:CreateTexture(nil, "OVERLAY"); b.etCoin:SetSize(9, 9); b.etCoin:SetPoint("BOTTOMLEFT", 3, 3); A.Theme.Shape(b.etCoin, "dot")
    b.etNew = o:CreateTexture(nil, "OVERLAY"); b.etNew:SetSize(7, 7); b.etNew:SetPoint("TOPRIGHT", -3, -3); A.Theme.Shape(b.etNew, "dot")
    b.etShade = o:CreateTexture(nil, "OVERLAY", nil, 2); b.etShade:SetAllPoints(b); paint(b.etShade, {0, 0, 0}, 0.62)
    return b
end
local function showItem(b, it, dim)
    dressButton(b)
    b.etItem = it
    if it then
        b.etIcon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark"); b.etIcon:Show()
        b.etIcon:SetDesaturated(it.locked and true or false)
        b.etCount:SetText((it.count or 1) > 1 and tostring(it.count) or "")
        local edge = (it.quality or 1) >= 2 and qualityColor(it.quality) or (it.new and C.gold) or C.line
        for _, t in ipairs(b.etEdge) do paint(t, edge, (it.quality or 1) >= 2 and 0.95 or (edge[4] or 1)) end
        b.etMark:SetText(it.quest and "!" or "")
        b.etArrow:SetShown(it.upgrade ~= nil)
        if it.upgrade then
            local c = it.upgrade == "empty" and C.sky or C.green
            if b.etArrow.etArt then b.etArrow:SetVertexColor(c[1], c[2], c[3], 1) else paint(b.etArrow, c) end
        end
        b.etCoin:SetShown(it.junk or it.sell)
        if it.junk or it.sell then paint(b.etCoin, it.junk and C.faint or C.peach) end
        b.etNew:SetShown(it.new); if it.new then paint(b.etNew, C.gold) end
    else
        b.etIcon:Hide(); b.etCount:SetText(""); b.etMark:SetText("")
        for _, t in ipairs(b.etEdge) do paint(t, C.line, 0.55) end
        b.etArrow:Hide(); b.etCoin:Hide(); b.etNew:Hide()
    end
    b.etShade:SetShown(dim and true or false)
    -- the client's cooldown on a live slot
    if it and it.live then
        local cd = rawget(b, "Cooldown") or (b.GetName and b:GetName() and _G[b:GetName() .. "Cooldown"])
        local start, duration, enable = call(api("GetContainerItemCooldown"), it.bag, it.slot)
        if cd and start and rawget(_G, "CooldownFrame_Set") then call(CooldownFrame_Set, cd, start, duration, enable) end
    end
    b:Show()
end

-- An equipped bag's inventory slot (the backpack has none).
local function bagInv(bag)
    if bag <= 0 then return nil end
    return tonumber(call(api("ContainerIDToInventoryID"), bag))
end
local function bagIcon(bag)
    if bag == 0 then return "Interface\\Buttons\\Button-Backpack-Up" end
    if bag == BANK then return "Interface\\Icons\\INV_Misc_Bag_10_Blue" end
    local inv = bagInv(bag)
    return inv and call(rawget(_G, "GetInventoryItemTexture"), "player", inv) or nil
end

BW.BagIcon = bagIcon
local nLive = 0
local SPEC = {
    bags = {name = "EvertallyBagWindow", title = "bwBags", bags = playerBags, live = function() return true end, point = "point"},
    bank = {name = "EvertallyBankWindow", title = "bwBank", bags = bankBags, live = function() return bankOpen end, point = "bankPoint"},
}

local function newWindow(kind)
    local spec = SPEC[kind]
    local w = {kind = kind}
    local win
    local holders, liveButtons, lookButtons, bagButtons = {}, {}, {}, {}

    -- live slots: the client's item button under a holder that carries the bag's ID (its clicks read the parent's ID)
    local function holder(bag)
        local h = holders[bag]
        if h then return h end
        h = CreateFrame("Frame", nil, win.content)
        if h.SetID then h:SetID(bag) end
        h:SetSize(1, 1); h:SetPoint("TOPLEFT")
        holders[bag] = h
        return h
    end
    local function liveButton(bag, slot)
        liveButtons[bag] = liveButtons[bag] or {}
        local b = liveButtons[bag][slot]
        if b then return b end
        nLive = nLive + 1
        local ok, made = pcall(CreateFrame, "Button", "EvertallyBagItem" .. nLive, holder(bag), "ContainerFrameItemButtonTemplate")
        if not ok or not made then made = CreateFrame("Button", "EvertallyBagItem" .. nLive, holder(bag)) end
        b = made
        if b.SetID then b:SetID(slot) end
        b:SetSize(SLOT, SLOT)
        b.etBag, b.etSlot = bag, slot
        if b.RegisterForDrag then pcall(b.RegisterForDrag, b, "LeftButton") end
        -- the bank's own slots are inventory slots for the tooltip (the client's bag tooltip does not read them)
        if bag == BANK then
            b:SetScript("OnEnter", function(self)
                local inv = tonumber(call(rawget(_G, "BankButtonIDToInvSlotID"), self:GetID(), nil))
                tip(self, function(t) if inv then t:SetInventoryItem("player", inv) elseif self.etItem then t:SetHyperlink(self.etItem.link) end end)
            end)
            b:SetScript("OnLeave", hideTip)
        end
        dressButton(b)
        liveButtons[bag][slot] = b
        return b
    end
    -- look-only slots (the bank away from it, other characters): the item's tooltip, Shift+click links it
    local function lookButton(i)
        local b = lookButtons[i]
        if b then return b end
        b = CreateFrame("Button", nil, win.content); b:SetSize(SLOT, SLOT)
        if b.RegisterForClicks then b:RegisterForClicks("AnyUp") end
        b:SetScript("OnEnter", function(self)
            local it = self.etItem
            if it then tip(self, function(t) t:SetHyperlink(it.link); t:AddLine(A.L("bwHintLook"), 0.55, 0.58, 0.66, true) end) end
        end)
        b:SetScript("OnLeave", hideTip)
        b:SetScript("OnClick", function(self)
            local it = self.etItem
            if it and rawget(_G, "HandleModifiedItemClick") then call(HandleModifiedItemClick, it.link) end
        end)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(b); paint(hl, {1, 1, 1}, 0.10)
        dressButton(b)
        lookButtons[i] = b
        return b
    end

    -- the pools of drawn parts that are not item buttons
    local function pool(name, make)
        win[name] = win[name] or {list = {}, used = 0}
        local p = win[name]
        p.used = p.used + 1
        local r = p.list[p.used]
        if not r then r = make(); p.list[p.used] = r end
        r:Show()
        return r
    end
    local function resetPools()
        for _, name in ipairs({"heads", "rows", "notes"}) do
            local p = win[name]
            if p then for i = 1, #p.list do p.list[i]:Hide() end; p.used = 0 end
        end
    end
    local function sectionHead(x, y, width, label, count, key)
        local h = pool("heads", function()
            local f = CreateFrame("Frame", nil, win.content); f:SetHeight(SECTION_HEAD)
            f.tick = f:CreateTexture(nil, "ARTWORK"); f.tick:SetSize(2, 11); f.tick:SetPoint("LEFT", 0, 0)
            f.text = kit.label(f, 11, C.gold); f.text:SetPoint("LEFT", f.tick, "RIGHT", 7, 0)
            f.count = kit.label(f, 11, C.faint); f.count:SetPoint("LEFT", f.text, "RIGHT", 6, 0)
            -- an item dragged onto the heading goes into this section from now on
            f:EnableMouse(true)
            local function drop(self)
                local what, id = call(rawget(_G, "GetCursorInfo"))
                if what ~= "item" or not self.key or self.key == "new" then return end
                if BW.PutItem(id, self.key) then
                    call(rawget(_G, "ClearCursor"))
                    if A.Print then A.Print(string.format(A.L("bwCatMoved"), itemName("item:" .. tostring(id)) or tostring(id), BW.SectionName(self.key))) end
                    BW.Request()
                end
            end
            f:SetScript("OnReceiveDrag", drop)
            f:SetScript("OnMouseUp", drop)
            f:SetScript("OnEnter", function(self)
                if call(rawget(_G, "GetCursorInfo")) == "item" and self.key ~= "new" then
                    tip(self, function(t) t:SetText(string.format(A.L("bwCatDrop"), BW.SectionName(self.key)), 1, 1, 1, 1, true) end)
                end
            end)
            f:SetScript("OnLeave", hideTip)
            return f
        end)
        h.key = key
        paint(h.tick, C.gold, 1)
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", win.content, "TOPLEFT", x, -y); h:SetWidth(width)
        h.text:SetText(label); h.count:SetText(count and tostring(count) or "")
    end
    local function note(y, msg)
        local n = pool("notes", function() local f = kit.label(win.content, 12, C.faint); f:SetJustifyH("CENTER"); return f end)
        n:ClearAllPoints(); n:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -y); n:SetWidth(CONTENT_W); n:SetText(msg)
    end
    local function listRow(y, it)
        local r = pool("rows", function()
            local f = CreateFrame("Frame", nil, win.content); f:SetSize(CONTENT_W, ROW_H)
            f.rule = f:CreateTexture(nil, "BACKGROUND"); f.rule:SetHeight(1); f.rule:SetPoint("BOTTOMLEFT"); f.rule:SetPoint("BOTTOMRIGHT")
            f.name = kit.label(f, 12, C.text); f.name:SetPoint("LEFT", ROW_H + 8, 0); f.name:SetWordWrap(false)
            f.tag = kit.label(f, 11, C.faint); f.tag:SetPoint("RIGHT", -70, 0); f.tag:SetJustifyH("RIGHT")
            f.count = kit.label(f, 12, C.mist); f.count:SetPoint("RIGHT", -8, 0); f.count:SetJustifyH("RIGHT")
            f.name:SetPoint("RIGHT", f.tag, "LEFT", -10, 0)
            return f
        end)
        paint(r.rule, C.line, 0.35)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -y)
        local q = qualityColor(it.quality or 1)
        r.name:SetText(it.name ~= "" and it.name or tostring(it.id)); r.name:SetTextColor(q[1], q[2], q[3], 1)
        r.tag:SetText(BW.SectionName(it.section)); r.count:SetText((it.count or 1) > 1 and ("×" .. it.count) or "")
    end

    -- what is shown: whose, and whether it is live (the own bags; the own bank while the banker is open)
    local function viewing()
        local key = charKey()
        local who = w.char or key
        return who, who == key
    end
    local function isLive() local _, own = viewing(); return own and spec.live() end
    local function sourceItems()
        local who, own = viewing()
        local entry = (cacheRoot() or {})[who]
        if isLive() then
            local list = kind == "bags" and liveItems(spec.bags()) or {}
            if kind == "bank" then
                for _, e in ipairs(readBags(spec.bags())) do list[#list + 1] = describe(e[1], e[2], e[3], e[4], e[5], e[6], true) end
            end
            local used, total = slotCounts(spec.bags())
            return list, used, total
        end
        if kind == "bank" then
            if entry and entry.bank then return cachedItems(entry.bank), entry.bankUsed, entry.bankTotal end
            return {}, 0, 0, "never"
        end
        if entry then return cachedItems(entry.bags), entry.used, entry.total end
        return {}, 0, 0
    end
    local function placeButton(b, x, y, size)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", win.content, "TOPLEFT", x, -y); b:SetSize(size or SLOT, size or SLOT)
    end
    local function hideAllButtons()
        for _, slots in pairs(liveButtons) do for _, b in pairs(slots) do b:Hide(); b.etItem = nil end end
        for _, b in ipairs(lookButtons) do b:Hide(); b.etItem = nil end
    end

    -- the equipped bags: their icons on the chips row; hovering one lights its slots, a click or a drag takes it, an
    -- item dropped on it goes in
    local function bagButton(i)
        local b = bagButtons[i]
        if b then return b end
        b = CreateFrame("Button", nil, win); b:SetSize(24, 24)
        if b.RegisterForClicks then b:RegisterForClicks("AnyUp") end
        if b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(b); paint(b.bg, C.well or C.card, 1)
        kit.outline(b, C.line)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(b); paint(hl, {1, 1, 1}, 0.12)
        local function take(self)
            if not isLive() then return end
            local inv = bagInv(self.bag)
            if not inv then return end
            if call(rawget(_G, "CursorHasItem")) then call(rawget(_G, "PutItemInBag"), inv) else call(rawget(_G, "PickupBagFromSlot"), inv) end
        end
        b:SetScript("OnClick", take)
        b:SetScript("OnDragStart", take)
        b:SetScript("OnReceiveDrag", take)
        b:SetScript("OnEnter", function(self)
            w.hiBag = self.bag; w.Render()
            local inv = isLive() and bagInv(self.bag)
            tip(self, function(t)
                if inv and call(rawget(_G, "GetInventoryItemTexture"), "player", inv) then t:SetInventoryItem("player", inv)
                else t:SetText(self.bag == 0 and A.L("bwBackpack") or self.bag == BANK and A.L("bwBankSlots") or string.format(A.L("bwBagN"), self.bag)) end
            end)
        end)
        b:SetScript("OnLeave", function() w.hiBag = nil; hideTip(); w.Request() end)
        bagButtons[i] = b
        return b
    end
    local function layoutBags()
        local who = viewing()
        local entry = (cacheRoot() or {})[who] or {}
        local icons = kind == "bank" and entry.bankBagIcons or entry.bagIcons or {}
        local x, n = 0, 0
        local list = spec.bags()
        for i = #list, 1, -1 do
            local bag = list[i]
            n = n + 1
            local b = bagButton(n)
            b.bag = bag
            local icon = isLive() and bagIcon(bag) or icons[bag] or (bag == 0 and bagIcon(0)) or (bag == BANK and bagIcon(BANK))
            if icon then b.icon:SetTexture(icon); b.icon:Show() else b.icon:Hide() end
            b:ClearAllPoints(); b:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD - x, -CHIP_Y + 1)
            b:Show()
            x = x + 24 + 4
        end
        for i = n + 1, #bagButtons do bagButtons[i]:Hide() end
    end

    function w.Render()
        if not (win and win:IsShown()) then return end
        win.dirty = false
        resetPools(); hideAllButtons()
        local items, used, total, state = sourceItems()
        win.items = items
        local live = isLive()
        local query = win.search and win.search:GetText() or ""
        local view = settings().view
        local nLook = 0
        local function button(it)
            if live and it then return liveButton(it.bag, it.slot) end
            nLook = nLook + 1
            return lookButton(nLook)
        end
        local function dimmed(it) return w.hiBag ~= nil and (not it or it.bag ~= w.hiBag) end
        local nSell, nNew, nJunk, nUp = 0, 0, 0, 0
        for _, it in ipairs(items) do
            if it.sell then nSell = nSell + 1 end
            if it.new then nNew = nNew + 1 end
            if it.junk then nJunk = nJunk + 1 end
            if it.upgrade then nUp = nUp + 1 end
        end
        w.UpdateChips({sell = nSell, new = nNew, junk = nJunk, upgrade = nUp})
        layoutBags()
        local shown = {}
        for _, it in ipairs(items) do if BW.Matches(it, query) then shown[#shown + 1] = it end end
        table.sort(shown, byKind)
        local y = 0
        if state == "never" then note(20, A.L("bwBankNever")); y = 60
        elseif view == "exact" then
            -- bag by bag, every slot, the empty ones too; what the search leaves out is dimmed
            local at = {}
            for _, it in ipairs(items) do at[it.bag .. ":" .. it.slot] = it end
            local match = {}
            for _, it in ipairs(shown) do match[it] = true end
            for _, bag in ipairs(spec.bags()) do
                local n = live and numSlots(bag) or 0
                if not live then for _, it in ipairs(items) do if it.bag == bag and it.slot > n then n = it.slot end end end
                if n > 0 then
                    local free = 0
                    for s = 1, n do if not at[bag .. ":" .. s] then free = free + 1 end end
                    local name = bag == 0 and A.L("bwBackpack") or bag == BANK and A.L("bwBankSlots")
                        or (live and call(api("GetBagName"), bag)) or string.format(A.L("bwBagN"), bag)
                    sectionHead(0, y, CONTENT_W, string.format(A.L("bwBagHead"), name, n - free, n))
                    y = y + SECTION_HEAD
                    local col = 0
                    for s = 1, n do
                        local it = at[bag .. ":" .. s]
                        local b
                        if live then b = liveButton(bag, s) elseif it then b = button(it) end
                        if b then
                            placeButton(b, col * (SLOT + GAP), y)
                            showItem(b, it, (it and query ~= "" and not match[it]) or (w.hiBag ~= nil and bag ~= w.hiBag))
                        end
                        col = col + 1
                        if col >= GRID_COLS and s < n then col = 0; y = y + SLOT + GAP end
                    end
                    y = y + SLOT + GAP + 8
                end
            end
        elseif #shown == 0 then
            note(20, #items == 0 and A.L("bwNothing") or A.L("bwNoMatch")); y = 60
        elseif view == "packed" then
            for i, it in ipairs(shown) do
                local b = button(it)
                placeButton(b, ((i - 1) % GRID_COLS) * (SLOT + GAP), y + math.floor((i - 1) / GRID_COLS) * (SLOT + GAP))
                showItem(b, it, dimmed(it))
            end
            y = y + math.ceil(#shown / GRID_COLS) * (SLOT + GAP)
        elseif view == "list" then
            for _, it in ipairs(shown) do
                listRow(y, it)
                local b = button(it)
                placeButton(b, 2, y + 2, ROW_H - 4)
                showItem(b, it, dimmed(it))
                b.etCount:SetText(""); b.etMark:SetText("")   -- the row says the count
                y = y + ROW_H
            end
        else
            -- sections in three columns, each into the shortest
            local groups, order = {}, {}
            for _, it in ipairs(shown) do
                if not groups[it.section] then groups[it.section] = {}; order[#order + 1] = it.section end
                table.insert(groups[it.section], it)
            end
            BW.Sections()
            table.sort(order, function(a, b) return (SECTION_ORDER[a] or 99) < (SECTION_ORDER[b] or 99) end)
            local colY = {}
            for c = 1, SECTION_COLS do colY[c] = 0 end
            for _, key in ipairs(order) do
                local list = groups[key]
                local c = 1
                for k = 2, SECTION_COLS do if colY[k] < colY[c] then c = k end end
                local x = (c - 1) * (COL_W + COL_GAP)
                sectionHead(x, colY[c], COL_W, BW.SectionName(key), #list, key)
                local top = colY[c] + SECTION_HEAD
                for i, it in ipairs(list) do
                    local b = button(it)
                    placeButton(b, x + ((i - 1) % SECTION_SLOTS) * (SLOT + GAP), top + math.floor((i - 1) / SECTION_SLOTS) * (SLOT + GAP))
                    showItem(b, it, dimmed(it))
                end
                colY[c] = top + math.ceil(#list / SECTION_SLOTS) * (SLOT + GAP) + 10
            end
            for c = 1, SECTION_COLS do if colY[c] > y then y = colY[c] end end
        end
        win.content:SetHeight(math.max(y, 10))
        local want = BODY_Y + y + FOOT_H + 6
        win:SetHeight(math.max(MIN_H, math.min(MAX_H, want)))
        w.UpdateHeader(used or 0, total or 0)
    end

    function w.UpdateChips(counts)
        for key, chip in pairs(win.chips) do
            local n = counts[key] or 0
            chip.num:SetText(tostring(n)); chip.text:SetText(A.L("bwChip_" .. key))
            chip:SetShown(n > 0 or key ~= "upgrade")
            local on = win.search and win.search:GetText() == "#" .. key
            paint(chip.bg, on and (C.raised or C.card) or C.card, 1)
            chip:SetWidth(math.floor((chip.num:GetStringWidth() or 10) + (chip.text:GetStringWidth() or 40) + 32))
        end
        local x = 0
        for _, key in ipairs({"sell", "new", "junk", "upgrade"}) do
            local chip = win.chips[key]
            if chip:IsShown() then chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + x, -CHIP_Y); x = x + chip:GetWidth() + 6 end
        end
    end

    -- the tracked items of the view (the live bags, a look at the bank or an alt's)
    function w.UpdateTracker()
        local list = BW.Tracked(win.items or {})
        local x = 8
        for i = 1, TRACK_MAX do
            local c = win.track.chips[i]
            local e = list[i]
            if not c and e then
                c = CreateFrame("Button", nil, win.track); c:SetHeight(TRACK_H)
                c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(14, 14); c.icon:SetPoint("LEFT", 0, 0); c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                c.num = kit.label(c, 12, C.text); c.num:SetPoint("LEFT", c.icon, "RIGHT", 5, 0)
                c:SetScript("OnClick", function(self, button)
                    if w.dropTrack() then return end
                    if button == "RightButton" and self.pinned then BW.Untrack(self.id); BW.Request() end
                end)
                c:SetScript("OnReceiveDrag", function() w.dropTrack() end)
                c:SetScript("OnEnter", function(self)
                    tip(self, function(t)
                        t:SetHyperlink("item:" .. tostring(self.id))
                        t:AddLine(self.pinned and A.L("bwTrackOff") or A.L("bwTrackAuto"), 0.55, 0.58, 0.66, true)
                    end)
                end)
                c:SetScript("OnLeave", hideTip)
                win.track.chips[i] = c
            end
            if c then
                if e then
                    c.id, c.pinned = e.id, e.pinned
                    c.icon:SetTexture(e.icon or 134400)
                    c.num:SetText(tostring(e.count))
                    paint(c.num, e.count > 0 and C.text or C.faint)
                    c:SetWidth(math.floor(14 + 5 + (c.num:GetStringWidth() or 10) + 4))
                    c:ClearAllPoints(); c:SetPoint("LEFT", win.track, "LEFT", x, 0)
                    x = x + c:GetWidth() + 12
                    c:SetShown(x < CONTENT_W)
                else
                    c:Hide()
                end
            end
        end
        win.track.hint:SetShown(#list == 0)
    end

    function w.UpdateHeader(used, total)
        local who, own = viewing()
        local entry = (cacheRoot() or {})[who]
        local live = isLive()
        win.slots:SetText(string.format("%d / %d", used, total))
        local frac = total > 0 and used / total or 0
        win.barFill:SetWidth(math.max(1, math.floor(110 * math.min(1, frac))))
        paint(win.barFill, frac >= 0.9 and C.red or frac >= 0.75 and C.peach or C.green, 1)
        local name = entry and entry.name or (who and who:match("^([^%-]+)")) or "?"
        win.charText:SetText(name)
        local cc = entry and entry.class and rawget(_G, "RAID_CLASS_COLORS") and RAID_CLASS_COLORS[entry.class]
        if cc then win.charText:SetTextColor(cc.r, cc.g, cc.b, 1) else win.charText:SetTextColor(C.text[1], C.text[2], C.text[3], 1) end
        win.charArrow:ClearAllPoints(); win.charArrow:SetPoint("LEFT", win.charText, "RIGHT", 4, -1)
        local m = own and tonumber(call(rawget(_G, "GetMoney"))) or (entry and entry.money) or 0
        win.money:SetText(money(m))
        local free = math.max(0, total - used)
        win.free:SetText(string.format(A.L("bwFree"), free))
        w.UpdateTracker()
        paint(win.free, free == 0 and C.red or C.mist)
        win.sort:SetShown(live)
        if win.equip then
            local plan = live and BW.EquipPlan() or {}
            win.equip.plan = plan
            win.equip:SetShown(live)
            if win.equip.text then win.equip.text:SetText(#plan > 0 and string.format(A.L("bwEquipN"), #plan) or A.L("bwEquip")) end
            win.equip:SetAlpha(#plan > 0 and 1 or 0.45)
        end
        if win.bankLink then
            paint(win.bankLink.text, BW.bank.Shown() and C.bright or C.mist)
            win.bankLink.line:SetShown(BW.bank.Shown())
        end
        -- how old a look is
        local stamp
        if kind == "bank" and not live then stamp = entry and entry.bankTime and A.L("bwBankClosed")
        elseif not own and entry and entry.time then
            stamp = string.format(A.L("bwAltSeen"), call(rawget(_G, "date"), "%d.%m. %H:%M", entry.time) or "?")
        end
        win.stamp:SetText(stamp or ""); win.stamp:SetShown(stamp ~= nil)
        win.lock.SetTint(settings().locked and C.gold or C.mist)
        for _, seg in ipairs(win.segs) do
            local on = settings().view == seg.view
            paint(seg.bg, on and (C.raised or C.card) or C.card, 1)
            paint(seg.text, on and C.bright or C.mist)
            seg.line:SetShown(on)
        end
    end

    function w.Request()
        if not win then return end
        win.dirty = true
        if win.pending then return end
        win.pending = true
        local function run() win.pending = false; if win:IsShown() and win.dirty then w.Render() end end
        if rawget(_G, "C_Timer") and C_Timer.After then C_Timer.After(0.05, run) else run() end
    end

    -- a small menu under a header control: {text, checked, onClick} rows
    local function popup(owner, items)
        local m = win.menu
        if not m then
            m = CreateFrame("Frame", nil, win); m:SetFrameStrata("DIALOG"); m:EnableMouse(true)
            A.NativeFrame(m, C)
            m.rows = {}
            win.menu = m
        end
        if m:IsShown() and m.owner == owner then m:Hide(); return end
        m.owner = owner
        local width = 200
        for i, item in ipairs(items) do
            local r = m.rows[i]
            if not r then
                r = CreateFrame("Button", nil, m); r:SetHeight(24)
                local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(r); paint(hl, C.gold, 0.12)
                r.check = A.Theme.Glyph(r, "check", 12, C.gold); r.check:SetPoint("LEFT", 8, 0)
                r.text = kit.label(r, 12, C.text); r.text:SetPoint("LEFT", 26, 0)
                r:SetScript("OnClick", function(self) m:Hide(); if self.fn then pcall(self.fn) end; BW.Request() end)
                m.rows[i] = r
            end
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24); r:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 24)
            r.text:SetText(item.text); r.check:SetShown(item.checked and true or false); r.fn = item.onClick
            width = math.max(width, math.floor((r.text:GetStringWidth() or 0) + 44))
            r:Show()
        end
        for i = #items + 1, #m.rows do m.rows[i]:Hide() end
        m:SetSize(width, #items * 24 + 8)
        m:ClearAllPoints(); m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
        m:Show()
    end

    local function savePoint()
        local point, _, rel, x, y = win:GetPoint(1)
        settings()[spec.point] = {point, rel, x, y}
    end
    function w.Build()
        if win then return win end
        kit = kit or A.UIKit(); C = C or kit.C
        win = CreateFrame("Frame", spec.name, UIParent)
        w.frame = win
        win:SetSize(WIDTH, 520); win:SetFrameStrata("HIGH"); win:SetToplevel(true); win:SetClampedToScreen(true)
        win:EnableMouse(true); win:SetMovable(true)
        A.NativeFrame(win, C)
        -- header: logo, the title, (the bank's link), the character, the slots, lock, settings, close
        win.head = win:CreateTexture(nil, "BORDER"); win.head:SetPoint("TOPLEFT", 1, -1); win.head:SetPoint("TOPRIGHT", -1, -1); win.head:SetHeight(HEAD_H)
        paint(win.head, C.header or C.well, 1)
        win.drag = CreateFrame("Frame", nil, win); win.drag:SetPoint("TOPLEFT"); win.drag:SetPoint("TOPRIGHT", -240, 0); win.drag:SetHeight(HEAD_H)
        win.drag:EnableMouse(true); win.drag:RegisterForDrag("LeftButton")
        win.drag:SetScript("OnDragStart", function() if not settings().locked then win:StartMoving() end end)
        win.drag:SetScript("OnDragStop", function() win:StopMovingOrSizing(); savePoint() end)
        win.logo = win:CreateTexture(nil, "ARTWORK"); win.logo:SetSize(24, 24); win.logo:SetPoint("TOPLEFT", PAD, -11); win.logo:SetTexture(LOGO)
        win.title = kit.label(win, 15, C.bright); win.title:SetPoint("LEFT", win.logo, "RIGHT", 10, 0); win.title:SetText(A.L(spec.title))
        local anchor = win.title
        if kind == "bags" then
            -- the bank window from the bags: the bank itself at the banker, the last one you saw elsewhere
            local t = CreateFrame("Button", nil, win); t:SetHeight(HEAD_H - 8)
            t.text = kit.label(t, 14, C.mist); t.text:SetPoint("CENTER", 0, 1); t.text:SetText(A.L("bwBank"))
            t.line = t:CreateTexture(nil, "ARTWORK"); t.line:SetHeight(2); t.line:SetPoint("BOTTOMLEFT", 4, 2); t.line:SetPoint("BOTTOMRIGHT", -4, 2); paint(t.line, C.gold, 1)
            t:SetWidth(math.floor((t.text:GetStringWidth() or 40) + 20))
            t:SetPoint("LEFT", win.title, "RIGHT", 12, 0)
            t:SetScript("OnClick", function() BW.bank.Toggle(); w.Request() end)
            win.bankLink = t
            anchor = t
        end
        w.char = nil
        win.charBtn = CreateFrame("Button", nil, win); win.charBtn:SetSize(150, 24); win.charBtn:SetPoint("LEFT", anchor, "RIGHT", 14, 0)
        win.charText = kit.label(win.charBtn, 13, C.text); win.charText:SetPoint("LEFT", 0, 0)
        win.charArrow = A.Theme.Glyph(win.charBtn, "chevron-down", 12, C.mist); win.charArrow:SetPoint("LEFT", win.charText, "RIGHT", 4, -1)
        win.charBtn:SetScript("OnClick", function(self)
            local items, root, mine = {}, cacheRoot() or {}, charKey()
            local keys = {}
            for k in pairs(root) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) if a == mine then return true elseif b == mine then return false end return a < b end)
            for _, k in ipairs(keys) do
                local e = root[k]
                items[#items + 1] = {text = (e.name or k) .. (k == mine and "" or ("  |cff8b93a8" .. (k:match("%-(.+)$") or "") .. "|r")), checked = (w.char or mine) == k,
                    onClick = function() w.char = k ~= mine and k or nil end}
            end
            popup(self, items)
        end)
        win.stamp = kit.label(win, 10, C.faint); win.stamp:SetPoint("TOPLEFT", win.charBtn, "BOTTOMLEFT", 0, 2)
        win.close = kit.IconButton(win, "close", 24, function() win:Hide() end, "bwClose"); win.close:SetPoint("TOPRIGHT", -10, -11)
        win.gear = kit.IconButton(win, "gear", 24, function(self)
            popup(self, {
                {text = A.L("bwReplace"), checked = BW.Replaces(), onClick = function() BW.SetReplace(not BW.Replaces()) end},
                {text = A.L("bwClearNew"), onClick = function() BW.ClearNew() end},
                {text = A.L("bwCats"), onClick = function() BW.Categories.Toggle(win) end},
                {text = A.L("bwTrackHide"), checked = BW.TrackHides(), onClick = function() settings().trackHide = not BW.TrackHides() end},
            })
        end, "bwSettings")
        win.gear:SetPoint("RIGHT", win.close, "LEFT", -2, 0)
        win.lock = kit.IconButton(win, "lock", 24, function() settings().locked = not settings().locked; BW.Request() end, "bwLock")
        win.lock:SetPoint("RIGHT", win.gear, "LEFT", -2, 0)
        win.bar = win:CreateTexture(nil, "ARTWORK"); win.bar:SetSize(110, 3); win.bar:SetPoint("RIGHT", win.lock, "LEFT", -14, -8); paint(win.bar, C.off or C.line, 1)
        win.barFill = win:CreateTexture(nil, "ARTWORK", nil, 1); win.barFill:SetHeight(3); win.barFill:SetPoint("LEFT", win.bar, "LEFT")
        win.slots = kit.label(win, 13, C.text); win.slots:SetPoint("BOTTOMRIGHT", win.bar, "TOPRIGHT", 0, 4); win.slots:SetJustifyH("RIGHT")
        win.slotsTip = CreateFrame("Frame", nil, win); win.slotsTip:SetPoint("TOPLEFT", win.slots, "TOPLEFT", -4, 4); win.slotsTip:SetPoint("BOTTOMRIGHT", win.bar, "BOTTOMRIGHT", 0, -4)
        win.slotsTip:EnableMouse(true)
        win.slotsTip:SetScript("OnEnter", function(self) tip(self, function(t) t:SetText(A.L("bwSlotsTip")) end) end)
        win.slotsTip:SetScript("OnLeave", hideTip)
        -- the search and the views
        local segW = 92
        local box = CreateFrame("EditBox", nil, win)
        box:SetPoint("TOPLEFT", PAD, -TOOL_Y); box:SetSize(CONTENT_W - segW * #VIEWS - 10, TOOL_H)
        box:SetAutoFocus(false)
        if box.SetFont then box:SetFont(kit.fontPath("body"), 12, "") end
        if box.SetTextInsets then box:SetTextInsets(28, 8, 0, 0) end
        box:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
        box.bg = box:CreateTexture(nil, "BACKGROUND"); box.bg:SetAllPoints(box); paint(box.bg, C.well or C.card, 1)
        kit.outline(box, C.line)
        box.icon = A.Theme.Glyph(box, "search", 13, C.faint); box.icon:SetPoint("LEFT", 9, 0)
        box.hint = kit.label(box, 12, C.faint); box.hint:SetPoint("LEFT", 28, 0); box.hint:SetText(A.L("bwSearch"))
        box:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == ""); w.Request() end)
        box:SetScript("OnEscapePressed", function(self) if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end end)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnter", function(self) if guide() then tip(self, function(t) t:SetText(A.L("bwHintMarks"), 1, 1, 1, 1, true) end) end end)
        box:SetScript("OnLeave", hideTip)
        win.search = box
        win.segs = {}
        for i, view in ipairs(VIEWS) do
            local s = CreateFrame("Button", nil, win); s:SetSize(segW, TOOL_H)
            s:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + CONTENT_W - segW * (#VIEWS - i + 1), -TOOL_Y)
            s.bg = s:CreateTexture(nil, "BACKGROUND"); s.bg:SetAllPoints(s)
            kit.outline(s, C.line)
            s.text = kit.label(s, 12, C.mist); s.text:SetPoint("CENTER"); s.text:SetText(A.L("bwView_" .. view))
            s.line = s:CreateTexture(nil, "ARTWORK"); s.line:SetHeight(2); s.line:SetPoint("BOTTOMLEFT", 1, 1); s.line:SetPoint("BOTTOMRIGHT", -1, 1); paint(s.line, C.gold, 1)
            s.view = view
            s:SetScript("OnClick", function() settings().view = view; BW.Request() end)
            win.segs[i] = s
        end
        -- the chips (the equipped bags sit at the row's right end)
        win.chips = {}
        local dots = {sell = C.peach, new = C.gold, junk = C.faint, upgrade = C.green}
        for _, key in ipairs({"sell", "new", "junk", "upgrade"}) do
            local c = CreateFrame("Button", nil, win); c:SetHeight(CHIP_H)
            c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints(c); A.Theme.Shape(c.bg, "pill")
            c.dot = c:CreateTexture(nil, "ARTWORK"); c.dot:SetSize(7, 7); c.dot:SetPoint("LEFT", 10, 0); A.Theme.Shape(c.dot, "dot"); paint(c.dot, dots[key], 1)
            c.num = kit.label(c, 12, C.bright); c.num:SetPoint("LEFT", c.dot, "RIGHT", 6, 0)
            c.text = kit.label(c, 12, C.mist); c.text:SetPoint("LEFT", c.num, "RIGHT", 5, 0)
            c:SetScript("OnClick", function()
                local tag = "#" .. key
                win.search:SetText(win.search:GetText() == tag and "" or tag)
            end)
            win.chips[key] = c
        end
        -- the body
        win.scroll = CreateFrame("ScrollFrame", nil, win)
        win.scroll:SetPoint("TOPLEFT", PAD, -BODY_Y); win.scroll:SetPoint("BOTTOMRIGHT", -PAD + 4, FOOT_H)
        win.content = CreateFrame("Frame", nil, win.scroll); win.content:SetSize(CONTENT_W, 10)
        win.scroll:SetScrollChild(win.content)
        win.scroll:EnableMouseWheel(true)
        win.scroll:SetScript("OnMouseWheel", function(self, delta)
            local max = math.max(0, (win.content:GetHeight() or 0) - (self:GetHeight() or 0))
            local v = math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * (SLOT + GAP)))
            self:SetVerticalScroll(v)
        end)
        -- the footer: gold, free slots, (equip best), sort
        win.foot = win:CreateTexture(nil, "BORDER"); win.foot:SetPoint("BOTTOMLEFT", 1, 1); win.foot:SetPoint("BOTTOMRIGHT", -1, 1); win.foot:SetHeight(FOOT_H - 6)
        paint(win.foot, C.header or C.well, 1)
        win.footRule = win:CreateTexture(nil, "ARTWORK"); win.footRule:SetHeight(1); win.footRule:SetPoint("BOTTOMLEFT", win.foot, "TOPLEFT"); win.footRule:SetPoint("BOTTOMRIGHT", win.foot, "TOPRIGHT")
        paint(win.footRule, C.line, 1)
        -- the tracked items: a row over the gold; an item dropped on it is counted from now on
        win.track = CreateFrame("Button", nil, win); win.track:SetHeight(TRACK_H)
        win.track:SetPoint("BOTTOMLEFT", PAD, 46); win.track:SetPoint("BOTTOMRIGHT", -PAD, 46)
        win.track.bg = win.track:CreateTexture(nil, "BACKGROUND"); win.track.bg:SetAllPoints(win.track); paint(win.track.bg, C.well or C.card, 1)
        kit.outline(win.track, C.line)
        win.track.hint = kit.label(win.track, 11, C.faint); win.track.hint:SetPoint("LEFT", 10, 0); win.track.hint:SetText(A.L("bwTrackHint"))
        win.track.chips = {}
        local function dropTrack()
            local what, id = call(rawget(_G, "GetCursorInfo"))
            if what ~= "item" then return false end
            if BW.Track(id) and A.Print then A.Print(string.format(A.L("bwTrackAdded"), itemName("item:" .. tostring(id)) or tostring(id))) end
            call(rawget(_G, "ClearCursor"))
            BW.Request()
            return true
        end
        w.dropTrack = dropTrack
        win.track:SetScript("OnReceiveDrag", dropTrack)
        win.track:SetScript("OnClick", dropTrack)
        win.goldLabel = kit.label(win, 12, C.mist); win.goldLabel:SetPoint("BOTTOMLEFT", PAD, 16); win.goldLabel:SetText(A.L("bwGold"))
        win.money = kit.label(win, 13, C.text); win.money:SetPoint("LEFT", win.goldLabel, "RIGHT", 12, 0)
        win.free = kit.label(win, 12, C.mist); win.free:SetPoint("LEFT", win.money, "RIGHT", 22, 0)
        win.sort = kit.Button(win, "bwSort", 110, "ghost", function()
            if kind == "bank" then if not call(api("SortBankBags")) and rawget(_G, "SortBankBags") then call(SortBankBags) end
            elseif not call(api("SortBags")) and rawget(_G, "SortBags") then call(SortBags) end
        end)
        win.sort:SetPoint("BOTTOMRIGHT", -PAD, 9); win.sort:SetHeight(28)
        if win.sort.text then win.sort.text:SetText(A.L("bwSort")) end
        if kind == "bags" then
            win.equip = kit.Button(win, "bwEquip", 180, "primary", function() BW.EquipBest() end)
            win.equip:SetPoint("RIGHT", win.sort, "LEFT", -8, 0); win.equip:SetHeight(28)
            win.equip:HookScript("OnEnter", function(self)
                tip(self, function(t)
                    local plan = self.plan or {}
                    if #plan == 0 then t:SetText(A.L("bwEquipNone")); return end
                    t:SetText(A.L("bwEquip"))
                    t:AddLine(A.L("bwEquipTip"), 0.72, 0.75, 0.80, true)
                    for _, p in ipairs(plan) do
                        local q = qualityColor(p.quality or 1)
                        t:AddDoubleLine(p.name ~= "" and p.name or p.link, p.pct and string.format("+%.0f %%", p.pct) or "", q[1], q[2], q[3], 0.40, 0.80, 0.58)
                    end
                    t:AddLine(A.L("bwEquipBind"), 0.55, 0.58, 0.66, true)
                end)
            end)
            win.equip:HookScript("OnLeave", hideTip)
        end
        win:Hide()
        win:SetScript("OnShow", function() w.Render() end)
        win:SetScript("OnHide", function()
            if win.menu then win.menu:Hide() end
            if win.search then win.search:ClearFocus() end
            if kind == "bags" then BW.MarkSeen()
            elseif bankOpen and not w.closingQuietly then call(rawget(_G, "CloseBankFrame")) end   -- closing the bank window leaves the banker
            if BW.bags.frame and BW.bags.frame:IsShown() then BW.bags.Request() end
        end)
        local p = settings()[spec.point]
        if type(p) == "table" and p[1] then win:SetPoint(p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
        elseif kind == "bank" then win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -110)
        else win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 110) end
        if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, spec.name) end
        return win
    end

    function w.Show() w.Build(); w.char = nil; win:Show(); w.Render() end
    function w.Hide() if win then win:Hide() end end
    function w.Shown() return win ~= nil and win:IsShown() end
    function w.Toggle() if w.Shown() then w.Hide() else w.Show() end end
    return w
end
BW.bags = newWindow("bags")
BW.bank = newWindow("bank")

--- What is in the bags now counts as seen: nothing is new.
function BW.MarkSeen()
    seen = countById(liveItems(playerBags()))
end
function BW.ClearNew()
    if rawget(_G, "C_NewItems") and C_NewItems.ClearAll then call(C_NewItems.ClearAll) end
    BW.MarkSeen()
end

-- The bags window keeps the old names; "bank" opens the bank window (the bags stay as they are).
function BW.Build() return BW.bags.Build() end
function BW.Show(tab) if tab == "bank" then BW.bank.Show() else BW.bags.Show() end end
function BW.Hide() BW.bags.Hide() end
function BW.Shown() return BW.bags.Shown() end
function BW.Toggle() BW.bags.Toggle() end
function BW.Render() BW.bags.Render(); BW.bank.Render() end
function BW.Request() BW.bags.Request(); BW.bank.Request() end
function A.ToggleBagWindow() BW.Toggle() end

-- ---------------------------------------------------------------- the game's bag keys
-- The game's container frames for the player's bags are hidden again whenever they open while this window stands in
-- for them. The window's state follows the outermost call of a key press: its post-hook runs last.
local function isPlayerBag(id) return id ~= nil and id >= 0 and id <= nBagSlots() end
function BW.HideGameBags()
    for i = 1, (tonumber(rawget(_G, "NUM_CONTAINER_FRAMES")) or 13) do
        local f = rawget(_G, "ContainerFrame" .. i)
        if f and f.IsShown and f:IsShown() and isPlayerBag(f.GetID and f:GetID()) then f:Hide() end
    end
end
local stampFrame, wasShown
local function before()
    local now = call(rawget(_G, "GetTime")) or 0
    if stampFrame ~= now then stampFrame = now; wasShown = BW.Shown() end
    return wasShown
end
local function onKey(kind, bag)
    if not BW.Replaces() or not A.db then return end
    if bag ~= nil and not isPlayerBag(tonumber(bag)) then return end
    local was = before()
    BW.HideGameBags()
    if kind == "toggle" then if was then BW.Hide() else BW.Show("bags") end
    elseif kind == "open" then if not BW.Shown() then BW.Show("bags") end
    else BW.Hide() end
end
local hooked = false
function BW.Hook()
    if hooked or type(hooksecurefunc) ~= "function" then return end
    hooked = true
    local kinds = {ToggleAllBags = "toggle", ToggleBackpack = "toggle", OpenAllBags = "open", OpenBackpack = "open", CloseAllBags = "close", CloseBackpack = "close"}
    for name, kind in pairs(kinds) do
        if type(rawget(_G, name)) == "function" then hooksecurefunc(name, function() onKey(kind) end) end
    end
    if type(rawget(_G, "ToggleBag")) == "function" then hooksecurefunc("ToggleBag", function(id) onKey("toggle", id or 0) end) end
    if type(rawget(_G, "OpenBag")) == "function" then hooksecurefunc("OpenBag", function(id) onKey("open", id or 0) end) end
end

-- The game's bank window steps aside while ours stands in for it: it stays open (closing it would leave the banker),
-- out of sight and out of the mouse's way, and comes back as it was when the bank closes.
local function gameBank(hide)
    local f = rawget(_G, "BankFrame")
    if not (f and f.SetAlpha) then return end
    if hide then
        f.etHidden = true
        f:SetAlpha(0)
        if f.EnableMouse then f:EnableMouse(false) end
        if f.SetScale then f.etScale = f.etScale or (f.GetScale and f:GetScale()) or 1; f:SetScale(0.001) end
    elseif f.etHidden then
        f.etHidden = nil
        f:SetAlpha(1)
        if f.EnableMouse then f:EnableMouse(true) end
        if f.SetScale and f.etScale then f:SetScale(f.etScale); f.etScale = nil end
    end
end
BW.GameBank = gameBank

-- ---------------------------------------------------------------- events
A.On("PLAYER_LOGIN", function()
    BW.Hook()
    local other = BW.OtherBagAddon()
    if other and settings().replace == nil and settings().toldOther ~= other and A.Print then
        settings().toldOther = other
        A.Print(string.format(A.L("bwAnotherAddon"), other))
    end
end)
A.On("BAG_UPDATE_DELAYED", function()
    if seen == nil then BW.MarkSeen() end
    BW.Snapshot(bankOpen)
    BW.Request()
end)
A.On("PLAYER_ENTERING_WORLD", function() BW.Snapshot(false); if seen == nil then BW.MarkSeen() end end)
A.On("ITEM_LOCK_CHANGED", function() BW.Request() end)
A.On("PLAYER_EQUIPMENT_CHANGED", function() BW.Request() end)
A.On("BAG_UPDATE_COOLDOWN", function() BW.Request() end)
A.On("PLAYER_MONEY", function() BW.Snapshot(bankOpen); BW.Request() end)
A.On("GET_ITEM_INFO_RECEIVED", function() BW.Request() end)
A.On("BANKFRAME_OPENED", function()
    bankOpen = true
    BW.Snapshot(true)
    if BW.Replaces() then
        gameBank(true)
        BW.bank.Show()
        if not BW.Shown() then BW.Show("bags") end
    end
    BW.Request()
end)
A.On("BANKFRAME_CLOSED", function()
    BW.Snapshot(true)
    bankOpen = false
    gameBank(false)
    BW.bank.closingQuietly = true
    BW.bank.Hide()
    BW.bank.closingQuietly = nil
    BW.Request()
end)
A.On("PLAYERBANKSLOTS_CHANGED", function() if bankOpen then BW.Snapshot(true); BW.Request() end end)
