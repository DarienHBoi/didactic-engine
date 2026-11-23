local _, ns = ...

ns.RegisterPage("auctions", "Auctions", function(page)
    local W = ns.PAGE_WIDTH
    page.view = "all"

    local views = ns.Toggles(page, {
        { key = "all", text = "All items", width = 100 },
        { key = "attention", text = "Needs attention", width = 120 },
    }, function(key) page.view = key page:Refresh() end)
    views.first:SetPoint("TOPLEFT", 0, 0)
    views:Select(page.view)

    local summary = ns.Label(page, "GameFontHighlight", "", "LEFT")
    summary:SetPoint("TOPLEFT", 0, -32)
    summary:SetWidth(W)

    local hint = ns.Label(page, "GameFontDisableSmall",
        "Click: search it on the AH.  Right-click: add to / remove from watchlist.", "RIGHT")
    hint:SetPoint("TOPRIGHT", 0, -6)

    local tbl = ns.CreateTable(page, {
        { title = "Item", width = 190, icon = function(r) return ns.ItemIcon(r.a.itemID) end,
          text = function(r) return r.name end, sort = function(r) return r.name end, defaultAsc = true },
        { title = "Posted", width = 50, align = "RIGHT", text = function(r) return r.a.posts end, sort = function(r) return r.a.posts end },
        { title = "Sold", width = 45, align = "RIGHT", text = function(r) return r.a.sold end, sort = function(r) return r.a.sold end },
        { title = "Back", width = 45, align = "RIGHT", text = function(r) return r.a.expired + r.a.cancelled end, sort = function(r) return r.a.expired + r.a.cancelled end },
        { title = "Sells", width = 50, align = "RIGHT", text = function(r) return ns.Percent(r.v.sellThrough) end, sort = function(r) return r.v.sellThrough end },
        { title = "Profit", width = 95, align = "RIGHT", text = function(r) return ns.MoneyColored(r.v.profit) end, sort = function(r) return r.v.profit end },
        { title = "Per unit", width = 85, align = "RIGHT", text = function(r) return r.v.avgSale and ns.Money(r.v.avgSale) or "-" end, sort = function(r) return r.v.avgSale end },
        { title = "Verdict", width = 165, text = function(r) return r.v.color .. r.v.verdict .. "|r" end, sort = function(r) return r.v.verdict end, defaultAsc = true },
    }, {
        rows = 19, sortCol = 6,
        empty = "Nothing tracked yet. Post auctions and collect your AH mail, and results show up here.",
        onEnter = function(r, row)
            ns.ItemTooltip(row, r.a.itemID, function(tip)
                local a, v = r.a, r.v
                tip:AddLine(" ")
                tip:AddLine("Your auction history", 1, 0.82, 0)
                tip:AddDoubleLine("Auctions posted", string.format("%d (%d items)", a.posts, a.postedUnits), 1, 1, 1, 1, 1, 1)
                tip:AddDoubleLine("Sold", string.format("%d (%d items)", a.sold, a.soldUnits), 1, 1, 1, 1, 1, 1)
                tip:AddDoubleLine("Expired / cancelled", string.format("%d / %d", a.expired, a.cancelled), 1, 1, 1, 1, 1, 1)
                tip:AddDoubleLine("Received from sales", ns.Money(a.received), 1, 1, 1, 1, 1, 1)
                tip:AddDoubleLine("AH cut", ns.Money(a.cut), 1, 1, 1, 1, 1, 1)
                tip:AddDoubleLine("Deposits paid", ns.Money(a.deposits), 1, 1, 1, 1, 1, 1)
                if a.boughtUnits > 0 then
                    tip:AddDoubleLine("Bought on AH", string.format("%d for %s (%s each)", a.boughtUnits,
                        ns.Money(a.spent), ns.Money(v.avgBuy)), 1, 1, 1, 1, 1, 1)
                end
                tip:AddDoubleLine("Profit", ns.MoneyColored(v.profit), 1, 1, 1, 1, 1, 1)
                if a.lastPostPrice then tip:AddDoubleLine("Last listed at", ns.Money(a.lastPostPrice) .. " each", 1, 1, 1, 1, 1, 1) end
                local stats = ns.PriceStats(a.itemID)
                if stats and stats.usual then
                    tip:AddDoubleLine("Market now / usual", ns.Money(stats.current) .. " / " .. ns.Money(stats.usual), 1, 1, 1, 1, 1, 1)
                end
            end)
        end,
        onClick = function(r, button)
            if button == "RightButton" then
                if r.a.itemID then ns.SetWatched(r.a.itemID, not ns.IsWatched(r.a.itemID)) end
            else
                ns.SearchAH({ r.name })
            end
        end,
    })
    tbl:SetPoint("TOPLEFT", 0, -58)
    tbl:SetWidth(W)

    function page:Refresh()
        local rows = {}
        local received, deposits, profit, sold, outcomes = 0, 0, 0, 0, 0
        for name, a in pairs(ns.db.auctions) do
            local v = ns.AuctionVerdict(a)
            received, deposits, profit = received + a.received, deposits + a.deposits, profit + v.profit
            sold, outcomes = sold + a.sold, outcomes + v.outcomes
            local attention = v.outcomes >= 3 and (v.profit < 0 or v.sellThrough < 0.5)
            if (a.posts > 0 or a.sold > 0 or v.outcomes > 0) and (self.view == "all" or attention) then
                rows[#rows + 1] = { name = name, a = a, v = v }
            end
        end
        summary:SetText(string.format("Received %s   Deposits %s   Profit %s   Sells %s of the time",
            ns.Money(received), ns.Money(deposits), ns.MoneyColored(profit),
            outcomes > 0 and ns.Percent(sold / outcomes) or "-"))
        tbl:SetData(rows)
    end
end)
