local _,ns=...
local V={};ns.Presentation=V
local T,A,S,P,I=ns.Theme,ns.API,ns.Shopping,ns.Advice,ns.Impact
local C=T.colors
function V.Place(f,x,y) f:ClearAllPoints();f:SetPoint('TOPLEFT',x,-y) end
function V.Label(parent,value,x,y,width,font,color)
 local t=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlightSmall');T.Font(t,font=='GameFontNormalLarge' and 24 or font=='GameFontHighlight' and 14 or 12)
 V.Place(t,x,y);t:SetWidth(width);t:SetJustifyH('LEFT');t:SetJustifyV('TOP');t:SetSpacing(2);t:SetText(value);t:SetTextColor(unpack(color or C.text));return t
end
function V.Button(parent,value,x,y,width,fn)
 local b=CreateFrame('Button',nil,parent,'BackdropTemplate');b:SetSize(width,28);V.Place(b,x,y)
 local t=V.Label(b,value,6,6,width-12);t:ClearAllPoints();t:SetPoint('CENTER');t:SetJustifyH('CENTER');b:SetFontString(t);b:SetText(value)
 b:SetScript('OnClick',fn);b:SetScript('OnEnter',function(self) T.Button(self,true) end)
 b:SetScript('OnLeave',function(self) T.Button(self);GameTooltip:Hide() end);T.Button(b);return b
end
function V.Bonus(option)
 local s=P.Stats(option).stats;local value=s.strength
 if value and value==s.agility and value==s.stamina and value==s.intellect and value==s.spirit then
  local count=0;for _ in pairs(s) do count=count+1 end
  if count==5 then return string.format(ns.L('+%d auf alle Hauptattribute'),value) end
 end
 return ns.Procs.CardText(option)
end
function V.Cost(requirements,compact)
 local e=S.Estimate(requirements)
 if compact and e.total>0 then return (e.complete and '' or ns.L('ab '))..ns.Money(e.total) end
 return e.total>0 and S.PriceText(e) or e.complete and #requirements>0 and ns.Money(0) or '—'
end
function V.PriceAge(id)
 if ns.db.settings.showPriceAge==false then return end
 local _,age=S.Price(id)
 if ns.IsPublicNumber(age) and age>0 then GameTooltip:AddLine(ns.L('Preisstand: vor ')..ns.Impact.Number(age)..ns.L(' Tagen'),.70,.65,.54,true) end
end
function V.Hide(holder)
 for _,key in ipairs({'materialRows','metrics','materialIcons'}) do for _,row in ipairs(holder[key] or {}) do row:Hide() end end
end
function V.Materials(parent,holder,requirements,x,y,width,onClick)
 holder.materialRows=holder.materialRows or {}
 for _,row in ipairs(holder.materialRows) do row:Hide() end
 for i,m in ipairs(requirements) do
  local row=holder.materialRows[i]
  if not row then
   row=CreateFrame('Button',nil,parent,'BackdropTemplate');holder.materialRows[i]=row;T.Surface(row)
   row.icon=row:CreateTexture(nil,'ARTWORK');row.icon:SetSize(32,32);row.icon:SetPoint('TOPLEFT',9,-9);T.IconBorder(row,row.icon)
   row.name=V.Label(row,'',52,12,width-202,'GameFontHighlight')
   row.stock=V.Label(row,'',width-142,10,130,nil,C.muted);row.stock:SetJustifyH('RIGHT')
   row.price=V.Label(row,'',width-142,30,130,nil,C.muted);row.price:SetJustifyH('RIGHT')
  end
  V.Place(row,x,y);row:SetWidth(width);row:Show()
  local name=A.ItemInfo(m.id);if not name then A.RequestItem(m.id) end
  row.name:SetWidth(width-202);row.name:SetHeight(0);row.name:SetText(m.count..' × '..T.ItemName(m.id,name or m.name or ('#'..m.id)))
  V.Place(row.stock,width-142,10);V.Place(row.price,width-142,30)
  local owned=A.Count(m.id);row.stock:SetText(ns.L('Inventar: ')..owned);row.stock:SetTextColor(unpack(owned<m.count and C.worse or C.better))
  local price=S.Price(m.id);row.price:SetText(ns.L('Stück: ')..(price and ns.Money(price) or '—'))
  row.icon:SetTexture(A.Icon({itemID=m.id}));row:SetHeight(math.max(52,row.name:GetStringHeight()+24,row.price:GetStringHeight()+36))
  T.NativeHover(row,{itemID=m.id},onClick,m.count)
  row:HookScript('OnEnter',function() V.PriceAge(m.id);GameTooltip:Show() end)
  y=y+row:GetHeight()+4
 end
 return y
end
function V.MaterialIcons(parent,holder,requirements,x,y,width,onClick)
 holder.materialIcons=holder.materialIcons or {};for _,r in ipairs(holder.materialIcons) do r:Hide() end
 local columns=math.max(1,math.floor(width/58))
 for i,m in ipairs(requirements) do
  local r=holder.materialIcons[i]
  if not r then
   r=CreateFrame('Button',nil,parent);holder.materialIcons[i]=r;r:SetSize(54,26)
   r.icon=r:CreateTexture(nil,'ARTWORK');r.icon:SetSize(24,24);r.icon:SetPoint('TOPLEFT',0,-1)
   r.count=V.Label(r,'',27,6,27)
  end
  V.Place(r,x+((i-1)%columns)*58,y+math.floor((i-1)/columns)*29);r:Show()
  r.icon:SetTexture(A.Icon({itemID=m.id}));r.count:SetText('×'..m.count)
  T.NativeHover(r,{itemID=m.id},onClick,m.count)
 end
 return y+math.ceil(#requirements/columns)*29
end
function V.Effects(option,slot,profile,impact)
 local proc=ns.Procs.Evaluate(option,slot,profile)
 local source=proc or impact or {lines={},notes={}}
 local all={};local seen={}
 for _,line in ipairs(source.lines) do
  local text=line.text
  if line.kind=='dps' then
   text='≈ '..I.Number(source.dps or line.value)..' '..ns.L(source.dps and 'Auto-DPS' or 'Basis-DPS')
  elseif line.kind=='crit' then
   local spell=line.text:find(ns.L('Prozentpunkte Zauberkrit'),1,true)
   text=I.Number(line.value)..' '..ns.L(spell and '%-Pkt. Zauberkrit' or '%-Pkt. Waffen-Krit')
  end
  for _,pair in ipairs({{'Angriffskraft (Basis)','Angriffskraft'},{'Gesundheit (Basis)','Gesundheit'},{'Mana (Basis)','Mana'},{'Rüstung (Basis)','Rüstung'}}) do
   local full,short=ns.L(pair[1]),ns.L(pair[2]);local first,last=text:find(full,1,true)
   if first then text=text:sub(1,first-1)..short..text:sub(last+1) end
  end
  if not seen[text] then all[#all+1]={text=text,value=line.value,kind=line.kind};seen[text]=true end
 end
 if proc then
  local data=ns.Procs.Data(option)
  local low,high
  if data then low,high=data.effect:match('heals for (%d+) to (%d+)') end
  if low then all[#all+1]={text=low..'–'..high..' '..ns.L('Heilung / Proc'),value=1} end
 end
 table.sort(all,function(a,b)
  local function rank(v)
   local caster=profile.role=='healer' or profile.role=='caster'
   if v.kind=='dps' then return caster and 8 or 1 end
   if v.kind=='crit' then return 2 end
   if v.text:find(ns.L('Angriffskraft'),1,true) then return caster and 9 or 3 end
   if v.text:find(ns.L('Mana'),1,true) then return caster and 3 or 6 end
   if v.text:find(ns.L('Gesundheit'),1,true) then return profile.role=='tank' and 1 or 4 end
   return caster and 1 or 5
  end
  local ar,br=rank(a),rank(b);return ar==br and a.text<b.text or ar<br
 end)
 return all,proc
end
function V.Metrics(parent,holder,values,x,y,width,expanded)
 holder.metrics=holder.metrics or {};for _,r in ipairs(holder.metrics) do r:Hide() end
 local count=expanded and #values or math.min(4,#values);local column=(width-12)/2
 local rowY=y
 for i=1,count,2 do
  local height=0
  for j=i,math.min(i+1,count) do
   local label=holder.metrics[j]
   if not label then label=V.Label(parent,'',0,0,column,'GameFontHighlight',C.better);holder.metrics[j]=label end
   V.Place(label,x+(j-i)*(column+12),rowY);label:SetWidth(column);label:SetHeight(0);label:SetText(values[j].text);T.Font(label,values[j].kind=='dps' and 18 or 16)
   label:SetTextColor(unpack(values[j].value<0 and C.worse or C.better));label:Show();height=math.max(height,label:GetStringHeight())
  end
  rowY=rowY+height+10
 end
 return rowY
end
function V.Info(parent,option,x,y,impact)
 local b=T.RecipeInfo(parent,option,x,y,function()
  local click=parent:GetScript('OnClick');if click then click(parent,'LeftButton') else ns.RecipeInfo.Show(parent.recipeInfo,option) end
 end)
 b:SetScript('OnEnter',function(self)
  T.Button(self,true);ns.RecipeInfo.Show(self,option)
  local texts={A.Description(option)}
  for _,note in ipairs(impact and impact.notes or {}) do texts[#texts+1]=note end
  if P.Stats(option).conditional then texts[#texts+1]=ns.L('Werte pro Auslösung bzw. während der Wirkung; keine durchschnittlichen DPS.') end
  for _,value in ipairs(texts) do GameTooltip:AddLine(value,.8,.76,.65,true) end;GameTooltip:Show()
 end)
 return b
end
