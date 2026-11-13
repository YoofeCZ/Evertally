"""Real SPF collision and road data, not an invented square standability mask.

No WoW window or user character data is read. Packed fields are the bundled data;
Python supplies the client's base64/zlib codec and high-resolution frame clock.
"""
from pathlib import Path
import base64
import hashlib
import json
import math
import sys
import time
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import LuaRuntime, ROOT

MAP = ROOT / "addon" / "Evertally_Map"


def session():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().PYUNPACK = lambda text, _method: zlib.decompress(base64.b64decode(text))
    lua.globals().debugprofilestop = lambda: time.perf_counter() * 1000
    # Keep the opaque compressed blob base64-wrapped when it crosses Python's
    # UTF-8 bridge. The combined codec returns the exact decompressed ASCII field.
    lua.execute('''
      C_EncodingUtil={DecodeBase64=function(b) return b end,DecompressString=PYUNPACK}
      Enum={CompressionMethod={Zlib=1}}
      function geterrorhandler() return function(e) LAST_ERROR=e end end
      ThirdPartySentinel={value="untouched"}; ShortestPathForeverPathData=ThirdPartySentinel
      M={}
    ''')
    for name in (MAP / "Roads/files.txt").read_text(encoding="utf8").splitlines():
        lua.eval("loadstring")((MAP / name).read_text(encoding="utf8"), name)("Evertally_Map", lua.globals().M)
    return lua, lua.globals().M


class RoadPathTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.m = session()
        self.p = self.m.RoadPath

    def finish(self, job, limit=10000):
        slices = []
        for _ in range(limit):
            if job.state != "pending":
                break
            start = time.perf_counter()
            self.p.Step(job)
            slices.append(time.perf_counter() - start)
        self.assertNotEqual(job.state, "pending", "cooperative search must finish")
        self.assertIsNone(self.lua.globals().LAST_ERROR)
        return slices

    def test_real_stormwind_closed_wall_edge_is_not_joined_directly(self):
        # Fine cell19 is ground with +x/+y edges CLOSED. Old EVWM kept only its
        # ground bit, joined it to cell16, and called the 7.96yd chord clear.
        job = self.p.Begin(0, -8800, 600.9950248756222, -8800, 608.9552238805974)
        self.finish(job)
        self.assertEqual(job.state, "ready")
        self.assertGreater(len(job.result.points), 2)
        self.assertGreater(job.result.yards, 20, "the route must walk round the closed wall edge")
        self.assertLess(job.result.yards, 100)
        self.assertTrue(job.result.validated)

    def test_city_to_harbor_has_real_collision_bends_and_preserves_endpoint_heights(self):
        job = self.p.Begin(0, -8800, 600, -8300, 1450, self.lua.table(roads=True))
        self.finish(job)
        self.assertEqual(job.state, "ready")
        self.assertGreater(len(job.result.points), 15)
        self.assertGreater(job.result.yards, math.hypot(500, 850) * 1.1)
        self.assertIsNotNone(job.result.points[2][3], "native solver retains the chosen floor height")
        self.assertAlmostEqual(job.result.tails[1], job.result.yards)
        self.assertEqual(job.result.tails[len(job.result.points)], 0)
        self.assertTrue(all(job.result.tails[i] >= job.result.tails[i + 1] for i in range(1, len(job.result.points))))

    def road_fraction(self, points):
        self.lua.globals().POINTS = points
        return self.lua.eval('''(function()
          local G=M._roadEngine.PathGrid;local st=G.State(0)
          local road,total=0,0
          for i=2,#POINTS do
            local a,b=POINTS[i-1],POINTS[i]
            local dx,dy=b[1]-a[1],b[2]-a[2];local n=math.max(1,math.ceil(math.sqrt(dx*dx+dy*dy)/2))
            for j=1,n do
              local k,cell=G.locate(st,a[1]+dx*(j-.5)/n,a[2]+dy*(j-.5)/n)
              local set=k and G.roads(st,k)
              if set and set[cell] then road=road+1 end
              total=total+1
            end
          end
          return road/total
        end)()''')

    def test_real_stormwind_to_goldshire_walk_prefers_and_preserves_roads(self):
        pair = (0, -8913, 610, -9468, 68)
        direct = self.p.Begin(*pair, self.lua.table(roads=False))
        self.finish(direct)
        roads = self.p.Begin(*pair, self.lua.table(roads=True))
        self.finish(roads)
        self.assertEqual((direct.state, roads.state), ("ready", "ready"))
        self.assertGreater(self.road_fraction(roads.result.points), self.road_fraction(direct.result.points) + .05)
        self.assertTrue(roads.result.roads)
        self.assertFalse(direct.result.roads)

    def test_steep_directed_height_step_allows_downhill_but_rejects_uphill(self):
        step = self.m._roadEngine.PathGrid.steepStep
        self.assertFalse(step(self.lua.table_from([3]), self.lua.table_from([10]), 0,
                              self.lua.table_from([1]), self.lua.table_from([20]), 0))
        self.assertTrue(step(self.lua.table_from([1]), self.lua.table_from([20]), 0,
                             self.lua.table_from([3]), self.lua.table_from([10]), 0))

    def test_search_yields_between_slices_and_cancel_releases_it(self):
        job = self.p.Begin(0, -8913, 610, -9468, 68)
        self.assertEqual(job.state, "pending")
        self.p.Step(job)
        self.assertEqual(job.state, "pending", "a full city route must not be searched synchronously in Begin/one frame")
        self.p.Cancel(job)
        self.assertEqual(job.state, "cancelled")
        self.assertTrue(job.handle.cancelled)
        self.assertIsNone(job.handle.co)
        self.assertIsNone(job.result)
        self.p.Step(job)
        self.assertEqual(job.state, "cancelled")

    def test_native_search_is_sliced_with_a_two_millisecond_shared_deadline(self):
        job = self.p.Begin(0, -8913, 610, -9468, 68)
        slices = self.finish(job)
        self.assertGreater(len(slices), 2)
        self.assertEqual(self.m._roadEngine.Path.budget, 2)
        # CPython codec/clock callbacks and scheduler pauses add overhead. This is
        # only a smoke ceiling; it is not a claim about measured game frame time.
        self.assertLess(max(slices), .08)

    def test_namespace_and_data_are_independent_of_installed_spf(self):
        self.assertTrue(self.p.HasData(0)); self.assertTrue(self.p.HasData(1)); self.assertTrue(self.p.HasData(2991))
        self.assertFalse(self.p.HasData(9999))
        self.assertEqual(self.lua.eval("ShortestPathForeverPathData==ThirdPartySentinel"), True)
        self.assertIsNone(self.lua.globals().ShortestPathForever)
        self.assertEqual(self.lua.globals().ThirdPartySentinel.value, "untouched")

    def test_invalid_uncovered_or_unavailable_decoder_never_returns_fake_straight_route(self):
        unknown = self.p.Begin(9999, 0, 0, 1, 1)
        invalid = self.p.Begin(0, float("nan"), 0, 1, 1)
        self.lua.execute("C_EncodingUtil=nil")
        unavailable = self.p.Begin(0, -8800, 600, -8300, 1450)
        self.assertEqual((unknown.reason, invalid.reason, unavailable.reason), ("uncovered_map", "invalid_position", "decoder_unavailable"))
        for job in (unknown, invalid, unavailable):
            self.assertEqual(job.state, "failed"); self.assertIsNone(job.result)

    def test_vendored_source_manifest_matches_all_minimal_namespace_copies(self):
        manifest = json.loads((MAP / "Roads/manifest.json").read_text(encoding="utf8"))
        self.assertEqual(manifest["version"], "v1.35.0")
        self.assertEqual(manifest["license"], "GPL-3.0-or-later")
        for entry in manifest["files"]:
            self.assertEqual(hashlib.sha256((MAP / entry["bundled"]).read_bytes()).hexdigest(), entry["bundledSha256"])
        self.assertIn("GNU GENERAL PUBLIC LICENSE", (MAP / "Roads/LICENSE.txt").read_text(encoding="utf8"))


if __name__ == "__main__":
    unittest.main()
