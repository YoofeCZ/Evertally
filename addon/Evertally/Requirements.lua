local _,A=...
local window,lastCheck
local linkWindow
A.BRIDGE_MINIMUM="0.9.9"
local installationLinks={bridge="https://evertally.afstudio.dev/#sync",openmap="https://www.curseforge.com/wow/addons/openmap"}
-- WoW has no public API for opening an arbitrary browser URL. Keep addresses
-- behind an explicit button and show a focused copy field only on request.
function A.OpenInstallationLink(which)
    local url=installationLinks[which]
    if not url then return false end
    local k=A.UIKit();local C=k.C
    if not linkWindow then
        linkWindow=CreateFrame("Frame","EvertallyInstallationLink",UIParent)
        A.installationLinkWindow=linkWindow
        linkWindow:SetSize(650,218);linkWindow:SetPoint("CENTER");linkWindow:SetFrameStrata("FULLSCREEN_DIALOG")
        linkWindow:SetClampedToScreen(true);linkWindow:EnableMouse(true);A.NativeFrame(linkWindow,C)
        linkWindow.title=k.label(linkWindow,18,C.gold);linkWindow.title:SetPoint("TOPLEFT",24,-22)
        linkWindow.help=k.label(linkWindow,12,C.text);linkWindow.help:SetPoint("TOPLEFT",24,-60);linkWindow.help:SetPoint("TOPRIGHT",-24,-60)
        linkWindow.address=k.LinkBox(linkWindow);linkWindow.address:SetPoint("TOPLEFT",24,-111);linkWindow.address:SetPoint("TOPRIGHT",-24,-111)
        linkWindow.close=k.Button(linkWindow,"installLinkClose",120,"primary",function() linkWindow:Hide() end)
        linkWindow.close:SetPoint("BOTTOMRIGHT",-24,20)
        linkWindow:SetScript("OnHide",function() linkWindow.address:ClearFocus() end)
        if type(UISpecialFrames)=="table" then UISpecialFrames[#UISpecialFrames+1]="EvertallyInstallationLink" end
    end
    linkWindow.title:SetText(A.L("installOpen_"..which));linkWindow.help:SetText(A.L("installLinkHelp"))
    linkWindow.close.text:SetText(A.L("installLinkClose"));linkWindow.address.SetUrl(url)
    linkWindow:Show();linkWindow.address:SetFocus();linkWindow.address:HighlightText()
    return true
end
local function version(text)
    text=A.Text(text,32)
    if not text then return nil end
    local a,b,c=text:match("^(%d+)%.(%d+)%.(%d+)$")
    a,b,c=tonumber(a),tonumber(b),tonumber(c)
    if not a or not b or not c or a>999 or b>999 or c>999 then return nil end
    return a*1000000+b*1000+c
end
function A.RequirementsStatus()
    local receipt=A.bridgeInstallation
    local v=version(A.Field(receipt,"bridgeVersion"))
    local at=A.Number(A.Field(receipt,"createdAt"),1,A.Now()+300)
    local bridge=A.Field(receipt,"schemaVersion")==1 and A.Field(receipt,"kind")=="evertally-bridge-installation" and v~=nil and v>=version(A.BRIDGE_MINIMUM) and at~=nil
    local openmap=A.OpenMapInstalled and A.OpenMapInstalled()==true or false
    return {bridge=bridge==true,openmap=openmap,ready=bridge==true and openmap,bridgeVersion=v and A.Field(receipt,"bridgeVersion") or nil}
end
function A.RequirementsReady() return A.RequirementsStatus().ready end
function A.VerifyInstallation()
    lastCheck=A.RequirementsStatus()
    if window and window.Refresh then window.Refresh() end
    return lastCheck.ready,lastCheck
end
function A.RequirementsGuard()
    if A.RequirementsReady() then return true end
    A.ShowRequirements()
    return false
end
function A.ShowRequirements()
    if not A.db or type(CreateFrame)~="function" then return end
    if not window then
        local k=A.UIKit();local C=k.C
        window=CreateFrame("Frame","EvertallyInstallation",UIParent)
        A.requirementsWindow=window
        window:SetSize(720,540);window:SetPoint("CENTER");window:SetFrameStrata("DIALOG");window:SetClampedToScreen(true)
        window:EnableMouse(true);window:SetMovable(true);window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart",function() window:StartMoving() end);window:SetScript("OnDragStop",function() window:StopMovingOrSizing() end)
        A.NativeFrame(window,C)
        window.title=k.label(window,22,C.gold);window.title:SetPoint("TOPLEFT",26,-22)
        window.subtitle=k.label(window,12,C.text);window.subtitle:SetPoint("TOPLEFT",26,-60);window.subtitle:SetPoint("TOPRIGHT",-26,-60)
        window.rows={}
        for i,which in ipairs({"bridge","openmap"}) do
            local top=112+(i-1)*112
            local row={}
            row.title=k.label(window,15,C.text);row.title:SetPoint("TOPLEFT",26,-top)
            row.status=k.label(window,12,C.mist);row.status:SetPoint("TOPRIGHT",-26,-top);row.status:SetJustifyH("RIGHT")
            row.body=k.label(window,11,C.mist);row.body:SetPoint("TOPLEFT",26,-top-27);row.body:SetPoint("TOPRIGHT",-26,-top-27)
            local destination=which
            row.open=k.Button(window,"installOpen_"..which,210,"ghost",function() A.OpenInstallationLink(destination) end)
            row.open:SetPoint("TOPLEFT",26,-top-60)
            window.rows[which]=row
        end
        window.help=k.label(window,11,C.mist);window.help:SetPoint("TOPLEFT",26,-346);window.help:SetPoint("TOPRIGHT",-26,-346)
        window.result=k.label(window,12,C.peach);window.result:SetPoint("TOPLEFT",26,-415);window.result:SetPoint("TOPRIGHT",-26,-415)
        window.verify=k.Button(window,"installVerify",170,"primary",A.VerifyInstallation);window.verify:SetPoint("BOTTOMLEFT",26,24)
        window.reload=k.Button(window,"installReload",180,"ghost",function()
            if A.Call(InCombatLockdown)==true then A.Print(A.L("markPlatesCombat"));return end
            A.Call(ReloadUI)
        end);window.reload:SetPoint("LEFT",window.verify,"RIGHT",10,0)
        window.next=k.Button(window,"installContinue",140,"ghost",function()
            if not A.VerifyInstallation() then return end
            window:Hide()
            if A.OpenOnboarding then A.OpenOnboarding() else A.OpenUI() end
        end);window.next:SetPoint("BOTTOMRIGHT",-26,24)
        window.close=k.Button(window,nil,28,"ghost",function() window:Hide() end);window.close.text:SetText("x");window.close:SetPoint("TOPRIGHT",-14,-14)
        window.languages={}
        for i,lang in ipairs({"en","cs"}) do
            local choice=lang
            local b=k.Button(window,nil,32,"ghost",function() A.SetLanguage(choice);window.Refresh() end)
            b.text:SetText(lang:upper());b:SetHeight(24);b:SetPoint("TOPRIGHT",-58-(i-1)*38,-18)
            window.languages[#window.languages+1]=b
        end
        function window.Refresh()
            local status=A.RequirementsStatus()
            window.title:SetText(A.L("installTitle"));window.subtitle:SetText(A.L("installSubtitle"));window.help:SetText(A.L("installHelp"))
            for which,row in pairs(window.rows) do
                local installed=status[which]
                row.title:SetText(A.L("install_"..which));row.body:SetText(A.L("installBody_"..which))
                row.open.text:SetText(A.L(row.open.localeKey))
                row.status:SetText(A.L(installed and "installPresent" or "installMissing"));row.status:SetTextColor(unpack(installed and C.green or C.peach))
            end
            for _,b in ipairs({window.verify,window.reload,window.next}) do b.text:SetText(A.L(b.localeKey)) end
            window.next:SetEnabled(status.ready);window.next:SetAlpha(status.ready and 1 or 0.45)
            window.result:SetText(lastCheck and A.L(lastCheck.ready and "installSuccess" or "installFailed") or "")
        end
        if type(UISpecialFrames)=="table" then UISpecialFrames[#UISpecialFrames+1]="EvertallyInstallation" end
    end
    window.Refresh();window:Show()
end
function A.RequirementsMaybe()
    if not A.db or A.RequirementsReady() then return end
    if A.Call(InCombatLockdown)==true then return end
    A.ShowRequirements()
end
A.On("PLAYER_REGEN_ENABLED",A.RequirementsMaybe)
local labels={
    installTitle={"Complete your installation","Dokonči instalaci"},
    installSubtitle={"Evertally requires OpenMap and the Evertally app for Windows. Verify both before continuing.","Evertally vyžaduje OpenMap a aplikaci Evertally pro Windows. Než budeš pokračovat, ověř obě instalace."},
    install_bridge={"1. Evertally app for Windows","1. Aplikace Evertally pro Windows"},install_openmap={"2. OpenMap add-on","2. Addon OpenMap"},
    installBody_bridge={"Install and start Bridge 0.9.9 or newer for this WoW folder. Pairing and web sharing remain optional.","Nainstaluj a spusť most 0.9.9 nebo novější pro tuto složku WoW. Párování a sdílení na web zůstávají volitelné."},
    installBody_openmap={"Install OpenMap for WoW Forever and enable it in the add-on list.","Nainstaluj OpenMap pro WoW Forever a zapni ho v seznamu addonů."},
    installHelp={"Use the download buttons above. The app writes an installation receipt; after starting it, reload the interface to load the receipt. Restart WoW fully after adding OpenMap or new add-on files. Pairing is not required for verification.","Použij tlačítka pro stažení nahoře. Aplikace vytvoří potvrzení instalace; po jejím spuštění načti znovu rozhraní. Po přidání OpenMap nebo nových souborů addonu WoW úplně restartuj. Pro ověření nepotřebuješ párování."},
    installOpen_bridge={"Download app","Stáhnout aplikaci"},installOpen_openmap={"Get OpenMap","Získat OpenMap"},
    installLinkHelp={"WoW cannot open the browser directly. Press Ctrl+C, paste into your browser and press Enter.","WoW neumí přímo otevřít prohlížeč. Stiskni Ctrl+C, vlož do prohlížeče a potvrď Enterem."},
    installLinkClose={"Done","Hotovo"},
    installPresent={"Verified","Ověřeno"},installMissing={"Not verified","Neověřeno"},
    installVerify={"Verify installation","Ověřit instalaci"},installReload={"Reload interface","Znovu načíst rozhraní"},installContinue={"Continue","Pokračovat"},
    installSuccess={"Both requirements are verified. You can continue.","Obě požadované instalace jsou ověřené. Můžeš pokračovat."},
    installFailed={"A requirement is still missing. Install it, reload and verify again.","Některá instalace stále chybí. Nainstaluj ji, načti rozhraní a ověř znovu."},
    navErr_dependencies_required={"Complete the required installation first.","Nejdřív dokonči požadované instalace."},
}
for key,value in pairs(labels) do A.locale.en[key]=value[1];A.locale.cs[key]=value[2] end
