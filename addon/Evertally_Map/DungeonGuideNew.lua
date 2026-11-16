local _, M = ...
-- Guides for Forever's own dungeons. Nobody has published tactics for them yet: the advice here is general (from dungeons of
-- the same level and kind) plus what the DungeonJournal add-on's own descriptions say about a boss. Players who know a fight
-- are asked (DungeonGuide.lua) to send it in. `classic` is left out on purpose: these are not Classic fights.
M.dungeonGuides = M.dungeonGuides or {}
local G = M.dungeonGuides
local function t(en, cs) return {en = en, cs = cs} end

G["Hall of Thanes"] = {mobs = {"undead", "elemental", "humanoid"}, dispel = {"curse", "magic"},
    intro = t("A short dwarven crypt beneath Ironforge, the first dungeon for Alliance characters. Expect restless dwarven dead, fire and stone constructs. The quests start in Ironforge and around Dun Morogh: take them before you go in.",
        "Krátká trpasličí krypta pod Ironforge, první dungeon pro postavy Aliance. Čekej neklidné trpasličí mrtvé, ohnivé a kamenné výtvory. Questy začínají v Ironforge a v okolí Dun Morogh: vezmi si je před vstupem."),
    tips = {t("Read the quests' notes in the Quests tab: one tablet must be picked up inside the last boss room before you leave.", "Přečti si poznámky questů v záložce Questy: jednu tabulku musíš sebrat v místnosti posledního bosse, než odejdeš."),
        t("At level 13 to 16 one extra pack is a wipe: pull one group at a time.", "Na úrovni 13 až 16 znamená jedna skupina navíc wipe: pullujte po jedné.")},
    bosses = {Magmatus = t("A fire elemental (the game calls the encounter Infurnus). Fight it where fire on the ground can be left; casters with fire spells do less here, frost and arcane more.",
        "Ohnivý elementál (hra souboj nazývá Infurnus). Bojuj tam, kde se dá z ohně na zemi odejít; ohnivá kouzla tu dávají méně, mráz a arkána víc.")}}

G["Ruins of Lordaeron"] = {mobs = {"undead", "humanoid"}, dispel = {"disease", "curse"},
    intro = t("The ruined capital above the Undercity, full of Scourge. A necromancer gathers power inside. The Lordaeron Captain (rare) is friendly to the Alliance: only the Horde can kill him.",
        "Zničené hlavní město nad Undercity, plné Pohromy. Uvnitř sbírá moc nekromant. Lordaeron Captain (rare) je přátelský k Alianci: zabít ho může jen Horda."),
    tips = {t("The Crest of Lordaeron for its quest can appear in several places (see the quest's note): look in the towers and side rooms while you clear.", "Crest of Lordaeron pro jeho quest se může objevit na více místech (viz poznámka questu): při čištění se podívej do věží a vedlejších místností."),
        t("Scourge brings diseases: a priest, paladin or shaman who removes them makes the run much easier.", "Pohroma nosí nemoci: kněz, paladin nebo šaman, který je čistí, běh hodně usnadní.")}}

G["Excavation Site: Wetlands"] = {mobs = {"beast", "mechanical", "giant"}, dispel = {"poison"},
    intro = t("A Titan dig site above Whelgar's Excavation, trapped in time; its constructs no longer obey anyone. Inside: Lost Marsh, Stalker's Thicket, Site of the Guardian and Lost Dig Site.",
        "Titánské naleziště nad Whelgar's Excavation, uvězněné v čase; jeho výtvory už nikoho neposlouchají. Uvnitř: Lost Marsh, Stalker's Thicket, Site of the Guardian a Lost Dig Site."),
    tips = {t("Raptors in the Thicket come in packs and run fast: pull with line of sight and keep crowd control on one.", "Raptoři v Thicketu chodí ve smečkách a běhají rychle: tahej je za roh a jednoho drž v crowd controlu.")},
    bosses = {Saltspine = t("A white crocolisk. Stay behind it so its front attacks only hit the tank.", "Bílý krokodýl. Stůj za ním, ať jeho útoky zepředu zasáhnou jen tanka."),
        Shadetooth = t("A giant violet raptor, leader of the Thicket raptors: clear the raptors around it first so they do not join.", "Obří fialový raptor, vůdce raptorů z Thicketu: nejdřív vyčisti raptory kolem, ať se nepřidají."),
        ["Relic Guardian"] = t("Final boss, a stone Titan construct: expect heavy melee on the tank, so cooldowns ready and the healer at full mana.", "Poslední boss, kamenný titánský výtvor: počítej s tvrdými ranami na tanka, tak měj cooldowny a healera s plnou manou.")}}

G["City of Dalaran"] = {mobs = {"humanoid", "elemental", "undead"}, dispel = {"magic", "curse"},
    intro = t("The restored mage city as a five-player dungeon: in through the sewers and the Underbelly, then up the streets to the Violet Citadel.",
        "Obnovené město mágů jako dungeon pro pět hráčů: dovnitř kanály a Underbelly, pak ulicemi až do Violet Citadel."),
    route = t("Sewers and the Underbelly (Atrexis) → the streets (Arcane Anomaly, Fel Ancient, Unstable Sentinel by the Magus Commerce Exchange, Mana Devourer, Arcanic Enigma) → the Purple Parlor of the Violet Citadel (Shade of the Archmage).",
        "Kanály a Underbelly (Atrexis) → ulice (Arcane Anomaly, Fel Ancient, Unstable Sentinel u Magus Commerce Exchange, Mana Devourer, Arcanic Enigma) → Purple Parlor ve Violet Citadel (Shade of the Archmage)."),
    tips = {t("Lots of casters: interrupts (Kick, Pummel, Earth Shock, Counterspell) are worth more than raw damage here.", "Hodně casterů: přerušení (Kick, Pummel, Earth Shock, Counterspell) tu mají větší cenu než čisté poškození.")},
    bosses = {["Atrexis the Grave Knight"] = t("At the ritual circle in the Underbelly, with Kirin Tor Necromancers and rising skeletons. Kill or control the necromancers first.\nTank: he disarms, so keep a shield and defensive cooldowns for that time.\nDPS: area damage on the skeletons when they rise.",
            "U rituálního kruhu v Underbelly, s Kirin Tor Necromancery a vstávajícími kostlivci. Nekromanty zabij nebo dej do crowd controlu jako první.\nTank: odzbrojuje, tak si na tu chvíli nech štít a obranné cooldowny.\nDPS: plošné poškození na kostlivce, když vstanou."),
        ["Arcane Anomaly"] = t("On a round terrace after the sewers. Casts Arcane Bolt and Focal Blast: interrupt them in turn.", "Na kulaté terase za kanály. Sesílá Arcane Bolt a Focal Blast: přerušujte je na střídačku."),
        ["Fel Ancient"] = t("A fel-touched treant among Suffused Treants: pull it away from the treants or kill them first.", "Fel stromový muž mezi Suffused Treanty: odtáhni ho od nich, nebo je zabij jako první."),
        ["Unstable Sentinel"] = t("An arcane golem with Angry Tomes. Malfunction hits everyone within 25 yards.\nRanged and healer: stay farther than 25 yards.\nMelee: step out when it starts Malfunction.",
            "Arkánový golem s Angry Tomes. Malfunction zasáhne všechny do 25 yardů.\nRanged a healer: stůjte dál než 25 yardů.\nMelee: když začne Malfunction, odstup."),
        ["Shade of the Archmage"] = t("Final boss in the Purple Parlor. Do not stand in a line with the target of Bounding Mana. He polymorphs the group, and the fight resets if anyone leaves the room: stay inside to the end.",
            "Poslední boss v Purple Parlor. Nestůj v jedné přímce s cílem Bounding Mana. Polymorfuje skupinu a souboj se resetuje, když kdokoli opustí místnost: zůstaňte uvnitř až do konce.")}}

G["The Drowned City"] = {mobs = {"humanoid", "undead", "elemental"}, dispel = {"poison", "curse"},
    intro = t("I'lalai, a lost Gurubashi troll city risen from the sea west of Grom'gol. An open-air dungeon of trolls and naga with a pirate wreck nearby; the weather turns into a storm before the last fight. Dive underwater to find the entrance.",
        "I'lalai, ztracené město trollů Gurubashi vynořené z moře západně od Grom'gol. Dungeon pod širým nebem plný trollů a nag s vrakem pirátské lodi; před posledním soubojem se zvedne bouře. Vchod najdeš pod vodou."),
    tips = {t("Open-air means patrols from the sides: watch the edges while you fight.", "Pod širým nebem chodí patroly ze stran: během boje hlídej okraje.")},
    bosses = {["Zul'Alai"] = t("First boss, an undead troll. He enrages near death and then hits the whole group hard: save cooldowns and healing for the last fifth.",
            "První boss, nemrtvý troll. Těsně před smrtí se rozzuří a pak tvrdě zasahuje celou skupinu: cooldowny a léčení si nech na poslední pětinu."),
        ["Var'Taka"] = t("Leader of the naga (the Horde quest The Only Good Brinescale... wants him dead). Naga casters around him: interrupt.", "Vůdce nag (hordí quest The Only Good Brinescale... chce jeho smrt). Kolem jsou nagy castery: přerušujte."),
        ["Deathless Marrow"] = t("Fought together with a Primeval Elemental: the tank holds both, damage kills one at a time. A warlock may try Banish on the elemental.", "Bojuje spolu s Primeval Elementalem: tank drží oba, DPS zabíjí jednoho po druhém. Warlock může zkusit na elementála Banish."),
        ["Min'loth the Serpent"] = t("Final boss, the Gurubashi witch doctor of I'lalai, in the storm. Expect totems and curses as from other troll witch doctors: kill totems, remove curses.", "Poslední boss, gurubašský šaman I'lalai, v bouři. Počítej s totemy a kletbami jako u jiných trollích šamanů: ničte totemy, čistěte kletby.")}}

G["Krol'dok Stronghold"] = {mobs = {"humanoid", "giant"}, dispel = {"magic"},
    intro = t("An ogre fortress in the Riverglades: workshops, camps and guarded inner passages. Ogre outrunners have been kidnapping travelers; chanting is heard after nightfall.",
        "Pevnost zlobrů v Riverglades: dílny, tábory a střežené vnitřní chodby. Zlobří běžci unášejí pocestné; po setmění je slyšet zpěv."),
    tips = {t("Ogres hit hard and are humanoids: sheep, sap and traps work on them. A Twilight commander means casters, so interrupts.", "Zlobři tvrdě bijí a jsou humanoidi: ovce, sap i pasti na ně fungují. Twilight velitel znamená castery, takže přerušovat.")}}

G["Alcaz Prison"] = {mobs = {"humanoid"}, dispel = {"poison", "magic"},
    intro = t("The prison on Alcaz Island in Dustwallow Marsh, rumored to hold high-ranking prisoners. Inside, the Defias Brotherhood and the naga are at war.",
        "Vězení na ostrově Alcaz v Dustwallow Marsh, prý drží důležité vězně. Uvnitř spolu válčí Defias Brotherhood a nagy."),
    tips = {t("Two sides at war: let them fight each other where you can, and do not pull into the middle of both.", "Dvě strany ve válce: kde to jde, nech je bojovat mezi sebou a netahej doprostřed obou.")}}

G["Blackmaw Hold"] = {mobs = {"humanoid", "beast", "demon"}, dispel = {"poison", "disease", "curse"},
    intro = t("The furbolg city of the Blackmaw clan in Azshara, behind a long-sealed gate, fighting a corruption that spreads through its groves and tunnels. A large level-60 dungeon with several routes.",
        "Furbolží město klanu Blackmaw v Azsharze, za dlouho zapečetěnou bránou, kde se šíří zkaženost háji a tunely. Velký dungeon pro úroveň 60 s několika cestami."),
    tips = {t("Several routes: agree on one before you start, and do not split.", "Několik cest: domluvte se na jedné ještě před začátkem a nerozdělujte se."),
        t("Corrupted furbolgs suggest poisons and diseases: bring someone who removes them.", "Zkažení furbolgové znamenají jedy a nemoci: vezměte někoho, kdo je čistí.")}}

G["Shaper's Terrace"] = {mobs = {"beast", "elemental", "mechanical"}, dispel = {"poison"},
    intro = t("An ancient titan facility in the northern hills of Un'Goro Crater. Collect power crystals across Un'Goro and use them at the consoles inside.",
        "Prastaré titánské zařízení v severních kopcích Un'Goro Crater. Posbírej po Un'Goru krystaly energie a použij je u konzolí uvnitř."),
    tips = {t("Bring the crystals before you go in: without them the consoles do nothing.", "Krystaly si přines před vstupem: bez nich konzole nic neudělají.")},
    bosses = {["Izha'Rel and Tor'Rel"] = t("Two raptors fought together, not elite: the tank holds both, damage kills one, then the other.", "Dva raptoři naráz, ne elitní: tank drží oba, DPS zabíjí jednoho, pak druhého.")}}
