local _, ns = ...

-- Crafting profit: for the recipes this character knows, is a material worth more sold as it is,
-- or turned into something (and maybe that into something else)?
--
-- Recipes are read from the profession window whenever it's open (and imported once from
-- ZugDAQ Professions's scan if that addon has one). Prices:
--   selling   ns.Value: the better of the AH price after the cut and the vendor price
--   using     a material you own costs what you'd have got selling it; one you don't own costs
--             what you'd pay for it; vendor goods (salt, thread, dye) always cost the vendor price

local MAX_DEPTH = 3

-- ---------------------------------------------------------------- recipe store

local function charRecipes()
    local c = ns.db.chars[ns.charKey]
    c.recipes = c.recipes or {}
    return c.recipes
end
ns.CharRecipes = charRecipes

-- every character's recipes (the account counts as one player), each tagged with who knows it: .crafter. Views of the
-- saved recipes (nothing saved is changed); one per recipe, the logged-in character's first when two know it.
local function accountRecipeList()
    local list, seen = {}, {}
    local me = ns.charKey
    local function add(key, c)
        local who = key:match("^[^-]+") or key
        for id, r in pairs(c.recipes or {}) do
            local k = tostring(r.output) .. ":" .. tostring(r.name or id)
            if r.output and not seen[k] then
                seen[k] = true
                list[#list + 1] = setmetatable({ crafter = who, mine = key == me }, { __index = r })
            end
        end
    end
    if me and ns.db.chars[me] then add(me, ns.db.chars[me]) end
    for key, c in pairs(ns.db.chars) do
        if key ~= me then add(key, c) end
    end
    return list
end
ns.AccountRecipeList = accountRecipeList

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
                if itemID then items[#items + 1] = itemID end
            end
            if #items > 0 then slots[#slots + 1] = { items = items, qty = slot.quantityRequired } end
        end
    end
    return slots
end

local function scanOpenProfession()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetRecipeSchematic) then return end
    if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return end
    if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
        or (T.IsNPCCrafting and T.IsNPCCrafting()) then return end
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
    local prof = (base and base.professionName) or (child and child.professionName)
    if not prof or prof == "" then return end
    local profID = (base and base.professionID) or (child and (child.parentProfessionID or child.professionID))

    -- learned recipes drive ZugDAQ's own crafting views; unlearned ones (with their reagents) are kept
    -- apart for ZugDAQ's levelling planner
    local found, notLearned = {}, {}
    for _, recipeID in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(recipeID)
        if info and not info.isRecraft and not info.isDummyRecipe and not info.isGatheringRecipe then
            local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false)
            if ok and schematic and schematic.outputItemID then
                local slots = readSlots(schematic)
                if #slots > 0 then
                    local entry = {
                        name = info.name, prof = prof, profID = profID, output = schematic.outputItemID,
                        yield = ((schematic.quantityMin or 1) + (schematic.quantityMax or 1)) / 2,
                        slots = slots,
                    }
                    if info.learned then
                        -- skill-up colour right now (0 orange, 1 yellow, 2 green, 3 grey) and points per craft
                        entry.diff, entry.ups = info.relativeDifficulty, info.numSkillUps
                        found[recipeID] = entry
                    else
                        notLearned[recipeID] = entry
                    end
                end
            end
        end
    end
    if not next(found) then return end
    local c = ns.db.chars[ns.charKey]
    c.profSkill = c.profSkill or {}
    local skill = base and base.skillLevel
    if skill then
        c.profSkill[prof] = { level = skill, max = base.maxSkillLevel, at = time() }
    end
    local recipes = charRecipes()
    for id, r in pairs(recipes) do
        if r.prof == prof then recipes[id] = nil end
    end
    for id, r in pairs(found) do recipes[id] = r end

    c.unlearned = c.unlearned or {}
    for id, r in pairs(c.unlearned) do
        if r.prof == prof then c.unlearned[id] = nil end
    end
    for id, r in pairs(notLearned) do c.unlearned[id] = r end

    -- each recipe's colour at this skill: over time this pins down where it turns yellow, green and grey
    if skill then
        c.recipeObs = c.recipeObs or {}
        for id, r in pairs(found) do
            if r.diff then
                local obs = c.recipeObs[id] or {}
                obs[skill] = r.diff
                c.recipeObs[id] = obs
            end
        end
    end
    ns.RequestRefresh()
end

local function queueScan() ns.Debounce("tradeskill", 0.6, scanOpenProfession) end
ns.On("TRADE_SKILL_SHOW", queueScan)
ns.On("TRADE_SKILL_LIST_UPDATE", queueScan)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", queueScan)
ns.On("NEW_RECIPE_LEARNED", queueScan)

-- one-time import from ZugDAQ Professions's per-character scan, for professions not scanned here yet
ns.OnLogin(function()
    local pg = ZugDAQ_ProfCharDB and ZugDAQ_ProfCharDB.professions
    if type(pg) ~= "table" then return end
    local recipes = charRecipes()
    local have = {}
    for _, r in pairs(recipes) do have[r.prof] = true end
    for skillLine, entry in pairs(pg) do
        if type(entry) == "table" and entry.name and not have[entry.name] and type(entry.recipes) == "table" then
            for id, r in pairs(entry.recipes) do
                if r.learned and r.output and type(r.slots) == "table" and #r.slots > 0 then
                    recipes[id] = { name = r.name, prof = entry.name, profID = tonumber(skillLine), output = r.output,
                                    yield = r.yield or 1, slots = r.slots }
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------- vendor buy prices

-- who sells what, and where: the vendor's name, NPC id, zone and map position (for ZugDAQ's shopping lists)
local function merchantRecord()
    local guid = UnitGUID and UnitGUID("npc")
    -- parentheses keep only the NPC id: select(6, ...) also returns the spawn id, which tonumber would take as a base
    local npcID = guid and tonumber((select(6, strsplit("-", guid))))
    if not npcID then return end
    ns.db.merchants = ns.db.merchants or {}
    local m = ns.db.merchants[npcID] or { items = {} }
    m.name = UnitName("npc") or m.name
    m.zone = (GetRealZoneText and GetRealZoneText()) or m.zone
    m.seen = time()
    if C_Map and C_Map.GetBestMapForUnit then
        local map = C_Map.GetBestMapForUnit("player")
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
        if map and ok and pos then
            local x, y = pos:GetXY()
            m.map, m.x, m.y = map, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
        end
    end
    m.items = {}
    ns.db.merchants[npcID] = m
    return m
end

local function captureMerchant()
    ns.db.vendorBuy = ns.db.vendorBuy or {}
    local merchant = merchantRecord()
    local n = GetMerchantNumItems and GetMerchantNumItems() or 0
    for index = 1, n do
        local itemID = GetMerchantItemID and GetMerchantItemID(index)
        local price, stack, extended
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(index)
            if info then price, stack, extended = info.price, info.stackCount, info.hasExtendedCost end
        elseif GetMerchantItemInfo then
            local _
            _, _, price, stack, _, _, _, extended = GetMerchantItemInfo(index)
        end
        if itemID and price and price > 0 and not extended then
            ns.db.vendorBuy[itemID] = price / math.max(stack or 1, 1)
            if merchant then merchant.items[itemID] = price / math.max(stack or 1, 1) end
        end
    end
end
ns.On("MERCHANT_SHOW", function() ns.Debounce("merchantprices", 0.3, captureMerchant) end)
ns.On("MERCHANT_UPDATE", function() ns.Debounce("merchantprices", 0.3, captureMerchant) end)

-- what a vendor charges for one, if any vendor you (or Auctionator, or ZugDAQ Professions) saw sells it
function ns.VendorBuy(itemID)
    local own = ns.db.vendorBuy and ns.db.vendorBuy[itemID]
    if own then return own end
    local a = Auctionator and Auctionator.API and Auctionator.API.v1
    if a and a.GetVendorPriceByItemID then
        local ok, p = pcall(a.GetVendorPriceByItemID, "ZugDAQ", itemID)
        if ok and type(p) == "number" and p > 0 then return p end
    end
    local pg = ZugDAQ_ProfDB and ZugDAQ_ProfDB.vendorPrices
    if pg and type(pg[itemID]) == "number" and pg[itemID] > 0 then return pg[itemID] end
end

-- cheapest way to buy one: vendor, else the AH listing
function ns.BuyPrice(itemID)
    local vendor = ns.VendorBuy(itemID)
    local ah = ns.AuctionPrice(itemID)
    if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
    if ah then return ah, "AH" end
end

-- ---------------------------------------------------------------- evaluation

-- per-refresh caches so the recursive search stays cheap
local E

local function owned(itemID)
    local v = E.owned[itemID]
    if v == nil then
        v = ns.AccountCount(itemID) -- every character's bags and bank, and the warbank
        E.owned[itemID] = v
    end
    return v
end

local function sell(itemID)
    local v = E.sell[itemID]
    if v == nil then
        v = ns.Value(itemID) or 0
        E.sell[itemID] = v
    end
    return v
end

-- cost of putting one unit into a craft, and where that number came from
local function useCost(itemID)
    local hit = E.cost[itemID]
    if hit then return hit[1], hit[2] end
    local cost, source
    local vendor = ns.VendorBuy(itemID)
    if vendor then
        cost, source = vendor, "vendor"
    elseif owned(itemID) > 0 then
        cost, source = sell(itemID), "owned"
    else
        local ah = ns.AuctionPrice(itemID)
        if ah then cost, source = ah, "AH" else cost, source = sell(itemID), "estimate" end
    end
    E.cost[itemID] = { cost, source }
    return cost, source
end

-- the cheapest item that fills a reagent slot
local function slotChoice(slot)
    local bestID, bestCost, bestSource
    for _, itemID in ipairs(slot.items) do
        local cost, source = useCost(itemID)
        if not bestCost or cost < bestCost then bestID, bestCost, bestSource = itemID, cost, source end
    end
    return bestID, bestCost or 0, bestSource
end

local worth

-- what one unit of `itemID` is worth when it goes into recipe r (other reagents paid for)
local function perUnitVia(r, itemID, depth, visiting)
    local myQty, others = nil, 0
    for _, slot in ipairs(r.slots) do
        local mine = false
        for _, id in ipairs(slot.items) do
            if id == itemID then mine = true break end
        end
        if mine and not myQty then
            myQty = slot.qty
        else
            local _, cost = slotChoice(slot)
            others = others + cost * slot.qty
        end
    end
    if not myQty or myQty <= 0 then return end
    local outEach, path = worth(r.output, depth, visiting)
    return (outEach * (r.yield or 1) - others) / myQty, path
end

-- best value of one unit: sell it, or craft it (up to `depth` steps). Returns value, path of recipes
worth = function(itemID, depth, visiting)
    local key = itemID .. ":" .. depth
    local memo = E.worth[key]
    if memo then return memo[1], memo[2] end
    local best, bestPath = sell(itemID), nil
    local uses = depth > 0 and E.usage[itemID]
    if uses and not visiting[itemID] then
        visiting[itemID] = true
        for _, u in ipairs(uses) do
            local v, sub = perUnitVia(u.recipe, itemID, depth - 1, visiting)
            if v and v > best + 0.5 then
                best = v
                bestPath = { u.recipe }
                for _, step in ipairs(sub or {}) do bestPath[#bestPath + 1] = step end
            end
        end
        visiting[itemID] = nil
    end
    E.worth[key] = { best, bestPath }
    return best, bestPath
end

local function begin()
    E = { owned = {}, sell = {}, cost = {}, worth = {}, usage = {} }
    for id, r in pairs(charRecipes()) do
        r.id = id -- so a recipe found anywhere (a crafting chain, a to-do) can be opened
        for _, slot in ipairs(r.slots) do
            for _, itemID in ipairs(slot.items) do
                E.usage[itemID] = E.usage[itemID] or {}
                table.insert(E.usage[itemID], { recipe = r })
            end
        end
    end
end

-- how many crafts the reagents on hand allow; vendor goods count as unlimited. nil = all from a vendor
local function craftable(r)
    local count
    for _, slot in ipairs(r.slots) do
        local vendor = false
        local have = 0
        for _, id in ipairs(slot.items) do
            if ns.VendorBuy(id) then vendor = true end
            have = have + owned(id)
        end
        if not vendor then
            local n = math.floor(have / slot.qty)
            count = count and math.min(count, n) or n
        end
    end
    return count
end

local function reagentDetails(r)
    local list = {}
    for _, slot in ipairs(r.slots) do
        local id, cost, source = slotChoice(slot)
        list[#list + 1] = { itemID = id, qty = slot.qty, cost = cost, source = source, have = owned(id) }
    end
    return list
end

-- reagents of one recipe with what each costs, for tooltips
function ns.RecipeReagents(r)
    if not E then begin() end
    return reagentDetails(r)
end

-- every known recipe with profit per craft and how many you can make
function ns.CraftRows()
    begin()
    local rows = {}
    for _, r in ipairs(accountRecipeList()) do -- every character's recipes: r.crafter knows it
        local outEach = sell(r.output)
        local value = outEach * (r.yield or 1)
        local cost = 0
        for _, slot in ipairs(r.slots) do
            local _, c = slotChoice(slot)
            cost = cost + c * slot.qty
        end
        local can = craftable(r)
        local profit = value - cost
        rows[#rows + 1] = {
            recipe = r, itemID = r.output, name = r.name, prof = r.prof, crafter = r.crafter, mine = r.mine, value = value, cost = cost,
            profit = profit, can = can, total = (can and profit > 0) and can * profit or nil,
            reagents = reagentDetails(r), hasAH = ns.AuctionPrice(r.output) ~= nil,
        }
    end
    return rows
end

-- materials you own that go into a known recipe: sell them, or craft them into what?
function ns.MaterialRows()
    begin()
    local rows = {}
    for itemID, uses in pairs(E.usage) do
        local have = owned(itemID)
        if have > 0 then
            local raw = sell(itemID)
            local best, path = worth(itemID, MAX_DEPTH, {})
            local gain = best - raw
            local usable = have
            if path then
                -- the first step can be held back by other reagents you don't have
                local r = path[1]
                local can = craftable(r)
                if can then
                    for _, slot in ipairs(r.slots) do
                        for _, id in ipairs(slot.items) do
                            if id == itemID then usable = math.min(have, can * slot.qty) end
                        end
                    end
                end
            end
            local ah = ns.AuctionPrice(itemID)
            local where = (ah and ah * (1 - ns.settings.ahCut) > (ns.VendorSell(itemID) or 0)) and "AH" or "vendor"
            rows[#rows + 1] = {
                itemID = itemID, name = ns.ItemName(itemID), have = have, raw = raw, best = best, path = path,
                where = where,
                gain = path and gain or 0, usable = path and usable or 0,
                totalGain = path and gain * usable or 0, uses = #uses,
            }
        end
    end
    return rows
end

-- ---------------------------------------------------------------- buy & craft

local MAX_FLIP_CRAFTS = 50
ns.FLIP_TARGET_MARGIN = 0.2 -- the "buy under" price leaves this much profit on top of the mats
ns.FLIP_PRICEY = 1.1        -- mats this far over their usual price are worth waiting on
local MIN_STEP_MARGIN = 0.1 -- stop buying up the listings once the next craft makes less than this

-- listings to buy from, cheapest first: the live check when it's the newest look, else one
-- tier at the last known price (as many as were listed on the last scan)
local function buyBook(itemID, price)
    local entry = ns.LiveListings(itemID)
    if entry and #entry.listings > 0 then
        local book = {}
        for i, l in ipairs(entry.listings) do book[i] = { price = l.price, qty = l.qty } end
        return book, true
    end
    local stats = ns.PriceStats(itemID) or {}
    return { { price = price, qty = stats.available or math.huge } }, false
end

-- buy n off a book (cheapest first): total cost and the highest price paid, or nil if it runs out
local function take(book, n)
    local cost, top = 0, 0
    while n > 0 do
        local l = book[1]
        if not l then return nil end
        local q = math.min(n, l.qty)
        cost = cost + q * l.price
        top = l.price
        l.qty = l.qty - q
        n = n - q
        if l.qty <= 0 then table.remove(book, 1) end
    end
    return cost, top
end

-- freshness, mats against their usual price, buy-under prices, how many crafts stay profitable
local function analyseFlip(row)
    local value, cost = row.value, row.cost
    local usualSum, nowSum = 0, 0
    local oldest, unknown = ns.PriceAge(row.itemID), ns.PriceAge(row.itemID) == nil
    for _, rg in ipairs(row.reagents) do
        if rg.source ~= "vendor" then
            local age = ns.PriceAge(rg.itemID)
            if age == nil then unknown = true elseif not oldest or age > oldest then oldest = age end
            rg.age = age
            local stats = ns.PriceStats(rg.itemID) or {}
            rg.usual = stats.usual
            if rg.usual and rg.usual > 0 then
                rg.ratio = rg.cost / rg.usual
                nowSum, usualSum = nowSum + rg.cost * rg.qty, usualSum + rg.usual * rg.qty
            end
            local rest = cost - rg.cost * rg.qty
            rg.breakEven = (value - rest) / rg.qty
            rg.buyUnder = (value / (1 + ns.FLIP_TARGET_MARGIN) - rest) / rg.qty
        end
        rg.need, rg.top = 0, nil
    end
    row.age = (not unknown) and oldest or nil
    row.stale = unknown or (oldest or 0) > ns.FRESH_SECONDS
    row.matsRatio = usualSum > 0 and nowSum / usualSum or nil

    -- walk the listings craft by craft until the next one makes too little to be worth it
    local books, live = {}, true
    for i, rg in ipairs(row.reagents) do
        if rg.source ~= "vendor" then
            local book, isLive = buyBook(rg.itemID, rg.cost)
            books[i] = book
            if not isLive then live = false end
        end
    end
    local crafts, total, spend = 0, 0, 0
    while crafts < MAX_FLIP_CRAFTS do
        local c, tops, ok = 0, {}, true
        for i, rg in ipairs(row.reagents) do
            if rg.source == "vendor" then
                c = c + rg.cost * rg.qty
            else
                local paid, top = take(books[i], rg.qty)
                if not paid then ok = false break end
                c, tops[i] = c + paid, top
            end
        end
        if not ok or value - c <= c * MIN_STEP_MARGIN then break end
        crafts, total, spend = crafts + 1, total + (value - c), spend + c
        for i, rg in ipairs(row.reagents) do
            rg.need = rg.need + rg.qty
            if tops[i] then rg.top = tops[i] end
        end
    end
    row.crafts, row.totalProfit, row.spend, row.liveBooks = crafts, total, spend, live

    if row.profit <= 0 then
        row.verdict = "loss"
    elseif row.stale then
        row.verdict = "check"
    elseif row.matsRatio and row.matsRatio > ns.FLIP_PRICEY then
        row.verdict = "pricey"
    elseif (row.margin or 0) < 0.1 then
        row.verdict = "thin"
    else
        row.verdict = "buy"
    end
end

-- recipes worth crafting even when every reagent is bought (all = include the ones that lose money)
function ns.FlipRows(all)
    begin()
    local rows = {}
    for _, r in ipairs(accountRecipeList()) do -- every character's recipes: r.crafter knows it
        local cost, complete, reagents = 0, true, {}
        for _, slot in ipairs(r.slots) do
            local bestID, best, bestSource
            for _, id in ipairs(slot.items) do
                local p, source = ns.BuyPrice(id)
                if p and (not best or p < best) then bestID, best, bestSource = id, p, source end
            end
            if not best then complete = false break end
            cost = cost + best * slot.qty
            reagents[#reagents + 1] = { itemID = bestID, qty = slot.qty, cost = best, source = bestSource,
                                        have = owned(bestID) }
        end
        local ah = ns.AuctionPrice(r.output)
        if complete and ah then
            local value = sell(r.output) * (r.yield or 1)
            local profit = value - cost
            if profit > 0 or all then
                local row = {
                    recipe = r, itemID = r.output, name = r.name, prof = r.prof, crafter = r.crafter, mine = r.mine,
                    value = value, cost = cost,
                    profit = profit, margin = cost > 0 and profit / cost or nil, reagents = reagents,
                    stats = ns.PriceStats(r.output) or {},
                }
                analyseFlip(row)
                rows[#rows + 1] = row
            end
        end
    end
    return rows
end

-- what to check on the AH for Buy & craft: results and AH-bought reagents, most promising first
function ns.FlipCheckItems(limit)
    limit = limit or 100
    local list, seenIDs = {}, {}
    local function add(id)
        if id and not seenIDs[id] and #list < limit then
            seenIDs[id] = true
            list[#list + 1] = id
        end
    end
    local rows = ns.FlipRows(true)
    table.sort(rows, function(a, b) return a.profit > b.profit end)
    for _, row in ipairs(rows) do
        add(row.itemID)
        for _, rg in ipairs(row.reagents) do
            if rg.source ~= "vendor" then add(rg.itemID) end
        end
    end
    -- recipes with no price at all yet, so they can show up next time
    for _, r in ipairs(accountRecipeList()) do -- every character's recipes: r.crafter knows it
        add(r.output)
        for _, slot in ipairs(r.slots) do
            for _, id in ipairs(slot.items) do
                if not ns.VendorBuy(id) then add(id) end
            end
        end
    end
    return list
end

function ns.KnownProfessions()
    local profs, count = {}, 0
    for _, r in pairs(charRecipes()) do
        if not profs[r.prof] then profs[r.prof] = 0 end
        profs[r.prof] = profs[r.prof] + 1
        count = count + 1
    end
    return profs, count
end

-- ---------------------------------------------------------------- open a recipe in the profession window

-- skill lines by (English) name, for recipes stored before their profession ID was recorded
local PROFESSION_IDS = {
    Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202, Leatherworking = 165,
    Tailoring = 197, Cooking = 185, ["First Aid"] = 129, Mining = 186, Skinning = 393, Herbalism = 182,
    Fishing = 356, Jewelcrafting = 755, Inscription = 773,
}

-- Opens the profession window at this recipe (r is a stored recipe table). Called straight from a click, and only
-- ever through Blizzard's own C_TradeSkillUI.OpenRecipe: reaching into the profession window (selecting a row in its
-- recipe list) or opening professions from timers taints the window, and Blizzard then blocks its own Create button
-- and blames ZugDAQ ("blocked from an action only available to the Blizzard UI").
function ns.OpenRecipe(r)
    if not (r and r.id) then return end
    -- another character's recipe (the lists cover the whole account): only they can craft it
    if r.crafter and r.mine == false then
        ns.Print("%s is %s's recipe: log in on %s to craft it.", r.name or "that", r.crafter, r.crafter)
        return
    end
    local T = C_TradeSkillUI
    if not (T and T.OpenRecipe) then return end
    if InCombatLockdown and InCombatLockdown() then
        ns.Print("can't open a profession in combat.")
        return
    end
    if ns.Trace then ns.Trace("OpenRecipe " .. tostring(r.id)) end
    if ZugDAQFrame then ZugDAQFrame:Lower() end
    local ok, result = pcall(T.OpenRecipe, r.id)
    if not ok or result == false then
        ns.Print("open %s from your spellbook, then right-click the recipe again.", r.prof or "the profession")
    end
end

-- ---------------------------------------------------------------- explore: what an item can become

-- chance one craft gives a skill point, by the colour the profession window showed
local SKILL_CHANCE = { [0] = 1, [1] = 0.75, [2] = 0.3, [3] = 0 }
ns.SKILL_COLORS = {
    [0] = { 1, 0.5, 0.25 }, [1] = { 1, 0.9, 0 }, [2] = { 0.25, 0.75, 0.25 }, [3] = { 0.55, 0.55, 0.55 },
}
ns.SKILL_NAMES = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }
local GRAPH_DEPTH = 3
local SHOW_CHILDREN = { [0] = 7, [1] = 4, [2] = 3 }

function ns.ProfessionSkill(prof)
    local c = ns.db.chars[ns.charKey]
    return c and c.profSkill and prof and c.profSkill[prof]
end

-- the reagent a recipe is "about": the most valuable one you can't just buy from a vendor
function ns.MainReagent(r)
    if not E then begin() end
    local bestID, bestCost
    for _, slot in ipairs(r.slots) do
        local id, cost, source = slotChoice(slot)
        if source ~= "vendor" and (not bestCost or cost * slot.qty > bestCost) then
            bestID, bestCost = id, cost * slot.qty
        end
    end
    return bestID or (r.slots[1] and r.slots[1].items[1])
end

-- everything that goes into a recipe you know, for the Explore list
function ns.ExploreItems()
    begin()
    local rows = {}
    for itemID, uses in pairs(E.usage) do
        local seen, n = {}, 0
        for _, u in ipairs(uses) do
            if not seen[u.recipe] then seen[u.recipe] = true n = n + 1 end
        end
        rows[#rows + 1] = { itemID = itemID, name = ns.ItemName(itemID), have = owned(itemID), uses = n,
                            vendor = ns.VendorBuy(itemID) ~= nil }
    end
    return rows
end

-- A tree of what `rootID` can be crafted into, up to three steps. Every node says what one unit of
-- the root item is worth if you craft down to that node and sell it there (rootValue), and gain is
-- that minus selling the root as it is. Nodes also carry the recipe's skill-up colour and what one
-- craft costs you (craftNet), so the cheapest way to level can be picked too.
--   result = { root, raw, profit = best node for gold, level = best node for skill points, prof, skill, colours }
function ns.CraftGraph(rootID)
    begin()
    local raw = sell(rootID)
    local root = { itemID = rootID, depth = 0, a = 1, b = 0, sell = raw, rootValue = raw, gain = 0,
                   children = {}, have = owned(rootID) }
    local all = { root }
    local prof, colours = nil, false

    local function expand(node, visiting)
        if node.depth >= GRAPH_DEPTH then return end
        local uses = E.usage[node.itemID]
        if not uses then return end
        visiting[node.itemID] = true
        local seen = {}
        for _, u in ipairs(uses) do
            local r = u.recipe
            if not seen[r] and not visiting[r.output] then
                seen[r] = true
                local qty, others = nil, 0
                for _, slot in ipairs(r.slots) do
                    local mine = false
                    for _, id in ipairs(slot.items) do
                        if id == node.itemID then mine = true break end
                    end
                    if mine and not qty then
                        qty = slot.qty
                    else
                        local _, cost = slotChoice(slot)
                        others = others + cost * slot.qty
                    end
                end
                if qty and qty > 0 then
                    local yield = r.yield or 1
                    local out = sell(r.output)
                    -- one unit of this node's item is worth v  =>  one root unit is worth a*v + b
                    local a = node.a * yield / qty
                    local b = node.b - node.a * others / qty
                    local child = {
                        itemID = r.output, recipe = r, parent = node, depth = node.depth + 1,
                        qty = qty, yield = yield, others = others, a = a, b = b, sell = out, children = {},
                    }
                    child.rootValue = a * out + b
                    child.gain = child.rootValue - raw
                    child.craftNet = others + qty * useCost(node.itemID) - out * yield
                    child.chance = r.diff and SKILL_CHANCE[r.diff]
                    if r.diff then colours = true end
                    if child.chance and child.chance > 0 then
                        child.costPerPoint = child.craftNet / (child.chance * math.max(1, r.ups or 1))
                    end
                    prof = prof or r.prof
                    node.children[#node.children + 1] = child
                    all[#all + 1] = child
                    expand(child, visiting)
                end
            end
        end
        visiting[node.itemID] = nil
    end
    expand(root, {})

    -- best value anywhere below each node; children best-first
    local function bestBelow(node)
        local best = node.rootValue
        for _, c in ipairs(node.children) do best = math.max(best, bestBelow(c)) end
        node.bestBelow = best
        table.sort(node.children, function(x, y) return x.bestBelow > y.bestBelow end)
        return best
    end
    bestBelow(root)

    -- best for gold: highest value per root unit (selling it as it is unless crafting beats it)
    local profit = root
    for _, n in ipairs(all) do
        if n.rootValue > profit.rootValue + 0.5 then profit = n end
    end
    -- best for leveling: the surest skill point, then the cheapest one
    local level
    for _, n in ipairs(all) do
        if n.chance and n.chance > 0 then
            if not level or n.chance > level.chance
                or (n.chance == level.chance and n.costPerPoint < level.costPerPoint) then
                level = n
            end
        end
    end
    local function mark(node, flag)
        while node do node[flag] = true node = node.parent end
    end
    mark(profit, "onProfit")
    if level then mark(level, "onLevel") end

    -- how many root units the gold route can use: the first craft may need reagents you lack
    if profit ~= root then
        local first = profit
        while first.parent ~= root do first = first.parent end
        local can = craftable(first.recipe)
        profit.usable = can and math.min(root.have, can * first.qty) or root.have
    end

    -- drop what's no use either way: no skill points and worth less than selling the item raw
    -- (kept when something further down is worth it, or it's on a route)
    local culled = 0
    local function size(node)
        local n = 1
        for _, c in ipairs(node.children) do n = n + size(c) end
        return n
    end
    local function cull(node)
        local keep = {}
        for _, c in ipairs(node.children) do
            if cull(c) then keep[#keep + 1] = c else culled = culled + size(c) end
        end
        node.children = keep
        return node.onProfit or node.onLevel or node.gain >= 0 or (node.chance or 0) > 0 or #keep > 0
    end
    cull(root)

    -- keep the picture readable: the best few children of each node, plus anything on a route
    local function prune(node)
        local keep, hidden = {}, 0
        for i, c in ipairs(node.children) do
            if i <= (SHOW_CHILDREN[node.depth] or 3) or c.onProfit or c.onLevel then
                keep[#keep + 1] = c
            else
                hidden = hidden + 1
            end
        end
        node.children, node.hidden = keep, hidden
        for _, c in ipairs(keep) do prune(c) end
    end
    prune(root)

    return { root = root, raw = raw, profit = profit, level = level, prof = prof,
             skill = ns.ProfessionSkill(prof), colours = colours, culled = culled }
end

-- "Cured Medium Hide > Hillman's Leather Vest"
function ns.PathText(path)
    if not path then return "Sell it as it is" end
    local names = {}
    for _, r in ipairs(path) do names[#names + 1] = ns.ItemName(r.output) or r.name or "?" end
    return table.concat(names, " > ")
end
