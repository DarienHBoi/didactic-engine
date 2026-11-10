local _, ns = ...
local U,A,S,R,P=ns.UI,ns.API,ns.Shopping,ns.Rules,ns.Advice
local T=ns.Theme
local C=T.colors
U.colors=C
local W,H,CW=560,760,516
local function paint(f) T.Surface(f) end
local function text(parent,value,x,y,width,font,color,align)
 local t=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
 T.Font(t,font=="GameFontNormalLarge" and 24 or font=="GameFontHighlight" and 14 or 12)
 t:SetPoint("TOPLEFT",x,-y);t:SetWidth(width);t:SetJustifyH(align or "LEFT");t:SetJustifyV("TOP");t:SetText(value)
 local c=color or C.text;t:SetTextColor(c[1],c[2],c[3]);return t
end
local function tip(owner,title,body)
 GameTooltip:SetOwner(owner,"ANCHOR_RIGHT");GameTooltip:SetText(title);GameTooltip:AddLine(body,.82,.77,.65,true);GameTooltip:Show()
end
local function button(parent,label,width,fn)
 local b=CreateFrame("Button",nil,parent,"BackdropTemplate");b:SetSize(width,28)
 local t=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");t:SetPoint("CENTER");t:SetWidth(width-14);b:SetFontString(t);b:SetText(label)
 b.Paint=function(self,hover) T.Button(self,hover) end
 b:SetScript("OnEnter",function(self) self:Paint(true);if self.tip then self.tip(self) end end)
 b:SetScript("OnLeave",function(self) self:Paint();GameTooltip:Hide() end)
 b:SetScript("OnClick",fn);b:SetScript("OnDisable",function(self) self:SetAlpha(.4) end)
 b:SetScript("OnEnable",function(self) self:SetAlpha(1) end);b:Paint();return b
end
local function place(b,x,y) b:ClearAllPoints();b:SetPoint("TOPLEFT",x,-y) end
function U.ShowSource(option)
 if not U.source then
  local f=CreateFrame("Frame","GearWiseSource",UIParent,"BackdropTemplate");paint(f);T.CaptureWheel(f)
  f:SetSize(540,122);f:SetPoint("CENTER");f:SetFrameStrata("DIALOG");f:SetToplevel(true);f:EnableMouse(true)
  text(f,ns.L("Quelle kopieren · Strg+C"),18,16,480,"GameFontHighlight",C.accent)
  local e=CreateFrame("EditBox",nil,f,"InputBoxTemplate");e:SetSize(490,26);place(e,25,48);e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed",function() f:Hide() end)
  local close=button(f,ns.L("Schließen"),96,function() f:Hide() end);place(close,424,84)
  f.edit=e;U.source=f;tinsert(UISpecialFrames,"GearWiseSource")
  f:HookScript("OnHide",S.WindowHidden)
 end
 U.source:Show();S.WindowShown(U.source);T.RaiseWindow(U.source);U.source.edit:SetText(option.source or option.listSource or "");U.source.edit:SetFocus();U.source.edit:HighlightText()
end
function U.PlacePanel()
 local f=U.panel;if not f then return end
 f:ClearAllPoints();local saved=ns.db.settings.detached
 if saved then f:SetPoint("CENTER",UIParent,"CENTER",saved.x or 0,saved.y or 0)
 elseif CharacterFrame and CharacterFrame:IsShown() then f:SetPoint("TOPLEFT",CharacterFrame,"TOPRIGHT",8,-12)
 else f:SetPoint("CENTER",UIParent,"CENTER",220,0) end
 local scale=math.min(1,math.max(.55,(UIParent:GetHeight()-32)/H))
 f:SetClampedToScreen(true);f:SetScale(scale)
end
function U.ResetScroll() if U.bar then U.bar:SetValue(0) end end
function U.SelectSlot(slot)
 if not ns.slotByID[slot] then return end
 if U.slot~=slot then U.CloseDetails();U.slot=slot;U.selected=nil;U.purchaseMode=nil;U.tab="options";U.ResetScroll();U.PlacePanel() end
 U.Refresh()
end
function U.LoadProfile()
 U.profile,U.detected=P.Detect();U.manual=false
 local saved=ns.char.preferredProfile
 if saved then
  for _,profile in ipairs(P.Profiles()) do
   if profile.id==saved then U.profile=profile;U.manual=true;return end
  end
  -- An obsolete profile must not lock the character to an unavailable selection.
  ns.char.preferredProfile=nil
 end
end
function U.SetRememberProfile(enabled)
 if enabled and U.profile then
  ns.char.preferredProfile=U.profile.id;U.manual=true
 else ns.char.preferredProfile=nil end
 U.Refresh()
end
function U.Open(slot)
 if not ns.enabled then return end
 if U.panel:IsShown() then T.RaiseWindow(U.panel);if slot then U.SelectSlot(slot) end;return end
 U.LoadProfile()
 U.slot=slot or U.slot or 5;U.tab="options";U.selected=nil;U.purchaseMode=nil
 U.PlacePanel();U.panel:Show();U.ResetScroll();U.Refresh()
end
function U.OpenCart()
 if not ns.enabled then return end
 if not U.cartWindow then U.CreateCart() end
 U.cartWindow:Show();T.RaiseWindow(U.cartWindow);U.RefreshCart()
end
function U.ToggleCart()
 if U.cartWindow and U.cartWindow:IsShown() then U.cartWindow:Hide() else U.OpenCart() end
end
function U.Toggle() if U.panel:IsShown() then U.panel:Hide() else U.Open() end end
function U.ChooseProfile(profile,automatic)
 U.CloseDetails()
 U.profile=profile;U.manual=not automatic
 if ns.char.preferredProfile then ns.char.preferredProfile=profile.id;U.manual=true end
 U.selected=nil;U.ResetScroll()
 if U.profileMenu then U.profileMenu:Hide() end
 if U.RefreshIndicators then U.RefreshIndicators() end
 U.Refresh()
end
function U.ProfileMenu()
 if U.kindMenu then U.kindMenu:Hide() end
 if U.sortMenu then U.sortMenu:Hide() end
 if U.profileMenu and U.profileMenu:IsShown() then U.profileMenu:Hide();return end
 if not U.profileMenu then
  U.profileMenu=CreateFrame("Frame",nil,U.panel,"BackdropTemplate");paint(U.profileMenu);T.CaptureWheel(U.profileMenu)
  T.WindowMenu(U.profileMenu,U.panel);U.profileMenu:SetWidth(326);U.profileMenu.buttons={}
  U.profileMenu:SetPoint("TOPLEFT",U.profileButton,"BOTTOMLEFT",0,-4)
 end
 local menu=U.profileMenu;local profiles=P.Profiles()
 -- Keep each specialization and its variants together; generic roles follow.
 local order={}
 for i,profile in ipairs(profiles) do order[profile]=i end
 table.sort(profiles,function(a,b)
  local ai,bi=a.index or math.huge,b.index or math.huge
  if ai~=bi then return ai<bi end
  return order[a]<order[b]
 end)
 for _,b in ipairs(menu.buttons) do b:Hide() end
 for i,profile in ipairs(profiles) do
  local choice=profile
  local b=menu.buttons[i]
  if not b then b=button(menu,"",310);menu.buttons[i]=b end
  b:SetText(choice.label..(choice.index and (" · "..P.roles[choice.role]) or ""));place(b,8,8+(i-1)*31)
  b:SetScript("OnClick",function() U.ChooseProfile(choice) end);b.active=choice.id==U.profile.id;b:Paint();b:Show()
 end
 menu:SetHeight(#profiles*31+16);menu:Show()
end
function U.ClearRows()
 for _,row in ipairs(U.rows) do row:Hide() end
 U.rowIndex=0;U.y=0
end
function U.Row(owner)
 owner=owner or U
 owner.rowIndex=owner.rowIndex+1;local row=owner.rows[owner.rowIndex]
 if not row then
  row=CreateFrame("Button",nil,owner.content,"BackdropTemplate");row.uiStyle="card";row:SetWidth(owner.width or CW);row:RegisterForClicks("LeftButtonUp");paint(row)
  row.texts={};row.buttons={};row.icons={};owner.rows[owner.rowIndex]=row
 end
 for _,t in ipairs(row.dividers or {}) do t:Hide() end
 for _,t in ipairs(row.chevron or {}) do t:Hide() end
 for _,t in ipairs(row.texts) do t:Hide() end
 for _,b in ipairs(row.buttons) do b:Hide() end
 for _,icon in ipairs(row.icons) do icon:Hide() end
 for _,rule in ipairs(row.rules or {}) do rule:Hide() end
 ns.Presentation.Hide(row);T.ClearLinks(row);if row.recipeInfo then row.recipeInfo:Hide() end;row.ruleIndex=0
 if row.crest then row.crest:Hide() end
 -- Rows are also reused by the cart: remove recommendation clicks before repopulating them.
 row:EnableMouse(false);row:SetScript("OnClick",nil);row:SetScript("OnEnter",nil);row:SetScript("OnLeave",nil);paint(row)
 row.textIndex=0;row.buttonIndex=0;row.iconIndex=0;row.layoutOwner=owner;place(row,0,owner.y);row:Show();return row
end
local function line(row,value,y,font,color,width,x,align)
 row.textIndex=row.textIndex+1;local t=row.texts[row.textIndex]
 if not t then t=text(row,"",14,y,CW-28);row.texts[row.textIndex]=t end
 t:ClearAllPoints();t:SetPoint("TOPLEFT",x or 14,-y);t:SetWidth(width or CW-28);t:SetJustifyH(align or "LEFT")
 t:SetFontObject(font or "GameFontHighlightSmall");T.Font(t,font=="GameFontHighlight" and 15 or 12);t:SetSpacing(2);t:SetHeight(0);t:SetText(value);t:Show()
 t:SetTextColor(unpack(color or C.text));return y+math.max(16,t:GetStringHeight())+9
end
local function action(row,label,x,y,width,fn,tooltip)
 row.buttonIndex=row.buttonIndex+1;local b=row.buttons[row.buttonIndex]
 if not b then b=button(row,label,width,fn);row.buttons[row.buttonIndex]=b end
 place(b,x,y);b:SetSize(width,28)
 if b.icon then b.icon:Hide() end
 b:GetFontString():ClearAllPoints();b:GetFontString():SetPoint("CENTER")
 b:GetFontString():SetFontObject("GameFontHighlightSmall");b:GetFontString():SetWordWrap(true)
 b:GetFontString():SetJustifyH("CENTER");b:GetFontString():SetWidth(width-14);b:SetText(label)
 b:SetScript("OnClick",fn);b.tip=tooltip;b.active=false;b.plain=false;b.primary=false;b.fontSize=(label=='+' or label=='−') and 19 or 13;b:Paint();b:SetEnabled(true);b:Show();return b
end
local function rowIcon(row,option,x,y,size)
 row.iconIndex=row.iconIndex+1;local icon=row.icons[row.iconIndex]
 if not icon then
  icon=CreateFrame("Button",nil,row,"BackdropTemplate");paint(icon)
  icon.texture=icon:CreateTexture(nil,"ARTWORK");icon.texture:SetPoint("TOPLEFT",2,-2)
  icon:SetScript("OnLeave",function() GameTooltip:Hide() end)
  row.icons[row.iconIndex]=icon
 end
 place(icon,x,y);icon:SetSize(size,size);icon.texture:SetSize(size-4,size-4);icon.texture:SetTexture(A.Icon(option))
 T.NativeHover(icon,option,nil,option.chatCount);T.IconBorder(icon,icon.texture);icon:Show()
 return icon
end
local function finish(row,y) row:SetHeight(y+12);local owner=row.layoutOwner or U;owner.y=owner.y+y+26 end
local function name(m)
 local n=A.ItemInfo(m.id);if not n then A.RequestItem(m.id) end
 return n or m.name or (ns.L("Gegenstand #")..m.id)
end
function U.CloseDetails()
 U.selected=nil;U.purchaseMode=nil;U.details=nil
end
function U.ToggleDetails(option)
 U.selected=U.selected~=option.id and option.id or nil;U.purchaseMode=nil
 U.Refresh()
end
function U.ExpandPlanner()
 local slot,selected,profile,query=U.slot,U.selected,U.profile,U.search:GetText()
 U.OpenPlanner();U.SetPlannerView('gear');local f=U.planner
 local _,class=UnitClass('player');ns.Planner.SetClass(class);ns.Planner.State().profile=profile and profile.id
 f.slot=slot;f.upgrade.selected[slot]=selected;f.upgrade.mode=U.SortMode();ns.char.upgradeSort=f.upgrade.mode;f.upgrade.search:SetText(query)
 U.panel:Hide();U.RefreshPlanner()
end
function U.CompactPlanner()
 local f=U.planner;local slot=f.slot;local g=f.upgrade;local profile=ns.Planner.Profile()
 local _,class=UnitClass('player');if profile.class~=class then profile=P.Detect() end
 U.Open(slot);U.profile=profile;U.manual=true;U.selected=g and g.selected[slot] or nil
 U.search:SetText(g and g.search:GetText() or '');if g then ns.char.recommendationSort=g.mode end
 f:Hide();U.Refresh()
end
function U.DrawOption(entry,inspection)
 local V=ns.Presentation;local option=entry.option;local row=U.Row();V.Hide(row)
 if row.optionID~=option.id then row.showAllValues=false;row.optionID=option.id end
 local selected=U.selected==option.id;row.active=selected;T.Button(row)
 local function choose(_,mouseButton) if A.ChatLink(option,nil,mouseButton) then return end;U.ToggleDetails(option) end
 row:EnableMouse(true);row:SetScript('OnClick',choose)
 row:SetScript('OnEnter',function(self) T.Button(self,true);A.ShowRecipeTooltip(self,option) end)
 row:SetScript('OnLeave',function(self) T.Button(self);GameTooltip:Hide() end)
 local icon=rowIcon(row,option,14,14,48);T.NativeHover(icon,option,function() U.ToggleDetails(option) end)
 local impact=ns.Impact.Evaluate(inspection,option,U.profile,U.impactContext)
 V.Info(row,option,CW-58,10,impact);T.Chevron(row,selected,CW-31,42)
 local y=line(row,T.ItemName(option.itemID,A.Name(option)),12,'GameFontHighlight',C.gold,CW-142,76)
 T.Font(row.texts[row.textIndex],17);y=14+row.texts[row.textIndex]:GetStringHeight()+5
 local top=y;line(row,V.Bonus(option),y,'GameFontHighlight',C.better,CW-104,76)
 local bonus=row.texts[row.textIndex];T.BenefitText(bonus,option,17);y=math.max(72,top+bonus:GetStringHeight()+12)
 local mode=option.itemID and option.tradable~=false and 'item' or 'materials'
 if selected and U.purchaseMode then mode=U.purchaseMode end
 local req=S.Requirements(option,mode)
 if selected then
  T.Divider(row,1,14,y,CW-28);y=y+14
  local values,proc=V.Effects(option,U.slot,U.profile,impact)
  if #values>0 then
   y=line(row,proc and proc.duration and string.format(ns.L('Während der Wirkung (%d Sek.):'),proc.duration) or ns.L('Für deinen Charakter'),y,nil,C.gold)
   y=V.Metrics(row,row,values,12,y,CW-24,row.showAllValues)
  end
  if #values>4 then
   action(row,ns.L('Alle Werte')..(row.showAllValues and ' −' or ' +'),12,y,128,function() row.showAllValues=not row.showAllValues;U.Refresh() end);y=y+36
  end
  local comparison=entry.comparison or P.Comparison(inspection,option,entry.state)
  for _,change in ipairs(comparison.changes or {}) do
   if change.value<0 then y=line(row,change.text,y,'GameFontHighlight',C.worse,CW-24,12) end
  end
  if option.itemID and option.tradable~=false and #S.Requirements(option,'materials')>0 then
   local a=action(row,ns.L('Materialien'),12,y,194,function() U.purchaseMode='materials';U.Refresh() end);a.active=mode=='materials';a:Paint()
   local b=action(row,ns.L('Fertigprodukt'),218,y,206,function() U.purchaseMode='item';U.Refresh() end);b.active=mode=='item';b:Paint();y=y+36
  end
  T.Divider(row,2,14,y+2,CW-28);y=y+12
  y=V.Materials(row,row,req,14,y,CW-28,function() U.ToggleDetails(option) end)
  T.Divider(row,3,14,y+4,CW-28);y=y+18
  local plan=ns.Planner.GearPlan()[tostring(U.slot)];local planned=plan and plan.enchant==option.id
  local bottom=line(row,ns.L('Materialkosten: ')..V.Cost(req,true),y+7,nil,C.text,190,14)
  action(row,ns.L(planned and 'Im Gesamtplan' or 'Planen'),212,y,116,function() ns.Planner.PlanUpgrade(U.slot,option);U.Refresh() end):SetEnabled(not planned and inspection.context.item~=nil and entry.state~='blocked')
  local buy=action(row,ns.L('Warenkorb +1'),338,y,CW-352,function() local ok,message=S.Append(U.slot,option,mode);if not ok then ns.Print(message) end;U.Refresh() end)
  T.Primary(buy);buy:SetEnabled(#req>0 and entry.state~='blocked');y=math.max(y+34,bottom)

 else
  y=V.MaterialIcons(row,row,req,76,y,CW-212,function() U.ToggleDetails(option) end)
  line(row,V.Cost(req,true),y-24,nil,C.gold,110,CW-122,'RIGHT')
 end
 finish(row,y)
end
local enhancementKinds={
 {id="enchant",label="Verzauberungen"},{id="kit",label="Rüstungssets"},
 {id="arcanum",label="Arkana & Siegel"},{id="shoulder",label="Schulterinschriften"},
 {id="scope",label="Zielfernrohre"},{id="attachment",label="Anbauteile / Sonstige"},
}
U.EnhancementKinds=enhancementKinds
function U.EnhancementKind(option)
 if option.kind=="enchant" or option.kind=="kit" or option.kind=="scope" then return option.kind end
 if option.kind=="reward" then return option.category=="Shoulder rewards" and "shoulder" or "arcanum" end
 return "attachment"
end
function U.KindEnabled(option)
 local excluded=ns.char.excludedEnhancementKinds
 return type(excluded)~="table" or excluded[U.EnhancementKind(option)]~=true
end
function U.RefreshKindFilter()
 local excluded=ns.char.excludedEnhancementKinds
 local active=0
 for i,kind in ipairs(enhancementKinds) do
  local enabled=type(excluded)~="table" or excluded[kind.id]~=true
  if enabled then active=active+1 end
  local b=U.kindMenu and U.kindMenu.buttons[i]
  if b then b.mark:SetShown(enabled);b.active=enabled;b:Paint() end
 end
 if U.kindButton then
  U.kindButton:SetText(string.format(ns.L("Arten: %d/%d"),active,#enhancementKinds).."  v")
  U.kindButton.active=active<#enhancementKinds;U.kindButton:Paint()
 end
 return active,#enhancementKinds
end
function U.ToggleEnhancementKind(id)
 local valid=false;for _,kind in ipairs(enhancementKinds) do if kind.id==id then valid=true;break end end
 if not valid then return end
 if type(ns.char.excludedEnhancementKinds)~="table" then ns.char.excludedEnhancementKinds={} end
 local excluded=ns.char.excludedEnhancementKinds;excluded[id]=not excluded[id] or nil
 local option=U.selected and ns.byID[U.selected]
 if option and not U.KindEnabled(option) then U.CloseDetails();U.selected=nil end
 U.ResetScroll();U.Refresh()
end
function U.KindMenu()
 if U.kindMenu and U.kindMenu:IsShown() then U.kindMenu:Hide();return end
 if U.sortMenu then U.sortMenu:Hide() end
 if U.profileMenu then U.profileMenu:Hide() end
 if U.panel.languagePicker then U.panel.languagePicker.menu:Hide() end
 if not U.kindMenu then
  local menu=CreateFrame("Frame",nil,U.panel,"BackdropTemplate");U.kindMenu=menu
  paint(menu);T.CaptureWheel(menu);menu:SetSize(270,#enhancementKinds*31+16);menu.buttons={}
  menu:SetPoint("TOPRIGHT",U.kindButton,"BOTTOMRIGHT",0,-3)
  for i,kind in ipairs(enhancementKinds) do
   local id=kind.id;local b=button(menu,ns.L(kind.label),254,function() U.ToggleEnhancementKind(id) end)
   menu.buttons[i]=b;place(b,8,8+(i-1)*31)
   b:GetFontString():ClearAllPoints();b:GetFontString():SetPoint("LEFT",32,0);b:GetFontString():SetWidth(214);b:GetFontString():SetJustifyH("LEFT")
   local box=CreateFrame("Frame",nil,b,"BackdropTemplate");box:SetSize(15,15);box:SetPoint("LEFT",8,0);paint(box)
   b.mark=box:CreateTexture(nil,"OVERLAY");b.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check");b.mark:SetSize(21,21);b.mark:SetPoint("CENTER")
  end
 end
 U.RefreshKindFilter();T.WindowMenu(U.kindMenu,U.panel);U.kindMenu:Show()
end
local sortChoices={{id="relevance",label=ns.L("Relevanz")},{id="expensive",label=ns.L("Teuerste zuerst")},{id="cheapest",label=ns.L("Günstigste zuerst")},{id="all",label=ns.L("Alle · nach Name")}}
function U.SortMode()
 local saved=ns.char.recommendationSort
 for _,choice in ipairs(sortChoices) do if choice.id==saved then return saved,choice.label end end
 return "relevance",ns.L("Relevanz")
end
function U.ChooseSort(mode)
 local valid=false
 for _,choice in ipairs(sortChoices) do if choice.id==mode then valid=true;break end end
 if not valid then return end
 ns.char.recommendationSort=mode
 if U.sortMenu then U.sortMenu:Hide() end
 U.ResetScroll();U.Refresh()
end
function U.SortMenu()
 if U.kindMenu then U.kindMenu:Hide() end
 if U.sortMenu and U.sortMenu:IsShown() then U.sortMenu:Hide();return end
 if U.profileMenu then U.profileMenu:Hide() end
 if not U.sortMenu then
  local menu=CreateFrame("Frame",nil,U.panel,"BackdropTemplate");U.sortMenu=menu;paint(menu);T.CaptureWheel(menu)
  T.WindowMenu(menu,U.panel);menu:SetSize(280,#sortChoices*31+52);menu:SetPoint("TOPRIGHT",U.sortButton,"BOTTOMRIGHT",0,-3);menu.buttons={}
  for i,choice in ipairs(sortChoices) do
   local mode=choice.id;menu.buttons[i]=button(menu,choice.label,264,function() U.ChooseSort(mode) end);place(menu.buttons[i],8,8+(i-1)*31)
  end
 end
 U.later:SetParent(U.sortMenu);U.later:SetWidth(264);place(U.later,8,8+#sortChoices*31);U.later:Show()
 local mode=U.SortMode()
 for i,choice in ipairs(sortChoices) do local b=U.sortMenu.buttons[i];b.active=choice.id==mode;b:Paint() end
 U.sortMenu:Show()
end
function U.OptionEntries(inspection)
 local entries,maxScore,hidden={},0,0
 local query=ns.Locale.Fold(U.search:GetText())
 local mode=U.SortMode();local all=mode=="all"
 for _,option in ipairs(ns.bySlot[U.slot] or {}) do
  local state,reason,blockKind=R.Evaluate(option,inspection.context)
  local relevant=all or P.Relevant(option,U.profile)
  local fits=not inspection.context.loaded or ns.Planner.Fits(option,inspection.context)
  if relevant and fits and U.KindEnabled(option) then
   local score=P.Score(option,U.profile)
   if state~="blocked" then maxScore=math.max(maxScore,score) end
   local match=query=="" or ns.Locale.Fold(A.Name(option).." "..option.name.." "..P.Stats(option).summary):find(query,1,true)
   if match and (all or state~="blocked" or U.showLater or blockKind=="profession") then entries[#entries+1]={option=option,state=state,reason=reason,blockKind=blockKind}
   elseif match and state=="blocked" then hidden=hidden+1 end
  end
 end
 for _,e in ipairs(entries) do
  e.group,e.grade,e.score,e.data,e.comparison=P.Grade(inspection,e.option,U.profile,maxScore,e.state)
  e.recommendation=P.Recommendation(e.option,U.profile)
  e.sortName=ns.Locale.Fold(A.Name(e.option))
  if mode=="cheapest" or mode=="expensive" then
   local purchase=e.option.itemID and e.option.tradable~=false and "item" or "materials"
   e.cost=S.Estimate(S.Requirements(e.option,purchase))
  end
 end
 local stateOrder={usable=1,unknown=2,blocked=3}
 table.sort(entries,function(a,b)
  if mode=="cheapest" or mode=="expensive" then
   if a.cost.complete~=b.cost.complete then return a.cost.complete end
   if a.cost.complete and a.cost.total~=b.cost.total then
    if mode=="cheapest" then return a.cost.total<b.cost.total end
    return a.cost.total>b.cost.total
   end
  end
  if mode=="relevance" then
   -- A strong recommendation never bypasses actual application requirements.
   if (a.state=="blocked")~=(b.state=="blocked") then return a.state~="blocked" end
   local ap=a.recommendation and a.recommendation.priority or 0
   local bp=b.recommendation and b.recommendation.priority or 0
   if ap~=bp then return ap>bp end
  end
  if mode~="all" then
   if a.group~=b.group then return a.group<b.group end
   if a.state~=b.state then return stateOrder[a.state]<stateOrder[b.state] end
   if a.score~=b.score then return a.score>b.score end
  end
  if a.sortName~=b.sortName then return a.sortName<b.sortName end
  return a.option.id<b.option.id
 end)
 return entries,maxScore,hidden
end
function U.DrawOptions(inspection)
 local activeKinds,totalKinds=U.RefreshKindFilter()
 local entries,maxScore,hidden=U.OptionEntries(inspection)
 U.maximumScore=maxScore
 for _,entry in ipairs(entries) do U.DrawOption(entry,inspection) end
 if #entries==0 then
  local row=U.Row();local y=line(row,ns.L("Keine passenden Verbesserungen"),16,"GameFontHighlight",C.accent)
  y=line(row,activeKinds<totalKinds and ns.L("Passe die Artenfilter an oder ändere die Suche.") or ns.L(ns.slotNotes[U.slot]) or ns.L("Wähle eine andere Ausrichtung oder zeige später nutzbare Einträge an."),y+4,nil,C.muted);finish(row,y)
 end
 local mode,label=U.SortMode();local all=mode=="all"
 U.sortButton:SetText(label.."  v")
 U.later:SetText(all and ns.L("Später: alle") or U.showLater and ns.L("Später: an") or (ns.L("Später (")..hidden..")"));U.later.active=all or U.showLater;U.later:Paint();U.later:SetEnabled(not all)
 local count=0;for _ in pairs(ns.Planner.GearPlan()) do count=count+1 end
 U.footer:SetText(count..ns.L(' geplant'))
end
-- Cart rows keep normal font sizes, but use tighter spacing than recommendation cards.
local function cartLine(row,value,y,font,color,width,x)
 line(row,value,y,font,color,width,x)
 local label=row.texts[row.textIndex];label:SetSpacing(1)
 return y+math.max(14,label:GetStringHeight())+4
end
local function finishCart(row,y)
 row:SetHeight(y+8)
 local owner=row.layoutOwner;owner.y=owner.y+y+10
end
function U.DrawCart()
 local f=U.cartWindow;local Q=ns.Presentation
 local requirements,entries=S.GetCart();local missing=S.Missing(requirements);local cost=S.Estimate(missing)
 local totalQuantity=0;local exists=false
 for _,entry in ipairs(entries) do if entry.key==f.selectedRecipe then exists=true end end
 if not exists then f.selectedRecipe=nil end
 for _,entry in ipairs(entries) do
  totalQuantity=totalQuantity+entry.quantity
  local row=U.Row(f);row.entryKey=entry.key;row.active=f.selectedRecipe==entry.key;T.Button(row);row:EnableMouse(true)
  row:SetScript('OnClick',function(_,mouseButton) if A.ChatLink(entry.option,entry.quantity,mouseButton) then return end;f.selectedRecipe=f.selectedRecipe~=entry.key and entry.key or nil;U.RefreshCart() end)
  row:SetScript('OnEnter',function(self) T.Button(self,true) end);row:SetScript('OnLeave',function(self) T.Button(self);GameTooltip:Hide() end)
  local icon=rowIcon(row,entry.option,12,14,44)
  T.NativeHover(icon,entry.option,function() row:GetScript('OnClick')(row,'LeftButton') end,entry.quantity)
  local bottom=cartLine(row,T.ItemName(entry.option.itemID,A.Name(entry.option)),12,'GameFontHighlight',nil,240,68)
  local y=math.max(40,bottom)
  cartLine(row,ns.slotByID[entry.slot].label,y+7,nil,C.muted,200,68)
  action(row,'−',316,24,30,function() S.SetQuantity(entry.key,entry.quantity-1);U.Refresh() end):SetEnabled(entry.quantity>1)
  cartLine(row,tostring(entry.quantity),31,'GameFontHighlight',C.text,30,352)
  action(row,'+',385,24,30,function() S.SetQuantity(entry.key,entry.quantity+1);U.Refresh() end):SetEnabled(entry.quantity<99)
  action(row,'×',425,24,28,function() S.Remove(entry.key);U.Refresh() end,function(self) tip(self,ns.L('Entfernen'),A.Name(entry.option)) end)
  finishCart(row,y+28)
 end
 if #entries==0 then local row=U.Row(f);finishCart(row,cartLine(row,ns.L('Warenkorb leer'),18,nil,C.muted,350,12)) end
 for _,m in ipairs(requirements) do
  local row=U.Row(f.resources);row.materialID=m.id;local contribution=0
  for _,part in ipairs(m.contributors or {}) do if part.key==f.selectedRecipe then contribution=contribution+part.count end end
  row.active=contribution>0;row.uiStyle='table';T.Button(row)
  local icon=rowIcon(row,{itemID=m.id,chatCount=m.purchaseCount},10,12,34)
  local nameBottom=cartLine(row,T.ItemName(m.id,name(m)),12,'GameFontHighlight',C.text,190,54)
  cartLine(row,tostring(m.count),24,'GameFontHighlight',C.text,48,250)
  cartLine(row,tostring(math.max(0,m.owned or 0)),24,'GameFontHighlight',(m.owned or 0)<m.count and C.worse or C.better,48,310)
  action(row,'−',366,16,30,function() S.SetResourceQuantity(m.id,m.purchaseCount-1) end):SetEnabled(m.purchaseCount>0)
  cartLine(row,tostring(m.purchaseCount),24,'GameFontHighlight',C.text,46,405)
  action(row,'+',450,16,30,function() S.SetResourceQuantity(m.id,m.purchaseCount+1) end):SetEnabled(m.purchaseCount<999999)
  local price=S.Price(m.id);cartLine(row,price and ns.Money(price) or '—',24,nil,C.gold,150,492)
  local detailY=math.max(37,nameBottom)
  if contribution>0 then cartLine(row,string.format(ns.L('+%d aus Auswahl'),contribution),detailY,nil,C.gold,270,54) end
  if m.adjustment~=0 then
   action(row,'R',618,detailY-3,26,function() S.ResetResourceQuantity(m.id) end,function(self) tip(self,ns.L('Automatisch'),ns.L('Mengen zurücksetzen')) end)
  end
  local function materialTip(owner)
   A.ShowTooltip(owner,{itemID=m.id});Q.PriceAge(m.id)
   if ns.db.settings.showCartContributions~=false then
    for _,part in ipairs(m.contributors or {}) do GameTooltip:AddLine(part.count..' × '..A.Name(part.option),.85,.8,.65,true) end
   end
   GameTooltip:Show()
  end
  icon:SetScript('OnEnter',materialTip)
  T.LinkArea(row,{itemID=m.id},m.purchaseCount,54,8,184,math.max(28,nameBottom-8))
  row.chatLinks[row.chatLinkIndex]:SetScript('OnEnter',materialTip)
  finishCart(row,math.max(54,detailY+16))
 end
 if #requirements==0 then local row=U.Row(f.resources);finishCart(row,cartLine(row,'—',18,nil,C.muted,620,12)) end
 U.cartCost:SetText(ns.L('Warenkorb: ')..(#missing==0 and ns.Money(0) or cost.total>0 and S.PriceText(cost) or ns.L('Betrag offen')))
 local unknown=0;for _,m in ipairs(missing) do if not S.Price(m.id) then unknown=unknown+1 end end
 U.cartPriceStatus:SetText(unknown>0 and string.format(ns.L('%d Preise fehlen'),unknown) or '');U.cartPriceStatus:SetShown(unknown>0)
 local ready=S.CanExport();local auctionOpen=S.IsAuctionOpen()
 local enabled=#missing>0 and auctionOpen and ready
 U.cartImport:SetEnabled(enabled)
 local hint=not auctionOpen and ns.L('Besuche das Auktionshaus, um die Einkaufsliste zu importieren.')
  or S.transferStatus or (#missing==0 and ns.L('Keine fehlenden Waren zum Übertragen.') or ns.L('In Auctionator übernehmen'))
 if not ready then
  local requirement=type(Auctionator)=='table' and ns.L('Auctionator-Einkaufslisten-API nicht verfügbar.')
   or ns.L('Dafür benötigst du das Addon Auctionator. Bitte installiere und aktiviere es.')
  hint=hint..'\n\n'..requirement
 end
 U.cartImportHint:SetText(hint);U.cartImportHint:Hide()
 U.cartImport.tip=function(self) tip(self,ns.L('In Auctionator übernehmen'),U.cartImportHint:GetText()) end
 U.cartImportHover:SetShown(not enabled)
 U.cartPurchase:SetHeight(72)
 for _,column in ipairs({f,f.resources}) do
  column.scroll:ClearAllPoints();column.scroll:SetPoint('TOPLEFT',f,'TOPLEFT',column.x,-164);column.scroll:SetPoint('BOTTOMLEFT',f,'BOTTOMLEFT',column.x,155)
  column.bar:ClearAllPoints();column.bar:SetPoint('TOPLEFT',f,'TOPLEFT',column.x+column.width+2,-166);column.bar:SetPoint('BOTTOMLEFT',f,'BOTTOMLEFT',column.x+column.width+2,157)
 end
 U.cartSummary:SetText(string.format(ns.L('%d Rezepte · %d Anwendungen'),#entries,totalQuantity))
 f.resetQuantities:SetEnabled(next(ns.char.cartAdjustments or {})~=nil)
 f.footer:SetText('')
end
function U.RefreshPrices()
 U.Refresh()
 if U.planner and U.planner:IsShown() then U.RefreshPlanner() end
end
function U.ImportPrices()
 S.ImportPrices(function(ok,message)
  ns.Print(message)
  if ok then U.RefreshPrices();U.RefreshCart() end
 end)
end
function U.RefreshCart()
 local _,entries=S.GetCart()
 if U.cartTab then
  U.cartTab:SetText(ns.L("Einkaufsliste · ")..#entries)
  U.cartTab.active=U.cartWindow and U.cartWindow:IsShown();U.cartTab:Paint()
 end
 if U.RefreshCartLauncher then U.RefreshCartLauncher(entries) end
 local f=U.cartWindow;if not f or not f:IsShown() then return end
 f.priceMode:SetText(ns.db.settings.autoPriceImport==false and ns.L("Preisübernahme: manuell") or ns.L("Preisübernahme: automatisch"))
 for _,column in ipairs({f,f.resources}) do
  for _,row in ipairs(column.rows) do row:Hide() end
  column.rowIndex=0;column.y=0
 end
 U.DrawCart();f.priceStamp:SetText(S.PriceImportText())
 for _,column in ipairs({f,f.resources}) do
  column.content:SetHeight(math.max(1,column.y))
  local maximum=math.max(0,column.y-column.scroll:GetHeight())
  column.bar:SetMinMaxValues(0,maximum);column.bar:SetValue(math.min(column.scroll:GetVerticalScroll(),maximum));column.bar:SetShown(maximum>0)
 end
end
function U.CreateCart()
 local W=1180
 local f=CreateFrame("Frame","GearWiseForeverCart",UIParent,"BackdropTemplate");U.cartWindow=f
 f.rows={};f.rowIndex=0;f.y=0;f.x=18;f.width=462
 f.resources={rows={},rowIndex=0,y=0,x=502,width=656}
 f:SetSize(W,H);f:SetFrameStrata("HIGH");f:SetClampedToScreen(true);f:EnableMouse(true);f:SetMovable(true);T.Window(f,W,H)
 f:SetScale(math.min(1,(UIParent:GetHeight()-32)/H,(UIParent:GetWidth()-32)/W))
 local position=ns.db.settings.cartPosition or {}
 f:SetPoint("CENTER",UIParent,"CENTER",position.x or math.max(0,(UIParent:GetWidth()-W)/2-18),position.y or 0)
 local header=CreateFrame("Frame",nil,f);header:SetSize(W-70,42);place(header,10,5);header:EnableMouse(true);header:RegisterForDrag("LeftButton")
 header:SetScript("OnDragStart",function() f:StartMoving() end)
 header:SetScript("OnDragStop",function()
  f:StopMovingOrSizing();local x,y=f:GetCenter();local ux,uy=UIParent:GetCenter();local scale=f:GetEffectiveScale()/UIParent:GetEffectiveScale()
  ns.db.settings.cartPosition={x=x*scale-ux,y=y*scale-uy}
 end)
 f.headerLogo=T.HeaderLogo(f,22,5,36)
 f.brand=T.BrandText(text(f,"GearWise",68,8,156,"GameFontNormalLarge",C.gold),27)
 text(f,ns.L("Warenkorb"),230,13,W-290,"GameFontHighlight",C.accent)
 local close=button(f,"×",28,function() f:Hide() end);close:SetPoint("TOPRIGHT",-14,-12);close.danger=true;close.fontSize=20;close:Paint()
 U.cartSummary=text(f,"",18,60,CW,"GameFontHighlight",C.text);U.cartSummary:SetHeight(20)
 f.priceRefresh=button(f,ns.L('Preise importieren'),180,U.ImportPrices);place(f.priceRefresh,692,60)
 f.priceRefresh.tip=function(self) tip(self,ns.L('Preise aus Auctionator'),ns.L('Übernimmt gespeicherte Auctionator-Preise für Materialien und Fertigprodukte. Neue AH-Preise zuerst mit Auctionator erfassen.')) end
 f.priceMode=text(f,'',800,92,260,nil,C.muted);f.priceMode:Hide()
 f.priceStamp=text(f,'',890,63,270,nil,C.muted)
 f.recipePanel=T.Group(f,12,100,474,H-216);f.materialPanel=T.Group(f,496,100,668,H-216)
 local recipeTitle=text(f,ns.L('Rezepte'),26,113,440,'GameFontHighlight',C.gold);T.Font(recipeTitle,19)
 local materialTitle=text(f,ns.L('Materialien'),510,113,600,'GameFontHighlight',C.gold);T.Font(materialTitle,19)
 for _,heading in ipairs({{ns.L('Materialien'),502,236},{ns.L('Bedarf'),752,54},{ns.L('Inventar'),812,60},{ns.L('Kaufen'),868,110},{ns.L('Stück'),994,140}}) do text(f,heading[1],heading[2],143,heading[3],nil,C.muted) end
 f.resetQuantities=button(f,ns.L('Mengen zurücksetzen'),228,function() ns.char.cartAdjustments={};S.CartChanged() end);place(f.resetQuantities,510,H-145)
 for _,column in ipairs({f,f.resources}) do
  local scroll=CreateFrame("ScrollFrame",nil,f);column.scroll=scroll;scroll:SetWidth(column.width)
  local content=CreateFrame("Frame",nil,scroll);column.content=content;content:SetWidth(column.width);content:SetHeight(1);scroll:SetScrollChild(content)
  local bar=CreateFrame("Slider",nil,f,"BackdropTemplate");column.bar=bar
  bar:SetOrientation("VERTICAL");bar:SetMinMaxValues(0,0);bar:SetValueStep(20);T.Scrollbar(bar)
  bar:SetScript("OnValueChanged",function(_,value) scroll:SetVerticalScroll(value) end)
  local function wheel(_,delta) local _,maximum=bar:GetMinMaxValues();bar:SetValue(math.max(0,math.min(maximum,scroll:GetVerticalScroll()-delta*44))) end
  T.CaptureWheel(scroll,wheel);T.CaptureWheel(bar,wheel)
 end
 local purchase=CreateFrame("Frame",nil,f,"BackdropTemplate");U.cartPurchase=purchase
 purchase:SetPoint("BOTTOMLEFT",18,44);purchase:SetSize(W-36,72);paint(purchase)
 U.cartCost=text(purchase,"",12,10,CW,"GameFontHighlight",C.gold)
 U.cartPriceStatus=text(purchase,"",12,30,CW,nil,C.muted)
 U.cartImport=button(purchase,ns.L("In Auctionator übernehmen"),350,function()
  local ok,message=S.Export();ns.Print(message);if not ok then S.transferStatus=message end;U.Refresh()
 end);place(U.cartImport,W-398,20);T.Primary(U.cartImport);U.cartImport:SetHeight(36);T.Font(U.cartCost,17)
 U.cartImportHint=text(purchase,"",480,42,412,nil,C.muted)
 -- Disabled buttons do not reliably receive OnEnter in Classic. A frame covers
 -- only the disabled state; enabled buttons keep their normal click handling.
 local importHover=CreateFrame('Frame',nil,purchase);U.cartImportHover=importHover
 importHover:SetPoint('TOPLEFT',U.cartImport,'TOPLEFT',0,0);importHover:SetPoint('BOTTOMRIGHT',U.cartImport,'BOTTOMRIGHT',0,0)
 importHover:SetFrameLevel(U.cartImport:GetFrameLevel()+1);importHover:EnableMouse(true)
 importHover:SetScript('OnEnter',function(self) if U.cartImport.tip then U.cartImport.tip(self) end end)
 importHover:SetScript('OnLeave',function() GameTooltip:Hide() end)
 importHover:SetScript('OnHide',function(self) if GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
 T.CaptureWheel(importHover)

 f.footer=text(f,"",18,H-29,W-36,nil,C.muted)
 f:SetScript("OnHide",function() U.RefreshCart() end)
 tinsert(UISpecialFrames,"GearWiseForeverCart");f:Hide()
end
function U.Refresh()
 U.RefreshCart()
 if U.RefreshSelection then U.RefreshSelection() end
 if not U.panel or not U.panel:IsShown() then return end
 if not U.profile then U.LoadProfile() elseif not U.manual then U.profile,U.detected=P.Detect() end
 U.impactContext=ns.Impact.Context(U.profile)
 U.ClearRows();local inspection=A.Inspect(U.slot);local c=inspection.context
 U.itemIcon:SetTexture(c.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
 U.itemName:SetText(c.item and T.ItemName(c.item,A.ItemInfo(c.item) or ns.L("Gegenstand")) or ns.L("Kein Gegenstand angelegt"))
 U.itemMeta:SetText(ns.slotByID[U.slot].label..(c.itemLevel and (ns.L(" · Gegenstandsstufe ")..c.itemLevel) or ""))
 U.status:SetText(inspection.status);U.status:SetTextColor(unpack(C[inspection.state]))
 U.profileButton:SetText(U.profile.label.."  v")
 U.auto:SetText(U.manual and ns.L("Aktive Skillung") or U.detected and ns.L("Aktive Skillung") or ns.L("Standardrolle"))
 U.rememberProfile:SetChecked(ns.char.preferredProfile~=nil)
 U.auto.active=not U.manual;U.auto:Paint()
 for key,b in pairs(U.directions) do
  b.active=(key=="damage" and (U.profile.role=="physical" or U.profile.role=="caster")) or key==U.profile.role;b:Paint()
 end
 U.optionsTab.active=true;U.optionsTab:Paint()
 U.placeholder:SetShown(U.search:GetText()=="")
 U.DrawOptions(inspection)
 U.content:SetHeight(math.max(1,U.y));local maximum=math.max(0,U.y-U.scroll:GetHeight())
 U.bar:SetMinMaxValues(0,maximum);U.bar:SetValue(math.min(U.scroll:GetVerticalScroll(),maximum));U.bar:SetShown(maximum>0)

end
function U.Initialize()
 U.rows={};U.slot=5;U.tab="options";U.directions={}
 local f=CreateFrame("Frame","GearWiseForeverPanel",UIParent,"BackdropTemplate");U.panel=f
 f:SetSize(W,H);f:SetFrameStrata("HIGH");T.Window(f,W,H);f:EnableMouse(true)
 local header=CreateFrame("Frame",nil,f);header:SetSize(W-70,34);place(header,0,0);header:EnableMouse(true);f:SetMovable(true);header:RegisterForDrag("LeftButton")
 header:SetScript("OnDragStart",function() f:StartMoving() end)
 header:SetScript("OnDragStop",function()
  f:StopMovingOrSizing();local x,y=f:GetCenter();local ux,uy=UIParent:GetCenter();local scale=f:GetEffectiveScale()/UIParent:GetEffectiveScale()
  ns.db.settings["detached"]={x=x*scale-ux,y=y*scale-uy};U.PlacePanel()
 end)
 U.headerLogo=T.HeaderLogo(f,176,5,38)
 local brand=text(f,"GearWise",222,6,188,"GameFontNormalLarge",C.gold)
 U.brand=T.BrandText(brand,30);brand:SetJustifyH("CENTER")
 local brandSub=text(f,"F O R E V E R",196,35,152,"GameFontHighlightSmall",C.muted,"CENTER")
 brandSub:Hide()
 local close=button(f,"x",28,function() f:Hide() end);place(close,W-42,8);close.danger=true;close.fontSize=18;close:Paint()
 local dock=button(f,"",28,function() ns.db.settings.detached=nil;U.PlacePanel() end);place(dock,18,10);T.DockSymbol(dock)
 dock.tip=function(self) tip(self,ns.L("Andocken"),ns.L("Fenster wieder neben dem Charakterbildschirm ausrichten.")) end
 U.itemMount=CreateFrame('Frame',nil,f);U.itemMount:SetSize(62,62);place(U.itemMount,22,67)
 U.itemIcon=U.itemMount:CreateTexture(nil,'ARTWORK');U.itemIcon:SetSize(58,58);U.itemIcon:SetPoint('CENTER');T.IconBorder(U.itemMount,U.itemIcon)
 U.itemName=text(f,"",100,69,W-124,"GameFontHighlight",C.text);T.Font(U.itemName,21);U.itemName:SetHeight(48)
 U.itemMeta=text(f,"",100,119,W-124,nil,C.muted)
 U.status=text(f,"",18,174,W-36,nil,C.muted,"CENTER");U.status:Hide()
 local hover=CreateFrame("Frame",nil,f);U.itemHover=hover;hover:SetSize(W-36,80);place(hover,18,56);hover:EnableMouse(true)
 hover:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetInventoryItem("player",U.slot);GameTooltip:Show() end)
 hover:SetScript("OnLeave",function() GameTooltip:Hide() end)
 for i,entry in ipairs({{"damage",ns.L("Schaden")},{"healer",ns.L("Heilung")},{"tank",ns.L("Tank")},{"profession",ns.L("Berufe")}}) do
  local key=entry[1];local b=button(f,entry[2],105,function()
   local role=key
   if key=="damage" then local p=P.Detect();role=p.role=="caster" and "caster" or "physical" end
   local detected=P.Detect()
   local selected=detected.role==role and detected or nil
   if not selected then
    for _,p in ipairs(P.Profiles()) do if p.role==role then selected=p;break end end
   end
   U.ChooseProfile(selected)
  end);place(b,18+(i-1)*113,197);b:Hide();U.directions[key]=b
  local icons={damage="Interface\\Icons\\INV_Sword_04",healer="Interface\\Icons\\Spell_Holy_Heal",tank="Interface\\Icons\\INV_Shield_06",profession="Interface\\Icons\\Trade_Engraving"}
  T.ButtonIcon(b,icons[key])
 end
 U.profileButton=button(f,"",330,U.ProfileMenu);place(U.profileButton,18,148)
 U.auto=button(f,ns.L("Automatisch"),126,function() local p,detected=P.Detect();U.detected=detected;U.ChooseProfile(p,true) end);place(U.auto,358,148)
 U.auto.tip=function(self) tip(self,ns.L("Aktive Skillung übernehmen"),ns.L("Übernimmt deine aktuell gespielte Skillung. Ist das Häkchen gesetzt, wird sie auch als Standard für diesen Charakter gespeichert.")) end
 local remember=CreateFrame("CheckButton",nil,f,"BackdropTemplate");U.rememberProfile=remember
 remember:SetSize(18,18);place(remember,510,153);paint(remember)
 remember:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
 remember:SetScript("OnClick",function(self) U.SetRememberProfile(self:GetChecked()) end)
 remember:SetScript("OnEnter",function(self)
  tip(self,ns.L("Standard für diesen Charakter"),ns.L("Speichert die gewählte Skillung oder Ausrichtung dauerhaft. Weitere Änderungen werden mitgespeichert. Ohne Häkchen wird beim nächsten Öffnen die aktive Skillung gewählt."))
 end)
 remember:SetScript("OnLeave",function() GameTooltip:Hide() end)
 U.optionsTab=button(f,ns.L("Empfehlungen"),214,function() U.tab="options";U.ResetScroll();U.PlacePanel();U.Refresh() end);place(U.optionsTab,18,299);U.optionsTab:Hide()
 U.cartTab=button(f,ns.L("Einkaufsliste"),222,U.OpenCart);place(U.cartTab,240,299);U.cartTab:Hide()
 local search=CreateFrame("EditBox",nil,f,"BackdropTemplate");U.search=search;paint(search)
 search:SetBackdropColor(.035,.043,.050,1);search:SetBackdropBorderColor(.43,.46,.46,1);search:SetSize(244,30);place(search,18,188);search:SetFontObject("GameFontHighlightSmall");search:SetTextInsets(30,10,0,0);search:SetAutoFocus(false)
 local searchIcon=search:CreateTexture(nil,"ARTWORK");searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon");searchIcon:SetSize(16,16);searchIcon:SetPoint("LEFT",9,0)
 U.placeholder=text(search,ns.L("Suchen …"),30,8,204,nil,C.muted)
 search:SetScript("OnTextChanged",function(self) U.placeholder:SetShown(self:GetText()=="");U.ResetScroll();U.Refresh() end)
 search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
 U.later=button(f,ns.L("Später"),132,function() U.showLater=not U.showLater;U.ResetScroll();U.Refresh() end);place(U.later,18,222);U.later:Hide()
 U.later.tip=function(self) tip(self,ns.L("Später nutzbar"),ns.L("Zeigt auch Verbesserungen, deren Stufen- oder Gegenstandsanforderungen du derzeit nicht erfüllst.")) end
 U.sortButton=button(f,ns.L("Sortierung: Relevanz  v"),126,U.SortMenu);place(U.sortButton,270,188)
 U.kindButton=button(f,"",138,U.KindMenu);place(U.kindButton,404,188)
 U.kindButton.tip=function(self) tip(self,ns.L("Verbesserungsarten"),ns.L("Häkchen wählen, um Verbesserungsarten ein- oder auszublenden. Die Auswahl wird für diesen Charakter gespeichert.")) end
 U.sortButton.tip=function(self) tip(self,ns.L("Sortierung & Auswahl"),ns.L("Relevanz: passend zur Skillung. Preise: Gesamtkosten mit Auctionator; unvollständige Preise zuletzt. Alle: jede passende Verbesserung, auch andere Ausrichtungen und später nutzbare, nach Name.")) end
 U.scroll=CreateFrame("ScrollFrame",nil,f);U.scroll:SetPoint("TOPLEFT",18,-230);U.scroll:SetPoint("BOTTOMRIGHT",-26,46)
 U.content=CreateFrame("Frame",nil,U.scroll);U.content:SetWidth(CW);U.content:SetHeight(1);U.scroll:SetScrollChild(U.content)
 local bar=CreateFrame("Slider",nil,f,"BackdropTemplate");U.bar=bar;bar:SetWidth(5);bar:SetPoint("TOPRIGHT",-12,-232);bar:SetPoint("BOTTOMRIGHT",-12,48)
 paint(bar);bar:SetOrientation("VERTICAL");bar:SetMinMaxValues(0,0);bar:SetValueStep(20)
 T.Scrollbar(bar)
 bar:SetScript("OnValueChanged",function(_,value) U.scroll:SetVerticalScroll(value) end)
 U.scroll:EnableMouseWheel(true);U.scroll:SetScript("OnMouseWheel",function(_,delta)
  local _,maximum=bar:GetMinMaxValues();bar:SetValue(math.max(0,math.min(maximum,U.scroll:GetVerticalScroll()-delta*44)))
 end)
 U.footer=text(f,"",18,H-29,180,nil,C.muted)
 U.planOpen=button(f,ns.L('Plan öffnen'),136,U.ExpandPlanner);place(U.planOpen,W-198,H-35)
 U.expand=button(f,'',28,U.ExpandPlanner);place(U.expand,54,10);T.ViewSymbol(U.expand,false)
 U.expand.tip=function(self) tip(self,ns.L('Große Ansicht'),ns.L('Öffnet denselben Slot und dieselbe Auswahl im Planer.')) end
 f:SetScript("OnHide",function()
  if U.RefreshSelection then U.RefreshSelection() end
  U.CloseDetails()
  if U.sortMenu then U.sortMenu:Hide() end
  if U.kindMenu then U.kindMenu:Hide() end
  U.profile=nil;U.manual=nil;U.details=nil;if U.profileMenu then U.profileMenu:Hide() end;if U.source then U.source:Hide() end
 end)
 T.LanguagePicker(f,8)
 tinsert(UISpecialFrames,"GearWiseForeverPanel");f:Hide();U.PlacePanel();U.CreateMinimap();U.CreateCartLauncher(f)
end

ns.Locale.Track(sortChoices)
