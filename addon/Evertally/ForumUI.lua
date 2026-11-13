local _, A = ...
-- The Community page: the forum (Forum.lua) in the window's own stone, bronze and gold. Categories across the top, the threads of the
-- chosen category on the left page of a book and the open thread on parchment on the right, with a small writing window for new
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

-- ---------------------------------------------------------------- the writing window
local function ensureCompose()
    if compose then return compose end
    local k = K()
    local C = k.C
    local f = CreateFrame("Frame", "EvertallyForumCompose", UIParent)
    f:SetSize(520, 430); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    A.NativeFrame(f, C)
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", function() f:StartMoving() end); f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.title = k.label(f, 15, C.gold); f.title:SetPoint("TOPLEFT", 18, -16); f.title:SetWidth(484)
    f.quote = k.label(f, 11, C.mist); f.quote:SetPoint("TOPLEFT", 18, -44); f.quote:SetWidth(484); f.quote:SetHeight(30); f.quote:SetWordWrap(true); f.quote:SetJustifyV("TOP")
    f.chips = {}
    local previous
    for _, id in ipairs(A.ForumCategories()) do
        local chip = k.Chip(f, function() f.category = id; A.ForumRefreshCompose() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 5, 0) else chip:SetPoint("TOPLEFT", 18, -44) end
        chip.categoryId = id; f.chips[#f.chips + 1] = chip; previous = chip
    end
    f.titleLabel = k.label(f, 11, C.mist); f.titleLabel:SetPoint("TOPLEFT", 18, -82)
    f.titleBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); f.titleBox:SetHeight(26); f.titleBox:SetPoint("TOPLEFT", 22, -98); f.titleBox:SetPoint("TOPRIGHT", -18, -98)
    f.titleBox:SetAutoFocus(false); f.titleBox:SetMaxLetters(A.FORUM_LIMITS.title); f.titleBox:SetFont(FONT, 12, ""); k.trackFont(f.titleBox, 12)
    f.bodyLabel = k.label(f, 11, C.mist)
    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.body = CreateFrame("EditBox", nil, f.scroll)
    f.body:SetMultiLine(true); f.body:SetAutoFocus(false); f.body:SetFont(FONT, 12, ""); k.trackFont(f.body, 12)
    f.body:SetWidth(440); f.body:SetMaxLetters(A.FORUM_LIMITS.body)
    f.body:SetScript("OnEscapePressed", function() f:Hide() end)
    f.body:SetScript("OnTextChanged", function() A.ForumRefreshCompose() end)
    f.scroll:SetScrollChild(f.body)
    f.counter = k.label(f, 10, C.faint); f.counter:SetPoint("BOTTOMRIGHT", -18, 90); f.counter:SetJustifyH("RIGHT")
    f.status = k.label(f, 11, C.peach); f.status:SetPoint("BOTTOMLEFT", 18, 90); f.status:SetWidth(380)
    f.note = k.label(f, 10, C.faint); f.note:SetPoint("BOTTOMLEFT", 18, 54); f.note:SetWidth(484); f.note:SetHeight(28); f.note:SetWordWrap(true); f.note:SetJustifyV("TOP")
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
    local top = isThread and 134 or 82
    f.title:SetText(A.L(isThread and "forumNewTitle" or "forumReplyTitle"))
    f.quote:SetShown(not isThread); f.quote:SetText(f.quoteText or "")
    for _, chip in ipairs(f.chips) do chip:SetShown(isThread); chip.SetLabel(A.L("forumCatShort_" .. chip.categoryId)); chip.SetOn(f.category == chip.categoryId) end
    f.titleLabel:SetShown(isThread); f.titleLabel:SetText(A.L("forumThreadTitle")); f.titleBox:SetShown(isThread)
    f.bodyLabel:ClearAllPoints(); f.bodyLabel:SetPoint("TOPLEFT", 18, -(top - 16)); f.bodyLabel:SetText(A.L("forumThreadBody"))
    f.scroll:ClearAllPoints(); f.scroll:SetPoint("TOPLEFT", 18, -top); f.scroll:SetPoint("BOTTOMRIGHT", -38, 112)
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
    local muted = k.ParchmentText.mutedInk
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
        entries[#entries + 1] = {text = plain(post.body)}
        local postId = post.id
        entries[#entries + 1] = {text = string.format(A.L("forumReplyTo"), plain(post.author)), size = 10, color = muted, onClick = function() A.ForumOpenCompose({threadId = thread.id, replyTo = postId}) end}
    end
    return entries
end

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
        chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", p, "TOPLEFT", x, -(54 + row * 28))
        x = x + w + 6
    end
    return row
end

function A.BuildForumPage(host, k)
    page = host; A.forumPage = host
    local C = k.C
    k.PageHeader(page, "community")
    page.category, page.chips = "", {}
    for _, id in ipairs({"", unpack(A.ForumCategories())}) do
        local chip = k.Chip(page, function() page.category = id; page.threadId = nil; A.RefreshUI() end)
        chip.categoryId = id; page.chips[#page.chips + 1] = chip
    end
    page.newButton = k.Button(page, "forumNew", 140, "primary", function() A.ForumOpenCompose({category = page.category ~= "" and page.category or "general"}) end)
    page.newButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -50)
    page.info = k.label(page, 10, C.mist); page.info:SetWordWrap(false)
    page.book = k.Book(page, 112)
    page.list = k.ListView(page.book.index, 8); page.list:ClearAllPoints(); page.list:SetPoint("TOPLEFT", 6, -6); page.list:SetPoint("BOTTOMRIGHT", -10, 6)
    page.doc = k.Document(page.book.paper)
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
        local infoTop = 54 + (rows + 1) * 28
        page.info:ClearAllPoints(); page.info:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -infoTop); page.info:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -infoTop)
        page.info:SetText(infoLine(info))
        page.book:ClearAllPoints(); page.book:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(infoTop + 18)); page.book:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

        local threads = A.ForumThreads(page.category)
        local current
        for _, thread in ipairs(threads) do if thread.id == page.threadId then current = thread end end
        if not current and page.newest then for _, thread in ipairs(A.ForumThreads()) do if thread.id == page.threadId then current = thread end end end
        current = current or threads[1]
        page.threadId = current and current.id or nil
        local items = {}
        for _, thread in ipairs(threads) do
            local id = thread.id
            items[#items + 1] = {title = (thread.pinned and "* " or "") .. plain(thread.title), titleColor = id == page.threadId and k.C.gold or nil,
                sub = (thread.pending and (A.L("forumPending") .. "  ·  ") or "") .. plain(thread.author) .. "  ·  " .. string.format(A.L("forumRepliesShort"), thread.replies),
                class = thread.classId, icon = k.ICON.community,
                onClick = function() page.threadId = id; A.RefreshUI() end}
        end
        page.list.SetItems(items, A.L(info.total == 0 and "forumNoData" or "forumNoThreads"))
        if current then
            local meta = categoryName(current.category) .. "  ·  " .. string.format(A.L("forumReplies"), current.replies)
            page.doc.Set({key = current.id, title = plain(current.title), subtitle = meta, entries = postEntries(current)})
        else
            local open = {text = A.L("forumNew"), size = 12, onClick = function() A.ForumOpenCompose({category = page.category ~= "" and page.category or "general"}) end}
            page.doc.Set({key = "welcome", title = A.L("forumWelcome"), subtitle = infoLine(info), entries = {{text = A.L(info.total == 0 and "forumEmptyHelp" or "forumPickHelp")}, open}})
        end
    end
end

-- ---------------------------------------------------------------- texts
local text = {
    en = {
        webfacts = "Website facts", sub_webfacts = "Sample of public facts from the website, stored separately from your own observations. Search by name or ID.",
        community = "Community", sub_community = "Forum shared with the website. Public posts under your full character name.",
        forumAll = "All", forumNew = "New thread", forumPost = "Post", forumCancel = "Cancel",
        forumCatShort_general = "General", forumCatShort_dungeons = "Dungeons", forumCatShort_professions = "Professions", forumCatShort_trading = "Trading", forumCatShort_guilds = "Guilds", forumCatShort_feedback = "Feedback",
        forumCat_general = "General", forumCat_dungeons = "Dungeons and raids", forumCat_professions = "Professions", forumCat_trading = "Trading", forumCat_guilds = "Guilds and groups", forumCat_feedback = "Bugs and feedback",
        forumReplies = "%d replies", forumRepliesShort = "%d repl.", forumFromWeb = "website", forumFromGame = "game", forumPending = "waiting to be sent", forumInReplyTo = "In reply to %s", forumReplyTo = "Reply to %s",
        forumNewTitle = "New thread", forumReplyTitle = "Reply", forumThreadTitle = "Title", forumThreadBody = "Text",
        forumReplyingTo = "Replying to %s: %s", forumReplyingThread = "Replying in: %s",
        forumPublicNote = "Public: posted on the Evertally website as %s. It reaches the website when the Evertally app is running and the game saves its files (/reload or logout).",
        forumQueued = "Saved. It is sent to the website when the game saves its files (/reload or logout) and the Evertally app is running.",
        forumCopyFrom = "Forum copy from %s", forumNoCopy = "No forum data from the website yet", forumWaiting = "%d waiting to be sent",
        forumNoData = "No threads yet. Start the first one, or run the Evertally app and /reload to load the website's forum.", forumNoThreads = "No threads in this category yet.",
        forumWelcome = "Evertally forum", forumEmptyHelp = "There is nothing here yet. Start a thread with the button below. To read what others wrote on the website, run the Evertally desktop app (paired with your account) and type /reload: it writes the forum next to the addon and the game loads it.",
        forumPickHelp = "Choose a thread on the left to read it, or start a new one.",
        forumAgoHours = "%d h ago", forumAgoDays = "%d d ago",
    },
    cs = {
        webfacts = "Fakta z webu", sub_webfacts = "Vzorek veřejných faktů z webu uložený odděleně od tvých pozorování. Hledej podle názvu nebo ID.",
        community = "Komunita", sub_community = "Fórum sdílené s webem. Veřejné příspěvky pod celým jménem postavy.",
        forumAll = "Vše", forumNew = "Nové vlákno", forumPost = "Odeslat", forumCancel = "Zrušit",
        forumCatShort_general = "Obecné", forumCatShort_dungeons = "Dungeony", forumCatShort_professions = "Profese", forumCatShort_trading = "Obchod", forumCatShort_guilds = "Cechy", forumCatShort_feedback = "Nápady",
        forumCat_general = "Obecné", forumCat_dungeons = "Dungeony a raidy", forumCat_professions = "Profese", forumCat_trading = "Obchod", forumCat_guilds = "Cechy a skupiny", forumCat_feedback = "Chyby a nápady",
        forumReplies = "odpovědí: %d", forumRepliesShort = "odp. %d", forumFromWeb = "web", forumFromGame = "hra", forumPending = "čeká na odeslání", forumInReplyTo = "Odpověď pro %s", forumReplyTo = "Odpovědět: %s",
        forumNewTitle = "Nové vlákno", forumReplyTitle = "Odpověď", forumThreadTitle = "Název", forumThreadBody = "Text",
        forumReplyingTo = "Odpovídáš hráči %s: %s", forumReplyingThread = "Odpovídáš ve vláknu: %s",
        forumPublicNote = "Veřejné: zveřejní se na webu Evertally jako %s. Na web se dostane, když běží aplikace Evertally a hra uloží své soubory (/reload nebo odhlášení).",
        forumQueued = "Uloženo. Na web se odešle, až hra uloží své soubory (/reload nebo odhlášení) a poběží aplikace Evertally.",
        forumCopyFrom = "Kopie fóra z %s", forumNoCopy = "Zatím žádná data fóra z webu", forumWaiting = "Čeká na odeslání: %d",
        forumNoData = "Zatím žádná vlákna. Začni první, nebo spusť aplikaci Evertally a dej /reload, ať se načte fórum z webu.", forumNoThreads = "V této kategorii zatím nejsou vlákna.",
        forumWelcome = "Fórum Evertally", forumEmptyHelp = "Zatím tu nic není. Vlákno založíš tlačítkem níže. Aby ses dočetl, co napsali ostatní na webu, spusť desktopovou aplikaci Evertally (spárovanou s tvým účtem) a napiš /reload: zapíše fórum vedle addonu a hra ho načte.",
        forumPickHelp = "Vlevo vyber vlákno k přečtení, nebo založ nové.",
        forumAgoHours = "před %d h", forumAgoDays = "před %d d",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end
