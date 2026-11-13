"""Solid route strokes on both map surfaces. No running WoW or player data are accessed."""
from pathlib import Path
import math
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import LuaRuntime, ROOT


SCENE = r'''
FRAMES={}; REGIONS={}; NATIVE=true; ROTATE="0"; FACING=0; RADIUS=100; SHAPE="ROUND"
PX=0; PY=0; INSTANCE=0; NEXT_STITCH=false
Evertally={Call=function(fn,...) if type(fn)=="function" then local ok,a,b,c=pcall(fn,...);if ok then return a,b,c end end end,
    Number=function(v) if type(v)=="number" and v==v and math.abs(v)<math.huge then return v end end}
local methods={}
function methods:IsShown() return self.shown end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetLeft() return self.left or (self.parent and self.parent:GetLeft()) or 0 end
function methods:GetTop() return self.top or (self.parent and self.parent:GetTop()) or 0 end
function methods:GetEffectiveScale() return self.scale or (self.parent and self.parent:GetEffectiveScale()) or 1 end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameLevel(level) assert(type(level)=="number");self.level=level end
function methods:SetAllPoints(parent) self.width=parent.width;self.height=parent.height end
function methods:EnableMouse(on) self.mouse=on end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:RegisterEvent(event) self.events[event]=true end
function methods:SetColorTexture(r,g,b,a) self.texture={r,g,b,a} end
function methods:SetTexture(path,hwrap,vwrap,filter) self.asset=path;self.wrap={hwrap,vwrap};self.filter=filter end
function methods:SetVertexColor(r,g,b,a) self.color={r,g,b,a} end
function methods:SetThickness(width) assert(width>0);self.thickness=width end
function methods:SetStartPoint(anchor,owner,x,y)
    assert(anchor=="TOPLEFT" and owner==self.parent and type(x)=="number" and type(y)=="number")
    self.x1,self.y1=x,-y
end
function methods:SetEndPoint(anchor,owner,x,y)
    assert(anchor=="TOPLEFT" and owner==self.parent and type(x)=="number" and type(y)=="number")
    self.x2,self.y2=x,-y
end
local function region(parent,sublevel,kind)
    local r=setmetatable({parent=parent,shown=true,sublevel=sublevel or 0,kind=kind},{__index=methods})
    REGIONS[#REGIONS+1]=r;return r
end
function methods:CreateLine(_,_,_,sublevel) if NATIVE then return region(self,sublevel,"line") end end
function methods:CreateTexture(_,_,_,sublevel) return region(self,sublevel,"texture") end
function CreateFrame(_,name,parent)
    local f=setmetatable({name=name,parent=parent,shown=true,width=200,height=200,scripts={},events={}},{__index=methods})
    FRAMES[#FRAMES+1]=f;return f
end
function DrawLine(r,owner,x1,y1,x2,y2,width,scale,anchor)
    assert(r.kind=="texture" and owner==r.parent and anchor=="TOPLEFT" and scale==1)
    r.x1,r.y1,r.x2,r.y2,r.thickness=x1,-y1,x2,-y2,width
end
UIParent=CreateFrame("Frame","UIParent");UIParent.scale=1
Minimap=CreateFrame("Frame","Minimap",UIParent);Minimap.zoom=0
function Minimap:GetZoom() return self.zoom end
WorldMapFrame=CreateFrame("Frame","WorldMapFrame",UIParent)
VIEW=CreateFrame("Frame","viewport",WorldMapFrame);VIEW.width=400;VIEW.height=200;VIEW.left=100;VIEW.top=800
CANVAS=CreateFrame("Frame","canvas",VIEW);CANVAS.width=400;CANVAS.height=200;CANVAS.left=100;CANVAS.top=800
WorldMapFrame.ScrollContainer=VIEW;WorldMapFrame.id=1429
function WorldMapFrame:GetCanvas() return CANVAS end
function WorldMapFrame:GetMapID() return self.id end
GetCVar=function(name) if name=="rotateMinimap" then return ROTATE elseif name=="minimapZoom" then return "0" end end
GetPlayerFacing=function() return FACING end
GetMinimapShape=function() return SHAPE end
C_Minimap={GetViewRadius=function() return RADIUS end}
HBD={}
function HBD:GetWorldCoordinatesFromZone(u,v,map) return (.6-u)*1000,(.5-v)*1000,map==1411 and 1 or 0 end
function HBD:GetPlayerWorldPosition() return PX,PY,INSTANCE end
function HBD:GetZoneCoordinatesFromWorldInstance(x,y,c,map,allowOutside)
    assert(allowOutside==true)
    if map==99 or (map==1411 and c~=1) or (map==1429 and c~=0) then return nil end
    return .6-x/1000,.5-y/1000
end
LibStub=function(name,silent) if name=="HereBeDragons-2.0" then return HBD end assert(silent) end
OpenMapAPI={major=1,version=2,IsStitched=function() return NEXT_STITCH end,ArtTopLevel=function() return 25 end,
    CanvasFromWorldPos=function(c,north,west) STITCH={c,north,west};return .6-west/1000,.5-north/1000 end}
M={data={maps={[1414]={0,.46,0,1},[1415]={.46,1,0,1}},yards={[0]={.6,-.001,.5,-.001},[1]={.6,-.001,.5,-.001}}}}
function M.Locate(u,v) return u<.46 and 1411 or 1429,u,v end
function M.ToYards(u,v) return u<.46 and 1 or 0,(.5-v)*1000,(.6-u)*1000 end
function Drive(dt)
    for _,f in ipairs(FRAMES) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f,dt) end end
end
function Event(event)
    for _,f in ipairs(FRAMES) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event) end end
end
function Strokes(surface)
    local out={}
    for _,r in ipairs(REGIONS) do
        if r.shown and r.sublevel==0 and r.parent.shown and r.parent.parent==surface then out[#out+1]=r end
    end
    return out
end
'''


class RouteLineTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(SCENE)
        loader = self.lua.eval("loadstring")((ROOT / "addon/Evertally_Map/Route.lua").read_text(encoding="utf-8"), "Route.lua")
        loader("Evertally_Map", self.lua.globals().M)
        self.m, self.g = self.lua.globals().M, self.lua.globals()

    def plan(self, *steps):
        return self.lua.table_from({"steps": self.lua.table_from([
            self.lua.table_from(dict(mode=mode, fu=fu, fv=fv, tu=tu, tv=tv))
            for mode, fu, fv, tu, tv in steps])})

    def show(self, plan):
        self.m.route = plan
        self.m.RefreshRoute(True)

    def strokes(self, surface):
        table = self.g.Strokes(self.g[surface])
        return [table[i] for i in range(1, len(table) + 1)]

    def assert_point(self, line, endpoint, x, y):
        self.assertAlmostEqual(line[f"x{endpoint}"], x, places=6)
        self.assertAlmostEqual(line[f"y{endpoint}"], y, places=6)

    def test_actual_bends_are_connected_solid_edges_on_both_maps(self):
        # The middle vertex is not collinear. Losing it would draw through a terrain obstacle.
        self.lua.execute("M.RouteLegPath=function() return {{.55,.5},{.6,.54},{.65,.5}} end")
        plan = self.plan(("walk", .55, .5, .65, .5))
        edges = self.m.RouteSegments(plan)
        self.assertEqual(len(edges), 2)
        self.assertAlmostEqual(edges[1].tu, edges[2].fu)
        self.assertAlmostEqual(edges[1].tv, edges[2].fv)
        self.show(plan)
        for surface in ("VIEW", "Minimap"):
            lines = self.strokes(surface)
            self.assertEqual(len(lines), 2)
            self.assertEqual(lines[0].kind, "line")
            self.assert_point(lines[0], 2, lines[1].x1, lines[1].y1)
            self.assertEqual(lines[0].texture[4], 1)
        self.assertEqual(self.m.routeLines, 2)
        self.assertEqual(self.m.routeMiniLines, 2)
        self.assertEqual(self.m.routeDots, 0)

    def test_world_rect_clips_crossing_with_both_endpoints_outside(self):
        self.show(self.plan(("flight", -.1, .5, 1.1, .5)))
        # Crossing between continents is deliberately absent. A same-continent offscreen edge is clipped.
        self.assertEqual(len(self.strokes("VIEW")), 0)
        self.lua.execute("M.ToYards=function(u,v) return 0,(.5-v)*1000,(.6-u)*1000 end;M.Locate=function(u,v) return 1429,u,v end")
        self.m.RefreshRoute(True)
        lines = self.strokes("VIEW")
        self.assertEqual(len(lines), 1)
        self.assert_point(lines[0], 1, 2.25, 100)
        self.assert_point(lines[0], 2, 397.75, 100)

    def test_circle_clips_whole_edge_including_offscreen_endpoints(self):
        self.show(self.plan(("flight", .1, .5, 1.1, .5)))
        self.assertEqual(len(self.strokes("Minimap")), 0)
        self.show(self.plan(("flight", .47, .5, .9, .5)))
        lines = self.strokes("Minimap")
        self.assertEqual(len(lines), 1)
        self.assert_point(lines[0], 1, 2.25, 100)
        self.assert_point(lines[0], 2, 197.75, 100)
        self.show(self.plan(("flight", .47, .2, .9, .2)))
        self.assertEqual(len(self.strokes("Minimap")), 0)

    def test_minimap_follows_player_zoom_rotation_and_resize_without_recompile(self):
        self.show(self.plan(("flight", .6, .5, .65, .5)))
        line = self.strokes("Minimap")[0]
        self.assert_point(line, 1, 100, 100)
        self.assert_point(line, 2, 150, 100)
        self.g.PX = -10
        self.g.Drive(.11)
        self.assert_point(line, 1, 90, 100)
        self.assert_point(line, 2, 140, 100)
        self.g.RADIUS = 50
        self.g.Drive(.11)
        self.assert_point(line, 1, 80, 100)
        self.assert_point(line, 2, 180, 100)
        self.g.ROTATE = "1"
        self.g.FACING = math.pi / 2
        self.g.Drive(.11)
        self.assert_point(line, 1, 100, 80)
        self.assert_point(line, 2, 100, 180)
        self.g.Minimap.width, self.g.Minimap.height = 300, 300
        self.g.Drive(.11)
        self.assert_point(line, 1, 150, 120)
        self.assert_point(line, 2, 150, 270)

    def test_world_projection_tracks_canvas_pan_zoom_scale_and_openmap_native_axes(self):
        self.show(self.plan(("flight", .6, .5, .65, .53)))
        line = self.strokes("VIEW")[0]
        self.assert_point(line, 1, 240, 100)
        self.assert_point(line, 2, 260, 106)
        self.g.CANVAS.width, self.g.CANVAS.height = 800, 400
        self.g.CANVAS.left, self.g.CANVAS.top = -200, 900
        self.g.Drive(.11)
        self.assert_point(line, 1, 180, 100)
        self.assert_point(line, 2, 220, 112)
        self.g.CANVAS.scale, self.g.VIEW.scale = 2, 2
        self.g.Drive(.11)
        self.assert_point(line, 1, 180, 100)
        self.assert_point(line, 2, 220, 112)
        self.assertEqual(line.thickness, 1.25)  # screen thickness stays fixed under UI scaling
        self.g.NEXT_STITCH = True
        self.g.WorldMapFrame.id = 99  # no HBD projection for this host map
        self.g.Drive(.11)
        self.assertEqual(self.m.routeLines, 1)
        self.assert_point(line, 1, 180, 100)
        self.assertAlmostEqual(self.g.STITCH[2], -30)  # north, NOT HBD's west axis
        self.assertAlmostEqual(self.g.STITCH[3], -50)
        self.g.NEXT_STITCH = False
        self.g.Drive(.11)
        self.assertEqual(len(self.strokes("VIEW")), 0)
        self.assertEqual(len(self.strokes("Minimap")), 1)

    def test_stop_hidden_maps_loading_and_invalid_position_hide_stale_lines(self):
        plan = self.plan(("flight", .6, .5, .65, .5))
        self.show(plan)
        self.g.WorldMapFrame.Hide(self.g.WorldMapFrame)
        self.g.Drive(.11)
        self.assertEqual(len(self.strokes("VIEW")), 0)
        self.assertEqual(len(self.strokes("Minimap")), 1)
        self.g.Event("LOADING_SCREEN_ENABLED")
        self.assertEqual(len(self.strokes("Minimap")), 0)
        self.g.Event("LOADING_SCREEN_DISABLED")
        self.assertEqual(len(self.strokes("Minimap")), 1)
        self.g.PX = None
        self.g.Drive(.11)
        self.assertEqual(len(self.strokes("Minimap")), 0)
        self.g.PX = 0
        self.g.WorldMapFrame.Show(self.g.WorldMapFrame)
        self.g.Drive(.11)
        self.assertEqual(len(self.strokes("VIEW")), 1)
        self.m.ClearRoute()
        self.assertEqual(len(self.strokes("VIEW")), 0)
        self.assertEqual(len(self.strokes("Minimap")), 0)

    def test_no_native_line_uses_blizzard_solid_drawline_never_dot_pins(self):
        self.g.NATIVE = False
        self.show(self.plan(("flight", .6, .5, .65, .5)))
        for surface in ("VIEW", "Minimap"):
            lines = self.strokes(surface)
            self.assertEqual(len(lines), 1)
            self.assertEqual(lines[0].kind, "texture")
            self.assertEqual(lines[0].thickness, 2.5)
            self.assertEqual(lines[0].wrap[1], "CLAMPTOBLACKADDITIVE")
            self.assertEqual(lines[0].wrap[2], "CLAMPTOBLACKADDITIVE")

    def test_temporarily_unavailable_rotation_api_hides_minimap_route_without_throwing(self):
        self.show(self.plan(("flight", .6, .5, .65, .5)))
        self.lua.execute('ROTATE="1"; GetPlayerFacing=function() error("unavailable") end')
        self.g.Drive(.11)
        self.assertEqual(len(self.strokes("Minimap")), 0)
        self.assertEqual(len(self.strokes("VIEW")), 1)

    def test_navigation_stopping_without_explicit_refresh_clears_both_painters(self):
        self.m.RoutePlan = self.lua.eval("function() return NAVPLAN end")
        self.g.NAVPLAN = self.plan(("flight", .6, .5, .65, .5))
        self.m.RefreshRoute(True)
        self.assertEqual(len(self.strokes("VIEW")), 1)
        self.assertEqual(len(self.strokes("Minimap")), 1)
        self.g.NAVPLAN = None
        self.g.Drive(.11)
        self.assertEqual(len(self.strokes("VIEW")), 0)
        self.assertEqual(len(self.strokes("Minimap")), 0)
        self.assertEqual(self.m.routeLines, 0)
        self.assertEqual(self.m.routeMiniLines, 0)

    def test_square_minimap_and_classic_radius_fallback(self):
        self.g.C_Minimap = None
        self.show(self.plan(("flight", .6, .5, .65, .5)))
        self.assert_point(self.strokes("Minimap")[0], 2, 100 + 50 / (466 + 2 / 3) * 200, 100)
        self.g.C_Minimap = self.lua.table_from({"GetViewRadius": self.lua.eval("function() return RADIUS end")})
        self.g.SHAPE = "SQUARE"
        self.show(self.plan(("flight", .47, .37, .9, .8)))
        line = self.strokes("Minimap")[0]
        self.assert_point(line, 1, 2.25, 2.25)
        self.assert_point(line, 2, 197.75, 197.75)

    def test_pooled_strokes_hide_unused_edges_and_reuse_after_clear(self):
        self.lua.execute("M.RouteLegPath=function() return {{.55,.5},{.6,.54},{.65,.5}} end")
        plan = self.plan(("walk", .55, .5, .65, .5))
        self.show(plan)
        count = len(self.g.REGIONS)
        self.assertEqual(count, 8)  # two edges, core plus outline, two surfaces
        self.m.ClearRoute()
        self.lua.execute("M.RouteLegPath=function() return nil end")
        self.show(plan)
        self.assertEqual(len(self.strokes("VIEW")), 1)
        self.assertEqual(len(self.strokes("Minimap")), 1)
        self.assertEqual(len(self.g.REGIONS), count)

    def test_invalid_edges_do_not_bridge_legs_or_continents(self):
        plan = self.plan(("boat", .2, .5, .7, .5), ("flight", .6, .5, .62, .5),
                         ("portal", .6, .5, .6, .5), ("walk", .6, .5, .65, .5))
        plan.steps[4].tv = None
        edges = self.m.RouteSegments(plan)
        self.assertEqual(len(edges), 1)
        self.assertEqual(edges[1].leg, 2)
        self.show(plan)
        self.assertEqual(len(self.strokes("VIEW")), 1)
        self.assertEqual(len(self.strokes("Minimap")), 1)

    def test_terrain_search_replaces_initial_edge_with_all_returned_bends(self):
        self.lua.execute('''
        M.Terrain={maps={[0]=true},Begin=function() return {state="pending"} end,
            Step=function(job) job.state="ready";job.result={points={{0,50},{-40,0},{0,-50}}} end,
            Cancel=function(job) job.state="cancelled" end}
        ''')
        plan = self.plan(("walk", .55, .5, .65, .5))
        self.show(plan)
        self.assertEqual(len(self.strokes("VIEW")), 1)
        self.assertTrue(self.m.RouteStep())
        self.m.RefreshRoute()
        self.assertEqual(len(self.strokes("VIEW")), 2)
        self.assertEqual(len(self.strokes("Minimap")), 2)
        self.assertEqual(self.m.routeReady, 1)


if __name__ == "__main__":
    unittest.main()
