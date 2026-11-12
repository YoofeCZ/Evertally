"""Lua replay checks for live position, pings, the map add-on (pins) and navigation. No game, no user data."""
from pathlib import Path
import json
import math
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, ROOT, runtime  # noqa: E402

MAP_DIR = ROOT / "addon" / "Evertally_Map"
MAP_FILES = ["Data.lua", "Planner.lua", "Navigator.lua", "WorldPage.lua", "WorldDb.lua", "GuideKit.lua", "WorldDbPage.lua", "WorldPlan.lua", "MapLayers.lua", "MapPanel.lua", "Pins.lua"]  # the order of Evertally_Map.toc after the libraries
JOURNEYS = json.loads((ROOT / "tests" / "lua" / "fixtures" / "journeys.json").read_text(encoding="utf-8"))
ELWYNN, WESTFALL, STORMWIND, DUROTAR = 1429, 1436, 1453, 1411

FAKE_LIBS = """
PINLOG={world={},mini={},allWorld=0,allMini=0}
FAKEPINS={
  AddWorldMapIconMap=function(self,ref,icon,map,x,y,flag) PINLOG.world[icon]={ref=ref,map=map,x=x,y=y,flag=flag,spec=icon.spec} end,
  AddMinimapIconMap=function(self,ref,icon,map,x,y,parent,edge) PINLOG.mini[icon]={ref=ref,map=map,x=x,y=y,edge=edge,spec=icon.spec} end,
  RemoveWorldMapIcon=function(self,ref,icon) PINLOG.world[icon]=nil end,
  RemoveMinimapIcon=function(self,ref,icon) PINLOG.mini[icon]=nil end,
  RemoveAllWorldMapIcons=function(self,ref) for icon,e in pairs(PINLOG.world) do if e.ref==ref then PINLOG.world[icon]=nil end end PINLOG.allWorld=PINLOG.allWorld+1 end,
  RemoveAllMinimapIcons=function(self,ref) PINLOG.mini={};PINLOG.allMini=PINLOG.allMini+1 end,
}
LibStub=function(name,silent) if name=="HereBeDragons-Pins-2.0" then return FAKEPINS end if silent then return nil end error("missing "..name) end
function PINS(which)
  local out={}
  for icon,v in pairs(which=="world" and PINLOG.world or PINLOG.mini) do out[#out+1]={title=v.spec.title,map=v.map,x=v.x,y=v.y,edge=v.edge,flag=v.flag,icon=v.spec.icon} end
  table.sort(out,function(a,b) return a.title<b.title end)
  return out
end
"""

RECORD_ROTATION = """
local base=object
function object(parent)
  local t=base(parent);local mt=getmetatable(t);local old=mt.__index
  mt.__index=function(self,k) if k=="SetRotation" then return function(s,v) s.rotation=v end end return old(self,k) end
  return t
end
"""


def ok(result):
    return result[0] if isinstance(result, tuple) else bool(result)


def lst(table):
    return [table[i] for i in range(1, len(table) + 1)] if table is not None else []


class MapTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(RECORD_ROTATION)
        self.lua.execute(FAKE_LIBS)
        self.lua.execute("""
        SENT={}
        C_ChatInfo={RegisterAddonMessagePrefix=function() return true end,SendAddonMessage=function(prefix,text,channel,target) SENT[#SENT+1]={prefix=prefix,text=text,channel=channel,target=target} return 0 end}
        MAPID=1429;MX=0.4234;MY=0.6512;FACING=0
        C_Map={GetBestMapForUnit=function() return MAPID end,GetPlayerMapPosition=function() if MX then return {GetXY=function() return MX,MY end} end end,
               GetMapInfo=function(id) return {name="Zone "..id} end}
        GetPlayerFacing=function() return FACING end
        UnitFactionGroup=function() return "Alliance" end
        IsMounted=function() return false end
        """)
        self.lua.globals().PYLOAD = self.load_map_files

    # ---- helpers ----
    def load_map_files(self):
        M = self.lua.table()
        for name in MAP_FILES:
            fn = self.lua.eval("loadstring")((MAP_DIR / name).read_text(encoding="utf-8"), name)
            if isinstance(fn, tuple):
                raise AssertionError(f"{name}: {fn}")
            fn("Evertally_Map", M)
        return True

    def enable(self):
        self.a.db.settings.mapPins = True
        self.load_map_files()
        return self.a.map

    def beacon(self, sender, map_id, x, y, cls=8, channel="GUILD", advance=3):
        self.lua.globals().CLOCK += advance
        self.a.ReceiveMessage("Evtly1", "S|L|%d|%d|%d|%d" % (map_id, round(x * 1000), round(y * 1000), cls), channel, sender)

    def pump(self, times=6):
        for _ in range(times):
            self.lua.globals().CLOCK += 1.1
            self.a.PumpSync()

    def sent(self, prefix=""):
        sent = self.lua.globals().SENT
        out = [sent[i] for i in range(1, len(sent) + 1) if sent[i].text.startswith(prefix)]
        self.lua.execute("SENT={}")
        return out

    def stand(self, map_id, x, y, facing=0):
        g = self.lua.globals()
        g.MAPID, g.MX, g.MY, g.FACING = map_id, x, y, facing

    # ================================================================ the planner
    def test_lua_planner_gives_the_same_journeys_as_the_website(self):
        # the planner is loaded on its own: Pins.lua needs the add-on environment, the planner does not
        table = self.lua.table()
        for name in ("Data.lua", "Planner.lua"):
            self.lua.eval("loadstring")((MAP_DIR / name).read_text(encoding="utf-8"), name)("Evertally_Map", table)
        different = []
        for i, case in enumerate(JOURNEYS):
            journey = table.PlanJourney(self.lua.table(u=case["from"][1], v=case["from"][2], label=case["from"][0]), self.lua.table(u=case["to"][1], v=case["to"][2], label=case["to"][0]),
                                        self.lua.table(side=case["side"], speed=case["speed"]))
            if case["seconds"] is None:
                if journey is not None:
                    different.append((i, "expected no route"))
                continue
            if journey is None:
                different.append((i, "no route"))
                continue
            steps = [[s.mode, s["from"], s.to] for s in lst(journey.steps)]
            if abs(journey.seconds - case["seconds"]) > 0.01 or steps != [x[:3] for x in case["steps"]]:
                different.append((i, case["from"][0], case["to"][0], journey.seconds, case["seconds"]))
        self.assertEqual(different[:5], [])
        self.assertGreater(len(JOURNEYS), 1000)

    def test_positions_survive_the_trip_through_azeroths_map(self):
        M = self.enable()
        for map_id, x, y in ((ELWYNN, 0.4234, 0.6512), (WESTFALL, 0.5, 0.5), (STORMWIND, 0.2, 0.8), (DUROTAR, 0.9, 0.1)):
            u, v = M.ToUV(map_id, x, y)
            found, fx, fy = M.Locate(u, v)
            self.assertEqual(found, map_id)
            self.assertAlmostEqual(fx, x, places=6)
            self.assertAlmostEqual(fy, y, places=6)
        self.assertIsNone(M.ToUV(999999, 0.5, 0.5))
        self.assertIsNone(M.Locate(-1, -1))

    def test_arrow_follows_the_game_convention_north_zero_west_positive(self):
        M = self.enable()
        c = 0
        self.assertEqual(M.Bearing(c, 0, 0, 1, 5, 5), None)  # another continent: no direction
        north, west, east = M.Bearing(c, 0, 0, c, 100, 0), M.Bearing(c, 0, 0, c, 0, 100), M.Bearing(c, 0, 0, c, 0, -100)
        self.assertAlmostEqual(north[0], 0)
        self.assertAlmostEqual(west[0], math.pi / 2)
        self.assertAlmostEqual(east[0], -math.pi / 2)
        self.assertAlmostEqual(M.Bearing(c, 0, 0, c, 30, 40)[1], 50)
        # facing west, a target in the north is on the right: -90 degrees
        self.assertAlmostEqual(M.Normalize(north[0] - math.pi / 2), -math.pi / 2)
        self.assertAlmostEqual(M.Normalize(3 * math.pi), math.pi)

    # ================================================================ live position
    def test_live_position_is_off_by_default_and_sends_nothing(self):
        self.lua.execute("IsInGuild=function() return true end")
        self.a.LiveTick()
        self.pump()
        self.assertEqual(self.sent("S|L"), [])
        self.assertFalse(self.a.LiveActive())

    def test_beacons_go_to_the_chosen_channel_when_you_move_and_replace_each_other(self):
        self.lua.execute("IsInGuild=function() return true end;IsInGroup=function() return true end")
        self.a.SetLive("guild", True)
        self.a.LiveTick()
        self.stand(ELWYNN, 0.45, 0.65)
        self.lua.globals().CLOCK += 6
        self.a.LiveTick()
        self.stand(ELWYNN, 0.47, 0.66)
        self.lua.globals().CLOCK += 6
        self.a.LiveTick()  # nothing was pumped in between: only the newest beacon is still waiting
        self.pump()
        beacons = self.sent("S|L")
        self.assertEqual(len(beacons), 1)
        self.assertEqual(beacons[0].channel, "GUILD")
        self.assertTrue(beacons[0].text.startswith("S|L|1429|470|660|"))
        self.assertIsNone(beacons[0].target)

    def test_standing_still_sends_a_heartbeat_not_a_stream(self):
        self.lua.execute("IsInGuild=function() return true end")
        self.a.SetLive("guild", True)
        self.a.LiveTick(); self.pump(); self.assertEqual(len(self.sent("S|L")), 1)
        for _ in range(3):
            self.lua.globals().CLOCK += 6
            self.a.LiveTick()
        self.pump(); self.assertEqual(self.sent("S|L"), [])
        self.lua.globals().CLOCK += 31
        self.a.LiveTick(); self.pump()
        self.assertEqual(len(self.sent("S|L")), 1)

    def test_party_beacons_use_raid_when_in_a_raid_and_nothing_without_a_group(self):
        self.a.SetLive("party", True)
        self.a.LiveTick(); self.pump(); self.assertEqual(self.sent("S|L"), [])  # not in a group
        self.lua.execute("IsInGroup=function() return true end;IsInRaid=function() return true end")
        self.a.LiveTick(); self.pump()
        self.assertEqual([m.channel for m in self.sent("S|L")], ["RAID"])

    def test_no_beacon_where_there_is_no_map_position(self):
        self.lua.execute("IsInGuild=function() return true end")
        self.a.SetLive("guild", True)
        self.lua.execute("MX=nil")
        self.a.LiveTick(); self.pump()
        self.assertEqual(self.sent("S|L"), [])

    def test_turning_it_off_tells_the_others_at_once(self):
        self.lua.execute("IsInGuild=function() return true end")
        self.a.SetLive("guild", True)
        self.a.LiveTick(); self.pump(); self.sent()
        self.a.SetLive("guild", False)
        self.pump()
        self.assertEqual([(m.text, m.channel) for m in self.sent("S|")], [("S|E", "GUILD")])
        self.a.LiveTick(); self.pump()
        self.assertEqual(self.sent("S|L"), [])
        self.assertFalse(self.a.LiveActive())

    def test_received_beacons_become_peers_with_validation_and_a_flood_limit(self):
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.42, 0.65, cls=3)
        peer = self.a.LivePeer("bran")
        self.assertEqual((peer.name, peer.map, peer.x, peer.y, peer["class"], peer.channel), ("Bran", ELWYNN, 0.42, 0.65, 3, "GUILD"))
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.9, 0.9, advance=0.5)  # too soon after the last one
        self.assertEqual(self.a.LivePeer("Bran").x, 0.42)
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.5, 0.5)
        self.assertEqual(self.a.LivePeer("Bran").x, 0.5)
        for bad in ("S|L|0|10|10|1", "S|L|1429|2000|10|1", "S|L|1429|10|-5|1", "S|L|abc|1|1|1", "S|L|1429|10", "S|L"):
            self.a.ReceiveMessage("Evtly1", bad, "GUILD", "Eve-Fixture Realm")
        self.assertIsNone(self.a.LivePeer("Eve"))
        self.lua.globals().CLOCK += 5
        self.a.ReceiveMessage("Evtly1", "S|L|1429|10|10|1", "WHISPER", "Eve-Fixture Realm")  # only group and guild channels count
        self.a.ReceiveMessage("Evtly1", "S|L|1429|10|10|1", "SAY", "Eve-Fixture Realm")
        self.assertIsNone(self.a.LivePeer("Eve"))
        self.a.ReceiveMessage("Evtly1", "S|L|1429|10|10|1", "GUILD", "Fixture Hero-Fixture Realm")  # yourself
        self.assertIsNone(self.a.LivePeer("Fixture"))

    def test_peers_expire_and_an_end_message_removes_them(self):
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.42, 0.65)
        self.beacon("Ilyra-Fixture Realm", ELWYNN, 0.3, 0.3, channel="PARTY")
        self.assertEqual([p.name for p in lst(self.a.LivePeers())], ["Bran", "Ilyra"])
        self.a.ReceiveMessage("Evtly1", "S|E", "PARTY", "Bran-Fixture Realm")  # Bran shares on the guild channel, not this one
        self.assertIsNotNone(self.a.LivePeer("Bran"))
        self.a.ReceiveMessage("Evtly1", "S|E", "GUILD", "Bran-Fixture Realm")
        self.assertIsNone(self.a.LivePeer("Bran"))
        self.lua.globals().NOW += 121
        self.assertEqual(lst(self.a.LivePeers()), [])

    def test_name_lookup_needs_an_unambiguous_start(self):
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.4, 0.4)
        self.beacon("Branka-Fixture Realm", ELWYNN, 0.5, 0.5)
        self.assertEqual(self.a.LivePeer("Bran").name, "Bran")  # exact wins
        self.assertIsNone(self.a.LivePeer("Bra"))  # two candidates
        self.assertEqual(self.a.LivePeer("branka").name, "Branka")

    # ================================================================ pings
    def test_ping_goes_to_the_group_then_the_guild_and_is_shown_to_the_sender_too(self):
        self.assertEqual(tuple(self.a.SendPing("hello")), (False, "no_channel"))
        self.lua.execute("IsInGuild=function() return true end")
        ok = self.a.SendPing("Boss |cffff0000here|r")
        self.assertTrue(ok)
        self.pump()
        message = self.sent("S|P")[0]
        self.assertEqual(message.channel, "GUILD")
        self.assertRegex(message.text, r"^S\|P\|[0-9a-f]{6}\|1429\|423\|651\|Boss")
        label = message.text.split("|", 6)[6]
        self.assertNotIn("|", label)  # no colour or link escape can be built from what travels
        mine = lst(self.a.LivePings())[0]
        self.assertTrue(mine.mine)
        self.lua.execute("IsInGroup=function() return true end")
        self.a.SendPing("again"); self.pump()
        self.assertEqual(self.sent("S|P")[0].channel, "PARTY")

    def test_ping_without_a_map_position_and_at_a_chosen_point(self):
        self.lua.execute("IsInGuild=function() return true end;MX=nil")
        self.assertEqual(tuple(self.a.SendPing("x")), (False, "no_position"))
        self.assertTrue(self.a.SendPing("there", WESTFALL, 0.25, 0.75))
        self.pump()
        self.assertRegex(self.sent("S|P")[0].text, r"\|1436\|250\|750\|there$")

    def test_received_pings_are_validated_limited_and_expire(self):
        def ping(sender, id_, map_id=ELWYNN, x=400, y=500, label="here", channel="GUILD", advance=6):
            self.lua.globals().CLOCK += advance
            self.a.ReceiveMessage("Evtly1", "S|P|%s|%d|%d|%d|%s" % (id_, map_id, x, y, label), channel, sender)
        ping("Bran-Fixture Realm", "abcdef")
        self.assertEqual([(g.name, g.map, g.x, g.y, g.label) for g in lst(self.a.LivePings())], [("Bran", ELWYNN, 0.4, 0.5, "here")])
        ping("Bran-Fixture Realm", "abcde1", advance=1)  # same sender, too soon
        self.assertEqual(len(lst(self.a.LivePings())), 1)
        for bad in (("Eve-Fixture Realm", "zzzzzz"), ("Eve-Fixture Realm", "abc"), ("Eve-Fixture Realm", "abcdef", 0), ("Eve-Fixture Realm", "abcdef", ELWYNN, 5000)):
            ping(*bad)
        ping("Eve-Fixture Realm", "abcdef", channel="WHISPER")
        self.assertEqual(len(lst(self.a.LivePings())), 1)
        for i in range(30):
            ping("Peer%d-Fixture Realm" % i, "%06x" % i, advance=0)
        self.assertLessEqual(len(lst(self.a.LivePings())), 20)
        self.lua.globals().NOW += 301
        self.assertEqual(lst(self.a.LivePings()), [])

    def test_ping_key_binding_uses_the_map_cursor_when_the_map_is_open(self):
        self.lua.execute("IsInGuild=function() return true end")
        self.lua.execute("WorldMapFrame={IsShown=function() return true end,GetNormalizedCursorPosition=function() return 0.5,0.25 end,GetMapID=function() return 1436 end}")
        self.lua.execute("Evertally_Ping()")
        self.pump()
        self.assertRegex(self.sent("S|P")[0].text, r"\|1436\|500\|250\|$")
        self.lua.execute("WorldMapFrame.GetNormalizedCursorPosition=function() return 2,2 end")  # the cursor is off the map: use my position
        self.lua.execute("Evertally_Ping()")
        self.pump()
        self.assertRegex(self.sent("S|P")[0].text, r"\|1429\|423\|651\|$")

    # ================================================================ loading the map add-on
    def test_the_map_add_on_is_not_loaded_unless_switched_on(self):
        self.lua.execute("""LOADS=0;C_AddOns={LoadAddOn=function(name) LOADS=LOADS+1;return PYLOAD() end};C_Timer={After=function(s,fn) fn() end}""")
        self.assertEqual(tuple(self.a.LoadMap()), (False, "disabled"))
        self.a.Dispatch("PLAYER_LOGIN")
        self.assertEqual(self.lua.globals().LOADS, 0)
        self.assertIsNone(self.a.map)

    def test_switching_it_on_loads_it_once_and_off_removes_the_pins(self):
        self.lua.execute("""LOADS=0;C_AddOns={LoadAddOn=function(name) LOADS=LOADS+1;return PYLOAD() end}""")
        self.a.SetMapPins(True)
        self.assertEqual(self.lua.globals().LOADS, 1)
        self.assertIsNotNone(self.a.map)
        self.a.SetMapPins(True)
        self.assertEqual(self.lua.globals().LOADS, 1)
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.42, 0.65)
        self.a.map.Refresh()
        self.assertEqual(len(lst(self.lua.eval("PINS")("world"))), 1)
        self.a.SetMapPins(False)
        self.assertEqual(len(lst(self.lua.eval("PINS")("world"))), 0)
        # the people's icons and the layers' icons are removed together: two world map sets, one minimap set
        self.assertEqual((self.lua.globals().PINLOG.allWorld, self.lua.globals().PINLOG.allMini), (2, 1))
        self.assertFalse(self.a.db.settings.mapPins)

    def test_a_failing_load_is_reported_and_does_not_break_the_addon(self):
        self.lua.execute("""C_AddOns={LoadAddOn=function(name) return nil,"MISSING" end}""")
        self.a.SetMapPins(True)
        self.assertIsNone(self.a.map)
        self.assertEqual(self.a.errors.map_load, 1)
        self.lua.execute("""C_AddOns={LoadAddOn=function(name) error("boom") end}""")
        self.assertEqual(self.a.LoadMap()[0], False)
        self.assertEqual(self.a.errors.map_load, 2)
        self.assertFalse(self.a.NavigateByName("Bran")[0])

    def test_login_loads_the_map_add_on_when_it_was_on(self):
        self.lua.execute("""LOADS=0;C_AddOns={LoadAddOn=function(name) LOADS=LOADS+1;return PYLOAD() end};C_Timer={After=function(s,fn) fn() end}""")
        self.a.db.settings.mapPins = True
        self.a.Dispatch("PLAYER_LOGIN")
        self.assertEqual(self.lua.globals().LOADS, 1)

    # ================================================================ pins
    def test_pins_for_people_meets_and_pings_with_the_right_places(self):
        self.enable()
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.42, 0.65, cls=3)
        self.a.ReceiveMessage("Evtly1", "S|M|abcdef|%d|300|400|30|Hostinec" % WESTFALL, "PARTY", "Ilyra-Fixture Realm")
        self.lua.globals().CLOCK += 6
        self.a.ReceiveMessage("Evtly1", "S|P|abcde1|%d|600|700|Boss" % ELWYNN, "GUILD", "Bran-Fixture Realm")
        self.a.map.Refresh()
        world = {p.title: p for p in lst(self.lua.eval("PINS")("world"))}
        self.assertEqual(set(world), {"Bran", "Hostinec", "Boss"})
        self.assertEqual((world["Bran"].map, world["Bran"].x, world["Bran"].y), (ELWYNN, 0.42, 0.65))
        self.assertEqual((world["Hostinec"].map, world["Hostinec"].x, world["Hostinec"].y), (WESTFALL, 0.3, 0.4))
        self.assertEqual((world["Boss"].map, world["Boss"].icon), (ELWYNN, "ping"))
        mini = {p.title: p for p in lst(self.lua.eval("PINS")("mini"))}
        self.assertFalse(mini["Bran"].edge)  # people stay where they are
        self.assertTrue(mini["Hostinec"].edge)  # a meet or a ping floats on the edge of the minimap so you can see the direction
        self.assertTrue(mini["Boss"].edge)

    def test_people_of_your_own_group_are_left_off_the_minimap_because_the_game_draws_them(self):
        self.enable()
        self.lua.execute('UnitInParty=function(name) return name=="Ilyra" end')
        self.beacon("Ilyra-Fixture Realm", ELWYNN, 0.3, 0.3, channel="PARTY")
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.4, 0.4)
        self.a.map.Refresh()
        self.assertEqual({p.title for p in lst(self.lua.eval("PINS")("world"))}, {"Ilyra", "Bran"})
        self.assertEqual({p.title for p in lst(self.lua.eval("PINS")("mini"))}, {"Bran"})

    def test_pins_disappear_when_the_data_expires_and_follow_a_moving_person(self):
        self.enable()
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.42, 0.65)
        self.a.map.Refresh()
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.5, 0.6)
        self.a.map.Refresh()
        pins = lst(self.lua.eval("PINS")("world"))
        self.assertEqual((len(pins), pins[0].x, pins[0].y), (1, 0.5, 0.6))
        self.lua.globals().NOW += 121
        self.a.map.Refresh()
        self.assertEqual(lst(self.lua.eval("PINS")("world")), [])
        self.assertEqual(lst(self.lua.eval("PINS")("mini")), [])

    def test_an_old_meet_is_not_pinned(self):
        self.enable()
        self.a.ReceiveMessage("Evtly1", "S|M|abcdef|%d|300|400|0|Old" % ELWYNN, "PARTY", "Ilyra-Fixture Realm")
        self.a.map.Refresh()
        self.assertEqual(len(lst(self.lua.eval("PINS")("world"))), 1)
        self.lua.globals().NOW += 7300
        self.a.map.Refresh()
        self.assertEqual(lst(self.lua.eval("PINS")("world")), [])

    # ================================================================ navigation
    def tracker(self):
        return self.lua.globals().EvertallyTracker

    def test_navigation_needs_the_map_switched_on_and_a_known_target(self):
        self.assertEqual(tuple(self.a.NavigateByName("Bran")), (False, "map_off"))
        self.a.db.settings.mapPins = True
        self.lua.execute("C_AddOns={LoadAddOn=function() return PYLOAD() end}")
        self.assertEqual(tuple(self.a.NavigateByName("Bran")), (False, "unknown_player"))
        self.assertEqual(tuple(self.a.NavigateByName("meet")), (False, "no_meet"))
        self.assertEqual(tuple(self.a.NavigateByName("ping")), (False, "no_ping"))
        self.assertEqual(tuple(self.a.NavigateByName("")), (False, "no_target"))

    def test_arrow_points_east_and_the_text_gives_the_distance(self):
        self.enable()
        self.stand(ELWYNN, 0.40, 0.65, facing=0)
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.50, 0.65)
        self.assertTrue(ok(self.a.map.Navigate(self.lua.table(kind="player", name="Bran"))))
        tracker = self.tracker()
        self.assertTrue(tracker.IsShown(tracker))
        self.assertIn("Bran", tracker.title.text)
        self.assertRegex(tracker.line1.text, r"\d+ yd")
        self.assertAlmostEqual(tracker.arrow.rotation, -math.pi / 2, places=3)  # east is on the right
        self.stand(ELWYNN, 0.40, 0.65, facing=math.pi)  # now facing south: east is on the left
        self.a.map.nav.Update()
        self.assertAlmostEqual(tracker.arrow.rotation, math.pi / 2, places=3)

    def test_arrow_points_north_when_the_target_is_north_and_you_face_north(self):
        self.enable()
        self.stand(ELWYNN, 0.5, 0.7)
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.5, 0.5)
        self.a.map.Navigate(self.lua.table(kind="player", name="Bran"))
        self.assertAlmostEqual(self.tracker().arrow.rotation, 0, places=3)

    def test_the_arrow_is_green_facing_the_goal_orange_beside_it_and_red_with_the_goal_behind(self):
        self.enable()
        self.stand(ELWYNN, 0.5, 0.7, facing=0)
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.5, 0.5)   # north of you
        self.a.map.Navigate(self.lua.table(kind="player", name="Bran"))
        tracker = self.tracker()
        tracker.arrow.SetVertexColor = self.lua.eval("function(self, r, g, b) self.color = {r, g, b} end")   # (the plain mock keeps no colour)

        def colour(facing):
            self.stand(ELWYNN, 0.5, 0.7, facing=facing)
            self.a.map.nav.Update()
            return tuple(float(tracker.arrow.color[i]) for i in (1, 2, 3))
        ahead, beside, behind = colour(0), colour(math.pi / 2), colour(math.pi)
        self.assertGreater(ahead[1], 0.85); self.assertLess(ahead[0], 0.35)                 # green
        self.assertGreater(beside[0], 0.9); self.assertTrue(0.45 < beside[1] < 0.8)           # orange
        self.assertGreater(behind[0], 0.85); self.assertLess(behind[1], 0.3)                 # red
        self.assertRegex(str(tracker.distance.text), r"^\d+ yd$", "the distance under the arrow")

    def test_the_colour_goes_smoothly_from_green_through_orange_to_red(self):
        self.enable()
        arrow = self.a.map.ArrowColor
        greens = [float(arrow(angle)[1]) for angle in (0, 0.5, 1.0, 1.5, 2.0, 2.5, math.pi)]
        self.assertEqual(greens, sorted(greens, reverse=True), "the further round, the less green")
        self.assertEqual(tuple(round(float(x), 2) for x in arrow(0)), tuple(round(float(x), 2) for x in arrow(-0.1)), "straight ahead and a little off are both green")
        self.assertEqual(tuple(float(x) for x in arrow(math.pi)), tuple(float(x) for x in arrow(-math.pi)), "left and right are the same")

    def test_no_direction_without_facing_or_position(self):
        self.enable()
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.5, 0.5)
        self.a.map.Navigate(self.lua.table(kind="player", name="Bran"))
        self.lua.execute("GetPlayerFacing=function() return nil end")
        self.a.map.nav.Update()
        self.assertFalse(self.tracker().arrow.IsShown(self.tracker().arrow))  # without a facing there is no arrow, only the text
        self.lua.execute("MX=nil")  # on a ship, in an instance
        self.a.map.nav.Update()
        self.assertIn(self.a.L("navNoPosition"), self.tracker().hint.text)

    def test_a_trip_to_another_continent_is_a_journey_in_steps(self):
        self.enable()
        self.stand(ELWYNN, 0.5, 0.5)
        self.beacon("Grom-Fixture Realm", DUROTAR, 0.5, 0.5)
        self.a.map.Navigate(self.lua.table(kind="player", name="Grom"))
        plan = self.a.map.nav.plan
        modes = [s.mode for s in lst(plan.steps)]
        self.assertEqual(modes, ["walk", "flight", "walk", "boat", "walk"])  # the same journey the website plans for an Alliance player
        self.assertIn("Grom", self.tracker().title.text)
        self.assertRegex(self.tracker().line2.text, r"\d+:\d\d")  # the time of the whole journey
        pins = lst(self.a.map.NavPins())
        self.assertIn("goal", [p.id for p in pins])
        self.assertIn("next", [p.id for p in pins])

    def test_the_goal_pin_is_big_pulses_and_is_named_on_the_world_map(self):
        self.enable()
        self.stand(ELWYNN, 0.5, 0.5)
        self.assertTrue(ok(self.a.NavigateToPoint("Hostinec", WESTFALL, 0.25, 0.75)))
        self.a.map.Refresh()
        frames = lambda which: lst(self.lua.eval("(function() local o={} for f in pairs(PINLOG.%s) do o[#o+1]=f end return o end)()" % which))
        world = [f for f in frames("world") if f.spec.icon == "goal"]
        mini = [f for f in frames("mini") if f.spec.icon == "goal"]
        self.assertEqual((len(world), len(mini)), (1, 1))
        self.assertEqual((world[0].w, world[0].h, mini[0].w, mini[0].h), (30, 30, 26, 26), "bigger than the 18 / 14 px of the other pins")
        self.assertEqual(world[0].caption.text, "Hostinec", "the world map names the place")
        self.assertIsNone(mini[0].caption, "the minimap is too small for a caption")
        self.assertEqual(world[0].tex.texture, "Interface\\AddOns\\Evertally_Map\\Media\\goal")
        self.lua.execute("GetTime=function() return math.pi/8 end")
        world[0].scripts.OnUpdate(world[0])  # sin(pi/2) = 1: the top of the pulse
        self.assertAlmostEqual(world[0].w, 30 * 1.14, places=6)
        others = [f for f in frames("world") if f.spec.icon != "goal"]
        for f in others:
            self.assertIsNone(f.scripts.OnUpdate, "only the goal pulses")
            self.assertIsNone(f.caption)

    def test_a_moving_target_makes_the_plan_follow(self):
        self.enable()
        self.stand(ELWYNN, 0.5, 0.5)
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.55, 0.5)
        self.a.map.Navigate(self.lua.table(kind="player", name="Bran"))
        before = self.a.map.nav.planTo[1]
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.9, 0.9)
        self.a.map.nav.Update()
        self.assertNotEqual(self.a.map.nav.planTo[1], before)

    def test_losing_the_target_keeps_the_last_known_place_and_says_so(self):
        self.enable()
        self.stand(ELWYNN, 0.5, 0.5)
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.55, 0.5)
        self.a.map.Navigate(self.lua.table(kind="player", name="Bran"))
        self.lua.globals().NOW += 200
        self.a.map.nav.Update()
        self.assertTrue(self.tracker().title.text.startswith("? "))
        self.assertRegex(self.tracker().line1.text, r"yd|\d+:\d\d")

    def test_arriving_at_a_point_ends_navigation_after_a_moment(self):
        self.enable()
        self.stand(ELWYNN, 0.5, 0.5)
        self.assertTrue(ok(self.a.NavigateToPoint("Cil", ELWYNN, 0.5001, 0.5001)))
        self.assertEqual(self.tracker().line1.text, self.a.L("navArrived"))
        self.lua.globals().CLOCK += 20
        self.a.map.nav.Update()
        self.assertFalse(self.tracker().IsShown(self.tracker()))
        self.assertIsNone(self.a.map.nav.target)

    def test_stop_hides_the_tracker_and_removes_the_navigation_pins(self):
        self.enable()
        self.stand(ELWYNN, 0.5, 0.5)
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.7, 0.5)
        self.a.map.Navigate(self.lua.table(kind="player", name="Bran"))
        self.a.map.Refresh()
        self.assertIn("goal", [p.id for p in lst(self.a.map.NavPins())])
        self.a.StopNavigation()
        self.a.map.Refresh()
        self.assertFalse(self.tracker().IsShown(self.tracker()))
        self.assertEqual(lst(self.a.map.NavPins()), [])

    def test_navigate_by_keyword_to_the_newest_meet_and_ping(self):
        self.a.db.settings.mapPins = True
        self.lua.execute("C_AddOns={LoadAddOn=function() return PYLOAD() end}")
        self.stand(ELWYNN, 0.5, 0.5)
        self.a.ReceiveMessage("Evtly1", "S|M|abcdef|%d|700|500|0|Hostinec" % ELWYNN, "PARTY", "Ilyra-Fixture Realm")
        self.assertTrue(ok(self.a.NavigateByName("meet")))
        self.assertEqual(self.a.map.nav.target.label, "Hostinec")
        self.lua.globals().CLOCK += 6
        self.a.ReceiveMessage("Evtly1", "S|P|abcde1|%d|200|300|Boss" % ELWYNN, "GUILD", "Bran-Fixture Realm")
        self.a.NavigateByName("ping")
        self.assertEqual(self.a.map.nav.target.label, "Boss")

    def test_slash_commands_for_navigation_and_ping(self):
        self.a.db.settings.mapPins = True
        self.lua.execute("C_AddOns={LoadAddOn=function() return PYLOAD() end};IsInGuild=function() return true end")
        self.stand(ELWYNN, 0.5, 0.5)
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.6, 0.5)
        self.lua.execute('SlashCmdList.EVERTALLY("go bran")')
        self.assertEqual(self.a.map.nav.target.name, "Bran")
        self.lua.execute('SlashCmdList.EVERTALLY("stop")')
        self.assertIsNone(self.a.map.nav.target)
        self.lua.execute('SlashCmdList.EVERTALLY("ping Here we go")')
        self.pump()
        self.assertRegex(self.sent("S|P")[0].text, r"\|Here we go$")

    def test_debug_command_prints_both_the_addon_and_the_library_angle(self):
        self.enable()
        printed = []
        self.lua.globals().PRINTED = self.lua.table()
        self.lua.execute("""DEFAULT_CHAT_FRAME={AddMessage=function(self,text) PRINTED[#PRINTED+1]=text end}
        FAKEHBD={GetPlayerWorldPosition=function() return 100,100,0 end,GetWorldCoordinatesFromZone=function() return 200,100,0 end,GetWorldVector=function() return 1.57,100 end}
        local previous=LibStub
        LibStub=function(name,silent) if name=="HereBeDragons-2.0" then return FAKEHBD end return previous(name,silent) end""")
        self.stand(ELWYNN, 0.5, 0.5)
        self.beacon("Bran-Fixture Realm", ELWYNN, 0.6, 0.5)
        self.a.map.Navigate(self.lua.table(kind="player", name="Bran"))
        self.a.map.NavDebug()
        lines = [self.lua.globals().PRINTED[i] for i in range(1, len(self.lua.globals().PRINTED) + 1)]
        self.assertTrue(any("ours bearing" in line for line in lines), lines)
        self.assertTrue(any("HereBeDragons angle 1.570" in line for line in lines), lines)

    def test_terrain_handoff_is_explicit_and_preserves_target_coordinates(self):
        self.enable()
        self.assertEqual(tuple(self.a.map.NavigateTerrain()), (False, "missing"))
        self.lua.execute('ShortestPathForever={API={Navigate=function(owner,map,x,y,title) CAPTURE={owner,map,x,y,title};return true end}}')
        self.assertEqual(tuple(self.a.map.NavigateTerrain()), (False, "no_target"))
        self.assertTrue(ok(self.a.NavigateToPoint("Inn", WESTFALL, 0.25, 0.75)))
        self.assertTrue(self.a.map.NavigateTerrain())
        capture = self.lua.globals().CAPTURE
        self.assertEqual((capture[1], capture[2], capture[3], capture[4], capture[5]), ("Evertally", WESTFALL, 0.25, 0.75, "Inn"))
        self.lua.execute('ShortestPathForever.API.Navigate=function() return false end')
        self.assertEqual(tuple(self.a.map.NavigateTerrain()), (False, "refused"))

    def test_tracker_shows_the_terrain_button_only_while_shortest_path_is_installed(self):
        self.enable()
        self.assertTrue(ok(self.a.NavigateToPoint("Inn", WESTFALL, 0.25, 0.75)))
        tracker = self.lua.globals().EvertallyTracker
        self.assertFalse(tracker.terrain.shown, "no Shortest Path Forever, no button")
        self.lua.execute('ACTIVE=false;ShortestPathForever={API={Navigate=function(owner,map,x,y,title) CAPTURE={owner,map,x,y,title};return true end,CurrentStop=function(owner) if owner=="Evertally" and ACTIVE then return 1 end return nil end}}')
        self.assertTrue(ok(self.a.NavigateToPoint("Inn", WESTFALL, 0.25, 0.75)))
        self.assertTrue(tracker.terrain.shown)
        self.assertEqual(tracker.terrain.label.text, self.a.L("terrainButton"))
        tracker.terrain.scripts.OnClick()
        capture = self.lua.globals().CAPTURE
        self.assertEqual((capture[1], capture[2], capture[3], capture[4], capture[5]), ("Evertally", WESTFALL, 0.25, 0.75, "Inn"))
        self.lua.execute("ACTIVE=true")
        self.assertTrue(ok(self.a.NavigateToPoint("Inn", WESTFALL, 0.25, 0.75)))
        self.assertEqual(tracker.terrain.label.text, self.a.L("terrainOn"), "the button says when the journey is guided")
        self.lua.execute("ShortestPathForever=nil")
        self.assertTrue(ok(self.a.NavigateToPoint("Inn", WESTFALL, 0.25, 0.75)))
        self.assertFalse(tracker.terrain.shown, "the button goes away with the addon")


    # ================================================================ friends
    FRIENDS_LUA = """
    FRIENDS={{name="Bran",connected=true},{name="Eve-Fixture Realm",connected=false},{name="Ilyra",connected=true}}
    C_FriendList={GetNumFriends=function() return #FRIENDS end,GetFriendInfoByIndex=function(i) return FRIENDS[i] end}
    """

    def test_friends_get_the_beacons_by_whisper_only_while_online_and_only_when_chosen(self):
        self.lua.execute(self.FRIENDS_LUA)
        self.stand(ELWYNN, 0.45, 0.65)
        self.a.LiveTick(); self.pump()
        self.assertEqual(self.sent("S|L"), [], "off by default")
        self.a.SetLive("friends", True)
        self.a.LiveTick(); self.pump()
        beacons = self.sent("S|L")
        self.assertEqual(sorted(b.target for b in beacons), ["Bran", "Ilyra"], "the friend who is offline gets nothing")
        self.assertTrue(all(b.channel == "WHISPER" and b.text.startswith("S|L|1429|450|650|") for b in beacons))

    def test_no_more_than_twelve_friends_get_beacons(self):
        self.lua.execute("""
        FRIENDS={};for i=1,20 do FRIENDS[i]={name="Friend"..string.char(64+i),connected=true} end
        C_FriendList={GetNumFriends=function() return #FRIENDS end,GetFriendInfoByIndex=function(i) return FRIENDS[i] end}
        """)
        self.stand(ELWYNN, 0.45, 0.65)
        self.a.SetLive("friends", True)
        self.a.LiveTick(); self.pump(20)
        self.assertEqual(len(self.sent("S|L")), 12)

    def test_a_whispered_beacon_counts_only_from_someone_on_my_friends_list(self):
        self.lua.execute(self.FRIENDS_LUA)
        self.a.ReceiveMessage("Evtly1", "S|L|1429|100|100|1", "WHISPER", "Stranger-Fixture Realm")
        self.assertIsNone(self.a.LivePeer("Stranger"), "a stranger cannot put a dot on my map")
        self.a.ReceiveMessage("Evtly1", "S|L|1429|100|100|1", "WHISPER", "Bran-Fixture Realm")
        self.assertIsNotNone(self.a.LivePeer("Bran"))
        self.lua.globals().CLOCK += 5
        self.a.ReceiveMessage("Evtly1", "S|L|1429|100|100|1", "WHISPER", "Eve-Fixture Realm")
        self.assertIsNotNone(self.a.LivePeer("Eve"), "being on my list is what counts, not being online")
        self.a.ReceiveMessage("Evtly1", "S|E", "WHISPER", "Bran-Fixture Realm")
        self.assertIsNone(self.a.LivePeer("Bran"), "a friend's end message removes the dot")

    def test_switching_friends_off_tells_them_and_battle_net_friends_count_too(self):
        self.lua.execute(self.FRIENDS_LUA + """
        WOW_PROJECT_ID=160
        BNGetNumFriends=function() return 2 end
        C_BattleNet={GetFriendAccountInfo=function(i)
          if i==1 then return {gameAccountInfo={clientProgram="WoW",characterName="Grom",realmName="Fixture Realm",wowProjectID=160,isOnline=true}} end
          return {gameAccountInfo={clientProgram="BSAp",isOnline=true}} end}
        """)
        self.stand(ELWYNN, 0.45, 0.65)
        self.a.SetLive("friends", True)
        self.a.LiveTick(); self.pump()
        self.assertEqual(sorted(b.target for b in self.sent("S|L")), ["Bran", "Grom", "Ilyra"])
        self.a.SetLive("friends", False); self.pump()
        self.assertEqual(sorted(b.target for b in self.sent("S|E")), ["Bran", "Grom", "Ilyra"])
        self.lua.globals().CLOCK += 40
        self.a.LiveTick(); self.pump()
        self.assertEqual(self.sent("S|L"), [], "off: nothing more goes out")
        self.assertFalse(self.a.LiveActive())

    # ================================================================ the map in the window
    def world_fixture(self):
        self.lua.execute("""
        C_Map.GetMapInfo=function(id) return {name="Zone "..id,parentMapID=0} end
        C_Map.GetBestMapForUnit=function() return MAPID end
        OPENED=nil;OpenWorldMap=function(id) OPENED=id end
        WORLDMAP=1429;WorldMapFrame={IsShown=function() return true end,GetMapID=function() return WORLDMAP end}
        """)
        M = self.enable()
        self.stand(ELWYNN, 0.5, 0.5)
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        M.BuildWorld(body, self.a.UIKit())
        M.RefreshWorld(body)
        return M, body

    def world_pins(self, title=None):
        frames = lst(self.lua.eval("(function() local o={} for f in pairs(PINLOG.world) do o[#o+1]=f end return o end)()"))
        return [f for f in frames if title is None or str(f.spec.title) == title]

    # ================================================================ the database tab (QuestieDB)
    FAKE_QUESTIE = """
    local function entity(rows, keys)
      local e = {}
      function e.GetAllIds() local ids = {} for id in pairs(rows) do ids[#ids + 1] = id end table.sort(ids) return ids end
      function e.GetAll(id, wanted)
        local row = rows[id]
        if not row then return nil end
        local out = {n = #wanted}
        for i, key in ipairs(wanted) do out[i] = row[key] end
        return out
      end
      return e
    end
    LibQuestieDB = {
      RequireContract = function(n) return n == 2 end,
      Support = {Get = function(name) if name == "ZoneDB" then return {private = {areaIdToUiMapId = "return {[12]=1429,[40]=1436,[41]=1437}", areaIdToUiMapIdOverride = "return {[40]=0}"}} end end},
      Npc = entity({
        [100] = {name = "Marshal McBride", minLevel = 5, maxLevel = 5, subName = "Quest giver", npcFlags = 16, friendlyToFaction = "AH", questStarts = {200}, questEnds = {200}, spawns = {[12] = {{48.5, 42.3}, {50, 50}}}},
        [101] = {name = "Marshal Dughan", minLevel = 5, maxLevel = 7, npcFlags = 128, friendlyToFaction = "H", spawns = {[40] = {{50, 50}}, [12] = {{70, 70}}}},
        [102] = {name = "Brog Hamfist", minLevel = 3, maxLevel = 3, npcFlags = 65536 + 128, friendlyToFaction = "A", spawns = {[41] = {{10, 20}}, [12] = {{101, 5}}}},
        [103] = {name = "Mcbride's Cousin", minLevel = 1, maxLevel = 1},
      }),
      Quest = entity({[200] = {name = "Kobold Candles", questLevel = 2, startedBy = {{100}}, finishedBy = {{100, 102}}, objectivesText = {"Bring 8 candles."}}}),
      Item = entity({[300] = {name = "Linen Cloth", npcDrops = {101, 102}, questRewards = {200}}}),
    }
    """

    def db(self):
        self.lua.execute(self.FAKE_QUESTIE)
        M = self.enable()
        opened = M.Db.Open()
        return M, opened

    def test_questiedb_is_opened_only_when_it_is_there_and_the_right_version(self):
        M = self.enable()
        self.assertEqual(tuple(M.Db.Open()), (None, "missing"))
        self.lua.execute(self.FAKE_QUESTIE + "LibQuestieDB.RequireContract=function() return false end")
        self.assertEqual(tuple(M.Db.Open()), (None, "failed"))
        self.lua.execute(self.FAKE_QUESTIE + "LibQuestieDB.Npc=nil")
        self.assertEqual(tuple(M.Db.Open()), (None, "failed"))
        M, opened = self.db()
        self.assertIsNotNone(opened)

    def test_areas_become_maps_with_the_override_and_places_are_fractions(self):
        M, db = self.db()
        self.assertEqual(M.Db.MapOf(db, 12), 1429)
        self.assertIsNone(M.Db.MapOf(db, 40), "the override says 0: not shown")
        self.assertIsNone(M.Db.MapOf(db, 9999))
        spots = lst(M.Db.Spots(db, M.Db.Get(db, "npc", 102).spawns))
        self.assertEqual([(p.map, p.x, p.y) for p in spots], [(1437, 0.1, 0.2)], "the 101 > 100 coordinate is dropped, the area without a map too")

    def test_the_name_index_is_read_in_slices_and_search_puts_prefix_matches_first(self):
        M, db = self.db()
        done, progress = M.Db.Step(db, "npc")
        self.assertTrue(done); self.assertEqual(progress, 1)
        found = [M.Db.Get(db, "npc", i).name for i in lst(M.Db.Search(db, "npc", "marshal"))]
        self.assertEqual(found, ["Marshal McBride", "Marshal Dughan"])
        found = [M.Db.Get(db, "npc", i).name for i in lst(M.Db.Search(db, "npc", "bride"))]
        self.assertEqual(found, ["Marshal McBride", "Mcbride's Cousin"], "both contain it, neither starts with it: in the order of the ids")
        self.assertEqual([M.Db.Get(db, "npc", i).name for i in lst(M.Db.Search(db, "npc", "MC"))][0], "Mcbride's Cousin", "case does not matter, a name that starts with it comes first")
        self.assertEqual(lst(M.Db.Search(db, "npc", "m")), [], "one letter is not a search")
        self.assertEqual(lst(M.Db.Search(db, "npc", "zzz")), [])

    def test_details_name_the_places_and_the_people_behind_a_quest_and_an_item(self):
        M, db = self.db()
        npc = M.Db.Detail(db, "npc", 100)
        self.assertEqual(npc.map, 1429); self.assertEqual(len(lst(npc.spots)), 2)
        self.assertIn("Quest giver", npc.subtitle); self.assertIn("5", npc.subtitle)
        quest = M.Db.Detail(db, "quest", 200)
        text = "\n".join(str(l) for l in lst(quest.lines))
        self.assertIn("Bring 8 candles.", text); self.assertIn("Marshal McBride", text); self.assertIn("Brog Hamfist", text)
        self.assertEqual(quest.map, 1429, "the map with most of the places")
        item = M.Db.Detail(db, "item", 300)
        text = "\n".join(str(l) for l in lst(item.lines))
        self.assertIn("Marshal Dughan", text); self.assertIn("Kobold Candles", text)
        self.assertIsNone(M.Db.Detail(db, "npc", 99999))

    def database_fixture(self):
        """The database page's body (the database is a page of its own, not a tab of the map)."""
        M, world = self.world_fixture()
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 600, 420)
        M.BuildDatabase(body, self.a.UIKit())
        M.RefreshDatabase(body)
        return M, body

    def test_the_database_tab_searches_shows_a_detail_and_puts_the_places_on_the_map(self):
        self.lua.execute(self.FAKE_QUESTIE)
        M, body = self.database_fixture()
        frame = body.tabFrames.db
        s = frame.db
        self.assertTrue(frame.shown)
        s.box.SetText(s.box, "marshal")
        s.box.scripts.OnTextChanged(s.box)
        frame.scripts.OnUpdate(frame)
        rows = [r for r in lst(s.rows) if r.shown]
        self.assertEqual([str(r.name.text) for r in rows], ["Marshal McBride", "Marshal Dughan"])
        rows[0].scripts.OnClick()
        self.assertEqual(str(s.title.text), "Marshal McBride")
        self.assertTrue(s.show.shown and s.go.shown)
        s.show.scripts.OnClick()
        self.assertEqual(self.lua.globals().OPENED, 1429, "the game's own world map opens on the zone")
        self.assertEqual(len(lst(M.extra)), 2)
        marked = [f for f in self.world_pins("Marshal McBride") if f.spec.icon == "goal"]
        self.assertEqual(len(marked), 2, "and the places are marked on it")

    def test_a_record_of_a_quest_shows_what_the_quest_was_and_opens_in_the_database(self):
        self.lua.execute(self.FAKE_QUESTIE)
        self.enable()
        rows = [(str(r.title), str(r.sub or "")) for r in lst(self.a.DatabaseRows("quest", 200))]
        self.assertEqual(rows[0][0], "Kobold Candles", "what the quest is called")
        self.assertIn("Bring 8 candles.", [title for title, _ in rows], "what it asks for")
        self.assertIn("Marshal McBride", [title for title, _ in rows], "who gives it and who takes it")
        npc = [str(r.title) for r in lst(self.a.DatabaseRows("npc", 100))]
        self.assertEqual(npc[0], "Marshal McBride")
        unknown = lst(self.a.DatabaseRows("quest", 97236))
        self.assertEqual(len(unknown), 1)
        self.assertEqual(str(unknown[0].title), self.a.L("worldDbUnknown"), "a quest the database lacks says so instead of showing nothing")
        # the record's window offers the entry
        event = self.lua.table(kind="quest.completed", observedAt=1000, payload=self.lua.table(questId=200, npcId=100, title="Kobold Candles"))
        self.a.UIShowEventDetail(event)
        frame = self.lua.globals().EvertallyDetailFrame
        self.assertEqual((str(frame.entryKind), int(frame.entryId)), ("quest", 200))
        self.assertTrue(frame.database.shown)
        # and clicking it opens the database page on that quest
        M = self.a.map
        body = self.lua.eval("CreateFrame")("Frame", None, None)
        body.SetSize(body, 600, 420)
        M.BuildDatabase(body, self.a.UIKit())
        M.RefreshDatabase(body)
        self.a.databaseBody = body
        self.lua.execute("SHOWN=nil")
        self.a.ShowView = self.lua.eval("function(view) SHOWN=view end")
        frame.database.scripts.OnClick()
        self.assertEqual(self.lua.globals().SHOWN, "database")
        s = body.tabFrames.db.db
        self.assertEqual((str(s.selected.kind), int(s.selected.id)), ("quest", 200))
        self.assertEqual(str(s.title.text), "Kobold Candles")
        self.assertFalse(frame.IsShown(frame), "the window of the record closes")

    def test_the_database_lists_everything_before_anything_is_typed_and_has_objects(self):
        self.lua.execute(self.FAKE_QUESTIE)
        M, body = self.database_fixture()
        frame = body.tabFrames.db
        s = frame.db
        frame.scripts.OnUpdate(frame)
        for _ in range(5):
            frame.scripts.OnUpdate(frame)
        self.assertIn("2", str(s.status.text) + "2")
        s.kind = "quest"
        M.WorldDbRefresh(frame)
        for _ in range(3):
            M.Db.Step(s.dbHandle, "quest", 1000)
        M.WorldDbRefresh(frame)
        self.assertEqual(len(lst(s.results)), 1, "the one quest of the fake database, with nothing typed")
        s.kind = "npc"
        M.Db.Step(s.dbHandle, "npc", 1000)
        M.WorldDbRefresh(frame)
        names = [str(M.Db.Get(s.dbHandle, "npc", i).name) for i in lst(s.results)]
        self.assertEqual(names, sorted(names, key=str.lower), "by name")
        self.assertFalse(s.kindButtons["object"].shown, "the fake database has no objects: no button for them")

    def test_the_rows_of_an_entry_open_the_entries_they_name_so_the_database_is_linked(self):
        self.lua.execute(self.FAKE_QUESTIE)
        M, body = self.database_fixture()
        self.a.databaseBody = body
        self.a.ShowView = self.lua.eval("function(view) SHOWN=view end")
        frame = body.tabFrames.db
        s = frame.db
        M.OpenDatabaseEntry("quest", 200)
        self.assertEqual(str(s.title.text), "Kobold Candles")
        used = int(s.view.used.link)
        rows = [s.view.pools.link[i] for i in range(1, used + 1)]
        npc_rows = [r for r in rows if str(r.title.text) == "Marshal McBride"]
        self.assertEqual(len(npc_rows), 2, "he gives the quest and takes it in")
        self.assertTrue(npc_rows[0].icon.texture, "with an icon")
        npc_rows[0].scripts.OnClick(npc_rows[0])
        self.assertEqual((str(s.selected.kind), int(s.selected.id)), ("npc", 100), "a click opens the person")
        self.assertEqual(str(s.title.text), "Marshal McBride")
        rows = [s.view.pools.link[i] for i in range(1, int(s.view.used.link) + 1)]
        self.assertIn("Kobold Candles", [str(r.title.text) for r in rows], "and his quests are rows too: back to the quest")

    def test_the_database_tab_says_so_when_questiedb_is_missing(self):
        M, body = self.database_fixture()
        self.assertIn("QuestieDB", str(body.tabFrames.db.db.status.text))
        self.assertEqual(len([r for r in lst(body.tabFrames.db.db.rows) if r.shown]), 0)

    # ================================================================ the journey tab
    def test_places_to_go_are_zones_and_hubs_and_search_puts_prefix_matches_first(self):
        M, body = self.world_fixture()
        places = lst(M.Plan.Places())
        self.assertTrue(any(p.rank == 1 for p in places) and any(p.rank == 2 for p in places), "zones and hubs")
        hub = [p for p in places if p.rank == 2 and len(str(p.name)) >= 8][0]
        found = lst(M.Plan.Search(str(hub.name)[:6].lower()))
        self.assertIn(str(hub.name), [str(p.name) for p in found])
        starts = [str(p.lower).startswith(str(hub.name)[:6].lower()) for p in found]
        self.assertEqual(starts, sorted(starts, reverse=True), "names that start with the query come before the others")
        self.assertEqual(lst(M.Plan.Search("z")), [], "one letter is not a search")
        self.assertEqual(lst(M.Plan.Search("zzzzzz")), [])

    def test_the_journey_starts_where_you_stand_and_says_when_there_is_no_position(self):
        M, body = self.world_fixture()
        durotar = [p for p in lst(M.Plan.Places()) if p.rank == 1 and str(p.name) == "Zone %d" % DUROTAR][0]
        plan = M.Plan.Journey(durotar)
        self.assertIsNotNone(plan)
        self.assertGreater(plan.seconds, 0)
        self.assertGreaterEqual(len(lst(plan.steps)), 2, "another continent: more than a walk")
        self.lua.execute("MX=nil")
        result = tuple(M.Plan.Journey(durotar))
        self.assertEqual(result, (None, "no_position"))

    def test_the_journey_tab_lists_places_shows_the_steps_and_navigates(self):
        M, body = self.world_fixture()
        body.mode = "plan"
        M.RefreshWorld(body)
        frame = body.tabFrames.plan
        s = frame.plan
        s.box.SetText(s.box, "zone")
        s.box.scripts.OnTextChanged(s.box)
        rows = [r for r in lst(s.rows) if r.shown]
        self.assertGreater(len(rows), 0)
        durotar = [r for r in rows if str(r.name.text) == "Zone %d" % DUROTAR]
        if not durotar:
            s.box.SetText(s.box, "Zone %d" % DUROTAR)
            s.box.scripts.OnTextChanged(s.box)
            durotar = [r for r in lst(s.rows) if r.shown and str(r.name.text) == "Zone %d" % DUROTAR]
        self.assertEqual(len(durotar), 1)
        durotar[0].scripts.OnClick()
        self.assertEqual(str(s.title.text), "Zone %d" % DUROTAR)
        body_text = str(s.body.text)
        self.assertRegex(body_text, r"\d+:\d\d", "the steps carry their times")
        self.assertIn("|cffa78bfa", body_text, "and the total")
        s.go.scripts.OnClick()
        self.assertEqual(self.a.map.nav.target.kind, "point")
        self.assertEqual(self.a.map.nav.target.map, DUROTAR)
        s.show.scripts.OnClick()
        self.assertEqual(self.lua.globals().OPENED, DUROTAR)
        self.assertEqual(len(lst(M.extra)), 1)
    # ================================================================ layers on the map
    def test_the_travel_layer_puts_flight_masters_and_the_like_on_the_map_they_lie_on(self):
        M, body = self.world_fixture()
        specs = lst(M.LayerSpecs(1415, self.lua.table(travel=True)))  # Eastern Kingdoms
        self.assertGreater(len(specs), 5)
        self.assertLessEqual(len(specs), 250)
        self.assertTrue(all(0 <= p.x <= 1 and 0 <= p.y <= 1 and p.map == 1415 for p in specs))
        self.assertEqual(lst(M.LayerSpecs(1415, self.lua.table())), [], "off: nothing")

    def test_services_are_read_from_questiedb_for_this_side_and_only_shown_on_their_own_zone(self):
        self.lua.execute(self.FAKE_QUESTIE)
        M, body = self.world_fixture()
        db = M.Db.Open()
        done, progress = M.Db.ScanServices(db, None, "A")
        self.assertTrue(done); self.assertEqual(progress, 1)
        lists = M.Db.scan.lists
        self.assertEqual(len(lst(lists.trainer)), 2, "the trainer with two spawns")
        self.assertEqual([str(e.name) for e in lst(lists.vendor)], ["Brog Hamfist"], "the Horde vendor is not for an Alliance character")
        self.assertEqual([(e.map, e.x, e.y) for e in lst(lists.inn)], [(1437, 0.1, 0.2)], "the spawn at 101 is dropped and a map of its own")
        self.assertEqual(len(lst(M.LayerSpecs(1429, self.lua.table(trainer=True)))), 2)
        self.assertEqual(lst(M.LayerSpecs(1429, self.lua.table(inn=True))), [], "that inn is on another zone")
        self.assertEqual(len(lst(M.LayerSpecs(1437, self.lua.table(inn=True)))), 1)
        M.Db.Reset()

    def test_a_layer_is_drawn_on_the_world_map_that_is_shown_and_follows_the_map_and_the_switch(self):
        self.lua.execute(self.FAKE_QUESTIE)
        M, body = self.world_fixture()
        M.Db.ScanServices(M.Db.Open(), None, "A")
        self.assertEqual(self.world_pins("Marshal McBride"), [], "nothing until a layer is on")
        M.SetLayer("trainer", True)
        self.assertEqual(len(self.world_pins("Marshal McBride")), 2, "the trainer's two places on the zone that is shown")
        self.assertTrue(self.a.db.settings.mapLayers.trainer, "kept in the settings")
        self.lua.execute("WORLDMAP=1437")
        M.RefreshLayerPins(False)
        self.assertEqual(self.world_pins("Marshal McBride"), [], "another map: the pins move away with it")
        M.SetLayer("inn", True)
        self.assertEqual([str(f.spec.title) for f in self.world_pins()], ["Brog Hamfist"])
        self.lua.execute("WORLDMAP=1429")
        M.SetLayer("inn", False)
        self.assertEqual(len(self.world_pins("Marshal McBride")), 2)
        M.SetLayer("trainer", False)
        self.assertEqual(self.world_pins(), [])
        self.lua.execute("WorldMapFrame.IsShown=function() return false end")
        M.SetLayer("trainer", True)
        self.assertEqual(self.world_pins(), [], "no pins while the world map is closed")
        M.Db.Reset()

    def test_openmaps_own_menu_gets_what_openmap_has_no_layer_for(self):
        M, body = self.world_fixture()
        self.lua.execute("""
        TOGGLES={}
        OpenMapAPI={RegisterMenuToggle=function(owner,spec) TOGGLES[#TOGGLES+1]={owner=owner,spec=spec} end}
        """)
        self.assertTrue(M.RegisterWithOpenMap())
        toggles = lst(self.lua.globals().TOGGLES)
        self.assertEqual([str(t.spec.id) for t in toggles][:10], ["evertally_gather", "evertally_gather_herb", "evertally_gather_ore", "evertally_gather_fishing", "evertally_gather_container", "evertally_gather_all", "evertally_resources", "evertally_marked", "evertally_search", "evertally_journey"],
                         "flight masters, trainers, vendors, innkeepers and entrances are OpenMap's own layers: Evertally does not offer them twice")
        self.assertTrue(all(str(t.owner) == "Evertally" for t in toggles))
        self.assertEqual([str(t.spec.tab) for t in toggles][:10], ["show", "show", "show", "show", "show", "show", "more", "show", "more", "more"])
        self.assertTrue(all(str(t.spec.section).startswith("Evertally") for t in toggles), "every row under a heading of Evertally's")
        gather = toggles[0].spec
        self.assertTrue(gather.get(), "gathering is what the map is first used for: on from the start")
        gather.set(False)
        self.assertFalse(M.LayerOn("gather"))
        gather.set(True)
        self.assertTrue(gather.get())
        self.assertTrue(M.LayerOn("gather"))
        self.lua.execute("OpenMapAPI=nil")
        self.assertFalse(M.RegisterWithOpenMap(), "no OpenMap: nothing to register with")

    def test_the_map_panel_hangs_on_the_world_map_and_opens_the_database_and_clears_places(self):
        M, body = self.world_fixture()
        self.lua.execute("SHOWN=nil;WorldMapFrame=CreateFrame('Frame','WorldMapFrame')")
        self.a.ShowView = self.lua.eval("function(view) SHOWN=view end")
        self.assertTrue(M.BuildMapPanel())
        panel = self.lua.globals().EvertallyMapPanel
        self.assertFalse(panel.shown)
        self.lua.globals().EvertallyMapButton.scripts.OnClick()
        self.assertTrue(panel.shown)
        self.assertFalse(panel.clear.shown, "nothing marked: no clear button")
        self.a.worldBody = body  # what the page of the window does when it has built its body
        panel.journey.scripts.OnClick()
        self.assertEqual(self.lua.globals().SHOWN, "world")
        self.assertEqual(body.mode, "plan")
        panel.search.scripts.OnClick()
        self.assertEqual(self.lua.globals().SHOWN, "database", "the database is a page of its own")
        M.ShowOnWorldMap(self.lua.table_from([self.lua.table(map=1429, x=0.5, y=0.5, title="Here")]), 1429)
        M.PanelRefresh()
        self.assertTrue(panel.clear.shown)
        panel.clear.scripts.OnClick()
        self.assertEqual(len(lst(M.extra)), 0)
        self.assertTrue(M.BuildMapPanel(), "building it again changes nothing")

if __name__ == "__main__":
    unittest.main()
