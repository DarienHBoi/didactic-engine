local _, P = ...
P.List = {}
local L = P.List

-- Rows for the item list: stored items plus crafted items (even with no history). Salesman is optional.
-- recipes = SalesmanAPI.recipes() rows ({itemID, name}); salesOf(id) = SalesmanAPI.sales(id).
function L.build(db, recipes, salesOf, today, e0)
    local rows, at = {}, {}
    local function row(id)
        local r = at[id]
        if not r then
            r = { id = id, hasData = false }
            at[id] = r
            rows[#rows + 1] = r
        end
        return r
    end
    if type(db) == "table" and type(db.items) == "table" then
        for id, it in pairs(db.items) do
            local r = row(id)
            r.name = it.name
            local f = P.Verdict.figures(it, nil, today, { e0 = e0 })
            r.now, r.age = f.now, f.age
            r.hasData = f.now ~= nil
            if f.now and f.d7 and f.d7 > 0 then r.change = math.floor((f.now - f.d7) / f.d7 * 1000 + 0.5) / 10 end
        end
    end
    for _, rc in ipairs(type(recipes) == "table" and recipes or {}) do
        if type(rc) == "table" and type(rc.itemID) == "number" then
            local r = row(rc.itemID)
            if type(rc.name) == "string" then r.name = rc.name end
            r.crafted = true
        end
    end
    for _, r in ipairs(rows) do
        r.name = r.name or ("Item " .. r.id)
        r.sells = 0
        if type(salesOf) == "function" then
            local ok, list = pcall(salesOf, r.id)
            if ok and type(list) == "table" then
                local f = P.Verdict.figures(nil, list, today, { e0 = e0 })
                r.sells, r.sold = f.sellsPerWeek, f.sales
            end
        end
    end
    return rows
end

function L.filter(rows, q)
    local out = {}
    q = type(q) == "string" and q:lower():match("^%s*(.-)%s*$") or ""
    for _, r in ipairs(rows or {}) do
        if q == "" or r.name:lower():find(q, 1, true) then out[#out + 1] = r end
    end
    return out
end

-- Modes: name, sells (most sold first), change (biggest price change first, no change last). Ties by name.
function L.sort(rows, mode)
    local out = {}
    for _, r in ipairs(rows or {}) do out[#out + 1] = r end
    table.sort(out, function(a, b)
        if mode == "sells" and a.sells ~= b.sells then return a.sells > b.sells end
        if mode == "change" then
            if (a.change ~= nil) ~= (b.change ~= nil) then return a.change ~= nil end
            if a.change ~= nil and a.change ~= b.change then return math.abs(a.change) > math.abs(b.change) end
        end
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        return a.id < b.id
    end)
    return out
end
