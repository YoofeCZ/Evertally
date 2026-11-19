"""The guide's tweens (Evertally_Guide/Theme/Anim.lua): one tween whose object fails must not freeze the others.
2026-11-19: on a player's PC the setup's page stayed at alpha 0 (its fade-in never moved), so its titles and labels
were not seen; one failing tween stopped the shared loop on itself every frame."""
from pathlib import Path
import unittest

import lupa

ROOT = Path(__file__).resolve().parents[2]
ANIM = ROOT / "addon" / "Evertally_Guide" / "Theme" / "Anim.lua"

STUB = r'''
NOW = 0
function GetTime() return NOW end
DRIVER = nil
function CreateFrame()
  DRIVER = {script = nil}
  function DRIVER:SetScript(_, fn) self.script = fn end
  return DRIVER
end
ERRORS = {}
NS = {Get = function() return nil end,
      Safe = function(fn) return function(...) local ok, e = pcall(fn, ...); if not ok then ERRORS[#ERRORS + 1] = e end end end}
function OBJ(fail)
  local o = {alpha = nil, calls = 0}
  -- (a broken one draws its first value, then fails: as a frame gone bad while it fades)
  function o:SetAlpha(v) self.calls = self.calls + 1; if fail and self.calls > 1 then error("broken frame") end; self.alpha = v end
  return o
end
function FRAME() if DRIVER.script then DRIVER.script() end end
'''


class GuideAnimTests(unittest.TestCase):
    def setUp(self):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(STUB)
        chunk = self.lua.eval("loadstring or load")(ANIM.read_text(encoding="utf8"))
        self.lua.globals().ANIM_CHUNK = chunk
        self.lua.execute('ANIM_CHUNK("Evertally_Guide", NS); Anim = NS.Anim')

    def test_one_failing_tween_does_not_freeze_the_page_fade(self):
        lua = self.lua
        lua.execute('''
          BAD, PAGE = OBJ(true), OBJ(false)
          Anim.To(BAD, "alpha", 0, 1, 0.18, "out")
          Anim.To(PAGE, "alpha", 0, 1, 0.18, "out")
        ''')
        g = lua.globals()
        self.assertEqual(g.PAGE.alpha, 0, "starts at its from")
        for t in (0.05, 0.1, 0.2, 0.3):
            g.NOW = t
            lua.execute("FRAME()")
        self.assertEqual(g.PAGE.alpha, 1, "the page fades in to the end")
        self.assertEqual(lua.eval("Anim.Active()"), 0, "nothing left running")
        self.assertEqual(lua.eval("#ERRORS"), 1, "the failure is still reported, once")

    def test_stop_with_a_failing_tween_in_flight_does_not_throw(self):
        lua = self.lua
        lua.execute('''
          BAD, PAGE = OBJ(true), OBJ(false)
          Anim.To(BAD, "alpha", 0, 1, 0.18, "out")
          Anim.To(PAGE, "alpha", 0, 1, 0.18, "out")
          Anim.Stop(PAGE, "alpha")
        ''')
        self.assertEqual(lua.globals().PAGE.alpha, 1)


if __name__ == "__main__":
    unittest.main()
