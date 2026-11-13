local _, A = ...
-- Small icons beside player names (on the nameplates):
--  * a mark you give to somebody, so you can tell friends from other players at a glance. It exists only on this
--    computer: the player never sees it, and a mark somebody gave you is not visible to you.
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

--- The mark number (1..8) given to a player on this computer, or nil.
function A.GetMark(name)
    local s, k = settings(), key(name)
    return s and k and s.marks and s.marks[k] or nil
end
--- mark: 1..8, or 0/nil to clear. Returns true when something was stored or removed.
function A.SetMark(name, mark)
    local s, k = settings(), key(name)
    if not s or not k then return false end
    s.marks = type(s.marks) == "table" and s.marks or {}
    local wanted = tonumber(mark)
    if wanted ~= nil and (wanted < 0 or wanted > MARKS) then return false end
    mark = wanted
    if not mark or mark == 0 then s.marks[k] = nil
    else
        if not s.marks[k] and count(s.marks) >= MAX_MARKS then return false end
        s.marks[k] = math.floor(mark)
    end
    if A.MarksRefresh then A.MarksRefresh() end
    return true
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
local function isUser(name)
    local s, k = settings(), key(name)
    local at = s and k and s.evertallyUsers and s.evertallyUsers[k]
    return at ~= nil and A.Now() - at <= USER_TTL
end

-- ---------------------------------------------------------------- drawing
local holders = {}
local function size() local s = settings(); return A.Number(s and s.markSize, 10, 32) or 16 end
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
-- The frames of the target and of the group get the icons too (above the frame, outside it).
local UNIT_FRAMES = {{"target", "TargetFrame"}, {"party1", "PartyMemberFrame1"}, {"party2", "PartyMemberFrame2"}, {"party3", "PartyMemberFrame3"}, {"party4", "PartyMemberFrame4"}}
function A.MarksRefresh()
    local s = settings()
    local used = 0
    if s then
        local showLogo = s.markUsers ~= false
        local px = size()
        local function draw(anchor, token, offset)
            if used >= 48 or A.Call(UnitIsPlayer, token) ~= true or A.Call(UnitIsUnit, token, "player") == true then return end
            local name = A.Text(A.Call(UnitName, token), 80)
            local mark = name and A.GetMark(name)
            local logo = showLogo and name and isUser(name)
            if not (mark or logo) then return end
            used = used + 1
            local h = holder(used)
            h:ClearAllPoints(); h:SetPoint("BOTTOM", anchor, "TOP", 0, offset)
            h:SetSize(px * 2 + 2, px)
            h.mark:ClearAllPoints(); h.logo:ClearAllPoints()
            h.mark:SetSize(px, px); h.logo:SetSize(px, px)
            if mark and logo then h.mark:SetPoint("RIGHT", h, "CENTER", -1, 0); h.logo:SetPoint("LEFT", h, "CENTER", 1, 0)
            elseif mark then h.mark:SetPoint("CENTER", h, "CENTER")
            else h.logo:SetPoint("CENTER", h, "CENTER") end
            if mark then h.mark:SetTexture(TEXTURE .. mark); h.mark:Show() else h.mark:Hide() end
            if logo then h.logo:Show() else h.logo:Hide() end
            h:Show()
        end
        for _, plate in ipairs(plates()) do
            local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if token then draw(plate, token, 6) end
        end
        for _, entry in ipairs(UNIT_FRAMES) do
            local frame = rawget(_G, entry[2])
            if frame and A.Call(frame.IsShown, frame) == true and A.Call(UnitExists, entry[1]) == true then draw(frame, entry[1], 2) end
        end
    end
    for i = used + 1, #holders do holders[i]:Hide() end
end
A.On("NAME_PLATE_UNIT_ADDED", function() pcall(A.MarksRefresh) end)
A.On("NAME_PLATE_UNIT_REMOVED", function() pcall(A.MarksRefresh) end)
if C_Timer and type(C_Timer.NewTicker) == "function" then C_Timer.NewTicker(1, function() pcall(A.MarksRefresh) end) end

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
    if size then s.markSize = A.Number(tonumber(size), 10, 32) or 16; A.MarksRefresh(); return end
    if rest == "list" or rest == "" then
        local names = {}
        for k, m in pairs(s.marks or {}) do names[#names + 1] = k .. "=" .. m end
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
A.locale.en.markUsage = "Marks: /etally mark <1-8> (your target), /etally mark <name> <1-8>, 0 removes, /etally mark list, /etally mark logo on|off, /etally mark size 10-32"
A.locale.cs.markUsage = "Značky: /etally mark <1-8> (tvůj cíl), /etally mark <jméno> <1-8>, 0 odebere, /etally mark list, /etally mark logo on|off, /etally mark size 10-32"
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
