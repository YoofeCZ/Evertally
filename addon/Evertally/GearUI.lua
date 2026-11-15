local _, A = ...
local function T(key) return A.L(key) end
A.locale.en.gearSearch="Search bags…";A.locale.cs.gearSearch="Hledat v taškách…"
function A.BuildGearPage(page,k)
 local G=A.Gear;if not G then return end
 A.gearPage=page;k.PageHeader(page,"gear")
 local tabs={"upgrades","junk","kept","options"};local names={upgrades="gearUpgrades",junk="gearJunk",kept="gearKept",options="gearOptions"}
 page.filter="upgrades";page.query="";page.chips={}
 local previous
 for _,key in ipairs(tabs) do local value=key;local chip=k.Chip(page,function()page.filter=value;page.selected=nil;page.plan=nil;page.Refresh()end)
  if previous then chip:SetPoint("LEFT",previous,"RIGHT",5,0) else chip:SetPoint("TOPLEFT",0,-55) end
  page.chips[key]=chip;previous=chip
 end
 page.role=k.Button(page,nil,210,"ghost",function()
  local profile=G.Profile();local n=profile and not profile.automatic and profile.index or 0;n=n+1;if n>#G.Profiles() then n=0 end
  G.SetProfile(n);page.plan=nil;page.Refresh()
 end);page.role:SetPoint("TOPLEFT",0,-87)
 page.search=k.SearchBox(page,180,function(value)page.query=value or "";page.selected=nil;page.Refresh()end);page.search:SetPoint("TOPRIGHT",0,-87)
 page.book=k.Book(page,124);page.list=k.ListView(page.book.index,0,nil,true);page.document=k.Document(page.book.paper)
 page.book:SetPoint("BOTTOMRIGHT",0,80)
 page.primary=k.Button(page,nil,185,"primary",function()
  if page.filter=="junk" then
   if page.plan then local ok,reason=G.BeginSale(page.plan);page.message=not ok and T(reason) or nil;page.plan=nil
   else page.plan=G.PreviewJunk();page.message=nil end
  elseif page.selected then local ok,reason=G.Equip(page.selected);page.message=not ok and T(reason) or nil end
  page.Refresh()
 end);page.primary:SetPoint("BOTTOMLEFT",0,42)
 page.keep=k.Button(page,nil,220,"ghost",function()
  if page.selected then G.SetKept(page.selected.id,not G.Kept(page.selected.id));page.plan=nil;page.Refresh() end
 end);page.keep:SetPoint("BOTTOMRIGHT",0,42)
 page.cancel=k.Button(page,nil,185,"ghost",function()G.CancelSale();page.plan=nil;page.Refresh()end);page.cancel:SetPoint("BOTTOMLEFT",0,42)
 page.note=k.label(page,11,k.C.mist);page.note:SetPoint("BOTTOMLEFT",0,9);page.note:SetPoint("BOTTOMRIGHT",0,9);page.note:SetWordWrap(true)
 page.footerRule=page:CreateTexture(nil,"BORDER");page.footerRule:SetHeight(1);page.footerRule:SetPoint("BOTTOMLEFT",0,33);page.footerRule:SetPoint("BOTTOMRIGHT",0,33);k.paint(page.footerRule,k.C.gold,.3)
 local function itemTitle(item,id) return item and item.name or ("#"..tostring(id or "?")) end
 local function optionRows()
  local rows={};for _,key in ipairs({"tooltip","loot","rewards"}) do local value=key;rows[#rows+1]={text=T(({tooltip="gearTooltip",loot="gearLoot",rewards="gearRewards"})[key])..": "..T(G.Enabled(key) and "gearOn" or "gearOff"),onClick=function()G.SetOption(value,not G.Enabled(value));page.Refresh()end} end
  return rows
 end
 function page.Refresh()
  local profile=G.Profile()
  page.search.hint:SetText(T("gearSearch"))
  page.role.text:SetText(T("gearRole")..": "..(profile and ((profile.automatic and T("gearAuto").." · " or "")..profile.name) or "?"))
  for key,chip in pairs(page.chips)do chip.SetLabel(T(names[key]));chip.SetOn(page.filter==key)end
  local sale=G.sale;local selling=sale and sale.active
  page.cancel:SetShown(selling==true);page.cancel.text:SetText(T("gearCancel"))
  page.primary:SetShown(page.filter~="options" and not selling and page.filter~="kept")
  page.keep:SetShown(page.selected~=nil and not selling and page.filter~="options")
  page.keep.text:SetText(T(page.selected and G.Kept(page.selected.id) and "gearUnkeep" or "gearKeep"))
  page.primary.text:SetText(T(page.filter=="junk" and (page.plan and "gearConfirm" or "gearPreview") or "gearEquip"))
  local rows,selected={},nil;local query=k.fold(page.query)
  if page.filter~="options" then
   local entries=G.Bags()
   if page.filter=="kept" then
    local seen={};for _,entry in ipairs(entries)do if G.Kept(entry.id)then seen[entry.id]=true end end
    for id in pairs(G.Settings().keep)do if not seen[id]then entries[#entries+1]={id=id,item=G.Item(id),savedOnly=true}end end
   end
   for _,entry in ipairs(entries)do
    local value=entry;local item=entry.item;local comparison=G.Compare(item);entry.comparison=comparison
    local keep=page.filter=="upgrades" and (comparison.status=="upgrade" or comparison.status=="unknown" and item and item.equipLoc and item.equipLoc~="") or page.filter=="junk" and item and item.quality==0 or page.filter=="kept" and G.Kept(entry.id)
    if keep and (query=="" or k.fold(itemTitle(item,entry.id).." "..tostring(entry.id)):find(query,1,true))then
     local why=G.JunkReason(entry);local sub=page.filter=="junk" and (why=="kept" and T("gearProtected") or why=="useful" and T("gearUsefulGrey") or why and tostring(why) or A.FormatMoney((item.vendorPrice or 0)*(entry.count or 1))) or G.Kept(entry.id) and T("gearProtected") or comparison.reason and T(comparison.reason) or T("gearEstimate")
     rows[#rows+1]={key=tostring(entry.bag)..":"..tostring(entry.slot)..":"..entry.id,itemId=entry.id,icon=item and item.icon or k.ICON.item,title=itemTitle(item,entry.id),sub=sub,right=comparison.delta and string.format("%+.1f",comparison.delta) or "",onClick=function()page.selected=value;page.plan=nil;page.message=nil;page.Refresh()end}
     if not page.selected and not selected or page.selected and page.selected.id==entry.id and page.selected.bag==entry.bag and page.selected.slot==entry.slot then selected=entry end
    end
   end
  end
  page.selected=selected
  page.list.SetItems(rows,T("gearEmpty"))
  local spec={key="gear:"..page.filter,title=T(names[page.filter]),entries={}}
  if page.filter=="options"then spec.subtitle=T("gearEstimate");spec.entries=optionRows()
  elseif page.plan then
   spec.key="gear:preview:"..tostring(page.plan.createdAt);spec.title=T("gearPreview");spec.subtitle=A.FormatMoney(page.plan.value)
   spec.entries[1]={text=T("gearSaleHint")}
   for _,entry in ipairs(page.plan.items)do spec.entries[#spec.entries+1]={text=itemTitle(entry.item,entry.id).." ×"..entry.count.."  "..A.FormatMoney(entry.item.vendorPrice*entry.count),icon=entry.item.icon}end
   if #page.plan.items==0 then spec.entries[#spec.entries+1]={text=T("gearNoJunk")}end
  elseif selected then
   local item,comparison=selected.item,selected.comparison;spec.key="gear:"..selected.id..":"..tostring(selected.bag)..":"..tostring(selected.slot);spec.title=itemTitle(item,selected.id);spec.subtitle=profile and profile.name or ""
   spec.entries={{text=T("gearEstimate")},{text=G.Kept(selected.id)and T("gearProtected")or comparison.reason and T(comparison.reason)or comparison.delta and T("gearDelta")..string.format(": %+.1f",comparison.delta)or ""}}
   if comparison.current then spec.entries[#spec.entries+1]={head=true,text=T("gearCurrent")};spec.entries[#spec.entries+1]={text=itemTitle(comparison.current),icon=comparison.current.icon}end
   if comparison.score then
    spec.entries[#spec.entries+1]={head=true,text=T("gearCandidate")..string.format(" · %.1f",comparison.score)}
    for _,part in ipairs(comparison.parts or {})do spec.entries[#spec.entries+1]={text=string.format("%s: %g × %g = %+.1f",G.StatName(part.stat),part.value,part.weight,part.score)}end
   end
  else spec.entries={{text=T("gearEmpty")},{text=T("gearEstimate")}}end
  page.document.Set(spec)
  local state=selling and T("gearWaiting") or sale and (T(sale.reason=="complete"and"gearSaleDone"or"gearSaleStopped")..": "..tostring(sale.confirmed).." / "..#sale.plan.items.." · "..A.FormatMoney(sale.value))or nil
  page.note:SetText(page.message or state or T("gearEstimate"))
  page.keep:SetShown(page.selected~=nil and not selling and page.filter~="options")
  page.keep.text:SetText(T(page.selected and G.Kept(page.selected.id) and "gearUnkeep" or "gearKeep"))
 end
 local function layout()
  local width=tonumber(page:GetWidth())or 640;if width<300 then width=640 end
  page.role:SetWidth(math.min(330,math.max(210,width*.55)));page.search:SetWidth(math.min(250,math.max(150,width*.36)))
  local bw=math.min(220,(width-12)/2);page.primary:SetWidth(bw);page.cancel:SetWidth(bw);page.keep:SetWidth(bw)
  if page.document.spec then page.document.Set(page.document.spec)end
 end
 page.book.onLayout=layout;page.Layout=function()if page.book.Layout then page.book.Layout()end;layout()end
end
