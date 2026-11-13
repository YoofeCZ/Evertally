"""One-off patch: armory kinds, 'always' button, website flag, stats/talents tabs and revoke list in SocialUI.lua and UI.lua."""
import sys
from pathlib import Path

root = Path(sys.argv[1])


def patch(name, pairs):
    path = root / name
    s = path.read_text(encoding="utf8")
    for old, new in pairs:
        assert s.count(old) == 1, (name, s.count(old), old[:80])
        s = s.replace(old, new)
    path.write_text(s, encoding="utf8")


patch("SocialUI.lua", [
    # popup: six checkboxes, four buttons
    ('f:SetSize(440, 250); f:SetPoint("TOP", UIParent, "TOP", 0, -150)', 'f:SetSize(440, 360); f:SetPoint("TOP", UIParent, "TOP", 0, -130)'),
    ('''    for i = 1, 3 do
        local b = k.Button(f, nil, 404, "ghost", function() end); b:SetPoint("TOPLEFT", 18, -112 - (i - 1) * 32); b:Hide(); f.checks[i] = b
    end
    for i = 1, 3 do f.buttons[i] = k.Button(f, nil, 126, i == 1 and "primary" or "ghost", function() end); f.buttons[i]:Hide() end''',
     '''    for i = 1, 6 do
        local b = k.Button(f, nil, 404, "ghost", function() end); b:SetPoint("TOPLEFT", 18, -122 - (i - 1) * 32); b:Hide(); f.checks[i] = b
    end
    for i = 1, 4 do f.buttons[i] = k.Button(f, nil, 98, i == 1 and "primary" or "ghost", function() end); f.buttons[i]:Hide() end'''),
    ('b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", 18 + (i - 1) * 134, 16); b.text:SetText(def.label); b:Show()', 'b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", 18 + (i - 1) * 102, 16); b.text:SetText(def.label); b:Show()'),
    # kinds text
    ('''    if kinds:find("i", 1, true) then out[#out + 1] = A.L("socialInv") end
    if kinds:find("p", 1, true) then out[#out + 1] = A.L("socialProf") end
    if kinds:find("g", 1, true) then out[#out + 1] = A.L("socialGold") end
    return table.concat(out, ", ")''', '''    for _, key in ipairs({"i", "s", "t", "p", "g", "w"}) do
        if kinds:find(key, 1, true) then out[#out + 1] = A.L(({i = "socialInv", s = "socialStats", t = "socialTalents", p = "socialProf", g = "socialGold", w = "socialWeb"})[key]) end
    end
    return table.concat(out, ", ")'''),
    ('''    local checks = {}
    for _, key in ipairs({"i", "p", "g"}) do
        if request.kinds:find(key, 1, true) then checks[#checks + 1] = {key = key, label = A.L(({i = "socialInv", p = "socialProf", g = "socialGold"})[key]), on = key ~= "g"} end
    end
    A.SocialShowPopup({id = request.id, title = string.format(A.L("socialAskTitle"), plain(base(request.sender))), body = A.L("socialAskNote"), checks = checks, buttons = {
        {label = A.L("socialAllow"), fn = function(sel) local allowed = ""; for _, key in ipairs({"i", "p", "g"}) do if sel[key] then allowed = allowed .. key end end; A.AnswerRequest(request.id, allowed) end},
        {label = A.L("socialDeny"), fn = function() A.DenyRequest(request.id, false) end},
        {label = A.L("socialBlock"), fn = function() A.DenyRequest(request.id, true) end},
    }})''', '''    local checks = {}
    local keys = {"i", "s", "t", "p", "g", "w"}
    local labels = {i = "socialInv", s = "socialStats", t = "socialTalents", p = "socialProf", g = "socialGold", w = "socialWebAsk"}
    for _, key in ipairs(keys) do
        -- gold and the website copy are never ticked for you
        if request.kinds:find(key, 1, true) then checks[#checks + 1] = {key = key, label = A.L(labels[key]), on = key ~= "g" and key ~= "w"} end
    end
    local function chosen(sel) local allowed = ""; for _, key in ipairs(keys) do if sel[key] then allowed = allowed .. key end end; return allowed end
    A.SocialShowPopup({id = request.id, title = string.format(A.L("socialAskTitle"), plain(base(request.sender))), body = A.L("socialAskNote"), checks = checks, buttons = {
        {label = A.L("socialAllowOnce"), fn = function(sel) A.AnswerRequest(request.id, chosen(sel), false) end},
        {label = A.L("socialAllowAlways"), fn = function(sel) A.AnswerRequest(request.id, chosen(sel), true) end},
        {label = A.L("socialDeny"), fn = function() A.DenyRequest(request.id, false) end},
        {label = A.L("socialBlock"), fn = function() A.DenyRequest(request.id, true) end},
    }})'''),
    # viewer tabs
    ('for _, mode in ipairs({"equipped", "bags", "professions", "gold"}) do\n                local chip = k.Chip(f, function() f.mode = mode; A.SocialRefreshViewer() end)',
     'for _, mode in ipairs({"equipped", "stats", "talents", "bags", "professions", "gold"}) do\n                local chip = k.Chip(f, function() f.mode = mode; A.SocialRefreshViewer() end)'),
    ('''    elseif f.mode == "professions" then
        local rows = {}''', '''    elseif f.mode == "stats" then
        local rows = {}
        for _, key in ipairs(A.ArmoryStatKeys or {}) do
            if v.stats and v.stats[key] then rows[#rows + 1] = {title = plain(A.ArmoryStatLabel(key)), icon = k.ICON.unknown, right = string.format("%g", v.stats[key])} end
        end
        f.list.SetItems(rows, A.L("viewNoStats"))
    elseif f.mode == "talents" then
        local rows = {}
        for _, tree in ipairs(v.talents or {}) do
            rows[#rows + 1] = {title = plain(tree.name ~= "" and tree.name or "?"), sub = string.format(A.L("viewTalentPoints"), #tree.ranks), icon = k.ICON.unknown, right = tostring(tree.spent)}
        end
        f.list.SetItems(rows, A.L("viewNoTalents"))
    elseif f.mode == "professions" then
        local rows = {}'''),
    # privacy rows: permanent permissions and what was shown, each revocable
    ('''    for _, s in ipairs(A.social.shown) do rows[#rows + 1] = {title = plain(s.name), sub = A.L("socialShownTitle") .. " " .. kindsText(s.kinds) .. "  ·  " .. (A.Call(date, "%H:%M", s.at) or ""), icon = K().ICON.peers} end''',
     '''    for _, t in ipairs(A.SocialTrusted()) do
        local who = t.sender
        rows[#rows + 1] = {title = plain(base(t.sender)), sub = A.L("socialTrustedTitle") .. " " .. kindsText(t.kinds or ""), icon = K().ICON.peers, tag = A.Upper(A.L("socialRevoke")), tagColor = K().C.red,
            onClick = function() A.RevokeAccess(who); A.RefreshUI() end}
    end
    for _, s in ipairs(A.social.shown) do
        local entry = s
        rows[#rows + 1] = {title = plain(s.name), sub = A.L("socialShownTitle") .. " " .. kindsText(s.kinds) .. "  ·  " .. (A.Call(date, "%H:%M", s.at) or ""), icon = K().ICON.peers,
            tag = entry.revoked and A.Upper(A.L("socialRevoked")) or A.Upper(A.L("socialRevoke")), tagColor = K().C.red,
            onClick = (not entry.revoked) and function() A.RevokeAccess(entry.sender or entry.name); A.RefreshUI() end or nil}
    end'''),
    # request form: kind chips in two rows, website flag only when it can work
    ('''    page.kinds={i=true,p=true,g=false};page.kindButtons={}
    local last
    for _,key in ipairs({"i","p","g"})do
        local chip=k.Chip(form,function()page.kinds[key]=not page.kinds[key];A.RefreshUI()end)
        if last then chip:SetPoint("LEFT",last,"RIGHT",5,0)else chip:SetPoint("TOPLEFT",14,-141)end
        page.kindButtons[key]=chip;last=chip
    end
    page.permissionNote=k.label(form,10,muted);page.permissionNote:SetPoint("TOPLEFT",14,-175);page.permissionNote:SetPoint("TOPRIGHT",-14,-175);page.permissionNote:SetHeight(18)''',
     '''    page.kinds={i=true,s=true,t=true,p=true,g=false,w=A.DefaultLookKinds():find("w",1,true)~=nil};page.kindButtons={}
    local last
    for n,key in ipairs({"i","s","t","p","g","w"})do
        local chip=k.Chip(form,function()page.kinds[key]=not page.kinds[key];A.RefreshUI()end)
        if n==5 then chip:SetPoint("TOPLEFT",14,-171)elseif last then chip:SetPoint("LEFT",last,"RIGHT",5,0)else chip:SetPoint("TOPLEFT",14,-141)end
        page.kindButtons[key]=chip;last=chip
    end
    page.permissionNote=k.label(form,10,muted);page.permissionNote:SetPoint("TOPLEFT",14,-205);page.permissionNote:SetPoint("TOPRIGHT",-14,-205);page.permissionNote:SetHeight(30)'''),
    ('''        local chosen="";for _,key in ipairs({"i","p","g"})do if page.kinds[key]then chosen=chosen..key end end''',
     '''        local chosen="";for _,key in ipairs({"i","s","t","p","g","w"})do if page.kinds[key]then chosen=chosen..key end end'''),
    ('''        for key, chip in pairs(page.kindButtons) do chip.SetLabel(A.L(({i = "socialInv", p = "socialProf", g = "socialGold"})[key])); chip.SetOn(page.kinds[key]) end''',
     '''        local webReady = A.DefaultLookKinds():find("w", 1, true) ~= nil
        for key, chip in pairs(page.kindButtons) do
            chip.SetLabel(A.L(({i = "socialInv", s = "socialStats", t = "socialTalents", p = "socialProf", g = "socialGold", w = "socialWeb"})[key]))
            chip.SetOn(page.kinds[key] and (key ~= "w" or webReady)); chip:SetShown(key ~= "w" or webReady)
        end'''),
    ('''page.permissionNote:SetText(A.db.settings.language=="cs" and "Hráč rozhodne, co ti ukáže. Zlato se žádá zvlášť." or "The player chooses what to show. Gold is a separate request.")''',
     '''page.permissionNote:SetText(A.L("socialPermissionNote"))'''),
    ('''    elseif kind == "view" then if not viewer or not viewer:IsShown() then openViewer(data) end end''',
     '''    elseif kind == "view" then if not viewer or not viewer:IsShown() then openViewer(data) end
    elseif kind == "viewRevoked" and viewer and viewer:IsShown() and viewer.view and base(viewer.view.sender):lower() == base(data.name):lower() then viewer:Hide() end'''),
    # texts
    ('''        socialShownTitle = "You showed:", socialBlockedHint = "Blocked. Click to unblock.", socialBlock = "Block",
        socialAskTitle = "%s asks to look at:", socialAskNote = "They see only what you tick. Evertally does not save what you show.", socialAllow = "Allow", socialDeny = "Deny",''',
     '''        socialShownTitle = "You showed:", socialBlockedHint = "Blocked. Click to unblock.", socialBlock = "Block",
        socialAskTitle = "%s asks to look at:", socialAskNote = "They see only what you tick. Gold and the website copy are never ticked for you. \\"Always\\" never covers gold, and you can take it back under Privacy or with /etally revoke.", socialAllow = "Allow", socialDeny = "Deny",
        socialAllowOnce = "Allow once", socialAllowAlways = "Always", socialStats = "Stats", socialTalents = "Talents", socialWeb = "Keep on their website",
        socialWebAsk = "They may keep this on their Evertally website", socialTrustedTitle = "Allowed for good:", socialRevoke = "Revoke", socialRevoked = "revoked",
        socialPermissionNote = "The player chooses what to show. Gold is a separate request. With the website box they may keep a copy on their Evertally website until you revoke it.",
        viewTab_stats = "Stats", viewTab_talents = "Talents", viewNoStats = "No stats shown.", viewNoTalents = "No talents shown.", viewTalentPoints = "%d talents with points",'''),
    ('''        socialShownTitle = "Ukázal jsi:", socialBlockedHint = "Zablokován. Kliknutím odblokuješ.", socialBlock = "Blokovat",
        socialAskTitle = "%s se chce podívat na:", socialAskNote = "Uvidí jen to, co zaškrtneš. Evertally neukládá, co ukážeš.", socialAllow = "Povolit", socialDeny = "Odmítnout",''',
     '''        socialShownTitle = "Ukázal jsi:", socialBlockedHint = "Zablokován. Kliknutím odblokuješ.", socialBlock = "Blokovat",
        socialAskTitle = "%s se chce podívat na:", socialAskNote = "Uvidí jen to, co zaškrtneš. Zlato a kopie na webu se nikdy nezaškrtávají za tebe. \\"Vždy\\" se zlata netýká a půjde vzít zpět v Soukromí nebo příkazem /etally revoke.", socialAllow = "Povolit", socialDeny = "Odmítnout",
        socialAllowOnce = "Jednou", socialAllowAlways = "Vždy", socialStats = "Statistiky", socialTalents = "Talenty", socialWeb = "Nechat na jejich webu",
        socialWebAsk = "Smí si to nechat na webu Evertally", socialTrustedTitle = "Povoleno trvale:", socialRevoke = "Odvolat", socialRevoked = "odvoláno",
        socialPermissionNote = "Hráč rozhodne, co ukáže. Zlato se žádá zvlášť. Se zaškrtnutým webem si smí nechat kopii na webu Evertally, dokud ji neodvoláš.",
        viewTab_stats = "Statistiky", viewTab_talents = "Talenty", viewNoStats = "Statistiky neukázal.", viewNoTalents = "Talenty neukázal.", viewTalentPoints = "Talentů s body: %d",'''),
])

patch("UI.lua", [
    ('''        local ok, state = A.AnswerRequest(id, kinds ~= "" and kinds or "ip"); A.Print(ok and state or tostring(state))
    elseif text:match("^deny%s+%x+") then
        A.DenyRequest(text:match("^deny%s+(%x+)"), false)''', '''        local ok, state = A.AnswerRequest(id, kinds ~= "" and kinds or "istp"); A.Print(ok and state or tostring(state))
    elseif text:match("^always%s+%x+") then
        -- /etally always <id> [kinds]: like allow, and remembered for this player (never covers gold) until /etally revoke
        local id, kinds = text:match("^always%s+(%x+)%s*(%a*)")
        local ok, state = A.AnswerRequest(id, kinds ~= "" and kinds or "istp", true); A.Print(ok and state or tostring(state))
    elseif text:match("^deny%s+%x+") then
        A.DenyRequest(text:match("^deny%s+(%x+)"), false)
    elseif text:match("^revoke%s+%S") then
        local name = text:match("^revoke%s+(%S+)")
        local ok, err = A.RevokeAccess(name); A.Print(ok and string.format(A.L("socialRevokedChat"), name) or tostring(err))
    elseif text:match("^look%s+%S") then
        -- /etally look <name> [kinds]: ask a player to show gear, stats, talents and professions (i s t p, g for gold, w for your website)
        local name, kinds = text:match("^look%s+(%S+)%s*(%a*)")
        local ok, err = A.RequestInspect(name, kinds ~= "" and kinds or nil); A.Print(ok and string.format(A.L("socialWaiting"), name) or A.L("socialErr_" .. tostring(err)))'''),
])
print("ok")
