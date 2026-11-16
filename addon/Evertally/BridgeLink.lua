local _, A = ...
-- The link to the Evertally app for Windows, as far as the game can see it.
--
-- The game cannot start a program or talk to one while it runs. What it can do: keep a request in EvertallyDB.bridgeRequest
-- and save it (/reload, logout). The app watches the SavedVariables folder, reads only that table and acts: it opens the
-- website's pairing page, or turns "start with WoW" on or off. What the app knows travels back in BridgeInstallation.lua,
-- which the game loads at login and /reload: whether this PC is paired and whether the app starts with WoW (yes/no only,
-- never an account or a token).
--
-- The same holds for every choice that concerns the website: the game writes it to disk only at /reload or logout, and only
-- then can the app send it. After such a change a small bar offers to save now.

local PAIR_FRESH = 15 * 60   -- the app ignores an older pairing request (sync/src/game_requests.rs)

local function receipt() return type(A.bridgeInstallation) == "table" and A.bridgeInstallation or nil end
local function request()
    if not A.db then return nil end
    if type(A.db.bridgeRequest) ~= "table" then A.db.bridgeRequest = {} end
    return A.db.bridgeRequest
end

--- "paired", "unpaired" or "unknown" (an app too old to report it, or no app at all).
function A.BridgePairing()
    local r = receipt()
    if not r then return "unknown" end
    if r.paired == true then return "paired" end
    if r.paired == false then return "unpaired" end
    return "unknown"
end
function A.BridgePaired() return A.BridgePairing() == "paired" end

--- True while a pairing request from this game is recent and the app has not reported a pairing yet.
function A.BridgePairingRequested()
    local r = A.db and type(A.db.bridgeRequest) == "table" and A.db.bridgeRequest or nil
    local at = r and A.Number(r.pairAt, 1)
    return at ~= nil and not A.BridgePaired() and A.Now() - at <= PAIR_FRESH
end

--- Asks the app to open pairing: saves the request and reloads the interface so the game writes it to disk.
function A.RequestPairing()
    if A.Call(InCombatLockdown) == true then A.Print(A.L("markPlatesCombat")); return false end
    local r = request(); if not r then return false end
    r.pairAt = A.Now()
    A.Call(ReloadUI)
    return true
end

--- The start-with-WoW choice: what the player chose here last, or else what the app reports.
function A.BridgeAutostart()
    local r = A.db and type(A.db.bridgeRequest) == "table" and A.db.bridgeRequest or nil
    if r and type(r.autostart) == "boolean" then return r.autostart end
    local proof = receipt()
    return proof ~= nil and proof.autostart == true
end
--- What the app itself reports (nil when it does not say).
function A.BridgeAutostartReported()
    local proof = receipt()
    if proof and type(proof.autostart) == "boolean" then return proof.autostart end
    return nil
end
function A.SetBridgeAutostart(on)
    local r = request(); if not r then return end
    r.autostart = on == true
    r.autostartAt = A.Now()
    A.MarkWebChanged()
    if A.Changed then A.Changed() end
end

-- ---------------------------------------------------------------- "save now" after a change the website or the app should see
local bar
local function buildBar()
    local kit = A.UIKit(); local C = kit.C
    bar = CreateFrame("Frame", "EvertallySaveBar", UIParent)
    bar:SetSize(560, 48); bar:SetPoint("TOP", UIParent, "TOP", 0, -84); bar:SetFrameStrata("DIALOG"); bar:EnableMouse(true)
    A.NativeFrame(bar, C)
    bar.text = kit.label(bar, 12, C.text); bar.text:SetPoint("LEFT", 16, 0); bar.text:SetPoint("RIGHT", -220, 0)
    bar.close = kit.Button(bar, nil, 28, "ghost", function() bar:Hide() end); bar.close:SetPoint("RIGHT", -10, 0); bar.close.text:SetText("x")
    bar.save = kit.Button(bar, nil, 160, "primary", function()
        if A.Call(InCombatLockdown) == true then A.Print(A.L("markPlatesCombat")); return end
        A.Call(ReloadUI)
    end)
    bar.save:SetPoint("RIGHT", bar.close, "LEFT", -8, 0)
    bar:Hide()
end
--- Shows the bar: the change is kept in the game, and reaches the app and the website once the game saves it.
function A.MarkWebChanged()
    if not A.db or type(CreateFrame) ~= "function" then return end
    A.webChangePending = true
    if A.OnboardingShown and A.OnboardingShown() then return end   -- the setup says it itself, and shows the bar at Finish
    if not bar and not pcall(buildBar) then bar = nil; return end   -- no interface yet: the change is still kept
    bar.text:SetText(A.L("saveBarText")); bar.save.text:SetText(A.L("saveBarButton"))
    bar:Show()
end
function A.SaveBarShown() return bar ~= nil and bar:IsShown() end

local text = {
    en = {
        saveBarText = "Changes for the website are saved by the game only at /reload or logout.",
        saveBarButton = "Save and send",
    },
    cs = {
        saveBarText = "Změny pro web hra uloží až při /reload nebo odhlášení.",
        saveBarButton = "Uložit a poslat",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end
