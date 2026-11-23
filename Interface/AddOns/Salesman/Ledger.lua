local _, S = ...
S.Ledger = {}
S.Ledger.MAX = 200

local function valid(v)
    return type(v) == "number" and v == v and v > 0 and v < math.huge
end

local function book(db)
    db.ledger = db.ledger or { entries = {}, total = 0, count = 0, byKey = {} }
    return db.ledger
end

-- Per-item totals ({count, total} by recipe key). A ledger saved before they existed is rebuilt from its entries once.
local function perItem(b)
    if not b.byKey then
        b.byKey = {}
        for _, e in ipairs(b.entries or {}) do
            if e.key and valid(e.copper) then
                local r = b.byKey[e.key] or { count = 0, total = 0 }
                r.count, r.total = r.count + 1, r.total + e.copper
                b.byKey[e.key] = r
            end
        end
    end
    return b.byKey
end

-- Adds money earned (copper). Bad amounts are ignored. The running total and count survive the entry cap.
function S.Ledger.add(db, name, copper, key, now, source)
    if type(db) ~= "table" or not valid(copper) then return false end
    local b = book(db)
    local pk = perItem(b)
    b.entries[#b.entries + 1] = { t = now or 0, name = name, copper = copper, key = key, source = source }
    while #b.entries > S.Ledger.MAX do table.remove(b.entries, 1) end
    b.total = b.total + copper
    b.count = b.count + 1
    if key then
        local r = pk[key] or { count = 0, total = 0 }
        r.count, r.total = r.count + 1, r.total + copper
        pk[key] = r
    end
    return true
end

-- Sales count and gold earned for one recipe key (0, 0 when none).
function S.Ledger.byKey(db, key)
    if not (db and db.ledger and key) then return 0, 0 end
    local r = perItem(db.ledger)[key]
    if not r then return 0, 0 end
    return r.count, r.total
end

-- The n biggest earners as {key, count, total}, most gold first.
function S.Ledger.top(db, n)
    local out = {}
    if db and db.ledger then
        for key, r in pairs(perItem(db.ledger)) do out[#out + 1] = { key = key, count = r.count, total = r.total } end
    end
    table.sort(out, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.key < b.key end)
    while #out > (n or 10) do table.remove(out) end
    return out
end

function S.Ledger.total(db) return db and db.ledger and db.ledger.total or 0 end
function S.Ledger.count(db) return db and db.ledger and db.ledger.count or 0 end

function S.Ledger.recent(db, n)
    local out = {}
    local list = db and db.ledger and db.ledger.entries or {}
    for i = #list, math.max(1, #list - (n or 10) + 1), -1 do out[#out + 1] = list[i] end
    return out
end

local function short(n) return (tostring(n):gsub("%-.*$", "")):lower() end

-- A customer by exact name, else by name without realm (case-insensitive).
function S.Ledger.findCustomer(db, partner)
    if type(partner) ~= "string" or partner == "" or not db.customers then return nil end
    if db.customers[partner] then return partner end
    local want = short(partner)
    for name in pairs(db.customers) do
        if short(name) == want then return name end
    end
    return nil
end

-- A finished trade: gold received from partner. Only customers are counted. The gold you really got is what is
-- logged (not the quote); the customer is marked done and the quote is used up.
function S.Ledger.recordTrade(db, partner, copper, now)
    local name = S.Ledger.findCustomer(db, partner)
    local res = { matched = name ~= nil, counted = false, name = name, copper = valid(copper) and copper or 0 }
    if not name or not valid(copper) then return res end
    local c = db.customers[name]
    local key = c.quote and c.quote.key
    if key then
        db.sales = db.sales or {}
        local list = db.sales[key] or {}
        S.Sales.add(list, copper, now)
        db.sales[key] = list
        c.quote = nil
    end
    c.status = "done"
    res.counted = S.Ledger.add(db, name, copper, key, now, "trade")
    return res
end

-- A sale typed in by hand for a customer. key is the enchant (optional). Marks the customer done and uses up the quote.
function S.Ledger.logSale(db, name, key, copper, now)
    local c = type(db) == "table" and db.customers and db.customers[name]
    if not c or not valid(copper) then return false end
    if key then
        db.sales = db.sales or {}
        local list = db.sales[key] or {}
        S.Sales.add(list, copper, now)
        db.sales[key] = list
    end
    c.quote = nil
    c.status = "done"
    return S.Ledger.add(db, name, copper, key, now, "manual")
end
