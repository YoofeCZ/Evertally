"""Draws the Evertally window pages WITHOUT the game: the add-on runs on tools/ui_preview/layout_mock.lua (a model of WoW frames with real
anchoring), every visible region is exported and drawn as HTML, and headless Chrome takes a picture.

    python tools/ui_preview/preview.py [--size 960x620] [--out DIR] [view ...]

What it shows is the LAYOUT: overlaps, text that spills out of its card, empty buttons, things that fall outside the window. Known icons are read
from existing local game exports; native surfaces and fonts are modelled. This is not a picture of the game's pixels.
"""
import argparse
import base64
import html
import json
import re
import subprocess
import sys
import time
import zlib
from pathlib import Path
from functools import lru_cache

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tests" / "lua"))
from test_addon import runtime  # noqa: E402
from test_navigation import FAKE_LIBS, MapTests  # noqa: E402
from test_dungeons import FAKE_JOURNAL  # noqa: E402
from test_openmap import OPENMAP  # noqa: E402
from test_forever_traits import FOREVER_TRAITS  # noqa: E402

CAPTURE = HERE / "capture.cjs"
ADDONS = Path(r"D:\World of Warcraft\_forever_\Interface\AddOns")
ICON_FILES = {}
VIEWS = ["overview", "journal", "history", "places", "facts", "professions", "database", "dungeons", "recipes", "talents", "world", "guides", "community", "social", "rankings", "webfacts", "settings"]

FIXTURE = r'''
UnitName=function() return "Mardyx" end
UnitFullName=function() return "Mardyx","Valdren" end
UnitClass=function() return "Paladin","PALADIN",2 end
UnitRace=function() return "Human","Human",1 end
UnitLevel=function() return 13 end
UnitXP=function() return 1435 end
UnitXPMax=function() return 11400 end
GetMoney=function() return 6298 end
GetRealmName=function() return "Valdren" end
date=os.date
RAID_CLASS_COLORS={PALADIN={r=.96,g=.55,b=.73},SHAMAN={r=0,g=.44,b=.87},MAGE={r=.25,g=.78,b=.92},WARRIOR={r=.78,g=.61,b=.43},PRIEST={r=1,g=1,b=1},HUNTER={r=.67,g=.83,b=.45}}
GetClassInfo=function(id) local f={"WARRIOR","PALADIN","HUNTER",nil,"PRIEST",nil,"SHAMAN","MAGE"}; return nil,f[id],id end
C_Map={GetMapInfo=function(id) return {name=({[1429]="Elwynn Forest",[1453]="Stormwind City",[1436]="Westfall",[1426]="Dun Morogh"})[id] or ("Zone "..id)} end,
  GetBestMapForUnit=function() return 1429 end,GetPlayerMapPosition=function() return {GetXY=function() return .42,.65 end} end}
GetItemInfo=function(id) return ({[2136]="Conjured Water",[2589]="Linen Cloth",[4540]="Tough Hunk of Bread",[6948]="Hearthstone"})[id] end
GetItemIcon=function() return "Interface\\Icons\\INV_Misc_Bag_08" end
UnitFactionGroup=function() return "Alliance" end
local A=Evertally
local day=86400
local base=NOW
local function at(daysAgo,hour) NOW=base-daysAgo*day-(24-hour)*3600 end
for d=5,0,-1 do
  for i=1,(6-d)*3 do
    at(d,8+i%12)
    A.Record("quest.accepted",{questId=100+d*10+i,title="Report to Gryan Stoutmantle "..i,mapId=1429,x=.4,y=.6})
    at(d,9+i%12)
    A.Record("quest.turned_in",{questId=100+d*10+i,title="Wolves Across the Border "..i,mapId=1429,xp=450,money=1200})
    A.Record("loot.received",{itemId=2136,name="Conjured Water",quantity=2})
    A.Record("loot.received",{itemId=2589,name="Linen Cloth",quantity=3})
  end
  at(d,10); A.Record("zone.visited",{mapId=1429,mapName="Elwynn Forest",mapSystem="ui_map"})
  at(d,11); A.Record("craft.result",{recipeId=2,quantity=1})
end
at(0,18); A.Record("character.level",{level=13})
at(0,19); A.Record("instance.entered",{name="The Deadmines",instanceId=36})
NOW=base
A.db.runs={{character={id="Player-TEST-own",name="Mardyx",classId=2,raceId=1,level=13},status="completed",completion="full_clear",name="The Deadmines",durationMs=1800000,startedAt=base-3600,bossCount=6},
           {character={id="Player-TEST-own",name="Mardyx",classId=2,raceId=1,level=13},status="interrupted",name="Wailing Caverns",durationMs=900000,startedAt=base-86400,bossCount=2}}
A.peerDB.peers.Bran={producerId="p1",receivedAt=NOW-600,completedRuns=7,character={id="Player-B",name="Bran",classId=8,raceId=1,level=33,realm="Valdren"},runs={{name="The Deadmines",status="completed",durationMs=1500000}}}
A.peerDB.peers.Mira={producerId="p2",receivedAt=NOW-4000,character={id="Player-M",name="Mira",classId=5,raceId=2,level=18,realm="Valdren"},runs={{name="The Deadmines",status="completed",durationMs=2100000}}}
A.db.settings.web=true; A.db.settings.ingame=true; A.db.settings.scopes.own_character=true
FRIENDS={{name="Thalia",level=42,connected=true,area="Stormwind City",guid="Player-1"},{name="Orgrim",level=33,connected=true,area="Elwynn Forest",guid="Player-2"},{name="Offline",level=10,connected=false}}
C_FriendList={GetNumFriends=function() return #FRIENDS end,GetFriendInfoByIndex=function(i) return FRIENDS[i] end}
GetPlayerInfoByGUID=function(g) if g=="Player-1" then return "Mage","MAGE" end return "Warrior","WARRIOR" end
IsInGuild=function() return true end
GetNumGuildMembers=function() return 3 end
GetGuildRosterInfo=function(i) local r={{"Korgan-Valdren","Member",3,60,"Warrior","Ironforge","","",true,0,"WARRIOR"},{"Lyra-Valdren","Officer",1,25,"Priest","Darnassus","","",true,0,"PRIEST"},{"Gone-Valdren","Member",3,12,"Mage","","","",false,0,"MAGE"}}; local x=r[i]; return x[1],x[2],x[3],x[4],x[5],x[6],x[7],x[8],x[9],x[10],x[11] end
'''


def to_py(value, depth=0):
    if depth > 6:
        return None
    if hasattr(value, "items") and not isinstance(value, (str, bytes)):
        try:
            items = list(value.items())
        except Exception:
            return None
        keys = [k for k, _ in items]
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(v, depth + 1) for _, v in sorted(items)]
        return {str(k): to_py(v, depth + 1) for k, v in items}
    return value


def color(c, alpha=1.0, tint=None):
    if not c:
        return "transparent"
    r, g, b = c[0], c[1], c[2]
    a = (c[3] if len(c) > 3 and c[3] is not None else 1) * alpha
    if tint:
        r, g, b = r * tint[0], g * tint[1], b * tint[2]
        a *= tint[3] if len(tint) > 3 else 1
    return f"rgba({round(r * 255)},{round(g * 255)},{round(b * 255)},{a:.3f})"


def rich(text):
    """WoW colour codes to HTML spans; || is a literal bar."""
    out, open_span = [], False
    pos = 0
    for m in re.finditer(r"\|c([0-9a-fA-F]{8})|\|r", text):
        out.append(html.escape(text[pos:m.start()].replace("||", "|")))
        if m.group(1):
            if open_span:
                out.append("</span>")
            out.append(f'<span style="color:#{m.group(1)[2:]}">'); open_span = True
        elif open_span:
            out.append("</span>"); open_span = False
        pos = m.end()
    out.append(html.escape(text[pos:].replace("||", "|")))
    if open_span:
        out.append("</span>")
    return "".join(out)


@lru_cache(maxsize=512)
def image_data(path):
    path = Path(path)
    if not path.is_file():
        return None
    suffix = path.suffix.lower()
    if suffix in {".png", ".jpg", ".jpeg", ".webp"}:
        kind = {".jpg": "jpeg", ".jpeg": "jpeg"}.get(suffix, suffix[1:])
        return f"data:image/{kind};base64," + base64.b64encode(path.read_bytes()).decode("ascii")
    if suffix in {".tga", ".blp"}:
        try:
            try:
                from PIL import Image
            except ImportError:
                sys.path.insert(0, str(ROOT / ".tools" / "python-data"))
                from PIL import Image
            from io import BytesIO
            out = BytesIO()
            with Image.open(path) as image:
                image.convert("RGBA").save(out, format="PNG")
            return "data:image/png;base64," + base64.b64encode(out.getvalue()).decode("ascii")
        except (ImportError, OSError, ValueError):
            return None
    return None


@lru_cache(maxsize=2)
def identity_assets(kind):
    """Match the production helper's existing atlas coordinates to its already-exported class/race image."""
    source = (ROOT / "addon/Evertally/Identity.lua").read_text(encoding="utf8")
    section = source.split("local " + kind + " = {", 1)[1].split("\n}", 1)[0]
    found = {}
    for line in section.splitlines():
        match = re.search(r"\[(\d+)\]=.*\{([\d.,]+)\}\},?$", line.strip())
        if match:
            coords = tuple(round(float(v), 3) for v in match[2].split(","))
            path = ROOT / "platform/public/media/identity" / kind / f"{match[1]}.png"
            if len(coords) == 4 and path.is_file():
                found[coords] = path
    return found


def local_asset(texture, item_id=None, coords=None):
    """Only existing local exports and addon artwork; no downloads and no client access."""
    value = str(texture).replace("/", "\\")
    if value.isdigit():
        return image_data(ROOT / "platform/public/media/identity/client-items" / f"{value}.jpg")
    key = value.lower()
    identity_kind = "classes" if key.endswith("ui-charactercreate-classes") else "races" if key.endswith("ui-charactercreate-races") else None
    if identity_kind and coords and len(coords) == 4:
        asset = identity_assets(identity_kind).get(tuple(round(v, 3) for v in coords))
        if asset:
            return image_data(asset)
    if key in ICON_FILES:
        found = image_data(ICON_FILES[key])
        if found:
            return found
    if item_id:
        found = image_data(ROOT / "platform/public/media/identity/items" / f"{int(item_id)}.jpg")
        if found:
            return found
    prefix = "interface\\addons\\"
    if key.startswith(prefix):
        relative = Path(*value[len(prefix):].split("\\"))
        for root in (ROOT / "addon", ADDONS):
            candidate = root / relative
            for path in (candidate, candidate.with_suffix(".tga"), candidate.with_suffix(".png"), candidate.with_suffix(".blp")):
                if found := image_data(path):
                    return found
    return None


def icon_style(path, tint=None, item_id=None, coords=None):
    name = str(path).replace("/", "\\").split("\\")[-1]
    low = name.lower()
    if low == "questbg":
        paper = color([.74,.63,.43,1], tint=tint)
        return f"background:{paper};box-shadow:inset 0 0 24px #62442133", ""
    if low == "ui-background-rock":
        return "background:repeating-linear-gradient(135deg,#17130f 0px,#201b15 3px,#181510 6px)", ""
    if low in {"ui-dialogbox-background", "ui-dialogbox-background-dark"}:
        return "background:linear-gradient(#30241a,#18110b)", ""
    if low.startswith("ui-panel-button-"):
        return "background:linear-gradient(#8b2519,#5b110b 45%,#7a1e12);border:2px ridge #8e713b;box-shadow:inset 0 0 0 1px #211208", ""
    if low in {"availablequesticon", "activequesticon"}:
        return "background:transparent;color:#e8bc33;font:bold 28px Georgia;text-shadow:1px 2px #38210b;text-align:center", "!" if low.startswith("available") else "?"
    if low in {"ui-questreward-exp", "ui-questreward-experience"}:
        return "background:#684681;color:#fff;font:bold 12px Georgia;text-align:center", "XP"
    if data := local_asset(path, item_id, coords):
        return f"background-image:url('{data}');background-size:100% 100%;background-repeat:no-repeat", ""
    return "background:#30291e;border:1px solid #8b7040;color:#d7c69e;font:15px Georgia;text-align:center", "?"


def render(nodes, width, height, debug=False):
    parts = []
    for n in nodes:
        l, t, w, h = n["l"], n["t"], n["w"], n["h"]
        alpha = n.get("alpha", 1)
        if w <= 0 or h <= 0:
            continue
        clip = ""
        if n.get("clip"):
            cl, ct, cw, ch = n["clip"]
            top, left = max(0, ct - t), max(0, cl - l)
            right, bottom = max(0, (l + w) - (cl + cw)), max(0, (t + h) - (ct + ch))
            if left >= w or top >= h or right >= w or bottom >= h:
                continue
            clip = f"clip-path:inset({top:.1f}px {right:.1f}px {bottom:.1f}px {left:.1f}px);"
        box = f"left:{l:.1f}px;top:{t:.1f}px;width:{w:.1f}px;height:{h:.1f}px;{clip}"
        kind = n["kind"]
        if kind == "Texture":
            if n.get("gradient"):
                g = n["gradient"]
                c1, c2 = g[1], g[2]
                direction = "to right" if n["gradient"][0] == "HORIZONTAL" else "to top"
                style = f"background:linear-gradient({direction},{color(c1, alpha)},{color(c2, alpha)});"
                parts.append(f'<div class="r" style="{box}{style}"></div>')
            elif n.get("rgba"):
                parts.append(f'<div class="r" style="{box}background:{color(n["rgba"], alpha, n.get("tint"))}"></div>')
            elif n.get("path"):
                path = str(n["path"])
                if "WHITE8X8" in path and n.get("tint"):
                    parts.append(f'<div class="r" style="{box}background:{color(n["tint"], alpha)}"></div>')
                else:
                    style, label = icon_style(path, n.get("tint"), n.get("itemId"), n.get("coords"))
                    parts.append(f'<div class="r ic" title="{html.escape(path)}" style="{box}{style};opacity:{alpha:.2f}">{html.escape(label)}</div>')
        elif kind == "FontString":
            text = n.get("text") or ""
            if not text:
                continue
            size = n.get("size") or 12
            justify = {"LEFT": "left", "RIGHT": "right", "CENTER": "center"}.get(n.get("justify"), "left")
            wrap = n.get("wrap")
            style = f"font-size:{size}px;color:{color(n.get('color') or [1, 1, 1, 1], alpha)};text-align:{justify};"
            style += "white-space:pre-wrap;" if wrap else "white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"
            parts.append(f'<div class="t" style="{box}{style}">{rich(text)}</div>')
        else:
            if n.get("template") == "InputBoxTemplate" or kind == "EditBox":
                parts.append(f'<div class="eb" style="{box}"><span>{html.escape(str(n.get("text") or ""))}</span></div>')
            elif debug:
                parts.append(f'<div class="dbg" style="{box}"></div>')
    css = ("body{margin:0;background:#2b3a2a url(none);}"
           ".stage{position:relative;width:%dpx;height:%dpx;overflow:hidden;font-family:'Segoe UI',Arial,sans-serif;"
           "background:linear-gradient(135deg,#5b6b45,#8a7a4a 45%%,#4a5b3a)}"
           ".r,.t,.eb,.dbg{position:absolute;box-sizing:border-box}.t{line-height:1.25}.ic{border-radius:2px;overflow:hidden;display:flex;align-items:flex-end}"
           ".ic{display:block}"
           ".eb{background:#0d0d12;border:1px solid #6b6b78;border-radius:3px;color:#fff;font-size:12px;padding:3px 6px}"
           ".dbg{outline:1px solid rgba(255,0,0,.35)}") % (width, height)
    return f"<!doctype html><meta charset=utf-8><style>{css}</style><div class=stage>{''.join(parts)}</div>"


def lint(nodes):
    """Layout problems found in the exported nodes: buttons without a caption, texts on top of each other, things outside the window."""
    problems = []
    window = next((n for n in nodes if n["kind"] != "Texture" and n["kind"] != "FontString" and n.get("name") == "EvertallyFrame"), None)

    def visible_box(n, width_used=None):
        l, t, w, h = n["l"], n["t"], n["w"], n["h"]
        if width_used is not None:
            if n.get("justify") == "RIGHT":
                l = l + w - width_used
            elif n.get("justify") == "CENTER":
                l = l + (w - width_used) / 2
            w = width_used
        r, b = l + w, t + h
        c = n.get("clip")
        if c:
            l, t, r, b = max(l, c[0]), max(t, c[1]), min(r, c[0] + c[2]), min(b, c[1] + c[3])
        return (l, t, r, b) if r > l and b > t else None

    texts = []
    for n in nodes:
        if n["kind"] == "FontString" and (n.get("text") or "").strip():
            plain = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", n["text"]).replace("||", "|")
            size = n.get("size") or 12
            used = min(n["w"], len(plain.encode("utf8").decode("utf8")) * size * 0.55) if not n.get("wrap") else min(n["w"], len(plain) * size * 0.55)
            box = visible_box(n, used)
            if box:
                texts.append((plain, box, n))
            if not n.get("wrap") and len(plain) * size * 0.55 > n["w"] + 2 and n["w"] > 0:
                problems.append(f"cut off: '{plain[:40]}' needs {len(plain) * size * 0.55:.0f}px, has {n['w']:.0f}px")
        elif n["kind"] not in ("Texture", "FontString") and n.get("hasCaption") and n.get("captionEmpty") and n["w"] > 20 and n["h"] > 12:
            problems.append(f"button without a caption at {n['l']:.0f},{n['t']:.0f} ({n['w']:.0f}x{n['h']:.0f})")
    for i in range(len(texts)):
        for j in range(i + 1, len(texts)):
            (ta, a, na), (tb, b, nb) = texts[i], texts[j]
            ix = min(a[2], b[2]) - max(a[0], b[0])
            iy = min(a[3], b[3]) - max(a[1], b[1])
            if ix > 3 and iy > 3:
                smaller = min((a[2] - a[0]) * (a[3] - a[1]), (b[2] - b[0]) * (b[3] - b[1]))
                if ix * iy > 0.25 * smaller:
                    problems.append(f"overlap: '{ta[:28]}' x '{tb[:28]}' at {max(a[0], b[0]):.0f},{max(a[1], b[1]):.0f}")
    if window:
        wl, wt, wr, wb = window["l"], window["t"], window["l"] + window["w"], window["t"] + window["h"]
        for plain, box, n in texts:
            if box[0] < wl - 1 or box[1] < wt - 1 or box[2] > wr + 1 or box[3] > wb + 1:
                problems.append(f"outside the window: '{plain[:40]}'")
    return problems


def make_session(ww, wh, sw=1280, sh=760, openmap=False, language="en"):
    """The add-on running on the layout mock with a realistic character; returns (lua, add-on table)."""
    lua, a = runtime()
    # The collision data uses the real client's packed-string codec. Model it
    # with exact base64/zlib bytes, rather than silently making every path fail.
    lua.globals().PY_NAV_UNPACK = lambda data, _method: zlib.decompress(base64.b64decode(data))
    lua.globals().debugprofilestop = lambda: time.perf_counter() * 1000
    lua.execute('''
      C_EncodingUtil={DecodeBase64=function(v) return v end,DecompressString=PY_NAV_UNPACK}
      Enum=Enum or {};Enum.CompressionMethod={Zlib=1}
    ''')
    lua.execute(f"SCREEN_W,SCREEN_H={sw},{sh}")
    lua.execute((HERE / "layout_mock.lua").read_text(encoding="utf8"))
    lua.execute(FIXTURE)
    # a small forum, so that the Community page shows threads, a thread on parchment and a reply from another realm
    lua.execute("""EvertallyForumData={schemaVersion=1,generatedAt=NOW-100,count=2,threads={
      {id="wabcdef012345",category="dungeons",title="Deadmines v patek, hledam healera",author="Aria-Fixture Realm",classId=8,origin="web",pinned=false,createdAt=NOW-5000,lastPostAt=NOW-300,replies=1,posts={
        {id="wabcdef012345",author="Aria-Fixture Realm",classId=8,origin="web",body="Kdo jde v patek vecer? Potrebuji healera a jednoho tanka. Level 18 az 22.",createdAt=NOW-5000},
        {id="gpost00112233",author="Bran-Other Realm",classId=7,origin="game",body="Ja.",createdAt=NOW-300,replyTo="wabcdef012345"}}},
      {id="wpinned123456",category="general",title="Pravidla foray",author="Admin-Fixture Realm",origin="web",pinned=true,createdAt=NOW-9000,lastPostAt=NOW-9000,replies=0,posts={
        {id="wpinned123456",author="Admin-Fixture Realm",origin="web",body="Be kind.",createdAt=NOW-9000}}}}}""")
    a.ForumResetCache()
    # Forever has C_Traits only. Leave legacy GetTalent* globals absent so a broken adapter cannot hide behind the mock.
    lua.execute(FOREVER_TRAITS)
    lua.execute('TRAIT_NODES[100001].activeRank=4;TRAIT_NODES[100201].activeRank=0')
    a.db.settings.language = language
    a.db.settings.uiWidth, a.db.settings.uiHeight = ww, wh
    # the map add-on, loaded the way the game does it on first use (with the stand-ins the unit tests use for the map libraries and QuestieDB)
    lua.execute(FAKE_LIBS)
    lua.execute(MapTests.FAKE_QUESTIE)
    lua.execute(FAKE_JOURNAL)   # (a small stand-in for the DungeonJournal add-on's data)
    map_table = lua.table()

    def load_map():
        for line in (ROOT / "addon" / "Evertally_Map" / "Evertally_Map.toc").read_text(encoding="utf8").splitlines():
            if line.endswith(".lua") and not line.startswith("Libs"):
                chunk = lua.eval("loadstring")((ROOT / "addon" / "Evertally_Map" / line.strip()).read_text(encoding="utf8"), line)
                if isinstance(chunk, tuple):
                    raise RuntimeError(str(chunk))
                chunk("Evertally_Map", map_table)
        # Item ids, names and artwork are the existing local reference export; unlike the talent APIs above these are not invented fixtures.
        item_guide = map_table.itemGuide
        if item_guide is not None:
            lua.globals().PREVIEW_ITEM_GUIDE = item_guide
            lua.execute('''
                GetItemIcon=function(id) local item=PREVIEW_ITEM_GUIDE[tonumber(id)];return item and item.icon or "Interface\\\\Icons\\\\INV_Misc_QuestionMark" end
                GetItemInfo=function(id) local item=PREVIEW_ITEM_GUIDE[tonumber(id)];if item then return item.name,nil,item.quality end end
            ''')
            for item_id, item in item_guide.items():
                if item.icon is not None:
                    icon_key = str(item.icon).replace("/", "\\").lower()
                    icon_file = ROOT / "platform/public/media/identity/items" / f"{int(item_id)}.jpg"
                    if icon_file.is_file():
                        ICON_FILES.setdefault(icon_key, icon_file)
        return True

    lua.globals().PYLOADMAP = load_map
    lua.execute("LoadAddOn=function(name) return PYLOADMAP() end")
    a.db.settings.mapPins = True
    if openmap:   # a stand-in for OpenMap's interface (the shape read from OpenMap 0.8.3)
        lua.execute(OPENMAP)
    return lua, a


WORLD_TABS = ("map", "plan", "gather", "services", "instances")
# pages with more than one state worth looking at: view -> the states
STATES = {"setup": ("1", "2", "3", "4", "5", "6", "7", "7:names", "7:icons", "7:position", "7:auras", "7:bars", "8", "9"), "settings": ("names", "icons", "auras", "bars", "position"), "viewer": ("equipped", "bags", "professions"), "world": WORLD_TABS, "database": ("npc", "quest", "item"), "dungeons": ("home", "bosses", "quests", "map"), "overview": ("activity", "areas", "loot"), "rankings": ("runs", "level", "fastest", "dungeons"), "journal": ("all", "quests")}


def capture(lua, a, view, tab=None, quest_id=None, destination=None):
    """Opens one page (one tab of the World page), lets the client's size events settle and exports what is drawn."""
    if view == "setup":   # the first-start setup, one step at a time
        step, _, group = (tab or "1").partition(":")
        a.OpenOnboarding(int(step))
        if group:
            lua.execute('C_CVar={GetCVar=function() return "1" end,SetCVar=function() end}')
            editor = a.onboarding.pages[7].plates
            editor.providers.evertally.GetScript(editor.providers.evertally,"OnClick")()
            editor.group = group
            editor.Update()
        win = a.onboarding.window
        lua.execute("PREVIEW_SETTLE()")
        return to_py(lua.eval("PREVIEW_EXPORT")(win))
    if view == "viewer":   # the window that opens when somebody shows you their things
        a.OpenUI()
        ok, ident = a.RequestInspect("Thalia-Valdren", "ip")
        items = ",".join(f"{slot}:{900000 + slot}" for slot in (1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 15, 16))
        bags = ",".join(f"{2500 + i}*{(i % 3) * 7 + 1}" for i in range(1, 17))
        a.ReceiveMessage("Evtly1", f"S|A|{ident}|ip|1", "WHISPER", "Thalia-Valdren")
        a.ReceiveMessage("Evtly1", f"S|D|{ident}|1|1|I1;E={items};B={bags};P=171:225:300:Alchemy:97", "WHISPER", "Thalia-Valdren")
        viewer = lua.globals().EvertallyViewFrame
        viewer.mode = tab or "equipped"
        viewer.wanted[900001], viewer.wanted[2503] = 1, 8
        a.SocialRefreshViewer()
        return to_py(lua.eval("PREVIEW_EXPORT")(viewer))
    a.ShowView(view)
    lua.execute("PREVIEW_SETTLE()")
    if view == "settings" and tab:
        lua.execute('C_CVar={GetCVar=function() return "1" end,SetCVar=function() end}')
        a.db.settings.plateGameLook = True
        a.settingsPage.SelectSection(5)
        editor = a.settingsPage.plates
        editor.providers.evertally.GetScript(editor.providers.evertally,"OnClick")()
        a.settingsPage.plates.group = tab
    if view == "world" and a.worldBody is not None:
        a.worldBody.mode = tab or "map"
        a.map.RefreshWorld(a.worldBody)
        if tab == "plan" and destination:
            frame = a.worldBody.tabFrames.plan
            box = frame.plan.box
            box.SetText(box, destination)
            box.GetScript(box, "OnTextChanged")(box)
            row = frame.plan.rows[1]
            if row.place is None:
                raise ValueError(f"No destination matches {destination!r}.")
            row.GetScript(row, "OnClick")()
            lua.execute("PREVIEW_SETTLE()")
    if view == "database" and a.databaseBody is not None:
        frame = a.databaseBody.tabFrames.db
        kind = "quest" if quest_id else tab or "npc"
        query = {"npc": "mar", "quest": "kob", "item": "line"}[kind]
        if quest_id:
            extra = a.map.questDetails[int(quest_id)]
            if extra is None:
                raise ValueError(f"Quest {quest_id} is not in the local reference export.")
            lua.globals().PREVIEW_QUEST_ID = int(quest_id)
            lua.globals().PREVIEW_QUEST_EXTRA = extra
            # Inject only this real exported quest into the otherwise synthetic Questie contract.
            # Both the selected index row and reader must describe the same record.
            lua.execute('''
              local ids, get = LibQuestieDB.Quest.GetAllIds, LibQuestieDB.Quest.GetAll
              LibQuestieDB.Quest.GetAllIds=function()
                local result=ids();for _,id in ipairs(result) do if id==PREVIEW_QUEST_ID then return result end end
                result[#result+1]=PREVIEW_QUEST_ID;return result
              end
              LibQuestieDB.Quest.GetAll=function(id,wanted)
                if id~=PREVIEW_QUEST_ID then return get(id,wanted) end
                local q=PREVIEW_QUEST_EXTRA
                local row={name=q.name,questLevel=q.questLevel,requiredLevel=q.requiredLevel,objectivesText=q.objective and {q.objective}}
                local result={n=#wanted};for i,key in ipairs(wanted) do result[i]=row[key] end;return result
              end
              Evertally.map.Db.index.quest=nil
            ''')
            query = str(extra.name)
        frame.db.kind = kind
        box = frame.db.box
        box.SetText(box, query); box.GetScript(box, "OnTextChanged")(box)
        handle = frame.db.dbHandle
        for _ in range(400):   # the page reads the names a slice at a time from a timer; the preview has none
            done, _progress = a.map.Db.Step(handle, kind, 1000)
            if done:
                break
        a.map.WorldDbRefresh(frame)
        row = frame.db.rows[1]
        if row.id:
            row.GetScript(row, "OnClick")()
        if quest_id:
            frame.db.selected = lua.table_from({"kind": "quest", "id": int(quest_id)})
            a.map.WorldDbDetail(frame)
    if view == "overview" and tab:
        a.overviewPage.recentMode = tab
    elif view == "rankings" and tab:
        a.rankingsPage.mode = tab
    elif view == "journal" and tab:
        a.journalPage.filter = tab
    a.RefreshUI()
    if view == "dungeons" and tab and tab != "home":
        dj = a.dungeonsBody.dungeons
        dj.cards[1].GetScript(dj.cards[1], "OnClick")(dj.cards[1])
        dj.tabs[tab].GetScript(dj.tabs[tab], "OnClick")()
        a.RefreshUI()
        lua.execute("PREVIEW_SETTLE()")
    return to_py(lua.eval("PREVIEW_EXPORT")(None))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("views", nargs="*")
    ap.add_argument("--size", default="960x620")
    ap.add_argument("--out", default=str(ROOT / "output" / "ui-preview"))
    ap.add_argument("--debug", action="store_true")
    ap.add_argument("--screen", default="1280x760")
    ap.add_argument("--no-shots", action="store_true")
    ap.add_argument("--tab", default="")
    ap.add_argument("--language", choices=("en", "cs"), default="en")
    ap.add_argument("--quest-id", type=int, help="show an actual local quest card in the database reader")
    ap.add_argument("--destination", help="select a real travel destination in the journey tab")
    ap.add_argument("--openmap", action="store_true", help="draw it as if OpenMap were installed")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    sw, sh = (int(v) for v in args.screen.split("x"))
    ww, wh = (int(v) for v in args.size.split("x"))
    lua, a = make_session(ww, wh, sw, sh, args.openmap, args.language)
    problems = {}
    scenes = []
    for view in args.views or VIEWS:
        if view in STATES:
            scenes += [(view, tab) for tab in ((args.tab,) if args.tab else STATES[view])]
        else:
            scenes.append((view, None))
    for view, tab in scenes:
        nodes = capture(lua, a, view, tab, args.quest_id if view == "database" else None, args.destination)
        name = f"{view}{'-' + tab.replace(':', '-') if tab else ''}-{ww}x{wh}{'-openmap' if args.openmap else ''}"
        if args.language != "en": name += "-" + args.language
        if args.quest_id and view == "database": name += "-" + str(args.quest_id)
        page = out / f"{name}.html"
        page.write_text(render(nodes, sw, sh, args.debug), encoding="utf8")
        bad = [k for k in ("ui_refresh", "overview_page", "journal_page", "rankings_page", "social_page", "world_page", "forum_page", "forum_compose") if a.errors[k]]
        if bad or a.lastUIError:
            problems[name] = (bad, str(a.lastUIError))
        if not args.no_shots:
            subprocess.run(["node", str(CAPTURE), str(page.resolve()), str(page.with_suffix(".png")), str(sw), str(sh)], check=True)
        found = lint(nodes)
        print("drew", name, f"({len(found)} layout problems)" if found else "(clean)")
        for line in found[:25]:
            print("   -", line)
    if problems:
        print("ERRORS:", json.dumps(problems, ensure_ascii=False))


if __name__ == "__main__":
    main()
