local _, P = ...
P.Watch = {}

-- The live sources: Salesman's recipes and sold items (one call each), Auctionator's posted items.
function P.Watch.live()
    return { recipes = P.Adapters.salesmanRecipes, posted = P.Adapters.postedIDs, sold = P.Adapters.salesmanSoldIDs }
end

-- The bounded watch list: disenchant mats, crafted items, items you sold or listed. Nothing else is copied.
-- deps = { recipes() -> {{itemID}}, sold() -> ids, posted() -> ids }; a failing source is skipped.
function P.Watch.build(deps)
    deps = deps or {}
    local out, seen = {}, {}
    local function add(id)
        if type(id) == "number" and not seen[id] and #out < P.Config.MAX_ITEMS then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    local function each(fn, field)
        if type(fn) ~= "function" then return end
        local ok, list = pcall(fn)
        if not ok or type(list) ~= "table" then return end
        for _, v in ipairs(list) do
            if field then add(type(v) == "table" and v[field] or nil) else add(v) end
        end
    end
    local mats = {}
    for id in pairs(P.DE.MATS) do mats[#mats + 1] = id end
    table.sort(mats)
    for _, id in ipairs(mats) do add(id) end
    each(deps.recipes, "itemID")
    each(deps.sold)
    each(deps.posted)
    return out
end
