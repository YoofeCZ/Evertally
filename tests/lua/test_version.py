"""A new version is announced in game when two other players report it in #Evertally. No game/network."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime

LUA = r'''
SENT={}; PRINTED={}
C_ChatInfo={SendAddonMessage=function(prefix,text,kind,target) SENT[#SENT+1]={prefix=prefix,text=text,kind=kind,target=target} end,RegisterAddonMessagePrefix=function() end}
GetChannelName=function(name) if tostring(name):lower()=="evertally" then return 7,name end;return 0 end
Evertally.Print=function(t) PRINTED[#PRINTED+1]=t end
'''


class VersionTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(LUA)
        self.v = self.a.VersionCheck
        self.lua.execute('Evertally.version="0.9.51"')

    def hear(self, version, sender):
        self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyVer", "V|" + version, "CHANNEL", sender)

    def test_versions_compare_as_numbers(self):
        self.assertGreater(self.v.Number("0.9.100"), self.v.Number("0.9.51"))
        self.assertGreater(self.v.Number("1.0.0"), self.v.Number("0.99.999"))
        for bad in ("0.9", "v0.9.1", "0.9.1-beta", "99.0.0", ""):
            self.assertIsNone(self.v.Number(bad), bad)

    def test_a_newer_version_needs_two_players_and_is_told_once(self):
        self.hear("0.9.52", "Bran Realm")
        self.assertEqual(len(self.lua.globals().PRINTED), 0, "one player alone could be a prank")
        self.hear("0.9.52", "Bran-Realm")
        self.assertEqual(len(self.lua.globals().PRINTED), 0, "the same player under another name form counts once")
        self.hear("0.9.52", "Ilyra")
        printed = self.lua.globals().PRINTED
        self.assertEqual(len(printed), 1)
        self.assertIn("0.9.52", printed[1]); self.assertIn("0.9.51", printed[1])
        self.hear("0.9.52", "Grom")
        self.assertEqual(len(self.lua.globals().PRINTED), 1, "told once")
        self.hear("0.9.53", "Grom"); self.hear("0.9.53", "Ilyra")
        self.assertEqual(len(self.lua.globals().PRINTED), 2, "a still newer one is told again")

    def test_older_and_equal_versions_are_quiet_and_an_older_player_gets_our_version(self):
        self.hear("0.9.51", "Bran"); self.hear("0.9.51", "Ilyra")
        self.assertEqual(len(self.lua.globals().PRINTED), 0)
        self.hear("0.9.40", "Old")
        sent = self.lua.globals().SENT
        self.assertEqual((sent[1].prefix, sent[1].text, sent[1].kind, sent[1].target), ("EvtlyVer", "V|0.9.51", "CHANNEL", 7))
        self.hear("0.9.40", "Older")
        self.assertEqual(len(self.lua.globals().SENT), 1, "replies are rate-limited")
        self.hear("garbage", "X"); self.a.Dispatch("CHAT_MSG_ADDON", "Other", "V|9.9.9", "CHANNEL", "X")
        self.assertEqual(len(self.lua.globals().PRINTED), 0)

    def test_texts_in_both_languages(self):
        for lang in ("en", "cs"):
            self.assertIn("%s", self.a.locale[lang].versionNew)


if __name__ == "__main__":
    unittest.main()
