local _, M = ...
local A = _G.Evertally
-- Building blocks the guide pages (database, dungeon journal) share: a scrolling detail made of headings, text and rows with an icon that can be
-- clicked (a quest -> the person who gives it -> his other quests -> an item -> who sells it), and the colour of an item's quality. The rows are
-- pooled, so opening one entry after another costs nothing.
local ROW_H, ICON = 46, 30
local QUALITY = {[0] = {0.62, 0.62, 0.62}, [1] = {1, 1, 1}, [2] = {0.12, 1, 0.1}, [3] = {0.25, 0.6, 1}, [4] = {0.72, 0.4, 1}, [5] = {1, 0.55, 0.1}, [6] = {0.9, 0.8, 0.5}}
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
M.guideQuestion = QUESTION

function M.QualityColor(quality) return QUALITY[tonumber(quality) or 1] or QUALITY[1] end

--- The icon of an item by id (the game's own file), and its quality (nil until the client has the item in its cache).
function M.ItemLook(id)
    local icon = A.Call(GetItemIcon, id)
    if not icon and C_Item then icon = A.Call(C_Item.GetItemIconByID, id) end
    local quality
    if C_Item and C_Item.GetItemQualityByID then quality = A.Call(C_Item.GetItemQualityByID, id) end
    if quality == nil and type(GetItemInfo) == "function" then local ok, _, _, q = pcall(GetItemInfo, id); if ok then quality = q end end
    local saved = type(M.itemGuide) == "table" and M.itemGuide[id] or nil
    return icon or (saved and saved.icon) or QUESTION, quality or (saved and saved.quality)
end

--- The name of an item: from QuestieDB when it is there, else from the game, else its number.
function M.ItemName(id)
    local saved = type(M.itemGuide) == "table" and M.itemGuide[id] or nil
    if saved and type(saved.name) == "string" then return saved.name end
    if M.Db and M.Db.Open then
        M.guideDb = M.guideDb or M.Db.Open()
        local values = M.guideDb and M.Db.Get(M.guideDb, "item", id)
        if values and type(values.name) == "string" then return values.name end
    end
    local ok, name = pcall(GetItemInfo or function() end, id)
    return ok and type(name) == "string" and name or ("#" .. tostring(id))
end

--- The game's tooltip for an item, placed by `owner`.
function M.ShowItemTooltip(owner, id, name, extra)
    if not (GameTooltip and id) then return end
    pcall(function()
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. id)
        if (GameTooltip.NumLines and GameTooltip:NumLines() or 1) == 0 then GameTooltip:SetText(name or "?") end
        if extra and extra ~= "" then GameTooltip:AddLine(extra, 0.7, 0.7, 0.78) end
        GameTooltip:Show()
    end)
end

--- A scrolling detail inside `parent`. d.Reset(); d.Head(text); d.Text(text[, color, size]); d.Link(spec); d.Done().
--- Link spec: {icon, title, sub, color, onClick, itemId, extra, badge}. The detail scrolls with the wheel and a scroll bar.
-- In the guide's hub (an Evertally page drawn there, A.InHubPage): the guide's own scroll area (its thin bar, no arrow
-- buttons), its type ladder and colours, flat rows and a flat pane, the way the hub's Database draws an entry.
local function hubGuide(parent)
    local g = rawget(_G, "EvertallyGuide")
    if not (A.InHubPage and A.InHubPage(parent)) then return nil end
    if type(g) == "table" and type(g.Widgets) == "table" and g.Widgets.Scroll and g.Widgets.SetScrollContent and type(g.Theme) == "table" and g.Theme.Font then return g end
    return nil
end
-- the guide's role for a size the pages ask for
local function hubRole(size)
    size = size or 13
    if size >= 19 then return "display" elseif size >= 15 then return "title" elseif size >= 13 then return "body" elseif size >= 12 then return "note" end
    return "small"
end

function M.GuideDetail(kit, parent)
    local C = kit.C
    local d = {kit = kit, pools = {text = {}, link = {}, badge = {}, hit = {}}, used = {text = 0, link = 0, badge = 0, hit = 0}, y = 0, width = 360}
    local hub = hubGuide(parent)
    d.hub = hub
    if hub then
        d.scroll = hub.Widgets.Scroll(parent)
        d.content = d.scroll.Child; d.content:SetSize(360, 100)
    else
        d.scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
        d.content = CreateFrame("Frame", nil, d.scroll); d.content:SetSize(360, 100); d.scroll:SetScrollChild(d.content)
    end
    d.surface = CreateFrame("Frame", nil, parent)
    d.surface:SetPoint("TOPLEFT", d.scroll, "TOPLEFT", -12, 12); d.surface:SetPoint("BOTTOMRIGHT", d.scroll, "BOTTOMRIGHT", 24, -12)
    if d.surface.SetFrameLevel and d.scroll.GetFrameLevel then d.surface:SetFrameLevel(math.max(0, (d.scroll:GetFrameLevel() or 1) - 1)) end
    if hub then hub.Widgets.Fill(d.surface, "panel")
    elseif A.NativeParchment then A.NativeParchment(d.surface, C)
    else
        kit.fill(d.surface, C.well, 1)
        kit.outline(d.surface, C.line or C.gold)
    end
    d.surface:Hide()
    d.ink, d.heading = C.text, hub and C.gold or C.bright or C.gold
    function d.SetTheme(theme)
        if theme == "parchment" then theme = "quest" end
        d.theme = theme
        d.surface:SetShown(theme == "quest")
        d.ink = C.text
        d.heading = hub and C.gold or C.bright or C.gold
    end

    local function textLine()
        d.used.text = d.used.text + 1
        local fs = d.pools.text[d.used.text]
        if not fs then fs = kit.label(d.content, 13, C.text); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP"); d.pools.text[d.used.text] = fs end
        fs:Show()
        return fs
    end
    local function linkRow()
        d.used.link = d.used.link + 1
        local row = d.pools.link[d.used.link]
        if not row then
            row = CreateFrame("Button", nil, d.content)
            row:SetHeight(ROW_H - 4)
            row.bg = kit.fill(row, C.card, 1)
            local hover = row:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(row); kit.paint(hover, C.gold, 0.12)
            row.border = row:CreateTexture(nil, "BORDER"); row.border:SetSize(ICON + 4, ICON + 4); row.border:SetPoint("LEFT", 4, 0)
            row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(ICON, ICON); row.icon:SetPoint("LEFT", 6, 0); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.title = kit.label(row, 13, C.text); row.title:SetPoint("TOPLEFT", ICON + 16, -6); row.title:SetPoint("TOPRIGHT", -34, -6); row.title:SetWordWrap(false); row.title:SetJustifyH("LEFT")
            row.sub = kit.label(row, 11, C.mist); row.sub:SetPoint("BOTTOMLEFT", ICON + 16, 5); row.sub:SetPoint("BOTTOMRIGHT", -34, 5); row.sub:SetWordWrap(false); row.sub:SetJustifyH("LEFT")
            row.badge = kit.label(row, 11, C.mist); row.badge:SetPoint("RIGHT", -10, 0); row.badge:SetJustifyH("RIGHT")
            if hub then
                hub.Theme.Font(row.title, "body"); hub.Theme.Font(row.sub, "small"); hub.Theme.Font(row.badge, "number")
                row.hubRow = true
            end
            row:SetScript("OnEnter", function(self) if self.spec and self.spec.itemId then M.ShowItemTooltip(self, self.spec.itemId, self.spec.title, self.spec.extra) end end)
            row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            row:SetScript("OnClick", function(self) if self.spec and self.spec.onClick then self.spec.onClick() end end)
            d.pools.link[d.used.link] = row
        end
        row:Show()
        return row
    end

    function d.SetWidth(width)
        d.width = math.max(160, width)
        d.content:SetWidth(d.width)
    end
    function d.Reset(identity)
        d.savedScroll = identity and d.identity == identity and (d.scroll:GetVerticalScroll() or 0) or 0
        d.identity = identity
        for _, fs in ipairs(d.pools.text) do fs:Hide() end
        for _, row in ipairs(d.pools.link) do row:Hide() end
        for _, badge in ipairs(d.pools.badge) do badge:Hide() end
        for _, hit in ipairs(d.pools.hit) do hit:Hide() end
        if d.portrait then d.portrait:Hide() end
        if d.factions then for _, icon in ipairs(d.factions) do icon:Hide() end end
        d.used.text, d.used.link, d.used.badge, d.used.hit, d.y = 0, 0, 0, 0, 0
    end
    function d.Text(value, color, size, width)
        local fs = textLine()
        fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", d.content, "TOPLEFT", 0, -d.y); fs:SetWidth(width or d.width)
        if hub then hub.Theme.Font(fs, hubRole(size)) else fs:SetFont(kit.fontPath(), size or 13, "") end
        local c = color or d.ink
        fs:SetTextColor(c[1], c[2], c[3], 1)
        if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
        fs:SetText(value or "")
        -- the larger of the two: a wrapped line must never lie under the next one, whichever of them the client updates first
        d.y = d.y + math.max(16, fs:GetStringHeight() or 16, fs.GetHeight and fs:GetHeight() or 0) + 6
        return fs
    end
    function d.Head(value)
        d.y = d.y + 10
        -- in the hub: the guide's small capitals in the accent, as the Database's section heads
        if hub then
            local fs = d.Text(A.Upper and A.Upper(value or "") or value, d.heading, 14)
            hub.Theme.Font(fs, "label")
            return fs
        end
        local fs = d.Text(value, d.heading, 14)
        return fs
    end
    function d.PortraitHeader(value, texture)
        if not d.portrait then
            d.portrait = CreateFrame("Frame", nil, d.content)
            d.portrait:SetSize(50, 50)
            d.portrait.bg = kit.fill(d.portrait, C.card, 1)
            kit.outline(d.portrait, C.line or C.gold)
            d.portrait.icon = d.portrait:CreateTexture(nil, "ARTWORK"); d.portrait.icon:SetPoint("TOPLEFT", 3, -3); d.portrait.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        end
        local top = d.y
        d.portrait:Show(); d.portrait:ClearAllPoints(); d.portrait:SetPoint("TOPLEFT", 0, -top); d.portrait.icon:SetTexture(texture or QUESTION)
        local fs = d.Text(value, d.heading, 20, math.max(90, d.width - 64))
        fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", d.content, "TOPLEFT", 62, -top - 3)
        d.y = math.max(d.y, top + 56)
    end
    function d.Link(spec)
        local row = linkRow()
        row.spec = spec
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", d.content, "TOPLEFT", 0, -d.y); row:SetPoint("TOPRIGHT", d.content, "TOPRIGHT", 0, -d.y)
        row:SetHeight(ROW_H - 4)
        kit.paint(row.bg, C.card, 1); row.bg:SetAlpha(row.hubRow and 0.55 or 1)
        row.icon:ClearAllPoints(); row.icon:SetSize(ICON, ICON); row.icon:SetPoint("LEFT", 6, 0)
        row.title:ClearAllPoints(); row.title:SetPoint("TOPLEFT", ICON + 16, -6); row.title:SetPoint("TOPRIGHT", -34, -6); row.title:SetHeight(15); row.title:SetWordWrap(false)
        row.badge:ClearAllPoints(); row.badge:SetPoint("RIGHT", -10, 0); row.badge:Show()
        row.icon:SetTexture(spec.icon or QUESTION)
        local q = spec.quality
        if spec.itemId then local _,current=M.ItemLook(spec.itemId);q=current or q end
        row.border:SetShown(q ~= nil)
        if q ~= nil then local c = M.QualityColor(q); kit.paint(row.border, c, 1) end
        local c = spec.color or (q ~= nil and M.QualityColor(q)) or d.ink
        row.title:SetTextColor(c[1], c[2], c[3], 1)
        row.title:SetText(A.Plain(spec.title or "?")); row.sub:SetText(A.Plain(spec.sub or "")); row.badge:SetText(spec.badge or "")
        row.sub:SetTextColor(C.mist[1], C.mist[2], C.mist[3], 1)
        row.sub:SetShown(spec.sub ~= nil and spec.sub ~= "")
        d.y = d.y + ROW_H
        return row
    end
    -- Quest rewards use the actual quest-window shape: one or two compact cards per row, not a list of anonymous icons.
    function d.Rewards(items)
        local cols = d.width >= 300 and 2 or 1
        local gap, height = 10, 46
        local width = (d.width - gap * (cols - 1)) / cols
        for index, item in ipairs(items or {}) do
            local id = tonumber(item.id or item[1])
            if id then
                local icon, quality = M.ItemLook(id)
                local row = linkRow()
                row.spec = {itemId = id, quality = quality or item.quality, title = item.name or item[2] or M.ItemName(id), onClick = function() if A.OpenDatabaseEntry then A.OpenDatabaseEntry("item", id) end end}
                row:ClearAllPoints(); row:SetPoint("TOPLEFT", d.content, "TOPLEFT", ((index - 1) % cols) * (width + gap), -d.y - math.floor((index - 1) / cols) * (height + 6)); row:SetSize(width, height)
                kit.paint(row.bg, C.card, 1); row.bg:SetAlpha(1)
                if not row.rewardEdge then row.rewardEdge = true; kit.outline(row, C.line or C.gold) end
                row.icon:SetTexture(icon); row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", 4, 0); row.icon:SetSize(36, 36)
                row.border:SetShown(false)
                row.title:ClearAllPoints(); row.title:SetPoint("LEFT", 46, 0); row.title:SetPoint("RIGHT", -6, 0); row.title:SetHeight(34); row.title:SetWordWrap(true)
                row.title:SetText(row.spec.title)
                local color = M.QualityColor(row.spec.quality or 1); row.title:SetTextColor(color[1], color[2], color[3], 1)
                row.sub:Hide(); row.badge:Hide()
                if tonumber(item.count) and item.count > 1 then
                    row.badge:Show(); row.badge:SetText(tostring(item.count)); row.badge:ClearAllPoints(); row.badge:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 1); row.badge:SetTextColor(1, 1, 1, 1)
                end
            end
        end
        d.y = d.y + math.ceil(#(items or {}) / cols) * (height + 6)
    end
    function d.Badge(value, color, icon)
        d.used.badge = d.used.badge + 1
        local badge = d.pools.badge[d.used.badge]
        if not badge then
            badge = CreateFrame("Frame", nil, d.content)
            badge.bg = kit.fill(badge, C.card, 1)
            kit.outline(badge, C.line or C.gold)
            badge.icon = badge:CreateTexture(nil, "ARTWORK"); badge.icon:SetSize(22, 22); badge.icon:SetPoint("LEFT", 3, 0)
            badge.iconText = kit.label(badge, 10, {1, 0.93, 0.5}); badge.iconText:SetPoint("CENTER", badge.icon, "CENTER", 0, 0); badge.iconText:SetText("XP")
            badge.text = kit.label(badge, 12, {1, 1, 1}); badge.text:SetPoint("LEFT", 30, 0)
            d.pools.badge[d.used.badge] = badge
        end
        badge:Show(); badge:SetSize(math.min(d.width, 150), 30); badge:ClearAllPoints(); badge:SetPoint("TOPLEFT", 0, -d.y)
        if not icon or icon == "XP" then kit.paint(badge.icon, C.header or C.well, 1); badge.iconText:Show()
        else badge.icon:SetTexture(icon); badge.iconText:Hide() end
        badge.text:SetText(value)
        if color then kit.paint(badge.bg, color, 1) end
        d.y = d.y + 36
        return badge
    end
    function d.Done()
        local height = math.max(60, d.y + 8)
        if hub then
            hub.Widgets.SetScrollContent(d.scroll, height, d.scroll:GetHeight())
            local maximum = math.max(0, height - (d.scroll:GetHeight() or 0))
            hub.Widgets.ScrollTo(d.scroll, math.min(d.savedScroll or 0, maximum))
            return
        end
        d.content:SetHeight(height)
        local maximum = math.max(0, (d.content:GetHeight() or 0) - (d.scroll:GetHeight() or 0))
        d.scroll:SetVerticalScroll(math.min(d.savedScroll or 0, maximum))
    end
    return d
end

local questText = {
    en = {questCardNote = "Note", questCardWarning = "Watch out", questCardClass = "Only for: %s", questCardInside = "The quest starts inside the dungeon.", questCardStartItem = "Starts from an item",
        questCardFirst = "Complete first",
        questCardFrom = "Available from level %s", questCardLevel = "Level %s", questCardObjective = "Objective", questCardStarts = "Starts at", questCardTurnin = "Turn in", questCardChoose = "Choose one reward", questCardAlso = "You will also receive", questCardRewards = "Rewards", questCardNoObjective = "No objective text is recorded for this quest.", questCardChain = "Quest chain"},
    cs = {questCardNote = "Poznámka", questCardWarning = "Pozor", questCardClass = "Jen pro povolání: %s", questCardInside = "Quest začíná uvnitř dungeonu.", questCardStartItem = "Začíná předmětem",
        questCardFirst = "Nejdřív splň",
        questCardFrom = "Dostupné od úrovně %s", questCardLevel = "Úroveň %s", questCardObjective = "Cíl", questCardStarts = "Začíná u", questCardTurnin = "Odevzdat u", questCardChoose = "Vyber jednu odměnu", questCardAlso = "Dostaneš také", questCardRewards = "Odměny", questCardNoObjective = "U tohoto questu není zapsaný text cíle.", questCardChain = "Řetězec questů"},
}
for lang, values in pairs(questText) do for key, value in pairs(values) do A.locale[lang][key] = value end end

local function rewardList(list)
    local out = {}
    for _, entry in ipairs(type(list) == "table" and list or {}) do
        local id = tonumber(type(entry) == "table" and (entry.id or entry[1]) or entry)
        if id and id > 0 then
            out[#out + 1] = {id = id, name = type(entry) == "table" and entry.name or nil, quality = type(entry) == "table" and entry.quality or nil,
                count = type(entry) == "table" and (entry.count or entry[2]) or 1}
        end
    end
    return out
end

--- Normalised data shared by dungeon quests, the database and the character journal. Unknown reward grouping stays unknown.
function M.JournalQuestModel(quest)
    local model = {id = quest.id, title = quest.name or "?", requiredLevel = quest.requires, level = quest.level, faction = quest.faction, objective = quest.objective,
        starts = {}, turnin = {}, choiceRewards = {}, guaranteedRewards = {}, rewards = {}, extras = {}, xp = tonumber(quest.xp), xpBase = tonumber(quest.liveXPFallback), money = tonumber(quest.money)}
    -- with a place when Evertally's own journal knows it (the card then has a button to show it on the map)
    if type(quest.pickup) == "string" and quest.pickup ~= "" then model.starts[1] = {name = quest.pickup, spot = quest.pickupSpot} end
    if type(quest.turnin) == "string" and quest.turnin ~= "" then model.turnin[1] = {name = quest.turnin, spot = quest.turninSpot} end
    local items = {}
    for _, item in ipairs(type(quest.rewardItems) == "table" and quest.rewardItems or {}) do
        if type(item) == "table" and tonumber(item[1]) then items[#items + 1] = {id = tonumber(item[1]), name = item[2], quality = item[3], count = item[4] or 1} end
    end
    if quest.rewardChoice == true then model.choiceRewards = items elseif quest.rewardChoice == false then model.guaranteedRewards = items else model.rewards = items end
    for line in ((quest.rewards or "") .. "\n"):gmatch("([^\n]*)\n") do
        local xp = line:match("([%d, ]+)%s*[Xx][Pp]")
        if xp then
            if not model.xpBase then model.xp = tonumber((xp:gsub("[, ]", ""))); model.xpLabel = line end
            local extras = line:gsub("[%d, ]+%s*[Xx][Pp]%s*", "", 1):gsub("^%s*•%s*", ""):gsub("^%s*|%s*", "")
            if extras ~= "" then model.extras[#model.extras + 1] = extras end
        elseif line ~= "" and not line:find("^Choose") then model.extras[#model.extras + 1] = line end
    end
    if type(quest.rewardSummary) == "string" and quest.rewardSummary ~= "" then model.extras = {quest.rewardSummary} end
    for _, item in ipairs(type(quest.additionalRewardItems) == "table" and quest.additionalRewardItems or {}) do
        if type(item) == "table" and tonumber(item[1]) then model.guaranteedRewards[#model.guaranteedRewards + 1] = {id = tonumber(item[1]), name = item[2], quality = item[3], count = item[4] or 1} end
    end
    -- Evertally's own journal lists no rewards: they come from the quest facts every other quest card uses
    local extra = type(M.questDetails) == "table" and type(quest.id) == "number" and M.questDetails[quest.id] or nil
    if #model.choiceRewards == 0 and #model.guaranteedRewards == 0 and #model.rewards == 0 then
        model.choiceRewards = rewardList(extra and extra.choice); model.guaranteedRewards = rewardList(extra and extra.guaranteed)
        if #model.choiceRewards == 0 and #model.guaranteedRewards == 0 then
            model.rewards = rewardList(extra and extra.rewards or (type(M.questRewards) == "table" and type(quest.id) == "number" and M.questRewards[quest.id] or nil))
        end
    end
    if extra then
        model.xp = model.xp or tonumber(extra.xp); model.xpBase = model.xpBase or tonumber(extra.xpBase); model.money = model.money or tonumber(extra.money)
        if #model.extras == 0 and type(extra.rewardSummary) == "string" and extra.rewardSummary ~= "" then model.extras[1] = extra.rewardSummary end
    end
    -- Forever exposes a quest-id argument here. A positive cached answer is authoritative; an uncached zero is not.
    local liveXP = A.Number(A.Call(GetQuestLogRewardXP, quest.id), 1, 1000000000)
    if liveXP then model.xp, model.xpLabel = liveXP, nil end
    -- what the journal adds about doing it: a note, a warning, the class it is for, where it starts and what must come first
    model.note = type(quest.note) == "string" and quest.note ~= "" and quest.note or nil
    model.warning = type(quest.warning) == "string" and quest.warning ~= "" and quest.warning or nil
    model.classOnly = type(quest.classOnly) == "string" and quest.classOnly ~= "" and quest.classOnly or nil
    model.startsInDungeon = quest.startsInDungeon == true
    if type(quest.startObject) == "table" and type(quest.startObject[1]) == "string" then
        model.startItem = quest.startObject[1] .. (type(quest.startObject[3]) == "string" and (": " .. quest.startObject[3]) or "")
    end
    local fdj = M.Journal and M.Journal()
    local chains = type(fdj) == "table" and type(fdj.QUEST_PREREQ_CHAINS) == "table" and fdj.QUEST_PREREQ_CHAINS[quest.id]
    if type(chains) == "table" then
        model.chain, model.chainTitle = {}, "questCardFirst"
        for _, link in ipairs(chains) do
            if type(link) == "table" and tonumber(link.id) then model.chain[#model.chain + 1] = {id = tonumber(link.id), name = tostring(link.name or ("#" .. link.id))} end
        end
    end
    return model
end

function M.DatabaseQuestModel(db, id, values, detail)
    values = values or (db and M.Db.Get(db, "quest", id))
    if not values then
        local ns = M.Journal and M.Journal()
        for _, dungeon in pairs(type(ns) == "table" and type(ns.DB) == "table" and ns.DB or {}) do
            for _, quest in ipairs(type(dungeon) == "table" and type(dungeon.quests) == "table" and dungeon.quests or {}) do if quest.id == id then return M.JournalQuestModel(quest) end end
        end
        local extra = type(M.questDetails) == "table" and M.questDetails[id]
        if not extra then return nil end
        values = {name = extra.name, requiredLevel = extra.requiredLevel, questLevel = extra.questLevel}
    end
    local extra = type(M.questDetails) == "table" and M.questDetails[id] or {}
    local model = {id = id, title = values.name or ("#" .. tostring(id)), requiredLevel = values.requiredLevel or extra.requiredLevel, level = values.questLevel or extra.questLevel,
        faction = extra.faction, starts = {}, turnin = {}, choiceRewards = rewardList(extra.choice), guaranteedRewards = rewardList(extra.guaranteed),
        rewards = {}, extras = {}, xp = extra.xp, xpBase = extra.xpBase, money = extra.money, chain = {}}
    if type(values.objectivesText) == "table" then model.objective = table.concat(values.objectivesText, "\n") end
    if not model.objective or model.objective == "" then model.objective = extra.objective end
    if type(extra.rewardSummary) == "string" and extra.rewardSummary ~= "" then model.extras[1] = extra.rewardSummary end
    local function people(groups, target)
        for index, kind in ipairs({"npc", "object", "item"}) do
            for _, otherId in ipairs(type(groups) == "table" and type(groups[index]) == "table" and groups[index] or {}) do
                local other = M.Db.Get(db, kind, otherId)
                local spot = other and M.Db.Spots(db, other.spawns)[1]
                local location = spot and M.MapName and M.MapName(spot.map)
                target[#target + 1] = {name = other and other.name or ("#" .. tostring(otherId)), location = location, kind = kind, id = otherId, spot = spot}
            end
        end
    end
    if db then people(values.startedBy, model.starts); people(values.finishedBy, model.turnin) end
    if #model.starts == 0 and extra.startName then model.starts[1] = {name = extra.startName, location = extra.startLocation} end
    if #model.turnin == 0 and extra.turninName then model.turnin[1] = {name = extra.turninName, location = extra.turninLocation} end
    if #model.choiceRewards == 0 and #model.guaranteedRewards == 0 then model.rewards = rewardList(extra.rewards or (type(M.questRewards) == "table" and M.questRewards[id] or nil)) end
    local prerequisites = type(values.preQuestSingle) == "table" and #values.preQuestSingle > 0 and values.preQuestSingle or values.preQuestGroup
    for _, otherId in ipairs(type(prerequisites) == "table" and prerequisites or {}) do model.chain[#model.chain + 1] = {id = otherId, kind = "quest"} end
    if tonumber(values.nextQuestInChain) and values.nextQuestInChain > 0 then model.chain[#model.chain + 1] = {id = values.nextQuestInChain, kind = "quest"} end
    for _, link in ipairs(model.chain) do local v = db and M.Db.Get(db, "quest", link.id); link.name = v and v.name or ("#" .. tostring(link.id)) end
    local liveXP = A.Number(A.Call(GetQuestLogRewardXP, id), 1, 1000000000)
    if liveXP then model.xp = liveXP end
    return model
end

--- A complete quest reader. All adapters share the same navy surface, typography and reward cards.
function M.RenderQuestCard(d, model)
    if not model then return false end
    d.SetTheme("quest"); d.Reset("quest:" .. tostring(model.id or model.title))
    d.model = model
    local title = d.Text(model.title or "?", d.heading, 20)
    if title.SetShadowOffset then title:SetShadowOffset(0, 0) end
    local available = tonumber(model.requiredLevel)
    local availableY = d.y
    if available then d.Text(string.format(A.L("questCardFrom"), available), d.ink, 11)
    elseif tonumber(model.level) then d.Text(string.format(A.L("questCardLevel"), model.level), d.ink, 11) end
    d.factions = d.factions or {}
    local faction = model.faction
    local both = faction == "Both" or faction == "both" or faction == "AH"
    for index, key in ipairs({"Alliance", "Horde"}) do
        if both or faction == key or faction == key:sub(1, 1) then
            local icon = d.factions[index]
            if not icon then icon = d.content:CreateTexture(nil, "ARTWORK"); d.factions[index] = icon end
            icon:Show(); icon:SetTexture("Interface\\PVPFrame\\PVP-Currency-" .. key); icon:SetSize(18, 18); icon:ClearAllPoints(); icon:SetPoint("TOPRIGHT", d.content, "TOPRIGHT", -((index - 1) * 22), -availableY + 1)
        end
    end
    if model.classOnly then d.Text(string.format(A.L("questCardClass"), model.classOnly), d.heading, 12) end
    d.Head(A.L("questCardObjective")); d.Text(model.objective and model.objective ~= "" and model.objective or A.L("questCardNoObjective"))
    if model.startsInDungeon then d.Text(A.L("questCardInside"), d.ink, 12) end
    if model.startItem then d.Head(A.L("questCardStartItem")); d.Text(model.startItem) end
    if model.warning then d.Head(A.L("questCardWarning")); d.Text(model.warning, d.kit and d.kit.C.peach or d.ink) end
    if model.note then d.Head(A.L("questCardNote")); d.Text(model.note) end
    local function people(label, rows)
        if #(rows or {}) == 0 then return end
        d.Head(A.L(label))
        for _, person in ipairs(rows) do
            local line = d.Text(tostring(person.name or "?") .. (person.location and (", " .. person.location) or ""), d.ink, 13, person.spot and math.max(80, d.width - 24) or nil)
            if (person.kind and person.id) or person.spot then
                d.used.hit = d.used.hit + 1
                local hit = d.pools.hit[d.used.hit] or CreateFrame("Button", nil, d.content); d.pools.hit[d.used.hit] = hit
                hit.person = person
                hit:ClearAllPoints(); hit:SetAllPoints(line); hit:Show()
                hit:SetScript("OnClick", function() if person.kind and person.id and A.OpenDatabaseEntry then A.OpenDatabaseEntry(person.kind, person.id) end end)
                if not hit.map then
                    hit.map = CreateFrame("Button", nil, hit); hit.map:SetSize(18, 18); hit.map:SetPoint("RIGHT", 0, 0)
                    hit.map.icon = hit.map:CreateTexture(nil, "ARTWORK"); hit.map.icon:SetAllPoints(); hit.map.icon:SetTexture(A.Theme.ART .. "map-fold")
                end
                hit.map:SetShown(person.spot ~= nil)
                if person.spot then
                    line:SetWidth(math.max(80, d.width - 24))
                    hit.map:SetScript("OnClick", function() if M.ShowOnWorldMap then M.ShowOnWorldMap({person.spot}, person.spot.map) end end)
                end
            end
        end
    end
    people("questCardStarts", model.starts); people("questCardTurnin", model.turnin)
    if #(model.choiceRewards or {}) > 0 then d.Head(A.L("questCardChoose")); d.Rewards(model.choiceRewards) end
    if #(model.guaranteedRewards or {}) > 0 then d.Head(A.L("questCardAlso")); d.Rewards(model.guaranteedRewards) end
    if #(model.rewards or {}) > 0 then d.Head(A.L("questCardRewards")); d.Rewards(model.rewards) end
    if tonumber(model.xp) or tonumber(model.xpBase) or tonumber(model.money) or #(model.extras or {}) > 0 then
        if #(model.guaranteedRewards or {}) == 0 then d.Head(A.L("questCardAlso")) end
        if (tonumber(model.xp) or tonumber(model.xpBase) or 0) > 0 then
            local label = model.xpLabel or (model.xp and (tostring(model.xp) .. " XP") or (tostring(model.xpBase) .. " XP*"))
            d.Badge(label, d.kit.C.card, "XP")
            if model.xp == nil and model.xpBase then d.Text(A.db and A.db.settings.language == "cs" and "* Základní XP; odměna ve hře se může lišit podle úrovně." or "* Base XP; the reward in game may vary with level.", d.ink, 10) end
        end
        if tonumber(model.money) and model.money > 0 then d.Text(A.FormatMoney and A.FormatMoney(model.money) or tostring(model.money)) end
        for _, line in ipairs(model.extras or {}) do d.Text(line) end
    end
    if #(model.chain or {}) > 0 then
        d.Head(A.L(model.chainTitle or "questCardChain"))
        for _, link in ipairs(model.chain) do local id = link.id; d.Link({icon = "Interface\\GossipFrame\\AvailableQuestIcon", title = link.name, onClick = function() if A.OpenDatabaseEntry then A.OpenDatabaseEntry("quest", id) end end}) end
    end
    d.Done()
    return true
end
