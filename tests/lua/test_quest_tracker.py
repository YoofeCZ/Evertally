"""The quest tracker (QuestTracker.lua): the guide window's Quests tab. Sections (this zone with the current step's
quests first, other zones, dungeons and groups, ready to turn in last), distances from the guide's quest database, the arrow on a click, folding, the order."""
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

    def test_sections_this_zone_other_zones_dungeons_then_ready_nearest_first(self):
        sections, count = self.sections()
        self.assertEqual(count, 5)
        self.assertEqual(sections, [("here", ["Near Wolves", "Far Kobolds"]), ("zone:Westfall", ["Westfall Stew"]),
                                    ("dungeons", ["Red Silk Bandanas"]), ("ready", ["Done Already"])])

    def test_the_current_steps_quests_lead_the_zone_wherever_they_are(self):
        # the guide's step on the kobolds (far) and the Westfall stew (another zone): both on top of this zone
        self.lua.execute("EvertallyGuide.UI={GuideFrame={View=function() return {goals={{quest=2},{quest=4}}} end}}")
        sections = dict(self.sections()[0])
        self.assertEqual(sections["here"], ["Far Kobolds", "Westfall Stew", "Near Wolves"])
        self.assertNotIn("zone:Westfall", sections)
        frame, rows, h = self.layout()
        marked = [str(r.quest.title) for r in rows if r.quest and r.mark.shown]
        self.assertEqual(sorted(marked), ["Far Kobolds", "Westfall Stew"])

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

    def test_czech_titles_and_objectives_come_from_wowfcz_where_installed(self):
        self.lua.execute('''WowfCZ_QuestData={[1]={Title="Blízcí vlci",Objectives={}},[2]={Title="Kobold $N"},[4]={Title="Polévka",Objectives={["Stringy Meat"]="Šlachovité maso"}}}
          WowfCZ_ItemData={[9]={e="Linen",n="Plátno"}}''')
        self.assertEqual(sorted(dict(self.sections()[0])["here"]), ["Far Kobolds", "Near Wolves"], "English while Evertally is in English")
        self.a.db.settings.language = "cs"
        log = {int(q.id): q for q in self.qt.ReadLog().values()}
        self.assertEqual(str(log[1].title), "Blízcí vlci")
        self.assertEqual(str(log[1].titleEn), "Near Wolves")
        self.assertEqual(str(log[2].title), "Far Kobolds", "a title with a $ token stays the game's")
        self.assertEqual(str(log[4].objectives[1].label), "Šlachovité maso")
        self.assertEqual(str(log[1].objectives[1].label), "Zabít Prowler")
        self.assertEqual(str(log[3].objectives[1].label), "Plátno")
        self.lua.execute("WowfCZ_QuestData=nil")
        self.assertEqual(str({int(q.id): q for q in self.qt.ReadLog().values()}[1].title), "Near Wolves", "without WowfCZ: English")

    def test_a_map_pins_quest_tooltip_turns_czech(self):
        self.a.db.settings.language = "cs"
        self.lua.execute('''WowfCZ_QuestData={[1]={Title="Blízcí vlci"}}
          C_QuestLog.GetTitleForQuestID=function(id) return id==1 and "Near Wolves" or nil end
          LINES={}; for i=1,3 do LINES[i]={t=nil, SetText=function(s,x) s.t=x end, GetText=function(s) return s.t end,
            GetFont=function() return "X", 12, "" end, SetFont=function(s,f) s.f=f end} ; _G["GameTooltipTextLeft"..i]=LINES[i] end
          PIN={data={id=1}}
          TIP={GetOwner=function() return PIN end, NumLines=function() return 2 end, Show=function() end}
          LINES[1].t="Near Wolves"; LINES[2].t="- Prowler slain: 2/8"''')
        self.assertTrue(self.qt.CzechTooltip(self.lua.globals().TIP))
        self.assertEqual(str(self.lua.globals().LINES[1].t), "Blízcí vlci")
        self.assertEqual(str(self.lua.globals().LINES[2].t), "- Zabít Prowler: 2/8")
        self.lua.execute('LINES[1].t="Something Else"')
        self.assertFalse(self.qt.CzechTooltip(self.lua.globals().TIP), "another tooltip is left alone")
        # over the world map, a pin without data: "[6] Near Wolves", "- 2/8 Prowler slain" (the log's titles name it)
        self.lua.execute('''WorldMapFrame={}; PIN={GetParent=function() return WorldMapFrame end}
          LINES[1].t="[6] Near Wolves"; LINES[2].t="- 2/8 Prowler slain"''')
        self.assertTrue(self.qt.CzechTooltip(self.lua.globals().TIP))
        self.assertEqual(str(self.lua.globals().LINES[1].t), "[6] Blízcí vlci")
        self.assertEqual(str(self.lua.globals().LINES[2].t), "- 2/8 Zabít Prowler")

    def test_one_quest_tracker_the_others_hidden(self):
        self.lua.execute('''SETS={}; EvertallyGuide.Set=function(k,v) SETS[k]=v end; InCombatLockdown=function() return false end
          TOGGLES=0; Questie={db={profile={trackerEnabled=true}}}
          QuestieLoader={ImportModule=function(_, name) return {Toggle=function() TOGGLES=TOGGLES+1; Questie.db.profile.trackerEnabled=not Questie.db.profile.trackerEnabled end} end}''')
        self.assertIsNone(self.qt.Choice(), "nothing changes before the setup asked")
        self.assertEqual(list(self.qt.Choices().values()), ["evertally", "blizzard", "questie"])
        self.assertTrue(self.a.SetQuestTrackerChoice("blizzard"))
        g = self.lua.globals()
        self.assertEqual(g.SETS["qol.hideQuestTracker"], False, "Blizzard's shows")
        self.assertEqual(g.TOGGLES, 1, "Questie's goes")
        self.assertFalse(g.Questie.db.profile.trackerEnabled)
        self.assertFalse(self.qt.Enabled())
        self.assertEqual(self.qt.Mode(), "guide", "no Quests tab")
        self.assertFalse(self.a.ShowQuestTracker())
        flat = [str(i.key) for grp in self.a.EvertallyMenuGroups().values() for i in grp["items"].values()]
        self.assertNotIn("menuQuests", flat)
        self.assertTrue(self.a.SetQuestTrackerChoice("questie"))
        self.assertEqual(g.SETS["qol.hideQuestTracker"], True, "Blizzard's hidden")
        self.assertTrue(g.Questie.db.profile.trackerEnabled)
        self.assertTrue(self.a.SetQuestTrackerChoice("evertally"))
        self.assertFalse(g.Questie.db.profile.trackerEnabled)
        self.assertEqual(g.SETS["qol.hideQuestTracker"], True)
        self.assertEqual(self.qt.Mode(), "quests")
        self.assertFalse(self.a.SetQuestTrackerChoice("nonsense"))

    def test_tracking_a_quest_elsewhere_sets_the_arrow(self):
        self.assertTrue(self.qt.ArrowToQuest(1))
        target = self.lua.globals().TARGET
        self.assertEqual((target[1], target[2], target[3]), (1, 10, 0))
        self.assertFalse(self.qt.ArrowToQuest(999), "not in the log")

    def test_a_click_opens_the_map_and_waits_out_a_fight(self):
        self.lua.execute("MAPS={}; EvertallyGuide.Compat.OpenWorldMap=function(m) MAPS[#MAPS+1]=m or 0; return true end; FIGHT=true; InCombatLockdown=function() return FIGHT end")
        frame, rows, h = self.layout()
        wolves = next(r for r in rows if r.quest and str(r.quest.title) == "Near Wolves")
        wolves.scripts.OnClick(wolves, "LeftButton")
        self.assertEqual(len(self.lua.globals().MAPS), 0, "not in a fight")
        self.lua.execute("FIGHT=false")
        self.a.Dispatch("PLAYER_REGEN_ENABLED")
        self.assertEqual(list(self.lua.globals().MAPS.values()), [1], "the fight over: the map opens, on the quest's")
        self.a.Dispatch("PLAYER_REGEN_ENABLED")
        self.assertEqual(len(self.lua.globals().MAPS), 1, "once")
        wolves.scripts.OnClick(wolves, "LeftButton")
        self.assertEqual(list(self.lua.globals().MAPS.values()), [1, 1], "out of a fight the click opens it at once")

    def test_the_tab_is_remembered_and_the_menu_opens_the_window_on_it(self):
        self.assertEqual(self.qt.Mode(), "quests", "Quests is the first tab and the default")
        self.qt.SetMode("guide")
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


class QuestTrackerBeforeLoadTests(unittest.TestCase):
    def test_a_layout_before_the_saved_settings_load_does_not_fail(self):
        lua, a = runtime()
        lua.execute(MOCK_UI_LUA)
        lua.execute(FAKE)
        a.db = None
        qt = a.QuestTracker
        parent = lua.eval("CreateFrame")("Frame", None, None)
        frame = qt.Attach(parent)
        frame.Show(frame)
        self.assertGreater(qt.Layout(320, 600), 0)
        self.assertEqual(qt.Mode(), "quests")
