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

-- ---------------------------------------------------------------- one popup, answered one question at a time
local function closePopup() if popup then popup:Hide() end; popup.current = nil; local nextSpec = table.remove(queue, 1); if nextSpec then A.SocialShowPopup(nextSpec) end end
local function ensurePopup()
    if popup then return popup end
    local k = K()
    local f = CreateFrame("Frame", "EvertallySocialPopup", UIParent)
    f:SetSize(440, 250); f:SetPoint("TOP", UIParent, "TOP", 0, -150); f:SetFrameStrata("DIALOG"); f:EnableMouse(true)
    A.NativeFrame(f, k.C)
    f.title = k.label(f, 15, k.C.gold); f.title:SetPoint("TOPLEFT", 18, -16); f.title:SetWidth(404)
    f.body = k.label(f, 12, k.C.mist); f.body:SetPoint("TOPLEFT", 18, -46); f.body:SetWidth(404); f.body:SetJustifyV("TOP")
    f.checks, f.buttons = {}, {}
    for i = 1, 3 do
        local b = k.Button(f, nil, 404, "ghost", function() end); b:SetPoint("TOPLEFT", 18, -112 - (i - 1) * 32); b:Hide(); f.checks[i] = b
    end
    for i = 1, 3 do f.buttons[i] = k.Button(f, nil, 126, i == 1 and "primary" or "ghost", function() end); f.buttons[i]:Hide() end
    popup = f
    return f
end
--- spec = {title, body, checks={{key,label,on}}, buttons={{label,primary,fn(selected)}}, id}
function A.SocialShowPopup(spec)
    local ok = pcall(function()
        local f = ensurePopup()
        if f:IsShown() and f.current then queue[#queue + 1] = spec; return end
        f.current = spec
        f.title:SetText(spec.title or ""); f.body:SetText(spec.body or "")
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
                b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", 18 + (i - 1) * 134, 16); b.text:SetText(def.label); b:Show()
                b:SetScript("OnClick", function() pcall(def.fn, selected); closePopup() end)
            else b:Hide() end
        end
        f:Show()
    end)
    if not ok then A.errors.social_popup = (A.errors.social_popup or 0) + 1 end
end

-- ---------------------------------------------------------------- reactions to what happens
local function kindsText(kinds)
    local out = {}
    if kinds:find("i", 1, true) then out[#out + 1] = A.L("socialInv") end
    if kinds:find("p", 1, true) then out[#out + 1] = A.L("socialProf") end
    if kinds:find("g", 1, true) then out[#out + 1] = A.L("socialGold") end
    return table.concat(out, ", ")
end
local function askPopup(request)
    local checks = {}
    for _, key in ipairs({"i", "p", "g"}) do
        if request.kinds:find(key, 1, true) then checks[#checks + 1] = {key = key, label = A.L(({i = "socialInv", p = "socialProf", g = "socialGold"})[key]), on = key ~= "g"} end
    end
    A.SocialShowPopup({id = request.id, title = string.format(A.L("socialAskTitle"), plain(base(request.sender))), body = A.L("socialAskNote"), checks = checks, buttons = {
        {label = A.L("socialAllow"), fn = function(sel) local allowed = ""; for _, key in ipairs({"i", "p", "g"}) do if sel[key] then allowed = allowed .. key end end; A.AnswerRequest(request.id, allowed) end},
        {label = A.L("socialDeny"), fn = function() A.DenyRequest(request.id, false) end},
        {label = A.L("socialBlock"), fn = function() A.DenyRequest(request.id, true) end},
    }})
end
local function proposalPopup(entry)
    local lines = {A.L("propWants") .. " " .. itemsText(entry.want), A.L("propOffers") .. " " .. itemsText(entry.offer)}
    if (entry.gold or 0) > 0 then lines[#lines + 1] = string.format(A.L("propGold"), money(entry.gold)) end
    if entry.note and entry.note ~= "" then lines[#lines + 1] = string.format(A.L("propNote"), plain(entry.note)) end
    A.SocialShowPopup({id = entry.id, title = string.format(A.L("propTitle"), plain(base(entry.peer))), body = table.concat(lines, "\n"), buttons = {
        {label = A.L("propAccept"), fn = function() A.AnswerProposal(entry.id, true, ""); A.Print(A.L("propAcceptedHint")) end},
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
local function openViewer(view)
    local ok, err = pcall(function()
        local k = K()
        local C = k.C
        if not viewer then
            local f = CreateFrame("Frame", "EvertallyViewFrame", UIParent)
            f:SetSize(820, 560); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
            A.NativeFrame(f, C)
            f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", function() f:StartMoving() end); f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
            f.title = k.label(f, 18, C.gold); f.title:SetPoint("TOPLEFT", 18, -14); f.title:SetWidth(560)
            f.sub = k.label(f, 11, C.mist); f.sub:SetPoint("TOPLEFT", 18, -40); f.sub:SetWidth(760)
            f.close = k.Button(f, nil, 30, "ghost", function() f:Hide() end); f.close:SetPoint("TOPRIGHT", -14, -12); f.close.text:SetText("x")
            f.tabs = {}
            local previous
            for _, mode in ipairs({"equipped", "bags", "professions", "gold"}) do
                local chip = k.Chip(f, function() f.mode = mode; A.SocialRefreshViewer() end)
                if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 18, -66) end
                f.tabs[mode] = chip; previous = chip
            end
            -- what they showed: icons for gear and bags, rows for professions and gold
            f.grid = k.IconGrid(f, 40, 6); f.grid:ClearAllPoints(); f.grid:SetPoint("TOPLEFT", 18, -102); f.grid:SetPoint("BOTTOMLEFT", 18, 36); f.grid:SetWidth(444)
            f.list = k.ListView(f, 102); f.list:ClearAllPoints(); f.list:SetPoint("TOPLEFT", 18, -102); f.list:SetPoint("BOTTOMLEFT", 18, 36); f.list:SetWidth(444); f.list.child:SetWidth(436)
            -- what I offer back
            f.offerTitle = k.label(f, 13, C.lilac); f.offerTitle:SetPoint("TOPLEFT", 492, -68); f.offerTitle:SetWidth(310)
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
    f.send.text:SetText(A.L("viewSend")); f.hint:SetText(A.L("viewHint"))
    local icons = f.mode == "equipped" or f.mode == "bags"
    f.grid:SetShown(icons); f.list:SetShown(not icons)
    if f.mode == "equipped" then
        local cells = {}
        for _, e in ipairs(v.equipped) do
            local id = e[2]
            cells[#cells + 1] = {itemId = id, icon = k.itemIcon(id), slot = A.L("viewSlot" .. e[1]), mark = f.wanted[id] and "want" or nil, markText = f.wanted[id] and A.L("viewWant") or nil,
                onClick = function() cycle(f.wanted, id, 1); A.SocialRefreshViewer() end}
        end
        f.grid.SetCells(cells, A.L("noData"))
    elseif f.mode == "bags" then
        local cells = {}
        for _, e in ipairs(v.bags) do
            local id, n = e[1], e[2]
            cells[#cells + 1] = {itemId = id, icon = k.itemIcon(id), count = n, mark = f.wanted[id] and "want" or nil, markText = f.wanted[id] and (f.wanted[id] >= n and n > 1 and "x" .. n or A.L("viewWant")) or nil,
                onClick = function() cycle(f.wanted, id, n); A.SocialRefreshViewer() end}
        end
        f.grid.SetCells(cells, A.L("noData"))
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
    local cells = {}
    for _, e in ipairs(A.OwnInventory().bags) do
        local id, n = e[1], e[2]
        cells[#cells + 1] = {itemId = id, icon = k.itemIcon(id), count = n, mark = f.offered[id] and "offer" or nil, markText = f.offered[id] and (f.offered[id] >= n and n > 1 and "x" .. n or A.L("viewOffer")) or nil,
            onClick = function() cycle(f.offered, id, n); A.SocialRefreshViewer() end}
    end
    f.offers.SetCells(cells, A.L("viewNoOffer"))
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
    for _, s in ipairs(A.social.shown) do rows[#rows + 1] = {title = plain(s.name), sub = A.L("socialShownTitle") .. " " .. kindsText(s.kinds) .. "  ·  " .. (A.Call(date, "%H:%M", s.at) or ""), icon = K().ICON.peers} end
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

function A.BuildSocialPage(host, k)
    page = host; A.social.page = host
    local C = k.C
    k.PageHeader(page, "social")
    page.mode = "ask"
    page.tabs = {}
    local previous
    for _, mode in ipairs({"ask", "live", "proposals", "meets", "privacy"}) do
        local chip = k.Chip(page, function() page.mode = mode; A.RefreshUI() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -54) end
        page.tabs[mode] = chip; previous = chip
    end

    -- ask: the people around you on the left, the request and what they showed you on the right
    page.cols = k.Columns(page, {2, 3}, 12)
    page.cols:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -90); page.cols:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    local rosterCard = k.Card(page.cols.cells[1]); rosterCard:SetAllPoints(page.cols.cells[1])
    page.rosterTitle = k.label(rosterCard, 13, C.gold); page.rosterTitle:SetPoint("TOPLEFT", 14, -12)
    local rosterInner = CreateFrame("Frame", nil, rosterCard); rosterInner:SetPoint("TOPLEFT", 8, -36); rosterInner:SetPoint("BOTTOMRIGHT", -8, 8)
    page.roster = k.ListView(rosterInner, 0)
    local right = page.cols.cells[2]
    local form = k.Card(right, C.lilac); form:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0); form:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, 0); form:SetHeight(152)
    page.formTitle = k.label(form, 13, C.gold); page.formTitle:SetPoint("TOPLEFT", 14, -12)
    page.name = CreateFrame("EditBox", nil, form, "InputBoxTemplate"); page.name:SetHeight(26)
    page.name:SetPoint("TOPLEFT", form, "TOPLEFT", 20, -38); page.name:SetPoint("TOPRIGHT", form, "TOPRIGHT", -132, -38)
    page.name:SetAutoFocus(false); page.name:SetMaxLetters(80); page.name:SetFont(FONT, 12, "")
    page.target = k.Button(form, "socialTarget", 108, "ghost", function()
        local name, realm = A.Call(UnitFullName, "target")
        name = A.Text(name or A.Call(UnitName, "target"), 80)
        if name then page.name:SetText(name .. ((A.Text(realm, 80) or "") ~= "" and ("-" .. A.Text(realm, 80)) or "")) end
    end); page.target:SetPoint("TOPRIGHT", form, "TOPRIGHT", -14, -36)
    page.kinds = {i = true, p = true, g = false}
    page.kindButtons = {}
    local last
    for _, key in ipairs({"i", "p", "g"}) do
        local chip = k.Chip(form, function() page.kinds[key] = not page.kinds[key]; A.RefreshUI() end)
        if last then chip:SetPoint("LEFT", last, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", form, "TOPLEFT", 14, -74) end
        page.kindButtons[key] = chip; last = chip
    end
    page.sendRequest = k.Button(form, "socialSend", 150, "primary", function()
        local chosen = ""; for _, key in ipairs({"i", "p", "g"}) do if page.kinds[key] then chosen = chosen .. key end end
        local ok, err = A.RequestInspect(page.name:GetText() or "", chosen)
        page.status:SetText(ok and string.format(A.L("socialWaiting"), plain(base(page.name:GetText() or ""))) or A.L("socialErr_" .. tostring(err)))
        A.RefreshUI()
    end); page.sendRequest:SetPoint("TOPLEFT", form, "TOPLEFT", 14, -108)
    page.status = k.label(form, 11, C.green); page.status:SetPoint("LEFT", page.sendRequest, "RIGHT", 12, 0); page.status:SetPoint("RIGHT", form, "RIGHT", -14, 0)
    local viewsCard = k.Card(right); viewsCard:SetPoint("TOPLEFT", form, "BOTTOMLEFT", 0, -10); viewsCard:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
    page.viewsTitle = k.label(viewsCard, 13, C.gold); page.viewsTitle:SetPoint("TOPLEFT", 14, -12)
    local viewsInner = CreateFrame("Frame", nil, viewsCard); viewsInner:SetPoint("TOPLEFT", 8, -36); viewsInner:SetPoint("BOTTOMRIGHT", -8, 8)
    page.viewList = k.ListView(viewsInner, 0)

    -- meets
    page.meetLabel = CreateFrame("EditBox", nil, page, "InputBoxTemplate"); page.meetLabel:SetSize(300, 26); page.meetLabel:SetPoint("TOPLEFT", 6, -100)
    page.meetLabel:SetAutoFocus(false); page.meetLabel:SetMaxLetters(60); page.meetLabel:SetFont(FONT, 12, "")
    page.meetButtons = {}
    for n, def in ipairs({{"PARTY", "socialMeetParty"}, {"GUILD", "socialMeetGuild"}, {"WHISPER", "socialMeetWhisper"}}) do
        local b = k.Button(page, def[2], 140, "ghost", function()
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
        end); b:SetPoint("TOPLEFT", (n - 1) * 146, -136); page.meetButtons[#page.meetButtons + 1] = b
    end
    page.meetStatus = k.label(page, 11, C.green); page.meetStatus:SetPoint("TOPLEFT", 0, -172); page.meetStatus:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -172)
    -- live
    page.ping = k.Button(page, "socialPing", 150, "primary", function()
        local ok, err = A.SendPing("")
        A.Print(ok and A.L("pingSent") or A.L("pingErr_" .. tostring(err))); A.RefreshUI()
    end); page.ping:SetPoint("TOPLEFT", 0, -100)
    page.stopNav = k.Button(page, "socialStopNav", 190, "ghost", function() A.StopNavigation(); A.Print(A.L("navStopped")) end); page.stopNav:SetPoint("LEFT", page.ping, "RIGHT", 10, 0)
    page.liveNote = k.label(page, 11, C.mist); page.liveNote:SetPoint("TOPLEFT", 0, -144); page.liveNote:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -144)
    -- privacy
    page.privacy = k.label(page, 11, C.mist); page.privacy:SetPoint("TOPLEFT", 0, -96); page.privacy:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -96)
    page.list = k.ListView(page, 204)
    function page.Refresh()
        local mode = page.mode
        for key, chip in pairs(page.tabs) do chip.SetLabel(A.L("socialTab_" .. key)); chip.SetOn(mode == key) end
        page.cols:SetShown(mode == "ask"); page.cols.Layout()
        for key, chip in pairs(page.kindButtons) do chip.SetLabel(A.L(({i = "socialInv", p = "socialProf", g = "socialGold"})[key])); chip.SetOn(page.kinds[key]) end
        page.rosterTitle:SetText(A.L("socialRoster")); page.formTitle:SetText(A.L("socialAsk")); page.viewsTitle:SetText(A.L("socialViewsTitle"))
        page.meetLabel:SetShown(mode == "meets"); page.meetStatus:SetShown(mode == "meets")
        for _, b in ipairs(page.meetButtons) do b:SetShown(mode == "meets"); b.text:SetText(A.L(b.localeKey)) end
        page.privacy:SetShown(mode == "privacy"); page.privacy:SetText(A.L("socialPrivacyInfo"))
        for _, w in ipairs({page.ping, page.stopNav, page.liveNote}) do w:SetShown(mode == "live") end
        page.list:SetShown(mode ~= "ask")
        page.ping.text:SetText(A.L("socialPing")); page.stopNav.text:SetText(A.L("socialStopNav"))
        page.liveNote:SetText(A.LiveActive() and A.L("liveHint") or (A.L("liveOffNote") .. "  " .. A.L("liveHint")))
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
            page.roster.SetItems(rosterRows(), A.L("socialNoRoster"))
            page.viewList.SetItems(viewRows(), A.L("socialNoViews"))
        elseif mode == "live" then page.list.SetItems(liveRows(), A.L("liveNone"))
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
    elseif kind == "view" then if not viewer or not viewer:IsShown() then openViewer(data) end end
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
        socialTab_ask = "Look", socialTab_proposals = "Trades", socialTab_meets = "Meets", socialTab_privacy = "Privacy",
        socialWaiting = "Waiting for %s to answer...", socialDenied = "%s declined.", socialNoAnswer = "%s did not answer.", socialReceiving = "Receiving from %s: %d/%d",
        socialDone = "%s showed you their things. Open them in the list.", socialErr_pending = "You already asked this player.", socialErr_self = "That is you.",
        socialErr_no_target = "Type a name, or target a player and press the button.", socialErr_no_kinds = "Tick at least one thing to ask for.", socialErr_queue_full = "Too many messages are waiting. Try again in a moment.", socialErr_size_limit = "That is too much to send.",
        socialNoViews = "Nothing received yet. Ask a player; they decide what to show.", socialNoProposals = "No trade proposals yet.", socialNoMeets = "No meets received yet.", socialNoShown = "You have not shown anything this session.",
        socialIn = "from", socialOut = "to", socialStatus_open = "open", socialStatus_sent = "sent", socialStatus_accepted = "accepted", socialStatus_declined = "declined",
        socialMeetParty = "To party / raid", socialMeetGuild = "To guild", socialMeetWhisper = "To my target", socialMeetSent = "Sent. Others can set a waypoint.", socialMeetErr_no_position = "No map position here (instance or loading screen).",
        socialMeetErr_no_target = "Target a player first.", socialMeetErr_queue_full = "Too many messages are waiting.", socialMeetIn = "in %d min", socialMeetNow = "now",
        socialPrivacyInfo = "What another player shows you is kept only while the addon runs: it is never saved and never uploaded. You are asked before anyone sees anything of yours, and you choose what to show each time. Evertally does not keep what you showed, only a short list below.",
        socialShownTitle = "You showed:", socialBlockedHint = "Blocked. Click to unblock.", socialBlock = "Block",
        socialAskTitle = "%s asks to look at:", socialAskNote = "They see only what you tick. Evertally does not save what you show.", socialAllow = "Allow", socialDeny = "Deny",
        viewTitle = "%s", viewReceived = "received %s", viewTab_equipped = "Equipped", viewTab_bags = "Bags", viewTab_professions = "Professions", viewTab_gold = "Gold",
        viewWant = "WANT", viewOffer = "OFFER", viewMyOffer = "My offer (my bags)", viewGoldOffer = "Gold I offer", viewNote = "Note", viewSend = "Send proposal", viewSent = "Proposal sent to %s.",
        viewHint = "Click an item to mark it as wanted (click again for the whole stack, again to remove). Pick what you offer on the right, then send.", viewNoGold = "They did not show their gold.",
        viewNoProf = "No professions shown, or none recorded yet.", viewRecipes = "%d known recipes",
        propTitle = "%s proposes a trade", propWants = "Wants from you:", propOffers = "Offers:", propGold = "Gold: %s", propNote = "Note: %s", propAccept = "Accept", propDecline = "Decline",
        propAcceptedHint = "Accepted. Meet and use the normal trade window.", meetTitle = "%s suggests a meet", meetWaypoint = "Set waypoint", meetDismiss = "Dismiss",
        viewSlot1 = "Head", viewSlot2 = "Neck", viewSlot3 = "Shoulder", viewSlot4 = "Shirt", viewSlot5 = "Chest", viewSlot6 = "Waist", viewSlot7 = "Legs", viewSlot8 = "Feet", viewSlot9 = "Wrist", viewSlot10 = "Hands",
        viewSlot11 = "Finger 1", viewSlot12 = "Finger 2", viewSlot13 = "Trinket 1", viewSlot14 = "Trinket 2", viewSlot15 = "Back", viewSlot16 = "Main hand", viewSlot17 = "Off hand", viewSlot18 = "Ranged", viewSlot19 = "Tabard",
    },
    cs = {
        waypointSet = "Waypoint nastaven: %s", socialAsk = "Požádat o pohled do hráče", socialTarget = "Můj cíl", socialInv = "Výbava a tašky", socialProf = "Profese", socialGold = "Zlato", socialSend = "Odeslat žádost",
        socialTab_ask = "Pohled", socialTab_proposals = "Výměny", socialTab_meets = "Srazy", socialTab_privacy = "Soukromí",
        socialWaiting = "Čeká se, až %s odpoví...", socialDenied = "%s odmítl.", socialNoAnswer = "%s neodpověděl.", socialReceiving = "Přijímám od %s: %d/%d",
        socialDone = "%s ti ukázal své věci. Otevři je v seznamu.", socialErr_pending = "Tohoto hráče jsi už požádal.", socialErr_self = "To jsi ty.",
        socialErr_no_target = "Napiš jméno, nebo označ hráče a stiskni tlačítko.", socialErr_no_kinds = "Zaškrtni aspoň jednu věc.", socialErr_queue_full = "Čeká příliš mnoho zpráv. Zkus to za chvíli.", socialErr_size_limit = "To je příliš mnoho k odeslání.",
        socialNoViews = "Zatím nic nepřišlo. Požádej hráče; on rozhodne, co ukáže.", socialNoProposals = "Zatím žádné návrhy výměn.", socialNoMeets = "Zatím žádné srazy.", socialNoShown = "V této relaci jsi nic neukázal.",
        socialIn = "od", socialOut = "pro", socialStatus_open = "otevřeno", socialStatus_sent = "odesláno", socialStatus_accepted = "přijato", socialStatus_declined = "odmítnuto",
        socialMeetParty = "Partě / raidu", socialMeetGuild = "Cechu", socialMeetWhisper = "Mému cíli", socialMeetSent = "Odesláno. Ostatní si mohou nastavit waypoint.", socialMeetErr_no_position = "Tady není poloha na mapě (instance nebo načítání).",
        socialMeetErr_no_target = "Nejdřív někoho označ.", socialMeetErr_queue_full = "Čeká příliš mnoho zpráv.", socialMeetIn = "za %d min", socialMeetNow = "hned",
        socialPrivacyInfo = "Co ti jiný hráč ukáže, drží se jen dokud běží addon: nikdy se neukládá ani neodesílá. Než kdokoli uvidí něco z tvého, zeptá se tě a pokaždé volíš, co ukážeš. Evertally si neuchovává, co jsi ukázal, jen krátký seznam níže.",
        socialShownTitle = "Ukázal jsi:", socialBlockedHint = "Zablokován. Kliknutím odblokuješ.", socialBlock = "Blokovat",
        socialAskTitle = "%s se chce podívat na:", socialAskNote = "Uvidí jen to, co zaškrtneš. Evertally neukládá, co ukážeš.", socialAllow = "Povolit", socialDeny = "Odmítnout",
        viewTitle = "%s", viewReceived = "přijato %s", viewTab_equipped = "Nasazené", viewTab_bags = "Tašky", viewTab_professions = "Profese", viewTab_gold = "Zlato",
        viewWant = "CHCI", viewOffer = "NABÍZÍM", viewMyOffer = "Moje nabídka (moje tašky)", viewGoldOffer = "Zlato, které nabízím", viewNote = "Poznámka", viewSend = "Poslat návrh", viewSent = "Návrh odeslán hráči %s.",
        viewHint = "Kliknutím na věc ji označíš jako chtěnou (znovu = celý stack, znovu = zrušit). Vpravo vyber, co nabízíš, a pošli.", viewNoGold = "Své zlato neukázal.",
        viewNoProf = "Žádné profese neukázal, nebo ještě žádné nejsou zaznamenané.", viewRecipes = "Známých receptů: %d",
        propTitle = "%s navrhuje výměnu", propWants = "Chce od tebe:", propOffers = "Nabízí:", propGold = "Zlato: %s", propNote = "Poznámka: %s", propAccept = "Přijmout", propDecline = "Odmítnout",
        propAcceptedHint = "Přijato. Sejděte se a použijte běžné okno výměny.", meetTitle = "%s navrhuje sraz", meetWaypoint = "Nastavit waypoint", meetDismiss = "Zavřít",
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
