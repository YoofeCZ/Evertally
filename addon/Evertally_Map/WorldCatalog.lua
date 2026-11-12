local _, M = ...
local A = _G.Evertally
-- Resource and instance catalogues: the same verified reference data as the map layers.
local text = {
    en = {catalogSearch = "Search by name", catalogShow = "Show on map", catalogGo = "Navigate", catalogAll = "All", catalogNone = "Nothing found.",
        catalogPoints = "%d reference locations", catalogCounts = "%d entries", catalogUnknown = "No entrance is known; navigation is unavailable.",
        catalogNearest = "No location is known on your continent. Show the map instead.", catalogAllResources = "Clear resource selection", catalogReference = "Reference data, not live resource availability."},
    cs = {catalogSearch = "Hledat podle jména", catalogShow = "Ukázat na mapě", catalogGo = "Navigovat", catalogAll = "Vše", catalogNone = "Nic nenalezeno.",
        catalogPoints = "%d referenčních míst", catalogCounts = "%d záznamů", catalogUnknown = "Vchod není známý; navigace není dostupná.",
        catalogNearest = "Na tvém kontinentu není známé místo. Použij zobrazení na mapě.", catalogAllResources = "Zrušit výběr suroviny", catalogReference = "Referenční data, ne aktuální dostupnost surovin."},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local TYPES = {"herb", "ore", "fishing", "container"}
local MAX_ROWS, ROW_HEIGHT = 14, 28

local function spotsFor(mode, item)
    if not item then return {} end
    if mode == "gather" then return M.ResourceSpots(item.key) end
    if mode == "services" then return M.ServiceSpots(item.key) end
    return item.map and {{map = item.map, x = item.x, y = item.y, title = item.name}} or {}
end
local function selectItem(frame, item)
    local s = frame.catalog
    s.selected = item
    s.title:SetText(item and A.Plain(item.name) or "")
    local lines = {}
    if item then
        if s.mode == "gather" then
            lines[#lines + 1] = A.L("gather_" .. item.kind)
            if item.skill then lines[#lines + 1] = string.format(A.L("layerSkill"), item.skill) end
            lines[#lines + 1] = string.format(A.L("catalogPoints"), item.count)
            lines[#lines + 1] = A.L("catalogReference")
        elseif s.mode == "services" then
            lines[#lines + 1] = A.L("servicesKind_" .. item.kind)
            lines[#lines + 1] = string.format(A.L("servicesPlaces"), item.count)
            lines[#lines + 1] = A.L("servicesHint")
        else
            lines[#lines + 1] = A.L("instance_" .. item.kind)
            if item.level then lines[#lines + 1] = tostring(item.level[1]) .. "–" .. tostring(item.level[2]) end
            lines[#lines + 1] = string.format(A.L("layerPlayers"), item.players)
            lines[#lines + 1] = item.map and M.MapName(item.map) or A.L("catalogUnknown")
            if item.hint ~= "" then lines[#lines + 1] = item.hint end
        end
    end
    s.detail:SetText(A.Plain(table.concat(lines, "\n\n")))
    s.scrollContent:SetHeight(math.max(80, (s.detail:GetStringHeight() or 80) + 12))
    local places = spotsFor(s.mode, item)
    s.show:SetShown(#places > 0); s.go:SetShown(#places > 0)
    for _, row in ipairs(s.rows) do row.bg:SetAlpha(row.item == item and 0.14 or 0.05) end
end

function M.WorldCatalogRows(frame)
    local s = frame.catalog
    for i, row in ipairs(s.rows) do
        row.item = i <= s.visibleRows and s.results[s.offset + i] or nil
        row:SetShown(row.item ~= nil)
        if row.item then
            row.name:SetText(A.Plain(row.item.name))
            row.bg:SetAlpha(row.item == s.selected and 0.14 or 0.05)
            local ticked = s.mode == "gather" or s.mode == "services"
            row.icon:SetShown(ticked); row.check:SetShown(ticked)
            row.name:ClearAllPoints(); row.name:SetPoint("LEFT", ticked and 36 or 8, 0); row.name:SetPoint("RIGHT", ticked and -34 or -8, 0)
            if ticked then
                if row.item.icon then row.icon:SetTexture(row.item.icon); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
                local shown
                if s.mode == "services" then shown = M.ServicePicked(row.item.key) else shown = M.GatherShown(row.item.key) end
                row.check.box:SetAlpha(shown and 1 or 0.25)
                row.name:SetTextColor(shown and 1 or 0.55, shown and 1 or 0.55, shown and 1 or 0.6)
            end
        end
    end
end

function M.WorldCatalogRefresh(frame)
    local s = frame.catalog
    if not s then return end
    local active = {}
    if s.mode == "gather" then
        s.results = M.GatherResources(s.query)
        for key, chip in pairs(s.filterButtons) do chip.SetLabel(A.L("gather_" .. key)); chip.SetOn(M.GatherTypeOn(key)) end
    elseif s.mode == "services" then
        M.wantServices = true   -- the list is read from the NPC database: the scan has to run while this is open
        local kind = M.ServiceKind()
        s.results = M.ServiceItems(s.query, kind)
        for key, chip in pairs(s.filterButtons) do chip.SetLabel(A.L("servicesKind_" .. key)); chip.SetOn(kind == key) end
    else
        local kind = A.db.settings.instanceKind or "all"
        s.results = M.Instances(s.query, kind)
        for key, chip in pairs(s.filterButtons) do chip.SetLabel(A.L(key == "all" and "catalogAll" or ("instance_" .. key))); chip.SetOn(kind == key) end
    end
    for _, item in ipairs(s.results) do active[item.key] = item end
    s.offset = math.min(s.offset, math.max(0, #s.results - s.visibleRows))
    local progress = s.mode == "services" and M.layerProgress
    s.count:SetText(#s.results > 0 and string.format(A.L("catalogCounts"), #s.results)
        or (progress and string.format(A.L("servicesReading"), math.floor(progress * 100)) or A.L(s.mode == "services" and "servicesNothing" or "catalogNone")))
    s.show.text:SetText(A.L("catalogShow")); s.go.text:SetText(A.L("catalogGo"))
    if s.all then s.all.text:SetText(A.L(s.mode == "services" and "catalogClearPicks" or "catalogAllResources")) end
    if s.showAll then s.showAll.SetLabel(A.L("catalogShowAll")); s.hideAll.SetLabel(A.L("catalogHideAll")); s.showAll.SetOn(false); s.hideAll.SetOn(false) end
    M.WorldCatalogRows(frame)
    selectItem(frame, s.selected and active[s.selected.key] or s.results[1])
end

local function build(frame, kit, mode)
    frame.kit = kit
    local s = {mode = mode, query = "", results = {}, rows = {}, filterButtons = {}, offset = 0, visibleRows = 8}
    frame.catalog = s
    local kinds = mode == "gather" and TYPES or mode == "services" and {"trainer", "vendor"} or {"all", "dungeon", "raid"}
    local previous
    for _, key in ipairs(kinds) do
        local chip = kit.Chip(frame, function()
            if mode == "gather" then M.SetGatherType(key, not M.GatherTypeOn(key))
            elseif mode == "services" then M.SetServiceKind(key)
            else M.SetInstanceKind(key) end
            s.offset = 0; M.WorldCatalogRefresh(frame)
        end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 0, 0) end
        s.filterButtons[key] = chip; previous = chip
    end
    s.box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    s.box:SetSize(250, 26); s.box:SetPoint("TOPLEFT", 6, -36); s.box:SetAutoFocus(false); s.box:SetMaxLetters(60)
    s.box:SetFont(A.FontPath and A.FontPath() or "Fonts\\ARIALN.TTF", 12, "")
    s.box:SetScript("OnTextChanged", function(self) s.query = self:GetText() or ""; s.offset = 0; M.WorldCatalogRefresh(frame) end)
    s.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    s.count = kit.label(frame, 11, kit.C.mist); s.count:SetPoint("LEFT", s.box, "RIGHT", 12, 0)
    s.list = CreateFrame("Frame", nil, frame); s.list:SetPoint("TOPLEFT", 0, -78); s.list:SetPoint("BOTTOMLEFT", 0, 0)
    s.list:EnableMouse(true); if s.list.EnableMouseWheel then s.list:EnableMouseWheel(true) end
    s.list:SetScript("OnMouseWheel", function(_, delta)
        s.offset = math.max(0, math.min(math.max(0, #s.results - s.visibleRows), s.offset - delta * 3)); M.WorldCatalogRows(frame)
    end)
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, s.list); row:SetHeight(ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
        row.bg = kit.fill(row, {1, 1, 1}, 1); row.bg:SetAlpha(0.05)   -- the alpha IS the strength: a colour alpha on top would multiply
        row.name = kit.label(row, 12, kit.C.text); row.name:SetPoint("LEFT", 8, 0); row.name:SetPoint("RIGHT", -8, 0); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        -- gathering: the resource's own picture on the left and a tick on the right that shows or hides it on the map
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(22, 22); row.icon:SetPoint("LEFT", 8, 0); row.icon:Hide()
        row.check = CreateFrame("Button", nil, row); row.check:SetSize(28, ROW_HEIGHT - 4); row.check:SetPoint("RIGHT", -2, 0); row.check:Hide()
        row.check.box = row.check:CreateTexture(nil, "ARTWORK"); row.check.box:SetSize(14, 14); row.check.box:SetPoint("CENTER")
        kit.paint(row.check.box, kit.C.lilac, 1)
        row.check:SetScript("OnClick", function()
            if not row.item then return end
            if s.mode == "services" then M.SetServicePicked(row.item.key, not M.ServicePicked(row.item.key))
            else M.SetGatherShown(row.item.key, not M.GatherShown(row.item.key)) end
            M.WorldCatalogRows(frame)
        end)
        row:SetScript("OnClick", function() selectItem(frame, row.item) end)
        s.rows[i] = row
    end
    s.card = CreateFrame("Frame", nil, frame); s.card:SetPoint("TOPLEFT", s.list, "TOPRIGHT", 12, 0); s.card:SetPoint("BOTTOMRIGHT")
    local ink=A.NativeParchment(s.card,kit.C)
    s.title = kit.label(s.card, 16, ink.heading); s.title:SetPoint("TOPLEFT", 12, -12); s.title:SetPoint("TOPRIGHT", -12, -12); s.title:SetJustifyH("LEFT")
    local scroll = CreateFrame("ScrollFrame", nil, s.card, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -48); scroll:SetPoint("BOTTOMRIGHT", -28, 86)
    s.scrollContent = CreateFrame("Frame", nil, scroll); s.scrollContent:SetSize(260, 180)
    s.detail = kit.label(s.scrollContent, 12, ink.ink); s.detail:SetPoint("TOPLEFT"); s.detail:SetJustifyH("LEFT"); s.detail:SetJustifyV("TOP"); scroll:SetScrollChild(s.scrollContent)
    s.show = kit.Button(s.card, "catalogShow", 158, "primary", function()
        local places = spotsFor(mode, s.selected)
        local nearest = M.NearestLayerSpot(places) or places[1]
        if not nearest then return end
        if mode == "gather" then M.SetGatherResource(s.selected.key); M.SetLayer("gather", true)
        elseif mode == "services" then M.SetServicePicked(s.selected.key, true)
        else M.SetLayer("instances", true) end
        M.ShowOnWorldMap({nearest}, nearest.map)
    end)
    s.show:SetPoint("BOTTOMLEFT", 12, 46)
    s.go = kit.Button(s.card, "catalogGo", 158, "ghost", function()
        local nearest = M.NearestLayerSpot(spotsFor(mode, s.selected))
        if nearest then
            nearest.source = {tab = mode, key = s.selected.key}   -- (a click on the arrow comes back to this item)
            M.NavigateLayerSpot(nearest)
        else s.detail:SetText(A.L("catalogNearest")) end
    end)
    s.go:SetPoint("BOTTOMLEFT", 12, 12)
    if mode == "gather" or mode == "services" then
        s.all = kit.Button(frame, mode == "gather" and "catalogAllResources" or "catalogClearPicks", 202, "ghost", function()
            if mode == "gather" then M.SetGatherResource(nil); M.SetLayer("gather", true) else M.ClearServicePicks(); M.WorldCatalogRefresh(frame) end
        end)
        s.all:SetPoint("TOPRIGHT", 0, -36)
        -- everything the list shows at once ("Show all" with a search typed takes what it found)
        local function bulk(on)
            local keys = {}
            for _, item in ipairs(s.results) do keys[#keys + 1] = item.key end
            if mode == "gather" then M.SetGatherKeys(keys, on); if on then M.SetLayer("gather", true) end else M.SetServiceKeys(keys, on) end
            M.WorldCatalogRefresh(frame)
        end
        s.hideAll = kit.Chip(frame, function() bulk(false) end); s.hideAll:SetPoint("TOPRIGHT", 0, 0)
        s.showAll = kit.Chip(frame, function() bulk(true) end); s.showAll:SetPoint("RIGHT", s.hideAll, "LEFT", -6, 0)
    end
    local function layout()
        local width, height = frame:GetWidth(), frame:GetHeight()
        local left = math.max(170, math.min(310, width * 0.45))
        s.list:SetWidth(left)
        s.visibleRows = math.max(3, math.min(MAX_ROWS, math.floor((height - 80) / ROW_HEIGHT)))
        s.detail:SetWidth(math.max(140, width - left - 54))
        s.scrollContent:SetWidth(math.max(140, width - left - 54))
        s.scrollContent:SetHeight(math.max(80, (s.detail:GetStringHeight() or 80) + 12))
        M.WorldCatalogRows(frame)
    end
    frame:SetScript("OnSizeChanged", layout)
    layout()
end

M.worldTabs.gather = {build = function(frame, kit) build(frame, kit, "gather") end, refresh = M.WorldCatalogRefresh}
M.worldTabs.services = {build = function(frame, kit) build(frame, kit, "services") end, refresh = M.WorldCatalogRefresh}
M.worldTabs.instances = {build = function(frame, kit) build(frame, kit, "instances") end, refresh = M.WorldCatalogRefresh}
