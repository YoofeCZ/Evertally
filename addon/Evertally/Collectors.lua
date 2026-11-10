local _, A = ...
local recently={}
local function once(key,seconds)
    local now=A.Monotonic();if recently[key] and now-recently[key]<seconds then return false end
    recently[key]=now;return true
end
function A.CreatureId(guid)
    guid=A.Text(guid,150);if not guid then return nil end
    local kind,_,_,_,_,id=string.match(guid,"^([^-]+)%-([^-]+)%-([^-]+)%-([^-]+)%-([^-]+)%-([^-]+)")
    if kind~="Creature" and kind~="Vehicle" then return nil end
    return A.Number(tonumber(id),1,10000000)
end
function A.PlayerPosition()
    if not C_Map then return nil end
    local map=A.Number(A.Call(C_Map.GetBestMapForUnit,"player"),1,100000)
    if not map then return nil end
    local pos=A.Call(C_Map.GetPlayerMapPosition,map,"player")
    if not pos then return map end
    local x,y
    local method=A.Field(pos,"GetXY")
    if type(method)=="function" then x,y=A.Call(method,pos) else x,y=A.Field(pos,"x"),A.Field(pos,"y") end
    x=A.Number(x,0,1);y=A.Number(y,0,1)
    if not x or not y or (x==0 and y==0) then return map end
    return map,x,y
end
local function interactionUnit()
    if A.Call(UnitExists,"npc")==true then return "npc" end
    return nil -- A target might be unrelated to the open interaction.
end
local function observeNpc()
    local unit=interactionUnit();if not unit then return end
    local id=A.CreatureId(A.Call(UnitGUID,unit));if not id or not once("npc:"..id,60) then return end
    local map,x,y=A.PlayerPosition()
    A.Record("npc.observed",{npcId=id,name=A.Text(A.Call(UnitName,unit),150),level=A.Number(A.Call(UnitLevel,unit),1,100),
        mapId=map,x=x,y=y,positionMethod=x and "player_interaction" or "unknown"},"api_snapshot")
end
local function character(kind)
    local c=A.Character();if not c then return end
    A.Record(kind or "character.snapshot",{name=c.name,realm=c.realm,classId=c.classId,raceId=c.raceId,level=c.level},"api_snapshot")
end
A.On("PLAYER_LOGIN",function() character();A.RefreshInstance() end)
local lastZone
local function visitZone()
    if not C_Map then return end
    local map=A.Number(A.Call(C_Map.GetBestMapForUnit,"player"),1,100000)
    if not map or lastZone==map then return end
    lastZone=map
    local info=A.Call(C_Map.GetMapInfo,map)
    A.Record("zone.visited",{mapId=map,mapSystem="ui_map",mapName=A.Text(A.Field(info,"name"),150)},"api_snapshot")
end
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","ZONE_CHANGED_NEW_AREA","ZONE_CHANGED","ZONE_CHANGED_INDOORS"}) do A.On(event,visitZone) end
A.On("PLAYER_LEVEL_UP",function(level)
    local c=A.Character();if not c then return end
    c.level=A.Number(level,1,100) or c.level
    A.Record("character.level",{name=c.name,realm=c.realm,classId=c.classId,raceId=c.raceId,level=c.level})
end)
for _,event in ipairs({"GOSSIP_SHOW","QUEST_DETAIL","QUEST_PROGRESS","QUEST_COMPLETE","MERCHANT_SHOW","TRAINER_SHOW"}) do A.On(event,observeNpc) end
local function quest(kind,id,xp,money)
    id=A.Number(id,1,10000000);if not id then return end
    local title=C_QuestLog and A.Text(A.Call(C_QuestLog.GetTitleForQuestID,id),200)
    local unit=interactionUnit();local npc=unit and A.CreatureId(A.Call(UnitGUID,unit))
    local map,x,y=A.PlayerPosition()
    A.Record(kind,{questId=id,title=title,xp=A.Number(xp,0),money=A.Number(money,0),npcId=npc,mapId=map,x=x,y=y})
end
A.On("QUEST_ACCEPTED",function(first,id) id=A.Plain(id);if id==nil then id=A.Plain(first) end;quest("quest.accepted",id) end)
A.On("QUEST_TURNED_IN",function(id,xp,money) quest("quest.turned_in",id,xp,money) end)
-- QUEST_REMOVED can also be a completed quest disappearing. Capture explicit abandon intent instead.
if type(hooksecurefunc)=="function" and C_QuestLog and type(C_QuestLog.AbandonQuest)=="function" then
    pcall(hooksecurefunc,C_QuestLog,"AbandonQuest",function()
        local id=A.Call(C_QuestLog.GetAbandonQuest);quest("quest.abandoned",id)
    end)
end
A.On("MERCHANT_SHOW",function()
    local unit=interactionUnit();local npc=unit and A.CreatureId(A.Call(UnitGUID,unit));if not npc then return end
    local count=A.Number(A.Call(GetMerchantNumItems),0,500);if not count then return end
    local items={}
    for i=1,math.min(count,200) do
        local link=A.Text(A.Call(GetMerchantItemLink,i),500)
        local id=link and tonumber(link:match("item:(%d+)"))
        local name,_,price,quantity=A.Call(GetMerchantItemInfo,i)
        if id then items[#items+1]={itemId=id,name=A.Text(name,150),price=A.Number(price,0),quantity=A.Number(quantity,0)} end
    end
    local map,x,y=A.PlayerPosition()
    A.Record("vendor.snapshot",{npcId=npc,name=A.Text(A.Call(UnitName,unit),150),items=items,mapId=map,x=x,y=y},"api_snapshot")
end)

local lootPending,lastLootAt={},0
A.On("LOOT_OPENED",function()
    lootPending={};lastLootAt=A.Monotonic()
    local n=A.Number(A.Call(GetNumLootItems),0,300) or 0
    for slot=1,n do
        local link=A.Text(A.Call(GetLootSlotLink,slot),500);local id=link and tonumber(link:match("item:(%d+)"))
        if id then
            local ok,sources=pcall(function() return {GetLootSourceInfo(slot)} end)
            local sourceId,certain=nil,false
            if ok and type(sources)=="table" then
                local plain=A.Copy(sources)
                if plain and #plain==2 then sourceId=A.CreatureId(plain[1]);certain=sourceId~=nil end
            end
            lootPending[id]={sourceNpcId=sourceId,sourceCertain=certain,sourceKind=certain and "corpse" or "unknown"}
        end
    end
end)
local function selfLootMessage(message)
    for _,key in ipairs({"LOOT_ITEM_SELF","LOOT_ITEM_SELF_MULTIPLE","LOOT_ITEM_PUSHED_SELF","LOOT_ITEM_PUSHED_SELF_MULTIPLE",
        "LOOT_ITEM_CREATED_SELF","LOOT_ITEM_CREATED_SELF_MULTIPLE"}) do
        local format=A.Text(_G[key],1000)
        if format then
            local pattern=format:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1")
            pattern=pattern:gsub("%%%%s","(.-)"):gsub("%%%%d","(%%d+)")
            if message:match("^"..pattern.."$") then return true,key:find("CREATED")~=nil end
        end
    end
    return false
end
A.On("CHAT_MSG_LOOT",function(message)
    message=A.Text(message,2048)
    -- Match Blizzard's localized self-only templates; never compare a recipient's player name.
    if not message then return end
    local mine,created=selfLootMessage(message)
    if not mine then return end
    local id=tonumber(message:match("item:(%d+)"));if not id then return end
    local quantity=tonumber(message:match("|h|r?%s*x(%d+)")) or tonumber(message:match("x(%d+)%.?$")) or 1
    local name=message:match("|h%[(.-)%]|h")
    -- "You create: X" (conjured food, crafted items) is not loot from the world.
    local source=created and {sourceKind="craft",sourceCertain=true} or (A.Monotonic()-lastLootAt<30 and lootPending[id] or nil)
    A.Record("loot.received",{itemId=id,name=name,quantity=quantity,sourceNpcId=source and source.sourceNpcId,
        sourceCertain=source and source.sourceCertain or false,sourceKind=source and source.sourceKind or "unknown"})
end)

local currentProfession,craftRecipe,craftAt=nil,nil,nil
-- TRADE_SKILL_LIST_UPDATE fires repeatedly; record a snapshot only when its content changes.
local professionSeen,cooldownSeen={},{}
local function profession()
    if not C_TradeSkillUI then return end
    if A.Call(C_TradeSkillUI.IsTradeSkillLinked)==true or A.Call(C_TradeSkillUI.IsTradeSkillGuild)==true then return end
    local info=A.Call(C_TradeSkillUI.GetBaseProfessionInfo)
    local id=A.Number(A.Field(info,"professionID"),1,1000000)
    if not id then return end
    currentProfession=id
    if not once("profession:"..id,10) then return end
    local ids=A.Call(C_TradeSkillUI.GetAllRecipeIDs);if type(ids)~="table" then return end
    local recipes={};local count=A.Number(A.Call(function() return #ids end),0,100000) or 0;local idSum=0
    for i=1,math.min(count,600) do
        local recipeId=A.Number(A.Field(ids,i),1,10000000)
        if recipeId then
            local recipe=A.Call(C_TradeSkillUI.GetRecipeInfo,recipeId)
            if A.Field(recipe,"learned")==true then
                recipes[#recipes+1]={recipeId=recipeId,name=A.Text(A.Field(recipe,"name"),150),learned=true};idSum=idSum+recipeId
                local seconds=A.Number(A.Call(C_TradeSkillUI.GetRecipeCooldown,recipeId),0,31536000)
                local readyAt=seconds and seconds>0 and A.Now()+seconds or nil
                if readyAt and (not cooldownSeen[recipeId] or math.abs(cooldownSeen[recipeId]-readyAt)>60) then
                    cooldownSeen[recipeId]=readyAt;A.Record("cooldown.snapshot",{recipeId=recipeId,readyAt=readyAt},"api_snapshot")
                end
            end
        end
    end
    local skill=A.Number(A.Field(info,"skillLevel"),0,10000);local maxSkill=A.Number(A.Field(info,"maxSkillLevel"),0,10000)
    local signature=table.concat({skill or "-",maxSkill or "-",#recipes,idSum},":")
    if professionSeen[id]==signature then return end
    professionSeen[id]=signature
    A.Record("profession.snapshot",{professionId=id,name=A.Text(A.Field(info,"professionName"),150),
        skill=skill,maxSkill=maxSkill,recipes=recipes},"api_snapshot")
end
for _,event in ipairs({"TRADE_SKILL_SHOW","TRADE_SKILL_LIST_UPDATE","TRADE_SKILL_DATA_SOURCE_CHANGED"}) do A.On(event,profession) end
A.On("TRADE_SKILL_CRAFT_BEGIN",function(recipe)
    craftRecipe=A.Number(recipe,1,10000000);craftAt=A.Monotonic()
end)
A.On("TRADE_SKILL_ITEM_CRAFTED_RESULT",function(data)
    if not craftRecipe or not craftAt or A.Monotonic()-craftAt>120 then return end
    local item=A.Number(A.Field(data,"itemID"),1,10000000);local quantity=A.Number(A.Field(data,"quantity"),1,100000)
    if not item or not quantity or A.Field(data,"firstCraftReward")==true then return end
    -- Match the intended recipe output to avoid counting ancillary rewards as crafts.
    local schematic=C_TradeSkillUI and A.Call(C_TradeSkillUI.GetRecipeSchematic,craftRecipe,false)
    local expected=A.Number(A.Field(schematic,"outputItemID"),1,10000000)
    if expected~=item then return end
    A.Record("craft.result",{recipeId=craftRecipe,itemId=item,quantity=quantity,professionId=currentProfession})
end)
