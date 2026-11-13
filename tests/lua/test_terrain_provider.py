"""Terrain facade selects collision routing without confusing injected legacy grids."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import ROOT, runtime
from test_terrain import grid


PROVIDER = r'''
ROADLOG={begin=0,step=0,cancel=0}
ROAD={HasData=function(id) return id==0 or id==2991 end}
function ROAD.Begin(id,x,y,tx,ty,options)
    ROADLOG.begin=ROADLOG.begin+1
    ROADLOG.args={id,x,y,tx,ty};ROADLOG.options=options
    return {state="pending",map={id=id,cell=8},from={x,y},to={tx,ty},steps=0}
end
function ROAD.Step(job,budget)
    ROADLOG.step=ROADLOG.step+1;ROADLOG.budget=budget
    if job.state~="pending" then return job.state,job.result,job.reason end
    job.steps=job.steps+1
    job.result={points={job.from,job.to},tails={20,0},yards=20,cost=20,snapped=false,mapId=job.map.id}
    job.state="ready"
    return job.state,job.result,job.reason
end
function ROAD.Cancel(job)
    ROADLOG.cancel=ROADLOG.cancel+1
    job.state,job.reason,job.result="cancelled","cancelled",nil
end
'''


class TerrainProviderTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.addon = runtime()
        self.module = self.lua.table()
        self.original = grid(self.lua, [[1] * 4 for _ in range(4)])
        self.module.terrainMaps = self.lua.table_from({0: self.original})
        self.lua.execute(PROVIDER)
        self.module.RoadPath = self.lua.globals().ROAD
        source = (ROOT / "addon/Evertally_Map/Terrain.lua").read_text(encoding="utf-8")
        self.lua.eval("loadstring")(source, "Terrain.lua")("Evertally_Map", self.module)
        self.terrain = self.module.Terrain

    def test_bundled_map_delegates_with_road_preference_and_height_without_mutating_options(self):
        options = self.lua.table(fromZ=41.5, toZ=38, maxNodes=17)
        job = self.terrain.Begin(0, 5, 5, 25, 5, options)
        self.assertTrue(self.terrain.RoadBacked(0))
        self.assertEqual(job.provider, "roads")
        self.assertEqual(job.map.cell, 8)
        args = self.lua.globals().ROADLOG.args
        self.assertEqual([args[i] for i in range(1, 6)], [0, 5, 5, 25, 5])
        passed = self.lua.globals().ROADLOG.options
        self.assertTrue(passed.roads)
        self.assertIsNone(options.roads, "the caller's profile remains unchanged")
        self.assertEqual((passed.fromZ, passed.toZ, passed.maxNodes), (41.5, 38, 17))
        state, result, _ = self.terrain.Step(job, 23)
        self.assertEqual(state, "ready")
        self.assertEqual(result.yards, 20)
        self.assertEqual(self.lua.globals().ROADLOG.budget, 23)

    def test_explicit_profile_is_preserved(self):
        self.terrain.Begin(0, 5, 5, 25, 5, self.lua.table(roads=False))
        self.assertFalse(self.lua.globals().ROADLOG.options.roads)

    def test_replacement_grid_and_removed_map_never_use_world_collision_provider(self):
        self.terrain.maps[0] = grid(self.lua, [[1] * 4 for _ in range(4)])
        self.assertFalse(self.terrain.RoadBacked(0))
        job = self.terrain.Begin(0, 5, 5, 25, 5)
        self.assertIsNone(job.provider)
        for _ in range(100):
            self.terrain.Step(job)
            if job.state != "pending":
                break
        self.assertEqual(job.state, "ready")
        self.assertEqual(self.lua.globals().ROADLOG.begin, 0)
        self.terrain.maps[0] = None
        self.assertFalse(self.terrain.RoadBacked(0))
        missing = self.terrain.Begin(0, 5, 5, 25, 5)
        self.assertEqual((missing.state, missing.reason), ("failed", "uncovered_map"))

    def test_covered_provider_map_without_old_mask_still_routes(self):
        self.assertIsNone(self.terrain.maps[2991])
        self.assertTrue(self.terrain.RoadBacked(2991))
        self.assertEqual(self.terrain.Begin(2991, 5, 5, 25, 5).provider, "roads")
        self.assertFalse(self.terrain.RoadBacked(999))
        self.assertEqual(self.terrain.Begin(999, 5, 5, 25, 5).reason, "uncovered_map")

    def test_cancel_and_step_keep_the_provider_that_created_the_job(self):
        job = self.terrain.Begin(0, 5, 5, 25, 5)
        self.module.RoadPath = self.lua.table()
        self.terrain.Cancel(job)
        self.assertEqual(self.lua.globals().ROADLOG.cancel, 1)
        self.assertEqual((job.state, job.reason), ("cancelled", "cancelled"))
        self.assertEqual(self.terrain.Step(job)[0], "cancelled")
        self.assertIsNone(job.result)

    def test_arrival_does_not_trust_a_coarse_shortcut_or_fall_back_after_provider_rejection(self):
        self.assertTrue(self.terrain.Cell(self.original, 0, 0))
        self.assertFalse(self.terrain.Clear(self.original, 5, 5, 25, 5, True))
        self.lua.execute('''
          ROAD.Clear=function(map,x,y,tx,ty,dry)
              ROADLOG.clear={map,x,y,tx,ty,dry};return CLEAR_OK
          end
        ''')
        self.lua.globals().CLEAR_OK = False
        self.assertFalse(self.terrain.Clear(self.original, 5, 5, 25, 5, True))
        self.lua.globals().CLEAR_OK = True
        self.assertTrue(self.terrain.Clear(self.original, 5, 5, 25, 5, True))
        args = self.lua.globals().ROADLOG.clear
        self.assertEqual([args[i] for i in range(1, 7)], [0, 5, 5, 25, 5, True])


if __name__ == "__main__":
    unittest.main()
