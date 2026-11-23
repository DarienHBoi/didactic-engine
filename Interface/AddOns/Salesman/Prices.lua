local _, S = ...
S.Prices = {}

function S.Prices.available()
    return Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil
        and Auctionator.API.v1.GetAuctionPriceByItemID ~= nil
end

-- Returns {copper=number|nil, ageSecs=number|nil}. Auction price first, then vendor price.
function S.Prices.lookup(itemID)
    if not S.Prices.available() then return {} end
    local v1 = Auctionator.API.v1
    -- Vendor-sold reagents use the vendor price (spec); everything else uses the auction price.
    local okV, vendor = pcall(v1.GetVendorPriceByItemID, "Salesman", itemID)
    if okV and vendor then return { copper = vendor, ageSecs = 0 } end
    local ok, price = pcall(v1.GetAuctionPriceByItemID, "Salesman", itemID)
    if ok and price then
        local okAge, days = pcall(v1.GetAuctionAgeByItemID, "Salesman", itemID)
        -- Auctionator returns nil once a price is older than 21 days: treat as very stale.
        local age = (okAge and days) and days * 86400 or math.huge
        return { copper = price, ageSecs = age }
    end
    return {}
end

-- The numeric item id inside an item link; enchant, spell and junk links give nil.
function S.Prices.itemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("|Hitem:(%d+)")
    return id and tonumber(id) or nil
end

-- Auction-house price only (no vendor price): what a crafted item sells for. Same shape as lookup.
function S.Prices.auction(itemID)
    if not itemID or not S.Prices.available() then return {} end
    local v1 = Auctionator.API.v1
    local ok, price = pcall(v1.GetAuctionPriceByItemID, "Salesman", itemID)
    if not (ok and price) then return {} end
    local okAge, days = pcall(v1.GetAuctionAgeByItemID, "Salesman", itemID)
    return { copper = price, ageSecs = (okAge and days) and days * 86400 or math.huge }
end

-- Auctionator's per-day price history for an item (internal, not its public API, so fully guarded).
-- Rows: { rawDay = "2508", minSeen = copper, maxSeen = copper, available = quantity listed }.
function S.Prices.history(itemID)
    if not itemID then return {} end
    local db = Auctionator and Auctionator.Database
    if type(db) ~= "table" or type(db.GetPriceHistory) ~= "function" then return {} end
    local ok, h = pcall(db.GetPriceHistory, db, tostring(itemID))
    if ok and type(h) == "table" then return h end
    return {}
end
