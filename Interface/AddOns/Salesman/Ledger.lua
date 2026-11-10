local _, S = ...
S.Ledger = {}
S.Ledger.MAX = 200

local function valid(v)
    return type(v) == "number" and v == v and v > 0 and v < math.huge
end

local function book(db)
    db.ledger = db.ledger or { entries = {}, total = 0, count = 0 }
    return db.ledger
end

-- Adds money earned (copper). Bad amounts are ignored. The running total and count survive the entry cap.
function S.Ledger.add(db, name, copper, key, now, source)
    if type(db) ~= "table" or not valid(copper) then return false end
    local b = book(db)
    b.entries[#b.entries + 1] = { t = now or 0, name = name, copper = copper, key = key, source = source }
    while #b.entries > S.Ledger.MAX do table.remove(b.entries, 1) end
    b.total = b.total + copper
    b.count = b.count + 1
    return true
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
