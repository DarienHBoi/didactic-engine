local _, ns = ...

local SOURCE_TEXT = {
    vendor = "|cff80ff80vendor|r",
    owned = "|cffffd200yours|r",
    AH = "|cff66bbffAH|r",
    estimate = "|cffaaaaaaestimate|r",
}

local function money(v) return v and ns.Money(v) or "-" end

local function addReagents(tip, reagents)
    for _, rg in ipairs(reagents) do
        local have = rg.have and rg.have > 0 and string.format(" |cffaaaaaa(have %d)|r", rg.have) or ""
        tip:AddDoubleLine(string.format("  %dx %s%s", rg.qty, ns.ItemLabel(rg.itemID), have),
            string.format("%s  %s", ns.Money(rg.cost * rg.qty), SOURCE_TEXT[rg.source] or ""), 1, 1, 1, 1, 1, 1)
    end
end

local function addOutputMarket(tip, itemID)
    local stats = ns.PriceStats(itemID)
    local ah = ns.AuctionPrice(itemID)
    local vendor = ns.VendorSell(itemID)
    tip:AddDoubleLine("  AH lowest / usual", money(ah) .. " / " .. money(stats and stats.usual), 1, 1, 1, 1, 1, 1)
    tip:AddDoubleLine("  Vendor pays", money(vendor), 1, 1, 1, 1, 1, 1)
    if stats and stats.available then
        tip:AddDoubleLine("  Listed on last scan", stats.available .. "  (scanned " ..
            (stats.age == 0 and "today" or ((stats.age or "?") .. "d ago")) .. ")", 1, 1, 1, 1, 1, 1)
    end
    if not ah then tip:AddLine("  No AH price seen: valued at what a vendor pays.", 1, 0.5, 0.3, true) end
end

local function recipeTooltip(row, frame)
    ns.ItemTooltip(frame, row.itemID, function(tip)
        local r = row.recipe
        tip:AddLine(" ")
        tip:AddLine(string.format("%s (%s)", r.name or "?", r.prof or "?"), 1, 0.82, 0)
        if (r.yield or 1) ~= 1 then tip:AddLine(string.format("Makes %g each craft", r.yield), 0.8, 0.8, 0.8) end
        tip:AddLine("Reagents", 1, 0.82, 0)
        addReagents(tip, row.reagents)
        tip:AddDoubleLine("Reagents cost", ns.Money(row.cost), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("Result sells for", ns.Money(row.value), 1, 1, 1, 1, 1, 1)
        addOutputMarket(tip, row.itemID)
        tip:AddDoubleLine("Profit each craft", ns.MoneyColored(row.profit), 1, 1, 1, 1, 1, 1)
        tip:AddLine(" ")
        tip:AddLine("\"yours\" = what you'd get selling your own copy instead.", 0.6, 0.6, 0.6, true)
        tip:AddLine("Click: see everything its main reagent can become (Explore).", 0.6, 0.6, 0.6)
        tip:AddLine("Right-click: open this recipe in " .. (r.prof or "the profession window") .. ".", 0.6, 0.6, 0.6)
        tip:AddLine("Shift-click: search the result and its reagents on the AH.", 0.6, 0.6, 0.6)
    end)
end

-- ---------------------------------------------------------------- buy & craft

local DIM = "|cff777777"
local VERDICT = {
    buy = "|cff38c75cBuy & craft|r", pricey = "|cffff9933Mats pricey|r", thin = "|cffaaaaaaThin margin|r",
    check = "|cffe64d4dCheck prices|r", loss = "|cffe64d4dLoses money|r",
}
local VERDICT_ORDER = { buy = 1, pricey = 2, thin = 3, check = 4, loss = 5 }
local VERDICT_TEXT = {
    buy = "Prices are fresh, the mats are at or under their usual price, and the margin is good.",
    pricey = "Still profits, but the mats cost more than usual right now. Waiting for cheaper mats makes more.",
    thin = "Profits by less than 10%: a small price move wipes it out.",
    check = "Prices are over 10 minutes old (or have no time on them). Open the AH and press Refresh prices before buying.",
    loss = "Loses money at these prices.",
}

-- mats against their usual price: green when cheaper, orange when pricier
local function matsText(ratio)
    if not ratio then return DIM .. "-|r" end
    local pct = math.floor((ratio - 1) * 100 + 0.5)
    local color = ratio <= 0.95 and "|cff38c75c" or (ratio > ns.FLIP_PRICEY and "|cffff9933" or "|cffaaaaaa")
    return string.format("%s%+d%%|r", color, pct)
end

local function flipTooltip(row, frame)
    ns.ItemTooltip(frame, row.itemID, function(tip)
        local r = row.recipe
        tip:AddLine(" ")
        tip:AddLine(string.format("%s (%s)", r.name or "?", r.prof or "?"), 1, 0.82, 0)
        tip:AddLine((VERDICT[row.verdict] or "") .. "  " .. (VERDICT_TEXT[row.verdict] or ""), 1, 1, 1, true)
        tip:AddLine(" ")
        tip:AddDoubleLine("Mats, each", "now  vs usual  age", 1, 0.82, 0, 0.6, 0.6, 0.6)
        for _, rg in ipairs(row.reagents) do
            local left = string.format("  %dx %s", rg.qty, ns.ItemLabel(rg.itemID))
            if rg.source == "vendor" then
                tip:AddDoubleLine(left, ns.Money(rg.cost) .. "  |cff80ff80vendor|r", 1, 1, 1, 1, 1, 1)
            else
                tip:AddDoubleLine(left, ns.Money(rg.cost) .. "  " .. matsText(rg.ratio) .. "  " .. ns.AgeColored(rg.age),
                    1, 1, 1, 1, 1, 1)
                tip:AddDoubleLine("     usual " .. money(rg.usual),
                    "buy under " .. ns.Money(math.max(0, rg.buyUnder)) .. DIM .. "  (break-even " ..
                    ns.Money(math.max(0, rg.breakEven)) .. ")|r", 0.7, 0.7, 0.7, 0.5, 1, 0.5)
            end
        end
        tip:AddDoubleLine("Mats cost", ns.Money(row.cost), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("Result sells for", ns.Money(row.value) .. "  " .. ns.AgeColored(ns.PriceAge(row.itemID)),
            1, 1, 1, 1, 1, 1)
        addOutputMarket(tip, row.itemID)
        tip:AddDoubleLine("Profit each craft", ns.MoneyPL(row.profit) .. DIM .. "  " .. ns.Percent(row.margin) .. "|r",
            1, 1, 1, 1, 1, 1)
        tip:AddLine(string.format("\"Buy under\" keeps a %s margin; break-even is the most a mat can cost before it loses money.",
            ns.Percent(ns.FLIP_TARGET_MARGIN)), 0.6, 0.6, 0.6, true)

        if row.crafts > 0 then
            tip:AddLine(" ")
            tip:AddLine(string.format("Shopping list for %d profitable craft%s", row.crafts, row.crafts == 1 and "" or "s"), 1, 0.82, 0)
            for _, rg in ipairs(row.reagents) do
                if rg.need > 0 then
                    tip:AddDoubleLine(string.format("  %d %s", rg.need, ns.ItemName(rg.itemID) or "?"),
                        rg.source == "vendor" and "from a vendor" or ("pay up to " .. ns.Money(rg.top or rg.cost) .. " each"),
                        1, 1, 1, 1, 1, 1)
                end
            end
            tip:AddDoubleLine("Spend", ns.Money(row.spend), 1, 1, 1, 1, 1, 1)
            tip:AddDoubleLine("Profit", ns.MoneyPL(row.totalProfit), 1, 1, 1, 1, 1, 1)
            if row.liveBooks then
                tip:AddLine("Costed listing by listing: stops where the next craft would lose money.", 0.6, 0.6, 0.6, true)
            else
                tip:AddLine("Costed at the lowest price only. Refresh prices to cost it listing by listing.", 1, 0.6, 0.3, true)
            end
            local listed = row.stats.available
            local made = row.crafts * (r.yield or 1)
            if listed and made > listed then
                tip:AddLine(string.format("Only %d listed on the last scan: selling %d may take a while.", listed, made),
                    1, 0.6, 0.3, true)
            end
        end
        tip:AddLine(" ")
        tip:AddLine("Click: Explore its main reagent.  Right-click: open the recipe.", 0.6, 0.6, 0.6)
        tip:AddLine("Shift-click: search the result and its mats on the AH.", 0.6, 0.6, 0.6)
    end)
end

local function searchRecipe(row, button)
    if button == "RightButton" then
        ns.OpenRecipe(row.recipe)
    elseif IsShiftKeyDown() then
        local names = { ns.ItemName(row.itemID) }
        for _, rg in ipairs(row.reagents or {}) do
            if rg.source ~= "vendor" then names[#names + 1] = ns.ItemName(rg.itemID) end
        end
        ns.SearchAH(names)
    else
        ns.ExploreItem(ns.MainReagent(row.recipe))
    end
end

ns.RegisterPage("crafting", "Crafting", function(page)
    local W = ns.PAGE_WIDTH
    page.view = "mats"

    local hint = ns.Label(page, "GameFontDisableSmall", "", "LEFT")
    hint:SetPoint("TOPLEFT", 0, -6)
    hint:SetWidth(W - 260)
    hint:SetWordWrap(false)

    local summary = ns.Label(page, "GameFontHighlight", "", "LEFT")
    summary:SetPoint("TOPLEFT", 0, -32)
    summary:SetWidth(W)

    local mats = ns.CreateTable(page, {
        { title = "Material", width = 165, icon = function(r) return ns.ItemIcon(r.itemID) end,
          text = function(r) return r.name or ("item " .. r.itemID) end, sort = function(r) return r.name or "" end, defaultAsc = true },
        { title = "Have", width = 40, align = "RIGHT", text = function(r) return r.have end, sort = function(r) return r.have end },
        { title = "Sell raw", width = 75, align = "RIGHT", text = function(r) return ns.Money(r.raw) end, sort = function(r) return r.raw end },
        { title = "Best use", width = 215, text = function(r)
            if r.path then return "|cff40ff40Craft into|r " .. ns.PathText(r.path) end
            return r.where == "AH" and "|cffffd700Sell on the AH|r" or "|cffc7c7cfSell to a vendor|r"
        end, sort = function(r) return r.path and 1 or 0 end },
        { title = "Worth each", width = 75, align = "RIGHT", text = function(r) return ns.Money(r.best) end, sort = function(r) return r.best end },
        { title = "Gain each", width = 75, align = "RIGHT", text = function(r) return r.path and ns.MoneyColored(r.gain) or "" end, sort = function(r) return r.gain end },
        { title = "Total gain", width = 85, align = "RIGHT", text = function(r) return r.path and ns.MoneyColored(r.totalGain) or "" end, sort = function(r) return r.totalGain end },
    }, {
        rows = 19, sortCol = 7,
        empty = "None of your materials go into a recipe you know. Open your profession window once so ZugDAQ can read your recipes.",
        onEnter = function(r, frame)
            ns.ItemTooltip(frame, r.itemID, function(tip)
                tip:AddLine(" ")
                tip:AddDoubleLine("You have", r.have, 1, 1, 1, 1, 1, 1)
                tip:AddDoubleLine("Sold as it is", ns.Money(r.raw) .. " each", 1, 1, 1, 1, 1, 1)
                if not r.path then
                    tip:AddLine("No recipe you know beats selling it.", 0.8, 0.8, 0.8, true)
                    return
                end
                tip:AddDoubleLine("Crafted", ns.Money(r.best) .. " each", 1, 1, 1, 1, 1, 1)
                if r.usable < r.have then
                    tip:AddLine(string.format("Other reagents you have only cover %d of them.", r.usable), 1, 0.6, 0.3, true)
                end
                for i, step in ipairs(r.path) do
                    tip:AddLine(" ")
                    tip:AddLine(string.format("Step %d: %s", i, step.name or "?"), 1, 0.82, 0)
                    addReagents(tip, ns.RecipeReagents(step))
                    tip:AddDoubleLine(string.format("  Makes %g x %s", step.yield or 1, ns.ItemLabel(step.output)),
                        ns.Money(ns.Value(step.output)) .. " each", 1, 1, 1, 1, 1, 1)
                end
                tip:AddLine(" ")
                tip:AddLine("Click: see everything it can become (Explore).", 0.6, 0.6, 0.6)
                tip:AddLine("Right-click: open the first recipe in the profession window.", 0.6, 0.6, 0.6)
                tip:AddLine("Shift-click: search the material and what it becomes on the AH.", 0.6, 0.6, 0.6)
            end)
        end,
        onClick = function(r, button)
            if button == "RightButton" then
                if r.path then ns.OpenRecipe(r.path[1])
                else ns.Print("%s is best sold, so there's no recipe to open.", r.name or "That") end
            elseif IsShiftKeyDown() then
                local names = { r.name }
                for _, step in ipairs(r.path or {}) do names[#names + 1] = ns.ItemName(step.output) end
                ns.SearchAH(names)
            else
                ns.ExploreItem(r.itemID)
            end
        end,
    })

    local recipes = ns.CreateTable(page, {
        { title = "Recipe", width = 190, icon = function(r) return ns.ItemIcon(r.itemID) end,
          text = function(r) return (r.name or "?") .. ((r.crafter and not r.mine) and ("  |cff888888(" .. r.crafter .. ")|r") or "") end,
          sort = function(r) return r.name or "" end, defaultAsc = true },
        { title = "Profession", width = 95, text = function(r) return r.prof or "" end, sort = function(r) return r.prof or "" end, defaultAsc = true },
        { title = "Sells for", width = 80, align = "RIGHT", text = function(r) return ns.Money(r.value) .. (r.hasAH and "" or "|cffff8040*|r") end, sort = function(r) return r.value end },
        { title = "Mats cost", width = 80, align = "RIGHT", text = function(r) return ns.Money(r.cost) end, sort = function(r) return r.cost end },
        { title = "Profit each", width = 85, align = "RIGHT", text = function(r) return ns.MoneyColored(r.profit) end, sort = function(r) return r.profit end },
        { title = "Can make", width = 60, align = "RIGHT", text = function(r) return r.can and r.can or "|cff80ff80buy|r" end, sort = function(r) return r.can or 9999 end },
        { title = "Total profit", width = 95, align = "RIGHT", text = function(r) return r.total and ns.MoneyColored(r.total) or "" end, sort = function(r) return r.total end },
    }, {
        rows = 19, sortCol = 5,
        empty = "No recipes read yet. Open your profession window once.",
        onEnter = recipeTooltip,
        onClick = searchRecipe,
    })

    local flips = ns.CreateTable(page, {
        { title = "Recipe", width = 150, icon = function(r) return ns.ItemIcon(r.itemID) end,
          text = function(r) return (r.name or "?") .. ((r.crafter and not r.mine) and ("  |cff888888(" .. r.crafter .. ")|r") or "") end,
          sort = function(r) return r.name or "" end, defaultAsc = true },
        { title = "Sells for", width = 70, align = "RIGHT", text = function(r) return ns.Money(r.value) end, sort = function(r) return r.value end },
        { title = "Mats", width = 70, align = "RIGHT", text = function(r) return ns.Money(r.cost) end, sort = function(r) return r.cost end },
        { title = "Profit", width = 70, align = "RIGHT", text = function(r) return ns.MoneyPL(r.profit) end, sort = function(r) return r.profit end },
        { title = "Margin", width = 45, align = "RIGHT", text = function(r) return ns.Percent(r.margin) end, sort = function(r) return r.margin end },
        { title = "Crafts", width = 40, align = "RIGHT", text = function(r) return r.crafts > 0 and r.crafts or "-" end, sort = function(r) return r.crafts end },
        { title = "Total", width = 75, align = "RIGHT", text = function(r) return r.totalProfit > 0 and ns.MoneyPL(r.totalProfit) or "-" end, sort = function(r) return r.totalProfit end },
        { title = "Mats now", width = 55, align = "RIGHT", text = function(r) return matsText(r.matsRatio) end,
          sort = function(r) return r.matsRatio end, defaultAsc = true },
        { title = "Prices", width = 50, align = "RIGHT", text = function(r) return ns.AgeColored(r.age) end,
          sort = function(r) return r.age or math.huge end, defaultAsc = true },
        { title = "Verdict", width = 80, text = function(r) return VERDICT[r.verdict] or "" end,
          -- by verdict, then the most total profit first
          sort = function(r) return (VERDICT_ORDER[r.verdict] or 9) * 1e10 - math.max(r.totalProfit, r.profit) end,
          defaultAsc = true },
    }, {
        rows = 19, sortCol = 10, sortDesc = false,
        empty = "Nothing you know turns a profit when every reagent is bought. Open the AH and press Refresh prices.",
        onEnter = flipTooltip,
        onClick = searchRecipe,
    })

    -- live price check for everything on this view (needs the AH open)
    local refreshBtn = ns.Button(page, "Refresh prices", 130, function()
        if ns.PriceCheckRunning() then
            ns.StopPriceCheck()
        else
            ns.CheckPrices(ns.FlipCheckItems())
        end
    end)
    refreshBtn:SetPoint("TOPRIGHT", 0, 0)
    refreshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Check every result and mat on the AH now")
        GameTooltip:AddLine("Reads every listing, so the cost of buying several is exact. Takes about a second per item. "
            .. "Needs the auction house open. Click again to stop.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local shopBtn = ns.Button(page, "Shopping list", 110, function()
        local names = {}
        for _, row in ipairs(page.flipRows or {}) do
            if row.verdict == "buy" then
                for _, rg in ipairs(row.reagents) do
                    if rg.source ~= "vendor" then names[#names + 1] = ns.ItemName(rg.itemID) end
                end
            end
        end
        if #names == 0 then
            ns.Print("nothing marked \"Buy & craft\" right now.")
        else
            ns.SearchAH(names)
        end
    end)
    shopBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -4, 0)
    shopBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Search the mats for every \"Buy & craft\" recipe")
        GameTooltip:AddLine("Opens them in Auctionator's Shopping tab. Hover a recipe for how many to buy and the most to pay.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    shopBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function updateButtons()
        local isFlip = page.view == "flip"
        refreshBtn:SetShown(isFlip)
        shopBtn:SetShown(isFlip)
        local done, total = ns.PriceCheckRunning()
        if done then
            refreshBtn:SetText(string.format("Stop (%d/%d)", done, total))
        else
            refreshBtn:SetText("Refresh prices")
        end
        refreshBtn:SetEnabled(done ~= nil or ns.InContext("auction"))
    end
    ns.Listen("LIVE_PROGRESS", function(done)
        if not page:IsShown() then return end
        updateButtons()
        -- show new prices as they come in
        if done and done > 0 and done % 10 == 0 then ns.RequestRefresh() end
    end)
    ns.On("AUCTION_HOUSE_SHOW", function() if page:IsShown() then updateButtons() end end)
    ns.On("AUCTION_HOUSE_CLOSED", function() if page:IsShown() then updateButtons() end end)

    for _, t in ipairs({ mats, recipes, flips }) do
        t:SetPoint("TOPLEFT", 0, -58)
        t:SetWidth(W)
    end

    function page:Refresh()
        mats:SetShown(self.view == "mats")
        recipes:SetShown(self.view == "recipes")
        flips:SetShown(self.view == "flip")

        local profs, count = ns.KnownProfessions()
        local names = {}
        for prof, n in pairs(profs) do names[#names + 1] = string.format("%s (%d)", prof, n) end
        table.sort(names)
        local known = #names > 0 and ("Recipes known: " .. table.concat(names, ", ")) or
            "|cffff8040No recipes read yet: open each profession window once.|r"

        if self.view == "mats" then
            local rows = ns.MaterialRows()
            mats:SetData(rows)
            local gain, craftCount = 0, 0
            for _, r in ipairs(rows) do
                if r.path and r.totalGain > 0 then gain, craftCount = gain + r.totalGain, craftCount + 1 end
            end
            summary:SetText(craftCount > 0
                and string.format("Crafting %d of your materials instead of selling them raw is worth %s more.", craftCount, ns.MoneyColored(gain))
                or "Selling your materials raw is the best use right now.")
            hint:SetText(known)
        elseif self.view == "recipes" then
            local rows = ns.CraftRows()
            recipes:SetData(rows)
            local total = 0
            for _, r in ipairs(rows) do total = total + (r.total or 0) end
            summary:SetText(string.format("Profit from crafting what you can make right now: %s.  |cffff8040*|r = no AH price, valued at vendor.",
                ns.MoneyColored(total)))
            hint:SetText(known)
        else
            local rows = ns.FlipRows()
            self.flipRows = rows
            flips:SetData(rows)
            local buy, stale, pricey = 0, 0, 0
            for _, r in ipairs(rows) do
                if r.verdict == "buy" then buy = buy + 1
                elseif r.verdict == "check" then stale = stale + 1
                elseif r.verdict == "pricey" then pricey = pricey + 1 end
            end
            local parts = { string.format("|cff38c75c%d to buy & craft|r", buy) }
            if pricey > 0 then parts[#parts + 1] = string.format("|cffff9933%d waiting on cheaper mats|r", pricey) end
            if stale > 0 then
                parts[#parts + 1] = string.format("|cffe64d4d%d with prices over 10 minutes old|r", stale)
            end
            summary:SetText(table.concat(parts, ",  ") .. (stale > 0 and
                (ns.InContext("auction") and "  - press Refresh prices." or "  - open the AH and press Refresh prices.") or "."))
            hint:SetText(known)
        end
        updateButtons()
    end
end)
