local _,ns=...
local M={};ns.Planner=M
local A,P,R,I=ns.API,ns.Advice,ns.Rules,ns.Impact
M.items={};M.bySlot={}
local statIDs={[0]="mana",[1]="health",[3]="agility",[4]="strength",[5]="intellect",[6]="spirit",[7]="stamina",[38]="attack",[39]="rangedAttack",[41]="healing",[42]="spell",[43]="mp5",[45]="spellPower",[48]="blockValue",[50]="bonusArmor"}
local statKeys={ITEM_MOD_STRENGTH_SHORT="strength",ITEM_MOD_AGILITY_SHORT="agility",ITEM_MOD_STAMINA_SHORT="stamina",ITEM_MOD_INTELLECT_SHORT="intellect",ITEM_MOD_SPIRIT_SHORT="spirit",ITEM_MOD_HEALTH_SHORT="health",ITEM_MOD_MANA_SHORT="mana",ITEM_MOD_ATTACK_POWER_SHORT="attack",ITEM_MOD_RANGED_ATTACK_POWER_SHORT="rangedAttack",ITEM_MOD_SPELL_POWER_SHORT="spellPower",ITEM_MOD_SPELL_DAMAGE_DONE_SHORT="spell",ITEM_MOD_SPELL_HEALING_DONE_SHORT="healing",ITEM_MOD_MANA_REGENERATION_SHORT="mp5",RESISTANCE0_NAME="armor",ITEM_MOD_EXTRA_ARMOR_SHORT="bonusArmor",ITEM_MOD_BLOCK_VALUE_SHORT="blockValue",ITEM_MOD_DEFENSE_SKILL_RATING_SHORT="stat12",ITEM_MOD_DODGE_RATING_SHORT="stat13",ITEM_MOD_PARRY_RATING_SHORT="stat14",ITEM_MOD_BLOCK_RATING_SHORT="stat15",ITEM_MOD_HIT_RATING_SHORT="stat31",ITEM_MOD_CRIT_RATING_SHORT="stat32",ITEM_MOD_HASTE_RATING_SHORT="stat36"}
for id,key in pairs({[16]="ITEM_MOD_HIT_MELEE_RATING_SHORT",[17]="ITEM_MOD_HIT_RANGED_RATING_SHORT",[18]="ITEM_MOD_HIT_SPELL_RATING_SHORT",[19]="ITEM_MOD_CRIT_MELEE_RATING_SHORT",[20]="ITEM_MOD_CRIT_RANGED_RATING_SHORT",[21]="ITEM_MOD_CRIT_SPELL_RATING_SHORT",[28]="ITEM_MOD_HASTE_MELEE_RATING_SHORT",[29]="ITEM_MOD_HASTE_RANGED_RATING_SHORT",[30]="ITEM_MOD_HASTE_SPELL_RATING_SHORT",[51]="RESISTANCE2_NAME",[52]="RESISTANCE4_NAME",[53]="RESISTANCE1_NAME",[54]="RESISTANCE5_NAME",[55]="RESISTANCE3_NAME",[56]="RESISTANCE6_NAME"}) do statKeys[key]="stat"..id end
M.labels={strength=ns.L("Stärke"),agility=ns.L("Beweglichkeit"),stamina=ns.L("Ausdauer"),intellect=ns.L("Intelligenz"),spirit=ns.L("Willenskraft"),health=ns.L("Gesundheit direkt"),mana=ns.L("Mana direkt"),armor=ns.L("Rüstung"),bonusArmor=ns.L("Bonusrüstung"),attack=ns.L("Angriffskraft"),rangedAttack=ns.L("Distanz-Angriffskraft"),spell=ns.L("Zauberschaden"),healing=ns.L("Heilbonus"),mp5=ns.L("Mana / 5 Sek."),damage=ns.L("Waffenschaden"),haste=ns.L("Tempo %"),crit=ns.L("Krit %"),threat=ns.L("Bedrohung %"),defense=ns.L("Verteidigung"),blockValue=ns.L("Blockwert"),herbalism=ns.L("Kräuterkunde"),mining=ns.L("Bergbau"),skinning=ns.L("Kürschnerei"),fishing=ns.L("Angeln"),fire=ns.L("Feuerschaden"),frost=ns.L("Frostschaden"),shadow=ns.L("Schattenschaden"),nature=ns.L("Naturschaden"),arcane=ns.L("Arkanschaden")}
local ratingNames={[12]=ns.L("Verteidigungswertung"),[13]=ns.L("Ausweichwertung"),[14]=ns.L("Parierwertung"),[15]=ns.L("Blockwertung"),[16]=ns.L("Nahkampf-Trefferwertung"),[17]=ns.L("Distanz-Trefferwertung"),[18]=ns.L("Zauber-Trefferwertung"),[19]=ns.L("Nahkampf-Kritwertung"),[20]=ns.L("Distanz-Kritwertung"),[21]=ns.L("Zauber-Kritwertung"),[28]=ns.L("Nahkampf-Tempowertung"),[29]=ns.L("Distanz-Tempowertung"),[30]=ns.L("Zauber-Tempowertung"),[31]=ns.L("Trefferwertung"),[32]=ns.L("Kritwertung"),[36]=ns.L("Tempowertung"),[51]=ns.L("Feuerwiderstand"),[52]=ns.L("Frostwiderstand"),[53]=ns.L("Heiligwiderstand"),[54]=ns.L("Schattenwiderstand"),[55]=ns.L("Naturwiderstand"),[56]=ns.L("Arkanwiderstand")}
for id,label in pairs(ratingNames) do M.labels["stat"..id]=label end
for key,label in pairs(P.StatLabels) do if not M.labels[key] then M.labels[key]=label end end
local function add(t,k,v) if ns.IsPublicNumber(v) then t[k]=(t[k] or 0)+v end end
local function normalize(t)
 if t.spellPower then add(t,"spell",t.spellPower);add(t,"healing",t.spellPower);t.spellPower=nil end
 if t.bonusArmor then add(t,"armor",t.bonusArmor);t.bonusArmor=nil end
 return t
end
local function contains(t,v) for _,x in ipairs(t or {}) do if x==v then return true end end end
local function fits(option,context)
 return contains(option.slots,context.slot)
  and (not option.equipLocs or contains(option.equipLocs,context.equipLoc))
  and (not option.weaponTypes or context.classID==2 and contains(option.weaponTypes,context.subclassID))
  and (not option.db2ItemClass or option.db2ItemClass<0 or option.db2ItemClass==context.classID)
  and (not option.db2Subclasses or contains(option.db2Subclasses,context.subclassID))
end
function M.ID(ref) return tonumber(type(ref)=="number" and ref or type(ref)=="string" and (ref:match("item:(%d+)") or ref:match("^%s*(%d+)%s*$"))) end
function M.Reference(ref) return type(ref)=="string" and ref:match("item:[%d:%-]+") or M.ID(ref) and ("item:"..M.ID(ref)..":0:") end
for _,r in ipairs(ns.itemCatalog or {}) do
 local item={id=r[1],name=r[2],quality=r[3],itemLevel=r[4],requiredLevel=r[5],classID=r[6],subclassID=r[7],equipLoc=r[8],icon=r[9],armor=r[10],dps=r[11],speed=r[12],stats=r[13],effects=r[14]~=0,setID=r[15],slots=r[16]}
 local slots={}
 for _,slot in ipairs(item.slots) do
  for _,option in ipairs(ns.bySlot[slot] or {}) do
   if fits(option,{slot=slot,equipLoc=item.equipLoc,classID=item.classID,subclassID=item.subclassID}) then slots[#slots+1]=slot;break end
  end
 end
 item.slots=slots
 if #slots>0 then
  M.items[item.id]=item
  for _,slot in ipairs(slots) do M.bySlot[slot]=M.bySlot[slot] or {};table.insert(M.bySlot[slot],item) end
 end
end
ns.itemCatalog=nil
function M.State()
 if type(ns.char.planner)~="table" then ns.char.planner={} end
 local state=ns.char.planner
 if type(state.slots)~="table" then state.slots={} end
 return state
end
function M.Class()
 local selected=M.State().class
 for _,entry in ipairs(P.classes) do if entry.id==selected then return selected end end
 return select(2,UnitClass('player'))
end
function M.SetClass(class)
 local valid=false;for _,entry in ipairs(P.classes) do if entry.id==class then valid=true;break end end
 if not valid then return false end
 local state=M.State();state.profilesByClass=state.profilesByClass or {}
 state.profilesByClass[M.Class()]=M.Profile().id
 state.class=class
 local _,own=UnitClass('player')
 state.profile=state.profilesByClass[class] or (class==own and (ns.char.preferredProfile or P.Detect().id)) or 'spec1'
 return true
end
function M.UseActiveProfile()
 local _,class=UnitClass('player');M.SetClass(class)
 M.State().profile=P.Detect().id
end
function M.Profiles()
 local profiles=P.Profiles(M.Class());local order={}
 for i,p in ipairs(profiles) do order[p]=i end
 table.sort(profiles,function(a,b) local ai,bi=a.index or math.huge,b.index or math.huge;if ai~=bi then return ai<bi end;return order[a]<order[b] end)
 return profiles
end
function M.Profile()
 local class=M.Class();local _,own=UnitClass('player')
 local id=M.State().profile or (class==own and ns.char.preferredProfile)
 local profiles=P.Profiles(class)
 for _,p in ipairs(profiles) do if p.id==id then return p end end
 if class==own then return P.Detect() end
 return profiles[1]
end
function M.Name(item)
 return A.ItemInfo(item.id) or item.name
end
M.qualities={
 {id=0,label=ns.L("Schlecht"),color={.62,.62,.62}},
 {id=1,label=ns.L("Gewöhnlich"),color={1,1,1}},
 {id=2,label=ns.L("Ungewöhnlich"),color={.12,1,0}},
 {id=3,label=ns.L("Selten"),color={.25,.60,1}},
 {id=4,label=ns.L("Episch"),color={.72,.40,1}},
 {id=5,label=ns.L("Legendär"),color={1,.50,0}},
 {id=6,label=ns.L("Artefakt"),color={.90,.80,.50}},
}
function M.IsQualityShown(quality)
 local excluded=M.State().excludedQualities
 return type(excluded)~="table" or excluded[tostring(quality)]~=true
end
function M.ToggleQuality(quality)
 local state=M.State()
 if type(state.excludedQualities)~="table" then state.excludedQualities={} end
 local key=tostring(quality);state.excludedQualities[key]=not state.excludedQualities[key] or nil
end
function M.ShowAllQualities() M.State().excludedQualities={} end
function M.Search(slot,query)
 local found={};local q=ns.Locale.Fold(query);local id=M.ID(query)
 for _,item in ipairs(M.bySlot[slot] or {}) do
  local placeholder=item.name:match("^%d+ Green ") or item.name:match("^%d+ Epic ")
  if not placeholder and M.IsQualityShown(item.quality) and (id and item.id==id or not id and (q=="" or ns.Locale.Fold(item.name):find(q,1,true) or ns.Locale.Fold(M.Name(item)):find(q,1,true))) then found[#found+1]=item end
 end
 table.sort(found,function(a,b) if a.itemLevel~=b.itemLevel then return a.itemLevel>b.itemLevel end;return a.id<b.id end)
 return found
end
function M.Current(slot)
 local ref=GetInventoryItemLink("player",slot)
 return {ref=ref,option=A.CurrentEnchant(slot,ref),enchantID=ref and R.ParseEnchant(ref) or 0}
end
function M.Preview(slot)
 local entry=M.State().slots[tostring(slot)]
 if entry==nil then return M.Current(slot) end
 if entry==false then return {enchantID=0} end
 return {ref=entry.ref,option=ns.byID[entry.enchant],enchantID=0,planned=true}
end
function M.Context(slot,preview)
 local c=A.Context(slot);local id=M.ID(preview.ref);local item=M.items[id]
 c.item=preview.ref
 if item then
  c.name=M.Name(item);c.itemLevel=item.itemLevel;c.equipLoc=item.equipLoc;c.texture=item.icon;c.classID=item.classID;c.subclassID=item.subclassID;c.loaded=true
 elseif preview.ref then
  local name,_,_,il,_,_,_,_,loc,icon,_,cls,sub=A.ItemInfo(preview.ref)
  c.name,c.itemLevel,c.equipLoc,c.texture,c.classID,c.subclassID=name,il,loc,icon,cls,sub;c.loaded=name~=nil
 else c.loaded=false;c.name=nil end
 return c
end
function M.Fits(option,context)
 return fits(option,context)
end
-- Compare the equipped effect with the usable recommendations for the selected profile.
-- Unidentified and unranked effects remain "present", never automatically "top".
function M.SlotStatus(slot,snapshot)
 snapshot=snapshot or M.Current(slot)
 if not snapshot.ref then return 'empty',ns.L('Kein Gegenstand angelegt') end
 local context=M.Context(slot,snapshot);local current=snapshot.option
 local present=current or (snapshot.enchantID or 0)>0
 local presentText=ns.L('Dauerhafte Verbesserung vorhanden')
 if not context.loaded or snapshot.enchantID==nil then
  return present and 'enhanced' or 'unknown',present and presentText or ns.L('Gegenstandsdaten werden geladen')
 end
 local profile=M.Profile();local score,data=0,nil;local priority=0;local ranked=false
 if current then
  score,data=P.Score(current,profile)
  local recommendation=P.Recommendation(current,profile);priority=recommendation and recommendation.priority or 0
  ranked=P.Relevant(current,profile) and (priority>0 or score>0 and data.complete~=false and not data.conditional)
 end
 local pending,blocked;local usable=false;local better=false
 for _,option in ipairs(ns.bySlot[slot] or {}) do
  if M.Fits(option,context) then
   local state,reason=R.Evaluate(option,context)
   if state=='usable' then
    usable=true
    if present and ranked and P.Relevant(option,profile) then
     local recommendation=P.Recommendation(option,profile);local optionPriority=recommendation and recommendation.priority or 0
     if optionPriority>priority or optionPriority==priority and P.Score(option,profile)>score+.0001 then better=true end
    end
   elseif state=='unknown' then pending=pending or reason else blocked=blocked or reason end
  end
 end
 if present then
  if ranked and usable and not better then return 'top',ns.L('Beste aktuell nutzbare Verbesserung für die gewählte Skillung') end
  return 'enhanced',presentText
 end
 if usable then return 'missing',ns.L('Nutzbare Verbesserung fehlt') end
 if pending then return 'unknown',pending end
 if blocked then return 'blocked',blocked end
 return 'none',ns.L('Keine passenden Verbesserungen')
end
function M.SelectItem(slot,ref)
 local item=M.items[M.ID(ref)]
 if not item or not contains(item.slots,slot) then return false,ns.L("Item passt nicht in diesen Slot.") end
 local slots=M.State().slots
 local main=M.Preview(16);local weapon=M.items[M.ID(main.ref)]
 local mainLoc=weapon and weapon.equipLoc or select(9,A.ItemInfo(main.ref))
 if slot==17 and mainLoc=="INVTYPE_2HWEAPON" then return false,ns.L("Zweihandwaffe belegt die Nebenhand.") end
 slots[tostring(slot)]={ref=M.Reference(ref),enchant=false}
 if slot==16 then
  if item.equipLoc=="INVTYPE_2HWEAPON" then slots['17']=false
  elseif slots['17']==false then slots['17']=nil end
 end
 return true
end
function M.SelectEnchant(slot,id)
 local preview=M.Preview(slot)
 if not preview.ref then return false end
 local option=id and ns.byID[id]
 if id and (not option or not M.Fits(option,M.Context(slot,preview))) then return false end
 M.State().slots[tostring(slot)]={ref=preview.ref,enchant=id or false}
 return true
end
function M.Reset(slot)
 local slots=M.State().slots
 if slot then
  if slot==17 then
   local main=M.items[M.ID(M.Preview(16).ref)]
   if main and main.equipLoc=="INVTYPE_2HWEAPON" and slots['16'] then return end
  end
  slots[tostring(slot)]=nil
  -- Restore an off-hand automatically cleared by a planned two-hander.
  if slot==16 and slots['17']==false then slots['17']=nil end
 else M.State().slots={} end
end
function M.Recipes(slot,query)
 local fold=ns.Locale.Fold
 local q=fold(query):match('^%s*(.-)%s*$');local list={};local profile=M.Profile()
 for _,option in ipairs(ns.bySlot[slot] or {}) do
  local profession=ns.professions[option.profession]
  local text=table.concat({A.Name(option),option.name or '',option.effect or '',P.Stats(option).summary,profession and profession.name or '',tostring(option.spellID or ''),tostring(option.itemID or '')},' ')
  if q=='' or fold(text):find(q,1,true) then list[#list+1]={option=option,score=P.Score(option,profile),recommendation=P.Recommendation(option,profile)} end
 end
 table.sort(list,function(a,b)
  local ap=a.recommendation and a.recommendation.priority or 0
  local bp=b.recommendation and b.recommendation.priority or 0
  if ap~=bp then return ap>bp end
  if a.score~=b.score then return a.score>b.score end
  local an,bn=fold(A.Name(a.option)),fold(A.Name(b.option))
  if an~=bn then return an<bn end
  return a.option.id<b.option.id
 end)
 return list
end
function M.Options(slot,preview)
 preview=preview or M.Preview(slot);local context=M.Context(slot,preview);local profile=M.Profile();local list={}
 if not preview.ref then return list,context end
 for _,o in ipairs(ns.bySlot[slot] or {}) do
  if M.Fits(o,context) then
   local state,reason,kind=R.Evaluate(o,context)
   list[#list+1]={option=o,state=state,reason=reason,kind=kind,score=P.Score(o,profile),recommendation=P.Recommendation(o,profile)}
  end
 end
 table.sort(list,function(a,b)
  if (a.state=="blocked")~=(b.state=="blocked") then return a.state~="blocked" end
  local ap=a.recommendation and a.recommendation.priority or 0
  local bp=b.recommendation and b.recommendation.priority or 0
  if ap~=bp then return ap>bp end
  if a.score~=b.score then return a.score>b.score end
  return a.option.id<b.option.id
 end)
 return list,context
end
function M.ItemStats(ref)
 if not ref then return {},true,false end
 local item=M.items[M.ID(ref)];local stats={};local known=item~=nil;local liveLoaded=false
 if item then
  add(stats,"armor",item.armor)
  for i=1,#item.stats,2 do add(stats,statIDs[item.stats[i]] or ("stat"..item.stats[i]),item.stats[i+1]) end
 end
 -- The client provides base-item stats for an exact link, including random suffixes.
 local fn=C_Item and C_Item.GetItemStats or GetItemStats
 if fn then
  local ok,live=pcall(fn,ref)
  if ok and ns.PublicValue(live) and type(live)=="table" and (not canaccesstable or canaccesstable(live)) and A.ItemInfo(ref) then
   local mapped={};local unmapped=false
   for key,value in pairs(live) do
    if not ns.IsPublicNumber(value) then unmapped=true
    elseif statKeys[key] then add(mapped,statKeys[key],value)
    elseif value~=0 and key~="ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then unmapped=true end
   end
   stats=mapped;known=not unmapped;liveLoaded=true
  end
 end
 local fields={}
 for value in (ref..":"):gmatch("([^:]*):") do fields[#fields+1]=value end
 local suffix=tonumber(fields[8]) or 0
 if suffix~=0 and not liveLoaded then known=false end
 return normalize(stats),known,item and (item.effects or item.setID~=0) or false
end
function M.SnapshotStats(snapshot)
 local stats,known,special=M.ItemStats(snapshot.ref)
 if snapshot.option then
  local decoded=P.Stats(snapshot.option)
  local bonus=decoded.stats
  if decoded.complete==false then known=false end
  if decoded.conditional then special=true end
  for k,v in pairs(bonus) do add(stats,k,v) end
  if not next(bonus) then special=true end
 elseif (snapshot.enchantID or 0)>0 then known=false end
 return stats,known,special
end
function M.RequirementWarnings(ref)
 local result={};local seen={}
 local fn=C_TooltipInfo and C_TooltipInfo.GetHyperlink
 if not ref or not fn then return result end
 local ok,data=pcall(fn,ref)
 if not ok or not data or not data.lines then return result end
 for _,line in ipairs(data.lines) do
  for _,side in ipairs({"left","right"}) do
   local color,text=line[side.."Color"],line[side.."Text"]
   if color and color.GetRGB and type(text)=="string" then
    local r,g,b=color:GetRGB()
    if ns.IsPublicNumber(r) and ns.IsPublicNumber(g) and ns.IsPublicNumber(b) and r>.75 and g<.3 and b<.3 and not seen[text] then
     seen[text]=true;result[#result+1]=text
    end
   end
  end
 end
 return result
end
function M.Compare(onlySlot,plan)
 plan=plan or M.State().slots
 local result={delta={},changed=0,complete=true,special=false,weapons={},warnings={},procs={}}
 for _,s in ipairs(ns.slots) do
  local entry=plan[tostring(s.id)]
  if entry~=nil and (not onlySlot or onlySlot==s.id) then
   result.changed=result.changed+1
   local current=M.Current(s.id)
   local preview=entry==false and {enchantID=0} or {ref=entry.ref,option=ns.byID[entry.enchant],enchantID=entry.enchantID or 0}
   if (current.option and current.option.id)~=(preview.option and preview.option.id) then
    for _,choice in ipairs({{option=preview.option},{option=current.option,removed=true}}) do
     if choice.option and P.Stats(choice.option).conditional then
      result.procs[#result.procs+1]={slot=s.id,option=choice.option,removed=choice.removed}
     end
    end
   end
   local before,k1,fx1=M.SnapshotStats(current);local after,k2,fx2=M.SnapshotStats(preview)
   for key,v in pairs(after) do add(result.delta,key,v) end
   for key,v in pairs(before) do add(result.delta,key,-v) end
   result.complete=result.complete and k1 and k2;result.special=result.special or fx1 or fx2
   local item=M.items[M.ID(preview.ref)]
   if item and item.requiredLevel>UnitLevel('player') then result.warnings[#result.warnings+1]=s.label..ns.L(": benötigt Stufe ")..item.requiredLevel end
   for _,warning in ipairs(M.RequirementWarnings(preview.ref)) do result.warnings[#result.warnings+1]=s.label..': '..warning end
   if preview.option then
    local state,reason=R.Evaluate(preview.option,M.Context(s.id,preview))
    if state=='blocked' then result.warnings[#result.warnings+1]=s.label..": "..reason end
   end
   if s.id==16 or s.id==17 or s.id==18 then
    local old=M.items[M.ID(current.ref)]
    if (not current.ref or old) and (not preview.ref or item) then
     result.weapons[#result.weapons+1]={slot=s.id,label=s.label,value=(item and item.dps or 0)-(old and old.dps or 0)}
    end
   end
  end
 end
 local profile=M.Profile();local score=0
 for k,v in pairs(result.delta) do score=score+v*P.Weight(profile,k) end
 if profile.school then score=score+(result.delta[profile.school] or 0) end
 result.verdict=score>.0001 and 'better' or score<-.0001 and 'worse' or 'equal'
 -- Stat conversions use the active character, not a fictional talent respec.
 local _,ownClass=UnitClass('player');result.foreignClass=profile.class and profile.class~=ownClass
 if result.foreignClass then result.impact={lines={},notes={}}
 else
  local c=I.Context(profile);c.noWeaponEstimate=true
  result.impact=I.Derive({delta=result.delta,lines={},notes={}}, {context={slot=5}},profile,c)
 end
 for _,proc in ipairs(result.procs) do
  local c
  if not result.foreignClass then c=I.Context(profile);c.noWeaponEstimate=true end
  proc.result=ns.Procs.Evaluate(proc.option,proc.slot,profile,c)
 end
 return result
end
-- The equipped-gear plan is separate from the existing wish-item plan.
function M.GearPlan()
 local state=M.State();state.gearSlots=type(state.gearSlots)=="table" and state.gearSlots or {}
 for slot,entry in pairs(state.gearSlots) do
  local current=M.Current(tonumber(slot))
  if not current.ref or M.Reference(current.ref)~=M.Reference(entry.ref) or current.option and current.option.id==entry.enchant then state.gearSlots[slot]=nil end
 end
 return state.gearSlots
end
function M.PlanUpgrade(slot,option)
 local current=M.Current(slot)
 if not current.ref or not option or not M.Fits(option,M.Context(slot,current)) then return false end
 M.GearPlan()[tostring(slot)]={ref=current.ref,enchant=option.id}
 return true
end
function M.UpgradeCart(plan)
 local cart={}
 for slot,entry in pairs(plan) do
  local option=type(entry)=="table" and ns.byID[entry.enchant]
  local current=M.Current(tonumber(slot))
  if option and (not current.option or current.option.id~=option.id or M.ID(current.ref)~=M.ID(entry.ref)) then
   cart[slot]={slot=tonumber(slot),id=option.id,mode=option.itemID and option.tradable~=false and "item" or "materials",quantity=1}
  end
 end
 return ns.Shopping.Aggregate(cart,ns.byID,A.Count)
end
function M.TransferUpgrades(plan)
 local _,entries=M.UpgradeCart(plan);local added=0
 for _,entry in ipairs(entries) do
  if #entry.requirements>0 then
   -- A plan has one application per slot; repeating transfer must not double it.
   local key=ns.Shopping.Find(entry.slot,entry.option,entry.mode)
   if not key then local ok=ns.Shopping.Append(entry.slot,entry.option,entry.mode);if ok then added=added+1 end end
  end
 end
 return added
end
function M.StatLines(stats)
 local lines={}
 for k,v in pairs(stats) do if math.abs(v)>.0001 then lines[#lines+1]={key=k,value=v,text=I.Number(v).." "..(M.labels[k] or _G[k] or k)} end end
 table.sort(lines,function(a,b) return a.text:sub(2)<b.text:sub(2) end)
 return lines
end

ns.Locale.Track(M.labels)
ns.Locale.Track(M.qualities)
