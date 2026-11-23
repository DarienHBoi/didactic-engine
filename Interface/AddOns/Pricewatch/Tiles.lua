local _, P = ...
P.Tiles = {}
local Ti = P.Tiles

local function money(v) return P.Money.format(v) end

-- The stat tiles under the graph, as data: { key, label, text, tone, trend, trendTone, sub, tip = { lines }, hidden }.
-- Tones: white, green, red, grey. view = { fig = P.Verdict.figures, value = P.Value.get table, outcomes = Salesman outcomes,
-- profit = Salesman profit row, market = P.Market.summary }; every part may be nil (a missing part gives a grey dash, or a hidden craft tile).
function Ti.build(view)
    view = view or {}
    local fig, v, o, p = view.fig or {}, view.value, view.outcomes, view.profit
    local tiles = {}

    local now = { key = "now", label = "Now", text = "-", tone = "grey", tip = {} }
    if type(fig.now) == "number" then
        now.text, now.tone = money(fig.now), "white"
        if type(fig.age) == "number" and fig.age > 0 then now.sub = fig.age .. "d old" end
        now.tip[1] = "The lowest price at the newest scan, per unit."
        if now.sub then now.tip[2] = "Scanned " .. fig.age .. " day" .. (fig.age == 1 and "" or "s") .. " ago." end
        if type(fig.qty) == "number" then now.tip[#now.tip + 1] = "Listed at that scan: " .. fig.qty end
    else
        now.tip[1] = "No price stored for this item yet."
    end
    tiles[#tiles + 1] = now

    local market = { key = "market", label = "Market", text = "-", tone = "grey", tip = {} }
    if type(v) == "table" and type(v.market) == "number" then
        market.text, market.tone = money(v.market), "white"
        local t = v.trendPct
        if type(t) == "number" and t ~= 0 and (v.days or 0) >= P.Config.TREND_MIN_DAYS then
            market.trend = (t > 0 and "+" or "") .. t .. "%"
            market.trendTone = t > 0 and "green" or "red"
        end
        market.tip[1] = "Weighted average of the lowest daily price over " .. P.Config.MARKET_DAYS .. " days; recent days count more."
        market.tip[2] = "The change shows Market against the usual (median) price: " .. money(v.usual) .. "."
        market.tip[3] = (v.days or 0) .. " scan day" .. (v.days == 1 and "" or "s") .. " stored."
    else
        market.tip[1] = "No price history stored for this item yet."
    end
    tiles[#tiles + 1] = market

    local avg = { key = "avg", label = "Your avg sale", text = "-", tone = "grey", tip = {} }
    local avgValue = (type(o) == "table" and type(o.avgSold) == "number" and o.avgSold > 0) and o.avgSold or fig.avgSale
    if type(avgValue) == "number" and avgValue > 0 then
        avg.text, avg.tone = money(avgValue), "white"
        avg.tip[1] = "Average per unit of your logged sales, after the returned deposit."
        if (fig.sales or 0) > 0 then avg.tip[2] = fig.sales .. " sale" .. (fig.sales == 1 and "" or "s") .. " logged." end
    else
        avg.tip[1] = "No sales logged (needs the mail log of Salesman)."
    end
    tiles[#tiles + 1] = avg

    local rate = P.Rate.of(o)
    tiles[#tiles + 1] = { key = "sells", label = "Sells", text = P.Rate.text(rate), tone = P.Rate.tone(rate),
        tip = { P.Rate.tip(o), "Sale rate = sold / (sold + expired + cancelled)." } }

    local sold = Ti.soldTile(view.market)
    sold.hidden = view.noMarket or nil -- the sold tracker is switched off in NectarKit: no tile
    tiles[#tiles + 1] = sold

    local craft = { key = "craft", label = "Craft profit", text = "-", tone = "grey", hidden = type(p) ~= "table" or type(p.profit) ~= "number", tip = {} }
    if not craft.hidden then
        craft.text = (p.profit < 0 and "-" or "+") .. money(math.abs(p.profit))
        craft.tone = p.profit < 0 and "red" or "green"
        craft.tip[1] = "Sell price after the cut minus the materials, per craft."
        if type(p.net) == "number" and type(p.mats) == "number" then
            craft.tip[2] = "Sells for " .. money(p.net) .. " after the cut; materials " .. money(p.mats) .. "."
        end
    end
    tiles[#tiles + 1] = craft
    return tiles
end

-- The sold tracker's tile: units seen sold per tracked day, sell-through in the corner, the sells-at price in the hover.
-- Fewer than MARKET_MIN_SCANS tracked scans: a dash, or the rough figure from listed counts (grey, labelled rough).
function Ti.soldTile(m)
    local t = { key = "sold", label = "Sold/day", text = "-", tone = "grey", tip = {} }
    local min = P.Config.MARKET_MIN_SCANS
    if type(m) == "table" and not m.thin and type(m.perDay) == "number" then
        t.text, t.tone = "~" .. P.Market.perDayText(m.perDay), "white"
        if type(m.sellThrough) == "number" then
            t.trend = math.floor(m.sellThrough * 100 + 0.5) .. "%"
            t.trendTone = m.sellThrough >= 0.5 and "green" or (m.sellThrough >= 0.2 and "yellow" or "red")
        end
        t.tip[1] = ("Estimated market sales per day, seen by repeated AH searches: %d unit%s over %d day%s (%d scans), estimate."):format(m.sold or 0,
            m.sold == 1 and "" or "s", m.days or 0, m.days == 1 and "" or "s", m.scans or 0)
        t.tip[2] = ("Sell-through %s = sold / (sold + expired). %d expired, %d cancelled, %d unknown."):format(t.trend or "-",
            m.exp or 0, m.cxl or 0, m.unk or 0)
        t.tip[3] = type(m.sellsAt) == "number" and ("Sells at " .. money(m.sellsAt) .. " (median per unit of the sold listings, "
            .. P.Config.MARKET_DAYS .. " days).") or "No sold price seen yet."
    else
        if type(m) == "table" and type(m.rough) == "number" then
            t.text, t.sub = "~" .. P.Market.perDayText(m.rough), "rough"
            t.tip[1] = "Rough: average daily drop in the listed count. New posts hide sales; expiries and cancels count as sales."
        end
        t.tip[#t.tip + 1] = ("Fewer than %d tracked scans. Search the item a few times, or use Rescan watched on the Deals panel."):format(min)
    end
    return t
end

-- "Prices are per unit. 9 scan days stored."
function Ti.footnote(fig)
    local n = type(fig) == "table" and fig.scanDays or 0
    return "Prices are per unit. " .. n .. " scan day" .. (n == 1 and "" or "s") .. " stored."
end

-- Extra lines for the verdict banner's hover: the disenchant estimate and where its rates come from. Empty for items that
-- cannot be disenchanted. view = { fig = { de }, hasDE }.
function Ti.verdictTip(view)
    if type(view) ~= "table" or not view.hasDE then return {} end
    local de = view.fig and view.fig.de
    return { P.DE.LABEL .. ": " .. (de and money(de) or "needs mat prices") .. " (rates ported from DisenchantBuddy for Forever; skill needs are inferred)." }
end
