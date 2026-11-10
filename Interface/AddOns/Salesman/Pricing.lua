local _, S = ...
S.Pricing = {}

function S.Pricing.matsCost(reagents, lookup, staleSecs)
    staleSecs = staleSecs or 86400
    if #reagents == 0 then return { state = "unknown" } end
    local total, stale = 0, false
    for _, r in ipairs(reagents) do
        if r[1] == false or type(r[2]) ~= "number" or r[2] <= 0 then return { state = "unknown" } end
        local p = lookup(r[1])
        if not p or p.copper == nil or p.copper <= 0 then return { state = "unknown" } end
        total = total + p.copper * r[2]
        if p.ageSecs and p.ageSecs >= staleSecs then stale = true end
    end
    return { state = stale and "stale" or "ok", copper = total }
end

-- Plain decimal only ("15", "12.5"); anything else is nil. Clamped to 0..1000.
function S.Pricing.parseMargin(text)
    if type(text) ~= "string" or not text:match("^%d+%.?%d*$") then return nil end
    local n = tonumber(text)
    if not n then return nil end
    if n > 1000 then n = 1000 end
    return n
end

-- "You bring the mats": only the margin part, at least 1 silver.
function S.Pricing.labour(cost, marginPct)
    if not cost or cost.copper == nil or cost.copper <= 0 then return nil end
    local m = tonumber(marginPct) or 0
    if m ~= m or m == math.huge or m < 0 then m = 0 end
    if m > 1000 then m = 1000 end
    local raw = math.floor(cost.copper * m / 100 * 1e6 + 0.5) / 1e6
    return math.max(100, S.Money.roundUpSilver(raw))
end

function S.Pricing.suggest(cost, marginPct)
    if not cost or cost.copper == nil or cost.copper <= 0 then return nil end
    local m = tonumber(marginPct) or 0
    if m ~= m or m == math.huge or m < 0 then m = 0 end
    if m > 1000 then m = 1000 end
    local raw = cost.copper * (100 + m) / 100
    return S.Money.roundUpSilver(math.floor(raw * 1e6 + 0.5) / 1e6)
end
