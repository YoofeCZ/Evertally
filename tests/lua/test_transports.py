"""Boat and zeppelin times from DockWatch's data (TransportData.lua): the schedule arithmetic, the docks and the pins on the map."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_openmap
from test_openmap import MAP_DIR, OPENMAP, lst

POS = """
CreateVector2D=function(x,y) return {x=x,y=y} end
C_Map.GetMapPosFromWorldPos=function(instance,vec,map)
  -- Durotar (1411) holds the Orgrimmar towers, Tirisfal (1420) the Undercity ones; nothing else
  if map==1411 and instance==1 and vec.x>1000 and vec.x<1500 and vec.y<-4500 then return 1411,{GetXY=function() return .5,.2 end} end
  if map==1420 and instance==0 and vec.x>1900 and vec.x<2200 and vec.y>200 and vec.y<350 then return 1420,{GetXY=function() return .6,.6 end} end
  return nil
end
C_Map.GetWorldPosFromMapPos=function(map) if map==1411 then return 1 end if map==1420 then return 0 end end
C_Map.GetMapInfo=function(id) return {name="Map "..id,mapType=3} end
"""


class TransportTests(unittest.TestCase):
    def setUp(self):
        test_openmap.OpenMapTests.setUp(self)
        self.assertTrue(self.m.transport, "the map add-on's toc loads TransportData.lua and Transports.lua")
        self.lua.execute(POS)
        self.t = self.m.transport
        self.routes = lst(self.m.transportData.routes)

    def route(self, rid):
        return next(r for r in self.routes if r.id == rid)

    def test_every_route_leaves_from_at_least_one_end_and_circuit_legs_only_one_way(self):
        self.assertEqual(len(self.routes), 13)
        for r in self.routes:
            self.assertGreaterEqual(len(lst(self.t.Legs(r))), 1, r.id)
        legs = lst(self.t.Legs(self.route("baradin-longwash")))
        self.assertEqual([(l["from"], l.to) for l in legs], [("b", "a")], "the circuit boat sails The Long Wash -> Baradin Bay only")

    def test_both_seeds_of_a_route_agree_with_the_trip_and_the_wait(self):
        # leaving b = leaving a + trip a->b + wait at b, modulo the loop: DockWatch's numbers hold together
        for r in self.routes:
            s, t = r.seed, r.times
            if s.a and s.b and t.ab and t.wb:
                off = (s.b - (s.a + t.ab + t.wb)) % t.loop
                self.assertLess(min(off, t.loop - off), 2.5, r.id)

    def test_the_next_departure_counts_whole_loops_and_knows_the_wait_in_port(self):
        leg = self.lua.table_from({"first": 1000, "wait": 60, "trip": 100})
        left, waiting = self.t.Next(leg, 300, 1000 + 300 * 5 - 30)[0:2]
        self.assertAlmostEqual(left, 30); self.assertTrue(waiting)
        left, waiting = self.t.Next(leg, 300, 1001)[0:2]
        self.assertAlmostEqual(left, 299); self.assertFalse(waiting)
        self.assertEqual(self.t.Clock(125), "2:05")

    def test_the_faction_decides_which_docks_are_shown_and_near_towers_share_a_pin(self):
        horde = lst(self.t.Docks("Horde"))
        names = {lst(d.legs)[0].route.id for d in horde}
        self.assertNotIn("stormwind-mistsedge", names)
        self.assertIn("bootybay-ratchet", names, "neutral boats are for everyone")
        alliance = {lst(d.legs)[0].route.id for d in lst(self.t.Docks("Alliance"))}
        self.assertNotIn("tirisfal-durotar", alliance)
        # Durotar: the Tirisfal and the Grom'gol zeppelin towers are 50 yards apart: one pin with both
        durotar = [d for d in horde if d.instance == 1 and abs(d.x - 1330) < 60 and abs(d.y + 4650) < 60]
        self.assertEqual(len(durotar), 1)
        self.assertEqual(sorted(e.route.id for e in lst(durotar[0].legs)), ["gromgol-durotar", "tirisfal-durotar"])

    def test_pins_with_countdowns_on_the_map_that_is_shown_and_off_with_the_switch(self):
        self.lua.execute("UnitFactionGroup=function() return 'Horde' end; GetServerTime=function() return 1791725282 + 356.29*100 + 10 end; WORLDMAP=1411")
        self.t.Refresh(True)
        pins = self.lua.eval("(function() local o={} for f,e in pairs(PINLOG.world) do if e.ref=='EvertallyDocks' then o[#o+1]=f end end return o end)()")
        pins = lst(pins)
        self.assertEqual(len(pins), 1, "one pin for the Durotar towers")
        caption = pins[0].caption.text if hasattr(pins[0].caption, "text") else pins[0].caption.GetText(pins[0].caption)
        self.assertRegex(caption, r"^~\d+:\d\d$")
        info = self.t.Describe(pins[0].dock, 1791725282 + 356.29 * 100 + 10)
        self.assertEqual(len(lst(info.lines)), 2)
        self.t.SetEnabled(False)
        left = self.lua.eval("(function() local n=0 for f,e in pairs(PINLOG.world) do if e.ref=='EvertallyDocks' then n=n+1 end end return n end)()")
        self.assertEqual(left, 0)

    def test_the_switch_is_in_openmaps_menu(self):
        self.lua.execute(OPENMAP)
        self.assertTrue(self.t.RegisterWithOpenMap(self.lua.globals().OpenMapAPI))
        ids = [t.spec.id for t in lst(self.lua.globals().TOGGLES)]
        self.assertIn("evertally_docks", ids)

    def test_texts_in_both_languages_and_the_mit_notice_travels_with_the_data(self):
        for lang in ("en", "cs"):
            for key in ("dockToggle", "dockLeaves", "dockInPort", "dockArrives", "dockSource"):
                self.assertIn(key, self.a.locale[lang], (lang, key))
                # the source is credited in NOTICE.txt and THIRD_PARTY.md, never in the game's own texts
                self.assertNotIn("dockwatch", str(self.a.locale[lang][key]).lower(), (lang, key))
        code = (MAP_DIR / "Transports.lua").read_text(encoding="utf8")
        self.assertNotIn("PocketWatch", code, "our own badges, not a borrowed icon")
        for name in ("ship.tga", "zeppelin.tga"):
            self.assertEqual((MAP_DIR / "Media" / name).read_bytes()[:3], bytes([0, 0, 2]), name)
        data = (MAP_DIR / "TransportData.lua").read_text(encoding="utf8")
        self.assertIn("Copyright (c) 2026 Wyveryx", data)
        self.assertIn("Permission is hereby granted", data)


if __name__ == "__main__":
    unittest.main()
