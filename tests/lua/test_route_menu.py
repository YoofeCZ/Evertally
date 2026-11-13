"""Route-specific actions; map hit testing is covered by renderer tests."""
import unittest
import test_arrow_menu as arrow_tests


class RouteMenuTests(unittest.TestCase):
    setUp = arrow_tests.ArrowTests.setUp
    go = arrow_tests.ArrowTests.go

    def menu(self):
        return self.lua.globals().EvertallyRouteMenu

    def choose(self, index):
        button = self.menu()["items"][index]
        button.scripts.OnClick(button)

    def test_opens_route_actions_without_ending_navigation(self):
        self.go()
        self.assertTrue(self.m.ShowRouteMenu())
        self.assertIsNotNone(self.m.nav.target)
        self.assertEqual(self.menu().title.text, "Goal")
        self.assertEqual(self.menu()["items"][2].text.text, self.a.L("routeMenuRecalculate"))
        self.choose(1)
        self.assertIsNone(self.m.nav.target)
        self.assertIsNone(self.m.route)
        self.assertFalse(self.menu().IsShown(self.menu()))

    def test_recalculate_keeps_destination_and_requests_new_path(self):
        self.go()
        self.lua.execute('RECALCULATED=0; Evertally.map.RecalculateRoute=function() RECALCULATED=RECALCULATED+1;return true end')
        self.m.ShowRouteMenu()
        self.choose(2)
        self.assertEqual(self.lua.globals().RECALCULATED, 1)
        self.assertEqual(self.m.nav.target.label, "Goal")

    def test_change_route_opens_internal_planner(self):
        self.go()
        self.m.OpenWorldTab = self.lua.eval('function(tab) OPEN_TAB=tab end')
        self.m.ShowRouteMenu()
        self.choose(3)
        self.assertEqual(self.lua.globals().OPEN_TAB, "plan")
        self.assertIsNotNone(self.m.nav.target)

    def test_hidden_arrow_can_be_restored_from_route_menu(self):
        self.go()
        self.m.SetArrowShown(False)
        self.m.ShowRouteMenu()
        self.assertEqual(self.menu()["items"][5].text.text, self.a.L("routeMenuShowArrow"))
        self.choose(5)
        self.assertTrue(self.m.ArrowShown())

    def test_preview_starts_navigation_to_its_goal_and_stop_clears_preview(self):
        self.a.db.settings.mapPins = True
        self.a.LoadMap = self.lua.eval('function() return true end')
        self.m.route = self.lua.table(steps=self.lua.table_from([
            self.lua.table(fu=.62, fv=.42, tu=.64, tv=.44, to="Preview goal", mode="walk")
        ]))
        self.m.RoutePlace = self.lua.eval('function() return 1429,.6,.3 end')
        self.assertTrue(self.m.ShowRouteMenu())
        self.assertEqual(self.menu()["items"][2].text.text, self.a.L("routeMenuStart"))
        self.choose(2)
        self.assertEqual(self.m.nav.target.label, "Preview goal")
        self.assertEqual(self.m.nav.target.map, 1429)
        self.m.ShowRouteMenu()
        self.choose(1)
        self.assertIsNone(self.m.route)

    def test_empty_map_has_no_navigation_menu_and_arrow_menu_closes_route_menu(self):
        self.assertFalse(self.m.ShowRouteMenu())
        self.go()
        self.m.ShowRouteMenu()
        self.m.ArrowMenuOpen()
        self.assertFalse(self.menu().IsShown(self.menu()))


if __name__ == "__main__":
    unittest.main()
