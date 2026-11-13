"""The forum of the Community page: validation of the website's copy, the player's outbox, merging and the page itself (mock frames)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime  # noqa: E402

DATA = '''
EvertallyForumData={schemaVersion=1,generatedAt=NOW-100,count=2,threads={
 {id="wabcdef012345",category="dungeons",title="Deadmines v pátek",author="Aria-Fixture Realm",classId=8,origin="web",pinned=false,createdAt=NOW-5000,lastPostAt=NOW-300,replies=1,posts={
  {id="wabcdef012345",author="Aria-Fixture Realm",classId=8,origin="web",body="Kdo jde?\\nHledám healera |cffff0000.",createdAt=NOW-5000},
  {id="gpost00112233",author="Bran-Other Realm",origin="game",body="Já.",createdAt=NOW-300,replyTo="wabcdef012345"}}},
 {id="wpinned123456",category="general",title="Pravidla",author="Admin",origin="web",pinned=true,createdAt=NOW-9000,lastPostAt=NOW-9000,replies=0,posts={
  {id="wpinned123456",author="Admin",origin="web",body="Buďte slušní.",createdAt=NOW-9000}}}}}
'''


class ForumTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute("date=os.date")
        self.a.ForumResetCache()
        self.a.ForumResetThrottle()

    def load(self, code=DATA):
        self.lua.execute(code)
        self.a.ForumResetCache()

    def test_valid_copy_is_read_pinned_first_with_full_author_names(self):
        self.load()
        threads = self.a.ForumThreads("")
        self.assertEqual([threads[i].id for i in (1, 2)], ["wpinned123456", "wabcdef012345"])
        deadmines = self.a.ForumThread("wabcdef012345")
        self.assertEqual(deadmines.posts[2].author, "Bran-Other Realm")
        self.assertEqual(deadmines.author, "Aria-Fixture Realm")
        self.assertEqual(len(self.a.ForumThreads("dungeons")), 1)
        self.assertEqual(len(self.a.ForumThreads("trading")), 0)

    def test_damaged_threads_are_dropped_but_the_rest_shows(self):
        self.load(DATA.replace('category="general"', 'category="politics"'))
        info = self.a.ForumInfo()
        self.assertEqual(info.total, 1)
        self.assertEqual(info.dropped, 1)
        self.assertFalse(info.invalid)

    def test_hostile_or_foreign_data_shows_nothing(self):
        for code in ['EvertallyForumData={schemaVersion=2,generatedAt=1,threads={}}',
                     'EvertallyForumData={schemaVersion=1,generatedAt=NOW-1,threads={},extra=1}',
                     'EvertallyForumData="text"',
                     'EvertallyForumData={schemaVersion=1,generatedAt=NOW+999999,threads={}}']:
            self.load(code)
            self.assertEqual(self.a.ForumInfo().total, 0, code)
        self.load('EvertallyForumData={schemaVersion=1,generatedAt=NOW-1,threads={{id="wabcdef012345",category="general",title="x\\0y",author="A",origin="web",pinned=false,createdAt=1,lastPostAt=1,posts={{id="wabcdef012345",author="A",origin="web",body="b",createdAt=1}}}}}')
        self.assertEqual(self.a.ForumInfo().total, 0)

    def test_no_data_file_means_an_empty_forum(self):
        self.lua.execute("EvertallyForumData=nil")
        self.a.ForumResetCache()
        info = self.a.ForumInfo()
        self.assertEqual((info.total, info.pending), (0, 0))
        self.assertIsNone(info.generatedAt)

    def test_new_thread_goes_to_the_outbox_under_the_full_name_and_shows_at_once(self):
        ok, tid = self.a.ForumNewThread("trading", "  Prodám   rudu ", "Měď a cín.\r\n\r\n\r\nPíšte.")
        self.assertTrue(ok)
        entry = self.a.ForumOutbox()[1]
        self.assertEqual((entry.kind, entry.author, entry.title, entry.classId), ("thread", "Fixture Hero-Fixture Realm", "Prodám rudu", 7))
        self.assertEqual(entry.body, "Měď a cín.\n\nPíšte.")
        thread = self.a.ForumThread(tid)
        self.assertTrue(thread.pending)
        self.assertTrue(thread.posts[1].pending)

    def test_reply_is_merged_into_the_thread_and_bad_input_is_refused(self):
        self.load()
        self.assertEqual(self.a.ForumReply("wabcdef012345", "   ")[1], "body")
        self.assertEqual(self.a.ForumReply("wnothread123", "x")[1], "thread")
        self.assertEqual(self.a.ForumNewThread("nope", "Název", "x")[1], "category")
        self.assertEqual(self.a.ForumNewThread("general", "ab", "x")[1], "title")
        ok, pid = self.a.ForumReply("wabcdef012345", "Přijdu.", "gpost00112233")
        self.assertTrue(ok)
        thread = self.a.ForumThread("wabcdef012345")
        self.assertEqual(len(thread.posts), 3)
        self.assertEqual(thread.posts[3].replyTo, "gpost00112233")
        self.assertEqual(thread.replies, 2)
        self.assertEqual(thread.posts[3].author, "Fixture Hero-Fixture Realm")

    def test_posts_are_throttled_not_in_combat_and_bounded(self):
        self.assertTrue(self.a.ForumNewThread("general", "První", "a")[0])
        self.assertEqual(self.a.ForumNewThread("general", "Druhé", "b")[1], "too_fast")
        self.a.ForumResetThrottle()
        self.lua.execute("INCOMBAT=true")
        self.assertEqual(self.a.ForumNewThread("general", "Třetí", "c")[1], "combat")
        self.lua.execute("INCOMBAT=false")
        self.assertTrue(self.a.ForumNewThread("general", "T" * 200, "ž" * 2000)[0])
        entry = self.a.ForumOutbox()[2]
        self.assertEqual(len(entry.title), 80)
        self.assertEqual(len(entry.body), 800)

    def test_outbox_entries_leave_when_the_website_copy_has_them_or_when_too_old(self):
        ok, tid = self.a.ForumNewThread("general", "Moje vlákno", "text")
        self.a.ForumResetThrottle()
        ok2, pid = self.a.ForumReply(tid, "odpověď")
        self.assertEqual(len(self.a.ForumOutbox()), 2)
        self.load('EvertallyForumData={schemaVersion=1,generatedAt=NOW-1,threads={{id="%s",category="general",title="Moje vlákno",author="Fixture Hero-Fixture Realm",origin="game",pinned=false,createdAt=NOW-10,lastPostAt=NOW-5,replies=1,posts={{id="%s",author="Fixture Hero-Fixture Realm",origin="game",body="text",createdAt=NOW-10},{id="%s",author="Fixture Hero-Fixture Realm",origin="game",body="odpověď",createdAt=NOW-5,replyTo="%s"}}}}}' % (tid, tid, pid, tid))
        self.assertEqual(self.a.ForumPrune(), 2)
        self.assertEqual(len(self.a.ForumThread(tid).posts), 2)
        self.lua.execute("EvertallyForumData=nil")
        self.a.ForumResetCache()
        self.a.ForumResetThrottle()
        self.a.ForumNewThread("general", "Stará", "x")
        self.lua.execute("NOW=NOW+15*86400")
        self.assertEqual(self.a.ForumPrune(), 1)

    def test_outbox_stays_in_the_saved_history_and_never_enters_the_export(self):
        self.a.ForumNewThread("general", "Nevyexportuj", "tajný text")
        self.assertIn("outbox", self.a.Encode(self.a.db.forum))
        self.assertEqual(len(self.a.db.events), 0)
        self.assertNotIn("Nevyexportuj", self.a.Encode(self.a.ExportStore()))
        self.assertNotIn("Nevyexportuj", self.a.Encode(self.a.MakeSummary()))


class ForumPageTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute("date=os.date")
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(DATA)
        self.a.ForumResetCache()
        self.a.ForumResetThrottle()

    def open(self):
        self.a.ShowView("community")
        self.assertIsNone(self.a.lastUIError)
        return self.a.forumPage

    def test_page_lists_threads_and_reads_the_first_one_with_full_names(self):
        page = self.open()
        items = page.list["items"]
        self.assertEqual(items[1].title, "* Pravidla")
        self.assertTrue(items[2].sub.startswith("Aria-Fixture"))
        self.assertEqual(page.threadId, "wpinned123456")
        page.list["items"][2].onClick()
        self.assertEqual(page.threadId, "wabcdef012345")
        spec = page.doc.spec
        self.assertEqual(spec.title, "Deadmines v pátek")
        texts = [spec.entries[i].text for i in range(1, len(spec.entries) + 1)]
        self.assertTrue(any(t.startswith("Aria-Fixture Realm") for t in texts), "the complete author remains in the opened thread")
        self.assertTrue(any(t.startswith("Bran-Other Realm") for t in texts))
        self.assertTrue(any("||cffff0000" in t for t in texts))  # a pipe from the website can never start a colour code

    def test_category_chip_filters_and_new_thread_is_posted_through_the_writing_window(self):
        page = self.open()
        dungeons = next(page.chips[i] for i in range(1, len(page.chips) + 1) if page.chips[i].categoryId == "dungeons")
        dungeons.scripts.OnClick()
        self.assertEqual(len(page.list["items"]), 1)
        page.newButton.scripts.OnClick()
        f = self.lua.globals().EvertallyForumCompose
        self.assertEqual(f.mode, "thread")
        self.assertEqual(f.category, "dungeons")
        f.titleBox.text, f.body.text = "Nové z hry", "Obsah příspěvku"
        ok, tid = self.a.ForumSubmitCompose()
        self.assertTrue(ok)
        self.assertFalse(f.shown)
        self.assertEqual(page.threadId, tid)
        self.assertEqual(self.a.ForumOutbox()[1].category, "dungeons")

    def test_empty_forum_explains_how_to_get_the_websites_posts(self):
        self.lua.execute("EvertallyForumData=nil")
        self.a.ForumResetCache()
        page = self.open()
        self.assertEqual(len(page.list["items"]), 0)
        self.assertEqual(page.doc.spec.key, "welcome")
        self.assertEqual(page.info.text, self.a.L("forumNoCopy"))

    def test_search_combines_category_title_author_and_post_body_with_czech_case(self):
        page = self.open()
        def search(text):
            page.search.SetText(page.search, text)
            page.search.scripts.OnTextChanged(page.search)
        search("PÁTEK")
        self.assertEqual(len(page.list["items"]), 1)
        self.assertEqual(page.doc.spec.title, "Deadmines v pátek")
        search("HEALERA")
        self.assertEqual(len(page.list["items"]), 1, "search includes visible post bodies")
        search("BRAN-OTHER REALM")
        self.assertEqual(len(page.list["items"]), 1, "search includes reply authors")
        general = next(page.chips[i] for i in range(1, len(page.chips) + 1) if page.chips[i].categoryId == "general")
        general.scripts.OnClick()
        self.assertEqual(len(page.list["items"]), 0)
        self.assertEqual(page.doc.spec.entries[1].text, self.a.L("forumNoResults"))
        page.clearSearch.scripts.OnClick()
        self.assertEqual(page.query, "")
        self.assertEqual(len(page.list["items"]), 1)

    def test_search_includes_pending_local_post_without_accessing_any_web(self):
        ok, tid = self.a.ForumNewThread("general", "Nové téma", "Čerstvý příspěvek")
        self.assertTrue(ok)
        page = self.open()
        page.search.SetText(page.search, "ČERSTVÝ")
        page.search.scripts.OnTextChanged(page.search)
        self.assertEqual(len(page.list["items"]), 1)
        self.assertEqual(page.threadId, tid)

    def test_czech_texts_exist_for_every_english_forum_text(self):
        en, cs = self.lua.eval("Evertally.locale.en"), self.lua.eval("Evertally.locale.cs")
        missing = [k for k in en.keys() if str(k).startswith(("forum", "webfacts", "sub_webfacts")) and cs[k] is None]
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
