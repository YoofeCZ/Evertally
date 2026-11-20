local _, A = ...
-- Navy-and-gold window and shared controls; Theme.lua owns every surface colour.

-- The window is resizable: these are its default and smallest size; below COMPACT_BELOW the side menu shrinks to icons.
local DEFAULT_W, DEFAULT_H, MIN_W, MIN_H = 1120, 740, 700, 460
-- The side menu is a narrow column of group glyphs (RAIL) beside the list of pages.
local WIDTH, HEIGHT, HEADER, SIDEBAR, PAD, ROW = DEFAULT_W, DEFAULT_H, 64, 236, 22, 44
local RAIL = 40
local COMPACT_SIDEBAR, COMPACT_BELOW, HEAD_ROW = 56, 860, 30
local LOGO = "Interface\\AddOns\\Evertally\\Media\\Logo"
-- Legacy accent names remain aliases for pages that use the shared kit.
local C = A.Theme.colors
local ART = A.Theme.ART
local ICON = {
    overview = ART .. "house", journal = ART .. "journal", history = ART .. "hourglass",
    facts = ART .. "layers", rankings = ART .. "icon-achieve", peers = ART .. "people", settings = ART .. "gear",
    social = ART .. "people", webfacts = ART .. "plug", community = ART .. "icon-talk",
    professions = ART .. "icon-craft", places = ART .. "icon-explore", world = ART .. "route",
    database = ART .. "database", dungeons = ART .. "icon-dungeon", guides = ART .. "guides",
    recipes = ART .. "recipes", talents = ART .. "star", gear = ART .. "armor", training = ART .. "icon-learn",
    questguide = ART .. "map-fold", leveling = ART .. "icon-level", quest = ART .. "icon-accept",
    questDone = ART .. "icon-turnin", npc = ART .. "person", vendor = ART .. "icon-vendor", item = ART .. "bag",
    profession = ART .. "icon-craft", craft = ART .. "icon-craft", cooldown = ART .. "watch", raid = ART .. "icon-elite",
    run = ART .. "icon-kill", unknown = "Interface\\Icons\\INV_Misc_QuestionMark",
}
-- The side menu: groups with a small heading, in the order the pages are built.
-- (what you did: history; what the game has: the guide; who plays with you: people)
local NAV = {
    {head = "navHistory", glyph = "hourglass", "overview", "journal", "history", "places", "facts", "professions"},
    {head = "navGuide", glyph = "guides", "leveling", "questguide", "gear", "training", "database", "dungeons", "recipes", "talents", "world", "guides"},
    {head = "navPeople", glyph = "icon-talk", "community", "social", "rankings", "webfacts"},
    {glyph = "gear", tip = "settings", "settings"},
}
local VIEWS = {}
for _, group in ipairs(NAV) do for _, view in ipairs(group) do VIEWS[#VIEWS + 1] = view end end
local pageText = {
    en = {pageSearch="Search by name or ID",pageResults="Results",pageProfessionCount="Saved professions",pageRecipeCount="Known recipes",pageCooldownCount="Active cooldowns",pageAreaCount="Visited areas",pageVisitCount="Recorded entries",pageQuestFacts="Quest observations",pageNpcFacts="NPC observations",pageItemFacts="Loot observations",pageAll="All",pageQuests="Quests",pageNpcs="NPCs",pageItems="Loot",pageAllFacts="Retained observations",pageCacheState="Cache",pageCacheFresh="Available offline",pageCacheEmpty="No snapshot",pageCacheExpired="Expired",pageOnlyOwn="Your own retained observations",pageNoMatch="No matching records.",pageActionHint="Sharing and export use only the permissions selected above.",pageLiveWebHint="For your position on the website enable Web export, My character, My route and Position on the website, with the paired Evertally app running. It is not live: sent on a zone change, login, /reload, a “Where are you?” from the website, and otherwise at most every 5 minutes."},
    cs = {pageSearch="Hledat podle názvu nebo ID",pageResults="Výsledky",pageProfessionCount="Uložené profese",pageRecipeCount="Známé recepty",pageCooldownCount="Aktivní cooldowny",pageAreaCount="Navštívené oblasti",pageVisitCount="Zaznamenané vstupy",pageQuestFacts="Pozorování questů",pageNpcFacts="Pozorování NPC",pageItemFacts="Záznamy lootu",pageAll="Vše",pageQuests="Questy",pageNpcs="NPC",pageItems="Loot",pageAllFacts="Uchovaná pozorování",pageCacheState="Mezipaměť",pageCacheFresh="Dostupná i offline",pageCacheEmpty="Bez vzorku",pageCacheExpired="Platnost vypršela",pageOnlyOwn="Vlastní uchovaná pozorování",pageNoMatch="Žádné odpovídající záznamy.",pageActionHint="Sdílení a export používají pouze oprávnění zvolená výše.",pageLiveWebHint="Pro polohu na webu zapni Webový export, Moji postavu, Moji trasu a Polohu na webu a nech běžet spárovanou aplikaci Evertally. Není živá: posílá se při změně lokace, přihlášení, /reload, dotazu „Kde jsi?“ z webu a jinak nejvýš jednou za 5 minut."},
}
for lang,entries in pairs(pageText) do for key,value in pairs(entries) do A.locale[lang][key]=value end end

local frame, content, pages, navButtons, header = nil, nil, {}, {}, {}
local shell, navByView, navHeads = {}, {}, {}
local fontStrings, toggles, copyFrame, minimapButton = {}, {}, nil, nil
local selected = "overview"
local showRun, showEvent, showProfession, showCommunityDetail

-- ---------- helpers ----------

-- Painting goes through the theme, which remembers palette colours so a new colour scheme repaints them in place.
local paint = A.Theme.paint
local function fill(parent, c, alpha, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints(parent)
    if parent.evertallySkin and parent.evertallySkin.shaped then A.Theme.Shape(t, "round") end
    paint(t, c, alpha); return t
end
local function shape(tex, kind) return A.Theme.Shape(tex, kind) end
local function gradient(tex, top, bottom) A.Theme.gradient(tex, top, bottom) end
local glyph = A.Theme.Glyph
local function outline(f, c)
    -- a rounded surface already carries its own outline
    if f.evertallySkin and f.evertallySkin.shaped then
        if c then paint(f.evertallySkin.ring, c, c[4] or 1) end
        return
    end
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
-- Inter (Media/Fonts, OFL) on request: it carries the Czech letters too, so it serves both languages.
local INTER = {heading = "Interface\\AddOns\\Evertally\\Media\\Fonts\\Inter-SemiBold.ttf", body = "Interface\\AddOns\\Evertally\\Media\\Fonts\\Inter-Regular.ttf"}
local function fontPath(role)
    -- The guide's font (its skin's face, Inter by default; it has the Czech letters): the default while the guide's
    -- look is on, or when chosen.
    local font = A.db and A.db.settings.uiFont
    if (font == "guide" or (font == nil and A.Theme.Flat and A.Theme.Flat())) and A.Theme.GuideTheme then
        local th = A.Theme.GuideTheme()
        if th and type(th.FontSpec) == "function" then
            local ok, path = pcall(th.FontSpec, role == "heading" and "title" or "body")
            if ok and type(path) == "string" and path ~= "" then return path end
        end
    end
    if A.db and A.db.settings.uiFont == "inter" then
        local path = INTER[role == "heading" and "heading" or "body"]
        if canUseFont(path) then return path end
    end
    if A.db and A.db.settings.language == "cs" then
        if canUseFont("Interface\\AddOns\\WowfCZ\\Fonts\\FRIZQT__.ttf") then return "Interface\\AddOns\\WowfCZ\\Fonts\\FRIZQT__.ttf" end
        return "Fonts\\ARIALN.TTF"
    end
    return role == "heading" and "Fonts\\FRIZQT__.TTF" or "Fonts\\ARIALN.TTF"
end
function A.FontPath() return fontPath() end
local function label(parent, size, c, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    size=size or 13
    local role=size>=18 and "heading" or "body"
    fs:SetFont(fontPath(role), size, ""); fs:SetTextColor(c[1], c[2], c[3], c[4] or 1); fs:SetJustifyH("LEFT")
    if role=="heading" and fs.SetShadowOffset then fs:SetShadowOffset(1,-1);fs:SetShadowColor(0,0,0,0.7) end
    fontStrings[#fontStrings + 1] = {fs = fs, size = size,role=role}
    return fs
end
local function applyFonts()
    for _, entry in ipairs(fontStrings) do entry.fs:SetFont(fontPath(entry.role), entry.size, "") end
end
A.ApplyFonts = applyFonts
local function plain(v) local text = tostring(A.Plain(v) or A.L("unknown")); return (text:gsub("|", "||")) end
-- string.upper leaves the Czech letters alone, so they are mapped by hand
local UPPER = {["á"] = "Á", ["č"] = "Č", ["ď"] = "Ď", ["é"] = "É", ["ě"] = "Ě", ["í"] = "Í", ["ň"] = "Ň", ["ó"] = "Ó", ["ř"] = "Ř", ["š"] = "Š", ["ť"] = "Ť", ["ú"] = "Ú", ["ů"] = "Ů", ["ý"] = "Ý", ["ž"] = "Ž"}
local function upper(text)
    -- (only a-z through string.upper: with a non-C locale it would also change the bytes inside the Czech letters)
    text = tostring(text or ""):gsub("[a-z]", string.upper)
    for low, high in pairs(UPPER) do text = text:gsub(low, high) end
    return text
end
function A.Upper(text) return upper(text) end
local function clockText(at) at = A.Number(at, 0); return at and (A.Call(date, "%H:%M", at) or "") or "" end
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

local localeButtons = {}
-- A button: gold for the main action, a quiet raised panel with a gold-tinted line for the rest. `icon` (optional)
-- is a line glyph from Media/Polestar drawn before the caption.
-- On a page drawn in the guide's hub (A.InHubPage): the hub's own button (its shape, colours and type), the same
-- calls as here (b.text is its caption, b.localeKey the caption's key).
local function hubButton(parent, key, width, kind, onClick)
    local g = A.HubKit and A.HubKit.Guide and A.HubKit.Guide()
    if not (g and g.Widgets.Button and A.InHubPage and A.InHubPage(parent)) then return nil end
    local b = g.Widgets.Button(parent, key and A.L(key) or "", function(self, ...) if onClick then onClick(self, ...) end end, {width = width, height = 30, primary = kind == "primary", danger = kind == "danger"})
    b:SetWidth(width)
    b.text, b.localeKey, b.hub = b.Label, key, true
    if key then localeButtons[#localeButtons + 1] = b end
    return b
end

local function Button(parent, key, width, kind, onClick, icon)
    local hub = not icon and hubButton(parent, key, width, kind, onClick)
    if hub then return hub end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 32)
    local primary = kind == "primary"
    A.NativeButton(b, C, primary)
    if not primary then outline(b, C.line) end
    local glow = b:CreateTexture(nil, "ARTWORK"); glow:SetPoint("TOPLEFT", 1, -1); glow:SetPoint("BOTTOMRIGHT", -1, 1); shape(glow, "round"); paint(glow, C.gold, 0)
    local shaped = b.evertallySkin and b.evertallySkin.shaped
    -- dark text on the gold (or the guide's accent) of a main button
    local text = label(b, 13, primary and ((shaped or A.Theme.Flat()) and C.canvas or C.bright) or C.text); text:SetPoint("CENTER"); text:SetJustifyH("CENTER")
    if icon then
        b.icon = glyph(b, icon, 14, primary and C.canvas or C.bright)
        b.icon:SetPoint("RIGHT", text, "LEFT", -7, 0)
        text:ClearAllPoints(); text:SetPoint("CENTER", 10, 0)
    end
    b.text, b.localeKey = text, key
    if key then text:SetText(A.L(key)); localeButtons[#localeButtons + 1] = b end
    b:SetScript("OnEnter", function() paint(glow, C.gold, 0.12) end)
    b:SetScript("OnLeave", function() paint(glow, C.gold, 0) end)
    b:SetScript("OnMouseDown", function() paint(glow,C.gold,0.22) end)
    b:SetScript("OnMouseUp", function() paint(glow,C.gold,0.10) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A square button with only a line glyph (close, the menu's group column); the name is its tooltip.
local function IconButton(parent, art, size, onClick, tipKey)
    size = size or 28
    local b = CreateFrame("Button", nil, parent); b:SetSize(size, size)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(b); shape(b.bg, "round"); paint(b.bg, {1, 1, 1}, 0)
    b.icon = glyph(b, art, math.floor(size * 0.55 + 0.5), C.mist); b.icon:SetPoint("CENTER")
    b.tipKey, b.tint = tipKey, C.mist
    b:SetScript("OnEnter", function()
        paint(b.bg, {1, 1, 1}, 0.07); paint(b.icon, C.bright)
        if b.tipKey and GameTooltip then pcall(function() GameTooltip:SetOwner(b, "ANCHOR_RIGHT"); GameTooltip:SetText(A.L(b.tipKey)); GameTooltip:Show() end) end
    end)
    b:SetScript("OnLeave", function() paint(b.bg, {1, 1, 1}, 0); paint(b.icon, b.tint); if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", onClick)
    function b.SetTint(c) b.tint = c; paint(b.icon, c) end
    return b
end

local function Toggle(parent, key, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(560, 36)
    -- A settings row: the label on the left, the switch at the right edge, a 1px line under it.
    -- The switch is a pill: lit gold with the knob on the right when on, an unlit outline with the knob on the left when off.
    local track = b:CreateTexture(nil, "ARTWORK"); track:SetSize(34, 18); track:SetPoint("RIGHT", -4, 0); shape(track, "pill")
    local edge = b:CreateTexture(nil, "ARTWORK", nil, 1); edge:SetAllPoints(track); shape(edge, "ring")
    local shadow = b:CreateTexture(nil, "OVERLAY"); shadow:SetSize(20, 20); A.Theme.Art(shadow, "knob-shadow", {0, 0, 0}, 0.55)
    local knob = b:CreateTexture(nil, "OVERLAY", nil, 1); knob:SetSize(14, 14); shape(knob, "dot"); paint(knob, C.text)
    shadow:SetPoint("CENTER", knob, "CENTER", 0, -1)
    local hover = b:CreateTexture(nil, "HIGHLIGHT"); hover:SetPoint("TOPLEFT", -6, 0); hover:SetPoint("BOTTOMRIGHT", 0, 0); shape(hover, "round"); paint(hover, {1, 1, 1}, 0.035)
    local rule = b:CreateTexture(nil, "BORDER"); rule:SetHeight(1); rule:SetPoint("BOTTOMLEFT", 0, 0); rule:SetPoint("BOTTOMRIGHT", 0, 0); paint(rule, C.rule)
    local text = label(b, 12, parent.parchment and A.UIKit().ParchmentText.ink or C.text); text:SetPoint("LEFT", b, "LEFT", 0, 0);text:SetPoint("RIGHT",track,"LEFT",-16,0);text:SetWordWrap(true)
    b.localeKey, b.get, b.label = key, get, text
    function b.Update()
        local on = get() == true
        paint(track, on and C.gold or C.off, on and 1 or 0.55)
        paint(edge, on and C.bright or C.mist, on and 0 or 0.45)
        knob:ClearAllPoints(); knob:SetPoint("LEFT", track, "LEFT", on and 18 or 2, 0); paint(knob, on and C.canvas or C.mist)
        text:SetText(A.L(key))
        -- a row that matches the settings search is marked in gold
        local c = b.match and C.gold or (parent.parchment and A.UIKit().ParchmentText.ink or C.text)
        text:SetTextColor(c[1], c[2], c[3])
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
    f.bg = fill(f, C.off, 0.5); shape(f.bg, "pill")
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
    local child = CreateFrame("Frame", nil, scroll); child:SetSize(560, 10)
    scroll:SetScrollChild(child)
    local thumb = scroll:CreateTexture(nil, "OVERLAY"); thumb:SetWidth(4); paint(thumb, C.gold, 0.65)
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
    scroll:SetScript("OnSizeChanged", function(self, width)
        width = tonumber(width) or self:GetWidth() or 0
        if width > 40 then child:SetWidth(width) end
        if scroll.onResize then scroll.onResize(child:GetWidth()) end
        update()
    end)
    scroll.child, scroll.UpdateThumb = child, update
    return scroll
end

local function NewRow(parent)
    local r = CreateFrame("Button", nil, parent); r:SetHeight(ROW - 4)
    r.bg = fill(r, C.card, 1)
    r.divider = r:CreateTexture(nil, "BORDER"); r.divider:SetHeight(1); r.divider:SetPoint("BOTTOMLEFT"); r.divider:SetPoint("BOTTOMRIGHT"); paint(r.divider, {0, 0, 0}, 1)
    -- the highlight is a texture of its own: changing the alpha of the card colour would multiply with the alpha it already has
    r.hover = r:CreateTexture(nil, "HIGHLIGHT"); r.hover:SetAllPoints(r); paint(r.hover, {1, 1, 1}, 0.07)
    r:SetScript("OnEnter", function(self)
        if self.heading then return end
        if self.itemId and GameTooltip then pcall(function() GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.itemId); GameTooltip:Show() end) end
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(26, 26); r.icon:SetPoint("LEFT", 8, 0)
    r.raceIcon = r:CreateTexture(nil, "ARTWORK"); r.raceIcon:SetSize(22, 22); r.raceIcon:SetPoint("LEFT", r.icon, "RIGHT", 4, 0); r.raceIcon:Hide()
    r.title = label(r, 13, C.text)
    r.sub = label(r, 11, C.mist)
    r.right = label(r, 13, C.text); r.right:SetPoint("RIGHT", -12, 0); r.right:SetJustifyH("RIGHT")
    r.tag = Pill(r); r.tag:SetPoint("RIGHT", r.right, "LEFT", -10, 0)
    r.chevron = label(r, 12, C.lilac); r.chevron:SetPoint("RIGHT", -7, 0)
    -- the hub look (A.HubLook): the icon on a dark tile, an accent bar at the left edge while pointed at
    r.iconTile = r:CreateTexture(nil, "BORDER"); r.iconTile:SetSize(30, 30); r.iconTile:SetPoint("CENTER", r.icon, "CENTER"); paint(r.iconTile, C.well, 1); r.iconTile:Hide()
    r.hoverBar = r:CreateTexture(nil, "HIGHLIGHT"); r.hoverBar:SetWidth(2); r.hoverBar:SetPoint("TOPLEFT", 0, -3); r.hoverBar:SetPoint("BOTTOMLEFT", 0, 3); paint(r.hoverBar, C.gold, 1)
    r.headTick = r:CreateTexture(nil, "ARTWORK"); r.headTick:SetSize(2, 10); r.headTick:SetPoint("BOTTOMLEFT", 4, 9); paint(r.headTick, C.gold, 1); r.headTick:Hide()
    -- a heading row (a day in the journal): text and a thin rule instead of a card
    r.head = label(r, 11, C.lilac); r.head:SetPoint("BOTTOMLEFT", 4, 7)
    r.headRight = label(r, 10, C.faint); r.headRight:SetPoint("BOTTOMRIGHT", -4, 7); r.headRight:SetJustifyH("RIGHT")
    r.headLine = r:CreateTexture(nil, "BORDER"); r.headLine:SetHeight(1); r.headLine:SetPoint("BOTTOMLEFT", 0, 3); r.headLine:SetPoint("BOTTOMRIGHT", 0, 3); paint(r.headLine, C.line)
    r:SetScript("OnClick", function(self) if type(self.action) == "function" then self.action() end end)
    return r
end

local function ListView(parent, top, striped, wrappedRows)
    local scroll = ScrollArea(parent, top)
    scroll.striped = striped ~= false
    scroll.wrappedRows = wrappedRows == true
    local rows, empty = {}, label(scroll, 12, C.mist)
    empty:SetPoint("TOPLEFT", 14, -40); empty:SetPoint("TOPRIGHT", -14, -40); empty:SetJustifyH("CENTER")
    function scroll.SetItems(items, emptyText)
        scroll.items, scroll.emptyText = items, emptyText
        local compact = (tonumber(scroll.child:GetWidth()) or 640) < 470
        scroll.compact = compact
        scroll.drawWidth = tonumber(scroll.child:GetWidth()) or 640
        local hub = A.HubLook()
        local y, stripe = 0, 0
        for i, item in ipairs(items) do
            local r = rows[i] or NewRow(scroll.child); rows[i] = r
            local heading = item.heading ~= nil
            local rowStep = heading and HEAD_ROW or ROW
            r.heading = heading
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("TOPRIGHT", 0, -y)
            r:SetHeight((heading and HEAD_ROW or ROW) - (scroll.striped and not heading and 0 or 4))
            r.bg:SetShown(not heading); r.hover:SetShown(not heading); r.divider:SetShown(not heading)
            if not heading and scroll.striped then stripe = stripe + 1; paint(r.bg, stripe % 2 == 1 and C.card or C.well, 1)
            elseif not heading then paint(r.bg, C.card, 0.55) end
            r.divider:SetShown(not heading and scroll.striped)
            r.head:SetShown(heading); r.headRight:SetShown(heading); r.headLine:SetShown(heading)
            -- the hub look: no cards, no black rules; a heading is a folder (a tick, small capitals, its count, a hairline)
            if hub then
                r.bg:SetShown(false); r.divider:SetShown(false); r.hover:SetShown(not heading); r.hoverBar:SetShown(not heading)
                r.headTick:SetShown(heading); r.iconTile:SetShown(not heading)
                r.head:ClearAllPoints(); r.head:SetPoint("BOTTOMLEFT", 12, 7)
                r.head:SetTextColor(C.gold[1], C.gold[2], C.gold[3]); paint(r.headLine, C.line, 0.6)
            else
                r.hoverBar:SetShown(false); r.headTick:SetShown(false); r.iconTile:SetShown(false)
                r.head:ClearAllPoints(); r.head:SetPoint("BOTTOMLEFT", 4, 7)
                r.head:SetTextColor(C.lilac[1], C.lilac[2], C.lilac[3]); paint(r.headLine, C.line)
            end
            if heading then
                r.head:SetText(hub and upper(item.heading) or item.heading); r.headRight:SetText(item.right or "")
                for _, widget in ipairs({r.icon, r.raceIcon, r.title, r.sub, r.right, r.tag, r.chevron}) do widget:Hide() end
                r.action, r.itemId = nil, nil
            else
                r.icon:Show(); r.title:Show(); r.sub:Show(); r.right:Show(); r.chevron:Show()
                if item.class then classIcon(r.icon, item.class) else setIcon(r.icon, item.icon) end
                r.raceIcon:SetShown(item.race ~= nil)
                if item.race then raceIcon(r.raceIcon, item.race) end
                local anchor = item.race and r.raceIcon or r.icon
                r.title:SetWordWrap(false); r.sub:SetWordWrap(false)
                r.right:SetWidth(compact and 60 or 100); r.right:ClearAllPoints(); r.right:SetPoint("RIGHT", item.onClick and -26 or -12, 0)
                r.action = item.onClick; r.itemId = item.itemId; r.chevron:SetText((item.onClick and not hub) and ">" or "")
                r.title:SetText(item.title or ""); r.sub:SetText(item.sub or ""); r.right:SetText(item.right or "")
                local tc = item.titleColor or C.text; r.title:SetTextColor(tc[1], tc[2], tc[3])
                r.right:SetTextColor(C.bright[1], C.bright[2], C.bright[3])
                -- the right side keeps room for what is really there: the chevron, the value and the tag (a narrow list shows no tag)
                local reserve = (item.onClick and 26 or 12) + ((item.right and item.right ~= "") and (compact and 66 or 110) or 0)
                if item.tag and not compact then
                    r.tag.Set(item.tag, item.tagColor or C.mist); r.tag:Show()
                    -- without a value the pill sits at the edge, not left of an empty value column
                    r.tag:ClearAllPoints(); r.tag:SetPoint("RIGHT", r, "RIGHT", -((item.onClick and 26 or 12) + ((item.right and item.right ~= "") and 110 or 0)), 0)
                    reserve = reserve + (tonumber(r.tag:GetWidth()) or 80) + 10
                else r.tag:Hide() end
                r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 10, 1); r.title:SetPoint("TOPRIGHT", r, "TOPRIGHT", -reserve, -5)
                r.sub:ClearAllPoints(); r.sub:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 10, 1); r.sub:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -reserve, 5)
                if scroll.wrappedRows then
                    -- Narrow catalogue cards keep their full names, requirements and prices on separate lines.
                    r.chevron:Hide()
                    r.icon:ClearAllPoints(); r.icon:SetPoint("TOPLEFT", 8, -9)
                    local left = item.race and 70 or 44
                    r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", left, -7); r.title:SetPoint("TOPRIGHT", r, "TOPRIGHT", item.onClick and -25 or -10, -7)
                    r.title:SetWordWrap(true)
                    local titleH = math.max(15, tonumber(r.title:GetStringHeight()) or 15); r.title:SetHeight(titleH)
                    r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT", left, -9-titleH); r.sub:SetPoint("TOPRIGHT", r, "TOPRIGHT", -10, -9-titleH); r.sub:SetWordWrap(true)
                    local subH = item.sub and item.sub ~= "" and math.max(12, tonumber(r.sub:GetStringHeight()) or 12) or 0
                    r.sub:SetHeight(math.max(1, subH)); r.sub:SetShown(subH > 0)
                    r.right:ClearAllPoints(); r.right:SetPoint("TOPLEFT", left, -12-titleH-subH); r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -10, -12-titleH-subH); r.right:SetJustifyH("LEFT")
                    local rightH = item.right and item.right ~= "" and 16 or 0; r.right:SetShown(rightH > 0); r.right:SetHeight(math.max(1, rightH))
                    r.tag:Hide(); rowStep = math.max(44, titleH + subH + rightH + 21); r:SetHeight(rowStep - 4)
                end
            end
            r:Show()
            y = y + rowStep
        end
        for i = #items + 1, #rows do rows[i]:Hide() end
        scroll.child:SetHeight(math.max(1, y))
        empty:SetText(#items == 0 and (emptyText or A.L("noData")) or "")
        scroll.UpdateThumb()
    end
    -- the rows are laid out for the width they have: crossing the narrow limit draws them again
    scroll.onResize = function(width)
        if scroll.items and (((tonumber(width) or 640) < 470) ~= scroll.compact or scroll.wrappedRows and math.abs((tonumber(width) or 640) - (scroll.drawWidth or 640)) > 1) then scroll.SetItems(scroll.items, scroll.emptyText) end
    end
    return scroll
end

-- ---------- data → rows ----------

local function eventItem(e, clock)
    local p, kind = e.payload or {}, e.kind
    local item = {title = plain(p.title or p.name or (kind=="zone.visited" and p.mapName) or (p.questId and "Quest #" .. p.questId) or (p.itemId and "Item #" .. p.itemId) or (kind == "character.level" and (A.L("level") .. " " .. tostring(p.level or "?"))) or (kind == "craft.result" and p.recipeId and ("#" .. p.recipeId)) or A.L(kind)),
        sub = A.L(kind) .. "  ·  " .. (clock and clockText(e.observedAt) or stamp(e.observedAt)), tag = upper(A.L(kind)), tagColor = C.mist}
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
        right = run.durationMs and duration(run.durationMs) or "—", tag = upper(tag), tagColor = tc,
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

--- The hub look: Evertally's pages in Evertally Guide's hub (its flat look) take the hub's language (flat rows, folders,
--- a details pane apart, no boxes) with Evertally's own marks (the accent bar and tick, icon tiles). Without the guide
--- Evertally's window keeps its own look.
function A.HubLook() return A.Theme and A.Theme.Flat and A.Theme.Flat() and true or false end

local function PageHeader(page, key)
    -- In the guide's hub: marked, the header drawn as before (GuideShell.lua clips it); a page built from the hub's own
    -- parts (hubColumn) takes the section's whole area and hides it (HubKit.lua)
    if A.HubKit and A.HubKit.Ready(page) then page.hubMode = true end
    local emblem=CreateFrame("Frame",nil,page);emblem:SetSize(38,38);emblem:SetPoint("TOPLEFT",0,0);A.NativePanel(emblem,C)
    emblem.icon=emblem:CreateTexture(nil,"ARTWORK");emblem.icon:SetPoint("TOPLEFT",5,-5);emblem.icon:SetPoint("BOTTOMRIGHT",-5,5);setIcon(emblem.icon,ICON[key] or ICON.overview)
    page.title = label(page, 23, C.bright); page.title:SetPoint("TOPLEFT", 50, 1)
    page.subtitle = label(page, 12, C.mist)
    page.subtitle:SetPoint("TOPLEFT", page, "TOPLEFT", 50, -28); page.subtitle:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -28);page.subtitle:SetHeight(17);page.subtitle:SetWordWrap(false)
    local rule=page:CreateTexture(nil,"BORDER");rule:SetHeight(1);rule:SetPoint("TOPLEFT",0,-47);rule:SetPoint("TOPRIGHT",0,-47);paint(rule,C.line,0.55)
    page.headerParts = {emblem, rule}
    page.titleKey = key
end

-- Shared content chrome for the older pages: the same cards and chips as the dashboard.
-- All columns anchor to the page width; no fixed-width toolbar can escape a narrow window.
-- ---------- the old pages in the hub: the same parts, the hub's look (HubKit.lua) ----------
-- A page drawn in the hub (PageHeader set page.hubMode) gets a column on the left (its search, its figures, its list,
-- top down) and the details pane on the right; its filters are the hub's tabs.
local function hubColumn(page)
    if page.hubLeft then return page.hubLeft end
    -- the whole area, the old header out of sight
    if not page.evertallyBleed then A.HubKit.Bleed(page) end
    for _, part in ipairs({page.title, page.subtitle, unpack(page.headerParts or {})}) do part:Hide() end
    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -A.HubKit.DETAIL_W, 0)
    page.hubLeft, page.hubParts = left, {}
    -- what the old page anchors to its spread (page.book) goes to a frame nobody sees
    page.book = CreateFrame("Frame", nil, page); page.book:Hide()
    return left
end
local function hubLayout(page)
    local left, p = page.hubLeft, page.hubParts
    local W = A.HubKit.Guide().Widgets
    local pad = (W.SHELL and W.SHELL.pad or 32) - 12
    local y = 14
    if p.search then
        p.search:ClearAllPoints(); p.search:SetPoint("TOPLEFT", left, "TOPLEFT", pad, -y); p.search:SetPoint("TOPRIGHT", left, "TOPRIGHT", -pad, -y)
        y = y + 40
    end
    if p.stats then
        p.stats:ClearAllPoints(); p.stats:SetPoint("TOPLEFT", left, "TOPLEFT", pad, -y); p.stats:SetPoint("TOPRIGHT", left, "TOPRIGHT", -pad, -y)
        y = y + 50
    end
    -- the page's own buttons in a row, its line of information under them
    if p.actions then
        local prev
        for _, b in ipairs(p.actions) do
            b:SetParent(left); b:ClearAllPoints()
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("TOPLEFT", left, "TOPLEFT", pad, -y) end
            b:SetHeight(28); prev = b
        end
        y = y + 38
    end
    if p.info then
        p.info:SetParent(left); p.info:ClearAllPoints()
        p.info:SetPoint("TOPLEFT", left, "TOPLEFT", pad, -y); p.info:SetPoint("TOPRIGHT", left, "TOPRIGHT", -pad, -y)
        y = y + 26
    end
    local bottom = 4
    if p.pager then
        local prev, next, counter = p.pager[1], p.pager[2], p.pager[3]
        for _, f in ipairs(p.pager) do f:SetParent(left) end
        counter:ClearAllPoints(); counter:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -pad, 14)
        next:ClearAllPoints(); next:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -pad - 66, 6)
        prev:ClearAllPoints(); prev:SetPoint("RIGHT", next, "LEFT", -6, 0)
        bottom = 44
    end
    if p.list then
        p.list.scroll:ClearAllPoints(); p.list.scroll:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -y); p.list.scroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -4, bottom)
    end
end
--- Puts a page's own parts (actions: buttons, info: a line, pager: {prev, next, counter}) into its hub column.
local function hubPlace(page, parts)
    if not page.hubMode then return end
    hubColumn(page)
    for k, v in pairs(parts) do page.hubParts[k] = v end
    hubLayout(page)
end
local function hubMetrics(page, definitions)
    hubColumn(page)
    local strip = A.HubKit.Stats(page.hubLeft, #definitions)
    page.hubParts.stats = strip
    hubLayout(page)
    page.metrics = {}
    for i = 1, #definitions do page.metrics[i] = {delta = {SetText = function() end}} end
    function page.RefreshMetrics(values)
        local captions = {}
        for i, definition in ipairs(definitions) do captions[i] = A.L(definition.key) end
        strip.Set(values, captions)
    end
    return strip
end
local function hubFilters(page, definitions, onChange)
    page.hubFilter = definitions[1] and definitions[1][1]
    page.hubTabs = function()
        local tabs = {}
        for _, definition in ipairs(definitions) do tabs[#tabs + 1] = {key = definition[1], label = A.L(definition[2])} end
        return tabs
    end
    page.hubTab = function() return page.hubFilter end
    page.OnHubTab = function(value) page.hubFilter = value; onChange(value) end
    return function(selected) page.hubFilter = selected end
end
local function hubSearch(page, onChange)
    hubColumn(page)
    local search = A.HubKit.Search(page.hubLeft, A.L("pageSearch"), onChange)
    -- the old pages set a hint on their box: the hub's placeholder takes it
    search.hint = {SetText = function(_, text)
        local W = A.HubKit.Guide().Widgets
        if W.SetSearchPlaceholder and text then W.SetSearchPlaceholder(search, text) end
    end}
    page.search, page.hubParts.search = search, search
    hubLayout(page)
    return search
end
-- An old list item as a row of the hub list: its name, its icon, its value on the right.
local function hubEntry(source, key)
    local e = {key = key, title = source.title or "", sub = source.right or (source.tag and string.lower(source.tag)) or nil}
    if source.titleColor then e.rgb = source.titleColor end
    if type(source.icon) == "string" and source.icon:find("\\") then e.icon = source.icon
    elseif type(source.icon) == "number" then e.icon = source.icon
    else e.glyph = source.class and "icon-level" or "icon-note" end
    return e
end
local function hubDocument(spec, row)
    local blocks = {}
    for _, entry in ipairs(spec and spec.entries or {}) do
        blocks[#blocks + 1] = {text = entry.text, head = entry.head, onClick = entry.onClick, icon = type(entry.icon) == "string" and entry.icon or nil}
    end
    local icon = row and (type(row.icon) == "string" and row.icon:find("\\") and row.icon or type(row.icon) == "number" and row.icon) or nil
    return {title = spec and spec.title or "", sub = spec and spec.subtitle or nil, icon = icon or nil, glyph = (not icon) and "icon-note" or nil,
        rgb = row and row.titleColor or nil, blocks = blocks}
end
local function hubBookList(page)
    hubColumn(page)
    local HK = A.HubKit
    local list = HK.List(page.hubLeft)
    local details = HK.Details(page)
    page.hubParts.list, page.hubDetails = list, details
    hubLayout(page)
    page.document = {Set = function(spec) details.Set(hubDocument(spec)) end}
    local view = {}
    function page.ReadRecord(row)
        local spec = (row.buildDocument and row.buildDocument()) or row.document or {title = row.title, subtitle = row.sub, entries = {}}
        if not row.document and not row.buildDocument and row.onClick then spec.entries = {{text = A.L("openDatabase"), icon = row.icon, onClick = row.onClick}} end
        details.Set(hubDocument(spec, row))
    end
    function view.SetItems(items, empty)
        local entries, selected = {}, nil
        for _, source in ipairs(items or {}) do
            if source.heading then
                entries[#entries + 1] = {folder = source.heading, count = source.right}
            else
                local key = source.key or source.title
                local e = hubEntry(source, key)
                e.onClick = function() page.recordKey = key; list.Set(list.entries, key); page.ReadRecord(source) end
                entries[#entries + 1] = e
                if key == page.recordKey then selected = source end
                selected = selected or nil
            end
        end
        if not selected then for _, source in ipairs(items or {}) do if not source.heading then selected = source; break end end end
        page.recordKey = selected and (selected.key or selected.title) or nil
        list.Set(entries, page.recordKey)
        if selected then page.ReadRecord(selected) else details.Empty(empty or A.L("noData"), "") end
    end
    view.scroll = list.scroll
    return view
end

local function Metrics(page, definitions)
    if page.hubMode then return hubMetrics(page, definitions) end
    local kit=A.UIKit();local weights={};for i=1,#definitions do weights[i]=1 end
    local row=kit.Columns(page,weights,10)
    row:SetPoint("TOPLEFT",0,-54);row:SetPoint("TOPRIGHT",0,-54);row:SetHeight(42)
    local cards={}
    for i,definition in ipairs(definitions) do
        local card=CreateFrame("Frame",nil,row.cells[i]);A.NativePanel(card,C)
        card.value=label(card,17,definition.color or C.bright);card.value:SetPoint("TOPLEFT",32,-3)
        local icon=card:CreateTexture(nil,"ARTWORK");icon:SetSize(18,18);icon:SetPoint("TOPLEFT",8,-8);setIcon(icon,definition.icon or ICON.facts)
        card.caption=label(card,10,C.mist);card.caption:SetPoint("TOPLEFT",32,-24);card.caption:SetPoint("TOPRIGHT",-6,-24);card.caption:SetWordWrap(false)
        card.delta=label(card,10,C.faint);card.delta:SetPoint("TOPRIGHT",-6,-4)
        card:SetAllPoints(row.cells[i]);cards[i]=card
    end
    page.metrics=cards
    page.metricRow=row
    function page.RefreshMetrics(values)
        for i,definition in ipairs(definitions) do
            cards[i].value:SetText(tostring(values[i] or 0));cards[i].caption:SetText(A.L(definition.key));cards[i].delta:SetText("")
        end
    end
    return row
end

local function documentRows(rows)
    local entries={}
    for _,r in ipairs(rows or {}) do
        entries[#entries+1]={text=tostring(r.title or "")..(r.sub and r.sub~="" and ("\n"..r.sub) or "")..(r.right and ("  "..r.right) or ""),icon=r.icon,onClick=r.onClick}
    end
    return entries
end
-- The old pages are now index-and-reader spreads. Selecting an entry reads it inline; actions remain explicit inside the page.
local function BookList(page,top)
    if page.hubMode then return hubBookList(page) end
    local kit=A.UIKit();local book=kit.Book(page,top);page.book=book
    local list=ListView(book.index,8);list:ClearAllPoints();list:SetPoint("TOPLEFT",6,-6);list:SetPoint("BOTTOMRIGHT",-10,6)
    list.readingIndex=true
    local doc=kit.Document(book.paper);page.document=doc
    local setItems=list.SetItems
    function list.SetItems(items,empty)
        local selected=nil;local decorated={}
        for _,source in ipairs(items) do
            local row={};for key,value in pairs(source) do row[key]=value end
            local recordKey=source.key or source.title
            row.onClick=function() page.recordKey=recordKey;page.ReadRecord(source) end
            row.tag=nil;row.right=nil
            decorated[#decorated+1]=row
            if recordKey==page.recordKey then selected=source end
        end
        setItems(decorated,empty)
        selected=selected or items[1]
        if selected then page.recordKey=selected.key or selected.title;page.ReadRecord(selected)
        else doc.Set({key="empty",title=empty or A.L("noData"),subtitle=A.L(page.titleKey),entries={}}) end
    end
    function page.ReadRecord(row)
        local spec=(row.buildDocument and row.buildDocument()) or row.document or {title=row.title,subtitle=row.sub,entries={}}
        spec.key=row.key or row.title
        if not row.document and not row.buildDocument and row.onClick then spec.entries={{text=A.L("openDatabase"),icon=row.icon,onClick=row.onClick}} end
        doc.Set(spec)
    end
    return list
end
local function Search(page,top,onChange)
    if page.hubMode then return hubSearch(page, onChange) end
    local search=A.UIKit().SearchBox(page,200,onChange)
    search:SetPoint("TOPLEFT",8,-top);search:SetPoint("TOPRIGHT",-8,-top)
    page.search=search
    return search
end
local function Filters(page,definitions,top,onChange)
    if page.hubMode then return hubFilters(page, definitions, onChange) end
    local chips={};local kit=A.UIKit()
    for i,definition in ipairs(definitions) do
        local value,key=definition[1],definition[2]
        local b=kit.Chip(page,function() onChange(value) end)
        if i==1 then b:SetPoint("TOPLEFT",0,-top) else b:SetPoint("LEFT",chips[i-1],"RIGHT",6,0) end
        b.value,b.localeKey=value,key;chips[i]=b
    end
    page.filters=chips
    return function(selected)
        for _,b in ipairs(chips) do b.SetLabel(A.L(b.localeKey));b.SetOn(b.value==selected) end
    end
end

local function overviewFallback(page)
    PageHeader(page, "overview")
    page.list = ListView(page, 52)
    function page.Refresh()
        local items, run = {}, A.ActiveRun()
        if run then items[1] = runItem(run, true) end
        for i = #A.db.events, math.max(1, #A.db.events - 59), -1 do items[#items + 1] = eventItem(A.db.events[i]) end
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
        A.NativeFrame(f, C)
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
            else f.status:SetText(A.L(result or "communityInvalid") .. "  (" .. string.format(A.L("communityChars"), #(edit:GetText() or "")) .. ")") end
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
    PageHeader(page,"webfacts");page.kind,page.query="",""
    Metrics(page,{{key="communityEntities",icon=ICON.facts},{key="count",icon=ICON.quest},{key="pageCacheState",icon=ICON.community}})
    page.import=Button(page,"communityImport",110,"primary",showCommunityImport);page.import:SetPoint("TOPLEFT",0,-104)
    page.clear=Button(page,"communityClear",80,"ghost",function() A.ClearCommunity() end);page.clear:SetPoint("LEFT",page.import,"RIGHT",8,0)
    local refreshFilters=Filters(page,{{"","communityKind_"},{"quest","communityKind_quest"},{"npc","communityKind_npc"},{"item","communityKind_item"}},104,function(kind) page.kind=kind;A.RefreshUI() end)
    if page.filters then page.filters[1]:ClearAllPoints();page.filters[1]:SetPoint("LEFT",page.clear,"RIGHT",12,0) end
    Search(page,142,function(value) page.query=value;A.RefreshUI() end)
    page.info=label(page,10,C.mist);page.info:SetPoint("TOPLEFT",0,-176);page.info:SetPoint("TOPRIGHT",0,-176);page.info:SetHeight(24);page.info:SetWordWrap(true)
    page.list=BookList(page,206)
    hubPlace(page, {actions = {page.import, page.clear}, info = page.info})
    function page.Refresh()
        page.import.text:SetText(A.L("communityImport"));page.clear.text:SetText(A.L("communityClear"));refreshFilters(page.kind)
        page.search.hint:SetText(A.L("pageSearch"))
        local snapshot,stale=A.GetCommunity()
        page.RefreshMetrics({snapshot and #snapshot.entities or 0,snapshot and snapshot.provenance.observationCount or 0,not snapshot and "—" or stale and "!" or "OK"})
        page.metrics[3].delta:SetText(A.L(not snapshot and "pageCacheEmpty" or stale and "pageCacheExpired" or "pageCacheFresh"))
        -- Status has its own full-width line; it cannot collide with the actions or the search field.
        local info=A.L("communityNoData")
        if snapshot then info=A.L("communityGenerated")..": "..stamp(snapshot.generatedAt).."  ·  "..A.L("communityExpires")..": "..stamp(snapshot.expiresAt) end
        page.info:SetText(info)
        local items={}
        for _,e in ipairs(A.CommunityEntries(page.kind,page.query)) do
            local current=e
            items[#items+1]={title=plain(e.name),icon=e.kind=="npc" and ICON.npc or e.kind=="item" and ICON.item or ICON.quest,
                sub=e.kind.." #"..e.id.."  ·  "..stamp(e.lastSeen)..(e.mapId and ("  ·  "..mapName(e.mapId)) or "")..
                    (e.x and e.y and string.format("  %.1f, %.1f",e.x*100,e.y*100) or ""),right=tostring(e.count),tag=A.L("webfacts"),tagColor=stale and C.peach or C.lilac,
                document={title=plain(e.name),subtitle=e.kind.." #"..e.id,entries={
                    {text=A.L("count")..": "..e.count,head=true},
                    {text=A.L("observedAt")..": "..stamp(e.lastSeen)},
                    {text=e.mapId and mapName(e.mapId) or A.L("unknown")},
                    {text=A.L("communityGenerated")..": "..(snapshot and stamp(snapshot.generatedAt) or "—")},
                    {text=A.L("communityExpires")..": "..(snapshot and stamp(snapshot.expiresAt) or "—")},
                    {text=A.L("openDatabase"),icon=ICON.facts,onClick=function() if A.OpenDatabaseEntry then A.OpenDatabaseEntry(current.kind,current.id) end end},
                }},onClick=function() showCommunityDetail(current) end}
        end
        page.list.SetItems(items,A.L("communityNoData"))
    end
end

for lang, entries in pairs({
    en = {histRuns = "Saved runs", histCompleted = "Completed", histBest = "Best time", histBosses = "Bosses killed", histAll = "All", histDone = "Completed", histCut = "Interrupted"},
    cs = {histRuns = "Uložené běhy", histCompleted = "Dokončené", histBest = "Nejlepší čas", histBosses = "Zabité bossy", histAll = "Vše", histDone = "Dokončené", histCut = "Přerušené"},
}) do for key, value in pairs(entries) do A.locale[lang][key] = value end end
local function buildHistory(page)
    PageHeader(page, "history"); page.filter = "all"
    Metrics(page, {{key = "histRuns", icon = ICON.run}, {key = "histCompleted", icon = ICON.questDone, color = C.green}, {key = "histBest", icon = ICON.cooldown, color = C.peach}, {key = "histBosses", icon = ICON.raid, color = C.sky}})
    local paintFilters = Filters(page, {{"all", "histAll"}, {"completed", "histDone"}, {"interrupted", "histCut"}}, 104, function(value) page.filter = value; A.RefreshUI() end)
    page.list = BookList(page, 144)
    function page.Refresh()
        local runs, completed, best, bosses = A.db.runs, 0, nil, 0
        for _, run in ipairs(runs) do
            if run.status == "completed" then
                completed = completed + 1
                local ms = A.Number(run.durationMs, 1)
                if ms and (not best or ms < best) then best = ms end
            end
            bosses = bosses + (A.Number(run.bossCount, 0) or 0)
        end
        page.RefreshMetrics({#runs, completed, best and duration(best) or "—", bosses})
        paintFilters(page.filter)
        local items, run = {}, A.ActiveRun()
        if run and page.filter == "all" then
            local row=runItem(run,true);row.key="active:"..tostring(run.startedAt);row.document={title=row.title,subtitle=A.L("currentRun"),entries=documentRows(A.RunDetailRows(run))};items[1]=row
        end
        local shown = 0
        for i = #runs, 1, -1 do
            local r = runs[i]
            if page.filter == "all" or (page.filter == "completed" and r.status == "completed") or (page.filter == "interrupted" and r.status == "interrupted") then
                local row=runItem(r);row.key=tostring(r.startedAt)..":"..i;row.document={title=row.title,subtitle=A.L(r.status or "unknown"),entries=documentRows(A.RunDetailRows(r))}
                items[#items + 1] = row; shown = shown + 1
                if shown >= 200 then break end
            end
        end
        page.list.SetItems(items, A.L("noRuns"))
    end
end
local function buildFacts(page)
    PageHeader(page,"facts");page.kind,page.query="all",""
    Metrics(page,{{key="pageQuestFacts",icon=ICON.quest},{key="pageNpcFacts",icon=ICON.npc},{key="pageItemFacts",icon=ICON.item}})
    local kit=A.UIKit()
    local refreshFilters=Filters(page,{{"all","pageAll"},{"quests","pageQuests"},{"npcs","pageNpcs"},{"items","pageItems"}},104,function(kind) page.kind=kind;A.RefreshUI() end)
    Search(page,138,function(value) page.query=value;A.RefreshUI() end)
    page.info=label(page,10,C.mist);page.info:SetPoint("TOPLEFT",0,-172);page.info:SetPoint("TOPRIGHT",0,-172)
    page.list=BookList(page,194)
    function page.Refresh()
        local counts={quests=0,npcs=0,items=0};local items={};local query=kit.fold(page.query);local total=0
        for i=#A.db.events,1,-1 do
            local e=A.db.events[i]
            if A.ScopeFor[e.kind]=="world_facts" then
                local category=e.kind:match("^quest%.") and "quests" or (e.kind=="npc.observed" or e.kind=="vendor.snapshot") and "npcs" or e.kind=="loot.received" and "items" or "other"
                if counts[category] then counts[category]=counts[category]+1 end
                total=total+1
                if page.kind=="all" or page.kind==category then
                    local row=eventItem(e)
                    row.key=tostring(e.id or (e.kind..":"..tostring(e.observedAt)..":"..i))
                    local p=e.payload or {};local current=e
                    row.buildDocument=function()
                    local entries={{text=A.L("observedAt")..": "..stamp(e.observedAt)},{text=A.L("observationType")..": "..A.L(e.kind),head=true}}
                    if p.mapId then entries[#entries+1]={text=p.mapName or mapName(p.mapId)} end
                    if p.questId or p.npcId or p.itemId then
                        local kind,id=p.questId and "quest" or p.npcId and "npc" or "item",p.questId or p.npcId or p.itemId
                        for _,detail in ipairs(A.DatabaseRows(kind,id)) do entries[#entries+1]={text=(detail.title or "").."\n"..(detail.sub or "")} end
                        entries[#entries+1]={text=A.L("openDatabase"),icon=row.icon,onClick=function() A.OpenDatabaseEntry(kind,id) end}
                    end
                    entries[#entries+1]={text=A.L("diagnostics"),onClick=function() showEvent(current) end}
                    return {title=row.title,subtitle=row.sub,entries=entries}
                    end
                    if kit.fold((row.title or "").." "..(row.sub or "").." "..tostring((e.payload or {}).questId or (e.payload or {}).npcId or (e.payload or {}).itemId or "")):find(query,1,true) and #items<200 then items[#items+1]=row end
                end
            end
        end
        page.RefreshMetrics({counts.quests,counts.npcs,counts.items});refreshFilters(page.kind);page.search.hint:SetText(A.L("pageSearch"))
        page.info:SetText(A.L("pageOnlyOwn").."  ·  "..A.L("pageResults")..": "..#items.." / "..total)
        page.list.SetItems(items,A.L(total==0 and "noData" or "pageNoMatch"))
    end
end

-- Details read retained own observations; opening a row never records, exports or
-- shares anything. Missing values stay unknown rather than becoming zero.
local detailFrame
local function showDetails(title, subtitle, items, position)
    if not detailFrame then
        local f=CreateFrame("Frame","EvertallyDetailFrame",UIParent);detailFrame=f
        f:SetSize(720,500);f:SetPoint("CENTER");f:SetFrameStrata("DIALOG");f:EnableMouse(true)
        A.NativeFrame(f,C)
        f.title=label(f,18,C.gold);f.title:SetPoint("TOPLEFT",18,-16);f.title:SetWidth(680)
        f.subtitle=label(f,11,C.mist);f.subtitle:SetPoint("TOPLEFT",18,-44);f.subtitle:SetWidth(680)
        f.list=ListView(f,86);f.list:ClearAllPoints();f.list:SetPoint("TOPLEFT",18,-86);f.list:SetPoint("BOTTOMRIGHT",-26,58);f.list.child:SetWidth(676)
        f.close=Button(f,"close",110,"ghost",function() f:Hide() end);f.close:SetPoint("BOTTOMRIGHT",-18,16)
        f.map=Button(f,"openMap",140,"primary",function()
            if not A.OpenRecordedMap(f.position) then A.Print(A.L("mapUnavailable")) end
        end);f.map:SetPoint("BOTTOMLEFT",18,16)
        f.database=Button(f,"openDatabase",200,"ghost",function()
            if f.entryKind and A.OpenDatabaseEntry then f:Hide(); A.OpenDatabaseEntry(f.entryKind,f.entryId) end
        end);f.database:SetPoint("BOTTOMLEFT",168,16)
        if type(UISpecialFrames)=="table" then UISpecialFrames[#UISpecialFrames+1]="EvertallyDetailFrame" end
    end
    local f=detailFrame;f.position=position
    f.title:SetText(title);f.subtitle:SetText(subtitle or "")
    f.close.text:SetText(A.L("close"));f.map.text:SetText(A.L("openMap"));f.map:SetShown(position and A.Number(position.mapId,1,100000)~=nil)
    -- a record of a quest, an NPC or an item can be opened in the database
    f.entryKind,f.entryId=nil,nil
    if type(position)=="table" then
        for _,pair in ipairs({{"quest","questId"},{"npc","npcId"},{"item","itemId"}}) do
            local id=A.Number(position[pair[2]],1,10000000)
            if id then f.entryKind,f.entryId=pair[1],id;break end
        end
    end
    f.database.text:SetText(A.L("openDatabase"));f.database:SetShown(f.entryKind~=nil)
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
    if p.npcId then
        items[#items+1]=detailRow("npcId",p.npcId,ICON.npc)
        for i,row in ipairs(A.DatabaseRows("npc",p.npcId)) do if i<=4 then items[#items+1]={title=plain(row.title),sub=plain(row.sub or ""),icon=ICON.npc} end end
    end
    if p.questId then
        items[#items+1]=detailRow("questId",p.questId,ICON.quest)
        for _,row in ipairs(A.DatabaseRows("quest",p.questId)) do items[#items+1]={title=plain(row.title),sub=plain(row.sub or ""),icon=ICON.quest} end
    end
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
    showDetails(plain(e.name),A.L("webfacts"),items,e)
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
    PageHeader(page,"professions");page.mode,page.query,page.index="professions","",1
    Metrics(page,{{key="pageProfessionCount",icon=ICON.profession},{key="pageRecipeCount",icon=ICON.craft},{key="pageCooldownCount",icon=ICON.cooldown,color=C.peach}})
    local refreshFilters=Filters(page,{{"professions","professionMode_professions"},{"recipes","professionMode_recipes"},{"cooldowns","professionMode_cooldowns"}},104,function(mode) page.mode=mode;page.index=1;A.RefreshUI() end)
    Search(page,138,function(value) page.query=value;page.index=1;A.RefreshUI() end)
    page.info=label(page,10,C.mist);page.info:SetPoint("TOPLEFT",0,-172);page.info:SetPoint("TOPRIGHT",0,-172);page.info:SetHeight(24);page.info:SetWordWrap(true)
    page.list=BookList(page,202);page.book:SetPoint("BOTTOMRIGHT",0,36)
    page.prev=Button(page,nil,32,"ghost",function() page.index=math.max(1,page.index-1);A.RefreshUI() end);page.prev:SetPoint("BOTTOMRIGHT",-108,0);page.prev.text:SetText("<")
    page.next=Button(page,nil,32,"ghost",function() page.index=page.index+1;A.RefreshUI() end);page.next:SetPoint("LEFT",page.prev,"RIGHT",6,0);page.next.text:SetText(">")
    page.counter=label(page,11,C.mist);page.counter:SetPoint("BOTTOMRIGHT",0,8);page.counter:SetWidth(58);page.counter:SetJustifyH("RIGHT")
    hubPlace(page, {info = page.info, pager = {page.prev, page.next, page.counter}})
    function page.Refresh()
        local rows,query={},fold(page.query);local entries=A.ProfessionSummaries();local recipes,cooldowns=0,0
        refreshFilters(page.mode);page.search.hint:SetText(A.L("pageSearch"));page.info:SetText(A.L("professionSnapshot"))
        for _,entry in ipairs(entries) do
            local p,c=entry.payload,entry.character
            recipes=recipes+#entry.recipes
            for _,recipe in ipairs(entry.recipes) do if recipe.cooldown and recipe.cooldown.readyAt>A.Now() then cooldowns=cooldowns+1 end end
            if page.mode=="professions" then
                local matches=fold(p.name):find(query,1,true) or fold(c and c.name):find(query,1,true)
                for _,recipe in ipairs(entry.recipes) do if fold(recipe.name):find(query,1,true) then matches=true;break end end
                local current=entry
                if matches then
                    local entries={{text=A.L("professionSkill")..": "..(p.skill or "?").." / "..(p.maxSkill or "?"),head=true},{text=A.L("observedAt")..": "..stamp(entry.observedAt)}}
                    for _,recipe in ipairs(entry.recipes) do local rr=recipeRow(entry,recipe);entries[#entries+1]={text=rr.title.."\n"..(rr.sub or ""),icon=rr.icon,onClick=rr.onClick} end
                    rows[#rows+1]={key=tostring(c and c.id)..":"..p.professionId,title=plain(p.name or p.professionId),sub=plain(c and c.name),icon=ICON.profession,
                        document={title=plain(p.name or p.professionId),subtitle=plain(c and c.name),entries=entries},onClick=function() showProfession(current) end}
                end
            else
                for _,recipe in ipairs(entry.recipes) do
                    if (page.mode~="cooldowns" or recipe.cooldown) and fold((recipe.name or recipe.recipeId).." "..(p.name or "").." "..(c and c.name or "")):find(query,1,true) then
                        local currentRecipe=recipe;local row=recipeRow(entry,recipe)
                        local facts={{text=A.L("observedAt")..": "..stamp(entry.observedAt)},{text=A.L("professionSkill")..": "..(p.skill or "?").." / "..(p.maxSkill or "?"),head=true}}
                        if recipe.cooldown then facts[#facts+1]={text=A.L("cooldowns")..": "..stamp(recipe.cooldown.readyAt)} end
                        facts[#facts+1]={text=A.L("recipes"),icon=ICON.craft,onClick=function() if A.LoadGuide then A.LoadGuide() end;if A.map and A.map.OpenRecipe then A.map.OpenRecipe(currentRecipe.recipeId) end end}
                        row.key=tostring(c and c.id)..":"..recipe.recipeId;row.document={title=row.title,subtitle=row.sub,entries=facts};rows[#rows+1]=row
                    end
                end
            end
        end
        page.RefreshMetrics({#entries,recipes,cooldowns})
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
local function buildPlaces(page)
    PageHeader(page,"places");page.query=""
    Metrics(page,{{key="pageAreaCount",icon=ICON.places},{key="pageVisitCount",icon=ICON.facts,color=C.green}})
    Search(page,104,function(value) page.query=value;A.RefreshUI() end)
    page.list=BookList(page,144)
    function page.Refresh()
        local items={};local areas=A.PlaceSummaries();local visits=0;local query=fold(page.query)
        for _,area in ipairs(areas) do
            visits=visits+area.count
            if fold((area.mapName or mapName(area.mapId)).." "..area.mapId):find(query,1,true) then
                local current=area
                items[#items+1]={key=tostring(area.mapId),title=plain(area.mapName or mapName(area.mapId)),sub=A.L("lastVisit")..": "..stamp(area.lastSeen),icon=ICON.places,
                    right=tostring(area.count),tag=A.L("recordedVisits"),tagColor=C.lilac,
                    document={title=plain(area.mapName or mapName(area.mapId)),subtitle=A.L("areaOnly"),entries={
                        {text=A.L("recordedVisits")..": "..area.count,head=true},
                        {text=A.L("lastVisit")..": "..stamp(area.lastSeen)},
                        {text=A.L("openMap"),icon=ICON.places,onClick=function() A.OpenRecordedMap(current) end},
                    }},onClick=function()
                        showDetails(plain(current.mapName or mapName(current.mapId)),A.L("areaOnly"),{detailRow("recordedVisits",current.count),detailRow("lastVisit",stamp(current.lastSeen))},current)
                    end}
            end
        end
        page.RefreshMetrics({#areas,visits});page.search.hint:SetText(A.L("pageSearch"));page.list.SetItems(items,A.L(#areas==0 and "noPlaces" or "pageNoMatch"))
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
        A.NativeFrame(copyFrame, C)
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

for lang, entries in pairs({
    en = {uiScheme = "Colour scheme", uiSchemeNight = "Night", uiSchemeDusk = "Dusk", uiSchemeGraphite = "Graphite", uiSchemeGuide = "Evertally Guide skin",
        uiFont = "Font", uiFontGame = "Game font", uiFontInter = "Inter", uiFontGuide = "Evertally Guide font", uiScale = "Window scale",
        settingsSearch = "Search settings", settingsNoMatch = "No setting matches the search.",
        settingsReset = "Reset window", settingsReload = "Reload UI", langEnglish = "English", langCzech = "Čeština"},
    cs = {uiScheme = "Barevné schéma", uiSchemeNight = "Noc", uiSchemeDusk = "Soumrak", uiSchemeGraphite = "Grafit", uiSchemeGuide = "Podle skinu Evertally Guide",
        uiFont = "Písmo", uiFontGame = "Herní písmo", uiFontInter = "Inter", uiFontGuide = "Podle Evertally Guide", uiScale = "Měřítko okna",
        settingsSearch = "Hledat v nastavení", settingsNoMatch = "Hledání neodpovídá žádné nastavení.",
        settingsReset = "Obnovit okno", settingsReload = "Znovu načíst UI", langEnglish = "English", langCzech = "Čeština"},
}) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local function SectionTitle(parent, key, y)
    local fs = label(parent, 16, C.bright); fs:SetPoint("TOPLEFT", 0, y); fs.localeKey = key
    return fs
end

-- The shared live nameplate editor is built in NameplateUI.lua.

local function buildSettings(page)
    A.settingsPage=page
    PageHeader(page,"settings")
    local kit=A.UIKit();local book=kit.Book(page,58);page.book=book
    -- the footer under the spread: reset the window, reload the interface, close
    book:SetPoint("BOTTOMRIGHT",0,44)
    local scroll=ScrollArea(book.paper,12);page.scroll=scroll
    scroll:ClearAllPoints();scroll:SetPoint("TOPLEFT",14,-14);scroll:SetPoint("BOTTOMRIGHT",-20,12)
    -- The index: a search over every setting, then the sections, each with its glyph in a narrow column of its own.
    page.query=""
    page.search=kit.SearchBox(book.index,160,function(value) page.query=value or "";if page.ApplySearch then page.ApplySearch() end end)
    page.search:ClearAllPoints();page.search:SetPoint("TOPLEFT",10,-10);page.search:SetPoint("TOPRIGHT",-10,-10);page.search:SetHeight(26)
    page.search.icon=glyph(page.search,"search",13,C.faint,"OVERLAY");page.search.icon:SetPoint("RIGHT",-9,0)
    page.search:SetTextInsets(10,28,0,0)
    local column=book.index:CreateTexture(nil,"BORDER");column:SetWidth(1);column:SetPoint("TOPLEFT",44,-46);column:SetPoint("BOTTOMLEFT",44,10);paint(column,C.rule)
    local categoryScroll=ScrollArea(book.index,46);page.categoryScroll=categoryScroll
    categoryScroll:SetPoint("BOTTOMRIGHT",-6,6)
    categoryScroll.child:SetHeight(300)
    page.noMatch=label(book.index,11,C.faint);page.noMatch:SetPoint("TOPLEFT",54,-58);page.noMatch:SetPoint("TOPRIGHT",-10,-58);page.noMatch:SetWordWrap(true)
    local body,y,card,cy=scroll.child,0,nil,0
    page.sections={};page.settingCards={};page.categoryButtons={};page.selectedSection=1;page.searchable={}
    local GLYPHS={sharingSection="icon-talk",liveSection="eye",webSection="plug",interfaceSection="window",nameplatesSection="layers",musicSection="speaker",actionsSection="bolt",diagnostics="bug"}
    local function finish()
        if card then card:SetHeight(-cy+12) end
    end
    local function categoryRow(key,index)
        local b=CreateFrame("Button",nil,categoryScroll.child);b:SetHeight(38)
        b.bg=b:CreateTexture(nil,"BACKGROUND");b.bg:SetPoint("TOPLEFT",42,-1);b.bg:SetPoint("BOTTOMRIGHT",0,1);shape(b.bg,"round");paint(b.bg,C.gold,0)
        b.bar=b:CreateTexture(nil,"ARTWORK");b.bar:SetSize(2,20);b.bar:SetPoint("LEFT",38,0);paint(b.bar,C.gold)
        b.icon=glyph(b,GLYPHS[key] or "gear",16,C.faint);b.icon:SetPoint("CENTER",b,"LEFT",22,0)
        b.text=label(b,12,C.mist);b.text:SetPoint("LEFT",52,0);b.text:SetPoint("RIGHT",-6,0);b.text:SetWordWrap(true)
        b.localeKey=key
        b:SetScript("OnEnter",function() if page.selectedSection~=index then paint(b.bg,{1,1,1},0.04) end end)
        b:SetScript("OnLeave",function() if page.selectedSection~=index then paint(b.bg,C.gold,0) end end)
        b:SetScript("OnClick",function() page.SelectSection(index) end)
        return b
    end
    local function section(key)
        finish();card=CreateFrame("Frame",nil,body);card.parchment=true;card:SetPoint("TOPLEFT");card:SetPoint("TOPRIGHT");cy=-50
        page.settingCards[#page.settingCards+1]=card
        -- the section's name as a tab: underlined in gold, over a 1px line across the page
        local fs=SectionTitle(card,key,-12);fs:ClearAllPoints();fs:SetPoint("TOPLEFT",12,-12);fs:SetFont(fontPath("heading"),15,"");fs:SetTextColor(unpack(kit.ParchmentText.heading));page.sections[#page.sections+1]=fs
        local rule=card:CreateTexture(nil,"BORDER");rule:SetHeight(1);rule:SetPoint("TOPLEFT",12,-38);rule:SetPoint("TOPRIGHT",-12,-38);paint(rule,C.line)
        local tab=card:CreateTexture(nil,"ARTWORK");tab:SetHeight(2);tab:SetPoint("BOTTOMLEFT",rule,"BOTTOMLEFT",0,0);tab:SetPoint("RIGHT",fs,"RIGHT",0,0);paint(tab,C.gold)
        local index=#page.settingCards
        page.categoryButtons[index]=categoryRow(key,index)
        page.searchable[index]={{key=key}}
    end
    local function place(control,height,indent)
        control:ClearAllPoints();control:SetPoint("TOPLEFT",12+(indent or 0),cy);control:SetPoint("TOPRIGHT",card,"TOPRIGHT",-12,cy)
        control:SetHeight(height or 36);cy=cy-(height or 36)
        if control.localeKey then local list=page.searchable[#page.settingCards];list[#list+1]={key=control.localeKey,widget=control} end
    end
    -- words of a section that are not a toggle (a label beside chips or a field) are found by the search too
    local function findable(key) local list=page.searchable[#page.settingCards];list[#list+1]={key=key} end
    local function note(height)
        local fs=label(card,11,kit.ParchmentText.mutedInk);fs:SetPoint("TOPLEFT",12,cy-4);fs:SetPoint("TOPRIGHT",card,"TOPRIGHT",-12,cy-4);fs:SetHeight(height);fs:SetWordWrap(true);cy=cy-height-10
        return fs
    end
    local s=function() return A.db.settings end
    section("sharingSection")
    place(Toggle(card,"share",function() return s().ingame end,A.SetIngame))
    local group=Toggle(card,"group",function() return s().group end,function(v) s().group=v end);group.disabled=function() return not s().ingame end;place(group,36,18)
    local guild=Toggle(card,"guild",function() return s().guild end,function(v) s().guild=v end);guild.disabled=function() return not s().ingame end;place(guild,36,18)
    place(Toggle(card,"socialEnabled",function() return s().social~=false end,function(v) s().social=v end))
    place(Toggle(card,"partyAnnounce",function() return s().partyAnnounce~=false end,function(v) if A.Announce then A.Announce.SetEnabled(v) end end),40)
    place(Toggle(card,"bragPrompt",function() return s().bragPrompt~=false end,function(v) if A.Announce then A.Announce.SetBragEnabled(v) end end),40)
    place(Toggle(card,"presence",function() return s().presence==true end,function(v) if A.Presence then A.Presence.SetEnabled(v) end end),40)

    section("liveSection")
    place(Toggle(card,"liveParty",function() return s().liveParty==true end,function(v) A.SetLive("party",v) end))
    place(Toggle(card,"liveGuild",function() return s().liveGuild==true end,function(v) A.SetLive("guild",v) end))
    place(Toggle(card,"liveFriends",function() return s().liveFriends==true end,function(v) A.SetLive("friends",v) end))
    place(Toggle(card,"mapPins",function() return s().mapPins==true end,function(v) A.SetMapPins(v) end))
    page.liveHint=note(48)

    section("webSection")
    place(Toggle(card,"web",function() return s().web end,A.SetWeb))
    -- (2026-11-18: everything is public: what is sent and shown on the website is not chosen here any more)
    local liveWeb=Toggle(card,"liveWeb",function() return s().liveWeb==true end,function(v) s().liveWeb=v==true;if A.OpticalTick then A.OpticalTick() end;if A.MarkWebChanged then A.MarkWebChanged() end end)
    liveWeb.disabled=function() return not s().web end;place(liveWeb,40,18)
    place(Toggle(card,"bridgeAutostart",function() return A.BridgeAutostart and A.BridgeAutostart() end,function(v) if A.SetBridgeAutostart then A.SetBridgeAutostart(v) end end),40)
    page.webLiveHint=note(60);page.webHint=note(60)

    section("interfaceSection")
    -- the language, the colour scheme and the font: rows of tabs, the chosen one underlined in gold
    local function choiceRow(key,values,current,choose)
        local fs=label(card,12,kit.ParchmentText.ink);fs:SetPoint("TOPLEFT",12,cy-6);fs:SetWidth(116);fs:SetWordWrap(false);fs.localeKey=key
        local chips={}
        for i,value in ipairs(values) do
            local chosen=value
            local chip=kit.Chip(card,function() choose(chosen) end)
            if i==1 then chip:SetPoint("TOPLEFT",132,cy-2) else chip:SetPoint("LEFT",chips[i-1],"RIGHT",6,0) end
            chip.value,chip.localeKey=value[2],value[2];chips[i]=chip
            if key=="language" then chip.lang=value[1] end
        end
        findable(key);cy=cy-34
        return {label=fs,chips=chips,current=current,values=values}
    end
    page.langRow=choiceRow("language",{{"en","langEnglish"},{"cs","langCzech"}},
        function() return s().language=="cs" and "cs" or "en" end,function(value) A.SetLanguage(value[1]) end)
    page.schemeRow=choiceRow("uiScheme",{{"night","uiSchemeNight"},{"dusk","uiSchemeDusk"},{"graphite","uiSchemeGraphite"}},
        function() return A.Theme.SchemeKey() end,function(value) A.Theme.SetScheme(value[1]) end)
    page.fontRow=choiceRow("uiFont",{{"game","uiFontGame"},{"inter","uiFontInter"}},
        function() return s().uiFont=="inter" and "inter" or "game" end,function(value) A.SetUIFont(value[1]) end)
    page.scale=kit.Slider(card,{min=60,max=160,step=5,format="%d %%",localeKey="uiScale",
        get=function() return math.floor(A.GetUIScale()*100+0.5) end,set=function(v) A.SetUIScale(v/100) end})
    place(page.scale,48)
    place(Toggle(card,"rankTooltip",function() return s().rankTooltip~=false end,function(v) s().rankTooltip=v==true end))
    place(Toggle(card,"minimap",function() return not s().hideMinimap end,function(v) s().hideMinimap=not v;if minimapButton then minimapButton:SetShown(v) end end))
    place(Toggle(card,"bagHighlight",function() return s().bagHighlight~=false end,function(v) if A.BagHighlight then A.BagHighlight.SetEnabled(v) end end),40)
    place(Toggle(card,"chatEnabled",function() return A.Chat and A.Chat.Settings().enabled~=false end,function(v) if A.Chat then A.Chat.SetEnabled(v) end end),40)
    local chatRedirect=Toggle(card,"chatRedirect",function() return A.Chat and A.Chat.Settings().redirect==true end,function(v) if A.Chat then A.Chat.SetRedirect(v) end end)
    chatRedirect.disabled=function() return not (A.Chat and A.Chat.Settings().enabled~=false) end;place(chatRedirect,40,18)

    section("nameplatesSection")
    page.plates=A.BuildFriendlyPlateControls(book.paper)
    page.plates:SetPoint("TOPLEFT",12,-12);page.plates:SetPoint("BOTTOMRIGHT",-12,12);page.plates:Hide()

    section("musicSection")
    place(Toggle(card,"musicEnabled",function() return A.Music and A.Music.Enabled() end,function(v) if A.Music then A.Music.SetEnabled(v) end end),40)
    local musicDuck=Toggle(card,"musicDuck",function() return A.Music and A.Music.DuckEnabled() end,function(v) if A.Music then A.Music.SetDuck(v) end end)
    musicDuck.disabled=function() return not (A.Music and A.Music.Enabled()) end;place(musicDuck,36,18)
    do
        local k=A.UIKit()
        page.musicSourceLabel=label(card,12,kit.ParchmentText.ink);page.musicSourceLabel:SetPoint("TOPLEFT",12,cy-8)
        page.musicSources={}
        for i,source in ipairs({"spotify","youtube"}) do
            local chip=k.Chip(card,function() if A.Music then A.Music.SetSource(source) end;A.RefreshUI() end)
            chip:SetPoint("TOPLEFT",132+(i-1)*130,cy-4);page.musicSources[source]=chip
        end
        cy=cy-40
        page.musicIdLabel=label(card,12,kit.ParchmentText.ink);page.musicIdLabel:SetPoint("TOPLEFT",12,cy-8)
        page.musicId=k.SearchBox(card,220,nil);page.musicId:SetPoint("TOPLEFT",132,cy-2);page.musicId:SetHeight(26);page.musicId:SetMaxLetters(40)
        page.musicConnect=Button(card,nil,110,"ghost",function()
            if not A.Music then return end
            local ok,why=A.Music.ConnectSpotify(page.musicId:GetText())
            if ok and not A.Music.toldCheck then A.Music.toldCheck=true;why="musicCheckApp" end
            A.Print(A.L(why))
        end)
        page.musicConnect:SetHeight(26);page.musicConnect:SetPoint("LEFT",page.musicId,"RIGHT",8,0)
        cy=cy-38
        page.musicDashboardLabel=label(card,12,kit.ParchmentText.ink);page.musicDashboardLabel:SetPoint("TOPLEFT",12,cy-8)
        page.musicDashboard=k.LinkBox(card);page.musicDashboard:SetPoint("TOPLEFT",132,cy-2);page.musicDashboard:SetWidth(338)
        cy=cy-38
        page.musicRedirectLabel=label(card,12,kit.ParchmentText.ink);page.musicRedirectLabel:SetPoint("TOPLEFT",12,cy-8)
        page.musicRedirect=k.LinkBox(card);page.musicRedirect:SetPoint("TOPLEFT",132,cy-2);page.musicRedirect:SetWidth(338)
        cy=cy-38
        page.musicHelp=note(76)
        page.musicOpen=Button(card,nil,200,"primary",function() if A.Music then A.Music.SetEnabled(true);A.Music.ToggleBrowser() end end)
        page.musicOpen:ClearAllPoints();page.musicOpen:SetPoint("TOPLEFT",12,cy);page.musicOpen:SetHeight(32);cy=cy-44
        function page.MusicRefresh()
            local source=A.db.settings.music and A.db.settings.music.source or "spotify"
            page.musicSourceLabel:SetText(A.L("musicSource"))
            for name,chip in pairs(page.musicSources) do chip.SetLabel(A.L(name=="youtube" and "musicYoutube" or "musicSpotify"));chip.SetOn(name==source) end
            local spotify=source~="youtube"
            page.musicIdLabel:SetText(A.L("musicSpotifyId"));page.musicIdLabel:SetShown(spotify);page.musicId:SetShown(spotify);page.musicConnect:SetShown(spotify)
            page.musicId.hint:SetText("0123456789abcdef…");page.musicConnect.text:SetText(A.L("musicSpotifyConnect"))
            local saved=A.db.settings.music and A.db.settings.music.spotifyId
            if saved and (page.musicId:GetText() or "")=="" and not (page.musicId.HasFocus and page.musicId:HasFocus()) then
                page.musicId:SetText(saved);if page.musicId.SetCursorPosition then page.musicId:SetCursorPosition(0) end
            end
            page.musicDashboardLabel:SetText(A.L("musicDashboardShort"));page.musicDashboardLabel:SetShown(spotify)
            page.musicDashboard.SetUrl(A.Music and A.Music.DASHBOARD or "");page.musicDashboard:SetShown(spotify)
            page.musicRedirectLabel:SetText(A.L("musicRedirectShort"));page.musicRedirectLabel:SetShown(spotify)
            page.musicRedirect.SetUrl(A.Music and A.Music.REDIRECT or "");page.musicRedirect:SetShown(spotify)
            page.musicHelp:SetText(A.L(spotify and "musicSpotifyHelp" or "setupMusicYoutubeHelp"))
            page.musicOpen.text:SetText(A.L("musicOpenWindow"))
        end
    end

    section("actionsSection")
    page.actions={
        Button(card,"installVerify",180,"ghost",function() A.VerifyInstallation();A.ShowRequirements() end),
        Button(card,"send",150,"primary",function() local ok,err=A.ShareNow();if not ok then A.Print(err or "sharing_error") end end),
        Button(card,"export",150,"ghost",showCopy),
        Button(card,"confirm",190,"ghost",function() A.FinishRun("manual","last_boss");A.RefreshUI() end),
        Button(card,"setupRun",150,"ghost",function() if A.OpenOnboarding then A.OpenOnboarding() end end),
    }
    for i,b in ipairs(page.actions) do b:ClearAllPoints();b:SetPoint("TOPLEFT",12,cy);b:SetPoint("TOPRIGHT",card,"TOPRIGHT",-12,cy);b:SetHeight(34);b.text:SetWordWrap(true);cy=cy-42 end
    page.actionHint=note(44)

    section("diagnostics");page.diag=note(100)
    finish()
    -- The footer: put the window back to its size and place, reload the interface, close.
    page.footer={
        Button(page,"settingsReset",150,"ghost",function() A.ResetUISize();A.Print(A.L("windowReset")) end,"reset"),
        Button(page,"settingsReload",150,"ghost",function() if type(ReloadUI)=="function" then ReloadUI() end end,"reload"),
        Button(page,"close",120,"primary",function() A.HideUI() end,"close"),
    }
    page.footer[3]:SetPoint("BOTTOMRIGHT",0,0)
    page.footer[2]:SetPoint("RIGHT",page.footer[3],"LEFT",-8,0)
    page.footer[1]:SetPoint("RIGHT",page.footer[2],"LEFT",-8,0)
    for _,b in ipairs(page.footer) do b:SetHeight(32) end
    -- The rows of the index, laid out again whenever the search hides some of them.
    local function layoutCategories()
        local y=0
        for i,button in ipairs(page.categoryButtons) do
            local shown=not page.hiddenSections or not page.hiddenSections[i]
            button:SetShown(shown)
            if shown then button:ClearAllPoints();button:SetPoint("TOPLEFT",0,-y);button:SetPoint("TOPRIGHT",0,-y);y=y+40 end
        end
        categoryScroll.child:SetHeight(math.max(1,y+8));categoryScroll.UpdateThumb()
        page.noMatch:SetShown(y==0)
    end
    page.LayoutCategories=layoutCategories
    -- The settings search: a section is kept when its name or any of its settings matches; matching rows turn gold.
    function page.ApplySearch()
        local query=fold(page.query or ""):gsub("^%s+",""):gsub("%s+$","")
        page.hiddenSections={}
        local first=nil
        for index,entries in ipairs(page.searchable) do
            local any=query==""
            for _,entry in ipairs(entries) do
                local hit=query~="" and fold(A.L(entry.key)):find(query,1,true)~=nil
                if entry.widget then entry.widget.match=hit end
                any=any or hit
            end
            page.hiddenSections[index]=not any
            if any and not first then first=index end
        end
        layoutCategories()
        if first and page.hiddenSections[page.selectedSection] then page.SelectSection(first) end
        for _,t in ipairs(toggles) do t.Update() end
    end
    layoutCategories()
    function page.SelectSection(index)
        page.selectedSection=index
        for i,panel in ipairs(page.settingCards) do panel:SetShown(i==index) end
        for i,button in ipairs(page.categoryButtons) do
            local on=i==index
            button.text:SetTextColor(unpack(on and C.bright or C.mist))
            paint(button.icon,on and C.gold or C.faint);paint(button.bg,C.gold,on and 0.10 or 0);button.bar:SetShown(on)
        end
        scroll:SetShown(index~=5);page.plates:SetShown(index==5)
        if index==5 then page.plates.Update() end
        body:SetHeight(page.settingCards[index]:GetHeight())
        scroll:SetVerticalScroll(0);scroll.UpdateThumb()
    end
    page.SelectSection(1)
    function page.Refresh()
        for _,t in ipairs(toggles) do t.Update() end
        for _,fs in ipairs(page.sections) do local t=A.L(fs.localeKey);fs:SetText(fs.upper and upper(t) or t) end
        for _,b in ipairs(page.actions) do b.text:SetText(A.L(b.localeKey)) end
        page.plates.Update()
        page.webHint:SetText(A.L("webHint"));page.webLiveHint:SetText(A.L("pageLiveWebHint"));page.liveHint:SetText(A.L("liveHint"));page.actionHint:SetText(A.L("pageActionHint"))
        for _,b in ipairs(page.categoryButtons) do b.text:SetText(A.L(b.localeKey)) end
        for _,row in ipairs({page.langRow,page.schemeRow,page.fontRow}) do
            row.label:SetText(A.L(row.label.localeKey))
            local current=row.current()
            for i,chip in ipairs(row.chips) do chip.SetLabel(A.L(chip.localeKey));chip.SetOn(row.values[i][1]==current) end
        end
        page.scale.Refresh()
        page.search.hint:SetText(A.L("settingsSearch"));page.noMatch:SetText(A.L("settingsNoMatch"))
        if page.MusicRefresh then page.MusicRefresh() end
        page.diag:SetText(A.Diagnostics());scroll.UpdateThumb()
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
    if A.lastUIError then out[#out + 1] = "ui: " .. plain(A.lastUIError) end
    if A.Music and A.Music.lastError then out[#out + 1] = "music: " .. plain(A.Music.lastError) end
    if A.lastOnboardingError then out[#out + 1] = "setup: " .. plain(A.lastOnboardingError) end
    return table.concat(out, "\n")
end

-- The scale of the window: 60 % to 160 %, kept between sessions (the header has - and + and Ctrl + mouse wheel works too).
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 1.6, 0.05
function A.GetUIScale()
    local value = A.db and A.db.settings and tonumber(A.db.settings.uiScale)
    return value and math.max(SCALE_MIN, math.min(SCALE_MAX, value)) or 1
end

-- The size of the window: dragged by the corner, kept between sessions and never bigger than the screen.
local function screenRoom()
    local scale = frame and frame.GetScale and frame:GetScale()
    scale = math.max(SCALE_MIN, tonumber(scale) or A.GetUIScale())
    local parentWidth = type(UIParent) == "table" and UIParent.GetWidth and UIParent:GetWidth()
    local parentHeight = type(UIParent) == "table" and UIParent.GetHeight and UIParent:GetHeight()
    local sw, sh = tonumber(parentWidth) or 1920, tonumber(parentHeight) or 1080
    return math.max(MIN_W, math.floor(sw / scale) - 30), math.max(MIN_H, math.floor(sh / scale) - 30)
end
function A.GetUISize()
    local s = A.db and A.db.settings
    local w = s and tonumber(s.uiWidth) or DEFAULT_W
    local h = s and tonumber(s.uiHeight) or DEFAULT_H
    local maxW, maxH = screenRoom()
    return math.max(MIN_W, math.min(maxW, math.floor(w + 0.5))), math.max(MIN_H, math.min(maxH, math.floor(h + 0.5)))
end
local layoutShell, ensureNavVisible
local function applyLimits()
    if not frame then return end
    local maxW, maxH = screenRoom()
    if frame.SetResizeBounds then pcall(frame.SetResizeBounds, frame, MIN_W, MIN_H, maxW, maxH)
    else
        if frame.SetMinResize then pcall(frame.SetMinResize, frame, MIN_W, MIN_H) end
        if frame.SetMaxResize then pcall(frame.SetMaxResize, frame, maxW, maxH) end
    end
end
function A.SetUISize(width, height)
    if not A.db then return DEFAULT_W, DEFAULT_H end
    local s = A.db.settings
    s.uiWidth, s.uiHeight = tonumber(width) or DEFAULT_W, tonumber(height) or DEFAULT_H
    local w, h = A.GetUISize()
    s.uiWidth, s.uiHeight = w, h
    if frame then frame:SetSize(w, h); applyLimits(); if layoutShell then layoutShell() end end
    return w, h
end
function A.ResetUISize()
    if A.db then A.db.settings.uiWidth, A.db.settings.uiHeight = nil, nil end
    local w, h = A.GetUISize()
    if frame then frame:SetSize(w, h); frame:ClearAllPoints(); frame:SetPoint("CENTER"); applyLimits(); if layoutShell then layoutShell() end end
    return w, h
end
function A.SetUIScale(value)
    if not A.db then return 1 end
    value = math.max(SCALE_MIN, math.min(SCALE_MAX, math.floor((tonumber(value) or 1) / SCALE_STEP + 0.5) * SCALE_STEP))
    A.db.settings.uiScale = value
    if frame then
        frame:SetScale(value)
        -- a bigger scale leaves less room on the screen: keep the window inside it
        local w, h = A.GetUISize(); frame:SetSize(w, h); applyLimits(); if layoutShell then layoutShell() end
    end
    return value
end

local function select(view)
    selected = view
    if A.db then A.db.settings.lastView = view end
    for key, page in pairs(pages) do page:SetShown(key == view) end
    if ensureNavVisible then ensureNavVisible(view) end
    A.RefreshUI()
end

local function navScroll(value)
    local scroll = shell.navScroll
    if not scroll then return end
    value = math.max(0, math.min(tonumber(scroll.maxScroll) or 0, tonumber(value) or 0))
    scroll:SetVerticalScroll(value)
    if shell.navUp then shell.navUp:SetShown(value > 0) end
    if shell.navDown then shell.navDown:SetShown(value < (scroll.maxScroll or 0)) end
end
ensureNavVisible = function(view)
    local scroll, button = shell.navScroll, navByView[view]
    if not scroll or not button or not button.navTop then return end
    local value = tonumber(scroll:GetVerticalScroll()) or 0
    local height = tonumber(scroll:GetHeight()) or 0
    if button.navTop < value then value = button.navTop - 4
    elseif button.navBottom > value + height then value = button.navBottom - height + 4 end
    navScroll(value)
end

local function NavButton(parent, view)
    local b = CreateFrame("Button", nil, parent); b:SetHeight(34)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetPoint("TOPLEFT", 6, -2); b.bg:SetPoint("BOTTOMRIGHT", -6, 2); shape(b.bg, "round"); paint(b.bg, C.lilac, 1); b.bg:SetAlpha(0)   -- the tint is its alpha: it shows when the item is selected or hovered
    b.bar = b:CreateTexture(nil, "ARTWORK"); b.bar:SetSize(3, 18); b.bar:SetPoint("LEFT", 6, 0); shape(b.bar, "pill"); paint(b.bar, C.gold)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(20, 20); b.icon:SetPoint("LEFT", 14, 0); setIcon(b.icon, ICON[view])
    b.text = label(b, 13, C.mist); b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
    b.viewKey, b.localeKey = view, view
    b:SetScript("OnEnter", function()
        if selected ~= view then b.bg:SetAlpha(0.06) end
        -- with only the icons left the name is shown as a tooltip
        if shell.compact and GameTooltip then pcall(function() GameTooltip:SetOwner(b, "ANCHOR_RIGHT"); GameTooltip:SetText(A.L(view)); GameTooltip:Show() end) end
    end)
    b:SetScript("OnLeave", function() if selected ~= view then b.bg:SetAlpha(0) end; if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function() select(view) end)
    return b
end

-- Positions the side menu for the height of the window and for the compact (icons only) form.
local function layoutNav()
    if not frame then return end
    local compact = shell.compact == true
    local height = tonumber(shell.navScroll:GetHeight()) or ((tonumber(frame:GetHeight()) or DEFAULT_H) - HEADER - 40)
    local headH = compact and 14 or 24
    local itemH = 34
    local y = -10
    for g, group in ipairs(NAV) do
        if group.head then
            local entry = navHeads[group.head]
            entry.fs:ClearAllPoints(); entry.fs:SetPoint("TOPLEFT", 18, y - 6); entry.fs:SetShown(not compact)
            entry.rule:ClearAllPoints(); entry.rule:SetPoint("TOPLEFT", 12, y - 7); entry.rule:SetPoint("TOPRIGHT", -12, y - 7); entry.rule:SetShown(compact)
            y = y - headH
        elseif g > 1 then y = y - 8 end
        for _, view in ipairs(group) do
            local b = navByView[view]
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", 8, y); b:SetPoint("TOPRIGHT", -8, y); b:SetHeight(itemH)
            b.icon:ClearAllPoints(); b.icon:SetPoint(compact and "CENTER" or "LEFT", compact and 2 or 14, 0)
            b.text:SetShown(not compact)
            b.navTop, b.navBottom = -y, -y + itemH
            y = y - itemH
        end
    end
    shell.navChild:SetSize(compact and COMPACT_SIDEBAR or (SIDEBAR - RAIL), math.max(height, -y + 10))
    shell.navScroll.maxScroll = math.max(0, -y + 10 - height)
    shell.navScroll.scrollStep = itemH * 3
    navScroll(shell.navScroll:GetVerticalScroll())
    ensureNavVisible(selected)
end

layoutShell = function()
    if not frame or not shell.side then return end
    local width = tonumber(frame:GetWidth()) or DEFAULT_W
    shell.compact = width < COMPACT_BELOW
    shell.side:SetWidth(shell.compact and COMPACT_SIDEBAR or SIDEBAR)
    -- the group column goes when the menu shrinks to icons: the icons are then the whole menu
    shell.rail:SetShown(not shell.compact)
    shell.navScroll:ClearAllPoints()
    shell.navScroll:SetPoint("TOPLEFT", shell.compact and shell.side or shell.rail, shell.compact and "TOPLEFT" or "TOPRIGHT", 0, 0)
    shell.navScroll:SetPoint("BOTTOMRIGHT", shell.side, "BOTTOMRIGHT", 0, 28)
    header.hint:SetShown(not shell.compact)
    if frame.evertallySkin then A.Theme.FitBand(frame.evertallySkin.band, width - 2) end
    layoutNav()
end

-- The helpers other addon files (SocialUI.lua and the page files) build their windows from; Widgets.lua adds to them.
local kitCache
function A.UIKit()
    if kitCache then return kitCache end
    kitCache = {C = C, ICON = ICON, Button = Button, label = label, fill = fill, outline = outline, paint = paint, gradient = gradient, ScrollArea = ScrollArea, ListView = ListView,
        PageHeader = PageHeader, SectionTitle = SectionTitle, setIcon = setIcon, classIcon = classIcon, classColor = classColor, raceIcon = raceIcon, identityText = identityText,
        mapName = mapName, plain = plain, stamp = stamp, duration = duration, itemIcon = itemIcon, fold = fold, eventItem = eventItem, runItem = runItem, fontPath = fontPath,
        trackFont = function(fs, size) fontStrings[#fontStrings + 1] = {fs = fs, size = size} end,
        IconButton = IconButton, Toggle = Toggle, glyph = glyph, Theme = A.Theme,
        WIDTH = WIDTH, SIDEBAR = SIDEBAR, PAD = PAD, ROW = ROW}
    if A.ExtendKit then A.ExtendKit(kitCache) end
    return kitCache
end

-- Builds one page with code from another file; whatever goes wrong there leaves a plain page and a counted error, never a broken window.
local function buildExternal(view, builder, errorKey, fallback)
    local page = pages[view]
    if builder then
        local ok, err = pcall(builder, page, A.UIKit())
        if not ok then A.errors[errorKey] = (A.errors[errorKey] or 0) + 1; A.lastUIError = tostring(err) end
        if ok and page.Refresh then return end
    end
    if fallback then fallback(page) end
    -- (a page built from the hub's own parts has the hub's header: HubKit.Bleed)
    if not page.title and not page.evertallyBleed then PageHeader(page, view) end
    if not page.Refresh then page.Refresh = function() end end
end

-- Draws one page into pages[view] (made by the caller: this window's content, or a section of Evertally Guide's hub).
local function buildPage(view)
    -- what is drawn on a page takes the hub look there (A.InHubPage)
    if pages[view] then pages[view].evertallyPage = view end
    if view == "overview" then buildExternal("overview", A.BuildOverviewPage, "overview_page", overviewFallback)
    elseif view == "journal" then buildExternal("journal", A.BuildJournalPage, "journal_page")
    elseif view == "history" then buildHistory(pages.history)
    elseif view == "professions" then buildProfessions(pages.professions)
    elseif view == "places" then buildPlaces(pages.places)
    elseif view == "facts" then buildFacts(pages.facts)
    elseif view == "rankings" then buildExternal("rankings", A.BuildRankingsPage, "rankings_page", function(page) buildList(page, "rankings", function() return rankingItems(), A.L("noData") end) end)
    -- the Community page is the forum (ForumUI.lua); the old sample of website facts lives on its own page
    elseif view == "community" then buildExternal("community", A.BuildForumPage, "forum_page")
    elseif view == "webfacts" then buildCommunity(pages.webfacts)
    elseif view == "settings" then buildSettings(pages.settings)
    -- the Social page lives in SocialUI.lua, the World page in WorldHost.lua (its code in Evertally_Map, loaded on first use)
    elseif view == "social" then buildExternal("social", A.BuildSocialPage, "social_page")
    elseif view == "world" then buildExternal("world", A.BuildWorldPage, "world_page")
    elseif view == "database" then buildExternal("database", A.BuildDatabasePage, "database_page")
    elseif view == "dungeons" then buildExternal("dungeons", A.BuildDungeonsPage, "dungeons_page")
    elseif view == "recipes" then buildExternal("recipes", A.BuildRecipesPage, "recipes_page")
    elseif view == "talents" then buildExternal("talents", A.BuildTalentsPage, "talents_page")
    elseif view == "guides" then buildExternal("guides", A.BuildGuidesPage, "guides_page")
    elseif view == "gear" then buildExternal("gear", A.BuildGearPage, "gear_page")
    elseif view == "training" then buildExternal("training", A.BuildTrainingPage, "training_page")
    elseif view == "questguide" then buildExternal("questguide", A.BuildQuestGuidePage, "questguide_page")
    elseif view == "leveling" then buildExternal("leveling", A.BuildLevelingPage, "leveling_page") end
end

-- One page's title and contents drawn again; a page that fails is counted, never passed on.
local function refreshPage(view)
    local page = pages[view]
    if not page then return end
    if page.title then page.title:SetText(A.L(page.titleKey)); page.subtitle:SetText(A.L("sub_" .. page.titleKey)) end
    local ok, err = pcall(page.Refresh)
    if not ok then A.errors.ui_refresh = (A.errors.ui_refresh or 0) + 1; A.lastUIError = view .. ": " .. tostring(err) end
end

-- With Evertally Guide loaded the pages live in its hub (GuideShell.lua sets A.guideShell); this window is the way
-- without it. The hub reads the menu and builds pages through these.
A.ShowExportCopy = function() showCopy() end
A.UIShell = {NAV = NAV, ICON = ICON, pages = pages, buildPage = function(view) return buildPage(view) end, refreshPage = refreshPage}

local function build()
    A.Theme.ApplyScheme()
    local width, height = A.GetUISize()
    frame = CreateFrame("Frame", "EvertallyFrame", UIParent)
    frame:SetSize(width, height); frame:SetPoint("CENTER"); frame:SetFrameStrata("HIGH")
    frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
    frame:SetScale(A.GetUIScale())
    if frame.SetResizable then pcall(frame.SetResizable, frame, true) end
    applyLimits()
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) if IsControlKeyDown and IsControlKeyDown() then A.SetUIScale(A.GetUIScale() + delta * 0.1) end end)
    A.NativeFrame(frame, C)

    -- The header: no panel of its own, it is the window's night band with the stars; a 1px line closes it.
    local bar = CreateFrame("Frame", nil, frame); bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1); bar:SetHeight(HEADER)
    local rule = bar:CreateTexture(nil, "BORDER"); rule:SetHeight(1); rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); paint(rule, C.line)
    bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local logo = bar:CreateTexture(nil, "ARTWORK"); logo:SetSize(38, 38); logo:SetPoint("LEFT", 16, 0); setLogo(logo)
    header.title = label(bar, 23, C.bright); header.title:SetPoint("LEFT", logo, "RIGHT", 10, 1); header.title:SetText("Evertally")
    header.version = label(bar, 10, C.faint); header.version:SetPoint("LEFT", header.title, "RIGHT", 8, -1); header.version:SetText("v" .. A.version)
    local zoomOut = Button(bar, nil, 26, "ghost", function() A.SetUIScale(A.GetUIScale() - 0.1) end); zoomOut:SetHeight(26); zoomOut:SetPoint("LEFT", header.version, "RIGHT", 18, 0); zoomOut.text:SetText("-")
    local zoomIn = Button(bar, nil, 26, "ghost", function() A.SetUIScale(A.GetUIScale() + 0.1) end); zoomIn:SetHeight(26); zoomIn:SetPoint("LEFT", zoomOut, "RIGHT", 4, 0); zoomIn.text:SetText("+")
    local close = IconButton(bar, "close", 30, function() frame:Hide() end, "close"); close:SetPoint("RIGHT", -14, 0)
    header.close = close
    header.web = Pill(bar); header.web:SetPoint("RIGHT", close, "LEFT", -12, 0)
    header.share = Pill(bar); header.share:SetPoint("RIGHT", header.web, "LEFT", -8, 0)
    header.live = Pill(bar); header.live:SetPoint("RIGHT", header.share, "LEFT", -8, 0)

    local side = CreateFrame("Frame", nil, frame); side:SetPoint("TOPLEFT", 1, -HEADER - 1); side:SetPoint("BOTTOMLEFT", 1, 1); side:SetWidth(SIDEBAR)
    shell.side = side
    fill(side, C.side, 1)
    local sideRule = side:CreateTexture(nil, "BORDER"); sideRule:SetWidth(1); sideRule:SetPoint("TOPRIGHT"); sideRule:SetPoint("BOTTOMRIGHT"); paint(sideRule, C.line)
    -- The group column: one glyph per group of pages; a click opens the group's first page, the gold one holds the page shown.
    local rail = CreateFrame("Frame", nil, side); rail:SetPoint("TOPLEFT"); rail:SetPoint("BOTTOMLEFT"); rail:SetWidth(RAIL)
    shell.rail, shell.railButtons = rail, {}
    local railShade = rail:CreateTexture(nil, "BACKGROUND", nil, 1); railShade:SetAllPoints(rail); paint(railShade, {0, 0, 0}, 0.22)
    local railRule = rail:CreateTexture(nil, "BORDER"); railRule:SetWidth(1); railRule:SetPoint("TOPRIGHT"); railRule:SetPoint("BOTTOMRIGHT"); paint(railRule, C.rule)
    for i, group in ipairs(NAV) do
        local first = group[1]
        local b = IconButton(rail, group.glyph, 30, function() select(first) end, group.head or group.tip)
        b:SetPoint("TOP", rail, "TOP", 0, -10 - (i - 1) * 38)
        b.mark = b:CreateTexture(nil, "ARTWORK"); b.mark:SetSize(2, 18); b.mark:SetPoint("LEFT", b, "LEFT", -5, 0); paint(b.mark, C.gold)
        b.group = group
        shell.railButtons[i] = b
    end
    local navViewport = CreateFrame("ScrollFrame", "EvertallyNavigationScroll", side)
    navViewport:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0); navViewport:SetPoint("BOTTOMRIGHT", 0, 28)
    navViewport:EnableMouseWheel(true)
    local navChild = CreateFrame("Frame", "EvertallyNavigationContent", navViewport); navChild:SetSize(SIDEBAR, 500)
    navViewport:SetScrollChild(navChild)
    shell.navScroll, shell.navChild = navViewport, navChild
    navViewport:SetScript("OnMouseWheel", function(self, delta)
        if IsControlKeyDown and IsControlKeyDown() then A.SetUIScale(A.GetUIScale() + delta * 0.1)
        else navScroll((tonumber(self:GetVerticalScroll()) or 0) - delta * (self.scrollStep or 72)) end
    end)
    local footerRule = side:CreateTexture(nil, "BORDER"); footerRule:SetHeight(1)
    footerRule:SetPoint("BOTTOMLEFT", navViewport, "BOTTOMLEFT", 8, -1); footerRule:SetPoint("BOTTOMRIGHT", -8, 27); paint(footerRule, C.rule)
    shell.navDown = Button(side, nil, 18, "ghost", function() navScroll((tonumber(navViewport:GetVerticalScroll()) or 0) + (navViewport.scrollStep or 72)) end)
    shell.navDown:SetHeight(18); shell.navDown:SetPoint("BOTTOMRIGHT", -8, 5); shell.navDown.text:SetText("v")
    shell.navUp = Button(side, nil, 18, "ghost", function() navScroll((tonumber(navViewport:GetVerticalScroll()) or 0) - (navViewport.scrollStep or 72)) end)
    shell.navUp:SetHeight(18); shell.navUp:SetPoint("RIGHT", shell.navDown, "LEFT", -2, 0); shell.navUp.text:SetText("^")
    for _, group in ipairs(NAV) do
        if group.head then
            local rule = navChild:CreateTexture(nil, "BORDER"); rule:SetHeight(1); paint(rule, C.line); rule:Hide()
            navHeads[group.head] = {fs = label(navChild, 10, C.faint), rule = rule, head = group.head}
            navHeads[#navHeads + 1] = navHeads[group.head]
        end
        for _, view in ipairs(group) do
            local b = NavButton(navChild, view)
            navButtons[#navButtons + 1] = b; navByView[view] = b
        end
    end
    header.hint = label(side, 10, C.faint); header.hint:SetPoint("BOTTOMLEFT", RAIL + 14, 9); header.hint:SetWidth(SIDEBAR - RAIL - 72); header.hint:SetText("/etally")

    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", side, "TOPRIGHT", PAD, -PAD); content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 6, PAD + 6)
    for _, view in ipairs(VIEWS) do
        local page = CreateFrame("Frame", nil, content); page:SetAllPoints(content); page:Hide()
        pages[view] = page
        buildPage(view)
    end
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EvertallyFrame" end

    -- the corner that resizes the window
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(18, 18); grip:SetPoint("BOTTOMRIGHT", -3, 3); grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 30)
    grip:SetNormalTexture(ART .. "resize")
    grip:SetHighlightTexture(ART .. "resize")
    grip:SetPushedTexture(ART .. "resize")
    grip:SetScript("OnMouseDown", function() if frame.StartSizing then frame:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); A.SetUISize(frame:GetWidth(), frame:GetHeight()) end)
    shell.grip = grip
    frame:SetScript("OnSizeChanged", function() layoutShell() end)

    local saved = A.db.settings.lastView
    if type(saved) == "string" and pages[saved] then selected = saved end
    layoutShell()
    pages[selected]:Show()
end

function A.RefreshUI()
    if A.guideShell then return A.guideShell.Refresh() end
    if not frame or not frame:IsShown() or not A.db then return end
    local s = A.db.settings
    header.web.Set(A.L(s.web and "webOn" or "webOff"), s.web and C.green or C.mist)
    header.share.Set(A.L(s.ingame and "shareOn" or "shareOff"), s.ingame and C.green or C.mist)
    -- sharing a live position must never be invisible
    header.live:SetShown(A.LiveActive and A.LiveActive() or false)
    if header.live:IsShown() then header.live.Set(A.L("livePill"), C.peach) end
    for _, entry in ipairs(navHeads) do entry.fs:SetText(A.L(entry.head)) end
    for _, b in ipairs(localeButtons) do b.text:SetText(A.L(b.localeKey)) end
    for _, b in ipairs(navButtons) do
        local on = b.viewKey == selected
        b.text:SetText(A.L(b.viewKey)); b.text:SetTextColor(unpack(on and C.text or C.mist))
        b.bg:SetAlpha(on and 0.12 or 0); b.bar:SetShown(on)
    end
    for _, b in ipairs(shell.railButtons or {}) do
        local on = false
        for _, view in ipairs(b.group) do if view == selected then on = true end end
        b.SetTint(on and C.gold or C.faint); b.mark:SetShown(on)
    end
    -- a page that fails to draw is counted and reported by /etally diag; it must not take the event that asked for the redraw down with it
    refreshPage(selected)
end

function A.OpenUI()
    if not A.db then return end
    if A.RequirementsGuard and not A.RequirementsGuard() then if frame then frame:Hide() end;return end
    if A.OnboardingClose then A.OnboardingClose() end
    if A.guideShell then return A.guideShell.Open() end
    if not frame then build() end
    frame:Show(); A.RefreshUI()
end
function A.HideUI()
    if A.guideShell then A.guideShell.Hide() end
    if frame then frame:Hide() end
end
A.CloseUI = A.HideUI

--- Opens the window on one of its pages.
function A.ShowView(view)
    if A.guideShell then
        if A.RequirementsGuard and not A.RequirementsGuard() then return end
        if A.OnboardingClose then A.OnboardingClose() end
        return A.guideShell.Open(view)
    end
    A.OpenUI()
    if pages[view] then select(view) end
end

function A.ToggleUI()
    if A.guideShell then
        if A.guideShell.Shown() then A.guideShell.Hide() else A.OpenUI() end
        return
    end
    if frame and frame:IsShown() then frame:Hide() else A.OpenUI() end
end
function A.OverviewShown()
    if A.guideShell then return A.guideShell.Shown("overview") end
    return frame ~= nil and frame:IsShown() and selected == "overview"
end

--- The language of the add-on ("en" or "cs"): kept, the fonts that carry the letters follow it and every page is drawn again.
function A.SetLanguage(language)
    if not A.db or (language ~= "en" and language ~= "cs") then return false end
    local was = A.db.settings.language == "cs" and "cs" or "en"
    A.db.settings.language = language
    applyFonts()
    A.RefreshUI()
    -- The guide reads its texts when its files load (Evertally_Guide_csCZ cannot be unloaded either): a new language
    -- takes the UI reloaded, at once (the user: "při změně jazyka reload hned"). A frame later, so the caller (the
    -- setup's Finish) saves the rest first; the setup opens again after it, in the new language.
    if language ~= was then
        A.reloadPending = true
        local reload = function() A.Call(ReloadUI) end
        if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, reload) else reload() end
    end
    return true
end
--- The font of the window: "game" (the game's own, by language) or "inter" (Media/Fonts). Kept; every text is set again.
function A.SetUIFont(font)
    if not A.db or (font ~= "game" and font ~= "inter" and font ~= "guide") then return false end
    A.db.settings.uiFont = font   -- "game" is kept as such: no choice (nil) means the guide's font while its look is on
    applyFonts()
    A.RefreshUI()
    return true
end
--- Shows or hides the button at the minimap (kept in the settings).
function A.SetMinimapButton(show)
    if not A.db then return end
    A.db.settings.hideMinimap = not show
    if minimapButton then minimapButton:SetShown(show or (A.RequirementsReady and not A.RequirementsReady())) end
end
--- Whether OpenMap is installed (it publishes OpenMapAPI when it loads).
function A.OpenMapInstalled()
    local api = rawget(_G, "OpenMapAPI")
    return type(api) == "table" and type(api.RegisterMenuToggle) == "function"
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
    -- The guide's tooltip when it is there: its font has the Czech letters the game's font lacks on an English client.
    local function guideWidgets() local g = rawget(_G, "EvertallyGuide"); local W = type(g) == "table" and g.Widgets; return type(W) == "table" and W.Tooltip and W or nil end
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetSize(22, 22); bg:SetPoint("CENTER"); paint(bg, C.canvas)
    local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetSize(20, 20); icon:SetPoint("CENTER"); setLogo(icon); b.icon = icon
    local ring = b:CreateTexture(nil, "OVERLAY"); ring:SetSize(53, 53); ring:SetPoint("TOPLEFT"); ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
    -- left: the Evertally menu (EvertallyMenu.lua); right: hide Evertally (the guide's hiding and this window) or show it
    b:SetScript("OnClick", function(self, which)
        if GameTooltip then GameTooltip:Hide() end
        local W = guideWidgets(); if W and W.HideTooltip then pcall(W.HideTooltip, self) end
        -- before the requirements are met any click leads to the installation check (A.OpenUI's guard)
        if A.RequirementsReady and not A.RequirementsReady() then return A.ToggleUI() end
        if which == "RightButton" then
            if A.ToggleEvertallyHidden then A.ToggleEvertallyHidden() else A.ToggleUI() end
        elseif A.ShowEvertallyMenu then A.ShowEvertallyMenu(self)
        else A.ToggleUI() end
    end)
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
        local hidden = A.EvertallyHidden and A.EvertallyHidden()
        local lines = {}
        for _, key in ipairs({"minimapLeft", hidden and "minimapRightShow" or "minimapRight", "minimapDrag"}) do lines[#lines + 1] = A.L(key) end
        local W = guideWidgets()
        if W and pcall(W.Tooltip, self, "ANCHOR_LEFT", "Evertally", lines) then return end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Evertally")
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 1, 1, 1) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        local W = guideWidgets()
        if W and W.HideTooltip then pcall(W.HideTooltip, self) end
        if GameTooltip then GameTooltip:Hide() end
    end)
    minimapButton = b
    placeMinimap()
    if A.PaintMinimapHidden then A.PaintMinimapHidden() end
    b:SetShown(not A.db.settings.hideMinimap or (A.RequirementsReady and not A.RequirementsReady()))
end
A.On("PLAYER_LOGIN", function() A.CreateMinimapButton() end)
--- While Evertally is hidden the button stays as the way back, its logo greyed and dimmed.
function A.PaintMinimapHidden()
    if not (minimapButton and minimapButton.icon) then return end
    local hidden = A.EvertallyHidden and A.EvertallyHidden() or false
    if minimapButton.icon.SetDesaturated then minimapButton.icon:SetDesaturated(hidden) end
    minimapButton.icon:SetAlpha(hidden and 0.45 or 1)
end

-- ---------- slash ----------

-- Never assign the global SlashCmdList itself, not even as `SlashCmdList = SlashCmdList or {}`: a write to a
-- Blizzard global taints it, and every chat command (/invite, /script, macros) then runs tainted and is blocked.
-- Only our own key is added to the table that already exists.
SLASH_EVERTALLY1 = "/evertally"
SLASH_EVERTALLY2 = "/etally"
local function slash(text)
    text = A.Text(text, 100) or ""
    if text=="install" then A.ShowRequirements();return end
    if text~="diag" and text~="web off" and text~="share off" and text~="stop" and text~="reset" and A.RequirementsGuard and not A.RequirementsGuard() then return end
    if text == "share" then local ok, err = A.ShareNow(); if not ok then A.Print(err or "sharing_error") end
    elseif text == "finish" then A.FinishRun("manual")
    elseif text == "export" then showCopy()
    elseif text == "diag" then A.Print(A.Diagnostics())
    elseif text == "reset" then A.ResetUISize(); A.Print(A.L("windowReset"))
    elseif text == "setup" then
        if A.OpenOnboarding then A.OpenOnboarding() end
    -- (in the guide's hub its own gear advice and its guides stand for Evertally's Gear and Quest guide pages)
    elseif text == "gear" then if not (A.guideShell and A.RunGuide and A.RunGuide("gear")) then A.ShowView("gear") end
    elseif text == "music" then if A.Music then A.Music.SetEnabled(not A.Music.Enabled()) end
    elseif text == "bags" then if A.BagHighlight then A.BagHighlight.Diagnose() end
    elseif text == "drawer" or text == "drawers" or text == "suplik" or text == "šuplík" then if A.Drawers then A.Drawers.Toggle() end
    elseif text == "bag" or text == "batoh" then if A.ToggleBagWindow then A.ToggleBagWindow() end
    elseif text == "meter" or text == "dmg" then if A.Meter then A.Meter.Toggle() end
    elseif text == "threat" or text == "agro" or text == "aggro" then if A.ThreatMeter then A.ThreatMeter.Toggle() end
    elseif text == "train" or text == "training" then A.ShowView("training")
    elseif text == "guide" or text == "questguide" then if not (A.guideShell and A.RunGuide and A.RunGuide("guides")) then A.ShowView("questguide") end
    elseif text == "map" then
        -- the map: OpenMap's (Evertally's layers are drawn on it)
        if type(ToggleWorldMap) == "function" then pcall(ToggleWorldMap) end
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
    elseif text == "arrow" then
        if not A.ToggleArrow() and not (A.map and A.map.SetArrowShown) then A.Print(A.L("terrainMapOff")) end
    elseif text == "terrain" then
        if not A.map or not A.map.NavigateTerrain then A.Print(A.L("terrainMapOff"))
        else
            local ok, reason = A.map.NavigateTerrain()
            A.Print(A.L(ok and "terrainStarted" or ("terrainErr_" .. tostring(reason))))
        end
    elseif text == "mark" or text:match("^mark%s") then A.MarkCommand(text)
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
        local ok, state = A.AnswerRequest(id, kinds ~= "" and kinds or "istp"); A.Print(ok and state or tostring(state))
    elseif text:match("^always%s+%x+") then
        -- /etally always <id> [kinds]: like allow, and remembered for this player (never covers gold) until /etally revoke
        local id, kinds = text:match("^always%s+(%x+)%s*(%a*)")
        local ok, state = A.AnswerRequest(id, kinds ~= "" and kinds or "istp", true); A.Print(ok and state or tostring(state))
    elseif text:match("^deny%s+%x+") then
        A.DenyRequest(text:match("^deny%s+(%x+)"), false)
    elseif text:match("^revoke%s+%S") then
        local name = text:match("^revoke%s+(%S+)")
        local ok, err = A.RevokeAccess(name); A.Print(ok and string.format(A.L("socialRevokedChat"), name) or tostring(err))
    elseif text:match("^look%s+%S") then
        -- /etally look <name> [kinds]: ask a player to show gear, stats, talents and professions (i s t p, g for gold, w for your website)
        local name, kinds = text:match("^look%s+(%S+)%s*(%a*)")
        local ok, err = A.RequestInspect(name, kinds ~= "" and kinds or nil); A.Print(ok and string.format(A.L("socialWaiting"), name) or A.L("socialErr_" .. tostring(err)))
    elseif text == "forum" then A.ShowView("community")
    elseif text == "minimap" then A.db.settings.hideMinimap = not A.db.settings.hideMinimap; if minimapButton then minimapButton:SetShown(not A.db.settings.hideMinimap) end
    else A.ToggleUI() end
end
if type(SlashCmdList) == "table" then SlashCmdList["EVERTALLY"] = slash end
