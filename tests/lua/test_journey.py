"""Compare actual walk geometry before selecting transport, using shipped collision data."""
import unittest
from test_roadpath import session, MAP


class JourneyTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.m = session()
        self.lua.execute('Evertally={}; function CreateFrame() return {SetScript=function() end} end')
        for name in ("Data.lua", "Planner.lua", "TerrainData.lua", "Terrain.lua", "Journey.lua"):
            self.lua.eval("loadstring")((MAP / name).read_text(encoding="utf8"), name)("Evertally_Map", self.m)

    def point(self, map_id, x, y, label):
        u, v = self.m.ToUV(map_id, x, y)
        return self.lua.table(u=u, v=v, label=label)

    def finish(self, job):
        for _ in range(20000):
            if job.state != "pending":
                break
            self.m.Journey.Step(job)
        self.assertNotEqual(job.state, "pending")
        self.assertIsNone(self.lua.globals().LAST_ERROR)
        return job

    def test_dolanaar_to_stormwind_uses_darnassus_portal_and_boats_without_unknown_flights(self):
        job = self.m.Journey.Begin(self.point(1438, .55, .60, "Dolanaar"), self.point(1453, .5, .5, "Stormwind"),
                                   self.lua.table(side="A", speed=7, knownTaxi=self.lua.table()))
        self.assertIsNone(job.plan, "estimated itinerary must never be presented as navigable")
        self.finish(job)
        self.assertEqual(job.state, "ready", job.reason)
        steps = [job.plan.steps[i] for i in range(1, len(job.plan.steps) + 1)]
        self.assertNotIn("flight", [s.mode for s in steps])
        self.assertIn("portal", [s.mode for s in steps], "walk through Darnassus portal, not round the Teldrassil cliff")
        self.assertEqual([s.mode for s in steps].count("boat"), 2)
        for step in steps:
            if step.mode == "walk":
                self.assertFalse(step.needsValidation)
                self.assertGreaterEqual(len(step.routePath), 2)
        self.assertGreater(job.rounds, 1, "the chosen straight-line estimate must be reconsidered using real costs")

    def test_flight_edges_require_both_confirmed_endpoints_and_cache_changes_with_knowledge(self):
        a = self.point(1453, .5, .5, "Stormwind")
        b = self.point(1419, .5, .5, "Blasted Lands")
        options = self.lua.table(side="A", speed=7, knownTaxi=self.lua.table())
        unknown = self.m.PlanJourney(a, b, options)
        self.assertFalse(any(unknown.steps[i].mode == "flight" for i in range(1, len(unknown.steps) + 1)))
        # Reference planning may use all flights, but actual character planning never does.
        reference = self.m.PlanJourney(a, b, self.lua.table(side="A", speed=7))
        flights = [s for _, s in reference.steps.items() if s.mode == "flight"]
        self.assertTrue(flights)
        ids = {}
        for step in flights:
            for label in (step["from"], step.to):
                for key, hub in self.m.data.hubs.items():
                    if str(key).startswith("taxi") and hub[6] == label:
                        ids[int(str(key)[4:])] = True
        options.knownTaxi = self.lua.table_from(ids)
        unlocked = self.m.PlanJourney(a, b, options)
        self.assertTrue(any(unlocked.steps[i].mode == "flight" for i in range(1, len(unlocked.steps) + 1)))
        options.knownTaxi = self.lua.table()
        locked_again = self.m.PlanJourney(a, b, options)
        self.assertFalse(any(locked_again.steps[i].mode == "flight" for i in range(1, len(locked_again.steps) + 1)))

    def test_cancel_releases_every_pending_search_without_publishing_a_route(self):
        job = self.m.Journey.Begin(self.point(1438, .55, .60, "Dolanaar"), self.point(1453, .5, .5, "Stormwind"),
                                   self.lua.table(side="A", speed=7, knownTaxi=self.lua.table()))
        self.m.Journey.Step(job)
        searches = [p.search for _, p in job.pending.items()]
        self.assertTrue(searches)
        self.m.Journey.Cancel(job)
        self.assertEqual(job.state, "cancelled")
        self.assertIsNone(job.plan)
        self.assertTrue(all(s.state == "cancelled" for s in searches))

    def test_unavailable_decoder_fails_without_unverified_direct_route(self):
        self.lua.execute("C_EncodingUtil=nil")
        job = self.m.Journey.Begin(self.point(1438, .55, .60, "Dolanaar"), self.point(1453, .5, .5, "Stormwind"),
                                   self.lua.table(side="A", speed=7, knownTaxi=self.lua.table()))
        self.finish(job)
        self.assertEqual(job.state, "failed")
        self.assertEqual(job.reason, "decoder_unavailable")
        self.assertIsNone(job.plan)


if __name__ == "__main__":
    unittest.main()
