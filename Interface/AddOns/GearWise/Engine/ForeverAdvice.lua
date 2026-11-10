local _, ns = ...
local P = {}
ns.Advice = P
-- Sorting aid, not simulated DPS/HPS. Pinned DB2 effects take precedence over text parsing.
P.roles = {physical=ns.L("Schaden · körperlich"), caster=ns.L("Schaden · Zauber"), healer=ns.L("Heilung"), tank=ns.L("Tank"), profession=ns.L("Berufe")}
local specs = {
 PALADIN={{ns.L("Heilig"),"healer"},{ns.L("Schutz"),"tank"},{ns.L("Vergeltung"),"physical"}},
 WARRIOR={{ns.L("Waffen"),"physical"},{ns.L("Furor"),"physical"},{ns.L("Schutz"),"tank"}},
 DRUID={{ns.L("Gleichgewicht"),"caster"},{ns.L("Wilder Kampf"),"physical"},{ns.L("Wiederherstellung"),"healer"}},
 PRIEST={{ns.L("Disziplin"),"healer"},{ns.L("Heilig"),"healer"},{ns.L("Schatten"),"caster","shadow"}},
 SHAMAN={{ns.L("Elementar"),"caster","nature"},{ns.L("Verstärkung"),"physical"},{ns.L("Wiederherstellung"),"healer"}},
 MAGE={{ns.L("Arkan"),"caster","arcane"},{ns.L("Feuer"),"caster","fire"},{ns.L("Frost"),"caster","frost"}},
 WARLOCK={{ns.L("Gebrechen"),"caster","shadow"},{ns.L("Dämonologie"),"caster"},{ns.L("Zerstörung"),"caster","fire"}},
 ROGUE={{ns.L("Meucheln"),"physical"},{ns.L("Kampf"),"physical"},{ns.L("Täuschung"),"physical"}},
 HUNTER={{ns.L("Tierherrschaft"),"physical"},{ns.L("Treffsicherheit"),"physical"},{ns.L("Überleben"),"physical"}},
}
P.classes={
 {id="DRUID",label=ns.L("Druide")},{id="HUNTER",label=ns.L("Jäger")},{id="MAGE",label=ns.L("Magier")},
 {id="PALADIN",label=ns.L("Paladin")},{id="PRIEST",label=ns.L("Priester")},{id="ROGUE",label=ns.L("Schurke")},
 {id="SHAMAN",label=ns.L("Schamane")},{id="WARLOCK",label=ns.L("Hexenmeister")},{id="WARRIOR",label=ns.L("Krieger")},
}
function P.ClassName(class)
 for _,entry in ipairs(P.classes) do if entry.id==class then return entry.label end end
 return class
end
local function call(fn,...)
 if type(fn)~="function" then return nil end
 local ok,a,b,c,d,e,f,g=pcall(fn,...)
 if ok then return ns.PublicValue(a),ns.PublicValue(b),ns.PublicValue(c),ns.PublicValue(d),ns.PublicValue(e),ns.PublicValue(f),ns.PublicValue(g) end
end
function P.Profiles(requestedClass)
 local _,playerClass=UnitClass("player")
 local class=specs[requestedClass] and requestedClass or playerClass
 local result={}
 for i,spec in ipairs(specs[class] or {}) do
  -- Forever uses Classic talent trees; generic class metadata can report a
  -- class-wide role/name instead of the individual tree's role/name.
  local key,label=spec[2],spec[1]
  local focus=class=="PALADIN" and key=="tank" and "balanced" or nil
  result[#result+1]={id="spec"..i,index=i,baseLabel=label,label=label..(focus and ns.L(" · Ausgewogen") or ""),role=key,school=spec[3],class=class,focus=focus}
 end
 if class=="PALADIN" then
  local base=result[2]
  for _,choice in ipairs({{"survival",ns.L("Überleben")},{"threat",ns.L("Bedrohung")}}) do
   result[#result+1]={id="spec2_"..choice[1],index=2,baseLabel=base.baseLabel,label=base.baseLabel.." · "..choice[2],role="tank",class=class,focus=choice[1]}
  end
 end
 for _,key in ipairs({"physical","caster","healer","tank","profession"}) do
  result[#result+1]={id=key,label=P.roles[key],role=key,class=class}
 end
 return result
end
function P.Detect()
 local profiles=P.Profiles()
 local group=call(C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup or GetActiveTalentGroup,false,false)
 local info=C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo
 local best,points,tied,available=nil,0,false,0
 for i=1,3 do
  -- pointsSpent is the seventh return value; previewPointsSpent is not committed.
  local _,_,_,_,_,_,n=call(info,i,false,false,nil,nil,group)
  local first,_,legacyPoints,_,modernPoints=call(GetTalentTabInfo,i,false,false,group)
  local legacy=type(first)=="string" and legacyPoints or modernPoints
  if not ns.IsPublicNumber(n) and ns.IsPublicNumber(legacy) then n=legacy end
  if ns.IsPublicNumber(n) and n>=0 then
   available=available+1
   if n>points then best,points,tied=i,n,false elseif n==points and n>0 then tied=true end
  end
 end
 local index
 if available==3 then
  index=not tied and best or nil
 elseif available==0 then
  -- Compatibility fallback only when no tree-point data is supplied by the client.
  local getSpec=C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization or GetPrimaryTalentTree
  index=call(getSpec,false,false,group)
 end
 for _,p in ipairs(profiles) do if p.index and p.index==index then return p,true end end
 local _,class=UnitClass("player")
 local role=(class=="MAGE" or class=="WARLOCK" or class=="PRIEST") and "caster" or "physical"
 return {id=role,label=P.roles[role],role=role},false
end
local labels={strength=ns.L("Stärke"),agility=ns.L("Beweglichkeit"),stamina=ns.L("Ausdauer"),intellect=ns.L("Intelligenz"),spirit=ns.L("Willenskraft"),
 armor=ns.L("Rüstung"),defense=ns.L("Verteidigung"),attack=ns.L("Angriffskraft"),spell=ns.L("Zaubermacht"),healing=ns.L("Heilung"),mp5=ns.L("Mana / 5 Sek."),
 damage=ns.L("Waffenschaden"),haste=ns.L("Tempo %"),crit=ns.L("Krit %"),threat=ns.L("Bedrohung %"),herbalism=ns.L("Kräuterkunde"),mining=ns.L("Bergbau"),skinning=ns.L("Kürschnerei"),fishing=ns.L("Angeln"),
 fire=ns.L("Feuerschaden"),frost=ns.L("Frostschaden"),shadow=ns.L("Schattenschaden"),nature=ns.L("Naturschaden"),arcane=ns.L("Arkanschaden")}

local db2Labels={meleeAttack=ns.L("Nahkampf-Angriffskraft"),rangedAttack=ns.L("Distanz-Angriffskraft"),health=ns.L("Gesundheit direkt"),mana=ns.L("Mana direkt"),blockValue=ns.L("Blockwert"),dodge=ns.L("Ausweichchance %"),block=ns.L("Blockchance %"),hit=ns.L("Trefferchance %"),spellHit=ns.L("Zaubertrefferchance %"),meleeCrit=ns.L("Waffen-Krit %"),rangedCrit=ns.L("Distanz-Krit %"),spellCrit=ns.L("Zauberkrit %"),meleeHaste=ns.L("Nahkampftempo %"),rangedHaste=ns.L("Distanztempo %"),castHaste=ns.L("Zaubertempo %"),runSpeed=ns.L("Bewegungstempo %"),mountSpeed=ns.L("Reittempo %"),stealth=ns.L("Verstohlenheit"),holy=ns.L("Heiligschaden"),stat12=ns.L("Verteidigungswertung"),stat51=ns.L("Feuerwiderstand"),stat52=ns.L("Frostwiderstand"),stat53=ns.L("Heiligwiderstand"),stat54=ns.L("Schattenwiderstand"),stat55=ns.L("Naturwiderstand"),stat56=ns.L("Arkanwiderstand")}
for key,label in pairs(db2Labels) do labels[key]=label end
P.StatLabels=labels
local order={"strength","agility","stamina","intellect","spirit","attack","spell","healing","mp5","damage","haste","crit","threat","defense","armor","fire","frost","shadow","nature","arcane","herbalism","mining","skinning","fishing"}
for _,key in ipairs({"meleeAttack","rangedAttack","health","mana","blockValue","dodge","block","hit","spellHit","meleeCrit","rangedCrit","spellCrit","meleeHaste","rangedHaste","castHaste","runSpeed","mountSpeed","stealth","holy","stat12","stat51","stat52","stat53","stat54","stat55","stat56"}) do order[#order+1]=key end
local cache={}
local function parseStats(text)
 local t=(text or ""):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
 t=ns.Locale.Fold(t)
 local stats={}
 -- Random procs, conditions and school resistances cannot be scored as permanent flat stats.
 local chanceText=t:gsub("critical strike chance",""):gsub("chance to hit",""):gsub("chance to land a critical strike","")
 chanceText=chanceText:gsub("%d+%% chance to dodge",""):gsub("ausweichchance","")
 local proc=chanceText:find("chance",1,true)
  or t:find("often",1,true) or t:find("occasionally",1,true) or t:match("for %d+ sec")
  or t:find("gelegentlich",1,true) or t:find("manchmal",1,true) or t:match("für %d+ sek")
  or t:find("wenn ",1,true) or t:find("bei einem treffer",1,true)
  or t:find("probabilidad",1,true) or t:find("parfois",1,true) or t:find("occasionnellement",1,true)
  or t:find("иногда",1,true) or t:find("вероятностью",1,true) or t:find("при попадании",1,true)
  or t:match("pendant %d+ s") or t:match("durante %d+ s") or t:match("на %d+ сек")
 if not proc and not t:find("resistance",1,true) and not t:find("widerstand",1,true) then
  for _,key in ipairs({"strength","agility","stamina","intellect","spirit","armor","herbalism","mining","skinning","fishing"}) do
   stats[key]=tonumber(t:match("%+(%d+) "..key) or t:match("adds (%d+) "..key)
    or t:match("give (%d+) "..key) or t:match(""..key.." by (%d+)") or t:match(key.." value by (%d+)"))
  end
  local all=tonumber(t:match("%+(%d+) to all stats"))
  if all then for _,k in ipairs({"strength","agility","stamina","intellect","spirit"}) do stats[k]=all end end
  stats.attack=tonumber(t:match("attack power by (%d+)") or t:match("attack power value by (%d+)"))
  -- Catalog effects use several phrases for the same flat bonus. Keep spell
  -- damage and healing separate, including enchants which grant different amounts.
  local power=tonumber(t:match("spell power value by (%d+)") or t:match("add (%d+) to spell power") or t:match("add (%d+) spell power"))
  local both=tonumber(t:match("damage and healing by up to (%d+)") or t:match("healing and spell damage by up to (%d+)")
   or t:match("adds %+(%d+) to your healing and damage from spells") or t:match("adds (%d+) to all healing and damage spells")
   or t:match("damage and healing done by magical spells and effects up to (%d+)"))
  stats.spell=tonumber(t:match("spell damage by up to (%d+)") or t:match("damage spells by up to (%d+)")
   or t:match("add up to (%d+) damage to spells") or t:match("up to (%d+) points of damage to damage spells")) or both or power
  stats.healing=tonumber(t:match("healing by up to (%d+)") or t:match("healing spells by up to (%d+)")
   or t:match("up to (%d+) points of healing to healing spells") or t:match("healing done by magical spells and effects up to (%d+)")
   or t:match("healing done by spells and effects up to (%d+)")) or both
  if stats.healing and not stats.spell then stats.spell=tonumber(t:match("and damage by up to (%d+)")) end
  stats.mp5=tonumber(t:match("restore (%d+) mana every 5 seconds") or t:match("(%d+) mana per 5 sec"))
  stats.defense=tonumber(t:match("defense skill by (%d+)") or t:match("defense by (%d+)")
   or t:match("%+(%d+) defense") or t:match("defense skill of the wearer is increased by (%d+)"))
  stats.damage=tonumber(t:match("do (%d+) additional point") or t:match("damage by (%d+)") or t:match("do %+(%d+) damage"))
  if stats.spell or stats.healing or t:find("spell",1,true) or t:find("damage to beasts",1,true) or t:find("against elementals",1,true) then stats.damage=nil end
  stats.haste=tonumber(t:match("%+(%d+)%% attack and casting speed") or t:match("adds (%d+)%% haste"))
  stats.crit=tonumber(t:match("critical strike chance by (%d+)%%") or t:match("chance to land a critical strike with spells by (%d+)%%"))
  stats.threat=tonumber(t:match("increase threat from all attacks and spells by (%d+)%%"))
  local reduction=tonumber(t:match("decrease threat caused by the wearer by (%d+)%%"))
  if reduction then stats.threat=-reduction end
  for _,school in ipairs({"fire","frost","shadow","nature","arcane"}) do
   stats[school]=tonumber(t:match(school.." damage by up to (%d+)") or t:match("up to (%d+) additional "..school.." damage when casting"))
   if stats[school] then stats.damage=nil end
  end
  -- Client descriptions are localized; take only explicit flat stat phrases.
  local german={strength="stärke",agility="beweglichkeit",stamina="ausdauer",intellect="intelligenz",spirit="willenskraft",armor="rüstung",defense="verteidigungsfertigkeit",attack="angriffskraft",herbalism="kräuterkunde",mining="bergbau",skinning="kürschnerei",fishing="angeln"}
  for key,word in pairs(german) do
   local amount,suffix=t:match(word.." um (%d+)([^%d]*)")
   if not amount then amount,suffix=t:match("%+(%d+) "..word.."([^%d]*)") end
   if amount and not suffix:match('^%s*%%') then stats[key]=tonumber(amount) end
  end
  local all=t:match('alle werte um (%d+)') or t:match('alle attribute um (%d+)')
  if all then for _,key in ipairs({"strength","agility","stamina","intellect","spirit"}) do stats[key]=tonumber(all) end end
 end
 -- Conservative fallback for client-only flat descriptions in the other supported
 -- languages. Never score a sentence containing a proc, duration or percentage.
 if not proc and not t:find("%%") then
  local words={
   strength={"force","fuerza","силу"},agility={"agilité","agilidad","ловкость"},
   stamina={"endurance","aguante","выносливость"},intellect={"intelligence","intelecto","интеллект"},
   spirit={"esprit","espíritu","дух"},armor={"armure","armadura","броню"},
   defense={"défense","defensa","защиту"},attack={"puissance d’attaque","puissance d'attaque","poder de ataque","силу атаки"},
  }
  for key,names in pairs(words) do
   if not stats[key] then for _,name in ipairs(names) do
    local value=t:match(name.." de (%d+)") or t:match(name.." en (%d+)") or t:match(name.." на (%d+)") or t:match("%+(%d+) "..name)
    if value then stats[key]=tonumber(value);break end
   end end
  end
 end
 local summary={}
 for _,key in ipairs(order) do if stats[key] then summary[#summary+1]=(stats[key]>=0 and "+" or "")..stats[key].." "..labels[key] end end
 local result={stats=stats,summary=table.concat(summary,"  ·  "),conditional=not not proc}
 return result
end
function P.Stats(option)
 if option.observed then return option.observed end
 local description=ns.API.Description(option)
 local saved=cache[option]
 if saved and saved.description==description and saved.effect==option.effect and saved.locale==ns.Locale.code then return saved.result end
 local db2=option.db2Effect==option.effect and ns.db2Stats and ns.db2Stats[option.id]
 local structured=db2 or (ns.catalogStats and ns.catalogStats[option.id])
 local result
 if structured and (db2 or structured.effect==option.effect) then
  local summary,stats={},{}
  for _,key in ipairs(order) do
   local value=structured.stats[key]
   if value then stats[key]=value;summary[#summary+1]=(value>=0 and "+" or "")..value.." "..labels[key] end
  end
  result={stats=stats,summary=table.concat(summary,"  ·  "),conditional=structured.conditional,complete=structured.complete}
 else result=parseStats(option.effect) end
 -- Preserve verified compound catalogue bonuses; use live text to fill missing effects.
 if not db2 and not next(result.stats) and not result.conditional and description~=option.effect then result=parseStats(description) end
 cache[option]={description=description,effect=option.effect,locale=ns.Locale.code,result=result}
 return result
end
function P.BonusText(option)
 local data=P.Stats(option)
 if data.conditional and ns.Procs then return ns.Procs.Summary(option) end
 local dodge=(option.effect or ""):lower():match("(%d+)%% chance to dodge")
 if dodge and not data.conditional then return "+"..dodge..ns.L(" Prozentpunkt Ausweichchance") end
 local summary=data.summary
 if summary~="" then return summary end
 local description=ns.API.Description(option)
 if description and description~="" and description~=ns.L("Wirkung im Spiel-Tooltip prüfen") then return (data.conditional and ns.L("Proc / zeitweiser Effekt: ") or "")..description end
 return ns.L("Effekt noch nicht geladen")
end
-- Only parse the client line explicitly marked as a permanent enchantment.
-- Full-string matching prevents base item stats, temporary effects and proc text
-- from being mistaken for a flat enchant bonus.
function P.ObservedEnchant(text)
 local clean=text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
 local template=ENCHANTED_TOOLTIP_LINE
 if type(template)=='string' then
  local prefix,suffix=template:match('^(.-)%%s(.-)$')
  if prefix and clean:sub(1,#prefix)==prefix and (suffix=='' or clean:sub(-#suffix)==suffix) then
   clean=clean:sub(#prefix+1,suffix=='' and #clean or #clean-#suffix)
  end
 end
 clean=clean:gsub('^Verzaubert:%s*',''):gsub('^Enchanted:%s*','')
 local option={name=clean,effect='',enchantText=clean,observed={stats={},summary=clean}}
 local t=ns.Locale.Fold(clean)
 t=t:gsub('(%d),(%d)','%1.%2'):gsub(' und ',';'):gsub(' and ',';'):gsub(' et ',';'):gsub(' y ',';'):gsub(' и ',';'):gsub(',%s*',';'):gsub(' · ',';'):gsub('\n',';')
 local aliases={strength='strength',['stärke']='strength',agility='agility',beweglichkeit='agility',stamina='stamina',ausdauer='stamina',intellect='intellect',intelligenz='intellect',spirit='spirit',willenskraft='spirit',armor='armor',['rüstung']='armor',defense='defense',defence='defense',verteidigung='defense',['defense skill']='defense',verteidigungsfertigkeit='defense',['attack power']='attack',angriffskraft='attack',['spell power']='spell',zaubermacht='spell',['spell damage']='spell',zauberschaden='spell',healing='healing',heilung='healing',heilbonus='healing',['weapon damage']='damage',waffenschaden='damage',damage='damage',schaden='damage',herbalism='herbalism',['kräuterkunde']='herbalism',mining='mining',bergbau='mining',skinning='skinning',['kürschnerei']='skinning',fishing='fishing',angeln='fishing',['all stats']='all',['alle werte']='all',['alle attribute']='all',haste='haste',tempo='haste',threat='threat',bedrohung='threat',['critical strike']='crit',['kritische trefferchance']='crit'}
 for name,key in pairs(ns.Locale.StatAliases()) do aliases[name]=key end
 local stats={};local count=0
 for piece in t:gmatch('[^;]+') do
  piece=piece:match('^%s*(.-)%s*$')
  local value,percent,name=piece:match('^([%+%-]?%d+%.?%d*)%s*(%%?)%s+(.+)$')
  if not value then name,value,percent=piece:match('^(.-)%s+([%+%-]?%d+%.?%d*)%s*(%%?)$') end
  if name then name=name:gsub("^к%s+","") end
  local key=name and aliases[name]
  if not key or not value then return option end
  local percentStat=key=='haste' or key=='threat' or key=='crit'
  if (percent=='%')~=percentStat then return option end
  value=tonumber(value);count=count+1
  if key=='all' then for _,k in ipairs({'strength','agility','stamina','intellect','spirit'}) do stats[k]=(stats[k] or 0)+value end
  else stats[key]=(stats[key] or 0)+value end
 end
 if count>0 then option.observed.stats=stats end
 return option
end
local weights={
 physical={strength=2,agility=1.5,attack=1,damage=4,haste=10,crit=10,stamina=.15},
 caster={spell=1,intellect=.5,spirit=.15,mp5=1,haste=10,crit=10,stamina=.1},
 healer={healing=1,spell=.35,intellect=.7,spirit=.4,mp5=2,haste=8,crit=5,stamina=.1},
 tank={stamina=2,armor=.05,defense=2,agility=.8,strength=.5,threat=10,damage=.5},
 profession={herbalism=1,mining=1,skinning=1,fishing=1},
}
-- Deliberate sorting preferences, not simulated stat equivalences or TPS.
-- Spell damage contributes to Paladin Holy threat; pure healing is not threat damage.
local paladinTankWeights={
 balanced={stamina=2,armor=.05,defense=2,agility=.8,strength=.5,attack=.25,damage=.5,spell=.8,intellect=.35,mp5=.8,threat=10,crit=1},
 survival={stamina=2,armor=.05,defense=2,agility=.8,strength=.25,attack=.1,damage=.2,spell=.2,intellect=.15,mp5=.4,threat=2,crit=.25},
 threat={stamina=.6,armor=.01,defense=.5,agility=.5,strength=.7,attack=.4,damage=2,spell=1.5,intellect=.4,mp5=1,threat=15,crit=3,haste=3},
}
function P.Weight(profile,key)
 local _,playerClass=UnitClass("player")
 local class=profile.class or playerClass
 local selectedWeights=weights[profile.role] or {}
 if class=="PALADIN" and profile.role=="tank" then selectedWeights=paladinTankWeights[profile.focus] or paladinTankWeights.balanced end
 local aliases={meleeHaste="haste",rangedHaste="haste",castHaste="haste",meleeCrit="crit",rangedCrit="crit",spellCrit="crit",meleeAttack="attack",rangedAttack="attack"}
 local weight=selectedWeights[key] or selectedWeights[aliases[key]] or 0
 if (key=="meleeAttack" or key=="meleeCrit" or key=="meleeHaste") and (class=="HUNTER" or profile.role=="caster" or profile.role=="healer") then weight=0 end
 if (key=="rangedAttack" or key=="rangedCrit" or key=="rangedHaste") and class~="HUNTER" then weight=0 end
 if (key=="spellCrit" or key=="castHaste") and profile.role=="physical" then weight=0 end
 if profile.role=="tank" and (key=="dodge" or key=="block" or key=="blockValue" or key=="stat12") then weight=key=="blockValue" and .2 or key=="stat12" and 1 or 8 end
 if key=="hit" and profile.role=="physical" then weight=10 end
 if key=="spellHit" and profile.role=="caster" then weight=10 end
 if class==playerClass and profile.role=="physical" and (key=="strength" or key=="agility") then
  local fn=class=="HUNTER" and GetRangedAttackPowerForStat or GetAttackPowerForStat
  local stat=key=="strength" and 1 or 2
  local one,zero=call(fn,stat,1),call(fn,stat,0)
  if ns.IsPublicNumber(one) and ns.IsPublicNumber(zero) then
   weight=math.max(0,one-zero)+(key=="agility" and .5 or 0)
  end
 end
 return weight
end
function P.Score(option,profile)
 local data=P.Stats(option)
 local score=0
 for key,value in pairs(data.stats) do score=score+value*P.Weight(profile,key) end
 if profile.role=="caster" and profile.school then score=score+(data.stats[profile.school] or 0) end
 return score,data
end
function P.Recommendation(option,profile)
 local rules=ns.procRecommendations and ns.procRecommendations[option.spellID]
 local rule=rules and rules[profile.role]
 local _,playerClass=UnitClass("player")
 if rule and rule.classes[profile.class or playerClass] then return rule end
end
function P.Relevant(option,profile)
 local name=string.lower(option.name or "")
 local job=name:find("herbalism",1,true) or name:find("mining",1,true) or name:find("skinning",1,true) or name:find("fishing",1,true) or name:find("lotus claw",1,true)
 if profile.role=="profession" then return job~=nil or name:find("riding",1,true)~=nil or name:find("spurs",1,true)~=nil end
 if job then return false end
 local score=P.Score(option,profile)
 if score>0 or P.Recommendation(option,profile) then return true end
 -- Keep unquantified effects available separately; don't invent a numeric value from their name.
 return next(P.Stats(option).stats)==nil
end
local percentStats={haste=ns.L("Tempo"),crit=ns.L("kritische Trefferchance"),threat=ns.L("Bedrohung")}
for _,key in ipairs({"dodge","block","hit","spellHit","meleeCrit","rangedCrit","spellCrit","meleeHaste","rangedHaste","castHaste","runSpeed","mountSpeed"}) do percentStats[key]=labels[key]:gsub(" %%$","") end
local function number(value)
 local rounded=math.floor(math.abs(value)*10+.5)/10
 return ns.Locale.Decimal(tostring(rounded))
end
local function statChange(key,value)
 local sign=value>0 and "+" or value<0 and "-" or ""
 if percentStats[key] then
  return sign..number(value).." "..(math.abs(value)==1 and ns.L("Prozentpunkt ") or ns.L("Prozentpunkte "))..percentStats[key]
 end
 return sign..number(value).." "..labels[key]
end
function P.Comparison(inspection,option,state)
 local data=P.Stats(option)
 if next(data.stats)==nil then return {label=data.conditional and ns.L("Proc · zeitweiser Bonus") or ns.L("Sondereffekt"),note=ns.L("Wirkung in der Beschreibung prüfen."),comparable=false} end
 local effect=ns.L("Effekt: ")..data.summary
 if data.complete==false or data.conditional then return {label=effect,note=ns.L("Vergleich offen"),comparable=false} end
 if not inspection.context.loaded or inspection.enchantID==nil then
  return {label=effect,note=ns.L("Vergleich offen: Gegenstandsdaten werden geladen."),comparable=false}
 end
 if inspection.enchantID==0 then
  return {label=data.summary,note=ns.L("Zusätzlicher Wertebonus gegenüber einem unverzauberten Item."),comparable=true}
 end
 local current=inspection.current and P.Stats(inspection.current)
 if not current or next(current.stats)==nil or current.complete==false or current.conditional then
  return {label=effect,note=ns.L("Vergleich offen: vorhandene Verzauberung nicht eindeutig bekannt."),comparable=false}
 end
 local changes,keys={},{}
 for _,key in ipairs(order) do
  local old,new=current.stats[key] or 0,data.stats[key] or 0
  if current.stats[key]~=nil or data.stats[key]~=nil then keys[#keys+1]=key end
  if old~=new then changes[#changes+1]={key=key,value=new-old,text=statChange(key,new-old)} end
 end
 table.sort(changes,function(a,b)
  if (a.value<0)~=(b.value<0) then return a.value<0 end
  return a.key<b.key
 end)
 local parts={};for _,change in ipairs(changes) do parts[#parts+1]=change.text end
 local result={changes=changes,label=#changes>0 and table.concat(parts," · ") or ns.L("Gleicher Wertebonus"),
  note=ns.L("Änderung gegenüber deiner vorhandenen Verzauberung. Verluste durch Ersetzen sind enthalten."),comparable=true}
 -- Percentages compare the same single enchantment bonus, never weighted scores or character DPS.
 if #keys==1 then
  local key=keys[1];local old,new=current.stats[key] or 0,data.stats[key] or 0
  if old>0 and new>0 and new~=old and not percentStats[key] then
   result.percent=(new-old)/old*100
   local sign=result.percent>0 and "+" or "-"
   result.label=result.label..ns.L(" · Bonus ")..sign..number(result.percent).." %"
   result.note=number(old).." → "..number(new).." "..labels[key]..ns.L(" durch die Verzauberung. Der Prozentwert bezieht sich nur auf diesen Bonus.")
  end
 end
 return result
end
function P.Grade(inspection,option,profile,maximum,state)
 local score,data=P.Score(option,profile)
 local comparison=P.Comparison(inspection,option,state)
 local function result(group) return group,comparison.label,score,data,comparison end
 if state=="blocked" then return result(7) end
 if not inspection.context.loaded or inspection.enchantID==nil then return result(6) end
 if score<=0 then return result(5) end
 local current=inspection.current
 if inspection.enchantID>0 and (not current or P.Score(current,profile)<=0) then return result(6) end
 local delta=score-(current and P.Score(current,profile) or 0)
 if delta<=0 then return result(4) end
 local ratio=delta/math.max(1,maximum)
 return result(ratio>=.65 and 1 or ratio>=.3 and 2 or 3)
end
P.explanation=ns.L("Die Sortierung berücksichtigt deine Ausrichtung. Angezeigt werden konkrete Werteänderungen. Prozentangaben vergleichen ausschließlich denselben bekannten Verzauberungsbonus; sie sind keine Aussage über Schaden oder Heilung des Charakters.")

ns.Locale.Track(P.roles)
ns.Locale.Track(specs)
ns.Locale.Track(P.classes)
ns.Locale.Track(labels)
ns.Locale.Track(percentStats)
