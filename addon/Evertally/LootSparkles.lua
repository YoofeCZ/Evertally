local _, A = ...
-- Loot sparkles (settings.lootSparkles, on by default): the client's sparkle on lootable quest items stays on. It is
-- the CVar outlineModeShowLootEffectWhenDisabled; a graphics preset (or the outline mode) switches it off, so it is set
-- again at login, after a fight (a CVar may not change in combat) and whenever the client reports it changed. Switched
-- off here, the value the player had before goes back.
local S = {}
A.LootSparkles = S

S.CVAR = "outlineModeShowLootEffectWhenDisabled"

local function g(name) return rawget(_G, name) end
local function settings() return A.db and A.db.settings or {} end
local function cvar() local c = g("C_CVar"); return type(c) == "table" and c or nil end
local function get() local c = cvar(); if not c or type(c.GetCVar) ~= "function" then return nil end; local ok, v = pcall(c.GetCVar, S.CVAR); return ok and v or nil end
local function set(v)
    local c = cvar()
    if not c or type(c.SetCVar) ~= "function" then return false end
    if type(g("InCombatLockdown")) == "function" and g("InCombatLockdown")() then S.pending = true; return false end
    local ok = pcall(c.SetCVar, S.CVAR, v)
    S.pending = not ok
    return ok
end

function S.Enabled() return settings().lootSparkles ~= false end

--- Puts the sparkle on (keeping the player's own value to give back) or gives that value back.
function S.Apply()
    if not A.db then return end
    local s = settings()
    local now = get()
    if now == nil then return end
    if S.Enabled() then
        if s.lootSparklesWas == nil and now ~= "1" then s.lootSparklesWas = now end
        if now ~= "1" then set("1") end
    elseif s.lootSparklesWas ~= nil then
        if set(s.lootSparklesWas) then s.lootSparklesWas = nil end
    end
end

function S.SetEnabled(on)
    if not A.db then return end
    settings().lootSparkles = on == true
    S.Apply()
end

A.On("PLAYER_LOGIN", S.Apply)
A.On("PLAYER_ENTERING_WORLD", S.Apply)
A.On("PLAYER_REGEN_ENABLED", function() if S.pending then S.Apply() end end)
A.On("CVAR_UPDATE", function(name)
    if type(name) == "string" and name:lower() == S.CVAR:lower() and S.Enabled() and get() ~= "1" then S.Apply() end
end)
