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
    {key = "damage", type = "DamageDone", label = "mtDamage", group = "damage", icon = "icon-kill"},
    {key = "dps", type = "Dps", label = "mtDps", perSecond = true, group = "damage", icon = "icon-kill"},
    {key = "taken", type = "DamageTaken", label = "mtTaken", group = "damage", icon = "armor"},
    {key = "enemies", type = "EnemyDamageTaken", label = "mtEnemies", group = "damage", icon = "skull"},
    {key = "avoidable", type = "AvoidableDamageTaken", label = "mtAvoidable", group = "damage", icon = "armor"},
    {key = "healing", type = "HealingDone", label = "mtHealing", group = "heal", icon = "heal"},
    {key = "hps", type = "Hps", label = "mtHps", perSecond = true, group = "heal", icon = "heal"},
    {key = "absorbs", type = "Absorbs", label = "mtAbsorbs", group = "heal", icon = "heal"},
    {key = "interrupts", type = "Interrupts", label = "mtInterrupts", count = true, group = "misc", icon = "bolt"},
    {key = "dispels", type = "Dispels", label = "mtDispels", count = true, group = "misc", icon = "bolt"},
    {key = "deaths", type = "Deaths", label = "mtDeaths", deaths = true, group = "misc", icon = "skull"},
    -- not the client's meter: drawn from the threat API and the tanks' health (ThreatMeter.lua)
    {key = "threat", label = "thTitle", plugin = "threat", group = "plugins", icon = "qol-target"},
    {key = "vanguard", label = "vgTitle", plugin = "vanguard", group = "plugins", icon = "warrior"},
}
M.GROUPS = {{key = "damage", label = "mgDamage"}, {key = "heal", label = "mgHeal"}, {key = "misc", label = "mgMisc"}, {key = "plugins", label = "mgPlugins"}}
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
        setSecMeter = "Damage meter", setSecThreat = "Threat meter", setSecSparkles = "Quest items", combatSection = "Combat",
        mgDamage = "Damage", mgHeal = "Heal", mgMisc = "Miscellaneous", mgPlugins = "Plugins", vgTitle = "Vanguard (tanks)",
        mtNewWindow = "New window", mtCloseWindow = "Close this window", mtLock = "Lock the windows", mtUnlock = "Unlock the windows",
        mtViewMenu = "What this window shows", mtSegMenu = "Which fight", mtSpellCol = "Spell", mtAmountCol = "Amount",
        mtPsCol = "per s", mtTargets = "Targets", mtNoTanks = "No tank in the group.", meterWindows = "Damage meter windows",
        setupCombatTitle = "Combat", setupCombatBody = "A damage meter, a threat meter and sparkles on quest items, in Evertally's look. All of it can be changed in Settings > Combat.",
        setupMeterSub = "Damage, healing, interrupts, deaths… of your group. You can open more windows, each with its own view.",
        setupThreatSub = "Who has threat on your target: a window of its own.", setupSparklesSub = "Lootable quest items sparkle, also after a graphics preset switches it off."},
    cs = {meterTitle = "Damage meter", mtDamage = "Poškození", mtDps = "DPS", mtHealing = "Léčení", mtHps = "HPS",
        mtAbsorbs = "Absorpce", mtTaken = "Přijaté poškození", mtAvoidable = "Přijaté poškození (šlo se vyhnout)", mtEnemies = "Nepřátelé (přijaté poškození)",
        mtInterrupts = "Přerušení", mtDispels = "Dispely", mtDeaths = "Smrti", mtCurrent = "Aktuální souboj", mtOverall = "Celkem",
        mtReset = "Vynulovat meter", mtResetDone = "Meter je prázdný.", mtNoData = "Zatím žádný souboj.",
        mtUnavailable = "Bojová data hry jsou vypnutá. Evertally je zapne; když meter zůstane prázdný, restartuj WoW.",
        mtSpells = "%s: podle kouzel", mtBack = "Zpět", mtInCombat = "Podrobnosti po souboji.", mtSegment = "Souboj",
        meterEnabled = "Damage meter", meterEnabledHelp = "Poškození, léčení, přijaté poškození, nepřátelé, přerušení, dispely a smrti tvé skupiny z vlastních bojových dat hry. /etally meter ho ukáže nebo schová.",
        meterLock = "Zamknout damage meter a threat meter", meterShow = "Ukázat damage meter", meterResetData = "Vynulovat meter",
        lootSparkles = "Jiskřičky na lootu", lootSparklesHelp = "Drží zapnuté jiskřičky na questových předmětech k sebrání, i když je grafická předvolba vypne.",
        setSecMeter = "Damage meter", setSecThreat = "Threat meter", setSecSparkles = "Questové předměty", combatSection = "Souboj",
        mgDamage = "Poškození", mgHeal = "Léčení", mgMisc = "Ostatní", mgPlugins = "Pluginy", vgTitle = "Vanguard (tanci)",
        mtNewWindow = "Nové okno", mtCloseWindow = "Zavřít toto okno", mtLock = "Zamknout okna", mtUnlock = "Odemknout okna",
        mtViewMenu = "Co okno ukazuje", mtSegMenu = "Který souboj", mtSpellCol = "Kouzlo", mtAmountCol = "Množství",
        mtPsCol = "za s", mtTargets = "Cíle", mtNoTanks = "Ve skupině není tank.", meterWindows = "Okna damage meteru",
        setupCombatTitle = "Souboj", setupCombatBody = "Damage meter, threat meter a jiskřičky na questových předmětech ve vzhledu Evertally. Všechno změníš v Nastavení > Souboj.",
        setupMeterSub = "Poškození, léčení, přerušení, smrti… tvé skupiny. Můžeš otevřít víc oken, každé s vlastním pohledem.",
        setupThreatSub = "Kdo má agro na tvém cíli: vlastní okno.", setupSparklesSub = "Questové předměty k sebrání jiskří, i když je grafická předvolba vypne."},
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
    local out, total, targets = {}, 0, {}
    for _, sp in ipairs(type(src.combatSpells) == "table" and src.combatSpells or {}) do
        if secret(sp.totalAmount) then return {} end
        -- who it hit (or who hit you): one record or a list of them
        local det = sp.combatSpellDetails
        local list = type(det) == "table" and (det.unitName ~= nil and {det} or det) or {}
        for _, d in ipairs(list) do
            if type(d) == "table" and not secret(d.unitName) and not secret(d.amount) and type(d.unitName) == "string" then
                targets[d.unitName] = (targets[d.unitName] or 0) + (tonumber(d.amount) or 0)
            end
        end
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
    local tlist = {}
    for name, amount in pairs(targets) do tlist[#tlist + 1] = {name = name, amount = amount, pct = total > 0 and amount / total or nil} end
    table.sort(tlist, function(a, b) return a.amount > b.amount end)
    out.targets = tlist
    out.seconds = nil
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

-- ---------------------------------------------------------------- the windows
-- Any number of windows (settings.meter.windows: {view, point, width, height}), each with its own view and fight.
-- A plain look: a dark ground, a header with the view's name (a click: the views by group) and its buttons (the fight,
-- reset, a new window, close), class-coloured bars, and at the foot the lock and the size grip. Hovering a player
-- shows their spells and targets (after the fight); a click lists the spells in the window, a right-click goes back.
local kit, C
local BG, HEAD = {0.03, 0.03, 0.05, 0.82}, {0.10, 0.09, 0.15, 0.95}
local HEADER_H, FOOT_H, BTN = 20, 12, 16
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
local function call(fn, ...) if type(fn) == "function" then return fn(...) end end

--- The windows' settings, made from the old single window (and the old threat window) the first time.
function M.Windows()
    local s = settings()
    if type(s.windows) ~= "table" then
        s.windows = {}
        if s.enabled then s.windows[1] = {view = s.mode or "damage", point = s.point, width = s.width, height = s.height} end
        if s.threat then s.windows[#s.windows + 1] = {view = "threat", point = s.threatPoint, width = 220, height = 120}; s.enabled = true end
    end
    return s.windows
end
M.live = {}

local function viewOf(cfg) return BY_KEY[cfg.view or ""] or M.MODES[1] end
local function isPlugin(cfg) return viewOf(cfg).plugin ~= nil end
local function locked() return settings().locked == true end

local function popup(w, owner, items)
    local f = w.frame
    local m = f.menu
    if not m then
        m = CreateFrame("Frame", nil, f); m:SetFrameStrata("DIALOG"); m:EnableMouse(true)
        m.bg = m:CreateTexture(nil, "BACKGROUND"); m.bg:SetAllPoints(m); paint(m.bg, {0.06, 0.06, 0.09}, 0.97)
        m.rows = {}
        f.menu = m
    end
    if m:IsShown() and m.owner == owner then m:Hide(); return end
    m.owner = owner
    local width = 170
    for i, item in ipairs(items) do
        local r = m.rows[i]
        if not r then
            r = CreateFrame("Button", nil, m); r:SetHeight(18)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(r); paint(r.hl, C.gold, 0.14)
            r.icon = A.Theme.Glyph(r, "check", 12, C.mist); r.icon:SetPoint("LEFT", 6, 0)
            r.text = kit.label(r, 11, C.text); r.text:SetPoint("LEFT", 24, 0)
            if r.text.SetWordWrap then r.text:SetWordWrap(false) end
            r:SetScript("OnClick", function(self) if not self.fn then return end; m:Hide(); pcall(self.fn); M.Request() end)
            m.rows[i] = r
        end
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 3, -3 - (i - 1) * 18); r:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * 18)
        r.text:SetText(item.text); r.fn = item.onClick
        if item.head then paint(r.text, C.gold); r.hl:SetAlpha(0) else paint(r.text, item.checked and C.bright or C.text); r.hl:SetAlpha(1) end
        r.icon:SetShown(item.icon ~= nil)
        if item.icon then A.Theme.Art(r.icon, item.icon, item.checked and C.gold or C.mist) end
        width = math.max(width, math.floor((r.text:GetStringWidth() or 0) + 34))
        r:Show()
    end
    for i = #items + 1, #m.rows do m.rows[i]:Hide() end
    m:SetSize(width, #items * 18 + 6)
    m:ClearAllPoints(); m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    m:Show()
end

local function headButton(f, art, tip, fn)
    local b = CreateFrame("Button", nil, f.head); b:SetSize(BTN, BTN)
    b.icon = A.Theme.Glyph(b, art, BTN - 4, C.mist); b.icon:SetPoint("CENTER")
    b:SetScript("OnEnter", function()
        paint(b.icon, C.bright)
        if GameTooltip then pcall(function() GameTooltip:SetOwner(b, "ANCHOR_TOP"); GameTooltip:SetText(A.L(type(tip) == "function" and tip() or tip)); GameTooltip:Show() end) end
    end)
    b:SetScript("OnLeave", function() paint(b.icon, b.tint or C.mist); if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", fn)
    return b
end

local function savePoint(w)
    local f = w.frame
    local p, _, rel, x, y = f:GetPoint(1)
    w.cfg.point = {p, rel, x, y}
    w.cfg.width, w.cfg.height = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
end

local Window = {}
Window.__index = Window

function Window:Build()
    if self.frame then return self.frame end
    kit = kit or A.UIKit(); C = C or kit.C
    local w, cfg = self, self.cfg
    local f = CreateFrame("Frame", "EvertallyMeter" .. self.index, UIParent)
    self.frame = f
    f:SetSize(cfg.width or 300, cfg.height or 200)
    if type(cfg.point) == "table" then f:SetPoint(cfg.point[1] or "CENTER", UIParent, cfg.point[2] or "CENTER", cfg.point[3] or 0, cfg.point[4] or 0)
    else f:SetPoint("RIGHT", UIParent, "RIGHT", -40, -120 + (self.index - 1) * 230) end
    f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
    if f.SetResizable then f:SetResizable(true) end
    if f.SetResizeBounds then pcall(f.SetResizeBounds, f, 180, 80, 800, 800) end
    f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(f); paint(f.bg, BG, BG[4])
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr) if not locked() then fr:StartMoving() end end)
    f:SetScript("OnDragStop", function(fr) fr:StopMovingOrSizing(); savePoint(w) end)
    -- the header: the view (a click: the views), then the buttons from the right
    f.head = CreateFrame("Frame", nil, f); f.head:SetHeight(HEADER_H); f.head:SetPoint("TOPLEFT"); f.head:SetPoint("TOPRIGHT")
    f.head.bg = f.head:CreateTexture(nil, "BACKGROUND"); f.head.bg:SetAllPoints(f.head); paint(f.head.bg, HEAD, HEAD[4])
    f.icon = A.Theme.Glyph(f.head, "icon-kill", 13, C.gold); f.icon:SetPoint("LEFT", 5, 0)
    f.title = CreateFrame("Button", nil, f.head); f.title:SetHeight(HEADER_H); f.title:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    f.title.text = kit.label(f.title, 11, C.bright); f.title.text:SetPoint("LEFT", 0, 0); f.title.text:SetPoint("RIGHT", 0, 0)
    f.title.text:SetJustifyH("LEFT"); if f.title.text.SetWordWrap then f.title.text:SetWordWrap(false) end
    f.title:SetScript("OnClick", function(b) w:ViewMenu(b) end)
    f.close = headButton(f, "close", "mtCloseWindow", function() M.CloseWindow(w.index) end); f.close:SetPoint("RIGHT", -3, 0)
    f.new = headButton(f, "window", "mtNewWindow", function() M.AddWindow(nil, w.index) end); f.new:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
    f.reset = headButton(f, "reset", "mtReset", function() M.Reset(); A.Print(A.L("mtResetDone")) end); f.reset:SetPoint("RIGHT", f.new, "LEFT", -2, 0)
    f.seg = headButton(f, "hourglass", "mtSegMenu", function(b) w:SegMenu(b) end); f.seg:SetPoint("RIGHT", f.reset, "LEFT", -2, 0)
    f.title:SetPoint("RIGHT", f.seg, "LEFT", -4, 0)
    f.note = kit.label(f, 11, C.mist); f.note:SetPoint("TOPLEFT", 6, -HEADER_H - 6); f.note:SetPoint("TOPRIGHT", -6, -HEADER_H - 6)
    f.note:SetJustifyH("LEFT")
    f.rows = {}
    -- the foot: the lock (all windows) and the size grip
    f.lock = CreateFrame("Button", nil, f); f.lock:SetSize(FOOT_H + 2, FOOT_H + 2); f.lock:SetPoint("BOTTOMLEFT", 2, 1)
    f.lock.icon = A.Theme.Glyph(f.lock, "lock", FOOT_H, C.faint or C.mist); f.lock.icon:SetPoint("CENTER")
    f.lock:SetScript("OnClick", function() M.SetLocked(not locked()) end)
    f.lock:SetScript("OnEnter", function(b) if GameTooltip then pcall(function() GameTooltip:SetOwner(b, "ANCHOR_TOP"); GameTooltip:SetText(A.L(locked() and "mtUnlock" or "mtLock")); GameTooltip:Show() end) end end)
    f.lock:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.grip = CreateFrame("Button", nil, f); f.grip:SetSize(FOOT_H + 2, FOOT_H + 2); f.grip:SetPoint("BOTTOMRIGHT", -1, 1)
    f.grip.icon = A.Theme.Glyph(f.grip, "resize", FOOT_H, C.faint or C.mist); f.grip.icon:SetPoint("CENTER")
    f.grip:SetScript("OnMouseDown", function() if not locked() then f:StartSizing("BOTTOMRIGHT") end end)
    f.grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); savePoint(w); M.Request() end)
    f:SetScript("OnSizeChanged", function() M.Request() end)
    return f
end

function Window:ViewMenu(owner)
    local items = {}
    for _, grp in ipairs(M.GROUPS) do
        items[#items + 1] = {text = A.L(grp.label), head = true}
        for _, m in ipairs(M.MODES) do
            if m.group == grp.key then
                local key = m.key
                items[#items + 1] = {text = A.L(m.label), icon = m.icon, checked = self.cfg.view == key,
                    onClick = function() self.cfg.view = key; self.detail = nil end}
            end
        end
    end
    popup(self, owner, items)
end

function Window:SegMenu(owner)
    local items = {}
    for i, sg in ipairs(M.Segments()) do
        local seg = sg
        items[#items + 1] = {text = sg.label .. (sg.seconds and ("  " .. M.Clock(sg.seconds)) or ""), icon = "hourglass",
            checked = (self.segIndex or 1) == i, onClick = function() self.segIndex = i; self.segment = seg; self.detail = nil end}
    end
    items[#items + 1] = {text = A.L("mtReset"), icon = "reset", onClick = function() M.Reset(); A.Print(A.L("mtResetDone")) end}
    popup(self, owner, items)
end

-- One row: a class-coloured bar, "1. Name" on the left, the amount and the extra on the right.
local function rowOf(w, i)
    local f = w.frame
    local r = f.rows[i]
    if r then return r end
    local ROW = 18
    r = CreateFrame("Button", nil, f); r:SetHeight(ROW - 1)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(r); paint(r.bg, {1, 1, 1}, 0.04)
    r.bar = CreateFrame("StatusBar", nil, r); r.bar:SetAllPoints(r)
    r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8"); r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(0)
    r.rank = kit.label(r.bar, 11, C.text); r.rank:SetPoint("LEFT", 4, 0); r.rank:SetJustifyH("LEFT")
    r.name = kit.label(r.bar, 11, C.text); r.name:SetPoint("LEFT", r.rank, "RIGHT", 2, 0); r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.extra = kit.label(r.bar, 11, C.text); r.extra:SetPoint("RIGHT", -4, 0); r.extra:SetJustifyH("RIGHT")
    r.amount = kit.label(r.bar, 11, C.text); r.amount:SetPoint("RIGHT", r.extra, "LEFT", -8, 0); r.amount:SetJustifyH("RIGHT")
    r.name:SetPoint("RIGHT", r.amount, "LEFT", -6, 0)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function() if not locked() then f:StartMoving() end end)
    r:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePoint(w) end)
    r:SetScript("OnClick", function(self, button)
        local mode = viewOf(w.cfg)
        if button == "RightButton" then w.detail = nil
        elseif self.data and not self.data.secret and not mode.deaths and not mode.plugin then w.detail = self.data end
        M.Request()
    end)
    r:SetScript("OnEnter", function(self) w:Tooltip(self) end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.rows[i] = r
    return r
end

local function spellIcon(id)
    local S = g("C_Spell")
    if type(S) == "table" and S.GetSpellTexture and type(id) == "number" then
        local ok, tex = pcall(S.GetSpellTexture, id)
        if ok and tex then return "|T" .. tostring(tex) .. ":14:14:0:0:64:64:5:59:5:59|t " end
    end
    return ""
end

--- The hover: the player's spells (name, amount, per second, %) and their targets, as after the fight.
function Window:Tooltip(r)
    local GT = g("GameTooltip")
    local mode = viewOf(self.cfg)
    if not (GT and r.data) or self.detail or mode.plugin or mode.deaths then return end
    pcall(function()
        GT:SetOwner(r, "ANCHOR_LEFT")
        GT:AddLine(r.data.name, 1, 1, 1)
        if r.data.secret then GT:AddLine(A.L("mtInCombat"), 0.7, 0.7, 0.75); GT:Show(); return end
        local spells = M.Spells(mode.key, self.segment or M.Segments()[1], r.data)
        GT:AddDoubleLine(A.L("mtSpellCol"), A.L("mtAmountCol") .. "   " .. A.L("mtPsCol") .. "   %", 0.85, 0.69, 0.4, 0.85, 0.69, 0.4)
        for i = 1, math.min(#spells, 10) do
            local sp = spells[i]
            GT:AddDoubleLine(spellIcon(sp.spellID) .. sp.name .. (sp.creature and (" (" .. sp.creature .. ")") or ""),
                M.Format(sp.amount) .. "   " .. (sp.perSecond and M.Format(sp.perSecond) or "-") .. "   " .. string.format("%.1f%%", (sp.pct or 0) * 100),
                1, 1, 1, 1, 1, 1)
        end
        local targets = spells.targets or {}
        if #targets > 0 then
            GT:AddLine(" ")
            GT:AddDoubleLine(A.L("mtTargets"), A.L("mtAmountCol") .. "   %", 0.85, 0.69, 0.4, 0.85, 0.69, 0.4)
            for i = 1, math.min(#targets, 6) do
                local tg = targets[i]
                GT:AddDoubleLine(tg.name, M.Format(tg.amount) .. "   " .. string.format("%.1f%%", (tg.pct or 0) * 100), 1, 1, 1, 1, 1, 1)
            end
        end
        GT:Show()
    end)
end

local function drawRows(w, list, maxValue)
    local f = w.frame
    local top = HEADER_H + 2
    local room = math.max(1, math.floor((f:GetHeight() - top - FOOT_H - 2) / 18))
    local n = math.min(#list, room)
    for i = 1, n do
        local d = list[i]
        local r = rowOf(w, i)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 1, -top - (i - 1) * 18); r:SetPoint("TOPRIGHT", -1, -top - (i - 1) * 18)
        r.data = d.row
        local c = d.color or C.lilac
        r.bar:SetStatusBarColor(c[1], c[2], c[3], 0.75)
        if d.secret then
            if not pcall(r.bar.SetMinMaxValues, r.bar, 0, maxValue) then r.bar:SetMinMaxValues(0, 1) end
            if not pcall(r.bar.SetValue, r.bar, d.value) then r.bar:SetValue(0) end
        else
            r.bar:SetMinMaxValues(0, 1); r.bar:SetValue(d.share or 0)
        end
        r.rank:SetText(d.noRank and "" or (i .. "."))
        setText(r.name, d.name)
        local amount = d.amount
        if not secret(amount) and amount == nil then amount = "" end
        setText(r.amount, amount)
        local extra = d.extra
        if not secret(extra) and extra == nil then extra = "" end
        setText(r.extra, extra)
        r:Show()
    end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end
end

-- The plugins' rows: threat on the target, the tanks' health.
local function threatList()
    local T = A.ThreatMeter
    if not T then return {}, "none" end
    local rows, state = T.Rows("target")
    local out = {}
    for _, d in ipairs(rows) do
        local e = {name = d.name, color = classColor(d.class), secret = d.secret, value = d.pct, noRank = false}
        if d.secret then e.amount = d.pct; e.extra = "%"
        else
            local pct = tonumber(d.pct) or 0
            e.share = pct / 100; e.amount = string.format("%d%%", math.floor(pct + 0.5)); e.extra = d.tanking == true and "TANK" or ""
            if d.tanking ~= true and pct >= 80 then e.color = {0.9, 0.25, 0.2} end
        end
        out[#out + 1] = e
    end
    return out, state
end
local function vanguardList()
    local T = A.ThreatMeter
    local units = T and T.Units() or {"player"}
    local out = {}
    for _, unit in ipairs(units) do
        local role = call(g("UnitGroupRolesAssigned"), unit)
        if role == "TANK" or (#units == 1 and unit == "player") then
            local hp, max = call(g("UnitHealth"), unit), call(g("UnitHealthMax"), unit)
            local _, class = call(g("UnitClass"), unit)
            local e = {name = call(g("UnitName"), unit), color = classColor(class), noRank = true}
            if secret(hp) or secret(max) then
                e.secret = true; e.value = hp; e.amount = M.Format(hp); e.extra = ""
            else
                hp, max = tonumber(hp) or 0, tonumber(max) or 0
                e.share = max > 0 and hp / max or 0
                e.amount = M.Format(hp); e.extra = max > 0 and string.format("%d%%", math.floor(hp / max * 100 + 0.5)) or ""
            end
            out[#out + 1] = e
        end
    end
    return out
end

function Window:Refresh()
    local f = self.frame
    if not (f and f:IsShown()) then return end
    local mode = viewOf(self.cfg)
    A.Theme.Art(f.icon, mode.icon or "icon-kill", C.gold)
    f.lock.icon:SetVertexColor(1, 1, 1, 1); A.Theme.Art(f.lock.icon, "lock", locked() and C.gold or (C.faint or C.mist))
    f.grip:SetShown(not locked())
    local segs = M.Segments()
    local seg = self.segment or segs[1]
    local title = A.L(mode.label)
    if mode.plugin then
        f.seg:Hide(); f.reset:Hide()
        if mode.plugin == "threat" then
            local list, state = threatList()
            local target = call(g("UnitName"), "target")
            f.title.text:SetText(title .. (state ~= "none" and target and (": " .. tostring(target)) or ""))
            f.note:SetText(state == "none" and A.L("thNoTarget") or #list == 0 and A.L("thNoThreat") or "")
            drawRows(self, list, 100)
        else
            f.title.text:SetText(title)
            local list = vanguardList()
            f.note:SetText(#list == 0 and A.L("mtNoTanks") or "")
            drawRows(self, list, 1)
        end
        return
    end
    f.seg:Show(); f.reset:Show()
    f.title.text:SetText(title .. "  ·  " .. (seg.label or ""))
    if not M.Available() then f.note:SetText(A.L("mtUnavailable")); drawRows(self, {}, 1); return end
    local key = mode.key
    if self.detail then
        local spells = M.Spells(key, seg, self.detail)
        if #spells == 0 then self.detail = nil else
            f.note:SetText("")
            f.title.text:SetText(string.format(A.L("mtSpells"), tostring(self.detail.name or "")))
            local list, top = {}, spells[1].amount
            for _, sp in ipairs(spells) do
                list[#list + 1] = {name = spellIcon(sp.spellID) .. sp.name .. (sp.creature and (" (" .. sp.creature .. ")") or ""),
                    amount = M.Format(sp.amount), extra = sp.pct and string.format("%.1f%%", sp.pct * 100) or "",
                    share = top > 0 and sp.amount / top or 0, color = classColor(self.detail.class)}
            end
            drawRows(self, list, 1)
            return
        end
    end
    local rows, info = M.Rows(key, seg)
    f.note:SetText(#rows == 0 and A.L("mtNoData") or "")
    local top = 0
    if info and not info.secret then for _, r in ipairs(rows) do top = math.max(top, tonumber(r.amount) or 0) end end
    local list = {}
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
                if not mode.perSecond and not mode.count then e.extra = M.Format(r.perSecond) else e.extra = "" end
            else
                e.share = top > 0 and (tonumber(r.amount) or 0) / top or 0
                local ps = (not mode.perSecond and not mode.count) and r.perSecond and M.Format(r.perSecond) or nil
                local pct = r.pct and string.format("%.1f%%", r.pct * 100) or nil
                e.extra = ps and pct and (ps .. "  " .. pct) or pct or ""
            end
        end
        list[#list + 1] = e
    end
    drawRows(self, list, info and info.max or 1)
end

local function windowAt(i)
    local list = M.Windows()
    local cfg = list[i]
    if not cfg then return nil end
    local w = M.live[i]
    if not w or w.cfg ~= cfg then
        if w and w.frame then w.frame:Hide() end
        w = setmetatable({index = i, cfg = cfg}, Window)
        M.live[i] = w
    end
    return w
end

--- Shows every window that is on (the meter on, the window not closed), hides the others.
function M.Update()
    M.Windows()   -- (first: the old settings move over, which may switch the meter on)
    local on = M.Enabled()
    for i = 1, #M.Windows() do
        local w = windowAt(i)
        local mode = viewOf(w.cfg)
        local show = on and not w.cfg.hidden
        -- a threat window "only in a group" waits for one
        if show and mode.plugin == "threat" and settings().threatGroupOnly == true and (tonumber(call(g("GetNumGroupMembers"))) or 0) == 0 then show = false end
        if show then w:Build():Show(); w:Refresh() elseif w.frame then w.frame:Hide() end
    end
    for i = #M.Windows() + 1, #M.live do if M.live[i] and M.live[i].frame then M.live[i].frame:Hide() end; M.live[i] = nil end
    local first = M.live[1]
    M.frame = first and first.frame or nil
    if A.ThreatMeter then
        local i = M.WindowWith("threat")
        A.ThreatMeter.frame = i and M.live[i] and M.live[i].frame or nil
    end
end

--- A new window (beside `from`, or the view given): it opens with the damage done unless asked otherwise.
function M.AddWindow(view, from)
    if not A.db then return nil end
    local list = M.Windows()
    local cfg = {view = view or "damage"}
    local src = from and M.live[from] and M.live[from].frame
    if src then
        local p, _, rel, x, y = src:GetPoint(1)
        cfg.point = {p, rel, (x or 0) - (src:GetWidth() + 6), y}
        cfg.width, cfg.height = math.floor(src:GetWidth() + 0.5), math.floor(src:GetHeight() + 0.5)
    end
    list[#list + 1] = cfg
    settings().enabled = true
    M.Update()
    return #list
end
--- Closes a window for good (its place in the list goes).
function M.CloseWindow(i)
    local list = M.Windows()
    if not list[i] then return end
    if M.live[i] and M.live[i].frame then M.live[i].frame:Hide() end
    table.remove(list, i)
    for k = i, #M.live do if M.live[k] and M.live[k].frame then M.live[k].frame:Hide() end; M.live[k] = nil end
    M.Update()
end
--- The first window showing `view`, or nil.
function M.WindowWith(view)
    for i, cfg in ipairs(M.Windows()) do if cfg.view == view then return i end end
    return nil
end

--- Redraws every window.
function M.Refresh()
    for i = 1, #M.Windows() do local w = M.live[i]; if w then pcall(w.Refresh, w) end end
end

-- One redraw a moment after a burst of updates.
local pending = false
function M.Request()
    if pending then return end
    pending = true
    local run = function() pending = false; M.Refresh() end
    local t = g("C_Timer")
    if type(t) == "table" and t.After then t.After(0.25, run) else run() end
end

function M.Enabled() return settings().enabled == true end
--- On: the windows show (a first one with the damage done when there is none); off: they hide.
function M.SetEnabled(on)
    if not A.db then return end
    settings().enabled = on == true
    if on then
        M.Available()
        local any = false
        for _, cfg in ipairs(M.Windows()) do if not cfg.hidden and not isPlugin(cfg) then any = true end end
        if not any then
            local i = M.WindowWith("damage")
            if i then M.Windows()[i].hidden = nil else M.AddWindow("damage") end
        end
    end
    M.Update()
end
M.SetShown = M.SetEnabled
--- /etally meter: the meter's windows on or off.
function M.Toggle()
    local shown = false
    for i = 1, #M.Windows() do local w = M.live[i]; if w and w.frame and w.frame:IsShown() and not viewOf(w.cfg).plugin then shown = true end end
    if shown then
        for _, cfg in ipairs(M.Windows()) do if not isPlugin(cfg) then cfg.hidden = true end end
        M.Update()
    else
        for _, cfg in ipairs(M.Windows()) do if not isPlugin(cfg) then cfg.hidden = nil end end
        M.SetEnabled(true)
    end
end
function M.SetLocked(on) settings().locked = on == true; M.Refresh() end

A.On("PLAYER_LOGIN", function() if A.db then M.Update() end end)
for _, ev in ipairs({"DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_HEALTH", "PLAYER_TARGET_CHANGED", "UNIT_THREAT_LIST_UPDATE",
    "UNIT_THREAT_SITUATION_UPDATE"}) do
    A.On(ev, function()
        -- a new fight starts on the current one again
        if ev == "PLAYER_REGEN_DISABLED" then for _, w in pairs(M.live) do w.detail = nil end end
        M.Request()
    end)
end
A.On("GROUP_ROSTER_UPDATE", function() M.Update() end)
-- threat and health move without an event for every hit: a light refresh while a fight is on
local ticker
A.On("PLAYER_REGEN_DISABLED", function()
    local t = g("C_Timer")
    if ticker or not (type(t) == "table" and t.NewTicker) then return end
    ticker = t.NewTicker(0.5, function()
        if call(g("InCombatLockdown")) ~= true then ticker:Cancel(); ticker = nil end
        M.Refresh()
    end)
end)
