local _, ns = ...
local A = ns.API
local requestedItems, requestedSpells = {}, {}
function A.ItemInfo(id)
    local fn = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not fn or not id then return nil end
    return fn(id)
end
function A.RequestItem(id)
    if id and not requestedItems[id] and C_Item and C_Item.RequestLoadItemDataByID then
        requestedItems[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
end
function A.SpellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info then return info.name end
        if C_Spell.RequestLoadSpellData and not requestedSpells[id] then
            requestedSpells[id] = true
            C_Spell.RequestLoadSpellData(id)
        end
    elseif GetSpellInfo then return GetSpellInfo(id) end
end
function A.Icon(option)
    if option.itemID then
        local icon
        if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(option.itemID) end
        if not icon then icon = select(10, A.ItemInfo(option.itemID)) end
        if icon then return icon end
        A.RequestItem(option.itemID)
    end
    local spellID = option.spellID or option.useSpellID
    if spellID then
        if C_Spell and C_Spell.GetSpellTexture then
            local icon = C_Spell.GetSpellTexture(spellID)
            if icon then return icon end
        end
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellID)
            if info and info.iconID then return info.iconID end
        elseif GetSpellTexture then
            local icon = GetSpellTexture(spellID)
            if icon then return icon end
        end
        A.SpellName(spellID) -- Request missing spell data; the load event refreshes the panel.
    end
    return option.itemID and "Interface\\Icons\\INV_Misc_QuestionMark" or "Interface\\Icons\\Trade_Engraving"
end
function A.Name(option)
    if option.itemID then
        local name = A.ItemInfo(option.itemID)
        if name then return name..(option.variant and (" · "..ns.L(option.variant)) or "") end
        A.RequestItem(option.itemID)
    end
    return (A.SpellName(option.spellID) or option.name)..(option.variant and (" · "..ns.L(option.variant)) or "")
end
-- Consume modified clicks even while data is loading: never change the selection.
function A.ChatLink(option,count,mouseButton)
    if mouseButton and mouseButton~="LeftButton" then return false end
    local modified=IsModifiedClick and IsModifiedClick("CHATLINK") or not IsModifiedClick and IsShiftKeyDown and IsShiftKeyDown()
    if not modified then return false end
    local link
    if option.itemID then
        link=select(2,A.ItemInfo(option.itemRef or option.itemID))
        if not link then A.RequestItem(option.itemID) end
    else
        local id=option.spellID or option.useSpellID
        local getLink=C_Spell and C_Spell.GetSpellLink or GetSpellLink
        if id and getLink then link=getLink(id) end
        if not link then A.SpellName(id) end
    end
    if not link then ns.Print(ns.L("Link wird geladen. Bitte erneut mit Shift + Linksklick versuchen."));return true end
    local includeQuantity=not ns.db or ns.db.settings.chatLinkQuantity~=false
    local value=(count and includeQuantity and (tostring(count).." × ") or "")..link
    if not (ChatEdit_InsertLink and ChatEdit_InsertLink(value)) and ChatFrame_OpenChat then ChatFrame_OpenChat(value) end
    return true
end
function A.Count(id)
    local fn = C_Item and C_Item.GetItemCount or GetItemCount
    return math.max(0,tonumber(fn and fn(id, false)) or 0)
end
function A.Known(id)
    if not id then return false end
    if IsPlayerSpell then return IsPlayerSpell(id) end
    if IsSpellKnown then return IsSpellKnown(id) end
    return false
end
local function professionCall(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b,c,d,e,f,g=pcall(fn,...)
    if ok then return a,b,c,d,e,f,g end
end
function A.Professions()
    local result,byID,byName={},{},{}
    for key,profession in pairs(ns.professions) do
        byID[profession.id]=key;byName[profession.name]=key
        if profession.english then byName[profession.english]=key end
        if profession.german then byName[profession.german]=key end
        local localized=A.SpellName(profession.spell)
        if localized then byName[localized]=key end
    end
    local function record(key,rank)
        if key and result[key]==nil and type(rank)=="number" and rank>0 then result[key]=rank end
    end
    -- Forever's ID lookup also works when the profession header is collapsed.
    if C_SkillInfo then
        for key,profession in pairs(ns.professions) do
            local data=professionCall(C_SkillInfo.GetSkillLineInfoByID,profession.id)
            if data and not data.isHeader then record(key,data.rank) end
        end
        local count=professionCall(C_SkillInfo.GetNumSkillLines) or 0
        for i=1,count do
            local data=professionCall(C_SkillInfo.GetSkillLineInfo,i)
            if data and not data.isHeader then record(byID[data.skillID] or byName[data.name],data.rank) end
        end
    end
    -- Some builds expose the old functions as empty compatibility stubs.
    -- Read all available sources so an empty result never prevents a fallback.
    if GetProfessions and GetProfessionInfo then
        for _,index in pairs({professionCall(GetProfessions)}) do
            local name,_,rank,_,_,_,skillLine=professionCall(GetProfessionInfo,index)
            record(byID[skillLine] or byName[name],rank)
        end
    end
    local count=professionCall(GetNumSkillLines) or 0
    for i=1,count do
        local name,header,_,rank=professionCall(GetSkillLineInfo,i)
        if not header then record(byName[name],rank) end
    end
    return result
end
function A.Reputations()
    local result = {}
    local modern = C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex
    local count = modern and C_Reputation.GetNumFactions() or (GetNumFactions and GetNumFactions() or 0)
    for i=1,count do
        if modern then
            local data = C_Reputation.GetFactionDataByIndex(i)
            if data and data.factionID then result[data.factionID] = data.reaction end
        elseif GetFactionInfo then
            local _, _, rank, _, _, _, _, _, _, _, _, _, _, id = GetFactionInfo(i)
            if id then result[id] = rank end
        end
    end
    return result
end
function A.TooltipLines(method, ...)
    local fn = C_TooltipInfo and C_TooltipInfo[method]
    if not fn then return {} end
    local ok, data = pcall(fn, ...)
    if not ok or not data or not data.lines then return {} end
    local lines = {}
    for _, line in ipairs(data.lines) do
        if type(line.leftText) == "string" and line.leftText ~= "" then lines[#lines+1] = line.leftText end
    end
    return lines
end
function A.Description(option)
    if option.kind == "enchant" and C_Spell and C_Spell.GetSpellDescription and option.spellID then
        local text = C_Spell.GetSpellDescription(option.spellID)
        if text and text ~= "" then return text end
        if C_Spell.RequestLoadSpellData and not requestedSpells[option.spellID] then
            requestedSpells[option.spellID]=true;C_Spell.RequestLoadSpellData(option.spellID)
        end
    end
    return ns.L(option.effect) or ns.L("Wirkung und Einschränkungen: Maus über den Namen bewegen.")
end
function A.Context(slot)
    local link = GetInventoryItemLink("player", slot)
    local context = {slot=slot, item=link, level=UnitLevel("player"), professions=A.Professions(), known={}, owned={}, reputations=A.Reputations()}
    if link then
        local name, _, _, itemLevel, _, _, _, _, equipLoc, texture, _, classID, subclassID = A.ItemInfo(link)
        context.name, context.itemLevel, context.equipLoc = name, itemLevel, equipLoc
        context.classID, context.subclassID, context.texture = classID, subclassID, texture
        context.loaded = name ~= nil and equipLoc ~= nil and classID ~= nil
        if not context.loaded then A.RequestItem(tonumber(link:match("item:(%d+)"))) end
    end
    for _, option in ipairs(ns.bySlot[slot] or {}) do
        if option.spellID then context.known[option.spellID] = A.Known(option.spellID) end
        if option.itemID then context.owned[option.itemID] = A.Count(option.itemID) > 0 end
    end
    return context
end
function A.CurrentEnchant(slot,link)
    local id=ns.Rules.ParseEnchant(link)
    if not id or id==0 then return end
    if ns.byEnchant[id] then return ns.byEnchant[id] end
    if not C_TooltipInfo or not ns.Advice.ObservedEnchant then return end
    local data
    if slot and C_TooltipInfo.GetInventoryItem and GetInventoryItemLink('player',slot)==link then
        local ok,result=pcall(C_TooltipInfo.GetInventoryItem,'player',slot)
        if ok then data=result end
    end
    if not data and C_TooltipInfo.GetHyperlink then
        local ok,result=pcall(C_TooltipInfo.GetHyperlink,link)
        if ok then data=result end
    end
    local kind=Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent or 15
    local texts={}
    for _,line in ipairs(data and data.lines or {}) do
        if line.type==kind and type(line.leftText)=='string' and line.leftText~='' then texts[#texts+1]=line.leftText end
    end
    if #texts==0 then return end
    return ns.Advice.ObservedEnchant(table.concat(texts,'; '))
end
function A.Inspect(slot)
    local context = A.Context(slot)
    local enchantID = ns.Rules.ParseEnchant(context.item)
    local id = context.item and context.item:match("item:(%d+)")
    local ignored = ns.char.ignored and ns.char.ignored[slot] == id
    local state, status = ns.Rules.Status(context, ns.bySlot[slot] or {}, enchantID, ignored)
    return {context=context, enchantID=enchantID, state=state, status=status, current=A.CurrentEnchant(slot,context.item), ignored=ignored}
end
function A.ShowTooltip(owner, option)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if option.itemID then GameTooltip:SetHyperlink(option.itemRef or ("item:"..option.itemID))
    elseif option.spellID or option.useSpellID then GameTooltip:SetHyperlink("spell:"..(option.spellID or option.useSpellID))
    elseif type(option.name)=="string" and option.name~="" then GameTooltip:SetText(option.name)
    else GameTooltip:Hide();return end
    GameTooltip:Show()
end


-- Recipe items give the client tooltip without the crafting spell's reagent block.
-- Trainer-only recipes have no item: show their client description directly.
function A.ShowRecipeTooltip(owner,option)
    if option.recipeItemID then
        A.RequestItem(option.recipeItemID)
        A.ShowTooltip(owner,{itemID=option.recipeItemID})
        return
    elseif option.itemID then
        A.ShowTooltip(owner,option)
        return
    end
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    GameTooltip:SetText(A.Name(option))
    if option.profession then
        local profession=ns.professions[option.profession]
        local name=profession and profession.name or option.profession
        GameTooltip:AddLine(name..(option.craftSkill and (" ("..option.craftSkill..")") or ""),1,1,1,true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(A.Description(option),.12,1,0,true)
    GameTooltip:Show()
end
