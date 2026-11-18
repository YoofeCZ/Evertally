"""Notes to the player's group, signed "(via Evertally)". No game/network."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime

LUA = r'''
SENT={}; GROUP="party"
C_ChatInfo={SendChatMessage=function(msg,kind) SENT[#SENT+1]={msg=msg,kind=kind} end}
IsInRaid=function() return GROUP=="raid" end
IsInGroup=function(category) if GROUP=="none" then return false end;if category==2 then return GROUP=="instance" end;if category==1 then return GROUP=="party" or GROUP=="raid" end;return true end
GetTitleText=function() return "Finding the Antidote" end
C_QuestLog={GetTitleForQuestID=function() return nil end}
'''


class AnnounceTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(LUA)
        self.n = self.a.Announce
        # (the chronicle is public from the start since 2026-11-18; these messages are checked without its link, the test
        # about the link turns it on again)
        self.a.SetPublish("chronicle", False)

    def sent(self):
        s = self.lua.globals().SENT
        return [(s[i].msg, s[i].kind) for i in range(1, len(s) + 1)]

    def flush(self):
        for _ in range(10):
            self.lua.execute("CLOCK=CLOCK+3"); self.n.Pump()

    def test_on_by_default_signed_marked_blue_and_only_to_the_group(self):
        self.assertTrue(self.n.Enabled())
        self.a.Dispatch("PLAYER_LEVEL_UP", 21)
        self.assertEqual(self.sent(), [("{rt6} Level 21! (via Evertally)", "PARTY")])
        self.lua.execute('GROUP="none"')
        self.a.Dispatch("PLAYER_LEVEL_UP", 22); self.flush()
        self.assertEqual(len(self.sent()), 1, "alone: nothing, never /say")

    def test_raid_and_instance_groups_use_their_channel(self):
        self.lua.execute('GROUP="raid"'); self.assertEqual(self.n.Channel(), "RAID")
        self.lua.execute('GROUP="instance"'); self.assertEqual(self.n.Channel(), "INSTANCE_CHAT")

    def test_quest_title_comes_from_the_reward_window_and_the_chronicle_is_mentioned_only_when_public(self):
        self.a.db.settings.language = "cs"
        self.a.Dispatch("QUEST_COMPLETE"); self.a.Dispatch("QUEST_TURNED_IN", 123, 100, 0)
        self.assertEqual(self.sent()[0][0], "{rt6} Quest done: Finding the Antidote (via Evertally)", "always English, also with the Czech addon")
        self.a.SetWeb(True); self.a.SetScope("own_character", True)
        self.a.PublishChoice().public = True; self.a.PublishChoice().chronicle = True
        self.lua.execute("CLOCK=CLOCK+3")
        self.a.Dispatch("QUEST_COMPLETE"); self.a.Dispatch("QUEST_TURNED_IN", 124, 100, 0)
        self.assertIn("in my chronicle on evertally.afstudio.dev", self.sent()[1][0])

    def test_dungeon_time_boss_split_and_personal_best(self):
        self.lua.execute('INSIDE=true')
        self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.lua.execute("CLOCK=CLOCK+605")
        self.a.ObserveBoss(1, "Rhahk'Zor", 1)
        self.assertEqual(self.sent()[0][0], "{rt6} Rhahk'Zor down at 10:05 (via Evertally)")
        self.lua.execute("CLOCK=CLOCK+300")
        self.a.FinishRun("completed", "last_boss"); self.flush()
        self.assertEqual(self.sent()[1][0], "{rt6} The Deadmines cleared in 15:05 (via Evertally)")
        self.a.Dispatch("PLAYER_ENTERING_WORLD"); self.lua.execute("CLOCK=CLOCK+400")
        self.a.FinishRun("completed", "last_boss"); self.flush()
        self.assertIn("personal best", self.sent()[2][0])

    def test_the_switch_turns_everything_off_and_the_rate_is_bounded(self):
        self.n.SetEnabled(False)
        self.a.Dispatch("PLAYER_LEVEL_UP", 21)
        self.assertEqual(self.sent(), [])
        self.n.SetEnabled(True)
        for level in range(30, 40): self.a.Dispatch("PLAYER_LEVEL_UP", level)
        self.assertEqual(len(self.sent()), 1, "one at once, the rest wait their turn")
        self.flush()
        self.assertLessEqual(len(self.sent()), 9, "a burst is capped: one at once and eight waiting")

    def test_long_text_still_ends_with_the_signature(self):
        self.n.Say("x" * 400)
        message = self.sent()[0][0]
        self.assertLessEqual(len(message.encode("utf8")), 255)
        self.assertTrue(message.endswith("(via Evertally)"))

    def test_a_level_offers_bragging_and_only_a_click_says_it(self):
        self.lua.execute('GROUP="none"; INGUILD=true; IsInGuild=function() return INGUILD end')
        self.a.Dispatch("PLAYER_LEVEL_UP", 30)
        self.assertEqual(self.sent(), [], "nothing goes to /say by itself")
        self.assertEqual(self.n.pending, "{rt6} Just hit level 30! (via Evertally)")
        self.assertTrue(self.n.SayBrag("SAY"))
        self.assertEqual(self.sent(), [("{rt6} Just hit level 30! (via Evertally)", "SAY")])
        self.assertIsNone(self.n.pending, "said once, then gone")
        self.assertFalse(self.n.SayBrag("SAY"))

    def test_a_record_brags_with_the_chronicle_and_the_guild_button_needs_a_guild(self):
        self.lua.execute('INGUILD=false; IsInGuild=function() return INGUILD end')
        self.a.SetWeb(True); self.a.SetScope("own_character", True)
        self.a.PublishChoice().public = True; self.a.PublishChoice().chronicle = True
        self.lua.execute('INSIDE=true'); self.a.Dispatch("PLAYER_ENTERING_WORLD"); self.lua.execute("CLOCK=CLOCK+900")
        self.a.FinishRun("completed", "last_boss")
        self.assertEqual(self.n.pending, "{rt6} Cleared The Deadmines in 15:00! Follow my journey in my chronicle on evertally.afstudio.dev (via Evertally)")
        self.a.Dispatch("PLAYER_ENTERING_WORLD"); self.lua.execute("CLOCK=CLOCK+600")
        self.a.FinishRun("completed", "last_boss")
        self.assertIn("a new personal best", self.n.pending)
        self.assertFalse(self.n.SayBrag("GUILD"), "not in a guild")
        self.lua.execute('INGUILD=true')
        self.assertTrue(self.n.SayBrag("GUILD"))
        self.assertEqual(self.sent()[-1][1], "GUILD")

    def test_the_brag_offer_can_be_switched_off(self):
        self.n.SetBragEnabled(False)
        self.a.Dispatch("PLAYER_LEVEL_UP", 30)
        self.assertIsNone(self.n.pending)

    def test_the_bar_shows_the_message_and_its_say_button_sends_it(self):
        from test_addon import MOCK_UI_LUA
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(LUA)
        a.SetPublish("chronicle", False)   # (public from the start since 2026-11-18; the wording here is checked without its link)
        lua.execute('GROUP="none"')
        a.Dispatch("PLAYER_LEVEL_UP", 30)
        bar = lua.globals().EvertallyBragBar
        self.assertTrue(bar.IsShown(bar))
        from test_addon import ADDON
        self.assertIn('bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)', (ADDON / "Announce.lua").read_text(encoding="utf8"), "the offer sits in the middle of the screen")
        self.assertEqual(bar.text.text, "Just hit level 30! (via Evertally)")
        bar.say.scripts.OnClick(bar.say)
        sent = lua.globals().SENT
        self.assertEqual((sent[1].msg, sent[1].kind), ("{rt6} Just hit level 30! (via Evertally)", "SAY"))
        self.assertFalse(bar.IsShown(bar))

    def test_questie_and_questmaster_group_messages_are_turned_off_and_given_back(self):
        self.lua.execute('''PRINTED={};Evertally.Print=function(t) PRINTED[#PRINTED+1]=t end
          Questie={db={profile={questAnnounceChannel="party",questAnnounceObjectives=true}}}
          QuestMaster={db={profile={announce={accept=false,complete=true,progressGroup=true,levelUpChat=true,levelUp=true,completeChannel="PARTY"}}}}''')
        changed = self.n.QuietOthers()
        self.assertEqual(list(changed.values()), ["Questie", "QuestMaster"])
        g = self.lua.globals()
        self.assertEqual(g.Questie.db.profile.questAnnounceChannel, "disabled")
        qm = g.QuestMaster.db.profile.announce
        self.assertEqual((qm.complete, qm.progressGroup, qm.levelUpChat, qm.accept), (False, False, False, False))
        self.assertTrue(qm.levelUp, "their own level-up line for the player stays")
        self.assertEqual(len(g.PRINTED), 1)
        self.assertEqual(len(self.n.QuietOthers()), 0, "nothing to do the second time, and no second note")
        self.n.SetEnabled(False)
        self.assertEqual(g.Questie.db.profile.questAnnounceChannel, "party")
        self.assertEqual((qm.complete, qm.progressGroup, qm.levelUpChat, qm.accept), (True, True, True, False))
        self.n.SetEnabled(True)
        self.assertEqual(g.Questie.db.profile.questAnnounceChannel, "disabled")

    def test_without_the_other_addons_nothing_happens(self):
        self.assertEqual(len(self.n.QuietOthers()), 0)

    def test_accepted_objectives_done_and_handed_in_are_all_announced_once(self):
        self.lua.execute("""LOG={}
          C_QuestLog={GetTitleForQuestID=function(id) return id==77 and "Finding the Antidote" or nil end,
            GetNumQuestLogEntries=function() return #LOG end,
            GetInfo=function(i) return LOG[i] end,
            IsComplete=function(id) for _,q in ipairs(LOG) do if q.questID==id then return q.done==true end end;return false end}
          LOG={{questID=50,title="Old Business",done=true}}""")
        self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.a.Dispatch("QUEST_LOG_UPDATE")
        self.assertEqual(self.sent(), [], "a quest already complete before entering the world is not announced")
        self.lua.execute('LOG[2]={questID=77,title="Finding the Antidote"}')
        self.a.Dispatch("QUEST_ACCEPTED", 77); self.flush()
        self.lua.execute("LOG[2].done=true")
        self.a.Dispatch("QUEST_LOG_UPDATE"); self.a.Dispatch("QUEST_LOG_UPDATE"); self.flush()
        self.a.Dispatch("QUEST_COMPLETE"); self.a.Dispatch("QUEST_TURNED_IN", 77, 100, 0); self.flush()
        self.assertEqual([m for m, _ in self.sent()], [
            "{rt6} Quest accepted: Finding the Antidote (via Evertally)",
            "{rt6} Quest objectives done: Finding the Antidote (via Evertally)",
            "{rt6} Quest done: Finding the Antidote (via Evertally)"])

    def test_each_finished_objective_is_announced_but_not_every_step(self):
        self.lua.execute("""OBJ={{text="Venom Sac: 3/8",finished=false,numFulfilled=3,numRequired=8},{text="Kill Snapjaw",finished=false,numFulfilled=0,numRequired=1}}
          LOG={{questID=77,title="Finding the Antidote"}}
          C_QuestLog={GetTitleForQuestID=function() return nil end,GetNumQuestLogEntries=function() return #LOG end,GetInfo=function(i) return LOG[i] end,
            IsComplete=function() return OBJ[1].finished and OBJ[2].finished end,GetQuestObjectives=function() return OBJ end}""")
        self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.lua.execute('OBJ[1].text="Venom Sac: 5/8";OBJ[1].numFulfilled=5'); self.a.Dispatch("QUEST_LOG_UPDATE"); self.flush()
        self.assertEqual(self.sent(), [], "a step on the way is not announced")
        self.lua.execute('OBJ[1].text="Venom Sac: 8/8";OBJ[1].numFulfilled=8;OBJ[1].finished=true'); self.a.Dispatch("QUEST_LOG_UPDATE"); self.flush()
        self.lua.execute('OBJ[2].finished=true;OBJ[2].numFulfilled=1'); self.a.Dispatch("QUEST_LOG_UPDATE"); self.flush()
        self.assertEqual([m for m, _ in self.sent()], [
            "{rt6} Finding the Antidote: Venom Sac: 8/8 (via Evertally)",
            "{rt6} Quest objectives done: Finding the Antidote (via Evertally)"], "the last objective is told by 'objectives done'")

    def test_the_offer_can_be_switched_off_from_the_bar_itself(self):
        from test_addon import MOCK_UI_LUA
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(LUA)
        lua.execute('GROUP="none";PRINTED={};Evertally.Print=function(t) PRINTED[#PRINTED+1]=t end')
        a.Dispatch("PLAYER_LEVEL_UP", 30)
        bar = lua.globals().EvertallyBragBar
        self.assertEqual(bar.never.text.text, a.L("bragNever"))
        bar.never.scripts.OnClick(bar.never)
        self.assertFalse(bar.IsShown(bar))
        self.assertFalse(a.Announce.BragEnabled())
        self.assertEqual(lua.globals().PRINTED[1], a.L("bragOff"))
        a.Dispatch("PLAYER_LEVEL_UP", 31)
        self.assertFalse(bar.IsShown(bar), "no more offers")
        self.assertEqual(len(lua.globals().SENT), 0)

    def test_texts_in_both_languages(self):
        for lang in ("en", "cs"):
            for key in ("partyAnnounce", "annVia", "annQuest", "annChronicle", "annRun", "annBoss", "annLevel", "annUpgrade"):
                self.assertTrue(self.a.locale[lang][key], (lang, key))


if __name__ == "__main__":
    unittest.main()
