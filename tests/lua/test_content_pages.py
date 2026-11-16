"""Content pages use the shared UI cards and keep real controls/data at narrow widths.

These are Lua/frame contract checks, not screenshots or a live WoW appearance claim.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime


class ContentPageTests(unittest.TestCase):
    def setUp(self):
        self.lua,self.a=runtime()
        self.lua.execute("date=os.date")
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute('''
        MOCKALL={}
        local original=object
        function object(parent)
          local o=original(parent);o.points={}
          function o:SetPoint(...) self.points[#self.points+1]={...} end
          function o:ClearAllPoints() self.points={} end
          function o:SetAllPoints(target) self.allPoints=target or self.parent end
          MOCKALL[#MOCKALL+1]=o
          return o
        end
        function PAGE(key) for _,o in ipairs(MOCKALL) do if o.titleKey==key and o.Refresh then return o end end end
        ''')
        self.a.OpenUI()

    def page(self,key):
        self.a.ShowView(key)
        self.assertIsNone(self.a.lastUIError)
        return self.lua.globals().PAGE(key)

    def test_profession_cards_count_latest_known_recipes_and_active_cooldowns(self):
        self.lua.execute('''
        Evertally.Record("profession.snapshot",{professionId=171,name="Alchemy",skill=50,maxSkill=75,recipes={{recipeId=1,name="Old",learned=true}}})
        NOW=NOW+1
        Evertally.Record("profession.snapshot",{professionId=171,name="Alchemy",skill=75,maxSkill=150,recipes={{recipeId=2,name="Known",learned=true},{recipeId=3,name="Unknown",learned=false}}})
        Evertally.Record("cooldown.snapshot",{recipeId=2,readyAt=NOW+120})
        ''')
        page=self.page('professions')
        self.assertEqual([page.metrics[i].value.text for i in (1,2,3)],['1','1','1'])
        self.assertEqual(len(page.filters),3)
        page.filters[2].scripts.OnClick()
        self.assertEqual(page.mode,'recipes')
        page.filters[3].scripts.OnClick()
        self.assertEqual(page.mode,'cooldowns')
        self.lua.execute('NOW=NOW+200')
        self.a.RefreshUI()
        self.assertEqual(page.metrics[3].value.text,'0')

    def test_places_counts_are_unchanged_by_search_and_match_the_retained_entries(self):
        self.lua.execute('''
        Evertally.Record("zone.visited",{mapId=1429,mapName="Elwynn Forest",mapSystem="ui_map"})
        Evertally.Record("zone.visited",{mapId=1429,mapName="Elwynn Forest",mapSystem="ui_map"})
        Evertally.Record("zone.visited",{mapId=1436,mapName="Westfall",mapSystem="ui_map"})
        ''')
        page=self.page('places')
        self.assertEqual([page.metrics[i].value.text for i in (1,2)],['2','3'])
        page.search.SetText(page.search,'westfall')
        page.search.scripts.OnTextChanged(page.search)
        self.assertEqual(page.query,'westfall')
        self.assertEqual([page.metrics[i].value.text for i in (1,2)],['2','3'])
        self.assertIsNone(self.a.lastUIError)

    def test_atlas_has_real_observation_counts_and_independent_kind_filters(self):
        self.lua.execute('''
        Evertally.Record("quest.accepted",{questId=1,title="Fixture quest"})
        Evertally.Record("quest.turned_in",{questId=1,title="Fixture quest"})
        Evertally.Record("npc.observed",{npcId=7,name="Fixture NPC"})
        Evertally.Record("loot.received",{itemId=25,name="Fixture sword",quantity=2})
        ''')
        page=self.page('facts')
        self.assertEqual([page.metrics[i].value.text for i in (1,2,3)],['2','1','1'])
        page.filters[3].scripts.OnClick()
        self.assertEqual(page.kind,'npcs')
        page.search.SetText(page.search,'7');page.search.scripts.OnTextChanged(page.search)
        self.assertEqual(page.query,'7')
        self.assertIsNone(self.a.lastUIError)

    def test_settings_categories_show_one_reading_page_and_toggles_keep_their_policy(self):
        page=self.page('settings')
        # sharing, live, web, interface, nameplates, music, actions, diagnostics
        self.assertEqual(len(page.settingCards),8)
        for i in range(1,9):
            card=page.settingCards[i]
            self.assertGreater(card.h,40)
            page.categoryButtons[i].scripts.OnClick()
            self.assertEqual(page.selectedSection,i)
            self.assertEqual([page.settingCards[j].shown for j in range(1,9)],[j==i for j in range(1,9)])
            self.assertGreaterEqual(page.scroll.child.h,card.h)
        buttons=self.lua.globals().MOCKBUTTONS
        toggles=[buttons[i] for i in range(1,len(buttons)+1) if buttons[i].get]
        self.assertTrue(toggles)
        for toggle in toggles:
            self.assertEqual(toggle.points[1][1],'TOPLEFT')
            self.assertEqual(toggle.points[2][1],'TOPRIGHT')
            self.assertGreaterEqual(toggle.h,36)
        web=next(b for b in toggles if b.localeKey=='web')
        scope=next(b for b in toggles if b.localeKey=='own_track')
        self.assertFalse(self.a.db.settings.web)
        scope.scripts.OnClick();self.assertFalse(self.a.db.settings.scopes.own_track)
        web.scripts.OnClick();scope.scripts.OnClick()
        self.assertTrue(self.a.db.settings.web);self.assertTrue(self.a.db.settings.scopes.own_track)

    def test_summary_columns_and_search_stretch_at_the_smallest_content_width(self):
        for key in ('professions','places','facts','webfacts'):
            page=self.page(key)
            page.metricRow.Layout(580)
            self.assertLessEqual(sum(page.metricRow.cells[i].w for i in range(1,len(page.metricRow.cells)+1))+10*(len(page.metricRow.cells)-1),581)
            self.assertEqual(page.search.points[1][1],'TOPLEFT')
            self.assertEqual(page.search.points[2][1],'TOPRIGHT')
        community=self.page('webfacts')
        self.assertEqual(community.metrics[3].value.text,'—')
        self.assertEqual(community.metrics[3].delta.text,self.a.L('pageCacheEmpty'))

    def test_run_and_place_selection_read_inline_without_losing_the_selected_record(self):
        self.lua.execute('''
          Evertally.db.runs={{name="The Deadmines",status="completed",startedAt=NOW-100,durationMs=100000,bossCount=2}}
          Evertally.Record("zone.visited",{mapId=1429,mapName="Elwynn Forest",mapSystem="ui_map"})
        ''')
        for key in ('history','places'):
            page=self.page(key)
            self.assertTrue(page.book.paper.parchment)
            self.assertTrue(page.document.spec.title)
            selected=page.recordKey
            self.a.RefreshUI()
            self.assertEqual(page.recordKey,selected)
            self.assertIsNone(self.lua.globals().EvertallyDetailFrame, 'reading a row should not force a modal')


if __name__=='__main__':unittest.main()
