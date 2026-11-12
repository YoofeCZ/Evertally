"""Packaged factual metadata stays useful without a warm game item cache."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, ROOT


class GuideDatasetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua, _ = runtime()
        cls.data = cls.lua.table()
        cls.lua.eval('loadstring')((ROOT / 'addon/Evertally_Map/GuideData.lua').read_text(encoding='utf8'))('Evertally_Map', cls.data)

    def test_reference_quest_has_real_choice_rewards_and_base_xp(self):
        quest = self.data.questDetails[96395]
        self.assertEqual(quest.name, 'An Ancient Grudge')
        self.assertEqual(quest.requiredLevel, 10)
        self.assertEqual(quest.choice[1][1], 279899)
        self.assertEqual(quest.choice[2][1], 279900)
        self.assertEqual(quest.xpBase, 1050)
        self.assertIn('Ghostly Attendant', quest.startName)
        self.assertEqual(self.data.itemGuide[279899].name, 'Catacomb Cloak')
        self.assertTrue(self.data.itemGuide[279899].icon)

    def test_unknown_reward_grouping_is_not_presented_as_guaranteed(self):
        quest = self.data.questDetails[6]
        self.assertTrue(quest.rewards)
        self.assertIsNone(quest.guaranteed)
        self.assertIsNone(quest.choice)

    def test_additional_fixed_reward_is_separate_from_the_choice(self):
        quest = self.data.questDetails[3341]
        self.assertEqual([quest.choice[i][1] for i in range(1, len(quest.choice)+1)], [10824, 270081])
        self.assertEqual(quest.guaranteed[1][1], 10823)

    def test_every_recipe_reagent_has_packaged_item_metadata(self):
        for _, recipe in self.data.recipes.items():
            for _, reagent in recipe.reagents.items():
                self.assertTrue(self.data.itemGuide[reagent[1]], f'missing item #{reagent[1]}')


if __name__ == '__main__': unittest.main()
