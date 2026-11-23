local _, ns = ...

-- Plain-language pointers built from your own numbers: what is earning, what is costing,
-- and what to change. Each insight is { text, kind } where kind is good / warn / bad / tip.

local function share(part, whole) return whole > 0 and part / whole or 0 end

local function topOf(map)
    local bestKey, bestValue
    for key, value in pairs(map) do
        if not bestValue or value > bestValue then bestKey, bestValue = key, value end
    end
    return bestKey, bestValue or 0
end

function ns.Insights()
    local out = {}
    local function add(kind, fmt, ...) out[#out + 1] = { kind = kind, text = string.format(fmt, ...) } end

    local week = ns.Totals(ns.LastDays(7))
    local lastWeekKeys = {}
    for i = 8, 14 do lastWeekKeys[#lastWeekKeys + 1] = ns.DayKey(time() - (i - 1) * 86400) end
    local prev = ns.Totals(lastWeekKeys)

    -- income mix
    if week.income > 0 then
        local cat, amount = topOf(week.inc)
        add("good", "%s brought in the most this week: %s (%s of your income).",
            cat, ns.Money(amount), ns.Percent(share(amount, week.income)))
        local hours = week.online / 3600
        if hours >= 1 then
            local rate = week.net / hours
            local text = string.format("You're making %s per hour played this week", ns.Money(rate))
            if prev.online >= 3600 then
                local prevRate = prev.net / (prev.online / 3600)
                text = text .. string.format(" (last week: %s)", ns.Money(prevRate))
            end
            add(rate >= 0 and "good" or "bad", "%s.", text)
        end
    end

    -- costs worth looking at
    local repairs = week.exp["Repairs"] or 0
    if repairs > 0 and week.income > 0 and share(repairs, week.income) >= 0.15 then
        add("warn", "Repairs ate %s of this week's income (%s). Dying less or farming easier mobs pays.",
            ns.Percent(share(repairs, week.income)), ns.Money(repairs))
    end
    local deposits = week.exp["Auction deposits"] or 0
    local sales = week.inc["Auction sales"] or 0
    if deposits > 0 and deposits > sales * 0.2 then
        add("warn", "AH deposits (%s) are high next to AH sales (%s) this week. Shorter durations or fewer relists help.",
            ns.Money(deposits), ns.Money(sales))
    end

    -- farming routes
    local routes = ns.RouteStats()
    local ranked = {}
    for _, r in ipairs(routes) do
        if r.gph and r.time >= 15 * 60 then ranked[#ranked + 1] = r end
    end
    table.sort(ranked, function(a, b) return a.gph > b.gph end)
    if #ranked >= 1 then
        add("good", "Best farm: %s at %s per hour over %d run%s.", ranked[1].route, ns.Money(ranked[1].gph),
            ranked[1].runs, ranked[1].runs == 1 and "" or "s")
    end
    if #ranked >= 2 then
        local worst = ranked[#ranked]
        add("tip", "%s earns %s per hour, %s less than %s. Swap the time over.", worst.route, ns.Money(worst.gph),
            ns.Percent(1 - share(worst.gph, ranked[1].gph)), ranked[1].route)
    end
    if #ranked >= 1 then
        local top = ns.TopItems(ranked[1].items, 1)[1]
        if top and ranked[1].value > 0 then
            add("tip", "%s is %s of what %s earns. If its price drops, so does the route.",
                ns.ItemName(top.itemID) or "One item", ns.Percent(share(top.value, ranked[1].value)), ranked[1].route)
        end
    end

    -- auction items
    local winners, losers, slow = {}, {}, {}
    for name, a in pairs(ns.db.auctions) do
        local v = ns.AuctionVerdict(a)
        if v.outcomes >= 3 then
            if v.profit < 0 then losers[#losers + 1] = { name = name, v = v }
            elseif v.sellThrough >= 0.85 and a.sold >= 3 then winners[#winners + 1] = { name = name, v = v }
            elseif v.sellThrough < 0.34 then slow[#slow + 1] = { name = name, v = v } end
        end
    end
    table.sort(winners, function(x, y) return x.v.profit > y.v.profit end)
    table.sort(slow, function(x, y) return x.v.sellThrough < y.v.sellThrough end)
    for i = 1, math.min(2, #winners) do
        add("good", "%s sells %s of the time. You could likely ask more for it.", winners[i].name,
            ns.Percent(winners[i].v.sellThrough))
    end
    for i = 1, math.min(2, #slow) do
        add("warn", "%s only sells %s of the time. Price it lower, or vendor it.", slow[i].name,
            ns.Percent(slow[i].v.sellThrough))
    end
    for i = 1, math.min(2, #losers) do
        add("bad", "%s has lost you %s on the AH so far (deposits and buy cost beat sales).", losers[i].name,
            ns.Money(-losers[i].v.profit))
    end

    -- materials worth more crafted than sold raw
    local mats = ns.MaterialRows()
    table.sort(mats, function(x, y) return x.totalGain > y.totalGain end)
    for i = 1, math.min(2, #mats) do
        local m = mats[i]
        if m.path and m.totalGain >= 100 then
            add("tip", "Your %d %s are worth %s more crafted into %s than sold raw. See Crafting.",
                m.usable, m.name or "materials", ns.Money(m.totalGain), ns.PathText(m.path))
        end
    end

    -- what's in the bags right now
    local sellNow, sellValue = 0, 0
    for _, r in ipairs(ns.BagRows()) do
        if r.signal == "high" then sellNow, sellValue = sellNow + 1, sellValue + r.total end
    end
    if sellNow > 0 then
        add("tip", "%d item%s in your bags %s priced above usual right now, worth about %s. See Market > My bags.",
            sellNow, sellNow == 1 and "" or "s", sellNow == 1 and "is" or "are", ns.Money(sellValue))
    end

    if not ns.HasAuctionator() then
        add("bad", "Auctionator isn't loaded, so items can only be valued at vendor prices.")
    end
    if #out == 0 then
        add("tip", "Not much to go on yet. Play as normal; farm with /zug farm start, and this fills in.")
    end
    return out
end
