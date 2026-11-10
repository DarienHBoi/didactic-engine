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
