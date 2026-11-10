local _,ns=...
local U,M,A,P,T,S=ns.UI,ns.Planner,ns.API,ns.Advice,ns.Theme,ns.Shopping
local V=U.PlannerWidgets
local place,label,button=V.place,V.label,V.button
local C=T.colors
local PAGE=6
local function scrollArea(parent,x,y,w,h)
 local result={height=h}
 result.scroll=CreateFrame('ScrollFrame',nil,parent);result.scroll:SetSize(w-14,h);place(result.scroll,x,y)
 result.content=CreateFrame('Frame',nil,result.scroll);result.content:SetSize(w-14,h);result.scroll:SetScrollChild(result.content)
 result.bar=CreateFrame('Slider',nil,parent,'BackdropTemplate');result.bar:SetSize(6,h);place(result.bar,x+w-8,y)
 result.bar:SetOrientation('VERTICAL');result.bar:SetMinMaxValues(0,0);result.bar:SetValueStep(28);T.Scrollbar(result.bar)
 result.bar:SetScript('OnValueChanged',function(_,v) result.scroll:SetVerticalScroll(v) end)
 local function wheel(_,delta) result.bar:SetValue(math.max(0,math.min(result.maximum or 0,result.scroll:GetVerticalScroll()-delta*40))) end
 T.CaptureWheel(result.scroll,wheel);T.CaptureWheel(result.bar,wheel)
 return result
end
local function contentHeight(area,height,key)
 area.content:SetHeight(math.max(area.height,height));area.maximum=math.max(0,height-area.height)
 local position=area.key==key and math.min(area.scroll:GetVerticalScroll(),area.maximum) or 0
 area.key=key;area.bar:SetMinMaxValues(0,area.maximum);area.bar:SetValue(position);area.bar:SetShown(area.maximum>0)
 if area.scroll.UpdateScrollChildRect then area.scroll:UpdateScrollChildRect() end
 area.scroll:SetVerticalScroll(position)
end
local function resultText(result,withProcs)
 local values={gains={},losses={},impact={}}
 for _,line in ipairs(M.StatLines(result.delta)) do
  local group=line.value>0 and values.gains or values.losses;group[#group+1]=V.colored(line.value,line.text)
 end
 local sorted={}
 for index,line in ipairs(result.impact.lines) do sorted[#sorted+1]={index=index,line=line} end
 local rank=M.Profile().role=='physical' and {dps=1,crit=2} or {crit=1}
 table.sort(sorted,function(a,b) local x,y=rank[a.line.kind] or 3,rank[b.line.kind] or 3;return x==y and a.index<b.index or x<y end)
 for _,entry in ipairs(sorted) do values.impact[#values.impact+1]=V.colored(entry.line.value,entry.line.text) end
 for _,weapon in ipairs(result.weapons) do
  if math.abs(weapon.value)>.0001 then values.impact[#values.impact+1]=V.colored(weapon.value,'≈ '..ns.Impact.Number(weapon.value)..ns.L(' Waffen-Basis-DPS · ')..weapon.label) end
 end
 if withProcs~=false then
  for _,proc in ipairs(result.procs or {}) do
   values.impact[#values.impact+1]=(proc.removed and ns.L('Entfällt: ') or '')..A.Name(proc.option)..'\n'..ns.Procs.CardText(proc.option)
  end
 end
 return values
end
local function empty(group)
 return ns.L(group=='gains' and 'Keine berechneten Zuwächse' or group=='losses' and 'Keine berechneten Verluste' or 'Keine abgeleitete Änderung')
end
local function summaryCost(requirements)
 local missing=S.Missing(requirements)
 return #missing==0 and ns.Money(0) or S.PriceText(S.Estimate(missing))
end
local function drawCard(card,option,y,selected)
 local Q=ns.Presentation
 place(card,0,y);T.ClearLinks(card);card.active=selected;T.Button(card)
 card:SetScript('OnEnter',function(self) T.Button(self,true);A.ShowRecipeTooltip(self,option) end)
 card.name:SetText(T.ItemName(option.itemID,A.Name(option)));card.name:SetHeight(0);T.Font(card.name,16);place(card.name,64,10);card.name:SetWidth(card:GetWidth()-112);card.icon:SetSize(42,42);T.IconBorder(card,card.icon)
 card.icon:SetTexture(A.Icon(option));T.IconHover(card,card.icon,option,function() card:GetScript('OnClick')(card,'LeftButton') end)
 Q.Info(card,option,card:GetWidth()-34,8)
 card.meta:SetText(Q.Bonus(option));card.meta:SetWidth(card:GetWidth()-78);T.BenefitText(card.meta,option)
 local metaY=14+card.name:GetStringHeight()+4;place(card.meta,64,metaY)
 local nextY=metaY+card.meta:GetStringHeight()+10
 local materials=S.Requirements(option,'materials')
 local bottom=Q.MaterialIcons(card,card,materials,64,nextY,card:GetWidth()-175,function() card:GetScript('OnClick')(card,'LeftButton') end)
 card.cost:SetWidth(100);card.cost:SetJustifyH('RIGHT');card.cost:SetText(Q.Cost(materials,true));place(card.cost,card:GetWidth()-112,nextY+6);card.cost:SetHeight(0)
 local height=math.max(bottom,nextY+card.cost:GetStringHeight()+6)+12;card:SetHeight(height)
 return y+height+12
end
local function kindMenu(g)
 if g.kinds:IsShown() then g.kinds:Hide();return end
 g.sortMenu:Hide();T.WindowMenu(g.kinds,U.planner);g.kinds:Show()
end
local function create()
 local f=U.planner
 local g=CreateFrame('Frame',nil,f);f.upgrade=g;g:SetSize(988,574);place(g,250,140)
 g.leftPanel=T.Group(g,-6,-8,456,586);g.rightPanel=T.Group(g,458,-8,532,586)
 g.selected={};g.page=1;g.mode=ns.char.upgradeSort or 'relevance'
 if not ({relevance=true,cheapest=true,expensive=true,all=true})[g.mode] then g.mode='relevance' end
 g.title=label(g,'',0,0,444,'GameFontHighlight',C.gold);g.title:Hide()
 local target=CreateFrame('Frame',nil,g,'BackdropTemplate');g.target=target;target:SetSize(444,70);place(target,0,0);T.Surface(target)
 target.icon=target:CreateTexture(nil,'ARTWORK');target.icon:SetSize(42,42);target.icon:SetPoint('TOPLEFT',9,-12);T.IconBorder(target,target.icon)
 target.name=label(target,'',64,12,236,'GameFontHighlight',C.text);target.name:SetWordWrap(false);target.name:SetHeight(20);target.status=label(target,'',64,40,360,nil,C.muted);target.status:SetHeight(16);target.status:SetWordWrap(false)
 g.otherItem=button(target,ns.L('Anderes Item …'),310,10,124,function() U.SetPlannerView('plan') end)
 local search=CreateFrame('EditBox',nil,g,'BackdropTemplate');g.search=search;search:SetSize(444,30);place(search,0,80);V.searchStyle(search)
 search:SetFontObject('GameFontHighlightSmall');search:SetAutoFocus(false)
 g.placeholder=label(search,ns.L('Suche nach Name oder Wirkung'),30,6,350,nil,C.text)
 search:SetScript('OnTextChanged',function() g.page=1;U.RefreshPlanner() end);search:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
 g.sort=button(g,ns.L('Relevanz')..' v',0,116,240,function() g.kinds:Hide();g.sortMenu:SetShown(not g.sortMenu:IsShown());T.WindowMenu(g.sortMenu,f) end)
 g.kindButton=button(g,'',248,116,196,function() kindMenu(g) end)
 g.sortMenu=CreateFrame('Frame',nil,g,'BackdropTemplate');T.Surface(g.sortMenu);T.CaptureWheel(g.sortMenu);g.sortMenu:SetSize(230,140);g.sortMenu:SetPoint('TOPLEFT',g.sort,'BOTTOMLEFT',0,-3);g.sortMenu:Hide()
 for i,choice in ipairs({{'relevance','Relevanz'},{'cheapest','Günstigste zuerst'},{'expensive','Teuerste zuerst'},{'all','Alle · nach Name'}}) do
  local id=choice[1];button(g.sortMenu,ns.L(choice[2]),8,8+(i-1)*31,214,function() g.mode=id;ns.char.upgradeSort=id;g.page=1;g.sortMenu:Hide();U.RefreshPlanner() end)
 end
 g.kinds=CreateFrame('Frame',nil,g,'BackdropTemplate');T.Surface(g.kinds);T.CaptureWheel(g.kinds);g.kinds:SetSize(270,202);g.kinds:SetPoint('TOPRIGHT',g.kindButton,'BOTTOMRIGHT',0,-3);g.kinds.buttons={};g.kinds:Hide()
 for i,k in ipairs(U.EnhancementKinds) do
  local id=k.id;local b=button(g.kinds,ns.L(k.label),8,8+(i-1)*31,254,function()
   U.ToggleEnhancementKind(id);g.page=1;U.RefreshPlanner()
  end);g.kinds.buttons[i]=b
  b:GetFontString():ClearAllPoints();b:GetFontString():SetPoint('LEFT',30,0);b:GetFontString():SetWidth(218);b:GetFontString():SetJustifyH('LEFT')
  b.check=b:CreateTexture(nil,'OVERLAY');b.check:SetTexture('Interface\\Buttons\\UI-CheckBox-Check');b.check:SetSize(20,20);b.check:SetPoint('LEFT',7,0)
 end
 g.cards={};g.list=V.recipeList(g,0,152,444,384,g.cards,PAGE)
 for _,card in ipairs(g.cards) do card.name:SetWidth(286);card.cost=label(card,'',12,0,350,nil,C.gold) end
 g.empty=label(g,ns.L('Keine passenden Verbesserungen'),12,168,365,'GameFontHighlight',C.muted)
 g.previous=button(g,'<',0,546,30,function() g.page=math.max(1,g.page-1);U.RefreshPlanner() end)
 g.next=button(g,'>',414,546,30,function() g.page=g.page+1;U.RefreshPlanner() end)
 g.count=label(g,'',40,553,365,nil,C.muted)
 g.detailIcon=g:CreateTexture(nil,'ARTWORK');g.detailIcon:SetSize(46,46);g.detailIcon:SetPoint('TOPLEFT',470,-8);T.IconBorder(g,g.detailIcon)
 g.previewTitle=label(g,'',530,10,388,'GameFontHighlight',C.gold);T.Font(g.previewTitle,18);g.previewTitle:SetWordWrap(false);g.previewTitle:SetHeight(22)
 g.preview=scrollArea(g,466,82,500,452)
 g.previewText=label(g.preview.content,'',0,0,350,'GameFontHighlight',C.text);g.previewText:SetSpacing(5);g.previewText:Hide()
 g.benefit=label(g.preview.content,'',0,0,473,'GameFontHighlight',C.better)
 g.current=label(g,'',530,38,400,nil,C.muted)
 g.effectsTitle=label(g.preview.content,'',0,0,473,'GameFontHighlight',C.gold)
 g.changes=label(g.preview.content,'',0,0,473,nil,C.worse)
 g.materialTitle=label(g.preview.content,ns.L('Materialien'),0,0,473,'GameFontHighlight',C.gold)
 g.cost=label(g.preview.content,'',0,0,473,nil,C.gold)
 g.allValues=button(g.preview.content,ns.L('Alle Werte')..' +',0,0,160,function() g.showAll=not g.showAll;U.RefreshPlanner() end)
 g.apply=button(g,ns.L('Für diesen Slot planen'),466,546,248,function()
  local option=ns.byID[g.selected[f.slot]]
  if option and M.PlanUpgrade(f.slot,option) then U.RefreshPlanner() end
 end)
 g.remove=button(g,'−',934,42,28,function() M.GearPlan()[tostring(f.slot)]=nil;g.selected[f.slot]=nil;U.RefreshPlanner() end)
 g.cart=button(g,ns.L('Warenkorb +1'),724,546,242,function()
  local option=ns.byID[g.selected[f.slot]];if option then local ok,message=S.Append(f.slot,option,'materials');if not ok then ns.Print(message) end;U.RefreshPlanner() end
 end)
 T.Primary(g.cart)
 local footer=T.Group(f,18,717,1220,40);g.footer=footer
 g.planSummary=label(footer,'',12,13,218,'GameFontHighlight',C.gold)
 g.planDetails=button(footer,ns.L('Plan ansehen'),780,6,180,function() U.ShowUpgradeReview() end)
 g.planCost=label(footer,'',300,13,430,nil,C.text)
 g.transfer=button(footer,ns.L('In den Warenkorb'),972,6,232,function()
  M.TransferUpgrades(M.GearPlan());U.OpenCart();U.RefreshPlanner()
 end)
 T.Primary(g.transfer);T.Font(g.planSummary,16)
 g:SetScript('OnHide',function() g.kinds:Hide();g.sortMenu:Hide();g.search:ClearFocus() end)
end
function U.RefreshUpgradePlan()
 if not U.planner.upgrade then create() end
 local f=U.planner;local g=f.upgrade;g:Show();g.footer:Show()
 local slot=f.slot;if g.lastSlot~=slot then g.page=1;g.lastSlot=slot end
 local current=M.Current(slot);local context=M.Context(slot,current);local plan=M.GearPlan()
 g.title:SetText(ns.L('Verbesserungen für ')..ns.slotByID[slot].label)
 local currentItem=M.items[M.ID(current.ref)]
 g.target.name:SetText(T.ItemName(current.ref,context.name or (current.ref and A.ItemInfo(current.ref)) or ns.L('Leer'),currentItem and currentItem.quality))
 g.target.icon:SetTexture(context.texture or 'Interface\\Icons\\INV_Misc_QuestionMark')
 if current.ref then
  T.IconHover(g.target,g.target.icon,{itemRef=current.ref,itemID=M.ID(current.ref)})
 elseif g.target.iconHover then
  g.target.iconHover:Hide()
 end
 g.target.status:SetText(ns.L('Aktuell: ')..(current.option and A.Name(current.option) or (current.enchantID or 0)>0 and ns.L('Verzauberung unbekannt') or ns.L('Ohne Verzauberung')))
 g.placeholder:SetShown(g.search:GetText()=='')
 local options=M.Options(slot,current);local found={};local query=ns.Locale.Fold(g.search:GetText())
 for _,entry in ipairs(options) do
  local o=entry.option
  if U.KindEnabled(o) and (g.mode=='all' or P.Relevant(o,M.Profile())) and (query=='' or ns.Locale.Fold(A.Name(o)..' '..P.BonusText(o)):find(query,1,true)) then
   entry.cost=S.Estimate(S.Requirements(o,'materials'));found[#found+1]=entry
  end
 end
 if g.mode~='relevance' then table.sort(found,function(a,b)
  if g.mode~='all' then
   if a.cost.complete~=b.cost.complete then return a.cost.complete end
   if a.cost.total~=b.cost.total then return g.mode=='cheapest' and a.cost.total<b.cost.total or g.mode=='expensive' and a.cost.total>b.cost.total end
  end
  local an,bn=ns.Locale.Fold(A.Name(a.option)),ns.Locale.Fold(A.Name(b.option));return an==bn and a.option.id<b.option.id or an<bn
 end) end
 local pages=math.max(1,math.ceil(#found/PAGE));g.page=math.min(pages,math.max(1,g.page))
 local chosen=g.selected[slot] or (plan[tostring(slot)] and plan[tostring(slot)].enchant)
 local selected
 for _,entry in ipairs(found) do if entry.option.id==chosen then selected=entry.option;break end end
 if not selected and found[1] then selected=found[1].option end
 g.selected[slot]=selected and selected.id or nil
 local y=0
 for i,card in ipairs(g.cards) do
  local entry=found[(g.page-1)*PAGE+i]
  if entry then
   local o=entry.option;card:Show()
   card:SetScript('OnClick',function(_,mouseButton) if A.ChatLink(o,nil,mouseButton) then return end;g.selected[slot]=o.id;U.RefreshPlanner() end)
   y=drawCard(card,o,y,selected and selected.id==o.id)
  else card:Hide() end
 end
 V.finishRecipeList(g.list,y,slot..':'..g.page..':'..query..':'..g.mode)
 g.empty:SetShown(#found==0);g.empty:SetText(not current.ref and ns.L('Dieser Slot ist leer. Wähle ein Item über „Anderes Item …“.') or ns.L('Keine passenden Verbesserungen'))
 g.previous:SetEnabled(g.page>1);g.next:SetEnabled(g.page<pages);g.count:SetText(#found..ns.L(' Verbesserungen · ')..g.page..' / '..pages)
 local modeNames={relevance='Relevanz',cheapest='Günstigste zuerst',expensive='Teuerste zuerst',all='Alle · nach Name'};g.sort:SetText(ns.L(modeNames[g.mode])..' v')
 local enabled,total=U.RefreshKindFilter();g.kindButton:SetText(string.format(ns.L('Arten: %d/%d'),enabled,total)..' v')
 for i,kind in ipairs(U.EnhancementKinds) do local b=g.kinds.buttons[i];b.active=not (ns.char.excludedEnhancementKinds or {})[kind.id];b.check:SetShown(b.active);T.Button(b) end
 local detail=g.preview.content;T.ClearLinks(detail);if g.recipeInfo then g.recipeInfo:Hide() end
 local Q=ns.Presentation;local lines={};local requirements={};local nextY=0
 Q.Hide(g);g.allValues:Hide();g.effectsTitle:Hide();g.changes:Hide();g.materialTitle:Hide();g.cost:Hide();g.benefit:Hide();g.current:Hide()
 if selected then
  if g.detailID~=selected.id then g.detailID=selected.id;g.showAll=false end
  local comparison=M.Compare(slot,{[tostring(slot)]={ref=current.ref,enchant=selected.id}})
  local values=resultText(comparison,false)
  local metrics,proc=Q.Effects(selected,slot,M.Profile(),comparison.impact)
  g.previewTitle:SetText(A.Name(selected));g.detailIcon:SetTexture(A.Icon(selected));g.detailIcon:Show();g.iconBorder:Show();T.IconHover(g,g.detailIcon,selected)
  g.benefit:SetText(Q.Bonus(selected));T.BenefitText(g.benefit,selected,23);g.benefit:Show();place(g.benefit,0,0)
  nextY=g.benefit:GetStringHeight()+12
  g.current:SetText(ns.L('Aktuell: ')..(current.option and A.Name(current.option) or ns.L('Ohne Verzauberung')));g.current:SetHeight(0);place(g.current,530,38);g.current:SetWidth(390);g.current:SetHeight(18);g.current:SetWordWrap(false);g.current:Show();nextY=nextY+12
  lines[#lines+1]=g.benefit:GetText()
  if #metrics>0 then
   g.effectsTitle:SetText(proc and proc.duration and string.format(ns.L('Während der Wirkung (%d Sek.):'),proc.duration) or ns.L('Für deinen Charakter'))
   place(g.effectsTitle,0,nextY);g.effectsTitle:Show();nextY=nextY+24
   nextY=Q.Metrics(detail,g,metrics,0,nextY,473,g.showAll)
   for _,metric in ipairs(metrics) do lines[#lines+1]=metric.text end
  end
  if #metrics>4 then place(g.allValues,0,nextY);g.allValues:Show();g.allValues:SetText(ns.L('Alle Werte')..(g.showAll and ' −' or ' +'));nextY=nextY+36 end
  local changes={}
  for _,v in ipairs(values.losses) do changes[#changes+1]=v end
  if current.option and current.option.id~=selected.id and P.Stats(current.option).conditional then changes[#changes+1]='|cffff564c'..ns.L('Entfällt: ')..ns.Procs.CardText(current.option)..'|r' end
  if #changes>0 then g.changes:SetText(table.concat(changes,'\n'));g.changes:SetHeight(0);place(g.changes,0,nextY);g.changes:Show();nextY=nextY+g.changes:GetStringHeight()+12;lines[#lines+1]=g.changes:GetText() end
  requirements=S.Requirements(selected,'materials')
  if #requirements>0 then
   place(g.materialTitle,0,nextY+6);g.materialTitle:Show();nextY=nextY+32
   nextY=Q.Materials(detail,g,requirements,0,nextY,473)
   g.cost:SetText(ns.L('Materialkosten: ')..Q.Cost(requirements));place(g.cost,0,nextY+6);g.cost:Show();nextY=nextY+30
  end
  Q.Info(g,selected,938,10,proc or comparison.impact)
 else
  g.previewTitle:SetText(ns.L('Wähle einen Slot und ein Rezept.'));g.detailIcon:Hide();g.iconBorder:Hide();if g.iconHover then g.iconHover:Hide() end
 end
 g.previewText:SetText(table.concat(lines,'\n'))
 g.cart:SetEnabled(selected~=nil and #requirements>0 and M.Fits(selected,context))
 contentHeight(g.preview,nextY,slot..':'..tostring(selected and selected.id))
 local planned=plan[tostring(slot)];local same=selected and planned and planned.enchant==selected.id
 g.apply:SetEnabled(selected~=nil and not same and M.Fits(selected,context));g.apply:SetText(same and ns.L('Im Gesamtplan') or ns.L('Für diesen Slot planen'));g.remove:SetEnabled(planned~=nil);g.remove:SetShown(planned~=nil)
 local allRequirements,entries=M.UpgradeCart(plan);local names={};local purchasable=false
 for _,entry in ipairs(entries) do names[#names+1]=ns.slotByID[entry.slot].label;if #entry.requirements>0 then purchasable=true end end
 g.planSummary:SetText(#entries..ns.L(' Slots geplant'))
 g.planSummary:SetHeight(28);g.planCost:SetText(#entries>0 and summaryCost(allRequirements) or '');g.transfer:SetEnabled(purchasable);g.planDetails:SetEnabled(#entries>0)
 f.summary:SetText(#entries..ns.L(' Verbesserungen geplant'));f.summary:SetTextColor(unpack(C.gold))
 if f.planReview and f.planReview:IsShown() then U.RefreshUpgradeReview() end
end
function U.ShowUpgradeReview(view)
 local f=U.planner
 if not f.planReview then
  local r=CreateFrame('Frame',nil,f,'BackdropTemplate');f.planReview=r;r:SetSize(800,588);r:SetPoint('CENTER');T.Window(r,800,588);r:EnableMouse(true)
  label(r,ns.L('Gesamtplan'),20,16,700,'GameFontNormalLarge',C.gold)
  button(r,'x',756,12,26,function() r:Hide() end)
  r.list=scrollArea(r,18,60,764,250);r.rows={}
  r.values={}
  for i,key in ipairs({'gains','losses','impact'}) do
   local titles={gains='Zuwächse',losses='Verluste',impact='Abgeleitete Wirkung'}
   label(r,ns.L(titles[key]),20+(i-1)*255,328,236,'GameFontHighlight',key=='losses' and C.worse or C.gold)
   local area=scrollArea(r,20+(i-1)*255,352,246,136);r.values[key]=area
   area.text=label(area.content,'',0,0,226,nil,C.text);area.text:SetSpacing(4)
  end
  r.cost=label(r,'',20,512,350,nil,C.gold)
  r.transfer=button(r,ns.L('Verbesserungen in den Warenkorb'),392,504,388,function() M.TransferUpgrades(f.reviewView=='plan' and M.State().slots or M.GearPlan());U.OpenCart() end)
  r:Hide();f:HookScript('OnHide',function() r:Hide() end)
 end
 f.reviewView=view or 'gear';T.WindowMenu(f.planReview,f);f.planReview:Show();U.RefreshUpgradeReview()
end
function U.RefreshUpgradeReview()
 local f=U.planner;local r=f.planReview;local plan=f.reviewView=='plan' and M.State().slots or M.GearPlan();local requirements,entries=M.UpgradeCart(plan)
 local purchasable=false;for _,e in ipairs(entries) do if #e.requirements>0 then purchasable=true end end
 r.cost:SetText(ns.L('Warenkorb: ')..summaryCost(requirements));r.transfer:SetEnabled(purchasable)
 if f.reviewView=='plan' then
  entries={}
  for _,slot in ipairs(ns.slots) do
   local e=plan[tostring(slot.id)]
   if e~=nil then
    local item=e and M.items[M.ID(e.ref)]
    entries[#entries+1]={slot=slot.id,option=e and ns.byID[e.enchant],itemName=T.ItemName(e and e.ref,item and M.Name(item) or e and e.ref and A.ItemInfo(e.ref) or ns.L('Leer'),item and item.quality)}
   end
  end
 end
 for _,row in ipairs(r.rows) do row:Hide() end
 local y=0
 for i,entry in ipairs(entries) do
  local row=r.rows[i]
  if not row then
   row=CreateFrame('Frame',nil,r.list.content,'BackdropTemplate');r.rows[i]=row;row:SetSize(746,48);T.Surface(row)
   row.name=label(row,'',10,8,600,'GameFontHighlight',C.text);row.name:SetHeight(34)
   row.remove=button(row,ns.L('Entfernen'),638,10,96)
  end
  place(row,0,y);row:Show();row.name:SetText(ns.slotByID[entry.slot].label..': '..(entry.itemName or '')..(entry.option and ((entry.itemName and ' · ' or '')..T.ItemName(entry.option.itemID,A.Name(entry.option))) or ''))
  row.remove:SetScript('OnClick',function() if f.reviewView=='plan' then M.Reset(entry.slot) else plan[tostring(entry.slot)]=nil end;U.RefreshPlanner() end)
  y=y+54
 end
 contentHeight(r.list,y,'plan')
 local result=M.Compare(nil,plan);local values=resultText(result)
 for key,area in pairs(r.values) do
  local text=#values[key]>0 and table.concat(values[key],'\n') or empty(key)
  area.text:SetHeight(0);area.text:SetText(text);contentHeight(area,area.text:GetStringHeight()+6,text)
 end
end
