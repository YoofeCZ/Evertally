"""Evertally's window as Evertally Guide's hub (GuideShell.lua): with the guide's hub API Evertally is one section of
the hub and its pages are the section's sidebar, in the menu's groups; without it UI.lua's own window stays. The guide
itself is faked here (its hub needs the game's frames): what is checked is what Evertally hands it and how it answers."""
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime

ROOT = Path(__file__).resolve().parents[2]
FAKE_GUIDE = r'''
SECTIONS, SHOWN_SECTION, TITLES = {}, nil, {}
local hubFrame = CreateFrame("Frame", nil, nil); hubFrame:Hide()
local P = {frame = hubFrame}
function P.ShowSection(key) SHOWN_SECTION = key end
function P.Section() return SHOWN_SECTION end
function P.Render()
  for _, s in ipairs(SECTIONS) do
    if s.key == SHOWN_SECTION then
      if not s.psFrame then s.psFrame = CreateFrame("Frame", nil, hubFrame); s.psFrame:SetSize(900, 520); s.build(s.psFrame, hubFrame) end
      s.render()
    end
  end
end
EvertallyGuide = {
  UI = {
    Picker = P,
    RegisterSection = function(spec) SECTIONS[#SECTIONS + 1] = spec; return true end,
    ShowPicker = function() hubFrame:Show(); P.Render() end,
  },
  Widgets = {ShellTitle = function(win, title, sub) TITLES[#TITLES + 1] = title end},
}
'''


class GuideShellTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)

    def install(self):
        self.lua.execute(FAKE_GUIDE)
        self.assertTrue(self.a.InstallGuideShell())
        sections = self.lua.globals().SECTIONS
        self.assertEqual(len(sections), 1)
        return sections[1]

    def views(self, section):
        items, active = section.nav()
        return [items[i].key for i in range(1, len(items) + 1) if not items[i].separator], items, active

    def test_without_the_guide_the_own_window_stays(self):
        self.assertFalse(self.a.InstallGuideShell())
        self.assertIsNone(self.a.guideShell)

    def test_evertally_is_one_section_with_every_page_in_its_groups(self):
        section = self.install()
        self.assertEqual(section.key, "Evertally")
        self.assertEqual(section.order, 1, "first on the rail")
        views, items, active = self.views(section)
        self.assertEqual(views[:6], ["overview", "journal", "history", "places", "facts", "professions"])
        for view in ("database", "gear", "questguide"):
            self.assertNotIn(view, views, "the guide's Lookup, gear advice and guides stand for it in the hub")
        self.assertIn("dungeons", views)
        self.assertEqual(views[-1], "settings")
        self.assertNotIn("leveling", views, "the guide's own sections replace the Leveling page")
        self.assertEqual(sum(1 for i in range(1, len(items) + 1) if items[i].separator), 3, "a rule between the four groups")
        self.assertEqual(active, "overview")
        for i in range(1, len(items) + 1):
            if not items[i].separator:
                self.assertTrue(items[i].label and items[i].icon)

    def test_pages_left_out_of_the_menu_still_open_and_entries_go_to_the_guides_lookup(self):
        section = self.install()
        self.a.ShowView("database")
        self.assertTrue(self.a.guideShell.Shown("database"), "a link that names the page still opens it")
        self.lua.execute("FIRED={}; EvertallyGuide.Fire=function(...) FIRED[#FIRED+1]={...} end")
        self.assertTrue(self.a.OpenDatabaseEntry("quest", 783))
        fired = self.lua.globals().FIRED[1]
        self.assertEqual((fired[1], fired[2], fired[3], fired[4]), ("SHOW_LOOKUP", None, "quest", 783))

    def test_every_page_builds_in_the_hub_and_opening_a_view_shows_it(self):
        section = self.install()
        views, _, _ = self.views(section)
        for view in views:
            self.a.ShowView(view)
            self.assertEqual(self.lua.globals().SHOWN_SECTION, "Evertally")
            self.assertTrue(self.a.guideShell.Shown(view), view)
        bad = {k: v for k, v in self.a.errors.items() if str(k).endswith("_page") or k == "ui_refresh"}
        self.assertEqual(bad, {}, self.a.lastUIError)

    def test_the_sidebar_switches_pages_and_toggle_closes_the_hub(self):
        section = self.install()
        self.a.OpenUI()
        self.assertTrue(self.a.OverviewShown())
        section.onNav("journal")
        self.assertTrue(self.a.guideShell.Shown("journal"))
        self.assertEqual(self.a.db.settings.lastView, "journal")
        self.assertFalse(self.a.OverviewShown())
        self.a.RefreshUI()
        self.a.ToggleUI()
        self.assertFalse(self.a.guideShell.Shown())
        self.a.ToggleUI()
        self.assertTrue(self.a.guideShell.Shown("journal"), "it opens again where it was")

    def test_the_rail_still_holds_every_guide_section(self):
        # W.ShellRail drops what is past its foot group. With our section the rows close up (import patch, to 46 px):
        # every section must still fit the smallest hub a skin draws (Halo and Hearth: 640 px).
        widgets = (ROOT / "addon" / "Evertally_Guide" / "Theme" / "Widgets.lua").read_text(encoding="latin-1")
        self.assertIn("step = max(46, math.floor((limit - y) / #items))", widgets)
        row = int(re.search(r"local RAIL_ROW = (\d+)", widgets).group(1))
        header = int(re.search(r"header = (\d+), tabs", widgets).group(1))
        heights = [int(h) for h in re.findall(r"pickerH = (\d+)", (ROOT / "addon" / "Evertally_Guide" / "Theme" / "Theme.lua").read_text(encoding="latin-1"))]
        rail, foot = 2, 1   # Evertally and the built-in Guides; Options
        for path in (ROOT / "addon" / "Evertally_Guide").rglob("*.lua"):
            text = path.read_text(encoding="latin-1")
            for m in re.finditer(r"^\s*UI\.RegisterSection\(\{", text, re.M):   # not the doc comment in Picker.lua
                head = text[m.end():m.end() + 300]
                if re.search(r"foot = true", head.split("})")[0]):
                    foot += 1
                else:
                    rail += 1
        self.assertEqual((rail, foot), (7, 2), "Evertally, Guides, Lookup, Dungeons, Talents, Rares, Characters; Options, Import")
        for height in heights + [680]:
            top, limit = header + 12, height - 2 - (12 + foot * row)
            self.assertLessEqual(top + rail * 46, limit, f"{height} px")

if __name__ == "__main__":
    unittest.main()
