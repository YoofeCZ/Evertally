"""The redesigned in-game window (mock frames): resizing, side menu, overview, journal and leaderboard. No running WoW needed."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime  # noqa: E402

VIEWS = ["overview", "journal", "history", "places", "facts", "professions", "questguide", "gear", "training", "database", "dungeons", "recipes", "talents", "world", "guides", "community", "social", "rankings", "webfacts", "settings"]


def lst(table):
    return [table[i] for i in range(1, len(table) + 1)]


class WindowTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute("date=os.date")
        self.lua.execute(MOCK_UI_LUA)
        self.kit_ready = False

    # ---- helpers ----
    def story(self):
        """A few days of play: quests, loot, places, a dungeon."""
        self.lua.execute("""
        local A=Evertally
        for day=3,0,-1 do
            NOW=1794236400-day*86400
            A.Record("quest.accepted",{questId=100+day,title="Quest "..day})
            A.Record("quest.turned_in",{questId=100+day,title="Quest "..day})
            A.Record("loot.received",{itemId=2136,name="Conjured Water",quantity=2})
        end
        NOW=1794236400
        A.Record("zone.visited",{mapId=1429,mapName="Elwynn Forest",mapSystem="ui_map"})
        A.Record("quest.accepted",{questId=900,title="Open quest"})
        A.Record("quest.abandoned",{questId=901,title="Dropped quest"})
        A.Record("npc.observed",{npcId=1,name="Noise"})
        """)

    def buttons(self):
        return [self.lua.globals().MOCKBUTTONS[i] for i in range(1, len(self.lua.globals().MOCKBUTTONS) + 1)]

    def nav(self):
        return {str(b.viewKey): b for b in self.buttons() if b.viewKey}

    def open_view(self, view):
        nav = self.nav()
        nav[view].scripts.OnClick(nav[view])

    def assert_clean(self):
        for key in ("overview_page", "journal_page", "rankings_page", "social_page", "world_page", "gear_page", "training_page", "questguide_page", "ui_refresh"):
            self.assertIsNone(self.a.errors[key], "%s: %s" % (key, self.a.lastUIError))
        self.assertIsNone(self.a.lastUIError)

    # ---- the side menu and every page ----
    def test_every_page_builds_and_draws_with_and_without_data(self):
        self.a.OpenUI()
        for view in VIEWS: self.open_view(view)
        self.assert_clean()
        self.story()
        self.lua.execute("Evertally.db.runs={{character={id='Player-TEST-own',name='Fixture Hero'},status='completed',name='The Deadmines',durationMs=1800000}}")
        for view in VIEWS: self.open_view(view)
        self.assert_clean()

    def test_the_side_menu_is_grouped_and_remembers_the_page(self):
        self.a.OpenUI()
        self.assertEqual(list(self.nav().keys()), VIEWS)
        self.open_view("rankings")
        self.assertEqual(self.a.db.settings.lastView, "rankings")
        self.lua.execute("EvertallyFrame:Hide()")
        self.lua.execute("EvertallyFrame=nil")  # a fresh build, as after a reload
        # (the window object is a local of the addon: opening again keeps the page it was on)
        self.a.OpenUI()
        self.assert_clean()

    def test_a_failing_page_is_counted_and_does_not_take_the_window_down(self):
        self.a.OpenUI()
        self.lua.execute("Evertally.RankingRows=function() error('boom') end")
        self.open_view("rankings")
        self.assertEqual(self.a.errors.ui_refresh, 1)
        self.assertIn("boom", str(self.a.lastUIError))
        self.assertIn("ui:", self.a.Diagnostics(), "the last error is in /etally diag")
        self.open_view("overview")  # the rest of the window still works

    # ---- size ----
    def test_the_window_size_is_limited_kept_and_resettable(self):
        self.assertEqual(tuple(self.a.GetUISize()), (1120, 740), "the default")
        self.assertEqual(tuple(self.a.SetUISize(100, 100)), (700, 460), "never smaller than the minimum")
        self.assertEqual(tuple(self.a.SetUISize(99999, 99999)), (1890, 1050), "never bigger than the screen")
        self.assertEqual(tuple(self.a.SetUISize(1000.4, 700.6)), (1000, 701), "whole pixels")
        self.assertEqual((self.a.db.settings.uiWidth, self.a.db.settings.uiHeight), (1000, 701))
        self.a.db.settings.uiWidth = "junk"
        self.assertEqual(self.a.GetUISize()[0], 1120, "a damaged value falls back")
        self.a.db.settings.uiWidth, self.a.db.settings.uiHeight = 1200, 800
        self.a.OpenUI()
        frame = self.lua.globals().EvertallyFrame
        self.assertEqual((frame.w, frame.h), (1200, 800), "built at the saved size")
        self.a.SetUISize(800, 500)
        self.assertEqual((frame.w, frame.h), (800, 500))
        self.assertEqual(tuple(self.a.ResetUISize()), (1120, 740))
        self.assertEqual((frame.w, frame.h), (1120, 740))
        self.assertIsNone(self.a.db.settings.uiWidth)

    def test_a_narrow_window_shows_only_the_icons_in_the_side_menu(self):
        self.a.OpenUI()
        nav = self.nav()
        self.assertTrue(nav["journal"].text.shown, "wide: names next to the icons")
        self.a.SetUISize(760, 500)
        self.assertFalse(nav["journal"].text.shown, "narrow: icons only")
        self.a.SetUISize(1000, 500)
        self.assertTrue(nav["journal"].text.shown)

    def test_the_slash_command_resets_the_window(self):
        self.a.OpenUI(); self.a.SetUISize(800, 500)
        self.lua.execute('SlashCmdList.EVERTALLY("reset")')
        self.assertEqual(tuple(self.a.GetUISize()), (1120, 740))

    # ---- the overview ----
    def test_the_chart_counts_per_day_and_ignores_noise(self):
        self.story()
        days = lst(self.a.ActivityByDay(14))
        self.assertEqual(len(days), 14)
        today = days[-1]
        self.assertEqual([today['values'][i] for i in range(1, 5)], [1, 1, 1, 0], "quest done, loot, place, no dungeon")
        self.assertEqual(today.total, 3)
        yesterday = days[-2]
        self.assertEqual([yesterday['values'][i] for i in range(1, 5)], [1, 1, 0, 0])
        self.assertEqual(sum(d.total for d in days), 3 + 3 * 2, "the npc sighting is not counted")

    def test_the_axis_maximum_is_a_round_number(self):
        nice = self.a.NiceMax
        self.assertEqual([nice(v) for v in (0, 1, 3, 4)], [1, 1, 3, 4])
        self.assertEqual([nice(v) for v in (5, 7, 11, 23, 41, 99, 101)], [5, 10, 20, 40, 50, 100, 200])

    def test_money_and_story_kinds(self):
        self.assertIn("12", str(self.a.FormatMoney(123456)))
        self.assertEqual(self.a.JournalCategory("quest.turned_in"), "quests")
        self.assertEqual(self.a.JournalCategory("loot.received"), "loot")
        self.assertIsNone(self.a.JournalCategory("npc.observed"), "raw sightings belong to the Atlas")
        self.assertEqual(self.a.Upper("Splněný quest"), "SPLNĚNÝ QUEST")

    # ---- the journal ----
    def test_the_journal_groups_by_day_filters_and_searches(self):
        self.story()
        self.a.OpenUI()
        kit = self.a.UIKit()
        items, counts, matches, states = self.a.JournalItems(kit, "all", "")
        self.assertEqual((counts.all, counts.quests, counts.loot, counts.places), (15, 10, 4, 1))
        headings = [i for i in lst(items) if i.heading is not None]
        self.assertEqual(len(headings), 4, "four days")
        self.assertEqual(str(headings[0].heading), str(self.a.L("journalToday")))
        self.assertEqual(str(headings[1].heading), str(self.a.L("journalYesterday")))
        self.assertEqual(matches, counts.all)
        loot, _, loot_matches, _ = self.a.JournalItems(kit, "loot", "")
        self.assertEqual(loot_matches, 4)
        self.assertTrue(all(i.heading is not None or i.icon is not None for i in lst(loot)))
        found, _, n, _ = self.a.JournalItems(kit, "all", "open quest")
        self.assertEqual(n, 1, "search ignores case")
        czech, _, n, _ = self.a.JournalItems(kit, "all", "ZZZ nothing")
        self.assertEqual(n, 0); self.assertEqual(len(lst(czech)), 0)

    def test_the_quest_filter_is_a_quest_log_with_one_row_per_quest(self):
        self.story()
        self.a.OpenUI()
        kit = self.a.UIKit()
        items, counts, matches, states = self.a.JournalItems(kit, "quests", "")
        self.assertEqual((states.open, states.done, states.dropped), (1, 4, 1), "the latest event of each quest decides")
        self.assertEqual(matches, 6, "six quests, not ten events")

    # ---- the leaderboard ----
    def peers(self):
        self.lua.execute("""
        local A=Evertally
        A.db.runs={{character={id='Player-TEST-own',name='Fixture Hero'},status='completed',name='The Deadmines',durationMs=1800000},
                   {character={id='Player-TEST-own',name='Fixture Hero'},status='completed',name='Wailing Caverns',durationMs=2400000}}
        A.peerDB.peers.Bran={producerId='p1',receivedAt=NOW,completedRuns=7,character={id='Player-B',name='Bran',classId=8,raceId=1,level=33},
            runs={{name='The Deadmines',status='completed',durationMs=1500000}}}
        A.peerDB.peers.Mira={producerId='p2',receivedAt=NOW,character={id='Player-M',name='Mira',classId=5,raceId=2,level=18},
            runs={{name='The Deadmines',status='completed',durationMs=2100000},{name='The Deadmines',status='interrupted',durationMs=100}}}
        """)

    def test_the_leaderboard_ranks_by_runs_level_and_best_time(self):
        self.peers()
        self.a.OpenUI()
        kit = self.a.UIKit()
        runs = lst(self.a.RankingRows(kit, "runs"))
        self.assertEqual([str(r.name) for r in runs], ["Bran", "Fixture Hero", "Mira"], "7, 2 and 1 completed runs")
        self.assertEqual([str(r.valueText) for r in runs], ["7", "2", "1"])
        self.assertEqual([r.rank for r in runs], [1, 2, 3])
        self.assertTrue(runs[1].own and not runs[0].own)
        self.assertEqual(runs[0].fraction, 1); self.assertAlmostEqual(runs[1].fraction, 2 / 7)
        level = lst(self.a.RankingRows(kit, "level"))
        self.assertEqual([str(r.name) for r in level], ["Bran", "Fixture Hero", "Mira"], "33, 20 and 18")
        fastest = lst(self.a.RankingRows(kit, "fastest"))
        self.assertEqual([str(r.name) for r in fastest], ["Bran", "Fixture Hero", "Mira"], "25:00, 30:00 and 35:00")
        self.assertEqual(str(fastest[0].valueText), "25:00")
        self.assertAlmostEqual(fastest[1].fraction, 1500000 / 1800000)
        dungeons = lst(self.a.RankingRows(kit, "dungeons"))
        self.assertEqual([str(r.name) for r in dungeons], ["The Deadmines", "Wailing Caverns"])
        self.assertEqual(str(dungeons[0].valueText), "25:00", "the best of three players")
        self.assertIn("3", str(dungeons[0].sub), "three players have run it")
        self.assertTrue(dungeons[1].own, "only you have run the caverns")

    def test_the_leaderboard_page_says_where_you_stand(self):
        self.peers()
        self.a.OpenUI()
        self.open_view("rankings")
        self.assert_clean()
        # one player alone: it says so instead of a rank
        self.lua.execute("Evertally.peerDB.peers={}")
        self.open_view("overview"); self.open_view("rankings")
        self.assert_clean()

    def test_the_leaderboard_includes_the_websites_public_board_once_per_player(self):
        self.peers()
        # Bran shared in game and is on the website too; you (Fixture Hero) are on the website as well
        self.lua.execute('''
        Evertally.peerDB.peers.Bran.character.realm="Fixture Realm"
        EvertallyRankingData={schemaVersion=1,kind="evertally-ranking",generatedAt=NOW-60,expiresAt=NOW+3600,total=4,truncated=false,
          players={{n="Aerin",r="Firemaw",k=1,u=9,l=60,c=11,x=4},{n="Bran",r="FixtureRealm",k=2,u=7,l=33,c=8,x=1},
                   {n="Fixture",r="Fixture Realm",k=3,u=2,l=20,c=2,x=1},{n="Kesh",r="Firemaw",k=4,u=0,l=12,c=1,x=2}}}
        UnitFullName=function() return "Fixture","Fixture Realm" end
        ''')
        self.a.OpenUI()
        kit = self.a.UIKit()
        runs = lst(self.a.RankingRows(kit, "runs"))
        self.assertEqual([str(r.name) for r in runs], ["Aerin", "Bran", "Fixture", "Mira", "Kesh"], "9, 7, 2, 1 and 0 completed runs; nobody twice")
        self.assertIn("website #1", str(runs[0].sub))
        self.assertTrue(runs[2].own)
        level = lst(self.a.RankingRows(kit, "level"))
        self.assertEqual(str(level[0].name), "Aerin")
        fastest = lst(self.a.RankingRows(kit, "fastest"))
        self.assertNotIn("Aerin", [str(r.name) for r in fastest], "no times arrive from the website, so no best time")
        self.lua.execute("EvertallyRankingData.expiresAt=NOW-1")
        self.assertNotIn("Aerin", [str(r.name) for r in lst(self.a.RankingRows(kit, "runs"))], "a stale package is ignored")
        self.lua.execute("EvertallyRankingData.expiresAt=NOW+3600")
        self.open_view("rankings")
        page = self.a.rankingsPage
        page.selection = self.lua.table(key="web:aerin|firemaw")
        self.open_view("overview"); self.open_view("rankings")
        self.assert_clean()

    # ---- people and what they showed you ----
    def receive_view(self):
        self.a.SetWeb(True); self.a.OpenUI()
        ok, ident = self.a.RequestInspect("Other-Fixture Realm", "ip")
        self.a.ReceiveMessage("Evtly1", "S|A|%s|ip|1" % ident, "WHISPER", "Other-Fixture Realm")
        self.a.ReceiveMessage("Evtly1", "S|D|%s|1|1|I1;E=1:987654;B=2589*20;P=171:225:300:Alchemy:97" % ident, "WHISPER", "Other-Fixture Realm")
        return self.lua.globals().EvertallyViewFrame

    def test_the_viewer_shows_gear_and_bags_as_icons_and_a_click_marks_what_you_want(self):
        viewer = self.receive_view()
        self.assertTrue(viewer.shown)
        self.assertIsNone(self.a.errors.social_viewer, self.a.lastUIError)
        gear = viewer.grid.cells[1]
        self.assertEqual(gear.item.itemId, 987654)
        self.assertEqual(str(gear.item.slot), "Head")
        self.assertIsNone(gear.item.mark)
        gear.scripts.OnClick(gear)
        self.assertEqual(viewer.wanted[987654], 1)
        self.assertEqual(str(viewer.grid.cells[1].item.mark), "want", "marked with the green frame")
        self.assertEqual(str(viewer.grid.cells[1].item.markText), str(self.a.L("viewWant")))
        viewer.tabs.bags.scripts.OnClick(viewer.tabs.bags)
        bag = viewer.grid.cells[1]
        self.assertEqual((bag.item.itemId, bag.item.count), (2589, 20))
        bag.scripts.OnClick(bag)
        self.assertEqual(viewer.wanted[2589], 1, "first click: one")
        bag.scripts.OnClick(bag)
        self.assertEqual(viewer.wanted[2589], 20, "second click: the whole stack")
        bag.scripts.OnClick(bag)
        self.assertIsNone(viewer.wanted[2589], "third click: off")
        viewer.tabs.professions.scripts.OnClick(viewer.tabs.professions)
        self.assertFalse(viewer.grid.shown); self.assertTrue(viewer.list.shown)
        self.assertIsNone(self.a.errors.social_viewer)

    def test_the_viewer_lists_quests_with_progress_and_reputations_with_standing(self):
        self.a.SetWeb(True); self.a.OpenUI()
        ok, ident = self.a.RequestInspect("Other-Fixture Realm", "qr")
        self.a.ReceiveMessage("Evtly1", "S|A|%s|qr|1" % ident, "WHISPER", "Other-Fixture Realm")
        self.a.ReceiveMessage("Evtly1", "S|D|%s|1|1|I1;Q=7:7:0:Kobold Camp Cleanup:4*10*Kobold Vermin slain 4/10~33:6:1:Wolves Across the Border:8*8*Tough Wolf Meat 8/8;"
                              "R=72:5:4200:3000:9000:Stormwind~47:4:0:0:3000:Ironforge" % ident, "WHISPER", "Other-Fixture Realm")
        viewer = self.lua.globals().EvertallyViewFrame
        self.assertIsNone(self.a.errors.social_viewer, self.a.lastUIError)
        viewer.tabs.quests.scripts.OnClick(viewer.tabs.quests)
        rows = lst(viewer.list["items"])
        self.assertEqual([str(r.title) for r in rows], ["[7] Kobold Camp Cleanup", "[6] Wolves Across the Border"])
        self.assertIn("4/10", str(rows[0].sub))
        self.assertEqual(str(rows[1].sub), str(self.a.L("viewQuestDone")), "every objective done: ready to turn in")
        self.assertTrue(viewer.list.shown and not viewer.grid.shown)
        viewer.tabs.reputation.scripts.OnClick(viewer.tabs.reputation)
        rows = lst(viewer.list["items"])
        self.assertEqual([str(r.title) for r in rows], ["Stormwind", "Ironforge"])
        self.assertEqual(str(rows[0].right), "Friendly")
        self.assertIn("1200/6000", str(rows[0].sub), "standing within the current level")
        self.assertIsNone(self.a.errors.social_viewer, self.a.lastUIError)

    def test_the_viewer_filters_by_name_sorts_and_groups_bags(self):
        self.a.SetWeb(True); self.a.OpenUI()
        ok, ident = self.a.RequestInspect("Other-Fixture Realm", "ip")
        self.a.ReceiveMessage("Evtly1", "S|A|%s|ip|1" % ident, "WHISPER", "Other-Fixture Realm")
        self.a.ReceiveMessage("Evtly1", "S|D|%s|1|1|I1;E=1:987654,5:987655;B=2589*20,2592*5,4306*3" % ident, "WHISPER", "Other-Fixture Realm")
        viewer = self.lua.globals().EvertallyViewFrame
        self.assertIsNone(self.a.errors.social_viewer, self.a.lastUIError)
        self.assertTrue(viewer.search.shown and viewer.sortBtn.shown)
        viewer.tabs.bags.scripts.OnClick(viewer.tabs.bags)
        self.assertEqual(str(viewer.summary.GetText(viewer.summary)), "3/3")
        # a search by item id narrows the grid (names are not loaded in the fixture)
        viewer.search.SetText(viewer.search, "2592")
        viewer.search.scripts.OnTextChanged(viewer.search)
        self.assertEqual(viewer.grid.cells[1].item.itemId, 2592)
        self.assertFalse(viewer.grid.cells[2].shown)
        self.assertEqual(str(viewer.summary.GetText(viewer.summary)), "1/3")
        viewer.search.SetText(viewer.search, "zzz")
        viewer.search.scripts.OnTextChanged(viewer.search)
        self.assertEqual(str(viewer.grid.empty.GetText(viewer.grid.empty)), str(self.a.L("viewNoMatch")))
        viewer.search.SetText(viewer.search, "")
        viewer.search.scripts.OnTextChanged(viewer.search)
        # cycle the sort to "type": group headers appear above the items and every item stays reachable
        for _ in range(3):
            viewer.sortBtn.scripts.OnClick(viewer.sortBtn)
        self.assertIn(str(self.a.L("viewSort_type")), str(viewer.sortBtn.text.GetText(viewer.sortBtn.text)))
        self.assertTrue(viewer.grid.heads[1].shown)
        self.assertEqual(sum(1 for c in viewer.grid.cells.values() if c.shown), 3)
        self.assertIsNone(self.a.errors.social_viewer, self.a.lastUIError)

    def test_the_look_page_lists_whoever_showed_you_something_and_draws_cleanly(self):
        self.receive_view()
        self.open_view("social")
        self.assert_clean()
        page = self.a.social.page
        self.assertEqual(page.mode, "live")
        self.assertFalse(page.cols.shown, "People (one list in categories) is the first mode; the request form is the second")
        for mode in ("live", "proposals", "meets", "privacy", "ask"):
            page.tabs[mode].scripts.OnClick(page.tabs[mode])
            self.assertEqual(page.mode, mode)
        self.assertTrue(page.cols.shown)
        page.tabs.privacy.scripts.OnClick(page.tabs.privacy)
        self.assertFalse(page.cols.shown, "the form belongs to the first mode only")
        self.assert_clean()

    def test_people_are_listed_in_categories_and_a_click_navigates_or_opens_the_form(self):
        self.receive_view()
        self.a.NoteEvertallyUser("Nobody-Fixture Realm")
        self.open_view("social")
        rows = self.a.SocialPeople()[0]
        items = [rows[i] for i in range(1, len(rows) + 1)]
        headings = [str(r.heading) for r in items if r.heading is not None]
        self.assertIn(str(self.a.L("peopleCatLinked")), headings)   # somebody showed you something
        self.assertIn(str(self.a.L("peopleCatUsers")), headings)    # a player known to run Evertally
        linked = next(r for r in items if r.heading is None and r.onClick is not None)
        page = self.a.social.page
        linked.onClick()                                            # no live position: the request form opens with the name
        self.assertEqual(page.mode, "ask")
        self.assertNotEqual(str(page.name.GetText(page.name)), "")

    # ---- People: category buttons, the website's players, one person per player ----
    def people(self, view="all"):
        rows, counts = self.a.SocialPeople(view)
        items = lst(rows)
        out, heading = [], None
        for r in items:
            if r.heading is not None: heading = str(r.heading)
            else: out.append((heading, str(r.title), str(r.sub)))
        return out, counts

    def web_board(self):
        self.lua.execute('''
        GetNormalizedRealmName=function() return "FixtureRealm" end
        EvertallyRankingData={schemaVersion=1,kind="evertally-ranking",generatedAt=NOW-60,expiresAt=NOW+3600,total=4,truncated=false,
          players={{n="Fixture",r="Fixture Realm",k=1,u=3,l=20,c=2,x=1},{n="Aerin",r="Fixture Realm",k=2,u=4,l=60,c=11,x=4},
                   {n="Mardyx",r="Valdren",k=3,u=0,l=13,c=8,x=7},{n="Mardyx",r="Warborn",k=4,u=0,l=6,c=1,x=1}}}
        ''')

    def test_people_include_the_websites_public_board_under_evertally(self):
        self.web_board()
        self.a.OpenUI(); self.open_view("social")
        people, counts = self.people("evertally")
        names = [(h, t) for h, t, _ in people]
        web = str(self.a.L("peopleCatWeb"))
        self.assertEqual(names, [(web, "Aerin"), (web, "Mardyx"), (web, "Mardyx")], "the board order; you are not on your own list; one name on two realms is two people")
        self.assertIn("web #2", people[0][2])
        self.assertIn("Valdren", people[1][2]); self.assertIn("Warborn", people[2][2])
        self.assertEqual(counts.evertally, 3)
        everybody, _ = self.people("all")
        self.assertEqual({h for h, _, _ in everybody}, {str(self.a.L("peopleCatUsers"))}, "in All they sit under Using Evertally")
        self.assertEqual(lst(self.a.SocialPeople("friends")[0]), [], "nobody else matches Friends")

    def test_a_player_named_name_space_realm_is_the_same_person_as_in_the_group(self):
        # WoW Forever names the sender of an addon message "Name Realm"; the group gives "Name"
        self.lua.execute('''
        UnitExists=function(u) return u=="party1" end
        UnitFullName=function(u) if u=="party1" then return "Vexara",nil end return "Fixture Hero","Fixture Realm" end
        UnitLevel=function() return 10 end
        ''')
        self.a.ReceiveMessage("Evtly1", "S|L|1411|470|660|9", "PARTY", "Vexara Nightcurse")
        self.a.NoteEvertallyUser("Vexara Nightcurse")
        self.a.OpenUI(); self.open_view("social")
        people, counts = self.people("all")
        self.assertEqual([(h, t) for h, t, _ in people], [(str(self.a.L("peopleCatLive")), "Vexara")], "one person, not two")
        self.assertIn(str(self.a.L("peopleFlag_group")), people[0][2])
        self.assertEqual((counts.all, counts.evertally, counts.group), (1, 1, 1))

    def test_the_category_buttons_pick_what_the_list_shows_and_are_remembered(self):
        self.web_board()
        self.lua.execute('''
        FRIENDS={{name="Thalia",level=42,connected=true,area="Stormwind City"},{name="Gone",level=10,connected=false}}
        C_FriendList={GetNumFriends=function() return #FRIENDS end,GetFriendInfoByIndex=function(i) return FRIENDS[i] end}
        ''')
        self.a.OpenUI(); self.open_view("social")
        page = self.a.social.page
        chips = page.filterChips
        self.assertEqual([str(self.a.PeopleFilters[i]) for i in range(1, 6)], ["all", "evertally", "friends", "group", "guild"])
        self.assertTrue(chips.all.on and chips.all.shown)
        self.assertEqual(str(chips.friends.text.GetText(chips.friends.text)), "Friends  2", "online and offline friends")
        self.assertEqual(str(chips.evertally.text.GetText(chips.evertally.text)), "Evertally  3")
        chips.friends.scripts.OnClick(chips.friends)
        self.assertEqual(self.a.db.settings.peopleFilter, "friends")
        self.assertTrue(chips.friends.on and not chips.all.on)
        shown = [str(r.title) for r in lst(page.list["items"]) if r.heading is None]
        self.assertEqual(shown, ["Thalia", "Gone"])
        chips.guild.scripts.OnClick(chips.guild)
        self.assertEqual(lst(page.list["items"]), [])
        self.assertEqual(str(page.list.emptyText), str(self.a.L("peopleNoneFilter")))
        page.tabs.privacy.scripts.OnClick(page.tabs.privacy)
        self.assertFalse(chips.all.shown, "the buttons belong to the People mode only")
        self.assert_clean()

    # ---- captions, people nearby ----
    def test_every_button_that_has_a_locale_key_has_a_caption_on_every_page(self):
        self.a.OpenUI()
        for view in VIEWS: self.open_view(view)
        empty = self.lua.eval('''(function() local bad={} for _,b in ipairs(MOCKBUTTONS) do
            if b.localeKey and type(b.text)=="table" and b.text.text=="" then bad[#bad+1]=b.localeKey end end return table.concat(bad,",") end)()''')
        self.assertEqual(empty, "", "an empty button: its page never set the caption")

    def test_the_look_page_lists_online_friends_and_guild_members_not_the_offline_ones(self):
        self.lua.execute('''
        FRIENDS={{name="Thalia",level=42,connected=true,area="Stormwind City"},{name="Gone",level=10,connected=false}}
        C_FriendList={GetNumFriends=function() return #FRIENDS end,GetFriendInfoByIndex=function(i) return FRIENDS[i] end}
        IsInGuild=function() return true end
        GetNumGuildMembers=function() return 2 end
        GetGuildRosterInfo=function(i) local r={{"Korgan-Realm","M",3,60,"Warrior","Ironforge","","",true,0,"WARRIOR"},{"Off-Realm","M",3,12,"Mage","","","",false,0,"MAGE"}}; return unpack(r[i]) end
        ''')
        self.a.OpenUI()
        self.open_view("social")
        rows = lst(self.a.SocialRoster())
        self.assertEqual([str(r.title) for r in rows], ["Thalia", "Korgan"], "friends first, then the guild; nobody offline")
        self.assertEqual(str(rows[0].sub), "friend  ·  Level 42  ·  Stormwind City")
        self.assertEqual(rows[1]["class"], 1, "the class comes from the guild roster")
        rows[1].onClick()
        self.assertEqual(self.a.social.page.name.text, "Korgan-Realm", "a click puts the name into the request")


if __name__ == "__main__":
    unittest.main()
