local _, P = ...
P.Market = {}
local M = P.Market

-- Sold tracker (pure). Each search of a watched item is fingerprinted and compared with the previous one of the same
-- variant: a listing that is gone although it had more time left than the gap since the last scan was bought.
-- PricewatchDB.market[id] = { last = { t, sig, rows = { [key] = {q, p, band, sec, owner, hold} } },
--   other = { [sig] = { t, rows } } (baselines of the other searched variants, at most MAX_OTHER, none older than a day),
--   days = { [day] = { sold, soldN, exp, cxl, unk, scans, cmp, prices = { per-unit, at most MARKET_PRICES } } } }
-- scans = searches counted, cmp = real comparisons (a baseline and a gap over MARKET_MAX_GAP are no comparison).
-- Units everywhere (a stack of 5 sold = 5). Commodity rows (sig "c") are keyed by unit price: the client groups them by
-- price and the auctionID it shows for a group can change.

-- Time-left bands (Enum.AuctionHouseTimeLeftBand: 0 Short, 1 Medium, 2 Long, 3 VeryLong) and the least time each
-- still has (retail floors, inferred for Forever: Short under 30 min, Medium 30 min-2 h, Long 2-12 h, VeryLong over 12 h).
M.BAND_FLOOR = { [0] = 0, [1] = 1800, [2] = 7200, [3] = 43200 }
local SHORT = 1800
local MAX_OTHER = 4

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function num(v)
    v = plain(v)
    return (type(v) == "number" and v == v and v > -math.huge and v < math.huge) and v or nil
end

-- One client result row -> { q, p (per unit), band or sec, owner, hold } or nil (own listing, no count, junk).
-- byPrice (commodity rows): a row holding own units keeps the others' units (quantity - numOwnerItems); with no
-- own count it is kept whole but marked hold (not judged).
function M.fingerprint(raw, byPrice)
    if type(raw) ~= "table" then return nil end
    local q = num(raw.quantity)
    if not q or q <= 0 then return nil end
    local hold
    if plain(raw.containsOwnerItem) == true then
        if not byPrice then return nil end
        local own = num(raw.numOwnerItems)
        if own then
            q = q - own
            if q <= 0 then return nil end
        else
            hold = true
        end
    end
    local p = num(raw.unitPrice)
    if not p then
        local b = num(raw.buyoutAmount)
        if b and b > 0 then p = b / q end
    end
    local owner
    local owners = plain(raw.owners)
    if type(owners) == "table" and #owners == 1 and (num(raw.totalNumberOfOwners) or 1) == 1 then
        local o = plain(owners[1])
        if type(o) == "string" and o ~= "" then owner = o end
    end
    local band = num(raw.timeLeft)
    if band and not M.BAND_FLOOR[band] then band = nil end
    return { q = q, p = p, band = band, sec = num(raw.timeLeftSeconds), owner = owner, hold = hold }
end

local function n2s(v)
    if type(v) ~= "number" then return "-" end
    if v == math.floor(v) then return string.format("%d", v) end
    return tostring(v)
end

-- auctionID, else seller:count:price (never the time left: it changes between scans); by price for commodity rows.
function M.key(raw, f, byPrice)
    if byPrice then return "p:" .. n2s(f.p) end
    local aid = type(raw) == "table" and num(raw.auctionID)
    if aid then return aid end
    return tostring(f.owner or "?") .. ":" .. n2s(f.q) .. ":" .. n2s(f.p)
end

local function lower(a, b)
    if a == nil then return b end
    if b == nil then return a end
    return math.min(a, b)
end

-- Result rows -> map key -> fingerprint, the cheapest MARKET_MAX_ROWS only. Returns the map, its size, the price of the
-- dearest kept row when rows were cut (a row dearer than that may still be listed), the number of usable rows read,
-- and the price of the dearest kept row. byPrice: rows at one unit price are summed into one.
function M.rowsFrom(list, byPrice)
    local fs, total = {}, 0
    local groups = {}
    for _, raw in ipairs(type(list) == "table" and list or {}) do
        local f = M.fingerprint(raw, byPrice)
        if f then
            total = total + 1
            if byPrice then
                local k = M.key(raw, f, true)
                local g = groups[k]
                if not g then
                    g = { k = k, f = f }
                    groups[k] = g
                    fs[#fs + 1] = g
                else
                    local a = g.f
                    a.q = a.q + f.q
                    a.sec, a.band = lower(a.sec, f.sec), lower(a.band, f.band)
                    if a.owner ~= f.owner then a.owner = nil end
                    a.hold = a.hold or f.hold
                end
            else
                fs[#fs + 1] = { raw = raw, f = f }
            end
        end
    end
    table.sort(fs, function(a, b) return (a.f.p or math.huge) < (b.f.p or math.huge) end)
    local map, n, top = {}, 0, nil
    for i = 1, math.min(#fs, P.Config.MARKET_MAX_ROWS) do
        local k = fs[i].k or M.key(fs[i].raw, fs[i].f)
        if map[k] then
            local j = 2
            while map[k .. "#" .. j] do j = j + 1 end
            k = k .. "#" .. j
        end
        map[k] = fs[i].f
        n = n + 1
        top = fs[i].f.p or top
    end
    local cut = #fs > n and fs[n] and fs[n].f.p or nil
    return map, n, cut, total, top
end

-- The least time a row still had at the last scan, and whether it was nearly out (Short).
local function floorOf(f)
    if f.sec then return f.sec, f.sec < SHORT end
    if f.band then return M.BAND_FLOOR[f.band], f.band == 0 end
    return 0, false
end

-- Compare two scans `gap` seconds apart: { sold, soldN, prices, exp, cxl, unk } in units.
-- Gone with more time left than the gap: sold. Gone while nearly out: expired. Otherwise unknown.
-- Gone + a new row by the same seller with the same count at another price: cancelled and reposted.
-- A gap over MARKET_MAX_GAP: everything gone is unknown. cut (from rowsFrom): rows at or above it are not judged.
function M.diff(last, now, gap, cut)
    local d = { sold = 0, soldN = 0, prices = {}, exp = 0, cxl = 0, unk = 0 }
    last, now = last or {}, now or {}
    local fresh = {}
    for k, f in pairs(now) do if last[k] == nil then fresh[#fresh + 1] = f end end
    local usedFresh = {}
    local function sold(units, p)
        d.sold = d.sold + units
        d.soldN = d.soldN + 1
        if p then d.prices[#d.prices + 1] = p end
    end
    local keys = {}
    for k in pairs(last) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local f, n = last[k], now[k]
        local floor, short = floorOf(f)
        local inTime = gap <= P.Config.MARKET_MAX_GAP and gap < floor
        if f.hold or (n and n.hold) then
            -- own units mixed in with no own count: not judged
        elseif not n and cut and (f.p == nil or f.p >= cut) then
            -- pushed out of the kept rows by cheaper ones (or past a partial result's last row): may still be listed
        elseif n then
            if n.q < f.q then
                local units = f.q - n.q
                if inTime then sold(units, f.p) else d.unk = d.unk + units end
            end
        else
            local repost
            if f.owner then
                for i, nf in ipairs(fresh) do
                    if not usedFresh[i] and nf.owner == f.owner and nf.q == f.q and nf.p ~= f.p then
                        repost = i
                        break
                    end
                end
            end
            if repost then
                usedFresh[repost] = true
                d.cxl = d.cxl + f.q
            elseif gap > P.Config.MARKET_MAX_GAP then
                d.unk = d.unk + f.q
            elseif inTime then
                sold(f.q, f.p)
            elseif short then
                d.exp = d.exp + f.q
            else
                d.unk = d.unk + f.q
            end
        end
    end
    return d
end

local function dayRow(e, day)
    local r = e.days[day]
    if not r then
        r = { sold = 0, soldN = 0, exp = 0, cxl = 0, unk = 0, scans = 0, cmp = 0, prices = {} }
        e.days[day] = r
    end
    return r
end

-- The baseline for variant sig: e.last when it is that variant, else the one kept aside in e.other (and e.last goes
-- aside in its place). Drops kept baselines older than MARKET_MAX_GAP and keeps at most MAX_OTHER.
local function baseline(e, sig, t)
    local last = e.last
    if type(last) == "table" and last.sig ~= sig then
        e.other = type(e.other) == "table" and e.other or {}
        e.other[tostring(last.sig)] = { t = last.t, rows = last.rows }
        last = e.other[tostring(sig)]
        e.other[tostring(sig)] = nil
        if type(last) == "table" then last.sig = sig else last = nil end
    end
    if type(e.other) == "table" then
        local keep = {}
        for k, o in pairs(e.other) do
            if type(o) == "table" and type(o.t) == "number" and t - o.t <= P.Config.MARKET_MAX_GAP then
                keep[#keep + 1] = { k = k, t = o.t }
            else
                e.other[k] = nil
            end
        end
        table.sort(keep, function(a, b) return a.t > b.t end)
        for i = MAX_OTHER + 1, #keep do e.other[keep[i].k] = nil end
        if next(e.other) == nil then e.other = nil end
    end
    return last
end

-- One search result of a watched item, at time t (seconds) on scan day `day`.
-- A partial result is used only when it already has MARKET_MAX_ROWS usable rows (a price-sorted search: its cheapest
-- rows are all there; rows past its dearest are not judged). An empty result is skipped: the client sometimes
-- answers a search with nothing although there are listings.
-- sig names the searched variant (item level, suffix, or "c" for a commodity): each variant has its own baseline.
-- Returns the diff against the previous scan (nil when nothing was recorded).
function M.record(db, id, list, t, day, full, sig)
    if type(db) ~= "table" or type(id) ~= "number" or type(t) ~= "number" or type(day) ~= "number" then return nil end
    if type(list) ~= "table" or list[1] == nil then return nil end
    local rows, _, cut, total, top = M.rowsFrom(list, sig == "c")
    if full ~= true then
        if total < P.Config.MARKET_MAX_ROWS or not top then return nil end
        cut = top
    end
    db.market = db.market or {}
    local e = db.market[id]
    if not e then e = { days = {} }; db.market[id] = e end
    local last = baseline(e, sig, t)
    local d
    local r = dayRow(e, day)
    if last and type(last.t) == "number" and t >= last.t then
        local gap = t - last.t
        d = M.diff(last.rows, rows, gap, cut)
        r.sold, r.soldN = r.sold + d.sold, (r.soldN or 0) + d.soldN
        r.exp, r.cxl, r.unk = r.exp + d.exp, r.cxl + d.cxl, r.unk + d.unk
        for _, p in ipairs(d.prices) do
            if #r.prices < P.Config.MARKET_PRICES then r.prices[#r.prices + 1] = p end
        end
        if gap >= P.Config.MARKET_MIN_GAP then
            r.scans = r.scans + 1
            if gap <= P.Config.MARKET_MAX_GAP then r.cmp = (tonumber(r.cmp) or 0) + 1 end
        end
    else
        d = M.diff(nil, rows, 0)
        r.scans = r.scans + 1
    end
    e.last = { t = t, rows = rows, sig = sig }
    return d
end

-- Drops day rows older than MARKET_KEEP_DAYS, items with no day rows, then the least recently scanned past MARKET_MAX_ITEMS.
function M.prune(db, today)
    if type(db) ~= "table" or type(db.market) ~= "table" or type(today) ~= "number" then return end
    local cut = today - P.Config.MARKET_KEEP_DAYS
    local list = {}
    for id, e in pairs(db.market) do
        if type(e) ~= "table" or type(e.days) ~= "table" then
            db.market[id] = nil
        else
            for d in pairs(e.days) do if type(d) ~= "number" or d <= cut then e.days[d] = nil end end
            if next(e.days) == nil then db.market[id] = nil
            else list[#list + 1] = { id = id, t = type(e.last) == "table" and tonumber(e.last.t) or 0 } end
        end
    end
    if #list <= P.Config.MARKET_MAX_ITEMS then return end
    table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
    for i = 1, #list - P.Config.MARKET_MAX_ITEMS do db.market[list[i].id] = nil end
end

function M.median(list)
    local s = {}
    for _, v in ipairs(list or {}) do if type(v) == "number" then s[#s + 1] = v end end
    if #s == 0 then return nil end
    table.sort(s)
    local m = math.floor((#s + 1) / 2)
    if #s % 2 == 1 then return s[m] end
    return (s[m] + s[m + 1]) / 2
end

-- Rough sold/day from the stored daily listed counts (fallback when tracking is thin): the sum of drops between
-- consecutive days, over the number of such day pairs, within MARKET_DAYS. New posts hide sales; expiries and cancels
-- count as sales. nil when there is no pair.
function M.rough(item, today)
    local days = type(item) == "table" and item.days
    if type(days) ~= "table" or type(today) ~= "number" then return nil end
    local drop, pairsN = 0, 0
    for d = today - P.Config.MARKET_DAYS + 1, today do
        local a, b = days[d - 1], days[d]
        local qa, qb = type(a) == "table" and tonumber(a.qty), type(b) == "table" and tonumber(b.qty)
        if qa and qb then
            pairsN = pairsN + 1
            if qa > qb then drop = drop + (qa - qb) end
        end
    end
    if pairsN == 0 then return nil end
    return drop / pairsN
end

-- Everything the views show for one item over the last MARKET_DAYS:
-- { scans, cmp, days, sold, exp, cxl, unk, perDay, sellThrough, sellsAt, thin, rough }.
-- Only days with a real comparison count (a day row saved before cmp existed counts its scans as comparisons);
-- thin = fewer than MARKET_MIN_SCANS comparisons.
function M.summary(db, id, today)
    local s = { scans = 0, cmp = 0, days = 0, sold = 0, exp = 0, cxl = 0, unk = 0, thin = true }
    local e = type(db) == "table" and type(db.market) == "table" and db.market[id]
    local prices = {}
    if type(e) == "table" and type(e.days) == "table" and type(today) == "number" then
        for d = today - P.Config.MARKET_DAYS + 1, today do
            local r = e.days[d]
            local scans = type(r) == "table" and tonumber(r.scans) or 0
            local cmp = type(r) == "table" and (tonumber(r.cmp) or (r.cmp == nil and scans)) or 0
            if scans > 0 then s.scans = s.scans + scans end
            if cmp > 0 then
                s.days = s.days + 1
                s.cmp = s.cmp + cmp
                s.sold = s.sold + (tonumber(r.sold) or 0)
                s.exp = s.exp + (tonumber(r.exp) or 0)
                s.cxl = s.cxl + (tonumber(r.cxl) or 0)
                s.unk = s.unk + (tonumber(r.unk) or 0)
                for _, p in ipairs(type(r.prices) == "table" and r.prices or {}) do prices[#prices + 1] = p end
            end
        end
    end
    s.thin = s.cmp < P.Config.MARKET_MIN_SCANS
    if s.days > 0 then s.perDay = s.sold / s.days end
    if s.sold + s.exp > 0 then s.sellThrough = s.sold / (s.sold + s.exp) end
    s.sellsAt = M.median(prices)
    if s.thin then
        s.rough = M.rough(type(db) == "table" and type(db.items) == "table" and db.items[id] or nil, today)
    end
    return s
end

-- "0.3", "2.7", "12"
function M.perDayText(x)
    if type(x) ~= "number" then return "-" end
    if x >= 10 then return tostring(math.floor(x + 0.5)) end
    local r = math.floor(x * 10 + 0.5) / 10
    if r == math.floor(r) then return tostring(math.floor(r)) end
    return tostring(r)
end

-- The tooltip text: "~3/day sold, 69% sell-through", the rough fallback, or nil when there is nothing to say.
function M.text(s)
    if type(s) ~= "table" then return nil end
    if not s.thin and type(s.perDay) == "number" then
        local t = "~" .. M.perDayText(s.perDay) .. "/day sold"
        if type(s.sellThrough) == "number" then t = t .. ", " .. math.floor(s.sellThrough * 100 + 0.5) .. "% sell-through" end
        return t
    end
    if type(s.rough) == "number" then return "~" .. M.perDayText(s.rough) .. "/day (rough, from listed counts)" end
    return nil
end
