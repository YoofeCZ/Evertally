local _, A = ...
local PREFIX="Evtly1"
local outgoing,incoming,lastHello={}, {}, {}
local MAX_BYTES,CHUNK,MAX_PARTS=10000,170,60
-- Client throttles addon messages per prefix (short burst, then ~1/s) and reports it
-- by return code, not by error. Stay under it so chunks are not silently dropped.
local BURST,REFILL_PER_SEC,MAX_TRIES=8,1,20
local tokens,lastRefill=BURST,nil
local function throttled(result)
    local R=type(Enum)=="table" and Enum.SendAddonMessageResult
    return result==(R and R.AddonMessageThrottle or 3) or result==(R and R.ChannelThrottle or 8)
end
local function channels()
    local result={};if not A.db then return result end
    local s=A.db.settings
    if s.group and A.Call(IsInGroup)==true then result[#result+1]=A.Call(IsInRaid)==true and "RAID" or "PARTY" end
    if s.guild and A.Call(IsInGuild)==true then result[#result+1]="GUILD" end
    return result
end
local function allowed(channel)
    return (channel=="PARTY" or channel=="RAID") and A.db.settings.group or channel=="GUILD" and A.db.settings.guild
end
local function queue(text,channel,target,social,key)
    -- a message with a key (a position beacon) replaces the one with the same key that is still waiting
    if key then for i=#outgoing,1,-1 do if outgoing[i].key==key then table.remove(outgoing,i) end end end
    if #outgoing>=180 then return false end
    outgoing[#outgoing+1]={text=text,channel=channel,target=target,social=social,key=key};return true
end
-- Social messages (inspect, trade proposals, meets) go out through the same throttled queue, to a WHISPER target or a group channel.
function A.QueueSocial(text,channel,target,key) return queue(text,channel,target,true,key) end
local function trimPeers()
    if not A.peerDB then return end
    local now=A.Now();local peers=A.peerDB.peers;local names={}
    for sender,peer in pairs(peers) do
        if type(peer)~="table" or type(peer.receivedAt)~="number" or now-peer.receivedAt>2592000 then peers[sender]=nil
        else names[#names+1]=sender end
    end
    table.sort(names,function(a,b) return peers[a].receivedAt<peers[b].receivedAt end)
    for i=1,math.max(0,#names-100) do peers[names[i]]=nil end
end
function A.MakeSummary()
    local own=A.Character();local completed=0
    for _,run in ipairs(A.db.runs) do if run.character and own and run.character.id==own.id and run.status=="completed" then completed=completed+1 end end
    local summary={v=1,producerId=A.db.producerId,generatedAt=A.Now(),character=own,runs={},facts={},completedRuns=completed}
    for i=#A.db.runs,1,-1 do
        local run=A.db.runs[i]
        if own and run.character and run.character.id==own.id then
            local clean=A.Copy(run);clean.character=nil
            -- A bounded peer summary shares the owner's attributable figures.
            -- Full group rosters and other people's combat rows stay in the
            -- observer's local run; a raid must not exhaust the message budget.
            clean.roster=nil
            if clean.combat then
                local players={}
                for _,p in ipairs(clean.combat.players or {}) do if p.guid==own.id then players[#players+1]=p end end
                clean.combat.players=players
            end
            summary.runs[#summary.runs+1]=clean
            if #summary.runs>=5 then break end
        end
    end
    for i=#A.db.events,1,-1 do
        local event=A.db.events[i]
        if A.ScopeFor[event.kind]=="world_facts" then
            summary.facts[#summary.facts+1]={kind=event.kind,observedAt=math.floor(event.observedAt/86400)*86400,payload=A.SafeWorldPayload(event.kind,event.payload)}
            if #summary.facts>=3 then break end
        end
    end
    return summary
end
function A.ShareNow()
    if not A.db or not A.db.settings.ingame then return false,"sharing_disabled" end
    local data=A.MakeSummary();local text=A.Encode(data)
    -- Keep each response bounded even if the user has unusually long boss lists.
    while text and #text>MAX_BYTES and #data.runs>0 do table.remove(data.runs);text=A.Encode(data) end
    if not text or #text>MAX_BYTES then return false,"size_limit" end
    local count=math.ceil(#text/CHUNK)
    if count>MAX_PARTS then return false,"size_limit" end
    local targets=channels();if #targets==0 then return false,"no_recipients" end
    local id=string.format("%x",math.random(1,2147483646))
    for _,channel in ipairs(targets) do
        for i=1,count do queue("D|"..id.."|"..i.."|"..count.."|"..text:sub((i-1)*CHUNK+1,i*CHUNK),channel) end
    end
    return true
end
function A.SetIngame(enabled)
    if not enabled and A.db.settings.ingame then
        -- Revoke is queued on the previously allowed channels; the transport may still be deferred by combat.
        outgoing={}
        for _,channel in ipairs(channels()) do queue("R|"..A.db.producerId,channel) end
    end
    A.db.settings.ingame=enabled==true
    if enabled then A.ShareNow() end
    A.Changed()
end
function A.ReceiveSummary(sender,data)
    if type(data)~="table" or data.v~=1 or not A.Text(data.producerId,100) or type(data.runs)~="table" or #data.runs>5 then return false end
    if data.producerId==A.db.producerId then return false end
    if type(data.facts)~="table" or #data.facts>3 then return false end
    local summary={origin="peer",receivedAt=A.Now(),producerId=A.Text(data.producerId,100),
        character=A.Copy(data.character),runs={},facts={},completedRuns=A.Number(data.completedRuns,0,1000000)}
    for _,run in ipairs(data.runs) do
        if type(run)~="table" or not A.Text(run.runId,150) or not A.Number(run.durationMs,0,604800000) then return false end
        local clean=A.Copy(run);clean.rankEligible=false;summary.runs[#summary.runs+1]=clean
    end
    for _,fact in ipairs(data.facts) do
        if type(fact)~="table" or A.ScopeFor[fact.kind]~="world_facts" then return false end
        summary.facts[#summary.facts+1]={origin="peer",kind=fact.kind,observedAt=A.Number(fact.observedAt,0),payload=A.SafeWorldPayload(fact.kind,fact.payload)}
    end
    A.peerDB.peers[sender]=summary;trimPeers();A.Changed();return true
end
function A.ReceiveMessage(prefix,message,channel,sender)
    prefix=A.Text(prefix,30);message=A.Text(message,255);channel=A.Text(channel,20);sender=A.Text(sender,150)
    if not A.db or prefix~=PREFIX or not message or not sender then return end
    -- Social messages have their own rules (every inspect needs the other player's answer) and are not "sharing summaries".
    if A.NoteEvertallyUser then A.NoteEvertallyUser(sender) end
    if message:sub(1,2)=="S|" then if A.ReceiveSocial then A.ReceiveSocial(channel,sender,message) end;return end
    if not allowed(channel) then return end
    if message:sub(1,2)=="R|" then
        local peer=A.peerDB.peers[sender]
        if peer and peer.producerId==message:sub(3) then A.peerDB.peers[sender]=nil;A.Changed() end
        return
    end
    if not A.db.settings.ingame then return end
    if message=="H|1" then
        if not lastHello[sender] or A.Monotonic()-lastHello[sender]>60 then lastHello[sender]=A.Monotonic();A.ShareNow() end
        return
    end
    local id,index,total,part=message:match("^D|([%x]+)|(%d+)|(%d+)|(.*)$")
    index=tonumber(index);total=tonumber(total)
    if not id or #id>12 or not index or not total or total<1 or total>MAX_PARTS or index<1 or index>total then return end
    local key=sender..":"..id;local now=A.Monotonic();local count=0
    for k,t in pairs(incoming) do if now-t.time>30 then incoming[k]=nil else count=count+1 end end
    local transfer=incoming[key]
    if not transfer then if count>=4 then return end;transfer={time=now,total=total,parts={},bytes=0,count=0};incoming[key]=transfer end
    if transfer.total~=total or transfer.parts[index] then return end
    transfer.parts[index]=part;transfer.bytes=transfer.bytes+#part;transfer.count=transfer.count+1
    if transfer.bytes>MAX_BYTES then incoming[key]=nil;return end
    if transfer.count==total then
        incoming[key]=nil;local data=A.Decode(table.concat(transfer.parts),MAX_BYTES)
        if data then A.ReceiveSummary(sender,data) end
    end
end
function A.PumpSync()
    if #outgoing==0 or A.Call(InCombatLockdown)==true then return end
    local now=A.Monotonic()
    if lastRefill then tokens=math.min(BURST,tokens+math.max(0,now-lastRefill)*REFILL_PER_SEC) end
    lastRefill=now
    if tokens<1 then return end
    local item=table.remove(outgoing,1)
    -- Recheck deferred live beacons after a friend goes offline or the server rejects the name.
    -- Manually requested inspect/trade whispers use other keys and retain their normal behavior.
    if item.channel=="WHISPER" and item.key and item.key:sub(1,4)=="L:F:" and A.LiveWhisperAllowed
        and not A.LiveWhisperAllowed(item.target,item.text=="S|E") then return end
    local revoke=item.text:sub(1,2)=="R|"
    if not revoke and not item.social and (not A.db.settings.ingame or not allowed(item.channel)) then return end
    if C_ChatInfo and type(C_ChatInfo.SendAddonMessage)=="function" then
        local ok,result=pcall(C_ChatInfo.SendAddonMessage,PREFIX,item.text,item.channel,item.target)
        if item.social and item.text:match("^S|[QAND]|") then
            local k,rest=item.text:match("^S|(%a)|(%x*)|?(%d*)")
            local part=item.text:match("^S|D|%x+|(%d+)|(%d+)|")
            if k~="D" or part=="1" or item.tries then A.DiagLog(string.format("send %s id=%s to=%s ok=%s result=%s tries=%s",k or "?",rest or "?",tostring(item.target),tostring(ok),tostring(ok and A.Plain(result) or result),tostring(item.tries or 0))) end
        end
        if not ok then A.errors.sync_send=(A.errors.sync_send or 0)+1
        elseif throttled(A.Plain(result)) then
            -- Retry the same chunk later; a lost chunk would invalidate the whole transfer.
            A.errors.sync_throttled=(A.errors.sync_throttled or 0)+1;tokens=0
            item.tries=(item.tries or 0)+1
            if item.tries<MAX_TRIES then table.insert(outgoing,1,item) end
            return
        end
        tokens=tokens-1
    end
end
A.On("CHAT_MSG_ADDON",A.ReceiveMessage)
A.On("PLAYER_LOGIN",function()
    trimPeers()
    if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix)=="function" then
        local ok=pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX);A.capabilities.peer_transport=ok and "registered; runtime unverified" or "unsupported"
    end
    if A.db.settings.ingame then for _,channel in ipairs(channels()) do queue("H|1",channel) end end
end)
if C_Timer and type(C_Timer.NewTicker)=="function" then C_Timer.NewTicker(0.3,A.PumpSync) end
