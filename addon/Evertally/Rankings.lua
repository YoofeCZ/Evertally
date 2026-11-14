local _, A = ...
-- Personal/shared observations. Unknown measurements never become zero damage or a realm score.
local text = {
 en={rankings="Leaderboard",sub_rankings="Your retained runs, players who shared with you in game and the website's public leaderboard (through the Evertally app). Personal observations, not a realm-wide competitive ranking.",rankModeRuns="Completions",rankModeLevel="Level",rankModeFastest="Best time",rankModeDungeons="Instances",rankModeDps="DPS",rankModeHeals="HPS",rankModeHistory="Run history",rankYou="You are #%d of %d",rankYouAlone="Local records only. Other players appear after sharing.",rankNoRuns="No completed timed run recorded.",rankRuns="%d completed",rankLevel="Level %s",rankPlayers="%d players",rankNoData="No matching records.",rankSelf="you",rankReceived="received",rankAll="All",rankParty="Dungeons",rankRaid="Raids",rankClass="Class",rankRace="Race",rankBack="< Leaderboard",rankUnrecorded="Not recorded",rankCombat="Combat measurements",rankActive="Combat time",rankCovered="Observation time",rankDamage="Damage",rankHealing="Effective healing",rankOverheal="Overhealing",rankTaken="Damage taken",rankDeaths="Deaths",rankBosses="Bosses",rankGroup="Group size",rankDuration="Run duration",rankStatus="Status",rankFinished="Completion evidence",rankRoster="Players in this run",rankPartial="Partial coverage · excluded from DPS/HPS rankings",rankObserved="Observed coverage · local measurements",rankUnavailable="Combat data unavailable · excluded from DPS/HPS rankings",rankScope="Group totals; rates below belong to individual players.",rankRateNote="DPS/HPS use recorded combat seconds. Different instances and incomplete observations are not directly comparable.",rankNoHistory="No retained runs for this player and filter.",rankReference="Reference entry · no observed run",rankCompleted="completed",rankInterrupted="interrupted",rankManual="manually ended",rankVisiting="visiting",rankUnknown="Unknown",rankNoBosses="No individual boss events recorded.",rankPersonal="Personal/shared record · no verified competitive score",rankFilterHint="Choose category, class, race and instance; click a player or run for details."},
 cs={rankings="Žebříček",sub_rankings="Tvoje uložené běhy, hráči, kteří s tebou sdíleli ve hře, a veřejný žebříček webu (přes aplikaci Evertally). Osobní záznamy, ne soutěžní žebříček celého serveru.",rankModeRuns="Dokončení",rankModeLevel="Úroveň",rankModeFastest="Nejlepší čas",rankModeDungeons="Instance",rankModeDps="DPS",rankModeHeals="HPS",rankModeHistory="Běhy",rankYou="Jsi #%d z %d",rankYouAlone="Jen místní záznamy. Další hráči se objeví po sdílení.",rankNoRuns="Žádný dokončený běh se zaznamenaným časem.",rankRuns="dokončeno: %d",rankLevel="Úroveň %s",rankPlayers="Hráčů: %d",rankNoData="Žádné odpovídající záznamy.",rankSelf="ty",rankReceived="přijato",rankAll="Vše",rankParty="Dungeony",rankRaid="Raidy",rankClass="Třída",rankRace="Rasa",rankBack="< Žebříček",rankUnrecorded="Nezaznamenáno",rankCombat="Bojové statistiky",rankActive="Čas v boji",rankCovered="Doba pozorování",rankDamage="Poškození",rankHealing="Účinné léčení",rankOverheal="Přeléčení",rankTaken="Přijaté poškození",rankDeaths="Úmrtí",rankBosses="Bossové",rankGroup="Velikost skupiny",rankDuration="Doba běhu",rankStatus="Stav",rankFinished="Doklad dokončení",rankRoster="Hráči v tomto běhu",rankPartial="Částečné pokrytí · neřadí se podle DPS/HPS",rankObserved="Pozorované pokrytí · místní měření",rankUnavailable="Bojová data nejsou dostupná · neřadí se podle DPS/HPS",rankScope="Součty patří celé skupině; hodnoty níže jednotlivým hráčům.",rankRateNote="DPS/HPS používají zaznamenaný čas v boji. Různé instance a neúplná měření nelze přímo porovnávat.",rankNoHistory="Pro hráče a zvolený filtr nejsou uložené běhy.",rankReference="Referenční položka · bez zaznamenaného běhu",rankCompleted="dokončeno",rankInterrupted="přerušeno",rankManual="ručně ukončeno",rankVisiting="návštěva",rankUnknown="Neznámé",rankNoBosses="Jednotliví bossové nebyli zaznamenáni.",rankPersonal="Osobní/sdílený záznam · bez ověřeného soutěžního skóre",rankFilterHint="Vyber kategorii, třídu, rasu a instanci; kliknutím otevřeš hráče nebo běh."},
}
for lang,entries in pairs(text) do for key,value in pairs(entries) do A.locale[lang][key]=value end end
A.locale.en.rankObservedGroup="observed in your group"
A.locale.cs.rankObservedGroup="pozorováno ve tvé skupině"
A.locale.en.rankWithoutRuns="No recorded runs";A.locale.cs.rankWithoutRuns="Bez běhů"
A.locale.en.rankSource="Source";A.locale.cs.rankSource="Zdroj"
A.locale.en.rankMeter="Game damage meter";A.locale.cs.rankMeter="Herní měřič"
A.locale.en.rankLog="Combat log";A.locale.cs.rankLog="Bojový deník"
A.locale.en.rankLastBoss="Last boss observed";A.locale.cs.rankLastBoss="Pozorován poslední boss"
A.locale.en.rankFullClear="Full clear reported";A.locale.cs.rankFullClear="Nahlášen úplný průchod"
A.locale.en.rankBossFight="fight";A.locale.cs.rankBossFight="boj"
A.locale.en.rankBossElapsed="since run start";A.locale.cs.rankBossElapsed="od začátku běhu"
A.locale.en.rankEndManual="End this record as a manual run";A.locale.cs.rankEndManual="Ukončit tento záznam jako ruční běh"
A.locale.en.rankAbsorbs="Absorbs";A.locale.cs.rankAbsorbs="Absorpce"
A.locale.en.rankInterrupts="Interrupts";A.locale.cs.rankInterrupts="Přerušení"
A.locale.en.rankDispels="Dispels";A.locale.cs.rankDispels="Dispel"
A.locale.en.rankSearch="Find player or realm";A.locale.cs.rankSearch="Hledat hráče nebo realm"
A.locale.en.rankClear="Clear";A.locale.cs.rankClear="Vymazat"
A.locale.en.rankColumns="RANK / CHARACTER";A.locale.cs.rankColumns="POŘADÍ / POSTAVA"
A.locale.en.rankResult="RESULT";A.locale.cs.rankResult="VÝSLEDEK"
A.locale.en.rankNoMatches="No locally available players match.";A.locale.cs.rankNoMatches="Žádný místně dostupný hráč neodpovídá."
A.locale.en.rankWeb="website #%d";A.locale.cs.rankWeb="web #%d"
A.locale.en.rankWebDetail="On the website's public leaderboard as #%d. Their runs stay on the website; only the summary comes to the game.";A.locale.cs.rankWebDetail="Na veřejném žebříčku webu jako #%d. Běhy zůstávají na webu; do hry přichází jen souhrn."
local CS_LOWER={["Á"]="á",["Č"]="č",["Ď"]="ď",["É"]="é",["Ě"]="ě",["Í"]="í",["Ň"]="ň",["Ó"]="ó",["Ř"]="ř",["Š"]="š",["Ť"]="ť",["Ú"]="ú",["Ů"]="ů",["Ý"]="ý",["Ž"]="ž"}
local function fold(value)
 local s=tostring(A.Plain(value) or ""):gsub("[A-Z]",function(c)return string.char(c:byte()+32) end)
 return (s:gsub("[\195-\197][\128-\191]",function(c)return CS_LOWER[c] or c end))
end
local function matchesSearch(entry,query)
 if query=="" then return true end
 local c=entry and entry.character or {}
 local name=entry and entry.name or c.name
 local full=tostring(A.Plain(name) or "").."-"..tostring(A.Plain(c.realm) or "")
 return fold(full):find(query,1,true)~=nil
end
local CS_UPPER={["á"]="Á",["č"]="Č",["ď"]="Ď",["é"]="É",["ě"]="Ě",["í"]="Í",["ň"]="Ň",["ó"]="Ó",["ř"]="Ř",["š"]="Š",["ť"]="Ť",["ú"]="Ú",["ů"]="Ů",["ý"]="Ý",["ž"]="Ž"}
local function upperText(s)
 s=tostring(s or ""):gsub("[a-z]",function(c) return string.char(c:byte()-32) end)
 return (s:gsub("[\195-\197][\128-\191]",function(c) return CS_UPPER[c] or c end))
end
local function fitIndex(text,width,measure)
 local value=tostring(text or "");measure:SetText(value)
 if (measure:GetStringWidth() or 0)<=width then return value end
 while value~="" do
  value=value:match("^(.*)[\1-\127\194-\244][\128-\191]*$") or "";measure:SetText(value.."...")
  if (measure:GetStringWidth() or 0)<=width then return value.."..." end
 end
 return "..."
end
local MODES={"runs","level","fastest","dungeons","dps","heals","history"}
local CLASSES={false,1,2,3,4,5,7,8,9,11,0}
local RACES={false,1,2,3,4,5,6,7,8,95,96,0}
local KINDS={false,"party","raid"}
local function num(v) return A.Number(v,0) end
local function countText(v) local n=num(v);return n and string.format("%.0f",n) or A.L("rankUnrecorded") end
local function modeLabel(mode) return A.L("rankMode"..mode:sub(1,1):upper()..mode:sub(2)) end
local function kindLabel(kind) return A.L(kind=="party" and "rankParty" or kind=="raid" and "rankRaid" or "rankAll") end
local function byName(a,b) return tostring(A.Plain(a.name))<tostring(A.Plain(b.name)) end
local function matchesId(actual,wanted) return wanted==nil or wanted==false or (wanted==0 and not num(actual)) or actual==wanted end
local function characterMatches(c,f) c=c or {};f=f or {};return matchesId(c.classId,f.classId) and matchesId(c.raceId,f.raceId) end
local function referenceKinds()
 local kinds={}
 for _,item in ipairs(A.InstanceCatalog or {}) do kinds[item.name]=item.kind=="raid" and "raid" or "party" end
 for _,row in ipairs(A.finalBosses or {}) do kinds[row[3]]="party" end
 for _,item in ipairs(A.map and A.map.layerData and A.map.layerData.instances or {}) do
  if item.kind=="raid" or item.kind=="dungeon" then kinds[item.name]=item.kind=="raid" and "raid" or "party" end
 end
 for _,rule in pairs(A.rulesets or {}) do if rule.name or rule.dungeon then kinds[rule.name or rule.dungeon]=rule.instanceType end end
 return kinds
end
local function runMatches(run,dungeon,filters,kinds)
 return (not dungeon or run.name==dungeon) and (not filters.kind or filters.kind==(run.instanceType or kinds[run.name]))
end
local function players(dungeon,filters)
 filters=filters or {};local db,me=A.db,A.Character();local list,seen={},{}
 local own={key="own:"..(me and me.id or "?"),name=me and me.name or "?",character=me,own=true,runs={},completed=0,level=me and me.level}
 for _,run in ipairs(db.runs or {}) do if run.character and me and run.character.id==me.id then own.runs[#own.runs+1]=run end end
 local active=A.ActiveRun and A.ActiveRun()
 if active and active.character and me and active.character.id==me.id then
  local duplicate=false;for _,run in ipairs(own.runs) do if run.runId and run.runId==active.runId then duplicate=true;break end end
  if not duplicate then own.runs[#own.runs+1]=active end
 end
 list[1]=own;seen[tostring(db.producerId)..":"..(me and me.id or "unknown")]=true
 for sender,peer in pairs(A.peerDB.peers or {}) do
  local key=tostring(peer.producerId)..":"..(peer.character and peer.character.id or sender)
  if not seen[key] then seen[key]=true;list[#list+1]={key=key,name=peer.character and peer.character.name or sender,character=peer.character,runs=peer.runs or {},receivedAt=peer.receivedAt,level=peer.character and peer.character.level,summaryCompleted=num(peer.completedRuns)} end
 end
 -- The website's public leaderboard (RankingData.lua, written by the Evertally app): players who paired the app and chose
 -- to show the character. Only a summary arrives (level, completed runs), so they rank by runs and level, not by times.
 local board;if A.RankingIndex then board=select(2,A.RankingIndex()) end
 if type(board)=="table" and type(board.players)=="table" then
  local function realmKey(r) return (A.Text(r,100) or ""):gsub("[%s%-']",""):lower() end
  local ownRealm=me and me.realm
  local listed={}
  for _,e in ipairs(list) do local c=e.character;local name=c and A.Text(c.name,100) or A.Text(e.name,100)
   local short=name and name:match("^[^%-%s]+")
   if short then listed[short:lower().."|"..realmKey(c and c.realm or ownRealm)]=true end
  end
  for _,w in ipairs(board.players) do
   local name,realm=type(w)=="table" and A.Text(w.n,80),type(w)=="table" and A.Text(w.r,80)
   local k=name and realm and not name:find("[%s%-]") and (name:lower().."|"..realmKey(realm))
   if k and not listed[k] then
    listed[k]=true
    local c={name=name,realm=realm,classId=A.Number(w.c,1,100),raceId=A.Number(w.x,1,100),level=A.Number(w.l,1,100)}
    list[#list+1]={key="web:"..k,name=name,character=c,runs={},web=true,webRank=A.Number(w.k,1,1000000),level=c.level,summaryCompleted=num(w.u) or 0}
   end
  end
 end
 -- Native meter/combat-log actors are useful even if they do not run this addon.
 -- Keep them distinct from shared profiles and never create an actor from group totals.
 local knownGuids,observed={},{ }
 for _,entry in ipairs(list) do local id=entry.character and entry.character.id;if id then knownGuids[id]=true end end
 for _,run in ipairs(own.runs) do
  for _,p in ipairs(type(run.combat)=="table" and run.combat.players or {}) do
   local guid=A.Text(p.guid,100)
   if guid and guid:match("^Player%-") and not knownGuids[guid] and (num(p.damage)~=nil or num(p.healing)~=nil) then
    local entry=observed[guid]
    if not entry then
     local c={id=guid,name=p.name or "?",classId=p.classId,raceId=p.raceId,level=p.level}
     entry={key="observed:"..guid,name=c.name,character=c,observed=true,runs={},runKeys={},level=c.level};observed[guid]=entry;list[#list+1]=entry
    end
    local key=run.runId or tostring(run)
    if not entry.runKeys[key] then entry.runKeys[key]=true;entry.runs[#entry.runs+1]=run end
   end
  end
 end
 local filtered,kinds={},referenceKinds()
 for _,e in ipairs(list) do if characterMatches(e.character,filters) then
  local runs,completed={},0
  for _,run in ipairs(e.runs) do if runMatches(run,dungeon,filters,kinds) then runs[#runs+1]=run;if run.status=="completed" then completed=completed+1 end end end
  e.runs=runs;e.completed=not dungeon and not filters.kind and e.summaryCompleted or completed;filtered[#filtered+1]=e
 end end
 return filtered
end
local function matchingCombatPlayer(run,character)
 local combat=run and run.combat;if type(combat)~="table" then return end
 local id=character and (character.id or character.guid);local name=character and character.name
 local full=name and character.realm and (name.."-"..character.realm)
 for _,p in ipairs(combat.players or {}) do
  local guid=p.guid or p.id
  if id and guid then if id==guid then return p end
  elseif name and (p.name==name or p.name==full) then return p end
 end
end
-- Rates require attributable individual measurements. Group totals are never treated as the owner's damage.
function A.RankingRate(run,character,metric,allowPartial)
 local c=run and run.combat
 if type(c)~="table" or (c.source~="combat_log" and c.source~="damage_meter") or c.coverage=="unavailable" or not allowPartial and c.coverage~="observed" then return end
 local p=matchingCombatPlayer(run,character);if not p then return end
 local value=num(p[metric=="heals" and "healing" or "damage"]);local ms=A.Number(p.activeMs,1) or A.Number(c.activeMs,1)
 if value==nil or not ms then return end
 return value/(ms/1000),p,ms
end
local function bestRun(e)
 local best;for _,r in ipairs(e.runs) do local ms=A.Number(r.durationMs,1);if r.status=="completed" and ms and (not best or ms<best.durationMs) then best=r end end;return best
end
function A.RankingRows(kit,mode,dungeon,filters)
 local list,rows=players(dungeon,filters),{}
 local query=fold(((filters and filters.query) or ""):match("^%s*(.-)%s*$"))
 local function source(e) return e.own and A.L("rankSelf") or e.observed and A.L("rankObservedGroup") or e.web and string.format(A.L("rankWeb"),e.webRank or 0) or (A.L("rankReceived").." "..kit.stamp(e.receivedAt)) end
 local function row(e,value,fraction,run) return {key=e.key,name=e.name,character=e.character,own=e.own,valueText=value,fraction=fraction,entry=e,run=run,sub=kit.identityText(e.character).." · "..source(e)} end
 if mode=="runs" or mode=="level" then
  local field=mode=="runs" and "completed" or "level"
  table.sort(list,function(a,b)local x,y=a[field] or 0,b[field] or 0;if x==y then return byName(a,b) end;return x>y end)
  local top=math.max(1,list[1] and list[1][field] or 1)
  for _,e in ipairs(list) do rows[#rows+1]=row(e,mode=="runs" and tostring(e.completed) or (e.level and string.format(A.L("rankLevel"),e.level) or "?"),(e[field] or 0)/top) end
 elseif mode=="fastest" or mode=="dps" or mode=="heals" then
  local chosen={}
  for _,e in ipairs(list) do
   if mode=="fastest" then e.best=bestRun(e);e.value=e.best and e.best.durationMs
   else for _,run in ipairs(e.runs) do if run.status=="completed" then local rate=A.RankingRate(run,e.character,mode);if rate and (not e.value or rate>e.value) then e.value,e.best=rate,run end end end end
   if e.best then chosen[#chosen+1]=e end
  end
  table.sort(chosen,function(a,b)if a.value==b.value then return byName(a,b) end;if mode=="fastest" then return a.value<b.value end;return a.value>b.value end)
  for _,e in ipairs(chosen) do
   local value=mode=="fastest" and kit.duration(e.value) or string.format("%.1f %s",e.value,mode=="dps" and "DPS" or "HPS")
   local fraction=mode=="fastest" and chosen[1].value/e.value or (chosen[1].value>0 and e.value/chosen[1].value or 0)
   local r=row(e,value,fraction,e.best);r.sub=kit.plain(e.best.name).." · "..kit.identityText(e.character);rows[#rows+1]=r
  end
 elseif mode=="history" then
  for _,e in ipairs(list) do for _,run in ipairs(e.runs) do
   local r=row(e,num(run.durationMs) and kit.duration(run.durationMs) or A.L("rankUnrecorded"),1,run)
   r.sub=kit.plain(run.name).." · "..kit.stamp(run.startedAt).." · "..A.L(run.status=="completed" and "rankCompleted" or run.status=="interrupted" and "rankInterrupted" or run.status=="visiting" and "rankVisiting" or "rankManual");rows[#rows+1]=r
  end end
  table.sort(rows,function(a,b)return (num(a.run.startedAt) or 0)>(num(b.run.startedAt) or 0) end)
 else
  local instances,order={},{}
  for _,e in ipairs(list) do if matchesSearch(e,query) then for _,run in ipairs(e.runs) do local ms=A.Number(run.durationMs,1)
   if run.status=="completed" and ms and run.name then
    local d=instances[run.name];if not d then d={name=run.name,players={},count=0};instances[run.name]=d;order[#order+1]=d end
    if not d.players[e.key] then d.players[e.key]=true;d.count=d.count+1 end
    if not d.best or ms<d.best.durationMs then d.best,d.who=run,e end
   end
  end end end
  table.sort(order,byName)
  for _,d in ipairs(order) do rows[#rows+1]={name=d.name,character=d.who.character,own=d.who.own,valueText=kit.duration(d.best.durationMs),fraction=1,plainName=true,run=d.best,entry=d.who,sub=kit.plain(d.who.name).." · "..string.format(A.L("rankPlayers"),d.count)} end
 end
 for i,r in ipairs(rows) do r.rank=i end
 if query~="" and mode~="dungeons" then
  local filtered={};for _,row in ipairs(rows) do if matchesSearch(row.entry,query) then filtered[#filtered+1]=row end end;rows=filtered
 end
 return rows
end
function A.RankingDungeons(filters)
 local names,seen={},{}
 for _,e in ipairs(players(nil,filters)) do for _,r in ipairs(e.runs) do if r.status=="completed" and type(r.name)=="string" and not seen[r.name] then seen[r.name]=true;names[#names+1]=r.name end end end
 table.sort(names);return names
end
function A.RankingCatalog(filters)
 filters=filters or {};local by,order={},{}
 local function add(name,kind,observed)
  if type(name)~="string" or name=="" or filters.kind and kind~=filters.kind then return end
  local item=by[name];if not item then item={name=name,kind=kind,count=0};by[name]=item;order[#order+1]=item end
  if observed then item.count=item.count+1 end
 end
 local kinds=referenceKinds();for name,kind in pairs(kinds) do add(name,kind) end
 local fdj=_G.ForeverDungeonJournal_NS
 if type(fdj)=="table" and type(fdj.DB)=="table" then for name,d in pairs(fdj.DB) do add(name,d.instanceType or (d.isRaid==true and "raid") or kinds[name]) end end
 local seenRuns={}
 for _,e in ipairs(players(nil,filters)) do for _,r in ipairs(e.runs) do
  local key=r.runId or tostring(r)
  if not seenRuns[key] then seenRuns[key]=true;add(r.name,r.instanceType or kinds[r.name],true) end
 end end
 table.sort(order,function(a,b)if (a.count>0)~=(b.count>0) then return a.count>0 end;return byName(a,b)end);return order
end
local function field(entries,label,value) entries[#entries+1]={text=A.L(label)..": "..value} end
local function coverageText(c) return A.L(c and c.coverage=="observed" and "rankObserved" or c and c.coverage=="partial" and "rankPartial" or "rankUnavailable") end
local function combatEntries(kit,run,entries)
 local c=run.combat;entries[#entries+1]={text=A.L("rankCombat"),head=true};entries[#entries+1]={text=coverageText(c)}
 if type(c)~="table" then return end
 field(entries,"rankSource",A.L(c.source=="damage_meter" and "rankMeter" or c.source=="combat_log" and "rankLog" or "rankUnrecorded"))
 entries[#entries+1]={text=A.L("rankScope")}
 field(entries,"rankCovered",num(c.coveredMs) and kit.duration(c.coveredMs) or A.L("rankUnrecorded"));field(entries,"rankActive",num(c.activeMs) and kit.duration(c.activeMs) or A.L("rankUnrecorded"))
 for _,key in ipairs({{"rankDamage","damage"},{"rankHealing","healing"},{"rankOverheal","overhealing"},{"rankTaken","damageTaken"},{"rankAbsorbs","absorbs"},{"rankInterrupts","interrupts"},{"rankDispels","dispels"}}) do field(entries,key[1],countText(c[key[2]])) end
 entries[#entries+1]={text=A.L("rankRoster"),head=true}
 local measured={};for _,p in ipairs(c.players or {}) do measured[#measured+1]=p end
 table.sort(measured,function(a,b)return (num(a.damage) or -1)>(num(b.damage) or -1) end)
 if #measured==0 then entries[#entries+1]={text=A.L("rankUnrecorded")} end
 local observed={}
 for _,p in ipairs(measured) do
  local identity={id=p.guid,name=p.name,classId=p.classId,raceId=p.raceId}
  entries[#entries+1]={text=kit.plain(p.name or "?").." · "..kit.identityText(identity)..(p.role and (" · "..kit.plain(p.role)) or ""),head=true,classId=p.classId,raceId=p.raceId}
  local dps=A.RankingRate(run,identity,"dps",true);local hps=A.RankingRate(run,identity,"heals",true)
  entries[#entries+1]={text="DPS: "..(dps and string.format("%.1f",dps) or A.L("rankUnrecorded")).." · HPS: "..(hps and string.format("%.1f",hps) or A.L("rankUnrecorded"))}
  entries[#entries+1]={text=A.L("rankDamage")..": "..countText(p.damage).." · "..A.L("rankHealing")..": "..countText(p.healing).." · "..A.L("rankDeaths")..": "..countText(p.deaths)}
  if p.guid then observed[p.guid]=true end;if p.name then observed[p.name]=true end
 end
 for _,p in ipairs(run.roster or {}) do if not observed[p.guid] and not observed[p.name] then entries[#entries+1]={text=kit.plain(p.name or "?").." · "..kit.identityText(p).." · "..A.L("rankUnrecorded")} end end
 entries[#entries+1]={text=A.L("rankRateNote")}
end
function A.RankingRunDetail(kit,run,character)
 local entries={};field(entries,"rankDuration",num(run.durationMs) and kit.duration(run.durationMs) or A.L("rankUnrecorded"))
 field(entries,"rankStatus",A.L(run.status=="completed" and "rankCompleted" or run.status=="interrupted" and "rankInterrupted" or run.status=="visiting" and "rankVisiting" or "rankManual"))
 field(entries,"rankFinished",A.L(run.completion=="last_boss" and "rankLastBoss" or run.completion=="full_clear" and "rankFullClear" or "rankUnknown"));field(entries,"rankGroup",countText(run.groupSize));field(entries,"rankDeaths",countText(run.deaths))
 local active=A.ActiveRun and A.ActiveRun()
 if active and run.runId and active.runId==run.runId then
  entries[#entries+1]={text=A.L("rankEndManual"),onClick=function()A.FinishRun("manual","unknown");A.RefreshUI()end}
 end
 entries[#entries+1]={text=A.L("rankBosses"),head=true};if #(run.bosses or {})==0 then entries[#entries+1]={text=A.L("rankNoBosses")} end
 for index,boss in ipairs(run.bosses or {}) do
  local split=num(boss.durationMs);if not split and num(boss.killedAt) and num(run.startedAt) then split=math.max(0,(boss.killedAt-run.startedAt)*1000) end
  local label=split and (kit.duration(split).." · "..A.L(num(boss.durationMs) and "rankBossFight" or "rankBossElapsed")) or A.L("rankUnrecorded")
  entries[#entries+1]={text=index..". "..kit.plain(boss.name or boss.encounterId or "?").." · "..label}
 end
 combatEntries(kit,run,entries)
 return {key="run:"..tostring(run.runId or run.startedAt or run)..":"..tostring(character and character.id),title=kit.plain(run.name or "?"),subtitle=kit.plain(character and character.name or "?").." · "..kit.stamp(run.startedAt).." · "..A.L("rankPersonal"),entries=entries}
end
local function cycle(values,value)
 for i,item in ipairs(values) do if item==value or item==false and value==nil then return values[i%#values+1] or nil end end;return values[1] or nil
end
local function filterName(value,kind)
 if value==nil or value==false then return A.L("rankAll") end
 if value==0 then return A.L("rankUnknown") end
 return kind=="class" and A.ClassName(value) or A.RaceName(value)
end
function A.BuildRankingsPage(page,kit)
 local C=kit.C;A.rankingsPage=page;kit.PageHeader(page,"rankings");page.mode,page.chips,page.filters="runs",{},{}
 for _,mode in ipairs(MODES) do page.chips[mode]=kit.Chip(page,function()page.mode=mode;page.selection=nil;A.RefreshUI()end) end
 local function change(key,choices) page.filters[key]=cycle(choices,page.filters[key]);page.selection=nil;page.dungeon=nil;A.RefreshUI() end
 page.kind=kit.Button(page,"rankAll",150,"ghost",function()change("kind",KINDS)end);page.class=kit.Button(page,"rankClass",150,"ghost",function()change("classId",CLASSES)end);page.race=kit.Button(page,"rankRace",150,"ghost",function()change("raceId",RACES)end)
 page.search=kit.SearchBox(page,240,function(value) if page.filters.query~=value then page.filters.query=value;page.selection=nil;A.RefreshUI() end end)
 page.clearSearch=kit.Button(page,"rankClear",76,"ghost",function()page.search:SetText("");page.filters.query="";page.selection=nil;A.RefreshUI()end)
 page.summary=kit.label(page,10,C.mist);page.summary:SetJustifyH("LEFT");page.summary:SetWordWrap(false)
 page.book=kit.Book(page,150);page.catalog=page.book.index;page.board=page.book.paper
 page.indexMeasure=kit.label(page,13,C.text);page.indexMeasure:Hide()
 page.metaMeasure=kit.label(page,10,C.mist);page.metaMeasure:Hide()
 page.dungeonList=kit.ListView(page.book.index,0,true);page.dungeonList:ClearAllPoints();page.dungeonList:SetPoint("TOPLEFT",6,-6);page.dungeonList:SetPoint("BOTTOMRIGHT",-10,6)
 page.detailFrame=CreateFrame("Frame",nil,page.book.paper);page.detailFrame:SetAllPoints(page.book.paper);kit.fill(page.detailFrame,{0.075,0.074,0.08},1)
 page.document=A.CreateCommunityDocument and A.CreateCommunityDocument(page.detailFrame,kit) or kit.Document(page.book.paper)
 page.boardFrame=CreateFrame("Frame",nil,page.book.paper);page.boardFrame:SetPoint("TOPLEFT",4,-4);page.boardFrame:SetPoint("BOTTOMRIGHT",-4,4)
 kit.fill(page.boardFrame,{0.094,0.09,0.086},1)
 page.boardTitle=kit.label(page.boardFrame,16,{0.96,0.86,0.67});page.boardTitle:SetPoint("TOPLEFT",16,-12);page.boardTitle:SetPoint("TOPRIGHT",-16,-12);page.boardTitle:SetJustifyH("LEFT")
 page.boardSub=kit.label(page.boardFrame,10,{0.70,0.68,0.64});page.boardSub:SetPoint("TOPLEFT",16,-34);page.boardSub:SetPoint("TOPRIGHT",-16,-34);page.boardSub:SetJustifyH("LEFT");page.boardSub:SetWordWrap(false)
 page.columnNames=kit.label(page.boardFrame,10,{0.65,0.62,0.56});page.columnNames:SetPoint("TOPLEFT",16,-54)
 page.columnValue=kit.label(page.boardFrame,10,{0.65,0.62,0.56});page.columnValue:SetPoint("TOPRIGHT",-18,-54);page.columnValue:SetJustifyH("RIGHT")
 local rule=page.boardFrame:CreateTexture(nil,"BORDER");rule:SetPoint("TOPLEFT",16,-69);rule:SetPoint("TOPRIGHT",-16,-69);rule:SetHeight(1);kit.paint(rule,{0.70,0.55,0.30},0.5)
 page.boardList=kit.ListView(page.boardFrame,0,true);page.boardList:ClearAllPoints();page.boardList:SetPoint("TOPLEFT",8,-75);page.boardList:SetPoint("BOTTOMRIGHT",-8,0)
 local function showSelection()
  local selected=page.selection;if not selected then return false end;local spec
  if selected.run then spec=A.RankingRunDetail(kit,selected.run,selected.character)
  else
   local entry;for _,e in ipairs(players(page.dungeon,page.filters)) do if e.key==selected.key then entry=e;break end end
   if not entry then page.selection=nil;return false end
   local entries={{text=kit.identityText(entry.character)},{text=string.format(A.L("rankRuns"),entry.completed),head=true}}
   local runs={};for _,run in ipairs(entry.runs) do runs[#runs+1]=run end
   table.sort(runs,function(a,b)return (num(a.startedAt) or 0)>(num(b.startedAt) or 0) end)
   for _,run in ipairs(runs) do local captured=run
    entries[#entries+1]={text=kit.plain(run.name or "?").." · "..(num(run.durationMs) and kit.duration(run.durationMs) or A.L("rankUnrecorded")).." · "..kit.stamp(run.startedAt),icon=run.instanceType=="raid" and kit.ICON.raid or kit.ICON.run,onClick=function()page.selection={run=captured,character=entry.character};A.RefreshUI()end}
   end
   if entry.web then entries[#entries+1]={text=string.format(A.L("rankWebDetail"),entry.webRank or 0)}
   elseif #runs==0 then entries[#entries+1]={text=A.L("rankNoHistory")} end
   spec={key="player:"..entry.key,title=kit.plain(entry.name),subtitle=A.L("rankPersonal"),entries=entries}
  end
  table.insert(spec.entries,1,{text=A.L("rankBack"),onClick=function()page.selection=nil;A.RefreshUI()end});page.document.Set(spec);return true
 end
 local function layout()
  local width=math.max(240,tonumber(page:GetWidth()) or 640);local x,y=0,-54
  for _,mode in ipairs(MODES) do local chip=page.chips[mode];chip.SetLabel(modeLabel(mode));chip.SetOn(page.mode==mode);local w=chip:GetWidth() or 70
   if x>0 and x+w>width then x=0;y=y-29 end
   chip:ClearAllPoints();chip:SetPoint("TOPLEFT",x,y);x=x+w+5
  end
  y=y-32;local w=(width-10)/3
  for i,b in ipairs({page.kind,page.class,page.race}) do b:ClearAllPoints();b:SetPoint("TOPLEFT",(i-1)*(w+5),y);b:SetWidth(w) end
  page.search:ClearAllPoints();page.search:SetPoint("TOPLEFT",0,y-38);page.search:SetWidth(math.max(90,math.min(270,width-84)))
  page.clearSearch:ClearAllPoints();page.clearSearch:SetPoint("LEFT",page.search,"RIGHT",8,0)
  page.summary:ClearAllPoints();page.summary:SetPoint("TOPLEFT",0,y-72);page.summary:SetPoint("TOPRIGHT",0,y-72)
  page.book:ClearAllPoints();page.book:SetPoint("TOPLEFT",0,y-91);page.book:SetPoint("BOTTOMRIGHT");page.book.Layout()
 end
 page:SetScript("OnSizeChanged",layout)
 function page.Refresh()
  layout();page.kind.text:SetText(kindLabel(page.filters.kind));page.class.text:SetText(A.L("rankClass")..": "..filterName(page.filters.classId,"class"));page.race.text:SetText(A.L("rankRace")..": "..filterName(page.filters.raceId,"race"));page.search.hint:SetText(A.L("rankSearch"));page.clearSearch.text:SetText(A.L("rankClear"));page.columnNames:SetText(A.L("rankColumns"));page.columnValue:SetText(A.L("rankResult"))
  local choices={{title=kindLabel(page.filters.kind),icon=kit.ICON.raid,onClick=function()page.dungeon=nil;page.selection=nil;A.RefreshUI()end}}
  for _,item in ipairs(A.RankingCatalog(page.filters)) do local instance=item.name
   local available=math.max(45,(tonumber(page.book.index:GetWidth()) or 200)-86)
   choices[#choices+1]={title=fitIndex(kit.plain(item.name),available,page.indexMeasure),icon=item.kind=="raid" and kit.ICON.raid or kit.ICON.run,sub=item.count>0 and tostring(item.count).." · "..A.L("rankModeHistory") or A.L("rankWithoutRuns"),tag=page.dungeon==instance and "•" or nil,onClick=function()page.dungeon=instance;page.selection=nil;if page.mode=="dungeons" then page.mode="history" end;A.RefreshUI()end}
  end
  page.dungeonList.SetItems(choices,A.L("rankNoData"));local data=A.RankingRows(kit,page.mode,page.dungeon,page.filters);page.data=data;page.summary:SetText(A.L("rankFilterHint"))
  if showSelection() then page.boardFrame:Hide();page.detailFrame:Show();page.document.scroll:Show();return end
  page.detailFrame:Hide();page.boardFrame:Show();page.document.scroll:Hide()
  local boardRows={}
  for _,row in ipairs(data) do local selected=row
   local classId=row.character and row.character.classId
   local color=classId and A.ClassColor and A.ClassColor(classId)
   local metaWidth=math.max(45,(tonumber(page.boardFrame:GetWidth()) or 350)-155)
   local realm=row.character and A.Text(row.character.realm,100)
   local meta=(realm and realm~="" and realm.." · " or "")..(row.sub or "")
   boardRows[#boardRows+1]={class=classId,race=row.character and row.character.raceId,title=tostring(row.rank)..".  "..kit.plain(row.name),sub=fitIndex(meta,metaWidth-(row.character and row.character.raceId and 26 or 0),page.metaMeasure),right=row.valueText,titleColor=type(color)=="table" and color[1] and {color[1],color[2],color[3]} or nil,
    onClick=function()page.selection=selected.run and {run=selected.run,character=selected.character} or {key=selected.key};A.RefreshUI()end}
  end
  page.boardTitle:SetText(upperText(page.dungeon and kit.plain(page.dungeon) or modeLabel(page.mode)))
  page.boardSub:SetText((page.mode=="dps" or page.mode=="heals") and A.L("rankRateNote") or A.L("rankPersonal"))
  page.boardList.SetItems(boardRows,A.L((page.filters.query or "")~="" and "rankNoMatches" or "rankNoData"))
  local entries={};if page.mode=="dps" or page.mode=="heals" then entries[#entries+1]={text=A.L("rankRateNote")} end
  for _,row in ipairs(data) do local selected=row
   entries[#entries+1]={text=tostring(row.rank)..". "..kit.plain(row.name).." · "..row.valueText,head=true,classId=row.character and row.character.classId,raceId=row.character and row.character.raceId,onClick=function()page.selection=selected.run and {run=selected.run,character=selected.character} or {key=selected.key};A.RefreshUI()end}
   entries[#entries+1]={text=row.sub or ""}
  end
  if #data==0 then entries[#entries+1]={text=A.L("rankNoData")} end
  page.document.Set({key="board:"..page.mode..":"..tostring(page.dungeon),title=page.dungeon and kit.plain(page.dungeon) or modeLabel(page.mode),subtitle=A.L("sub_rankings"),entries=entries})
 end
end
