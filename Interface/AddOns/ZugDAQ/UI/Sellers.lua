local _, ns = ...

-- Market > Best sellers: what has actually sold for you, from your AH mail.
-- How many, how fast, how often it sells when listed, what you got each, and whether
-- the market price now is above or below what you've been getting.

local PERIODS = {
    { key = 7, text = "7D", width = 44 },
    { key = 30, text = "30D", width = 44 },
    { key = 90, text = "90D", width = 44 },
    { key = 0, text = "ALL", width = 44 },
}
local DIM = "|cff777777"

local function rateText(rate)
    if not rate then return DIM .. "-|r" end
    local color = rate >= 0.75 and "|cff38c75c" or rate >= 0.4 and "|cffffd100" or "|cffe64d4d"
    return color .. ns.Percent(rate) .. "|r"
end

local function perDayText(v)
    if v >= 10 then return string.format("%d", math.floor(v + 0.5)) end
    if v >= 1 then return string.format("%.1f", v) end
    return string.format("%.2f", v)
end

local function ago(t)
    if not t then return "-" end
    local s = time() - t
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. "m ago" end
    if s < 86400 then return math.floor(s / 3600) .. "h ago" end
    return math.floor(s / 86400) .. "d ago"
end

-- market price now (after the AH cut) against what you've been getting each
local function nowRatio(r)
    local current = ns.AuctionPrice(r.itemID)
    if not current or not r.each or r.each <= 0 then return nil, current end
    return current * (1 - ns.settings.ahCut) / r.each, current
end

local function nowText(r)
    local ratio = nowRatio(r)
    if not ratio then return DIM .. "-|r" end
    local pct = math.floor((ratio - 1) * 100 + 0.5)
    local color = pct >= 5 and "|cff38c75c" or pct <= -5 and "|cffe64d4d" or "|cffaaaaaa"
    return string.format("%s%+d%%|r", color, pct)
end

local function tooltip(r, frame, days)
    ns.ItemTooltip(frame, r.itemID, function(tip)
        tip:AddLine(" ")
        tip:AddLine("Your sales" .. (days > 0 and (" (last " .. days .. " days)") or ""), 1, 0.82, 0)
        tip:AddDoubleLine("Sold", string.format("%d in %d auction%s", r.units, r.sold, r.sold == 1 and "" or "s"), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("Came back unsold", tostring(r.back), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("Received (after the cut)", ns.Money(r.money), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("Average each", ns.Money(r.each), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("Selling per day", perDayText(r.perDay), 1, 1, 1, 1, 1, 1)
        local ratio, current = nowRatio(r)
        if current then
            tip:AddDoubleLine("Lowest on the AH now", ns.Money(current) .. "  " .. ns.AgeColored(ns.PriceAge(r.itemID)), 1, 1, 1, 1, 1, 1)
            if ratio and ratio >= 1.05 then
                tip:AddLine("The market pays more than you've been getting: a good time to list.", 0.4, 1, 0.4, true)
            elseif ratio and ratio <= 0.95 then
                tip:AddLine("The market is below what you've been getting: hold if you can.", 1, 0.6, 0.3, true)
            end
        end

        -- units per week, newest week first
        tip:AddLine(" ")
        tip:AddLine("Sold per week", 1, 0.82, 0)
        local now = time()
        local weeks = {}
        for _, h in ipairs(r.sales) do
            local w = math.floor((now - h.t) / (7 * 86400))
            if w < 8 then
                weeks[w] = weeks[w] or { units = 0, money = 0 }
                weeks[w].units, weeks[w].money = weeks[w].units + h.u, weeks[w].money + h.m
            end
        end
        local shown = false
        for w = 0, 7 do
            local wk = weeks[w]
            if wk then
                shown = true
                tip:AddDoubleLine(w == 0 and "  This week" or ("  " .. date("Week of %d %b", now - w * 7 * 86400 - 6 * 86400)),
                    string.format("%d  %s", wk.units, ns.Money(wk.money)), 1, 1, 1, 1, 1, 1)
            end
        end
        if not shown then tip:AddLine("  Nothing in the last 8 weeks.", 0.6, 0.6, 0.6) end

        tip:AddLine(" ")
        tip:AddLine("Latest sales", 1, 0.82, 0)
        for i, h in ipairs(r.sales) do
            if i > 8 then break end
            tip:AddDoubleLine(string.format("  %s  x%d", date("%d %b %H:%M", h.t), h.u),
                string.format("%s  |cffaaaaaa(%s each)|r", ns.Money(h.m), ns.Money(h.m / math.max(1, h.u))), 1, 1, 1, 1, 1, 1)
        end
        tip:AddLine(" ")
        tip:AddLine("Click: search it on the AH.  Right-click: " ..
            (r.itemID and ns.IsWatched(r.itemID) and "remove from" or "add to") .. " watchlist.", 0.6, 0.6, 0.6)
    end)
end

ns.RegisterPage("sellers", "Best sellers", function(page)
    local W = ns.PAGE_WIDTH
    page.days = ns.settings.sellersDays or 30

    local periods = ns.Toggles(page, PERIODS, function(days)
        page.days = days
        ns.settings.sellersDays = days
        page:Refresh()
    end)
    periods.first:SetPoint("TOPLEFT", 0, 0)

    local note = ns.Label(page, "GameFontDisableSmall",
        "From your AH mail: collect it to keep this up to date.", "RIGHT")
    note:SetPoint("TOPRIGHT", 0, -6)

    local TILE_GAP = 8
    local tileW = math.floor((W - 4 * TILE_GAP) / 5)
    local tiles = {}
    for i, title in ipairs({ "UNITS SOLD", "RECEIVED", "SELL RATE", "SOLD PER DAY", "TOP SELLER" }) do
        local t = ns.StatTile(page, tileW, 46, title)
        t:SetPoint("TOPLEFT", (i - 1) * (tileW + TILE_GAP), -32)
        tiles[i] = t
    end
    tiles[5].value:SetFontObject("GameFontHighlight")
    tiles[5].value:SetWidth(tileW - 20)
    tiles[5].value:SetWordWrap(false)

    local tbl = ns.CreateTable(page, {
        { title = "Item", width = 170, icon = function(r) return r.itemID and ns.ItemIcon(r.itemID) or 134400 end,
          text = function(r) return r.name end, sort = function(r) return r.name end, defaultAsc = true },
        { title = "Sold", width = 45, align = "RIGHT", text = function(r) return r.units end, sort = function(r) return r.units end },
        { title = "Per day", width = 55, align = "RIGHT", text = function(r) return perDayText(r.perDay) end, sort = function(r) return r.perDay end },
        { title = "Sell rate", width = 60, align = "RIGHT", text = function(r) return rateText(r.rate) end, sort = function(r) return r.rate end },
        { title = "Avg each", width = 75, align = "RIGHT", text = function(r) return ns.Money(r.each) end, sort = function(r) return r.each end },
        { title = "Received", width = 85, align = "RIGHT", text = function(r) return ns.MoneyPL(r.money) end, sort = function(r) return r.money end },
        { title = "", width = 110, bar = function(r) return r.money end },
        { title = "Now vs you", width = 70, align = "RIGHT", text = nowText, sort = function(r) return (nowRatio(r)) end },
        { title = "Last sold", width = 55, align = "RIGHT", text = function(r) return ago(r.last) end, sort = function(r) return r.last end },
    }, {
        rows = 17, sortCol = 6,
        empty = "No sales in this period yet. Sell on the AH and collect your mail, and your best sellers show up here.",
        onEnter = function(r, frame) tooltip(r, frame, page.days) end,
        onClick = function(r, button)
            if button == "RightButton" then
                if r.itemID then ns.SetWatched(r.itemID, not ns.IsWatched(r.itemID)) end
            else
                ns.SearchAH({ r.name })
            end
        end,
    })
    tbl:SetPoint("TOPLEFT", 0, -88)
    tbl:SetWidth(W)

    function page:Refresh()
        periods:Select(self.days)
        local rows, totals = ns.SalesRows(self.days)
        tbl:SetData(rows)

        local span = self.days > 0 and self.days or nil
        if not span then
            local first
            for _, r in ipairs(rows) do first = first and math.min(first, r.first) or r.first end
            span = first and math.max(1, (time() - first) / 86400) or 1
        end
        local top
        for _, r in ipairs(rows) do
            if not top or r.money > top.money then top = r end
        end
        local name = self.days > 0 and ("last " .. self.days .. " days") or "all time"

        tiles[1]:Set(tostring(totals.units), string.format("%d auctions", totals.sold), totals.units > 0 and 1 or 0,
            { "Units sold, " .. name, { "Auctions sold", tostring(totals.sold) }, { "Came back unsold", tostring(totals.back) } })
        tiles[2]:Set(ns.MoneyPL(totals.money), "", totals.money > 0 and 1 or 0,
            { "Received from AH sales, " .. name, "After the AH cut, with deposits returned." })
        tiles[3]:Set(totals.rate and ns.Percent(totals.rate) or (DIM .. "-|r"), "",
            totals.rate and (totals.rate >= 0.5 and 1 or -1) or 0,
            { "How often a listing sells", "Auctions sold out of all that sold, expired or were cancelled." })
        tiles[4]:Set(perDayText(totals.units / span), "units", totals.units > 0 and 1 or 0,
            { "Units sold per day, " .. name })
        if top then
            tiles[5]:Set(top.name, "", 1, { "Most gold from one item, " .. name, { top.name, ns.Money(top.money) },
                { "Sold", tostring(top.units) } })
        else
            tiles[5]:Set(DIM .. "-|r", "", 0, nil)
        end
    end
end)
