local _, root = ...
root.PG = root.PG or {}
local ns = root.PG

local CALLER = "ZugDAQ Professions"

-- used only when nothing better is known: a rough copper value per quality
local GUESS_BY_QUALITY = { [0] = 10, [1] = 100, [2] = 1000, [3] = 10000, [4] = 100000, [5] = 1000000 }

-- how much of a reagent's value still counts when it is already in your bags.
-- Common stuff in your bags is close to free; rare stuff keeps its full weight so it is not burned.
ns.OWNED_FACTOR = { [0] = 0.1, [1] = 0.1, [2] = 0.5, [3] = 1, [4] = 1, [5] = 1 }

ns.SOURCE_LABELS = {
    vendor = "|cff80ff80vendor|r",
    auction = "|cff66bbffauction|r",
    crafted = "|cffffb84dcraft it|r",
    estimate = "|cffaaaaaaestimate|r",
    guess = "|cffff6666guess|r",
}

local function auctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end
function ns.HasAuctionator() return auctionator() ~= nil end

local function auctionPrice(itemID)
    local api = auctionator()
    if api and api.GetAuctionPriceByItemID then
        local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, itemID)
        if ok and type(price) == "number" and price > 0 then return price end
    end
    -- the ZugDAQ app's market price, when it has sent one
    return root.AppPrice and root.AppPrice(itemID) or nil
end

local function vendorPrice(itemID)
    local price = ZugDAQ_ProfDB.vendorPrices[itemID]
    if price then return price end
    local api = auctionator()
    if api and api.GetVendorPriceByItemID then
        local ok, p = pcall(api.GetVendorPriceByItemID, CALLER, itemID)
        if ok and type(p) == "number" and p > 0 then return p end
    end
end

-- modern crafting-reagent tier (1-3), when the client has them
function ns.ReagentTier(itemID)
    local f = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    if not f then return end
    local ok, tier = pcall(f, itemID)
    if ok and type(tier) == "number" and tier > 0 then return tier end
end

local cache = {}
function ns.ResetPriceCache() wipe(cache) end

-- copper per item before weighting, and where the number came from
function ns.BasePrice(itemID)
    local hit = cache[itemID]
    if hit then return hit[1], hit[2] end
    local price, source
    local vendor, auction = vendorPrice(itemID), auctionPrice(itemID)
    if vendor and (not auction or vendor <= auction) then
        price, source = vendor, "vendor"
    elseif auction then
        price, source = auction, "auction"
    else
        local sell = select(11, ns.GetItemInfo(itemID))
        if sell and sell > 0 then
            -- vendor-sell is usually a quarter of what the item goes for
            price, source = sell * 4, "estimate"
        else
            price, source = GUESS_BY_QUALITY[ns.ItemQuality(itemID) or 1] or 100, "guess"
        end
    end
    cache[itemID] = { price, source }
    return price, source
end

-- extra weight for rarer reagents; vendor items are unlimited, so they are never weighted
function ns.QualityWeight(itemID, source)
    if source == "vendor" then return 1 end
    local quality = ns.ItemQuality(itemID) or 1
    local weight = ns.settings.qualityWeight[quality] or 1
    local tier = ns.ReagentTier(itemID)
    -- an auction price already reflects the tier; estimates do not
    if tier and tier > 1 and source ~= "auction" then weight = weight * (1 + 0.5 * (tier - 1)) end
    return weight
end

function ns.OwnedFactor(itemID)
    if not ns.settings.bagDiscount then return 1 end
    return ns.OWNED_FACTOR[ns.ItemQuality(itemID) or 1] or 1
end

-- puts missing reagents on an Auctionator shopping list, or prints them
function ns.MakeShoppingList(title, missing)
    if #missing == 0 then
        ns.Print("you already have every reagent for %s.", title)
        return
    end
    local api = auctionator()
    if api and api.CreateShoppingList and api.ConvertToSearchString then
        local terms = {}
        for _, m in ipairs(missing) do
            local ok, term = pcall(api.ConvertToSearchString, CALLER,
                { searchString = ns.ItemName(m.itemID), isExact = true, quantity = m.count })
            if ok and term then table.insert(terms, term) end
        end
        local ok = pcall(api.CreateShoppingList, CALLER, "ZugDAQ Professions", terms)
        if ok then
            ns.Print("Auctionator shopping list \"ZugDAQ Professions\" now holds the reagents for %s.", title)
            return
        end
    end
    ns.Print("to buy for %s:", title)
    for _, m in ipairs(missing) do
        print(string.format("  %dx %s", m.count, select(2, ns.GetItemInfo(m.itemID)) or ns.ItemName(m.itemID)))
    end
end
