-- AddonPresets: pure logic (no game calls), so it can be tested outside WoW.
local ADDON, A = ...
A.UNDO = "(before load)"

local function tracked(name)
    return type(name) == "string" and name ~= ADDON and not name:find("^Blizzard_")
end

-- A preset from a list of {name, enabled}: every addon except Blizzard's and this one, on (true) or off (false).
function A.capture(list)
    local set = {}
    for _, a in ipairs(list or {}) do
        if tracked(a.name) then set[a.name] = a.enabled and true or false end
    end
    return set
end

-- What loading `set` applies: sorted installed addons to turn on and off. Addons the set does not know are left
-- alone; `missing` counts addons in the set that are no longer installed. Everything is applied, not only what
-- looks different, because a per-character switch can make an addon read as on while it stays off.
function A.entries(set, list)
    local e, seen = { on = {}, off = {}, missing = 0 }, {}
    for _, a in ipairs(list or {}) do
        seen[a.name] = true
        local want = set and set[a.name]
        if tracked(a.name) and want ~= nil then
            local t = want and e.on or e.off
            t[#t + 1] = a.name
        end
    end
    for name in pairs(set or {}) do
        if tracked(name) and not seen[name] then e.missing = e.missing + 1 end
    end
    table.sort(e.on); table.sort(e.off)
    return e
end

function A.cleanName(s)
    if type(s) ~= "string" then return nil end
    s = s:match("^%s*(.-)%s*$")
    if s == "" then return nil end
    return s:sub(1, 40)
end

-- Preset names A-Z ignoring case, with the undo slot last.
function A.sortedNames(sets)
    local out = {}
    for name in pairs(sets or {}) do if name ~= A.UNDO then out[#out + 1] = name end end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    if sets and sets[A.UNDO] then out[#out + 1] = A.UNDO end
    return out
end

-- How many addons a preset turns on, out of how many it records.
function A.count(set)
    local on, total = 0, 0
    for _, v in pairs(set or {}) do
        total = total + 1
        if v then on = on + 1 end
    end
    return on, total
end
