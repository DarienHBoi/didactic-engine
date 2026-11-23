local _, ns = ...

-- The in-game sales planner (Crafting > Sales plan): the plan the app's Desk makes, worked out in game from the AH as
-- it is right now. Pick an item and how many; the plan lists the steps to get them onto the AH:
--   COLLECT  what you already hold, on any character or in the warbank (and who to mail it to)
--   BUY      the rest, from a vendor or the AH. On the AH it walks the listings from the last price check, cheapest
--            first, so buying 50 across 20 postings costs what those postings ask, not 50 x the lowest price
--   CRAFT    with the recipes your characters know, a few levels deep
--   POST     at the market price, never under a guildmate's listing
-- The plan is kept in ZugDAQDB.gamePlan, in the same shape as a plan sent from the app, and ticked off the same way.

local MAX_DEPTH = 3
local LIVE_OK = 6 * 3600 -- live listings older than this aren't trusted for costing a purchase

-- every learned recipe on the account, by what it makes: { recipe, crafter }
function ns.AccountRecipes()
    local byOutput = {}
    for key, c in pairs(ns.db.chars) do
        for _, r in pairs(c.recipes or {}) do
            if r.output and type(r.slots) == "table" and #r.slots > 0 then
                local list = byOutput[r.output]
                if not list then list = {} byOutput[r.output] = list end
                list[#list + 1] = { recipe = r, crafter = key:match("^[^-]+") or key }
            end
        end
    end
    return byOutput
end

-- one unit's price to buy (for choosing between buying and crafting): a vendor, else the AH
local function unitBuy(id)
    local vendor = ns.VendorBuy(id)
    local ah = ns.LivePrice(id) or ns.AuctionPrice(id) or ns.AppPrice(id)
    if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
    if ah then return ah, "ah" end
end

-- buying n on the AH, cheapest listing first, from the last price check: cost, how many the listings cover, the dearest
-- price paid and how many postings that took. nil when there's no recent check of it.
function ns.LadderCost(id, n)
    local live = ns.LiveListings(id)
    if not (live and live.listings and #live.listings > 0 and time() - (live.t or 0) < LIVE_OK) then return nil end
    local cost, got, top, posts = 0, 0, 0, 0
    for _, l in ipairs(live.listings) do
        if got >= n then break end
        local take = math.min(l.qty or 1, n - got)
        cost, got, top, posts = cost + take * l.price, got + take, l.price, posts + 1
    end
    return cost, got, top, posts, live
end

local function name(id) return ns.ItemName(id) or ("item " .. tostring(id)) end

-- the price to post at: the app's market price (or the AH's), never under a guildmate
local function postPrice(id)
    local stats = ns.AppStats and ns.AppStats(id)
    local price = (stats and stats.market) or ns.AuctionPrice(id) or ns.LivePrice(id) or 0
    local d = ns.AppData()
    local mates = d and d.listed and d.listed[id]
    local mate = mates and mates[1]
    if mate and mate[3] and (price == 0 or mate[3] >= price * 0.9) then price = math.max(price, mate[3]) end
    return price, mate, stats
end

--- Plans getting `qty` of `itemID` onto the AH. useStock: take what you hold first (else everything is bought).
function ns.MakeSalePlan(itemID, qty, useStock)
    qty = math.max(1, math.floor(qty or 1))
    local warnings = {}

    -- what's held where (used up as the plan takes from it)
    local held = {}
    local function hold(id, where, owner, n)
        if not useStock or not n or n <= 0 then return end
        held[id] = held[id] or {}
        table.insert(held[id], { where = where, owner = owner, n = n })
    end
    for key, c in pairs(ns.db.chars) do
        local who = key:match("^[^-]+") or key
        for id, n in pairs(c.bags or {}) do hold(id, who .. "'s bags", who, n) end
        for id, n in pairs(c.bank or {}) do hold(id, who .. "'s bank", who, n) end
    end
    for id, n in pairs(ns.db.warbank and ns.db.warbank.items or {}) do hold(id, "the warbank", nil, n) end

    local recipes = ns.AccountRecipes()

    -- cheapest route to one more: buy it, or craft it (its mats got the same way)
    local memo = {}
    local function best(id, depth, path)
        local key = id .. ":" .. depth
        if memo[key] ~= nil then return memo[key] or nil end
        local route
        local price, source = unitBuy(id)
        if price then route = { buy = source, unit = price } end
        local crafted
        if depth < MAX_DEPTH and recipes[id] and not path[id] then
            path[id] = true
            for _, m in ipairs(recipes[id]) do
                local cost, ok = 0, true
                for _, slot in ipairs(m.recipe.slots) do
                    local cheapest
                    for _, mat in ipairs(slot.items) do
                        local r = best(mat, depth + 1, path)
                        if r and (not cheapest or r.unit < cheapest.unit) then cheapest = r end
                    end
                    if not cheapest then ok = false break end
                    cost = cost + cheapest.unit * (slot.qty or 1)
                end
                if ok then
                    cost = cost / math.max(m.recipe.yield or 1, 1)
                    if not crafted or cost < crafted.unit then crafted = { craft = m, unit = cost } end
                end
            end
            path[id] = nil
        end
        if crafted and (not route or crafted.unit < route.unit or depth == 0) then route = crafted end
        memo[key] = route or false
        return route
    end

    local collects, buys, crafts, crafters = {}, {}, {}, {}
    local stockValue = 0
    local function heldCount(id)
        local n = 0
        for _, p in ipairs(held[id] or {}) do n = n + p.n end
        return n
    end

    local function get(id, need, depth, path)
        for _, p in ipairs(held[id] or {}) do
            if need <= 0 then break end
            local take = math.min(p.n, need)
            if take > 0 then
                p.n = p.n - take
                table.insert(collects, { id = id, where = p.where, owner = p.owner, n = take })
                stockValue = stockValue + take * (ns.Value(id) or 0)
                need = need - take
            end
        end
        if need <= 0 then return end
        local route = best(id, depth, path)
        if not route then
            table.insert(warnings, string.format("No price or recipe for %s: get %d yourself.", name(id), need))
            return
        end
        if route.buy then
            local key = id .. ":" .. route.buy
            local b = buys[key] or { id = id, kind = route.buy, n = 0, unit = route.unit }
            b.n = b.n + need
            buys[key] = b
            return
        end
        local r, crafter = route.craft.recipe, route.craft.crafter
        local times = math.ceil(need / math.max(r.yield or 1, 1))
        path[id] = true
        local mats = {}
        for _, slot in ipairs(r.slots) do
            local pick, pickCost
            for _, mat in ipairs(slot.items) do
                local enough = heldCount(mat) >= (slot.qty or 1) * times
                local mr = best(mat, depth + 1, path)
                local c = enough and -1 or (mr and mr.unit or math.huge)
                if not pick or c < pickCost then pick, pickCost = mat, c end
            end
            table.insert(mats, string.format("%d %s", (slot.qty or 1) * times, name(pick)))
            get(pick, (slot.qty or 1) * times, depth + 1, path)
        end
        path[id] = nil
        crafters[crafter] = true
        local made = math.floor(times * math.max(r.yield or 1, 1) + 0.5)
        table.insert(crafts, {
            k = "CRAFT", id = id, q = made, g = 0,
            t = string.format("Craft %dx %s", times, r.name or name(id)),
            d = string.format("On %s (%s). Uses %s.", crafter, r.prof or "?", table.concat(mats, ", "))
                .. (made > need and string.format(" Makes %d: %d left over.", made, made - need) or ""),
        })
    end

    local canMake = recipes[itemID] ~= nil
    get(itemID, qty, 0, {})
    if not canMake then
        for _, b in pairs(buys) do
            if b.id == itemID then
                table.insert(warnings, "Nobody on your account crafts it: this buys it to sell again, which only pays when it's listed cheap.")
                break
            end
        end
    end

    -- ---- the steps, in order
    local steps = {}
    local worker = next(crafters)
    if not worker then
        local most, n = nil, 0
        for _, c in ipairs(collects) do if c.owner and c.n > n then most, n = c.owner, c.n end end
        worker = most
    end
    local byPlace, order = {}, {}
    for _, c in ipairs(collects) do
        if not byPlace[c.where] then byPlace[c.where] = { owner = c.owner, items = {}, n = 0, value = 0 } order[#order + 1] = c.where end
        local g = byPlace[c.where]
        table.insert(g.items, string.format("%d %s", c.n, name(c.id)))
        g.n, g.value, g.id = g.n + c.n, g.value + c.n * (ns.Value(c.id) or 0), g.id == nil and c.id or (g.id == c.id and c.id or false)
    end
    for _, where in ipairs(order) do
        local g = byPlace[where]
        local mail = worker and g.owner ~= worker
        table.insert(steps, {
            k = "COLLECT", id = g.id or nil, q = g.n, g = 0,
            t = "Take " .. table.concat(g.items, ", ") .. " from " .. where,
            d = (mail and (g.owner and ("Mail them to " .. worker .. ".") or ("Withdraw them, on " .. worker .. ".")) or "You already have these.")
                .. " Worth " .. ns.Money(g.value) .. " sold as they are.",
        })
    end

    local spend = 0
    local vendorBuys, ahBuys = {}, {}
    for _, b in pairs(buys) do table.insert(b.kind == "vendor" and vendorBuys or ahBuys, b) end
    for _, b in ipairs(vendorBuys) do
        local total = b.n * b.unit
        spend = spend + total
        table.insert(steps, { k = "BUY", id = b.id, q = b.n, g = total,
            t = string.format("Buy %d %s from a vendor", b.n, name(b.id)),
            d = string.format("%s each.", ns.Money(b.unit)) })
    end
    for _, b in ipairs(ahBuys) do
        local cost, got, top, posts, live = ns.LadderCost(b.id, b.n)
        local total, detail
        if cost and got > 0 then
            local missing = b.n - got
            total = cost + missing * math.max(top, b.unit)
            detail = string.format("%s up to %s across %d listing%s, %s each on average (checked %s).",
                ns.Money(live.listings[1].price), ns.Money(top), posts, posts == 1 and "" or "s",
                ns.Money(math.floor(total / b.n)), ns.AgeText(time() - live.t) .. (live.by and (" by " .. live.by) or ""))
            if missing > 0 then
                detail = detail .. string.format(" Only %d were listed: the other %d are priced at %s.", got, missing, ns.Money(math.max(top, b.unit)))
                table.insert(warnings, string.format("Only %d %s on the AH (in the last check); the plan needs %d.", got, name(b.id), b.n))
            end
        else
            total = b.n * b.unit
            detail = string.format("About %s each: not checked on the AH lately, so buying several may cost more. Check AH prices first.", ns.Money(b.unit))
        end
        spend = spend + total
        table.insert(steps, { k = "BUY", id = b.id, q = b.n, g = total,
            t = string.format("Buy %d %s on the AH", b.n, name(b.id)), d = detail })
    end
    for _, c in ipairs(crafts) do table.insert(steps, c) end

    -- ---- posting
    local price, mate, stats = postPrice(itemID)
    local notes = {}
    if mate then table.insert(notes, string.format("%s has %d up at %s: don't go under a guildmate.", mate[1] or "?", mate[2] or 0, ns.Money(mate[3] or 0))) end
    local lowest = ns.LivePrice(itemID)
    if lowest and lowest < price then table.insert(notes, "The cheapest up now is " .. ns.Money(lowest) .. ".") end
    local perDay = stats and stats.soldPerDay or 0
    if perDay > 0 then
        local batch = math.max(1, math.ceil(perDay * 2))
        if qty > batch then table.insert(notes, string.format("Post about %d at a time (two days of sales).", batch)) end
        local days = qty / perDay
        table.insert(notes, days < 1 and "Should sell within a day." or string.format("Should sell in about %d days.", math.floor(days + 0.5)))
    end
    local cut = (ns.AppData() and ns.AppData().cut) or 0.05
    local revenue = math.floor(price * (1 - cut)) * qty
    table.insert(steps, { k = "POST", id = itemID, q = qty, g = revenue,
        t = string.format("Post %d %s at %s each", qty, name(itemID), ns.Money(price)),
        d = table.concat(notes, " ") .. string.format(" After the AH cut: %s.", ns.Money(revenue)) })
    if price == 0 then table.insert(warnings, "No price known for " .. name(itemID) .. " yet: check it on the AH.") end

    return { made = time(), id = itemID, qty = qty, price = price, spend = spend, revenue = revenue, stock = stockValue,
             useStock = useStock and true or false, steps = steps, warnings = warnings }
end

--- What to check on the AH before planning `itemID`: it and everything its recipes use (a few levels down), not vendor goods.
function ns.SalePlanCheckItems(itemID)
    local recipes, list, seen = ns.AccountRecipes(), {}, {}
    local function walk(id, depth)
        if seen[id] then return end
        seen[id] = true
        if not ns.VendorBuy(id) then list[#list + 1] = id end
        if depth >= MAX_DEPTH then return end
        for _, m in ipairs(recipes[id] or {}) do
            for _, slot in ipairs(m.recipe.slots) do
                for _, mat in ipairs(slot.items) do walk(mat, depth + 1) end
            end
        end
    end
    walk(itemID, 0)
    return list
end
