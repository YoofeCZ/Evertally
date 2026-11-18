local _, A = ...
-- Evertally's pages in Evertally Guide's hub, built from the hub's own parts (EvertallyGuide.Widgets and Theme), the way
-- its Lookup (the Database) is: the hub's tabs and search box, a list of folders and one-line rows (the icon in the
-- gutter, the name in its subject's colour, a note on the right, the selection washed with an accent bar) and a details
-- pane on the right (a band of the place's zone art, the icon in a dark well, the name large, the facts under it, the
-- action pinned at the bottom). Evertally's own marks over it: an accent tick before a folder's name and an accent edge
-- under the band.
--   A.HubKit.Ready(page)  the page is in the hub and the guide's parts are there
--   A.HubKit.Bleed(page)  the page takes the hub section's whole area (no inset, no page header)
--   A.HubKit.List(parent) -> list; list.Set(entries, selectedKey), list.scroll
--       entry: {folder = text, count = text} or {key, title, sub, icon (a file), glyph (a guide glyph), color (a palette
--       name) or rgb ({r, g, b}), tip (lines), onClick}
--   A.HubKit.Details(parent) -> pane; pane.Set(spec)
--       spec: {map (uiMapID for the band), icon, glyph, title, color, rgb, sub, facts = {{label, value}}, note,
--              button = {text, onClick}} or nil (nothing selected: pane.Empty(title, note))
local HK = {}
A.HubKit = HK

local ROW_H, FOLDER_H, ROW_X = 28, 32, 12
local DETAIL_W, ART_H, ICON = 372, 112, 36
local FACT_W = 92
HK.DETAIL_W = DETAIL_W

local function guide()
    local g = rawget(_G, "EvertallyGuide")
    if type(g) == "table" and type(g.Widgets) == "table" and type(g.Theme) == "table" and g.Widgets.Scroll and g.Widgets.Text then return g end
    return nil
end
HK.Guide = guide
-- (string.upper leaves the Czech letters alone: A.Upper in UI.lua maps them)
local function upper(text) return A.Upper and A.Upper(text or "") or string.upper(text or "") end

--- Whether `page` is drawn in the hub (GuideShell.lua marks the frame its pages sit in) with the guide's parts there.
function HK.Ready(page)
    local parent = page and page.GetParent and page:GetParent()
    return guide() ~= nil and type(parent) == "table" and rawget(parent, "evertallyHubInner") == true
end

--- The page takes the hub section's whole area, as the guide's own sections do (GuideShell.lua insets the old pages and
--- clips their headers).
function HK.Bleed(page)
    local inner = page:GetParent()
    local host = inner and inner:GetParent()
    if not host then return end
    page:SetParent(host)
    page:ClearAllPoints()
    page:SetAllPoints(host)
    page.evertallyBleed = true
end

local function textX(W) return (W.SHELL and W.SHELL.pad or 32) - ROW_X end

-- ---------------------------------------------------------------- the list
local function makeFolder(parent, W)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(FOLDER_H)
    local x = textX(W)
    f.Tick = W.Tex(f, "ARTWORK", "white", "accent")
    f.Tick:SetSize(2, 10)
    f.Tick:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x - 9, 9)
    f.Text = W.Text(f, "label", "accent")
    f.Text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 7)
    f.Count = W.Text(f, "number", "textMuted")
    f.Count:SetJustifyH("RIGHT")
    f.Count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -x, 7)
    f.Rule = W.Divider(f, false, 0.7)
    f.Rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0)
    f.Rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -x, 0)
    return f
end

local function makeRow(parent, g)
    local W, Theme = g.Widgets, g.Theme
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    if W.Hover then W.Hover(r) end
    r.Selected = r:CreateTexture(nil, "BACKGROUND")
    r.Selected:SetTexture(Theme.Media("white"))
    r.Selected:SetAllPoints(r)
    W.Painter(r.Selected, function(t) t:SetVertexColor(Theme.Wash("selected")) end)
    r.Bar = r:CreateTexture(nil, "ARTWORK")
    r.Bar:SetTexture(Theme.Media("white"))
    r.Bar:SetWidth(2)
    r.Bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.Bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    W.Color(r.Bar, "accent")
    local x = textX(W)
    r.Icon = r:CreateTexture(nil, "ARTWORK")
    r.Icon:SetSize(14, 14)
    r.Icon:SetPoint("CENTER", r, "LEFT", x / 2 - 1, 0)
    r.Title = W.Text(r, "body", "text")
    r.Title:SetPoint("LEFT", r, "LEFT", x, 0)
    r.Title:SetJustifyH("LEFT")
    r.Title:SetWordWrap(false)
    r.Sub = W.Text(r, "small", "textMuted")
    r.Sub:SetJustifyH("RIGHT")
    r.Sub:SetPoint("RIGHT", r, "RIGHT", -x, 0)
    r:SetScript("OnClick", function(self) if self.psClick then self.psClick() end end)
    r:SetScript("OnEnter", function(self) if self.psTip and W.SimpleTip then W.SimpleTip(self) end end)
    r:SetScript("OnLeave", function(self) if W.HideTip then W.HideTip(self) end end)
    return r
end

-- The icon of a row or the details: a file (an item's icon, cropped) or a guide glyph in its colour.
local function setIcon(tex, g, spec, on)
    local W, Theme = g.Widgets, g.Theme
    if spec.icon then
        W.Uncolor(tex)
        tex:SetTexture(spec.icon)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:SetVertexColor(1, 1, 1, 1)
    else
        tex:SetTexture(Theme.Media(spec.glyph or "icon-note"))
        tex:SetTexCoord(0, 1, 0, 1)
        W.Color(tex, on and "accent" or (spec.glyphColor or "textDim"))
    end
end
local function setColor(fs, g, spec, fallback)
    local W = g.Widgets
    if spec.rgb then W.Uncolor(fs); fs:SetTextColor(spec.rgb[1], spec.rgb[2], spec.rgb[3], 1)
    else W.Color(fs, spec.color or fallback or "text") end
end

function HK.List(parent)
    local g = guide()
    local W = g.Widgets
    local list = {rows = {}, folders = {}}
    local sf = W.Scroll(parent)
    list.scroll = sf
    function list.Set(entries, selected)
        list.entries, list.selected = entries, selected
        -- the list's width: the scroll frame's, else what its anchors give it in its parent
        local width = math.floor(tonumber(sf:GetWidth()) or 0)
        if width < 120 then width = math.floor((tonumber(parent:GetWidth()) or 0) - 4) end
        if width < 120 then width = 420 end
        local child = sf.Child
        child:SetWidth(width)
        local inner = width - ROW_X * 2
        local x = textX(W)
        local y, nr, nf = 8, 0, 0
        for _, e in ipairs(entries or {}) do
            if e.folder then
                nf = nf + 1
                local f = list.folders[nf] or makeFolder(child, W)
                list.folders[nf] = f
                if nr + nf > 1 then y = y + 10 end
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", child, "TOPLEFT", ROW_X, -y)
                f:SetWidth(inner)
                f.Text:SetText(upper(e.folder))
                f.Count:SetText(e.count or "")
                f:Show()
                y = y + FOLDER_H + 4
            else
                nr = nr + 1
                local r = list.rows[nr] or makeRow(child, g)
                list.rows[nr] = r
                local on = selected ~= nil and e.key == selected
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", child, "TOPLEFT", ROW_X, -y)
                r:SetWidth(inner)
                r.Selected:SetShown(on); r.Bar:SetShown(on)
                setIcon(r.Icon, g, e, on)
                r.Title:SetText(e.title or "")
                setColor(r.Title, g, e)
                r.Sub:SetText(e.sub or "")
                local subW = (e.sub and e.sub ~= "") and (r.Sub:GetStringWidth() + 16) or 0
                r.Title:SetWidth(math.max(60, inner - x * 2 - subW))
                r.psClick, r.psTip, r.psTipLines = e.onClick, e.tip and e.title or nil, e.tip
                r:Show()
                y = y + ROW_H
            end
        end
        for i = nr + 1, #list.rows do list.rows[i]:Hide() end
        for i = nf + 1, #list.folders do list.folders[i]:Hide() end
        W.SetScrollContent(sf, y + 16, sf:GetHeight())
    end
    sf:HookScript("OnSizeChanged", function() if list.entries then list.Set(list.entries, list.selected) end end)
    return list
end

-- ---------------------------------------------------------------- the details pane
function HK.Details(parent)
    local g = guide()
    local W, Theme, UI = g.Widgets, g.Theme, g.UI
    local pad = (W.SHELL and W.SHELL.side) or 24
    local innerW = DETAIL_W - pad * 2
    local d = CreateFrame("Frame", nil, parent)
    d:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    d:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    d:SetWidth(DETAIL_W)
    d:EnableMouse(true)
    W.Fill(d, "panel")
    local rule = W.Divider(d, true)
    rule:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0)
    rule:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 0, 0)
    local ZA = UI and UI.ZoneArt
    if ZA and ZA.Create then
        d.Art = ZA.Create(d, DETAIL_W, ART_H, "panel")
        d.Art.psZoom = 1.5
    else
        d.Art = CreateFrame("Frame", nil, d); d.Art:SetSize(DETAIL_W, ART_H); d.Art.Over = d.Art
    end
    d.Art:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0)
    -- Evertally's mark: an accent edge under the band
    d.Edge = W.Tex(d, "OVERLAY", "white", "accent")
    d.Edge:SetHeight(2)
    d.Edge:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -ART_H)
    d.Edge:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, -ART_H)
    local over = d.Art.Over or d.Art
    d.Well = CreateFrame("Frame", nil, over)
    d.Well:SetSize(ICON, ICON)
    d.Well:SetPoint("BOTTOMLEFT", d.Art, "BOTTOMLEFT", pad, 16)
    d.Well:SetFrameLevel(over:GetFrameLevel() + 2)
    d.WellGround = d.Well:CreateTexture(nil, "BACKGROUND")
    d.WellGround:SetTexture(Theme.Media("white"))
    d.WellGround:SetAllPoints(d.Well)
    W.Painter(d.WellGround, function(t) local r, gg, b = Theme.Color("scrim"); t:SetVertexColor(r, gg, b, 0.72) end)
    d.Icon = d.Well:CreateTexture(nil, "ARTWORK")
    d.Icon:SetPoint("TOPLEFT", d.Well, "TOPLEFT", 4, -4)
    d.Icon:SetPoint("BOTTOMRIGHT", d.Well, "BOTTOMRIGHT", -4, 4)
    d.Title = W.Text(over, "display", "text")
    d.Title:SetPoint("BOTTOMLEFT", d.Art, "BOTTOMLEFT", pad + ICON + 12, 16 + 11 + 7)
    d.Title:SetWidth(innerW - ICON - 12)
    d.Title:SetWordWrap(true)
    if d.Title.SetMaxLines then d.Title:SetMaxLines(2) end
    d.Title:SetJustifyH("LEFT")
    d.Sub = W.Text(over, "small", "textDim")
    d.Sub:SetPoint("BOTTOMLEFT", d.Art, "BOTTOMLEFT", pad + ICON + 12, 17)
    d.Sub:SetWidth(innerW - ICON - 12)
    d.Sub:SetJustifyH("LEFT")
    for _, fs in ipairs({d.Title, d.Sub}) do
        W.Painter(fs, function(t) local r, gg, b = Theme.Color("shade"); t:SetShadowOffset(0, -1); t:SetShadowColor(r, gg, b, 0.85) end)
    end
    d.Facts = {}
    -- a document's body under the facts: headings, paragraphs and links, scrolling (spec.blocks)
    d.Body = W.Scroll(d)
    d.Body:Hide()
    d.Blocks = {}
    d.Note = W.Text(d, "note", "textDim")
    d.Note:SetWordWrap(true)
    d.Note:SetJustifyH("LEFT")
    d.Note:SetJustifyV("TOP")
    d.Note:SetWidth(innerW)
    d.Primary = W.Button(d, "", function() if d.psAction then d.psAction() end end, {primary = true, height = 32})
    d.Primary:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", pad, pad)
    d.Primary:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -pad, pad)
    d.EmptyTitle = W.Text(d, "display", "text")
    d.EmptyTitle:SetPoint("TOPLEFT", d, "TOPLEFT", pad, -(ART_H + 24))
    d.EmptyTitle:SetWidth(innerW)
    d.EmptyTitle:SetJustifyH("LEFT")
    d.EmptyTitle:SetWordWrap(true)
    d.EmptyNote = W.Text(d, "note", "textDim")
    d.EmptyNote:SetWordWrap(true)
    d.EmptyNote:SetJustifyH("LEFT")
    d.EmptyNote:SetWidth(innerW)
    d.EmptyNote:SetPoint("TOPLEFT", d.EmptyTitle, "BOTTOMLEFT", 0, -10)

    local function fact(i)
        local f = d.Facts[i]
        if f then return f end
        f = {}
        f.Label = W.Text(d, "small", "textMuted"); f.Label:SetWidth(FACT_W); f.Label:SetJustifyH("LEFT")
        f.Value = W.Text(d, "note", "text"); f.Value:SetWidth(innerW - FACT_W); f.Value:SetJustifyH("LEFT"); f.Value:SetJustifyV("TOP"); f.Value:SetWordWrap(true)
        d.Facts[i] = f
        return f
    end
    local function block(i)
        local b = d.Blocks[i]
        if b then return b end
        b = CreateFrame("Button", nil, d.Body.Child)
        b.Text = W.Text(b, "note", "text")
        b.Text:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b.Text:SetWordWrap(true)
        b.Text:SetJustifyH("LEFT")
        b.Text:SetJustifyV("TOP")
        b.Icon = b:CreateTexture(nil, "ARTWORK")
        b.Icon:SetSize(16, 16)
        b.Icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        if W.Hover then W.Hover(b) end
        b:SetScript("OnClick", function(self) if self.psClick then self.psClick() end end)
        d.Blocks[i] = b
        return b
    end
    -- the blocks laid out from y (in the pane) down to the button. -> nothing
    local function layBlocks(blocks, y, bottom)
        if not blocks or #blocks == 0 then d.Body:Hide(); return end
        d.Body:ClearAllPoints()
        d.Body:SetPoint("TOPLEFT", d, "TOPLEFT", pad, -y)
        d.Body:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -pad + 8, bottom)
        d.Body:Show()
        local child = d.Body.Child
        child:SetWidth(innerW)
        local by, n = 0, 0
        for _, spec in ipairs(blocks) do
            if spec.text and spec.text ~= "" then
                n = n + 1
                local b = block(n)
                local inset = spec.icon and 22 or 0
                b.Icon:SetShown(spec.icon ~= nil)
                if spec.icon then b.Icon:SetTexture(spec.icon); b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
                b.Text:ClearAllPoints(); b.Text:SetPoint("TOPLEFT", b, "TOPLEFT", inset, 0); b.Text:SetWidth(innerW - inset)
                g.Theme.Font(b.Text, spec.head and "label" or (spec.onClick and "body" or "note"))
                W.Color(b.Text, spec.head and "accent" or (spec.onClick and "accent" or (spec.muted and "textDim" or "text")))
                b.Text:SetText(spec.head and upper(spec.text) or spec.text)
                if spec.head and n > 1 then by = by + 8 end
                local h = math.max(spec.icon and 18 or 0, b.Text:GetStringHeight())
                b:ClearAllPoints(); b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -by); b:SetSize(innerW, h + 2)
                b.psClick = spec.onClick
                b:EnableMouse(spec.onClick ~= nil)
                b:Show()
                by = by + h + (spec.head and 6 or 10)
            end
        end
        for i = n + 1, #d.Blocks do d.Blocks[i]:Hide() end
        W.SetScrollContent(d.Body, by + 8, d.Body:GetHeight())
    end

    local function paintArt(map)
        if ZA and ZA.Paint and d.Art.psW then pcall(ZA.Paint, d.Art, map) end
    end

    function d.Empty(title, note)
        paintArt(nil)
        d.Well:Hide(); d.Title:SetText(""); d.Sub:SetText("")
        for _, f in ipairs(d.Facts) do f.Label:Hide(); f.Value:Hide() end
        d.Note:Hide(); d.Primary:Hide(); d.Body:Hide()
        d.EmptyTitle:SetText(title or ""); d.EmptyNote:SetText(note or "")
        d.EmptyTitle:Show(); d.EmptyNote:Show()
    end
    function d.Set(spec)
        if not spec then return d.Empty() end
        d.EmptyTitle:Hide(); d.EmptyNote:Hide()
        paintArt(spec.map)
        d.Well:Show()
        setIcon(d.Icon, g, spec, false)
        d.Title:SetText(spec.title or "")
        setColor(d.Title, g, spec, "text")
        d.Sub:SetText(spec.sub or "")
        local y = ART_H + 22
        local n = 0
        for _, pair in ipairs(spec.facts or {}) do
            if pair[2] ~= nil and pair[2] ~= "" then
                n = n + 1
                local f = fact(n)
                f.Label:SetText(pair[1]); f.Value:SetText(tostring(pair[2]))
                f.Label:ClearAllPoints(); f.Label:SetPoint("TOPLEFT", d, "TOPLEFT", pad, -(y + 1))
                f.Value:ClearAllPoints(); f.Value:SetPoint("TOPLEFT", d, "TOPLEFT", pad + FACT_W, -y)
                f.Label:Show(); f.Value:Show()
                y = y + math.max(16, f.Value:GetStringHeight()) + 10
            end
        end
        for i = n + 1, #d.Facts do d.Facts[i].Label:Hide(); d.Facts[i].Value:Hide() end
        if spec.note and spec.note ~= "" then
            d.Note:SetText(spec.note)
            d.Note:ClearAllPoints(); d.Note:SetPoint("TOPLEFT", d, "TOPLEFT", pad, -(y + 6))
            d.Note:Show()
            y = y + 12 + d.Note:GetStringHeight()
        else d.Note:Hide() end
        layBlocks(spec.blocks, y + 4, spec.button and (pad + 32 + 12) or pad)
        local b = spec.button
        d.psAction = b and b.onClick or nil
        if b then
            if W.SetButtonText then W.SetButtonText(d.Primary, b.text) elseif d.Primary.Label then d.Primary.Label:SetText(b.text) end
            d.Primary:Show()
        else d.Primary:Hide() end
    end
    d.Empty()
    return d
end

--- A strip of figures (a value in the accent, its caption under it), hairlines between. -> strip; strip.Set(values, captions)
function HK.Stats(parent, n)
    local W = guide().Widgets
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(42)
    s.cells = {}
    for i = 1, n do
        local c = CreateFrame("Frame", nil, s)
        c.Value = W.Text(c, "title", "accent"); c.Value:SetPoint("TOPLEFT", c, "TOPLEFT", i > 1 and 12 or 0, -2); c.Value:SetJustifyH("LEFT")
        c.Caption = W.Text(c, "small", "textMuted"); c.Caption:SetPoint("TOPLEFT", c.Value, "BOTTOMLEFT", 0, -2); c.Caption:SetJustifyH("LEFT")
        c.Caption:SetWordWrap(false)
        if i > 1 then
            c.Rule = W.Divider(c, true)
            c.Rule:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -4); c.Rule:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, 6)
        end
        s.cells[i] = c
    end
    local function lay()
        local w = (tonumber(s:GetWidth()) or 0)
        if w < 40 then return end
        local cw = w / n
        for i, c in ipairs(s.cells) do
            c:ClearAllPoints(); c:SetPoint("TOPLEFT", s, "TOPLEFT", (i - 1) * cw, 0); c:SetSize(cw, 42)
            c.Caption:SetWidth(cw - 16)
        end
    end
    s:SetScript("OnSizeChanged", lay)
    function s.Set(values, captions)
        lay()
        for i, c in ipairs(s.cells) do c.Value:SetText(tostring(values[i] or "")); c.Caption:SetText(captions[i] or "") end
    end
    return s
end

--- An old page's row of chips as the hub's tabs: the chips out of sight (their labels and shown state still kept by
--- the page), the hub's tab row in their place. order: the keys in order; chips: key -> chip (chip.text its label);
--- active(): the key chosen; pick(key): what a chip's click did.
function HK.ChipsToTabs(page, order, chips, active, pick)
    local away = CreateFrame("Frame", nil, page); away:Hide()
    for _, key in ipairs(order) do if chips[key] then chips[key]:SetParent(away) end end
    page.hubTabs = function()
        local tabs = {}
        for _, key in ipairs(order) do
            local chip = chips[key]
            if chip and chip:IsShown() then tabs[#tabs + 1] = {key = key, label = chip.text and chip.text:GetText() or tostring(key)} end
        end
        return tabs
    end
    page.hubTab = active
    page.OnHubTab = pick
end

--- The game's input boxes (InputBoxTemplate) under `root` in the hub's look: their template art hidden, the hub's
--- field (its well, its border, its focus) and type in its place. Their scripts stay as they are.
function HK.SkinInputs(root)
    local g = guide()
    if not (g and g.Theme.Skin and root and root.GetChildren) then return end
    local W, Theme = g.Widgets, g.Theme
    local function walk(f, depth)
        if depth > 8 then return end
        for _, child in ipairs({f:GetChildren()}) do
            -- (one-line boxes that have no hub look yet: not the hub's own search boxes, not a multi-line text)
            if type(child) == "table" and child.IsObjectType and child:IsObjectType("EditBox") and not rawget(child, "evertallyHubInput")
                and not rawget(child, "psSkin") and not rawget(child, "Placeholder") and not (child.IsMultiLine and child:IsMultiLine()) then
                child.evertallyHubInput = true
                for _, region in ipairs({child:GetRegions()}) do
                    if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(0) end
                end
                for _, key in ipairs({"Left", "Middle", "Right"}) do local t = rawget(child, key); if t and t.SetAlpha then t:SetAlpha(0) end end
                Theme.Skin(child, "editbox")
                Theme.Font(child, "label"); W.Color(child, "text")
                if child.SetTextInsets then child:SetTextInsets(8, 8, 0, 0) end
                if child.SetHeight then child:SetHeight(30) end
                child:HookScript("OnEditFocusGained", function(self) if Theme.SetFocused then Theme.SetFocused(self, true) end end)
                child:HookScript("OnEditFocusLost", function(self) if Theme.SetFocused then Theme.SetFocused(self, false) end end)
            end
            walk(child, depth + 1)
        end
    end
    walk(root, 0)
end

--- The hub's search box (its look, its placeholder). onChange(text) on every edit.
function HK.Search(parent, placeholder, onChange)
    local W = guide().Widgets
    return W.SearchBox(parent, placeholder, function(text) onChange(text or "") end)
end
