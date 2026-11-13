"""Published Forever allocations and the faction-reversed Sleeping Bag trail."""
import unittest
from test_addon import runtime


class GuideContentTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()

    def by_id(self):
        return {str(item.id): item for _, item in self.a.RecommendedBuilds.items()}

    def test_recommended_allocations_cover_every_class_and_use_a_complete_level60_budget(self):
        builds = list(self.by_id().values())
        self.assertEqual(len(builds), 13)
        self.assertEqual({str(b["class"]) for b in builds},
                         {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"})
        for build in builds:
            with self.subTest(build=build.id):
                ranks = [r for _, r in build.ranks.items()]
                self.assertEqual(sum(r.rank for r in ranks), 51)
                self.assertEqual(len({r.name for r in ranks}), len(ranks))
                self.assertTrue(all(1 <= r.rank <= 5 and r.rank == int(r.rank) for r in ranks))
                self.assertEqual(build.level, 60)
                self.assertIn("wowhandbook.com/classes/", build.source.url)
                self.assertEqual(build.source.checkedAt, "2026-11-13")
                self.assertIn("1.60.1.", build.source.clientBuild)

    def test_druid_role_presets_contain_the_role_defining_forever_talents(self):
        builds = self.by_id()
        def ranks(ident):
            return {str(r.name): int(r.rank) for _, r in builds[ident].ranks.items()}
        tank = ranks("druid-feral-tank")
        self.assertEqual(tank["Natural Reaction"], 5)
        self.assertEqual(tank["Primal Bite"], 1)
        self.assertEqual(ranks("druid-feral-leveling")["Shifting Power"], 1)
        healer = ranks("druid-restoration")
        self.assertEqual(healer["Wild Growth"], 1)
        self.assertEqual(healer["Nature's Swiftness"], 1)
        balance = ranks("druid-balance")
        self.assertEqual(balance["Moonkin Form"], 1)
        self.assertEqual(balance["Eclipse"], 3)

    def test_sleeping_bag_start_objects_reverse_between_factions_and_then_rejoin(self):
        a = self.a.GuideArticle("sleeping-bag-alliance")
        h = self.a.GuideArticle("sleeping-bag-horde")
        self.assertIsNotNone(a)
        self.assertIsNotNone(h)
        self.assertIn("navigate:1436:0.3750:0.5070", a.sections[2].action)
        self.assertIn("navigate:1413:0.4640:0.7390", a.sections[3].action)
        self.assertIn("navigate:1413:0.4640:0.7390", h.sections[2].action)
        self.assertIn("navigate:1436:0.3750:0.5070", h.sections[3].action)
        self.assertEqual(a.sections[2].questId, 79008)
        self.assertEqual(h.sections[2].questId, 79007)
        for index in range(4, len(a.sections) + 1):
            self.assertEqual(a.sections[index].body, h.sections[index].body)
            self.assertEqual(a.sections[index].action, h.sections[index].action)

    def test_sleeping_bag_is_readable_offline_in_both_languages_with_real_navigation_targets(self):
        self.assertEqual(self.a.SleepingBagGuide.requiredLevel, 14)
        self.assertEqual(self.a.SleepingBagGuide.itemId, 211527)
        for language in ("en", "cs"):
            self.a.db.settings.language = language
            guide = self.a.GuideArticle("sleeping-bag-alliance")
            text = " ".join(str(s.body) for _, s in guide.sections.items())
            for marker in ("Pocket Litter", "Scramble", "Wet Job", "Eagle's Fist", "Hastily Rolled-Up Satchel"):
                self.assertIn(marker, text)
            navigable = 0
            for _, section in guide.sections.items():
                if section.action:
                    _, map_id, x, y, _title = str(section.action).split(":", 4)
                    self.assertIn(int(map_id), {1436, 1413, 1442, 1432, 1424, 1417})
                    self.assertTrue(0 < float(x) < 1 and 0 < float(y) < 1)
                    navigable += 1
            self.assertGreaterEqual(navigable, 9)
            self.assertGreater(len(text), 1200, "the guide must contain the actual steps, not just an external URL")
            self.assertEqual(len(guide.sections[len(guide.sections)].sources), 3)


if __name__ == "__main__":
    unittest.main()
