local _, M = ...
-- Navigation to a player, a meet, a ping or a point: an arrow under the minimap with the distance, and the journey in steps
-- (walk to a flight master, fly, take the boat ...) planned by Planner.lua from where you stand and replanned every few
-- seconds, so it follows you and a moving target. Nothing here touches Blizzard frames; the arrow is our own frame.
local A = _G.Evertally
local MEDIA = "Interface\\AddOns\\Evertally_Map\\Media\\"
local TICK, PLAN_EVERY, MOVED_TARGET, BOARD, ARRIVED = 0.25, 8, 200, 60, 35
local atan2 = math.atan2 or math.atan
local sqrt, pi = math.sqrt, math.pi

local N = {target = nil, plan = nil, planAt = 0, planTo = nil, shown = {}}
M.nav = N
local frame, ticker
local terrainText={
    en={navGround="Terrain path",navGroundRoads="Roads and passable terrain",navGroundFloor="Different floor · continue via stairs or lift",navGroundSnapped="Path · approximate endpoints",navGroundPending="Finding a passable path…",navGroundFailed="No passable path found here",navGroundDirect="Direction only · no terrain path available",navJourneyPending="Comparing walking routes and available transport…",navKnownFlights="Only flight points confirmed for this character are used. Open a flight master's map to update them."},
    cs={navGround="Cesta po terénu",navGroundRoads="Silnice a průchozí terén",navGroundFloor="Jiné patro · pokračuj po schodech nebo výtahem",navGroundSnapped="Cesta · přiblížené konce",navGroundPending="Hledám průchozí cestu…",navGroundFailed="Tady se nepodařilo najít průchozí cestu",navGroundDirect="Pouze směr · bez známé průchozí cesty",navJourneyPending="Porovnávám pěší cesty a dostupnou dopravu…",navKnownFlights="Používám jen letové body potvrzené pro tuto postavu. Aktualizují se otevřením mapy u letového mistra."},
}
for lang,entries in pairs(terrainText) do if A.locale and A.locale[lang] then for key,value in pairs(entries) do A.locale[lang][key]=value end end end
local function clearGround()
    if N.ground and M.Terrain then M.Terrain.Cancel(N.ground.job) end
    N.ground,N.groundStatus=nil,nil
end
local function dist(ax,ay,bx,by) local dx,dy=ax-bx,ay-by;return sqrt(dx*dx+dy*dy) end
local function segmentDistance(x,y,a,b)
    local dx,dy=b[1]-a[1],b[2]-a[2];local length=dx*dx+dy*dy
    local t=length>0 and math.max(0,math.min(1,((x-a[1])*dx+(y-a[2])*dy)/length)) or 0
    return dist(x,y,a[1]+t*dx,a[2]+t*dy)
end
-- The active walking leg, independent of the transport planner's next eight-second refresh.
-- A target move or deviation cancels the old coroutine before another job can replace it.
local function groundPointer(pc,px,py,qc,qx,qy,now)
    local T=M.Terrain
    if not T or pc~=qc then clearGround();N.groundStatus="direct";return qx,qy end
    -- No mask is a normal fallback, not a repeatedly retried search each frame.
    if not T.maps[pc] and not (T.RoadBacked and T.RoadBacked(pc)) then clearGround();N.groundStatus="direct";return qx,qy end
    local _,_,currentZ=A.Call(UnitPosition,"player")
    currentZ=A.Number(currentZ)
    local g=N.ground
    local cellSize=T.maps[pc] and T.maps[pc].cell or 8
    local changed=not g or g.map~=pc or dist(qx,qy,g.x,g.y)>cellSize*2
    if g and not changed then
        local result=g.job.result
        local deviation=g.job.provider=="roads" and 24 or 96
        local off=result and segmentDistance(px,py,result.points[math.max(1,g.index-1)],result.points[g.index])>deviation
        local moved=dist(px,py,g.startX,g.startY)>64
        if (off and now-g.at>=1) or (g.job.state~="ready" and moved and now-g.at>=6) then changed=true end
        -- A lift/stair/fall can change the current floor without changing XY.
        local expectedZ=g.startZ
        local a=result and result.points[math.max(1,g.index-1)]
        local b=result and result.points[g.index]
        if a and b and a[3] and b[3] then
            local dx,dy=b[1]-a[1],b[2]-a[2];local length=dx*dx+dy*dy
            local t=length>0 and math.max(0,math.min(1,((px-a[1])*dx+(py-a[2])*dy)/length)) or 0
            expectedZ=a[3]+t*(b[3]-a[3])
        end
        if g.job.provider=="roads" and currentZ and expectedZ and math.abs(currentZ-expectedZ)>10 and now-g.at>=1 then changed=true end
        if g.job.state=="failed" and now-g.at>=8 then changed=true end
    end
    if changed then
        clearGround()
        g={map=pc,x=qx,y=qy,startX=px,startY=py,startZ=currentZ,at=now,index=2,job=T.Begin(pc,px,py,qx,qy,{fromZ=currentZ,roads=true})};N.ground=g
    end
    T.Step(g.job)
    local result=g.job.result
    if g.job.state=="ready" and result then
        local points=result.points
        g.index=math.min(g.index,#points)
        local point=points[g.index]
        local reach=g.job.provider=="roads" and 2.5 or math.max(5,g.job.map.cell*0.6)
        local function sameFloor(p) return g.job.provider~="roads" or not currentZ or not p[3] or math.abs(currentZ-p[3])<=4 end
        while g.index<#points and dist(px,py,point[1],point[2])<=reach and sameFloor(point) do
            g.index=g.index+1;point=points[g.index]
        end
        N.groundStatus=result.snapped and "snapped" or g.job.provider=="roads" and "roads" or "terrain"
        if dist(px,py,point[1],point[2])<=reach and not sameFloor(point) then
            N.groundStatus="floor";return nil,nil,result.tails[g.index]
        end
        return point[1],point[2],dist(px,py,point[1],point[2])+(result.tails[g.index] or 0)
    end
    N.groundStatus=g.job.state=="pending" and "pending" or "direct"
    if g.job.provider=="roads" then
        if g.job.state~="pending" then N.groundStatus="failed" end
        return nil,nil -- a pending/failed collision search is never a straight walking route
    end
    return qx,qy
end
local function groundHint()
    return A.L(N.groundStatus=="floor" and "navGroundFloor" or N.groundStatus=="roads" and "navGroundRoads" or N.groundStatus=="terrain" and "navGround" or N.groundStatus=="snapped" and "navGroundSnapped" or N.groundStatus=="pending" and "navGroundPending" or N.groundStatus=="failed" and "navGroundFailed" or N.groundStatus=="direct" and "navGroundDirect" or "navHint")
end
local function groundPin()
    local g=N.ground
    if not g or not g.job.result or g.job.state~="ready" then return end
    local point=g.job.result.points[g.index];local c=M.data and M.data.yards[g.map]
    if point and c then N.shown[#N.shown+1]={id="terrain",u=c[1]+point[2]*c[2],v=c[3]+point[1]*c[4],title=A.L("navGround")} end
end

-- ---------------------------------------------------------------- small helpers
local function clock(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    if seconds >= 3600 then return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60) end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function yards(n) return string.format("%d yd", math.floor((n or 0) + 0.5)) end
local function normalize(angle) angle = angle % (2 * pi); if angle > pi then angle = angle - 2 * pi end; return angle end
M.Normalize = normalize

--- Angle (radians, counter-clockwise from north, like GetPlayerFacing) and distance in yards between two points in the
--- game's own yard frame (x north, y west); nil for points on different continents.
function M.Bearing(c1, x1, y1, c2, x2, y2)
    if c1 ~= c2 or not (A.Number(x1) and A.Number(y1) and A.Number(x2) and A.Number(y2)) then return nil end
    local dx, dy = x2 - x1, y2 - y1
    return atan2(dy, dx), sqrt(dx * dx + dy * dy)
end

--- Where the player stands: u, v (Azeroth's map), uiMapID, x, y; nil in instances, on ships and in unmapped places.
function M.PlayerPosition()
    local map, x, y = A.PlayerPosition()
    if not map or not x or not y then return nil end
    local u, v = M.ToUV(map, x, y)
    if not u then return nil end
    return u, v, map, x, y
end

--- Straight-line yards from the player to a position on a map, nil when unknown or on another continent.
function M.DistanceTo(mapId, x, y)
    local pu, pv = M.PlayerPosition()
    local tu, tv = M.ToUV(mapId, x, y)
    if not pu or not tu then return nil end
    local pc, px, py = M.ToYards(pu, pv)
    local tc, tx, ty = M.ToYards(tu, tv)
    local _, d = M.Bearing(pc, px, py, tc, tx, ty)
    return d
end

local function side() return A.Call(UnitFactionGroup, "player") == "Horde" and "H" or "A" end
local function speed() return A.Call(IsMounted) == true and 11.2 or 7 end

-- ---------------------------------------------------------------- the target
local function resolve(target)
    if target.kind == "player" then
        local peer = A.LivePeer and A.LivePeer(target.name)
        if peer then target.last = {map = peer.map, x = peer.x, y = peer.y, at = A.Now()}; return peer.map, peer.x, peer.y, peer.name, false end
        if target.last then return target.last.map, target.last.x, target.last.y, target.name, true end
        return nil
    end
    return target.map, target.x, target.y, target.label, false
end

local function modeName(mode) return A.L("navMode_" .. mode) end
local function stepText(step, pointerYards)
    local mode = step.mode
    if mode == "walk" then return string.format(A.L("navWalk"), step.to, pointerYards and yards(pointerYards) or clock(step.seconds)) end
    if mode == "flight" then return string.format(A.L("navFly"), step.from, step.to, clock(step.seconds)) end
    if mode == "boat" or mode == "zeppelin" or mode == "airship" then return string.format(A.L("navShip"), modeName(mode), step.from, step.to, clock(step.wait or 0)) end
    return string.format(A.L("navOther"), modeName(mode), step.from, step.to)
end
--- what the journey tab of the window uses: the text of a step, a time, and the planner options for this character
function M.StepText(step) return stepText(step) end
function M.Clock(seconds) return clock(seconds) end
function M.JourneyOptions()
    local known, revision
    if M.TravelKnowledge then known, revision = M.TravelKnowledge.Options() end
    local _,_,z=A.Call(UnitPosition,"player")
    return {side = side(), speed = speed(), knownTaxi = known or {}, taxiRevision = revision,fromZ=A.Number(z)}
end

-- ---------------------------------------------------------------- the tracker frame
local function fontPath() return A.FontPath and A.FontPath() or "Fonts\\FRIZQT__.TTF" end
-- Shortest Path Forever is the one installed addon that searches real terrain: QuestMaster hands its targets to
-- ShortestPathForever.API too and Questie reaches it through its TomTom stand-in. So the tracker offers it as a button.
local function terrainApi()
    local spf = rawget(_G, "ShortestPathForever")
    local api = type(spf) == "table" and spf.API
    if type(api) == "table" and type(api.Navigate) == "function" then return api end
    return nil
end
local function terrainActive(api)
    if not api or type(api.CurrentStop) ~= "function" then return false end
    local ok, stop = pcall(api.CurrentStop, "Evertally")
    return ok and stop ~= nil and stop ~= false
end

--- The colour of the arrow for the angle between where you face and where the goal is (radians, 0 = straight ahead): green while you
--- face it, through orange when it is off to the side, to red when it is behind you. Returns r, g, b.
local GREEN, ORANGE, RED = {0.25, 0.95, 0.35}, {1, 0.62, 0.12}, {0.95, 0.18, 0.15}
function M.ArrowColor(angle)
    local a = math.min(math.abs(tonumber(angle) or 0), pi)
    local t = math.max(0, (a - 0.25) / (pi - 0.25))     -- (the first 14 degrees count as facing it)
    local from, to, k = GREEN, ORANGE, t / 0.5
    if t >= 0.5 then from, to, k = ORANGE, RED, (t - 0.5) / 0.5 end
    return from[1] + (to[1] - from[1]) * k, from[2] + (to[2] - from[2]) * k, from[3] + (to[3] - from[3]) * k
end

local function outlined(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontPath(), size, "OUTLINE"); fs:SetTextColor(r, g, b, 1); fs:SetJustifyH("CENTER"); fs:SetWidth(236)
    return fs
end

local function ensureFrame()
    if frame then return frame end
    local kit=A.UIKit();local C=kit.C
    -- the arrow with the distance under it and the name of the goal under that, floating over the game (no panel): the arrow changes colour with
    -- how you are turned to the goal (M.ArrowColor), so a glance says whether you are heading the right way
    local f = CreateFrame("Frame", "EvertallyTracker", UIParent)
    -- the frame is the arrow itself (its centre is what is placed and scaled); the text hangs under it and counts as part of it for the mouse
    f:SetSize(58, 58); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
    f:SetHitRectInsets(-90, -90, 0, -100)
    if M.ArrowApplyLayout then M.ArrowApplyLayout(f)
    elseif Minimap then f:SetPoint("TOP", Minimap, "BOTTOM", 0, -26) else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
    f.arrow = f:CreateTexture(nil, "ARTWORK"); f.arrow:SetAllPoints(f)
    f.arrow:SetTexture(MEDIA .. "arrow"); f.arrow:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
    f.distance = outlined(f,20,unpack(C.text));f.distance:SetPoint("TOP",f.arrow,"BOTTOM",0,-6)
    f.title = outlined(f,13,unpack(C.bright));f.title:SetPoint("TOP",f.distance,"BOTTOM",0,-3)
    f.line1 = outlined(f,11,unpack(C.text));f.line1:SetPoint("TOP",f.title,"BOTTOM",0,-3)
    f.line2 = outlined(f,10,unpack(C.mist));f.line2:SetPoint("TOP",f.line1,"BOTTOM",0,-2)
    f.hint = outlined(f,9,unpack(C.mist));f.hint:SetPoint("TOP",f.line2,"BOTTOM",0,-2)
    -- terrain guidance by Shortest Path Forever; only visible when that addon is there (see show)
    local terrain = CreateFrame("Button", nil, f)
    terrain:SetSize(56,20);terrain:SetPoint("LEFT",f,"RIGHT",8,0)
    terrain.bg=A.NativeButton(terrain,C,false)
    terrain.label=kit.label(terrain,10,C.bright);terrain.label:SetPoint("CENTER",0,0);terrain.label:SetJustifyH("CENTER")
    terrain:SetScript("OnClick", function()
        local ok, reason = M.NavigateTerrain()
        A.Print(A.L(ok and "terrainStarted" or ("terrainErr_" .. tostring(reason))))
    end)
    terrain:Hide()
    f.terrain = terrain
    -- drag to move it; a left click opens what it leads to; a right click opens the menu (resize, hide, reset, stop: ArrowMenu.lua)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnMouseDown", function(self) self.moved = false end)
    f:SetScript("OnDragStart", function(self) self.moved = true; self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); if M.ArrowSavePosition then M.ArrowSavePosition(self) end end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then if M.ArrowMenuOpen then M.ArrowMenuOpen() end
        elseif button == "LeftButton" and not self.moved and M.OpenGoalInfo then M.OpenGoalInfo() end
    end)
    -- the corner that is dragged to change the size (shown by the menu's "Change size", gone when the button is let go)
    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetSize(22, 22); f.grip:SetPoint("CENTER", f, "CENTER", 30, -30); f.grip:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
    f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"); f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    f.grip:SetScript("OnMouseDown", function() f.resizing = true end)
    f.grip:SetScript("OnMouseUp", function() f.resizing = false; f.grip:Hide() end)
    f.grip:Hide()
    -- One bounded search slice per rendered frame; the 0.25s navigation tick also advances it.
    -- Hiding/stopping navigation releases the pending coroutine instead of doing background work.
    f:SetScript("OnUpdate",function(self, elapsed)
        if N.aim and N.target and M.ArrowLive then M.ArrowLive(elapsed) end
        if self.resizing and M.ArrowResizeStep then M.ArrowResizeStep(self) end
        if N.target and N.ground and M.Terrain and N.ground.job.state=="pending" then M.Terrain.Step(N.ground.job) end
    end)
    f:Hide()
    frame = f
    return f
end

--- Turns the arrow (rotation: radians off straight ahead, nil = no direction) and writes the distance under it.
local function setArrow(rotation, distanceYards)
    if not frame then return end
    frame.distance:SetText(type(distanceYards) == "number" and yards(distanceYards) or "")
    if rotation == nil then frame.arrow:Hide(); return end
    frame.arrow:Show()
    if frame.arrow.SetRotation then pcall(frame.arrow.SetRotation, frame.arrow, rotation) end
    frame.arrow:SetVertexColor(M.ArrowColor(rotation))
end
--- Between two ticks of the navigation the arrow keeps turning with you: the angle and the distance are worked out again every frame from where
--- you face now and from where you stand (read twenty times a second), so it turns smoothly, not in steps of the tick.
function M.ArrowLive(elapsed)
    local aim = N.aim
    if not aim or not frame then return end
    N.liveFor = (N.liveFor or 1) + (tonumber(elapsed) or 0)
    if N.liveFor >= 0.05 then
        N.liveFor = 0
        local u, v = M.PlayerPosition()
        if u then local c, x, y = M.ToYards(u, v); N.livePos = {c, x, y} else N.livePos = nil end
    end
    local at, facing = N.livePos, A.Call(GetPlayerFacing)
    if not at or not facing then return end
    local bearing, distance = M.Bearing(at[1], at[2], at[3], aim.c, aim.x, aim.y)
    if not bearing then return end
    setArrow(normalize(bearing - facing), distance + (aim.tail or 0))
end
local function show(title, line1, line2, hint)
    if not frame then return end
    frame.title:SetText(title or ""); frame.line1:SetText(line1 or ""); frame.line2:SetText(line2 or ""); frame.hint:SetText(hint or "")
    local api = terrainApi()
    frame.terrain:SetShown(api ~= nil)
    if api then frame.terrain.label:SetText(A.L(terrainActive(api) and "terrainOn" or "terrainButton")) end
end

-- ---------------------------------------------------------------- one update
local function replan(meU, meV, tu, tv, label)
    if N.journey and M.Journey then M.Journey.Cancel(N.journey) end
    -- A replacement search is not a new destination. Keep the last verified
    -- itinerary (and its walking path) until its replacement is ready.
    N.journey=nil
    local options=M.JourneyOptions()
    local from,to={u=meU,v=meV,label=A.L("navYou")},{u=tu,v=tv,label=label}
    if M.Journey and M.Journey.Available() then
        N.journey=M.Journey.Begin(from,to,options)
        M.Journey.Step(N.journey)
    else N.plan=M.PlanJourney(from,to,options) end
    N.planAt, N.planTo = A.Monotonic(), {tu, tv}
    N.planned = true
end

function N.Update()
    local target = N.target
    if not target then return end
    N.aim = nil   -- (set again below where there is a direction to give)
    local f = ensureFrame()
    local tm, tx, ty, label, stale = resolve(target)
    if not tm then clearGround();show(target.name or target.label or "?", A.L("navLost"), "", A.L("navHint")); setArrow(nil); N.shown = {}; return end
    local tu, tv = M.ToUV(tm, tx, ty)
    if not tu then clearGround();show(label, A.L("navNoMap"), "", A.L("navHint")); setArrow(nil); N.shown = {}; return end
    local meU, meV, meMap, meX, meY = M.PlayerPosition()
    local title = (stale and "? " or "") .. tostring(label or "?")
    if not meU then
        clearGround()
        -- on a ship, in an instance, between maps: keep what was shown, but say the position is unknown
        show(title, f.line1:GetText(), f.line2:GetText(), A.L("navNoPosition")); setArrow(nil); N.shown = {}; return
    end

    local now = A.Monotonic()
    local tc, tX, tY = M.ToYards(tu, tv)
    local pc, pX, pY = M.ToYards(meU, meV)
    local movedTarget = N.planTo and select(2, M.Bearing(tc, tX, tY, M.ToYards(N.planTo[1], N.planTo[2]))) or math.huge
    if N.journey and N.journey.state=="pending" and not N.force and movedTarget<=MOVED_TARGET then
        -- Exact walking searches continue under their shared frame budget.
    elseif not N.plan and N.planned and now - N.planAt < PLAN_EVERY and not N.force then
        -- no route is known: do not search again every tick
    elseif not N.planned or now - N.planAt >= PLAN_EVERY or (movedTarget or 0) > MOVED_TARGET or N.force then
        replan(meU, meV, tu, tv, label); N.force = false
    end

    if N.journey then
        M.Journey.Step(N.journey)
        if N.journey.state=="ready" and N.plan~=N.journey.plan then
            N.plan=N.journey.plan;N.planAt=now
        end
        if N.journey.state~="ready" and not N.plan then
            clearGround()
            show(title,A.L(N.journey.state=="pending" and "navJourneyPending" or "navNoRoute"),"",A.L("navKnownFlights"))
            setArrow(nil);N.shown={{id="goal",u=tu,v=tv,title=title}};return
        end
    end

    local plan = N.plan
    local _, direct = M.Bearing(pc, pX, pY, tc, tX, tY)
    -- A nearby goal can still be across a wall. Arrival must not discard a necessary detour.
    local nearClear=true
    -- Within three real yards, trust the actual coordinates: a 16-yard mask cell may
    -- mark a perfectly usable doorway or indoor floor blocked, even directly underfoot.
    if direct and direct>3 and direct<=ARRIVED and M.Terrain and M.Terrain.maps[pc] then nearClear=M.Terrain.Clear(M.Terrain.maps[pc],pX,pY,tX,tY,false) end
    if direct and direct <= ARRIVED and nearClear then
        clearGround()
        show(title, A.L("navArrived"), "", A.L("navHint")); setArrow(nil); N.shown = {{id = "goal", u = tu, v = tv, title = title}}
        if target.kind ~= "player" then N.arrivedAt = N.arrivedAt or now; if now - N.arrivedAt > 15 then M.Stop() end end
        return
    end
    N.arrivedAt = nil

    if not plan or not plan.steps[1] then
        local gx,gy,remaining=groundPointer(pc,pX,pY,tc,tX,tY,now)
        if direct then show(title, string.format(A.L("navDirect"), yards(remaining or direct)), A.L("navNoRoute"), groundHint()) else show(title, A.L("navNoRoute"), "", A.L("navHint")) end
        local bearing, toPoint = M.Bearing(pc, pX, pY, tc, gx, gy)
        if direct and bearing then N.aim = {c = tc, x = gx, y = gy, tail = (remaining or direct) - (toPoint or 0)} end
        local facing = A.Call(GetPlayerFacing)
        setArrow(direct and bearing and facing and normalize(bearing - facing) or nil, remaining or direct)
        N.shown = {{id = "goal", u = tu, v = tv, title = title}}
        groundPin()
        return
    end

    -- the pointer: where the first step wants you to go
    local step = plan.steps[1]
    local pu, pv = step.tu, step.tv
    local walking=step.mode=="walk"
    if step.mode ~= "walk" and step.fu then
        local bc, bx, by = M.ToYards(step.fu, step.fv)
        local _, away = M.Bearing(pc, pX, pY, bc, bx, by)
        if away and away > BOARD then pu, pv,walking = step.fu, step.fv,true end -- walk to where it starts first
    end
    local pointerYards, rotation
    if pu then
        local qc, qx, qy = M.ToYards(pu, pv)
        local remaining
        if walking then qx,qy,remaining=groundPointer(pc,pX,pY,qc,qx,qy,now) else clearGround() end
        local bearing, d = M.Bearing(pc, pX, pY, qc, qx, qy)
        pointerYards = remaining or d
        if bearing and d then N.aim = {c = qc, x = qx, y = qy, tail = pointerYards - d} end
        local facing = A.Call(GetPlayerFacing)
        if bearing and facing then rotation = normalize(bearing - facing) end
        local _,legDistance=M.Bearing(pc,pX,pY,M.ToYards(pu,pv))
        if legDistance and legDistance < 40 and step.mode == "walk" and #plan.steps > 1 then N.force = true end -- reached the actual leg endpoint, not an intermediate terrain bend
    end
    setArrow(rotation, pointerYards)
    local more = #plan.steps - 1
    local second = more > 0 and (A.L("navThen") .. " " .. stepText(plan.steps[2])) or string.format(A.L("navTotal"), clock(plan.seconds))
    if more > 0 then second = second .. "  ·  " .. string.format(A.L("navTotal"), clock(plan.seconds)) end
    local hint = walking and groundHint() or A.L("navHint")
    if plan.steps[1].estimated then hint = A.L("navEstimate") .. "  " .. hint end
    show(title, stepText(step, step.mode == "walk" and pointerYards or nil), second, hint)

    N.shown = {{id = "goal", u = tu, v = tv, title = title}}
    if pu and (step.mode ~= "walk" or #plan.steps > 1) then N.shown[#N.shown + 1] = {id = "next", u = pu, v = pv, title = stepText(step)} end
    groundPin()
end

-- ---------------------------------------------------------------- public
--- target = {kind="player", name=} or {kind="point", map=, x=, y=, label=}
function M.Navigate(target)
    if type(target) ~= "table" then return false, "no_target" end
    if target.kind == "player" then
        if not A.LivePeer or not A.LivePeer(target.name) then return false, "unknown_player" end
    elseif target.kind == "point" then
        if not M.ToUV(target.map, target.x, target.y) then return false, "unknown_map" end
    else return false, "no_target" end
    if M.Plan and M.Plan.preview and M.Journey then
        M.Journey.Cancel(M.Plan.preview);M.Plan.preview=nil
    end
    clearGround()
    M.route = nil   -- a route that was only shown gives way to the one navigation draws
    N.target, N.plan, N.planned, N.planTo, N.arrivedAt, N.force = target, nil, false, nil, nil, true
    local f = ensureFrame()
    if M.ArrowShown and not M.ArrowShown() then f:Hide(); A.Print(A.L("arrowHiddenNote")) else f:Show() end
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(TICK, N.Update) end
    N.Update()
    -- A new Evertally destination always uses our solid route on both maps. Do not
    -- revive the old persisted SPF handoff: SPF draws its own breadcrumb overlay.
    local api = terrainApi()
    if api and terrainActive(api) and type(api.Cancel) == "function" then pcall(api.Cancel, "Evertally") end
    if A.db then A.db.settings.navSpfAuto = nil end
    return true
end

function M.Stop()
    clearGround()
    if N.journey and M.Journey then M.Journey.Cancel(N.journey) end
    N.journey=nil
    if M.Plan and M.Plan.preview and M.Journey then
        M.Journey.Cancel(M.Plan.preview);M.Plan.preview=nil
    end
    local spf = terrainApi()
    if spf and terrainActive(spf) and type(spf.Cancel) == "function" then pcall(spf.Cancel, "Evertally") end
    if A.db then A.db.settings.navSpfAuto = nil end
    N.target, N.plan, N.planned, N.shown, N.aim, N.routeCache = nil, nil, false, {}, nil, nil
    N.lastRoute = nil
    if ticker then ticker:Cancel(); ticker = nil end
    if frame then frame:Hide(); frame.resizing = false; if frame.grip then frame.grip:Hide() end end
    if M.ArrowMenuClose then M.ArrowMenuClose() end
    if M.ClearRoute then M.ClearRoute() end
end

--- Explicit refresh from the route/arrow menu. Preserve the current verified
--- line while comparing alternatives to this same destination.
function M.RecalculateRoute()
    if not N.target then return false end
    N.force = true
    N.Update()
    return true
end

-- Explicit handoff to the optional Shortest Path Forever addon. Its terrain
-- guidance is a separate journey and may replace another active SPF journey.
function M.NavigateTerrain()
    local api = _G.ShortestPathForever and _G.ShortestPathForever.API
    if not api or type(api.Navigate) ~= "function" then return false, "missing" end
    if not N.target then return false, "no_target" end
    local map, x, y, label = resolve(N.target)
    if not map or not x or not y then return false, "no_target" end
    local ok, started = pcall(api.Navigate, "Evertally", map, x, y, label or "Evertally")
    if not ok or not started then return false, "refused" end
    return true
end

--- Optional, explicit SPF guidance for the current destination. Evertally's solid
--- route stays visible; another destination does not automatically start SPF.
function M.SpfInstalled() return terrainApi() ~= nil end
function M.SpfAuto() return terrainActive(terrainApi()) end
function M.SetSpfAuto(on)
    if A.db then A.db.settings.navSpfAuto = nil end
    local api = terrainApi()
    if on then return M.NavigateTerrain() end
    if not on and api and type(api.Cancel) == "function" then pcall(api.Cancel, "Evertally") end
    if M.RefreshRoute then M.RefreshRoute(true) end
    return true
end
--- Compatibility query for the supplementary SPF journey; it never suppresses
--- the solid Evertally renderer.
function M.SpfDrawsRoute()
    if not N.target then return false end
    local api = terrainApi()
    return api ~= nil and terrainActive(api) == true
end

--- The arrow's frame (nil before the first navigation).
function M.NavFrame() return frame end

--- The remaining route starts at the player now, not at the last transport replan
--- eight seconds ago. Reuse the arrow's terrain search and discard passed bends.
function M.RoutePlan()
    if not N.target then return nil end
    if N.journey and N.journey.state~="ready" and not N.plan then return nil end
    local plan = N.plan
    local first = plan and plan.steps and plan.steps[1]
    -- The transport planner omits very short walks. A wall can still require a
    -- real detour there, and the arrow's searched walk must reach the renderer.
    if not first then
        local map,x,y,label=resolve(N.target)
        local tu,tv
        if map then tu,tv=M.ToUV(map,x,y) end
        local u,v=M.PlayerPosition()
        if not (u and tu) then return plan end
        local seconds=N.ground and N.ground.job.result and N.ground.job.result.yards/speed() or 0
        first={mode="walk",fu=u,fv=v,tu=tu,tv=tv,to=label or "?",seconds=seconds}
        plan={steps={first},seconds=seconds}
    end
    if not first or first.mode ~= "walk" then return plan end
    local u, v = M.PlayerPosition()
    if not u then return plan end
    local c = M.ToYards(u, v)
    local goalC = M.ToYards(first.tu, first.tv)
    if c ~= goalC then return plan end
    local ground = N.ground
    local result = ground and ground.job and ground.job.state == "ready" and ground.job.result
    local yardsFrame = result and ground.map == c and M.data.yards[c]
    local index = ground and ground.index
    local cached = N.routeCache
    local sameTail = result and cached and cached.result == result and cached.index == index and cached.map == c
        and cached.tu == first.tu and cached.tv == first.tv
    if sameTail and cached.plan == plan and cached.u == u and cached.v == v then return cached.remaining end
    local step = {}
    for key, value in pairs(first) do step[key] = value end
    step.fu, step.fv = u, v
    step.routePath = {{u, v}}
    step.routeGeometry = sameTail and cached.geometry or {}
    local last = N.lastRoute
    if sameTail then
        local previous = cached.remaining.steps[1].routePath
        for i = 2, #previous do step.routePath[i] = previous[i] end
    elseif yardsFrame then
        local tail = {}
        for i = ground.index, #result.points do
            local p = result.points[i]
            tail[#tail + 1] = {yardsFrame[1] + p[2] * yardsFrame[2], yardsFrame[3] + p[1] * yardsFrame[4]}
            step.routePath[#step.routePath + 1] = tail[#tail]
        end
        N.lastRoute = {map = c, tu = first.tu, tv = first.tv, tail = tail, geometry = step.routeGeometry}
    elseif last and last.map == c and last.tu == first.tu and last.tv == first.tv and #last.tail > 0 then
        -- A new search is running (the player left the line or the old one expired): the line stays on the map, trimmed to the player.
        local best, bestD = 1, math.huge
        for i, p in ipairs(last.tail) do
            local d = (p[1] - u) ^ 2 + (p[2] - v) ^ 2
            if d < bestD then best, bestD = i, d end
        end
        for i = best, #last.tail do step.routePath[#step.routePath + 1] = last.tail[i] end
        step.routeGeometry = last.geometry
    elseif not (M.Terrain and M.Terrain.RoadBacked and M.Terrain.RoadBacked(c)) then
        step.routePath[2] = {first.tu, first.tv}
    end
    local remaining = {}
    for key, value in pairs(plan) do remaining[key] = value end
    remaining.steps = {step}
    for i = 2, #plan.steps do remaining.steps[i] = plan.steps[i] end
    N.routeCache = {plan = plan, result = result, index = index, map = c, u = u, v = v, tu = first.tu, tv = first.tv,
        geometry = step.routeGeometry, remaining = remaining}
    return remaining
end

--- Pins for what navigation points at: the goal and, on a journey, the next stop. {id, map, x, y, title}
function M.NavPins()
    local out = {}
    for _, pin in ipairs(N.shown) do
        local map, x, y = M.Locate(pin.u, pin.v)
        if map then out[#out + 1] = {id = pin.id, map = map, x = x, y = y, title = pin.title} end
    end
    return out
end

--- /etally navdebug: the numbers behind the arrow, next to HereBeDragons' own vector for comparison.
function M.NavDebug()
    local target = N.target
    local meU, meV, meMap, meX, meY = M.PlayerPosition()
    if not meU then A.Print("navdebug: " .. A.L("navNoPosition")); return end
    local tm, tx, ty = resolve(target or {kind = "point", map = meMap, x = meX, y = meY})
    local tu, tv = M.ToUV(tm, tx, ty)
    local pc, pX, pY = M.ToYards(meU, meV)
    local tc, tX, tY = M.ToYards(tu, tv)
    local bearing, d = M.Bearing(pc, pX, pY, tc, tX, tY)
    local facing = A.Call(GetPlayerFacing)
    A.Print(string.format("navdebug: map %s %.3f %.3f -> yards c%s %.0f %.0f; target c%s %.0f %.0f", tostring(meMap), meX, meY, tostring(pc), pX, pY, tostring(tc), tX, tY))
    A.Print(string.format("navdebug: ours bearing %s facing %s distance %s", bearing and string.format("%.3f", bearing) or "-", facing and string.format("%.3f", facing) or "-", d and yards(d) or "-"))
    local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
    if HBD then
        local wx, wy, instance = HBD:GetPlayerWorldPosition()
        local dx, dy, dinstance = HBD:GetWorldCoordinatesFromZone(tx, ty, tm)
        if wx and dx and instance == dinstance then
            local angle, dist = HBD:GetWorldVector(instance, wx, wy, dx, dy)
            A.Print(string.format("navdebug: HereBeDragons angle %s distance %s", angle and string.format("%.3f", angle) or "-", dist and yards(dist) or "-"))
        end
    end
end

-- ---------------------------------------------------------------- loose "Stop navigation" button
-- A small button that is on screen only while navigating. It can be dragged anywhere (the place is kept) and a click
-- ends the navigation. It does not depend on the arrow, which can be hidden or resized.
A.locale.en.stopNavButton = "Stop navigation"
A.locale.cs.stopNavButton = "Ukončit navigaci"
local stopButton
local function applyStopPosition(b)
    local s = A.db and A.db.settings
    local pos = s and s.stopNavPos
    b:ClearAllPoints()
    if type(pos) == "table" and type(pos[1]) == "string" then b:SetPoint(pos[1], UIParent, pos[1], tonumber(pos[2]) or 0, tonumber(pos[3]) or 0)
    else b:SetPoint("TOP", UIParent, "TOP", 0, -170) end
end
local function ensureStopButton()
    if stopButton then return stopButton end
    local kit=A.UIKit();local C=kit.C
    local b = CreateFrame("Button", "EvertallyStopNavigation", UIParent)
    b:SetSize(150, 26); b:SetFrameStrata("HIGH"); b:SetMovable(true); b:SetClampedToScreen(true)
    b:RegisterForDrag("LeftButton")
    b.bg=A.NativeButton(b,C,false)
    b.hover=b:CreateTexture(nil,"HIGHLIGHT");b.hover:SetAllPoints(b);kit.paint(b.hover,C.gold,0.16)
    b.text=kit.label(b,12,C.bright);b.text:SetPoint("CENTER")
    b:SetScript("OnDragStart", function(self) self.moved = true; self:StartMoving() end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        if A.db and point then A.db.settings.stopNavPos = {point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)} end
    end)
    b:SetScript("OnMouseDown", function(self) self.moved = false end)
    b:SetScript("OnClick", function(self) if not self.moved then A.StopNavigation() end; self.moved = false end)
    applyStopPosition(b)
    b:Hide()
    stopButton = b
    return b
end
local function refreshStopButton()
    if not A.db then return end
    local active = N.target ~= nil
    if active then
        local b = ensureStopButton()
        b.text:SetText(A.L("stopNavButton"))
        b:Show()
    elseif stopButton then stopButton:Hide() end
end
if C_Timer and type(C_Timer.NewTicker) == "function" then C_Timer.NewTicker(0.5, function() pcall(refreshStopButton) end) end
