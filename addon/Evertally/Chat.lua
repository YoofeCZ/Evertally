local _, A = ...
-- A separate chat window: every whisper partner is its own conversation, plus rooms the player creates or joins.
-- Rooms are ordinary custom chat channels: the server keeps membership and passwords, players without
-- Evertally can take part, and a room survives a relog. History stays in memory for the session only:
-- private messages are never written to SavedVariables, which the sync app reads.
local C = {conversations = {}, order = {}}
A.Chat = C
local words = {
    en = {chatEnabled = "Evertally chat (button next to Social, window with whispers and rooms)",
        chatRedirect = "…show whispers and rooms only there, not in the main chat",
        chatTitle = "Evertally chat", chatOpen = "Open the Evertally chat", chatWhispers = "Whispers and rooms",
        chatTarget = "Name or room…", chatWhisper = "Whisper", chatRoom = "Room", chatLeave = "Leave room",
        chatList = "Conversations", chatMessageHint = "Write a message… Enter sends", chatSend = "Send",
        chatKindWhisper = "Private conversation", chatKindRoom = "Room · a chat channel, also open to players without Evertally",
        chatCloseConv = "Close conversation", chatEmpty = "No conversations yet. Whispers appear here; type a name to start one.",
        chatNoConv = "Pick a conversation on the left.",
        chatRoomHint = "Room: the name (letters and digits) and an optional password after a space. The first one in creates it.",
        chatBadRoom = "Room names use 2–24 letters or digits and cannot be a game channel.",
        chatBadName = "Type a character name.", chatNotJoined = "You are not in this room yet; wait a moment or join it again.",
        chatJoined = "You joined the room.", chatLeft = "You left the room.", chatWrongPassword = "Wrong room password.",
        chatBanned = "You are banned from this room.", chatSendFailed = "The game did not accept the message.", chatUnread = "unread",
        chatNoApi = "This client cannot join chat channels.", chatTooMany = "The game allows only ten chat channels at once; leave one first."},
    cs = {chatEnabled = "Evertally chat (tlačítko u Social, okno s whispery a místnostmi)",
        chatRedirect = "…whispery a místnosti ukazovat jen tam, ne v hlavním chatu",
        chatTitle = "Evertally chat", chatOpen = "Otevřít Evertally chat", chatWhispers = "Whispery a místnosti",
        chatTarget = "Jméno nebo místnost…", chatWhisper = "Whisper", chatRoom = "Místnost", chatLeave = "Opustit místnost",
        chatList = "Konverzace", chatMessageHint = "Napiš zprávu… Enter odešle", chatSend = "Odeslat",
        chatKindWhisper = "Soukromá konverzace", chatKindRoom = "Místnost · chatový kanál, přidat se může i hráč bez Evertally",
        chatCloseConv = "Zavřít konverzaci", chatEmpty = "Zatím žádné konverzace. Whispery se objeví tady; konverzaci začneš napsáním jména.",
        chatNoConv = "Vyber konverzaci vlevo.",
        chatRoomHint = "Místnost: název (písmena a číslice) a za mezerou případně heslo. Kdo vejde první, ten ji založí.",
        chatBadRoom = "Název místnosti má 2–24 písmen nebo číslic a nesmí to být herní kanál.",
        chatBadName = "Napiš jméno postavy.", chatNotJoined = "V místnosti ještě nejsi; chvíli počkej nebo se připoj znovu.",
        chatJoined = "Připojil ses do místnosti.", chatLeft = "Opustil jsi místnost.", chatWrongPassword = "Špatné heslo místnosti.",
        chatBanned = "V této místnosti máš zákaz.", chatSendFailed = "Hra zprávu nepřijala.", chatUnread = "nepřečtené",
        chatNoApi = "Tento klient neumí vstoupit do chatových kanálů.", chatTooMany = "Hra dovolí najednou jen deset chatových kanálů; nejdřív nějaký opusť."},
}
local more = {
    en = {chatTabRooms = "Rooms", chatTabWhispers = "Whispers", chatCatSupport = "Support", chatCatDefault = "General",
        chatCatLanguages = "Languages", chatCatCustom = "Custom", chatBrowse = "Browse and create rooms",
        chatBrowseTitle = "Custom rooms", chatBrowseHint = "Public rooms that players with Evertally are in right now. Private rooms are not listed: join one by its name.",
        chatSearch = "Search a room…", chatNoPublic = "No public room has been seen yet. Lists arrive from other players within a few minutes.",
        chatJoin = "Join", chatCreateTitle = "Create or join by name", chatRoomName = "Room name", chatPassword = "Password (optional)",
        chatPublic = "Public: listed for everyone", chatPrivate = "Private: only by name", chatCreate = "Create / join",
        chatShare = "Share", chatShareText = "Join my room #%s (Evertally chat → Rooms → Custom)", chatShared = "Shared in General.",
        chatSeenBy = "seen %d min ago", chatNotIn = "click to join", chatReserved = "This name belongs to a fixed room; pick it in the list.",
        chatNoGeneral = "Join General first; sharing posts there."},
    cs = {chatTabRooms = "Místnosti", chatTabWhispers = "Whispery", chatCatSupport = "Podpora", chatCatDefault = "Obecné",
        chatCatLanguages = "Jazyky", chatCatCustom = "Vlastní", chatBrowse = "Procházet a založit místnost",
        chatBrowseTitle = "Vlastní místnosti", chatBrowseHint = "Veřejné místnosti, ve kterých teď jsou hráči s Evertally. Soukromé se nezobrazují: vstoupíš do nich podle názvu.",
        chatSearch = "Hledat místnost…", chatNoPublic = "Zatím nebyla vidět žádná veřejná místnost. Seznam od ostatních hráčů dorazí během pár minut.",
        chatJoin = "Připojit", chatCreateTitle = "Založit nebo vstoupit podle názvu", chatRoomName = "Název místnosti", chatPassword = "Heslo (nepovinné)",
        chatPublic = "Veřejná: uvidí ji všichni", chatPrivate = "Soukromá: jen podle názvu", chatCreate = "Založit / vstoupit",
        chatShare = "Sdílet", chatShareText = "Pojďte do mé místnosti #%s (Evertally chat → Místnosti → Vlastní)", chatShared = "Sdíleno v Obecné.",
        chatSeenBy = "viděno před %d min", chatNotIn = "kliknutím vstoupíš", chatReserved = "Tento název patří pevné místnosti; vyber ji v seznamu.",
        chatNoGeneral = "Nejdřív vstup do místnosti General; sdílení se posílá tam."},
}
for lang, entries in pairs(more) do for key, value in pairs(entries) do words[lang][key] = value end end
for lang, entries in pairs(words) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local MAX_LINES, MAX_CONVERSATIONS, MAX_ROOMS = 300, 60, 12
-- Fixed rooms, grouped as the sidebar shows them. Channel names carry a prefix so they do not meet strangers' channels;
-- the label is what players read. Rooms marked auto are joined for everyone unless the player left them.
C.CATALOG = {
    {key = "support", title = "chatCatSupport", rooms = {{name = "Evertally", label = "Evertally", auto = true}}},
    {key = "default", title = "chatCatDefault", rooms = {{name = "EtGeneral", label = "General", auto = true}}},
    {key = "languages", title = "chatCatLanguages", rooms = {
        {name = "EtCestina", label = "Čeština"}, {name = "EtSlovencina", label = "Slovenčina"}, {name = "EtEnglish", label = "English"},
        {name = "EtDeutsch", label = "Deutsch"}, {name = "EtPolski", label = "Polski"}, {name = "EtFrancais", label = "Français"},
        {name = "EtEspanol", label = "Español"}, {name = "EtRusskiy", label = "Русский"}}},
}
local catalog = {}
for _, group in ipairs(C.CATALOG) do for _, room in ipairs(group.rooms) do room.group = group.key; catalog[room.name:lower()] = room end end
function C.CatalogRoom(name) return type(name) == "string" and catalog[name:lower()] or nil end
function C.Label(name) local room = C.CatalogRoom(name); return room and room.label or name end
local reserved = {general = true, trade = true, localdefense = true, worlddefense = true, lookingforgroup = true, guildrecruitment = true, services = true, newcomerchat = true, world = true}
local function text(v, max) v = A.Plain(v); if type(v) == "string" and v ~= "" then return v:sub(1, max or 255) end end

function C.Settings()
    if not A.db then return {rooms = {}} end
    local s = A.db.settings; if type(s.chat) ~= "table" then s.chat = {} end
    if type(s.chat.rooms) ~= "table" then s.chat.rooms = {} end
    if type(s.chat.left) ~= "table" then s.chat.left = {} end
    return s.chat
end
function C.Enabled() return A.db ~= nil and C.Settings().enabled ~= false and not (A.RequirementsReady and not A.RequirementsReady()) end
function C.Redirect() return C.Enabled() and C.Settings().redirect == true end
local function notify() if C.OnChanged then pcall(C.OnChanged) end end
function C.SetEnabled(on) C.Settings().enabled = on == true; notify() end
function C.SetRedirect(on) C.Settings().redirect = on == true; notify() end

-- "Bran", "Bran-Realm" and Forever's "Bran Realm" are one partner: the conversation key is the character name.
-- Only ASCII space and dash split it: %s and %c also match bytes inside UTF-8 letters such as Ř on some C libraries.
function C.NameKey(name) name = text(name, 80); return name and (name:match("^[^%- ]+") or name):lower() end
local function short(name) return name and (name:match("^[^%- ]+") or name) end

function C.Conversation(kind, id, display)
    local key = kind .. ":" .. id
    local conv = C.conversations[key]
    if not conv then
        conv = {key = key, kind = kind, id = id, name = display or id, lines = {}, unread = 0, updated = A.Monotonic()}
        C.conversations[key] = conv; table.insert(C.order, 1, key)
        while #C.order > MAX_CONVERSATIONS do local old = table.remove(C.order); C.conversations[old] = nil end
    end
    return conv
end
local function touch(conv)
    for i, key in ipairs(C.order) do if key == conv.key then table.remove(C.order, i); break end end
    table.insert(C.order, 1, conv.key); conv.updated = A.Monotonic()
end
function C.List(kind)
    local out = {}
    for _, key in ipairs(C.order) do local conv = C.conversations[key]; if not kind or conv.kind == kind then out[#out + 1] = conv end end
    return out
end
function C.Unread(kind) local n = 0; for _, conv in pairs(C.conversations) do if not kind or conv.kind == kind then n = n + conv.unread end end; return n end

function C.Add(conv, author, message, outgoing, system)
    local line = {at = A.Now(), author = author, text = message, out = outgoing == true, system = system == true}
    conv.lines[#conv.lines + 1] = line
    while #conv.lines > MAX_LINES do table.remove(conv.lines, 1) end
    local reading = C.IsReading and C.IsReading(conv)
    if not outgoing and not system and not reading then conv.unread = conv.unread + 1 end
    touch(conv)
    -- The open window appends the line itself; the full redraw that follows then finds nothing new.
    if C.OnLine then pcall(C.OnLine, conv, line) end
    notify()
    return line
end
function C.MarkRead(conv) if conv and conv.unread > 0 then conv.unread = 0; notify() end end
function C.Remove(conv)
    if not conv then return end
    C.conversations[conv.key] = nil
    for i, key in ipairs(C.order) do if key == conv.key then table.remove(C.order, i); break end end
    if C.selected == conv.key then C.selected = nil end
    notify()
end

function C.Whisper(name)
    local display = text(name, 80); if not display or display:find("[%z\1-\31\127|]") then return nil end
    local conv = C.Conversation("whisper", C.NameKey(display), short(display))
    if not conv.target or display:find("[%- ]") then conv.target = display end
    return conv
end

-- Rooms
function C.Rooms() return C.Settings().rooms end
function C.RoomKey(name) return text(name, 40) and name:lower() end
local function savedRoom(name)
    local key = C.RoomKey(name); if not key then return nil end
    for i, room in ipairs(C.Rooms()) do if room.name:lower() == key then return room, i end end
end
function C.IsRoom(name) return savedRoom(name) ~= nil end
function C.ParseRoom(input)
    input = text(input, 80); if not input then return nil end
    local name, password = input:match("^%s*(%S+)%s*(%S*)%s*$")
    if not name or not name:match("^%w+$") or #name < 2 or #name > 24 or reserved[name:lower()] or name:match("^%d+$") then return nil end
    return name, password ~= "" and password or nil
end
local function channelIndex(name)
    local id = A.Call(GetChannelName, name); id = A.Number(id); if id and id > 0 then return id end
end
-- public: true lists a custom room for everyone (see the directory below), false keeps it private, nil leaves it as it was.
-- A fixed room is joined by its own name only (C.JoinCatalog); its name cannot be taken for a custom room.
function C.JoinRoom(input, public, fixed)
    local name, password = C.ParseRoom(input); if not name then return false, "chatBadRoom" end
    if C.CatalogRoom(name) and not fixed then return false, "chatReserved" end
    local room = savedRoom(name)
    if not room then
        if #C.Rooms() >= MAX_ROOMS then return false, "chatTooMany" end
        room = {name = name}; table.insert(C.Rooms(), room)
    end
    if password then room.password = password end
    if public ~= nil and not fixed then room.public = public == true end
    C.Settings().left[name:lower()] = nil
    local join = JoinChannelByName or JoinTemporaryChannel
    if type(join) ~= "function" then return false, "chatNoApi" end
    -- No chat frame is given: the channel is not added to any Blizzard chat tab, the room lives in this window.
    if not channelIndex(room.name) then pcall(join, room.name, room.password) end
    local conv = C.Conversation("room", room.name:lower(), C.Label(room.name)); C.selected = conv.key
    if room.public and C.Announce then C.Announce(room) end
    notify()
    return true, conv
end
function C.JoinCatalog(name) local room = C.CatalogRoom(name); if not room then return false, "chatBadRoom" end; return C.JoinRoom(room.name, nil, true) end
function C.Joined(name) return savedRoom(name) ~= nil end
function C.LeaveRoom(name)
    local room, index = savedRoom(name); if not room then return false end
    table.remove(C.Rooms(), index)
    -- a fixed room the player leaves stays left, also after the next login
    if C.CatalogRoom(room.name) then C.Settings().left[room.name:lower()] = true end
    if type(LeaveChannelByName) == "function" then pcall(LeaveChannelByName, room.name) end
    C.Remove(C.conversations["room:" .. room.name:lower()])
    return true
end
function C.Rejoin()
    if not C.Enabled() then return 0 end
    local join = JoinChannelByName or JoinTemporaryChannel; if type(join) ~= "function" then return 0 end
    for _, group in ipairs(C.CATALOG) do
        for _, fixed in ipairs(group.rooms) do
            if fixed.auto and not C.Settings().left[fixed.name:lower()] and not savedRoom(fixed.name) then table.insert(C.Rooms(), {name = fixed.name}) end
        end
    end
    local n = 0
    for _, room in ipairs(C.Rooms()) do
        C.Conversation("room", room.name:lower(), C.Label(room.name))
        if not channelIndex(room.name) then pcall(join, room.name, room.password); n = n + 1 end
    end
    notify(); return n
end

-- Directory of public custom rooms. The game has no list of custom channels, so every Evertally client tells the others,
-- with an invisible addon message in the #Evertally room, which public rooms it is in. A room stays listed while
-- someone in it is online (announced every five minutes, forgotten after twenty). Private rooms are never announced.
local PREFIX, FORGET = "EvtlyRoom", 1200
C.directory = {}
function C.Announce(only)
    local id = channelIndex("Evertally")
    if not id or not C.Enabled() or not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then return 0 end
    local n = 0
    for _, room in ipairs(C.Rooms()) do
        if room.public and not C.CatalogRoom(room.name) and (not only or only == room) then
            if pcall(C_ChatInfo.SendAddonMessage, PREFIX, "R|1|" .. room.name, "CHANNEL", id) then n = n + 1 end
        end
    end
    return n
end
function C.OnAddon(prefix, message, _, sender)
    if text(prefix, 20) ~= PREFIX or not C.Enabled() then return end
    message = text(message, 60); local name = message and message:match("^R|1|(%w+)$")
    if not name or not C.ParseRoom(name) or C.CatalogRoom(name) then return end
    C.directory[name:lower()] = {name = name, seen = A.Now(), by = short(text(sender, 80))}
    notify()
end
function C.Directory(query)
    local now, out = A.Now(), {}
    query = text(query, 40); query = query and query:lower()
    for key, entry in pairs(C.directory) do
        if now - entry.seen > FORGET then C.directory[key] = nil
        elseif not query or key:find(query, 1, true) then out[#out + 1] = entry end
    end
    -- own public rooms are listed too, so the creator sees what others see
    for _, room in ipairs(C.Rooms()) do
        local key = room.name:lower()
        if room.public and not C.directory[key] and not C.CatalogRoom(room.name) and (not query or key:find(query, 1, true)) then
            out[#out + 1] = {name = room.name, seen = now, by = short(A.Text(A.Call(UnitName, "player"), 60))}
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end
-- Joining from the directory: the room is public, so this client keeps it listed as well.
function C.JoinPublic(name) return C.JoinRoom(name, true) end
-- Sharing posts an invitation into the General room, in the player's own click.
function C.Share(conv)
    if not conv or conv.kind ~= "room" or C.CatalogRoom(conv.id) then return false, "chatBadRoom" end
    local general = C.conversations["room:etgeneral"]
    if not general or not channelIndex("EtGeneral") then return false, "chatNoGeneral" end
    local ok = C.Send(general, string.format(A.L("chatShareText"), conv.name))
    return ok, ok and "chatShared" or "chatSendFailed"
end

-- Sending happens from the window's edit box, i.e. inside the key press that the game requires for chat.
local function send(message, kind, target)
    local fn = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(fn) ~= "function" then return false end
    return (pcall(fn, message, kind, nil, target))
end
function C.Send(conv, message)
    message = text(message, 255); if not conv or not message or not C.Enabled() then return false, "chatSendFailed" end
    message = message:gsub("[\r\n]", " ")
    if conv.kind == "whisper" then
        -- The echo arrives as CHAT_MSG_WHISPER_INFORM; adding the line here too would show it twice.
        local ok = send(message, "WHISPER", conv.target or conv.name); return ok, not ok and "chatSendFailed" or nil
    end
    -- a fixed room shows its label ("General"); the channel is its own name ("EtGeneral")
    local room = savedRoom(conv.id); if not room then return false, "chatNotJoined" end
    local id = channelIndex(room.name); if not id then return false, "chatNotJoined" end
    local ok = send(message, "CHANNEL", id); return ok, not ok and "chatSendFailed" or nil
end

-- Incoming
local function baseChannel(channelName, baseName)
    baseName = text(baseName, 60); if baseName then return baseName end
    channelName = text(channelName, 60); return channelName and (channelName:match("^%d+%.%s*(.+)$") or channelName)
end
function C.OnWhisper(message, sender, _, _, _, flags)
    if not C.Enabled() then return end
    message, sender = text(message, 4000), text(sender, 80); if not message or not sender then return end
    local conv = C.Whisper(sender); if not conv then return end
    conv.target = sender
    C.Add(conv, short(sender), message, false)
    if text(flags, 10) == "GM" then conv.gm = true end
    if C.OnIncoming then pcall(C.OnIncoming, conv) end
end
function C.OnWhisperInform(message, target)
    if not C.Enabled() then return end
    message, target = text(message, 4000), text(target, 80); if not message or not target then return end
    local conv = C.Whisper(target); if conv then C.Add(conv, short(A.Text(A.Call(UnitName, "player"), 60)) or "", message, true) end
end
function C.OnChannel(message, sender, _, channelName, _, _, _, _, baseName)
    if not C.Enabled() then return end
    local room = savedRoom(baseChannel(channelName, baseName)); if not room then return end
    message, sender = text(message, 4000), text(sender, 80); if not message or not sender then return end
    local own = C.NameKey(A.Text(A.Call(UnitName, "player"), 60)) == C.NameKey(sender)
    C.Add(C.Conversation("room", room.name:lower(), C.Label(room.name)), short(sender), message, own)
end
local notices = {YOU_JOINED = "chatJoined", YOU_CHANGED = "chatJoined", YOU_LEFT = "chatLeft", WRONG_PASSWORD = "chatWrongPassword", BANNED = "chatBanned"}
function C.OnNotice(kind, _, _, channelName, _, _, _, _, baseName)
    if not C.Enabled() then return end
    local room = savedRoom(baseChannel(channelName, baseName)); local key = notices[text(kind, 40) or ""]
    if room and key then C.Add(C.Conversation("room", room.name:lower(), C.Label(room.name)), "", A.L(key), false, true) end
end

-- Main-chat filter. Only messages this window has recorded may be hidden: a secret value, a GM whisper or a
-- disabled feature always passes through to the Blizzard chat.
function C.ShouldHide(event, message, _, _, channelName, _, flags, _, _, baseName)
    if not C.Redirect() or not text(message) or text(flags, 10) == "GM" then return false end
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then return true end
    if event == "CHAT_MSG_CHANNEL" then return C.IsRoom(baseChannel(channelName, baseName)) end
    return false
end
local function filter(_, event, ...) local ok, hide = pcall(C.ShouldHide, event, ...); return ok and hide == true end
C.Filter = filter
function C.InstallFilters()
    if C.filtersInstalled or type(ChatFrame_AddMessageEventFilter) ~= "function" then return false end
    for _, event in ipairs({"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL"}) do pcall(ChatFrame_AddMessageEventFilter, event, filter) end
    C.filtersInstalled = true; return true
end

A.On("PLAYER_LOGIN", function()
    C.InstallFilters()
    if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
end)
A.On("PLAYER_ENTERING_WORLD", function()
    if C.rejoined then return end; C.rejoined = true
    -- The default channels are joined first; joining ours right away can take a slot or fail during loading.
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(6, function() pcall(C.Rejoin) end)
        C_Timer.After(15, function() pcall(C.Announce) end)
        if type(C_Timer.NewTicker) == "function" then C_Timer.NewTicker(300, function() pcall(C.Announce) end) end
    else C.Rejoin() end
end)
A.On("CHAT_MSG_ADDON", function(...) pcall(C.OnAddon, ...) end)
A.On("CHAT_MSG_WHISPER", C.OnWhisper)
A.On("CHAT_MSG_WHISPER_INFORM", C.OnWhisperInform)
A.On("CHAT_MSG_CHANNEL", C.OnChannel)
A.On("CHAT_MSG_CHANNEL_NOTICE", C.OnNotice)
