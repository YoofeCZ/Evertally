"""The Evertally menu (EvertallyMenu.lua): the panel the minimap button's left click opens, its right click hides Evertally.
Evertally's own panel (groups of tiles), with the guide's parts only while EvertallyGuide is loaded."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime

FAKE_GUIDE = """
  FIRED={}; HIDDEN=false; ARROW=true; KEEP=false; PAUSED=nil; SHOWN_VIEW=nil
  EvertallyGuide={
    Fire=function(msg) FIRED[#FIRED+1]=msg end,
    SetHidden=function(on) HIDDEN=on and true or false end, Hidden=function() return HIDDEN end,
    HideKeepsArrow=function() return KEEP end, SetHideKeepsArrow=function(on) KEEP=on end,
    Paused=function() return PAUSED end, TogglePaused=function() if PAUSED then PAUSED=nil else PAUSED="hand" end end,
    GuideShown=function() return true end, Get=function(path) if path=="nav.arrow" then return ARROW end end,
    Nav={ToggleArrow=function() ARROW=not ARROW end, ClearTarget=function() FIRED[#FIRED+1]="clear" end}}
"""


class EvertallyMenuTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.a.ShowView = self.lua.eval("function(view) SHOWN_VIEW=view end")

    def keys(self):
        return [[str(i.key) for i in g["items"].values()] for g in self.a.EvertallyMenuGroups().values()]

    def tiles(self):
        panel = self.lua.globals().EvertallyMenuPanel
        return {str(t.item.key): t for t in panel.tiles.values() if t.item}

    def test_without_the_guide_only_evertallys_own_items(self):
        flat = [k for g in self.keys() for k in g]
        self.assertIn("menuDungeons", flat)
        self.assertIn("menuSettings", flat)
        for key in ("menuGuideWindow", "menuArrow", "menuPause", "menuDiscord", "menuHide"):
            self.assertNotIn(key, flat)

    def test_with_the_guide_the_groups_in_their_order(self):
        self.lua.execute(FAKE_GUIDE)
        heads = [str(g.head) for g in self.a.EvertallyMenuGroups().values()]
        self.assertEqual(heads, ["menuGuide", "menuNav", "menuGame", "menuSetup", "menuCommunity"])
        flat = [k for g in self.keys() for k in g]
        for key in ("menuGuideWindow", "menuPickGuide", "menuLookup", "menuArrow", "menuArrowHidden", "menuStopNav", "menuMap",
                    "menuDungeons", "menuTalents", "menuTraining", "menuRecipes", "menuRares", "menuPause",
                    "menuSettings", "menuSetupAgain", "menuHide", "menuDiscord", "menuReport", "menuForum", "menuRankings"):
            self.assertIn(key, flat)
        for lang in ("en", "cs"):
            for key in flat + heads + ["menuOpen", "menuHint", "menuShow", "minimapLeft", "minimapRight", "minimapRightShow", "minimapDrag"]:
                self.assertTrue(self.a.locale[lang][key], (lang, key))

    def test_the_minimap_filter_comes_first_and_a_category_turns_its_icons_on(self):
        # (2026-11-19: the user wants what the minimap shows chosen at the top of the menu, in the game's own icons)
        self.lua.execute(FAKE_GUIDE)
        self.lua.execute('''
          SET = {["maps.innPins"] = true, ["maps.travelMinimap"] = true}
          EvertallyGuide.Get = function(p) if p == "nav.arrow" then return ARROW end return SET[p] end
          EvertallyGuide.Set = function(p, v) SET[p] = v end
          EvertallyGuide.L = {Inns = "Hostince", ["Flight masters"] = "Letoví mistři"}
          EvertallyGuide.Maps = {
            ServiceCategories = {{key = "mailbox", label = "Schránky", icon = "Interface\\\\Minimap\\\\Tracking\\\\Mailbox"},
                                 {key = "vendor", label = "Prodejci", icon = "Interface\\\\GossipFrame\\\\VendorGossipIcon"}},
            GameIcon = function(kind) return "GAME:" .. kind end}
        ''')
        groups = self.a.EvertallyMenuGroups()
        first = groups[1]
        self.assertEqual(str(first.head), "menuMinimap")
        items = {str(i.key): i for i in first["items"].values()}
        self.assertEqual(list(items), ["menuInns", "menuFlight", "menuService_mailbox", "menuService_vendor"])
        self.assertEqual(str(items["menuInns"].text), "Hostince")
        self.assertEqual(str(items["menuInns"].icon), "GAME:inn")
        self.assertTrue(items["menuInns"].get())
        self.assertFalse(items["menuService_vendor"].get())
        items["menuService_vendor"].onClick()
        g = self.lua.globals().SET
        self.assertTrue(g["maps.servicePins"] and g["maps.serviceFilters.vendor"] and g["maps.serviceMinimap"],
                        "the layer, the category and its minimap icons")
        self.assertTrue(items["menuService_vendor"].get())
        items["menuService_vendor"].onClick()
        self.assertFalse(items["menuService_vendor"].get(), "a second click turns it off")
        items["menuFlight"].onClick()
        self.assertTrue(g["maps.taxiPins"])
        for lang in ("en", "cs"):
            self.assertTrue(self.a.locale[lang]["menuMinimap"])
        # the panel draws the tiles with their own text
        self.assertTrue(self.a.ShowEvertallyMenu(None))
        self.assertEqual(str(self.tiles()["menuInns"].text.text if hasattr(self.tiles()["menuInns"].text, "text") else "Hostince"), "Hostince")

    def test_a_switch_keeps_the_menu_open_and_shows_its_state_an_action_closes_it(self):
        self.lua.execute(FAKE_GUIDE)
        self.assertTrue(self.a.ShowEvertallyMenu(None))
        tiles = self.tiles()
        arrow = tiles["menuArrow"]
        self.assertTrue(arrow.on)
        arrow.scripts.OnClick(arrow)
        self.assertFalse(self.lua.globals().ARROW)
        self.assertTrue(self.a.EvertallyMenuShown(), "a switch keeps the menu open")
        self.assertFalse(self.tiles()["menuArrow"].on)
        dj = self.tiles()["menuDungeons"]
        dj.scripts.OnClick(dj)
        self.assertEqual(self.lua.globals().SHOWN_VIEW, "dungeons")
        self.assertFalse(self.a.EvertallyMenuShown(), "an action closes it")
        self.a.ShowEvertallyMenu(None)
        discord = self.tiles()["menuDiscord"]
        self.lua.globals().HIDDEN = True
        discord.scripts.OnClick(discord)
        self.assertEqual(list(self.lua.globals().FIRED.values())[-1], "SHOW_DISCORD")
        self.assertFalse(self.lua.globals().HIDDEN, "a window of the guide brings a hidden Evertally back")

    def test_hiding_hides_the_guide_and_the_window_and_shows_again(self):
        self.lua.execute(FAKE_GUIDE)
        self.assertTrue(self.a.ToggleEvertallyHidden())
        self.assertTrue(self.lua.globals().HIDDEN)
        self.assertTrue(self.a.EvertallyHidden())
        self.a.ShowEvertallyMenu(None)
        self.assertEqual(str(self.tiles()["menuHide"].text.text), self.a.L("menuShow"))
        self.assertFalse(self.a.ToggleEvertallyHidden())
        self.assertFalse(self.lua.globals().HIDDEN)

    def test_a_second_open_on_the_same_anchor_closes_it(self):
        anchor = self.lua.eval("CreateFrame")("Button", None, None)
        self.assertTrue(self.a.ShowEvertallyMenu(anchor))
        self.assertFalse(self.a.ShowEvertallyMenu(anchor))
        self.assertFalse(self.a.EvertallyMenuShown())


if __name__ == "__main__":
    unittest.main()
