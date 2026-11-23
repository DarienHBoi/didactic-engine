local _, ns = ...

-- Follow recorded item/container sources without treating a possible drop as
-- guaranteed. Cache only source relationships; the map index owns spawn points.
function ns.CreateItemSources(database)
    local cache = {}
    return function(itemID)
        if cache[itemID] then return cache[itemID] end
        local results, visited, seen = {}, {}, {}
        local items = database.Item
        if not items or not items.Get then return results end
        local function add(kind, id, source)
            if type(id) ~= 'number' or id <= 0 then return end
            local key = kind .. ':' .. id .. ':' .. source
            if not seen[key] then
                seen[key] = true
                results[#results + 1] = {kind = kind, id = id, source = source}
            end
        end
        local function visit(id)
            if visited[id] then return end
            visited[id] = true
            for _, npc in ipairs(items.Get(id, 'npcDrops') or {}) do add(1, npc, 'Possible drop source') end
            for _, object in ipairs(items.Get(id, 'objectDrops') or {}) do add(2, object, 'Possible container source') end
            for _, npc in ipairs(items.Get(id, 'vendors') or {}) do add(1, npc, 'Possible vendor source') end
            for _, container in ipairs(items.Get(id, 'itemDrops') or {}) do visit(container) end
        end
        visit(itemID)
        cache[itemID] = results
        return results
    end
end
