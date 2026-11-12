local _, A = ...
-- The Overview page: who you are playing, how far the level is, four figures, a chart of the last two weeks and the latest things that happened.
local text = {
    en = {
        sub_overview = "How your character is doing: level, progress and what you did lately.",
        dashQuests = "Quests completed", dashRuns = "Dungeons completed", dashPlaces = "Areas visited", dashEvents = "Records kept",
        dashToday = "+%d today", dashNothingToday = "nothing today", dashPending = "%d waiting for the web",
        dashXP = "Experience", dashMoney = "Money", dashMaxLevel = "Maximum level", dashChart = "Activity in the last 14 days", dashRecent = "Recent activity",
        chartQuests = "Quests", chartLoot = "Loot and crafts", chartPlaces = "Places", chartRuns = "Dungeons",
        dashTab_activity = "Activity", dashTab_areas = "Areas", dashTab_loot = "Loot",
        dashTitle_activity = "Recent activity", dashTitle_areas = "Busiest areas", dashTitle_loot = "Latest loot", dashAreaCount = "%d records",
    },
    cs = {
        sub_overview = "Jak se postavě daří: úroveň, postup a co jsi dělal v poslední době.",
        dashQuests = "Splněné questy", dashRuns = "Dokončené dungeony", dashPlaces = "Navštívené oblasti", dashEvents = "Uložené záznamy",
        dashToday = "+%d dnes", dashNothingToday = "dnes nic", dashPending = "%d čeká na web",
        dashXP = "Zkušenosti", dashMoney = "Peníze", dashMaxLevel = "Maximální úroveň", dashChart = "Aktivita za posledních 14 dní", dashRecent = "Poslední aktivita",
        chartQuests = "Questy", chartLoot = "Loot a výroba", chartPlaces = "Místa", chartRuns = "Dungeony",
        dashTab_activity = "Aktivita", dashTab_areas = "Oblasti", dashTab_loot = "Loot",
        dashTitle_activity = "Poslední aktivita", dashTitle_areas = "Nejaktivnější oblasti", dashTitle_loot = "Poslední loot", dashAreaCount = "záznamů: %d",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

-- which series of the chart an event counts in
local SERIES = {["quest.turned_in"] = 1, ["loot.received"] = 2, ["craft.result"] = 2, ["zone.visited"] = 3, ["instance.entered"] = 4}
local SERIES_KEYS = {"chartQuests", "chartLoot", "chartPlaces", "chartRuns"}

local function dayKey(at) return A.Call(date, "%Y%m%d", at) or tostring(math.floor(at / 86400)) end

--- Events counted per day for the last `days` days (today last): {{key, at, label, values = {quests, loot, places, runs}, total}}.
function A.ActivityByDay(days)
    days = days or 14
    local now = A.Now()
    local list, index = {}, {}
    for i = days - 1, 0, -1 do
        local at = now - i * 86400
        local key = dayKey(at)
        if not index[key] then
            list[#list + 1] = {key = key, at = at, label = A.Call(date, "%d.%m.", at) or "", values = {0, 0, 0, 0}, total = 0}
            index[key] = list[#list]
        end
    end
    local cutoff, old = now - (days + 1) * 86400, 0
    local events = A.db.events
    for i = #events, 1, -1 do
        local e = events[i]
        local at = A.Number(e.observedAt, 0)
        if at and at < cutoff then
            old = old + 1
            if old > 100 then break end   -- the events are in time order: nothing newer is left
        elseif at then
            local series, day = SERIES[e.kind], index[dayKey(at)]
            if series and day then day.values[series] = day.values[series] + 1; day.total = day.total + 1 end
        end
    end
    return list
end

--- The areas the character did most in (quests, loot, crafts, visits): {{label, value}} longest first.
function A.TopAreas(kit, limit)
    local counts, names = {}, {}
    for _, e in ipairs(A.db.events) do
        local p = type(e.payload) == "table" and e.payload or {}
        local id = A.Number(p.mapId, 1, 100000)
        if id and A.JournalCategory(e.kind) then
            counts[id] = (counts[id] or 0) + 1
            if not names[id] and A.Text(p.mapName, 80) then names[id] = p.mapName end
        end
    end
    local rows = {}
    for id, count in pairs(counts) do rows[#rows + 1] = {id = id, label = kit.plain(names[id] or kit.mapName(id)), value = count} end
    table.sort(rows, function(a, b) if a.value == b.value then return a.id < b.id end return a.value > b.value end)
    for i = #rows, (limit or 8) + 1, -1 do rows[i] = nil end
    return rows
end

--- The items looted most recently, each once with the amount: {{itemId, icon, count, label}}.
function A.RecentLoot(kit, limit)
    local order, totals = {}, {}
    for i = #A.db.events, 1, -1 do
        local e = A.db.events[i]
        local p = type(e.payload) == "table" and e.payload or {}
        local id = e.kind == "loot.received" and A.Number(p.itemId, 1, 100000000)
        if id then
            if not totals[id] then totals[id] = 0; order[#order + 1] = id end
            totals[id] = totals[id] + (A.Number(p.quantity, 1) or 1)
        end
    end
    local cells = {}
    for i = 1, math.min(#order, limit or 30) do
        local id = order[i]
        cells[i] = {itemId = id, icon = kit.itemIcon(id), count = totals[id], label = "Item #" .. id}
    end
    return cells
end

local function grouped(n)
    local digits = tostring(math.floor(tonumber(n) or 0)):reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (digits:gsub("^ ", ""))
end

function A.BuildOverviewPage(page, kit)
    local C, label = kit.C, kit.label
    local ink = {0.20, 0.12, 0.055}
    local muted = {0.36, 0.26, 0.14}
    local heading = {0.42, 0.23, 0.055}
    A.overviewPage = page
    kit.PageHeader(page, "overview")
    page.columns = kit.Columns(page, {2, 4}, 12)
    page.columns:SetPoint("TOPLEFT", 0, -54); page.columns:SetPoint("BOTTOMRIGHT")

    -- A character dossier, with a portrait and ruled journal entries rather than four dashboard tiles.
    local hero = CreateFrame("Frame", nil, page.columns.cells[1]); hero:SetAllPoints(page.columns.cells[1])
    A.NativeParchment(hero, C); page.hero = hero
    page.portrait = hero:CreateTexture(nil, "ARTWORK"); page.portrait:SetSize(54, 54); page.portrait:SetPoint("TOPLEFT", 12, -14)
    page.heroClass = hero:CreateTexture(nil, "OVERLAY"); page.heroClass:SetSize(22, 22); page.heroClass:SetPoint("BOTTOMRIGHT", page.portrait, "BOTTOMRIGHT", 2, -2)
    page.heroRace = hero:CreateTexture(nil, "OVERLAY"); page.heroRace:SetSize(20, 20); page.heroRace:SetPoint("BOTTOMLEFT", page.portrait, "BOTTOMLEFT", -2, -2)
    page.heroName = label(hero, 17, heading); page.heroName:SetPoint("TOPLEFT", 76, -18); page.heroName:SetPoint("TOPRIGHT", -12, -18); page.heroName:SetWordWrap(false)
    page.heroSub = label(hero, 11, ink); page.heroSub:SetPoint("TOPLEFT", 76, -41); page.heroSub:SetPoint("TOPRIGHT", -12, -41); page.heroSub:SetHeight(36)
    page.xpLabel = label(hero, 10, muted); page.xpLabel:SetPoint("TOPLEFT", 12, -90); page.xpLabel:SetPoint("TOPRIGHT", -12, -90)
    page.xpBar = kit.ProgressBar(hero, C.gold, 8); page.xpBar:SetPoint("TOPLEFT", 12, -110); page.xpBar:SetPoint("TOPRIGHT", -12, -110)
    page.dossierTitle = label(hero, 13, heading); page.dossierTitle:SetPoint("TOPLEFT", 12, -132)
    local rule = hero:CreateTexture(nil, "BORDER"); rule:SetPoint("TOPLEFT", 12, -155); rule:SetPoint("TOPRIGHT", -12, -155); rule:SetHeight(1); kit.paint(rule, heading, 0.4)
    page.stats = {}
    for i, icon in ipairs({kit.ICON.questDone, kit.ICON.run, kit.ICON.places, kit.ICON.overview}) do
        local entry = CreateFrame("Frame", nil, hero); entry:SetPoint("TOPLEFT", 12, -152-(i-1)*24); entry:SetPoint("TOPRIGHT", -12, -152-(i-1)*24); entry:SetHeight(22)
        entry.icon = entry:CreateTexture(nil, "ARTWORK"); entry.icon:SetSize(18, 18); entry.icon:SetPoint("LEFT"); kit.setIcon(entry.icon, icon)
        entry.caption = label(entry, 10, ink); entry.caption:SetPoint("LEFT", entry.icon, "RIGHT", 6, 0); entry.caption:SetPoint("RIGHT", -45, 0); entry.caption:SetWordWrap(false)
        entry.value = label(entry, 15, heading); entry.value:SetPoint("RIGHT"); entry.value:SetJustifyH("RIGHT")
        entry.delta = label(entry, 10, muted); entry.delta:Hide()
        page.stats[i] = entry
    end
    page.moneyLabel = label(hero, 11, muted); page.moneyLabel:SetPoint("BOTTOMLEFT", 12, 38)
    page.money = label(hero, 13, ink); page.money:SetPoint("BOTTOMLEFT", 12, 17)
    page.warning = label(hero, 10, C.red); page.warning:SetPoint("BOTTOMRIGHT", -12, 17)

    local right = page.columns.cells[2]
    local recent = kit.Card(right); recent:SetPoint("TOPLEFT"); recent:SetPoint("TOPRIGHT"); recent:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 162)
    page.recentTitle = label(recent, 14, C.gold); page.recentTitle:SetPoint("TOPLEFT", 12, -12)
    page.recentMode, page.recentChips = "activity", {}
    local previous
    for _, key in ipairs({"activity", "areas", "loot"}) do
        local chip = kit.Chip(recent, function() page.recentMode = key; A.RefreshUI() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 5, 0) else chip:SetPoint("TOPLEFT", 12, -36) end
        previous = chip; page.recentChips[key] = chip
    end
    local inner = CreateFrame("Frame", nil, recent); inner:SetPoint("TOPLEFT", 6, -66); inner:SetPoint("BOTTOMRIGHT", -6, 7)
    page.list = kit.ListView(inner, 0)
    page.areas = kit.BarList(inner); page.areas:SetPoint("TOPLEFT", 6, -3); page.areas:SetPoint("BOTTOMRIGHT", -6, 0)
    page.loot = kit.IconGrid(inner, 38, 6)
    local chart = CreateFrame("Frame", nil, right); chart:SetPoint("BOTTOMLEFT"); chart:SetPoint("BOTTOMRIGHT"); chart:SetHeight(150)
    A.NativeParchment(chart, C)
    page.chartTitle = label(chart, 12, heading); page.chartTitle:SetPoint("TOPLEFT", 12, -9)
    page.legend = kit.Legend(chart); page.legend:SetPoint("TOPLEFT", 12, -29)
    page.chart = kit.BarChart(chart); page.chart:SetPoint("TOPLEFT", 12, -50); page.chart:SetPoint("BOTTOMRIGHT", -12, 8)
    local colors = {C.gold, C.green, C.sky, C.peach}
    function page.Refresh()
        page.columns.Layout()
        local db, c = A.db, A.Character()
        if c then
            kit.classIcon(page.heroClass, c.classId); kit.raceIcon(page.heroRace, c.raceId); page.heroRace:Show()
            if type(SetPortraitTexture) == "function" then pcall(SetPortraitTexture, page.portrait, "player") else kit.classIcon(page.portrait, c.classId) end
            page.heroName:SetText(kit.plain(c.name)); page.heroSub:SetText(kit.identityText(c).."\n"..kit.plain(c.realm))
        else
            kit.setIcon(page.portrait, kit.ICON.npc); page.heroName:SetText(A.L("unknown")); page.heroSub:SetText("")
        end
        local xp, maximum = A.Number(A.Call(UnitXP, "player"), 0), A.Number(A.Call(UnitXPMax, "player"), 1)
        page.xpBar:SetShown(xp ~= nil and maximum ~= nil)
        page.xpLabel:SetText(xp and maximum and string.format("%s  %s / %s", A.L("dashXP"), grouped(xp), grouped(maximum)) or A.L("dashMaxLevel"))
        if xp and maximum then page.xpBar.Set(xp/maximum, C.gold) end
        page.dossierTitle:SetText(A.db.settings.language == "cs" and "Kniha dobrodružství" or "Adventure record")
        local quests, runs = 0, 0
        for _, event in ipairs(db.events) do if event.kind == "quest.turned_in" then quests = quests + 1 end end
        for _, run in ipairs(db.runs) do if c and run.character and run.character.id == c.id and run.status == "completed" then runs = runs + 1 end end
        local figures = {quests, runs, #A.PlaceSummaries(), #db.events}
        for i, key in ipairs({"dashQuests", "dashRuns", "dashPlaces", "dashEvents"}) do page.stats[i].value:SetText(grouped(figures[i])); page.stats[i].caption:SetText(A.L(key)) end
        local money = A.Number(A.Call(GetMoney), 0)
        page.moneyLabel:SetText(money and A.L("dashMoney") or ""); page.money:SetText(money and A.FormatMoney(money) or "")
        page.warning:SetText((A.storageFull or A.exportFull) and A.L("capped") or "")
        local names = {}; for i, key in ipairs(SERIES_KEYS) do names[i] = A.L(key) end
        page.chartTitle:SetText(A.L("dashChart")); page.legend.Set(colors, names); page.chart.SetData(A.ActivityByDay(14), colors, names)
        for _, entry in ipairs(page.legend.items) do entry.text:SetTextColor(unpack(muted)) end
        if page.chart.topText then page.chart.topText:SetTextColor(unpack(muted)); page.chart.midText:SetTextColor(unpack(muted)) end
        local mode = page.recentMode
        for key, chip in pairs(page.recentChips) do chip.SetLabel(A.L("dashTab_"..key)); chip.SetOn(mode == key) end
        page.recentTitle:SetText(A.L("dashTitle_"..mode)); page.list:SetShown(mode == "activity"); page.areas:SetShown(mode == "areas"); page.loot:SetShown(mode == "loot")
        if mode == "areas" then page.areas.SetRows(A.TopAreas(kit, 8), A.L("noData"))
        elseif mode == "loot" then page.loot.SetCells(A.RecentLoot(kit, 30), A.L("noData"))
        else
            local items, run = {}, A.ActiveRun(); if run then items[1] = kit.runItem(run, true) end
            for i=#db.events,1,-1 do if #items>=30 then break end; if A.JournalCategory(db.events[i].kind) then items[#items+1] = kit.eventItem(db.events[i]) end end
            page.list.SetItems(items, A.L("noData"))
        end
    end
end

if C_Timer and type(C_Timer.NewTicker) == "function" then
    -- experience and money change without any event of ours: redraw now and then while the page is open
    C_Timer.NewTicker(2, function() if A.RefreshUI and A.OverviewShown and A.OverviewShown() then A.RefreshUI() end end)
end
