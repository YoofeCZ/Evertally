"""Music control: commands through the pixel strip, the library from MusicData.lua, ducking at NPCs. No game/network."""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, MOCK_UI_LUA

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "optical_command.json"

TIMER = r'''
TIMERS={}
C_Timer={After=function(delay,fn) TIMERS[#TIMERS+1]=fn end,NewTicker=function() end}
function RunTimers() local list=TIMERS;TIMERS={};for _,fn in ipairs(list) do fn() end end
'''


def fletcher16(data):
    c0 = c1 = 0
    for byte in data:
        c0 = (c0 + byte) % 255
        c1 = (c1 + c0) % 255
    return (c1 << 8) | c0


class MusicCommandTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(TIMER)
        self.m = self.a.Music

    def bytes_of(self, text, seq=1):
        b = self.a.OpticalCommandBytes(text, seq)
        return None if b is None else [b[i] for i in range(1, len(b) + 1)]

    def test_command_frame_is_version_seq_length_text_and_checksum(self):
        data = self.bytes_of("m:next", 7)
        self.assertEqual(data[:3], [9, 7, 6])
        self.assertEqual(bytes(data[3:9]), b"m:next")
        self.assertEqual((data[9] << 8) | data[10], fletcher16(data[:9]))
        self.assertIsNone(self.bytes_of("m:find:Řehoř"), "only printable ASCII crosses the strip")
        self.assertIsNone(self.bytes_of("x" * 121))

    def test_the_pixels_match_the_fixture_the_app_is_tested_with(self):
        fixture = json.loads(FIXTURE.read_text(encoding="utf8"))
        symbols = self.a.OpticalSymbols(self.a.OpticalCommandBytes(fixture["text"], fixture["seq"]))
        levels = [0, 16, 32, 48]
        pixels = [[v, v, v] for v in levels]
        for i in range(1, len(symbols) + 1):
            s = symbols[i]
            pixels.append([levels[s // 16], levels[(s // 4) % 4], levels[s % 4]])
        self.assertEqual(pixels, fixture["pixels"], "regenerate tests/lua/fixtures/optical_command.json if the frame changed on purpose")

    def test_nothing_is_sent_while_the_player_is_off_and_commands_queue_when_on(self):
        self.assertFalse(self.m.Enabled())
        self.assertEqual(tuple(self.m.Send("m:next")), (False, "musicOff"), "says why, instead of a silent button")
        self.m.SetEnabled(True)
        self.assertTrue(self.m.Send("m:next")[0])
        self.assertTrue(self.a.OpticalCommandShown())
        self.assertTrue(self.m.Send("m:vol+"), "the second one waits")
        self.lua.execute("CLOCK=CLOCK+1"); self.lua.execute("RunTimers()")
        self.assertTrue(self.a.OpticalCommandShown(), "the waiting command is drawn next")

    def test_search_text_is_folded_to_ascii(self):
        self.assertEqual(self.m.Ascii("Žluťoučký kůň"), "Zlutoucky kun")
        self.m.SetEnabled(True)
        self.assertTrue(self.m.Search("  Čechomor  "))
        self.assertFalse(self.m.Search("   "))

    def test_the_dashboard_button_asks_the_app_even_before_music_is_on(self):
        self.lua.execute("SENTCMD={};Evertally.OpticalSendCommand=function(t) SENTCMD[#SENTCMD+1]=t;return true end")
        self.assertFalse(self.m.Enabled())
        self.assertTrue(self.m.OpenDashboard())
        self.assertEqual(self.lua.globals().SENTCMD[1], "m:spdev")
        self.assertEqual(self.m.REDIRECT, "http://127.0.0.1:8765/callback")
        self.assertEqual(self.m.DASHBOARD, "https://developer.spotify.com/dashboard")

    def test_spotify_client_id_is_checked_before_it_is_sent(self):
        self.lua.execute("SENTCMD={};Evertally.OpticalSendCommand=function(t) SENTCMD[#SENTCMD+1]=t;return true end")
        self.m.SetEnabled(True)
        self.assertEqual(self.m.ConnectSpotify("abc")[1], "musicBadId")
        self.assertTrue(self.m.ConnectSpotify(" 0123456789ABCDEF0123456789abcdef ")[0])
        self.assertEqual(self.lua.globals().SENTCMD[1], "m:spid:0123456789abcdef0123456789abcdef")
        self.assertEqual(self.a.db.settings.music.spotifyId, "0123456789abcdef0123456789abcdef", "kept for after a reload")

    def test_a_setup_button_tells_once_how_to_see_that_the_app_heard_it(self):
        self.lua.execute("SENTCMD={};PRINTED={};Evertally.OpticalSendCommand=function(t) SENTCMD[#SENTCMD+1]=t;return true end;Evertally.Print=function(t) PRINTED[#PRINTED+1]=t end")
        self.assertFalse(self.m.SendAndTell("m:lib"))
        self.assertEqual(self.lua.globals().PRINTED[1], self.a.L("musicOff"))
        self.m.SetEnabled(True)
        self.assertTrue(self.m.SendAndTell("m:lib")); self.assertTrue(self.m.SendAndTell("m:lib"))
        printed = self.lua.globals().PRINTED
        self.assertEqual((printed[2], printed[3]), (self.a.L("musicCheckApp"), self.a.L("musicSent")))

    def test_npc_conversation_ducks_once_and_restores(self):
        self.lua.execute("SENTCMD={};local send=Evertally.OpticalSendCommand;Evertally.OpticalSendCommand=function(t) SENTCMD[#SENTCMD+1]=t;return true end")
        self.m.SetEnabled(True)
        self.a.Dispatch("GOSSIP_SHOW"); self.a.Dispatch("QUEST_DETAIL"); self.a.Dispatch("QUEST_FINISHED")
        sent = self.lua.globals().SENTCMD
        self.assertEqual([sent[i] for i in range(1, len(sent) + 1)], ["m:duck", "m:unduck"])
        self.m.SetDuck(False)
        self.a.Dispatch("GOSSIP_SHOW")
        self.assertEqual(len(self.lua.globals().SENTCMD), 2)

    def test_library_rows_are_checked_and_filtered(self):
        self.lua.execute('''EvertallyMusicData={schemaVersion=1,source="spotify",playlists={{id="spotify:playlist:abc",name="Leveling Mix",count=40},
            {id="bad id with spaces",name="Broken"},{id="spotify:playlist:def",name="Chill"}},
            liked={{id="spotify:track:1",name="Song",artist="Čechomor"}}}''')
        rows = self.m.Rows("playlists", None)
        self.assertEqual([rows[i].name for i in range(1, len(rows) + 1)], ["Leveling Mix", "Chill"])
        self.assertEqual(len(self.m.Rows("playlists", "chi")), 1)
        self.assertEqual(len(self.m.Rows("liked", "čecho")), 1)
        self.lua.execute("EvertallyMusicData={schemaVersion=2}")
        self.assertEqual(len(self.m.Rows("playlists", None)), 0)


class MusicWindowTests(unittest.TestCase):
    def test_player_and_browser_build_and_double_click_plays(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(TIMER)
        lua.execute('''EvertallyMusicData={schemaVersion=1,nowPlaying={name="Song"},playlists={{id="spotify:playlist:abc",name="Leveling Mix"}}}
            SENTCMD={};Evertally.OpticalSendCommand=function(t) SENTCMD[#SENTCMD+1]=t;return true end''')
        a.Music.SetEnabled(True)
        player = lua.globals().EvertallyMusicPlayer
        self.assertTrue(player.IsShown(player))
        self.assertEqual(player.title.text, a.L("musicTitle"), "no song title: the game cannot follow the song live")
        player.buttons["m:next"].scripts.OnClick(player.buttons["m:next"])
        a.Music.ToggleBrowser()
        w = lua.globals().EvertallyMusicBrowser
        row = w.rows[1]
        self.assertEqual(row.text.text, "Leveling Mix")
        row.scripts.OnDoubleClick(row)
        sent = lua.globals().SENTCMD
        self.assertEqual([sent[i] for i in range(1, len(sent) + 1)], ["m:next", "m:pl:spotify:playlist:abc"])
        a.Music.SetEnabled(False)
        self.assertFalse(player.IsShown(player))

    def test_settings_have_a_music_section_with_service_and_client_id(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(TIMER)
        lua.execute("SENTCMD={};Evertally.OpticalSendCommand=function(t) SENTCMD[#SENTCMD+1]=t;return true end")
        a.OpenUI(); a.ShowView("settings")
        page = a.settingsPage
        titles = [str(page.sections[i].localeKey) for i in range(1, len(page.sections) + 1)]
        self.assertEqual(titles[5], "musicSection", "after the nameplates, which stay the fifth")
        self.assertEqual(titles[4], "nameplatesSection")
        a.Music.SetEnabled(True)
        page.musicSources["youtube"].scripts.OnClick(page.musicSources["youtube"])
        page.Refresh()
        self.assertFalse(page.musicId.IsShown(page.musicId), "YouTube Music needs no Client ID")
        page.musicSources["spotify"].scripts.OnClick(page.musicSources["spotify"])
        page.Refresh()
        page.musicId.SetText(page.musicId, "0123456789abcdef0123456789abcdef")
        page.musicConnect.scripts.OnClick(page.musicConnect)
        sent = lua.globals().SENTCMD
        self.assertEqual([sent[i] for i in range(1, len(sent) + 1)], ["m:src:youtube", "m:src:spotify", "m:spid:0123456789abcdef0123456789abcdef"])
        page.musicOpen.scripts.OnClick(page.musicOpen)
        browser = lua.globals().EvertallyMusicBrowser
        self.assertTrue(browser.IsShown(browser), "the music has its own window")

    def test_the_note_icon_shows_and_hides_the_small_player_and_right_click_opens_the_library(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(TIMER)
        a.Dispatch("PLAYER_LOGIN")
        self.assertIsNone(lua.globals().EvertallyMusicButton, "no icon while the music is off")
        a.Music.SetEnabled(True)
        icon, player = lua.globals().EvertallyMusicButton, lua.globals().EvertallyMusicPlayer
        self.assertTrue(icon.IsShown(icon)); self.assertTrue(player.IsShown(player))
        icon.scripts.OnClick(icon, "LeftButton")
        self.assertFalse(player.IsShown(player)); self.assertTrue(icon.IsShown(icon), "the icon stays to bring it back")
        self.assertTrue(a.Music.Enabled(), "hiding the player keeps the music on")
        icon.scripts.OnClick(icon, "LeftButton")
        self.assertTrue(player.IsShown(player))
        player.close.scripts.OnClick(player.close)
        self.assertFalse(player.IsShown(player)); self.assertTrue(a.Music.Enabled(), "the x only hides the small player")
        icon.scripts.OnClick(icon, "RightButton")
        browser = lua.globals().EvertallyMusicBrowser
        self.assertTrue(browser.IsShown(browser))
        a.Music.SetEnabled(False)
        self.assertFalse(icon.IsShown(icon))

    def test_the_library_window_switches_the_small_player(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(TIMER)
        a.Music.SetEnabled(True); a.Music.ToggleBrowser()
        w, player = lua.globals().EvertallyMusicBrowser, lua.globals().EvertallyMusicPlayer
        self.assertTrue(w.mini.on)
        w.mini.scripts.OnClick(w.mini)
        self.assertFalse(player.IsShown(player)); self.assertFalse(w.mini.on)
        w.mini.scripts.OnClick(w.mini)
        self.assertTrue(player.IsShown(player)); self.assertTrue(w.mini.on)

    def test_play_and_pause_are_two_buttons_with_icons(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(TIMER)
        lua.execute("SENTCMD={};Evertally.OpticalSendCommand=function(t) SENTCMD[#SENTCMD+1]=t;return true end")
        a.Music.SetEnabled(True)
        player = lua.globals().EvertallyMusicPlayer
        for command in ("m:prev", "m:play", "m:pause", "m:next"):
            b = player.buttons[command]
            self.assertIn("Shape", str(b.icon.texture), command)
            b.scripts.OnClick(b)
        self.assertIsNone(player.buttons["m:toggle"])
        sent = lua.globals().SENTCMD
        self.assertEqual([sent[i] for i in range(1, len(sent) + 1)], ["m:prev", "m:play", "m:pause", "m:next"])

    def test_a_search_waits_for_the_app_and_the_reload_opens_the_results(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(TIMER)
        lua.execute("SENTCMD={};Evertally.OpticalSendCommand=function(t) SENTCMD[#SENTCMD+1]=t;return true end")
        lua.execute('EvertallyMusicData={schemaVersion=1,playlists={{id="yt:playlist:PLa",name="Mix"}}}')
        a.Music.SetEnabled(True); a.Music.ToggleBrowser()
        w = lua.globals().EvertallyMusicBrowser
        w.search.SetText(w.search, "Eminem")
        w.search.scripts.OnEnterPressed(w.search)
        self.assertEqual(lua.globals().SENTCMD[1], "m:find:Eminem")
        self.assertEqual(w.part, "search")
        self.assertIn("Eminem", w.empty.text); self.assertTrue(w.empty.IsShown(w.empty))
        self.assertEqual(w.load.text.text, a.L("musicLoadResults"))
        # after the reload the app's file has the results and the window opens on them
        lua.execute('EvertallyMusicData={schemaVersion=1,searchQuery="Eminem",search={{id="yt:video:abc",name="Lose Yourself",artist="Eminem"}}}')
        w.Hide(w); a.Dispatch("PLAYER_LOGIN")
        self.assertTrue(w.IsShown(w)); self.assertEqual(w.part, "search")
        self.assertEqual(w.rows[1].text.text, "Lose Yourself  ·  Eminem")

    def test_a_playlist_opens_to_its_songs_and_a_song_plays_inside_it(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(TIMER)
        lua.execute('''SENTCMD={};Evertally.OpticalSendCommand=function(t) SENTCMD[#SENTCMD+1]=t;return true end
            EvertallyMusicData={schemaVersion=1,source="youtube",playlists={
              {id="yt:playlist:PLa",name="Hudba",artist="Mardyx",tracks={{id="yt:video:v1",name="Prvni",artist="A"},{id="bad id",name="Spatne"},{id="yt:video:v2",name="Druha"}}},
              {id="yt:playlist:PLb",name=""},
              {id="yt:playlist:PLc",name="Bez skladeb",tracks={}}}}''')
        a.Music.SetEnabled(True); a.Music.ToggleBrowser()
        w = lua.globals().EvertallyMusicBrowser
        shown = lambda: [w.rows[i].text.text for i in range(1, 9) if w.rows[i].IsShown(w.rows[i])]
        self.assertEqual(shown(), ["+  Hudba  ·  Mardyx", a.L("musicUntitled"), "Bez skladeb"], "emoji-only name kept as untitled; empty song list is no playlist to open")
        w.rows[1].scripts.OnClick(w.rows[1])
        self.assertEqual(shown(), ["-  Hudba  ·  Mardyx", "      Prvni  ·  A", "      Druha", a.L("musicUntitled"), "Bez skladeb"])
        w.rows[3].scripts.OnDoubleClick(w.rows[3])
        w.rows[2].scripts.OnClick(w.rows[2]); w.play.scripts.OnClick(w.play)
        w.rows[1].scripts.OnDoubleClick(w.rows[1])
        sent = lua.globals().SENTCMD
        self.assertEqual([sent[i] for i in range(1, len(sent) + 1)],
                         ["m:pt:yt:video:v2@yt:playlist:PLa", "m:pt:yt:video:v1@yt:playlist:PLa", "m:pl:yt:playlist:PLa"])
        w.rows[1].scripts.OnClick(w.rows[1])
        self.assertEqual(len(shown()), 3, "a second click closes it")

    def test_the_filter_finds_songs_inside_playlists(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(TIMER)
        lua.execute('''EvertallyMusicData={schemaVersion=1,playlists={
              {id="spotify:playlist:a",name="Leveling",tracks={{id="spotify:track:1",name="Píseň",artist="Čechomor"},{id="spotify:track:2",name="Other"}}},
              {id="spotify:playlist:b",name="Chill"}}}''')
        lines = a.Music.Lines("playlists", "cecho", None)
        self.assertEqual([lines[i].e.name for i in range(1, len(lines) + 1)], ["Leveling", "Píseň"], "only the matching song, opened")
        lines = a.Music.Lines("playlists", "cecho", lua.eval('{["spotify:playlist:a"]=false}'))
        self.assertEqual(len(lines), 1, "the player can still close it")
        self.assertEqual(len(a.Music.Lines("playlists", "chill", None)), 1)

    def test_after_a_reload_the_player_comes_back_even_from_a_place_off_the_screen(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(TIMER)
        lua.execute("UIParent.GetWidth=function() return 1600 end;UIParent.GetHeight=function() return 900 end")
        lua.execute("Evertally.db.settings.music={enabled=true,playerAt={x=5000,y=-40}}")
        a.Dispatch("PLAYER_LOGIN"); a.Dispatch("PLAYER_ENTERING_WORLD"); lua.execute("RunTimers()")
        player = lua.globals().EvertallyMusicPlayer
        self.assertTrue(player.IsShown(player))
        self.assertIsNone(a.db.settings.music.playerAt, "a place off the screen is forgotten")

    def test_an_error_while_drawing_the_player_is_counted_not_hidden(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(TIMER)
        lua.execute("Evertally.db.settings.music={enabled=true};Evertally.Music.Player=function() error('boom') end")
        a.Dispatch("PLAYER_ENTERING_WORLD")
        self.assertEqual(a.errors.music, 1)
        self.assertIn("boom", a.Music.lastError)
        self.assertIn("music: ", a.Diagnostics())

    def test_the_small_player_remembers_where_it_was_put(self):
        lua, a = runtime(); lua.execute(MOCK_UI_LUA); lua.execute(TIMER)
        lua.execute("Evertally.db.settings.music={enabled=true,playerAt={x=40,y=300}}")
        a.Music.Refresh()
        player = lua.globals().EvertallyMusicPlayer
        self.assertTrue(player.IsShown(player))
        lua.execute("EvertallyMusicPlayer.GetLeft=function() return 123.4 end;EvertallyMusicPlayer.GetBottom=function() return 456.6 end")
        player.scripts.OnDragStop(player)
        at = a.db.settings.music.playerAt
        self.assertEqual((at.x, at.y), (123, 457))

    def test_texts_in_both_languages(self):
        lua, a = runtime()
        for lang in ("en", "cs"):
            for key in ("musicEnabled", "musicDuck", "musicSearch", "musicNoLibrary", "musicRefresh", "musicLoad"):
                self.assertTrue(a.locale[lang][key], (lang, key))


if __name__ == "__main__":
    unittest.main()
