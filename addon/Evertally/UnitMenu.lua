local _,A=...
-- Extend the supported menu API only. Do not hook/rewrite Blizzard's secure
-- UnitPopup tables or add anything while unit identity is restricted.
local registered={}
local function restricted(unit)
    if type(InCombatLockdown)=="function" and A.Call(InCombatLockdown)~=false then return true end
    local restrictions=Enum and Enum.AddOnRestrictionType
    if C_RestrictedActions and type(restrictions)=="table" then
        for _,kind in pairs(restrictions) do
            local fn=C_RestrictedActions.IsAddOnRestrictionActive
            if type(fn)=="function" and A.Call(fn,kind)~=false then return true end
        end
    end
    if C_Secrets then
        for _,entry in ipairs({{C_Secrets.ShouldUnitIdentityBeSecret,unit},{C_Secrets.ShouldAurasBeSecret}}) do
            if type(entry[1])=="function" and A.Call(entry[1],entry[2])~=false then return true end
        end
    end
    return false
end
function A.OpenNameplateSettings()
    A.ShowView("settings")
    if A.settingsPage then A.settingsPage.SelectSection(5) end
end
function A.AddPlayerUnitMenu(owner,root,data)
    local unit=A.Text(A.Field(data,"unit"),40)
    if not unit or restricted(unit) or A.Call(UnitIsPlayer,unit)~=true then return end
    local name=A.UnitPlayerName(unit)
    if not name or name=="" then return end
    local guid=A.Text(A.Call(UnitGUID,unit),100)
    local self=A.Call(UnitIsUnit,unit,"player")==true
    root:CreateDivider()
    local menu=root:CreateButton("Evertally")
    local marks=menu:CreateButton(A.L("unitMenuMark"))
    for i=1,8 do
        local mark=i
        marks:CreateButton((A.MarkMarkup(mark,14) or tostring(mark)).."  "..A.L("unitMenuMark").." "..mark,function() A.SetMark(name,mark) end)
    end
    marks:CreateButton(A.L("markRemove"),function() A.SetMark(name,0) end)
    marks:CreateButton(A.L("unitMenuCustomIcon"),function() A.OpenMarkPicker(UIParent,owner or UIParent,name) end)
    if not self then
        menu:CreateButton(A.L("unitMenuNavigate"),function()
            -- A different target must never silently replace the clicked player.
            local ok,why=A.NavigateByName(name)
            if not ok and (not guid or A.Text(A.Call(UnitGUID,unit),100)==guid) and C_Map then
                local map=A.Number(A.Call(C_Map.GetBestMapForUnit,unit),1)
                local point=map and A.Call(C_Map.GetPlayerMapPosition,map,unit)
                local x,y=A.Call(A.Field(point,"GetXY"),point)
                x,y=A.Number(x,0,1),A.Number(y,0,1)
                if x and y then ok,why=A.NavigateToPoint(name,map,x,y,{view="social"}) end
            end
            if not ok then A.Print(A.L("navErr_"..(why or "unknown_player"))) end
        end)
        menu:CreateButton("Evertally inspect",function()
            local ok,why=A.RequestInspect(name)
            if not ok then A.Print(A.L("socialErr_"..(why or "no_target"))) end
        end)
    end
    menu:CreateButton(A.L("unitMenuSettings"),A.OpenNameplateSettings)
end
function A.RegisterPlayerUnitMenus()
    if not Menu or type(Menu.ModifyMenu)~="function" then return end
    for _,which in ipairs({"PLAYER","PARTY","RAID_PLAYER","RAID","FRIEND","SELF"}) do
        local tag="MENU_UNIT_"..which
        if not registered[tag] then
            local ok=pcall(Menu.ModifyMenu,tag,A.AddPlayerUnitMenu)
            if ok then registered[tag]=true end
        end
    end
end
A.On("ADDON_LOADED",A.RegisterPlayerUnitMenus)
A.On("PLAYER_LOGIN",A.RegisterPlayerUnitMenus)
A.RegisterPlayerUnitMenus()
local labels={unitMenuMark={"Player mark","Značka hráče"},unitMenuCustomIcon={"Choose another icon…","Vybrat jinou ikonu…"},unitMenuNavigate={"Navigate to player","Navigovat k hráči"},unitMenuSettings={"Nameplate settings…","Nastavení jmenovek…"}}
for key,value in pairs(labels) do A.locale.en[key]=value[1];A.locale.cs[key]=value[2] end
