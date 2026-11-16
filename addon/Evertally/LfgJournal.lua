local _, A = ...
-- A "Dungeon Journal" category in the game's Looking For Group window (LFGListingFrame.CategoryView, Forever's vanilla-style
-- group finder): one more button of the window's own category template under its categories, opening Evertally's Dungeon
-- Journal. The window's own buttons and their list are only read, never changed.
local L = {}
A.LfgJournal = L

local words = {
    en = {lfgJournal = "Dungeon Journal", lfgJournalTip = "Bosses, loot, quests and a guide for every dungeon (Evertally)."},
    cs = {lfgJournal = "Dungeon Journal", lfgJournalTip = "Bossové, loot, questy a návod ke každému dungeonu (Evertally)."},
}
for lang, entries in pairs(words) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

--- Puts our button under the last category the window shows.
function L.Place()
    local view = L.view
    if not view or not L.button then return end
    local last
    for _, b in ipairs(type(view.CategoryButtons) == "table" and view.CategoryButtons or {}) do
        if b.IsShown and b:IsShown() then last = b end
    end
    L.button:ClearAllPoints()
    if last then L.button:SetPoint("TOP", last, "BOTTOM", 0, -8) else L.button:SetPoint("TOP", view, "TOP", 0, -10) end
    L.button:SetText(A.L("lfgJournal"))
    L.button:Show()
end

function L.Open()
    if A.OpenUI then A.OpenUI() end
    if A.ShowView then A.ShowView("dungeons") end
end

function L.Attach()
    local view = LFGListingFrame and LFGListingFrame.CategoryView
    if L.button or not view then return false end
    L.view = view
    local ok, b = pcall(CreateFrame, "Button", "EvertallyLfgJournalCategory", view, "LFGListingCategoryTemplate")
    if not ok or not b then return false end
    if type(b.Icon) == "table" and b.Icon.SetAtlas then b.Icon:SetAtlas("groupfinder-button-dungeons") end
    -- our own click: the template's would pick a category of the group finder
    b:SetScript("OnClick", function() L.Open() end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(A.L("lfgJournal")); GameTooltip:AddLine(A.L("lfgJournalTip"), 0.85, 0.85, 0.85, true); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    L.button = b
    view:HookScript("OnShow", L.Place)
    if type(LFGListingCategorySelection_UpdateCategoryButtons) == "function" and type(hooksecurefunc) == "function" then
        hooksecurefunc("LFGListingCategorySelection_UpdateCategoryButtons", L.Place)
    end
    L.Place()
    return true
end

A.On("ADDON_LOADED", function() if not L.button then pcall(L.Attach) end end)
A.On("PLAYER_LOGIN", function() pcall(L.Attach) end)
