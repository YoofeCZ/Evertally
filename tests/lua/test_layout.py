"""The windows laid out with real anchoring (tools/ui_preview/layout_mock.lua): no empty buttons, no text on top of text, nothing outside the
window, at the default size and at the smallest. This is the check that would have caught what the first in-game screenshots showed."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "ui_preview"))
sys.path.insert(0, str(ROOT / "tests" / "lua"))
import preview  # noqa: E402

SIZES = ((960, 620), (700, 460))


def serious(problems):
    # cut-off text is an ellipsis by design (names, long lines); these are the real faults
    return [p for p in problems if not p.startswith("cut off")]


class LayoutTests(unittest.TestCase):
    def check(self, size, scenes):
        lua, a = preview.make_session(*size)
        for view, tab in scenes:
            nodes = preview.capture(lua, a, view, tab)
            self.assertTrue(len(nodes) > 20, f"{view} drew nothing")
            self.assertEqual(serious(preview.lint(nodes)), [], f"{view} {tab or ''} at {size}")
        self.assertIsNone(a.lastUIError, a.lastUIError)

    @staticmethod
    def every_scene():
        return [(view, state) for view in preview.VIEWS for state in (preview.STATES.get(view) or (None,))]

    def test_every_page_is_laid_out_cleanly_at_the_default_size(self):
        self.check(SIZES[0], self.every_scene())

    def test_every_page_is_laid_out_cleanly_at_the_smallest_size(self):
        self.check(SIZES[1], self.every_scene())

    def test_every_step_of_the_setup_is_laid_out_cleanly_in_both_languages_with_and_without_openmap(self):
        for openmap in (False, True):
            lua, a = preview.make_session(960, 620, openmap=openmap)
            for language in ("en", "cs"):
                a.db.settings.language = language
                for state in preview.STATES["setup"]:
                    nodes = preview.capture(lua, a, "setup", state)
                    self.assertGreater(len(nodes), 15, f"setup step {state} drew nothing")
                    self.assertEqual(serious(preview.lint(nodes)), [], f"setup step {state}, {language}, OpenMap {openmap}")

    def test_the_map_tab_is_laid_out_cleanly_with_openmap_installed_too(self):
        for size in SIZES:
            lua, a = preview.make_session(*size, openmap=True)
            nodes = preview.capture(lua, a, "world", "map")
            self.assertEqual(serious(preview.lint(nodes)), [], f"world map tab with OpenMap at {size}")

    def test_a_list_in_a_narrow_card_drops_the_tags_instead_of_drawing_them_over_the_text(self):
        lua, a = preview.make_session(960, 620)
        nodes = preview.capture(lua, a, "overview", "activity")
        # the recent-activity card is narrow: none of its rows may carry a tag pill
        tags = [n for n in nodes if n["kind"] == "FontString" and (n.get("text") or "") in ("LOOT", "QUEST COMPLETED", "ENTERED", "AREA VISIT")]
        self.assertEqual(preview.STATES["overview"][0], "activity", "the first state of the overview is the activity list")
        self.assertEqual(tags, [])
        wide = preview.capture(lua, a, "journal")
        self.assertTrue([n for n in wide if n["kind"] == "FontString" and (n.get("text") or "") == "LOOT"], "the wide journal list keeps its tags")

    def test_the_columns_never_stick_out_past_the_right_edge(self):
        lua, a = preview.make_session(700, 460)
        nodes = preview.capture(lua, a, "overview")
        window = next(n for n in nodes if n["kind"] not in ("Texture", "FontString") and n.get("name") == "EvertallyFrame")
        for n in nodes:
            if n["kind"] == "Texture" and n["w"] > 30 and n.get("rgba") and not n.get("clip"):
                self.assertLessEqual(n["l"] + n["w"], window["l"] + window["w"] + 1, "a card sticks out of the window")

    def test_every_navigation_entry_can_be_reached_at_the_smallest_size(self):
        lua, a = preview.make_session(700, 460)
        a.OpenUI()
        lua.execute("PREVIEW_SETTLE()")
        scroll = lua.globals().EvertallyNavigationScroll
        child = lua.globals().EvertallyNavigationContent
        entries = [button for _, button in child._children.items() if button.viewKey]
        self.assertEqual(len(entries), len(preview.VIEWS))
        self.assertGreater(scroll.maxScroll, 0, "a compact menu must scroll rather than clip its final entries")
        for button in entries:
            a.ShowView(button.viewKey)
            lua.execute("PREVIEW_SETTLE()")
            offset = scroll.GetVerticalScroll(scroll)
            self.assertGreaterEqual(button.navTop, offset, button.viewKey)
            self.assertLessEqual(button.navBottom, offset + scroll.GetHeight(scroll), button.viewKey)

    def test_navigation_wheel_is_bounded_and_resize_resets_obsolete_scroll(self):
        lua, a = preview.make_session(700, 460)
        a.OpenUI()
        lua.execute("PREVIEW_SETTLE()")
        scroll = lua.globals().EvertallyNavigationScroll
        wheel = scroll.GetScript(scroll, "OnMouseWheel")
        wheel(scroll, -100)
        self.assertEqual(scroll.GetVerticalScroll(scroll), scroll.maxScroll)
        wheel(scroll, 100)
        self.assertEqual(scroll.GetVerticalScroll(scroll), 0)
        a.ShowView("settings")
        self.assertGreater(scroll.GetVerticalScroll(scroll), 0)
        a.SetUISize(960, 620)
        lua.execute("PREVIEW_SETTLE()")
        self.assertEqual(scroll.maxScroll, 0)
        self.assertEqual(scroll.GetVerticalScroll(scroll), 0)


if __name__ == "__main__":
    unittest.main()
