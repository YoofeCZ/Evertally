local _, A = ...
-- Evertally's threat meter (settings.meter.threat): who has how much threat on your target, from
-- UnitDetailedThreatSituation for you, your pet and your group. The client may make the values secret
-- (SecretWhenUnitThreatValuesRestricted): then each row hands its percentage to the bar and the text as they are,
-- in group order; plain values are sorted, the tank marked, and you get a warning colour near the tank's threat.
local T = {}
A.ThreatMeter = T

local ROW_H, WIDTH, PAD, HEADER, MAX_ROWS = 16, 220, 6, 22, 10

local text = {
    en = {thTitle = "Threat", thNoTarget = "No hostile target.", thNoThreat = "Nobody has threat on it yet.",
        threatEnabled = "Threat meter", threatEnabledHelp = "Threat on your target for you, your pet and your group. /etally threat shows or hides it.",
        threatGroupOnly = "Threat meter only in a group", threatShow = "Show the threat meter"},
    cs = {thTitle = "Agro", thNoTarget = "Žádný nepřátelský cíl.", thNoThreat = "Na cíli zatím nikdo nemá agro.",
        threatEnabled = "Threat meter (agro)", threatEnabledHelp = "Agro na tvém cíli pro tebe, tvého mazlíčka a skupinu. /etally threat ho ukáže nebo schová.",
        threatGroupOnly = "Threat meter jen ve skupině", threatShow = "Ukázat threat meter"},
}
for lang, entries in pairs(text) do for k, v in pairs(entries) do A.locale[lang][k] = v end end

local function g(name) return rawget(_G, name) end
local function call(fn, ...) if type(fn) == "function" then return fn(...) end end
local function settings() return A.Meter and A.Meter.Settings() or {} end
local function secret(v) local f = g("issecretvalue"); return type(f) == "function" and f(v) == true end

function T.Enabled() return settings().threat == true end

--- The units to ask about: you, your pet, then the party or the raid (with their pets).
function T.Units()
    local out = {"player"}
    if call(g("UnitExists"), "pet") then out[#out + 1] = "pet" end
    local raid = call(g("IsInRaid")) == true
    local n = tonumber(call(g("GetNumGroupMembers"))) or 0
    if raid then
        for i = 1, math.min(n, 40) do
            local u = "raid" .. i
            if call(g("UnitExists"), u) and not call(g("UnitIsUnit"), u, "player") then out[#out + 1] = u end
        end
    elseif n > 0 then
        for i = 1, 4 do
            local u = "party" .. i
            if call(g("UnitExists"), u) then out[#out + 1] = u; if call(g("UnitExists"), "partypet" .. i) then out[#out + 1] = "partypet" .. i end end
        end
    end
    return out
end

--- The rows for the target: {unit, name, class, pct, tanking, secret}; sorted, highest first, when plain.
function T.Rows(target)
    target = target or "target"
    local out = {}
    if not call(g("UnitExists"), target) or call(g("UnitIsFriend"), "player", target) then return out, "none" end
    local anySecret = false
    for _, unit in ipairs(T.Units()) do
        local ok, tanking, status, scaled = pcall(g("UnitDetailedThreatSituation"), unit, target)
        if ok and (secret(scaled) or scaled ~= nil) then
            local _, class = call(g("UnitClass"), unit)
            local r = {unit = unit, name = call(g("UnitName"), unit), class = class, pct = scaled, tanking = tanking, status = status}
            r.secret = secret(scaled) or secret(tanking)
            anySecret = anySecret or r.secret
            out[#out + 1] = r
        end
    end
    if not anySecret then table.sort(out, function(a, b) return (tonumber(a.pct) or 0) > (tonumber(b.pct) or 0) end) end
    return out, anySecret and "secret" or "plain"
end

-- ---------------------------------------------------------------- the window
local kit, C
local function paint(t, c, a)
    if t.SetTextColor and not t.SetTexture then t:SetTextColor(c[1], c[2], c[3], a or c[4] or 1); return end
    kit.paint(t, c, a)
end
local function classColor(class)
    local cc = g("RAID_CLASS_COLORS")
    local c = type(cc) == "table" and type(class) == "string" and cc[class]
    return c and {c.r, c.g, c.b} or (C.lilac or {0.6, 0.5, 0.95})
end

function T.Build()
    if T.frame then return T.frame end
    kit = kit or A.UIKit(); C = C or kit.C
    local s = settings()
    local f = CreateFrame("Frame", "EvertallyThreat", UIParent)
    T.frame = f
    f:SetSize(WIDTH, HEADER + PAD * 2 + 3 * (ROW_H + 1))
    if type(s.threatPoint) == "table" then f:SetPoint(s.threatPoint[1] or "CENTER", UIParent, s.threatPoint[2] or "CENTER", s.threatPoint[3] or 0, s.threatPoint[4] or 0)
    else f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120) end
    f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
    A.NativeFrame(f, C)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not settings().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rel, x, y = self:GetPoint(1)
        settings().threatPoint = {p, rel, x, y}
    end)
    f.title = kit.label(f, 12, C.bright); f.title:SetPoint("TOPLEFT", PAD + 2, -5)
    f.close = kit.IconButton(f, "close", 16, function() T.SetShown(false) end, "lwClose"); f.close:SetPoint("TOPRIGHT", -3, -3)
    f.note = kit.label(f, 11, C.mist); f.note:SetPoint("TOPLEFT", PAD + 2, -HEADER - 4)
    f.rows = {}
    f:Hide()
    return f
end

local function row(f, i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("StatusBar", nil, f); r:SetHeight(ROW_H)
    r:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8"); r:SetMinMaxValues(0, 100); r:SetValue(0)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(r); paint(r.bg, C.card or {0.1, 0.1, 0.14}, 0.6)
    r.name = kit.label(r, 11, C.bright); r.name:SetPoint("LEFT", 4, 0); r.name:SetJustifyH("LEFT")
    r.pct = kit.label(r, 11, C.bright); r.pct:SetPoint("RIGHT", -4, 0); r.pct:SetJustifyH("RIGHT")
    r.name:SetPoint("RIGHT", r.pct, "LEFT", -4, 0)
    f.rows[i] = r
    return r
end

function T.Refresh()
    local f = T.frame
    if not (f and f:IsShown()) then return end
    f.title:SetText(A.L("thTitle") .. (call(g("UnitExists"), "target") and (": " .. tostring(call(g("UnitName"), "target") or "")) or ""))
    local rows, state = T.Rows("target")
    f.note:SetText(state == "none" and A.L("thNoTarget") or #rows == 0 and A.L("thNoThreat") or "")
    local n = math.min(#rows, MAX_ROWS)
    for i = 1, n do
        local d = rows[i]
        local r = row(f, i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", PAD, -HEADER - 2 - (i - 1) * (ROW_H + 1)); r:SetPoint("TOPRIGHT", -PAD, -HEADER - 2 - (i - 1) * (ROW_H + 1))
        local c = classColor(d.class)
        if d.secret then
            r:SetStatusBarColor(c[1], c[2], c[3], 0.55)
            if not pcall(r.SetValue, r, d.pct) then r:SetValue(0) end
            if not pcall(r.pct.SetText, r.pct, d.pct) then r.pct:SetText("") end
        else
            local pct = tonumber(d.pct) or 0
            -- the tank in its class colour; anyone near the tank's threat turns warning-red
            if d.tanking == true then r:SetStatusBarColor(c[1], c[2], c[3], 0.8)
            elseif pct >= 80 then r:SetStatusBarColor(0.9, 0.25, 0.2, 0.7)
            else r:SetStatusBarColor(c[1], c[2], c[3], 0.45) end
            r:SetValue(pct)
            r.pct:SetText(string.format("%d%%", math.floor(pct + 0.5)))
        end
        if not pcall(r.name.SetText, r.name, d.name) then r.name:SetText("") end
        r:Show()
    end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end
    f:SetHeight(HEADER + PAD * 2 + math.max(1, n) * (ROW_H + 1) + (n == 0 and 10 or 0))
end

--- Shown while it is on and (when asked) you are in a group.
function T.Update()
    local want = T.Enabled() and settings().threatShown ~= false
    if want and settings().threatGroupOnly == true and (tonumber(call(g("GetNumGroupMembers"))) or 0) == 0 then want = false end
    if want then T.Build():Show(); T.Refresh() elseif T.frame then T.frame:Hide() end
end
function T.SetShown(on) if not A.db then return end; settings().threatShown = on == true; T.Update() end
function T.SetEnabled(on) if not A.db then return end; settings().threat = on == true; if on then settings().threatShown = true end; T.Update() end
function T.Toggle() if T.frame and T.frame:IsShown() then T.SetShown(false) else settings().threat = true; T.SetShown(true) end end

A.On("PLAYER_LOGIN", function() T.Update() end)
A.On("GROUP_ROSTER_UPDATE", function() T.Update() end)
for _, ev in ipairs({"PLAYER_TARGET_CHANGED", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_ENABLED"}) do
    A.On(ev, function() T.Refresh() end)
end
-- threat moves without an event for every hit: a light refresh while a fight is on
local ticker
A.On("PLAYER_REGEN_DISABLED", function()
    local t = g("C_Timer")
    if ticker or not (type(t) == "table" and t.NewTicker) then return end
    ticker = t.NewTicker(0.5, function()
        if call(g("InCombatLockdown")) ~= true then ticker:Cancel(); ticker = nil end
        pcall(T.Refresh)
    end)
end)
