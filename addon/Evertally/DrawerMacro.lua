local _, A = ...
-- Drawers: a macro on the action bar opens a row of buttons (items, spells, macros, mounts) next to it, also in combat.
-- settings.drawers = {{name, entries = {{kind = "item"|"spell"|"macro"|"mount", id, name}}}}, edited in the drawers'
-- window (/etally drawer, or Actions in the settings): drag an item, a spell, a macro or a mount onto a slot,
-- right-click takes it off. "Make the macro" writes a macro "#evertally:drawer N / /click EvertallyDrawerN" and puts it
-- on the cursor for the action bar.
-- Secure: EvertallyDrawerN is a SecureActionButton (AnyUp and AnyDown registered, as the guide's step key: the player's
-- key-down setting picks which one acts, once) of type "click" on a SecureHandlerClickTemplate whose snippet shows or
-- hides the tray; each entry is a SecureActionButton, and a click on one hides the tray (a wrapped OnClick). Attributes
-- and the tray's place are set out of combat only (a change in combat waits for PLAYER_REGEN_ENABLED).
local DM = {}
A.Drawers = DM

local MAX_DRAWERS, MAX_ENTRIES, SLOT, GAP = 6, 12, 36, 4

local text = {
    en = {drawerEdit = "Drawers (a macro that opens a row of buttons)", dmTitle = "Drawers", dmNew = "New drawer", dmName = "Drawer %d",
        dmHint = "Drag an item, a spell, a macro or a mount onto a slot; right-click clears it. Make the macro and put it on your action bar: it opens the drawer, in combat too.",
        dmMacro = "Make the macro", dmMacroDone = "The macro %s is on your cursor: put it on the action bar.", dmMacroFull = "No room for another macro.",
        dmCombat = "The drawer changes after the fight.", dmDelete = "Delete the drawer", dmEmpty = "Drop here"},
    cs = {drawerEdit = "Šuplíky (makro, které otevře řadu tlačítek)", dmTitle = "Šuplíky", dmNew = "Nový šuplík", dmName = "Šuplík %d",
        dmHint = "Přetáhni na slot předmět, kouzlo, makro nebo mounta; pravý klik ho vyprázdní. Vytvoř makro a dej ho na akční lištu: otevře šuplík, i v boji.",
        dmMacro = "Vytvořit makro", dmMacroDone = "Makro %s máš na kurzoru: polož ho na akční lištu.", dmMacroFull = "Na další makro už není místo.",
        dmCombat = "Šuplík se změní po boji.", dmDelete = "Smazat šuplík", dmEmpty = "Pusť sem"},
}
for lang, entries in pairs(text) do for k, v in pairs(entries) do A.locale[lang][k] = v end end

local function g(name) return rawget(_G, name) end
local function call(fn, ...) if type(fn) == "function" then return fn(...) end end
local function inCombat() return call(g("InCombatLockdown")) == true end

function DM.List()
    local s = A.db and A.db.settings
    if not s then return {} end
    if type(s.drawers) ~= "table" then s.drawers = {} end
    return s.drawers
end
function DM.Add()
    local list = DM.List()
    if #list >= MAX_DRAWERS then return nil end
    list[#list + 1] = {name = string.format(A.L("dmName"), #list + 1), entries = {}}
    DM.Apply()
    return #list
end
function DM.Remove(i)
    local list = DM.List()
    if not list[i] then return false end
    table.remove(list, i)
    DM.Apply()
    return true
end

-- ---------------------------------------------------------------- an entry from the cursor
--- What is on the cursor as an entry, or nil.
function DM.FromCursor()
    local what, a, b, c = call(g("GetCursorInfo"))
    if what == "item" and tonumber(a) then return {kind = "item", id = tonumber(a)} end
    if what == "spell" then
        local id = tonumber(c)
        if not id and a and b then
            local _, sid = call(g("GetSpellBookItemInfo"), a, b)
            id = tonumber(sid)
        end
        if id then return {kind = "spell", id = id} end
    end
    if what == "macro" and tonumber(a) then
        local name = call(g("GetMacroInfo"), tonumber(a))
        if type(name) == "string" then return {kind = "macro", name = name} end
    end
    if what == "mount" and tonumber(a) then return {kind = "mount", id = tonumber(a)} end
    return nil
end
function DM.Icon(e)
    if type(e) ~= "table" then return nil end
    if e.kind == "item" then return call(g("GetItemIcon"), e.id) end
    if e.kind == "spell" then return call(g("GetSpellTexture"), e.id) end
    if e.kind == "macro" then local _, icon = call(g("GetMacroInfo"), e.name); return icon end
    if e.kind == "mount" then
        local MJ = g("C_MountJournal")
        if MJ and MJ.GetMountInfoByID then local _, _, icon = MJ.GetMountInfoByID(e.id); return icon end
    end
end
--- The secure attributes of an entry: {type, key, value} (nil: nothing to do).
function DM.Action(e)
    if type(e) ~= "table" then return nil end
    if e.kind == "item" then return "item", "item", "item:" .. tostring(e.id) end
    if e.kind == "spell" then
        local name = call(g("GetSpellInfo"), e.id)
        return "spell", "spell", name or e.id
    end
    if e.kind == "macro" then return "macro", "macro", e.name end
    if e.kind == "mount" then return "macro", "macrotext", "/run C_MountJournal.SummonByID(" .. tostring(e.id) .. ")" end
end

-- ---------------------------------------------------------------- the secure frames
local frames = {}   -- [i] = {toggle, handler, tray, buttons = {}}
local pending = false
local function trayFor(i)
    local f = frames[i]
    if f then return f end
    f = {buttons = {}}
    local handler = CreateFrame("Button", "EvertallyDrawerHandler" .. i, UIParent, "SecureHandlerClickTemplate")
    local tray = CreateFrame("Frame", "EvertallyDrawerTray" .. i, UIParent)
    tray:SetSize(SLOT, SLOT); tray:SetFrameStrata("DIALOG"); tray:Hide()
    tray:SetPoint("CENTER")
    if handler.SetFrameRef then handler:SetFrameRef("tray", tray) end
    handler:SetAttribute("_onclick", [[ local tray = self:GetFrameRef("tray"); if tray:IsShown() then tray:Hide() else tray:Show() end ]])
    local toggle = CreateFrame("Button", "EvertallyDrawer" .. i, UIParent, "SecureActionButtonTemplate")
    toggle:RegisterForClicks("AnyUp", "AnyDown")
    toggle:SetAttribute("type", "click")
    toggle:SetAttribute("clickbutton", handler)
    -- out of combat the tray opens by the cursor (the action button pressed); in combat where it last was
    toggle:HookScript("PreClick", function()
        if inCombat() then return end
        local x, y = call(g("GetCursorPosition"))
        local scale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if x and y then tray:ClearAllPoints(); tray:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale - SLOT / 2, y / scale + 18) end
    end)
    f.toggle, f.handler, f.tray = toggle, handler, tray
    frames[i] = f
    return f
end
local function slotButton(f, i, k)
    local b = f.buttons[k]
    if b then return b end
    b = CreateFrame("Button", "EvertallyDrawer" .. i .. "Slot" .. k, f.tray, "SecureActionButtonTemplate")
    b:SetSize(SLOT, SLOT)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(b); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(b); hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", function(self)
        local e = self.entry
        if not (e and GameTooltip) then return end
        pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if e.kind == "item" then GameTooltip:SetHyperlink("item:" .. e.id)
            elseif e.kind == "spell" and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(e.id)
            else GameTooltip:SetText(e.name or tostring(e.id)) end
            GameTooltip:Show()
        end)
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local wrap = g("SecureHandlerWrapScript")
    if wrap then pcall(wrap, b, "OnClick", f.handler, nil, [[ local tray = owner:GetFrameRef("tray"); if tray then tray:Hide() end ]]) end
    f.buttons[k] = b
    return b
end
--- Sets every drawer's buttons from the settings (out of combat; in combat after it).
function DM.Apply()
    if inCombat() then pending = true; return false end
    pending = false
    for i, d in ipairs(DM.List()) do
        local f = trayFor(i)
        local entries = type(d.entries) == "table" and d.entries or {}
        local n = 0
        for k = 1, MAX_ENTRIES do
            local e = entries[k]
            local b = f.buttons[k]
            if e then
                b = slotButton(f, i, k)
                local typ, key, value = DM.Action(e)
                b:SetAttribute("type", typ); b:SetAttribute("item", nil); b:SetAttribute("spell", nil); b:SetAttribute("macro", nil); b:SetAttribute("macrotext", nil)
                if key then b:SetAttribute(key, value) end
                b.entry = e
                b.icon:SetTexture(DM.Icon(e) or 134400)
                local cnt = e.kind == "item" and tonumber(call(g("GetItemCount"), e.id)) or nil
                b.count:SetText(cnt and cnt > 1 and tostring(cnt) or "")
                b:ClearAllPoints(); b:SetPoint("LEFT", f.tray, "LEFT", n * (SLOT + GAP), 0)
                b:Show()
                n = n + 1
            elseif b then
                b:SetAttribute("type", nil); b.entry = nil; b:Hide()
            end
        end
        f.tray:SetWidth(math.max(SLOT, n * (SLOT + GAP) - GAP))
    end
    for i = #DM.List() + 1, MAX_DRAWERS do
        local f = frames[i]
        if f then f.tray:Hide(); for _, b in pairs(f.buttons) do b:SetAttribute("type", nil); b.entry = nil; b:Hide() end end
    end
    return true
end

-- ---------------------------------------------------------------- the macro
function DM.MacroBody(i) return "#evertally:drawer " .. i .. "\n/click EvertallyDrawer" .. i end
--- Makes (or finds) drawer i's macro and puts it on the cursor.
function DM.MakeMacro(i)
    local d = DM.List()[i]
    if not d or inCombat() then return false end
    local name = (d.name or ("Drawer " .. i)):sub(1, 16)
    local index = tonumber(call(g("GetMacroIndexByName"), name)) or 0
    if index == 0 then
        local icon = DM.Icon((d.entries or {})[1]) or 134400
        local ok, made = pcall(g("CreateMacro"), name, icon, DM.MacroBody(i), nil)
        index = ok and tonumber(made) or 0
        if index == 0 then A.Print(A.L("dmMacroFull")); return false end
    else
        pcall(g("EditMacro"), index, name, nil, DM.MacroBody(i))
    end
    call(g("PickupMacro"), index)
    A.Print(string.format(A.L("dmMacroDone"), name))
    return true
end

-- ---------------------------------------------------------------- the editor
local kit, C, win
local function paint(t, c, a)
    if t.SetTextColor and not t.SetTexture then t:SetTextColor(c[1], c[2], c[3], a or c[4] or 1); return end
    kit.paint(t, c, a)
end
local function setEntry(i, k, e)
    local d = DM.List()[i]
    if not d then return end
    d.entries = d.entries or {}
    if e then
        if k > #d.entries + 1 then k = #d.entries + 1 end
        d.entries[k] = e
    else
        table.remove(d.entries, k)
    end
    if inCombat() and A.Print then A.Print(A.L("dmCombat")) end
    DM.Apply()
    DM.Refresh()
end

local function drawerRow(i)
    win.rows = win.rows or {}
    local r = win.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, win); r:SetSize(MAX_ENTRIES * (SLOT + GAP) + 20, 72)
    r.name = CreateFrame("EditBox", nil, r); r.name:SetSize(200, 22); r.name:SetPoint("TOPLEFT", 0, 0); r.name:SetAutoFocus(false)
    if r.name.SetFont then r.name:SetFont(kit.fontPath("body"), 12, "") end
    if r.name.SetTextInsets then r.name:SetTextInsets(8, 8, 0, 0) end
    r.name:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    r.name.bg = r.name:CreateTexture(nil, "BACKGROUND"); r.name.bg:SetAllPoints(r.name); paint(r.name.bg, C.well or C.card, 1)
    kit.outline(r.name, C.line)
    local function saveName(self) local d = DM.List()[r.i]; local t = self:GetText() or ""; if d and t:match("%S") then d.name = t end end
    r.name:SetScript("OnEnterPressed", function(self) saveName(self); self:ClearFocus() end)
    r.name:SetScript("OnEditFocusLost", saveName)
    r.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    r.macro = kit.Button(r, "dmMacro", 140, "primary", function() DM.MakeMacro(r.i) end)
    r.macro:SetHeight(24); r.macro:SetPoint("LEFT", r.name, "RIGHT", 10, 0)
    if r.macro.text then r.macro.text:SetText(A.L("dmMacro")) end
    r.del = kit.IconButton(r, "close", 22, function() DM.Remove(r.i); DM.Refresh() end, "dmDelete")
    r.del:SetPoint("LEFT", r.macro, "RIGHT", 6, 0)
    r.slots = {}
    for k = 1, MAX_ENTRIES do
        local s = CreateFrame("Button", nil, r); s:SetSize(SLOT, SLOT)
        s:SetPoint("TOPLEFT", (k - 1) * (SLOT + GAP), -30)
        s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        s.well = s:CreateTexture(nil, "BACKGROUND"); s.well:SetAllPoints(s); paint(s.well, C.well or C.card, 1)
        kit.outline(s, C.line)
        s.icon = s:CreateTexture(nil, "ARTWORK"); s.icon:SetPoint("TOPLEFT", 2, -2); s.icon:SetPoint("BOTTOMRIGHT", -2, 2); s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        s.plus = A.Theme.Glyph(s, "chevron-down", 12, C.faint); s.plus:SetPoint("CENTER")
        local function drop()
            local e = DM.FromCursor()
            if e then setEntry(r.i, s.k, e); call(g("ClearCursor")); return true end
        end
        s:SetScript("OnReceiveDrag", drop)
        s:SetScript("OnClick", function(_, button)
            if drop() then return end
            if button == "RightButton" then setEntry(r.i, s.k, nil) end
        end)
        s:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            pcall(function() GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(A.L("dmEmpty")); GameTooltip:Show() end)
        end)
        s:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        s.k = k
        r.slots[k] = s
    end
    win.rows[i] = r
    return r
end

function DM.Refresh()
    if not (win and win:IsShown()) then return end
    local list = DM.List()
    local y = win.top
    for i, d in ipairs(list) do
        local r = drawerRow(i)
        r.i = i
        if not r.name:HasFocus() then r.name:SetText(d.name or "") end
        local entries = d.entries or {}
        for k, s in ipairs(r.slots) do
            local e = entries[k]
            s.icon:SetTexture(e and (DM.Icon(e) or 134400) or nil)
            s.icon:SetShown(e ~= nil)
            s.plus:SetShown(e == nil and k == #entries + 1)
            s:SetAlpha((e or k == #entries + 1) and 1 or 0.35)
        end
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 16, -y); r:Show()
        y = y + 80
    end
    for i = #list + 1, #(win.rows or {}) do win.rows[i]:Hide() end
    win.add:SetShown(#list < MAX_DRAWERS)
    win:SetHeight(y + 50)
end

function DM.Show()
    if not win then
        kit = kit or A.UIKit(); C = C or kit.C
        win = CreateFrame("Frame", "EvertallyDrawers", UIParent)
        win:SetWidth(MAX_ENTRIES * (SLOT + GAP) + 32); win:SetFrameStrata("HIGH"); win:SetToplevel(true); win:SetClampedToScreen(true)
        win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
        A.NativeFrame(win, C)
        win.title = kit.label(win, 15, C.bright); win.title:SetPoint("TOPLEFT", 16, -14)
        win.close = kit.IconButton(win, "close", 24, function() win:Hide() end, "bwClose"); win.close:SetPoint("TOPRIGHT", -10, -10)
        win.hint = kit.label(win, 11, C.mist); win.hint:SetPoint("TOPLEFT", 16, -40); win.hint:SetWidth(MAX_ENTRIES * (SLOT + GAP))
        win.hint:SetJustifyH("LEFT"); if win.hint.SetWordWrap then win.hint:SetWordWrap(true) end
        win.add = kit.Button(win, "dmNew", 150, "ghost", function() DM.Add(); DM.Refresh() end)
        win.add:SetHeight(26); win.add:SetPoint("BOTTOMLEFT", 16, 14)
        if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "EvertallyDrawers") end
        win:SetPoint("CENTER")
    end
    win.title:SetText(A.L("dmTitle")); win.hint:SetText(A.L("dmHint"))
    if win.add.text then win.add.text:SetText(A.L("dmNew")) end
    win.top = 40 + math.ceil(win.hint:GetStringHeight() or 30) + 14
    if #DM.List() == 0 then DM.Add() end
    win:Show()
    DM.Refresh()
end
function DM.Toggle() if win and win:IsShown() then win:Hide() else DM.Show() end end

A.On("PLAYER_LOGIN", function() DM.Apply() end)
A.On("PLAYER_REGEN_ENABLED", function() if pending then DM.Apply() end end)
A.On("BAG_UPDATE_DELAYED", function() if not inCombat() and #DM.List() > 0 then DM.Apply() end end)
