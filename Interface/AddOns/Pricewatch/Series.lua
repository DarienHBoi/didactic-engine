local _, P = ...
P.Series = {}
local Se = P.Series

-- Builds the four graph series for one stored item over a window of days (30 / 90 / 0 = all).
-- opts = { range, today, sales = SalesmanAPI.sales list, e0, de = { {day, value} } }
-- Result: { market, listings, sales, de (each {day, value, ...}), minDay, maxDay, minV, maxV, hasData }.
-- Market and disenchant are per unit; sales are per unit too (assumed = stack size unknown, one unit taken).
function Se.build(item, opts)
    opts = opts or {}
    local today, e0 = opts.today or 0, opts.e0
    local out = { market = {}, listings = {}, sales = {}, de = {}, zug = {}, hasData = false }
    local first = nil
    local list = P.Store.daysList(item)
    local range = opts.range or 0
    local from = range > 0 and (today - range + 1) or nil
    for _, d in ipairs(list) do
        if (not from or d.day >= from) and d.day <= today then
            out.market[#out.market + 1] = { day = d.day, value = d.lo, hi = d.hi, qty = d.qty, hr = d.hr }
        end
    end
    for _, p in ipairs(item and item.posts or {}) do
        local day = P.Days.dayOf(p.t, e0)
        if day and (not from or day >= from) and day <= today then
            out.listings[#out.listings + 1] = { day = day, value = p.price, qty = p.qty }
        end
    end
    for _, s in ipairs(opts.sales or {}) do
        local day = P.Days.dayOf(s.time, e0)
        if day and type(s.perUnit) == "number" and (not from or day >= from) and day <= today then
            out.sales[#out.sales + 1] = { day = day, value = s.perUnit, assumed = s.assumed and true or false, units = s.units }
        end
    end
    for _, d in ipairs(opts.de or {}) do
        if (not from or d.day >= from) and d.day <= today then out.de[#out.de + 1] = { day = d.day, value = d.value } end
    end
    for _, d in ipairs(opts.zug or {}) do
        if (not from or d.day >= from) and d.day <= today then out.zug[#out.zug + 1] = { day = d.day, value = d.value } end
    end
    local minDay, maxDay, minV, maxV
    for _, key in ipairs({ "market", "listings", "sales", "de", "zug" }) do
        for _, p in ipairs(out[key]) do
            minDay = (minDay and minDay < p.day) and minDay or p.day
            maxDay = (maxDay and maxDay > p.day) and maxDay or p.day
            minV = (minV and minV < p.value) and minV or p.value
            maxV = (maxV and maxV > p.value) and maxV or p.value
            out.hasData = true
        end
    end
    if from then minDay, maxDay = from, today end
    out.minDay, out.maxDay, out.minV, out.maxV = minDay, maxDay, minV, maxV
    return out
end

-- Disenchant value per day: only days where every possible mat has a stored price (otherwise a gap).
-- days = list of day numbers; outcomes from P.DE.outcomes.
function Se.deByDay(db, outcomes, days)
    local out = {}
    if type(outcomes) ~= "table" or type(db) ~= "table" or type(db.items) ~= "table" then return out end
    for _, day in ipairs(days or {}) do
        local v = P.DE.value(outcomes, function(id)
            local it = db.items[id]
            local r = it and it.days[day]
            return r and r.lo or nil
        end)
        if v then out[#out + 1] = { day = day, value = v } end
    end
    return out
end
