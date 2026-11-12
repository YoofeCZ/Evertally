local _, M = ...
local A = _G.Evertally
-- The database tab as it looks: a search box, a list, and what is known about the chosen NPC, quest or item with buttons to show
-- the places on the map or to navigate to the nearest one. The reading of QuestieDB is in WorldDb.lua (M.Db).
local Db = M.Db
local ROWS, ROW_H, MAX_RESULTS = 12, 28, 60
local HEAD = "|cffa78bfa"

-- ---------------------------------------------------------------- what to show about one entity
local function nameOf(db, kind, id)
    local values = Db.Get(db, kind, id)
    return values and type(values.name) == "string" and values.name or (kind .. " #" .. tostring(id))
end
local function listNames(db, kind, ids, max)
    local out = {}
    if type(ids) ~= "table" then return out end
    for i, id in ipairs(ids) do
        if i > max then out[#out + 1] = string.format(A.L("worldDbMore"), #ids - max); break end
        out[#out + 1] = nameOf(db, kind, id)
    end
    return out
end
local function range(values)
    local low, high = values.minLevel, values.maxLevel
    if type(low) ~= "number" then return nil end
    return low == high and tostring(low) or (tostring(low) .. "-" .. tostring(type(high) == "number" and high or "?"))
end
local function addSpots(out, db, id, kind)
    local who = Db.Get(db, kind or "npc", id)
    for _, spot in ipairs(who and Db.Spots(db, who.spawns) or {}) do spot.title = nameOf(db, kind or "npc", id); out.spots[#out.spots + 1] = spot end
end

local ICON_OF = {quest = "Interface\\GossipFrame\\AvailableQuestIcon", npc = "Interface\\Icons\\INV_Misc_Head_Human_01", object = "Interface\\Icons\\INV_Misc_Bag_08"}

--- The short line under a name in a row of the detail: a quest's level, an NPC's title and level, an item's level.
local function subOf(db, kind, id)
    local v = Db.Get(db, kind, id)
    if not v then return nil end
    if kind == "quest" then return type(v.questLevel) == "number" and string.format(A.L("worldDbLevel"), tostring(v.questLevel)) or nil end
    if kind == "npc" then
        local level = range(v)
        local title = type(v.subName) == "string" and v.subName ~= "" and v.subName or nil
        if title and level then return title .. "  ·  " .. string.format(A.L("worldDbLevel"), level) end
        return title or (level and string.format(A.L("worldDbLevel"), level)) or nil
    end
    if kind == "item" then return type(v.itemLevel) == "number" and v.itemLevel > 0 and string.format(A.L("worldDbItemLevel"), tostring(v.itemLevel)) or nil end
end

--- {title, subtitle, lines, sections, spots, map} for one entity. sections are [{head, rows = [{text, kind, id}]}]: a row with a kind and an id is another
--- entry of the database (it can be opened); lines are the same as plain text (for the details window of a record). spots are {map, x, y, title} on maps
--- the window can show; map is the one with most of them.
function Db.Detail(db, kind, id)
    local values = Db.Get(db, kind, id)
    if not values then return nil end
    local out = {title = tostring(values.name or ("#" .. tostring(id))), lines = {}, sections = {}, spots = {}, kind = kind, id = id, subtitle = ""}
    local current
    local function head(key)
        out.lines[#out.lines + 1] = HEAD .. A.L(key) .. "|r"
        current = {head = A.L(key), rows = {}}
        out.sections[#out.sections + 1] = current
    end
    local function line(value, ofKind, ofId)
        out.lines[#out.lines + 1] = value
        if current then current.rows[#current.rows + 1] = {text = value, kind = ofKind, id = ofId} end
    end
    --- A list of entries under a heading; the places of the first few are added to the map (people and objects have them).
    local function names(label, ofKind, ids, max, withSpots)
        if type(ids) ~= "table" or #ids == 0 then return end
        head(label)
        for i, other in ipairs(ids) do
            if i > max then line(string.format(A.L("worldDbMore"), #ids - max)); break end
            line(nameOf(db, ofKind, other), ofKind, other)
            if withSpots and i <= 6 then addSpots(out, db, other, ofKind) end
        end
    end
    local function objectives(list)
        if type(list) ~= "table" then return end
        local function each(group, ofKind, label)
            if type(group) ~= "table" then return end
            for i, entry in ipairs(group) do
                if i > 8 then break end
                local other = type(entry) == "table" and entry[1]
                if type(other) == "number" then line(label .. ": " .. nameOf(db, ofKind, other), ofKind, other) end
            end
        end
        each(list[1], "npc", A.L("worldDbKill")); each(list[2], "object", A.L("worldDbUse")); each(list[3], "item", A.L("worldDbCollect"))
    end
    if kind == "npc" then
        local level = range(values)
        out.subtitle = (type(values.subName) == "string" and values.subName ~= "" and (values.subName .. "  ") or "") .. (level and string.format(A.L("worldDbLevel"), level) or "")
        for _, spot in ipairs(Db.Spots(db, values.spawns)) do spot.title = out.title; out.spots[#out.spots + 1] = spot end
        names("worldDbQuestStarts", "quest", values.questStarts, 14)
        names("worldDbQuestEnds", "quest", values.questEnds, 14)
        names("worldDbSells", "item", M.vendorStock and M.vendorStock[id], 80)
    elseif kind == "object" then
        for _, spot in ipairs(Db.Spots(db, values.spawns)) do spot.title = out.title; out.spots[#out.spots + 1] = spot end
        names("worldDbQuestStarts", "quest", values.questStarts, 14)
        names("worldDbQuestEnds", "quest", values.questEnds, 14)
    elseif kind == "quest" then
        local level, needs = values.questLevel, values.requiredLevel
        out.subtitle = (type(level) == "number" and string.format(A.L("worldDbLevel"), tostring(level)) or "")
            .. (type(needs) == "number" and needs > 0 and ("  ·  " .. string.format(A.L("worldDbRequires"), tostring(needs))) or "")
        if type(values.zoneOrSort) == "number" and values.zoneOrSort > 0 then
            local map = Db.MapOf(db, values.zoneOrSort)
            head("worldDbZone"); line(map and (A.Text(M.MapName(map), 80) or "?") or ("#" .. tostring(values.zoneOrSort)))
        end
        if type(values.objectivesText) == "table" and #values.objectivesText > 0 then
            head("worldDbObjectives")
            for _, text in ipairs(values.objectivesText) do if type(text) == "string" then line(text) end end
            objectives(values.objectives)
        elseif type(values.objectives) == "table" then
            head("worldDbObjectives"); objectives(values.objectives)
        end
        local function people(label, group)
            if type(group) ~= "table" then return end
            local npcs, objects, items = type(group[1]) == "table" and group[1] or {}, type(group[2]) == "table" and group[2] or {}, type(group[3]) == "table" and group[3] or {}
            if #npcs + #objects + #items == 0 then return end
            head(label)
            for i, npc in ipairs(npcs) do
                if i > 6 then line(string.format(A.L("worldDbMore"), #npcs - 6)); break end
                line(nameOf(db, "npc", npc), "npc", npc); addSpots(out, db, npc, "npc")
            end
            for i, object in ipairs(objects) do
                if i > 4 then break end
                line(nameOf(db, "object", object), "object", object); addSpots(out, db, object, "object")
            end
            for i, item in ipairs(items) do
                if i > 4 then break end
                line(nameOf(db, "item", item), "item", item)
            end
        end
        people("worldDbStarts", values.startedBy)
        people("worldDbEnds", values.finishedBy)
        names("worldDbPrereq", "quest", (type(values.preQuestSingle) == "table" and #values.preQuestSingle > 0) and values.preQuestSingle or values.preQuestGroup, 6)
        if type(values.nextQuestInChain) == "number" and values.nextQuestInChain > 0 then names("worldDbNext", "quest", {values.nextQuestInChain}, 1) end
        if type(values.sourceItemId) == "number" and values.sourceItemId > 0 then names("worldDbGives", "item", {values.sourceItemId}, 1) end
        names("worldDbRewardItems", "item", M.questRewards and M.questRewards[id], 12)
    else
        local bits = {}
        if type(values.itemLevel) == "number" and values.itemLevel > 0 then bits[#bits + 1] = string.format(A.L("worldDbItemLevel"), tostring(values.itemLevel)) end
        if type(values.requiredLevel) == "number" and values.requiredLevel > 0 then bits[#bits + 1] = string.format(A.L("worldDbRequires"), tostring(values.requiredLevel)) end
        out.subtitle = table.concat(bits, "  ·  ")
        names("worldDbSoldBy", "npc", values.vendors, 10, true)
        names("worldDbDrops", "npc", values.npcDrops, 12, true)
        names("worldDbFromObjects", "object", values.objectDrops, 6, true)
        if type(values.startQuest) == "number" and values.startQuest > 0 then names("worldDbStartsQuest", "quest", {values.startQuest}, 1) end
        names("worldDbRewards", "quest", values.questRewards, 8)
    end
    local counts, best = {}, nil
    for _, spot in ipairs(out.spots) do counts[spot.map] = (counts[spot.map] or 0) + 1; if not best or counts[spot.map] > counts[best] then best = spot.map end end
    out.map = best
    return out
end

--- Draws an entry's detail with the shared detail view: headings, text and rows with an icon that open the entry they name.
local function render(s, d, selected)
    local v, C = s.view, s.kit.C
    v.Reset()
    if d then
        if #d.spots > 0 and (selected.kind == "npc" or selected.kind == "object") then
            local where, seen = {}, {}
            for _, spot in ipairs(d.spots) do if not seen[spot.map] then seen[spot.map] = true; where[#where + 1] = A.Text(M.MapName(spot.map), 60) or "?" end end
            v.Head(A.L("worldDbWhere")); v.Text(table.concat(where, ", "), C.mist)
        end
        for _, section in ipairs(d.sections) do
            v.Head(section.head)
            for _, r in ipairs(section.rows) do
                if r.kind and r.id then
                    local icon = r.kind == "item" and M.ItemLook(r.id) or ICON_OF[r.kind]
                    local kind, id = r.kind, r.id
                    v.Link({icon = icon, title = r.text, sub = subOf(s.dbHandle, kind, id), itemId = kind == "item" and id or nil,
                        onClick = function() M.OpenDatabaseEntry(kind, id) end})
                else
                    v.Text(r.text, C.text)
                end
            end
        end
        if #d.sections == 0 and #d.spots == 0 then v.Text(A.L("worldDbNoPlace"), C.mist) end
    end
    v.Done()
end

-- ---------------------------------------------------------------- the tab
local function plainLine(line) return line:find("|c", 1, true) and line or A.Plain(line) end

function M.WorldDbRows(frame)
    local s = frame.db
    for i, row in ipairs(s.rows) do
        local id = s.results[s.offset + i]
        row.id = id
        row:SetShown(id ~= nil)
        if id then
            local values = s.dbHandle and Db.Get(s.dbHandle, s.kind, id)
            row.name:SetText(A.Plain(values and values.name or tostring(id)))
        end
    end
end

function M.WorldDbDetail(frame)
    local s = frame.db
    local selected = s.selected
    s.detail = selected and s.dbHandle and Db.Detail(s.dbHandle, selected.kind, selected.id) or nil
    local d = s.detail
    s.title:SetText(d and A.Plain(d.title) or "")
    local icon = d and selected.kind == "item" and (A.Call(GetItemIcon, selected.id) or (C_Item and A.Call(C_Item.GetItemIconByID, selected.id)))
    s.icon.itemId = icon and selected.id or nil
    s.icon:SetShown(icon ~= nil and icon ~= false)
    if icon then s.icon.tex:SetTexture(icon) end
    s.title:ClearAllPoints(); s.title:SetPoint("TOPLEFT", icon and 348 or 306, -60)
    s.subtitle:SetText(d and A.Plain(d.subtitle or "") or "")
    render(s, d, selected or {})
    s.show:SetShown(d ~= nil and d.map ~= nil); s.go:SetShown(d ~= nil and #d.spots > 0)
end

function M.WorldDbRefresh(frame, fromTimer)
    local s = frame.db
    if not s then return end
    if not s.dbHandle and not s.dbFailed then
        local db, why = Db.Open()
        if db then s.dbHandle = db else s.dbFailed = why or "failed" end
    end
    for kind, button in pairs(s.kindButtons) do
        button:SetShown(not s.dbHandle or s.dbHandle.has == nil or s.dbHandle.has[kind] == true)
        button.text:SetText(A.L("worldDb_" .. kind))
        button.text:SetTextColor(unpack(s.kind == kind and frame.kitColors.text or frame.kitColors.mist))
    end
    if s.dbFailed then
        s.status:SetText(A.L("worldDbMissing")); s.results = {}; M.WorldDbRows(frame); return
    end
    local entry = Db.StartIndex(s.dbHandle, s.kind)
    local reading = entry.at <= #entry.ids
    local typed = #(s.query:gsub("%s", "")) >= 2
    s.results = typed and Db.Search(s.dbHandle, s.kind, s.query, MAX_RESULTS) or Db.Sorted(s.kind)
    if reading then
        local progress = s.progress or (#entry.ids == 0 and 1 or (entry.at - 1) / #entry.ids)
        s.status:SetText(string.format(A.L("worldDbIndexing"), math.floor(progress * 100)))
    elseif typed and #s.results == 0 then s.status:SetText(A.L("worldDbNone"))
    elseif not typed then s.status:SetText(string.format(A.L("worldDbCount"), #s.results))
    else s.status:SetText(string.format(A.L("catalogCounts"), #s.results)) end
    M.WorldDbRows(frame)
    if not fromTimer then M.WorldDbDetail(frame) end
end

local function build(frame, kit)
    local C = kit.C
    frame.kitColors = C
    local s = {kind = "npc", results = {}, offset = 0, query = ""}
    frame.db = s
    s.box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    s.box:SetSize(230, 26); s.box:SetPoint("TOPLEFT", 6, -4); s.box:SetAutoFocus(false); s.box:SetMaxLetters(60); s.box:SetFont("Fonts\\ARIALN.TTF", 12, "")
    s.box:SetScript("OnTextChanged", function(self) s.query = self:GetText() or ""; s.offset = 0; M.WorldDbRefresh(frame) end)
    s.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    s.kindButtons = {}
    for i, kind in ipairs(Db.kinds) do
        local b = kit.Button(frame, "worldDb_" .. kind, 72, "ghost", function() s.kind = kind; s.offset = 0; s.selected = nil; s.progress = nil; M.WorldDbRefresh(frame) end)
        b:SetPoint("TOPLEFT", 246 + (i - 1) * 78, -2); s.kindButtons[kind] = b
    end
    s.status = kit.label(frame, 11, C.mist); s.status:SetPoint("TOPLEFT", 6, -40); s.status:SetWidth(620)
    -- the list
    s.list = CreateFrame("Frame", nil, frame)
    s.list:SetPoint("TOPLEFT", 0, -58); s.list:SetSize(290, ROWS * ROW_H)
    s.list:EnableMouse(true)
    if s.list.EnableMouseWheel then s.list:EnableMouseWheel(true) end
    s.list:SetScript("OnMouseWheel", function(_, delta)
        local step = math.max(3, math.floor(#s.results / 120))   -- (a list of thousands moves faster)
        s.offset = math.max(0, math.min(math.max(0, #s.results - ROWS), s.offset - delta * step))
        M.WorldDbRows(frame)
    end)
    s.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, s.list)
        row:SetSize(290, ROW_H - 2); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.bg = kit.fill(row, {1, 1, 1}, 1); row.bg:SetAlpha(0.05)   -- the alpha IS the strength: a colour alpha on top would multiply
        row.name = kit.label(row, 12, C.text); row.name:SetPoint("LEFT", 8, 0); row.name:SetWidth(270); row.name:SetJustifyH("LEFT")
        row:SetScript("OnEnter", function() row.bg:SetAlpha(0.14) end)
        row:SetScript("OnLeave", function() row.bg:SetAlpha(0.05) end)
        row:SetScript("OnClick", function() if row.id then s.selected = {kind = s.kind, id = row.id}; M.WorldDbDetail(frame) end end)
        s.rows[i] = row
    end
    -- the detail
    s.icon = CreateFrame("Button", nil, frame); s.icon:SetSize(34, 34); s.icon:SetPoint("TOPLEFT", 306, -56); s.icon:Hide()
    s.icon.tex = s.icon:CreateTexture(nil, "ARTWORK"); s.icon.tex:SetAllPoints(); s.icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.icon:SetScript("OnEnter", function(self)
        if not (GameTooltip and self.itemId) then return end
        pcall(function() GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.itemId); GameTooltip:Show() end)
    end)
    s.icon:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    s.title = kit.label(frame, 15, C.text); s.title:SetPoint("TOPLEFT", 306, -60); s.title:SetWidth(350); s.title:SetJustifyH("LEFT")
    s.subtitle = kit.label(frame, 11, C.mist); s.subtitle:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 0, -4); s.subtitle:SetWidth(350)
    -- the text of the detail scrolls (a quest or an item has many lines)
    s.kit = kit
    s.view = M.GuideDetail(kit, frame)
    s.view.scroll:SetPoint("TOPLEFT", s.subtitle, "BOTTOMLEFT", 0, -10); s.view.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 76)
    s.view.SetWidth(324)
    -- the detail and the status line follow the width of the window (the list on the left keeps its size)
    frame:SetScript("OnSizeChanged", function(_, w)
        w = tonumber(w) or 0
        if w < 200 then return end
        local detail = math.max(180, w - 312)
        s.title:SetWidth(detail); s.subtitle:SetWidth(detail); s.view.SetWidth(detail - 26); s.status:SetWidth(math.max(100, w - 12))
    end)
    s.show = kit.Button(frame, "worldDbShow", 160, "primary", function()
        local d = s.detail
        if d and d.map then M.ShowOnWorldMap(d.spots, d.map) end
    end)
    s.show:SetPoint("BOTTOMLEFT", 306, 36)
    s.go = kit.Button(frame, "worldDbGo", 190, "ghost", function()
        local d = s.detail
        if not d or #d.spots == 0 then return end
        local best, bestDistance
        for _, spot in ipairs(d.spots) do
            local distance = M.DistanceTo(spot.map, spot.x, spot.y)
            if not best or (distance and (not bestDistance or distance < bestDistance)) then best, bestDistance = spot, distance end
        end
        local chosen = s.selected
        if best and A.NavigateToPoint then A.NavigateToPoint(best.title or d.title, best.map, best.x, best.y, chosen and {tab = "db", kind = chosen.kind, id = chosen.id} or nil) end
    end)
    s.go:SetPoint("BOTTOMLEFT", 306, 0)   -- one above the other: side by side they would not fit the narrowest window
    -- the names are read a few milliseconds per frame while the tab is open
    frame:SetScript("OnUpdate", function()
        local db = s.dbHandle
        if not db or not frame:IsShown() then return end
        local entry = Db.index[s.kind]
        if entry and entry.at <= #entry.ids then
            local done, progress = Db.Step(db, s.kind, 4)
            s.progress = not done and progress or nil
            M.WorldDbRefresh(frame, true)
        end
    end)
end

M.worldTabs.db = {build = build, refresh = function(frame) M.WorldDbRefresh(frame) end}

--- Opens the database page on one entry: kind "npc", "quest", "item" or "object" and its id.
function M.OpenDatabaseEntry(kind, id)
    if A.ShowView then A.ShowView("database") end
    local body = A.databaseBody
    local frame = body and body.tabFrames and body.tabFrames.db
    if not (frame and frame.db) then return false end
    local s = frame.db
    s.kind, s.query, s.offset, s.selected = kind, "", 0, {kind = kind, id = id}
    if s.box then s.box:SetText("") end
    M.WorldDbRefresh(frame)
    return true
end

--- What the database knows about one entry as rows for the details window of a record: {title, sub, icon}. When it knows nothing, one row says so.
function M.DatabaseRows(kind, id)
    local db = Db.Open()
    local d = db and Db.Detail(db, kind, id)
    if not d then
        -- a quest the database lacks may still be in the dungeon journal (it lists the quests of every dungeon with their ids)
        local journal = kind == "quest" and M.DungeonQuestRows and M.DungeonQuestRows(id)
        if journal then return journal end
        return {{title = A.L("worldDbUnknown"), sub = A.L("worldDbUnknownSub")}}
    end
    local rows = {}
    if d.subtitle ~= "" then rows[#rows + 1] = {title = A.Plain(d.title), sub = A.Plain(d.subtitle)} else rows[#rows + 1] = {title = A.Plain(d.title)} end
    local heading
    for _, line in ipairs(d.lines) do
        if line:find("|c", 1, true) then heading = A.Plain((line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
        else rows[#rows + 1] = {title = A.Plain(line), sub = heading} end
    end
    return rows
end
