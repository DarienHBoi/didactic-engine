local _, P = ...
P.Adapters = {}
local A = P.Adapters

-- Auctionator's per-day history (internal, read the way Salesman/Prices.lua does): { rawDay, minSeen, maxSeen, available }.
function A.history(itemID)
    if not itemID then return {} end
    local db = Auctionator and Auctionator.Database
    if type(db) ~= "table" or type(db.GetPriceHistory) ~= "function" then return {} end
    local ok, h = pcall(db.GetPriceHistory, db, tostring(itemID))
    return (ok and type(h) == "table") and h or {}
end

-- Auctionator's posting history: { rawDay = time, price (per unit, verified in its source), quantity }.
function A.posts(itemID)
    if not itemID then return {} end
    local ph = Auctionator and Auctionator.PostingHistory
    if type(ph) ~= "table" or type(ph.GetPriceHistory) ~= "function" then return {} end
    local ok, h = pcall(ph.GetPriceHistory, ph, tostring(itemID))
    return (ok and type(h) == "table") and h or {}
end

-- Item ids Auctionator has posting records for (plain numeric keys only).
function A.postedIDs()
    local out = {}
    local ph = Auctionator and Auctionator.PostingHistory
    if type(ph) == "table" and type(ph.db) == "table" then
        local ok = pcall(function()
            for k in pairs(ph.db) do
                local n = type(k) == "string" and k:match("^%d+$") and tonumber(k)
                if n then out[#out + 1] = n end
            end
        end)
        if not ok then return {} end
    end
    return out
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local r = { pcall(fn, ...) }
    if r[1] then return unpack(r, 2, 15) end -- explicit range: GetItemInfo returns nils in the middle
    return nil
end

-- Item name, quality, item level, classID, vendor sell price, bindType through the client (guarded). WoW Forever has
-- C_Item.GetItemInfo and may not have the global GetItemInfo: use the C_Item one first, the global as fallback.
-- `link` (optional) is the item link; with it the real item level comes from C_Item.GetDetailedItemLevelInfo, because a
-- scaled item's base level (read by id) can be in the wrong disenchant bracket.
-- All fields nil while the client has not cached the item.
local function plainNumber(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return type(v) == "number" and v > 0 and v or nil
end

function A.itemInfo(id, link)
    local arg = id
    if type(link) == "string" and not (issecretvalue and issecretvalue(link)) then arg = link end
    local name, quality, ilvl, vendor, classID, bindType
    local tried = {}
    if C_Item and type(C_Item.GetItemInfo) == "function" then tried[#tried + 1] = C_Item.GetItemInfo end
    if type(GetItemInfo) == "function" then tried[#tried + 1] = GetItemInfo end
    for _, fn in ipairs(tried) do
        local r = { pcall(fn, arg) }
        if r[1] and r[2] ~= nil then
            name, quality, ilvl, vendor, classID, bindType = r[2], r[4], r[5], r[12], r[13], r[15]
            break
        end
    end
    if arg == link and C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function" then
        local okD, detailed = pcall(C_Item.GetDetailedItemLevelInfo, link)
        detailed = okD and plainNumber(detailed) or nil
        if detailed then ilvl = detailed end
    end
    return { name = name, quality = quality, ilvl = ilvl, classID = classID, vendor = vendor, bindType = bindType }
end

-- Asks the client to load an item (GET_ITEM_INFO_RECEIVED fires when it arrives).
function A.requestItem(id)
    if C_Item and C_Item.RequestLoadItemDataByID then call(C_Item.RequestLoadItemDataByID, id) end
end

-- Auctionator's last-scan lowest price and its age in scan days, by public API (guarded; nil, nil when unavailable).
function A.auctionPrice(id)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if type(api) ~= "table" or type(id) ~= "number" then return nil, nil end
    local price = call(api.GetAuctionPriceByItemID, "Pricewatch", id)
    if type(price) ~= "number" or price <= 0 then return nil, nil end
    local age = call(api.GetAuctionAgeByItemID, "Pricewatch", id)
    return price, type(age) == "number" and age or nil
end

-- The age (scan days) of Auctionator's price for one item, or nil. Read lazily, only for items that matter.
function A.listedAge(id)
    local d = Auctionator and Auctionator.Database
    if type(d) ~= "table" or type(d.GetPriceAge) ~= "function" or type(id) ~= "number" then return nil end
    local ok, age = pcall(d.GetPriceAge, d, tostring(id))
    return (ok and type(age) == "number") and age or nil
end

-- Every item Auctionator has a price for: { {id, price} } (the age is read later, by A.listedAge). Reads its saved price table (Auctionator.Database.db,
-- keys are the plain item id as a string; "g:id:ilvl" / "gr:..." gear variants are skipped). Guarded: empty on any surprise.
function A.listedItems()
    local out = {}
    local d = Auctionator and Auctionator.Database
    if type(d) ~= "table" or type(d.db) ~= "table" then return out end
    pcall(function()
        for key, entry in pairs(d.db) do
            local id = type(key) == "string" and key:match("^%d+$") and tonumber(key)
            local price = id and type(entry) == "table" and entry.m
            if id and type(price) == "number" and price > 0 then
                out[#out + 1] = { id = id, price = price }
            end
        end
    end)
    return out
end

-- The character's Enchanting skill, or nil when it cannot be told (no profession API, or the character has no Enchanting).
function A.enchantingSkill()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
    local ok, skill = pcall(function()
        for _, index in ipairs({ GetProfessions() }) do
            local _, _, rank, _, _, _, line = GetProfessionInfo(index)
            if line == 333 and type(rank) == "number" then return rank end
        end
    end)
    return ok and skill or nil
end

-- Salesman (optional): every call guarded; absent = empty.
function A.salesmanRecipes()
    local api = SalesmanAPI
    if type(api) ~= "table" then return {} end
    local r = call(api.recipes)
    return type(r) == "table" and r or {}
end

-- Items that ever had an AH sale in Salesman's mail log: one call into Salesman. An older Salesman without that call is
-- asked per crafted item instead.
function A.salesmanSoldIDs()
    local api = SalesmanAPI
    if type(api) ~= "table" then return {} end
    if type(api.soldItemIDs) == "function" then
        local r = call(api.soldItemIDs)
        return type(r) == "table" and r or {}
    end
    local out = {}
    for _, r in ipairs(A.salesmanRecipes()) do
        if #A.salesmanSales(r.itemID) > 0 then out[#out + 1] = r.itemID end
    end
    return out
end

function A.salesmanSales(id)
    local api = SalesmanAPI
    if type(api) ~= "table" then return {} end
    local r = call(api.sales, id)
    return type(r) == "table" and r or {}
end

-- Sold, expired and cancelled counts for one item from Salesman's mail log: { sold, expired, cancelled, avgSold, ... } or nil.
-- The client's deposit for listing one item for 24 h (copper), or nil. UNVERIFIED on WoW Forever: the retail-style
-- C_AuctionHouse.CalculateItemDeposit is tried (item id, duration 2 = 24h, quantity 1); any error or non-number gives nil
-- and the caller estimates instead (P.Reco.deposit).
function A.auctionDeposit(id)
    local api = C_AuctionHouse
    if type(api) ~= "table" then return nil end
    local d = call(api.CalculateItemDeposit, id, 2, 1)
    if type(d) == "number" and d >= 0 then return d end
    return nil
end

function A.salesmanOutcomes(id)
    local api = SalesmanAPI
    if type(api) ~= "table" then return nil end
    local r = call(api.outcomes, id)
    return type(r) == "table" and r or nil
end

function A.salesmanProfit(id)
    local api = SalesmanAPI
    if type(api) ~= "table" then return nil end
    local r = call(api.profit, id)
    return type(r) == "table" and r or nil
end

function A.hour()
    return tonumber(call(date, "%H"))
end

-- What the player carries: { {id, count, bound} } grouped by item and bound state, sorted by id then unbound first. Bags 0 to
-- NUM_BAG_SLOTS through C_Container (guarded; empty when anything is missing or throws).
function A.bagItems()
    local C = C_Container
    if type(C) ~= "table" or type(C.GetContainerNumSlots) ~= "function" or type(C.GetContainerItemInfo) ~= "function" then return {} end
    local by, list = {}, {}
    local okAll = pcall(function()
        for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
            for slot = 1, C.GetContainerNumSlots(bag) or 0 do
                local info = C.GetContainerItemInfo(bag, slot)
                local id = type(info) == "table" and plainNumber(info.itemID)
                if id then
                    local bound = info.isBound == true
                    local key = id .. (bound and "b" or "u")
                    local e = by[key]
                    if not e then e = { id = id, count = 0, bound = bound }; by[key] = e; list[#list + 1] = e end
                    e.count = e.count + (plainNumber(info.stackCount) or 1)
                end
            end
        end
    end)
    if not okAll then return {} end
    table.sort(list, function(a, b) if a.id ~= b.id then return a.id < b.id end return (not a.bound) and b.bound end)
    return list
end

-- The first bag item whose link shows this name: id, link (guarded; nil when none). The disenchant logger uses it for the target
-- name UNIT_SPELLCAST_SENT gives.
function A.bagItemByName(name)
    local C = C_Container
    if type(name) ~= "string" or name == "" or type(C) ~= "table" or type(C.GetContainerNumSlots) ~= "function"
        or type(C.GetContainerItemInfo) ~= "function" then return nil end
    local okAll, id, link = pcall(function()
        for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
            for slot = 1, C.GetContainerNumSlots(bag) or 0 do
                local info = C.GetContainerItemInfo(bag, slot)
                local l = type(info) == "table" and info.hyperlink
                if type(l) == "string" and not (issecretvalue and issecretvalue(l)) and l:match("%[(.-)%]") == name then
                    return plainNumber(info.itemID) or tonumber(l:match("item:(%d+)")), l
                end
            end
        end
    end)
    if okAll and id then return id, link end
    return nil
end

-- The open loot window as { { id, qty, link, slot } } (guarded; money and currency slots have no item link and are left out).
function A.lootItems()
    local out = {}
    if type(GetNumLootItems) ~= "function" or type(GetLootSlotLink) ~= "function" then return out end
    pcall(function()
        for i = 1, GetNumLootItems() or 0 do
            local link = GetLootSlotLink(i)
            if type(link) == "string" and not (issecretvalue and issecretvalue(link)) then
                local id = tonumber(link:match("item:(%d+)"))
                local qty = 1
                if type(GetLootSlotInfo) == "function" then
                    local okI, _, _, q = pcall(GetLootSlotInfo, i)
                    q = okI and plainNumber(q)
                    if q then qty = q end
                end
                if id then out[#out + 1] = { id = id, qty = qty, link = link, slot = i } end
            end
        end
    end)
    return out
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Auction house searches (sold tracker). Modern C_AuctionHouse only (what Auctionator uses on Forever); every call guarded.
-- Never buys, bids, cancels or touches AuctionHouseFrame.
local function AH() return type(C_AuctionHouse) == "table" and C_AuctionHouse or nil end
A.SEARCH_READ_MAX = 400 -- result rows read per search (the cheapest MARKET_MAX_ROWS are kept)

-- The variant a search was for: "itemLevel:suffix" for an item key, "c" for a commodity.
function A.keySig(itemKey)
    if type(itemKey) ~= "table" then return "c" end
    local lvl, sfx = plainNumber(itemKey.itemLevel) or 0, plainNumber(itemKey.itemSuffix) or 0
    return lvl .. ":" .. sfx
end

local function readRows(numFn, infoFn, arg)
    local out = {}
    local ok, n = pcall(numFn, arg)
    n = ok and plainNumber(n) or 0
    for i = 1, math.min(n, A.SEARCH_READ_MAX) do
        local okI, info = pcall(infoFn, arg, i)
        if okI and type(info) == "table" then out[#out + 1] = info end
    end
    return out
end

-- False when the client says it has no results for the key (it sometimes answers a search with nothing although
-- there are listings; Auctionator searches again then). True when the call is missing.
local function hasResults(ah, itemKey)
    if type(ah.HasSearchResults) ~= "function" then return true end
    local ok, has = pcall(ah.HasSearchResults, itemKey)
    return not (ok and has == false)
end

-- Rows and whether they are complete, for an item search (item key) or a commodity search (item id). {} and false
-- when the client lacks the calls.
function A.itemResults(itemKey)
    local ah = AH()
    if not ah or type(itemKey) ~= "table" or type(ah.GetNumItemSearchResults) ~= "function"
        or type(ah.GetItemSearchResultInfo) ~= "function" then return {}, false end
    local okF, full = pcall(ah.HasFullItemSearchResults, itemKey)
    full = okF and full == true and hasResults(ah, itemKey)
    return readRows(ah.GetNumItemSearchResults, ah.GetItemSearchResultInfo, itemKey), full
end

function A.commodityResults(itemID)
    local ah = AH()
    if not ah or type(itemID) ~= "number" or type(ah.GetNumCommoditySearchResults) ~= "function"
        or type(ah.GetCommoditySearchResultInfo) ~= "function" then return {}, false end
    local okF, full = pcall(ah.HasFullCommoditySearchResults, itemID)
    if okF and full == true and type(ah.MakeItemKey) == "function" then
        local okK, key = pcall(ah.MakeItemKey, itemID)
        if okK and type(key) == "table" then full = hasResults(ah, key) end
    end
    return readRows(ah.GetNumCommoditySearchResults, ah.GetCommoditySearchResultInfo, itemID), okF and full == true
end

-- Auctionator views that rebuild their list from any search result for their item: Rescan waits while one is shown.
A.AUCTIONATOR_BUSY = { "AuctionatorSellingFrame", "AuctionatorBuyItemFrame", "AuctionatorBuyCommodityFrame" }
local function auctionatorBusy()
    for _, name in ipairs(A.AUCTIONATOR_BUSY) do
        local fr = _G[name]
        if type(fr) == "table" and type(fr.IsVisible) == "function" then
            local ok, shown = pcall(fr.IsVisible, fr)
            if ok and shown == true then return true end
        end
    end
    return false
end

-- The client side of P.Rescan (see Rescan.lua). nil when the client has no modern search calls.
function A.searchClient()
    local ah = AH()
    if not ah or type(ah.SendSearchQuery) ~= "function" or type(ah.MakeItemKey) ~= "function" then return nil end
    local sortOrder = type(Enum) == "table" and type(Enum.AuctionHouseSortOrder) == "table" and Enum.AuctionHouseSortOrder.Price or 0
    return {
        key = function(id) return ah.MakeItemKey(id) end,
        keyReady = function(key)
            if type(ah.GetItemKeyInfo) ~= "function" then return true end
            return ah.GetItemKeyInfo(key) ~= nil
        end,
        ready = function()
            if auctionatorBusy() then return false end
            if type(ah.IsThrottledMessageSystemReady) ~= "function" then return true end
            return ah.IsThrottledMessageSystemReady() == true
        end,
        send = function(key)
            -- splitOwnedItems = true, as Auctionator's own searches of the same key
            ah.SendSearchQuery(key, { { sortOrder = sortOrder, reverseSort = false } }, true)
            return true
        end,
        requestMore = function(id, key, kind)
            -- One throttled call only: the kind the result event said, else Enum.ItemCommodityStatus (2 commodity),
            -- else an item search.
            if kind ~= "commodity" and kind ~= "item" then
                local okS, status = pcall(ah.GetItemCommodityStatus, id)
                kind = (okS and plainNumber(status) == 2) and "commodity" or "item"
            end
            if kind == "commodity" then
                if type(ah.RequestMoreCommoditySearchResults) ~= "function" then return false end
                return (pcall(ah.RequestMoreCommoditySearchResults, id))
            end
            if type(ah.RequestMoreItemSearchResults) ~= "function" or not key then return false end
            return (pcall(ah.RequestMoreItemSearchResults, key))
        end,
    }
end

-- ZugHistory (optional, ZugCompanion): long server-wide history, one value per day, up to 90 days. Spec:
-- ZugCompanion/PRICEWATCH-ADAPTER.md. { median, low, high, n, sold, age } over `days` (default 30), or nil: module 'zugdaq' off,
-- addon missing, no history for the item, or its newest snapshot older than P.Config.ZUG_STALE_DAYS. Never throws.
local function zugHistoryFresh()
    if P.Mod and not P.Mod.on("zugdaq") then return nil end
    local Z = ZugHistory
    if type(Z) ~= "table" or type(Z.info) ~= "function" then return nil end
    local info = Z.info()
    if type(info) ~= "table" then return nil end
    local age = info.age -- 0 = today, so not plainNumber (which drops 0)
    if type(age) ~= "number" or (issecretvalue and issecretvalue(age)) then age = nil end
    if age and age > P.Config.ZUG_STALE_DAYS then return nil end
    return Z, age
end
function A.zugHistory(id, days)
    if type(id) ~= "number" then return nil end
    local ok, res = pcall(function()
        local Z, age = zugHistoryFresh()
        if not Z or type(Z.stats) ~= "function" then return nil end
        local s = Z.stats(id, days or 30)
        if type(s) ~= "table" or not plainNumber(s.median) then return nil end
        return { median = s.median, low = plainNumber(s.low), high = plainNumber(s.high), n = plainNumber(s.n) or 0,
            sold = plainNumber(s.sold), age = age }
    end)
    return ok and res or nil
end

-- The same history as graph points on Pricewatch's day scale: { { day, value }, ... } oldest first, or nil.
function A.zugHistorySeries(id, e0)
    if type(id) ~= "number" then return nil end
    local ok, res = pcall(function()
        local Z = zugHistoryFresh()
        if not Z or type(Z.series) ~= "function" then return nil end
        local list = Z.series(id)
        if type(list) ~= "table" then return nil end
        local out = {}
        for _, p in ipairs(list) do
            local t, v = plainNumber(p.t), plainNumber(p.market)
            local day = t and P.Days.dayOf(t, e0 or P.Days.epoch0())
            if day and v and v > 0 then out[#out + 1] = { day = day, value = v } end
        end
        table.sort(out, function(a, b) return a.day < b.day end)
        return out
    end)
    return ok and res or nil
end

-- The live lot scan's client (P.LotScan): browse uncommon-epic armor/weapons, item searches, paging. Every call is ours while
-- A.lotOwn is set, so the hook in UI/Deals.lua can tell our queries from another addon's or the player's.
A.lotOwn = false
function A.lotClient()
    local ah = AH()
    if not ah or type(ah.SendBrowseQuery) ~= "function" or type(ah.SendSearchQuery) ~= "function" then return nil end
    local base = A.searchClient()
    local sortOrder = type(Enum) == "table" and type(Enum.AuctionHouseSortOrder) == "table" and Enum.AuctionHouseSortOrder.Price or 0
    local function own(fn, ...)
        A.lotOwn = true
        local r = { pcall(fn, ...) }
        A.lotOwn = false
        if not r[1] then error(r[2], 0) end
        return unpack(r, 2)
    end
    local function filters()
        local F = type(Enum) == "table" and Enum.AuctionHouseFilter
        if type(F) ~= "table" then return {} end
        local out = {}
        for _, k in ipairs({ "UncommonQuality", "RareQuality", "EpicQuality" }) do if F[k] then out[#out + 1] = F[k] end end
        return out
    end
    return {
        ready = base and base.ready or function() return true end,
        keyReady = function(key) if type(ah.GetItemKeyInfo) ~= "function" then return true end return ah.GetItemKeyInfo(key) ~= nil end,
        browse = function()
            own(ah.SendBrowseQuery, { searchString = "", sorts = { { sortOrder = sortOrder, reverseSort = false } }, filters = filters(),
                itemClassFilters = { { classID = 2 }, { classID = 4 } } })
            return true
        end,
        browseFull = function() return type(ah.HasFullBrowseResults) ~= "function" or ah.HasFullBrowseResults() == true end,
        browseMore = function() own(ah.RequestMoreBrowseResults) return true end,
        browseResults = function() return ah.GetBrowseResults() end,
        search = function(key) own(ah.SendSearchQuery, key, { { sortOrder = sortOrder, reverseSort = false } }, true) return true end,
        searchFull = function(key) return type(ah.HasFullItemSearchResults) ~= "function" or ah.HasFullItemSearchResults(key) == true end,
        searchMore = function(key) own(ah.RequestMoreItemSearchResults, key) return true end,
        searchResults = function(key)
            local n = plainNumber(ah.GetNumItemSearchResults(key)) or 0
            local out = {}
            for i = 1, math.min(n, 500) do
                local ok, info = pcall(ah.GetItemSearchResultInfo, key, i)
                if ok and type(info) == "table" then out[#out + 1] = info end
            end
            return out
        end,
    }
end

-- ---------------------------------------------------------------------------------------------------------------------
-- ZugDAQ (optional). Its desktop app writes the global ZugDAQ_AppData (Data\FromApp.lua, nil when the app is not used); shape from
-- ZugDAQ 2.0.3 Bridge.lua: { version, made (unix time written), snapshot (unix time of the AH snapshot),
-- prices = { [itemID] = { market, avg7, lowest, soldPerDay, trend } } } with the price row POSITIONAL: [1] market, [2] avg7 (its "usual"),
-- [3] lowest, [4] soldPerDay, [5] trend. ZugDAQ itself only uses the data when it is a table with a version. Read-only; never written.
local function finite(v)
    v = plainNumber(v)
    return v and v < math.huge and v or nil
end

-- True when the ZugDAQ addon is loaded (C_AddOns first, the old global as fallback). Unknown (neither exists) counts as loaded,
-- because the data global only exists when its file ran.
local function zugLoaded()
    local fn = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(fn) ~= "function" then return true end
    local ok, loaded = pcall(fn, "ZugDAQ")
    return ok and loaded and true or false
end

local function zugData()
    if not zugLoaded() then return nil end
    local d = ZugDAQ_AppData
    if type(d) == "table" and d.version then return d end
    return nil
end

-- Does ZugDAQ's own item tooltip carry its market line for this item? It adds the lines whenever the app data is there and has a
-- price row for the item (Bridge.lua addLines), whatever the data's age. Used to avoid showing the same number twice.
function A.zugShows(id)
    if type(id) ~= "number" then return false end
    local ok, shown = pcall(function()
        local d = zugData()
        return d ~= nil and type(d.prices) == "table" and type(d.prices[id]) == "table"
    end)
    return ok and shown == true
end

-- ZugDAQ's figures for one item: { market, avg7, perDay, age } (copper per unit, copper, units sold a day, whole days since its AH
-- snapshot or nil when it has no usable timestamp), or nil: module switched off, ZugDAQ not loaded, no app data, malformed row, no
-- market price, or older than P.Config.ZUG_STALE_DAYS. Every field type-checked; never throws.
function A.zug(id)
    if type(id) ~= "number" then return nil end
    if P.Mod and not P.Mod.on("zugdaq") then return nil end
    local ok, res = pcall(function()
        local d = zugData()
        local row = d and type(d.prices) == "table" and d.prices[id]
        if type(row) ~= "table" then return nil end
        local market = finite(row[1])
        if not market then return nil end
        local age
        local stamp = finite(d.snapshot) or finite(d.made)
        if stamp then
            local days = math.max(0, (time() - stamp) / 86400)
            if days > P.Config.ZUG_STALE_DAYS then return nil end
            age = math.floor(days)
        end
        -- [5] trend (current / usual) is not read: in real data it is always 1 or nil (owner check 2026-11-21)
        return { market = market, avg7 = finite(row[2]), lowest = finite(row[3]), perDay = finite(row[4]), age = age }
    end)
    return ok and res or nil
end
