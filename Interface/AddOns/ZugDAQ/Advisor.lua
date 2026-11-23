local _, ns = ...

-- Turns everything ZugDAQ knows into one ranked to-do list of plain actions:
--   CRAFT   materials worth more crafted than sold
--   SELL    bag items to put on the AH (now, if the price is above usual)
--   VENDOR  everything a vendor pays more for, in one trip
--   BUY     recipes that profit even buying every reagent, and big AH deals
--   FIX     auctions that keep coming back or lose money
--   HOLD    bag items whose AH price is below usual right now
--   FARM    your best route
-- Each action: { verb, kind, itemID, title, detail, gold, goldText, items (for tooltips), search (names) }

ns.ACTION_STYLE = {
    CRAFT = { color = "|cff40ff40", order = 1 },
    SELL = { color = "|cffffd700", order = 2 },
    VENDOR = { color = "|cffc7c7cf", order = 3 },
    BUY = { color = "|cff66bbff", order = 4 },
    FIX = { color = "|cffff8040", order = 5 },
    FARM = { color = "|cff40ff40", order = 6 },
    HOLD = { color = "|cff8080ff", order = 7 },
}

local MIN_CRAFT_GAIN = 50     -- copper; smaller gains aren't worth the clicks
local MIN_SELL_TOTAL = 100


local function pctText(trend)
    return string.format("%d%%", math.floor(math.abs(trend - 1) * 100 + 0.5))
end

local function craftActions(out, crafting)
    for _, m in ipairs(ns.MaterialRows()) do
        if m.path and m.totalGain >= MIN_CRAFT_GAIN and m.usable > 0 then
            local r = m.path[1]
            local myQty = 1
            for _, slot in ipairs(r.slots) do
                for _, id in ipairs(slot.items) do
                    if id == m.itemID then myQty = slot.qty end
                end
            end
            local crafts = math.floor(m.usable / myQty)
            if crafts > 0 then
                crafting[m.itemID] = true
                -- one craft's worth: how many to make is the player's call (the mats on hand say how many they can)
                local parts = { string.format("One craft uses %d %s", myQty, m.name or "materials") }
                local buy, buyCost = {}, 0
                for _, rg in ipairs(ns.RecipeReagents(r)) do
                    if rg.itemID ~= m.itemID then
                        if rg.source == "vendor" then
                            buy[#buy + 1] = string.format("%d %s", rg.qty, ns.ItemName(rg.itemID) or "?")
                            buyCost = buyCost + rg.cost * rg.qty
                        else
                            parts[#parts + 1] = string.format("%d %s", rg.qty, ns.ItemName(rg.itemID) or "?")
                        end
                    end
                end
                local detail = table.concat(parts, " + ")
                if #buy > 0 then
                    detail = detail .. string.format(", plus %s from a vendor (%s)", table.concat(buy, ", "), ns.Money(buyCost))
                end
                if #m.path > 1 then
                    local rest = {}
                    for i = 2, #m.path do rest[#rest + 1] = ns.ItemName(m.path[i].output) or m.path[i].name or "?" end
                    detail = detail .. ". Then craft those into " .. table.concat(rest, ", then ")
                end
                local perCraft = math.floor(m.gain * myQty)
                detail = detail .. string.format(". Beats selling the %s raw by %s a craft. Your mats (all characters) make %d.",
                    m.name or "materials", ns.Money(perCraft), crafts)
                local outName = ns.ItemName(r.output) or r.name or "?"
                local search = { m.name }
                for _, step in ipairs(m.path) do search[#search + 1] = ns.ItemName(step.output) end
                out[#out + 1] = {
                    verb = "CRAFT", itemID = r.output,
                    title = string.format("Craft %s", outName),
                    detail = detail, gold = perCraft, goldText = ns.MoneyColored(perCraft),
                    weight = m.totalGain, -- sorted by everything the mats on hand could make, shown for one
                    material = m, search = search, recipe = r,
                }
            end
        end
    end
end

local function bagActions(out, crafting)
    local vendorItems, vendorTotal = {}, 0
    for _, b in ipairs(ns.BagRows()) do
        if not crafting[b.itemID] then
            local name = b.name or ("item " .. b.itemID)
            local stats = b.stats or {}
            if b.where ~= "AH" then
                vendorItems[#vendorItems + 1] = b
                vendorTotal = vendorTotal + b.total
            elseif b.signal == "low" or b.signal == "deal" then
                out[#out + 1] = {
                    verb = "HOLD", itemID = b.itemID,
                    title = string.format("Hold %d %s", b.count, name),
                    detail = string.format("AH price is %s below usual (%s now, usually %s). Sell when it recovers.",
                        pctText(stats.trend), ns.Money(stats.current), ns.Money(stats.usual)),
                    gold = 0, goldText = "|cffaaaaaa" .. ns.Money(b.total) .. "|r", search = { name },
                }
            elseif b.total >= MIN_SELL_TOTAL then
                local each = stats.current or ns.AuctionPrice(b.itemID)
                local detail = string.format("List at about %s each (the current lowest).", ns.Money(each))
                if b.signal == "high" then
                    detail = string.format("Good time: %s above its usual %s. ", pctText(stats.trend),
                        ns.Money(stats.usual)) .. detail
                elseif not stats.usual then
                    detail = detail .. " Not much price history yet."
                end
                if stats.available then detail = detail .. string.format(" %d listed on the last scan.", stats.available) end
                out[#out + 1] = {
                    verb = "SELL", itemID = b.itemID, hot = b.signal == "high",
                    title = string.format("Sell %d %s on the AH%s", b.count, name, b.signal == "high" and " now" or ""),
                    detail = detail, gold = b.total, goldText = ns.Money(b.total), search = { name },
                }
            end
        end
    end
    if #vendorItems > 0 and vendorTotal > 0 then
        table.sort(vendorItems, function(x, y) return x.total > y.total end)
        local names = {}
        for i = 1, math.min(4, #vendorItems) do names[#names + 1] = vendorItems[i].name or "?" end
        out[#out + 1] = {
            verb = "VENDOR",
            title = string.format("Vendor %d item%s", #vendorItems, #vendorItems == 1 and "" or "s"),
            detail = string.format("A vendor pays more than the AH for these: %s%s.", table.concat(names, ", "),
                #vendorItems > 4 and ", ..." or ""),
            gold = vendorTotal, goldText = ns.Money(vendorTotal), items = vendorItems,
        }
    end
end

local function buyActions(out)
    local flips = ns.FlipRows()
    table.sort(flips, function(x, y) return x.profit > y.profit end)
    local shown = 0
    for _, f in ipairs(flips) do
        if shown >= 3 then break end
        -- skip mats that are dearer than usual; stale prices are listed, with a warning
        if (f.margin or 0) >= 0.2 and (f.stats.available or 0) >= 1 and f.verdict ~= "pricey" then
            shown = shown + 1
            local names = {}
            -- one craft's mats and profit; how many is the player's call
            for _, rg in ipairs(f.reagents) do
                local under = rg.source ~= "vendor" and rg.buyUnder and (" under " .. ns.Money(math.max(0, rg.buyUnder))) or ""
                names[#names + 1] = string.format("%d %s%s", rg.qty, ns.ItemName(rg.itemID) or "?", under)
            end
            local search = { ns.ItemName(f.itemID) }
            for _, rg in ipairs(f.reagents) do
                if rg.source ~= "vendor" then search[#search + 1] = ns.ItemName(rg.itemID) end
            end
            local total = f.profit
            local detail = string.format("One craft: buy %s, sell at %s (%s margin).",
                table.concat(names, ", "), ns.Money(f.value), ns.Percent(f.margin))
            if f.crafts > 1 then
                detail = detail .. string.format(" The listings cover up to %d.", f.crafts)
            end
            if f.stale then
                detail = "|cffe64d4dPrices are " .. ns.AgeText(f.age) .. " old: refresh them on Crafting > Buy & craft first.|r " .. detail
            end
            out[#out + 1] = {
                verb = "BUY", itemID = f.itemID,
                title = string.format("Buy mats, craft %s", ns.ItemName(f.itemID) or f.name or "?"),
                detail = detail,
                gold = total, goldText = ns.MoneyColored(total), search = search,
                weight = f.crafts > 0 and f.totalProfit or f.profit, -- sorted by what the listings allow, shown for one
                recipe = f.recipe,
            }
        end
    end
end

local function fixActions(out)
    for name, a in pairs(ns.db.auctions) do
        local v = ns.AuctionVerdict(a)
        if v.outcomes >= 3 then
            local stats = ns.PriceStats(a.itemID) or {}
            local detail
            if v.profit < 0 then
                detail = string.format("Lost %s so far on deposits and buy cost. Stop listing it, or list it much lower.",
                    ns.Money(-v.profit))
            elseif v.sellThrough < 0.25 then
                detail = string.format("Only sells %s of the time. Vendor it instead, or undercut hard.", ns.Percent(v.sellThrough))
            elseif v.sellThrough < 0.5 then
                detail = string.format("Sells %s of the time. List a bit lower%s.", ns.Percent(v.sellThrough),
                    stats.usual and (" (usual price " .. ns.Money(stats.usual) .. ")") or "")
            end
            if detail then
                out[#out + 1] = {
                    verb = "FIX", itemID = a.itemID,
                    title = string.format("%s keeps coming back", name),
                    detail = detail, gold = 0, goldText = "", search = { name },
                }
            end
        end
    end
end

local function farmAction(out)
    local best
    for _, r in ipairs(ns.RouteStats()) do
        if r.gph and r.time >= 15 * 60 and (not best or r.gph > best.gph) then best = r end
    end
    if best then
        out[#out + 1] = {
            verb = "FARM",
            title = string.format("Farm %s", best.route),
            detail = string.format("Your best route: %s per hour over %s of runs.", ns.Money(best.gph), ns.Duration(best.time)),
            gold = best.gph, goldText = ns.Money(best.gph) .. "|cffaaaaaa/h|r",
        }
    end
end

function ns.Actions()
    local out, crafting = {}, {}
    craftActions(out, crafting)
    bagActions(out, crafting)
    buyActions(out)
    fixActions(out)
    farmAction(out)
    -- crafting first, then selling (hot prices first), and so on; biggest gold first within each
    table.sort(out, function(a, b)
        local oa, ob = ns.ACTION_STYLE[a.verb].order, ns.ACTION_STYLE[b.verb].order
        if oa ~= ob then return oa < ob end
        if (a.hot and 1 or 0) ~= (b.hot and 1 or 0) then return a.hot == true end
        return (a.weight or a.gold or 0) > (b.weight or b.gold or 0)
    end)
    for i, a in ipairs(out) do a.rank = i end
    return out
end
