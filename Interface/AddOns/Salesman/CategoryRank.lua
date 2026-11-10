local _, S = ...
S.CategoryRank = {}

-- Gear families first (in this order), then oils, wands, unknown categories, then non-sellable ones.
local GEAR = { "Chest", "Bracer", "Gloves", "Boots", "Cloak", "Shield", "Two%-Handed", "One%-Handed", "Weapon", "Ring", "Neck" }
local UNKNOWN = 100
local TAIL = { ["Reagents"] = 200, ["Camping"] = 201, ["Runed Enchanting Rods"] = 202 }

function S.CategoryRank.rank(name)
    if type(name) ~= "string" then return UNKNOWN end
    if TAIL[name] then return TAIL[name] end
    if name == "Wizard Oils" then return 50 end
    if name == "Wands" then return 60 end
    for i, key in ipairs(GEAR) do
        if name:find(key) then return i end
    end
    return UNKNOWN
end

function S.CategoryRank.sellable(name)
    return TAIL[name] == nil
end

-- Stable order by rank then name. Returns a new list.
function S.CategoryRank.order(groups)
    local out = {}
    for i, g in ipairs(groups) do out[i] = { g = g, i = i } end
    table.sort(out, function(a, b)
        local ra, rb = S.CategoryRank.rank(a.g.name), S.CategoryRank.rank(b.g.name)
        if ra ~= rb then return ra < rb end
        if a.g.name ~= b.g.name then return a.g.name < b.g.name end
        return a.i < b.i
    end)
    local res = {}
    for i, e in ipairs(out) do res[i] = e.g end
    return res
end
