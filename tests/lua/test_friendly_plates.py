"""Friendly plate presentation and lifecycle using observable frame/texture state, not a running game."""
import unittest
from test_addon import runtime


FIXTURE = r'''
FRAMES={}; AURA_CALLS=0; UNIT_NAME="Friend"; FRIENDLY=true; FORBIDDEN=false; LOCKNAME=false
EXISTS=true; SELF=false; PLAYER=true; CASTING=false; CHANNEL=false
function region(parent)
    local r={parent=parent,shown=true,alpha=1,text="",font={"NativeFont",12,"OUTLINE"},color={0.2,0.8,0.3}}
    function r:IsForbidden() return false end
    function r:IsVisible() return self.shown end
    function r:IsShown() return self.shown end
    function r:Show() self.shown=true end
    function r:Hide() self.shown=false end
    function r:SetShown(on) self.shown=on and true or false end
    function r:GetAlpha() return self.alpha end
    function r:SetAlpha(alpha) if self.native and LOCKNAME then error("protected name") end self.alpha=alpha end
    function r:SetPoint(...) self.point={...} end
    function r:ClearAllPoints() self.point=nil end
    function r:SetAllPoints() end
    function r:SetSize(w,h) self.width=w;self.height=h end
    function r:SetWidth(w) self.width=w end
    function r:SetHeight(h) self.height=h end
    function r:SetScale(v) self.scale=v end
    function r:SetText(v) self.text=v end
    function r:GetText() return self.text end
    function r:GetStringWidth() return #self.text*7 end
    function r:GetFont() return unpack(self.font) end
    function r:SetFont(...) self.font={...} end
    function r:SetShadowColor(...) self.shadow={...} end
    function r:SetShadowOffset(...) self.shadowOffset={...} end
    function r:GetTextColor() return unpack(self.color) end
    function r:SetTextColor(...) self.color={...} end
    function r:SetWordWrap() end
    function r:SetJustifyH() end
    function r:SetTexture(v) self.texture=v end
    function r:SetTexCoord(...) self.crop={...} end
    function r:SetColorTexture(...) self.fill={...} end
    function r:EnableMouse(v) self.mouse=v end
    function r:SetFrameStrata() end
    function r:SetFrameLevel() end
    function r:SetStatusBarTexture(v) self.statusTexture=v end
    function r:SetStatusBarColor(...) self.statusColor={...} end
    function r:SetMinMaxValues(lo,hi) self.lo=lo;self.hi=hi end
    function r:SetValue(v) self.value=v end
    function r:CreateTexture() return region(self) end
    function r:CreateFontString() return region(self) end
    return r
end
function CreateFrame(_,_,parent) local f=region(parent);FRAMES[#FRAMES+1]=f;return f end
NAME=region(); NAME.native=true;NAME.alpha=0.75
PLATE=region();PLATE.UnitFrame={name=NAME};PLATE.namePlateUnitToken="nameplate1"
function PLATE:IsForbidden() return FORBIDDEN end
PLATES={PLATE}
C_NamePlate={GetNamePlates=function() return PLATES end}
C_CVar={GetCVar=function() return "1" end}
GameFontNormal={GetFont=function() return "GameFont",12,"" end}
UnitExists=function(u) return u=="nameplate1" and EXISTS end
UnitIsPlayer=function(u) return u=="nameplate1" and PLAYER end
UnitIsUnit=function(u,v) return v=="player" and SELF end
UnitIsFriend=function() return FRIENDLY end
UnitCanAttack=function() return not FRIENDLY end
UnitName=function() return UNIT_NAME,UNIT_SURNAME end
UnitHealth=function() return 60 end
UnitHealthMax=function() return 100 end
UnitCastingInfo=function() if CASTING then return "Healing Touch",nil,135913,98000,104000 end end
UnitChannelInfo=function() if CHANNEL then return "Channel",nil,135753,98000,104000 end end
BUFFS={{name="Fortitude",icon=135987,applications=3,duration=30,expirationTime=120}}
DEBUFFS={{name="Poison",icon=132273,applications=1,duration=10,expirationTime=105}}
C_UnitAuras={GetAuraDataByIndex=function(u,i,filter) AURA_CALLS=AURA_CALLS+1;return (filter=="HELPFUL" and BUFFS or DEBUFFS)[i] end}
'''


class FriendlyPlateTests(unittest.TestCase):
    def setUp(self):
        self.lua, self.a = runtime()
        self.lua.execute(FIXTURE)

    def render(self):
        self.a.RefreshFriendlyPlates()
        return self.lua.eval('(function() for _,f in ipairs(FRAMES) do if f.parent==PLATE then return f end end end)()')

    def test_plain_name_defaults_use_owned_frame_without_changing_native_font(self):
        f = self.render()
        self.assertTrue(f.shown)
        self.assertEqual(f.name.text, "Friend")
        self.assertEqual(f.name.font[1], "GameFont")
        self.assertEqual(f.name.font[2], 15)
        self.assertEqual(f.name.font[3], "")
        self.assertEqual(self.lua.globals().NAME.alpha, 0)
        self.assertEqual(self.lua.globals().NAME.font[1], "NativeFont")
        self.assertFalse(f.health.shown)
        self.assertFalse(f.cast.shown)
        self.assertEqual(self.lua.globals().AURA_CALLS, 0)
        self.assertFalse(f.mouse)

    def test_disable_and_removal_restore_exact_alpha_without_ghost_frame(self):
        f = self.render()
        self.a.db.settings.plateGameLook = False
        self.a.RefreshFriendlyPlates()
        self.assertFalse(f.shown)
        self.assertEqual(self.lua.globals().NAME.alpha, 0.75)
        self.a.db.settings.plateGameLook = True
        self.render()
        self.a.Dispatch("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        self.a.RefreshFriendlyPlates()  # even if the client list has not yet removed its old entry
        self.assertFalse(f.shown)
        self.assertEqual(self.lua.globals().NAME.alpha, 0.75)
        self.a.Dispatch("NAME_PLATE_UNIT_ADDED", "nameplate1")
        self.assertTrue(f.shown)

    def test_recycled_plate_replaces_the_name_and_drops_previous_icons(self):
        self.a.SetMark("Friend", 3)
        self.a.NoteEvertallyUser("Friend")
        f = self.render()
        self.assertTrue(f.mark.shown)
        self.assertTrue(f.logo.shown)
        self.lua.execute('UNIT_NAME="SomebodyElse"')
        self.render()
        self.assertEqual(f.name.text, "SomebodyElse")
        self.assertFalse(f.mark.shown)
        self.assertFalse(f.logo.shown)
        self.lua.execute('FRIENDLY=false')
        self.render()
        self.assertFalse(f.shown)
        self.assertEqual(self.lua.globals().NAME.alpha, 0.75)

    def test_individual_visibility_and_sizes_are_independent(self):
        s = self.a.db.settings
        self.a.SetMark("Friend", "f135940")
        self.a.NoteEvertallyUser("Friend")
        s.plateFontSize, s.markSize, s.plateLogoSize, s.plateScale = 23, 18, 21, 130
        f = self.render()
        self.assertEqual((f.name.font[2], f.mark.width, f.logo.width, f.scale), (23, 18, 21, 1.3))
        s.plateName, s.plateMarks = False, False
        self.a.FriendlyPlatesChanged()
        self.assertEqual(f.name.text, "")
        self.assertFalse(f.mark.shown)
        self.assertTrue(f.logo.shown)
        s.markUsers = False
        self.a.FriendlyPlatesChanged()
        self.assertFalse(f.logo.shown)

    def test_marks_renderer_does_not_draw_a_second_icon_set_on_owned_nameplate(self):
        self.a.SetMark("Friend", 3)
        f = self.render()
        self.a.MarksRefresh()
        self.assertTrue(f.mark.shown)
        self.assertEqual(self.lua.eval('#FRAMES'), 3)  # owned plate + health bar + cast bar, no old icon holder

    def test_master_off_disables_friendly_fallback_icons_and_restores_native_name(self):
        self.a.SetMark("Friend", 3)
        self.a.NoteEvertallyUser("Friend")
        f = self.render()
        self.a.db.settings.plateGameLook = False
        self.a.MarksRefresh()
        self.assertFalse(f.shown)
        self.assertEqual(self.lua.globals().NAME.alpha, 0.75)
        self.assertEqual(self.lua.eval('#FRAMES'), 3, "no fallback icon holder after the feature is disabled")

    def test_forever_surname_is_displayed_once_and_not_used_as_realm(self):
        self.lua.execute('UNIT_SURNAME="Nightcurse"; GetRealmName=function() return "Actual Realm" end')
        f = self.render()
        self.assertEqual(f.name.text, "Friend Nightcurse")
        self.assertEqual(self.a.UnitPlayerName("nameplate1"), ("Friend Nightcurse", "Actual Realm"))
        self.lua.execute('GetUnitName=function() return "Friend Nightcurse" end')
        self.render()
        self.assertEqual(f.name.text, "Friend Nightcurse")

    def test_font_outline_shadow_and_offsets_update_world_renderer(self):
        s = self.a.db.settings
        self.a.SetMark("Friend", 8)
        self.a.NoteEvertallyUser("Friend")
        f = self.render()
        s.plateFont, s.plateOutline, s.plateShadow = "arial", "outline", False
        s.plateOffsetY, s.plateMarkY, s.plateLogoX = 22, -9, 12
        self.a.FriendlyPlatesChanged()
        self.assertEqual(f.name.font[1], "Fonts\\ARIALN.TTF")
        self.assertEqual(f.name.font[3], "OUTLINE")
        self.assertEqual((f.name.shadowOffset[1],f.name.shadowOffset[2]), (0,0))
        self.assertEqual(f.point[5], 22)
        self.assertEqual(f.mark.point[5], -9)

    def test_preview_reuses_world_layout_and_never_mutes_any_native_name(self):
        self.lua.execute('PARENT=region()')
        state = self.a.CreateFriendlyPlatePreview(self.lua.globals().PARENT)
        self.a.db.settings.plateFont = "morpheus"
        self.a.db.settings.plateBuffs = True
        state.Update()
        self.assertEqual(state.frame.name.font[1], "Fonts\\MORPHEUS.TTF")
        self.assertTrue(state.frame.mark.shown)
        self.assertEqual(len(state.buffs), 1)
        self.assertEqual(self.lua.globals().NAME.alpha, 0.75)

    def test_distance_uses_both_player_and_global_limits_and_reads_client_clamp(self):
        self.lua.execute('''
            RANGE={nameplateMaxDistance="45",nameplatePlayerMaxDistance="40"}
            C_CVar={GetCVar=function(k) return RANGE[k] end,SetCVar=function(k,v) RANGE[k]=tostring(math.min(60,tonumber(v))) end}
            InCombatLockdown=function() return false end
        ''')
        self.a.SetFriendlyPlateOption("plateDistance", 100)
        self.assertEqual(self.a.db.settings.plateDistance, 60)
        self.assertEqual(self.lua.globals().RANGE.nameplateMaxDistance, "60")
        self.assertEqual(self.lua.globals().RANGE.nameplatePlayerMaxDistance, "60")
        self.lua.execute('InCombatLockdown=function() return true end')
        self.a.SetFriendlyPlateOption("plateDistance", 30)
        self.assertEqual(self.lua.globals().RANGE.nameplatePlayerMaxDistance, "60")

    def test_hidden_self_enemy_npc_and_forbidden_plates_are_not_replaced(self):
        for flag in ["FORBIDDEN", "SELF"]:
            with self.subTest(flag=flag):
                self.lua.execute(f"{flag}=true")
                self.render()
                self.assertEqual(self.lua.globals().NAME.alpha, 0.75)
                self.lua.execute(f"{flag}=false")
        for flag in ["FRIENDLY", "PLAYER", "EXISTS"]:
            with self.subTest(flag=flag):
                self.lua.execute(f"{flag}=false")
                self.render()
                self.assertEqual(self.lua.globals().NAME.alpha, 0.75)
                self.lua.execute(f"{flag}=true")
        self.lua.execute('LOCKNAME=true')
        f=self.render()
        self.assertFalse(f.shown)
        self.assertEqual(self.lua.globals().NAME.alpha, 0.75)

    def test_activation_applies_range_and_preserves_later_explicit_shorter_choice(self):
        self.lua.execute('''CVARS={nameplateShowFriendlyPlayers="0",nameplateShowOnlyNameForFriendlyPlayerUnits="0",nameplateMaxDistance="45",nameplatePlayerMaxDistance="40"}
            C_CVar={GetCVar=function(k) return CVARS[k] end,SetCVar=function(k,v) CVARS[k]=v end}''')
        self.a.db.settings.plateDistance=40
        self.a.db.settings.plateGameLook=False
        self.assertTrue(self.a.UseFriendlyPlateProvider("evertally"))
        self.assertEqual(self.lua.globals().CVARS.nameplatePlayerMaxDistance,"60")
        self.a.SetFriendlyPlateRange(25)
        self.a.Dispatch("PLAYER_ENTERING_WORLD")
        self.assertEqual(self.lua.globals().CVARS.nameplatePlayerMaxDistance,"25")

    def test_aura_rows_limits_sizes_stacks_and_disabled_scan(self):
        s=self.a.db.settings
        s.plateBuffs,s.plateDebuffs,s.plateAuraSize,s.plateAuraLimit=True,True,28,1
        self.lua.execute('BUFFS[2]={name="Other buff",icon=135913,applications=1}')
        self.render()
        self.assertEqual(len(self.a.ReadFriendlyAuras("nameplate1", "HELPFUL", 1)), 1)
        self.assertTrue(self.lua.eval('FRAMES[4].shown and FRAMES[5].shown'))
        self.assertEqual(self.lua.eval('FRAMES[4].width'),28)
        self.assertEqual(self.lua.eval('FRAMES[4].count.text'),"3")
        self.assertEqual(self.lua.eval('FRAMES[4].time.text'),"20")
        self.assertEqual(self.lua.eval('FRAMES[5].time.text'),"5")
        s.plateBuffs=False
        self.a.FriendlyPlatesChanged()
        self.assertFalse(self.lua.eval('FRAMES[4].shown'))
        self.assertTrue(self.lua.eval('FRAMES[5].shown'))
        s.plateDebuffs=False
        self.a.FriendlyPlatesChanged()
        calls=self.lua.globals().AURA_CALLS
        for _ in range(5): self.render()
        self.assertEqual(self.lua.globals().AURA_CALLS,calls)
        self.assertFalse(self.lua.eval('FRAMES[5].shown'))

    def test_unit_aura_event_invalidates_only_the_matching_unit(self):
        self.a.db.settings.plateBuffs=True
        self.render()
        n=self.lua.globals().AURA_CALLS
        self.a.Dispatch("UNIT_AURA", "party4")
        self.render()
        self.assertEqual(self.lua.globals().AURA_CALLS,n)
        self.a.Dispatch("UNIT_AURA", "nameplate1")
        self.render()
        self.assertGreater(self.lua.globals().AURA_CALLS,n)

    def test_cast_channel_health_and_each_visibility_option(self):
        s=self.a.db.settings
        s.plateCast,s.plateHealth,s.plateWidth,s.plateCastHeight=True,True,210,18
        self.lua.execute('CASTING=true')
        f=self.render()
        self.assertEqual((f.health.value,f.health.hi,f.health.label.text),(60,100,"60%"))
        self.assertEqual((f.cast.width,f.cast.height,f.cast.value),(210,18,2))
        self.assertIn("Healing Touch",f.cast.label.text)
        self.assertTrue(f.cast.icon.shown)
        s.plateCastIcon,s.plateCastLabel,s.plateHealthText=False,False,False
        self.a.FriendlyPlatesChanged()
        self.assertFalse(f.cast.icon.shown)
        self.assertEqual(f.cast.label.text,"")
        self.assertEqual(f.health.label.text,"")
        self.lua.execute('CASTING=false;CHANNEL=true')
        self.render()
        self.assertEqual(f.cast.value,4)
        self.lua.execute('CLOCK=105')
        self.render()
        self.assertFalse(f.cast.shown)
        s.plateHealth=False
        self.render()
        self.assertFalse(f.health.shown)

    def test_missing_and_secret_aura_cast_and_health_data_are_not_guessed(self):
        s=self.a.db.settings
        s.plateBuffs,s.plateCast,s.plateHealth=True,True,True
        self.lua.execute('''
        BUFFS={{name="Hidden",icon=SECRET,applications=SECRET,duration=SECRET,expirationTime=SECRET}}
        UnitCastingInfo=function() return "Hidden",nil,135913,SECRET,SECRET end
        UnitHealth=function() return SECRET end
        ''')
        f=self.render()
        self.assertTrue(f.shown)
        self.assertEqual(len(self.a.ReadFriendlyAuras("nameplate1","HELPFUL",6)),0)
        self.assertFalse(f.cast.shown)
        self.assertFalse(f.health.shown)
        self.lua.execute('C_UnitAuras=nil;UnitCastingInfo=nil;UnitChannelInfo=nil')
        self.assertIsNone(self.a.ReadFriendlyCast("nameplate1"))
        self.assertEqual(len(self.a.ReadFriendlyAuras("nameplate1","HELPFUL",6)),0)

    def test_repeated_refresh_reuses_frames_and_does_not_rescan_auras(self):
        self.a.db.settings.plateBuffs=True
        self.render()
        created,calls=self.lua.eval('#FRAMES'),self.lua.globals().AURA_CALLS
        for _ in range(20): self.render()
        self.assertEqual((self.lua.eval('#FRAMES'),self.lua.globals().AURA_CALLS),(created,calls))
        self.lua.execute('PLATES={}')
        self.a.RefreshFriendlyPlates()
        self.assertFalse(self.lua.eval('FRAMES[1].shown'))
        self.assertEqual(self.lua.globals().NAME.alpha,0.75)


if __name__ == "__main__":
    unittest.main()
