local _,ns=...
local U,M,A,P,I,T=ns.UI,ns.Planner,ns.API,ns.Advice,ns.Impact,ns.Theme
local C=T.colors
local slotStates={
 missing={color={1,.22,.18},priority=0},
 enhanced={color={1,.55,.12},priority=1},
 top={color={.25,1,.40},priority=2},
 unknown={color={.58,.59,.60},priority=3},
 blocked={color={.58,.59,.60},priority=4},
 none={color={.58,.59,.60},priority=4},
 empty={color={.58,.59,.60},priority=5},
}
local W,H=1260,800
local ITEM_PAGE,ENCHANT_PAGE=4,4
local function place(f,x,y) f:ClearAllPoints();f:SetPoint('TOPLEFT',x,-y) end
local function label(parent,value,x,y,w,font,color)
 local t=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlightSmall')
 T.Font(t,font=='GameFontNormalLarge' and 26 or font=='GameFontHighlight' and 15 or 12)
 place(t,x,y);t:SetWidth(w);t:SetJustifyH('LEFT');t:SetJustifyV('TOP');t:SetText(value);t:SetTextColor(unpack(color or C.text));return t
end
local function button(parent,value,x,y,w,fn)
 local b=CreateFrame('Button',nil,parent,'BackdropTemplate');b:SetSize(w,28);place(b,x,y)
 local text=b:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');text:SetPoint('CENTER');text:SetWidth(w-14);b:SetFontString(text);b:SetText(value)
 b:SetScript('OnClick',fn);b:SetScript('OnEnter',function(self) T.Button(self,true) end)
 b:SetScript('OnLeave',function(self) T.Button(self);GameTooltip:Hide() end);T.Button(b);return b
end
local function searchStyle(e)
 T.Surface(e);e:SetTextInsets(30,8,0,0)
 local icon=e:CreateTexture(nil,'ARTWORK');icon:SetTexture('Interface\\Common\\UI-Searchbox-Icon');icon:SetSize(16,16);icon:SetPoint('LEFT',8,0)
 local function paint(focused)
  e:SetBackdropColor(.035,.043,.050,1)
  e:SetBackdropBorderColor(unpack(focused and {1,.80,.38,1} or {.43,.46,.46,1}))
 end
 e:SetScript('OnEditFocusGained',function() paint(true) end)
 e:SetScript('OnEditFocusLost',function() paint(false) end);paint(false)
end
local function paintQuality(b,hover)
 T.Button(b,hover);b.mark:SetShown(b.active)
 b:GetFontString():SetTextColor(unpack(b.quality.color))
 b:GetFontString():SetAlpha(b.active and 1 or .5)
end
local function entry(parent,x,y,w,h)
 local b=button(parent,'',x,y,w);b.uiStyle='card';T.Button(b);b:SetHeight(h)
 b.name=label(b,'',50,7,w-60,'GameFontHighlight',C.text);b.name:SetHeight(28)
 b.meta=label(b,'',50,36,w-60,nil,C.muted);b.meta:SetHeight(h-40)
 b.icon=b:CreateTexture(nil,'ARTWORK');b.icon:SetSize(34,34);b.icon:SetPoint('TOPLEFT',8,-10);T.IconBorder(b,b.icon)
 return b
end
local function pageWheelArea(parent,x,y,w,h,cards,changePage)
 local area=CreateFrame('Frame',nil,parent);area:SetSize(w,h);place(area,x,y)
 local function wheel(_,delta)
  if delta~=0 then changePage(delta>0 and -1 or 1) end
 end
 T.CaptureWheel(area,wheel)
 for _,card in ipairs(cards) do T.CaptureWheel(card,wheel) end
 return area
end
local function recipeList(parent,x,y,w,h,cards,count)
 local list={height=h}
 local scroll=CreateFrame('ScrollFrame',nil,parent);list.scroll=scroll;scroll:SetSize(w-14,h);place(scroll,x,y)
 local content=CreateFrame('Frame',nil,scroll);list.content=content;content:SetSize(w-14,h);scroll:SetScrollChild(content)
 local bar=CreateFrame('Slider',nil,parent,'BackdropTemplate');list.bar=bar;bar:SetSize(6,h);place(bar,x+w-8,y)
 bar:SetOrientation('VERTICAL');bar:SetMinMaxValues(0,0);bar:SetValueStep(30);T.Scrollbar(bar)
 bar:SetScript('OnValueChanged',function(_,value) scroll:SetVerticalScroll(value) end)
 local function wheel(_,delta) bar:SetValue(math.max(0,math.min(list.maximum or 0,scroll:GetVerticalScroll()-delta*44))) end
 T.CaptureWheel(scroll,wheel);T.CaptureWheel(bar,wheel)
 for i=1,count do cards[i]=entry(content,0,0,w-14,82);T.CaptureWheel(cards[i],wheel) end
 return list
end
local function finishRecipeList(list,height,key)
 list.content:SetHeight(math.max(list.height,height));list.maximum=math.max(0,height-list.height)
 list.bar:SetMinMaxValues(0,list.maximum)
 list.bar:SetValue(list.key==key and math.min(list.scroll:GetVerticalScroll(),list.maximum) or 0)
 list.key=key;list.bar:SetShown(list.maximum>0)
end
local function recipeCard(b,option,requirement,blocked,y)
 local Q=ns.Presentation
 place(b,0,y);T.ClearLinks(b);Q.Hide(b)
 T.IconHover(b,b.icon,option,function() local click=b:GetScript('OnClick');if click then click(b,'LeftButton') end end)
 b.name:SetText(T.ItemName(option.itemID,A.Name(option)));b.name:SetHeight(0);b.name:SetWidth(b:GetWidth()-94);b.icon:SetTexture(A.Icon(option))
 Q.Info(b,option,b:GetWidth()-34,10)
 if not b.benefit then b.benefit=label(b,'',12,0,b:GetWidth()-24,'GameFontHighlight',C.better) end
 T.Font(b.name,16);b.icon:SetSize(40,40);T.IconBorder(b,b.icon);b.name:SetWidth(b:GetWidth()-108);place(b.name,60,10)
 local top=14+b.name:GetStringHeight()+4
 b.benefit:SetText(Q.Bonus(option));b.benefit:SetWidth(b:GetWidth()-74);T.BenefitText(b.benefit,option);place(b.benefit,60,top)
 b.meta:SetText('');b.meta:Hide()
 local materials=ns.Shopping.Requirements(option,'materials');local nextY=top+b.benefit:GetStringHeight()+10
 local bottom=Q.MaterialIcons(b,b,materials,60,nextY,b:GetWidth()-174,function() local click=b:GetScript('OnClick');if click then click(b,'LeftButton') end end)
 if not b.cost then b.cost=label(b,'',0,0,100,nil,C.gold);b.cost:SetJustifyH('RIGHT') end
 b.cost:SetText(Q.Cost(materials,true));place(b.cost,b:GetWidth()-112,nextY+6)
 local height=math.max(bottom,nextY+b.cost:GetStringHeight()+6)+12;b:SetHeight(height)
 return y+height+12
end
local function itemTip(owner,ref)
 GameTooltip:SetOwner(owner,'ANCHOR_RIGHT');GameTooltip:SetHyperlink(ref);GameTooltip:Show()
end
local function colored(value,text)
 local c=value>0 and C.better or value<0 and C.worse or C.equal
 return string.format('|cff%02x%02x%02x',math.floor(c[1]*255),math.floor(c[2]*255),math.floor(c[3]*255))..text..'|r'
end
function U.PlannerMessage(message)
 if U.planner then U.planner.message:SetText(message or '') end
end
function U.PlannerProfiles()
 local f=U.planner
 f.classMenu:Hide()
 if f.menu:IsShown() then f.menu:Hide();return end
 local profiles=M.Profiles()
 for _,b in ipairs(f.menu.buttons) do b:Hide() end
 for i,p in ipairs(profiles) do
  local profile=p;local b=f.menu.buttons[i]
  if not b then b=button(f.menu,'',8,8+(i-1)*30,350);f.menu.buttons[i]=b end
  b:SetText(profile.label..(profile.index and (' · '..P.roles[profile.role]) or ''))
  b.active=profile.id==M.Profile().id;T.Button(b)
  b:SetScript('OnClick',function() M.State().profile=profile.id;f.enchantPage=1;f.recipePage=1;f.menu:Hide();U.RefreshPlanner() end);b:Show()
 end
 f.menu:SetHeight(#profiles*30+16);f.menu:Show()
end
function U.PlannerClasses()
 local f=U.planner;f.menu:Hide()
 if f.classMenu:IsShown() then f.classMenu:Hide();return end
 for i,class in ipairs(P.classes) do
  local entry=class;local b=f.classMenu.buttons[i]
  if not b then b=button(f.classMenu,'',8,8+(i-1)*30,174);f.classMenu.buttons[i]=b end
  b:SetText(entry.label);b.active=M.Class()==entry.id;T.Button(b)
  b:SetScript('OnClick',function()
   M.SetClass(entry.id);f.enchantPage=1;f.recipePage=1;f.classMenu:Hide();U.PlannerMessage();U.RefreshPlanner()
  end);b:Show()
 end
 f.classMenu:SetHeight(#P.classes*30+16);f.classMenu:Show()
end
local function create()
 local f=CreateFrame('Frame','GearWiseForeverPlanner',UIParent,'BackdropTemplate');U.planner=f
 f:SetSize(W,H);f:SetPoint('CENTER');f:SetFrameStrata('HIGH');f:SetClampedToScreen(true);f:EnableMouse(true);f:SetMovable(true);T.Window(f,W,H)
 local scale=math.min(1,(UIParent:GetWidth()-30)/W,(UIParent:GetHeight()-30)/H);f:SetScale(math.max(.35,scale))
 f.headerLogo=T.HeaderLogo(f,22,5,36)
 f.brand=T.BrandText(label(f,'GearWise',68,8,720,'GameFontNormalLarge',C.gold),29)
 f.equipmentPanel=T.Group(f,12,132,232,584)
 local drag=CreateFrame('Frame',nil,f);drag:SetSize(W-80,40);place(drag,10,7);drag:EnableMouse(true);drag:RegisterForDrag('LeftButton')
 drag:SetScript('OnDragStart',function() f:StartMoving() end)
 drag:SetScript('OnDragStop',function()
  f:StopMovingOrSizing();local x,y=f:GetCenter();local ux,uy=UIParent:GetCenter();local scale=f:GetEffectiveScale()/UIParent:GetEffectiveScale()
  M.State().position={x=x*scale-ux,y=y*scale-uy}
 end)
 local close=button(f,'×',W-50,12,28,function() f:Hide() end);close.danger=true;close.fontSize=20;T.Button(close)
 f.compact=button(f,'',W-136,12,28,U.CompactPlanner);T.ViewSymbol(f.compact,true)
 f.compact:SetScript('OnEnter',function(self) T.Button(self,true);GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetText(ns.L('Kompakte Ansicht'));GameTooltip:Show() end)

 f.classButton=button(f,'',22,98,160,U.PlannerClasses)

 f.profile=button(f,'',192,98,260,U.PlannerProfiles)
 f.activeProfile=button(f,ns.L('Aktive Skillung'),462,98,160,function() M.UseActiveProfile();f.enchantPage=1;f.recipePage=1;f.menu:Hide();f.classMenu:Hide();U.RefreshPlanner() end)
 f.summary=label(f,'',782,101,250,nil,C.gold);f.summary:SetHeight(40);f.summary:Hide()
 f.menu=CreateFrame('Frame',nil,f,'BackdropTemplate');T.Surface(f.menu);T.CaptureWheel(f.menu);f.menu:SetWidth(366);T.WindowMenu(f.menu,f);f.menu:SetPoint('TOPLEFT',f.profile,'BOTTOMLEFT',0,-3);f.menu.buttons={};f.menu:Hide()
 f.classMenu=CreateFrame('Frame',nil,f,'BackdropTemplate');T.Surface(f.classMenu);T.CaptureWheel(f.classMenu);f.classMenu:SetWidth(190);T.WindowMenu(f.classMenu,f);f.classMenu:SetPoint('TOPLEFT',f.classButton,'BOTTOMLEFT',0,-3);f.classMenu.buttons={};f.classMenu:Hide()
 f.planMode=button(f,ns.L('Meine Ausrüstung'),22,56,194,function() U.SetPlannerView('gear') end)
 f.wishMode=button(f,ns.L('Wunschpläne'),1082,98,154,function() U.SetPlannerView('plan') end)
 f.recipeMode=button(f,ns.L('Rezepte'),226,56,146,function() U.SetPlannerView('recipes') end)
 label(f,ns.L('Ausrüstung'),22,145,100,'GameFontHighlight',C.gold)
 f.wishMode.plain=true;f.wishMode.link=true;T.Button(f.wishMode)
 f.missingFirst=button(f,ns.L('Fehlende zuerst'),122,143,110,function() M.State().missingFirst=not (M.State().missingFirst~=false);U.RefreshPlanner() end)
 f.slots={};local y=174
 for _,s in ipairs(ns.slots) do
  if ns.slotByID[s.id] then
   local slot=s.id;local b=button(f,s.label,18,y,218,function() f.slot=slot;f.itemPage=1;f.enchantPage=1;f.recipePage=1;U.PlannerMessage();U.RefreshPlanner() end)
   b:SetHeight(32);b.uiStyle='slot';b.fontSize=11;T.Button(b)
   local title=b:GetFontString();title:ClearAllPoints();title:SetPoint('TOPLEFT',43,-3);title:SetWidth(166);title:SetJustifyH('LEFT');title:SetWordWrap(false);title:SetHeight(13)
   b.detail=label(b,'',43,17,152,nil,C.muted);T.Font(b.detail,13);b.detail:SetHeight(15);b.detail:SetWordWrap(false)
   b.itemIcon=b:CreateTexture(nil,'ARTWORK');b.itemIcon:SetSize(26,26);b.itemIcon:SetPoint('TOPLEFT',8,-3);T.IconBorder(b,b.itemIcon)
   b.statusMark=b:CreateTexture(nil,'OVERLAY');b.statusMark:SetTexture('Interface\\Buttons\\WHITE8X8');b.statusMark:SetSize(7,7);b.statusMark:SetPoint('TOPRIGHT',-9,-12);b.statusMark:SetRotation(math.pi/4)
   f.slots[slot]=b;y=y+33
  end
 end
 f.resetSlot=button(f,ns.L('Slot zurücksetzen'),18,674,104,function() if M.State().view=='gear' then M.GearPlan()[tostring(f.slot)]=nil;if f.upgrade then f.upgrade.selected[f.slot]=nil end else M.Reset(f.slot) end;U.PlannerMessage();U.RefreshPlanner() end)
 f.resetPlan=button(f,ns.L('Gesamten Plan leeren'),128,674,108,function() if M.State().view=='gear' then M.State().gearSlots={};if f.upgrade then f.upgrade.selected={} end else M.Reset() end;U.PlannerMessage();U.RefreshPlanner() end)
 f.resetSlot.fontSize=11;f.resetPlan.fontSize=11;T.Button(f.resetSlot);T.Button(f.resetPlan)
 local body=CreateFrame('Frame',nil,f);f.planBody=body;body:SetSize(W,H-34);body:SetPoint('TOPLEFT',40,-34)
 label(body,ns.L('Itemdatenbank'),210,120,265,'GameFontHighlight',C.gold)
 f.allQualities=button(body,ns.L('Alle Qualitäten'),491,116,113,function() M.ShowAllQualities();f.itemPage=1;U.RefreshPlanner() end);f.allQualities:SetHeight(22)
 label(body,ns.L('Dauerhafte Verbesserung'),624,120,410,'GameFontHighlight',C.gold)
 local e=CreateFrame('EditBox',nil,body,'BackdropTemplate');f.search=e;e:SetSize(394,28);place(e,210,143);searchStyle(e);e:SetFontObject('GameFontHighlightSmall');e:SetAutoFocus(false)
 f.placeholder=label(e,ns.L('Suchen: Name, Item-ID oder Itemlink'),30,7,354,nil,C.text)
 e:SetScript('OnTextChanged',function(self)
  f.placeholder:SetShown(self:GetText()=='');f.itemPage=1
  U.RefreshPlanner()
 end)
 e:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
 f.qualityFilters={}
 for i,quality in ipairs(M.qualities) do
  local q=quality
  local first=i<=3;local index=first and i-1 or i-4
  local width=first and 128 or 95
  local b=button(body,q.label,210+index*(width+5),first and 178 or 205,width,function()
   M.ToggleQuality(q.id);f.itemPage=1;U.RefreshPlanner()
  end)
  b:SetHeight(24);b.quality=q
  local title=b:GetFontString();title:ClearAllPoints();title:SetPoint('LEFT',24,0);title:SetWidth(width-28);title:SetJustifyH('LEFT')
  local box=CreateFrame('Frame',nil,b,'BackdropTemplate');box:SetSize(13,13);box:SetPoint('LEFT',7,0);T.Surface(box)
  b.mark=box:CreateTexture(nil,'OVERLAY');b.mark:SetTexture('Interface\\Buttons\\UI-CheckBox-Check');b.mark:SetSize(19,19);b.mark:SetPoint('CENTER')
  b:SetScript('OnEnter',function(self) paintQuality(self,true) end)
  b:SetScript('OnLeave',function(self) paintQuality(self);GameTooltip:Hide() end)
  f.qualityFilters[q.id]=b
 end
 f.itemEmpty=label(body,ns.L('Keine Items gefunden. Suche oder Qualitätsfilter ändern.'),222,254,366,nil,C.muted);f.itemEmpty:SetHeight(54)
 f.current=button(body,ns.L('Getragenes Item'),624,143,199,function() M.Reset(f.slot);U.PlannerMessage();U.RefreshPlanner() end)
 button(body,ns.L('Ohne Verzauberung'),831,143,205,function() M.SelectEnchant(f.slot,false);U.PlannerMessage();U.RefreshPlanner() end)
 f.items={};for i=1,ITEM_PAGE do f.items[i]=entry(body,210,238+(i-1)*58,394,54) end
 f.enchants={};f.enchantList=recipeList(body,624,180,412,285,f.enchants,ENCHANT_PAGE)
 f.itemWheel=pageWheelArea(body,210,238,394,228,f.items,function(step)
  f.itemPage=f.itemPage+step;U.RefreshPlanner()
 end)
 f.enchantWheel=f.enchantList.scroll
 f.enchantEmpty=label(body,'',638,204,380,'GameFontHighlight',C.muted);f.enchantEmpty:SetHeight(90)
 f.itemPrev=button(body,'<',210,477,32,function() f.itemPage=math.max(1,f.itemPage-1);U.RefreshPlanner() end)
 f.itemNext=button(body,'>',572,477,32,function() f.itemPage=f.itemPage+1;U.RefreshPlanner() end)
 f.itemCount=label(body,'',250,484,318,nil,C.muted)
 f.enchantPrev=button(body,'<',624,477,32,function() f.enchantPage=math.max(1,f.enchantPage-1);U.RefreshPlanner() end)
 f.enchantNext=button(body,'>',1004,477,32,function() f.enchantPage=f.enchantPage+1;U.RefreshPlanner() end)
 f.enchantCount=label(body,'',666,484,330,nil,C.muted)
 f.shopping=button(body,ns.L('Auf Einkaufsliste'),624,509,412,function()
  local choice=M.Preview(f.slot).option
  local mode=choice and choice.itemID and choice.tradable~=false and 'item' or 'materials'
  if choice then local ok,message=ns.Shopping.Append(f.slot,choice,mode);U.PlannerMessage(message);U.RefreshPlanner() end
 end)
 f.chosen=label(body,'',210,513,394,'GameFontHighlight',C.gold);f.chosen:SetHeight(32)
 local comparison=CreateFrame('Frame',nil,body,'BackdropTemplate');f.comparisonBox=comparison
 comparison:SetSize(826,170);place(comparison,210,548);T.Surface(comparison)
 comparison:SetBackdropColor(.035,.03,.021,1);comparison:SetBackdropBorderColor(.55,.42,.20,1)
 f.comparisonTitle=label(comparison,'',12,10,570,'GameFontHighlight',C.gold)
 f.reviewPlan=button(comparison,ns.L('Gesamtplan ansehen'),598,6,180,function() U.ShowUpgradeReview('plan') end)
 f.comparisonInfo=button(comparison,'i',790,7,24)
 f.comparisonInfo:SetHeight(24)
 f.comparisonInfo:SetScript('OnEnter',function(self)
  T.Button(self,true);GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetText(f.comparisonTitle:GetText())
  GameTooltip:AddLine(f.comparisonLimits or '',.82,.77,.65,true);GameTooltip:Show()
 end)
 f.compareColumns={}
 for i,definition in ipairs({{'gains',ns.L('Zuwächse'),C.better},{'losses',ns.L('Verluste'),C.worse},{'impact',ns.L('Abgeleitete Wirkung'),C.gold}}) do
  local x=12+(i-1)*270
  local column={};f.compareColumns[definition[1]]=column
  column.heading=label(comparison,definition[2],x,36,248,'GameFontHighlight',definition[3])
  local scroll=CreateFrame('ScrollFrame',nil,comparison);column.scroll=scroll;scroll:SetSize(246,110);place(scroll,x,56)
  local content=CreateFrame('Frame',nil,scroll);column.content=content;content:SetSize(246,110);scroll:SetScrollChild(content)
  column.text=label(content,'',0,0,240,'GameFontHighlight',C.text);column.text:SetSpacing(5)
  local bar=CreateFrame('Slider',nil,comparison,'BackdropTemplate');column.bar=bar;bar:SetSize(6,110);place(bar,x+250,56)
  bar:SetOrientation('VERTICAL');bar:SetMinMaxValues(0,0);bar:SetValueStep(24);T.Scrollbar(bar)
  bar:SetScript('OnValueChanged',function(_,value) scroll:SetVerticalScroll(value) end)
  local function wheel(_,delta) bar:SetValue(math.max(0,math.min(column.maximum or 0,scroll:GetVerticalScroll()-delta*40))) end
  T.CaptureWheel(scroll,wheel);T.CaptureWheel(bar,wheel)
 end
 f.comparison=f.compareColumns.gains.text;f.scroll=f.compareColumns.gains.scroll;f.compareBar=f.compareColumns.gains.bar
 f.message=label(f,'',18,H-28,W-90,nil,C.gold)
 U.CreateCartLauncher(f)
 f.slot=5;f.itemPage=1;f.enchantPage=1;f.recipePage=1;f.recipeSelected={}
 f:SetScript('OnHide',function() f.menu:Hide();f.classMenu:Hide();GameTooltip:Hide() end)
 T.LanguagePicker(f,12)
 tinsert(UISpecialFrames,'GearWiseForeverPlanner');f:Hide()
end
function U.SetPlannerView(view)
 if view~='plan' and view~='recipes' and view~='gear' then return end
 M.State().view=view
 local f=U.planner
 if f then f.menu:Hide();f.classMenu:Hide();f.search:ClearFocus();U.PlannerMessage();U.RefreshPlanner() end
end
local RECIPE_PAGE=7
local function createReference(f)
 local ref=CreateFrame('Frame',nil,f);f.reference=ref;ref:SetSize(988,574);place(ref,250,140)
 label(ref,ns.L('Rezepte für den gewählten Slot'),0,0,444,'GameFontHighlight',C.gold)
 label(ref,ns.L('Rezeptdetails'),466,0,500,'GameFontHighlight',C.gold)

 local search=CreateFrame('EditBox',nil,ref,'BackdropTemplate');ref.search=search;search:SetSize(444,28);place(search,0,24);searchStyle(search)
 search:SetFontObject('GameFontHighlightSmall');search:SetAutoFocus(false)
 ref.placeholder=label(search,ns.L('Rezeptname, Wirkung, Beruf oder ID'),30,7,354,nil,C.text)
 search:SetScript('OnTextChanged',function(self) ref.placeholder:SetShown(self:GetText()=='');f.recipePage=1;ref.detailScroll:SetVerticalScroll(0);U.RefreshPlanner() end)
 search:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
 ref.cards={};ref.recipeList=recipeList(ref,0,64,444,422,ref.cards,RECIPE_PAGE);ref.recipeWheel=ref.recipeList.scroll
 ref.previous=button(ref,'<',0,495,32,function() f.recipePage=math.max(1,f.recipePage-1);U.RefreshPlanner() end)
 ref.next=button(ref,'>',412,495,32,function() f.recipePage=f.recipePage+1;U.RefreshPlanner() end)
 ref.count=label(ref,'',42,502,315,nil,C.muted)
 ref.empty=label(ref,ns.L('Keine passenden Rezepte.'),10,82,374,nil,C.muted);ref.empty:SetHeight(60)
 local scroll=CreateFrame('ScrollFrame',nil,ref);ref.detailScroll=scroll;scroll:SetSize(487,484);place(scroll,466,24)
 local content=CreateFrame('Frame',nil,scroll);content:SetWidth(481);content:SetHeight(484);scroll:SetScrollChild(content)
 ref.details=label(content,'',0,0,473,nil,C.text)
 local bar=CreateFrame('Slider',nil,ref,'BackdropTemplate');ref.bar=bar;bar:SetSize(6,484);place(bar,950,24);bar:SetOrientation('VERTICAL');bar:SetMinMaxValues(0,0);bar:SetValueStep(25);T.Scrollbar(bar)
 bar:SetScript('OnValueChanged',function(_,value) scroll:SetVerticalScroll(value) end)
 scroll:EnableMouseWheel(true);scroll:SetScript('OnMouseWheel',function(self,delta) bar:SetValue(math.max(0,math.min(ref.maximum or 0,self:GetVerticalScroll()-delta*30))) end)
 ref.shopping=button(ref,ns.L('Auf Einkaufsliste'),466,537,500,function()
  local option=ns.byID[f.recipeSelected[f.slot]]
  local mode=option and option.itemID and option.tradable~=false and 'item' or 'materials'
  if option then local ok,message=ns.Shopping.Append(f.slot,option,mode);U.PlannerMessage(message);U.RefreshPlanner() end
 end)
 ref.source=button(ref,ns.L('Rezeptquelle'),0,537,444,function()
  local option=ns.byID[f.recipeSelected[f.slot]];if option then U.ShowSource(option) end
 end)
end
function U.RefreshReference()
 local f=U.planner;if not f.reference then createReference(f) end
 local ref=f.reference;ref:Show();T.Primary(ref.shopping)
 local found=M.Recipes(f.slot,ref.search:GetText());local pages=math.max(1,math.ceil(#found/RECIPE_PAGE))
 f.recipePage=math.max(1,math.min(f.recipePage,pages))
 ref.count:SetText(#found..ns.L(' Rezepte · ')..f.recipePage..' / '..pages)
 ref.previous:SetEnabled(f.recipePage>1);ref.next:SetEnabled(f.recipePage<pages);ref.empty:SetShown(#found==0)
 ref.empty:SetText(ns.bySlot[f.slot] and ns.L('Keine Rezepte zu dieser Suche.') or (ns.L(ns.slotNotes[f.slot]) or ns.L('Für diesen Slot sind keine bestätigten Rezepte hinterlegt.')))
 local selected
 for _,entry in ipairs(found) do if entry.option.id==f.recipeSelected[f.slot] then selected=entry.option;break end end
 if not selected and found[1] then selected=found[1].option;f.recipeSelected[f.slot]=selected.id end
 if not selected then f.recipeSelected[f.slot]=nil end
 local cardY=0
 for i,b in ipairs(ref.cards) do
  local entry=found[(f.recipePage-1)*RECIPE_PAGE+i]
  if entry then
   local option=entry.option;b:Show();cardY=recipeCard(b,option,nil,false,cardY)
   b.active=selected and option.id==selected.id;T.Button(b)
   b:SetScript('OnClick',function(_,mouseButton) if A.ChatLink(option,nil,mouseButton) then return end;f.recipeSelected[f.slot]=option.id;ref.detailScroll:SetVerticalScroll(0);U.PlannerMessage();U.RefreshPlanner() end)
   b:SetScript('OnEnter',function(self) T.Button(self,true);A.ShowRecipeTooltip(self,option) end)
  else b:Hide() end
 end
 finishRecipeList(ref.recipeList,cardY,f.slot..':'..f.recipePage..':'..ref.search:GetText())
 local Q=ns.Presentation;local lines={};local detailMaterials={}
 local detailContent=ref.detailScroll:GetScrollChild();T.ClearLinks(detailContent);Q.Hide(ref)
 if detailContent.recipeInfo then detailContent.recipeInfo:Hide() end
 if selected then
  lines[#lines+1]='|cffffcc60'..A.Name(selected)..'|r'
  lines[#lines+1]='|cff8cffa6'..Q.Bonus(selected)..'|r'
  local proc=ns.Procs.Evaluate(selected,f.slot,(M.Profile()))
  if proc then for _,value in ipairs(proc.lines) do lines[#lines+1]='|cff8cffa6'..value.text..'|r' end end
  local mode=selected.itemID and selected.tradable~=false and 'item' or 'materials'
  detailMaterials=ns.Shopping.Requirements(selected,mode)
  ref.shopping:SetText(ns.L('Warenkorb +1'));ref.shopping:SetEnabled(#detailMaterials>0)
  Q.Info(detailContent,selected,445,0,proc)
 else lines[1]=ns.L('Wähle einen Slot und ein Rezept.');ref.shopping:SetEnabled(false) end
 ref.source:SetEnabled(selected~=nil)
 ref.details:SetWidth(435);ref.details:SetSpacing(6);ref.details:SetHeight(0);ref.details:SetText(table.concat(lines,'\n\n'))
 local nextY=ref.details:GetStringHeight()+18
 nextY=Q.Materials(detailContent,ref,detailMaterials,0,nextY,473)
 if not ref.cost then ref.cost=label(detailContent,'',0,0,473,nil,C.gold) end
 ref.cost:SetShown(#detailMaterials>0);ref.cost:SetText(ns.L('Materialkosten: ')..Q.Cost(detailMaterials));place(ref.cost,0,nextY+8);nextY=nextY+32
 local height=math.max(484,nextY+8)
 ref.detailScroll:GetScrollChild():SetHeight(height);ref.maximum=height-484
 ref.bar:SetMinMaxValues(0,ref.maximum);ref.bar:SetValue(math.min(ref.detailScroll:GetVerticalScroll(),ref.maximum));ref.bar:SetShown(ref.maximum>0)
 f.summary:SetText(ns.slotByID[f.slot].label..' · '..#found..ns.L(' Rezepte\nOhne Itemauswahl'));f.summary:SetTextColor(unpack(C.gold))
end
function U.RefreshPlanner()
 local f=U.planner;if not f or not f:IsShown() then return end
 local view=M.State().view or 'gear';M.State().view=view
 local reference=view=='recipes';local gear=view=='gear'
 if f.upgrade then f.upgrade:SetShown(gear);f.upgrade.footer:SetShown(gear) end
 if f.planReview and f.reviewView~=view then f.planReview:Hide() end
 f.planBody:SetShown(view=='plan');f.resetSlot:SetShown(not reference);f.resetPlan:SetShown(not reference)
 f.planMode.active=gear;f.wishMode.active=view=='plan';f.recipeMode.active=reference;T.Button(f.planMode);T.Button(f.wishMode);T.Button(f.recipeMode)
 if f.reference then f.reference:SetShown(reference);if not reference then f.reference.search:ClearFocus() end end
 f.missingFirst:SetShown(gear);f.missingFirst.active=M.State().missingFirst~=false;T.Button(f.missingFirst)
 local profile=M.Profile();f.classButton:SetText(P.ClassName(M.Class())..'  v');f.profile:SetText(profile.label..'  v')
 for id,b in pairs(f.slots) do
  if reference then
   b.statusMark:Hide()
   b.detail:SetText(#(ns.bySlot[id] or {})..ns.L(' Rezepte'));b.itemIcon:SetTexture('Interface\\Icons\\Trade_Engraving');b:SetText(ns.slotByID[id].label);b.active=id==f.slot;T.Button(b)
   b:SetScript('OnEnter',function(self) T.Button(self,true) end)
  else
   local snapshot=gear and M.Current(id) or M.Preview(id);local item=M.items[M.ID(snapshot.ref)]
  b.detail:SetText(T.ItemName(snapshot.ref,item and M.Name(item) or snapshot.ref and A.ItemInfo(snapshot.ref) or ns.L('Leer'),item and item.quality))
  b.itemIcon:SetTexture(item and item.icon or snapshot.ref and select(10,A.ItemInfo(snapshot.ref)) or 'Interface\\Icons\\INV_Misc_QuestionMark')
  local planned=gear and M.GearPlan()[tostring(id)]~=nil or not gear and M.State().slots[tostring(id)]~=nil
  local state,reason=M.SlotStatus(id,snapshot);local data=slotStates[state]
  b.enhancementState=state;b.statusReason=reason
  b.statusMark:SetVertexColor(unpack(data.color));b.statusMark:Show()
  b.active=id==f.slot;b:SetText(ns.slotByID[id].label..(planned and ' *' or ''));T.Button(b)
  b:SetScript('OnEnter',function(self)
   T.Button(self,true)
   if snapshot.ref then itemTip(self,snapshot.ref) else GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetText(ns.slotByID[id].label) end
   GameTooltip:AddLine(reason,data.color[1],data.color[2],data.color[3],true)
   if state=='enhanced' then GameTooltip:AddLine(ns.L('Verzaubert heißt nicht automatisch optimal.'),.7,.7,.7,true) end
   GameTooltip:Show()
  end)
  end
 end
 local ordered={}
 for index,slot in ipairs(ns.slots) do
  if f.slots[slot.id] then
   local state=f.slots[slot.id].enhancementState
   local priority=state and slotStates[state].priority or 4
   ordered[#ordered+1]={id=slot.id,index=index,priority=priority}
  end
 end
 if gear and M.State().missingFirst~=false then table.sort(ordered,function(a,b) return a.priority==b.priority and a.index<b.index or a.priority<b.priority end) end
 for i,slot in ipairs(ordered) do place(f.slots[slot.id],18,174+(i-1)*33) end
 if reference then U.RefreshReference();return end
 if gear then U.RefreshUpgradePlan();return end
 local preview=M.Preview(f.slot);local item=M.items[M.ID(preview.ref)];local context=M.Context(f.slot,preview)
 f.chosen:SetText(ns.slotByID[f.slot].label..': '..T.ItemName(preview.ref,item and M.Name(item) or context.name or ns.L('Leer'),item and item.quality))
 for _,q in ipairs(M.qualities) do local b=f.qualityFilters[q.id];b.active=M.IsQualityShown(q.id);paintQuality(b) end
 local found=M.Search(f.slot,f.search:GetText());local pages=math.max(1,math.ceil(#found/ITEM_PAGE));f.itemPage=math.max(1,math.min(f.itemPage,pages))
 f.itemEmpty:SetShown(#found==0)
 f.itemCount:SetText(#found..ns.L(' Items · ')..f.itemPage..' / '..pages)
 f.itemPrev:SetEnabled(f.itemPage>1);f.itemNext:SetEnabled(f.itemPage<pages)
 for i,b in ipairs(f.items) do
  local candidate=found[(f.itemPage-1)*ITEM_PAGE+i]
  if candidate then
   A.RequestItem(candidate.id);b:Show();b.name:SetText(T.ItemName(candidate.id,M.Name(candidate),candidate.quality));b.icon:SetTexture(candidate.icon)
   b.name:SetTextColor(unpack(C.text))
   b.meta:SetText(ns.L('Itemlevel ')..candidate.itemLevel..ns.L(' · benötigt Stufe ')..candidate.requiredLevel)
   b.active=candidate.id==M.ID(preview.ref);T.Button(b)
   b:SetScript('OnEnter',function(self) T.Button(self,true);itemTip(self,'item:'..candidate.id) end)
   b:SetScript('OnClick',function(_,mouseButton)
    local query=f.search:GetText();local ref=M.ID(query)==candidate.id and M.Reference(query) or 'item:'..candidate.id..':0:'
    if A.ChatLink({itemID=candidate.id,itemRef=ref},nil,mouseButton) then return end
    local ok,message=M.SelectItem(f.slot,ref);if ok then f.enchantPage=1 end
    U.PlannerMessage(message);U.RefreshPlanner()
   end)
  else b:Hide() end
 end
 local enchants,ctx=M.Options(f.slot);local epages=math.max(1,math.ceil(#enchants/ENCHANT_PAGE));f.enchantPage=math.max(1,math.min(f.enchantPage,epages))
 f.enchantEmpty:SetShown(#enchants==0)
 f.enchantEmpty:SetText(not preview.ref and ns.L('Wähle ein Item aus der Itemdatenbank, um passende Verbesserungen zu sehen.') or not ctx.loaded and ns.L('Die Gegenstandsdaten werden geladen.') or ns.L('Für dieses Item sind keine passenden Verbesserungen im Katalog hinterlegt.'))
 f.enchantCount:SetText(#enchants>0 and (#enchants..ns.L(' Verbesserungen · ')..f.enchantPage..' / '..epages) or ns.L('Keine Verbesserungen ausgewählt'))
 f.enchantPrev:SetEnabled(f.enchantPage>1);f.enchantNext:SetEnabled(f.enchantPage<epages)
 local cardY=0
 for i,b in ipairs(f.enchants) do
  local entry=enchants[(f.enchantPage-1)*ENCHANT_PAGE+i]
  if entry then
   local o=entry.option;b:Show();b.name:SetText(T.ItemName(o.itemID,A.Name(o)));b.icon:SetTexture(A.Icon(o));b.active=preview.option and preview.option.id==o.id;T.Button(b)
   local own=ns.Rules.ProfessionStatus(o,ctx,true)
   local requirement=own and own.text or ''
   if entry.state=='blocked' then requirement=entry.reason end
   cardY=recipeCard(b,o,requirement,entry.state=='blocked',cardY)
   b:SetScript('OnClick',function(_,mouseButton) if A.ChatLink(o,nil,mouseButton) then return end;M.SelectEnchant(f.slot,o.id);U.PlannerMessage();U.RefreshPlanner() end)
   b:SetScript('OnEnter',function(self) T.Button(self,true);A.ShowRecipeTooltip(self,o) end)
  else b:Hide() end
 end
 finishRecipeList(f.enchantList,cardY,f.slot..':'..f.enchantPage..':'..tostring(preview.ref))
 local mode=preview.option and preview.option.itemID and preview.option.tradable~=false and 'item' or 'materials'
 f.shopping:SetEnabled(preview.option~=nil and #ns.Shopping.Requirements(preview.option,mode)>0)
 f.shopping:SetText(preview.option and ns.Shopping.AddLabel(f.slot,preview.option,mode) or ns.L('Zuerst eine Verbesserung wählen'))
 local result=M.Compare(f.slot);local columns={gains={},losses={},impact={}}
 local stats=M.StatLines(result.delta)
 table.sort(stats,function(a,b)
  local aw,bw=math.abs(a.value*P.Weight(profile,a.key)),math.abs(b.value*P.Weight(profile,b.key))
  if aw~=bw then return aw>bw end
  return a.key<b.key
 end)
 for _,line in ipairs(stats) do
  local group=line.value>0 and columns.gains or columns.losses
  group[#group+1]=colored(line.value,line.text)
 end
 -- Effects only: item eligibility and incomplete-data notes belong outside these values.
 local effects={}
 for index,line in ipairs(result.impact.lines) do effects[#effects+1]={line=line,index=index} end
 local priority=profile.role=='physical' and {dps=1,crit=2} or {crit=1}
 table.sort(effects,function(a,b)
  local ap,bp=priority[a.line.kind] or 3,priority[b.line.kind] or 3
  if ap~=bp then return ap<bp end
  return a.index<b.index
 end)
 for _,entry in ipairs(effects) do columns.impact[#columns.impact+1]=colored(entry.line.value,entry.line.text) end
 for _,weapon in ipairs(result.weapons) do
  if math.abs(weapon.value)>.0001 then columns.impact[#columns.impact+1]=colored(weapon.value,'≈ '..I.Number(weapon.value)..ns.L(' Waffen-Basis-DPS · ')..weapon.label) end
 end
 for _,proc in ipairs(result.procs or {}) do
  columns.impact[#columns.impact+1]=(proc.removed and ns.L('Entfällt: ') or '')..A.Name(proc.option)..'\n'..ns.Procs.CardText(proc.option)
 end
 local limits=result.foreignClass and ns.L('Vergleichsbasis: deine angelegte Ausrüstung · reine Itemwerte') or ns.L('Basiswerte · Umrechnung mit aktiven Talenten · ohne Procs und Setboni')
 if not result.complete then limits=ns.L('Teilvergleich: Item-/Verzauberungswerte fehlen.\n')..limits end
 f.comparisonLimits=ns.L('Vorschau · nur ')..ns.slotByID[f.slot].label..'\n\n'..limits
 f.comparisonTitle:SetText(result.foreignClass and (ns.L('Itemwerte für ')..P.ClassName(M.Class())..' · '..profile.label) or (ns.L('Vorschau · nur ')..ns.slotByID[f.slot].label))
 local empty={gains=ns.L('Keine berechneten Zuwächse'),losses=ns.L('Keine berechneten Verluste'),impact=ns.L('Keine abgeleitete Änderung')}
 for key,column in pairs(f.compareColumns) do
  local value=#columns[key]>0 and table.concat(columns[key],'\n') or '|cffb3a68a'..empty[key]..'|r'
  local changed=value~=column.lastText;column.lastText=value
  column.text:SetHeight(0);column.text:SetText(value)
  local height=math.max(110,column.text:GetStringHeight()+4);column.content:SetHeight(height)
  column.maximum=height-110;column.bar:SetMinMaxValues(0,column.maximum)
  local position=changed and 0 or math.min(column.scroll:GetVerticalScroll(),column.maximum)
  column.bar:SetValue(position);column.bar:SetShown(column.maximum>0)
  -- Refresh the scroll child's bounds even when the slider value itself did not change.
  if column.scroll.UpdateScrollChildRect then column.scroll:UpdateScrollChildRect() end
  column.scroll:SetVerticalScroll(position)
 end
 local total=M.Compare();f.reviewPlan:SetEnabled(total.changed>0)
 if f.planReview and f.planReview:IsShown() then U.RefreshUpgradeReview() end
 f.summary:SetText(total.changed..ns.L(' geplante Slots\n')..(result.complete and ns.L('Rollenwertung') or ns.L('Teilwertung'))..' · '..(result.verdict=='better' and ns.L('Vorteil') or result.verdict=='worse' and ns.L('Nachteil') or ns.L('Ebenbürtig')))
 f.summary:SetTextColor(unpack(C[result.complete and result.verdict or 'muted']))
end
function U.OpenPlanner()
 if not ns.enabled then return end
 if not U.planner then create() end
 local f=U.planner
 local pos=M.State().position
 if not f:IsShown() then
  f:ClearAllPoints();f:SetPoint('CENTER',UIParent,'CENTER',pos and pos.x or 0,pos and pos.y or 0)
 end
 if not M.State().entryModeMigrated then M.State().view='gear';M.State().entryModeMigrated=true end
 f:Show();T.RaiseWindow(f);U.RefreshPlanner()
end

U.PlannerWidgets={place=place,label=label,button=button,searchStyle=searchStyle,recipeList=recipeList,finishRecipeList=finishRecipeList,colored=colored}
