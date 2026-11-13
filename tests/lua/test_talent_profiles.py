"""Data-only talent profile transport, atomic validation and planner zoom."""
import json
import sys
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, MOCK_UI_LUA, ROOT
from test_forever_traits import FOREVER_TRAITS


class TalentProfileTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(FOREVER_TRAITS)
        # Compatible with explicit-runtime loader before or after root wires TOC.
        if self.a.ExportTalentProfile is None:
            self.lua.eval("loadstring")((ROOT / "addon/Evertally/TalentProfiles.lua").read_text(encoding="utf8"))("Evertally", self.a)
        self.trees = self.a.TalentTrees()

    def plan(self):
        plan = self.a.NewTalentPlan(self.trees, 60, True)
        plan.ranks[self.trees[1].tab][100001] = 5
        plan.ranks[self.trees[1].tab][100003] = 1
        plan.ranks[self.trees[2].tab][100201] = 2
        return plan

    @staticmethod
    def code(data):
        payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
        return f"ETB1|{zlib.adler32(payload.encode('utf8')):08x}|{payload}"

    def exported_data(self):
        code = self.a.ExportTalentProfile(self.plan(), self.trees, "Nájezd — profil")
        return code, json.loads(code.split("|", 2)[2])

    def test_export_is_deterministic_and_round_trips_every_rank_name_level_and_class(self):
        code, _data = self.exported_data()
        self.assertEqual(code, self.a.ExportTalentProfile(self.plan(), self.trees, "Nájezd — profil"))
        loaded, why, name = self.a.ImportTalentProfile(code, self.trees)
        self.assertIsNone(why)
        self.assertEqual(name, "Nájezd — profil")
        self.assertEqual((loaded.level, loaded["class"]), (60, "SHAMAN"))
        self.assertEqual(loaded.ranks[self.trees[1].tab][100001], 5)
        self.assertEqual(loaded.ranks[self.trees[1].tab][100003], 1)
        self.assertEqual(loaded.ranks[self.trees[2].tab][100201], 2)
        self.assertEqual(self.lua.globals().TRAIT_WRITES, 0)

    def test_checksum_rejects_truncation_or_tampering_before_any_state_changes(self):
        code, _ = self.exported_data()
        before = len(self.a.SavedTalentBuilds())
        for bad in (code[:-1], code.replace('"level":60', '"level":59'), "ETB2|" + code[5:], "x" * 16385):
            result = self.a.ImportTalentProfile(bad, self.trees)
            self.assertIsNone(result[0])
        self.assertEqual(len(self.a.SavedTalentBuilds()), before)

    def test_other_class_unknown_node_schema_and_duplicate_allocations_are_rejected(self):
        _code, data = self.exported_data()
        data["class"] = "DRUID"
        self.assertEqual(self.a.ImportTalentProfile(self.code(data), self.trees)[1], "talentProfileClass")
        data["class"] = "SHAMAN"
        data["talents"][0]["node"] = 999999999
        self.assertEqual(self.a.ImportTalentProfile(self.code(data), self.trees)[1], "talentProfileSchema")
        _code, data = self.exported_data()
        data["talents"].append(data["talents"][0].copy())
        self.assertEqual(self.a.ImportTalentProfile(self.code(data), self.trees)[1], "talentProfileInvalid")
        _code, data = self.exported_data()
        data["schema"] = "different-patch"
        self.assertEqual(self.a.ImportTalentProfile(self.code(data), self.trees)[1], "talentProfileSchema")

    def test_impossible_ranks_prerequisites_and_level_budget_fail_atomically(self):
        _code, data = self.exported_data()
        data["talents"][0]["rank"] = 999
        self.assertEqual(self.a.ImportTalentProfile(self.code(data), self.trees)[1], "talentProfileInvalid")
        _code, data = self.exported_data()
        data["level"] = 10
        self.assertEqual(self.a.ImportTalentProfile(self.code(data), self.trees)[1], "talentBudgetError")
        _code, data = self.exported_data()
        data["talents"] = [entry for entry in data["talents"] if entry["node"] != 100001]
        self.assertEqual(self.a.ImportTalentProfile(self.code(data), self.trees)[1], "talentProfilePrerequisite")
        self.assertEqual(len(self.a.SavedTalentBuilds()), 0)
        self.assertEqual(self.lua.globals().TRAIT_WRITES, 0)

    def test_validly_encoded_strings_are_never_lua_code(self):
        _code, data = self.exported_data()
        data["name"] = "_G.PROFILE_EXECUTED=true; print('never')"
        loaded, _, name = self.a.ImportTalentProfile(self.code(data), self.trees)
        self.assertIsNotNone(loaded)
        self.assertIn("PROFILE_EXECUTED", name)
        self.assertIsNone(self.lua.globals().PROFILE_EXECUTED)
        self.assertEqual(self.lua.globals().TRAIT_WRITES, 0)

    def test_reordering_nodes_does_not_change_schema_but_real_talent_change_does(self):
        schema = self.a.TalentProfileSchema(self.trees)
        self.lua.execute("TRAIT_ORDER={100301,100005,100002,100006,100201,100001,100004,100003}")
        self.assertEqual(self.a.TalentProfileSchema(self.a.TalentTrees()), schema)
        self.lua.execute("TRAIT_NODES[100001].maxRanks=4")
        self.assertNotEqual(self.a.TalentProfileSchema(self.a.TalentTrees()), schema)

    def test_legacy_numeric_tree_identifiers_round_trip_without_becoming_strings(self):
        from test_ingame_guides import TALENTS
        self.lua.execute("C_Traits=nil;C_ClassTalents=nil")
        self.lua.execute(TALENTS)
        trees=self.a.TalentTrees()
        plan=self.a.NewTalentPlan(trees,60,True)
        plan.ranks[1][1]=5
        code=self.a.ExportTalentProfile(plan,trees,"Classic schema")
        loaded,why,_=self.a.ImportTalentProfile(code,trees)
        self.assertIsNone(why)
        self.assertEqual(loaded.ranks[1][1],5)
        self.assertIsNone(loaded.ranks["1"])

    def test_recommendations_match_client_talents_and_reject_missing_names_without_partial_plan(self):
        self.lua.execute('''
          RECOMMEND={class="SHAMAN",level=60,ranks={{name="Fixture spell 400001",rank=5},{name="Fixture spell 400003",rank=1}}}
        ''')
        template = self.lua.globals().RECOMMEND
        plan = self.a.LoadRecommendedTalentBuild(template, self.trees)
        self.assertEqual(plan.ranks[self.trees[1].tab][100001], 5)
        template.ranks[2].name = "Wrong patch talent"
        result = self.a.LoadRecommendedTalentBuild(template, self.trees)
        self.assertIsNone(result[0]); self.assertEqual(result[1], "talentTemplateMismatch")
        self.assertEqual(len(self.a.SavedTalentBuilds()), 0)

    def test_import_name_cannot_overwrite_existing_saved_build(self):
        self.a.SaveTalentBuild(self.plan(), "Same build")
        self.assertEqual(self.a.UniqueTalentProfileName("Same build"), "Same build (2)")

    def page(self):
        self.lua.execute(MOCK_UI_LUA)
        page = self.lua.eval("CreateFrame")("Frame", None, None)
        page.SetSize(page, 850, 570)
        self.a.BuildTalentsPage(page, self.a.UIKit())
        page.Refresh()
        return page, page.talents

    def test_default_zoom_is_smaller_adjustable_bounded_and_persisted(self):
        page, state = self.page()
        self.assertEqual(self.a.TalentZoom(), .75)
        default_height = state.content.h
        state.zoomPlus.scripts.OnClick()
        self.assertAlmostEqual(self.a.TalentZoom(), .85)
        self.assertGreater(state.content.h, default_height)
        self.a.SetTalentZoom(9)
        self.assertEqual(self.a.TalentZoom(), 1.5)
        self.a.SetTalentZoom(.01)
        self.assertEqual(self.a.TalentZoom(), .5)
        self.assertEqual(self.a.db.settings.talentZoom, .5)

    def test_import_dialog_keeps_current_plan_unchanged_on_failure_and_saves_valid_profile(self):
        page, state = self.page()
        state.plan = self.plan()
        self.a.SaveTalentBuild(state.plan, "Same build")
        code = self.a.ExportTalentProfile(state.plan, self.trees, "Same build")
        state["import"].scripts.OnClick()
        dialog = state.transfer
        self.assertIsNotNone(dialog.box.font, "edit boxes must have an explicit font in Forever")
        dialog.box.SetText(dialog.box, "return os.execute('no')")
        dialog.apply.scripts.OnClick()
        self.assertEqual(state.plan.level, 60)
        self.assertEqual(len(self.a.SavedTalentBuilds()), 1)
        self.assertTrue(dialog.shown)
        dialog.box.SetText(dialog.box, code)
        dialog.apply.scripts.OnClick()
        self.assertFalse(dialog.shown)
        self.assertEqual(len(self.a.SavedTalentBuilds()), 2)
        self.assertEqual(self.a.SavedTalentBuilds()[2].name, "Same build (2)")
        self.assertEqual(self.lua.globals().TRAIT_WRITES, 0)

    def test_full_profile_collection_is_not_silently_evicted_by_import(self):
        page, state = self.page()
        plan=self.plan()
        for i in range(8):
            self.a.SaveTalentBuild(plan,f"Existing {i}")
        code=self.a.ExportTalentProfile(plan,self.trees,"Imported")
        state["import"].scripts.OnClick()
        dialog=state.transfer
        dialog.box.SetText(dialog.box,code)
        dialog.apply.scripts.OnClick()
        self.assertTrue(dialog.shown)
        self.assertEqual(len(self.a.SavedTalentBuilds()),8)
        self.assertEqual(self.a.SavedTalentBuilds()[1].name,"Existing 0")
        self.assertEqual(dialog.error.text,self.a.L("talentProfileLimit"))

    def test_zoom_layout_stays_inside_each_tree_at_minimum_and_normal_window_widths(self):
        sys.path.insert(0,str(ROOT/"tools/ui_preview"))
        import preview
        for width,height in ((700,460),(1100,720)):
            lua,addon=preview.make_session(width,height,language="cs")
            addon.ShowView("talents")
            lua.execute("PREVIEW_SETTLE()")
            for zoom in (.5,.75,1.5):
                addon.SetTalentZoom(zoom);addon.talentPage.Refresh();lua.execute("PREVIEW_SETTLE()")
                state=addon.talentPage.talents
                for _,button in state.buttons.items():
                    if not button.IsShown(button):continue
                    tree=next(v for _,v in state.columns.items() if v.IsShown(v) and button.GetLeft(button)>=v.GetLeft(v) and button.GetLeft(button)<v.GetLeft(v)+v.GetWidth(v))
                    self.assertLessEqual(button.GetLeft(button)+button.GetWidth(button),tree.GetLeft(tree)+tree.GetWidth(tree))
                    self.assertGreaterEqual(button.GetTop(button)-button.GetHeight(button),tree.GetTop(tree)-tree.GetHeight(tree))


if __name__ == "__main__":
    unittest.main()
