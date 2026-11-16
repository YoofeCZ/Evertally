"""The moments of the journey (Journey.lua): kills, money, skills, deaths, groups, flights, in batches, under the consent of the route."""
import unittest
from test_addon import runtime


class JourneyTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute('''
          COMBATLOG_XPGAIN_FIRSTPERSON="%s dies, you gain %d experience."
          SKILL_RANK_UP="Your skill in %s has increased to %d."
          MONEY=1000; GROUPED=false; MEMBERS=1; TAXI=false
          GetMoney=function() return MONEY end
          IsInGroup=function() return GROUPED end
          GetNumGroupMembers=function() return MEMBERS end
          UnitOnTaxi=function() return TAXI end
          GetNumSkillLines=function() return 2 end
          GetSkillLineInfo=function(i) if i==1 then return "Professions",true,true,0,0,0,0 end return "Herbalism",false,false,93,0,0,150 end
          MAPID=1429; MX=0.5; MY=0.5
          C_Map={GetBestMapForUnit=function() return MAPID end,GetPlayerMapPosition=function() return {GetXY=function() return MX,MY end} end}
        ''')

    def on(self, web=True, track=True):
        if web: self.a.SetWeb(True)
        if track: self.a.SetScope("own_track", True)
        self.a.Dispatch("PLAYER_ENTERING_WORLD")

    def tick(self, seconds=1):
        g = self.lua.globals(); g.NOW = g.NOW + seconds

    def chunks(self):
        events = self.lua.globals().EvertallyExportDB.events
        return [events[i] for i in range(1, len(events) + 1) if events[i].kind == "journey.chunk"]

    def moments(self):
        self.a.Journey.Flush()
        out = []
        for chunk in self.chunks():
            ms = chunk.payload.events
            out += [ms[i] for i in range(1, len(ms) + 1)]
        return out

    def test_nothing_is_recorded_without_the_consent_of_the_route(self):
        self.on(track=False)
        self.lua.execute("MONEY=900"); self.a.Dispatch("PLAYER_MONEY"); self.a.Dispatch("PLAYER_DEAD")
        self.assertEqual(self.moments(), [])

    def test_kills_come_from_the_experience_message_and_only_the_one_that_names_what_died(self):
        self.on()
        self.a.Dispatch("CHAT_MSG_COMBAT_XP_GAIN", "Thistle Bear dies, you gain 42 experience.")
        self.tick(); self.a.Dispatch("CHAT_MSG_COMBAT_XP_GAIN", "You gain 180 experience.")  # a quest: no kill
        self.tick(); self.a.Dispatch("CHAT_MSG_COMBAT_XP_GAIN", "something else entirely")
        kills = [m for m in self.moments() if m.k == "kill"]
        self.assertEqual(len(kills), 1)
        self.assertEqual((kills[0].text, kills[0].xp), ("Thistle Bear", 42))
        self.assertEqual((kills[0].mapId, kills[0].x, kills[0].y), (1429, 0.5, 0.5))

    def test_money_gained_and_spent_and_the_first_look_is_not_a_moment(self):
        self.on()
        self.lua.execute("MONEY=1036"); self.a.Dispatch("PLAYER_MONEY")
        self.tick(); self.lua.execute("MONEY=900"); self.a.Dispatch("PLAYER_MONEY")
        self.tick(); self.a.Dispatch("PLAYER_MONEY")  # no change
        money = [m for m in self.moments() if m.k == "money"]
        self.assertEqual([(m.n, m.text) for m in money], [(36, "Money"), (-136, "Spent")])

    def test_a_skill_up_carries_the_maximum_from_the_skill_list(self):
        self.on()
        self.a.Dispatch("CHAT_MSG_SKILL", "Your skill in Herbalism has increased to 94.")
        self.a.Dispatch("CHAT_MSG_SKILL", "Your skill in Fishing has increased to 5.")
        skills = [m for m in self.moments() if m.k == "skill"]
        self.assertEqual([(m.text, m.n, m.max) for m in skills], [("Herbalism", 94, 150), ("Fishing", 5, None)])

    def test_death_group_and_flight(self):
        self.on()
        self.a.Dispatch("PLAYER_DEAD")
        self.lua.execute("GROUPED=true; MEMBERS=3"); self.a.Dispatch("GROUP_ROSTER_UPDATE")
        self.a.Dispatch("GROUP_ROSTER_UPDATE")  # a change of members, not of the group
        self.lua.execute("GROUPED=false"); self.a.Dispatch("GROUP_ROSTER_UPDATE")
        by = [(m.k, m.a, m.text) for m in self.moments() if m.k != "state"]
        self.assertEqual(by, [("death", None, "You died"), ("group", "join", "Joined a group of 3"), ("group", "leave", "Left the group")])

    def test_moments_are_batched_and_a_long_session_makes_several_batches(self):
        self.on()
        for i in range(5):
            self.tick(); self.a.Dispatch("CHAT_MSG_COMBAT_XP_GAIN", f"Wolf {i} dies, you gain 10 experience.")
        self.tick(400); self.a.Dispatch("PLAYER_DEAD")  # a batch is a few minutes long
        self.a.Journey.Flush()
        chunks = self.chunks()
        self.assertEqual(len(chunks), 2)
        first = chunks[0].payload
        self.assertEqual(len(first.events), 6)  # initial state plus the five kills
        self.assertEqual(sum(first.events[i].k == "kill" for i in range(1, len(first.events) + 1)), 5)
        self.assertTrue(all(0 <= first.events[i].t <= 300 for i in range(1, len(first.events) + 1)))
        self.assertEqual(len(chunks[1].payload.events), 1)
        history = self.a.db.events
        self.assertEqual([history[i].kind for i in range(1, len(history) + 1) if history[i].kind == "journey.chunk"], [], "the batches stay out of the local history")

    def test_a_batch_never_exceeds_the_limit_of_the_website(self):
        self.on()
        for i in range(650): self.a.Dispatch("PLAYER_DEAD")
        self.a.Journey.Flush()
        sizes = [len(c.payload.events) for c in self.chunks()]
        self.assertTrue(all(n <= 300 for n in sizes), sizes)
        self.assertEqual(sum(sizes), 651)  # 650 deaths plus the initial state

    def test_a_new_consent_drops_what_was_not_yet_written(self):
        self.on()
        self.a.Dispatch("PLAYER_DEAD")
        self.a.SetWeb(True)  # a new policy starts an empty outbox
        self.assertEqual(self.moments(), [])

    def test_the_quality_of_loot_comes_from_the_colour_of_the_link(self):
        self.a.SetWeb(True); self.a.SetScope("world_facts", True)
        for colour, quality in (("ffffff", 1), ("0070dd", 3), ("ff8000", 5)):
            self.lua.execute("LOOT_ITEM_SELF='You receive loot: %s.'")
            self.a.Dispatch("CHAT_MSG_LOOT", f"You receive loot: |cff{colour}|Hitem:111|h[Thing]|h|r.")
            events = self.a.db.events
            self.assertEqual(events[len(events)].payload.quality, quality)


if __name__ == "__main__":
    unittest.main()
