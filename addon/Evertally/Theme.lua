local _, A = ...
-- Shared visual contract for every Evertally window. All artwork is built from
-- opaque primitives, so the appearance does not depend on another addon's skin.
local T = {id = "navy-gold", colors = {
    canvas={0.024,0.075,0.122},header={0.039,0.125,0.188},side={0.027,0.090,0.145},
    card={0.051,0.141,0.200},well={0.031,0.106,0.157},line={0.400,0.325,0.184,0.75},
    text={0.910,0.894,0.847},mist={0.604,0.671,0.686},faint={0.44,0.53,0.58},
    gold={0.796,0.651,0.373},bright={0.945,0.847,0.604},lilac={0.796,0.651,0.373},
    violet={0.34,0.25,0.11},green={0.38,0.80,0.56},peach={0.94,0.68,0.36},
    red={0.89,0.35,0.35},off={0.14,0.23,0.29},sky={0.42,0.72,0.91},
    silver={0.76,0.81,0.83},bronze={0.72,0.47,0.27},
}, metrics={width=1120,height=740,header=64,sidebar=224,navRow=34,body=13,title=24}}
A.Theme = T
T.reader = {ink=T.colors.text,mutedInk=T.colors.mist,heading=T.colors.bright}

local function paint(tex,c,alpha)
    if tex.SetColorTexture then tex:SetColorTexture(c[1],c[2],c[3],alpha or c[4] or 1)
    else tex:SetTexture("Interface\\Buttons\\WHITE8X8");tex:SetVertexColor(c[1],c[2],c[3],alpha or c[4] or 1) end
end
local function gradient(tex,top,bottom)
    if type(CreateColor)=="function" and type(tex.SetGradient)=="function" then
        if pcall(tex.SetGradient,tex,"VERTICAL",CreateColor(bottom[1],bottom[2],bottom[3],1),CreateColor(top[1],top[2],top[3],1)) then return end
    end
    if type(tex.SetGradientAlpha)=="function" and pcall(tex.SetGradientAlpha,tex,"VERTICAL",bottom[1],bottom[2],bottom[3],1,top[1],top[2],top[3],1) then return end
    paint(tex,bottom)
end
local function line(parent,pointA,pointB,c,size,inset,alpha)
    local tex=parent:CreateTexture(nil,"BORDER")
    local a=pointA:find("LEFT") and inset or -inset
    local b=pointB:find("LEFT") and inset or -inset
    local ay=pointA:find("TOP") and -inset or inset
    local by=pointB:find("TOP") and -inset or inset
    tex:SetPoint(pointA,parent,pointA,a,ay);tex:SetPoint(pointB,parent,pointB,b,by)
    if pointA:find("TOP") and pointB:find("BOTTOM") then tex:SetWidth(size) else tex:SetHeight(size) end
    paint(tex,c,alpha)
    return tex
end

function T.Surface(frame,role)
    if frame.evertallySkin then return frame.evertallySkin end
    local C=T.colors
    local fill=role=="window" and C.canvas or role=="reader" and C.well or C.card
    local skin={role=role,lines={}}
    frame.evertallySkin=skin
    -- The native backdrop remains a fallback for clients without color textures.
    if type(frame.SetBackdrop)~="function" and type(BackdropTemplateMixin)=="table" and type(Mixin)=="function" then pcall(Mixin,frame,BackdropTemplateMixin) end
    if type(frame.SetBackdrop)=="function" then
        pcall(frame.SetBackdrop,frame,{bgFile="Interface\\Buttons\\WHITE8X8",tile=false,insets={left=0,right=0,top=0,bottom=0}})
        if type(frame.SetBackdropColor)=="function" then pcall(frame.SetBackdropColor,frame,fill[1],fill[2],fill[3],1) end
    end
    skin.base=frame:CreateTexture(nil,"BACKGROUND");skin.base:SetAllPoints(frame);paint(skin.base,fill,1)
    skin.top=frame:CreateTexture(nil,"BACKGROUND");skin.top:SetPoint("TOPLEFT",1,-1);skin.top:SetPoint("TOPRIGHT",-1,-1);skin.top:SetHeight(role=="window" and 70 or 28)
    gradient(skin.top,role=="window" and C.header or C.card,fill)
    local outer=role=="window" and C.gold or C.line
    for _,p in ipairs({{"TOPLEFT","TOPRIGHT"},{"BOTTOMLEFT","BOTTOMRIGHT"},{"TOPLEFT","BOTTOMLEFT"},{"TOPRIGHT","BOTTOMRIGHT"}}) do
        skin.lines[#skin.lines+1]=line(frame,p[1],p[2],outer,1,0,role=="window" and 1 or 0.75)
    end
    skin.lines[#skin.lines+1]=line(frame,"TOPLEFT","TOPRIGHT",C.bright,1,2,role=="window" and 0.45 or 0.10)
    if role=="window" then
        skin.lines[#skin.lines+1]=line(frame,"BOTTOMLEFT","BOTTOMRIGHT",C.gold,1,3,0.38)
        skin.corners={}
        for _,corner in ipairs({"TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT"}) do
            local x=corner:find("LEFT") and 3 or -3;local y=corner:find("TOP") and -3 or 3
            local jewel=frame:CreateTexture(nil,"OVERLAY");jewel:SetSize(7,7);jewel:SetPoint("CENTER",frame,corner,x,y);paint(jewel,C.gold,1)
            if type(jewel.SetRotation)=="function" then pcall(jewel.SetRotation,jewel,math.pi/4) end
            local core=frame:CreateTexture(nil,"OVERLAY");core:SetSize(3,3);core:SetPoint("CENTER",jewel,"CENTER");paint(core,C.bright,1)
            skin.corners[#skin.corners+1]={jewel,core}
        end
    end
    return skin
end

function T.Button(button,primary)
    local C=T.colors;local skin=T.Surface(button,primary and "primary" or "button")
    if primary then gradient(skin.base,{0.43,0.31,0.13},{0.23,0.16,0.065})
    else gradient(skin.base,{0.075,0.19,0.26},{0.035,0.10,0.15}) end
    skin.top:Hide()
    return skin.base
end
