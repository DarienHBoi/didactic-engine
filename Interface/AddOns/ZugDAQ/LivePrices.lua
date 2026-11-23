local _, ns = ...

-- How fresh each price is, to the second, and what is actually listed.
--   seen   every price Auctionator saves (full scan, shopping searches) gets a timestamp, by hooking
--          its price database: Auctionator itself only keeps one price per day.
--   live   ZugDAQ's own check while the AH is open: every listing (price and quantity) of an
--          item, so buying several can be costed listing by listing, not at the lowest price.

ns.FRESH_SECONDS = 600     -- older than this shows red: check again before buying
local LIVE_KEEP = 6 * 3600 -- live listings older than this are dropped at logout
local MAX_LISTINGS = 40
local TIMEOUT = 4

local seen, live = {}, {}

ns.OnLoad(function()
    ns.db.priceSeen = ns.db.priceSeen or {}
    ns.db.live = ns.db.live or {}
    seen, live = ns.db.priceSeen, ns.db.live
end)

-- ---------------------------------------------------------------- Auctionator timestamps

local hookedDB
local function hookAuctionator()
    local db = Auctionator and Auctionator.Database
    if type(db) ~= "table" or type(db.SetPrice) ~= "function" or db == hookedDB then return end
    hooksecurefunc(db, "SetPrice", function(_, dbKey)
        local id = tonumber(dbKey)
        if id then seen[id] = time() end
    end)
    hookedDB = db
end
ns.OnLogin(hookAuctionator)
ns.On("AUCTION_HOUSE_SHOW", hookAuctionator)

-- keep the saved timestamps small: only items that matter to recipes or the watchlist
ns.On("PLAYER_LOGOUT", function()
    local keep = {}
    for _, c in pairs(ns.db.chars) do
        for _, r in pairs(c.recipes or {}) do
            keep[r.output] = true
            for _, slot in ipairs(r.slots or {}) do
                for _, id in ipairs(slot.items) do keep[id] = true end
            end
        end
    end
    for id in pairs(ns.db.watch) do keep[id] = true end
    local now = time()
    for id in pairs(seen) do
        if not keep[id] then seen[id] = nil end
    end
    -- live checks: every recent one is kept (guildmates' too: they go to the app from here), the newest 1500 at most
    local recent = {}
    for id, entry in pairs(live) do
        if now - (entry.t or 0) > LIVE_KEEP then live[id] = nil else recent[#recent + 1] = { id = id, t = entry.t or 0 } end
    end
    if #recent > 1500 then
        table.sort(recent, function(a, b) return a.t > b.t end)
        for i = 1501, #recent do live[recent[i].id] = nil end
    end
end)

-- ---------------------------------------------------------------- freshness

-- when this item's price was last seen (Auctionator or ZugDAQ's own check), or nil
function ns.PriceTime(itemID)
    local a = seen[itemID]
    local b = live[itemID] and live[itemID].t
    if a and b then return math.max(a, b) end
    return a or b
end

-- seconds since then, or nil when it was never seen with a time on it
function ns.PriceAge(itemID)
    local t = ns.PriceTime(itemID)
    return t and math.max(0, time() - t) or nil
end

function ns.AgeText(seconds)
    if not seconds then return "old" end
    if seconds < 60 then return "now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end

-- "4m" in green while fresh, red once it's older than 10 minutes (or unknown)
function ns.AgeColored(seconds)
    local fresh = seconds and seconds <= ns.FRESH_SECONDS
    return (fresh and "|cff38c75c" or "|cffe64d4d") .. ns.AgeText(seconds) .. "|r"
end

-- ---------------------------------------------------------------- live listings

-- the newest live check of an item: { t, listings = { { price, qty } cheapest first }, total }
function ns.LiveListings(itemID)
    local entry = live[itemID]
    if entry and (not seen[itemID] or entry.t >= seen[itemID] - 5) then return entry end
end

-- the lowest price from a live check, when that check is the newest thing known about the item.
-- false means the check found nothing listed.
function ns.LivePrice(itemID)
    local entry = ns.LiveListings(itemID)
    if not entry then return nil end
    local first = entry.listings[1]
    if first then return first.price end
    return false
end

local queue, pending, total, done, waitingThrottle
local onFinish

local function ahOpen()
    return ns.InContext("auction") and C_AuctionHouse and C_AuctionHouse.SendSearchQuery ~= nil
end

local function finish(completed)
    queue, pending, waitingThrottle = nil, nil, false
    local cb = onFinish
    onFinish = nil
    ns.Fire("LIVE_PRICES", completed)
    ns.RequestRefresh()
    if cb then cb(completed) end
end

local nextItem

local function store(itemID, listings)
    table.sort(listings, function(a, b) return a.price < b.price end)
    local sum = 0
    for _, l in ipairs(listings) do sum = sum + l.qty end
    live[itemID] = { t = time(), listings = listings, total = sum }
    ns.Fire("LIVE_STORED", itemID) -- shared with the guild (Share.lua)
end

local function complete(itemID)
    if not pending or pending.id ~= itemID then return end
    pending = nil
    done = done + 1
    ns.Fire("LIVE_PROGRESS", done, total)
    nextItem()
end

nextItem = function()
    if not queue then return end
    if not ahOpen() then
        finish(false)
        return
    end
    local itemID = queue[1]
    if not itemID then
        finish(true)
        return
    end
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        waitingThrottle = true -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY picks it up again
        return
    end
    waitingThrottle = false
    table.remove(queue, 1)
    local key = C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(itemID)
    if not key then
        nextItem()
        return
    end
    local sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
    pending = { id = itemID }
    if ns.Trace then ns.Trace("AH SendSearchQuery " .. tostring(itemID)) end
    local ok = pcall(C_AuctionHouse.SendSearchQuery, key, { { sortOrder = sortOrder, reverseSort = false } }, false)
    if not ok then
        pending = nil
        nextItem()
        return
    end
    local mine = pending
    C_Timer.After(TIMEOUT, function()
        -- no answer in time: leave what we knew, move on
        if pending == mine then complete(itemID) end
    end)
end

ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
    if waitingThrottle then nextItem() end
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
    if queue then finish(false) end
end)

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    if not pending or pending.id ~= itemID then return end
    local listings = {}
    local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
    for i = 1, math.min(n, MAX_LISTINGS) do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.quantity then
            -- your own listings aren't for sale to you
            local qty = r.quantity - (r.numOwnerItems or 0)
            if qty > 0 then listings[#listings + 1] = { price = r.unitPrice, qty = qty } end
        end
    end
    store(itemID, listings)
    complete(itemID)
end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    local itemID = type(itemKey) == "table" and itemKey.itemID
    if not pending or pending.id ~= itemID then return end
    local listings = {}
    local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
    for i = 1, math.min(n, MAX_LISTINGS) do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and not r.containsOwnerItem then
            listings[#listings + 1] = { price = r.buyoutAmount, qty = r.quantity or 1 }
        end
    end
    store(itemID, listings)
    complete(itemID)
end)

-- check these items on the open AH, one at a time. onDone(completed) when finished or stopped.
function ns.CheckPrices(itemIDs, onDone)
    if not ahOpen() then
        ns.Print("open the auction house first.")
        return false
    end
    if queue then return false end
    local unique, list = {}, {}
    for _, id in ipairs(itemIDs) do
        if id and not unique[id] then
            unique[id] = true
            list[#list + 1] = id
        end
    end
    if #list == 0 then return false end
    queue, total, done, onFinish = list, #list, 0, onDone
    ns.Fire("LIVE_PROGRESS", 0, total)
    nextItem()
    return true
end

function ns.StopPriceCheck()
    if queue then finish(false) end
end

function ns.PriceCheckRunning()
    if queue then return done, total end
end

-- ---------------------------------------------------------------- auto scan
-- Opening the AH with old prices starts a scan by itself (on by default; /zug autoscan):
--   with Auctionator: its full scan (the whole AH in one go, which the game allows once every 15 minutes).
--   Auctionator's own autoscan starts it from the AH opening the same way, with no click, so it's allowed.
--   ZugDAQ reads Auctionator's price history, so that's where the scan should land.
--   without Auctionator: ZugDAQ's own check of the watchlist and this character's recipe mats that are stale.
-- Nothing here touches Blizzard's AH window.

local AUTO_DELAY = 3     -- seconds after opening: Auctionator sets up its scan frame (and maybe its own autoscan) first
local MAX_AUTO_ITEMS = 60

local function auctionatorScanFrame()
    local state = Auctionator and Auctionator.State
    local frame = state and state.FullScanFrameRef
    if type(frame) == "table" and type(frame.InitiateScan) == "function" then return frame end
end

-- when the last full AH scan started (Auctionator's record, else ours), or nil
function ns.LastFullScan()
    local a = Auctionator and Auctionator.SavedState and Auctionator.SavedState.TimeOfLastReplicateScan
    local b = ns.db and ns.db.lastAutoScan
    if a and b then return math.max(a, b) end
    return a or b
end

-- the items worth a fresh price without Auctionator: the watchlist, then this character's recipe mats
local function staleItems(maxAge)
    local list, seenIds = {}, {}
    local function add(id)
        if id and not seenIds[id] and #list < MAX_AUTO_ITEMS then
            seenIds[id] = true
            local age = ns.PriceAge(id)
            if not age or age > maxAge then list[#list + 1] = id end
        end
    end
    for id in pairs(ns.db.watch or {}) do add(id) end
    local c = ns.charKey and ns.db.chars[ns.charKey]
    for _, r in pairs(c and c.recipes or {}) do
        for _, slot in ipairs(r.slots or {}) do
            for _, id in ipairs(slot.items or {}) do add(id) end
        end
    end
    return list
end

-- force: /zug autoscan now (still subject to the game's 15 minute limit on full scans)
function ns.AutoScan(force)
    if not ahOpen() then
        if force then ns.Print("open the auction house first.") end
        return
    end
    local maxAge = (ns.settings.autoScanMinutes or 60) * 60
    local last = ns.LastFullScan()
    local age = last and (time() - last)
    if not force and age and age < maxAge then return end
    local ageText = age and ("are " .. ns.AgeText(age) .. " old") or "have never been scanned"

    local frame = auctionatorScanFrame()
    if frame then
        if frame.inProgress then return end
        local ok, can = pcall(frame.CanInitiate, frame)
        if ok and can == false then
            if force then ns.Print("the game allows one full scan every 15 minutes: try again in a few minutes.") end
            return
        end
        ns.Print("AH prices %s: starting an Auctionator full scan (/zug autoscan off to stop this).", ageText)
        if ns.Trace then ns.Trace("autoscan Auctionator full scan") end
        ns.db.lastAutoScan = time()
        local started = pcall(frame.InitiateScan, frame)
        if not started then ns.Print("couldn't start Auctionator's scan: use its Full Scan button.") end
        return
    end

    if ns.PriceCheckRunning() then return end
    local items = staleItems(maxAge)
    if #items == 0 then return end
    ns.Print("checking %d watched items and recipe mats with old prices (install Auctionator for full AH scans).", #items)
    if ns.Trace then ns.Trace("autoscan own check " .. #items) end
    ns.db.lastAutoScan = time()
    ns.CheckPrices(items)
end

ns.On("AUCTION_HOUSE_SHOW", function()
    if not ns.settings.autoScan then return end
    C_Timer.After(AUTO_DELAY, function() ns.AutoScan(false) end)
    C_Timer.After(AUTO_DELAY + 5, function() ns.AutoCheckListings(6) end)
end)

-- ---------------------------------------------------------------- the listings that matter, every visit
-- A full scan gives each item's lowest price; plans need the listings (to cost buying several). On opening the AH,
-- the items that matter get their listings checked: what your plans buy and sell, your watchlist, and what the
-- account's recipes use and make. Anything anyone in the guild checked in the last 15 minutes is skipped (their
-- check came over the guild channel), so the guild shares the work. Shared with the guild as each one finishes.

local MAX_LISTING_CHECKS = 40

local function listingItems()
    local list, seenIds = {}, {}
    local function add(id)
        if id and not seenIds[id] and #list < MAX_LISTING_CHECKS then
            seenIds[id] = true
            if not ns.VendorBuy(id) and not (ns.RecentlyChecked and ns.RecentlyChecked(id)) then list[#list + 1] = id end
        end
    end
    local function fromPlan(plan)
        for _, s in ipairs(plan and plan.steps or {}) do
            if s.k == "BUY" or s.k == "POST" then add(s.id) end
        end
    end
    fromPlan(ns.db.gamePlan)
    local d = ns.AppData and ns.AppData()
    fromPlan(d and d.sale)
    for id in pairs(ns.db.watch or {}) do add(id) end
    for output, makers in pairs(ns.AccountRecipes and ns.AccountRecipes() or {}) do
        add(output)
        for _, m in ipairs(makers) do
            for _, slot in ipairs(m.recipe.slots or {}) do
                for _, id in ipairs(slot.items or {}) do add(id) end
            end
        end
    end
    return list
end

-- waits for a full scan in progress (they share the AH's limits), then checks
function ns.AutoCheckListings(tries)
    if not ns.settings.autoScan or not ahOpen() or ns.PriceCheckRunning() then return end
    local frame = auctionatorScanFrame()
    if frame and frame.inProgress and (tries or 0) > 0 then
        C_Timer.After(10, function() ns.AutoCheckListings(tries - 1) end)
        return
    end
    local items = listingItems()
    if #items == 0 then return end
    if ns.Trace then ns.Trace("auto listing check " .. #items) end
    ns.CheckPrices(items)
end

-- an Auctionator scan finished: whatever shows prices or deals works them out again
local listening
local function listenForScans()
    if listening or not (Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.RegisterForDBUpdate) then return end
    listening = pcall(Auctionator.API.v1.RegisterForDBUpdate, "ZugDAQ", function()
        ns.Fire("SCAN_DONE")
        ns.RequestRefresh()
    end)
end
ns.OnLogin(listenForScans)
