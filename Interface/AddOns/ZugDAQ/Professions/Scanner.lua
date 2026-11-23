local _, root = ...
root.PG = root.PG or {}
local ns = root.PG

local D = Enum and Enum.TradeskillRelativeDifficulty or {}
local OPTIMAL = D.Optimal or 0
local MEDIUM = D.Medium or 1
local EASY = D.Easy or 2
local TRIVIAL = D.Trivial or 3
ns.DIFF = { OPTIMAL = OPTIMAL, MEDIUM = MEDIUM, EASY = EASY, TRIVIAL = TRIVIAL }

ns.DIFF_COLORS = {
    [OPTIMAL] = { 1, 0.5, 0.25 },
    [MEDIUM] = { 1, 1, 0 },
    [EASY] = { 0.25, 0.75, 0.25 },
    [TRIVIAL] = { 0.55, 0.55, 0.55 },
}
ns.DIFF_NAMES = { [OPTIMAL] = "orange", [MEDIUM] = "yellow", [EASY] = "green", [TRIVIAL] = "gray" }

---------------------------------------------------------------------------
-- player's professions
---------------------------------------------------------------------------

-- skill line id -> { name, rank, maxRank } for every profession the character has
function ns.PlayerProfessions()
    local result = {}
    if GetProfessions and GetProfessionInfo then
        for _, index in pairs({ GetProfessions() }) do
            if index then
                local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
                if skillLine and name then result[skillLine] = { name = name, rank = rank, maxRank = maxRank } end
            end
        end
    end
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        for skillLine in pairs(ns.Recipes) do
            if not result[skillLine] then
                local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, skillLine)
                if ok and info and info.rank and info.rank > 0 then
                    result[skillLine] = { name = info.name, rank = info.rank, maxRank = info.maxRank }
                end
            end
        end
    end
    return result
end

---------------------------------------------------------------------------
-- reading the open profession window
---------------------------------------------------------------------------

local function readSlots(schematic)
    local slots = {}
    if not (schematic and schematic.reagentSlotSchematics) then return slots end
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        local required = slot.required
        if required == nil then required = slot.reagentType == basic end
        if required and (slot.quantityRequired or 0) > 0 then
            local items = {}
            for _, reagent in ipairs(slot.reagents or {}) do
                local itemID = reagent.itemID or (reagent.reagent and reagent.reagent.itemID)
                if itemID then table.insert(items, itemID) end
            end
            if #items > 0 then table.insert(slots, { items = items, qty = slot.quantityRequired }) end
        end
    end
    return slots
end

-- records the lowest skill seen for each color, so chances sharpen the more you play
function ns.RecordDifficulty(recipeID, diff, rank)
    if not rank or rank <= 0 or diff == nil then return end
    local all = ZugDAQ_ProfDB.thresholds
    local t = all[recipeID] or {}
    if diff == OPTIMAL then
        t.o = math.max(t.o or 0, rank)
    else
        local key = diff == MEDIUM and "y" or diff == EASY and "g" or diff == TRIVIAL and "gray"
        if key and (not t[key] or rank < t[key]) then t[key] = rank end
    end
    all[recipeID] = t
end

local function resolveSkillLine(base, child)
    local candidates = {
        base and base.professionID,
        child and child.parentProfessionID,
        child and child.professionID,
    }
    for _, id in ipairs(candidates) do
        if id and id > 0 and ns.Recipes[id] then return id end
    end
    for _, id in ipairs(candidates) do
        if id and id > 0 then return id end
    end
end

local function viewingOwnProfession()
    local T = C_TradeSkillUI
    if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end
    if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return false end
    if T.IsNPCCrafting and T.IsNPCCrafting() then return false end
    return true
end

function ns.ScanOpenProfession()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
    if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return end
    if not viewingOwnProfession() then return end
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
    local skillLine = resolveSkillLine(base, child)
    if not skillLine then return end

    local rank, maxRank
    if child and (child.skillLevel or 0) > 0 then
        rank, maxRank = child.skillLevel, child.maxSkillLevel
    elseif base and (base.skillLevel or 0) > 0 then
        rank, maxRank = base.skillLevel, base.maxSkillLevel
    end
    local known = ns.PlayerProfessions()[skillLine]
    if known then
        rank = rank or known.rank
        maxRank = maxRank or known.maxRank
    end

    local entry = {
        name = (known and known.name) or (base and base.professionName) or (child and child.professionName) or "?",
        rank = rank or 0, maxRank = maxRank or 0, time = time(), recipes = {},
    }
    for _, recipeID in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(recipeID)
        if info and not info.isRecraft and not info.isDummyRecipe and not info.isGatheringRecipe then
            local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false)
            if not ok then schematic = nil end
            entry.recipes[recipeID] = {
                name = info.name, icon = info.icon, learned = info.learned and true or false,
                diff = info.learned and info.relativeDifficulty or nil,
                ups = info.numSkillUps or 1,
                output = schematic and schematic.outputItemID,
                yield = schematic and ((schematic.quantityMin or 1) + (schematic.quantityMax or 1)) / 2 or 1,
                slots = readSlots(schematic),
            }
            if info.learned then ns.RecordDifficulty(recipeID, info.relativeDifficulty, entry.rank) end
        end
    end
    ZugDAQ_ProfCharDB.professions[skillLine] = entry
    ns.currentSkillLine = skillLine
    return skillLine
end

---------------------------------------------------------------------------
-- skill-up chance
---------------------------------------------------------------------------

-- classic rule: 100% at orange, falling linearly from yellow to gray.
-- Uses thresholds this addon has watched happen; otherwise a typical value for the color.
function ns.SkillUpChance(recipeID, diff, rank)
    if diff == OPTIMAL then return 1, true end
    if diff == nil or diff == TRIVIAL then return 0, true end
    local t = ZugDAQ_ProfDB.thresholds[recipeID]
    local y, g, gray = t and t.y, t and t.g, t and t.gray
    if not gray and y and g and g > y then gray = g + (g - y) end
    local lo, hi = 0.5, 1
    if diff == EASY then lo, hi = 0.02, 0.5 end
    if y and gray and gray > y then
        local chance = (gray - rank) / (gray - y)
        return math.max(lo, math.min(hi, chance)), true
    end
    return diff == MEDIUM and 0.75 or 0.25, false
end

---------------------------------------------------------------------------
-- cost evaluation
---------------------------------------------------------------------------

-- cheapest way to fill one reagent slot for `crafts` crafts
local function evalSlot(slot, crafts, crafted)
    local best
    for _, itemID in ipairs(slot.items) do
        local need = slot.qty * crafts
        local base, source = ns.BasePrice(itemID)
        local weight = ns.QualityWeight(itemID, source)
        local unit, raw = base * weight, base
        local alt = crafted and crafted[itemID]
        if alt and alt < unit then unit, raw, source, weight = alt, alt, "crafted", 1 end
        local have = ns.AccountCount(itemID) -- mats on bank alts count as owned (mail them over)
        local used = math.min(have, need)
        local cost = used * unit * ns.OwnedFactor(itemID) + (need - used) * unit
        if not best or cost < best.cost then
            best = {
                itemID = itemID, need = need, have = have, cost = cost,
                spend = (need - used) * raw, unit = unit, raw = raw, source = source, weight = weight,
                qty = slot.qty,
            }
        end
    end
    return best
end

local function craftableNow(slots)
    local count
    for _, slot in ipairs(slots) do
        local have = 0
        for _, itemID in ipairs(slot.items) do have = have + ns.ItemCount(itemID, false) end
        local n = math.floor(have / slot.qty)
        count = count and math.min(count, n) or n
    end
    return count or 0
end

-- per-unit cost of reagents this profession can make itself (one level deep)
local function craftedPrices(entry)
    local result = {}
    for _, recipe in pairs(entry.recipes) do
        if recipe.learned and recipe.output and #recipe.slots > 0 then
            local total = 0
            for _, slot in ipairs(recipe.slots) do total = total + evalSlot(slot, 1, nil).cost end
            local unit = total / math.max(recipe.yield or 1, 1)
            if not result[recipe.output] or unit < result[recipe.output] then result[recipe.output] = unit end
        end
    end
    return result
end

-- cost of `crafts` crafts of a cached recipe, reagent by reagent
function ns.CostRecipe(recipe, crafts, crafted)
    local total, spend, reagents, missing, guessed = 0, 0, {}, {}, false
    for _, slot in ipairs(recipe.slots) do
        local r = evalSlot(slot, crafts, crafted)
        total, spend = total + r.cost, spend + r.spend
        if r.source == "guess" then guessed = true end
        table.insert(reagents, r)
        if r.need > r.have then table.insert(missing, { itemID = r.itemID, count = r.need - r.have }) end
    end
    return total, spend, reagents, missing, guessed
end

-- every learned recipe, ranked by what it costs to earn one skill point
function ns.Evaluate(skillLine)
    local entry = ZugDAQ_ProfCharDB.professions[skillLine]
    if not entry then return {} end
    ns.ResetPriceCache()
    local s = ns.settings
    local rank = entry.rank
    local live = ns.PlayerProfessions()[skillLine]
    if live and live.rank and live.rank > rank then rank = live.rank end
    local crafted = craftedPrices(entry)
    local rows = {}
    for recipeID, recipe in pairs(entry.recipes) do
        if recipe.learned and recipe.diff ~= nil then
            local chance, measured = ns.SkillUpChance(recipeID, recipe.diff, rank)
            local ups = recipe.diff == OPTIMAL and math.max(recipe.ups or 1, 1) or 1
            local expected = chance * ups
            local craftable = craftableNow(recipe.slots)
            local visible = not (s.hideTrivial and expected <= 0) and not (s.onlyCraftable and craftable == 0)
            if visible then
                -- price the crafts one point takes, so owned reagents are spread over all of them
                local crafts = expected > 0 and math.max(1, math.ceil(1 / expected)) or 1
                local total, spend, reagents, missing, guessed = ns.CostRecipe(recipe, crafts, crafted)
                local perCraft = total / crafts
                table.insert(rows, {
                    id = recipeID, name = recipe.name, icon = recipe.icon, diff = recipe.diff,
                    chance = chance, measured = measured, expected = expected,
                    craftsPerPoint = expected > 0 and 1 / expected or math.huge,
                    perCraft = perCraft, spendPerCraft = spend / crafts,
                    costPerPoint = expected > 0 and perCraft / expected or math.huge,
                    spendPerPoint = expected > 0 and (spend / crafts) / expected or math.huge,
                    craftable = craftable, reagents = reagents, missing = missing, guessed = guessed,
                    crafts = crafts, recipe = recipe,
                })
            end
        end
    end
    local sorters = {
        costPerPoint = function(a, b)
            if a.costPerPoint ~= b.costPerPoint then return a.costPerPoint < b.costPerPoint end
            return a.chance > b.chance
        end,
        chance = function(a, b)
            if a.expected ~= b.expected then return a.expected > b.expected end
            return a.costPerPoint < b.costPerPoint
        end,
        craftable = function(a, b)
            if (a.craftable > 0) ~= (b.craftable > 0) then return a.craftable > 0 end
            return a.costPerPoint < b.costPerPoint
        end,
        name = function(a, b) return (a.name or "") < (b.name or "") end,
    }
    local sorter = sorters[s.sortKey] or sorters.costPerPoint
    table.sort(rows, function(a, b)
        if (a.expected > 0) ~= (b.expected > 0) then return a.expected > 0 end
        if sorter(a, b) then return true end
        if sorter(b, a) then return false end
        return a.id < b.id
    end)
    return rows, crafted, rank, entry
end
