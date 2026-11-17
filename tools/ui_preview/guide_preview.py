"""Offline preview of the Evertally Guide window and its settings on layout_mock (no game). Usage:
    NODE_PATH=<node_modules with playwright> [CS=1] [OPTIONS=guide] [OUT=path] python tools/ui_preview/guide_preview.py Evertally_Guide,Evertally_Guide_SkinAPI,Evertally_Guide_Options,Evertally_Guide_Guides,Evertally_Guide_Guides_Horde,Evertally_Guide_Guides_Orc --skin
A layout picture, not the game: fonts and the game's own textures are stand-ins."""
import re, sys, subprocess
from pathlib import Path
ROOT = Path(r"D:\addon"); AD = ROOT / "addon"
sys.path.insert(0, str(ROOT/"tools/ui_preview"))
import preview as PV
import inspect as _in
_src=_in.getsource(PV.render)
_src=re.sub(r'"[^"]*polestar[^"]*" in path', '"addons" in path', _src)
_src=_src.replace("background:linear-gradient(135deg,#5b6b45,#8a7a4a 45%%,#4a5b3a)","background:#3a3f2a")
assert '"addons" in path' in _src, "patch failed"
exec(_src, PV.__dict__)
from lupa.lua51 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True, encoding="utf-8")
import os as _os0
lua.execute("SCREEN_W, SCREEN_H = 900, %d" % (900 if _os0.environ.get("SETUP") else 700))  # (the setup at full size: no fit to the screen)
lua.execute((ROOT/"tools/ui_preview/layout_mock.lua").read_text(encoding="utf8"))
lua.execute(r'''
STUB = setmetatable({}, {__call=function() return nil end, __index=function(t,k) return t end})
local function ret(k)
  if k:match("^GetNum") or k:match("Count$") then return 0 end
  if k:match("^Is") or k:match("^Has") or k:match("^Can") or k:match("^Should") then return false end
  return nil
end
local OBJ={}
local function obj(name)
  if OBJ[name] then return OBJ[name] end
  local o=setmetatable({}, {__call=function() return ret(name) end, __index=function(t,f) if type(f)~="string" then return nil end local v=obj(f); rawset(t,f,v); return v end})
  OBJ[name]=o; return o
end
setmetatable(_G, {__index=function(_, k)
  if type(k)~="string" then return nil end
  if k=="Enum" then local e=setmetatable({}, {__index=function(t,f) local v=setmetatable({}, {__index=function() return 0 end}); rawset(t,f,v); return v end}); rawset(_G,k,e); return e end
  if k:match("DB$") or k:match("DB_") then return nil end
  if k:match("^NUM_") or k:match("^MAX_") then return 0 end
  if k:match("^[%u_%d]+$") then return k end
  if k:match("^%u") or k:match("^C_") then local o=obj(k); rawset(_G,k,o); return o end
end})
PENDING={}
CreateFont=function(name) local f=CreateFrame("Frame"); if name then _G[name]=f end; f.CopyFontObject=function() end; return f end
GetLocale=function() return "enUS" end
GetServerTime=function() return 1794236400 end
time=os.time; date=os.date; bit={band=function(a,b) local r,m=0,1 while a>0 and b>0 do if a%2==1 and b%2==1 then r=r+m end a,b,m=math.floor(a/2),math.floor(b/2),m*2 end return r end}
GetBuildInfo=function() return "1.60.1","70862","",16001 end
UnitName=function() return "Hero" end
UnitLevel=function() return 5 end
UnitClass=function() return "Warrior","WARRIOR",1 end
UnitRace=function() return "Orc","Orc",2 end
UnitFactionGroup=function() return "Horde","Horde" end
UnitGUID=function() return "Player-1-1" end
GetRealmName=function() return "Realm" end
InCombatLockdown=function() return false end
IsInInstance=function() return false end
IsLoggedIn=function() return true end
hooksecurefunc=function() end
strsplit=function(d,s,n) local t={} local pat="(.-)"..d:gsub("%p","%%%0") for p in (s..d):gmatch(pat) do t[#t+1]=p end return unpack(t) end
strjoin=function(d,...) return table.concat({...},d) end
wipe=function(t) for k in pairs(t) do t[k]=nil end return t end
tinsert=table.insert; tremove=table.remove; format=string.format; strfind=string.find; strlower=string.lower; strupper=string.upper; strsub=string.sub; strlen=string.len; strtrim=function(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
strmatch=string.match; gsub=string.gsub; strrep=string.rep; strbyte=string.byte; strchar=string.char; sort=table.sort; tContains=function(t,v) for _,x in ipairs(t) do if x==v then return true end end end
max=math.max; min=math.min; floor=math.floor; ceil=math.ceil; abs=math.abs; random=math.random; sqrt=math.sqrt
debugprofilestop=function() return 0 end
geterrorhandler=function() return function(e) print("LUAERR", e) end end
seterrorhandler=function() end
securecall=function(f,...) if type(f)=="string" then f=_G[f] end return f(...) end
securecallfunction=securecall
issecure=function() return true end
issecretvalue=function() return false end
tostringall=function(...) local t={...} for i=1,select("#",...) do t[i]=tostring(t[i]) end return unpack(t,1,select("#",...)) end
getn=table.getn; tIndexOf=function(t,v) for i,x in ipairs(t) do if x==v then return i end end end
CopyTable=function(t) local r={} for k,v in pairs(t) do r[k]=type(v)=="table" and CopyTable(v) or v end return r end
Mixin=function(o,...) for i=1,select("#",...) do for k,v in pairs((select(i,...))) do o[k]=v end end return o end
CreateFromMixins=function(...) return Mixin({},...) end

C_Timer={After=function(_, fn) PENDING=PENDING or {}; PENDING[#PENDING+1]=fn end, NewTicker=function() return {Cancel=function() end} end, NewTimer=function(_,fn) PENDING=PENDING or {}; PENDING[#PENDING+1]=fn; return {Cancel=function() end} end}
function RUN_PENDING() for i=1,5 do local p=PENDING or {}; PENDING={}; for _,f in ipairs(p) do pcall(f) end end end
''')
lua.execute(r"""
EVENTS={}
-- (an animation group of the preview: every call is a no-op that returns it again)
ANIMSTUB=setmetatable({}, {__index=function(t,k) return function() return t end end})
local mt=getmetatable(CreateFrame("Frame")); local old=mt.__index
mt.__index=function(t,k)
  if k=="CreateAnimationGroup" then return function() return ANIMSTUB end end
  if k=="RegisterEvent" then return function(self,e) EVENTS[e]=EVENTS[e] or {}; table.insert(EVENTS[e], self); return true end end
  if k=="RegisterUnitEvent" then return function(self,e) EVENTS[e]=EVENTS[e] or {}; table.insert(EVENTS[e], self); return true end end
  if k=="IsEventRegistered" then return function(self,e) for _,f in ipairs(EVENTS[e] or {}) do if f==self then return true end end return false end end
  if k=="GetLineHeight" then return function(self) return (self._fontSize or 12)*1.2 end end
  if k=="GetUnboundedStringWidth" then return function(self) return self:GetStringWidth() end end
  if k=="GetNumLines" then return function(self) local h=self:GetStringHeight(); return math.max(1, math.floor(h/((self._fontSize or 12)*1.25)+0.5)) end end
  if k=="IsTruncated" then return function() return false end end
  if k=="GetRight" then return function(self) local l=self:GetLeft(); return l and l+self:GetWidth() end end
  if k=="GetBottom" then return function(self) local tp=self:GetTop(); return tp and tp-self:GetHeight() end end
  if k=="GetCenter" then return function(self) local l,tp=self:GetLeft(),self:GetTop(); if l then return l+self:GetWidth()/2, tp-self:GetHeight()/2 end end end
  if k=="GetTextColor" then return function(self) local c=self._color or {1,1,1,1}; return c[1],c[2],c[3],c[4] end end
  if k=="GetFontObject" then return function() return nil end end
  if k=="GetObjectType" then return function(self) return self._kind end end
  if k=="IsObjectType" then return function(self,t) return self._kind==t end end
  if k=="GetNumPoints" then return function(self) return #self._points end end
  if k=="GetPoint" then return function(self,i) local p=self._points[i or 1]; if p then return p.point, p.rel, p.relPoint, p.x, p.y end end end
  if k=="GetRegions" then return function(self) return unpack(self._regions or {}) end end
  if k=="GetChildren" then return function(self) return unpack(self._children or {}) end end
  if k=="GetFrameStrata" then return function() return "MEDIUM" end end
  if k=="GetValue" then return function(self) return self._value or 0 end end
  if k=="SetValue" then return function(self,v) self._value=v; local h=self._scripts.OnValueChanged; if h then pcall(h,self,v) end end end
  if k=="SetMinMaxValues" then return function(self,a,b) self._min,self._max=a,b end end
  if k=="GetMinMaxValues" then return function(self) return self._min or 0, self._max or 1 end end
  if k=="GetChecked" then return function(self) return self._checked end end
  if k=="SetChecked" then return function(self,v) self._checked=v end end
  if k=="GetTexCoord" then return function() return 0,0,0,1,1,0,1,1 end end
  return old(t,k)
end
FRAMES={}
local _cf=CreateFrame
CreateFrame=function(...) local f=_cf(...); FRAMES[#FRAMES+1]=f; return f end
NOWT=100
GetTime=function() return NOWT end
function TICK(n, dt) for i=1,(n or 30) do NOWT=NOWT+(dt or 0.05); for _,f in ipairs(FRAMES) do local h=f._scripts and f._scripts.OnUpdate; if h and f:IsVisible() then local ok,err=pcall(h,f,dt or 0.05); if not ok then print("TICKERR",err) end end end end end
function FIRE(e, ...) for _,f in ipairs(EVENTS[e] or {}) do local h=f:GetScript("OnEvent"); if h then local ok,err=pcall(h,f,e,...); if not ok then print("EVENT ERR",e,err) end end end end
""")
def files(toc):
    out=[]
    for line in toc.read_text(encoding="utf8").splitlines():
        line=line.strip()
        if not line or line.startswith("#"): continue
        p=toc.parent/line.replace("\\","/")
        if p.suffix==".xml":
            for m in re.finditer(r'<Script file="([^"]+)"', p.read_text(encoding="utf8")):
                out.append(p.parent/m.group(1).replace("\\","/"))
        else: out.append(p)
    return out
loader = lua.execute("return function(src, name) local f, e = loadstring(src, name); if not f then error(e) end; return f end")
def load(addon, ns):
    for f in files(AD/addon/f"{addon}.toc"):
        try: loader(f.read_text(encoding="utf8"), "@"+addon+"/"+f.name)(addon, ns)
        except Exception as e: print("FAIL", addon, f.name, str(e)[:300])
NS = {}
import sys as _s0
_list = _s0.argv[1].split(",") if len(_s0.argv)>1 else ["Evertally_Guide"]
meta = {}
for a in _list:
    m={}
    for line in (AD/a/f"{a}.toc").read_text(encoding="utf8").splitlines():
        mm=re.match(r"##\s*([^:]+):\s*(.*)", line)
        if mm: m[mm.group(1).strip()]=mm.group(2).strip()
    meta[a]=m
G0=lua.globals()
G0.ADDON_LIST = lua.table_from(_list)
G0.ADDON_META = lua.table_from({k: lua.table_from(v) for k,v in meta.items()})
lua.execute(r"""
C_AddOns={GetNumAddOns=function() return #ADDON_LIST end,
 GetAddOnInfo=function(i) local n=type(i)=="number" and ADDON_LIST[i] or i; return n, ADDON_META[n] and ADDON_META[n].Title, "", true, nil, "INSECURE", false end,
 GetAddOnMetadata=function(n,f) return ADDON_META[n] and ADDON_META[n][f] end,
 IsAddOnLoaded=function(n) return ADDON_META[n]~=nil, ADDON_META[n]~=nil end,
 GetAddOnEnableState=function() return 2 end, LoadAddOn=function(n) return ADDON_META[n]~=nil end, IsAddOnLoadOnDemand=function() return false end,
 DoesAddOnExist=function(n) return ADDON_META[n]~=nil end, GetAddOnName=function(i) return ADDON_LIST[i] end}
""")
import sys as _s
addons = _s.argv[1].split(",") if len(_s.argv)>1 else ["Evertally_Guide"]
import os as _os
for a in addons:
    NS[a]=lua.eval("{}")
    load(a, NS[a])
    if a=="Evertally_Guide" and _os.environ.get("CS"):
        lua.globals().EvertallyGuide.EvertallyLanguage="csCZ"
        lua.globals().EvertallyGuide.GuideTexts.UseLanguage("csCZ")
        load("Evertally_Guide_csCZ", lua.eval("{}"))
lua.execute("EvertallyGuideDB = EvertallyGuideDB or nil")
if "--skin" in sys.argv:
    loader((AD/"Evertally/GuideSkin.lua").read_text(encoding="utf8"), "@Evertally/GuideSkin.lua")("Evertally", lua.eval("{}"))


for a in addons: lua.globals().FIRE("ADDON_LOADED", a)
lua.globals().FIRE("PLAYER_LOGIN")
lua.globals().FIRE("PLAYER_ENTERING_WORLD", True, False)
lua.execute("RUN_PENDING()")
G = lua.globals()
print("GF frame:", G.EvertallyGuideGuideFrame)

E = G.EvertallyGuide.Engine
Gd = G.EvertallyGuide.Guides
Gd.SetPackShown("guides", True)
for a in addons[1:]: G.FIRE("ADDON_LOADED", a)
lua.execute("RUN_PENDING()")
Gd.ScanInstalled()
try:
    r = E.SetGuide("forever/horde/03-silverpine-forest")
    print("SetGuide ->", r)
except Exception as e: print("SetGuide ERR", e)
lua.execute("RUN_PENDING()")
GF = G.EvertallyGuide.UI.GuideFrame
F = G.EvertallyGuideGuideFrame
try:
    F.Show(F); GF.Render()
except Exception as e: print("Render ERR", e)
lua.execute("RUN_PENDING(); TICK(60); RUN_PENDING(); PREVIEW_SETTLE()")
import os
if os.environ.get("QUESTS"):
    # TEST FIXTURE: Evertally over the guide and a quest log of invented states (the Quests tab of the window)
    lua.execute(r"""
      QLOG={{h="Silverpine Forest"},
        {id=421,t="Prove Your Worth",l=12,objs={{text="Moonrage Whelp slain: 4/6",n=4,r=6}}},
        {id=422,t="Arugal's Folly",l=14,objs={{text="Remedy of Arugal: 1/1",n=1,r=1,f=true}},done=true},
        {id=425,t="Ivar the Foul",l=14,objs={{text="Ivar's Head: 0/1",n=0,r=1}}},
        {h="Tirisfal Glades"},
        {id=356,t="Rear Guard Patrol",l=8,objs={{text="Bleeding Horror slain: 7/8",n=7,r=8},{text="Wandering Spirit slain: 8/8",n=8,r=8,f=true}}},
        {h="Dungeons"},
        {id=1098,t="Deathstalkers in Shadowfang",l=25,g=5,objs={{text="Deathstalker Adamant found: 0/1",n=0,r=1}}}}
      C_QuestLog={GetNumQuestLogEntries=function() return #QLOG end,
        GetInfo=function(i) local q=QLOG[i]; if q.h then return {isHeader=true,title=q.h} end
          return {questID=q.id,title=q.t,level=q.l,suggestedGroup=q.g or 0,isComplete=q.done and 1 or nil} end,
        GetQuestObjectives=function(id) for _,q in ipairs(QLOG) do if q.id==id then local o={}; for k,v in ipairs(q.objs) do o[k]={text=v.text,finished=v.f or false,numFulfilled=v.n,numRequired=v.r} end; return o end end end,
        IsComplete=function(id) for _,q in ipairs(QLOG) do if q.id==id then return q.done end end end,
        GetTimeAllowed=function(id) if id==425 then return 900, 312 end end}
      GetRealZoneText=function() return "Silverpine Forest" end
    """)
    G.EvertallyGuide.Compat.IsQuestReadyForTurnIn = lua.eval("function(id) return id==422 end")
    NS["Evertally"] = lua.eval("{}")
    load("Evertally", NS["Evertally"])
    A = G.Evertally
    if not A.db:
        A.db = lua.eval("{settings={}}")
    A.db.settings.language = "cs" if os.environ.get("CS") else "en"
    A.QuestTracker.SetMode("guide" if os.environ.get("QUESTS") == "guide" else "quests")
    lua.execute("RUN_PENDING(); TICK(10); RUN_PENDING(); PREVIEW_SETTLE()")
F.ClearAllPoints(F); F.SetPoint(F, "TOPLEFT", G.UIParent, "TOPLEFT", 20, -20)
lua.execute("PREVIEW_SETTLE()")
if os.environ.get("SETUP"):
    # One setup: Evertally's pages in the guide's Install window (SetupPages.lua); SETUP=<page key>, e.g. et-website
    if "Evertally" not in NS:
        NS["Evertally"] = lua.eval("{}")
        load("Evertally", NS["Evertally"])
    A = G.Evertally
    if not A.db:
        A.db = lua.eval("{settings={}}")
    A.db.settings.language = "cs" if os.environ.get("CS") else "en"
    print("hosted:", A.setupHosted is not None)
    WEL = G.EvertallyGuide.UI.Welcome
    try:
        A.OpenOnboarding(None)
        WEL.Show(os.environ["SETUP"])
    except Exception as e: print("SETUP ERR", e)
    lua.execute("RUN_PENDING(); TICK(30); RUN_PENDING(); PREVIEW_SETTLE()")
    WF = G.EvertallyGuideWelcome
    # (laid out at full size in the top left corner: the picture is the window, not the screen's fit)
    # (the harness loses the window's width somewhere in its skinning; the page itself is 600 wide: UI/Welcome.lua WIDTH)
    WF.SetWidth(WF, 600); WF.SetScale(WF, 1)
    G.EvertallyGuide.UI.WelcomeKit.refresh(); WF.SetScale(WF, 1); WF.SetWidth(WF, 600)
    WF.ClearAllPoints(WF); WF.SetPoint(WF, "TOPLEFT", G.UIParent, "TOPLEFT", 20, -20)
    lua.execute("PREVIEW_SETTLE()")
    print("page:", WEL.Page(), "size", WF.GetWidth(WF), WF.GetHeight(WF))
    lua.execute('''for _, pg in ipairs(Evertally.setupPages.pages) do local P = EvertallyGuideWelcome and nil end''')
    lua.execute('''local W = EvertallyGuide.UI.Welcome; local F = EvertallyGuideWelcome
      for key, P in pairs(F.pages) do
        if key:find("^et%-") or key == "questing" then print("PAGEH", key, P:GetHeight(), P.Hero:GetHeight(), P.Body:GetHeight()) end
      end''')
    wn = PV.to_py(lua.eval("PREVIEW_EXPORT")(WF))
    wout = Path("D:/addon/output/guide-preview/setup").with_name("setup-" + os.environ["SETUP"])
    wpage = wout.with_suffix(".html"); wpage.write_text(PV.render(wn, 640, int(WF.GetHeight(WF)) + 40), encoding="utf8")
    subprocess.run(["node", str(ROOT/"tools/ui_preview/capture.cjs"), str(wpage), str(wout.with_suffix(".png")), "640", str(int(WF.GetHeight(WF)) + 40)], check=True)
    for n in wn:
        if n.get("text"): print("SETUPTXT", repr(n["text"])[:70])
    sys.exit(0)
nodes = PV.to_py(lua.eval("PREVIEW_EXPORT")(F))
print("nodes", len(nodes), "size", F.GetWidth(F), F.GetHeight(F))
import os; out = Path(os.environ.get("OUT", r"D:\addon\output\guide-preview\tracker"))
out.parent.mkdir(parents=True, exist_ok=True)
page = out.with_suffix(".html"); page.write_text(PV.render(nodes, 420, 640), encoding="utf8")
subprocess.run(["node", str(ROOT/"tools/ui_preview/capture.cjs"), str(page), str(out.with_suffix(".png")), "420", "640"], check=True)
for t in [n for n in nodes if n.get("text")][:60]: print(repr(t.get("text"))[:80])
if os.environ.get("OPTIONS"):
    UI = G.EvertallyGuide.UI
    try:
        UI.ShowOptions(os.environ["OPTIONS"])
    except Exception as e: print("OPT ERR", e)
    lua.execute("RUN_PENDING(); TICK(40); RUN_PENDING(); PREVIEW_SETTLE()")
    of = G.EvertallyGuideOptions
    print("options frame", of)
    if of:
        of.ClearAllPoints(of); of.SetPoint(of, "TOPLEFT", G.UIParent, "TOPLEFT", 10, -10); lua.execute("PREVIEW_SETTLE()")
        on = PV.to_py(lua.eval("PREVIEW_EXPORT")(of))
        pg = out.with_name("options.html"); pg.write_text(PV.render(on, 1000, 720), encoding="utf8")
        subprocess.run(["node", str(ROOT/"tools/ui_preview/capture.cjs"), str(pg), str(pg.with_suffix(".png")), "1000", "720"], check=True)
import json
for n in nodes:
    if n["kind"]=="Texture" and n["w"]*n["h"]>3000:
        print("BIG", round(n["l"]),round(n["t"]),round(n["w"]),round(n["h"]), n.get("path"), n.get("rgba"), n.get("tint"), n.get("gradient") and "grad", n.get("alpha"))
for n in nodes:
    if n["kind"]=="FontString" and n.get("text"):
        print("TXT", round(n["l"]),round(n["t"]),round(n["w"]),round(n["h"]), n.get("color"), n.get("alpha"), repr(n["text"])[:50])
