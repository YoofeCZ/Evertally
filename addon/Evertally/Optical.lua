local _, A = ...
-- Own live location for the Windows bridge: at most 128 x 6 physical pixels at the very top-left
-- corner of the game window, in four shades between black and 19 % grey. The bridge reads exactly those pixels (nothing is
-- saved, no game memory is read, no input is sent). Nothing is drawn unless the player switched "Live position on the website"
-- on. Four calibration pixels precede the variable-length version 4 packet. Own friend/group tokens travel in the same packet,
-- so roster changes and revocations need no SavedVariables write or reload.
-- Fields: version, scopes, epoch:u16, since:u32, time:u32, map:u16, x:u24, y:u24, GUID-key:u32, roster-key:u32,
-- token-count:u8, tokens:{kind:u8,key:u32}, Fletcher16. At most 100 contacts; 31..531 bytes.
local LEVELS={0,16,32,48}
local VERSION=4
local COLS=128
local frame,cells=nil,{}

local function adler(text)
    local a,b=1,0
    for i=1,#text do a=(a+text:byte(i))%65521;b=(b+a)%65521 end
    return b*65536+a
end
function A.OpticalKey(guid) return adler(guid) end

local function put(bytes,at,value,count)
    for i=count,1,-1 do bytes[at+i-1]=value%256;value=math.floor(value/256) end
end
local function fletcher(bytes,count)
    local c0,c1=0,0
    for i=1,count do c0=(c0+bytes[i])%255;c1=(c1+c0)%255 end
    return c1*256+c0
end

--- The sample to show, or nil: only with the live-position switch and the web consents on, and only with a known position.
function A.OpticalPacket()
    if A.RequirementsReady and not A.RequirementsReady() then return nil end
    local s=A.db and A.db.settings
    -- drawn on the player's screen, so its own opt-in (off by default), on top of the web consents
    if not s or s.liveWeb ~= true or not s.web or not s.scopes.own_track or not s.scopes.own_character then return nil end
    local map,x,y=A.PlayerPosition();local c=A.Character()
    if not map or not x or not y or not c or not c.id then return nil end
    local bits=0
    for i,k in ipairs({"world_facts","own_runs","own_character","own_professions","own_track","guild_share"}) do if s.scopes[k] then bits=bits+2^(i-1) end end
    local roster=A.ConnectionsTokensSnapshot and A.ConnectionsTokensSnapshot()
    return {b=bits,e=(s.consentEpoch or 0)%65536,s=s.since or 0,t=A.Now(),m=map,
        x=math.floor(x*100000+0.5),y=math.floor(y*100000+0.5),key=adler(c.id),r=roster and roster.key or 1,tokens=roster and roster.tokens or {}}
end
--- The variable-length bytes of a sample (1-based table), or nil when a value does not fit.
function A.OpticalBytes(p)
    if type(p)~="table" then return nil end
    local function fits(v,max) return type(v)=="number" and v>=0 and v<=max and v==math.floor(v) end
    if not (fits(p.b,63) and fits(p.e,65535) and fits(p.s,4294967295) and fits(p.t,4294967295) and fits(p.m,65535)
        and fits(p.x,100000) and fits(p.y,100000) and fits(p.key,4294967295) and fits(p.r or 1,4294967295)) then return nil end
    local bytes={VERSION,p.b}
    put(bytes,3,p.e,2);put(bytes,5,p.s,4);put(bytes,9,p.t,4);put(bytes,13,p.m,2)
    put(bytes,15,p.x,3);put(bytes,18,p.y,3);put(bytes,21,p.key,4)
    local tokens=p.tokens or {};if type(tokens)~="table" or #tokens>100 then return nil end
    put(bytes,25,p.r or 1,4);bytes[29]=#tokens
    for i,token in ipairs(tokens) do
        if type(token)~="table" or not fits(token.key,4294967295) or (token.kind~="friend" and token.kind~="group") then return nil end
        local at=30+(i-1)*5;bytes[at]=token.kind=="group" and 1 or 0;put(bytes,at+1,token.key,4)
    end
    local count=29+#tokens*5;put(bytes,count+1,fletcher(bytes,count),2)
    return bytes
end
--- 6-bit symbols of the bytes (40 for 30 bytes).
function A.OpticalSymbols(bytes)
    if type(bytes)~="table" or #bytes<31 or #bytes>531 then return nil end
    local out,acc,bits={},0,0
    for i=1,#bytes do
        acc=acc*256+bytes[i];bits=bits+8
        while bits>=6 do bits=bits-6;out[#out+1]=math.floor(acc/2^bits)%64 end
        acc=acc%2^bits
    end
    if bits>0 then out[#out+1]=acc*2^(6-bits) end
    return out
end
--- The channel values (0..255) of every pixel, ramp first: {{r,g,b},...}. This is what the bridge reads back.
function A.OpticalPixels(p)
    local symbols=A.OpticalSymbols(A.OpticalBytes(p))
    if not symbols then return nil end
    local out={}
    for k=1,#LEVELS do out[#out+1]={LEVELS[k],LEVELS[k],LEVELS[k]} end
    for _,symbol in ipairs(symbols) do
        out[#out+1]={LEVELS[math.floor(symbol/16)+1],LEVELS[math.floor(symbol/4)%4+1],LEVELS[symbol%4+1]}
    end
    return out
end

-- Physical height of the game's render area in pixels. The bridge reads real screen pixels, so one UI unit of the marker has
-- to be exactly one pixel: 1 pixel = (768 / physical height) / UIParent scale UI units. (Dividing by the UI scale alone gave
-- 1.41 pixels per unit at 1080p: measured on screen, 4.2 px cells instead of 3.)
local function physicalHeight()
    if type(GetPhysicalScreenSize)=="function" then
        local ok,_,h=pcall(GetPhysicalScreenSize)
        if ok and type(h)=="number" and h>0 then return h end
    end
    if type(GetCVar)=="function" then
        local ok,res=pcall(GetCVar,"gxWindowedResolution")
        local h=ok and type(res)=="string" and tonumber(res:match("%d+x(%d+)"))
        if h and h>0 then return h end
    end
    return 768
end
function A.OpticalClear() if frame then frame:Hide() end end
function A.OpticalTick()
    local packet=A.OpticalPacket();local pixels=packet and A.OpticalPixels(packet)
    if not pixels then if frame then frame:Hide() end;return end
    if not frame then
        frame=CreateFrame("Frame","EvertallyLiveBridgeStrip",UIParent)
        frame:SetFrameStrata("TOOLTIP");frame:SetFrameLevel(999);frame:EnableMouse(false)
        frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",0,0)
    end
    local scale=UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    frame:SetScale((768/physicalHeight())/scale);frame:SetSize(math.min(COLS,#pixels),math.ceil(#pixels/COLS))
    for i,c in ipairs(pixels) do
        local t=cells[i]
        if not t then t=frame:CreateTexture(nil,"OVERLAY");cells[i]=t;t:SetSize(1,1);t:SetPoint("TOPLEFT",(i-1)%COLS,-math.floor((i-1)/COLS)) end
        t:SetColorTexture(c[1]/255,c[2]/255,c[3]/255,1);t:Show()
    end
    for i=#pixels+1,#cells do cells[i]:Hide() end
    frame:Show()
end
A.On("PLAYER_LOGIN",function() if C_Timer and C_Timer.After then C_Timer.After(2,A.OpticalTick) end end)
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2,function() local ok=pcall(A.OpticalTick);if not ok then A.errors.optical=(A.errors.optical or 0)+1;if frame then frame:Hide() end end end) end
