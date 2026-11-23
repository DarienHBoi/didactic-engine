local _, ns = ...

-- Market views built on Auctionator's price history:
--   watchlist  items you follow, with usual price and whether now is cheap or dear
--   deals      anything from the last scan listed well under its usual price
--   bags       what you're carrying: sell now (price high) or hold (price low)
-- Also keeps a snapshot of bags and bank per character so your item wealth can be valued.

function ns.SetWatched(itemID, on)
    ns.db.watch[itemID] = on and true or nil
    local name = ns.ItemName(itemID) or ("item " .. itemID)
    ns.Print("%s %s the watchlist.", name, on and "added to" or "removed from")
    ns.RequestRefresh()
end

function ns.IsWatched(itemID) return itemID and ns.db.watch[itemID] == true end

local function signal(stats)
    if not stats or not stats.trend or (stats.daysSeen or 0) < 2 then return nil end
    if stats.trend <= ns.settings.dealRatio then return "deal" end
    if stats.trend >= ns.settings.sellHighRatio then return "high" end
    if stats.trend <= ns.settings.holdLowRatio then return "low" end
    return "normal"
end
ns.PriceSignal = signal

function ns.WatchRows()
    local rows = {}
    for itemID in pairs(ns.db.watch) do
        local stats = ns.PriceStats(itemID) or {}
        rows[#rows + 1] = { itemID = itemID, name = ns.ItemName(itemID), stats = stats, signal = signal(stats),
                            owned = ns.OwnedCount(itemID) }
    end
    return rows
end

-- items from a recent scan listed at or below dealRatio of their usual price
function ns.DealRows()
    local rows = {}
    local s = ns.settings
    ns.EachPricedItem(function(itemID, stats)
        if stats.usual and stats.current and stats.daysSeen >= 3 and stats.age and stats.age <= s.dealMaxAge
            and stats.usual >= s.dealMinValue and stats.current <= stats.usual * s.dealRatio then
            rows[#rows + 1] = { itemID = itemID, stats = stats, signal = "deal",
                                saving = stats.usual - stats.current }
        end
    end)
    table.sort(rows, function(a, b) return a.saving > b.saving end)
    for i = #rows, 301, -1 do rows[i] = nil end
    for _, r in ipairs(rows) do r.name = ns.ItemName(r.itemID) end
    return rows
end

-- ---------------------------------------------------------------- bags and bank

local function bagIndexes(kind)
    local list, seen = {}, {}
    local function add(i) if i and not seen[i] then seen[i] = true list[#list + 1] = i end end
    if kind == "bags" then
        for i = 0, (NUM_BAG_SLOTS or 4) do add(i) end
        if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then add(Enum.BagIndex.ReagentBag) end
    elseif kind == "bank" then
        add(BANK_CONTAINER or -1)
        local first = (NUM_BAG_SLOTS or 4) + 1
        for i = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do add(i) end
        add(REAGENTBANK_CONTAINER)
        if Enum and Enum.BagIndex then
            for name, index in pairs(Enum.BagIndex) do
                -- "Bankbag" holds the bank's bags themselves, not their contents
                if type(name) == "string" and name:find("Bank") and not name:find("Account")
                    and not name:find("Bankbag") then add(index) end
            end
        end
    elseif kind == "warbank" then
        if Enum and Enum.BagIndex then
            for name, index in pairs(Enum.BagIndex) do
                if type(name) == "string" and name:find("Account") then add(index) end
            end
        end
    end
    return list
end

-- { [itemID] = count } of sellable items, plus the vendor value of bound ones
local function scan(kind)
    local C = ns.Container()
    if not (C.GetContainerNumSlots and C.GetContainerItemInfo) then return end
    local items, boundValue, any = {}, 0, false
    for _, bag in ipairs(bagIndexes(kind)) do
        local ok, slots = pcall(C.GetContainerNumSlots, bag)
        if ok and slots and slots > 0 then
            any = true
            for slot = 1, slots do
                local info = C.GetContainerItemInfo(bag, slot)
                if type(info) == "table" and info.itemID then
                    local count = info.stackCount or 1
                    if info.isBound then
                        boundValue = boundValue + (ns.VendorSell(info.itemID) or 0) * count
                    else
                        items[info.itemID] = (items[info.itemID] or 0) + count
                    end
                end
            end
        end
    end
    if any then return items, boundValue end
end

local function scanBags()
    local items, bound = scan("bags")
    if not items then return end
    local c = ns.db.chars[ns.charKey]
    c.bags, c.bagsBound = items, bound
    ns.RequestRefresh()
end

local function scanBank()
    local items, bound = scan("bank")
    if items then
        local c = ns.db.chars[ns.charKey]
        c.bank, c.bankBound, c.bankSeen = items, bound, time()
    end
    local war = scan("warbank")
    if war then ns.db.warbank = { items = war, seen = time() } end
    ns.RequestRefresh()
end

ns.OnLogin(function() C_Timer.After(3, scanBags) end)
ns.On("BAG_UPDATE_DELAYED", function() if ns.charKey then ns.Debounce("bags", 1, scanBags) end end)
ns.On("BANKFRAME_OPENED", function() C_Timer.After(0.5, scanBank) end)
ns.On("PLAYERBANKSLOTS_CHANGED", function() ns.Debounce("bank", 1, scanBank) end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
    local enum = Enum and Enum.PlayerInteractionType
    if enum and (kind == enum.Banker or kind == enum.AccountBanker or kind == enum.CharacterBanker) then
        C_Timer.After(0.5, scanBank)
    end
end)

function ns.OwnedCount(itemID)
    local total = 0
    for _, c in pairs(ns.db.chars) do
        total = total + ((c.bags and c.bags[itemID]) or 0) + ((c.bank and c.bank[itemID]) or 0)
    end
    local war = ns.db.warbank.items
    if war then total = total + (war[itemID] or 0) end
    return total
end

-- How many the whole account holds: this character as the game counts it now (bags, bank, reagent bank), every other
-- character's bags and bank as last seen, and the warbank. Mats on a bank alt count, so crafting, costs and plans use
-- everything the player owns, not just who's logged in.
function ns.AccountCount(itemID)
    if not itemID then return 0 end
    local live
    if C_Item and C_Item.GetItemCount then
        live = C_Item.GetItemCount(itemID, true, false, true) -- not the warbank: that's added once, below
    elseif GetItemCount then
        live = GetItemCount(itemID, true)
    end
    local total, sawMe = 0, false
    for key, c in pairs(ns.db and ns.db.chars or {}) do
        if key == ns.charKey and live then
            total, sawMe = total + live, true
        else
            total = total + ((c.bags and c.bags[itemID]) or 0) + ((c.bank and c.bank[itemID]) or 0)
        end
    end
    if live and not sawMe then total = total + live end
    local war = ns.db and ns.db.warbank and ns.db.warbank.items
    if war then total = total + (war[itemID] or 0) end
    return total
end

local function valueOf(items)
    local total = 0
    for itemID, count in pairs(items or {}) do total = total + ns.Value(itemID) * count end
    return total
end

-- item wealth across all characters' bags and banks
function ns.ItemWealth()
    local bags, bank = 0, 0
    for _, c in pairs(ns.db.chars) do
        bags = bags + valueOf(c.bags) + (c.bagsBound or 0)
        bank = bank + valueOf(c.bank) + (c.bankBound or 0)
    end
    bank = bank + valueOf(ns.db.warbank.items)
    return bags + bank, bags, bank
end

-- this character's bag items with their price signal, for the "sell or hold" view
function ns.BagRows()
    local rows = {}
    local c = ns.db.chars[ns.charKey]
    for itemID, count in pairs((c and c.bags) or {}) do
        local stats = ns.PriceStats(itemID) or {}
        local unit = ns.Value(itemID)
        if unit > 0 then
            local vendor = ns.VendorSell(itemID) or 0
            local ah = ns.AuctionPrice(itemID)
            local where = (ah and ah * (1 - ns.settings.ahCut) > vendor) and "AH" or "Vendor"
            rows[#rows + 1] = { itemID = itemID, name = ns.ItemName(itemID), count = count, stats = stats,
                                signal = where == "AH" and signal(stats) or nil, unit = unit, total = unit * count,
                                where = where }
        end
    end
    return rows
end
