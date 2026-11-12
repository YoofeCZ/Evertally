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
function A.RankingRows(kit, mode, dungeon)
    local list = players()
    if dungeon and mode ~= "level" and mode ~= "dungeons" then
        for _, entry in ipairs(list) do
            local runs = {}
            for _, run in ipairs(entry.runs) do if run.name == dungeon then runs[#runs+1] = run end end
            entry.runs, entry.completed = runs, 0
            for _, run in ipairs(runs) do if run.status == "completed" then entry.completed = entry.completed + 1 end end
        end
    end
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

--- Names with an observed completed run, for the dungeon selector. Never implies a complete realm catalogue.
function A.RankingDungeons()
    local names, seen = {}, {}
    for _, player in ipairs(players()) do
        for _, run in ipairs(player.runs) do
            if run.status == "completed" and type(run.name) == "string" and not seen[run.name] then seen[run.name]=true;names[#names+1]=run.name end
        end
    end
    table.sort(names);return names
end

function A.BuildRankingsPage(page, kit)
    local C, ink, muted, heading = kit.C, {0.20,0.12,0.055}, {0.36,0.26,0.14}, {0.42,0.23,0.055}
    A.rankingsPage=page;kit.PageHeader(page,"rankings")
    page.mode,page.chips="runs",{}
    local previous
    for _,mode in ipairs(MODES) do
        local chip=kit.Chip(page,function()page.mode=mode;A.RefreshUI()end)
        if previous then chip:SetPoint("LEFT",previous,"RIGHT",5,0)else chip:SetPoint("TOPLEFT",0,-54)end
        page.chips[mode]=chip;previous=chip
    end
    page.summary=kit.label(page,11,C.mist);page.summary:SetPoint("TOPLEFT",0,-88);page.summary:SetPoint("TOPRIGHT",0,-88)
    page.columns=kit.Columns(page,{2,5},12);page.columns:SetPoint("TOPLEFT",0,-115);page.columns:SetPoint("BOTTOMRIGHT")
    local catalog=kit.Card(page.columns.cells[1]);catalog:SetAllPoints(page.columns.cells[1]);page.catalog=catalog
    page.catalogTitle=kit.label(catalog,13,C.gold);page.catalogTitle:SetPoint("TOPLEFT",12,-12);page.catalogTitle:SetPoint("TOPRIGHT",-12,-12)
    local catalogBody=CreateFrame("Frame",nil,catalog);catalogBody:SetPoint("TOPLEFT",6,-40);catalogBody:SetPoint("BOTTOMRIGHT",-6,6)
    page.dungeonList=kit.ListView(catalogBody,0)
    local board=CreateFrame("Frame",nil,page.columns.cells[2]);board:SetAllPoints(page.columns.cells[2]);A.NativeParchment(board,C);page.board=board
    page.boardTitle=kit.label(board,15,heading);page.boardTitle:SetPoint("TOPLEFT",14,-13);page.boardTitle:SetPoint("TOPRIGHT",-14,-13);page.boardTitle:SetWordWrap(false)
    page.winnerIcon=board:CreateTexture(nil,"ARTWORK");page.winnerIcon:SetSize(36,36);page.winnerIcon:SetPoint("TOPLEFT",14,-42)
    page.winnerName=kit.label(board,14,ink);page.winnerName:SetPoint("TOPLEFT",60,-43);page.winnerName:SetPoint("TOPRIGHT",-100,-43);page.winnerName:SetWordWrap(false)
    page.winnerSub=kit.label(board,10,muted);page.winnerSub:SetPoint("TOPLEFT",60,-63);page.winnerSub:SetPoint("TOPRIGHT",-100,-63);page.winnerSub:SetWordWrap(false)
    page.winnerValue=kit.label(board,20,heading);page.winnerValue:SetPoint("TOPRIGHT",-14,-48);page.winnerValue:SetWidth(90);page.winnerValue:SetJustifyH("RIGHT")
    local rule=board:CreateTexture(nil,"BORDER");rule:SetPoint("TOPLEFT",12,-88);rule:SetPoint("TOPRIGHT",-12,-88);rule:SetHeight(1);kit.paint(rule,heading,0.4)
    local inner=CreateFrame("Frame",nil,board);inner:SetPoint("TOPLEFT",8,-96);inner:SetPoint("BOTTOMRIGHT",-8,8)
    page.scroll=kit.ScrollArea(inner,0);page.rows={}
    page.empty=kit.label(inner,12,muted);page.empty:SetPoint("TOPLEFT",12,-15);page.empty:SetPoint("TOPRIGHT",-12,-15)
    local function newRow()
        local r=CreateFrame("Frame",nil,page.scroll.child);r:SetHeight(48)
        r.bg=kit.fill(r,heading,0.05)
        r.rank=kit.label(r,14,heading);r.rank:SetPoint("LEFT",8,0);r.rank:SetWidth(26)
        r.icon=r:CreateTexture(nil,"ARTWORK");r.icon:SetSize(26,26);r.icon:SetPoint("LEFT",36,0)
        r.name=kit.label(r,12,ink);r.name:SetPoint("TOPLEFT",72,-7);r.name:SetPoint("TOPRIGHT",-90,-7);r.name:SetWordWrap(false)
        r.sub=kit.label(r,10,muted);r.sub:SetPoint("TOPLEFT",72,-25);r.sub:SetPoint("TOPRIGHT",-90,-25);r.sub:SetWordWrap(false)
        r.value=kit.label(r,15,heading);r.value:SetPoint("RIGHT",-10,0);r.value:SetWidth(78);r.value:SetJustifyH("RIGHT")
        return r
    end
    function page.Refresh()
        page.columns.Layout()
        for _,mode in ipairs(MODES)do page.chips[mode].SetLabel(A.L("rankMode"..mode:sub(1,1):upper()..mode:sub(2)));page.chips[mode].SetOn(page.mode==mode)end
        local cs=A.db.settings.language=="cs"
        page.catalogTitle:SetText(cs and "Záznamy dungeonů" or "Dungeon records")
        local choices={{title=cs and "Všechny dungeony" or "All dungeons",icon=kit.ICON.raid,onClick=function()page.dungeon=nil;A.RefreshUI()end}}
        for _,name in ipairs(A.RankingDungeons())do
            local dungeon=name
            choices[#choices+1]={title=kit.plain(name),icon=kit.ICON.run,tag=page.dungeon==name and "•" or nil,onClick=function()page.dungeon=dungeon;page.mode="fastest";A.RefreshUI()end}
        end
        page.dungeonList.SetItems(choices,A.L("rankNoData"))
        local data=A.RankingRows(kit,page.mode,page.dungeon);page.data=data
        local me
        for _,entry in ipairs(data)do if entry.own then me=me or entry end end
        local total=#players()
        page.summary:SetText(total<=1 and A.L("rankYouAlone") or (me and page.mode~="dungeons" and string.format(A.L("rankYou"),me.rank,total) or A.L("sub_rankings")))
        page.boardTitle:SetText(page.dungeon and kit.plain(page.dungeon) or A.L("rankMode"..page.mode:sub(1,1):upper()..page.mode:sub(2)))
        local winner=data[1]
        if winner then
            if winner.character and winner.character.classId then kit.classIcon(page.winnerIcon,winner.character.classId)else kit.setIcon(page.winnerIcon,kit.ICON.run)end
            page.winnerIcon:Show();page.winnerName:SetText(kit.plain(winner.name));page.winnerSub:SetText(winner.sub or "");page.winnerValue:SetText(winner.valueText)
        else page.winnerIcon:Hide();page.winnerName:SetText(A.L("rankNoRuns"));page.winnerSub:SetText("");page.winnerValue:SetText("")end
        for i,entry in ipairs(data)do
            local r=page.rows[i] or newRow();page.rows[i]=r;r.data=entry
            r:ClearAllPoints();r:SetPoint("TOPLEFT",0,-(i-1)*52);r:SetPoint("TOPRIGHT",0,-(i-1)*52)
            r.rank:SetText(tostring(entry.rank or i));r.name:SetText(kit.plain(entry.name));r.sub:SetText(entry.sub or "");r.value:SetText(entry.valueText)
            if entry.character and entry.character.classId then kit.classIcon(r.icon,entry.character.classId)else kit.setIcon(r.icon,kit.ICON.run)end
            kit.paint(r.bg,heading,entry.own and 0.18 or (i%2==0 and 0.065 or 0.035));r:Show()
        end
        for i=#data+1,#page.rows do page.rows[i]:Hide()end
        page.scroll.child:SetHeight(math.max(1,#data*52));page.scroll.UpdateThumb()
        page.empty:SetText(#data==0 and A.L("rankNoData") or "")
    end
end
