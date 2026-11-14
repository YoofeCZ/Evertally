local _, A = ...
-- Small icons beside player names (on the nameplates):
--  * a mark you give to somebody, so you can tell friends from other players at a glance: one of the eight raid icons
--    or any game icon (of a spell or an item). It exists only on this computer: the player never sees it, and a mark
--    somebody gave you is not visible to you. It is drawn smaller than a raid target icon (12 px unless changed).
--  * a tiny Evertally logo for players who are known to run Evertally (they answered with an Evertally message).
-- Everything is drawn by frames of our own laid over the nameplates; nothing is written to Blizzard's frames.
local MARKS = 8
local TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local LOGO = "Interface\\AddOns\\Evertally\\Media\\Logo"
local USER_TTL, MAX_MARKS, MAX_USERS = 30 * 86400, 200, 300
A.MARK_COUNT = MARKS

--- "Name", "Name-Realm" or "Name Realm" all become the same lowercase first word.
local function key(name)
    name = A.Text(name, 150)
    local word = name and name:match("^[^%-%s]+")
    return word and word:lower() or nil
end
A.MarkKey = key

local function settings() return A.db and A.db.settings end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

-- A mark is a raid icon (the number 1..8) or any game icon ("f" and its file id, e.g. "f135940").
local function validMark(mark)
    if mark == nil then return 0 end
    if type(mark) == "number" or (type(mark) == "string" and mark:match("^%d+$")) then
        local n = tonumber(mark)
        return (n and n == math.floor(n) and n >= 0 and n <= MARKS) and n or nil
    end
    if type(mark) == "string" and #mark <= 12 and mark:match("^f[1-9]%d*$") then return mark end
    return nil
end

--- The mark given to a player on this computer (1..8 or "f<file id>"), or nil.
function A.GetMark(name)
    local s, k = settings(), key(name)
    local mark = s and k and s.marks and s.marks[k]
    return mark ~= nil and mark ~= 0 and validMark(mark) or nil
end
--- mark: 1..8, "f<file id>", or 0/nil to clear. Returns true when something was stored or removed.
function A.SetMark(name, mark)
    local s, k = settings(), key(name)
    if not s or not k then return false end
    s.marks = type(s.marks) == "table" and s.marks or {}
    mark = validMark(mark)
    if mark == nil then return false end
    if mark == 0 then s.marks[k] = nil
    else
        if not s.marks[k] and count(s.marks) >= MAX_MARKS then return false end
        s.marks[k] = mark
    end
    if A.MarksRefresh then A.MarksRefresh() end
    return true
end

--- The texture of a mark, and whether it is a game icon (those get their border trimmed).
function A.MarkTexture(mark)
    mark = validMark(mark)
    if type(mark) == "number" and mark >= 1 then return TEXTURE .. mark, false end
    if type(mark) == "string" then return tonumber(mark:sub(2)), true end
    return nil
end
--- The mark as inline text ("|T...|t"), or nil.
function A.MarkMarkup(mark, px)
    local texture, icon = A.MarkTexture(mark)
    if not texture then return nil end
    px = px or 14
    if icon then return string.format("|T%d:%d:%d:0:0:64:64:5:59:5:59|t", texture, px, px) end
    return string.format("|T%s:%d|t", texture, px)
end

-- Game icons to pick from, by spells and items every Forever client has. Any other one works with
-- /etally mark <name> spell <id> or item <id>.
local SPELLS = {2061, 355, 133, 116, 1784, 1499, 17, 1953}        -- Flash Heal, Taunt, Fireball, Frostbolt, Stealth, Freezing Trap, Power Word: Shield, Blink
local ITEMS = {6948, 2589, 765, 2770, 6265, 1251, 6256, 19019}    -- Hearthstone, Linen Cloth, Silverleaf, Copper Ore, Soul Shard, Linen Bandage, Fishing Pole, Thunderfury
--- The file id of a spell's or an item's icon, or nil.
function A.IconFileFor(kind, id)
    id = A.Number(id, 1, 10000000)
    if not id then return nil end
    local file
    if kind == "item" then file = A.Call(C_Item and C_Item.GetItemIconByID, id) or A.Call(GetItemIcon, id)
    elseif kind == "spell" then file = A.Call(C_Spell and C_Spell.GetSpellTexture, id) or A.Call(GetSpellTexture, id) end
    return A.Number(file, 1, 999999999)
end
--- Everything the picker offers: the eight raid icons, then the game icons that exist in this client.
function A.MarkChoices()
    local out = {}
    for i = 1, MARKS do out[#out + 1] = i end
    for _, list in ipairs({{"spell", SPELLS}, {"item", ITEMS}}) do
        for _, id in ipairs(list[2]) do
            local file = A.IconFileFor(list[1], id)
            if file then out[#out + 1] = "f" .. file end
        end
    end
    return out
end

--- Called for every addon message that proves the sender runs Evertally.
function A.NoteEvertallyUser(sender)
    local s, k = settings(), key(sender)
    if not s or not k then return end
    s.evertallyUsers = type(s.evertallyUsers) == "table" and s.evertallyUsers or {}
    local now = A.Now()
    if s.evertallyUsers[k] and now - s.evertallyUsers[k] < 3600 then return end   -- one write per hour is plenty
    s.evertallyUsers[k] = now
    if count(s.evertallyUsers) > MAX_USERS then
        for name, at in pairs(s.evertallyUsers) do if now - at > USER_TTL then s.evertallyUsers[name] = nil end end
        if count(s.evertallyUsers) > MAX_USERS then
            local oldest; for name, at in pairs(s.evertallyUsers) do if not oldest or at < s.evertallyUsers[oldest] then oldest = name end end
            if oldest then s.evertallyUsers[oldest] = nil end
        end
    end
end
--- A player known to run Evertally: they sent an Evertally message lately, or they are on the website's public board
--- (RankingData.lua). realm: the player's realm, nil for the own realm.
local function isUser(name, realm)
    local s, k = settings(), key(name)
    local at = s and k and s.evertallyUsers and s.evertallyUsers[k]
    if at ~= nil and A.Now() - at <= USER_TTL then return true end
    if not A.RankingFor or not name then return false end
    realm = A.Text(realm, 80)
    if not realm or realm == "" then realm = A.Call(GetNormalizedRealmName) or A.Call(GetRealmName) end
    return A.RankingFor(A.Text(name, 80) and name:match("^[^%-]+") or name, realm) ~= nil
end
A.IsEvertallyUser = isUser

-- ---------------------------------------------------------------- drawing
local holders = {}
-- Smaller than a raid target icon unless the player wants otherwise (/etally mark size 10-32).
local function size() local s = settings(); return A.Number(s and s.markSize, 10, 32) or 12 end
local function holder(i)
    local h = holders[i]
    if h then return h end
    h = CreateFrame("Frame", nil, UIParent)
    h:EnableMouse(false); h:SetFrameStrata("MEDIUM"); h:SetFrameLevel(50)
    h.mark = h:CreateTexture(nil, "OVERLAY")
    h.logo = h:CreateTexture(nil, "OVERLAY"); h.logo:SetTexture(LOGO)
    holders[i] = h
    return h
end
local function plates()
    local list = C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" and A.Call(C_NamePlate.GetNamePlates)
    return type(list) == "table" and list or {}
end
--- The name text of a nameplate when it shows one. With "names only" for friendly players the name is all there is
--- of the plate, so the icons go right beside it instead of above the (then empty) plate.
local function nameRegion(plate)
    local ok, region = pcall(function()
        local frame = plate.UnitFrame
        if type(frame) ~= "table" then return nil end
        for _, field in ipairs({"name", "Name", "NameText"}) do
            local r = frame[field]
            if type(r) == "table" and type(r.IsVisible) == "function" and r:IsVisible() then return r end
        end
    end)
    return ok and region or nil
end
local function plateToken(plate)
    local ok, token = pcall(function() return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit) end)
    return ok and A.Text(token, 40) or nil
end
-- The frames of the target and of the group get the icons too (above the frame, outside it).
local UNIT_FRAMES = {{"target", "TargetFrame"}, {"party1", "PartyMemberFrame1"}, {"party2", "PartyMemberFrame2"}, {"party3", "PartyMemberFrame3"}, {"party4", "PartyMemberFrame4"}}
function A.MarksRefresh()
    local s = settings()
    local used = 0
    if s then
        local showLogo = s.markUsers ~= false
        local px = size()
        -- beside: the anchor is a name text; the icons go to its right. Otherwise they sit centred above the anchor.
        local function draw(anchor, token, offset, beside)
            if used >= 48 or A.Call(UnitIsPlayer, token) ~= true or A.Call(UnitIsUnit, token, "player") == true then return end
            local name, realm = A.Call(UnitName, token)
            name = A.Text(name, 80)
            local mark = name and A.GetMark(name)
            local logo = showLogo and name and isUser(name, realm)
            if not (mark or logo) then return end
            used = used + 1
            local h = holder(used)
            h:ClearAllPoints()
            if beside then h:SetPoint("LEFT", anchor, "RIGHT", 3, 0) else h:SetPoint("BOTTOM", anchor, "TOP", 0, offset) end
            h:SetSize(px * 2 + 2, px)
            h.mark:ClearAllPoints(); h.logo:ClearAllPoints()
            h.mark:SetSize(px, px); h.logo:SetSize(px, px)
            if beside then
                h.mark:SetPoint("LEFT", h, "LEFT", 0, 0)
                h.logo:SetPoint("LEFT", h, "LEFT", mark and px + 2 or 0, 0)
            elseif mark and logo then h.mark:SetPoint("RIGHT", h, "CENTER", -1, 0); h.logo:SetPoint("LEFT", h, "CENTER", 1, 0)
            elseif mark then h.mark:SetPoint("CENTER", h, "CENTER")
            else h.logo:SetPoint("CENTER", h, "CENTER") end
            local texture, icon = A.MarkTexture(mark)
            if texture then
                h.mark:SetTexture(texture)
                if icon then h.mark:SetTexCoord(0.08, 0.92, 0.08, 0.92) else h.mark:SetTexCoord(0, 1, 0, 1) end
                h.mark:Show()
            else h.mark:Hide() end
            if logo then h.logo:Show() else h.logo:Hide() end
            h:Show()
        end
        -- one plate that cannot be read (a protected one) never stops the others
        for _, plate in ipairs(plates()) do
            local token = plateToken(plate)
            if token then
                local name = nameRegion(plate)
                pcall(draw, name or plate, token, 6, name ~= nil)
            end
        end
        for _, entry in ipairs(UNIT_FRAMES) do
            local frame = rawget(_G, entry[2])
            if frame and A.Call(frame.IsShown, frame) == true and A.Call(UnitExists, entry[1]) == true then draw(frame, entry[1], 2) end
        end
    end
    for i = used + 1, #holders do holders[i]:Hide() end
end
--- What the marks code sees on the nameplates around, for the chat and the diagnostics (/etally mark debug).
function A.MarksDebug()
    local s = settings() or {}
    local list = plates()
    local lines = {string.format("nameplates %d, logo %s, size %d", #list, s.markUsers ~= false and "on" or "off", size())}
    for i, plate in ipairs(list) do
        if i > 8 then lines[#lines + 1] = "..."; break end
        local token = plateToken(plate)
        local ok, line = pcall(function()
            local name, realm = A.Call(UnitName, token)
            name = A.Text(name, 80)
            return string.format("%d %s player=%s name=%s user=%s mark=%s visible=%s nametext=%s", i, tostring(token),
                tostring(A.Call(UnitIsPlayer, token)), tostring(name or "?"), tostring(name ~= nil and isUser(name, realm)),
                tostring(name and A.GetMark(name) or "-"), tostring(A.Call(plate.IsVisible, plate)), nameRegion(plate) and "yes" or "no")
        end)
        lines[#lines + 1] = ok and line or (i .. " unreadable")
    end
    local shown = 0
    for _, h in ipairs(holders) do if h:IsShown() then shown = shown + 1 end end
    lines[#lines + 1] = "icons drawn " .. shown
    for _, line in ipairs(lines) do A.Print(line); if A.DiagLog then A.DiagLog("marks " .. line) end end
    return lines
end

A.On("NAME_PLATE_UNIT_ADDED", function() pcall(A.MarksRefresh) end)
A.On("NAME_PLATE_UNIT_REMOVED", function() pcall(A.MarksRefresh) end)
if C_Timer and type(C_Timer.NewTicker) == "function" then C_Timer.NewTicker(1, function() pcall(A.MarksRefresh) end) end

-- ---------------------------------------------------------------- picker
--- A small grid of marks below `anchor`; a click stores the mark for `name` and calls done(). Parented to `parent`,
--- so it closes with the window it belongs to.
function A.OpenMarkPicker(parent, anchor, name, done)
    local p = A.markPicker
    if p and p:IsShown() and p.forName == name then p:Hide(); return end
    if not p then
        p = CreateFrame("Frame", nil, parent)
        p:SetFrameStrata("DIALOG"); p:EnableMouse(true)
        p.bg = p:CreateTexture(nil, "BACKGROUND"); p.bg:SetAllPoints(); p.bg:SetColorTexture(0.06, 0.05, 0.08, 0.96)
        p.title = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); p.title:SetPoint("TOPLEFT", 8, -6)
        p.buttons = {}
        A.markPicker = p
    end
    p:SetParent(parent); p.forName = name
    local choices = A.MarkChoices()
    choices[#choices + 1] = 0
    local columns, cell = 8, 24
    for i, choice in ipairs(choices) do
        local b = p.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, p); b:SetSize(cell - 2, cell - 2)
            b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
            b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.18)
            b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.label:SetPoint("CENTER")
            p.buttons[i] = b
        end
        local row, col = math.floor((i - 1) / columns), (i - 1) % columns
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", 6 + col * cell, -22 - row * cell)
        local texture, icon = A.MarkTexture(choice)
        if texture then
            b.icon:SetTexture(texture); b.icon:Show(); b.label:SetText("")
            if icon then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else b.icon:SetTexCoord(0, 1, 0, 1) end
        else b.icon:Hide(); b.label:SetText("×") end
        b:SetScript("OnClick", function() A.SetMark(name, choice); p:Hide(); if done then done() end end)
        b:Show()
    end
    for i = #choices + 1, #p.buttons do p.buttons[i]:Hide() end
    p.title:SetText(A.L("markPick"))
    p:SetSize(12 + columns * cell, 28 + math.ceil(#choices / columns) * cell)
    p:ClearAllPoints(); p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    p:Show()
    return p
end

-- ---------------------------------------------------------------- command: /etally mark [name] <1-8|0>
--- "3" marks the current target, "Anna 3" marks Anna, "Anna 0" or "0" clears, "list" prints the marks, "logo on|off".
function A.MarkCommand(text)
    text = A.Text(text, 100) or ""
    local rest = text:gsub("^mark%s*", "")
    local s = settings()
    if not s then return end
    if rest == "logo on" or rest == "logo off" then
        s.markUsers = rest == "logo on"; A.MarksRefresh(); A.Print(A.L(s.markUsers and "markLogoOn" or "markLogoOff")); return
    end
    local size = rest:match("^size%s+(%d+)$")
    if size then s.markSize = A.Number(tonumber(size), 10, 32) or 12; A.MarksRefresh(); return end
    if rest == "debug" then A.MarksDebug(); return end
    -- any game icon: the icon of a spell or of an item, by its id
    local who, kind, id = rest:match("^(.-)%s*(spell)%s+(%d+)$")
    if not kind then who, kind, id = rest:match("^(.-)%s*(item)%s+(%d+)$") end
    if kind then
        if who == "" then who = A.Text(A.Call(UnitName, "target"), 80) or "" end
        if who == "" then A.Print(A.L("markNoTarget")); return end
        local file = A.IconFileFor(kind, tonumber(id))
        if not file then A.Print(A.L("markNoIcon")); return end
        if A.SetMark(who, "f" .. file) then A.Print(string.format(A.L("markIconSet"), A.MarkMarkup("f" .. file, 14) or "", who)) else A.Print(A.L("markFull")) end
        return
    end
    if rest == "list" or rest == "" then
        local names = {}
        for k, m in pairs(s.marks or {}) do names[#names + 1] = k .. " " .. (A.MarkMarkup(m, 12) or tostring(m)) end
        table.sort(names)
        A.Print(#names > 0 and (A.L("markList") .. " " .. table.concat(names, ", ")) or A.L("markNone")); A.Print(A.L("markUsage")); return
    end
    local name, number = rest:match("^(.-)%s*(%d)$")
    if not number then A.Print(A.L("markUsage")); return end
    if name == "" then name = A.Text(A.Call(UnitName, "target"), 80) or "" end
    if name == "" then A.Print(A.L("markNoTarget")); return end
    local value = tonumber(number)
    if value > MARKS then A.Print(A.L("markUsage")); return end
    if A.SetMark(name, value) then
        A.Print(value == 0 and string.format(A.L("markCleared"), name) or string.format(A.L("markSet"), value, name))
    else A.Print(A.L("markFull")) end
end

A.locale.en.markSet = "Mark %d set for %s. Only you can see it."
A.locale.cs.markSet = "Značka %d nastavena hráči %s. Vidíš ji jen ty."
A.locale.en.markCleared = "Mark removed from %s."
A.locale.cs.markCleared = "Značka odebrána hráči %s."
A.locale.en.markUsage = "Marks: /etally mark <1-8> (your target), /etally mark <name> <1-8>, any icon: /etally mark [name] spell|item <id>, 0 removes, /etally mark list, logo on|off, size 10-32, debug"
A.locale.en.markIconSet = "Mark %s set for %s. Only you can see it."
A.locale.cs.markIconSet = "Značka %s nastavena hráči %s. Vidíš ji jen ty."
A.locale.en.markNoIcon = "This client has no icon for that id."
A.locale.cs.markNoIcon = "Pro toto ID nemá klient ikonu."
A.locale.en.markPick = "Pick a mark (only you see it)"
A.locale.cs.markPick = "Vyber značku (vidíš ji jen ty)"
A.locale.en.markRemove = "Remove"
A.locale.cs.markRemove = "Odebrat"
A.locale.cs.markUsage = "Značky: /etally mark <1-8> (tvůj cíl), /etally mark <jméno> <1-8>, libovolná ikona: /etally mark [jméno] spell|item <id>, 0 odebere, /etally mark list, logo on|off, size 10-32, debug"
A.locale.en.markList = "Your marks:"
A.locale.cs.markList = "Tvoje značky:"
A.locale.en.markNone = "No marks set yet."
A.locale.cs.markNone = "Zatím nemáš žádné značky."
A.locale.en.markNoTarget = "Select a player or type a name."
A.locale.cs.markNoTarget = "Označ hráče nebo napiš jméno."
A.locale.en.markFull = "Too many marks; remove some first."
A.locale.cs.markFull = "Moc značek; nejdřív některé odeber."
A.locale.en.markLogoOn = "The Evertally logo is shown beside players who use Evertally."
A.locale.cs.markLogoOn = "Logo Evertally se ukazuje u hráčů, kteří Evertally používají."
A.locale.en.markLogoOff = "The Evertally logo is hidden."
A.locale.cs.markLogoOff = "Logo Evertally je skryté."
A.locale.en.markButton = "Mark"
A.locale.cs.markButton = "Značka"
