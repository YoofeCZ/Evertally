"""Import Polestar (GPL-3.0-only, https://github.com/fitzforge/polestar) into Evertally as the Evertally_Guide* add-ons.

    python -I tools/import_polestar.py ["D:/World of Warcraft/_forever_/Interface/AddOns"]

Polestar changes every day, so the fork is generated, never edited by hand: run this again to take a newer Polestar. What
Evertally changes in the fork lives here (RENAMES, KEEP, PATCHES), so it survives every import. The renames keep the fork
apart from an installed Polestar: other folders, globals, frames, SavedVariables and key bindings.

  folders     Polestar -> Evertally_Guide, Polestar_X -> Evertally_Guide_X (language packs and the Recorder are left out)
  code        Polestar -> EvertallyGuide, PolestarDB -> EvertallyGuideDB, POLESTAR_X -> EVERTALLYGUIDE_X
  player text "Polestar" in a sentence -> "Evertally"; the guides' author stays "Polestar" (it is theirs), and so do the
              strings other Polestar users exchange with us (party addon messages, import strings), so the two can talk
  notices     LICENSE, THIRD_PARTY.md, CREDITS.md and LICENSE-DATA.txt are copied unchanged; NOTICE-EVERTALLY.txt says
              what was changed and when (GPL-3.0 section 5a)
"""
from __future__ import annotations

import datetime
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\World of Warcraft\_forever_\Interface\AddOns")
DEST = ROOT / "addon"
OVERLAY = ROOT / "tools" / "evertally-guide-overlay"
LANGUAGE = re.compile(r"^Polestar_[a-z]{2}[A-Z]{2}$")
SKIP = {"Polestar_Recorder"}
# The file types Evertally's updater installs (sync/src/addon_update.rs FILE_TYPES).
INSTALLED = {".lua", ".toc", ".xml", ".md", ".txt", ".tga", ".blp", ".ttf", ".ogg"}

# Strings other Polestar users send or paste: kept word for word so a party with Polestar players still works.
KEEP = {"PolestarT1"}
INTEROP = re.compile(r"Polestar (Pack|Community)|import string|^\^Polestar")
# Exact edits after the renames, per file (relative to the new folder): (old, new, expected count).
# Names other add-ons key us by (Auctionator caller, EllesmereUI painter, Waypoint UI flag, TomTom `from`, the SPF
# handoff owner) must differ from Polestar's: with both installed, the same name would overwrite or cancel the other's.
PATCHES: dict[str, list[tuple[str, str, int]]] = {
    # Czech needs letters the game font of an English client lacks (boxes instead of ě č ř ů).
    "Theme/Theme.lua": [
        ('local function facePath(face, weight)\n\tlocal locale = GetLocale and GetLocale()\n',
         'local function facePath(face, weight)\n\tlocal locale = GetLocale and GetLocale()\n\t-- Evertally: in Czech the game\'s own font (FRIZQT__ on an English client) has no \x0196m, \x0196a, \x0197k, \x0197}: Inter has them.\n\tif face == "game" and ns.EvertallyLanguage == "csCZ" then face = "inter" end\n', 1),
    ],
    # Evertally's own look is the default (addon/Evertally/GuideSkin.lua registers it): no starlit band.
    "UI/UI.lua": [
        ('	skin = "polestar", --', '	skin = "evertally", --', 1),
        ('	band = true, -- the starlit header band', '	band = false, -- the starlit header band', 1),
    ],
    # Polestar 0.4.0.1 bug: W.Bind calls stage:Refresh() before stage.Refresh is set ("Theme/Widgets.lua:1114:
    # attempt to call a nil value" on the Welcome page). Set it first.
    "UI/Welcome.lua": [
        ('\t\t\tW.Painter(stage, paintStage)\n\t\t\tW.Bind(stage, "qol.targetPlate", "qol.targetButton")\n'
         '\t\t\tW.Bind(stage, "qol.targetSimple")\n\t\t\tW.Bind(stage, "qol.markTarget")\n\t\t\tstage.Refresh = paintStage\n',
         '\t\t\tW.Painter(stage, paintStage)\n\t\t\tstage.Refresh = paintStage\n\t\t\tW.Bind(stage, "qol.targetPlate", "qol.targetButton")\n'
         '\t\t\tW.Bind(stage, "qol.targetSimple")\n\t\t\tW.Bind(stage, "qol.markTarget")\n', 1),
        # Evertally: one setup. Evertally's own steps (addon/Evertally/SetupPages.lua) are pages of this window
        # (UI.WelcomeHost), built from its own widgets (UI.WelcomeKit); a page may hold Next back (blocked: the
        # installation check, the pairing); Finish tells the host (UI.WelcomeOnFinish), an opening too
        # (UI.WelcomeOnOpen); with a host the login opening is the host's (UI.WelcomeOwner).
        ('-- The pages shown now, in order.\nfunction pageList()\n\tlocal out = {}\n',
         '-- Evertally: pages another add-on hosts here (UI.WelcomeHost), each after the page it names; placed once,\n'
         '-- before the pages are first listed.\n'
         'local hosted = {}\n'
         'local function placeHosted()\n'
         '\tif #hosted == 0 then return end\n'
         '\tfor _, spec in ipairs(hosted) do\n'
         '\t\tlocal at = #PAGES - 1 -- before the last page (finish) when the one it names is missing\n'
         '\t\tfor i, pg in ipairs(PAGES) do if pg.key == spec.after then at = i end end\n'
         '\t\ttable.insert(PAGES, at + 1, spec)\n'
         '\tend\n'
         '\thosted = {}\n'
         'end\n'
         'function UI.WelcomeHost(spec)\n'
         '\thosted[#hosted + 1] = spec\n'
         '\treturn true\n'
         'end\n\n'
         '-- The pages shown now, in order.\nfunction pageList()\n\tplaceHosted()\n\tlocal out = {}\n', 1),
        ('local render -- forward\n',
         'local render -- forward\n'
         'local makePage -- forward (build): a page\'s frames, built as it first shows\n\n'
         '-- Evertally: what a hosted page builds with (this window\'s own parts and sizes), and its redraw.\n'
         'UI.WelcomeKit = {\n'
         '\tCW = CW, W = W, Theme = Theme,\n'
         '\tcompactHero = compactHero, layoutCompactHero = layoutCompactHero,\n'
         '\ttoggleRow = toggleRow, toggleRowHeight = toggleRowHeight, layRows = layRows,\n'
         '\toptionGroup = optionGroup, layGroup = layGroup, keepLine = keepLine, para = para, place = place,\n'
         '\trefresh = function() if F and F:IsShown() and render then render() end end,\n'
         '\tshown = function() return F ~= nil and F:IsShown() end,\n'
         '\tcurrent = function() return current end,\n'
         '\tfull = function() return full end,\n'
         '}\n'
         '-- Finish: the host first (it applies its own choices), then the close.\n'
         'local function finish()\n'
         '\tif UI.WelcomeOnFinish then pcall(UI.WelcomeOnFinish) end\n'
         '\treturn close()\n'
         'end\n', 1),
        ('local function go(delta)\n\tlocal list = pageList()\n',
         'local function go(delta)\n\tlocal list = pageList()\n'
         '\t-- Evertally: a page that holds Next back (blocked) is not left forward\n'
         '\tif delta > 0 then\n'
         '\t\tfor _, pg in ipairs(list) do\n'
         '\t\t\tif pg.key == current and pg.blocked and pg.blocked() then return end\n'
         '\t\tend\n'
         '\tend\n', 1),
        ('\tif at and count and at >= count then return close() end\n\tgo(1)\nend',
         '\tif at and count and at >= count then return finish() end\n\tgo(1)\nend', 1),
        ('\tF.Finish = W.Button(foot, L["Finish"], close, { primary = true })',
         '\tF.Finish = W.Button(foot, L["Finish"], function() finish() end, { primary = true })', 1),
        ('\tF.Next:SetShown(not last)\n',
         '\tF.Next:SetShown(not last)\n'
         '\t-- Evertally: held back while the page says so (blocked)\n'
         '\tlocal held = list[at].blocked and list[at].blocked() and true or false\n'
         '\tF.Next:SetEnabled(not held)\n'
         '\tF.Next:SetAlpha(held and 0.45 or 1)\n', 1),
        ('\tF.pages = {}\n\tfor _, pg in ipairs(PAGES) do\n\t\tlocal P = CreateFrame("Frame", nil, F)\n',
         '\tF.pages = {}\n\t-- (Evertally: one page at a time, so a page that shows up later, a hosted one or one whose add-on loaded\n'
         '\t-- after the window was built, is built as it first shows: render)\n'
         '\tfunction makePage(pg)\n\t\tlocal P = CreateFrame("Frame", nil, F)\n', 1),
        ('\t\tpg.build(P)\n\t\tF.pages[pg.key] = P\n\tend\n\tif W.Rim then',
         '\t\tpg.build(P)\n\t\tF.pages[pg.key] = P\n\tend\n\tfor _, pg in ipairs(PAGES) do makePage(pg) end\n\tif W.Rim then', 1),
        ('function render(from)\n\tlocal list = pageList()\n',
         'function render(from)\n\tlocal list = pageList()\n'
         '\tfor _, pg in ipairs(list) do if not F.pages[pg.key] then makePage(pg) end end\n', 1),
        ('\tif not F then build() end\n\tunasked = deferred and true or false\n',
         '\tif not F then build() end\n'
         '\tif UI.WelcomeOnOpen then pcall(UI.WelcomeOnOpen, why) end\n'
         '\tunasked = deferred and true or false\n', 1),
        ('\tif seen() then return end\n\tpending = "login"\n',
         '\tif seen() then return end\n'
         '\t-- (Evertally: its setup decides when this window opens while the account has not had it; a new character on\n'
         '\t-- an account that has gets the guide\'s own short showing, its own choices alone)\n'
         '\tif UI.WelcomeOwner and not accountSeen() then return end\n'
         '\tpending = "login"\n', 1),
    ],
    "Core/Init.lua": [('SLASH_EVERTALLYGUIDE3 = "/ps"', 'SLASH_EVERTALLYGUIDE3 = "/evertallyguide"', 1),
                      # Evertally's own Discord (reports, Install's last page, About), not Polestar's
                      ('ns.DiscordURL = "https://discord.gg/polestar"', 'ns.DiscordURL = "https://discord.gg/Mjmj8gmAPT"', 1)],
    # "While you're here" (the line under the step and its toast: a later goal close by, sell/repair before heading
    # out) is off by default in Evertally; Settings turns it back on.
    "Core/Engine.lua": [
        ("\twhileHere = true, -- \"While you're here\"", "\twhileHere = false, -- (Evertally: off by default) \"While you're here\"", 1),
        ("\twhileHereVendors = true, --", "\twhileHereVendors = false, -- (Evertally: off by default)", 1),
    ],
    "Core/Materials.lua": [('local CALLER = "Polestar"', 'local CALLER = "Evertally Guide"', 1)],
    "Gear/Bags.lua": [('local ELLESMERE = "Polestar"', 'local ELLESMERE = "EvertallyGuide"', 1)],
    "Nav/Bridges.lua": [('local FLAG = "Polestar"', 'local FLAG = "EvertallyGuide"', 1),
                        ('from = "Polestar",', 'from = "EvertallyGuide",', 1)],
    "Nav/Journey.lua": [('opts.from == "Polestar"', 'opts.from == "EvertallyGuide"', 1),
                        ('uid.from == "Polestar"', 'uid.from == "EvertallyGuide"', 1)],
    "Nav/Handoff.lua": [('local OWNER = "Polestar"', 'local OWNER = "EvertallyGuide"', 1)],
    "Nav/Pins.lua": [('section = "Polestar",', 'section = "Evertally Guide",', 1)],
    "UI/GameMenu.lua": [('button:SetText("Polestar")', 'button:SetText("Evertally Guide")', 1)],
    # Czech on an English client (Evertally_Guide_csCZ, chosen in Evertally): the guide texts take the language
    # Evertally sets; the game's names stay English, as the client shows them.
    "Core/GuideTexts.lua": [
        ('local english = ENGLISH[locale] or false\n',
         'local english = ENGLISH[locale] or false\n'
         '-- Evertally: the language of the guide texts when it is not the client\'s (Evertally_Guide_csCZ on an English\n'
         '-- client, set by Evertally before the guide packs load).\n'
         'function GuideTexts.UseLanguage(loc) locale = loc; english = ENGLISH[loc] or false end\n', 1),
    ],
    # Talents in Polestar 0.4.0.1 are "Coming soon" (T.SOON): no section on the hub's rail, and SHOW_TALENTS opens
    # Evertally's own Talents page (its planner, ETB1 codes, profiles in the talent window) instead.
    "Talents/View.lua": [
        ('ns.On("SHOW_TALENTS", TV.Show)',
         'ns.On("SHOW_TALENTS", function(...)\n'
         '\tlocal E = rawget(_G, "Evertally")\n'
         '\tif T.SOON and type(E) == "table" and E.ShowView then return E.ShowView("talents") end\n'
         '\treturn TV.Show(...)\nend)', 1),
        ('if UI.RegisterSection then\n\tUI.RegisterSection({\n\t\tkey = "Talents"',
         'if UI.RegisterSection and not T.SOON then\n\tUI.RegisterSection({\n\t\tkey = "Talents"', 1),
    ],
    # The hub has no Dungeons section: its attunements, quest state and pick-up/hand-in runs are a tab of Evertally's
    # Dungeon Journal (Evertally_Map/DungeonJournal.lua), and SHOW_DUNGEON (map pins, the dungeon toast, Lookup,
    # /etguide dungeons) opens the journal at that dungeon. Without Evertally the hub opens as before (on its guides).
    "UI/Dungeons.lua": [
        ('ns.On("SHOW_DUNGEON", function(key) DS.Show(key) end)',
         'ns.On("SHOW_DUNGEON", function(key)\n'
         '\tlocal E = rawget(_G, "Evertally")\n'
         '\tif type(E) == "table" and E.OpenGuideDungeon and E.OpenGuideDungeon(key) then return end\n'
         '\tDS.Show(key)\nend)', 1),
        ('if UI.RegisterSection then\n\tUI.RegisterSection({\n\t\tkey = "Dungeons"',
         '-- (Evertally: no section on the rail, see SHOW_DUNGEON above)\nif false and UI.RegisterSection then\n\tUI.RegisterSection({\n\t\tkey = "Dungeons"', 1),
    ],
    # No Characters section either: Evertally's own pages show the characters. The alts are still recorded
    # (Alts/Snapshot.lua) for the tooltips and the gold total; SHOW_ALTS opens Evertally's Overview.
    "Alts/View.lua": [
        ('ns.On("SHOW_ALTS", AV.Show)',
         'ns.On("SHOW_ALTS", function(...)\n'
         '\tlocal E = rawget(_G, "Evertally")\n'
         '\tif type(E) == "table" and E.ShowView then return E.ShowView("overview") end\n'
         '\treturn AV.Show(...)\nend)', 1),
        ('if UI.RegisterSection then\n\tUI.RegisterSection({\n\t\tkey = "Characters"',
         '-- (Evertally: no section on the rail, see SHOW_ALTS above)\nif false and UI.RegisterSection then\n\tUI.RegisterSection({\n\t\tkey = "Characters"', 1),
    ],
    # One button on the minimap, Evertally's (left: the Evertally menu, right: hide): the guide's own is off by default
    # (still in its Buttons settings), and its menu, wherever it opens (that button, the floating one, the addon
    # compartment), is the Evertally menu (addon/Evertally/EvertallyMenu.lua).
    "Maps/Maps.lua": [("\tminimapButton = true,\n", "\tminimapButton = false, -- (Evertally: its own button is the one on the minimap)\n", 1)],
    "Maps/MinimapButton.lua": [
        ("function Maps.ShowMenu(anchor)\n\tlocal W = ns.Widgets\n",
         "function Maps.ShowMenu(anchor)\n\tlocal E = rawget(_G, \"Evertally\")\n"
         "\tif type(E) == \"table\" and E.ShowEvertallyMenu then return E.ShowEvertallyMenu(anchor) end\n\tlocal W = ns.Widgets\n", 1),
    ],
    # The settings window's sidebar groups are fixed; Evertally's own settings (addon/Evertally/EvertallySettings.lua)
    # register pages with group = "evertally", which leads the list.
    "UI/Options.lua": [
        ('local GROUPS = {\n\t{ key = "guiding", label = L["Guiding"] },',
         'local GROUPS = {\n\t{ key = "evertally", label = "Evertally" },\n\t{ key = "guiding", label = L["Guiding"] },', 1),
    ],
    # The hub's rail drops the sections past its foot group (rows of 56 px); with Evertally's own section the 640 px
    # hub of the Halo and Hearth skins is 2 px short. Close the rows up (to 46 px: icon and caption) before dropping.
    "Theme/Widgets.lua": [
        ("\tfor k = 1, #(bottom or {}) do\n\t\ti = i + 1\n\t\tplace(bottom[k], i, y, true)\n\t\ty = y + RAIL_ROW\n\tend\n"
         "\tlocal limit = f:GetHeight() - 2 - y -- the top of the bottom group\n"
         "\ty = f.psNavTop -- the first section level with the sidebar's first row\n"
         "\tfor k = 1, #items do\n\t\tif y + RAIL_ROW > limit then break end\n\t\ti = i + 1\n\t\tn = n + 1\n"
         "\t\tplace(items[k], i, y)\n\t\ty = y + RAIL_ROW\n\tend\n",
         "\tfor k = 1, #(bottom or {}) do\n\t\ti = i + 1\n\t\tplace(bottom[k], i, y, true)\n"
         "\t\trailButton(f, i):SetHeight(RAIL_ROW)\n\t\ty = y + RAIL_ROW\n\tend\n"
         "\tlocal limit = f:GetHeight() - 2 - y -- the top of the bottom group\n"
         "\ty = f.psNavTop -- the first section level with the sidebar's first row\n"
         "\t-- Evertally: more sections than rows close up (to 46 px) before one is dropped.\n"
         "\tlocal step = RAIL_ROW\n"
         "\tif #items > 0 and y + #items * step > limit then step = max(46, math.floor((limit - y) / #items)) end\n"
         "\tfor k = 1, #items do\n\t\tif y + step > limit then break end\n\t\ti = i + 1\n\t\tn = n + 1\n"
         "\t\tplace(items[k], i, y)\n\t\trailButton(f, i):SetHeight(step)\n\t\ty = y + step\n\tend\n", 1),
    ],
}


def _more(path: str, *edits: tuple[str, str, int]) -> None:
    PATCHES.setdefault(path, []).extend(edits)


# ---- 2026-11-17, after the first test of 0.11.0 in the game ----
# No stars anywhere: the starlit band's star layer (every header band), the Little Dipper and the emblem's beam in the
# setup and What's new.
_more("Theme/Theme.lua",
      ('\tstars:SetTexture(Theme.Media("band-stars"))\n',
       '\t-- (Evertally: no stars; the layer stays, empty, for the code that shows and hides it)\n', 1),
      # One look: Evertally's own (addon/Evertally/GuideSkin.lua); the others are not offered. Without it (Evertally
      # missing) every look is listed as before.
      ('\t\tif s and (Theme._testShowHidden or not HIDDEN_SKINS[id]) then\n\t\t\tif s.builtin then',
       '\t\tif s and (Theme._testShowHidden or not HIDDEN_SKINS[id]) and (id == "evertally" or not SKINS.evertally) then\n\t\t\tif s.builtin then', 1))
_more("UI/Welcome.lua",
      ('\t\tbeam:SetShown(house())\n', '\t\tbeam:SetShown(false) -- (Evertally: no beam, no stars)\n', 1),
      ('\tfunction dipper(parent, ox, oy, scale, deg)\n',
       '\tfunction dipper(parent, ox, oy, scale, deg)\n\t\tdo return end -- (Evertally: no stars)\n', 1),
      # One look, so no page to choose it.
      ('\t\tkey = "look",\n\t\tshown = function() return full end,',
       '\t\tkey = "look",\n\t\tshown = function() return false end, -- (Evertally: one look, nothing to choose)', 1))
# No beta: Evertally is released; the version shown is Evertally's (ns.ShownVersion), not Polestar's.
_more("Core/Init.lua",
      ('ns.stage = "Beta"', 'ns.stage = nil -- (Evertally: no beta)', 1),
      ('ns.routesBeta = true', 'ns.routesBeta = false -- (Evertally)', 1),
      ('ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"\n',
       'ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"\n'
       '-- Evertally: the version players see is Evertally\'s (ns.version stays Polestar\'s for the party and the packs).\n'
       'function ns.ShownVersion()\n\tlocal E = rawget(_G, "Evertally")\n'
       '\treturn type(E) == "table" and E.version and tostring(E.version) or ns.version\nend\n', 1))
# Only English and Czech ship: no line about the other languages' missing folders (bod 3 of the handoff).
_more("Core/Locale.lua",
      ('local language = pack and LANGUAGE[pack:match("^Evertally_Guide_(.+)$") or ""]',
       'local language = nil -- (Evertally: English and Czech only, nothing to miss; was LANGUAGE[pack])', 1))
_more("Core/Data.lua",
      ('\tif language then check(language, s) end\n',
       '\t-- (Evertally: no language folders but Czech, which Evertally loads itself)\n', 1))
# The party panel opens from the Evertally menu, not by itself.
_more("Quests/Party.lua",
      ('waitForGroup = true, lootNeeds = true, panel = true,', 'waitForGroup = true, lootNeeds = true, panel = false,', 1))
# Lookup is the Database: with no search it browses, each kind A to Z (Search.Browse), still searched from the box.
_more("Core/Search.lua",
      ('function Search.Status()\n',
       '-- Evertally: browsing, Lookup with nothing typed (the Database): a kind A to Z, a page at a time. Retired and\n'
       '-- sourceless entries are left out. The first page of each kind (a few names) is read in one pass; a whole kind is\n'
       '-- sorted once, when it is opened. -> results (as Query\'s), total\n'
       'local browsed = {}\n'
       'local BROWSE_LINE = "\\2([^\\1]*)\\1([^,]*),(%d*),(%a?),%d+\\n"\n'
       'local function browseResult(kind, rawId, quality)\n'
       '\tlocal C = ns.Codex\n'
       '\tlocal id = kind == "instance" and rawId or tonumber(rawId)\n'
       '\treturn { kind = kind, id = id, title = (localised() and localName(kind, id)) or C.Name(kind, id) or rawId,\n'
       '\t\tquality = tonumber(quality), score = 0, curated = curated[id] or nil }\n'
       'end\n'
       'function Search.Browse(kind, offset, count)\n'
       '\toffset, count = offset or 0, count or 50\n'
       '\tlocal out = {}\n'
       '\tif kind == "guide" then\n'
       '\t\tlocal list = guideList()\n'
       '\t\tlocal sorted = {}\n'
       '\t\tfor i = 1, #list do sorted[i] = list[i] end\n'
       '\t\ttable.sort(sorted, function(a, b) return a.folded < b.folded end)\n'
       '\t\tfor j = offset + 1, min(#sorted, offset + count) do\n'
       '\t\t\tlocal g = sorted[j]\n'
       '\t\t\tout[#out + 1] = { kind = "guide", id = g.id, title = g.title, subtitle = g.subtitle, score = 0 }\n'
       '\t\tend\n'
       '\t\treturn out, #sorted\n'
       '\tend\n'
       '\tif not codexOn() then return out, 0 end\n'
       '\tlocal C = ns.Codex\n'
       '\tif C and C.IsLoaded and not C.IsLoaded() and C.Load then C.Load() end\n'
       '\tlocal blob = codexBlob(kind)\n'
       '\tif not blob then return out, 0 end\n'
       '\tguideList() -- the curated set\n'
       '\tlocal b = browsed[kind]\n'
       '\tif not b or b.blob ~= blob then b = { blob = blob }; browsed[kind] = b end\n'
       '\tif not b.lines and offset == 0 and count <= 10 and b.first and b.firstN == count then\n'
       '\t\tfor i, res in ipairs(b.first) do out[i] = res end\n'
       '\t\treturn out, b.total\n'
       '\tend\n'
       '\tif not b.lines and offset == 0 and count <= 10 then\n'
       '\t\t-- the first few names and the count, without sorting the kind\n'
       '\t\tlocal names, ids, quals, n, total = {}, {}, {}, 0, 0\n'
       '\t\tfor folded, id, q, st in gmatch(blob, BROWSE_LINE) do\n'
       '\t\t\tif st == "" and folded ~= "" then\n'
       '\t\t\t\ttotal = total + 1\n'
       '\t\t\t\tif n < count or folded < names[n] then\n'
       '\t\t\t\t\tlocal pos = n < count and n + 1 or n\n'
       '\t\t\t\t\twhile pos > 1 and names[pos - 1] > folded do\n'
       '\t\t\t\t\t\tnames[pos], ids[pos], quals[pos] = names[pos - 1], ids[pos - 1], quals[pos - 1]\n'
       '\t\t\t\t\t\tpos = pos - 1\n'
       '\t\t\t\t\tend\n'
       '\t\t\t\t\tnames[pos], ids[pos], quals[pos] = folded, id, q\n'
       '\t\t\t\t\tif n < count then n = n + 1 end\n'
       '\t\t\t\tend\n'
       '\t\t\tend\n'
       '\t\tend\n'
       '\t\tb.total = total\n'
       '\t\tfor i = 1, n do out[i] = browseResult(kind, ids[i], quals[i]) end\n'
       '\t\tb.first, b.firstN = {}, count\n'
       '\t\tfor i, res in ipairs(out) do b.first[i] = res end\n'
       '\t\treturn out, total\n'
       '\tend\n'
       '\tif not b.lines then\n'
       '\t\tlocal lines = {}\n'
       '\t\tfor folded, id, q, st in gmatch(blob, BROWSE_LINE) do\n'
       '\t\t\tif st == "" and folded ~= "" then lines[#lines + 1] = folded .. "\\1" .. id .. "\\1" .. q end\n'
       '\t\tend\n'
       '\t\ttable.sort(lines)\n'
       '\t\tb.lines, b.total = lines, #lines\n'
       '\tend\n'
       '\tfor j = offset + 1, min(#b.lines, offset + count) do\n'
       '\t\tlocal id, q = match(b.lines[j], "\\1([^\\1]*)\\1(.*)$")\n'
       '\t\tout[#out + 1] = browseResult(kind, id, q)\n'
       '\tend\n'
       '\treturn out, b.total\n'
       'end\n\n'
       'function Search.Status()\n', 1))
_more("UI/Lookup.lua",
      ('local cache = {}\nlocal function current()\n',
       '-- Evertally: nothing typed browses (the Database): every kind A to Z (Search.Browse).\n'
       'local function browse(k, offset, count)\n'
       '\tlocal S = ns.Search\n'
       '\tif not (S and S.Browse) then return {}, 0 end\n'
       '\tlocal ok, list, total = pcall(S.Browse, k, offset, count)\n'
       '\tif not ok then return {}, 0 end\n'
       '\treturn list or {}, total or 0\n'
       'end\n'
       'local function browseAll()\n'
       '\tlocal all, counts = {}, {}\n'
       '\tfor _, k in ipairs(kinds()) do\n'
       '\t\tlocal list, total = browse(k.key, 0, GROUP_MAX)\n'
       '\t\tif total > 0 then\n'
       '\t\t\tcounts[k.key] = total\n'
       '\t\t\tfor _, r in ipairs(list) do all[#all + 1] = r end\n'
       '\t\tend\n'
       '\tend\n'
       '\treturn all, counts\n'
       'end\n\n'
       'local cache = {}\nlocal function current()\n', 1),
      ('\t\t\tlist = (search(query, { [kind] = true }, { perKind = PAGE, limit = PAGE, offset = 0, subtitles = false }))\n\t\tend\n\tend\n',
       '\t\t\tlist = (search(query, { [kind] = true }, { perKind = PAGE, limit = PAGE, offset = 0, subtitles = false }))\n\t\tend\n'
       '\telse\n'
       '\t\tall, counts = browseAll()\n'
       '\t\tif kind == "all" then list = all else list = (browse(kind, 0, PAGE)) end\n'
       '\tend\n', 1),
      ('\tif kind == "all" or query == "" then return end\n'
       '\tlocal more = search(query, { [kind] = true }, { perKind = PAGE, limit = PAGE, offset = #c.list, subtitles = false })\n',
       '\tif kind == "all" then return end\n'
       '\tlocal more = query == "" and (browse(kind, #c.list, PAGE))\n'
       '\t\tor search(query, { [kind] = true }, { perKind = PAGE, limit = PAGE, offset = #c.list, subtitles = false })\n', 1),
      ('local NAV_MAX = 10\n', 'local NAV_MAX = 12\n', 1),
      ('\tlocal title = (kind == "all" or query == "") and L["Lookup"] or kindLabel(kind)\n',
       '\tlocal title = kind == "all" and L["Database"] or kindLabel(kind)\n', 1),
      ('\tif query == "" then\n\t\t-- No search: the recent lookups, never a data set.\n',
       '\tif query == "" and kind == "all" then\n\t\t-- No search: the recent lookups, then (Evertally) the database, every kind A to Z.\n', 1),
      ('\t\t\tfor _, r in ipairs(recent) do row({ kind = r.kind, id = r.id, title = r.title, quality = r.quality, status = r.status }) end\n'
       '\t\tend\n\telse\n\t\tlocal byKind = {}\n',
       '\t\t\tfor _, r in ipairs(recent) do row({ kind = r.kind, id = r.id, title = r.title, quality = r.quality, status = r.status }) end\n'
       '\t\tend\n\tend\n\tdo\n\t\tlocal byKind = {}\n', 1),
      ('\telseif query == "" then\n\t\tempty = loaded and',
       '\telseif query == "" and #list == 0 then\n\t\tempty = loaded and', 1),
      ('\t\tkey = "Lookup", label = L["Lookup"], icon = "search", order = 20,',
       '\t\tkey = "Lookup", label = L["Database"], icon = "search", order = 20,', 1))
_more("UI/GuideFrame.lua",
      ('nav.Lookup = W.IconButton(nav, "search", 24, L["Lookup"], function() UI.ShowLookup() end)',
       'nav.Lookup = W.IconButton(nav, "search", 24, L["Database"], function() UI.ShowLookup() end)', 1))
# The window's height follows the grip too: dragging it up or down sets the tallest the window may be (ui.maxHeight);
# past it the steps and the quest tracker scroll. GF.dragShare holds it while dragging (UI/GuideFrameLayout.lua).
_more("UI/GuideFrameWindow.lua",
      ('\tlocal function resizeUpdate(self)\n'
       '\t\tlocal x = GetCursorPosition() / F:GetEffectiveScale()\n'
       '\t\tlocal w = min(UI.MAX_WIDTH, max(UI.MIN_WIDTH, floor(self.psStartW + (x - self.psStartX) + 0.5)))\n'
       '\t\tif w ~= floor(F:GetWidth() + 0.5) then\n',
       '\tlocal function resizeUpdate(self)\n'
       '\t\tlocal cx, cy = GetCursorPosition()\n'
       '\t\tlocal x = cx / F:GetEffectiveScale()\n'
       '\t\tlocal w = min(UI.MAX_WIDTH, max(UI.MIN_WIDTH, floor(self.psStartW + (x - self.psStartX) + 0.5)))\n'
       '\t\t-- Evertally: the height too (ui.maxHeight, a share of the screen)\n'
       '\t\tlocal dy = (self.psStartY or 0) - cy / F:GetEffectiveScale()\n'
       '\t\tif ns.Get("ui.growUp") then dy = -dy end\n'
       '\t\tlocal screen = UIParent:GetHeight() * UIParent:GetEffectiveScale()\n'
       '\t\tlocal share = min(0.95, max(0.15, ((self.psStartH or F:GetHeight()) + dy) * F:GetEffectiveScale() / screen))\n'
       '\t\tlocal tall = (GF.dragShare or math.abs(dy) > 4) and math.abs(share - (GF.dragShare or -1)) > 0.001\n'
       '\t\tif tall then GF.dragShare = share end\n'
       '\t\tif w ~= floor(F:GetWidth() + 0.5) or tall then\n', 1),
      ('\t\tself.psStartW = F:GetWidth()\n',
       '\t\tself.psStartW = F:GetWidth()\n'
       '\t\tlocal _, cy = GetCursorPosition()\n'
       '\t\tself.psStartY, self.psStartH, GF.dragShare = cy / F:GetEffectiveScale(), F:GetHeight(), nil\n', 1),
      ('\t\tns.Set("ui.width", floor(F:GetWidth() + 0.5))\n',
       '\t\tns.Set("ui.width", floor(F:GetWidth() + 0.5))\n'
       '\t\tif GF.dragShare then\n'
       '\t\t\tlocal share = floor(GF.dragShare * 1000 + 0.5) / 1000\n'
       '\t\t\tGF.dragShare = nil\n'
       '\t\t\tns.Set("ui.maxHeight", share)\n'
       '\t\tend\n', 1))
# The guide's own buttons (the minimap one, when a player turns it on; the floating one; the addon compartment) click as
# Evertally's: left the Evertally menu, right hides Evertally (or shows it again) - bod 6 of the handoff.
_more("Maps/MinimapButton.lua",
      ('function Maps.ButtonTip(owner, drag)\n',
       '-- Evertally: hiding goes through Evertally (its window and its minimap button too) while it is there.\n'
       'function Maps.ToggleHidden()\n'
       '\tlocal E = rawget(_G, "Evertally")\n'
       '\tif type(E) == "table" and E.ToggleEvertallyHidden then return E.ToggleEvertallyHidden() end\n'
       '\treturn ns.ToggleHidden()\n'
       'end\n\n'
       'function Maps.ButtonTip(owner, drag)\n', 1),
      ('{ L["Evertally is hidden: click to show"], T.Accent() } or L["Click: hide Evertally"] }',
       '{ L["Evertally is hidden: right-click to show"], T.Accent() } or L["Right-click: hide Evertally"] }', 1),
      ('L["Evertally is paused: right-click to resume"]', 'L["Evertally is paused: resume it in the menu"]', 1),
      ('\tlines[#lines + 1] = L["Right-click: menu"]\n', '\tlines[#lines + 1] = L["Click: menu"]\n', 1),
      ('\tif which == "RightButton" then\n\t\tMaps.ShowMenu(row or UIParent)\n\telse\n\t\tns.ToggleHidden()\n\tend\n',
       '\tif which == "RightButton" then\n\t\tMaps.ToggleHidden()\n\telse\n\t\tMaps.ShowMenu(row or UIParent)\n\tend\n', 1),
      ('\t\tif which == "RightButton" then\n\t\t\tW.HideTooltip(self)\n\t\t\tMaps.ShowMenu(self)\n\t\telse\n\t\t\tns.ToggleHidden()\n',
       '\t\tif which ~= "RightButton" then\n\t\t\tW.HideTooltip(self)\n\t\t\tMaps.ShowMenu(self)\n\t\telse\n\t\t\tMaps.ToggleHidden()\n', 1))
_more("UI/Launcher.lua",
      ('\t\tif which == "RightButton" then\n\t\t\tW.HideTooltip(self)\n\t\t\tns.Maps.ShowMenu(self)\n'
       '\t\telseif not ns.DragMoved(self) then\n\t\t\tns.ToggleHidden()\n',
       '\t\tif which == "RightButton" then\n\t\t\tns.Maps.ToggleHidden()\n'
       '\t\telseif not ns.DragMoved(self) then\n\t\t\tW.HideTooltip(self)\n\t\t\tns.Maps.ShowMenu(self)\n'
       '\t\t\tdo return end\n', 1))

# The settings' About group is About alone: no Guiding Stars (Polestar's supporters, and its "Special thanks to:" in the
# headers), no Recorder (for Polestar's guide authors). About says where Evertally Guide comes from: Polestar, its
# engine and its guides; the version is Evertally's.
_more("UI/Options.lua",
      ('add({ page = L["Guiding Stars"], key = "thanks", icon = "star", order = 80,',
       'if false then add({ page = L["Guiding Stars"], key = "thanks", icon = "star", order = 80,', 1),
      ('\tcustom = UI.Thanks.Build }, true)\n',
       '\tcustom = UI.Thanks.Build }, true) end -- (Evertally: no Guiding Stars)\n', 1),
      ('add({ page = REC, key = "recorder", icon = "record", order = 90,',
       'if false then add({ page = REC, key = "recorder", icon = "record", order = 90,', 1),
      ('custom = buildRecorder }, true)\n', 'custom = buildRecorder }, true) end -- (Evertally: no Recorder)\n', 1),
      ('\tlocal paras = {\n\t\tL["Leveling guides have become a business:',
       '\tlocal paras = {\n\t\thex .. L["Evertally Guide is inspired by Polestar and built on it: the guide engine and the leveling guides are the work of the Polestar authors (github.com/fitzforge/polestar, GPL-3.0). Thank you."] .. "|r",\n'
       '\t\tL["Leveling guides have become a business:', 1),
      ('\t\tlocal v = L["Version"] .. " " .. tostring(ns.version or "dev")\n',
       '\t\tlocal v = L["Version"] .. " " .. tostring(ns.ShownVersion and ns.ShownVersion() or ns.version or "dev")\n', 1),
      ('block(L["Credits"], L["Inter typeface by',
       'block(L["Credits"], L["Leveling guides, the guide engine and its data: Polestar by the Polestar authors (GPL-3.0)."] .. "\\n"\n\t\t.. L["Inter typeface by', 1))
_more("UI/Thanks.lua",
      ('function T.HeaderLink(f)\n', 'function T.HeaderLink(f)\n\tdo return end -- (Evertally: no "Special thanks to:" in the headers)\n', 1))

# Evertally's own strings in Czech (not in Polestar, so not in tools/polestar-cs/keys.json).
EXTRA_CS = {
    "Database": "Databáze",
    "Evertally is hidden: right-click to show": "Evertally je skrytý: pravým tlačítkem ho ukážeš",
    "Right-click: hide Evertally": "Pravé tlačítko: skrýt Evertally",
    "Evertally is paused: resume it in the menu": "Evertally je pozastavený: obnovíš ho v menu",
    "Click: menu": "Klik: menu",
    "Evertally Guide is inspired by Polestar and built on it: the guide engine and the leveling guides are the work of the Polestar authors (github.com/fitzforge/polestar, GPL-3.0). Thank you.":
        "Evertally Guide vychází z Polestaru a je na něm postavený: engine průvodce i návody na levelování jsou práce autorů Polestaru (github.com/fitzforge/polestar, GPL-3.0). Děkujeme.",
    "Leveling guides, the guide engine and its data: Polestar by the Polestar authors (GPL-3.0).":
        "Návody na levelování, engine průvodce a jeho data: Polestar od autorů Polestaru (GPL-3.0).",
}

# Slash commands: Polestar's own words would clash with an installed Polestar (the game picks one of the two).
SLASH_WORDS = [(re.compile(r"(?<![\w./])/polestar\b"), "/etguide"), (re.compile(r"(?<![\w./])/pole\b"), "/etg")]
# Ids other add-ons key us by, spelled in lower case ("polestar_quest_needed": a Baganator corner widget). Registering
# Polestar's id a second time fails ("Baganator API/Main.lua:230: assertion failed"). Plain "polestar" (the default
# skin's id) is ours alone and stays.
LOWER_ID = re.compile(r"^polestar_([a-z_]+)$")
# Everywhere: a few literals that name the add-on itself or are shown as its name.
GLOBAL_PATCHES = [
    ('GetAddOnMemoryUsage, "Polestar"', 'GetAddOnMemoryUsage, "Evertally_Guide"'),
    ('L["Polestar"] = "Polestar"', 'L["Polestar"] = "Evertally"'),
    ('Tooltip(owner, "ANCHOR_LEFT", "Polestar"', 'Tooltip(owner, "ANCHOR_LEFT", "Evertally"'),
    ('RegisterCanvasLayoutCategory, canvas, "Polestar")', 'RegisterCanvasLayoutCategory, canvas, "Evertally Guide")'),
]

LUA_TOKEN = re.compile(
    r"(--\[(=*)\[.*?\]\2\])"              # long comment
    r"|(--[^\n]*)"                         # comment
    r"|(\[(=*)\[.*?\]\5\])"                # long string
    r"|(\"(?:\\.|[^\"\\\n])*\")"           # "string"
    r"|('(?:\\.|[^'\\\n])*')",             # 'string'
    re.S)


# ---- 2026-11-18: labels read while the guide's files load (before Evertally chose Czech) are translated again by
# Evertally (addon/Evertally/EvertallySettings.lua relabel): the local tables it cannot reach are handed out.
_more('UI/Picker.lua', ('local VIEW_LABEL = { home = L["Home"], browse = L["Browse"], current = L["Current"], recent = L["Recent"] }\n',
      'local VIEW_LABEL = { home = L["Home"], browse = L["Browse"], current = L["Current"], recent = L["Recent"] }\n-- Evertally: read while this file loads, before Evertally chose Czech: Evertally translates them again (EvertallySettings.lua)\nP.VIEW_LABEL = VIEW_LABEL\n', 1))
_more('UI/Picker.lua', ('local GUIDES = { key = "Guides", label = L["Guides"], icon = "guides", order = 10, builtin = true }\n',
      'local GUIDES = { key = "Guides", label = L["Guides"], icon = "guides", order = 10, builtin = true }\nP.GUIDES = GUIDES -- (Evertally translates its label again, as VIEW_LABEL)\n', 1))
_more('UI/Picker.lua', ('local HUB_SEARCH = { L["Search guides, items, NPCs"], L["Search guides, items"], L["Search"] }\n',
      'local HUB_SEARCH = { L["Search guides, items, NPCs"], L["Search guides, items"], L["Search"] }\nP.HUB_SEARCH = HUB_SEARCH -- (Evertally translates it again, as VIEW_LABEL)\n', 1))
_more('UI/Lookup.lua', ('local FACTION = { A = ns.FactionName("A"), H = ns.FactionName("H"), AH = L["Both factions"] }\n',
      'local FACTION = { A = ns.FactionName("A"), H = ns.FactionName("H"), AH = L["Both factions"] }\n-- Evertally: read while this file loads, before Evertally chose Czech: Evertally translates them again (EvertallySettings.lua)\nLK.FACTION, LK.FALLBACK_KINDS = FACTION, FALLBACK_KINDS\n', 1))
_more('UI/Lookup.lua', ('local STATUS_TEXT = { retired = L["No longer obtainable"], nosource = L["No known source"] }\n',
      'local STATUS_TEXT = { retired = L["No longer obtainable"], nosource = L["No known source"] }\nLK.STATUS_TEXT = STATUS_TEXT -- (Evertally translates it again)\n', 1))
_more('Rares/View.lua', ('local LIST_W = 272\n',
      "-- Evertally: the list wide and the details 372 px on the right, as the Database (UI/Lookup.lua DETAIL_W) and\n-- Evertally's own pages: 878 (the main column at the default width) - 372\nlocal LIST_W = 506\n", 1))
# ---- 2026-11-18: the sections' categories as tabs, Evertally's menu in the sidebar of every section
_more('UI/Picker.lua', ('local function renderSection(s)\n',
      '-- Evertally: a section\'s own index (its nav: the Database\'s kinds, the Rares\' tabs) is a row of tabs over its page,\n-- and the sidebar holds Evertally\'s menu in every section, one click from any of its pages.\nlocal EVERTALLY_KEY = "Evertally"\nlocal function sectionTabs(s)\n\tif s.key == EVERTALLY_KEY or not s.nav then return false end\n\tlocal ok, items, activeKey = pcall(s.nav)\n\tif not ok or type(items) ~= "table" then return false end\n\tlocal tabs = {}\n\tfor _, it in ipairs(items) do\n\t\tif not it.separator and not it.heading and it.key and it.key ~= "" then tabs[#tabs + 1] = { key = it.key, label = it.label or it.key } end\n\tend\n\tif #tabs < 2 then return false end\n\tW.ShellTabs(win, tabs, activeKey, function(key) if s.onNav then s.onNav(key) end end)\n\treturn true\nend\nlocal function evertallyNav()\n\tfor _, s in ipairs(sections) do\n\t\tif s.key == EVERTALLY_KEY and s.nav then\n\t\t\tlocal ok, items = pcall(s.nav)\n\t\t\tif not ok or type(items) ~= "table" then return false end\n\t\t\tW.ShellNav(win, items, nil, function(key) P.ShowSection(s.key); if s.onNav then s.onNav(key) end end)\n\t\t\treturn true\n\t\tend\n\tend\n\treturn false\nend\n\nlocal function renderSection(s)\n', 1))
_more('UI/Picker.lua', ('\t-- No tabs until the section sets its own (its render may).\n\tW.ShellTabs(win, nil)\n\ts.render()\n',
      '\t-- No tabs until the section sets its own (its render may).\n\tW.ShellTabs(win, nil)\n\ts.render()\n\tsectionTabs(s) -- (Evertally: after its render, which may clear the row)\n', 1))
_more('UI/Picker.lua', ('local function sectionNav(s)\n',
      "local function sectionNav(s)\n\t-- Evertally: the section's own index is its tab row (sectionTabs); the sidebar is Evertally's menu\n\tif s.key ~= EVERTALLY_KEY and evertallyNav() then return end\n", 1))
_more('UI/Picker.lua', ('\tW.ShellNav(win, navItems(counts, total), view == "browse" and category or nil, function(key) P.SetCategory(key) end)\n\tlocal tabsList = {}\n\tfor i, v in ipairs(VIEWS) do tabsList[i] = { key = v, label = VIEW_LABEL[v] } end\n\tW.ShellTabs(win, tabsList, view, function(key) P.SetView(key) end)\n',
      '\t-- Evertally: the guides\' categories are tabs after Home, Current and Recent (Browse is the category tabs); the\n\t-- sidebar holds Evertally\'s menu (evertallyNav), or the categories when Evertally is not there.\n\tlocal navList = navItems(counts, total)\n\tlocal tabsList = {}\n\tfor _, v in ipairs(VIEWS) do if v ~= "browse" then tabsList[#tabsList + 1] = { key = v, label = VIEW_LABEL[v] } end end\n\tfor _, it in ipairs(navList) do\n\t\tif not it.heading and it.key ~= "" then tabsList[#tabsList + 1] = { key = "cat:" .. it.key, label = it.label } end\n\tend\n\tW.ShellTabs(win, tabsList, view == "browse" and ("cat:" .. category) or view, function(key)\n\t\tif key:sub(1, 4) == "cat:" then P.SetCategory(key:sub(5)) else P.SetView(key) end\n\tend)\n\tif not evertallyNav() then\n\t\tW.ShellNav(win, navList, view == "browse" and category or nil, function(key) P.SetCategory(key) end)\n\tend\n', 1))
# ---- 2026-11-19: one home per setting in the settings window (the user: "co jde to sluc.. duplicity pryc")
_more('UI/Options.lua', ('local function add(spec, builtin)\n\tIndex.spec = nil\n',
      '-- Evertally: one home per setting. A setting the guide offered on two to four pages keeps the page where the\n-- feature is switched on (Guide, Map, Questing, Discovery, Quality of Life); the Look pages keep how it looks. A key\n-- registered twice on the same page keeps its first row. A registration left with no rows adds nothing.\nlocal EV_DROP = {\n\tguidewindow = { ["ui.compact"] = true, ["ui.maxHeight"] = true, ["ui.showNotes"] = true, ["ui.upcoming"] = true,\n\t\t["ui.combat"] = true, ["ui.instance"] = true, ["ui.growUp"] = true, ["ui.barsBottom"] = true },\n\tbuttons = { ["ui.launcher"] = true, ["maps.minimapButton"] = true, ["maps.minimapButtonSize"] = true, ["qol.itemButton"] = true, ["qol.targetButton"] = true,\n\t\t["qol.hearthButton"] = true, ["nav.castPrompt"] = true, ["qol.rareButton"] = true, ["qol.targetPlate"] = true },\n\tmap = { ["maps.minimapButton"] = true },\n\t-- (the guide\'s minimap button: Evertally\'s own is on its Interface page)\n\tguide = { ["behavior.trainReminder"] = true, ["nav.lineStyle"] = true, ["maps.minimapButton"] = true },\n\tarrow = { ["nav.arrow"] = true, ["nav.hideArrowWithGuide"] = true, ["nav.arrowEta"] = true, ["nav.distanceUnit"] = true,\n\t\t["nav.arrivalSound"] = true },\n\troutelines = { ["nav.routeLines"] = true, ["nav.minimapRoute"] = true },\n\tmappins = { ["nav.worldPins"] = true, ["nav.minimapPins"] = true, ["nav.trailDots"] = true, ["nav.upcomingPins"] = true },\n\ttrackers = { ["nav.journeySteps"] = true, ["maps.flightTimer"] = true, ["maps.instances"] = true,\n\t\t["maps.instanceDisplay"] = true, ["qol.xpTargetMark"] = true, ["party.panel"] = true },\n\talerts = { ["nav.alerts"] = true, ["nav.alertBanner"] = true, ["nav.alertSound"] = true, ["nav.alertFlash"] = true,\n\t\t["rares.alerts"] = true, ["rares.toastSeconds"] = true, ["rares.treasureAlerts"] = true, ["rares.soundKit"] = true,\n\t\t["rares.sound"] = true, ["rares.combatAlerts"] = true, ["dungeons.headsUp"] = true },\n\tqualityoflife = { ["maps.minimapButton"] = true, ["nav.alerts"] = true, ["nav.nearbyMenu"] = true, ["nav.nearbyButton"] = true,\n\t\t["qol.hearthButton"] = true, ["nav.castPrompt"] = true, ["qol.itemButton"] = true,\n\t\t["behavior.autoAccept"] = true, ["behavior.autoTurnin"] = true, ["qol.instantQuestText"] = true, ["qol.skipGossip"] = true,\n\t\t["qol.fastLoot"] = true, ["qol.hideErrors"] = true, ["qol.hideQuestTracker"] = true, ["qol.instanceTrack"] = true,\n\t\t["qol.rewardAutoPick"] = true, ["qol.rewardEquip"] = true, ["qol.questLoot"] = true, ["qol.stepInteract"] = true,\n\t\t["maps.coords"] = true, ["maps.minimapCoords"] = true },\n}\nO.EV_DROP = EV_DROP\nlocal evSeen = {}\n-- Pages that draw the same kind of thing are one page: the map\'s pins and its route lines; the alerts and the\n-- trackers (cards and panels on the screen). The page merged in gives its tabs; its own Essentials stay out (one\n-- preset row per page). Old keys still open it (ALIASES).\nlocal EV_MERGE = {\n\tmappins = { "mappins", L["Map pins & routes"], "icon-goto", 23, L["How the guide\'s pins and route lines look on the world map and the minimap."] },\n\troutelines = { "mappins", L["Map pins & routes"], "icon-goto", 23, L["How the guide\'s pins and route lines look on the world map and the minimap."] },\n\talerts = { "alerts", L["Alerts & trackers"], "info", 26, L["The alerts that pop up and the trackers on the screen: their size, their look and when they show."] },\n\ttrackers = { "alerts", L["Alerts & trackers"], "info", 26, L["The alerts that pop up and the trackers on the screen: their size, their look and when they show."] },\n}\nO.EV_MERGE = EV_MERGE\n-- (a page\'s later registrations may give only its name, and that is translated: the key is the one its first\n-- registration with a key gave, so the rules hold in every language)\nlocal evKeyOf = {}\nlocal function evKey(spec)\n\tlocal name = spec.page or ""\n\tif spec.key then evKeyOf[name] = keyOf(spec.key) end\n\treturn evKeyOf[name] or keyOf(name)\nend\nlocal function evertallyKeep(spec)\n\tlocal pk = evKey(spec)\n\tlocal merge = EV_MERGE[pk]\n\tif merge then\n\t\tif pk ~= merge[1] and spec.tab == L["Essentials"] then return false end\n\t\tspec.page, spec.key, spec.icon, spec.order = merge[2], merge[1], merge[3], merge[4]\n\t\tif spec.subtitle then spec.subtitle = merge[5] end\n\tend\n\tlocal drop, seen = EV_DROP[pk], evSeen[pk] or {}\n\tevSeen[pk] = seen\n\tlocal function keep(c)\n\t\tif type(c) ~= "table" or type(c.key) ~= "string" or rawget(c, "ref") then return true end\n\t\tif drop and drop[c.key] then return false end\n\t\tif seen[c.key] then return false end\n\t\tseen[c.key] = true\n\t\treturn true\n\tend\n\tlocal had = (spec.controls and #spec.controls or 0) + (spec.toggle and 1 or 0)\n\tif spec.toggle and not keep(spec.toggle) then spec.toggle = nil end\n\tif spec.controls then\n\t\tlocal list = {}\n\t\tfor _, c in ipairs(spec.controls) do if keep(c) then list[#list + 1] = c end end\n\t\tspec.controls = list\n\t\t-- a row\'s own extras and more (a size slider\'s on/off beside it) follow the same rule\n\t\tlocal function inner(c)\n\t\t\tfor _, field in ipairs({ "extras", "more" }) do\n\t\t\t\tlocal sub = rawget(c, field)\n\t\t\t\tif type(sub) == "table" then\n\t\t\t\t\tlocal kept = {}\n\t\t\t\t\tfor _, e in ipairs(sub) do if keep(e) then kept[#kept + 1] = e; inner(e) end end\n\t\t\t\t\tc[field] = kept\n\t\t\t\tend\n\t\t\tend\n\t\tend\n\t\tfor _, c in ipairs(list) do inner(c) end\n\tend\n\tlocal left = (spec.controls and #spec.controls or 0) + (spec.toggle and 1 or 0)\n\treturn had == 0 or left > 0 or spec.custom ~= nil or spec.preview ~= nil\nend\n\nlocal function add(spec, builtin)\n\tif not evertallyKeep(spec) then return end\n\tIndex.spec = nil\n', 1))
# ---- 2026-11-19: merged settings pages keep their old keys (ALIASES)
_more('UI/Options.lua', ('\ttargeting = { "questing", L["Buttons"] },\n}',
      '\ttargeting = { "questing", L["Buttons"] },\n\t-- Evertally: pages merged into others (EV_MERGE)\n\troutelines = { "mappins", L["Route"] }, trackers = { "alerts", L["Travel"] },\n}', 1))
# ---- 2026-11-19: one failing tween froze every animation (the setup's page stayed at alpha 0, no texts)
_more('Theme/Anim.lua', ('local function step()\n\tlocal now = GetTime()\n\tlocal i = 1\n\twhile i <= count do\n\t\tlocal rec = active[i]\n\t\tlocal p = (now - rec.t0) / rec.dur\n\t\tif p >= 1 then\n\t\t\tactive[i] = active[count]\n\t\t\tactive[count] = nil\n\t\t\tcount = count - 1\n\t\t\tfinish(rec)\n\t\telse\n\t\t\tif p < 0 then p = 0 end\n\t\t\tAPPLY[rec.kind](rec.obj, rec.from + (rec.to - rec.from) * rec.ease(p))\n\t\t\ti = i + 1\n\t\tend\n\tend\n\tif count == 0 then driver:SetScript("OnUpdate", nil) end\nend\n',
      '-- Evertally: a tween whose object fails is dropped (put at its end), not met again every frame. Before, one failing\n-- tween stopped the loop on it for good and froze every other: the setup\'s page stayed at alpha 0, its texts unseen.\n-- The error still goes to the handler (ns.Safe), once, after the others have moved.\nlocal function step()\n\tlocal now = GetTime()\n\tlocal i = 1\n\tlocal failed\n\twhile i <= count do\n\t\tlocal rec = active[i]\n\t\tlocal p = (now - rec.t0) / rec.dur\n\t\tlocal ok, err = true, nil\n\t\tif p >= 1 then\n\t\t\tactive[i] = active[count]\n\t\t\tactive[count] = nil\n\t\t\tcount = count - 1\n\t\t\tok, err = pcall(finish, rec)\n\t\telse\n\t\t\tif p < 0 then p = 0 end\n\t\t\tok, err = pcall(APPLY[rec.kind], rec.obj, rec.from + (rec.to - rec.from) * rec.ease(p))\n\t\t\tif ok then\n\t\t\t\ti = i + 1\n\t\t\telse\n\t\t\t\tactive[i] = active[count]\n\t\t\t\tactive[count] = nil\n\t\t\t\tcount = count - 1\n\t\t\t\trec.running = false\n\t\t\t\tpcall(APPLY[rec.kind], rec.obj, rec.to)\n\t\t\tend\n\t\tend\n\t\tif not ok and failed == nil then failed = err end\n\tend\n\tif count == 0 then driver:SetScript("OnUpdate", nil) end\n\tif failed ~= nil then error(failed, 0) end\nend\n', 1),
      ('\t\trec.dur = 1e-9\n\t\trec.t0 = GetTime() - 1\n\t\tstep()\n', "\t\trec.dur = 1e-9\n\t\trec.t0 = GetTime() - 1\n\t\tpcall(step) -- (Evertally: another tween's failure is not the caller's)\n", 1))
# ---- 2026-11-19: quest mobs' nameplate icon: a loot bag where a quest item drops, a sword where it is only a kill
_more('Quests/Tooltips.lua', ('\t-- All objectives on nameplates are mobs to kill or loot: show the game\'s skull.\n\tlocal skullTex = ns.Theme and ns.Theme.Media and ns.Theme.Media("icon-skull")\n\t\tor "Interface\\\\TargetingFrame\\\\UI-RaidTargetingIcon_8"\n\tf.tex:SetTexture(skullTex)\n\tf.tex:SetVertexColor(1, 1, 1, 1)\n',
      '\t-- Evertally (2026-11-19, as Questie did): a mob a quest item drops from carries a loot bag, a mob only to kill a\n\t-- sword: the game\'s own icon art (Fat Sack of Coins 133639, Worn Shortsword 135274) with no background\n\t-- (Media/UI/quest-loot, quest-kill; the user: "at to nemá pozadí"). Any open loot objective makes it the bag.\n\t-- (2 = Tracker.lua\'s KIND_ITEM)\n\tlocal loot = false\n\tlocal list = Q.ObjectivesForNpc(npc)\n\tfor i = 1, list and #list or 0 do\n\t\tlocal o = list[i]\n\t\tif not o.done and not o.entry.ready and o.kind == 2 then loot = true; break end\n\tend\n\tf.tex:SetTexture("Interface\\\\AddOns\\\\Evertally_Guide\\\\Media\\\\UI\\\\" .. (loot and "quest-loot" or "quest-kill"))\n\tif f.tex.SetTexCoord then f.tex:SetTexCoord(0, 1, 0, 1) end\n\tf.tex:SetVertexColor(1, 1, 1, 1)\n\tf.kind = loot and "loot" or "kill"\n', 1))
# ---- 2026-11-19: quest icons on nameplates on by default (the user removed Questie)
_more('Quests/QuestDB.lua', ('\tnameplateIcons = false, -- quest icon on nameplates of objective mobs\n', "\tnameplateIcons = true, -- quest icon on nameplates of objective mobs (Evertally: on, in place of Questie's)\n", 1))
# ---- 2026-11-19: auto spell ranks (the user: the new rank onto the bars by itself, on by default)
_more('QoL/Spells.lua', ('ns.RegisterDefaults("qol", { levelUpSpells = true, oldRanks = true })\n',
       '-- (Evertally: autoRanks, on by default: a new rank goes onto the bars by itself, the card only for what it could not do)\nns.RegisterDefaults("qol", { levelUpSpells = true, oldRanks = true, autoRanks = true })\n', 1),
      ('\tlocal k = key(list)\n\tif k == told and not force then return false end\n\ttold = k\n\tns.Fire("OLD_RANKS", { spells = list, slots = n })\n\treturn true\nend\n',
       '\tlocal k = key(list)\n\tif k == told and not force then return false end\n\ttold = k\n\t-- Evertally: qol.autoRanks (on by default) puts the highest rank into the same buttons at once, once per list in a\n\t-- session (a slot that would not take it is not tried again and again). The card stays for what is left: something\n\t-- on the cursor, a slot that did not change.\n\tif QoL.On("autoRanks") and not autoTried[k] and not (GetCursorInfo and GetCursorInfo()) and Spells.Upgrade then\n\t\tautoTried[k] = true\n\t\tif Spells.Upgrade() ~= nil then return true end\n\tend\n\tns.Fire("OLD_RANKS", { spells = list, slots = n })\n\treturn true\nend\n', 1),
      ('-- Tell the old ranks (OLD_RANKS) when there are any not told yet. -> told\nfunction Spells.CheckRanks(force)',
       '-- Tell the old ranks (OLD_RANKS) when there are any not told yet. -> told\nlocal autoTried = {} -- (Evertally) lists of old ranks already put right by themselves this session\nfunction Spells.CheckRanks(force)', 1))
_more('QoL/Options.lua', ('\t\tsearch = "rank, old rank, downrank, action bar, upgrade spells, highest rank, buttons" },\n',
       '\t\tsearch = "rank, old rank, downrank, action bar, upgrade spells, highest rank, buttons" },\n\t-- Evertally: the new rank onto the bars by itself\n\t{ kind = "toggle", key = "qol.autoRanks", label = L["Put new ranks on your bars"],\n\t\thelp = L["When you learn a higher rank, it replaces the lower one in the same action buttons by itself (out of combat). Macros, items and the ranks you keep are left alone."],\n\t\tdisabled = function() return not QoL.On("oldRanks") end,\n\t\tsearch = "auto rank, spell ranks, new rank, action bar, upgrade, automatic" },\n', 1))
# ---- 2026-11-19: services, inns and flight masters on the map and the minimap by default; inns and flight masters in the tracking menu
_more('Maps/Maps.lua', ('\ttaxiPins = false,       -- flight masters\n',
       '\ttaxiPins = true,        -- flight masters (Evertally: on, with the minimap\'s, as the game\'s own tracking)\n', 1),
      ('\tinnPins = false,        -- inns\n',
       '\tinnPins = true,         -- inns (Evertally: on)\n', 1),
      ('\ttravelMinimap = false,  -- travel icons on the minimap too\n',
       '\ttravelMinimap = true,   -- travel icons on the minimap too (Evertally: on)\n', 1))
_more('Maps/Services.lua', ('\t{ key = "repair", label = L["Repair"], glyph = "repair" },\n',
       '\t{ key = "repair", label = L["Repair"], glyph = "repair", on = true },\n', 1),
      ('\t{ key = "auctioneer", label = L["Auctioneers"], glyph = "auction" },\n',
       '\t{ key = "auctioneer", label = L["Auctioneers"], glyph = "auction", on = true },\n', 1),
      ('\t{ key = "banker", label = L["Bankers"], glyph = "bank" },\n',
       '\t{ key = "banker", label = L["Bankers"], glyph = "bank", on = true },\n', 1),
      ('\t{ key = "trainer", label = L["Profession trainers"], glyph = "trainer-profession" },\n',
       '\t{ key = "trainer", label = L["Profession trainers"], glyph = "trainer-profession", on = true },\n', 1),
      ('ns.RegisterDefaults("maps", { servicePins = false, serviceMinimap = false, serviceFilters = filters })\n',
       '-- (Evertally, 2026-11-19: on by default, on the minimap too, as the game\'s own tracking; the user: "nevidím na\n-- minimapě inkeepery, trenéry")\nns.RegisterDefaults("maps", { servicePins = true, serviceMinimap = true, serviceFilters = filters })\n', 1),
      ('\tcheckbox(menu, L["Service icons on the minimap"], "maps.serviceMinimap")\n\tmenu:CreateDivider()\n',
       '\tcheckbox(menu, L["Service icons on the minimap"], "maps.serviceMinimap")\n\tmenu:CreateDivider()\n\t-- Evertally: the travel layer\'s inns and flight masters here too (looked for in the minimap\'s tracking menu)\n\tcheckbox(menu, L["Inns"], "maps.innPins")\n\tcheckbox(menu, L["Flight masters"], "maps.taxiPins")\n\tcheckbox(menu, L["Travel icons on the minimap"], "maps.travelMinimap")\n\tmenu:CreateDivider()\n', 1))
# ---- 2026-11-19: the game's own tracking icons on the service, inn and flight master pins
_more('Maps/Maps.lua', ('\ttrackerPos = false,\n})\n',
       '\ttrackerPos = false,\n})\n\n-- Evertally (2026-11-19): the game\'s own minimap tracking art on the service, inn and flight master pins (the user:\n-- "original blizzard ikonky: inkeeper, mail, shop, blacksmith"), white, as the game draws them. A file this client\n-- does not have (SetTexture says false) keeps the map mark.\nlocal GAME_ICONS = {\n\tinn = "Interface\\\\Minimap\\\\Tracking\\\\Innkeeper", flightmaster = "Interface\\\\Minimap\\\\Tracking\\\\FlightMaster",\n\tmailbox = "Interface\\\\Minimap\\\\Tracking\\\\Mailbox", repair = "Interface\\\\Minimap\\\\Tracking\\\\Repair",\n\tbanker = "Interface\\\\Minimap\\\\Tracking\\\\Banker", auctioneer = "Interface\\\\Minimap\\\\Tracking\\\\Auctioneer",\n\tclass = "Interface\\\\Minimap\\\\Tracking\\\\Class", trainer = "Interface\\\\Minimap\\\\Tracking\\\\Profession",\n\tstablemaster = "Interface\\\\Minimap\\\\Tracking\\\\StableMaster", battlemaster = "Interface\\\\Minimap\\\\Tracking\\\\BattleMaster",\n\tvendor = "Interface\\\\GossipFrame\\\\VendorGossipIcon",\n}\nMaps.GAME_ICONS = GAME_ICONS\nMaps.GAME_WHITE = { 1, 1, 1, 1 }\nlocal gameProbe, gameKnown = nil, {}\nfunction Maps.GameIcon(kind)\n\tlocal path = GAME_ICONS[kind]\n\tif not path then return nil end\n\tif gameKnown[path] == nil then\n\t\tif not gameProbe and UIParent and UIParent.CreateTexture then gameProbe = UIParent:CreateTexture(nil, "BACKGROUND") end\n\t\tlocal ok, set = false, false\n\t\tif gameProbe then ok, set = pcall(gameProbe.SetTexture, gameProbe, path) end\n\t\tgameKnown[path] = ok and set ~= false\n\tend\n\treturn gameKnown[path] and path or nil\nend\n', 1))
_more('Maps/Services.lua', ('\tcategory.mark = "map:" .. category.glyph\n\tcategory.icon = MAP_MEDIA .. "icon-" .. category.glyph\n',
       '\tcategory.mark = "map:" .. category.glyph\n\tcategory.icon = MAP_MEDIA .. "icon-" .. category.glyph\n\t-- Evertally: the game\'s own tracking icon where it has one (Maps.GameIcon)\n\tlocal game = Maps.GameIcon and Maps.GameIcon(category.key)\n\tif game then category.mark, category.icon, category.game = game, game, true end\n', 1),
      ('function Maps.ServiceIcon(category, size)\n',
       'function Maps.ServiceIcon(category, size)\n\tif category.game then return string.format("|T%s:%d:%d|t", category.icon, size or 16, size or 16) end\n', 1),
      ('\t\t\t\t\t\t\t\tsize = 16, color = color, priority = 1 }\n',
       '\t\t\t\t\t\t\t\tsize = 16, color = selected.game and Maps.GAME_WHITE or color, priority = 1 }\n', 1))
_more('Maps/ServiceClusters.lua', ('\tgroup.icon = group.stack[1]\n',
       '\tgroup.icon = group.stack[1]\n\t-- Evertally: a game icon in its own colours (Maps.GameIcon)\n\tif type(group.icon) == "string" and not group.icon:match("^map:") then group.color = Maps.GAME_WHITE end\n', 1))
_more('Maps/TravelPins.lua', ('\t\t\tlocal p = pinAt(node, "map:flightmaster", 15, isKnown and knownCol or unknownCol,\n',
       '\t\t\t-- (Evertally: the game\'s flight master icon, white; not learned yet keeps its "?")\n\t\t\tlocal game = Maps.GameIcon and Maps.GameIcon("flightmaster")\n\t\t\tlocal p = pinAt(node, game or "map:flightmaster", 15, game and Maps.GAME_WHITE or (isKnown and knownCol or unknownCol),\n', 1),
      ('\t\tlocal p = pinAt(inn, "map:inn", bound and 16 or 12, color(bound and "success" or "npc"), innTooltip(inn, bound), bound and 2 or 0)\n',
       '\t\t-- (Evertally: the game\'s innkeeper icon, white; the bound inn larger and circled)\n\t\tlocal game = Maps.GameIcon and Maps.GameIcon("inn")\n\t\tlocal p = pinAt(inn, game or "map:inn", bound and 16 or (game and 14 or 12), game and Maps.GAME_WHITE or color(bound and "success" or "npc"), innTooltip(inn, bound), bound and 2 or 0)\n', 1))
# ---- 2026-11-19: no spawn-area rings on the minimap (the user: "vypni ty prstence")
_more('Nav/Layers.lua', ('\t}, { world = world, minimap = minimap, edge = true, scale = scale, minimapAreas = true })\n',
       '\t}, { world = world, minimap = minimap, edge = true, scale = scale, minimapAreas = false }) -- (Evertally: no areas on the minimap)\n', 1),
      ('\t\tPins.SetLayer(AREAS, own, { world = world, minimap = minimap, minimapAreas = true })\n',
       '\t\t-- (Evertally, 2026-11-19: the spawn areas\' rings are the world map\'s only; the user: "vypni ty prstence")\n\t\tPins.SetLayer(AREAS, own, { world = world, minimap = minimap, minimapAreas = false })\n', 1),
      ('\t\tPins.SetLayer(HERE_AREAS, areas, { world = world, minimap = minimap, minimapAreas = true })\n',
       '\t\tPins.SetLayer(HERE_AREAS, areas, { world = world, minimap = minimap, minimapAreas = false }) -- (Evertally: world map only)\n', 1))
# ---- 2026-11-18: the guide's chat lines say Evertally, not Polestar (the user: "do chatu furt píše polestar")
_more('Core/Init.lua', ('local PREFIX = "|cff4fd1c5Polestar|r: "',
      'local PREFIX = "|cffd8b66aEvertally:|r " -- (Evertally: its own name and colour in the chat, as Evertally.Print)', 1))
# ---- 2026-11-18: quest names without quote marks in the steps and the quest texts
_more('Core/Init.lua', ('function ns.Quoted(name)\n\tif type(name) ~= "string" or name == "" then return name end\n',
      'function ns.Quoted(name)\n\tif type(name) ~= "string" or name == "" then return name end\n\t-- Evertally: a quest\'s name stands as it is, without quote marks (the user: "proč to píše uvozovky")\n\tif ns.EvertallyPlainNames ~= false then return name end\n', 1))

def folder_name(name: str) -> str:
    return "Evertally_Guide" + name[len("Polestar"):]


def identifiers(text: str, code: bool) -> str:
    text = re.sub(r"AddOns(\\\\|\\|/)Polestar(?=\\|/|\")", r"AddOns\1Evertally_Guide", text)
    text = re.sub(r"\bPolestar_", "Evertally_Guide_", text)
    text = re.sub(r"(?<![A-Za-z0-9])POLESTAR", "EVERTALLYGUIDE", text)   # also SLASH_POLESTAR1, BINDING_NAME_POLESTAR_X
    text = re.sub(r"\bPolestar(?=[A-Za-z0-9])", "EvertallyGuide", text)
    if code:
        text = re.sub(r"\bPolestar\b", "EvertallyGuide", text)
    return text


def string_literal(token: str) -> str:
    quote, body = token[0], token[1:-1]
    if body in KEEP or body == "Polestar":
        return token
    body = LOWER_ID.sub(r"evertally_guide_\1", body)
    body = identifiers(body, code=False)
    for pattern, word in SLASH_WORDS:
        body = pattern.sub(word, body)
    if re.search(r"\bPolestar\b", body) and not INTEROP.search(body):
        body = re.sub(r"\bPolestar\b", "Evertally", body)
    return quote + body + quote


def lua(text: str) -> str:
    out, at = [], 0
    for m in LUA_TOKEN.finditer(text):
        out.append(identifiers(text[at:m.start()], code=True))
        token = m.group(0)
        if m.group(6) or m.group(7):
            out.append(string_literal(token))
        elif m.group(3) and not m.group(1):
            out.append(token)                                   # a comment stays as Polestar wrote it
        elif m.group(4):
            out.append(identifiers(token, code=False))          # long strings hold data, not prose
        else:
            out.append(token)
        at = m.end()
    out.append(identifiers(text[at:], code=True))
    text = "".join(out)
    for old, new in GLOBAL_PATCHES:
        text = text.replace(old, new)
    return text


def toc(text: str) -> str:
    lines = []
    for line in text.replace("\r\n", "\n").split("\n"):  # not splitlines(): in latin-1 a UTF-8 byte 0x85 would split
        # The in-game AddOns list: every folder under the one Evertally header, titled "Evertally - ...", in English
        # (and Czech: Evertally_Guide_csCZ); Polestar's other languages are not shipped.
        if re.match(r"## (Title|Notes)-(?!csCZ)\w+:", line):
            continue
        if re.match(r"## (Group|Category):", line):
            line = line.split(":")[0] + ": Evertally"
        elif re.match(r"## Author:", line):
            line = "## Author: Evertally (from Polestar, The Polestar authors)"
        elif re.match(r"## (Title|Notes|Category)(-\w+)?:", line):
            line = re.sub(r"\bPolestar(?=_)", "Evertally_Guide", line)
            line = re.sub(r"\bPolestar\b", "Evertally Guide", line)
            if line.startswith("## Title: Evertally Guide"):
                rest = line[len("## Title: Evertally Guide"):]
                line = "## Title: Evertally - " + (rest.lstrip() if rest.startswith(" Guides") else "Guide" + rest)
        else:
            line = identifiers(line, code=False)
            line = re.sub(r"(## (?:Dependencies|RequiredDeps|OptionalDeps|LoadWith):.*)", lambda m: re.sub(r"\bPolestar\b", "Evertally_Guide", m.group(1)), line)
        lines.append(line)
    if not any(l.startswith("## Group:") for l in lines):
        lines.insert(1, "## Group: Evertally")
    if not any(l.startswith("## Category:") for l in lines):
        lines.insert(1, "## Category: Evertally")
    lines.append("## X-Evertally: generated from Polestar by tools/import_polestar.py; see NOTICE-EVERTALLY.txt")
    return "\n".join(lines) + "\n"


def lua_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r") + '"'


def czech(today: str, version: str) -> None:
    """Evertally_Guide_csCZ from the translation memory (tools/polestar-cs, keys from tools/polestar_cs_keys.py):
    the interface (L) and the guide texts in Czech, loaded by Evertally when its language is Czech. Only what is
    translated goes in; the rest stays English."""
    src = ROOT / "tools" / "polestar-cs"
    if not (src / "keys.json").is_file():
        return
    keys = json.loads((src / "keys.json").read_text(encoding="utf8"))
    ui = json.loads((src / "interface.json").read_text(encoding="utf8"))
    tx = json.loads((src / "texts.json").read_text(encoding="utf8"))
    dst = DEST / "Evertally_Guide_csCZ"
    dst.mkdir(parents=True, exist_ok=True)
    lines = ["-- Czech (csCZ) for Evertally Guide. Generated by tools/import_polestar.py from tools/polestar-cs/interface.json:",
             "-- edit the translation there. Keys are the English strings as the code writes them; a key missing here shows",
             "-- in English. Fills L only when Evertally asked for Czech (EvertallyGuide.EvertallyLanguage).", "",
             "local ns = EvertallyGuide", 'if not (ns and ns.EvertallyLanguage == "csCZ") then return end', "local L = ns.L", ""]
    n_ui = 0
    for k in keys["interface"]:
        v = ui.get(k) or ""
        if v:
            lines.append(f"L[{lua_string(k)}] = {lua_string(v)}")
            n_ui += 1
    for k, v in EXTRA_CS.items():
        lines.append(f"L[{lua_string(k)}] = {lua_string(v)}")
        n_ui += 1
    (dst / "Interface.lua").write_text("\n".join(lines) + "\n", encoding="utf8", newline="\n")
    out = ["-- Czech guide texts for Evertally Guide. Generated by tools/import_polestar.py from tools/polestar-cs/texts.json.",
           "", "local t = { guides = {} }", "t.pack = {"]
    n_tx = 0
    for k in keys["pack"]:
        if tx.get(k):
            out.append(f"\t[{lua_string(k)}] = {lua_string(tx[k])},")
            n_tx += 1
    out.append("}")
    for gid, ks in keys["guides"].items():
        rows = [f"\t[{lua_string(k)}] = {lua_string(tx[k])}," for k in ks if tx.get(k)]
        if rows:
            out.append(f"t.guides[{lua_string(gid)}] = {{")
            out += rows
            out.append("}")
            n_tx += len(rows)
    out += ["", 'EvertallyGuide.RegisterGuideTexts("csCZ", "guides", t)']
    (dst / "Texts.lua").write_text("\n".join(out) + "\n", encoding="utf8", newline="\n")
    (dst / "Evertally_Guide_csCZ.toc").write_text(
        "## Interface: 16001\n## Title: Evertally - Guide (Czech)\n## Group: Evertally\n## Category: Evertally\n## Notes: Evertally Guide in Czech: the interface and the guide texts.\n"
        "## Title-csCZ: Evertally Guide - čeština\n## Author: Evertally (translation); Polestar (the English)\n"
        f"## Version: {version}\n## LoadOnDemand: 1\n## Dependencies: Evertally_Guide\n## X-License: GPL-3.0-only\n"
        "## X-Evertally: generated by tools/import_polestar.py from tools/polestar-cs; see NOTICE-EVERTALLY.txt\n\nInterface.lua\nTexts.lua\n",
        encoding="utf8", newline="\n")
    shutil.copy2(SOURCE / "Polestar" / "LICENSE", dst / "LICENSE.txt")
    (dst / "NOTICE-EVERTALLY.txt").write_text(
        f"This folder is part of Evertally. It was generated on {today} by Evertally's tools/import_polestar.py. It is a Czech\n"
        f"translation of the interface and guide texts of Polestar {version} (https://github.com/fitzforge/polestar, Copyright (c)\n"
        "2026 The Polestar authors, GPL-3.0-only), made for Evertally from the English strings Polestar's own language folders\n"
        "list. Translated: " + f"{n_ui} interface strings, {n_tx} guide texts" + ". Distributed under the GNU GPL, version 3.\n",
        encoding="utf8", newline="\n")
    print(f"Czech: {n_ui}/{len(keys['interface'])} interface strings, {n_tx} guide texts")


def main() -> None:
    sources = sorted(p for p in SOURCE.glob("Polestar*") if p.is_dir() and not LANGUAGE.match(p.name) and p.name not in SKIP)
    if not sources or not (SOURCE / "Polestar" / "Polestar.toc").is_file():
        raise SystemExit(f"Polestar not found in {SOURCE}")
    version = re.search(r"^## Version: (.+)$", (SOURCE / "Polestar" / "Polestar.toc").read_text(encoding="utf8"), re.M).group(1).strip()
    today = datetime.date.today().isoformat()
    for old in DEST.glob("Evertally_Guide*"):
        if (old / "NOTICE-EVERTALLY.txt").is_file():          # only folders this script made
            shutil.rmtree(old)
    report = {"polestar": version, "date": today, "folders": {}}
    for src in sources:
        dst = DEST / folder_name(src.name)
        files = 0
        for path in sorted(src.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(src)
            name = rel.name
            if name.startswith("Polestar") and path.suffix.lower() in {".toc", ".lua", ".xml"}:
                name = folder_name(name)
            if path.suffix.lower() not in INSTALLED:
                name += ".txt"      # LICENSE, PACK.json: Evertally's updater installs known file types only (the text is unchanged)
            out = dst / rel.parent / name
            out.parent.mkdir(parents=True, exist_ok=True)
            suffix = path.suffix.lower()
            if suffix in {".lua", ".xml", ".toc"}:
                text = path.read_text(encoding="latin-1")  # byte for byte: packed data holds raw bytes, every rename is ASCII
                text = lua(text) if suffix == ".lua" else toc(text) if suffix == ".toc" else identifiers(text, code=True)
                for old, new, count in PATCHES.get(str(rel.parent / name).replace("\\", "/"), []):
                    assert text.count(old) == count, (src.name, rel, old)
                    text = text.replace(old, new)
                out.write_bytes(text.encode("latin-1"))
            else:
                shutil.copy2(path, out)
            files += 1
        (dst / "NOTICE-EVERTALLY.txt").write_text(
            f"This folder is part of Evertally. It was generated on {today} from {src.name} of Polestar {version}\n"
            "(https://github.com/fitzforge/polestar, Copyright (c) 2026 The Polestar authors, GPL-3.0-only) by\n"
            "Evertally's tools/import_polestar.py, which changed it as follows:\n"
            "  - the folder and file names: Polestar -> Evertally_Guide;\n"
            "  - globals, frames, saved variables and key bindings: Polestar -> EvertallyGuide, POLESTAR -> EVERTALLYGUIDE;\n"
            "  - the add-on's name shown to players: Polestar -> Evertally (the guides' author is still Polestar);\n"
            "  - slash commands /polestar, /pole, /ps -> /etguide, /etg, /evertallyguide, and the ids other add-ons know\n"
            "    us by (polestar_* bag widgets, waypoint owners) -> evertally_guide_* / EvertallyGuide;\n"
            "  - the patches listed in tools/import_polestar.py and the files of tools/evertally-guide-overlay\n"
            "    (Evertally's own window layout, settings window and brand art).\n"
            "Everything else is Polestar's work, under its licence (LICENSE.txt) and notices (THIRD_PARTY.md, CREDITS.md,\n"
            "LICENSE-DATA.txt where present). This modified version is distributed under the GNU GPL, version 3.\n",
            encoding="utf8", newline="\n")
        report["folders"][dst.name] = files
    # Evertally's own design (tools/evertally-guide-overlay): whole files that replace Polestar's after the import, so
    # the window's layout, the settings shell and the brand art are Evertally's and survive every new Polestar.
    for path in sorted(OVERLAY.rglob("*")):
        if path.is_file():
            out = DEST / path.relative_to(OVERLAY)
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, out)
    czech(today, version)
    (ROOT / "tools" / "polestar-import.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf8")
    print(f"Polestar {version}: {len(sources)} folders, {sum(report['folders'].values())} files -> {DEST}\\Evertally_Guide*")


if __name__ == "__main__":
    main()
