"""Run-scoped meter snapshots, actor attribution, missing data and final combat."""
import unittest
from test_addon import runtime


class CombatRunTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute('''
          INSIDE=true;GetNumGroupMembers=function() return 2 end
          UnitGUID=function(unit) if unit=="player" then return "Player-TEST-own" elseif unit=="party1" then return "Player-healer" end end
          UnitFullName=function(unit) return unit=="party1" and "Healer" or "Fixture Hero","Fixture Realm" end
          UnitGroupRolesAssigned=function(unit) return unit=="party1" and "HEALER" or "DAMAGER" end
          Enum={DamageMeterType={DamageDone=0,HealingDone=2,Absorbs=4,DamageTaken=7,Interrupts=5,Dispels=6}}
          SESSIONS={{sessionID=10,durationSeconds=30}};METERS={}
          C_DamageMeter={GetAvailableCombatSessions=function() return SESSIONS end,
            GetCombatSessionFromID=function(id,kind) return METERS[id] and METERS[id][kind] end}
        ''')
        self.a.RefreshInstance()

    def add_session(self):
        self.lua.execute('''
          SESSIONS[2]={sessionID=11,durationSeconds=10}
          METERS[10]={[0]={durationSeconds=30,combatSources={{sourceGUID="Player-TEST-own",totalAmount=99999}}}}
          METERS[11]={
            [0]={durationSeconds=10,combatSources={{sourceGUID="Player-TEST-own",totalAmount=1000,isLocalPlayer=true},{sourceGUID="Player-healer",totalAmount=100}}},
            [2]={durationSeconds=10,combatSources={{sourceGUID="Player-healer",totalAmount=800}}},
            [7]={durationSeconds=10,combatSources={{sourceGUID="Player-TEST-own",totalAmount=300}}}}
          CLOCK=CLOCK+10
        ''')

    def test_native_sessions_exclude_pre_instance_fights_and_repeated_updates_do_not_double_count(self):
        self.add_session()
        run = self.a.ActiveRun()
        self.a.Combat.Snapshot(run)
        self.a.Combat.Snapshot(run)
        self.assertEqual(run.combat.damage, 1100)
        self.assertEqual(run.combat.healing, 800)
        self.assertEqual(run.combat.activeMs, 10000)
        players = {p.guid: p for _, p in run.combat.players.items()}
        self.assertEqual(players["Player-TEST-own"].damage, 1000)
        self.assertEqual(players["Player-healer"].healing, 800)
        self.assertEqual(players["Player-healer"].role, "HEALER")
        self.assertEqual(len(run.roster), 2)

    def test_missing_or_secret_values_are_unrecorded_instead_of_rankable_zero(self):
        run = self.a.ActiveRun()
        self.assertEqual(run.combat.coverage, "unavailable")
        self.assertIsNone(run.combat.damage)
        self.add_session()
        self.lua.execute('METERS[11][0].combatSources[1].totalAmount=SECRET')
        self.a.Combat.Snapshot(run)
        self.assertEqual(run.combat.coverage, "partial")
        players = {p.guid: p for _, p in run.combat.players.items()}
        self.assertIsNone(players["Player-TEST-own"].damage)
        self.assertIsNone(run.combat.damage)

    def test_finishing_during_combat_collects_final_public_session_after_combat(self):
        self.add_session()
        run = self.a.ActiveRun()
        self.lua.execute("INCOMBAT=true")
        self.a.FinishRun("completed", "last_boss")
        self.assertEqual(self.a.db.runs[1].combat.coverage, "unavailable")
        self.lua.execute("INCOMBAT=false;CLOCK=CLOCK+1")
        self.a.Combat.FinalizePending()
        self.assertEqual(self.a.db.runs[1].combat.damage, 1100)
        self.assertEqual(self.a.db.runs[1].combat.activeMs, 10000)
        self.assertIsNone(self.a.ActiveRun())

    def test_peer_summary_shares_owner_stats_without_a_full_raid_roster(self):
        self.add_session()
        self.a.FinishRun("completed", "last_boss")
        summary = self.a.MakeSummary()
        run = summary.runs[1]
        self.assertIsNone(run.roster)
        self.assertEqual(len(run.combat.players), 1)
        self.assertEqual(run.combat.players[1].guid, "Player-TEST-own")
        self.assertEqual(run.combat.players[1].damage, 1000)
        self.assertEqual(run.combat.damage, 1100, "group totals are preserved with explicit attribution")

    def test_legacy_log_uses_effective_healing_and_does_not_include_overkill(self):
        self.a.FinishRun("interrupted")
        self.lua.execute("C_DamageMeter=nil;CombatLogGetCurrentEventInfo=function() end;INCOMBAT=true")
        self.a.RefreshInstance()
        self.lua.execute('''
          Evertally.Combat.ObserveLog(100,"SPELL_DAMAGE",false,"Player-TEST-own","Me",0,0,"Creature-enemy","Mob",0,0,133,"Fireball",4,1200,200)
          Evertally.Combat.ObserveLog(100,"SPELL_HEAL",false,"Player-healer","Healer",0,0,"Player-TEST-own","Me",0,0,2061,"Heal",2,900,100)
          CLOCK=CLOCK+10
        ''')
        self.a.Combat.Snapshot(self.a.ActiveRun())
        combat = self.a.ActiveRun().combat
        self.assertEqual(combat.damage, 1000)
        self.assertEqual(combat.healing, 800)
        self.assertEqual(combat.overhealing, 100)
        self.assertEqual(combat.activeMs, 10000)

    def test_disabling_character_export_removes_roster_and_actor_names_but_keeps_own_pseudonymous_metrics(self):
        self.add_session()
        self.a.SetWeb(True)
        self.a.SetScope("own_character", False)
        self.a.FinishRun("completed", "last_boss")
        events = [e for _,e in self.a.ExportStore().events.items() if e.kind == "run.finished"]
        self.assertTrue(events)
        event=events[-1]
        self.assertIsNone(event.payload.roster)
        self.assertEqual(len(event.payload.combat.players),1)
        self.assertIsNone(event.payload.combat.players[1].name)
        self.assertEqual(event.payload.combat.players[1].guid,event.character.id)
        self.assertEqual(event.payload.combat.players[1].damage,1000)

    def test_health_and_player_dead_events_do_not_double_count_one_death(self):
        self.lua.execute('''
          DEAD=false;UnitIsDeadOrGhost=function() return DEAD end
          Evertally.Combat.Roster(Evertally.ActiveRun())
          DEAD=true
          for _,fn in ipairs(Evertally.handlers.UNIT_HEALTH) do fn("player") end
          for _,fn in ipairs(Evertally.handlers.PLAYER_DEAD) do fn() end
        ''')
        self.a.Combat.Snapshot(self.a.ActiveRun())
        players={p.guid:p for _,p in self.a.ActiveRun().combat.players.items()}
        self.assertEqual(players["Player-TEST-own"].deaths,1)
        self.assertEqual(self.a.ActiveRun().deaths,1)

    def test_idle_self_healing_does_not_become_dungeon_hps(self):
        self.a.FinishRun("interrupted")
        self.lua.execute('''
          C_DamageMeter=nil;CombatLogGetCurrentEventInfo=function() end;INCOMBAT=false
          Evertally.RefreshInstance()
          Evertally.Combat.ObserveLog(100,"SPELL_HEAL",false,"Player-TEST-own","Me",0,0,"Player-TEST-own","Me",0,0,2061,"Heal",2,900,0)
          CLOCK=CLOCK+10
        ''')
        self.a.Combat.Snapshot(self.a.ActiveRun())
        self.assertIsNone(self.a.ActiveRun().combat.healing)
        self.assertEqual(self.a.ActiveRun().combat.activeMs,0)


if __name__ == "__main__":
    unittest.main()
