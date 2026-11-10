local _, S = ...
S.Stock = {}

-- What the player holds against what a recipe needs. count(itemID) -> number.
-- Returns { lines = {{have, need, ok}}, craftable = number|nil, missing = {{index, short}} }.
-- craftable is nil (unknown) when any item id is unknown, a need is not positive, or counting fails.
function S.Stock.check(recipe, count)
    local out = { lines = {}, missing = {} }
    if type(recipe) ~= "table" or type(recipe.reagents) ~= "table" or #recipe.reagents == 0 then return out end
    local craftable, unknown = nil, false
    for i, r in ipairs(recipe.reagents) do
        local id, need = r[1], r[2]
        local line = { need = need }
        local good = type(need) == "number" and need > 0
        if good and id then
            local ok, n = pcall(count, id)
            if ok and type(n) == "number" then line.have = n end
        end
        if line.have then
            line.ok = line.have >= need
            local can = math.floor(line.have / need)
            if craftable == nil or can < craftable then craftable = can end
            if not line.ok then out.missing[#out.missing + 1] = { index = i, short = need - line.have } end
        else
            unknown = true
        end
        out.lines[i] = line
    end
    if not unknown then out.craftable = craftable end
    return out
end

function S.Stock.label(craftable)
    if craftable == nil then return "" end
    if craftable <= 0 then return "no mats" end
    return "can make " .. craftable
end
