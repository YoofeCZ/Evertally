local _,A=...
local GROUPS={"names","icons","auras","bars","position"}

-- Live editor shared by Settings and onboarding. Its preview stays above the
-- independently scrolling controls and uses FriendlyPlates' world renderer.
function A.BuildFriendlyPlateControls(parent,options)
    options=options or {}
    local k=A.UIKit()
    local editor=CreateFrame("Frame",nil,parent)
    A.NativePanel(editor,k.C)
    editor.controls,editor.tabs,editor.groups,editor.providers={},{},{},{}
    editor.group="names";editor.choosing=options.chooseFirst==true
    local function active() return A.db.settings.plateGameLook~=false and A.FriendlyPlatesShown() end
    local function changed()
        if options.changed then options.changed() end
        editor.Update()
    end
    editor.choice=CreateFrame("Frame",nil,editor);editor.choice:SetAllPoints()
    editor.choiceHint=k.label(editor.choice,13,k.C.mist)
    editor.choiceHint:SetPoint("TOPLEFT",12,-10);editor.choiceHint:SetPoint("TOPRIGHT",-12,-10)
    local choices=k.Columns(editor.choice,{1,1},12)
    choices:SetPoint("TOPLEFT",12,-60);choices:SetPoint("TOPRIGHT",-12,-60);choices:SetHeight(176)
    for i,provider in ipairs({"evertally","blizzard"}) do
        local mode=provider
        local b=k.Option(choices.cells[i],function()
            if A.UseFriendlyPlateProvider(mode) then editor.choosing=mode~="evertally";changed() end
        end,176)
        b:SetAllPoints(choices.cells[i]);b.title:SetWordWrap(true)
        b.sub:ClearAllPoints();b.sub:SetPoint("TOPLEFT",14,-60);b.sub:SetPoint("TOPRIGHT",-14,-60)
        b.sample=k.label(b,18,k.C.sky);b.sample:SetPoint("BOTTOMLEFT",14,24);b.sample:SetPoint("BOTTOMRIGHT",-36,24);b.sample:SetWordWrap(false)
        b.icon=b:CreateTexture(nil,"OVERLAY");b.icon:SetSize(16,16);b.icon:SetPoint("BOTTOMRIGHT",-14,24)
        b.icon:SetTexture("Interface\\AddOns\\Evertally\\Media\\Logo");b.icon:SetShown(mode=="evertally")
        editor.providers[mode]=b
    end
    editor.config=CreateFrame("Frame",nil,editor);editor.config:SetAllPoints()
    editor.mode=k.label(editor.config,13,k.C.bright);editor.mode:SetPoint("TOPLEFT",12,-10)
    editor.change=k.Button(editor.config,nil,105,"ghost",function() editor.choosing=true;editor.Update() end)
    editor.change:SetPoint("TOPRIGHT",-8,-6);editor.change:SetHeight(26)
    editor.previewBox=CreateFrame("ScrollFrame",nil,editor.config)
    editor.previewBox:SetPoint("TOPLEFT",8,-40);editor.previewBox:SetPoint("TOPRIGHT",-8,-40);editor.previewBox:SetHeight(94)
    A.NativeParchment(editor.previewBox,k.C)
    local stage=CreateFrame("Frame",nil,editor.previewBox);stage:SetHeight(94)
    editor.previewBox:SetScrollChild(stage)
    editor.preview=A.CreateFriendlyPlatePreview(stage)
    editor.previewLabel=k.label(editor.config,11,k.C.mist)
    editor.previewLabel:SetPoint("TOPLEFT",12,-140);editor.previewLabel:SetPoint("TOPRIGHT",-12,-140)
    local tabs=k.Columns(editor.config,{1,1,1,1,1},4)
    tabs:SetPoint("TOPLEFT",8,-160);tabs:SetPoint("TOPRIGHT",-8,-160);tabs:SetHeight(32)
    editor.scroll=k.ScrollArea(editor.config,4)
    editor.scroll:ClearAllPoints();editor.scroll:SetPoint("TOPLEFT",8,-200);editor.scroll:SetPoint("BOTTOMRIGHT",-10,8)
    for i,group in ipairs(GROUPS) do
        local id=group
        local panel=CreateFrame("Frame",nil,editor.scroll.child);panel:SetPoint("TOPLEFT");panel:SetPoint("TOPRIGHT")
        editor.groups[id]={frame=panel,rows={}}
        local button=k.Button(tabs.cells[i],nil,80,"ghost",function()
            editor.group=id;editor.scroll:SetVerticalScroll(0);editor.Update()
        end)
        button:ClearAllPoints();button:SetAllPoints(tabs.cells[i]);button.text:SetWordWrap(true);button.text:SetFont(k.fontPath(),11,"")
        editor.tabs[id]=button
    end
    for _,definition in ipairs(A.FriendlyPlateOptions) do
        local option=definition
        local group=editor.groups[option.group]
        local row
        if option.min or option.values then
            row=CreateFrame("Frame",nil,group.frame)
            row.title=k.label(row,12,k.C.text);row.title:SetPoint("LEFT",10,0);row.title:SetPoint("RIGHT",-146,0);row.title:SetWordWrap(true)
            row.value=k.label(row,12,k.C.bright);row.value:SetPoint("RIGHT",-30,0);row.value:SetWidth(82);row.value:SetJustifyH("CENTER");row.value:SetWordWrap(true)
            local function change(delta)
                local current=A.FriendlyPlateChoices()[option.key]
                if option.values then
                    local index=1;for i,value in ipairs(option.values) do if value==current then index=i end end
                    current=option.values[(index-1+delta)%#option.values+1]
                else current=math.max(option.min,math.min(option.max,current+delta*option.step)) end
                A.SetFriendlyPlateOption(option.key,current);changed()
            end
            row.minus=k.Button(row,nil,26,"ghost",function() change(-1) end);row.minus:SetPoint("RIGHT",-116,0);row.minus:SetHeight(28);row.minus.text:SetText("−")
            row.plus=k.Button(row,nil,26,"ghost",function() change(1) end);row.plus:SetPoint("RIGHT",-2,0);row.plus:SetHeight(28);row.plus.text:SetText("+")
            row.Update=function()
                row.title:SetText(A.L(option.key))
                local value=A.FriendlyPlateChoices()[option.key]
                row.value:SetText(option.values and A.L("plateValue_"..value) or tostring(value))
            end
        else
            row=k.Switch(group.frame,function(on) A.SetFriendlyPlateOption(option.key,on);changed() end,44)
            row.title:SetWordWrap(true)
            row.Update=function() row.SetTexts(A.L(option.key));row.Set(A.FriendlyPlateChoices()[option.key],true) end
        end
        if not row.bg then A.NativePanel(row,k.C) end
        row:SetHeight(44);group.rows[#group.rows+1]=row;editor.controls[option.key]=row
        -- the font's own choices count only in the Custom style ("Like the game" copies the game's name)
        if option.key=="plateFont" or option.key=="plateFontSize" or option.key=="plateOutline" or option.key=="plateShadow" then
            local base=row.Update
            row.Update=function() base();row:SetAlpha(A.FriendlyPlateChoices().plateStyle=="custom" and 1 or 0.45) end
        end
    end
    function editor.Layout()
        local width=editor:GetWidth() or 0
        stage:SetWidth(math.max(1,width-16))
        local columns=width>=640 and 2 or 1
        local cell=math.max(1,(width-20-(columns-1)*10)/columns)
        for id,group in pairs(editor.groups) do
            group.frame:SetShown(editor.group==id)
            for i,row in ipairs(group.rows) do
                row:ClearAllPoints();row:SetPoint("TOPLEFT",((i-1)%columns)*(cell+10),-math.floor((i-1)/columns)*48);row:SetWidth(cell)
            end
            group.frame:SetHeight(math.ceil(#group.rows/columns)*48)
            if id==editor.group then editor.scroll.child:SetHeight(group.frame:GetHeight()) end
        end
        editor.scroll.UpdateThumb()
    end
    function editor.Update()
        local on=active()
        if not on then editor.choosing=true end
        editor.choice:SetShown(editor.choosing);editor.config:SetShown(not editor.choosing)
        editor.choiceHint:SetText(A.L("plateChooseHelp"))
        local name=A.UnitPlayerName("player") or "Evertally"
        for id,b in pairs(editor.providers) do
            b.SetTexts(A.L("plateProvider_"..id),A.L("plateProviderSub_"..id));b.Set(on==(id=="evertally"))
            b.sample:SetText(name)
        end
        editor.mode:SetText(A.L("plateProvider_evertally"));editor.change.text:SetText(A.L("plateChangeProvider"))
        editor.previewLabel:SetText(A.L("platePreview"))
        for id,b in pairs(editor.tabs) do b.text:SetText(A.L("plateTab_"..id));b.text:SetTextColor(unpack(id==editor.group and k.C.gold or k.C.text)) end
        for _,control in pairs(editor.controls) do control.Update() end
        editor.Layout();editor.preview.Update()
    end
    editor:SetScript("OnSizeChanged",function() editor.Layout();editor.preview.Update() end)
    return editor
end
