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
    if c1 ~= c2 then return nil end
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

-- ---------------------------------------------------------------- the tracker frame
local function fontPath() return A.FontPath and A.FontPath() or "Fonts\\FRIZQT__.TTF" end
local function text(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontPath(), size, ""); fs:SetTextColor(r, g, b, 1); fs:SetJustifyH("LEFT")
    return fs
end
local function ensureFrame()
    if frame then return frame end
    local f = CreateFrame("Frame", "EvertallyTracker", UIParent)
    f:SetSize(262, 66); f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
    local saved = A.db and A.db.settings.navPos
    if type(saved) == "table" and A.Number(saved[2], -5000, 5000) and A.Number(saved[3], -5000, 5000) then f:SetPoint("CENTER", UIParent, "CENTER", saved[2], saved[3])
    elseif Minimap then f:SetPoint("TOP", Minimap, "BOTTOM", 0, -26)
    else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints()
    if f.bg.SetColorTexture then f.bg:SetColorTexture(0.075, 0.067, 0.11, 0.88) else f.bg:SetTexture(0.075, 0.067, 0.11, 0.88) end
    f.arrow = f:CreateTexture(nil, "ARTWORK"); f.arrow:SetSize(40, 40); f.arrow:SetPoint("LEFT", 8, 0)
    f.arrow:SetTexture(MEDIA .. "arrow"); f.arrow:SetVertexColor(0.655, 0.545, 0.98)
    f.title = text(f, 12, 0.97, 0.97, 0.97); f.title:SetPoint("TOPLEFT", 56, -8); f.title:SetWidth(190)
    f.line1 = text(f, 10, 0.80, 0.80, 0.85); f.line1:SetPoint("TOPLEFT", 56, -24); f.line1:SetWidth(196)
    f.line2 = text(f, 10, 0.60, 0.60, 0.68); f.line2:SetPoint("TOPLEFT", 56, -38); f.line2:SetWidth(196)
    f.hint = text(f, 9, 0.45, 0.46, 0.52); f.hint:SetPoint("BOTTOMLEFT", 56, 5); f.hint:SetWidth(196)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter(); local ux, uy = UIParent:GetCenter()
        if A.db and x and ux then A.db.settings.navPos = {"CENTER", math.floor(x - ux), math.floor(y - uy)} end
    end)
    f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then M.Stop() end end)
    f:Hide()
    frame = f
    return f
end

local function setArrow(rotation)
    if not frame then return end
    if rotation == nil then frame.arrow:Hide(); return end
    frame.arrow:Show()
    if frame.arrow.SetRotation then pcall(frame.arrow.SetRotation, frame.arrow, rotation) end
end
local function show(title, line1, line2, hint)
    if not frame then return end
    frame.title:SetText(title or ""); frame.line1:SetText(line1 or ""); frame.line2:SetText(line2 or ""); frame.hint:SetText(hint or "")
end

-- ---------------------------------------------------------------- one update
local function replan(meU, meV, tu, tv, label)
    N.plan = M.PlanJourney({u = meU, v = meV, label = A.L("navYou")}, {u = tu, v = tv, label = label}, {side = side(), speed = speed()})
    N.planAt, N.planTo = A.Monotonic(), {tu, tv}
    N.planned = true
end

function N.Update()
    local target = N.target
    if not target then return end
    local f = ensureFrame()
    local tm, tx, ty, label, stale = resolve(target)
    if not tm then show(target.name or target.label or "?", A.L("navLost"), "", A.L("navHint")); setArrow(nil); N.shown = {}; return end
    local tu, tv = M.ToUV(tm, tx, ty)
    if not tu then show(label, A.L("navNoMap"), "", A.L("navHint")); setArrow(nil); N.shown = {}; return end
    local meU, meV, meMap, meX, meY = M.PlayerPosition()
    local title = (stale and "? " or "") .. tostring(label or "?")
    if not meU then
        -- on a ship, in an instance, between maps: keep what was shown, but say the position is unknown
        show(title, f.line1:GetText(), f.line2:GetText(), A.L("navNoPosition")); setArrow(nil); N.shown = {}; return
    end

    local now = A.Monotonic()
    local tc, tX, tY = M.ToYards(tu, tv)
    local pc, pX, pY = M.ToYards(meU, meV)
    local movedTarget = N.planTo and select(2, M.Bearing(tc, tX, tY, M.ToYards(N.planTo[1], N.planTo[2]))) or math.huge
    if not N.plan and N.planned and now - N.planAt < PLAN_EVERY then
        -- no route is known: do not search again every tick
    elseif not N.planned or now - N.planAt >= PLAN_EVERY or (movedTarget or 0) > MOVED_TARGET or N.force then
        replan(meU, meV, tu, tv, label); N.force = false
    end

    local plan = N.plan
    local _, direct = M.Bearing(pc, pX, pY, tc, tX, tY)
    if direct and direct <= ARRIVED then
        show(title, A.L("navArrived"), "", A.L("navHint")); setArrow(nil); N.shown = {{id = "goal", u = tu, v = tv, title = title}}
        if target.kind ~= "player" then N.arrivedAt = N.arrivedAt or now; if now - N.arrivedAt > 15 then M.Stop() end end
        return
    end
    N.arrivedAt = nil

    if not plan or not plan.steps[1] then
        if direct then show(title, string.format(A.L("navDirect"), yards(direct)), A.L("navNoRoute"), A.L("navHint")) else show(title, A.L("navNoRoute"), "", A.L("navHint")) end
        local bearing = direct and M.Bearing(pc, pX, pY, tc, tX, tY)
        local facing = A.Call(GetPlayerFacing)
        setArrow(bearing and facing and normalize(bearing - facing) or nil)
        N.shown = {{id = "goal", u = tu, v = tv, title = title}}
        return
    end

    -- the pointer: where the first step wants you to go
    local step = plan.steps[1]
    local pu, pv = step.tu, step.tv
    if step.mode ~= "walk" and step.fu then
        local bc, bx, by = M.ToYards(step.fu, step.fv)
        local _, away = M.Bearing(pc, pX, pY, bc, bx, by)
        if away and away > BOARD then pu, pv = step.fu, step.fv end -- walk to where it starts first
    end
    local pointerYards, rotation
    if pu then
        local qc, qx, qy = M.ToYards(pu, pv)
        local bearing, d = M.Bearing(pc, pX, pY, qc, qx, qy)
        pointerYards = d
        local facing = A.Call(GetPlayerFacing)
        if bearing and facing then rotation = normalize(bearing - facing) end
        if d and d < 40 and step.mode == "walk" and #plan.steps > 1 then N.force = true end -- reached the end of this walk: look further ahead
    end
    setArrow(rotation)
    local more = #plan.steps - 1
    local second = more > 0 and (A.L("navThen") .. " " .. stepText(plan.steps[2])) or string.format(A.L("navTotal"), clock(plan.seconds))
    if more > 0 then second = second .. "  ·  " .. string.format(A.L("navTotal"), clock(plan.seconds)) end
    local hint = A.L("navHint")
    if plan.steps[1].estimated then hint = A.L("navEstimate") .. "  " .. hint end
    show(title, stepText(step, step.mode == "walk" and pointerYards or nil), second, hint)

    N.shown = {{id = "goal", u = tu, v = tv, title = title}}
    if pu and (step.mode ~= "walk" or #plan.steps > 1) then N.shown[#N.shown + 1] = {id = "next", u = pu, v = pv, title = stepText(step)} end
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
    N.target, N.plan, N.planned, N.planTo, N.arrivedAt, N.force = target, nil, false, nil, nil, true
    local f = ensureFrame(); f:Show()
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(TICK, N.Update) end
    N.Update()
    return true
end

function M.Stop()
    N.target, N.plan, N.planned, N.shown = nil, nil, false, {}
    if ticker then ticker:Cancel(); ticker = nil end
    if frame then frame:Hide() end
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
