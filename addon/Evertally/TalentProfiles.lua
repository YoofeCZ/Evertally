local _, A = ...
-- Versioned data-only profiles. JSON parsing is bounded; no Lua is evaluated.
local MAX_BYTES, PREFIX = 16384, "ETB1|"
local function classKey() local _,key=A.Call(UnitClass,"player");return A.Text(key,40) or "unknown" end
local function integer(value,low,high)
 value=A.Number(value,low,high);return value and value==math.floor(value) and value or nil
end
local function checksum(text)
 local a,b=1,0
 for i=1,#text do a=(a+text:byte(i))%65521;b=(b+a)%65521 end
 return string.format("%08x",b*65536+a)
end
local function label(value)
 local text=(A.Text(value,48) or A.L("talentNameDefault")):gsub("|",""):gsub("[%z\1-\31]","")
 return text~="" and text or A.L("talentNameDefault")
end
function A.TalentProfileSchema(trees)
 local parts={}
 for _,tree in ipairs(trees or {}) do for _,talent in ipairs(tree.talents or {}) do
  parts[#parts+1]=table.concat({tostring(tree.tab),tostring(talent.index),tostring(talent.max),tostring(talent.entryID or 0),tostring(talent.spellID or 0)},":")
 end end
 table.sort(parts)
 return checksum(table.concat(parts,";"))
end
function A.ValidateTalentProfile(plan,trees)
 if type(plan)~="table" or plan.class~=classKey() then return false,"talentProfileClass" end
 if not trees or #trees==0 then return false,"talentNoApi" end
 if not integer(plan.level,1,60) or type(plan.ranks)~="table" then return false,"talentProfileInvalid" end
 local known={}
 for _,tree in ipairs(trees) do
  known[tree.tab]={}
  for _,talent in ipairs(tree.talents or {}) do known[tree.tab][talent.index]=talent.max end
 end
 for tab,ranks in pairs(plan.ranks) do
  if type(ranks)~="table" or not known[tab] then return false,"talentProfileSchema" end
  for id,rank in pairs(ranks) do
   if not known[tab][id] then return false,"talentProfileSchema" end
   if not integer(rank,0,known[tab][id]) then return false,"talentProfileInvalid" end
  end
 end
 if A.TalentPlanPoints(plan)>A.TalentPlanBudget(plan) then return false,"talentBudgetError" end
 if not A.LoadTalentBuild(plan,trees) then return false,"talentProfilePrerequisite" end
 return true
end
function A.ExportTalentProfile(plan,trees,name)
 local valid,why=A.ValidateTalentProfile(plan,trees)
 if not valid then return nil,why end
 local entries={}
 for _,tree in ipairs(trees) do for _,talent in ipairs(tree.talents) do
  local rank=plan.ranks[tree.tab] and plan.ranks[tree.tab][talent.index] or 0
  if rank>0 then entries[#entries+1]={tab=tree.tab,node=talent.index,rank=rank} end
 end end
 table.sort(entries,function(a,b)if tostring(a.tab)~=tostring(b.tab) then return tostring(a.tab)<tostring(b.tab) end;return a.node<b.node end)
 local payload=A.Encode({version=1,class=plan.class,level=plan.level,name=label(name),schema=A.TalentProfileSchema(trees),talents=entries})
 if not payload or #payload>MAX_BYTES-20 then return nil,"talentProfileInvalid" end
 return PREFIX..checksum(payload).."|"..payload
end
function A.ImportTalentProfile(text,trees)
 text=A.Plain(text)
 if type(text)~="string" or #text>MAX_BYTES then return nil,"talentProfileInvalid" end
 text=text:gsub("^%s+",""):gsub("%s+$","")
 local digest,payload=text:match("^ETB1|(%x%x%x%x%x%x%x%x)|(.+)$")
 if not digest or checksum(payload)~=digest:lower() then return nil,"talentProfileChecksum" end
 local data=A.Decode(payload,MAX_BYTES)
 if type(data)~="table" or data.version~=1 or type(data.talents)~="table" or #data.talents>300 then return nil,"talentProfileInvalid" end
 if data.class~=classKey() then return nil,"talentProfileClass" end
 if not trees or #trees==0 then return nil,"talentNoApi" end
 if data.schema~=A.TalentProfileSchema(trees) then return nil,"talentProfileSchema" end
 local plan=A.NewTalentPlan(trees,data.level,true)
 if not integer(data.level,1,60) then return nil,"talentProfileInvalid" end
 local known,seen,count={},{},0
 for _,tree in ipairs(trees) do known[tree.tab]={};for _,talent in ipairs(tree.talents) do known[tree.tab][talent.index]=talent.max end end
 for i,entry in pairs(data.talents) do
  count=count+1
  if not integer(i,1,#data.talents) or type(entry)~="table" then return nil,"talentProfileInvalid" end
  local tab,node,rank=entry.tab,entry.node,entry.rank
  if not known[tab] or not known[tab][node] then return nil,"talentProfileSchema" end
  local key=tostring(tab)..":"..tostring(node)
  if seen[key] or not integer(rank,1,known[tab][node]) then return nil,"talentProfileInvalid" end
  seen[key]=true;plan.ranks[tab][node]=rank
 end
 if count~=#data.talents then return nil,"talentProfileInvalid" end
 local valid,why=A.ValidateTalentProfile(plan,trees)
 if not valid then return nil,why end
 return plan,nil,label(data.name)
end
function A.UniqueTalentProfileName(name)
 name=label(name)
 local used={};for _,saved in ipairs(A.SavedTalentBuilds()) do used[saved.name]=true end
 if not used[name] then return name end
 for i=2,999 do local candidate=name:sub(1,41).." ("..i..")";if not used[candidate] then return candidate end end
 return name:sub(1,34).." "..tostring(A.Now())
end
function A.RecommendedForClass()
 local out={}
 for _,build in ipairs(A.RecommendedBuilds or {}) do if build.class==classKey() then out[#out+1]=build end end
 return out
end
function A.LoadRecommendedTalentBuild(build,trees)
 if type(build)~="table" or build.class~=classKey() then return nil,"talentProfileClass" end
 if not trees or #trees==0 then return nil,"talentNoApi" end
 local plan=A.NewTalentPlan(trees,build.level or 60,true)
 local picked={}
 for _,choice in ipairs(build.talents or build.ranks or {}) do
  local wanted=type(choice.name)=="string" and choice.name:lower()
  local localized=choice.spellID and C_Spell and A.Text(A.Call(C_Spell.GetSpellName,choice.spellID),150)
  localized=localized and localized:lower()
  local found,tab
  for _,tree in ipairs(trees) do for _,talent in ipairs(tree.talents) do
   if (choice.spellID and talent.spellID==choice.spellID) or (wanted and talent.name:lower()==wanted) or (localized and talent.name:lower()==localized) then
    if found then return nil,"talentProfileSchema",choice.name end
    found,tab=talent,tree.tab
   end
  end end
  if not found then return nil,"talentTemplateMismatch",choice.name or tostring(choice.spellID or "?") end
  local key=tostring(tab)..":"..found.index
  if picked[key] or not integer(choice.rank,1,found.max) then return nil,"talentProfileInvalid",choice.name end
  picked[key]=true;plan.ranks[tab][found.index]=choice.rank
 end
 if not next(picked) then return nil,"talentTemplateInformational" end
 local valid,why=A.ValidateTalentProfile(plan,trees)
 if not valid then return nil,why end
 return plan
end
