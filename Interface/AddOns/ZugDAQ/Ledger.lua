local _, ns = ...

-- Every change to your gold is recorded under a category. The category comes from either
--   an expectation another module registered just before (an AH sale taken from the mailbox,
--   an item sold to a vendor, a post deposit), or
--   whatever window was open (merchant, mailbox, auction house, loot, trainer, flight master...).

ns.CATEGORY_ORDER = {
    "Auction sales", "Vendor sales", "Looted coin", "Quests", "Mail", "Trades", "Guild bank",
    "Auction purchases", "Auction deposits", "Vendor purchases", "Repairs", "Flights",
    "Postage & sent gold", "Barber", "Other",
}

-- Spending on your character's skills is kept apart from profit and loss: it's an investment,
-- not a trade, and a big riding or profession bill would otherwise hide how your gold-making is going.
ns.SKILL_ORDER = { "Training", "Recipes" }
ns.SKILL_CATEGORIES = { Training = true, Recipes = true }

-- open windows: name -> expiry (GetTime); math.huge while open, a short grace period after closing
local context = {}
local GRACE = 1.5

local function open(name) context[name] = math.huge end
local function close(name) if context[name] then context[name] = GetTime() + GRACE end end
function ns.SetContext(name, seconds) context[name] = GetTime() + (seconds or GRACE) end
function ns.InContext(name)
    local t = context[name]
    return t ~= nil and t > GetTime()
end

local EVENT_CONTEXT = {
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
    AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
    LOOT_OPENED = { "loot", true }, LOOT_CLOSED = { "loot", false },
    TRAINER_SHOW = { "trainer", true }, TRAINER_CLOSED = { "trainer", false },
    TAXIMAP_OPENED = { "taxi", true }, TAXIMAP_CLOSED = { "taxi", false },
    TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
    GUILDBANKFRAME_OPENED = { "guildbank", true }, GUILDBANKFRAME_CLOSED = { "guildbank", false },
    BARBER_SHOP_OPEN = { "barber", true }, BARBER_SHOP_CLOSE = { "barber", false },
    QUEST_COMPLETE = { "quest", true }, QUEST_FINISHED = { "quest", false },
}
for event, info in pairs(EVENT_CONTEXT) do
    ns.On(event, function()
        if info[2] then open(info[1]) else close(info[1]) end
    end)
end

-- the modern client reports most NPC windows through the interaction manager
local INTERACTION_CONTEXT = {
    Merchant = "merchant", MailInfo = "mail", Auctioneer = "auction", Trainer = "trainer",
    TaxiNode = "taxi", TradePartner = "trade", GuildBanker = "guildbank", Barber = "barber",
}
local interactionNames
local function interactionName(kind)
    if not interactionNames then
        interactionNames = {}
        local enum = Enum and Enum.PlayerInteractionType
        if enum then
            for key, ctx in pairs(INTERACTION_CONTEXT) do
                if enum[key] then interactionNames[enum[key]] = ctx end
            end
        end
    end
    return interactionNames[kind]
end
-- the guild bank's gold, whenever a character opens it: the app shows it on its Guild tab. Right after opening, the
-- game may still say 0 until the bank's data arrives, so a 0 then is ignored; GUILDBANK_UPDATE_MONEY is the real figure.
local function readGuildBank(trusted)
    if not ns.db or not GetGuildBankMoney then return end
    local ok, money = pcall(GetGuildBankMoney)
    if not ok or type(money) ~= "number" or (money == 0 and not trusted) then return end
    ns.db.guildBank = {
        money = money, t = time(), by = UnitName("player"),
        guild = GetGuildInfo and (GetGuildInfo("player")) or nil,
    }
end
ns.On("GUILDBANK_UPDATE_MONEY", function() readGuildBank(true) end)
ns.On("GUILDBANKFRAME_OPENED", function() C_Timer.After(1, function() readGuildBank(false) end) end)

ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
    local ctx = interactionName(kind)
    if ctx then open(ctx) end
    if ctx == "guildbank" then C_Timer.After(1, function() readGuildBank(false) end) end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
    local ctx = interactionName(kind)
    if ctx then close(ctx) end
end)

ns.Hook("RepairAllItems", function(guildBank)
    if not guildBank then ns.SetContext("repair", 3) end
end)

-- Expectations: { cat, amount (exact, signed) or sign (+1/-1), detail, expires, onMatch(amount) }
local expected = {}
function ns.ExpectMoney(e)
    e.expires = GetTime() + (e.ttl or 5)
    table.insert(expected, e)
end

local function prune()
    local now = GetTime()
    for i = #expected, 1, -1 do
        if expected[i].expires < now then table.remove(expected, i) end
    end
end

-- returns a list of { e, amount } covering diff, or nil
local function matchExpected(diff)
    prune()
    -- one exact match
    for i, e in ipairs(expected) do
        if e.amount == diff then
            table.remove(expected, i)
            return { { e, diff } }
        end
    end
    -- several exact amounts that arrived as one change
    local sum, picked = 0, {}
    for i, e in ipairs(expected) do
        if e.amount and (e.amount > 0) == (diff > 0) then
            sum = sum + e.amount
            table.insert(picked, i)
            if sum == diff then
                local out = {}
                for j = #picked, 1, -1 do
                    local ex = table.remove(expected, picked[j])
                    table.insert(out, 1, { ex, ex.amount })
                end
                return out
            end
        end
    end
    -- an expectation that only knows the direction
    for i, e in ipairs(expected) do
        if not e.amount and e.sign and (e.sign > 0) == (diff > 0) then
            table.remove(expected, i)
            return { { e, diff } }
        end
    end
end

local function byContext(diff)
    local gain = diff > 0
    if ns.InContext("loot") then return gain and "Looted coin" or "Other" end
    if ns.InContext("repair") and not gain then return "Repairs" end
    if ns.InContext("merchant") then
        if not gain and InRepairMode and InRepairMode() then return "Repairs" end
        return gain and "Vendor sales" or "Vendor purchases"
    end
    if ns.InContext("auction") then return gain and "Auction sales" or "Auction purchases" end
    if ns.InContext("mail") then return gain and "Mail" or "Postage & sent gold" end
    if ns.InContext("quest") and gain then return "Quests" end
    if ns.InContext("trainer") and not gain then return "Training" end
    if ns.InContext("taxi") and not gain then return "Flights" end
    if ns.InContext("trade") then return "Trades" end
    if ns.InContext("guildbank") then return "Guild bank" end
    if ns.InContext("barber") and not gain then return "Barber" end
    return "Other"
end

function ns.Record(cat, amount, detail)
    if not amount or amount == 0 then return end
    local d = ns.Day()
    if amount > 0 then
        d.inc[cat] = (d.inc[cat] or 0) + amount
    else
        d.exp[cat] = (d.exp[cat] or 0) - amount
    end
    local log = ns.db.log
    log[#log + 1] = { t = time(), c = ns.charKey, k = cat, a = amount, d = detail }
    local extra = #log - ns.settings.logLimit
    if extra > 200 then
        local trimmed = {}
        for i = extra + 1, #log do trimmed[#trimmed + 1] = log[i] end
        ns.db.log = trimmed
    end
    ns.Fire("MONEY", cat, amount, detail)
    ns.RequestRefresh()
end

local lastMoney

local function snapshotWealth(money)
    local day = ns.Today()
    ns.db.wealth[day] = ns.db.wealth[day] or {}
    ns.db.wealth[day][ns.charKey] = money
    local c = ns.db.chars[ns.charKey]
    c.money, c.seen = money, time()
end

ns.OnLogin(function()
    lastMoney = GetMoney()
    snapshotWealth(lastMoney)
end)

ns.On("PLAYER_MONEY", function()
    if not lastMoney then return end
    local now = GetMoney()
    local diff = now - lastMoney
    lastMoney = now
    snapshotWealth(now)
    if diff == 0 then return end
    local matched = matchExpected(diff)
    if matched then
        for _, m in ipairs(matched) do
            local e, amount = m[1], m[2]
            ns.Record(e.cat, amount, e.detail)
            if e.onMatch then
                local ok, err = pcall(e.onMatch, amount)
                if not ok then geterrorhandler()(err) end
            end
        end
    else
        ns.Record(byContext(diff), diff)
    end
end)

-- vendor sales, item by item: right-clicking a bag item while a merchant is open sells it
local lastUse, lastUseTime
local function onUseContainerItem(bag, slot)
    if not ns.InContext("merchant") or ns.InContext("repair") then return end
    if InRepairMode and InRepairMode() then return end
    -- the old global and C_Container can both fire for one click
    local key = tostring(bag) .. ":" .. tostring(slot)
    if lastUse == key and lastUseTime == GetTime() then return end
    lastUse, lastUseTime = key, GetTime()
    local C = ns.Container()
    local info = C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
    if type(info) ~= "table" or not info.itemID then return end
    local sell = ns.VendorSell(info.itemID)
    if not sell or (info.hasNoValue) then return end
    local count = info.stackCount or 1
    local name = ns.ItemName(info.itemID) or "item"
    ns.ExpectMoney({
        cat = "Vendor sales",
        amount = sell * count,
        ttl = 4,
        detail = count > 1 and string.format("%s x%d", name, count) or name,
        itemID = info.itemID,
    })
end
if C_Container then ns.Hook(C_Container, "UseContainerItem", onUseContainerItem) end
ns.Hook("UseContainerItem", onUseContainerItem)

-- trainer purchases by name: class skills, profession ranks, riding
ns.Hook("BuyTrainerService", function(index)
    local ok, name = pcall(GetTrainerServiceInfo, index)
    ns.ExpectMoney({ cat = "Training", sign = -1, ttl = 5, detail = ok and name or nil })
end)

-- recipes bought from a vendor count as skills, not as vendor shopping
local function isRecipe(itemID)
    if not itemID then return false end
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not info then return false end
    local ok, _, _, _, _, _, classID = pcall(info, itemID)
    local recipeClass = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
    return ok and classID == recipeClass
end
ns.Hook("BuyMerchantItem", function(index)
    local ok, itemID = pcall(GetMerchantItemID, index)
    if ok and isRecipe(itemID) then
        ns.ExpectMoney({ cat = "Recipes", sign = -1, ttl = 4, detail = ns.ItemName(itemID) })
    end
end)

-- totals for a set of day keys. Profit and loss (inc, exp, income, expense, net) leaves out
-- skills and training; those are in skill (per category) and skills (total spent).
function ns.Totals(dayKeys)
    local inc, exp, skill, online = {}, {}, {}, 0
    for _, key in ipairs(dayKeys) do
        local d = ns.db.days[key]
        if d then
            for cat, v in pairs(d.inc) do
                if ns.SKILL_CATEGORIES[cat] then skill[cat] = (skill[cat] or 0) - v
                else inc[cat] = (inc[cat] or 0) + v end
            end
            for cat, v in pairs(d.exp) do
                if ns.SKILL_CATEGORIES[cat] then skill[cat] = (skill[cat] or 0) + v
                else exp[cat] = (exp[cat] or 0) + v end
            end
            online = online + (d.online or 0)
        end
    end
    local totalInc, totalExp, totalSkill = 0, 0, 0
    for _, v in pairs(inc) do totalInc = totalInc + v end
    for _, v in pairs(exp) do totalExp = totalExp + v end
    for _, v in pairs(skill) do totalSkill = totalSkill + v end
    return { inc = inc, exp = exp, income = totalInc, expense = totalExp, net = totalInc - totalExp,
             skill = skill, skills = totalSkill, online = online }
end

function ns.AllDayKeys()
    local keys = {}
    for key in pairs(ns.db.days) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return a > b end)
    return keys
end

-- gold on hand across characters at the end of a day, carrying each character's last known amount forward
function ns.WealthOn(dayKey)
    local total, found = 0, false
    for char in pairs(ns.db.chars) do
        local best, bestDay
        for day, chars in pairs(ns.db.wealth) do
            if day <= dayKey and chars[char] and (not bestDay or day > bestDay) then
                best, bestDay = chars[char], day
            end
        end
        if best then total, found = total + best, true end
    end
    return found and total or nil
end

function ns.TotalGold()
    local total = 0
    for _, c in pairs(ns.db.chars) do total = total + (c.money or 0) end
    return total
end
