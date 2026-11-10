local _, S = ...
S.Money = {}

function S.Money.format(copper)
    if copper == nil or copper ~= copper or copper == math.huge or copper == -math.huge then return "unknown" end
    copper = math.floor(copper)
    if copper <= 0 then return "0c" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = string.format("%d", g) .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

function S.Money.roundUpSilver(copper)
    if copper == nil then return nil end
    return math.ceil(copper / 100) * 100
end

-- Plain decimal gold ("4.5") to copper; nil for anything else, zero, negatives or absurd amounts.
function S.Money.parseGold(text)
    if type(text) ~= "string" then return nil end
    text = text:match("^%s*(.-)%s*$")
    if not text:match("^%d+%.?%d*$") then return nil end
    local g = tonumber(text)
    if not g or g <= 0 or g > 1000000 then return nil end
    local c = math.floor(g * 10000 + 0.5)
    if c < 1 then return nil end
    return c
end

-- Copper to a plain gold string without trailing zeros ("4.5").
function S.Money.goldText(copper)
    if type(copper) ~= "number" or copper ~= copper then return "" end
    local s = string.format("%.4f", copper / 10000)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end
