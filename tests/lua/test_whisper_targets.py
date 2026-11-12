"""Live beacons use only valid, online character-whisper targets. No game/network."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime


class WhisperTargetTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute('''
          SENT={}
          Evertally.QueueSocial=function(text,channel,target,key) SENT[#SENT+1]={text=text,channel=channel,target=target,key=key};return true end
          C_Map={GetBestMapForUnit=function() return 1429 end,GetPlayerMapPosition=function() return {GetXY=function() return .42,.65 end} end}
          WOW_PROJECT_ID=160
          FRIENDS={}
          C_FriendList={GetNumFriends=function() return #FRIENDS end,GetFriendInfoByIndex=function(i) return FRIENDS[i] end}
          ERR_CHAT_PLAYER_NOT_FOUND_S="No player named '%s' is currently playing."
        ''')
        self.a.SetLive("friends", True)

    def targets(self):
        sent = self.lua.globals().SENT
        return [str(sent[i].target) for i in range(1, len(sent) + 1) if sent[i].channel == "WHISPER"]

    def test_unsafe_names_foreign_realms_offline_and_duplicate_entries_are_not_whispered(self):
        self.lua.execute('''FRIENDS={{name="Bran",connected=true},{name="Gonemacz",connected=false},
          {name="Radulin Veynhart-CAMWOWEU4Realm3PvE",connected=true},{name="Grom-OtherRealm",connected=true},
          {name="Bran-FixtureRealm",connected=true},{name="Bad123",connected=true},{name="Élodie",connected=true}}''')
        self.a.LiveTick()
        self.assertEqual(self.targets(), ["Bran", "Élodie"])

    def test_bnet_requires_matching_project_and_current_realm_and_plausible_character(self):
        self.lua.execute('''
          BNGetNumFriends=function() return 5 end
          GAMES={
            {clientProgram="WoW",characterName="Wrongproject",realmName="Fixture Realm",wowProjectID=1,isOnline=true},
            {clientProgram="WoW",characterName="Wrongrealm",realmName="CAMWOWEU4Realm3PvE",wowProjectID=160,isOnline=true},
            {clientProgram="WoW",characterName="Radulin Veynhart",realmName="Fixture Realm",wowProjectID=160,isOnline=true},
            {clientProgram="WoW",characterName="Unknownproject",realmName="Fixture Realm",isOnline=true},
            {clientProgram="WoW",characterName="Bnetfriend",realmName="Fixture Realm",wowProjectID=160,isOnline=true}}
          C_BattleNet={GetFriendAccountInfo=function(i) return {gameAccountInfo=GAMES[i]} end}
        ''')
        self.a.LiveTick()
        self.assertEqual(self.targets(), ["Bnetfriend"])

    def test_offline_update_invalidates_cached_online_target_immediately(self):
        self.lua.execute('FRIENDS={{name="Bran",connected=true}}')
        self.a.LiveTick(); self.assertEqual(self.targets(), ["Bran"])
        self.lua.execute('SENT={};FRIENDS[1].connected=false;CLOCK=CLOCK+6')
        self.a.Dispatch("FRIENDLIST_UPDATE")
        self.a.LiveTick(); self.assertEqual(self.targets(), [])

    def test_exact_no_player_error_blocks_target_for_session_without_hiding_other_errors(self):
        self.lua.execute('FRIENDS={{name="Bran",connected=true},{name="Ilyra",connected=true}}')
        self.a.LiveTick()
        self.a.Dispatch("CHAT_MSG_SYSTEM", "No player named 'Bran' is currently playing.")
        self.assertFalse(self.a.LiveWhisperAllowed("Bran"))
        self.lua.execute('SENT={};CLOCK=CLOCK+40')
        self.a.LiveTick()
        self.assertEqual(self.targets(), ["Ilyra"])
        # The precise system format is matched; unrelated text never blocks another friend.
        self.a.Dispatch("CHAT_MSG_SYSTEM", "Ignore this No player named 'Ilyra' message")
        self.a.SetLive("friends", False)
        self.a.SetLive("friends", True)
        self.lua.execute('SENT={};CLOCK=CLOCK+40')
        self.a.LiveTick()
        self.assertEqual(self.targets(), ["Ilyra"])
        self.a.SetLive("friends", False)
        self.assertTrue(self.a.LiveWhisperAllowed("Ilyra", True), "end message remains allowed after switching off")
        self.assertFalse(self.a.LiveWhisperAllowed("Bran", True), "blocked targets do not even receive an end message")

    def test_group_channel_replaces_duplicate_friend_whisper(self):
        self.lua.execute('''FRIENDS={{name="Bran",connected=true},{name="Ilyra",connected=true}}
          IsInGroup=function() return true end;UnitInParty=function(name) return name=="Bran" end''')
        self.a.SetLive("party", True)
        self.a.LiveTick()
        self.assertEqual(self.targets(), ["Ilyra"])
        self.assertTrue(any(str(self.lua.globals().SENT[i].channel) == "PARTY" for i in range(1, len(self.lua.globals().SENT) + 1)))

    def test_legacy_connected_flag_uses_fifth_return_value(self):
        self.lua.execute('''C_FriendList=nil;GetNumFriends=function() return 2 end
          GetFriendInfo=function(i) return i==1 and "Online" or "Offline",20,"Mage","Zone",i==1 end''')
        self.a.LiveTick()
        self.assertEqual(self.targets(), ["Online"])

    def test_real_queue_drops_rejected_deferred_beacon_but_keeps_manual_social_messages(self):
        lua, addon = runtime()  # Keep the real throttled queue, rather than the sender spy used above.
        lua.execute('''
          SENT={}; FRIENDS={{name="Bran",connected=true},{name="Ilyra",connected=true}}
          C_FriendList={GetNumFriends=function() return #FRIENDS end,GetFriendInfoByIndex=function(i) return FRIENDS[i] end}
          ERR_CHAT_PLAYER_NOT_FOUND_S="No player named '%s' is currently playing."
          C_ChatInfo={SendAddonMessage=function(prefix,text,channel,target) SENT[#SENT+1]={text=text,target=target};return 0 end}
        ''')
        addon.SetLive("friends", True)
        addon.QueueSocial("S|L|1429|420|650|8", "WHISPER", "Bran", "L:F:Bran")
        addon.Dispatch("CHAT_MSG_SYSTEM", "No player named 'Bran' is currently playing.")
        addon.PumpSync()
        self.assertEqual(len(lua.globals().SENT), 0, "an already queued beacon must not retry a server-rejected name")
        addon.QueueSocial("S|L|1429|420|650|8", "WHISPER", "Ilyra", "L:F:Ilyra")
        addon.QueueSocial("manual inspect fixture", "WHISPER", "Bran", "I:Bran")
        addon.PumpSync(); addon.PumpSync()
        sent = lua.globals().SENT
        self.assertEqual([sent[i].target for i in range(1, len(sent) + 1)], ["Ilyra", "Bran"])

    def test_real_queue_rechecks_online_status_immediately_before_send(self):
        lua, addon = runtime()
        lua.execute('''
          SENT={}; FRIENDS={{name="Bran",connected=true}}
          C_FriendList={GetNumFriends=function() return #FRIENDS end,GetFriendInfoByIndex=function(i) return FRIENDS[i] end}
          C_ChatInfo={SendAddonMessage=function() SENT[#SENT+1]=true;return 0 end}
        ''')
        addon.SetLive("friends", True)
        self.assertTrue(addon.LiveWhisperAllowed("Bran"))
        addon.QueueSocial("S|L|1429|420|650|8", "WHISPER", "Bran", "L:F:Bran")
        lua.execute('FRIENDS[1].connected=false')
        addon.Dispatch("FRIENDLIST_UPDATE")
        addon.PumpSync()
        self.assertEqual(len(lua.globals().SENT), 0)


if __name__ == "__main__":
    unittest.main()
