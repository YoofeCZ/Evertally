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
    A.overviewPage = page   -- read by the layout preview
    kit.PageHeader(page, "overview")

    -- the character
    local hero = kit.Card(page, C.lilac)
    hero:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -54); hero:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -54); hero:SetHeight(84)
    page.hero = hero
    page.heroTint = hero:CreateTexture(nil, "BACKGROUND"); page.heroTint:SetPoint("TOPLEFT"); page.heroTint:SetPoint("BOTTOMRIGHT", hero, "BOTTOM", 0, 0)
    page.heroClass = hero:CreateTexture(nil, "ARTWORK"); page.heroClass:SetSize(48, 48); page.heroClass:SetPoint("LEFT", 16, 0)
    page.heroRace = hero:CreateTexture(nil, "OVERLAY"); page.heroRace:SetSize(22, 22); page.heroRace:SetPoint("BOTTOMRIGHT", page.heroClass, "BOTTOMRIGHT", 6, -4)
    page.heroName = label(hero, 18, C.text); page.heroName:SetPoint("TOPLEFT", page.heroClass, "TOPRIGHT", 16, -2); page.heroName:SetWordWrap(false)
    page.heroSub = label(hero, 11, C.mist); page.heroSub:SetPoint("TOPLEFT", page.heroName, "BOTTOMLEFT", 0, -5); page.heroSub:SetWordWrap(false)
    local right = CreateFrame("Frame", nil, hero); right:SetPoint("TOPRIGHT", -16, -14); right:SetPoint("BOTTOMRIGHT", -16, 14); right:SetWidth(260)
    page.xpLabel = label(right, 10, C.mist); page.xpLabel:SetPoint("TOPLEFT"); page.xpLabel:SetPoint("TOPRIGHT")
    page.xpBar = kit.ProgressBar(right, C.lilac, 8); page.xpBar:SetPoint("TOPLEFT", 0, -17); page.xpBar:SetPoint("TOPRIGHT", 0, -17)
    page.moneyLabel = label(right, 10, C.mist); page.moneyLabel:SetPoint("TOPLEFT", 0, -38)
    page.money = label(right, 13, C.text); page.money:SetPoint("TOPRIGHT", 0, -36); page.money:SetJustifyH("RIGHT")
    hero:SetScript("OnSizeChanged", function(_, width)
        width = tonumber(width) or hero:GetWidth() or 600
        local rightWidth = math.max(180, math.min(340, math.floor(width * 0.42)))
        right:SetWidth(rightWidth)
        local nameWidth = math.max(80, width - 80 - rightWidth - 36)
        page.heroName:SetWidth(nameWidth); page.heroSub:SetWidth(nameWidth)
    end)

    -- four figures
    local row = kit.Columns(page, {1, 1, 1, 1}, 10)
    row:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -10); row:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, -10); row:SetHeight(70)
    page.stats = {}
    for i, def in ipairs({{kit.ICON.questDone, C.lilac}, {kit.ICON.run, C.peach}, {kit.ICON.places, C.sky}, {kit.ICON.overview, C.green}}) do
        local card = kit.Stat(row.cells[i], def[1], def[2]); card:SetAllPoints(row.cells[i]); page.stats[i] = card
    end

    -- the chart and the latest things
    local lower = kit.Columns(page, {3, 2}, 10)
    lower:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -10); lower:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    local chartCard = kit.Card(lower.cells[1]); chartCard:SetAllPoints(lower.cells[1])
    page.chartTitle = label(chartCard, 13, C.text); page.chartTitle:SetPoint("TOPLEFT", 14, -12)
    page.legend = kit.Legend(chartCard); page.legend:SetPoint("TOPLEFT", 14, -33)
    page.chart = kit.BarChart(chartCard); page.chart:SetPoint("TOPLEFT", 14, -54); page.chart:SetPoint("BOTTOMRIGHT", -14, 10)
    local recentCard = kit.Card(lower.cells[2]); recentCard:SetAllPoints(lower.cells[2])
    page.recentTitle = label(recentCard, 13, C.text); page.recentTitle:SetPoint("TOPLEFT", 14, -12)
    page.recentMode, page.recentChips = "activity", {}
    local previousChip
    for _, key in ipairs({"activity", "areas", "loot"}) do
        local chip = kit.Chip(recentCard, function() page.recentMode = key; A.RefreshUI() end)
        if previousChip then chip:SetPoint("LEFT", previousChip, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", recentCard, "TOPLEFT", 10, -34) end
        page.recentChips[key] = chip; previousChip = chip
    end
    local inner = CreateFrame("Frame", nil, recentCard); inner:SetPoint("TOPLEFT", 8, -66); inner:SetPoint("BOTTOMRIGHT", -8, 8)
    page.list = kit.ListView(inner, 0)
    page.areas = kit.BarList(inner); page.areas:SetPoint("TOPLEFT", inner, "TOPLEFT", 6, -4); page.areas:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", -6, 0)
    page.loot = kit.IconGrid(inner, 38, 6)
    page.warning = label(recentCard, 10, C.peach); page.warning:SetPoint("TOPRIGHT", -14, -15); page.warning:SetJustifyH("RIGHT")

    local colors = {C.lilac, C.green, C.sky, C.peach}
    function page.Refresh()
        row.Layout(); lower.Layout()   -- the cells are sized from the page's width, which is known by now
        local db, out = A.db, A.ExportStore()
        local c = A.Character()
        if c then
            kit.classIcon(page.heroClass, c.classId); kit.raceIcon(page.heroRace, c.raceId); page.heroRace:Show()
            page.heroName:SetText(kit.plain(c.name))
            local cc = kit.classColor(c.classId); page.heroName:SetTextColor(cc[1], cc[2], cc[3])
            kit.alphaGradient(page.heroTint, "HORIZONTAL", cc[1], cc[2], cc[3], 0.30, cc[1], cc[2], cc[3], 0)
            if page.hero.accentLine then kit.paint(page.hero.accentLine, cc, 0.9) end
            page.heroSub:SetText(kit.identityText(c) .. "  ·  " .. kit.plain(c.realm))
        else
            kit.setIcon(page.heroClass, kit.ICON.npc); page.heroRace:Hide()
            page.heroName:SetText(A.L("unknown")); page.heroName:SetTextColor(C.text[1], C.text[2], C.text[3]); page.heroSub:SetText("")
        end
        local xp, xpMax = A.Number(A.Call(UnitXP, "player"), 0), A.Number(A.Call(UnitXPMax, "player"), 1)
        if xp and xpMax then
            page.xpBar:Show(); page.xpBar.Set(xp / xpMax, C.lilac)
            page.xpLabel:SetText(string.format("%s   %s / %s  ·  %d %%", A.L("dashXP"), grouped(xp), grouped(xpMax), math.floor(xp / xpMax * 100)))
        else
            page.xpBar:Hide(); page.xpLabel:SetText("")
        end
        local copper = A.Number(A.Call(GetMoney), 0)
        page.moneyLabel:SetText(copper and A.L("dashMoney") or ""); page.money:SetText(copper and A.FormatMoney(copper) or "")

        local days = A.ActivityByDay(14)
        local today = days[#days]
        local quests, runs = 0, 0
        for _, e in ipairs(db.events) do if e.kind == "quest.turned_in" then quests = quests + 1 end end
        for _, run in ipairs(db.runs) do if run.character and c and run.character.id == c.id and run.status == "completed" then runs = runs + 1 end end
        local places = #A.PlaceSummaries()
        local pending = out and #out.events or 0
        local figures = {quests, runs, places, #db.events}
        local captions = {"dashQuests", "dashRuns", "dashPlaces", "dashEvents"}
        for i, card in ipairs(page.stats) do card.value:SetText(grouped(figures[i])); card.caption:SetText(A.L(captions[i])) end
        local function delta(card, value, good)
            if value > 0 then card.delta:SetText(string.format(A.L("dashToday"), value)); card.delta:SetTextColor(good[1], good[2], good[3])
            else card.delta:SetText(A.L("dashNothingToday")); card.delta:SetTextColor(C.faint[1], C.faint[2], C.faint[3]) end
        end
        delta(page.stats[1], today.values[1], C.green)
        delta(page.stats[2], today.values[4], C.green)
        delta(page.stats[3], today.values[3], C.green)
        if pending > 0 then page.stats[4].delta:SetText(string.format(A.L("dashPending"), pending)); page.stats[4].delta:SetTextColor(C.peach[1], C.peach[2], C.peach[3])
        else page.stats[4].delta:SetText("") end

        local names = {}
        for i, key in ipairs(SERIES_KEYS) do names[i] = A.L(key) end
        page.chartTitle:SetText(A.L("dashChart")); page.legend.Set(colors, names); page.chart.SetData(days, colors, names)
        local mode = page.recentMode
        for key, chip in pairs(page.recentChips) do chip.SetLabel(A.L("dashTab_" .. key)); chip.SetOn(mode == key) end
        page.recentTitle:SetText(A.L("dashTitle_" .. mode))
        page.warning:SetText((A.storageFull or A.exportFull) and A.L("capped") or "")
        page.list:SetShown(mode == "activity"); page.areas:SetShown(mode == "areas"); page.loot:SetShown(mode == "loot")
        if mode == "areas" then
            local rows = A.TopAreas(kit, 8)
            page.areas.SetRows(rows, A.L("noData"))
        elseif mode == "loot" then
            page.loot.SetCells(A.RecentLoot(kit, 30), A.L("noData"))
        else
            local items, run = {}, A.ActiveRun()
            if run then items[1] = kit.runItem(run, true) end
            for i = #db.events, 1, -1 do
                if #items >= 30 then break end
                local e = db.events[i]
                if A.JournalCategory(e.kind) then items[#items + 1] = kit.eventItem(e) end
            end
            page.list.SetItems(items, A.L("noData"))
        end
    end
end

if C_Timer and type(C_Timer.NewTicker) == "function" then
    -- experience and money change without any event of ours: redraw now and then while the page is open
    C_Timer.NewTicker(2, function() if A.RefreshUI and A.OverviewShown and A.OverviewShown() then A.RefreshUI() end end)
end
