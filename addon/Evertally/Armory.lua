local _, A = ...
-- The armory of the current character: gear, bags, stats, talents and professions in one table. The same table is
--  * exported (own_character scope) as an "armory.snapshot" so the owner sees it on the website,
--  * sent to another player, but only after that player answered a request in game (Social.lua),
--  * and, for a view somebody allowed, forwarded to the viewer's own account as "armory.view" (Social.lua).
-- Everything is read through A.Call / A.Number, so a missing or restricted API costs a field, never an error.
local KEYS = {"str", "agi", "sta", "int", "spi", "armor", "ap", "rap", "crit", "scrit", "dodge", "parry", "block", "hp", "mana",
    "holy", "fire", "nature", "frost", "shadow", "arcane"}
local STAT_LABEL = {en = {str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", armor = "Armor", ap = "Attack power", rap = "Ranged attack power",
    crit = "Melee crit %", scrit = "Spell crit %", dodge = "Dodge %", parry = "Parry %", block = "Block %", hp = "Health", mana = "Mana", holy = "Holy resistance", fire = "Fire resistance",
    nature = "Nature resistance", frost = "Frost resistance", shadow = "Shadow resistance", arcane = "Arcane resistance"},
    cs = {str = "Síla", agi = "Obratnost", sta = "Odolnost", int = "Inteligence", spi = "Duch", armor = "Brnění", ap = "Útočná síla", rap = "Útočná síla na dálku",
    crit = "Kritický zásah %", scrit = "Kritické kouzlo %", dodge = "Úhyb %", parry = "Odražení %", block = "Blok %", hp = "Zdraví", mana = "Mana", holy = "Odolnost Svatá", fire = "Odolnost Oheň",
    nature = "Odolnost Příroda", frost = "Odolnost Mráz", shadow = "Odolnost Stín", arcane = "Odolnost Tajná"}}
A.ArmoryStatKeys = KEYS
function A.ArmoryStatLabel(key) return (STAT_LABEL[A.db and A.db.settings.language == "cs" and "cs" or "en"] or STAT_LABEL.en)[key] or key end

local function num(v, max) return A.Number(v, 0, max or 1000000) end
local function rounded(v, max)
    v = num(v, max); if not v then return nil end
    return math.floor(v * 10 + 0.5) / 10
end
local function attackPower(fn)
    local base, plus, minus = A.Call(fn, "player")
    base, plus, minus = num(base), num(plus) or 0, A.Number(minus, -1000000, 1000000) or 0
    return base and math.max(0, base + plus + minus) or nil
end

--- {str=..., agi=..., ...} with whatever the client reports; absent values are left out.
function A.CollectStats()
    local out = {}
    for i, key in ipairs({"str", "agi", "sta", "int", "spi"}) do
        local _, effective = A.Call(UnitStat, "player", i)
        out[key] = num(effective)
    end
    local _, armor = A.Call(UnitArmor, "player"); out.armor = num(armor)
    out.ap = attackPower(UnitAttackPower); out.rap = attackPower(UnitRangedAttackPower)
    out.crit = rounded(A.Call(GetCritChance), 100)
    out.scrit = rounded(A.Call(GetSpellCritChance, 2), 100)
    out.dodge = rounded(A.Call(GetDodgeChance), 100); out.parry = rounded(A.Call(GetParryChance), 100); out.block = rounded(A.Call(GetBlockChance), 100)
    out.hp = num(A.Call(UnitHealthMax, "player"))
    out.mana = num(A.Call(UnitPowerMax, "player", 0))
    for i, key in ipairs({"holy", "fire", "nature", "frost", "shadow", "arcane"}) do
        local _, total = A.Call(UnitResistance, "player", i - 1)
        out[key] = num(total, 10000)
    end
    return out
end

--- Talent trees as {{name=, spent=, ranks={{id, rank, name}...}}...}: only the talents that have points.
function A.CollectTalents()
    local out = {}
    local trees = A.TalentTrees and A.TalentTrees() or nil
    for _, tree in ipairs(type(trees) == "table" and trees or {}) do
        if #out >= 4 then break end
        local entry = {name = A.SocialClean and A.SocialClean(tree.name, 40) or "", spent = num(tree.spent, 1000) or 0, ranks = {}}
        for _, talent in ipairs(tree.talents or {}) do
            local rank = num(talent.rank, 100)
            local id = num(talent.index, 100000000)
            -- {id, rank, name}: a plain list, so it survives the saved-variables file as a list
            if rank and rank > 0 and id and #entry.ranks < 80 then entry.ranks[#entry.ranks + 1] = {id, rank, A.SocialClean and A.SocialClean(talent.name, 40) or ""} end
        end
        if entry.spent == 0 then for _, r in ipairs(entry.ranks) do entry.spent = entry.spent + r[2] end end
        out[#out + 1] = entry
    end
    return out
end

--- Professions of this character as {{id, name, skill, max}...} (without the recipe lists; those go in the in-game view only).
function A.CollectProfessionLines()
    local out = {}
    local me = A.Character(); local mine = me and me.id
    if not A.ProfessionSummaries or not mine then return out end
    local ok, list = pcall(A.ProfessionSummaries)
    for _, entry in ipairs(ok and type(list) == "table" and list or {}) do
        local c, p = entry.character, entry.payload
        local id = type(p) == "table" and A.Number(p.professionId, 1, 1000000)
        if c and c.id == mine and id and #out < 12 then
            out[#out + 1] = {id = id, name = A.SocialClean and A.SocialClean(p.name, 40) or "", skill = A.Number(p.skill, 0, 10000), max = A.Number(p.maxSkill, 0, 10000)}
        end
    end
    return out
end

--- Who this is, as the viewer should show them: {name, realm, classId, raceId, level}.
function A.ArmorySubject()
    local c = A.Character()
    if not c then return nil end
    return {name = c.name, realm = c.realm, classId = c.classId, raceId = c.raceId, level = c.level}
end

--- Everything about this character that the website's armory shows.
function A.CollectArmory()
    local inv = A.OwnInventory()
    local equipped = {}
    for _, e in ipairs(inv.equipped) do equipped[#equipped + 1] = {slot = e[1], itemId = e[2]} end
    local bags = {}
    for _, e in ipairs(inv.bags) do bags[#bags + 1] = {itemId = e[1], count = e[2]} end
    return {equipped = equipped, bags = bags, stats = A.CollectStats(), talents = A.CollectTalents(), professions = A.CollectProfessionLines()}
end

-- ---------------------------------------------------------------- own armory to the website
-- Sent at most every 5 minutes, and only when something is worth sending (a login, new gear, spent talent points).
local lastSent, pending = -1e9, false
local function send()
    pending = false
    if not A.db or not A.db.settings.web then return end
    if A.Monotonic() - lastSent < 300 then return end
    lastSent = A.Monotonic()
    A.Record("armory.snapshot", A.CollectArmory(), "api_snapshot", nil, true)
end
local function later()
    if pending then return end
    pending = true
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(10, send) else send() end
end
A.SendArmorySnapshot = function() lastSent = -1e9; send() end
A.On("PLAYER_LOGIN", function() later() end)
A.On("PLAYER_EQUIPMENT_CHANGED", function() later() end)
A.On("CHARACTER_POINTS_CHANGED", function() later() end)

--- The quest log as the game shows it (Forever: C_QuestLog): {id, level, done, title, objectives={{have, need, text}}}.
--- Headers and hidden entries are skipped; quests under a collapsed header are not listed (nothing is expanded for this).
function A.CollectQuests(limit)
    local out = {}
    if not C_QuestLog or type(C_QuestLog.GetNumQuestLogEntries) ~= "function" or type(C_QuestLog.GetInfo) ~= "function" then return out end
    local shown = A.Number(A.Call(C_QuestLog.GetNumQuestLogEntries), 0, 300) or 0
    for index = 1, shown do
        local info = A.Call(C_QuestLog.GetInfo, index)
        local id = type(info) == "table" and A.Number(A.Field(info, "questID"), 1, 100000000)
        if id and A.Field(info, "isHeader") ~= true and A.Field(info, "isHidden") ~= true and #out < (limit or 35) then
            local objectives = {}
            local list = type(C_QuestLog.GetQuestObjectives) == "function" and A.Call(C_QuestLog.GetQuestObjectives, id) or nil
            for _, o in ipairs(type(list) == "table" and list or {}) do
                if type(o) == "table" and #objectives < 6 then
                    objectives[#objectives + 1] = {A.Number(A.Field(o, "numFulfilled"), 0, 100000) or 0, A.Number(A.Field(o, "numRequired"), 0, 100000) or 0, A.Text(A.Field(o, "text"), 80) or ""}
                end
            end
            local done = type(C_QuestLog.IsComplete) == "function" and A.Call(C_QuestLog.IsComplete, id) == true
            out[#out + 1] = {id = id, level = A.Number(A.Field(info, "level"), 0, 200) or 0, done = done, title = A.Text(A.Field(info, "title"), 120) or ("#" .. id), objectives = objectives}
        end
    end
    return out
end

--- Reputations as the game lists them (Forever: C_Reputation): {id, name, reaction 1-8, standing, min, max}. Headers without
--- their own reputation are skipped; factions under a collapsed header are not listed.
function A.CollectReputations(limit)
    local out = {}
    if not C_Reputation or type(C_Reputation.GetNumFactions) ~= "function" or type(C_Reputation.GetFactionDataByIndex) ~= "function" then return out end
    for index = 1, A.Number(A.Call(C_Reputation.GetNumFactions), 0, 400) or 0 do
        local f = A.Call(C_Reputation.GetFactionDataByIndex, index)
        local id = type(f) == "table" and A.Number(A.Field(f, "factionID"), 1, 1000000)
        if id and (A.Field(f, "isHeader") ~= true or A.Field(f, "isHeaderWithRep") == true) and #out < (limit or 60) then
            out[#out + 1] = {id = id, name = A.Text(A.Field(f, "name"), 60) or ("#" .. id), reaction = A.Number(A.Field(f, "reaction"), 1, 8) or 4,
                standing = A.Number(A.Field(f, "currentStanding"), -100000, 1000000) or 0,
                min = A.Number(A.Field(f, "currentReactionThreshold"), -100000, 1000000) or 0, max = A.Number(A.Field(f, "nextReactionThreshold"), -100000, 1000000) or 0}
        end
    end
    return out
end
