local _, A = ...
-- Shared native stone and bronze surfaces. Some clients put backdrop methods in a mixin rather than on every Frame.
local function backdrop(frame, spec, color, border)
    if type(frame.SetBackdrop) ~= "function" and type(BackdropTemplateMixin) == "table" and type(Mixin) == "function" then
        pcall(Mixin, frame, BackdropTemplateMixin)
    end
    if type(frame.SetBackdrop) ~= "function" or not pcall(frame.SetBackdrop, frame, spec) then return false end
    if type(frame.SetBackdropColor) == "function" then frame:SetBackdropColor(unpack(color)) end
    if type(frame.SetBackdropBorderColor) == "function" then frame:SetBackdropBorderColor(unpack(border)) end
    return true
end
local function surfaceFallback(frame, color, edge)
    local function texture()
        local t = frame:CreateTexture(nil, "BACKGROUND")
        if t.SetColorTexture then t:SetColorTexture(unpack(color))
        else t:SetTexture("Interface\\Buttons\\WHITE8X8"); t:SetVertexColor(unpack(color)) end
        return t
    end
    local bg = texture(); bg:SetAllPoints(frame)
    for _, pair in ipairs({{"TOPLEFT", "TOPRIGHT"}, {"BOTTOMLEFT", "BOTTOMRIGHT"}, {"TOPLEFT", "BOTTOMLEFT"}, {"TOPRIGHT", "BOTTOMRIGHT"}}) do
        local t = texture()
        if t.SetColorTexture then t:SetColorTexture(unpack(edge)) else t:SetVertexColor(unpack(edge)) end
        t:SetPoint(pair[1]); t:SetPoint(pair[2])
        if pair[1]:find("TOP") and pair[2]:find("BOTTOM") then t:SetWidth(1) else t:SetHeight(1) end
    end
end

--- Window and dialog skin; no external addon or artwork is required.
function A.NativeFrame(frame, C)
    local ok = backdrop(frame, {
        bgFile = "Interface\\FrameGeneral\\UI-Background-Rock", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 64, edgeSize = 24, insets = {left = 6, right = 6, top = 6, bottom = 6}},
        {0.22, 0.19, 0.15, 0.99}, {1, 0.90, 0.69, 1})
    if not ok then surfaceFallback(frame, {C.canvas[1], C.canvas[2], C.canvas[3], 0.99}, C.line) end
    return ok
end

--- Recessed stone card with a restrained bronze edge. Used by every page's shared Card helper.
function A.NativePanel(frame, C)
    local ok = backdrop(frame, {
        bgFile = "Interface\\FrameGeneral\\UI-Background-Rock", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 64, edgeSize = 8, insets = {left = 3, right = 3, top = 3, bottom = 3}},
        {0.30, 0.25, 0.18, 0.98}, {0.70, 0.52, 0.27, 0.85})
    if not ok then surfaceFallback(frame, {C.card[1], C.card[2], C.card[3], 0.98}, C.line) end
    return ok
end

local PARCHMENT = {ink = {0.20, 0.12, 0.055}, mutedInk = {0.36, 0.26, 0.14}, heading = {0.42, 0.23, 0.055}}
-- Opaque paper across the whole reader. QuestBG contains transparent padding in this client and cannot be the backing surface.
function A.NativeParchment(frame, C)
    frame.parchment = true
    local ok = backdrop(frame, {
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12, insets = {left = 5, right = 5, top = 5, bottom = 5}},
        {0.73, 0.63, 0.43, 1}, {0.42, 0.29, 0.13, 1})
    if not ok then surfaceFallback(frame, {0.73, 0.63, 0.43, 1}, {0.42, 0.29, 0.13, 1}) end
    if not frame.paperBase then frame.paperBase=frame:CreateTexture(nil,"BACKGROUND") end
    frame.paperBase:ClearAllPoints();frame.paperBase:SetPoint("TOPLEFT",4,-4);frame.paperBase:SetPoint("BOTTOMRIGHT",-4,4)
    if frame.paperBase.SetColorTexture then frame.paperBase:SetColorTexture(0.73,0.63,0.43,1)
    else frame.paperBase:SetTexture("Interface\\Buttons\\WHITE8X8");frame.paperBase:SetVertexColor(0.73,0.63,0.43,1) end
    return PARCHMENT
end

--- Built-in button artwork: red for the principal action, bronze for secondary controls and filters.
function A.NativeButton(button, C, primary)
    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetPoint("TOPLEFT", 1, -1); texture:SetPoint("BOTTOMRIGHT", -1, 1)
    local path = primary and "Interface\\Buttons\\UI-Panel-Button-Up" or "Interface\\DialogFrame\\UI-DialogBox-Background"
    if texture:SetTexture(path) == false then
        if texture.SetColorTexture then texture:SetColorTexture(unpack(primary and C.violet or C.card)) end
    elseif primary then texture:SetTexCoord(0, 0.625, 0, 0.6875)
    else texture:SetVertexColor(0.72, 0.56, 0.33, 1) end
    button.nativeSurface = texture
    return texture
end

-- Building blocks for the redesigned window: cards, filter chips, progress bars, a stacked bar chart and a few helpers the pages share.
-- They are added to the kit that UI.lua hands out (A.UIKit), so every page builds from the same pieces and looks the same.
local text = {
    en = {navHistory = "MY HISTORY", navGuide = "GUIDE", navPeople = "COMMUNITY", windowReset = "Window size and position reset.",
        setupRun = "Run the setup again", mapNeedsOpenMap = "Evertally's map features are built on OpenMap (free, on CurseForge), which is not installed. Install and enable it, then /reload."},
    cs = {navHistory = "MOJE HISTORIE", navGuide = "PRŮVODCE", navPeople = "KOMUNITA", windowReset = "Velikost a poloha okna jsou obnovené.",
        setupRun = "Spustit nastavení znovu", mapNeedsOpenMap = "Funkce mapy Evertally jsou postavené na OpenMap (zdarma, na CurseForge), která není nainstalovaná. Nainstaluj a zapni ji a pak /reload."},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

-- The kinds of events that tell the story of a character (the journal and the dashboard show these); the rest is raw material for the Atlas.
local CATEGORY = {
    ["quest.accepted"] = "quests", ["quest.turned_in"] = "quests", ["quest.abandoned"] = "quests",
    ["loot.received"] = "loot", ["craft.result"] = "loot", ["zone.visited"] = "places", ["character.level"] = "level",
    ["instance.entered"] = "runs", ["run.finished"] = "runs", ["run.interrupted"] = "runs", ["raid.encounter_finished"] = "runs",
}
function A.JournalCategory(kind) return CATEGORY[kind] end

--- Money as the game writes it: gold, silver and copper in their colours.
function A.FormatMoney(copper)
    copper = math.floor(A.Number(copper, 0) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    return string.format("|cffffd700%d|rg |cffc7c7cf%d|rs |cffeda55f%d|rc", g, s, c)
end

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

-- A round axis maximum for a bar chart: 1..4 exactly, then 5, 10, 20, 40, 50, 100 and so on.
local function niceMax(value)
    if value <= 4 then return math.max(1, math.ceil(value)) end
    local magnitude = 10 ^ math.floor(math.log10(value))
    for _, step in ipairs({1, 2, 4, 5, 10}) do if step * magnitude >= value then return step * magnitude end end
    return 10 * magnitude
end
A.NiceMax = niceMax

-- A texture that fades between two colours with their own alpha (the plain gradient helper only knows opaque colours).
-- orientation "VERTICAL": the first colour is at the bottom; "HORIZONTAL": the first colour is on the left.
local function alphaGradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    if tex.SetColorTexture then tex:SetColorTexture(1, 1, 1, 1) else tex:SetTexture("Interface\Buttons\WHITE8X8") end
    if type(CreateColor) == "function" and tex.SetGradient and pcall(tex.SetGradient, tex, orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2)) then return true end
    if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2) then return true end
    return false
end
A.AlphaGradient = alphaGradient

function A.ExtendKit(kit)
    local C, fill, outline, label, paint = kit.C, kit.fill, kit.outline, kit.label, kit.paint
    kit.alphaGradient = alphaGradient
    kit.ParchmentText = PARCHMENT

    -- A book spread: a narrow index on the left and a readable page on the right.
    function kit.Book(parent, top)
        local book = CreateFrame("Frame", nil, parent)
        book:SetPoint("TOPLEFT", 0, -(top or 58)); book:SetPoint("BOTTOMRIGHT")
        book.index = CreateFrame("Frame", nil, book); A.NativePanel(book.index, C)
        book.index:SetPoint("TOPLEFT"); book.index:SetPoint("BOTTOMLEFT")
        book.paper = CreateFrame("Frame", nil, book); A.NativeParchment(book.paper, C)
        book.paper:SetPoint("TOPLEFT", book.index, "TOPRIGHT", 12, 0); book.paper:SetPoint("BOTTOMRIGHT")
        local function layout()
            local width = tonumber(book:GetWidth()) or 640
            book.index:SetWidth(math.max(156, math.min(245, width * 0.32)))
            if book.onLayout then book.onLayout() end
        end
        book:SetScript("OnSizeChanged", layout); book.Layout = layout; layout()
        return book
    end

    -- Structured, scrollable prose and clickable records on paper. Repaints preserve reading position.
    function kit.Document(parent)
        local document = {pool = {}, key = nil}
        local scroll = kit.ScrollArea(parent, 0)
        scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT", 16, -14); scroll:SetPoint("BOTTOMRIGHT", -22, 12)
        document.scroll = scroll
        function document.Set(spec)
            spec = spec or {}; document.spec = spec
            local oldOffset = scroll:GetVerticalScroll() or 0
            local changed = document.key ~= spec.key; document.key = spec.key
            local width = math.max(120, tonumber(scroll.child:GetWidth()) or 300)
            local entries = {{text = spec.title or A.L("noData"), size = 19, color = PARCHMENT.heading}}
            if spec.subtitle and spec.subtitle~="" then entries[#entries+1]={text=spec.subtitle,size=11,color=PARCHMENT.mutedInk} end
            for _, entry in ipairs(spec.entries or {}) do entries[#entries + 1] = entry end
            local y = 0
            for i, entry in ipairs(entries) do
                local row = document.pool[i]
                if not row then
                    row = CreateFrame("Button", nil, scroll.child)
                    row.text = label(row, 12, PARCHMENT.ink); row.text:SetJustifyH("LEFT"); row.text:SetJustifyV("TOP"); row.text:SetWordWrap(true)
                    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(28, 28); row.icon:SetPoint("TOPLEFT", 0, -2)
                    row.rule = row:CreateTexture(nil, "BORDER"); row.rule:SetHeight(1); row.rule:SetPoint("BOTTOMLEFT"); row.rule:SetPoint("BOTTOMRIGHT"); paint(row.rule, PARCHMENT.heading, 0.20)
                    row:SetScript("OnClick", function(self) if self.action then self.action() end end)
                    document.pool[i] = row
                end
                row:Show(); row.action = entry.onClick
                row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y); row:SetWidth(width)
                local inset=entry.classId and entry.raceId and 64 or (entry.icon or entry.classId) and 36 or 0
                row.text:ClearAllPoints(); row.text:SetPoint("TOPLEFT", inset, 0); row.text:SetWidth(width - inset)
                row.text:SetFont(kit.fontPath(), entry.size or 12, "")
                local tint = entry.color or (entry.head and PARCHMENT.heading) or PARCHMENT.ink
                row.text:SetTextColor(tint[1], tint[2], tint[3]); row.text:SetText(entry.text or "")
                row.icon:SetShown(entry.icon ~= nil or entry.classId~=nil)
                if entry.classId and A.SetClassIcon then A.SetClassIcon(row.icon,entry.classId) elseif entry.icon then kit.setIcon(row.icon, entry.icon) end
                if entry.raceId and not row.race then row.race=row:CreateTexture(nil,"ARTWORK");row.race:SetSize(24,24);row.race:SetPoint("TOPLEFT",32,-4) end
                if row.race then row.race:SetShown(entry.classId~=nil and entry.raceId~=nil);if entry.raceId then A.SetRaceIcon(row.race,entry.raceId) end end
                local h = math.max((entry.icon or entry.classId) and 34 or 0, row.text:GetStringHeight() or 16, entry.size or 12) + (entry.head and 12 or 8)
                row:SetHeight(h); row.rule:SetShown(entry.head == true or entry.onClick ~= nil)
                y = y + h
            end
            for i = #entries + 1, #document.pool do document.pool[i]:Hide() end
            scroll.child:SetHeight(math.max(1, y + 10))
            scroll:SetVerticalScroll(changed and 0 or math.min(oldOffset, math.max(0, y - (scroll:GetHeight() or 1))))
            scroll.UpdateThumb()
        end
        scroll.onResize = function() if document.spec then document.Set(document.spec) end end
        return document
    end

    --- A card: a filled panel with a thin outline and, optionally, a coloured line along the top.
    function kit.Card(parent, accent)
        local f = CreateFrame("Frame", nil, parent)
        A.NativePanel(f, C)
        -- a soft light from the top edge gives the panel some depth
        f.sheen = f:CreateTexture(nil, "BACKGROUND"); f.sheen:SetHeight(56); f.sheen:SetPoint("TOPLEFT"); f.sheen:SetPoint("TOPRIGHT")
        alphaGradient(f.sheen, "VERTICAL", 1, 1, 1, 0, 1, 1, 1, 0.055)
        if accent then
            f.accentLine = f:CreateTexture(nil, "ARTWORK"); f.accentLine:SetHeight(2); f.accentLine:SetPoint("TOPLEFT"); f.accentLine:SetPoint("TOPRIGHT"); paint(f.accentLine, accent, 0.75)
        end
        return f
    end

    --- A filter chip: a small pill that is either on or off. chip.SetLabel(text) sizes it to the text, chip.SetOn(bool) paints it.
    function kit.Chip(parent, onClick)
        local b = CreateFrame("Button", nil, parent); b:SetHeight(24)
        A.NativeButton(b, C, false); outline(b, C.line)
        b.bg = fill(b, C.off, 0.35, "ARTWORK")
        local hover = b:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(b); paint(hover, {1, 1, 1}, 0.07)
        b.text = label(b, 11, C.mist); b.text:SetPoint("CENTER"); b.text:SetJustifyH("CENTER")
        function b.SetLabel(value) b.text:SetText(value); b:SetWidth(math.max(34, (b.text:GetStringWidth() or 30) + 22)) end
        function b.SetOn(on)
            b.on = on and true or false
            paint(b.bg, on and C.lilac or C.off, on and 0.30 or 0.35)
            local c = on and C.text or C.mist
            b.text:SetTextColor(c[1], c[2], c[3])
        end
        b:SetScript("OnClick", onClick)
        return b
    end

    --- A horizontal bar, 0 to 1. bar.Set(fraction[, colour]); it follows its own width.
    function kit.ProgressBar(parent, color, height)
        local f = CreateFrame("Frame", nil, parent); f:SetHeight(height or 6)
        f.track = fill(f, C.off, 0.5)
        f.fill = f:CreateTexture(nil, "ARTWORK"); f.fill:SetPoint("TOPLEFT"); f.fill:SetPoint("BOTTOMLEFT"); paint(f.fill, color or C.lilac)
        f.fraction = 0
        local function apply(width)
            width = tonumber(width) or f:GetWidth() or 0
            f.fill:SetWidth(math.max(0.01, width * f.fraction)); f.fill:SetShown(f.fraction > 0)
        end
        function f.Set(fraction, c)
            f.fraction = clamp(tonumber(fraction) or 0, 0, 1)
            if c then paint(f.fill, c) end
            apply()
        end
        f:SetScript("OnSizeChanged", function(_, width) apply(width) end)
        return f
    end

    --- Cells side by side with the given weights and a gap; they stretch with the frame. f.cells[i] are plain frames to build in.
    function kit.Columns(parent, weights, gap)
        local f = CreateFrame("Frame", nil, parent)
        f.cells, f.weights, f.gap = {}, weights, gap or 10
        for i = 1, #weights do f.cells[i] = CreateFrame("Frame", nil, f) end
        function f.Layout(width)
            width = tonumber(width) or f:GetWidth() or 0
            local total = 0; for _, w in ipairs(weights) do total = total + w end
            local usable = math.max(0, width - f.gap * (#weights - 1))
            local x, used = 0, 0
            for i, cell in ipairs(f.cells) do
                -- the last cell takes what is left, so rounding can never push it past the right edge
                local w = (i == #f.cells) and (usable - used) or math.floor(usable * weights[i] / total + 0.5)
                cell:ClearAllPoints(); cell:SetPoint("TOPLEFT", f, "TOPLEFT", x, 0); cell:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0); cell:SetWidth(math.max(1, w))
                x = x + w + f.gap; used = used + w
            end
        end
        f:SetScript("OnSizeChanged", function(_, width) f.Layout(width) end)
        f.Layout()
        return f
    end

    --- A figure card: a big value, what it counts and a small line below (a change, a note).
    function kit.Stat(parent, iconPath, accent)
        local card = kit.Card(parent, accent or C.lilac)
        card.icon = card:CreateTexture(nil, "ARTWORK"); card.icon:SetSize(18, 18); card.icon:SetPoint("TOPRIGHT", -10, -12); kit.setIcon(card.icon, iconPath); card.icon:SetAlpha(0.8)
        card.value = label(card, 22, C.text); card.value:SetPoint("TOPLEFT", 12, -9)
        card.caption = label(card, 10, C.mist); card.caption:SetPoint("TOPLEFT", 12, -37); card.caption:SetPoint("TOPRIGHT", -10, -37); card.caption:SetWordWrap(false)
        card.delta = label(card, 10, C.green); card.delta:SetPoint("TOPLEFT", 12, -51); card.delta:SetPoint("TOPRIGHT", -10, -51); card.delta:SetWordWrap(false)
        return card
    end

    --- A search field with a grey hint while it is empty. onChange(text) runs on every edit.
    function kit.SearchBox(parent, width, onChange)
        local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        box:SetSize(width, 24); box:SetAutoFocus(false); box:SetMaxLetters(100); box:SetFont(kit.fontPath(), 12, "")
        kit.trackFont(box, 12)
        box.hint = label(box, 11, C.faint); box.hint:SetPoint("LEFT", 8, 0)
        box:SetScript("OnTextChanged", function(self)
            local value = self:GetText() or ""
            box.hint:SetShown(value == "")
            if onChange then onChange(value) end
        end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return box
    end

    --- A web address to copy. The game cannot open a link, so it is a field that selects its text when it is clicked (Ctrl+C copies it)
    --- and cannot be edited. box.SetUrl(url).
    function kit.LinkBox(parent)
        local box = CreateFrame("EditBox", nil, parent)
        box:SetHeight(28); box:SetAutoFocus(false); box:SetMaxLetters(200)
        -- a game font object first (an edit box without one draws no text at all), then our font over it
        local object = rawget(_G, "ChatFontNormal") or rawget(_G, "GameFontHighlight") or rawget(_G, "GameFontNormal")
        if object and box.SetFontObject then pcall(box.SetFontObject, box, object) end
        pcall(box.SetFont, box, kit.fontPath(), 12, ""); kit.trackFont(box, 12)
        box:SetTextInsets(10, 10, 0, 0); box:SetTextColor(C.text[1], C.text[2], C.text[3])
        box.bg = fill(box, C.canvas, 1)
        kit.outline(box, {C.lilac[1], C.lilac[2], C.lilac[3], 0.5})
        box.url = ""
        function box.SetUrl(url) box.url = url or ""; box:SetText(box.url); if box.SetCursorPosition then box:SetCursorPosition(0) end end
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        box:SetScript("OnTextChanged", function(self, user)
            if user and self:GetText() ~= box.url then self:SetText(box.url); self:HighlightText() end   -- (read-only: a typed letter is put back)
        end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
        return box
    end

    --- A row of colour squares with names (the key of a chart). legend.Set(colors, names) sizes the frame to fit.
    function kit.Legend(parent)
        local f = CreateFrame("Frame", nil, parent); f:SetHeight(14)
        f.items = {}
        function f.Set(colors, names)
            local x = 0
            for i, name in ipairs(names) do
                local item = f.items[i]
                if not item then
                    item = {box = f:CreateTexture(nil, "ARTWORK"), text = label(f, 10, C.mist)}
                    item.box:SetSize(8, 8); f.items[i] = item
                end
                paint(item.box, colors[i] or C.lilac)
                item.text:SetText(name)
                item.box:ClearAllPoints(); item.box:SetPoint("LEFT", f, "LEFT", x, 0)
                item.text:ClearAllPoints(); item.text:SetPoint("LEFT", f, "LEFT", x + 12, 0)
                item.box:Show(); item.text:Show()
                x = x + 12 + (item.text:GetStringWidth() or 30) + 14
            end
            for i = #names + 1, #f.items do f.items[i].box:Hide(); f.items[i].text:Hide() end
            f:SetWidth(math.max(1, x - 14))
        end
        return f
    end

    --- A scrolling grid of item icons (equipped gear, bags). grid.SetCells(items[, emptyText]) with items[i] = {icon, itemId, count, slot, label, caption, mark = "want"|"offer", markText, onClick}; {header = "Weapons"} is a full-width group title.
    function kit.IconGrid(parent, size, gap)
        gap = gap or 6
        local scroll = kit.ScrollArea(parent, 0)
        local content = scroll.child
        scroll.cells = {}
        scroll.empty = label(scroll, 12, C.mist); scroll.empty:SetPoint("TOPLEFT", 14, -30); scroll.empty:SetPoint("TOPRIGHT", -14, -30); scroll.empty:SetJustifyH("CENTER")
        local data = {}
        scroll.heads = {}
        local marks = {want = C.green, offer = C.peach}
        local function tip(cell)
            local item = cell.item
            if not item or not GameTooltip then return end
            pcall(function()
                GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
                if item.itemId then GameTooltip:SetHyperlink("item:" .. item.itemId) else GameTooltip:SetText(tostring(item.label or "")) end
                if item.slot then GameTooltip:AddLine(tostring(item.slot), 0.7, 0.7, 0.75) end
                GameTooltip:Show()
            end)
        end
        local function newCell()
            local b = CreateFrame("Button", nil, content); b:SetSize(size, size)
            fill(b, C.well, 1)
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            b.edges = {}
            for _, def in ipairs({{"TOPLEFT", "TOPRIGHT", nil, 1}, {"BOTTOMLEFT", "BOTTOMRIGHT", nil, 1}, {"TOPLEFT", "BOTTOMLEFT", 1, nil}, {"TOPRIGHT", "BOTTOMRIGHT", 1, nil}}) do
                local t = b:CreateTexture(nil, "OVERLAY"); t:SetPoint(def[1]); t:SetPoint(def[2])
                if def[3] then t:SetWidth(def[3]) else t:SetHeight(def[4]) end
                b.edges[#b.edges + 1] = t
            end
            b.tint = b:CreateTexture(nil, "OVERLAY"); b.tint:SetAllPoints(b)
            b.count = label(b, 10, C.text); b.count:SetPoint("BOTTOMRIGHT", -3, 3); b.count:SetJustifyH("RIGHT")
            b.markText = label(b, 9, C.text); b.markText:SetPoint("TOPLEFT", 3, -3)
            b.caption = label(b, 8, C.mist); b.caption:SetPoint("BOTTOMLEFT", 3, 3); b.caption:SetWidth(size - 6); b.caption:SetJustifyH("LEFT"); b.caption:SetWordWrap(false)
            b:SetScript("OnEnter", tip)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            b:SetScript("OnClick", function(self) if self.item and self.item.onClick then self.item.onClick() end end)
            return b
        end
        local function qualityColor(itemId)
            local _, _, q = A.Call(GetItemInfo, itemId)
            local color = q and type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[q]
            if color and q >= 2 then return {color.r, color.g, color.b, 1} end
        end
        local function newHead()
            local h = CreateFrame("Frame", nil, content); h:SetHeight(16)
            h.text = label(h, 10, C.gold); h.text:SetPoint("LEFT", 2, 0)
            h.rule = h:CreateTexture(nil, "ARTWORK"); h.rule:SetHeight(1); h.rule:SetPoint("LEFT", h.text, "RIGHT", 8, 0); h.rule:SetPoint("RIGHT", h, "RIGHT", 0, 0); paint(h.rule, C.line, 0.7)
            return h
        end
        function scroll.Layout(width)
            width = tonumber(width) or content:GetWidth() or 300
            local columns = math.max(1, math.floor((width + gap) / (size + gap)))
            local column, y, cellIndex, headIndex = 0, 0, 0, 0
            for _, item in ipairs(data) do
                if item.header then
                    if column > 0 then column = 0; y = y + size + gap end
                    headIndex = headIndex + 1
                    local head = scroll.heads[headIndex]
                    if head then
                        head:ClearAllPoints(); head:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); head:SetWidth(math.max(40, width)); y = y + 20
                    end
                else
                    cellIndex = cellIndex + 1
                    local cell = scroll.cells[cellIndex]
                    if cell then cell:ClearAllPoints(); cell:SetPoint("TOPLEFT", content, "TOPLEFT", column * (size + gap), -y) end
                    column = column + 1
                    if column >= columns then column = 0; y = y + size + gap end
                end
            end
            if column > 0 then y = y + size + gap end
            content:SetHeight(math.max(1, y))
            scroll.UpdateThumb()
        end
        scroll.onResize = scroll.Layout
        function scroll.SetCells(items, emptyText)
            data = items
            local cellIndex, headIndex = 0, 0
            for _, item in ipairs(items) do
                if item.header then
                    headIndex = headIndex + 1
                    local head = scroll.heads[headIndex]
                    if not head then head = newHead(); scroll.heads[headIndex] = head end
                    head.text:SetText(tostring(item.header)); head:Show()
                else
                    cellIndex = cellIndex + 1
                    local cell = scroll.cells[cellIndex]
                    if not cell then cell = newCell(); scroll.cells[cellIndex] = cell end
                    cell.item = item
                    kit.setIcon(cell.icon, item.icon)
                    local edge = marks[item.mark] or (item.itemId and qualityColor(item.itemId)) or C.line
                    for _, t in ipairs(cell.edges) do paint(t, edge) end
                    local mark = marks[item.mark]
                    if mark then paint(cell.tint, mark, 0.22); cell.tint:Show() else cell.tint:Hide() end
                    cell.markText:SetText(item.markText or "")
                    cell.caption:SetText(item.caption or "")
                    cell.count:SetText((item.count or 0) > 1 and tostring(item.count) or "")
                    cell:Show()
                end
            end
            for i = cellIndex + 1, #scroll.cells do scroll.cells[i]:Hide() end
            for i = headIndex + 1, #scroll.heads do scroll.heads[i]:Hide() end
            scroll.empty:SetText(cellIndex == 0 and (emptyText or "") or "")
            scroll.Layout()
        end
        return scroll
    end

    --- A switch row: a track and a knob, a title and, under it, a small explanation. sw.Set(on[, enabled]); sw.SetTexts(title, sub).
    --- onClick(newValue) runs on a click while it is enabled.
    function kit.Switch(parent, onClick, height)
        local b = CreateFrame("Button", nil, parent); b:SetHeight(height or 40)
        b.bg = fill(b, C.card, 0.6)
        local hover = b:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(b); paint(hover, {1, 1, 1}, 0.05)
        b.track = b:CreateTexture(nil, "ARTWORK"); b.track:SetSize(34, 18); b.track:SetPoint("LEFT", 14, 0)
        b.knob = b:CreateTexture(nil, "OVERLAY"); b.knob:SetSize(14, 14); paint(b.knob, C.text)
        b.title = label(b, 13, C.text); b.title:SetWordWrap(false)
        b.sub = label(b, 10, C.mist)
        b.on, b.enabled = false, true
        function b.SetTexts(title, sub)
            b.title:SetText(title or ""); b.sub:SetText(sub or "")
            b.title:ClearAllPoints(); b.sub:ClearAllPoints()
            if sub and sub ~= "" then
                b.title:SetPoint("TOPLEFT", 62, -7); b.title:SetPoint("TOPRIGHT", -12, -7)
                b.sub:SetPoint("TOPLEFT", 62, -25); b.sub:SetPoint("TOPRIGHT", -12, -25); b.sub:Show()
            else
                b.title:SetPoint("LEFT", 62, 0); b.title:SetPoint("RIGHT", -12, 0); b.sub:Hide()
            end
        end
        function b.Set(on, enabled)
            b.on = on and true or false
            if enabled ~= nil then b.enabled = enabled and true or false end
            paint(b.track, b.on and C.lilac or C.off, b.enabled and 1 or 0.4)
            b.knob:ClearAllPoints(); b.knob:SetPoint("LEFT", b.track, "LEFT", b.on and 18 or 2, 0)
            local c = b.enabled and C.text or C.faint
            b.title:SetTextColor(c[1], c[2], c[3])
        end
        b:SetScript("OnClick", function() if b.enabled and onClick then onClick(not b.on) end end)
        b.SetTexts("", "")
        return b
    end

    --- A choice among several: a card with a round mark, a title and a description. option.Set(selected); option.SetTexts(title, description).
    function kit.Option(parent, onClick, height)
        local b = CreateFrame("Button", nil, parent); b:SetHeight(height or 66)
        b.bg = fill(b, C.card, 0.6)
        local hover = b:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(b); paint(hover, {1, 1, 1}, 0.05)
        b.edges = {}
        for _, def in ipairs({{"TOPLEFT", "TOPRIGHT", nil, 1}, {"BOTTOMLEFT", "BOTTOMRIGHT", nil, 1}, {"TOPLEFT", "BOTTOMLEFT", 1, nil}, {"TOPRIGHT", "BOTTOMRIGHT", 1, nil}}) do
            local e = b:CreateTexture(nil, "BORDER"); e:SetPoint(def[1]); e:SetPoint(def[2])
            if def[3] then e:SetWidth(def[3]) else e:SetHeight(def[4]) end
            b.edges[#b.edges + 1] = e
        end
        b.ring = b:CreateTexture(nil, "ARTWORK"); b.ring:SetSize(16, 16); b.ring:SetPoint("TOPLEFT", 14, -14)
        b.dot = b:CreateTexture(nil, "OVERLAY"); b.dot:SetSize(8, 8); b.dot:SetPoint("CENTER", b.ring, "CENTER")
        b.title = label(b, 14, C.text); b.title:SetPoint("TOPLEFT", 42, -10); b.title:SetPoint("TOPRIGHT", -12, -10); b.title:SetWordWrap(false)
        b.sub = label(b, 11, C.mist); b.sub:SetPoint("TOPLEFT", 42, -32); b.sub:SetPoint("TOPRIGHT", -12, -32)
        function b.SetTexts(title, sub) b.title:SetText(title or ""); b.sub:SetText(sub or "") end
        function b.Set(selected)
            b.selected = selected and true or false
            for _, e in ipairs(b.edges) do paint(e, b.selected and C.lilac or C.line, b.selected and 0.9 or nil) end
            paint(b.ring, b.selected and C.lilac or C.off, 1)
            paint(b.dot, C.canvas, 1); b.dot:SetShown(b.selected)
            paint(b.bg, b.selected and C.violet or C.card, b.selected and 0.45 or 0.6)
        end
        b:SetScript("OnClick", function() if onClick then onClick() end end)
        b.Set(false)
        return b
    end

    --- Rows of a label, a bar and a value, longest first (top areas, best times). list.SetRows({{label=, value=, text=, color=}}).
    function kit.BarList(parent)
        local list = CreateFrame("Frame", nil, parent)
        list.rows = {}
        local ROW = 34
        function list.SetRows(rows, emptyText)
            local peak = 1
            for _, row in ipairs(rows) do peak = math.max(peak, row.value or 0) end
            for i, row in ipairs(rows) do
                local r = list.rows[i]
                if not r then
                    r = CreateFrame("Frame", nil, list)
                    r.label = label(r, 12, C.text); r.label:SetWordWrap(false)
                    r.value = label(r, 12, C.mist); r.value:SetJustifyH("RIGHT")
                    r.bar = kit.ProgressBar(r, C.lilac, 5)
                    list.rows[i] = r
                end
                r:ClearAllPoints(); r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW); r:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(i - 1) * ROW); r:SetHeight(ROW - 4)
                r.value:ClearAllPoints(); r.value:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0); r.value:SetWidth(60)
                r.label:ClearAllPoints(); r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.label:SetPoint("TOPRIGHT", r, "TOPRIGHT", -66, 0)
                r.bar:ClearAllPoints(); r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 2); r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 2)
                r.label:SetText(row.label or ""); r.value:SetText(row.text or tostring(row.value or 0))
                r.bar.Set((row.value or 0) / peak, row.color or C.lilac)
                r:Show()
            end
            for i = #rows + 1, #list.rows do list.rows[i]:Hide() end
            if not list.empty then
                list.empty = label(list, 12, C.mist); list.empty:SetPoint("TOPLEFT", 8, -24); list.empty:SetPoint("TOPRIGHT", -8, -24); list.empty:SetJustifyH("CENTER")
            end
            list.empty:SetText(#rows == 0 and (emptyText or "") or "")
        end
        return list
    end

    --- A stacked bar chart, one bar per day. chart.SetData(days, colors, names) where days[i] = {label=, values={...}, total=}.
    function kit.BarChart(parent)
        local chart = CreateFrame("Frame", nil, parent)
        chart.segments, chart.labels, chart.hits, chart.lines, chart.days, chart.colors, chart.names = {}, {}, {}, {}, {}, {}, {}
        for i = 1, 3 do chart.lines[i] = chart:CreateTexture(nil, "BACKGROUND"); chart.lines[i]:SetHeight(1); paint(chart.lines[i], C.line) end
        chart.topText = label(chart, 9, C.faint); chart.topText:SetJustifyH("RIGHT")
        chart.midText = label(chart, 9, C.faint); chart.midText:SetJustifyH("RIGHT")
        local LABEL_H, TOP, GAP, AXIS_W = 16, 8, 3, 26

        local function showTip(hit)
            local day = hit.day
            if not day or not GameTooltip then return end
            pcall(function()
                GameTooltip:SetOwner(hit, "ANCHOR_TOP"); GameTooltip:AddLine(tostring(day.label or ""), 1, 1, 1)
                for s, value in ipairs(day.values) do
                    local c = chart.colors[s] or C.text
                    GameTooltip:AddDoubleLine(tostring(chart.names[s] or ""), tostring(value), c[1], c[2], c[3], 1, 1, 1)
                end
                GameTooltip:Show()
            end)
        end

        function chart.Layout(width, height)
            width = tonumber(width) or chart:GetWidth() or 0
            height = tonumber(height) or chart:GetHeight() or 0
            local days = chart.days
            local n = #days
            local plotW, plotH = math.max(20, width - AXIS_W), math.max(10, height - LABEL_H - TOP)
            local peak = 0
            for _, day in ipairs(days) do peak = math.max(peak, day.total or 0) end
            local top = niceMax(math.max(peak, 1))
            chart.top = top
            local barW = math.max(2, math.floor((plotW - GAP * math.max(n - 1, 0)) / math.max(n, 1)))
            local every = math.max(1, math.ceil(34 / (barW + GAP)))   -- a date label is about 34 px wide
            for i, day in ipairs(days) do
                local x = AXIS_W + (i - 1) * (barW + GAP)
                local y = LABEL_H
                local row = chart.segments[i]; if not row then row = {}; chart.segments[i] = row end
                for s, value in ipairs(day.values) do
                    local seg = row[s]
                    if not seg then seg = chart:CreateTexture(nil, "ARTWORK"); row[s] = seg end
                    local h = value > 0 and math.max(1, math.floor(value / top * plotH + 0.5)) or 0
                    seg:ClearAllPoints(); seg:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", x, y); seg:SetSize(barW, math.max(h, 0.01))
                    paint(seg, chart.colors[s] or C.lilac); seg:SetShown(h > 0)
                    y = y + h
                end
                for s = #day.values + 1, #row do row[s]:Hide() end
                local fs = chart.labels[i]
                if not fs then fs = label(chart, 9, C.faint); fs:SetJustifyH("CENTER"); chart.labels[i] = fs end
                fs:ClearAllPoints(); fs:SetPoint("BOTTOM", chart, "BOTTOMLEFT", x + barW / 2, 1)
                fs:SetText(day.label or ""); fs:SetShown((n - i) % every == 0)
                local hit = chart.hits[i]
                if not hit then
                    hit = CreateFrame("Frame", nil, chart); hit:EnableMouse(true)
                    hit:SetScript("OnEnter", showTip)
                    hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                    chart.hits[i] = hit
                end
                hit.day = day
                hit:ClearAllPoints(); hit:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", x - 1, LABEL_H); hit:SetSize(barW + GAP, plotH); hit:Show()
            end
            for i = n + 1, #chart.labels do chart.labels[i]:Hide() end
            for i = n + 1, #chart.hits do chart.hits[i]:Hide() end
            for i = n + 1, #chart.segments do for _, seg in pairs(chart.segments[i]) do seg:Hide() end end
            for i, offset in ipairs({LABEL_H, LABEL_H + plotH / 2, LABEL_H + plotH}) do
                local line = chart.lines[i]
                line:ClearAllPoints(); line:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", AXIS_W, offset); line:SetPoint("BOTTOMRIGHT", chart, "BOTTOMRIGHT", 0, offset)
            end
            chart.topText:ClearAllPoints(); chart.topText:SetPoint("RIGHT", chart, "BOTTOMLEFT", AXIS_W - 5, LABEL_H + plotH); chart.topText:SetText(tostring(top))
            chart.midText:ClearAllPoints(); chart.midText:SetPoint("RIGHT", chart, "BOTTOMLEFT", AXIS_W - 5, LABEL_H + plotH / 2)
            chart.midText:SetText(top >= 2 and top % 2 == 0 and tostring(top / 2) or "");
        end

        function chart.SetData(days, colors, names)
            chart.days, chart.colors, chart.names = days or {}, colors or {}, names or {}
            chart.Layout()
        end
        chart:SetScript("OnSizeChanged", function(_, width, height) chart.Layout(width, height) end)
        return chart
    end
end
