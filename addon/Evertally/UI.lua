local _, A = ...
-- Evertally window: dark dusk theme matching the website. Only built-in game textures are
-- used (plus the addon logo with a built-in fallback), so nothing depends on new files.

local WIDTH, HEIGHT, HEADER, SIDEBAR, PAD, ROW = 880, 580, 54, 178, 20, 42
local LOGO = "Interface\\AddOns\\Evertally\\Media\\Logo"
local C = {
    canvas = {0.075, 0.067, 0.110}, header = {0.106, 0.090, 0.165}, side = {0.090, 0.082, 0.133},
    card = {0.125, 0.118, 0.188}, well = {0.055, 0.052, 0.075}, line = {1, 1, 1, 0.08},
    text = {0.97, 0.97, 0.97}, mist = {0.66, 0.65, 0.70}, faint = {0.45, 0.46, 0.52},
    violet = {0.333, 0.247, 0.514}, lilac = {0.655, 0.545, 0.980}, green = {0.37, 0.72, 0.55},
    peach = {0.92, 0.70, 0.54}, red = {0.89, 0.47, 0.42}, off = {0.26, 0.25, 0.31},
}
local ICON = {
    overview = "Interface\\Icons\\INV_Misc_Book_09", history = "Interface\\Icons\\INV_Sword_04",
    facts = "Interface\\Icons\\INV_Misc_Map_01", rankings = "Interface\\Icons\\Ability_Warrior_BattleShout",
    peers = "Interface\\Icons\\INV_Misc_GroupNeedMore", settings = "Interface\\Icons\\INV_Misc_Gear_01",
    social = "Interface\\Icons\\INV_Misc_Note_01", community = "Interface\\Icons\\INV_Misc_Map_01", professions = "Interface\\Icons\\Trade_Engineering", places = "Interface\\Icons\\INV_Misc_Map_01",
    quest = "Interface\\GossipFrame\\AvailableQuestIcon", questDone = "Interface\\GossipFrame\\ActiveQuestIcon",
    npc = "Interface\\Icons\\INV_Misc_Head_Human_01", vendor = "Interface\\Icons\\INV_Misc_Bag_10",
    item = "Interface\\Icons\\INV_Misc_Bag_08", profession = "Interface\\Icons\\Trade_Engineering",
    craft = "Interface\\Icons\\Trade_BlackSmithing", cooldown = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    raid = "Interface\\Icons\\INV_Misc_Head_Dragon_01", run = "Interface\\Icons\\INV_Sword_04",
    unknown = "Interface\\Icons\\INV_Misc_QuestionMark",
}
local VIEWS = {"overview", "history", "professions", "places", "facts", "rankings", "peers", "community", "social", "settings"}

local frame, content, pages, navButtons, header = nil, nil, {}, {}, {}
local fontStrings, toggles, copyFrame, minimapButton = {}, {}, nil, nil
local selected = "overview"
local showRun, showEvent, showProfession, showCommunityDetail

-- ---------- helpers ----------

local function paint(tex, c, alpha)
    local a = alpha or c[4] or 1
    if tex.SetColorTexture then tex:SetColorTexture(c[1], c[2], c[3], a)
    else tex:SetTexture("Interface\\Buttons\\WHITE8X8"); tex:SetVertexColor(c[1], c[2], c[3], a) end
end
local function fill(parent, c, alpha, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints(parent); paint(t, c, alpha); return t
end
local function gradient(tex, top, bottom)
    -- Modern clients take colour objects, older ones take numbers; fall back to a flat fill.
    if type(CreateColor) == "function" and pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1)) then return end
    if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, "VERTICAL", bottom[1], bottom[2], bottom[3], 1, top[1], top[2], top[3], 1) then return end
end
local function outline(f, c)
    for _, side in ipairs({{"TOPLEFT", "TOPRIGHT", nil, 1}, {"BOTTOMLEFT", "BOTTOMRIGHT", nil, 1}, {"TOPLEFT", "BOTTOMLEFT", 1, nil}, {"TOPRIGHT", "BOTTOMRIGHT", 1, nil}}) do
        local t = f:CreateTexture(nil, "BORDER"); paint(t, c or C.line)
        t:SetPoint(side[1]); t:SetPoint(side[2])
        if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
    end
end

-- Czech needs glyphs that Friz Quadrata lacks; prefer the WoWF.cz font, else Arial Narrow.
local probe, fontOk = nil, {}
local function canUseFont(path)
    if fontOk[path] ~= nil then return fontOk[path] end
    if not probe then local holder = CreateFrame("Frame"); holder:Hide(); probe = holder:CreateFontString(nil, "ARTWORK") end
    local ok = pcall(probe.SetFont, probe, path, 12, "")
    local applied = ok and probe.GetFont and probe:GetFont()
    ok = ok and (applied == nil or tostring(applied):gsub("/", "\\"):lower() == path:gsub("/", "\\"):lower())
    fontOk[path] = ok and true or false
    return fontOk[path]
end
local function fontPath()
    if A.db and A.db.settings.language == "cs" then
        if canUseFont("Interface\\AddOns\\WowfCZ\\Fonts\\FRIZQT__.ttf") then return "Interface\\AddOns\\WowfCZ\\Fonts\\FRIZQT__.ttf" end
        return "Fonts\\ARIALN.TTF"
    end
    return "Fonts\\FRIZQT__.TTF"
end
function A.FontPath() return fontPath() end
local function label(parent, size, c, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(fontPath(), size, ""); fs:SetTextColor(c[1], c[2], c[3], c[4] or 1); fs:SetJustifyH("LEFT")
    fontStrings[#fontStrings + 1] = {fs = fs, size = size}
    return fs
end
local function applyFonts()
    local path = fontPath()
    for _, entry in ipairs(fontStrings) do entry.fs:SetFont(path, entry.size, "") end
end
local function plain(v) local text = tostring(A.Plain(v) or A.L("unknown")); return (text:gsub("|", "||")) end
local function stamp(at) at = A.Number(at, 0); return at and (A.Call(date, "%d.%m. %H:%M", at) or tostring(at)) or "?" end
local function duration(ms)
    local s = math.floor((A.Number(ms, 0) or 0) / 1000)
    if s >= 3600 then return string.format("%d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60) end
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
local function setIcon(tex, path)
    tex:SetTexture(path or ICON.unknown)
    if type(path) == "number" or (type(path) == "string" and path:find("^Interface\\Icons\\")) then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else tex:SetTexCoord(0, 1, 0, 1) end
end
local function setLogo(tex)
    if tex:SetTexture(LOGO) == false then setIcon(tex, ICON.overview) else tex:SetTexCoord(0, 1, 0, 1) end
end
local function classIcon(tex, classId)
    if A.SetClassIcon then A.SetClassIcon(tex, classId); return end
    local _, classFile = A.Call(GetClassInfo, A.Number(classId, 1, 100))
    local coords = classFile and type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[classFile]
    if coords then tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles"); tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else setIcon(tex, ICON.npc) end
end
local function classColor(classId)
    if A.ClassColor then return A.ClassColor(classId) end
    local _, classFile = A.Call(GetClassInfo, A.Number(classId, 1, 100))
    local c = classFile and type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[classFile]
    return c and {c.r, c.g, c.b} or C.text
end
local function raceIcon(tex, raceId)
    if A.SetRaceIcon then A.SetRaceIcon(tex, raceId) else setIcon(tex, ICON.npc) end
end
local function identityText(c)
    if A.IdentityText then return A.IdentityText(c) end
    return c and c.level and (A.L("level") .. " " .. plain(c.level)) or A.L("unknown")
end
local function mapName(id)
    local info = C_Map and A.Call(C_Map.GetMapInfo, id)
    return plain(A.Field(info, "name") or (A.L("map") .. " #" .. tostring(id)))
end
local function itemIcon(itemId)
    local icon = A.Call(GetItemIcon, itemId)
    if not icon and C_Item then icon = A.Call(C_Item.GetItemIconByID, itemId) end
    return icon
end

-- ---------- controls ----------

local function Button(parent, key, width, kind, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 30)
    local bg = fill(b, kind == "primary" and C.violet or {1, 1, 1}, kind == "primary" and 1 or 0.08)
    local text = label(b, 12, C.text); text:SetPoint("CENTER"); text:SetJustifyH("CENTER")
    b.text, b.localeKey = text, key
    b:SetScript("OnEnter", function() bg:SetAlpha(0.8) end)
    b:SetScript("OnLeave", function() bg:SetAlpha(1) end)
    b:SetScript("OnClick", onClick)
    return b
end

local function Toggle(parent, key, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(560, 26)
    local track = b:CreateTexture(nil, "ARTWORK"); track:SetSize(30, 16); track:SetPoint("LEFT")
    local knob = b:CreateTexture(nil, "OVERLAY"); knob:SetSize(12, 12); paint(knob, C.text)
    local text = label(b, 12, C.text); text:SetPoint("LEFT", track, "RIGHT", 10, 0)
    b.localeKey, b.get = key, get
    function b.Update()
        local on = get() == true
        paint(track, on and C.lilac or C.off)
        knob:ClearAllPoints(); knob:SetPoint("LEFT", track, "LEFT", on and 16 or 2, 0)
        text:SetText(A.L(key))
        b:SetAlpha(b.disabled and b.disabled() and 0.45 or 1)
    end
    b:SetScript("OnClick", function()
        if b.disabled and b.disabled() then return end
        set(not get()); A.RefreshUI()
    end)
    toggles[#toggles + 1] = b
    return b
end

local function Pill(parent)
    local f = CreateFrame("Frame", nil, parent); f:SetSize(80, 20)
    f.bg = fill(f, C.off, 0.5)
    f.text = label(f, 10, C.text); f.text:SetPoint("CENTER")
    function f.Set(text, c)
        f.text:SetText(text); f.text:SetTextColor(c[1], c[2], c[3])
        paint(f.bg, c, 0.16); f:SetWidth((f.text:GetStringWidth() or 40) + 16)
    end
    return f
end

-- ---------- scrollable list ----------

local function ScrollArea(parent, top)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", 0, -top); scroll:SetPoint("BOTTOMRIGHT", -8, 0)
    local child = CreateFrame("Frame", nil, scroll); child:SetSize(WIDTH - SIDEBAR - PAD * 2 - 8, 10)
    scroll:SetScrollChild(child)
    local thumb = scroll:CreateTexture(nil, "OVERLAY"); thumb:SetWidth(3); paint(thumb, C.lilac, 0.5)
    local function update()
        local view, total = scroll:GetHeight() or 1, child:GetHeight() or 1
        if total <= view + 1 then thumb:Hide(); scroll:SetVerticalScroll(0); return end
        local size = math.max(24, view * view / total)
        local offset = (scroll:GetVerticalScroll() or 0) / (total - view) * (view - size)
        thumb:ClearAllPoints(); thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 6, -offset); thumb:SetHeight(size); thumb:Show()
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * ROW * 2))); update()
    end)
    scroll.child, scroll.UpdateThumb = child, update
    return scroll
end

local function NewRow(parent)
    local r = CreateFrame("Button", nil, parent); r:SetHeight(ROW - 4)
    local bg = fill(r, C.card, 0.55)
    r:SetScript("OnEnter", function(self)
        bg:SetAlpha(1)
        if self.itemId and GameTooltip then pcall(function() GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.itemId); GameTooltip:Show() end) end
    end)
    r:SetScript("OnLeave", function() bg:SetAlpha(0.55); if GameTooltip then GameTooltip:Hide() end end)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(26, 26); r.icon:SetPoint("LEFT", 8, 0)
    r.raceIcon = r:CreateTexture(nil, "ARTWORK"); r.raceIcon:SetSize(22, 22); r.raceIcon:SetPoint("LEFT", r.icon, "RIGHT", 4, 0); r.raceIcon:Hide()
    r.title = label(r, 13, C.text); r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 1)
    r.sub = label(r, 10, C.mist); r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 1)
    r.right = label(r, 13, C.text); r.right:SetPoint("RIGHT", -12, 0); r.right:SetJustifyH("RIGHT")
    r.tag = Pill(r); r.tag:SetPoint("RIGHT", r.right, "LEFT", -10, 0)
    r.chevron = label(r, 12, C.lilac); r.chevron:SetPoint("RIGHT", -7, 0)
    r:SetScript("OnClick", function(self) if type(self.action) == "function" then self.action() end end)
    return r
end

local function ListView(parent, top)
    local scroll = ScrollArea(parent, top)
    local rows, empty = {}, label(scroll, 12, C.mist)
    empty:SetPoint("TOP", 0, -40); empty:SetWidth(460); empty:SetJustifyH("CENTER")
    function scroll.SetItems(items, emptyText)
        local width = scroll.child:GetWidth() or 640
        for i, item in ipairs(items) do
            local r = rows[i] or NewRow(scroll.child); rows[i] = r
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW); r:SetWidth(width)
            if item.class then classIcon(r.icon, item.class) else setIcon(r.icon, item.icon) end
            r.raceIcon:SetShown(item.race ~= nil)
            if item.race then raceIcon(r.raceIcon, item.race) end
            local anchor = item.race and r.raceIcon or r.icon
            r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 10, 1)
            r.sub:ClearAllPoints(); r.sub:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 10, 1)
            r.title:SetWidth(math.max(120, width - (item.race and 300 or 274)))
            r.sub:SetWidth(math.max(120, width - (item.race and 180 or 154)))
            r.title:SetWordWrap(false); r.sub:SetWordWrap(false)
            r.right:SetWidth(100); r.right:ClearAllPoints(); r.right:SetPoint("RIGHT", item.onClick and -26 or -12, 0)
            r.action = item.onClick; r.itemId = item.itemId; r.chevron:SetText(item.onClick and ">" or "")
            r.title:SetText(item.title or ""); r.sub:SetText(item.sub or ""); r.right:SetText(item.right or "")
            local tc = item.titleColor or C.text; r.title:SetTextColor(tc[1], tc[2], tc[3])
            if item.tag then r.tag.Set(item.tag, item.tagColor or C.mist); r.tag:Show() else r.tag:Hide() end
            r:Show()
        end
        for i = #items + 1, #rows do rows[i]:Hide() end
        scroll.child:SetHeight(math.max(1, #items * ROW))
        empty:SetText(#items == 0 and (emptyText or A.L("noData")) or "")
        scroll.UpdateThumb()
    end
    return scroll
end

-- ---------- data → rows ----------

local function eventItem(e)
    local p, kind = e.payload or {}, e.kind
    local item = {title = plain(p.title or p.name or (kind=="zone.visited" and p.mapName) or (p.questId and "Quest #" .. p.questId) or (p.itemId and "Item #" .. p.itemId) or kind),
        sub = A.L(kind) .. "  ·  " .. stamp(e.observedAt), tag = A.L(kind):upper(), tagColor = C.mist}
    if kind == "quest.accepted" then item.icon, item.tagColor = ICON.quest, C.peach
    elseif kind == "quest.turned_in" then item.icon, item.tagColor = ICON.questDone, C.green
    elseif kind == "quest.abandoned" then item.icon = ICON.quest
    elseif kind == "npc.observed" then item.icon = ICON.npc
    elseif kind == "vendor.snapshot" then item.icon, item.right = ICON.vendor, (type(p.items) == "table" and #p.items or 0) .. " " .. A.L("items")
    elseif kind == "loot.received" then
        item.icon, item.tagColor = itemIcon(p.itemId) or ICON.item, C.lilac
        if (A.Number(p.quantity, 1) or 1) > 1 then item.right = "x" .. p.quantity end
    elseif kind == "profession.snapshot" then item.icon, item.right = ICON.profession, (p.skill or "?") .. "/" .. (p.maxSkill or "?")
    elseif kind == "craft.result" then item.icon = itemIcon(p.itemId) or ICON.craft
    elseif kind == "cooldown.snapshot" then item.icon = ICON.cooldown
    elseif kind == "character.snapshot" or kind == "character.level" then item.class, item.right = p.classId, A.L("level") .. " " .. (p.level or "?")
    elseif kind == "raid.encounter_finished" then item.icon, item.right = ICON.raid, duration(p.durationMs)
    else item.icon, item.right = ICON.run, p.durationMs and duration(p.durationMs) or nil end
    item.onClick = function() showEvent(e) end
    if p.mapId and kind ~= "loot.received" then
        local x,y=A.Number(p.x,0,1),A.Number(p.y,0,1)
        local worldPosition=A.ScopeFor[kind]=="world_facts" and kind~="zone.visited"
        item.sub = item.sub .. "  ·  " .. mapName(p.mapId) .. (worldPosition and x and y and string.format("  %.1f, %.1f", x * 100, y * 100) or "")
    end
    return item
end

local function runItem(run, live)
    local status = run.status == "manual" and "manualStatus" or run.status
    local tag, tc = A.L(status), C.mist
    if live then tag, tc = A.L("live"), C.lilac
    elseif run.completion == "full_clear" then tag, tc = A.L("full_clear"), C.green
    elseif run.completion == "last_boss" then tag, tc = A.L("last_boss"), C.peach
    elseif run.status == "interrupted" then tc = C.red end
    local c=type(run.character)=="table" and run.character or nil
    return {icon = run.instanceType == "raid" and ICON.raid or ICON.run, class=c and c.classId, race=c and c.raceId, title = plain(run.name),
        sub = stamp(run.startedAt) .. "  ·  " .. (c and plain(c.name) .. "  ·  " or "") .. (run.bossCount or 0) .. " " .. A.L("bosses"),
        right = run.durationMs and duration(run.durationMs) or "—", tag = tostring(tag):upper(), tagColor = tc,
        onClick=function() showRun(run,live) end}
end

local function rankingItems()
    local db, character = A.db, A.Character()
    local own = 0
    for _, run in ipairs(db.runs) do if run.character and character and run.character.id == character.id and run.status == "completed" then own = own + 1 end end
    local rows = {{name = character and character.name or "?", character = character, count = own, source = A.L("myself")}}
    local seen = {[db.producerId .. ":" .. (character and character.id or "unknown")] = true}
    for sender, peer in pairs(A.peerDB.peers) do
        local key = tostring(peer.producerId) .. ":" .. (peer.character and peer.character.id or sender)
        if not seen[key] then
            seen[key] = true
            local count = peer.completedRuns
            if count == nil then count = 0; for _, run in ipairs(peer.runs or {}) do if run.status == "completed" then count = count + 1 end end end
            rows[#rows + 1] = {name = peer.character and peer.character.name or sender, character = peer.character, count = count, source = A.L("received") .. " " .. stamp(peer.receivedAt)}
        end
    end
    table.sort(rows, function(a, b) if a.count == b.count then return plain(a.name) < plain(b.name) end return a.count > b.count end)
    local items = {}
    for i, row in ipairs(rows) do
        local c = row.character
        items[#items + 1] = {class = c and c.classId, race=c and c.raceId, title = i .. ".  " .. plain(row.name), titleColor = classColor(c and c.classId),
            sub = identityText(c) .. "  ·  " .. row.source, right = tostring(row.count)}
    end
    return items
end

-- ---------- pages ----------

local function PageHeader(page, key)
    page.title = label(page, 20, C.text); page.title:SetPoint("TOPLEFT", 0, 0)
    page.subtitle = label(page, 11, C.mist); page.subtitle:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -6)
    page.subtitle:SetWidth(WIDTH - SIDEBAR - PAD * 2)
    page.titleKey = key
end

local function StatCard(parent, index, iconPath, key)
    local width = (WIDTH - SIDEBAR - PAD * 2 - 30) / 4
    local card = CreateFrame("Frame", nil, parent); card:SetSize(width, 78)
    card:SetPoint("TOPLEFT", (index - 1) * (width + 10), -52)
    fill(card, C.card); outline(card)
    local accent = card:CreateTexture(nil, "ARTWORK"); accent:SetHeight(2); accent:SetPoint("TOPLEFT"); accent:SetPoint("TOPRIGHT"); paint(accent, C.lilac, 0.6)
    local icon = card:CreateTexture(nil, "ARTWORK"); icon:SetSize(22, 22); icon:SetPoint("TOPLEFT", 12, -12); setIcon(icon, iconPath)
    card.value = label(card, 24, C.text); card.value:SetPoint("TOPRIGHT", -12, -10); card.value:SetJustifyH("RIGHT")
    card.caption = label(card, 10, C.mist); card.caption:SetPoint("BOTTOMLEFT", 12, 10); card.caption:SetWidth(width - 24)
    card.key = key
    return card
end

local function buildOverview(page)
    PageHeader(page, "overview")
    page.cards = {StatCard(page, 1, ICON.facts, "count"), StatCard(page, 2, ICON.history, "runs"), StatCard(page, 3, ICON.overview, "pending"), StatCard(page, 4, ICON.peers, "players")}
    page.who = CreateFrame("Frame", nil, page); page.who:SetSize(400, 22); page.who:SetPoint("TOPRIGHT", 0, -4)
    page.whoIcon = page.who:CreateTexture(nil, "ARTWORK"); page.whoIcon:SetSize(18, 18); page.whoIcon:SetPoint("RIGHT")
    page.whoRace = page.who:CreateTexture(nil, "ARTWORK"); page.whoRace:SetSize(18, 18); page.whoRace:SetPoint("RIGHT", page.whoIcon, "LEFT", -4, 0)
    page.whoText = label(page.who, 12, C.text); page.whoText:SetPoint("RIGHT", page.whoRace, "LEFT", -6, 0); page.whoText:SetJustifyH("RIGHT"); page.whoText:SetWidth(350)
    page.recent = label(page, 13, C.text); page.recent:SetPoint("TOPLEFT", 0, -146)
    page.warning = label(page, 11, C.peach); page.warning:SetPoint("TOPRIGHT", 0, -148); page.warning:SetJustifyH("RIGHT")
    page.list = ListView(page, 168)
    function page.Refresh()
        local db, out = A.db, A.ExportStore()
        local peers = 0; for _ in pairs(A.peerDB.peers) do peers = peers + 1 end
        local values = {#db.events, #db.runs, out and #out.events or 0, peers}
        for i, card in ipairs(page.cards) do card.value:SetText(tostring(values[i])); card.caption:SetText(A.L(card.key)) end
        local c = A.Character()
        if c then
            classIcon(page.whoIcon, c.classId)
            raceIcon(page.whoRace, c.raceId)
            page.whoText:SetText(plain(c.name) .. "  ·  " .. plain(c.realm) .. "  ·  " .. A.L("level") .. " " .. plain(c.level))
            local cc = classColor(c.classId); page.whoText:SetTextColor(cc[1], cc[2], cc[3])
        end
        page.recent:SetText(A.L("recent"))
        page.warning:SetText((A.storageFull or A.exportFull) and A.L("capped") or "")
        local items, run = {}, A.ActiveRun()
        if run then items[1] = runItem(run, true) end
        for i = #db.events, math.max(1, #db.events - 59), -1 do items[#items + 1] = eventItem(db.events[i]) end
        page.list.SetItems(items, A.L("noData"))
    end
end

local function buildList(page, key, source)
    PageHeader(page, key)
    page.list = ListView(page, 52)
    function page.Refresh() local items, empty = source(); page.list.SetItems(items, empty) end
end

local communityImportFrame
local function showCommunityImport()
    if not communityImportFrame then
        local f = CreateFrame("Frame", "EvertallyCommunityImport", UIParent)
        communityImportFrame = f
        f:SetSize(720, 460); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:EnableMouse(true)
        fill(f, C.canvas, 0.99); outline(f)
        f.hint = label(f, 12, C.mist); f.hint:SetPoint("TOPLEFT", 18, -16); f.hint:SetWidth(680)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -68); scroll:SetPoint("BOTTOMRIGHT", -38, 82)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFont(fontPath(), 12, "")
        fontStrings[#fontStrings + 1] = {fs=edit,size=12}
        edit:SetWidth(660); edit:SetMaxLetters(A.COMMUNITY_MAX_BYTES + 1)
        edit:SetScript("OnEscapePressed", function() f:Hide() end); scroll:SetScrollChild(edit); f.edit = edit
        f.status = label(f, 11, C.peach); f.status:SetPoint("BOTTOMLEFT", 18, 58); f.status:SetWidth(680)
        f.submit = Button(f, "communityImport", 160, "primary", function()
            local ok, result = A.ImportCommunity(edit:GetText())
            if ok then edit:SetText(""); f.status:SetText(A.L("communityImported") .. " " .. result)
            else f.status:SetText(A.L(result or "communityInvalid")) end
        end)
        f.submit:SetPoint("BOTTOMLEFT", 18, 16)
        f.close = Button(f, "close", 110, "ghost", function() f:Hide() end); f.close:SetPoint("BOTTOMRIGHT", -18, 16)
        if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames+1] = "EvertallyCommunityImport" end
    end
    local f = communityImportFrame
    f.hint:SetText(A.L("communityPaste")); f.submit.text:SetText(A.L("communityImport")); f.close.text:SetText(A.L("close"))
    f.status:SetText(""); f:Show()
end

local function buildCommunity(page)
    PageHeader(page, "community")
    page.kind, page.query = "", ""
    page.import = Button(page, "communityImport", 140, "primary", showCommunityImport); page.import:SetPoint("TOPLEFT", 0, -62)
    page.clear = Button(page, "communityClear", 90, "ghost", function() A.ClearCommunity() end); page.clear:SetPoint("LEFT", page.import, "RIGHT", 8, 0)
    page.kindButton = Button(page, nil, 110, "ghost", function()
        local nextKind = {[""]="quest",quest="npc",npc="item",item=""}; page.kind = nextKind[page.kind]; A.RefreshUI()
    end)
    page.kindButton:SetPoint("LEFT", page.clear, "RIGHT", 8, 0)
    local search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    search:SetSize(230, 26); search:SetPoint("LEFT", page.kindButton, "RIGHT", 14, 0)
    search:SetAutoFocus(false); search:SetMaxLetters(200); search:SetFont(fontPath(), 12, "")
    fontStrings[#fontStrings+1] = {fs=search,size=12}
    search:SetScript("OnTextChanged", function(self) page.query=self:GetText() or ""; A.RefreshUI() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.info = label(page, 11, C.mist); page.info:SetPoint("TOPLEFT", 0, -106); page.info:SetWidth(640)
    page.list = ListView(page, 164)
    function page.Refresh()
        page.import.text:SetText(A.L("communityImport")); page.clear.text:SetText(A.L("communityClear"))
        page.kindButton.text:SetText(A.L("communityKind_" .. page.kind))
        local snapshot, stale = A.GetCommunity()
        local info = A.L("communityNoData")
        if snapshot then info = string.format("%s %s  ·  %s %s\n%s %d/%d  ·  %s %d%s", A.L("communityGenerated"), stamp(snapshot.generatedAt),
            A.L("communityExpires"), stamp(snapshot.expiresAt), A.L("communityEntities"), #snapshot.entities, snapshot.provenance.entityCount,
            A.L("count"), snapshot.provenance.observationCount, stale and ("  ·  " .. A.L("communityStale")) or "") end
        page.info:SetText(info)
        local items = {}
        for _, e in ipairs(A.CommunityEntries(page.kind, page.query)) do
            items[#items+1] = {title=plain(e.name),icon=e.kind=="npc" and ICON.npc or e.kind=="item" and ICON.item or ICON.quest,
                sub=e.kind .. " #" .. e.id .. "  ·  " .. stamp(e.lastSeen) .. (e.mapId and ("  ·  " .. mapName(e.mapId)) or "") ..
                    (e.x and e.y and string.format("  %.1f, %.1f", e.x*100,e.y*100) or ""),right=tostring(e.count),tag=A.L("community"),tagColor=C.lilac,
                onClick=function() showCommunityDetail(e) end}
        end
        page.list.SetItems(items, A.L("communityNoData"))
    end
end

local function historyItems()
    local items, run = {}, A.ActiveRun()
    if run then items[1] = runItem(run, true) end
    for i = #A.db.runs, math.max(1, #A.db.runs - 199), -1 do items[#items + 1] = runItem(A.db.runs[i]) end
    return items, A.L("noRuns")
end
local function factItems()
    local items = {}
    for i = #A.db.events, math.max(1, #A.db.events - 199), -1 do
        local e = A.db.events[i]
        if A.ScopeFor[e.kind] == "world_facts" then items[#items + 1] = eventItem(e) end
    end
    return items, A.L("noData")
end
local function peerItems()
    local items = {}
    for sender, peer in pairs(A.peerDB.peers) do
        local c = peer.character
        items[#items + 1] = {class = c and c.classId, race=c and c.raceId, title = plain(sender), titleColor = classColor(c and c.classId),
            sub = identityText(c) .. "  ·  " .. A.L("seen") .. " " .. stamp(peer.receivedAt), right = tostring(#(peer.runs or {})) .. " " .. A.L("history"):lower()}
    end
    table.sort(items, function(a, b) return a.title < b.title end)
    return items, A.L("noPeers")
end

-- Details read retained own observations; opening a row never records, exports or
-- shares anything. Missing values stay unknown rather than becoming zero.
local detailFrame
local function showDetails(title, subtitle, items, position)
    if not detailFrame then
        local f=CreateFrame("Frame","EvertallyDetailFrame",UIParent);detailFrame=f
        f:SetSize(720,500);f:SetPoint("CENTER");f:SetFrameStrata("DIALOG");f:EnableMouse(true)
        fill(f,C.canvas,0.99);outline(f)
        f.title=label(f,18,C.text);f.title:SetPoint("TOPLEFT",18,-16);f.title:SetWidth(680)
        f.subtitle=label(f,11,C.mist);f.subtitle:SetPoint("TOPLEFT",18,-44);f.subtitle:SetWidth(680)
        f.list=ListView(f,86);f.list:ClearAllPoints();f.list:SetPoint("TOPLEFT",18,-86);f.list:SetPoint("BOTTOMRIGHT",-26,58);f.list.child:SetWidth(676)
        f.close=Button(f,"close",110,"ghost",function() f:Hide() end);f.close:SetPoint("BOTTOMRIGHT",-18,16)
        f.map=Button(f,"openMap",140,"primary",function()
            if not A.OpenRecordedMap(f.position) then A.Print(A.L("mapUnavailable")) end
        end);f.map:SetPoint("BOTTOMLEFT",18,16)
        if type(UISpecialFrames)=="table" then UISpecialFrames[#UISpecialFrames+1]="EvertallyDetailFrame" end
    end
    local f=detailFrame;f.position=position
    f.title:SetText(title);f.subtitle:SetText(subtitle or "")
    f.close.text:SetText(A.L("close"));f.map.text:SetText(A.L("openMap"));f.map:SetShown(position and A.Number(position.mapId,1,100000)~=nil)
    f.list:SetVerticalScroll(0);f.list.SetItems(items,A.L("noData"));f:Show()
end
function A.OpenRecordedMap(position)
    local id=type(position)=="table" and A.Number(position.mapId,1,100000)
    if not id or id~=math.floor(id) or (position.mapSystem and position.mapSystem~="ui_map") or A.Call(InCombatLockdown)==true then return false end
    if C_Map and type(C_Map.OpenWorldMap)=="function" then return pcall(C_Map.OpenWorldMap,id) end
    local map=WorldMapFrame
    if not map or type(map.SetMapID)~="function" then return false end
    if type(ShowUIPanel)=="function" then pcall(ShowUIPanel,map)
    elseif type(map.Show)=="function" then pcall(map.Show,map) end
    return pcall(map.SetMapID,map,id)
end
local function detailRow(key,value,icon)
    return {title=A.L(key),sub=plain(value),icon=icon or ICON.facts}
end
function A.RunDetailRows(run)
    if type(run)~="table" then return {} end
    local c=type(run.character)=="table" and run.character or nil
    local items={
        {title=c and plain(c.name) or A.L("unknown"),sub=identityText(c)..(c and c.realm and ("  ·  "..plain(c.realm)) or ""),class=c and c.classId,race=c and c.raceId,icon=ICON.npc},
        detailRow("runDuration",run.durationMs and duration(run.durationMs) or A.L("unknown"),ICON.cooldown),
        detailRow("runStarted",stamp(run.startedAt)),detailRow("runEnded",run.endedAt and stamp(run.endedAt) or A.L("currentRun")),
        detailRow("runDifficulty",A.Call(GetDifficultyInfo,run.difficultyId) or run.difficultyId),detailRow("runDeaths",run.deaths),detailRow("runGroup",run.groupSize),
        detailRow("runLevels",(run.minLevel and tostring(run.minLevel) or "?").." – "..(run.maxLevel and tostring(run.maxLevel) or "?")),
        detailRow("runFinish",A.L(run.completion or "unknown")),
    }
    local started,ended,previous=A.Number(run.startedAt,0),A.Number(run.endedAt,0),nil
    for i,boss in ipairs(type(run.bosses)=="table" and run.bosses or {}) do
        if type(boss)=="table" then
            local at=A.Number(boss.killedAt,0)
            local valid=at and started and at>=started and (not ended or at<=ended) and (not previous or at>=previous)
            local elapsed=valid and (at-started)*1000 or nil
            local split=valid and previous and (at-previous)*1000 or nil
            items[#items+1]={title=i..". "..plain(boss.name or boss.encounterId),sub=A.L("bossSinceStart")..": "..(elapsed and duration(elapsed) or A.L("unknown"))..
                (split and ("  ·  "..A.L("bossSplit")..": "..duration(split)) or ""),right=at and stamp(at) or "—",icon=ICON.raid}
            previous=valid and at or nil
        end
    end
    if type(run.bosses)~="table" or #run.bosses==0 then items[#items+1]=detailRow("bossTimeline",A.L("noBossTimeline"),ICON.raid) end
    return items
end
showRun=function(run,live)
    showDetails(plain(run.name),A.L(live and "currentRun" or "sub_history"),A.RunDetailRows(run))
end
A.UIShowRunDetail=showRun
local function positionRows(p,items,exact)
    local map=A.Number(p.mapId,1,100000);if not map then return end
    items[#items+1]=detailRow("map",p.mapName or mapName(map))
    local x,y=A.Number(p.x,0,1),A.Number(p.y,0,1)
    if x and y then
        items[#items+1]=detailRow("coordinates",string.format("%.1f, %.1f",x*100,y*100))
        items[#items+1]=detailRow("positionSource",A.L(exact and "exactPosition" or "source"))
    end
end
showEvent=function(e)
    local p=type(e.payload)=="table" and e.payload or {}
    local items={detailRow("observedAt",stamp(e.observedAt)),detailRow("observationType",A.L(e.kind))}
    if p.npcId then items[#items+1]=detailRow("npcId",p.npcId,ICON.npc) end
    if p.questId then items[#items+1]=detailRow("questId",p.questId,ICON.quest) end
    if p.itemId then items[#items+1]={title=plain(p.name or ("Item #"..p.itemId)),sub=A.L("itemId")..": "..p.itemId,icon=itemIcon(p.itemId) or ICON.item,right=p.quantity and ("x"..p.quantity) or ""} end
    if p.xp then items[#items+1]=detailRow("questXP",p.xp) end
    if p.money then items[#items+1]=detailRow("questMoney",p.money) end
    if e.kind=="zone.visited" then
        -- Area visits deliberately contain no player coordinates.
        if p.mapId then items[#items+1]=detailRow("map",p.mapName or mapName(p.mapId)) end
    elseif A.ScopeFor[e.kind]=="world_facts" then positionRows(p,items,p.positionMethod=="unit_position") end
    for _,item in ipairs(type(p.items)=="table" and p.items or {}) do
        if type(item)=="table" then
            items[#items+1]={title=plain(item.name or ("Item #"..tostring(item.itemId))),sub=A.L("vendorPrice")..": "..plain(item.price),
                right=item.quantity and ("x"..item.quantity) or "",icon=itemIcon(item.itemId) or ICON.item}
        end
    end
    showDetails(plain(p.title or p.name or A.L(e.kind)),A.L(e.kind),items,p)
end
A.UIShowEventDetail=showEvent
showCommunityDetail=function(e)
    local items={detailRow("observedAt",stamp(e.lastSeen)),detailRow("count",e.count),detailRow("observationType",e.kind.." #"..e.id)}
    positionRows(e,items,true)
    showDetails(plain(e.name),A.L("community"),items,e)
end

local function fold(text)
    text=tostring(text or ""):gsub("[A-Z]",string.lower)
    for upper,lower in pairs({["Á"]="á",["Č"]="č",["Ď"]="ď",["É"]="é",["Ě"]="ě",["Í"]="í",["Ň"]="ň",["Ó"]="ó",["Ř"]="ř",["Š"]="š",["Ť"]="ť",["Ú"]="ú",["Ů"]="ů",["Ý"]="ý",["Ž"]="ž"}) do text=text:gsub(upper,lower) end
    return text
end
function A.ProfessionSummaries()
    local sources,crafts,cooldowns={},{},{}
    for _,e in ipairs(A.db.events or {}) do
        local p=type(e.payload)=="table" and e.payload or {}
        local c=type(e.character)=="table" and e.character or nil
        local source=c and A.Text(c.id,100) or "unknown"
        local at=A.Number(e.observedAt,0) or 0
        if e.kind=="profession.snapshot" and A.Number(p.professionId,1,1000000) then
            local key=source..":"..p.professionId
            if not sources[key] or at>=sources[key].observedAt then sources[key]={key=key,source=source,character=c,observedAt=at,payload=p} end
        elseif e.kind=="craft.result" and A.Number(p.recipeId,1,10000000) then
            local key=source..":"..p.recipeId;crafts[key]=(crafts[key] or 0)+1
        elseif e.kind=="cooldown.snapshot" and A.Number(p.recipeId,1,10000000) and A.Number(p.readyAt,0) then
            local key=source..":"..p.recipeId
            if not cooldowns[key] or at>=cooldowns[key].observedAt then cooldowns[key]={readyAt=p.readyAt,observedAt=at} end
        end
    end
    local out={}
    for _,entry in pairs(sources) do
        entry.recipes={}
        for _,recipe in ipairs(type(entry.payload.recipes)=="table" and entry.payload.recipes or {}) do
            if type(recipe)=="table" and recipe.learned==true and A.Number(recipe.recipeId,1,10000000) then
                local key=entry.source..":"..recipe.recipeId
                entry.recipes[#entry.recipes+1]={recipeId=recipe.recipeId,name=recipe.name,crafts=crafts[key] or 0,cooldown=cooldowns[key]}
            end
        end
        table.sort(entry.recipes,function(a,b) return fold(a.name or a.recipeId)<fold(b.name or b.recipeId) end)
        out[#out+1]=entry
    end
    table.sort(out,function(a,b) return fold(a.payload.name or a.payload.professionId)..a.key<fold(b.payload.name or b.payload.professionId)..b.key end)
    return out
end
local function recipeIcon(id)
    return A.Call(GetSpellTexture,id) or (C_Spell and A.Call(C_Spell.GetSpellTexture,id)) or ICON.profession
end
local function cooldownText(cooldown)
    if not cooldown then return "" end
    local left=cooldown.readyAt-A.Now()
    return left>0 and duration(left*1000) or A.L("cooldownReady")
end
local function recipeRow(entry,recipe)
    return {title=plain(recipe.name or ("Recipe #"..recipe.recipeId)),icon=recipeIcon(recipe.recipeId),
        sub=plain(entry.payload.name).."  ·  "..plain(entry.character and entry.character.name).."  ·  "..A.L("observedCrafts")..": "..recipe.crafts,
        right=cooldownText(recipe.cooldown),tag=recipe.cooldown and A.L("cooldown") or nil,tagColor=C.peach}
end
showProfession=function(entry)
    local p=entry.payload
    local items={detailRow("professionSkill",(p.skill~=nil and p.skill or "?").."/"..(p.maxSkill~=nil and p.maxSkill or "?"),ICON.profession),detailRow("observedAt",stamp(entry.observedAt))}
    for _,recipe in ipairs(entry.recipes) do items[#items+1]=recipeRow(entry,recipe) end
    showDetails(plain(p.name or p.professionId),plain(entry.character and entry.character.name).."  ·  "..A.L("professionSnapshot"),items)
end
A.UIShowProfessionDetail=showProfession
local function buildProfessions(page)
    PageHeader(page,"professions");page.mode="professions";page.query="";page.index=1
    page.modeButton=Button(page,nil,128,"ghost",function()
        page.mode=({professions="recipes",recipes="cooldowns",cooldowns="professions"})[page.mode];page.index=1;A.RefreshUI()
    end);page.modeButton:SetPoint("TOPLEFT",0,-62)
    local search=CreateFrame("EditBox",nil,page,"InputBoxTemplate");search:SetSize(248,26);search:SetPoint("LEFT",page.modeButton,"RIGHT",14,0)
    search:SetAutoFocus(false);search:SetMaxLetters(160);search:SetFont(fontPath(),12,"");fontStrings[#fontStrings+1]={fs=search,size=12}
    search:SetScript("OnTextChanged",function(self) page.query=self:GetText() or "";page.index=1;A.RefreshUI() end)
    search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    page.prev=Button(page,nil,32,"ghost",function() page.index=math.max(1,page.index-1);A.RefreshUI() end);page.prev:SetPoint("LEFT",search,"RIGHT",12,0);page.prev.text:SetText("<")
    page.next=Button(page,nil,32,"ghost",function() page.index=page.index+1;A.RefreshUI() end);page.next:SetPoint("LEFT",page.prev,"RIGHT",6,0);page.next.text:SetText(">")
    page.counter=label(page,11,C.mist);page.counter:SetPoint("LEFT",page.next,"RIGHT",8,0)
    page.info=label(page,11,C.mist);page.info:SetPoint("TOPLEFT",0,-106);page.info:SetWidth(640)
    page.list=ListView(page,144)
    function page.Refresh()
        local rows,query={},fold(page.query)
        page.modeButton.text:SetText(A.L("professionMode_"..page.mode));page.info:SetText(A.L("professionSnapshot"))
        for _,entry in ipairs(A.ProfessionSummaries()) do
            local p,c=entry.payload,entry.character
            if page.mode=="professions" then
                local matches=fold(p.name):find(query,1,true) or fold(c and c.name):find(query,1,true)
                for _,recipe in ipairs(entry.recipes) do if fold(recipe.name):find(query,1,true) then matches=true;break end end
                local current=entry
                if matches then rows[#rows+1]={title=plain(p.name or p.professionId),sub=plain(c and c.name).."  ·  "..stamp(entry.observedAt).."  ·  "..A.L("recipes")..": "..#entry.recipes,
                    icon=ICON.profession,right=(p.skill~=nil and p.skill or "?").."/"..(p.maxSkill~=nil and p.maxSkill or "?"),onClick=function() showProfession(current) end} end
            else
                for _,recipe in ipairs(entry.recipes) do
                    if (page.mode~="cooldowns" or recipe.cooldown) and fold((recipe.name or recipe.recipeId).." "..(p.name or "").." "..(c and c.name or "")):find(query,1,true) then rows[#rows+1]=recipeRow(entry,recipe) end
                end
            end
        end
        local total=math.max(1,math.ceil(#rows/100));page.index=math.min(page.index,total)
        local visible={};for i=(page.index-1)*100+1,math.min(#rows,page.index*100) do visible[#visible+1]=rows[i] end
        page.counter:SetText(page.index.." / "..total);page.prev:SetAlpha(page.index>1 and 1 or 0.35);page.next:SetAlpha(page.index<total and 1 or 0.35)
        page.list.SetItems(visible,A.L("noProfessions"))
    end
end
function A.PlaceSummaries()
    local areas={}
    for _,e in ipairs(A.db.events or {}) do
        local p=type(e.payload)=="table" and e.payload or {}
        local id=e.kind=="zone.visited" and A.Number(p.mapId,1,100000)
        if id then
            local key=tostring(p.mapSystem or "ui_map")..":"..id
            local area=areas[key] or {mapId=id,mapSystem=p.mapSystem,mapName=p.mapName,count=0,lastSeen=0};areas[key]=area
            area.count=area.count+1
            local at=A.Number(e.observedAt,0) or 0
            if at>=area.lastSeen then area.lastSeen=at;area.mapName=p.mapName or area.mapName end
        end
    end
    local out={};for _,area in pairs(areas) do out[#out+1]=area end
    table.sort(out,function(a,b) if a.lastSeen==b.lastSeen then return a.mapId<b.mapId end return a.lastSeen>b.lastSeen end)
    return out
end
local function placeItems()
    local items={}
    for _,area in ipairs(A.PlaceSummaries()) do
        items[#items+1]={title=plain(area.mapName or mapName(area.mapId)),sub=A.L("lastVisit")..": "..stamp(area.lastSeen),icon=ICON.places,
            right=tostring(area.count),tag=A.L("recordedVisits"),tagColor=C.lilac,onClick=function()
                showDetails(plain(area.mapName or mapName(area.mapId)),A.L("areaOnly"),{detailRow("recordedVisits",area.count),detailRow("lastVisit",stamp(area.lastSeen))},area)
            end}
    end
    return items,A.L("noPlaces")
end
local function buildPlaces(page)
    PageHeader(page,"places");page.info=label(page,12,C.lilac);page.info:SetPoint("TOPLEFT",0,-54)
    page.list=ListView(page,84)
    function page.Refresh()
        local items,empty=placeItems();local visits=0
        for _,area in ipairs(A.PlaceSummaries()) do visits=visits+area.count end
        page.info:SetText(A.L("visitedAreas")..": "..#items.."  ·  "..A.L("recordedVisits")..": "..visits)
        page.list.SetItems(items,empty)
    end
end

local function showCopy()
    local store = A.ExportStore()
    if not store or not store.enabled then A.Print(A.L("exportOff")); return end
    local json, err = A.Encode(store)
    if not json then A.Print(err or "export_error"); return end
    if not copyFrame then
        copyFrame = CreateFrame("Frame", "EvertallyCopyFrame", UIParent)
        copyFrame:SetSize(720, 460); copyFrame:SetPoint("CENTER"); copyFrame:SetFrameStrata("DIALOG"); copyFrame:EnableMouse(true)
        fill(copyFrame, C.canvas, 0.98); outline(copyFrame, {C.lilac[1], C.lilac[2], C.lilac[3], 0.35})
        local hint = label(copyFrame, 12, C.mist); hint:SetPoint("TOPLEFT", 18, -16); hint:SetWidth(680); hint:SetText(A.L("copyHint"))
        local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -56); scroll:SetPoint("BOTTOMRIGHT", -38, 52)
        local edit = CreateFrame("EditBox", nil, scroll); edit:SetMultiLine(true); edit:SetAutoFocus(false)
        edit:SetFont("Fonts\\ARIALN.TTF", 12, ""); edit:SetWidth(660); edit:SetMaxLetters(1048576)
        edit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
        scroll:SetScrollChild(edit); copyFrame.edit = edit
        Button(copyFrame, "close", 110, "ghost", function() copyFrame:Hide() end):SetPoint("BOTTOMRIGHT", -18, 14)
    end
    copyFrame:Show(); copyFrame.edit:SetText(json); copyFrame.edit:HighlightText(); copyFrame.edit:SetFocus()
end

local function SectionTitle(parent, key, y)
    local fs = label(parent, 13, C.lilac); fs:SetPoint("TOPLEFT", 0, y); fs.localeKey = key
    return fs
end

local function buildSettings(page)
    PageHeader(page, "settings")
    local scroll = ScrollArea(page, 52)
    local body, y = scroll.child, 0
    page.sections = {}
    local function section(key) page.sections[#page.sections + 1] = SectionTitle(body, key, y); y = y - 26 end
    local function place(control, height) control:SetPoint("TOPLEFT", 0, y); y = y - (height or 30) end
    local s = function() return A.db.settings end

    section("sharingSection")
    place(Toggle(body, "share", function() return s().ingame end, A.SetIngame))
    local group = Toggle(body, "group", function() return s().group end, function(v) s().group = v end); group.disabled = function() return not s().ingame end; place(group)
    local guild = Toggle(body, "guild", function() return s().guild end, function(v) s().guild = v end); guild.disabled = function() return not s().ingame end; place(guild)
    place(Toggle(body, "socialEnabled", function() return s().social ~= false end, function(v) s().social = v end))
    y = y - 10

    section("liveSection")
    place(Toggle(body, "liveParty", function() return s().liveParty == true end, function(v) A.SetLive("party", v) end))
    place(Toggle(body, "liveGuild", function() return s().liveGuild == true end, function(v) A.SetLive("guild", v) end))
    place(Toggle(body, "mapPins", function() return s().mapPins == true end, function(v) A.SetMapPins(v) end))
    page.liveHint = label(body, 11, C.mist); page.liveHint:SetPoint("TOPLEFT", 0, y - 2); page.liveHint:SetWidth(600); y = y - 66

    section("webSection")
    place(Toggle(body, "web", function() return s().web end, A.SetWeb))
    for _, scope in ipairs({"world_facts", "own_runs", "own_character", "own_professions", "own_track", "guild_share"}) do
        local t = Toggle(body, scope, function() return s().scopes[scope] == true end, function(v) A.SetScope(scope, v) end)
        t.disabled = function() return not s().web end
        t:SetPoint("TOPLEFT", 22, y); y = y - 28
    end
    page.webHint = label(body, 11, C.mist); page.webHint:SetPoint("TOPLEFT", 0, y - 4); page.webHint:SetWidth(600); y = y - 52

    section("interfaceSection")
    page.langLabel = label(body, 12, C.text); page.langLabel:SetPoint("TOPLEFT", 0, y - 6)
    page.langButtons = {}
    for i, lang in ipairs({"en", "cs"}) do
        local b = Button(body, nil, 48, "ghost", function() A.db.settings.language = lang; applyFonts(); A.RefreshUI() end)
        b:SetPoint("TOPLEFT", 120 + (i - 1) * 54, y); b.text:SetText(lang:upper()); b.lang = lang
        page.langButtons[i] = b
    end
    y = y - 38
    place(Toggle(body, "minimap", function() return not s().hideMinimap end, function(v) s().hideMinimap = not v; if minimapButton then minimapButton:SetShown(v) end end))
    y = y - 10

    section("actionsSection")
    page.actions = {
        Button(body, "send", 150, "primary", function() local ok, err = A.ShareNow(); if not ok then A.Print(err or "sharing_error") end end),
        Button(body, "export", 150, "ghost", showCopy),
        Button(body, "confirm", 190, "ghost", function() A.FinishRun("manual", "last_boss"); A.RefreshUI() end),
    }
    local x = 0
    for _, b in ipairs(page.actions) do b:SetPoint("TOPLEFT", x, y); x = x + b:GetWidth() + 10 end
    y = y - 50

    section("diagnostics")
    page.diag = label(body, 11, C.mist); page.diag:SetPoint("TOPLEFT", 0, y); page.diag:SetWidth(600)
    y = y - 90
    body:SetHeight(-y)

    function page.Refresh()
        for _, t in ipairs(toggles) do t.Update() end
        for _, fs in ipairs(page.sections) do fs:SetText(A.L(fs.localeKey)) end
        for _, b in ipairs(page.actions) do b.text:SetText(A.L(b.localeKey)) end
        page.webHint:SetText(A.L("webHint"))
        page.liveHint:SetText(A.L("liveHint"))
        page.langLabel:SetText(A.L("language"))
        for _, b in ipairs(page.langButtons) do b.text:SetTextColor(unpack(b.lang == s().language and C.lilac or C.mist)) end
        page.diag:SetText(A.Diagnostics())
        scroll.UpdateThumb()
    end
end

-- ---------- frame ----------

function A.Diagnostics()
    local out = {"Interface: " .. plain(A.Game().interface) .. "  ·  build " .. plain(A.Game().build) .. "  ·  Evertally " .. A.version}
    if A.errors then for event, count in pairs(A.errors) do out[#out + 1] = plain(event) .. ": " .. count end end
    local unavailable = {}
    for event, state in pairs(A.capabilities) do if state == "unsupported" then unavailable[#unavailable + 1] = event end end
    table.sort(unavailable)
    out[#out + 1] = A.L("unsupported") .. ": " .. (#unavailable > 0 and table.concat(unavailable, ", ") or "0")
    return table.concat(out, "\n")
end

local function select(view)
    selected = view
    for key, page in pairs(pages) do page:SetShown(key == view) end
    A.RefreshUI()
end

local function NavButton(parent, view, index)
    local b = CreateFrame("Button", nil, parent); b:SetSize(SIDEBAR - 16, 36)
    b:SetPoint("TOPLEFT", 8, -14 - (index - 1) * 40)
    b.bg = fill(b, C.lilac, 0)
    b.bar = b:CreateTexture(nil, "ARTWORK"); b.bar:SetSize(3, 22); b.bar:SetPoint("LEFT"); paint(b.bar, C.lilac)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(20, 20); b.icon:SetPoint("LEFT", 14, 0); setIcon(b.icon, ICON[view])
    b.text = label(b, 13, C.mist); b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
    b.viewKey, b.localeKey = view, view
    b:SetScript("OnEnter", function() if selected ~= view then b.bg:SetAlpha(0.06) end end)
    b:SetScript("OnLeave", function() if selected ~= view then b.bg:SetAlpha(0) end end)
    b:SetScript("OnClick", function() select(view) end)
    return b
end

-- The helpers other addon files (SocialUI.lua) build their windows from.
function A.UIKit()
    return {C = C, ICON = ICON, Button = Button, label = label, fill = fill, outline = outline, ScrollArea = ScrollArea, ListView = ListView, PageHeader = PageHeader,
        SectionTitle = SectionTitle, setIcon = setIcon, classIcon = classIcon, plain = plain, stamp = stamp, itemIcon = itemIcon, WIDTH = WIDTH, SIDEBAR = SIDEBAR, PAD = PAD, ROW = ROW}
end

local function build()
    frame = CreateFrame("Frame", "EvertallyFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT); frame:SetPoint("CENTER"); frame:SetFrameStrata("HIGH")
    frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
    fill(frame, C.canvas, 0.97); outline(frame, {C.lilac[1], C.lilac[2], C.lilac[3], 0.25})

    local bar = CreateFrame("Frame", nil, frame); bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT"); bar:SetHeight(HEADER)
    gradient(fill(bar, C.header), {0.20, 0.15, 0.30}, C.canvas)
    local rule = bar:CreateTexture(nil, "BORDER"); rule:SetHeight(1); rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); paint(rule, C.line)
    bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local logo = bar:CreateTexture(nil, "ARTWORK"); logo:SetSize(30, 30); logo:SetPoint("LEFT", 16, 0); setLogo(logo)
    header.title = label(bar, 18, C.text); header.title:SetPoint("LEFT", logo, "RIGHT", 10, 1); header.title:SetText("Evertally")
    header.version = label(bar, 10, C.faint); header.version:SetPoint("LEFT", header.title, "RIGHT", 8, -1); header.version:SetText("v" .. A.version)
    local close = Button(bar, nil, 30, "ghost", function() frame:Hide() end); close:SetPoint("RIGHT", -14, 0); close.text:SetText("x")
    header.web = Pill(bar); header.web:SetPoint("RIGHT", close, "LEFT", -12, 0)
    header.share = Pill(bar); header.share:SetPoint("RIGHT", header.web, "LEFT", -8, 0)
    header.live = Pill(bar); header.live:SetPoint("RIGHT", header.share, "LEFT", -8, 0)

    local side = CreateFrame("Frame", nil, frame); side:SetPoint("TOPLEFT", 0, -HEADER); side:SetPoint("BOTTOMLEFT"); side:SetWidth(SIDEBAR)
    fill(side, C.side, 0.9)
    local sideRule = side:CreateTexture(nil, "BORDER"); sideRule:SetWidth(1); sideRule:SetPoint("TOPRIGHT"); sideRule:SetPoint("BOTTOMRIGHT"); paint(sideRule, C.line)
    for i, view in ipairs(VIEWS) do navButtons[i] = NavButton(side, view, i) end
    header.hint = label(side, 10, C.faint); header.hint:SetPoint("BOTTOMLEFT", 14, 14); header.hint:SetWidth(SIDEBAR - 28); header.hint:SetText("/etally")

    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", SIDEBAR + PAD, -HEADER - PAD); content:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    for _, view in ipairs(VIEWS) do
        local page = CreateFrame("Frame", nil, content); page:SetAllPoints(content); page:Hide()
        pages[view] = page
    end
    buildOverview(pages.overview)
    buildList(pages.history, "history", historyItems)
    buildProfessions(pages.professions)
    buildPlaces(pages.places)
    buildList(pages.facts, "facts", factItems)
    buildList(pages.rankings, "rankings", function() return rankingItems(), A.L("noData") end)
    buildList(pages.peers, "peers", peerItems)
    buildCommunity(pages.community)
    buildSettings(pages.settings)
    -- the Social page lives in SocialUI.lua; if it cannot be built the rest of the window still works
    if A.BuildSocialPage then
        local ok = pcall(A.BuildSocialPage, pages.social, A.UIKit())
        if not ok then A.errors.social_page = (A.errors.social_page or 0) + 1 end
    end
    if not pages.social.Refresh then PageHeader(pages.social, "social"); pages.social.Refresh = function() end end
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EvertallyFrame" end
    pages[selected]:Show()
end

function A.RefreshUI()
    if not frame or not frame:IsShown() or not A.db then return end
    local s = A.db.settings
    header.web.Set(A.L(s.web and "webOn" or "webOff"), s.web and C.green or C.mist)
    header.share.Set(A.L(s.ingame and "shareOn" or "shareOff"), s.ingame and C.green or C.mist)
    -- sharing a live position must never be invisible
    header.live:SetShown(A.LiveActive and A.LiveActive() or false)
    if header.live:IsShown() then header.live.Set(A.L("livePill"), C.peach) end
    for _, b in ipairs(navButtons) do
        local on = b.viewKey == selected
        b.text:SetText(A.L(b.viewKey)); b.text:SetTextColor(unpack(on and C.text or C.mist))
        b.bg:SetAlpha(on and 0.12 or 0); b.bar:SetShown(on)
    end
    local page = pages[selected]
    page.title:SetText(A.L(page.titleKey)); page.subtitle:SetText(A.L("sub_" .. page.titleKey))
    page.Refresh()
end

function A.OpenUI()
    if not A.db then return end
    if not frame then build() end
    frame:Show(); A.RefreshUI()
end

function A.ToggleUI()
    if frame and frame:IsShown() then frame:Hide() else A.OpenUI() end
end

-- ---------- minimap button ----------

local function placeMinimap()
    local angle = math.rad(A.db.settings.minimapAngle or 210)
    local radius = ((Minimap:GetWidth() or 140) / 2) + 10
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function A.CreateMinimapButton()
    if minimapButton or type(Minimap) ~= "table" or not A.db then return end
    local b = CreateFrame("Button", "EvertallyMinimapButton", Minimap)
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetSize(22, 22); bg:SetPoint("CENTER"); paint(bg, C.canvas)
    local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetSize(20, 20); icon:SetPoint("CENTER"); setLogo(icon)
    local ring = b:CreateTexture(nil, "OVERLAY"); ring:SetSize(53, 53); ring:SetPoint("TOPLEFT"); ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function() A.ToggleUI() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            A.db.settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            placeMinimap()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Evertally")
        GameTooltip:AddLine(A.L("openHint"), 1, 1, 1); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    minimapButton = b
    placeMinimap()
    b:SetShown(not A.db.settings.hideMinimap)
end
A.On("PLAYER_LOGIN", function() A.CreateMinimapButton() end)

-- ---------- slash ----------

-- Never assign the global SlashCmdList itself, not even as `SlashCmdList = SlashCmdList or {}`: a write to a
-- Blizzard global taints it, and every chat command (/invite, /script, macros) then runs tainted and is blocked.
-- Only our own key is added to the table that already exists.
SLASH_EVERTALLY1 = "/evertally"
SLASH_EVERTALLY2 = "/etally"
local function slash(text)
    text = A.Text(text, 100) or ""
    if text == "share" then local ok, err = A.ShareNow(); if not ok then A.Print(err or "sharing_error") end
    elseif text == "finish" then A.FinishRun("manual")
    elseif text == "export" then showCopy()
    elseif text == "diag" then A.Print(A.Diagnostics())
    elseif text == "web on" then A.SetWeb(true)
    elseif text == "web off" then A.SetWeb(false)
    elseif text == "share on" then A.SetIngame(true)
    elseif text == "share off" then A.SetIngame(false)
    elseif text:match("^inspect%s+%S") then
        local name = text:match("^inspect%s+(.+)$")
        local ok, err = A.RequestInspect(name, "ip")
        A.Print(ok and string.format(A.L("socialWaiting"), name) or A.L("socialErr_" .. tostring(err)))
    elseif text == "meet" or text:match("^meet%s") then
        local channel = A.Call(IsInRaid) == true and "RAID" or A.Call(IsInGroup) == true and "PARTY" or A.Call(IsInGuild) == true and "GUILD" or nil
        if not channel then A.Print(A.L("socialMeetErr_no_target"))
        else local ok, err = A.SendMeet(channel, nil, text:match("^meet%s+(.+)$") or "", 0); A.Print(ok and A.L("socialMeetSent") or A.L("socialMeetErr_" .. tostring(err))) end
    elseif text:match("^go%s+%S") then
        local ok, err = A.NavigateByName(text:match("^go%s+(.+)$"))
        A.Print(ok and string.format(A.L("navStarted"), A.Text(text:match("^go%s+(.+)$"), 60)) or A.L("navErr_" .. tostring(err)))
    elseif text == "stop" then A.StopNavigation(); A.Print(A.L("navStopped"))
    elseif text == "ping" or text:match("^ping%s") then
        local ok, err = A.SendPing(text:match("^ping%s+(.+)$") or "")
        A.Print(ok and A.L("pingSent") or A.L("pingErr_" .. tostring(err)))
    elseif text == "navdebug" then
        if A.map and A.map.NavDebug then A.map.NavDebug() else A.Print(A.L("navErr_map_off")) end
    elseif text:match("^waypoint%s+%d+%s+[%d%.]+%s+[%d%.]+") then
        -- /etally waypoint <map id> <x> <y> [name]: a map waypoint, e.g. copied from a meet on the website
        local map, x, y, name = text:match("^waypoint%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)%s*(.*)$")
        map, x, y = A.Number(tonumber(map), 1, 100000), tonumber(x), tonumber(y)
        if x and x > 1 then x = x / 100 end
        if y and y > 1 then y = y / 100 end
        if map and x and y and x <= 1 and y <= 1 and A.SetMeetWaypoint({mapId = math.floor(map), x = x, y = y}) then
            A.Print(string.format(A.L("waypointSet"), A.Text(name, 60) ~= "" and A.Text(name, 60) or "?"))
        else A.Print(A.L("mapUnavailable")) end
    elseif text:match("^allow%s+%x+") then
        local id, kinds = text:match("^allow%s+(%x+)%s*(%a*)")
        local ok, state = A.AnswerRequest(id, kinds ~= "" and kinds or "ip"); A.Print(ok and state or tostring(state))
    elseif text:match("^deny%s+%x+") then
        A.DenyRequest(text:match("^deny%s+(%x+)"), false)
    elseif text == "minimap" then A.db.settings.hideMinimap = not A.db.settings.hideMinimap; if minimapButton then minimapButton:SetShown(not A.db.settings.hideMinimap) end
    else A.ToggleUI() end
end
if type(SlashCmdList) == "table" then SlashCmdList["EVERTALLY"] = slash end
