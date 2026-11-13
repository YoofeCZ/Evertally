local _, A = ...
-- Original concise walkthrough, checked against Forever-specific authored guides
-- on 2026-11-13; quest IDs/level/reward also match bundled Questie reference facts.
local sources={
    {title="Neryssa · Icy Veins · Sleeping Bag (Forever)",url="https://www.icy-veins.com/wow-forever/sleeping-bag/",checkedAt="2026-11-13"},
    {title="WoW Handbook · Cozy Sleeping Bag walkthrough",url="https://wowhandbook.com/news/cozy-sleeping-bag-in-wow-forever/",checkedAt="2026-11-13"},
    {title="Fred the Purifier · MMONerds · Sleeping Bag (Forever)",url="https://mmonerds.com/guides/wow-forever-cozy-sleeping-bag/",checkedAt="2026-11-13"},
}
A.SleepingBagSources=sources
local function tr(en,cs) return A.db and A.db.settings.language=="cs" and cs or en end
local function section(en,cs,bodyEn,bodyCs,map,x,y,quest)
    local title=tr(en,cs)
    return {title=title,body=tr(bodyEn,bodyCs),questId=quest,
        action=map and string.format("navigate:%d:%.4f:%.4f:%s",map,x,y,title) or nil}
end
local function article(faction)
    local alliance=faction=="Alliance"
    local out={section("Before travelling","Před cestou",
        "Level 14 required. You must read each object yourself. The trip crosses both continents; dangerous roads and jumping sections remain.",
        "Vyžaduje úroveň 14. Každý musí přečíst předměty sám. Cesta vede přes oba kontinenty; čekají tě nebezpečné oblasti a skoky.")}
    if alliance then
        out[#out+1]=section("1 · Alliance: Westfall","1 · Aliance: Westfall",
            "At Alexston Farmstead (37.5, 50.7), click Burned-Out Remains. Accept … and that note you found.",
            "Na Alexston Farmstead (37.5, 50.7) klikni na Burned-Out Remains. Přijmi … and that note you found.",1436,.375,.507,79008)
        out[#out+1]=section("2 · Across to The Barrens","2 · Přesun do The Barrens",
            "Read the matching remains at the ruined tower south of Camp Taurajo (46.4, 73.9). Turn in the note; accept Stepping Stones from the plank.",
            "U zničené věže jižně od Camp Taurajo (46.4, 73.9) přečti druhé ostatky. Odevzdej poznámku a z prkna přijmi Stepping Stones.",1413,.464,.739,79192)
    else
        out[#out+1]=section("1 · Horde: The Barrens","1 · Horda: The Barrens",
            "South of Camp Taurajo, click Burned-Out Remains at the ruined tower (46.4, 73.9). Accept … and that note you found.",
            "Jižně od Camp Taurajo klikni u zničené věže (46.4, 73.9) na Burned-Out Remains. Přijmi … and that note you found.",1413,.464,.739,79007)
        out[#out+1]=section("2 · Across to Westfall","2 · Přesun do Westfallu",
            "Read the matching remains at Alexston Farmstead (37.5, 50.7). Turn in the note; accept Stepping Stones from the plank.",
            "Na Alexston Farmstead (37.5, 50.7) přečti druhé ostatky. Odevzdej poznámku a z prkna přijmi Stepping Stones.",1436,.375,.507,79192)
    end
    out[#out+1]=section("3 · Stonetalon: uphill path","3 · Stonetalon: odbočka do hor",
        "The factions now share the route. Near 50.9, 52.3, take the uphill trail northeast of Sun Rock Retreat toward the abandoned camp.",
        "Odteď je postup společný. U 50.9, 52.3 odboč na stezku do hor severovýchodně od Sun Rock Retreat a pokračuj k opuštěnému táboru.",1442,.509,.523,79192)
    out[#out+1]=section("4 · Pocket Litter","4 · Pocket Litter",
        "At the camp (40.8, 52.5), click Pocket Litter on the crate. Finish Stepping Stones and take Scramble. The Old Toolbox reward has 12 slots.",
        "V táboře (40.8, 52.5) klikni na Pocket Litter na bedně. Dokonči Stepping Stones a vezmi Scramble. Odměnou je také dvanáctimístný Old Toolbox.",1442,.408,.525,79980)
    out[#out+1]=section("Optional · Rekindle","Volitelné · Rekindle",
        "The nearby firepit (40.6, 52.4) offers Rekindle. Use the supplied wood and tinder. This quest is optional for the sleeping bag.",
        "Blízké ohniště (40.6, 52.4) nabízí Rekindle. Použij získané dřevo a křesadlo. Tento quest není pro spacák povinný.",1442,.406,.524,80001)
    out[#out+1]=section("5 · Scramble: Mound of Dirt","5 · Scramble: Mound of Dirt",
        "Climb north of the camp to 39.6, 49.9. Approach the cliff ledge carefully and jump across to the dirt mound. Read it and accept Wet Job.",
        "Vystoupej severně od tábora k 39.6, 49.9. Opatrně přejdi ke skalní římse a přeskoč k hromádce hlíny. Přečti ji a přijmi Wet Job.",1442,.396,.499,79974)
    out[#out+1]=section("6 · Wet Job: Stonewrought Dam","6 · Wet Job: Stonewrought Dam",
        "At Loch Modan 49.5, 12.8, descend onto the carved dwarf heads on the Wetlands-facing dam wall. Click Carved Figurine and take Eagle's Fist.",
        "V Loch Modan na 49.5, 12.8 sestup na vytesané trpasličí hlavy na straně hráze obrácené k Wetlands. Klikni na Carved Figurine a vezmi Eagle's Fist.",1432,.495,.128,79975)
    out[#out+1]=section("7 · Thoradin's Wall: climb from Hillsbrad","7 · Thoradinova zeď: výstup z Hillsbradu",
        "Use the broken cart at Hillsbrad 87.3, 49.6 to climb the wall. Follow the jumping route into its upper room; map navigation only reaches the approach.",
        "Přes rozbitý vůz v Hillsbradu na 87.3, 49.6 vystoupej na zeď. Skoky pokračuj do horní místnosti; mapová navigace tě přivede jen k nástupu.",1424,.873,.496,79975)
    out[#out+1]=section("8 · Messenger Bag and final satchel","8 · Messenger Bag a poslední vak",
        "On the Arathi side at 22.5, 24.2, click Messenger Bag to finish Eagle's Fist. Accept This Must Be The Place, then click Hastily Rolled-Up Satchel below it.",
        "Na straně Arathi na 22.5, 24.2 dokonči Eagle's Fist kliknutím na Messenger Bag. Přijmi This Must Be The Place a otevři Hastily Rolled-Up Satchel pod ním.",1417,.225,.242,79976)
    out[#out+1]=section("Use your Cozy Sleeping Bag","Použití Cozy Sleeping Bag",
        "Use the bag outside combat. Rest inside for three minutes for three 1% XP stacks; the buff lasts two hours. The item has a one-hour cooldown. Camping is separate.",
        "Spacák použij mimo boj. Tři minuty uvnitř dávají tři vrstvy po 1 % XP na dvě hodiny. Předmět má hodinový cooldown. Camping je samostatný bonus.")
    out[#out+1]={title=tr("Sources · checked 13 Nov 2026","Zdroje · ověřeno 13. 11. 2026"),
        body="Icy Veins (Neryssa) · WoW Handbook · MMONerds (Fred the Purifier)",sources=sources}
    return out
end
A.SleepingBagGuide={sources=sources,requiredLevel=14,itemId=211527,sections=article}
A.RegisterGuide("sleeping-bag-alliance","leveling","Cozy Sleeping Bag · Alliance","Cozy Sleeping Bag · Aliance",function() return article("Alliance") end,"Interface\\Icons\\INV_Misc_Bag_10")
A.RegisterGuide("sleeping-bag-horde","leveling","Cozy Sleeping Bag · Horde","Cozy Sleeping Bag · Horda",function() return article("Horde") end,"Interface\\Icons\\INV_Misc_Bag_10")
