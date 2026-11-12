local _, M = ...
local A = _G.Evertally
-- The Recipes page: every profession recipe Forever has (2,339, from the website's database), by profession, with what it makes, the skill it turns orange,
-- yellow, green and grey at, and its reagents as rows with the item's icon that open the item in the database. The list is data shipped with this add-on
-- (GuideData.lua: ids, numbers and names); icons and tooltips are the game's own.
local ROW_H, ROWS_MAX = 30, 18
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

local function detailOf(rp, recipe)
    local d = rp.detail
    local ink = rp.kit.ParchmentText
    local C = {text=ink.ink,mist=ink.mutedInk}
    d.SetTheme("quest");d.Reset("recipe:"..recipe.id)
    d.Text(A.Plain(recipe.name), C.text, 16)
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
            row.bg:SetAlpha(recipe == rp.selected and 0.16 or 0.05)
        end
    end
end

local function choose(rp, recipe)
    rp.selected = recipe
    if recipe then detailOf(rp, recipe) else rp.detail.Reset(); rp.detail.Text(A.L("recipesNone"), rp.kit.C.mist); rp.detail.Done() end
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
    rp.box = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
    rp.box:SetSize(240, 26); rp.box:SetPoint("TOPLEFT", 6, -4); rp.box:SetAutoFocus(false); rp.box:SetMaxLetters(60); rp.box:SetFont(kit.fontPath(), 12, "")
    rp.box:SetScript("OnTextChanged", function(self) rp.query = self:GetText() or ""; filter(rp) end)
    rp.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    rp.count = kit.label(body, 11, C.mist); rp.count:SetPoint("LEFT", rp.box, "RIGHT", 12, 0)
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
    local edge = {C.gold[1] * 0.78, C.gold[2] * 0.66, C.gold[3] * 0.5, 0.55}
    rp.list = CreateFrame("Frame", nil, body); rp.list:SetPoint("TOPLEFT", 0, -44); rp.list:SetPoint("BOTTOMLEFT", 0, 0); rp.list:SetWidth(270)
    rp.listBg = CreateFrame("Frame", nil, body); rp.listBg:SetFrameLevel(math.max(0, (rp.list:GetFrameLevel() or 1) - 1))
    rp.listBg:SetPoint("TOPLEFT", rp.list, "TOPLEFT", -3, 3); rp.listBg:SetPoint("BOTTOMRIGHT", rp.list, "BOTTOMRIGHT", 3, -3); kit.fill(rp.listBg, C.well, 0.6); kit.outline(rp.listBg, edge)
    rp.list:EnableMouse(true); if rp.list.EnableMouseWheel then rp.list:EnableMouseWheel(true) end
    rp.list:SetScript("OnMouseWheel", function(_, delta)
        local step = math.max(3, math.floor(#rp.results / 100))
        rp.offset = math.max(0, math.min(math.max(0, #rp.results - rp.visibleRows), rp.offset - delta * step)); refreshRows(rp)
    end)
    for i = 1, ROWS_MAX do
        local row = CreateFrame("Button", nil, rp.list); row:SetHeight(ROW_H - 2)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row.bg = kit.fill(row, {1, 1, 1}, 1); row.bg:SetAlpha(0.05)
        local hover = row:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(row); kit.paint(hover, {1, 1, 1}, 0.07)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(22, 22); row.icon:SetPoint("LEFT", 5, 0); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.badge = kit.label(row, 10, SKILL_COLOR and {1, 0.5, 0.25}); row.badge:SetPoint("RIGHT", -8, 0); row.badge:SetJustifyH("RIGHT")
        row.name = kit.label(row, 12, C.text); row.name:SetPoint("LEFT", 32, 0); row.name:SetPoint("RIGHT", row.badge, "LEFT", -4, 0); row.name:SetWordWrap(false); row.name:SetJustifyH("LEFT")
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
        rp.list:SetWidth(math.max(210, math.min(300, width * 0.38)))
        rp.visibleRows = math.max(3, math.min(ROWS_MAX, math.floor((height - 44) / ROW_H)))
        rp.detail.SetWidth(width - rp.list:GetWidth() - 12 - 40)
        refreshRows(rp)
    end
    body:SetScript("OnSizeChanged", layout)
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
