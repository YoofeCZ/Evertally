local _, A = ...
-- "A new version is out": Evertally players tell each other their addon version with an invisible addon message in the
-- #Evertally room (Chat.lua joins it for everyone). The game cannot learn of a release from the Evertally app before a
-- /reload, but it hears other players at once. A newer version is announced once per session, and only after two
-- different players reported it, so one prankster cannot fake a release.
local V = {seen = {}, told = nil}
A.VersionCheck = V
local words = {
    en = {versionNew = "A new Evertally %s is out (you have %s). The Evertally app downloads it by itself; restart the game when it is done.",
        versionTitle = "New Evertally version"},
    cs = {versionNew = "Je venku nový Evertally %s (máš %s). Aplikace Evertally ho stáhne sama; až bude hotovo, restartuj hru.",
        versionTitle = "Nová verze Evertally"},
}
for lang, entries in pairs(words) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local PREFIX, WITNESSES = "EvtlyVer", 2

--- 0.9.51 -> 9051 (major*1000000 + minor*1000 + patch); nil for anything else.
function V.Number(text)
    text = A.Text(text, 20); if not text then return nil end
    local a, b, c = text:match("^(%d+)%.(%d+)%.(%d+)$")
    a, b, c = tonumber(a), tonumber(b), tonumber(c)
    if not a or a > 9 or b > 999 or c > 999 then return nil end
    return a * 1000000 + b * 1000 + c
end

local function channel()
    local id = A.Call(GetChannelName, "Evertally"); id = A.Number(id)
    if id and id > 0 then return id end
end
function V.Announce()
    local id = channel()
    if not id or not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then return false end
    return (pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V|" .. A.version, "CHANNEL", id))
end

local function key(name) name = A.Text(name, 80); return name and (name:match("^[^%- ]+") or name):lower() end
function V.Receive(prefix, message, _, sender)
    if A.Text(prefix, 20) ~= PREFIX then return end
    local version = A.Text(message, 30); version = version and version:match("^V|(%d+%.%d+%.%d+)$")
    local number, mine, who = V.Number(version), V.Number(A.version), key(sender)
    if not number or not mine or not who then return end
    -- someone with an older version: tell the room ours (at most every five minutes), so they learn of it now
    if number < mine then
        if not V.replied or A.Monotonic() - V.replied >= 300 then V.replied = A.Monotonic(); pcall(V.Announce) end
        return
    end
    if number == mine then return end
    V.seen[version] = V.seen[version] or {}
    V.seen[version][who] = true
    local count = 0; for _ in pairs(V.seen[version]) do count = count + 1 end
    if count >= WITNESSES and (not V.told or V.Number(V.told) < number) then
        V.told = version
        V.Notify(version)
        return true
    end
end

function V.Notify(version)
    local text = string.format(A.L("versionNew"), version, A.version)
    A.Print(text)
    if type(RaidNotice_AddMessage) == "function" and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.SYSTEM then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, "Evertally " .. version, ChatTypeInfo.SYSTEM)
    end
end

A.On("PLAYER_LOGIN", function()
    if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
end)
A.On("PLAYER_ENTERING_WORLD", function()
    if V.started then return end; V.started = true
    -- once #Evertally is joined (Chat.lua does it 6 s after loading), then every half hour for players who log in later
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(14, function() pcall(V.Announce) end)
        if type(C_Timer.NewTicker) == "function" then C_Timer.NewTicker(1800, function() pcall(V.Announce) end) end
    end
end)
A.On("CHAT_MSG_ADDON", function(...) pcall(V.Receive, ...) end)
