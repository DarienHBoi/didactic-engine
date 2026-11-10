local _,ns=...
local B={forms=setmetatable({},{__mode='k'}),byRecipe={}};ns.RecipeHints=B
local P,A,I=ns.Advice,ns.API,ns.Impact
-- Forever/Camelot: reagents are anchored to Description.BOTTOMLEFT.
-- Post-hooking the native description update also covers asynchronous recipe loads.
for _,option in ipairs(ns.catalog) do
 if option.spellID then B.byRecipe[option.spellID]=option end
end
function B.Text(option,targetProfile)
 local data=P.Stats(option)
 if not next(data.stats) then return '|cffe3bd64GearWise|r · '..P.BonusText(option) end
 local groups,ordered={},{}
 for _,profile in ipairs(P.Profiles(targetProfile and targetProfile.class)) do
  if profile.index then
   local score=P.Score(option,profile)
   if score>0 then
    local group=groups[profile.index]
    if not group then
     group={name=profile.baseLabel or profile.label,score=score,index=profile.index,profile=profile}
     groups[profile.index]=group;ordered[#ordered+1]=group
    elseif score>group.score then group.score=score;group.profile=profile end
   end
  end
 end
 table.sort(ordered,function(a,b) if a.score~=b.score then return a.score>b.score end;return a.index<b.index end)
 local names={};for _,g in ipairs(ordered) do names[#names+1]=g.name end
 local direction=#names>0 and (ns.L('Geeignet: ')..table.concat(names,', ')) or ns.L('Kein Schwerpunkt deiner Skillungen')
 if P.Relevant(option,{role='profession'}) then direction=ns.L('Berufe') end
 local lines={'|cffe3bd64GearWise|r · '..direction,'|cff9fe3b0'..data.summary..'|r'}
 local _,ownClass=UnitClass('player')
 if targetProfile and targetProfile.class and targetProfile.class~=ownClass then return table.concat(lines,'\n') end
 -- One compact conversion; the original recipe retains the complete effect text.
 -- Use the active specialization's client values without assuming another talent build.
 local active=P.Detect();local context=I.Context(active);context.noWeaponEstimate=true
 local impact=I.Derive({delta=data.stats,lines={},notes={}}, {context={slot=option.slots[1]}},active,context)
 for _,line in ipairs(impact.lines) do
  if line.text:find(ns.L('Angriffskraft (Basis)'),1,true) or line.text:find(ns.L('Gesundheit (Basis)'),1,true) or line.text:find(ns.L('Mana (Basis)'),1,true) then
   lines[#lines+1]='|cffb3a68a'..line.text..'|r';break
  end
 end
 return table.concat(lines,'\n')
end
function B.Update(form)
 if not ns.enabled or not form.Description then return end
 local description=form.Description
 local info=form.GetRecipeInfo and form:GetRecipeInfo() or form.currentRecipeInfo
 local id=info and info.recipeID
 local state=B.forms[form]
 if not state then return end
 local original=description:GetText() or ''
 if original==state.rendered then original=state.original or '' end
 local option=B.byRecipe[id]
 local minimized=ProfessionsUtil and ProfessionsUtil.IsCraftingMinimized and ProfessionsUtil.IsCraftingMinimized()
 local skip=(ns.db and ns.db.settings.showRecipeHints==false) or not option or minimized or form.isRecraftOverride or form.isInspection or info and info.isRecraft or original=='' or not description:IsShown()
 local text=skip and original or (original..'\n\n'..B.Text(option))
 if text~=description:GetText() then
  description:SetText(text)
  description:SetHeight(600)
  description:SetHeight(math.max(1,description:GetStringHeight()+1))
 end
 state.original=original;state.rendered=text;state.recipeID=id
end
function B.Attach(form)
 if not form or B.forms[form] or not form.Description or type(form.UpdateRecipeDescription)~='function' or not hooksecurefunc then return end
 B.forms[form]={}
 hooksecurefunc(form,'UpdateRecipeDescription',B.Update)
 if type(form.ClearRecipeDescription)=='function' then
  hooksecurefunc(form,'ClearRecipeDescription',function(self)
   local state=B.forms[self];state.original=nil;state.rendered=nil;state.recipeID=nil
  end)
 end
 form:HookScript('OnShow',function(self) B.Update(self) end)
 if form:IsShown() then B.Update(form) end
end
function B.Refresh()
 if not ns.enabled then return end
 local frame=ProfessionsFrame
 B.Attach(frame and frame.CraftingPage and frame.CraftingPage.SchematicForm)
 for form in pairs(B.forms) do if form:IsShown() then B.Update(form) end end
end
