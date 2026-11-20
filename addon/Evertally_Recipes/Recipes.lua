local A = _G.Evertally
local M = A.map -- (Evertally_Recipes: a module of Evertally_Map's pages since 2026-11-20)
-- The Recipes page: every profession recipe Forever has (2,339, from the website's database), by profession, with what it makes, the skill it turns orange,
-- yellow, green and grey at, and its reagents as rows with the item's icon that open the item in the database. The list is data shipped with this add-on
-- (GuideData.lua: ids, numbers and names); icons and tooltips are the game's own.
local ROW_H, ROWS_MAX = 40, 18
local SKILL_COLOR = {"|cffff8040", "|cffffff00", "|cff40c040", "|cff9a9a9a"}
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local PROFESSION_ICON = {
    [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", [164] = "Interface\\Icons\\Trade_BlackSmithing", [165] = "Interface\\Icons\\INV_Misc_ArmorKit_17",
    [171] = "Interface\\Icons\\Trade_Alchemy", [185] = "Interface\\Icons\\INV_Misc_Food_15", [197] = "Interface\\Icons\\Trade_Tailoring",
    [202] = "Interface\\Icons\\Trade_Engineering", [333] = "Interface\\Icons\\Trade_Engraving", [186] = "Interface\\Icons\\Trade_Mining",
    [182] = "Interface\\Icons\\Trade_Herbalism", [356] = "Interface\\Icons\\Trade_Fishing", [393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
}
local ORDER = {171, 164, 165, 197, 202, 333, 185, 129, 186, 182, 393, 356}

local text = {
    en = {recipesSearch = "Search recipes", recipesAll = "All", recipesCount = "%d recipes", recipesNone = "Nothing found.", recipesCreates = "Makes", recipesSkill = "Skill",
        recipesReagents = "Reagents", recipesLearn = "To learn it you need %d skill", recipesOrange = "orange", recipesYellow = "yellow", recipesGreen = "green", recipesGrey = "grey",
        recipesNoOut = "This recipe makes no item (an effect, an enchant or a buff).", recipesProfession = "Profession", recipesNoData = "The recipe data is missing from this install."},
    cs = {recipesSearch = "Hledat recepty", recipesAll = "Vše", recipesCount = "Receptů: %d", recipesNone = "Nic nenalezeno.", recipesCreates = "Vyrobí", recipesSkill = "Dovednost",
        recipesReagents = "Suroviny", recipesLearn = "Na naučení potřebuješ dovednost %d", recipesOrange = "oranžová", recipesYellow = "žlutá", recipesGreen = "zelená", recipesGrey = "šedá",
        recipesNoOut = "Tenhle recept nevyrábí předmět (efekt, očarování nebo buff).", recipesProfession = "Profese", recipesNoData = "V téhle instalaci chybí data receptů."},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

-- In the hub: the hub's details pane (HubKit.lua), as the Database draws an entry: the profession's icon and the recipe's
-- name, the profession, the skill colours and what it takes to learn as facts, then what it makes and its reagents as rows
-- with the item's icon that open the item in the database.
local function hubDetailOf(rp, recipe)
    local blocks = {}
    local function item(id, badge)
        local icon = M.ItemLook(id)
        return {text = M.ItemName(id) .. (badge and ("  " .. badge) or ""), icon = icon, onClick = function() if A.OpenDatabaseEntry then A.OpenDatabaseEntry("item", id) end end}
    end
    if recipe.out then blocks[#blocks + 1] = {head = true, text = A.L("recipesCreates")}; blocks[#blocks + 1] = item(recipe.out)
    else blocks[#blocks + 1] = {text = A.L("recipesNoOut"), muted = true} end
    local reagents = recipe.reagents or {}
    if #reagents > 0 then
        blocks[#blocks + 1] = {head = true, text = A.L("recipesReagents")}
        for _, reagent in ipairs(reagents) do blocks[#blocks + 1] = item(reagent[1], "x" .. tostring(reagent[2])) end
    end
    local skill = recipe.skill or {}
    local facts = {{A.L("recipesProfession"), M.recipeLines and M.recipeLines[recipe.line] or ""}}
    if #skill >= 4 then
        facts[#facts + 1] = {A.L("recipesSkill"), SKILL_COLOR[1] .. skill[1] .. "|r  " .. SKILL_COLOR[2] .. skill[2] .. "|r  " .. SKILL_COLOR[3] .. skill[3] .. "|r  " .. SKILL_COLOR[4] .. skill[4] .. "|r"}
    end
    if recipe.req then facts[#facts + 1] = {"", string.format(A.L("recipesLearn"), recipe.req)} end
    rp.hubDetails.Set({title = A.Plain(recipe.name), sub = M.recipeLines and M.recipeLines[recipe.line] or "", icon = PROFESSION_ICON[recipe.line] or QUESTION,
        facts = facts, blocks = blocks})
end

local function detailOf(rp, recipe)
    if rp.hubDetails then return hubDetailOf(rp, recipe) end
    local d = rp.detail
    local ink = rp.kit.ParchmentText
    local C = {text=ink.ink,mist=ink.mutedInk}
    d.SetTheme("quest");d.Reset("recipe:"..recipe.id)
    d.Text(A.Plain(recipe.name), ink.heading, 20)
    d.Text(M.recipeLines and M.recipeLines[recipe.line] or "", C.mist, 11)
    if recipe.out then
        d.Head(A.L("recipesCreates"))
        local icon, quality = M.ItemLook(recipe.out)
        d.Link({icon = icon, title = M.ItemName(recipe.out), quality = quality, itemId = recipe.out,
            onClick = function() if A.OpenDatabaseEntry then A.OpenDatabaseEntry("item", recipe.out) end end})
    else
        d.Text(A.L("recipesNoOut"), C.mist)
    end
    local skill = recipe.skill or {}
    if #skill >= 4 then
        d.Head(A.L("recipesSkill"))
        d.Text(SKILL_COLOR[1] .. skill[1] .. "|r " .. A.L("recipesOrange") .. "   " .. SKILL_COLOR[2] .. skill[2] .. "|r " .. A.L("recipesYellow") .. "   "
            .. SKILL_COLOR[3] .. skill[3] .. "|r " .. A.L("recipesGreen") .. "   " .. SKILL_COLOR[4] .. skill[4] .. "|r " .. A.L("recipesGrey"), C.text)
    end
    if recipe.req then d.Text(string.format(A.L("recipesLearn"), recipe.req), C.mist, 11) end
    local reagents = recipe.reagents or {}
    if #reagents > 0 then
        d.Head(A.L("recipesReagents"))
        for _, reagent in ipairs(reagents) do
            local id, count = reagent[1], reagent[2]
            local icon, quality = M.ItemLook(id)
            d.Link({icon = icon, title = M.ItemName(id), quality = quality, itemId = id, badge = "x" .. tostring(count),
                onClick = function() if A.OpenDatabaseEntry then A.OpenDatabaseEntry("item", id) end end})
        end
    end
    d.Done()
end

local function refreshRows(rp)
    for i, row in ipairs(rp.rows) do
        local recipe = rp.results[rp.offset + i]
        row.recipe = recipe
        row:SetShown(recipe ~= nil and i <= rp.visibleRows)
        if recipe then
            row.icon:SetTexture(PROFESSION_ICON[recipe.line] or QUESTION)
            row.name:SetText(A.Plain(recipe.name))
            row.badge:SetText(recipe.skill and recipe.skill[1] and tostring(recipe.skill[1]) or "")
            row.bg:SetAlpha(recipe == rp.selected and 0.18 or 0.025)
            row.accent:SetShown(recipe == rp.selected)
        end
    end
end

local function choose(rp, recipe)
    rp.selected = recipe
    if recipe then detailOf(rp, recipe)
    elseif rp.hubDetails then rp.hubDetails.Empty(A.L("recipes"), A.L("recipesNone"))
    else rp.detail.Reset(); rp.detail.Text(A.L("recipesNone"), rp.kit.C.mist); rp.detail.Done() end
    refreshRows(rp)
end

local function filter(rp)
    local query = (rp.query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    rp.results = {}
    for _, recipe in ipairs(M.recipes or {}) do
        if (not rp.line or recipe.line == rp.line) and (query == "" or recipe.name:lower():find(query, 1, true)) then rp.results[#rp.results + 1] = recipe end
    end
    table.sort(rp.results, function(a, b)
        local x, y = a.skill and a.skill[1] or 0, b.skill and b.skill[1] or 0
        if x ~= y then return x < y end
        return a.name < b.name
    end)
    rp.offset = 0
    rp.count:SetText(#rp.results > 0 and string.format(A.L("recipesCount"), #rp.results) or A.L("recipesNone"))
    for key, chip in pairs(rp.chips) do
        chip.SetLabel(key == 0 and A.L("recipesAll") or (M.recipeLines and M.recipeLines[key]) or tostring(key))
        chip.SetOn((key == 0 and not rp.line) or key == rp.line)
    end
    choose(rp, rp.results[1])
end

function M.BuildRecipes(body, kit)
    local C = kit.C
    local rp = {kit = kit, body = body, rows = {}, chips = {}, results = {}, offset = 0, visibleRows = 8, query = ""}
    body.recipes = rp
    M.recipePage = rp
    rp.box = kit.SearchBox(body, 240, function(value) rp.query = value or ""; filter(rp) end)
    rp.box:SetPoint("TOPLEFT", 0, -4); rp.box:SetMaxLetters(60); rp.box.hint:SetText(A.L("recipesSearch"))
    rp.count = kit.label(body, 11, C.mist); rp.count:SetPoint("TOPLEFT", 2, -37)
    -- A native profession menu leaves room for the recipe itself, even in a narrow window.
    rp.professionButton=kit.Button(body,"recipesAll",190,"ghost",function() rp.professionMenu:SetShown(not rp.professionMenu:IsShown()) end)
    rp.professionButton:SetPoint("TOPRIGHT",0,-2)
    rp.professionMenu=CreateFrame("Frame",nil,body);rp.professionMenu:SetSize(230,250);rp.professionMenu:SetPoint("TOPRIGHT",rp.professionButton,"BOTTOMRIGHT",0,-4)
    rp.professionMenu:SetFrameLevel((body:GetFrameLevel() or 1)+30);A.NativeFrame(rp.professionMenu,kit.C);rp.professionMenu:Hide()
    local menuScroll=kit.ScrollArea(rp.professionMenu,8);menuScroll:ClearAllPoints();menuScroll:SetPoint("TOPLEFT",8,-8);menuScroll:SetPoint("BOTTOMRIGHT",-10,8)
    menuScroll.child:SetHeight(13*30)
    local order = {0}
    for _, line in ipairs(ORDER) do order[#order + 1] = line end
    for i, key in ipairs(order) do
        local chip = kit.Chip(menuScroll.child, function()
            rp.line = key ~= 0 and key or nil;rp.professionMenu:Hide();filter(rp)
            rp.professionButton.text:SetText((M.recipeLines and M.recipeLines[rp.line]) or A.L("recipesAll"))
        end)
        chip:SetPoint("TOPLEFT",0,-(i-1)*30);chip:SetPoint("TOPRIGHT",0,-(i-1)*30)
        rp.chips[key] = chip
    end
    local edge = C.line or C.gold
    rp.list = CreateFrame("Frame", nil, body); rp.list:SetPoint("TOPLEFT", 0, -62); rp.list:SetPoint("BOTTOMLEFT", 0, 0); rp.list:SetWidth(270)
    rp.listBg = CreateFrame("Frame", nil, body); rp.listBg:SetFrameLevel(math.max(0, (rp.list:GetFrameLevel() or 1) - 1))
    rp.listBg:SetPoint("TOPLEFT", rp.list, "TOPLEFT", -3, 3); rp.listBg:SetPoint("BOTTOMRIGHT", rp.list, "BOTTOMRIGHT", 3, -3); kit.fill(rp.listBg, C.well, 1); kit.outline(rp.listBg, edge)
    rp.list:EnableMouse(true); if rp.list.EnableMouseWheel then rp.list:EnableMouseWheel(true) end
    rp.list:SetScript("OnMouseWheel", function(_, delta)
        local step = math.max(3, math.floor(#rp.results / 100))
        rp.offset = math.max(0, math.min(math.max(0, #rp.results - rp.visibleRows), rp.offset - delta * step)); refreshRows(rp)
    end)
    for i = 1, ROWS_MAX do
        local row = CreateFrame("Button", nil, rp.list); row:SetHeight(ROW_H - 2)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row.bg = kit.fill(row, C.gold, 1); row.bg:SetAlpha(0.025)
        row.accent = row:CreateTexture(nil, "OVERLAY"); row.accent:SetPoint("TOPLEFT"); row.accent:SetPoint("BOTTOMLEFT"); row.accent:SetWidth(2); kit.paint(row.accent, C.gold, 1); row.accent:Hide()
        local hover = row:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(row); kit.paint(hover, C.gold, 0.10)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(26, 26); row.icon:SetPoint("LEFT", 8, 0); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.badge = kit.label(row, 11, C.gold); row.badge:SetPoint("RIGHT", -8, 0); row.badge:SetJustifyH("RIGHT")
        row.name = kit.label(row, 13, C.text); row.name:SetPoint("LEFT", 42, 0); row.name:SetPoint("RIGHT", row.badge, "LEFT", -4, 0); row.name:SetWordWrap(false); row.name:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self) if self.recipe then choose(rp, self.recipe) end end)
        row:Hide()
        rp.rows[i] = row
    end
    rp.panel = CreateFrame("Frame", nil, body)
    rp.panel:SetPoint("TOPLEFT", rp.list, "TOPRIGHT", 12, 3); rp.panel:SetPoint("BOTTOMRIGHT", 0, -3)
    A.NativeParchment(rp.panel,C)
    rp.detail = M.GuideDetail(kit, body)
    rp.detail.scroll:SetPoint("TOPLEFT", rp.panel, "TOPLEFT", 10, -10); rp.detail.scroll:SetPoint("BOTTOMRIGHT", rp.panel, "BOTTOMRIGHT", -28, 10)
    rp.nodata = kit.label(body, 12, C.peach); rp.nodata:SetPoint("TOPLEFT", 0, -110); rp.nodata:Hide()
    local function layout()
        local width, height = body:GetWidth() or 640, body:GetHeight() or 420
        if rp.hubDetails then
            -- the list takes what the details pane leaves
            local listW = math.max(180, width - A.HubKit.DETAIL_W - 16)
            rp.list:SetWidth(listW); rp.box:SetWidth(math.max(140, listW - 210))
            rp.visibleRows = math.max(1, math.min(ROWS_MAX, math.floor((height - 62) / ROW_H)))
            refreshRows(rp)
            return
        end
        rp.box:SetWidth(math.max(160, math.min(300, width - 218)))
        rp.list:SetWidth(math.max(180, math.min(290, width * 0.34)))
        rp.visibleRows = math.max(1, math.min(ROWS_MAX, math.floor((height - 62) / ROW_H)))
        rp.detail.SetWidth(width - rp.list:GetWidth() - 12 - 40)
        refreshRows(rp)
    end
    body:SetScript("OnSizeChanged", layout)
    -- In the guide's hub (Evertally's page drawn there, HubKit.lua): the hub's search box and button, flat rows in the
    -- hub's type, no box around the list; the recipe in the reader as before.
    local page = body:GetParent()
    local g = rawget(_G, "EvertallyGuide")
    local W = type(g) == "table" and g.Widgets
    if page and page.hubMode and W and W.SearchBox and W.Button then
        local Theme = g.Theme
        local oldBox = rp.box
        oldBox:Hide()
        local box = W.SearchBox(body, A.L("recipesSearch"), function(value) rp.query = value or ""; filter(rp) end)
        box:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -2)
        if box.SetMaxLetters then box:SetMaxLetters(60) end
        box.hint = {SetText = function(_, value) if W.SetSearchPlaceholder and value then W.SetSearchPlaceholder(box, value) end end}
        rp.box = box
        local oldButton = rp.professionButton
        oldButton:Hide()
        local button = W.Button(body, A.L("recipesAll"), function() rp.professionMenu:SetShown(not rp.professionMenu:IsShown()) end, {height = 30, width = 200})
        button:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -2)
        button.text = {SetText = function(_, value) if W.SetButtonText then W.SetButtonText(button, value) end end}
        rp.professionButton = button
        rp.professionMenu:ClearAllPoints(); rp.professionMenu:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
        Theme.Font(rp.count, "small"); W.Color(rp.count, "textMuted")
        rp.count:ClearAllPoints(); rp.count:SetPoint("TOPLEFT", body, "TOPLEFT", 2, -40)
        rp.listBg:SetAlpha(0)
        -- the details: the hub's pane on the right (the reader and its scroll put away)
        if A.HubKit and A.HubKit.Details and A.HubKit.Guide() then
            rp.panel:Hide(); rp.detail.scroll:Hide(); rp.detail.surface:Hide()
            rp.hubDetails = A.HubKit.Details(body)
            -- the profession button over the list, not over the pane
            button:ClearAllPoints(); button:SetPoint("TOPRIGHT", rp.list, "TOPRIGHT", 0, 60)
            rp.professionMenu:ClearAllPoints(); rp.professionMenu:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
        end
        for _, row in ipairs(rp.rows) do
            Theme.Font(row.name, "body"); W.Color(row.name, "text")
            Theme.Font(row.badge, "small"); W.Color(row.badge, "accent")
        end
    end
    layout()
    return rp
end

function M.OpenRecipe(id)
    if A.ShowView then A.ShowView("recipes") end
    local rp=M.recipePage
    if not rp then return false end
    for _,recipe in ipairs(M.recipes or {}) do
        if recipe.id==id then
            rp.line=recipe.line;rp.query="";rp.box:SetText("");filter(rp)
            for i,entry in ipairs(rp.results) do if entry.id==id then rp.offset=math.max(0,i-1);break end end
            rp.professionButton.text:SetText(M.recipeLines[recipe.line] or A.L("recipesAll"));choose(rp,recipe);return true
        end
    end
    return false
end

function M.RefreshRecipes(body)
    local rp = body.recipes
    if not rp then return end
    if not M.recipes or #M.recipes == 0 then rp.nodata:SetText(A.L("recipesNoData")); rp.nodata:Show(); return end
    rp.nodata:Hide()
    rp.box:SetShown(true)
    if not rp.filled then rp.filled = true; filter(rp) else
        -- (a refresh of the window keeps the profession, the search and the recipe: only the words are written again)
        rp.count:SetText(#rp.results > 0 and string.format(A.L("recipesCount"), #rp.results) or A.L("recipesNone"))
        for key, chip in pairs(rp.chips) do chip.SetLabel(key == 0 and A.L("recipesAll") or (M.recipeLines and M.recipeLines[key]) or tostring(key)) end
    end
end
