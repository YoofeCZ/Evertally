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
