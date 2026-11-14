local _, A = ...
-- Our friendly name-only presentation, anchored to the nameplate supplied by the client.
-- Never reparent/hide the protected UnitFrame or replace any Blizzard method. Only a readable,
-- non-forbidden name text is muted, and its exact alpha is restored when we stop using it.
local states, removed, revision = {}, {}, 0
local LOGO = "Interface\\AddOns\\Evertally\\Media\\Logo"
local function settings() return A.db and A.db.settings or {} end
-- One schema for Settings and the setup draft. Optional elements stay off by default.
A.FriendlyPlateOptions = {
    {key="plateName", default=true, group="names"},
    {key="plateFont", default="game", values={"game","friz","arial","morpheus","skurri"}, group="names"},
    {key="plateFontSize", default=15, min=10, max=32, step=1, group="names"},
    {key="plateScale", default=100, min=60, max=160, step=10, group="names"},
    {key="plateOutline", default="none", values={"none","outline","thick"}, group="names"},
    {key="plateShadow", default=true, group="names"},
    {key="plateMarks", default=true, group="icons"},
    {key="markSize", default=12, min=10, max=32, step=1, group="icons"},
    {key="markUsers", default=true, group="icons"},
    {key="plateLogoSize", default=12, min=10, max=32, step=1, group="icons"},
    {key="plateBuffs", default=false, group="auras"},
    {key="plateDebuffs", default=false, group="auras"},
    {key="plateAuraTimers", default=true, group="auras"},
    {key="plateAuraSize", default=20, min=12, max=40, step=1, group="auras"},
    {key="plateAuraLimit", default=6, min=1, max=12, step=1, group="auras"},
    {key="plateCast", default=false, group="bars"},
    {key="plateCastIcon", default=true, group="bars"},
    {key="plateCastLabel", default=true, group="bars"},
    {key="plateCastHeight", default=12, min=8, max=24, step=1, group="bars"},
    {key="plateHealth", default=false, group="bars"},
    {key="plateHealthText", default=true, group="bars"},
    {key="plateWidth", default=140, min=80, max=300, step=10, group="bars"},
    {key="plateOffsetX", default=0, min=-100, max=100, step=1, group="position"},
    {key="plateDistance", default=60, min=20, max=100, step=5, group="position"},
    {key="plateOffsetY", default=0, min=-100, max=100, step=1, group="position"},
    {key="plateMarkX", default=0, min=-100, max=100, step=1, group="position"},
    {key="plateMarkY", default=0, min=-100, max=100, step=1, group="position"},
    {key="plateLogoX", default=0, min=-100, max=100, step=1, group="position"},
    {key="plateLogoY", default=0, min=-100, max=100, step=1, group="position"},
}
local function optionValue(source, option)
    if option.key=="plateDistance" and A.PlateCVar then
        local global=A.Number(tonumber(A.PlateCVar("nameplateMaxDistance")),20,100)
        local players=A.Number(tonumber(A.PlateCVar("nameplatePlayerMaxDistance")),20,100)
        if global and players then return math.min(global,players) end
        if players or global then return players or global end
    end
    if option.values then
        for _,value in ipairs(option.values) do if source[option.key]==value then return value end end
        return option.default
    end
    if option.min then return A.Number(source[option.key], option.min, option.max) or option.default end
    if type(source[option.key]) == "boolean" then return source[option.key] end
    return option.default
end
function A.FriendlyPlateChoices(source)
    source = type(source)=="table" and source or settings()
    local choices = {plateGameLook=source.plateGameLook~=false}
    for _,option in ipairs(A.FriendlyPlateOptions) do choices[option.key]=optionValue(source,option) end
    return choices
end
function A.ApplyFriendlyPlateChoices(choices)
    local s = settings()
    local values = A.FriendlyPlateChoices(choices)
    for key,value in pairs(values) do s[key]=value end
    A.FriendlyPlatesChanged()
end
function A.SetFriendlyPlateOption(key,value)
    if key=="plateDistance" then return A.SetFriendlyPlateRange(value) end
    local choices=A.FriendlyPlateChoices();choices[key]=value
    A.ApplyFriendlyPlateChoices(choices);A.Changed()
end
function A.UseFriendlyPlateProvider(provider)
    if provider~="evertally" and provider~="blizzard" then return false end
    if A.Call(InCombatLockdown)==true then A.Print(A.L("markPlatesCombat"));return false end
    if not A.SetFriendlyPlates(provider=="evertally") then return false end
    settings().plateGameLook=provider=="evertally"
    A.FriendlyPlatesChanged();A.Changed()
    return true
end
local function number(key, default, lo, hi) return A.Number(settings()[key], lo, hi) or default end
local function allowed(frame)
    if not frame then return false end
    local fn = A.Field(frame, "IsForbidden")
    return type(fn) ~= "function" or A.Call(fn, frame) == false
end
local function nativeName(plate)
    local frame = A.Field(plate, "UnitFrame")
    if not allowed(frame) then return nil end
    for _, key in ipairs({"name", "Name", "NameText"}) do
        local name = A.Field(frame, key)
        if allowed(name) and A.Call(A.Field(name, "IsVisible"), name) == true then return name end
    end
end
local function restore(state)
    if state.native and state.alpha ~= nil and allowed(state.native) then
        pcall(state.native.SetAlpha, state.native, state.alpha)
    end
    state.native, state.alpha, state.unit, state.cast = nil, nil, nil, nil
    state.key, state.auraDirty = nil, true
    state.frame:Hide()
end
local FONT_FILES={friz="Fonts\\FRIZQT__.TTF",arial="Fonts\\ARIALN.TTF",morpheus="Fonts\\MORPHEUS.TTF",skurri="Fonts\\SKURRI.TTF"}
local function font(text, size, name)
    local file = A.Call(GameFontNormal and GameFontNormal.GetFont, GameFontNormal)
    local s=settings()
    local flags=name and ({outline="OUTLINE",thick="THICKOUTLINE"})[s.plateOutline] or ""
    local path=name and FONT_FILES[s.plateFont] or nil
    local ok,result=pcall(text.SetFont,text,path or A.Text(file,200) or FONT_FILES.friz,size,flags or "")
    if not ok or result==false then text:SetFont(A.Text(file,200) or FONT_FILES.friz,size,flags or "") end
    text:SetShadowColor(0, 0, 0, 1); text:SetShadowOffset(name and s.plateShadow==false and 0 or 1,name and s.plateShadow==false and 0 or -1)
end
local function create(plate,preview)
    local f = CreateFrame("Frame", nil, plate)
    f:EnableMouse(false)
    local state = {frame=f, buffs={}, debuffs={}, auraDirty=true}
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.name:SetPoint("CENTER"); f.name:SetWordWrap(false);f.name:SetJustifyH("CENTER")
    f.mark = f:CreateTexture(nil, "OVERLAY")
    f.logo = f:CreateTexture(nil, "OVERLAY"); f.logo:SetTexture(LOGO)
    for _, kind in ipairs({"health", "cast"}) do
        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar.bg = bar:CreateTexture(nil, "BACKGROUND"); bar.bg:SetAllPoints(); bar.bg:SetColorTexture(0,0,0,0.75)
        bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.label:SetPoint("LEFT",4,0); bar.label:SetPoint("RIGHT",-4,0); font(bar.label,10)
        bar:Hide(); f[kind] = bar
    end
    f.cast.icon = f.cast:CreateTexture(nil, "OVERLAY"); f.cast.icon:SetTexCoord(0.08,0.92,0.08,0.92)
    f:Hide()
    state.preview=preview
    if not preview then states[plate] = state end
    return state
end
function A.ReadFriendlyAuras(unit, filter, limit)
    local out = {}
    limit = math.floor(A.Number(limit,1,12) or 6)
    for i=1,40 do
        local name, icon, count, duration, expires
        if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex)=="function" then
            local aura=A.Call(C_UnitAuras.GetAuraDataByIndex,unit,i,filter)
            if not aura then break end
            name=A.Text(A.Field(aura,"name"),160); icon=A.Plain(A.Field(aura,"icon"))
            count=A.Number(A.Field(aura,"applications"),0,9999)
            duration=A.Number(A.Field(aura,"duration"),0)
            expires=A.Number(A.Field(aura,"expirationTime"),0)
        else
            local fn = filter=="HELPFUL" and UnitBuff or UnitDebuff
            local n, texture, stacks, _, seconds, expiry=A.Call(fn,unit,i)
            if not n then break end
            name=A.Text(n,160);icon=A.Plain(texture);count=A.Number(stacks,0,9999)
            duration=A.Number(seconds,0);expires=A.Number(expiry,0)
        end
        if name and (type(icon)=="string" or A.Number(icon,1)) then
            out[#out+1]={name=name,icon=icon,count=count or 0,expires=duration and duration>0 and expires or nil}
            if #out>=limit then break end
        end
    end
    return out
end
function A.ReadFriendlyCast(unit)
    local name,_,icon,startAt,endAt=A.Call(UnitCastingInfo,unit)
    local channel=false
    if not name then name,_,icon,startAt,endAt=A.Call(UnitChannelInfo,unit);channel=true end
    name=A.Text(name,160); startAt=A.Number(startAt,0);endAt=A.Number(endAt,0)
    if not name or not startAt or not endAt or endAt<=startAt or endAt-startAt>86400000 then return nil end
    return {name=name,icon=A.Number(icon,1) or A.Text(icon,200),startAt=startAt/1000,endAt=endAt/1000,channel=channel}
end
local function auraIcon(state, list, index)
    if list[index] then return list[index] end
    local f=CreateFrame("Frame",nil,state.frame)
    f.texture=f:CreateTexture(nil,"ARTWORK");f.texture:SetAllPoints();f.texture:SetTexCoord(0.08,0.92,0.08,0.92)
    f.count=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");font(f.count,10);f.count:SetPoint("BOTTOMRIGHT",1,-1)
    f.time=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");font(f.time,10);f.time:SetPoint("CENTER")
    list[index]=f
    return f
end
local function auraRow(state, list, filter, enabled, y)
    local sample={{name="Preview",icon=filter=="HELPFUL" and 135987 or 132273,count=2,expires=A.Monotonic()+18}}
    local data=enabled and (state.preview and sample or A.ReadFriendlyAuras(state.unit,filter,number("plateAuraLimit",6,1,12))) or {}
    local px=number("plateAuraSize",20,12,40)
    for i,aura in ipairs(data) do
        local f=auraIcon(state,list,i);f:ClearAllPoints();f:SetSize(px,px)
        f:SetPoint("BOTTOM",state.frame,"TOP",(i-(#data+1)/2)*(px+2),y)
        f.texture:SetTexture(aura.icon);f.count:SetText(aura.count>1 and tostring(aura.count) or "")
        f.expires=aura.expires;f:Show()
    end
    for i=#data+1,#list do list[i]:Hide();list[i].expires=nil end
    return #data>0 and y+px+3 or y
end
local function updateAuras(state)
    local s=settings()
    local y=auraRow(state,state.buffs,"HELPFUL",s.plateBuffs==true,4)
    auraRow(state,state.debuffs,"HARMFUL",s.plateDebuffs==true,y)
    state.auraDirty=false
end
local function timer(state,now)
    local s=settings()
    for _,list in ipairs({state.buffs,state.debuffs}) do
        for _,aura in ipairs(list) do
            if aura:IsShown() then
                local left=aura.expires and aura.expires-now
                if left and left<=0 then aura:Hide();state.auraDirty=true
                else
                    local text=s.plateAuraTimers~=false and left and (left>=60 and math.ceil(left/60).."m" or tostring(math.ceil(left))) or ""
                    if aura.lastTime~=text then aura.time:SetText(text);aura.lastTime=text end
                end
            end
        end
    end
    local bar,cast=state.frame.cast,state.cast
    if s.plateCast~=true or not cast or now>=cast.endAt then bar:Hide();return end
    local total=cast.endAt-cast.startAt
    bar:SetMinMaxValues(0,total)
    bar:SetValue(math.max(0,math.min(total,cast.channel and cast.endAt-now or now-cast.startAt)))
    bar.label:SetText(s.plateCastLabel~=false and (cast.name..string.format("  %.1fs",math.max(0,cast.endAt-now))) or "")
    bar:Show()
end
local function layout(state,name,native)
    local s,f=settings(),state.frame
    local px=number("plateFontSize",15,10,32)
    local width=number("plateWidth",140,80,300)
    local mark=s.plateMarks~=false and (state.preview and 8 or A.GetMark(name))
    local logo=s.markUsers~=false and (state.preview or A.IsEvertallyUser(name,state.realm))
    local iconPx=number("markSize",12,10,32);local logoPx=number("plateLogoSize",12,10,32)
    local signature=table.concat({name,px,width,number("plateScale",100,60,160),iconPx,logoPx,tostring(mark),tostring(logo),tostring(s.plateName~=false),tostring(s.plateFont),tostring(s.plateOutline),tostring(s.plateShadow),number("plateMarkX",0,-100,100),number("plateMarkY",0,-100,100),number("plateLogoX",0,-100,100),number("plateLogoY",0,-100,100)},"|")
    if signature~=state.key then
        font(f.name,px,true);f.name:SetText(s.plateName~=false and name or "")
        f.name:SetWidth(math.max(1,(A.Call(f.name.GetStringWidth,f.name) or 0)+16));f.name:SetHeight(px+4)
        local r,g,b=A.Call(native.GetTextColor,native)
        f.name:SetTextColor(A.Number(r,0,1) or 0.4,A.Number(g,0,1) or 1,A.Number(b,0,1) or 0.4)
        f:SetSize(width,px+4);f:SetScale(number("plateScale",100,60,160)/100)
        f.mark:ClearAllPoints();f.logo:ClearAllPoints()
        local x=(A.Number(A.Call(f.name.GetStringWidth,f.name),0,1000) or 0)/2+3
        f.mark:SetSize(iconPx,iconPx);f.mark:SetPoint("LEFT",f,"CENTER",x+number("plateMarkX",0,-100,100),number("plateMarkY",0,-100,100))
        local texture,crop=A.MarkTexture(mark)
        if texture then f.mark:SetTexture(texture);f.mark:SetTexCoord(crop and 0.08 or 0,crop and 0.92 or 1,crop and 0.08 or 0,crop and 0.92 or 1);f.mark:Show() else f.mark:Hide() end
        f.logo:SetSize(logoPx,logoPx);f.logo:SetPoint("LEFT",f,"CENTER",x+(mark and iconPx+3 or 0)+number("plateLogoX",0,-100,100),number("plateLogoY",0,-100,100));f.logo:SetShown(logo==true)
        state.key=signature
    end
    local health=f.health
    if s.plateHealth==true then
        local hp,max=A.Number(A.Call(UnitHealth,state.unit),0),A.Number(A.Call(UnitHealthMax,state.unit),1)
        if state.preview then hp,max=72,100 end
        if hp and max then
            health:ClearAllPoints();health:SetPoint("TOP",f,"BOTTOM",0,-2);health:SetSize(width,10)
            health:SetMinMaxValues(0,max);health:SetValue(hp);health:SetStatusBarColor(0.2,0.75,0.25)
            health.label:SetText(s.plateHealthText~=false and math.floor(math.min(hp/max,1)*100).."%" or "");health:Show()
        else health:Hide() end
    else health:Hide() end
    f.cast:ClearAllPoints();f.cast:SetPoint("TOP",f,"BOTTOM",0,health:IsShown() and -15 or -2)
    local castHeight=number("plateCastHeight",12,8,24)
    f.cast:SetSize(width,castHeight);f.cast:SetStatusBarColor(1,0.72,0.18)
    state.cast=s.plateCast==true and A.ReadFriendlyCast(state.unit) or nil
    if state.preview and s.plateCast==true then state.cast={name=A.L("platePreviewSpell"),icon=136048,startAt=A.Monotonic()-1,endAt=A.Monotonic()+2} end
    f.cast.icon:ClearAllPoints();f.cast.icon:SetSize(castHeight+2,castHeight+2);f.cast.icon:SetPoint("RIGHT",f.cast,"LEFT",-3,0)
    if s.plateCastIcon~=false and state.cast and state.cast.icon then f.cast.icon:SetTexture(state.cast.icon);f.cast.icon:Show() else f.cast.icon:Hide() end
end
-- The preview uses the exact same name/icon/bar layout and fonts as world plates.
function A.CreateFriendlyPlatePreview(parent)
    local state=create(parent,true)
    function state.Update()
        state.frame:ClearAllPoints();state.frame:SetPoint("CENTER",parent,"CENTER",number("plateOffsetX",0,-100,100),number("plateOffsetY",0,-100,100))
        local name=A.UnitPlayerName("player") or "Evertally"
        layout(state,name,{GetTextColor=function() return 0.5,0.8,1 end})
        updateAuras(state);timer(state,A.Monotonic());state.frame:Show()
        local scale=number("plateScale",100,60,160)/100
        local w=A.Number(A.Call(parent.GetWidth,parent),1) or 640
        local h=A.Number(A.Call(parent.GetHeight,parent),1) or 94
        local extentX=math.max(180,(A.Call(state.frame.name.GetStringWidth,state.frame.name) or 100)/2+80)+math.abs(number("plateOffsetX",0,-100,100))+math.max(math.abs(number("plateMarkX",0,-100,100)),math.abs(number("plateLogoX",0,-100,100)))
        local extentY=40+math.abs(number("plateOffsetY",0,-100,100))+math.max(math.abs(number("plateMarkY",0,-100,100)),math.abs(number("plateLogoY",0,-100,100)))
        local fit=math.max(0.05,math.min(1,(w-16)/(2*extentX*scale),(h-8)/(2*extentY*scale)))
        state.frame:SetScale(scale*fit)
        state.frame:ClearAllPoints();state.frame:SetPoint("CENTER",parent,"CENTER",number("plateOffsetX",0,-100,100)*fit,number("plateOffsetY",0,-100,100)*fit)
    end
    return state
end
local function updatePlate(plate)
    if not allowed(plate) or A.Call(A.Field(plate,"IsShown"),plate)==false then return end
    local unit=A.Text(A.Field(plate,"namePlateUnitToken"),40) or A.Text(A.Field(A.Field(plate,"UnitFrame"),"unit"),40)
    if not unit or removed[unit] or A.Call(UnitExists,unit)==false or A.Call(UnitIsPlayer,unit)~=true or A.Call(UnitIsUnit,unit,"player")==true then return end
    if A.Call(UnitIsFriend,"player",unit)~=true and A.Call(UnitCanAttack,"player",unit)~=false then return end
    local name,realm=A.UnitPlayerName(unit)
    local native=nativeName(plate)
    if not name or not native then return end
    local state=states[plate]
    if state and state.unit and (state.unit~=unit or state.native~=native or state.name~=name) then restore(state) end
    local alpha=state and state.alpha or A.Number(A.Call(native.GetAlpha,native),0,1)
    if not alpha or alpha==0 then return end
    state=state or create(plate)
    state.unit,state.name,state.realm=unit,name,realm
    state.frame:ClearAllPoints();state.frame:SetPoint("CENTER",native,"CENTER",number("plateOffsetX",0,-100,100),number("plateOffsetY",0,-100,100))
    layout(state,name,native)
    if state.revision~=revision then state.auraDirty=true;state.revision=revision end
    if state.auraDirty then updateAuras(state) end
    timer(state,A.Monotonic())
    -- Only show our replacement after the original was successfully muted.
    local ok=pcall(native.SetAlpha,native,0)
    if not ok then restore(state);return end
    state.native,state.alpha=native,alpha
    state.frame:Show();state.seen=true
end
function A.RefreshFriendlyPlates()
    for _,state in pairs(states) do state.seen=false end
    local s=settings()
    if (not A.RequirementsReady or A.RequirementsReady()) and s.plateGameLook~=false and A.FriendlyPlatesShown() and A.PlateCVar("nameplateShowOnlyNameForFriendlyPlayerUnits")=="1" then
        local plates=A.Call(C_NamePlate and C_NamePlate.GetNamePlates)
        if type(plates)=="table" then
            local n=0
            for _,plate in ipairs(plates) do
                n=n+1;if n>48 then break end
                local ok=pcall(updatePlate,plate)
                if not ok and states[plate] then restore(states[plate]) end
            end
        end
    end
    for _,state in pairs(states) do if not state.seen then restore(state) end end
end
function A.FriendlyPlateManaged(plate,unit)
    local state=states[plate]
    return state~=nil and state.unit==unit and state.frame:IsShown()
end
function A.FriendlyPlatesChanged()
    revision=revision+1
    A.RefreshFriendlyPlates()
    if A.MarksRefresh then A.MarksRefresh() end
end
-- Data changes refresh only the affected unit's aura rows. Timer ticks never scan auras.
A.On("UNIT_AURA",function(unit)
    for _,state in pairs(states) do if state.unit==unit then state.auraDirty=true end end
end)
A.On("NAME_PLATE_UNIT_REMOVED",function(unit)
    if type(unit)=="string" then removed[unit]=true end
    for _,state in pairs(states) do if state.unit==unit then restore(state) end end
end)
A.On("NAME_PLATE_UNIT_ADDED",function(unit)
    if type(unit)=="string" then removed[unit]=nil end
    A.RefreshFriendlyPlates()
end)
A.On("PLAYER_ENTERING_WORLD",function()
    removed={};for _,state in pairs(states) do restore(state) end
    A.EnsureFriendlyPlateRange()
end)
if C_Timer and type(C_Timer.NewTicker)=="function" then
    C_Timer.NewTicker(0.25,function() pcall(A.RefreshFriendlyPlates) end)
    C_Timer.NewTicker(0.1,function()
        local now=A.Monotonic()
        for _,state in pairs(states) do if state.unit then pcall(timer,state,now) end end
    end)
end

local labels={
    nameplatesSection={"Nameplates", "Jmenovky"},
    plateGameLook={"Use Evertally friendly nameplates", "Vlastní jmenovky spojenců Evertally"},
    plateName={"Show player names", "Zobrazovat jména hráčů"},
    plateMarks={"Show my player marks", "Zobrazovat moje značky hráčů"},
    markUsers={"Show the Evertally logo for addon users", "Zobrazovat logo u uživatelů Evertally"},
    plateFontSize={"Name size", "Velikost jména"},
    markSize={"Mark icon size", "Velikost značek"},
    plateLogoSize={"Logo size", "Velikost loga"},
    plateScale={"Whole nameplate scale (%)", "Měřítko celé jmenovky (%)"},
    plateWidth={"Health / cast bar width", "Šířka ukazatele zdraví / kouzlení"},
    plateBuffs={"Show buffs", "Zobrazovat buffy"},
    plateDebuffs={"Show debuffs", "Zobrazovat debuffy"},
    plateAuraTimers={"Show buff / debuff countdowns", "Zobrazovat odpočty buffů / debuffů"},
    plateAuraSize={"Buff / debuff icon size", "Velikost ikon buffů / debuffů"},
    plateAuraLimit={"Maximum icons per aura row", "Nejvýše ikon v jednom řádku aur"},
    plateCast={"Show cast / channel bar", "Zobrazovat kouzlení / sesílání"},
    plateCastIcon={"Show spell icon", "Zobrazovat ikonu kouzla"},
    plateCastLabel={"Show spell name and time", "Zobrazovat název kouzla a čas"},
    plateCastHeight={"Cast bar height", "Výška ukazatele kouzlení"},
    plateHealth={"Show health bar", "Zobrazovat zdraví"},
    plateHealthText={"Show health percentage", "Zobrazovat procenta zdraví"},
    plateTab_names={"Name", "Jméno"},
    plateTab_auras={"Buffs / debuffs", "Buffy / debuffy"},
    plateTab_bars={"Bars", "Lišty"},
    plateTab_icons={"Icons", "Ikony"},plateTab_position={"Position", "Pozice"},
    plateFont={"Font", "Písmo"},plateOutline={"Outline", "Obrys"},plateShadow={"Text shadow", "Stín textu"},
    plateValue_game={"Game font", "Herní font"},plateValue_friz={"Friz Quadrata", "Friz Quadrata"},plateValue_arial={"Arial Narrow", "Arial Narrow"},
    plateValue_morpheus={"Morpheus", "Morpheus"},plateValue_skurri={"Skurri", "Skurri"},plateValue_none={"None", "Žádný"},plateValue_outline={"Thin", "Tenký"},plateValue_thick={"Thick", "Silný"},
    plateOffsetX={"Whole nameplate: left / right", "Celá jmenovka: vlevo / vpravo"},plateOffsetY={"Whole nameplate: down / up", "Celá jmenovka: dolů / nahoru"},
    plateMarkX={"Mark: left / right", "Značka: vlevo / vpravo"},plateMarkY={"Mark: down / up", "Značka: dolů / nahoru"},
    plateLogoX={"Logo: left / right", "Logo: vlevo / vpravo"},plateLogoY={"Logo: down / up", "Logo: dolů / nahoru"},
    plateProvider_evertally={"Evertally · recommended", "Evertally · doporučujeme"},plateProvider_blizzard={"Blizzard", "Blizzard"},
    plateProviderSub_evertally={"Close to the original look, with marks, logo and adjustable elements. Activate now and customize.", "Podobné originálu, navíc značky, logo a nastavitelné prvky. Kliknutím zapneš a přejdeš na úpravy."},
    plateProviderSub_blizzard={"Use the original game names. Evertally leaves their appearance to Blizzard.", "Původní jména ze hry. Jejich vzhled bude určovat Blizzard."},
    plateChooseHelp={"Choose your friendly nameplates. The choice activates immediately; you can change it later.", "Vyber jmenovky spojenců. Volba se aktivuje ihned a můžeš ji později změnit."},
    plateChangeProvider={"Change style", "Změnit styl"},
    platePreview={"Live preview · sample icons and auras · fitted to this panel", "Živý náhled · ukázkové ikony a aury · přizpůsoben prostoru"},
    platePreviewSpell={"Lightning Bolt", "Blesk"},
    plateDistance={"Range (yards, client limit)", "Dosah (yardy, limit hry)"},
    plateHelp={"Uses friendly name-only plates as anchors. Enable them below. Names and icons are on by default; health, buffs, debuffs and casts are optional. Restricted nameplates or hidden API data are left to the game.", "Používá jmenovky spojenců jen se jménem jako kotvy. Zapni je níže. Jména a ikonky jsou výchozí; zdraví, buffy, debuffy a kouzlení jsou volitelné. Chráněné jmenovky a nepřístupná data zůstávají hře."},
}
for key,text in pairs(labels) do A.locale.en[key]=text[1];A.locale.cs[key]=text[2] end
