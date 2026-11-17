local _, A = ...
-- The quest tracker: the guide window's second tab (Guide | Quests, tools/evertally-guide-overlay/.../GuideFrameLayout.lua
-- asks for it as Evertally.QuestTracker). Evertally's own: the ideas of a sectioned tracker (ready to turn in, this
-- zone, the other zones, dungeons and groups), drawn and written here; no code or art of another tracker.
--   * a quest: its level in the colour of its difficulty, its title, how far its nearest goal is; its objectives with
--     their counts and a thin bar; a finished one says where it is turned in; a timed one its time left
--   * click: the arrow (the guide's navigation) to the nearest goal or the turn-in; Shift+click: the quest's link in
--     the chat; right click: a menu (the quest log, the map, share, abandon); the small sign before it folds it
--   * a section folds by its heading; the order is by distance, level or the quest log's; EVERTALLY MENU on the bar
-- Distances and places come from the guide's quest database (EvertallyGuide.QuestDB, where it is loaded); without it
-- the tracker still lists the log, without distances.
local QT = {}
A.QuestTracker = QT

local BAR_H, SECTION_H, QUEST_H, LINE_H = 26, 20, 19, 15
local SORTS = {"distance", "level", "log"}

local text = {
    en = {qtGuide = "Guide", qtQuests = "Quests", qtTitle = "Quests %d/%d", qtReady = "Ready to turn in", qtDungeons = "Dungeons and groups",
        qtOther = "Other quests", qtNone = "Your quest log is empty.", qtSort_distance = "Nearest first", qtSort_level = "By level", qtSort_log = "As in the log",
        qtTurnIn = "Turn in: %s", qtTurnInHere = "Ready to turn in", qtFailed = "Failed", qtTime = "Time left %s", qtMenu = "EVERTALLY MENU",
        qtYards = "%d yd", qtLog = "Show in the quest log", qtMap = "Show on the map", qtShare = "Share with the group", qtAbandon = "Abandon",
        qtArrow = "Set the arrow here", qtFold = "Fold or unfold", qtTip = "Click: the arrow  ·  Shift+click: link in chat  ·  Right click: menu"},
    cs = {qtGuide = "Návod", qtQuests = "Questy", qtTitle = "Questy %d/%d", qtReady = "K odevzdání", qtDungeons = "Dungeony a skupiny",
        qtOther = "Ostatní questy", qtNone = "Deník questů je prázdný.", qtSort_distance = "Nejbližší první", qtSort_level = "Podle úrovně", qtSort_log = "Jako v deníku",
        qtTurnIn = "Odevzdat u: %s", qtTurnInHere = "Hotovo, odevzdat", qtFailed = "Nesplněno", qtTime = "Zbývá %s", qtMenu = "EVERTALLY MENU",
        qtYards = "%d yd", qtLog = "Ukázat v deníku questů", qtMap = "Ukázat na mapě", qtShare = "Sdílet se skupinou", qtAbandon = "Zrušit quest",
        qtArrow = "Šipka sem", qtFold = "Sbalit nebo rozbalit", qtTip = "Klik: šipka  ·  Shift+klik: odkaz do chatu  ·  Pravé tlačítko: menu"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local function settings()
    local s = A.db and A.db.settings
    if not s then return {} end
    if type(s.questTracker) ~= "table" then s.questTracker = {} end
    local t = s.questTracker
    if type(t.folded) ~= "table" then t.folded = {} end      -- section key -> true
    if type(t.foldedQuests) ~= "table" then t.foldedQuests = {} end
    return t
end
local function guide()
    local g = rawget(_G, "EvertallyGuide")
    return type(g) == "table" and g or nil
end
local function try(f, ...) if type(f) == "function" then local ok, a, b, c = pcall(f, ...); if ok then return a, b, c end end end

-- ---------------------------------------------------------------- the tab
--- The window's tab: "guide" (the guide's steps, as before) or "quests" (this tracker).
function QT.Mode() return settings().mode == "quests" and "quests" or "guide" end
local function relayout()
    local g = guide()
    local GF = g and g.UI and g.UI.GuideFrame
    if GF and GF.Layout then pcall(GF.Layout) end
end
function QT.SetMode(mode)
    settings().mode = mode == "quests" and "quests" or "guide"
    if QT.frame then QT.frame:SetShown(QT.Mode() == "quests") end
    local g = guide()
    local GF = g and g.UI and g.UI.GuideFrame
    if GF and GF.Render then pcall(GF.Render) else relayout() end
end
--- Shows the guide window on the Quests tab (the Evertally menu's Quest tracker).
function A.ShowQuestTracker()
    local g = guide()
    if not g then return false end
    QT.SetMode("quests")
    try(g.SetHidden, false)
    if not try(g.GuideShown) then try(g.Fire, "TOGGLE_FRAME") end
    return true
end

--- The two tabs at the left of the window's header: Guide | Quests.
function QT.BuildSwitch(parent)
    local kit = A.UIKit()
    local s = CreateFrame("Frame", nil, parent); s:SetSize(10, 22)
    s.guide = kit.Chip(s, function() QT.SetMode("guide") end)
    s.quests = kit.Chip(s, function() QT.SetMode("quests") end)
    s.guide:SetPoint("LEFT", s, "LEFT", 0, 0); s.quests:SetPoint("LEFT", s.guide, "RIGHT", 2, 0)
    s.guide:SetHeight(22); s.quests:SetHeight(22)
    function s.Refresh()
        s.guide.SetLabel(A.L("qtGuide")); s.quests.SetLabel(A.L("qtQuests"))
        local q = QT.Mode() == "quests"
        s.guide.SetOn(not q); s.quests.SetOn(q)
        s:SetWidth((s.guide:GetWidth() or 40) + 2 + (s.quests:GetWidth() or 40))
    end
    s.Refresh()
    return s
end

-- ---------------------------------------------------------------- the log
local function readyOf(id, info)
    local g = guide()
    local C = g and g.Compat
    if C and C.IsQuestReadyForTurnIn then return try(C.IsQuestReadyForTurnIn, id) == true end
    return info and (info.isComplete == true or info.isComplete == 1) or false
end
local function objectivesOf(id)
    local g = guide()
    local C = g and g.Compat
    local list = C and C.GetQuestObjectives and try(C.GetQuestObjectives, id)
    if type(list) ~= "table" and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local raw = try(C_QuestLog.GetQuestObjectives, id)
        if type(raw) == "table" then
            list = {}
            for i, o in ipairs(raw) do list[i] = {text = o.text or "", finished = o.finished and true or false, numFulfilled = tonumber(o.numFulfilled) or 0, numRequired = tonumber(o.numRequired) or 0} end
        end
    end
    local out = {}
    for i, o in ipairs(type(list) == "table" and list or {}) do
        local label = C and C.ObjectiveLabel and try(C.ObjectiveLabel, o.text) or o.text
        out[i] = {label = (label ~= nil and label ~= "") and label or (o.text or ""), done = o.finished, have = o.numFulfilled or 0, need = o.numRequired or 0}
    end
    return out
end
local function timeLeft(id)
    if not (C_QuestLog and C_QuestLog.GetTimeAllowed) then return nil end
    local total, elapsed = try(C_QuestLog.GetTimeAllowed, id)
    if tonumber(total) and tonumber(elapsed) and total > 0 then return math.max(0, total - elapsed) end
    return nil
end

--- The quests in the log: {id, title, level, group, header (its zone or category), index, ready, failed, objectives, time}.
function QT.ReadLog()
    local out, header = {}, nil
    local QL = C_QuestLog
    if QL and QL.GetNumQuestLogEntries and QL.GetInfo then
        for i = 1, (try(QL.GetNumQuestLogEntries) or 0) do
            local info = try(QL.GetInfo, i)
            if type(info) == "table" then
                if info.isHeader then header = info.title
                elseif not info.isHidden and tonumber(info.questID) and info.questID > 0 then
                    out[#out + 1] = {id = info.questID, title = info.title or ("#" .. info.questID), level = tonumber(info.level) or 0, group = tonumber(info.suggestedGroup) or 0,
                        header = header, index = i, ready = readyOf(info.questID, info), failed = info.isComplete == -1}
                end
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, (try(GetNumQuestLogEntries) or 0) do
            local title, level, group, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
            if isHeader then header = title
            elseif tonumber(questID) and questID > 0 then
                out[#out + 1] = {id = questID, title = title or ("#" .. questID), level = tonumber(level) or 0, group = tonumber(group) or 0, header = header, index = i,
                    ready = isComplete == 1 or readyOf(questID, nil), failed = isComplete == -1}
            end
        end
    end
    for _, q in ipairs(out) do q.objectives = objectivesOf(q.id); q.time = timeLeft(q.id) end
    return out
end

-- ---------------------------------------------------------------- places and distance (the guide's quest database)
local spawnCache = {}   -- ref -> { {c, wx, wy, map, x, y, f}, ... }
local function questDB()
    local g = guide()
    local Q = g and g.QuestDB
    if not (Q and Q.GetQuest and Q.EachSpawn) then return nil end
    if Q.IsLoaded and not try(Q.IsLoaded) then return nil end
    return Q, g
end
local function spawnsOf(Q, g, ref)
    local list = spawnCache[ref]
    if list then return list end
    list = {}
    local C = g.Compat
    try(Q.EachSpawn, ref, function(_, _, map, f, x, y)
        if #list < 60 then
            local c, wx, wy = try(C.MapToWorld, map, x, y, f)
            if c then list[#list + 1] = {c = c, wx = wx, wy = wy, map = map, x = x, y = y, f = f} end
        end
    end)
    spawnCache[ref] = list
    return list
end
-- The refs (an NPC id, an object as -id) a quest leads to now: its finishers once ready, else the objectives still open.
local function refsOf(Q, q)
    local rec = try(Q.GetQuest, q.id)
    if type(rec) ~= "table" then return {}, nil end
    local refs, points = {}, {}
    if q.ready then
        for _, id in ipairs(rec.finish and rec.finish.npc or {}) do refs[#refs + 1] = id end
        for _, id in ipairs(rec.finish and rec.finish.object or {}) do refs[#refs + 1] = -id end
        return refs, points, rec
    end
    for i, o in ipairs(rec.objectives or {}) do
        local mine = q.objectives and q.objectives[i]
        if not (mine and mine.done) then
            if o.kind == "kill" and o.id then refs[#refs + 1] = o.id
            elseif o.kind == "object" and o.id then refs[#refs + 1] = -o.id
            elseif o.kind == "item" and o.id and Q.GetItemDroppers then
                local droppers = try(Q.GetItemDroppers, o.id)
                for k = 1, math.min(3, type(droppers) == "table" and #droppers or 0) do if droppers[k].id then refs[#refs + 1] = droppers[k].id end end
            elseif o.map and o.x and o.y then points[#points + 1] = {map = o.map, x = o.x, y = o.y, f = o.f} end
        end
    end
    return refs, points, rec
end
--- How far the quest's nearest goal (or its turn-in) is: yards and the point, or nil (no place known, another continent).
function QT.Nearest(q)
    local Q, g = questDB()
    if not Q then return nil end
    local pc, px, py = try(g.Compat.GetPlayerWorldPosition)
    if not pc then return nil end
    local refs, points, rec = refsOf(Q, q)
    local best, at
    local function consider(s, name)
        if s.c ~= pc then return end
        local dx, dy = s.wx - px, s.wy - py
        local d = math.sqrt(dx * dx + dy * dy)
        if not best or d < best then best, at = d, {map = s.map, x = s.x, y = s.y, f = s.f, name = name} end
    end
    for _, ref in ipairs(refs) do
        local name = try(Q.EntityName, ref)
        for _, s in ipairs(spawnsOf(Q, g, ref)) do consider(s, name) end
    end
    for _, p in ipairs(points) do
        local c, wx, wy = try(g.Compat.MapToWorld, p.map, p.x, p.y, p.f)
        if c then consider({c = c, wx = wx, wy = wy, map = p.map, x = p.x, y = p.y, f = p.f}, q.title) end
    end
    if q.ready and rec and not q.turnIn then
        local id = rec.finish and (rec.finish.npc or {})[1]
        q.turnIn = id and try(Q.EntityName, id) or nil
    end
    return best, at
end

-- ---------------------------------------------------------------- the model
local function zoneName()
    local z = GetRealZoneText and GetRealZoneText()
    if (not z or z == "") and C_Map and C_Map.GetBestMapForUnit then
        local map = try(C_Map.GetBestMapForUnit, "player")
        local info = map and try(C_Map.GetMapInfo, map)
        z = info and info.name
    end
    return z
end
local function isDungeon(q)
    if q.group and q.group > 1 then return true end
    local g = guide()
    local D = g and g.Dungeons
    return D and D.QuestMark and try(D.QuestMark, q.id) ~= nil or false
end
local function sorter(mode)
    return function(a, b)
        if mode == "distance" then
            if (a.yards ~= nil) ~= (b.yards ~= nil) then return a.yards ~= nil end
            if a.yards and b.yards and a.yards ~= b.yards then return a.yards < b.yards end
        elseif mode == "level" and a.level ~= b.level then
            return a.level < b.level
        end
        return a.index < b.index
    end
end
function QT.Sort() local s = settings().sort; for _, k in ipairs(SORTS) do if k == s then return s end end; return "distance" end

--- The tracker's sections from the log: {key, title, quests}; ready first, then this zone, the other zones (each its
--- own, nearest first when sorted by distance), dungeons and groups last.
function QT.Model(log)
    log = log or QT.ReadLog()
    local here = zoneName()
    local ready, local_, dungeons, zones, order = {}, {}, {}, {}, {}
    for _, q in ipairs(log) do
        q.yards, q.point = QT.Nearest(q)
        if q.ready then ready[#ready + 1] = q
        elseif isDungeon(q) then dungeons[#dungeons + 1] = q
        elseif here and q.header == here then local_[#local_ + 1] = q
        else
            local key = q.header or ""
            if not zones[key] then zones[key] = {}; order[#order + 1] = key end
            table.insert(zones[key], q)
        end
    end
    local sort = sorter(QT.Sort())
    local sections = {}
    local function add(key, title, list) if #list > 0 then table.sort(list, sort); sections[#sections + 1] = {key = key, title = title, quests = list} end end
    add("ready", A.L("qtReady"), ready)
    add("here", here or A.L("qtOther"), local_)
    local function nearest(list) local n; for _, q in ipairs(list) do if q.yards and (not n or q.yards < n) then n = q.yards end end; return n end
    table.sort(order, function(a, b)
        if QT.Sort() == "distance" then
            local da, db = nearest(zones[a]), nearest(zones[b])
            if (da ~= nil) ~= (db ~= nil) then return da ~= nil end
            if da and db and da ~= db then return da < db end
        end
        return a < b
    end)
    for _, key in ipairs(order) do add("zone:" .. key, key ~= "" and key or A.L("qtOther"), zones[key]) end
    add("dungeons", A.L("qtDungeons"), dungeons)
    return sections, #log
end

-- ---------------------------------------------------------------- drawing
local function difficulty(level)
    if GetQuestDifficultyColor then
        local c = try(GetQuestDifficultyColor, level)
        if type(c) == "table" and c.r then return {c.r, c.g, c.b} end
    end
    local d = (level or 0) - ((UnitLevel and UnitLevel("player")) or 1)
    if d >= 5 then return {1, 0.1, 0.1} elseif d >= 3 then return {1, 0.5, 0.25} elseif d >= -2 then return {1, 0.82, 0} elseif d >= -8 then return {0.25, 0.75, 0.25} end
    return {0.5, 0.5, 0.5}
end
local function clock(seconds)
    seconds = math.floor(seconds or 0)
    if seconds >= 3600 then return string.format("%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60) end
    return string.format("%d:%02d", seconds / 60, seconds % 60)
end

local function setArrow(q)
    local g = guide()
    local Nav = g and g.Nav
    local p = q.point
    if not (Nav and Nav.SetTarget and p) then return false end
    try(Nav.SetTarget, p.map, p.x, p.y, (p.name and p.name ~= "" and p.name) or q.title, p.f)
    return true
end
local function chatLink(q)
    -- the client's link (as a shift-click in the quest log), else the title as plain text
    local link = GetQuestLink and try(GetQuestLink, q.id)
    if type(link) ~= "string" or link == "" then link = "\"" .. tostring(q.title or ""):gsub("[%[%]|]", "") .. "\"" end
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if insert then return try(insert, link) end
end
local function contextMenu(owner, q)
    local g = guide()
    local W = g and g.Widgets
    if not (W and W.ShowMenu) then return end
    local items = {
        {text = A.L("qtLog"), onClick = function()
            if QuestLog_SetSelection then try(QuestLog_SetSelection, q.index) end
            if ToggleQuestLog then try(ToggleQuestLog) elseif ShowUIPanel and QuestLogFrame then try(ShowUIPanel, QuestLogFrame) end
        end},
        q.point and {text = A.L("qtMap"), onClick = function() if g.Compat and g.Compat.OpenWorldMap then try(g.Compat.OpenWorldMap, q.point.map) end end} or nil,
        q.point and {text = A.L("qtArrow"), onClick = function() setArrow(q) end} or nil,
        {text = A.L("qtShare"), onClick = function()
            if SelectQuestLogEntry then try(SelectQuestLogEntry, q.index) end
            if QuestLogPushQuest then try(QuestLogPushQuest) end
        end},
        {separator = true},
        -- the game's own question ("Abandon ...?") asks before anything is lost
        {text = A.L("qtAbandon"), onClick = function()
            if SelectQuestLogEntry then try(SelectQuestLogEntry, q.index) end
            if SetAbandonQuest then try(SetAbandonQuest) end
            if StaticPopup_Show then try(StaticPopup_Show, "ABANDON_QUEST", GetAbandonQuestName and GetAbandonQuestName() or q.title) end
        end},
    }
    local list = {}
    for _, item in ipairs(items) do if item then list[#list + 1] = item end end
    try(W.ShowMenu, owner, list, {point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -2})
end

local function build(parent)
    local kit = A.UIKit()
    local C = kit.C
    local f = CreateFrame("Frame", nil, parent)
    f.kit = kit
    f.bar = CreateFrame("Frame", nil, f); f.bar:SetPoint("TOPLEFT"); f.bar:SetPoint("TOPRIGHT"); f.bar:SetHeight(BAR_H)
    f.sort = CreateFrame("Button", nil, f.bar); f.sort:SetPoint("LEFT", 10, 0); f.sort:SetSize(120, BAR_H)
    f.sort.text = kit.label(f.sort, 11, C.mist); f.sort.text:SetPoint("LEFT")
    f.sort:SetScript("OnClick", function()
        local now, nextKey = QT.Sort(), SORTS[1]
        for i, k in ipairs(SORTS) do if k == now then nextKey = SORTS[i % #SORTS + 1] end end
        settings().sort = nextKey; QT.Refresh(true)
    end)
    f.menu = kit.Button(f.bar, "qtMenu", 120, "primary", function(self) if A.ShowEvertallyMenu then A.ShowEvertallyMenu(self) end end)
    f.menu:SetHeight(20); f.menu:SetPoint("RIGHT", -8, 0)
    if f.menu.text then f.menu.text:SetFont(kit.fontPath(), 10, "") end
    f.scroll = CreateFrame("ScrollFrame", nil, f); f.scroll:SetPoint("TOPLEFT", 0, -BAR_H); f.scroll:SetPoint("BOTTOMRIGHT")
    f.content = CreateFrame("Frame", nil, f.scroll); f.content:SetSize(300, 10); f.scroll:SetScrollChild(f.content)
    f.scroll:EnableMouseWheel(true)
    f.scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, (f.content:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 40)))
    end)
    f.rows, f.used = {}, 0
    f.empty = kit.label(f.content, 12, C.mist); f.empty:SetPoint("TOPLEFT", 12, -8)
    return f
end

-- A pooled row: a button with a fold sign, a badge (level or count), its text and a right-hand note; a thin bar under.
local function row(f)
    f.used = f.used + 1
    local r = f.rows[f.used]
    if r then return r end
    local kit, C = f.kit, f.kit.C
    r = CreateFrame("Button", nil, f.content)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hover = r:CreateTexture(nil, "HIGHLIGHT"); r.hover:SetAllPoints(r); kit.paint(r.hover, C.gold, 0.07)
    r.fold = CreateFrame("Button", nil, r); r.fold:SetSize(14, 14); r.fold:SetPoint("LEFT", 6, 0)
    r.fold.text = kit.label(r.fold, 12, C.faint); r.fold.text:SetPoint("CENTER"); r.fold.text:SetJustifyH("CENTER")
    r.badge = kit.label(r, 11, C.text); r.badge:SetPoint("LEFT", 22, 0); r.badge:SetJustifyH("LEFT")
    r.note = kit.label(r, 10, C.faint); r.note:SetPoint("RIGHT", -10, 0); r.note:SetJustifyH("RIGHT")
    r.text = kit.label(r, 12, C.text); r.text:SetPoint("LEFT", r.badge, "RIGHT", 5, 0); r.text:SetPoint("RIGHT", r.note, "LEFT", -6, 0); r.text:SetWordWrap(false)
    r.track = r:CreateTexture(nil, "ARTWORK"); r.track:SetHeight(2); kit.paint(r.track, C.off or C.card, 1)
    r.fill = r:CreateTexture(nil, "OVERLAY"); r.fill:SetHeight(2); kit.paint(r.fill, C.gold, 1)
    r:SetScript("OnClick", function(self, which)
        local q = self.quest
        if self.section then
            local folded = settings().folded
            folded[self.section] = not folded[self.section] or nil
            return QT.Refresh(true)
        end
        if not q then return end
        if which == "RightButton" then return contextMenu(self, q) end
        if IsShiftKeyDown and IsShiftKeyDown() then return chatLink(q) end
        setArrow(q)
    end)
    r.fold:SetScript("OnClick", function(self)
        local q = self:GetParent().quest
        if not q then return self:GetParent():GetScript("OnClick")(self:GetParent(), "LeftButton") end
        local fq = settings().foldedQuests
        fq[q.id] = not fq[q.id] or nil
        QT.Refresh(true)
    end)
    r:SetScript("OnEnter", function(self)
        if not (self.quest and GameTooltip) then return end
        local g = guide(); local W = g and g.Widgets
        if W and W.Tooltip and pcall(W.Tooltip, self, "ANCHOR_LEFT", self.quest.title, {A.L("qtTip")}) then return end
    end)
    r:SetScript("OnLeave", function(self) local g = guide(); local W = g and g.Widgets; if W and W.HideTooltip then pcall(W.HideTooltip, self) end end)
    f.rows[f.used] = r
    return r
end

local function paintRow(f, r, y, width, kind, spec)
    local kit, C = f.kit, f.kit.C
    local h = kind == "section" and SECTION_H or kind == "quest" and QUEST_H or LINE_H
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y); r:SetSize(width, h)
    r.quest, r.section = spec.quest, spec.section
    r.fold:SetShown(kind ~= "line")
    r.fold.text:SetText(spec.folded and "+" or "-")
    r.badge:SetText(spec.badge or "")
    local bc = spec.badgeColor or C.faint
    r.badge:SetTextColor(bc[1], bc[2], bc[3], 1)
    -- a line with a bar sits a little higher, the bar under it
    local dy = spec.bar and 2 or 0
    r.badge:ClearAllPoints(); r.badge:SetPoint("LEFT", kind == "line" and 26 or 22, dy)
    r.note:ClearAllPoints(); r.note:SetPoint("RIGHT", -10, dy)
    r.text:SetFont(kit.fontPath(kind == "section" and "heading" or "body"), kind == "section" and 11 or kind == "quest" and 12 or 11, "")
    local tc = spec.color or C.text
    r.text:SetTextColor(tc[1], tc[2], tc[3], 1)
    r.text:SetText(spec.text or "")
    r.note:SetText(spec.note or "")
    local bar = spec.bar
    r.track:SetShown(bar ~= nil); r.fill:SetShown(bar ~= nil and bar > 0)
    if bar then
        local left, w = 30, math.max(20, width - 40)
        r.track:ClearAllPoints(); r.track:SetPoint("BOTTOMLEFT", left, 0); r.track:SetWidth(w)
        r.fill:ClearAllPoints(); r.fill:SetPoint("BOTTOMLEFT", left, 0); r.fill:SetWidth(math.max(1, w * math.min(1, bar)))
    end
    r:Show()
    return y + h
end

--- Places the tracker in `parent` (the guide window's body) once. -> its frame
function QT.Attach(parent)
    if not QT.frame then QT.frame = build(parent) end
    if QT.frame:GetParent() ~= parent then QT.frame:SetParent(parent) end
    return QT.frame
end

--- Draws the sections at `width`; at most `room` tall (then it scrolls). -> the height it takes
function QT.Layout(width, room)
    local f = QT.frame
    if not f then return 0 end
    local C = f.kit.C
    local sections, count = QT.Model()
    QT.count = count
    f.sort.text:SetText(A.L("qtSort_" .. QT.Sort()))
    if f.menu.text then f.menu.text:SetText(A.L("qtMenu")) end
    f.used = 0
    local y, folded, fq = 4, settings().folded, settings().foldedQuests
    for _, sec in ipairs(sections) do
        local closed = folded[sec.key] == true
        y = paintRow(f, row(f), y, width, "section", {section = sec.key, folded = closed, text = sec.title, color = C.gold, note = tostring(#sec.quests)})
        if not closed then
            for _, q in ipairs(sec.quests) do
                local note = q.yards and string.format(A.L("qtYards"), math.floor(q.yards + 0.5)) or nil
                y = paintRow(f, row(f), y, width, "quest", {quest = q, folded = fq[q.id] == true, badge = "[" .. tostring(q.level or "?") .. (q.group and q.group > 1 and "+" or "") .. "]",
                    badgeColor = difficulty(q.level), text = q.title, color = q.ready and C.green or q.failed and C.red or C.text, note = note})
                if not fq[q.id] then
                    if q.failed then
                        y = paintRow(f, row(f), y, width, "line", {text = A.L("qtFailed"), color = C.red})
                    elseif q.ready then
                        y = paintRow(f, row(f), y, width, "line", {text = q.turnIn and string.format(A.L("qtTurnIn"), q.turnIn) or A.L("qtTurnInHere"), color = C.mist})
                    else
                        for _, o in ipairs(q.objectives or {}) do
                            local counts = o.need > 1 and (o.have .. "/" .. o.need) or nil
                            y = paintRow(f, row(f), y, width, "line", {text = o.label, note = counts, color = o.done and C.faint or C.mist,
                                bar = (o.need > 1 and not o.done) and (o.have / o.need) or nil})
                        end
                    end
                    if q.time then y = paintRow(f, row(f), y, width, "line", {text = string.format(A.L("qtTime"), clock(q.time)), color = C.peach}) end
                end
            end
        end
        y = y + 4
    end
    for i = f.used + 1, #f.rows do f.rows[i]:Hide(); f.rows[i].quest, f.rows[i].section = nil, nil end
    f.empty:SetShown(count == 0); f.empty:SetText(A.L("qtNone"))
    if count == 0 then y = 34 end
    f.content:SetSize(width, y)
    local inner = room and math.max(60, room - BAR_H) or y
    local shown = math.min(y, inner)
    f.scroll:SetVerticalScroll(math.min(f.scroll:GetVerticalScroll() or 0, math.max(0, y - shown)))
    f:SetHeight(BAR_H + shown)
    return BAR_H + shown
end

--- The window's title while the Quests tab shows: "Quests 12/20".
function QT.Title()
    local max = tonumber(rawget(_G, "MAX_QUESTLOG_QUESTS")) or (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and try(C_QuestLog.GetMaxNumQuestsCanAccept)) or 20
    return string.format(A.L("qtTitle"), QT.count or 0, max)
end

--- Draws the tracker again (the log changed, a fold, the order): through the window's layout, its height may change.
local pending
function QT.Refresh(now)
    if QT.Mode() ~= "quests" or not (QT.frame and QT.frame:IsVisible()) then return end
    if now then pending = nil; return relayout() end
    if pending then return end
    pending = true
    local function run() if pending then pending = nil; relayout() end end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, run) else run() end
end
for _, event in ipairs({"QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "ZONE_CHANGED_NEW_AREA", "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP"}) do
    A.On(event, function() QT.Refresh(false) end)
end
-- the distances (and timers) every two seconds while the tab shows
A.On("PLAYER_LOGIN", function()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2, function() QT.Refresh(false) end) end
end)
