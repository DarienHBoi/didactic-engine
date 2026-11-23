local _, P = ...
P.Reco = {}
local R = P.Reco

-- A price after the AH cut (copper, rounded down). nil stays nil. The epsilon keeps 0.95 * 1000 from landing on 949.
function R.net(copper)
    if type(copper) ~= "number" then return nil end
    return math.floor(copper * (1 - P.Config.AH_CUT) + 1e-9)
end

-- True when `value` beats `other` by the margin: at least pct more AND at least `min` copper more.
function R.beats(value, other, margin)
    margin = margin or {}
    local pct = margin.pct or P.Config.DE_MARGIN_PCT
    local min = margin.min or P.Config.DE_MARGIN_COPPER
    return value - other >= min - 1e-9 and value >= other * (1 + pct) - 1e-9
end

-- de = expected disenchant value (copper, before the cut), ah = the item's AH price (before the cut), vendor = its vendor
-- price, bound = soulbound/BoP (cannot be listed). margin = { pct, min } (defaults in P.Config). ahNet (optional) = the AH side
-- already after the cut and weighted by its chance of selling (R.ahValue); it replaces the cut `ah` price.
-- Returns action, gain, alternative, close: "disenchant" (gain = disenchant net - other), "sell" or "vendor" (gain = that option's net
-- minus the disenchant net, negative when disenchant is a little better but under the margin) or "nodata" (no gain).
-- The third value names what it was compared with: "sell" or "vendor" for a disenchant verdict, else "disenchant".
-- close is true when neither side beats the other by the margin (percent and copper, both).
function R.decide(de, ah, vendor, bound, margin, ahNet)
    local deNet = R.net(de)
    if not deNet then return "nodata", nil, nil, false end
    local other, action
    local ahN = (not bound) and (ahNet or R.net(ah)) or nil
    if ahN then other, action = ahN, "sell" end
    if type(vendor) == "number" and (not other or vendor > other) then other, action = vendor, "vendor" end
    if not other then return "nodata", nil, nil, false end
    if R.beats(deNet, other, margin) then return "disenchant", deNet - other, action, false end
    return action, other - deNet, "disenchant", not R.beats(other, deNet, margin)
end

local function clamp01(p) return math.max(0, math.min(1, p)) end

-- ZugDAQ sells/day -> chance a listing sells: perDay / (perDay + P.Config.ZUG_SELL_HALF). 1/day = 50%, 3/day = 75%, 4/day = 80%;
-- rises with demand, never reaches 1. A chosen curve (not measured). nil for anything but a positive finite number.
function R.zugChance(perDay)
    if type(perDay) ~= "number" or not (perDay > 0) or perDay == math.huge then return nil end
    return perDay / (perDay + P.Config.ZUG_SELL_HALF)
end

-- Chance an item sells when listed: your own sell rate (deps.outcomes(id), at least P.Rate.MIN outcomes), else ZugDAQ's sells/day
-- through R.zugChance (deps.zug(id) -> { perDay }), else the sold tracker's sell-through (deps.market(id), not thin), else
-- P.Config.SELL_DEFAULT. Returns p (0..1) and "own" | "zugdaq" | "market" | "default". ZugDAQ before the tracker: owner
-- 2026-11-21 "ZugDAQ wins duplicates" (audit step 6). Every source is guarded; a failing or missing one is skipped.
function R.pSell(id, deps)
    deps = deps or {}
    if type(deps.outcomes) == "function" then
        local ok, o = pcall(deps.outcomes, id)
        if ok then
            local rate = P.Rate.of(o)
            if type(rate) == "number" then return clamp01(rate), "own" end
        end
    end
    if type(deps.zug) == "function" then
        local ok, z = pcall(deps.zug, id)
        local p = ok and type(z) == "table" and R.zugChance(z.perDay)
        if p then return clamp01(p), "zugdaq" end
    end
    if type(deps.market) == "function" then
        local ok, m = pcall(deps.market, id)
        if ok and type(m) == "table" and not m.thin and type(m.sellThrough) == "number" then return clamp01(m.sellThrough), "market" end
    end
    return P.Config.SELL_DEFAULT, "default"
end

-- Deposit lost when a listing does not sell (copper): the client's own figure (deps.deposit(id), guarded) when it has one,
-- else the vendor price x P.Config.DEPOSIT_RATE_24H (an estimate). Returns copper and "client" | "estimate".
function R.deposit(id, vendor, deps)
    deps = deps or {}
    if type(deps.deposit) == "function" then
        local ok, d = pcall(deps.deposit, id)
        if ok and type(d) == "number" and d >= 0 then return d, "client" end
    end
    return math.floor((type(vendor) == "number" and vendor or 0) * P.Config.DEPOSIT_RATE_24H + 1e-9), "estimate"
end

-- Expected copper from listing: price after the cut x p - deposit x (1 - p), rounded half up. nil without a price.
function R.ahValue(ah, p, deposit)
    local net = R.net(ah)
    if not net then return nil end
    return math.floor(net * p - (deposit or 0) * (1 - p) + 0.5)
end
