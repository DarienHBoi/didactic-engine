local _, S = ...
S.UI = S.UI or {}

-- "Best crafts" tab: every recipe that makes an item, ranked by what it earns on the AH after the cut.
local ROW_W, ROW_H = 790, 30
-- Column x offsets and widths: name, profession, price, net, mats, profit, margin, sells (your sale rate), demand.
local COLS = {
    { key = "name", x = 34, w = 160, label = "Item" },
    { key = "prof", x = 196, w = 66, label = "Profession" },
    { key = "sell", x = 264, w = 76, label = "Sells on AH" },
    { key = "net", x = 342, w = 76, label = "After 5% cut" },
    { key = "mats", x = 420, w = 76, label = "Mats" },
    { key = "profit", x = 498, w = 84, label = "Profit" },
    { key = "margin", x = 584, w = 44, label = "Margin" },
    { key = "sells", x = 630, w = 44, label = "Sells" },
    { key = "demand", x = 676, w = 80, label = "Demand" },
}
local SELLS_COLOUR = { green = "|cff40ff40", yellow = "|cffffd040", grey = "|cff999999" }
local STATUS_NOTE = { stale = "price over a day old", noprice = "no AH price", nomats = "mats price unknown" }

local function newRow(parent)
    local b = CreateFrame("Button", nil, parent, S.UI.TEMPLATE)
    b:SetSize(ROW_W, ROW_H)
    S.UI.cardStyle(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22)
    b.icon:SetPoint("LEFT", 6, 0)
    for _, c in ipairs(COLS) do
        local fs = b:CreateFontString(nil, "OVERLAY", c.key == "name" and "GameFontNormal" or "GameFontHighlightSmall")
        fs:SetPoint("LEFT", c.x, 0)
        fs:SetWidth(c.w)
        fs:SetJustifyH(c.key == "name" and "LEFT" or "RIGHT")
        fs:SetWordWrap(false)
        b[c.key] = fs
    end
    -- "Sold on AH: N, avg X" (from the mail log) sits under the name when there are sales.
    b.sold = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.sold:SetPoint("LEFT", 34, -8)
    b.sold:SetWidth(COLS[1].w + COLS[2].w)
    b.sold:SetJustifyH("LEFT")
    b.sold:SetWordWrap(false)
    -- Opens the Pricewatch graph for this item when that addon is installed.
    b.graph = S.UI.button(b, "G", 22, 20)
    b.graph:SetPoint("RIGHT", -4, 0)
    b.graph:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Price history graph (Pricewatch)", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    b.graph:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.rank = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.rank:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMLEFT", -2, -2)
    return b
end

local function money(v) return v and S.Money.format(v) or "-" end

local function paint(b, row, i)
    local r = row.recipe
    local dim = row.status ~= "ok"
    b.icon:SetTexture(r.icon or S.UI.itemIcon(row.itemID))
    if b.icon.SetDesaturated then b.icon:SetDesaturated(dim) end
    b.name:SetText(S.Group.shortName(r.name))
    local sold = S.Board.soldText(row)
    b.sold:SetText(sold and ("|cff80c0ff" .. sold .. "|r") or "")
    b.name:ClearAllPoints()
    b.name:SetPoint("LEFT", 34, sold and 6 or 0)
    if dim then b.name:SetTextColor(0.55, 0.55, 0.55) else b.name:SetTextColor(1, 0.88, 0.24) end
    b.prof:SetText(S.Recipes.professionOf(r) or "")
    b.sell:SetText(money(row.sell) .. (row.status == "stale" and " |cffff8800(old)|r" or ""))
    b.net:SetText(money(row.net))
    local mats = (row.farmed and row.mats == 0) and "|cff80c080farmed|r"
        or (money(row.mats) .. (row.farmed and " |cff80c080(farmed)|r" or ""))
    b.mats:SetText(mats .. (row.matsOld and " |cffff8800(old)|r" or ""))
    local profit = row.profit and S.UI.signedMoney(row.profit) or "-"
    if row.profit and not dim then
        profit = (row.profit < 0 and "|cffff4040" or "|cff40ff40") .. profit .. "|r"
    end
    b.profit:SetText(profit)
    b.margin:SetText(row.margin and (row.margin .. "%") or "-")
    local cell = S.Board.sellsCell(row.outcomes, S.DB.global.boardSort == "expected")
    b.sells:SetText(SELLS_COLOUR[cell.colour] .. cell.text .. "|r")
    b.demand:SetText(S.Trend.label(row.trend))
    b.rank:SetText(dim and "" or tostring(i))
    local hasGraph = type(Pricewatch_Open) == "function"
    b.graph:SetShown(hasGraph)
    b.graph:SetScript("OnClick", function() if type(Pricewatch_Open) == "function" then pcall(Pricewatch_Open, row.itemID) end end)
    for _, c in ipairs(COLS) do
        if c.key ~= "name" and b[c.key].SetAlpha then b[c.key]:SetAlpha(dim and 0.55 or 1) end
    end
end

local function showTip(owner, row)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local link = row.recipe.resultLink
    local ok = link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if not ok then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(row.recipe.name, 1, 0.82, 0)
    end
    GameTooltip:AddLine(" ")
    if row.sell then GameTooltip:AddDoubleLine("Auctionator price", S.Money.format(row.sell), 1, 1, 1, 1, 1, 1) end
    local sold = S.Board.soldText(row)
    if sold then
        GameTooltip:AddLine(sold .. " (what you got, after the AH cut; from your mail log)", 0.5, 0.75, 1, true)
    else
        GameTooltip:AddLine("Sold on AH: none logged yet (open your mailbox to log AH sales).", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine("Sells (your sale rate): " .. S.Board.sellsTip(row.outcomes), 0.8, 0.8, 0.8, true)
    local t = row.trend
    if t then
        GameTooltip:AddLine("Demand (Auctionator scans): " .. S.Trend.label(t), 1, 0.82, 0)
        if t.pricePct then
            GameTooltip:AddDoubleLine("Price now / before", S.Money.format(t.price) .. " / " .. S.Money.format(t.basePrice), 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddDoubleLine("Price", S.Money.format(t.price), 1, 1, 1, 1, 1, 1)
        end
        if t.qty then
            local was = t.baseQty and (" (was " .. t.baseQty .. (t.qtyPct and (", " .. (t.qtyPct > 0 and "+" or "") .. t.qtyPct .. "%") or "") .. ")") or ""
            GameTooltip:AddDoubleLine("Listed", t.qty .. was, 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:AddLine(t.heat == "new" and "Only one scan day so far: scan again on another day for a trend."
            or ("Latest scan day vs the average of the " .. (t.days - 1) .. " before."), 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Demand: no scan history yet.", 0.6, 0.6, 0.6)
    end
    if row.farmed then
        GameTooltip:AddLine(row.farmed .. (row.farmed == 1 and " mat has" or " mats have") .. " no AH price: counted as free (you farm it).", 0.5, 0.8, 0.5, true)
    end
    if STATUS_NOTE[row.status] then GameTooltip:AddLine("Not ranked: " .. STATUS_NOTE[row.status], 1, 0.5, 0) end
    GameTooltip:AddLine("Click to open this recipe in the " .. (S.Recipes.professionOf(row.recipe) or "profession") .. " view.", 0.6, 0.6, 0.6)
    if type(Pricewatch_Open) == "function" then GameTooltip:AddLine("Shift-click or G: price history graph (Pricewatch).", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

-- hooks: rows() -> ranked rows, select(recipe), status(msg)
function S.UI.buildBoard(root, hooks)
    local panel = { frames = {}, shown = {} }

    local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("Best crafts")
    panel.summary = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.summary:SetPoint("LEFT", title, "RIGHT", 12, -1)

    local showAll = CreateFrame("CheckButton", nil, root, "UICheckButtonTemplate")
    showAll:SetSize(24, 24)
    showAll:SetPoint("TOPRIGHT", -150, -2)
    local showLabel = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    showLabel:SetPoint("LEFT", showAll, "RIGHT", 0, 0)
    panel.showAll, panel.showLabel = showAll, showLabel

    -- Profession filter: click for the next profession, right-click for the previous; "All" first.
    local prof = S.UI.button(root, "Profession: All", 170, 24)
    prof:SetPoint("RIGHT", showAll, "LEFT", -10, 0)
    prof:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    panel.prof = prof

    -- Sort: by profit (default) or by expected profit (profit x your sale rate).
    local sortBtn = S.UI.button(root, "Sort: Profit", 130, 24)
    sortBtn:SetPoint("RIGHT", prof, "LEFT", -10, 0)
    panel.sortBtn = sortBtn

    local box = S.UI.panel(root)
    box:SetPoint("TOPLEFT", 0, -50)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    for _, c in ipairs(COLS) do
        local h = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("BOTTOMLEFT", box, "TOPLEFT", c.x + 4, 3)
        h:SetWidth(c.w)
        h:SetJustifyH(c.key == "name" and "LEFT" or "RIGHT")
        h:SetText(c.label)
    end
    local _, content = S.UI.scrollList(box, ROW_W)
    panel.empty = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.empty:SetPoint("CENTER")
    panel.empty:SetWidth(420)

    local function getRow(i)
        if not panel.frames[i] then panel.frames[i] = newRow(content) end
        return panel.frames[i]
    end

    function panel.update()
        local rows = hooks.rows()
        local profs = S.Board.professions(rows)
        local want = S.DB.global.boardProf
        local cur
        for _, p in ipairs(profs) do if p == want then cur = p end end
        panel.profs = profs
        prof:SetText("Profession: " .. (cur or "All"))
        sortBtn:SetText(S.DB.global.boardSort == "expected" and "Sort: Expected" or "Sort: Profit")
        rows = S.Board.filter(rows, cur)
        local all = S.DB.global.boardShowAll and true or false
        local sum = S.Board.summary(rows)
        panel.shown = S.Board.visible(rows, all)
        showAll:SetChecked(all)
        showLabel:SetText("Show unpriced (" .. sum.hidden .. ")")
        panel.summary:SetText(sum.ranked .. " priced, " .. sum.profitable .. " in profit")
        for _, b in ipairs(panel.frames) do b:Hide() end
        local y = 0
        for i, row in ipairs(panel.shown) do
            local b = getRow(i)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 0, -y)
            paint(b, row, i)
            b:SetSelected(row.recipe.key == S.DB.char.selected)
            b:SetScript("OnClick", function()
                -- Shift-click opens the Pricewatch graph instead of the recipe.
                local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown()
                if shift and type(Pricewatch_Open) == "function" then pcall(Pricewatch_Open, row.itemID) return end
                hooks.select(row.recipe)
            end)
            b:SetScript("OnEnter", function(self) showTip(self, row) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Show()
            y = y + ROW_H + 2
        end
        content:SetHeight(math.max(1, y))
        panel.empty:SetShown(#panel.shown == 0)
        if #rows == 0 then
            panel.empty:SetText("No crafted items yet. Open a profession that makes items (Tailoring, Cooking...) to load its recipes.")
        elseif #panel.shown == 0 then
            panel.empty:SetText("No fresh AH prices. Scan the auction house with Auctionator, or tick Show unpriced.")
        end
    end

    prof:SetScript("OnClick", function(_, btn)
        local list = panel.profs or {}
        local idx = 0 -- 0 = All
        for i, p in ipairs(list) do if p == S.DB.global.boardProf then idx = i end end
        idx = (idx + (btn == "RightButton" and -1 or 1)) % (#list + 1)
        S.DB.global.boardProf = list[idx]
        panel.update()
    end)
    sortBtn:SetScript("OnClick", function()
        S.DB.global.boardSort = S.DB.global.boardSort ~= "expected" and "expected" or nil
        panel.update()
    end)
    showAll:SetScript("OnClick", function()
        S.DB.global.boardShowAll = (not S.DB.global.boardShowAll) and true or nil
        panel.update()
    end)
    return panel
end
