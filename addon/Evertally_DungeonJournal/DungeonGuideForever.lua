local M = _G.Evertally.map -- (Evertally_DungeonJournal: a module of Evertally_Map's pages since 2026-11-20)
-- Boss tactics for Forever's own dungeons, written in our own words from the facts (abilities, adds, what to avoid) in the guides
-- published for Forever in November 2026: Wowhead's dungeon overviews and Warcraft Tavern's Shaper's Terrace guide. Nothing is
-- quoted. Loaded after DungeonGuideNew.lua: a boss here replaces its general advice there; `published` tells the page so.
local G = M.dungeonGuides
local function t(en, cs) return {en = en, cs = cs} end
local function add(dungeon, bosses, tips)
    local guide = G[dungeon] or {}
    G[dungeon] = guide
    guide.published = true
    guide.bosses = guide.bosses or {}
    for name, tactic in pairs(bosses) do guide.bosses[name] = tactic end
    for _, tip in ipairs(tips or {}) do guide.tips = guide.tips or {}; table.insert(guide.tips, 1, tip) end
end

add("Hall of Thanes", {
    ["Faldrim Anvilmar"] = t("Patrols the middle of Anvilmar's Rest. Clear your side of the room first, wait until he walks over and pull him alone: a simple fight.\nHe casts Mind Blast and puts a 10-minute Curse of Anvilmar on the tank: remove it after the fight.",
        "Hlídkuje uprostřed Anvilmar's Rest. Nejdřív vyčisti svou stranu místnosti, počkej, až dojde k vám, a stáhni ho samotného: jednoduchý souboj.\nSesílá Mind Blast a tankovi dá na 10 minut Curse of Anvilmar: po souboji ji sundejte."),
    Magmatus = t("Comes with a Dark Iron Summoner. Tank: drag the boss away from the group. Everyone else: kill the Summoner first, then the boss.\nHe pulses a fire nova around himself and casts Combust on a random player: a healing check, keep everyone topped up.",
        "Má u sebe Dark Iron Summonera. Tank: odtáhni bosse od skupiny. Ostatní: nejdřív zabijte Summonera, pak bosse.\nKolem sebe pulzuje ohnivou novou a na náhodného hráče sesílá Combust: zkouška healera, držte všechny nahoře."),
    Plunder = t("Patrols his corridor and has a single ability, a knockback. Pull him to a spot where nobody can be thrown into another pack, and stand with your backs to a wall or corner.",
        "Hlídkuje ve své chodbě a má jedinou schopnost, odhození. Stáhni ho tam, kde nikoho neodhodí do další skupiny, a stůjte zády ke zdi nebo v rohu."),
    ["Durgen Dirgehammer"] = t("Final boss, with two Lesser Stone Golems; Dark Iron Looters stand around the room. Kill all the Looters before the pull.\nHe fears the whole group and puts Rend on the tank: kill the golems one at a time, use stuns, and the healer watches the tank.",
        "Poslední boss se dvěma Lesser Stone Golemy; po okraji místnosti stojí Dark Iron Looteři. Všechny Lootery zabijte před pullem.\nStraší celou skupinu (fear) a tankovi dává Rend: golemy zabíjejte po jednom, používejte stuny a healer hlídá tanka."),
}, {t("Dark Iron Engineers throw bombs at a spot chosen when the throw starts: step out and they never hit. Kill the Looters in a pack first, they hit fast.",
    "Dark Iron Engineeři hází bomby na místo zvolené na začátku hodu: ustup a nikdy netrefí. Ve skupině zabíjejte nejdřív Lootery, bijí rychle.")})

add("Ruins of Lordaeron", {
    ["The Baron"] = t("Hits hard and has Knockout: a big instant hit that also drops threat. With the tank not at full health it can kill him, so heal the tank up and stun the boss to stop it.",
        "Tvrdě bije a má Knockout: velkou okamžitou ránu, která navíc shodí aggro. Když tank není na plném zdraví, může ho zabít: držte tanka nahoře a stunujte bosse, ať ho nepoužije."),
    Witherfang = t("Patrols King's Alley with two spiders: kill the spiders first. Then tank and spank; cleanse Leech Poison from the tank.",
        "Hlídkuje v King's Alley se dvěma pavouky: nejdřív zabijte pavouky. Pak už jen tank and spank; z tanka čistěte Leech Poison."),
    ["The Abandoned"] = t("At the start of Market Street the statue sends three waves of adds before he comes out. He casts Frost Nova, chills anyone who hits him in melee and drains life from the tank: melee keep an eye on the slow, the healer on the tank.",
        "Na začátku Market Street pošle socha tři vlny nepřátel, pak vyjde on. Sesílá Frost Novu, zpomalí každého, kdo ho bije zblízka, a vysává život tankovi: melee pozor na zpomalení, healer na tanka."),
    Bjork = t("Only a very short Anti-Magic Shield: casters wait a second, otherwise a quick tank and spank.",
        "Jen velmi krátký Anti-Magic Shield: casteři chvilku počkají, jinak rychlý tank and spank."),
    ["Rath'mael"] = t("Only Flamestrike, always on the spot where the tank stood when the cast began: everyone steps out the moment he starts it. A stun stops it altogether. Edward Heartweaver for the quest is by him.",
        "Jen Flamestrike, vždy na místo, kde stál tank na začátku sesílání: jakmile ho začne, všichni ven. Stun ho zastaví úplně. Edward Heartweaver pro quest je u něj."),
    ["Viktor the Vile"] = t("Light the fire in the chimney of the house south-west in Lordamere Overlook, by the graveyard: five waves of adds, then Viktor. Hard melee and the same Leech Poison as Witherfang: let the tank build threat first and cleanse the poison.",
        "Zapal oheň v krbu domu na jihozápadě Lordamere Overlook u hřbitova: pět vln nepřátel, pak Viktor. Silné rány zblízka a stejný Leech Poison jako Witherfang: nech tanka nabrat aggro a čistěte jed."),
}, {t("Shrieking Banshees silence and Flesh Golems knock back: pull the Overlook carefully so nobody lands in the next pack. Ghouls come in threes and fours and hit hard.",
    "Shrieking Banshee umlčují a Flesh Golemové odhazují: v Overlooku tahejte opatrně, ať nikdo nepřistane v další skupině. Ghoulové chodí po třech až čtyřech a tvrdě bijí.")})

add("Excavation Site: Wetlands", {
    Saltspine = t("Easy once the area around him is clear. Tendon Rip slows the tank a lot but changes nothing in the fight.",
        "Snadný, když je okolí vyčištěné. Tendon Rip tanka hodně zpomalí, na souboji to ale nic nemění."),
    Shadetooth = t("With two Thicket Hunters: three at once is too much unless you outlevel it. Keep the hunters in crowd control (or one controlled while you kill the other) and dispel Infected Wound fast.\nAlone he uses Rend and Terrifying Roar, a 5-second fear you cannot dispel: clear the area first, a feared player who runs into the grass pulls more raptors.",
        "Se dvěma Thicket Huntery: všichni tři naráz jsou moc, pokud nejste přelevelovaní. Huntery držte v crowd controlu (nebo jednoho, zatímco zabíjíte druhého) a rychle čistěte Infected Wound.\nSám pak dává Rend a Terrifying Roar, 5sekundový fear, který nejde zrušit: okolí vyčistěte předem, vystrašený hráč, co vběhne do trávy, přitáhne další raptory."),
    ["Relic Guardian"] = t("Start it with the Archival Panel on its right. A gear and level check: lots of health and heavy hits on the tank. Thunderclap hits everyone within 10 yards and slows movement and attacks: ranged and healer stay away.",
        "Spustíš ho Archival Panelem vpravo od něj. Zkouška výbavy a úrovně: hodně zdraví a tvrdé rány do tanka. Thunderclap zasáhne všechny do 10 yardů a zpomalí pohyb i útoky: ranged a healer stojí dál."),
}, {t("The trash before Saltspine: Thicket Lurkers hide in the tall grass, and pulling one can bring up to three more. Pull from the edge of the grass, never from the middle.",
    "Trash před Saltspinem: Thicket Lurkeři se skrývají ve vysoké trávě a pull jednoho může přivést až tři další. Tahejte z okraje trávy, nikdy ze středu.")})

add("City of Dalaran", {
    ["Atrexis the Grave Knight"] = t("An easy first boss that raises non-elite Skeletons: kill them as they come. Only AoE before the tank has threat gets people killed here.",
        "Snadný první boss, který vyvolává ne-elitní kostlivce: zabíjejte je průběžně. Zabít tu může jen AoE dřív, než má tank aggro."),
    ["Arcane Anomaly"] = t("Focal Blast is an arcane beam that sweeps the room counter-clockwise: move with it, standing in it kills. Small adds wait at the edge: stay inside the circle on the platform. Arcane Bolt on the tank.",
        "Focal Blast je arkánový paprsek, který přejíždí místnost proti směru hodinových ručiček: pohybujte se před ním, kdo v něm stojí, umře. Na okraji čekají malí nepřátelé: zůstaňte uvnitř kruhu na plošině. Na tanka Arcane Bolt."),
    ["Arcanic Enigma"] = t("Starts with two Mana Phantoms: burn them first, their Mana Burn drains a lot. He keeps making Arcane Manalings (cleave them) but no more Phantoms.\nManamorph locks a player for 8 seconds: dispel magic. He silences everyone near him: the healer stands far away.",
        "Začíná se dvěma Mana Phantomy: spalte je jako první, jejich Mana Burn hodně vysává. Průběžně vyvolává Arcane Manalingy (cleave), další Phantomy už ne.\nManamorph vyřadí hráče na 8 sekund: dispel magie. Umlčí všechny poblíž: healer stojí daleko."),
    ["Unstable Sentinel"] = t("One mechanic, Malfunction: a short wind-up, then heavy damage to everyone within 25 yards. Ranged and healer stay at maximum range all fight, melee run out at the wind-up.",
        "Jedna mechanika, Malfunction: krátké nabíjení, pak velké poškození všem do 25 yardů. Ranged a healer celou dobu na maximální vzdálenosti, melee při nabíjení vybíhají ven."),
    ["Mana Devourer"] = t("Outside the Violet Hold. A race against your mana: Debilitate hits everyone within 45 yards and drains 200 mana, Drain Vitality burns the tank for 10 seconds. Immune to arcane. Kill it fast, keep everyone topped up.",
        "Před Violet Hold. Závod s vaší manou: Debilitate zasáhne všechny do 45 yardů a vezme 200 many, Drain Vitality pálí tanka 10 sekund. Imunní vůči arkánu. Zabijte ho rychle a držte všechny nahoře."),
    ["Fel Ancient"] = t("Talk to the NPCs in the town centre to drop the wall around him. Entangle roots two players and hurts them; Fel Timbers leaves green pools. Never stay rooted in a pool: Blessing of Freedom or Escape Artist.",
        "Promluv s NPC uprostřed města, zmizí zeď kolem něj. Entangle znehybní dva hráče a zraňuje je; Fel Timbers nechává zelené louže. Nikdy nezůstaň znehybněný v louži: Blessing of Freedom nebo Escape Artist."),
    ["Lyn the Ignored"] = t("A hidden boss: use the Tome of Dalaran (from the Black Tome in Shadowfang Keep) on the purple rune in the side room straight on in the sewers, past the first boss.\nShadow Bolt Volley hits the group hard; Curse of Thorns makes your own attacks hurt you (bad for melee and rogues): remove the curse. Raise Dead adds two skeletons.",
        "Skrytý boss: použij Tome of Dalaran (z Black Tome ze Shadowfang Keep) na fialovou runu v boční místnosti rovně v kanálech, za prvním bossem.\nShadow Bolt Volley tvrdě zasahuje skupinu; Curse of Thorns způsobí, že vaše vlastní útoky zraňují vás (špatné pro melee a rogue): kletbu sundávejte. Raise Dead přidá dva kostlivce."),
    ["Shade of the Archmage"] = t("Final boss in the Purple Parlor (an NPC opens the portal from the tower). He spends mana on his spells; when it runs out he Mass Polymorphs the group and Evocates back to full.\nArcane Bolt on the tank, Arcane Explosion within 20 yards (casters at maximum range), Bounding Mana flies to one player and hits everyone in its path: spread out. Stay in the room to the end.",
        "Poslední boss v Purple Parlor (portál z věže otevře NPC). Kouzla platí manou; když dojde, dá skupině Mass Polymorph a Evokací se dobije.\nNa tanka Arcane Bolt, Arcane Explosion do 20 yardů (casteři na maximální vzdálenost), Bounding Mana letí k jednomu hráči a zasáhne každého v cestě: rozestupte se. Zůstaňte v místnosti až do konce."),
}, {t("Almost everything here is immune to arcane: Arcane Explosion, Arcane Shot and Counterspell do nothing. Interrupt the Mana Phantoms' Mana Burn, and stand in the mana pool a Saturated Remnant leaves behind.",
    "Skoro všechno je tu imunní vůči arkánu: Arcane Explosion, Arcane Shot ani Counterspell nefungují. Přerušujte Mana Burn Mana Phantomů a stoupněte si do louže many, kterou po sobě nechá Saturated Remnant.")})

add("The Drowned City", {
    ["Zul'Alai"] = t("Heavy physical damage on the tank. Monstrous Slam stuns everyone near him for 3 seconds (he stands still while casting: melee step out), Rotted Strike slows: dispel the tank first.\nAt 30% Undying Oath: 30% faster attacks and 3% health back every 5 seconds. Save cooldowns and burst for that.",
        "Velké fyzické poškození do tanka. Monstrous Slam omráčí všechny poblíž na 3 sekundy (při sesílání stojí: melee odstoupí), Rotted Strike zpomaluje: dispel nejdřív tankovi.\nNa 30 % Undying Oath: o 30 % rychlejší útoky a každých 5 sekund 3 % zdraví zpět. Na to si šetřete cooldowny a burst."),
    Gill = t("On the way to the Primeval Elemental in the Deep Archives. Throws dynamite at the tank; simple unless pulled with the trash next to him.",
        "Na cestě k Primeval Elementalovi v Deep Archives. Hází dynamit na tanka; jednoduchý, pokud ho nestáhnete i s trashem vedle."),
    ["Primeval Elemental"] = t("Optional, in the water tunnels to the right of the Deep Archives. Kill the Undying Offerings to wake him. Waterbolt on the tank, Freeze Water on everyone: easy, just watch your breath and surface when needed.",
        "Volitelný, ve vodních tunelech vpravo od Deep Archives. Zabijte Undying Offeringy, tím ho probudíte. Waterbolt na tanka, Freeze Water na všechny: snadný, jen hlídejte dech a vyplavte se, když je potřeba."),
    ["Captain Dreadrise"] = t("Clear around him first, patrols join easily. Embrine traps a random player (the tank too) in an Abyssal Bubble: kill the bubble before they drown. Interrupt Waterbolt Volley. Click the Glowing Pearl afterwards to open the barrier.",
        "Nejdřív vyčistěte okolí, patroly se snadno přidají. Embrine uvězní náhodného hráče (i tanka) v Abyssal Bubble: zabijte bublinu, než se utopí. Waterbolt Volley přerušujte. Potom klikněte na Glowing Pearl, otevře bariéru."),
    ["Var'Taka"] = t("With two Brinescale Priestesses who heal and cast Frostbolt: kill or control them first (Polymorph, Sap). Harpoon pulls a random player to him and he cleaves in front: tank faces him away. Click the Glowing Pearl afterwards.",
        "Se dvěma Brinescale Priestess, které léčí a sesílají Frostbolt: nejdřív je zabijte nebo dejte do crowd controlu (Polymorph, Sap). Harpoon přitáhne náhodného hráče k němu a dopředu dává cleave: tank ho otočí od skupiny. Potom klikněte na Glowing Pearl."),
    ["Deathless Marrow"] = t("Bloodbolt hits everyone, and Deathless Guardians and Sorcerers keep coming until he dies. Kill the Guardians first (Shield Slam stuns), cleave the rest while you damage the boss, and use crowd control: fighting only the adds loses.",
        "Bloodbolt zasahuje všechny a Deathless Guardiani a Sorcereři přicházejí, dokud boss nezemře. Guardiany zabíjejte první (Shield Slam omračuje), zbytek cleavujte při poškozování bosse a používejte crowd control: kdo bojuje jen s přídavky, prohraje."),
    ["Min'loth the Serpent"] = t("Two phases. As a troll: Drench hits the tank hard, Deluge is a channel that hurts the whole group. At 0% he turns into a serpent with full health: Poison Bolt Volley on everyone (cleanse fast) and a fear on a random player. The fight ends at 0% in serpent form.",
        "Dvě fáze. Jako troll: Drench tvrdě zasahuje tanka, Deluge je sesílání, které zraňuje celou skupinu. Na 0 % se změní v hada s plným zdravím: Poison Bolt Volley na všechny (rychle čistit) a fear na náhodného hráče. Souboj končí na 0 % v hadí podobě."),
}, nil)

add("Krol'dok Stronghold", {
    ["Slavecrusher Grox"] = t("Patrols the mines: clear the gnolls in one area before the pull. Bloodlust (30% faster attacks for 30 s) and Knockdown on the tank. He calls Redridge Prisoners in: non-elite, kill them fast, then the boss.",
        "Hlídkuje v dolech: před pullem vyčistěte gnolly v jedné části. Bloodlust (o 30 % rychlejší útoky na 30 s) a Knockdown na tanka. Přivolává Redridge Prisonery: ne-elitní, rychle je zabijte, pak bosse."),
    ["Twilight Commander Zarmok"] = t("Patrols among Twilight's Hammer: kill them until you can pull him alone. Rending Whirl hurts everyone within 8 yards a lot: ranged and healer away, melee out when he spins. He enrages.",
        "Hlídkuje mezi Twilight's Hammer: zabíjejte je, dokud ho nestáhnete samotného. Rending Whirl hodně zraní všechny do 8 yardů: ranged a healer dál, melee ven, když se točí. Umí se rozzuřit."),
    ["War Handler Ashka"] = t("With her wolves Snarlfang and Terrorhowl: kill the wolves first, stuns help. Command: Kill sends the wolves at a random player for 10 seconds. Without the wolves an easy fight.",
        "Se svými vlky Snarlfang a Terrorhowl: vlky zabijte první, pomáhají stuny. Command: Kill pošle vlky na 10 sekund na náhodného hráče. Bez vlků snadný souboj."),
    ["Nar'gurk"] = t("With a Shadowhide Curseweaver and two Twilight Warlocks: control them (Polymorph, Sap, Fear) or kill them first. Shadow Bolt Volley on the group; Convert mind-controls a player: bring them to 50% health and it breaks.",
        "S Shadowhide Curseweaverem a dvěma Twilight Warlocky: dejte je do crowd controlu (Polymorph, Sap, Fear) nebo je zabijte první. Shadow Bolt Volley na skupinu; Convert ovládne hráče: srazte ho na 50 % zdraví a kouzlo spadne."),
    ["Bossman Toof"] = t("Engaging the Centurions at the start of the bridge makes him send two Krol'dok Brutes again and again: a rogue's Distract buys time. He stands with two Shamans (control them). Let one more wave of Brutes come and die, then pull.\nHe is a warrior: Mortal Strike, Thunderclap, Demoralizing Shout. Mortal Strike with many adds up is deadly.",
        "Když napadnete Centuriony na začátku mostu, začne opakovaně posílat po dvou Krol'dok Brutech: Distract od rogua získá čas. Stojí se dvěma Shamany (crowd control). Nechte přijít a padnout ještě jednu vlnu Brutů, pak pull.\nJe to warrior: Mortal Strike, Thunderclap, Demoralizing Shout. Mortal Strike s mnoha přídavky naživu je smrtelný."),
    ["Overlord Mugg"] = t("Final boss with two Krol'dok Centurions: control them or kill them one by one first, their damage is large. Crushing Slam leaps to a random player and knocks back everyone nearby. Mugg's Fury stacks attack speed until he changes weapons (maces, then mauls): the tank needs cooldowns toward the end.",
        "Poslední boss se dvěma Krol'dok Centuriony: dejte je do crowd controlu nebo je nejdřív zabijte po jednom, dávají hodně. Crushing Slam skočí na náhodného hráče a odhodí všechny poblíž. Mugg's Fury zrychluje útoky, dokud nevymění zbraně (palice, pak kladiva): tank potřebuje ke konci cooldowny."),
}, {t("Twilight Grunts are the most dangerous trash: an 8-yard Bladestorm and Sunder Armor. Stun them, control any beyond two. Twilight Outriders net the tank for 10 s from range: pull them around a corner. Twilight Peons run to warn others: kill them first.",
    "Twilight Grunti jsou nejnebezpečnější trash: Bladestorm na 8 yardů a Sunder Armor. Stunujte je, třetího a dalšího dejte do crowd controlu. Twilight Outrideři chytí tanka na 10 s do sítě z dálky: tahejte je za roh. Twilight Peoni běží varovat ostatní: zabíjejte je první.")})

add("Alcaz Prison", {
    ["Tidemistress Ca'zass"] = t("With two Strashaz Enchantresses: kill or control them first. Frostbolt Volley hits everyone, Frost Nova roots and she drops Blizzard on herself: dispel the roots and move her out of the Blizzard.",
        "Se dvěma Strashaz Enchantress: nejdřív je zabijte nebo dejte do crowd controlu. Frostbolt Volley zasáhne všechny, Frost Nova znehybní a sama na sebe sesílá Blizzard: znehybnění dispelujte a bosse z Blizzardu vytáhněte."),
    ["Overseer Wrex"] = t("Patrols three prison chambers and calls every add in them when pulled: sneak past and clear all three chambers first. Mortal Strike on the tank cuts healing by 50% for 5 s; Battle Shout at the start.",
        "Hlídkuje u tří vězeňských komor a při pullu svolá všechny nepřátele v nich: proplížte se a nejdřív vyčistěte všechny tři komory. Mortal Strike na tanka sníží léčení o 50 % na 5 s; na začátku Battle Shout."),
    ["Katerina the Cleaner"] = t("With two Alcaz Chaplains who heal: control them or kill them first. Grievous Garrote hits a random player and keeps bleeding until they are healed above 90%. Deadly Poison on the tank: dispel it at once.",
        "Se dvěma Alcaz Chaplainy, kteří léčí: crowd control, nebo je zabijte první. Grievous Garrote zasáhne náhodného hráče a krvácí, dokud ho nevyléčíte nad 90 %. Deadly Poison na tankovi: hned dispelovat."),
    ["The Questioner"] = t("Kill him last, after the rest of the prison. Pull some of the adds in his chamber before him. Rend and Drain Life (dispellable): a simple fight.",
        "Zabijte ho až nakonec, po zbytku vězení. Část nepřátel v jeho komoře stáhněte před ním. Rend a Drain Life (jde dispelovat): jednoduchý souboj."),
    ["Zarla Ober"] = t("Final boss in two phases. As a human: Fireball and Flamestrike. At 30% she reveals her dragon form, Blazeroar, with full health: Searing Scales hurt everyone all the time, Flame Breath and Thrash hit the tank very hard, and she fears all but the tank. Tank: defensive cooldowns, potion and healthstone ready.",
        "Poslední bosska ve dvou fázích. Jako člověk: Fireball a Flamestrike. Na 30 % odhalí dračí podobu Blazeroar s plným zdravím: Searing Scales neustále zraňují všechny, Flame Breath a Thrash velmi tvrdě zasahují tanka a všechny kromě tanka zastraší (fear). Tank: připravit cooldowny, lektvar a healthstone."),
}, {t("Strashaz Soldiers charge anyone 8 yards or more away: stand behind them, close. Interrupt or dispel the Enchantresses' Polymorph and Frostbolt Volley. Alcaz Chaplains heal: always kill them first.",
    "Strashaz Soldieři se vrhají na každého dál než 8 yardů: stůjte těsně za nimi. Polymorph a Frostbolt Volley od Enchantress přerušujte nebo dispelujte. Alcaz Chaplaini léčí: vždy je zabíjejte první.")})

add("Shaper's Terrace", {
    Titanosaur = t("A devilsaur patrolling the wide paved road. Clear everything near its path: it fears the group, and a feared player running into a pack ruins the fight. A shaman's Tremor Totem makes it easy.",
        "Devilsaur, který hlídkuje po široké dlážděné cestě. Vyčistěte všechno u jeho trasy: straší skupinu (fear) a vystrašený hráč, který vběhne do skupiny nepřátel, souboj pokazí. Tremor Totem od šamana ho velmi usnadní."),
    Cinder = t("Summoned with 15 Red Power Crystals at the Archival Panel on the mountain in the west. Clear the fire elementals around it first; fire resistance (a paladin's aura) helps.",
        "Vyvolá se 15 Red Power Crystaly u Archival Panelu na hoře na západě. Nejdřív vyčistěte ohnivé elementály okolo; pomůže odolnost proti ohni (aura paladina)."),
    Snowtalon = t("Summoned with 15 Blue Power Crystals in the cave behind the left waterfall in the north-west. Pull it out of the cave first. Frost Nova plus Cone of Cold hurt: the tank faces it away from the group.",
        "Vyvolá se 15 Blue Power Crystaly v jeskyni za levým vodopádem na severozápadě. Nejdřív ho vytáhněte z jeskyně. Frost Nova a Cone of Cold bolí: tank ho otočí od skupiny."),
    ["Izha'Rel and Tor'Rel"] = t("Two raptors on the northern path near the Green panel cave: Tor'Rel fire, Izha'Rel ice with Frost Armor. Kill Tor'Rel first. Low on health they call Ravasaur Stalkers: the tank picks them up.",
        "Dva raptoři na severní cestě u jeskyně se zeleným panelem: Tor'Rel ohnivý, Izha'Rel ledový s Frost Armorem. Nejdřív zabijte Tor'Rela. Když mají málo zdraví, přivolají Ravasaur Stalkery: tank je sebere."),
    Vitrix = t("Summoned with 15 Green Power Crystals in the cave in the north. At release it killed whole groups in one hit: putting the crystals in is enough to progress, so you can skip the fight.",
        "Vyvolá se 15 Green Power Crystaly v jeskyni na severu. Po vydání zabíjel celé skupiny jednou ranou: k postupu stačí krystaly vložit, souboj se dá vynechat."),
    ["Direhorn Matriarch"] = t("On the eastern edge. Clear the adds first. Nobody behind her (tail sweep); she charges random players, so stand together at her sides.",
        "Na východním okraji. Nejdřív vyčistěte přídavky. Nikdo za ní (úder ocasem); vrhá se na náhodné hráče, tak stůjte pohromadě po jejích stranách."),
    Thunderhoof = t("A thunder lizard on the southern rim. Interrupt its lightning casts; nature resistance helps if you cannot.",
        "Hromová ještěrka na jižním okraji. Přerušujte její blesková kouzla; když nejde, pomůže odolnost proti přírodě."),
    Venomridge = t("In the tar pits south of the Achromatic Crystal. Poisons the whole group again and again: a shaman's Poison Cleansing Totem makes it trivial, otherwise cleanse or heal through.",
        "V dehtových jámách jižně od Achromatic Crystal. Znovu a znovu otráví celou skupinu: Poison Cleansing Totem od šamana z toho udělá hračku, jinak čistěte nebo léčte."),
    Bolt = t("Summoned with 15 Yellow Power Crystals behind Venomridge. Instant Chain Lightning on random players: ranged and healer spread out so it does not jump, and heal through it.",
        "Vyvolá se 15 Yellow Power Crystaly za Venomridgem. Okamžitý Chain Lightning na náhodné hráče: ranged a healer se rozestoupí, ať nepřeskakuje, a prostě se to doléčí."),
    Nanaya = t("Final boss: after all four Archival Panels, use the Titan Panel on the Pillar of Assimilation (two Stone Guardians at the entrance). She draws power from the crystals around her and gains their spells (Blizzard from blue, Chain Lightning from yellow…) and stuns nearby players now and then. Spectacular but easy.",
        "Poslední bosska: po všech čtyřech Archival Panelech použijte Titan Panel na Pillar of Assimilation (u vstupu dva Stone Guardiani). Bere sílu z krystalů kolem sebe a získává jejich kouzla (Blizzard z modrého, Chain Lightning ze žlutého…) a občas omráčí hráče poblíž. Velkolepé, ale snadné."),
}, {t("The goal: put 15 Power Crystals of each colour into the four Archival Panels (red west on the mountain, blue behind the north-west waterfall, green in the northern cave, yellow behind Venomridge), then summon Nanaya. Crystals can be gathered inside too, at the cost of more trash. The dinosaur bosses are optional and in any order. Falling off the edge by the lake throws you out of the dungeon.",
    "Cíl: do čtyř Archival Panelů vložit po 15 Power Crystalech každé barvy (červený na západě na hoře, modrý za vodopádem na severozápadě, zelený v jeskyni na severu, žlutý za Venomridgem) a pak vyvolat Nanayu. Krystaly jde nasbírat i uvnitř, za cenu víc trashe. Dinosauří bossové jsou volitelní a v libovolném pořadí. Kdo spadne z okraje u jezera, vypadne z dungeonu.")})
