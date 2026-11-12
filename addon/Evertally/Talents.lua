local _, A = ...
-- The Talents page: your talent trees as the game has them, inside Evertally: each tree with its icon, the points spent in it, and every talent as an
-- icon in its place (tier by column) with the rank you have; the ones you have none of are dimmed, and the game's own tooltip shows on the mouse.
-- It reads the game's talent functions (GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo); when this client does not have them the page
-- says so instead of showing an empty frame.
local MAX_PER_TREE, GAP = 60, 6
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local text = {
    en = {talents = "Talents", sub_talents = "Your talent trees as the game has them: the points in each tree and every talent in its place.", talentsPoints = "%d points",
        talentsSpent = "Spent: %s", talentsFree = "Unspent: %d", talentsNone = "This client has no talent functions the page can read.", talentsNoTrees = "No talent trees are available for this character yet.",
        talentsRank = "%d/%d"},
    cs = {talents = "Talenty", sub_talents = "Tvoje talentové stromy tak, jak je má hra: body v každém stromě a každý talent na svém místě.", talentsPoints = "Bodů: %d",
        talentsSpent = "Utraceno: %s", talentsFree = "Neutraceno: %d", talentsNone = "Tenhle klient nemá talentové funkce, které by stránka uměla číst.", talentsNoTrees = "Pro tuhle postavu zatím nejsou talentové stromy.",
        talentsRank = "%d/%d"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local function have() return type(GetNumTalentTabs) == "function" and type(GetTalentTabInfo) == "function" and type(GetNumTalents) == "function" and type(GetTalentInfo) == "function" end

--- The player's talent trees: [{name, icon, spent, talents = [{index, name, icon, tier, column, rank, max}]}]. nil when the client has no such functions.
function A.TalentTrees()
    if not have() then return nil end
    local trees = {}
    local tabs = A.Number(A.Call(GetNumTalentTabs), 0, 10) or 0
    for tab = 1, tabs do
        local ok, name, icon, spent = pcall(GetTalentTabInfo, tab)
        if ok and name then
            local tree = {tab = tab, name = A.Plain(name), icon = icon or QUESTION, spent = tonumber(spent) or 0, talents = {}}
            local count = A.Number(A.Call(GetNumTalents, tab), 0, MAX_PER_TREE) or 0
            for index = 1, count do
                local good, tname, ticon, tier, column, rank, max = pcall(GetTalentInfo, tab, index)
                if good and tname then
                    tree.talents[#tree.talents + 1] = {index = index, name = A.Plain(tname), icon = ticon or QUESTION, tier = tonumber(tier) or 1, column = tonumber(column) or 1,
                        rank = tonumber(rank) or 0, max = tonumber(max) or 1}
                end
            end
            trees[#trees + 1] = tree
        end
    end
    return trees
end

local function paint(page, kit)
    local trees = A.TalentTrees()
    local t = page.talents
    for _, column in ipairs(t.columns) do column:Hide() end
    for _, button in ipairs(t.buttons) do button:Hide() end
    if trees == nil then t.note:SetText(A.L("talentsNone")); t.summary:SetText(""); return end
    if #trees == 0 then t.note:SetText(A.L("talentsNoTrees")); t.summary:SetText(""); return end
    t.note:SetText("")
    local spent = {}
    for i, tree in ipairs(trees) do spent[i] = tostring(tree.spent) end
    local free = type(UnitCharacterPoints) == "function" and A.Number(A.Call(UnitCharacterPoints, "player"), 0, 100) or nil
    t.summary:SetText(string.format(A.L("talentsSpent"), table.concat(spent, " / ")) .. (free and free > 0 and ("   " .. string.format(A.L("talentsFree"), free)) or ""))
    local used = 0
    local width = page:GetWidth() or 640
    local per = #trees
    local colW = math.floor((width - 24 - (per - 1) * 10) / math.max(1, per))
    for i, tree in ipairs(trees) do
        local column = t.columns[i]
        if not column then break end
        column:ClearAllPoints(); column:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * (colW + 10), -80); column:SetSize(colW, math.max(200, (page:GetHeight() or 400) - 84))
        column:Show()
        column.icon:SetTexture(tree.icon); column.name:SetText(tree.name); column.points:SetText(string.format(A.L("talentsPoints"), tree.spent))
        local size = math.max(22, math.min(40, math.floor((colW - 24 - 3 * GAP) / 4)))
        for _, talent in ipairs(tree.talents) do
            used = used + 1
            local button = t.buttons[used]
            if not button then
                button = CreateFrame("Button", nil, page)
                button.border = button:CreateTexture(nil, "BACKGROUND")
                button.icon = button:CreateTexture(nil, "ARTWORK"); button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                button.rank = kit.label(button, 11, {1, 1, 1}); button.rank:SetJustifyH("RIGHT")
                button:SetScript("OnEnter", function(self)
                    if not GameTooltip then return end
                    pcall(function()
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        if GameTooltip.SetTalent and self.tab then GameTooltip:SetTalent(self.tab, self.index) else GameTooltip:SetText(self.talentName or "?") end
                        GameTooltip:Show()
                    end)
                end)
                button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                t.buttons[used] = button
            end
            button.tab, button.index, button.talentName = tree.tab, talent.index, talent.name
            button:ClearAllPoints(); button:SetSize(size, size)
            button:SetPoint("TOPLEFT", column, "TOPLEFT", 12 + (talent.column - 1) * (size + GAP), -(54 + (talent.tier - 1) * (size + GAP)))
            button.border:ClearAllPoints(); button.border:SetPoint("TOPLEFT", -2, 2); button.border:SetPoint("BOTTOMRIGHT", 2, -2)
            button.icon:ClearAllPoints(); button.icon:SetAllPoints(button); button.icon:SetTexture(talent.icon)
            button.rank:ClearAllPoints(); button.rank:SetPoint("BOTTOMRIGHT", 1, -1)
            local learned = talent.rank > 0
            local full = talent.rank >= talent.max
            button.icon:SetVertexColor(learned and 1 or 0.38, learned and 1 or 0.38, learned and 1 or 0.38)
            local c = full and kit.C.gold or learned and kit.C.green or kit.C.off
            kit.paint(button.border, c, 1)
            button.rank:SetText(learned and string.format(A.L("talentsRank"), talent.rank, talent.max) or "")
            button:Show()
        end
    end
end

function A.BuildTalentsPage(page, kit)
    local C = kit.C
    kit.PageHeader(page, "talents")
    local t = {columns = {}, buttons = {}}
    page.talents = t
    t.summary = kit.label(page, 12, C.mist); t.summary:SetPoint("TOPLEFT", 0, -52)
    t.note = kit.label(page, 12, C.peach); t.note:SetPoint("TOPLEFT", 0, -80); t.note:SetPoint("TOPRIGHT", 0, -80)
    local edge = {C.gold[1] * 0.78, C.gold[2] * 0.66, C.gold[3] * 0.5, 0.55}
    for i = 1, 3 do
        local column = CreateFrame("Frame", nil, page)
        kit.fill(column, C.well, 0.6); kit.outline(column, edge)
        column.icon = column:CreateTexture(nil, "ARTWORK"); column.icon:SetSize(32, 32); column.icon:SetPoint("TOPLEFT", 12, -10); column.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        column.name = kit.label(column, 14, C.gold); column.name:SetPoint("TOPLEFT", column.icon, "TOPRIGHT", 8, -2)
        column.points = kit.label(column, 11, C.mist); column.points:SetPoint("TOPLEFT", column.icon, "BOTTOMRIGHT", 8, 14)
        column:Hide()
        t.columns[i] = column
    end
    page:SetScript("OnSizeChanged", function() if page:IsShown() then paint(page, kit) end end)
    function page.Refresh() paint(page, kit) end
end
