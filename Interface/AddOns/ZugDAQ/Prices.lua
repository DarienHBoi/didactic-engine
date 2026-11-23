local _, ns = ...

-- Prices come from Auctionator: its API for the latest price, and its price database for
-- the day-by-day history (lowest price seen each day it scanned).

local CALLER = "ZugDAQ"

local function api()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end
function ns.HasAuctionator() return api() ~= nil end

-- latest lowest buyout per item (copper) or nil: ZugDAQ's own live check when that's the
-- newest look at the item, otherwise what Auctionator last saw
function ns.AuctionPrice(itemID)
    if ns.LivePrice and itemID then
        local livePrice = ns.LivePrice(itemID)
        if livePrice then return livePrice end
        if livePrice == false then return nil end -- checked just now: nothing listed
    end
    local a = api()
    if a and a.GetAuctionPriceByItemID and itemID then
        local ok, price = pcall(a.GetAuctionPriceByItemID, CALLER, itemID)
        if ok and type(price) == "number" and price > 0 then return price end
    end
    -- nothing from Auctionator: the ZugDAQ app's market price, from its last data sent to the game
    return ns.AppPrice and ns.AppPrice(itemID) or nil
end

-- what a vendor pays for one
function ns.VendorSell(itemID)
    if not itemID then return end
    local sell = select(11, ns.GetItemInfo(itemID))
    if type(sell) == "number" and sell > 0 then return sell end
    if sell == nil then ns.RequestItem(itemID) end
end

-- value of one item under the chosen mode; bound items only ever go to a vendor
function ns.Value(itemID, bound)
    local vendor = ns.VendorSell(itemID) or 0
    if bound then return vendor end
    local mode = ns.settings.valueMode
    if mode == "vendor" then return vendor end
    local ah = ns.AuctionPrice(itemID)
    ah = ah and ah * (1 - ns.settings.ahCut) or nil
    if mode == "auction" then return ah or vendor end
    return math.max(ah or 0, vendor)
end

local function priceDB()
    local db = Auctionator and Auctionator.Database and Auctionator.Database.db
    if type(db) == "table" then return db end
end

local function scanDay()
    local zero = Auctionator and Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0
    if not zero then return end
    return math.floor((time() - zero) / 86400)
end

-- Market stats for one price-database entry:
--   current  latest lowest buyout
--   usual    average of each day's lowest price over the `days` before the latest scan
--   low/high cheapest and dearest daily lows in that window
--   daysSeen how many days are in that window
--   age      days since the latest scan saw it (0 = today)
--   available how many were listed on the latest scan day
--   trend    current / usual
local function statsFor(entry, days, today)
    if type(entry) ~= "table" or type(entry.h) ~= "table" then return end
    local latest
    for day in pairs(entry.h) do
        local d = tonumber(day)
        if d and (not latest or d > latest) then latest = d end
    end
    if not latest then return end
    local sum, n, low, high = 0, 0, nil, nil
    for day, hi in pairs(entry.h) do
        local d = tonumber(day)
        if d and d < latest and d >= latest - days then
            local lo = (entry.l and entry.l[day]) or hi
            if type(lo) == "number" then
                sum, n = sum + lo, n + 1
                if not low or lo < low then low = lo end
                if not high or lo > high then high = lo end
            end
        end
    end
    local latestKey = latest
    if entry.h[latestKey] == nil then latestKey = tostring(latest) end
    local current = entry.m
    if type(current) ~= "number" or current <= 0 then
        current = (entry.l and entry.l[latestKey]) or entry.h[latestKey]
    end
    local usual = n > 0 and sum / n or nil
    return {
        current = current,
        usual = usual,
        low = low,
        high = high,
        daysSeen = n,
        age = today and (today - latest) or nil,
        available = entry.a and entry.a[latestKey] or nil,
        trend = (usual and usual > 0 and current) and current / usual or nil,
    }
end

function ns.PriceStats(itemID, days)
    local db = priceDB()
    if not db or not itemID then return end
    local ok, stats = pcall(statsFor, db[tostring(itemID)], days or ns.settings.avgDays, scanDay())
    if ok then return stats end
end

-- walks every plain item in Auctionator's price database: fn(itemID, stats)
function ns.EachPricedItem(fn, days)
    local db = priceDB()
    if not db then return 0 end
    local today = scanDay()
    days = days or ns.settings.avgDays
    local count = 0
    for key, entry in pairs(db) do
        local itemID = type(key) == "string" and tonumber(key) or (type(key) == "number" and key) or nil
        if itemID and type(entry) == "table" then
            local ok, stats = pcall(statsFor, entry, days, today)
            if ok and stats then
                count = count + 1
                fn(itemID, stats)
            end
        end
    end
    return count
end

-- opens Auctionator's shopping tab searching for these exact item names (AH must be open)
function ns.SearchAH(names)
    local a = api()
    if not (a and a.MultiSearchExact) then
        ns.Print("searching needs Auctionator.")
        return
    end
    local clean = {}
    for _, name in ipairs(names) do
        if type(name) == "string" and name ~= "" and not name:find("[;^\"]") then
            clean[#clean + 1] = name
            if #clean >= 50 then break end
        end
    end
    if #clean == 0 then return end
    if ns.Trace then ns.Trace("Auctionator MultiSearchExact") end
    local ok, err = pcall(a.MultiSearchExact, CALLER, clean)
    if not ok then
        if tostring(err):find("not open") then
            ns.Print("open the auction house first.")
        else
            ns.Print("search failed: %s", tostring(err))
        end
    end
end
