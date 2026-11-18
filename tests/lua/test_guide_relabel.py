"""The guide's labels its files read before Czech was chosen are translated again once the Czech strings are in
(EvertallySettings.lua A.RelabelGuide): the hub's tabs, its sections and their search placeholders, the Database's kinds."""
import unittest
from test_addon import runtime


class RelabelTests(unittest.TestCase):
    def test_labels_read_before_czech_are_translated_again_and_unknown_ones_stay(self):
        lua, a = runtime()
        lua.execute('SECTIONS = {{key = "Rares", label = "Rares", searchPlaceholder = {"Search rares", "Search"}}}')
        g = lua.eval('''{
            L = {Home = "Domů", Guides = "Návody", Rares = "Vzácní mobové", ["Search rares"] = "Hledat vzácné moby", Seen = "Viděno"},
            UI = {Picker = {VIEW_LABEL = {home = "Home", browse = "Browse"}, GUIDES = {label = "Guides"},
                            Sections = function() return SECTIONS end},
                  RaresSection = {TABS = {{key = "seen", label = "Seen"}}}},
        }''')
        n = a.RelabelGuide(g)
        P = g.UI.Picker
        self.assertEqual(P.VIEW_LABEL.home, "Domů")
        self.assertEqual(P.VIEW_LABEL.browse, "Browse", "no Czech for it: stays")
        self.assertEqual(P.GUIDES.label, "Návody")
        self.assertEqual(g.UI.RaresSection.TABS[1].label, "Viděno")
        section = P.Sections()[1]
        self.assertEqual(section.label, "Vzácní mobové")
        self.assertEqual(list(section.searchPlaceholder.values()), ["Hledat vzácné moby", "Search"])
        self.assertEqual(n, 5)
        self.assertEqual(a.RelabelGuide(g), 0, "a second pass finds nothing left in English")


if __name__ == "__main__":
    unittest.main()
