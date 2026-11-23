local _, ns = ...

-- A running history of what each character holds (bags + bank) and what's in the warbank: every time an
-- item's count changes, its new count is logged with the time. Changes within a few minutes of the last
-- entry replace it, so a busy farming session doesn't flood the file. ZugDAQ reads this to chart your
-- stock, see how fast you gather or use each item, and project what it will earn.
--
--   ZugDAQDB.inventory[owner][itemID] = { time1, count1, time2, count2, ... }   (owner: "Name-Realm" or "Warbank")
--
-- Ninety days are kept, plus the last entry before that so every item still has a starting count.

local MERGE_SECONDS = 300
local KEEP_SECONDS = 90 * 86400

local function counts(owner)
    local db = ns.db
    if owner == "Warbank" then
        local w = db.warbank and db.warbank.items
        if type(w) ~= "table" then return nil end
        local t = {}
        for id, n in pairs(w) do t[id] = n end
        return t
    end
    local c = db.chars and db.chars[owner]
    if not c or not c.bags then return nil end
    local t = {}
    for id, n in pairs(c.bags or {}) do t[id] = (t[id] or 0) + n end
    for id, n in pairs(c.bank or {}) do t[id] = (t[id] or 0) + n end
    return t
end

local function prune(series, now)
    -- drop pairs older than the window, but keep the newest of those as the starting count
    local cutoff, first = now - KEEP_SECONDS, nil
    for i = 1, #series - 2, 2 do
        if series[i + 2] < cutoff then first = i + 2 else break end
    end
    if first then
        local kept = {}
        for i = first, #series do kept[#kept + 1] = series[i] end
        return kept
    end
    return series
end

local function log(owner)
    local now = counts(owner)
    if not now then return end
    local inv = ns.db.inventory or {}
    ns.db.inventory = inv
    local mine = inv[owner] or {}
    inv[owner] = mine
    local t = time()

    local seen = {}
    for id, n in pairs(now) do seen[id] = true end
    for id in pairs(mine) do seen[id] = true end
    for id in pairs(seen) do
        local series = mine[id] or {}
        local last = #series >= 2 and series[#series] or nil
        local n = now[id] or 0
        if last ~= n and not (last == nil and n == 0) then
            if #series >= 2 and t - series[#series - 1] < MERGE_SECONDS then
                series[#series] = n                       -- a moment ago: update that entry
                if #series >= 4 and series[#series - 2] == n then  -- and it's back where it was
                    series[#series] = nil; series[#series] = nil
                end
            else
                series[#series + 1] = t
                series[#series + 1] = n
            end
            mine[id] = prune(series, t)
        end
        -- an item gone for good, with nothing left in the window, needn't be kept
        if mine[id] and #mine[id] == 2 and mine[id][2] == 0 and t - mine[id][1] > KEEP_SECONDS then mine[id] = nil end
    end
end

local function logCharacter()
    if ns.charKey then log(ns.charKey) end
end

local function logAll()
    logCharacter()
    log("Warbank")
end

-- after the bag and bank scans (Market.lua) have run
ns.OnLogin(function() C_Timer.After(6, logAll) end)
ns.On("BAG_UPDATE_DELAYED", function() ns.Debounce("inventorylog", 4, logCharacter) end)
ns.On("PLAYERBANKSLOTS_CHANGED", function() ns.Debounce("inventorybank", 3, logAll) end)
ns.On("BANKFRAME_CLOSED", function() C_Timer.After(1, logAll) end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function() ns.Debounce("inventorybank", 1, logAll) end)
ns.On("PLAYER_LOGOUT", logAll)
