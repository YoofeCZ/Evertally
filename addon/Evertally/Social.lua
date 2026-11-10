local _, A = ...
-- Social tools between two players, all inside the game: look at someone's gear, bags, professions and gold (only after
-- they answer a request), propose a trade, and send a meeting point. Nothing here touches the website: what another
-- player shows you stays in memory for this session, is never saved to the addon's files and never enters the export.
-- Messages are addon whispers (or party / guild for meets) on the same prefix as in-game sharing, sent through its
-- throttled queue. Every message type is validated and bounded before anything is shown.
local CHUNK,MAX_PARTS,MAX_PAYLOAD=200,60,12000
local REQUEST_TTL,OUTGOING_TTL,ASSEMBLY_TTL,COOLDOWN,SPAM_GAP=120,90,30,45,20
local MAX_VIEWS,MAX_PROPOSALS,MAX_MEETS,MAX_INCOMING=8,30,20,3
local KIND_ORDER={"i","p","g"}
local S={incoming={},outgoing={},views={},proposals={},meets={},shown={},cooldown={},lastSeen={},assembling={},listeners={},deferred={}}
A.social=S
A.socialHandlers={} -- message types owned by other files (Live.lua: L, E, P), called as fn(channel, sender, message)

-- ---------------------------------------------------------------- small helpers
local function utf8Safe(text)
    -- a cut inside a multi-byte character would leave an invalid tail
    local tail=text:match("[\192-\253][\128-\191]*$")
    if tail then
        local lead=tail:byte(1);local need=lead>=252 and 6 or lead>=248 and 5 or lead>=240 and 4 or lead>=224 and 3 or 2
        if #tail<need then text=text:sub(1,#text-#tail) end
    end
    return text
end
-- Printable text only: no control characters, no "|" (so no colour or link escapes), no field separators of our own.
local function clean(text,max)
    text=A.Text(text,(max or 100)+8);if not text then return "" end
    text=text:gsub("[%z\1-\31|;=~]"," "):gsub("%s+"," ")
    text=text:gsub("^%s+",""):gsub("%s+$","")
    return utf8Safe(text:sub(1,max or 100))
end
A.SocialClean=clean
local function baseName(name) return (A.Text(name,150) or ""):match("^[^-]+") or "" end
local function same(a,b) return baseName(a):lower()==baseName(b):lower() and baseName(a)~="" end
local function shortId() return string.format("%06x",math.random(0,16777215)) end
local function isId(id) return type(id)=="string" and #id==6 and id:match("^%x+$")~=nil end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local function kindsOnly(kinds,limit)
    local out={}
    for _,k in ipairs(KIND_ORDER) do if type(kinds)=="string" and kinds:find(k,1,true) and (not limit or limit:find(k,1,true)) then out[#out+1]=k end end
    return table.concat(out)
end
local function b36(n)
    n=math.floor(n);if n<=0 then return "0" end
    local digits,out="0123456789abcdefghijklmnopqrstuvwxyz",{}
    while n>0 do local d=n%36;table.insert(out,1,digits:sub(d+1,d+1));n=math.floor(n/36) end
    return table.concat(out)
end
function A.SocialEnabled() return A.db~=nil and A.db.settings.social~=false end
local function blocked(name) return A.db and A.db.settings.socialBlock and A.db.settings.socialBlock[baseName(name):lower()]==true end

function A.SocialListen(fn) S.listeners[#S.listeners+1]=fn end
local function emit(kind,data) for _,fn in ipairs(S.listeners) do pcall(fn,kind,data) end end
-- Windows that ask something are held until combat ends; the chat line is printed at once.
local function notify(kind,data)
    if A.Call(InCombatLockdown)==true then S.deferred[#S.deferred+1]={kind,data} else emit(kind,data) end
end

-- ---------------------------------------------------------------- own inventory
local function bagMax() return A.Number(NUM_BAG_SLOTS,0,10) or 4 end
local function containerSlots(bag)
    if C_Container and type(C_Container.GetContainerNumSlots)=="function" then return A.Number(A.Call(C_Container.GetContainerNumSlots,bag),0,200) or 0 end
    return A.Number(A.Call(GetContainerNumSlots,bag),0,200) or 0
end
local function containerItem(bag,slot)
    if C_Container and type(C_Container.GetContainerItemInfo)=="function" then
        local info=A.Call(C_Container.GetContainerItemInfo,bag,slot)
        return A.Number(A.Field(info,"itemID"),1,10000000),A.Number(A.Field(info,"stackCount"),1,100000) or 1
    end
    local id=A.Number(A.Call(GetContainerItemID,bag,slot),1,10000000)
    local _,stack=A.Call(GetContainerItemInfo,bag,slot)
    return id,A.Number(stack,1,100000) or 1
end
--- What the current character carries: {equipped={{slot,id}...}, bags={{id,count}...}} (distinct items, at most 400).
function A.OwnInventory()
    local out={equipped={},bags={}}
    for slot=1,19 do
        local id=A.Number(A.Call(GetInventoryItemID,"player",slot),1,10000000)
        if id then out.equipped[#out.equipped+1]={slot,id} end
    end
    local totals={}
    for bag=0,bagMax() do
        for slot=1,containerSlots(bag) do
            local id,stack=containerItem(bag,slot)
            if id then totals[id]=(totals[id] or 0)+stack end
        end
    end
    for id,n in pairs(totals) do out.bags[#out.bags+1]={id,n} end
    table.sort(out.bags,function(a,b) return a[1]<b[1] end)
    while #out.bags>400 do table.remove(out.bags) end
    return out
end

-- ---------------------------------------------------------------- payloads
local function ownProfessions(budget)
    local lines,used={},0
    local me=A.Character();local mine=me and me.id
    if not A.ProfessionSummaries or not mine then return "" end
    for _,entry in ipairs(A.ProfessionSummaries()) do
        local c=entry.character;local p=entry.payload
        if c and c.id==mine and A.Number(p.professionId,1,1000000) then
            local ids={}
            for _,recipe in ipairs(entry.recipes) do if #ids<350 then ids[#ids+1]=b36(recipe.recipeId) end end
            local line=string.format("%d:%d:%d:%s:%s",p.professionId,A.Number(p.skill,0,10000) or -1,A.Number(p.maxSkill,0,10000) or -1,(clean(p.name,40):gsub("[:,*]"," ")),table.concat(ids,","))
            if used+#line<=budget then lines[#lines+1]=line;used=used+#line+1 end
        end
    end
    return table.concat(lines,"~")
end
local function itemList(list,fmt)
    local out={}
    for _,entry in ipairs(list) do out[#out+1]=string.format(fmt,entry[1],entry[2]) end
    return table.concat(out,",")
end
local function inspectPayload(kinds)
    local parts={"I1"}
    if kinds:find("i",1,true) then
        local inv=A.OwnInventory()
        parts[#parts+1]="E="..itemList(inv.equipped,"%d:%d");parts[#parts+1]="B="..itemList(inv.bags,"%d*%d")
    end
    if kinds:find("g",1,true) then parts[#parts+1]="G="..string.format("%d",A.Number(A.Call(GetMoney),0,1e12) or 0) end
    if kinds:find("p",1,true) then parts[#parts+1]="P="..ownProfessions(MAX_PAYLOAD-#table.concat(parts,";")-200) end
    return table.concat(parts,";")
end
local function parseInspect(text)
    local out={equipped={},bags={},professions={}}
    for field in text:gmatch("[^;]+") do
        local tag,value=field:match("^(%u)=(.*)$")
        if tag=="E" then
            for slot,id in value:gmatch("(%d+):(%d+)") do
                slot,id=tonumber(slot),tonumber(id)
                if slot>=1 and slot<=19 and id>=1 and id<=10000000 and #out.equipped<25 then out.equipped[#out.equipped+1]={slot,id} end
            end
        elseif tag=="B" then
            for id,n in value:gmatch("(%d+)%*(%d+)") do
                id,n=tonumber(id),tonumber(n)
                if id>=1 and id<=10000000 and n>=1 and n<=100000 and #out.bags<400 then out.bags[#out.bags+1]={id,n} end
            end
        elseif tag=="G" then out.gold=A.Number(tonumber(value),0,1e12)
        elseif tag=="P" then
            for entry in value:gmatch("[^~]+") do
                local pid,skill,max,name,recipes=entry:match("^(%d+):(%-?%d+):(%-?%d+):([^:]*):(.*)$")
                if pid and #out.professions<12 then
                    local ids={}
                    for r in recipes:gmatch("%w+") do local id=tonumber(r,36);if id and id>=1 and id<=10000000 and #ids<400 then ids[#ids+1]=id end end
                    skill,max=tonumber(skill),tonumber(max)
                    out.professions[#out.professions+1]={id=tonumber(pid),name=clean(name,40),skill=skill>=0 and skill or nil,max=max>=0 and max or nil,recipes=ids}
                end
            end
        end
    end
    return out
end
local function proposalPayload(p)
    local function items(list) local out={};for _,e in ipairs(list or {}) do if #out<8 then out[#out+1]={e[1],e[2]} end end;return itemList(out,"%d*%d") end
    return table.concat({"T1","W="..items(p.want),"O="..items(p.offer),"G="..string.format("%d",A.Number(p.gold,0,99999999) or 0),"N="..clean(p.note,120)},";")
end
local function parseProposal(text)
    local out={want={},offer={},gold=0,note=""}
    local head,note=text:match("^(.-);N=(.*)$")
    out.note=clean(note,120)
    for field in (head or text):gmatch("[^;]+") do
        local tag,value=field:match("^(%u)=(.*)$")
        local list=tag=="W" and out.want or tag=="O" and out.offer
        if list then
            for id,n in value:gmatch("(%d+)%*(%d+)") do
                id,n=tonumber(id),tonumber(n)
                if id>=1 and id<=10000000 and n>=1 and n<=100000 and #list<8 then list[#list+1]={id,n} end
            end
        elseif tag=="G" then out.gold=A.Number(tonumber(value),0,99999999) or 0 end
    end
    return out
end

-- ---------------------------------------------------------------- sending in chunks
local function sendChunks(target,id,payload)
    local total=math.ceil(#payload/CHUNK)
    if total<1 or total>MAX_PARTS then return false,"size_limit" end
    for i=1,total do
        if not A.QueueSocial("S|D|"..id.."|"..i.."|"..total.."|"..payload:sub((i-1)*CHUNK+1,i*CHUNK),"WHISPER",target) then return false,"queue_full" end
    end
    return true,total
end

-- ---------------------------------------------------------------- asking to look at a player
--- Asks `target` ("Name" or "Name-Realm") to show `kinds`: letters i (gear and bags), p (professions), g (gold).
function A.RequestInspect(target,kinds)
    target=clean(target,80);kinds=kindsOnly(kinds or "ip")
    if target=="" then return false,"no_target" end
    if kinds=="" then return false,"no_kinds" end
    if same(target,A.Text(A.Call(UnitName,"player"),80)) then return false,"self" end
    for _,entry in pairs(S.outgoing) do if same(entry.target,target) and (entry.status=="waiting" or entry.status=="receiving") then return false,"pending" end end
    local id=shortId()
    if not A.QueueSocial("S|Q|"..id.."|"..kinds,"WHISPER",target) then return false,"queue_full" end
    S.outgoing[id]={id=id,target=target,kinds=kinds,at=A.Now(),status="waiting"}
    emit("outgoing",S.outgoing[id]);return true,id
end

local function onRequest(sender,fields)
    local id,kinds=fields[3],kindsOnly(fields[4] or "")
    if not isId(id) or kinds=="" or not A.SocialEnabled() or blocked(sender) then return end
    local who=baseName(sender):lower()
    if (S.cooldown[who] or 0)>A.Now() or count(S.incoming)>=MAX_INCOMING then return end
    for _,entry in pairs(S.incoming) do if same(entry.sender,sender) then return end end
    S.incoming[id]={id=id,sender=sender,kinds=kinds,at=A.Now()}
    -- the chat line works even when the window cannot be built: /etally allow <id> or /etally deny <id>
    A.Print(string.format(A.L("socialAskChat"),baseName(sender),id,id))
    notify("request",S.incoming[id])
end

--- Answers a request with the kinds the player agreed to share (a subset of what was asked); an empty answer declines.
function A.AnswerRequest(id,allowed)
    local request=S.incoming[id];if not request then return false,"unknown" end
    S.incoming[id]=nil
    local kinds=kindsOnly(request.kinds,allowed or "")
    if kinds=="" then
        A.QueueSocial("S|N|"..id,"WHISPER",request.sender);S.cooldown[baseName(request.sender):lower()]=A.Now()+COOLDOWN
        return true,"denied"
    end
    local payload=inspectPayload(kinds)
    if #payload>MAX_PAYLOAD then payload=inspectPayload((kinds:gsub("p",""))) end
    local total=math.ceil(#payload/CHUNK)
    if total>MAX_PARTS then A.QueueSocial("S|N|"..id,"WHISPER",request.sender);return false,"size_limit" end
    A.QueueSocial("S|A|"..id.."|"..kinds.."|"..total,"WHISPER",request.sender)
    local ok,err=sendChunks(request.sender,id,payload)
    if not ok then return false,err end
    S.shown[#S.shown+1]={name=baseName(request.sender),kinds=kinds,at=A.Now()}
    while #S.shown>20 do table.remove(S.shown,1) end
    emit("shown",S.shown[#S.shown]);return true,"allowed"
end
function A.DenyRequest(id,block)
    local request=S.incoming[id];if not request then return false end
    if block and A.db then A.db.settings.socialBlock=A.db.settings.socialBlock or {};A.db.settings.socialBlock[baseName(request.sender):lower()]=true end
    return A.AnswerRequest(id,"")
end
function A.SocialUnblock(name) if A.db and A.db.settings.socialBlock then A.db.settings.socialBlock[baseName(name):lower()]=nil end end

-- ---------------------------------------------------------------- receiving data
local function storeView(entry,text)
    local data=parseInspect(text)
    local view={id=entry.id,sender=entry.target,kinds=entry.kinds,at=A.Now(),equipped=data.equipped,bags=data.bags,gold=data.gold,professions=data.professions}
    table.insert(S.views,1,view);while #S.views>MAX_VIEWS do table.remove(S.views) end
    entry.status="done";emit("view",view)
end
local function storeProposal(sender,id,text)
    local now=A.Now()
    if blocked(sender) or now-(S.lastSeen["T:"..baseName(sender):lower()] or 0)<SPAM_GAP then return end
    S.lastSeen["T:"..baseName(sender):lower()]=now
    local p=parseProposal(text)
    if #p.want==0 and #p.offer==0 and p.gold==0 and p.note=="" then return end
    local entry={id=id,dir="in",peer=sender,want=p.want,offer=p.offer,gold=p.gold,note=p.note,at=now,status="open"}
    table.insert(S.proposals,1,entry);while #S.proposals>MAX_PROPOSALS do table.remove(S.proposals) end
    A.Print(string.format(A.L("socialProposalChat"),baseName(sender)))
    notify("proposal",entry)
end
local function finishTransfer(sender,id,text)
    if text:sub(1,2)=="I1" then
        local entry=S.outgoing[id]
        if entry and same(entry.target,sender) and (entry.status=="receiving" or entry.status=="waiting") then storeView(entry,text) end
    elseif text:sub(1,2)=="T1" then storeProposal(sender,id,text) end
end
local function onChunk(sender,fields)
    local id,index,total,part=fields[3],tonumber(fields[4]),tonumber(fields[5]),fields[6]
    if not isId(id) or not index or not total or total<1 or total>MAX_PARTS or index<1 or index>total or not part then return end
    local key=sender..":"..id;local now=A.Monotonic()
    local live=0
    for k,t in pairs(S.assembling) do if now-t.time>ASSEMBLY_TTL then S.assembling[k]=nil else live=live+1 end end
    local transfer=S.assembling[key]
    if not transfer then
        -- only data somebody asked for (an inspect answer) or a short proposal may start a transfer
        local entry=S.outgoing[id]
        if live>=4 or (not entry and total>8) then return end
        transfer={time=now,total=total,parts={},bytes=0,count=0};S.assembling[key]=transfer
    end
    if transfer.total~=total or transfer.parts[index] then return end
    transfer.parts[index]=part;transfer.bytes=transfer.bytes+#part;transfer.count=transfer.count+1;transfer.time=now
    if transfer.bytes>MAX_PAYLOAD+400 then S.assembling[key]=nil;return end
    local entry=S.outgoing[id]
    if entry and entry.status=="receiving" then entry.done=transfer.count;emit("progress",entry) end
    if transfer.count==total then S.assembling[key]=nil;finishTransfer(sender,id,table.concat(transfer.parts)) end
end
local function onAccept(sender,fields)
    local entry=S.outgoing[fields[3] or ""]
    if not entry or not same(entry.target,sender) or entry.status~="waiting" then return end
    entry.status="receiving";entry.kinds=kindsOnly(fields[4] or "",entry.kinds);entry.total=A.Number(tonumber(fields[5]),1,MAX_PARTS);entry.done=0
    emit("progress",entry)
end
local function onDeny(sender,fields)
    local entry=S.outgoing[fields[3] or ""]
    if entry and same(entry.target,sender) and entry.status=="waiting" then entry.status="denied";emit("outgoing",entry) end
end

-- ---------------------------------------------------------------- trade proposals
--- proposal = {want={{itemId,count}...}, offer={{itemId,count}...}, gold=copper, note=text}. A proposal is only a message:
--- the trade itself happens in the normal trade window, between the two players.
function A.SendProposal(target,proposal)
    target=clean(target,80)
    if target=="" or type(proposal)~="table" then return false,"no_target" end
    local id=shortId()
    local ok,err=sendChunks(target,id,proposalPayload(proposal))
    if not ok then return false,err end
    local p=parseProposal(proposalPayload(proposal))
    local entry={id=id,dir="out",peer=target,want=p.want,offer=p.offer,gold=p.gold,note=p.note,at=A.Now(),status="sent"}
    table.insert(S.proposals,1,entry);while #S.proposals>MAX_PROPOSALS do table.remove(S.proposals) end
    emit("proposalSent",entry);return true,id
end
function A.AnswerProposal(id,accept,message)
    for _,entry in ipairs(S.proposals) do
        if entry.id==id and entry.dir=="in" and entry.status=="open" then
            entry.status=accept and "accepted" or "declined"
            A.QueueSocial("S|R|"..id.."|"..(accept and "ok" or "no").."|"..clean(message,60),"WHISPER",entry.peer)
            emit("proposalAnswered",entry);return true
        end
    end
    return false
end
local function onReply(sender,fields)
    local id,answer,message=fields[3],fields[4],clean(fields[5] or "",60)
    for _,entry in ipairs(S.proposals) do
        if entry.id==id and entry.dir=="out" and same(entry.peer,sender) and entry.status=="sent" then
            entry.status=answer=="ok" and "accepted" or "declined";entry.reply=message
            A.Print(string.format(A.L(answer=="ok" and "socialAcceptedChat" or "socialDeclinedChat"),baseName(sender)))
            emit("proposalAnswered",entry);return
        end
    end
end

-- ---------------------------------------------------------------- meets
local MEET_CHANNELS={WHISPER=true,PARTY=true,RAID=true,GUILD=true,INSTANCE_CHAT=true}
--- Sends the current position as a meet. `channel` is PARTY, RAID, GUILD or WHISPER (then with `target`).
function A.SendMeet(channel,target,label,minutes)
    if not MEET_CHANNELS[channel] then return false,"channel" end
    if channel=="WHISPER" and clean(target,80)=="" then return false,"no_target" end
    local map,x,y=A.PlayerPosition()
    if not map or not x or not y then return false,"no_position" end
    local text=string.format("S|M|%s|%d|%d|%d|%d|%s",shortId(),map,math.floor(x*1000+0.5),math.floor(y*1000+0.5),A.Number(minutes,0,1440) or 0,clean(label,60))
    if not A.QueueSocial(text,channel,channel=="WHISPER" and clean(target,80) or nil) then return false,"queue_full" end
    return true
end
local function onMeet(channel,sender,fields)
    if not MEET_CHANNELS[channel] or not A.SocialEnabled() or blocked(sender) or same(sender,A.Text(A.Call(UnitName,"player"),80)) then return end
    local map,x,y,minutes=A.Number(tonumber(fields[4]),1,100000),A.Number(tonumber(fields[5]),0,1000),A.Number(tonumber(fields[6]),0,1000),A.Number(tonumber(fields[7]),0,1440)
    if not isId(fields[3]) or not map or not x or not y or not minutes then return end
    local now=A.Now();local who="M:"..baseName(sender):lower()
    if now-(S.lastSeen[who] or 0)<SPAM_GAP then return end
    S.lastSeen[who]=now
    local meet={id=fields[3],sender=sender,mapId=math.floor(map),x=x/1000,y=y/1000,minutes=math.floor(minutes),label=clean(fields[8],60),at=now,channel=channel}
    table.insert(S.meets,1,meet);while #S.meets>MAX_MEETS do table.remove(S.meets) end
    A.Print(string.format(A.L("socialMeetChat"),baseName(sender),meet.label))
    notify("meet",meet)
end
--- Marks a received meet on the map: a waypoint where the client has them, otherwise the map of its zone.
function A.SetMeetWaypoint(meet)
    if type(meet)~="table" then return false end
    if C_Map and type(C_Map.SetUserWaypoint)=="function" and UiMapPoint and type(UiMapPoint.CreateFromCoordinates)=="function" then
        local ok=pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(meet.mapId,meet.x,meet.y))
            if C_SuperTrack and type(C_SuperTrack.SetSuperTrackedUserWaypoint)=="function" then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
        if ok then return true end
    end
    if A.OpenRecordedMap then return A.OpenRecordedMap({mapId=meet.mapId}) end
    return false
end

-- ---------------------------------------------------------------- entry point and housekeeping
function A.ReceiveSocial(channel,sender,message)
    if not A.db then return end
    local kind=message:sub(3,3)
    local handler=A.socialHandlers[kind]
    if handler then handler(channel,sender,message);return end
    local function split(n)
        local out,pos={},1
        for i=1,n-1 do local at=message:find("|",pos,true);if not at then break end;out[i]=message:sub(pos,at-1);pos=at+1 end
        out[#out+1]=message:sub(pos);return out
    end
    if channel=="WHISPER" then
        if kind=="Q" then onRequest(sender,split(4))
        elseif kind=="N" then onDeny(sender,split(3))
        elseif kind=="A" then onAccept(sender,split(5))
        elseif kind=="D" then if A.SocialEnabled() or next(S.outgoing) then onChunk(sender,split(6)) end
        elseif kind=="R" then onReply(sender,split(5)) end
    end
    if kind=="M" then onMeet(channel,sender,split(8)) end
end
function A.SocialTick()
    local now=A.Now()
    for id,entry in pairs(S.incoming) do if now-entry.at>REQUEST_TTL then S.incoming[id]=nil;emit("requestExpired",entry) end end
    for _,entry in pairs(S.outgoing) do
        if (entry.status=="waiting" or entry.status=="receiving") and now-entry.at>OUTGOING_TTL+(entry.total or 0)*2 then entry.status="noanswer";emit("outgoing",entry) end
    end
end
function A.SocialRequests() return S.incoming end
function A.SocialAccessLog() return S.shown end

A.On("PLAYER_LOGIN",function()
    local s=A.db.settings
    if s.social==nil then s.social=true end
    s.socialBlock=s.socialBlock or {}
end)
A.On("PLAYER_REGEN_ENABLED",function()
    local list=S.deferred;S.deferred={}
    for _,item in ipairs(list) do emit(item[1],item[2]) end
end)
if C_Timer and type(C_Timer.NewTicker)=="function" then C_Timer.NewTicker(5,A.SocialTick) end

-- ---------------------------------------------------------------- texts
local text={
    en={
        social="Social",sub_social="Look at another player's gear, bags and professions after they allow it, propose trades, and share meeting points.",
        socialEnabled="Let other players ask to see my gear and professions (I decide every time)",
        socialAskChat="%s asks to look at you. Answer in the window, or type /etally allow %s  or  /etally deny %s",
        socialProposalChat="%s sent you a trade proposal (Evertally > Social).",socialAcceptedChat="%s accepted your trade proposal. Meet and use the trade window.",
        socialDeclinedChat="%s declined your trade proposal.",socialMeetChat="%s suggests a meet: %s (Evertally > Social).",
    },
    cs={
        social="Lidé",sub_social="Podívej se hráči do výbavy, tašek a profesí, až to povolí; navrhni výměnu a pošli místo srazu.",
        socialEnabled="Povolit ostatním požádat o pohled do výbavy a profesí (pokaždé rozhoduju já)",
        socialAskChat="%s se chce na tebe podívat. Odpověz v okně, nebo napiš /etally allow %s  či  /etally deny %s",
        socialProposalChat="%s ti poslal návrh výměny (Evertally > Lidé).",socialAcceptedChat="%s přijal tvůj návrh výměny. Sejděte se a použijte okno výměny.",
        socialDeclinedChat="%s odmítl tvůj návrh výměny.",socialMeetChat="%s navrhuje sraz: %s (Evertally > Lidé).",
    },
}
for lang,entries in pairs(text) do for key,value in pairs(entries) do A.locale[lang][key]=value end end
