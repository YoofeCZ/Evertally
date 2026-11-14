local _, A = ...
-- UI-only identity assets. Never adds fields to saved/exported observations.
local UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Forever's second UnitName return is a surname. Keep realm handling separate.
function A.UnitPlayerName(unit)
    local first,second=A.Call(UnitName,unit)
    first=A.Text(first,100);second=A.Text(second,100)
    if not first then return nil end
    local interface=A.Game().interface or 0
    local forever=interface>=16000 and interface<20000
    local complete=A.Text(A.Call(GetUnitName,unit,false),160)
    if forever then
        if not complete then
            complete=first
            if second and second~="" and first:sub(-#second)~=second then complete=first.." "..second end
        end
        return complete,A.Text(A.Call(GetRealmName),100)
    end
    local _,realm=A.Call(UnitFullName,unit)
    return complete or first,A.Text(realm,100) or second
end
local classes = {
    [1]={"WARRIOR", "Warrior", "Válečník", {0.78,0.61,0.43}, {0,0.25,0,0.25}},
    [2]={"PALADIN", "Paladin", "Paladin", {0.96,0.55,0.73}, {0,0.25,0.5,0.75}},
    [3]={"HUNTER", "Hunter", "Lovec", {0.67,0.83,0.45}, {0,0.25,0.25,0.5}},
    [4]={"ROGUE", "Rogue", "Zloděj", {1,0.96,0.41}, {0.49609375,0.7421875,0,0.25}},
    [5]={"PRIEST", "Priest", "Kněz", {1,1,1}, {0.49609375,0.7421875,0.25,0.5}},
    [6]={"DEATHKNIGHT", "Death Knight", "Rytíř smrti", {0.77,0.12,0.23}},
    [7]={"SHAMAN", "Shaman", "Šaman", {0,0.44,0.87}, {0.25,0.49609375,0.25,0.5}},
    [8]={"MAGE", "Mage", "Mág", {0.25,0.78,0.92}, {0.25,0.49609375,0,0.25}},
    [9]={"WARLOCK", "Warlock", "Černokněžník", {0.53,0.53,0.93}, {0.7421875,0.98828125,0.25,0.5}},
    [10]={"MONK", "Monk", "Mnich", {0,1,0.6}},
    [11]={"DRUID", "Druid", "Druid", {1,0.49,0.04}, {0.7421875,0.98828125,0,0.25}},
    [12]={"DEMONHUNTER", "Demon Hunter", "Lovec démonů", {0.64,0.19,0.79}},
    [13]={"EVOKER", "Evoker", "Vyvolávač", {0.2,0.58,0.5}},
}
-- Blizzard's original 4x4 CharacterCreate race texture. The male portrait is a
-- representative race emblem; no historical character gender is inferred.
local races = {
    [1]={"human", "Human", "Člověk", {0,0.25,0,0.25}},
    [2]={"orc", "Orc", "Ork", {0.75,1,0.25,0.5}},
    [3]={"dwarf", "Dwarf", "Trpaslík", {0.25,0.5,0,0.25}},
    [4]={"nightelf", "Night Elf", "Noční elf", {0.75,1,0,0.25}},
    [5]={"undead", "Undead", "Nemrtvý", {0.25,0.5,0.25,0.5}},
    [6]={"tauren", "Tauren", "Tauren", {0,0.25,0.25,0.5}},
    [7]={"gnome", "Gnome", "Gnóm", {0.5,0.75,0,0.25}},
    [8]={"troll", "Troll", "Troll", {0.5,0.75,0.25,0.5}},
    [9]={"goblin", "Goblin", "Goblin"}, [10]={"bloodelf", "Blood Elf", "Krvavý elf"},
    [11]={"draenei", "Draenei", "Draenei"}, [22]={"worgen", "Worgen", "Worgen"},
    [24]={"pandaren", "Pandaren", "Pandaren"}, [25]={"pandaren", "Pandaren", "Pandaren"}, [26]={"pandaren", "Pandaren", "Pandaren"},
    -- The Skyborne races new in Forever (UnitRace ids as in QuestieDB raceMaskById). The game has no Czech
    -- names, so both languages keep the English ones; without an atlas they fall back to the question mark.
    [95]={"highorderskyborne", "High Order Skyborne", "High Order Skyborne"}, [96]={"windshaperskyborne", "Windshaper Skyborne", "Windshaper Skyborne"},
}
local function localized(info)
    return info and info[A.db and A.db.settings.language == "cs" and 3 or 2] or A.L("unknown")
end
function A.ClassIdFromFile(file)
    file=A.Text(file,40);if not file then return nil end
    for id,info in pairs(classes) do if info[1]==file then return id end end
end
function A.ClassName(id) return localized(classes[A.Number(id,1,100)]) end
function A.RaceName(id) return localized(races[A.Number(id,1,100)]) end
function A.ClassColor(id)
    local info=classes[A.Number(id,1,100)]
    local color=info and type(RAID_CLASS_COLORS)=="table" and RAID_CLASS_COLORS[info[1]]
    return color and {color.r,color.g,color.b} or info and info[4] or {0.97,0.97,0.97}
end
local function texture(tex,path,coords)
    local ok,result=pcall(tex.SetTexture,tex,path)
    if not ok or result==false then tex:SetTexture(UNKNOWN);tex:SetTexCoord(0.08,0.92,0.08,0.92);return false end
    tex:SetTexCoord(unpack(coords or {0,1,0,1}));return true
end
local function atlas(tex,name)
    if type(tex.SetAtlas)~="function" or not C_Texture or type(C_Texture.GetAtlasInfo)~="function" then return false end
    if not A.Call(C_Texture.GetAtlasInfo,name) then return false end
    local ok,result=pcall(tex.SetAtlas,tex,name,false)
    return ok and result~=false
end
function A.SetClassIcon(tex,id)
    local info=classes[A.Number(id,1,100)]
    if not info then return texture(tex,UNKNOWN,{0.08,0.92,0.08,0.92}) end
    if atlas(tex,"classicon-"..info[1]:lower()) then return true end
    local coords=type(CLASS_ICON_TCOORDS)=="table" and CLASS_ICON_TCOORDS[info[1]] or info[5]
    if coords then return texture(tex,"Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes",coords) end
    return texture(tex,UNKNOWN,{0.08,0.92,0.08,0.92})
end
function A.SetRaceIcon(tex,id)
    local info=races[A.Number(id,1,100)]
    if not info then return texture(tex,UNKNOWN,{0.08,0.92,0.08,0.92}) end
    if atlas(tex,"raceicon-"..info[1].."-male") or atlas(tex,"raceicon128-"..info[1].."-male") then return true end
    if info[4] then return texture(tex,"Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",info[4]) end
    return texture(tex,UNKNOWN,{0.08,0.92,0.08,0.92})
end
function A.IdentityText(character)
    if type(character)~="table" then return A.L("unknown") end
    local bits={}
    if character.level then bits[#bits+1]=A.L("level").." "..tostring(character.level) end
    if character.raceId then bits[#bits+1]=A.RaceName(character.raceId) end
    if character.classId then bits[#bits+1]=A.ClassName(character.classId) end
    return table.concat(bits," · ")
end
