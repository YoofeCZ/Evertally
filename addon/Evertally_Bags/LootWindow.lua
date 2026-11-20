local A = _G.Evertally -- (Evertally_Bags: a module of Evertally since 2026-11-20)
-- Evertally's loot window (settings.lootWindow, off by default; Interface page of the settings). While it is on:
--   * looting by hand: the corpse's items in Evertally's look, a click takes one (LootSlot), Take all, close (CloseLoot);
--   * with auto loot (autoLootDefault, inverted by the auto-loot key): every slot is taken at once, again on a repeat
--     LOOT_READY (the client sometimes leaves one), and what came in shows for a moment ("+3 Silk Cloth"). What could not
--     be taken (full bags, a bind confirmation) stays in the window to take by hand.
-- The game's loot frame stops listening for LOOT_OPENED while the window is on (its other events stay: the master
-- looter's list, the bind confirmations); with master loot the game's frame opens as before. Nothing of Blizzard's is
-- written: only that frame's events are switched (RegisterEvent / UnregisterEvent), and back when the window is off.
local LW = {}
A.LootWindow = LW

local ROW_H, WIDTH, PAD, TOAST_SECONDS = 34, 260, 10, 3.5

local text = {
    en = {lootWindow = "Evertally's loot window", lootWindowHelp = "Loot fast in Evertally's look; with auto loot it shows what you got. Off: the game's loot window.",
        lwTitle = "Loot", lwTakeAll = "Take all", lwClose = "Close", lwMoney = "Money"},
    cs = {lootWindow = "Okno lootu Evertally", lootWindowHelp = "Rychlé sbírání lootu ve vzhledu Evertally; s auto lootem ukáže, co jsi dostal. Vypnuté: herní okno lootu.",
        lwTitle = "Loot", lwTakeAll = "Vzít vše", lwClose = "Zavřít", lwMoney = "Peníze"},
}
for lang, entries in pairs(text) do for k, v in pairs(entries) do A.locale[lang][k] = v end end

local function call(fn, ...) if type(fn) == "function" then return fn(...) end end
local function g(name) return rawget(_G, name) end
local function settings() return A.db and A.db.settings or {} end
function LW.Enabled() return settings().lootWindow == true end

-- ---------------------------------------------------------------- the game's loot frame
local OWN_EVENTS = {"LOOT_OPENED"}
local muted = false
local function gameFrame() local f = g("LootFrame"); return type(f) == "table" and f.UnregisterEvent and f or nil end
local function muteGame(on)
    local f = gameFrame()
    if not f or muted == on then return end
    for _, ev in ipairs(OWN_EVENTS) do pcall(on and f.UnregisterEvent or f.RegisterEvent, f, ev) end
    muted = on
end
function LW.SetEnabled(on)
    if not A.db then return end
    settings().lootWindow = on == true
    muteGame(on == true)
    if not on and LW.frame then LW.frame:Hide() end
end

-- ---------------------------------------------------------------- what the corpse has
local function autoLooting(flag)
    if flag ~= nil then return flag == true or flag == 1 end
    local cvar = call(g("GetCVar"), "autoLootDefault") == "1"
    local key = call(g("IsModifiedClick"), "AUTOLOOTTOGGLE") == true
    return cvar ~= key
end
local function masterLoot()
    local method = call(g("GetLootMethod"))
    return method == "master"
end
--- The slots: {slot, icon, name, count, quality, link, money, locked}
function LW.Slots()
    local out = {}
    local n = tonumber(call(g("GetNumLootItems"))) or 0
    for slot = 1, n do
        local ok, icon, name, count, a4, a5, a6 = pcall(g("GetLootSlotInfo"), slot)
        if ok and (icon or name) then
            -- (the returns moved over the clients: icon, name, quantity, [currencyID], quality, locked)
            local quality, locked = a4, a5
            if type(a6) == "boolean" or (type(a5) == "number" and type(a4) == "number" and a6 ~= nil) then quality, locked = a5, a6 end
            local link = call(g("GetLootSlotLink"), slot)
            local kind = call(g("GetLootSlotType"), slot)
            local money = kind == 2 or (link == nil and (count == 0 or count == nil) and type(name) == "string" and name:find("\n") ~= nil)
            out[#out + 1] = {slot = slot, icon = icon, name = name or "", count = tonumber(count) or 1, quality = tonumber(quality) or 1,
                link = link, money = money, locked = locked == true}
        end
    end
    return out
end

-- ---------------------------------------------------------------- the window
local kit, C
local function paint(t, c, a)
    if t.SetTextColor and not t.SetTexture then t:SetTextColor(c[1], c[2], c[3], a or c[4] or 1); return end
    kit.paint(t, c, a)
end
local function qualityColor(q)
    local qc = g("ITEM_QUALITY_COLORS")
    local c = type(qc) == "table" and qc[q or 1]
    if c then return {c.r, c.g, c.b} end
    return C.text
end

local function build()
    if LW.frame then return LW.frame end
    kit = kit or A.UIKit(); C = C or kit.C
    local f = CreateFrame("Frame", "EvertallyLootWindow", UIParent)
    LW.frame = f
    f:SetWidth(WIDTH); f:SetFrameStrata("DIALOG"); f:SetToplevel(true); f:SetClampedToScreen(true); f:EnableMouse(true); f:SetMovable(true)
    A.NativeFrame(f, C)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rel, x, y = self:GetPoint(1)
        settings().lootPoint = {p, rel, x, y}
    end)
    f.title = kit.label(f, 13, C.bright); f.title:SetPoint("TOPLEFT", PAD + 2, -10)
    f.close = kit.IconButton(f, "close", 22, function() LW.Close() end, "lwClose"); f.close:SetPoint("TOPRIGHT", -6, -6)
    f.all = kit.Button(f, "lwTakeAll", 110, "primary", function() LW.TakeAll() end)
    f.all:SetHeight(24); f.all:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    f.rows = {}
    f:SetScript("OnHide", function(self)
        -- the window closed by hand (Escape, the X) while the corpse is open: the loot closes too
        if self.interactive and LW.open then LW.open = false; call(g("CloseLoot")) end
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "EvertallyLootWindow") end
    f:Hide()
    return f
end

local function row(f, i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, f); r:SetHeight(ROW_H - 2)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(r); paint(r.hl, C.gold, 0.10)
    r.well = r:CreateTexture(nil, "BACKGROUND"); r.well:SetSize(28, 28); r.well:SetPoint("LEFT", 0, 0); paint(r.well, C.well or C.card, 1)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(26, 26); r.icon:SetPoint("CENTER", r.well); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.count = kit.label(r, 11, C.bright); r.count:SetPoint("BOTTOMRIGHT", r.well, "BOTTOMRIGHT", -1, 1)
    r.name = kit.label(r, 12, C.text); r.name:SetPoint("LEFT", r.well, "RIGHT", 8, 0); r.name:SetPoint("RIGHT", -4, 0)
    r.name:SetJustifyH("LEFT"); if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r:SetScript("OnClick", function(self) if self.slot and LW.open then call(g("LootSlot"), self.slot) end end)
    r:SetScript("OnEnter", function(self)
        if self.link and GameTooltip then pcall(function() GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.link); GameTooltip:Show() end) end
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.rows[i] = r
    return r
end

--- Draws a list: interactive (the corpse's slots, a click takes one) or a toast (what came in, "+3 Name").
local function draw(list, interactive)
    local f = build()
    f.interactive = interactive
    f.title:SetText(A.L("lwTitle"))
    local y = 34
    for i, e in ipairs(list) do
        local r = row(f, i)
        r.slot = interactive and e.slot or nil
        r.link = e.link
        r.icon:SetTexture(e.icon or 134400)
        if e.money then
            r.name:SetText((e.name or ""):gsub("\n", " ")); paint(r.name, C.gold); r.count:SetText("")
        elseif interactive then
            r.name:SetText(e.name); paint(r.name, qualityColor(e.quality)); r.count:SetText(e.count > 1 and tostring(e.count) or "")
        else
            r.name:SetText(string.format("+%d  %s", e.count or 1, e.name)); paint(r.name, qualityColor(e.quality)); r.count:SetText("")
        end
        r:EnableMouse(interactive or e.link ~= nil)
        r:SetAlpha(e.locked and 0.5 or 1)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", PAD, -y); r:SetPoint("TOPRIGHT", -PAD, -y)
        r:Show()
        y = y + ROW_H
    end
    for i = #list + 1, #f.rows do f.rows[i]:Hide() end
    f.all:SetShown(interactive and #list > 1)
    f.close:SetShown(interactive)
    f:SetHeight(y + (interactive and #list > 1 and 38 or 8))
    f:SetAlpha(1)
    if not f:IsShown() then
        f:ClearAllPoints()
        local p = settings().lootPoint
        if type(p) == "table" and p[1] then f:SetPoint(p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
        else
            local x, yy = call(g("GetCursorPosition"))
            local scale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if x and yy then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 24, yy / scale + 20) else f:SetPoint("LEFT", UIParent, "CENTER", 120, 0) end
        end
    end
    f:Show()
end

local toastToken = 0
local function toast(list)
    if #list == 0 then return end
    draw(list, false)
    toastToken = toastToken + 1
    local mine = toastToken
    local T = g("C_Timer")
    if T and T.After then T.After(TOAST_SECONDS, function() if mine == toastToken and LW.frame and not LW.frame.interactive then LW.frame:Hide() end end) end
end

-- ---------------------------------------------------------------- the events
LW.open = false
function LW.TakeAll()
    for _, e in ipairs(LW.Slots()) do if not e.locked then call(g("LootSlot"), e.slot) end end
end
function LW.Close()
    LW.open = false
    if LW.frame then LW.frame.interactive = false; LW.frame:Hide() end
    call(g("CloseLoot"))
end

local pendingToast = {}
local lastReady = 0
function LW.OnReady(autoloot)
    if not LW.Enabled() or masterLoot() then return end
    if not autoLooting(autoloot) then return end
    local now = tonumber(call(g("GetTime"))) or 0
    local list = LW.Slots()
    -- what came in is remembered once per corpse (a repeat LOOT_READY only takes again)
    if now - lastReady > 0.5 then
        pendingToast = {}
        for _, e in ipairs(list) do if not e.locked then pendingToast[#pendingToast + 1] = e end end
    end
    lastReady = now
    for slot = #list, 1, -1 do local e = list[slot]; if not e.locked then call(g("LootSlot"), e.slot) end end
end
function LW.OnOpened(autoloot)
    if not LW.Enabled() then return end
    if masterLoot() then
        -- the game's own frame: its handler, as when it listens itself
        local f = gameFrame()
        local h = f and f.GetScript and f:GetScript("OnEvent")
        if h then pcall(h, f, "LOOT_OPENED", autoloot) end
        return
    end
    LW.open = true
    if autoLooting(autoloot) then
        -- taken already (OnReady); what is left (full bags, a confirmation) is taken by hand
        local left = LW.Slots()
        if #left > 0 then draw(left, true) end
        return
    end
    draw(LW.Slots(), true)
end
function LW.OnSlotCleared()
    if LW.frame and LW.frame:IsShown() and LW.frame.interactive then
        local left = LW.Slots()
        local any = false
        for _, e in ipairs(left) do if e.name ~= "" or e.icon then any = true end end
        if any then draw(left, true) else LW.Close() end
    end
end
function LW.OnClosed()
    LW.open = false
    if LW.frame and LW.frame.interactive then LW.frame.interactive = false; LW.frame:Hide() end
    if #pendingToast > 0 then local list = pendingToast; pendingToast = {}; toast(list) end
end

A.On("LOOT_READY", function(autoloot) LW.OnReady(autoloot) end)
A.On("LOOT_OPENED", function(autoloot) LW.OnOpened(autoloot) end)
A.On("LOOT_SLOT_CLEARED", function() LW.OnSlotCleared() end)
A.On("LOOT_CLOSED", function() LW.OnClosed() end)
A.On("PLAYER_LOGIN", function() if LW.Enabled() then muteGame(true) end end)
