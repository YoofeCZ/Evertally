local _, A = ...
-- The forum of the Community page: categories, threads and replies shared with the Evertally website.
--
-- Data comes from two places, and nothing else:
--  * ForumData.lua (a data file the Evertally desktop app writes next to the addon from the website; the game loads it at login
--    or /reload). It is checked here again, field by field, before anything is shown: a damaged or hostile file shows nothing.
--  * what the player writes in game: it waits in EvertallyDB.forum.outbox, is shown at once as "waiting to be sent", and
--    travels to the website through the desktop app when the game saves its files (/reload or logout). When the website's
--    copy comes back with the same id, the outbox entry is dropped.
-- Authors are always the full character name "Name-Realm". The addon makes no request of its own.
local MAX_THREADS, MAX_POSTS, MAX_TITLE, MIN_TITLE, MAX_BODY = 60, 30, 80, 3, 800
local OUTBOX_MAX, OUTBOX_AGE, GAP = 40, 14 * 86400, 10
local CATEGORIES = {"general", "dungeons", "professions", "trading", "guilds", "feedback"}
local CATEGORY = {}
for _, id in ipairs(CATEGORIES) do CATEGORY[id] = true end
A.FORUM_LIMITS = {title = MAX_TITLE, body = MAX_BODY, titleMin = MIN_TITLE}

local rootKeys = {schemaVersion = true, generatedAt = true, count = true, threads = true}
local threadKeys = {id = true, category = true, title = true, author = true, classId = true, origin = true, pinned = true, createdAt = true, lastPostAt = true, replies = true, posts = true}
local postKeys = {id = true, author = true, classId = true, origin = true, body = true, createdAt = true, replyTo = true}

function A.ForumCategories() return CATEGORIES end

-- ---------------------------------------------------------------- checks
local function strict(value, keys)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do if type(key) ~= "string" or not keys[key] then return false end end
    return true
end
local function integer(value, low, high)
    return type(value) == "number" and value == value and value >= low and value <= high and value == math.floor(value)
end
local function validId(value) return type(value) == "string" and #value >= 8 and #value <= 40 and value:find("^[%w_%-]+$") ~= nil end
-- Lua 5.1 has no utf8 library: reject truncated and overlong sequences, surrogates and bytes outside Unicode.
local function validUtf8(value)
    local index = 1
    while index <= #value do
        local byte = value:byte(index)
        local length = byte < 128 and 1 or byte >= 194 and byte <= 223 and 2 or byte >= 224 and byte <= 239 and 3 or byte >= 240 and byte <= 244 and 4
        if not length or index + length - 1 > #value then return false end
        for offset = 1, length - 1 do
            local continuation = value:byte(index + offset)
            if continuation < 128 or continuation > 191 then return false end
        end
        local second = value:byte(index + 1)
        if (byte == 224 and second < 160) or (byte == 237 and second > 159) or (byte == 240 and second < 144) or (byte == 244 and second > 143) then return false end
        index = index + length
    end
    return true
end
local function chars(value)
    local n = 0
    for _ in value:gmatch("[^\128-\191]") do n = n + 1 end
    return n
end
-- Text that is allowed on screen: no control characters (a new line only in a body) and well-formed UTF-8. "|" is allowed and is doubled when drawn.
local function validText(value, maxChars, lines)
    if type(value) ~= "string" or #value < 1 or #value > maxChars * 4 or not validUtf8(value) or chars(value) > maxChars then return false end
    if value:find(lines and "[%z\1-\9\11-\31\127]" or "[%z\1-\31\127]") then return false end
    return value:find("%S") ~= nil
end
-- What the player typed, made safe: control characters become blanks, blank runs and empty lines are folded, the length is cut.
local function utf8Cut(value, maxChars)
    local count, index = 0, 1
    while index <= #value do
        local byte = value:byte(index)
        local length = byte < 128 and 1 or byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 1
        count = count + 1
        if count > maxChars then return value:sub(1, index - 1) end
        index = index + length
    end
    return value
end
local function typed(value, maxChars, lines)
    value = A.Text(value, maxChars * 4 + 8)
    if not value then return "" end
    value = value:gsub("\r\n?", "\n")
    value = value:gsub(lines and "[%z\1-\9\11-\31\127]" or "[%z\1-\31\127]", " ")
    if lines then
        value = value:gsub("[ \t]+", " "):gsub(" ?\n ?", "\n"):gsub("\n\n\n+", "\n\n")
    else
        value = value:gsub("%s+", " ")
    end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = utf8Cut(value, maxChars)
    -- a cut inside a character leaves an invalid tail
    while #value > 0 and not validUtf8(value) do value = value:sub(1, -2) end
    return value
end
A.ForumTyped = typed

-- ---------------------------------------------------------------- the website's copy
local function cleanPost(entry, now)
    if not strict(entry, postKeys) or not validId(entry.id) or not validText(entry.author, 80, false) or not validText(entry.body, MAX_BODY, true) then return nil end
    if not integer(entry.createdAt, 0, now + 86400) then return nil end
    if entry.classId ~= nil and not integer(entry.classId, 1, 100) then return nil end
    if entry.replyTo ~= nil and not validId(entry.replyTo) then return nil end
    if entry.origin ~= "web" and entry.origin ~= "game" then return nil end
    return {id = entry.id, author = entry.author, classId = entry.classId, origin = entry.origin, body = entry.body, createdAt = entry.createdAt, replyTo = entry.replyTo}
end
local function cleanThread(entry, now)
    if not strict(entry, threadKeys) or not validId(entry.id) or not CATEGORY[entry.category] or not validText(entry.title, MAX_TITLE, false) or not validText(entry.author, 80, false) then return nil end
    if not integer(entry.createdAt, 0, now + 86400) or not integer(entry.lastPostAt, 0, now + 86400) or not integer(entry.replies or 0, 0, 1000000) then return nil end
    if entry.classId ~= nil and not integer(entry.classId, 1, 100) then return nil end
    if entry.origin ~= "web" and entry.origin ~= "game" then return nil end
    if type(entry.pinned) ~= "boolean" or type(entry.posts) ~= "table" then return nil end
    local posts, length, highest = {}, 0, 0
    for key in pairs(entry.posts) do
        if not integer(key, 1, MAX_POSTS) then return nil end
        length, highest = length + 1, math.max(highest, key)
    end
    if length ~= highest or length < 1 then return nil end
    local seen = {}
    for index = 1, length do
        local post = cleanPost(entry.posts[index], now)
        if not post or seen[post.id] then return nil end
        seen[post.id] = true;posts[index] = post
    end
    return {id = entry.id, category = entry.category, title = entry.title, author = entry.author, classId = entry.classId, origin = entry.origin, pinned = entry.pinned,
        createdAt = entry.createdAt, lastPostAt = entry.lastPostAt, replies = entry.replies or (length - 1), posts = posts}
end
-- A thread that does not pass is left out; the rest still shows. A file that is not a forum at all shows nothing.
local function validate(data)
    if not strict(data, rootKeys) or data.schemaVersion ~= 1 or type(data.threads) ~= "table" then return nil, "forumInvalid" end
    local now = A.Now()
    if not integer(data.generatedAt, 0, now + 86400) then return nil, "forumInvalid" end
    local threads, seen, dropped = {}, {}, 0
    local length = 0
    for key in pairs(data.threads) do
        if not integer(key, 1, MAX_THREADS) then return nil, "forumInvalid" end
        length = math.max(length, key)
    end
    for index = 1, length do
        local thread = cleanThread(data.threads[index], now)
        if thread and not seen[thread.id] then seen[thread.id] = true;threads[#threads + 1] = thread else dropped = dropped + 1 end
    end
    return {generatedAt = data.generatedAt, threads = threads, dropped = dropped}
end
local cache = {raw = nil, clean = nil, err = nil}
--- The website's forum as the game loaded it, checked: {generatedAt, threads, dropped}, or nil when there is no data (or nil, "forumInvalid").
function A.ForumSnapshot()
    local raw = rawget(_G, "EvertallyForumData")
    if raw == nil then return nil end
    if cache.raw ~= raw or cache.stamp ~= A.Now() - A.Now() % 60 then
        local ok, clean, err = pcall(validate, raw)
        cache.raw, cache.stamp = raw, A.Now() - A.Now() % 60
        if ok then cache.clean, cache.err = clean, err else cache.clean, cache.err = nil, "forumInvalid" end
    end
    return cache.clean, cache.err
end
function A.ForumResetCache() cache = {} end

-- ---------------------------------------------------------------- what the player wrote
local function store()
    local db = A.db
    if not db then return nil end
    if type(db.forum) ~= "table" then db.forum = {} end
    if type(db.forum.outbox) ~= "table" then db.forum.outbox = {} end
    return db.forum
end
local function b36(n)
    n = math.floor(n);if n <= 0 then return "0" end
    local digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", {}
    while n > 0 do local d = n % 36;table.insert(out, 1, digits:sub(d + 1, d + 1));n = math.floor(n / 36) end
    return table.concat(out)
end
local function newId()
    local id = string.format("g%s%08x%06x", b36(A.Now()), math.random(0, 2147483646), math.random(0, 16777215))
    return id:sub(1, 40)
end
--- The full name of the current character, "Name-Realm", and its class.
function A.ForumAuthor()
    local c = A.Character()
    if not c then return nil end
    local name = typed(c.name, 40, false)
    local realm = typed(c.realm, 40, false)
    if name == "" then return nil end
    return realm ~= "" and (name .. "-" .. realm) or name, c.classId
end

local function outboxClean(entry)
    return type(entry) == "table" and validId(entry.id) and (entry.kind == "thread" or entry.kind == "post")
        and validText(entry.body, MAX_BODY, true) and validText(entry.author, 80, false) and integer(entry.createdAt, 0, 253402300799)
        and (entry.kind == "post" and validId(entry.threadId) or entry.kind == "thread" and CATEGORY[entry.category] and validText(entry.title, MAX_TITLE, false))
end
-- Entries the website already has, entries that are damaged and entries that have waited too long leave the outbox.
function A.ForumPrune()
    local forum = store()
    if not forum then return 0 end
    local snapshot = A.ForumSnapshot()
    local known = {}
    for _, thread in ipairs(snapshot and snapshot.threads or {}) do
        known[thread.id] = true
        for _, post in ipairs(thread.posts) do known[post.id] = true end
    end
    local now, kept, removed = A.Now(), {}, 0
    for _, entry in ipairs(forum.outbox) do
        if outboxClean(entry) and not known[entry.id] and now - entry.createdAt < OUTBOX_AGE and #kept < OUTBOX_MAX then kept[#kept + 1] = entry else removed = removed + 1 end
    end
    forum.outbox = kept
    return removed
end
function A.ForumOutbox() local forum = store();return forum and forum.outbox or {} end

-- ---------------------------------------------------------------- reading: the website's copy and the player's own pending posts together
local function byOldest(a, b) if a.createdAt ~= b.createdAt then return a.createdAt < b.createdAt end return (a.order or 0) < (b.order or 0) end
local function merged()
    local snapshot = A.ForumSnapshot()
    local threads, byId = {}, {}
    for _, source in ipairs(snapshot and snapshot.threads or {}) do
        local thread = {id = source.id, category = source.category, title = source.title, author = source.author, classId = source.classId, origin = source.origin, pinned = source.pinned,
            createdAt = source.createdAt, lastPostAt = source.lastPostAt, replies = source.replies, posts = {}, ids = {}}
        for i, post in ipairs(source.posts) do thread.posts[i] = {id = post.id, author = post.author, classId = post.classId, origin = post.origin, body = post.body, createdAt = post.createdAt, replyTo = post.replyTo, order = i};thread.ids[post.id] = true end
        threads[#threads + 1] = thread;byId[thread.id] = thread
    end
    local forum = store()
    local outbox = forum and forum.outbox or {}
    for i, entry in ipairs(outbox) do
        if outboxClean(entry) and entry.kind == "thread" and not byId[entry.id] then
            local thread = {id = entry.id, category = entry.category, title = entry.title, author = entry.author, classId = entry.classId, origin = "game", pinned = false,
                createdAt = entry.createdAt, lastPostAt = entry.createdAt, replies = 0, pending = true, ids = {[entry.id] = true},
                posts = {{id = entry.id, author = entry.author, classId = entry.classId, origin = "game", body = entry.body, createdAt = entry.createdAt, pending = true, order = 0}}}
            threads[#threads + 1] = thread;byId[thread.id] = thread
        end
    end
    for i, entry in ipairs(outbox) do
        local thread = outboxClean(entry) and entry.kind == "post" and byId[entry.threadId]
        if thread and not thread.ids[entry.id] then
            thread.ids[entry.id] = true
            thread.posts[#thread.posts + 1] = {id = entry.id, author = entry.author, classId = entry.classId, origin = "game", body = entry.body, createdAt = entry.createdAt, replyTo = entry.replyTo, pending = true, order = 1000 + i}
            thread.replies = thread.replies + 1;thread.pendingReplies = (thread.pendingReplies or 0) + 1
            thread.lastPostAt = math.max(thread.lastPostAt, entry.createdAt)
        end
    end
    for _, thread in ipairs(threads) do
        -- the opening post first, then oldest to newest
        table.sort(thread.posts, function(a, b)
            local aOpen, bOpen = a.id == thread.id, b.id == thread.id
            if aOpen ~= bOpen then return aOpen end
            return byOldest(a, b)
        end)
    end
    table.sort(threads, function(a, b)
        if a.pinned ~= b.pinned then return a.pinned end
        if a.lastPostAt ~= b.lastPostAt then return a.lastPostAt > b.lastPostAt end
        return a.id < b.id
    end)
    return threads, byId
end
--- Threads of one category (all when `category` is nil or empty), pinned first and then the most recently active.
function A.ForumThreads(category)
    local all = merged()
    if not category or category == "" then return all end
    local out = {}
    for _, thread in ipairs(all) do if thread.category == category then out[#out + 1] = thread end end
    return out
end
function A.ForumThread(id)
    local _, byId = merged()
    return byId[id]
end
--- {threads = per category, total, pending, generatedAt, invalid}: what the page shows about the state of the forum.
function A.ForumInfo()
    local snapshot, err = A.ForumSnapshot()
    local counts, total = {}, 0
    for _, thread in ipairs(A.ForumThreads()) do counts[thread.category] = (counts[thread.category] or 0) + 1;total = total + 1 end
    return {counts = counts, total = total, pending = #A.ForumOutbox(), generatedAt = snapshot and snapshot.generatedAt or nil, invalid = err == "forumInvalid", dropped = snapshot and snapshot.dropped or 0}
end

-- ---------------------------------------------------------------- writing
local lastWrite = -1e9
local function guard()
    if not A.db then return nil, "no_db" end
    if A.Call(InCombatLockdown) == true then return nil, "combat" end
    local author, classId = A.ForumAuthor()
    if not author then return nil, "no_character" end
    if A.Monotonic() - lastWrite < GAP then return nil, "too_fast" end
    local forum = store()
    if #forum.outbox >= OUTBOX_MAX then return nil, "outbox_full" end
    return author, classId
end
--- Starts a thread. Returns true and the id, or false and a reason (forumErr_<reason> is its text).
function A.ForumNewThread(category, title, body)
    if not CATEGORY[category] then return false, "category" end
    title, body = typed(title, MAX_TITLE, false), typed(body, MAX_BODY, true)
    if chars(title) < MIN_TITLE then return false, "title" end
    if body == "" then return false, "body" end
    local author, classId = guard()
    if not author then return false, classId end
    local id = newId()
    local forum = store()
    forum.outbox[#forum.outbox + 1] = {kind = "thread", id = id, category = category, title = title, body = body, author = author, classId = classId, createdAt = A.Now()}
    lastWrite = A.Monotonic()
    return true, id
end
--- Answers a thread, optionally a particular post of it. `replyTo` that is not in the thread is dropped.
function A.ForumReply(threadId, body, replyTo)
    local thread = A.ForumThread(threadId)
    if not thread then return false, "thread" end
    body = typed(body, MAX_BODY, true)
    if body == "" then return false, "body" end
    local author, classId = guard()
    if not author then return false, classId end
    local target
    if replyTo and replyTo ~= thread.id then for _, post in ipairs(thread.posts) do if post.id == replyTo then target = replyTo end end end
    local id = newId()
    local forum = store()
    forum.outbox[#forum.outbox + 1] = {kind = "post", id = id, threadId = thread.id, replyTo = target, body = body, author = author, classId = classId, createdAt = A.Now()}
    lastWrite = A.Monotonic()
    return true, id
end
function A.ForumResetThrottle() lastWrite = -1e9 end

A.On("PLAYER_LOGIN", function() pcall(A.ForumPrune) end)

-- ---------------------------------------------------------------- texts
local text = {
    en = {
        forumErr_no_db = "The addon is not ready yet.", forumErr_combat = "You cannot post while in combat.", forumErr_no_character = "No character is known yet.",
        forumErr_too_fast = "Wait a few seconds between posts.", forumErr_outbox_full = "Too many posts are waiting to be sent. Run Evertally Sync and /reload first.",
        forumErr_category = "Choose a category.", forumErr_title = "The title needs at least 3 characters.", forumErr_body = "Write something first.", forumErr_thread = "This thread is no longer in the game's copy of the forum.",
        forumInvalid = "The forum data file is damaged and was ignored.",
    },
    cs = {
        forumErr_no_db = "Addon ještě není připravený.", forumErr_combat = "V boji nelze psát.", forumErr_no_character = "Postava zatím není známá.",
        forumErr_too_fast = "Mezi příspěvky chvíli počkej.", forumErr_outbox_full = "Čeká příliš mnoho příspěvků na odeslání. Nejdřív spusť Evertally Sync a dej /reload.",
        forumErr_category = "Vyber kategorii.", forumErr_title = "Název musí mít aspoň 3 znaky.", forumErr_body = "Nejdřív něco napiš.", forumErr_thread = "Toto vlákno už v herní kopii fóra není.",
        forumInvalid = "Datový soubor fóra je poškozený a byl ignorován.",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end
