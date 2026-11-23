-- ZugHistory: long server-wide price history for other addons, read from Data\History.lua (ZugHistory_Data), which the
-- ZugCompanion desktop app rewrites from its archive of ZugDAQ snapshots. The game reads it at login and on /reload.
--
--   ZugHistory_Data = { version = 1, made, house, first (unix time of day 1's local midnight), days, newest (newest snapshot),
--     market = { [itemID] = "v1,v2,,v4" },   -- day-end market price in copper per day, empty = no price that day
--     sold   = { [itemID] = "s1,s2,,s4" } }  -- ZugDAQ's sold-per-day estimate on that day
--
-- Prices are packed in strings so the file stays far below Lua 5.1's constant limit; an item is unpacked on first use.
-- Day i starts at first + (i - 1) * 86400 (an hour off across a clock change; fine for day-level history).
--
-- Second job: remember each ZugDAQ item's quality, class, item level and vendor price in ZugHistoryDB.items, so the
-- companion app can value disenchants and vendor sales while the game is closed. Nothing here writes to ZugDAQ.
--
-- Public API (never throws; nil when there is nothing):
--   ZugHistory.series(id)      -> { { t, market, sold }, ... } days that have a price, oldest first
--   ZugHistory.stats(id, days) -> { n, median, low, high, first, last, sold } over the newest `days` days (default 30)
--   ZugHistory.info()          -> { house, days, first, newest, age (whole days since the newest snapshot), items }

local ADDON = ...
ZugHistory = ZugHistory or {}
local Z = ZugHistory
local DAY = 86400

local function data()
    local d = ZugHistory_Data
    if type(d) == "table" and d.version == 1 and type(d.market) == "table" and type(d.first) == "number" then return d end
    return nil
end

local function unpackList(s, n)
    local out, i = {}, 0
    if type(s) ~= "string" then return out end
    for v in (s .. ","):gmatch("([^,]*),") do
        i = i + 1
        if i > n then break end
        out[i] = tonumber(v)
    end
    return out
end

local cache = {}

function Z.series(id)
    if type(id) ~= "number" then return nil end
    local ok, res = pcall(function()
        local d = data()
        if not d then return nil end
        if cache[id] ~= nil and cache.made == d.made then return cache[id] or nil end
        if cache.made ~= d.made then cache = { made = d.made } end
        local packed = d.market[id]
        if type(packed) ~= "string" then cache[id] = false; return nil end
        local n = tonumber(d.days) or 0
        local m = unpackList(packed, n)
        local s = unpackList(type(d.sold) == "table" and d.sold[id], n)
        local out = {}
        for i = 1, n do
            if m[i] then out[#out + 1] = { t = d.first + (i - 1) * DAY, market = m[i], sold = s[i] } end
        end
        if #out == 0 then out = false end
        cache[id] = out
        return out or nil
    end)
    return ok and res or nil
end

function Z.stats(id, days)
    local ok, res = pcall(function()
        local series = Z.series(id)
        local d = data()
        if not series or not d then return nil end
        days = tonumber(days) or 30
        local from = d.first + ((tonumber(d.days) or 0) - days) * DAY
        local vals, soldSum, soldN, first, last = {}, 0, 0, nil, nil
        for _, e in ipairs(series) do
            if e.t >= from then
                vals[#vals + 1] = e.market
                first = first or e.market
                last = e.market
                if e.sold then soldSum, soldN = soldSum + e.sold, soldN + 1 end
            end
        end
        local n = #vals
        if n == 0 then return nil end
        table.sort(vals)
        local median = (n % 2 == 1) and vals[(n + 1) / 2] or (vals[n / 2] + vals[n / 2 + 1]) / 2
        return { n = n, median = median, low = vals[1], high = vals[n], first = first, last = last,
                 sold = soldN > 0 and soldSum / soldN or nil }
    end)
    return ok and res or nil
end

function Z.info()
    local ok, res = pcall(function()
        local d = data()
        if not d then return nil end
        local count = 0
        for _ in pairs(d.market) do count = count + 1 end
        local stamp = tonumber(d.newest) or tonumber(d.made)
        return { house = d.house, days = d.days, first = d.first, newest = d.newest, items = count,
                 age = stamp and math.floor(math.max(0, time() - stamp) / DAY) or nil }
    end)
    return ok and res or nil
end

-- ------------------------------------------------------------------------------------------------ item info recorder
local BATCH, BATCH_DELAY = 150, 0.2

local function itemInfo(id)
    local fn = (type(C_Item) == "table" and C_Item.GetItemInfo) or GetItemInfo
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, id) }
    if not r[1] or r[2] == nil then return nil end
    -- name, link, quality, ilvl, reqLevel, class, subclass, stack, equipLoc, texture, vendor, classID, subclassID, bindType
    return { q = r[4], l = r[5], v = r[12], c = r[13], b = r[15], t = time() }
end

local function request(id)
    if type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function" then
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
end

local function wantedIds()
    local ids = {}
    local function add(id) id = tonumber(id); if id and id > 0 then ids[id] = true end end
    local db = ZugDAQDB
    if type(db) ~= "table" then return ids end
    for _, c in pairs(type(db.chars) == "table" and db.chars or {}) do
        if type(c) == "table" then
            for id in pairs(type(c.bags) == "table" and c.bags or {}) do add(id) end
            for id in pairs(type(c.bank) == "table" and c.bank or {}) do add(id) end
            for _, list in ipairs({ c.recipes, c.unlearned }) do
                for _, r in pairs(type(list) == "table" and list or {}) do
                    if type(r) == "table" then
                        add(r.output)
                        for _, slot in ipairs(type(r.slots) == "table" and r.slots or {}) do
                            for _, it in ipairs(type(slot) == "table" and type(slot.items) == "table" and slot.items or {}) do add(it) end
                        end
                    end
                end
            end
        end
    end
    local wb = type(db.warbank) == "table" and db.warbank.items
    for id in pairs(type(wb) == "table" and wb or {}) do add(id) end
    return ids
end

local queue, waiting = {}, {}

local function store()
    ZugHistoryDB = type(ZugHistoryDB) == "table" and ZugHistoryDB or {}
    ZugHistoryDB.items = type(ZugHistoryDB.items) == "table" and ZugHistoryDB.items or {}
    return ZugHistoryDB.items
end

local function record(id)
    local info = itemInfo(id)
    if info and info.q then
        store()[id] = info
        waiting[id] = nil
        return true
    end
    waiting[id] = true
    request(id)
    return false
end

local function step()
    local n = 0
    while #queue > 0 and n < BATCH do
        record(table.remove(queue))
        n = n + 1
    end
    if #queue > 0 and C_Timer then C_Timer.After(BATCH_DELAY, step) end
end

local function scanAll()
    local have = store()
    queue = {}
    for id in pairs(wantedIds()) do
        if type(have[id]) ~= "table" then queue[#queue + 1] = id end
    end
    step()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
pcall(f.RegisterEvent, f, "GET_ITEM_INFO_RECEIVED")
f:SetScript("OnEvent", function(_, event, a, b)
    if event == "ADDON_LOADED" and a == ADDON then
        store()
    elseif event == "PLAYER_LOGIN" then
        if C_Timer then C_Timer.After(10, function() pcall(scanAll) end) else pcall(scanAll) end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local id = tonumber(a)
        if id and waiting[id] and b then pcall(record, id) end
    end
end)

SLASH_ZUGHISTORY1 = "/zughistory"
SlashCmdList = SlashCmdList or {}
SlashCmdList.ZUGHISTORY = function()
    local i = Z.info()
    if not i or (i.days or 0) == 0 then
        print("|cff33ff99ZugHistory|r: no history yet. Run ZugCompanion on the PC, then /reload.")
        return
    end
    local recorded = 0
    for _ in pairs(store()) do recorded = recorded + 1 end
    print(string.format("|cff33ff99ZugHistory|r: %d days of %s prices for %d items, newest snapshot %s day(s) old. Item info kept: %d.",
        i.days, tostring(i.house or "?"), i.items, tostring(i.age or "?"), recorded))
end
