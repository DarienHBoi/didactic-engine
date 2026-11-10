local _, ns = ...
local R = ns.Rules
function R.ParseEnchant(link)
    if type(link) ~= "string" then return nil end
    local value = link:match("item:%d+:(%d*):")
    if value == nil then return nil end
    return tonumber(value) or 0
end
local function has(list, value)
    for _, candidate in ipairs(list or {}) do if candidate == value then return true end end
    return false
end
function R.ProfessionStatus(option,context,usage)
    local key,required=option.profession,option.craftSkill
    if usage then key,required=option.selfProfession,option.useSkill end
    if not key then return end
    local profession=ns.professions[key]
    local name=profession and profession.name or key
    local current=(context.professions or {})[key]
    local result={key=key,current=current,required=required,state="unknown",usage=usage}
    local prefix=usage and ns.L("Nur selbst: ") or ns.L("Optional: ")
    if current==nil then
        result.state="missing"
        result.text=prefix..name..(required and (" "..required) or "")..(usage and ns.L(" · Beruf nicht erlernt") or ns.L(" · anderer Handwerker"))
    elseif required then
        result.state=current<required and "low" or "ready"
        result.text=prefix..name.." "..current.." / "..required
    else
        result.text=prefix..name..ns.L(" · dein Skill ")..current
    end
    return result
end
function R.Evaluate(option, context)
    if not context.item then return "blocked", ns.L("Kein Gegenstand angelegt") end
    if not has(option.slots, context.slot) then return "blocked", ns.L("Anderer Ausrüstungsplatz") end
    if not context.loaded then return "unknown", ns.L("Gegenstandsdaten werden geladen") end
    if option.equipLocs and not has(option.equipLocs, context.equipLoc) then
        return "blocked", ns.L("Für diesen Gegenstandstyp nicht geeignet")
    end
    if option.weaponTypes and (context.classID ~= 2 or not has(option.weaponTypes, context.subclassID)) then
        return "blocked", ns.L("Für diesen Waffentyp nicht geeignet")
    end
    if option.db2ItemClass and option.db2ItemClass>=0 and context.classID~=option.db2ItemClass then
        return "blocked", ns.L("Für diesen Gegenstandstyp nicht geeignet")
    end
    if option.db2Subclasses and not has(option.db2Subclasses,context.subclassID) then
        return "blocked", ns.L("Für diesen Gegenstandstyp nicht geeignet")
    end
    local profession=R.ProfessionStatus(option,context,true)
    if profession and (profession.state=="missing" or profession.state=="low") then
        return "blocked",profession.text,"profession"
    end
    if option.minLevel and (context.level or 0) < option.minLevel then
        return "blocked", ns.L("Benötigt Charakterstufe ")..option.minLevel
    end
    if option.minItemLevel then
        if not context.itemLevel then return "unknown", ns.L("Gegenstandsstufe unbekannt") end
        if context.itemLevel < option.minItemLevel then return "blocked", ns.L("Benötigt Gegenstandsstufe ")..option.minItemLevel end
    end
    if option.reputation then
        local rank = (context.reputations or {})[option.reputation.id]
        if not rank then return "unknown", ns.L("Rufvoraussetzung noch nicht geprüft") end
        if rank < option.reputation.rank then return "blocked", ns.L("Rufvoraussetzung nicht erfüllt") end
    end
    if not option.rulesVerified then return "unknown", ns.L("Anwendungsregeln in Forever noch nicht vollständig geprüft") end
    if option.availability ~= "available" and not (context.known or {})[option.spellID]
        and not (option.itemID and (context.owned or {})[option.itemID]) then
        return "unknown", ns.L("Rezept im Beta-Katalog; Bezugsquelle noch nicht bestätigt")
    end
    return "usable", ns.L("Voraussetzungen erfüllt")
end
function R.Status(context, options, enchantID, ignored)
    if not context.item then return "empty", ns.L("Kein Gegenstand angelegt") end
    if not context.loaded or enchantID == nil then return "unknown", ns.L("Gegenstandsdaten werden geladen") end
    -- Presence is not a claim that this is the best enchant for the character.
    if enchantID > 0 then return "enhanced", ns.L("Dauerhafte Verbesserung vorhanden") end
    if ignored then return "ignored", ns.L("Hinweis für diesen Gegenstand ausgeblendet") end
    for _, option in ipairs(options) do
        local state = R.Evaluate(option, context)
        if state == "usable" then return "missing", ns.L("Nutzbare Verbesserung fehlt") end
    end
    return "neutral", ns.L("Möglichkeiten und Voraussetzungen ansehen")
end
function R.Compare(current, candidate)
    -- Only compare the exact same stat family with vetted values.
    if not current or not candidate or not current.family or current.family ~= candidate.family
        or not current.value or not candidate.value then return nil end
    return candidate.value - current.value
end

