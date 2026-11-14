local _, A = ...
-- Evertally's public leaderboard in the player tooltip: the place on the website's board and in the class, completed
-- runs, and the item level where the player chose to show it. The data comes from RankingData.lua, which Evertally Sync
-- writes from the website; without it, or once it is stale, nothing is added. Settings → Interface can turn it off.

local index, indexedAt

--- The same key for the website's realm text and the game's: no spaces, dashes or apostrophes, lower case.
local function key(name, realm)
    name, realm = A.Plain(name), A.Plain(realm)
    if type(name) ~= "string" or type(realm) ~= "string" or name == "" or realm == "" then return nil end
    return name:lower() .. "|" .. realm:gsub("[%s%-']", ""):lower()
end

--- The players of a current package by name and realm, and the package itself; nil when there is none or it is stale.
function A.RankingIndex()
    local data = EvertallyRankingData
    if type(data) ~= "table" or data.kind ~= "evertally-ranking" or data.schemaVersion ~= 1 then return nil end
    if type(data.expiresAt) ~= "number" or data.expiresAt < A.Now() then return nil end
    if index and indexedAt == data.generatedAt then return index, data end
    index = {}
    for _, p in ipairs(type(data.players) == "table" and data.players or {}) do
        if type(p) == "table" and type(p.k) == "number" then
            local k = key(p.n, p.r)
            if k then index[k] = p end
        end
    end
    indexedAt = data.generatedAt
    return index, data
end

function A.RankingFor(name, realm)
    local players, data = A.RankingIndex()
    local k = players and key(name, realm)
    return k and players[k] or nil, data
end

--- The lines for one player: {left, right}. The first one is the place on the whole board.
function A.RankingLines(p, data)
    local lines = {{"Evertally", string.format(A.L("tipRank"), p.k, tonumber(data.total) or p.k)}}
    if type(p.ck) == "number" then
        local class = p.c and A.ClassName and A.ClassName(p.c) or nil
        lines[#lines + 1] = {class and string.format(A.L("tipClassRankOf"), class) or A.L("tipClassRank"), "#" .. p.ck}
    end
    if type(p.i) == "number" then lines[#lines + 1] = {A.L("tipItemLevel"), tostring(p.i)} end
    if type(p.u) == "number" and p.u > 0 then lines[#lines + 1] = {A.L("tipRuns"), tostring(p.u)} end
    return lines
end

local function onUnit(tooltip)
    if not A.db or A.db.settings.rankTooltip == false then return end
    if tooltip ~= GameTooltip or type(tooltip.GetUnit) ~= "function" then return end
    local _, unit = tooltip:GetUnit()
    if not unit or not A.Call(UnitIsPlayer, unit) then return end
    local name, realm = A.Call(UnitName, unit)
    realm = A.Plain(realm)
    if type(realm) ~= "string" or realm == "" then realm = A.Call(GetNormalizedRealmName) or A.Call(GetRealmName) end
    local p, data = A.RankingFor(name, realm)
    if not p then return end
    for i, line in ipairs(A.RankingLines(p, data)) do
        if i == 1 then tooltip:AddDoubleLine(line[1], line[2], 1, 0.6, 0.12, 1, 0.82, 0.4)
        else tooltip:AddDoubleLine(line[1], line[2], 0.75, 0.75, 0.75, 1, 1, 1) end
    end
    tooltip:Show()
end

local hooked = false
--- The way the addons that run on Forever do it: the tooltip data processor when the client has it, else the old script.
function A.HookRankingTooltip()
    if hooked or not GameTooltip then return end
    hooked = true
    local viaProcessor = false
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        viaProcessor = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tooltip) pcall(onUnit, tooltip) end)
    end
    if not viaProcessor and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip) pcall(onUnit, tooltip) end)
    end
end

if A.On then A.On("PLAYER_LOGIN", function() A.HookRankingTooltip() end) end
