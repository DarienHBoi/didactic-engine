local _, S = ...
S.Sales = {}
S.Sales.MAX = 20

local function valid(v)
    return type(v) == "number" and v == v and v > 0 and v < math.huge
end

-- Appends a sold price (copper). Ignores bad values. Keeps only the newest MAX entries.
function S.Sales.add(list, copper, t)
    if type(list) ~= "table" or not valid(copper) then return list end
    list[#list + 1] = { copper = copper, time = t or 0 }
    while #list > S.Sales.MAX do table.remove(list, 1) end
    return list
end

-- Newest first.
function S.Sales.recent(list, n)
    local out = {}
    if type(list) ~= "table" then return out end
    for i = #list, 1, -1 do
        if #out >= (n or #list) then break end
        out[#out + 1] = list[i]
    end
    return out
end

function S.Sales.median(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local v = {}
    for i, e in ipairs(list) do v[i] = e.copper end
    table.sort(v)
    local mid = #v / 2
    if #v % 2 == 1 then return v[math.ceil(mid)] end
    return math.floor((v[mid] + v[mid + 1]) / 2)
end
