local _, A = ...
-- The player's own route and guild identity, for the website's map. Both are off by default and exported
-- only while web export is on AND the matching scope is on (own_track, guild_share). Nothing here is
-- kept in the local history list: it goes straight to the outbox, which the sync app uploads.
local TICK,MOVED,IDLE,STALE,MAX_POINTS=4,0.002,120,60,100
local MAX_TRACK_EVENTS,GUILD_REFRESH,MAX_ROSTER=500,7*86400,1000
local current,pendingRoster

local function settings() return A.db and A.db.settings end
local function active(scope)
    local s=settings()
    return s~=nil and s.web==true and type(s.scopes)=="table" and s.scopes[scope]==true and A.ExportStore()~=nil
end

-- ---------------------------------------------------------------- route
local function round(v) return math.floor(v*1000+0.5)/1000 end
-- The outbox is only emptied when the consent changes, so cap the routes by dropping the oldest ones.
local function trimTracks(store)
    local count=0
    for _,event in ipairs(store.events) do if event.kind=="track.path" then count=count+1 end end
    local i=1
    while count>=MAX_TRACK_EVENTS and i<=#store.events do
        if store.events[i].kind=="track.path" then table.remove(store.events,i);count=count-1 else i=i+1 end
    end
end
function A.FlushTrack()
    local path=current;current=nil
    if not path or #path.points==0 or not active("own_track") then return end
    trimTracks(A.ExportStore())
    A.Record("track.path",{mapId=path.mapId,mapSystem="ui_map",startedAt=path.startedAt,points=path.points},"api_snapshot",nil,true)
end
function A.SampleTrack()
    if not active("own_track") then current=nil;return end
    local map,x,y=A.PlayerPosition()
    -- Instances and loading screens give no map position: close the stretch walked so far.
    if not map or not x or not y then A.FlushTrack();return end
    local now=A.Now()
    if current and (current.mapId~=map or now-current.seen>STALE or #current.points>=MAX_POINTS) then A.FlushTrack() end
    if not current then current={mapId=map,startedAt=now,points={},seen=now} end
    x,y=round(x),round(y)
    local points=current.points;local last=points[#points]
    local moved=not last or math.abs(x-last[2])+math.abs(y-last[3])>=MOVED
    -- Standing still adds a heartbeat point only now and then, so the last known time stays fresh.
    if moved or now-(current.startedAt+last[1])>=IDLE then points[#points+1]={now-current.startedAt,x,y} end
    current.seen=now
end

-- ---------------------------------------------------------------- guild
local function guildInfo()
    if A.Call(IsInGuild)~=true then return nil end
    local name,rankName,rankIndex=A.Call(GetGuildInfo,"player")
    name=A.Text(name,100);rankIndex=A.Number(rankIndex,0,100)
    if not name or rankIndex==nil then return nil end
    return name,A.Text(rankName,100),rankIndex
end
-- GetGuildRosterInfo returns more values than A.Call passes on, so read it directly.
local function rosterRow(index)
    local ok,name,_,rankIndex,level,_,_,_,_,_,_,classFile=pcall(GetGuildRosterInfo,index)
    if not ok then return nil end
    name=A.Text(name,60);rankIndex=A.Number(rankIndex,0,100)
    if not name or rankIndex==nil then return nil end
    return {name=name,rankIndex=rankIndex,level=A.Number(level,1,1000),classId=A.ClassIdFromFile(A.Plain(classFile))}
end
local function readRoster()
    local total=A.Number(A.Call(GetNumGuildMembers),0,100000);if not total or total<1 then return nil end
    local roster={}
    for i=1,math.min(total,MAX_ROSTER) do
        local row=rosterRow(i);if row then roster[#roster+1]=row end
    end
    return #roster>0 and roster or nil
end
local function requestRoster()
    if C_GuildInfo and type(C_GuildInfo.GuildRoster)=="function" then pcall(C_GuildInfo.GuildRoster)
    elseif type(GuildRoster)=="function" then pcall(GuildRoster) end
end
function A.GuildSnapshot()
    if not active("guild_share") or not settings().scopes.own_character then return end
    local db,now=A.db,A.Now()
    local name,rankName,rankIndex=guildInfo()
    if not name then
        -- Out of the guild: tell the website once, so it stops treating the character as a member.
        if db.guildSig and db.guildSig~="none" then
            -- An empty Lua table would read back as an array, so the event says it explicitly.
            A.Record("guild.snapshot",{left=true},"api_snapshot",nil,true);db.guildSig="none";db.guildSigAt=now
        end
        return
    end
    local signature=name.."|"..rankIndex
    if db.guildSig~=signature or now-(db.guildSigAt or 0)>GUILD_REFRESH then
        A.Record("guild.snapshot",{guildName=name,rankName=rankName,rankIndex=rankIndex},"api_snapshot",nil,true)
        db.guildSig=signature;db.guildSigAt=now
    end
    -- Only a guild master (rank 0) sends the member list; once a week is enough.
    if rankIndex==0 and now-(db.rosterAt or 0)>GUILD_REFRESH then pendingRoster=true;requestRoster() end
end
local function rosterUpdated()
    if not pendingRoster or not active("guild_share") then return end
    local name,rankName,rankIndex=guildInfo()
    if not name or rankIndex~=0 then pendingRoster=false;return end
    local roster=readRoster();if not roster then return end
    pendingRoster=false
    A.Record("guild.snapshot",{guildName=name,rankName=rankName,rankIndex=0,roster=roster},"api_snapshot",nil,true)
    A.db.rosterAt=A.Now()
end

function A.ResetPeople()
    current=nil;pendingRoster=false
    if A.db then A.db.guildSig=nil;A.db.guildSigAt=nil;A.db.rosterAt=nil end
    -- Send the guild identity again for the new outbox, once the policy change has finished.
    if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(2,A.GuildSnapshot) end
end

A.On("PLAYER_LOGOUT",A.FlushTrack)
A.On("PLAYER_LOGIN",function() if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(8,A.GuildSnapshot) end end)
for _,event in ipairs({"PLAYER_GUILD_UPDATE","GUILD_RANKS_UPDATE"}) do A.On(event,A.GuildSnapshot) end
A.On("GUILD_ROSTER_UPDATE",rosterUpdated)
if C_Timer and type(C_Timer.NewTicker)=="function" then C_Timer.NewTicker(TICK,A.SampleTrack) end
