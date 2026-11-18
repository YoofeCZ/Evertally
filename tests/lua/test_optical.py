"""Cross-language optical transport fixture (the live-position marker). No game, screenshot or user data."""
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_addon import runtime, ROOT

LEVELS=[0,16,32,48]

def adler(text):
    a,b=1,0
    for ch in text.encode():
        a=(a+ch)%65521;b=(b+a)%65521
    return b*65536+a

def fletcher(values):
    c0=c1=0
    for v in values:
        c0=(c0+v)%255;c1=(c1+c0)%255
    return c1*256+c0

def lst(table):
    return [table[i] for i in range(1,len(table)+1)]

MOCK_POSITION='C_Map={GetBestMapForUnit=function() return 1429 end,GetPlayerMapPosition=function() return {GetXY=function() return 0.42345,0.65123 end} end}'

class OpticalTests(unittest.TestCase):
    def test_marker_obeys_consent_and_carries_only_own_location(self):
        lua,a=runtime()
        lua.execute(MOCK_POSITION)
        self.assertIsNone(a.OpticalPacket())
        a.SetScope('guild_share',False)   # (every scope is on from the start since 2026-11-18; the guild here is switched off)
        a.SetScope('own_track',True);a.SetScope('own_character',True);a.SetWeb(True)
        self.assertIsNone(a.OpticalPacket(),'the screen-corner marker is its own opt-in: web consents alone never draw it')
        a.db.settings.liveWeb=True
        p=a.OpticalPacket()
        self.assertEqual((p.m,p.x,p.y),(1429,42345,65123))
        self.assertEqual(p.key,adler('Player-TEST-own'),'the bridge finds the character by the Adler-32 of its GUID')
        self.assertEqual(p.b & 20,20,'my character (4) and my route (16) are consented')
        self.assertEqual(p.b & 32,0,'the guild list (32) is switched off')
        data=lst(a.OpticalBytes(p))
        self.assertEqual(len(data),31)
        self.assertEqual(data[0],4)
        self.assertEqual(data[29]*256+data[30],fletcher(data[:29]),'Fletcher-16 over the first 29 bytes')
        self.assertEqual((data[12]*256+data[13],data[14]*65536+data[15]*256+data[16],data[17]*65536+data[18]*256+data[19]),(1429,42345,65123))
        symbols=lst(a.OpticalSymbols(a.OpticalBytes(p)))
        self.assertEqual(len(symbols),42)
        self.assertTrue(all(0<=s<64 for s in symbols))
        pixels=[lst(px) for px in lst(a.OpticalPixels(p))]
        self.assertEqual(len(pixels),4+42,'a 46 pixel row: four reference shades, then the data')
        self.assertEqual(pixels[:4],[[v,v,v] for v in LEVELS])
        self.assertTrue(all(c in LEVELS for px in pixels for c in px),'only the four near-black shades are ever drawn')
        self.assertLessEqual(max(c for px in pixels for c in px)/255,0.19)
        # Rust tests decode exactly this Lua output, not a second implementation alone.
        output=ROOT/'tests'/'lua'/'fixtures'/'optical.json'
        output.write_text(json.dumps({'packet':{k:p[k] for k in ('b','e','s','t','m','x','y','key','r')},'guid':'Player-TEST-own',
            'bytes':data,'symbols':symbols,'levels':LEVELS,'pixels':pixels},ensure_ascii=False),encoding='utf-8')
        a.SetWeb(False);self.assertIsNone(a.OpticalPacket())

    def test_values_that_do_not_fit_are_never_drawn(self):
        lua,a=runtime()
        good={'b':20,'e':3,'s':1000,'t':2000,'m':1429,'x':1,'y':2,'key':7}
        for field,value in (('x',100001),('y',-1),('m',70000),('b',64),('e',65536),('key',2**32),('t',1.5)):
            table=lua.table(**{**good,field:value})
            self.assertIsNone(a.OpticalBytes(table),field)
        self.assertEqual(len(lst(a.OpticalBytes(lua.table(**good)))),31)

    def test_live_roster_changes_in_the_pixels_without_a_saved_variables_write(self):
        lua,a=runtime();lua.execute(MOCK_POSITION)
        a.SetScope('own_track',True);a.SetScope('own_character',True);a.SetWeb(True)
        a.db.settings.liveWeb=True;a.db.settings.liveParty=True
        lua.execute('''
        PARTY_NAME="First"; UnitExists=function(unit)return unit=="party1" end
        local own=UnitFullName;UnitFullName=function(unit) if unit=="party1" then return PARTY_NAME,"Fixture Realm" else return own(unit) end end
        ''')
        one=a.OpticalPacket();self.assertEqual(len(one.tokens),1)
        lua.execute('PARTY_NAME="Second"')
        two=a.OpticalPacket();self.assertNotEqual(two.r,one.r)
        self.assertNotEqual(two.tokens[1].key,one.tokens[1].key)
        self.assertEqual(two.tokens[1].kind,'group')
        a.db.settings.liveParty=False
        self.assertEqual(len(a.OpticalPacket().tokens),0)
        # Maximum bounded transport: 100 current contacts fit inside a128x6 physical-pixel area.
        two.tokens=lua.table_from([lua.table(key=i,kind='friend') for i in range(100)])
        self.assertEqual(len(a.OpticalBytes(two)),531)
        self.assertEqual(len(a.OpticalPixels(two)),712)

    def test_marker_is_physical_size_and_disappears_immediately_when_consent_changes(self):
        lua,a=runtime()
        lua.execute('''
        UIParent={GetEffectiveScale=function() return 0.75 end}
        GetPhysicalScreenSize=function() return 1920,1080 end
        local function object()
          local o={visible=false}
          setmetatable(o,{__index=function(t,k) return function() end end})
          function o:Show() self.visible=true end
          function o:Hide() self.visible=false end
          function o:SetScale(s) self.scale=s end
          function o:SetSize(w,h) self.width=w;self.height=h end
          function o:CreateTexture() return object() end
          return o
        end
        function CreateFrame(_,name) local o=object();_G[name]=o;return o end
        ''')
        lua.execute(MOCK_POSITION)
        a.SetScope('own_track',True);a.SetScope('own_character',True);a.SetWeb(True)
        a.OpticalTick();self.assertIsNone(lua.globals().EvertallyLiveBridgeStrip,'nothing is drawn until the live-position opt-in is on')
        a.db.settings.liveWeb=True
        a.OpticalTick();frame=lua.globals().EvertallyLiveBridgeStrip
        self.assertTrue(frame.visible)
        self.assertEqual((frame.width,frame.height),(46,1),'one row, 46 pixels')
        a.db.settings.liveWeb=False;a.OpticalTick();self.assertFalse(frame.visible,'switching the opt-in off hides it at the next tick')
        a.db.settings.liveWeb=True;a.OpticalTick();self.assertTrue(frame.visible)
        # one unit of the marker must be one real screen pixel: scale * UI scale * physical height / 768 == 1.
        # (The first version used scale * UI scale == 1, which is 1.41 px per unit at 1080p; measured on screen, 4.2 px cells.)
        self.assertAlmostEqual(frame.scale*0.75*1080/768,1)
        for height,ui in ((768,1.0),(1080,768/1080),(1440,0.5),(2160,0.45)):
            lua.execute('GetPhysicalScreenSize=function() return 1,%d end;UIParent.GetEffectiveScale=function() return %r end'%(height,ui))
            a.OpticalTick();self.assertAlmostEqual(frame.scale*ui*height/768,1,msg='physical height %d'%height)
        lua.execute('GetPhysicalScreenSize=nil;GetCVar=function() return "2560x1440" end;UIParent.GetEffectiveScale=function() return 0.6 end')
        a.OpticalTick();self.assertAlmostEqual(frame.scale*0.6*1440/768,1,msg='falls back to the resolution setting')
        a.SetScope('own_track',False);self.assertFalse(frame.visible)
        a.SetScope('own_track',True);a.OpticalTick();self.assertTrue(frame.visible)
        a.SetWeb(False);self.assertFalse(frame.visible)

if __name__=='__main__':unittest.main()
