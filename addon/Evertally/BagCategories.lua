local _, A = ...
-- The bag window's categories, as the player wants them (BagWindow.lua: BW.Sections, the rules): a panel beside the
-- bags with every section in its order. Each moves up or down; a category of the player's own has a name and a search
-- (words of an item's name, #tags) and can be deleted; a new one comes first. Items dragged onto a section's heading in
-- the bags go into it (BW.PutItem).
local BW = A.BagWindow
if not BW then return end
local Cats = {}
BW.Categories = Cats

local WIDTH, PAD, ROW_BUILTIN, ROW_OWN = 360, 14, 32, 64
local kit, C, panel

local function paint(t, c, a)
    if t.SetTextColor and not t.SetTexture then t:SetTextColor(c[1], c[2], c[3], a or c[4] or 1); return end
    kit.paint(t, c, a)
end

local function editBox(parent, width, hintKey, onCommit)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 22); box:SetAutoFocus(false)
    if box.SetFont then box:SetFont(kit.fontPath("body"), 12, "") end
    if box.SetTextInsets then box:SetTextInsets(8, 8, 0, 0) end
    box:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    box.bg = box:CreateTexture(nil, "BACKGROUND"); box.bg:SetAllPoints(box); paint(box.bg, C.well or C.card, 1)
    kit.outline(box, C.line)
    box.hint = kit.label(box, 11, C.faint); box.hint:SetPoint("LEFT", 8, 0); box.hint:SetText(A.L(hintKey))
    box:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
    local function commit(self) self:ClearFocus(); if onCommit then onCommit(self:GetText() or "") end end
    box:SetScript("OnEnterPressed", commit)
    box:SetScript("OnEditFocusLost", function(self) if onCommit then onCommit(self:GetText() or "") end end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function row(i)
    panel.rows = panel.rows or {}
    local r = panel.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, panel.body); r:SetWidth(WIDTH - PAD * 2)
    r.rule = r:CreateTexture(nil, "BACKGROUND"); r.rule:SetHeight(1); r.rule:SetPoint("BOTTOMLEFT"); r.rule:SetPoint("BOTTOMRIGHT"); paint(r.rule, C.line, 1)
    r.tick = r:CreateTexture(nil, "ARTWORK"); r.tick:SetSize(2, 11); r.tick:SetPoint("TOPLEFT", 0, -10); paint(r.tick, C.gold, 1)
    r.name = kit.label(r, 13, C.text); r.name:SetPoint("TOPLEFT", 10, -8)
    r.kind = kit.label(r, 10, C.faint); r.kind:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    r.nameBox = editBox(r, WIDTH - PAD * 2 - 100, "bwCatName", function(text)
        local e = BW.Section(r.key)
        if type(e) == "table" and text:match("%S") and e.name ~= text then e.name = text; BW.Request() end
    end)
    r.nameBox:SetPoint("TOPLEFT", 8, -5)
    r.queryBox = editBox(r, WIDTH - PAD * 2 - 100, "bwCatQuery", function(text)
        local e = BW.Section(r.key)
        if type(e) == "table" and e.query ~= text then e.query = text; BW.Request() end
    end)
    r.queryBox:SetPoint("TOPLEFT", r.nameBox, "BOTTOMLEFT", 0, -6)
    r.del = kit.IconButton(r, "close", 22, function() if BW.RemoveSection(r.key) then Cats.Refresh(); BW.Request() end end, "bwCatDelete")
    r.del:SetPoint("TOPRIGHT", 0, -5)
    r.down = kit.IconButton(r, "chevron-down", 22, function() if BW.MoveSection(r.key, 1) then Cats.Refresh(); BW.Request() end end, "bwCatDown")
    r.down:SetPoint("RIGHT", r.del, "LEFT", -2, 0)
    r.up = kit.IconButton(r, "chevron-up", 22, function() if BW.MoveSection(r.key, -1) then Cats.Refresh(); BW.Request() end end, "bwCatUp")
    r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
    panel.rows[i] = r
    return r
end

function Cats.Refresh()
    if not panel then return end
    local list = BW.Sections()
    local y = 0
    for i, e in ipairs(list) do
        local r = row(i)
        local own = type(e) == "table"
        r.key = own and e.key or e
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, -y)
        r:SetHeight(own and ROW_OWN or ROW_BUILTIN)
        r.name:SetShown(not own); r.kind:SetShown(not own)
        r.nameBox:SetShown(own); r.queryBox:SetShown(own); r.del:SetShown(own)
        if own then
            if not r.nameBox:HasFocus() then r.nameBox:SetText(e.name or "") end
            if not r.queryBox:HasFocus() then r.queryBox:SetText(e.query or "") end
            r.tick:SetShown(false)
        else
            r.name:SetText(BW.SectionName(e)); r.kind:SetText(A.L("bwCatBuiltin")); r.tick:SetShown(true)
        end
        r.up:SetAlpha(i > 1 and 1 or 0.3); r.down:SetAlpha(i < #list and 1 or 0.3)
        r:Show()
        y = y + (own and ROW_OWN or ROW_BUILTIN)
    end
    for i = #list + 1, #(panel.rows or {}) do panel.rows[i]:Hide() end
    panel.body:SetHeight(math.max(1, y))
    panel:SetHeight(panel.top + y + 56)
end

function Cats.Build(anchor)
    if panel then return panel end
    kit = kit or A.UIKit(); C = C or kit.C
    panel = CreateFrame("Frame", "EvertallyBagCategories", UIParent)
    panel:SetWidth(WIDTH); panel:SetFrameStrata("HIGH"); panel:SetToplevel(true); panel:SetClampedToScreen(true); panel:EnableMouse(true)
    A.NativeFrame(panel, C)
    panel.title = kit.label(panel, 15, C.bright); panel.title:SetPoint("TOPLEFT", PAD, -14); panel.title:SetText(A.L("bwCatsTitle"))
    panel.close = kit.IconButton(panel, "close", 24, function() panel:Hide() end, "bwClose"); panel.close:SetPoint("TOPRIGHT", -10, -10)
    panel.hint = kit.label(panel, 11, C.mist); panel.hint:SetPoint("TOPLEFT", PAD, -40); panel.hint:SetWidth(WIDTH - PAD * 2)
    panel.hint:SetJustifyH("LEFT"); if panel.hint.SetWordWrap then panel.hint:SetWordWrap(true) end
    panel.hint:SetText(A.L("bwCatsHint"))
    panel.top = 40 + math.ceil(panel.hint:GetStringHeight() or 40) + 12
    panel.body = CreateFrame("Frame", nil, panel); panel.body:SetPoint("TOPLEFT", PAD, -panel.top); panel.body:SetWidth(WIDTH - PAD * 2)
    panel.add = kit.Button(panel, "bwCatNew", 160, "primary", function() BW.AddSection(); Cats.Refresh(); BW.Request() end)
    panel.add:SetPoint("BOTTOMLEFT", PAD, 14); panel.add:SetHeight(28)
    if panel.add.text then panel.add.text:SetText(A.L("bwCatNew")) end
    panel.reset = kit.Button(panel, "bwCatReset", 150, "ghost", function() BW.ResetSections(); Cats.Refresh(); BW.Request() end)
    panel.reset:SetPoint("BOTTOMRIGHT", -PAD, 14); panel.reset:SetHeight(28)
    if panel.reset.text then panel.reset.text:SetText(A.L("bwCatReset")) end
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "EvertallyBagCategories") end
    panel:Hide()
    return panel
end

function Cats.Show(anchor)
    Cats.Build()
    panel:ClearAllPoints()
    if anchor then panel:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0) else panel:SetPoint("CENTER") end
    panel.title:SetText(A.L("bwCatsTitle")); panel.hint:SetText(A.L("bwCatsHint"))
    panel:Show()
    Cats.Refresh()
end
function Cats.Shown() return panel ~= nil and panel:IsShown() end
function Cats.Toggle(anchor) if Cats.Shown() then panel:Hide() else Cats.Show(anchor) end end
