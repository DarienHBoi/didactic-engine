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
