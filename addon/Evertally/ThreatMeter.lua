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

-- ---------------------------------------------------------------- the window: a view of the meter's windows (Meter.lua)
local function M() return A.Meter end
--- On while a window shows the threat view.
function T.Enabled()
    local i = M() and M().WindowWith("threat")
    return i ~= nil and not M().Windows()[i].hidden
end
function T.Update() if M() then M().Update() end end
function T.Refresh() if M() then M().Refresh() end end
--- On: a window with the threat view (a new one when there is none); off: that window goes.
function T.SetEnabled(on)
    if not (A.db and M()) then return end
    local i = M().WindowWith("threat")
    if on then
        settings().enabled = true
        if i then M().Windows()[i].hidden = nil; M().Update() else M().AddWindow("threat") end
    elseif i then
        M().CloseWindow(i)
    end
end
T.SetShown = T.SetEnabled
--- /etally threat: the threat window on or off.
function T.Toggle()
    if T.frame and T.frame:IsShown() then
        local i = M().WindowWith("threat"); if i then M().Windows()[i].hidden = true end
        M().Update()
    else
        T.SetEnabled(true)
    end
end
