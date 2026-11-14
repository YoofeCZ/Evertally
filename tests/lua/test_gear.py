"""Behavioural checks for the own gear scorer and preview-authorised vendor actions."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_addon import runtime, MOCK_UI_LUA, ADDON


def setup_runtime():
    lua, a = runtime()
    if a.Gear is None:
        for name in ("Gear.lua", "GearUI.lua"):
            fn = lua.eval("loadstring")((ADDON / name).read_text(encoding="utf8"), name)
            if isinstance(fn, tuple):
                raise AssertionError(fn)
            fn("Evertally", a)
    lua.execute('''
    CLASS="SHAMAN"; LEVEL=20; ITEMS={}; EQUIPPED={}; BAGS={}; MONEY=1000; SALES={}; EQUIPS={}; NOTICES={}; QUESTCHOICES={}; CURSOR=false
    UnitClass=function() return CLASS,CLASS,7 end
    UnitLevel=function() return LEVEL end
    GetInventoryItemLink=function(_,slot) local id=EQUIPPED[slot];return id and "item:"..id end
    GetItemInfo=function(ref)
      local id=type(ref)=="number" and ref or tonumber(tostring(ref):match("item:(%d+)"));local x=ITEMS[id]
      if not x or x.uncached then return end
      return x.name or "Item "..id,"item:"..id,x.quality or 0,x.ilevel or 1,x.level or 0,"Armor","Armor",1,x.loc or "",132540,x.price or 10,x.class or 4,x.sub or 1
    end
    GetItemStats=function(ref) local x=ITEMS[tonumber(tostring(ref):match("item:(%d+)"))];return x and x.stats end
    IsEquippableItem=function(ref)local x=ITEMS[tonumber(tostring(ref):match("item:(%d+)"))];return x and x.loc and x.loc~="" or false end
    GetMoney=function()return MONEY end
    CursorHasItem=function()return CURSOR end
    NUM_BAG_SLOTS=0
    C_Container={
      GetContainerNumSlots=function()return #BAGS end,
      GetContainerItemInfo=function(_,slot)
        local x=BAGS[slot];if not x or x.gone then return end
        return {itemID=x.id,hyperlink="item:"..x.id,stackCount=x.count or 1,isLocked=x.locked==true,isQuestItem=x.quest,hasNoValue=x.noValue}
      end,
      GetContainerItemQuestInfo=function(_,slot)local x=BAGS[slot];return x and {isQuestItem=x.quest}end,
      UseContainerItem=function(bag,slot) SALES[#SALES+1]={bag,slot} end
    }
    EquipItemByName=function(link,slot)EQUIPS[#EQUIPS+1]={link,slot}end
    GetNumQuestChoices=function()return #QUESTCHOICES end
    GetQuestItemLink=function(_,index)return QUESTCHOICES[index] and "item:"..QUESTCHOICES[index] end
    GetQuestItemInfo=function(_,index)return "Reward",132540,QUESTCOUNTS and QUESTCOUNTS[index] or 1 end
    Evertally.Print=function(text)NOTICES[#NOTICES+1]=text end
    Evertally.Gear.cache={};Evertally.Gear.generation=Evertally.Gear.generation+1
    function Item(id,values) ITEMS[id]=values end
    ''')
    return lua, a, a.Gear


class GearTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a, self.g = setup_runtime()

    def runlua(self, text):
        self.lua.execute(text)

    def test_own_class_profiles_and_manual_override(self):
        self.assertEqual(self.g.Profile().name, "Enhancement")
        self.assertTrue(self.g.SetProfile(3))
        self.assertEqual(self.g.Profile().name, "Restoration")
        self.assertFalse(self.g.Profile().automatic)
        self.assertFalse(self.g.SetProfile(9))
        self.g.SetProfile(0)
        self.runlua('Evertally.TalentTrees=function()return {{spent=15},{spent=2},{spent=0}}end;Evertally.Dispatch("PLAYER_TALENT_UPDATE")')
        self.assertEqual(self.g.Profile().name, "Elemental")

    def test_stats_are_weighted_and_item_level_is_not_score(self):
        self.runlua('Item(1,{loc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=3}});Item(2,{loc="INVTYPE_CHEST",ilevel=900,stats={ITEM_MOD_STRENGTH_SHORT=1}});EQUIPPED[5]=1')
        comparison = self.g.Compare("item:2")
        self.assertEqual(comparison.status, "downgrade")
        self.assertAlmostEqual(comparison.delta, -3.6)
        self.assertEqual(comparison.parts[1].stat, "strength")

    def test_get_item_info_price_and_class_are_not_truncated(self):
        self.runlua('Item(1,{loc="INVTYPE_CHEST",price=12345,class=4,sub=3,stats={}})')
        item = self.g.Item(1)
        self.assertEqual(item.vendorPrice, 12345)
        self.assertEqual(item.classId, 4)
        self.assertEqual(item.subclassId, 3)
        self.assertEqual(item.icon, 132540)

    def test_ring_compares_against_weaker_slot(self):
        self.runlua('Item(1,{loc="INVTYPE_FINGER",stats={ITEM_MOD_STRENGTH_SHORT=5}});Item(2,{loc="INVTYPE_FINGER",stats={ITEM_MOD_STRENGTH_SHORT=1}});Item(3,{loc="INVTYPE_FINGER",stats={ITEM_MOD_STRENGTH_SHORT=3}});EQUIPPED[11]=1;EQUIPPED[12]=2')
        comparison = self.g.Compare(3)
        self.assertEqual(comparison.status, "upgrade")
        self.assertEqual(comparison.slot, 12)
        self.assertAlmostEqual(comparison.delta, 3.6)

    def test_two_hand_compares_both_hands(self):
        self.runlua('Item(1,{class=2,sub=0,loc="INVTYPE_WEAPON",stats={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=4}});Item(2,{loc="INVTYPE_SHIELD",sub=6,stats={ITEM_MOD_STRENGTH_SHORT=8}});Item(3,{class=2,sub=1,loc="INVTYPE_2HWEAPON",stats={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=5}});EQUIPPED[16]=1;EQUIPPED[17]=2')
        result = self.g.Compare(3)
        self.assertEqual(result.status, "downgrade")
        self.assertAlmostEqual(result.baseline, 42.4)

    def test_one_hand_can_replace_weaker_offhand_only_after_dual_wield_is_known(self):
        self.runlua('''
        Item(1,{class=2,sub=0,loc="INVTYPE_WEAPON",stats={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=6}})
        Item(2,{class=2,sub=0,loc="INVTYPE_WEAPON",stats={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=1}})
        Item(3,{class=2,sub=0,loc="INVTYPE_WEAPON",stats={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=3}})
        EQUIPPED[16]=1;EQUIPPED[17]=2
        ''')
        self.assertEqual(self.g.Compare(3).status, "downgrade")
        self.runlua('IsPlayerSpell=function(id)return id==674 end')
        comparison = self.g.Compare(3)
        self.assertEqual(comparison.status, "upgrade")
        self.assertEqual(comparison.slot, 17)

    def test_unknown_info_or_weapon_dps_never_becomes_upgrade_or_zero(self):
        self.runlua('Item(1,{uncached=true});Item(2,{class=2,sub=0,loc="INVTYPE_WEAPON",stats={ITEM_MOD_STRENGTH_SHORT=50}})')
        self.assertEqual(self.g.Compare(1).status, "unknown")
        self.assertIsNone(self.g.Compare(1).score)
        self.assertEqual(self.g.Compare(2).status, "unknown")

    def test_level_armor_shield_and_weapon_class_restrictions(self):
        self.runlua('Item(1,{loc="INVTYPE_CHEST",level=30,stats={}});Item(2,{loc="INVTYPE_CHEST",sub=3,stats={}});Item(3,{class=2,sub=7,loc="INVTYPE_WEAPON",stats={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=99}})')
        for item in (1, 2, 3):
            self.assertEqual(self.g.Compare(item).status, "unusable")
        self.runlua('CLASS="PRIEST";Item(4,{loc="INVTYPE_SHIELD",sub=6,stats={}})')
        self.assertEqual(self.g.Compare(4).status, "unusable")

    def test_keep_list_persists_in_own_settings(self):
        self.g.SetKept(123, True)
        self.assertTrue(self.g.Kept("item:123"))
        self.assertTrue(self.a.db.settings.gear.keep[123])
        self.g.SetKept(123, False)
        self.assertFalse(self.g.Kept(123))

    def test_junk_preview_excludes_quest_locked_kept_unknown_and_useful_grey(self):
        self.runlua('''
        Item(1,{price=2,stats={}});Item(2,{price=3,stats={}});Item(3,{price=5,stats={}});Item(4,{price=7,stats={}})
        Item(5,{loc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=5}});Item(6,{uncached=true})
        Item(7,{quality=1,stats={}});Item(8,{loc="INVTYPE_CHEST"})
        BAGS={{id=1,count=3},{id=2,quest=true},{id=3,locked=true},{id=4},{id=5},{id=6},{id=7},{id=8}}
        Evertally.Gear.SetKept(4,true)
        ''')
        preview = self.g.PreviewJunk()
        self.assertEqual(len(preview["items"]), 1)
        self.assertEqual(preview["items"][1].id, 1)
        self.assertEqual(preview.value, 6)

    def test_no_merchant_no_confirm_and_no_automatic_sale(self):
        self.runlua('Item(1,{price=2,stats={}});BAGS={{id=1}}')
        preview = self.g.PreviewJunk()
        self.assertEqual(len(self.lua.globals().SALES), 0)
        ok, reason = self.g.BeginSale(preview)
        self.assertFalse(ok)
        self.assertEqual(reason, "gearMerchant")

    def test_sale_rechecks_exact_original_slot_and_never_sells_replacement(self):
        self.runlua('Item(1,{price=2,stats={}});Item(2,{price=50,stats={}});BAGS={{id=1}};Evertally.Dispatch("MERCHANT_SHOW")')
        plan = self.g.PreviewJunk()
        self.runlua('BAGS[1]={id=2}')
        self.g.BeginSale(plan)
        self.assertEqual(len(self.lua.globals().SALES), 0)
        self.assertEqual(self.g.sale.skipped, 1)

    def test_confirm_is_requested_not_success_until_bag_and_money_acknowledge(self):
        self.runlua('Item(1,{price=2,stats={}});BAGS={{id=1,count=3}};Evertally.Dispatch("MERCHANT_SHOW")')
        plan = self.g.PreviewJunk()
        self.assertTrue(self.g.BeginSale(plan)[0])
        self.assertEqual(self.g.sale.confirmed, 0)
        self.assertEqual(self.g.sale.attempted, 1)
        self.g.StepSale()
        self.assertEqual(len(self.lua.globals().SALES), 1)
        self.runlua('BAGS[1].gone=true;MONEY=MONEY+6;Evertally.Dispatch("BAG_UPDATE_DELAYED")')
        self.assertEqual(self.g.sale.confirmed, 1)
        self.assertEqual(self.g.sale.value, 6)
        self.assertFalse(self.g.sale.active)
        self.assertFalse(self.g.BeginSale(plan)[0])

    def test_sale_stops_if_cursor_combat_or_merchant_changes(self):
        for event in ("cursor", "combat", "close"):
            with self.subTest(event=event):
                self.setUp()
                self.runlua('Item(1,{price=2,stats={}});BAGS={{id=1}};Evertally.Dispatch("MERCHANT_SHOW")')
                plan = self.g.PreviewJunk()
                if event == "cursor":
                    self.runlua('CURSOR=true')
                elif event == "combat":
                    self.runlua('INCOMBAT=true')
                else:
                    self.a.Dispatch("MERCHANT_CLOSED")
                self.assertFalse(self.g.BeginSale(plan)[0])
                self.assertEqual(len(self.lua.globals().SALES), 0)

    def test_active_batch_does_not_continue_after_merchant_closed(self):
        self.runlua('Item(1,{price=2,stats={}});BAGS={{id=1},{id=1}};Evertally.Dispatch("MERCHANT_SHOW")')
        self.g.BeginSale(self.g.PreviewJunk())
        self.a.Dispatch("MERCHANT_CLOSED")
        self.runlua('BAGS[1].gone=true;MONEY=MONEY+2;Evertally.Dispatch("BAG_UPDATE_DELAYED")')
        self.assertEqual(len(self.lua.globals().SALES), 1)
        self.assertFalse(self.g.sale.active)

    def test_pcalls_without_acknowledgement_are_not_reported_as_sales(self):
        self.runlua('Item(1,{price=2,stats={}});BAGS={{id=1}};Evertally.Dispatch("MERCHANT_SHOW")')
        self.g.BeginSale(self.g.PreviewJunk())
        for _ in range(3):
            self.g.StepSale(True)
        self.assertEqual(self.g.sale.confirmed, 0)
        self.assertEqual(self.g.sale.reason, "unconfirmed")
        self.assertFalse(self.g.sale.active)

    def test_moving_stack_with_unrelated_income_is_not_a_confirmed_sale(self):
        self.runlua('Item(1,{price=2,stats={}});BAGS={{id=1,count=3},{id=1,gone=true}};Evertally.Dispatch("MERCHANT_SHOW")')
        self.g.BeginSale(self.g.PreviewJunk())
        self.runlua('BAGS[1].gone=true;BAGS[2]={id=1,count=3};MONEY=MONEY+6;Evertally.Dispatch("BAG_UPDATE_DELAYED")')
        self.assertEqual(self.g.sale.confirmed, 0)
        self.assertEqual(len(self.lua.globals().SALES), 1)
        for _ in range(3):
            self.g.StepSale(True)
        self.assertFalse(self.g.sale.active)
        self.assertEqual(self.g.sale.reason, "unconfirmed")

    def test_secret_or_invalid_stack_count_never_enters_sale_preview(self):
        self.runlua('''
        Item(1,{price=2,stats={}});BAGS={{id=1}}
        C_Container.GetContainerItemInfo=function()return {itemID=1,hyperlink="item:1",stackCount=SECRET,isLocked=false}end
        ''')
        self.assertEqual(len(self.g.PreviewJunk()["items"]), 0)
        self.runlua('C_Container.GetContainerItemInfo=function()return {itemID=1,hyperlink="item:1",stackCount=1.5,isLocked=false}end')
        self.assertEqual(len(self.g.PreviewJunk()["items"]), 0)

    def test_unlearned_weapon_is_not_recommended_when_client_explicitly_refuses_it(self):
        self.runlua('''
        CLASS="WARRIOR";Item(1,{class=2,sub=7,loc="INVTYPE_WEAPON",stats={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=50}})
        IsUsableItem=function()return false,false end
        ''')
        self.assertEqual(self.g.Compare(1).status, "unusable")

    def test_explicitly_hidden_merchant_overrides_old_open_event(self):
        self.runlua('''
        Item(1,{price=2,stats={}});BAGS={{id=1}};Evertally.Dispatch("MERCHANT_SHOW")
        MerchantFrame={IsShown=function()return false end}
        ''')
        self.assertFalse(self.g.BeginSale(self.g.PreviewJunk())[0])
        self.assertEqual(len(self.lua.globals().SALES), 0)

    def test_vendor_reward_uses_entire_stack_value_and_unknown_count_waits(self):
        self.runlua('Item(1,{price=3,stats={}});Item(2,{price=10,stats={}});QUESTCHOICES={1,2};QUESTCOUNTS={5,1}')
        _, best, reason = self.g.QuestRewards()
        self.assertEqual(best, 1)
        self.assertEqual(reason, "vendor")
        self.runlua('GetQuestItemInfo=function()return "Reward",132540,SECRET end')
        _, best, reason = self.g.QuestRewards()
        self.assertIsNone(best)
        self.assertEqual(reason, "loading")

    def test_equipping_is_a_user_action_and_refuses_changed_slots_or_combat(self):
        self.runlua('Item(1,{loc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=5}});BAGS={{id=1}}')
        entry = self.g.Bags()[1]
        self.assertTrue(self.g.Equip(entry)[0])
        self.assertEqual(len(self.lua.globals().EQUIPS), 1)
        self.runlua('INCOMBAT=true')
        self.assertFalse(self.g.Equip(entry)[0])
        self.runlua('INCOMBAT=false;BAGS[1].gone=true')
        self.assertFalse(self.g.Equip(entry)[0])
        self.assertEqual(len(self.lua.globals().EQUIPS), 1)

    def test_tooltip_is_idempotent_and_does_not_replace_blizzard_handlers(self):
        self.runlua('''
        Item(1,{loc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=5}})
        TIP={lines={},GetItem=function()return "Thing","item:1"end,AddLine=function(t,x)t.lines[#t.lines+1]=x end,Show=function()end}
        ''')
        tooltip = self.lua.globals().TIP
        self.assertTrue(self.g.AppendTooltip(tooltip))
        self.assertFalse(self.g.AppendTooltip(tooltip))
        self.assertEqual(len(tooltip.lines), 2)
        self.g.SetOption("tooltip", False)
        self.runlua('TIP.evertallyGearLink=nil')
        self.assertFalse(self.g.AppendTooltip(tooltip))

    def test_best_quest_reward_is_an_actual_role_upgrade_and_uncached_waits(self):
        self.runlua('Item(1,{loc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=2}});Item(2,{loc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=5}});QUESTCHOICES={1,2}')
        entries, best, reason = self.g.QuestRewards()
        self.assertEqual(best, 2)
        self.assertEqual(reason, "upgrade")
        self.runlua('Item(3,{uncached=true});QUESTCHOICES={2,3}')
        self.assertEqual(self.g.QuestRewards()[2], "loading")
        self.assertIsNone(self.g.QuestRewards()[1])

    def test_own_loot_only_and_feature_switch(self):
        self.runlua('Item(1,{loc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=5}})')
        self.a.Dispatch("CHAT_MSG_LOOT", "Other receives loot: |Hitem:1|h[Thing]|h.")
        self.assertEqual(len(self.lua.globals().NOTICES), 0)
        self.a.Dispatch("CHAT_MSG_LOOT", "You receive loot: |Hitem:1|h[Thing]|h.")
        self.assertEqual(len(self.lua.globals().NOTICES), 1)
        self.g.SetOption("loot", False)
        self.assertFalse(self.g.LootNotice("item:1"))

    def test_real_reward_button_mark_is_removed_when_option_disabled(self):
        self.lua.execute(MOCK_UI_LUA)
        self.runlua('''
        Item(1,{loc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=2}})
        Item(2,{loc="INVTYPE_CHEST",stats={ITEM_MOD_STRENGTH_SHORT=5}})
        QUESTCHOICES={1,2};QuestInfoRewardsFrame={RewardButtons={object(),object()}}
        Evertally.Dispatch("QUEST_COMPLETE")
        ''')
        buttons = self.lua.globals().QuestInfoRewardsFrame.RewardButtons
        self.assertIsNone(buttons[1].evertallyGearBadge)
        self.assertTrue(buttons[2].evertallyGearBadge.shown)
        self.assertIn("Best upgrade", buttons[2].evertallyGearBadge.text)
        self.g.SetOption("rewards", False)
        self.assertFalse(buttons[2].evertallyGearBadge.shown)

    def test_changed_or_newly_protected_stack_during_batch_is_skipped(self):
        self.runlua('Item(1,{price=2,stats={}});Item(2,{price=5,stats={}});BAGS={{id=1},{id=2}};Evertally.Dispatch("MERCHANT_SHOW")')
        self.g.BeginSale(self.g.PreviewJunk())
        self.g.SetKept(2, True)
        self.runlua('BAGS[1].gone=true;MONEY=MONEY+2;Evertally.Dispatch("BAG_UPDATE_DELAYED")')
        self.assertEqual(len(self.lua.globals().SALES), 1)
        self.assertEqual(self.g.sale.confirmed, 1)
        self.assertEqual(self.g.sale.skipped, 1)

    def test_tooltip_hook_uses_item_postprocessor_without_global_replacement(self):
        self.runlua('''
        HOOKED={};GameTooltip={HookScript=function(_,key,fn)HOOKED[key]=fn end}
        Enum={TooltipDataType={Item=1}}
        TooltipDataProcessor={AddTooltipPostCall=function(kind,fn)HOOKED.processor=fn;HOOKED.kind=kind end}
        Evertally.Dispatch("PLAYER_LOGIN")
        ''')
        self.assertEqual(self.lua.globals().HOOKED.kind, 1)
        self.assertIsNotNone(self.lua.globals().HOOKED.processor)
        self.assertIsNotNone(self.lua.globals().HOOKED.OnTooltipCleared)

    def test_secret_fields_are_not_reintroduced_by_fallbacks(self):
        self.runlua('GetItemInfo=function()return SECRET end')
        self.assertFalse(self.g.Item(1).known)

    def test_one_hand_comparison_keeps_mainhand_option_when_current_weapon_is_two_handed(self):
        self.runlua('''
        CLASS="WARRIOR";IsPlayerSpell=function(id)return id==674 end
        Item(1,{class=2,sub=8,loc="INVTYPE_2HWEAPON",stats={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=5}})
        Item(2,{class=2,sub=7,loc="INVTYPE_WEAPON",stats={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=8}})
        EQUIPPED[16]=1
        ''')
        comparison = self.g.Compare(2)
        self.assertEqual(comparison.slot, 16)
        self.assertEqual(comparison.status, 'upgrade')

    def test_page_build_and_refresh_reuses_widgets_at_minimum_width(self):
        self.lua.execute(MOCK_UI_LUA)
        page = self.lua.globals().object(None)
        page.SetSize(page, 450, 410)
        self.a.BuildGearPage(page, self.a.UIKit())
        page.Refresh()
        before = len(self.lua.globals().MOCKBUTTONS)
        for _ in range(3):
            page.Refresh()
        self.assertEqual(len(self.lua.globals().MOCKBUTTONS), before)
        self.assertIsNotNone(page.document.spec.title)


if __name__ == "__main__":
    unittest.main()
