local _, root = ...
root.PG = root.PG or {}
local ns = root.PG

-- recipe data comes from What's Training? (MIT), Forever ("Camelot") edition
ns.SOURCE_NAMES = {
    trainer = "Trainer", vendor = "Vendor", drop = "Drop", quest = "Quest",
    crafted = "Crafted", world_object = "World object", discovery = "Discovery",
}

local RANK_CAPS = { Apprentice = 75, Journeyman = 150, Expert = 225, Artisan = 300 }
-- a recipe learned this many points below your skill has very likely gone gray
local PROBABLY_GRAY_SPAN = 40

local requestedSpells = {}
function ns.SpellRequested(spellID)
    return requestedSpells[spellID] == true
end

local function spellName(spellID)
    local name
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        name = info and info.name
    elseif GetSpellInfo then
        name = GetSpellInfo(spellID)
    end
    if not name and not requestedSpells[spellID] then
        requestedSpells[spellID] = true
        if C_Spell and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(spellID) end
    end
    return name
end

local function spellIcon(spellID)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellID) end
    return GetSpellTexture and GetSpellTexture(spellID)
end

local function isSpellKnown(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID, bank)
        if ok and known then return true end
    end
    return IsSpellKnown and IsSpellKnown(spellID) or false
end

-- keeps quest/vendor sources only if some location serves the player's faction
local function usableSources(recipe, faction)
    local sources = recipe.source or {}
    local usable = {}
    for _, source in ipairs(sources) do
        local locations = (source == "quest" and recipe.quests) or (source == "vendor" and recipe.vendors) or nil
        local keep = not locations or #locations == 0
        for _, location in ipairs(locations or {}) do
            if not location.faction or location.faction == faction then keep = true end
        end
        if keep then table.insert(usable, source) end
    end
    return usable
end

function ns.AreaName(area)
    if not area or area <= 0 then return end
    return C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area) or nil
end

-- zone names for a list of vendor or quest locations on the player's side
function ns.LocationZones(locations, faction, limit)
    local seen, zones = {}, {}
    for _, location in ipairs(locations or {}) do
        if not location.faction or location.faction == faction then
            local areas = location.areas or { location.area }
            for _, area in ipairs(areas) do
                local name = ns.AreaName(area)
                if name and not seen[name] then
                    seen[name] = true
                    table.insert(zones, name)
                end
            end
        end
    end
    local extra = 0
    if limit and #zones > limit then
        extra = #zones - limit
        for i = #zones, limit + 1, -1 do zones[i] = nil end
    end
    return zones, extra
end

-- best-effort NPC name from the client cache
local npcNames = {}
function ns.NpcName(npcID)
    if npcNames[npcID] then return npcNames[npcID] end
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, string.format("unit:Creature-0-0-0-0-%d-0000000000", npcID))
    local line = ok and data and data.lines and data.lines[1]
    local name = line and line.leftText
    if name and name ~= "" then npcNames[npcID] = name end
    return npcNames[npcID]
end

function ns.ReputationRequirement(recipe)
    local rep = recipe.reputation
    if not rep then return end
    local parts, met = {}, false
    for i = 1, #rep, 3 do
        local name, standing
        if C_Reputation and C_Reputation.GetFactionDataByID then
            local data = C_Reputation.GetFactionDataByID(rep[i])
            if data then name, standing = data.name, data.reaction end
        elseif GetFactionInfoByID then
            local _
            name, _, standing = GetFactionInfoByID(rep[i])
        end
        met = met or (standing and standing >= rep[i + 1]) or false
        local label = _G["FACTION_STANDING_LABEL" .. rep[i + 1]] or ("rank " .. rep[i + 1])
        table.insert(parts, string.format("%s with %s", label, name or rep[i + 2] or ("faction " .. rep[i])))
    end
    return table.concat(parts, " or "), met
end

local function sourceSummary(recipe, sources, faction)
    local parts = {}
    for _, source in ipairs(sources) do
        if source == "trainer" then
            table.insert(parts, "Trainer" .. (recipe.cost and recipe.cost > 0 and (" " .. ns.Money(recipe.cost)) or ""))
        elseif source == "vendor" then
            local zones, extra = ns.LocationZones(recipe.vendors, faction, 2)
            local where = #zones > 0 and (" (" .. table.concat(zones, ", ") .. (extra > 0 and (" +" .. extra) or "") .. ")") or ""
            table.insert(parts, "Vendor" .. where)
        elseif source == "quest" then
            local zones = ns.LocationZones(recipe.quests, faction, 1)
            table.insert(parts, "Quest" .. (#zones > 0 and (" (" .. zones[1] .. ")") or ""))
        elseif source == "drop" then
            table.insert(parts, "World drop")
        else
            table.insert(parts, ns.SOURCE_NAMES[source] or source)
        end
    end
    return table.concat(parts, " · ")
end

-- recipes you don't know yet that help from your current skill, grouped for display
function ns.RecipesToGet(skillLine, rank, maxRank)
    local data = ns.Recipes[skillLine]
    if not data then return {} end
    local faction = UnitFactionGroup("player")
    local lookahead = ns.settings.farLookahead and 75 or 25
    local cached = ZugDAQ_ProfCharDB.professions[skillLine]
    local groups = { rank = {}, now = {}, soon = {} }
    ns.ResetPriceCache()
    for _, recipe in ipairs(data) do
        local cachedRecipe = cached and cached.recipes[recipe.spell]
        local known = (cachedRecipe and cachedRecipe.learned) or isSpellKnown(recipe.spell)
        if recipe.rank then
            local cap = RANK_CAPS[recipe.rank]
            known = known or (cap and maxRank >= cap)
        end
        local sources = usableSources(recipe, faction)
        local factionOk = not recipe.faction or recipe.faction == faction
        if not known and factionOk and #sources > 0 and recipe.skill then
            local group
            local delta = recipe.skill - rank
            if recipe.rank then
                if delta <= lookahead then group = "rank" end
            elseif delta <= 0 then
                local t = ZugDAQ_ProfDB.thresholds[recipe.spell]
                local gray = t and t.gray
                if (gray and rank < gray) or (not gray and -delta < PROBABLY_GRAY_SPAN) then group = "now" end
            elseif delta <= lookahead then
                group = "soon"
            end
            if group then
                local row = {
                    spell = recipe.spell, recipe = recipe, sources = sources,
                    name = spellName(recipe.spell) or ("Recipe " .. recipe.spell),
                    icon = (recipe.creates and C_Item.GetItemIconByID(recipe.creates)) or spellIcon(recipe.spell)
                        or "Interface\\Icons\\INV_Misc_QuestionMark",
                    skill = recipe.skill, delta = delta,
                    sourceText = sourceSummary(recipe, sources, faction),
                }
                if recipe.rank then row.name = recipe.rank .. " " .. (cached and cached.name or row.name) end
                local notes = {}
                if recipe.level and recipe.level > UnitLevel("player") then
                    table.insert(notes, "|cffff6666needs level " .. recipe.level .. "|r")
                end
                local repText, repMet = ns.ReputationRequirement(recipe)
                if repText then
                    table.insert(notes, (repMet and "|cff80ff80" or "|cffff6666") .. repText .. "|r")
                end
                if recipe.merchantFavor then
                    table.insert(notes, "|cffffd100merchant favor " .. recipe.merchantFavor .. "|r")
                end
                if recipe.bound then table.insert(notes, "|cffaaaaaarecipe is bind-on-pickup|r") end
                row.notes = notes
                -- the profession window also lists unlearned recipes, so their reagents can be priced
                if cachedRecipe and #cachedRecipe.slots > 0 then
                    row.perCraft = ns.CostRecipe(cachedRecipe, 1, nil)
                end
                table.insert(groups[group], row)
            end
        end
    end
    table.sort(groups.rank, function(a, b) return a.skill < b.skill end)
    -- closest to orange first: the highest requirement you already meet
    table.sort(groups.now, function(a, b)
        if a.skill ~= b.skill then return a.skill > b.skill end
        return a.name < b.name
    end)
    table.sort(groups.soon, function(a, b)
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.name < b.name
    end)
    return groups
end
