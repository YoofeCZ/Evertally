"""Evertally's bag window (BagWindow.lua): which section an item goes to, the search and its #tags, what counts as new,
the game's bag keys opening it instead of the game's bags (post-hooks, no Blizzard global written), and the snapshot of
the bags other characters see."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime

FAKE = r"""
  local make = CreateFrame
  CreateFrame = function(kind, name, parent, template)
    local t = make(kind, name, parent)
    rawset(t, "SetID", function(self, v) self.id = v end)
    rawset(t, "GetID", function(self) return self.id end)
    rawset(t, "template", template)
    return t
  end
  -- {bag, slot, id, name, quality, classID, equipLoc, count}
  ITEMS = {
    {0, 1, 159, "Refreshing Spring Water", 1, 0, "", 10},
    {0, 2, 2589, "Linen Cloth", 1, 7, "", 13},
    {0, 3, 5374, "Small Pocket Watch", 0, 15, "", 1},
    {0, 4, 5085, "Bristleback Quilboar Tusk", 1, 12, "", 6},
    {0, 5, 6070, "Wolfskin Bracers", 2, 4, "INVTYPE_WRIST", 1},
    {1, 1, 2140, "Carving Knife", 1, 2, "INVTYPE_WEAPON", 1},
    {1, 2, 6948, "Hearthstone", 1, 15, "", 1},
  }
  local function index() BY = {}; for _, it in ipairs(ITEMS) do BY[it[1] .. ":" .. it[2]] = it; BY[it[3]] = it end end
  index(); REINDEX = index
  SIZES = {[0] = 8, [1] = 4}
  C_Container = {
    GetContainerNumSlots = function(bag) return SIZES[bag] or 0 end,
    GetContainerNumFreeSlots = function(bag) local n = 0; for s = 1, SIZES[bag] or 0 do if not BY[bag .. ":" .. s] then n = n + 1 end end; return n, 0 end,
    GetContainerItemInfo = function(bag, slot) local it = BY[bag .. ":" .. slot]; if not it then return nil end
      return {iconFileID = 1, stackCount = it[8], quality = it[5], itemID = it[3], hyperlink = "|Hitem:" .. it[3] .. "|h[" .. it[4] .. "]|h"} end,
  }
  GetItemInfoInstant = function(link) local id = tonumber(tostring(link):match("item:(%d+)")); local it = id and BY[id]; if not it then return nil end
    return id, "", "", it[7], 1, it[6], 0 end
  GetItemInfo = function(link) local id = tonumber(tostring(link):match("item:(%d+)")); local it = id and BY[id]; if it then return it[4], link, it[5] end end
  GetMoney = function() return 12345 end
  -- the player marked the knife as junk in the guide
  EvertallyGuide = {QoL = {Marks = {Junk = function(id) return id == 2140 end, Protected = function() return false end}}}
  -- the game's bag keys: each opens the backpack's container frame
  ContainerFrame1 = CreateFrame("Frame"); ContainerFrame1:SetID(0); ContainerFrame1:Hide()
  NUM_CONTAINER_FRAMES = 1
  ToggleAllBags = function() ContainerFrame1:Show() end
  CloseAllBags = function() ContainerFrame1:Hide() end
  hooksecurefunc = function(name, fn) local orig = _G[name]; _G[name] = function(...) orig(...); fn(...) end end
"""


class BagWindowTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE)
        self.bw = self.a.BagWindow

    def items(self):
        lst = self.bw.LiveItems(self.lua.eval("{0, 1}"))
        return {str(it.name): it for it in lst.values()}

    def test_each_item_goes_to_its_section(self):
        it = self.items()
        self.assertEqual(it["Refreshing Spring Water"].section, "consumable")
        self.assertEqual(it["Linen Cloth"].section, "profession")
        self.assertEqual(it["Small Pocket Watch"].section, "junk")          # grey
        self.assertEqual(it["Bristleback Quilboar Tusk"].section, "quest")  # a quest item
        self.assertEqual(it["Wolfskin Bracers"].section, "gear")
        self.assertEqual(it["Carving Knife"].section, "sell")               # marked junk in the guide, not grey
        self.assertEqual(it["Hearthstone"].section, "other")

    def test_search_by_name_and_by_tag(self):
        it = self.items()
        m = self.bw.Matches
        self.assertTrue(m(it["Linen Cloth"], "linen"))
        self.assertFalse(m(it["Linen Cloth"], "silk"))
        self.assertTrue(m(it["Small Pocket Watch"], "#sell"))   # #sell: to sell and junk
        self.assertTrue(m(it["Carving Knife"], "#sell"))
        self.assertFalse(m(it["Carving Knife"], "#junk"))
        self.assertTrue(m(it["Wolfskin Bracers"], "#gear bracers"))
        self.assertFalse(m(it["Wolfskin Bracers"], "#gear knife"))
        self.assertTrue(m(it["Hearthstone"], ""))

    def test_more_of_an_item_than_when_last_closed_is_new(self):
        self.bw.MarkSeen()
        self.assertFalse(any(i.new for i in self.items().values()))
        self.lua.execute('ITEMS[#ITEMS + 1] = {1, 3, 4306, "Silk Cloth", 1, 7, "", 5}; REINDEX()')
        it = self.items()
        self.assertTrue(it["Silk Cloth"].new)
        self.assertEqual(it["Silk Cloth"].section, "new")
        self.assertFalse(it["Linen Cloth"].new)

    def test_every_view_draws_live_slots_as_the_clients_item_buttons(self):
        for view in ("sections", "packed", "exact", "list"):
            self.a.db.settings.bagWindow = self.lua.eval('{view = "%s"}' % view)
            self.bw.Show("bags")
            self.assertTrue(self.bw.Shown(), view)
        # the button for bag 1, slot 2 sits under a frame carrying bag 1's ID: the client's clicks read it there
        b = self.lua.globals().EvertallyBagItem1
        self.assertEqual(b.template, "ContainerFrameItemButtonTemplate")
        self.assertIsNotNone(b.GetParent(b).GetID(b.GetParent(b)))

    def test_bag_key_opens_this_window_and_hides_the_games_bags(self):
        g = self.lua.globals()
        self.bw.Hook()
        self.assertTrue(self.bw.Replaces())   # no other bag add-on loaded
        g.ToggleAllBags()
        self.assertTrue(self.bw.Shown())
        self.assertFalse(g.ContainerFrame1.IsShown(g.ContainerFrame1))
        g.CLOCK = g.CLOCK + 1
        g.ToggleAllBags()
        self.assertFalse(self.bw.Shown())
        self.assertFalse(g.ContainerFrame1.IsShown(g.ContainerFrame1))
        # turned off: the game's bags open as before
        self.bw.SetReplace(False)
        g.CLOCK = g.CLOCK + 1
        g.ToggleAllBags()
        self.assertFalse(self.bw.Shown())
        self.assertTrue(g.ContainerFrame1.IsShown(g.ContainerFrame1))

    def test_the_hook_writes_no_blizzard_global_but_the_ones_it_hooks(self):
        src = (Path(__file__).resolve().parents[2] / "addon" / "Evertally" / "BagWindow.lua").read_text(encoding="utf8")
        import re
        self.assertIsNone(re.search(r"^\s*(ToggleAllBags|ToggleBackpack|OpenAllBags|CloseAllBags|SortBags)\s*=", src, re.M))

    def test_equip_best_puts_on_what_the_guide_would_wear_one_piece_at_a_time(self):
        self.lua.execute(r"""
          EQUIPPED = {}
          -- the guide's rule: the bracers are a 12 % upgrade for the wrist (9); the knife is marked junk (never worn)
          EvertallyGuide.Gear = {}
          EvertallyGuide.QoL.Equip = {Placement = function(G, link)
            if link:find("item:6070") and not EQUIPPED[6070] then return 9, 12 end
            if link:find("item:2140") then return 16, 50 end
          end}
          C_Item = {EquipItemByName = function(link, slot) EQUIPPED[tonumber(link:match("item:(%d+)"))] = slot end}
          PRINTED = {}
          Evertally.Print = function(m) PRINTED[#PRINTED + 1] = m end
        """)
        plan = self.bw.EquipPlan()
        self.assertEqual([str(p.name) for p in plan.values()], ["Wolfskin Bracers"])
        self.assertTrue(self.bw.EquipBest())
        g = self.lua.globals()
        self.assertEqual(g.EQUIPPED[6070], 9)
        self.assertIsNone(g.EQUIPPED[2140])
        self.assertIn("Wolfskin Bracers", str(g.PRINTED[1]))

    def test_equip_best_waits_for_the_fight_to_end(self):
        self.lua.execute('INCOMBAT = true; EQUIPPED = {}; C_Item = {EquipItemByName = function(l) EQUIPPED[l] = true end}')
        self.assertFalse(self.bw.EquipBest())
        self.assertTrue(self.bw.equipAfterFight)

    def test_the_setup_choice_turns_the_other_bag_addon_off_or_on(self):
        self.lua.execute(r"""
          ENABLED = {Baganator = true}
          C_AddOns = {
            GetAddOnInfo = function(n) if n == "Baganator" then return n, "Baganator", "", true, nil end; return nil, nil, nil, false, "MISSING" end,
            IsAddOnLoaded = function(n) return n == "Baganator" and LOADED end,
            GetAddOnEnableState = function(n) return ENABLED[n] and 2 or 0 end,
            DisableAddOn = function(n) ENABLED[n] = false end, EnableAddOn = function(n) ENABLED[n] = true end}
          LOADED = true
          PRINTED = {}; Evertally.Print = function(m) PRINTED[#PRINTED + 1] = m end
        """)
        g = self.lua.globals()
        values = [str(c.value) for c in self.bw.Choices().values()]
        self.assertEqual(values, ["evertally", "game", "Baganator"])
        self.assertIsNone(self.bw.Choice())
        self.assertTrue(self.bw.SetChoice("evertally"))
        self.assertTrue(self.bw.Replaces())
        self.assertFalse(g.ENABLED.Baganator)
        self.assertIn("/reload", str(g.PRINTED[1]))
        self.assertTrue(self.bw.SetChoice("Baganator"))
        self.assertFalse(self.bw.Replaces())
        self.assertTrue(g.ENABLED.Baganator)
        self.assertFalse(self.bw.SetChoice("Bagnon"))   # not on disk

    def test_the_banker_opens_the_bank_window_and_the_game_bank_steps_aside(self):
        self.lua.execute(r"""
          BankFrame = CreateFrame("Frame"); BankFrame:Show()
          rawset(BankFrame, "SetAlpha", function(self, a) self.alpha = a end)
          rawset(BankFrame, "SetScale", function(self, v) self.scale = v end)
          rawset(BankFrame, "GetScale", function(self) return self.scale or 1 end)
          CLOSED = 0; CloseBankFrame = function() CLOSED = CLOSED + 1 end
          SIZES[-1] = 4
          ITEMS[#ITEMS + 1] = {-1, 1, 2592, "Wool Cloth", 1, 7, "", 20}; REINDEX()
        """)
        g = self.lua.globals()
        self.lua.eval("Evertally.Dispatch")("BANKFRAME_OPENED")
        self.assertTrue(self.bw.bank.Shown())
        self.assertTrue(self.bw.Shown())                  # the bags come along
        self.assertEqual(g.BankFrame.alpha, 0)            # the game's bank stays open, out of sight
        self.assertEqual(len(self.a.db.bagCache["Fixture Hero-Fixture Realm"].bank), 1)
        f = self.bw.bank.frame
        self.bw.bank.Hide(); f.scripts.OnHide(f)          # closing ours leaves the banker (the mock fires no OnHide)
        self.assertEqual(g.CLOSED, 1)
        self.lua.eval("Evertally.Dispatch")("BANKFRAME_CLOSED")
        self.assertEqual(g.BankFrame.alpha, 1)
        self.assertEqual(g.CLOSED, 1)                     # the banker closing itself is not closed again

    def test_text_is_coloured_as_text(self):
        # the game's font strings have no SetTexture: the window colours them with SetTextColor (23:40 error in the game)
        src = (Path(__file__).resolve().parents[2] / "addon" / "Evertally" / "BagWindow.lua").read_text(encoding="utf8")
        self.assertIn('if t.SetTextColor and not t.SetTexture then t:SetTextColor', src)

    def test_snapshot_keeps_the_bags_for_the_alts_view(self):
        self.bw.Snapshot(False)
        cache = self.a.db.bagCache
        entry = cache["Fixture Hero-Fixture Realm"]
        self.assertEqual(entry.money, 12345)
        self.assertEqual(len(entry.bags), 7)
        self.assertEqual(entry.total, 12)
        self.assertEqual(entry.used, 7)


if __name__ == "__main__":
    unittest.main()
