local _, P = ...
P.Graph = {}
local G = P.Graph
G.GAP_DAYS = 3      -- scan days further apart than this are not joined by a line
G.HOVER_RADIUS = 14 -- pixels
G.BAR_SHARE = 0.2   -- the supply bars use at most this share of the plot height

local KEYS = { "market", "listings", "sales", "de", "zug" }

local function niceTicks(lo, hi, n)
    local out = {}
    for i = 0, n - 1 do out[#out + 1] = lo + (hi - lo) * i / (n - 1) end
    return out
end

-- Pixel layout of a series set in a w x h box (origin top-left, y grows downward).
-- Result: market/listings/sales/de = lists of {x, y, day, value, ...}; segments.market/de = line pieces
-- {x1, y1, x2, y2}; yTicks = {{y, value}}; xTicks = {{x, day}}; w, h.
function G.layout(s, w, h)
    local lay = { market = {}, listings = {}, sales = {}, de = {}, zug = {}, segments = { market = {}, de = {}, zug = {} },
                  yTicks = {}, xTicks = {}, bars = {}, w = w, h = h }
    if not (s and s.hasData and s.minV and s.maxV and s.minDay and s.maxDay) then return lay end
    local lo, hi = s.minV, s.maxV
    local pad = math.max((hi - lo) * 0.08, hi * 0.03, 1)
    lo, hi = math.max(0, lo - pad), hi + pad
    local span = s.maxDay - s.minDay
    local function X(day) return span > 0 and (day - s.minDay) / span * w or w / 2 end
    local function Y(v) return h - (v - lo) / (hi - lo) * h end
    for _, key in ipairs(KEYS) do
        for _, p in ipairs(s[key] or {}) do
            local q = { x = X(p.day), y = Y(p.value), day = p.day, value = p.value, assumed = p.assumed, qty = p.qty, hr = p.hr, series = key }
            lay[key][#lay[key] + 1] = q
        end
    end
    for _, key in ipairs({ "market", "de", "zug" }) do
        local pts = lay[key]
        for i = 2, #pts do
            if pts[i].day - pts[i - 1].day <= G.GAP_DAYS then
                lay.segments[key][#lay.segments[key] + 1] = { x1 = pts[i - 1].x, y1 = pts[i - 1].y, x2 = pts[i].x, y2 = pts[i].y }
            end
        end
    end
    -- Supply: one thin bar per market day that has a listed quantity, the biggest filling the bottom BAR_SHARE of the plot.
    local maxQ = 0
    for _, p in ipairs(lay.market) do if type(p.qty) == "number" and p.qty > maxQ then maxQ = p.qty end end
    if maxQ > 0 then
        local cap = h * G.BAR_SHARE
        for _, p in ipairs(lay.market) do
            if type(p.qty) == "number" and p.qty > 0 then
                lay.bars[#lay.bars + 1] = { x = p.x, h = math.max(1, p.qty / maxQ * cap), day = p.day, qty = p.qty }
            end
        end
    end
    for _, v in ipairs(niceTicks(lo, hi, 5)) do lay.yTicks[#lay.yTicks + 1] = { y = Y(v), value = v } end
    local nx = span > 0 and 4 or 1
    for _, d in ipairs(niceTicks(s.minDay, s.maxDay, nx + 1 > 1 and nx + 1 or 2)) do
        local day = math.floor(d + 0.5)
        lay.xTicks[#lay.xTicks + 1] = { x = X(day), day = day }
    end
    return lay
end

-- The scan-time note for a market point's hover: "scanned about 14:00", or "scan hour unknown" for a backfilled day.
function G.scanText(p)
    if type(p) ~= "table" or p.series ~= "market" then return nil end
    if type(p.hr) == "number" then return ("scanned about %02d:00"):format(p.hr) end
    return "scan hour unknown"
end

-- The point nearest to (x, y) within HOVER_RADIUS, or nil. Sales and listings win ties over the market line.
function G.hover(lay, x, y)
    local best, bestD
    for _, key in ipairs({ "sales", "listings", "de", "market" }) do
        for _, p in ipairs(lay[key] or {}) do
            local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
            if d <= G.HOVER_RADIUS ^ 2 and (not bestD or d < bestD) then best, bestD = p, d end
        end
    end
    return best
end

-- Axis labels for tick values: rounded to the largest unit ("12g"); when two neighbours would read the same, every label
-- is written out in full instead.
function G.axisLabels(values)
    local out = {}
    for i, v in ipairs(values or {}) do out[i] = P.Money.short(math.floor(v + 0.5)) end
    for i = 2, #out do
        if out[i] == out[i - 1] then
            for j, v in ipairs(values) do out[j] = P.Money.format(math.floor(v + 0.5)) end
            break
        end
    end
    return out
end

-- The legend: only the series that have points. { { key, label } } in drawing order; "supply" when any day has a quantity,
-- "salesAssumed" (stack unknown) apart from "sales".
local LEGEND_LABEL = { market = "Market low", listings = "Your listings", sales = "Your sales",
    salesAssumed = "Sale, stack unknown", de = "Disenchant (estimate)", supply = "Supply (listed)",
    zug = "Server price (ZugHistory)" }
function G.legend(s)
    local out = {}
    if type(s) ~= "table" then return out end
    local function add(key) out[#out + 1] = { key = key, label = LEGEND_LABEL[key] } end
    local hasQty = false
    for _, p in ipairs(s.market or {}) do if type(p.qty) == "number" and p.qty > 0 then hasQty = true end end
    local plain, assumed = false, false
    for _, p in ipairs(s.sales or {}) do if p.assumed then assumed = true else plain = true end end
    if #(s.market or {}) > 0 then add("market") end
    if #(s.listings or {}) > 0 then add("listings") end
    if plain then add("sales") end
    if assumed then add("salesAssumed") end
    if #(s.de or {}) > 0 then add("de") end
    if #(s.zug or {}) > 0 then add("zug") end
    if hasQty then add("supply") end
    return out
end
