local _, A = ...
-- Evertally's damage meter (settings.meter): the game's own combat data (C_DamageMeter, the client's built-in meter,
-- CVar damageMeterEnabled), drawn in Evertally's look. Forever gives add-ons no combat log
-- (CombatLogGetCurrentEventInfo is not in the client), so this is the source the other meters use too.
--
-- In combat the session's numbers and names are secret values: add-on code may hand them to a widget
-- (StatusBar:SetValue, AbbreviateNumbers, FontString:SetText) but not add, compare, sort or format them. So while they
-- are secret a row shows its bar, its name and its amount and per second as the client gives them, in the client's
-- order; once the fight is over (the values are plain again) it gets its percentage, the spell breakdown and the death
-- times. Every hand-over of a value that may be secret goes through pcall, so a refusal leaves a blank, never an error.
local M = {}
A.Meter = M

local ROW_H, WIDTH, HEIGHT, PAD, HEADER = 18, 300, 220, 6, 26

-- The meter's views: key, the client's DamageMeterType name, the locale key, the per-second view beside it.
M.MODES = {
    {key = "damage", type = "DamageDone", label = "mtDamage"},
    {key = "dps", type = "Dps", label = "mtDps", perSecond = true},
    {key = "healing", type = "HealingDone", label = "mtHealing"},
    {key = "hps", type = "Hps", label = "mtHps", perSecond = true},
    {key = "absorbs", type = "Absorbs", label = "mtAbsorbs"},
    {key = "taken", type = "DamageTaken", label = "mtTaken"},
    {key = "avoidable", type = "AvoidableDamageTaken", label = "mtAvoidable"},
    {key = "enemies", type = "EnemyDamageTaken", label = "mtEnemies"},
    {key = "interrupts", type = "Interrupts", label = "mtInterrupts", count = true},
    {key = "dispels", type = "Dispels", label = "mtDispels", count = true},
    {key = "deaths", type = "Deaths", label = "mtDeaths", deaths = true},
}
local BY_KEY = {}
for _, m in ipairs(M.MODES) do BY_KEY[m.key] = m end

local text = {
    en = {meterTitle = "Damage meter", mtDamage = "Damage done", mtDps = "DPS", mtHealing = "Healing done", mtHps = "HPS",
        mtAbsorbs = "Absorbs", mtTaken = "Damage taken", mtAvoidable = "Avoidable damage taken", mtEnemies = "Enemies (damage taken)",
        mtInterrupts = "Interrupts", mtDispels = "Dispels", mtDeaths = "Deaths", mtCurrent = "Current fight", mtOverall = "Overall",
        mtReset = "Reset the meter", mtResetDone = "The meter is empty.", mtNoData = "No fight yet.",
        mtUnavailable = "The game's combat data is off. Evertally switches it on; if the meter stays empty, restart WoW.",
        mtSpells = "%s: by spell", mtBack = "Back", mtInCombat = "Details after the fight.", mtSegment = "Fight",
        meterEnabled = "Damage meter", meterEnabledHelp = "Damage, healing, damage taken, enemies, interrupts, dispels and deaths of your group, from the game's own combat data. /etally meter shows or hides it.",
        meterLock = "Lock the meter and the threat meter", meterShow = "Show the damage meter", meterResetData = "Reset the meter",
        lootSparkles = "Loot sparkles", lootSparklesHelp = "Keeps the sparkle on lootable quest items on, also after a graphics preset switches it off.",
        setSecMeter = "Damage meter", setSecThreat = "Threat meter", setSecSparkles = "Quest items", combatSection = "Combat"},
    cs = {meterTitle = "Damage meter", mtDamage = "Poškození", mtDps = "DPS", mtHealing = "Léčení", mtHps = "HPS",
        mtAbsorbs = "Absorpce", mtTaken = "Přijaté poškození", mtAvoidable = "Přijaté poškození (šlo se vyhnout)", mtEnemies = "Nepřátelé (přijaté poškození)",
        mtInterrupts = "Přerušení", mtDispels = "Dispely", mtDeaths = "Smrti", mtCurrent = "Aktuální souboj", mtOverall = "Celkem",
        mtReset = "Vynulovat meter", mtResetDone = "Meter je prázdný.", mtNoData = "Zatím žádný souboj.",
        mtUnavailable = "Bojová data hry jsou vypnutá. Evertally je zapne; když meter zůstane prázdný, restartuj WoW.",
        mtSpells = "%s: podle kouzel", mtBack = "Zpět", mtInCombat = "Podrobnosti po souboji.", mtSegment = "Souboj",
        meterEnabled = "Damage meter", meterEnabledHelp = "Poškození, léčení, přijaté poškození, nepřátelé, přerušení, dispely a smrti tvé skupiny z vlastních bojových dat hry. /etally meter ho ukáže nebo schová.",
        meterLock = "Zamknout damage meter a threat meter", meterShow = "Ukázat damage meter", meterResetData = "Vynulovat meter",
        lootSparkles = "Jiskřičky na lootu", lootSparklesHelp = "Drží zapnuté jiskřičky na questových předmětech k sebrání, i když je grafická předvolba vypne.",
        setSecMeter = "Damage meter", setSecThreat = "Threat meter", setSecSparkles = "Questové předměty", combatSection = "Souboj"},
}
for lang, entries in pairs(text) do for k, v in pairs(entries) do A.locale[lang][k] = v end end

local function g(name) return rawget(_G, name) end
local function settings()
    local s = A.db and A.db.settings
    if not s then return {} end
    if type(s.meter) ~= "table" then s.meter = {} end
    return s.meter
end
M.Settings = settings
local function secret(v) local f = g("issecretvalue"); return type(f) == "function" and f(v) == true end
M.IsSecret = secret

-- ---------------------------------------------------------------- the game's data
local function api() local d = g("C_DamageMeter"); return type(d) == "table" and d or nil end
local function enum(group, name)
    local E = g("Enum"); local t = type(E) == "table" and E[group]
    return type(t) == "table" and t[name] or nil
end

--- Whether the client keeps combat data; switches it on when it does not (the CVar the game's meter uses).
function M.Available()
    local d = api()
    if not d then return false end
    local cvar = g("C_CVar")
    if type(cvar) == "table" and cvar.GetCVarBool and cvar.SetCVar and not cvar.GetCVarBool("damageMeterEnabled") then
        pcall(cvar.SetCVar, "damageMeterEnabled", "1")
    end
    if type(d.IsDamageMeterAvailable) ~= "function" then return true end
    local ok, on = pcall(d.IsDamageMeterAvailable)
    return ok and on ~= false
end

--- The fights to choose from: the current one, the overall, then the kept ones (sessionID, name, seconds).
function M.Segments()
    local out = {{kind = "type", value = "Current", label = A.L("mtCurrent")}, {kind = "type", value = "Overall", label = A.L("mtOverall")}}
    local d = api()
    if d and type(d.GetAvailableCombatSessions) == "function" then
        local ok, list = pcall(d.GetAvailableCombatSessions)
        if ok and type(list) == "table" then
            for i = #list, 1, -1 do
                local s = list[i]
                if type(s) == "table" and type(s.sessionID) == "number" then
                    local name = (not secret(s.name) and type(s.name) == "string" and s.name ~= "") and s.name or (A.L("mtSegment") .. " " .. s.sessionID)
                    out[#out + 1] = {kind = "id", value = s.sessionID, label = name, seconds = not secret(s.durationSeconds) and s.durationSeconds or nil}
                end
            end
        end
    end
    return out
end

local function sessionOf(mode, seg)
    local d = api()
    local mtype = enum("DamageMeterType", mode.type)
    if not (d and mtype) then return nil end
    local ok, session
    if seg.kind == "id" then
        ok, session = pcall(d.GetCombatSessionFromID, seg.value, mtype)
    else
        local st = enum("DamageMeterSessionType", seg.value)
        if st == nil then return nil end
        ok, session = pcall(d.GetCombatSessionFromType, st, mtype)
    end
    return ok and type(session) == "table" and session or nil
end

--- The rows of a view: {name, class, amount, perSecond, pct, secret, guid, creatureID, deathTime, isLocal}, in the
--- client's order; sorted by amount and given a percentage only when nothing is secret.
function M.Rows(modeKey, seg)
    local mode = BY_KEY[modeKey] or M.MODES[1]
    local session = sessionOf(mode, seg or M.Segments()[1])
    if not session then return {}, nil end
    local rows, anySecret = {}, secret(session.totalAmount) or secret(session.maxAmount)
    for _, src in ipairs(type(session.combatSources) == "table" and session.combatSources or {}) do
        local r = {name = src.name, class = src.classFilename, amount = src.totalAmount, perSecond = src.amountPerSecond,
            guid = src.sourceGUID, creatureID = src.sourceCreatureID, deathTime = src.deathTimeSeconds, isLocal = src.isLocalPlayer == true,
            deathRecapID = src.deathRecapID}
        r.secret = secret(r.amount) or secret(r.perSecond) or secret(r.name)
        anySecret = anySecret or r.secret
        rows[#rows + 1] = r
    end
    if not anySecret then
        local total = tonumber(session.totalAmount) or 0
        if mode.deaths then
            table.sort(rows, function(a, b) return (tonumber(a.deathTime) or 0) < (tonumber(b.deathTime) or 0) end)
        else
            table.sort(rows, function(a, b) return (tonumber(a.amount) or 0) > (tonumber(b.amount) or 0) end)
            if total > 0 then for _, r in ipairs(rows) do r.pct = (tonumber(r.amount) or 0) / total end end
        end
    end
    return rows, {total = session.totalAmount, max = session.maxAmount, seconds = session.durationSeconds, secret = anySecret}
end

--- A source's spells (out of combat): {spellID, name, amount, perSecond, pct, creature}, biggest first.
function M.Spells(modeKey, seg, row)
    local mode = BY_KEY[modeKey] or M.MODES[1]
    local d, mtype = api(), enum("DamageMeterType", mode.type)
    if not (d and mtype and row) or row.secret then return {} end
    local ok, src
    if seg.kind == "id" then
        ok, src = pcall(d.GetCombatSessionSourceFromID, seg.value, mtype, row.guid, row.creatureID)
    else
        ok, src = pcall(d.GetCombatSessionSourceFromType, enum("DamageMeterSessionType", seg.value), mtype, row.guid, row.creatureID)
    end
    if not (ok and type(src) == "table") then return {} end
    local out, total = {}, 0
    for _, sp in ipairs(type(src.combatSpells) == "table" and src.combatSpells or {}) do
        if secret(sp.totalAmount) then return {} end
        local name
        local C_Spell = g("C_Spell")
        if type(C_Spell) == "table" and C_Spell.GetSpellName and type(sp.spellID) == "number" then
            local okName, n = pcall(C_Spell.GetSpellName, sp.spellID); name = okName and n or nil
        end
        out[#out + 1] = {spellID = sp.spellID, name = name or ("#" .. tostring(sp.spellID)), amount = tonumber(sp.totalAmount) or 0,
            perSecond = tonumber(sp.amountPerSecond), creature = sp.creatureName}
        total = total + (tonumber(sp.totalAmount) or 0)
    end
    table.sort(out, function(a, b) return a.amount > b.amount end)
    if total > 0 then for _, s in ipairs(out) do s.pct = s.amount / total end end
    return out
end

function M.Reset()
    local d = api()
    if d and type(d.ResetAllCombatSessions) == "function" then pcall(d.ResetAllCombatSessions) end
    M.Request()
end

--- 1234 -> "1.2K", 1550000 -> "1.55M" (plain numbers); a secret one through the client's AbbreviateNumbers.
function M.Format(v)
    if secret(v) then
        local f = g("AbbreviateNumbers")
        if type(f) == "function" then local ok, s = pcall(f, v); if ok then return s end end
        return nil
    end
    if v == nil then return "" end
    v = tonumber(v) or 0
    local a = math.abs(v)
    if a >= 1e9 then return string.format("%.2fB", v / 1e9) end
    if a >= 1e6 then return string.format("%.2fM", v / 1e6) end
    if a >= 1e4 then return string.format("%.1fK", v / 1e3) end
    return tostring(math.floor(v + 0.5))
end
--- Seconds as m:ss.
function M.Clock(sec)
    if secret(sec) then return "" end
    sec = tonumber(sec)
    if not sec then return "" end
    return string.format("%dm %02ds", math.floor(sec / 60), math.floor(sec % 60))
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
    if c then return {c.r, c.g, c.b} end
    return C.lilac or {0.6, 0.5, 0.95}
end
local function setText(fs, v) if not pcall(fs.SetText, fs, v) then fs:SetText("") end end

local function popup(owner, items)
    local f = M.frame
    local m = f.menu
    if not m then
        m = CreateFrame("Frame", nil, f); m:SetFrameStrata("DIALOG"); m:EnableMouse(true)
        A.NativeFrame(m, C)
        m.rows = {}
        f.menu = m
    end
    if m:IsShown() and m.owner == owner then m:Hide(); return end
    m.owner = owner
    local width = 160
    for i, item in ipairs(items) do
        local r = m.rows[i]
        if not r then
            r = CreateFrame("Button", nil, m); r:SetHeight(20)
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(r); paint(hl, C.gold, 0.12)
            r.text = kit.label(r, 12, C.text); r.text:SetPoint("LEFT", 10, 0)
            r:SetScript("OnClick", function(self) m:Hide(); if self.fn then pcall(self.fn) end; M.Request() end)
            m.rows[i] = r
        end
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20); r:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 20)
        r.text:SetText(item.text); paint(r.text, item.checked and C.gold or C.text); r.fn = item.onClick
        width = math.max(width, math.floor((r.text:GetStringWidth() or 0) + 24))
        r:Show()
    end
    for i = #items + 1, #m.rows do m.rows[i]:Hide() end
    m:SetSize(width, #items * 20 + 8)
    m:ClearAllPoints(); m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    m:Show()
end

local function savePoint(f)
    local p, _, rel, x, y = f:GetPoint(1)
    local s = settings()
    s.point = {p, rel, x, y}
    s.width, s.height = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
end

function M.Build()
    if M.frame then return M.frame end
    kit = kit or A.UIKit(); C = C or kit.C
    local s = settings()
    local f = CreateFrame("Frame", "EvertallyMeter", UIParent)
    M.frame = f
    f:SetSize(s.width or WIDTH, s.height or HEIGHT)
    if type(s.point) == "table" then f:SetPoint(s.point[1] or "CENTER", UIParent, s.point[2] or "CENTER", s.point[3] or 0, s.point[4] or 0)
    else f:SetPoint("RIGHT", UIParent, "RIGHT", -40, -120) end
    f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
    if f.SetResizable then f:SetResizable(true) end
    if f.SetResizeBounds then pcall(f.SetResizeBounds, f, 200, 100, 700, 700) end
    A.NativeFrame(f, C)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not settings().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint(self) end)
    f.mode = CreateFrame("Button", nil, f); f.mode:SetHeight(HEADER - 6); f.mode:SetPoint("TOPLEFT", PAD, -4)
    f.mode.text = kit.label(f.mode, 12, C.bright); f.mode.text:SetPoint("LEFT", 2, 0)
    f.mode:SetScript("OnClick", function(self)
        local items = {}
        for _, m in ipairs(M.MODES) do
            local key = m.key
            items[#items + 1] = {text = A.L(m.label), checked = M.mode == key, onClick = function() M.mode = key; settings().mode = key; M.detail = nil end}
        end
        popup(self, items)
    end)
    f.seg = CreateFrame("Button", nil, f); f.seg:SetHeight(HEADER - 6); f.seg:SetPoint("LEFT", f.mode, "RIGHT", 8, 0)
    f.seg.text = kit.label(f.seg, 11, C.mist); f.seg.text:SetPoint("LEFT", 2, 0)
    f.seg:SetScript("OnClick", function(self)
        local items = {}
        for i, sg in ipairs(M.Segments()) do
            local seg = sg
            local label = sg.label .. (sg.seconds and ("  " .. M.Clock(sg.seconds)) or "")
            items[#items + 1] = {text = label, checked = M.segIndex == i, onClick = function() M.segIndex = i; M.segment = seg; M.detail = nil end}
        end
        items[#items + 1] = {text = A.L("mtReset"), onClick = function() M.Reset(); A.Print(A.L("mtResetDone")) end}
        popup(self, items)
    end)
    f.close = kit.IconButton(f, "close", 18, function() M.SetShown(false) end, "lwClose"); f.close:SetPoint("TOPRIGHT", -4, -4)
    f.line = f:CreateTexture(nil, "BORDER"); f.line:SetHeight(1); f.line:SetPoint("TOPLEFT", PAD, -HEADER); f.line:SetPoint("TOPRIGHT", -PAD, -HEADER); paint(f.line, C.line or C.mist, 0.5)
    f.note = kit.label(f, 11, C.mist); f.note:SetPoint("TOPLEFT", PAD + 2, -HEADER - 8); f.note:SetPoint("TOPRIGHT", -PAD, -HEADER - 8)
    f.note:SetJustifyH("LEFT")
    f.rows = {}
    f.grip = CreateFrame("Button", nil, f); f.grip:SetSize(14, 14); f.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    f.grip.tex = f.grip:CreateTexture(nil, "OVERLAY"); f.grip.tex:SetAllPoints(f.grip); paint(f.grip.tex, C.mist, 0.35)
    f.grip:SetScript("OnMouseDown", function() if not settings().locked then f:StartSizing("BOTTOMRIGHT") end end)
    f.grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); savePoint(f); M.Request() end)
    f:SetScript("OnSizeChanged", function() M.Request() end)
    f:Hide()
    return f
end

local function row(f, i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, f); r:SetHeight(ROW_H)
    r.bar = CreateFrame("StatusBar", nil, r); r.bar:SetAllPoints(r)
    r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8"); r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(0)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(r); paint(r.bg, C.card or {0.1, 0.1, 0.14}, 0.6)
    r.rank = kit.label(r.bar, 11, C.bright); r.rank:SetPoint("LEFT", 4, 0); r.rank:SetWidth(20); r.rank:SetJustifyH("LEFT")
    r.name = kit.label(r.bar, 11, C.bright); r.name:SetPoint("LEFT", r.rank, "RIGHT", 0, 0); r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.extra = kit.label(r.bar, 11, C.text); r.extra:SetPoint("RIGHT", -4, 0); r.extra:SetJustifyH("RIGHT")
    r.amount = kit.label(r.bar, 11, C.bright); r.amount:SetPoint("RIGHT", r.extra, "LEFT", -4, 0); r.amount:SetJustifyH("RIGHT")
    r.name:SetPoint("RIGHT", r.amount, "LEFT", -6, 0)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then M.detail = nil
        elseif self.data and not self.data.secret and not BY_KEY[M.mode or "damage"].deaths then M.detail = self.data end
        M.Request()
    end)
    f.rows[i] = r
    return r
end

local function drawRows(f, list, maxValue, mode)
    local room = math.max(1, math.floor((f:GetHeight() - HEADER - PAD * 2) / (ROW_H + 1)))
    local n = math.min(#list, room)
    for i = 1, n do
        local d = list[i]
        local r = row(f, i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", PAD, -HEADER - 4 - (i - 1) * (ROW_H + 1)); r:SetPoint("TOPRIGHT", -PAD, -HEADER - 4 - (i - 1) * (ROW_H + 1))
        r.data = d.row
        local c = d.color or C.lilac
        r.bar:SetStatusBarColor(c[1], c[2], c[3], 0.55)
        -- the bar: plain values as a share, secret ones handed to the bar (the client allows that, a refusal leaves it empty)
        if d.secret then
            if not pcall(r.bar.SetMinMaxValues, r.bar, 0, maxValue) then r.bar:SetMinMaxValues(0, 1) end
            if not pcall(r.bar.SetValue, r.bar, d.value) then r.bar:SetValue(0) end
        else
            r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(d.share or 0)
        end
        r.rank:SetText(i .. ".")
        setText(r.name, d.name)
        local amount = d.amount
        if not secret(amount) and amount == nil then amount = "" end
        setText(r.amount, amount)
        r.extra:SetText(d.extra or "")
        r:Show()
    end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end
end

--- Redraws the window from the client's data.
function M.Refresh()
    local f = M.frame
    if not (f and f:IsShown()) then return end
    kit = kit or A.UIKit(); C = C or kit.C
    local key = M.mode or settings().mode or "damage"
    M.mode = key
    local mode = BY_KEY[key] or M.MODES[1]
    local segs = M.Segments()
    local seg = M.segment or segs[1]
    f.mode.text:SetText(A.L(mode.label)); f.mode:SetWidth(math.max(40, (f.mode.text:GetStringWidth() or 60) + 6))
    f.seg.text:SetText("· " .. (seg.label or "")); f.seg:SetWidth(math.max(40, (f.seg.text:GetStringWidth() or 60) + 6))
    if not M.Available() then f.note:SetText(A.L("mtUnavailable")); drawRows(f, {}, 1, mode); return end
    local list = {}
    if M.detail then
        local spells = M.Spells(key, seg, M.detail)
        if #spells == 0 then M.detail = nil else
            f.note:SetText("")
            local top = spells[1].amount
            for _, sp in ipairs(spells) do
                list[#list + 1] = {name = sp.creature and (sp.name .. " (" .. sp.creature .. ")") or sp.name, amount = M.Format(sp.amount),
                    extra = sp.pct and string.format("%.1f%%", sp.pct * 100) or "", share = top > 0 and sp.amount / top or 0,
                    color = classColor(M.detail.class)}
            end
            f.seg.text:SetText("· " .. string.format(A.L("mtSpells"), tostring(M.detail.name or "")))
            drawRows(f, list, 1, mode)
            return
        end
    end
    local rows, info = M.Rows(key, seg)
    f.note:SetText(#rows == 0 and A.L("mtNoData") or "")
    local top = 0
    if info and not info.secret then for _, r in ipairs(rows) do top = math.max(top, tonumber(r.amount) or 0) end end
    for _, r in ipairs(rows) do
        local e = {row = r, name = r.name, color = classColor(r.class), secret = r.secret}
        if mode.deaths then
            e.amount = M.Clock(r.deathTime); e.share = 1
        else
            -- (no and/or on a value that may be secret: only plain booleans are tested)
            local main
            if mode.perSecond then main = r.perSecond else main = r.amount end
            e.value = main
            e.amount = M.Format(main)
            if r.secret then
                e.extra = ""
            else
                e.share = top > 0 and (tonumber(r.amount) or 0) / top or 0
                local ps = (not mode.perSecond and not mode.count) and r.perSecond and M.Format(r.perSecond) or nil
                local pct = r.pct and string.format("%.1f%%", r.pct * 100) or nil
                e.extra = ps and pct and ("(" .. ps .. ", " .. pct .. ")") or pct and ("(" .. pct .. ")") or ""
            end
        end
        list[#list + 1] = e
    end
    drawRows(f, list, info and info.max or 1, mode)
end

-- One redraw a moment after a burst of updates.
local pending = false
function M.Request()
    if pending then return end
    pending = true
    local run = function() pending = false; pcall(M.Refresh) end
    local t = g("C_Timer")
    if type(t) == "table" and t.After then t.After(0.25, run) else run() end
end

function M.Enabled() return settings().enabled == true end
function M.SetShown(on)
    if not A.db then return end
    settings().shown = on == true
    if on then M.Available(); M.Build():Show(); M.Request() elseif M.frame then M.frame:Hide() end
end
function M.SetEnabled(on)
    if not A.db then return end
    settings().enabled = on == true
    M.SetShown(on == true)
    if A.ThreatMeter then A.ThreatMeter.Update() end
end
function M.Toggle() if M.frame and M.frame:IsShown() then M.SetShown(false) else settings().enabled = true; M.SetShown(true) end end
function M.SetLocked(on) settings().locked = on == true end

A.On("PLAYER_LOGIN", function() if M.Enabled() and settings().shown ~= false then M.SetShown(true) end end)
for _, ev in ipairs({"DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE"}) do
    A.On(ev, function()
        -- a new fight starts on the current one again
        if ev == "PLAYER_REGEN_DISABLED" then M.detail = nil end
        M.Request()
    end)
end
