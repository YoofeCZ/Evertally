local _, A = ...
-- The Guides page: where to read more about Forever (talent calculators, class and profession guides, best in slot, databases, maps, changes), the same
-- list as the website's guides. The game cannot open a link, so each address is a field that selects itself when it is clicked (Ctrl+C copies it).
-- Descriptions are written by us from each site's own summary; those sites are not operated by Evertally.
local RESOURCES = {
    {group = "talents", id = "wowf", url = "https://wowf.io/en/", name = "WOWF.IO", tags = "talents · maps · dungeons",
        en = "Talent calculator and spellbook for all nine classes, race and class combinations with reworked racials, maps and dungeon guides.",
        cs = "Kalkulačka talentů a kniha kouzel pro všech devět classů, kombinace ras a class s přepracovanými rasovými schopnostmi, mapy a návody k dungeonům."},
    {group = "talents", id = "forevertalents", url = "https://wowforevertalents.com/", name = "WoW Forever Talents", tags = "talents · quests · dungeons",
        en = "Talent calculator for all nine classes with 51 points, plus quest and dungeon pages.",
        cs = "Kalkulačka talentů pro všech devět classů s 51 body a stránky s questy a dungeony."},
    {group = "talents", id = "foreverera", url = "https://theforeverera.com/en/", name = "The Forever Era", tags = "talents · best in slot · map",
        en = "Talent calculator, best-in-slot by class and level, map, dungeons and every change from Classic, build by build.",
        cs = "Kalkulačka talentů, BiS podle classy a levelu, mapa, dungeony a všechny změny oproti Classicu, build po buildu."},
    {group = "guides", id = "wowhead", url = "https://www.wowhead.com/forever", name = "Wowhead Forever", tags = "database · guides",
        en = "The largest WoW Forever site: class and profession guides, best-in-slot lists, a quest database and a talent calculator.",
        cs = "Největší web o WoW Forever: návody ke classám a profesím, BiS seznamy, databáze questů a kalkulačka talentů."},
    {group = "guides", id = "foreverguides", url = "https://theforeverguides.com/", name = "Forever Guides", tags = "guides · gold · professions",
        en = "Researched class guides, gold and profession guides, trackers, tools and daily news.",
        cs = "Důkladné návody ke classám, goldu a profesím, trackery, nástroje a denní novinky."},
    {group = "databases", id = "foreverbase", url = "https://foreverbase.org/en/", name = "foreverbase", tags = "database · maps · addons",
        en = "Guides, a database and maps for WoW Forever, plus a catalogue of addons that work on Forever.",
        cs = "Návody, databáze a mapy pro WoW Forever a katalog addonů, které na Forever fungují."},
    {group = "databases", id = "wowsrc", url = "https://wowsrc.com/", name = "WoW Source", tags = "tools · dungeons · professions",
        en = "Tools and guides: Legacy planner, dungeon list, class changes and professions.",
        cs = "Nástroje a návody: plánovač Legacy, seznam dungeonů, změny classů a profese."},
    {group = "changes", id = "foreverchanges", url = "https://foreverchanges.pro/", name = "ForeverChanges", tags = "changes · talents",
        en = "Latest Forever updates and patch notes, class buffs and nerfs, and everything Forever changes from Classic.",
        cs = "Poslední aktualizace Forever a patch notes, buffy a nerfy classů a všechno, co Forever mění oproti Classicu."},
}
local GROUPS = {"talents", "guides", "databases", "changes"}
local CARD_H, GAP = 104, 10

local text = {
    en = {guides = "Guides", sub_guides = "Where to read more about Forever: talent calculators, class and profession guides, best in slot, databases, maps and changes.",
        guidesGroup_talents = "Talent calculators", guidesGroup_guides = "Class, profession and gold guides", guidesGroup_databases = "Databases, maps and tools", guidesGroup_changes = "Changes and patch notes",
        guidesHow = "The game cannot open links: click an address, press Ctrl+C and paste it into your browser. These sites are not run by Evertally.",
        guidesRead = "How to read the database", guidesRead1 = "NPCs, quests and places come from QuestieDB; item tooltips from the game itself; dungeon facts from the DungeonJournal add-on.",
        guidesRead2 = "Drop chances are shown only where a source gives them. A loot source is not a measured drop rate.",
        guidesLocal = "In the game itself", guidesLocal1 = "Database: every quest, NPC, item and object, linked together.  Dungeon Journal: bosses, loot, quests and maps of every dungeon.  Map & routes: gathering, trainers, merchants and the way to a place."},
    cs = {guides = "Návody", sub_guides = "Kde se dočíst víc o Forever: kalkulačky talentů, návody ke classám a profesím, BiS, databáze, mapy a změny.",
        guidesGroup_talents = "Kalkulačky talentů", guidesGroup_guides = "Návody ke classám, profesím a goldu", guidesGroup_databases = "Databáze, mapy a nástroje", guidesGroup_changes = "Změny a patch notes",
        guidesHow = "Hra neumí otevřít odkaz: klikni na adresu, stiskni Ctrl+C a vlož ji do prohlížeče. Ty weby Evertally neprovozuje.",
        guidesRead = "Jak číst databázi", guidesRead1 = "NPC, questy a místa jsou z QuestieDB, tooltipy itemů z hry samotné a fakta o dungeonech z addonu DungeonJournal.",
        guidesRead2 = "Šance na drop se ukazují jen tam, kde je zdroj uvádí. Zdroj lootu není změřená šance.",
        guidesLocal = "Přímo ve hře", guidesLocal1 = "Databáze: každý quest, NPC, item a objekt, propojené.  Dungeon Journal: bossové, loot, questy a mapy každého dungeonu.  Mapa a cesty: sbírání, trenéři, obchodníci a cesta na místo."},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end
A.GUIDE_RESOURCES = RESOURCES

function A.BuildGuidesPage(page, kit)
    local C = kit.C
    kit.PageHeader(page, "guides")
    local g = {cards = {}, heads = {}}
    page.guides = g
    page.scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    page.scroll:SetPoint("TOPLEFT", 0, -56); page.scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    page.content = CreateFrame("Frame", nil, page.scroll); page.content:SetSize(600, 800); page.scroll:SetScrollChild(page.content)
    g.how = kit.label(page.content, 11, C.peach); g.how:SetPoint("TOPLEFT", 0, 0); g.how:SetPoint("TOPRIGHT", 0, 0)
    local y = 26
    for _, group in ipairs(GROUPS) do
        local head = kit.label(page.content, 14, C.gold); head:SetPoint("TOPLEFT", 0, -y); y = y + 24
        head.group = group; g.heads[#g.heads + 1] = head
        for _, resource in ipairs(RESOURCES) do
            if resource.group == group then
                local card = CreateFrame("Frame", nil, page.content)
                card:SetHeight(CARD_H); card:SetPoint("TOPLEFT", 0, -y); card:SetPoint("TOPRIGHT", 0, -y)
                A.NativePanel(card, C)
                card.name = kit.label(card, 14, C.text); card.name:SetPoint("TOPLEFT", 12, -9); card.name:SetText(resource.name)
                card.tags = kit.label(card, 10, C.faint); card.tags:SetPoint("TOPRIGHT", -12, -12); card.tags:SetJustifyH("RIGHT"); card.tags:SetText(resource.tags)
                card.desc = kit.label(card, 11, C.mist); card.desc:SetPoint("TOPLEFT", 12, -30); card.desc:SetPoint("TOPRIGHT", -12, -30); card.desc:SetJustifyH("LEFT"); card.desc:SetJustifyV("TOP"); card.desc:SetHeight(32)
                card.link = kit.LinkBox(card); card.link:SetPoint("BOTTOMLEFT", 12, 10); card.link:SetPoint("BOTTOMRIGHT", -12, 10); card.link.SetUrl(resource.url)
                card.resource = resource
                g.cards[#g.cards + 1] = card
                y = y + CARD_H + GAP
            end
        end
        y = y + 6
    end
    g.read = kit.label(page.content, 14, C.gold); g.read:SetPoint("TOPLEFT", 0, -y); y = y + 24
    g.read1 = kit.label(page.content, 11, C.text); g.read1:SetPoint("TOPLEFT", 0, -y); g.read1:SetPoint("TOPRIGHT", 0, -y); g.read1:SetHeight(34); y = y + 36
    g.read2 = kit.label(page.content, 11, C.text); g.read2:SetPoint("TOPLEFT", 0, -y); g.read2:SetPoint("TOPRIGHT", 0, -y); g.read2:SetHeight(34); y = y + 40
    g.here = kit.label(page.content, 14, C.gold); g.here:SetPoint("TOPLEFT", 0, -y); y = y + 24
    g.here1 = kit.label(page.content, 11, C.text); g.here1:SetPoint("TOPLEFT", 0, -y); g.here1:SetPoint("TOPRIGHT", 0, -y); g.here1:SetHeight(48); y = y + 56
    page.content:SetHeight(y + 10)
    page:SetScript("OnSizeChanged", function(_, width) page.content:SetWidth(math.max(300, (tonumber(width) or 640) - 28)) end)
    function page.Refresh()
        local lang = A.db and A.db.settings.language == "cs" and "cs" or "en"
        g.how:SetText(A.L("guidesHow"))
        for _, head in ipairs(g.heads) do head:SetText(A.L("guidesGroup_" .. head.group)) end
        for _, card in ipairs(g.cards) do card.desc:SetText(card.resource[lang]) end
        g.read:SetText(A.L("guidesRead")); g.read1:SetText(A.L("guidesRead1")); g.read2:SetText(A.L("guidesRead2"))
        g.here:SetText(A.L("guidesLocal")); g.here1:SetText(A.L("guidesLocal1"))
    end
end
