local _, A = ...
-- Run-local observations. Never reset the game's meter or read secret values.
-- Native session IDs prevent pre-dungeon combat leaking into a run. Snapshots
-- replace a session's earlier snapshot instead of counting an update twice.
local C = {}
A.Combat = C
local state
local pending={}
local metrics={damage="DamageDone",healing="HealingDone",absorbs="Absorbs",damageTaken="DamageTaken",interrupts="Interrupts",dispels="Dispels",deaths="Deaths"}

local function member(unit)
    local guid=A.Text(A.Call(UnitGUID,unit),100)
    if not guid then return end
    local name,realm=A.Call(UnitFullName,unit)
    name=A.Text(name,100) or A.Text(A.Call(UnitName,unit),100)
    realm=A.Text(realm,100)
    local _,_,class=A.Call(UnitClass,unit);local _,_,race=A.Call(UnitRace,unit)
    return {guid=guid,name=name and (realm and realm~="" and name.."-"..realm or name) or guid,
        classId=A.Number(class,1,100),raceId=A.Number(race,1,100),level=A.Number(A.Call(UnitLevel,unit),1,1000),role=A.Text(A.Call(UnitGroupRolesAssigned,unit),20)}
end

function C.Roster(run)
    if not run then return end
    local map={};for _,p in ipairs(run.roster or {}) do map[p.guid]=p end
    local memberCount=0;for _ in pairs(map) do memberCount=memberCount+1 end
    local units={"player"}
    local raid=A.Call(IsInRaid)==true
    local count=A.Number(A.Call(GetNumGroupMembers),0,40) or 0
    for i=1,(raid and count or math.max(0,count-1)) do units[#units+1]=(raid and "raid" or "party")..i end
    for _,unit in ipairs(units) do
        local p=member(unit)
        if p and not map[p.guid] and memberCount>=80 then if state then state.partial=true end;p=nil end
        if p then
            if not map[p.guid] then memberCount=memberCount+1 end
            map[p.guid]=p
            if state and state.run==run then
                state.members[p.guid]=p
                if state.dead[p.guid]==nil then
                    local dead=A.Call(UnitIsDeadOrGhost,unit)
                    if dead==true or dead==false then state.dead[p.guid]=dead end
                end
                local petUnit=unit=="player" and "pet" or unit:gsub("^(party)(%d+)$","%1pet%2"):gsub("^(raid)(%d+)$","%1pet%2")
                local pet=A.Text(A.Call(UnitGUID,petUnit),100)
                if pet then state.pets[pet]=p.guid end
            end
        end
    end
    run.roster={};for _,p in pairs(map) do run.roster[#run.roster+1]=p end
    table.sort(run.roster,function(a,b)return a.guid<b.guid end)
end

local function native()
    return C_DamageMeter and type(C_DamageMeter.GetAvailableCombatSessions)=="function" and type(C_DamageMeter.GetCombatSessionFromID)=="function"
        and (type(C_DamageMeter.IsDamageMeterAvailable)~="function" or A.Call(C_DamageMeter.IsDamageMeterAvailable)==true)
end
local function legacyLogAllowed()
    -- Forever exposes legacy API stubs, but registering CLEU is restricted and
    -- can show ADDON_ACTION_FORBIDDEN even when RegisterEvent is inside pcall.
    -- Only positively identified pre-Forever Classic clients may use it.
    if C_DamageMeter then return false end
    local _,_,_,interface=A.Call(GetBuildInfo)
    interface=A.Number(interface,10000,59999)
    return interface and (interface<16000 or interface>=20000)
        and type(CombatLogGetCurrentEventInfo)=="function" or false
end
local function sessions()
    local list=native() and A.Call(C_DamageMeter.GetAvailableCombatSessions)
    return type(list)=="table" and list or {}
end
function C.Start(run)
    state={run=run,at=A.Monotonic(),members={},pets={},baseline={},tracked={},sessions={},epoch=0,partial=false,deaths={},dead={}}
    C.Roster(run)
    state.source=native() and "damage_meter" or legacyLogAllowed() and "combat_log" or "unavailable"
    for _,s in pairs(sessions()) do local id=A.Number(A.Field(s,"sessionID"),1);if id then state.baseline[id]=true end end
    if A.Call(UnitAffectingCombat,"player")==true then state.partial=true end
    run.combat={source=state.source,coverage="unavailable",coveredMs=0,activeMs=0,players={}}
end

local function identity(source)
    local guid=A.Text(A.Field(source,"sourceGUID"),100)
    if A.Field(source,"isLocalPlayer")==true then guid=state.run.character and state.run.character.id end
    guid=guid and (state.pets[guid] or guid)
    return guid and state.members[guid] and guid or nil
end
local function refreshNative()
    if not state or state.source~="damage_meter" or A.Call(InCombatLockdown)==true then return end
    local kinds=Enum and Enum.DamageMeterType
    if not kinds then return end
    for _,available in pairs(sessions()) do
        local id=A.Number(A.Field(available,"sessionID"),1)
        if id and not state.baseline[id] and (not state.allowed or state.allowed[id]) then
            local key=state.epoch..":"..id
            local record=state.sessions[key] or {types={},durationMs=0}
            record.durationMs=math.max(record.durationMs,math.floor((A.Number(A.Field(available,"durationSeconds"),0,604800) or 0)*1000))
            for field,enum in pairs(metrics) do
                if A.Number(kinds[enum],0) then
                    local snapshot=A.Call(C_DamageMeter.GetCombatSessionFromID,id,kinds[enum])
                    local sources=A.Field(snapshot,"combatSources")
                    if type(sources)=="table" then
                        local values,readable={},true
                        for _,source in pairs(sources) do
                            local guid=identity(source)
                            if guid then
                                local amount=A.Number(A.Field(source,"totalAmount"),0,1e15)
                                if amount then values[guid]=(values[guid] or 0)+amount else readable=false end
                            elseif A.Field(source,"sourceCreatureID")==nil then
                                -- An inaccessible identity cannot be attributed as
                                -- zero to every known party member.
                                state.partial=true
                            end
                        end
                        if readable then record.types[field]=values else state.partial=true end
                        local duration=A.Number(A.Field(snapshot,"durationSeconds"),0,604800)
                        if duration then record.durationMs=math.max(record.durationMs,math.floor(duration*1000)) end
                    end
                end
            end
            state.sessions[key]=record
        end
    end
end

local function closeLegacy(at)
    if state and state.fightStart then
        state.legacyMs=(state.legacyMs or 0)+math.max(0,((at or A.Monotonic())-state.fightStart)*1000)
        state.fightStart,state.enemyActive=nil,nil
    end
end
function C.Snapshot(run)
    if not state or state.run~=run then return end
    refreshNative()
    if state.source=="combat_log" and state.fightStart and state.lastLogAt
        and A.Monotonic()-state.lastLogAt>5 and A.Call(InCombatLockdown)~=true then closeLegacy(state.lastLogAt) end
    local out={source=state.source,coverage="unavailable",coveredMs=math.max(0,math.floor(((state.endedAt or A.Monotonic())-state.at)*1000)),activeMs=0,players={}}
    local players,seen={},{}
    for guid,p in pairs(state.members) do players[guid]=A.Copy(p) end
    for _,record in pairs(state.sessions) do
        local any=false
        for field,values in pairs(record.types) do
            seen[field],any=true,true
            out[field]=out[field] or 0
            for guid,value in pairs(values) do
                if players[guid] then players[guid][field]=(players[guid][field] or 0)+value;out[field]=out[field]+value end
            end
        end
        if any then out.activeMs=out.activeMs+record.durationMs end
    end
    if state.source=="combat_log" and state.legacy then
        seen=state.legacySeen
        out.activeMs=math.floor((state.legacyMs or 0)+(state.fightStart and math.max(0,A.Monotonic()-state.fightStart)*1000 or 0))
        for guid,values in pairs(state.legacy) do for field,value in pairs(values) do
            if players[guid] then players[guid][field]=value;out[field]=(out[field] or 0)+value end
        end end
    end
    if next(seen) then out.coverage=state.partial and "partial" or "observed" end
    for _,p in pairs(players) do
        for field in pairs(seen) do if not state.partial then p[field]=p[field] or 0 end end
        if state.deaths[p.guid] then p.deaths=math.max(p.deaths or 0,state.deaths[p.guid]) end
        p.activeMs=out.activeMs;out.players[#out.players+1]=p
    end
    table.sort(out.players,function(a,b)return a.guid<b.guid end)
    run.combat=out
end

local function observeDeath(unit,definite)
    if not state then return end
    local guid=A.Text(A.Call(UnitGUID,unit),100)
    if not guid or not state.members[guid] then return end
    local dead=definite or A.Call(UnitIsDeadOrGhost,unit)
    if dead==true and (state.dead[guid]==false or definite and state.dead[guid]~=true) then state.deaths[guid]=(state.deaths[guid] or 0)+1 end
    if dead==true or dead==false then state.dead[guid]=dead end
end
function C.Finish(run)
    if not state or state.run~=run then return end
    if state.source=="combat_log" then closeLegacy() end
    state.endedAt=A.Monotonic()
    if state.source=="damage_meter" then
        state.allowed={}
        for _,s in pairs(sessions()) do local id=A.Number(A.Field(s,"sessionID"),1);if id then state.allowed[id]=true end end
        for id in pairs(state.tracked) do state.allowed[id]=true end
        pending[#pending+1]=state
    end
    C.Snapshot(run);state=nil
end

function C.FinalizePending()
    if A.Call(InCombatLockdown)==true then return end
    for i=#pending,1,-1 do
        local finished=pending[i]
        if A.Monotonic()-finished.endedAt>=0.3 then
            table.remove(pending,i)
            local current=state;state=finished;C.Snapshot(finished.run);state=current
            if A.RefreshRunCombat then A.RefreshRunCombat(finished.run.runId,finished.run.combat) end
        end
    end
end

function C.ObserveLog(...)
    if not state or state.source~="combat_log" then return end
    local event={...}
    for i=1,math.min(#event,30) do event[i]=A.Plain(event[i]) end
    local kind=A.Text(event[2],50)
    local src=A.Text(event[4],100);src=src and (state.pets[src] or src)
    local dst=A.Text(event[8],100);dst=dst and (state.pets[dst] or dst)
    local field,guid,amount,over,overkill
    if kind=="SWING_DAMAGE" then field,guid,amount="damage",src,A.Number(event[12],0,1e15);overkill=A.Number(event[13],-1,1e15)
    elseif kind=="SPELL_DAMAGE" or kind=="SPELL_PERIODIC_DAMAGE" or kind=="RANGE_DAMAGE" then field,guid,amount="damage",src,A.Number(event[15],0,1e15);overkill=A.Number(event[16],-1,1e15)
    elseif kind=="SPELL_HEAL" or kind=="SPELL_PERIODIC_HEAL" then
        if A.Call(InCombatLockdown)~=true and not state.enemyActive then return end
        field,guid,amount,over="healing",src,A.Number(event[15],0,1e15),A.Number(event[16],0,1e15)
        if amount and over then amount=math.max(0,amount-over) else amount=nil;state.partial=true end
    elseif kind=="SPELL_INTERRUPT" then field,guid,amount="interrupts",src,1
    elseif kind=="SPELL_DISPEL" then field,guid,amount="dispels",src,1
    elseif kind=="UNIT_DIED" then field,guid,amount="deaths",dst,1 end
    if field=="damage" and amount then
        if overkill then amount=math.max(0,amount-math.max(0,overkill)) else state.partial=true;amount=nil end
        if amount and (state.members[src] or state.members[dst]) then state.enemyActive=true end
    end
    state.legacy=state.legacy or {};state.legacySeen=state.legacySeen or {}
    local function add(who,metric,value)
        if not who or not state.members[who] or not value then return end
        local p=state.legacy[who] or {};state.legacy[who]=p
        p[metric]=(p[metric] or 0)+value;state.legacySeen[metric]=true
        state.fightStart=state.fightStart or A.Monotonic()
        state.lastLogAt=A.Monotonic()
    end
    add(guid,field,amount)
    if over then add(guid,"overhealing",over) end
    if field=="damage" then add(dst,"damageTaken",amount) end
end

if legacyLogAllowed() then
    A.On("COMBAT_LOG_EVENT_UNFILTERED",function()
        if not state or state.source~="combat_log" then return end
        local ok=pcall(function() C.ObserveLog(CombatLogGetCurrentEventInfo()) end)
        if not ok then state.partial=true end
    end)
end
A.On("PLAYER_REGEN_ENABLED",function() if state then closeLegacy();C.Snapshot(state.run) end;C.FinalizePending() end)
A.On("PLAYER_REGEN_DISABLED",function() if state and state.source=="combat_log" then state.fightStart=state.fightStart or A.Monotonic();state.enemyActive=true end end)
A.On("GROUP_ROSTER_UPDATE",function() if state then C.Roster(state.run) end end)
A.On("UNIT_HEALTH",function(unit) unit=A.Text(unit,30);if unit then observeDeath(unit) end end)
A.On("PLAYER_DEAD",function() observeDeath("player",true) end)
A.On("DAMAGE_METER_RESET",function()
    if state then state.epoch=state.epoch+1;state.baseline={};state.partial=true end
    for _,finished in ipairs(pending) do finished.allowed={};finished.partial=true end
end)
A.On("DAMAGE_METER_COMBAT_SESSION_UPDATED",function(_,id)
    id=A.Number(id,1)
    if state then if id then state.tracked[id]=true end;C.Snapshot(state.run) end
end)
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2,function() if state then C.Snapshot(state.run) end;C.FinalizePending() end) end
