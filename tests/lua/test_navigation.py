"""Lua replay checks for live position, pings, the map add-on (pins) and navigation. No game, no user data."""
from pathlib import Path
import json
import math
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, ROOT, runtime  # noqa: E402

MAP_DIR = ROOT / "addon" / "Evertally_Map"
MAP_FILES = ["Data.lua", "Planner.lua", "Navigator.lua", "Pins.lua"]  # the order of Evertally_Map.toc after the libraries
JOURNEYS = json.loads((ROOT / "tests" / "lua" / "fixtures" / "journeys.json").read_text(encoding="utf-8"))
ELWYNN, WESTFALL, STORMWIND, DUROTAR = 1429, 1436, 1453, 1411

FAKE_LIBS = """
PINLOG={world={},mini={},allWorld=0,allMini=0}
FAKEPINS={
  AddWorldMapIconMap=function(self,ref,icon,map,x,y,flag) PINLOG.world[icon]={ref=ref,map=map,x=x,y=y,flag=flag,spec=icon.spec} end,
  AddMinimapIconMap=function(self,ref,icon,map,x,y,parent,edge) PINLOG.mini[icon]={ref=ref,map=map,x=x,y=y,edge=edge,spec=icon.spec} end,
  RemoveWorldMapIcon=function(self,ref,icon) PINLOG.world[icon]=nil end,
  RemoveMinimapIcon=function(self,ref,icon) PINLOG.mini[icon]=nil end,
  RemoveAllWorldMapIcons=function(self,ref) PINLOG.world={};PINLOG.allWorld=PINLOG.allWorld+1 end,
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
        self.assertEqual((self.lua.globals().PINLOG.allWorld, self.lua.globals().PINLOG.allMini), (1, 1))
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


if __name__ == "__main__":
    unittest.main()
