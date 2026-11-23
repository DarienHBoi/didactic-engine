local _, S = ...
S.Stats = {}

-- Longest names first so "fire resistance" is taken before "resistance".
local NAMES = {
    { "resistance to all schools of magic", "All Res" }, { "additional points of damage", "Dmg" },
    { "all resistances", "All Res" }, { "arcane resistance", "Arcane Res" }, { "fire resistance", "Fire Res" },
    { "frost resistance", "Frost Res" }, { "nature resistance", "Nature Res" }, { "shadow resistance", "Shadow Res" },
    { "attack power", "AP" }, { "spell power", "SP" }, { "spell damage", "Spell dmg" }, { "all stats", "All stats" },
    { "resistance", "Res" }, { "strength", "STR" }, { "agility", "AGI" }, { "intellect", "INT" }, { "spirit", "SPI" },
    { "stamina", "STA" }, { "health", "HP" }, { "mana", "Mana" }, { "armor", "Armor" }, { "defense", "Def" },
    { "healing", "Healing" },
}

-- Turns an enchant description into a short stat string such as "+3 STR" or "+5 AGI +2 SPI".
-- Only known stat names are ever output, so nothing from the description can inject chat codes.
function S.Stats.parse(desc)
    if type(desc) ~= "string" or desc == "" then return nil end
    local low = desc:lower()
    local taken, found = {}, {}
    for _, e in ipairs(NAMES) do
        local pos = 1
        while true do
            local a, b = low:find(e[1], pos, true)
            if not a then break end
            pos = b + 1
            local free = true
            for i = a, b do if taken[i] then free = false break end end
            if free then
                -- "Stamina by 4", plus Forever's "Stamina of the wearer by 4" and "defense skill of the wearer is increased by 3".
                local rest = low:sub(b + 1)
                local n = rest:match("^%s+by%s+(%d+)") or rest:match("^%s+of%s+the%s+wearer%s+by%s+(%d+)")
                    or rest:match("^%s+skill%s+of%s+the%s+wearer%s+is%s+increased%s+by%s+(%d+)")
                if not n then
                    local before = low:sub(1, a - 1)
                    n = before:match("%+(%d+)%s*$") or before:match("adds?%s+(%d+)%s+to%s+$") or before:match("adds?%s+(%d+)%s+$") or before:match("(%d+)%s+$")
                end
                if n then
                    for i = a, b do taken[i] = true end
                    found[#found + 1] = { at = a, text = "+" .. tonumber(n) .. " " .. e[2] }
                end
            end
        end
    end
    if #found == 0 then return nil end
    table.sort(found, function(x, y) return x.at < y.at end)
    local out = {}
    for _, f in ipairs(found) do out[#out + 1] = f.text end
    return table.concat(out, " ")
end

-- Stats of a piece of gear from the table GetItemStats returns, best-known first, at most three.
local ITEM_STATS = {
    { "ITEM_MOD_STRENGTH_SHORT", "STR" }, { "ITEM_MOD_AGILITY_SHORT", "AGI" }, { "ITEM_MOD_STAMINA_SHORT", "STA" },
    { "ITEM_MOD_INTELLECT_SHORT", "INT" }, { "ITEM_MOD_SPIRIT_SHORT", "SPI" },
}
function S.Stats.fromItemStats(t)
    if type(t) ~= "table" then return nil end
    local out = {}
    for _, e in ipairs(ITEM_STATS) do
        local v = t[e[1]]
        if type(v) == "number" and v > 0 and #out < 3 then out[#out + 1] = "+" .. v .. " " .. e[2] end
    end
    local armor = t.RESISTANCE0_NAME
    if type(armor) == "number" and armor > 0 and #out < 3 then out[#out + 1] = "+" .. armor .. " Armor" end
    if #out == 0 then return nil end
    return table.concat(out, " ")
end

-- What a recipe gives, as short chat text: the game's own description, else the built-in table, else the crafted item's stats.
-- getItemStats(link) is the client's GetItemStats; it is only called for recipes with a result item link.
function S.Stats.forRecipe(r, getItemStats, overrides)
    if type(r) ~= "table" then return nil end
    local mine = overrides and type(r.name) == "string" and overrides[r.name:lower()]
    if mine then return mine end
    if type(r.stats) == "string" and r.stats ~= "" then return r.stats end
    -- The game's own text beats the built-in Classic table (Forever changes values and adds enchants).
    local fromDesc = S.Stats.parse(r.desc)
    if fromDesc then return fromDesc end
    local known = S.StatsData and type(r.name) == "string" and S.StatsData[r.name:lower()]
    if known then return known end
    if r.resultLink and getItemStats then
        local ok, t = pcall(getItemStats, r.resultLink)
        if ok then return S.Stats.fromItemStats(t) end
    end
    return nil
end

-- The owner's own stats text for a recipe (Forever differs from Classic, so any built-in value can be corrected).
-- Blank removes the override. Returns true, or false and a reason.
function S.Stats.setOverride(store, name, text)
    if type(store) ~= "table" or type(name) ~= "string" or name == "" then return false, "no recipe" end
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if text == "" then store[name:lower()] = nil return true end
    if text:find("[|{}]") then return false, "Stats cannot contain | { or }." end
    if #text > 40 then return false, "Keep the stats under 40 characters." end
    store[name:lower()] = text
    return true
end
