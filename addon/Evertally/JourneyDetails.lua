local _, A = ...
-- Additive detailed observations for Journey's bounded outbox. Never reset the game's meter, replace the run recorder,
-- register restricted combat-log events, or turn unavailable numbers into zero. Native meter summaries are read AFTER combat.
local J = A.Journey
if not J then return end
local fight, pending, lastSessions = nil, {}, {}
local previousState, previousSignature, previousAuras, auraKnown, stateQueued, unixOffset, mounted
local playedTotal,playedClock,askedPlayed
local seenCasts,castTargets,castCount={},{},0
local METRICS = {damage="DamageDone",healing="HealingDone",absorbs="Absorbs",damageTaken="DamageTaken",interrupts="Interrupts",dispels="Dispels",deaths="Deaths"}
local SPELL_ROWS = {damage="dealt",healing="healed",damageTaken="took"}
local function active()
    local s=A.db and A.db.settings
    return s and s.web==true and type(s.scopes)=="table" and s.scopes.own_track==true and A.ExportStore()~=nil
end
local function identified() return active() and A.db.settings.scopes.own_character==true end
local function text(v,n) local s=A.Text(v,n or 120);return s and s~="" and s or nil end
local function number(v,max) return A.Number(v,0,max or 1e15) end
local function round(v) return math.floor(v*1000+0.5)/1000 end
local function encode(v) return A.Encode(v) end
local function spell(id)
    id=A.Number(id,1,1e9);if not id then return end
    local data=C_Spell and A.Call(C_Spell.GetSpellInfo,id)
    local name=text(A.Field(data,"name"))
    if not name then name=text(A.Call(GetSpellInfo,id)) end
    return name or "Spell "..tostring(id)
end

local function member(unit)
    local guid=text(A.Call(UnitGUID,unit),100);if not guid then return end
    local name,realm=A.Call(UnitFullName,unit)
    name,realm=text(name,80) or text(A.Call(UnitName,unit),80),text(realm,80)
    local _,_,class=A.Call(UnitClass,unit);local _,_,race=A.Call(UnitRace,unit)
    return {guid=guid,name=name and (realm and realm~="" and name.."-"..realm or name),classId=A.Number(class,1,100),
        raceId=A.Number(race,1,100),level=A.Number(A.Call(UnitLevel,unit),1,1000),role=text(A.Call(UnitGroupRolesAssigned,unit),20)}
end
local function roster()
    local raid,group=A.Call(IsInRaid)==true,A.Call(IsInGroup)==true
    local count=A.Number(A.Call(GetNumGroupMembers),0,40) or 0
    local mode=raid and "raid" or group and "party" or "solo"
    local units={"player"}
    for i=1,(raid and count or group and math.max(0,count-1) or 0) do units[#units+1]=(raid and "raid" or "party")..i end
    local rows,seen,complete={},{},true
    for _,unit in ipairs(units) do
        local row=member(unit)
        if not row then complete=false elseif not seen[row.guid] then seen[row.guid]=true;rows[#rows+1]=row end
    end
    table.sort(rows,function(a,b)return a.guid<b.guid end)
    return complete and rows or nil,mode,rows
end
local function expires(v)
    v=number(v,1e12);if not v or v==0 then return end
    unixOffset=unixOffset or A.Now()-A.Monotonic()
    return round(unixOffset+v)
end
local function auraRow(data,helpful)
    local id=A.Number(A.Field(data,"spellId"),1,1e9) or A.Number(A.Field(data,"spellID"),1,1e9)
    local name=text(A.Field(data,"name"))
    if not name and not id then return end
    return {id=id,text=name or spell(id),helpful=helpful,stacks=number(A.Field(data,"applications"),10000),
        duration=number(A.Field(data,"duration"),604800),expiresAt=expires(A.Field(data,"expirationTime")),icon=A.Number(A.Field(data,"icon"),1,1e10)}
end
local function readAuras()
    local modern=C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex)=="function"
    if not modern and type(UnitBuff)~="function" and type(UnitDebuff)~="function" then return nil,false end
    local out,known={},true
    for _,filter in ipairs({"HELPFUL","HARMFUL"}) do
        local helpful,ended=filter=="HELPFUL",false
        local fn=modern and C_UnitAuras.GetAuraDataByIndex or (helpful and UnitBuff or UnitDebuff)
        if type(fn)~="function" then known=false
        else
            for i=1,40 do
                local row
                if modern then
                    local ok,raw=pcall(fn,"player",i,filter)
                    if not ok then known=false;ended=true;break end
                    local plain=A.Plain(raw)
                    if plain==nil then if type(raw)~="nil" then known=false end;ended=true;break end
                    row=auraRow(plain,helpful)
                else
                    -- The legacy spell id is return 10, beyond A.Call's generic nine-value return limit.
                    local ok,name,icon,stacks,_,duration,expiration,_,_,_,id=pcall(fn,"player",i)
                    if not ok then known=false;ended=true;break end
                    if type(name)=="nil" then ended=true;break end
                    name=text(name)
                    if name then row={id=A.Number(id,1,1e9),text=name,helpful=helpful,stacks=number(stacks,10000),
                        duration=number(duration,604800),expiresAt=expires(expiration),icon=A.Number(icon,1,1e10)} end
                end
                if row then out[#out+1]=row else known=false end
            end
            if not ended then known=false end
        end
    end
    table.sort(out,function(a,b)
        return (a.helpful and "0" or "1")..tostring(a.id or 0)..a.text < (b.helpful and "0" or "1")..tostring(b.id or 0)..b.text
    end)
    return out,known
end
local function auraKey(row) return (row.helpful and "b:" or "d:")..tostring(row.id or 0)..":"..row.text end
local function auraChanges(rows,known)
    if not known then auraKnown=false;return end
    local nextAuras={};for _,row in ipairs(rows or {}) do nextAuras[auraKey(row)]=row end
    if previousAuras and auraKnown then
        for key,row in pairs(nextAuras) do
            local old=previousAuras[key]
            if not old or encode(old)~=encode(row) then
                local moment=A.Copy(row);moment.a=old and "refresh" or "gain";moment.fightId=fight and fight.id;J.Add("aura",moment)
            end
        end
        for key,row in pairs(previousAuras) do
            if not nextAuras[key] then local moment=A.Copy(row);moment.a="loss";moment.fightId=fight and fight.id;J.Add("aura",moment) end
        end
    end
    previousAuras,auraKnown=nextAuras,true
end
local function skillState()
    local skills,professions,seen={},{},{}
    local function profession(name,value,max)
        name=text(name,40);value,max=number(value,100000),number(max,100000)
        if not name or not value or not max or max<=0 then return end
        skills[name]={value,max}
        if not seen[name] and #professions<20 then seen[name]=true;professions[#professions+1]=name end
    end
    if type(GetProfessions)=="function" and type(GetProfessionInfo)=="function" then
        for _,index in pairs({A.Call(GetProfessions)}) do
            index=A.Number(index,1,1000)
            if index then local name,_,value,max=A.Call(GetProfessionInfo,index);profession(name,value,max) end
        end
    end
    for _,entry in ipairs(A.CollectProfessionLines and A.CollectProfessionLines() or {}) do profession(entry.name,entry.skill,entry.max) end
    local count=A.Number(A.Call(GetNumSkillLines),0,300)
    local trade=false
    for i=1,count or 0 do
        local name,header,_,value,_,_,max=A.Call(GetSkillLineInfo,i)
        name=text(name,40)
        if header==true then trade=name==A.Text(_G.TRADE_SKILLS,40) or name==A.Text(_G.SECONDARY_SKILLS,40)
        elseif name and number(value,100000) and number(max,100000) and max>0 then
            if trade then profession(name,value,max) else skills[name]={value,max} end
        end
    end
    local size=0;for name in pairs(skills) do size=size+1;if size>100 then skills[name]=nil end end
    return next(skills) and skills or nil,professions
end
function J.SnapshotState()
    stateQueued=false
    if not active() then previousState,previousSignature,previousAuras,auraKnown=nil,nil,nil,nil;return end
    local rows,mode=roster()
    local auras,known=readAuras();auraChanges(auras,known)
    local state={text="Character state",groupType=mode,aurasKnown=known}
    if identified() then
        state.roster=rows
        local stats=A.CollectStats and A.CollectStats();local attrs,enh={},{}
        local percentages={crit=true,scrit=true,dodge=true,parry=true,block=true}
        for _,key in ipairs(A.ArmoryStatKeys or {}) do
            local value=number(A.Field(stats,key))
            if value then
                local label=A.ArmoryStatLabel and A.ArmoryStatLabel(key) or key
                if percentages[key] then enh[#enh+1]={label,string.format("%.1f%%",value)} else attrs[#attrs+1]={label,value} end
            end
        end
        for _,extra in ipairs({{"Haste",GetHaste},{"Mastery",GetMasteryEffect}}) do
            local value=number(A.Call(extra[2]),10000);if value then enh[#enh+1]={extra[1],string.format("%.1f%%",value)} end
        end
        if #attrs>0 then state.attrs=attrs end
        if #enh>0 then state.enh=enh end
        local _,equipped=A.Call(GetAverageItemLevel);state.ilvl=number(equipped,100000)
        state.copper=number(A.Call(GetMoney),1e12)
        state.race=text(A.Call(UnitRace,"player"),80);state.faction=text(A.Call(UnitFactionGroup,"player"),80)
        state.guild=A.Call(IsInGuild)==false and "" or text(A.Call(GetGuildInfo,"player"),80)
        local best=0
        for _,tree in ipairs(A.CollectTalents and A.CollectTalents() or {}) do
            local spent=number(tree.spent,1000)
            if spent and spent>best then best=spent;state.spec=text(tree.name,80) end
        end
        state.skills,state.professions=skillState()
        if type(GetInventoryItemID)=="function" then
            state.equipped={}
            for slot=1,19 do local id=A.Number(A.Call(GetInventoryItemID,"player",slot),1,1e9);if id then state.equipped[#state.equipped+1]={slot=slot,itemId=id} end end
        end
        if playedTotal then state.played=round(playedTotal+math.max(0,A.Monotonic()-playedClock)) end
    end
    if known then state.auras=auras end
    -- Elapsed time alone must not duplicate a complete raid/aura snapshot every few seconds.
    local signatureState=A.Copy(state);signatureState.played=nil
    local signature=encode(signatureState)
    if signature and signature~=previousSignature then
        -- A changed buff must not repeat forty raid members and an unchanged character sheet.
        local delta={text=state.text}
        for key,value in pairs(state) do if not previousState or encode(value)~=encode(previousState[key]) then delta[key]=value end end
        if delta.auras then delta.aurasKnown=state.aurasKnown end
        if state.played then delta.played=state.played end
        previousState,previousSignature=state,signature;J.Add("state",delta)
    end
end
local function queueState()
    if not active() or stateQueued then return end
    stateQueued=true
    if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(0.2,J.SnapshotState) else J.SnapshotState() end
end

local function meterAvailable()
    return C_DamageMeter and type(C_DamageMeter.GetAvailableCombatSessions)=="function" and type(C_DamageMeter.GetCombatSessionFromID)=="function"
        and (type(C_DamageMeter.IsDamageMeterAvailable)~="function" or A.Call(C_DamageMeter.IsDamageMeterAvailable)==true)
end
local function sessions()
    local rows=meterAvailable() and A.Call(C_DamageMeter.GetAvailableCombatSessions);local out={}
    if type(rows)=="table" then for _,row in pairs(rows) do local id=A.Number(A.Field(row,"sessionID"),1);if id then out[id]=true end end end
    return out
end
local function cacheSessions() if A.Call(InCombatLockdown)~=true then lastSessions=sessions() end end
local function target()
    if A.Call(UnitExists,"target")~=true or A.Call(UnitCanAttack,"player","target")==false then return end
    local guid=text(A.Call(UnitGUID,"target"),100)
    local npcId=A.CreatureId(guid)
    return text(A.Call(UnitName,"target")),A.Call(UnitIsPlayer,"target")==true,A.Number(npcId,1,1e9)
end
local function observeTarget()
    if not fight then return end
    local name,player,npcId=target()
    if name and fight.kind~="boss" then fight.name=name;fight.npcId=npcId;if player then fight.kind="pvp" end end
    if name and name==fight.name and A.Call(UnitIsDeadOrGhost,"target")==true then fight.result="kill" end
end
local function spells(id,kind,guid)
    if not C_DamageMeter or type(C_DamageMeter.GetCombatSessionSourceFromID)~="function" then return end
    local data=A.Call(C_DamageMeter.GetCombatSessionSourceFromID,id,kind,guid)
    local rows=A.Field(data,"combatSpells");if type(rows)~="table" then return end
    local out={}
    for _,row in pairs(rows) do
        local spellId=A.Number(A.Field(row,"spellID"),0,1e9);local amount=number(A.Field(row,"totalAmount"))
        if spellId and amount and #out<80 then out[#out+1]={id=spellId>0 and spellId or nil,name=spellId>0 and spell(spellId) or text(_G.ATTACK) or "Attack",total=amount} end
    end
    return #out>0 and out or nil
end
local function summaryFor(done)
    local ms=math.max(0,math.floor(done.duration*1000))
    local out={source=meterAvailable() and "damage_meter" or "unavailable",coverage="unavailable",coveredMs=ms,activeMs=ms,players={}}
    local members={};for _,row in ipairs(done.members) do members[row.guid]=A.Copy(row) end
    if A.Call(InCombatLockdown)~=true and out.source=="damage_meter" then
        local seen,partial=false,done.partial==true
        local kinds=Enum and Enum.DamageMeterType
        for id in pairs(sessions()) do
            if not done.baseline[id] and (not done.allowed or done.allowed[id]) then
                for metric,enum in pairs(METRICS) do
                    local kind=kinds and A.Number(A.Field(kinds,enum),0)
                    if kind then
                        local snapshot=A.Call(C_DamageMeter.GetCombatSessionFromID,id,kind);local sources=A.Field(snapshot,"combatSources")
                        if type(sources)=="table" then
                            local values,complete={},true
                            for _,source in pairs(sources) do
                                local guid=text(A.Field(source,"sourceGUID"),100)
                                if A.Field(source,"isLocalPlayer")==true then guid=done.own end
                                if guid and members[guid] then
                                    local amount=number(A.Field(source,"totalAmount"))
                                    if amount then
                                        values[guid]=(values[guid] or 0)+amount
                                        local field=SPELL_ROWS[metric]
                                        if field and guid==done.own then
                                            local rows=spells(id,kind,text(A.Field(source,"sourceGUID"),100) or guid)
                                            if rows then
                                                local list=members[guid][field] or {};members[guid][field]=list
                                                for _,r in ipairs(rows) do if #list<80 then list[#list+1]=r end end
                                            end
                                        end
                                    else complete=false;partial=true end
                                elseif A.Field(source,"sourceCreatureID")==nil then complete=false;partial=true end
                            end
                            if complete then
                                local total=0
                                for guid,row in pairs(members) do row[metric]=(row[metric] or 0)+(values[guid] or 0);total=total+(values[guid] or 0) end
                                out[metric]=(out[metric] or 0)+total;seen=true
                            else for guid,value in pairs(values) do members[guid][metric]=(members[guid][metric] or 0)+value;seen=true end end
                        end
                    end
                end
            end
        end
        if seen then out.coverage=partial and "partial" or "observed" end
    end
    for _,row in pairs(members) do out.players[#out.players+1]=row end
    table.sort(out.players,function(a,b)return a.guid<b.guid end)
    return out
end
local function finalize(force)
    if A.Call(InCombatLockdown)==true and not force then return end
    for i=#pending,1,-1 do
        local done=pending[i]
        if force or A.Monotonic()-done.endedClock>=0.6 then
            if not fight and A.Call(InCombatLockdown)~=true then
                done.allowed=done.allowed or {}
                for id in pairs(sessions()) do if not done.baseline[id] then done.allowed[id]=true end end
            end
            local summary=summaryFor(done)
            if not force and summary.source=="damage_meter" and summary.coverage=="unavailable" and A.Monotonic()-done.endedClock<3 then
                if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(0.7,function()finalize(false)end) end
            else
                table.remove(pending,i)
                J.Add("combat",{a="end",fightId=done.id,text=done.name,npcId=done.npcId,encounterKind=done.kind,d=done.duration,result=done.result or "ended",summary=summary,difficulty=done.difficulty,size=done.size,mapId=done.mapId,x=done.x,y=done.y},done.endedAt)
            end
        end
    end
    if not fight then cacheSessions() end
end
function J.StartCombat()
    if not active() or fight then return end
    finalize(true)
    local _,_,members=roster();local name,player,npcId=target();local _,instanceType=A.Call(IsInInstance)
    fight={id=A.sessionId..":fight:"..A.RandomId(),at=A.Now(),clock=A.Monotonic(),own=text(A.Call(UnitGUID,"player"),100),
        name=name or "Combat",npcId=npcId,kind=(player or instanceType=="pvp" or instanceType=="arena") and "pvp" or "combat",members=members,baseline=A.Copy(lastSessions)}
    fight.size=A.Number(A.Call(GetNumGroupMembers),1,80) or (#members>0 and #members or nil)
    if A.Call(IsInInstance)==true then
        local _,_,difficultyId,difficultyName=A.Call(GetInstanceInfo)
        fight.difficulty=text(difficultyName,80) or (A.Number(difficultyId,1,10000) and "#"..tostring(difficultyId) or nil)
    end
    J.Add("combat",{a="start",fightId=fight.id,text=fight.name,npcId=fight.npcId,encounterKind=fight.kind,difficulty=fight.difficulty,size=fight.size});queueState()
end
function J.EndCombat(result)
    if not fight then return end
    observeTarget();local done=fight;fight=nil
    done.endedAt,done.endedClock=A.Now(),A.Monotonic()
    done.mapId,done.x,done.y=A.PlayerPosition()
    done.duration=math.max(0,round(math.max(done.endedAt-done.at,done.endedClock-done.clock)))
    done.result=result or done.result or "ended";done.allowed=sessions()
    -- The native row can arrive just after REGEN_ENABLED; its update event whitelists it before finalization.
    if not next(done.allowed) then done.allowed=nil end
    pending[#pending+1]=done
    if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(0.7,function()finalize(false)end) else finalize(true) end
    queueState()
end
function J.CurrentFightId() return fight and fight.id end
function J.NoteKill(name)
    local record=fight or pending[#pending]
    if record and record.kind~="boss" and (fight or A.Now()-record.endedAt<=2) then
        name=text(name,100);if name and name~=record.name then record.npcId=nil end
        record.name=name or record.name;record.result="kill"
    end
end
J.FinalizeCombat=finalize
local originalFlush,originalReset=J.Flush,A.ResetJourney
function J.Flush() finalize(true);originalFlush() end
function A.ResetJourney()
    originalReset();fight,pending,lastSessions=nil,{},{}
    previousState,previousSignature,previousAuras,auraKnown,stateQueued,unixOffset,mounted=nil,nil,nil,nil,nil,nil,nil
    playedTotal,playedClock,askedPlayed=nil,nil,nil
    seenCasts,castTargets,castCount={},{},0
end

A.On("PLAYER_REGEN_DISABLED",J.StartCombat)
A.On("PLAYER_REGEN_ENABLED",function()J.EndCombat();finalize(false);queueState()end)
A.On("PLAYER_TARGET_CHANGED",observeTarget)
A.On("UNIT_TARGET",function(unit)if A.Text(unit,20)=="player" then observeTarget()end end)
A.On("UNIT_HEALTH",function(unit)if A.Text(unit,20)=="target" then observeTarget()end end)
A.On("PLAYER_DEAD",function()if fight then fight.result=fight.kind=="pvp" and "loss" or "wipe" end end)
A.On("ENCOUNTER_START",function(_,name)
    if not active() then return end
    if not fight then J.StartCombat() end
    if fight then
        fight.kind="boss";fight.name=text(name) or fight.name
        local targetName,_,npcId=target();fight.npcId=targetName==fight.name and npcId or nil
    end
end)
A.On("ENCOUNTER_END",function(_,name,_,_,success)
    if fight then
        fight.kind="boss";fight.name=text(name) or fight.name;success=A.Number(success,0,1)
        if success~=nil then fight.result=success==1 and "kill" or "wipe" end
    end
end)
A.On("DAMAGE_METER_COMBAT_SESSION_UPDATED",function(_,id)
    if A.Call(InCombatLockdown)==true then return end
    id=A.Number(id,1)
    for _,done in ipairs(pending) do if id then done.allowed=done.allowed or {};done.allowed[id]=true end end
    finalize(false);if not fight and #pending==0 then cacheSessions() end
end)
A.On("DAMAGE_METER_RESET",function()
    lastSessions={};if fight then fight.partial=true;fight.baseline={} end
    for _,done in ipairs(pending) do done.partial=true;done.allowed={} end
end)
local function action(kind,name,id,detail)
    J.Add("action",{a=kind,text=name,id=id,detail=detail,fightId=fight and fight.id})
end
local function cast(kind,unit,castId,id)
    unit=A.Text(unit,40)
    if not unit or not active() then return end
    local own=unit=="player"
    if not own and (not fight or not identified() or A.Call(UnitAffectingCombat,unit)~=true) then return end
    if not own and unit~="target" and unit~="focus" and unit~="pet" and not unit:match("^party%d+$") and not unit:match("^raid%d+$") and not unit:match("^boss%d+$") and not unit:match("^nameplate%d+$") then return end
    id=A.Number(id,1,1e9);castId=text(castId,120)
    local guid=text(A.Call(UnitGUID,unit),100)
    if not own and not guid then return end
    local key=castId and kind..":"..(guid or unit)..":"..castId
    if key and seenCasts[key] then return end
    if castCount>=1024 then seenCasts,castTargets,castCount={},{},0 end
    if key then seenCasts[key]=true;castCount=castCount+1 end
    local data=id and C_Spell and A.Call(C_Spell.GetSpellInfo,id)
    local icon=A.Number(A.Field(data,"iconID"),1,1e9)
    if not icon and id then local _,_,legacy=A.Call(GetSpellInfo,id);icon=A.Number(legacy,1,1e9) end
    local fields={a=kind,text=id and spell(id) or "Spell",id=id,icon=icon,fightId=fight and fight.id,actorSide="me"}
    if identified() then
        fields.actor=text(A.Call(UnitName,unit),120)
        local _,_,class=A.Call(UnitClass,unit);fields.actorClassId=A.Number(class,1,100)
        fields.target=own and castId and castTargets[castId] or nil
        if not own then fields.actorSide=(unit=="pet" or unit:match("^party%d+$") or unit:match("^raid%d+$") or A.Call(UnitIsFriend,"player",unit)==true) and "party" or "enemy" end
    end
    J.Add("action",fields)
    if castId and (kind=="cast" or kind=="cast_failed") then castTargets[castId]=nil end
end
A.On("UNIT_SPELLCAST_SENT",function(unit,targetName,castId)
    if A.Text(unit,40)~="player" or not identified() then return end
    castId=text(castId,120);targetName=text(targetName,120)
    if castId and targetName then
        if castCount>=1024 then seenCasts,castTargets,castCount={},{},0 end
        castTargets[castId]=targetName;castCount=castCount+1
    end
end)
A.On("UNIT_SPELLCAST_START",function(...)cast("cast_start",...)end)
A.On("UNIT_SPELLCAST_SUCCEEDED",function(...)cast("cast",...)end)
A.On("UNIT_SPELLCAST_FAILED",function(...)cast("cast_failed",...)end)
A.On("UNIT_SPELLCAST_INTERRUPTED",function(...)cast("cast_failed",...)end)
local speechEvents={CHAT_MSG_MONSTER_SAY="say",CHAT_MSG_MONSTER_YELL="yell",CHAT_MSG_MONSTER_EMOTE="emote",CHAT_MSG_RAID_BOSS_EMOTE="boss_emote",CHAT_MSG_RAID_BOSS_WHISPER="boss_whisper"}
for event,channel in pairs(speechEvents) do
    local kind=channel
    A.On(event,function(message,speaker)
        if not identified() then return end
        message=text(message,1000);speaker=text(speaker,120)
        if not message then return end
        message=message:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|H.-|h(.-)|h","%1"):gsub("|T.-|t","")
        J.Add("speech",{a=kind,text=(speaker or "NPC"):sub(1,120),speaker=speaker,message=message,fightId=fight and fight.id})
    end)
end
local function hookJump()
    if J.jumpHooked or type(hooksecurefunc)~="function" or type(JumpOrAscendStart)~="function" then return end
    J.jumpHooked=pcall(hooksecurefunc,"JumpOrAscendStart",function()
        if A.Call(UnitOnTaxi,"player")==true or A.Call(IsFlying)==true or A.Call(IsSwimming)==true then return end
        action("jump","Jump",nil,"Jump command")
    end)
end
local itemHooks,lastItem,lastItemAt={},nil,-1e9
local function itemRequest(raw,detail)
    if not active() then return end
    local id=A.Number(raw,1,1e9)
    local label=text(raw)
    if label then id=id or tonumber(label:match("item:(%d+)")) or tonumber(label:match("^(%d+)$"));label=label:match("%[(.-)%]") or label end
    id=A.Number(id,1,1e9)
    local known=id and (C_Item and A.Call(C_Item.GetItemInfo,id) or A.Call(GetItemInfo,id))
    label=text(known) or label or (id and "Item "..tostring(id)) or "Item"
    local signature=id and tostring(id) or label..(detail or "")
    if signature==lastItem and A.Monotonic()-lastItemAt<0.15 then return end
    lastItem,lastItemAt=signature,A.Monotonic()
    -- A secure post-hook proves the use command was issued, not that cooldown/range/consumption succeeded.
    action("item_attempt",label,id,detail or "Use requested; outcome not recorded")
end
local function hookItems()
    if type(hooksecurefunc)~="function" then return end
    if not itemHooks.named and type(UseItemByName)=="function" then
        itemHooks.named=pcall(hooksecurefunc,"UseItemByName",function(item)itemRequest(item)end)
    end
    if not itemHooks.equipped and type(UseInventoryItem)=="function" then
        itemHooks.equipped=pcall(hooksecurefunc,"UseInventoryItem",function(slot)
            slot=A.Number(slot,1,100);if slot then itemRequest(A.Call(GetInventoryItemID,"player",slot),"Use requested from equipment slot "..tostring(slot).."; outcome not recorded") end
        end)
    end
    if not itemHooks.bag and C_Container and type(C_Container.UseContainerItem)=="function" then
        itemHooks.bag=pcall(hooksecurefunc,C_Container,"UseContainerItem",function(bag,slot)
            bag,slot=A.Number(bag,-10,100),A.Number(slot,1,10000)
            if bag and slot then itemRequest(A.Call(C_Container.GetContainerItemID,bag,slot),"Use requested from bag "..tostring(bag)..", slot "..tostring(slot).."; outcome not recorded") end
        end)
    end
end
local function mountState()
    local now=A.Call(IsMounted)
    if now~=true and now~=false then return end
    if mounted~=nil and now~=mounted then action(now and "mount" or "dismount",now and "Mounted" or "Dismounted") end
    mounted=now
end
A.On("PLAYER_MOUNT_DISPLAY_CHANGED",function()mountState();queueState()end)
A.On("PLAYER_MONEY",queueState)
A.On("CHAT_MSG_SKILL",queueState)
A.On("TIME_PLAYED_MSG",function(total)
    total=number(total,1e10)
    if total then playedTotal,playedClock=total,A.Monotonic();previousState,previousSignature=nil,nil;queueState() end
end)
A.On("GROUP_ROSTER_UPDATE",function()
    queueState()
    if fight then
        local rows,_,observed=roster();local seen={}
        for _,row in ipairs(fight.members) do seen[row.guid]=true end
        for _,row in ipairs(observed) do if not seen[row.guid] and #fight.members<80 then fight.members[#fight.members+1]=row;seen[row.guid]=true end end
        fight.size=math.max(fight.size or 1,A.Number(A.Call(GetNumGroupMembers),1,80) or 1)
        if not rows then fight.partial=true end
    end
end)
A.On("UNIT_AURA",function(unit)if A.Text(unit,20)=="player" then queueState()end end)
A.On("UNIT_STATS",function(unit)if A.Text(unit,20)=="player" then queueState()end end)
for _,event in ipairs({"PLAYER_EQUIPMENT_CHANGED","SPELLS_CHANGED","PLAYER_TALENT_UPDATE","CHARACTER_POINTS_CHANGED"}) do A.On(event,queueState) end
A.On("PLAYER_ENTERING_WORLD",function()
    mounted=A.Call(IsMounted);hookJump();hookItems();cacheSessions();queueState()
    if active() and A.Call(UnitAffectingCombat,"player")==true then J.StartCombat();if fight then fight.partial=true end end
    if identified() and not askedPlayed and type(RequestTimePlayed)=="function" then askedPlayed=true;pcall(RequestTimePlayed) end
end)
A.On("PLAYER_LOGOUT",function()if fight then J.EndCombat("interrupted") end;J.Flush()end)
local lastScan=-1e9
function J.TickDetail()
    if active() and A.Monotonic()-lastScan>=5 then lastScan=A.Monotonic();J.SnapshotState();mountState() end
    finalize(false);if not fight and #pending==0 then cacheSessions() end
end
hookJump();hookItems()
if C_Timer and type(C_Timer.NewTicker)=="function" then C_Timer.NewTicker(2,J.TickDetail) end
