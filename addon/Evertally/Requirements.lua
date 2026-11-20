local _,A=...
local lastCheck,offered
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
        linkWindow:SetSize(650,236);linkWindow:SetPoint("CENTER");linkWindow:SetFrameStrata("FULLSCREEN_DIALOG")
        linkWindow:SetClampedToScreen(true);linkWindow:EnableMouse(true);A.NativeFrame(linkWindow,C)
        linkWindow.title=k.label(linkWindow,20,C.bright);linkWindow.title:SetPoint("TOPLEFT",24,-22)
        local divider=linkWindow:CreateTexture(nil,"BORDER");divider:SetHeight(1);divider:SetPoint("TOPLEFT",24,-56);divider:SetPoint("TOPRIGHT",-24,-56);k.paint(divider,C.line)
        linkWindow.help=k.label(linkWindow,13,C.mist);linkWindow.help:SetPoint("TOPLEFT",24,-70);linkWindow.help:SetPoint("TOPRIGHT",-24,-70)
        linkWindow.address=k.LinkBox(linkWindow);linkWindow.address:SetPoint("TOPLEFT",24,-123);linkWindow.address:SetPoint("TOPRIGHT",-24,-123)
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
    -- Once is enough: the receipt is a file inside the add-on, which every update of the add-on (CurseForge, a copy)
    -- puts back empty, and the app writes it again only while it runs. A receipt seen once is kept for the account, so
    -- the player is not asked to start the app again after an update or with the app closed.
    local db=A.db
    if bridge and db then db.bridgeVerified={bridgeVersion=A.Field(receipt,"bridgeVersion"),at=at}
    elseif not bridge and db and type(db.bridgeVerified)=="table" then
        local kept=version(db.bridgeVerified.bridgeVersion)
        if kept and kept>=version(A.BRIDGE_MINIMUM) then bridge=true;v=kept;receipt=db.bridgeVerified end
    end
    local openmap=A.OpenMapInstalled and A.OpenMapInstalled()==true or false
    -- 2026-11-20: neither is required any more (ready is always true); `complete` says whether the online part works
    return {bridge=bridge==true,openmap=openmap,ready=true,complete=bridge==true and openmap,bridgeVersion=v and A.Field(receipt,"bridgeVersion") or nil}
end
--- The add-on runs without the app and without OpenMap: always true (kept for the callers that asked).
function A.RequirementsReady() return true end
--- Whether the app and OpenMap are both there: without them the online part is missing (A.L("installLimited")).
function A.RequirementsComplete() return A.RequirementsStatus().complete end
--- What is missing, for the warning: "bridge", "openmap", both or none (a list).
function A.RequirementsMissing()
    local s,out=A.RequirementsStatus(),{}
    if not s.bridge then out[#out+1]="bridge" end
    if not s.openmap then out[#out+1]="openmap" end
    return out
end
function A.VerifyInstallation()
    lastCheck=A.RequirementsStatus()
    if A.RefreshOnboarding then A.RefreshOnboarding() end
    return lastCheck.complete,lastCheck
end
function A.RequirementsGuard() return true end
function A.ShowRequirements()
    if A.OpenOnboarding then A.OpenOnboarding(A.ONBOARDING_INSTALL_STEP or 2) end
end
-- Installation is content of the first setup page, never another top-level window.
function A.BuildInstallationControls(parent)
    local k=A.UIKit();local C=k.C
    local panel=CreateFrame("Frame",nil,parent);panel.rows={}
    A.installationPage=panel
    for i,which in ipairs({"bridge","openmap"}) do
        local top=(i-1)*112
        local row={}
        row.card=CreateFrame("Frame",nil,panel);row.card:SetPoint("TOPLEFT",0,-top);row.card:SetPoint("TOPRIGHT",0,-top);row.card:SetHeight(102);A.NativePanel(row.card,C)
        row.title=k.label(row.card,14,C.bright);row.title:SetPoint("TOPLEFT",14,-12);row.title:SetPoint("TOPRIGHT",-110,-12)
        row.status=k.label(row.card,11,C.mist);row.status:SetPoint("TOPRIGHT",-14,-14);row.status:SetJustifyH("RIGHT")
        row.body=k.label(row.card,12,C.mist);row.body:SetPoint("TOPLEFT",14,-35);row.body:SetPoint("TOPRIGHT",-14,-35)
        local destination=which
        row.open=k.Button(row.card,"installOpen_"..which,210,"ghost",function() A.OpenInstallationLink(destination) end)
        row.open:SetPoint("TOPLEFT",14,-62)
        panel.rows[which]=row
    end
    panel.help=k.label(panel,12,C.mist);panel.help:SetPoint("TOPLEFT",2,-232);panel.help:SetPoint("TOPRIGHT",-2,-232)
    panel.verify=k.Button(panel,"installVerify",170,"primary",A.VerifyInstallation);panel.verify:SetPoint("TOPLEFT",0,-292)
    panel.reload=k.Button(panel,"installReload",180,"ghost",function()
        if A.Call(InCombatLockdown)==true then A.Print(A.L("markPlatesCombat"));return end
        A.Call(ReloadUI)
    end);panel.reload:SetPoint("LEFT",panel.verify,"RIGHT",10,0)
    panel.result=k.label(panel,12,C.peach);panel.result:SetPoint("TOPLEFT",0,-334);panel.result:SetPoint("TOPRIGHT",0,-334)
    function panel.Update()
        local status=A.RequirementsStatus()
        for which,row in pairs(panel.rows) do
            row.title:SetText(A.L("install_"..which));row.body:SetText(A.L("installBody_"..which));row.open.text:SetText(A.L(row.open.localeKey))
            row.status:SetText(A.L(status[which] and "installPresent" or "installMissing"));row.status:SetTextColor(unpack(status[which] and C.green or C.peach))
        end
        panel.help:SetText(A.L("installHelp"));panel.verify.text:SetText(A.L("installVerify"));panel.reload.text:SetText(A.L("installReload"))
        -- without the app or OpenMap: what the player goes without, every time (not only after Verify)
        local text=status.complete and (lastCheck and A.L("installSuccess") or "") or A.L("installLimited")
        panel.result:SetText(text);panel.result:SetTextColor(unpack(status.complete and C.green or C.peach))
    end
    return panel
end
function A.RequirementsMaybe()
    -- (nothing is required since 2026-11-20: the setup opens by itself as for anyone, OnboardingMaybe)
    do return end
    if offered or not A.db or A.RequirementsReady() then return end
    if A.Call(InCombatLockdown)==true then return end
    offered=true
    A.ShowRequirements()
end
A.On("PLAYER_REGEN_ENABLED",A.RequirementsMaybe)
local labels={
    installTitle={"Complete your installation","Dokonči instalaci"},
    installSubtitle={"Evertally works without them, but the Evertally app for Windows and OpenMap give you the whole of it.","Evertally funguje i bez nich, ale celý zážitek dá až aplikace Evertally pro Windows a OpenMap."},
    install_bridge={"1. Evertally app for Windows","1. Aplikace Evertally pro Windows"},install_openmap={"2. OpenMap add-on","2. Addon OpenMap"},
    installBody_bridge={"Install and start the Evertally app for this WoW folder. The next step pairs it with the website.","Nainstaluj a spusť aplikaci Evertally pro tuto složku WoW. V dalším kroku ji spáruješ s webem."},
    installBody_openmap={"Install OpenMap for WoW Forever and enable it in the add-on list.","Nainstaluj OpenMap pro WoW Forever a zapni ho v seznamu addonů."},
    installHelp={"Both are optional. Use the download buttons above. The app writes an installation receipt; after starting it, reload the interface to load the receipt. Restart WoW fully after adding OpenMap. Pairing follows in the next step.","Obojí je dobrovolné. Použij tlačítka pro stažení nahoře. Aplikace vytvoří potvrzení instalace; po jejím spuštění načti znovu rozhraní. Po přidání OpenMap WoW úplně restartuj. Párování následuje v dalším kroku."},
    installOpen_bridge={"Download app","Stáhnout aplikaci"},installOpen_openmap={"Get OpenMap","Získat OpenMap"},
    installLinkHelp={"WoW cannot open the browser directly. Press Ctrl+C, paste into your browser and press Enter.","WoW neumí přímo otevřít prohlížeč. Stiskni Ctrl+C, vlož do prohlížeče a potvrď Enterem."},
    installLinkClose={"Done","Hotovo"},
    installPresent={"Verified","Ověřeno"},installMissing={"Not verified","Neověřeno"},
    installVerify={"Verify installation","Ověřit instalaci"},installReload={"Reload interface","Znovu načíst rozhraní"},installContinue={"Continue","Pokračovat"},
    installSuccess={"Both are installed: you have all of Evertally.","Obojí je nainstalované: máš celý Evertally."},
    installFailed={"Something is still missing. You can continue, but without the online part.","Něco pořád chybí. Můžeš pokračovat, ale bez online části."},
    installLimited={"Without the Evertally app and OpenMap it is not the full experience: you will not see your party members in the game, you will have no personal chronicle on the website, you will not get onto the leaderboard and nothing else online works (the website, Armory, live position). Everything in the game itself works.","Bez aplikace Evertally a OpenMap to není plnohodnotný zážitek: neuvidíš spoluhráče ve hře, nebudeš mít osobní kroniku na webu, nezapíšeš se do žebříčku a nebude fungovat nic dalšího online (web, Armory, živá poloha). Všechno ve hře samotné funguje."},
    navErr_dependencies_required={"Complete the required installation first.","Nejdřív dokonči požadované instalace."},
}
for key,value in pairs(labels) do A.locale.en[key]=value[1];A.locale.cs[key]=value[2] end
