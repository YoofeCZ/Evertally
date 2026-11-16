local _, A = ...
-- "What can I train?" inside the game's spellbook (PlayerSpellsFrame.SpellBookFrame, Forever): a tab beside the book's own
-- category tabs opens a page over the spell grid with Evertally's training model (Training.lua): what the trainer teaches
-- now, what comes in the next two levels and what later, with rank, level and price. Nothing in the book is changed: the
-- page lies over it and a click on any of the book's own tabs, a search or closing the book puts it away.
local S = {shown = false, offset = 0, ignored = nil}
A.SpellbookTraining = S

local words = {
    en = {sbTab = "What can I train?", sbTitle = "What can I train?", sbNow = "Available now", sbSoon = "Coming soon",
        sbLater = "Not yet available", sbLevel = "Level %d", sbQuest = "Quest", sbTotal = "Available total: %s",
        sbNone = "Nothing to train for your class in Evertally's data yet.",
        sbHint = "Hover a spell for details. Prices are what your trainer asked, or the base price until you visit one.",
        sbSetting = "\"What can I train?\" tab in the spellbook"},
    cs = {sbTab = "Co se můžu naučit?", sbTitle = "Co se můžu naučit?", sbNow = "Dostupné teď", sbSoon = "Brzy",
        sbLater = "Zatím nedostupné", sbLevel = "Úroveň %d", sbQuest = "Quest", sbTotal = "Celkem k dispozici: %s",
        sbNone = "Pro tvoje povolání zatím Evertally nemá data tréninku.",
        sbHint = "Najetím na kouzlo uvidíš podrobnosti. Cena je ta od tvého trenéra, dokud u něj nebudeš, základní.",
        sbSetting = "Záložka „Co se můžu naučit?“ ve spellbooku"},
}
for lang, entries in pairs(words) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local TAB_ART = {"spellbook-Tab-Frame-C60", "spellbook-Tab-Frame-Glow-C60"}
local PAGES = {left = "spellbook-Page-Left-C60", right = "spellbook-Page-Right-C60"}
local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local INK, MUTED, LATE = {0.25, 0.15, 0.07}, {0.42, 0.33, 0.22}, {0.62, 0.16, 0.1}
local SECTION = {now = {0.36, 0.75, 0.32}, soon = {0.42, 0.72, 0.92}, later = {0.95, 0.55, 0.42}}
local ROW_H, SOON = 22, 2

function S.Enabled() return not (A.db and A.db.settings and A.db.settings.spellbookTraining == false) end
function S.SetEnabled(on)
    if A.db then A.db.settings.spellbookTraining = on and nil or false end
    if S.launcher then S.launcher:SetShown(on and S.book ~= nil and S.book:IsShown()) end
    if not on then S.Hide() end
end

--- The lines of the page: a header per group, then its spells. `level` is the character's.
function S.Lines(level)
    local T = A.Training
    if not T then return {}, 0 end
    local model = T.Model()
    local groups = {now = {}, soon = {}, later = {}}
    for _, row in ipairs(T.Rows("all", "", false)) do
        if row.status == "ready" then groups.now[#groups.now + 1] = row
        elseif row.status ~= "known" and (row.level or 1) <= level + SOON and row.status == "later" then groups.soon[#groups.soon + 1] = row
        elseif row.status ~= "known" then groups.later[#groups.later + 1] = row end
    end
    local lines = {}
    for _, key in ipairs({"now", "soon", "later"}) do
        if #groups[key] > 0 then
            lines[#lines + 1] = {header = key, count = #groups[key]}
            for _, row in ipairs(groups[key]) do lines[#lines + 1] = {row = row, group = key} end
        end
    end
    return lines, model.total or 0
end

-- ---------------------------------------------------------------- drawing
local function label(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(A.FontPath and A.FontPath() or "Fonts\\FRIZQT__.TTF", size, "")
    fs:SetTextColor(color[1], color[2], color[3]); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    return fs
end

local function newRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r.band = r:CreateTexture(nil, "BACKGROUND"); r.band:SetAllPoints()
    r.hover = r:CreateTexture(nil, "HIGHLIGHT"); r.hover:SetAllPoints(); r.hover:SetColorTexture(1, 0.9, 0.6, 0.12)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 8, 0)
    r.name = label(r, 13, INK); r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0); r.name:SetPoint("RIGHT", r, "RIGHT", -230, 0)
    r.rank = label(r, 12, INK); r.rank:SetPoint("LEFT", r, "RIGHT", -222, 0); r.rank:SetWidth(80)
    r.level = label(r, 12, INK); r.level:SetPoint("LEFT", r, "RIGHT", -136, 0); r.level:SetWidth(80)
    r.price = label(r, 11, INK); r.price:SetPoint("RIGHT", r, "RIGHT", -6, 0); r.price:SetJustifyH("RIGHT")
    r:SetScript("OnEnter", function(self)
        local row = self.data
        if not row or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local id = A.Number(row.spellId or row.taughtId or row.id, 1)
        if not (id and pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. id)) then GameTooltip:SetText(row.name or "?") end
        if row.status == "requirements" and row.missingId then
            local missing = A.Training.SpellInfo(row.missingId)
            GameTooltip:AddLine(string.format(A.L("trainingPrerequisite"), missing.name or "?"), 1, 0.4, 0.3, true)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return r
end

local function build(book)
    local root = CreateFrame("Frame", "EvertallySpellbookTraining", PlayerSpellsFrame)
    root:SetAllPoints(book); root:EnableMouse(true); root:Hide()
    root.backing = root:CreateTexture(nil, "BACKGROUND", nil, -2); root.backing:SetAllPoints(); root.backing:SetColorTexture(0.86, 0.78, 0.62, 1)
    root.left = root:CreateTexture(nil, "BACKGROUND", nil, -1); root.left:SetAtlas(PAGES.left)
    root.left:SetPoint("TOPLEFT"); root.left:SetPoint("BOTTOMRIGHT", root, "BOTTOM")
    root.right = root:CreateTexture(nil, "BACKGROUND", nil, -1); root.right:SetAtlas(PAGES.right)
    root.right:SetPoint("TOPLEFT", root, "TOP"); root.right:SetPoint("BOTTOMRIGHT")
    root.whole = root:CreateTexture(nil, "BACKGROUND", nil, -1); root.whole:SetAtlas(PAGES.right); root.whole:SetAllPoints()
    root.title = label(root, 22, INK); root.title:SetPoint("TOPLEFT", 70, -78)
    root.total = label(root, 13, INK); root.total:SetPoint("TOPRIGHT", root, "TOPRIGHT", -70, -84); root.total:SetJustifyH("RIGHT")
    root.list = CreateFrame("Frame", nil, root)
    root.list:SetPoint("TOPLEFT", 62, -112); root.list:SetPoint("BOTTOMRIGHT", -56, 44)
    root.list:EnableMouseWheel(true)
    root.list:SetScript("OnMouseWheel", function(_, delta) S.offset = math.max(0, S.offset - delta * 3); S.Draw() end)
    root.empty = label(root.list, 13, MUTED); root.empty:SetPoint("TOPLEFT", 6, -6); root.empty:SetPoint("RIGHT", -6, 0); root.empty:SetWordWrap(true)
    root.hint = label(root, 11, MUTED); root.hint:SetPoint("BOTTOMLEFT", 66, 24); root.hint:SetPoint("RIGHT", root, "RIGHT", -60, 0)
    root.rows = {}
    root:SetScript("OnShow", function() S.Draw() end)
    return root
end

local function sizeRows()
    local root = S.root
    local height = root.list:GetHeight() or 0
    local want = math.max(1, math.floor(height / ROW_H))
    for i = #root.rows + 1, want do
        local r = newRow(root.list)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); r:SetPoint("RIGHT", root.list, "RIGHT", 0, 0)
        root.rows[i] = r
    end
    return want
end

function S.Draw()
    local root = S.root
    if not root or not root:IsShown() then return end
    local minimized = S.book and S.book.isMinimized
    root.whole:SetShown(minimized == true); root.left:SetShown(not minimized); root.right:SetShown(not minimized)
    root.title:SetText(A.L("sbTitle")); root.hint:SetText(A.L("sbHint"))
    local level = A.Number(A.Call(UnitLevel, "player"), 1) or 1
    local lines, total = S.Lines(level)
    root.total:SetText(string.format(A.L("sbTotal"), A.FormatMoney(total)))
    local visible = sizeRows()
    S.offset = math.max(0, math.min(S.offset, math.max(0, #lines - visible)))
    for i, r in ipairs(root.rows) do
        local line = i <= visible and lines[i + S.offset] or nil
        r:SetShown(line ~= nil); r.data = line and line.row
        if line and line.header then
            local c = SECTION[line.header]
            r.band:SetColorTexture(0.22, 0.14, 0.07, 0.75)
            r.icon:Hide(); r.rank:SetText(""); r.level:SetText(""); r.price:SetText("")
            r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 10, 0); r.name:SetPoint("RIGHT", -10, 0)
            r.name:SetText(A.L(line.header == "now" and "sbNow" or line.header == "soon" and "sbSoon" or "sbLater") .. "  •  " .. line.count)
            r.name:SetTextColor(c[1], c[2], c[3])
        elseif line then
            local row = line.row
            r.band:SetColorTexture(0, 0, 0, 0)
            r.icon:Show(); r.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.name:ClearAllPoints(); r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0); r.name:SetPoint("RIGHT", r, "RIGHT", -230, 0)
            r.name:SetText(row.name or "?"); r.name:SetTextColor(INK[1], INK[2], INK[3])
            r.rank:SetText(row.quest and A.L("sbQuest") or row.rank or "")
            r.level:SetText(line.group ~= "now" and string.format(A.L("sbLevel"), row.level or 1) or "")
            local late = (row.level or 1) > level
            r.level:SetTextColor((late and LATE or INK)[1], (late and LATE or INK)[2], (late and LATE or INK)[3])
            r.price:SetText(line.group == "now" and row.price and row.price > 0 and A.FormatMoney(row.price) or "")
        end
    end
    root.empty:SetText(A.L("sbNone")); root.empty:SetShown(#lines == 0)
end

-- ---------------------------------------------------------------- showing and hiding
local function paintTab()
    if not S.launcher then return end
    S.launcher.glow:SetShown(S.shown)
end
function S.Show()
    if not S.root then return end
    S.shown = true; S.offset = 0
    local nine = PlayerSpellsFrame and PlayerSpellsFrame.NineSlice
    -- just under the window's border, so the border is drawn over the page like over the book
    local level = A.Number(nine and A.Call(nine.GetFrameLevel, nine), 1) or (A.Number(A.Call(S.book.GetFrameLevel, S.book), 0) or 0) + 20
    local strata = A.Call(PlayerSpellsFrame.GetFrameStrata, PlayerSpellsFrame)
    if strata then S.root:SetFrameStrata(strata) end
    S.root:SetFrameLevel(math.max(1, level - 1))
    S.root:Show(); paintTab(); S.Draw()
end
function S.Hide()
    S.shown = false
    if S.root then S.root:Hide() end
    paintTab()
end
function S.Toggle() if S.shown then S.Hide() else S.Show() end end

-- the tab sits right of the book's own tabs; with What's Training? loaded, right of its tab too
local function placeLauncher()
    local tabs = S.book and S.book.CategoryTabSystem
    if not tabs or not S.launcher then return end
    local loaded = C_AddOns and A.Call(C_AddOns.IsAddOnLoaded, "WhatsTraining")
    S.launcher:ClearAllPoints()
    S.launcher:SetPoint("LEFT", tabs, "RIGHT", loaded and 56 or 8, 0)
    local nine = PlayerSpellsFrame.NineSlice
    S.launcher:SetFrameLevel((A.Number(nine and A.Call(nine.GetFrameLevel, nine), 1) or 10) + 5)
end

local function hookNativeTabs()
    local tabs = S.book and S.book.CategoryTabSystem
    if not tabs or S.tabsHooked then return end
    S.tabsHooked = true
    for _, child in ipairs({tabs:GetChildren()}) do
        if child.HookScript then child:HookScript("OnMouseDown", function() S.Hide() end) end
    end
end

function S.Attach()
    if S.book or not PlayerSpellsFrame or not PlayerSpellsFrame.SpellBookFrame then return false end
    local book = PlayerSpellsFrame.SpellBookFrame
    S.book = book
    S.root = build(book)
    local b = CreateFrame("Button", "EvertallySpellbookTrainingTab", PlayerSpellsFrame)
    b:SetSize(44, 32)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(34, 33); b.icon:SetPoint("BOTTOM", -1, 0); b.icon:SetTexture(ICON)
    b.frame = b:CreateTexture(nil, "ARTWORK", nil, 1); b.frame:SetAtlas(TAB_ART[1], true); b.frame:SetPoint("BOTTOM", 0, 1)
    b.glow = b:CreateTexture(nil, "ARTWORK", nil, 2); b.glow:SetAtlas(TAB_ART[2], true); b.glow:SetPoint("BOTTOM", 0, 1); b.glow:Hide()
    b:SetScript("OnClick", function() S.Toggle() end)
    b:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(A.L("sbTab")); GameTooltip:Show() end end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    S.launcher = b
    placeLauncher(); b:SetShown(S.Enabled())
    book:HookScript("OnShow", function() placeLauncher(); hookNativeTabs(); S.launcher:SetShown(S.Enabled()); if S.shown then S.Draw() end end)
    book:HookScript("OnHide", function() S.Hide(); S.launcher:Hide() end)
    book:HookScript("OnSizeChanged", function() placeLauncher(); S.Draw() end)
    if book.SearchBox and book.SearchBox.HookScript then book.SearchBox:HookScript("OnEditFocusGained", function() S.Hide() end) end
    hookNativeTabs()
    return true
end

A.On("ADDON_LOADED", function() if not S.book then pcall(S.Attach) end end)
A.On("PLAYER_LOGIN", function() pcall(S.Attach) end)
for _, event in ipairs({"SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "TRAINER_UPDATE"}) do
    A.On(event, function() if S.shown then S.Draw() end end)
end
