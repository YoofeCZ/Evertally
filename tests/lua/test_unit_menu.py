"""Player context menus: captured names, actions, supported hooks and restriction guards."""
import unittest
from test_addon import runtime, MOCK_UI_LUA

MENU = r'''
FIRST,SURNAME="Vexara","Nightcurse"; CURRENT_GUID="Player-1"; COMBAT=false
UnitName=function() return FIRST,SURNAME end
GetRealmName=function() return "Actual Realm" end
UnitIsPlayer=function() return true end
UnitIsUnit=function() return false end
UnitGUID=function() return CURRENT_GUID end
InCombatLockdown=function() return COMBAT end
function description(text,callback)
    local d={text=text,callback=callback,children={}}
    function d:CreateButton(text,callback) local child=description(text,callback);self.children[#self.children+1]=child;return child end
    function d:CreateDivider() self.children[#self.children+1]=description("divider") end
    return d
end
ROOT=description("root")
HOOKS={};HOOK_COUNT=0
Menu={ModifyMenu=function(tag,callback) HOOKS[tag]=callback;HOOK_COUNT=HOOK_COUNT+1 end}
'''


class UnitMenuTests(unittest.TestCase):
    def setUp(self):
        self.lua,self.a=runtime()
        self.lua.execute(MOCK_UI_LUA)
        self.lua.execute(MENU)

    def menu(self):
        self.a.AddPlayerUnitMenu(None,self.lua.globals().ROOT,self.lua.table(unit="target"))
        return self.lua.globals().ROOT.children[2]

    def test_supported_unit_menus_are_registered_once(self):
        self.a.RegisterPlayerUnitMenus();self.a.RegisterPlayerUnitMenus()
        self.assertEqual(self.lua.globals().HOOK_COUNT,6)
        self.assertIsNotNone(self.lua.globals().HOOKS.MENU_UNIT_PLAYER)

    def test_marks_and_inspect_keep_the_clicked_players_full_name(self):
        self.lua.execute('Evertally.RequestInspect=function(name) INSPECT=name;return true end; Evertally.NavigateByName=function(name) NAV=name;return true end')
        menu=self.menu()
        self.lua.execute('FIRST="Someone";SURNAME="Else";CURRENT_GUID="Player-2"')
        menu.children[1].children[3].callback()
        self.assertEqual(self.a.GetMark("Vexara Nightcurse"),3)
        self.assertIsNone(self.a.GetMark("Someone Else"))
        menu.children[2].callback()
        menu.children[3].callback()
        self.assertEqual(self.lua.globals().NAV,"Vexara Nightcurse")
        self.assertEqual(self.lua.globals().INSPECT,"Vexara Nightcurse")

    def test_combat_and_hidden_unit_identity_leave_blizzard_menu_untouched(self):
        self.lua.execute('COMBAT=true')
        self.a.AddPlayerUnitMenu(None,self.lua.globals().ROOT,self.lua.table(unit="target"))
        self.assertEqual(len(self.lua.globals().ROOT.children),0)
        self.lua.execute('COMBAT=false;C_Secrets={ShouldUnitIdentityBeSecret=function() return true end}')
        self.a.AddPlayerUnitMenu(None,self.lua.globals().ROOT,self.lua.table(unit="target"))
        self.assertEqual(len(self.lua.globals().ROOT.children),0)

    def test_settings_action_opens_nameplate_section_and_self_has_no_inspect(self):
        self.lua.execute('UnitIsUnit=function() return true end')
        menu=self.menu()
        self.assertEqual(len(menu.children),2)
        menu.children[2].callback()
        self.assertEqual(self.a.settingsPage.selectedSection,5)
        self.assertIsNone(self.a.lastUIError)


if __name__ == "__main__":
    unittest.main()
