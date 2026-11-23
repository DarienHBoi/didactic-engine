local _, P = ...
P.Deals = {}
local Dl = P.Deals

local BELOW_MAX = 1000 -- vendor-flip candidates kept per scan

local function round(x) return math.floor(x + 0.5) end

-- A row is weak (greyed, red "!") when its price is older than DEALS_MAX_AGE_DAYS scan days (the one stale threshold: the same one
-- hides stale rows unless "Include stale" is ticked), or, for disenchant rows, when a mat
-- has fewer than DEALS_THIN_DAYS scan days of history (an unknown history counts as thin). Vendor rows have no mats.
function Dl.weak(row)
    if type(row.age) == "number" and row.age > P.Config.DEALS_MAX_AGE_DAYS then return true end
    if row.kind == "vendor" then return false end
    return type(row.days) ~= "number" or row.days < P.Config.DEALS_THIN_DAYS
end

-- Why a row is weak, for its hover; nil when it is not.
function Dl.weakNote(row)
    local old = type(row.age) == "number" and row.age > P.Config.DEALS_MAX_AGE_DAYS
    local thin
    if row.kind ~= "vendor" then
        if type(row.days) ~= "number" then thin = "unknown"
        elseif row.days < P.Config.DEALS_THIN_DAYS then thin = row.days end
    end
    local oldText = old and ("Price is " .. row.age .. " days old") or nil
    if oldText and thin == "unknown" then return oldText .. "; material history unknown" end
    if oldText and thin then return oldText .. "; a material has " .. thin .. " scan day" .. (thin == 1 and "" or "s") end
    if oldText then return oldText end
    if thin == "unknown" then return "Material history unknown" end
    if thin then return "Thin history: a material has " .. thin .. " scan day" .. (thin == 1 and "" or "s") end
    return nil
end

-- The margin the Min profit box feeds into P.Reco.beats: its minimum in copper (the percentage keeps its default); nil = defaults.
function Dl.margin(minCopper)
    if type(minCopper) ~= "number" then return nil end
    return { min = minCopper }
end

-- "1.5" -> 15000 copper (gold with decimals); nil for blank, junk or negative text.
function Dl.parseGold(text)
    if type(text) ~= "string" then return nil end
    local n = text:match("^%s*(%d+%.?%d*)%s*$") or text:match("^%s*(%.%d+)%s*$")
    n = tonumber(n)
    if not n then return nil end
    return math.floor(n * 10000 + 0.5)
end

-- 15000 -> "1.5", 20000 -> "2".
function Dl.formatGold(copper)
    if type(copper) ~= "number" then return "" end
    local s = ("%.4f"):format(copper / 10000)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end

local function matches(row, a, b, key)
    if key == "roi" then
        if a.roi ~= b.roi then return a.roi > b.roi end
        if a.profit ~= b.profit then return a.profit > b.profit end
    elseif key == "score" then
        local as, bs = a.score or 0, b.score or 0
        if as ~= bs then return as > bs end
        if a.profit ~= b.profit then return a.profit > b.profit end
    elseif key == "age" then
        local aa, ba = a.age or 0, b.age or 0
        if aa ~= ba then return aa < ba end
        if a.profit ~= b.profit then return a.profit > b.profit end
    else
        if a.profit ~= b.profit then return a.profit > b.profit end
    end
    return a.id < b.id
end

-- A sorted copy: "profit" (default, most first), "roi" (best first, ties by profit), "score" (flip: profit x p(sell), ties by profit)
-- or "age" (newest first, ties by profit).
function Dl.sort(rows, key)
    local out = {}
    for _, r in ipairs(rows or {}) do out[#out + 1] = r end
    table.sort(out, function(a, b) return matches(nil, a, b, key) end)
    return out
end

-- "8 deals, +2g 40s if you buy all". Live lots rows count each lot once (deals rework R9): a group head adds the sum of its lots,
-- an expanded lot row adds nothing (its head already did): "5 lots, +1g if you buy all".
function Dl.totalText(rows)
    local n, total, lots = 0, 0, false
    for _, r in ipairs(rows or {}) do
        if r.group then
            lots = true
            for _, l in ipairs(r.lots or {}) do n = n + 1; total = total + (l.profit or 0) end
        elseif not r.lot then
            n = n + 1; total = total + (r.profit or 0)
        end
    end
    local word = lots and "lot" or "deal"
    if n == 0 then return "0 " .. word .. "s" end
    return ("%d %s%s, +%s if you buy all"):format(n, word, n == 1 and "" or "s", P.Money.format(total))
end

-- Deals rework (views over the index): the three candidate lists from the deal index and the buy prices, without asking the
-- client or any price source. items = PricewatchDB.dealIndex.items, prices = P.DealIndex.prices(). ageOf(entry) -> scan days of
-- that price, read only for items that pass (and kept on the entry). Returns { de, below, flips, missing = ids not indexed }.
function Dl.candidates(items, prices, ageOf)
    local out = { de = {}, below = {}, flips = {}, missing = {} }
    for _, p in ipairs(prices and prices.list or {}) do
        local it = items and items[p.id]
        if not it then
            out.missing[#out.missing + 1] = p.id
        else
            local function age()
                if p.age == nil and type(ageOf) == "function" then
                    local ok, a = pcall(ageOf, p)
                    if ok and type(a) == "number" then p.age = a end
                end
                return p.age
            end
            local price = p.price
            if type(it.q) == "number" and it.q >= 2 and it.q <= 4 and (it.c == 2 or it.c == 4) and P.DE.bracket(it.q, it.c, it.l) then
                out.de[#out.de + 1] = { id = p.id, name = it.n, quality = it.q, classID = it.c, ilvl = it.l, price = price, age = age() }
            end
            if type(it.v) == "number" and it.v > price and #out.below < BELOW_MAX then
                out.below[#out.below + 1] = { id = p.id, name = it.n, quality = it.q, price = price, vendor = it.v, age = age() }
            end
            if type(it.r) == "number" and type(it.d) == "number" and price <= it.r * P.Config.FLIP_BELOW + 1e-9
                and #out.flips < P.Config.FLIP_MAX then
                out.flips[#out.flips + 1] = { id = p.id, name = it.n, quality = it.q, price = price, market = it.r, vendor = it.v,
                    age = age(), demand = { perDay = it.d, p = it.p or P.Config.SELL_DEFAULT, source = it.s } }
            end
        end
    end
    return out
end

-- Hover line: what disenchanting gives, most likely first, at most four mats, quantities to one decimal.
-- "Disenchant gives ~ Strange Dust x2.1, Soul Dust x0.5". nameOf(id) -> name or nil.
function Dl.givesText(outcomes, nameOf)
    if type(outcomes) ~= "table" or #outcomes == 0 then return nil end
    local list = {}
    for _, o in ipairs(outcomes) do list[#list + 1] = { id = o.id, q = o.chance * o.avg } end
    table.sort(list, function(a, b) if a.q ~= b.q then return a.q > b.q end return a.id < b.id end)
    local parts = {}
    for i = 1, math.min(4, #list) do
        local okN, name = pcall(nameOf or function() end, list[i].id)
        local q = ("%.1f"):format(math.floor(list[i].q * 10 + 0.5) / 10):gsub("%.0$", "")
        parts[#parts + 1] = ((okN and type(name) == "string" and name ~= "") and name or ("Item " .. list[i].id)) .. " x" .. q
    end
    return "Disenchant gives ~ " .. table.concat(parts, ", ")
end

-- Rows where the disenchant value (after the AH cut) beats the buy price by the margin.
-- candidates: { id, name, quality, classID, ilvl, price (AH lowest, copper), age (scan days) }.
-- matPrice(id) -> price, age (scan days). opts: includeStale, includeHighSkill, skill (enchanting, nil = unknown), maxAge, margin,
-- matDays(id) -> scan days of history of that mat; memo = the DE.unitValue memo (P.DealIndex.memo()). Values come from P.DE.unitValue.
-- Row: { id, name, quality, buy, de (after the cut), gets (= de), profit, roi (percent), age (oldest of item and mats), days (thinnest
-- mat history, nil when unknown), weak, kind = "de", needSkill, outcomes }.
function Dl.build(candidates, matPrice, opts)
    opts = opts or {}
    local maxAge = opts.maxAge or P.Config.DEALS_MAX_AGE_DAYS
    local rows = {}
    for _, c in ipairs(candidates or {}) do
        local u = type(c.price) == "number" and c.price > 0 and P.DE.unitValue(c.quality, c.classID, c.ilvl,
            { price = matPrice, days = opts.matDays, memo = opts.memo }) or nil
        if u then
            local age, days, de = math.max(c.age or 0, u.age or 0), u.days, u.de
            if de and P.Reco.beats(de, c.price, opts.margin) and (opts.includeStale or age <= maxAge) then
                local need = u.need
                local tooHigh = type(opts.skill) == "number" and need and need > opts.skill
                if not tooHigh or opts.includeHighSkill then
                    local row = { id = c.id, name = c.name, quality = c.quality, buy = c.price, de = de, gets = de,
                        profit = de - c.price, roi = round((de - c.price) / c.price * 100), age = age, days = days, kind = "de",
                        needSkill = tooHigh and need or nil, outcomes = u.outcomes }
                    row.weak = Dl.weak(row)
                    rows[#rows + 1] = row
                end
            end
        end
    end
    return Dl.sort(rows, "profit")
end

-- "Below vendor" mode: listed items whose buyout is under the vendor price (no AH cut on a vendor sale).
-- candidates: { id, name, quality, price, vendor, age }. opts: includeStale, maxAge, margin.
function Dl.buildVendor(candidates, opts)
    opts = opts or {}
    local maxAge = opts.maxAge or P.Config.DEALS_MAX_AGE_DAYS
    local rows = {}
    for _, c in ipairs(candidates or {}) do
        if type(c.price) == "number" and c.price > 0 and type(c.vendor) == "number" and c.vendor > c.price then
            local age = c.age or 0
            if P.Reco.beats(c.vendor, c.price, opts.margin) and (opts.includeStale or age <= maxAge) then
                local row = { id = c.id, name = c.name, quality = c.quality, buy = c.price, de = c.vendor, gets = c.vendor,
                    profit = c.vendor - c.price, roi = round((c.vendor - c.price) / c.price * 100), age = age, kind = "vendor" }
                row.weak = Dl.weak(row)
                rows[#rows + 1] = row
            end
        end
    end
    return Dl.sort(rows, "profit")
end

-- Flip mode. The price a flip is relisted at: the lower of the scan Market and ZugDAQ's market, so one cheap scan day (or one odd
-- server figure) cannot make a flip look better than it is. nil when neither is known.
function Dl.flipRef(scanMarket, zugMarket, historyMedian)
    local best
    for _, x in ipairs({ scanMarket or false, zugMarket or false, historyMedian or false }) do
        if type(x) == "number" and x > 0 and (not best or x < best) then best = x end
    end
    return best
end

-- How fast an item sells: { perDay, p, source } with perDay from ZugDAQ's sells/day, else the sold tracker (not thin), and p from
-- P.Reco.pSell (own rate, tracker, ZugDAQ, default). nil when no per-day figure exists (a flip needs measured demand).
-- deps = { market(id) -> tracker summary, zug(id) -> { perDay }, outcomes(id) } (the P.Reco.pSell deps); every call guarded.
function Dl.demand(id, deps)
    deps = deps or {}
    local perDay, source
    -- ZugDAQ first, the sold tracker as fallback (owner 2026-11-21: ZugDAQ wins duplicates; audit step 6)
    if type(deps.zug) == "function" then
        local ok, z = pcall(deps.zug, id)
        if ok and type(z) == "table" and type(z.perDay) == "number" and z.perDay > 0 then perDay, source = z.perDay, "zugdaq" end
    end
    if not perDay and type(deps.market) == "function" then
        local ok, m = pcall(deps.market, id)
        if ok and type(m) == "table" and not m.thin and type(m.perDay) == "number" then perDay, source = m.perDay, "market" end
    end
    if not perDay then return nil end
    local p = P.Reco.pSell(id, deps)
    return { perDay = perDay, p = p, source = source }
end

-- Flip rows: listed at most FLIP_BELOW x Market, selling at least FLIP_MIN_PER_DAY a day. candidates: { id, name, quality, price (Now),
-- market (the flip reference), vendor, age, demand (optional: the index's stored Dl.demand) }. demandOf(id) -> Dl.demand table
-- (used when a candidate has no demand). opts: includeStale, maxAge, margin (Min profit).
-- profit = Market after the cut - Now - deposit x (1 - p) (the deposit is lost only when the relist does not sell);
-- score = profit x p. Row: { id, name, quality, buy, gets, profit, roi, score, p, perDay, source, age, weak, kind = "flip" }.
function Dl.buildFlip(candidates, demandOf, opts)
    opts = opts or {}
    local maxAge = opts.maxAge or P.Config.DEALS_MAX_AGE_DAYS
    local rows = {}
    for _, c in ipairs(candidates or {}) do
        local price, ref = c.price, c.market
        if type(price) == "number" and price > 0 and type(ref) == "number" and price <= ref * P.Config.FLIP_BELOW + 1e-9 then
            local age = c.age or 0
            local okD, dm = true, c.demand
            if dm == nil then okD, dm = pcall(demandOf, c.id) end
            if okD and type(dm) == "table" and type(dm.perDay) == "number" and dm.perDay >= P.Config.FLIP_MIN_PER_DAY
                and type(dm.p) == "number" and (opts.includeStale or age <= maxAge) then
                local gets = P.Reco.net(ref)
                local deposit = P.Reco.deposit(c.id, c.vendor, opts)
                local back = gets - deposit * (1 - dm.p)
                if P.Reco.beats(back, price, opts.margin) then
                    local profit = round(back - price)
                    local row = { id = c.id, name = c.name, quality = c.quality, buy = price, gets = gets, profit = profit,
                        roi = round(profit / price * 100), score = round(profit * dm.p), p = dm.p, perDay = dm.perDay,
                        source = dm.source, age = age, kind = "flip" }
                    row.weak = type(age) == "number" and age > P.Config.DEALS_MAX_AGE_DAYS
                    rows[#rows + 1] = row
                end
            end
        end
    end
    return Dl.sort(rows, "score")
end

-- Whether the panel should rebuild its rows now: when the scan is finished, or when something changed and DEALS_REBUILD_SECS
-- have passed since the last rebuild.
function Dl.due(dirty, since, finished)
    return finished or (dirty and since >= P.Config.DEALS_REBUILD_SECS)
end

-- Incremental classification of Auctionator's listed items. listed = { {id, price, age?}, ... };
-- getInfo(id) -> { name, quality, classID, ilvl, vendor } or nil while the client has not cached the item; request(id) asks it to;
-- ageOf(entry) -> scan days of that entry's price, read only for items that matter (disenchant candidates and vendor deals).
-- step(budget) does at most `budget` items and returns how many are still queued. Items without info wait (scan.waiting)
-- until onInfo(id, success) puts them back in the queue. A failed load is asked for once more, then dropped; so is an item that
-- answers but still has no info (asked twice at most, else it looped forever). tick(dt) drops
-- every item still waiting once the queue has been empty for DEALS_TIMEOUT_SECS (scan.gaveUp counts them).
-- scan.candidates feeds the disenchant rows, scan.below the below-vendor rows.
-- refOf(id) (optional) -> the flip reference price (Dl.flipRef); items listed at most FLIP_BELOW x it go to scan.flips.
-- onItem(e, info) (optional): every item whose info is known goes to it instead of the three lists (the deal index uses the same
-- queue, wait, retry and give-up rules this way). step(budget, stop) also ends early when stop() returns true (a time budget).
function Dl.newScan(listed, getInfo, request, ageOf, refOf, onItem)
    local scan = { candidates = {}, below = {}, flips = {}, waiting = 0, gaveUp = 0, idle = 0, total = 0 }
    local queue, qi = {}, 1
    local pending = {}  -- id -> listed entry, waiting for item info
    local retried = {}  -- id -> true once its failed load was asked for again
    local asked = {}    -- id -> times it was asked for; an item that answers but still has no info is dropped after 2
    for _, e in ipairs(listed or {}) do queue[#queue + 1] = e end

    local function age(e)
        if e.age == nil and type(ageOf) == "function" then
            local ok, a = pcall(ageOf, e)
            if ok and type(a) == "number" then e.age = a end
        end
        return e.age
    end

    local function classify(e)
        local ok, info = pcall(getInfo, e.id)
        if not ok then return end
        if not info or not info.quality or not info.classID or not info.ilvl then
            if not pending[e.id] then
                asked[e.id] = (asked[e.id] or 0) + 1
                if asked[e.id] > 2 then scan.gaveUp = scan.gaveUp + 1 return end
                scan.waiting = scan.waiting + 1
                pending[e.id] = e
                pcall(request, e.id)
            end
            return
        end
        if pending[e.id] then pending[e.id] = nil; scan.waiting = scan.waiting - 1 end
        if onItem then pcall(onItem, e, info) return end
        if (info.quality >= 2 and info.quality <= 4) and (info.classID == 2 or info.classID == 4) and P.DE.outcomes(info.quality, info.classID, info.ilvl) then
            scan.candidates[#scan.candidates + 1] = { id = e.id, name = info.name, quality = info.quality, classID = info.classID,
                ilvl = info.ilvl, price = e.price, age = age(e) }
        end
        if type(info.vendor) == "number" and info.vendor > e.price and #scan.below < BELOW_MAX then
            scan.below[#scan.below + 1] = { id = e.id, name = info.name, quality = info.quality, price = e.price, vendor = info.vendor, age = age(e) }
        end
        if type(refOf) == "function" and #scan.flips < P.Config.FLIP_MAX then
            local okR, ref = pcall(refOf, e.id)
            if okR and type(ref) == "number" and ref > 0 and e.price <= ref * P.Config.FLIP_BELOW + 1e-9 then
                scan.flips[#scan.flips + 1] = { id = e.id, name = info.name, quality = info.quality, price = e.price, market = ref,
                    vendor = info.vendor, age = age(e) }
            end
        end
    end

    scan.total = #queue
    function scan:step(budget, stop)
        local n = 0
        while qi <= #queue and n < budget and not (n > 0 and stop and stop()) do
            local e = queue[qi]
            queue[qi] = false
            qi = qi + 1
            n = n + 1
            classify(e)
        end
        if n > 0 then scan.idle = 0 end
        return #queue - qi + 1
    end

    -- success == false: the client could not load this item. The first time it is asked for again; the second time it leaves
    -- the wait queue for good.
    function scan:onInfo(id, success)
        local e = pending[id]
        if not e then return end
        if success == false then
            if not retried[id] then
                retried[id] = true
                pcall(request, id)
                return
            end
            pending[id] = nil
            scan.waiting = scan.waiting - 1
            return
        end
        pending[id] = nil
        scan.waiting = scan.waiting - 1
        queue[#queue + 1] = e
        scan.idle = 0
    end

    function scan:tick(dt)
        if qi <= #queue or scan.waiting == 0 then scan.idle = 0 return end
        scan.idle = scan.idle + (tonumber(dt) or 0)
        if scan.idle >= P.Config.DEALS_TIMEOUT_SECS then
            scan.gaveUp = scan.gaveUp + scan.waiting
            pending = {}
            scan.waiting = 0
        end
    end

    function scan:done() return qi > #queue and scan.waiting == 0 end
    function scan:left() return #queue - qi + 1 end
    return scan
end
