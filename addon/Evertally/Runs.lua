local _, A = ...
-- No ruleset is ranked until verified against the live Forever client.
A.rulesets = {}
local active, firstCombat, outsideAt, encounter = nil, nil, nil, nil

local function roster()
    local levels={};local size=A.Number(A.Call(GetNumGroupMembers),0,40) or 0
    local raid=A.Call(IsInRaid)==true
    if size==0 then size=1 end
    local own=A.Number(A.Call(UnitLevel,"player"),1,100);if own then levels[#levels+1]=own end
    for i=1,(raid and size or size-1) do
        local level=A.Number(A.Call(UnitLevel,(raid and "raid" or "party")..i),1,100)
        if level then levels[#levels+1]=level end
    end
    local low,high=nil,nil
    for _,v in ipairs(levels) do low=not low and v or math.min(low,v);high=not high and v or math.max(high,v) end
    -- A full raid includes player too, so duplicate own count is not completeness proof.
    return size,low,high
end
local function checkpoint()
    if not active then return end
    active.durationMs=math.max(0,math.floor((A.Monotonic()-(firstCombat or active.clockStart))*1000))
    A.db.activeRun=A.Copy(active)
    -- Ephemeral clock is not trusted across a reload.
    if A.db.activeRun then A.db.activeRun.clockStart=nil end
end
local function payload(run)
    local out={}
    for _,key in ipairs({"runId","instanceId","name","instanceType","difficultyId","startedAt","endedAt","durationMs",
        "status","completion","rankEligible","rulesetId","groupSize","maxLevel","minLevel","deaths","bossCount","bosses"}) do
        out[key]=A.Copy(run[key])
    end
    return out
end
function A.ActiveRun() return active end
function A.CheckpointRun() checkpoint() end
function A.RestoreRun()
    active=nil;firstCombat=nil;outsideAt=nil;encounter=nil
    local old=A.db.activeRun
    if type(old)=="table" and old.runId then
        old=A.Copy(old);old.status="interrupted";old.rankEligible=false;old.endedAt=A.Now()
        local retained=payload(old);retained.character=A.Copy(old.character)
        if #A.db.runs<A.MAX_RUNS then A.db.runs[#A.db.runs+1]=retained end
        A.Record("run.interrupted",payload(old),"api_snapshot",old.character)
        A.db.activeRun=nil
    end
end
function A.FinishRun(status,completion)
    if not active then return false end
    checkpoint();local run=active;active=nil;firstCombat=nil;outsideAt=nil
    run.status=status or "manual";run.completion=completion or "unknown";run.endedAt=A.Now();run.rankEligible=false
    local p=payload(run)
    local retained=A.Copy(p);retained.character=A.Copy(run.character)
    if #A.db.runs<A.MAX_RUNS then A.db.runs[#A.db.runs+1]=retained else A.storageFull=true end
    A.db.activeRun=nil
    A.Record(run.status=="interrupted" and "run.interrupted" or "run.finished",p,run.status=="manual" and "manual" or "api_event",run.character)
    if A.ShareNow and A.db.settings.ingame then A.ShareNow() end
    A.Changed();return true
end
function A.RefreshInstance()
    local inside,kind=A.Call(IsInInstance)
    local name,instanceType,difficultyId,_,_,_,_,instanceId=A.Call(GetInstanceInfo)
    kind=A.Text(instanceType,20) or A.Text(kind,20)
    instanceId=A.Number(instanceId,1,100000)
    if inside~=true or (kind~="party" and kind~="raid") or not instanceId then
        if active then outsideAt=outsideAt or A.Monotonic() end
        return
    end
    if active and active.instanceId==instanceId and active.instanceType==kind then outsideAt=nil;return end
    if active then A.FinishRun("interrupted") end
    local size,low,high=roster()
    active={runId=A.db.producerId..":"..A.RandomId(),instanceId=instanceId,name=A.Text(name,150) or tostring(instanceId),
        character=A.Character(),
        instanceType=kind,difficultyId=A.Number(difficultyId,0,1000),startedAt=A.Now(),clockStart=A.Monotonic(),
        durationMs=0,status="visiting",completion="unknown",rankEligible=false,groupSize=size,minLevel=low,maxLevel=high,
        deaths=0,bossCount=0,bosses={}}
    firstCombat=nil;outsideAt=nil;checkpoint();A.Record("instance.entered",payload(active),"api_snapshot")
end
function A.ObserveBoss(id,name,success)
    id=A.Number(id,1,1000000);name=A.Text(name,150);success=A.Plain(success)
    if not active or not id or (success~=true and success~=1) then return end
    for _,boss in ipairs(active.bosses) do
        if boss.encounterId==id then return end
        if name and boss.name==name and math.abs(A.Now()-boss.killedAt)<15 then return end
    end
    active.bosses[#active.bosses+1]={encounterId=id,name=name or tostring(id),killedAt=A.Now()}
    active.bossCount=#active.bosses
    local rule=A.rulesets[active.instanceId]
    local candidate=name and A.finalByName and A.finalByName[name:lower()]
    if rule and rule.lastEncounterId==id then
        active.rulesetId=rule.id
        -- Candidate rules may classify observed last-boss completion, never competitive speed.
        A.FinishRun("completed","last_boss")
    elseif candidate and active.instanceType=="party" then
        active.rulesetId=candidate.id;active.name=candidate.dungeon
        A.FinishRun("completed","last_boss")
    else checkpoint();A.Changed() end
end
A.On("PLAYER_ENTERING_WORLD",A.RefreshInstance)
A.On("ZONE_CHANGED_NEW_AREA",A.RefreshInstance)
A.On("PLAYER_REGEN_DISABLED",function()
    if not active then A.RefreshInstance() end
    if active and not firstCombat then firstCombat=A.Monotonic();active.startedAt=A.Now();checkpoint() end
end)
local function observeDead(unit)
    unit=A.Text(unit,30)
    if not active or not unit or active.instanceType~="party" or A.Call(UnitIsDeadOrGhost,unit)~=true then return end
    local npc=A.CreatureId and A.CreatureId(A.Call(UnitGUID,unit))
    local rule=npc and A.finalByNpc and A.finalByNpc[npc]
    if not rule then return end
    active.rulesetId=rule.id;active.name=rule.dungeon;active.bossCount=math.max(1,active.bossCount)
    A.FinishRun("completed","last_boss")
end
A.On("UNIT_HEALTH",function(unit) observeDead(unit) end)
A.On("PLAYER_TARGET_CHANGED",function() observeDead("target") end)
A.On("LOOT_OPENED",function() observeDead("target") end)
A.On("PLAYER_REGEN_ENABLED",function() checkpoint();A.Changed() end)
A.On("PLAYER_DEAD",function() if active then active.deaths=active.deaths+1;checkpoint() end end)
A.On("GROUP_ROSTER_UPDATE",function()
    if active then
        local size,low,high=roster();active.groupSize=math.max(active.groupSize or 1,size)
        if low then active.minLevel=active.minLevel and math.min(active.minLevel,low) or low end
        if high then active.maxLevel=active.maxLevel and math.max(active.maxLevel,high) or high end
        checkpoint()
    end
end)
A.On("BOSS_KILL",function(id,name) A.ObserveBoss(id,name,1) end)
A.On("ENCOUNTER_START",function(id,name)
    id=A.Number(id,1,1000000);if id then encounter={id=id,name=A.Text(name,150),clock=A.Monotonic()} end
end)
A.On("ENCOUNTER_END",function(id,name,_,_,success)
    id=A.Number(id,1,1000000);success=A.Number(success,0,1)
    if active and id then
        local ms=encounter and encounter.id==id and math.max(0,math.floor((A.Monotonic()-encounter.clock)*1000)) or nil
        A.Record("raid.encounter_finished",{encounterId=id,name=A.Text(name,150),success=success==1,
            durationMs=ms,instanceId=active.instanceId,instanceName=active.name})
    end
    A.ObserveBoss(id,name,success);encounter=nil
end)
A.On("PLAYER_LOGOUT",checkpoint)
if C_Timer and type(C_Timer.NewTicker)=="function" then
    C_Timer.NewTicker(5,function()
        if A.db then
            if active and outsideAt and A.Monotonic()-outsideAt>900 then A.FinishRun("interrupted")
            else checkpoint() end
            if A.RefreshUI then A.RefreshUI() end
        end
    end)
end
