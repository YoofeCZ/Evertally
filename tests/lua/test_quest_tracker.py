"""The quest tracker (QuestTracker.lua): the guide window's Quests tab. Sections (ready, this zone, other zones,
dungeons and groups), distances from the guide's quest database, the arrow on a click, folding, the order."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import MOCK_UI_LUA, runtime

FAKE = r"""
  QLOG={{h="Elwynn Forest"},
    {id=1,t="Near Wolves",l=6,objs={{text="Prowler slain: 2/8",n=2,r=8}}},
    {id=2,t="Far Kobolds",l=7,objs={{text="Kobold Vermin slain: 0/10",n=0,r=10}}},
    {id=3,t="Done Already",l=5,objs={{text="Linen: 4/4",n=4,r=4,f=true}},done=true},
    {h="Westfall"},
    {id=4,t="Westfall Stew",l=12,objs={{text="Stringy Meat: 1/3",n=1,r=3}}},
    {h="Dungeons"},
    {id=5,t="Red Silk Bandanas",l=17,g=5,objs={{text="Bandana: 0/10",n=0,r=10}}}}
  C_QuestLog={GetNumQuestLogEntries=function() return #QLOG end,
    GetInfo=function(i) local q=QLOG[i]; if q.h then return {isHeader=true,title=q.h} end
      return {questID=q.id,title=q.t,level=q.l,suggestedGroup=q.g or 0,isComplete=q.done and 1 or nil} end,
    GetTimeAllowed=function(id) if id==2 then return 600, 100 end end}
  GetRealZoneText=function() return "Elwynn Forest" end
  TARGET=nil; LINK=nil; FIRED={}; SHOWN=false
  -- spawns: the wolves 10 yd away, the kobolds 300, the turn-in NPC 50, Westfall's meat on another continent
  local SPAWNS={[100]={{1,nil,10,0}}, [200]={{1,nil,300,0}}, [300]={{1,nil,50,0}}, [400]={{2,nil,5,5}}}
  EvertallyGuide={
    Fire=function(m) FIRED[#FIRED+1]=m end, SetHidden=function() end, GuideShown=function() return SHOWN end,
    Compat={IsQuestReadyForTurnIn=function(id) return id==3 end,
      GetQuestObjectives=function(id) for _,q in ipairs(QLOG) do if q.id==id then local o={}; for k,v in ipairs(q.objs) do o[k]={text=v.text,finished=v.f or false,numFulfilled=v.n,numRequired=v.r} end; return o end end end,
      ObjectiveLabel=function(t) return (t:gsub(":%s*%d+/%d+$","")) end,
      GetPlayerWorldPosition=function() return 1, 0, 0 end,
      MapToWorld=function(map, x, y) return map, x, y end},
    QuestDB={IsLoaded=function() return true end,
      GetQuest=function(id)
        local objectives={[1]={{kind="kill",id=100}},[2]={{kind="kill",id=200}},[4]={{kind="kill",id=400}},[5]={{kind="kill",id=200}}}
        return {id=id, finish={npc={300},object={}}, objectives=objectives[id] or {}} end,
      EachSpawn=function(ref, fn) for _,s in ipairs(SPAWNS[ref] or {}) do fn(nil,nil,s[1],s[2],s[3],s[4]) end end,
      EntityName=function(ref) return ref==300 and "Marshal Dughan" or ("NPC "..ref) end},
    Nav={SetTarget=function(map,x,y,label) TARGET={map,x,y,label} end}}
  IsShiftKeyDown=function() return SHIFT end
  GetQuestLink=function(id) return "|Hquest:"..id.."|h[link]|h" end
  ChatEdit_InsertLink=function(l) LINK=l end
"""


class QuestTrackerTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(FAKE)
        self.qt = self.a.QuestTracker

    def sections(self):
        sections, count = self.qt.Model()
        return [(str(s.key), [str(q.title) for q in s.quests.values()]) for s in sections.values()], count

    def test_sections_ready_this_zone_other_zones_then_dungeons_nearest_first(self):
        sections, count = self.sections()
        self.assertEqual(count, 5)
        self.assertEqual(sections, [("ready", ["Done Already"]), ("here", ["Near Wolves", "Far Kobolds"]),
                                    ("zone:Westfall", ["Westfall Stew"]), ("dungeons", ["Red Silk Bandanas"])])

    def test_the_order_by_level_and_as_in_the_log(self):
        self.a.db.settings.questTracker = self.lua.table_from({"sort": "level"})
        here = dict(self.sections()[0])["here"]
        self.assertEqual(here, ["Near Wolves", "Far Kobolds"])
        self.lua.execute("QLOG[2].l=9")
        self.assertEqual(dict(self.sections()[0])["here"], ["Far Kobolds", "Near Wolves"])
        self.a.db.settings.questTracker.sort = "log"
        self.assertEqual(dict(self.sections()[0])["here"], ["Near Wolves", "Far Kobolds"])

    def test_distance_and_turn_in_come_from_the_guides_database(self):
        log = self.qt.ReadLog()
        by = {str(q.title): q for q in log.values()}
        yards, point = self.qt.Nearest(by["Near Wolves"])
        self.assertEqual(round(yards), 10)
        yards, point = self.qt.Nearest(by["Done Already"])
        self.assertEqual(round(yards), 50, "a ready quest leads to its turn-in")
        self.assertEqual(str(by["Done Already"].turnIn), "Marshal Dughan")
        self.assertIsNone(self.qt.Nearest(by["Westfall Stew"])[0], "another continent: no distance")

    def layout(self):
        parent = self.lua.eval("CreateFrame")("Frame", None, None)
        frame = self.qt.Attach(parent)
        frame.Show(frame)
        h = self.qt.Layout(320, 600)
        rows = [r for r in frame.rows.values() if r.shown]
        return frame, rows, h

    def test_rows_objectives_with_counts_a_turn_in_and_a_timer(self):
        frame, rows, h = self.layout()
        texts = [str(r.text.text) for r in rows]
        self.assertIn("Prowler slain", texts)
        self.assertIn(self.a.L("qtTurnIn") % "Marshal Dughan", texts)
        notes = [str(r.note.text) for r in rows]
        self.assertIn("2/8", notes)
        self.assertIn(self.a.L("qtYards") % 10, notes)
        self.assertIn(self.a.L("qtTime") % "8:20", texts)
        self.assertEqual(str(self.qt.Title()), self.a.L("qtTitle") % (5, 20))

    def test_a_click_sets_the_arrow_shift_links_a_heading_folds(self):
        frame, rows, h = self.layout()
        wolves = next(r for r in rows if r.quest and str(r.quest.title) == "Near Wolves")
        wolves.scripts.OnClick(wolves, "LeftButton")
        target = self.lua.globals().TARGET
        self.assertEqual((target[1], target[2], target[3]), (1, 10, 0))
        self.lua.globals().SHIFT = True
        wolves.scripts.OnClick(wolves, "LeftButton")
        self.assertEqual(str(self.lua.globals().LINK), "|Hquest:1|h[link]|h")
        self.lua.globals().SHIFT = False
        self.a.db.settings.questTracker.mode = "quests"
        heading = next(r for r in rows if r.section == "here")
        heading.scripts.OnClick(heading, "LeftButton")
        self.assertTrue(self.a.db.settings.questTracker.folded["here"])
        frame, rows, h = self.layout()
        self.assertNotIn("Near Wolves", [str(r.quest.title) for r in rows if r.quest])

    def test_the_tab_is_remembered_and_the_menu_opens_the_window_on_it(self):
        self.assertEqual(self.qt.Mode(), "guide")
        self.assertTrue(self.a.ShowQuestTracker())
        self.assertEqual(self.qt.Mode(), "quests")
        self.assertIn("TOGGLE_FRAME", list(self.lua.globals().FIRED.values()), "the window was closed: opened")
        flat = [str(i.key) for g in self.a.EvertallyMenuGroups().values() for i in g["items"].values()]
        self.assertIn("menuQuests", flat)
        for lang in ("en", "cs"):
            for key in ("qtGuide", "qtQuests", "qtTitle", "qtReady", "qtDungeons", "qtMenu", "qtTurnIn", "qtAbandon", "qtSort_distance"):
                self.assertTrue(self.a.locale[lang][key], (lang, key))


if __name__ == "__main__":
    unittest.main()
