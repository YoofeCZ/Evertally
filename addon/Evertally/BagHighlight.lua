local _, A = ...
-- Marks bag items that fit an equipment slot the character has left empty and that it can wear now.
-- Works with any bag addon: item buttons are found by what they expose (bag and slot, or an item link),
-- not by the addon that drew them. Textures are added to the buttons; nothing is written to their tables.
local B = {buttons = setmetatable({}, {__mode = "k"}), glows = setmetatable({}, {__mode = "k"}), arrows = setmetatable({}, {__mode = "k"}), wanted = {}}
A.BagHighlight = B
local words = {
    en = {bagHighlightGuide = "Evertally Guide draws the bag arrows now (Settings > Questing > Rewards & gear).", bagHighlight = "Mark gear in bags: blue border = fits an empty slot, green arrow = upgrade",
        bagDiag = "Bag check: %d frames walked, %d item buttons found, %d marked."},
    cs = {bagHighlightGuide = "Šipky v taškách teď kreslí Evertally Guide (Nastavení > Questing > Rewards & gear).", bagHighlight = "Označit výbavu v taškách: modrý okraj = do prázdného slotu, zelená šipka = lepší",
        bagDiag = "Kontrola tašek: prošlo %d rámců, nalezeno %d tlačítek předmětů, označeno %d."},
}
for lang, entries in pairs(words) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local BLUE = {0.25, 0.62, 1}
local FULL_GAP = 2.5
-- Shirt and tabard carry no stats; an empty one is a choice, not a gap worth flagging.
local slotsFor = {
    INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3}, INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6},
    INVTYPE_LEGS = {7}, INVTYPE_FEET = {8}, INVTYPE_WRIST = {9}, INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14},
    INVTYPE_CLOAK = {15}, INVTYPE_WEAPON = {16}, INVTYPE_WEAPONMAINHAND = {16}, INVTYPE_2HWEAPON = {16}, INVTYPE_WEAPONOFFHAND = {17},
    INVTYPE_SHIELD = {17}, INVTYPE_HOLDABLE = {17}, INVTYPE_RANGED = {18}, INVTYPE_RANGEDRIGHT = {18}, INVTYPE_THROWN = {18}, INVTYPE_RELIC = {18},
}
B.SlotsFor = slotsFor

local function plain(v) return A.Plain(v) end
local function method(obj, name, ...)
    local fn = type(obj) == "table" and obj[name]
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, obj, ...)
    if ok then return plain(a), plain(b) end
end
local function integer(v) v = plain(v); if type(v) == "number" and v == math.floor(v) and v > -10 and v < 300 then return v end end
local function itemLink(v) v = plain(v); if type(v) == "string" and v:find("item:%d+") then return v end end

-- Evertally Guide's bag arrows (gear.bagArrows) win: one arrow per item, not two.
function B.Enabled() return A.db ~= nil and A.db.settings.bagHighlight ~= false and not (A.Gear and A.Gear.GuideHas and A.Gear.GuideHas("bagArrows")) end
function B.SetEnabled(on) if A.db then A.db.settings.bagHighlight = on == true end; B.Request(true) end

-- One empty, known slot is enough; a slot the client cannot report counts as occupied.
local function empty(slot) local G = A.Gear; local item, known = G.Equipped(slot); return known and item == nil end
function B.EmptySlotFor(item)
    local list = item and slotsFor[item.equipLoc]; if not list then return false end
    local G = A.Gear
    if item.equipLoc == "INVTYPE_WEAPON" then
        if empty(16) then return true end
        if not G.DualWieldKnown() or not empty(17) then return false end
        local main = G.Equipped(16); return not (main and main.equipLoc == "INVTYPE_2HWEAPON")
    end
    if list[1] == 17 then
        if not empty(17) then return false end
        local main = G.Equipped(16); return not (main and main.equipLoc == "INVTYPE_2HWEAPON")
    end
    for _, slot in ipairs(list) do if empty(slot) then return true end end
    return false
end

-- What the item means for this character: "empty" (wearable, its slot is free), "upgrade" (wearable and scores
-- higher than what is worn) or false. Both can apply; "empty" wins the border, the arrow shows an upgrade.
function B.Assess(link)
    local G = A.Gear; if not G or not link then return false, false, "no_link" end
    local cached = B.wanted[link]
    if cached and cached.generation == G.generation then return cached.empty, cached.upgrade, cached.reason end
    local item = G.Item(link); local isEmpty, isUpgrade, reason = false, false, nil
    if not item or not item.known then reason = "loading"; B.pendingInfo = true
    elseif not slotsFor[item.equipLoc] then reason = "not_gear"
    else
        local use, why = G.CanUse(item)
        if use ~= true then reason = why or "unusable"
        else
            isEmpty = B.EmptySlotFor(item)
            local compare = G.Compare(item); isUpgrade = compare.status == "upgrade"
            reason = isEmpty and "empty" or compare.status or "unknown"
        end
    end
    -- An item the client has not described yet is not cached: the answer comes with GET_ITEM_INFO_RECEIVED.
    if item and item.known then B.wanted[link] = {generation = G.generation, empty = isEmpty, upgrade = isUpgrade, reason = reason} end
    return isEmpty, isUpgrade, reason
end
function B.Wanted(link) local isEmpty = B.Assess(link); return isEmpty end

-- Where a button's item lives. Each line is one bag addon's convention; all are checked, none is required.
function B.Locate(button)
    local slot = integer(method(button, "GetID"))
    local bag = integer(method(button, "GetBagID"))                                -- Blizzard containers, Baganator live view
    if bag == nil then bag = integer(method(button, "GetBag")) end                 -- Bagnon
    if bag == nil then
        local fields = button.bagID ~= nil and button or button.bag ~= nil and button   -- AdiBags and others
        if fields then bag = integer(fields.bagID or fields.bag); slot = integer(fields.slotID or fields.slot) or slot end
    end
    local ark = type(button.ARK_Data) == "table" and button.ARK_Data              -- ArkInventory
    if bag == nil and ark then bag = integer(ark.blizzard_id); slot = integer(ark.slot_id) or slot end
    if bag == nil then
        local name = method(button, "GetName")
        if type(name) == "string" and name:match("^ContainerFrame%d+Item%d+$") then
            local ok, parent = pcall(button.GetParent, button)
            if ok then bag = integer(method(parent, "GetID")) end
        end
    end
    if bag == nil and type(button.GetItemLocation) == "function" then                -- ItemButtonMixin
        local ok, location = pcall(button.GetItemLocation, button)
        if ok and type(location) == "table" and type(location.GetBagAndSlot) == "function" then
            local fine, b, s = pcall(location.GetBagAndSlot, location); if fine then bag, slot = integer(b), integer(s) end
        end
    end
    if bag == nil and type(button.BGR) == "table" then                             -- Baganator (classic-style buttons)
        local ok, parent = pcall(button.GetParent, button)
        if ok then bag = integer(method(parent, "GetID")) end
    end
    if bag == nil or not slot or slot < 1 then return nil end
    return bag, slot
end

-- The link the button shows. Baganator keeps it in button.BGR even where no bag and slot can be read.
local function shownLink(button)
    return itemLink(button.itemLink) or itemLink(button.link)
        or type(button.BGR) == "table" and (itemLink(button.BGR.itemLink) or itemLink(button.BGR.link))
        or type(button.info) == "table" and (itemLink(button.info.hyperlink) or itemLink(button.info.link))
end
function B.LinkOf(button)
    local shown = shownLink(button)
    local bag, slot = B.Locate(button)
    if bag == nil then
        -- Without a bag and slot only a bag addon's own marker makes a link trustworthy (not loot or merchant buttons).
        if shown and (type(button.BGR) == "table" or type(button.ARK_Data) == "table") then return shown end
        return nil
    end
    if shown then return shown end
    local get = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
    return itemLink(A.Call(get, bag, slot))
end

-- Marks are drawn on a small frame of ours laid over the button, a few levels above it: bag addons put their own
-- widgets (and other addons' icons) on child frames, which would cover textures drawn on the button itself.
B.layers = setmetatable({}, {__mode = "k"})
local function layer(button)
    local f = B.layers[button]
    if f then return f end
    f = button
    if type(CreateFrame) == "function" then
        local ok, made = pcall(CreateFrame, "Frame", nil, button)
        if ok and made then
            made:SetAllPoints(button)
            local level = method(button, "GetFrameLevel")
            if type(level) == "number" and made.SetFrameLevel then made:SetFrameLevel(level + 12) end
            f = made
        end
    end
    B.layers[button] = f
    return f
end
-- The upgrade arrow is Evertally's own texture (Media/ShapeArrow.tga), so it does not depend on which Blizzard art the
-- client ships, and sits in the top-right corner, away from where Pawn and bag addons put theirs.
local function arrow(button, on)
    local t = B.arrows[button]
    if not on then if t then t:Hide() end; return end
    if not t then
        local host = layer(button)
        if type(host.CreateTexture) ~= "function" then return end
        t = host:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\AddOns\\Evertally\\Media\\ShapeArrow"); t:SetVertexColor(0.35, 0.95, 0.42, 1)
        t:SetSize(16, 16); t:SetPoint("TOPRIGHT", 1, 1)
        B.arrows[button] = t
    end
    t:Show()
end
local function glow(button, on)
    local g = B.glows[button]
    if not on then if g then for _, t in ipairs(g) do t:Hide() end end; return end
    if not g then
        local host = layer(button)
        if type(host.CreateTexture) ~= "function" then return end
        g = {}
        local soft = host:CreateTexture(nil, "OVERLAY")
        soft:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); soft:SetBlendMode("ADD")
        soft:SetPoint("TOPLEFT", -12, 12); soft:SetPoint("BOTTOMRIGHT", 12, -12); soft:SetVertexColor(BLUE[1], BLUE[2], BLUE[3], 0.9)
        g[1] = soft
        for i, edge in ipairs({{"TOPLEFT", "TOPRIGHT", nil, 2}, {"BOTTOMLEFT", "BOTTOMRIGHT", nil, 2}, {"TOPLEFT", "BOTTOMLEFT", 2, nil}, {"TOPRIGHT", "BOTTOMRIGHT", 2, nil}}) do
            local t = host:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(BLUE[1], BLUE[2], BLUE[3], 1); t:SetPoint(edge[1]); t:SetPoint(edge[2])
            if edge[3] then t:SetWidth(edge[3]) else t:SetHeight(edge[4]) end
            g[i + 1] = t
        end
        B.glows[button] = g
    end
    for _, t in ipairs(g) do t:Show() end
end

local function visible(frame) return method(frame, "IsVisible") == true end
-- Runs for every frame of the whole interface: a plain field read first, so the tens of thousands of frames
-- that are no bag item button cost one lookup each and no method call.
local function marked(frame)
    return frame.GetBagID or frame.GetBag or frame.BGR or frame.ARK_Data or frame.bagID or frame.bag or frame.GetItemLocation
end
local function candidate(frame)
    if type(frame) ~= "table" or not marked(frame) then return false end
    if method(frame, "IsForbidden") == true or not visible(frame) then return false end
    local kind = method(frame, "GetObjectType")
    if kind ~= nil and kind ~= "Button" and kind ~= "ItemButton" and kind ~= "CheckButton" then return false end
    if B.Locate(frame) ~= nil then return true end
    return (type(frame.BGR) == "table" or type(frame.ARK_Data) == "table") and shownLink(frame) ~= nil
end

function B.Update(button)
    local isEmpty, isUpgrade = false, false
    if B.Enabled() and visible(button) then isEmpty, isUpgrade = B.Assess(B.LinkOf(button)) end
    glow(button, isEmpty == true); arrow(button, isUpgrade == true)
    return isEmpty == true or isUpgrade == true
end

-- A full pass walks every frame to find item buttons a bag addon created since the last pass; a light pass
-- only repaints the buttons already found. Both are cheap enough at a few per second.
function B.Scan(full)
    B.scheduled = false
    if not B.Enabled() then
        for button in pairs(B.glows) do glow(button, false) end
        for button in pairs(B.arrows) do arrow(button, false) end
        return 0
    end
    local clock = type(debugprofilestop) == "function" and debugprofilestop or nil
    local started = clock and clock()
    -- The full walk is the expensive part: at most once per FULL_GAP seconds, whoever asks.
    if full and B.lastFull and A.Monotonic() - B.lastFull < FULL_GAP then full = false end
    if full and type(EnumerateFrames) == "function" then
        B.lastFull = A.Monotonic()
        local ok, frame = pcall(EnumerateFrames); local guard = 0
        while ok and frame and guard < 60000 do
            guard = guard + 1; B.walked = guard
            if candidate(frame) then B.buttons[frame] = true end
            ok, frame = pcall(EnumerateFrames, frame)
        end
    end
    local lit = 0
    for button in pairs(B.buttons) do if B.Update(button) then lit = lit + 1 end end
    B.lit = lit
    if started then local ms = clock() - started; B.lastMs = ms; if full then B.lastFullMs = ms end end
    return lit
end

function B.Request(full)
    B.wantFull = B.wantFull or full
    if B.scheduled then return end
    if not (C_Timer and type(C_Timer.After) == "function") then local f = B.wantFull; B.wantFull = false; B.Scan(f); return end
    B.scheduled = true
    C_Timer.After(0.15, function() local f = B.wantFull; B.wantFull = false; pcall(B.Scan, f) end)
end

-- /etally bags: what the addon sees, printed and kept in the diagnostic log, so a missing mark can be traced.
function B.Diagnose()
    B.wanted = {}; B.lastFull = nil; local lit = B.Scan(true); local found = 0
    for _ in pairs(B.buttons) do found = found + 1 end
    A.Print(string.format(A.L("bagDiag"), B.walked or 0, found, lit) .. string.format(" (%.1f ms)", B.lastFullMs or 0))
    A.DiagLog(string.format("bags walked=%d buttons=%d marked=%d ms=%.1f", B.walked or 0, found, lit, B.lastFullMs or 0))
    local count = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local get = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
    for bag = 0, math.min(10, A.Number(NUM_BAG_SLOTS) or 4) do
        for slot = 1, math.min(200, A.Number((A.Call(count, bag))) or 0) do
            local link = itemLink((A.Call(get, bag, slot)))
            local item = link and A.Gear.Item(link)
            if item and item.known and slotsFor[item.equipLoc] then
                local isEmpty, isUpgrade, reason = B.Assess(link)
                local line = string.format("%s %s empty=%s upgrade=%s (%s) usable=%s tooltip=%s", item.name or "?", item.equipLoc, tostring(isEmpty), tostring(isUpgrade), tostring(reason), tostring(item.usable), tostring(item.tooltipRead == true))
                A.Print(line); A.DiagLog("bags " .. line)
            end
        end
    end
    for button in pairs(B.buttons) do
        local bag, slot = B.Locate(button)
        A.DiagLog(string.format("bags button %s bag=%s slot=%s link=%s", tostring(method(button, "GetName")), tostring(bag), tostring(slot), tostring(B.LinkOf(button) ~= nil)))
    end
    return found, lit
end

local function anyVisible() for button in pairs(B.buttons) do if visible(button) then return true end end end
local function opened() B.Request(true); if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0.6, function() B.Request(true) end) end end
function B.Hook()
    if B.hooked or type(hooksecurefunc) ~= "function" then return end
    B.hooked = true
    for _, name in ipairs({"ToggleAllBags", "OpenAllBags", "ToggleBackpack", "OpenBackpack", "ToggleBag", "OpenBag"}) do
        if type(_G[name]) == "function" then pcall(hooksecurefunc, name, opened) end
    end
    if C_Timer and type(C_Timer.NewTicker) == "function" then
        -- Bag addons re-sort and recycle buttons without an event: repaint the buttons already found while bags are
        -- open. New buttons are looked for only when bags open or change, never on this timer.
        C_Timer.NewTicker(1, function()
            if not B.Enabled() or not anyVisible() then return end
            pcall(B.Scan, false)
        end)
    end
end

local function changed() B.wanted = {}; B.Request(true) end
A.On("PLAYER_LOGIN", function() B.Hook(); B.Request(true) end)
A.On("BAG_UPDATE_DELAYED", function() B.Request(true) end)
A.On("PLAYER_EQUIPMENT_CHANGED", changed)
A.On("PLAYER_LEVEL_UP", changed)
A.On("SPELLS_CHANGED", changed)
-- Other addons ask for item data all the time; only an item this module is waiting for is worth a repaint.
A.On("GET_ITEM_INFO_RECEIVED", function()
    if not B.pendingInfo or not anyVisible() then return end
    B.pendingInfo = false; B.Request(false)
end)
A.On("BANKFRAME_OPENED", function() B.Request(true) end)
