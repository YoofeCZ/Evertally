"""Bag items that fit an empty equipment slot and are wearable now get a blue border, in any bag addon. No game/network."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_gear import setup_runtime

BUTTONS_LUA = r'''
FRAMES={}; TEXTURES=0
local function button(fields)
  local b=fields or {}
  b.visible=b.visible~=false
  b.lit=function(self) local g=Evertally.BagHighlight.glows[self];return g~=nil and g[1].shown==true end
  b.IsVisible=function(self) return self.visible end
  b.IsForbidden=function() return false end
  b.GetObjectType=function() return "Button" end
  b.CreateTexture=function(self)
    TEXTURES=TEXTURES+1
    local t={shown=true}
    return setmetatable(t,{__index=function(_,k) if k=="Show" then return function(s) s.shown=true end elseif k=="Hide" then return function(s) s.shown=false end end;return function() end end})
  end
  FRAMES[#FRAMES+1]=b;return b
end
-- Blizzard container button, Bagnon, AdiBags, Baganator, and a button that is not a bag item at all.
function BlizzardButton(slot) return button({GetBagID=function() return 0 end,GetID=function() return slot end}) end
function BagnonButton(slot) return button({GetBag=function() return 0 end,GetID=function() return slot end}) end
function AdiButton(slot,link) return button({bag=0,slot=slot,itemLink=link}) end
function BaganatorButton(slot,link) return button({GetBagID=function() return 0 end,GetID=function() return slot end,BGR={itemLink=link}}) end
function OtherButton() return button({GetID=function() return 1 end,itemLink="item:10"}) end
EnumerateFrames=function(prev)
  if prev==nil then return FRAMES[1] end
  for i,f in ipairs(FRAMES) do if f==prev then return FRAMES[i+1] end end
end
C_Container.GetContainerItemLink=function(_,slot) local x=BAGS[slot];return x and "item:"..x.id end
C_Timer=nil
'''


class BagHighlightTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a, self.g = setup_runtime()
        self.b = self.a.BagHighlight
        self.lua.execute(BUTTONS_LUA)
        # boots, mail boots (too heavy for a level 20 shaman), a ring, a shirt, a staff
        self.lua.execute('''
        Item(10,{loc="INVTYPE_FEET",class=4,sub=2,stats={}})
        Item(11,{loc="INVTYPE_FEET",class=4,sub=3,stats={}})
        Item(12,{loc="INVTYPE_FINGER",class=4,sub=0,stats={}})
        Item(13,{loc="INVTYPE_BODY",class=4,sub=0,stats={}})
        Item(14,{loc="INVTYPE_FEET",class=4,sub=1,level=40,stats={}})
        Item(15,{loc="INVTYPE_SHIELD",class=4,sub=6,stats={}})
        Item(16,{loc="INVTYPE_2HWEAPON",class=2,sub=10,stats={}})
        BAGS={{id=10},{id=11},{id=12},{id=13},{id=14},{id=15}}
        ''')

    def scan(self):
        self.b.wanted = self.lua.table(); self.b.lastFull = None
        return self.b.Scan(True)

    def test_the_full_walk_runs_at_most_once_per_gap_and_skips_unmarked_frames_cheaply(self):
        self.lua.execute('BlizzardButton(1);for i=1,50 do FRAMES[#FRAMES+1]={GetName=function() error("called") end} end')
        self.lua.execute('local plain={IsVisible=function() error("called") end};FRAMES[#FRAMES+1]=plain')
        self.assertEqual(self.scan(), 1, "frames without a bag-button field are never asked anything")
        self.lua.execute('BlizzardButton(3)')
        self.b.Scan(True)
        self.assertEqual(self.b.lit, 1, "a second walk within the gap does not run")
        self.lua.execute('CLOCK=CLOCK+3')
        self.b.Scan(True)
        self.assertEqual(self.b.lit, 2)

    def test_wearable_item_for_an_empty_slot_glows_in_the_blizzard_bags(self):
        self.lua.execute('for slot=1,6 do BlizzardButton(slot) end')
        self.assertEqual(self.scan(), 3)
        frames = self.lua.globals().FRAMES
        lit = [bool(frames[i].lit(frames[i])) for i in range(1, 7)]
        # boots yes, mail no (proficiency), ring yes, shirt no (cosmetic), level 40 boots no, shield yes (offhand empty)
        self.assertEqual(lit, [True, False, True, False, False, True])

    def test_an_occupied_slot_does_not_glow_and_rings_need_both_fingers_taken(self):
        self.lua.execute('for slot=1,3 do BlizzardButton(slot) end;EQUIPPED[8]=10;EQUIPPED[11]=12')
        self.lua.execute('Evertally.Gear.cache={}')
        frames = self.lua.globals().FRAMES
        self.scan()
        self.assertFalse(frames[1].lit(frames[1]))
        self.assertTrue(frames[3].lit(frames[3]), "one free finger is enough")
        self.lua.execute('EQUIPPED[12]=12;Evertally.Gear.cache={};Evertally.Dispatch("PLAYER_EQUIPMENT_CHANGED")')
        self.scan()
        self.assertFalse(frames[3].lit(frames[3]))

    def test_a_two_hander_in_the_main_hand_blocks_the_offhand(self):
        self.lua.execute('BlizzardButton(6);EQUIPPED[16]=16;Evertally.Gear.cache={}')
        frames = self.lua.globals().FRAMES
        self.scan()
        self.assertFalse(frames[1].lit(frames[1]))

    def test_other_bag_addons_are_recognised_and_non_bag_buttons_are_ignored(self):
        self.lua.execute('BagnonButton(1);AdiButton(3,"item:12");BaganatorButton(2,"item:10");OtherButton()')
        self.assertEqual(self.scan(), 3)
        frames = self.lua.globals().FRAMES
        self.assertFalse(frames[4].lit(frames[4]))
        self.assertIsNone(self.b.Locate(frames[4]))

    def test_hidden_buttons_and_the_setting_turn_the_glow_off(self):
        self.lua.execute('BlizzardButton(1)')
        frames = self.lua.globals().FRAMES
        self.scan(); self.assertTrue(frames[1].lit(frames[1]))
        self.assertIsNot(self.a.db.settings.bagHighlight, False, "on by default")
        self.b.SetEnabled(False)
        self.assertFalse(frames[1].lit(frames[1]))
        self.b.SetEnabled(True); self.assertTrue(frames[1].lit(frames[1]))
        frames[1].visible = False; self.scan()
        self.assertFalse(frames[1].lit(frames[1]))

    def test_textures_are_made_once_per_button_and_no_field_is_written_to_the_button(self):
        self.lua.execute('BlizzardButton(1)')
        frames = self.lua.globals().FRAMES
        before = sorted(str(k) for k in frames[1].keys())
        self.scan(); self.scan(); self.scan()
        self.assertEqual(self.lua.globals().TEXTURES, 5)
        self.assertEqual(sorted(str(k) for k in frames[1].keys()), before)

    def test_baganator_buttons_without_bag_and_slot_are_read_from_their_link(self):
        # Baganator's classic-style buttons expose only BGR.itemLink and a parent without an id
        self.lua.execute('local b=BlizzardButton(9);b.GetBagID=nil;b.GetID=function() return 0 end;b.BGR={itemLink="item:10"}')
        frames = self.lua.globals().FRAMES
        self.assertEqual(self.scan(), 1)
        self.assertTrue(frames[1].lit(frames[1]))

    def test_a_clean_item_tooltip_outweighs_is_usable_item_for_plain_armour(self):
        self.lua.execute('''
        IsUsableItem=function() return false,false end
        C_TooltipInfo={GetHyperlink=function(link)
          if link=="item:11" then return {lines={{leftText="Mail",leftColor={r=1,g=.1,b=.1}}}} end
          return {lines={{leftText="Boots",leftColor={r=1,g=1,b=1}}}} end}
        Item(11,{loc="INVTYPE_FEET",class=4,sub=1,stats={}})
        Evertally.Gear.cache={};BlizzardButton(1);BlizzardButton(2)''')
        frames = self.lua.globals().FRAMES
        self.scan()
        self.assertTrue(frames[1].lit(frames[1]), "plain boots: IsUsableItem false, tooltip has no red line")
        self.assertFalse(frames[2].lit(frames[2]), "a red requirement line in the tooltip still refuses the item")

    def test_an_upgrade_for_an_occupied_slot_gets_the_green_arrow(self):
        self.lua.execute('''
        Item(20,{loc="INVTYPE_LEGS",class=4,sub=2,stats={ITEM_MOD_AGILITY_SHORT=1}})
        Item(21,{loc="INVTYPE_LEGS",class=4,sub=2,stats={ITEM_MOD_AGILITY_SHORT=5}})
        Item(22,{loc="INVTYPE_LEGS",class=4,sub=2,stats={}})
        EQUIPPED[7]=20;BAGS={{id=21},{id=22}};Evertally.Gear.cache={}
        BlizzardButton(1);BlizzardButton(2)''')
        frames = self.lua.globals().FRAMES
        self.assertEqual(self.scan(), 1)
        arrows = self.b.arrows
        self.assertTrue(arrows[frames[1]].shown)
        self.assertFalse(frames[1].lit(frames[1]), "the legs slot is taken: no blue border")
        self.assertIsNone(arrows[frames[2]])

    def test_unknown_items_are_not_marked_until_the_client_describes_them(self):
        self.lua.execute('ITEMS[10].uncached=true;Evertally.Gear.cache={};BlizzardButton(1)')
        frames = self.lua.globals().FRAMES
        self.scan(); self.assertFalse(frames[1].lit(frames[1]))
        self.lua.execute('ITEMS[10].uncached=nil;Evertally.Dispatch("GET_ITEM_INFO_RECEIVED",10,true)')
        self.scan(); self.assertTrue(frames[1].lit(frames[1]))


if __name__ == "__main__":
    unittest.main()
