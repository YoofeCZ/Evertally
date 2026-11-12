local _, A = ...
-- The Leaderboard page: every player whose addon shared with you, ranked by completed dungeons, by level or by best time, plus the best time in each dungeon.
-- It is a ranking of the players you know, not of the realm, and the page says so.
local text = {
    en = {
        rankings = "Leaderboard", sub_rankings = "Players whose addon shared with you, and you. Not a leaderboard of the whole realm.",
        rankModeRuns = "Dungeons completed", rankModeLevel = "Level", rankModeFastest = "Fastest run", rankModeDungeons = "Best time per dungeon",
        rankYou = "You are #%d of %d", rankYouAlone = "Nobody has shared with you yet. Turn on in-game sharing and play in a group.", rankNoRuns = "You have no completed run with a time yet.",
        rankRuns = "%d completed", rankLevel = "Level %s", rankPlayers = "%d players", rankNoData = "Nothing to rank yet.", rankSelf = "you", rankReceived = "received",
    },
    cs = {
        rankings = "Žebříček", sub_rankings = "Hráči, jejichž addon s tebou sdílel, a ty. Není to žebříček celého serveru.",
        rankModeRuns = "Dokončené dungeony", rankModeLevel = "Úroveň", rankModeFastest = "Nejrychlejší běh", rankModeDungeons = "Nejlepší čas v dungeonu",
        rankYou = "Jsi #%d z %d", rankYouAlone = "Zatím s tebou nikdo nesdílel. Zapni sdílení ve hře a hraj ve skupině.", rankNoRuns = "Zatím nemáš žádný dokončený běh s časem.",
        rankRuns = "dokončeno: %d", rankLevel = "Úroveň %s", rankPlayers = "Hráčů: %d", rankNoData = "Zatím není co řadit.", rankSelf = "ty", rankReceived = "přijato",
    },
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local MODES = {"runs", "level", "fastest", "dungeons"}
local ROW_H = 58

-- every player we know: yourself and each summary somebody sent (one entry per character)
local function players()
    local db, me = A.db, A.Character()
    local list, seen = {}, {}
    local own = {name = me and me.name or "?", character = me, own = true, runs = {}, completed = 0, level = me and me.level}
    for _, run in ipairs(db.runs) do
        if run.character and me and run.character.id == me.id then
            own.runs[#own.runs + 1] = run
            if run.status == "completed" then own.completed = own.completed + 1 end
        end
    end
    list[1] = own
    seen[tostring(db.producerId) .. ":" .. (me and me.id or "unknown")] = true
    for sender, peer in pairs(A.peerDB.peers) do
        local key = tostring(peer.producerId) .. ":" .. (peer.character and peer.character.id or sender)
        if not seen[key] then
            seen[key] = true
            local entry = {name = peer.character and peer.character.name or sender, character = peer.character, runs = peer.runs or {}, receivedAt = peer.receivedAt,
                level = peer.character and peer.character.level, completed = peer.completedRuns}
            if entry.completed == nil then
                entry.completed = 0
                for _, run in ipairs(entry.runs) do if run.status == "completed" then entry.completed = entry.completed + 1 end end
            end
            list[#list + 1] = entry
        end
    end
    return list
end

local function bestRun(entry)
    local best
    for _, run in ipairs(entry.runs) do
        local ms = A.Number(run.durationMs, 1)
        if run.status == "completed" and ms and (not best or ms < best.durationMs) then best = {durationMs = ms, name = run.name, completion = run.completion} end
    end
    return best
end

local function byName(a, b) return tostring(A.Plain(a.name)) < tostring(A.Plain(b.name)) end

--- The ranking for one mode as rows ready to show: {name, character, own, valueText, fraction, sub, rank}.
function A.RankingRows(kit, mode)
    local list = players()
    local rows = {}
    local function source(entry) return entry.own and A.L("rankSelf") or (A.L("rankReceived") .. " " .. kit.stamp(entry.receivedAt)) end
    if mode == "runs" then
        table.sort(list, function(a, b) if a.completed == b.completed then return byName(a, b) end return a.completed > b.completed end)
        local top = math.max(1, list[1].completed)
        for i, e in ipairs(list) do
            rows[i] = {name = e.name, character = e.character, own = e.own, valueText = tostring(e.completed), fraction = e.completed / top, rank = i,
                sub = kit.identityText(e.character) .. "  ·  " .. source(e)}
        end
    elseif mode == "level" then
        table.sort(list, function(a, b) local x, y = a.level or 0, b.level or 0; if x == y then return byName(a, b) end return x > y end)
        local top = math.max(1, list[1].level or 1)
        for i, e in ipairs(list) do
            rows[i] = {name = e.name, character = e.character, own = e.own, valueText = e.level and string.format(A.L("rankLevel"), e.level) or "?", fraction = (e.level or 0) / top, rank = i,
                sub = kit.identityText(e.character) .. "  ·  " .. source(e)}
        end
    elseif mode == "fastest" then
        local timed = {}
        for _, e in ipairs(list) do
            local best = bestRun(e)
            if best then e.best = best; timed[#timed + 1] = e end
        end
        table.sort(timed, function(a, b) if a.best.durationMs == b.best.durationMs then return byName(a, b) end return a.best.durationMs < b.best.durationMs end)
        for i, e in ipairs(timed) do
            rows[i] = {name = e.name, character = e.character, own = e.own, valueText = kit.duration(e.best.durationMs), fraction = timed[1].best.durationMs / e.best.durationMs, rank = i,
                sub = kit.plain(e.best.name) .. "  ·  " .. kit.identityText(e.character)}
        end
    else
        local dungeons, order = {}, {}
        for _, e in ipairs(list) do
            for _, run in ipairs(e.runs) do
                local ms = A.Number(run.durationMs, 1)
                if run.status == "completed" and ms and run.name then
                    local d = dungeons[run.name]
                    if not d then d = {name = run.name, players = {}, count = 0}; dungeons[run.name] = d; order[#order + 1] = d end
                    if not d.players[e] then d.players[e] = true; d.count = d.count + 1 end
                    if not d.best or ms < d.best then d.best, d.who = ms, e end
                end
            end
        end
        table.sort(order, function(a, b) return tostring(A.Plain(a.name)) < tostring(A.Plain(b.name)) end)
        for _, d in ipairs(order) do
            rows[#rows + 1] = {name = d.name, character = d.who.character, own = d.who.own, valueText = kit.duration(d.best), fraction = 1, plainName = true,
                sub = kit.plain(d.who.name) .. "  ·  " .. string.format(A.L("rankPlayers"), d.count)}
        end
    end
    return rows
end

local MEDAL = {"gold", "silver", "bronze"}
local PODIUM_TOP, PODIUM_H = 116, 116

function A.BuildRankingsPage(page, kit)
    local C = kit.C
    A.rankingsPage = page   -- read by the layout preview
    kit.PageHeader(page, "rankings")
    page.mode, page.chips = "runs", {}
    local previous
    for _, mode in ipairs(MODES) do
        local chip = kit.Chip(page, function() page.mode = mode; A.RefreshUI() end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -54) end
        page.chips[mode] = chip; previous = chip
    end
    page.summary = kit.label(page, 12, C.lilac)
    page.summary:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -88); page.summary:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -88)

    -- the first three get a card of their own
    page.podium = kit.Columns(page, {1, 1, 1}, 10)
    page.podium:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -PODIUM_TOP); page.podium:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -PODIUM_TOP); page.podium:SetHeight(PODIUM_H)
    page.cards = {}
    for i = 1, 3 do
        local card = kit.Card(page.podium.cells[i], C.off); card:SetAllPoints(page.podium.cells[i])
        card.tint = card:CreateTexture(nil, "BACKGROUND"); card.tint:SetAllPoints(card)
        card.icon = card:CreateTexture(nil, "ARTWORK"); card.icon:SetSize(44, 44); card.icon:SetPoint("TOPLEFT", 12, -16)
        card.rank = kit.label(card, 18, C.text); card.rank:SetPoint("TOPRIGHT", -12, -14); card.rank:SetJustifyH("RIGHT")
        card.name = kit.label(card, 13, C.text); card.name:SetPoint("TOPLEFT", 66, -18); card.name:SetPoint("TOPRIGHT", -46, -18); card.name:SetWordWrap(false)
        card.sub = kit.label(card, 10, C.mist); card.sub:SetPoint("TOPLEFT", 66, -36); card.sub:SetPoint("TOPRIGHT", -12, -36); card.sub:SetWordWrap(false)
        card.value = kit.label(card, 22, C.text); card.value:SetPoint("BOTTOMLEFT", 12, 24); card.value:SetJustifyH("LEFT")
        card.bar = kit.ProgressBar(card, C.lilac, 4); card.bar:SetPoint("BOTTOMLEFT", 12, 10); card.bar:SetPoint("BOTTOMRIGHT", -12, 10)
        page.cards[i] = card
    end

    page.scroll = kit.ScrollArea(page, 112)
    page.empty = kit.label(page.scroll, 12, C.mist); page.empty:SetPoint("TOPLEFT", 14, -40); page.empty:SetPoint("TOPRIGHT", -14, -40); page.empty:SetJustifyH("CENTER")
    local rows = {}

    local function newRow()
        local r = CreateFrame("Frame", nil, page.scroll.child); r:SetHeight(ROW_H - 4)
        r.bg = kit.fill(r, C.card, 0.55)
        r.mark = r:CreateTexture(nil, "ARTWORK"); r.mark:SetWidth(3); r.mark:SetPoint("TOPLEFT"); r.mark:SetPoint("BOTTOMLEFT"); kit.paint(r.mark, C.lilac)
        r.badge = CreateFrame("Frame", nil, r); r.badge:SetSize(30, 30); r.badge:SetPoint("LEFT", 12, 0)
        r.badge.bg = kit.fill(r.badge, C.off, 1)
        r.badge.text = kit.label(r.badge, 13, C.text); r.badge.text:SetPoint("CENTER"); r.badge.text:SetJustifyH("CENTER")
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(30, 30)
        r.name = kit.label(r, 13, C.text); r.name:SetWordWrap(false)
        r.sub = kit.label(r, 10, C.mist); r.sub:SetWordWrap(false)
        r.value = kit.label(r, 15, C.text); r.value:SetJustifyH("RIGHT"); r.value:SetWidth(100)
        r.bar = kit.ProgressBar(r, C.lilac, 4)
        return r
    end

    local function fillCard(card, row)
        local medal = C[MEDAL[row.rank]] or C.off
        kit.paint(card.accentLine, medal, 0.95)
        local cc = row.character and kit.classColor(row.character.classId) or C.text
        if row.own then kit.paint(card.tint, C.violet, 0.45) else kit.paint(card.tint, medal, 0.07) end
        if row.character and row.character.classId then kit.classIcon(card.icon, row.character.classId) else kit.setIcon(card.icon, kit.ICON.run) end
        card.rank:SetText("#" .. row.rank); card.rank:SetTextColor(medal[1], medal[2], medal[3])
        card.name:SetText(kit.plain(row.name)); card.name:SetTextColor(cc[1], cc[2], cc[3])
        card.sub:SetText(row.sub); card.value:SetText(row.valueText)
        card.bar.Set(row.fraction, medal)
    end

    function page.Refresh()
        for _, mode in ipairs(MODES) do page.chips[mode].SetLabel(A.L("rankMode" .. mode:sub(1, 1):upper() .. mode:sub(2))); page.chips[mode].SetOn(page.mode == mode) end
        local data = A.RankingRows(kit, page.mode)
        local me, total = nil, 0
        for _, row in ipairs(data) do if row.own then me = me or row end end
        if page.mode == "dungeons" then page.summary:SetText("")
        else
            total = #players()
            if total <= 1 then page.summary:SetText(A.L("rankYouAlone"))
            elseif me then page.summary:SetText(string.format(A.L("rankYou"), me.rank, total))
            else page.summary:SetText(A.L("rankNoRuns")) end
        end
        local podiumOn = page.mode ~= "dungeons" and #data > 0
        page.podium:SetShown(podiumOn); page.podium.Layout()
        if podiumOn then
            for i, card in ipairs(page.cards) do
                local row = data[i]
                page.podium.cells[i]:SetShown(row ~= nil)
                if row then fillCard(card, row) end
            end
        end
        local first = podiumOn and 4 or 1
        page.scroll:ClearAllPoints()
        page.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(podiumOn and (PODIUM_TOP + PODIUM_H + 12) or 112)); page.scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -8, 0)
        local shown = 0
        for index = first, #data do
            shown = shown + 1
            local row, r = data[index], rows[shown]
            if not r then r = newRow(); rows[shown] = r end
            r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(shown - 1) * ROW_H); r:SetPoint("TOPRIGHT", 0, -(shown - 1) * ROW_H)
            local ranked = page.mode ~= "dungeons"
            r.badge:SetShown(ranked)
            if ranked then
                kit.paint(r.badge.bg, C.off, 0.6)
                r.badge.text:SetText(tostring(row.rank)); r.badge.text:SetTextColor(C.text[1], C.text[2], C.text[3])
            end
            local left = ranked and 54 or 14
            r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", left, 0)
            if row.character and row.character.classId then kit.classIcon(r.icon, row.character.classId) else kit.setIcon(r.icon, kit.ICON.run) end
            r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", r, "TOPLEFT", left + 40, -9); r.name:SetPoint("TOPRIGHT", r, "TOPRIGHT", -120, -9)
            r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", left + 40, -26); r.sub:SetPoint("TOPRIGHT", r, "TOPRIGHT", -120, -26)
            r.value:ClearAllPoints(); r.value:SetPoint("TOPRIGHT", r, "TOPRIGHT", -14, -10)
            r.bar:ClearAllPoints(); r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", left + 40, 8); r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -14, 8)
            r.name:SetText(kit.plain(row.name)); r.sub:SetText(row.sub); r.value:SetText(row.valueText)
            local cc = (not row.plainName and row.character) and kit.classColor(row.character.classId) or C.text
            r.name:SetTextColor(cc[1], cc[2], cc[3])
            r.mark:SetShown(row.own == true)
            kit.paint(r.bg, row.own and C.violet or C.card, 0.55)
            r.bar.Set(row.fraction, row.own and C.lilac or C.sky)
            r:Show()
        end
        for i = shown + 1, #rows do rows[i]:Hide() end
        page.scroll.child:SetHeight(math.max(1, shown * ROW_H))
        page.empty:SetText(#data == 0 and A.L("rankNoData") or "")
        page.scroll.UpdateThumb()
    end
end
