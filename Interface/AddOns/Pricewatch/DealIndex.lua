local _, P = ...
-- Deals rework (2026-11-21, docs/deals-rework-2026-11-21.md, rulings R1-R5): the cached deal index and the shared DE memo.
-- PricewatchDB.dealIndex = { v, key, built (unix time), n, complete, items = { [id] = item } } with item fields
--   q quality, c classID, l item level, v vendor price, n name (may be nil: read for painted rows only),
--   r flip reference (Deals.flipRef), d sold per day, p chance a listing sells, s demand source ("zugdaq" | "market").
-- The index changes only when its key changes (ZugDAQ snapshot, ZugHistory file, Enchanting skill, DELog samples, scan day), so a
-- /reload with nothing new reuses it. Building is time-sliced (Deals.newScan's queue: wait, retry once, give up). The views
-- (Deals.lua) are filters over it against the current buy prices and never ask the client or the price sources.
P.DealIndex = {}
local X = P.DealIndex

local VERSION = 1
local MEMO_SECS = 60 -- wall clock (time()); never GetTime, which advances per call in the test fakes
X.STEP = 150         -- items per frame at most
X.STEP_MS = 2        -- and stop early past this many milliseconds (when debugprofilestop exists)

local function now() return type(time) == "function" and time() or 0 end
local function num(v)
    if type(v) ~= "number" then return nil end
    if type(issecretvalue) == "function" then
        local ok, s = pcall(issecretvalue, v)
        if not ok or s then return nil end
    end
    return v
end

-- --------------------------------------------------------------------------------------------------------- DE memo (R2)
-- The DE.unitValue memo shared by Deals, Live lots and the AH rows. Dropped by X.dropMemo (Recalculate, Scan AH, AH open/close,
-- index completion) and after MEMO_SECS, so new mat prices reach every path within a minute and all three see one number.
local memo, memoAt, memoGen = nil, nil, 0
function X.memo()
    local t = now()
    if not memo or not memoAt or t - memoAt >= MEMO_SECS or t < memoAt then memo, memoAt, memoGen = {}, t, memoGen + 1 end
    return memo
end
function X.dropMemo() memo, memoAt = nil, nil end
function X.memoGen() return memoGen end

-- ------------------------------------------------------------------------------------------------------------ sources
-- The game sources. Tests pass their own table with the same functions.
local function zugData()
    local d = ZugDAQ_AppData
    if type(d) == "table" and d.version then return d end
    return nil
end
X.game = {
    zug = function() if P.Mod and not P.Mod.on("zugdaq") then return nil end return zugData() end,
    zh = function()
        local d = ZugHistory_Data
        return type(d) == "table" and { made = num(d.made), newest = num(d.newest) } or nil
    end,
    zhItems = function()
        local db = ZugHistoryDB
        return type(db) == "table" and type(db.items) == "table" and db.items or nil
    end,
    skill = function() local ok, s = pcall(P.Adapters.enchantingSkill) return ok and num(s) or nil end,
    delog = function()
        local de = type(P.db) == "table" and type(P.db.de) == "table" and P.db.de or nil
        return de and num(de.total) or 0
    end,
    day = function() return P.Days.dayOf(now(), P.Days.epoch0()) end,
    client = function(id)
        local ok, i = pcall(P.Adapters.itemInfo, id)
        if ok and type(i) == "table" and i.name and i.quality and i.classID and i.ilvl then return i end
        return nil
    end,
    request = function(id) pcall(P.Adapters.requestItem, id) end,
    ref = function(id)
        local v = P.Value.get(id)
        local z = P.Adapters.zug(id)
        local h = P.Adapters.zugHistory(id)
        return P.Deals.flipRef(v and v.market, z and z.market, h and (h.n or 0) >= P.Config.ZUGH_MIN_N and h.median or nil)
    end,
    demand = function(id, deps) return P.Deals.demand(id, deps) end,
    demandDeps = function() return P.Tip.deps() end,
    listed = function() return P.Adapters.listedItems() end,
}

-- R1: the index key. Every part read guarded; a missing part is "-".
function X.key(src)
    src = src or X.game
    local function part(fn)
        local ok, a, b = pcall(fn)
        if not ok then return "-" end
        return a, b
    end
    local z = part(src.zug)
    local h = part(src.zh)
    local zs = type(z) == "table" and (tostring(num(z.made) or "-") .. ":" .. tostring(num(z.snapshot) or "-")) or "-"
    local hs = type(h) == "table" and (tostring(h.made or "-") .. ":" .. tostring(h.newest or "-")) or "-"
    return ("v%d|z%s|h%s|s%s|d%s|t%s"):format(VERSION, zs, hs, tostring(part(src.skill) or "-"), tostring(part(src.delog) or "-"),
        tostring(part(src.day) or "-"))
end

-- R3: the buy prices. listed = Adapters.listedItems() ({ id, price }), zug = ZugDAQ_AppData. Auctionator first; ZugDAQ's lowest
-- for the items Auctionator does not have (its age = whole days since the ZugDAQ snapshot). { map = { [id] = entry }, list, n }.
function X.prices(listed, zug)
    local map, list = {}, {}
    for _, e in ipairs(listed or {}) do
        if type(e.id) == "number" and type(e.price) == "number" and e.price > 0 and not map[e.id] then
            local p = { id = e.id, price = e.price, src = "auctionator" }
            map[e.id] = p
            list[#list + 1] = p
        end
    end
    if type(zug) == "table" and type(zug.prices) == "table" then
        local stamp = num(zug.snapshot) or num(zug.made)
        local age = stamp and math.floor(math.max(0, now() - stamp) / 86400) or nil
        for id, row in pairs(zug.prices) do
            local lowest = type(row) == "table" and num(row[3]) or nil
            if type(id) == "number" and not map[id] and lowest and lowest > 0 and lowest < math.huge then
                local p = { id = id, price = lowest, src = "zugdaq", age = age }
                map[id] = p
                list[#list + 1] = p
            end
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return { map = map, list = list, n = #list }
end

-- R4: an item's facts without asking the client: the index (any key), else ZugHistoryDB.items ({ q, l, v, c }).
local function cachedInfo(id, old, zh)
    local o = old and old[id]
    if type(o) == "table" and o.q and o.c and o.l then
        return { name = o.n, quality = o.q, classID = o.c, ilvl = o.l, vendor = o.v }
    end
    local z = zh and zh[id]
    if type(z) == "table" and num(z.q) and num(z.c) and num(z.l) then
        return { quality = z.q, classID = z.c, ilvl = z.l, vendor = num(z.v) }
    end
    return nil
end

-- A build job over `ids` (a list of item ids). old = the current index items (facts reused). opts.into = an items table to fill
-- (a top-up of the current index); else a fresh one, swapped in by X.finish. Counters for tests: job.clientCalls, job.cached.
function X.newBuild(ids, src, old, opts)
    src = src or X.game
    opts = opts or {}
    local items = opts.into or {}
    local okZ, zh = pcall(src.zhItems or function() end)
    zh = okZ and type(zh) == "table" and zh or nil
    local okD, deps = pcall(src.demandDeps or function() end)
    deps = okD and deps or nil
    local job = { items = items, key = opts.key, topUp = opts.into ~= nil, ids = ids or {}, clientCalls = 0, cached = 0, stepped = {} }
    local listed = {}
    for _, id in ipairs(ids or {}) do listed[#listed + 1] = { id = id, price = 0 } end
    local function getInfo(id)
        local c = cachedInfo(id, old, zh)
        if c then job.cached = job.cached + 1 return c end
        job.clientCalls = job.clientCalls + 1
        return src.client(id)
    end
    local function onItem(e, info)
        local id = e.id
        local prev = old and old[id]
        local it = { q = info.quality, c = info.classID, l = info.ilvl, v = num(info.vendor),
            n = (type(info.name) == "string" and info.name ~= "" and info.name) or (type(prev) == "table" and prev.n) or nil }
        local okR, r = pcall(src.ref, id)
        it.r = okR and num(r) or nil
        if it.r then
            local okM, d = pcall(src.demand, id, deps)
            if okM and type(d) == "table" and num(d.perDay) then it.d, it.p, it.s = d.perDay, num(d.p), d.source end
        end
        items[id] = it
    end
    job.scan = P.Deals.newScan(listed, getInfo, src.request, nil, nil, onItem)
    function job:step(budget, stop)
        local before = self.scan:left()
        local left = self.scan:step(budget or X.STEP, stop)
        self.stepped[#self.stepped + 1] = before - left
        return left
    end
    function job:onInfo(id, success) self.scan:onInfo(id, success) end
    function job:tick(dt) self.scan:tick(dt) end
    function job:done() return self.scan:done() end
    function job:progress()
        local total = math.max(1, self.scan.total)
        return math.max(0, math.min(1, (total - self.scan:left() - self.scan.waiting) / total))
    end
    return job
end

-- The universe: every item with a buy price (Auctionator's plain ids and ZugDAQ's price ids), sorted.
function X.universe(prices)
    local ids = {}
    for _, p in ipairs(prices and prices.list or {}) do ids[#ids + 1] = p.id end
    return ids
end

-- Is the stored index usable for this key?
function X.warm(db, key)
    local idx = type(db) == "table" and db.dealIndex or nil
    return type(idx) == "table" and idx.v == VERSION and idx.complete == true and idx.key == key and type(idx.items) == "table"
end

-- The current index items (complete or not), or nil.
function X.items(db)
    local idx = type(db) == "table" and db.dealIndex or nil
    return type(idx) == "table" and type(idx.items) == "table" and idx.items or nil
end

-- What needs doing: nil when the stored index fits this key and covers every priced item; else a job (a full rebuild when the
-- key changed, else a top-up of the item ids missing from it). X.job holds the running one; a second ensure with the same key
-- keeps it.
X.job = nil
function X.ensure(db, prices, src)
    src = src or X.game
    if type(db) ~= "table" then return nil end
    local key = X.key(src)
    if X.job and not X.job:done() and X.job.key == key then return X.job end
    local ids = X.universe(prices)
    if X.warm(db, key) then
        local missing = {}
        local miss = type(db.dealIndex.miss) == "table" and db.dealIndex.miss or {}
        for _, id in ipairs(ids) do
            if db.dealIndex.items[id] == nil and (tonumber(miss[id]) or 0) < X.MAX_MISSES then missing[#missing + 1] = id end
        end
        if #missing == 0 then X.job = nil return nil end
        X.job = X.newBuild(missing, src, db.dealIndex.items, { into = db.dealIndex.items, key = key })
        return X.job
    end
    X.job = X.newBuild(ids, src, X.items(db), { key = key })
    return X.job
end

-- A finished job: a full build replaces the stored index; a top-up already wrote into it. Returns true when the index changed.
-- db.dealIndex.miss[id] counts the builds that gave up on an item (the client never answered); at X.MAX_MISSES ensure stops
-- topping it up until the key changes (a full build starts a fresh count).
X.MAX_MISSES = 2
function X.finish(db, job)
    job = job or X.job
    if not job or not job:done() or type(db) ~= "table" then return false end
    local miss
    if not job.topUp then
        local n = 0
        for _ in pairs(job.items) do n = n + 1 end
        db.dealIndex = { v = VERSION, key = job.key, built = now(), n = n, complete = true, items = job.items }
        miss = {}
    else
        local n = 0
        for _ in pairs(db.dealIndex.items) do n = n + 1 end
        db.dealIndex.n = n
        miss = type(db.dealIndex.miss) == "table" and db.dealIndex.miss or {}
    end
    for _, id in ipairs(job.ids or {}) do
        if db.dealIndex.items[id] == nil then miss[id] = (tonumber(miss[id]) or 0) + 1 else miss[id] = nil end
    end
    db.dealIndex.miss = miss
    if X.job == job then X.job = nil end
    X.dropMemo()
    return true
end

-- A time budget for one frame: stop() is true past STEP_MS milliseconds (no clock = never; the item count still bounds it).
function X.stopper()
    if type(debugprofilestop) ~= "function" then return nil end
    local ok, t0 = pcall(debugprofilestop)
    if not ok or type(t0) ~= "number" then return nil end
    return function()
        local ok2, t = pcall(debugprofilestop)
        return ok2 and type(t) == "number" and t - t0 >= X.STEP_MS
    end
end

-- The header line (design 5): where the data comes from.
-- "ZugDAQ snapshot 21:10, 9400 items, index built 21:12" or "Rebuilding the deal index 40% (3 waiting for item info)".
function X.sourceText(db, zug, job, dateFn)
    dateFn = dateFn or (type(date) == "function" and date) or nil
    local function hm(t) return (t and dateFn) and dateFn("%H:%M", t) or "?" end
    local idx = type(db) == "table" and db.dealIndex or nil
    local parts = {}
    local stamp = type(zug) == "table" and (num(zug.snapshot) or num(zug.made)) or nil
    parts[#parts + 1] = stamp and ("ZugDAQ snapshot " .. hm(stamp)) or "No ZugDAQ data (Auctionator and own scans only)"
    if job and not job:done() then
        local pct = math.floor(job:progress() * 100 + 0.5)
        local w = job.scan.waiting > 0 and (", " .. job.scan.waiting .. " waiting for item info") or ""
        parts[#parts + 1] = (job.topUp and "adding new items " or "rebuilding the deal index ") .. pct .. "%" .. w
    elseif type(idx) == "table" and idx.complete then
        parts[#parts + 1] = (idx.n or 0) .. " items, index built " .. hm(idx.built)
    end
    return table.concat(parts, ", ")
end
