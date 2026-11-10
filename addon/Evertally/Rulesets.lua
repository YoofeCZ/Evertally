local _, A = ...
-- Factual candidate NPC/name metadata only. This classifies LAST-BOSS observations,
-- never a full clear or verified timing. No encounter IDs are inferred from NPC IDs.
-- Reviewed against installed ForeverDungeonJournal data on 2026-11-09.
A.finalBosses={
    {639,"Edwin VanCleef","The Deadmines"},
    {3654,"Mutanus the Devourer","Wailing Caverns"},
    {4275,"Archmage Arugal","Shadowfang Keep"},
    {1716,"Bazil Thredd","The Stockade"},
    {4829,"Aku'mai","Blackfathom Deeps"},
    {11519,"Bazzalan","Ragefire Chasm"},
    {4421,"Charlga Razorflank","Razorfen Kraul"},
    {7800,"Mekgineer Thermaplugg","Gnomeregan"},
    {4543,"Bloodmage Thalnos","Scarlet Monastery: Graveyard"},
    {6487,"Arcanist Doan","Scarlet Monastery: Library"},
    {3975,"Herod","Scarlet Monastery: Armory"},
    {3977,"High Inquisitor Whitemane","Scarlet Monastery: Cathedral"},
    {7358,"Amnennar the Coldbringer","Razorfen Downs"},
    {2748,"Archaedas","Uldaman"},
    {7267,"Chief Ukorz Sandscalp","Zul'Farrak"},
    {12201,"Princess Theradras","Maraudon"},
    {5709,"Shade of Eranikus","Sunken Temple"},
    {9019,"Emperor Dagran Thaurissan","Blackrock Depths"},
    {9568,"Overlord Wyrmthalak","Lower Blackrock Spire"},
    {10363,"General Drakkisath","Upper Blackrock Spire"},
    {1853,"Darkmaster Gandling","Scholomance"},
    {10813,"Balnazzar","Stratholme: Living"},
    {10440,"Baron Rivendare","Stratholme: Undead"},
    {11492,"Alzzin the Wildshaper","Dire Maul: East"},
    {11486,"Prince Tortheldrin","Dire Maul: West"},
    {11501,"King Gordok","Dire Maul: North"},
    {261319,"Durgen Dirgehammer","Hall of Thanes"},
    {250657,"Rath'mael","Ruins of Lordaeron"},
    {260326,"Relic Guardian","Excavation Site: Wetlands"},
    {246020,"Shade of the Archmage","City of Dalaran"},
    {258968,"Overlord Mugg","Krol'dok Stronghold"},
    {255702,"Blazeroar","Alcaz Prison"},
    {247234,"Varrox Bleakhoof","Blackmaw Hold"},
    {261809,"Nanaya","Shaper's Terrace"},
    {260274,"Min'loth the Serpent","The Drowned City"},
}
A.finalByNpc,A.finalByName={},{}
for _,row in ipairs(A.finalBosses) do
    local rule={id="candidate-last-boss-"..row[1].."-v1",npcId=row[1],name=row[2],dungeon=row[3],ranked=false}
    A.finalByNpc[row[1]]=rule;A.finalByName[row[2]:lower()]=rule
end
A.finalByName["overseer mugg"]=A.finalByNpc[258968]
