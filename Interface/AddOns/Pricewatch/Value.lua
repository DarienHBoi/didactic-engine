local _, P = ...
P.Value = {}
local V = P.Value

local function round(x) return math.floor(x + 0.5) end

-- One shared set of figures per item, from the Pricewatch day store (copper per unit):
--   now      the newest day's lowest price
--   market   weighted mean of the daily lowest prices over the last MARKET_DAYS days, weight 0.5^(age / MARKET_HALF_LIFE),
--            so one cheap listing only partly moves it (equals now when there is one day)
--   usual    median of every stored day's lowest price
--   age      days since the newest scan
--   trendPct market against usual, in percent
--   days     number of stored days
-- nil when there is nothing stored for the item. today = scan day number (default: today).
function V.get(id, today)
    if type(id) ~= "number" or type(P.db) ~= "table" or type(P.db.items) ~= "table" then return nil end
    local it = P.db.items[id]
    local list = it and P.Store.daysList(it) or {}
    if #list == 0 then return nil end
    today = today or P.Days.dayOf(time(), P.Days.epoch0())
    local newest = list[#list]
    local num, den = 0, 0
    for _, d in ipairs(list) do
        local age = math.max(0, today - d.day)
        if age < P.Config.MARKET_DAYS then
            local w = 0.5 ^ (age / P.Config.MARKET_HALF_LIFE)
            num, den = num + w * d.lo, den + w
        end
    end
    local market = den > 0 and round(num / den) or newest.lo
    local los = {}
    for i, d in ipairs(list) do los[i] = d.lo end
    table.sort(los)
    local n = #los
    local usual = (n % 2 == 1) and los[(n + 1) / 2] or round((los[n / 2] + los[n / 2 + 1]) / 2)
    return { now = newest.lo, market = market, usual = usual, age = math.max(0, today - newest.day),
        trendPct = round((market - usual) / usual * 100), days = n }
end

-- Market for display: the Pricewatch figures (V.get) with source = "scan"; with no stored history, ZugDAQ's market price as a
-- fallback { market, trendPct (vs its 7-day average, when it has one), age, source = "zugdaq" }. nil when neither has the item.
-- V.get itself stays Pricewatch-only: Today and the item window need real scan days.
function V.market(id, today)
    local v = V.get(id, today)
    local function zh()
        local h = P.Adapters.zugHistory(id)
        if h and (h.n or 0) >= P.Config.ZUGH_MIN_N and h.median > 0 then return h end
    end
    if v then
        local out = {}
        for k, x in pairs(v) do out[k] = x end
        out.source = "scan"
        -- thin own history: ZugHistory's server-wide 30-day median is the better Usual
        if (v.days or 0) < P.Config.ZUGH_THIN_DAYS then
            local h = zh()
            if h then out.usual, out.usualSource, out.trendPct = h.median, "zughistory", round((v.market - h.median) / h.median * 100) end
        end
        return out
    end
    local z = P.Adapters.zug(id)
    if not z then
        local h = zh()
        if not h then return nil end
        return { market = h.median, usual = h.median, age = h.age, source = "zughistory", low = h.low, high = h.high }
    end
    return { market = z.market, age = z.age, source = "zugdaq",
        trendPct = z.avg7 and round((z.market - z.avg7) / z.avg7 * 100) or nil }
end

-- The price one decision uses, and its age in scan days (nil age = unknown). Disenchant mats are priced at Market (the
-- Pricewatch store, else Auctionator's last scan); anything else at Auctionator's last scan, else its newest stored day. Last
-- resort for both: ZugDAQ's market price (when the module is on and its data is fresh), with its age in days.
local function priceOld(id, today)
    local v = V.get(id, today)
    local function zug()
        local z = P.Adapters.zug(id)
        if z then return z.market, z.age end
        local h = P.Adapters.zugHistory(id)
        if h and (h.n or 0) >= P.Config.ZUGH_MIN_N and h.median > 0 then return h.median, h.age end
        return nil, nil
    end
    if P.DE.MATS[id] then
        local p, age = V.matPrice(id, today)
        if not p then return nil, nil end
        local t = V.matTrend(id, today, p)
        return t.valued or p, age
    end
    local price, age = P.Adapters.auctionPrice(id)
    if price then return price, age end
    if v then return v.now, v.age end
    return zug()
end

-- Disenchant mat prices (owner 2026-11-21: "whichever is most accurate, sanity check between them"). list = { { source, price,
-- age }, ... } in priority order (ZugDAQ, scan, Auctionator, ZugHistory). 3+ prices: the median; 2: the higher-priority one when
-- they agree within P.Config.MAT_AGREE, else the lower (conservative when buying to disenchant); 1: it. Returns price, age,
-- { source, n, agree } or nil.
function V.matConsensus(list)
    local ok = {}
    for _, e in ipairs(list or {}) do if type(e.price) == "number" and e.price > 0 then ok[#ok + 1] = e end end
    local n = #ok
    if n == 0 then return nil end
    if n == 1 then return ok[1].price, ok[1].age, { source = ok[1].source, n = 1, agree = true } end
    if n == 2 then
        local a, b = ok[1], ok[2]
        local lo, hi = math.min(a.price, b.price), math.max(a.price, b.price)
        if hi <= lo * (1 + P.Config.MAT_AGREE) then return a.price, a.age, { source = a.source, n = 2, agree = true } end
        local low = a.price <= b.price and a or b
        return low.price, low.age, { source = low.source, n = 2, agree = false }
    end
    local sorted = {}
    for i, e in ipairs(ok) do sorted[i] = e end
    table.sort(sorted, function(x, y) return x.price < y.price end)
    local price, src
    if n % 2 == 1 then src = sorted[(n + 1) / 2]; price = src.price
    else src = sorted[n / 2]; price = round((sorted[n / 2].price + sorted[n / 2 + 1].price) / 2) end
    local age = 0
    for _, e in ipairs(ok) do if type(e.age) == "number" and e.age > age then age = e.age end end
    return price, age, { source = "median", n = n, agree = true }
end

local function matSources(id, today)
    local list = {}
    local z = P.Adapters.zug(id)
    if z then list[#list + 1] = { source = "zugdaq", price = z.market, age = z.age } end
    local v = V.get(id, today)
    if v then list[#list + 1] = { source = "scan", price = v.market, age = v.age } end
    local ap, aa = P.Adapters.auctionPrice(id)
    if ap then list[#list + 1] = { source = "auctionator", price = ap, age = aa } end
    local h = P.Adapters.zugHistory and P.Adapters.zugHistory(id)
    if h and (h.n or 0) >= P.Config.ZUGH_MIN_N then list[#list + 1] = { source = "zughistory", price = h.median, age = h.age } end
    return list
end

function V.matPrice(id, today)
    local p, age = V.matConsensus(matSources(id, today))
    return p, age
end

-- The Pricewatch 7-day mean of a mat's daily lows (nil unless it covers P.Config.TREND_MIN_DAYS distinct days of the last 7).
local function scanAvg7(id, today)
    local it = type(P.db) == "table" and type(P.db.items) == "table" and P.db.items[id]
    if not it then return nil end
    today = today or P.Days.dayOf(time(), P.Days.epoch0())
    local sum, n = 0, 0
    for _, d in ipairs(P.Store.daysList(it)) do
        if today - d.day < 7 and today - d.day >= 0 then sum, n = sum + d.lo, n + 1 end
    end
    return n >= P.Config.TREND_MIN_DAYS and round(sum / n) or nil
end

-- Trend guard (owner 2026-11-21, corrected twice) for disenchant valuation. now = the mat's consensus price (V.matPrice).
-- 7-day = ZugDAQ avg7 (server-side), else ZugHistory's 7-day median or the Pricewatch 7-day mean, each only once it covers
-- TREND_MIN_DAYS (5) distinct days. A 7-day outside [0.5x, 2x] of now is unusable (real outliers: market 20000, avg7 361666).
-- Falling = now more than TREND_DOWN (5%) under the 7-day: valued at now * (now / 7-day) (the fall extended one more week),
-- floored at TREND_FLOOR (0.75) * now. Otherwise now; a rising price is never raised. ZugDAQ's trend field is NOT used: in
-- real data it is always 1 or nil. Returns { falling, now, avg7, source, valued, noHistory }.
function V.matTrend(id, today, now)
    now = now or V.matPrice(id, today)
    local out = { falling = false, now = now, valued = now }
    if type(now) ~= "number" or now <= 0 then return out end
    local function usable(v) return type(v) == "number" and v >= now * 0.5 and v <= now * 2 end
    local avg7, source
    local z = P.Adapters.zug(id)
    if z and usable(z.avg7) then avg7, source = z.avg7, "zugdaq" end
    if not avg7 and P.Adapters.zugHistory then
        local h = P.Adapters.zugHistory(id, 7)
        if h and (h.n or 0) >= P.Config.TREND_MIN_DAYS and usable(h.median) then avg7, source = h.median, "zughistory" end
    end
    if not avg7 then
        local s = scanAvg7(id, today)
        if usable(s) then avg7, source = s, "scan" end
    end
    if not avg7 then out.noHistory = true return out end
    out.avg7, out.source = avg7, source
    if now < avg7 * (1 - P.Config.TREND_DOWN) then
        out.falling = true
        out.valued = round(math.max(now * now / avg7, now * P.Config.TREND_FLOOR))
    end
    return out
end

local SOURCE_NAME = { zugdaq = "ZugDAQ", scan = "Pricewatch scan", auctionator = "Auctionator", zughistory = "ZugHistory", median = "median" }
-- One hover phrase on how a mat was priced, e.g. "median of 3 sources" or "ZugDAQ (2 sources agree)".
function V.matNote(id, today)
    local p, _, info = V.matConsensus(matSources(id, today))
    if not p then return "no price" end
    if info.source == "median" then return "median of " .. info.n .. " sources" end
    if info.n == 1 then return SOURCE_NAME[info.source] .. " only" end
    return SOURCE_NAME[info.source] .. (info.agree and " (2 sources agree)" or " (lower of 2 sources that disagree)")
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Audit step 5 (owner 2026-11-21): ONE ZugDAQ-first resolver. V.resolve(id, today) -> price, age, info, or nil.
-- 1. ZugDAQ market (A.zug: module on, data fresh within ZUG_STALE_DAYS); info.now = its lowest ([3]), info.usual = its avg7.
-- 2. ZugHistory median (n >= ZUGH_MIN_N), 3. own scan Market (V.get), 4. Auctionator's last scan.
-- 2-4 are a sanity band only while ZugDAQ has the item: info.outside = true when ZugDAQ is more than RESOLVE_BAND x outside
-- [band.lo, band.hi]; they never outvote it. Memoized per item for RESOLVE_MEMO_SECS (one evaluation pass); V.forget(id) and
-- V.resetMemo() invalidate. Mats keep the trend guard on top (V.resolvedPrice). V.price keeps the OLD rule until the owner
-- switches (V.setResolveUse, "/pricewatch resolve on"); while logging is on, every V.price call records items where the two
-- differ by more than RESOLVE_LOG_PCT in PricewatchDB.resolveLog (bounded, one entry per item).
local memo, memoN = {}, 0
local function clock() return type(GetTime) == "function" and GetTime() or nil end
function V.resetMemo() memo, memoN = {}, 0 end
function V.forget(id) if id ~= nil and memo[id] then memo[id] = nil end end

local function resolveFresh(id, today)
    local band = { n = 0 }
    local function add(x)
        if type(x) ~= "number" or x <= 0 then return end
        band.n = band.n + 1
        if not band.lo or x < band.lo then band.lo = x end
        if not band.hi or x > band.hi then band.hi = x end
    end
    local h = P.Adapters.zugHistory and P.Adapters.zugHistory(id)
    local zhOk = type(h) == "table" and (h.n or 0) >= P.Config.ZUGH_MIN_N and type(h.median) == "number" and h.median > 0
    local v = V.get(id, today)
    local ap, aa = P.Adapters.auctionPrice(id)
    if zhOk then add(h.median) end
    if v then add(v.market) end
    add(ap)
    local z = P.Adapters.zug(id)
    if type(z) == "table" and type(z.market) == "number" and z.market > 0 then
        local f = P.Config.RESOLVE_BAND
        local outside = band.n > 0 and (z.market > band.hi * f or z.market * f < band.lo) or false
        return z.market, z.age, { source = "zugdaq", now = z.lowest, usual = z.avg7, band = band, outside = outside }
    end
    if zhOk then return h.median, h.age, { source = "zughistory", band = band } end
    if v and type(v.market) == "number" and v.market > 0 then return v.market, v.age, { source = "scan", band = band } end
    if ap then return ap, aa, { source = "auctionator", band = band } end
    return nil
end

function V.resolve(id, today)
    if type(id) ~= "number" then return nil end
    local t = clock()
    local m = memo[id]
    if m and m.today == today and (t == nil or m.t == nil or t - m.t <= P.Config.RESOLVE_MEMO_SECS) then return m.p, m.age, m.info end
    local p, age, info = resolveFresh(id, today)
    if not m then
        memoN = memoN + 1
        if memoN > 4000 then memo, memoN = {}, 1 end
    end
    memo[id] = { p = p, age = age, info = info, t = t, today = today }
    return p, age, info
end

-- The valuation figure from the resolver, in V.price's shape (price, age): mats get the trend guard (h12b) on the resolved price.
function V.resolvedPrice(id, today)
    local p, age, info = V.resolve(id, today)
    if not p then return nil, nil end
    if P.DE.MATS[id] then
        local tr = V.matTrend(id, today, p)
        return tr.valued or p, age, info
    end
    return p, age, info
end

local function settings()
    if type(P.db) ~= "table" then return nil end
    if type(P.db.resolve) ~= "table" then P.db.resolve = {} end
    return P.db.resolve
end
function V.resolveUse()
    local s = settings()
    if s and type(s.use) == "boolean" then return s.use end
    return P.Config.RESOLVE_USE == true
end
function V.resolveLogging()
    local s = settings()
    if s and type(s.log) == "boolean" then return s.log end
    return P.Config.RESOLVE_LOG == true
end
function V.setResolveUse(on) local s = settings() if s then s.use = on and true or false end V.resetMemo() end
function V.setResolveLogging(on) local s = settings() if s then s.log = on and true or false end end

local function logDiff(id, old, new, info)
    if type(P.db) ~= "table" then return end
    local differs
    if old and new then differs = math.abs(new - old) > old * P.Config.RESOLVE_LOG_PCT
    else differs = (old ~= nil) ~= (new ~= nil) end
    local log = P.db.resolveLog
    if not differs then
        if type(log) == "table" and log[id] then log[id] = nil P.db.resolveLogN = math.max(0, (P.db.resolveLogN or 1) - 1) end
        return
    end
    if type(log) ~= "table" then log = {} P.db.resolveLog = log P.db.resolveLogN = 0 end
    if not log[id] then
        if (P.db.resolveLogN or 0) >= P.Config.RESOLVE_LOG_MAX then return end
        P.db.resolveLogN = (P.db.resolveLogN or 0) + 1
    end
    log[id] = { old = old, new = new, src = info and info.source, outside = info and info.outside or nil, t = time() }
end

-- The price one decision uses, and its age in scan days (nil age = unknown). The old rule (priceOld) until switched; see above.
function V.price(id, today)
    local use, logging = V.resolveUse(), V.resolveLogging()
    if not use and not logging then return priceOld(id, today) end
    local op, oa = priceOld(id, today)
    local np, na, info = V.resolvedPrice(id, today)
    if logging and type(id) == "number" then pcall(logDiff, id, op, np, info) end
    if use then return np, na end
    return op, oa
end

local function itemName(id)
    local ok, name = pcall(function()
        if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
        if C_Item and C_Item.GetItemInfo then return (C_Item.GetItemInfo(id)) end
    end)
    if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then return name end
    return "item " .. tostring(id)
end

-- /pricewatch resolve log: a header and the n entries with the biggest difference (one side missing first).
function V.resolveReport(n)
    local rows = {}
    local log = type(P.db) == "table" and type(P.db.resolveLog) == "table" and P.db.resolveLog or {}
    for id, e in pairs(log) do
        if type(e) == "table" then
            local r = (e.old and e.new) and math.abs(e.new - e.old) / e.old or math.huge
            rows[#rows + 1] = { id = id, e = e, r = r }
        end
    end
    table.sort(rows, function(a, b) if a.r ~= b.r then return a.r > b.r end return a.id < b.id end)
    local out = { #rows .. " items differ by more than " .. math.floor(P.Config.RESOLVE_LOG_PCT * 100 + 0.5) ..
        "% (old price -> ZugDAQ-first). Valuation uses: " .. (V.resolveUse() and "the new resolver" or "the old rule") ..
        "; logging " .. (V.resolveLogging() and "on" or "off") .. "." }
    for i = 1, math.min(n or 15, #rows) do
        local e = rows[i].e
        local old = e.old and P.Money.format(e.old) or "none"
        local new = e.new and P.Money.format(e.new) or "none"
        local pct = (e.old and e.new) and string.format("%+d%%", math.floor((e.new - e.old) / e.old * 100 + 0.5)) or "one side only"
        out[#out + 1] = itemName(rows[i].id) .. ": " .. old .. " -> " .. new .. " (" .. pct .. ", " .. tostring(e.src or "none") ..
            (e.outside and ", ZugDAQ far outside the others" or "") .. ")"
    end
    return out
end

-- For other addons (Salesman's Trend): a fresh table, or nil. Never throws.
function Pricewatch_Value(id)
    local ok, v = pcall(V.get, id)
    return ok and v or nil
end
