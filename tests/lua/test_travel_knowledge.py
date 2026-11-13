"""Only confirmed flight-master states become per-character learned nodes."""
import unittest
from test_addon import runtime, MOCK_UI_LUA
from test_terrain import load


class TravelKnowledgeTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.m = self.lua.table()
        for name in ("Data.lua", "Planner.lua", "TravelKnowledge.lua"):
            load(self.lua, self.m, name)
        self.k = self.m.TravelKnowledge
        self.lua.execute('''
          GetTaxiMapID=function() return 1463 end
          Enum={FlightPathState={Current=0,Reachable=1,Unreachable=2}}
          C_TaxiMap={GetTaxiNodesForMap=function() error("generic list is not proof") end,
            GetAllTaxiNodes=function() return {
              {nodeID=2,state=0},{nodeID=4,state=1},{nodeID=5,state=2},
              {nodeID=6}, {nodeID=7,state=3}} end}
        ''')

    def test_generic_map_listing_and_unopened_flight_master_do_not_unlock_anything(self):
        self.assertFalse(self.k.Refresh())
        self.assertEqual(len(list(self.k.Options()[0].keys())), 0)

    def test_current_and_reachable_states_are_confirmed_but_not_unreachable_or_unknown(self):
        self.k.open = True
        self.assertTrue(self.k.Refresh())
        known, revision = self.k.Options()
        self.assertEqual(sorted(known.keys()), [2, 4])
        self.assertFalse(self.k.Refresh())
        self.assertEqual(self.k.Options()[1], revision, "repeated polling does not invalidate routes")

    def test_character_and_realm_changes_never_reuse_someone_elses_unlocks(self):
        self.k.open = True
        self.k.Refresh()
        self.lua.execute('UnitGUID=function() return "Player-other" end')
        self.assertEqual(len(list(self.k.Options()[0].keys())), 0)
        self.lua.execute('UnitGUID=function() return "Player-TEST-own" end; UnitFullName=function() return "Fixture Hero","Different Realm" end')
        self.assertEqual(len(list(self.k.Options()[0].keys())), 0)

    def test_options_are_copies_and_confirmed_data_survives_missing_api(self):
        self.k.open = True
        self.k.Refresh()
        known, _ = self.k.Options()
        known[5] = True
        self.lua.execute("C_TaxiMap=nil")
        self.k.Refresh()
        self.assertEqual(sorted(self.k.Options()[0].keys()), [2, 4])

    def test_no_current_flight_master_means_the_snapshot_is_not_trusted(self):
        self.k.open = True
        self.lua.execute('C_TaxiMap.GetAllTaxiNodes=function() return {{nodeID=2,state=1},{nodeID=4,state=1}} end')
        self.assertFalse(self.k.Refresh())
        self.assertEqual(list(self.k.Options()[0].keys()), [])

    def test_legacy_menu_slot_is_not_treated_as_a_taxi_node_id(self):
        self.lua.execute('''
          C_TaxiMap=nil;NumTaxiNodes=function() return 2 end
          TaxiNodeGetType=function(i) return i==1 and "CURRENT" or "UNREACHABLE" end
          TaxiNodeName=function(i) return i==1 and "Rut'theran Village, Teldrassil" or "Stormwind, Elwynn" end
        ''')
        self.k.open = True
        self.k.Refresh()
        ids = list(self.k.Options()[0].keys())
        expected = [int(str(key)[4:]) for key, hub in self.m.data.hubs.items() if str(key).startswith("taxi") and hub[6] == "Rut'theran Village, Teldrassil"]
        self.assertEqual(ids, expected)
        self.assertNotEqual(ids, [1])


if __name__ == "__main__":
    unittest.main()
