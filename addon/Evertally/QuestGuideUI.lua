local _, A = ...
local Q=A.QuestGuide
local translations={
 en={questguide="Quest guide",sub_questguide="Your computed route through quests. Class and dungeon steps, progress and navigation.",qgComputed="Computed from reference data; not a manually verified 1–60 route.",qgClasses="Class quests",qgDungeons="Dungeon quests",qgAuto="Auto navigation",qgTracker="Tracker",qgRecommended="Recommended",qgProgress="%d / %d handed in · %d skipped",qgAccept="Pick up",qgObjectives="Do the objectives",qgTurnin="Hand in",qgNext="Next step",qgBack="Back",qgSkip="Skip step",qgResume="Restore skipped",qgNavigate="Navigate",qgNone="No available step in this area.",qgLocked="Waiting for requirements",qgNoPoint="No reference coordinates for this step.",qgPhaseHint="The step advances when the game confirms acceptance, objectives or hand-in. Next and Skip do not complete a quest.",qgUpcoming="Coming up",qgSelectArea="Choose an area",qgSearch="Search an area…",qgNoRoute="No route matches your character and filters.",qgObjectivesUnknown="Read the quest log for the exact objective.",qgOptions="Click to change",qgLevel="Level",qgUnknown="Eligibility must be confirmed at the quest giver."},
 cs={questguide="Questový průvodce",sub_questguide="Tvoje vypočtená cesta questy. Class questy, dungeony, postup a navigace.",qgComputed="Vypočteno z referenčních dat; nejde o ručně ověřenou trasu 1–60.",qgClasses="Class questy",qgDungeons="Dungeon questy",qgAuto="Auto navigace",qgTracker="Tracker",qgRecommended="Doporučeno",qgProgress="Odevzdáno %d / %d · přeskočeno %d",qgAccept="Vyzvednout",qgObjectives="Splnit cíle",qgTurnin="Odevzdat",qgNext="Další krok",qgBack="Zpět",qgSkip="Přeskočit krok",qgResume="Vrátit přeskočené",qgNavigate="Navigovat",qgNone="V této oblasti teď není dostupný krok.",qgLocked="Čeká na podmínky",qgNoPoint="Pro tento krok nejsou referenční souřadnice.",qgPhaseHint="Krok postupuje po potvrzení přijetí, cílů či odevzdání hrou. Další ani Přeskočit quest nedokončí.",qgUpcoming="Následuje",qgSelectArea="Vyber oblast",qgSearch="Hledat oblast…",qgNoRoute="Pro postavu a filtry není vhodná trasa.",qgObjectivesUnknown="Přesný cíl najdeš v quest logu.",qgOptions="Kliknutím změnit",qgLevel="Úroveň",qgUnknown="Dostupnost ověř u zadavatele questu."},
}
for lang,values in pairs(translations) do for key,value in pairs(values) do A.locale[lang][key]=value end end
local phaseKeys={accept="qgAccept",objectives="qgObjectives",turnin="qgTurnin"}
local reasonText={
 cs={level="Nízká úroveň",prerequisite="Předchozí quest",exclusive="Jiná větev řetězce",dynamic="Podmínka závislá na postavě",skill="Požadovaná profese",spell="Požadovaná schopnost",reputation="Požadovaná reputace",item="Požadovaný předmět",unverified_requirement="Podmínku nelze automaticky ověřit"},
 en={level="Required level",prerequisite="Previous quest",exclusive="Another branch",dynamic="Character-dependent requirement",skill="Required profession",spell="Required ability",reputation="Required reputation",item="Required item",unverified_requirement="Requirement cannot be verified automatically"},
}
local tracker
local function refresh()
    if A.RefreshUI then A.RefreshUI() end
    if A.QuestGuideRefreshTracker then A.QuestGuideRefreshTracker() end
end
function A.QuestGuideRefreshTracker()
    local state=Q.Store()
    if not state or not state.tracker then if tracker then tracker:Hide() end;return end
    if not tracker then
        local kit=A.UIKit();tracker=CreateFrame("Frame",nil,UIParent)
        tracker:SetSize(290,122);tracker:SetPoint("RIGHT",UIParent,"RIGHT",-35,70);tracker:SetMovable(true);tracker:EnableMouse(true);tracker:SetClampedToScreen(true)
        A.NativePanel(tracker,kit.C);tracker:RegisterForDrag("LeftButton")
        tracker:SetScript("OnDragStart",function(self)self:StartMoving()end)
        tracker:SetScript("OnDragStop",function(self)self:StopMovingOrSizing()end)
        tracker.title=kit.label(tracker,13,kit.C.gold);tracker.title:SetPoint("TOPLEFT",10,-10);tracker.title:SetPoint("TOPRIGHT",-34,-10);tracker.title:SetWordWrap(true)
        tracker.info=kit.label(tracker,11,kit.C.mist);tracker.info:SetPoint("TOPLEFT",10,-39);tracker.info:SetPoint("TOPRIGHT",-10,-39);tracker.info:SetWordWrap(true)
        tracker.close=kit.Button(tracker,nil,20,"ghost",function()Q.SetOption("tracker",false);refresh()end);tracker.close:SetHeight(20);tracker.close:SetPoint("TOPRIGHT",-5,-5);tracker.close.text:SetText("x")
        tracker.go=kit.Button(tracker,"qgNavigate",128,"primary",function()local ok,why=Q.Navigate();if not ok then A.Print(A.L("qgNoPoint").." ("..tostring(why)..")") end end);tracker.go:SetPoint("BOTTOMLEFT",10,9)
        tracker.skip=kit.Button(tracker,"qgSkip",128,"ghost",function()Q.Skip();refresh()end);tracker.skip:SetPoint("BOTTOMRIGHT",-10,9)
    end
    local step=Q.Current()
    tracker.title:SetText(step and step.quest.title or A.L("questguide"))
    tracker.info:SetText(step and (A.L(phaseKeys[step.phase] or "qgObjectives").." · "..(step.quest.zone or "")) or A.L("qgNone"))
    tracker.go.text:SetText(A.L("qgNavigate"));tracker.skip.text:SetText(A.L("qgSkip"));tracker:Show()
end
function A.BuildQuestGuidePage(page,kit)
    A.questGuidePage=page
    local C=kit.C
    kit.PageHeader(page,"questguide")
    page.query=""
    page.search=kit.SearchBox(page,190,function(value)if page.query~=value then page.query=value;refresh()end end)
    page.search:SetPoint("TOPLEFT",0,-57)
    page.options={}
    local previous=page.search
    for _,option in ipairs({{"includeClass","qgClasses"},{"includeDungeons","qgDungeons"}}) do
        local key,label=option[1],option[2]
        local chip=kit.Chip(page,function()local state=Q.Store();Q.SetOption(key,not state[key]);refresh()end)
        chip:SetPoint("LEFT",previous,"RIGHT",8,0);page.options[key]={chip=chip,label=label};previous=chip
    end
    page.note=kit.label(page,10,C.mist);page.note:SetPoint("TOPLEFT",0,-91);page.note:SetPoint("TOPRIGHT",0,-91);page.note:SetWordWrap(true)
    page.book=kit.Book(page,120)
    page.list=kit.ListView(page.book.index,0)
    page.document=kit.Document(page.book.paper)
    page.document.scroll:SetPoint("BOTTOMRIGHT",page.book.paper,"BOTTOMRIGHT",-22,116)
    page.actions={}
    local actions={{"qgBack",Q.Back},{"qgNext",Q.Next},{"qgSkip",Q.Skip},{"qgResume",Q.Resume},{"qgNavigate",function()local ok,why=Q.Navigate();if not ok then A.Print(A.L("qgNoPoint").." ("..tostring(why)..")")end end},{"qgTracker",function()local s=Q.Store();Q.SetOption("tracker",not s.tracker)end}}
    for i,action in ipairs(actions) do
        local key,fn=action[1],action[2]
        local button=kit.Button(page.book.paper,key,110,key=="qgNavigate" and "primary" or "ghost",function()fn();refresh()end)
        button:SetHeight(27);page.actions[i]=button
    end
    page.auto=kit.Chip(page.book.paper,function()local s=Q.Store();Q.SetOption("autoNavigate",not s.autoNavigate);refresh()end)
    page.auto:SetPoint("BOTTOMLEFT",12,8)
    local function layout()
        local bookWidth=tonumber(page.book:GetWidth()) or 640
        page.book.index:SetWidth(math.max(185,math.min(260,bookWidth*0.38)))
        local width=math.max(210,(tonumber(page.book.paper:GetWidth()) or 440)-24)
        local cell=(width-12)/3
        for i,button in ipairs(page.actions) do
            local col=(i-1)%3;local row=math.floor((i-1)/3)
            button:ClearAllPoints();button:SetWidth(cell);button:SetPoint("BOTTOMLEFT",page.book.paper,"BOTTOMLEFT",12+col*(cell+6),70-row*32)
            button.text:SetFont(kit.fontPath(),width<360 and 10 or 11,"")
        end
    end
    page.book.onLayout=layout;page.Layout=layout
    page.Refresh=function()
        local state=Q.Store();if not state then return end
        page.search.hint:SetText(A.L("qgSearch"));page.note:SetText(A.L("qgComputed"))
        for key,entry in pairs(page.options) do entry.chip.SetLabel(A.L(entry.label));entry.chip.SetOn(state[key]==true) end
        page.auto.SetLabel(A.L("qgAuto"));page.auto.SetOn(state.autoNavigate==true)
        local routes=Q.Routes(page.query);local items={}
        for _,route in ipairs(routes) do
            local current=route
            items[#items+1]={title=route.name,sub=(route.recommended and "★ " or "")..string.format("%d–%d · %d/%d",route.minLevel,route.maxLevel,route.done,route.total),right="",icon=kit.ICON.quest,
                titleColor=state.routeKey==route.key and C.gold or C.text,onClick=function()Q.SelectRoute(current.key);refresh()end}
        end
        page.list.SetItems(items,#items==0 and A.L("qgNoRoute") or nil)
        local model,step=Q.Plan(),Q.Current()
        local entries={}
        entries[#entries+1]={text=string.format(A.L("qgProgress"),model.done,model.total,model.skipped)}
        if step then
            entries[#entries+1]={text=A.L(phaseKeys[step.phase] or "qgObjectives"),head=true}
            entries[#entries+1]={text=step.quest.title,head=true,icon=kit.ICON.quest}
            entries[#entries+1]={text=A.L("qgLevel").." "..tostring(step.quest.level).." · "..(step.quest.zone or "")..(step.quest.dungeon and " · "..step.quest.dungeon or "")}
            if step.phase=="objectives" then
                local objectives=C_QuestLog and A.Call(C_QuestLog.GetQuestObjectives,step.questId)
                if type(objectives)=="table" and #objectives>0 then
                    for _,objective in ipairs(objectives) do entries[#entries+1]={text=(objective.finished and "✓ " or "• ")..tostring(objective.text or step.quest.text or A.L("qgObjectivesUnknown"))} end
                else entries[#entries+1]={text=step.quest.text~="" and step.quest.text or A.L("qgObjectivesUnknown")} end
            else
                local people=step.phase=="accept" and step.quest.starts or step.quest.ends
                for _,person in ipairs(people or {}) do entries[#entries+1]={text=person.name or ("#"..tostring(person.id)),icon=person.kind=="item" and kit.itemIcon(person.id) or kit.ICON.npc} end
                if Q.State(step.questId)=="unknown" then entries[#entries+1]={text=A.L("qgUnknown")} end
            end
            if #step.targets==0 then entries[#entries+1]={text=A.L("qgNoPoint")} end
            entries[#entries+1]={text=A.L("qgUpcoming"),head=true}
            local _,index=Q.Current()
            for i=index+1,math.min(#model.steps,index+4) do
                local nextStep=model.steps[i]
                entries[#entries+1]={text=A.L(phaseKeys[nextStep.phase] or "qgObjectives")..": "..nextStep.quest.title,onClick=function()Q.SelectStep(nextStep.key);refresh()end}
            end
        else entries[#entries+1]={text=A.L("qgNone")} end
        if #model.locked>0 then
            entries[#entries+1]={text=A.L("qgLocked").." ("..#model.locked..")",head=true}
            local reasons=reasonText[A.db.settings.language=="cs" and "cs" or "en"]
            for index=1,math.min(8,#model.locked) do local blocked=model.locked[index];entries[#entries+1]={text=blocked.quest.title.." — "..(reasons[blocked.reason] or blocked.reason)} end
        end
        entries[#entries+1]={text=A.L("qgPhaseHint"),size=10}
        local title=model.route and (model.route.name.." "..model.route.minLevel.."–"..model.route.maxLevel) or A.L("qgSelectArea")
        page.document.Set({key="questguide:"..tostring(state.routeKey or state.map)..":"..tostring(step and step.key),title=title,entries=entries})
        layout()
    end
end
