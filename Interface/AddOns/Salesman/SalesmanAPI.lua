local _, S = ...
S.API = {}
local A = S.API
local DAY = 86400

-- Read-only view of Salesman for other addons (Pricewatch), keyed by itemID. Pure functions take their data
-- explicitly; the global SalesmanAPI at the bottom feeds them the saved data and never raises.

local function resultID(r)
    return type(r) == "table" and S.Prices.itemIDFromLink(r.resultLink) or nil
end

-- { lowercase item name -> itemID } from the recipes that make an item.
function A.nameIndex(recipes)
    local idx = {}
    for _, r in ipairs(recipes or {}) do
        local id = resultID(r)
        local name = id and (type(r.resultLink) == "string" and r.resultLink:match("%[(.-)%]") or r.name)
        if id and type(name) == "string" then idx[name:lower()] = id end
    end
    return idx
end

-- A copy of a recipe's saved reagents ({ {id, qty, name=...} }) as { {id, qty} }; rows without a whole positive id and qty are left out.
local function reagentsOf(r)
    local out = {}
    for _, g in ipairs(type(r.reagents) == "table" and r.reagents or {}) do
        local id, qty = type(g) == "table" and g[1], type(g) == "table" and g[2]
        if type(id) == "number" and id >= 1 and id == math.floor(id) and type(qty) == "number" and qty >= 1 and qty == math.floor(qty) then
            out[#out + 1] = { id = id, qty = qty }
        end
    end
    return out
end

-- Crafted items: { itemID, name, profession, resultLink, mats (copper or nil), reagents = { {id, qty} } }. deps.cost(recipe) as in Board.
function A.recipes(recipes, deps)
    local out, seen = {}, {}
    for _, r in ipairs(recipes or {}) do
        local id = resultID(r)
        if id and not seen[id] then
            seen[id] = true
            local mats
            if deps and deps.cost then
                local ok, c = pcall(deps.cost, r)
                if ok and type(c) == "table" and (c.state == "ok" or c.state == "stale") then mats = c.copper end
            end
            out[#out + 1] = { itemID = id, name = r.name, profession = S.Recipes.professionOf(r),
                              resultLink = r.resultLink, mats = mats, reagents = reagentsOf(r) }
        end
    end
    return out
end

-- Salesman's sell / net / mats / profit row for one crafted item, or nil when no recipe makes it.
function A.profit(recipes, deps, itemID)
    for _, r in ipairs(recipes or {}) do
        if resultID(r) == itemID then
            local row = S.Board.rank({ r }, deps)[1]
            if not row then return nil end
            return { sell = row.sell, net = row.net, mats = row.mats, profit = row.profit, margin = row.margin,
                     status = row.status, ageSecs = row.ageSecs }
        end
    end
    return nil
end

-- AH sales of one item from the mail log, oldest first: { time (when the mail was first seen), copper (gold
-- received, deposit excluded), units, perUnit, assumed (stack size unknown: one unit assumed), invoice }.
function A.sales(log, itemID, index)
    local out = {}
    if not (log and log.entries and itemID) then return out end
    for _, e in ipairs(log.entries) do
        if e.kind == "ah_sold" then
            local id = e.itemID
            if id == nil and type(e.item) == "string" and index then id = index[e.item:lower()] end
            if id == itemID then
                local dep = e.invoice and type(e.invoice.deposit) == "number" and e.invoice.deposit or 0
                local copper = math.max(0, (type(e.money) == "number" and e.money or 0) - dep)
                local known = type(e.units) == "number" and e.units > 0
                out[#out + 1] = { time = e.seen, copper = copper, units = known and e.units or 1,
                                  perUnit = known and math.floor(copper / e.units + 0.5) or copper,
                                  assumed = not known, invoice = e.invoice }
            end
        end
    end
    table.sort(out, function(a, b) return (a.time or 0) < (b.time or 0) end)
    return out
end

local OUTCOME_DAYS, UNITS_DAYS = 30, 14

local function entryID(e, index)
    local id = e.itemID
    if id == nil and type(e.item) == "string" and index then id = index[e.item:lower()] end
    return id
end

-- Personal sale outcomes for every item in ONE pass over the mail log: { byID = { [itemID] = { sold, expired, cancelled,
-- units14 (units sold in the last 14 days), lastSold (time of the newest sale, any age), avgSold (per-unit average of what
-- the sales within 30 days brought in, after the returned deposit) } } }. Sales, expiries and cancellations older than 30
-- days are not counted. avgPaid is not logged yet (AH purchases are not parsed), so it is left out.
function A.tally(log, index, now)
    local by = {}
    if not (log and log.entries) then return { byID = by } end
    now = now or time()
    local sums = {}
    for _, e in ipairs(log.entries) do
        local id = entryID(e, index)
        if id and type(e.seen) == "number" then
            local r = by[id]
            local function rec()
                if not r then r = { sold = 0, expired = 0, cancelled = 0, units14 = 0 }; by[id] = r; sums[id] = { copper = 0, n = 0 } end
                return r
            end
            local age = now - e.seen
            if e.kind == "ah_sold" then
                rec()
                if not r.lastSold or e.seen > r.lastSold then r.lastSold = e.seen end
                if age <= OUTCOME_DAYS * DAY then
                    r.sold = r.sold + 1
                    local dep = e.invoice and type(e.invoice.deposit) == "number" and e.invoice.deposit or 0
                    local copper = math.max(0, (type(e.money) == "number" and e.money or 0) - dep)
                    local units = (type(e.units) == "number" and e.units > 0) and e.units or 1
                    local s = sums[id]
                    s.copper, s.n = s.copper + copper / units, s.n + 1
                    if age <= UNITS_DAYS * DAY then r.units14 = r.units14 + units end
                end
            elseif e.kind == "ah_return" and age <= OUTCOME_DAYS * DAY then
                local what = S.MailLog.returnKind(e.subject)
                if what then rec(); r[what] = r[what] + 1 end
            end
        end
    end
    for id, r in pairs(by) do
        local s = sums[id]
        if s and s.n > 0 then r.avgSold = math.floor(s.copper / s.n + 0.5) end
    end
    return { byID = by }
end

-- The tally is rebuilt only when the log changed (a mail was added or aged out) or the day changed.
local tallyMemo = { log = nil, sig = nil, value = nil }
function A.tallyCached(log, index, now)
    now = now or time()
    local n = log and log.entries and #log.entries or 0
    local sig = n .. ":" .. tostring(n > 0 and log.entries[1].seen or 0) .. ":" .. tostring(n > 0 and log.entries[n].seen or 0)
        .. ":" .. math.floor(now / DAY)
    if tallyMemo.log ~= log or tallyMemo.sig ~= sig then
        tallyMemo.log, tallyMemo.sig, tallyMemo.value = log, sig, A.tally(log, index, now)
    end
    return tallyMemo.value
end

-- { sold, expired, cancelled, units14, lastSold, avgSold } for one item, or nil when the log has nothing for it.
function A.outcomes(log, itemID, index, now)
    if not (log and log.entries and itemID) then return nil end
    return A.tally(log, index, now).byID[itemID]
end

-- Item ids that have ever had an AH sale in the log, ascending (Pricewatch watches them).
function A.soldIDs(log, index)
    local seen, out = {}, {}
    for _, e in ipairs(log and log.entries or {}) do
        if e.kind == "ah_sold" then
            local id = entryID(e, index)
            if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
        end
    end
    table.sort(out)
    return out
end

-- Service earnings by UTC day, ascending: { day (start, seconds), copper, count }.
function A.ledger(db)
    local by, out = {}, {}
    for _, e in ipairs(db and db.ledger and db.ledger.entries or {}) do
        if type(e.copper) == "number" and e.copper > 0 and type(e.t) == "number" then
            local d = e.t - e.t % DAY
            local r = by[d]
            if not r then r = { day = d, copper = 0, count = 0 }; by[d] = r; out[#out + 1] = r end
            r.copper, r.count = r.copper + e.copper, r.count + 1
        end
    end
    table.sort(out, function(a, b) return a.day < b.day end)
    return out
end

-- Item id for an item name from the saved recipes (used to tag mail-log sales).
function A.itemIDByName(name)
    if type(name) ~= "string" or not (S.DB.char and S.DB.char.recipes) then return nil end
    return A.nameIndex(S.DB.char.recipes)[name:lower()]
end

local function liveDeps()
    return {
        cost = function(r) return S.Pricing.matsCostFarmed(r.reagents, S.Prices.lookup, 86400) end,
        auction = S.Prices.auction, staleSecs = 86400,
    }
end

local function safe(fn, empty)
    return function(...)
        local ok, r = pcall(fn, ...)
        if ok and r ~= nil then return r end
        return empty
    end
end

SalesmanAPI = {
    version = 1,
    sales = safe(function(itemID)
        return A.sales(S.DB.char.mailLog, itemID, A.nameIndex(S.DB.char.recipes))
    end, {}),
    recipes = safe(function() return A.recipes(S.DB.char.recipes, liveDeps()) end, {}),
    profit = safe(function(itemID) return A.profit(S.DB.char.recipes, liveDeps(), itemID) end, nil),
    ledger = safe(function() return A.ledger(S.DB.char) end, {}),
    outcomes = safe(function(itemID)
        local o = A.tallyCached(S.DB.char.mailLog, A.nameIndex(S.DB.char.recipes)).byID[itemID]
        if not o then return nil end
        return { sold = o.sold, expired = o.expired, cancelled = o.cancelled, units14 = o.units14, lastSold = o.lastSold, avgSold = o.avgSold }
    end, nil),
    soldItemIDs = safe(function() return A.soldIDs(S.DB.char.mailLog, A.nameIndex(S.DB.char.recipes)) end, {}),
}
