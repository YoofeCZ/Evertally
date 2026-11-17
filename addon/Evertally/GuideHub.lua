local _, A = ...
-- The Leveling page: the way into Evertally Guide (the Evertally_Guide add-ons, generated from Polestar by
-- tools/import_polestar.py): its leveling guides with the step window and the arrow, Lookup, rares, alts, its dungeon
-- hub, gear and talent plans, and its settings with every Quality of Life switch. Each button runs the guide's own
-- command; the guide draws its windows. Without the guide loaded the page says how to switch it on.
local text = {
    en = {leveling = "Leveling", sub_leveling = "Step-by-step leveling guides 1-60, the arrow, Lookup, rares and Quality of Life (Evertally Guide, based on Polestar).",
        lvMissing = "Evertally Guide is not loaded. Turn on the Evertally_Guide add-ons in the add-on list and restart the game.",
        lvCredit = "Evertally Guide is built from Polestar (github.com/fitzforge/polestar, GPL-3.0) by The Polestar authors, with thanks.",
        lvShow = "Guide window", lvShowHint = "The current step: where to go, what to do, the arrow to it.",
        lvGuides = "Choose a guide", lvGuidesHint = "Leveling routes for every race and class, profession and exploration guides.",
        lvLookup = "Lookup", lvLookupHint = "Find a quest, NPC, item or object: where it is, what drops it, who gives it.",
        lvRares = "Rares", lvRaresHint = "Rare creatures near you: where they spawn, an alert when one is up.",
        lvAlts = "Your characters", lvAltsHint = "Levels, gold, bags and professions of your other characters.",
        lvDungeons = "Dungeon hub", lvDungeonsHint = "Which dungeons suit your level, their quests and attunements.",
        lvGear = "Gear advice", lvGearHint = "Upgrades in your bags, quest rewards worth taking.",
        lvTalents = "Talent plan", lvTalentsHint = "A talent build to follow while you level.",
        lvOptions = "Guide and QoL settings", lvOptionsHint = "Every Quality of Life switch: auto quests, selling and repair, restock, death helper, XP pace and more.",
        lvInstall = "Set up again", lvInstallHint = "Go through the guide's setup a page at a time."},
    cs = {leveling = "Levelování", sub_leveling = "Návody na levelování 1–60 krok za krokem, šipka, Lookup, vzácní mobové a vylepšení hraní (Evertally Guide, založeno na Polestaru).",
        lvMissing = "Evertally Guide není načtený. Zapni addony Evertally_Guide v seznamu addonů a restartuj hru.",
        lvCredit = "Evertally Guide vychází z Polestaru (github.com/fitzforge/polestar, GPL-3.0) od jeho autorů. Díky.",
        lvShow = "Okno průvodce", lvShowHint = "Aktuální krok: kam jít, co udělat, šipka k cíli.",
        lvGuides = "Vybrat návod", lvGuidesHint = "Levelovací trasy pro každou rasu a povolání, návody na profese a průzkum.",
        lvLookup = "Lookup", lvLookupHint = "Najdi quest, NPC, předmět nebo objekt: kde je, co ho dropuje, kdo ho dává.",
        lvRares = "Vzácní mobové", lvRaresHint = "Vzácní mobové poblíž: kde se objevují, upozornění, když je někdo venku.",
        lvAlts = "Tvoje postavy", lvAltsHint = "Úrovně, zlato, tašky a profese tvých dalších postav.",
        lvDungeons = "Přehled dungeonů", lvDungeonsHint = "Které dungeony sedí na tvou úroveň, jejich questy a attunementy.",
        lvGear = "Rady k výbavě", lvGearHint = "Vylepšení v taškách, odměny z questů, které se vyplatí vzít.",
        lvTalents = "Plán talentů", lvTalentsHint = "Rozložení talentů, podle kterého levelovat.",
        lvOptions = "Nastavení průvodce a QoL", lvOptionsHint = "Všechna vylepšení hraní: automatické questy, prodej a oprava, doplnění zásob, pomoc po smrti, tempo XP a další.",
        lvInstall = "Nastavit znovu", lvInstallHint = "Projít nastavení průvodce stránku po stránce."},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

-- {label, hint, the guide's command}
local ITEMS = {
    {"lvShow", "lvShowHint", "show"}, {"lvGuides", "lvGuidesHint", "guides"}, {"lvLookup", "lvLookupHint", "lookup"},
    {"lvRares", "lvRaresHint", "rares"}, {"lvAlts", "lvAltsHint", "alts"}, {"lvDungeons", "lvDungeonsHint", "dungeons"},
    {"lvGear", "lvGearHint", "gear"}, {"lvTalents", "lvTalentsHint", "talents"}, {"lvOptions", "lvOptionsHint", "options"},
    {"lvInstall", "lvInstallHint", "install"},
}
local ROW = 46

--- The guide's command runner, or nil while the guide is not loaded.
function A.GuideCommand()
    local guide = rawget(_G, "EvertallyGuide")
    return type(guide) == "table" and type(guide.RunCommand) == "function" and guide.RunCommand or nil
end

--- Runs one of the guide's commands (as /polestar <command> would); false without the guide.
function A.RunGuide(command)
    local run = A.GuideCommand()
    if not run then return false end
    return (pcall(run, command))
end

function A.BuildLevelingPage(page, kit)
    local C = kit.C
    kit.PageHeader(page, "leveling")
    local hub = {rows = {}}
    page.leveling = hub
    hub.missing = kit.label(page, 12, C.peach); hub.missing:SetPoint("TOPLEFT", 0, -58); hub.missing:SetPoint("RIGHT", 0, 0); hub.missing:SetJustifyH("LEFT"); hub.missing:SetWordWrap(true)
    -- the buttons scroll: a small window shows the first ones and the rest under the wheel
    hub.scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    hub.scroll:SetPoint("TOPLEFT", 0, -92); hub.scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    hub.list = CreateFrame("Frame", nil, hub.scroll); hub.list:SetSize(600, #ITEMS * ROW + 40); hub.scroll:SetScrollChild(hub.list)
    for i, item in ipairs(ITEMS) do
        local command = item[3]
        local button = kit.Button(hub.list, item[1], 210, i == 1 and "primary" or "ghost", function() A.RunGuide(command) end)
        button:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        -- (two lines at most beside the button: a narrow window wraps the hint instead of cutting it off)
        local hint = kit.label(hub.list, 11, C.mist); hint:SetPoint("TOPLEFT", button, "TOPRIGHT", 12, 1); hint:SetPoint("RIGHT", hub.list, "RIGHT", 0, 0)
        hint:SetJustifyH("LEFT"); hint:SetJustifyV("TOP"); hint:SetWordWrap(true); hint:SetHeight(ROW - 6)
        hub.rows[i] = {button = button, hint = hint, label = item[1], hintKey = item[2]}
    end
    hub.credit = kit.label(hub.list, 10, C.faint or C.mist); hub.credit:SetPoint("TOPLEFT", 0, -#ITEMS * ROW - 4); hub.credit:SetPoint("RIGHT", hub.list, "RIGHT", 0, 0)
    hub.credit:SetJustifyH("LEFT"); hub.credit:SetWordWrap(true)
    local function fit() hub.list:SetWidth(math.max(300, (hub.scroll:GetWidth() or 600) - 4)) end
    hub.scroll:SetScript("OnSizeChanged", fit)
    function page.Refresh()
        fit()
        local ready = A.GuideCommand() ~= nil
        hub.missing:SetText(ready and "" or A.L("lvMissing")); hub.missing:SetShown(not ready)
        for _, row in ipairs(hub.rows) do
            row.button.text:SetText(A.L(row.label)); row.hint:SetText(A.L(row.hintKey))
            if row.button.SetEnabled then row.button:SetEnabled(ready) end
            row.button:SetAlpha(ready and 1 or 0.45)
        end
        hub.credit:SetText(A.L("lvCredit"))
    end
end
