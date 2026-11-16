local _, M = ...
local A = _G.Evertally
-- The guide of a dungeon in the Dungeon Journal: an overview, advice for the tank, the healer and damage, tips for each class
-- and a tactic for each boss. The words per dungeon and boss are in DungeonGuideData.lua (M.dungeonGuides), written for
-- Evertally: for dungeons from Classic they follow Classic and say so (Forever may have changed a fight); for Forever's own
-- dungeons nobody has described the fights yet, so the guide gives general advice from other dungeons and asks players who
-- know a tactic to send it. Class tips are built from what the dungeon is full of (undead, beasts...) and what it puts on
-- the group (poison, curses...), so they fit the dungeon without being written 36 times.
local G = {}
M.DungeonGuide = G
G.EMAIL = "dominik.mracek@afstudio.dev"

local text = {
    en = {dgGuide = "Guide", dgOverview = "Overview", dgTank = "Tank", dgHealer = "Healer", dgDps = "Damage", dgClasses = "Classes", dgTips = "Tips",
        dgTactic = "Tactic", dgRoute = "Route", dgClassicNote = "Written from the Classic version of this fight. Forever may have changed it: if something differs, let us know.",
        dgNewDungeon = "This dungeon is new in Forever and no tactics have been published for it yet. What follows is general advice from dungeons of the same level and kind, not a description of these fights.",
        dgSend = "Do you know how a boss here works? Send the tactic (abilities, what to avoid, what worked) to %s and it goes into the guide for everyone.",
        dgBossUnknown = "The abilities of this boss are not described anywhere yet. General advice: pull it into a clear room, keep it facing away from the group, interrupt casts you have not seen before and save cooldowns for the second half.",
        dgYourClass = "Your class", dgMobs = "Enemies here: %s", dgCleanse = "Remove from the group: %s",
        dgMob_undead = "undead", dgMob_beast = "beasts", dgMob_humanoid = "humanoids", dgMob_elemental = "elementals", dgMob_demon = "demons", dgMob_dragonkin = "dragonkin", dgMob_giant = "giants", dgMob_mechanical = "mechanical",
        dgDispel_poison = "poison", dgDispel_disease = "disease", dgDispel_curse = "curses", dgDispel_magic = "magic"},
    cs = {dgGuide = "Návod", dgOverview = "Přehled", dgTank = "Tank", dgHealer = "Healer", dgDps = "DPS", dgClasses = "Povolání", dgTips = "Tipy",
        dgTactic = "Taktika", dgRoute = "Postup", dgClassicNote = "Napsáno podle verze tohoto souboje z Classicu. Forever ho mohl změnit: když se něco liší, dej vědět.",
        dgNewDungeon = "Tenhle dungeon je ve Forever nový a taktiky k němu zatím nikde nevyšly. Dál jsou obecné rady z dungeonů stejné úrovně a druhu, ne popis zdejších soubojů.",
        dgSend = "Víš, jak tu některý boss funguje? Pošli taktiku (schopnosti, čemu se vyhnout, co fungovalo) na %s a dostane se do návodu pro všechny.",
        dgBossUnknown = "Schopnosti tohohle bosse zatím nikde popsané nejsou. Obecně: stáhni ho do čisté místnosti, natoč ho od skupiny, přerušuj kouzla, která neznáš, a cooldowny si nech na druhou polovinu souboje.",
        dgYourClass = "Tvoje povolání", dgMobs = "Nepřátelé: %s", dgCleanse = "Čistit ze skupiny: %s",
        dgMob_undead = "nemrtví", dgMob_beast = "šelmy", dgMob_humanoid = "humanoidi", dgMob_elemental = "elementálové", dgMob_demon = "démoni", dgMob_dragonkin = "draci", dgMob_giant = "obři", dgMob_mechanical = "stroje",
        dgDispel_poison = "jed", dgDispel_disease = "nemoc", dgDispel_curse = "kletby", dgDispel_magic = "magie"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local function lang() return A.db and A.db.settings and A.db.settings.language == "cs" and "cs" or "en" end
--- The text of `value` in the player's language: a string, or {en = ..., cs = ...}.
function G.Pick(value)
    if type(value) ~= "table" then return value end
    return value[lang()] or value.en or value.cs
end

-- ---------------------------------------------------------------- advice for every dungeon
local ROLE = {
    tank = {
        {en = "Mark the pull before it starts: skull dies first, a moon or a square for crowd control. Wait until the healer has mana.", cs = "Před pullem označ cíle: lebka umírá první, měsíc nebo čtverec pro crowd control. Počkej, až má healer manu."},
        {en = "Pull casters around a corner (line of sight) so they come to you instead of casting from afar.", cs = "Castery tahej za roh (line of sight), ať přijdou k tobě a nesesílají z dálky."},
        {en = "Turn the boss away from the group: breath, cleave and fear in front of it then hit only you.", cs = "Bosse natoč od skupiny: dech, cleave a fear před ním pak zasáhnou jen tebe."},
        {en = "Walk into the next pack only when it is clear: patrols and adds that join mid-fight wipe more groups than bosses.", cs = "Do další skupiny jdi, až je čisto: patroly a přidaní nepřátelé uprostřed boje zabijí víc skupin než bossové."},
    },
    healer = {
        {en = "Stand where you see the tank and nobody pulls you by accident; out of line of sight you cannot heal.", cs = "Stůj tam, kde vidíš tanka a kde nic omylem nepullneš; mimo dohled léčit nejde."},
        {en = "Drink between pulls and say so: a short pause is cheaper than a wipe.", cs = "Mezi pully pij a řekni to: krátká pauza je levnější než wipe."},
        {en = "Heal what is needed, not more: overhealing early pulls the enemies to you before the tank holds them.", cs = "Léč jen kolik je potřeba: velké léčení hned na začátku stáhne nepřátele na tebe dřív, než je tank udrží."},
        {en = "Keep the cleanses on the group (see Classes): one removed debuff saves a lot of healing.", cs = "Hlídej čištění debuffů na skupině (viz Povolání): jeden odstraněný debuff ušetří spoustu léčení."},
    },
    dps = {
        {en = "Hit the tank's target (skull) and start a few seconds after the tank; at the top of the threat list you become the target.", cs = "Mlať cíl tanka (lebku) a začni pár vteřin po tankovi; navrchu seznamu threatu se cílem stáváš ty."},
        {en = "Do not break crowd control: no area damage next to a sheep, a sap or a shackle.", cs = "Nerozbíjej crowd control: žádné plošné poškození vedle ovce, sapu nebo shackle."},
        {en = "Interrupt heals and big casts; a caster that is not interrupted makes the fight long.", cs = "Přerušuj léčení a velká kouzla; nepřerušený caster souboj hodně prodlouží."},
        {en = "Stand behind the enemy (melee) or at range out of cleave; damage is only useful while you live.", cs = "Stůj za nepřítelem (melee) nebo na dálku mimo cleave; poškození má cenu, jen dokud žiješ."},
    },
}
G.ROLE = ROLE

-- what each class can do against what the dungeon is full of (crowd control, extra damage) and what it removes from the group
local MOB_TIPS = {
    undead = {PRIEST = {en = "Shackle Undead holds one undead out of the fight: ask for a mark for it.", cs = "Shackle Undead vyřadí jednoho nemrtvého z boje: řekni si o značku pro něj."},
        PALADIN = {en = "Exorcism and Holy Wrath hit undead hard; Turn Undead keeps one away for a while.", cs = "Exorcism a Holy Wrath na nemrtvé silně účinkují; Turn Undead jednoho na chvíli odežene."},
        MAGE = {en = "Polymorph does not work on undead: use Frost Nova and range instead.", cs = "Polymorph na nemrtvé nefunguje: použij Frost Novu a odstup."}},
    beast = {DRUID = {en = "Hibernate puts a beast to sleep; Soothe Animal keeps one from joining.", cs = "Hibernate uspí šelmu; Soothe Animal zabrání, aby se přidala."},
        HUNTER = {en = "Scare Beast takes one beast out of the pull; Freezing Trap works on beasts too.", cs = "Scare Beast vyřadí jednu šelmu z pullu; Freezing Trap funguje i na šelmy."},
        MAGE = {en = "Polymorph works on beasts.", cs = "Polymorph na šelmy funguje."}},
    humanoid = {MAGE = {en = "Polymorph on the moon: humanoids are the best target for a sheep.", cs = "Polymorph na měsíc: humanoidi jsou nejlepší cíl pro ovci."},
        ROGUE = {en = "Sap one humanoid before the pull (it must not be in combat yet).", cs = "Sapni jednoho humanoida před pullem (ještě nesmí být v boji)."},
        HUNTER = {en = "Freezing Trap before the pull; lead the trapped one away with your pet if needed.", cs = "Freezing Trap před pullem; když je potřeba, odveď ho petem."},
        WARLOCK = {en = "Seduction (Succubus) or Fear holds a humanoid, but Fear sends it running into more packs.", cs = "Seduction (Succubus) nebo Fear udrží humanoida, ale Fear ho pošle utíkat do dalších skupin."},
        WARRIOR = {en = "Pummel and Shield Bash stop their heals and casts.", cs = "Pummel a Shield Bash zastaví jejich léčení a kouzla."}},
    elemental = {WARLOCK = {en = "Banish holds an elemental out of the fight.", cs = "Banish vyřadí elementála z boje."},
        MAGE = {en = "Polymorph does not work on elementals; fire- or frost-made ones resist that school.", cs = "Polymorph na elementály nefunguje; ohniví nebo ledoví odolávají své škole magie."},
        SHAMAN = {en = "Fire, frost and nature resistance totems help against elemental damage.", cs = "Totemy odolnosti proti ohni, mrazu a přírodě pomáhají proti poškození elementálů."}},
    demon = {WARLOCK = {en = "Banish or Enslave Demon takes a demon out of the fight.", cs = "Banish nebo Enslave Demon vyřadí démona z boje."},
        PALADIN = {en = "Exorcism also hits demons hard.", cs = "Exorcism silně účinkuje i na démony."}},
    dragonkin = {DRUID = {en = "Hibernate works on dragonkin too.", cs = "Hibernate funguje i na draky."}},
    mechanical = {ROGUE = {en = "Machines cannot be sapped or poisoned to effect; kick casts instead.", cs = "Stroje nejde sapnout a jed na ně moc nepůsobí; radši přerušuj."}},
}
local CLEANSE = {
    poison = {DRUID = {en = "Cure / Abolish Poison: you are the poison cleanser here.", cs = "Cure / Abolish Poison: tady čistíš jedy ty."},
        SHAMAN = {en = "Cure Poison and the Poison Cleansing Totem.", cs = "Cure Poison a Poison Cleansing Totem."},
        PALADIN = {en = "Purify / Cleanse removes poison.", cs = "Purify / Cleanse odstraní jed."}},
    disease = {PRIEST = {en = "Cure / Abolish Disease: diseases are yours to remove.", cs = "Cure / Abolish Disease: nemoci čistíš ty."},
        PALADIN = {en = "Purify / Cleanse removes disease.", cs = "Purify / Cleanse odstraní nemoc."},
        SHAMAN = {en = "Cure Disease and the Disease Cleansing Totem.", cs = "Cure Disease a Disease Cleansing Totem."}},
    curse = {MAGE = {en = "Remove Lesser Curse: you are the curse remover here.", cs = "Remove Lesser Curse: kletby tady čistíš ty."},
        DRUID = {en = "Remove Curse takes curses off the group.", cs = "Remove Curse sundá kletby ze skupiny."}},
    magic = {PRIEST = {en = "Dispel Magic on harmful magic (fear, slows, sleep).", cs = "Dispel Magic na škodlivou magii (fear, zpomalení, spánek)."},
        PALADIN = {en = "Cleanse removes harmful magic as well.", cs = "Cleanse odstraní i škodlivou magii."}},
}
-- what every class brings anywhere, shown when the dungeon gives it nothing more specific
local ALWAYS = {
    WARRIOR = {en = "Tank: Taunt and Mocking Blow for loose enemies. Damage: Sunder Armor helps the tank, Pummel interrupts.", cs = "Tank: Taunt a Mocking Blow na utržené nepřátele. DPS: Sunder Armor pomáhá tankovi, Pummel přerušuje."},
    PALADIN = {en = "Blessings for the group before the first pull; Blessing of Protection saves a cloth wearer.", cs = "Blessingy pro skupinu před prvním pullem; Blessing of Protection zachrání člena v látce."},
    HUNTER = {en = "Turn off Growl in a group with a tank; Feign Death drops threat.", cs = "Ve skupině s tankem vypni petovi Growl; Feign Death shodí threat."},
    ROGUE = {en = "Kick casters, Sap before the pull; Vanish if you pull aggro.", cs = "Kickuj castery, Sap před pullem; Vanish, když strhneš aggro."},
    PRIEST = {en = "Power Word: Fortitude for all; Fade if enemies come to you.", cs = "Power Word: Fortitude pro všechny; Fade, když jdou nepřátelé na tebe."},
    SHAMAN = {en = "Totems for the fight (Strength of Earth, Mana Spring); Earth Shock interrupts.", cs = "Totemy na souboj (Strength of Earth, Mana Spring); Earth Shock přerušuje."},
    MAGE = {en = "Water and food for the group before you go in; Polymorph on the moon.", cs = "Voda a jídlo pro skupinu před vstupem; Polymorph na měsíc."},
    WARLOCK = {en = "Healthstones and a Soulstone on the healer before the first boss.", cs = "Healthstony a Soulstone na healera před prvním bossem."},
    DRUID = {en = "Mark of the Wild for all; Innervate the healer in long fights; Rebirth after a death.", cs = "Mark of the Wild pro všechny; Innervate healerovi v dlouhých soubojích; Rebirth po smrti."},
}
local CLASS_ORDER = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"}

--- The guide of a dungeon by its journal name (or nil).
function G.Of(name) return type(M.dungeonGuides) == "table" and M.dungeonGuides[name] or nil end

--- The tips for each class in `guide`: {class, lines = {text...}}, the player's class first.
function G.ClassTips(guide)
    local mine = select(2, A.Call(UnitClass, "player"))
    local out = {}
    for _, class in ipairs(CLASS_ORDER) do
        local lines = {}
        for _, mob in ipairs(guide and guide.mobs or {}) do local t = MOB_TIPS[mob] and MOB_TIPS[mob][class]; if t then lines[#lines + 1] = G.Pick(t) end end
        for _, kind in ipairs(guide and guide.dispel or {}) do local t = CLEANSE[kind] and CLEANSE[kind][class]; if t then lines[#lines + 1] = G.Pick(t) end end
        for _, t in ipairs(guide and guide.classes and guide.classes[class] or {}) do lines[#lines + 1] = G.Pick(t) end
        if #lines == 0 then lines[1] = G.Pick(ALWAYS[class]) end
        out[#out + 1] = {class = class, lines = lines, mine = class == mine}
    end
    table.sort(out, function(a, b) if a.mine ~= b.mine then return a.mine end; return false end)
    return out
end

--- The sections of the Guide tab, for the list on the left.
function G.Sections(guide)
    return {
        {key = "overview", title = A.L("dgOverview"), icon = "Interface\\Icons\\INV_Misc_Map_01"},
        {key = "tank", title = A.L("dgTank"), icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance"},
        {key = "healer", title = A.L("dgHealer"), icon = "Interface\\Icons\\Spell_Holy_FlashHeal"},
        {key = "dps", title = A.L("dgDps"), icon = "Interface\\Icons\\Ability_DualWield"},
        {key = "classes", title = A.L("dgClasses"), icon = "Interface\\Icons\\INV_Misc_Book_07"},
    }
end

local function names(list, prefix)
    local out = {}
    for _, key in ipairs(list or {}) do out[#out + 1] = A.L(prefix .. key) end
    return table.concat(out, ", ")
end

--- Draws one section of the guide of `entry` (a Dungeon Journal entry) into the detail panel `d`.
function G.Render(d, entry, section)
    local guide = G.Of(entry.name) or {}
    local new = guide.classic ~= true
    local C = d.kit and d.kit.C or {}
    d.SetTheme("parchment"); d.Reset("guide:" .. tostring(entry.name) .. ":" .. section)
    if section == "overview" then
        d.Text(entry.name or "?", d.heading, 18)
        local data = entry.data or {}
        if data.description then d.Text(data.description) end
        if guide.intro then d.Text(G.Pick(guide.intro)) end
        if new then d.Text(A.L("dgNewDungeon"), C.peach or d.ink, 12) end
        if guide.route then d.Head(A.L("dgRoute")); d.Text(G.Pick(guide.route)) end
        if guide.mobs and #guide.mobs > 0 then d.Text(string.format(A.L("dgMobs"), names(guide.mobs, "dgMob_")), d.ink, 12) end
        if guide.dispel and #guide.dispel > 0 then d.Text(string.format(A.L("dgCleanse"), names(guide.dispel, "dgDispel_")), d.ink, 12) end
        if guide.tips then d.Head(A.L("dgTips")); for _, tip in ipairs(guide.tips) do d.Text("•  " .. G.Pick(tip)) end end
        d.Head(" "); d.Text(string.format(A.L("dgSend"), G.EMAIL), d.ink, 11)
        if not new then d.Text(A.L("dgClassicNote"), d.ink, 10) end
    elseif section == "tank" or section == "healer" or section == "dps" then
        d.Text(A.L(section == "tank" and "dgTank" or section == "healer" and "dgHealer" or "dgDps"), d.heading, 18)
        local own = guide[section == "healer" and "healer" or section]
        if own then for _, tip in ipairs(own) do d.Text("•  " .. G.Pick(tip)) end; d.Head(A.L("dgTips")) end
        for _, tip in ipairs(ROLE[section]) do d.Text("•  " .. G.Pick(tip)) end
    elseif section == "classes" then
        d.Text(A.L("dgClasses"), d.heading, 18)
        local localized = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
        for _, item in ipairs(G.ClassTips(guide)) do
            local label = (type(localized) == "table" and localized[item.class]) or (item.class:sub(1, 1) .. item.class:sub(2):lower())
            d.Head(item.mine and (label .. "  (" .. A.L("dgYourClass") .. ")") or label)
            for _, line in ipairs(item.lines) do d.Text("•  " .. line) end
        end
    end
    d.Done()
end

--- The tactic of `boss` in the dungeon `entry`, drawn before its loot.
function G.RenderBoss(d, entry, boss)
    local guide = G.Of(entry.name) or {}
    local tactic = guide.bosses and guide.bosses[boss.name]
    if not tactic and boss.name == "Trash Drops" then return end
    d.Head(A.L("dgTactic"))
    if tactic then
        for line in (G.Pick(tactic) .. "\n"):gmatch("([^\n]*)\n") do if line ~= "" then d.Text(line) end end
        if guide.classic then d.Text(A.L("dgClassicNote"), d.ink, 10) end
    else
        d.Text(A.L("dgBossUnknown"))
        d.Text(string.format(A.L("dgSend"), G.EMAIL), d.ink, 11)
    end
end
