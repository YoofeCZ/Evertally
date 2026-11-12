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

-- Item names and icons can arrive after the first read; keep an already selected entry, then redraw its details once.
A.On("GET_ITEM_INFO_RECEIVED",function()
    local page=A.journalPage
    if page then page.detailSignature=nil;if page:IsShown() and A.RefreshUI then A.RefreshUI() end end
end)

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
            item.event = e
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
    local ink, muted = {0.20,0.12,0.055}, {0.36,0.26,0.14}
    A.journalPage = page
    kit.PageHeader(page, "journal")
    page.filter, page.query, page.chips = "all", "", {}
    local previous
    for _, key in ipairs(FILTERS) do
        local chip = kit.Chip(page, function() page.filter=key; page.selectedEvent=nil; A.RefreshUI() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 5, 0) else chip:SetPoint("TOPLEFT", 0,-54) end
        page.chips[key]=chip; previous=chip
    end
    page.search=kit.SearchBox(page,180,function(value) if value~=page.query then page.query=value; A.RefreshUI() end end)
    page.search:SetPoint("TOPRIGHT",-4,-84)
    page.summary=kit.label(page,11,C.mist); page.summary:SetPoint("TOPLEFT",0,-90); page.summary:SetPoint("TOPRIGHT",-195,-90)
    page.columns=kit.Columns(page,{2,3},12);page.columns:SetPoint("TOPLEFT",0,-118);page.columns:SetPoint("BOTTOMRIGHT")
    local ledger=kit.Card(page.columns.cells[1]);ledger:SetAllPoints(page.columns.cells[1]);page.ledger=ledger
    page.list=kit.ListView(ledger,0)
    local reader=CreateFrame("Frame",nil,page.columns.cells[2]);reader:SetAllPoints(page.columns.cells[2]);A.NativeParchment(reader,C);page.reader=reader
    page.readerBody=CreateFrame("Frame",nil,reader);page.readerBody:SetPoint("TOPLEFT",14,-14);page.readerBody:SetPoint("BOTTOMRIGHT",-14,52)
    page.readerTitle=kit.label(page.readerBody,17,ink);page.readerTitle:SetPoint("TOPLEFT");page.readerTitle:SetPoint("TOPRIGHT");page.readerTitle:SetJustifyH("LEFT")
    page.readerDate=kit.label(page.readerBody,10,muted);page.readerDate:SetPoint("TOPLEFT",0,-48);page.readerDate:SetPoint("TOPRIGHT",0,-48)
    page.readerText=kit.label(page.readerBody,12,ink);page.readerText:SetPoint("TOPLEFT",0,-76);page.readerText:SetPoint("BOTTOMRIGHT");page.readerText:SetJustifyV("TOP")
    page.open=kit.Button(reader,nil,170,"primary",function()
        local e=page.selectedEvent;local p=e and e.payload or {}
        if p.questId then A.OpenDatabaseEntry("quest",p.questId)
        elseif p.itemId then A.OpenDatabaseEntry("item",p.itemId)
        elseif page.selectedAction then page.selectedAction() end
    end);page.open:SetPoint("BOTTOMLEFT",14,12);page.open:SetPoint("BOTTOMRIGHT",-14,12)
    local function selectedDetail(force)
        local event=page.selectedEvent
        local signature=tostring(event)..":"..tostring(A.db.settings.language)
        if not force and signature==page.detailSignature then return end
        page.detailSignature=signature
        local payload=event and event.payload or {}
        local model, M
        if payload.questId and A.LoadGuide then A.LoadGuide();M=A.map end
        if M and M.GuideDetail and M.RenderQuestCard then
            if not page.questView then
                page.questView=M.GuideDetail(kit,page.readerBody)
                page.questView.scroll:SetPoint("TOPLEFT");page.questView.scroll:SetPoint("BOTTOMRIGHT",-16,0)
            end
            local handle=M.Db and M.Db.Open()
            model=handle and M.DatabaseQuestModel and M.DatabaseQuestModel(handle,payload.questId)
            model=model or {id=payload.questId,title=payload.title or page.selectedTitle or ("Quest #"..payload.questId),extras={A.L(event.kind),kit.stamp(event.observedAt)}}
            page.questView.SetWidth(math.max(160,(page.readerBody:GetWidth() or 340)-20))
            M.RenderQuestCard(page.questView,model)
            page.questView.scroll:Show()
        elseif page.questView then page.questView.scroll:Hide() end
        local questCard=model~=nil
        page.readerTitle:SetShown(not questCard);page.readerDate:SetShown(not questCard);page.readerText:SetShown(not questCard)
        page.readerTitle:SetText(page.selectedTitle or A.L("journalNone"));page.readerDate:SetText(event and kit.stamp(event.observedAt) or "")
        local lines={}
        if event then
            lines[#lines+1]=A.L(event.kind)
            if payload.mapId then lines[#lines+1]=kit.mapName(payload.mapId) end
            if payload.quantity then lines[#lines+1]="x"..payload.quantity end
            if payload.xp then lines[#lines+1]=tostring(payload.xp).." XP" end
            if payload.money then lines[#lines+1]=A.FormatMoney(payload.money) end
            if payload.durationMs then lines[#lines+1]=kit.duration(payload.durationMs) end
            if payload.itemId and A.Call(GetItemInfo,payload.itemId) then lines[#lines+1]=A.Call(GetItemInfo,payload.itemId) end
        else lines[1]=A.L("journalNone") end
        page.readerText:SetText(table.concat(lines,"\n\n"))
        page.open.text:SetText((payload.questId or payload.itemId) and A.L("openDatabase") or (A.db.settings.language=="cs" and "Podrobnosti záznamu" or "Record details"));page.open:SetShown(event~=nil)
    end
    function page.SelectEvent(event,item)
        page.selectedEvent=event;page.selectedTitle=item and item.title;page.selectedAction=item and item.openAction
        selectedDetail(true)
    end
    page.readerBody:SetScript("OnSizeChanged",function() selectedDetail(true) end)
    function page.Refresh()
        page.columns.Layout()
        local items,counts,matches,states=A.JournalItems(kit,page.filter,page.query)
        for _,key in ipairs(FILTERS) do local chip=page.chips[key];chip.SetLabel(A.L("journal"..key:sub(1,1):upper()..key:sub(2)));chip.SetOn(page.filter==key) end
        page.search.hint:SetText(A.L("journalSearch"))
        if page.filter=="quests" then page.summary:SetText(string.format(A.L("journalQuestState"),states.open,states.done,states.dropped)) else page.summary:SetText(string.format(A.L("journalCount"),matches)) end
        local first,selected
        for _,item in ipairs(items) do
            if item.event then
                first=first or item
                if item.event==page.selectedEvent then selected=item end
                item.openAction=item.onClick
                item.onClick=function() page.SelectEvent(item.event,item) end
            end
        end
        page.list.SetItems(items,(page.query~="" or counts.all>0) and A.L("journalNoMatch") or A.L("journalNone"))
        selected=selected or first
        if selected then
            page.selectedEvent=selected.event;page.selectedTitle=selected.title;page.selectedAction=selected.openAction
        else page.selectedEvent=nil;page.selectedTitle=nil;page.selectedAction=nil end
        selectedDetail()
    end
end
