local _, P = ...
P.UI = P.UI or {}

-- Window: item list (search, sort) on the left, graph with 30 / 90 / all days and stats on the right.
local state = { range = 30, sort = "name", search = "", selected = nil, tab = "today" }
P.UI.state = state
local ROW_H = 30
local SORTS = { "name", "sells", "change" }
local SORT_LABEL = { name = "Sort: name", sells = "Sort: sells/week", change = "Sort: price change" }
local RANGES = { { 30, "30 days" }, { 90, "90 days" }, { 0, "All" } }

local function money(v) return v and P.Money.format(v) or "-" end

-- Tabs: Today, Items, Gather. Today and Gather can be switched off in NectarKit; Items is always there.
local TABS = { today = true, items = true, gather = true }
local function normalizeTab()
    if not TABS[state.tab] then state.tab = "today" end
    if state.tab == "gather" and not P.Mod.on("gather") then state.tab = "today" end
    if state.tab == "today" and not P.Mod.on("today") then state.tab = "items" end
end

local function layoutTabs(f)
    f.tabToday:SetShown(P.Mod.on("today"))
    f.tabItems:ClearAllPoints()
    if P.Mod.on("today") then
        f.tabItems:SetPoint("LEFT", f.tabToday, "RIGHT", 6, 0)
    else
        f.tabItems:SetPoint("TOPLEFT", 20, -30)
    end
    if f.tabGather then
        f.tabGather:SetShown(P.Mod.on("gather"))
        f.tabGather:ClearAllPoints()
        f.tabGather:SetPoint("LEFT", f.tabItems, "RIGHT", 6, 0)
    end
end

local function makeFrame()
    local ok, f = pcall(CreateFrame, "Frame", "PricewatchWindow", UIParent, "ButtonFrameTemplate")
    if ok and f then
        f.skin = "blizzard"
        if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, f) end
        if f.SetTitle then f:SetTitle("Pricewatch") elseif f.TitleText then f.TitleText:SetText("Pricewatch") end
        if f.Inset then f.Inset:Hide() end
        return f
    end
    f = CreateFrame("Frame", "PricewatchWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f.skin = "flat"
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f:SetBackdropColor(0.04, 0.035, 0.03, 0.97)
    f:SetBackdropBorderColor(0.6, 0.48, 0.15, 1)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Pricewatch")
    title:SetTextColor(1, 0.82, 0)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    return f
end

local function today() return P.Days.dayOf(time and time() or 0, P.Days.epoch0()) end

-- Item quality (remembered once the client has told us), and the colour the game uses for it (gold when unknown).
local qualities = {}
function P.UI.qualityOf(id)
    if type(id) ~= "number" then return nil end
    local q = qualities[id]
    if q then return q end
    local ok, info = pcall(P.Adapters.itemInfo, id)
    q = ok and type(info) == "table" and info.quality or nil
    if q then qualities[id] = q end
    return q
end

function P.UI.qualityColour(q)
    local c = ITEM_QUALITY_COLORS and q and ITEM_QUALITY_COLORS[q]
    if c and c.r then return c.r, c.g, c.b end
    return 1, 0.88, 0.25
end

-- The game's own item tooltip for an item id, then our extra lines ({ text, r, g, b }). Guarded; nothing is ever read back.
function P.UI.itemTip(owner, id, lines)
    if not GameTooltip or not owner or type(id) ~= "number" then return end
    pcall(function()
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        local shown = GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, id)
        if not shown and GameTooltip.SetHyperlink then pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. id) end
        for _, l in ipairs(lines or {}) do GameTooltip:AddLine(l.text, l.r or 0.7, l.g or 0.7, l.b or 0.7, true) end
        GameTooltip:Show()
    end)
end

function P.UI.hideTip()
    if GameTooltip and GameTooltip.Hide then pcall(GameTooltip.Hide, GameTooltip) end
end

-- Everything one item's panel needs: series, figures, verdict, tiles, disenchant estimate.
function P.UI.itemView(db, id, range)
    local e0, t = P.Days.epoch0(), today()
    local item = db and db.items and db.items[id]
    local sales = P.Adapters.salesmanSales(id)
    local info = P.Adapters.itemInfo(id)
    local outcomes = P.Mod.on("disenchant") and P.DE.outcomes(info.quality, info.classID, info.ilvl) or nil
    local de, deNow
    if outcomes and item then
        local dl = {}
        for _, d in ipairs(P.Store.daysList(item)) do dl[#dl + 1] = d.day end
        de = P.Series.deByDay(db, outcomes, dl)
        deNow = de[#de] and de[#de].day == (dl[#dl]) and de[#de].value or nil
    end
    local series = P.Series.build(item, { range = range, today = t, sales = sales, e0 = e0, de = de,
        zug = P.Adapters.zugHistorySeries(id, e0) })
    local fig = P.Verdict.figures(item, sales, t, { e0 = e0, de = deNow })
    local text, vr, vg, vb = P.Verdict.line(id, t)
    local tiles = P.Tiles.build({ fig = fig, value = P.Value.get(id, t), outcomes = P.Adapters.salesmanOutcomes(id),
        profit = P.Adapters.salesmanProfit(id), market = P.Mod.on("market") and P.Market.summary(db, id, t) or nil,
        noMarket = not P.Mod.on("market") })
    return { series = series, figures = fig, verdictText = text, verdictColour = { vr, vg, vb }, outcomes = outcomes, item = item, e0 = e0,
        tiles = tiles, footnote = P.Tiles.footnote(fig), verdictTip = P.Tiles.verdictTip({ fig = fig, hasDE = outcomes ~= nil }) }
end

local TONE = { white = { 1, 1, 1 }, green = { 0.25, 1, 0.25 }, red = { 1, 0.3, 0.3 }, grey = { 0.6, 0.6, 0.6 }, orange = { 1, 0.53, 0 },
    yellow = { 1, 0.82, 0.25 } }

-- Legend text from the series that have points: a coloured square and the label.
function P.UI.legendText(series)
    local out = {}
    for _, e in ipairs(P.Graph.legend(series)) do
        local c = P.UI.GRAPH_COLORS[e.key] or TONE.grey
        out[#out + 1] = ("|cff%02x%02x%02x\226\150\160|r %s"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
            math.floor(c[3] * 255 + 0.5), e.label)
    end
    return table.concat(out, "   ")
end

local function newRow(parent)
    local b = CreateFrame("Button", nil, parent, P.UI.TEMPLATE)
    b:SetSize(262, ROW_H)
    P.UI.cardStyle(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22)
    b.icon:SetPoint("LEFT", 6, 0)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("LEFT", 34, 6)
    b.name:SetWidth(122)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.sub:SetPoint("LEFT", 34, -7)
    b.sub:SetWidth(122)
    b.sub:SetJustifyH("LEFT")
    b.price = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.price:SetPoint("RIGHT", -8, 6)
    b.price:SetJustifyH("RIGHT")
    b.chg = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.chg:SetPoint("RIGHT", -8, -7)
    b.chg:SetJustifyH("RIGHT")
    b:SetScript("OnEnter", function(self) if self.itemID then P.UI.itemTip(self, self.itemID) end end)
    b:SetScript("OnLeave", P.UI.hideTip)
    return b
end


local function shiftDown()
    if type(IsShiftKeyDown) ~= "function" then return false end
    local ok, down = pcall(IsShiftKeyDown)
    return ok and down == true
end

local function ahOpen()
    local ah = AuctionHouseFrame or AuctionFrame
    if not ah or not ah.IsShown then return false end
    local ok, shown = pcall(ah.IsShown, ah)
    return ok and shown == true
end

local TODAY_ROW_H = 32
local EMPTY_TODAY = "Nothing worth doing yet. Scan the AH with Auctionator and open your professions."

-- One row of the Today table. The handlers are made once and read the row the button currently holds (b.row).
local function newTodayRow(parent)
    local b = CreateFrame("Button", nil, parent, P.UI.TEMPLATE)
    b:SetSize(842, TODAY_ROW_H - 2)
    P.UI.cardStyle(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22)
    b.icon:SetPoint("LEFT", 8, 0)
    local function fs(font, key, x, w, just)
        local t = b:CreateFontString(nil, "OVERLAY", font)
        t:SetPoint("LEFT", x, 0)
        t:SetWidth(w)
        t:SetJustifyH(just or "LEFT")
        t:SetWordWrap(false)
        b[key] = t
    end
    fs("GameFontNormal", "name", 38, 190)
    fs("GameFontHighlightSmall", "action", 236, 100)
    fs("GameFontHighlightSmall", "gain", 340, 90, "RIGHT")
    fs("GameFontDisableSmall", "reason", 446, 380)
    b:SetScript("OnClick", function(self)
        local r = self.row
        if not r or type(r.id) ~= "number" then return end
        -- Shift-click a Buy + DE row with the auction house open: run the search instead of opening the item.
        if r.kind == "deal" and shiftDown() and ahOpen() and P.UI.Deals then
            pcall(P.UI.Deals.search, r.name)
            return
        end
        P.UI.select(r.id)
    end)
    b:SetScript("OnEnter", function(self)
        local r = self.row
        if not r then return end
        P.UI.itemTip(self, r.id, { { text = r.breakdown, r = 0.78, g = 0.72, b = 0.5 } })
    end)
    b:SetScript("OnLeave", P.UI.hideTip)
    return b
end

local function buildToday(f)
    local page = f.todayPage
    -- Best move now (P.Best): one green line beside the tabs.
    f.todayBest = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.todayBest:SetPoint("TOPLEFT", 330, -34)
    f.todayBest:SetWidth(540)
    f.todayBest:SetJustifyH("LEFT")
    f.todayBest:SetWordWrap(false)
    f.todayBest:SetTextColor(0.25, 1, 0.25)
    f.todayHeader = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.todayHeader:SetPoint("TOPLEFT", 24, -64)
    f.todayHeader:SetWidth(700)
    f.todayHeader:SetJustifyH("LEFT")
    f.todayRefresh = P.UI.button(page, "Refresh", 80, 20)
    f.todayRefresh:SetPoint("TOPRIGHT", -24, -60)
    f.todayRefresh:SetScript("OnClick", function() P.UI.refresh() end)
    f.todayBox = P.UI.panel(page)
    f.todayBox:SetPoint("TOPLEFT", 14, -84)
    f.todayBox:SetSize(872, P.Config.TODAY_ROWS * TODAY_ROW_H + 12)
    f.todayRows = {}
    for i = 1, P.Config.TODAY_ROWS do
        local b = newTodayRow(f.todayBox)
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * TODAY_ROW_H)
        b:SetShown(false)
        f.todayRows[i] = b
    end
    f.todayEmpty = f.todayBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.todayEmpty:SetPoint("CENTER")
    f.todayEmpty:SetWidth(600)
    f.todayFooter = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.todayFooter:SetPoint("TOPLEFT", 24, -(84 + P.Config.TODAY_ROWS * TODAY_ROW_H + 18))
    f.todayFooter:SetWidth(700)
    f.todayFooter:SetJustifyH("LEFT")
end

local function refreshToday(f)
    if P.Mod.on("best") then
        P.Best.reset()
        local okB, line = pcall(function() return P.Best.line(P.Best.now()) end)
        f.todayBest:SetText(okB and line or "")
        f.todayBest:SetShown(true)
    else
        f.todayBest:SetShown(false)
    end
    local ok, res = pcall(function() return P.Today.build(P.Today.live()) end)
    local rows = ok and res.rows or {}
    state.today = { rows = rows, skipped = ok and res.skipped or 0 }
    local text, stale = P.Today.header(P.db, today())
    f.todayHeader:SetText(text)
    if stale then f.todayHeader:SetTextColor(1, 0.53, 0) else f.todayHeader:SetTextColor(0.6, 0.6, 0.6) end
    for i, b in ipairs(f.todayRows) do
        local r = rows[i]
        b.row = r
        if r then
            b.icon:SetTexture(P.UI.itemIcon(r.id))
            b.name:SetText(r.name or ("Item " .. r.id))
            b.name:SetTextColor(P.UI.qualityColour(P.UI.qualityOf(r.id)))
            b.action:SetText(r.action)
            b.gain:SetText("|cff40ff40+" .. P.Money.format(r.gain) .. "|r")
            b.reason:SetText(r.reason)
            b:SetShown(true)
        else
            b:SetShown(false)
        end
    end
    f.todayEmpty:SetText(EMPTY_TODAY)
    f.todayEmpty:SetShown(#rows == 0)
    local skipped = state.today.skipped
    f.todayFooter:SetText(skipped > 0 and (skipped .. " item" .. (skipped == 1 and "" or "s") .. " skipped (old or thin data)") or "")
end

-- Gather tab: where your loot was worth the most per hour, and cook or sell raw for your Cooking recipes.
local GATHER_SPOTS, GATHER_COOK = 5, 6
local function buildGather(f)
    local page = f.gatherPage
    local function header(y, text)
        local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", 24, y)
        h:SetWidth(700)
        h:SetJustifyH("LEFT")
        h:SetText(text)
        return h
    end
    local function box(y, n, key)
        local bx = P.UI.panel(page)
        bx:SetPoint("TOPLEFT", 14, y)
        bx:SetSize(872, n * TODAY_ROW_H + 12)
        f[key] = {}
        for i = 1, n do
            local b = newTodayRow(bx)
            b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * TODAY_ROW_H)
            b:SetShown(false)
            f[key][i] = b
        end
        local e = bx:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        e:SetPoint("CENTER")
        e:SetWidth(600)
        return bx, e
    end
    f.spotHeader = header(-64, "Gold per hour where you looted (items at AH price after the cut, or vendor price if higher)")
    f.spotBox, f.spotEmpty = box(-84, GATHER_SPOTS, "spotRows")
    local y = -84 - (GATHER_SPOTS * TODAY_ROW_H + 12) - 14
    f.cookHeader = header(y, "Cook or sell raw (your Cooking recipes from Salesman)")
    f.cookBox, f.cookEmpty = box(y - 20, GATHER_COOK, "cookRows")
    f.gatherFooter = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.gatherFooter:SetPoint("TOPLEFT", 24, y - 20 - (GATHER_COOK * TODAY_ROW_H + 12) - 6)
    f.gatherFooter:SetWidth(840)
    f.gatherFooter:SetJustifyH("LEFT")
end

local function itemName(id)
    local ok, info = pcall(P.Adapters.itemInfo, id)
    return ok and type(info) == "table" and info.name or nil
end

local function fill(b, r)
    b.row = r
    if not r then b:SetShown(false) return end
    b.icon:SetTexture(r.id and P.UI.itemIcon(r.id) or nil)
    b.name:SetText(r.name)
    if r.id then b.name:SetTextColor(P.UI.qualityColour(P.UI.qualityOf(r.id))) else b.name:SetTextColor(1, 0.82, 0) end
    b.action:SetText(r.action)
    b.gain:SetText(r.gainText)
    b.reason:SetText(r.reason)
    b:SetShown(true)
end

local function refreshGather(f)
    local okS, spots = pcall(P.Loot.spots, P.db, {
        price = function(id) return (P.Value.price(id)) end,
        vendor = function(id) return P.Adapters.itemInfo(id).vendor end,
    })
    spots = okS and spots or {}
    for i, b in ipairs(f.spotRows) do
        local s = spots[i]
        fill(b, s and {
            id = s.top[1] and s.top[1].id or nil, name = s.zone, action = P.Loot.sourceLabel(s.source),
            gainText = s.perHour and ("|cff40ff40" .. P.Money.format(s.perHour) .. "/h|r") or "|cff999999(under 10 min)|r",
            reason = P.Loot.reason(s, itemName),
            breakdown = "Total " .. P.Money.format(s.value) .. " over " .. math.floor(s.secs / 60 + 0.5) .. " min of looting",
        } or nil)
    end
    f.spotEmpty:SetText("Nothing logged yet. Loot mobs, fish, mine or pick herbs; each spot shows up here.")
    f.spotEmpty:SetShown(#spots == 0)
    local okC, cook, skipped = pcall(P.Cook.rows, P.Adapters.salesmanRecipes(), P.Cook.deps())
    if not okC then cook, skipped = {}, 0 end
    for i, b in ipairs(f.cookRows) do
        local c = cook[i]
        local colour = c and (c.action == "close" and "|cffd9d199" or "|cff40ff40") or ""
        fill(b, c and {
            id = c.itemID, name = c.name or ("Item " .. c.itemID), action = P.Cook.actionText(c),
            gainText = colour .. "+" .. P.Money.format(c.gain) .. "|r",
            reason = P.Cook.reason(c, itemName),
            breakdown = "Values are after the 5% cut x the chance each one sells; one craft makes one item.",
        } or nil)
    end
    f.cookEmpty:SetText(SalesmanAPI and "No Cooking recipe with prices yet. Open Cooking once (Salesman reads it) and scan the AH."
        or "Needs Salesman (it reads your Cooking recipes).")
    f.cookEmpty:SetShown(#cook == 0)
    f.gatherFooter:SetText((skipped or 0) > 0 and (skipped .. " Cooking recipe" .. (skipped == 1 and "" or "s") .. " skipped (a price is missing; open a vendor to record spice prices)") or "")
end

local function build()
    local f = makeFrame()
    state.frame = f
    f:SetSize(900, 580)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "PricewatchWindow")

    -- Tabs: Today (default) and Items
    f.tabToday = P.UI.button(f, "Today", 90, 22)
    f.tabToday:SetPoint("TOPLEFT", 20, -30)
    f.tabToday:SetScript("OnClick", function() P.UI.setTab("today") end)
    f.tabItems = P.UI.button(f, "Items", 90, 22)
    f.tabItems:SetPoint("LEFT", f.tabToday, "RIGHT", 6, 0)
    f.tabGather = P.UI.button(f, "Gather", 90, 22)
    f.tabGather:SetScript("OnClick", function() P.UI.setTab("gather") end)
    layoutTabs(f)
    f.tabItems:SetScript("OnClick", function() P.UI.setTab("items") end)
    f.todayPage = CreateFrame("Frame", nil, f)
    f.todayPage:SetAllPoints(f)
    f.itemsPage = CreateFrame("Frame", nil, f)
    f.itemsPage:SetAllPoints(f)
    f.gatherPage = CreateFrame("Frame", nil, f)
    f.gatherPage:SetAllPoints(f)
    buildToday(f)
    buildGather(f)
    local page = f.itemsPage

    -- Left: search, sort, list
    f.search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    f.search:SetSize(180, 22)
    f.search:SetPoint("TOPLEFT", 24, -62)
    f.search:SetAutoFocus(false)
    f.sortBtn = P.UI.button(page, SORT_LABEL.name, 100, 22)
    f.sortBtn:SetPoint("LEFT", f.search, "RIGHT", 6, 0)
    f.count = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.count:SetPoint("TOPLEFT", 30, -86)
    f.listBox = P.UI.panel(page)
    f.listBox:SetPoint("TOPLEFT", 14, -100)
    f.listBox:SetSize(300, 450)
    local _, content = P.UI.scrollList(f.listBox, 262)
    f.listContent = content
    f.rows = {}
    f.listEmpty = f.listBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.listEmpty:SetPoint("CENTER")
    f.listEmpty:SetWidth(240)

    -- Right: title, verdict banner, range buttons, graph, legend, tiles
    f.title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 330, -64)
    f.title:SetWidth(300)
    f.title:SetJustifyH("LEFT")
    f.verdict = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.verdict:SetPoint("TOPLEFT", 330, -88)
    f.verdict:SetWidth(540)
    f.verdict:SetJustifyH("LEFT")
    f.verdict:SetWordWrap(false)
    f.verdictHit = CreateFrame("Frame", nil, page)
    f.verdictHit:SetSize(540, 22)
    f.verdictHit:SetPoint("TOPLEFT", 330, -86)
    f.verdictHit:EnableMouse(true)
    f.verdictHit:SetScript("OnEnter", function(self)
        local lines = f.verdictTip
        if not lines or #lines == 0 or not GameTooltip then return end
        pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            for _, l in ipairs(lines) do GameTooltip:AddLine(l, 0.78, 0.72, 0.5, true) end
            GameTooltip:Show()
        end)
    end)
    f.verdictHit:SetScript("OnLeave", P.UI.hideTip)
    f.rangeBtns = {}
    for i, r in ipairs(RANGES) do
        local b = P.UI.button(page, r[2], 70, 22)
        b:SetPoint("TOPRIGHT", -20 - (#RANGES - i) * 74, -62)
        b.range = r[1]
        b:SetScript("OnClick", function() state.range = r[1]; P.UI.refresh() end)
        f.rangeBtns[i] = b
    end
    f.graph = P.UI.newGraph(page, 548, 270)
    f.graph.canvas:SetPoint("TOPLEFT", 326, -116)
    f.legend = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.legend:SetPoint("TOPLEFT", 330, -392)
    f.legend:SetWidth(540)
    f.legend:SetJustifyH("LEFT")
    f.tiles = {}
    for i = 1, 6 do
        local t = CreateFrame("Frame", nil, page, P.UI.TEMPLATE)
        t:SetSize(84, 44)
        t:SetPoint("TOPLEFT", 330 + (i - 1) * 92, -414)
        P.UI.cardStyle(t)
        t:EnableMouse(true)
        t.label = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        t.label:SetPoint("TOPLEFT", 8, -7)
        t.label:SetWidth(50)
        t.label:SetJustifyH("LEFT")
        t.label:SetWordWrap(false)
        t.note = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t.note:SetPoint("TOPRIGHT", -7, -7)
        t.note:SetJustifyH("RIGHT")
        t.value = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        t.value:SetPoint("BOTTOMLEFT", 8, 7)
        t.value:SetWidth(72)
        t.value:SetJustifyH("LEFT")
        t.value:SetWordWrap(false)
        t:SetScript("OnEnter", function(self)
            local lines = self.tipLines
            if not lines or #lines == 0 or not GameTooltip then return end
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                for _, l in ipairs(lines) do GameTooltip:AddLine(l, 0.85, 0.85, 0.85, true) end
                GameTooltip:Show()
            end)
        end)
        t:SetScript("OnLeave", P.UI.hideTip)
        f.tiles[i] = t
    end
    f.footnote = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.footnote:SetPoint("TOPLEFT", 330, -466)
    f.footnote:SetWidth(540)
    f.footnote:SetJustifyH("LEFT")

    f.search:SetScript("OnTextChanged", function(self)
        state.search = self:GetText() or ""
        P.UI.refresh()
    end)
    f.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.sortBtn:SetScript("OnClick", function()
        local idx = 1
        for i, m in ipairs(SORTS) do if m == state.sort then idx = i end end
        state.sort = SORTS[idx % #SORTS + 1]
        P.UI.refresh()
    end)
    f:Hide()
    return f
end

-- Shows the page of the current tab and paints the tab buttons.
local function applyTab(f)
    normalizeTab()
    local t = state.tab
    f.todayPage:SetShown(t == "today")
    f.itemsPage:SetShown(t == "items")
    f.gatherPage:SetShown(t == "gather")
    f.tabToday:SetSelected(t == "today")
    f.tabItems:SetSelected(t == "items")
    f.tabGather:SetSelected(t == "gather")
end

local function refreshItems(f)
    local db = P.db
    local rows = P.List.build(db, P.Adapters.salesmanRecipes(), P.Adapters.salesmanSales, today(), P.Days.epoch0())
    local shown = P.List.sort(P.List.filter(rows, state.search), state.sort)
    f.sortBtn:SetText(SORT_LABEL[state.sort])
    f.count:SetText(#shown .. " of " .. #rows .. " items")
    for _, b in ipairs(f.rows) do b:Hide() end
    for i, r in ipairs(shown) do
        local b = f.rows[i]
        if not b then
            b = newRow(f.listContent)
            f.rows[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 2))
        b.itemID = r.id
        b.icon:SetTexture(P.UI.itemIcon(r.id))
        b.name:SetText(r.name)
        if r.hasData then b.name:SetTextColor(P.UI.qualityColour(P.UI.qualityOf(r.id))) else b.name:SetTextColor(0.55, 0.55, 0.55) end
        b.sub:SetText(r.sold and r.sold > 0 and (r.sold .. " sold") or (r.crafted and "you craft this" or ""))
        b.price:SetText(r.now and P.Money.format(r.now) or "no data")
        local chg = r.change
        b.chg:SetText(chg and ((chg > 0 and "|cff40ff40+" or (chg < 0 and "|cffff4040" or "|cffaaaaaa")) .. chg .. "%|r") or "")
        b:SetSelected(r.id == state.selected)
        b:SetScript("OnClick", function() P.UI.select(r.id) end)
        b:Show()
    end
    f.listContent:SetHeight(math.max(1, #shown * (ROW_H + 2)))
    f.listEmpty:SetShown(#shown == 0)
    f.listEmpty:SetText(#rows == 0 and "Nothing stored yet. Open the auction house and scan with Auctionator; Pricewatch copies the daily prices of the items you craft and sell."
        or "No item matches the search.")
    for _, b in ipairs(f.rangeBtns) do b:SetSelected(b.range == state.range) end

    local function clearRight(verdict, footnote)
        f.verdict:SetText(verdict or "")
        f.verdictTip = nil
        f.legend:SetText("")
        f.footnote:SetText(footnote or "")
        for _, t in ipairs(f.tiles) do t:SetShown(false) end
        f.graph:draw(nil, P.Days.epoch0())
    end
    local id = state.selected
    if not id then
        f.title:SetText("Pick an item")
        clearRight()
        return
    end
    local ok, v = pcall(P.UI.itemView, db, id, state.range)
    local name = "Item " .. id
    for _, r in ipairs(rows) do if r.id == id then name = r.name end end
    f.title:SetText(name)
    if not ok then
        clearRight("", "Could not read this item.")
        return
    end
    local vc = v.verdictColour
    f.verdict:SetText(v.verdictText)
    f.verdict:SetTextColor(vc[1], vc[2], vc[3])
    f.verdictTip = v.verdictTip
    for i, t in ipairs(f.tiles) do
        local d = v.tiles[i]
        if d and not d.hidden then
            local c = TONE[d.tone] or TONE.white
            t.label:SetText(d.label)
            t.value:SetText(d.text)
            t.value:SetTextColor(c[1], c[2], c[3])
            local note, nc = d.trend or (d.sub and ("(" .. d.sub .. ")")) or "", TONE[d.trendTone or "orange"] or TONE.orange
            t.note:SetText(note)
            t.label:SetWidth(note ~= "" and 50 or 70) -- a long label may use the corner when there is no note
            t.note:SetTextColor(nc[1], nc[2], nc[3])
            t.tipLines = d.tip
            t:SetShown(true)
        else
            t:SetShown(false)
        end
    end
    f.footnote:SetText(v.footnote)
    f.legend:SetText(P.UI.legendText(v.series))
    f.graph:draw(v.series, v.e0)
end

function P.UI.refresh()
    local f = state.frame
    if not f or not f:IsShown() then return end
    normalizeTab()
    if state.tab == "items" then refreshItems(f) elseif state.tab == "gather" then refreshGather(f) else refreshToday(f) end
end

function P.UI.setTab(tab)
    state.tab = TABS[tab] and tab or "today"
    normalizeTab()
    if state.frame then applyTab(state.frame) end
    P.UI.refresh()
end

function P.UI.select(id)
    state.selected = id
    state.tab = "items"
    if state.frame then applyTab(state.frame) end
    P.UI.refresh()
end

function P.UI.toggle()
    local f = state.frame or build()
    f:SetShown(not f:IsShown())
    if f:IsShown() then applyTab(f); P.UI.refresh() end
end

-- Opens the window on a tab ("today", "items" or "gather").
function P.UI.openTab(tab)
    local f = state.frame or build()
    f:Show()
    state.tab = TABS[tab] and tab or "today"
    applyTab(f)
    P.UI.refresh()
end

-- Opens the window on one item (Salesman's Best crafts calls this through Pricewatch_Open); no id opens the current tab.
function P.UI.open(id)
    local f = state.frame or build()
    f:Show()
    state.search = ""
    if f.search and f.search.SetText then f.search:SetText("") end
    if type(id) == "number" then state.selected = id; state.tab = "items" end
    applyTab(f)
    P.UI.refresh()
end

-- NectarKit switches, live. Today off: the tab goes and the window shows Items; disenchant and sold tracker change what the
-- item view shows, so a shown window is redrawn.
for _, key in ipairs({ "today", "gather" }) do
    P.Mod.listen(key, function()
        local f = state.frame
        if not f then return end
        layoutTabs(f)
        applyTab(f)
        P.UI.refresh()
    end)
end
for _, key in ipairs({ "disenchant", "market", "best" }) do
    P.Mod.listen(key, function() pcall(P.UI.refresh) end)
end
