local _, S = ...
S.Profit = {}

function S.Profit.of(ask, mats)
    if type(ask) ~= "number" or type(mats) ~= "number" then return nil end
    return ask - mats
end

-- Margin over mats cost as a percent with one decimal; nil when it cannot be worked out.
function S.Profit.marginFromAsk(ask, mats)
    if type(ask) ~= "number" or type(mats) ~= "number" or mats <= 0 then return nil end
    local pct = (ask - mats) / mats * 100
    return math.floor(pct * 10 + 0.5) / 10
end

-- The auction house keeps 5% of a sale (the faction houses; the neutral one keeps more).
S.Profit.AH_CUT = 0.05

-- What lands in your pocket from selling at `sell` copper; nil when there is no usable price.
function S.Profit.afterCut(sell)
    if type(sell) ~= "number" or sell <= 0 then return nil end
    return math.floor(sell * (1 - S.Profit.AH_CUT))
end

-- Reselling a crafted item: {sell, net (after the cut), profit over mats, margin %}; nil without a sale price.
function S.Profit.craft(sell, mats)
    local net = S.Profit.afterCut(sell)
    if not net then return nil end
    return { sell = sell, net = net, profit = S.Profit.of(net, mats), margin = S.Profit.marginFromAsk(net, mats) }
end
