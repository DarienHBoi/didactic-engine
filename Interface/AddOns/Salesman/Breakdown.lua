local _, S = ...
S.Breakdown = {}

-- Per-reagent unit, line and stack prices. lookup(itemID) -> {copper=number|nil}. total is nil if any price is unknown.
function S.Breakdown.compute(recipe, lookup, stackSize)
    local lines, total = {}, 0
    for _, r in ipairs(recipe.reagents) do
        local p = r[1] and lookup(r[1]) or {}
        local unit = p.copper
        if unit ~= nil and unit <= 0 then unit = nil end
        local line = unit and unit * r[2] or nil
        lines[#lines + 1] = {
            name = r.name or ("item " .. tostring(r[1])), count = r[2], unit = unit, line = line,
            stack = unit and unit * stackSize or nil, link = r.link, itemID = r[1],
        }
        if line == nil then total = nil elseif total then total = total + line end
    end
    return { lines = lines, total = total, stackSize = stackSize }
end

function S.Breakdown.text(b)
    local out = {}
    for _, l in ipairs(b.lines) do
        out[#out + 1] = string.format("%s x%s: %s ea = %s  (stack of %d: %s)", l.name, tostring(l.count),
            S.Money.format(l.unit), S.Money.format(l.line), b.stackSize, S.Money.format(l.stack))
    end
    out[#out + 1] = "Total mats: " .. S.Money.format(b.total)
    return table.concat(out, "\n")
end
