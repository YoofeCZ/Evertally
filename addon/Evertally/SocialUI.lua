local _, A = ...
-- Windows for the social tools (Social.lua): the question "may X look at you?", the viewer of what somebody showed you
-- (with "I would like this" and "I offer ..." for a trade proposal), proposals and meets, and the "Social" page.
-- Built lazily and only from helpers the main window already exports (A.UIKit). Every entry point is wrapped, so a
-- problem here can never stop the rest of the addon: the chat commands in Social.lua keep working.
local kit
local function K() if not kit then kit = A.UIKit() end return kit end
local popup, queue, viewer, page = nil, {}, nil, nil
local FONT = "Fonts\\ARIALN.TTF"

local function plain(text) return (tostring(A.Plain(text) or ""):gsub("|", "||")) end
local function base(name) return (A.Text(name, 150) or ""):match("^[^-]+") or "?" end
local function money(copper)
    copper = math.floor(A.Number(copper, 0) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 then out[#out + 1] = s .. "s" end
    if c > 0 then out[#out + 1] = c .. "c" end
    return #out > 0 and table.concat(out, " ") or "0"
end
local function itemName(id)
    local name = A.Call(GetItemInfo, id)
    if not name and C_Item then
        name = A.Call(C_Item.GetItemNameByID, id)
        if not name and type(C_Item.RequestLoadItemDataByID) == "function" then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
    return plain(name or ("Item #" .. id))
end
local function itemsText(list)
    local out = {}
    for _, e in ipairs(list or {}) do out[#out + 1] = itemName(e[1]) .. (e[2] > 1 and (" x" .. e[2]) or "") end
    return #out > 0 and table.concat(out, ", ") or "-"
end
local function zoneName(mapId)
    local info = C_Map and A.Call(C_Map.GetMapInfo, mapId)
    return plain(A.Field(info, "name") or (A.L("map") .. " #" .. tostring(mapId)))
end

local function itemIcon(id)
    local icon = A.Call(GetItemIcon, id)
    if not icon and C_Item then icon = A.Call(C_Item.GetItemIconByID, id) end
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end
--- A proposal's item rows: icon, name and count, with the game's item tooltip (stats included) on hover.
local ROW_H, MAX_ROWS = 24, 16
local function layoutItems(f, spec)
    f.itemHeads = f.itemHeads or {}
    f.itemRows = f.itemRows or {}
    local y = -46
    local used = 0
    for g, group in ipairs(spec.items or {}) do
        local head = f.itemHeads[g]
        if not head then head = K().label(f, 12, K().C.gold); head:SetWidth(404); f.itemHeads[g] = head end
        head:ClearAllPoints(); head:SetPoint("TOPLEFT", 18, y); head:SetText(group.head); head:Show(); y = y - 20
        for _, e in ipairs(group.list) do
            if used < MAX_ROWS then
                used = used + 1
                local row = f.itemRows[used]
                if not row then
                    row = CreateFrame("Button", nil, f); row:SetSize(404, ROW_H - 2)
                    row.hover = row:CreateTexture(nil, "HIGHLIGHT"); row.hover:SetAllPoints(row); row.hover:SetColorTexture(1, 1, 1, 0.08)
                    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(20, 20); row.icon:SetPoint("LEFT", 2, 0)
                    row.text = K().label(row, 12, K().C.mist); row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0); row.text:SetWidth(360)
                    row:SetScript("OnEnter", function(self)
                        if self.itemId and GameTooltip then pcall(function() GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.itemId); GameTooltip:Show() end) end
                    end)
                    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                    f.itemRows[used] = row
                end
                row.itemId = e[1]
                row:ClearAllPoints(); row:SetPoint("TOPLEFT", 18, y)
                row.icon:SetTexture(itemIcon(e[1]))
                row.text:SetText(itemName(e[1]) .. (e[2] > 1 and ("  x" .. e[2]) or ""))
                row:Show(); y = y - ROW_H
            end
        end
        local none = f.itemHeads[g].none
        if #group.list == 0 then
            if not none then none = K().label(f, 12, K().C.mist); none:SetWidth(404); f.itemHeads[g].none = none end
            none:ClearAllPoints(); none:SetPoint("TOPLEFT", 18, y); none:SetText("-"); none:Show(); y = y - ROW_H
        elseif none then none:Hide() end
    end
    for i = used + 1, #f.itemRows do f.itemRows[i]:Hide() end
    for g = #(spec.items or {}) + 1, #f.itemHeads do f.itemHeads[g]:Hide(); if f.itemHeads[g].none then f.itemHeads[g].none:Hide() end end
    return y
end

-- ---------------------------------------------------------------- one popup, answered one question at a time
local function closePopup() if popup then popup:Hide() end; popup.current = nil; local nextSpec = table.remove(queue, 1); if nextSpec then A.SocialShowPopup(nextSpec) end end
local function ensurePopup()
    if popup then return popup end
    local k = K()
    local f = CreateFrame("Frame", "EvertallySocialPopup", UIParent)
    f:SetSize(440, 360); f:SetPoint("TOP", UIParent, "TOP", 0, -130); f:SetFrameStrata("DIALOG"); f:EnableMouse(true)
    A.NativeFrame(f, k.C)
    f.title = k.label(f, 15, k.C.gold); f.title:SetPoint("TOPLEFT", 18, -16); f.title:SetWidth(404)
    f.body = k.label(f, 12, k.C.mist); f.body:SetPoint("TOPLEFT", 18, -46); f.body:SetWidth(404); f.body:SetJustifyV("TOP")
    f.checks, f.buttons = {}, {}
    for i = 1, 6 do
        local b = k.Button(f, nil, 404, "ghost", function() end); b:SetPoint("TOPLEFT", 18, -122 - (i - 1) * 32); b:Hide(); f.checks[i] = b
    end
    for i = 1, 4 do f.buttons[i] = k.Button(f, nil, 98, i == 1 and "primary" or "ghost", function() end); f.buttons[i]:Hide() end
    popup = f
    return f
end
--- spec = {title, body, checks={{key,label,on}}, buttons={{label,primary,fn(selected)}}, id}
function A.SocialShowPopup(spec)
    local ok = pcall(function()
        local f = ensurePopup()
        if f:IsShown() and f.current then queue[#queue + 1] = spec; return end
        f.current = spec
        f.title:SetText(spec.title or "")
        f.body:ClearAllPoints()
        if spec.items then
            local y = layoutItems(f, spec)
            f.body:SetPoint("TOPLEFT", 18, y - 6); f.body:SetText(spec.body or "")
            local lines = select(2, (spec.body or ""):gsub("\n", "\n")) + (spec.body and spec.body ~= "" and 1 or 0)
            f:SetHeight(math.max(170, math.min(560, -y + 6 + lines * 16 + 80)))
        else
            layoutItems(f, {})
            f.body:SetPoint("TOPLEFT", 18, -46); f.body:SetText(spec.body or "")
            f:SetHeight(360)
        end
        local selected = {}
        for i, b in ipairs(f.checks) do
            local c = spec.checks and spec.checks[i]
            if c then
                selected[c.key] = c.on and true or false
                local function paint() b.text:SetText((selected[c.key] and "[x]  " or "[  ]  ") .. c.label) end
                b:SetScript("OnClick", function() selected[c.key] = not selected[c.key]; paint() end)
                paint(); b:Show()
            else b:Hide() end
        end
        local shown = spec.buttons or {}
        for i, b in ipairs(f.buttons) do
            local def = shown[i]
            if def then
                b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", 18 + (i - 1) * 102, 16); b.text:SetText(def.label); b:Show()
                b:SetScript("OnClick", function() pcall(def.fn, selected); closePopup() end)
            else b:Hide() end
        end
        f:Show()
    end)
    if not ok then A.errors.social_popup = (A.errors.social_popup or 0) + 1 end
end

-- ---------------------------------------------------------------- green highlight of a pointed-at item in the open bags
-- The overlays are frames of our own laid over the bag buttons (nothing is written to Blizzard's frames), so a
-- pointer from another player can never taint the bags. They follow the buttons while the bags are open.
local overlays = {}
local function overlay(i)
    local o = overlays[i]
    if o then return o end
    o = CreateFrame("Frame", nil, UIParent)
    o.fill = o:CreateTexture(nil, "OVERLAY"); o.fill:SetAllPoints(o); o.fill:SetColorTexture(0.1, 1, 0.2, 0.28)
    o.edges = {}
    for n = 1, 4 do local e = o:CreateTexture(nil, "OVERLAY"); e:SetColorTexture(0.2, 1, 0.3, 1); o.edges[n] = e end
    o.edges[1]:SetPoint("TOPLEFT"); o.edges[1]:SetPoint("TOPRIGHT"); o.edges[1]:SetHeight(3)
    o.edges[2]:SetPoint("BOTTOMLEFT"); o.edges[2]:SetPoint("BOTTOMRIGHT"); o.edges[2]:SetHeight(3)
    o.edges[3]:SetPoint("TOPLEFT"); o.edges[3]:SetPoint("BOTTOMLEFT"); o.edges[3]:SetWidth(3)
    o.edges[4]:SetPoint("TOPRIGHT"); o.edges[4]:SetPoint("BOTTOMRIGHT"); o.edges[4]:SetWidth(3)
    o:SetScript("OnUpdate", function(self) self:SetAlpha(0.65 + 0.35 * math.abs(math.sin((GetTime and GetTime() or 0) * 3))) end)
    o:EnableMouse(false); overlays[i] = o
    return o
end
-- Works with the default bags and with bag addons (Baganator, Bagnon, ElvUI, ...): any shown item button is recognised
-- by what it exposes (an item id, or a bag and slot). Only read, never written.
local function buttonItem(b)
    local id
    local bgr = rawget(b, "BGR")
    if type(bgr) == "table" then id = tonumber(bgr.itemID) end
    if not id and type(b.info) == "table" then id = tonumber(b.info.itemID) end
    if not id and type(b.GetItemID) == "function" then id = tonumber(A.Call(b.GetItemID, b)) end
    if not id then
        local bag, slot = rawget(b, "bagID") or rawget(b, "bagId"), rawget(b, "slotID") or rawget(b, "slotId")
        if not bag and type(b.GetBagID) == "function" then bag = A.Call(b.GetBagID, b) end
        if not bag then local par = b.GetParent and b:GetParent(); bag = par and par.GetID and par:GetID() end
        slot = slot or (b.GetID and b:GetID())
        if tonumber(bag) and tonumber(slot) and slot > 0 and A.ContainerItemId then id = A.ContainerItemId(bag, slot) end
    end
    return id
end
-- Only buttons that sit inside a bag window count (never action bars, vendors, the trade window...): one of the frames
-- above the button is named like a bag window (ContainerFrame, Baganator, Bagnon, ElvUI containers, ...).
local BAG_WORDS = {"containerframe", "baganator", "bagnon", "bagbrother", "inventorian", "adibags", "arkinventory", "combuctor", "elvui_container", "backpack", "bagview", "bagsframe", "cargbags"}
local function insideBag(b)
    local node = b
    for _ = 1, 12 do
        node = node and node.GetParent and node:GetParent()
        if not node or node == UIParent then return false end
        local name = node.GetName and node:GetName()
        if type(name) == "string" and name ~= "" then
            name = name:lower()
            for _, word in ipairs(BAG_WORDS) do if name:find(word, 1, true) then return true end end
        end
    end
    return false
end
local function bagButtons(visit)
    if type(EnumerateFrames) ~= "function" then return end
    local f = EnumerateFrames()
    local n = 0
    while f and n < 20000 do
        n = n + 1
        if f.IsVisible and f.GetObjectType and f:GetObjectType() == "Button" and f:IsVisible() then
            local w = f.GetWidth and f:GetWidth() or 0
            if w >= 20 and w <= 90 and insideBag(f) then
                local ok, id = pcall(buttonItem, f)
                if ok and id then visit(f, id) end
            end
        end
        f = EnumerateFrames(f)
    end
end
function A.SocialHighlightRefresh()
    local points, now, used = A.SocialPointers and A.SocialPointers() or {}, A.Now(), 0
    local any = false
    for id, p in pairs(points) do if now - p.at > 120 then points[id] = nil else any = true end end
    if any then
        bagButtons(function(button, id)
            if points[id] and used < 40 then
                used = used + 1
                local o = overlay(used)
                o:SetParent(UIParent); o:SetFrameStrata("TOOLTIP"); o:ClearAllPoints(); o:SetAllPoints(button); o:Show()
            end
        end)
    end
    for i = used + 1, #overlays do overlays[i]:Hide() end
end
if C_Timer and type(C_Timer.NewTicker) == "function" then C_Timer.NewTicker(0.5, function() pcall(A.SocialHighlightRefresh) end) end

-- ---------------------------------------------------------------- reactions to what happens
local function kindsText(kinds)
    local out = {}
    for _, key in ipairs({"i", "s", "t", "p", "g", "w"}) do
        if kinds:find(key, 1, true) then out[#out + 1] = A.L(({i = "socialInv", s = "socialStats", t = "socialTalents", p = "socialProf", g = "socialGold", w = "socialWeb"})[key]) end
    end
    return table.concat(out, ", ")
end
local function askPopup(request)
    local checks = {}
    local keys = {"i", "s", "t", "p", "g", "w"}
    local labels = {i = "socialInv", s = "socialStats", t = "socialTalents", p = "socialProf", g = "socialGold", w = "socialWebAsk"}
    for _, key in ipairs(keys) do
        -- gold and the website copy are never ticked for you
        if request.kinds:find(key, 1, true) then checks[#checks + 1] = {key = key, label = A.L(labels[key]), on = key ~= "g" and key ~= "w"} end
    end
    local function chosen(sel) local allowed = ""; for _, key in ipairs(keys) do if sel[key] then allowed = allowed .. key end end; return allowed end
    A.SocialShowPopup({id = request.id, title = string.format(A.L("socialAskTitle"), plain(base(request.sender))), body = A.L("socialAskNote"), checks = checks, buttons = {
        {label = A.L("socialAllowOnce"), fn = function(sel) A.AnswerRequest(request.id, chosen(sel), false) end},
        {label = A.L("socialAllowAlways"), fn = function(sel) A.AnswerRequest(request.id, chosen(sel), true) end},
        {label = A.L("socialDeny"), fn = function() A.DenyRequest(request.id, false) end},
        {label = A.L("socialBlock"), fn = function() A.DenyRequest(request.id, true) end},
    }})
end
local function proposalPopup(entry)
    local lines = {}
    if (entry.gold or 0) > 0 then lines[#lines + 1] = string.format(A.L("propGold"), money(entry.gold)) end
    if entry.note and entry.note ~= "" then lines[#lines + 1] = string.format(A.L("propNote"), plain(entry.note)) end
    A.SocialShowPopup({id = entry.id, title = string.format(A.L("propTitle"), plain(base(entry.peer))), body = table.concat(lines, "\n"),
        items = {{head = A.L("propWants"), list = entry.want or {}}, {head = A.L("propOffers"), list = entry.offer or {}}}, buttons = {
        {label = A.L("propAccept"), fn = function()
            A.AnswerProposal(entry.id, true, "")
            if A.PrepareTrade then A.PrepareTrade(entry.peer, entry.want) end
            -- Close enough to trade: open the trade window straight away; otherwise just tell them to meet.
            if A.TradeWithPlayer and A.TradeWithPlayer(entry.peer) then A.Print(A.L("propTradeOpened")) else A.Print(A.L("propAcceptedHint")) end
        end},
        {label = A.L("propDecline"), fn = function() A.AnswerProposal(entry.id, false, "") end},
    }})
end
local function meetText(meet)
    local when = meet.minutes > 0 and string.format(A.L("socialMeetIn"), meet.minutes) or A.L("socialMeetNow")
    return string.format("%s (%.1f, %.1f) - %s", zoneName(meet.mapId), meet.x * 100, meet.y * 100, when)
end
local function meetPopup(meet)
    A.SocialShowPopup({id = meet.id, title = string.format(A.L("meetTitle"), plain(base(meet.sender))), body = plain(meet.label ~= "" and meet.label or "-") .. "\n" .. meetText(meet), buttons = {
        {label = A.L("meetWaypoint"), fn = function() if not A.SetMeetWaypoint(meet) then A.Print(A.L("mapUnavailable")) end end},
        {label = A.L("meetNavigate"), fn = function()
            local label = meet.label ~= "" and meet.label or A.L("meetDefault")
            local ok, err = A.NavigateToPoint(label, meet.mapId, meet.x, meet.y, {view = "people"})
            A.Print(ok and string.format(A.L("navStarted"), plain(label)) or A.L("navErr_" .. tostring(err)))
        end},
        {label = A.L("meetDismiss"), fn = function() end},
    }})
end

-- ---------------------------------------------------------------- viewer: what somebody showed you
local SORTS = {"default", "quality", "name", "type"}
local TYPE_KEYS = {Weapon = "viewType_weapon", Armor = "viewType_armor", Consumable = "viewType_consumable", Container = "viewType_container", Projectile = "viewType_ammo", Quiver = "viewType_ammo",
    Trade = "viewType_trade", ["Trade Goods"] = "viewType_trade", Recipe = "viewType_recipe", Reagent = "viewType_trade", Quest = "viewType_quest", Miscellaneous = "viewType_misc", Key = "viewType_misc", Gem = "viewType_trade"}
local function itemMeta(id)
    local name, _, quality, _, _, kind = A.Call(GetItemInfo, id)
    return {name = name and plain(name) or nil, quality = A.Number(quality, 0, 8) or -1, kind = type(kind) == "string" and kind or nil}
end
local function typeGroup(meta)
    local key = meta.kind and TYPE_KEYS[meta.kind]
    return key and A.L(key) or (meta.kind and plain(meta.kind)) or A.L("viewType_unknown")
end
--- Filters (case-insensitive substring on the item name; an unknown name matches by id) and orders cells; with "type" sort inserts group headers.
--- entries[i] = {id, count, cell}. Returns the final list for IconGrid and how many items matched.
local function arrange(entries, query, sortKey, slotOrder)
    local q = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local rows = {}
    for _, e in ipairs(entries) do
        local meta = itemMeta(e.id)
        e.meta = meta
        local hay = (meta.name or ("item " .. e.id)):lower()
        if q == "" or hay:find(q, 1, true) or tostring(e.id) == q then rows[#rows + 1] = e end
    end
    local function byName(a, b) return (a.meta.name or "~") < (b.meta.name or "~") end
    if sortKey == "quality" then
        table.sort(rows, function(a, b) if a.meta.quality ~= b.meta.quality then return a.meta.quality > b.meta.quality end; if byName(a, b) ~= byName(b, a) then return byName(a, b) end; return a.id < b.id end)
    elseif sortKey == "name" then
        table.sort(rows, function(a, b) if byName(a, b) ~= byName(b, a) then return byName(a, b) end; return a.id < b.id end)
    elseif sortKey == "type" then
        for _, e in ipairs(rows) do e.group = typeGroup(e.meta) end
        table.sort(rows, function(a, b) if a.group ~= b.group then return a.group < b.group end; if a.meta.quality ~= b.meta.quality then return a.meta.quality > b.meta.quality end; return a.id < b.id end)
    elseif slotOrder then
        table.sort(rows, function(a, b) return (a.order or 0) < (b.order or 0) end)
    else
        table.sort(rows, function(a, b) return a.id < b.id end)
    end
    local out, lastGroup = {}, nil
    for _, e in ipairs(rows) do
        if sortKey == "type" and e.group ~= lastGroup then out[#out + 1] = {header = e.group}; lastGroup = e.group end
        out[#out + 1] = e.cell
    end
    return out, #rows
end
local openViewer
function openViewer(view)
    local ok, err = pcall(function()
        local k = K()
        local C = k.C
        if not viewer then
            local f = CreateFrame("Frame", "EvertallyViewFrame", UIParent)
            f:SetSize(820, 560); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
            A.NativeFrame(f, C)
            -- Two clearly separated surfaces: the shared character on the left,
            -- your proposal on the right. Background textures never intercept input.
            local header=k.fill(f,{0.10,0.095,0.095},1,"BACKGROUND")
            header:ClearAllPoints();header:SetPoint("TOPLEFT",5,-5);header:SetPoint("TOPRIGHT",-5,-5);header:SetHeight(52)
            local headerLine=f:CreateTexture(nil,"BORDER");headerLine:SetPoint("TOPLEFT",7,-55);headerLine:SetPoint("TOPRIGHT",-7,-55);headerLine:SetHeight(1);k.paint(headerLine,{0.62,0.48,0.26},0.65)
            local profilePanel=f:CreateTexture(nil,"BACKGROUND");profilePanel:SetPoint("TOPLEFT",14,-96);profilePanel:SetPoint("BOTTOMLEFT",14,32);profilePanel:SetWidth(454);k.paint(profilePanel,{0.065,0.065,0.075},0.96)
            local offerPanel=f:CreateTexture(nil,"BACKGROUND");offerPanel:SetPoint("TOPLEFT",482,-62);offerPanel:SetPoint("BOTTOMRIGHT",-14,32);k.paint(offerPanel,{0.095,0.088,0.088},0.98)
            local divider=f:CreateTexture(nil,"BORDER");divider:SetPoint("TOPLEFT",482,-62);divider:SetPoint("BOTTOMLEFT",482,32);divider:SetWidth(1);k.paint(divider,{0.65,0.50,0.25},0.65)
            f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", function() f:StartMoving() end); f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
            f.title = k.label(f, 18, C.gold); f.title:SetPoint("TOPLEFT", 20, -10); f.title:SetWidth(560)
            f.sub = k.label(f, 10, C.mist); f.sub:SetPoint("TOPLEFT", 20, -34); f.sub:SetWidth(560)
            f.close = k.Button(f, nil, 30, "ghost", function() f:Hide() end); f.close:SetPoint("TOPRIGHT", -14, -12); f.close.text:SetText("x")
            f.pointChip = k.Chip(f, function() f.pointMode = not f.pointMode; A.SocialRefreshViewer() end)
            f.pointChip:SetPoint("TOPRIGHT", -54, -14)
            f.pointInfo = k.label(f, 10, C.green); f.pointInfo:SetPoint("TOPRIGHT", f.pointChip, "TOPLEFT", -10, 3); f.pointInfo:SetWidth(250); f.pointInfo:SetHeight(26); f.pointInfo:SetJustifyH("RIGHT")
            f.pointChip:HookScript("OnEnter", function() if GameTooltip then GameTooltip:SetOwner(f.pointChip, "ANCHOR_BOTTOM"); GameTooltip:SetText(A.L("viewPointInfo"), 1, 1, 1, 1, true); GameTooltip:Show() end end)
            f.pointChip:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            f.tabs = {}
            local previous
            for _, mode in ipairs({"equipped", "stats", "talents", "bags", "professions", "gold"}) do
                local chip = k.Chip(f, function() f.mode = mode; A.SocialRefreshViewer() end)
                if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 18, -66) end
                f.tabs[mode] = chip; previous = chip
            end
            -- what they showed: icons for gear and bags, rows for professions and gold
            f.search = k.SearchBox(f, 230, function(value) if value ~= f.query then f.query = value; A.SocialRefreshViewer() end end); f.search:SetPoint("TOPLEFT", 22, -98)
            f.sortBtn = k.Button(f, nil, 150, "ghost", function() f.sort = (f.sort or 1) % #SORTS + 1; A.SocialRefreshViewer() end); f.sortBtn:SetPoint("LEFT", f.search, "RIGHT", 10, 0)
            f.summary = k.label(f, 10, C.faint); f.summary:SetPoint("LEFT", f.sortBtn, "RIGHT", 10, 0); f.summary:SetWidth(40)
            f.grid = k.IconGrid(f, 40, 6); f.grid:ClearAllPoints(); f.grid:SetPoint("TOPLEFT", 18, -130); f.grid:SetPoint("BOTTOMLEFT", 18, 36); f.grid:SetWidth(444)
            f.list = k.ListView(f, 102); f.list:ClearAllPoints(); f.list:SetPoint("TOPLEFT", 18, -102); f.list:SetPoint("BOTTOMLEFT", 18, 36); f.list:SetWidth(444); f.list.child:SetWidth(436)
            -- what I offer back
            f.offerTitle = k.label(f, 13, C.gold); f.offerTitle:SetPoint("TOPLEFT", 492, -68); f.offerTitle:SetWidth(310)
            f.offers = k.IconGrid(f, 36, 6); f.offers:ClearAllPoints(); f.offers:SetPoint("TOPLEFT", 492, -92); f.offers:SetSize(310, 214)
            f.goldLabel = k.label(f, 11, C.mist); f.goldLabel:SetPoint("TOPLEFT", 492, -318)
            f.gold = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); f.gold:SetSize(90, 24); f.gold:SetPoint("TOPLEFT", 496, -334)
            f.gold:SetAutoFocus(false); f.gold:SetMaxLetters(7); f.gold:SetFont(FONT, 12, ""); f.gold:SetNumeric(true)
            f.noteLabel = k.label(f, 11, C.mist); f.noteLabel:SetPoint("TOPLEFT", 492, -364)
            f.note = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); f.note:SetSize(300, 24); f.note:SetPoint("TOPLEFT", 496, -380)
            f.note:SetAutoFocus(false); f.note:SetMaxLetters(120); f.note:SetFont(FONT, 12, "")
            f.send = k.Button(f, nil, 180, "primary", function() A.SocialSendFromViewer() end); f.send:SetPoint("BOTTOMLEFT", 492, 36)
            f.status = k.label(f, 11, C.green); f.status:SetPoint("BOTTOMLEFT", 492, 72); f.status:SetWidth(310)
            f.hint = k.label(f, 10, C.faint); f.hint:SetPoint("BOTTOMLEFT", 18, 12); f.hint:SetWidth(780)
            if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EvertallyViewFrame" end
            viewer = f
        end
        viewer.view = view; viewer.mode = viewer.mode or "equipped"; viewer.wanted, viewer.offered = {}, {}
        viewer.gold:SetText(""); viewer.note:SetText(""); viewer.status:SetText("")
        viewer:Show(); A.SocialRefreshViewer()
    end)
    if not ok then A.errors.social_viewer = (A.errors.social_viewer or 0) + 1; A.lastUIError = tostring(err) end
end

local function cycle(map, id, stack)
    -- off -> 1 -> everything -> off
    local now = map[id]
    if not now then map[id] = 1
    elseif now < stack and stack > 1 then map[id] = stack
    else map[id] = nil end
end

function A.SocialRefreshViewer()
    local f = viewer
    if not f or not f:IsShown() or not f.view then return end
    local k = K();local v = f.view
    f.title:SetText(string.format(A.L("viewTitle"), plain(base(v.sender))))
    f.sub:SetText(string.format(A.L("viewReceived"), (A.Call(date, "%H:%M", v.at) or "")) .. "   " .. kindsText(v.kinds or ""))
    for mode, chip in pairs(f.tabs) do chip.SetLabel(A.L("viewTab_" .. mode)); chip.SetOn(f.mode == mode) end
    f.offerTitle:SetText(A.L("viewMyOffer")); f.goldLabel:SetText(A.L("viewGoldOffer")); f.noteLabel:SetText(A.L("viewNote"))
    f.send.text:SetText(A.L("viewSend")); f.hint:SetText(f.pointMode and A.L("viewPointHint") or A.L("viewHint")); f.hint:SetTextColor(unpack(f.pointMode and k.C.green or k.C.faint))
    f.pointChip.SetLabel(A.L("viewPoint")); f.pointInfo:SetText(A.L("viewPointInfo")); f.pointChip.SetOn(f.pointMode == true)
    local icons = f.mode == "equipped" or f.mode == "bags"
    f.grid:SetShown(icons); f.list:SetShown(not icons)
    f.search:SetShown(icons); f.sortBtn:SetShown(icons); f.summary:SetShown(icons)
    f.search.hint:SetText(A.L("viewSearch")); f.sortBtn.text:SetText(A.L("viewSortBy") .. " " .. A.L("viewSort_" .. SORTS[f.sort or 1]))
    if f.mode == "equipped" then
        local entries = {}
        for i, e in ipairs(v.equipped) do
            local id = e[2]
            local slotName = A.L("viewSlot" .. e[1])
            entries[#entries + 1] = {id = id, order = e[1] * 100 + i, cell = {itemId = id, icon = k.itemIcon(id), slot = slotName, mark = f.wanted[id] and "want" or nil, markText = f.wanted[id] and A.L("viewWant") or nil,
                onClick = function() cycle(f.wanted, id, 1); A.SocialRefreshViewer() end}}
        end
        local cells, shown = arrange(entries, f.query, SORTS[f.sort or 1], true)
        f.grid.SetCells(cells, (f.query or "") ~= "" and A.L("viewNoMatch") or A.L("noData"))
        f.summary:SetText(string.format(A.L("viewCount"), shown, #entries))
    elseif f.mode == "bags" then
        local entries, pieces = {}, 0
        for _, e in ipairs(v.bags) do
            local id, n = e[1], e[2]
            pieces = pieces + n
            entries[#entries + 1] = {id = id, cell = {itemId = id, icon = k.itemIcon(id), count = n, mark = f.wanted[id] and "want" or nil, markText = f.wanted[id] and (f.wanted[id] >= n and n > 1 and "x" .. n or A.L("viewWant")) or nil,
                onClick = function()
                    if f.pointMode then
                        local sent = A.SendPointer and A.SendPointer(v.sender, id)
                        f.status:SetText(sent and string.format(A.L("viewPointed"), itemName(id), plain(base(v.sender))) or "")
                    else cycle(f.wanted, id, n); A.SocialRefreshViewer() end
                end}}
        end
        local cells, shown = arrange(entries, f.query, SORTS[f.sort or 1], false)
        f.grid.SetCells(cells, (f.query or "") ~= "" and A.L("viewNoMatch") or A.L("noData"))
        f.summary:SetText(string.format(A.L("viewCount"), shown, #entries))
    elseif f.mode == "stats" then
        local rows = {}
        for _, key in ipairs(A.ArmoryStatKeys or {}) do
            if v.stats and v.stats[key] then rows[#rows + 1] = {title = plain(A.ArmoryStatLabel(key)), icon = k.ICON.unknown, right = string.format("%g", v.stats[key])} end
        end
        f.list.SetItems(rows, A.L("viewNoStats"))
    elseif f.mode == "talents" then
        local rows = {}
        for _, tree in ipairs(v.talents or {}) do
            rows[#rows + 1] = {title = plain(tree.name ~= "" and tree.name or "?"), sub = string.format(A.L("viewTalentPoints"), #tree.ranks), icon = k.ICON.unknown, right = tostring(tree.spent)}
        end
        f.list.SetItems(rows, A.L("viewNoTalents"))
    elseif f.mode == "professions" then
        local rows = {}
        for _, p in ipairs(v.professions) do
            rows[#rows + 1] = {title = p.name ~= "" and p.name or ("#" .. p.id), sub = string.format(A.L("viewRecipes"), #p.recipes), icon = k.ICON.profession, right = string.format("%s/%s", p.skill or "?", p.max or "?")}
        end
        f.list.SetItems(rows, A.L("viewNoProf"))
    else
        f.list.SetItems({{title = v.gold and money(v.gold) or A.L("viewNoGold"), sub = A.L("socialGold"), icon = k.ICON.vendor}}, A.L("noData"))
    end
    -- what I could offer: my own bags
    local mine = {}
    for _, e in ipairs(A.OwnInventory().bags) do
        local id, n = e[1], e[2]
        mine[#mine + 1] = {id = id, cell = {itemId = id, icon = k.itemIcon(id), count = n, mark = f.offered[id] and "offer" or nil, markText = f.offered[id] and (f.offered[id] >= n and n > 1 and "x" .. n or A.L("viewOffer")) or nil,
            onClick = function() cycle(f.offered, id, n); A.SocialRefreshViewer() end}}
    end
    local cells = arrange(mine, f.query, SORTS[f.sort or 1], false)
    f.offers.SetCells(cells, (f.query or "") ~= "" and #mine > 0 and A.L("viewNoMatch") or A.L("viewNoOffer"))
end

function A.SocialSendFromViewer()
    local f = viewer
    if not f or not f.view then return end
    local want, offer = {}, {}
    for id, n in pairs(f.wanted) do want[#want + 1] = {id, n} end
    for id, n in pairs(f.offered) do offer[#offer + 1] = {id, n} end
    table.sort(want, function(a, b) return a[1] < b[1] end); table.sort(offer, function(a, b) return a[1] < b[1] end)
    local gold = (A.Number(tonumber(f.gold:GetText() or ""), 0, 9999) or 0) * 10000
    local ok, err = A.SendProposal(f.view.sender, {want = want, offer = offer, gold = gold, note = f.note:GetText() or ""})
    f.status:SetText(ok and string.format(A.L("viewSent"), plain(base(f.view.sender))) or A.L("socialErr_" .. tostring(err)))
end

-- ---------------------------------------------------------------- the page in the main window
local function viewRows()
    local rows = {}
    for _, v in ipairs(A.social.views) do
        local view = v
        rows[#rows + 1] = {title = plain(base(v.sender)), sub = kindsText(v.kinds or "") .. "  ·  " .. (A.Call(date, "%H:%M", v.at) or ""), icon = K().ICON.peers, onClick = function() openViewer(view) end}
    end
    return rows
end
local function proposalRows()
    local rows = {}
    for _, p in ipairs(A.social.proposals) do
        local entry = p
        rows[#rows + 1] = {title = (p.dir == "in" and A.L("socialIn") or A.L("socialOut")) .. " " .. plain(base(p.peer)), sub = itemsText(p.want) .. "  <>  " .. itemsText(p.offer) .. ((p.gold or 0) > 0 and ("  +" .. money(p.gold)) or ""),
            icon = K().ICON.item, tag = A.Upper(A.L("socialStatus_" .. p.status)), tagColor = (p.status == "accepted" and K().C.green) or (p.status == "declined" and K().C.red) or K().C.peach,
            onClick = (p.dir == "in" and p.status == "open") and function() proposalPopup(entry) end or nil}
    end
    return rows
end
local function meetRows()
    local rows = {}
    for _, m in ipairs(A.social.meets) do
        local meet = m
        rows[#rows + 1] = {title = plain(m.label ~= "" and m.label or "-"), sub = plain(base(m.sender)) .. "  ·  " .. meetText(m), icon = K().ICON.places, onClick = function() meetPopup(meet) end}
    end
    return rows
end
local function navigate(name)
    local ok, err = A.NavigateByName(name)
    A.Print(ok and string.format(A.L("navStarted"), plain(name)) or A.L("navErr_" .. tostring(err)))
end
local function liveRows()
    local rows = {}
    local function ago(at) local seconds = math.max(0, A.Now() - (at or 0)); if seconds < 90 then return A.L("agoNow") end; return string.format(A.L("agoMinutes"), math.floor(seconds / 60)) end
    for _, p in ipairs(A.LivePeers()) do
        local peer = p
        local distance = A.map and A.map.DistanceTo and A.map.DistanceTo(p.map, p.x, p.y)
        rows[#rows + 1] = {title = plain(p.name), sub = string.format(A.L("liveRowSub"), zoneName(p.map), ago(p.at)), class = p.class, icon = K().ICON.peers,
            right = distance and (math.floor(distance + 0.5) .. " yd") or nil, onClick = function() navigate(peer.name) end}
    end
    for _, g in ipairs(A.LivePings()) do
        local ping = g
        rows[#rows + 1] = {title = plain(g.label ~= "" and g.label or A.L("pingTitle")), sub = string.format(A.L("liveRowSub"), plain(g.mine and A.L("navYou") or g.name), zoneName(g.map) .. "  ·  " .. ago(g.at)), icon = K().ICON.places, tag = A.Upper(A.L("pingTitle")), tagColor = K().C.peach,
            onClick = function()
                local ok, err = A.NavigateToPoint(ping.label ~= "" and ping.label or A.L("pingTitle"), ping.map, ping.x, ping.y, {view = "people"})
                A.Print(ok and string.format(A.L("navStarted"), plain(ping.label ~= "" and ping.label or A.L("pingTitle"))) or A.L("navErr_" .. tostring(err)))
            end}
    end
    return rows
end
local function privacyRows()
    local rows = {}
    for _, t in ipairs(A.SocialTrusted()) do
        local who = t.sender
        rows[#rows + 1] = {title = plain(base(t.sender)), sub = A.L("socialTrustedTitle") .. " " .. kindsText(t.kinds or ""), icon = K().ICON.peers, tag = A.Upper(A.L("socialRevoke")), tagColor = K().C.red,
            onClick = function() A.RevokeAccess(who); A.RefreshUI() end}
    end
    for _, s in ipairs(A.social.shown) do
        local entry = s
        rows[#rows + 1] = {title = plain(s.name), sub = A.L("socialShownTitle") .. " " .. kindsText(s.kinds) .. "  ·  " .. (A.Call(date, "%H:%M", s.at) or ""), icon = K().ICON.peers,
            tag = entry.revoked and A.Upper(A.L("socialRevoked")) or A.Upper(A.L("socialRevoke")), tagColor = K().C.red,
            onClick = (not entry.revoked) and function() A.RevokeAccess(entry.sender or entry.name); A.RefreshUI() end or nil}
    end
    for name in pairs(A.db.settings.socialBlock or {}) do
        local blockedName = name
        rows[#rows + 1] = {title = plain(name), sub = A.L("socialBlockedHint"), icon = K().ICON.unknown, tag = A.Upper(A.L("socialBlock")), tagColor = K().C.red, onClick = function() A.SocialUnblock(blockedName); A.RefreshUI() end}
    end
    return rows
end

-- the people around you, to pick one to look at: your target, the group, players who share a live position, those who showed you something
local function fullName(name, realm)
    name, realm = A.Text(name, 80), A.Text(realm, 80)
    if not name then return nil end
    return realm and realm ~= "" and (name .. "-" .. realm) or name
end
local CLASS_ID = {WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13}
local function classIdOfGuid(guid)
    if type(guid) ~= "string" or type(GetPlayerInfoByGUID) ~= "function" then return nil end
    local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
    return ok and CLASS_ID[classFile] or nil
end
local lastRosterAsk = 0
local MAX_ROSTER = 120
-- everybody you could look at, nearest first: your target, the group, those who share a live position, online friends, online guild members and
-- those who already showed you something. Clicking a row puts the name into the request.
local function rosterRows()
    local rows, seen = {}, {}
    local myName = A.Text(A.Call(UnitName, "player"), 80)
    local function add(order, name, class, whyKey, level, zone)
        name = A.Text(name, 120)
        if not name or seen[base(name):lower()] or base(name) == myName or #rows >= MAX_ROSTER then return end
        seen[base(name):lower()] = true
        local sub = A.L(whyKey)
        if A.Number(level, 1, 200) then sub = sub .. "  ·  " .. A.L("level") .. " " .. level end
        if A.Text(zone, 80) and zone ~= "" then sub = sub .. "  ·  " .. plain(zone) end
        local picked = name
        rows[#rows + 1] = {order = order, title = plain(base(name)), sub = sub, class = class, icon = K().ICON.peers,
            titleColor = class and K().classColor(class) or nil,
            onClick = function() if page and page.name then page.name:SetText(picked) end; A.RefreshUI() end}
    end
    local function unitClass(unit) local _, _, id = A.Call(UnitClass, unit); return A.Number(id, 1, 100) end
    if A.Call(UnitExists, "target") == true and A.Call(UnitIsPlayer, "target") == true then add(0, fullName(A.Call(UnitFullName, "target")), unitClass("target"), "socialRosterTarget", A.Call(UnitLevel, "target")) end
    local raid = A.Call(IsInRaid) == true
    for i = 1, raid and 40 or 4 do
        local unit = (raid and "raid" or "party") .. i
        if A.Call(UnitExists, unit) == true then add(1, fullName(A.Call(UnitFullName, unit)), unitClass(unit), "socialRosterGroup", A.Call(UnitLevel, unit)) end
    end
    for _, p in ipairs(A.LivePeers()) do add(2, p.name, p.class, "socialRosterLive", nil, p.map and zoneName(p.map) or nil) end
    -- friends who are online (the game's friend list, not Battle.net)
    if C_FriendList and type(C_FriendList.GetNumFriends) == "function" and type(C_FriendList.GetFriendInfoByIndex) == "function" then
        for i = 1, A.Number(A.Call(C_FriendList.GetNumFriends), 0, 500) or 0 do
            local info = A.Call(C_FriendList.GetFriendInfoByIndex, i)
            if type(info) == "table" and A.Field(info, "connected") == true then
                add(3, A.Field(info, "name"), classIdOfGuid(A.Field(info, "guid")), "socialRosterFriend", A.Field(info, "level"), A.Field(info, "area"))
            end
        end
    elseif type(GetNumFriends) == "function" and type(GetFriendInfo) == "function" then
        for i = 1, A.Number(A.Call(GetNumFriends), 0, 500) or 0 do
            local name, level, _, area, connected = A.Call(GetFriendInfo, i)
            if connected == true then add(3, name, nil, "socialRosterFriend", level, area) end
        end
    end
    -- guild members who are online; the roster arrives only after the game was asked for it
    if A.Call(IsInGuild) == true then
        if A.Monotonic() - lastRosterAsk > 60 then
            lastRosterAsk = A.Monotonic()
            local ask = C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster
            if type(ask) == "function" then pcall(ask) end
        end
        for i = 1, A.Number(A.Call(GetNumGuildMembers), 0, 1000) or 0 do
            local ok, name, _, _, level, _, zone, _, _, online, _, classFile = pcall(GetGuildRosterInfo, i)
            if ok and online == true then add(4, name, CLASS_ID[classFile], "socialRosterGuild", level, zone) end
        end
    end
    for _, v in ipairs(A.social.views) do add(5, v.sender, nil, "socialRosterSeen") end
    table.sort(rows, function(x, y) if x.order ~= y.order then return x.order < y.order end return tostring(x.title) < tostring(y.title) end)
    return rows
end
A.SocialRoster = rosterRows   -- read by the tests and the layout preview

-- ---------------------------------------------------------------- everybody, in categories
-- The People tab: friends, players who share a live position (they run Evertally), your group, players you are connected
-- with through Evertally (they showed you something, proposed a trade or a meet, or you asked them) and players known
-- to run Evertally. A click starts the navigation to the player when their position is known, otherwise it opens the
-- request form with the name filled in.
local function markText(name)
    local mark = A.GetMark and A.GetMark(name)
    return mark and ("|TInterface\TargetingFrame\UI-RaidTargetingIcon_" .. mark .. ":14|t") or nil
end
local function peopleRows()
    local people, order = {}, {}
    local function person(name)
        name = A.Text(name, 120)
        if not name or base(name) == "" then return nil end
        local key = base(name):lower()
        if key == (A.Text(A.Call(UnitName, "player"), 80) or ""):lower() then return nil end
        local p = people[key]
        if not p then p = {name = name, flags = {}}; people[key] = p; order[#order + 1] = key end
        return p
    end
    local function note(name, flag, class, level, zone)
        local p = person(name)
        if not p then return end
        p.flags[flag] = true
        p.class = p.class or class
        p.level = p.level or A.Number(level, 1, 200)
        if not p.zone and A.Text(zone, 80) and zone ~= "" then p.zone = zone end
    end
    local function unitClass(unit) local _, _, id = A.Call(UnitClass, unit); return A.Number(id, 1, 100) end
    if A.Call(UnitExists, "target") == true and A.Call(UnitIsPlayer, "target") == true then
        note(fullName(A.Call(UnitFullName, "target")), "target", unitClass("target"), A.Call(UnitLevel, "target"))
    end
    local raid = A.Call(IsInRaid) == true
    for i = 1, raid and 40 or 4 do
        local unit = (raid and "raid" or "party") .. i
        if A.Call(UnitExists, unit) == true then note(fullName(A.Call(UnitFullName, unit)), "group", unitClass(unit), A.Call(UnitLevel, unit)) end
    end
    for _, p in ipairs(A.LivePeers()) do note(p.name, "live", p.class, nil, p.map and zoneName(p.map) or nil) end
    if C_FriendList and type(C_FriendList.GetNumFriends) == "function" and type(C_FriendList.GetFriendInfoByIndex) == "function" then
        for i = 1, A.Number(A.Call(C_FriendList.GetNumFriends), 0, 500) or 0 do
            local info = A.Call(C_FriendList.GetFriendInfoByIndex, i)
            if type(info) == "table" then
                local online = A.Field(info, "connected") == true
                note(A.Field(info, "name"), online and "friend" or "friendOff", classIdOfGuid(A.Field(info, "guid")), A.Field(info, "level"), online and A.Field(info, "area") or nil)
            end
        end
    elseif type(GetNumFriends) == "function" and type(GetFriendInfo) == "function" then
        for i = 1, A.Number(A.Call(GetNumFriends), 0, 500) or 0 do
            local name, level, _, area, connected = A.Call(GetFriendInfo, i)
            note(name, connected == true and "friend" or "friendOff", nil, level, connected == true and area or nil)
        end
    end
    -- connected through Evertally: showed you something, traded or met with you, or you asked them
    for _, v in ipairs(A.social.views) do note(v.sender, "linked") end
    for _, e in ipairs(A.social.proposals) do note(e.peer, "linked") end
    for _, m in ipairs(A.social.meets) do note(m.sender, "linked") end
    for _, o in pairs(A.social.outgoing) do note(o.target, "linked") end
    for _, s in ipairs(A.social.shown) do note(s.sender or s.name, "linked") end
    -- known to run Evertally (any Evertally message from them in the last 30 days)
    for name in pairs((A.db and A.db.settings.evertallyUsers) or {}) do note(name, "user") end
    if A.Call(IsInGuild) == true then
        if A.Monotonic() - lastRosterAsk > 60 then
            lastRosterAsk = A.Monotonic()
            local ask = C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster
            if type(ask) == "function" then pcall(ask) end
        end
        for i = 1, A.Number(A.Call(GetNumGuildMembers), 0, 1000) or 0 do
            local ok, name, _, _, level, _, zone, _, _, online, _, classFile = pcall(GetGuildRosterInfo, i)
            if ok and online == true then note(name, "guild", CLASS_ID[classFile], level, zone) end
        end
    end
    -- every person goes under the first category that fits; the other facts stay as small labels
    local CATS = {
        {flag = "friend", title = "peopleCatFriends"}, {flag = "live", title = "peopleCatLive"}, {flag = "group", title = "peopleCatGroup"},
        {flag = "linked", title = "peopleCatLinked"}, {flag = "user", title = "peopleCatUsers"}, {flag = "guild", title = "peopleCatGuild"},
        {flag = "target", title = "peopleCatTarget"}, {flag = "friendOff", title = "peopleCatFriendsOff"},
    }
    local buckets = {}
    for _, key in ipairs(order) do
        local p = people[key]
        for _, cat in ipairs(CATS) do
            if p.flags[cat.flag] then buckets[cat.flag] = buckets[cat.flag] or {}; table.insert(buckets[cat.flag], p); break end
        end
    end
    local rows = {}
    -- pings stay on top: a place somebody marked on the map
    local pings = A.LivePings()
    if #pings > 0 then
        rows[#rows + 1] = {heading = A.L("peopleCatPings"), right = tostring(#pings)}
        for _, g in ipairs(pings) do
            local ping = g
            rows[#rows + 1] = {title = plain(g.label ~= "" and g.label or A.L("pingTitle")), sub = string.format(A.L("liveRowSub"), plain(g.mine and A.L("navYou") or g.name), zoneName(g.map)), icon = K().ICON.unknown, tag = A.Upper(A.L("pingTitle")), tagColor = K().C.mist,
                onClick = function()
                    local ok, err = A.NavigateToPoint(ping.label ~= "" and ping.label or A.L("pingTitle"), ping.map, ping.x, ping.y, {view = "people"})
                    A.Print(ok and string.format(A.L("navStarted"), plain(ping.label ~= "" and ping.label or A.L("pingTitle"))) or A.L("navErr_" .. tostring(err)))
                end}
        end
    end
    for _, cat in ipairs(CATS) do
        local list = buckets[cat.flag]
        if list and #list > 0 then
            table.sort(list, function(a, b) return base(a.name):lower() < base(b.name):lower() end)
            rows[#rows + 1] = {heading = A.L(cat.title), right = tostring(#list)}
            for _, p in ipairs(list) do
                local who = p.name
                local live = A.LivePeer(who)
                local distance = live and A.map and A.map.DistanceTo and A.map.DistanceTo(live.map, live.x, live.y)
                local bits = {}
                if p.level then bits[#bits + 1] = A.L("level") .. " " .. p.level end
                local zone = live and live.map and zoneName(live.map) or p.zone
                if zone then bits[#bits + 1] = plain(zone) end
                for _, flag in ipairs({"friend", "group", "guild", "user", "linked"}) do
                    if p.flags[flag] and flag ~= cat.flag and not (flag == "user" and p.flags.live) then bits[#bits + 1] = A.L("peopleFlag_" .. flag) end
                end
                if #bits == 0 then bits[1] = A.L(cat.flag == "friendOff" and "peopleOffline" or "peopleNoPosition") end
                local mark = markText(who)
                local row = {title = plain(base(who)), sub = table.concat(bits, "  ·  "), class = p.class, icon = K().ICON.peers,
                    titleColor = p.class and K().classColor(p.class) or nil,
                    right = (mark and (mark .. "  ") or "") .. (distance and (math.floor(distance + 0.5) .. " yd") or "")}
                if p.flags.live or p.flags.user or p.flags.linked then row.tag, row.tagColor = "EVERTALLY", K().C.lilac end
                if cat.flag == "friendOff" then row.titleColor = {0.55, 0.52, 0.5}
                elseif live then row.onClick = function() navigate(live.name) end
                else row.onClick = function()
                    if page and page.name then page.name:SetText(who) end
                    page.mode = "ask"; A.Print(string.format(A.L("peopleNoPositionChat"), plain(base(who)))); A.RefreshUI()
                end end
                rows[#rows + 1] = row
            end
        end
    end
    return rows
end
A.SocialPeople = peopleRows   -- read by the tests and the layout preview

function A.BuildSocialPage(host, k)
    page = host; A.social.page = host
    local C = k.C
    k.PageHeader(page, "social")
    page.mode = "live"
    page.tabs = {}
    local previous
    for _, mode in ipairs({"live", "ask", "proposals", "meets", "privacy"}) do
        local chip = k.Chip(page, function() page.mode = mode; A.RefreshUI() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -54) end
        page.tabs[mode] = chip; previous = chip
    end

    -- A contact ledger on the left; the selected player's permission request is a full parchment leaf.
    local ink, muted, heading = {0.90,0.88,0.82}, {0.66,0.63,0.56}, C.gold
    page.cols=k.Columns(page,{2,3},12)
    page.cols:SetPoint("TOPLEFT",0,-90);page.cols:SetPoint("BOTTOMRIGHT")
    local rosterCard=k.Card(page.cols.cells[1]);rosterCard:SetAllPoints(page.cols.cells[1]);page.rosterCard=rosterCard
    page.rosterTitle=k.label(rosterCard,13,C.gold);page.rosterTitle:SetPoint("TOPLEFT",12,-12)
    local rosterInner=CreateFrame("Frame",nil,rosterCard);rosterInner:SetPoint("TOPLEFT",6,-36);rosterInner:SetPoint("BOTTOMRIGHT",-6,120)
    page.roster=k.ListView(rosterInner,0)
    page.viewsTitle=k.label(rosterCard,12,C.gold);page.viewsTitle:SetPoint("BOTTOMLEFT",12,94)
    local viewsInner=CreateFrame("Frame",nil,rosterCard);viewsInner:SetPoint("BOTTOMLEFT",6,6);viewsInner:SetPoint("BOTTOMRIGHT",-6,6);viewsInner:SetHeight(80)
    page.viewList=k.ListView(viewsInner,0)
    local form=CreateFrame("Frame",nil,page.cols.cells[2]);form:SetAllPoints(page.cols.cells[2]);A.NativePanel(form,C);page.requestLeaf=form
    page.formTitle=k.label(form,15,heading);page.formTitle:SetPoint("TOPLEFT",14,-12);page.formTitle:SetPoint("TOPRIGHT",-14,-12)
    page.contactPortrait=form:CreateTexture(nil,"ARTWORK");page.contactPortrait:SetSize(50,50);page.contactPortrait:SetPoint("TOPLEFT",14,-42);k.setIcon(page.contactPortrait,k.ICON.npc)
    page.name=CreateFrame("EditBox",nil,form,"InputBoxTemplate");page.name:SetHeight(26);page.name:SetPoint("TOPLEFT",80,-42);page.name:SetPoint("TOPRIGHT",-14,-42)
    page.name:SetAutoFocus(false);page.name:SetMaxLetters(80);page.name:SetFont(FONT,12,"")
    page.target=k.Button(form,"socialTarget",118,"ghost",function()
        local name,realm=A.Call(UnitFullName,"target");name=A.Text(name or A.Call(UnitName,"target"),80)
        if name then page.name:SetText(name..((A.Text(realm,80) or "")~="" and ("-"..A.Text(realm,80)) or ""))end
    end);page.target:SetPoint("TOPLEFT",80,-77)
    page.permissionTitle=k.label(form,12,heading);page.permissionTitle:SetPoint("TOPLEFT",14,-117)
    page.kinds={i=true,s=true,t=true,p=true,g=false,w=A.DefaultLookKinds():find("w",1,true)~=nil};page.kindButtons={}
    local last
    for n,key in ipairs({"i","s","t","p","g","w"})do
        local chip=k.Chip(form,function()page.kinds[key]=not page.kinds[key];A.RefreshUI()end)
        if n==5 then chip:SetPoint("TOPLEFT",14,-167)elseif last then chip:SetPoint("LEFT",last,"RIGHT",5,0)else chip:SetPoint("TOPLEFT",14,-141)end
        page.kindButtons[key]=chip;last=chip
    end
    page.permissionNote=k.label(form,10,muted);page.permissionNote:SetPoint("TOPLEFT",14,-195);page.permissionNote:SetPoint("TOPRIGHT",-14,-195);page.permissionNote:SetHeight(16)
    -- a private mark for this player, drawn beside their nameplate; one click cycles 0 (none), 1..8, 0
    page.markButton=k.Button(form,nil,96,"ghost",function()
        local who=page.name:GetText() or ""
        local current=A.GetMark and A.GetMark(who) or 0
        if A.SetMark and A.SetMark(who,(current+1)%((A.MARK_COUNT or 8)+1)) then A.RefreshUI() end
    end);page.markButton:SetPoint("TOPLEFT",204,-77)
    page.sendRequest=k.Button(form,"socialSend",180,"primary",function()
        local chosen="";for _,key in ipairs({"i","s","t","p","g","w"})do if page.kinds[key]then chosen=chosen..key end end
        local ok,err=A.RequestInspect(page.name:GetText() or "",chosen)
        page.status:SetText(ok and string.format(A.L("socialWaiting"),plain(base(page.name:GetText() or ""))) or A.L("socialErr_"..tostring(err)));A.RefreshUI()
    end);page.sendRequest:SetPoint("BOTTOMLEFT",14,13)
    page.status=k.label(form,11,ink);page.status:SetPoint("BOTTOMLEFT",14,54);page.status:SetPoint("BOTTOMRIGHT",-14,54);page.status:SetHeight(22)

    -- The pages other than "Look" live on one dark panel; every widget is created directly on it.
    local leaf = CreateFrame("Frame", nil, page); leaf:SetPoint("TOPLEFT", 0, -90); leaf:SetPoint("BOTTOMRIGHT"); A.NativePanel(leaf, C)
    page.secondaryLeaf = leaf
    local function fieldBox(w) local e = CreateFrame("EditBox", nil, leaf, "InputBoxTemplate"); e:SetSize(w, 26); e:SetAutoFocus(false); e:SetFont(FONT, 12, ""); return e end
    -- live
    page.ping = k.Button(leaf, "socialPing", 150, "primary", function()
        local ok, err = A.SendPing("")
        A.Print(ok and A.L("pingSent") or A.L("pingErr_" .. tostring(err))); A.RefreshUI()
    end); page.ping:SetPoint("TOPLEFT", 16, -16)
    page.stopNav = k.Button(leaf, "socialStopNav", 190, "ghost", function() A.StopNavigation(); A.Print(A.L("navStopped")) end); page.stopNav:SetPoint("LEFT", page.ping, "RIGHT", 10, 0)
    page.liveState = k.label(leaf, 12, C.green); page.liveState:SetPoint("TOPRIGHT", -16, -22); page.liveState:SetJustifyH("RIGHT")
    page.liveNote = k.label(leaf, 11, muted); page.liveNote:SetPoint("TOPLEFT", 16, -56); page.liveNote:SetPoint("TOPRIGHT", -16, -56); page.liveNote:SetHeight(34)
    -- meets
    page.meetTitle = k.label(leaf, 13, heading); page.meetTitle:SetPoint("TOPLEFT", 16, -14)
    page.meetHelp = k.label(leaf, 11, muted); page.meetHelp:SetPoint("TOPLEFT", 16, -38); page.meetHelp:SetPoint("TOPRIGHT", -16, -38); page.meetHelp:SetHeight(34)
    page.meetHint = k.label(leaf, 11, ink); page.meetHint:SetPoint("TOPLEFT", 16, -82)
    page.meetLabel = fieldBox(420); page.meetLabel:SetPoint("TOPLEFT", 22, -100); page.meetLabel:SetMaxLetters(60)
    page.meetButtons = {}
    for n, def in ipairs({{"PARTY", "socialMeetParty"}, {"GUILD", "socialMeetGuild"}, {"WHISPER", "socialMeetWhisper"}}) do
        local b = k.Button(leaf, def[2], 140, n == 1 and "primary" or "ghost", function()
            local target
            if def[1] == "WHISPER" then
                local name, realm = A.Call(UnitFullName, "target")
                name = A.Text(name or A.Call(UnitName, "target"), 80)
                target = name and (name .. ((A.Text(realm, 80) or "") ~= "" and ("-" .. A.Text(realm, 80)) or "")) or nil
            end
            local channel = def[1]
            if channel == "PARTY" and A.Call(IsInRaid) == true then channel = "RAID" end
            local ok, err = A.SendMeet(channel, target, page.meetLabel:GetText() or "", 0)
            page.meetStatus:SetText(ok and A.L("socialMeetSent") or A.L("socialMeetErr_" .. tostring(err)))
        end); b:SetPoint("TOPLEFT", 16 + (n - 1) * 148, -140); page.meetButtons[#page.meetButtons + 1] = b
    end
    page.meetStatus = k.label(leaf, 11, C.green); page.meetStatus:SetPoint("TOPLEFT", 16, -176); page.meetStatus:SetPoint("TOPRIGHT", -16, -176); page.meetStatus:SetHeight(30)
    -- privacy
    page.privacy = k.label(leaf, 11, ink); page.privacy:SetPoint("TOPLEFT", 16, -16); page.privacy:SetPoint("TOPRIGHT", -16, -16); page.privacy:SetHeight(64)
    page.list = k.ListView(leaf, 204)
    function page.Refresh()
        local mode = page.mode
        for key, chip in pairs(page.tabs) do chip.SetLabel(A.L("socialTab_" .. key)); chip.SetOn(mode == key) end
        page.cols:SetShown(mode == "ask"); page.cols.Layout()
        page.secondaryLeaf:SetShown(mode ~= "ask")
        page.list:ClearAllPoints();page.list:SetPoint("TOPLEFT",page.secondaryLeaf,"TOPLEFT",10,-(mode=="proposals" and 12 or mode=="meets" and 214 or mode=="privacy" and 90 or 96));page.list:SetPoint("BOTTOMRIGHT",page.secondaryLeaf,"BOTTOMRIGHT",-10,10)
        local webReady = A.DefaultLookKinds():find("w", 1, true) ~= nil
        for key, chip in pairs(page.kindButtons) do
            chip.SetLabel(A.L(({i = "socialInv", s = "socialStats", t = "socialTalents", p = "socialProf", g = "socialGold", w = "socialWeb"})[key]))
            chip.SetOn(page.kinds[key] and (key ~= "w" or webReady)); chip:SetShown(key ~= "w" or webReady)
        end
        page.rosterTitle:SetText(A.L("socialRoster")); page.formTitle:SetText(A.L("socialAsk")); page.viewsTitle:SetText(A.L("socialViewsTitle"))
        page.meetLabel:SetShown(mode == "meets"); page.meetStatus:SetShown(mode == "meets")
        page.meetHint:SetShown(mode == "meets"); page.meetHint:SetText(A.L("socialMeetLabelHint"))
        page.meetHelp:SetShown(mode == "meets"); page.meetTitle:SetShown(mode == "meets"); page.meetTitle:SetText(A.L("socialMeetTitle")); page.meetHelp:SetText(A.L("socialMeetHelp"))
        for _, b in ipairs(page.meetButtons) do b:SetShown(mode == "meets"); b.text:SetText(A.L(b.localeKey)) end
        page.privacy:SetShown(mode == "privacy"); page.privacy:SetText(A.L("socialPrivacyInfo"))
        for _, w in ipairs({page.ping, page.stopNav, page.liveNote, page.liveState}) do w:SetShown(mode == "live") end
        page.liveState:SetText(A.LiveActive() and A.L("socialLiveOn") or A.L("socialLiveOff"))
        page.list:SetShown(mode ~= "ask")
        page.ping.text:SetText(A.L("socialPing")); page.stopNav.text:SetText(A.L("socialStopNav"))
        page.liveNote:SetText(A.LiveActive() and A.L("liveHint") or (A.L("liveOffNote") .. "  " .. A.L("liveHint")))
        page.liveState:SetTextColor(unpack(A.LiveActive() and C.green or muted))
        page.target.text:SetText(A.L("socialTarget")); page.sendRequest.text:SetText(A.L("socialSend"))
        if mode == "ask" then
            local newest
            for _, entry in pairs(A.social.outgoing) do if not newest or entry.at >= newest.at then newest = entry end end
            if newest then
                local who = plain(base(newest.target))
                local key = newest.status
                page.status:SetText(key == "waiting" and string.format(A.L("socialWaiting"), who) or key == "receiving" and string.format(A.L("socialReceiving"), who, newest.done or 0, newest.total or 0)
                    or key == "denied" and string.format(A.L("socialDenied"), who) or key == "noanswer" and string.format(A.L("socialNoAnswer"), who) or key == "done" and string.format(A.L("socialDone"), who) or "")
            end
            local roster=rosterRows()
            page.roster.SetItems(roster, A.L("socialNoRoster"))
            local chosen=base(page.name:GetText() or ""):lower()
            local found
            for _,contact in ipairs(roster)do if base(contact.title):lower()==chosen then found=contact;break end end
            if chosen==base(A.Text(A.Call(UnitName,"target"),80) or ""):lower() and type(SetPortraitTexture)=="function" and A.Call(UnitIsPlayer,"target")==true then
                pcall(SetPortraitTexture,page.contactPortrait,"target")
            elseif found and found.class then k.classIcon(page.contactPortrait,found.class)
            else k.setIcon(page.contactPortrait,k.ICON.npc)end
            page.permissionTitle:SetText(A.db.settings.language=="cs" and "O co chceš požádat" or "What you want to see")
            page.permissionNote:SetText(A.L("socialPermissionNote"))
            local currentMark = A.GetMark and A.GetMark(page.name:GetText() or "") or 0
            page.markButton.text:SetText(A.L("markButton") .. (currentMark > 0 and ("  |TInterface" .. string.char(92) .. "TargetingFrame" .. string.char(92) .. "UI-RaidTargetingIcon_" .. currentMark .. ":14|t") or ""))
            page.viewList.SetItems(viewRows(), A.L("socialNoViews"))
        elseif mode == "live" then page.list.SetItems(peopleRows(), A.L("peopleNone"))
        elseif mode == "proposals" then page.list.SetItems(proposalRows(), A.L("socialNoProposals"))
        elseif mode == "meets" then page.list.SetItems(meetRows(), A.L("socialNoMeets"))
        else page.list.SetItems(privacyRows(), A.L("socialNoShown")) end
    end
end

A.SocialListen(function(kind, data)
    if kind == "request" then askPopup(data)
    elseif kind == "proposal" then proposalPopup(data)
    elseif kind == "meet" then meetPopup(data)
    elseif kind == "requestExpired" and popup and popup.current and popup.current.id == data.id then closePopup()
    elseif kind == "view" then if not viewer or not viewer:IsShown() then openViewer(data) end
    elseif kind == "viewRevoked" and viewer and viewer:IsShown() and viewer.view and base(viewer.view.sender):lower() == base(data.name):lower() then viewer:Hide() end
    if A.RefreshUI then A.RefreshUI() end
    if A.SocialRefreshViewer then A.SocialRefreshViewer() end
end)
A.On("GET_ITEM_INFO_RECEIVED", function() A.SocialRefreshViewer() end)
if C_Timer and type(C_Timer.NewTicker) == "function" then
    C_Timer.NewTicker(3, function() if page and page.mode == "live" and page:IsShown() then A.RefreshUI() end end)
end

-- ---------------------------------------------------------------- texts
local text = {
    en = {
        waypointSet = "Waypoint set: %s", socialAsk = "Ask to look at a player", socialTarget = "Use my target", socialInv = "Gear and bags", socialProf = "Professions", socialGold = "Gold", socialSend = "Send request",
        peopleCatFriends = "Friends online", peopleCatFriendsOff = "Friends offline", peopleCatLive = "Sharing their position (Evertally)", peopleCatGroup = "Group / raid",
        peopleCatLinked = "Connected through Evertally", peopleCatUsers = "Evertally players", peopleCatGuild = "Guild online", peopleCatTarget = "Your target", peopleCatPings = "Pings on the map",
        peopleFlag_friend = "friend", peopleFlag_group = "group", peopleFlag_guild = "guild", peopleFlag_user = "Evertally", peopleFlag_linked = "connected", peopleOffline = "offline", peopleNoPosition = "position unknown",
        peopleNone = "Nobody here yet. Friends, group, guild and everybody you meet through Evertally appear in categories.", peopleNoPositionChat = "%s does not share a position. Ask to look at them or for a meet instead.",
        socialTab_ask = "Look", socialTab_proposals = "Trades", socialTab_meets = "Meets", socialTab_privacy = "Privacy",
        socialWaiting = "Waiting for %s to answer...", socialDenied = "%s declined.", socialNoAnswer = "%s did not answer.", socialReceiving = "Receiving from %s: %d/%d",
        socialDone = "%s showed you their things. Open them in the list.", socialErr_pending = "You already asked this player.", socialErr_self = "That is you.",
        socialErr_no_target = "Type a name, or target a player and press the button.", socialErr_no_kinds = "Tick at least one thing to ask for.", socialErr_queue_full = "Too many messages are waiting. Try again in a moment.", socialErr_size_limit = "That is too much to send.",
        socialNoViews = "Nothing received yet. Ask a player; they decide what to show.", socialNoProposals = "No trade proposals yet.", socialNoMeets = "No meets received yet.", socialNoShown = "You have not shown anything this session.",
        socialIn = "from", socialOut = "to", socialStatus_open = "open", socialStatus_sent = "sent", socialStatus_accepted = "accepted", socialStatus_declined = "declined",
        socialMeetTitle = "Send a meet", socialLiveOn = "Live position: ON", socialLiveOff = "Live position: OFF", socialMeetLabelHint = "Name of the place (optional)", socialMeetHelp = "A meet shows the others a waypoint to where you are (or to the spot under the map cursor). Pick who gets it: your group, your guild or your target. They accept it with one click.", socialMeetParty = "To party / raid", socialMeetGuild = "To guild", socialMeetWhisper = "To my target", socialMeetSent = "Sent. Others can set a waypoint. Tip: with the world map open, the place under your cursor is sent.", socialMeetErr_no_position = "No map position here (instance or loading screen).",
        socialMeetErr_no_target = "Target a player first.", socialMeetErr_queue_full = "Too many messages are waiting.", socialMeetIn = "in %d min", socialMeetNow = "now",
        socialPrivacyInfo = "What another player shows you is kept only while the addon runs: it is never saved and never uploaded. You are asked before anyone sees anything of yours, and you choose what to show each time. Evertally does not keep what you showed, only a short list below.",
        socialShownTitle = "You showed:", socialBlockedHint = "Blocked. Click to unblock.", socialBlock = "Block",
        socialAskTitle = "%s asks to look at:", socialAskNote = "They see only what you tick. Gold and the website copy are never ticked for you. \"Always\" never covers gold, and you can take it back under Privacy or with /etally revoke.", socialAllow = "Allow", socialDeny = "Deny",
        socialAllowOnce = "Allow once", socialAllowAlways = "Always", socialStats = "Stats", socialTalents = "Talents", socialWeb = "Keep on their website",
        socialWebAsk = "They may keep this on their Evertally website", socialTrustedTitle = "Allowed for good:", socialRevoke = "Revoke", socialRevoked = "revoked",
        socialPermissionNote = "They choose what to show. Gold is separate.",
        viewTab_stats = "Stats", viewTab_talents = "Talents", viewNoStats = "No stats shown.", viewNoTalents = "No talents shown.", viewTalentPoints = "%d talents with points",
        viewTitle = "%s", viewReceived = "received %s", viewTab_equipped = "Equipped", viewTab_bags = "Bags", viewTab_professions = "Professions", viewTab_gold = "Gold",
        viewPointInfo = "Point at an item: click it and it blinks green in their open bags.", viewPoint = "Show mode", viewPointed = "Showing %s to %s", viewPointHint = "SHOW MODE is on: click an item and it blinks green in THEIR open bags (any bag addon) and they get a chat message. Click \"Show mode\" again to go back to choosing wanted items.",
        viewWant = "WANT", viewOffer = "OFFER", viewMyOffer = "My offer (my bags)", viewGoldOffer = "Gold I offer", viewNote = "Note", viewSend = "Send proposal", viewSent = "Proposal sent to %s.",
        viewHint = "Click an item to mark it as wanted (click again for the whole stack, again to remove). Pick what you offer on the right, then send.", viewNoGold = "They did not show their gold.",
        viewNoProf = "No professions shown, or none recorded yet.", viewRecipes = "%d known recipes",
        viewSearch = "Search items...", viewSortBy = "Sort:", viewSort_default = "default", viewSort_quality = "quality", viewSort_name = "name", viewSort_type = "type (groups)", viewCount = "%d/%d", viewNoMatch = "Nothing matches.",
        viewType_weapon = "Weapons", viewType_armor = "Armor", viewType_consumable = "Consumables", viewType_container = "Bags", viewType_ammo = "Ammunition", viewType_trade = "Trade goods", viewType_recipe = "Recipes", viewType_quest = "Quest items", viewType_misc = "Other", viewType_unknown = "Not loaded yet",
        propTitle = "%s proposes a trade", propWants = "Wants from you:", propOffers = "Offers:", propGold = "Gold: %s", propNote = "Note: %s", propAccept = "Accept", propDecline = "Decline",
        propAcceptedHint = "Accepted. Meet and use the normal trade window.", propTradeOpened = "Accepted. Opening the trade window.", meetTitle = "%s suggests a meet", meetWaypoint = "Set waypoint", meetDismiss = "Dismiss",
        viewSlot1 = "Head", viewSlot2 = "Neck", viewSlot3 = "Shoulder", viewSlot4 = "Shirt", viewSlot5 = "Chest", viewSlot6 = "Waist", viewSlot7 = "Legs", viewSlot8 = "Feet", viewSlot9 = "Wrist", viewSlot10 = "Hands",
        viewSlot11 = "Finger 1", viewSlot12 = "Finger 2", viewSlot13 = "Trinket 1", viewSlot14 = "Trinket 2", viewSlot15 = "Back", viewSlot16 = "Main hand", viewSlot17 = "Off hand", viewSlot18 = "Ranged", viewSlot19 = "Tabard",
    },
    cs = {
        waypointSet = "Waypoint nastaven: %s", socialAsk = "Požádat o pohled do hráče", socialTarget = "Můj cíl", socialInv = "Výbava a tašky", socialProf = "Profese", socialGold = "Zlato", socialSend = "Odeslat žádost",
        peopleCatFriends = "Přátelé online", peopleCatFriendsOff = "Přátelé offline", peopleCatLive = "Sdílejí polohu (Evertally)", peopleCatGroup = "Skupina / raid",
        peopleCatLinked = "Spojení přes Evertally", peopleCatUsers = "Hráči s Evertally", peopleCatGuild = "Cech online", peopleCatTarget = "Tvůj cíl", peopleCatPings = "Pingy na mapě",
        peopleFlag_friend = "přítel", peopleFlag_group = "skupina", peopleFlag_guild = "cech", peopleFlag_user = "Evertally", peopleFlag_linked = "spojen", peopleOffline = "offline", peopleNoPosition = "poloha neznámá",
        peopleNone = "Zatím tu nikdo není. Přátelé, skupina, cech a všichni, koho potkáš přes Evertally, se objeví v kategoriích.", peopleNoPositionChat = "%s nesdílí polohu. Požádej ho o pohled nebo mu pošli sraz.",
        socialTab_ask = "Pohled", socialTab_proposals = "Výměny", socialTab_meets = "Srazy", socialTab_privacy = "Soukromí",
        socialWaiting = "Čeká se, až %s odpoví...", socialDenied = "%s odmítl.", socialNoAnswer = "%s neodpověděl.", socialReceiving = "Přijímám od %s: %d/%d",
        socialDone = "%s ti ukázal své věci. Otevři je v seznamu.", socialErr_pending = "Tohoto hráče jsi už požádal.", socialErr_self = "To jsi ty.",
        socialErr_no_target = "Napiš jméno, nebo označ hráče a stiskni tlačítko.", socialErr_no_kinds = "Zaškrtni aspoň jednu věc.", socialErr_queue_full = "Čeká příliš mnoho zpráv. Zkus to za chvíli.", socialErr_size_limit = "To je příliš mnoho k odeslání.",
        socialNoViews = "Zatím nic nepřišlo. Požádej hráče; on rozhodne, co ukáže.", socialNoProposals = "Zatím žádné návrhy výměn.", socialNoMeets = "Zatím žádné srazy.", socialNoShown = "V této relaci jsi nic neukázal.",
        socialIn = "od", socialOut = "pro", socialStatus_open = "otevřeno", socialStatus_sent = "odesláno", socialStatus_accepted = "přijato", socialStatus_declined = "odmítnuto",
        socialMeetTitle = "Poslat sraz", socialLiveOn = "Živá poloha: ZAPNUTO", socialLiveOff = "Živá poloha: VYPNUTO", socialMeetLabelHint = "Název místa (nepovinné)", socialMeetHelp = "Sraz ukáže ostatním waypoint tam, kde stojíš (nebo na místo pod kurzorem na mapě). Vyber, komu: partě, cechu nebo tvému cíli. Oni ho přijmou jedním klikem.", socialMeetParty = "Partě / raidu", socialMeetGuild = "Cechu", socialMeetWhisper = "Mému cíli", socialMeetSent = "Odesláno. Ostatní si mohou nastavit waypoint. Tip: s otevřenou mapou se pošle místo pod kurzorem.", socialMeetErr_no_position = "Tady není poloha na mapě (instance nebo načítání).",
        socialMeetErr_no_target = "Nejdřív někoho označ.", socialMeetErr_queue_full = "Čeká příliš mnoho zpráv.", socialMeetIn = "za %d min", socialMeetNow = "hned",
        socialPrivacyInfo = "Co ti jiný hráč ukáže, drží se jen dokud běží addon: nikdy se neukládá ani neodesílá. Než kdokoli uvidí něco z tvého, zeptá se tě a pokaždé volíš, co ukážeš. Evertally si neuchovává, co jsi ukázal, jen krátký seznam níže.",
        socialShownTitle = "Ukázal jsi:", socialBlockedHint = "Zablokován. Kliknutím odblokuješ.", socialBlock = "Blokovat",
        socialAskTitle = "%s se chce podívat na:", socialAskNote = "Uvidí jen to, co zaškrtneš. Zlato a kopie na webu se nikdy nezaškrtávají za tebe. \"Vždy\" se zlata netýká a půjde vzít zpět v Soukromí nebo příkazem /etally revoke.", socialAllow = "Povolit", socialDeny = "Odmítnout",
        socialAllowOnce = "Jednou", socialAllowAlways = "Vždy", socialStats = "Statistiky", socialTalents = "Talenty", socialWeb = "Nechat na jejich webu",
        socialWebAsk = "Smí si to nechat na webu Evertally", socialTrustedTitle = "Povoleno trvale:", socialRevoke = "Odvolat", socialRevoked = "odvoláno",
        socialPermissionNote = "Hráč rozhodne, co ukáže. Zlato se žádá zvlášť.",
        viewTab_stats = "Statistiky", viewTab_talents = "Talenty", viewNoStats = "Statistiky neukázal.", viewNoTalents = "Talenty neukázal.", viewTalentPoints = "Talentů s body: %d",
        viewTitle = "%s", viewReceived = "přijato %s", viewTab_equipped = "Nasazené", viewTab_bags = "Tašky", viewTab_professions = "Profese", viewTab_gold = "Zlato",
        viewPointInfo = "Ukaž předmět: klikni na něj a v jeho otevřených taškách zableská zeleně.", viewPoint = "Ukazovat", viewPointed = "Ukazuji %s hráči %s", viewPointHint = "REŽIM UKAZOVÁNÍ je zapnutý: klikni na předmět a v JEHO otevřených taškách (i v addonech na tašky) zableská zeleně a přijde mu zpráva do chatu. Dalším klikem na \"Ukazovat\" se vrátíš k výběru chtěných předmětů.",
        viewWant = "CHCI", viewOffer = "NABÍZÍM", viewMyOffer = "Moje nabídka (moje tašky)", viewGoldOffer = "Zlato, které nabízím", viewNote = "Poznámka", viewSend = "Poslat návrh", viewSent = "Návrh odeslán hráči %s.",
        viewHint = "Kliknutím na věc ji označíš jako chtěnou (znovu = celý stack, znovu = zrušit). Vpravo vyber, co nabízíš, a pošli.", viewNoGold = "Své zlato neukázal.",
        viewNoProf = "Žádné profese neukázal, nebo ještě žádné nejsou zaznamenané.", viewRecipes = "Známých receptů: %d",
        viewSearch = "Hledat věci...", viewSortBy = "Řazení:", viewSort_default = "výchozí", viewSort_quality = "kvalita", viewSort_name = "název", viewSort_type = "typ (skupiny)", viewCount = "%d/%d", viewNoMatch = "Nic neodpovídá.",
        viewType_weapon = "Zbraně", viewType_armor = "Zbroj", viewType_consumable = "Spotřebky", viewType_container = "Tašky", viewType_ammo = "Střelivo", viewType_trade = "Řemeslné zboží", viewType_recipe = "Recepty", viewType_quest = "Úkolové věci", viewType_misc = "Ostatní", viewType_unknown = "Ještě nenačteno",
        propTitle = "%s navrhuje výměnu", propWants = "Chce od tebe:", propOffers = "Nabízí:", propGold = "Zlato: %s", propNote = "Poznámka: %s", propAccept = "Přijmout", propDecline = "Odmítnout",
        propAcceptedHint = "Přijato. Sejděte se a použijte běžné okno výměny.", propTradeOpened = "Přijato. Otevírám okno výměny.", meetTitle = "%s navrhuje sraz", meetWaypoint = "Nastavit waypoint", meetDismiss = "Zavřít",
        viewSlot1 = "Hlava", viewSlot2 = "Krk", viewSlot3 = "Ramena", viewSlot4 = "Košile", viewSlot5 = "Hruď", viewSlot6 = "Opasek", viewSlot7 = "Nohy", viewSlot8 = "Boty", viewSlot9 = "Zápěstí", viewSlot10 = "Ruce",
        viewSlot11 = "Prsten 1", viewSlot12 = "Prsten 2", viewSlot13 = "Talisman 1", viewSlot14 = "Talisman 2", viewSlot15 = "Záda", viewSlot16 = "Hlavní ruka", viewSlot17 = "Vedlejší ruka", viewSlot18 = "Střelná zbraň", viewSlot19 = "Tabard",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local more = {
    en = {social = "People", sub_social = "Look at a player's gear and bags (they decide what to show), propose a trade, send a meet or a ping.",
        socialRoster = "People nearby", socialNoRoster = "Nobody here. Target a player or type a name on the right.", socialRosterTarget = "your target", socialRosterGroup = "in your group",
        socialRosterLive = "shares a live position", socialRosterSeen = "showed you things", socialViewsTitle = "What they showed you", socialRosterFriend = "friend", socialRosterGuild = "guild", viewNoOffer = "Your bags are empty, so there is nothing to offer."},
    cs = {social = "Lidé", sub_social = "Pohled na výbavu a tašky hráče (on rozhodne, co ukáže), návrh výměny, sraz nebo ping.",
        socialRoster = "Lidé v okolí", socialNoRoster = "Nikdo tu není. Označ hráče nebo napiš jméno vpravo.", socialRosterTarget = "tvůj cíl", socialRosterGroup = "ve tvé skupině",
        socialRosterLive = "sdílí živou polohu", socialRosterSeen = "ukázal ti věci", socialViewsTitle = "Co ti ukázali", socialRosterFriend = "přítel", socialRosterGuild = "cech", viewNoOffer = "Tvoje tašky jsou prázdné, nemáš co nabídnout."},
}
for lang, entries in pairs(more) do for key, value in pairs(entries) do A.locale[lang][key] = value end end
