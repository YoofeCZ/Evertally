local _, M = ...
local A = _G.Evertally
-- The Dungeon Journal page, built like the journal itself: a grid of cards with the dungeon's banner, and inside a dungeon three tabs: Bosses (a list
-- of them with their level; the loot of one as rows with the item's icon, its name in the colour of its quality and its slot; the game's tooltip on the
-- mouse), Quests (the quests of the dungeon: what they ask, who gives them, where to hand them in, what they reward) and Map (the dungeon's map with
-- its bosses, when a map is known). The data is Evertally's own (DungeonData.lua and QuestGuideData.lua, see journal() below), no other add-on is
-- needed; the banner is the instance's loading screen, drawn by the game by its file ID. An instance without data is listed from the entrances.
local CARD_H, GAP, ROW_H, ROWS_MAX = 160, 14, 46, 16
local GOLD = A.Theme and A.Theme.colors.gold or {0.796, 0.651, 0.373}
local QUEST_ICON, BOSS_ICON = "Interface\\GossipFrame\\AvailableQuestIcon", "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"

local text = {
    en = {dungeonsSearch = "Search for dungeons", dungeonsCount = "%d dungeons and raids", dungeonsBosses = "Bosses", dungeonsQuests = "Quests", dungeonsMap = "Map",
        dungeonsBack = "< Dungeons", dungeonsNone = "Nothing found.", dungeonsQuestCount = "%d quests", dungeonsLv = "LV %s", dungeonsFrom = "Available from level %s",
        dungeonsObjective = "Objective", dungeonsStarts = "Starts at", dungeonsTurnin = "Turn in", dungeonsChoose = "Choose one reward", dungeonsAlso = "You will also receive",
        dungeonsLoot = "Loot", dungeonsNoLoot = "No loot is listed.", dungeonsNoBosses = "No bosses are listed for this one.", dungeonsNoQuests = "No quests are listed for this one.",
        dungeonsNoMap = "There is no map for this dungeon.", dungeonsEntrance = "Entrance", dungeonsShow = "Show the entrance on the map", dungeonsGo = "Navigate to the entrance", dungeonsGuide = "Attunements and quest runs",
        dungeonsNoJournal = "Evertally has no list of bosses, loot and quests for this one yet.",
        dungeonsFaction = "%s only", dungeonsInDb = "Open the quest in the database", dungeonsPlayers = "%d players", dungeonsIn = "In %s",
        dungeonsLevel = "Level %s", dungeonsPickup = "From", dungeonsRewards = "Reward", dungeonsNpcInDb = "Open the boss in the database",
        dungeonsFloor = "Floor %d", dungeonsLearned = "level seen in the game"},
    cs = {dungeonsSearch = "Hledat dungeony", dungeonsCount = "Dungeonů a raidů: %d", dungeonsBosses = "Bossové", dungeonsQuests = "Questy", dungeonsMap = "Mapa",
        dungeonsBack = "< Dungeony", dungeonsNone = "Nic nenalezeno.", dungeonsQuestCount = "Questů: %d", dungeonsLv = "LV %s", dungeonsFrom = "Dostupné od úrovně %s",
        dungeonsObjective = "Cíl", dungeonsStarts = "Začíná u", dungeonsTurnin = "Odevzdat u", dungeonsChoose = "Vyber jednu odměnu", dungeonsAlso = "Dostaneš také",
        dungeonsLoot = "Loot", dungeonsNoLoot = "Žádný loot není uvedený.", dungeonsNoBosses = "U tohohle nejsou uvedení žádní bossové.", dungeonsNoQuests = "U tohohle nejsou uvedené žádné questy.",
        dungeonsNoMap = "Pro tenhle dungeon není mapa.", dungeonsEntrance = "Vchod", dungeonsShow = "Ukázat vchod na mapě", dungeonsGo = "Navigovat ke vchodu", dungeonsGuide = "Attunementy a questy",
        dungeonsNoJournal = "Pro tenhle Evertally zatím nemá seznam bossů, lootu a questů.",
        dungeonsFaction = "Jen %s", dungeonsInDb = "Otevřít quest v databázi", dungeonsPlayers = "Hráčů: %d", dungeonsIn = "V %s",
        dungeonsLevel = "Úroveň %s", dungeonsPickup = "Od", dungeonsRewards = "Odměna", dungeonsNpcInDb = "Otevřít bosse v databázi",
        dungeonsFloor = "Patro %d", dungeonsLearned = "úroveň viděná ve hře"},
}
for lang, entries in pairs(text) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

-- ---------------------------------------------------------------- the data
-- Evertally's own journal (no other add-on needed): dungeons, bosses and loot from DungeonData.lua (AtlasLoot facts), the quests of
-- each dungeon from QuestGuideData.lua (QuestieDB facts), the art a loading screen the game draws by file ID, boss levels, portraits
-- (a model the game draws by its display ID) and the floor maps (tiles the game draws by file ID, a mark where each boss stands).
-- Built once, in the shape the page reads (DB, BOSS_LEVELS, DUNGEON_HOME_ART, DUNGEON_HOME_TEXCOORD, DUNGEON_MAPS, QUEST_PREREQ_CHAINS).
local CLASS_BITS = {{1, "Warrior"}, {2, "Paladin"}, {4, "Hunter"}, {8, "Rogue"}, {16, "Priest"}, {64, "Shaman"}, {128, "Mage"}, {256, "Warlock"}, {1024, "Druid"}}
local function classesOf(mask)
    mask = tonumber(mask) or 0
    if mask <= 0 then return nil end
    local names, all = {}, true
    for _, c in ipairs(CLASS_BITS) do if math.floor(mask / c[1]) % 2 == 1 then names[#names + 1] = c[2] else all = false end end
    return not all and #names > 0 and table.concat(names, ", ") or nil
end
local function person(list)
    local p = type(list) == "table" and list[1]
    if type(p) ~= "table" then return nil, nil end
    local spot = type(p.spots) == "table" and type(p.spots[1]) == "table" and p.spots[1] or nil
    local zone = spot and M.MapName and M.MapName(spot.map)
    local name = A.Text(p.name, 80)
    return name and zone and zone ~= "" and (name .. ", " .. zone) or name, spot
end
-- Evertally Guide's Codex (the Evertally_Guide add-ons, from Polestar): its dungeon pages add the quests our catalogue lacks
-- (Forever's new ones with their rewards, XP and where they start), and a level where AtlasLoot gives none. Its instances are
-- whole (Dire Maul, Scarlet Monastery, Stratholme, Blackrock Spire): a wing of ours takes only the quests of its own bosses.
local FORK_ALIAS = {["stockade"] = "stormwind stockade", ["temple of ahnqiraj"] = "ahnqiraj temple", ["shapers terrace"] = "shapers terrace"}
local function norm(name)
    name = tostring(name or ""):lower():gsub("^the ", ""):gsub("[^%w ]", ""):gsub("%s+", " ")
    return FORK_ALIAS[name] or name
end
local function wholeOf(name)
    local base = tostring(name):match("^(.-):") or tostring(name):gsub("^Lower ", ""):gsub("^Upper ", "")
    return norm(base), base ~= name
end
local function forkDungeons()
    local guide = rawget(_G, "EvertallyGuide")
    local D = type(guide) == "table" and guide.Dungeons
    if type(D) ~= "table" or type(D.Load) ~= "function" or type(D.List) ~= "function" or type(D.Quests) ~= "function" then return nil end
    local ok, loaded = pcall(D.Load)
    if not (ok and loaded) then return nil end
    local keys = {}
    for _, entry in ipairs(D.List() or {}) do if type(entry) == "table" and entry.key then keys[norm(entry.name)] = entry end end
    return D, keys
end
local function forkPerson(p)
    if type(p) ~= "table" then return nil, nil end
    local spot = tonumber(p.map) and tonumber(p.x) and tonumber(p.y) and {map = tonumber(p.map), x = tonumber(p.x) / 100, y = tonumber(p.y) / 100} or nil
    local zone = spot and M.MapName and M.MapName(spot.map)
    local name = A.Text(p.name, 80)
    return name and zone and zone ~= "" and (name .. ", " .. zone) or name, spot
end
local function forkQuest(D, key, q)
    local choice, also = {}, {}
    for _, item in ipairs(type(q.rewards) == "table" and type(q.rewards.items) == "table" and q.rewards.items or {}) do
        local row = {item.id, item.name, item.quality, 1}
        if item.choice then choice[#choice + 1] = row else also[#also + 1] = row end
    end
    local pickup, pickupSpot = forkPerson(q.start)
    local turnin, turninSpot = forkPerson(q.finish)
    local quest = {id = q.id, name = q.title, level = q.level, requires = q.minLevel, faction = q.faction == "A" and "Alliance" or q.faction == "H" and "Horde" or "Both",
        objective = D.ObjectiveText and D.ObjectiveText(q) or nil, pickup = pickup, pickupSpot = pickupSpot, turnin = turnin, turninSpot = turninSpot,
        xp = type(q.rewards) == "table" and q.rewards.xp or nil, money = type(q.rewards) == "table" and q.rewards.money or nil,
        startsInDungeon = q.inside == true or nil, fromGuide = true}
    if #choice > 0 then quest.rewardItems, quest.rewardChoice = choice, true; if #also > 0 then quest.additionalRewardItems = also end
    elseif #also > 0 then quest.rewardItems, quest.rewardChoice = also, false end
    local before = {}
    for _, id in ipairs(type(q.chain) == "table" and q.chain or {}) do
        local prior = D.Quest and D.Quest(key, id)
        if type(prior) == "table" and prior.title then before[#before + 1] = {id = id, name = prior.title} end
    end
    return quest, #before > 0 and before or nil
end
local own
local function journal()
    if own then return own end
    if type(M.dungeonData) ~= "table" then return nil end
    local quests = type(A.questGuideData) == "table" and type(A.questGuideData.quests) == "table" and A.questGuideData.quests or {}
    local byDungeon, chains = {}, {}
    for id, q in pairs(quests) do
        if type(q) == "table" and type(q.dungeon) == "string" then
            local pickup, pickupSpot = person(q.starts)
            local turnin, turninSpot = person(q.ends)
            local list = byDungeon[q.dungeon] or {}; byDungeon[q.dungeon] = list
            list[#list + 1] = {id = id, name = q.title, level = q.level, requires = q.minLevel, faction = q.faction or "Both", objective = q.text,
                pickup = pickup, pickupSpot = pickupSpot, turnin = turnin, turninSpot = turninSpot, classOnly = classesOf(q.classMask)}
            -- the quests to finish first, by their titles in the same catalogue
            local before = {}
            for _, key in ipairs({"requiresAll", "requiresAny"}) do
                for _, pre in ipairs(type(q[key]) == "table" and q[key] or {}) do
                    local title = type(quests[pre]) == "table" and quests[pre].title
                    if title then before[#before + 1] = {id = pre, name = title} end
                end
            end
            if #before > 0 then chains[id] = before end
        end
    end
    local db, art, coords, levels, maps = {}, {}, {}, {}, {}
    local fork, forkKeys = forkDungeons()
    local allFloors = type(M.dungeonFloors) == "table" and M.dungeonFloors or {}
    for name, d in pairs(M.dungeonData) do
        local bosses, bossLevels, marks, onFloor = {}, {}, {}, {}
        for _, b in ipairs(d.bosses or {}) do
            local loot = {}
            for _, row in ipairs(b.loot or {}) do loot[#loot + 1] = {row[1], row[2] or ("#" .. tostring(row[1])), row[3] ~= "" and row[3] or nil, row[4] or 1} end
            bosses[#bosses + 1] = {name = b.name, npcID = b.npc, loot = loot, display = b.display}
            if type(b.level) == "table" and b.level[1] then
                bossLevels[b.name] = b.level[1] == b.level[2] and tostring(b.level[1]) or (tostring(b.level[1]) .. "-" .. tostring(b.level[2]))
            end
            if type(b.pos) == "table" and b.pos[1] then marks[#marks + 1] = {name = b.name, at = b.pos[1], x = b.pos[2], y = b.pos[3]}; onFloor[b.pos[1]] = true end
        end
        levels[name] = bossLevels
        -- the floors this one uses (the wings of an instance share its floors: a wing shows those its bosses stand on)
        local source = d.floors and allFloors[d.floors]
        if type(source) == "table" and #marks > 0 then
            local floors, index = {}, {}
            for i, floor in ipairs(source) do
                if onFloor[i] then floors[#floors + 1] = floor; index[i] = #floors end
            end
            for _, mark in ipairs(marks) do mark.floor = index[mark.at] end
            maps[name] = {floors = floors, bosses = marks}
        end
        local list = byDungeon[name] or {}
        -- what the guide's Codex knows about this one that our catalogue does not
        local whole, wing = wholeOf(name)
        local forkEntry = fork and (forkKeys[norm(name)] or forkKeys[whole])
        if forkEntry then
            local have, ours = {}, {}
            for _, q in ipairs(list) do have[q.id] = true end
            for _, b in ipairs(d.bosses or {}) do ours[b.name] = true end
            for _, q in ipairs(fork.Quests(forkEntry.key) or {}) do
                local mine = not wing
                if wing then for _, boss in ipairs(type(q.bosses) == "table" and q.bosses or {}) do if ours[boss] then mine = true end end end
                if type(q) == "table" and tonumber(q.id) and not have[q.id] and mine then
                    local quest, before = forkQuest(fork, forkEntry.key, q)
                    list[#list + 1] = quest; have[q.id] = true
                    if before then chains[q.id] = before end
                end
            end
            if not d.level and tonumber(forkEntry.minLevel) and tonumber(forkEntry.maxLevel) then d = setmetatable({level = {forkEntry.minLevel, forkEntry.minLevel, forkEntry.maxLevel}}, {__index = d}) end
        end
        table.sort(list, function(a, b) if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end; return tostring(a.name) < tostring(b.name) end)
        local level = d.level and (d.level[2] == d.level[3] and tostring(d.level[2]) or (tostring(d.level[2]) .. "-" .. tostring(d.level[3]))) or ""
        db[name] = {level = level, location = "", isRaid = d.raid, bosses = bosses, quests = list}
        -- a loading screen is 4:3: the card shows its middle band
        if d.art then art[name] = d.art; coords[name] = {0, 1, 0.22, 0.72} end
    end
    own = {DB = db, BOSS_LEVELS = levels, DUNGEON_MAPS = maps, DUNGEON_HOME_ART = art, DUNGEON_HOME_TEXCOORD = coords, QUEST_PREREQ_CHAINS = chains, own = true}
    M.ownJournal = own
    return own
end
M.Journal = journal
local function firstNumber(level) return tonumber(tostring(level or ""):match("^(%d+)")) or 0 end

--- The dungeons and raids, lowest level first: {key, name, level, min, location, icon, source, data, banner, texcoord, quests}. From Evertally's
--- own journal, else (the data file missing) from the instances Evertally has the entrances of.
function M.DungeonList()
    local out, fdj = {}, journal()
    if fdj then
        for name, d in pairs(fdj.DB) do
            if type(d) == "table" and type(name) == "string" then
                local art = type(fdj.DUNGEON_HOME_ART) == "table" and fdj.DUNGEON_HOME_ART[name] or nil
                local coords = type(fdj.DUNGEON_HOME_TEXCOORD) == "table" and fdj.DUNGEON_HOME_TEXCOORD[name] or nil
                -- the place: where Evertally knows the entrance (the zone of the instance with this name)
                if d.location == "" and M.Instances and M.MapName then
                    for _, item in ipairs(M.Instances(name, "all") or {}) do if item.map and item.name:lower() == name:lower() then d.location = M.MapName(item.map) or ""; break end end
                end
                -- (an instance without a level, the raids, comes after all those with one)
                local min = firstNumber(d.level)
                out[#out + 1] = {key = name, name = name, level = tostring(d.level or ""), min = min > 0 and min or 99, location = type(d.location) == "string" and d.location or "",
                    icon = d.icon, source = "journal", data = d, banner = art, texcoord = coords, quests = type(d.quests) == "table" and #d.quests or 0}
            end
        end
    elseif M.Instances then
        for _, item in ipairs(M.Instances("", "all")) do
            local level = item.level and (tostring(item.level[1]) .. "-" .. tostring(item.level[2])) or ""
            out[#out + 1] = {key = item.key, name = item.name, level = level, min = item.level and item.level[1] or 0, location = item.map and M.MapName(item.map) or "", source = "layer", item = item, quests = 0}
        end
    end
    table.sort(out, function(a, b) if a.min ~= b.min then return a.min < b.min end return a.name < b.name end)
    return out
end

local function matches(entry, query)
    if query == "" then return true end
    return entry.name:lower():find(query, 1, true) ~= nil or (entry.location or ""):lower():find(query, 1, true) ~= nil
end

--- The entrance of a dungeon on the map, when Evertally has it: the instance with the same name.
local function entranceOf(entry)
    if entry.item and entry.item.map then return entry.item end
    for _, item in ipairs(M.Instances and M.Instances(entry.name, "all") or {}) do
        if item.map and item.name:lower() == entry.name:lower() then return item end
    end
    for _, item in ipairs(M.Instances and M.Instances(entry.name, "all") or {}) do if item.map then return item end end
end

--- The quests of the dungeon journal by id, as rows for the record window (a quest QuestieDB does not know is often there).
function M.DungeonQuestRows(id)
    local fdj = journal()
    if not fdj then return nil end
    for dungeon, d in pairs(fdj.DB) do
        for _, quest in ipairs(type(d) == "table" and type(d.quests) == "table" and d.quests or {}) do
            if quest.id == id then
                local rows = {{title = A.Plain(quest.name or ("#" .. tostring(id))), sub = A.Plain(tostring(dungeon) .. (quest.level and ("  ·  " .. string.format(A.L("dungeonsLevel"), quest.level)) or ""))}}
                local function add(label, value)
                    if type(value) == "string" and value ~= "" then rows[#rows + 1] = {title = A.Plain(value), sub = A.L(label)} end
                end
                add("dungeonsObjective", quest.objective); add("dungeonsPickup", quest.pickup); add("dungeonsTurnin", quest.turnin); add("dungeonsRewards", (quest.rewards or ""):gsub("\n", "  ·  "))
                return rows
            end
        end
    end
end

local function portraitOf(boss) return boss.customIcon or BOSS_ICON end
--- Draws the boss on `texture`: the game's portrait of its model when the journal knows the model, else the skull.
local function paintBoss(texture, boss)
    local display = boss and tonumber(boss.display)
    if display and type(SetPortraitTextureFromCreatureDisplayID) == "function" and pcall(SetPortraitTextureFromCreatureDisplayID, texture, display) then
        texture:SetTexCoord(0, 1, 0, 1); return
    end
    texture:SetTexture(portraitOf(boss or {})); texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end
M.PaintBoss = paintBoss
-- what the game showed of a boss the data has no level for (Forever's own dungeons): its NPC ID -> level, -1 for a skull ("??")
local function learned() return A.db and type(A.db.bossLevels) == "table" and A.db.bossLevels or nil end
--- A boss's level: the journal's, else the one the game showed when the player saw it.
local function bossLevel(entry, boss)
    local fdj = journal()
    local levels = fdj and type(fdj.BOSS_LEVELS) == "table" and fdj.BOSS_LEVELS[entry.name]
    local level = type(levels) == "table" and levels[boss.name] or nil
    if level then return level end
    local seen = boss.npcID and learned() and learned()[boss.npcID]
    if seen then return seen == -1 and "??" or tostring(seen), true end
end
--- Remembers the level of a boss the player sees (target or mouse-over) when the journal has none for it.
local wanted
function M.LearnBossLevel(unit)
    if not A.db then return end
    if not wanted then
        wanted = {}
        local fdj = journal()
        for name, d in pairs(fdj and fdj.DB or {}) do
            local levels = fdj.BOSS_LEVELS and fdj.BOSS_LEVELS[name] or {}
            for _, b in ipairs(d.bosses or {}) do if b.npcID and not levels[b.name] then wanted[b.npcID] = true end end
        end
    end
    local guid = A.Text(A.Call(UnitGUID, unit), 100)
    if not guid then return end
    local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    npc = tonumber(npc)
    if kind ~= "Creature" or not npc or not wanted[npc] then return end
    local level = A.Number(A.Call(UnitLevel, unit), -1, 999)
    if not level or level == 0 then return end
    A.db.bossLevels = A.db.bossLevels or {}
    A.db.bossLevels[npc] = level
    return level
end
do
    local watcher = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT"}) do pcall(watcher.RegisterEvent, watcher, event) end
    watcher:SetScript("OnEvent", function(_, event) pcall(M.LearnBossLevel, event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover") end)
end
--- The map of a dungeon with its floors and boss marks, when the journal has one.
local function mapOf(entry)
    local fdj = journal()
    local data = entry and fdj and type(fdj.DUNGEON_MAPS) == "table" and fdj.DUNGEON_MAPS[entry.name]
    return type(data) == "table" and type(data.floors) == "table" and data.floors[1] and data or nil
end

-- ---------------------------------------------------------------- the detail of a boss and of a quest
local function showBoss(dj, boss)
    local d = dj.detail
    d.SetTheme("parchment"); d.Reset("boss:" .. tostring(boss.npcID or boss.name)); d.model = nil
    local level, seen = bossLevel(dj.selected, boss)
    d.PortraitHeader(tostring(boss.name or "?") .. (level and ("   " .. string.format(A.L("dungeonsLv"), level)) or ""), portraitOf(boss))
    if d.portrait and d.portrait.icon then paintBoss(d.portrait.icon, boss) end
    if seen then d.Text(A.L("dungeonsLearned"), d.ink) end
    if boss.description then d.Text(boss.description) end
    if M.DungeonGuide then M.DungeonGuide.RenderBoss(d, dj.selected, boss) end
    d.Head(A.L("dungeonsLoot"))
    local shown = 0
    for _, item in ipairs(type(boss.loot) == "table" and boss.loot or {}) do
        local id = type(item) == "table" and tonumber(item[1])
        if id then
            shown = shown + 1
            d.Link({icon = M.ItemLook(id), title = item[2] or ("#" .. id), sub = item[3], quality = item[4], itemId = id, extra = item[3],
                onClick = function() if A.OpenDatabaseEntry then A.OpenDatabaseEntry("item", id) end end})
        end
    end
    if shown == 0 then d.Text(A.L("dungeonsNoLoot"), d.ink) end
    if tonumber(boss.npcID) then
        d.Link({icon = BOSS_ICON, title = A.L("dungeonsNpcInDb"), sub = "#" .. boss.npcID,
            onClick = function() if A.OpenDatabaseEntry then A.OpenDatabaseEntry("npc", tonumber(boss.npcID)) end end})
    end
    d.Done()
end

local function showQuest(dj, quest)
    local d = dj.detail
    M.RenderQuestCard(d, M.JournalQuestModel(quest))
    if tonumber(quest.id) then
        d.Link({icon = QUEST_ICON, title = A.L("dungeonsInDb"), sub = "#" .. quest.id, onClick = function() if A.OpenDatabaseEntry then A.OpenDatabaseEntry("quest", tonumber(quest.id)) end end})
        d.Done()
    end
end

-- ---------------------------------------------------------------- the map of a dungeon: the art of its floor and a numbered mark for each boss
local function drawMap(dj)
    local m = dj.map
    for _, tile in ipairs(m.tiles) do tile:Hide() end
    for _, mark in ipairs(m.marks) do mark:Hide() end
    m.single:Hide(); m.note:SetText("")
    local data = mapOf(dj.selected)
    -- a button for each floor when there are more of them
    local count = data and #data.floors or 0
    for i = 1, math.max(count, #m.floorChips) do
        local chip = m.floorChips[i]
        if i <= count and count > 1 then
            if not chip then
                chip = dj.kit.Chip(dj.mapArea, function() dj.floorIndex = i; drawMap(dj) end)
                if i == 1 then chip:SetPoint("TOPLEFT", 0, 0) else chip:SetPoint("LEFT", m.floorChips[i - 1], "RIGHT", 6, 0) end
                m.floorChips[i] = chip
            end
            local label = data.floors[i].name
            chip.SetLabel(label and label ~= "" and A.Plain(label) or string.format(A.L("dungeonsFloor"), i)); chip.SetOn(i == (dj.floorIndex or 1)); chip:Show()
        elseif chip then chip:Hide() end
    end
    local floor = data and data.floors and data.floors[dj.floorIndex or 1]
    if not floor then m.note:SetText(A.L("dungeonsNoMap")); return end
    local aspect = floor.texture and (1 / (floor.texBottom or 1)) or 1002 / 668
    -- (room for the floor buttons above the map)
    local top = count > 1 and 32 or 0
    local w, h = m.area:GetWidth() or 400, (m.area:GetHeight() or 300) - top
    local mw = math.min(w, h * aspect); local mh = mw / aspect
    m.frame:ClearAllPoints(); m.frame:SetSize(mw, mh); m.frame:SetPoint("CENTER", m.area, "CENTER", 0, -top / 2)
    if floor.texture then
        m.single:SetTexture(floor.texture); m.single:SetTexCoord(0, 1, 0, floor.texBottom or 1); m.single:Show()
    elseif floor.tiles then
        for i = 1, 12 do
            local tile = m.tiles[i]
            local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", m.frame, "TOPLEFT", col * 256 / 1002 * mw, -row * 256 / 668 * mh)
            tile:SetSize(math.min(256, 1002 - col * 256) / 1002 * mw, math.min(256, 668 - row * 256) / 668 * mh)
            tile:SetTexture(type(floor.tiles) == "table" and floor.tiles[i] or (tostring(floor.tiles) .. i))
            tile:SetTexCoord(0, col == 3 and (1002 - 768) / 256 or 1, 0, row == 2 and (668 - 512) / 256 or 1)
            tile:Show()
        end
    end
    local at = 0
    -- the number of a mark is the boss's place in the Bosses list
    local order = {}
    local byName = {}
    for i, b in ipairs(dj.selected and dj.selected.data and dj.selected.data.bosses or {}) do order[b.name] = i; byName[b.name] = b end
    for i, boss in ipairs(data.bosses or {}) do
        if (boss.floor or 1) == (dj.floorIndex or 1) and tonumber(boss.x) and tonumber(boss.y) then
            at = at + 1
            local mark = m.marks[at]
            if not mark then
                -- the boss's portrait in a gold ring, its number in the Bosses list in a small badge at the bottom
                mark = CreateFrame("Button", nil, m.frame)
                mark:SetSize(34, 34)
                mark.ring = mark:CreateTexture(nil, "BACKGROUND"); mark.ring:SetPoint("TOPLEFT", -2, 2); mark.ring:SetPoint("BOTTOMRIGHT", 2, -2)
                mark.ring:SetTexture("Interface\\AddOns\\Evertally_Map\\Media\\dot"); mark.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
                mark.bg = mark:CreateTexture(nil, "ARTWORK"); mark.bg:SetAllPoints()
                mark.round = mark.CreateMaskTexture and mark:CreateMaskTexture() or nil
                if mark.round then
                    mark.round:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); mark.round:SetAllPoints(mark.bg)
                    pcall(mark.bg.AddMaskTexture, mark.bg, mark.round)
                end
                mark.badge = mark:CreateTexture(nil, "OVERLAY"); mark.badge:SetSize(15, 15); mark.badge:SetPoint("BOTTOMRIGHT", 4, -4)
                mark.badge:SetTexture("Interface\\AddOns\\Evertally_Map\\Media\\dot"); mark.badge:SetVertexColor(0.12, 0.09, 0.06)
                mark.num = dj.kit.label(mark, 9, {1, 0.86, 0.5}); mark.num:SetPoint("CENTER", mark.badge, "CENTER", 0, 0); mark.num:SetJustifyH("CENTER")
                mark:SetScript("OnEnter", function(self) if GameTooltip then pcall(function() GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.bossName or "?"); GameTooltip:Show() end) end end)
                mark:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                mark:SetScript("OnClick", function(self) if dj.OpenBossByName then dj.OpenBossByName(self.bossName) end end)
                m.marks[at] = mark
            end
            mark.bossName = boss.name
            paintBoss(mark.bg, byName[boss.name] or {name = boss.name})
            mark.num:SetText(tostring(order[boss.name] or i))
            mark:ClearAllPoints(); mark:SetPoint("CENTER", m.frame, "TOPLEFT", math.max(0, math.min(1, boss.x)) * mw, -math.max(0, math.min(1, boss.y)) * mh)
            mark:Show()
        end
    end
end

-- ---------------------------------------------------------------- the home grid and the dungeon view
local function layout(dj)
    local body = dj.body
    local width, height = body:GetWidth() or 640, body:GetHeight() or 420
    dj.w, dj.h = width, height
    dj.scroll:ClearAllPoints(); dj.scroll:SetPoint("TOPLEFT", 0, -40); dj.scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    dj.gridWidth = math.max(300, width - 30)
    dj.cols = dj.gridWidth >= 620 and 2 or 1
    dj.cardW = math.floor((dj.gridWidth - GAP * (dj.cols - 1)) / dj.cols)
    dj.listWidth = math.max(175, math.min(280, width * 0.33))
    dj.list:SetWidth(dj.listWidth)
    dj.visibleRows = math.max(1, math.min(ROWS_MAX, math.floor((height - 130) / ROW_H)))
    dj.detail.SetWidth(width - dj.listWidth - 12 - 40)
    dj.mapArea:ClearAllPoints(); dj.mapArea:SetPoint("TOPLEFT", 0, -86); dj.mapArea:SetPoint("BOTTOMRIGHT", 0, 44)
    local actionWidth = math.min(240, (width - 16) / 3)
    dj.show:SetWidth(actionWidth); dj.go:SetWidth(actionWidth); if dj.attune then dj.attune:SetWidth(actionWidth) end
    dj.box:SetWidth(math.max(170, math.min(300, width * 0.48)))
end

-- The same dungeon in Evertally Guide's Dungeons (the fork of Polestar): its attunements and keys, per-character
-- quest state and the guides that pick the quests up and hand them in. Evertally's journal keeps the bosses, loot,
-- floor maps and tactics; the guide's page is one click away. -> its key, or nil (no guide, no such dungeon).
function M.GuideDungeonKey(entry)
    local g = rawget(_G, "EvertallyGuide")
    local D = type(g) == "table" and g.Dungeons
    if type(D) ~= "table" or type(D.Find) ~= "function" or type(D.Open) ~= "function" or not entry then return nil end
    if D.Load then pcall(D.Load) end
    local names = {}
    for _, name in pairs({entry.name, entry.key, type(entry.name) == "string" and entry.name:match("^(.-)%s*[:%-]") or nil}) do names[#names + 1] = name end
    for _, name in ipairs(names) do
        if type(name) == "string" and name ~= "" then
            local ok, key = pcall(D.Find, name)
            if ok and key then return key end
        end
    end
    return nil
end

local function refreshCards(dj)
    local cols, cardW = dj.cols or 2, dj.cardW or 300
    for i, card in ipairs(dj.cards) do
        local entry = dj.results[i]
        card.entry = entry
        card:SetShown(entry ~= nil and dj.mode == "home")
        if entry then
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", dj.grid, "TOPLEFT", ((i - 1) % cols) * (cardW + GAP), -math.floor((i - 1) / cols) * (CARD_H + GAP))
            card:SetSize(cardW, CARD_H)
            if entry.banner then
                card.art:SetTexture(entry.banner)
                local c = entry.texcoord
                if type(c) == "table" then card.art:SetTexCoord(c[1], c[2], c[3], c[4]) else card.art:SetTexCoord(0, 1, 0, 1) end
                card.art:SetVertexColor(1, 1, 1)
            else
                card.art:SetTexture(entry.icon or M.guideQuestion); card.art:SetTexCoord(0.2, 0.8, 0.2, 0.8); card.art:SetVertexColor(0.55, 0.55, 0.65)
            end
            card.title:SetText(A.Plain(entry.name))
            card.level:SetText(entry.level ~= "" and string.format(A.L("dungeonsLv"), entry.level) or "")
            card.quests:SetText(entry.quests and entry.quests > 0 and string.format(A.L("dungeonsQuestCount"), entry.quests) or "")
            card.location:SetText(A.Plain(entry.location or ""))
        end
    end
    local rows = math.ceil(#dj.results / cols)
    dj.grid:SetSize(dj.gridWidth or 600, math.max(60, rows * (CARD_H + GAP)))
end

local function refreshList(dj)
    local items = dj.items or {}
    for i, row in ipairs(dj.rows) do
        local item = items[dj.offset + i]
        row.item = item
        row:SetShown(item ~= nil and i <= dj.visibleRows and dj.mode == "dungeon" and dj.tab ~= "map")
        if item then
            if item.boss then paintBoss(row.icon, item.boss) else row.icon:SetTexture(item.icon or BOSS_ICON); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            row.name:SetText(A.Plain(item.title)); row.sub:SetText(A.Plain(item.sub or "")); row.badge:SetText(item.badge or "")
            row.bg:SetAlpha(item == dj.chosen and 0.18 or 0.025)
            row.accent:SetShown(item == dj.chosen)
            row.sub:SetShown(item.sub ~= nil and item.sub ~= "")
        end
    end
end

local function chooseItem(dj, item)
    dj.chosen = item
    if item then
        if dj.tab == "bosses" then showBoss(dj, item.boss) elseif dj.tab == "quests" then showQuest(dj, item.quest)
        elseif dj.tab == "guide" and M.DungeonGuide then M.DungeonGuide.Render(dj.detail, dj.selected, item.section) end
    else
        dj.detail.SetTheme("parchment"); dj.detail.Reset(); dj.detail.Text(A.L(dj.tab == "bosses" and "dungeonsNoBosses" or "dungeonsNoQuests")); dj.detail.Done()
    end
    refreshList(dj)
end

local function detailShown(dj, on)
    dj.panel:SetShown(on); dj.detail.scroll:SetShown(on); dj.detail.surface:SetShown(on and dj.detail.theme == "quest")
end

local function setTab(dj, tab)
    dj.tab = tab
    local entry = dj.selected
    local d = entry and entry.data
    dj.items, dj.offset, dj.chosen = {}, 0, nil
    if entry and entry.source == "journal" and d then
        if tab == "guide" and M.DungeonGuide then
            for _, section in ipairs(M.DungeonGuide.Sections(M.DungeonGuide.Of(entry.name))) do
                dj.items[#dj.items + 1] = {title = section.title, icon = section.icon, section = section.key}
            end
        elseif tab == "bosses" then
            for _, boss in ipairs(type(d.bosses) == "table" and d.bosses or {}) do
                local level = bossLevel(entry, boss)
                dj.items[#dj.items + 1] = {title = boss.name or "?", icon = portraitOf(boss), badge = level and ("LV " .. level) or "", boss = boss}
            end
        elseif tab == "quests" then
            for _, quest in ipairs(type(d.quests) == "table" and d.quests or {}) do
                local sub = quest.requires and string.format(A.L("dungeonsFrom"), quest.requires) or nil
                if quest.faction and quest.faction ~= "Both" then sub = (sub and (sub .. "  ·  ") or "") .. string.format(A.L("dungeonsFaction"), quest.faction) end
                dj.items[#dj.items + 1] = {title = quest.name or "?", icon = QUEST_ICON, sub = sub, quest = quest}
            end
        end
    end
    local isMap = tab == "map"
    dj.list:SetShown(dj.mode == "dungeon" and not isMap); detailShown(dj, dj.mode == "dungeon" and not isMap); dj.listBg:SetShown(dj.mode == "dungeon" and not isMap)
    dj.mapArea:SetShown(dj.mode == "dungeon" and isMap)
    for key, chip in pairs(dj.tabs) do chip.SetOn(key == tab) end
    if isMap then drawMap(dj) else chooseItem(dj, dj.items[1]) end
    refreshList(dj)
end

local function showMode(dj)
    local home = dj.mode == "home"
    dj.scroll:SetShown(home); dj.box:SetShown(home); dj.count:SetShown(home)
    dj.head:SetShown(not home)
    dj.show:SetShown(not home and dj.entrance ~= nil); dj.go:SetShown(not home and dj.entrance ~= nil)
    dj.guideKey = not home and M.GuideDungeonKey(dj.selected) or nil
    if dj.attune then dj.attune:SetShown(dj.guideKey ~= nil) end
    if home then dj.list:Hide(); dj.listBg:Hide(); detailShown(dj, false); dj.mapArea:Hide() end
    refreshCards(dj)
end

local function openDungeon(dj, entry)
    dj.selected, dj.mode, dj.floorIndex = entry, "dungeon", 1
    dj.title:SetText(A.Plain(entry.name))
    local bits = {}
    if entry.level ~= "" then bits[#bits + 1] = string.format(A.L("dungeonsLevel"), entry.level) end
    if entry.location ~= "" then bits[#bits + 1] = entry.location end
    dj.subtitle:SetText(A.Plain(table.concat(bits, "  ·  ")))
    dj.entrance = entranceOf(entry)
    dj.noJournal:SetShown(entry.source ~= "journal")
    showMode(dj)
    local hasData = entry.source == "journal"
    -- the Map tab only where there is a map to show
    for key, chip in pairs(dj.tabs) do chip:SetShown(hasData and (key ~= "map" or mapOf(entry) ~= nil)) end
    if hasData then setTab(dj, M.DungeonGuide and "guide" or "bosses")
    else
        dj.list:Hide(); dj.listBg:Hide(); dj.mapArea:Hide(); dj.detail.SetTheme("parchment"); detailShown(dj, true); dj.detail.Reset()
        local item = entry.item
        if item then
            dj.detail.Text(string.format(A.L("dungeonsPlayers"), item.players or 0))
            if item.map then dj.detail.Text(string.format(A.L("dungeonsIn"), M.MapName(item.map))) end
        end
        dj.detail.Done()
    end
end

local function refresh(dj)
    local language = A.db and A.db.settings.language or "en"
    local languageChanged = dj.language ~= language
    dj.language = language
    local query = (dj.query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    dj.results = {}
    for _, entry in ipairs(M.DungeonList()) do if matches(entry, query) then dj.results[#dj.results + 1] = entry end end
    dj.count:SetText(#dj.results > 0 and string.format(A.L("dungeonsCount"), #dj.results) or A.L("dungeonsNone"))
    for key, chip in pairs(dj.tabs) do chip.SetLabel(A.L(key == "guide" and "dgGuide" or key == "bosses" and "dungeonsBosses" or key == "quests" and "dungeonsQuests" or "dungeonsMap")) end
    dj.back.text:SetText(A.L("dungeonsBack")); dj.show.text:SetText(A.L("dungeonsShow")); dj.go.text:SetText(A.L("dungeonsGo")); if dj.attune then dj.attune.text:SetText(A.L("dungeonsGuide")) end
    dj.noJournal:SetText(A.L("dungeonsNoJournal"))
    layout(dj)
    -- a narrower or wider detail wraps its texts again: what is shown is drawn again so nothing lies on top of the next line
    local width = dj.detail.width
    if dj.detailWidth and dj.detailWidth ~= width and dj.mode == "dungeon" and dj.chosen and dj.tab ~= "map" then dj.detailWidth = width; chooseItem(dj, dj.chosen) end
    dj.detailWidth = width
    if dj.mode == "dungeon" and dj.selected then
        -- (only the words are written again: the tab, the boss or quest and the scrolling stay as they are)
        for _, entry in ipairs(M.DungeonList()) do
            if entry.key == dj.selected.key then
                if languageChanged and dj.chosen then chooseItem(dj, dj.chosen) end
                return
            end
        end
        dj.mode = "home"
    end
    showMode(dj)
end

function M.BuildDungeons(body, kit)
    local C = kit.C
    local dj = {kit = kit, body = body, mode = "home", tab = "bosses", results = {}, rows = {}, cards = {}, offset = 0, visibleRows = 8, query = "", items = {}, cols = 2, cardW = 300}
    body.dungeons = dj
    function dj.OpenBossByName(name)
        setTab(dj, "bosses")
        for index, item in ipairs(dj.items) do
            if item.title == name then
                dj.offset = math.max(0, math.min(index - 1, math.max(0, #dj.items - dj.visibleRows)))
                chooseItem(dj, item)
                return true
            end
        end
        return false
    end
    -- home: the search and the grid of cards
    dj.box = kit.SearchBox(body, 260, function(value) dj.query = value or ""; refresh(dj) end)
    dj.box:SetPoint("TOPLEFT", 0, -4); dj.box:SetMaxLetters(60); dj.box.hint:SetText(A.L("dungeonsSearch"))
    dj.count = kit.label(body, 11, C.mist); dj.count:SetPoint("LEFT", dj.box, "RIGHT", 12, 0)
    dj.scroll = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
    dj.grid = CreateFrame("Frame", nil, dj.scroll); dj.grid:SetSize(600, 400); dj.scroll:SetScrollChild(dj.grid)
    for i = 1, 60 do
        local card = CreateFrame("Button", nil, dj.grid)
        card.bg = kit.fill(card, C.card, 1)
        kit.outline(card, C.line or C.gold)
        card.art = card:CreateTexture(nil, "ARTWORK"); card.art:SetPoint("TOPLEFT", 2, -2); card.art:SetPoint("BOTTOMRIGHT", -2, 2)
        card.shade = card:CreateTexture(nil, "OVERLAY"); card.shade:SetPoint("BOTTOMLEFT", 2, 2); card.shade:SetPoint("BOTTOMRIGHT", -2, 2); card.shade:SetHeight(34); kit.paint(card.shade, C.well, 0.96)
        card.top = card:CreateTexture(nil, "OVERLAY"); card.top:SetPoint("TOPLEFT", 2, -2); card.top:SetPoint("TOPRIGHT", -2, -2); card.top:SetHeight(40); kit.paint(card.top, C.header or C.well, 0.96)
        card.rule = card:CreateTexture(nil, "OVERLAY"); card.rule:SetPoint("TOPLEFT", 2, -42); card.rule:SetPoint("TOPRIGHT", -2, -42); card.rule:SetHeight(1); kit.paint(card.rule, C.gold, 0.55)
        card.title = card:CreateFontString(nil, "OVERLAY"); card.title:SetFont(kit.fontPath(), 16, ""); card.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
        card.title:SetPoint("TOPLEFT", 12, -12); card.title:SetPoint("TOPRIGHT", -100, -12); card.title:SetJustifyH("LEFT"); card.title:SetWordWrap(false)
        card.quests = card:CreateFontString(nil, "OVERLAY"); card.quests:SetFont(kit.fontPath(), 11, ""); card.quests:SetTextColor(C.mist[1], C.mist[2], C.mist[3], 1)
        card.quests:SetPoint("TOPRIGHT", -12, -14); card.quests:SetJustifyH("RIGHT")
        card.level = card:CreateFontString(nil, "OVERLAY"); card.level:SetFont(kit.fontPath(), 11, ""); card.level:SetTextColor(C.bright[1], C.bright[2], C.bright[3], 1)
        card.level:SetPoint("BOTTOMLEFT", 12, 11); card.level:SetJustifyH("LEFT")
        card.location = kit.label(card, 11, C.text); card.location:SetPoint("BOTTOMLEFT", 95, 11); card.location:SetPoint("BOTTOMRIGHT", -12, 11); card.location:SetWordWrap(false); card.location:SetJustifyH("RIGHT")
        local hover = card:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(card); kit.paint(hover, C.gold, 0.10)
        card:SetScript("OnClick", function(self) if self.entry then openDungeon(dj, self.entry) end end)
        card:Hide()
        dj.cards[i] = card
    end
    -- a dungeon: the header with the way back and the tabs
    dj.head = CreateFrame("Frame", nil, body); dj.head:SetPoint("TOPLEFT"); dj.head:SetPoint("TOPRIGHT"); dj.head:SetHeight(80)
    dj.back = kit.Button(dj.head, "dungeonsBack", 110, "ghost", function() dj.mode = "home"; showMode(dj) end); dj.back:SetPoint("TOPLEFT", 0, -2)
    dj.title = kit.label(dj.head, 21, C.bright or C.gold); dj.title:SetPoint("TOPLEFT", dj.back, "TOPRIGHT", 14, -2); dj.title:SetPoint("RIGHT", -4, 0); dj.title:SetWordWrap(false); dj.title:SetJustifyH("LEFT")
    dj.subtitle = kit.label(dj.head, 11, C.mist); dj.subtitle:SetPoint("TOPLEFT", dj.back, "TOPRIGHT", 14, -29); dj.subtitle:SetPoint("RIGHT", -4, 0); dj.subtitle:SetWordWrap(false); dj.subtitle:SetJustifyH("LEFT")
    dj.tabs = {}
    local previous
    for _, key in ipairs({"guide", "bosses", "quests", "map"}) do
        local chip = kit.Chip(dj.head, function() setTab(dj, key) end)
        if previous then chip:SetPoint("LEFT", previous, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 0, -48) end
        dj.tabs[key] = chip; previous = chip
    end
    dj.noJournal = kit.label(dj.head, 11, C.peach); dj.noJournal:SetPoint("TOPLEFT", 0, -48); dj.noJournal:SetPoint("TOPRIGHT", 0, -48); dj.noJournal:SetWordWrap(true); dj.noJournal:Hide()
    dj.head:Hide()
    -- a dungeon: the list on the left (bosses or quests) and the detail on the right
    dj.list = CreateFrame("Frame", nil, body); dj.list:SetPoint("TOPLEFT", 0, -86); dj.list:SetPoint("BOTTOMLEFT", 0, 44); dj.list:SetWidth(240)
    dj.list:EnableMouse(true); if dj.list.EnableMouseWheel then dj.list:EnableMouseWheel(true) end
    dj.list:SetScript("OnMouseWheel", function(_, delta)
        dj.offset = math.max(0, math.min(math.max(0, #dj.items - dj.visibleRows), dj.offset - delta * 2)); refreshList(dj)
    end)
    for i = 1, ROWS_MAX do
        local row = CreateFrame("Button", nil, dj.list); row:SetHeight(ROW_H - 3)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        row.bg = kit.fill(row, C.gold, 1); row.bg:SetAlpha(0.025)
        row.accent = row:CreateTexture(nil, "OVERLAY"); row.accent:SetPoint("TOPLEFT"); row.accent:SetPoint("BOTTOMLEFT"); row.accent:SetWidth(2); kit.paint(row.accent, C.gold, 1); row.accent:Hide()
        local hover = row:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(row); kit.paint(hover, C.gold, 0.10)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(26, 26); row.icon:SetPoint("LEFT", 6, 0); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.badge = kit.label(row, 10, C.gold or GOLD); row.badge:SetPoint("RIGHT", -8, 0); row.badge:SetJustifyH("RIGHT")
        row.name = kit.label(row, 13, C.text); row.name:SetPoint("TOPLEFT", 40, -6); row.name:SetPoint("RIGHT", row.badge, "LEFT", -4, 0); row.name:SetWordWrap(false); row.name:SetJustifyH("LEFT")
        row.sub = kit.label(row, 11, C.mist); row.sub:SetPoint("BOTTOMLEFT", 40, 5); row.sub:SetPoint("BOTTOMRIGHT", -6, 5); row.sub:SetWordWrap(false); row.sub:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self) if self.item then chooseItem(dj, self.item) end end)
        row:Hide()
        dj.rows[i] = row
    end
    local edge = C.line or C.gold
    dj.listBg = CreateFrame("Frame", nil, body); dj.listBg:SetFrameLevel(math.max(0, (dj.list:GetFrameLevel() or 1) - 1))
    dj.listBg:SetPoint("TOPLEFT", dj.list, "TOPLEFT", -3, 3); dj.listBg:SetPoint("BOTTOMRIGHT", dj.list, "BOTTOMRIGHT", 3, -3)
    kit.fill(dj.listBg, C.well, 1); kit.outline(dj.listBg, edge); dj.listBg:Hide()
    dj.panel = CreateFrame("Frame", nil, body)
    dj.panel:SetPoint("TOPLEFT", dj.list, "TOPRIGHT", 12, 3); dj.panel:SetPoint("BOTTOMRIGHT", 0, 44)
    A.NativeParchment(dj.panel,C)
    dj.panel:Hide()
    dj.detail = M.GuideDetail(kit, body)
    dj.detail.scroll:SetPoint("TOPLEFT", dj.panel, "TOPLEFT", 10, -10); dj.detail.scroll:SetPoint("BOTTOMRIGHT", dj.panel, "BOTTOMRIGHT", -28, 10)
    dj.detail.scroll:Hide()
    dj.show = kit.Button(body, "dungeonsShow", 230, "primary", function()
        local item = dj.entrance
        if item and M.ShowOnWorldMap then M.ShowOnWorldMap({{map = item.map, x = item.x, y = item.y, title = dj.selected and dj.selected.name or item.name}}, item.map) end
    end)
    dj.show:SetPoint("BOTTOMLEFT", 0, 4); dj.show:Hide()
    dj.go = kit.Button(body, "dungeonsGo", 230, "ghost", function()
        local item = dj.entrance
        if item and M.NavigateLayerSpot then M.NavigateLayerSpot({map = item.map, x = item.x, y = item.y, title = dj.selected and dj.selected.name or item.name, source = {dungeon = dj.selected and dj.selected.key}}) end
    end)
    dj.go:SetPoint("BOTTOMLEFT", dj.show, "BOTTOMRIGHT", 8, 0); dj.go:Hide()
    dj.attune = kit.Button(body, "dungeonsGuide", 230, "ghost", function()
        local g = rawget(_G, "EvertallyGuide")
        if dj.guideKey and g and g.Dungeons then pcall(g.Dungeons.Open, dj.guideKey) end
    end)
    dj.attune:SetPoint("BOTTOMLEFT", dj.go, "BOTTOMRIGHT", 8, 0); dj.attune:Hide()
    -- the map tab
    dj.mapArea = CreateFrame("Frame", nil, body); dj.mapArea:Hide()
    local m = {area = dj.mapArea, tiles = {}, marks = {}, floorChips = {}}
    m.frame = CreateFrame("Frame", nil, dj.mapArea); m.frame:SetSize(400, 300)
    m.single = m.frame:CreateTexture(nil, "ARTWORK"); m.single:SetAllPoints(); m.single:Hide()
    for i = 1, 12 do m.tiles[i] = m.frame:CreateTexture(nil, "ARTWORK"); m.tiles[i]:Hide() end
    m.note = kit.label(dj.mapArea, 12, C.mist); m.note:SetPoint("TOPLEFT", 0, -10)
    dj.map = m
    body:SetScript("OnSizeChanged", function()
        layout(dj)
        if dj.mode == "dungeon" then
            if dj.tab == "map" then drawMap(dj)
            elseif dj.chosen then chooseItem(dj, dj.chosen) end
            refreshList(dj)
        else refreshCards(dj) end
    end)
    layout(dj)
    return dj
end

function M.RefreshDungeons(body)
    local dj = body.dungeons
    if dj then refresh(dj) end
end

--- Opens the journal on one dungeon by its name (the arrow's click on a journey to a dungeon's entrance).
function M.OpenDungeonEntry(name)
    if A.ShowView then A.ShowView("dungeons") end
    local body = A.dungeonsBody
    local dj = body and body.dungeons
    if not dj then return false end
    dj.query = ""; if dj.box then dj.box:SetText("") end
    refresh(dj)
    for _, entry in ipairs(dj.results) do if entry.key == name then openDungeon(dj, entry); return true end end
    return false
end
