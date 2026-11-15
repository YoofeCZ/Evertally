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
        paper=[node for node in nodes if node['kind']=='Texture' and node.get('rgba') and node['rgba'][3]==1 and node['w']>=610 and node['h']>=390]
        self.assertTrue(paper,'reader must be opaque across its entire surface')
        self.assertTrue(any(node['rgba'][2]>node['rgba'][0] and node['rgba'][1]<.2 for node in paper),'the full reader uses the shared dark navy surface')
        self.assertIn('WHITE8X8',panel._backdrop.bgFile)

    def test_refresh_reuses_the_support_texture(self):
        lua,addon=preview.make_session(960,620)
        panel=lua.eval('CreateFrame')('Frame',None,lua.globals().UIParent)
        addon.NativeParchment(panel,addon.UIKit().C)
        count=lua.eval('function(frame) return #frame._regions end')(panel)
        for _ in range(20):addon.NativeParchment(panel,addon.UIKit().C)
        self.assertEqual(lua.eval('function(frame) return #frame._regions end')(panel),count)


if __name__=='__main__':unittest.main()
