local _,ns=...
local T={};ns.Theme=T
T.colors={better={.40,.87,.54},worse={1,.34,.30},equal={1,.80,.38},unrated={.64,.65,.66},text={.92,.91,.86},muted={.66,.67,.65},accent={.86,.71,.39},gold={1,.80,.38},
 missing={1,.80,.38},enhanced={.46,.80,.64},usable={.46,.80,.64},blocked={.55,.51,.44},
 unknown={.91,.73,.43},neutral={.58,.78,.72},empty={.70,.65,.54},ignored={.70,.65,.54}}
local WHITE="Interface\\Buttons\\WHITE8X8"
T.logoPath="Interface\\AddOns\\GearWise\\Assets\\GearWiseScrollHeader.png"
T.minimapLogoPath="Interface\\AddOns\\GearWise\\Assets\\GearWiseScrollMinimap.png"
function T.HeaderLogo(parent,x,y,size)
 local logo=parent:CreateTexture(nil,"OVERLAY")
 logo:SetTexture(T.logoPath);logo:SetSize(size,size);logo:SetPoint("TOPLEFT",x,-y)
 return logo
end
function T.BrandText(text,size)
 text:SetFont("Fonts\\MORPHEUS.TTF",size or 27,"OUTLINE")
 text:SetTextColor(1,1,1)
 text:SetText("|cffffe5a0Gear|r|cffffb629Wise|r")
 if text.SetShadowColor then text:SetShadowColor(.45,.13,0,1);text:SetShadowOffset(2,-2) end
 return text
end
-- Use the client's quality colors for item names; spells have no item quality.
local itemQualityHex={[0]='ff9d9d9d',[1]='ffffffff',[2]='ff1eff00',[3]='ff0070dd',[4]='ffa335ee',[5]='ffff8000',[6]='ffe6cc80',[7]='ffe6cc80',[8]='ff00ccff'}
function T.ItemName(ref,name,fallbackQuality)
 name=name or ''
 if not ref or name:find('|Hitem:',1,true) then return name end
 local _,_,quality=ns.API.ItemInfo(ref)
 quality=ns.PublicValue(quality) or fallbackQuality
 if quality==nil then
  local id=type(ref)=='number' and ref or type(ref)=='string' and tonumber(ref:match('item:(%d+)'))
  if id then ns.API.RequestItem(id) end
  return name
 end
 local color=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
 local hex=itemQualityHex[quality]
 if color then
  if color.hex then hex=color.hex:gsub('^|c','')
  elseif color.r and color.g and color.b then
   hex=string.format('ff%02x%02x%02x',math.floor(color.r*255+.5),math.floor(color.g*255+.5),math.floor(color.b*255+.5))
  end
 end
 return hex and ('|c'..hex..name..'|r') or name
end
function T.Font(text,size)
 if not text then return end
 local flags=''
 if text.GetFont then local _,current,currentFlags=text:GetFont();size=size or current;flags=currentFlags or '' end
 size=size or 13
 text:SetFont(ns.Locale.code=='ruRU' and 'Fonts\\FRIZQT___CYR.TTF' or 'Fonts\\FRIZQT__.TTF',size,flags)
 if text.SetShadowColor then text:SetShadowColor(0,0,0,.9);text:SetShadowOffset(1,-1) end
end
function T.BenefitText(text,option,size)
 T.Font(text,size or 17)
 text:SetWordWrap(true);text:SetSpacing(3);text:SetHeight(0)
 text:SetTextColor(unpack(ns.Advice.Stats(option).conditional and T.colors.gold or {.40,1,.60}))
end
function T.Surface(f)
 f:SetBackdrop({bgFile=WHITE,edgeFile=WHITE,edgeSize=1})
 f:SetBackdropColor(.035,.040,.045,1);f:SetBackdropBorderColor(.26,.28,.29,1)
end
function T.Primary(b) b.primary=true;T.Button(b);return b end
function T.Group(parent,x,y,w,h)
 local f=CreateFrame('Frame',nil,parent,'BackdropTemplate');f:SetSize(w,h);f:SetPoint('TOPLEFT',x,-y)
 f:SetFrameLevel(parent:GetFrameLevel());T.Surface(f)
 f:SetBackdrop({bgFile='Interface\\DialogFrame\\UI-DialogBox-Background',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',tile=true,tileSize=64,edgeSize=12,insets={left=4,right=4,top=4,bottom=4}})
 f:SetBackdropColor(.48,.53,.57,1);f:SetBackdropBorderColor(.49,.39,.23,1)
 f:EnableMouse(false);return f
end
function T.IconBorder(parent,icon)
 local border=parent.iconBorder
 if not border then
  border=parent:CreateTexture(nil,'OVERLAY');parent.iconBorder=border
  border:SetTexture('Interface\\Buttons\\UI-Quickslot2');border:SetPoint('CENTER',icon,'CENTER',0,0)
 end
 border:SetSize(icon:GetWidth()*1.55,icon:GetHeight()*1.55);border:SetVertexColor(.77,.78,.75,1)
end
local function stroke(f,x,y,w,h,color,layer)
 local t=f:CreateTexture(nil,layer or "ARTWORK")
 t:SetTexture(WHITE);t:SetPoint("TOPLEFT",x,-y);t:SetSize(w,h)
 t:SetVertexColor(unpack(color));return t
end
function T.Rule(f,y,width)
 stroke(f,18,y,width-36,1,{.45,.34,.18,.7})
 stroke(f,width/2-18,y-1,36,3,{.74,.56,.27,.9})
 local gem=stroke(f,width/2-2,y-2,4,4,{.94,.75,.38,1});gem:SetRotation(math.pi/4)
end
function T.CaptureWheel(f,handler)
 -- Click capture alone does not stop wheel events reaching a frame behind this window.
 f:EnableMouseWheel(true)
 f:SetScript("OnMouseWheel",handler or function() end)
end
-- Let the client raise a complete window when any of its controls is clicked.
-- A plain HIGH frame does not participate in that window stacking behaviour.
function T.RaiseWindow(f)
 f:Raise()
end
function T.WindowMenu(menu,owner)
 -- Menus belong to their window, rather than floating above every HIGH window.
 menu:SetFrameStrata(owner:GetFrameStrata())
 menu:SetFrameLevel(owner:GetFrameLevel()+50)
end
function T.Window(f,width,height)
 f:SetToplevel(true)
 f:HookScript("OnShow",T.RaiseWindow)
 f:HookScript("OnShow",ns.Shopping.WindowShown)
 f:HookScript("OnHide",ns.Shopping.WindowHidden)
 T.CaptureWheel(f)
 f:SetBackdrop({bgFile=WHITE,edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=24,insets={left=5,right=5,top=5,bottom=5}})
 -- WHITE8X8 has no baked-in transparency: keep the dark window fill at a full opacity.
 f:SetBackdropColor(.025,.030,.034,1);f:SetBackdropBorderColor(.90,.70,.35,1)
 stroke(f,10,8,width-20,39,{.055,.062,.068,1})
 T.Rule(f,48,width);T.Rule(f,height-39,width)
 -- Small brass corner details stay outside the interactive content.
 for _,x in ipairs({12,width-16}) do
  local gem=stroke(f,x,13,4,4,{.83,.64,.31,1});gem:SetRotation(math.pi/4)
 end
end
function T.Button(b,hover)
 if not b.gearwiseButtonHooks then
  b.gearwiseButtonHooks=true
  b:HookScript("OnEnable",function(self) T.Button(self) end)
  b:HookScript("OnDisable",function(self) self.pressed=nil;T.Button(self) end)
  b:HookScript("OnMouseDown",function(self) self.pressed=true;T.Button(self,true) end)
  b:HookScript("OnMouseUp",function(self) self.pressed=nil;T.Button(self,true) end)
  b:HookScript("OnLeave",function(self) self.pressed=nil;T.Button(self) end)
 end
 -- Composite recipe/material cards use their own labels and have no button font string.
 local label=b:GetFontString()
 if label then T.Font(label,b.fontSize or 13) end
 local enabled=not b.IsEnabled or b:IsEnabled()
 local active=b.active;local card=b.uiStyle=='card' or b.uiStyle=='table';local slot=b.uiStyle=='slot'
 local edge=(b.primary or b.uiStyle=='card' or active and card) and 12 or 8
 b:SetBackdrop({bgFile=WHITE,edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=edge,insets={left=3,right=3,top=3,bottom=3}})
 b:SetAlpha(enabled and 1 or .70)
 local fill,border
 if not enabled then fill={.045,.049,.052,1};border={.27,.28,.27,1}
 elseif b.danger then fill={.25,.025,.018,1};border={.84,.66,.33,1}
 elseif b.plain and not hover and not active then fill={0,0,0,0};border={0,0,0,0}
 elseif slot and active then fill={.035,.095,.17,1};border={.35,.60,.80,1}
 elseif b.primary then fill=hover and {.31,.21,.065,1} or {.20,.135,.040,1};border={1,.79,.35,1}
 elseif card and active then fill=hover and {.10,.115,.125,1} or {.065,.075,.085,1};border={1,.78,.33,1}
 elseif active then fill={.10,.105,.105,1};border={.87,.68,.34,1}
 elseif hover then fill={.105,.12,.135,1};border={.70,.60,.39,1}
 else fill=card and {.037,.043,.049,1} or {.060,.068,.077,1};border=b.uiStyle=='card' and {.43,.45,.46,1} or card and {.27,.29,.30,1} or {.50,.45,.35,1} end
 if b.pressed and enabled then fill={.13,.105,.065,1} end
 b:SetBackdropColor(unpack(fill));b:SetBackdropBorderColor(unpack(border))
 if not b.bevel then
  local t=b:CreateTexture(nil,'BORDER');b.bevel=t;t:SetTexture(WHITE)
  t:SetPoint('TOPLEFT',5,-5);t:SetPoint('TOPRIGHT',-5,-5);t:SetHeight(1)
 end
 -- Keep alpha numeric: boolean selection states must never reach texture APIs.
 b.bevel:SetVertexColor(1,1,1,b.plain and 0 or (active or b.primary) and .18 or b.uiStyle=='card' and .12 or .07)
 if label then label:SetTextColor(unpack(not enabled and {.52,.49,.42} or b.danger and {1,.82,.32} or b.link and {.25,.65,1} or (hover or active or b.primary) and T.colors.gold or {.94,.92,.85})) end
end
function T.Divider(parent,key,x,y,width)
 parent.dividers=parent.dividers or {};local t=parent.dividers[key]
 if not t then t=parent:CreateTexture(nil,'ARTWORK');t:SetTexture(WHITE);parent.dividers[key]=t end
 t:ClearAllPoints();t:SetPoint('TOPLEFT',x,-y);t:SetSize(width,1);t:SetVertexColor(.50,.40,.22,.65);t:Show();return t
end
function T.Chevron(parent,expanded,x,y)
 if not parent.chevron then
  parent.chevron={}
  for i=1,2 do local t=parent:CreateTexture(nil,'OVERLAY');t:SetTexture(WHITE);t:SetSize(9,2);t:SetVertexColor(.92,.77,.48,1);parent.chevron[i]=t end
 end
 for i,t in ipairs(parent.chevron) do
  t:ClearAllPoints();t:SetPoint('TOPLEFT',x+(i-1)*6,-y);t:SetRotation((i==1 and 1 or -1)*(expanded and 1 or -1)*math.pi/4);t:Show()
 end
end
function T.ButtonIcon(b,path)
 local icon=b:CreateTexture(nil,"ARTWORK");icon:SetSize(18,18);icon:SetPoint("LEFT",7,0);icon:SetTexture(path)
 local label=b:GetFontString();label:ClearAllPoints();label:SetPoint("LEFT",30,0);label:SetWidth(b:GetWidth()-35);label:SetJustifyH("LEFT")
 b.symbol=icon
end
function T.DockSymbol(b)
 -- Drawn instead of using an arrow glyph missing from some Classic fonts.
 for _,v in ipairs({{7,8,5,12},{14,8,8,1},{14,19,8,1},{14,8,1,12},{21,8,1,12}}) do
  stroke(b,v[1],v[2],v[3],v[4],{.86,.71,.39,1})
 end
end
function T.CartSymbol(b)

 -- Small gold cart drawn from textures: readable in every client language.

 local gold={1,.80,.38,1}

 stroke(b,7,10,8,2,gold)

 local side=stroke(b,14,11,2,20,gold);side:SetRotation(math.rad(12))

 stroke(b,16,15,21,2,gold)

 local edge=stroke(b,34,16,2,12,gold);edge:SetRotation(math.rad(-10))

 stroke(b,18,27,16,2,gold);stroke(b,18,31,17,2,gold)

 stroke(b,17,21,18,1,{.74,.56,.27,1})

 stroke(b,22,17,1,10,{.74,.56,.27,1});stroke(b,28,17,1,10,{.74,.56,.27,1})

 for _,x in ipairs({20,31}) do

  local wheel=stroke(b,x,35,4,4,gold);wheel:SetRotation(math.pi/4)

 end

end

-- Native circular masks keep the small counter smooth at every UI scale.
function T.CartBadge(parent)
 local badge=CreateFrame('Frame',nil,parent);badge:SetSize(18,18);badge:SetPoint('TOPRIGHT',parent,'TOPRIGHT',5,0);badge:EnableMouse(false)
 local function circle(size,layer)
  local texture=badge:CreateTexture(nil,layer);texture:SetTexture(WHITE);texture:SetSize(size,size);texture:SetPoint('CENTER')
  local mask=badge:CreateMaskTexture();mask:SetTexture('Interface\\CHARACTERFRAME\\TempPortraitAlphaMask','CLAMPTOBLACKADDITIVE','CLAMPTOBLACKADDITIVE')
  mask:SetPoint('TOPLEFT',texture,'TOPLEFT',0,0);mask:SetPoint('BOTTOMRIGHT',texture,'BOTTOMRIGHT',0,0);texture:AddMaskTexture(mask)
  return texture
 end
 badge.rim=circle(18,'BACKGROUND');badge.rim:SetVertexColor(.48,.23,.23,1)
 badge.fill=circle(16,'ARTWORK');badge.fill:SetVertexColor(.49,.07,.09,1)
 badge.text=badge:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');badge.text:SetPoint('CENTER',0,0)
 badge.text:SetTextColor(1,.94,.90);T.Font(badge.text,10)
 return badge
end
function T.PaintCartBadge(button)
 button.badge.fill:SetVertexColor(unpack(button.hovered and {.66,.10,.12,1} or {.49,.07,.09,1}))
 button.badge.rim:SetVertexColor(unpack(button.hovered and {.73,.40,.36,1} or {.48,.23,.23,1}))
end
function T.ViewSymbol(b,compact)
 local color={1,.80,.38,1}
 local function box(x,y,w,h)
  stroke(b,x,y,w,1,color);stroke(b,x,y+h-1,w,1,color)
  stroke(b,x,y,1,h,color);stroke(b,x+w-1,y,1,h,color)
 end
 if compact then box(7,11,10,10);box(12,6,10,10) else box(6,7,16,14);stroke(b,7,8,14,2,color) end
end
function T.Scrollbar(bar)
 bar:SetWidth(10)
 bar:SetBackdrop({bgFile=WHITE,edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8})
 bar:SetBackdropColor(.035,.028,.018,1);bar:SetBackdropBorderColor(.52,.39,.19,1)
 bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
 bar:GetThumbTexture():SetVertexColor(.94,.74,.36,1);bar:GetThumbTexture():SetSize(12,36)
end
function T.Emblem(f,x,y)
 for i=0,3 do
  local spoke=stroke(f,x-1,y-14,2,28,{.81,.62,.28,1})
  spoke:SetRotation(i*math.pi/4)
 end
 local gem=stroke(f,x-3,y-3,6,6,{1,.82,.43,1});gem:SetRotation(math.pi/4)
end

-- Native tooltips on icons preserve the parent card's selection and hover state.
function T.NativeHover(target,option,fallback,count)
 local parent=target:GetParent()
 target:EnableMouse(true);target:RegisterForClicks("LeftButtonUp")
 target:SetScript("OnEnter",function(self)
  local enter=parent and parent:GetScript("OnEnter");if enter then enter(parent) end
  if option.kind or option.recipeItemID then ns.API.ShowRecipeTooltip(self,option) else ns.API.ShowTooltip(self,option) end
 end)
 target:SetScript("OnLeave",function()
  local leave=parent and parent:GetScript("OnLeave");if leave then leave(parent) end
  GameTooltip:Hide()
 end)
 target:SetScript("OnHide",function(self)
  if GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
 end)
 target:SetScript("OnClick",function(_,mouseButton)
  if ns.API.ChatLink(option,count,mouseButton) then return end
  if fallback then fallback() end
 end)
 T.CaptureWheel(target,function(_,delta)
  local current=parent
  while current do
   local handler=current:GetScript("OnMouseWheel")
   if handler then handler(current,delta);return end
   current=current:GetParent()
  end
 end)
end
function T.IconHover(parent,texture,option,fallback)
 local target=parent.iconHover
 if not target then target=CreateFrame("Button",nil,parent);parent.iconHover=target end
 target:ClearAllPoints();target:SetPoint("TOPLEFT",texture,"TOPLEFT",0,0)
 target:SetSize(texture:GetWidth(),texture:GetHeight());target:Show()
 T.NativeHover(target,option,fallback)
 return target
end

-- Invisible hit areas keep the card appearance and preserve its normal click action.
function T.ClearLinks(parent)
 for _,b in ipairs(parent.chatLinks or {}) do b:Hide() end
 parent.chatLinkIndex=0
end
function T.LinkArea(parent,option,count,x,y,w,h,fallback)
 parent.chatLinks=parent.chatLinks or {};parent.chatLinkIndex=(parent.chatLinkIndex or 0)+1
 local b=parent.chatLinks[parent.chatLinkIndex]
 if not b then
  b=CreateFrame("Button",nil,parent);b:RegisterForClicks("LeftButtonUp")
  parent.chatLinks[parent.chatLinkIndex]=b
 end
 b:ClearAllPoints();b:SetPoint("TOPLEFT",x,-y);b:SetSize(w,h);b:Show()
 b:SetScript("OnEnter",function()
  local handler=parent:GetScript("OnEnter");if handler then handler(parent) end
 end)
 b:SetScript("OnLeave",function()
  local handler=parent:GetScript("OnLeave");if handler then handler(parent) end
 end)
 b:SetScript("OnClick",function(_,mouseButton)
  if ns.API.ChatLink(option,count,mouseButton) then return end
  if fallback then fallback() end
 end)
 -- Explicitly forward the wheel to the nearest scrolling ancestor.
 T.CaptureWheel(b,function(_,delta)
  local current=parent
  while current do
   local handler=current:GetScript("OnMouseWheel")
   if handler then handler(current,delta);return end
   current=current:GetParent()
  end
 end)
 if option.itemID then T.NativeHover(b,option,fallback,count) end
 return b
end

-- A small, explicit hover target keeps recipe and material cards uncluttered.
function T.RecipeInfo(parent,option,x,y,fallback)
 local b=parent.recipeInfo
 if not b then
  b=CreateFrame("Button",nil,parent,"BackdropTemplate");parent.recipeInfo=b
  b:SetSize(24,24);b.plain=true;b.fontSize=16;b:RegisterForClicks("LeftButtonUp")
  local text=b:CreateFontString(nil,"OVERLAY","GameFontNormal");text:SetPoint("CENTER");b:SetFontString(text);b:SetText("i")
  T.Button(b)
  T.CaptureWheel(b,function(_,delta)
   local current=parent
   while current do
    local handler=current:GetScript("OnMouseWheel")
    if handler then handler(current,delta);return end
    current=current:GetParent()
   end
  end)
 end
 b:ClearAllPoints();b:SetPoint("TOPLEFT",x,-y);b:Show()
 b:SetScript("OnEnter",function(self) T.Button(self,true);ns.RecipeInfo.Show(self,option) end)
 b:SetScript("OnLeave",function(self) T.Button(self);GameTooltip:Hide() end)
 b:SetScript("OnHide",function(self) if GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
 b:SetScript("OnClick",function(self,mouseButton)
  if ns.API.ChatLink(option,nil,mouseButton) then return end
  if fallback then fallback() else ns.RecipeInfo.Show(self,option) end
 end)
 return b
end

-- Small native texture flags avoid missing emoji glyphs in Classic client fonts.
function T.LanguageFlag(parent,code)
 if parent.languageFlag then parent.languageFlag:Hide() end
 parent.languageFlags=parent.languageFlags or {}
 local flag=parent.languageFlags[code]
 if not flag then
  flag=CreateFrame("Frame",nil,parent);flag:SetSize(24,16)
  if parent.flagOnly then flag:SetPoint("CENTER",0,0) else flag:SetPoint("LEFT",8,0) end
  parent.languageFlags[code]=flag
  local white={1,1,1,1};local red={.8,.05,.10,1};local blue={.06,.18,.48,1}
  local function band(x,y,w,h,color) stroke(flag,x,y,w,h,color) end
  if code=="frFR" then
   band(0,0,8,16,blue);band(8,0,8,16,white);band(16,0,8,16,red)
  elseif code=="deDE" then
   band(0,0,24,5,{.02,.02,.02,1});band(0,5,24,6,red);band(0,11,24,5,{1,.78,0,1})
  elseif code=="esES" then
   band(0,0,24,4,red);band(0,4,24,8,{1,.8,.06,1});band(0,12,24,4,red)
   band(7,6,3,4,red)
  elseif code=="ruRU" then
   band(0,0,24,5,white);band(0,5,24,6,blue);band(0,11,24,5,red)
  else
   for i=0,12 do band(0,i*16/13,24,16/13,i%2==0 and red or white) end
   band(0,0,11,9,blue)
   for y=1,7,2 do for x=1,9,2 do band(x,y,1,1,white) end end
  end
 end
 parent.languageFlag=flag;flag:Show()
end
function T.RefreshLanguages()
 local saved=ns.db.settings.language or "auto"
 local code=ns.Locale.Resolve(saved)
 for _,picker in ipairs(T.languagePickers or {}) do
  T.LanguageFlag(picker,code)
  for _,b in ipairs(picker.menu.buttons) do
   b.active=b.language==saved or saved=="auto" and b.language==code;T.Button(b)
  end
  picker.menu.reload:SetEnabled(code~=ns.Locale.code)
 end
end
function T.LanguagePicker(owner,top)
 if owner.languagePicker then return owner.languagePicker end
 local function control(parent,label,width)
  local b=CreateFrame("Button",nil,parent,"BackdropTemplate");b:SetSize(width,28)
  local text=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  text:SetPoint("CENTER");text:SetWidth(width-14);b:SetFontString(text);b:SetText(label);T.Button(b)
  b:SetScript("OnEnter",function(self) T.Button(self,true) end)
  b:SetScript("OnLeave",function(self) T.Button(self);GameTooltip:Hide() end)
  return b
 end
 local picker=control(owner,"",36);owner.languagePicker=picker;picker.flagOnly=true
 picker:SetPoint("TOPRIGHT",-58,-top);picker:SetFrameLevel(owner:GetFrameLevel()+4)
 local menu=CreateFrame("Frame",nil,owner,"BackdropTemplate");picker.menu=menu
 T.Surface(menu);T.CaptureWheel(menu)
 local menuWidth=(#ns.Locale.choices-1)*40+16
 menu:SetSize(menuWidth,84)
 menu:SetPoint("TOPRIGHT",picker,"BOTTOMRIGHT",0,-5);menu.buttons={};menu:Hide()
 local index=0
 for _,entry in ipairs(ns.Locale.choices) do
  if entry.id~="auto" then
   index=index+1
   local choice=entry.id;local languageName=entry.name
   local b=control(menu,"",36);menu.buttons[index]=b;b.language=choice;b.flagOnly=true
   b:SetPoint("TOPLEFT",8+(index-1)*40,-8)
   T.LanguageFlag(b,choice)
   b:SetScript("OnClick",function() ns.Locale.Set(choice) end)
   b:SetScript("OnEnter",function(self)
    T.Button(self,true);GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(ns.L(languageName));GameTooltip:Show()
   end)
  end
 end
 menu.reload=control(menu,"/reload",menuWidth-16);menu.reload:SetPoint("TOPLEFT",8,-48)
 menu.reload:SetScript("OnClick",function() if ReloadUI then ReloadUI() end end)
 picker:SetScript("OnClick",function()
  if menu:IsShown() then menu:Hide();return end
  for _,other in ipairs(T.languagePickers) do other.menu:Hide() end
  T.RefreshLanguages();T.WindowMenu(menu,owner);menu:Show()
 end)
 picker:SetScript("OnEnter",function(self)
  T.Button(self,true);GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(ns.L("Sprache"))
  GameTooltip:AddLine(ns.L("Sprache für GearWise. Nach Änderung /reload ausführen. Namen, Chatlinks und originale Tooltips bleiben in der Spielsprache."),.82,.77,.65,true);GameTooltip:Show()
 end)
 owner:HookScript("OnHide",function() menu:Hide() end)
 T.languagePickers=T.languagePickers or {};table.insert(T.languagePickers,picker)
 T.RefreshLanguages();return picker
end
