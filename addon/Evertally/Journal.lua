local _, A = ...
-- The Journal page: the story of the character, day by day, with filters and a search. The Quests filter turns into a quest log:
-- one row per quest, with where it stands (open, completed, dropped).
local text = {
    en = {
        journal = "Journal", sub_journal = "Everything that happened to your character, day by day. Search by name, filter by kind.",
        journalAll = "All", journalQuests = "Quests", journalLoot = "Loot", journalPlaces = "Places", journalLevel = "Levels", journalRuns = "Dungeons",
        journalSearch = "Search…", journalCount = "%d records", journalQuestState = "%d open  ·  %d completed  ·  %d dropped",
        journalToday = "Today", journalYesterday = "Yesterday", journalNone = "Nothing here yet. Play, and the journal fills itself.", journalNoMatch = "Nothing matches.",
    },
    cs = {
        journal = "Deník", sub_journal = "Všechno, co se tvé postavě stalo, den po dni. Hledej podle názvu, filtruj podle druhu.",
        journalAll = "Vše", journalQuests = "Questy", journalLoot = "Loot", journalPlaces = "Místa", journalLevel = "Levely", journalRuns = "Dungeony",
        journalSearch = "Hledat…", journalCount = "Záznamů: %d", journalQuestState = "Rozpracováno %d  ·  splněno %d  ·  opuštěno %d",
        journalToday = "Dnes", journalYesterday = "Včera", journalNone = "Zatím tu nic není. Hraj a deník se vyplní sám.", journalNoMatch = "Nic nevyhovuje.",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local FILTERS = {"all", "quests", "loot", "places", "level", "runs"}
local LIMIT = 250

local function dayKey(at) return A.Call(date, "%Y%m%d", at) or tostring(math.floor(at / 86400)) end
local function dayTitle(at, today, yesterday)
    local key = dayKey(at)
    if key == today then return A.L("journalToday") end
    if key == yesterday then return A.L("journalYesterday") end
    return A.Call(date, "%d. %m. %Y", at) or key
end

--- The journal as list rows: {filter = "all"|"quests"|..., query = "text"} -> items (with day headings), counts per filter, number of matches.
function A.JournalItems(kit, filter, query)
    local events = A.db.events
    local counts = {all = 0, quests = 0, loot = 0, places = 0, level = 0, runs = 0}
    for i = #events, 1, -1 do
        local category = A.JournalCategory(events[i].kind)
        if category then counts.all = counts.all + 1; counts[category] = counts[category] + 1 end
    end
    local states = {open = 0, done = 0, dropped = 0}
    local now = A.Now()
    local today, yesterday = dayKey(now), dayKey(now - 86400)
    query = kit.fold(query or "")
    local groups, group, matches, seenQuest = {}, nil, 0, {}
    for i = #events, 1, -1 do
        local e = events[i]
        local category = A.JournalCategory(e.kind)
        local keep = category ~= nil and (filter == "all" or filter == category)
        if keep and category == "quests" then
            local id = type(e.payload) == "table" and e.payload.questId or nil
            if filter == "quests" and id then
                if seenQuest[id] then keep = false else
                    seenQuest[id] = true
                    if e.kind == "quest.turned_in" then states.done = states.done + 1 elseif e.kind == "quest.abandoned" then states.dropped = states.dropped + 1 else states.open = states.open + 1 end
                end
            end
        end
        if keep and matches < LIMIT then
            local item = kit.eventItem(e, true)
            if query == "" or kit.fold((item.title or "") .. " " .. (item.sub or "")):find(query, 1, true) then
                local at = A.Number(e.observedAt, 0) or 0
                local key = dayKey(at)
                if not group or group.key ~= key then group = {key = key, title = dayTitle(at, today, yesterday), items = {}}; groups[#groups + 1] = group end
                group.items[#group.items + 1] = item
                matches = matches + 1
            end
        end
    end
    local items = {}
    for _, g in ipairs(groups) do
        items[#items + 1] = {heading = g.title, right = tostring(#g.items)}
        for _, item in ipairs(g.items) do items[#items + 1] = item end
    end
    return items, counts, matches, states
end

function A.BuildJournalPage(page, kit)
    local C = kit.C
    A.journalPage = page   -- read by the layout preview
    kit.PageHeader(page, "journal")
    page.filter, page.query, page.chips = "all", "", {}
    local previous
    for _, key in ipairs(FILTERS) do
        local chip = kit.Chip(page, function() page.filter = key; A.RefreshUI() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -54) end
        page.chips[key] = chip; previous = chip
    end
    page.search = kit.SearchBox(page, 190, function(value) if value ~= page.query then page.query = value; A.RefreshUI() end end)
    page.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -84)
    page.summary = kit.label(page, 11, C.mist)
    page.summary:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -90); page.summary:SetPoint("TOPRIGHT", page, "TOPRIGHT", -204, -90)
    page.list = kit.ListView(page, 118)
    function page.Refresh()
        local items, counts, matches, states = A.JournalItems(kit, page.filter, page.query)
        for _, key in ipairs(FILTERS) do
            local chip = page.chips[key]
            chip.SetLabel(A.L("journal" .. key:sub(1, 1):upper() .. key:sub(2)) .. "  " .. counts[key]); chip.SetOn(page.filter == key)
        end
        page.search.hint:SetText(A.L("journalSearch"))
        if page.filter == "quests" then page.summary:SetText(string.format(A.L("journalQuestState"), states.open, states.done, states.dropped))
        else page.summary:SetText(string.format(A.L("journalCount"), matches)) end
        page.list.SetItems(items, (page.query ~= "" or counts.all > 0) and A.L("journalNoMatch") or A.L("journalNone"))
    end
end
