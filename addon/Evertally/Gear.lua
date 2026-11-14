local _, A = ...
-- Own estimates and merchant actions. No external addon, item-level ranking or automatic equip is used.
local G = {cache = {}, generation = 0, merchant = false}
A.Gear = G
local words = {
 en = {gear="Gear & junk",sub_gear="Compare equipment for your role, keep exceptions and review vendor sales.",gearUpgrades="Upgrades",gearJunk="Junk",gearKept="Keep",gearOptions="Options",gearAuto="Auto",gearRole="Gear for",gearEstimate="Weighted estimate, not a DPS percentage",gearLoading="Item information is not available yet.",gearUnusable="Not usable by this character",gearNoStats="The client has not supplied the required item statistics.",gearDelta="Score change",gearCurrent="Currently equipped",gearCandidate="Candidate",gearKeep="Keep this item",gearUnkeep="Allow this item in junk sales",gearEquip="Equip selected",gearPreview="Preview vendor sale",gearConfirm="Confirm sale",gearCancel="Cancel sale",gearMerchant="Open a merchant before confirming the sale.",gearEmpty="No matching items in your bags.",gearProtected="Kept: excluded from vendor sales",gearNoJunk="No safe grey junk to sell.",gearSaleHint="Only the stacks in this preview are authorised. Changed, locked or quest items are skipped.",gearSaleStopped="Sale stopped",gearSaleDone="Sale finished",gearTooltip="Comparison in item tooltips",gearLoot="Notify when you loot an upgrade",gearRewards="Mark the best quest reward",gearOn="On",gearOff="Off",gearBest="Best upgrade",gearBestVendor="Highest vendor value",gearLearned="Requirements or proficiency not met",gearBagChanged="Bag contents changed; review a new preview.",gearCombat="Unavailable in combat.",gearCursor="Clear the cursor first.",gearReady="Ready",gearWaiting="Waiting for the game to confirm the sale",gearUsefulGrey="Kept: useful equipment or unknown comparison",gearRewardLoading="Quest reward information is still loading."},
 cs = {gear="Výbava a odpad",sub_gear="Porovnání pro tvoji roli, chráněné předměty a náhled prodeje obchodníkovi.",gearUpgrades="Zlepšení",gearJunk="Odpad",gearKept="Ponechat",gearOptions="Nastavení",gearAuto="Automaticky",gearRole="Výbava pro",gearEstimate="Odhad podle vah, ne procento DPS",gearLoading="Informace o předmětu ještě nejsou dostupné.",gearUnusable="Tato postava předmět nemůže použít",gearNoStats="Klient neposkytl potřebné statistiky předmětu.",gearDelta="Změna skóre",gearCurrent="Právě nasazeno",gearCandidate="Nový předmět",gearKeep="Tento předmět ponechat",gearUnkeep="Povolit předmět v prodeji odpadu",gearEquip="Nasadit vybrané",gearPreview="Náhled prodeje odpadu",gearConfirm="Potvrdit prodej",gearCancel="Zastavit prodej",gearMerchant="Před potvrzením prodeje otevři obchodníka.",gearEmpty="V taškách nejsou odpovídající předměty.",gearProtected="Ponecháno: vyloučeno z prodeje",gearNoJunk="Žádný bezpečný šedý odpad k prodeji.",gearSaleHint="Schválené jsou jen stacky z tohoto náhledu. Změněné, zamčené a questové věci se přeskočí.",gearSaleStopped="Prodej zastaven",gearSaleDone="Prodej dokončen",gearTooltip="Porovnání v tooltipech předmětů",gearLoot="Upozornit na vylootené zlepšení",gearRewards="Označit nejlepší odměnu questu",gearOn="Zapnuto",gearOff="Vypnuto",gearBest="Nejlepší zlepšení",gearBestVendor="Nejvyšší prodejní cena",gearLearned="Nesplněné podmínky nebo znalost výbavy",gearBagChanged="Obsah tašek se změnil; vytvoř nový náhled.",gearCombat="V boji není tato akce dostupná.",gearCursor="Nejdřív uvolni kurzor.",gearReady="Připraveno",gearWaiting="Čekám na potvrzení prodeje hrou",gearUsefulGrey="Ponecháno: užitečná výbava nebo neznámé porovnání",gearRewardLoading="Načítají se informace o odměnách questu."},
}
for lang, entries in pairs(words) do for key, value in pairs(entries) do A.locale[lang][key] = value end end
local function call(fn, ...) if type(fn) ~= "function" then return nil end; local r={pcall(fn,...)}; if r[1] then return r end end
local function plain(v) if type(A.Plain)=="function" then return A.Plain(v) end;return v end
local function num(v) v=plain(v); if type(v)=="number" and v==v and math.abs(v)<1e15 then return v end end
local function flag(v) return plain(v)==true end
local function field(t,k) if type(A.Field)=="function" then return A.Field(t,k) end;return type(t)=="table" and t[k] end
local function api(mod,key,legacy) return type(mod)=="table" and type(mod[key])=="function" and mod[key] or legacy end
local function idOf(v) if type(v)=="number" then return v end;if type(v)=="string" then return tonumber(v:match("item:(%d+)")) end end
local function changed()
 G.generation=G.generation+1
 if A.gearPage and A.gearPage:IsShown() and A.Changed then A.Changed() end
end
function G.Settings()
 if not A.db then return {keep={}} end
 local s=A.db.settings;if type(s.gear)~="table" then s.gear={} end
 if type(s.gear.keep)~="table" then s.gear.keep={} end
 return s.gear
end
function G.Enabled(key) return G.Settings()[key]~=false end
function G.SetOption(key,on)
 if key~="tooltip" and key~="loot" and key~="rewards" then return false end
 G.Settings()[key]=on==true
 if key=="rewards" and G.MarkRewards then G.MarkRewards() end
 changed();return true
end
function G.Kept(id) return G.Settings().keep[idOf(id)]==true end
function G.SetKept(id,on) id=idOf(id);if not id then return false end;G.Settings().keep[id]=on and true or nil;G.preview=nil;changed();return true end
local melee={strength=1.8,agility=1.1,stamina=.35,attackPower=.8,crit=10,hit=12,haste=8,dps=7}
local ranged={strength=.05,agility=2,stamina=.3,attackPower=.7,rangedAttackPower=.8,crit=10,hit=12,haste=8,dps=8}
local caster={intellect=.9,spirit=.2,stamina=.3,spellPower=1.8,spellCrit=9,spellHit=12,haste=8,mp5=.5}
local healer={intellect=1,spirit=.9,stamina=.25,spellPower=1.2,healing=1.2,spellCrit=4,mp5=3}
local tank={strength=.7,agility=.7,stamina=2,armor=.015,defense=12,dodge=10,parry=9,block=5,hit=5,dps=2}
local agile={strength=1,agility=1.8,stamina=.4,attackPower=.8,crit=10,hit=12,haste=8,dps=7}
local feral={strength=2,agility=1.8,stamina=.4,attackPower=.8,crit=10,hit=12,haste=8}
local classes={WARRIOR={{"Arms",melee},{"Fury",melee},{"Protection",tank}},PALADIN={{"Holy",healer},{"Protection",tank},{"Retribution",melee}},HUNTER={{"Beast Mastery",ranged},{"Marksmanship",ranged},{"Survival",ranged}},ROGUE={{"Assassination",agile},{"Combat",agile},{"Subtlety",agile}},PRIEST={{"Discipline",healer},{"Holy",healer},{"Shadow",caster}},SHAMAN={{"Elemental",caster},{"Enhancement",melee},{"Restoration",healer}},MAGE={{"Arcane",caster},{"Fire",caster},{"Frost",caster}},WARLOCK={{"Affliction",caster},{"Demonology",caster},{"Destruction",caster}},DRUID={{"Balance",caster},{"Feral Combat",feral},{"Restoration",healer},{"Feral tank",tank}}}
local defaults={WARRIOR=1,PALADIN=3,HUNTER=1,ROGUE=2,PRIEST=3,SHAMAN=2,MAGE=3,WARLOCK=1,DRUID=2}
function G.Class() local r=call(UnitClass,"player");return r and plain(r[3]) end
function G.Profiles() return classes[G.Class()] or {} end
function G.SetProfile(index)
 local c=G.Class();index=tonumber(index);if index~=0 and not (classes[c] and classes[c][index]) then return false end
 if index==0 then G.Settings().profile=nil else G.Settings().profile=c..":"..index end
 G.profileCache=nil
 changed();return true
end
function G.Profile()
 local c=G.Class();local list=classes[c];if not list then return nil end
 if G.profileCache and G.profileCache.class==c and G.profileCache.choice==G.Settings().profile then return G.profileCache end
 local override=G.Settings().profile;local selected=type(override)=="string" and tonumber(override:match("^"..c..":(%d+)$")) or nil
 if not list[selected] then selected=nil end
 local index=selected
 if not index then
  local trees=A.TalentTrees and A.TalentTrees();local best=0
  for i,t in ipairs(type(trees)=="table" and trees or {}) do local spent=num(t.spent) or 0;if spent>best and list[i] then best,index=spent,i end end
 end
 index=index or defaults[c] or 1
 G.profileCache={class=c,index=index,name=list[index][1],weights=list[index][2],automatic=selected==nil,choice=override};return G.profileCache
end
local statKeys={ITEM_MOD_STRENGTH_SHORT="strength",ITEM_MOD_AGILITY_SHORT="agility",ITEM_MOD_STAMINA_SHORT="stamina",ITEM_MOD_INTELLECT_SHORT="intellect",ITEM_MOD_SPIRIT_SHORT="spirit",ITEM_MOD_ATTACK_POWER_SHORT="attackPower",ITEM_MOD_RANGED_ATTACK_POWER_SHORT="rangedAttackPower",ITEM_MOD_SPELL_POWER_SHORT="spellPower",ITEM_MOD_SPELL_DAMAGE_DONE_SHORT="spellPower",ITEM_MOD_SPELL_HEALING_DONE_SHORT="healing",ITEM_MOD_CRIT_RATING_SHORT="crit",ITEM_MOD_HIT_RATING_SHORT="hit",ITEM_MOD_SPELL_CRIT_RATING_SHORT="spellCrit",ITEM_MOD_SPELL_HIT_RATING_SHORT="spellHit",ITEM_MOD_HASTE_RATING_SHORT="haste",ITEM_MOD_MANA_REGENERATION_SHORT="mp5",ITEM_MOD_POWER_REGEN0_SHORT="mp5",RESISTANCE0_NAME="armor",ITEM_MOD_ARMOR_SHORT="armor",ITEM_MOD_DEFENSE_SKILL_RATING_SHORT="defense",ITEM_MOD_DODGE_RATING_SHORT="dodge",ITEM_MOD_PARRY_RATING_SHORT="parry",ITEM_MOD_BLOCK_RATING_SHORT="block",ITEM_MOD_DAMAGE_PER_SECOND_SHORT="dps"}
G.StatKeys=statKeys
local statNames={
 en={strength="Strength",agility="Agility",stamina="Stamina",intellect="Intellect",spirit="Spirit",attackPower="Attack power",rangedAttackPower="Ranged attack power",spellPower="Spell power",healing="Healing power",crit="Critical strike",spellCrit="Spell critical strike",hit="Hit",spellHit="Spell hit",haste="Haste",mp5="Mana per 5 seconds",armor="Armor",defense="Defense",dodge="Dodge",parry="Parry",block="Block",dps="Weapon damage per second"},
 cs={strength="Síla",agility="Obratnost",stamina="Výdrž",intellect="Inteligence",spirit="Duch",attackPower="Síla útoku",rangedAttackPower="Síla útoku na dálku",spellPower="Síla kouzel",healing="Síla léčení",crit="Kritický zásah",spellCrit="Kritický zásah kouzel",hit="Zásah",spellHit="Zásah kouzel",haste="Rychlost",mp5="Mana za 5 sekund",armor="Zbroj",defense="Obrana",dodge="Úhyb",parry="Odražení",block="Blok",dps="Poškození zbraně za sekundu"},
}
function G.StatName(stat) local lang=A.db and A.db.settings.language=="cs" and "cs" or "en";return statNames[lang][stat] or stat end
local slots={INVTYPE_HEAD={1},INVTYPE_NECK={2},INVTYPE_SHOULDER={3},INVTYPE_BODY={4},INVTYPE_CHEST={5},INVTYPE_ROBE={5},INVTYPE_WAIST={6},INVTYPE_LEGS={7},INVTYPE_FEET={8},INVTYPE_WRIST={9},INVTYPE_HAND={10},INVTYPE_FINGER={11,12},INVTYPE_TRINKET={13,14},INVTYPE_CLOAK={15},INVTYPE_WEAPON={16},INVTYPE_WEAPONMAINHAND={16},INVTYPE_WEAPONOFFHAND={17},INVTYPE_SHIELD={17},INVTYPE_HOLDABLE={17},INVTYPE_2HWEAPON={16},INVTYPE_RANGED={18},INVTYPE_RANGEDRIGHT={18},INVTYPE_THROWN={18},INVTYPE_RELIC={18},INVTYPE_TABARD={19}}
local weaponClasses={WARRIOR={[0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[10]=true,[13]=true,[15]=true,[16]=true,[18]=true},PALADIN={[0]=true,[1]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true},HUNTER={[0]=true,[1]=true,[2]=true,[3]=true,[6]=true,[7]=true,[8]=true,[10]=true,[13]=true,[15]=true,[18]=true},ROGUE={[0]=true,[2]=true,[3]=true,[4]=true,[7]=true,[13]=true,[15]=true,[16]=true,[18]=true},PRIEST={[4]=true,[10]=true,[15]=true,[19]=true},SHAMAN={[0]=true,[1]=true,[4]=true,[5]=true,[10]=true,[13]=true,[15]=true},MAGE={[7]=true,[10]=true,[15]=true,[19]=true},WARLOCK={[7]=true,[10]=true,[15]=true,[19]=true},DRUID={[4]=true,[5]=true,[6]=true,[10]=true,[13]=true,[15]=true}}
local armor={WARRIOR=4,PALADIN=4,HUNTER=3,ROGUE=2,PRIEST=1,SHAMAN=3,MAGE=1,WARLOCK=1,DRUID=2}
local function tooltipData(link) local r=call(C_TooltipInfo and C_TooltipInfo.GetHyperlink,link);return r and r[2] end
function G.DualWieldKnown()
 if A.Call(IsPlayerSpell,674)==true or A.Call(IsSpellKnown,674)==true then return true end
 local bank=Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
 return bank~=nil and A.Call(C_SpellBook and C_SpellBook.IsSpellKnown,674,bank)==true or false
end
function G.Item(reference)
 if type(reference)=="table" then return reference end
 reference=plain(reference);local id=idOf(reference);if not id then return nil end
 local key=tostring(reference);if G.cache[key] then return G.cache[key] end
 local r=call(api(C_Item,"GetItemInfo",GetItemInfo),reference)
 if not r or type(plain(r[2]))~="string" then return {id=id,link=reference,known=false} end
 local item={id=id,name=plain(r[2]),link=plain(r[3]) or reference,quality=num(r[4]),itemLevel=num(r[5]),minLevel=num(r[6]) or 0,kind=plain(r[7]),subType=plain(r[8]),equipLoc=plain(r[10]) or "",icon=plain(r[11]),vendorPrice=num(r[12]),classId=num(r[13]),subclassId=num(r[14]),known=true}
 local stats=call(api(C_Item,"GetItemStats",GetItemStats),item.link)
 if stats and type(stats[2])=="table" then
  item.stats={}
  for k,v in pairs(stats[2]) do if type(k)=="string" and num(v) then local s=statKeys[k];if s then item.stats[s]=math.max(item.stats[s] or 0,v) end end end
 end
 local equip=call(api(C_Item,"IsEquippableItem",IsEquippableItem),item.link);if equip and type(plain(equip[2]))=="boolean" then item.equippable=plain(equip[2]) end
 local usableFn=api(C_Item,"IsUsableItem",IsUsableItem)
 if type(usableFn)=="function" then
  local usable=call(usableFn,item.link);local value=usable and plain(usable[2])
  if type(value)=="boolean" then item.usable=value else item.usabilityUnknown=true end
 end
 local tip=tooltipData(item.link)
 for _,line in ipairs(type(tip)=="table" and type(tip.lines)=="table" and tip.lines or {}) do
  local left=plain(field(line,"leftText"));local color=field(line,"leftColor")
  if type(left)=="string" then
   local lower=left:lower();local value=tonumber((lower:match("([%d]+[.,]?[%d]*)[^%d]*damage per second") or lower:match("([%d]+[.,]?[%d]*)[^%d]*dps") or ""):gsub(",","."))
   if value then item.stats=item.stats or {};item.stats.dps=value end
   if color and (num(field(color,"r")) or 0)>.9 and (num(field(color,"g")) or 1)<.25 and (num(field(color,"b")) or 1)<.25 then item.unmet=true end
  end
 end
 G.cache[key]=item;return item
end
function G.CanUse(item)
 if not item or not item.known then return nil,"gearLoading" end
 if not slots[item.equipLoc] or item.equippable==false then return false,"gearUnusable" end
 if item.usable==false then return false,"gearLearned" end
 if item.usabilityUnknown then return nil,"gearLoading" end
 local c=G.Class();local level=num(A.Call(UnitLevel,"player")) or 1
 if (item.minLevel or 0)>level or item.unmet then return false,"gearLearned" end
 if item.classId==4 and item.equipLoc~="INVTYPE_CLOAK" and item.subclassId and item.subclassId>=1 and item.subclassId<=4 then
  local max=armor[c] or 0;if level<40 and (c=="WARRIOR" or c=="PALADIN" or c=="HUNTER" or c=="SHAMAN") then max=max-1 end
  if item.subclassId>max then return false,"gearLearned" end
 end
 if item.equipLoc=="INVTYPE_SHIELD" and c~="WARRIOR" and c~="PALADIN" and c~="SHAMAN" then return false,"gearLearned" end
 if item.equipLoc=="INVTYPE_WEAPONOFFHAND" and not G.DualWieldKnown() then return false,"gearLearned" end
 if item.classId==2 and item.subclassId and not (weaponClasses[c] and weaponClasses[c][item.subclassId]) then return false,"gearLearned" end
 if item.allowedClasses and not item.allowedClasses[c] then return false,"gearLearned" end
 return true
end
function G.Score(item,profile)
 profile=profile or G.Profile();if not item or not item.known or not profile or type(item.stats)~="table" then return nil,{} end
 if item.classId==2 and profile.weights.dps and item.stats.dps==nil and item.equipLoc~="INVTYPE_RELIC" then return nil,{} end
 local score,parts=0,{}
 for stat,value in pairs(item.stats) do local weight=profile.weights[stat]
  if stat=="dps" and weight then
   local rangedSlot=item.equipLoc=="INVTYPE_RANGED" or item.equipLoc=="INVTYPE_RANGEDRIGHT" or item.equipLoc=="INVTYPE_THROWN"
   if profile.class=="HUNTER" and not rangedSlot then weight=.1 elseif profile.class~="HUNTER" and rangedSlot then weight=.1 end
  end
  if weight and num(value) then local amount=value*weight;score=score+amount;parts[#parts+1]={stat=stat,value=value,weight=weight,score=amount} end
 end
 table.sort(parts,function(a,b)return math.abs(a.score)>math.abs(b.score) end)
 return score,parts
end
function G.Equipped(slot)
 local r=call(GetInventoryItemLink,"player",slot)
 if r then if not r[2] then return nil,true end;return G.Item(plain(r[2])),true end
 r=call(GetInventoryItemID,"player",slot)
 if r then if not r[2] then return nil,true end;return G.Item(plain(r[2])),true end
 return nil,false
end
function G.Compare(reference)
 local item=G.Item(reference);local use,reason=G.CanUse(item)
 local out={item=item,status=use==false and "unusable" or "unknown",reason=reason,parts={}}
 if not use then return out end
 local profile=G.Profile();local score,parts=G.Score(item,profile);out.score,out.parts,out.profile=score,parts,profile
 if not score then out.reason="gearNoStats";return out end
 local options=slots[item.equipLoc];local best,current,replace
 if item.equipLoc=="INVTYPE_WEAPON" and G.DualWieldKnown() then options={16,17} end
 for _,slot in ipairs(options) do
  local equipped,available=G.Equipped(slot);if not available then out.reason="gearLoading";return out end
  local baseline=equipped and G.Score(equipped,profile) or 0
  if equipped and baseline==nil then out.reason="gearNoStats";return out end
  local blockedOffhand=false
  if slot==17 then
   local main=G.Equipped(16)
   blockedOffhand=main and main.equipLoc=="INVTYPE_2HWEAPON"
  end
  if item.equipLoc=="INVTYPE_2HWEAPON" then
   local off,offAvailable=G.Equipped(17);if not offAvailable then out.reason="gearLoading";return out end
   local offScore=off and G.Score(off,profile) or 0;if off and offScore==nil then out.reason="gearNoStats";return out end;baseline=baseline+offScore
  end
  if not blockedOffhand and (best==nil or baseline<best) then best,current,replace=baseline,equipped,slot end
 end
 if best==nil then out.reason="gearLearned";return out end
 out.baseline,out.current,out.slot,out.delta=best,current,replace,score-best
 out.status=out.delta>.01 and "upgrade" or out.delta<-.01 and "downgrade" or "same"
 return out
end
local function bagSlots(bag) return math.min(200,num(A.Call(api(C_Container,"GetContainerNumSlots",GetContainerNumSlots),bag)) or 0) end
function G.BagSlot(bag,slot)
 local r=call(C_Container and C_Container.GetContainerItemInfo,bag,slot);local entry
 if r then
  local v=r[2];if type(v)~="table" then return nil end
  entry={bag=bag,slot=slot,id=num(field(v,"itemID")),link=plain(field(v,"hyperlink")),count=num(field(v,"stackCount")),locked=plain(field(v,"isLocked"))~=false,quest=flag(field(v,"isQuestItem")),noValue=flag(field(v,"hasNoValue"))}
 else
  r=call(GetContainerItemInfo,bag,slot);if not r or not r[2] then return nil end
  entry={bag=bag,slot=slot,id=num(r[11]) or num(A.Call(GetContainerItemID,bag,slot)),link=plain(r[8]),count=num(r[3]),locked=plain(r[4])~=false,noValue=flag(r[10])}
 end
 if not entry.count or entry.count<1 or entry.count>1000000 or entry.count~=math.floor(entry.count) then return nil,"unknown_count" end
 entry.id=entry.id or idOf(entry.link);if not entry.id then return nil end
 local quest=call(api(C_Container,"GetContainerItemQuestInfo",GetContainerItemQuestInfo),bag,slot)
 if quest then local value=quest[2];entry.quest=entry.quest or type(value)=="table" and (flag(field(value,"isQuestItem")) or num(field(value,"questID"))~=nil) or value==true end
 entry.item=G.Item(entry.link or entry.id);entry.link=entry.link or entry.item and entry.item.link
 if entry.item and entry.item.classId==12 then entry.quest=true end
 return entry
end
-- Confirmation checks the whole carried inventory, so moving a stack to another bag cannot count as a vendor sale.
function G.TotalLink(link)
 local total=0;local max=math.min(10,num(NUM_BAG_SLOTS) or 4)
 for bag=0,max do for slot=1,bagSlots(bag) do
  local entry,reason=G.BagSlot(bag,slot);if reason then return nil end
  if entry and entry.link==link then total=total+entry.count end
 end end
 return total
end
function G.Bags()
 local out={};local max=math.min(10,num(NUM_BAG_SLOTS) or 4)
 for bag=0,max do for slot=1,bagSlots(bag) do local entry=G.BagSlot(bag,slot);if entry then out[#out+1]=entry end end end
 return out
end
function G.JunkReason(entry)
 local item=entry and entry.item
 if not entry or not item or not item.known or item.quality~=0 or not item.vendorPrice or item.vendorPrice<=0 or entry.noValue then return "ineligible" end
 if entry.locked then return "locked" end
 if entry.quest then return "quest" end
 if G.Kept(entry.id) then return "kept" end
 if slots[item.equipLoc] then local compare=G.Compare(item);if compare.status=="upgrade" or compare.status=="unknown" then return "useful" end end
 return nil
end
function G.PreviewJunk()
 local plan={items={},value=0,createdAt=A.Now(),generation=G.generation,merchantEpoch=G.merchantEpoch}
 for _,entry in ipairs(G.Bags()) do if not G.JunkReason(entry) then plan.items[#plan.items+1]=entry;plan.value=plan.value+entry.item.vendorPrice*entry.count end end
 G.preview=plan;return plan
end
local function combat() return A.Call(InCombatLockdown)==true end
local function cursor() return A.Call(CursorHasItem)==true or A.Call(CursorHasSpell)==true end
local function merchant()
 if MerchantFrame and type(MerchantFrame.IsShown)=="function" then
  local shown=A.Call(MerchantFrame.IsShown,MerchantFrame);if type(shown)=="boolean" then return shown end
 end
 return G.merchant==true
end
local function same(a,b) return a and b and a.id==b.id and a.count==b.count and a.link==b.link end
function G.CancelSale(reason)
 local sale=G.sale;if sale then sale.active=false;sale.reason=reason or "cancelled" end;G.preview=nil
end
local function saleGuard()
 if not merchant() then return "gearMerchant" end;if combat() then return "gearCombat" end;if cursor() then return "gearCursor" end
end
local function schedule()
 if C_Timer and type(C_Timer.After)=="function" then local sale=G.sale;C_Timer.After(.4,function() if G.sale==sale and sale.active then G.StepSale(true) end end) end
end
function G.StepSale(poll)
 local sale=G.sale;if not sale or not sale.active then return false,"inactive" end
 if sale.merchantEpoch~=G.merchantEpoch then G.CancelSale("gearMerchant");changed();return false,"gearMerchant" end
 local stop=saleGuard();if stop then G.CancelSale(stop);changed();return false,stop end
 if sale.waiting then
  local pending=sale.waiting;local now=G.BagSlot(pending.entry.bag,pending.entry.slot)
  local money=num(A.Call(GetMoney))
  local total=G.TotalLink(pending.entry.link)
  if not same(now,pending.entry) and total and pending.total and total==pending.total-pending.entry.count and money and pending.money and money>=pending.money+pending.value then
   sale.confirmed=sale.confirmed+1;sale.value=sale.value+pending.value;sale.waiting=nil;sale.index=sale.index+1
  else
   if poll then pending.polls=pending.polls+1 end
   if pending.polls>=3 then G.CancelSale("unconfirmed");changed();return false,"unconfirmed" end
   if poll then schedule() end;return false,"waiting"
  end
 end
 while sale.index<=#sale.plan.items do
  local expected=sale.plan.items[sale.index];local entry=G.BagSlot(expected.bag,expected.slot)
  if not same(entry,expected) or G.JunkReason(entry) then sale.skipped=sale.skipped+1;sale.index=sale.index+1
  else
   local fn=api(C_Container,"UseContainerItem",UseContainerItem);if type(fn)~="function" then G.CancelSale("api_missing");return false,"api_missing" end
   local total=G.TotalLink(expected.link);if not total then G.CancelSale("gearBagChanged");changed();return false,"gearBagChanged" end
   sale.waiting={entry=expected,money=num(A.Call(GetMoney)),total=total,value=expected.item.vendorPrice*expected.count,polls=0}
   local ok=pcall(fn,expected.bag,expected.slot);sale.attempted=sale.attempted+1
   if not ok then G.CancelSale("refused");changed();return false,"refused" end
   schedule();changed();return true,"requested"
  end
 end
 sale.active=false;sale.reason="complete";G.preview=nil;changed();return true,"complete"
end
function G.BeginSale(plan)
 local reason=saleGuard();if reason then return false,reason end
 if G.sale and G.sale.active then return false,"busy" end
 if not plan or plan~=G.preview or plan.used then return false,"gearBagChanged" end
 if plan.merchantEpoch~=G.merchantEpoch then return false,"gearMerchant" end
 if #plan.items==0 then return false,"gearNoJunk" end
 plan.used=true;G.sale={plan=plan,index=1,merchantEpoch=G.merchantEpoch,active=true,attempted=0,confirmed=0,skipped=0,value=0}
 return G.StepSale()
end
function G.Equip(entry)
 if combat() then return false,"gearCombat" end;if cursor() then return false,"gearCursor" end
 local current=entry and G.BagSlot(entry.bag,entry.slot)
 if not entry or not same(entry,current) or current.locked then return false,"gearBagChanged" end
 local comparison=G.Compare(entry.item);if comparison.status~="upgrade" and comparison.status~="same" and comparison.status~="downgrade" then return false,comparison.reason or "gearUnusable" end
 if type(EquipItemByName)~="function" then return false,"api_missing" end
 local ok=pcall(EquipItemByName,entry.link or entry.id,comparison.slot);return ok,ok and "requested" or "refused"
end
function G.QuestRewards()
 local entries,best,bestDelta,bestVendor={},nil,0,-1;local loading=false;local vendorLoading=false
 local count=math.min(20,num(A.Call(GetNumQuestChoices)) or 0)
 for index=1,count do
  local link=A.Call(GetQuestItemLink,"choice",index);local item=G.Item(link);local comparison=G.Compare(item)
  local reward=call(GetQuestItemInfo,"choice",index);local count=reward and num(reward[4])
  if not count or count<1 or count~=math.floor(count) then count=nil;vendorLoading=true end
  entries[index]={index=index,item=item,comparison=comparison,count=count}
  if not item or not item.known or comparison.status=="unknown" and item.equipLoc~="" then loading=true end
  if comparison.status=="upgrade" and comparison.delta>bestDelta then best,bestDelta=index,comparison.delta end
  local vendor=item and item.vendorPrice and count and item.vendorPrice*count;if vendor and vendor>bestVendor then bestVendor=vendor;entries.vendor=index end
 end
 if loading then return entries,nil,"loading" end
 if best then return entries,best,"upgrade" end
 if vendorLoading then return entries,nil,"loading" end
 return entries,entries.vendor,entries.vendor and "vendor" or "unknown"
end
function G.MarkRewards()
 local entries,best,reason=G.QuestRewards();local frame=QuestInfoRewardsFrame
 for i=1,math.max(#entries,20) do
  local button=frame and type(frame.RewardButtons)=="table" and frame.RewardButtons[i] or _G["QuestInfoRewardsFrameQuestInfoItem"..i] or _G["QuestInfoItem"..i]
  if button and button.evertallyGearBadge then button.evertallyGearBadge:Hide() end
  if i==best and G.Enabled("rewards") and button and type(button.CreateFontString)=="function" then
   if not button.evertallyGearBadge then local badge=button:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");badge:SetPoint("BOTTOMLEFT",3,2);button.evertallyGearBadge=badge end
   button.evertallyGearBadge:SetText("Evertally: "..A.L(reason=="upgrade" and "gearBest" or "gearBestVendor"));button.evertallyGearBadge:Show()
  end
 end
 return best,reason
end
function G.AppendTooltip(tooltip)
 if not G.Enabled("tooltip") or not tooltip or type(tooltip.GetItem)~="function" then return false end
 local r=call(tooltip.GetItem,tooltip);local link=r and plain(r[3]);if not link or tooltip.evertallyGearLink==link then return false end
 local compare=G.Compare(link);if compare.status=="unknown" or compare.status=="unusable" then return false end
 tooltip.evertallyGearLink=link
 local tint=compare.delta>0 and {.4,1,.35} or {1,.65,.35}
 tooltip:AddLine(string.format("Evertally · %s: %+.1f",compare.profile.name,compare.delta),unpack(tint));tooltip:AddLine(A.L("gearEstimate"),.72,.72,.72,true)
 tooltip:Show();return true
end
function G.HookTooltip()
 if G.hooked or not GameTooltip then return end;G.hooked=true
 if type(GameTooltip.HookScript)=="function" then pcall(GameTooltip.HookScript,GameTooltip,"OnTooltipCleared",function(t)t.evertallyGearLink=nil end) end
 local modern=TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
 if modern then pcall(TooltipDataProcessor.AddTooltipPostCall,Enum.TooltipDataType.Item,function(t)pcall(G.AppendTooltip,t) end)
 elseif type(GameTooltip.HookScript)=="function" then pcall(GameTooltip.HookScript,GameTooltip,"OnTooltipSetItem",function(t)pcall(G.AppendTooltip,t) end) end
end
function G.HookRewards()
 if G.rewardsHooked then return end
 if type(hooksecurefunc)=="function" and type(QuestInfo_Display)=="function" then
  G.rewardsHooked=pcall(hooksecurefunc,"QuestInfo_Display",function()pcall(G.MarkRewards)end)
 end
end
function G.LootNotice(link)
 if not G.Enabled("loot") then return false end
 local item=G.Item(link);local compare=G.Compare(item)
 if compare.status=="upgrade" then
  if G.lastNotice and G.lastNotice.link==link and A.Now()-G.lastNotice.at<3 then return false end
  G.lastNotice={link=link,at=A.Now()};A.Print(A.L("gearUpgrades")..": "..(item.name or tostring(item.id))..string.format(" (%s %+.1f)",compare.profile.name,compare.delta));return true
 end
 if item and not item.known then G.pendingLoot=link end
 return false
end
local function invalidate() G.cache={};G.generation=G.generation+1 end
A.On("PLAYER_LOGIN",function()G.HookTooltip();G.HookRewards()end)
A.On("PLAYER_EQUIPMENT_CHANGED",function()invalidate();changed()end)
A.On("PLAYER_LEVEL_UP",function()invalidate();changed()end)
A.On("SPELLS_CHANGED",function()G.profileCache=nil;invalidate();changed()end)
A.On("PLAYER_TALENT_UPDATE",function()G.profileCache=nil;invalidate();changed()end)
A.On("TRAIT_CONFIG_UPDATED",function()G.profileCache=nil;invalidate();changed()end)
A.On("GET_ITEM_INFO_RECEIVED",function(_,ok)invalidate();if G.pendingLoot and ok~=false then local link=G.pendingLoot;G.pendingLoot=nil;G.LootNotice(link) end;G.MarkRewards();changed()end)
local function ownLoot(message)
 for _,template in ipairs({LOOT_ITEM_SELF,LOOT_ITEM_SELF_MULTIPLE,LOOT_ITEM_CREATED_SELF,LOOT_ITEM_CREATED_SELF_MULTIPLE}) do
  if type(template)=="string" then local prefix=template:match("^(.-)%%s");if prefix and message:sub(1,#prefix)==prefix then return true end end
 end
 return false
end
A.On("CHAT_MSG_LOOT",function(message)message=plain(message);if type(message)=="string" and ownLoot(message) then local link=message:match("(|c%x+|Hitem:.-|h.-|h|r)") or message:match("(|Hitem:.-|h.-|h)");if link then G.LootNotice(link) end end end)
A.On("MERCHANT_SHOW",function()G.merchant=true;G.merchantEpoch=(G.merchantEpoch or 0)+1;G.CancelSale("new_merchant");changed()end)
A.On("MERCHANT_CLOSED",function()G.merchant=false;G.merchantEpoch=(G.merchantEpoch or 0)+1;G.CancelSale("gearMerchant");changed()end)
A.On("PLAYER_REGEN_DISABLED",function()G.CancelSale("gearCombat")end)
A.On("BAG_UPDATE_DELAYED",function()if G.sale and G.sale.active then G.StepSale() end;changed()end)
A.On("QUEST_COMPLETE",function()
 G.MarkRewards()
 if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(0,function()pcall(G.MarkRewards)end) end
end)
A.On("QUEST_FINISHED",function()G.preview=nil end)
