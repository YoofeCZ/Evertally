local _, A = ...
-- The player's choice to show their characters in the website's public leaderboard (and, optionally, the average
-- item level, the guild name, the gear and talents on the character page, and the chronicle of the journey; never the bags). One choice for the account, sent once for every character the player
-- logs in with as a `character.publish` event. The website applies it only when it is newer than a choice made there
-- (payload.chosenAt), so neither side silently undoes a later choice of the other. Off until the player turns it on,
-- and it travels only with the website export and the character scope.

local function state()
    local s = A.db.settings
    if type(s.publish) ~= "table" then s.publish = {public = false, itemLevel = false, guild = false, gear = false, chronicle = false} end
    if type(s.publishSent) ~= "table" then s.publishSent = {} end
    return s.publish, s.publishSent
end

function A.PublishChoice() return (state()) end
function A.CanPublish()
    local s = A.db and A.db.settings
    return s ~= nil and s.web == true and type(s.scopes) == "table" and s.scopes.own_character == true
end

--- Sends the current choice for the logged-in character when it has not been sent for it yet. Returns true when sent.
function A.SendPublish()
    if not A.db or not A.CanPublish() then return false end
    local choice, sent = state()
    if not choice.chosenAt then return false end   -- never chosen in the game: the website alone decides
    local c = A.Character()
    local key = c and c.id
    -- the revision, not the time: two changes within one second are two choices
    if not key or sent[key] == choice.revision then return false end
    local event = A.Record("character.publish", {public = choice.public == true, showItemLevel = choice.itemLevel == true,
        showGuild = choice.guild == true, showGear = choice.gear == true, showChronicle = choice.chronicle == true, chosenAt = choice.chosenAt}, "api_snapshot", nil, true)
    if not event then return false end
    sent[key] = choice.revision
    return true
end

--- field: "public", "itemLevel", "guild", "gear" or "chronicle" (the route and what the character did, as a replayable journey on the website).
function A.SetPublish(field, value)
    if not A.db or (field ~= "public" and field ~= "itemLevel" and field ~= "guild" and field ~= "gear" and field ~= "chronicle") then return end
    local choice = state()
    choice[field] = value == true
    choice.chosenAt = A.Now()
    choice.revision = (tonumber(choice.revision) or 0) + 1
    A.SendPublish()
    if A.Changed then A.Changed() end
end

--- A new consent starts an empty outbox: the choice has to travel again in it.
function A.ResendPublish()
    if not A.db then return end
    A.db.settings.publishSent = {}
    A.SendPublish()
end

if A.On then A.On("PLAYER_ENTERING_WORLD", function() A.SendPublish() end) end
