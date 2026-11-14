local addonName, A = ...
_G.Evertally = A
A.handlers, A.capabilities, A.errors = {}, {}, {}
A.MAX_EVENTS, A.MAX_RUNS, A.MAX_EXPORT = 5000, 1000, 4000
-- Soft limits stop only repeated low-priority sampling; results keep recording up to the hard cap.
A.HARD_EVENTS, A.HARD_EXPORT = 6000, 4800
local sampling={["npc.observed"]=true,["vendor.snapshot"]=true,["profession.snapshot"]=true,
    ["cooldown.snapshot"]=true,["character.snapshot"]=true,["track.path"]=true,["armory.snapshot"]=true,["armory.view"]=true}
local function overLimit(count,soft,hard,kind) return count>=hard or (count>=soft and sampling[kind]==true) end

function A.Plain(v)
    if type(issecretvalue)=="function" then
        local ok, secret=pcall(issecretvalue,v)
        if not ok or secret then return nil end
    end
    if type(issecrettable)=="function" and type(v)=="table" then
        local ok,secret=pcall(issecrettable,v)
        if not ok or secret then return nil end
    end
    return v
end
function A.Field(t,k)
    t=A.Plain(t);if type(t)~="table" then return nil end
    local ok,v=pcall(function() return t[k] end)
    if ok then return A.Plain(v) end
end
function A.Call(fn,...)
    if type(fn)~="function" then return nil end
    local ok,a,b,c,d,e,f,g,h,i=pcall(fn,...)
    if not ok then return nil end
    return A.Plain(a),A.Plain(b),A.Plain(c),A.Plain(d),A.Plain(e),A.Plain(f),A.Plain(g),A.Plain(h),A.Plain(i)
end
function A.Text(v,max)
    v=A.Plain(v);if type(v)~="string" then return nil end
    return v:sub(1,max or 300)
end
function A.Number(v,min,max)
    v=A.Plain(v)
    if type(v)~="number" or v~=v or v==math.huge or v==-math.huge then return nil end
    if min and v<min or max and v>max then return nil end
    return v
end
function A.Copy(value,depth)
    value=A.Plain(value);depth=depth or 0;if depth>12 then return nil end
    if type(value)=="string" then return value:sub(1,2048) end
    if type(value)=="number" then return A.Number(value) end
    if type(value)=="boolean" then return value end
    if type(value)~="table" then return nil end
    local ok,result=pcall(function()
        local out,count={},0
        for k,v in pairs(value) do
            k=A.Plain(k)
            if type(k)=="string" or type(k)=="number" then
                count=count+1;if count>1000 then break end
                out[k]=A.Copy(v,depth+1)
            end
        end
        return out
    end)
    if ok then return result end
end
function A.Now() return A.Number(A.Call(GetServerTime),0) or A.Number(A.Call(time),0) or 0 end
function A.Monotonic() return A.Number(A.Call(GetTime),0) or 0 end
function A.RandomId()
    return string.format("%x-%x-%x",A.Now(),math.random(1,2147483646),math.random(1,2147483646))
end
function A.Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage("|cffd8b66aEvertally:|r "..message) end
end
function A.On(event,fn)
    A.handlers[event]=A.handlers[event] or {};table.insert(A.handlers[event],fn)
    if A.frame then
        local ok=pcall(A.frame.RegisterEvent,A.frame,event)
        A.capabilities[event]=ok and "registered; runtime unverified" or "unsupported"
    end
end
function A.Dispatch(event,...)
    if A.RequirementsReady and not A.RequirementsReady() then
        if event=="PLAYER_LOGIN" and A.CreateMinimapButton then A.CreateMinimapButton() end
        if (event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_REGEN_ENABLED") and A.RequirementsMaybe then A.RequirementsMaybe() end
        return
    end
    for _,fn in ipairs(A.handlers[event] or {}) do
        local ok=pcall(fn,...)
        if not ok then A.errors[event]=(A.errors[event] or 0)+1 end
    end
end
function A.Changed() if A.RefreshUI then A.RefreshUI() end end

function A.Character()
    local id=A.Text(A.Call(UnitGUID,"player"),100)
    local name,realm=A.Call(UnitFullName,"player")
    name=A.Text(name,100) or A.Text(A.Call(UnitName,"player"),100)
    realm=A.Text(realm,100) or A.Text(A.Call(GetRealmName),100) or "unknown"
    local _,_,classId=A.Call(UnitClass,"player");local _,_,raceId=A.Call(UnitRace,"player")
    local level=A.Number(A.Call(UnitLevel,"player"),1,100)
    if not id or not name then return nil end
    return {id=id,name=name,realm=realm,classId=A.Number(classId,1,100),raceId=A.Number(raceId,1,100),level=level}
end
function A.Game()
    local _,build,_,interface=A.Call(GetBuildInfo)
    local region=A.Number(A.Call(GetCurrentRegion),1,20)
    return {product="forever",build=A.Text(build,40) or "unknown",interface=A.Number(interface,1,999999) or 16001,
        region=region and tostring(region) or "unknown",realm=A.Text(A.Call(GetRealmName),100) or "unknown"}
end

local scopeFor={
    ["character.snapshot"]="own_character",["character.level"]="own_character",["character.publish"]="own_character",
    ["profession.snapshot"]="own_professions",["craft.result"]="own_professions",["cooldown.snapshot"]="own_professions",
    ["instance.entered"]="own_runs",["run.finished"]="own_runs",["run.interrupted"]="own_runs",["raid.encounter_finished"]="own_runs",
    ["quest.accepted"]="world_facts",["quest.turned_in"]="world_facts",["quest.abandoned"]="world_facts",
    ["npc.observed"]="world_facts",["vendor.snapshot"]="world_facts",["loot.received"]="world_facts",["zone.visited"]="world_facts",
    ["track.path"]="own_track",["guild.snapshot"]="guild_share",
    -- the own armory, and what other players allowed this player to keep (see Social.lua); both need the character scope
    ["armory.snapshot"]="own_character",["armory.view"]="own_character",["armory.revoked"]="own_character",
}
A.ScopeFor=scopeFor
function A.SafeWorldPayload(kind,payload)
    local clean=A.Copy(payload)
    if type(clean)~="table" then return clean end
    if kind~="npc.observed" or clean.positionMethod~="unit_position" then clean.x=nil;clean.y=nil;clean.z=nil end
    return clean
end
function A.ExportStore()
    if type(EvertallyExportDB)~="table" then return nil end
    return EvertallyExportDB
end
function A.ResetExport()
    local store=A.ExportStore();if not store then return end
    local s=A.db.settings
    store.schemaVersion=1;store.enabled=s.web==true;store.producerId=A.db.producerId
    store.consentEpoch=s.consentEpoch;store.since=s.since;store.scopes={};store.events={}
    for _,scope in ipairs({"world_facts","own_runs","own_character","own_professions","own_track","guild_share"}) do
        if s.scopes[scope] then store.scopes[#store.scopes+1]=scope end
    end
    -- A new policy starts a fresh outbox: a half-walked route or an old guild snapshot must not leak into it.
    if A.ResetPeople then A.ResetPeople() end
    if A.RefreshConnections then A.RefreshConnections() end
end
function A.SetWeb(enabled)
    if enabled and not A.ExportStore() then A.Print(A.L("missingExport"));return false end
    A.db.settings.web=enabled==true
    A.db.settings.consentEpoch=A.db.settings.consentEpoch+1;A.db.settings.since=A.Now()
    A.ResetExport();A.Changed()
    if A.OpticalClear then A.OpticalClear() end
    if enabled and A.ResendPublish then A.ResendPublish() end
    if not enabled then A.Print(A.L("revokeHint")) end
    return true
end
function A.SetScope(scope,enabled)
    if not A.db.settings.scopes[scope] and not enabled then return end
    A.db.settings.scopes[scope]=enabled==true
    -- The guild recognises members by character name, so the two always go together.
    if scope=="guild_share" and enabled then A.db.settings.scopes.own_character=true end
    if scope=="own_character" and not enabled then A.db.settings.scopes.guild_share=false end
    -- A new policy invalidates the old outbox; no retroactive upload.
    if A.db.settings.web then A.SetWeb(true) end
    A.Changed()
end
function A.ExportEvent(event)
    local store=A.ExportStore();local s=A.db.settings
    if not store or not s.web or store.enabled~=true or event.origin~="local_observation" then return end
    local scope=scopeFor[event.kind]
    if not scope or not s.scopes[scope] or event.observedAt<s.since then return end
    if scope=="guild_share" and not s.scopes.own_character then return end
    if overLimit(#store.events,A.MAX_EXPORT,A.HARD_EXPORT,event.kind) then A.exportFull=true;return end
    local projection=A.Copy(event)
    if scope=="world_facts" then projection.payload=A.SafeWorldPayload(event.kind,event.payload) end
    if not s.scopes.own_character then
        -- Own run association is pseudonymous; world facts carry no character identity.
        if scope=="own_runs" or scope=="own_track" then
            local original=event.character and event.character.id or "unknown"
            A.db.characterKeys[original]=A.db.characterKeys[original] or A.RandomId()
            projection.character={id=A.db.characterKeys[original],classId=event.character and event.character.classId,
                raceId=event.character and event.character.raceId,level=event.character and event.character.level}
            if scope=="own_runs" then
                projection.payload.roster=nil
                if type(projection.payload.combat)=="table" then
                    local players={}
                    for _,p in ipairs(projection.payload.combat.players or {}) do
                        if p.guid==original then p.guid=projection.character.id;p.name=nil;players[#players+1]=p end
                    end
                    projection.payload.combat.players=players
                end
            end
        else projection.character=nil end
    end
    store.events[#store.events+1]=projection
end
-- exportOnly events (routes, guild snapshots) go to the web outbox but never into the local history list.
--- Short trail of the social whispers (requests, answers, data) kept in the saved settings, newest last, so a lost
--- answer can be traced after /reload. Holds only message types, player names, ids and outcomes, never item data.
function A.DiagLog(text)
    if not A.db or not A.db.settings then return end
    local log=A.db.settings.diagLog
    if type(log)~="table" then log={};A.db.settings.diagLog=log end
    log[#log+1]=string.format("%s %s",A.Now(),tostring(text):sub(1,160))
    while #log>120 do table.remove(log,1) end
end
function A.Record(kind,payload,evidence,ownCharacter,exportOnly)
    if A.RequirementsReady and not A.RequirementsReady() then return nil end
    if not A.db or not scopeFor[kind] then return nil end
    if not exportOnly and overLimit(#A.db.events,A.MAX_EVENTS,A.HARD_EVENTS,kind) then A.storageFull=true;return nil end
    local data=scopeFor[kind]=="world_facts" and A.SafeWorldPayload(kind,payload) or A.Copy(payload);if type(data)~="table" then return nil end
    A.db.sequence=A.db.sequence+1
    local event={schemaVersion=1,eventId=A.db.producerId..":"..A.sessionId..":"..A.db.sequence,
        producerId=A.db.producerId,origin="local_observation",kind=kind,observedAt=A.Now(),game=A.Game(),
        character=ownCharacter and A.Copy(ownCharacter) or A.Character(),payload=data,evidence=evidence or "api_event"}
    if exportOnly then A.ExportEvent(event);return event end
    A.db.events[#A.db.events+1]=event;A.ExportEvent(event);A.Changed();return event
end

function A.Initialize()
    if type(EvertallyDB)~="table" then EvertallyDB={} end
    local db=EvertallyDB
    if db.schemaVersion and db.schemaVersion>1 then A.Print("Unsupported future database; recording disabled.");return end
    db.schemaVersion=1;db.producerId=db.producerId or A.RandomId();db.sequence=db.sequence or 0
    db.events=db.events or {};db.runs=db.runs or {};db.settings=db.settings or {}
    db.characterKeys=db.characterKeys or {}
    local s=db.settings;s.language=s.language or "en";s.web=s.web==true;s.ingame=s.ingame==true
    if s.group==nil then s.group=true end;if s.guild==nil then s.guild=false end
    s.consentEpoch=s.consentEpoch or 0;s.since=s.since or A.Now()
    s.scopes=s.scopes or {world_facts=true,own_runs=true,own_character=true,own_professions=true,own_track=false,guild_share=false}
    A.db=db;A.sessionId=A.RandomId()
    -- Remove historical player-interaction coordinates from local history/outbox.
    for _,event in ipairs(db.events) do if scopeFor[event.kind]=="world_facts" then event.payload=A.SafeWorldPayload(event.kind,event.payload) end end
    if type(EvertallyPeersDB)~="table" then EvertallyPeersDB={schemaVersion=1,peers={}} end
    EvertallyPeersDB.peers=EvertallyPeersDB.peers or {};A.peerDB=EvertallyPeersDB
    local store=A.ExportStore()
    if store then
        for _,event in ipairs(store.events or {}) do if scopeFor[event.kind]=="world_facts" then event.payload=A.SafeWorldPayload(event.kind,event.payload) end end
        if not s.web then A.ResetExport()
        elseif store.producerId~=db.producerId or store.consentEpoch~=s.consentEpoch then A.ResetExport() end
    end
    if A.RestoreRun then A.RestoreRun() end
    A.Print(A.L("loaded"))
    -- Evertally Sync installs updates while the game runs; after the restart, say once that the new version is here.
    if s.lastVersion and s.lastVersion ~= A.version then A.Print(string.format(A.L("updatedTo"), A.version)) end
    s.lastVersion = A.version
end

if type(CreateFrame)=="function" then
    A.frame=CreateFrame("Frame")
    A.frame:SetScript("OnEvent",function(_,event,...)
        if event=="ADDON_LOADED" then
            local name=A.Plain((...));if name==addonName then A.Initialize() end
            return
        end
        if A.db then A.Dispatch(event,...) end
    end)
    A.frame:RegisterEvent("ADDON_LOADED")
end
