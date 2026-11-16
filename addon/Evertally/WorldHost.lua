local _, A = ...
-- The "Map" page of the window. Its code (the map made of the game's own art, the database search, the journey planner) lives in
-- Evertally_Map, which loads only after "Map and minimap" is switched on in Settings; this page asks for it on first use, and
-- offers the switch when it is still off. If anything in there fails the rest of the window keeps working.
local text = {
    en = {
        world = "Map & routes", sub_world = "What Evertally adds to OpenMap's map (gathering, trainers and merchants, instances), and the way to a place. Searching quests, NPCs and items is in the Database.",
        recipes = "Recipes", sub_recipes = "Every profession recipe: what it makes, the skill it turns orange, yellow, green and grey at, and its reagents.",
        database = "Database", sub_database = "Every quest, NPC, item and object the game knows, from QuestieDB: where they are, who gives and ends a quest, who drops or sells an item.",
        dungeons = "Dungeon Journal", sub_dungeons = "Dungeons and raids: their bosses and loot and the quests of each, from Evertally's own data.",
        guideMissing = "The guide could not be loaded (%s). Is the Evertally_Map add-on enabled?",
        dbUnavailable = "Not in the database", dbUnavailableSub = "QuestieDB is not installed, or this record has no entry there.", openDatabase = "Open in the database",
        worldEnable = "Turn on map and minimap", worldNeedMap = "This page uses the map add-on, the same switch as \"Map and minimap\" in Settings. It stays off until you turn it on.",
    },
    cs = {
        world = "Mapa a cesty", sub_world = "Co Evertally přidává do mapy OpenMap (sbírání, trenéři a obchodníci, instance) a cesta na místo. Hledání questů, NPC a itemů je v Databázi.",
        recipes = "Recepty", sub_recipes = "Každý recept profesí: co vyrobí, při jaké dovednosti je oranžový, žlutý, zelený a šedý, a jeho suroviny.",
        database = "Databáze", sub_database = "Každý quest, NPC, item a objekt, které hra zná, z QuestieDB: kde jsou, kdo quest dává a kdo ho přijímá, kdo item dropí nebo prodává.",
        dungeons = "Dungeon Journal", sub_dungeons = "Dungeony a raidy: jejich bossové a loot a questy každého, z vlastních dat Evertally.",
        guideMissing = "Průvodce se nepodařilo načíst (%s). Je zapnutý addon Evertally_Map?",
        dbUnavailable = "V databázi není", dbUnavailableSub = "QuestieDB není nainstalovaná, nebo tenhle záznam tam nemá položku.", openDatabase = "Otevřít v databázi",
        worldEnable = "Zapnout mapu a minimapu", worldNeedMap = "Tahle stránka používá addon mapy, stejný přepínač jako \"Mapa a minimapa\" v Nastavení. Zůstane vypnutý, dokud ho nezapneš.",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

--- What the database knows about an entry (kind "quest", "npc", "item" or "object") as rows for a details window: {title, sub}. Loads the guide
--- when it has to; when that fails or the entry is unknown, one row says so.
function A.DatabaseRows(kind, id)
    local ok, loaded = pcall(A.LoadGuide)
    if ok and loaded and A.map and A.map.DatabaseRows then
        local good, rows = pcall(A.map.DatabaseRows, kind, id)
        if good and type(rows) == "table" and #rows > 0 then return rows end
    end
    return {{title = A.L("dbUnavailable"), sub = A.L("dbUnavailableSub")}}
end
--- Opens the database page on one entry.
function A.OpenDatabaseEntry(kind, id)
    local ok, loaded = pcall(A.LoadGuide)
    if not (ok and loaded and A.map and A.map.OpenDatabaseEntry) then return false end
    return pcall(A.map.OpenDatabaseEntry, kind, id)
end

--- A page of the guide: its body is built by the map add-on (loaded here without "Map and minimap" and without OpenMap) on first use.
local function hosted(page, kit, key, bodyName, build, refresh)
    kit.PageHeader(page, key)
    page.prompt = kit.label(page, 12, kit.C.peach); page.prompt:SetPoint("TOPLEFT", 0, -64); page.prompt:SetWidth(560)
    page.Refresh = function()
        local ok, why = A.LoadGuide()
        local ready = ok and A.map and A.map[build] and true or false
        page.prompt:SetShown(not ready)
        if page.body then page.body:SetShown(ready) end
        if not ready then page.prompt:SetText(string.format(A.L("guideMissing"), tostring(why or "?"))); return end
        if not page.body then
            page.body = CreateFrame("Frame", nil, page)
            page.body:SetPoint("TOPLEFT", 0, -56); page.body:SetPoint("BOTTOMRIGHT")
            local built = pcall(A.map[build], page.body, kit)
            if not built then A.errors[key .. "_page"] = (A.errors[key .. "_page"] or 0) + 1 end
            A[bodyName] = page.body
        end
        pcall(A.map[refresh], page.body)
    end
end
function A.BuildDatabasePage(page, kit) hosted(page, kit, "database", "databaseBody", "BuildDatabase", "RefreshDatabase") end
function A.BuildRecipesPage(page, kit) hosted(page, kit, "recipes", "recipesBody", "BuildRecipes", "RefreshRecipes") end
function A.BuildDungeonsPage(page, kit) hosted(page, kit, "dungeons", "dungeonsBody", "BuildDungeons", "RefreshDungeons") end

function A.BuildWorldPage(page, kit)
    kit.PageHeader(page, "world")
    page.prompt = kit.label(page, 12, kit.C.mist); page.prompt:SetPoint("TOPLEFT", 0, -64); page.prompt:SetWidth(560)
    page.enable = kit.Button(page, "worldEnable", 240, "primary", function() A.SetMapPins(true); A.RefreshUI() end)
    page.enable:SetPoint("TOPLEFT", 0, -112)
    page.Refresh = function()
        local s = A.db and A.db.settings
        local loaded = s and s.mapPins == true and A.LoadMap()
        local ready = loaded and A.map and A.map.BuildWorld and true or false
        page.prompt:SetShown(not ready); page.enable:SetShown(not ready)
        if page.body then page.body:SetShown(ready) end
        if not ready then
            page.prompt:SetText(A.L("worldNeedMap")); page.enable.text:SetText(A.L("worldEnable"))
            return
        end
        if not page.body then
            page.body = CreateFrame("Frame", nil, page)
            page.body:SetPoint("TOPLEFT", 0, -56); page.body:SetPoint("BOTTOMRIGHT")
            local built = pcall(A.map.BuildWorld, page.body, kit)
            if not built then A.errors.world_page = (A.errors.world_page or 0) + 1 end
            A.worldBody = page.body
        end
        pcall(A.map.RefreshWorld, page.body)
    end
end
