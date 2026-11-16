local _, A = ...
-- The chat button beside the Social button and the conversation window, drawn in Evertally's own navy-and-gold
-- style (Theme.lua) with its fonts, which carry the Czech letters the game's default fonts lack.
-- Sidebar: two tabs. Rooms are grouped (Support, General, Languages, Custom); Whispers lists private conversations.
-- The window can be resized from the bottom-right corner; the size is kept.
local C = A.Chat
local U = {rows = {}, offset = 0, tab = "rooms", browse = {rows = {}}}
A.ChatUI = U
local ROW_H, HEAD_H, SIDE, HEAD = 36, 24, 220, 52
local MIN_W, MIN_H, MAX_W, MAX_H = 600, 400, 1400, 1000

local function hex(c) return string.format("%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end
local function stamp(at)
    local value = A.Call(date, "%H:%M", at); return type(value) == "string" and value or ""
end
function U.Format(line)
    local T = A.Theme.colors
    if line.system then return "|cff" .. hex(T.faint) .. stamp(line.at) .. "   " .. line.text .. "|r" end
    local who = line.author ~= "" and line.author or "›"
    local color = line.out and T.sky or T.bright
    return "|cff" .. hex(T.faint) .. stamp(line.at) .. "|r   |cff" .. hex(color) .. who .. "|r   " .. line.text
end

function C.IsReading(conv) return U.window ~= nil and U.window:IsShown() and C.selected == conv.key end

-- The button sits right of the Social button (QuickJoinToastButton on newer clients, FriendsMicroButton on older),
-- or above the chat frame when neither exists. It is a plain frame of ours: Blizzard's buttons are only anchored to.
function U.Anchor()
    local social = QuickJoinToastButton or FriendsMicroButton
    if type(social) == "table" and type(social.GetObjectType) == "function" then return social, "LEFT", "RIGHT", 2, 0 end
    local chat = ChatFrame1 or DEFAULT_CHAT_FRAME
    if type(chat) == "table" then return chat, "BOTTOMLEFT", "TOPLEFT", 0, 28 end
    return UIParent, "BOTTOMLEFT", "BOTTOMLEFT", 30, 260
end
function U.Button()
    if U.button then return U.button end
    local b = CreateFrame("Button", "EvertallyChatButton", UIParent)
    b:SetSize(28, 28); b:SetFrameStrata("MEDIUM")
    local target, point, rel, x, y = U.Anchor(); b:SetPoint(point, target, rel, x, y)
    -- The same art as the chat's own menu button, so it reads as part of the chat frame.
    b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
    b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall"); b.count:SetPoint("BOTTOMRIGHT", 3, -2)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() U.Toggle() end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(A.L("chatTitle"))
        local unread = C.Unread(); GameTooltip:AddLine(unread > 0 and (unread .. " " .. A.L("chatUnread")) or A.L("chatOpen"), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    U.button = b; return b
end

local function selected() return C.selected and C.conversations[C.selected] end
function U.Select(conv)
    C.selected = conv and conv.key or nil
    if conv then C.MarkRead(conv) end
    U.Redraw()
end

-- ---------- sidebar entries ----------

-- What the active tab lists, top to bottom: headings and rows. A row is a conversation, a fixed room not joined yet,
-- or the "browse" action.
function U.Entries()
    local out = {}
    if U.tab == "whispers" then
        for _, conv in ipairs(C.List("whisper")) do out[#out + 1] = {kind = "conv", conv = conv} end
        return out
    end
    for _, group in ipairs(C.CATALOG) do
        out[#out + 1] = {kind = "head", text = group.title}
        for _, room in ipairs(group.rooms) do
            local conv = C.Joined(room.name) and C.conversations["room:" .. room.name:lower()]
            out[#out + 1] = conv and {kind = "conv", conv = conv} or {kind = "fixed", room = room}
        end
    end
    out[#out + 1] = {kind = "head", text = "chatCatCustom"}
    for _, conv in ipairs(C.List("room")) do
        if not C.CatalogRoom(conv.id) then out[#out + 1] = {kind = "conv", conv = conv} end
    end
    out[#out + 1] = {kind = "browse"}
    return out
end

local function initial(name)
    name = name or "?"; local first = name:byte(1); if not first then return "?" end
    local length = first >= 240 and 4 or first >= 224 and 3 or first >= 192 and 2 or 1
    return name:sub(1, length)
end

local function row(parent)
    local kit = A.UIKit(); local T = kit.C
    local r = CreateFrame("Button", nil, parent)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetPoint("TOPLEFT", 6, -1); r.bg:SetPoint("BOTTOMRIGHT", -6, 1); A.Theme.Shape(r.bg, "round"); kit.paint(r.bg, T.card, 0)
    r.accent = r:CreateTexture(nil, "ARTWORK"); r.accent:SetSize(3, 18); r.accent:SetPoint("LEFT", 6, 0); A.Theme.Shape(r.accent, "pill"); kit.paint(r.accent, T.gold, 1)
    local hover = r:CreateTexture(nil, "HIGHLIGHT"); hover:SetPoint("TOPLEFT", 6, -1); hover:SetPoint("BOTTOMRIGHT", -6, 1); A.Theme.Shape(hover, "round"); kit.paint(hover, {1, 1, 1}, 0.04)
    r.tile = r:CreateTexture(nil, "ARTWORK"); r.tile:SetSize(24, 24); r.tile:SetPoint("LEFT", 16, 0); A.Theme.Shape(r.tile, "round"); kit.paint(r.tile, T.off, 1)
    r.initial = kit.label(r, 12, T.bright); r.initial:SetPoint("CENTER", r.tile, "CENTER", 0, 0); r.initial:SetJustifyH("CENTER")
    r.name = kit.label(r, 12, T.text); r.name:SetPoint("TOPLEFT", r.tile, "TOPRIGHT", 10, 1); r.name:SetPoint("RIGHT", -38, 0); r.name:SetWordWrap(false)
    r.preview = kit.label(r, 10, T.faint); r.preview:SetPoint("BOTTOMLEFT", r.tile, "BOTTOMRIGHT", 10, -1); r.preview:SetPoint("RIGHT", -16, 0); r.preview:SetWordWrap(false)
    r.pill = r:CreateTexture(nil, "ARTWORK"); r.pill:SetSize(22, 15); r.pill:SetPoint("RIGHT", -14, 6); A.Theme.Shape(r.pill, "pill"); kit.paint(r.pill, T.sky, 0.95)
    r.count = kit.label(r, 10, T.canvas); r.count:SetPoint("CENTER", r.pill, "CENTER", 0, 0); r.count:SetJustifyH("CENTER")
    r.head = kit.label(r, 10, T.faint); r.head:SetPoint("BOTTOMLEFT", 16, 4)
    r:SetScript("OnClick", function(self) U.Activate(self.entry) end)
    return r
end

function U.Activate(entry)
    if not entry then return end
    if entry.kind == "conv" then U.browsing = false; U.Select(entry.conv)
    elseif entry.kind == "fixed" then
        local ok, result = C.JoinCatalog(entry.room.name)
        if ok then U.browsing = false; U.Select(result) else U.Status(A.L(result)) end
    elseif entry.kind == "browse" then U.browsing = true; C.selected = nil; U.Redraw() end
end

-- ---------- building ----------

local function input(parent, kit)
    local box = kit.SearchBox(parent, 100, nil); box:SetMaxLetters(255)
    return box
end
local function settingsSize()
    local size = C.Settings().size
    if type(size) == "table" and type(size[1]) == "number" and type(size[2]) == "number" then
        return math.max(MIN_W, math.min(MAX_W, size[1])), math.max(MIN_H, math.min(MAX_H, size[2]))
    end
    return 700, 460
end

function U.Build()
    if U.window then return U.window end
    local kit = A.UIKit(); local T = kit.C
    local w = CreateFrame("Frame", "EvertallyChatWindow", UIParent)
    w:SetSize(settingsSize()); w:SetPoint("CENTER", UIParent, "CENTER", -180, 60); w:SetFrameStrata("HIGH")
    if w.SetToplevel then w:SetToplevel(true) end
    w:SetMovable(true); w:EnableMouse(true); w:SetClampedToScreen(true)
    if w.SetResizable then w:SetResizable(true) end
    if w.SetResizeBounds then pcall(w.SetResizeBounds, w, MIN_W, MIN_H, MAX_W, MAX_H)
    elseif w.SetMinResize then pcall(w.SetMinResize, w, MIN_W, MIN_H); if w.SetMaxResize then pcall(w.SetMaxResize, w, MAX_W, MAX_H) end end
    w:SetScript("OnShow", function() local conv = selected(); if conv then C.MarkRead(conv) end; U.Redraw() end)
    w:SetScript("OnSizeChanged", function() if w:IsShown() then U.Redraw() end end)
    A.NativeFrame(w, T)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EvertallyChatWindow" end

    -- Header
    local bar = CreateFrame("Frame", nil, w); bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1); bar:SetHeight(HEAD)
    local barFill = bar:CreateTexture(nil, "BACKGROUND"); barFill:SetAllPoints(); A.Theme.Shape(barFill, "round"); kit.paint(barFill, T.header, 0.97)
    local rule = bar:CreateTexture(nil, "BORDER"); rule:SetHeight(1); rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); kit.paint(rule, T.gold, 0.45)
    bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() w:StartMoving() end)
    bar:SetScript("OnDragStop", function() w:StopMovingOrSizing() end)
    local logo = bar:CreateTexture(nil, "ARTWORK"); logo:SetSize(30, 30); logo:SetPoint("LEFT", 14, 0)
    if logo:SetTexture("Interface\\AddOns\\Evertally\\Media\\Logo") == false then kit.setIcon(logo, kit.ICON.social) end
    w.title = kit.label(bar, 18, T.bright); w.title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, 0)
    w.subtitle = kit.label(bar, 10, T.faint); w.subtitle:SetPoint("BOTTOMLEFT", logo, "BOTTOMRIGHT", 10, 1)
    w.close = kit.Button(bar, nil, 28, "ghost", function() w:Hide() end); w.close:SetHeight(26); w.close:SetPoint("RIGHT", -12, 0); w.close.text:SetText("x")

    -- Sidebar with the two tabs
    local side = CreateFrame("Frame", nil, w); side:SetPoint("TOPLEFT", 1, -HEAD - 1); side:SetPoint("BOTTOMLEFT", 1, 1); side:SetWidth(SIDE); w.side = side
    local sideRule = side:CreateTexture(nil, "BORDER"); sideRule:SetWidth(1); sideRule:SetPoint("TOPRIGHT"); sideRule:SetPoint("BOTTOMRIGHT"); kit.paint(sideRule, T.line)
    w.tabRooms = kit.Chip(side, function() U.tab = "rooms"; U.offset = 0; U.Redraw() end); w.tabRooms:SetPoint("TOPLEFT", 12, -12)
    w.tabWhispers = kit.Chip(side, function() U.tab = "whispers"; U.offset = 0; U.Redraw() end); w.tabWhispers:SetPoint("LEFT", w.tabRooms, "RIGHT", 6, 0)
    local list = CreateFrame("Frame", nil, side); list:SetPoint("TOPLEFT", 0, -46); list:SetPoint("BOTTOMRIGHT", 0, 84)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) U.offset = math.max(0, math.min(U.maxOffset or 0, U.offset - delta)); U.Redraw() end)
    w.list = list
    w.empty = kit.label(side, 11, T.mist); w.empty:SetPoint("TOPLEFT", 16, -54); w.empty:SetPoint("TOPRIGHT", -16, -54); w.empty:SetWordWrap(true)

    -- Sidebar footer: start a whisper (whispers tab) or open browsing (rooms tab)
    local foot = CreateFrame("Frame", nil, side); foot:SetPoint("BOTTOMLEFT", 0, 0); foot:SetPoint("BOTTOMRIGHT", -1, 0); foot:SetHeight(84)
    local footRule = foot:CreateTexture(nil, "BORDER"); footRule:SetHeight(1); footRule:SetPoint("TOPLEFT"); footRule:SetPoint("TOPRIGHT"); kit.paint(footRule, T.line)
    local target = input(foot, kit); target:ClearAllPoints(); target:SetPoint("TOPLEFT", 12, -12); target:SetPoint("TOPRIGHT", -12, -12); target:SetHeight(26); target:SetMaxLetters(60)
    target:SetScript("OnEnterPressed", function() if U.tab == "whispers" then U.StartWhisper() else U.JoinRoom() end end)
    w.target = target
    w.whisper = kit.Chip(foot, function() U.StartWhisper() end); w.whisper:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -8)
    w.room = kit.Chip(foot, function() U.JoinRoom() end); w.room:SetPoint("LEFT", w.whisper, "RIGHT", 6, 0)
    w.room:SetScript("OnEnter", function(self) if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(A.L("chatRoomHint"), 1, 1, 1, 1, true); GameTooltip:Show() end end)
    w.room:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- Conversation
    local main = CreateFrame("Frame", nil, w); main:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0); main:SetPoint("BOTTOMRIGHT", -1, 1); w.main = main
    w.leave = kit.Chip(main, function() U.LeaveOrClose() end); w.leave:SetPoint("TOPRIGHT", -16, -16)
    w.share = kit.Chip(main, function() U.ShareRoom() end); w.share:SetPoint("RIGHT", w.leave, "LEFT", -6, 0)
    w.friend = kit.Chip(main, function() local conv = selected(); if conv and A.Presence then U.Status(A.L(A.Presence.AddFriend(conv.target or conv.name) and "chatFriendAdded" or "chatSendFailed")) end end)
    w.friend:SetPoint("RIGHT", w.leave, "LEFT", -6, 0)
    w.invite = kit.Chip(main, function() local conv = selected(); if conv and A.Presence then U.Status(A.L(A.Presence.Invite(conv.target or conv.name) and "chatInvited" or "chatSendFailed")) end end)
    w.invite:SetPoint("RIGHT", w.friend, "LEFT", -6, 0)
    w.head = kit.label(main, 15, T.bright); w.head:SetPoint("TOPLEFT", 20, -14); w.head:SetWordWrap(false)
    w.kind = kit.label(main, 10, T.faint); w.kind:SetPoint("TOPLEFT", w.head, "BOTTOMLEFT", 0, -3); w.kind:SetWordWrap(false)
    local well = CreateFrame("Frame", nil, main); well:SetPoint("TOPLEFT", 14, -56); well:SetPoint("BOTTOMRIGHT", -14, 64)
    A.Theme.Surface(well, "reader"); w.well = well
    local log = CreateFrame("ScrollingMessageFrame", nil, well)
    log:SetPoint("TOPLEFT", 12, -10); log:SetPoint("BOTTOMRIGHT", -12, 10)
    log:SetFont(kit.fontPath(), 13, ""); kit.trackFont(log, 13)
    if log.SetSpacing then log:SetSpacing(4) end
    log:SetJustifyH("LEFT"); log:SetFading(false); log:SetMaxLines(300); log:SetHyperlinksEnabled(true)
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(self, delta) if delta > 0 then self:ScrollUp() else self:ScrollDown() end end)
    log:SetScript("OnHyperlinkClick", function(_, link, text, button) if type(SetItemRef) == "function" then pcall(SetItemRef, link, text, button) end end)
    w.log = log
    w.hintLogo = well:CreateTexture(nil, "ARTWORK"); w.hintLogo:SetSize(56, 56); w.hintLogo:SetPoint("CENTER", 0, 18); w.hintLogo:SetAlpha(0.18)
    if w.hintLogo:SetTexture("Interface\\AddOns\\Evertally\\Media\\Logo") == false then w.hintLogo:Hide() end
    w.hint = kit.label(well, 12, T.mist); w.hint:SetPoint("TOP", w.hintLogo, "BOTTOM", 0, -10); w.hint:SetWidth(320); w.hint:SetJustifyH("CENTER"); w.hint:SetWordWrap(true)

    local box = input(main, kit); box:ClearAllPoints(); box:SetPoint("BOTTOMLEFT", 14, 22); box:SetPoint("RIGHT", main, "RIGHT", -108, 0); box:SetHeight(30)
    box:SetScript("OnEnterPressed", function(self) U.SendInput(self) end)
    w.input = box
    w.send = kit.Button(main, "chatSend", 84, "primary", function() U.SendInput(w.input) end); w.send:SetHeight(30); w.send:SetPoint("BOTTOMRIGHT", -14, 22)
    w.status = kit.label(main, 10, T.red); w.status:SetPoint("BOTTOMLEFT", 16, 6); w.status:SetPoint("BOTTOMRIGHT", -30, 6); w.status:SetWordWrap(false)

    U.BuildBrowse(w, main, kit)

    -- Resize grip in the bottom-right corner
    local grip = CreateFrame("Button", nil, w); grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() w:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        w:StopMovingOrSizing()
        local width, height = w:GetWidth(), w:GetHeight()
        if type(width) == "number" and type(height) == "number" then C.Settings().size = {math.floor(width + 0.5), math.floor(height + 0.5)} end
        U.Redraw()
    end)
    w.grip = grip
    w:Hide()
    U.window = w
    return w
end

-- The main area while browsing: public rooms with a search, and a form to create or enter a room by name.
function U.BuildBrowse(w, main, kit)
    local T = kit.C
    local b = CreateFrame("Frame", nil, main); b:SetPoint("TOPLEFT", 14, -56); b:SetPoint("BOTTOMRIGHT", -14, 14); b:Hide(); w.browse = b; b.rows = {}
    b.search = input(b, kit); b.search:ClearAllPoints(); b.search:SetPoint("TOPLEFT", 0, 0); b.search:SetPoint("TOPRIGHT", 0, 0); b.search:SetHeight(28)
    b.search:SetScript("OnTextChanged", function(self) self.hint:SetShown((self:GetText() or "") == ""); U.Redraw() end)
    b.note = kit.label(b, 10, T.faint); b.note:SetPoint("TOPLEFT", b.search, "BOTTOMLEFT", 2, -6); b.note:SetPoint("TOPRIGHT", b.search, "BOTTOMRIGHT", -2, -6); b.note:SetWordWrap(true)
    b.listArea = CreateFrame("Frame", nil, b); b.listArea:SetPoint("TOPLEFT", 0, -64); b.listArea:SetPoint("BOTTOMRIGHT", 0, 120)
    A.Theme.Surface(b.listArea, "reader")
    b.none = kit.label(b.listArea, 11, T.mist); b.none:SetPoint("TOPLEFT", 12, -12); b.none:SetPoint("TOPRIGHT", -12, -12); b.none:SetWordWrap(true)
    -- create
    local form = CreateFrame("Frame", nil, b); form:SetPoint("BOTTOMLEFT"); form:SetPoint("BOTTOMRIGHT"); form:SetHeight(108); b.form = form
    b.formTitle = kit.label(form, 12, T.bright); b.formTitle:SetPoint("TOPLEFT", 2, -4)
    b.name = input(form, kit); b.name:ClearAllPoints(); b.name:SetPoint("TOPLEFT", 0, -24); b.name:SetPoint("RIGHT", form, "CENTER", -4, 0); b.name:SetHeight(28); b.name:SetMaxLetters(24)
    b.password = input(form, kit); b.password:ClearAllPoints(); b.password:SetPoint("TOPLEFT", form, "TOP", 4, -24); b.password:SetPoint("TOPRIGHT", 0, -24); b.password:SetHeight(28); b.password:SetMaxLetters(24)
    b.public = kit.Chip(form, function() U.makePublic = true; U.Redraw() end); b.public:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -10)
    b.private = kit.Chip(form, function() U.makePublic = false; U.Redraw() end); b.private:SetPoint("LEFT", b.public, "RIGHT", 6, 0)
    b.create = kit.Button(form, "chatCreate", 150, "primary", function() U.CreateRoom() end); b.create:SetHeight(28); b.create:SetPoint("TOPRIGHT", b.password, "BOTTOMRIGHT", 0, -8)
    U.makePublic = true
end

-- ---------- actions ----------

function U.SendInput(box)
    local conv = selected(); local message = box:GetText()
    if not conv or not message or message:match("^%s*$") then box:ClearFocus(); return end
    local ok, why = C.Send(conv, message)
    if ok then box:SetText(""); U.Status("") else U.Status(A.L(why or "chatSendFailed")) end
end
function U.Status(message) if U.window then U.window.status:SetText(message or "") end end
function U.StartWhisper()
    local w = U.window; local name = w.target:GetText(); name = name and name:match("^%s*(.-)%s*$")
    if not name or name == "" or name:find("[%s|]") and not name:match("^%S+ %S+$") then U.Status(A.L("chatBadName")); return end
    local conv = C.Whisper(name); if not conv then U.Status(A.L("chatBadName")); return end
    w.target:SetText(""); U.Status(""); U.tab = "whispers"; U.browsing = false; U.Select(conv); w.input:SetFocus()
end
function U.JoinRoom()
    local w = U.window; local ok, result = C.JoinRoom(w.target:GetText())
    if not ok then U.Status(A.L(result)); return end
    w.target:SetText(""); U.Status(""); U.tab = "rooms"; U.browsing = false; U.Select(result)
end
function U.CreateRoom()
    local b = U.window.browse
    local name, password = b.name:GetText() or "", b.password:GetText() or ""
    local ok, result = C.JoinRoom(name .. (password ~= "" and (" " .. password) or ""), U.makePublic == true)
    if not ok then U.Status(A.L(result)); return end
    b.name:SetText(""); b.password:SetText(""); U.Status(""); U.tab = "rooms"; U.browsing = false; U.Select(result)
end
function U.JoinListed(name)
    local ok, result = C.JoinPublic(name)
    if not ok then U.Status(A.L(result)); return end
    U.Status(""); U.tab = "rooms"; U.browsing = false; U.Select(result)
end
function U.ShareRoom()
    local ok, why = C.Share(selected()); U.Status(A.L(why or (ok and "chatShared" or "chatSendFailed")))
end
function U.LeaveOrClose()
    local conv = selected(); if not conv then return end
    if conv.kind == "room" then C.LeaveRoom(conv.id) else C.Remove(conv) end
    U.Redraw()
end

-- ---------- drawing ----------

local function drawRow(r, entry, kit)
    local T = kit.C
    r.entry = entry
    local isHead = entry.kind == "head"
    r.head:SetShown(isHead)
    for _, part in ipairs({r.tile, r.initial, r.name, r.preview}) do part:SetShown(not isHead) end
    r.bg:SetShown(not isHead); r.accent:Hide(); r.pill:Hide(); r.count:Hide()
    r:EnableMouse(not isHead)
    if isHead then r.head:SetText(A.Upper(A.L(entry.text))); return end
    if entry.kind == "browse" then
        r.initial:SetText("+"); kit.paint(r.tile, T.violet, 1); r.name:SetText(A.L("chatBrowse")); r.preview:SetText("")
        local on = U.browsing == true; kit.paint(r.bg, T.card, on and 0.95 or 0); r.accent:SetShown(on)
        r.name:SetTextColor(T.mist[1], T.mist[2], T.mist[3]); return
    end
    if entry.kind == "fixed" then
        r.initial:SetText("#"); kit.paint(r.tile, T.off, 0.6); r.name:SetText(entry.room.label); r.preview:SetText(A.L("chatNotIn"))
        kit.paint(r.bg, T.card, 0); r.name:SetTextColor(T.mist[1], T.mist[2], T.mist[3]); return
    end
    local conv = entry.conv; local on = conv.key == C.selected and not U.browsing
    r.initial:SetText(conv.kind == "room" and "#" or A.Upper(initial(conv.name)))
    kit.paint(r.tile, conv.kind == "room" and T.violet or T.off, 1)
    r.name:SetText(conv.name)
    local last = conv.lines[#conv.lines]
    r.preview:SetText(last and ((last.out and "› " or "") .. last.text:gsub("|", "¦")) or "")
    kit.paint(r.bg, T.card, on and 0.95 or 0); r.accent:SetShown(on)
    local c = (on or conv.unread > 0) and T.bright or T.text; r.name:SetTextColor(c[1], c[2], c[3])
    r.pill:SetShown(conv.unread > 0); r.count:SetShown(conv.unread > 0); r.count:SetText(conv.unread > 99 and "99" or tostring(conv.unread))
end

function U.DrawList(w, kit)
    local entries = U.Entries()
    local height = w.list:GetHeight(); if type(height) ~= "number" or height <= 0 then height = 300 end
    U.maxOffset = math.max(0, #entries - 1)
    U.offset = math.max(0, math.min(U.offset, U.maxOffset))
    local y, used = 0, 0
    for i = U.offset + 1, #entries do
        local entry = entries[i]; local h = entry.kind == "head" and HEAD_H or ROW_H
        if y + h > height then break end
        used = used + 1
        local r = U.rows[used]; if not r then r = row(w.list); U.rows[used] = r end
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("TOPRIGHT", 0, -y); r:SetHeight(h); r:Show()
        drawRow(r, entry, kit); y = y + h
    end
    for i = used + 1, #U.rows do U.rows[i]:Hide(); U.rows[i].entry = nil end
    -- the list never scrolls past the point where its end is in view
    if y < height and U.offset > 0 then U.maxOffset = U.offset end
    return entries
end

function U.DrawBrowse(w, kit)
    local b = w.browse; local T = kit.C
    b.search.hint:SetText(A.L("chatSearch")); b.note:SetText(A.L("chatBrowseHint"))
    b.formTitle:SetText(A.L("chatCreateTitle")); b.name.hint:SetText(A.L("chatRoomName")); b.password.hint:SetText(A.L("chatPassword"))
    b.public.SetLabel(A.L("chatPublic")); b.private.SetLabel(A.L("chatPrivate"))
    b.public.SetOn(U.makePublic == true); b.private.SetOn(U.makePublic ~= true)
    local rooms = C.Directory(b.search:GetText())
    local height = b.listArea:GetHeight(); if type(height) ~= "number" or height <= 0 then height = 160 end
    local fit = math.max(0, math.floor((height - 12) / 32))
    for i = 1, math.max(#b.rows, math.min(#rooms, fit)) do
        local room = i <= fit and rooms[i]
        local r = b.rows[i]
        if room and not r then
            r = CreateFrame("Frame", nil, b.listArea); r:SetHeight(30)
            r:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 32); r:SetPoint("TOPRIGHT", -8, -6 - (i - 1) * 32)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); A.Theme.Shape(r.bg, "round"); kit.paint(r.bg, T.card, 0.7)
            r.name = kit.label(r, 12, T.text); r.name:SetPoint("LEFT", 12, 0)
            r.meta = kit.label(r, 10, T.faint); r.meta:SetPoint("LEFT", r.name, "RIGHT", 10, 0)
            r.join = kit.Chip(r, function() U.JoinListed(r.room) end); r.join:SetPoint("RIGHT", -6, 0)
            b.rows[i] = r
        end
        if r then
            r:SetShown(room ~= nil and room ~= false)
            if room then
                r.room = room.name; r.name:SetText("# " .. room.name)
                r.meta:SetText((room.by and (room.by .. " · ") or "") .. string.format(A.L("chatSeenBy"), math.floor((A.Now() - room.seen) / 60)))
                local joined = C.Joined(room.name)
                r.join.SetLabel(A.L(joined and "chatTabRooms" or "chatJoin")); r.join:SetShown(not joined)
            end
        end
    end
    b.none:SetText(A.L("chatNoPublic")); b.none:SetShown(#rooms == 0)
end

function U.Redraw()
    U.Refresh()
    local w = U.window; if not w or not w:IsShown() then return end
    local kit = A.UIKit()
    w.title:SetText(A.L("chatTitle")); w.subtitle:SetText(A.L("chatWhispers"))
    local roomsUnread, whispersUnread = C.Unread("room"), C.Unread("whisper")
    w.tabRooms.SetLabel(A.L("chatTabRooms") .. (roomsUnread > 0 and ("  " .. roomsUnread) or "")); w.tabRooms.SetOn(U.tab == "rooms")
    w.tabWhispers.SetLabel(A.L("chatTabWhispers") .. (whispersUnread > 0 and ("  " .. whispersUnread) or "")); w.tabWhispers.SetOn(U.tab == "whispers")
    w.target.hint:SetText(A.L("chatTarget")); w.input.hint:SetText(A.L("chatMessageHint"))
    w.whisper.SetLabel(A.L("chatWhisper")); w.room.SetLabel(A.L("chatRoom"))
    local entries = U.DrawList(w, kit)
    local listed = 0; for _, e in ipairs(entries) do if e.kind == "conv" then listed = listed + 1 end end
    w.empty:SetText(A.L("chatEmpty")); w.empty:SetShown(U.tab == "whispers" and listed == 0)

    local browsing = U.browsing == true
    local conv = not browsing and selected() or nil
    w.browse:SetShown(browsing)
    if browsing then U.DrawBrowse(w, kit) end
    w.well:SetShown(not browsing)
    w.head:SetText(browsing and A.L("chatBrowseTitle") or conv and ((conv.kind == "room" and "# " or "") .. (conv.kind == "whisper" and conv.target or conv.name)) or A.L("chatTitle"))
    w.kind:SetText(conv and A.L(conv.kind == "room" and "chatKindRoom" or "chatKindWhisper") or "")
    w.leave:SetShown(conv ~= nil); w.leave.SetLabel(A.L(conv and conv.kind == "room" and "chatLeave" or "chatCloseConv"))
    w.share:SetShown(conv ~= nil and conv.kind == "room" and not C.CatalogRoom(conv.id)); w.share.SetLabel(A.L("chatShare"))
    local whisper = conv ~= nil and conv.kind == "whisper"
    w.invite:SetShown(whisper); w.friend:SetShown(whisper); w.invite.SetLabel(A.L("chatInvite")); w.friend.SetLabel(A.L("chatAddFriend"))
    -- the title and its line end before the first visible button on the right
    local edge = whisper and w.invite or (w.share:IsShown() and w.share) or w.leave
    for _, fs in ipairs({w.head, w.kind}) do
        local point, rel, relPoint, x, y = fs:GetPoint(1); fs:ClearAllPoints(); fs:SetPoint(point, rel, relPoint, x, y)
        fs:SetPoint("RIGHT", edge, "LEFT", -12, 0)
    end
    w.input:SetShown(conv ~= nil); w.send:SetShown(conv ~= nil)
    w.hint:SetText(A.L(U.tab == "whispers" and listed == 0 and "chatEmpty" or "chatNoConv")); w.hint:SetShown(conv == nil and not browsing); w.hintLogo:SetShown(conv == nil and not browsing)
    if w.shownKey ~= (conv and conv.key) or w.shownCount ~= (conv and #conv.lines) then
        w.log:Clear()
        for _, line in ipairs(conv and conv.lines or {}) do w.log:AddMessage(U.Format(line)) end
        w.shownKey, w.shownCount = conv and conv.key, conv and #conv.lines
    end
end

-- Button visibility and the unread count; cheap enough to run on every change.
function U.Refresh()
    if not A.db then return end
    if not C.Enabled() then
        if U.button then U.button:Hide() end
        if U.window then U.window:Hide() end
        return
    end
    local b = U.Button(); b:Show()
    local unread = C.Unread(); b.count:SetText(unread > 0 and tostring(unread) or "")
end
function U.Toggle()
    if not C.Enabled() then return end
    local w = U.Build()
    if w:IsShown() then w:Hide() else w:Show(); U.Redraw() end
end
function U.Open(conv)
    if not C.Enabled() then return end
    local w = U.Build()
    if conv then C.selected = conv.key; C.MarkRead(conv); U.browsing = false; U.tab = conv.kind == "whisper" and "whispers" or "rooms" end
    w:Show(); U.Redraw()
end

C.OnChanged = function() U.Redraw() end
C.OnLine = function(conv)
    local w = U.window
    if w and w:IsShown() and C.selected == conv.key and w.shownKey == conv.key and not U.browsing then
        w.log:AddMessage(U.Format(conv.lines[#conv.lines])); w.shownCount = #conv.lines
    end
end
-- With whispers taken out of the main chat, a new one must not go unnoticed: the window opens (outside combat)
-- and the usual whisper sound plays, which the Blizzard chat no longer does for a hidden message.
C.OnIncoming = function(conv)
    if not C.Redirect() then return end
    if type(PlaySound) == "function" then pcall(PlaySound, SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081) end
    if A.Call(InCombatLockdown) == true then return end
    if not (U.window and U.window:IsShown()) then U.Open(conv)
    elseif not C.selected then U.Select(conv) end
end
A.On("PLAYER_LOGIN", U.Refresh)
A.On("PLAYER_REGEN_ENABLED", U.Refresh)
