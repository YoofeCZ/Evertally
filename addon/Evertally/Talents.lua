local _, A = ...
-- An offline planner using the current character's real talent trees. Never trains talents.
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local words = {
 en={talents="Talents",sub_talents="Plan your current class here. Left click adds a rank; right click removes it.",talentPlan="PLAN",talentActual="CURRENT",talentLevel="Level %d",talentBudget="%d / %d points · %d remaining",talentLoad="Load current",talentClear="Reset plan",talentSave="Save build",talentSaved="Saved builds",talentSavedEmpty="No saved build",talentNoApi="This client does not expose this character's talent trees.",talentNoTrees="Your class has no talent trees yet.",talentFull="That talent is at maximum rank.",talentBudgetError="No points remain at this planned level.",talentTierError="Spend %d points in earlier tiers of this tree first.",talentPrereqError="Maximise the prerequisite talent first.",talentRemoveError="Another talent depends on this rank or its tier points.",talentSavedNote="Build saved locally. Planning does not train talents in the game.",talentPlannerHint="Current class · client talent data · changes only your plan",talentPlannedRank="Planned rank: %d / %d",talentCurrentRank="Current rank: %d / %d",talentDelete="Delete build",talentLevelBlocked="Remove excess points before lowering the level.",talentNameDefault="My build"},
 cs={talents="Talenty",sub_talents="Plánuj talenty své třídy přímo tady. Levé kliknutí přidá bod, pravé ho odebere.",talentPlan="PLÁN",talentActual="VE HŘE",talentLevel="Úroveň %d",talentBudget="%d / %d bodů · zbývá %d",talentLoad="Načíst moje",talentClear="Vymazat plán",talentSave="Uložit build",talentSaved="Uložené buildy",talentSavedEmpty="Žádný uložený build",talentNoApi="Klient neposkytuje talentové stromy této postavy.",talentNoTrees="Tvoje třída zatím nemá talentové stromy.",talentFull="Talent už má nejvyšší úroveň.",talentBudgetError="Pro zvolenou úroveň už nezbývají body.",talentTierError="Nejdřív vlož %d bodů do předchozích řad tohoto stromu.",talentPrereqError="Nejdřív dokonči předchozí talent, na kterém tento závisí.",talentRemoveError="Na tomto bodu závisí další talent nebo odemčení řady.",talentSavedNote="Build je uložený místně. Plánování nerozděluje skutečné body ve hře.",talentPlannerHint="Aktuální třída · data z klienta · měníš pouze svůj plán",talentPlannedRank="Plánovaná úroveň: %d / %d",talentCurrentRank="Ve hře: %d / %d",talentDelete="Smazat build",talentLevelBlocked="Před snížením úrovně nejdřív odeber přebytečné body.",talentNameDefault="Můj build"},
}
for lang,entries in pairs(words) do for key,value in pairs(entries) do A.locale[lang][key]=value end end
A.locale.en.talentLoading="Loading your character's talent data…"
A.locale.cs.talentLoading="Načítám talentová data postavy…"
local function n(v,d) return A.Number(v,0,10000) or d end
local function classKey() local _,file=A.Call(UnitClass,"player");return A.Text(file,40) or "unknown" end
local function classicTrees()
 if type(GetNumTalentTabs)~="function" or type(GetTalentTabInfo)~="function" or type(GetNumTalents)~="function" or type(GetTalentInfo)~="function" then return nil end
 local trees={}
 for tab=1,math.min(10,n(A.Call(GetNumTalentTabs),0)) do
  local name,icon,spent,background=A.Call(GetTalentTabInfo,tab)
  if type(name)=="string" then
   local tree={tab=tab,name=name,icon=icon or QUESTION,spent=n(spent,0),background=A.Text(background,80),talents={}}
   for index=1,math.min(80,n(A.Call(GetNumTalents,tab),0)) do
    local title,image,tier,column,rank,max=A.Call(GetTalentInfo,tab,index)
    if type(title)=="string" then
     local talent={index=index,name=title,icon=image or QUESTION,tier=n(tier,1),column=n(column,1),rank=n(rank,0),max=n(max,1),prereqs={}}
     if type(GetTalentPrereqs)=="function" then local p={A.Call(GetTalentPrereqs,tab,index)};for i=1,7,3 do if type(p[i])=="number" and type(p[i+1])=="number" then talent.prereqs[#talent.prereqs+1]={tier=p[i],column=p[i+1]} end end end
     tree.talents[#tree.talents+1]=talent
    end
   end
   trees[#trees+1]=tree
  end
 end
 for _,tree in ipairs(trees) do for _,talent in ipairs(tree.talents) do for _,pre in ipairs(talent.prereqs) do for _,other in ipairs(tree.talents) do if other.tier==pre.tier and other.column==pre.column then pre.index,pre.max=other.index,other.max;break end end end end end
 return trees
end
local function numberField(value,key) return A.Number(A.Field(value,key),0) end
local function traitConfig()
 local id=C_ClassTalents and A.Number(A.Call(C_ClassTalents.GetActiveConfigID),1)
 if not id and C_SpecializationInfo then
  local group=A.Number(A.Call(C_SpecializationInfo.GetActiveSpecGroup),1) or 1
  id=A.Number(A.Call(C_SpecializationInfo.GetCombatConfigIDForSpecGroup,group),1)
 end
 return id
end
-- Forever uses C_Traits, with three node groups inside one trait tree. Read only committed client data.
local requestedSpells={}
local function traitTrees()
 if not(C_Traits and type(C_Traits.GetConfigInfo)=="function" and type(C_Traits.GetNodeInfo)=="function") then return nil end
 local config=traitConfig();if not config then return {} end
 local info=A.Call(C_Traits.GetConfigInfo,config);local ids=A.Field(info,"treeIDs")
 if type(ids)~="table" then return {} end
 local groups,nodes,byID,incoming={},{},{},{}
 for treeOrder,treeID in ipairs(ids) do
  treeID=A.Number(treeID,1)
  if treeID then
   local names={};local displays=A.Call(C_Traits.GetGroupDisplayInfoByTreeID,treeID)
   for _,display in ipairs(type(displays)=="table" and displays or {}) do
    local gid=numberField(display,"groupID");if gid then names[gid]=A.Text(A.Field(display,"displayName"),100) or "" end
   end
   local list=A.Call(C_Traits.GetTreeNodes,treeID)
   local loose={}
   for _,nodeID in ipairs(type(list)=="table" and list or {}) do
    nodeID=A.Number(nodeID,1);local node=nodeID and A.Call(C_Traits.GetNodeInfo,config,nodeID)
    local x,y=numberField(node,"posX") or 0,numberField(node,"posY") or 0
    local entries=A.Field(node,"entryIDs")
    if node and A.Field(node,"isVisible")~=false and x<=20000 and y<=10000 and type(entries)=="table" and #entries>0 then
     local chosen=numberField(A.Field(node,"activeEntry"),"entryID") or A.Number(entries[1],1)
     local entry=chosen and A.Call(C_Traits.GetEntryInfo,config,chosen)
     local defID=numberField(entry,"definitionID");local def=defID and A.Call(C_Traits.GetDefinitionInfo,defID)
     local spell=numberField(def,"spellID") or numberField(def,"overriddenSpellID")
     local title=A.Text(A.Field(def,"overrideName"),150)
     if not title or title=="" then title=C_Spell and A.Text(A.Call(C_Spell.GetSpellName,spell),150) end
     if (not title or title=="") and spell and not requestedSpells[spell] and C_Spell and C_Spell.RequestLoadSpellData then
      requestedSpells[spell]=true;A.Call(C_Spell.RequestLoadSpellData,spell)
     end
     if title then
      local icon=A.Number(A.Field(def,"overrideIcon"),1) or (C_Spell and A.Call(C_Spell.GetSpellTexture,spell)) or QUESTION
      local talent={index=nodeID,nodeID=nodeID,entryID=chosen,spellID=spell,name=title,icon=icon,rank=numberField(node,"activeRank") or numberField(node,"currentRank") or numberField(node,"ranksPurchased") or 0,
       max=numberField(node,"maxRanks") or 1,prereqs={},x=x,y=y,treeID=treeID,treeOrder=treeOrder,modern=true}
      nodes[#nodes+1]=talent;byID[nodeID]=talent
      local gid;local membership=A.Field(node,"groupIDs")
      for _,candidate in ipairs(type(membership)=="table" and membership or {}) do candidate=A.Number(candidate,0);if candidate and names[candidate] then gid=candidate;break end end
      if gid then talent.groupKey="trait:"..treeID..":"..gid;talent.groupName=names[gid]
      elseif #ids>1 then talent.groupKey="trait:"..treeID
      else loose[#loose+1]=talent end
      for _,edge in ipairs(type(A.Field(node,"visibleEdges"))=="table" and A.Field(node,"visibleEdges") or {}) do
       local target,kind=numberField(edge,"targetNode"),numberField(edge,"type")
       if target and kind~=0 and kind~=4 then incoming[target]=incoming[target] or {};incoming[target][#incoming[target]+1]={nodeID=nodeID,any=kind==2} end
      end
     end
    end
   end
   if #loose>0 then
    -- Older trait builds omit group headers. Their three trees are separated by the two largest X gaps.
    table.sort(loose,function(a,b)if a.x~=b.x then return a.x<b.x end;return a.nodeID<b.nodeID end)
    local gaps={};for i=2,#loose do if loose[i].x>loose[i-1].x then gaps[#gaps+1]={at=i,gap=loose[i].x-loose[i-1].x} end end
    table.sort(gaps,function(a,b)if a.gap~=b.gap then return a.gap>b.gap end;return a.at<b.at end)
    local cuts={};for i=1,math.min(2,#gaps)do cuts[gaps[i].at]=true end
    local section=1;for i,talent in ipairs(loose)do if cuts[i]then section=section+1 end;talent.groupKey="trait:"..treeID..":section"..section end
   end
  end
 end
 for _,talent in ipairs(nodes)do
  local key=talent.groupKey;local group=groups[key]
  if not group then group={tab=key,name=talent.groupName,icon=talent.icon,talents={},spent=0,sumX=0,treeOrder=talent.treeOrder,modern=true,configID=config};groups[key]=group end
  group.talents[#group.talents+1]=talent;group.spent=group.spent+talent.rank;group.sumX=group.sumX+talent.x
 end
 local trees={};for _,group in pairs(groups)do trees[#trees+1]=group end
 table.sort(trees,function(a,b)if a.treeOrder~=b.treeOrder then return a.treeOrder<b.treeOrder end;local ax,bx=a.sumX/#a.talents,b.sumX/#b.talents;if ax~=bx then return ax<bx end;return a.tab<b.tab end)
 for order,group in ipairs(trees)do
  group.name=group.name and group.name~="" and group.name or (A.L("talents").." "..order)
  local ys,xs={},{};for _,talent in ipairs(group.talents)do ys[#ys+1]=talent.y;xs[#xs+1]=talent.x;talent.tab=group.tab end
  table.sort(ys);table.sort(xs)
  local step;for i=2,#ys do local gap=ys[i]-ys[i-1];if gap>1 and(not step or gap<step)then step=gap end end
  local columns={};for _,x in ipairs(xs)do if #columns==0 or x-columns[#columns]>1 then columns[#columns+1]=x end end
  for _,talent in ipairs(group.talents)do
   talent.tier=step and(1+math.floor((talent.y-ys[1])/step+.5))or 1
   for column,x in ipairs(columns)do if math.abs(talent.x-x)<=1 then talent.column=column;break end end
  end
  table.sort(group.talents,function(a,b)if a.tier~=b.tier then return a.tier<b.tier end;if a.column~=b.column then return a.column<b.column end;return a.index<b.index end)
 end
 for _,talent in ipairs(nodes)do for _,edge in ipairs(incoming[talent.nodeID] or {})do local parent=byID[edge.nodeID];if parent then talent.prereqs[#talent.prereqs+1]={index=parent.index,tab=parent.tab,tier=parent.tier,column=parent.column,max=parent.max,any=edge.any} end end end
 return trees
end
function A.TalentTrees()
 local trees=traitTrees();if trees~=nil then return trees end
 return classicTrees()
end
local function rankAt(plan,tab,index) return plan.ranks[tab] and plan.ranks[tab][index] or 0 end
function A.TalentPlanPoints(plan,tab)
 local total=0;for tree,ranks in pairs(plan.ranks) do if not tab or tree==tab then for _,rank in pairs(ranks) do total=total+rank end end end;return total
end
function A.TalentPlanBudget(plan) return math.max(0,math.min(60,plan.level or 1)-9) end
local function earlier(plan,tree,tier) local total=0;for _,talent in ipairs(tree.talents) do if talent.tier<tier then total=total+rankAt(plan,tree.tab,talent.index) end end;return total end
local function prerequisitesMet(plan,tree,talent)
 local any,met=false,false
 for _,pre in ipairs(talent.prereqs)do
  local ready=pre.index and rankAt(plan,pre.tab or tree.tab,pre.index)>=pre.max
  if pre.any then any=true;met=met or ready elseif not ready then return false end
 end
 return not any or met
end
function A.NewTalentPlan(trees,level,empty)
 local plan={class=classKey(),level=math.max(1,math.min(60,math.floor(level or n(A.Call(UnitLevel,"player"),60)))),ranks={}}
 for _,tree in ipairs(trees or {}) do plan.ranks[tree.tab]={};for _,talent in ipairs(tree.talents) do plan.ranks[tree.tab][talent.index]=empty and 0 or talent.rank end end
 return plan
end
local function valid(plan,trees)
 for _,tree in ipairs(trees or {}) do for _,talent in ipairs(tree.talents) do
  local rank=rankAt(plan,tree.tab,talent.index)
  if rank<0 or rank>talent.max then return false end
  if rank>0 then
   if earlier(plan,tree,talent.tier)<(talent.tier-1)*5 then return false end
   if not prerequisitesMet(plan,tree,talent)then return false end
  end
 end end;return true
end
function A.ChangeTalentPlan(plan,trees,tab,index,delta)
 local tree,talent
 for _,v in ipairs(trees or {}) do if v.tab==tab then tree=v;for _,candidate in ipairs(v.talents) do if candidate.index==index then talent=candidate;break end end;break end end
 if not talent or delta~=1 and delta~=-1 then return false,"unknown" end
 local old=rankAt(plan,tab,index)
 if delta==1 then
  if old>=talent.max then return false,"talentFull" end
  if A.TalentPlanPoints(plan)>=A.TalentPlanBudget(plan) then return false,"talentBudgetError" end
  if earlier(plan,tree,talent.tier)<(talent.tier-1)*5 then return false,"talentTierError",(talent.tier-1)*5 end
  if not prerequisitesMet(plan,tree,talent)then return false,"talentPrereqError" end
 elseif old<=0 then return false,"unknown" end
 plan.ranks[tab]=plan.ranks[tab] or {};plan.ranks[tab][index]=old+delta
 if delta<0 and not valid(plan,trees) then plan.ranks[tab][index]=old;return false,"talentRemoveError" end
 return true
end
function A.SavedTalentBuilds()
 if not A.db then return {} end
 if type(A.db.talentBuilds)~="table" then A.db.talentBuilds={} end
 local key=classKey();if type(A.db.talentBuilds[key])~="table" then A.db.talentBuilds[key]={} end
 return A.db.talentBuilds[key]
end
function A.SaveTalentBuild(plan,name)
 local list=A.SavedTalentBuilds();local saved=A.Copy(plan)
 saved.name=(A.Text(name,48) or A.L("talentNameDefault")):gsub("|","");if saved.name=="" then saved.name=A.L("talentNameDefault") end
 for i,build in ipairs(list) do if build.name==saved.name then list[i]=saved;return i end end
 if #list>=8 then table.remove(list,1) end;list[#list+1]=saved;return #list
end
function A.LoadTalentBuild(saved,trees)
 if type(saved)~="table" or saved.class~=classKey() then return nil end
 local plan=A.NewTalentPlan(trees,n(saved.level,60),true)
 for _,tree in ipairs(trees or {}) do for _,talent in ipairs(tree.talents) do
  local r=type(saved.ranks)=="table" and type(saved.ranks[tree.tab])=="table" and saved.ranks[tree.tab][talent.index]
  if type(r)=="number" and r==math.floor(r) and r>=0 and r<=talent.max then plan.ranks[tree.tab][talent.index]=r end
 end end
 if A.TalentPlanPoints(plan)>A.TalentPlanBudget(plan) or not valid(plan,trees) then return nil end;return plan
end
local function draw(page,kit)
 local t,C=page.talents,kit.C
 t.saved.text:SetText((A.SavedTalentBuilds()[t.savedIndex or 1] or {}).name or A.L("talentSavedEmpty"))
 for _,v in ipairs(t.columns) do v:Hide() end;for _,v in ipairs(t.buttons) do v:Hide() end;for _,v in ipairs(t.lines) do v:Hide() end
 local trees=A.TalentTrees();if not trees or #trees==0 then
  t.note:SetText(A.L(trees and C_Traits and "talentLoading" or trees and "talentNoTrees" or "talentNoApi"));t.summary:SetText("")
  t.level:SetText(string.format(A.L("talentLevel"),A.Number(A.Call(UnitLevel,"player"),1) or 1));return
 end
 t.trees=trees
 if not t.plan or t.plan.class~=classKey() then t.plan=A.NewTalentPlan(trees) end
 local plan=t.plan;local total,budget=A.TalentPlanPoints(plan),A.TalentPlanBudget(plan)
 t.summary:SetText(string.format(A.L("talentBudget"),total,budget,math.max(0,budget-total)));t.level:SetText(string.format(A.L("talentLevel"),plan.level));t.note:SetText(t.notice or "")
 local width=math.max(430,(page:GetWidth() or 640)-24);local cw=math.floor((width-(#trees-1)*10)/#trees)
 local size=math.max(24,math.min(38,math.floor((cw-42)/4)));local sx,sy=(cw-38)/4,size+20
 local maxTier=1;for _,tree in ipairs(trees) do for _,talent in ipairs(tree.talents) do maxTier=math.max(maxTier,talent.tier) end end
 local height=math.max(330,78+maxTier*sy);t.content:SetSize(width,height)
 local used,lines=0,0
 for i,tree in ipairs(trees) do
  local column=t.columns[i]
  if not column then
   column=CreateFrame("Frame",nil,t.content);A.NativePanel(column,C)
   column.icon=column:CreateTexture(nil,"ARTWORK");column.icon:SetSize(28,28);column.icon:SetPoint("TOPLEFT",10,-10)
   column.name=kit.label(column,13,C.gold);column.name:SetPoint("TOPLEFT",column.icon,"TOPRIGHT",6,-1);column.name:SetPoint("RIGHT",-6,0);column.name:SetWordWrap(false)
   column.points=kit.label(column,10,C.text);column.points:SetPoint("TOPLEFT",column.icon,"TOPRIGHT",6,-17)
   column.back=column:CreateTexture(nil,"BACKGROUND");column.back:SetPoint("TOPLEFT",3,-48);column.back:SetPoint("BOTTOMRIGHT",-3,3);column.back:SetAlpha(.45)
   t.columns[i]=column
  end
  column:ClearAllPoints();column:SetPoint("TOPLEFT",(i-1)*(cw+10),0);column:SetSize(cw,height);column:Show();column.icon:SetTexture(tree.icon);column.name:SetText(tree.name)
  column.points:SetText(A.TalentPlanPoints(plan,tree.tab).." "..A.L("talentPlan").." · "..tree.spent.." "..A.L("talentActual"))
  if tree.background then column.back:SetTexture("Interface\\TalentFrame\\"..tree.background.."-TopLeft") else column.back:SetTexture(nil) end
  for _,talent in ipairs(tree.talents) do
   used=used+1;local b=t.buttons[used]
   if not b then
    b=CreateFrame("Button",nil,t.content);b:RegisterForClicks("LeftButtonUp","RightButtonUp")
    b.border=b:CreateTexture(nil,"BACKGROUND");b.border:SetPoint("TOPLEFT",-2,2);b.border:SetPoint("BOTTOMRIGHT",2,-2)
    b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetAllPoints(b);b.icon:SetTexCoord(.08,.92,.08,.92)
    b.rank=kit.label(b,10,C.text);b.rank:SetPoint("BOTTOMRIGHT",3,-4)
    b:SetScript("OnClick",function(self,mouse)
     local ok,reason,value=A.ChangeTalentPlan(t.plan,t.trees,self.tab,self.index,mouse=="RightButton" and -1 or 1)
     t.notice=not ok and (value and string.format(A.L(reason),value) or A.L(reason)) or "";draw(page,kit)
    end)
    b:SetScript("OnEnter",function(self)
     if GameTooltip then pcall(function()
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
      if self.modern and self.spellID and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spellID)
      elseif not self.modern and GameTooltip.SetTalent then GameTooltip:SetTalent(self.tab,self.index)
      else GameTooltip:SetText(self.name or "?") end
      GameTooltip:AddLine(string.format(A.L("talentPlannedRank"),self.planned,self.max),1,.82,.2);GameTooltip:AddLine(string.format(A.L("talentCurrentRank"),self.actual,self.max),.7,.7,.7);GameTooltip:Show()
     end) end
    end);b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end);t.buttons[used]=b
   end
   local rank=rankAt(plan,tree.tab,talent.index)
   b.tab,b.index,b.name,b.planned,b.actual,b.max,b.modern,b.spellID=tree.tab,talent.index,talent.name,rank,talent.rank,talent.max,talent.modern,talent.spellID
   b:ClearAllPoints();b:SetSize(size,size);b:SetPoint("TOPLEFT",column,"TOPLEFT",20+(talent.column-1)*sx,-64-(talent.tier-1)*sy)
   b.icon:SetTexture(talent.icon);b.icon:SetVertexColor(rank>0 and 1 or .4,rank>0 and 1 or .4,rank>0 and 1 or .4)
   kit.paint(b.border,rank>=talent.max and C.gold or rank>0 and C.green or C.off);b.rank:SetText(rank.."/"..talent.max);b:Show()
   for _,pre in ipairs(talent.prereqs) do if pre.index and (not pre.tab or pre.tab==tree.tab) then
    local x1=20+(pre.column-1)*sx+size/2;local x2=20+(talent.column-1)*sx+size/2
    local y1=64+(pre.tier-1)*sy+size+3;local y2=64+(talent.tier-1)*sy-4;local mid=(y1+y2)/2
    local color=rankAt(plan,pre.tab or tree.tab,pre.index)>=pre.max and C.gold or C.faint
    local function seg(x,y,w,h)
     lines=lines+1;local line=t.lines[lines];if not line then line=t.content:CreateTexture(nil,"BORDER");t.lines[lines]=line end
     line:ClearAllPoints();line:SetPoint("TOPLEFT",column,"TOPLEFT",x,-y);line:SetSize(math.max(2,w),math.max(2,h));kit.paint(line,color,.8);line:Show()
    end
    seg(x1,y1,2,math.max(2,mid-y1));seg(math.min(x1,x2),mid,math.max(2,math.abs(x2-x1)),2);seg(x2,mid,2,math.max(2,y2-mid));seg(x2-3,y2-3,8,3)
   end end
  end
 end
 t.saved.text:SetText((A.SavedTalentBuilds()[t.savedIndex or 1] or {}).name or A.L("talentSavedEmpty"))
end
function A.BuildTalentsPage(page,kit)
 local C=kit.C;kit.PageHeader(page,"talents");local t={columns={},buttons={},lines={}};page.talents=t;A.talentPage=page
 t.summary=kit.label(page,12,C.gold);t.summary:SetPoint("TOPLEFT",0,-55)
 t.level=kit.label(page,11,C.text);t.level:SetPoint("TOPRIGHT",-36,-55)
 local function levelBy(delta)
  if not t.plan then return end;local level=math.max(10,math.min(60,t.plan.level+delta))
  if A.TalentPlanPoints(t.plan)>math.max(0,level-9) then t.notice=A.L("talentLevelBlocked") else t.plan.level=level;t.notice="" end;draw(page,kit)
 end
 local minus=kit.Button(page,nil,25,"ghost",function() levelBy(-1) end);minus.text:SetText("-");minus:SetPoint("TOPRIGHT",t.level,"TOPLEFT",-6,6)
 local plus=kit.Button(page,nil,25,"ghost",function() levelBy(1) end);plus.text:SetText("+");plus:SetPoint("TOPRIGHT",0,-49)
 t.load=kit.Button(page,"talentLoad",110,"ghost",function() t.plan=A.NewTalentPlan(A.TalentTrees());t.notice="";draw(page,kit) end);t.load:SetPoint("TOPLEFT",0,-79)
 t.clear=kit.Button(page,"talentClear",110,"ghost",function() t.plan=A.NewTalentPlan(A.TalentTrees(),t.plan and t.plan.level or 60,true);t.notice="";draw(page,kit) end);t.clear:SetPoint("LEFT",t.load,"RIGHT",6,0)
 t.name=CreateFrame("EditBox",nil,page,"InputBoxTemplate");t.name:SetAutoFocus(false);t.name:SetMaxLetters(48);t.name:SetFont(kit.fontPath(),11,"");t.name:SetSize(126,25);t.name:SetPoint("LEFT",t.clear,"RIGHT",12,0);t.name:SetText(A.L("talentNameDefault"));t.name:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
 t.save=kit.Button(page,"talentSave",104,"primary",function() if t.plan then t.savedIndex=A.SaveTalentBuild(t.plan,t.name:GetText());t.notice=A.L("talentSavedNote");draw(page,kit) end end);t.save:SetPoint("LEFT",t.name,"RIGHT",8,0)
 t.scroll=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate");t.scroll:SetPoint("TOPLEFT",0,-148);t.scroll:SetPoint("BOTTOMRIGHT",-24,70)
 t.content=CreateFrame("Frame",nil,t.scroll);t.content:SetSize(600,420);t.scroll:SetScrollChild(t.content)
 t.note=kit.label(page,10,C.peach);t.note:SetPoint("TOPLEFT",0,-115);t.note:SetPoint("TOPRIGHT",-5,-115);t.note:SetHeight(28)
 t.savedLabel=kit.label(page,10,C.mist);t.savedLabel:SetPoint("BOTTOMLEFT",0,48);t.savedLabel:SetText(A.L("talentSaved"))
 t.saved=kit.Button(page,nil,200,"ghost",function()
  local list=A.SavedTalentBuilds();if #list==0 then return end;t.savedIndex=(t.savedIndex or 0)%#list+1
  local plan=A.LoadTalentBuild(list[t.savedIndex],A.TalentTrees());if plan then t.plan=plan;t.name:SetText(list[t.savedIndex].name);t.notice="";draw(page,kit) end
 end);t.saved:SetPoint("BOTTOMLEFT",0,13)
 t.delete=kit.Button(page,"talentDelete",130,"ghost",function() local list=A.SavedTalentBuilds();if #list>0 then table.remove(list,math.min(t.savedIndex or 1,#list));t.savedIndex=1;draw(page,kit) end end);t.delete:SetPoint("LEFT",t.saved,"RIGHT",8,0)
 t.hint=kit.label(page,10,C.mist);t.hint:SetPoint("BOTTOMLEFT",0,-3);t.hint:SetPoint("BOTTOMRIGHT",0,-3);t.hint:SetWordWrap(false);t.hint:SetText(A.L("talentPlannerHint"))
 page:SetScript("OnSizeChanged",function() if page:IsShown() then draw(page,kit) end end);function page.Refresh() draw(page,kit) end
end

for _,event in ipairs({"PLAYER_LOGIN","TRAIT_CONFIG_UPDATED","TRAIT_CONFIG_LIST_UPDATED","TRAIT_NODE_CHANGED","TRAIT_TREE_CHANGED","SPELL_DATA_LOAD_RESULT","ACTIVE_PLAYER_SPECIALIZATION_CHANGED"})do
 A.On(event,function()
  if A.talentPage and A.talentPage:IsShown() and A.RefreshUI then A.RefreshUI() end
 end)
end

