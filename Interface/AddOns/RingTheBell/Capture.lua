-- Ring the Bell: pure best-spell pick from the damage meter's combatSpells list.
local addonName, RB = ...
local L = RB.L
local C = {}
RB.C = C

function C.bestSpell(rows)
    if type(rows) ~= "table" then return nil end
    local best, bestAmount
    for _, row in ipairs(rows) do
        if type(row) == "table" then
            local amt = row.totalAmount
            if L.isNum(amt) and amt > 0 and (bestAmount == nil or amt > bestAmount) then
                best, bestAmount = row, amt
            end
        end
    end
    return best
end
