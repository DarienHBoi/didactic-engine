local _, ns = ...

local SIGNAL_TEXT = {
    deal = "|cff40ff40Cheap - buy|r",
    low = "|cff66bbffBelow usual|r",
    normal = "|cffaaaaaaNormal|r",
    high = "|cffffd200Pricey - sell|r",
}
local BAG_ADVICE = {
    deal = "|cff66bbffVery low - hold|r",
    low = "|cff66bbffLow - hold if you can|r",
    normal = "|cffaaaaaaNormal price|r",
    high = "|cff40ff40Good time to sell|r",
}

local function ageText(age)
    if not age then return "-" end
    if age <= 0 then return "today" end
    return age == 1 and "1 day" or (age .. " days")
end

local function trendText(trend)
    if not trend then return "-" end
    local pct = math.floor((trend - 1) * 100 + 0.5)
    local color = pct <= -10 and "|cff40ff40" or (pct >= 10 and "|cffffd200" or "|cffaaaaaa")
    return string.format("%s%+d%%|r", color, pct)
end

local function money(v) return v and ns.Money(v) or "-" end

local function nameOf(r) return r.name or ns.ItemName(r.itemID) or ("item " .. r.itemID) end

local function priceTooltip(r, row, extra)
    ns.ItemTooltip(row, r.itemID, function(tip)
        local s = r.stats or {}
        tip:AddLine(" ")
        tip:AddLine("Market", 1, 0.82, 0)
        tip:AddDoubleLine("Lowest listing (last scan)", money(s.current), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine(string.format("Usual (%d days seen)", s.daysSeen or 0), money(s.usual), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine("Cheapest / dearest day", money(s.low) .. " / " .. money(s.high), 1, 1, 1, 1, 1, 1)
        if s.available then tip:AddDoubleLine("Listed on last scan", s.available, 1, 1, 1, 1, 1, 1) end
        tip:AddDoubleLine("Last scanned", ageText(s.age), 1, 1, 1, 1, 1, 1)
        local owned = ns.OwnedCount(r.itemID)
        if owned > 0 then tip:AddDoubleLine("You own (bags + banks)", owned, 1, 1, 1, 1, 1, 1) end
        if extra then extra(tip) end
        tip:AddLine(" ")
        tip:AddLine("Click: search it on the AH.  Right-click: " ..
            (ns.IsWatched(r.itemID) and "remove from" or "add to") .. " watchlist.", 0.6, 0.6, 0.6)
    end)
end

local function rowClick(r, button)
    if button == "RightButton" then
        ns.SetWatched(r.itemID, not ns.IsWatched(r.itemID))
    else
        ns.SearchAH({ nameOf(r) })
    end
end

ns.RegisterPage("market", "Market", function(page)
    local W = ns.PAGE_WIDTH
    page.view = "watch"

    -- add to watchlist: shift-click an item or type its name
    local addBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    addBox:SetSize(200, 20)
    addBox:SetPoint("TOPRIGHT", page, "TOPRIGHT", -200, -1)
    addBox:SetAutoFocus(false)
    local addLabel = ns.Label(page, "GameFontNormalSmall", "Watch item:", "RIGHT")
    addLabel:SetPoint("RIGHT", addBox, "LEFT", -8, 0)
    local function addFromBox()
        local text = strtrim(addBox:GetText() or "")
        if text == "" then return end
        local id = ns.ItemIDFromName(text)
        if id then
            ns.SetWatched(id, true)
            addBox:SetText("")
        else
            ns.Print("couldn't find \"%s\". Shift-click the item into the box instead.", text)
        end
        addBox:ClearFocus()
    end
    addBox:SetScript("OnEnterPressed", addFromBox)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local addBtn = ns.Button(page, "Add", 50, addFromBox)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 4, 0)
    local function insertLink(link)
        if addBox:HasFocus() and type(link) == "string" then
            addBox:SetText(link)
            return true
        end
    end
    ns.Hook("ChatEdit_InsertLink", insertLink)
    if ChatFrameUtil then ns.Hook(ChatFrameUtil, "InsertLink", insertLink) end

    local searchBtn = ns.Button(page, "Search these", 110, function()
        local names = {}
        for _, r in ipairs(page.current or {}) do names[#names + 1] = nameOf(r) end
        ns.SearchAH(names)
    end)
    searchBtn:SetPoint("TOPRIGHT", 0, 0)
    searchBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Search the AH for everything in this list")
        GameTooltip:AddLine("Needs the auction house open. Uses Auctionator's Shopping tab (first 50 items).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    searchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local summary = ns.Label(page, "GameFontHighlight", "", "LEFT")
    summary:SetPoint("TOPLEFT", 0, -32)
    summary:SetWidth(W)

    local watch = ns.CreateTable(page, {
        { title = "Item", width = 180, icon = function(r) return ns.ItemIcon(r.itemID) end, text = nameOf, sort = nameOf, defaultAsc = true },
        { title = "Now", width = 85, align = "RIGHT", text = function(r) return money(r.stats.current) end, sort = function(r) return r.stats.current end },
        { title = "Usual", width = 85, align = "RIGHT", text = function(r) return money(r.stats.usual) end, sort = function(r) return r.stats.usual end },
        { title = "vs usual", width = 60, align = "RIGHT", text = function(r) return trendText(r.stats.trend) end, sort = function(r) return r.stats.trend end, defaultAsc = true },
        { title = "Range", width = 150, align = "RIGHT", text = function(r) return money(r.stats.low) .. " - " .. money(r.stats.high) end, sort = function(r) return r.stats.low end },
        { title = "Listed", width = 45, align = "RIGHT", text = function(r) return r.stats.available or "-" end, sort = function(r) return r.stats.available end },
        { title = "Scanned", width = 55, align = "RIGHT", text = function(r) return ageText(r.stats.age) end, sort = function(r) return r.stats.age end, defaultAsc = true },
        { title = "Signal", width = 85, text = function(r) return SIGNAL_TEXT[r.signal] or "|cffaaaaaa-|r" end, sort = function(r) return r.stats.trend end, defaultAsc = true },
    }, {
        rows = 19, sortCol = 4, sortDesc = false,
        empty = "Your watchlist is empty. Shift-click an item into the box above, or right-click items on the other tabs.",
        onEnter = function(r, row) priceTooltip(r, row) end,
        onClick = rowClick,
    })

    local deals = ns.CreateTable(page, {
        { title = "Item", width = 200, icon = function(r) return ns.ItemIcon(r.itemID) end, text = nameOf, sort = nameOf, defaultAsc = true },
        { title = "Now", width = 90, align = "RIGHT", text = function(r) return money(r.stats.current) end, sort = function(r) return r.stats.current end },
        { title = "Usual", width = 90, align = "RIGHT", text = function(r) return money(r.stats.usual) end, sort = function(r) return r.stats.usual end },
        { title = "vs usual", width = 60, align = "RIGHT", text = function(r) return trendText(r.stats.trend) end, sort = function(r) return r.stats.trend end, defaultAsc = true },
        { title = "Saving each", width = 100, align = "RIGHT", text = function(r) return ns.Money(r.saving) end, sort = function(r) return r.saving end },
        { title = "Listed", width = 55, align = "RIGHT", text = function(r) return r.stats.available or "-" end, sort = function(r) return r.stats.available end },
        { title = "Scanned", width = 65, align = "RIGHT", text = function(r) return ageText(r.stats.age) end, sort = function(r) return r.stats.age end, defaultAsc = true },
    }, {
        rows = 19, sortCol = 5,
        empty = "No deals in the latest scan. Run a full scan in Auctionator, then check back.",
        onEnter = function(r, row) priceTooltip(r, row) end,
        onClick = rowClick,
    })

    local bags = ns.CreateTable(page, {
        { title = "Item", width = 200, icon = function(r) return ns.ItemIcon(r.itemID) end, text = nameOf, sort = nameOf, defaultAsc = true },
        { title = "Count", width = 45, align = "RIGHT", text = function(r) return r.count end, sort = function(r) return r.count end },
        { title = "Each", width = 85, align = "RIGHT", text = function(r) return ns.Money(r.unit) end, sort = function(r) return r.unit end },
        { title = "Total", width = 95, align = "RIGHT", text = function(r) return ns.Money(r.total) end, sort = function(r) return r.total end },
        { title = "Sell at", width = 55, text = function(r) return r.where end, sort = function(r) return r.where end, defaultAsc = true },
        { title = "vs usual", width = 60, align = "RIGHT", text = function(r) return r.where == "AH" and trendText(r.stats.trend) or "" end, sort = function(r) return r.stats.trend end },
        { title = "Advice", width = 180, text = function(r)
            if r.where ~= "AH" then return "|cffaaaaaaVendor it|r" end
            return BAG_ADVICE[r.signal] or "|cffaaaaaaNot enough history|r"
        end, sort = function(r) return r.stats.trend or 0 end },
    }, {
        rows = 19, sortCol = 4,
        empty = "Nothing sellable in your bags.",
        onEnter = function(r, row) priceTooltip(r, row) end,
        onClick = rowClick,
    })

    -- a new scan may have happened: rebuild the deals list next time it's shown
    ns.On("AUCTION_HOUSE_CLOSED", function() page.dealsCache = nil end)
    ns.On("AUCTION_HOUSE_SHOW", function() page.dealsCache = nil end)
    ns.Listen("SCAN_DONE", function() page.dealsCache = nil end) -- a fresh (auto) scan: new deals

    for _, t in ipairs({ watch, deals, bags }) do
        t:SetPoint("TOPLEFT", 0, -58)
        t:SetWidth(W)
    end

    function page:Refresh()
        -- coming back to Deals from another view rebuilds it, in case a scan happened meanwhile
        if self.view ~= self.lastView then self.dealsCache = nil end
        self.lastView = self.view
        watch:SetShown(self.view == "watch")
        deals:SetShown(self.view == "deals")
        bags:SetShown(self.view == "bags")
        if not ns.HasAuctionator() then
            summary:SetText("|cffff5050Auctionator isn't loaded.|r Market views need its price data.")
        end
        if self.view == "watch" then
            self.current = ns.WatchRows()
            watch:SetData(self.current)
            local cheap, dear = 0, 0
            for _, r in ipairs(self.current) do
                if r.signal == "deal" then cheap = cheap + 1 elseif r.signal == "high" then dear = dear + 1 end
            end
            if ns.HasAuctionator() then
                summary:SetText(string.format("%d watched.  %d cheap right now, %d priced high.  Usual = average daily low over %d days.",
                    #self.current, cheap, dear, ns.settings.avgDays))
            end
        elseif self.view == "deals" then
            -- the full price database is big; only rebuild when asked to
            self.dealsCache = self.dealsCache or ns.DealRows()
            self.current = self.dealsCache
            deals:SetData(self.current)
            if ns.HasAuctionator() then
                summary:SetText(string.format("%d listings at %s or less of their usual price (usually worth %s+).  /zug deal <percent> to change.",
                    #self.current, ns.Percent(ns.settings.dealRatio), ns.Money(ns.settings.dealMinValue)))
            end
        else
            self.current = ns.BagRows()
            bags:SetData(self.current)
            local total, sellNow = 0, 0
            for _, r in ipairs(self.current) do
                total = total + r.total
                if r.signal == "high" then sellNow = sellNow + r.total end
            end
            if ns.HasAuctionator() then
                summary:SetText(string.format("Bags worth %s.  %s of that is priced above usual right now.",
                    ns.Money(total), ns.Money(sellNow)))
            end
        end
    end
end)
