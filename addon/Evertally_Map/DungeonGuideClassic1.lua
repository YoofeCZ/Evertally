local _, M = ...
-- Guides for the dungeons Forever took from Classic, levels 13 to 46. Written for Evertally from how these fights work in
-- Classic; `classic = true` makes the journal say so, since Forever may have changed a fight.
M.dungeonGuides = M.dungeonGuides or {}
local G = M.dungeonGuides
local function t(en, cs) return {en = en, cs = cs} end

G["Ragefire Chasm"] = {classic = true, mobs = {"humanoid", "elemental", "beast"}, dispel = {"magic"},
    intro = t("Caves under Orgrimmar, the first Horde dungeon: troggs, Searing Blade cultists and fire elementals. Short and forgiving.", "Jeskyně pod Orgrimmarem, první dungeon Hordy: troggové, kultisté Searing Blade a ohniví elementálové. Krátký a shovívavý."),
    tips = {t("Cultist casters cast Shadow Bolt: pull them around corners.", "Kultisté sesílají Shadow Bolt: tahej je za roh.")},
    bosses = {Oggleflint = t("A trogg chief with a few troggs: kill the adds, then him. Simple tank-and-spank.", "Trogg náčelník s pár troggy: zabij přidané, pak jeho. Jednoduchý souboj."),
        ["Taragaman the Hungerer"] = t("A demon. Fire Nova hits everyone near him and Uppercut knocks the tank back: melee stand behind, ranged keep distance, the tank stays with his back to a wall.", "Démon. Fire Nova zasáhne všechny kolem a Uppercut odhodí tanka: melee za něj, ranged z dálky, tank zády ke zdi."),
        ["Jergosh the Invoker"] = t("A caster: Curse of Weakness and Immolate. Interrupt and remove the curse.", "Caster: Curse of Weakness a Immolate. Přerušujte a čistěte kletbu."),
        Bazzalan = t("A satyr: Sinister Strike and poison on the tank. Short fight, keep the tank healed.", "Satyr: Sinister Strike a jed na tanka. Krátký souboj, drž tanka naléčeného.")}}

G["Wailing Caverns"] = {classic = true, mobs = {"humanoid", "beast", "dragonkin"}, dispel = {"poison", "magic"},
    intro = t("Caves under the Barrens, a maze of druids of the Fang and deviate beasts. The goal is to wake Naralex: at the end, escort the Disciple of Naralex.", "Jeskyně pod Barrens, bludiště druidů Fangu a zmutovaných zvířat. Cílem je probudit Naralexe: na konci doprovoď Disciple of Naralex."),
    route = t("Anacondra → Pythas → Cobrahn (and the optional Kresh, Skum) → Serpentis → Verdan; then talk to the Disciple at the entrance and protect him to Mutanus.", "Anacondra → Pythas → Cobrahn (volitelně Kresh, Skum) → Serpentis → Verdan; pak promluv s Disciple u vchodu a chraň ho až k Mutanovi."),
    tips = {t("The four Fang druids cast Sleep and heal: interrupt the heals and remove Sleep with Dispel Magic.", "Čtyři druidi Fangu uspávají a léčí se: přerušujte léčení a Sleep sundávejte Dispel Magic."),
        t("The maze is easy to get lost in: follow the tank, do not wander.", "V bludišti se snadno ztratíš: drž se tanka.")},
    bosses = {["Lady Anacondra"] = t("Druid: Sleep and Healing Touch. Interrupt every heal, dispel Sleep.", "Druidka: Sleep a Healing Touch. Přerušujte každé léčení, Sleep dispelujte."),
        ["Lord Cobrahn"] = t("Druid who turns into a serpent and poisons: cure the poison, interrupt his heals.", "Druid, který se mění v hada a otravuje: čistěte jed, přerušujte léčení."),
        ["Lord Pythas"] = t("Druid with Thunderclap and Sleep: melee will be slowed, keep interrupting heals.", "Druid s Thunderclapem a Sleep: melee bude zpomalené, dál přerušujte léčení."),
        ["Lord Serpentis"] = t("Druid with Lightning Bolt and Sleep, often with adds: clear the adds, then interrupt him.", "Druid s Lightning Boltem a Sleep, často s přidanými: nejdřív přidané, pak ho přerušujte."),
        Kresh = t("A turtle in the water, optional. Slow but tough; fight him in the shallows.", "Želva ve vodě, volitelná. Pomalá, ale odolná; bojuj na mělčině."),
        Skum = t("A thunder lizard in the water, optional: Chained Bolt hits a few players. Spread a little.", "Hromová ještěrka ve vodě, volitelná: Chained Bolt zasáhne více hráčů. Trochu se roztáhněte."),
        ["Verdan the Everliving"] = t("A big plant: Grasping Vines knock players down. Melee stand behind, healer keeps distance.", "Velká rostlina: Grasping Vines srážejí hráče k zemi. Melee za něj, healer z dálky."),
        ["Mutanus the Devourer"] = t("Comes after the escort. Naralex's Nightmare puts a player to sleep and Terrify fears: tank with your back to a wall, dispel the sleep.", "Přijde po doprovodu. Naralex's Nightmare uspí hráče a Terrify straší: tank zády ke zdi, spánek dispelujte.")}}

G["The Deadmines"] = {classic = true, mobs = {"humanoid", "mechanical"}, dispel = {"poison"},
    intro = t("The Defias mines under Moonbrook, Westfall, with a goblin-built ship at the end. Classic first Alliance dungeon, long but straight.", "Doly Defias pod Moonbrookem ve Westfallu, na konci loď postavená gobliny. Klasický první dungeon Aliance, dlouhý, ale přímý."),
    route = t("Rhahk'Zor → (Miner Johnson rare) → Sneed's Shredder and Sneed → Gilnid in the foundry → the cannon opens the cove → Mr. Smite → Captain Greenskin → Edwin VanCleef on the deck (Cookie at the ship's galley).", "Rhahk'Zor → (Miner Johnson rare) → Sneed's Shredder a Sneed → Gilnid ve slévárně → dělo otevře zátoku → Mr. Smite → Captain Greenskin → Edwin VanCleef na palubě (Cookie v kuchyni lodi)."),
    tips = {t("Defias casters and Evokers: sheep or kill them first.", "Defias castery a Evokery dejte do ovce, nebo je zabijte první."),
        t("In the cove, goblin and pirate patrols move: watch the stairs.", "V zátoce chodí goblinské a pirátské patroly: hlídejte schody.")},
    bosses = {["Rhahk'Zor"] = t("An ogre with Rhahk'Zor Slam that stuns the tank. Simple fight; healer keeps the tank topped.", "Zlobr s Rhahk'Zor Slamem, který omráčí tanka. Jednoduchý souboj; healer drží tanka plného."),
        ["Sneed's Shredder"] = t("A shredder; when it dies Sneed jumps out. Keep damage on it, then switch to Sneed.", "Shredder; když padne, vyskočí Sneed. Mlaťte stroj, pak přepněte na Sneeda."),
        Sneed = t("Disarms. A quick kill after the shredder.", "Odzbrojuje. Rychlé zabití po shredderu."),
        Gilnid = t("In the foundry, with goblin adds that come from the sides: clear the room first, then pull him.", "Ve slévárně, s goblinskými přidanými ze stran: nejdřív vyčisti místnost, pak ho pullni."),
        ["Mr. Smite"] = t("At 66% and 33% he stuns the group and switches weapons, hitting harder: tank cooldowns for the last third.", "Na 66 % a 33 % omráčí skupinu a vymění zbraň, pak bije víc: obranné cooldowny tanka na poslední třetinu."),
        ["Captain Greenskin"] = t("Cleave and Poisoned Harpoon, with pirate adds: kill the adds, cure the poison, melee stay out of the front.", "Cleave a Poisoned Harpoon, s piráty kolem: zabijte přidané, čistěte jed, melee mimo přední stranu."),
        ["Edwin VanCleef"] = t("Thrash. Calls two Defias Blackguards at about half health: the tank picks them up, kill them before him.", "Thrash. Kolem poloviny zdraví přivolá dva Defias Blackguardy: tank je sebere, zabijte je dřív než jeho."),
        Cookie = t("The ship's cook in the galley: heals himself with food. Interrupt or burst.", "Lodní kuchař v kuchyni: léčí se jídlem. Přerušte nebo ho rychle sundejte.")}}

G["Shadowfang Keep"] = {classic = true, mobs = {"undead", "humanoid", "beast"}, dispel = {"curse", "magic"},
    intro = t("Arugal's keep in Silverpine Forest, full of worgen and undead. Free the prisoner in the courtyard cell (Sorcerer Ashcrombe / Deathstalker Adamant) to open the gate.", "Arugalova pevnost v Silverpine Forest, plná worgenů a nemrtvých. Osvoboď vězně v cele na nádvoří (Sorcerer Ashcrombe / Deathstalker Adamant), ten otevře bránu."),
    tips = {t("Worgen packs hit hard and some curse: a mage or druid removing curses helps a lot.", "Skupiny worgenů tvrdě bijí a některé proklínají: mág nebo druid, který čistí kletby, hodně pomůže.")},
    bosses = {Rethilgore = t("In the cells. Soul Drain on the tank; a quick fight.", "U cel. Soul Drain na tanka; krátký souboj."),
        ["Fel Steed / Shadow Charger"] = t("Spectral horses in the stable: fight them one at a time.", "Přízrační koně ve stáji: bojujte s nimi po jednom."),
        ["Razorclaw the Butcher"] = t("Butcher Cleave: melee behind him, tank faces him away.", "Butcher Cleave: melee za něj, tank ho natočí od skupiny."),
        ["Baron Silverlaine"] = t("Veil of Shadow lowers healing on the tank: dispel it (magic) and keep heals coming.", "Veil of Shadow snižuje léčení tanka: dispelujte ji (magie) a léčte dál."),
        ["Commander Springvale"] = t("A paladin with Holy Light and Divine Protection: interrupt the heals. Comes with adds.", "Paladin s Holy Light a Divine Protection: přerušujte léčení. Přichází s přidanými."),
        ["Odo the Blindwatcher"] = t("Howling Rage makes him faster and stronger as he loses health: burst him down, tank cooldowns at the end.", "Howling Rage ho se ztrátou zdraví zrychluje a posiluje: rychle ho sundejte, obranné cooldowny na konec."),
        ["Arugal's Voidwalker"] = t("Voidwalkers that patrol in a group: pull them all at once and use area damage, or take them one by one.", "Voidwalkeři, kteří chodí ve skupině: pullněte je naráz a plošné poškození, nebo po jednom."),
        ["Fenrus the Devourer"] = t("A big wolf: Toxic Saliva poisons the tank. Cure poison.", "Velký vlk: Toxic Saliva otráví tanka. Čistěte jed."),
        ["Wolf Master Nandos"] = t("Summons wolves around him: kill the wolves fast or use area damage.", "Vyvolává kolem sebe vlky: rychle je zabijte nebo použijte plošné poškození."),
        ["Archmage Arugal"] = t("Teleports around the room, Shadow Bolts and turns a player into a worgen (Arugal's Curse). Remove the curse; stay ready to move with him.", "Teleportuje se po místnosti, sesílá Shadow Bolty a mění hráče ve worgena (Arugal's Curse). Čistěte kletbu a buďte připraveni se s ním přesouvat.")}}

G["Blackfathom Deeps"] = {classic = true, mobs = {"humanoid", "beast", "elemental"}, dispel = {"poison", "curse"},
    intro = t("A flooded night elf temple on the Zoram Strand: naga, murlocs and Twilight's Hammer cultists serving Aku'mai. Much of it is underwater.", "Zatopený elfí chrám na Zoram Strand: nagy, murloci a kultisté Twilight's Hammer ve službách Aku'mai. Velká část je pod vodou."),
    tips = {t("Watch your breath underwater; a warlock's Unending Breath or a shaman's Water Breathing helps.", "Pod vodou hlídej dech; pomůže warlockův Unending Breath nebo šamanův Water Breathing."),
        t("Before Aku'mai, the four braziers summon waves of adds when lit: the tank gathers them, everyone else kills them.", "Před Aku'mai přivolá zapálení čtyř pánví vlny nepřátel: tank je posbírá, ostatní zabíjí.")},
    bosses = {["Ghamoo-ra"] = t("A giant turtle with Trample: high armor, so casters and armor reduction help.", "Obří želva s Trample: má vysoké brnění, takže pomůžou kouzla a snížení brnění."),
        ["Lady Sarevess"] = t("A naga with Forked Lightning and Slow, with two adds: kill the adds, stay out of her front.", "Naga s Forked Lightning a Slow, se dvěma přidanými: zabijte přidané, nestůjte před ní."),
        Gelihast = t("A murloc boss with Net: the tank stands still anyway, ranged spread.", "Murločí boss s Netem: tank stejně stojí, ranged se roztáhnou."),
        ["Lorgus Jett"] = t("A Twilight caster with a totem: kill the totem, interrupt Lightning Bolt.", "Twilight caster s totemem: zničte totem, přerušujte Lightning Bolt."),
        ["Old Serra'kis"] = t("A shark underwater: fight him near the surface so nobody drowns.", "Žralok pod vodou: bojujte blízko hladiny, ať se nikdo neutopí."),
        ["Twilight Lord Kelris"] = t("Mind Blast and Sleep: dispel sleep, interrupt. Talk to the altar after him to start the braziers.", "Mind Blast a Sleep: dispelujte spánek, přerušujte. Po něm použijte oltář a začnou pánve."),
        ["Aku'mai"] = t("A hydra: Frenzied Rage and Poison Cloud. Tank faces it away, melee behind, cure poison; burst it in the last quarter.", "Hydra: Frenzied Rage a Poison Cloud. Tank ji natočí od skupiny, melee za ni, čistěte jed; poslední čtvrtinu rychle.")}}

G["The Stockade"] = {classic = true, mobs = {"humanoid"}, dispel = {"poison"},
    intro = t("Stormwind's prison taken by its inmates: three corridors of rioting Defias convicts. Alliance only, short, many packs.", "Stormwindské vězení ovládnuté vězni: tři chodby vzbouřených trestanců Defias. Jen pro Alianci, krátké, hodně skupin."),
    tips = {t("Packs stand close: pull slowly, one at a time, and sap or sheep the extras.", "Skupiny stojí blízko sebe: pullujte pomalu, po jedné, a navíc sapněte nebo dejte do ovce.")},
    bosses = {["Targorr the Dread"] = t("Enrages at low health: keep damage high at the end.", "Na nízkém zdraví se rozzuří: na konci držte vysoké poškození."),
        ["Kam Deepfury"] = t("A dwarf with Shield Slam and Defensive Stance: slow but long; armor reduction helps.", "Trpaslík se Shield Slamem a Defensive Stance: pomalý, ale dlouhý souboj; pomůže snížení brnění."),
        Hamhock = t("Chain Lightning hits several players: spread out a little.", "Chain Lightning zasáhne více hráčů: trochu se roztáhněte."),
        ["Dextren Ward"] = t("Fears and Mortal Strikes the tank (less healing): tank against a wall, heal through.", "Straší a dává tankovi Mortal Strike (méně léčení): tank u zdi, proléčit."),
        ["Bazil Thredd"] = t("The Defias leader, with adds: kill the adds, then him.", "Vůdce Defias, s přidanými: nejdřív přidaní, pak on.")}}

G["Gnomeregan"] = {classic = true, mobs = {"mechanical", "humanoid"}, dispel = {"poison", "disease"},
    intro = t("The irradiated gnome capital in Dun Morogh: troggs, leper gnomes and machines. Long and confusing; the back entrance (with the Workshop Key) saves time.", "Ozářené hlavní město gnómů v Dun Moroghu: troggové, malomocní gnómové a stroje. Dlouhé a matoucí; zadní vchod (s Workshop Key) ušetří čas."),
    tips = {t("Irradiated mobs and slimes cause diseases and poisons: bring cleanses.", "Ozáření nepřátelé a slizy způsobují nemoci a jedy: vezměte čištění."),
        t("Before Thermaplugg, Electrocutioner's key and the cleaning bots: kill the bots before they reach you.", "Před Thermapluggem jsou čistící roboti: zabijte je dřív, než k vám dojdou.")},
    bosses = {Grubbis = t("Comes after a trogg event at the Workshop: defend Emi Shortfuse while she opens the door, then kill Grubbis and his pet.", "Přijde po události s troggy u dílny: brante Emi Shortfuse, dokud otevírá dveře, pak zabijte Grubbise a jeho mazlíčka."),
        ["Viscous Fallout"] = t("A big slime with Disarm and corrosive ooze: cure poison and disease.", "Velký sliz s Disarmem a žíravým slizem: čistěte jed a nemoc."),
        ["Electrocutioner 6000"] = t("Chain Bolt hits several players: spread out. Drops the Workshop Key.", "Chain Bolt zasáhne více hráčů: roztáhněte se. Padá z něj Workshop Key."),
        ["Crowd Pummeler 9-60"] = t("Crowd Pummel knocks back everyone around: melee from behind, the tank keeps its back to a wall.", "Crowd Pummel odhodí všechny kolem: melee zezadu, tank zády ke zdi."),
        ["Mekgineer Thermaplugg"] = t("Bombs come out of the vents around the room: someone presses the button by each active vent to stop them; everyone else kills the bombs and the boss.", "Z otvorů kolem místnosti vylézají bomby: někdo mačká tlačítko u aktivního otvoru, ostatní zabíjí bomby a bosse.")}}

G["Razorfen Kraul"] = {classic = true, mobs = {"humanoid", "beast"}, dispel = {"poison", "curse"},
    intro = t("A quilboar warren in the southern Barrens, a thorny maze of tunnels with boars and Death's Head casters.", "Doupě kančí lidí na jihu Barrens, trnité bludiště tunelů s kanci a castery Death's Head."),
    tips = {t("Death's Head casters and geomancers: interrupt and sheep.", "Castery Death's Head a geomancery přerušujte a dávejte do ovce.")},
    bosses = {Roogug = t("A geomancer with a totem and earth spells: kill the totem.", "Geomancer s totemem a zemními kouzly: zničte totem."),
        ["Aggem Thorncurse"] = t("Heals and summons a boar: interrupt the heals, kill the boar.", "Léčí se a vyvolá kance: přerušujte léčení, zabijte kance."),
        ["Death Speaker Jargba"] = t("Mind controls a player: crowd control or carefully stun the controlled one.", "Ovládá hráče Mind Controlem: ovládaného zneškodněte crowd controlem nebo opatrně omračte."),
        ["Overlord Ramtusk"] = t("Thunderclap and adds: kill the adds first.", "Thunderclap a přidaní: nejdřív přidané."),
        ["Agathelos the Raging"] = t("A boar that enrages and knocks down: tank with cooldowns, everyone behind.", "Kanec, který se rozzuří a sráží k zemi: tank s cooldowny, ostatní za ním."),
        ["Charlga Razorflank"] = t("Chain Bolt and heals her adds: kill the adds, interrupt her heals, spread.", "Chain Bolt a léčí své přidané: zabijte je, přerušujte léčení, roztáhněte se.")}}

G["Scarlet Monastery: Graveyard"] = {classic = true, mobs = {"undead", "humanoid"}, dispel = {"magic"},
    intro = t("The Scarlet Crusade's graveyard in Tirisfal: undead and the Crusade's dead. Short wing, good for levels 30 to 35.", "Hřbitov Šarlatové výpravy v Tirisfalu: nemrtví a padlí z výpravy. Krátké křídlo, dobré pro úrovně 30 až 35."),
    bosses = {["Interrogator Vishas"] = t("Shadow Word: Pain on the tank; cast an extra heal over time.", "Shadow Word: Pain na tanka; přidejte léčení v čase."),
        ["Bloodmage Thalnos"] = t("Fire and Shadow spells and Flame Spike on the ground: interrupt, step out of the fire.", "Ohnivá a stínová kouzla a Flame Spike na zemi: přerušujte, z ohně odstupte.")}}

G["Scarlet Monastery: Library"] = {classic = true, mobs = {"humanoid", "beast"}, dispel = {"magic", "poison"},
    intro = t("The Crusade's library, full of casters and hounds.", "Knihovna výpravy, plná casterů a psů."),
    bosses = {["Houndmaster Loksey"] = t("With his dogs: kill the dogs or AoE them, then him. Bloodlust makes him faster.", "Se svými psy: zabijte nebo AoE psy, pak jeho. Bloodlust ho zrychlí."),
        ["Arcanist Doan"] = t("At half health he casts Arcane Bubble and then Detonation: run away from him when the bubble goes up, come back after the blast. Polymorphs a player too.", "Na půlce zdraví si dá Arcane Bubble a pak Detonation: když se objeví bublina, utečte od něj, po výbuchu se vraťte. Také polymorfuje hráče.")}}

G["Scarlet Monastery: Armory"] = {classic = true, mobs = {"humanoid"}, dispel = {"magic"},
    intro = t("The Crusade's barracks: warriors and trainees, then Herod.", "Kasárna výpravy: válečníci a rekruti, pak Herod."),
    bosses = {Herod = t("Whirlwind hits everyone near him: when he starts, everyone except the tank runs out. At low health he enrages and a wave of Scarlet Trainees runs in after his death: area damage or run.", "Whirlwind zasáhne všechny kolem: když začne, všichni kromě tanka utečou. Na nízkém zdraví se rozzuří a po jeho smrti přiběhne vlna Scarlet Trainees: plošné poškození, nebo utéct.")}}

G["Scarlet Monastery: Cathedral"] = {classic = true, mobs = {"humanoid"}, dispel = {"magic"},
    intro = t("The Crusade's cathedral, the hardest wing: Mograine and Whitemane at the end.", "Katedrála výpravy, nejtěžší křídlo: na konci Mograine a Whitemane."),
    tips = {t("The courtyard has many packs and patrols: pull slowly.", "Na nádvoří je hodně skupin a patrol: pullujte pomalu.")},
    bosses = {["High Inquisitor Fairbanks"] = t("Hidden behind the cathedral (optional). Dispels, fears and heals: a short fight.", "Schovaný za katedrálou (volitelný). Dispeluje, straší a léčí se: krátký souboj."),
        ["Scarlet Commander Mograine"] = t("Kill him first; then Whitemane comes in. Hammer of Justice and Divine Shield.", "Zabijte ho první; pak přijde Whitemane. Hammer of Justice a Divine Shield."),
        ["High Inquisitor Whitemane"] = t("Puts the group to sleep with Deep Sleep and resurrects Mograine: interrupt her heals, kill Mograine again quickly, then her.", "Uspí skupinu Deep Sleep a oživí Mograina: přerušujte léčení, Mograina znovu rychle zabijte, pak ji.")}}

G["Razorfen Downs"] = {classic = true, mobs = {"undead", "humanoid", "beast"}, dispel = {"disease", "curse"},
    intro = t("The quilboar warren taken by the Scourge, in the southern Barrens: undead quilboar and their necromancers.", "Doupě kančích lidí ovládnuté Pohromou na jihu Barrens: nemrtví kančí lidé a jejich nekromanti."),
    tips = {t("The gong event summons Tuten'kash after waves of spiders: the tank gathers the waves.", "Gong přivolá po vlnách pavouků Tuten'kashe: tank sbírá vlny.")},
    bosses = {["Tuten'kash"] = t("A giant spider after the gong waves: Web Spray stuns, poison on the tank.", "Obří pavouk po vlnách od gongu: Web Spray omráčí, jed na tankovi."),
        ["Plaguemaw the Rotting"] = t("Diseases the group: cure disease.", "Nakazí skupinu nemocí: čistěte nemoc."),
        ["Mordresh Fire Eye"] = t("A caster with Fireball and Fire Nova: interrupt, melee out of the nova.", "Caster s Fireballem a Fire Novou: přerušujte, melee mimo novu."),
        Glutton = t("Disease Cloud and he enrages at low health: cure, burst at the end.", "Disease Cloud a na nízkém zdraví se rozzuří: čistěte, na konci rychle."),
        ["Amnennar the Coldbringer"] = t("Frost Nova and Frostbolt; summons Frozen Spectres at low health: area damage on the spectres, tank grabs them.", "Frost Nova a Frostbolt; na nízkém zdraví vyvolá Frozen Spectres: plošné poškození na přízraky, tank je sebere.")}}
