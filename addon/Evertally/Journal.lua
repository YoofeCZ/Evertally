local _, A = ...
-- The Journal page: the story of the character, day by day, with filters and a search. The Quests filter turns into a quest log:
-- one row per quest, with where it stands (open, completed, dropped).
local text = {
    en = {
        journal = "Journal", sub_journal = "Everything that happened to your character, day by day. Search by name, filter by kind.",
        journalAll = "All", journalQuests = "Quests", journalLoot = "Loot", journalPlaces = "Places", journalLevel = "Levels", journalRuns = "Dungeons",
        journalSearch = "Search…", journalCount = "%d records", journalQuestState = "%d open  ·  %d completed  ·  %d dropped",
        journalToday = "Today", journalYesterday = "Yesterday", journalNone = "Nothing here yet. Play, and the journal fills itself.", journalNoMatch = "Nothing matches.",
        jhKind = "Kind", jhWhen = "When", jhWhere = "Where", jhAmount = "Amount", jhXp = "Experience", jhMoney = "Money", jhDuration = "Time",
        jhLevel = "Level", jhPick = "Pick a record", jhPickNote = "Choose a record on the left to see it here.", jhMap = "Show on the map",
    },
    cs = {
        journal = "Deník", sub_journal = "Všechno, co se tvé postavě stalo, den po dni. Hledej podle názvu, filtruj podle druhu.",
        journalAll = "Vše", journalQuests = "Questy", journalLoot = "Loot", journalPlaces = "Místa", journalLevel = "Levely", journalRuns = "Dungeony",
        journalSearch = "Hledat…", journalCount = "Záznamů: %d", journalQuestState = "Rozpracováno %d  ·  splněno %d  ·  opuštěno %d",
        journalToday = "Dnes", journalYesterday = "Včera", journalNone = "Zatím tu nic není. Hraj a deník se vyplní sám.", journalNoMatch = "Nic nevyhovuje.",
        jhKind = "Druh", jhWhen = "Kdy", jhWhere = "Kde", jhAmount = "Množství", jhXp = "Zkušenosti", jhMoney = "Peníze", jhDuration = "Čas",
        jhLevel = "Level", jhPick = "Vyber záznam", jhPickNote = "Vyber vlevo záznam a uvidíš ho tady.", jhMap = "Ukázat na mapě",
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

-- ---------------------------------------------------------------- the Journal in the hub (HubKit.lua: the Database's look)
-- The kinds' glyphs and colours, as the Database draws its kinds.
local LOOK = {
    ["quest.accepted"] = {"icon-accept", "quest"}, ["quest.turned_in"] = {"icon-turnin", "quest"}, ["quest.abandoned"] = {"icon-accept", "textMuted"},
    ["loot.received"] = {"icon-use", "item"}, ["craft.result"] = {"icon-craft", "item"}, ["zone.visited"] = {"icon-explore", "place"},
    ["character.level"] = {"icon-level", "accent"}, ["instance.entered"] = {"icon-dungeon", "dungeon"}, ["run.finished"] = {"icon-kill", "dungeon"},
    ["run.interrupted"] = {"icon-kill", "textMuted"}, ["raid.encounter_finished"] = {"icon-kill", "dungeon"},
}
local function itemLook(id)
    id = tonumber(id)
    if not id then return nil end
    local icon = (C_Item and C_Item.GetItemIconByID and A.Call(C_Item.GetItemIconByID, id)) or (GetItemIcon and A.Call(GetItemIcon, id))
    local quality = select(3, A.Call(GetItemInfo, id))
    local g = rawget(_G, "EvertallyGuide")
    local LK = g and g.UI and g.UI.Lookup
    local rgb
    if quality and LK and LK.QualityColor then local r, gg, b = LK.QualityColor(quality); if r then rgb = {r, gg, b} end end
    return icon, rgb
end

local function buildHub(page, kit)
    local HK = A.HubKit
    local g = HK.Guide()
    local W = g.Widgets
    local pad = (W.SHELL and W.SHELL.pad or 32) - 12
    HK.Bleed(page)
    A.journalPage = page
    page.hub = true
    page.filter, page.query = "all", ""
    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -HK.DETAIL_W, 0)
    page.search = HK.Search(left, A.L("journalSearch"), function(text)
        if text ~= page.query then page.query = text; page.selectedEvent = nil; page.Refresh() end
    end)
    page.search:SetPoint("TOPLEFT", left, "TOPLEFT", pad, -14)
    page.search:SetPoint("TOPRIGHT", left, "TOPRIGHT", -150, -14)
    page.count = W.Text(left, "small", "textMuted")
    page.count:SetPoint("TOPRIGHT", left, "TOPRIGHT", -pad, -22)
    page.count:SetWidth(130)
    page.count:SetJustifyH("RIGHT")
    if W.SetSearchPlaceholder then W.SetSearchPlaceholder(page.search, A.L("journalSearch")) end
    page.list = HK.List(left)
    page.list.scroll:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -54)
    page.list.scroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -4, 4)
    page.details = HK.Details(page)
    page.hubTabs = function()
        local tabs = {}
        for _, key in ipairs(FILTERS) do tabs[#tabs + 1] = {key = key, label = A.L("journal" .. key:sub(1, 1):upper() .. key:sub(2))} end
        return tabs
    end
    page.hubTab = function() return page.filter end
    page.OnHubTab = function(key) page.filter = key; page.selectedEvent = nil end

    local function look(e)
        local p = type(e.payload) == "table" and e.payload or {}
        local l = LOOK[e.kind] or {"icon-note", "text"}
        local spec = {glyph = l[1], color = l[2]}
        if p.itemId and (e.kind == "loot.received" or e.kind == "craft.result") then
            local icon, rgb = itemLook(p.itemId)
            spec.icon, spec.rgb = icon, rgb
        end
        return spec, p
    end
    local function detail(e, item)
        if not e then return page.details.Empty(A.L("jhPick"), A.L("jhPickNote")) end
        local spec, p = look(e)
        spec.title = item and item.title or A.L(e.kind)
        spec.sub = A.L(e.kind) .. "  \194\183  " .. kit.stamp(e.observedAt)
        spec.map = tonumber(p.mapId)
        spec.facts = {
            {A.L("jhKind"), A.L(e.kind)},
            {A.L("jhWhen"), kit.stamp(e.observedAt)},
            {A.L("jhWhere"), p.mapId and kit.mapName(p.mapId) or nil},
            {A.L("jhLevel"), e.kind == "character.level" and p.level and tostring(p.level) or nil},
            {A.L("jhAmount"), (tonumber(p.quantity) or 1) > 1 and ("x" .. p.quantity) or nil},
            {A.L("jhXp"), p.xp and (tostring(p.xp) .. " XP") or nil},
            {A.L("jhMoney"), p.money and A.FormatMoney(p.money) or nil},
            {A.L("jhDuration"), p.durationMs and kit.duration(p.durationMs) or nil},
        }
        if p.questId then spec.button = {text = A.L("openDatabase"), onClick = function() A.OpenDatabaseEntry("quest", p.questId) end}
        elseif p.itemId then spec.button = {text = A.L("openDatabase"), onClick = function() A.OpenDatabaseEntry("item", p.itemId) end}
        elseif p.mapId then
            spec.button = {text = A.L("jhMap"), onClick = function()
                local C = g.Compat
                if C and C.OpenWorldMap then pcall(C.OpenWorldMap, tonumber(p.mapId)) end
            end}
        end
        page.details.Set(spec)
    end
    function page.Refresh()
        local items, counts, matches, states = A.JournalItems(kit, page.filter, page.query)
        if page.filter == "quests" then page.count:SetText(string.format(A.L("journalQuestState"), states.open, states.done, states.dropped))
        else page.count:SetText(string.format(A.L("journalCount"), matches)) end
        local entries, first, selectedItem = {}, nil, nil
        for _, item in ipairs(items) do
            if item.heading then
                entries[#entries + 1] = {folder = item.heading, count = item.right}
            elseif item.event then
                local e = item.event
                local spec, p = look(e)
                local clock = A.Call(date, "%H:%M", A.Number(e.observedAt, 0) or 0) or ""
                spec.key, spec.title = e, item.title
                spec.sub = ((tonumber(p.quantity) or 1) > 1 and ("x" .. p.quantity .. "  \194\183  ") or "") .. clock
                spec.tip = {A.L(e.kind), p.mapId and kit.mapName(p.mapId) or nil}
                spec.onClick = function() page.selectedEvent = e; page.Refresh() end
                entries[#entries + 1] = spec
                first = first or item
                if e == page.selectedEvent then selectedItem = item end
            end
        end
        selectedItem = selectedItem or first
        page.selectedEvent = selectedItem and selectedItem.event or nil
        page.list.Set(entries, page.selectedEvent)
        if #entries == 0 then
            page.details.Empty(A.L("jhPick"), (page.query ~= "" or counts.all > 0) and A.L("journalNoMatch") or A.L("journalNone"))
        else
            detail(page.selectedEvent, selectedItem)
        end
    end
end

function A.BuildJournalPage(page, kit)
    -- In the guide's hub: the Database's look (HubKit.lua)
    if A.HubKit and A.HubKit.Ready(page) then return buildHub(page, kit) end
    local C = kit.C
    local ink, muted = C.text, C.mist
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
    page.metaMeasure=kit.label(page,10,C.mist);page.metaMeasure:Hide()
    local reader=CreateFrame("Frame",nil,page.columns.cells[2]);reader:SetAllPoints(page.columns.cells[2]);A.NativeParchment(reader,C);page.reader=reader
    page.readerBody=CreateFrame("Frame",nil,reader);page.readerBody:SetPoint("TOPLEFT",14,-14);page.readerBody:SetPoint("BOTTOMRIGHT",-14,52)
    page.readerTitle=kit.label(page.readerBody,20,C.bright or C.gold);page.readerTitle:SetPoint("TOPLEFT");page.readerTitle:SetPoint("TOPRIGHT");page.readerTitle:SetJustifyH("LEFT")
    page.readerDate=kit.label(page.readerBody,10,muted);page.readerDate:SetPoint("TOPLEFT",0,-48);page.readerDate:SetPoint("TOPRIGHT",0,-48)
    page.readerText=kit.label(page.readerBody,13,ink);page.readerText:SetPoint("TOPLEFT",0,-88);page.readerText:SetPoint("BOTTOMRIGHT");page.readerText:SetJustifyV("TOP")
    local readerRule=page.readerBody:CreateTexture(nil,"BORDER");readerRule:SetPoint("TOPLEFT",0,-72);readerRule:SetPoint("TOPRIGHT",0,-72);readerRule:SetHeight(1);kit.paint(readerRule,C.line,0.8)
    page.readerRule=readerRule
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
        page.readerTitle:SetShown(not questCard);page.readerDate:SetShown(not questCard);page.readerText:SetShown(not questCard);page.readerRule:SetShown(not questCard)
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
        local items,counts,matches,states=A.JournalItems(kit,page.filter,page.query)
        for _,key in ipairs(FILTERS) do local chip=page.chips[key];chip.SetLabel(A.L("journal"..key:sub(1,1):upper()..key:sub(2)));chip.SetOn(page.filter==key) end
        page.search.hint:SetText(A.L("journalSearch"))
        local width=math.max(240,tonumber(page:GetWidth()) or 640)
        local x,y=0,-62
        for _,key in ipairs(FILTERS) do
            local chip=page.chips[key];local w=tonumber(chip:GetWidth()) or 60
            if x>0 and x+w>width then x,y=0,y-30 end
            chip:ClearAllPoints();chip:SetPoint("TOPLEFT",x,y);x=x+w+6
        end
        page.search:ClearAllPoints();page.search:SetPoint("TOPLEFT",0,y-36);page.search:SetWidth(math.min(260,width*.48))
        page.summary:ClearAllPoints();page.summary:SetPoint("TOPLEFT",page.search,"TOPRIGHT",14,-6);page.summary:SetPoint("TOPRIGHT",page,"TOPRIGHT",-4,y-42);page.summary:SetHeight(16);page.summary:SetWordWrap(false)
        page.columns:ClearAllPoints();page.columns:SetPoint("TOPLEFT",0,y-76);page.columns:SetPoint("BOTTOMRIGHT");page.columns.Layout()
        if page.filter=="quests" then page.summary:SetText(string.format(A.L("journalQuestState"),states.open,states.done,states.dropped)) else page.summary:SetText(string.format(A.L("journalCount"),matches)) end
        local first,selected
        for _,item in ipairs(items) do
            if item.sub then
                local text=item.sub
                local available=math.max(55,(tonumber(page.columns.cells[1]:GetWidth()) or 300)-76)
                page.metaMeasure:SetText(text)
                if (page.metaMeasure:GetStringWidth() or 0)>available then
                    repeat
                        text=text:match("^(.*)[\1-\127\194-\244][\128-\191]*$") or ""
                        page.metaMeasure:SetText(text.."...")
                    until text=="" or (page.metaMeasure:GetStringWidth() or 0)<=available
                    item.sub=text.."..."
                end
            end
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
