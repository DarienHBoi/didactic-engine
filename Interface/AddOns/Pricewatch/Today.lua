local _, P = ...
P.Today = {}
local Td = P.Today

local ACTION = { craft = "Craft + list", deal = "Buy + DE", bag = "Sell bag item", hold = "Hold" }
local function money(v) return P.Money.format(v) end
local function round(x) return math.floor(x + 0.5) end

-- ---------------------------------------------------------------------------------------------------------------------
-- Ranking (pure). A candidate is { id, name, quality, kind = craft | deal | bag | hold, gain (copper, before the sale rate),
-- cost, net (what it sells for after the cut), rate (0..1 or nil), units14, trendPct, days (scan days), age (price age in
-- scan days), now, market (hold rows) }.

local function thin(c)
    return type(c.days) ~= "number" or c.days < P.Config.TODAY_MIN_DAYS or type(c.age) ~= "number" or c.age > P.Config.TODAY_MAX_AGE
end

local function reason(c)
    local facts = {}
    if c.kind == "hold" and type(c.now) == "number" and type(c.market) == "number" and c.market > 0 then
        facts[#facts + 1] = ("price %d%% under its market"):format(round((c.market - c.now) / c.market * 100))
    elseif c.kind == "deal" and type(c.cost) == "number" and c.cost > 0 and type(c.net) == "number" then
        local pct = round((c.net - c.cost) / c.cost * 100)
        facts[#facts + 1] = ("%s%d%% over the buy price"):format(pct >= 0 and "+" or "", pct)
    end
    if type(c.units14) == "number" and c.units14 > 0 then facts[#facts + 1] = ("sold %d in 14 days"):format(c.units14) end
    if type(c.trendPct) == "number" and math.abs(c.trendPct) >= 3 then
        facts[#facts + 1] = ("market %s%d%%"):format(c.trendPct > 0 and "+" or "", c.trendPct)
    end
    if #facts == 0 then return ("%d scan days"):format(c.days or 0) end
    return table.concat(facts, ", ", 1, math.min(2, #facts))
end

local function breakdown(c)
    local parts = {}
    if c.kind == "hold" then
        parts[#parts + 1] = "now " .. money(c.now)
        parts[#parts + 1] = "Market " .. money(c.market)
    else
        local costLabel = c.kind == "deal" and "buy" or (c.kind == "bag" and "vendor" or "cost")
        local netLabel = c.kind == "deal" and "disenchants for" or "sells"
        parts[#parts + 1] = costLabel .. " " .. money(c.cost)
        parts[#parts + 1] = netLabel .. " " .. money(c.net) .. " after cut"
    end
    if type(c.rate) == "number" then parts[#parts + 1] = P.Rate.text(c.rate) .. " sell rate"
    elseif type(c.mktRate) == "number" then parts[#parts + 1] = P.Rate.text(c.mktRate) .. " market sell-through" end
    parts[#parts + 1] = ("%d scan days"):format(c.days or 0)
    return table.concat(parts, ", ")
end

-- rows (best first, at most TODAY_ROWS) and how many candidates were dropped for old or thin data. A candidate whose gain is
-- zero or less is not listed and not counted. Expected gain = gain x rate (plain gain when the rate is unknown). Hold rows
-- come after every do-now row.
function Td.rank(cands)
    local rows, skipped = {}, 0
    for _, c in ipairs(cands or {}) do
        if type(c) == "table" and type(c.gain) == "number" and c.gain > 0 then
            if thin(c) then
                skipped = skipped + 1
            else
                -- The own sale rate first; the market sell-through (sold tracker) when there is none.
                local rate = type(c.rate) == "number" and c.rate or (type(c.mktRate) == "number" and c.mktRate or nil)
                local score = (c.kind ~= "hold" and rate) and round(c.gain * rate) or c.gain
                rows[#rows + 1] = { id = c.id, name = c.name, quality = c.quality, kind = c.kind, action = ACTION[c.kind] or "Hold",
                    gain = score, rawGain = c.gain, rate = c.rate, useRate = rate, perDay = tonumber(c.mktPerDay) or 0,
                    days = c.days, age = c.age, count = c.count,
                    reason = reason(c), breakdown = breakdown(c) }
            end
        end
    end
    table.sort(rows, function(a, b)
        local ha, hb = a.kind == "hold", b.kind == "hold"
        if ha ~= hb then return hb end
        if a.gain ~= b.gain then return a.gain > b.gain end
        local ra, rb = a.useRate or 0, b.useRate or 0
        if ra ~= rb then return ra > rb end
        if a.perDay ~= b.perDay then return a.perDay > b.perDay end
        return a.id < b.id
    end)
    for i = #rows, P.Config.TODAY_ROWS + 1, -1 do rows[i] = nil end
    return rows, skipped
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Header: "Prices from 2 scans, newest today about 14:00" and whether it is stale (older than 3 days, shown orange).
-- Looks at the last 7 days of every stored item: bounded by items x 7.
function Td.header(db, today)
    if type(db) ~= "table" or type(db.items) ~= "table" or type(today) ~= "number" or next(db.items) == nil then
        return "No scans stored yet", true
    end
    local seen, newest, hr = {}, nil, nil
    for _, it in pairs(db.items) do
        local days = type(it) == "table" and it.days
        if type(days) == "table" then
            for d = today - 6, today do
                local r = days[d]
                if r then
                    seen[d] = true
                    if not newest or d > newest then newest, hr = d, nil end
                    if d == newest and type(r.hr) == "number" and (not hr or r.hr > hr) then hr = r.hr end
                end
            end
        end
    end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    if n == 0 then return "No scans stored in the last 7 days", true end
    local age = today - newest
    local when
    if age <= 0 then when = "today" .. (hr and (" about %02d:00"):format(hr) or "")
    else when = age .. " day" .. (age == 1 and "" or "s") .. " ago" end
    return ("Prices from %d scan%s, newest %s"):format(n, n == 1 and "" or "s", when), age > P.Config.TODAY_MAX_AGE
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Candidates from the sources, all injected so Pricewatch works alone (every source is optional and guarded):
-- deps = { recipes() -> {{itemID, name}}, profit(id) -> Salesman's profit row, value(id) -> P.Value table, outcomes(id) -> sale
-- outcomes, info(id) -> {name, quality, vendor}, verdict(id, bound) -> action word, deals() -> deal rows, bag() -> {{id, count, bound}},
-- market(id) -> P.Market.summary }.
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn, ...)
    if ok then return r end
    return nil
end

local function saleFacts(deps, id)
    local o = call(deps.outcomes, id)
    local rate = P.Rate.of(o)
    return rate, type(o) == "table" and tonumber(o.units14) or nil
end

-- Sold tracker figures (sell-through, sold/day), only when tracking is not thin.
local function marketFacts(deps, id)
    local m = call(deps.market, id)
    if type(m) ~= "table" or m.thin then return nil, nil end
    return tonumber(m.sellThrough), tonumber(m.perDay)
end

local function underMarket(v)
    return type(v.now) == "number" and type(v.market) == "number" and v.now < v.market * P.Config.HOLD_BELOW
end

function Td.candidates(deps)
    deps = deps or {}
    local out = {}
    for _, rc in ipairs(call(deps.recipes) or {}) do
        local id = type(rc) == "table" and rc.itemID
        local p = type(id) == "number" and call(deps.profit, id)
        if type(p) == "table" and type(p.profit) == "number" and p.profit > 0 then
            local v = call(deps.value, id)
            local rate, units14 = saleFacts(deps, id)
            local mr, mpd = marketFacts(deps, id)
            local c = { id = id, name = rc.name or ("Item " .. id), kind = "craft", gain = p.profit, cost = p.mats, net = p.net,
                rate = rate, units14 = units14, days = v and v.days or false, age = v and v.age or false, trendPct = v and v.trendPct,
                mktRate = mr, mktPerDay = mpd }
            if v and underMarket(v) then
                c.kind, c.now, c.market = "hold", v.now, v.market
                c.gain = P.Reco.net(v.market) - P.Reco.net(v.now)
            end
            out[#out + 1] = c
        end
    end
    for _, r in ipairs(call(deps.deals) or {}) do
        if type(r) == "table" and type(r.id) == "number" and type(r.profit) == "number" then
            out[#out + 1] = { id = r.id, name = r.name or ("Item " .. r.id), quality = r.quality, kind = "deal", gain = r.profit,
                cost = r.buy, net = r.de, days = r.days or false, age = r.age or 0 }
        end
    end
    for _, b in ipairs(call(deps.bag) or {}) do
        local id = type(b) == "table" and b.id
        local v = type(id) == "number" and not b.bound and call(deps.value, id)
        if type(v) == "table" and type(v.now) == "number" and call(deps.verdict, id, false) ~= "disenchant" then
            local info = call(deps.info, id) or {}
            local units = math.min(tonumber(b.count) or 1, P.Config.BAG_UNITS)
            local net = P.Reco.net(v.now * units)
            local vendor = (tonumber(info.vendor) or 0) * units
            if net and P.Reco.beats(net, vendor) then
                local rate, units14 = saleFacts(deps, id)
                local c = { id = id, name = info.name or ("Item " .. id), quality = info.quality, kind = "bag", gain = net - vendor,
                    cost = vendor, net = net, rate = rate, units14 = units14, days = v.days, age = v.age, trendPct = v.trendPct,
                    count = units }
                c.mktRate, c.mktPerDay = marketFacts(deps, id)
                if underMarket(v) then
                    c.kind, c.now, c.market = "hold", v.now, v.market
                    c.gain = (P.Reco.net(v.market * units) or 0) - net
                end
                out[#out + 1] = c
            end
        end
    end
    return out
end

function Td.build(deps)
    local rows, skipped = Td.rank(Td.candidates(deps))
    return { rows = rows, skipped = skipped }
end

-- The live sources (every one guarded; an absent addon is an empty source).
function Td.live()
    return {
        recipes = P.Adapters.salesmanRecipes,
        profit = P.Adapters.salesmanProfit,
        value = function(id) return P.Value.get(id) end,
        outcomes = P.Adapters.salesmanOutcomes,
        info = P.Adapters.itemInfo,
        verdict = function(id, bound)
            local r = P.Tip.evaluate(id, bound, P.Tip.deps())
            return r and r.action or nil
        end,
        deals = function() if not P.Mod.on("deals") then return nil end return P.Deals.last end,
        bag = P.Adapters.bagItems,
        market = function(id) if not P.Mod.on("market") then return nil end return P.Market.summary(P.db, id, P.Days.dayOf(time(), P.Days.epoch0())) end,
    }
end
