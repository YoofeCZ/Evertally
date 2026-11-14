local _, A = ...
-- Evertally's own training model. The shipped catalog is data, never an external addon dependency.
local T = {revision = 1}
A.Training = T
local names, pending, modelCache = {}, {}, nil
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local function plain(v) return A.Plain(v) end
local function call(fn, ...) return A.Call(fn, ...) end
local function text(key) return A.L(key) end

local function identity()
    local _, class = call(UnitClass, "player")
    local _, _, race = call(UnitRace, "player")
    local c = A.Character and A.Character() or {}
    return class or "", race or c.raceId, call(UnitFactionGroup, "player") or "", call(UnitLevel, "player") or c.level or 1, c.id or "unknown"
end
function T.State()
    if not A.db then return {petKnown = {}, prices = {}, tomeKnown = {}} end
    if type(A.db.training) ~= "table" then A.db.training = {characters = {}} end
    local data = A.db.training
    if type(data.characters) ~= "table" then data.characters = {} end
    local _, _, _, _, id = identity()
    if type(data.characters[id]) ~= "table" then data.characters[id] = {petKnown = {}, tomeKnown = {}, prices = {}} end
    local state = data.characters[id]
    for _, key in ipairs({"petKnown", "tomeKnown", "prices"}) do if type(state[key]) ~= "table" then state[key] = {} end end
    return state
end
function T.Invalidate(notify)
    T.revision = T.revision + 1; modelCache = nil
    if notify and A.Changed then A.Changed() end
end

--- Returns true/false only when a supported spellbook API actually answered. Missing APIs are unknown.
function T.Known(id, pet)
    id = A.Number(id, 1)
    if not id then return nil end
    local banks = Enum and Enum.SpellBookSpellBank
    local bank = banks and (pet and banks.Pet or banks.Player)
    if C_SpellBook and bank ~= nil then
        local known = call(C_SpellBook.IsSpellKnown, id, bank)
        if type(known) == "boolean" then return known end
        known = call(C_SpellBook.IsSpellInSpellBook, id, bank, false)
        if type(known) == "boolean" then return known end
    end
    local known = call(IsSpellKnown, id, pet == true)
    if type(known) == "boolean" then return known end
    if not pet then
        known = call(IsPlayerSpell, id)
        if type(known) == "boolean" then return known end
    end
    return nil
end

function T.SpellInfo(id, itemId)
    local key = itemId and ("i:" .. itemId) or id
    if names[key] then return names[key] end
    local info = not itemId and C_Spell and call(C_Spell.GetSpellInfo, id)
    local name, rank, icon
    if type(info) == "table" then
        name, icon = A.Text(info.name, 180), info.iconID or info.originalIconID
        rank = C_Spell and A.Text(call(C_Spell.GetSpellSubtext, id), 60)
    elseif itemId then
        name = A.Text(call(GetItemInfo, itemId), 180)
        icon = call(GetItemIcon, itemId) or (C_Item and call(C_Item.GetItemIconByID, itemId))
    else
        name, rank, icon = call(GetSpellInfo, id)
        name, rank = A.Text(name, 180), A.Text(rank, 60)
    end
    if not name and not itemId and C_Spell and not pending[id] then
        pending[id] = true; call(C_Spell.RequestLoadSpellData, id)
    end
    local result = {name = name or ((itemId and text("trainingItem") or text("trainingSpell")) .. " #" .. tostring(itemId or id)), rank = rank, icon = icon or QUESTION, loaded = name ~= nil}
    if name then names[key] = result end
    return result
end

function T.Matches(row, race, faction)
    if row.race and row.race ~= race then return false end
    if type(row.races) == "table" then
        local found = false; for _, id in ipairs(row.races) do if id == race then found = true end end
        if not found then return false end
    end
    if row.faction and row.faction ~= "Both" and row.faction ~= faction then return false end
    return true
end

local function modelRow(source, known, overridden, state, level)
    local row = {}; for k, v in pairs(source) do row[k] = v end
    local info = T.SpellInfo(row.taughtId or row.id, row.itemId)
    row.name, row.rank, row.icon, row.loaded = info.name, info.rank, info.icon, info.loaded
    local trained
    if row.pet then trained = state.petKnown[row.id]; if trained == nil and state.petScanned then trained = false end
    elseif row.tome then
        trained = state.tomeKnown[row.taughtId or row.id]
        local family = call(UnitCreatureFamily, "pet")
        if trained ~= true and family == row.family then trained = T.Known(row.taughtId, true) end
    else trained = known[row.id] end
    if trained == true or overridden[row.id] then row.status = "known"
    elseif level < (row.level or 1) then row.status = "later"
    elseif row.pet and trained == nil or row.tome and trained == nil then row.status = "pet_unknown"
    elseif trained == nil then row.status = "unknown"
    else
        row.status = "ready"
        for _, id in ipairs(row.requiredIds or {}) do
            local isKnown = known[id]
            if isKnown == nil then isKnown = T.Known(id, false); known[id] = isKnown end
            if not isKnown and not overridden[id] and not state.petKnown[id] then row.status = "requirements"; row.missingId = id; break end
        end
        if row.requiredTalentId and T.Known(row.requiredTalentId, false) ~= true then row.status = "requirements"; row.missingId = row.requiredTalentId end
    end
    local price = state.prices[row.id]
    row.price, row.priceSource = row.baseCost, "base"
    if type(price) == "table" and A.Number(price.cost, 0, 1000000000) then row.price, row.priceSource, row.priceAt = price.cost, "observed", price.at end
    return row
end

function T.Model()
    local class, race, faction, level, characterId = identity()
    local money = A.Number(call(GetMoney), 0)
    local key = table.concat({T.revision, class, race or 0, faction, level, characterId}, ":")
    if not modelCache or modelCache.key ~= key then
        local catalog = A.trainingData and A.trainingData.classes and A.trainingData.classes[class]
        local rows, known, overridden = {}, {}, {}
        local state = T.State()
        if catalog then
            for _, source in ipairs(catalog.spells or {}) do if not source.pet and not source.tome then known[source.id] = T.Known(source.id, false) end end
            for _, group in ipairs(catalog.overrides or {}) do
                local highest = 0
                for index, id in ipairs(group) do if known[id] == true or T.Known(id, false) == true then highest = index end end
                for index = 1, highest do overridden[group[index]] = true end
            end
            for _, source in ipairs(catalog.spells or {}) do
                if T.Matches(source, race, faction) then rows[#rows + 1] = modelRow(source, known, overridden, state, level) end
            end
            local quests = A.trainingData.questSpells and A.trainingData.questSpells[class] or {}
            for spellId, alternatives in pairs(quests) do
                for _, path in ipairs(alternatives) do
                    if T.Matches(path, race, faction) then
                        local info = T.SpellInfo(spellId)
                        rows[#rows + 1] = {id = "quest:" .. spellId, spellId = spellId, name = info.name, rank = info.rank, icon = info.icon,
                            level = path.level or 1, quests = path.quests, areas = path.areas or {path.area}, quest = true,
                            status = T.Known(spellId, false) == true and "known" or "quest"}
                        break
                    end
                end
            end
        end
        table.sort(rows, function(a, b)
            if a.level ~= b.level then return a.level < b.level end
            if a.name ~= b.name then return a.name < b.name end
            return tostring(a.id) < tostring(b.id)
        end)
        local count, total, base, observed, unknown = 0, 0, 0, 0, 0
        for _, row in ipairs(rows) do
            if row.status == "ready" then
                count = count + 1; total = total + (row.price or 0)
                if row.priceSource == "observed" then observed = observed + 1 else base = base + 1 end
            end
            if row.status == "unknown" or row.status == "pet_unknown" then unknown = unknown + 1 end
        end
        modelCache = {key = key, rows = rows, class = class, level = level, available = catalog ~= nil, readyCount = count,
            total = total, baseCount = base, observedCount = observed, unknownCount = unknown, petScanned = state.petScanned == true}
    end
    -- Money changes do not require rescanning the spellbook.
    modelCache.money = money; modelCache.affordable = money and money >= modelCache.total or false
    return modelCache
end

function T.Rows(mode, query, showKnown)
    local out = {}; query = type(query) == "string" and query:lower() or ""
    for _, row in ipairs(T.Model().rows) do
        local keep = mode == "all" or mode == "pet" and (row.pet or row.tome) or mode == "quest" and row.quest
            or mode == "ready" and row.status == "ready"
            or mode == "later" and not row.pet and not row.tome and not row.quest and (row.status == "later" or row.status == "requirements" or row.status == "unknown")
        if keep and (showKnown or row.status ~= "known") and (query == "" or (row.name .. " " .. tostring(row.id)):lower():find(query, 1, true)) then out[#out + 1] = row end
    end
    return out
end

function T.ObserveTrainer()
    local count = A.Number(call(GetNumTrainerServices), 0, 2000)
    if not count or count == 0 or not C_TooltipInfo or type(C_TooltipInfo.GetTrainerService) ~= "function" then return false end
    local state, changed = T.State(), false
    local petType = Enum and Enum.TrainerType and Enum.TrainerType.Pet
    local isPet = petType ~= nil and C_Trainer and call(C_Trainer.GetTrainerType) == petType
    for i = 1, count do
        local info = call(C_TooltipInfo.GetTrainerService, i)
        local id = type(info) == "table" and A.Number(info.id, 1)
        if id then
            if isPet then if state.petKnown[id] ~= true then state.petKnown[id] = true; changed = true end
            else
                local cost = A.Number(call(GetTrainerServiceCost, i), 0, 1000000000)
                if cost then state.prices[id] = {cost = cost, at = A.Now()}; changed = true end
            end
        end
    end
    if isPet then state.petScanned = true; changed = true end
    if changed then T.Invalidate(true) end
    return changed
end

function T.Trainers(kind)
    local class, _, faction = identity(); kind = kind or class
    local out = {}
    for _, spot in ipairs(A.trainingData and A.trainingData.trainers or {}) do
        if spot.kind == kind and (spot.faction == "Both" or spot.faction == faction) then out[#out + 1] = spot end
    end
    return out
end
function T.NearestTrainer(kind)
    if not A.map and A.LoadGuide then A.LoadGuide() end
    local map = A.map
    if not map or type(map.NearestLayerSpot) ~= "function" then return nil, "map_unavailable" end
    local spot = map.NearestLayerSpot(T.Trainers(kind))
    if not spot then return nil, "no_trainer_here" end
    return spot
end
function T.Navigate(kind)
    local spot, reason = T.NearestTrainer(kind)
    if not spot then return false, reason end
    if not A.NavigateToPoint then return false, "map_unavailable" end
    return A.NavigateToPoint(spot.name, spot.map, spot.x, spot.y, {view = "training", npcId = spot.npcId})
end

for _, event in ipairs({"SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD"}) do
    A.On(event, function() T.Invalidate(true) end)
end
A.On("SPELL_DATA_LOAD_RESULT", function(id)
    if pending[id] then pending[id] = nil; names[id] = nil; T.Invalidate(true) end
end)
A.On("GET_ITEM_INFO_RECEIVED", function(id) names["i:" .. tostring(id)] = nil; T.Invalidate(false) end)
A.On("UPDATE_FACTION", function() T.State().prices = {}; T.Invalidate(true) end)
A.On("TRAINER_SHOW", T.ObserveTrainer)
A.On("TRAINER_UPDATE", T.ObserveTrainer)
A.On("PLAYER_MONEY", function() if A.trainingPage and A.trainingPage.IsShown and A.trainingPage:IsShown() and A.RefreshUI then A.RefreshUI() end end)

local strings = {
    en = {training = "What to learn", sub_training = "Your class abilities, ranks, costs and trainer. Includes pet training and class quests.",
        trainingSpell = "Ability", trainingItem = "Grimoire", training_ready = "Ready now", training_later = "Upcoming", training_pet = "Pets", training_quest = "Class quests", training_all = "All",
        training_known = "Known", training_requirements = "Missing prerequisite", training_unknown = "Spellbook unavailable", training_pet_unknown = "Pet knowledge unverified",
        trainingShowKnown = "Show known", trainingHideKnown = "Hide known", trainingNavigate = "Nearest trainer", trainingBase = "Base price", trainingObserved = "Observed price",
        trainingPetHint = "Open Beast Training to verify learned hunter pet abilities. Warlock grimoires are checked against the active pet's spellbook.",
        trainingMissingData = "No training catalog is available for this class.", trainingEmpty = "No matching abilities.", trainingSummary = "%d abilities ready · %s total", trainingEnough = "You have enough money.", trainingNotEnough = "You do not have enough money.",
        trainingCostHint = "Base prices are before reputation discounts. Observed prices come from a trainer visit and can change.", trainingLevel = "Required level %d", trainingPrerequisite = "Prerequisite: %s", trainingQuestSource = "Learned through a class quest", trainingNoTrainer = "No matching friendly trainer on this continent.", trainingChoose = "Select an ability to see its requirements and source.", trainingOpenQuest = "Open quest #%d", trainingPetTrainer = "Pet trainer", trainingTomeVendor = "Grimoire vendor"},
    cs = {training = "Co se naučit", sub_training = "Schopnosti tvojí třídy, ranky, ceny a trenér. Včetně mazlíčků a class questů.",
        trainingSpell = "Schopnost", trainingItem = "Grimoár", training_ready = "Dostupné", training_later = "Následující", training_pet = "Mazlíčci", training_quest = "Class questy", training_all = "Vše",
        training_known = "Naučeno", training_requirements = "Chybí předpoklad", training_unknown = "Kniha kouzel není dostupná", training_pet_unknown = "Schopnosti mazlíčka nejsou ověřené",
        trainingShowKnown = "Ukázat naučené", trainingHideKnown = "Skrýt naučené", trainingNavigate = "Nejbližší trenér", trainingBase = "Základní cena", trainingObserved = "Pozorovaná cena",
        trainingPetHint = "Otevři Beast Training pro ověření naučených schopností lovcova mazlíčka. Grimoáry černokněžníka se ověřují podle knihy kouzel aktivního mazlíčka.",
        trainingMissingData = "Pro tuto třídu není dostupný katalog tréninku.", trainingEmpty = "Žádné odpovídající schopnosti.", trainingSummary = "Dostupných schopností: %d · celkem %s", trainingEnough = "Máš dost peněz.", trainingNotEnough = "Na všechno nemáš dost peněz.",
        trainingCostHint = "Základní ceny jsou před slevou za reputaci. Pozorované ceny pocházejí z návštěvy trenéra a mohou se změnit.", trainingLevel = "Požadovaná úroveň %d", trainingPrerequisite = "Předpoklad: %s", trainingQuestSource = "Naučíš se prostřednictvím class questu", trainingNoTrainer = "Na tomto kontinentu není známý vhodný přátelský trenér.", trainingChoose = "Vyber schopnost a uvidíš její předpoklady a zdroj.", trainingOpenQuest = "Otevřít quest #%d", trainingPetTrainer = "Trenér mazlíčků", trainingTomeVendor = "Prodejce grimoárů"},
}
for lang, values in pairs(strings) do for key, value in pairs(values) do A.locale[lang][key] = value end end
