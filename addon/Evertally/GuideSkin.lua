local _, A = ...
-- Evertally's own look for Evertally Guide (the Polestar fork): its colours, its face and no starlit band, through the
-- guide's Skin API (Evertally_Guide/Theme/SkinApi.lua). The default skin of the fork (tools/import_polestar.py sets
-- ui.skin = "evertally"); a player may still pick another one in the guide's Theme page.
-- Graphite grounds, a cool off-white ladder and Evertally's violet (the stroke of its tally mark) as the accent.

local G = rawget(_G, "EvertallyGuide")
local Theme = type(G) == "table" and G.Theme
if not (Theme and Theme.RegisterSkin and Theme.RegisterScheme and (Theme.API_VERSION or 0) >= 2) then return end

local function check(what, ok, message)
    if not ok then print(("|cffff8040Evertally|r: %s refused: %s"):format(what, tostring(message))) end
end

local ACCENT = "#9d8cff"
local GROUNDS = {
    bg = "#131418", panel = "#181a1f", panelAlt = "#21242b", sidebar = "#0f1013", footer = "#111216", sky = "#191b21",
    text = "#eef0f4", textDim = "#bcc1cc", textMuted = "#868c99",
    ink = "#ffffff", star = "#ffffff00", shade = "#000000", scrim = "#050507", onAccent = "#16131f", shadow = "#00000099",
}

check("scheme evertally", Theme.RegisterScheme("evertally", {
    api = 2, name = "Evertally", addon = "Evertally", author = "Evertally",
    desc = "Graphite grounds and Evertally's violet.",
    tokens = GROUNDS, accent = ACCENT,
}))

local TOKENS = {
    accent = ACCENT,
    success = "#5fd39a", warning = "#f0b357", danger = "#ff7a7a",
    quest = "#ffd27a", npc = "#86b8ff", item = "#c9a6ff", place = "#f2a77e", object = "#d8ccb4",
    area = "#f2bf94", dungeon = "#b9a4ff", rare = "#ff9a6b",
}

local PRESET = {
    ["ui.band"] = false, ["ui.shadow"] = true, ["ui.border"] = true, ["ui.borderSize"] = 1,
}

check("skin evertally", Theme.RegisterSkin("evertally", {
    api = 2,
    name = "Evertally",
    addon = "Evertally",
    author = "Evertally",
    desc = "Evertally's own look: graphite, violet, no stars.",
    base = "polestar",
    scheme = "evertally",
    tokens = TOKENS,
    font = "inter",
    textShadow = false,
    preset = PRESET,
}))

-- One look: Evertally's (the guide offers no other, tools/import_polestar.py). A look saved before 0.11.1 is put back
-- to it at login.
if A and A.On then
    A.On("PLAYER_LOGIN", function()
        if type(G.Get) == "function" and type(G.Set) == "function" and G.Get("ui.skin") ~= "evertally" then
            pcall(G.Set, "ui.skin", "evertally")
        end
    end)
end
