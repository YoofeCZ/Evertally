"""One transport replan per real frame across navigation and preview requests."""
import unittest

from test_addon import LuaRuntime
from test_terrain import MAP


class JourneyFrameBudgetTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
          PLAN_CALLS=0;PLAN_ORDER={};SEARCHES={};COMPLETED={}
          M={data={yards={[0]={0,1,0,1}}}}
          function CreateFrame()
            DRIVER={scripts={}}
            function DRIVER:SetScript(event,callback) self.scripts[event]=callback end
            return DRIVER
          end
          function M.ToYards(u,v) return 0,v,u end
          M.RoadPath={HasData=function() return true end}
          function M.RoadPath.Begin(map,x,y,tx,ty,options)
            local search={state="pending",blocked=BLOCK_NEW==true,costOnly=options.costOnly,
              result={cost=10,points=not options.costOnly and {{x,y},{tx,ty}} or nil}}
            SEARCHES[#SEARCHES+1]=search
            return search
          end
          function M.RoadPath.Step(search)
            if not search.blocked then search.state="ready" end
            return search.state
          end
          function M.RoadPath.Cancel(search) search.state="cancelled" end
          function M.PlanJourney(from,to,options)
            PLAN_CALLS=PLAN_CALLS+1;PLAN_ORDER[#PLAN_ORDER+1]=from.label
            local key="walk-"..from.label
            local record=options.walkCosts[key]
            return {steps={{mode="walk",walkKey=key,fu=from.u,fv=from.v,tu=to.u,tv=to.v,
              needsValidation=record==nil,routePath=record and record.path or nil}},seconds=10}
          end
        ''')
        self.m = self.lua.globals().M
        self.lua.eval("loadstring")((MAP / "Journey.lua").read_text(encoding="utf-8"), "Journey.lua")("Evertally_Map", self.m)

    def begin(self, label, cached=False):
        if cached:
            self.m.Journey.cache["walk-" + label] = self.lua.table(cost=10, path=self.lua.table_from([
                self.lua.table_from([.1, .1]), self.lua.table_from([.2, .2])]))
        job = self.m.Journey.Begin(self.lua.table(u=.1, v=.1, label=label), self.lua.table(u=.2, v=.2), self.lua.table())
        self.lua.globals().LATEST_JOB = job
        self.lua.execute('''local job=LATEST_JOB
          job.onDone=function(completed) COMPLETED[job.from.label]=(COMPLETED[job.from.label] or 0)+1 end''')
        return job

    def frame(self):
        before = self.lua.globals().PLAN_CALLS
        self.lua.globals().DRIVER.scripts.OnUpdate()
        self.assertLessEqual(self.lua.globals().PLAN_CALLS - before, 1)

    def test_offline_step_only_plans_once_even_when_cached_walks_allow_an_immediate_retry(self):
        job = self.begin("solo", cached=True)
        self.m.Journey.Step(job)
        self.assertEqual(self.lua.globals().PLAN_CALLS, 1)
        self.assertEqual(job.state, "pending")
        self.m.Journey.Step(job)
        self.assertEqual(job.state, "ready")
        self.assertEqual(self.lua.globals().COMPLETED.solo, 1)

    def test_navigation_and_preview_steps_share_one_driver_slot_without_starvation(self):
        self.frame()  # A real render driver now owns planning, unlike offline replay.
        nav = self.begin("nav", cached=True)
        preview = self.begin("preview", cached=True)
        for _ in range(3):
            self.m.Journey.Step(nav)
            self.m.Journey.Step(preview)
        self.assertEqual(self.lua.globals().PLAN_CALLS, 0)
        self.frame()
        for _ in range(3):
            self.m.Journey.Step(nav)
            self.m.Journey.Step(preview)
        self.assertEqual(self.lua.globals().PLAN_CALLS, 1)
        for _ in range(3):
            self.frame()
        self.assertEqual(list(self.lua.globals().PLAN_ORDER.values()), ["nav", "preview", "nav", "preview"])
        self.assertEqual((nav.state, preview.state), ("ready", "ready"))
        self.assertEqual(self.lua.globals().COMPLETED.nav, 1)
        self.assertEqual(self.lua.globals().COMPLETED.preview, 1)

    def test_initial_external_plan_does_not_add_another_plan_on_the_first_driver_update(self):
        nav = self.begin("nav", cached=True)
        self.begin("preview", cached=True)
        self.m.Journey.Step(nav)
        self.frame()
        self.assertEqual(self.lua.globals().PLAN_CALLS, 1)
        self.frame()
        self.assertEqual(self.lua.globals().PLAN_CALLS, 2)

    def test_waiting_collision_search_does_not_starve_a_ready_preview(self):
        self.frame()
        self.lua.execute("BLOCK_NEW=true")
        waiting = self.begin("waiting")
        preview = self.begin("preview", cached=True)
        self.frame()
        for _ in range(3):
            self.frame()
        self.assertEqual(waiting.state, "pending")
        self.assertEqual(preview.state, "ready")
        self.assertEqual(self.lua.globals().COMPLETED.preview, 1)
        self.assertIsNone(self.lua.globals().COMPLETED.waiting)

    def test_cancel_releases_search_and_does_not_consume_another_jobs_turn(self):
        self.frame()
        cancelled = self.begin("cancelled")
        next_job = self.begin("next", cached=True)
        self.frame()
        search = self.lua.globals().SEARCHES[1]
        self.m.Journey.Cancel(cancelled)
        self.assertEqual(search.state, "cancelled")
        for _ in range(3):
            self.frame()
        self.assertEqual(next_job.state, "ready")
        self.assertEqual(self.lua.globals().COMPLETED.next, 1)
        self.assertIsNone(self.lua.globals().COMPLETED.cancelled)
        self.assertIsNone(self.m.Journey.active[cancelled])


if __name__ == "__main__":
    unittest.main()
