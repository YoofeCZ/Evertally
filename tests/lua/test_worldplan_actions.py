"""Journey controls run on the real anchoring mock, with the addon's actual navigation entry point."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "ui_preview"))
import preview


class WorldPlanActionsTests(unittest.TestCase):
    def session(self, width=960, height=620):
        lua, addon = preview.make_session(width, height, language="cs")
        preview.capture(lua, addon, "world", "plan")
        lua.execute('''
            FRAME=Evertally.worldBody.tabFrames.plan
            local M=Evertally.map
            local u,v=M.ToUV(1453,.5,.5)
            M.Plan.cache={{name="Stormwind City",lower="stormwind city",map=1453,u=u,v=v,rank=1}}
            FRAME.plan.box:SetText("storm")
            FRAME.plan.box:GetScript("OnTextChanged")(FRAME.plan.box)
            FRAME.plan.rows[1]:GetScript("OnClick")()
            PREVIEW_SETTLE()
        ''')
        return lua, addon, lua.globals().FRAME, lua.globals().FRAME.plan

    @staticmethod
    def click(button):
        button.GetScript(button, "OnClick")()

    def finish_preview(self, addon):
        job = addon.map.Plan.preview
        for _ in range(10000):
            if job.state != "pending":
                break
            addon.map.Journey.Step(job)
        self.assertEqual(job.state, "ready", job.reason)

    def test_controls_are_children_above_paper_and_fit_at_both_window_sizes(self):
        for size in ((960, 620), (700, 460)):
            with self.subTest(size=size):
                lua, addon, frame, state = self.session(*size)
                paper, footer = state.book.paper, state.footer
                self.assertEqual(footer.GetParent(footer)._id, paper._id)
                self.assertGreater(footer.GetFrameLevel(footer), paper.GetFrameLevel(paper))
                self.assertEqual(state.list.GetParent(state.list)._id, state.book.index._id)
                self.assertGreater(state.list.GetFrameLevel(state.list), state.book.index.GetFrameLevel(state.book.index))
                self.assertGreater(state.rows[1].GetFrameLevel(state.rows[1]), state.list.GetFrameLevel(state.list))
                drawn = preview.to_py(lua.eval("PREVIEW_EXPORT")(None))
                names = [node for node in drawn if node.get("text") == "Stormwind City"]
                self.assertGreaterEqual(len(names), 2, "selected destination must appear in both list and reader")
                for button in (state.go, state.show, state.more, state.stop):
                    self.assertEqual(button.GetParent(button)._id, footer._id)
                    self.assertGreater(button.GetFrameLevel(button), footer.GetFrameLevel(footer))
                    self.assertGreaterEqual(button.GetLeft(button), paper.GetLeft(paper))
                    self.assertLessEqual(button.GetLeft(button) + button.GetWidth(button), paper.GetLeft(paper) + paper.GetWidth(paper))
                    self.assertLessEqual(button.GetTop(button) + button.GetHeight(button), paper.GetTop(paper) + paper.GetHeight(paper))
                self.assertTrue(state.go.IsShown(state.go))
                self.assertTrue(state.show.IsShown(state.show))
                self.assertFalse(state.stop.IsShown(state.stop))
                self.assertIsNone(addon.lastUIError)

    def test_navigate_button_reaches_the_real_navigator_with_exact_selected_coordinates(self):
        lua, addon, frame, state = self.session()
        self.click(state.go)
        self.assertEqual(addon.map.nav.target.map, 1453)
        self.assertEqual(addon.map.nav.target.x, .5)
        self.assertEqual(addon.map.nav.target.y, .5)
        self.assertEqual(addon.map.nav.target.source.tab, "plan")
        self.assertEqual(addon.map.nav.target.source.name, "Stormwind City")
        self.assertTrue(state.stop.IsShown(state.stop))
        self.assertEqual(addon.map.nav.journey.state, "pending")
        self.assertIn("Porovnávám", state.document.spec.entries[1].text)

    def test_map_button_preserves_all_three_lua_return_values_for_a_city(self):
        lua, addon, frame, state = self.session()
        lua.execute('''
            Evertally.map.ShowOnWorldMap=function() return true end
            Evertally.map.ShowRoute=function(plan, goals) SHOWN_GOAL=goals[1];return true end
        ''')
        self.click(state.show)
        self.finish_preview(addon)
        point = lua.globals().SHOWN_GOAL
        self.assertEqual(point.map, 1453)
        self.assertEqual(point.x, .5)
        self.assertEqual(point.y, .5)

    def test_map_button_preserves_hub_coordinates_instead_of_replacing_them_by_map_centre(self):
        lua, addon, frame, state = self.session()
        lua.execute('''
            local M=Evertally.map
            local u,v=M.ToUV(1453,.23,.71)
            FRAME.plan.chosen={name="Stormwind harbour",u=u,v=v}
            M.ShowOnWorldMap=function() return true end
            M.ShowRoute=function(plan, goals) SHOWN_GOAL=goals[1];return true end
        ''')
        self.click(state.show)
        self.finish_preview(addon)
        point = lua.globals().SHOWN_GOAL
        expected = addon.map.Plan.Point(state.chosen)
        self.assertEqual(point.map, expected[0])
        self.assertAlmostEqual(point.x, expected[1])
        self.assertAlmostEqual(point.y, expected[2])

    def test_stop_button_cancels_real_navigation_and_preview_lines(self):
        lua, addon, frame, state = self.session()
        self.click(state.go)
        addon.map.route = lua.table(steps=lua.table())
        self.click(state.stop)
        self.assertIsNone(addon.map.nav.target)
        self.assertIsNone(addon.map.route)
        self.assertFalse(state.stop.IsShown(state.stop))
        self.assertIn("zastavena", state.document.spec.entries[1].text)

    def test_global_stop_cannot_publish_an_old_pending_map_preview_later(self):
        lua, addon, frame, state = self.session()
        lua.execute('Evertally.map.ShowRoute=function() GHOST_ROUTE=true end')
        self.click(state.show)
        job = addon.map.Plan.preview
        self.assertEqual(job.state,"pending")
        addon.StopNavigation()
        self.assertEqual(job.state,"cancelled")
        addon.map.Journey.Step(job)
        addon.map.WorldPlanShow(frame)
        self.assertIsNone(lua.globals().GHOST_ROUTE)
        self.assertIsNone(state.wantMap)

    def test_navigation_rejection_is_shown_in_reader_and_chat(self):
        lua, addon, frame, state = self.session()
        lua.execute('''
            Evertally.NavigateToPoint=function() return false,"map_off" end
            Evertally.Print=function(message) LAST_MESSAGE=message end
        ''')
        self.click(state.go)
        self.assertIn("nepodařilo", state.message)
        self.assertEqual(lua.globals().LAST_MESSAGE, state.message)
        self.assertEqual(state.document.spec.entries[1].text, state.message)

    def test_full_itinerary_is_optional_and_refresh_preserves_search_selection_and_details(self):
        lua, addon, frame, state = self.session()
        lua.execute('''
            Evertally.map.Plan.Journey=function()
                return {seconds=600,steps={
                    {mode="walk",to="Port",seconds=60},
                    {mode="boat",from="Port",to="Stormwind",wait=120},
                    {mode="walk",to="Stormwind City",seconds=60}}}
            end
            Evertally.map.WorldPlanShow(FRAME)
        ''')
        self.assertEqual(len(state.document.spec.entries), 1)
        self.click(state.more)
        self.assertEqual(len(state.document.spec.entries), 4)
        addon.map.WorldPlanRefresh(frame)
        self.assertEqual(state.query, "storm")
        self.assertEqual(state.chosen.name, "Stormwind City")
        self.assertTrue(state.details)
        self.assertEqual(len(state.document.spec.entries), 4)
        self.click(state.more)
        self.assertEqual(len(state.document.spec.entries), 1)


if __name__ == "__main__":
    unittest.main()
