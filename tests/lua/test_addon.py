"""Lua 5.1 replay checks. No running WoW or user addon data are accessed."""
from pathlib import Path
import json
import sys
import unittest

VENDOR = Path(r"C:\Users\domin\.codex\visualizations\2026\11\08\01a1bd6e-06a5-7b90-a316-c224aeeafc7c\questmaster-cs\vendor")
if VENDOR.exists():
    sys.path.insert(0, str(VENDOR))
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "Evertally"


def runtime(record_globals=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
    NOW=1794236400; CLOCK=100; INSIDE=false; INSTANCE=36; INCOMBAT=false
    GetServerTime=function() return NOW end
    GetTime=function() return CLOCK end
    GetBuildInfo=function() return "1.60.1", "70862", "", 16001 end
    GetCurrentRegion=function() return 3 end
    GetRealmName=function() return "Fixture Realm" end
    UnitGUID=function(unit) if unit=="player" then return "Player-TEST-own" end end
    UnitFullName=function() return "Fixture Hero", "Fixture Realm" end
    UnitName=function() return "Fixture Hero" end
    UnitClass=function() return "Shaman", "SHAMAN", 7 end
    UnitRace=function() return "Tauren", "Tauren", 6 end
    UnitLevel=function() return 20 end
    UnitExists=function() return false end
    GetNumGroupMembers=function() return 0 end
    IsInRaid=function() return false end
    IsInGroup=function() return false end
    IsInGuild=function() return false end
    IsInInstance=function() return INSIDE,"party" end
    GetInstanceInfo=function() return "The Deadmines","party",1,"Normal",5,0,false,INSTANCE end
    InCombatLockdown=function() return INCOMBAT end
    SECRET=setmetatable({}, {__tostring=function() error("Secret was stringified") end})
    issecretvalue=function(v) return rawequal(v,SECRET) end
    LOOT_ITEM_SELF="You receive loot: %s."
    LOOT_ITEM_SELF_MULTIPLE="You receive loot: %sx%d."
    LOOT_ITEM_CREATED_SELF="You create: %s."
    SlashCmdList={}
    ''')
    # Writes to global names made by addon code are recorded: a write to a Blizzard-owned global taints it.
    lua.execute("""WRITES={}
    ENVPROXY=setmetatable({},{__index=_G,__newindex=function(t,k,v) WRITES[#WRITES+1]=tostring(k) rawset(_G,k,v) end})""")
    ns = lua.table()
    export_source = (ROOT / "addon" / "Evertally_Export" / "Export.lua").read_text(encoding="utf-8")
    lua.execute(export_source)
    for name in ["Locale.lua", "Codec.lua", "Core.lua", "Identity.lua", "Rulesets.lua", "Runs.lua", "Collectors.lua", "People.lua", "Sync.lua", "Social.lua", "Live.lua", "Community.lua", "UI.lua", "SocialUI.lua"]:
        source = (ADDON / name).read_text(encoding="utf-8")
        fn = lua.eval("loadstring")(source, name)
        if isinstance(fn, tuple):
            raise AssertionError(f"Failed compiling {name}: {fn}")
        if record_globals:
            lua.eval("setfenv")(fn, lua.eval("ENVPROXY"))
        fn("Evertally", ns)
    ns.Initialize()
    return lua, ns


MOCK_UI_LUA = '''
        UIParent={}; UISpecialFrames={}; MOCKBUTTONS={}; MOCKNUMERICICON=false
        GetItemIcon=function() return 132540 end
        function object(parent)
            local t={parent=parent,shown=true,text="",scripts={},w=100,h=100}
            local methods={
                SetScript=function(self,k,v) self.scripts[k]=v end,
                SetText=function(self,v) self.text=v end,
                GetText=function(self) return self.text end,
                SetShown=function(self,v) self.shown=v and true or false end,
                IsShown=function(self) return self.shown end,
                Show=function(self) self.shown=true end,
                Hide=function(self) self.shown=false end,
                GetParent=function(self) return self.parent end,
                GetStringHeight=function(self) return #self.text end,
                GetStringWidth=function(self) return #self.text*6 end,
                SetSize=function(self,w,h) self.w,self.h=w,h end,
                SetWidth=function(self,w) self.w=w end,
                SetHeight=function(self,h) self.h=h end,
                GetWidth=function(self) return self.w end,
                GetHeight=function(self) return self.h end,
                GetVerticalScroll=function(self) return 0 end,
                CreateFontString=function(self) return object(self) end,
                CreateTexture=function(self) return object(self) end,
                SetTexture=function(self,v) self.texture=v;if v==132540 then MOCKNUMERICICON=true end;return true end,
                SetFont=function(self,path) self.font=path; return true end,
                GetFont=function(self) return self.font end,
            }
            return setmetatable(t,{__index=function(self,k) return methods[k] or (k:match("^%u") and function() end or nil) end})
        end
        function CreateFrame(kind,name,parent) local t=object(parent);if name then _G[name]=t end;if kind=="Button" then MOCKBUTTONS[#MOCKBUTTONS+1]=t end;return t end
        '''


class ReplayTests(unittest.TestCase):
    def setUp(self):
        self.lua,self.a=runtime()

    # ---- own route and guild identity (People.lua) ----
    def walk(self, x, y, map_id=1429, seconds=4):
        g = self.lua.globals(); g.MAPID = map_id; g.MX = x; g.MY = y; g.NOW = g.NOW + seconds
        self.a.SampleTrack()

    def mock_map(self):
        self.lua.execute("MAPID=1429;MX=0.5;MY=0.5;C_Map={GetBestMapForUnit=function() return MAPID end,GetPlayerMapPosition=function() return {GetXY=function() return MX,MY end} end}")

    def exported(self, kind):
        events = self.lua.globals().EvertallyExportDB.events
        return [events[i] for i in range(1, len(events) + 1) if events[i].kind == kind]

    def export_scopes(self):
        scopes = self.lua.globals().EvertallyExportDB.scopes
        return [scopes[i] for i in range(1, len(scopes) + 1)]

    def route_on(self):
        self.mock_map(); self.a.SetWeb(True); self.a.SetScope("own_track", True)

    def test_route_is_off_by_default_and_needs_web_and_its_own_scope(self):
        self.mock_map()
        for step in range(5): self.walk(0.5 + step * 0.02, 0.5)
        self.a.FlushTrack(); self.assertEqual(len(self.exported("track.path")), 0)
        self.a.SetWeb(True)  # web on, but own_track is still off
        self.assertNotIn("own_track", self.export_scopes())
        for step in range(5): self.walk(0.5 + step * 0.02, 0.5)
        self.a.FlushTrack(); self.assertEqual(len(self.exported("track.path")), 0)
        self.a.SetScope("own_track", True); self.assertIn("own_track", self.export_scopes())

    def test_route_records_moves_not_standing_still_and_stays_out_of_local_history(self):
        self.route_on(); start = int(self.lua.globals().NOW)
        self.walk(0.5, 0.5); self.walk(0.5, 0.5); self.walk(0.5004, 0.5)  # standing still: one point only
        self.walk(0.5123, 0.5); self.walk(0.5256, 0.5)
        self.a.FlushTrack()
        events = self.exported("track.path"); self.assertEqual(len(events), 1)
        p = events[0].payload; self.assertEqual(p.mapId, 1429); self.assertEqual(p.mapSystem, "ui_map")
        self.assertEqual(int(p.startedAt), start + 4)
        self.assertEqual(len(p.points), 3)
        self.assertEqual([p.points[i][2] for i in (1, 2, 3)], [0.5, 0.512, 0.526])  # rounded to three decimals
        self.assertEqual([int(p.points[i][1]) for i in (1, 2, 3)], [0, 12, 16])
        self.assertEqual(events[0].character.name, "Fixture Hero")
        self.assertEqual(len(self.a.db.events), 0)
        self.assertNotIn("track", self.a.Encode(self.a.MakeSummary()))

    def test_route_is_cut_at_a_map_change_and_at_100_points(self):
        self.route_on()
        self.walk(0.1, 0.1); self.walk(0.2, 0.2); self.walk(0.3, 0.3, map_id=1430)
        self.assertEqual(len(self.exported("track.path")), 1)
        self.assertEqual(self.exported("track.path")[0].payload.mapId, 1429)
        for i in range(110): self.walk(0.1 + (i % 2) * 0.3, 0.2 + i * 0.003, map_id=1430)
        self.a.FlushTrack()
        sizes = [len(e.payload.points) for e in self.exported("track.path")]
        self.assertTrue(all(n <= 100 for n in sizes)); self.assertEqual(sizes[1], 100)

    def test_route_without_position_closes_the_stretch_and_a_loading_gap_splits_it(self):
        self.route_on()
        self.walk(0.1, 0.1); self.walk(0.2, 0.2)
        self.lua.execute("C_Map.GetBestMapForUnit=function() return nil end"); self.a.SampleTrack()  # instance
        self.assertEqual(len(self.exported("track.path")), 1)
        self.lua.execute("C_Map.GetBestMapForUnit=function() return MAPID end")
        self.walk(0.3, 0.3); self.walk(0.4, 0.4, seconds=200); self.walk(0.5, 0.5)
        self.a.FlushTrack(); self.assertEqual(len(self.exported("track.path")), 3)

    def test_route_without_character_scope_is_pseudonymous(self):
        self.route_on(); self.a.SetScope("own_character", False)
        self.walk(0.1, 0.1); self.walk(0.2, 0.2); self.a.FlushTrack()
        e = self.exported("track.path")[0]
        self.assertIsNone(e.character.name); self.assertIsNone(e.character.realm)
        self.assertNotEqual(e.character.id, "Player-TEST-own")

    def test_route_outbox_keeps_the_newest_500_routes(self):
        self.route_on()
        self.lua.execute('for i=1,500 do table.insert(EvertallyExportDB.events,{kind="track.path",eventId="old"..i,observedAt=NOW,payload={}}) end')
        self.walk(0.1, 0.1); self.walk(0.2, 0.2); self.a.FlushTrack()
        routes = self.exported("track.path"); self.assertEqual(len(routes), 500)
        self.assertEqual(routes[0].eventId, "old2"); self.assertEqual(routes[499].payload.mapId, 1429)

    def test_changing_policy_discards_a_half_walked_route(self):
        self.route_on(); self.walk(0.1, 0.1); self.walk(0.2, 0.2)
        self.a.SetScope("world_facts", False)  # new consent version: nothing walked before it may be exported
        self.a.FlushTrack(); self.assertEqual(len(self.exported("track.path")), 0)

    def mock_guild(self, rank=0, member=True):
        self.lua.execute("IN_GUILD=%s;RANK=%d;ROSTER_ASKED=0" % ("true" if member else "false", rank))
        self.lua.execute("""
        IsInGuild=function() return IN_GUILD end
        GetGuildInfo=function() if IN_GUILD then return "Dawn","Rank "..RANK,RANK end end
        GetNumGuildMembers=function() return 2 end
        GetGuildRosterInfo=function(i) if i==1 then return "Hero-Fixture Realm","Guild Master",0,30,"Shaman","Zone","n","o",true,0,"SHAMAN" end
            return "Bran","Member",3,22,"Mage","Zone","n","o",false,0,"MAGE" end
        C_GuildInfo={GuildRoster=function() ROSTER_ASKED=ROSTER_ASKED+1 end}""")

    def test_guild_is_off_by_default_and_needs_character_scope(self):
        self.mock_guild(); self.a.SetWeb(True)
        self.a.GuildSnapshot(); self.assertEqual(len(self.exported("guild.snapshot")), 0)
        self.a.SetScope("guild_share", True)
        self.assertTrue(self.a.db.settings.scopes.own_character)  # the guild needs the name to recognise the member
        self.a.SetScope("own_character", False)
        self.assertFalse(self.a.db.settings.scopes.guild_share)

    def test_guild_master_sends_identity_then_roster_once(self):
        self.mock_guild(rank=0); self.a.SetWeb(True); self.a.SetScope("guild_share", True)
        self.a.GuildSnapshot()
        first = self.exported("guild.snapshot"); self.assertEqual(len(first), 1)
        self.assertEqual((first[0].payload.guildName, first[0].payload.rankIndex), ("Dawn", 0))
        self.assertIsNone(first[0].payload.roster); self.assertEqual(self.lua.globals().ROSTER_ASKED, 1)
        self.a.Dispatch("GUILD_ROSTER_UPDATE")
        both = self.exported("guild.snapshot"); self.assertEqual(len(both), 2)
        roster = both[1].payload.roster; self.assertEqual(len(roster), 2)
        self.assertEqual((roster[1].name, roster[1].rankIndex, roster[1].level, roster[1].classId), ("Hero-Fixture Realm", 0, 30, 7))
        self.assertEqual(roster[2].classId, 8)
        self.a.GuildSnapshot(); self.a.Dispatch("GUILD_ROSTER_UPDATE")
        self.assertEqual(len(self.exported("guild.snapshot")), 2)  # unchanged: nothing is sent again
        self.assertEqual(len(self.a.db.events), 0)

    def test_ordinary_member_never_sends_a_roster(self):
        self.mock_guild(rank=3); self.a.SetWeb(True); self.a.SetScope("guild_share", True)
        self.a.GuildSnapshot(); self.a.Dispatch("GUILD_ROSTER_UPDATE")
        events = self.exported("guild.snapshot"); self.assertEqual(len(events), 1)
        self.assertIsNone(events[0].payload.roster); self.assertEqual(self.lua.globals().ROSTER_ASKED, 0)

    def test_leaving_the_guild_is_reported_once(self):
        self.mock_guild(rank=3); self.a.SetWeb(True); self.a.SetScope("guild_share", True)
        self.a.GuildSnapshot(); self.lua.execute("IN_GUILD=false")
        self.a.GuildSnapshot(); self.a.GuildSnapshot()
        events = self.exported("guild.snapshot"); self.assertEqual(len(events), 2)
        self.assertTrue(events[1].payload.left); self.assertIsNone(events[1].payload.guildName)

    def test_new_consent_version_resends_the_guild_identity(self):
        self.mock_guild(rank=3); self.a.SetWeb(True); self.a.SetScope("guild_share", True)
        self.a.GuildSnapshot(); self.a.SetScope("world_facts", False)  # new epoch, fresh outbox
        self.assertEqual(len(self.exported("guild.snapshot")), 0)
        self.a.GuildSnapshot(); self.assertEqual(len(self.exported("guild.snapshot")), 1)

    def test_addon_writes_no_blizzard_global_so_chat_commands_stay_untainted(self):
        # Regression: `SlashCmdList = SlashCmdList or {}` tainted the global and blocked /invite and /script.
        lua,a=runtime(record_globals=True)
        writes=lua.eval("WRITES")
        written={writes[i] for i in range(1,len(writes)+1)}
        # Only names that are ours and did not exist before: saved variables, the slash command words, and what Bindings.xml needs
        # (a header, two labels and the functions the two key bindings call). Anything else would be a write to a Blizzard-owned global.
        own={"EvertallyDB","EvertallyPeersDB","SLASH_EVERTALLY1","SLASH_EVERTALLY2","BINDING_HEADER_EVERTALLY","BINDING_NAME_EVERTALLY_PING","BINDING_NAME_EVERTALLY_STOPNAV","Evertally_Ping","Evertally_StopNav"}
        self.assertEqual(written-own,set())
        self.assertTrue(lua.eval("type(SlashCmdList.EVERTALLY)=='function'"))

    def community(self):
        now=int(self.lua.globals().NOW)
        return {"schemaVersion":1,"kind":"evertally-community","scope":"world_facts","generatedAt":now,
                "expiresAt":now+3600,"game":{"product":"forever"},"provenance":{"source":"community",
                "countingUnit":"observations","truncated":False,"observationCount":3,"entityCount":1},
                "entities":[{"kind":"npc","id":706,"name":"Trollí jeskyně","count":3,"lastSeen":now,"mapId":1426}]}

    def test_community_import_survives_reload_without_becoming_own_or_peer_export(self):
        self.a.SetWeb(True)
        before=self.a.Encode(self.a.ExportStore())
        self.assertEqual(self.a.ImportCommunity(json.dumps(self.community(),ensure_ascii=False)),(True,1))
        self.a.Initialize()
        snapshot,stale=self.a.GetCommunity()
        self.assertEqual(snapshot.entities[1].name,"Trollí jeskyně")
        self.assertFalse(stale)
        self.assertEqual(self.a.Encode(self.a.ExportStore()),before)
        self.assertEqual(len(self.a.db.events),0)
        self.assertNotIn("Trollí",self.a.Encode(self.a.MakeSummary()))

    def test_community_tampering_keeps_previous_snapshot(self):
        sample=self.community()
        self.a.ImportCommunity(json.dumps(sample))
        variants=[]
        for field,value in [("schemaVersion",2),("scope","own_character"),("generatedAt",sample["generatedAt"]+301),("character",{"name":"private"})]:
            bad=json.loads(json.dumps(sample));bad[field]=value;variants.append(bad)
        bad=json.loads(json.dumps(sample));bad["entities"][0]["name"]="|Hplayer:bad|h";variants.append(bad)
        bad=json.loads(json.dumps(sample));bad["provenance"]["observationCount"]=0;variants.append(bad)
        for bad in variants:
            self.assertIsNone(self.a.ImportCommunity(json.dumps(bad))[0])
            self.assertEqual(self.a.GetCommunity()[0].entities[1].id,706)

    def test_community_expiry_and_limits(self):
        sample=self.community();self.a.ImportCommunity(json.dumps(sample))
        self.lua.globals().NOW=sample["expiresAt"]+1
        self.assertTrue(self.a.GetCommunity()[1])
        self.assertEqual(self.a.ImportCommunity(json.dumps(sample))[1],"communityExpiredImport")
        self.assertIsNone(self.a.ImportCommunity(" "*49153)[0])
        sample=self.community();sample["entities"]*=151
        self.assertIsNone(self.a.ImportCommunity(json.dumps(sample))[0])
        self.a.ClearCommunity();self.assertIsNone(self.a.GetCommunity())

    def test_community_search_czech_and_strict_coordinates(self):
        sample=self.community();self.a.ImportCommunity(json.dumps(sample,ensure_ascii=False))
        self.assertEqual(len(self.a.CommunityEntries("npc","TROLLÍ")),1)
        self.assertEqual(len(self.a.CommunityEntries("quest","")),0)
        sample["entities"][0]["x"]=.5
        self.assertIsNone(self.a.ImportCommunity(json.dumps(sample))[0])

    def pump(self,times):
        for _ in range(times):
            self.lua.globals().CLOCK+=0.3
            self.a.PumpSync()

    def test_default_off_and_enabling_is_not_retroactive(self):
        self.a.Record("quest.turned_in",self.lua.table_from({"questId":182}))
        self.assertFalse(self.lua.globals().EvertallyExportDB.enabled)
        self.assertEqual(len(self.lua.globals().EvertallyExportDB.events),0)
        self.a.SetWeb(True)
        self.assertEqual(len(self.lua.globals().EvertallyExportDB.events),0)
        self.a.Record("quest.accepted",self.lua.table_from({"questId":183}))
        self.assertEqual(len(self.lua.globals().EvertallyExportDB.events),1)

    def test_optout_erases_outbox_and_advances_epoch(self):
        self.a.SetWeb(True)
        self.a.Record("quest.turned_in",self.lua.table_from({"questId":182}))
        epoch=self.lua.globals().EvertallyExportDB.consentEpoch
        self.a.SetWeb(False)
        store=self.lua.globals().EvertallyExportDB
        self.assertFalse(store.enabled)
        self.assertGreater(store.consentEpoch,epoch)
        self.assertEqual(len(store.events),0)

    def test_reload_keeps_existing_enabled_outbox(self):
        self.a.SetWeb(True)
        self.a.Record("quest.turned_in",self.lua.table_from({"questId":182}))
        self.a.Initialize()
        self.assertEqual(len(self.lua.globals().EvertallyExportDB.events),1)

    def test_ingame_summary_does_not_disclose_other_alts(self):
        self.a.db.runs[1]=self.lua.table_from({"status":"completed","runId":"other","durationMs":1000,
            "character":self.lua.table_from({"id":"Player-OTHER","name":"Private Alt"})})
        self.assertEqual(self.a.MakeSummary().completedRuns,0)
        self.assertEqual(len(self.a.MakeSummary().runs),0)

    def test_share_transport_queues_and_never_sends_in_combat(self):
        self.lua.execute('SENT={}; IsInGroup=function() return true end; C_ChatInfo={SendAddonMessage=function(prefix,data,channel) SENT[#SENT+1]={prefix,data,channel} end}')
        self.a.SetIngame(True)
        self.lua.globals().INCOMBAT=True
        self.a.PumpSync()
        self.assertEqual(len(self.lua.globals().SENT),0)
        self.lua.globals().INCOMBAT=False
        self.pump(50)
        sent=self.lua.globals().SENT
        self.assertGreater(len(sent),0)
        for i in range(1,len(sent)+1):
            self.assertLessEqual(len(sent[i][2].encode()),255)

    def test_send_rate_stays_under_client_throttle(self):
        self.lua.execute('SENT={}; IsInGroup=function() return true end; C_ChatInfo={SendAddonMessage=function(prefix,data,channel) SENT[#SENT+1]={GetTime(),data} end}')
        self.a.db.settings.ingame=True
        for i in range(30): self.a.ShareNow()
        self.pump(200)
        times=[self.lua.globals().SENT[i][1] for i in range(1,len(self.lua.globals().SENT)+1)]
        self.assertGreater(len(times),10)
        for start in times:
            window=[t for t in times if start<=t<start+10]
            self.assertLessEqual(len(window),8+10)

    def test_throttled_chunk_is_retried_not_lost(self):
        self.lua.execute('''SENT={}; CALLS=0; IsInGroup=function() return true end
        C_ChatInfo={SendAddonMessage=function(prefix,data,channel)
            CALLS=CALLS+1; if CALLS==1 then return 3 end; SENT[#SENT+1]=data; return 0 end}''')
        self.a.db.settings.ingame=True
        self.assertTrue(self.a.ShareNow())
        self.pump(200)
        sent=[self.lua.globals().SENT[i] for i in range(1,len(self.lua.globals().SENT)+1)]
        total=int(sent[0].split("|")[3])
        self.assertEqual(sorted(int(m.split("|")[2]) for m in sent),list(range(1,total+1)))
        self.assertEqual(self.a.errors.sync_throttled,1)

    def test_soft_limit_pauses_sampling_but_keeps_results(self):
        self.a.MAX_EVENTS=3;self.a.HARD_EVENTS=5
        for i in range(3): self.a.Record("quest.turned_in",self.lua.table_from({"questId":100+i}))
        self.assertIsNone(self.a.Record("npc.observed",self.lua.table_from({"npcId":1})))
        self.assertIsNotNone(self.a.Record("run.finished",self.lua.table_from({"runId":"r1","durationMs":1000})))
        self.assertIsNotNone(self.a.Record("quest.turned_in",self.lua.table_from({"questId":200})))
        self.assertIsNone(self.a.Record("run.finished",self.lua.table_from({"runId":"r2","durationMs":1000})))
        self.assertTrue(self.a.storageFull)

    def test_unchanged_profession_window_is_recorded_once(self):
        self.lua.execute('''C_TradeSkillUI={
            GetBaseProfessionInfo=function() return {professionID=171,professionName="Alchemy",skillLevel=75,maxSkillLevel=150} end,
            GetAllRecipeIDs=function() return {999002} end,
            GetRecipeInfo=function(id) return {name="Recipe",learned=true} end,
            GetRecipeCooldown=function() return 3600 end}''')
        for _ in range(3):
            self.lua.globals().CLOCK+=11
            self.a.Dispatch("TRADE_SKILL_LIST_UPDATE")
        kinds=[self.a.db.events[i].kind for i in range(1,len(self.a.db.events)+1)]
        self.assertEqual(kinds.count("profession.snapshot"),1)
        self.assertEqual(kinds.count("cooldown.snapshot"),1)

    def test_disabling_recipient_drops_queued_data(self):
        self.lua.execute('SENT={}; IsInGroup=function() return true end; C_ChatInfo={SendAddonMessage=function(prefix,data,channel) SENT[#SENT+1]={prefix,data,channel} end}')
        self.a.SetIngame(True)
        self.a.db.settings.group=False
        self.pump(100)
        self.assertEqual(len(self.lua.globals().SENT),0)

    def test_finish_automatically_shares_own_result(self):
        self.lua.execute('SENT={}; IsInGroup=function() return true end; C_ChatInfo={SendAddonMessage=function(prefix,data,channel) SENT[#SENT+1]={prefix,data,channel} end}')
        self.a.SetIngame(True)
        self.pump(100)
        self.lua.globals().SENT=self.lua.table()
        self.lua.globals().INSIDE=True
        self.a.RefreshInstance()
        self.a.FinishRun("manual","last_boss")
        self.pump(100)
        self.assertGreater(len(self.lua.globals().SENT),0)

    def mock_ui(self):
        self.lua.execute(MOCK_UI_LUA)

    def test_ui_builds_and_opens_each_tab_with_mock_native_frames(self):
        self.mock_ui()
        self.a.Record("quest.accepted",self.lua.table_from({"questId":182,"title":"Mock quest"}))
        self.a.Record("loot.received",self.lua.table_from({"itemId":2136,"name":"Conjured Water","quantity":2}))
        self.a.OpenUI()
        self.assertTrue(self.lua.globals().MOCKNUMERICICON)
        frame=self.lua.globals().EvertallyFrame
        self.assertTrue(frame.IsShown(frame))
        opened=self.lua.eval('''function()
            local views={}
            for _,b in ipairs(MOCKBUTTONS) do
                if b.viewKey then b.scripts.OnClick(b); views[#views+1]=b.viewKey end
            end
            return table.concat(views,",")
        end''')()
        self.assertEqual(opened,"overview,history,professions,places,facts,rankings,peers,community,social,settings")
        # Toggles in Settings change real settings, and language switching re-renders.
        self.lua.execute('''for _,b in ipairs(MOCKBUTTONS) do if b.localeKey=="web" and b.Update then b.scripts.OnClick(b) end end''')
        self.assertTrue(self.a.db.settings.web)
        self.lua.execute('''for _,b in ipairs(MOCKBUTTONS) do if b.lang=="cs" then b.scripts.OnClick(b) end end''')
        self.assertEqual(self.a.db.settings.language,"cs")

    def test_identity_uses_race_and_class_textures_without_glue_globals(self):
        self.lua.execute('''
        CLASS_ICON_TCOORDS=nil;RAID_CLASS_COLORS=nil;C_Texture=nil;GetClassInfo=nil
        T={SetTexture=function(self,v) self.texture=v;return true end,SetTexCoord=function(self,...) self.coords={...} end}
        Evertally.SetClassIcon(T,7)
        ''')
        texture=self.lua.globals().T
        self.assertTrue(texture.texture.endswith("UI-CharacterCreate-Classes"))
        self.assertEqual(texture.coords[1],0.25)
        self.a.SetRaceIcon(texture,6)
        self.assertTrue(texture.texture.endswith("UI-CharacterCreate-Races"))
        self.assertEqual([texture.coords[i] for i in range(1,5)],[0,0.25,0.25,0.5])
        self.a.SetRaceIcon(texture,999)
        self.assertTrue(texture.texture.endswith("INV_Misc_QuestionMark"))
        self.a.db.settings.language="cs"
        self.assertEqual(self.a.ClassName(7),"Šaman")
        self.assertEqual(self.a.RaceName(6),"Tauren")

    def test_profession_summary_uses_latest_own_snapshot_and_keeps_unknown_values(self):
        self.lua.execute('''
        local A=Evertally
        A.Record("profession.snapshot",{professionId=171,name="Alchemy",skill=50,maxSkill=75,recipes={{recipeId=1,name="Old recipe",learned=true}}})
        NOW=NOW+20
        A.Record("profession.snapshot",{professionId=171,name="Alchemy",skill=75,maxSkill=150,recipes={{recipeId=2,name="Čirá voda",learned=true},{recipeId=3,name="Unknown recipe",learned=false}}})
        A.Record("craft.result",{recipeId=2,quantity=3})
        A.Record("craft.result",{recipeId=2})
        A.Record("cooldown.snapshot",{recipeId=2,readyAt=NOW+600})
        A.Record("profession.snapshot",{professionId=171,name="Alchemy",recipes={}},"api_snapshot",{id="Player-ALT",name="Alt"})
        A.peerDB.peers.fake={facts={{kind="profession.snapshot",payload={professionId=999,name="Peer profession"}}}}
        ''')
        before=len(self.a.db.events)
        summaries=self.a.ProfessionSummaries()
        self.assertEqual(len(summaries),2)
        main=next(e for _,e in summaries.items() if e.character.name=="Fixture Hero")
        alt=next(e for _,e in summaries.items() if e.character.name=="Alt")
        self.assertEqual(main.payload.skill,75)
        self.assertEqual(len(main.recipes),1)
        self.assertEqual(main.recipes[1].recipeId,2)
        self.assertEqual(main.recipes[1].crafts,2)
        self.assertEqual(main.recipes[1].cooldown.readyAt,int(self.lua.globals().NOW)+600)
        self.assertIsNone(alt.payload.skill)
        self.assertEqual(len(self.a.db.events),before)
        self.mock_ui()
        self.a.OpenUI()
        self.a.UIShowProfessionDetail(main)
        self.assertTrue(self.lua.globals().EvertallyDetailFrame.shown)
        self.assertEqual(len(self.a.db.events),before)

    def test_run_details_preserve_unknowns_and_reject_negative_boss_splits(self):
        run=self.a.Decode(json.dumps({"name":"Test dungeon","startedAt":100,"endedAt":400,"durationMs":300000,
            "bosses":[{"name":"Boss A","killedAt":150},{"name":"Boss B","killedAt":120},{"name":"Boss C","killedAt":300}]}))
        rows=self.a.RunDetailRows(run)
        self.assertEqual(rows[2].sub,"5:00")
        self.assertEqual(rows[6].sub,"unknown")
        self.assertEqual(rows[7].sub,"unknown")
        self.assertIn("unknown",rows[11].sub)
        self.assertNotIn("Since previous boss",rows[12].sub)
        self.mock_ui()
        self.a.OpenUI()
        self.a.UIShowRunDetail(run,False)
        self.assertTrue(self.lua.globals().EvertallyDetailFrame.shown)

    def test_area_summary_has_no_player_coordinates_and_map_action_only_opens_zone(self):
        self.lua.execute('''
        Evertally.db.events={
          {kind="zone.visited",observedAt=100,payload={mapId=1426,mapName="Dun Morogh",mapSystem="ui_map",x=0.4,y=0.6}},
          {kind="zone.visited",observedAt=300,payload={mapId=1426,mapName="Dun Morogh",mapSystem="ui_map"}},
          {kind="zone.visited",observedAt=200,payload={mapId=1429,mapName="Elwynn Forest",mapSystem="ui_map"}},
          {kind="npc.observed",observedAt=400,payload={mapId=1426,npcId=706,x=0.5,y=0.7}}
        }
        C_Map={OpenWorldMap=function(id) OPENEDMAP=id end,SetUserWaypoint=function() error("Must never place a player tracking pin") end}
        ''')
        places=self.a.PlaceSummaries()
        self.assertEqual(len(places),2)
        self.assertEqual(places[1].mapId,1426)
        self.assertEqual(places[1].count,2)
        self.assertEqual(places[1].lastSeen,300)
        self.assertIsNone(places[1].x)
        self.assertIsNone(places[1].y)
        self.assertTrue(self.a.OpenRecordedMap(places[1]))
        self.assertEqual(self.lua.globals().OPENEDMAP,1426)
        self.lua.globals().INCOMBAT=True
        self.assertFalse(self.a.OpenRecordedMap(places[2]))

    def test_minimap_button_toggles_window(self):
        self.lua.execute('''
        UIParent={}; UISpecialFrames={}
        function object(parent)
            local t={parent=parent,shown=true,text="",scripts={},w=140,h=140}
            local methods={SetScript=function(self,k,v) self.scripts[k]=v end, SetShown=function(self,v) self.shown=v and true or false end,
                IsShown=function(self) return self.shown end, Show=function(self) self.shown=true end, Hide=function(self) self.shown=false end,
                GetWidth=function(self) return self.w end, GetHeight=function(self) return self.h end, GetStringWidth=function() return 10 end,
                GetVerticalScroll=function() return 0 end, CreateFontString=function(self) return object(self) end,
                CreateTexture=function(self) return object(self) end, SetTexture=function() return true end, GetFont=function() return nil end}
            return setmetatable(t,{__index=function(self,k) return methods[k] or (k:match("^%u") and function() end or nil) end})
        end
        function CreateFrame(kind,name,parent) local t=object(parent);if name then _G[name]=t end;return t end
        Minimap=object(nil)
        ''')
        self.a.CreateMinimapButton()
        button=self.lua.globals().EvertallyMinimapButton
        self.assertIsNotNone(button)
        self.lua.execute("EvertallyMinimapButton.scripts.OnClick(EvertallyMinimapButton)")
        self.assertTrue(self.lua.globals().EvertallyFrame.IsShown(self.lua.globals().EvertallyFrame))
        self.lua.execute("EvertallyMinimapButton.scripts.OnClick(EvertallyMinimapButton)")
        self.assertFalse(self.lua.globals().EvertallyFrame.IsShown(self.lua.globals().EvertallyFrame))

    def test_dead_candidate_npc_is_not_used_as_encounter_id(self):
        self.lua.globals().INSIDE=True
        self.a.RefreshInstance()
        self.lua.execute('''UnitIsDeadOrGhost=function(unit) return true end
        UnitGUID=function(unit) if unit=="player" then return "Player-TEST-own" end;return "Creature-0-1-36-2-639-00000001" end''')
        self.a.Dispatch("PLAYER_TARGET_CHANGED")
        self.assertEqual(self.a.db.runs[1].completion,"last_boss")
        self.assertEqual(len(self.a.db.runs[1].bosses),0)

    def test_secret_quest_event_is_ignored(self):
        self.a.Dispatch("QUEST_ACCEPTED",self.lua.globals().SECRET,self.lua.globals().SECRET)
        self.assertEqual(len(self.a.db.events),0)

    def test_peer_origin_never_becomes_upload(self):
        self.a.SetWeb(True)
        peer=self.lua.table_from({"v":1,"producerId":"peer","generatedAt":1794236400,
            "runs":self.lua.table(),"facts":self.lua.table_from([self.lua.table_from({"kind":"quest.turned_in","observedAt":1794236400,"payload":self.lua.table_from({"questId":777})})])})
        self.assertTrue(self.a.ReceiveSummary("Friend-Realm",peer))
        self.assertEqual(self.a.peerDB.peers["Friend-Realm"].origin,"peer")
        self.assertEqual(len(self.a.db.events),0)
        self.assertEqual(len(self.lua.globals().EvertallyExportDB.events),0)

    def test_world_scope_without_character_drops_identity(self):
        self.a.db.settings.scopes.own_character=False
        self.a.SetWeb(True)
        self.a.Record("quest.turned_in",self.lua.table_from({"questId":182}))
        event=self.lua.globals().EvertallyExportDB.events[1]
        self.assertIsNone(event.character)

    def test_own_runs_without_character_are_pseudonymous(self):
        self.a.db.settings.scopes.own_character=False
        self.a.SetWeb(True)
        self.a.Record("run.finished",self.lua.table_from({"runId":"test","instanceId":36,"status":"manual","durationMs":1000}))
        event=self.lua.globals().EvertallyExportDB.events[1]
        self.assertIsNone(event.character.name)
        self.assertNotEqual(event.character.id,"Player-TEST-own")

    def test_boss_signals_deduplicate(self):
        self.lua.globals().INSIDE=True
        self.a.RefreshInstance()
        self.a.ObserveBoss(123,"Test Boss",1)
        self.a.ObserveBoss(123,"Test Boss",1)
        self.assertEqual(self.a.ActiveRun().bossCount,1)

    def test_last_boss_auto_completion_never_ranked(self):
        self.lua.globals().INSIDE=True
        self.a.RefreshInstance()
        self.lua.globals().CLOCK=200
        self.a.ObserveBoss(555,"Edwin VanCleef",1)
        self.assertIsNone(self.a.ActiveRun())
        run=self.a.db.runs[1]
        self.assertEqual(run.status,"completed")
        self.assertEqual(run.completion,"last_boss")
        self.assertFalse(run.rankEligible)
        self.assertEqual(run.bosses[1].encounterId,555) # Never substituted NPC 639.

    def test_reload_marks_continuity_interrupted(self):
        self.lua.globals().INSIDE=True
        self.a.RefreshInstance()
        self.lua.globals().CLOCK=180
        self.a.CheckpointRun()
        self.a.RestoreRun()
        run=self.a.db.runs[1]
        self.assertEqual(run.status,"interrupted")
        self.assertFalse(run.rankEligible)
        self.assertEqual(run.durationMs,80000)

    def test_secret_cannot_be_stringified_or_serialized(self):
        secret=self.lua.globals().SECRET
        self.assertIsNone(self.a.Text(secret))
        self.assertIsNone(self.a.Number(secret))
        event=self.a.Record("npc.observed",self.lua.table_from({"npcId":1,"name":secret,"level":secret}))
        self.assertIsNone(event.payload.name)
        self.assertIsNone(event.payload.level)

    def test_json_rejects_code_and_duplicate_keys(self):
        self.assertEqual(self.a.Decode('loadstring("return 1")()')[0],None)
        self.assertEqual(self.a.Decode('{"a":1,"a":2}')[0],None)
        self.assertEqual(self.a.Decode('{"__proto__":{}}')[0],None)
        sample='{"name":"Trollí jeskyně","items":[1,2],"ok":true}'
        parsed=self.a.Decode(sample)
        self.assertEqual(parsed.name,"Trollí jeskyně")

    def test_own_loot_only_from_localized_templates(self):
        self.a.Dispatch("CHAT_MSG_LOOT","Someone receives loot: |cffffffff|Hitem:111|h[Test]|h|r.")
        self.assertEqual(len(self.a.db.events),0)
        self.a.Dispatch("CHAT_MSG_LOOT","You receive loot: |cffffffff|Hitem:111|h[Test]|h|r.")
        self.assertEqual(len(self.a.db.events),1)
        self.assertEqual(self.a.db.events[1].payload.itemId,111)
        self.assertFalse(self.a.db.events[1].payload.sourceCertain)

    def test_export_fixture(self):
        self.a.SetWeb(True)
        self.a.db.producerId="fixture-installation"
        self.a.sessionId="fixture-session"
        self.a.db.sequence=0
        self.a.ResetExport()
        payloads=[
            ("quest.turned_in",{"questId":182,"title":"Syntetický testovací quest","xp":100,"money":0}),
            ("npc.observed",{"npcId":999001,"name":"Syntetický obchodník","mapId":1426,"x":0.5,"y":0.6,"positionMethod":"player_interaction"}),
            ("run.finished",{"runId":"fixture-run-1","instanceId":36,"name":"Syntetický dungeon","instanceType":"party","difficultyId":1,"startedAt":1794235000,"endedAt":1794236400,"durationMs":1400000,"status":"completed","completion":"last_boss","rankEligible":False,"groupSize":5,"minLevel":18,"maxLevel":22,"bossCount":1}),
            ("profession.snapshot",{"professionId":171,"name":"Syntetická alchymie","skill":75,"maxSkill":150,"recipes":self.lua.table_from([self.lua.table_from({"recipeId":999002,"name":"Syntetický recept","learned":True})])}),
        ]
        for kind,payload in payloads:
            self.a.Record(kind,self.lua.table_from(payload))
        export=self.lua.globals().EvertallyExportDB
        encoded=self.a.Encode(export)
        self.assertIsInstance(encoded,str)
        fixture_json=json.loads(encoded)
        self.assertEqual(len(fixture_json["events"]),4)
        dest=Path(__file__).parent/"fixtures"
        dest.mkdir(exist_ok=True)
        (dest/"export.json").write_text(json.dumps(fixture_json,ensure_ascii=False,indent=2),encoding="utf-8")
        # Render a WoW-like data-only SavedVariables table, with indexed array entries.
        def lua_data(value,level=0):
            if isinstance(value,dict):
                rows=[f'[{json.dumps(k,ensure_ascii=False)}] = {lua_data(v,level+1)},' for k,v in value.items()]
            elif isinstance(value,list):
                rows=[f'[{i}] = {lua_data(v,level+1)},' for i,v in enumerate(value,1)]
            elif isinstance(value,str): return json.dumps(value,ensure_ascii=False)
            elif value is True: return 'true'
            elif value is False: return 'false'
            elif value is None: return 'nil'
            else: return str(value)
            return '{\n'+'\n'.join('\t'*(level+1)+row for row in rows)+'\n'+'\t'*level+'}'
        (dest/"Evertally_Export.lua").write_text('-- Synthetic test data only; no real player data.\nEvertallyExportDB = '+lua_data(fixture_json)+'\n',encoding="utf-8")


class LocationPrivacyTests(unittest.TestCase):
    def test_visits_record_zones_only_and_world_exports_strip_historical_actor_coordinates(self):
        lua, a = runtime()
        lua.execute('''C_Map={GetBestMapForUnit=function() return 1426 end,GetMapInfo=function() return {name="Dun Morogh"} end}''')
        a.SetWeb(True)
        a.Dispatch("ZONE_CHANGED_NEW_AREA")
        event=a.db.events[len(a.db.events)]
        self.assertEqual(event.kind,"zone.visited")
        self.assertEqual(event.payload.mapId,1426)
        self.assertIsNone(event.payload.x)
        self.assertIsNone(event.payload.y)
        payload=lua.table_from({"npcId":706,"mapId":1426,"x":.4,"y":.7,"positionMethod":"player_interaction"})
        observation=a.Record("npc.observed",payload,"api_snapshot")
        self.assertIsNone(observation.payload.x)
        self.assertIsNone(observation.payload.y)
        store=lua.globals().EvertallyExportDB
        self.assertIsNone(store.events[len(store.events)].payload.x)

if __name__ == "__main__":
    unittest.main(verbosity=2)


class SocialTests(unittest.TestCase):
    """Two addon instances in two Lua states, joined by a recording whisper transport."""

    def setUp(self):
        self.lua_a, self.a = runtime()
        self.lua_b, self.b = runtime()
        for lua, name, guid in ((self.lua_a, "Fixture Hero", "Player-TEST-own"), (self.lua_b, "Other", "Player-TEST-other")):
            lua.execute("""
            SENT={}
            C_ChatInfo={RegisterAddonMessagePrefix=function() return true end,SendAddonMessage=function(prefix,text,channel,target) SENT[#SENT+1]={prefix=prefix,text=text,channel=channel,target=target} return 0 end}
            MAPID=1429;MX=0.4234;MY=0.6512
            C_Map={GetBestMapForUnit=function() return MAPID end,GetPlayerMapPosition=function() return {GetXY=function() return MX,MY end} end}
            """)
            lua.execute('UnitName=function() return "%s" end;UnitFullName=function() return "%s","Fixture Realm" end;UnitGUID=function(u) if u=="player" then return "%s" end end' % (name, name, guid))
        # B carries a few things and knows a recipe
        self.lua_b.execute("""
        NUM_BAG_SLOTS=1
        GetInventoryItemID=function(unit,slot) if slot==1 then return 987654 elseif slot==5 then return 23456 end end
        C_Container={GetContainerNumSlots=function(bag) return bag==0 and 4 or 0 end,
            GetContainerItemInfo=function(bag,slot) if slot==1 then return {itemID=2589,stackCount=20} elseif slot==2 then return {itemID=2589,stackCount=5} elseif slot==3 then return {itemID=1205,stackCount=1} end end}
        GetMoney=function() return 123456 end
        """)
        self.b.SetWeb(True)
        self.b.Record("profession.snapshot", self.lua_b.table_from({"professionId": 171, "name": "Alchemy", "skill": 225, "maxSkill": 300,
            "recipes": self.lua_b.table_from([self.lua_b.table_from({"recipeId": 2329, "name": "Lion Elixir", "learned": True}), self.lua_b.table_from({"recipeId": 3170, "name": "Weak Troll's Blood", "learned": True})])}), "api_snapshot")

    def deliver(self, source, target, sender, channel="WHISPER"):
        """Pump `source`'s outgoing queue and hand every message to `target` as if `sender` had whispered it."""
        moved = 0
        for _ in range(400):
            source[0].globals().CLOCK += 1.1
            source[1].PumpSync()
        sent = source[0].globals().SENT
        for i in range(1, len(sent) + 1):
            message = sent[i]
            target[1].ReceiveMessage(message.prefix, message.text, message.channel or channel, sender); moved += 1
        source[0].execute("SENT={}")
        return moved

    @property
    def A(self): return (self.lua_a, self.a)

    @property
    def B(self): return (self.lua_b, self.b)

    def ask(self, kinds="ipg"):
        ok, ident = self.a.RequestInspect("Other-Fixture Realm", kinds)
        self.assertTrue(ok)
        self.deliver(self.A, self.B, "Fixture Hero-Fixture Realm")
        return ident

    def test_inspect_waits_for_consent_and_sends_only_what_was_allowed(self):
        ident = self.ask("ipg")
        incoming = self.b.SocialRequests()[ident]
        self.assertEqual(incoming.kinds, "ipg")
        self.assertEqual(len(self.lua_b.globals().SENT), 0)  # nothing is sent before the player answers
        self.deliver(self.B, self.A, "Other-Fixture Realm")
        self.assertEqual(len(self.a.social.views), 0)
        ok, state = self.b.AnswerRequest(ident, "ip")  # gold is not allowed
        self.assertEqual((ok, state), (True, "allowed"))
        self.deliver(self.B, self.A, "Other-Fixture Realm")
        view = self.a.social.views[1]
        self.assertEqual([(e[1], e[2]) for e in [view.equipped[i] for i in (1, 2)]], [(1, 987654), (5, 23456)])
        bags = {view.bags[i][1]: view.bags[i][2] for i in range(1, len(view.bags) + 1)}
        self.assertEqual(bags, {2589: 25, 1205: 1})  # two stacks of the same item are added up
        self.assertIsNone(view.gold)
        prof = view.professions[1]
        self.assertEqual((prof.name, prof.skill, prof.max), ("Alchemy", 225, 300))
        self.assertEqual([prof.recipes[i] for i in (1, 2)], [2329, 3170])
        self.assertEqual(self.a.social.outgoing[ident].status, "done")
        self.assertEqual(self.b.social.shown[1].kinds, "ip")  # the other side keeps a record of what it showed

    def test_gold_is_sent_only_when_asked_and_allowed(self):
        ident = self.ask("g")
        self.b.AnswerRequest(ident, "g")
        self.deliver(self.B, self.A, "Other-Fixture Realm")
        view = self.a.social.views[1]
        self.assertEqual(view.gold, 123456)
        self.assertEqual(len(view.bags), 0)

    def test_denied_request_gets_a_denial_then_a_cooldown_and_nothing_leaks(self):
        ident = self.ask("ip")
        self.b.DenyRequest(ident, False)
        self.deliver(self.B, self.A, "Other-Fixture Realm")
        self.assertEqual(self.a.social.outgoing[ident].status, "denied")
        self.assertEqual(len(self.a.social.views), 0)
        ok, again = self.a.RequestInspect("Other-Fixture Realm", "ip")
        self.assertTrue(ok)
        self.deliver(self.A, self.B, "Fixture Hero-Fixture Realm")
        self.assertEqual(len(list(self.b.SocialRequests().items())), 0)  # asking again right away is ignored

    def test_blocked_sender_and_disabled_feature_are_ignored_silently(self):
        ident = self.ask("ip")
        self.b.DenyRequest(ident, True)
        self.assertTrue(self.b.db.settings.socialBlock["fixture hero"])
        self.lua_b.globals().NOW += 500; self.b.social.cooldown = self.lua_b.table()
        self.a.social.outgoing = self.lua_a.table()
        self.ask("ip")
        self.assertEqual(len(list(self.b.SocialRequests().items())), 0)
        self.b.SocialUnblock("Fixture Hero-Fixture Realm"); self.b.db.settings.social = False
        self.a.social.outgoing = self.lua_a.table()
        self.ask("ip")
        self.assertEqual(len(list(self.b.SocialRequests().items())), 0)

    def test_unsolicited_inspect_data_and_data_from_somebody_else_are_dropped(self):
        payload = "I1;E=1:987654;B=2589*20"
        self.a.ReceiveMessage("Evtly1", "S|D|abcdef|1|1|" + payload, "WHISPER", "Other-Fixture Realm")
        self.assertEqual(len(self.a.social.views), 0)  # nobody was asked
        ok, ident = self.a.RequestInspect("Other-Fixture Realm", "ip")
        self.lua_a.execute("SENT={}")
        self.a.ReceiveMessage("Evtly1", "S|A|%s|ip|1" % ident, "WHISPER", "Stranger-Fixture Realm")
        self.a.ReceiveMessage("Evtly1", "S|D|%s|1|1|%s" % (ident, payload), "WHISPER", "Stranger-Fixture Realm")
        self.assertEqual(len(self.a.social.views), 0)  # right id, wrong player
        self.a.ReceiveMessage("Evtly1", "S|D|%s|1|1|%s" % (ident, payload), "WHISPER", "Other-Fixture Realm")
        self.assertEqual(len(self.a.social.views), 1)

    def test_inspect_data_never_reaches_saved_variables_or_the_web_export(self):
        self.b.SetWeb(True); self.a.SetWeb(True)
        ident = self.ask("ip")
        self.b.AnswerRequest(ident, "ip")
        self.deliver(self.B, self.A, "Other-Fixture Realm")
        self.assertEqual(len(self.a.social.views), 1)
        for text in (self.a.Encode(self.lua_a.globals().EvertallyDB), self.a.Encode(self.lua_a.globals().EvertallyExportDB), self.a.Encode(self.lua_a.globals().EvertallyPeersDB)):
            self.assertNotIn("987654", text)
            self.assertNotIn("Alchemy", text)

    def test_malformed_messages_are_ignored(self):
        junk = ["S|Q||ip", "S|Q|zzzzzz|ip", "S|Q|abcdef|x", "S|D|abcdef|9|2|x", "S|D|abcdef|1|99|x", "S|M|abcdef|0|1|1|1|x", "S|M|abcdef|1429|5000|1|1|x", "S|M|abcdef|1429|1|1|99999|x", "S|", "S|Z|1|2|3"]
        for message in junk:
            self.b.ReceiveMessage("Evtly1", message, "WHISPER", "Fixture Hero-Fixture Realm")
        self.assertEqual(len(list(self.b.SocialRequests().items())), 0)
        self.assertEqual(len(self.b.social.meets), 0)

    def test_requests_are_limited_and_expire(self):
        for i, name in enumerate(["A", "B", "C", "D"]):
            self.b.ReceiveMessage("Evtly1", "S|Q|00000%d|ip" % i, "WHISPER", name + "-Fixture Realm")
        self.assertEqual(len(list(self.b.SocialRequests().items())), 3)
        self.lua_b.globals().NOW += 300
        self.b.SocialTick()
        self.assertEqual(len(list(self.b.SocialRequests().items())), 0)

    def test_windows_wait_for_the_end_of_combat_but_the_chat_line_does_not(self):
        seen = []
        self.b.SocialListen(self.lua_b.eval("function(kind) SEEN=(SEEN or '')..kind..';' end"))
        self.lua_b.execute("INCOMBAT=true")
        self.b.ReceiveMessage("Evtly1", "S|Q|abcdef|ip", "WHISPER", "Fixture Hero-Fixture Realm")
        self.assertIsNone(self.lua_b.globals().SEEN)
        self.lua_b.execute("INCOMBAT=false"); self.b.Dispatch("PLAYER_REGEN_ENABLED")
        self.assertEqual(self.lua_b.globals().SEEN, "request;")

    def proposal(self):
        return self.lua_a.table_from({"want": self.lua_a.table_from([self.lua_a.table_from([987654, 1])]),
                                     "offer": self.lua_a.table_from([self.lua_a.table_from([2589, 20])]), "gold": 5000, "note": "Platím |cffff0000hned|r; díky = ok"})

    def test_trade_proposal_round_trip_is_sanitised_and_only_a_message(self):
        ok, ident = self.a.SendProposal("Other-Fixture Realm", self.proposal())
        self.assertTrue(ok)
        self.deliver(self.A, self.B, "Fixture Hero-Fixture Realm")
        entry = self.b.social.proposals[1]
        self.assertEqual((entry.dir, entry.status, entry.gold), ("in", "open", 5000))
        self.assertEqual((entry.want[1][1], entry.want[1][2], entry.offer[1][1], entry.offer[1][2]), (987654, 1, 2589, 20))
        self.assertNotIn("|", entry.note); self.assertNotIn("=", entry.note); self.assertNotIn(";", entry.note)
        self.assertTrue(self.b.AnswerProposal(entry.id, True, "Dohodnuto"))
        self.deliver(self.B, self.A, "Other-Fixture Realm")
        self.assertEqual(self.a.social.proposals[1].status, "accepted")
        self.assertEqual(self.a.social.proposals[1].reply, "Dohodnuto")
        self.assertEqual(len(self.b.db.events), 1)  # only the recipe snapshot: no trade is recorded as an observation

    def test_proposals_are_limited_per_sender_and_empty_ones_are_dropped(self):
        self.a.SendProposal("Other-Fixture Realm", self.proposal()); self.a.SendProposal("Other-Fixture Realm", self.proposal())
        self.deliver(self.A, self.B, "Fixture Hero-Fixture Realm")
        self.assertEqual(len(self.b.social.proposals), 1)
        self.b.ReceiveMessage("Evtly1", "S|D|abcdef|1|1|T1;W=;O=;G=0;N=", "WHISPER", "Somebody-Fixture Realm")
        self.assertEqual(len(self.b.social.proposals), 1)

    def test_meet_goes_to_the_group_and_arrives_validated(self):
        ok = self.a.SendMeet("PARTY", None, "Sraz |cff00ff00u hostince|r", 15)
        self.assertTrue(ok)
        for _ in range(5):
            self.lua_a.globals().CLOCK += 1.1; self.a.PumpSync()
        message = self.lua_a.globals().SENT[1]
        self.assertEqual((message.channel, message.target), ("PARTY", None))
        self.b.ReceiveMessage("Evtly1", message.text, "PARTY", "Fixture Hero-Fixture Realm")
        meet = self.b.social.meets[1]
        self.assertEqual((meet.mapId, meet.x, meet.y, meet.minutes), (1429, 0.423, 0.651, 15))
        self.assertNotIn("|", meet.label)
        self.b.ReceiveMessage("Evtly1", message.text, "PARTY", "Fixture Hero-Fixture Realm")
        self.assertEqual(len(self.b.social.meets), 1)  # the same sender cannot flood
        self.assertEqual(tuple(self.a.SendMeet("SAY", None, "x", 0)), (False, "channel"))

    def test_meet_waypoint_uses_the_client_waypoint_when_there_is_one(self):
        self.lua_b.execute("""
        WAYPOINT=nil
        UiMapPoint={CreateFromCoordinates=function(map,x,y) return {map=map,x=x,y=y} end}
        C_Map.SetUserWaypoint=function(point) WAYPOINT=point end
        C_SuperTrack={SetSuperTrackedUserWaypoint=function(on) SUPER=on end}
        """)
        self.b.ReceiveMessage("Evtly1", "S|M|abcdef|1429|423|651|0|Hostinec", "GUILD", "Fixture Hero-Fixture Realm")
        self.assertTrue(self.b.SetMeetWaypoint(self.b.social.meets[1]))
        way = self.lua_b.globals().WAYPOINT
        self.assertEqual((way.map, way.x, way.y), (1429, 0.423, 0.651))
        self.assertTrue(self.lua_b.globals().SUPER)

    def test_send_meet_needs_a_position_and_a_target_for_whispers(self):
        self.lua_a.execute("C_Map.GetBestMapForUnit=function() return nil end")
        self.assertEqual(tuple(self.a.SendMeet("PARTY", None, "x", 0)), (False, "no_position"))
        self.lua_a.execute("C_Map.GetBestMapForUnit=function() return MAPID end")
        self.assertEqual(tuple(self.a.SendMeet("WHISPER", "", "x", 0)), (False, "no_target"))

    # ---- the windows (mock frames) ----
    def open_social(self):
        self.lua_a.execute(MOCK_UI_LUA)
        self.a.SetWeb(True)
        self.a.OpenUI()
        self.lua_a.execute("for _,b in ipairs(MOCKBUTTONS) do if b.viewKey=='social' then b.scripts.OnClick(b) end end")
        return self.a.social.page

    def test_social_page_builds_and_every_mode_renders(self):
        page = self.open_social()
        self.assertIsNotNone(page)
        self.assertIsNone(self.a.errors.social_page)
        for mode in ("proposals", "meets", "privacy", "ask"):
            page.tabs[mode].scripts.OnClick(page.tabs[mode])
            self.assertEqual(page.mode, mode)
        self.assertIsNone(self.a.errors.social_page)

    def test_a_request_opens_the_question_and_allowing_sends_the_answer(self):
        self.open_social()
        self.a.ReceiveMessage("Evtly1", "S|Q|abcdef|ipg", "WHISPER", "Other-Fixture Realm")
        popup = self.lua_a.globals().EvertallySocialPopup
        self.assertTrue(popup.IsShown(popup))
        self.assertIsNone(self.a.errors.social_popup)
        self.assertIn("Other", popup.title.text)
        # gold is asked for but starts unticked; the player can tick it
        popup.buttons[1].scripts.OnClick(popup.buttons[1])
        self.assertFalse(popup.IsShown(popup))
        self.lua_a.execute("SENT={}")
        for _ in range(30):
            self.lua_a.globals().CLOCK += 1.1; self.a.PumpSync()
        texts = [self.lua_a.globals().SENT[i].text for i in range(1, len(self.lua_a.globals().SENT) + 1)]
        self.assertTrue(any(t.startswith("S|A|abcdef|ip|") for t in texts), texts)  # inventory and professions, not gold
        self.assertFalse(any(t.startswith("S|A|abcdef|ipg") for t in texts))

    def test_denying_and_blocking_from_the_question(self):
        self.open_social()
        self.a.ReceiveMessage("Evtly1", "S|Q|abcdef|ip", "WHISPER", "Other-Fixture Realm")
        popup = self.lua_a.globals().EvertallySocialPopup
        popup.buttons[3].scripts.OnClick(popup.buttons[3])
        self.assertTrue(self.a.db.settings.socialBlock["other"])
        self.assertEqual(len(list(self.a.SocialRequests().items())), 0)

    def test_questions_queue_up_instead_of_stacking(self):
        self.open_social()
        self.a.ReceiveMessage("Evtly1", "S|Q|abcdef|ip", "WHISPER", "One-Fixture Realm")
        self.a.ReceiveMessage("Evtly1", "S|Q|abcde0|ip", "WHISPER", "Two-Fixture Realm")
        popup = self.lua_a.globals().EvertallySocialPopup
        self.assertIn("One", popup.title.text)
        popup.buttons[2].scripts.OnClick(popup.buttons[2])  # deny the first
        self.assertTrue(popup.IsShown(popup))
        self.assertIn("Two", popup.title.text)

    def test_received_data_opens_the_viewer_and_a_proposal_can_be_sent_from_it(self):
        self.open_social()
        ok, ident = self.a.RequestInspect("Other-Fixture Realm", "ip")
        self.a.ReceiveMessage("Evtly1", "S|A|%s|ip|1" % ident, "WHISPER", "Other-Fixture Realm")
        self.a.ReceiveMessage("Evtly1", "S|D|%s|1|1|I1;E=1:987654;B=2589*20;P=171:225:300:Alchemy:97" % ident, "WHISPER", "Other-Fixture Realm")
        viewer = self.lua_a.globals().EvertallyViewFrame
        self.assertTrue(viewer.IsShown(viewer))
        self.assertIsNone(self.a.errors.social_viewer)
        # mark the helmet as wanted and offer nothing, then send
        self.lua_a.execute("local v=EvertallyViewFrame; v.wanted[987654]=1")
        self.lua_a.execute("NUM_BAG_SLOTS=0;C_Container={GetContainerNumSlots=function() return 0 end}")
        self.a.SocialSendFromViewer()
        sent = [e for e in [self.a.social.proposals[i] for i in range(1, len(self.a.social.proposals) + 1)]]
        self.assertEqual(len(sent), 1)
        self.assertEqual((sent[0].dir, sent[0].peer, sent[0].want[1][1]), ("out", "Other-Fixture Realm", 987654))

    def test_waypoint_command_sets_a_map_waypoint_and_rejects_nonsense(self):
        self.lua_a.execute("""
        WAYPOINT=nil
        UiMapPoint={CreateFromCoordinates=function(map,x,y) return {map=map,x=x,y=y} end}
        C_Map.SetUserWaypoint=function(point) WAYPOINT=point end
        """)
        self.lua_a.execute('SlashCmdList.EVERTALLY("waypoint 1429 0.4234 0.6512 Hostinec")')
        way = self.lua_a.globals().WAYPOINT
        self.assertEqual((way.map, way.x, way.y), (1429, 0.4234, 0.6512))
        self.lua_a.execute("WAYPOINT=nil")
        self.lua_a.execute('SlashCmdList.EVERTALLY("waypoint 1429 42.34 65.12")')  # percent, as the game's own coordinates read
        self.assertAlmostEqual(self.lua_a.globals().WAYPOINT.x, 0.4234, places=6)
        self.lua_a.execute("WAYPOINT=nil")
        self.lua_a.execute('SlashCmdList.EVERTALLY("waypoint 0 0.5 0.5")')
        self.lua_a.execute('SlashCmdList.EVERTALLY("waypoint 1429 500 0.5")')
        self.assertIsNone(self.lua_a.globals().WAYPOINT)
