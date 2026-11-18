local _, A = ...
-- The Community page: the forum (Forum.lua) in navy and gold. Categories across the top, threads in the left ledger
-- and the open thread in the right reader, with a writing window for new
-- threads and replies. Built lazily from helpers the main window exports (A.UIKit); a problem here leaves the old page in place.
local kit
local function K() if not kit then kit = A.UIKit() end return kit end
local page, compose
local FONT = "Fonts\\ARIALN.TTF"

local function plain(text) return (tostring(A.Plain(text) or ""):gsub("|", "||")) end
local function ageText(at)
    local seconds = math.max(0, A.Now() - (A.Number(at, 0) or 0))
    if seconds < 90 then return A.L("agoNow") end
    if seconds < 3600 then return string.format(A.L("agoMinutes"), math.floor(seconds / 60)) end
    if seconds < 86400 then return string.format(A.L("forumAgoHours"), math.floor(seconds / 3600)) end
    return string.format(A.L("forumAgoDays"), math.floor(seconds / 86400))
end
local function categoryName(id) return A.L("forumCat_" .. tostring(id)) end
local CS_LOWER={["Á"]="á",["Č"]="č",["Ď"]="ď",["É"]="é",["Ě"]="ě",["Í"]="í",["Ň"]="ň",["Ó"]="ó",["Ř"]="ř",["Š"]="š",["Ť"]="ť",["Ú"]="ú",["Ů"]="ů",["Ý"]="ý",["Ž"]="ž"}
local function searchFold(value)
    -- Lua 5.1 may lowercase UTF-8 lead bytes according to the OS locale.
    -- Only fold ASCII here; handle Czech characters as complete UTF-8 pairs.
    local s=tostring(value or ""):gsub("[A-Z]",function(c) return string.char(c:byte()+32) end)
    return (s:gsub("[\195-\197][\128-\191]",function(c) return CS_LOWER[c] or c end))
end
local function matchesSearch(thread,query)
    if query=="" then return true end
    local function contains(s) return searchFold(s):find(query,1,true)~=nil end
    if contains(thread.title) or contains(thread.author) then return true end
    for _,post in ipairs(thread.posts or {}) do if contains(post.body) or contains(post.author) then return true end end
    return false
end
local function fitIndex(text, width, measure)
    local value=tostring(text or "")
    measure:SetText(value)
    if (measure:GetStringWidth() or 0)<=width then return value end
    local suffix="..."
    while value~="" do
        value=value:match("^(.*)[\1-\127\194-\244][\128-\191]*$") or ""
        measure:SetText(value..suffix)
        if (measure:GetStringWidth() or 0)<=width then return value..suffix end
    end
    return suffix
end

-- ---------------------------------------------------------------- the writing window
local function ensureCompose()
    if compose then return compose end
    local k = K()
    local C = k.C
    local f = CreateFrame("Frame", "EvertallyForumCompose", UIParent)
    f:SetSize(600, 500); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    A.NativeFrame(f, C)
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", function() f:StartMoving() end); f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.title = k.label(f, 20, C.bright or C.gold); f.title:SetPoint("TOPLEFT", 20, -18); f.title:SetPoint("TOPRIGHT", -20, -18)
    f.quote = k.label(f, 11, C.mist); f.quote:SetPoint("TOPLEFT", 20, -60); f.quote:SetPoint("TOPRIGHT", -20, -60); f.quote:SetHeight(30); f.quote:SetWordWrap(true); f.quote:SetJustifyV("TOP")
    f.chips = {}
    local previous
    for _, id in ipairs(A.ForumCategories()) do
        local chip = k.Chip(f, function() f.category = id; A.ForumRefreshCompose() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 5, 0) else chip:SetPoint("TOPLEFT", 18, -44) end
        chip.categoryId = id; f.chips[#f.chips + 1] = chip; previous = chip
    end
    f.titleLabel = k.label(f, 11, C.gold)
    f.titleBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); f.titleBox:SetHeight(30)
    f.titleBox:SetAutoFocus(false); f.titleBox:SetMaxLetters(A.FORUM_LIMITS.title); f.titleBox:SetFont(FONT, 12, ""); k.trackFont(f.titleBox, 12)
    f.bodyLabel = k.label(f, 11, C.gold)
    f.editor = CreateFrame("Frame", nil, f); A.NativePanel(f.editor,C)
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.body = CreateFrame("EditBox", nil, f.scroll)
    f.body:SetMultiLine(true); f.body:SetAutoFocus(false); f.body:SetFont(FONT, 13, ""); k.trackFont(f.body, 13); f.body:SetTextColor(unpack(C.text))
    f.body:SetWidth(520); f.body:SetMaxLetters(A.FORUM_LIMITS.body)
    f.body:SetScript("OnEscapePressed", function() f:Hide() end)
    f.body:SetScript("OnTextChanged", function() A.ForumRefreshCompose() end)
    f.scroll:SetScrollChild(f.body)
    f.counter = k.label(f, 10, C.faint); f.counter:SetPoint("BOTTOMRIGHT", -18, 90); f.counter:SetJustifyH("RIGHT")
    f.status = k.label(f, 11, C.peach); f.status:SetPoint("BOTTOMLEFT", 18, 90); f.status:SetWidth(380)
    f.note = k.label(f, 10, C.mist); f.note:SetPoint("BOTTOMLEFT", 20, 54); f.note:SetPoint("BOTTOMRIGHT", -20, 54); f.note:SetHeight(28); f.note:SetWordWrap(true); f.note:SetJustifyV("TOP")
    f.submit = k.Button(f, "forumPost", 150, "primary", function() A.ForumSubmitCompose() end); f.submit:SetPoint("BOTTOMLEFT", 18, 16)
    f.cancel = k.Button(f, "forumCancel", 110, "ghost", function() f:Hide() end); f.cancel:SetPoint("BOTTOMRIGHT", -18, 16)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EvertallyForumCompose" end
    compose = f
    return f
end

function A.ForumRefreshCompose()
    local f = compose
    if not f then return end
    local isThread = f.mode == "thread"
    local x,y=20,-60
    f.title:SetText(A.L(isThread and "forumNewTitle" or "forumReplyTitle"))
    f.quote:SetShown(not isThread); f.quote:SetText(f.quoteText or "")
    for _, chip in ipairs(f.chips) do
        chip:SetShown(isThread); chip.SetLabel(A.L("forumCatShort_" .. chip.categoryId)); chip.SetOn(f.category == chip.categoryId)
        local width=tonumber(chip:GetWidth()) or 80
        if x>20 and x+width>580 then x,y=20,y-30 end
        chip:ClearAllPoints();chip:SetPoint("TOPLEFT",x,y);x=x+width+6
    end
    local titleTop=-y+42
    local top=isThread and titleTop+78 or 116
    f.titleLabel:SetShown(isThread); f.titleLabel:SetText(A.L("forumThreadTitle")); f.titleBox:SetShown(isThread)
    f.titleLabel:ClearAllPoints();f.titleLabel:SetPoint("TOPLEFT",20,-titleTop)
    f.titleBox:ClearAllPoints();f.titleBox:SetPoint("TOPLEFT",24,-titleTop-17);f.titleBox:SetPoint("TOPRIGHT",-20,-titleTop-17)
    f.bodyLabel:ClearAllPoints(); f.bodyLabel:SetPoint("TOPLEFT", 20, -(top - 20)); f.bodyLabel:SetText(A.L("forumThreadBody"))
    f.editor:ClearAllPoints();f.editor:SetPoint("TOPLEFT",20,-top);f.editor:SetPoint("BOTTOMRIGHT",-20,112)
    f.scroll:ClearAllPoints(); f.scroll:SetPoint("TOPLEFT", 30, -top-10); f.scroll:SetPoint("BOTTOMRIGHT", -44, 122)
    local author = A.ForumAuthor()
    f.note:SetText(string.format(A.L("forumPublicNote"), plain(author or "?")))
    f.counter:SetText(string.format("%d / %d", #(f.body:GetText() or ""), A.FORUM_LIMITS.body))
    f.submit.text:SetText(A.L("forumPost")); f.cancel.text:SetText(A.L("forumCancel"))
end

--- spec = {thread = id (a reply), replyTo = post id, category = id (a new thread)}
function A.ForumOpenCompose(spec)
    local ok, err = pcall(function()
        spec = spec or {}
        local f = ensureCompose()
        f.mode = spec.threadId and "reply" or "thread"
        f.threadId, f.replyTo, f.category = spec.threadId, spec.replyTo, spec.category or "general"
        f.quoteText = ""
        if spec.threadId then
            local thread = A.ForumThread(spec.threadId)
            for _, post in ipairs(thread and thread.posts or {}) do
                if post.id == spec.replyTo then f.quoteText = string.format(A.L("forumReplyingTo"), plain(post.author), plain((post.body:gsub("%s+", " "):sub(1, 90)))) end
            end
            if f.quoteText == "" and thread then f.quoteText = string.format(A.L("forumReplyingThread"), plain(thread.title)) end
        end
        f.titleBox:SetText(""); f.body:SetText(""); f.status:SetText("")
        A.ForumRefreshCompose()
        f:Show()
    end)
    if not ok then A.errors.forum_compose = (A.errors.forum_compose or 0) + 1; A.lastUIError = tostring(err) end
end

function A.ForumSubmitCompose()
    local f = compose
    if not f then return false end
    local ok, result
    if f.mode == "thread" then ok, result = A.ForumNewThread(f.category, f.titleBox:GetText() or "", f.body:GetText() or "")
    else ok, result = A.ForumReply(f.threadId, f.body:GetText() or "", f.replyTo) end
    if not ok then f.status:SetText(A.L("forumErr_" .. tostring(result))); return false end
    f:Hide()
    if page then page.threadId = f.mode == "thread" and result or f.threadId; page.newest = result end
    A.Print(A.L("forumQueued"))
    if A.RefreshUI then A.RefreshUI() end
    return true, result
end

-- ---------------------------------------------------------------- the thread on parchment
local function postEntries(thread)
    local k = K()
    local muted = k.C.mist
    local entries, authors = {}, {}
    for _, post in ipairs(thread.posts) do authors[post.id] = post.author end
    for _, post in ipairs(thread.posts) do
        local meta = ageText(post.createdAt) .. "  ·  " .. A.L(post.origin == "web" and "forumFromWeb" or "forumFromGame")
        if post.pending then meta = meta .. "  ·  " .. A.L("forumPending") end
        -- the full name, character and realm, with the class icon of the character where the class is known
        entries[#entries + 1] = {text = plain(post.author) .. "\n" .. meta, head = true, classId = post.classId, size = 12}
        if post.replyTo and post.replyTo ~= thread.id and authors[post.replyTo] then
            entries[#entries + 1] = {text = string.format(A.L("forumInReplyTo"), plain(authors[post.replyTo])), size = 10, color = muted}
        end
        entries[#entries + 1] = {text = plain(post.body), size=13, color = k.C.text}
        local postId = post.id
        entries[#entries + 1] = {text = string.format(A.L("forumReplyTo"), plain(post.author)), size = 10, color = muted, onClick = function() A.ForumOpenCompose({threadId = thread.id, replyTo = postId}) end}
    end
    return entries
end

-- Forum posts use the same dark reading surface as the ranking and armory;
-- this scrolls individual posts without changing the shared parchment widget.
local function forumDocument(parent, k)
    local document = {pool = {}}
    local scroll = k.ScrollArea(parent, 0)
    scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT", 16, -15); scroll:SetPoint("BOTTOMRIGHT", -22, 12)
    document.scroll = scroll
    function document.Set(spec)
        spec = spec or {}; document.spec = spec
        local old = scroll:GetVerticalScroll() or 0
        local changed = document.key ~= spec.key; document.key = spec.key
        local width = math.max(120, tonumber(scroll.child:GetWidth()) or 300)
        local entries = {{text=spec.title or A.L("noData"), size=21, color=k.C.bright or k.C.gold}}
        if spec.subtitle and spec.subtitle ~= "" then entries[#entries+1] = {text=spec.subtitle,size=11,color=k.C.mist} end
        for _, e in ipairs(spec.entries or {}) do entries[#entries+1]=e end
        local y = 0
        for i, e in ipairs(entries) do
            local row = document.pool[i]
            if not row then
                row=CreateFrame("Button",nil,scroll.child)
                row.text=k.label(row,12,k.C.text); row.text:SetJustifyH("LEFT");row.text:SetJustifyV("TOP");row.text:SetWordWrap(true)
                row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(28,28);row.icon:SetPoint("TOPLEFT",0,-2)
                row.rule=row:CreateTexture(nil,"BORDER");row.rule:SetHeight(1);row.rule:SetPoint("BOTTOMLEFT");row.rule:SetPoint("BOTTOMRIGHT");k.paint(row.rule,k.C.line,0.8)
                row:SetScript("OnClick",function(self) if self.action then self.action() end end)
                document.pool[i]=row
            end
            row:Show();row.action=e.onClick;row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-y);row:SetWidth(width)
            local inset=e.classId and e.raceId and 66 or (e.icon or e.classId) and 38 or 0
            row.text:ClearAllPoints();row.text:SetPoint("TOPLEFT",inset,0);row.text:SetWidth(width-inset)
            row.text:SetFont(k.fontPath(),e.size or 13,"")
            local c=e.color or (e.head and (k.C.bright or k.C.gold) or k.C.text)
            row.text:SetTextColor(c[1],c[2],c[3]);row.text:SetText(e.text or "")
            row.icon:SetShown(e.icon~=nil or e.classId~=nil)
            if e.classId and A.SetClassIcon then A.SetClassIcon(row.icon,e.classId) elseif e.icon then k.setIcon(row.icon,e.icon) end
            if e.raceId and not row.race then row.race=row:CreateTexture(nil,"ARTWORK");row.race:SetSize(24,24);row.race:SetPoint("TOPLEFT",32,-4) end
            if row.race then row.race:SetShown(e.classId~=nil and e.raceId~=nil);if e.raceId and A.SetRaceIcon then A.SetRaceIcon(row.race,e.raceId) end end
            local h=math.max((e.icon or e.classId) and 34 or 0,row.text:GetStringHeight() or 16,e.size or 12)+(e.head and 14 or 10)
            row:SetHeight(h);row.rule:SetShown(e.head==true or e.onClick~=nil);y=y+h
        end
        for i=#entries+1,#document.pool do document.pool[i]:Hide() end
        scroll.child:SetHeight(math.max(1,y+10));scroll:SetVerticalScroll(changed and 0 or math.min(old,math.max(0,y-(scroll:GetHeight() or 1))));scroll.UpdateThumb()
    end
    scroll.onResize=function() if document.spec then document.Set(document.spec) end end
    return document
end
A.CreateCommunityDocument = forumDocument

-- ---------------------------------------------------------------- the page
local function infoLine(info)
    local parts = {}
    if info.invalid then parts[#parts + 1] = A.L("forumInvalid")
    elseif info.generatedAt then parts[#parts + 1] = string.format(A.L("forumCopyFrom"), K().stamp(info.generatedAt))
    else parts[#parts + 1] = A.L("forumNoCopy") end
    if info.pending > 0 then parts[#parts + 1] = string.format(A.L("forumWaiting"), info.pending) end
    return table.concat(parts, "  ·  ")
end

local function layoutChips(p)
    local width = (tonumber(p:GetWidth()) or 600) - 150
    local x, row = 0, 0
    for _, chip in ipairs(p.chips) do
        local w = tonumber(chip:GetWidth()) or 80
        if x > 0 and x + w > width then x = 0; row = row + 1 end
        chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", p, "TOPLEFT", x, -(62 + row * 30))
        x = x + w + 6
    end
    return row
end

-- In the guide's hub: the Database's look (HubKit.lua). The categories are the hub's tabs; the search, New thread, the
-- line about the copy and the threads on the left; the thread with its posts on the right.
local function buildHub(host, k)
    page = host; A.forumPage = host
    local HK = A.HubKit
    local W = HK.Guide().Widgets
    local pad = (W.SHELL and W.SHELL.pad or 32) - 12
    HK.Bleed(page)
    page.category, page.query = "", ""
    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0); left:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -HK.DETAIL_W, 0)
    page.search = HK.Search(left, A.L("forumSearch"), function(value) if value ~= page.query then page.query = value; page.Refresh() end end)
    page.search:SetPoint("TOPLEFT", left, "TOPLEFT", pad, -14); page.search:SetPoint("TOPRIGHT", left, "TOPRIGHT", -pad - 150, -14)
    page.newButton = W.Button(left, A.L("forumNew"), function() A.ForumOpenCompose({category = page.category ~= "" and page.category or "general"}) end, {primary = true, height = 30, width = 140})
    page.newButton:SetPoint("TOPRIGHT", left, "TOPRIGHT", -pad, -14)
    page.info = W.Text(left, "small", "textMuted"); page.info:SetJustifyH("LEFT"); page.info:SetWordWrap(false)
    page.info:SetPoint("TOPLEFT", left, "TOPLEFT", pad, -56); page.info:SetPoint("TOPRIGHT", left, "TOPRIGHT", -pad, -56)
    page.list = HK.List(left)
    page.list.scroll:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -76); page.list.scroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -4, 4)
    page.details = HK.Details(page)
    page.hubTabs = function()
        local info = A.ForumInfo()
        local tabs = {}
        for _, id in ipairs({"", unpack(A.ForumCategories())}) do
            local count = id == "" and info.total or info.counts[id] or 0
            tabs[#tabs + 1] = {key = id == "" and "all" or id, label = A.L(id == "" and "forumAll" or "forumCatShort_" .. id) .. (count > 0 and ("  " .. count) or "")}
        end
        return tabs
    end
    page.hubTab = function() return page.category == "" and "all" or page.category end
    page.OnHubTab = function(key) page.category = key == "all" and "" or key; page.threadId = nil end
    function page.Refresh()
        local info = A.ForumInfo()
        page.info:SetText(infoLine(info))
        local query = searchFold((page.query or ""):match("^%s*(.-)%s*$"))
        local threads = {}
        for _, thread in ipairs(A.ForumThreads(page.category)) do if matchesSearch(thread, query) then threads[#threads + 1] = thread end end
        local current
        for _, thread in ipairs(threads) do if thread.id == page.threadId then current = thread end end
        current = current or threads[1]
        page.threadId = current and current.id or nil
        local entries = {}
        for _, thread in ipairs(threads) do
            local id = thread.id
            entries[#entries + 1] = {key = id, title = (thread.pinned and "* " or "") .. plain(thread.title), glyph = "icon-talk",
                color = thread.pending and "textMuted" or "text", sub = plain(thread.author) .. "  \194\183  " .. string.format(A.L("forumRepliesShort"), thread.replies),
                onClick = function() page.threadId = id; page.Refresh() end}
        end
        page.list.Set(entries, page.threadId)
        if current then
            local blocks = {}
            for _, e in ipairs(postEntries(current) or {}) do
                blocks[#blocks + 1] = {text = e.text, head = e.head or (e.size and e.size >= 13 and not e.onClick) or nil, onClick = e.onClick, muted = e.color ~= nil and not e.onClick and not e.head}
            end
            page.details.Set({title = plain(current.title), sub = categoryName(current.category) .. "  \194\183  " .. string.format(A.L("forumReplies"), current.replies),
                glyph = "icon-talk", color = "text", blocks = blocks})
        else
            page.details.Empty(A.L("forumWelcome"), A.L(query ~= "" and "forumNoResults" or info.total == 0 and "forumEmptyHelp" or "forumPickHelp"))
        end
    end
end

function A.BuildForumPage(host, k)
    if A.HubKit and A.HubKit.Ready(host) then return buildHub(host, k) end
    page = host; A.forumPage = host
    local C = k.C
    k.PageHeader(page, "community")
    page.category, page.chips, page.query = "", {}, ""
    for _, id in ipairs({"", unpack(A.ForumCategories())}) do
        local chip = k.Chip(page, function() page.category = id; page.threadId = nil; A.RefreshUI() end)
        chip.categoryId = id; page.chips[#page.chips + 1] = chip
    end
    page.newButton = k.Button(page, "forumNew", 140, "primary", function() A.ForumOpenCompose({category = page.category ~= "" and page.category or "general"}) end)
    page.newButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -60)
    page.search = k.SearchBox(page, 240, function(value)
        if value~=page.query then page.query=value;A.RefreshUI() end
    end)
    page.clearSearch = k.Button(page,"forumClearSearch",76,"ghost",function()
        page.search:SetText("");page.query="";A.RefreshUI()
    end)
    page.info = k.label(page, 10, C.mist); page.info:SetWordWrap(false)
    page.book = k.Book(page, 112)
    page.measure = k.label(page,13,C.text);page.measure:Hide()
    page.metaMeasure = k.label(page,10,C.mist);page.metaMeasure:Hide()
    page.listTitle=k.label(page.book.index,12,C.bright or C.gold);page.listTitle:SetPoint("TOPLEFT",14,-14);page.listTitle:SetPoint("TOPRIGHT",-14,-14)
    page.list = k.ListView(page.book.index, 8); page.list:ClearAllPoints(); page.list:SetPoint("TOPLEFT", 6, -42); page.list:SetPoint("BOTTOMRIGHT", -10, 6)
    page.reading = CreateFrame("Frame",nil,page.book.paper);page.reading:SetAllPoints(page.book.paper)
    k.fill(page.reading,C.well or C.side,1);k.outline(page.reading,C.line)
    page.doc = forumDocument(page.reading,k)
    -- thread titles need more room than the default index of a book
    page.book.onLayout = function() page.book.index:SetWidth(math.max(190, math.min(300, (tonumber(page.book:GetWidth()) or 640) * 0.4))) end
    page.book.onLayout()

    function page.Refresh()
        local info = A.ForumInfo()
        page.title:SetText(A.L("community")); page.subtitle:SetText(A.L("sub_community"))
        for _, chip in ipairs(page.chips) do
            local id = chip.categoryId
            local count = id == "" and info.total or info.counts[id] or 0
            chip.SetLabel(A.L(id == "" and "forumAll" or "forumCatShort_" .. id) .. (count > 0 and ("  " .. count) or ""))
            chip.SetOn(page.category == id)
        end
        page.newButton.text:SetText(A.L("forumNew"))
        local rows = layoutChips(page)
        local searchTop = 62 + (rows + 1) * 30+6
        page.listTitle:SetText(page.category=="" and A.L("forumAll") or categoryName(page.category))
        page.search.hint:SetText(A.L("forumSearch"));page.clearSearch.text:SetText(A.L("forumClearSearch"))
        page.search:ClearAllPoints();page.search:SetPoint("TOPLEFT",page,"TOPLEFT",0,-searchTop)
        page.search:SetWidth(math.max(90,math.min(270,(tonumber(page:GetWidth()) or 600)-88)))
        page.clearSearch:ClearAllPoints();page.clearSearch:SetPoint("LEFT",page.search,"RIGHT",8,0)
        local infoTop = searchTop + 34
        page.info:ClearAllPoints(); page.info:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -infoTop); page.info:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -infoTop)
        page.info:SetText(infoLine(info))
        page.book:ClearAllPoints(); page.book:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(infoTop + 18)); page.book:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

        local query=searchFold((page.query or ""):match("^%s*(.-)%s*$"))
        local threads = {}
        for _,thread in ipairs(A.ForumThreads(page.category)) do if matchesSearch(thread,query) then threads[#threads+1]=thread end end
        local current
        for _, thread in ipairs(threads) do if thread.id == page.threadId then current = thread end end
        if not current and page.newest and query=="" then for _, thread in ipairs(A.ForumThreads()) do if thread.id == page.threadId then current = thread end end end
        current = current or threads[1]
        page.threadId = current and current.id or nil
        local items = {}
        for _, thread in ipairs(threads) do
            local id = thread.id
            local indexWidth=tonumber(page.book.index:GetWidth()) or 245
            if indexWidth<150 then indexWidth=245 end -- not laid out yet
            indexWidth=math.max(45,indexWidth-86)
            local author=plain(thread.author)
            local meta=(thread.pending and (A.L("forumPending") .. "  ·  ") or "") .. author .. "  ·  " .. string.format(A.L("forumRepliesShort"), thread.replies)
            page.metaMeasure:SetText(meta)
            if (page.metaMeasure:GetStringWidth() or 0)>indexWidth then meta=author end
            items[#items + 1] = {title = fitIndex((thread.pinned and "* " or "") .. plain(thread.title),indexWidth,page.measure), titleColor = id == page.threadId and k.C.gold or nil,
                sub = fitIndex(meta,indexWidth,page.metaMeasure),
                class = thread.classId, icon = k.ICON.community,
                onClick = function() page.threadId = id; A.RefreshUI() end}
        end
        page.list.SetItems(items, A.L(query~="" and "forumNoResults" or info.total == 0 and "forumNoData" or "forumNoThreads"))
        if current then
            local meta = categoryName(current.category) .. "  ·  " .. string.format(A.L("forumReplies"), current.replies)
            page.doc.Set({key = current.id, title = plain(current.title), subtitle = meta, entries = postEntries(current)})
        else
            local open = {text = A.L("forumNew"), size = 12, onClick = function() A.ForumOpenCompose({category = page.category ~= "" and page.category or "general"}) end}
            page.doc.Set({key = "welcome", title = A.L("forumWelcome"), subtitle = infoLine(info), entries = {{text = A.L(query~="" and "forumNoResults" or info.total == 0 and "forumEmptyHelp" or "forumPickHelp")}, open}})
        end
    end
end

-- ---------------------------------------------------------------- texts
local text = {
    en = {
        webfacts = "Website facts", sub_webfacts = "Sample of public facts from the website, stored separately from your own observations. Search by name or ID.",
        community = "Community", sub_community = "Forum shared with the website. Public posts under your full character name.",
        forumAll = "All", forumNew = "New thread", forumPost = "Post", forumCancel = "Cancel", forumSearch = "Search cached forum", forumClearSearch = "Clear", forumNoResults = "No matching threads in the saved forum.",
        forumCatShort_general = "General", forumCatShort_dungeons = "Dungeons", forumCatShort_professions = "Professions", forumCatShort_trading = "Trading", forumCatShort_guilds = "Guilds", forumCatShort_feedback = "Feedback",
        forumCat_general = "General", forumCat_dungeons = "Dungeons and raids", forumCat_professions = "Professions", forumCat_trading = "Trading", forumCat_guilds = "Guilds and groups", forumCat_feedback = "Bugs and feedback",
        forumReplies = "%d replies", forumRepliesShort = "%d repl.", forumFromWeb = "website", forumFromGame = "game", forumPending = "waiting to be sent", forumInReplyTo = "In reply to %s", forumReplyTo = "Reply to %s",
        forumNewTitle = "New thread", forumReplyTitle = "Reply", forumThreadTitle = "Title", forumThreadBody = "Text",
        forumReplyingTo = "Replying to %s: %s", forumReplyingThread = "Replying in: %s",
        forumPublicNote = "Public: posted on the Evertally website as %s. It reaches the website when the Evertally app is running and the game saves its files (/reload or logout).",
        forumQueued = "Saved. It is sent to the website when the game saves its files (/reload or logout) and the Evertally app is running.",
        forumCopyFrom = "Forum copy from %s", forumNoCopy = "No forum data from the website yet", forumWaiting = "%d waiting to be sent",
        forumNoData = "No threads yet. Start the first one, or run the Evertally app and /reload to load the website's forum.", forumNoThreads = "No threads in this category yet.",
        forumWelcome = "Evertally forum", forumEmptyHelp = "There is nothing here yet. Start a thread with the New thread button. To read what others wrote on the website, run the Evertally desktop app (paired with your account) and type /reload: it writes the forum next to the addon and the game loads it.",
        forumPickHelp = "Choose a thread on the left to read it, or start a new one.",
        forumAgoHours = "%d h ago", forumAgoDays = "%d d ago",
    },
    cs = {
        webfacts = "Fakta z webu", sub_webfacts = "Vzorek veřejných faktů z webu uložený odděleně od tvých pozorování. Hledej podle názvu nebo ID.",
        community = "Komunita", sub_community = "Fórum sdílené s webem. Veřejné příspěvky pod celým jménem postavy.",
        forumAll = "Vše", forumNew = "Nové vlákno", forumPost = "Odeslat", forumCancel = "Zrušit", forumSearch = "Hledat v uloženém fóru", forumClearSearch = "Vymazat", forumNoResults = "V uloženém fóru nejsou žádná odpovídající vlákna.",
        forumCatShort_general = "Obecné", forumCatShort_dungeons = "Dungeony", forumCatShort_professions = "Profese", forumCatShort_trading = "Obchod", forumCatShort_guilds = "Cechy", forumCatShort_feedback = "Nápady",
        forumCat_general = "Obecné", forumCat_dungeons = "Dungeony a raidy", forumCat_professions = "Profese", forumCat_trading = "Obchod", forumCat_guilds = "Cechy a skupiny", forumCat_feedback = "Chyby a nápady",
        forumReplies = "odpovědí: %d", forumRepliesShort = "odp. %d", forumFromWeb = "web", forumFromGame = "hra", forumPending = "čeká na odeslání", forumInReplyTo = "Odpověď pro %s", forumReplyTo = "Odpovědět: %s",
        forumNewTitle = "Nové vlákno", forumReplyTitle = "Odpověď", forumThreadTitle = "Název", forumThreadBody = "Text",
        forumReplyingTo = "Odpovídáš hráči %s: %s", forumReplyingThread = "Odpovídáš ve vláknu: %s",
        forumPublicNote = "Veřejné: zveřejní se na webu Evertally jako %s. Na web se dostane, když běží aplikace Evertally a hra uloží své soubory (/reload nebo odhlášení).",
        forumQueued = "Uloženo. Na web se odešle, až hra uloží své soubory (/reload nebo odhlášení) a poběží aplikace Evertally.",
        forumCopyFrom = "Kopie fóra z %s", forumNoCopy = "Zatím žádná data fóra z webu", forumWaiting = "Čeká na odeslání: %d",
        forumNoData = "Zatím žádná vlákna. Začni první, nebo spusť aplikaci Evertally a dej /reload, ať se načte fórum z webu.", forumNoThreads = "V této kategorii zatím nejsou vlákna.",
        forumWelcome = "Fórum Evertally", forumEmptyHelp = "Zatím tu nic není. Vlákno založíš tlačítkem Nové vlákno. Aby ses dočetl, co napsali ostatní na webu, spusť desktopovou aplikaci Evertally (spárovanou s tvým účtem) a napiš /reload: zapíše fórum vedle addonu a hra ho načte.",
        forumPickHelp = "Vlevo vyber vlákno k přečtení, nebo založ nové.",
        forumAgoHours = "před %d h", forumAgoDays = "před %d d",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end
