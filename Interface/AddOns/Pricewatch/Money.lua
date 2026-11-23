local _, P = ...
P.Money = {}

function P.Money.format(copper)
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

-- Padded plain text: "1g 05s 03c", "7s 00c", "0c". Units below the highest one in use are always shown, two digits.
function P.Money.pad(copper)
    if copper == nil or copper ~= copper or copper == math.huge or copper == -math.huge then return "unknown" end
    copper = math.floor(copper)
    if copper <= 0 then return "0c" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return ("%dg %02ds %02dc"):format(g, s, c) end
    if s > 0 then return ("%ds %02dc"):format(s, c) end
    return c .. "c"
end

local ICON = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"

-- The same amount with the game's own coin icons in place of the letters (for tooltip lines).
function P.Money.coins(copper)
    local text = P.Money.pad(copper)
    if text == "unknown" then return text end
    local names = { g = "Gold", s = "Silver", c = "Copper" }
    return (text:gsub("(%d+)([gsc])", function(n, u) return n .. ICON:format(names[u]) end))
end

-- Rounded to the largest unit, for axis labels: "12g", "45s", "37c". 99s 99c rounds up to "1g", never "100s".
function P.Money.short(copper)
    if copper == nil or copper ~= copper or copper == math.huge or copper == -math.huge then return "unknown" end
    if copper < 0 then return "-" .. P.Money.short(-copper) end
    copper = math.floor(copper)
    if copper >= 10000 then return math.floor(copper / 10000 + 0.5) .. "g" end
    if copper >= 100 then
        local s = math.floor(copper / 100 + 0.5)
        if s >= 100 then return "1g" end
        return s .. "s"
    end
    return copper .. "c"
end
