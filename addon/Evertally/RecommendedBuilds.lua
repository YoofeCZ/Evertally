local _, A = ...
-- Factual allocations from the author's Forever talent plans, checked 2026-11-13.
-- No guide prose, tooltip text or third-party calculator code is copied.
-- The live client validates every name/rank/prerequisite before loading a plan.
A.RecommendedBuilds = {}
local names = {
  DRUID = {
    {"Improved Wrath","Genesis","Moonglow","Improved Moonfire","Nature's Majesty","Nature's Reach","Improved Entangling Roots","Nature's Splendor","Insect Swarm","Vengeance","Improved Starfire","Overgrowth","Nature's Grace","Eclipse","Moonfury","Moonkin Form"},
    {"Ferocity","Furor","Feral Swiftness","Feral Instinct","Brutal Impact","Thick Hide","Shredding Attacks","Savage Fury","Feral Charge","Sharpened Claws","Predatory Strikes","Lacerate","Predatory Discipline","Blood Frenzy","Leader of the Pack","Natural Instinct","Rend and Tear","Natural Reaction","Primal Bite","Shifting Power"},
    {"Nature's Focus","Heart of the Wild","Naturalist","Reflection","Natural Shapeshifter","Subtlety","Gift of Nature","Bloom","Tranquil Spirit","Improved Rejuvenation","Swiftmend","Nature's Swiftness","Living Spirit","Improved Tranquility","Improved Regrowth","Wild Growth"},
  },
  WARRIOR = {
    {"Improved Heroic Strike","Deflection","Improved Rend","Improved Charge","Improved Tactical Mastery","Improved Overpower","Anger Management","Deep Wounds","Spearing Strike","Two-Handed Weapon Specialization","Impale","Bloodthrill","Sweeping Strikes","Weaponmaster","Improved Slam","Improved Hamstring","Mortal Strike"},
    {"Booming Voice","Cruelty","Lingering Rage","Unbridled Wrath","Furious Precision","Piercing Howl","Blood Craze","Enrage","Dual Wield Specialization","Reckless Swings","Improved Execute","Improved Berserker Rage","Death Wish","Gore Drinker","Improved Intercept","Improved Whirlwind","Flurry","Bloodthirst"},
    {"Improved Bloodrage","Shield Specialization","Iron Will","Anticipation","Improved Revenge","Improved Thunder Clap","Last Stand","Master of Defense","Improved Disarm","Defiance","Improved Sunder Armor","Vanguard","Improved Shield Bash","Improved Shield Wall","Concussion Blow","Focused Rage","Bastion","Shield Slam"},
  },
  PALADIN = {
    {"Spiritual Focus","Divine Strength","Healing Light","Reverence","Improved Seals","Purifying Power","Divine Favor","Illumination","Holy Conduit","Divine Precision","Infusion of Light","Oath of Light","Consecrated Ground","Holy Shock","Boundless Light","Holy Power","Light's Vigil"},
    {"Divine Intellect","Redoubt","Precision","Guardian's Favor","Sacred Duty","Templar's Bulwark","Improved Hammer of Justice","Shield Specialization","Toughness","Swift Judgement","Improved Righteous Fury","Anticipation","Stoicism","Holy Shield","Reckoning","Iron Creed","Shieldsworn"},
    {"Deflection","Benediction","Improved Judgement","Conviction","Sanctified Judgement","Vindication","Unyielding Faith","Seal of Command","Pursuit of Justice","Eye for an Eye","Sacred Arbiter","Two-Handed Weapon Specialization","Turn Evil","Repentance","Vengeance","Champion of the Light","Unsealed Wrath"},
  },
  HUNTER = {
    {"Deadly Aspects","Endurance Training","Focused Fire","Improved Aspect of the Monkey","Improved Revive Pet","Pathfinding","Bestial Swiftness","Unleashed Fury","Improved Mend Pet","Ferocity","Summon Hawk","Spirit Bond","Intimidation","Bestial Discipline","Frenzy","Bestial Wrath"},
    {"Hawk Eye","Improved Concussive Shot","Lethal Attacks","Improved Stings","Efficiency","Careful Aim","Rapid Killing","Improved Arcane Shot","Lone Wolf","Trueshot Aura","Mortal Shots","Rapid Recuperation","Barrage","Scatter Shot","Ranged Weapon Specialization","Sniper Shot"},
    {"Improved Tracking","Deflection","Entrapment","Savage Strikes","Survivalist","Improved Wing Clip","Clever Traps","Surefooted","Deterrence","Survival Tactics","Predator's Edge","Counterattack","Resourcefulness","Expose Prey","Survivalist's Discipline","Strider Kick","Lightning Reflexes","Lacerating Strikes"},
  },
  ROGUE = {
    {"Improved Gouge","Remorseless Attacks","Malice","Ruthlessness","Improved Expose Armor","Improved Slice and Dice","Vigor","Blood Splatter","Lethality","Vile Poisons","Cold Blood","Improved Poisons","Relentless Strikes","Venom","Improved Kidney Shot","Seal Fate","Mutilate"},
    {"Coup de Grace","Efficient Strikes","Lightning Reflexes","Puncturing Wounds","Deflection","Precision","Improved Sprint","Endurance","Riposte","Composure","Improved Kick","Flawless Execution","Weapon Expertise","Aggression","Dual Wield Specialization","Blade Flurry","Hack and Slash","Flash of Steel","Adrenaline Rush"},
    {"Setup","Master of Deception","Opportunity","Dirty Deeds","Camouflage","Improved Ambush","Dirty Tricks","Initiative","Premeditation","Serrated Blades","Elusiveness","Ghostly Strike","Quick Getaway","Heightened Senses","Preparation","Hemorrhage","Boot Knife","Death Mark"},
  },
  PRIEST = {
    {"Power in Light","Wand Specialization","Twin Disciplines","Silent Resolve","Holy Precision","Mental Strength","Martyrdom","Mental Agility","Inner Focus","Improved Power Word: Shield","Meditation","Improved Inner Fire","Improved Mana Burn","Soul Warding","Penance","Renewed Hope","Divine Aegis","Power Infusion"},
    {"Twilight Focus","Improved Renew","Holy Specialization","Spell Warding","Divine Fury","Holy Nova","Blessed Recovery","Inspiration","Holy Reach","Improved Healing","Searing Light","Holy Binding","Litany of Light","Spirit of Redemption","Spiritual Guidance","Spiritual Healing","Prayer of Mending"},
    {"Shadow Focus","Blackout","Spirit Tap","Improved Mind Blast","Improved Shadow Word: Pain","Shadow Reach","Improved Psychic Scream","Mind Flay","Improved Mind Flay","Dark Inspiration","Vampiric Embrace","Shadow Weaving","Silence","Devouring Contagion","Early Demise","Darkness","Shadowform"},
  },
  SHAMAN = {
    {"Convection","Concussion","Elemental Devastation","Reverberation","Elemental Alacrity","Call of Flame","Elemental Focus","Elemental Warding","Trial by Fire","Eye of the Storm","Earthbound","Elemental Reach","Call of Thunder","Lightning Overload","Elemental Fury","Lightning Mastery"},
    {"Earth's Grasp","Thundering Strikes","Ancestral Knowledge","Guardian Totems","Mental Dexterity","Improved Lightning Shield","Elemental Weapons","Shamanistic Focus","Anticipation","Toughness","Flurry","Stormstrike","Improved Ghost Wolf","Spirit Weapons","Mental Quickness","Improved Stormstrike","Maelstrom Weapon","Rage of the Farseer"},
    {"Improved Healing Wave","Tidal Focus","Mindfulness","Natural Grace","Totemic Focus","Improved Reincarnation","Ancestral Healing","Healing Focus","Water Shield","Tidal Mastery","Restorative Totems","Mana Tide Totem","Healing Way","Nature's Swiftness","Purification","Riptide"},
  },
  MAGE = {
    {"Wand Specialization","Improved Channeling","Arcane Resilience","Arcane Subtlety","Magic Absorption","Arcane Concentration","Missile Barrage","Arcane Geometry","Arcane Impact","Arcane Blast","Arcane Shielding","Improved Counterspell","Arcane Meditation","Arcane Wrath","Presence of Mind","Arcane Mind","Arcane Instability","Arcane Power"},
    {"Incineration","Accelerant","Ignite","Flame Throwing","Impact","Burning Soul","Improved Flamestrike","Pyroblast","Improved Fire Blast","Improved Scorch","Improved Fire Ward","Heating Up","Master of Elements","Critical Mass","Blast Wave","Fire Power","Combustion"},
    {"Frost Warding","Improved Frostbolt","Precision","Ice Shards","Frostbite","Improved Frost Nova","Permafrost","Frost Channeling","Improved Blizzard","Ice Lance","Arctic Reach","Ice Block","Shatter","Improved Cone of Cold","Cold Snap","Fingers of Frost","Winter's Chill","Ice Barrier"},
  },
  WARLOCK = {
    {"Improved Life Tap","Suppression","Improved Corruption","Grim Reach","Soul Harvest","Improved Drains","Improved Bane of Agony","Fel Concentration","Amplify Curse","Pandemic","Malevolence","Nightfall","Curse of Exhaustion","Siphon Life","Soul Siphon","Shadow Mastery","Wrack"},
    {"Improved Health Funnel","Improved Imp","Demonic Embrace","Unholy Power","Demonic Aegis","Improved Voidwalker","Fel Vitality","Demonic Energies","Improved Sayaad","Demonic Sacrifice","Master Summoner","Decimation","Fel Domination","Demonic Brand","Improved Felhunter","Soul Link","Demonic Knowledge","Master Demonologist","Demonic Pact"},
    {"Destructive Reach","Improved Shadow Bolt","Bane","Molten Skin","Cataclysm","Aftermath","Ruin","Shadowburn","Intensity","Agonizing Flames","Conflagrate","Pyroclasm","Bane of Havoc","Fire and Brimstone","Shadow and Flame","Incinerate"},
  },
}
local function add(id,class,en,cs,role,vector)
    local ranks={};local parts={}
    for part in (vector.."-"):gmatch("(.-)-") do parts[#parts+1]=part end
    for tab,tree in ipairs(names[class]) do
        for index,name in ipairs(tree) do
            local rank=tonumber((parts[tab] or ""):sub(index,index)) or 0
            if rank>0 then ranks[#ranks+1]={name=name,rank=rank} end
        end
    end
    A.RecommendedBuilds[#A.RecommendedBuilds+1]={id=id,class=class,level=60,
        name={en=en,cs=cs},role=role,ranks=ranks,
        source={title="WoW Handbook · Forever talent plans",url="https://wowhandbook.com/classes/"..class:lower().."/talents/#build-"..id,
            checkedAt="2026-11-13",clientBuild=class=="DRUID" and "1.60.1.70790" or "1.60.1.70862"},
        note={en="Starting plan for Forever, not a guaranteed best build. Check the current client and your group role.",
              cs="Výchozí plán pro Forever, nikoli záruka nejlepšího buildu. Ověř aktuální klient a svoji roli ve skupině."}}
end
add("druid-feral-leveling","DRUID","Feral · leveling","Feral · levelování","leveling","050022-45200002123012125001-05501")
add("druid-feral-tank","DRUID","Bear · dungeon/raid tank","Medvěd · tank do dungeonů a raidů","tank","-5523033212310212551-05")
add("druid-feral-cat","DRUID","Cat · melee damage","Kočka · poškození zblízka","dps","-55230332123012125001-055")
add("druid-restoration","DRUID","Restoration · healer","Restoration · léčitel","healer","05302001--5053025153113051")
add("druid-balance","DRUID","Balance · caster damage","Balance · kouzelnické poškození","dps","5532220115501351--505")
add("warrior-protection-leveling","WARRIOR","Protection · leveling","Protection · levelování","leveling","05-051-250533120331021351")
add("paladin-retribution-leveling","PALADIN","Retribution · leveling","Retribution · levelování","leveling","05025-503-51233001201301351")
add("hunter-beast-mastery-leveling","HUNTER","Beast Mastery · leveling","Beast Mastery · levelování","leveling","0503221515121241-0053052001")
add("rogue-combat-leveling","ROGUE","Combat · leveling","Combat · levelování","leveling","02510320201-3200330112012321551")
add("priest-shadow-leveling","PRIEST","Shadow · leveling","Shadow · levelování","leveling","02500300033001-3-50512201201312051")
add("shaman-enhancement-leveling","SHAMAN","Enhancement · leveling","Enhancement · levelování","leveling","051-052030311051212251-053020001")
add("mage-arcane-frost-leveling","MAGE","Arcane/Frost · leveling","Arcane/Frost · levelování","leveling","0502052001003--052500031101331251")
add("warlock-affliction-leveling","WARLOCK","Affliction · leveling","Affliction · levelování","leveling","25500323135201351-00350002")
