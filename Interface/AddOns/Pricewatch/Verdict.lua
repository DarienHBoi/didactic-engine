local _, P = ...
P.Verdict = {}
local V = P.Verdict

local function priceAt(list, day, tolerance)
    -- Newest scan day at or before `day`, no more than `tolerance` days earlier; nil when none.
    for i = #list, 1, -1 do
        if list[i].day <= day then
            return (day - list[i].day <= tolerance) and list[i].lo or nil, list[i].day
        end
    end
    return nil
end

-- Numbers shown under the graph. item = store entry, sales = SalesmanAPI.sales list.
-- opts = { e0, de = disenchant value now (copper) }.
function V.figures(item, sales, today, opts)
    opts = opts or {}
    local f = { sales = 0, scanDays = 0, de = opts.de }
    local list = P.Store.daysList(item)
    f.scanDays = #list
    local last = list[#list]
    if last then
        f.now, f.nowDay, f.qty = last.lo, last.day, last.qty
        f.age = today - last.day
    end
    local seven = priceAt(list, today - 7, 3)
    local thirty = priceAt(list, today - 30, 3)
    f.d7, f.d30 = seven, thirty
    local total, n, recent = 0, 0, 0
    for _, s in ipairs(sales or {}) do
        if type(s.perUnit) == "number" then
            total, n = total + s.perUnit, n + 1
            local day = P.Days.dayOf(s.time, opts.e0)
            if day and day > today - 28 then recent = recent + 1 end
        end
    end
    f.sales = n
    f.avgSale = n > 0 and math.floor(total / n + 0.5) or nil
    f.sellsPerWeek = recent / 4
    return f
end

V.NODATA = "No price data"

-- The verdict line of the item window, built the same way as the tooltip's (one rule: P.Tip.evaluate): text, r, g, b.
-- Items that cannot be disenchanted get "Sell on AH" when a price is stored, else "No price data".
function V.line(id, today)
    local info = P.Adapters.itemInfo(id)
    local deps = P.Tip.deps()
    deps.price = function(x) return (P.Value.price(x, today)) end
    local r = P.Mod.on("disenchant") and P.Tip.evaluate(id, info.bindType == 1, deps) or nil -- off: no Disenchant verdict in the window
    if r then return P.Tip.format(r) end
    if P.Value.price(id, today) then return "Sell on AH", 1, 1, 1 end
    return V.NODATA, 0.6, 0.6, 0.6
end
