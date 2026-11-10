local _,ns=...
local I={};ns.Impact=I
local P=ns.Advice
-- Source: Blizzard's Forever/Camelot PaperDoll, commit 9a789c074b8e73c5d604ef2d6af3bb5b3aefb348.
local function call(fn,...)
 if type(fn)~="function" then return nil end
 local ok,a,b,c,d,e,f,g=pcall(fn,...)
 if ok then return ns.PublicValue(a),ns.PublicValue(b),ns.PublicValue(c),ns.PublicValue(d),ns.PublicValue(e),ns.PublicValue(f),ns.PublicValue(g) end
end
local numeric=ns.IsPublicNumber
function I.Number(v)
 if not numeric(v) then return ns.L("unbekannt") end
 local s=string.format(math.abs(v)<.01 and "%.3f" or "%.2f",math.abs(v)):gsub("0+$",""):gsub("%.$","")
 return (v>0 and "+" or v<0 and "-" or "")..ns.Locale.Decimal(s)
end
function I.Context(profile)
 local _,class=UnitClass("player")
 local c={class=class,stats={},profile=profile}
 for i=1,5 do local _,value=call(UnitStat,"player",i);if numeric(value) then c.stats[i]=value end end
 local active=P.Detect();c.otherSpec=profile.index and active.index~=profile.index
 return c
end
local function converted(fn,index,total,change)
 if not numeric(total) then return nil end
 local before=call(fn,index,total);local after=call(fn,index,math.max(0,total+change))
 if numeric(before) and numeric(after) then return after-before end
end
function I.Evaluate(inspection,option,profile,context)
 local comparison=P.Comparison(inspection,option,"usable")
 local current=inspection.enchantID~=0 and inspection.current or nil
 local result={lines={},notes={},verdict="unknown",label=ns.L("Vergleich offen"),delta={},comparable=comparison.comparable}
 local c=context or I.Context(profile)
 local proposed=P.Stats(option).stats
 local old=comparison.comparable and current and P.Stats(current).stats or {}
 for key,value in pairs(proposed) do result.delta[key]=value-(old[key] or 0) end
 for key,value in pairs(old) do if proposed[key]==nil then result.delta[key]=-value end end
 if comparison.comparable then
  local score=P.Score(option,profile)-(current and P.Score(current,profile) or 0)
  result.verdict=score>.0001 and "better" or score<-.0001 and "worse" or "equal"
  result.label=ns.L("Rollenwertung: ")..(result.verdict=="better" and ns.L("Vorteil") or result.verdict=="worse" and ns.L("Nachteil") or ns.L("Ebenbürtig"))..ns.L(" für ")..profile.label
 else
  result.notes[#result.notes+1]=ns.L("Effekt allein; vorhandene Verzauberung nicht verrechnet.")
 end
 if c.otherSpec then result.notes[#result.notes+1]=ns.L("Umrechnung mit aktiven Talenten; gewählte Skillung zur Bewertung.") end
 return I.Derive(result,inspection,profile,c)
end
function I.Derive(result,inspection,profile,c)
 local d=result.delta
 local function add(value,label,kind)
  if numeric(value) and math.abs(value)>.00001 then
   result.lines[#result.lines+1]={value=value,text=I.Number(value).." "..label,kind=kind}
  end
 end
 local ranged=not c.forceMelee and c.class=="HUNTER" and profile.role=="physical"
 if (d.damage or 0)~=0 and inspection.context.slot~=18 then ranged=false end
 local ap=(d.attack or 0)+(ranged and (d.rangedAttack or 0) or (d.meleeAttack or 0));local apKnown=true
 local apFn=ranged and GetRangedAttackPowerForStat or GetAttackPowerForStat
 for _,entry in ipairs({{"strength",1},{"agility",2}}) do
  local change=d[entry[1]] or 0
  if change~=0 then
   local value=converted(apFn,entry[2],c.stats[entry[2]],change)
   if value then ap=ap+value else apKnown=false end
  end
 end
 local override=call(GetOverrideAPBySpellPower)
 if numeric(override) and override>0 then apKnown=false;result.notes[#result.notes+1]=ns.L("Angriffskraft wird durch Zaubermacht ersetzt.") end
 if apKnown then add(ap,ranged and ns.L("Distanz-Angriffskraft (Basis)") or ns.L("Angriffskraft (Basis)"))
 elseif (d.strength or 0)~=0 or (d.agility or 0)~=0 then result.notes[#result.notes+1]=ns.L("Attribut-Umrechnung im Client noch nicht verfügbar.") end
 local flat=d.damage or 0
 if flat~=0 and inspection.context.slot~=16 and inspection.context.slot~=18 then flat=0 end
 if apKnown and (ap~=0 or flat~=0) then
  local speed,haste,mult
  local weaponSlot=ranged and 18 or 16
  local weapon=GetInventoryItemLink("player",weaponSlot)
  local _,_,_,_,_,_,_,_,_,_,_,weaponClass,weaponType=ns.API.ItemInfo(weapon)
  local validWeapon=weapon and weaponClass==2 and (not ranged or weaponType==2 or weaponType==3 or weaponType==18)
  if ranged then
   local s,_,_,_,_,m=call(UnitRangedDamage,"player");speed,mult=s,m
   local base,ammo=call(GetRangedHaste);if numeric(base) then haste=base+(numeric(ammo) and ammo or 0) end
  else
   speed=call(UnitAttackSpeed,"player")
   local _,_,_,_,_,_,m=call(UnitDamage,"player");mult=m
   haste=call(GetMeleeHaste)
  end
  local form=call(GetShapeshiftForm)
  if c.class=="DRUID" and numeric(form) and form>0 then validWeapon=false end
  if not c.noWeaponEstimate and validWeapon and numeric(speed) and speed>0 and numeric(haste) and haste>-100 and numeric(mult) and mult>0 then
   local baseSpeed=speed*(1+haste/100)
   local hit=(ap/14*baseSpeed+flat)*mult
   local dps=hit/speed
   result.hit,result.dps=hit,dps
   if math.abs(hit)>.00001 then
    result.lines[#result.lines+1]={value=hit,kind="dps",text="≈ "..I.Number(hit)..ns.L(" Schaden / Treffer · ")..I.Number(dps)..ns.L(" Auto-DPS (")..(ranged and ns.L("Distanz") or ns.L("Waffenhand"))..")"}
    result.notes[#result.notes+1]=ns.L("DPS-Schätzung: AP/Waffenbonus, ohne Krit, Procs, Fähigkeiten und Zielrüstung.")
   end
  elseif ap~=0 then
   add(ap/14,ns.L("Basis-DPS aus Angriffskraft (vor Tempo)"),"dps")
   result.notes[#result.notes+1]=ns.L("Trefferschaden offen: Waffen-, Tempo- oder Gestaltdaten fehlen.")
  end
  if profile.role=="caster" or profile.role=="healer" then result.notes[#result.notes+1]=ns.L("Dieser Angriffskraftbonus wirkt im Nahkampf, nicht direkt auf Zauber.") end
 end
 if (d.stamina or 0)~=0 then
  local value=c.stats[3];local per=call(UnitHPPerStamina,"player")
  if numeric(value) and numeric(per) then
   local function health(s) return math.min(20,s)+math.max(0,s-20)*per end
   add(health(math.max(0,value+d.stamina))-health(value),ns.L("Gesundheit (Basis)"))
  end
 end
 if (d.intellect or 0)~=0 then
  local value=c.stats[4]
  if numeric(value) and c.class~="WARRIOR" and c.class~="ROGUE" then
   local function mana(s) return math.min(20,s)+math.max(0,s-20)*15 end
   add(mana(math.max(0,value+d.intellect))-mana(value),ns.L("Mana (Basis)"))
  end
  local crit=converted(GetSpellCritChanceFromStat,4,value,d.intellect)
  if crit then add(crit*100,ns.L("Prozentpunkte Zauberkrit"),"crit") end
 end
 local armor=(d.armor or 0)+(d.agility or 0)*2
 if (d.agility or 0)~=0 then
  add(armor,ns.L("Rüstung (Basis)"))
  local crit=converted(GetCritChanceFromStat,2,c.stats[2],d.agility)
  if crit then add(crit*100,ns.L("Prozentpunkte Waffen-Krit"),"crit") end
 end
 if armor~=0 and profile.role=="tank" then
  local _,effective=call(UnitArmor,"player")
  local armorFn=C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness
  local level=UnitLevel("player")
  if numeric(effective) and numeric(level) then
   local oldDR=call(armorFn,effective,level);local newDR=call(armorFn,math.max(0,effective+armor),level)
   if numeric(oldDR) and numeric(newDR) then add((newDR-oldDR)*100,ns.L("Prozentpunkte physische Minderung (gleichstufig)")) end
  end
 end
 if (d.spell or 0)~=0 or (d.healing or 0)~=0 then
  add(profile.role=="healer" and (d.healing or 0) or (d.spell or 0),profile.role=="healer" and ns.L("Heilbonus vor Zauberkoeffizient") or ns.L("Zauberbonus vor Zauberkoeffizient"))
  result.notes[#result.notes+1]=profile.role=="healer" and ns.L("Heilung pro Zauber hängt von dessen Koeffizienten ab.") or ns.L("Zauber-DPS hängt von Zauber, Rang und Wirkzeit ab.")
 end
 if (d.mp5 or 0)~=0 then add(d.mp5*12,ns.L("Mana pro Minute")) end
 if (d.spirit or 0)~=0 then result.notes[#result.notes+1]=ns.L("Willenskraft beeinflusst Regeneration; Wirkung hängt von Klasse und Talenten ab.") end
 if #result.lines==0 and #result.notes==0 then result.notes[1]=ns.L("Direkter Bonus oben; weitere Wirkung abhängig von Fähigkeiten und Talenten.") end
 return result
end
