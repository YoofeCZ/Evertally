"""One-off patch: armory kinds, web flag, permanent trust and revoke in Social.lua (asserts every replacement count)."""
import sys
from pathlib import Path

path = Path(sys.argv[1])
s = path.read_text(encoding="utf8")


def sub(old, new, count=1):
    global s
    assert s.count(old) == count, (s.count(old), old[:70])
    s = s.replace(old, new)


sub('''-- Social tools between two players, all inside the game: look at someone's gear, bags, professions and gold (only after
-- they answer a request), propose a trade, and send a meeting point. Nothing here touches the website: what another
-- player shows you stays in memory for this session, is never saved to the addon's files and never enters the export.''',
'''-- Social tools between two players, all inside the game: look at someone's gear, bags, stats, talents, professions and
-- gold (only after they answer a request), propose a trade, and send a meeting point. What another player shows you stays
-- in memory for this session. The one exception is the letter "w" in a request: the asker wants to keep the armory on
-- their own Evertally website, and that happens only when the player being looked at ticked it in the question (or
-- allowed it permanently) and the asker's own web export and character scope are on. Gold never goes to the website.
-- Permanent permission ("always") is kept per player in the settings, never covers gold, and can be revoked at any time.''')
sub('local KIND_ORDER={"i","p","g"}', 'local KIND_ORDER={"i","s","t","p","g","w"} -- gear+bags, stats, talents, professions, gold, keep-on-website flag')

# ---------------------------------------------------------------- payload: header, stats, talents
sub('''local function inspectPayload(kinds)
    local parts={"I1"}
    if kinds:find("i",1,true) then
        local inv=A.OwnInventory()
        parts[#parts+1]="E="..itemList(inv.equipped,"%d:%d");parts[#parts+1]="B="..itemList(inv.bags,"%d*%d")
    end''', '''local function field(text) return (clean(text,40):gsub("[:,*~]"," ")) end
local function statsLine()
    local parts={};local stats=A.CollectStats and A.CollectStats() or {}
    for _,key in ipairs(A.ArmoryStatKeys or {}) do if stats[key] then parts[#parts+1]=key..":"..string.format("%g",stats[key]) end end
    return table.concat(parts,",")
end
local function talentsLine()
    local trees={}
    for _,tree in ipairs(A.CollectTalents and A.CollectTalents() or {}) do
        local ranks={};for _,r in ipairs(tree.ranks) do ranks[#ranks+1]=string.format("%d*%d",r[1],r[2]) end
        trees[#trees+1]=string.format("%s:%d:%s",field(tree.name),tree.spent,table.concat(ranks,","))
    end
    return table.concat(trees,"~")
end
local function inspectPayload(kinds)
    local parts={"I1"}
    if kinds:find("i",1,true) or kinds:find("s",1,true) or kinds:find("t",1,true) or kinds:find("p",1,true) then
        -- who this is; the sender's name comes from the whisper itself, so only class, race, level and the realm's spelling travel here
        local me=A.Character() or {}
        parts[#parts+1]=string.format("H=%d:%d:%d:%s",me.classId or 0,me.raceId or 0,me.level or 0,field(me.realm))
    end
    if kinds:find("i",1,true) then
        local inv=A.OwnInventory()
        parts[#parts+1]="E="..itemList(inv.equipped,"%d:%d");parts[#parts+1]="B="..itemList(inv.bags,"%d*%d")
    end
    if kinds:find("s",1,true) then parts[#parts+1]="S="..statsLine() end
    if kinds:find("t",1,true) then parts[#parts+1]="T="..talentsLine() end''')

sub('''    local out={equipped={},bags={},professions={}}
    for field in text:gmatch("[^;]+") do
        local tag,value=field:match("^(%u)=(.*)$")
        if tag=="E" then''', '''    local out={equipped={},bags={},professions={},stats={},talents={}}
    local statKeys={};for _,key in ipairs(A.ArmoryStatKeys or {}) do statKeys[key]=true end
    for chunk in text:gmatch("[^;]+") do
        local tag,value=chunk:match("^(%u)=(.*)$")
        if tag=="H" then
            local class,race,level,realm=value:match("^(%d+):(%d+):(%d+):([^:]*)$")
            if class then out.header={classId=A.Number(tonumber(class),1,100),raceId=A.Number(tonumber(race),1,100),level=A.Number(tonumber(level),1,1000),realm=clean(realm,40)} end
        elseif tag=="S" then
            for key,number in value:gmatch("(%l+):(%-?[%d%.]+)") do
                local n=A.Number(tonumber(number),0,10000000)
                if statKeys[key] and n then out.stats[key]=n end
            end
        elseif tag=="T" then
            for entry in value:gmatch("[^~]+") do
                local name,spent,list=entry:match("^([^:]*):(%d+):(.*)$")
                if name and #out.talents<4 then
                    local ranks={}
                    for id,rank in list:gmatch("(%d+)%*(%d+)") do
                        id,rank=tonumber(id),tonumber(rank)
                        if id>=1 and id<=100000000 and rank>=1 and rank<=100 and #ranks<80 then ranks[#ranks+1]={id,rank} end
                    end
                    out.talents[#out.talents+1]={name=clean(name,40),spent=A.Number(tonumber(spent),0,1000) or 0,ranks=ranks}
                end
            end
        elseif tag=="E" then''')

# ---------------------------------------------------------------- asking: the web flag
sub('''--- Asks `target` ("Name" or "Name-Realm") to show `kinds`: letters i (gear and bags), p (professions), g (gold).
function A.RequestInspect(target,kinds)
    target=clean(target,80);kinds=kindsOnly(kinds or "ip")
    if target=="" then return false,"no_target" end
    if kinds=="" then return false,"no_kinds" end''', '''--- The kinds a request starts with: everything but gold, plus keeping it on the website when that export is on.
function A.DefaultLookKinds()
    local web=A.db and A.db.settings.web==true and A.db.settings.scopes and A.db.settings.scopes.own_character==true
    return "istp"..(web and "w" or "")
end
--- Asks `target` ("Name" or "Name-Realm") to show `kinds`: letters i (gear and bags), s (stats), t (talents), p (professions),
--- g (gold) and w (the asker may keep it on their Evertally website). "w" alone is not a request.
function A.RequestInspect(target,kinds)
    target=clean(target,80);kinds=kindsOnly(kinds or A.DefaultLookKinds())
    if target=="" then return false,"no_target" end
    if kinds=="" or kinds=="w" then return false,"no_kinds" end
    -- a website copy is only asked for when this player can actually keep it
    if kinds:find("w",1,true) and not (A.db and A.db.settings.web==true and A.db.settings.scopes and A.db.settings.scopes.own_character==true) then kinds=kindsOnly((kinds:gsub("w",""))) end
    if kinds=="" then return false,"no_kinds" end''')

# ---------------------------------------------------------------- answering: trust
sub('''local function onRequest(sender,fields)
    local id,kinds=fields[3],kindsOnly(fields[4] or "")
    if not isId(id) or kinds=="" or not A.SocialEnabled() or blocked(sender) then return end
    local who=baseName(sender):lower()
    if (S.cooldown[who] or 0)>A.Now() or count(S.incoming)>=MAX_INCOMING then return end
    for _,entry in pairs(S.incoming) do if same(entry.sender,sender) then return end end
    S.incoming[id]={id=id,sender=sender,kinds=kinds,at=A.Now()}''', '''-- Permanent permission, one entry per player: {kinds=, sender=, at=}. It never covers gold and ends with A.RevokeAccess.
local function trustFor(sender)
    local list=A.db and A.db.settings.socialTrust
    return list and list[baseName(sender):lower()]
end
function A.SocialTrusted()
    local out={}
    for key,entry in pairs(A.db and A.db.settings.socialTrust or {}) do out[#out+1]={key=key,sender=entry.sender or key,kinds=entry.kinds,at=entry.at} end
    table.sort(out,function(a,b) return a.key<b.key end)
    return out
end

local function onRequest(sender,fields)
    local id,kinds=fields[3],kindsOnly(fields[4] or "")
    if not isId(id) or kinds=="" or kinds=="w" or not A.SocialEnabled() or blocked(sender) then return end
    local who=baseName(sender):lower()
    if (S.cooldown[who] or 0)>A.Now() or count(S.incoming)>=MAX_INCOMING then return end
    for _,entry in pairs(S.incoming) do if same(entry.sender,sender) then return end end
    S.incoming[id]={id=id,sender=sender,kinds=kinds,at=A.Now()}
    local trust=trustFor(sender)
    local covered=trust and kindsOnly(kinds,trust.kinds):gsub("w","") or ""
    if covered~="" then
        -- already allowed for good: answer without asking, with what the permission covers, and say so in chat
        local ok,state=A.AnswerRequest(id,kindsOnly(kinds,trust.kinds),false,"always")
        if ok and state=="allowed" then A.Print(string.format(A.L("socialAutoChat"),baseName(sender),baseName(sender))) end
        return
    end''')

sub('''--- Answers a request with the kinds the player agreed to share (a subset of what was asked); an empty answer declines.
function A.AnswerRequest(id,allowed)
    local request=S.incoming[id];if not request then return false,"unknown" end
    S.incoming[id]=nil
    local kinds=kindsOnly(request.kinds,allowed or "")''', '''--- Answers a request with the kinds the player agreed to share (a subset of what was asked); an empty answer declines.
--- `always` also remembers the permission for this player (without gold) until it is revoked.
function A.AnswerRequest(id,allowed,always,mode)
    local request=S.incoming[id];if not request then return false,"unknown" end
    S.incoming[id]=nil
    local kinds=kindsOnly(request.kinds,allowed or "")
    mode=(mode=="always" or (always and kinds~="")) and "always" or "once"''')
sub('''    A.QueueSocial("S|A|"..id.."|"..kinds.."|"..total,"WHISPER",request.sender)
    local ok,err=sendChunks(request.sender,id,payload)
    if not ok then return false,err end
    S.shown[#S.shown+1]={name=baseName(request.sender),kinds=kinds,at=A.Now()}''', '''    A.QueueSocial("S|A|"..id.."|"..kinds.."|"..total.."|"..(mode=="always" and "a" or "o"),"WHISPER",request.sender)
    local ok,err=sendChunks(request.sender,id,payload)
    if not ok then return false,err end
    if always and A.db then
        A.db.settings.socialTrust=A.db.settings.socialTrust or {}
        A.db.settings.socialTrust[baseName(request.sender):lower()]={kinds=kindsOnly((kinds:gsub("g",""))),sender=request.sender,at=A.Now()}
    end
    S.shown[#S.shown+1]={name=baseName(request.sender),sender=request.sender,kinds=kinds,at=A.Now(),mode=mode}''')

sub('''function A.SocialUnblock(name)''', '''--- Takes back what a player was shown or allowed: forgets the permanent permission and tells that player's addon to drop
--- (and, where it was kept on their website, to withdraw) the armory. Works for "once" answers too.
function A.RevokeAccess(name)
    name=clean(name,80);if name=="" then return false,"no_target" end
    local key=baseName(name):lower();local sender=name
    local list=A.db and A.db.settings.socialTrust
    if list and list[key] then sender=list[key].sender or name;list[key]=nil end
    for _,entry in ipairs(S.shown) do if baseName(entry.name):lower()==key then sender=entry.sender or sender;entry.revoked=true end end
    A.QueueSocial("S|X|"..shortId(),"WHISPER",sender)
    emit("revoked",{name=baseName(name)})
    return true
end
function A.SocialUnblock(name)''')

# ---------------------------------------------------------------- receiving: keep on the website, revoke notice
sub('''local function storeView(entry,text)
    local data=parseInspect(text)
    local view={id=entry.id,sender=entry.target,kinds=entry.kinds,at=A.Now(),equipped=data.equipped,bags=data.bags,gold=data.gold,professions=data.professions}
    table.insert(S.views,1,view);while #S.views>MAX_VIEWS do table.remove(S.views) end
    entry.status="done";emit("view",view)
end''', '''local function realmKey(realm) return ((realm or ""):gsub("%s+",""):lower()) end
--- Keeps what a player allowed on this player's own website account (event armory.view). The identity comes from the whisper:
--- a sender cannot claim to be somebody else. Gold and the "w" flag itself are not part of the copy.
local function forwardArmory(view,data)
    if not view.kinds:find("w",1,true) or not A.Record then return end
    local name=baseName(view.sender)
    local senderRealm=A.Text(view.sender,150):match("^[^-]+%-(.+)$")
    local header=data.header or {}
    local realm=senderRealm
    if header.realm and header.realm~="" and (not senderRealm or realmKey(header.realm)==realmKey(senderRealm)) then realm=header.realm end
    realm=realm or A.Text(A.Call(GetRealmName),80) or ""
    local equipped,bags,professions={},{},{}
    for _,e in ipairs(data.equipped) do equipped[#equipped+1]={slot=e[1],itemId=e[2]} end
    for _,e in ipairs(data.bags) do bags[#bags+1]={itemId=e[1],count=e[2]} end
    for _,p in ipairs(data.professions) do professions[#professions+1]={id=p.id,name=p.name,skill=p.skill,max=p.max} end
    local kinds=(kindsOnly(view.kinds):gsub("[gw]",""))
    A.Record("armory.view",{subject={name=name,realm=realm,classId=header.classId,raceId=header.raceId,level=header.level},mode=view.mode or "once",kinds=kinds,
        equipped=equipped,bags=bags,stats=data.stats,talents=data.talents,professions=professions},"api_snapshot",nil,true)
end
local function storeView(entry,text)
    local data=parseInspect(text)
    local view={id=entry.id,sender=entry.target,kinds=entry.kinds,at=A.Now(),mode=entry.mode,header=data.header,equipped=data.equipped,bags=data.bags,gold=data.gold,professions=data.professions,stats=data.stats,talents=data.talents}
    table.insert(S.views,1,view);while #S.views>MAX_VIEWS do table.remove(S.views) end
    entry.status="done";forwardArmory(view,data);emit("view",view)
end
local revokedNotices=0
-- The other player took their permission back: drop what we hold of them and withdraw the copy on our website.
local function onRevoked(sender)
    if blocked(sender) then return end
    local key=baseName(sender):lower()
    for i=#S.views,1,-1 do if baseName(S.views[i].sender):lower()==key then table.remove(S.views,i) end end
    local now=A.Now()
    if now-(S.lastSeen["X:"..key] or 0)<SPAM_GAP or revokedNotices>=50 then return end
    S.lastSeen["X:"..key]=now;revokedNotices=revokedNotices+1
    if A.Record then A.Record("armory.revoked",{name=baseName(sender),realm=(A.Text(sender,150):match("^[^-]+%-(.+)$"))},"api_snapshot",nil,true) end
    A.Print(string.format(A.L("socialRevokedByChat"),baseName(sender)))
    emit("viewRevoked",{name=baseName(sender)})
end''')

sub('''    entry.status="receiving";entry.kinds=kindsOnly(fields[4] or "",entry.kinds);entry.total=A.Number(tonumber(fields[5]),1,MAX_PARTS);entry.done=0''',
    '''    entry.status="receiving";entry.kinds=kindsOnly(fields[4] or "",entry.kinds);entry.total=A.Number(tonumber(fields[5]),1,MAX_PARTS);entry.done=0
    entry.mode=fields[6]=="a" and "always" or "once"''')
sub('''        elseif kind=="A" then onAccept(sender,split(5))''', '''        elseif kind=="A" then onAccept(sender,split(6))
        elseif kind=="X" then onRevoked(sender)''')

sub('''    s.socialBlock=s.socialBlock or {}
end)''', '''    s.socialBlock=s.socialBlock or {}
    s.socialTrust=s.socialTrust or {}
end)''')

# ---------------------------------------------------------------- texts
sub('''        socialDeclinedChat="%s declined your trade proposal.",socialMeetChat="%s suggests a meet: %s (Evertally > Social).",
    },''', '''        socialDeclinedChat="%s declined your trade proposal.",socialMeetChat="%s suggests a meet: %s (Evertally > Social).",
        socialAutoChat="%s looked at you (you allowed this for good). Take it back with /etally revoke %s",
        socialRevokedByChat="%s took their permission back. Their armory was removed from your view and your website.",
    },''')
sub('''        socialDeclinedChat="%s odmítl tvůj návrh výměny.",socialMeetChat="%s navrhuje sraz: %s (Evertally > Lidé).",
    },''', '''        socialDeclinedChat="%s odmítl tvůj návrh výměny.",socialMeetChat="%s navrhuje sraz: %s (Evertally > Lidé).",
        socialAutoChat="%s se na tebe podíval (povolil jsi to trvale). Odvolat můžeš příkazem /etally revoke %s",
        socialRevokedByChat="%s vzal své povolení zpět. Jeho armory zmizelo z tvého náhledu i z tvého webu.",
    },''')

path.write_text(s, encoding="utf8")
print("ok")
