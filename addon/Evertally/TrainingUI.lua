local _, A = ...
local MODES = {"ready", "later", "pet", "quest", "all"}
A.locale.en.trainingSearch="Search abilities…";A.locale.cs.trainingSearch="Hledat schopnosti…"

function A.BuildTrainingPage(page, kit)
    local T, C = A.Training, kit.C
    A.trainingPage = page
    kit.PageHeader(page, "training")
    local prefs = T.State()
    page.mode, page.query, page.showKnown = prefs.mode or "ready", prefs.query or "", prefs.showKnown == true
    page.filters = {}
    local previous
    for _, mode in ipairs(MODES) do
        local picked = mode
        local button = kit.Button(page, nil, 83, "ghost", function()
            page.mode, page.selectedId = picked, nil; T.State().mode = picked; page.Refresh()
        end)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("TOPLEFT", 0, -55) end
        page.filters[mode] = button; previous = button
    end
    page.search = kit.SearchBox(page, 210, function(value)
        page.query = value; T.State().query = value; page.Refresh()
    end)
    page.search:SetPoint("TOPLEFT", 0, -91)
    page.known = kit.Button(page, nil, 158, "ghost", function()
        page.showKnown = not page.showKnown; T.State().showKnown = page.showKnown; page.Refresh()
    end)
    page.known:SetPoint("TOPRIGHT", 0, -89)
    page.summaryCard = kit.Card(page, C.gold); page.summaryCard:SetPoint("TOPLEFT", 0, -123); page.summaryCard:SetPoint("TOPRIGHT", 0, -123); page.summaryCard:SetHeight(36)
    page.summary = kit.label(page.summaryCard, 12, C.bright or C.gold); page.summary:SetPoint("TOPLEFT", 10, -8); page.summary:SetPoint("TOPRIGHT", -10, -8); page.summary:SetHeight(28); page.summary:SetWordWrap(true)
    page.book = kit.Book(page, 168); page.book:SetPoint("BOTTOMRIGHT", 0, 44)
    page.list = kit.ListView(page.book.index, 0, nil, true)
    page.document = kit.Document(page.book.paper)
    page.navigate = kit.Button(page, "trainingNavigate", 180, "primary", function()
        local row = page.selected
        local kind = row and row.tome and "GRIMOIRE" or row and row.pet and "PET" or page.mode == "pet" and T.Model().class == "HUNTER" and "PET" or nil
        local ok, reason = T.Navigate(kind)
        if not ok then A.Print(A.L(reason == "map_off" and "navErr_map_off" or "trainingNoTrainer")) end
    end)
    page.navigate:SetPoint("BOTTOMRIGHT", 0, 2)
    page.priceHint = kit.label(page, 11, C.mist)
    page.priceHint:SetPoint("BOTTOMLEFT", 0, 7); page.priceHint:SetPoint("BOTTOMRIGHT", page.navigate, "BOTTOMLEFT", -10, 0)
    page.priceHint:SetWordWrap(true)
    local function money(copper) return A.FormatMoney and A.FormatMoney(copper) or tostring(copper or 0) end
    local function selectedDetail(row)
        if not row then return {key = "training-empty", title = A.L("training"), entries = {{text = A.L("trainingChoose")}}} end
        local entries = {{head = true, text = string.format(A.L("trainingLevel"), row.level)}, {text = A.L("training_" .. row.status)}}
        if row.rank and row.rank ~= "" then entries[#entries + 1] = {text = row.rank} end
        if row.price ~= nil then
            entries[#entries + 1] = {head = true, text = A.L(row.priceSource == "observed" and "trainingObserved" or "trainingBase")}
            entries[#entries + 1] = {text = money(row.price)}
        end
        if row.missingId then
            local info = T.SpellInfo(row.missingId)
            entries[#entries + 1] = {text = string.format(A.L("trainingPrerequisite"), info.name), icon = info.icon}
        end
        if row.pet or row.tome then entries[#entries + 1] = {text = A.L("trainingPetHint")} end
        if row.tome then entries[#entries + 1] = {text = A.L("trainingTomeVendor") .. ": " .. (row.family or ""), icon = row.icon, itemId = row.itemId} end
        if row.quest then
            entries[#entries + 1] = {head = true, text = A.L("trainingQuestSource")}
            for _, id in ipairs(row.quests or {}) do
                local questId = id
                entries[#entries + 1] = {text = string.format(A.L("trainingOpenQuest"), id), icon = kit.ICON.quest, onClick = function()
                    if A.OpenDatabaseEntry then A.OpenDatabaseEntry("quest", questId) end
                end}
            end
        end
        if row.status == "unknown" then entries[#entries + 1] = {text = A.L("training_unknown")} end
        entries[#entries + 1] = {text = A.L("trainingCostHint"), color = kit.ParchmentText and kit.ParchmentText.mutedInk}
        return {key = "training:" .. tostring(row.id), title = row.name, subtitle = row.family, entries = entries}
    end
    function page.Refresh()
        local model, rows = T.Model(), T.Rows(page.mode, page.query, page.showKnown)
        page.search.hint:SetText(A.L("trainingSearch"))
        for _, mode in ipairs(MODES) do
            local button = page.filters[mode]; button.text:SetText(A.L("training_" .. mode))
            local color = mode == page.mode and (C.bright or C.gold) or C.mist; button.text:SetTextColor(unpack(color))
        end
        page.known.text:SetText(A.L(page.showKnown and "trainingHideKnown" or "trainingShowKnown"))
        page.navigate.text:SetText(A.L("trainingNavigate"))
        page.summary:SetText(model.available and (string.format(A.L("trainingSummary"), model.readyCount, money(model.total)) .. " · " .. A.L(model.affordable and "trainingEnough" or "trainingNotEnough")) or A.L("trainingMissingData"))
        page.priceHint:SetText(A.L(model.observedCount > 0 and model.baseCount == 0 and "trainingObserved" or "trainingBase"))
        local items, selected = {}, nil
        for _, source in ipairs(rows) do
            local row = source
            if row.id == page.selectedId then selected = row end
            items[#items + 1] = {title = row.name, icon = row.icon, sub = string.format(A.L("trainingLevel"), row.level) .. " · " .. (row.rank and row.rank ~= "" and row.rank or A.L("training_" .. row.status)),
                right = row.price ~= nil and money(row.price) or "", itemId = row.itemId,
                titleColor = row.status == "ready" and C.green or row.status == "known" and C.mist or C.text,
                onClick = function() page.selectedId = row.id; page.Refresh() end}
        end
        page.list.SetItems(items, model.available and A.L("trainingEmpty") or A.L("trainingMissingData"))
        selected = selected or rows[1]; page.selected = selected; page.selectedId = selected and selected.id
        page.document.Set(selectedDetail(selected))
    end
    local function layout()
        local width = tonumber(page:GetWidth()) or 640; if width < 300 then width = 640 end
        local tabWidth = math.min(108, (width - 16) / #MODES)
        for _, mode in ipairs(MODES) do page.filters[mode]:SetWidth(tabWidth) end
        page.search:SetWidth(math.max(180, math.min(300, width * .56)))
        page.known:SetWidth(math.max(150, math.min(190, width * .36)))
        if page.document.spec then page.document.Set(page.document.spec) end
    end
    page.book.onLayout = layout
    page.Layout = function() if page.book.Layout then page.book.Layout() end; layout() end
end
