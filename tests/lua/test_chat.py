"""Evertally chat: whisper conversations, rooms on custom channels, the main-chat filter and the window. No game/network."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, MOCK_UI_LUA

CHAT_LUA = r'''
SENT={}; JOINED={}; LEFT={}; CHANNELS={}; FILTERS={}; SOUNDS=0
C_ChatInfo={SendChatMessage=function(msg,kind,lang,target) SENT[#SENT+1]={msg=msg,kind=kind,target=target} end}
JoinChannelByName=function(name,password) JOINED[#JOINED+1]={name=name,password=password};CHANNELS[name:lower()]=#JOINED+4 end
LeaveChannelByName=function(name) LEFT[#LEFT+1]=name;CHANNELS[name:lower()]=nil end
GetChannelName=function(name) local id=CHANNELS[tostring(name):lower()];if id then return id,name end;return 0 end
ChatFrame_AddMessageEventFilter=function(event,fn) FILTERS[event]=fn end
PlaySound=function() SOUNDS=SOUNDS+1 end
function Hidden(event,...) local fn=FILTERS[event];return fn~=nil and fn(nil,event,...)==true end
'''


class ChatTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(CHAT_LUA)
        self.c = self.a.Chat
        self.a.Dispatch("PLAYER_LOGIN")

    def hidden(self, event, *args):
        return bool(self.lua.globals().Hidden(event, *args))

    def lines(self, conv):
        return [conv.lines[i].text for i in range(1, len(conv.lines) + 1)]

    def test_whispers_become_one_conversation_per_partner_whatever_the_name_form(self):
        self.a.Dispatch("CHAT_MSG_WHISPER", "hi", "Bran-Fixture Realm")
        self.a.Dispatch("CHAT_MSG_WHISPER", "still there?", "Bran Fixture")
        self.a.Dispatch("CHAT_MSG_WHISPER_INFORM", "yes", "Bran")
        self.a.Dispatch("CHAT_MSG_WHISPER", "hey", "Ilyra")
        convs = self.c.List()
        self.assertEqual([convs[i].name for i in range(1, len(convs) + 1)], ["Ilyra", "Bran"])
        bran = self.c.conversations["whisper:bran"]
        self.assertEqual(self.lines(bran), ["hi", "still there?", "yes"])
        self.assertTrue(bran.lines[3].out)
        self.assertEqual(bran.unread, 2)
        self.assertEqual(self.c.Unread(), 3)
        self.c.MarkRead(bran); self.assertEqual(self.c.Unread(), 1)

    def test_replies_go_to_the_name_the_partner_wrote_from(self):
        self.a.Dispatch("CHAT_MSG_WHISPER", "hi", "Bran Fixture")
        ok, _ = self.c.Send(self.c.conversations["whisper:bran"], "hello\nthere")
        self.assertTrue(ok)
        sent = self.lua.globals().SENT[1]
        self.assertEqual((sent.kind, sent.target, sent.msg), ("WHISPER", "Bran Fixture", "hello there"))
        self.assertEqual(len(self.c.conversations["whisper:bran"].lines), 1, "the echo (WHISPER_INFORM) adds the own line")

    def test_main_chat_keeps_whispers_unless_redirect_is_on(self):
        self.assertTrue(self.c.Enabled(), "the chat is on by default")
        self.assertFalse(self.c.Settings().redirect, "redirect is off by default")
        self.assertFalse(self.hidden("CHAT_MSG_WHISPER", "hi", "Bran"))
        self.c.SetRedirect(True)
        self.assertTrue(self.hidden("CHAT_MSG_WHISPER", "hi", "Bran"))
        self.assertTrue(self.hidden("CHAT_MSG_WHISPER_INFORM", "hi", "Bran"))
        self.assertFalse(self.hidden("CHAT_MSG_SAY", "hi", "Bran"))
        self.c.SetEnabled(False)
        self.assertFalse(self.hidden("CHAT_MSG_WHISPER", "hi", "Bran"), "a disabled chat hides nothing")
        self.a.Dispatch("CHAT_MSG_WHISPER", "lost?", "Bran")
        self.assertEqual(len(self.c.List()), 0, "a disabled chat records nothing")

    def test_gm_and_secret_messages_are_never_hidden(self):
        self.c.SetRedirect(True)
        self.assertFalse(self.hidden("CHAT_MSG_WHISPER", "hello", "Gamemaster", "", "", "", "GM"))
        self.assertFalse(self.hidden("CHAT_MSG_WHISPER", self.lua.globals().SECRET, "Bran"))
        self.a.Dispatch("CHAT_MSG_WHISPER", self.lua.globals().SECRET, "Bran")
        self.assertEqual(len(self.c.List()), 0)

    def test_nothing_is_hidden_while_the_installation_gate_is_closed(self):
        self.c.SetRedirect(True)
        self.a.RequirementsReady = self.lua.eval("function() return false end")
        self.assertFalse(self.hidden("CHAT_MSG_WHISPER", "hi", "Bran"))

    def test_rooms_are_custom_channels_that_are_created_joined_and_left(self):
        ok, conv = self.c.JoinRoom("Raiders secret")
        self.assertTrue(ok)
        joined = self.lua.globals().JOINED[1]
        self.assertEqual((joined.name, joined.password), ("Raiders", "secret"))
        self.assertEqual(self.c.Rooms()[1].name, "Raiders")
        self.assertEqual(self.c.selected, conv.key)
        self.a.Dispatch("CHAT_MSG_CHANNEL", "pull at 8", "Ilyra", "", "5. Raiders", "", "", 0, 5, "Raiders")
        self.a.Dispatch("CHAT_MSG_CHANNEL", "wts ore", "Grom", "", "2. Trade", "", "", 2, 2, "Trade")
        self.assertEqual(self.lines(conv), ["pull at 8"])
        self.assertTrue(self.c.Send(conv, "ok")[0])
        sent = self.lua.globals().SENT[1]; self.assertEqual((sent.kind, sent.target), ("CHANNEL", 5))
        self.c.SetRedirect(True)
        self.assertTrue(self.hidden("CHAT_MSG_CHANNEL", "pull", "Ilyra", "", "5. Raiders", "", "", 0, 5, "Raiders"))
        self.assertFalse(self.hidden("CHAT_MSG_CHANNEL", "wts", "Grom", "", "2. Trade", "", "", 2, 2, "Trade"))
        self.assertTrue(self.c.LeaveRoom("raiders"))
        self.assertEqual(list(self.lua.globals().LEFT.values()), ["Raiders"])
        self.assertEqual(len(self.c.Rooms()), 0)
        self.assertIsNone(self.c.conversations[conv.key])
        self.assertEqual(self.c.Send(conv, "gone")[1], "chatNotJoined")

    def test_invalid_and_game_channel_names_are_refused(self):
        for name in ("", "a", "Trade", "general", "bad!name", "12345", "x" * 25, "bad|cff"):
            ok, why = self.c.JoinRoom(name)
            self.assertFalse(ok, name); self.assertEqual(why, "chatBadRoom")
        self.assertEqual(len(self.lua.globals().JOINED), 0)

    def test_saved_rooms_are_rejoined_once_after_loading(self):
        self.c.Settings().rooms = self.lua.table_from([self.lua.table_from({"name": "Raiders"}), self.lua.table_from({"name": "Crafters", "password": "pw"})])
        self.lua.execute("CHANNELS.raiders=6")
        self.lua.execute("C_Timer=nil")
        self.a.Dispatch("PLAYER_ENTERING_WORLD"); self.a.Dispatch("PLAYER_ENTERING_WORLD")
        joined = self.lua.globals().JOINED
        # saved custom rooms first, then the fixed rooms everyone is in (#Evertally support and General)
        self.assertEqual([(joined[i].name, joined[i].password) for i in range(1, len(joined) + 1)], [("Crafters", "pw"), ("Evertally", None), ("EtGeneral", None)])
        self.assertIsNotNone(self.c.conversations["room:raiders"])
        self.assertEqual(self.c.conversations["room:etgeneral"].name, "General")

    def test_channel_notices_land_in_the_room(self):
        _, conv = self.c.JoinRoom("Raiders")
        self.a.Dispatch("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "Raiders", "", "", 0, 0, "Raiders")
        self.assertTrue(conv.lines[1].system)
        self.assertEqual(conv.lines[1].text, self.a.L("chatWrongPassword"))

    def test_fixed_rooms_are_never_joined_with_a_password_even_one_saved_before(self):
        self.lua.execute('Evertally.db.settings.chat.rooms={{name="Evertally",password="oops"},{name="Mine",password="secret"}}; JOINED={}; CHANNELS={}')
        self.c.Rejoin()
        joined = {str(j.name): j.password for j in self.lua.globals().JOINED.values()}
        self.assertIsNone(joined["Evertally"], "a fixed room is open to everyone")
        self.assertEqual(joined["Mine"], "secret", "a private room keeps its password")

    def test_a_fixed_room_locked_with_a_password_closes_the_game_box_and_is_skipped(self):
        self.c.Rejoin()
        self.lua.execute("HIDDEN={}; StaticPopup_Hide=function(name) HIDDEN[#HIDDEN+1]=name end")
        self.a.Dispatch("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "5. Evertally", "", "", 0, 5, "Evertally")
        self.assertIn("CHAT_CHANNEL_PASSWORD", list(self.lua.globals().HIDDEN.values()))
        self.lua.execute("JOINED={}; CHANNELS={}")
        self.c.Rejoin()
        self.assertNotIn("Evertally", [str(j.name) for j in self.lua.globals().JOINED.values()], "not tried again this session")

    def test_only_the_authors_write_in_the_announcement_room_and_others_are_not_shown(self):
        self.assertTrue(self.c.IsAnnouncer("Mardyx-Vexwick")); self.assertTrue(self.c.IsAnnouncer("Mardyx Vexwick"))
        self.assertTrue(self.c.IsAnnouncer("sir dominik"))
        self.assertFalse(self.c.IsAnnouncer("Mardyx-Someoneelse")); self.assertFalse(self.c.IsAnnouncer("Radu-Linek"))
        self.c.Rejoin()
        room = self.c.conversations["room:evertally"]
        self.a.Dispatch("CHAT_MSG_CHANNEL", "spam", "Random-Player", "", "5. Evertally", "", "", 0, 5, "Evertally")
        self.a.Dispatch("CHAT_MSG_CHANNEL", "Nova verze venku", "Mardyx-Vexwick", "", "5. Evertally", "", "", 0, 5, "Evertally")
        self.assertEqual(self.lines(room), ["Nova verze venku"])
        self.assertFalse(self.c.CanSpeak("Evertally"), "the fixture character is not an author")
        ok, why = self.c.Send(room, "hello")
        self.assertFalse(ok); self.assertEqual(why, "chatReadOnly")
        self.lua.execute('UnitFullName=function() return "Mardyx", "Vexwick" end')
        self.assertTrue(self.c.CanSpeak("Evertally"))
        self.assertTrue(self.c.CanSpeak("EtGeneral"), "other rooms are open to all")

    def test_history_is_bounded_and_never_saved(self):
        for i in range(320): self.a.Dispatch("CHAT_MSG_WHISPER", "m%d" % i, "Bran")
        self.assertEqual(len(self.c.conversations["whisper:bran"].lines), 300)
        for i in range(70): self.a.Dispatch("CHAT_MSG_WHISPER", "hi", "Player%c" % (65 + i % 26) + "x" * (i // 26))
        self.assertLessEqual(len(self.c.List()), 60)
        self.assertNotIn("bran", self.a.Encode(self.a.db.settings).lower())

    def test_fixed_rooms_cannot_be_taken_and_a_left_fixed_room_stays_left(self):
        self.assertEqual(self.c.JoinRoom("EtGeneral")[1], "chatReserved")
        ok, conv = self.c.JoinCatalog("EtCestina")
        self.assertTrue(ok); self.assertEqual(conv.name, "Čeština")
        self.lua.execute("C_Timer=nil"); self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.assertTrue(self.c.Joined("EtGeneral"))
        self.c.LeaveRoom("EtGeneral")
        self.assertFalse(self.c.Joined("EtGeneral"))
        self.c.rejoined = False; self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.assertFalse(self.c.Joined("EtGeneral"), "a fixed room the player left is not joined again")
        self.c.JoinCatalog("EtGeneral"); self.assertTrue(self.c.Joined("EtGeneral"))

    def test_public_rooms_are_announced_in_evertally_and_private_ones_never(self):
        self.lua.execute("""ADDONMSG={};C_ChatInfo.SendAddonMessage=function(prefix,text,kind,target) ADDONMSG[#ADDONMSG+1]={prefix=prefix,text=text,kind=kind,target=target} end""")
        self.c.JoinCatalog("Evertally")
        self.c.JoinRoom("Secret pw", False)
        self.c.JoinRoom("Raiders", True)
        sent = self.lua.globals().ADDONMSG
        self.assertEqual([(sent[i].prefix, sent[i].text, sent[i].kind) for i in range(1, len(sent) + 1)], [("EvtlyRoom", "R|1|Raiders", "CHANNEL")])
        self.assertEqual(sent[1].target, self.lua.eval('GetChannelName("Evertally")')[0])
        self.assertEqual(self.c.Announce(), 1)

    def test_the_directory_lists_rooms_others_announce_and_forgets_them(self):
        self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyRoom", "R|1|Crafters", "CHANNEL", "Ilyra Realm")
        self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyRoom", "R|1|Trade", "CHANNEL", "Grom")          # a game channel name: ignored
        self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyRoom", "R|1|EtGeneral", "CHANNEL", "Grom")      # a fixed room: ignored
        self.a.Dispatch("CHAT_MSG_ADDON", "Other", "R|1|Nope", "CHANNEL", "Grom")
        rooms = self.c.Directory(None)
        self.assertEqual([rooms[i].name for i in range(1, len(rooms) + 1)], ["Crafters"])
        self.assertEqual(rooms[1].by, "Ilyra")
        self.assertEqual(len(self.c.Directory("craf")), 1); self.assertEqual(len(self.c.Directory("xyz")), 0)
        self.lua.execute("NOW=NOW+1300")
        self.assertEqual(len(self.c.Directory(None)), 0)

    def test_sharing_posts_an_invitation_into_general(self):
        self.assertEqual(self.c.Share(self.c.JoinRoom("Raiders", True)[1])[1], "chatNoGeneral")
        self.c.JoinCatalog("EtGeneral")
        ok, why = self.c.Share(self.c.conversations["room:raiders"])
        self.assertTrue(ok); self.assertEqual(why, "chatShared")
        sent = self.lua.globals().SENT
        self.assertEqual(sent[len(sent)].kind, "CHANNEL")
        self.assertIn("#Raiders", sent[len(sent)].msg)

    def test_texts_exist_in_both_languages(self):
        keys = ["chatEnabled", "chatRedirect", "chatTitle", "chatRoom", "chatWhisper", "chatLeave", "chatRoomHint", "chatBadRoom", "bagHighlight"]
        for lang in ("en", "cs"):
            for key in keys:
                self.assertTrue(self.a.locale[lang][key], (lang, key))
        self.assertNotEqual(self.a.locale.en.chatRedirect, self.a.locale.cs.chatRedirect)


class ChatWindowTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(CHAT_LUA)
        self.lua.execute('''
            QuickJoinToastButton=CreateFrame("Button","QuickJoinToastButton")
            local base=CreateFrame
            CreateFrame=function(kind,name,parent,template)
              local f=base(kind,name,parent,template)
              f.points={}
              f.SetPoint=function(self,...) self.points[#self.points+1]={...} end
              f.messages={}
              f.AddMessage=function(self,m) self.messages[#self.messages+1]=m end
              f.Clear=function(self) self.messages={} end
              f.SetFocus=function(self) self.focused=true end
              return f
            end''')
        self.c, self.u = self.a.Chat, self.a.ChatUI
        self.a.Dispatch("PLAYER_LOGIN")

    def test_the_button_sits_next_to_social_and_follows_the_setting(self):
        b = self.lua.globals().EvertallyChatButton
        self.assertIsNotNone(b)
        point = b.points[1]
        self.assertEqual((point[1], point[3]), ("LEFT", "RIGHT"))
        self.assertTrue(self.lua.eval("EvertallyChatButton.points[1][2]==QuickJoinToastButton"))
        self.assertTrue(b.IsShown(b))
        self.c.SetEnabled(False); self.assertFalse(b.IsShown(b))
        self.c.SetEnabled(True); self.assertTrue(b.IsShown(b))

    def test_unread_count_is_shown_on_the_button_and_reading_clears_it(self):
        self.a.Dispatch("CHAT_MSG_WHISPER", "hi", "Bran")
        b = self.lua.globals().EvertallyChatButton
        self.assertEqual(b.count.text, "1")
        self.u.Open(self.c.conversations["whisper:bran"])
        self.assertEqual(b.count.text, "")
        w = self.lua.globals().EvertallyChatWindow
        self.assertEqual(len(w.log.messages), 1)
        self.assertIn("hi", w.log.messages[1])
        self.a.Dispatch("CHAT_MSG_WHISPER", "again", "Bran")
        self.assertEqual(len(w.log.messages), 2)
        self.assertEqual(b.count.text, "", "a message in the open conversation is read")

    def test_a_redirected_whisper_opens_the_window_but_not_in_combat(self):
        self.c.SetRedirect(True)
        self.lua.execute("INCOMBAT=true")
        self.a.Dispatch("CHAT_MSG_WHISPER", "hi", "Bran")
        self.assertIsNone(self.lua.globals().EvertallyChatWindow)
        self.assertEqual(self.lua.globals().SOUNDS, 1)
        self.lua.execute("INCOMBAT=false")
        self.a.Dispatch("CHAT_MSG_WHISPER", "hi", "Ilyra")
        w = self.lua.globals().EvertallyChatWindow
        self.assertTrue(w.IsShown(w))
        self.assertEqual(self.c.selected, "whisper:ilyra")

    def test_the_window_starts_whispers_joins_rooms_and_sends_from_the_edit_box(self):
        self.u.Toggle()
        w = self.lua.globals().EvertallyChatWindow
        w.target.SetText(w.target, "Bran")
        self.u.StartWhisper()
        self.assertEqual(self.c.selected, "whisper:bran")
        w.input.SetText(w.input, "hello")
        w.input.scripts.OnEnterPressed(w.input)
        self.assertEqual(self.lua.globals().SENT[1].msg, "hello")
        self.assertEqual(w.input.text, "")
        w.target.SetText(w.target, "Raiders")
        self.u.JoinRoom()
        self.assertEqual(self.c.selected, "room:raiders")
        self.u.LeaveOrClose()
        self.assertEqual(len(self.c.Rooms()), 0)
        w.target.SetText(w.target, "Trade")
        self.u.JoinRoom()
        self.assertEqual(w.status.text, self.a.L("chatBadRoom"))

    def test_the_window_is_drawn_in_evertally_style_at_a_fixed_size_with_czech_capable_fonts(self):
        self.lua.execute("""TEMPLATES={};local base=CreateFrame
            CreateFrame=function(kind,name,parent,template) if template then TEMPLATES[#TEMPLATES+1]=template end
              return base(kind,name,parent,template) end""")
        self.a.db.settings.language = "cs"
        self.u.Toggle()
        w = self.lua.globals().EvertallyChatWindow
        self.assertEqual((w.w, w.h), (700, 460), "a sized window, never stretched over the screen")
        templates = self.lua.globals().TEMPLATES
        used = {templates[i] for i in range(1, len(templates) + 1)}
        self.assertEqual(used, {"InputBoxTemplate"}, "no Blizzard dialog shell or panel buttons; only the skinned input boxes")
        self.assertEqual(w.log.font, self.a.FontPath(), "the log uses Evertally's font, which has the Czech letters")
        self.assertEqual(w.whisper.text.text, "Whisper")
        self.assertEqual(w.room.text.text, "Místnost")
        self.assertEqual(w.tabRooms.text.text, "Místnosti")

    def test_sidebar_rows_show_initial_last_line_and_unread_pill(self):
        self.a.Dispatch("CHAT_MSG_WHISPER", "ahoj", "Řehoř")
        self.u.tab = "whispers"; self.u.Toggle()
        row = self.u.rows[1]
        self.assertEqual(row.initial.text, "Ř")
        self.assertEqual(row.preview.text, "ahoj")
        self.assertTrue(row.pill.IsShown(row.pill))
        self.assertEqual(row.count.text, "1")
        self.u.Select(row.entry.conv)
        self.assertFalse(row.pill.IsShown(row.pill))
        self.assertTrue(row.accent.IsShown(row.accent))

    def test_texture_paths_keep_their_backslashes(self):
        import re
        from test_addon import ADDON
        for name in ("Chat.lua", "ChatUI.lua", "BagHighlight.lua"):
            source = (ADDON / name).read_text(encoding="utf8")
            self.assertIsNone(re.search(r'"Interface\\[A-Za-z]', source), name)

    def test_the_rooms_tab_groups_fixed_rooms_and_ends_with_browsing(self):
        self.lua.execute("C_Timer=nil"); self.a.Dispatch("PLAYER_ENTERING_WORLD")
        entries = self.u.Entries()
        kinds = [entries[i].kind for i in range(1, len(entries) + 1)]
        heads = [entries[i].text for i in range(1, len(entries) + 1) if entries[i].kind == "head"]
        self.assertEqual(heads, ["chatCatSupport", "chatCatDefault", "chatCatLanguages", "chatCatCustom"])
        self.assertEqual(kinds[1], "conv", "#Evertally is joined for everyone")
        self.assertEqual(kinds[-1], "browse")
        fixed = next(entries[i] for i in range(1, len(entries) + 1) if entries[i].kind == "fixed")
        self.u.Toggle(); self.u.Activate(fixed)
        self.assertTrue(self.c.Joined(fixed.room.name))
        self.assertEqual(self.c.selected, "room:" + fixed.room.name.lower())

    def test_browsing_shows_public_rooms_and_creates_private_or_public_ones(self):
        self.a.Dispatch("CHAT_MSG_ADDON", "EvtlyRoom", "R|1|Crafters", "CHANNEL", "Ilyra")
        self.u.Toggle(); self.u.Activate(self.lua.table_from({"kind": "browse"}))
        w = self.lua.globals().EvertallyChatWindow
        self.assertTrue(w.browse.IsShown(w.browse))
        row = w.browse.rows[1]
        self.assertEqual(row.name.text, "# Crafters")
        self.u.JoinListed("Crafters")
        self.assertTrue(self.c.Joined("Crafters")); self.assertTrue(self.c.Rooms()[len(self.c.Rooms())].public)
        self.u.Activate(self.lua.table_from({"kind": "browse"}))
        w.browse.name.SetText(w.browse.name, "Secret"); w.browse.password.SetText(w.browse.password, "pw")
        self.u.makePublic = False; self.u.CreateRoom()
        room = [r for r in self.c.Rooms().values() if r.name == "Secret"][0]
        self.assertEqual((room.password, room.public), ("pw", False))

    def test_the_window_can_be_resized_and_keeps_its_size(self):
        self.u.Toggle()
        w = self.lua.globals().EvertallyChatWindow
        w.SetSize(w, 900, 600)
        w.grip.scripts.OnMouseUp(w.grip)
        self.assertEqual(list(self.c.Settings().size.values()), [900, 600])
        lua2, a2 = runtime(); lua2.execute(MOCK_UI_LUA); lua2.execute(CHAT_LUA)
        a2.Dispatch("PLAYER_LOGIN"); a2.Chat.Settings().size = lua2.table_from([2000, 100]); a2.ChatUI.Toggle()
        w2 = lua2.globals().EvertallyChatWindow
        self.assertEqual((w2.w, w2.h), (1400, 400), "kept inside the allowed bounds")

    def test_settings_page_has_the_three_switches(self):
        self.a.OpenUI(); self.a.ShowView("settings")
        keys = self.lua.eval('''function()
            local out={};for _,b in ipairs(MOCKBUTTONS) do if b.localeKey then out[#out+1]=b.localeKey end end;return table.concat(out,",") end''')()
        for key in ("bagHighlight", "chatEnabled", "chatRedirect"):
            self.assertIn(key, keys.split(","))


if __name__ == "__main__":
    unittest.main()
