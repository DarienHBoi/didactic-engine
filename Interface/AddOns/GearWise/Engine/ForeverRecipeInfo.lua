local _,ns=...
local Info={};ns.RecipeInfo=Info
local A,R=ns.API,ns.Rules
local colors={title={1,.80,.38},text={.94,.89,.77},muted={.70,.65,.54},bad={1,.34,.30},good={.40,.87,.54}}
function Info.Lines(option,context)
 context=context or {professions=A.Professions(),level=UnitLevel("player")}
 local lines={}
 local function add(text,color) lines[#lines+1]={text=text,color=colors[color or "text"]} end
 local function heading(text) if #lines>0 then add(" ") end;add(text,"title") end
 local function professionName(key) return ns.professions[key] and ns.professions[key].name or key end
 heading(option.kind=="enchant" and ns.L("Wer kann verzaubern?") or ns.L("Wer kann es herstellen?"))
 if option.profession then
  local required=option.craftSkill
  add(professionName(option.profession)..(required and (ns.L(" · benötigt Skill ")..required) or ns.L(" · benötigter Skill nicht bestätigt")))
  add(ns.L("Der Handwerker muss das Rezept erlernt haben."),"muted")
  local own=R.ProfessionStatus(option,context,false)
  if own then
   local mandatory=option.selfProfession==option.profession
   local rank=own.current and tostring(own.current) or ns.L("nicht erlernt")
   add(ns.L("Dein Berufsskill: ")..rank..(own.current and required and (" / "..required) or "")..(not mandatory and ns.L(" · optional") or ""),
    mandatory and (own.state=="missing" or own.state=="low") and "bad" or "muted")
  end
 else add(ns.L("Kein Herstellungsrezept im Katalog hinterlegt."),"muted") end
 heading(ns.L("Wer kann es anwenden?"))
 local usage=R.ProfessionStatus(option,context,true)
 if usage then
  local unmet=usage.state=="missing" or usage.state=="low"
  add(ns.L("Nur selbst anwendbar"),unmet and "bad" or "good")
  add(usage.text,unmet and "bad" or "muted")
 elseif not option.rulesVerified then
  add(ns.L("Anwendung durch andere und eigene Berufspflicht in Forever noch nicht bestätigt."),"title")
 elseif option.kind=="enchant" and option.profession then
  add(ns.L("Ein anderer Handwerker mit diesem Rezept kann deine Ausrüstung verzaubern."))
  add(ns.L("Für dich ist der Beruf optional."),"muted")
 elseif option.itemID then
  add(ns.L("Du wendest den fertigen Verbesserungsgegenstand an."))
  add(ns.L("Kein eigener Herstellungsberuf erforderlich."),"muted")
 else add(ns.L("Anwender nicht bestätigt."),"title") end
 if option.itemID and option.tradable==true then add(ns.L("Fertigprodukt handelbar."),"muted") end
 if option.minLevel then add(ns.L("Benötigt Charakterstufe ")..option.minLevel,(context.level or 0)<option.minLevel and "bad" or "text") end
 if option.minItemLevel and option.minItemLevel>0 then add(ns.L("Benötigt Gegenstandsstufe ")..option.minItemLevel) end
 if option.reputation then
  local rep=option.reputation
  add(ns.L("Benötigter Ruf: ")..(rep.name or (ns.L("Fraktion ")..tostring(rep.id))).." · "..(_G['FACTION_STANDING_LABEL'..tostring(rep.rank)] or (ns.L("Rang ")..tostring(rep.rank))))
 end
 heading(option.kind=="reward" and ns.L("Bezugsquelle") or ns.L("Woher kommt das Rezept?"))
 if option.recipeItemID then
  local name=A.ItemInfo(option.recipeItemID)
  if not name then A.RequestItem(option.recipeItemID) end
  add(name or (ns.L("Rezeptgegenstand #")..option.recipeItemID))
 end
 if option.availability=="available" and option.acquisition and option.acquisition~="" then
  add(ns.L(option.acquisition))
 else
  add(ns.L("Bezugsquelle in Forever noch nicht bestätigt."),"title")
 end
 return lines
end
function Info.Show(owner,option)
 GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
 GameTooltip:SetText(A.Name(option))
 for _,line in ipairs(Info.Lines(option)) do GameTooltip:AddLine(line.text,line.color[1],line.color[2],line.color[3],true) end
 GameTooltip:Show()
end
