"""The guide's enemy nameplates use Evertally's transparent loot bag for a
loot objective, a sword for a kill objective, and no glyph for a completed objective."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime

ROOT = Path(__file__).resolve().parents[2]
TOOLTIPS = ROOT / "addon" / "Evertally_Guide" / "Quests" / "Tooltips.lua"

STUB = r'''
  HANDLERS, ONS = {}, {}
  local make = CreateFrame
  CreateFrame = function(...)
    local f = make(...)
    for k, v in pairs({GetFrameStrata = function() return "MEDIUM" end, GetFrameLevel = function() return 1 end,
        SetFrameStrata = function() end, SetFrameLevel = function() end}) do rawset(f, k, v) end
    return f
  end
  -- npc 1: drops a quest item (kind 2); npc 2: to kill (kind 1); npc 3: its objective done
  OBJ = {
    [1] = {{kind = 2, done = false, entry = {}, q = 10, id = 1, max = 8, cur = 3}},
    [2] = {{kind = 1, done = false, entry = {}, q = 11, id = 2, max = 1, cur = 0}},
    [3] = {{kind = 1, done = true, entry = {}, q = 12, id = 3, max = 5, cur = 5}},
  }
  GNS = {
    L = setmetatable({}, {__index = function(_, k) return k end}),
    QuestDB = {IsRunning = function() return true end, ObjectivesForNpc = function(id) return OBJ[id] end,
      ProgressText = function(o) return o.cur .. "/" .. o.max end, Color = function() return {r = 1, g = 1, b = 1, a = 1} end},
    Get = function(path) if path == "qol.nameplateIconSide" then return "left" end return true end,
    Hidden = function() return false end,
    On = function(ev, fn) ONS[ev] = ONS[ev] or {}; table.insert(ONS[ev], fn) end,
    RegisterEvent = function(ev, fn) HANDLERS[ev] = fn; return true end,
    UnregisterEvent = function() end,
    After = function() end,
    Hooks = setmetatable({}, {__index = function() return function() end end}),
    Compat = {GetNpcID = function(unit) return NPC[unit] end},
    Theme = {Media = function(name) return "MEDIA:" .. name end},
  }
  NPC = {nameplate1 = 1, nameplate2 = 2, nameplate3 = 3}
  PLATES = {}
  C_NamePlate = {GetNamePlateForUnit = function(unit)
    PLATES[unit] = PLATES[unit] or CreateFrame("Frame")
    return PLATES[unit]
  end}
'''


class GuidePlateIconTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(STUB)
        chunk = self.lua.eval("loadstring or load")(TOOLTIPS.read_text(encoding="utf8"))
        self.assertIsNotNone(chunk)
        self.lua.globals().TT_CHUNK = chunk
        self.lua.execute('TT_CHUNK("Evertally_Guide", GNS); Q = GNS.QuestDB')
        # the module turns its plates on with the quest database
        self.lua.execute('for _, fn in ipairs(ONS.QUESTDB_STARTED or {}) do fn() end')

    def add(self, unit):
        h = self.lua.globals().HANDLERS["NAME_PLATE_UNIT_ADDED"]
        self.assertIsNotNone(h, "the plates listen")
        h(None, unit)
        return self.lua.eval('Q.NameplateIcon("%s")' % unit)

    def test_loot_bag_where_an_item_drops_sword_where_only_to_kill(self):
        loot = self.add("nameplate1")
        self.assertEqual(loot.kind, "loot")
        self.assertEqual(self.lua.eval('Q.NameplateIcon("nameplate1").tex.texture'), "Interface\\AddOns\\Evertally_Guide\\Media\\UI\\quest-loot")
        kill = self.add("nameplate2")
        self.assertEqual(kill.kind, "kill")
        self.assertEqual(self.lua.eval('Q.NameplateIcon("nameplate2").tex.texture'), "Interface\\AddOns\\Evertally_Guide\\Media\\UI\\quest-kill")
        self.assertIsNone(self.add("nameplate3"), "nothing open: no icon")


if __name__ == "__main__":
    unittest.main()
