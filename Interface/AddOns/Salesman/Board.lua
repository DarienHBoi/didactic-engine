local _, S = ...
S.Board = {}

-- "Best crafts": every recipe that makes an item, with what it sells for on the AH and the profit after the cut.
-- deps = { cost = fn(recipe) -> matsCost result, auction = fn(itemID) -> {copper, ageSecs}, staleSecs = 86400 }
-- Row status: "ok" (fresh price, profit known), "stale" (price a day old or more), "noprice", "nomats".
local ORDER = { ok = 1, stale = 2, nomats = 3, noprice = 4 }

local function rowFor(r, deps, staleSecs)
    local id = S.Prices.itemIDFromLink(r.resultLink)
    if not id then return nil end
    local okC, c = pcall(deps.cost, r)
    if not okC or type(c) ~= "table" then c = {} end
    local mats = (c.state == "ok" or c.state == "stale") and c.copper or nil
    local okA, ah = pcall(deps.auction, id)
    if not okA or type(ah) ~= "table" then ah = {} end
    local res = S.Profit.craft(ah.copper, mats)
    local row = { recipe = r, itemID = id, mats = mats, matsOld = c.state == "stale", ageSecs = res and ah.ageSecs or nil }
    if mats and type(c.missing) == "number" and c.missing > 0 then row.farmed = c.missing end
    if res then
        row.sell, row.net, row.profit, row.margin = res.sell, res.net, res.profit, res.margin
    end
    if deps.history then
        local okH, h = pcall(deps.history, id)
        if okH then
            local okT, t = pcall(S.Trend.compute, h, id)
            if okT then row.trend = t end
        end
    end
    if deps.outcomes then
        local okO, o = pcall(deps.outcomes, id)
        if okO and type(o) == "table" then
            row.outcomes = o
            row.rate = S.Board.sellRate(o)
        end
    end
    -- What a craft is worth in expectation: profit x sale rate; without a rate, the profit as it is.
    if row.profit then
        row.expected = row.rate and math.floor(row.profit * row.rate + 0.5) or row.profit
    end
    if deps.sold then
        local okS, n, _, avg = pcall(deps.sold, r)
        if okS and type(n) == "number" and n > 0 then row.soldCount, row.soldAvg = n, avg end
    end
    if not res then row.status = "noprice"
    elseif (ah.ageSecs or math.huge) >= staleSecs then row.status = "stale"
    elseif mats == nil then row.status = "nomats"
    else row.status = "ok" end
    return row
end

local function before(a, b, key)
    local oa, ob = ORDER[a.status], ORDER[b.status]
    if oa ~= ob then return oa < ob end
    local pa, pb = a[key], b[key]
    if pa ~= nil and pb ~= nil and pa ~= pb then return pa > pb end
    if (pa ~= nil) ~= (pb ~= nil) then return pa ~= nil end
    return (a.recipe.name or "") < (b.recipe.name or "")
end

function S.Board.rank(recipes, deps)
    local out, seen = {}, {}
    local staleSecs = deps.staleSecs or 86400
    for _, r in ipairs(recipes or {}) do
        local k = r.key or r.name
        if not seen[k] then
            local row = rowFor(r, deps, staleSecs)
            if row then seen[k] = true; out[#out + 1] = row end
        end
    end
    local key = deps.sort == "expected" and "expected" or "profit"
    table.sort(out, function(a, b) return before(a, b, key) end)
    return out
end

-- The personal sale rate: sold / (sold + expired + cancelled) over the last 30 days, and the outcome count.
-- nil rate when there are fewer than SELLS_MIN outcomes.
S.Board.SELLS_MIN, S.Board.SELLS_GOOD, S.Board.SELLS_OK = 5, 0.30, 0.10
function S.Board.sellRate(o)
    if type(o) ~= "table" then return nil, 0 end
    local sold, total = tonumber(o.sold) or 0, (tonumber(o.sold) or 0) + (tonumber(o.expired) or 0) + (tonumber(o.cancelled) or 0)
    if total < S.Board.SELLS_MIN then return nil, total end
    return sold / total, total
end

-- The Sells cell: { text = "78%", colour = green | yellow | grey, rate }. Green from 30%, yellow from 10%, grey below and for a
-- dash when there are too few outcomes ("?" instead in the Expected sort, where such a row is counted at its plain profit).
function S.Board.sellsCell(o, expectedMode)
    local rate = S.Board.sellRate(o)
    if not rate then return { text = expectedMode and "?" or "-", colour = "grey" } end
    local colour = rate >= S.Board.SELLS_GOOD - 1e-9 and "green" or (rate >= S.Board.SELLS_OK - 1e-9 and "yellow" or "grey")
    return { text = math.floor(rate * 100 + 0.5) .. "%", colour = colour, rate = rate }
end

-- Hover text for the Sells cell.
function S.Board.sellsTip(o)
    if type(o) ~= "table" then return "No sales or expiries logged in the last 30 days (open your mailbox to log them)." end
    local perDay = (tonumber(o.units14) or 0) / 14
    return ("%d sold, %d expired, %d cancelled (30 days), %s/day"):format(o.sold or 0, o.expired or 0, o.cancelled or 0,
        tostring(math.floor(perDay * 10 + 0.5) / 10))
end

-- Ranked rows only, unless showAll: then the unranked ones follow at the bottom.
function S.Board.visible(rows, showAll)
    local out = {}
    for _, row in ipairs(rows or {}) do
        if showAll or row.status == "ok" then out[#out + 1] = row end
    end
    return out
end

function S.Board.summary(rows)
    local s = { ranked = 0, hidden = 0, profitable = 0 }
    for _, row in ipairs(rows or {}) do
        if row.status == "ok" then
            s.ranked = s.ranked + 1
            if row.profit and row.profit > 0 then s.profitable = s.profitable + 1 end
        else
            s.hidden = s.hidden + 1
        end
    end
    return s
end

-- The professions present on the board, sorted by name (for the filter button).
function S.Board.professions(rows)
    local seen, out = {}, {}
    for _, row in ipairs(rows or {}) do
        local p = S.Recipes.professionOf(row.recipe)
        if p and not seen[p] then seen[p] = true; out[#out + 1] = p end
    end
    table.sort(out)
    return out
end

-- Rows of one profession; nil keeps all.
function S.Board.filter(rows, prof)
    local out = {}
    for _, row in ipairs(rows or {}) do
        if prof == nil or S.Recipes.professionOf(row.recipe) == prof then out[#out + 1] = row end
    end
    return out
end

-- "Sold on AH: N, avg X" from the mail log (what you really got per sale, after the cut), or nil.
function S.Board.soldText(row)
    if not (row and row.soldCount) then return nil end
    return "Sold on AH: " .. row.soldCount .. ", avg " .. S.Money.format(row.soldAvg or 0)
end
