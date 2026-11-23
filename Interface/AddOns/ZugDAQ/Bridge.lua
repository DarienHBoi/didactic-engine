local _, ns = ...

-- The way in from the ZugDAQ app. The app writes Data\FromApp.lua (ZugDAQ_AppData) whenever its market data or
-- your plans change; the game reads it at login and on /reload. The way out is this addon's saved data, which the
-- app reads every time the game saves it.
--
--   ZugDAQ_AppData = {
--     version, made (unix time written), snapshot (unix time of the AH snapshot), house, cut,
--     prices = { [itemID] = { market, avg7, lowest, soldPerDay, trend } },
--     deals  = { { kind = "vendor"|"under"|"thin", id, units, max, cost, resell, profit, sold } },
--     sell   = { { id, title, detail, gold } },                       -- what the app says to sell
--     plan   = { title, char, prof, steps = { { id, spell, name, crafts, from, to, learn } },
--                shop = { { id, buy, have, each, where } } },         -- the plan open in the app
--     cycles = { [itemID] = { cheapWeekday, dearWeekday } },         -- 0 = Sunday, server days
--     bestHour = local hour the whole AH buys most (start of a 3 hour window),
--     trade  = { { id, who, count, give } },                          -- guild trade matches
--     guild  = { { name, realm, class, level, race, guild, profs, week, today, seen, you } }, -- the guild board
--     sale   = { made, id, qty, price, spend, revenue, steps = { { k = COLLECT|BUY|CRAFT|POST, id, q, t, d, g } } }, -- Desk planner
--     listed = { [itemID] = { { who, count, each } } },                 -- guildmates' open auctions
--     verdicts = { [itemID] = { SELL|HOT|HOLD|VENDOR|GUILD|KEEP, why } },  -- what to do with what you hold
--     pooled = { [itemID] = { t, by, total, l = { { price, qty } } } },  -- the guild's in-game price checks
--     addon = the addon version the app ships, installed = the version in the AddOns folder (newer than this: /reload)
--   }

local function data()
    local d = ZugDAQ_AppData
    if type(d) == "table" and d.version then return d end
end

function ns.AppData() return data() end

-- the app's market price for one (copper), when it has sent one
function ns.AppPrice(itemID)
    local d = data()
    local p = d and d.prices and itemID and d.prices[itemID]
    if p and p[1] and p[1] > 0 then return p[1] end
end

function ns.AppStats(itemID)
    local d = data()
    local p = d and d.prices and itemID and d.prices[itemID]
    if not p then return end
    return { market = p[1], usual = p[2], lowest = p[3], soldPerDay = p[4], trend = p[5] }
end

-- "sent 12 minutes ago" for the app's data
function ns.AppAge()
    local d = data()
    if not d or not d.made then return end
    local mins = math.floor((time() - d.made) / 60)
    if mins < 1 then return "just now" end
    if mins < 90 then return mins .. " minutes ago" end
    local hours = math.floor(mins / 60 + 0.5)
    if hours < 48 then return hours .. " hours ago" end
    return math.floor(hours / 24 + 0.5) .. " days ago"
end

local function count(n)
    if not n then return "?" end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    if n >= 10 then return string.format("%d", n) end
    return string.format("%.1f", n)
end

local DAYS = { [0] = "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

-- ---------------------------------------------------------------- item tooltips

local dealByItem
local function dealFor(itemID)
    local d = data()
    if not d then return end
    if not dealByItem then
        dealByItem = {}
        for _, deal in ipairs(d.deals or {}) do
            if deal.id and (not dealByItem[deal.id] or deal.profit > dealByItem[deal.id].profit) then dealByItem[deal.id] = deal end
        end
    end
    return dealByItem[itemID]
end

-- guildmates with it up on the AH (from the app): don't undercut them
local function addGuildListings(tip, itemID)
    local d = data()
    local listed = d and d.listed and d.listed[itemID]
    if not listed or #listed == 0 then return end
    for i, l in ipairs(listed) do
        if i > 3 then break end
        tip:AddDoubleLine(i == 1 and "   Guild selling" or " ", string.format("%s: %d at %s", l[1] or "?", l[2] or 0, ns.Money(l[3] or 0)),
            0.8, 0.8, 0.8, 0.6, 0.85, 1)
    end
end

-- what to do with it, from the app (only for things you hold): sell, hold, vendor, trade to the guild, or craft with it
local VERDICT = {
    SELL = "|cff40ff40SELL|r", HOT = "|cffff8000SELL NOW|r", HOLD = "|cff66bbffHOLD|r", VENDOR = "|cffaaaaaaVENDOR|r",
    GUILD = "|cffc080ffGUILD|r", KEEP = "|cffffd200KEEP|r",
}
local function addVerdict(tip, itemID)
    local d = data()
    local v = d and d.verdicts and d.verdicts[itemID]
    if not v or not v[1] then return end
    tip:AddLine("|cffffd700ZugDAQ:|r " .. (VERDICT[v[1]] or v[1]) .. "  |cffdddddd" .. (v[2] or "") .. "|r", 1, 1, 1, true)
end

local function addLines(tip, itemID)
    addVerdict(tip, itemID)
    local s = ns.AppStats(itemID)
    if not s then
        addGuildListings(tip, itemID)
        return
    end
    local trend = ""
    if s.trend and math.abs(s.trend - 1) >= 0.05 then
        trend = s.trend > 1 and string.format("  |cff40ff40+%d%%|r", math.floor((s.trend - 1) * 100 + 0.5))
            or string.format("  |cffff5050-%d%%|r", math.floor((1 - s.trend) * 100 + 0.5))
    end
    tip:AddDoubleLine("|cffffd700ZugDAQ|r market", ns.Money(s.market) .. trend, 1, 1, 1, 1, 1, 1)
    if s.usual and s.usual > 0 then
        tip:AddDoubleLine("   7-day average", ns.Money(s.usual), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if s.soldPerDay and s.soldPerDay > 0 then
        tip:AddDoubleLine("   Sells a day", count(s.soldPerDay), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local deal = dealFor(itemID)
    if deal then
        tip:AddLine(string.format("   Deal: %d listed at up to %s (%s profit)", deal.units or 0, ns.Money(deal.max), ns.Money(deal.profit)),
            0.4, 1, 0.4, true)
    end
    local d = data()
    local cycle = d and d.cycles and d.cycles[itemID]
    if cycle then
        tip:AddLine(string.format("   Cheapest on %ss, dearest on %ss", DAYS[cycle[1]] or "?", DAYS[cycle[2]] or "?"), 0.7, 0.6, 1, true)
    end
    addGuildListings(tip, itemID)
end

local function onItemTooltip(tip, tooltipData)
    if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
    local itemID = tooltipData and tooltipData.id
    if not itemID and tip.GetItem then
        local _, link = tip:GetItem()
        itemID = link and tonumber(link:match("item:(%d+)"))
    end
    if itemID then
        if ns.Trace then ns.Trace("tooltip item") end
        addLines(tip, itemID)
    end
end

ns.OnLogin(function()
    if not data() then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItemTooltip)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tip) onItemTooltip(tip) end)
    end
end)
