local _, M = ...
local A = _G.Evertally
-- The journey tab: pick a place (a zone or a city, or a flight master, boat, zeppelin, lift or portal) and see the way from where
-- you stand: walking, flights, boats and portals with the time of each step, from the same planner the website uses (Planner.lua).
-- "Navigate" starts the arrow and tracker for the place; "Show on map" opens the map there.
local ROWS, ROW_H, MAX_RESULTS = 8, 28, 40

local text = {
    en = {
        worldPlanTo = "Where to?", worldPlanHint = "Type the name of a zone, a city or a flight master.", worldPlanNone = "Nothing found.",
        worldPlanNoPosition = "Your position is not known here, so there is nothing to start from.", worldPlanNoRoute = "No route is known to that place.",
        worldPlanGo = "Navigate", worldPlanShow = "Show on map", worldPlanTotal = "Total about %s", worldPlanFromYou = "From where you stand",
    },
    cs = {
        worldPlanTo = "Kam?", worldPlanHint = "Napiš název zóny, města nebo létajícího mistra.", worldPlanNone = "Nic nenalezeno.",
        worldPlanNoPosition = "Tvoje poloha tady není známá, takže není odkud vyjít.", worldPlanNoRoute = "Na to místo není známá žádná cesta.",
        worldPlanGo = "Navigovat", worldPlanShow = "Ukázat na mapě", worldPlanTotal = "Celkem asi %s", worldPlanFromYou = "Odtud, kde stojíš",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local Plan = {}
M.Plan = Plan

--- Every place that can be chosen: zones and cities, and the hubs of the travel data. Built once.
function Plan.Places()
    if Plan.cache then return Plan.cache end
    local out = {}
    for id, map in pairs(M.data.maps) do
        if map[5] == 1 or map[5] == 2 then
            local info = C_Map and A.Call(C_Map.GetMapInfo, id)
            local name = A.Text(A.Field(info, "name"), 80)
            if name then out[#out + 1] = {name = name, lower = name:lower(), u = (map[1] + map[2]) / 2, v = (map[3] + map[4]) / 2, map = id, rank = 1} end
        end
    end
    for _, hub in pairs(M.data.hubs) do
        local name = type(hub[6]) == "string" and hub[6] or nil
        if name and name ~= "" then out[#out + 1] = {name = name, lower = name:lower(), u = hub[4], v = hub[5], rank = 2} end
    end
    table.sort(out, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.name < b.name end)
    Plan.cache = out
    return out
end

--- Places whose name contains the query, the ones that start with it first (zones before hubs).
function Plan.Search(query, limit)
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if #query < 2 then return {} end
    local starts, contains = {}, {}
    for _, place in ipairs(Plan.Places()) do
        local at = place.lower:find(query, 1, true)
        if at == 1 then starts[#starts + 1] = place elseif at then contains[#contains + 1] = place end
    end
    local out = {}
    for _, list in ipairs({starts, contains}) do
        for _, place in ipairs(list) do if #out < (limit or MAX_RESULTS) then out[#out + 1] = place end end
    end
    return out
end

--- The journey from where you stand to a place, or nil and why ("no_position" or "no_route").
function Plan.Journey(place)
    local u, v = M.PlayerPosition()
    if not u then return nil, "no_position" end
    local plan = M.PlanJourney({u = u, v = v, label = A.L("navYou")}, {u = place.u, v = place.v, label = place.name}, M.JourneyOptions())
    if not plan or not plan.steps or not plan.steps[1] then return nil, "no_route" end
    return plan
end

--- A place as a point on a game map for the navigator: {map, x, y}.
function Plan.Point(place)
    local map, x, y = M.Locate(place.u, place.v)
    if place.map then map, x, y = place.map, 0.5, 0.5 end
    return map, x, y
end

local function build(frame, kit)
    local C = kit.C
    local s = {results = {}, offset = 0, query = ""}
    frame.plan = s
    s.box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    s.box:SetSize(260, 26); s.box:SetPoint("TOPLEFT", 6, -4); s.box:SetAutoFocus(false); s.box:SetMaxLetters(60); s.box:SetFont("Fonts\\ARIALN.TTF", 12, "")
    s.box:SetScript("OnTextChanged", function(self) s.query = self:GetText() or ""; s.offset = 0; M.WorldPlanRefresh(frame) end)
    s.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    s.label = kit.label(frame, 11, C.mist); s.label:SetPoint("TOPLEFT", 6, -40); s.label:SetWidth(620)
    s.list = CreateFrame("Frame", nil, frame)
    s.list:SetPoint("TOPLEFT", 0, -58); s.list:SetSize(290, ROWS * ROW_H)
    s.list:EnableMouse(true)
    if s.list.EnableMouseWheel then s.list:EnableMouseWheel(true) end
    s.list:SetScript("OnMouseWheel", function(_, delta)
        s.offset = math.max(0, math.min(math.max(0, #s.results - ROWS), s.offset - delta * 3))
        M.WorldPlanRows(frame)
    end)
    s.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, s.list)
        row:SetSize(290, ROW_H - 2); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.bg = kit.fill(row, {1, 1, 1}, 1); row.bg:SetAlpha(0.05)   -- the alpha IS the strength: a colour alpha on top would multiply
        row.name = kit.label(row, 12, C.text); row.name:SetPoint("LEFT", 8, 0); row.name:SetWidth(270); row.name:SetJustifyH("LEFT")
        row:SetScript("OnEnter", function() row.bg:SetAlpha(0.14) end)
        row:SetScript("OnLeave", function() row.bg:SetAlpha(0.05) end)
        row:SetScript("OnClick", function() if row.place then s.chosen = row.place; M.WorldPlanShow(frame) end end)
        s.rows[i] = row
    end
    s.title = kit.label(frame, 15, C.text); s.title:SetPoint("TOPLEFT", 306, -60); s.title:SetWidth(350); s.title:SetJustifyH("LEFT")
    s.sub = kit.label(frame, 11, C.mist); s.sub:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 0, -4); s.sub:SetWidth(350)
    s.body = kit.label(frame, 12, C.text); s.body:SetPoint("TOPLEFT", s.sub, "BOTTOMLEFT", 0, -10); s.body:SetWidth(350); s.body:SetJustifyH("LEFT")
    frame:SetScript("OnSizeChanged", function(_, w)
        w = tonumber(w) or 0
        if w < 200 then return end
        local detail = math.max(180, w - 312)
        s.title:SetWidth(detail); s.sub:SetWidth(detail); s.body:SetWidth(detail); s.label:SetWidth(math.max(100, w - 12))
    end)
    s.go = kit.Button(frame, "worldPlanGo", 150, "primary", function()
        local place = s.chosen
        if not place then return end
        local map, x, y = Plan.Point(place)
        if map and A.NavigateToPoint then A.NavigateToPoint(place.name, map, x, y, {tab = "plan", name = place.name}) end
    end)
    s.go:SetPoint("BOTTOMLEFT", 306, 36)
    s.show = kit.Button(frame, "worldPlanShow", 150, "ghost", function()
        local place = s.chosen
        local map, x, y = place and Plan.Point(place)
        if not (map and M.ShowOnWorldMap) then return end
        local goal = {{map = map, x = x, y = y, title = place.name}}
        local plan = Plan.Journey(place)
        if plan and M.ShowRoute then M.ShowRoute(plan, goal)   -- the line from where you stand, and the view that holds it
        else M.ShowOnWorldMap(goal, map) end
    end)
    s.show:SetPoint("BOTTOMLEFT", 306, 0)
end

function M.WorldPlanRows(frame)
    local s = frame.plan
    for i, row in ipairs(s.rows) do
        local place = s.results[s.offset + i]
        row.place = place
        row:SetShown(place ~= nil)
        if place then row.name:SetText(A.Plain(place.name)) end
    end
end

--- The chosen place with the steps of the way there.
function M.WorldPlanShow(frame)
    local s = frame.plan
    local place = s.chosen
    s.title:SetText(place and A.Plain(place.name) or "")
    s.go:SetShown(place ~= nil); s.show:SetShown(place ~= nil)
    if not place then s.sub:SetText(""); s.body:SetText(""); return end
    local plan, why = Plan.Journey(place)
    s.sub:SetText(A.L("worldPlanFromYou"))
    if not plan then
        s.body:SetText(A.L(why == "no_position" and "worldPlanNoPosition" or "worldPlanNoRoute"))
        return
    end
    local lines = {}
    for _, step in ipairs(plan.steps) do lines[#lines + 1] = M.StepText(step) end
    lines[#lines + 1] = "|cffa78bfa" .. string.format(A.L("worldPlanTotal"), M.Clock(plan.seconds)) .. "|r"
    local plain = {}
    for _, line in ipairs(lines) do plain[#plain + 1] = line:find("|c", 1, true) and line or A.Plain(line) end
    s.body:SetText(table.concat(plain, "\n"))
end

function M.WorldPlanRefresh(frame)
    local s = frame.plan
    if not s then return end
    s.results = Plan.Search(s.query, MAX_RESULTS)
    if #(s.query:gsub("%s", "")) < 2 then s.label:SetText(A.L("worldPlanHint"))
    elseif #s.results == 0 then s.label:SetText(A.L("worldPlanNone"))
    else s.label:SetText("") end
    M.WorldPlanRows(frame)
    M.WorldPlanShow(frame)
end

M.worldTabs.plan = {build = build, refresh = function(frame) M.WorldPlanRefresh(frame) end}
