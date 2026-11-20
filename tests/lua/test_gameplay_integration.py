"""The three own gameplay modules are part of the shipped addon, without optional addon mocks."""
from pathlib import Path
import unittest

from test_addon import MOCK_UI_LUA, ROOT, runtime


class GameplayIntegrationTests(unittest.TestCase):
    def test_distribution_declares_each_module_once_and_all_files_exist(self):
        toc = (ROOT / 'addon' / 'Evertally' / 'Evertally.toc').read_text(encoding='utf-8')
        files = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith('#')]
        for name in ('Gear.lua', 'GearUI.lua', 'TrainingData.lua', 'Training.lua', 'TrainingUI.lua',
                     'QuestGuideData.lua', 'QuestGuide.lua', 'QuestGuideUI.lua'):
            self.assertEqual(files.count(name), 1, name)
            self.assertTrue((ROOT / 'addon' / 'Evertally' / name).is_file(), name)
        for data, module in (('TrainingData.lua', 'Training.lua'), ('QuestGuideData.lua', 'QuestGuide.lua')):
            self.assertLess(files.index(data), files.index(module))

    def test_own_pages_open_with_no_other_gear_training_or_guide_addon(self):
        lua, addon = runtime()
        lua.execute(MOCK_UI_LUA)
        lua.execute('date=os.date; WhatsTraining=nil; WT_API=nil; GearQuestForever=nil; Matty7500QuestGuide=nil')
        for view, field in (('gear', 'gearPage'), ('training', 'trainingPage'), ('questguide', 'questGuidePage')):
            addon.ShowView(view)
            self.assertIsNotNone(addon[field], view)
            self.assertIsNone(addon.errors[view + '_page'], str(addon.lastUIError))
            self.assertIsNone(addon.errors.ui_refresh, str(addon.lastUIError))
        addon.SetUISize(700, 460)
        addon.SetLanguage('cs')
        for view in ('gear', 'training', 'questguide'):
            addon.ShowView(view)
            addon.RefreshUI()
            self.assertIsNone(addon.errors.ui_refresh, str(addon.lastUIError))
        self.assertIsNone(addon.lastUIError)

    def test_new_shortcuts_work_without_the_app_and_openmap(self):
        # (2026-11-20: the app and OpenMap are optional; there is no installation gate any more)
        lua, addon = runtime(enforce_requirements=True)
        lua.execute(MOCK_UI_LUA)
        lua.execute('date=os.date')
        for command in ('gear', 'train', 'guide'):
            lua.globals().SlashCmdList.EVERTALLY(command)
            self.assertTrue(addon.RequirementsReady())
            self.assertFalse(addon.RequirementsComplete())
            self.assertFalse(bool(addon.onboarding and addon.onboarding.window and addon.onboarding.window.IsShown(addon.onboarding.window)),
                             "no installation page instead of the shortcut")


if __name__ == '__main__':
    unittest.main()
