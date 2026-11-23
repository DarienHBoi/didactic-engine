local _, P = ...
P.Store = {}
local St = P.Store

-- PricewatchDB: { v = 1, items = { [itemID] = { name, seen, days = { [day] = {lo, hi, qty, hr} }, posts = { {t, price, qty} } } } }
-- A day with no scan has no entry (unknown, never zero).
function St.init(db)
    db = db or {}
    db.v = 1
    db.items = db.items or {}
    return db
end

local function pos(v) return type(v) == "number" and v == v and v > 0 and v < math.huge end

local function item(db, id)
    local it = db.items[id]
    if not it then it = { days = {}, posts = {}, seen = 0 }; db.items[id] = it end
    return it
end

-- Copies Auctionator's history rows ({rawDay, minSeen, maxSeen, available}) and posting rows
-- ({rawDay = time, price, quantity}) for one item. hour = the hour of this scan, kept only for today's row (backfilled days have no known hour).
function St.record(db, id, rows, posts, today, hour)
    if type(db) ~= "table" or type(db.items) ~= "table" or type(id) ~= "number" then return end
    local it
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        local d = tonumber(type(r) == "table" and r.rawDay)
        local lo = type(r) == "table" and (r.minSeen or r.maxSeen)
        if d and pos(lo) then
            it = it or item(db, id)
            local hi = pos(r.maxSeen) and r.maxSeen or lo
            local qty = pos(r.available) and r.available or nil
            local old = it.days[d]
            if not old or old.lo ~= lo or old.hi ~= hi or old.qty ~= qty then
                -- The scan hour is only known for today's scan; a backfilled day was scanned some other time.
                it.days[d] = { lo = lo, hi = hi, qty = qty, hr = (d == today and hour) or (old and old.hr) or nil }
            end
        end
    end
    -- Posting records: Auctionator merges records over time, so adding rows to ours would count a post twice. Instead,
    -- every row of ours inside the span Auctionator still holds (from its oldest record on) is replaced by its rows.
    -- Older rows, which Auctionator has dropped, are kept. A missing quantity counts as 1 here and in the stored row.
    local fresh, minT = {}, nil
    for _, r in ipairs(type(posts) == "table" and posts or {}) do
        if type(r) == "table" and pos(r.price) and type(r.rawDay) == "number" then
            fresh[#fresh + 1] = { t = r.rawDay, price = r.price, qty = pos(r.quantity) and r.quantity or 1 }
            if not minT or r.rawDay < minT then minT = r.rawDay end
        end
    end
    if #fresh > 0 then
        it = it or item(db, id)
        local kept = {}
        for _, p in ipairs(it.posts) do
            if p.t < minT then kept[#kept + 1] = p end
        end
        for _, p in ipairs(fresh) do kept[#kept + 1] = p end
        it.posts = kept
    end
    if not it then return end
    table.sort(it.posts, function(a, b) return a.t < b.t end)
    while #it.posts > P.Config.MAX_POSTS do table.remove(it.posts, 1) end
    if type(today) == "number" then
        it.seen = math.max(it.seen or 0, today)
        local cut = today - P.Config.MAX_DAYS
        for d in pairs(it.days) do if d <= cut then it.days[d] = nil end end
    end
end

function St.setName(db, id, name)
    if type(name) == "string" and name ~= "" and db and db.items and db.items[id] then db.items[id].name = name end
end

-- Days of an item as an ascending list of {day, lo, hi, qty, hr}.
function St.daysList(it)
    local out = {}
    for d, r in pairs(it and it.days or {}) do out[#out + 1] = { day = d, lo = r.lo, hi = r.hi, qty = r.qty, hr = r.hr } end
    table.sort(out, function(a, b) return a.day < b.day end)
    return out
end

-- Drops items not seen for DROP_UNSEEN_DAYS, then the least recently seen ones past MAX_ITEMS.
function St.prune(db, today)
    if type(db) ~= "table" or type(db.items) ~= "table" or type(today) ~= "number" then return end
    for id, it in pairs(db.items) do
        if (it.seen or 0) < today - P.Config.DROP_UNSEEN_DAYS then db.items[id] = nil end
    end
    local list = {}
    for id, it in pairs(db.items) do list[#list + 1] = { id = id, seen = it.seen or 0 } end
    if #list <= P.Config.MAX_ITEMS then return end
    table.sort(list, function(a, b) if a.seen ~= b.seen then return a.seen < b.seen end return a.id < b.id end)
    for i = 1, #list - P.Config.MAX_ITEMS do db.items[list[i].id] = nil end
end
