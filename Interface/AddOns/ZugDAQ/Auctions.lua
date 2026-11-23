local _, ns = ...

-- Auction results per item, keyed by item name (that's all the AH mail tells us):
--   posts        auctions you put up        postedUnits  items in them
--   sold         auctions that sold         soldUnits
--   expired      auctions that came back unsold
--   cancelled    auctions you cancelled
--   received     money from sales (after the AH cut, with the deposit returned)
--   cut          AH cut on those sales      deposits    deposits paid when posting
--   bought / boughtUnits / spent           what you paid buying this item on the AH

local function item(name, itemID)
    if not name or name == "" then return end
    local a = ns.db.auctions[name]
    if not a then
        a = { posts = 0, postedUnits = 0, sold = 0, soldUnits = 0, expired = 0, cancelled = 0,
              received = 0, cut = 0, deposits = 0, bought = 0, boughtUnits = 0, spent = 0 }
        ns.db.auctions[name] = a
    end
    a.itemID = a.itemID or itemID or ns.ItemIDFromName(name)
    return a
end
ns.AuctionItem = item

-- per-item history: { t, k = "s" sold / "e" expired / "c" cancelled / "p" posted, u = units, m = money received }
-- Posts are kept so a cancel can be told apart from a cancel-and-relist (undercutting): the app pools the
-- difference with the guild to make its "sold a day" estimates more accurate.
local HISTORY_MAX = 400
local function remember(a, kind, units, money)
    a.history = a.history or {}
    local h = a.history
    h[#h + 1] = { t = time(), k = kind, u = units or 1, m = money or 0 }
    if #h > HISTORY_MAX then table.remove(h, 1) end
end

-- once: rebuild sales history from the transaction log, which has every AH sale with its time
ns.OnLoad(function()
    if ns.db.salesHistoryVersion == 1 then return end
    for _, e in ipairs(ns.db.log) do
        if e.k == "Auction sales" and type(e.d) == "string" and (e.a or 0) > 0 then
            local name, n = e.d:match("^(.-) x(%d+)$")
            name = name or e.d
            local a = ns.db.auctions[name]
            if a then
                a.history = a.history or {}
                table.insert(a.history, { t = e.t, k = "s", u = tonumber(n) or 1, m = e.a })
            end
        end
    end
    for _, a in pairs(ns.db.auctions) do
        if a.history then table.sort(a.history, function(x, y) return x.t < y.t end) end
    end
    ns.db.salesHistoryVersion = 1
end)

-- ---------------------------------------------------------------- posting

local function itemFromLocation(location)
    if not location then return end
    local ok, id = pcall(C_Item.GetItemID, location)
    if not ok then id = nil end
    local okLink, link = pcall(C_Item.GetItemLink, location)
    if not okLink then link = nil end
    id = id or ns.ItemIDFromLink(link)
    local name = id and ns.ItemName(id) or (link and link:match("%[(.-)%]"))
    return id, name
end

local function recordPost(itemID, name, quantity, unitPrice)
    local a = item(name, itemID)
    ns.ExpectMoney({
        cat = "Auction deposits", sign = -1, ttl = 5, detail = name,
        onMatch = function(amount) if a then a.deposits = a.deposits - amount end end,
    })
    if not a then return end
    quantity = tonumber(quantity) or 1
    a.posts = a.posts + 1
    a.postedUnits = a.postedUnits + quantity
    a.lastPostPrice = unitPrice
    a.lastPost = time()
    remember(a, "p", quantity, 0)
    ns.RequestRefresh()
end

if C_AuctionHouse then
    ns.Hook(C_AuctionHouse, "PostItem", function(location, _, quantity, _, buyout)
        local id, name = itemFromLocation(location)
        quantity = tonumber(quantity) or 1
        recordPost(id, name, quantity, buyout and quantity > 0 and buyout / quantity or nil)
    end)
    ns.Hook(C_AuctionHouse, "PostCommodity", function(location, _, quantity, unitPrice)
        local id, name = itemFromLocation(location)
        recordPost(id, name, quantity, unitPrice)
    end)

    -- buying a commodity: the money leaves right away and nothing comes by mail
    ns.Hook(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
        local name = ns.ItemName(itemID)
        local a = item(name, itemID)
        quantity = tonumber(quantity) or 1
        ns.ExpectMoney({
            cat = "Auction purchases", sign = -1, ttl = 15,
            detail = name and string.format("%s x%d", name, quantity),
            onMatch = function(amount)
                if a then
                    a.bought = a.bought + 1
                    a.boughtUnits = a.boughtUnits + quantity
                    a.spent = a.spent - amount
                end
            end,
        })
    end)
    -- buying (or bidding on) an item: it arrives by mail, which is where it's counted per item
    ns.Hook(C_AuctionHouse, "PlaceBid", function(_, bidAmount)
        if bidAmount then ns.ExpectMoney({ cat = "Auction purchases", amount = -bidAmount, ttl = 15 }) end
    end)
end

-- older auction house, in case the client uses it
ns.Hook("PostAuction", function(_, buyout, _, stackSize, numStacks)
    if not GetAuctionSellItemInfo then return end
    local name = GetAuctionSellItemInfo()
    for _ = 1, numStacks or 1 do
        recordPost(nil, name, stackSize or 1, buyout and stackSize and buyout / stackSize)
    end
end)
ns.Hook("PlaceAuctionBid", function(_, _, bid)
    if bid then ns.ExpectMoney({ cat = "Auction purchases", amount = -bid, ttl = 15 }) end
end)

-- ---------------------------------------------------------------- mail

-- "Auction expired: %s" -> "^Auction expired: (.+)$"
local function subjectPattern(fmt)
    if type(fmt) ~= "string" then return end
    local p = fmt:gsub("%%%d?%$?s", "\001")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("\001", "(.+)")
    return "^" .. p .. "$"
end

local SUBJECTS
local function subjects()
    if not SUBJECTS then
        SUBJECTS = {
            sold = subjectPattern(AUCTION_SOLD_MAIL_SUBJECT) or "^Auction successful: (.+)$",
            expired = subjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT) or "^Auction expired: (.+)$",
            cancelled = subjectPattern(AUCTION_REMOVED_MAIL_SUBJECT) or "^Auction cancelled: (.+)$",
            won = subjectPattern(AUCTION_WON_MAIL_SUBJECT) or "^Auction won: (.+)$",
        }
    end
    return SUBJECTS
end

-- "Peacebloom (5)" -> "Peacebloom", 5
local function splitCount(text)
    if not text then return end
    local name, count = text:match("^(.-)%s*%((%d+)%)$")
    if name then return name, tonumber(count) end
    return text, nil
end

-- what's in each mail, read whenever the inbox changes (before anything is taken from it)
local inbox = {}
local function readInbox()
    wipe(inbox)
    local n = GetInboxNumItems and GetInboxNumItems() or 0
    for i = 1, n do
        local _, _, sender, subject, money, _, _, itemCount = GetInboxHeaderInfo(i)
        local invoiceType, itemName, _, bid, _, _, consignment, _, _, count
        if GetInboxInvoiceInfo then
            invoiceType, itemName, _, bid, _, _, consignment, _, _, count = GetInboxInvoiceInfo(i)
        end
        inbox[i] = {
            sender = sender, subject = subject, money = money or 0, itemCount = itemCount or 0,
            invoiceType = invoiceType, itemName = itemName, bid = bid, consignment = consignment,
            count = tonumber(count),
        }
    end
end
ns.On("MAIL_SHOW", readInbox)
ns.On("MAIL_INBOX_UPDATE", readInbox)

local function handleMail(index, takingMoney, takingItems)
    local m = inbox[index]
    if not m or m.done then return end
    local s = subjects()
    local subject = m.subject or ""

    if m.invoiceType == "seller" or (subject:match(s.sold) and m.money > 0) then
        if not takingMoney or m.money <= 0 then return end
        m.done = true
        local name, count = splitCount(m.itemName or subject:match(s.sold))
        count = m.count or count or 1
        local a = item(name)
        if a then
            a.sold = a.sold + 1
            a.soldUnits = a.soldUnits + count
            a.received = a.received + m.money
            a.cut = a.cut + (m.consignment or 0)
            a.lastSale = time()
            if m.bid and count > 0 then a.lastSalePrice = m.bid / count end
            remember(a, "s", count, m.money)
        end
        ns.ExpectMoney({
            cat = "Auction sales", amount = m.money, ttl = 10,
            detail = name and (count > 1 and string.format("%s x%d", name, count) or name),
        })
    elseif m.invoiceType == "buyer" or subject:match(s.won) then
        if not takingItems or m.itemCount <= 0 then return end
        m.done = true
        local name, count = splitCount(m.itemName or subject:match(s.won))
        count = m.count or count or 1
        local a = item(name)
        if a and m.bid then
            a.bought = a.bought + 1
            a.boughtUnits = a.boughtUnits + count
            a.spent = a.spent + m.bid
        end
    elseif subject:match(s.expired) or subject:match(s.cancelled) then
        if not takingItems or m.itemCount <= 0 then return end
        m.done = true
        local expired = subject:match(s.expired) ~= nil
        local name = splitCount(subject:match(expired and s.expired or s.cancelled))
        local a = item(name)
        if a then
            if expired then a.expired = a.expired + 1 else a.cancelled = a.cancelled + 1 end
            a.lastReturn = time()
            remember(a, expired and "e" or "c", m.itemCount, 0)
        end
    end
    ns.RequestRefresh()
end

ns.Hook("TakeInboxMoney", function(index) handleMail(index, true, false) end)
ns.Hook("TakeInboxItem", function(index) handleMail(index, false, true) end)
ns.Hook("AutoLootMailItem", function(index) handleMail(index, true, true) end)
if C_Mail then
    ns.Hook(C_Mail, "TakeInboxMoney", function(index) handleMail(index, true, false) end)
    ns.Hook(C_Mail, "TakeInboxItem", function(index) handleMail(index, false, true) end)
    ns.Hook(C_Mail, "AutoLootMailItem", function(index) handleMail(index, true, true) end)
end

-- ---------------------------------------------------------------- analysis

-- what sold in the last `days` days (0 = all time), per item, from the sales history
--   row: name, itemID, units, money (received after the cut), sold (auctions), back (expired or
--        cancelled), rate (sold / (sold + back)), each, perDay, first, last, sales (newest first)
function ns.SalesRows(days)
    local now = time()
    local since = (days and days > 0) and (now - days * 86400) or 0
    local rows = {}
    local totals = { units = 0, money = 0, sold = 0, back = 0 }
    for name, a in pairs(ns.db.auctions) do
        local units, money, sold, back, first, last = 0, 0, 0, 0, nil, nil
        local sales = {}
        for _, h in ipairs(a.history or {}) do
            if h.t >= since then
                if h.k == "s" then
                    units, money, sold = units + h.u, money + h.m, sold + 1
                    first = first and math.min(first, h.t) or h.t
                    last = last and math.max(last, h.t) or h.t
                    table.insert(sales, 1, h)
                else
                    back = back + 1
                end
            end
        end
        totals.units, totals.money = totals.units + units, totals.money + money
        totals.sold, totals.back = totals.sold + sold, totals.back + back
        if sold > 0 then
            local span = (days and days > 0) and days or math.max(1, (now - first) / 86400)
            rows[#rows + 1] = {
                name = name, itemID = a.itemID, a = a, units = units, money = money, sold = sold, back = back,
                rate = sold / (sold + back), each = units > 0 and money / units or 0, perDay = units / span, -- old records can have sales with no unit count
                first = first, last = last, sales = sales,
            }
        end
    end
    totals.rate = (totals.sold + totals.back) > 0 and totals.sold / (totals.sold + totals.back) or nil
    return rows, totals
end

-- how an item is doing on the AH, and what to do about it
function ns.AuctionVerdict(a)
    local outcomes = a.sold + a.expired + a.cancelled
    local sellThrough = outcomes > 0 and a.sold / outcomes or nil
    local avgBuy = a.boughtUnits > 0 and a.spent / a.boughtUnits or nil
    local cost = avgBuy and avgBuy * a.soldUnits or 0
    local profit = a.received - a.deposits - cost
    local verdict, color
    if outcomes < 3 then
        verdict, color = "Not enough data", "|cffaaaaaa"
    elseif profit < 0 then
        verdict, color = "Losing money", "|cffff5050"
    elseif sellThrough >= 0.85 and a.sold >= 3 then
        verdict, color = "Sells fast - try higher", "|cff40ff40"
    elseif sellThrough >= 0.5 then
        verdict, color = "Working - keep going", "|cff40ff40"
    elseif sellThrough >= 0.25 then
        verdict, color = "Slow - price lower", "|cffffd200"
    else
        verdict, color = "Rarely sells - drop it?", "|cffff8040"
    end
    return {
        outcomes = outcomes,
        sellThrough = sellThrough,
        avgBuy = avgBuy,
        avgSale = a.soldUnits > 0 and a.received / a.soldUnits or nil,
        profit = profit,
        verdict = verdict,
        color = color,
    }
end

-- ---------------------------------------------------------------- what's up for sale now
--
-- Each character's open auctions, as the game lists them (the AH's Auctions tab): the app shares them with the guild,
-- so guildmates can see who's selling what and don't undercut each other, and plans sales around them.
--   ns.db.chars[key].listings = { t = when seen, items = { { i = itemID, q = quantity, b = buyout, l = seconds left } } }
-- The buyout is as the game gives it (for a commodity that's per unit); the app works the unit price out.

local function snapshotOwned()
    if not (ns.db and ns.charKey and C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions) then return end
    local c = ns.db.chars[ns.charKey]
    if not c then return end
    local active = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Active or 0
    local items = {}
    for index = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
        local a = C_AuctionHouse.GetOwnedAuctionInfo(index)
        local id = a and a.itemKey and a.itemKey.itemID
        if id and a.status == active then
            items[#items + 1] = { i = id, q = a.quantity or 1, b = a.buyoutAmount or a.bidAmount or 0, l = a.timeLeftSeconds }
        end
        if #items >= 200 then break end
    end
    c.listings = { t = time(), items = items }
    if ns.Trace then ns.Trace("own auctions " .. #items) end
end

local function askForOwned()
    if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then pcall(C_AuctionHouse.QueryOwnedAuctions, {}) end
end

ns.On("OWNED_AUCTIONS_UPDATED", function() ns.Debounce("ownedauctions", 0.5, snapshotOwned) end)
-- opening the AH, and after posting: ask the game for the list (the Auctions tab does the same)
ns.On("AUCTION_HOUSE_SHOW", function() C_Timer.After(2, askForOwned) end)
ns.On("AUCTION_HOUSE_AUCTION_CREATED", function() ns.Debounce("ownedask", 2, askForOwned) end)
