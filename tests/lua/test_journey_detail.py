"""Detailed chronicle observations, replayed with public/secret API fixtures (no running game or SavedVariables)."""
import json
import unittest
from test_addon import runtime


class DetailedJourneyTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute('''
          COMBATLOG_XPGAIN_FIRSTPERSON="%s dies, you gain %d experience."
          TARGET="Plainstrider"; TARGETPLAYER=false; TARGETDEAD=false; GROUPED=false; MEMBERS=1; RAID=false; MOUNTED=false
          UnitExists=function(unit) return unit=="player" or unit=="target" or unit=="party1" end
          UnitGUID=function(unit) if unit=="player" then return "Player-TEST-own" elseif unit=="party1" then return "Player-friend" elseif unit=="target" then return "Creature-0-0-0-0-2955-0" end end
          UnitName=function(unit) return unit=="target" and TARGET or unit=="party1" and "Friend" or "Fixture Hero" end
          UnitFullName=function(unit) return unit=="party1" and "Friend" or "Fixture Hero","Fixture Realm" end
          UnitCanAttack=function(_,unit) return unit=="target" end
          UnitIsPlayer=function(unit) return unit=="target" and TARGETPLAYER end
          UnitIsDeadOrGhost=function(unit) return unit=="target" and TARGETDEAD end
          IsInGroup=function() return GROUPED end;IsInRaid=function() return RAID end
          GetNumGroupMembers=function() return MEMBERS end
          IsMounted=function() return MOUNTED end
          UnitOnTaxi=function() return false end;IsFlying=function() return false end;IsSwimming=function() return false end
          GetMoney=function() return 1000 end
          MAPID=1412;C_Map={GetBestMapForUnit=function() return MAPID end,GetPlayerMapPosition=function() return {GetXY=function() return 0.466,0.796 end} end}
          GetSpellInfo=function(id) return id==78 and "Heroic Strike" or "Spell "..id end
          HOOKS={};JumpOrAscendStart=function() end;ORIGINAL_JUMP=JumpOrAscendStart
          UseItemByName=function() end;UseInventoryItem=function() end
          GetItemInfo=function(id) return id==117 and "Tough Jerky" or "Item "..id end
          GetInventoryItemID=function() return 117 end
          C_Container={UseContainerItem=function() end,GetContainerItemID=function() return 117 end}
          hooksecurefunc=function(first,second,third) if type(first)=="table" then HOOKS[second]=third else HOOKS[first]=second end end
        ''')

    def on(self, character=True):
        self.a.SetWeb(True)
        if not character:
            self.a.SetScope("own_character", False)
        self.a.SetScope("own_track", True)
        self.a.Dispatch("PLAYER_ENTERING_WORLD")

    def advance(self, seconds):
        g = self.lua.globals()
        g.NOW += seconds
        g.CLOCK += seconds

    def events(self):
        self.a.Journey.Flush()
        return json.loads(self.a.Encode(self.lua.globals().EvertallyExportDB.events))

    def moments(self, kind=None):
        rows = [m for e in self.events() if e["kind"] == "journey.chunk" for m in e["payload"]["events"]]
        return [m for m in rows if kind is None or m["k"] == kind]

    def begin(self):
        self.lua.execute("INCOMBAT=true")
        self.a.Dispatch("PLAYER_REGEN_DISABLED")

    def end(self):
        self.lua.execute("INCOMBAT=false")
        self.a.Dispatch("PLAYER_REGEN_ENABLED")

    def native(self, secret=False):
        self.lua.execute('''
          Enum={DamageMeterType={DamageDone=0,HealingDone=2,DamageTaken=7}}
          SESSIONS={{sessionID=10,durationSeconds=60}};METERS={};METER_READS_IN_COMBAT=0
          C_DamageMeter={GetAvailableCombatSessions=function() return SESSIONS end,
            GetCombatSessionFromID=function(id,kind)
              if INCOMBAT then METER_READS_IN_COMBAT=METER_READS_IN_COMBAT+1;error("not public during combat") end
              return METERS[id] and METERS[id][kind]
            end,
            GetCombatSessionSourceFromID=function(id,kind,guid)
              if INCOMBAT then METER_READS_IN_COMBAT=METER_READS_IN_COMBAT+1;error("not public during combat") end
              if id==11 and kind==0 and guid=="Player-TEST-own" then return {combatSpells={{spellID=78,totalAmount=100}}} end
            end}
        ''')
        self.secret = secret

    def fill_native(self):
        self.lua.execute('''
          SESSIONS[2]={sessionID=11,durationSeconds=12}
          METERS[10]={[0]={combatSources={{sourceGUID="Player-TEST-own",isLocalPlayer=true,totalAmount=99999}}}}
          METERS[11]={[0]={combatSources={{sourceGUID="Player-TEST-own",isLocalPlayer=true,totalAmount=100}}},
            [2]={combatSources={}},[7]={combatSources={{sourceGUID="Player-TEST-own",isLocalPlayer=true,totalAmount=24}}}}
        ''')
        if self.secret:
            self.lua.execute("METERS[11][0].combatSources[1].totalAmount=SECRET")

    def test_plainstrider_creates_a_real_interval_even_without_a_meter(self):
        self.on(); self.begin(); self.advance(12)
        self.a.Dispatch("CHAT_MSG_COMBAT_XP_GAIN", "Plainstrider dies, you gain 52 experience.")
        self.end()
        fights = self.moments("combat")
        self.assertEqual([m["a"] for m in fights], ["start", "end"])
        self.assertEqual(fights[0]["fightId"], fights[1]["fightId"])
        self.assertEqual((fights[1]["text"], fights[1]["d"], fights[1]["result"]), ("Plainstrider", 12, "kill"))
        self.assertEqual(fights[1]["summary"]["coverage"], "unavailable")
        self.assertNotIn("damage", fights[1]["summary"])
        self.assertNotIn("damage", fights[1]["summary"]["players"][0])
        self.assertIsNone(self.a.ActiveRun(), "the journey recorder does not create/replace the dungeon run")
        self.assertEqual(self.moments("kill")[0]["fightId"], fights[0]["fightId"])

    def test_regen_alone_does_not_mean_the_target_was_killed(self):
        self.on(); self.begin(); self.advance(3); self.end()
        self.assertEqual(self.moments("combat")[-1]["result"], "ended")

    def test_public_native_session_excludes_old_fights_and_keeps_real_spell_totals(self):
        self.native(); self.on(); self.begin(); self.advance(12); self.fill_native(); self.end()
        summary = self.moments("combat")[-1]["summary"]
        self.assertEqual(summary["coverage"], "observed")
        self.assertEqual((summary["damage"], summary["healing"], summary["damageTaken"]), (100, 0, 24))
        own = summary["players"][0]
        self.assertEqual(own["dealt"], [{"id": 78, "name": "Heroic Strike", "total": 100}])
        self.assertNotIn("casts", own["dealt"][0], "the meter has no cast count, so one is not invented")
        self.assertEqual(self.lua.globals().METER_READS_IN_COMBAT, 0)
        self.a.Dispatch("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 11)
        self.assertEqual(len([m for m in self.moments("combat") if m["a"] == "end"]), 1)

    def test_secret_native_amount_is_unknown_instead_of_zero(self):
        self.native(secret=True); self.on(); self.begin(); self.advance(12); self.fill_native(); self.end()
        summary = self.moments("combat")[-1]["summary"]
        self.assertEqual(summary["coverage"], "partial")
        self.assertNotIn("damage", summary)
        self.assertNotIn("damage", summary["players"][0])
        self.assertEqual(self.lua.globals().METER_READS_IN_COMBAT, 0)

    def test_native_row_can_arrive_after_regen_without_changing_the_recorded_end_time(self):
        self.native(); self.on(); self.begin(); self.advance(12)
        self.lua.execute("DEFERRED={};C_Timer={After=function(_,callback)DEFERRED[#DEFERRED+1]=callback end}")
        self.end()
        self.advance(0.7); self.a.Journey.FinalizeCombat(False)
        self.fill_native(); self.advance(0.7); self.a.Journey.FinalizeCombat(False)
        end = self.moments("combat")[-1]
        self.assertEqual(end["d"], 12)
        self.assertEqual(end["t"], 12)
        self.assertEqual(end["summary"]["damage"], 100)

    def test_run_scoped_meter_keeps_its_own_state_while_journey_records_the_same_combat(self):
        self.native(); self.lua.execute("INSIDE=true")
        self.on(); run = self.a.ActiveRun(); self.assertIsNotNone(run)
        self.begin(); self.advance(12); self.fill_native(); self.end()
        self.a.Combat.Snapshot(run)
        self.assertEqual(run.combat.damage, 100)
        self.assertEqual(self.moments("combat")[-1]["summary"]["damage"], 100)
        self.assertEqual(self.a.ActiveRun().runId, run.runId)

    def test_pvp_and_boss_classification_use_actual_observed_context(self):
        self.lua.execute("TARGETPLAYER=true;TARGET='Opponent'")
        self.on(); self.begin(); self.advance(2); self.end()
        self.assertEqual(self.moments("combat")[-1]["encounterKind"], "pvp")
        self.lua.execute("TARGETPLAYER=false")
        self.begin(); self.a.Dispatch("ENCOUNTER_START", 7, "Boss", 1, 5)
        self.advance(5); self.a.Dispatch("ENCOUNTER_END", 7, "Boss", 1, 5, 1); self.end()
        last = self.moments("combat")[-1]
        self.assertEqual((last["encounterKind"], last["text"], last["result"]), ("boss", "Boss", "kill"))

    def test_own_actions_are_recorded_outside_combat_without_patching_game_globals(self):
        self.on()
        self.a.Dispatch("UNIT_SPELLCAST_START", "player", "Cast-1", 78)
        self.a.Dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 78)
        self.a.Dispatch("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-2", 78)
        self.lua.globals().HOOKS.JumpOrAscendStart()
        self.lua.execute("MOUNTED=true"); self.a.Dispatch("PLAYER_MOUNT_DISPLAY_CHANGED")
        self.lua.globals().HOOKS.UseItemByName(117)
        self.advance(1); self.lua.globals().HOOKS.UseContainerItem(0, 1)
        actions = self.moments("action")
        self.assertEqual([m["a"] for m in actions], ["cast_start", "cast", "jump", "mount", "item_attempt", "item_attempt"])
        self.assertTrue(all("fightId" not in m for m in actions))
        self.assertEqual(actions[1]["text"], "Heroic Strike")
        self.assertEqual(actions[-1]["id"], 117)
        self.assertIn("outcome not recorded", actions[-1]["detail"])
        self.assertTrue(self.lua.eval("JumpOrAscendStart==ORIGINAL_JUMP"))
        self.assertIsNone(self.a.handlers["COMBAT_LOG_EVENT_UNFILTERED"])

    def test_aura_baseline_gain_refresh_loss_and_known_empty_state(self):
        self.lua.execute('''
          AURAS={HELPFUL={},HARMFUL={}}
          C_UnitAuras={GetAuraDataByIndex=function(_,i,filter)return AURAS[filter][i]end}
        ''')
        self.on(); self.a.Journey.SnapshotState()
        self.assertEqual(len(self.moments("state")), 1, "unchanged state is not recorded repeatedly")
        self.lua.execute('AURAS.HELPFUL[1]={spellId=1243,name="Fortitude",applications=1,duration=1800,expirationTime=CLOCK+1800,icon=135987}')
        self.a.Dispatch("UNIT_AURA", "player")
        self.lua.execute("AURAS.HELPFUL[1].applications=2;AURAS.HELPFUL[1].expirationTime=CLOCK+1805")
        self.a.Dispatch("UNIT_AURA", "player")
        self.lua.execute("AURAS.HELPFUL={}"); self.a.Dispatch("UNIT_AURA", "player")
        auras = self.moments("aura")
        self.assertEqual([m["a"] for m in auras], ["gain", "refresh", "loss"])
        self.assertEqual((auras[0]["id"], auras[0]["helpful"], auras[0]["icon"]), (1243, True, 135987))
        final = self.moments("state")[-1]
        self.assertTrue(final["aurasKnown"])
        self.assertEqual(final["auras"], [])

    def test_casts_keep_real_icons_actor_and_sent_target_and_deduplicate_visible_units(self):
        self.lua.execute('''
          C_Spell={GetSpellInfo=function(id)return {name=id==78 and "Heroic Strike" or "Fireball",iconID=132282}end}
          UnitAffectingCombat=function()return INCOMBAT end
          UnitIsFriend=function(_,unit)return unit=="party1"end
        ''')
        self.on()
        self.a.Dispatch("UNIT_SPELLCAST_SENT", "player", "Plainstrider", "Cast-own", 78)
        self.begin()
        self.a.Dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-own", 78)
        self.a.Dispatch("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-enemy", 133)
        self.a.Dispatch("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-enemy", 133)
        self.a.Dispatch("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-friend", 133)
        actions = self.moments("action")
        self.assertEqual(len(actions), 3)
        self.assertEqual((actions[0]["icon"], actions[0]["actor"], actions[0]["target"]), (132282, "Fixture Hero", "Plainstrider"))
        self.assertEqual([m["actorSide"] for m in actions], ["me", "enemy", "party"])
        self.assertEqual(actions[1]["actor"], "Plainstrider")
        self.assertEqual(self.moments("combat")[0]["npcId"], 2955)
        self.assertTrue(all("amount" not in m for m in actions), "spell success does not invent hit damage")

    def test_other_actor_casts_require_character_scope_and_an_active_fight(self):
        self.lua.execute('UnitAffectingCombat=function()return true end')
        self.on(character=False)
        self.begin()
        self.a.Dispatch("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-enemy", 133)
        self.a.Dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-own", 78)
        actions = self.moments("action")
        self.assertEqual(len(actions), 1)
        self.assertNotIn("actor", actions[0])

    def test_restricted_aura_snapshot_is_not_reported_as_a_known_empty_list(self):
        self.lua.execute('C_UnitAuras={GetAuraDataByIndex=function()return SECRET end}')
        self.on()
        state = self.moments("state")[-1]
        self.assertFalse(state["aurasKnown"])
        self.assertNotIn("auras", state)
        self.assertEqual(self.moments("aura"), [])

    def test_partial_aura_scan_cannot_export_a_false_complete_list(self):
        self.lua.execute('''C_UnitAuras={GetAuraDataByIndex=function(_,i,filter)
          if filter=="HELPFUL" and i==1 then return {spellId=1243,name="Fortitude",icon=0} end
          if filter=="HELPFUL" and i==2 then return SECRET end
        end}''')
        self.on()
        state = self.moments("state")[-1]
        self.assertFalse(state["aurasKnown"])
        self.assertNotIn("auras", state)

    def test_own_attributes_and_party_leave_are_time_ordered_snapshots(self):
        self.lua.execute('UnitStat=function(_,i)return 10,10+i end;UnitArmor=function()return 40,50 end')
        self.on()
        self.lua.execute("GROUPED=true;MEMBERS=2"); self.a.Dispatch("GROUP_ROSTER_UPDATE")
        self.lua.execute("GROUPED=false;MEMBERS=0"); self.a.Dispatch("GROUP_ROSTER_UPDATE")
        states = self.moments("state")
        self.assertEqual([m["groupType"] for m in states], ["solo", "party", "solo"])
        self.assertEqual(len(states[1]["roster"]), 2)
        self.assertEqual(len(states[-1]["roster"]), 1)
        self.assertIn(["Strength", 11], states[0]["attrs"])

    def test_missing_character_scope_strips_nested_roster_stats_and_identity(self):
        self.on(character=False)
        self.a.Journey.Add("state", self.lua.table_from({"text": "State", "attrs": self.lua.table_from([self.lua.table_from(["Strength", 11])]),
            "roster": self.lua.table_from([self.lua.table_from({"guid": "Player-friend", "name": "Friend"})])}))
        self.lua.execute('''
          Evertally.Journey.Add("combat",{a="end",fightId="privacy",text="Opponent",encounterKind="pvp",d=1,result="ended",summary={
            source="damage_meter",coverage="observed",coveredMs=1000,activeMs=1000,
            players={{guid="Player-TEST-own",name="Fixture Hero",damage=7},{guid="Player-friend",name="Friend",damage=8}}}})
        ''')
        events = [e for e in self.events() if e["kind"] == "journey.chunk"]
        for event in events:
            for moment in event["payload"]["events"]:
                self.assertNotIn("roster", moment)
                self.assertNotIn("attrs", moment)
                if "summary" in moment:
                    self.assertEqual(moment["text"], "PvP")
                    players = moment["summary"]["players"]
                    self.assertEqual(len(players), 1)
                    self.assertEqual(players[0]["guid"], event["character"]["id"])
                    self.assertNotIn("name", players[0])

    def test_nested_state_batches_stay_below_200_kib_and_do_not_lose_moments(self):
        self.on()
        self.lua.execute('''
          for n=1,30 do
            local rows,auras={},{}
            for i=1,40 do rows[i]={guid="Player-"..i,name=string.rep("R",100),classId=1} end
            for i=1,80 do auras[i]={id=i,text=string.rep("B",120),helpful=i<=40,duration=100,expiresAt=NOW+100} end
            Evertally.Journey.Add("state",{text="State "..n,roster=rows,auras=auras,aurasKnown=true})
          end
        ''')
        events = [e for e in self.events() if e["kind"] == "journey.chunk"]
        self.assertEqual(sum(len(e["payload"]["events"]) for e in events), 31)
        self.assertTrue(all(len(json.dumps(e["payload"]).encode("utf-8")) < 200 * 1024 for e in events))

    def test_sidebar_snapshots_include_wallet_played_identity_full_skills_and_enhancements(self):
        self.lua.execute('''
          GetMoney=function()return 123456 end;GetCritChance=function()return 12.5 end;GetHaste=function()return 5.2 end
          UnitStat=function(_,i)return 10,10+i end;UnitFactionGroup=function()return "Horde" end
          IsInGuild=function()return true end;GetGuildInfo=function()return "Recorded Guild" end
          GetAverageItemLevel=function()return 30,28 end
          GetInventoryItemID=function(_,slot)if slot==16 then return 117 end end
          Evertally.CollectTalents=function()return {{name="Arms",spent=17}} end
          TRADE_SKILLS="Professions";GetNumSkillLines=function()return 4 end
          GetSkillLineInfo=function(i)
            if i==1 then return "Professions",true end
            if i==2 then return "Herbalism",false,false,54,0,0,75 end
            if i==3 then return "Weapon Skills",true end
            if i==4 then return "Defense",false,false,20,0,0,100 end
          end
        ''')
        self.on(); self.a.Dispatch("TIME_PLAYED_MSG", 144000)
        state = self.moments("state")[-1]
        self.assertEqual((state["copper"],state["played"],state["guild"],state["faction"],state["spec"],state["ilvl"]), (123456,144000,"Recorded Guild","Horde","Arms",28))
        self.assertEqual(state["skills"], {"Herbalism":[54,75],"Defense":[20,100]})
        self.assertEqual(state["professions"], ["Herbalism"])
        self.assertEqual(state["equipped"], [{"slot":16,"itemId":117}])
        self.assertIn(["Melee crit %","12.5%"],state["enh"])
        self.assertIn(["Haste","5.2%"],state["enh"])
        self.advance(6); self.a.Journey.SnapshotState()
        self.assertEqual(len(self.moments("state")),2,"elapsed time alone does not repeat a full state snapshot")
        self.a.SetScope("own_character",False); self.a.Journey.SnapshotState()
        for moment in self.moments("state"):
            for key in ["copper","played","guild","race","faction","spec","skills","professions","equipped"]:
                self.assertNotIn(key,moment)

    def test_npc_dialogue_keeps_the_full_observed_text_but_no_player_whispers(self):
        self.on()
        message="This is a full NPC line. "*20
        self.a.Dispatch("CHAT_MSG_MONSTER_SAY",message,"Recorded Speaker")
        self.a.Dispatch("CHAT_MSG_RAID_BOSS_EMOTE","|cffff0000The boss prepares a spell!|r","Boss")
        self.a.Dispatch("CHAT_MSG_MONSTER_SAY",self.lua.globals().SECRET,"Secret")
        self.a.Dispatch("CHAT_MSG_WHISPER","Private player text","Another player")
        rows=self.moments("speech")
        self.assertEqual(len(rows),2)
        self.assertEqual((rows[0]["message"],rows[0]["speaker"],rows[0]["a"]),(message,"Recorded Speaker","say"))
        self.assertEqual(rows[1]["message"],"The boss prepares a spell!")
        self.a.SetScope("own_character",False)
        self.a.Dispatch("CHAT_MSG_MONSTER_SAY","Potentially identifies the player","Speaker")
        self.assertEqual(self.moments("speech"),[])

    def test_fight_records_observed_difficulty_and_group_size(self):
        self.on()
        self.lua.execute('INSIDE=true;GROUPED=true;MEMBERS=2;GetInstanceInfo=function()return "Recorded Dungeon","party",2,"Heroic",5 end')
        self.begin();self.advance(5);self.end()
        for row in self.moments("combat"):
            self.assertEqual((row["difficulty"],row["size"]),("Heroic",2))

    def test_revoked_consent_drops_an_unfinished_fight(self):
        self.on(); self.begin(); self.advance(3)
        self.a.SetScope("own_track", False)
        self.end()
        self.assertEqual(self.moments(), [])


if __name__ == "__main__":
    unittest.main()
