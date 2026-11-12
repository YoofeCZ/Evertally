"""Own game contacts export adapters. No game, network, credentials or user data."""
from pathlib import Path
import sys
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import ROOT, runtime


class ConnectionTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        source = ROOT / "addon/Evertally/Connections.lua"
        # The root adds the module to the shared runtime; avoid registering it twice then.
        if self.a.ConnectionsSnapshot is None:
            self.lua.eval("loadstring")(source.read_text(encoding="utf8"), source.name)("Evertally", self.a)

    def allow(self, friends=True, party=False):
        self.a.db.settings.liveFriends = friends
        self.a.db.settings.liveParty = party
        self.a.SetScope("own_character", True)
        self.a.SetScope("own_track", True)
        self.a.SetWeb(True)

    def entries(self):
        out = self.a.ConnectionsSnapshot().entries
        return [(str(out[i].kind), str(out[i].name), str(out[i].realm)) for i in range(1, len(out) + 1)]

    def test_modern_friends_include_offline_and_bnet_wow_only_and_never_battletags(self):
        self.allow()
        self.lua.execute('''
          C_FriendList={GetNumFriends=function() return 2 end,GetFriendInfoByIndex=function(i)
            return ({ {name=" Alice ",connected=false}, {name="Bob-Other Realm",connected=true} })[i] end}
          BNGetNumFriends=function() return 2 end
          C_BattleNet={GetFriendAccountInfo=function(i) return ({
            {battleTag="Private#123",gameAccountInfo={clientProgram="WoW",characterName="Bnet",realmName="Far Realm"}},
            {battleTag="Other#456",gameAccountInfo={clientProgram="D3",characterName="NotWoW",realmName="Elsewhere"}}
          })[i] end}
        ''')
        self.assertEqual(self.entries(), [("friend", "Alice", "Fixture Realm"), ("friend", "Bnet", "Far Realm"), ("friend", "Bob", "Other Realm")])

    def test_legacy_adapter_and_group_unitname_fallback(self):
        self.allow(party=True)
        self.lua.execute('''
          GetNumFriends=function() return 1 end;GetFriendInfo=function() return "Legacy",20,"Mage","Zone",false end
          UnitExists=function(unit) return unit=="party1" end
          local old=UnitFullName;UnitFullName=function(unit) if unit=="player" then return old(unit) end end
          UnitName=function(unit) return unit=="party1" and "Party-OtherRealm" or "Fixture Hero" end
        ''')
        self.assertEqual(self.entries(), [("friend", "Legacy", "Fixture Realm"), ("group", "Party", "OtherRealm")])

    def test_dedup_self_crossrealm_and_unicode_and_determinism(self):
        self.allow()
        self.lua.execute('''
          ROWS={{name="Bób-Říše"},{name="Alice-FixtureRealm"},{name="alice-Fixture Realm"},
            {name="Fixture Hero-FixtureRealm"},{name="Fixture Hero-Other Realm"},{name="Áda"}}
          C_FriendList={GetNumFriends=function() return #ROWS end,GetFriendInfoByIndex=function(i) return ROWS[i] end}
        ''')
        before = self.a.ConnectionsSnapshot().key
        self.assertEqual(self.entries(), [("friend", "Alice", "FixtureRealm"), ("friend", "Bób", "Říše"), ("friend", "Fixture Hero", "Other Realm"), ("friend", "Áda", "Fixture Realm")])
        self.lua.execute('local out={} for i=#ROWS,1,-1 do out[#out+1]=ROWS[i] end ROWS=out')
        self.assertEqual(self.a.ConnectionsSnapshot().key, before)
        encoded = "".join(kind + "\0" + name.translate(str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")) + "\0" + realm.replace(" ", "").translate(str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")) + "\n" for kind, name, realm in self.entries()).encode()
        self.assertEqual(before, zlib.adler32(encoded))

    def test_requires_web_and_both_scopes_and_channel_optins_and_clears_export(self):
        self.lua.execute('C_FriendList={GetNumFriends=function() return 1 end,GetFriendInfoByIndex=function() return {name="Friend"} end}')
        self.assertEqual(self.entries(), [])
        self.allow(friends=False)
        self.assertEqual(self.entries(), [])
        self.a.db.settings.liveFriends = True
        self.assertEqual(len(self.entries()), 1)
        self.a.RefreshConnections()
        self.assertEqual(len(self.a.ExportStore().connections.entries), 1)
        self.a.SetScope("own_track", False)
        self.a.RefreshConnections()
        self.assertIsNone(self.a.ExportStore().connections)
        self.assertEqual(self.a.ConnectionsSnapshot().key, 1)
        self.a.SetScope("own_track", True)
        self.a.SetScope("own_character", False)
        self.a.RefreshConnections()
        self.assertEqual(self.entries(), [])
        self.assertIsNone(self.a.ExportStore().connections)
        self.a.SetScope("own_character", True)
        self.a.SetWeb(False)
        self.a.RefreshConnections()
        self.assertIsNone(self.a.ExportStore().connections)

    def test_raid_roster_events_remove_old_entries_and_change_the_hash(self):
        self.allow(party=True)
        self.lua.execute('''
          RAID={ ["raid1"]={"Fixture Hero","Fixture Realm"}, ["raid2"]={"Raidmate","Other Realm"} }
          IsInRaid=function() return true end;GetNumGroupMembers=function() return 2 end
          UnitExists=function(unit) return RAID[unit]~=nil end
          UnitFullName=function(unit) if unit=="player" then return "Fixture Hero","Fixture Realm" end if RAID[unit] then return unpack(RAID[unit]) end end
        ''')
        self.a.Dispatch("GROUP_ROSTER_UPDATE")
        before = self.a.ExportStore().connections.key
        self.assertEqual(self.entries(), [("group", "Raidmate", "Other Realm")])
        self.lua.execute('RAID.raid2=nil')
        self.a.Dispatch("GROUP_ROSTER_UPDATE")
        self.assertNotEqual(before, self.a.ExportStore().connections.key)
        self.assertEqual(self.a.ExportStore().connections.key, 1)

    def test_friend_events_update_hash_and_only_export_contact_identity(self):
        self.allow()
        self.lua.execute('''
          FRIENDS={{name="Friend",connected=false,guid="PrivateGUID",className="Mage",notes="Private note"}}
          C_FriendList={GetNumFriends=function() return #FRIENDS end,GetFriendInfoByIndex=function(i) return FRIENDS[i] end}
        ''')
        self.a.Dispatch("PLAYER_LOGIN")
        before = self.a.ExportStore().connections.key
        item = self.a.ExportStore().connections.entries[1]
        self.assertEqual(set(item.keys()), {"name", "realm", "kind"})
        self.lua.execute("FRIENDS={}")
        for event in ("FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED"):
            self.a.Dispatch(event)
            self.assertEqual(self.a.ExportStore().connections.key, 1)
            self.assertNotEqual(before, self.a.ExportStore().connections.key)

    def test_cap_is_deterministic_and_duplicate_friend_group_keeps_each_kind(self):
        self.allow(party=True)
        self.lua.execute('''
          C_FriendList={GetNumFriends=function() return 150 end,GetFriendInfoByIndex=function(i) return {name=string.format("Friend%03d",151-i)} end}
          UnitExists=function(unit) return unit=="party1" end
          UnitFullName=function(unit) if unit=="player" then return "Fixture Hero","Fixture Realm" end return "Friend001","Fixture Realm" end
        ''')
        values = self.entries()
        self.assertEqual(len(values), 100)
        self.assertEqual(values[0][1], "Friend001")
        self.assertEqual(values[-1][0], "group")
        self.assertEqual(values[-2][1], "Friend099")
        self.lua.execute('C_FriendList.GetNumFriends=function() return 1 end;C_FriendList.GetFriendInfoByIndex=function() return {name="Friend001"} end')
        self.assertEqual([entry[0] for entry in self.entries()], ["friend", "group"])

    def test_bad_or_secret_api_values_do_not_leak_or_break_refresh(self):
        self.allow(party=True)
        self.lua.execute('''
          C_FriendList={GetNumFriends=function() return 3 end,GetFriendInfoByIndex=function(i)
            if i==1 then error("not available") end
            return {name=i==2 and SECRET or "Bad\\nName"}
          end}
          BNGetNumFriends=function() error("not available") end
        ''')
        self.a.Dispatch("FRIENDLIST_UPDATE")
        self.assertEqual(self.entries(), [])
        self.assertIsNone(self.a.errors.FRIENDLIST_UPDATE)


if __name__ == "__main__":
    unittest.main()
