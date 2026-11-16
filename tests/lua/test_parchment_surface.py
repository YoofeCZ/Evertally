"""Readers need opaque coverage even when a decorative game texture has transparent padding."""
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/ui_preview'))
sys.path.insert(0,str(ROOT/'tests/lua'))
import preview


class ParchmentSurfaceTests(unittest.TestCase):
    def test_reader_has_an_opaque_primitive_across_its_full_width_and_height(self):
        lua,addon=preview.make_session(960,620)
        panel=lua.eval('CreateFrame')("Frame",None,lua.globals().UIParent)
        panel.SetSize(panel,620,400);panel.SetPoint(panel,'CENTER')
        addon.NativeParchment(panel,addon.UIKit().C)
        lua.execute('PREVIEW_SETTLE()')
        nodes=preview.to_py(lua.eval('PREVIEW_EXPORT')(panel))
        # a flat colour, or the rounded body shape (opaque white texture tinted with the colour)
        def body(node):
            if node['kind']!='Texture' or node['w']<610 or node['h']<390: return None
            if node.get('rgba'): return node['rgba']
            if 'ShapeRound' in str(node.get('path') or '') and node.get('tint'): return node['tint']
        paper=[body(node) for node in nodes if body(node) and body(node)[3]==1]
        self.assertTrue(paper,'reader must be opaque across its entire surface')
        self.assertTrue(any(c[2]>c[0] and c[1]<.2 for c in paper),'the full reader uses the shared dark navy surface')
        shaped=any('ShapeRound' in str(node.get('path') or '') for node in nodes)
        self.assertTrue(shaped or 'WHITE8X8' in panel._backdrop.bgFile)

    def test_refresh_reuses_the_support_texture(self):
        lua,addon=preview.make_session(960,620)
        panel=lua.eval('CreateFrame')('Frame',None,lua.globals().UIParent)
        addon.NativeParchment(panel,addon.UIKit().C)
        count=lua.eval('function(frame) return #frame._regions end')(panel)
        for _ in range(20):addon.NativeParchment(panel,addon.UIKit().C)
        self.assertEqual(lua.eval('function(frame) return #frame._regions end')(panel),count)


if __name__=='__main__':unittest.main()
