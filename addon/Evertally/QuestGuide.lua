local _, A = ...
-- Evertally's own computed quest itinerary. The catalogue contains reference facts,
-- never an authored or claimed play-tested levelling route.
local Q = {}
A.QuestGuide = Q
local revision, routeCache, planCache, completed, completedReady, scheduled = 1, nil, nil, {}, false, false
local completedOwner, observedActive = nil, {}
local lastNavigated
local function data() return type(A.questGuideData)=="table" and A.questGuideData or {quests={},raceBits={}} end
local function rows() return data().quests or {} end
local function list(v) return type(v)=="table" and v or {} end
local function call(fn,...) return A.Call(fn,...) end
local function known(id)
    if type(id)~="number" then return nil end
    local book=C_SpellBook
    local bank=Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local answer=book and call(book.IsSpellKnown,id,bank)
    if type(answer)~="boolean" and book then answer=call(book.IsSpellInSpellBook,id,bank,false) end
    if type(answer)~="boolean" then answer=call(IsPlayerSpell,id) end
    if type(answer)~="boolean" then answer=call(IsSpellKnown,id,false) end
    if type(answer)=="boolean" then return answer end
    return nil
end
function Q.Context()
    local c=A.Character() or {}
    local _,_,race=call(UnitRace,"player")
    local _,_,class=call(UnitClass,"player")
    local map=call(C_Map and C_Map.GetBestMapForUnit,"player")
    return {id=c.id or "unknown",level=call(UnitLevel,"player") or c.level or 1,
        raceId=race or c.raceId,classId=class or c.classId,faction=call(UnitFactionGroup,"player"),map=map}
end
function Q.Store()
    if not A.db then return nil end
    A.db.settings=A.db.settings or {}
    local s=A.db.settings
    if type(s.questGuide)~="table" then s.questGuide={characters={}} end
    if type(s.questGuide.characters)~="table" then s.questGuide.characters={} end
    local id=Q.Context().id
    if type(s.questGuide.characters[id])~="table" then s.questGuide.characters[id]={skipped={},done={},history={},includeClass=true,includeDungeons=false} end
    local state=s.questGuide.characters[id]
    for _,key in ipairs({"skipped","done","history"}) do if type(state[key])~="table" then state[key]={} end end
    if type(state.includeClass)~="boolean" then state.includeClass=true end
    return state
end
local function bitPresent(mask,bit)
    return type(mask)=="number" and type(bit)=="number" and bit>0 and math.floor(mask/bit)%2>=1
end
Q.BitPresent=bitPresent
function Q.Visible(quest,context,state)
    context=context or Q.Context();state=state or Q.Store() or {}
    if type(quest)~="table" then return false,"missing" end
    if quest.faction and context.faction~=quest.faction then return false,"faction" end
    if quest.raceMask and quest.raceMask>0 and not bitPresent(quest.raceMask,(data().raceBits or {})[context.raceId]) then return false,"race" end
    if quest.classMask and quest.classMask>0 then
        if not context.classId or not bitPresent(quest.classMask,2^(context.classId-1)) then return false,"class" end
        if state.includeClass==false then return false,"class_off" end
    end
    if quest.dungeon and state.includeDungeons~=true then return false,"dungeon_off" end
    if quest.maxLevel and quest.maxLevel>0 and context.level>quest.maxLevel then return false,"max_level" end
    return true
end
local function refreshCompleted()
    local owner=Q.Context().id
    if completedOwner~=owner then completedOwner=owner;completed={};completedReady=false;observedActive={} end
    if completedReady then return end
    completedReady=true
    local values=call(C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs)
    for key,value in pairs(list(values)) do
        local id=type(value)=="number" and value or value==true and tonumber(key)
        if id then completed[id]=true end
    end
end
function Q.State(id)
    local state=Q.Store();refreshCompleted()
    if completed[id] or state and state.done[id] then return "done" end
    local log=C_QuestLog
    local done=log and call(log.IsQuestFlaggedCompleted,id)
    if done==true then completed[id]=true;return "done" end
    local on=log and call(log.IsOnQuest,id)
    if type(on)~="boolean" then
        local index=log and call(log.GetLogIndexForQuestID,id)
        if type(index)=="number" then on=index>0 end
    end
    if type(on)~="boolean" and observedActive[id] then on=true end
    if type(on)~="boolean" then
        local count=log and call(log.GetNumQuestLogEntries)
        if type(count)=="number" then
            on=false
            for index=1,math.min(count,200) do
                local info=call(log.GetInfo,index)
                if type(info)=="table" and info.questID==id and info.isHeader~=true then on=true;break end
            end
        end
    end
    if on~=true then return on==false and "available" or "unknown" end
    local complete=call(log and log.IsComplete,id)
    if complete==true then return "turnin" end
    local objectives=call(log and log.GetQuestObjectives,id)
    if type(objectives)=="table" and #objectives>0 then
        local all=true
        for _,objective in ipairs(objectives) do if objective.finished~=true then all=false end end
        if all then return "turnin" end
    end
    return "objectives"
end
local function prerequisite(id)
    if type(id)~="number" or id<=0 then return false,"unverified_requirement" end
    return Q.State(id)=="done","prerequisite"
end
local function skillValue(id)
    local info=call(C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID,id)
    return type(info)=="table" and A.Number(info.skillLevel,0) or nil
end
local function reputation(id)
    local info=call(C_Reputation and C_Reputation.GetFactionDataByID,id)
    return type(info)=="table" and A.Number(info.currentStanding or info.barValue) or nil
end
function Q.Available(quest,context)
    context=context or Q.Context()
    local visible,why=Q.Visible(quest,context)
    if not visible then return false,why end
    local state=Q.State(quest.id)
    if state=="done" then return false,"done" end
    if state=="objectives" or state=="turnin" then return true,state end
    if context.level<(quest.minLevel or 1) then return false,"level" end
    if quest.dynamic then return false,"dynamic" end
    for _,id in ipairs(list(quest.requiresAll)) do local ok,reason=prerequisite(id);if not ok then return false,reason end end
    if #list(quest.requiresAny)>0 then
        local one=false
        for _,id in ipairs(quest.requiresAny) do if prerequisite(id) then one=true;break end end
        if not one then return false,"prerequisite" end
    end
    for _,id in ipairs(list(quest.exclusive)) do local other=Q.State(id);if other=="done" or other=="objectives" or other=="turnin" then return false,"exclusive" end end
    if quest.untilCompleted and Q.State(quest.untilCompleted)=="done" then return false,"exclusive" end
    if quest.parentQuest then
        local other=Q.State(quest.parentQuest)
        if other~="objectives" and other~="turnin" then return false,"prerequisite" end
    end
    if quest.nextQuest then
        local other=Q.State(quest.nextQuest)
        if other=="done" or other=="objectives" or other=="turnin" then return false,"exclusive" end
    end
    if quest.startingWith then
        local other=Q.State(quest.startingWith)
        if other~="done" and other~="objectives" and other~="turnin" then return false,"prerequisite" end
    end
    if quest.disabledBy then local other=Q.State(quest.disabledBy);if other=="objectives" or other=="turnin" then return false,"exclusive" end end
    if type(quest.requiredSkill)=="table" then
        local value=skillValue(quest.requiredSkill[1]);if not value or value<(quest.requiredSkill[2] or 0) then return false,"skill" end
    end
    if #list(quest.requiredRanks)>0 then
        -- Source ranks are not ordinary skill point requirements. Do not invent an equivalence.
        return false,"unverified_requirement"
    end
    if quest.requiredSpell then
        if quest.requiredSpell<0 then return false,"unverified_requirement" end
        if known(quest.requiredSpell)~=true then return false,"spell" end
    end
    if quest.requiredSpec then
        if quest.requiredSpec<1000 then
            if not skillValue(quest.requiredSpec) then return false,"skill" end
        elseif known(quest.requiredSpec)~=true then return false,"spell" end
    end
    if type(quest.requiredMinRep)=="table" then local value=reputation(quest.requiredMinRep[1]);if not value or value<quest.requiredMinRep[2] then return false,"reputation" end end
    if type(quest.requiredMaxRep)=="table" then local value=reputation(quest.requiredMaxRep[1]);if not value or value>=quest.requiredMaxRep[2] then return false,"reputation" end end
    for _,id in ipairs(list(quest.sourceItems)) do
        local count=call(C_Item and C_Item.GetItemCount or GetItemCount,id,false,false)
        if type(count)~="number" or count<=0 then return false,"item" end
    end
    -- An unavailable quest-log API never proves acceptance or completion. Reference
    -- eligibility may still be displayed as the next pickup, with runtime state unknown.
    return true,"accept"
end
function Q.Invalidate()
    revision=revision+1;planCache=nil;routeCache=nil
end
function Q.ResetCache()
    completed={};completedReady=false;completedOwner=nil;observedActive={};Q.Invalidate()
end
local function signature(context,state)
    return table.concat({context.id,context.level,context.raceId or "?",context.classId or "?",context.faction or "?",context.map or "?",state.includeClass==false and 0 or 1,state.includeDungeons and 1 or 0,revision},":")
end
local LEVEL_LEGS={{1,6},{6,10},{10,15},{15,20},{20,25},{25,30},{30,35},{35,40},{40,45},{45,50},{50,55},{55,60}}
local function questLeg(quest)
    local level=quest.level and quest.level>0 and quest.level or quest.minLevel
    if type(level)~="number" or level<1 then return nil end
    level=math.max(level,quest.minLevel or 1)
    for _,leg in ipairs(LEVEL_LEGS) do if level<=leg[2] then return leg[1],leg[2] end end
    return 55,60
end
function Q.Routes(query)
    local context,state=Q.Context(),Q.Store();if not state then return {} end
    refreshCompleted()
    local key=signature(context,state)
    if not routeCache or routeCache.key~=key then
        local groups={}
        for id,quest in pairs(rows()) do
            local minimum,maximum=questLeg(quest)
            if quest.map and minimum and Q.Visible(quest,context,state) then
                local routeKey=tostring(quest.map)..":"..minimum..":"..maximum
                local group=groups[routeKey]
                if not group then group={key=routeKey,map=quest.map,name=quest.zone or tostring(quest.map),minLevel=minimum,maxLevel=maximum,total=0,done=0,suitable=0,ids={}};groups[routeKey]=group end
                group.ids[#group.ids+1]=id;group.total=group.total+1
                if completed[id] or state.done[id] then group.done=group.done+1 end
                if context.level>=(quest.minLevel or 1) and not completed[id] and not state.done[id] then group.suitable=group.suitable+1 end
            end
        end
        local routes={};for _,group in pairs(groups) do
            table.sort(group.ids)
            local canonical=(data().zoneLevels or {})[group.map]
            local levelAppropriate=context.level>=group.minLevel and context.level<=group.maxLevel and group.suitable>0
            if type(canonical)=="table" then levelAppropriate=levelAppropriate and context.level>=canonical[1] and context.level<=canonical[2]+2 end
            group.candidate=levelAppropriate
            group.recommendation=(levelAppropriate and 0 or 1000)+(group.map==context.map and -100 or 0)+math.abs(context.level-(group.minLevel+group.maxLevel)/2)-math.min(25,group.suitable)*0.1
            local geometry=data().zoneGeometry or {}
            local here,there=geometry[context.map],geometry[group.map]
            if here and there then
                if here.continent~=there.continent then group.recommendation=group.recommendation+200
                elseif type(here.rect)=="table" and type(there.rect)=="table" then
                    local dx=(here.rect[1]+here.rect[2]-there.rect[1]-there.rect[2])/2
                    local dy=(here.rect[3]+here.rect[4]-there.rect[3]-there.rect[4])/2
                    group.recommendation=group.recommendation+math.sqrt(dx*dx+dy*dy)*100
                end
            end
            routes[#routes+1]=group
        end
        table.sort(routes,function(a,b) if a.recommendation~=b.recommendation then return a.recommendation<b.recommendation end return a.name<b.name end)
        local suggested=0
        for _,group in ipairs(routes) do group.recommended=group.candidate and suggested<3;if group.recommended then suggested=suggested+1 end end
        routeCache={key=key,routes=routes}
    end
    query=type(query)=="string" and query:lower() or ""
    if query=="" then return routeCache.routes end
    local filtered={};for _,route in ipairs(routeCache.routes) do if route.name:lower():find(query,1,true) or tostring(route.map)==query then filtered[#filtered+1]=route end end
    return filtered
end
function Q.SelectRoute(map)
    local state=Q.Store();if not state then return false end
    for _,route in ipairs(Q.Routes()) do if route.key==map or type(map)=="number" and route.map==map then state.map=route.map;state.routeKey=route.key;state.selected=nil;planCache=nil;return true end end
    return false
end
function Q.SetOption(key,value)
    local state=Q.Store();if not state then return false end
    if key~="includeClass" and key~="includeDungeons" and key~="autoNavigate" and key~="tracker" then return false end
    state[key]=value==true
    if key=="includeClass" or key=="includeDungeons" then state.selected=nil;Q.Invalidate() end
    return true
end
local function targetFor(quest,phase)
    local candidates=phase=="accept" and quest.starts or phase=="turnin" and quest.ends or quest.objectives
    local objectives=phase=="objectives" and call(C_QuestLog and C_QuestLog.GetQuestObjectives,quest.id)
    local all={}
    for _,person in ipairs(list(candidates)) do
        local finished=false
        for _,objective in ipairs(list(objectives)) do
            local kind=objective.type=="monster" and "npc" or objective.type
            if objective.objectID==person.id and (not kind or kind==person.kind) and objective.finished==true then finished=true end
        end
        if not finished then
            for _,spot in ipairs(list(person.spots)) do all[#all+1]={map=spot.map,x=spot.x,y=spot.y,label=person.name or quest.title} end
        end
    end
    return all
end
function Q.Plan()
    local state=Q.Store();if not state then return {steps={},locked={},total=0,done=0} end
    local context=Q.Context();local routes=Q.Routes()
    if not state.map and routes[1] then state.map=routes[1].map;state.routeKey=routes[1].key end
    local key=signature(context,state)..":"..tostring(state.routeKey or state.map)
    if planCache and planCache.key==key then return planCache.model end
    local route
    for _,candidate in ipairs(routes) do if candidate.key==state.routeKey or not state.routeKey and candidate.map==state.map then route=candidate;break end end
    if not route and routes[1] then route=routes[1];state.map=route.map;state.routeKey=route.key end
    local ids,seen={},{}
    local function include(id,depth)
        local quest=rows()[id]
        if seen[id] or not quest or depth>40 or #ids>=800 or not Q.Visible(quest,context,state) then return end
        seen[id]=true
        if Q.State(id)~="done" then
            for _,required in ipairs(list(quest.requiresAll)) do if required>0 then include(required,depth+1) end end
            local anyMet=false
            for _,required in ipairs(list(quest.requiresAny)) do if prerequisite(required) then anyMet=true;break end end
            if not anyMet then
                local selected
                for _,required in ipairs(list(quest.requiresAny)) do
                    local alternative=rows()[required]
                    if alternative and Q.Visible(alternative,context,state) then
                        local status=Q.State(required)
                        if not selected then selected=required end
                        if status=="objectives" or status=="turnin" then selected=required;break end
                    end
                end
                if selected then include(selected,depth+1) end
            end
        end
        ids[#ids+1]=id
    end
    for _,id in ipairs(route and route.ids or {}) do include(id,0) end
    local model={steps={},locked={},total=#ids,done=0,route=route,skipped=0}
    for _,id in ipairs(ids) do
        local quest=rows()[id]
        local phase=Q.State(id)
        if phase=="done" then model.done=model.done+1 else
            local available,reason=Q.Available(quest,context)
            if available then
                local step={questId=id,quest=quest,phase=reason,key=tostring(id)..":"..reason,targets=targetFor(quest,reason)}
                if state.skipped[step.key] then model.skipped=model.skipped+1 else model.steps[#model.steps+1]=step end
            else model.locked[#model.locked+1]={quest=quest,reason=reason} end
        end
    end
    local priority={turnin=1,objectives=2,accept=3}
    table.sort(model.steps,function(a,b)
        local ap,bp=priority[a.phase] or 4,priority[b.phase] or 4
        if ap~=bp then return ap<bp end
        local al,bl=a.quest.level or 1,b.quest.level or 1
        if al~=bl then return al<bl end
        return a.questId<b.questId
    end)
    planCache={key=key,model=model}
    return model
end
function Q.Current()
    local state=Q.Store();local model=Q.Plan()
    if state and state.selected then for index,step in ipairs(model.steps) do if step.key==state.selected then return step,index end end end
    return model.steps[1],1
end
function Q.SelectStep(key)
    local state=Q.Store();if not state then return false end
    for _,step in ipairs(Q.Plan().steps) do if step.key==key then
        if state.selected then state.history[#state.history+1]=state.selected;if #state.history>50 then table.remove(state.history,1) end end
        state.selected=key;return true
    end end
    return false
end
function Q.Next()
    local _,index=Q.Current();local steps=Q.Plan().steps
    if steps[index+1] then return Q.SelectStep(steps[index+1].key) end
    return false
end
function Q.Back()
    local state=Q.Store();if not state then return false end
    while #state.history>0 do
        local key=table.remove(state.history)
        for _,step in ipairs(Q.Plan().steps) do if step.key==key then state.selected=key;return true end end
    end
    local _,index=Q.Current();local step=Q.Plan().steps[index-1]
    if step then state.selected=step.key;return true end
    return false
end
function Q.Skip()
    local state,step=Q.Store(),Q.Current();if not state or not step then return false end
    state.skipped[step.key]=true;state.selected=nil;planCache=nil;return true
end
function Q.Resume()
    local state=Q.Store();if not state then return false end
    state.skipped={};state.selected=nil;planCache=nil;return true
end
function Q.Navigate()
    local step=Q.Current();if not step or #step.targets==0 then return false,"no_coordinates" end
    local map,x,y=A.PlayerPosition()
    local best,distance
    for _,spot in ipairs(step.targets) do
        if spot.map==map and type(x)=="number" and type(y)=="number" then
            local d=(x-spot.x)^2+(y-spot.y)^2
            if not distance or d<distance then best,distance=spot,d end
        end
    end
    if not best then
        if A.LoadGuide then A.LoadGuide() end
        local nearest=A.map and A.map.NearestLayerSpot and A.map.NearestLayerSpot(step.targets)
        best=nearest or step.targets[1]
    end
    if not A.NavigateToPoint then return false,"no_navigation" end
    local ok,reason=A.NavigateToPoint(best.label or step.quest.title,best.map,best.x,best.y,{view="questguide",questId=step.questId,step=step.phase})
    if ok then lastNavigated=step.key end
    return ok,reason
end
local function changed()
    Q.Invalidate()
    if scheduled then return end
    scheduled=true
    local function update()
        scheduled=false
        local state=Q.Store()
        if state and state.autoNavigate and lastNavigated then local step=Q.Current();if step and step.key~=lastNavigated then Q.Navigate() end end
        if A.QuestGuideRefreshTracker then A.QuestGuideRefreshTracker() end
        if A.questGuidePage and A.questGuidePage:IsShown() and A.RefreshUI then A.RefreshUI() end
    end
    if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(0.2,update) else update() end
end
Q.Changed=changed
A.On("QUEST_TURNED_IN",function(id)
    id=tonumber(id);local state=Q.Store();if id and state then state.done[id]=true;completed[id]=true;state.selected=nil end
    changed()
end)
A.On("QUEST_ACCEPTED",function(first,id)
    refreshCompleted();id=tonumber(id) or tonumber(first);if id then observedActive[id]=true end
    local state=Q.Store();if state then state.selected=nil end;changed()
end)
A.On("QUEST_REMOVED",function(id) id=tonumber(id);if id then observedActive[id]=nil end;changed() end)
for _,event in ipairs({"QUEST_LOG_UPDATE","PLAYER_LEVEL_UP","SPELLS_CHANGED","SKILL_LINES_CHANGED","UPDATE_FACTION"}) do A.On(event,changed) end
A.On("PLAYER_ENTERING_WORLD",function() completedReady=false;changed() end)
