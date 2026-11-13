"""Map marker ownership: Evertally adds only positions not already painted by the game."""
import unittest

from test_addon import MOCK_UI_LUA, runtime
from test_navigation import FAKE_LIBS, MAP_DIR


class PlayerPinOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE_LIBS)
        self.lua.execute('''
          PEERS={};Evertally.LivePeers=function() return PEERS end
          C_Map={GetBestMapForUnit=function() return 1429 end,
            GetPlayerMapPosition=function() return {x=.3,y=.4} end,
            GetMapInfo=function() return {name="Elwynn"} end}
        ''')
        self.m = self.lua.table()
        self.m.DistanceTo = self.lua.eval("function() return 10 end")
        self.m.NavPins = self.lua.eval("function() return {} end")
        fn = self.lua.eval("loadstring")((MAP_DIR / "Pins.lua").read_text(encoding="utf-8"), "Pins.lua")
        fn("Evertally_Map", self.m)

    def peer(self, name="Bran", full="Bran-Fixture Realm", guid=None):
        self.lua.globals().PEERS[1] = self.lua.table_from({
            "name": name, "full": full, "guid": guid, "map": 1429,
            "x": .3, "y": .4, "class": 3, "at": 1794236400,
        })

    def titles(self, surface):
        return {p.title for _, p in self.lua.eval("PINS")(surface).items()}

    def native_group(self):
        self.lua.execute('''
          GetNumGroupMembers=function() return 2 end
          UnitFullName=function(unit)
            if unit=="party1" then return "Bran","Fixture Realm" end
            return "Fixture Hero","Fixture Realm"
          end
          UnitGUID=function(unit) return unit=="party1" and "Player-bran" or "Player-TEST-own" end
          MOD={db={group=true},ToWorld=function(map,x,y) return x,y end}
          OpenMap={GetModule=function(_,name) if name=="worldmap" then return MOD end end}
          OpenMapAPI={IsStitched=function() return true end}
        ''')

    def test_numeric_party_and_raid_indices_leave_native_minimap_blips_alone(self):
        for function in ("UnitInParty", "UnitInRaid"):
            with self.subTest(function=function):
                self.lua.execute("UnitInParty=nil;UnitInRaid=nil")
                self.lua.globals()[function] = self.lua.eval('function(name) if name=="Bran-Fixture Realm" then return 2 end end')
                self.peer()
                self.m.Refresh()
                self.assertEqual(self.titles("mini"), set())
                self.assertEqual(self.titles("world"), {"Bran"}, "without a known native world marker, retain the beacon")

    def test_false_zero_secret_and_missing_group_results_keep_a_peer_pin(self):
        for result in ("false", "0", "SECRET", "nil"):
            with self.subTest(result=result):
                self.lua.execute(f"UnitInParty=function() return {result} end")
                self.peer()
                self.m.Refresh()
                self.assertEqual(self.titles("mini"), {"Bran"})

    def test_roster_identity_works_without_unit_in_party_name_lookup(self):
        self.native_group()
        self.peer()
        self.m.Refresh()
        self.assertEqual(self.titles("mini"), set())
        self.assertEqual(self.titles("world"), set())

    def test_own_player_marker_is_never_duplicated_even_if_a_self_beacon_reaches_pins(self):
        self.peer(name="Fixture Hero", full="Fixture Hero-Fixture Realm")
        self.m.Refresh()
        self.assertEqual(self.titles("mini"), set())
        self.assertEqual(self.titles("world"), set())

    def test_guid_identity_is_authoritative(self):
        self.peer(name="Different spelling", full="Different spelling-Other", guid="Player-TEST-own")
        self.m.Refresh()
        self.assertEqual(self.titles("world"), set())
        self.peer(name="Fixture Hero", full="Fixture Hero-Fixture Realm", guid="Player-other")
        self.m.Refresh()
        self.assertEqual(self.titles("world"), {"Fixture Hero"})

    def test_same_name_on_another_realm_is_not_removed_as_self_or_group(self):
        self.native_group()
        self.lua.execute('UnitInParty=function(name) if name=="Bran" then return 1 end end')
        self.peer(name="Bran", full="Bran-Other Realm")
        self.m.Refresh()
        self.assertEqual(self.titles("world"), {"Bran"})
        self.assertEqual(self.titles("mini"), {"Bran"})
        self.peer(name="Fixture Hero", full="Fixture Hero-Other Realm")
        self.m.Refresh()
        self.assertEqual(self.titles("world"), {"Fixture Hero"})

    def test_openmap_disabled_group_layer_keeps_precise_evertally_beacon(self):
        self.native_group()
        self.lua.execute("MOD.db.group=false")
        self.peer()
        self.m.Refresh()
        self.assertEqual(self.titles("world"), {"Bran"})

    def test_openmap_without_precise_native_position_keeps_live_beacon(self):
        self.native_group()
        self.peer()
        for result in ("nil", "{x=0,y=0}", "{x=SECRET,y=.4}"):
            with self.subTest(result=result):
                self.lua.execute(f"C_Map.GetPlayerMapPosition=function() return {result} end")
                self.m.Refresh()
                self.assertEqual(self.titles("world"), {"Bran"})

    def test_duplicate_is_removed_when_native_ownership_becomes_available(self):
        self.peer()
        self.m.Refresh()
        self.assertEqual(self.titles("world"), {"Bran"})
        self.assertEqual(self.titles("mini"), {"Bran"})
        self.native_group()
        self.m.Refresh()
        self.assertEqual(self.titles("world"), set())
        self.assertEqual(self.titles("mini"), set())
        self.lua.execute("MOD.db.group=false")
        self.m.Refresh()
        self.assertEqual(self.titles("world"), {"Bran"})

    def test_navigation_bend_and_nearby_waypoint_do_not_mimic_an_extra_player(self):
        self.lua.execute('''
          Evertally.map=Evertally.map or {}
          NEAR=4
        ''')
        self.m.NavPins = self.lua.eval('function() return {{id="terrain",map=1429,x=.3,y=.4,title="Bend"},{id="next",map=1429,x=.3,y=.4,title="Next"},{id="goal",map=1429,x=.3,y=.4,title="Goal"}} end')
        self.m.DistanceTo = self.lua.eval('function() return NEAR end')
        self.m.Refresh()
        self.assertEqual(self.titles("world"), {"Goal"})
        self.assertEqual(self.titles("mini"), {"Goal"})
        self.lua.globals().NEAR = 9
        self.m.Refresh()
        self.assertEqual(self.titles("world"), {"Next", "Goal"})
        self.lua.globals().NEAR = None
        self.m.Refresh()
        self.assertEqual(self.titles("mini"), {"Next", "Goal"})

    def test_blizzard_map_owns_only_group_positions_on_its_current_zone_or_parent(self):
        self.lua.execute('''
          UnitInParty=function() return 1 end
          WorldMapFrame={GetMapID=function() return HOST end}
          C_Map.GetMapInfo=function(id) return {parentMapID=id==1429 and 1415 or 0} end
        ''')
        self.peer()
        for host, expected in ((1429, set()), (1415, set()), (1436, {"Bran"}), (947, {"Bran"})):
            with self.subTest(host=host):
                self.lua.globals().HOST = host
                self.m.Refresh()
                self.assertEqual(self.titles("world"), expected)


if __name__ == "__main__":
    unittest.main()
