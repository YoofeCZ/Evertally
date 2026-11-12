"""Bounded Lua terrain search and its actual Navigator.Update integration, without WoW.

The real-data case reads the same walk.bin and coordinate transforms as the web.
CPU timing is an offline test measurement, never a live-client frame-rate claim.
"""
import math
from pathlib import Path
import struct
import sys
import time
import unittest
import zlib

sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_addon import runtime,MOCK_UI_LUA,ROOT
from test_navigation import RECORD_ROTATION

MAP=ROOT/'addon/Evertally_Map'
ALPHABET='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'


def load(lua,m,name):
    fn=lua.eval('loadstring')((MAP/name).read_text(encoding='utf8'),name)
    if isinstance(fn,tuple):raise AssertionError(f'{name}: {fn}')
    fn('Evertally_Map',m)


def grid(lua,rows,cell=10,map_id=0):
    nx,ny=len(rows),len(rows[0]);flat=[v for row in rows for v in row]
    padded=flat+[0]*((-len(flat))%3)
    data=''.join(ALPHABET[padded[i]*16+padded[i+1]*4+padded[i+2]] for i in range(0,len(padded),3))
    return lua.table_from(dict(id=map_id,x0=0,y0=0,cell=cell,nx=nx,ny=ny,data=data))


class TerrainTests(unittest.TestCase):
    def setUp(self):
        self.lua,self.a=runtime();self.m=self.lua.table();load(self.lua,self.m,'Terrain.lua');self.t=self.m.Terrain

    def finish(self,job,budget=192,max_steps=20000):
        times=[]
        for _ in range(max_steps):
            if job.state!='pending':return job,times
            before=time.perf_counter();self.t.Step(job,budget);times.append((time.perf_counter()-before)*1000)
        self.fail('Search did not stop within the explicit step limit')

    def test_routes_around_a_wall_and_every_smoothed_segment_keeps_clear(self):
        rows=[[1]*12 for _ in range(12)]
        for y in range(9):rows[5][y]=0
        terrain=grid(self.lua,rows);self.t.maps[0]=terrain
        job,_=self.finish(self.t.Begin(0,15,25,95,25))
        self.assertEqual(job.state,'ready',job.reason)
        points=job.result.points
        self.assertTrue(any(points[i][2]>=90 for i in range(1,len(points)+1)))
        self.assertGreater(job.result.yards,80)
        for i in range(1,len(points)):
            self.assertTrue(self.t.Clear(terrain,points[i][1],points[i][2],points[i+1][1],points[i+1][2],True))

    def test_does_not_cut_blocked_diagonal_corners(self):
        self.t.maps[0]=grid(self.lua,[[1,0],[0,1]],1)
        job,_=self.finish(self.t.Begin(0,.5,.5,1.5,1.5))
        self.assertEqual((job.state,job.reason),('failed','no_path'))

    def test_prefers_a_short_dry_detour_over_the_water(self):
        rows=[[1]*5 for _ in range(9)]
        for x in range(2,7):rows[x][2]=2
        terrain=grid(self.lua,rows);self.t.maps[0]=terrain
        job,_=self.finish(self.t.Begin(0,5,25,85,25))
        self.assertEqual(job.state,'ready',job.reason)
        self.assertLess(job.result.cost,120,'The straight route has a water-weighted cost of 180 yards')
        self.assertGreater(job.result.yards,80)

    def test_budget_node_limit_cancel_and_uncovered_maps(self):
        rows=[[1]*18 for _ in range(18)]
        for y in range(15):rows[7][y]=0
        self.t.maps[0]=grid(self.lua,rows)
        job=self.t.Begin(0,15,25,155,25)
        self.t.Step(job,1)
        self.assertEqual(job.state,'pending');self.assertLessEqual(job.expanded,1)
        self.t.Cancel(job);steps=job.steps;self.t.Step(job)
        self.assertEqual((job.state,job.steps),('cancelled',steps));self.assertIsNone(job.co)
        limited,_=self.finish(self.t.Begin(0,15,25,155,25,self.lua.table_from({'maxNodes':3})))
        self.assertEqual((limited.state,limited.reason),('failed','node_limit'))
        self.assertLessEqual(limited.discovered,4)
        unknown=self.t.Begin(999,0,0,1,1)
        self.assertEqual((unknown.state,unknown.reason),('failed','uncovered_map'))

    def test_frame_time_deadline_yields_before_the_larger_node_budget(self):
        rows=[[1]*24 for _ in range(24)]
        for y in range(21):rows[7][y]=0
        self.t.maps[0]=grid(self.lua,rows)
        self.lua.execute('PROFILE=0;debugprofilestop=function() PROFILE=PROFILE+3;return PROFILE end')
        job=self.t.Begin(0,15,25,195,25)
        self.t.Step(job,512)
        self.assertEqual(job.state,'pending')
        self.assertLessEqual(job.expanded,16,'A 2ms deadline interrupts a slice before its larger operation budget')

    def navigator(self):
        self.lua.execute(MOCK_UI_LUA);self.lua.execute(RECORD_ROTATION)
        m=self.lua.table()
        for name in ('Data.lua','Planner.lua','Terrain.lua','Navigator.lua'):load(self.lua,m,name)
        self.lua.globals().NAVTEST=m
        self.lua.execute('''
        PX,PY=15,25
        GetPlayerFacing=function() return 0 end
        UnitFactionGroup=function() return 'Alliance' end
        NAVTEST.ToUV=function(_,x,y) return x*100,y*100 end
        NAVTEST.ToYards=function(x,y) return 0,x,y end
        NAVTEST.PlayerPosition=function() return PX,PY,1429,PX/100,PY/100 end
        NAVTEST.PlanJourney=function(a,b) return {steps={{mode='walk',tu=b.u,tv=b.v,to='Fixture',seconds=10}},seconds=10} end
        ''')
        rows=[[1]*12 for _ in range(12)]
        for y in range(9):rows[5][y]=0
        m.Terrain.maps[0]=grid(self.lua,rows);m.Terrain.BATCH=8
        return m

    def test_real_navigator_uses_the_bend_then_cancels_and_replans(self):
        m=self.navigator();goal=self.lua.table_from(dict(kind='point',map=1429,x=.95,y=.25,label='Terrain fixture'))
        self.assertTrue(m.Navigate(goal))
        tracker=self.lua.globals().EvertallyTracker
        self.assertEqual(m.nav.groundStatus,'pending')
        self.assertIn(str(self.a.L('navGroundPending')),tracker.hint.text)
        job=m.nav.ground.job
        for _ in range(1000):
            tracker.scripts.OnUpdate(tracker,.016);m.nav.Update()
            if m.nav.groundStatus in ('terrain','snapped'):break
        self.assertEqual(m.nav.groundStatus,'terrain')
        self.assertEqual(job.state,'ready')
        self.assertGreater(tracker.arrow.rotation,.2,'The direct goal is due north: the arrow must instead point at a terrain bend')
        self.assertIn(str(self.a.L('navGround')),tracker.hint.text)
        self.assertEqual(m.nav.shown[1].id,'goal')
        self.assertTrue(any(m.nav.shown[i].id=='terrain' for i in range(2,len(m.nav.shown)+1)))
        # Walking away from the active polyline cancels the route before it is replaced.
        self.lua.execute('PX=300;PY=300;CLOCK=CLOCK+2')
        m.nav.Update()
        self.assertEqual(job.state,'cancelled')
        self.lua.execute('PX=15;PY=25;CLOCK=CLOCK+2')
        m.nav.Update()
        job=m.nav.ground.job
        for _ in range(1000):
            tracker.scripts.OnUpdate(tracker,.016);m.nav.Update()
            if m.nav.groundStatus in ('terrain','snapped'):break
        old=job
        m.Navigate(self.lua.table_from(dict(kind='point',map=1429,x=.9,y=.9,label='Moved')))
        self.assertEqual(old.state,'cancelled')
        pending=m.nav.ground.job;m.Stop()
        self.assertEqual(pending.state,'cancelled');self.assertIsNone(m.nav.ground)
        m.Terrain.maps[0]=None
        m.Navigate(goal)
        self.assertEqual(m.nav.groundStatus,'direct');self.assertIsNone(m.nav.ground)
        self.assertEqual(tracker.hint.text,self.a.L('navGroundDirect'))

    def test_nearby_goal_behind_a_wall_is_not_marked_arrived(self):
        m=self.navigator()
        self.lua.execute('PX=45;PY=25')
        m.Navigate(self.lua.table_from(dict(kind='point',map=1429,x=.75,y=.25,label='Across wall')))
        tracker=self.lua.globals().EvertallyTracker
        self.assertNotEqual(tracker.line1.text,self.a.L('navArrived'))
        self.assertIsNotNone(m.nav.ground)
        self.assertIn(m.nav.groundStatus,('pending','terrain'))

    def test_identical_coordinates_arrive_even_when_the_coarse_cell_is_blocked(self):
        m=self.navigator()
        self.lua.execute('PX=55;PY=25')
        m.Navigate(self.lua.table_from(dict(kind='point',map=1429,x=.55,y=.25,label='Already here')))
        tracker=self.lua.globals().EvertallyTracker
        self.assertEqual(tracker.line1.text,self.a.L('navArrived'))
        self.assertIsNone(m.nav.ground)

    def test_real_mask_decodes_and_a_goldshire_walk_completes_with_bounded_slices(self):
        m=self.lua.table()
        for name in ('Data.lua','Planner.lua','TerrainData.lua','Terrain.lua'):load(self.lua,m,name)
        blob=(ROOT/'platform/public/media/world/walk.bin').read_bytes();at=6
        for _ in range(blob[5]):
            map_id,x0,y0,cell,nx,ny,length=struct.unpack_from('<hfffHHI',blob,at);at+=22
            raw=zlib.decompress(blob[at:at+length]);at+=length
            terrain=m.Terrain.maps[map_id]
            self.assertEqual((terrain.nx,terrain.ny),(nx,ny));self.assertAlmostEqual(terrain.cell,cell,8)
            for i in (0,len(raw)-1,*range(17,len(raw),max(1,len(raw)//50))):
                self.assertEqual(m.Terrain.Cell(terrain,i//ny,i%ny),raw[i])
        u,v=m.ToUV(1429,.4234,.6512);continent,x,y=m.ToYards(u,v)
        tu,tv=m.ToUV(1429,.53,.50);other,tx,ty=m.ToYards(tu,tv)
        self.assertEqual(continent,other)
        job=m.Terrain.Begin(continent,x,y,tx,ty)
        old_t=self.t;self.t=m.Terrain
        try:job,times=self.finish(job)
        finally:self.t=old_t
        self.assertEqual(job.state,'ready',job.reason)
        self.assertGreater(job.result.yards,0)
        self.assertLessEqual(job.discovered,m.Terrain.MAX_NODES)
        self.assertGreater(len(times),1)
        print(f'\nTerrain offline Goldshire: {job.expanded} expanded / {job.discovered} discovered, {len(times)} slices, max slice {max(times):.2f} ms, total {sum(times):.2f} ms, path {job.result.yards:.0f} yd')


if __name__=='__main__':unittest.main()
