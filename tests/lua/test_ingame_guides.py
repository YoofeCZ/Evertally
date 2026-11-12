"""Local guide chapters and a real talent planner; no game, network or player files."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import ROOT, runtime


def rows(table):
    return [table[i] for i in range(1, len(table) + 1)]


TALENTS = '''
 GetNumTalentTabs=function() return 2 end
 GetTalentTabInfo=function(tab) return tab==1 and "Holy" or "Protection",130000+tab,0,"PaladinHoly" end
 DATA={
   {{"First",130010,1,1,0,5},{"Second",130011,1,2,0,5},{"Dependent",130012,2,1,0,1},{"Third tier",130013,3,2,0,1}},
   {{"Other tree",130020,1,1,0,5}}}
 GetNumTalents=function(tab) return #DATA[tab] end
 GetTalentInfo=function(tab,index) return unpack(DATA[tab][index]) end
 GetTalentPrereqs=function(tab,index) if tab==1 and index==3 then return 1,1,true end end
 LEARN_CALLS=0
 LearnTalent=function() LEARN_CALLS=LEARN_CALLS+1;error("Planner must never train talents") end
'''


class InGameGuideTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()

    def guide_data(self):
        namespace = self.lua.table()
        source = (ROOT / "addon/Evertally_Map/GuideData.lua").read_text(encoding="utf-8")
        self.lua.eval("loadstring")(source)("Evertally_Map", namespace)
        self.a.map = namespace
        self.a.LoadGuide = self.lua.eval("function() return true end")
        return namespace

    def test_all_twelve_professions_and_nine_classes_have_readable_local_chapters(self):
        self.guide_data()
        library = rows(self.a.GuideLibrary())
        self.assertEqual(len([chapter for chapter in library if chapter.id.startswith("profession-")]), 12)
        self.assertEqual(len([chapter for chapter in library if chapter.id.startswith("class-")]), 9)
        for language in ("en", "cs"):
            self.a.db.settings.language = language
            for chapter in library:
                article = self.a.GuideArticle(chapter.id)
                sections = rows(article.sections)
                self.assertGreaterEqual(len(sections), 3, chapter.id)
                text = " ".join(section.body or "" for section in sections)
                self.assertGreater(len(text), 250, chapter.id)
                self.assertNotIn("https://", text, chapter.id)
                self.assertTrue(all(section.action is None or "http" not in section.action for section in sections))

    def test_recipe_batches_use_required_skill_and_exact_direct_material_counts(self):
        recipes = self.lua.eval('''{
          {id=1,name="First",line=171,skill={1,10,15,20},out=100,reagents={{10,2}}},
          {id=2,name="Next",line=171,req=10,skill={1,30,35,40},out=101,reagents={{11,3}}},
          {id=3,name="Locked",line=171,req=50,skill={1,100,110,120},out=102,reagents={{12,1}}}}
        ''')
        plan = self.a.ProfessionGuidePlan(171, recipes, 1, 30)
        self.assertEqual(plan.reached, 30)
        self.assertEqual([step.recipe.id for step in rows(plan.steps)], [1, 2])
        self.assertEqual(plan.materials[10], 18)
        self.assertEqual(plan.materials[11], 60)
        self.assertIsNone(plan.materials[12], "a recipe cannot be used before its learning requirement")

    def test_random_skillup_is_marked_and_missing_recipe_stops_instead_of_inventing_a_step(self):
        recipes = self.lua.eval('{ {id=1,name="Yellow",line=171,skill={1,1,5,10},out=1,reagents={{2,1}}} }')
        plan = self.a.ProfessionGuidePlan(171, recipes, 1, 300)
        self.assertTrue(all(step.chance for step in rows(plan.steps)))
        self.assertEqual(plan.uncovered, 10)
        self.assertEqual(plan.reached, 10)
        self.assertEqual(plan.materials[2], 9, "minimum attempts are labelled, not a promised 299 skill gains")

    def test_shipped_production_routes_are_contiguous_and_only_use_actual_recipes(self):
        data = self.guide_data()
        for profession in (171, 164, 165, 197, 202, 333, 185, 129):
            plan = self.a.ProfessionGuidePlan(profession, data.recipes, 1, 300)
            last = 1
            for step in rows(plan.steps):
                self.assertEqual(step.recipe.line, profession)
                self.assertEqual(step["from"], last)
                self.assertGreater(step.to, last)
                self.assertLessEqual(step.to, 300)
                self.assertGreaterEqual(last, max(step.recipe.skill[1], step.recipe.req or 1))
                last = step.to
            self.assertEqual(last, plan.reached)
            self.assertEqual(plan.reached, 300, f"profession {profession} lacks a complete documented path")


class TalentPlannerTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(TALENTS)
        self.trees = self.a.TalentTrees()
        self.plan = self.a.NewTalentPlan(self.trees, 60, True)

    def change(self, tree, talent, delta=1):
        result = self.a.ChangeTalentPlan(self.plan, self.trees, tree, talent, delta)
        return result if isinstance(result, bool) else result[0]

    def test_tier_prerequisite_maximum_and_remove_dependencies_are_enforced(self):
        self.assertFalse(self.change(1, 3))
        for _ in range(5):
            self.assertTrue(self.change(1, 1))
        self.assertFalse(self.change(1, 1), "maximum rank")
        self.assertTrue(self.change(1, 3))
        self.assertFalse(self.change(1, 1, -1), "cannot break the prerequisite of a learned dependent")
        self.assertFalse(self.change(1, 4), "tier 3 requires ten points in earlier tiers")
        for _ in range(5):
            self.assertTrue(self.change(1, 2))
        self.assertTrue(self.change(1, 4))
        self.assertTrue(self.change(1, 3, -1), "removal is valid while ten earlier points still exist")
        self.assertFalse(self.change(1, 2, -1), "cannot relock a higher tier")

    def test_budget_is_shared_between_trees_and_never_trains_actual_talents(self):
        self.plan.level = 10
        self.assertTrue(self.change(1, 1))
        self.assertFalse(self.change(2, 1))
        self.assertEqual(self.a.TalentPlanPoints(self.plan), 1)
        self.assertEqual(self.lua.globals().LEARN_CALLS, 0)
        self.assertEqual(self.a.TalentTrees()[1].talents[1].rank, 0)

    def test_load_current_uses_real_ranks_and_saved_builds_are_independent_and_validated(self):
        self.lua.execute('DATA[1][1][5]=5')
        current = self.a.NewTalentPlan(self.a.TalentTrees(), 60, False)
        self.assertEqual(current.ranks[1][1], 5)
        self.a.SaveTalentBuild(current, "Solo")
        current.ranks[1][1] = 0
        saved = self.a.SavedTalentBuilds()[1]
        self.assertEqual(saved.ranks[1][1], 5, "saving copies rather than aliases the active plan")
        loaded = self.a.LoadTalentBuild(saved, self.trees)
        self.assertEqual(loaded.ranks[1][1], 5)
        saved.ranks[1][3] = 1
        saved.ranks[1][1] = 1
        self.assertIsNone(self.a.LoadTalentBuild(saved, self.trees), "reject a damaged build that violates prerequisites")
        saved["class"] = "MAGE"
        self.assertIsNone(self.a.LoadTalentBuild(saved, self.trees), "never load another class into these trees")

    def test_saved_builds_are_bounded_and_same_name_replaces(self):
        for i in range(12):
            self.a.SaveTalentBuild(self.plan, f"Build {i}")
        self.assertEqual(len(self.a.SavedTalentBuilds()), 8)
        self.a.SaveTalentBuild(self.plan, "Build 11")
        self.assertEqual(len(self.a.SavedTalentBuilds()), 8)


if __name__ == "__main__":
    unittest.main()
