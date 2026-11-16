local _, A = ...
-- Short notes to the player's own group, signed "(via Evertally)", the way other quest addons do it: a quest handed in
-- (and that it is in the chronicle on the website, when the player publishes it), a dungeon finished with its time, a boss
-- down with the time since the start, a new level and a better item from loot. Only to the party, raid or instance group
-- the player is in, never to /say or public channels, and at most one message every two seconds. On by default; one
-- switch in Settings turns it off. Chat text cannot carry colours, so the note starts with the blue square raid mark.
local N = {queue = {}}
A.Announce = N
local words = {
    en = {partyAnnounce = "Tell my group about quests, dungeon times, bosses, levels and upgrades (signed “via Evertally”)",
        annVia = "(via Evertally)", annQuest = "Quest done: %s", annChronicle = "in my chronicle on evertally.afstudio.dev",
        annRun = "%s cleared in %s", annBest = "personal best", annBoss = "%s down at %s", annLevel = "Level %d!",
        annUpgrade = "Better gear: %s (%+.1f for %s)"},
    cs = {partyAnnounce = "Hlásit skupině questy, časy dungeonů, bosse, levely a lepší výbavu (s podpisem „přes Evertally“)",
        annVia = "(přes Evertally)", annQuest = "Hotový quest: %s", annChronicle = "v mé Kronice na evertally.afstudio.dev",
        annRun = "%s dokončeno za %s", annBest = "osobní rekord", annBoss = "%s padl v čase %s", annLevel = "Level %d!",
        annUpgrade = "Lepší výbava: %s (%+.1f pro %s)"},
}
local brag = {
    en = {bragPrompt = "Offer to brag in /say or the guild after a level, a cleared dungeon or a record (one click)",
        bragSay = "Say", bragGuild = "Guild", bragTitle = "Brag about it?", bragNever = "Don't offer again",
        bragOff = "The brag offer is off. Settings > Sharing in game turns it back on.",
        bragLevel = "Just hit level %d!", bragRun = "Cleared %s in %s!", bragBest = "Cleared %s in %s, a new personal best!",
        bragFollow = "Follow my journey in my chronicle on evertally.afstudio.dev"},
    cs = {bragPrompt = "Po levelu, dungeonu nebo rekordu nabídnout pochlubení do /say nebo guildy (jedním kliknutím)",
        bragSay = "Říct do /say", bragGuild = "Do guildy", bragTitle = "Pochlubit se?", bragNever = "Už nenabízet",
        bragOff = "Nabídka pochlubení je vypnutá. Zapneš ji v Nastavení > Sdílení ve hře."},
}
for lang, entries in pairs(brag) do for key, value in pairs(entries) do words[lang][key] = value end end
words.en.annAccepted = "Quest accepted: %s"; words.en.annReady = "Quest objectives done: %s"; words.en.annObjective = "%s: %s"
words.cs.annAccepted = "Přijatý quest: %s"; words.cs.annReady = "Splněné cíle questu: %s"
words.en.quietDone = "Evertally now tells your group about quests; %s no longer sends its own group messages, so they are not doubled. Turning Evertally's group messages off gives them back."
words.cs.quietDone = "Evertally teď hlásí skupině questy; %s už své zprávy do skupiny neposílá, aby se nezdvojovaly. Vypnutím hlášení v Evertally se mu vrátí."
for lang, entries in pairs(words) do for key, value in pairs(entries) do A.locale[lang][key] = value end end

local MARK, GAP, MAX_QUEUE = "{rt6} ", 2, 8
-- The group may not share the player's language: what goes into the chat is always English. Only the switch in
-- Settings follows the addon language.
local function EN(key) return A.locale.en[key] or key end

function N.Enabled() return A.db ~= nil and A.db.settings.partyAnnounce ~= false end
function N.SetEnabled(on)
    if not A.db then return end
    A.db.settings.partyAnnounce = on == true
    if on then N.QuietOthers() else N.RestoreOthers() end
end

-- Questie and QuestMaster send their own quest lines to the group. While Evertally announces, their group messages are
-- turned off (in their own saved settings, which they expose: Questie.db.profile, QuestMaster.db.profile.announce), the
-- values they had are kept, and they come back when Evertally's announcing is switched off. Only these keys are touched.
local QM_KEYS = {"accept", "complete", "abandon", "itemStarts", "progress", "progressGroup", "levelUpChat"}
local function questieProfile() local q = rawget(_G, "Questie"); return type(q) == "table" and type(q.db) == "table" and type(q.db.profile) == "table" and q.db.profile or nil end
local function questMasterAnnounce()
    local qm = rawget(_G, "QuestMaster"); local profile = type(qm) == "table" and type(qm.db) == "table" and qm.db.profile
    return type(profile) == "table" and type(profile.announce) == "table" and profile.announce or nil
end
local function kept() local s = A.db.settings; if type(s.quieted) ~= "table" then s.quieted = {} end; return s.quieted end
function N.QuietOthers()
    if not A.db or not N.Enabled() then return {} end
    local store, changed = kept(), {}
    local questie = questieProfile()
    if questie and questie.questAnnounceChannel ~= "disabled" then
        if store.questie == nil then store.questie = questie.questAnnounceChannel or "party" end
        questie.questAnnounceChannel = "disabled"; changed[#changed + 1] = "Questie"
    end
    local announce = questMasterAnnounce()
    if announce then
        local touched = false
        store.questMaster = type(store.questMaster) == "table" and store.questMaster or {}
        for _, key in ipairs(QM_KEYS) do
            if announce[key] == true then
                if store.questMaster[key] == nil then store.questMaster[key] = true end
                announce[key] = false; touched = true
            end
        end
        if touched then changed[#changed + 1] = "QuestMaster" end
    end
    if #changed > 0 then A.Print(string.format(A.L("quietDone"), table.concat(changed, ", "))) end
    return changed
end
function N.RestoreOthers()
    if not A.db or type(A.db.settings.quieted) ~= "table" then return end
    local store = A.db.settings.quieted
    local questie = questieProfile()
    if questie and store.questie ~= nil then questie.questAnnounceChannel = store.questie end
    local announce = questMasterAnnounce()
    if announce and type(store.questMaster) == "table" then for key, value in pairs(store.questMaster) do announce[key] = value end end
    A.db.settings.quieted = nil
end

-- The group the player is in: a raid, an instance group (dungeon finder) or a home party. Nothing when alone.
function N.Channel()
    if A.Call(IsInRaid) == true then return "RAID" end
    local home = A.Call(IsInGroup, 1) == true
    if not home and A.Call(IsInGroup, 2) == true then return "INSTANCE_CHAT" end
    if home or A.Call(IsInGroup) == true then return "PARTY" end
end

function N.Clock(ms)
    local s = math.floor((A.Number(ms, 0) or 0) / 1000 + 0.5)
    local h, m = math.floor(s / 3600), math.floor(s % 3600 / 60)
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s % 60) end
    return string.format("%d:%02d", m, s % 60)
end

local function compose(text)
    local tail = " " .. EN("annVia")
    local body = MARK .. text
    -- 255 bytes in all; the cut never splits a UTF-8 letter (the last, possibly partial, one goes)
    if #body + #tail > 255 then body = body:sub(1, 255 - #tail - 3):gsub("[\192-\255][\128-\191]*$", "") .. "…" end
    return body .. tail
end
function N.Say(text)
    if not N.Enabled() or not text or not N.Channel() then return false end
    if #N.queue >= MAX_QUEUE then return false end
    N.queue[#N.queue + 1] = compose(text)
    N.Pump()
    return true
end
function N.Pump()
    if #N.queue == 0 then return end
    local now = A.Monotonic()
    if N.lastSent and now - N.lastSent < GAP then return end
    local channel = N.Channel(); if not channel then N.queue = {}; return end
    local message = table.remove(N.queue, 1)
    local fn = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(fn) == "function" and pcall(fn, message, channel) then N.lastSent = now end
end

-- the chronicle is mentioned only when the player shows it publicly on the website
local function chronicleShown()
    local choice = A.PublishChoice and A.PublishChoice()
    return type(choice) == "table" and choice.public == true and choice.chronicle == true and A.CanPublish and A.CanPublish() == true
end
local function bestBefore(run)
    local best
    for _, old in ipairs(A.db and A.db.runs or {}) do
        if old ~= run and old.runId ~= run.runId and old.instanceId == run.instanceId and old.status == "completed" and A.Number(old.durationMs, 1) then
            best = math.min(best or old.durationMs, old.durationMs)
        end
    end
    return best
end

function N.OnRecord(kind, payload)
    if type(payload) ~= "table" then return end
    if kind == "quest.turned_in" then
        -- after the hand-in the quest log may no longer know the title; the reward window showed it a moment ago
        local title = A.Text(payload.title, 120) or (N.lastTitle and A.Now() - N.lastTitle.at < 120 and N.lastTitle.text)
        if not title then return end
        local text = string.format(EN("annQuest"), title)
        if chronicleShown() then text = text .. " · " .. EN("annChronicle") end
        N.Say(text)
        if N.ready then N.ready[A.Number(payload.questId, 1) or 0] = nil end
    elseif kind == "quest.accepted" then
        local title = A.Text(payload.title, 120) or N.LogTitle(payload.questId)
        if title then N.Say(string.format(EN("annAccepted"), title)) end
    elseif kind == "run.finished" and payload.status == "completed" then
        local ms = A.Number(payload.durationMs, 1); if not ms then return end
        local name = A.Text(payload.name, 80) or "?"
        local text = string.format(EN("annRun"), name, N.Clock(ms))
        local best = bestBefore(payload)
        local record = best and ms < best
        if record then text = text .. ", " .. EN("annBest") end
        N.Say(text)
        N.Brag(string.format(EN(record and "bragBest" or "bragRun"), name, N.Clock(ms)))
    elseif kind == "character.level" then
        local level = A.Number(payload.level, 2, 200)
        if level then N.Say(string.format(EN("annLevel"), level)); N.Brag(string.format(EN("bragLevel"), level)) end
    end
end

-- Bragging. The game lets an addon speak in /say (outside instances) or a public channel only inside the player's own
-- click, so after a level, a cleared dungeon or a record a small bar offers it: one click says it, nothing is said
-- otherwise. The guild button is there for players in a guild. The message is English, signed, and points to the
-- chronicle on the website when the player shows it there. The bar stays until the player answers it.
function N.BragEnabled() return A.db ~= nil and A.db.settings.bragPrompt ~= false end
function N.SetBragEnabled(on) if A.db then A.db.settings.bragPrompt = on == true end; if not on and N.bar then N.bar:Hide() end end
function N.BragText(text)
    if chronicleShown() then text = text .. " " .. EN("bragFollow") end
    return compose(text)
end
function N.Brag(text)
    if not N.BragEnabled() or not text then return false end
    N.pending = N.BragText(text)
    if N.ShowBar then pcall(N.ShowBar) end
    return true
end
-- channel: "SAY" or "GUILD"; called from the bar's buttons, i.e. inside the player's click
function N.SayBrag(channel)
    local message = N.pending; if not message then return false end
    if channel == "GUILD" and A.Call(IsInGuild) ~= true then return false end
    local fn = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    local ok = type(fn) == "function" and pcall(fn, message, channel)
    if ok then N.pending = nil; if N.bar then N.bar:Hide() end end
    return ok and true or false
end
function N.ShowBar()
    if not N.pending or type(CreateFrame) ~= "function" then return end
    local kit = A.UIKit and A.UIKit(); if not kit then return end
    local T = kit.C
    if not N.bar then
        local bar = CreateFrame("Frame", "EvertallyBragBar", UIParent)
        -- in the middle of the screen, where the eye is after a level or a boss
        bar:SetSize(560, 96); bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0); bar:SetFrameStrata("DIALOG")
        A.NativePanel(bar, T)
        bar.title = kit.label(bar, 12, T.bright); bar.title:SetPoint("TOPLEFT", 14, -10)
        bar.text = kit.label(bar, 11, T.mist); bar.text:SetPoint("TOPLEFT", 14, -30); bar.text:SetPoint("RIGHT", bar, "RIGHT", -230, 0); bar.text:SetWordWrap(true); bar.text:SetHeight(34)
        bar.close = kit.Button(bar, nil, 24, "ghost", function() bar:Hide() end); bar.close:SetHeight(22); bar.close:SetPoint("TOPRIGHT", -8, -8); bar.close.text:SetText("x")
        bar.say = kit.Button(bar, nil, 110, "primary", function() N.SayBrag("SAY") end); bar.say:SetHeight(28); bar.say:SetPoint("BOTTOMRIGHT", -40, 12)
        bar.guild = kit.Button(bar, nil, 90, "ghost", function() N.SayBrag("GUILD") end); bar.guild:SetHeight(28); bar.guild:SetPoint("RIGHT", bar.say, "LEFT", -6, 0)
        -- switching the offer off right where it appears; Settings turns it back on
        bar.never = kit.Button(bar, nil, 130, "ghost", function() N.SetBragEnabled(false); A.Print(A.L("bragOff")) end)
        bar.never:SetHeight(22); bar.never:SetPoint("BOTTOMLEFT", 14, 12)
        N.bar = bar
    end
    local bar = N.bar
    bar.title:SetText(A.L("bragTitle"))
    bar.text:SetText((N.pending:gsub("^{rt6} ", "")))
    bar.say.text:SetText(A.L("bragSay")); bar.guild.text:SetText(A.L("bragGuild")); bar.never.text:SetText(A.L("bragNever"))
    bar.guild:SetShown(A.Call(IsInGuild) == true)
    -- it stays until the player answers: the x, a channel, or "never again" (a level-up mid-fight is easy to miss)
    bar:Show()
end

-- A.Record is the one place every observation passes; the note follows whatever was recorded.
if type(A.Record) == "function" and not A.RecordAnnounced then
    local record = A.Record
    A.Record = function(kind, payload, ...)
        local result = record(kind, payload, ...)
        pcall(N.OnRecord, kind, payload)
        return result
    end
    A.RecordAnnounced = true
end

-- A boss on the way: announced unless it ended the run, which the dungeon note already covers.
if type(A.ObserveBoss) == "function" then
    local observe = A.ObserveBoss
    A.ObserveBoss = function(...)
        local run = A.ActiveRun and A.ActiveRun()
        local before = run and #run.bosses or 0
        local result = observe(...)
        if run and #run.bosses > before and not run.endedAt then
            local boss = run.bosses[#run.bosses]
            pcall(N.Say, string.format(EN("annBoss"), A.Text(boss.name, 80) or "?", N.Clock(boss.splitMs)))
        end
        return result
    end
end

-- A better piece from loot, as the gear module judges it for the current role.
function N.HookGear()
    local G = A.Gear
    if N.gearHooked or not G or type(G.LootNotice) ~= "function" then return end
    N.gearHooked = true
    local notice = G.LootNotice
    G.LootNotice = function(link, ...)
        local shown = notice(link, ...)
        if shown then
            local compare = G.Compare(link)
            if compare and compare.status == "upgrade" and compare.item and compare.profile then
                pcall(N.Say, string.format(EN("annUpgrade"), compare.item.link or compare.item.name or "?", compare.delta or 0, compare.profile.name))
            end
        end
        return shown
    end
end
-- Objectives done: a quest in the log that turns complete. The log is read once on entering the world, so quests
-- that were already complete then are not announced again; afterwards each change of the log is compared.
function N.LogTitle(id)
    id = A.Number(id, 1, 10000000)
    return id and C_QuestLog and A.Text(A.Call(C_QuestLog.GetTitleForQuestID, id), 120) or nil
end
function N.ScanLog(silent)
    if not (C_QuestLog and type(C_QuestLog.GetNumQuestLogEntries) == "function" and type(C_QuestLog.GetInfo) == "function") then return 0 end
    local count = A.Number((A.Call(C_QuestLog.GetNumQuestLogEntries)), 0, 200) or 0
    local seen, announced = {}, 0
    N.ready = N.ready or {}; N.objectives = N.objectives or {}
    for i = 1, count do
        local info = A.Call(C_QuestLog.GetInfo, i)
        local id = A.Number(A.Field(info, "questID"), 1, 10000000)
        if id and A.Field(info, "isHeader") ~= true then
            seen[id] = true
            local complete = A.Call(C_QuestLog.IsComplete, id) == true or A.Field(info, "isComplete") == true
            -- each objective that becomes finished ("Venom Sac 8/8"); the last one is covered by "objectives done"
            local done = N.objectives[id] or {}
            local list = type(C_QuestLog.GetQuestObjectives) == "function" and A.Call(C_QuestLog.GetQuestObjectives, id)
            if type(list) == "table" then
                for index, objective in ipairs(list) do
                    local finished = A.Field(objective, "finished") == true
                    if finished and done[index] == false and not silent and not complete then
                        local text = A.Text(A.Field(objective, "text"), 100)
                        local have, need = A.Number(A.Field(objective, "numFulfilled"), 0), A.Number(A.Field(objective, "numRequired"), 1)
                        if text and need and need > 1 and not text:find("%d+/%d+") then text = text .. " " .. (have or need) .. "/" .. need end
                        local title = A.Text(A.Field(info, "title"), 80) or N.LogTitle(id)
                        if text and title then N.Say(string.format(EN("annObjective"), title, text)); announced = announced + 1 end
                    end
                    done[index] = finished
                end
            end
            N.objectives[id] = done
            if complete and not N.ready[id] then
                N.ready[id] = true
                if not silent then
                    local title = A.Text(A.Field(info, "title"), 120) or N.LogTitle(id)
                    if title then N.Say(string.format(EN("annReady"), title)); announced = announced + 1 end
                end
            elseif not complete then N.ready[id] = nil end
        end
    end
    for id in pairs(N.ready) do if not seen[id] then N.ready[id] = nil end end
    for id in pairs(N.objectives) do if not seen[id] then N.objectives[id] = nil end end
    return announced
end
A.On("PLAYER_ENTERING_WORLD", function() if not N.logRead then N.logRead = true; pcall(N.ScanLog, true) end end)
A.On("QUEST_LOG_UPDATE", function() if N.logRead then pcall(N.ScanLog, false) end end)

N.HookGear()
A.On("PLAYER_LOGIN", N.HookGear)
-- the other addons build their saved settings while loading; a moment after entering the world they are there
A.On("PLAYER_ENTERING_WORLD", function()
    if N.quietChecked then return end; N.quietChecked = true
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(3, function() pcall(N.QuietOthers) end) else pcall(N.QuietOthers) end
end)
A.On("QUEST_COMPLETE", function()
    local title = A.Text(A.Call(GetTitleText), 120)
    if title then N.lastTitle = {text = title, at = A.Now()} end
end)
if C_Timer and type(C_Timer.NewTicker) == "function" then C_Timer.NewTicker(1, function() pcall(N.Pump) end) end
