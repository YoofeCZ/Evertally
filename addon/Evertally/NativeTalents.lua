local _, A = ...
-- Profiles and import/export in the game's own talent window (PlayerSpellsFrame.TalentsFrame, Forever). Two buttons beside
-- the window's Apply Changes: "Profiles" (the builds saved for this class, saving the current talents, loading one) and
-- "Import / Export" (the same ETB1 code as Evertally's planner, TalentProfiles.lua). Loading a profile only stages it in
-- the talent window (C_Traits.ResetTree + PurchaseRank on the active config): nothing is learned until the player presses
-- the window's own Apply Changes, and closing the window without it leaves the talents as they were.
local N = {}
A.NativeTalents = N

local words = {
    en = {ntProfiles = "Profiles", ntTransfer = "Import / Export", ntSaveCurrent = "Save current talents as a profile",
        ntSaved = "Saved as \"%s\".", ntNoProfiles = "No saved profile for this class yet.",
        ntStaged = "\"%s\" is set in the talent window: check it and press Apply Changes. Close the window to leave your talents as they were.",
        ntStagedPartly = "\"%s\" is set except %d rank(s) the game refused (tier or level). Check the window before Apply Changes.",
        ntCombat = "Not in combat: talents can only change out of combat.", ntExportCurrent = "Export current talents",
        ntImport = "Import a code", ntImportApply = "Import and set", ntOpenPlanner = "Open Evertally's talent planner",
        ntProfileTip = "Click: set it in the talent window (press Apply Changes to keep it). Right-click: delete.",
        ntDeleted = "Profile \"%s\" deleted."},
    cs = {ntProfiles = "Profily", ntTransfer = "Import / Export", ntSaveCurrent = "Uložit současné talenty jako profil",
        ntSaved = "Uloženo jako „%s“.", ntNoProfiles = "Pro tohle povolání zatím není uložený žádný profil.",
        ntStaged = "„%s“ je nastavený v okně talentů: zkontroluj ho a stiskni Apply Changes. Zavřením okna zůstanou talenty jako dřív.",
        ntStagedPartly = "„%s“ je nastavený kromě %d bodů, které hra odmítla (řada nebo úroveň). Před Apply Changes okno zkontroluj.",
        ntCombat = "V boji ne: talenty jdou měnit jen mimo boj.", ntExportCurrent = "Exportovat současné talenty",
        ntImport = "Importovat kód", ntImportApply = "Importovat a nastavit", ntOpenPlanner = "Otevřít plánovač talentů Evertally",
        ntProfileTip = "Klik: nastavit v okně talentů (potvrď tlačítkem Apply Changes). Pravý klik: smazat.",
        ntDeleted = "Profil „%s“ smazán."},
}
for lang, entries in pairs(words) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local function rankOf(config, nodeID)
    local node = A.Call(C_Traits.GetNodeInfo, config, nodeID)
    return A.Number(A.Field(node, "currentRank"), 0) or A.Number(A.Field(node, "ranksPurchased"), 0) or 0
end

--- Stages `plan` in the talent window: the trees are refunded and the plan's ranks bought tier by tier. Returns ok and the
--- number of ranks the game refused; nothing is committed (the window's Apply Changes does that).
function A.StageTalentPlan(plan, trees)
    if A.Call(InCombatLockdown) then return false, "ntCombat" end
    if not (C_Traits and type(C_Traits.PurchaseRank) == "function" and type(C_Traits.ResetTree) == "function") then return false, "talentNoApi" end
    local config, treeIDs, wanted = nil, {}, {}
    for _, tree in ipairs(trees or {}) do
        if not tree.modern or not tree.configID then return false, "talentNoApi" end
        config = tree.configID
        for _, t in ipairs(tree.talents) do
            treeIDs[t.treeID] = true
            local r = plan.ranks[tree.tab] and plan.ranks[tree.tab][t.index] or 0
            if r > 0 then wanted[#wanted + 1] = {nodeID = t.nodeID, rank = r, tier = t.tier or 1, order = t.treeOrder or 1} end
        end
    end
    if not config then return false, "talentNoApi" end
    for treeID in pairs(treeIDs) do A.Call(C_Traits.ResetTree, config, treeID) end
    table.sort(wanted, function(a, b) if a.tier ~= b.tier then return a.tier < b.tier end; return a.order < b.order end)
    -- a few passes: a rank refused because an earlier tier was short goes through once that tier is filled
    for _ = 1, 4 do
        local bought = false
        for _, w in ipairs(wanted) do
            while rankOf(config, w.nodeID) < w.rank do
                if not A.Call(C_Traits.PurchaseRank, config, w.nodeID) then break end
                bought = true
            end
        end
        if not bought then break end
    end
    local missing = 0
    for _, w in ipairs(wanted) do missing = missing + math.max(0, w.rank - rankOf(config, w.nodeID)) end
    return true, missing
end

--- The talents as they are now (committed), as a plan.
function N.CurrentPlan()
    local trees = A.TalentTrees()
    if not trees or #trees == 0 then return nil, nil end
    return A.NewTalentPlan(trees, nil, false), trees
end

function N.SaveCurrent()
    local plan = N.CurrentPlan()
    if not plan then A.Print(A.L("talentNoApi")); return nil end
    local name = A.UniqueTalentProfileName(A.L("talentNameDefault"))
    A.SaveTalentBuild(plan, name)
    A.Print(string.format(A.L("ntSaved"), name))
    return name
end

function N.Stage(saved)
    local trees = A.TalentTrees()
    local plan = trees and A.LoadTalentBuild(saved, trees)
    if not plan then A.Print(A.L("talentProfileInvalid")); return false end
    local ok, result = A.StageTalentPlan(plan, trees)
    if not ok then A.Print(A.L(result)); return false end
    A.Print(string.format(A.L(result > 0 and "ntStagedPartly" or "ntStaged"), saved.name or "?", result))
    return true
end

-- ---------------------------------------------------------------- the menu of profiles
local function kit() return A.UIKit and A.UIKit() end
local function menu()
    if N.menu then return N.menu end
    local k = kit(); if not k then return nil end
    local m = CreateFrame("Frame", "EvertallyTalentProfilesMenu", UIParent)
    m:SetFrameStrata("DIALOG"); m:SetWidth(300); m:EnableMouse(true); m:Hide()
    A.NativePanel(m, k.C)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EvertallyTalentProfilesMenu" end
    m.rows = {}
    N.menu = m
    return m
end
local function row(m, i)
    local k = kit()
    local r = m.rows[i]
    if not r then
        r = CreateFrame("Button", nil, m); r:SetHeight(24)
        r:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 25); r:SetPoint("RIGHT", m, "RIGHT", -8, 0)
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.85, 0.5, 0.1)
        r.text = k.label(r, 12, k.C.text); r.text:SetPoint("LEFT", 8, 0); r.text:SetPoint("RIGHT", -8, 0); r.text:SetWordWrap(false)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, mouse) if self.action then self.action(mouse) end end)
        r:SetScript("OnEnter", function(self) if self.tip and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.tip, 1, 1, 1, 1, true); GameTooltip:Show() end end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        m.rows[i] = r
    end
    return r
end
function N.ShowMenu(anchor)
    local m = menu(); if not m then return end
    if m:IsShown() and m.anchor == anchor then m:Hide(); return end
    local k = kit()
    local entries = {}
    local list = A.SavedTalentBuilds()
    for index, saved in ipairs(list) do
        entries[#entries + 1] = {text = saved.name or "?", color = k.C.bright, tip = A.L("ntProfileTip"), action = function(mouse)
            if mouse == "RightButton" then
                table.remove(list, index); A.Print(string.format(A.L("ntDeleted"), saved.name or "?")); N.ShowMenu(anchor); N.ShowMenu(anchor)
            else m:Hide(); N.Stage(saved) end
        end}
    end
    if #list == 0 then entries[#entries + 1] = {text = A.L("ntNoProfiles"), color = k.C.mist} end
    entries[#entries + 1] = {text = "+ " .. A.L("ntSaveCurrent"), color = k.C.gold, action = function() N.SaveCurrent(); N.ShowMenu(anchor); N.ShowMenu(anchor) end}
    entries[#entries + 1] = {text = A.L("ntOpenPlanner"), color = k.C.text, action = function() m:Hide(); if A.OpenUI then A.OpenUI(); A.ShowView("talents") end end}
    for i, e in ipairs(entries) do
        local r = row(m, i)
        r.text:SetText(e.text); r.text:SetTextColor(e.color[1], e.color[2], e.color[3])
        r.action, r.tip = e.action, e.tip; r:Show()
    end
    for i = #entries + 1, #m.rows do m.rows[i]:Hide() end
    m:SetHeight(16 + #entries * 25)
    m:ClearAllPoints(); m:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
    m.anchor = anchor; m:Show()
end

-- ---------------------------------------------------------------- the import / export dialog
local function dialog()
    if N.dialog then return N.dialog end
    local k = kit(); if not k then return nil end
    local C = k.C
    local d = CreateFrame("Frame", "EvertallyTalentTransfer", UIParent)
    d:SetSize(520, 300); d:SetPoint("CENTER"); d:SetFrameStrata("DIALOG"); d:EnableMouse(true); d:Hide()
    A.NativePanel(d, C)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EvertallyTalentTransfer" end
    d.title = k.label(d, 17, C.bright); d.title:SetPoint("TOPLEFT", 16, -14)
    d.hint = k.label(d, 11, C.mist); d.hint:SetPoint("TOPLEFT", 16, -40); d.hint:SetPoint("RIGHT", d, "RIGHT", -16, 0); d.hint:SetWordWrap(true)
    d.well = CreateFrame("Frame", nil, d); A.NativeParchment(d.well, C); d.well:SetPoint("TOPLEFT", 12, -78); d.well:SetPoint("BOTTOMRIGHT", -12, 76)
    d.scroll = CreateFrame("ScrollFrame", nil, d.well, "UIPanelScrollFrameTemplate"); d.scroll:SetPoint("TOPLEFT", 8, -6); d.scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    d.box = CreateFrame("EditBox", nil, d.scroll); d.box:SetMultiLine(true); d.box:SetAutoFocus(false); d.box:SetMaxLetters(16384)
    d.box:SetFont(k.fontPath(), 12, ""); d.box:SetTextColor(C.text[1], C.text[2], C.text[3]); d.box:SetWidth(440); d.box:SetHeight(100)
    d.scroll:SetScrollChild(d.box)
    d.box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); d:Hide() end)
    d.error = k.label(d, 11, C.peach); d.error:SetPoint("BOTTOMLEFT", 14, 48); d.error:SetPoint("RIGHT", d, "RIGHT", -14, 0)
    d.close = k.Button(d, "talentClose", 96, "ghost", function() d.box:ClearFocus(); d:Hide() end); d.close:SetPoint("BOTTOMLEFT", 12, 10)
    d.export = k.Button(d, "ntExportCurrent", 180, "ghost", function() N.Transfer("export") end); d.export:SetPoint("LEFT", d.close, "RIGHT", 6, 0)
    d.apply = k.Button(d, "ntImportApply", 180, "primary", function()
        local trees = A.TalentTrees()
        local plan, why, name = A.ImportTalentProfile(d.box:GetText(), trees)
        if not plan then d.error:SetText(A.L(why or "talentProfileInvalid")); return end
        if #A.SavedTalentBuilds() >= 8 then d.error:SetText(A.L("talentProfileLimit")); return end
        name = A.UniqueTalentProfileName(name)
        A.SaveTalentBuild(plan, name)
        d.box:ClearFocus(); d:Hide()
        local list = A.SavedTalentBuilds()
        for _, saved in ipairs(list) do if saved.name == name then N.Stage(saved) break end end
    end)
    d.apply:SetPoint("BOTTOMRIGHT", -12, 10)
    N.dialog = d
    return d
end
--- `mode` "export" fills the box with the current talents' code; "import" waits for one.
function N.Transfer(mode)
    local d = dialog(); if not d then return end
    d.error:SetText("")
    if mode == "export" then
        local plan, trees = N.CurrentPlan()
        local code, why
        if plan then code, why = A.ExportTalentProfile(plan, trees, A.L("talentNameDefault")) end
        d.title:SetText(A.L("talentExportTitle")); d.hint:SetText(A.L("talentExportHint"))
        d.box:SetText(code or ""); if not code then d.error:SetText(A.L(why or "talentNoApi")) end
        d:Show(); d.box:SetFocus(); d.box:HighlightText()
    else
        d.title:SetText(A.L("talentImportTitle")); d.hint:SetText(A.L("talentImportHint"))
        d.box:SetText(""); d:Show(); d.box:SetFocus()
    end
    d.mode = mode
end

-- ---------------------------------------------------------------- the buttons in the talent window
function N.Attach()
    local frame = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if N.profiles or not frame then return false end
    local profiles = CreateFrame("Button", "EvertallyTalentProfilesButton", frame, "UIPanelButtonTemplate")
    profiles:SetSize(110, 22); profiles:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 10)
    profiles:SetText(A.L("ntProfiles"))
    profiles:SetScript("OnClick", function(self) N.ShowMenu(self) end)
    local transfer = CreateFrame("Button", "EvertallyTalentTransferButton", frame, "UIPanelButtonTemplate")
    transfer:SetSize(130, 22); transfer:SetPoint("LEFT", profiles, "RIGHT", 6, 0)
    transfer:SetText(A.L("ntTransfer"))
    transfer:SetScript("OnClick", function() N.Transfer("import") end)
    frame:HookScript("OnHide", function() if N.menu then N.menu:Hide() end end)
    N.profiles, N.transfer = profiles, transfer
    return true
end

A.On("ADDON_LOADED", function() if not N.profiles then pcall(N.Attach) end end)
A.On("PLAYER_LOGIN", function() pcall(N.Attach) end)
