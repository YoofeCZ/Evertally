"""The damage meter (Meter.lua), the threat meter (ThreatMeter.lua) and the loot sparkles (LootSparkles.lua).

The meter reads the client's own combat data (C_DamageMeter; Forever has no CombatLogGetCurrentEventInfo for add-ons).
After a fight the values are plain: rows sorted, percentages, the spell breakdown, death times. In a fight they are
secret: nothing is compared, sorted or formatted, the values go to the widgets as they are. Here a secret is the
runtime's SECRET sentinel (issecretvalue), whose tostring raises, so any formatting of it fails the test."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime

FAKE_METER = r"""
Enum = Enum or {}
Enum.DamageMeterType = {DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5, Dispels = 6,
  DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10}
Enum.DamageMeterSessionType = {Overall = 0, Current = 1, Expired = 2}
CVARS = {damageMeterEnabled = "0", outlineModeShowLootEffectWhenDisabled = "0"}
C_CVar = {GetCVar = function(k) return CVARS[k] end, SetCVar = function(k, v) CVARS[k] = tostring(v); return true end,
  GetCVarBool = function(k) return CVARS[k] == "1" end}
SESSIONS = {}
RESETS = 0
C_DamageMeter = {
  IsDamageMeterAvailable = function() return true end,
  GetAvailableCombatSessions = function() return {{sessionID = 7, name = "Maiden of Vigilance", durationSeconds = 312}} end,
  GetCombatSessionFromType = function(st, t) return SESSIONS[t] or {combatSources = {}, totalAmount = 0, maxAmount = 0} end,
  GetCombatSessionFromID = function(id, t) return SESSIONS[t] or {combatSources = {}, totalAmount = 0, maxAmount = 0} end,
  GetCombatSessionSourceFromType = function(st, t, guid) return SPELLS end,
  GetCombatSessionSourceFromID = function(id, t, guid) return SPELLS end,
  ResetAllCombatSessions = function() RESETS = RESETS + 1 end,
}
C_Spell = {GetSpellName = function(id) return ({[133] = "Fireball", [116] = "Frostbolt"})[id] end}
RAID_CLASS_COLORS = {MAGE = {r = 0.25, g = 0.78, b = 0.92}, WARRIOR = {r = 0.78, g = 0.61, b = 0.43}}
ABBREVIATED = {}
AbbreviateNumbers = function(v) ABBREVIATED[#ABBREVIATED + 1] = v; return v end
"""

PLAIN = r"""
SESSIONS[Enum.DamageMeterType.DamageDone] = {totalAmount = 1000, maxAmount = 600, durationSeconds = 10, combatSources = {
  {name = "Noe", classFilename = "WARRIOR", totalAmount = 400, amountPerSecond = 40, sourceGUID = "g2", isLocalPlayer = false},
  {name = "Touchmebaby", classFilename = "MAGE", totalAmount = 600, amountPerSecond = 60, sourceGUID = "g1", isLocalPlayer = true},
}}
SESSIONS[Enum.DamageMeterType.Deaths] = {totalAmount = 2, maxAmount = 1, combatSources = {
  {name = "Shiver", classFilename = "MAGE", totalAmount = 1, deathTimeSeconds = 70},
  {name = "Daboon", classFilename = "WARRIOR", totalAmount = 1, deathTimeSeconds = 51},
}}
SPELLS = {totalAmount = 600, maxAmount = 500, combatSpells = {
  {spellID = 116, totalAmount = 100, amountPerSecond = 10},
  {spellID = 133, totalAmount = 500, amountPerSecond = 50},
}}
"""

SECRET_FIGHT = r"""
SESSIONS[Enum.DamageMeterType.DamageDone] = {totalAmount = SECRET, maxAmount = SECRET, combatSources = {
  {name = SECRET, classFilename = "MAGE", totalAmount = SECRET, amountPerSecond = SECRET, sourceGUID = SECRET},
  {name = SECRET, classFilename = "WARRIOR", totalAmount = SECRET, amountPerSecond = SECRET, sourceGUID = SECRET},
}}
"""


class MeterTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE_METER)
        self.m = self.a.Meter

    def rows(self, mode="damage"):
        rows, info = self.m.Rows(mode, self.m.Segments()[1])
        return [rows[i] for i in range(1, len(rows) + 1)], info

    def test_after_a_fight_rows_are_sorted_with_their_share(self):
        self.lua.execute(PLAIN)
        rows, info = self.rows()
        self.assertEqual([str(r.name) for r in rows], ["Touchmebaby", "Noe"])
        self.assertAlmostEqual(rows[0].pct, 0.6)
        self.assertFalse(info.secret)
        self.assertEqual(self.m.Format(1550000), "1.55M")
        self.assertEqual(self.m.Format(320930000), "320.93M")
        self.assertEqual(self.m.Format(12345), "12.3K")

    def test_the_spell_breakdown_and_the_death_log(self):
        self.lua.execute(PLAIN)
        rows, _ = self.rows()
        spells = self.m.Spells("damage", self.m.Segments()[1], rows[0])
        spells = [spells[i] for i in range(1, len(spells) + 1)]
        self.assertEqual([str(s.name) for s in spells], ["Fireball", "Frostbolt"])
        self.assertAlmostEqual(spells[0].pct, 500 / 600)
        deaths, _ = self.rows("deaths")
        self.assertEqual([str(r.name) for r in deaths], ["Daboon", "Shiver"], "in order of death")
        self.assertEqual(self.m.Clock(deaths[0].deathTime), "0m 51s")

    def test_segments_list_current_overall_and_kept_fights(self):
        segs = self.m.Segments()
        self.assertEqual([str(segs[i].label) for i in range(1, len(segs) + 1)], ["Current fight", "Overall", "Maiden of Vigilance"])
        self.assertEqual(segs[3].value, 7)

    def test_in_a_fight_secret_values_are_only_handed_on(self):
        self.lua.execute(SECRET_FIGHT)
        rows, info = self.rows()   # a tostring, compare or sort of SECRET would raise here
        self.assertTrue(info.secret)
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(r.secret for r in rows))
        self.assertTrue(all(r.pct is None for r in rows), "no percentage from secret values")
        self.assertEqual(len(self.m.Spells("damage", self.m.Segments()[1], rows[0])), 0, "the breakdown waits for the fight's end")
        self.m.Format(self.lua.globals().SECRET)
        self.assertEqual(len(self.lua.globals().ABBREVIATED), 1, "a secret number goes through the client's AbbreviateNumbers")

    def test_the_window_draws_plain_and_secret_fights(self):
        self.a.db.settings.meter = self.lua.table(enabled=True)
        self.lua.execute(PLAIN)
        self.lua.execute("C_Timer = nil")
        self.m.SetShown(True)
        self.m.Refresh()
        f = self.m.frame
        self.assertTrue(f.rows[1].shown)
        self.assertEqual(str(f.rows[1].name.text), "Touchmebaby")
        self.assertEqual(str(f.rows[1].amount.text), "600")
        self.assertIn("60.0%", str(f.rows[1].extra.text))
        self.lua.execute(SECRET_FIGHT)
        self.m.Refresh()   # must not format, compare or sort a secret
        self.assertTrue(f.rows[2].shown)
        self.assertEqual(str(f.rows[1].extra.text), "")

    def test_the_games_combat_data_is_switched_on(self):
        self.assertTrue(self.m.Available())
        self.assertEqual(self.lua.globals().CVARS.damageMeterEnabled, "1")

    def test_reset_clears_the_games_sessions(self):
        self.m.Reset()
        self.assertEqual(self.lua.globals().RESETS, 1)

    def test_slash_toggles_the_meter_and_the_threat_meter(self):
        self.lua.execute("C_Timer = nil")
        self.lua.globals().SlashCmdList.EVERTALLY("meter")
        self.assertTrue(self.m.frame.shown)
        self.assertTrue(self.m.Enabled())
        self.lua.globals().SlashCmdList.EVERTALLY("threat")
        self.assertTrue(self.a.ThreatMeter.frame.shown)


class ThreatTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(r"""
          GROUP = 2
          GetNumGroupMembers = function() return GROUP end
          UnitExists = function(u) return u == "target" or u == "player" or u == "party1" or u == "party2" end
          UnitIsFriend = function() return false end
          UnitIsUnit = function(a, b) return a == b end
          UnitName = function(u) return ({player = "Me", party1 = "Tank", party2 = "Heal", target = "Boss"})[u] end
          UnitClass = function(u) return "x", ({player = "MAGE", party1 = "WARRIOR", party2 = "PRIEST"})[u] end
          THREAT = {player = {false, 1, 85}, party1 = {true, 3, 100}, party2 = {false, 0, 30}}
          UnitDetailedThreatSituation = function(u, t) local v = THREAT[u]; if v then return v[1], v[2], v[3], v[3], v[3] end end
        """)
        self.t = self.a.ThreatMeter

    def test_threat_sorted_highest_first_with_the_tank(self):
        rows, state = self.t.Rows("target")
        rows = [rows[i] for i in range(1, len(rows) + 1)]
        self.assertEqual(state, "plain")
        self.assertEqual([str(r.name) for r in rows], ["Tank", "Me", "Heal"])
        self.assertTrue(rows[0].tanking)

    def test_secret_threat_is_kept_in_group_order(self):
        self.lua.execute('THREAT = {player = {SECRET, SECRET, SECRET}, party1 = {SECRET, SECRET, SECRET}}')
        rows, state = self.t.Rows("target")
        self.assertEqual(state, "secret")
        self.assertEqual([str(rows[i].name) for i in range(1, len(rows) + 1)], ["Me", "Tank"])
        self.a.db.settings.meter = self.lua.table(threat=True)
        self.t.Update()
        self.t.Refresh()   # the window hands SECRET on, never formats it
        self.assertTrue(self.t.frame.rows[2].shown)

    def test_no_hostile_target_no_rows(self):
        self.lua.execute('UnitIsFriend = function() return true end')
        rows, state = self.t.Rows("target")
        self.assertEqual(state, "none")

    def test_group_only_hides_it_when_solo(self):
        self.a.db.settings.meter = self.lua.table(threat=True, threatGroupOnly=True)
        self.lua.execute('GROUP = 0')
        self.t.Update()
        self.assertFalse(bool(self.t.frame and self.t.frame.shown))
        self.lua.execute('GROUP = 2')
        self.t.Update()
        self.assertTrue(self.t.frame.shown)


class LootSparklesTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE_METER)
        self.s = self.a.LootSparkles

    def cvar(self): return str(self.lua.globals().CVARS.outlineModeShowLootEffectWhenDisabled)

    def test_on_by_default_and_kept_on(self):
        self.assertTrue(self.s.Enabled())
        self.a.Dispatch("PLAYER_LOGIN")
        self.assertEqual(self.cvar(), "1")
        # a graphics preset switches it off: the client reports it, it goes back on
        self.lua.execute('CVARS.outlineModeShowLootEffectWhenDisabled = "0"')
        self.a.Dispatch("CVAR_UPDATE", "outlineModeShowLootEffectWhenDisabled")
        self.assertEqual(self.cvar(), "1")

    def test_in_a_fight_it_waits_for_the_end(self):
        self.lua.execute('INCOMBAT = true')
        self.s.Apply()
        self.assertEqual(self.cvar(), "0")
        self.lua.execute('INCOMBAT = false')
        self.a.Dispatch("PLAYER_REGEN_ENABLED")
        self.assertEqual(self.cvar(), "1")

    def test_switched_off_the_players_own_value_goes_back(self):
        self.s.Apply()
        self.assertEqual(self.cvar(), "1")
        self.s.SetEnabled(False)
        self.assertEqual(self.cvar(), "0")
        self.assertIsNone(self.a.db.settings.lootSparklesWas)


class CombatSettingsTests(unittest.TestCase):
    def test_the_combat_page_reads_and_writes_the_same_settings(self):
        lua, a = runtime()
        lua.execute(MOCK_UI_LUA)
        lua.execute(FAKE_METER)
        lua.execute("C_Timer = nil")
        from test_guide_settings import FAKE_OPTIONS
        lua.execute(FAKE_OPTIONS)
        self.assertTrue(a.InstallGuideSettings())
        specs = lua.globals().SPECS
        found = {}
        for i in range(1, len(specs) + 1):
            s = specs[i]
            for j in range(1, len(s.controls) + 1):
                found[str(s.controls[j].localeKey)] = (s, s.controls[j])
        for key in ("meterEnabled", "meterLock", "meterShow", "meterResetData", "threatEnabled", "threatGroupOnly", "threatShow", "lootSparkles"):
            self.assertEqual(found[key][0].key, "evertallycombat", key)
            for lang in ("en", "cs"):
                self.assertIsNotNone(a.locale[lang][key], (lang, key))
        found["meterEnabled"][1].set(True)
        self.assertTrue(a.Meter.Enabled())
        self.assertTrue(a.Meter.frame.shown)
        found["threatEnabled"][1].set(True)
        self.assertTrue(a.ThreatMeter.Enabled())
        found["lootSparkles"][1].set(False)
        self.assertFalse(a.LootSparkles.Enabled())


if __name__ == "__main__":
    unittest.main()
