local _,ns=...
local F={};ns.Procs=F
local P,I,A=ns.Advice,ns.Impact,ns.API
function F.Data(option)
 local data=ns.procEffects[option.id]
 if data and data.effect==option.effect then return data end
end
function F.Summary(option)
 local data=F.Data(option)
 return data and ns.L(data.summary) or A.Description(option)
end
function F.Evaluate(option,slot,profile,context)
 if not P.Stats(option).conditional then return end
 local data=F.Data(option)
 local result={summary=F.Summary(option),lines={},notes={},delta={}}
 local _,ownClass=UnitClass('player')
 if profile.class and profile.class~=ownClass then return result end
 -- Keep active-effect values separate from permanent stats and role scores.
 local c=type(context)=='table' and context or I.Context(profile)
 local active={class=c.class,stats=c.stats,profile=profile,otherSpec=c.otherSpec,noWeaponEstimate=c.noWeaponEstimate,forceMelee=data and data.melee}
 if data then
  for key,value in pairs(data.stats or {}) do result.delta[key]=value end
  if data.spiritPercent and ns.IsPublicNumber(c.stats[5]) then
   result.delta.spirit=c.stats[5]*data.spiritPercent/100
   result.lines[#result.lines+1]={value=result.delta.spirit,text=I.Number(result.delta.spirit)..' '..ns.L('Willenskraft')}
  end
  if data.healthPercent and UnitHealthMax then
   local ok,health=pcall(UnitHealthMax,'player')
   if ok and ns.IsPublicNumber(health) then
    local value=health*data.healthPercent/100
    result.lines[#result.lines+1]={value=value,text=I.Number(value)..ns.L(' Heilung pro Auslösung (vor Überheilung)')}
   end
  end
  result.duration=data.duration
 end
 if next(result.delta) then I.Derive(result,{context={slot=slot}},profile,active) end
 if c.otherSpec then result.notes[#result.notes+1]=ns.L('Umrechnung mit aktiven Talenten; gewählte Skillung zur Bewertung.') end
 return result
end
function F.Text(result,includeNotes)
 if not result then return '' end
 local lines={result.summary}
 if #result.lines>0 then
  if result.duration then lines[#lines+1]=string.format(ns.L('Während der Wirkung (%d Sek.):'),result.duration) end
  for _,line in ipairs(result.lines) do lines[#lines+1]='|cff8cffa6'..line.text..'|r' end
 end
 if includeNotes then
  for _,note in ipairs(result.notes) do lines[#lines+1]=note end
  lines[#lines+1]=ns.L('Werte pro Auslösung bzw. während der Wirkung; keine durchschnittlichen DPS.')
 end
 return table.concat(lines,'\n')
end

function F.CardText(option)
 if not P.Stats(option).conditional then return P.BonusText(option) end
 local data=F.Data(option)
 return data and data.cardText and ns.L(data.cardText) or F.Summary(option)
end
