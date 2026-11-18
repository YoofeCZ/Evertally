local _, M = ...
local A = _G.Evertally
-- The "World" page of the Evertally window: a strip of tabs (database, journey) over one body. The tabs live in their own files
-- (WorldDbPage.lua, WorldPlan.lua) and register themselves in M.worldTabs; this file is the frame around them. The map itself is
-- the game's world map (MapLayers.lua, MapPanel.lua), not a map in this window.
-- It is built once, the first time the page is opened with the map add-on loaded (WorldHost.lua in the main add-on asks for it).
local ORDER = {"map", "plan", "gather", "services", "instances"}
M.worldTabs = M.worldTabs or {}

local text = {
    en = {worldTab_map = "Map", worldTab_db = "Database", worldTab_plan = "Journey", worldTab_gather = "Gathering", worldTab_instances = "Instances"},
    cs = {worldTab_map = "Mapa", worldTab_db = "Databáze", worldTab_plan = "Cesta", worldTab_gather = "Sbírání", worldTab_instances = "Instance"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

--- body: the area under the page header; kit: the window's helpers (A.UIKit()).
function M.BuildWorld(body, kit)
    body.kit, body.mode, body.tabButtons, body.tabFrames = kit, "map", {}, {}
    for i, key in ipairs(ORDER) do
        local button = kit.Button(body, "worldTab_" .. key, 96, "ghost", function() body.mode = key; M.RefreshWorld(body) end)
        button:SetPoint("TOPLEFT", (i - 1) * 100, 0)
        body.tabButtons[key] = button
        local frame = CreateFrame("Frame", nil, body)
        frame:SetPoint("TOPLEFT", 0, -38); frame:SetPoint("BOTTOMRIGHT"); frame:Hide()
        body.tabFrames[key] = frame
    end
    -- In the guide's hub (HubKit.lua): the tabs are the hub's own, in its tab row; the tab's body starts at the top.
    local page = body:GetParent()
    if page and page.hubMode and A.HubKit and A.HubKit.Guide() then
        local away = CreateFrame("Frame", nil, body); away:Hide()
        for _, key in ipairs(ORDER) do
            body.tabButtons[key]:SetParent(away)
            body.tabFrames[key]:ClearAllPoints(); body.tabFrames[key]:SetPoint("TOPLEFT", 0, 0); body.tabFrames[key]:SetPoint("BOTTOMRIGHT")
        end
        page.hubTabs = function()
            local tabs = {}
            for _, key in ipairs(ORDER) do tabs[#tabs + 1] = {key = key, label = A.L("worldTab_" .. key)} end
            return tabs
        end
        page.hubTab = function() return body.mode end
        page.OnHubTab = function(key) body.mode = key; M.RefreshWorld(body) end
    end
end

--- The database page: the database tab on a page of its own (it is not a part of the map). body.tabFrames.db is the tab's frame.
function M.BuildDatabase(body, kit)
    body.kit, body.mode, body.tabButtons, body.tabFrames = kit, "db", {}, {}
    local frame = CreateFrame("Frame", nil, body)
    frame:SetAllPoints(body)
    body.tabFrames.db = frame
end
function M.RefreshDatabase(body)
    local frame, tab = body.tabFrames and body.tabFrames.db, M.worldTabs.db
    if not frame or not tab then return end
    if not frame.built then
        frame.built = true
        local ok = pcall(tab.build, frame, body.kit)
        if not ok then A.errors.world_db = (A.errors.world_db or 0) + 1; frame.failed = true end
    end
    if not frame.failed then pcall(tab.refresh, frame) end
end

--- Shows the chosen tab, building it the first time. A tab that fails to build leaves the others working.
function M.RefreshWorld(body)
    if not body.tabFrames then return end
    for _, key in ipairs(ORDER) do
        local button, frame, tab = body.tabButtons[key], body.tabFrames[key], M.worldTabs[key]
        button.text:SetText(A.L("worldTab_" .. key))
        button.text:SetTextColor(unpack(body.mode == key and (body.kit.C.bright or body.kit.C.gold) or body.kit.C.mist))
        frame:SetShown(body.mode == key)
        if body.mode == key and tab then
            if not frame.built then
                frame.built = true
                local ok = pcall(tab.build, frame, body.kit)
                if not ok then A.errors["world_" .. key] = (A.errors["world_" .. key] or 0) + 1; frame.failed = true end
            end
            if not frame.failed then pcall(tab.refresh, frame) end
        end
    end
end
