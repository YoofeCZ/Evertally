local _, M = ...
local A = _G.Evertally
-- Building blocks the guide pages (database, dungeon journal) share: a scrolling detail made of headings, text and rows with an icon that can be
-- clicked (a quest -> the person who gives it -> his other quests -> an item -> who sells it), and the colour of an item's quality. The rows are
-- pooled, so opening one entry after another costs nothing.
local ROW_H, ICON = 40, 30
local QUALITY = {[0] = {0.62, 0.62, 0.62}, [1] = {1, 1, 1}, [2] = {0.12, 1, 0.1}, [3] = {0.25, 0.6, 1}, [4] = {0.72, 0.4, 1}, [5] = {1, 0.55, 0.1}, [6] = {0.9, 0.8, 0.5}}
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
M.guideQuestion = QUESTION

function M.QualityColor(quality) return QUALITY[tonumber(quality) or 1] or QUALITY[1] end

--- The icon of an item by id (the game's own file), and its quality (nil until the client has the item in its cache).
function M.ItemLook(id)
    local icon = A.Call(GetItemIcon, id)
    if not icon and C_Item then icon = A.Call(C_Item.GetItemIconByID, id) end
    local quality
    if C_Item and C_Item.GetItemQualityByID then quality = A.Call(C_Item.GetItemQualityByID, id) end
    if quality == nil and type(GetItemInfo) == "function" then local ok, _, _, q = pcall(GetItemInfo, id); if ok then quality = q end end
    return icon or QUESTION, quality
end

--- The name of an item: from QuestieDB when it is there, else from the game, else its number.
function M.ItemName(id)
    if M.Db and M.Db.Open then
        M.guideDb = M.guideDb or M.Db.Open()
        local values = M.guideDb and M.Db.Get(M.guideDb, "item", id)
        if values and type(values.name) == "string" then return values.name end
    end
    local ok, name = pcall(GetItemInfo or function() end, id)
    return ok and type(name) == "string" and name or ("#" .. tostring(id))
end

--- The game's tooltip for an item, placed by `owner`.
function M.ShowItemTooltip(owner, id, name, extra)
    if not (GameTooltip and id) then return end
    pcall(function()
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. id)
        if (GameTooltip.NumLines and GameTooltip:NumLines() or 1) == 0 then GameTooltip:SetText(name or "?") end
        if extra and extra ~= "" then GameTooltip:AddLine(extra, 0.7, 0.7, 0.78) end
        GameTooltip:Show()
    end)
end

--- A scrolling detail inside `parent`. d.Reset(); d.Head(text); d.Text(text[, color, size]); d.Link(spec); d.Done().
--- Link spec: {icon, title, sub, color, onClick, itemId, extra, badge}. The detail scrolls with the wheel and a scroll bar.
function M.GuideDetail(kit, parent)
    local C = kit.C
    local d = {pools = {text = {}, link = {}}, used = {text = 0, link = 0}, y = 0, width = 360}
    d.scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    d.content = CreateFrame("Frame", nil, d.scroll); d.content:SetSize(360, 100); d.scroll:SetScrollChild(d.content)

    local function textLine()
        d.used.text = d.used.text + 1
        local fs = d.pools.text[d.used.text]
        if not fs then fs = kit.label(d.content, 12, C.text); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP"); d.pools.text[d.used.text] = fs end
        fs:Show()
        return fs
    end
    local function linkRow()
        d.used.link = d.used.link + 1
        local row = d.pools.link[d.used.link]
        if not row then
            row = CreateFrame("Button", nil, d.content)
            row:SetHeight(ROW_H - 4)
            row.bg = kit.fill(row, {1, 1, 1}, 1); row.bg:SetAlpha(0.05)
            local hover = row:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(row); kit.paint(hover, {1, 1, 1}, 0.07)
            row.border = row:CreateTexture(nil, "BORDER"); row.border:SetSize(ICON + 4, ICON + 4); row.border:SetPoint("LEFT", 4, 0)
            row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(ICON, ICON); row.icon:SetPoint("LEFT", 6, 0); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.title = kit.label(row, 12, C.text); row.title:SetPoint("TOPLEFT", ICON + 16, -6); row.title:SetPoint("TOPRIGHT", -34, -6); row.title:SetWordWrap(false); row.title:SetJustifyH("LEFT")
            row.sub = kit.label(row, 10, C.mist); row.sub:SetPoint("BOTTOMLEFT", ICON + 16, 5); row.sub:SetPoint("BOTTOMRIGHT", -34, 5); row.sub:SetWordWrap(false); row.sub:SetJustifyH("LEFT")
            row.badge = kit.label(row, 11, C.mist); row.badge:SetPoint("RIGHT", -10, 0); row.badge:SetJustifyH("RIGHT")
            row:SetScript("OnEnter", function(self) if self.spec and self.spec.itemId then M.ShowItemTooltip(self, self.spec.itemId, self.spec.title, self.spec.extra) end end)
            row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            row:SetScript("OnClick", function(self) if self.spec and self.spec.onClick then self.spec.onClick() end end)
            d.pools.link[d.used.link] = row
        end
        row:Show()
        return row
    end

    function d.SetWidth(width)
        d.width = math.max(160, width)
        d.content:SetWidth(d.width)
    end
    function d.Reset()
        for _, fs in ipairs(d.pools.text) do fs:Hide() end
        for _, row in ipairs(d.pools.link) do row:Hide() end
        d.used.text, d.used.link, d.y = 0, 0, 0
    end
    function d.Text(value, color, size)
        local fs = textLine()
        fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", d.content, "TOPLEFT", 0, -d.y); fs:SetWidth(d.width)
        fs:SetFont(kit.fontPath(), size or 12, "")
        local c = color or C.text
        fs:SetTextColor(c[1], c[2], c[3], 1)
        fs:SetText(value or "")
        d.y = d.y + math.max(14, fs:GetStringHeight() or 14) + 6
        return fs
    end
    function d.Head(value) d.y = d.y + 6; return d.Text(value, C.lilac, 13) end
    function d.Link(spec)
        local row = linkRow()
        row.spec = spec
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", d.content, "TOPLEFT", 0, -d.y); row:SetPoint("TOPRIGHT", d.content, "TOPRIGHT", 0, -d.y)
        row.icon:SetTexture(spec.icon or QUESTION)
        local q = spec.quality
        row.border:SetShown(q ~= nil)
        if q ~= nil then local c = M.QualityColor(q); kit.paint(row.border, c, 1) end
        local c = spec.color or (q ~= nil and M.QualityColor(q)) or C.text
        row.title:SetTextColor(c[1], c[2], c[3], 1)
        row.title:SetText(A.Plain(spec.title or "?")); row.sub:SetText(A.Plain(spec.sub or "")); row.badge:SetText(spec.badge or "")
        row.sub:SetShown(spec.sub ~= nil and spec.sub ~= "")
        d.y = d.y + ROW_H
        return row
    end
    function d.Done()
        d.content:SetHeight(math.max(60, d.y + 8))
        d.scroll:SetVerticalScroll(0)
    end
    return d
end
