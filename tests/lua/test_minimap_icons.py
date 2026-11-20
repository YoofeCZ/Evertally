"""Original client textures on the minimap and Evertally glyphs on the world map."""
import unittest

from test_addon import LuaRuntime, MOCK_UI_LUA, ROOT


class MinimapIconTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(r'''
            local function noop() end
            PROBES = {}
            UIParent.CreateTexture = function()
                local tex = object()
                tex.SetTexture = function(_, path)
                    PROBES[path] = (PROBES[path] or 0) + 1
                    if path:match("Repair$") then return false end
                end
                return tex
            end
            NS = {
                L = setmetatable({}, { __index = function(_, key) return key end }),
                RegisterDefaults = noop, OnInit = noop, OnLogin = noop, RegisterEvent = noop, On = noop,
                Get = function(key) return key:match("^maps%.serviceFilters%.") ~= nil end,
                Theme = { Color = function() return 0.5, 0.75, 1 end },
                Compat = { MapToWorld = function(map, x, y) return 0, x, y end },
            }
            function Paint(pin, minimap)
                local f = object()
                f.psMinimap = minimap
                NS.Pins.BuildLook(f)
                f.icon.SetVertexColor = function(self, ...) self.tint = {...} end
                NS.Pins.ApplyLook(f, pin, 14)
                return f
            end
        ''')
        self.g = self.lua.globals()
        for name in ("Nav/Pins.lua", "Maps/Maps.lua", "Maps/TravelPins.lua", "Maps/Services.lua"):
            source = (ROOT / "addon/Evertally_Guide" / name).read_text(encoding="utf-8")
            self.lua.eval("loadstring")(source, name)("Evertally_Guide", self.g.NS)

    def test_native_travel_texture_keeps_badge_and_bound_inn_ring(self):
        self.lua.execute(r'''
            local taxi, _, inns = NS.Maps.BuildTravelPins({ faction = 1, bind = "Goldshire", data = {
                taxi = {{ id = 2, name = "Stormwind", faction = 1, map = 1453, x = 10, y = 20 }},
                inns = {{ name = "Goldshire", names = {"Goldshire"}, map = 1429, x = 40, y = 50 }},
            }})
            WORLD = Paint(taxi[1], false)
            MINI = Paint(taxi[1], true)
            INN = Paint(inns[1], true)
        ''')
        self.assertTrue(self.g.WORLD.icon.texture.endswith(r"\Media\Map\icon-flightmaster"))
        self.assertTrue(self.g.WORLD.medal.IsShown(self.g.WORLD.medal))
        self.assertEqual(self.g.MINI.icon.texture, r"Interface\Minimap\Tracking\FlightMaster")
        self.assertEqual(list(self.g.MINI.icon.tint.values()), [1, 1, 1, 1])
        self.assertFalse(self.g.MINI.medal.IsShown(self.g.MINI.medal))
        self.assertEqual(self.g.MINI.badge.text.text, "?")
        self.assertTrue(self.g.MINI.badge.text.IsShown(self.g.MINI.badge.text))
        self.assertEqual(self.g.INN.icon.texture, r"Interface\Minimap\Tracking\Innkeeper")
        self.assertTrue(self.g.INN.mark.IsShown(self.g.INN.mark))

    def test_missing_client_texture_uses_evertally_glyph(self):
        self.lua.execute(r'''
            local pins = NS.Maps.BuildServicePins({
                { id = 1, kind = "object", roles = {"mailbox"}, spawns = {{map = 1453, x = 10, y = 20}} },
                { id = 2, roles = {"repair"}, spawns = {{map = 1453, x = 20, y = 30}} },
                { id = 3, roles = {"repair"}, spawns = {{map = 1453, x = 30, y = 40}} },
            })
            MAIL_WORLD = Paint(pins[1], false)
            MAIL_MINI = Paint(pins[1], true)
            REPAIR_MINI = Paint(pins[2], true)
        ''')
        self.assertTrue(self.g.MAIL_WORLD.icon.texture.endswith(r"\Media\Map\icon-mailbox"))
        self.assertEqual(self.g.MAIL_MINI.icon.texture, r"Interface\Minimap\Tracking\Mailbox")
        self.assertTrue(self.g.REPAIR_MINI.icon.texture.endswith(r"\Media\Map\icon-repair"))
        self.assertEqual(self.g.PROBES[r"Interface\Minimap\Tracking\Repair"], 1)
