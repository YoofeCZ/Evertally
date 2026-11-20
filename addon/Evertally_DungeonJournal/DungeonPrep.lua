local A = _G.Evertally
local M = A.map -- (Evertally_DungeonJournal: a module of Evertally_Map's pages since 2026-11-20)
-- The Dungeon Journal's "For you" tab: what this character still has to do around a dungeon, from Evertally Guide's
-- Dungeons (the fork of Polestar, EvertallyGuide.Dungeons): the state of the dungeon's quests, what they are worth in
-- levels, the guides that pick them up before the run and hand them in after it, the way to the entrance, and each
-- attunement or key step by step with a guide through what is left. Evertally draws it in the journal's own panel;
-- the guide only supplies the data and opens its guides. Without the guide the tab is not shown.
local P = {}
M.DungeonPrep = P

local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local ACTIVE_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"
local DONE_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local WAIT_ICON = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local NO_ICON = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local KEY_ICON = A.Theme.ART .. "key"
local ROUTE_ICON = A.Theme.ART .. "route"
local HANDIN_ICON = A.Theme.ART .. "mail"
local SIDE = {Alliance = "A", Horde = "H"}

local text = {
    en = {prepTab = "For you", prepOverview = "Your character", prepOverviewSub = "Quests, levels and the way there",
        prepLevels = "Levels %s", prepBest = "Best at level %d", prepXP = "Its quests still to do are worth %.1f levels to you.",
        prepXPReady = "Those you can take now: %.1f levels.", prepMaxed = "At level 60 the quests give no more levels.",
        prepQuests = "Quests here", prepCount_done = "Done: %d", prepCount_ready = "Ready to turn in: %d", prepCount_log = "In your log: %d",
        prepCount_open = "You can take: %d", prepCount_low = "Later level: %d", prepCount_other = "Not for you: %d",
        prepActions = "Before and after the run", prepPickup = "Pick up the quests (%d)", prepPickupSub = "A guide to the givers, ending at the entrance",
        prepNothing = "Nothing to pick up before the run", prepNothingSub = "Done, in your log, inside or waiting for a level",
        prepWaiting = "Waiting for a level:", prepHandin = "Hand in the quests (%d)", prepHandinSub = "A guide to where they are turned in",
        prepAttunes = "Attunements and keys", prepAttDone = "Done", prepAttProgress = "%d of %d steps done", prepAttNew = "Not started",
        prepAttOther = "For the other faction", prepAttOne = "One in the group is enough", prepAttEach = "Everyone entering needs it", prepAttFrom = "From level %d",
        prepAttGuide = "Guide me through it", prepAttLeft = "%d steps left, from where you stand",
        prepHave = "You have it", prepHaveNot = "Not in your bags or bank", prepKeyLost = "Done once, but the item is not in your bags",
        prepSteps = "Steps", prepStepArrow = "Click: the arrow to this place",
        prepState_done = "Done", prepState_ready = "Ready to turn in", prepState_log = "In your log", prepState_open = "You can do it now",
        prepState_locked = "After the steps before it", prepState_level = "From level %d", prepState_rep = "Needs more reputation", prepState_na = "Not for you",
        prepState_skip = "Not needed", prepFrom = "%s from %s", prepGift = "%s gives you %s", prepRepStep = "Reputation with %s: %s",
        prepUnknown = "Evertally Guide has no page for this one: no attunements or quest runs to show.",
        prepBadge_done = "done", prepBadge_ready = "turn in", prepBadge_log = "in log"},
    cs = {prepTab = "Pro tebe", prepOverview = "Tvoje postava", prepOverviewSub = "Questy, úrovně a cesta",
        prepLevels = "Úrovně %s", prepBest = "Nejlépe na úrovni %d", prepXP = "Questy, které tu ještě máš, ti dají %.1f úrovně.",
        prepXPReady = "Ty, které můžeš vzít hned: %.1f úrovně.", prepMaxed = "Na úrovni 60 už questy úrovně nedávají.",
        prepQuests = "Questy tady", prepCount_done = "Hotové: %d", prepCount_ready = "K odevzdání: %d", prepCount_log = "V deníku: %d",
        prepCount_open = "Můžeš vzít: %d", prepCount_low = "Na vyšší úrovni: %d", prepCount_other = "Nejsou pro tebe: %d",
        prepActions = "Před během a po něm", prepPickup = "Vyzvednout questy (%d)", prepPickupSub = "Návod k zadavatelům, končí u vchodu",
        prepNothing = "Před během není co vyzvednout", prepNothingSub = "Hotové, v deníku, uvnitř nebo čekají na úroveň",
        prepWaiting = "Čeká na úroveň:", prepHandin = "Odevzdat questy (%d)", prepHandinSub = "Návod k místům odevzdání",
        prepAttunes = "Attunementy a klíče", prepAttDone = "Hotovo", prepAttProgress = "Hotovo %d z %d kroků", prepAttNew = "Nezačato",
        prepAttOther = "Pro druhou frakci", prepAttOne = "Stačí jeden ve skupině", prepAttEach = "Potřebuje každý, kdo vstoupí", prepAttFrom = "Od úrovně %d",
        prepAttGuide = "Proveď mě tím", prepAttLeft = "Zbývá kroků: %d, odtud, kde stojíš",
        prepHave = "Máš ho", prepHaveNot = "Není v taškách ani v bance", prepKeyLost = "Splněno, ale předmět v taškách nemáš",
        prepSteps = "Kroky", prepStepArrow = "Klik: šipka na tohle místo",
        prepState_done = "Hotovo", prepState_ready = "K odevzdání", prepState_log = "V deníku", prepState_open = "Můžeš teď",
        prepState_locked = "Po předchozích krocích", prepState_level = "Od úrovně %d", prepState_rep = "Potřebuje vyšší reputaci", prepState_na = "Není pro tebe",
        prepState_skip = "Není potřeba", prepFrom = "%s od %s", prepGift = "%s ti dá %s", prepRepStep = "Reputace u %s: %s",
        prepUnknown = "Evertally Guide pro tenhle nemá stránku: žádné attunementy ani questové běhy.",
        prepBadge_done = "hotovo", prepBadge_ready = "odevzdat", prepBadge_log = "v deníku"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

-- ---------------------------------------------------------------- the guide's data
local function guide()
    local g = rawget(_G, "EvertallyGuide")
    local D = type(g) == "table" and g.Dungeons
    if type(D) ~= "table" or type(D.Get) ~= "function" then return nil end
    return g, D
end
local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if ok then return a, b end
    return nil
end
local function side()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return SIDE[faction or ""]
end
local function level() return (UnitLevel and UnitLevel("player")) or 1 end
-- 3.2 levels; "3,2" in Czech
local function levels(key, n)
    local value = string.format(A.L(key), n)
    if A.db and A.db.settings and A.db.settings.language == "cs" then value = value:gsub("(%d)%.(%d)", "%1,%2") end
    return value
end

--- This character's state of a quest: "done", "ready" (objectives done), "log", or nil (not taken). The guide's
--- Compat when it is there (it knows the client's quest API), else the game's.
function P.QuestState(id)
    id = tonumber(id)
    if not id then return nil end
    local g = rawget(_G, "EvertallyGuide")
    local C = type(g) == "table" and g.Compat or nil
    local completed = C and C.IsQuestCompleted or (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or rawget(_G, "IsQuestFlaggedCompleted")
    if call(completed, id) then return "done" end
    if C and C.IsOnQuest then
        if call(C.IsOnQuest, id) then return call(C.IsQuestReadyForTurnIn, id) and "ready" or "log" end
    elseif C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) then
        return "log"
    end
    return nil
end
--- The short word for the Quests tab's list: "done", "turn in", "in log" (nil: nothing to say).
function P.QuestBadge(id)
    local state = P.QuestState(id)
    return state and A.L("prepBadge_" .. state) or nil
end

-- A page quest's state with the guide's reasons: the above, else "class"/"race" (Dungeons.QuestFor), "low", "open".
local function pageState(D, q, plevel)
    local state = P.QuestState(q.id)
    if state then return state end
    local _, why = call(D.QuestFor, q)
    if why then return "other" end
    if q.minLevel and plevel < q.minLevel then return "low" end
    return "open"
end

--- Whether the tab has anything for the dungeon the guide calls `key`.
function P.Has(key)
    local _, D = guide()
    return D ~= nil and key ~= nil and call(D.Get, key) ~= nil
end

--- The sections for the list on the left: the overview, then one per attunement or key of this side.
function P.Sections(key)
    local out = {{key = "overview", title = A.L("prepOverview"), sub = A.L("prepOverviewSub"), icon = ROUTE_ICON}}
    local _, D = guide()
    if not (D and key) then return out end
    for _, a in ipairs(call(D.Attunements, key, side()) or {}) do
        local st = call(D.AttunementState, a)
        local icon = KEY_ICON
        if a.item and a.item.id and GetItemIcon then icon = GetItemIcon(a.item.id) or icon end
        out[#out + 1] = {key = "attune:" .. tostring(a.id), title = a.name or "?", icon = icon, attune = a,
            sub = st and st.done and A.L("prepAttDone") or nil}
    end
    return out
end

-- ---------------------------------------------------------------- drawing
local function standing(n)
    local g = rawget(_G, "EvertallyGuide")
    local name = g and call(g.StandingName, n)
    return name or (_G["FACTION_STANDING_LABEL" .. tostring(n or 4)]) or tostring(n or "?")
end
local function stepText(s)
    if s.kind == "quest" then return s.title or "?" end
    local item = s.item and (s.item.name or ("#" .. tostring(s.item.id))) or "?"
    if s.kind == "drop" then return string.format(A.L("prepFrom"), item, s.npc and s.npc.name or "?") end
    if s.kind == "object" then return string.format(A.L("prepFrom"), item, s.object and s.object.name or "?") end
    if s.kind == "gift" then return string.format(A.L("prepGift"), s.npc and s.npc.name or "?", item) end
    if s.kind == "rep" then return string.format(A.L("prepRepStep"), s.name or "?", standing(s.standing)) end
    return "?"
end
local function stepPoint(s)
    local p = s.kind == "quest" and s.start or s.npc or s.object
    if type(p) == "table" and p.map and p.x and p.y then return p end
    return nil
end
local STEP_ICON = {done = DONE_ICON, ready = ACTIVE_ICON, log = ACTIVE_ICON, open = QUEST_ICON, locked = WAIT_ICON, level = WAIT_ICON,
    rep = WAIT_ICON, na = NO_ICON, skip = NO_ICON}

local function renderOverview(d, D, key)
    local info = call(D.Get, key) or {}
    d.Text(info.name or "?", d.heading, 18)
    local facts = {}
    if info.minLevel then facts[#facts + 1] = string.format(A.L("prepLevels"), info.maxLevel and info.maxLevel ~= info.minLevel and (info.minLevel .. "-" .. info.maxLevel) or tostring(info.minLevel)) end
    local best = call(D.BestAt, key)
    if best then facts[#facts + 1] = string.format(A.L("prepBest"), best) end
    if #facts > 0 then d.Text(table.concat(facts, "  ·  "), d.ink, 12) end
    local xs = call(D.QuestXP, key)
    if type(xs) == "table" then
        if xs.maxed then d.Text(A.L("prepMaxed"), d.ink, 12)
        elseif (xs.levels or 0) > 0.05 then
            d.Text(levels("prepXP", xs.levels))
            if type(xs.ready) == "table" and (xs.ready.levels or 0) > 0.05 and xs.ready.levels < xs.levels - 0.05 then
                d.Text(levels("prepXPReady", xs.ready.levels), d.ink, 12)
            end
        end
    end
    local quests = call(D.Quests, key, side()) or {}
    -- the guide's runs first (what the tab is for): pick up before, hand in after (the way to the entrance is the
    -- journal's own button under the panel)
    d.Head(A.L("prepActions"))
    local g = rawget(_G, "EvertallyGuide")
    local guided = type(g) == "table" and type(g.Lookup) == "table" and g.Lookup.Guide ~= nil
    local plan = guided and call(D.PickupPlan, key) or nil
    local take = type(plan) == "table" and type(plan.take) == "table" and #plan.take or 0
    if take > 0 then
        d.Link({title = string.format(A.L("prepPickup"), take), sub = A.L("prepPickupSub"), icon = QUEST_ICON, onClick = function() call(D.PickUp, key) end})
    elseif #quests > 0 and plan then
        d.Link({title = A.L("prepNothing"), sub = A.L("prepNothingSub"), icon = WAIT_ICON})
    end
    local waiting = plan and call(D.WaitingLines, plan) or nil
    if type(waiting) == "table" and #waiting > 0 then
        d.Text(A.L("prepWaiting"), d.ink, 12)
        for _, line in ipairs(waiting) do d.Text("•  " .. tostring(line), d.ink, 12) end
    end
    local hplan = guided and call(D.HandinPlan, key) or nil
    local hand = type(hplan) == "table" and ((type(hplan.hand) == "table" and #hplan.hand or 0) + (type(hplan.errands) == "table" and #hplan.errands or 0)) or 0
    if hand > 0 then
        d.Link({title = string.format(A.L("prepHandin"), hand), sub = A.L("prepHandinSub"), icon = HANDIN_ICON, onClick = function() call(D.HandIn, key) end})
    end
    -- the page's quests for this side, counted by state (each one's state is on the Quests tab)
    local plevel, counts, parts = level(), {}, {}
    for _, q in ipairs(quests) do local s = pageState(D, q, plevel); counts[s] = (counts[s] or 0) + 1 end
    for _, s in ipairs({"ready", "log", "open", "low", "done", "other"}) do
        if (counts[s] or 0) > 0 then parts[#parts + 1] = string.format(A.L("prepCount_" .. s), counts[s]) end
    end
    if #parts > 0 then d.Head(A.L("prepQuests")); d.Text(table.concat(parts, "  ·  "), d.ink, 12) end
end

local function renderAttune(d, D, key, a)
    d.Text(a.name or "?", d.heading, 18)
    local mine = not a.faction or a.faction == side()
    local facts = {a.need == "one" and A.L("prepAttOne") or A.L("prepAttEach")}
    if a.level then facts[#facts + 1] = string.format(A.L("prepAttFrom"), a.level) end
    if not mine then facts[#facts + 1] = A.L("prepAttOther") end
    d.Text(table.concat(facts, "  ·  "), d.ink, 12)
    local g = rawget(_G, "EvertallyGuide")
    if a.note and type(g) == "table" and type(g.L) == "table" then d.Text(tostring(g.L[a.note] or a.note)) end
    local st = call(D.AttunementState, a) or {steps = {}, left = 0}
    if a.item then
        local owned = mine and (st.owned and A.L("prepHave") or (st.goalDone and A.L("prepKeyLost") or A.L("prepHaveNot"))) or nil
        d.Link({title = a.item.name or ("#" .. tostring(a.item.id)), itemId = a.item.id, quality = a.item.quality, sub = owned,
            icon = GetItemIcon and GetItemIcon(a.item.id) or KEY_ICON,
            onClick = function() if A.OpenDatabaseEntry then A.OpenDatabaseEntry("item", a.item.id) end end})
    end
    local total, did = 0, 0
    for _, e in ipairs(st.steps or {}) do
        if e.state ~= "na" and e.state ~= "skip" then total = total + 1; if e.state == "done" then did = did + 1 end end
    end
    if mine then
        if st.done then d.Badge(A.L("prepAttDone"), nil, DONE_ICON)
        elseif did > 0 then d.Badge(string.format(A.L("prepAttProgress"), did, total), nil, WAIT_ICON)
        else d.Badge(A.L("prepAttNew"), nil, QUEST_ICON) end
        if not st.done and (st.left or 0) > 0 and D.Attune then
            d.Link({title = A.L("prepAttGuide"), sub = string.format(A.L("prepAttLeft"), st.left), icon = ROUTE_ICON, onClick = function() call(D.Attune, key, a.id) end})
        end
    end
    d.Head(A.L("prepSteps"))
    local mySide = side()
    for _, e in ipairs(st.steps or {}) do
        local s = e.step or {}
        if not mySide or not s.faction or s.faction == mySide then
            local state = mine and e.state or "na"
            local sub = state == "level" and string.format(A.L("prepState_level"), s.minLevel or 0) or A.L("prepState_" .. tostring(state))
            local point = state ~= "done" and state ~= "skip" and state ~= "na" and stepPoint(s) or nil
            if point then sub = sub .. "  ·  " .. A.L("prepStepArrow") end
            d.Link({title = stepText(s), sub = sub, icon = STEP_ICON[state] or QUEST_ICON,
                onClick = point and function() call(D.GuideToPoint, point, point.name) end or nil})
        end
    end
end

--- Draws one section (from P.Sections) of the dungeon the guide calls `key` into the journal's detail panel `d`.
function P.Render(d, key, section)
    d.SetTheme("parchment"); d.Reset("prep:" .. tostring(key) .. ":" .. tostring(section and section.key))
    local _, D = guide()
    if not (D and key and call(D.Get, key)) then
        d.Text(A.L("prepUnknown")); d.Done(); return
    end
    if section and section.attune then renderAttune(d, D, key, section.attune) else renderOverview(d, D, key) end
    d.Done()
end
