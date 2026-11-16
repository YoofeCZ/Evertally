"""Online with Evertally: opt-in announcements in the #Evertally room and the People list. No game/network."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, MOCK_UI_LUA

LUA = r'''
SENT={}; CHANNELS={evertally=7}
C_ChatInfo={SendAddonMessage=function(prefix,text,kind,target) SENT[#SENT+1]={prefix=prefix,text=text,kind=kind,target=target} end,
  RegisterAddonMessagePrefix=function() end, SendChatMessage=function() end}
GetChannelName=function(name) local id=CHANNELS[tostring(name):lower()];if id then return id,name end;return 0 end
C_Map={GetBestMapForUnit=function() return 1412 end,GetMapInfo=function(id) return {name=id==1412 and "Mulgore" or "Durotar"} end}
INVITES={};FRIENDS_ADDED={}
C_PartyInfo={InviteUnit=function(name) INVITES[#INVITES+1]=name end}
C_FriendList={AddFriend=function(name) FRIENDS_ADDED[#FRIENDS_ADDED+1]=name end,GetNumFriends=function() return 0 end,GetFriendInfoByIndex=function() end}
'''


class PresenceTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(LUA)
        self.p = self.a.Presence
        self.a.Dispatch("PLAYER_LOGIN")

    def sent(self):
        s = self.lua.globals().SENT
        return [(s[i].prefix, s[i].text, s[i].kind, s[i].target) for i in range(1, len(s) + 1)]

    def test_off_by_default_and_nothing_is_announced(self):
        self.assertFalse(self.p.Enabled())
        self.assertFalse(self.p.Announce(True))
        self.a.Dispatch("ZONE_CHANGED_NEW_AREA")
        self.assertEqual(self.sent(), [])

    def test_turning_it_on_announces_class_level_and_zone_only_in_evertally(self):
        self.p.SetEnabled(True)
        self.assertEqual(self.sent(), [("EvtlyHere", "P|1|7|20|1412", "CHANNEL", 7)])
        self.lua.execute("CLOCK=CLOCK+5")
        self.a.Dispatch("ZONE_CHANGED_NEW_AREA")
        self.assertEqual(len(self.sent()), 1, "a zone change within 30 s waits for the next turn")
        self.lua.execute("CLOCK=CLOCK+40")
        self.a.Dispatch("ZONE_CHANGED_NEW_AREA")
        self.assertEqual(len(self.sent()), 2)
        self.p.SetEnabled(False)
        self.assertEqual(self.sent()[-1][1], "P|0", "turning it off tells the others at once")

    def test_without_the_evertally_room_nothing_is_sent(self):
        self.lua.execute("CHANNELS={}")
        self.p.SetEnabled(True)
        self.assertEqual(self.sent(), [])

    def test_received_players_are_listed_and_forgotten(self):
        self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyHere", "P|1|1|11|1412", "CHANNEL", "Honza Pichac")
        self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyHere", "P|1|1|11|1412", "CHANNEL", "Fixture Hero")   # myself
        self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyHere", "garbage", "CHANNEL", "Grom")
        self.a.Dispatch("CHAT_MSG_ADDON", "Other", "P|1|1|11|1412", "CHANNEL", "Grom")
        peers = self.p.List()
        self.assertEqual([(peers[i].name, peers[i].level, peers[i].map) for i in range(1, len(peers) + 1)], [("Honza Pichac", 11, 1412)])
        self.assertIsNotNone(self.p.Get("Honza"))
        self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyHere", "P|0", "CHANNEL", "Honza Pichac")
        self.assertEqual(len(self.p.List()), 0)
        self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyHere", "P|1|1|11|1412", "CHANNEL", "Honza")
        self.lua.execute("NOW=NOW+901")
        self.assertEqual(len(self.p.List()), 0, "silent for 15 minutes: gone")

    def test_the_list_is_bounded(self):
        for i in range(230):
            self.lua.execute("NOW=NOW+1")
            self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyHere", "P|1|1|10|1412", "CHANNEL", "Player%dx" % i)
        self.assertLessEqual(len(self.p.List()), 200)
        self.assertIsNone(self.p.Get("Player0x"), "the oldest went first")

    def test_people_page_shows_them_under_online_with_evertally(self):
        self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyHere", "P|1|1|11|1412", "CHANNEL", "Honza Pichac")
        rows = self.a.SocialPeople("evertally")[0]
        texts = [(rows[i].heading, rows[i].title, rows[i].sub, rows[i].tag) for i in range(1, len(rows) + 1)]
        heading = next(i for i, r in enumerate(texts) if r[0] == self.a.L("peopleCatOnline"))
        row = texts[heading + 1]
        self.assertEqual(row[1], "Honza")
        self.assertIn("Mulgore", row[2]); self.assertIn("11", row[2])
        self.assertEqual(row[3], "EVERTALLY")

    def test_invite_and_friend_request_go_to_the_name_as_written(self):
        self.assertTrue(self.p.Invite("Honza Pichac")); self.assertTrue(self.p.AddFriend("Honza Pichac"))
        self.assertEqual(self.lua.globals().INVITES[1], "Honza Pichac")
        self.assertEqual(self.lua.globals().FRIENDS_ADDED[1], "Honza Pichac")

    def test_texts_in_both_languages(self):
        for lang in ("en", "cs"):
            for key in ("presence", "peopleCatOnline", "chatInvite", "chatAddFriend", "setupPresenceSub"):
                self.assertTrue(self.a.locale[lang][key], (lang, key))


class PresenceWindowTests(unittest.TestCase):
    def test_clicking_an_online_player_opens_a_whisper_with_invite_and_friend_buttons(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(LUA)
        a.Dispatch("PLAYER_LOGIN")
        a.Dispatch("CHAT_MSG_ADDON", "EvtlyHere", "P|1|1|11|1412", "CHANNEL", "Honza Pichac")
        rows = a.SocialPeople("evertally")[0]
        row = next(rows[i] for i in range(1, len(rows) + 1) if rows[i].title == "Honza")
        row.onClick()
        w = lua.globals().EvertallyChatWindow
        self.assertTrue(w.IsShown(w))
        self.assertEqual(a.Chat.selected, "whisper:honza")
        self.assertEqual(a.Chat.conversations["whisper:honza"].target, "Honza Pichac")
        self.assertTrue(w.invite.IsShown(w.invite)); self.assertTrue(w.friend.IsShown(w.friend))
        w.invite.scripts.OnClick(w.invite)
        self.assertEqual(lua.globals().INVITES[1], "Honza Pichac")

    def test_settings_has_the_switch(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(LUA)
        a.OpenUI(); a.ShowView("settings")
        keys = lua.eval('''function() local out={};for _,b in ipairs(MOCKBUTTONS) do if b.localeKey then out[#out+1]=b.localeKey end end;return table.concat(out,",") end''')()
        self.assertIn("presence", keys.split(","))


if __name__ == "__main__":
    unittest.main()
