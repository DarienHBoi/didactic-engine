local _, S = ...
S.Trend = {}

-- How hot an item is on the AH, from Auctionator's per-day history (one entry per scan day:
-- lowest price seen and the most listed). The newest day is compared with the average of up to
-- BASE_DAYS earlier scan days. Price up or listings drying up = hot; price down or a flood = cold.
local BASE_DAYS = 7

local function round(x) return math.floor(x + 0.5) end

-- Heat from the price change percent p and the listings change percent q (nil when unknown).
local function heatOf(p, q)
    if (p >= 10 and (q == nil or q <= 25)) or (q and q <= -30 and p > -10) then
        return "hot"
    elseif (p <= -10 and (q == nil or q >= -25)) or (q and q >= 50 and p < 10) then
        return "cold"
    end
    return "steady"
end

-- Pricewatch's shared value for an item (market against usual), when that addon is present and has 2+ stored days. Guarded.
local function pricewatchTrend(itemID)
    if type(itemID) ~= "number" or type(Pricewatch_Value) ~= "function" then return nil end
    local ok, v = pcall(Pricewatch_Value, itemID)
    if ok and type(v) == "table" and type(v.trendPct) == "number" and type(v.usual) == "number"
        and type(v.days) == "number" and v.days >= 2 then
        return v
    end
    return nil
end

-- itemID (optional): with Pricewatch present, its trend (market against usual) replaces the price change.
function S.Trend.compute(history, itemID)
    local days = {}
    for _, e in ipairs(history or {}) do
        local d = tonumber(e.rawDay)
        if d and type(e.minSeen) == "number" and e.minSeen > 0 then
            days[#days + 1] = { d = d, p = e.minSeen, q = type(e.available) == "number" and e.available or nil }
        end
    end
    if #days == 0 then return nil end
    table.sort(days, function(a, b) return a.d > b.d end)
    local last = days[1]
    local t = { price = last.p, qty = last.q, days = 1 }
    local sp, np, sq, nq = 0, 0, 0, 0
    for i = 2, math.min(#days, BASE_DAYS + 1) do
        sp, np = sp + days[i].p, np + 1
        if days[i].q then sq, nq = sq + days[i].q, nq + 1 end
    end
    if np == 0 then t.heat = "new" return t end
    t.days = np + 1
    t.basePrice = round(sp / np)
    t.pricePct = round((last.p - t.basePrice) / t.basePrice * 100)
    if nq > 0 then t.baseQty = round(sq / nq) end
    if last.q and t.baseQty and t.baseQty > 0 then
        t.qtyPct = round((last.q - t.baseQty) / t.baseQty * 100)
    end
    local pw = pricewatchTrend(itemID)
    if pw then
        t.pricePct, t.basePrice, t.days = pw.trendPct, pw.usual, pw.days
    end
    t.heat = heatOf(t.pricePct, t.qtyPct)
    return t
end

local LABEL = { hot = "|cffff7020Hot|r", cold = "|cff60a0ffCold|r", steady = "|cffc0c0c0Steady|r", new = "|cff808080New|r" }

-- Short text for the board column: heat word and the price change.
function S.Trend.label(t)
    if not t then return "-" end
    if not t.pricePct then return LABEL[t.heat] or "-" end
    return LABEL[t.heat] .. " " .. (t.pricePct > 0 and "+" or "") .. t.pricePct .. "%"
end
