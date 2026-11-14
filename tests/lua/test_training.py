"""Own training model, bundled Forever data and UI contracts; no running WoW required."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import ADDON, MOCK_UI_LUA, runtime


def training_runtime():
    lua, addon = runtime()
    if addon.Training is None:
        for name in ("TrainingData.lua", "Training.lua", "TrainingUI.lua"):
            lua.eval("loadstring")((ADDON / name).read_text(encoding="utf8"), name)("Evertally", addon)
    lua.execute("""
        LEVEL=10; RACE=4; FACTION='Alliance'; MONEY=10000; KNOWN={}; PETKNOWN={}; BOOKCHECKS=0
        UnitClass=function() return 'Druid','DRUID',11 end
        UnitRace=function() return 'Night Elf','NightElf',RACE end
        UnitFactionGroup=function() return FACTION end
        UnitLevel=function() return LEVEL end
        GetMoney=function() return MONEY end
        Enum={SpellBookSpellBank={Player=0,Pet=1},TrainerType={Class=1,Pet=2}}
        C_SpellBook={IsSpellKnown=function(id,bank) BOOKCHECKS=BOOKCHECKS+1; return (bank==1 and PETKNOWN[id] or bank==0 and KNOWN[id])==true end}
        C_Spell={GetSpellInfo=function(id) return {name='Spell '..id,iconID=136096} end,GetSpellSubtext=function(id) return 'Rank '..id end}
        GetItemInfo=function(id) return 'Grimoire '..id end
        GetItemIcon=function() return 136096 end
    """)
    addon.Training.Invalidate(False)
    return lua, addon


class TrainingTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = training_runtime()

    def catalog(self, rows, overrides="{}", quests="{}"):
        self.lua.execute("Evertally.trainingData={classes={DRUID={spells=" + rows + ",overrides=" + overrides + "}},questSpells={DRUID=" + quests + "},trainers={}}")
        self.a.Training.Invalidate(False)

    def rows(self):
        rows = self.a.Training.Model().rows
        return {str(rows[i].id): rows[i] for i in range(1, len(rows) + 1)}

    def test_real_catalog_covers_nine_classes_and_forever_spells(self):
        data = self.a.trainingData
        self.assertEqual(len(list(data.classes.keys())), 9)
        total = sum(len(data.classes[c].spells) for c in data.classes.keys())
        self.assertGreater(total, 1400)
        self.assertEqual(data.sourceVersion, "11.4.7")
        self.assertGreater(len(data.trainers), 200)
        spell_ids = {row.id for c in data.classes.keys() for _, row in data.classes[c].spells.items() if isinstance(row.id, (int, float))}
        self.assertTrue(any(i > 1_000_000 for i in spell_ids))
        tomes = [row for _, row in data.classes.WARLOCK.spells.items() if row.tome]
        self.assertGreater(len(tomes), 30)
        self.assertTrue(all(row.taughtId for row in tomes))

    def test_level_prerequisite_and_talent_are_separate_from_price(self):
        self.catalog("{{id=10,level=1,baseCost=10},{id=20,level=10,baseCost=300,requiredIds={10}},{id=30,level=11,baseCost=500},{id=40,level=10,baseCost=700,requiredTalentId=99}}")
        self.lua.execute("KNOWN[10]=true")
        model = self.a.Training.Model()
        rows = self.rows()
        self.assertEqual(rows["10"].status, "known")
        self.assertEqual(rows["20"].status, "ready")
        self.assertEqual(rows["30"].status, "later")
        self.assertEqual(rows["40"].status, "requirements")
        self.assertEqual(model.readyCount, 1)
        self.assertEqual(model.total, 300)

    def test_missing_rank_is_not_counted_as_ready(self):
        self.catalog("{{id=20,level=10,baseCost=300,requiredIds={10}}}")
        row = self.rows()["20"]
        self.assertEqual(row.status, "requirements")
        self.assertEqual(row.missingId, 10)
        self.assertEqual(self.a.Training.Model().total, 0)

    def test_known_higher_rank_suppresses_all_earlier_overrides(self):
        self.catalog("{{id=10,level=1,baseCost=10},{id=20,level=5,baseCost=50},{id=30,level=10,baseCost=100}}", "{{10,20,30}}")
        self.lua.execute("KNOWN[30]=true")
        self.assertTrue(all(row.status == "known" for row in self.rows().values()))
        self.assertEqual(self.a.Training.Model().readyCount, 0)

    def test_missing_spellbook_is_unknown_not_unlearned(self):
        self.catalog("{{id=10,level=1,baseCost=10}}")
        self.lua.execute("C_SpellBook=nil;IsSpellKnown=nil;IsPlayerSpell=nil")
        self.assertEqual(self.rows()["10"].status, "unknown")
        self.assertEqual(self.a.Training.Model().total, 0)

    def test_modern_api_then_legacy_fallback(self):
        self.catalog("{{id=10,level=1,baseCost=10}}")
        self.lua.execute("C_SpellBook=nil; IsSpellKnown=function(id,pet) return id==10 and not pet end")
        self.assertTrue(self.a.Training.Known(10, False))
        self.assertFalse(self.a.Training.Known(10, True))

    def test_faction_and_high_numbered_race_filters(self):
        self.catalog("{{id=10,level=1,baseCost=10,race=95},{id=20,level=1,baseCost=10,races={96}},{id=30,level=1,baseCost=10,faction='Horde'}}")
        self.lua.execute("RACE=95")
        self.assertEqual(set(self.rows()), {"10"})
        self.lua.execute("RACE=96;FACTION='Horde'")
        self.assertEqual(set(self.rows()), {"20", "30"})

    def test_class_quest_source_uses_actual_race_and_quest_ids(self):
        self.catalog("{}", quests="{[123]={{races={95},level=10,quests={94003}},{races={96},level=10,quests={94004}}}}")
        self.lua.execute("RACE=95")
        self.assertEqual(self.rows()["quest:123"].quests[1], 94003)
        self.lua.execute("RACE=96")
        self.assertEqual(self.rows()["quest:123"].quests[1], 94004)

    def test_pet_unknown_does_not_inflate_total_and_beast_training_observes_known(self):
        self.catalog("{{id=80,level=1,baseCost=10,pet=true},{id=81,level=1,baseCost=20,pet=true}}")
        self.assertEqual(self.rows()["80"].status, "pet_unknown")
        self.assertEqual(self.a.Training.Model().total, 0)
        self.lua.execute("GetNumTrainerServices=function()return 1 end; C_TooltipInfo={GetTrainerService=function()return{id=80}end};C_Trainer={GetTrainerType=function()return 2 end}")
        self.a.Dispatch("TRAINER_SHOW")
        self.assertEqual(self.rows()["80"].status, "known")
        self.assertEqual(self.rows()["81"].status, "ready")
        self.assertEqual(self.a.Training.Model().total, 20)

    def test_tomes_use_taught_spell_and_active_pet_family(self):
        self.catalog("{{id='tome:123',itemId=123,taughtId=222,family='Imp',tome=true,level=1,baseCost=50}}")
        self.lua.execute("UnitCreatureFamily=function()return 'Imp' end;PETKNOWN[222]=true")
        self.assertEqual(self.rows()["tome:123"].status, "known")
        self.lua.execute("UnitCreatureFamily=function()return 'Voidwalker' end")
        self.a.Training.Invalidate(False)
        self.assertEqual(self.rows()["tome:123"].status, "pet_unknown")

    def test_observed_price_is_distinct_and_reputation_change_invalidates_it(self):
        self.catalog("{{id=20,level=1,baseCost=300}}")
        self.lua.execute("GetNumTrainerServices=function()return 1 end; C_TooltipInfo={GetTrainerService=function()return{id=20}end};C_Trainer={GetTrainerType=function()return 1 end};GetTrainerServiceCost=function()return 270 end")
        self.a.Training.ObserveTrainer()
        self.assertEqual(self.rows()["20"].priceSource, "observed")
        self.assertEqual(self.a.Training.Model().total, 270)
        self.a.Dispatch("UPDATE_FACTION")
        self.assertEqual(self.rows()["20"].priceSource, "base")
        self.assertEqual(self.a.Training.Model().total, 300)

    def test_price_zero_is_valid_and_affordability_responds_without_rescan(self):
        self.catalog("{{id=20,level=1,baseCost=300},{id=30,level=1,baseCost=0}}")
        model = self.a.Training.Model()
        checks = self.lua.globals().BOOKCHECKS
        self.assertEqual(model.readyCount, 2)
        self.lua.execute("MONEY=299")
        self.assertFalse(self.a.Training.Model().affordable)
        self.assertEqual(self.lua.globals().BOOKCHECKS, checks)
        self.lua.execute("MONEY=300")
        self.assertTrue(self.a.Training.Model().affordable)

    def test_spell_info_load_is_requested_once_then_refreshed(self):
        self.lua.execute("LOADS=0;C_Spell.GetSpellInfo=function(id)if NAME_READY then return{name='Loaded',iconID=123}end end;C_Spell.RequestLoadSpellData=function()LOADS=LOADS+1 end;GetSpellInfo=nil")
        self.assertFalse(self.a.Training.SpellInfo(999).loaded)
        self.a.Training.SpellInfo(999)
        self.assertEqual(self.lua.globals().LOADS, 1)
        self.lua.execute("NAME_READY=true")
        self.a.Dispatch("SPELL_DATA_LOAD_RESULT", 999, True)
        self.assertEqual(self.a.Training.SpellInfo(999).name, "Loaded")

    def test_pet_and_price_state_do_not_leak_to_another_character(self):
        state = self.a.Training.State()
        state.petKnown[80] = True
        self.lua.execute("UnitGUID=function() return 'Player-OTHER' end")
        self.assertIsNone(self.a.Training.State().petKnown[80])

    def test_navigation_filters_faction_before_same_continent_distance(self):
        self.catalog("{}")
        self.lua.execute("""
          Evertally.trainingData.trainers={
            {kind='DRUID',faction='Horde',npcId=1,map=2,x=.1,y=.1,name='Enemy'},
            {kind='DRUID',faction='Alliance',npcId=2,map=2,x=.1,y=.1,name='Wrong continent'},
            {kind='DRUID',faction='Both',npcId=3,map=1,x=.8,y=.8,name='Friendly'}}
          Evertally.map={NearestLayerSpot=function(spots)
            FILTERED=#spots;for _,s in ipairs(spots)do if s.map==1 then return s end end end}
          Evertally.NavigateToPoint=function(name,map,x,y,source) NAV={name,map,x,y,source};return true end
        """)
        self.assertTrue(self.a.Training.Navigate())
        self.assertEqual(self.lua.globals().FILTERED, 2)
        self.assertEqual(self.lua.globals().NAV[1], "Friendly")
        self.assertEqual(self.lua.globals().NAV[5].view, "training")

    def test_navigation_refuses_unavailable_map_or_no_matching_continent(self):
        self.lua.execute("Evertally.map=nil;Evertally.LoadGuide=function()return false end")
        result = self.a.Training.Navigate()
        self.assertEqual(result, (False, "map_unavailable"))
        self.lua.execute("Evertally.map={NearestLayerSpot=function()return nil end}")
        self.assertEqual(self.a.Training.Navigate(), (False, "no_trainer_here"))

    def test_ui_is_lazy_and_controls_filter_own_data(self):
        self.catalog("{{id=10,level=1,baseCost=10},{id=20,level=20,baseCost=100}}")
        self.lua.execute(MOCK_UI_LUA)
        page = self.lua.globals().CreateFrame("Frame", None, self.lua.globals().UIParent)
        self.a.BuildTrainingPage(page, self.a.UIKit())
        self.assertEqual(self.lua.globals().BOOKCHECKS, 0)
        page.Refresh()
        self.assertEqual(page.selected.id, 10)
        page.filters.later.scripts.OnClick()
        self.assertEqual(page.selected.id, 20)
        page.known.scripts.OnClick()
        self.assertTrue(page.showKnown)
        self.assertEqual(len(page.filters), 0)  # dictionary keys, not an array
        self.assertIn("20", page.document.spec.title)


if __name__ == "__main__":
    unittest.main()
