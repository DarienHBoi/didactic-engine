local _, S = ...
S.Group = {}

-- Groups recipes by category in order of first appearance; recipes without a category go to "Other".
function S.Group.byCategory(recipes, keep)
    local groups, at = {}, {}
    for _, r in ipairs(recipes) do
        if keep(r) then
            local name = r.category or "Other"
            if not at[name] then
                groups[#groups + 1] = { name = name, items = {} }
                at[name] = #groups
            end
            local g = groups[at[name]]
            g.items[#g.items + 1] = r
        end
    end
    return groups
end

-- Returns a sorted copy. mode: "price_desc", "price_asc" or "name". Unknown prices sort last; ties by name.
function S.Group.sort(items, mode, askFn)
    local out = {}
    for i, r in ipairs(items) do out[i] = r end
    table.sort(out, function(a, b)
        if mode == "price_desc" or mode == "price_asc" then
            local pa, pb = askFn(a), askFn(b)
            if pa ~= pb then
                if pa == nil then return false end
                if pb == nil then return true end
                if mode == "price_desc" then return pa > pb end
                return pa < pb
            end
        end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

-- One group holding every item, for flat sorted views.
function S.Group.flat(items)
    local copy = {}
    for i, r in ipairs(items) do copy[i] = r end
    return { { name = "All enchants", items = copy } }
end

-- "Enchant 2H Weapon - Lesser Spirit" -> "Lesser Spirit": the tail is what distinguishes list rows.
function S.Group.shortName(name)
    if type(name) ~= "string" then return "" end
    local tail = name:match("^.-%s%-%s(.+)$")
    return tail or name
end
