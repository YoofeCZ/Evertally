"""Armory: stats and talents travel only after consent; "always" is remembered, never covers gold and can be revoked;
the website copy (armory.view) exists only when the player being looked at allowed it."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_addon  # noqa: E402

SocialTests = test_addon.SocialTests

ASKER = "Fixture Hero-Fixture Realm"
OWNER = "Other-Fixture Realm"

OWNER_API = """
UnitStat=function(unit,i) return 100+i,150+i,0,0 end
UnitArmor=function() return 1,1234 end
UnitAttackPower=function() return 100,20,-5 end
UnitRangedAttackPower=function() return 10,0,0 end
GetCritChance=function() return 5.25 end
GetSpellCritChance=function() return 3.5 end
GetDodgeChance=function() return 4.1 end
GetParryChance=function() return 5 end
GetBlockChance=function() return 0 end
UnitHealthMax=function() return 2400 end
UnitPowerMax=function() return 1800 end
UnitResistance=function(unit,i) return 0,i*10 end
GetNumTalentTabs=function() return 2 end
GetTalentTabInfo=function(tab) if tab==1 then return "Elemental",1,5 else return "Restoration",2,0 end end
GetNumTalents=function(tab) return tab==1 and 2 or 1 end
GetTalentInfo=function(tab,i)
  if tab==1 then return "Convection",2,1,i,(i==1 and 5 or 0),5 end
  return "Tidal Focus",3,1,1,0,5
end
"""


def events(lua, kind):
    store = lua.globals().EvertallyExportDB
    return [store.events[i] for i in range(1, len(store.events) + 1) if store.events[i].kind == kind]


class ArmoryTests(unittest.TestCase):
    setUp = SocialTests.setUp
    deliver = SocialTests.deliver
    A = SocialTests.A
    B = SocialTests.B

    def prepare(self):
        self.lua_b.execute(OWNER_API)
        self.a.SetWeb(True)

    def ask(self, kinds):
        ok, ident = self.a.RequestInspect(OWNER, kinds)
        self.assertTrue(ok)
        self.deliver(self.A, self.B, ASKER)
        return ident

    def answer(self, ident, allowed, always=False):
        result = self.b.AnswerRequest(ident, allowed, always)
        self.deliver(self.B, self.A, OWNER)
        return result

    def test_stats_and_talents_arrive_only_with_consent_and_are_parsed(self):
        self.prepare()
        ident = self.ask("istp")
        self.assertEqual(len(self.a.social.views), 0)
        self.answer(ident, "st")
        view = self.a.social.views[1]
        self.assertEqual(len(view.equipped), 0)  # gear was not allowed
        self.assertEqual((view.stats.str, view.stats.agi, view.stats.armor), (151, 152, 1234))
        self.assertEqual(view.stats.ap, 115)
        self.assertAlmostEqual(view.stats.crit, 5.3, places=1)
        self.assertEqual(view.talents[1].name, "Elemental")
        self.assertEqual((view.talents[1].spent, view.talents[1].ranks[1][1], view.talents[1].ranks[1][2], view.talents[1].ranks[1][3]), (5, 1, 5, "Convection"))
        self.assertEqual(len(events(self.lua_a, "armory.view")), 0)  # nobody asked to keep it on the website

    def test_website_copy_needs_the_owner_to_allow_it_and_never_contains_gold(self):
        self.prepare()
        ident = self.ask("istpgw")
        self.answer(ident, "istpg")  # gold yes, website no
        self.assertEqual(len(events(self.lua_a, "armory.view")), 0)
        self.a.social.outgoing = self.lua_a.table()
        self.lua_b.globals().NOW += 500; self.b.social.cooldown = self.lua_b.table()
        ident = self.ask("istpgw")
        self.answer(ident, "istpgw")
        views = events(self.lua_a, "armory.view")
        self.assertEqual(len(views), 1)
        payload = views[0].payload
        self.assertEqual((payload.subject.name, payload.subject.realm, payload.subject.classId, payload.mode), ("Other", "Fixture Realm", 7, "once"))
        self.assertEqual(payload.stats.str, 151)
        self.assertEqual(payload.equipped[1].itemId, 987654)
        self.assertIsNone(payload.gold)
        self.assertNotIn("g", payload.kinds)
        self.assertNotIn("w", payload.kinds)

    def test_the_asker_cannot_ask_for_a_website_copy_without_web_export(self):
        self.prepare()
        self.a.SetWeb(False)
        ok, ident = self.a.RequestInspect(OWNER, "istpw")
        self.assertTrue(ok)
        self.assertEqual(self.a.social.outgoing[ident].kinds, "istp")

    def test_identity_comes_from_the_whisper_not_from_the_payload(self):
        self.prepare()
        ok, ident = self.a.RequestInspect(OWNER, "istw")
        self.lua_a.execute("SENT={}")
        self.a.ReceiveMessage("Evtly1", "S|A|%s|istw|1|o" % ident, "WHISPER", OWNER)
        self.a.ReceiveMessage("Evtly1", "S|D|%s|1|1|I1;H=1:2:60:Other Realm;S=str:5" % ident, "WHISPER", OWNER)
        subject = events(self.lua_a, "armory.view")[0].payload.subject
        self.assertEqual((subject.name, subject.realm), ("Other", "Fixture Realm"))  # not the claimed realm
        self.assertEqual((subject.classId, subject.raceId, subject.level), (1, 2, 60))

    def test_always_is_remembered_skips_the_question_and_never_covers_gold(self):
        self.prepare()
        ident = self.ask("istpgw")
        self.answer(ident, "istpgw", True)
        trust = self.b.db.settings.socialTrust["fixture hero"]
        self.assertEqual(trust.kinds, "istpw")
        self.assertEqual(self.b.social.shown[1].mode, "always")
        self.assertEqual(events(self.lua_a, "armory.view")[0].payload.mode, "always")
        # the next request, even for gold, is answered at once with what was allowed for good
        self.a.social.outgoing = self.lua_a.table()
        self.lua_b.globals().NOW += 500
        ident = self.ask("istpgw")
        self.assertEqual(len(list(self.b.SocialRequests().items())), 0)  # no question
        self.deliver(self.B, self.A, OWNER)
        view = self.a.social.views[1]
        self.assertIsNone(view.gold)
        self.assertEqual(view.stats.str, 151)
        self.assertEqual(len(events(self.lua_a, "armory.view")), 2)
        # a request for gold alone is not covered and is asked
        self.a.social.outgoing = self.lua_a.table()
        self.lua_b.globals().NOW += 500
        self.ask("g")
        self.assertEqual(len(list(self.b.SocialRequests().items())), 1)

    def test_revoking_forgets_the_permission_and_withdraws_the_copy_on_the_other_side(self):
        self.prepare()
        ident = self.ask("istpw")
        self.answer(ident, "istpw", True)
        self.assertEqual(len(self.a.social.views), 1)
        self.assertTrue(self.b.RevokeAccess("Fixture Hero"))
        self.assertIsNone(self.b.db.settings.socialTrust["fixture hero"])
        self.deliver(self.B, self.A, OWNER)
        self.assertEqual(len(self.a.social.views), 0)
        tombstone = events(self.lua_a, "armory.revoked")
        self.assertEqual(len(tombstone), 1)
        self.assertEqual(tombstone[0].payload.name, "Other")
        # after the revoke the owner is asked again
        self.a.social.outgoing = self.lua_a.table()
        self.lua_b.globals().NOW += 500
        self.ask("istpw")
        self.assertEqual(len(list(self.b.SocialRequests().items())), 1)

    def test_a_stranger_cannot_flood_the_outbox_with_revoke_notices(self):
        self.prepare()
        for i in range(5):
            self.a.ReceiveMessage("Evtly1", "S|X|abcde%d" % i, "WHISPER", "Spammer-Fixture Realm")
        self.assertEqual(len(events(self.lua_a, "armory.revoked")), 1)  # one per player per 20 s

    def test_own_armory_is_exported_for_the_website(self):
        self.prepare()
        self.b.SetWeb(True)
        self.b.SendArmorySnapshot()
        snapshots = events(self.lua_b, "armory.snapshot")
        self.assertEqual(len(snapshots), 1)
        payload = snapshots[0].payload
        self.assertEqual(payload.stats.sta, 153)
        self.assertEqual(payload.talents[1].name, "Elemental")
        self.assertEqual({payload.equipped[1].slot, payload.equipped[2].slot}, {1, 5})
        self.assertIsNone(payload.gold)
        self.assertEqual(snapshots[0].character.name, "Other")


del SocialTests  # only borrowed for its setUp; its own tests run in test_addon


if __name__ == "__main__":
    unittest.main()
