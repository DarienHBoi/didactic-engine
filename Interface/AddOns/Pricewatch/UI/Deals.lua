local _, P = ...
P.UI = P.UI or {}

-- "Deals": a button on the auction house frame opens a panel next to it. Four modes (deals rework 2026-11-21,
-- docs/deals-rework-2026-11-21.md): Disenchant (armor/weapons under their disenchant value), Live lots (a live AH scan, with the
-- buy workflow), Flip (listed well under their reference, selling daily) and Vendor (under the vendor price).
-- Disenchant, Flip and Vendor are filters over the cached deal index (P.DealIndex) against the buy prices: no client or price
-- lookups when they redraw. Only the visible rows are painted.
local D = {}
P.UI.Deals = D
local state = { includeStale = false, includeHighSkill = false, rows = {}, build = nil, sort = "profit", mode = "de",
    rebuilds = 0, paints = 0, offset = 0, prices = nil, pricesGen = 0, indexGen = 0, cand = nil, candKey = nil, viewKey = nil,
    lots = { job = nil, expanded = {}, material = nil, since = 0, sig = nil } }
D.state = state
local ROW_H, VISIBLE = 22, 13
local COLS = { icon = 4, flag = 26, name = 38, buy = 210, gets = 292, profit = 374, roi = 456, age = 508 }
local ROW_W = 556
local LIST_TOP, LIST_H = -140, 278
local H_FULL, H_SHORT = 540, 452 -- with and without the workflow bar (Live lots only)
local EMPTY = "No deals at this floor. Lower Min profit or scan again."
local MODES = { "de", "lots", "flip", "vendor" }
local MODE_LABEL = { de = "Disenchant", lots = "Live lots", flip = "Flip", vendor = "Vendor" }

local function ahFrame() return AuctionHouseFrame or AuctionFrame end
local function money(v) return P.Money.format(v) end
local function ageText(a) return (a == nil or a <= 0) and "today" or (a .. "d") end
local function stale() return P.Config.DEALS_MAX_AGE_DAYS end

-- What every mode's button says on hover (checked by the UI smoke: the copy must match what the mode does).
D.TIPS = {
    de = function()
        return "Armor and weapons whose last price (Auctionator's scan, else ZugDAQ's lowest) is under their disenchant value"
            .. " after the 5% AH cut by at least Min profit. Values use your logged disenchant rates and the same mat prices as"
            .. " the tooltip. Click a row to search the auction house for it."
    end,
    lots = function()
        return "Scans the auction house now (Scan AH): every armor/weapon lot whose disenchant value after the 5% cut beats its"
            .. " buyout by Min profit. Click a row to select it (shift-click a range, ctrl-click to add or remove), then Buy:"
            .. " one purchase per click. Right-click a group to show its lots, a lot to search it. Unchanged items are not"
            .. " searched twice; any other search stops the scan."
    end,
    flip = function()
        return ("Items listed at %d%% of their reference price or less that sell at least %s a day (ZugDAQ sells/day, else the"
            .. " sold tracker). Reference = the lowest of your scan Market, ZugDAQ's market and the ZugHistory median. Buy, then"
            .. " relist at the reference. Score = profit x chance it sells. Click a row to search the auction house."):format(
            math.floor(P.Config.FLIP_BELOW * 100 + 0.5), tostring(P.Config.FLIP_MIN_PER_DAY))
    end,
    vendor = function()
        return "Items listed under the price a vendor pays for them (a vendor sale has no AH cut). Buy, then sell to any vendor."
            .. " Click a row to search the auction house."
    end,
    recalc = function()
        return "Re-reads Auctionator's prices and recomputes the rows. The deal index (item facts, flip references, demand) is"
            .. " rebuilt only when ZugDAQ, ZugHistory, your Enchanting skill, your disenchant log or the day changed."
    end,
    scan = function() return "Starts a new live scan of the auction house (items unchanged since the last pass are not searched again)." end,
}

-- The Min profit in copper: the saved value, else the default.
function D.minProfit()
    local saved = type(P.db) == "table" and type(P.db.opts) == "table" and P.db.opts.dealsMin
    if type(saved) == "number" and saved >= 0 then return saved end
    return P.Config.DEALS_MIN_PROFIT
end

-- Text from the Min profit box (gold, decimals allowed): saved when it is a number, a blank or junk goes back to the default.
function D.setMinProfit(text)
    if type(P.db) ~= "table" then return end
    P.db.opts = P.db.opts or {}
    P.db.opts.dealsMin = P.Deals.parseGold(text)
    local f = state.frame
    if f and f.minProfit then f.minProfit:SetText(P.Deals.formatGold(D.minProfit())) end
    D.rebuild()
end

-- Live search for one item: Auctionator's public API when it works, else the default AH search box.
function D.search(name)
    if type(name) ~= "string" or name == "" then return false end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and type(api.MultiSearchExact) == "function" then
        local ok = pcall(api.MultiSearchExact, "Pricewatch", { name })
        if ok then return true end
    end
    local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
    local box = type(bar) == "table" and bar.SearchBox
    if type(box) == "table" and box.SetText then
        pcall(box.SetText, box, name)
        if bar.StartSearch then pcall(bar.StartSearch, bar) end
        return true
    end
    if BrowseName and BrowseName.SetText then
        pcall(BrowseName.SetText, BrowseName, name)
        if AuctionFrameBrowse_Search then pcall(AuctionFrameBrowse_Search) end
        return true
    end
    return false
end

local function matName(id)
    local ok, info = pcall(P.Adapters.itemInfo, id)
    return ok and type(info) == "table" and info.name or nil
end

-- A painted row's name when the index has none (its facts came from ZugHistoryDB): C_Item.GetItemNameByID, kept in the index.
local function nameFor(r)
    if r.name then return r.name end
    local ok, n = pcall(function() return C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.id) end)
    if ok and type(n) == "string" and n ~= "" and not (issecretvalue and issecretvalue(n)) then
        r.name = n
        local items = P.DealIndex.items(P.db)
        if items and type(items[r.id]) == "table" then items[r.id].n = n end
        return n
    end
    pcall(P.Adapters.requestItem, r.id)
    return nil
end

local function tip(owner, title, text)
    if not GameTooltip then return end
    pcall(function()
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:AddLine(title, 1, 1, 1)
        GameTooltip:AddLine(text, 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
end
D.tip = tip

-- The hover lines of a row (also read by the UI smoke).
function D.rowLines(r)
    local lines = {}
    if r.kind == "de" then
        local gives = P.Deals.givesText(r.outcomes, matName)
        if gives then lines[#lines + 1] = { text = gives, r = 0.78, g = 0.72, b = 0.5 } end
    elseif r.kind == "flip" then
        lines[#lines + 1] = { text = ("Relist at %s after the cut. Sells ~%s/day (%s), ~%d%% chance a listing sells."):format(
            money(r.gets), P.Market.perDayText(r.perDay), r.source == "market" and "sold tracker" or "ZugDAQ",
            math.floor((r.p or 0) * 100 + 0.5)), r = 0.78, g = 0.72, b = 0.5 }
        lines[#lines + 1] = { text = "Score = profit x chance it sells", r = 0.6, g = 0.6, b = 0.6 }
    elseif r.kind == "vendor" then
        lines[#lines + 1] = { text = "A vendor pays " .. money(r.gets) .. " for it.", r = 0.78, g = 0.72, b = 0.5 }
    end
    local note = r.weak and P.Deals.weakNote(r)
    if note then lines[#lines + 1] = { text = note, r = 1, g = 0.3, b = 0.3 } end
    local how
    if state.mode == "lots" then
        how = "Click: select (shift: range, ctrl: add or remove). Right-click: " .. (r.group and "show its lots." or "search this item.")
    else
        how = "Click: search the auction house for it."
    end
    lines[#lines + 1] = { text = how, r = 0.6, g = 0.6, b = 0.6 }
    return lines
end

-- One row button (VISIBLE of them, reused while scrolling). Its handlers are made once and read the row it currently holds.
local function newRow(parent)
    local b = CreateFrame("Button", nil, parent, P.UI.TEMPLATE)
    b:SetSize(ROW_W, ROW_H)
    P.UI.cardStyle(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", COLS.icon, 0)
    local function fs(font, key, x, w, just)
        local t = b:CreateFontString(nil, "OVERLAY", font)
        t:SetPoint("LEFT", x, 0)
        t:SetWidth(w)
        t:SetJustifyH(just or "LEFT")
        t:SetWordWrap(false)
        b[key] = t
    end
    fs("GameFontNormalSmall", "flag", COLS.flag, 10)
    fs("GameFontNormalSmall", "name", COLS.name, 170)
    fs("GameFontHighlightSmall", "buy", COLS.buy, 80, "RIGHT")
    fs("GameFontHighlightSmall", "gets", COLS.gets, 80, "RIGHT")
    fs("GameFontHighlightSmall", "profit", COLS.profit, 80, "RIGHT")
    fs("GameFontHighlightSmall", "roi", COLS.roi, 50, "RIGHT")
    fs("GameFontHighlightSmall", "age", COLS.age, 44, "RIGHT")
    b.flag:SetTextColor(1, 0.2, 0.2)
    b.selTex = b:CreateTexture(nil, "BACKGROUND")
    b.selTex:SetAllPoints()
    b.selTex:SetColorTexture(1, 0.82, 0, 0.2)
    b.selTex:Hide()
    pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
        local r = self.row
        if not r then return end
        if state.mode == "lots" and button ~= "RightButton" and P.UI.Workflow and self.index then
            P.UI.Workflow.rowClick(self.index)
            return
        end
        if r.group then D.toggleGroup(r.key) else D.search(r.name or nameFor(r)) end
    end)
    b:SetScript("OnEnter", function(self)
        local r = self.row
        if not r then return end
        P.UI.itemTip(self, r.id, D.rowLines(r))
    end)
    b:SetScript("OnLeave", P.UI.hideTip)
    return b
end

local function head(f, key, label, x, w, sortable)
    local h
    if sortable then
        h = CreateFrame("Button", nil, f)
        h:SetSize(w, 16)
        h:SetPoint("TOPLEFT", 8 + x, LIST_TOP + 16)
        pcall(h.SetNormalFontObject, h, "GameFontNormalSmall")
        local fsr = h.GetFontString and h:GetFontString()
        if fsr and fsr.SetJustifyH then fsr:SetJustifyH("RIGHT") end
        h.sortKey = key
        h:SetScript("OnClick", function() state.sort = h.sortKey; D.rebuild() end)
        f.heads[key] = h
    else
        h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", 8 + x, LIST_TOP + 16)
        h:SetWidth(w)
        h:SetJustifyH(key == "name" and "LEFT" or "RIGHT")
    end
    h:SetText(label)
    return h
end

local function scrollOffset()
    local s = state.frame and state.frame.scroll
    local ok, v = pcall(function() return s:GetVerticalScroll() end)
    v = ok and type(v) == "number" and v or 0
    return math.max(0, math.floor(v / (ROW_H + 1)))
end

local function build()
    local f = P.UI.panel(UIParent)
    state.frame = f
    f:SetSize(600, H_SHORT)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetText("Deals")
    f.refresh = P.UI.button(f, "Recalculate", 100, 22)
    f.refresh:SetPoint("TOPRIGHT", -14, -10)
    f.refresh:SetScript("OnClick", function() D.refresh() end)
    f.refresh:SetScript("OnEnter", function(self)
        if state.mode == "lots" then tip(self, "Scan AH", D.TIPS.scan()) else tip(self, "Recalculate", D.TIPS.recalc()) end
    end)
    f.refresh:SetScript("OnLeave", P.UI.hideTip)
    f.rescan = P.UI.button(f, "Rescan watched", 150, 22)
    f.rescan:SetPoint("RIGHT", f.refresh, "LEFT", -6, 0)
    f.rescan:SetScript("OnClick", function() D.toggleRescan() end)
    f.rescan:SetScript("OnEnter", function(self)
        tip(self, "Rescan watched", "Searches your watched items one by one (oldest first, at most " .. P.Config.RESCAN_MAX
            .. "), so the sold tracker can see what sold since the last search. Click again to cancel.")
    end)
    f.rescan:SetScript("OnLeave", P.UI.hideTip)
    f.rescanStatus = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.rescanStatus:SetPoint("TOPLEFT", 80, -16)
    f.rescanStatus:SetWidth(240)
    f.rescanStatus:SetJustifyH("LEFT")
    f.rescanStatus:SetWordWrap(false)
    f.rescan:SetShown(P.Mod.on("market"))
    f.rescanStatus:SetShown(P.Mod.on("market"))
    state.driver = CreateFrame("Frame", nil, f)

    -- the mode selector: one button per mode, the active one highlighted
    f.modes = {}
    local prev
    for _, m in ipairs(MODES) do
        local b = P.UI.button(f, MODE_LABEL[m], m == "de" and 110 or 96, 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 12, -38) end
        b.mode = m
        b:SetScript("OnClick", function() D.setMode(m) end)
        b:SetScript("OnEnter", function(self) tip(self, MODE_LABEL[m], D.TIPS[m]()) end)
        b:SetScript("OnLeave", P.UI.hideTip)
        f.modes[m] = b
        prev = b
    end
    f.deBtn, f.lotsBtn, f.flip, f.vendor = f.modes.de, f.modes.lots, f.modes.flip, f.modes.vendor

    -- Min profit (gold), right of the modes
    f.minLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.minLabel:SetPoint("TOPRIGHT", -86, -43)
    f.minLabel:SetText("Min profit (gold)")
    f.minProfit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.minProfit:SetSize(60, 20)
    f.minProfit:SetPoint("TOPRIGHT", -16, -38)
    f.minProfit:SetAutoFocus(false)
    f.minProfit:SetMaxLetters(9)
    f.minProfit:SetTextColor(1, 0.82, 0)
    f.minProfit:SetText(P.Deals.formatGold(D.minProfit()))
    f.minProfit:SetScript("OnEnterPressed", function(self) D.setMinProfit(self:GetText()); self:ClearFocus() end)
    f.minProfit:SetScript("OnEditFocusLost", function(self) D.setMinProfit(self:GetText()) end)
    f.minProfit:SetScript("OnEscapePressed", function(self) self:SetText(P.Deals.formatGold(D.minProfit())); self:ClearFocus() end)

    f.stale = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.stale:SetPoint("TOPLEFT", 10, -64)
    f.staleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.staleLabel:SetPoint("LEFT", f.stale, "RIGHT", 0, 0)
    f.staleLabel:SetText(("Include stale prices (over %d day%s old, marked !)"):format(stale(), stale() == 1 and "" or "s"))
    f.stale:SetScript("OnClick", function(self) state.includeStale = self:GetChecked() and true or false; D.rebuild() end)
    f.skill = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.skill:SetPoint("LEFT", f.staleLabel, "RIGHT", 12, 0)
    f.skillLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.skillLabel:SetPoint("LEFT", f.skill, "RIGHT", 0, 0)
    f.skillLabel:SetText("Include too-high skill")
    f.skill:SetScript("OnClick", function(self) state.includeHighSkill = self:GetChecked() and true or false; D.rebuild() end)
    f.mat = P.UI.button(f, "Mat: All", 130, 22)
    f.mat:SetPoint("LEFT", f.skillLabel, "RIGHT", 10, 0)
    pcall(f.mat.RegisterForClicks, f.mat, "LeftButtonUp", "RightButtonUp")
    f.mat:SetScript("OnClick", function(_, button) D.cycleMaterial(button == "RightButton" and -1 or 1) end)
    f.mat:SetScript("OnEnter", function(self)
        tip(self, "Material filter", "Live lots only: keep items that can give this disenchant material. Click: next, right-click: previous. Rescans.")
    end)
    f.mat:SetScript("OnLeave", P.UI.hideTip)
    f.mat:SetShown(false)

    -- where the data comes from, then what this pass found
    f.source = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.source:SetPoint("TOPLEFT", 16, -96)
    f.source:SetWidth(568)
    f.source:SetJustifyH("LEFT")
    f.source:SetWordWrap(false)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.status:SetPoint("TOPLEFT", 16, -110)
    f.status:SetWidth(568)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)

    f.heads = {}
    head(f, "name", "Item", COLS.name, 170)
    head(f, "buy", "Buy", COLS.buy, 80)
    f.getsHead = head(f, "gets", "Gets", COLS.gets, 80)
    head(f, "profit", "Profit", COLS.profit, 80, true)
    head(f, "roi", "ROI", COLS.roi, 50, true)
    head(f, "age", "Age", COLS.age, 44, true)

    f.listBox = P.UI.panel(f)
    f.listBox:SetPoint("TOPLEFT", 8, LIST_TOP)
    f.listBox:SetSize(584, LIST_H)
    local scroll, content = P.UI.scrollList(f.listBox, ROW_W)
    f.scroll, f.content = scroll, content
    -- a virtual list: VISIBLE row buttons, repainted when the list scrolls
    pcall(scroll.HookScript, scroll, "OnVerticalScroll", function()
        local o = scrollOffset()
        if o ~= state.offset then state.offset = o; D.paint() end
    end)
    f.rows = {}
    for i = 1, VISIBLE do f.rows[i] = newRow(content); f.rows[i]:SetShown(false) end
    f.empty = f.listBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.empty:SetPoint("CENTER")
    f.empty:SetWidth(420)
    f.total = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.total:SetPoint("TOPLEFT", 16, LIST_TOP - LIST_H - 8)
    f.total:SetWidth(568)
    f.total:SetJustifyH("LEFT")
    if P.UI.Workflow then pcall(P.UI.Workflow.build, f, LIST_TOP - LIST_H - 30) end
    return f
end

local LABEL = { profit = "Profit", roi = "ROI", age = "Age", score = "Score" }

-- The workflow bar and the taller panel belong to Live lots only. Its Disenchant next is a secure button: never shown, hidden
-- or resized in combat (done after PLAYER_REGEN_ENABLED instead).
function D.layout()
    local f = state.frame
    if not f then return end
    local okC, combat = pcall(InCombatLockdown or function() return false end)
    if okC and combat then state.layoutPending = true return end
    state.layoutPending = nil
    local lots = state.mode == "lots"
    f:SetHeight(lots and H_FULL or H_SHORT)
    if P.UI.Workflow and P.UI.Workflow.setShown then pcall(P.UI.Workflow.setShown, lots) end
end

-- Switches the mode. Clicking the active mode does nothing. Flip sorts by Score; leaving it goes back to Profit.
function D.setMode(mode)
    local was = state.mode
    if mode == was then return end
    state.mode = mode
    if mode == "flip" then state.sort = "score" elseif was == "flip" and state.sort == "score" then state.sort = "profit" end
    if mode == "lots" and not state.lots.job then D.startLots() end
    if was == "lots" and P.UI.Workflow and P.UI.Workflow.multiCancel then pcall(P.UI.Workflow.multiCancel) end
    state.offset = 0
    pcall(function() state.frame.scroll:SetVerticalScroll(0) end)
    D.layout()
    D.rebuild()
end

local function zugData()
    local d = ZugDAQ_AppData
    if type(d) == "table" and d.version and P.Mod.on("zugdaq") then return d end
    return nil
end

-- The candidate lists, recomputed only when the buy prices or the index changed. Items not yet indexed start a top-up.
local function candidates()
    local key = state.pricesGen .. ":" .. state.indexGen
    if state.candKey == key and state.cand then return state.cand end
    -- the first build ever has no stored index: its partial items serve meanwhile
    local items = P.DealIndex.items(P.db) or (state.build and state.build.items)
    state.cand = P.Deals.candidates(items, state.prices, function(e)
        if e.src == "auctionator" then return P.Adapters.listedAge(e.id) end
        return nil
    end)
    state.candKey = key
    return state.cand
end

local function margin() return P.Deals.margin(D.minProfit()) end
local function memo() return P.DealIndex.memo() end
local function matPrice(id) return P.Value.price(id) end
local function matDays(id) local v = P.Value.get(id); return v and v.days or 0 end
local function deposit(id) return P.Adapters.auctionDeposit(id) end

-- The Today view and the Best move read the last finished pass: refreshed when the candidates, Min profit, skill or DE memo
-- change (state.feedKey). Kept rows get a name when the index has none.
local function feedToday(cand)
    if not P.DealIndex.items(P.db) then return end
    local m = margin()
    local deRows = P.Deals.build(cand.de, matPrice, { skill = state.skill, margin = m, memo = memo(), matDays = matDays })
    local keep = {}
    for i = 1, math.min(#deRows, P.Config.TODAY_ROWS * 2) do keep[i] = deRows[i]; pcall(nameFor, deRows[i]) end
    P.Deals.last = keep
    local okF, flips = pcall(P.Deals.buildFlip, cand.flips, nil, { margin = m, deposit = deposit })
    local keepF = {}
    for i = 1, math.min(okF and #flips or 0, P.Config.TODAY_ROWS * 2) do keepF[i] = flips[i]; pcall(nameFor, flips[i]) end
    P.Deals.lastFlips = keepF
end

-- The rows for the current mode. Recomputed only when something they depend on changed (mode, sort, filters, Min profit,
-- prices, index, DE memo); otherwise only repainted.
function D.rebuild()
    local f = state.frame
    if not f then return end
    local lots = state.mode == "lots"
    local m = margin()
    local rows
    if lots then
        local job = state.lots.job
        rows = P.LotScan.view(job and job.rows or {}, { margin = m, expanded = state.lots.expanded, sort = state.sort,
            includeHighSkill = state.includeHighSkill })
        state.viewKey = nil
    else
        if state.mode ~= "flip" and state.sort == "score" then state.sort = "profit" end
        local cand = candidates()
        local feedKey = table.concat({ state.candKey, m and m.min or "-", tostring(state.skill), P.DealIndex.memoGen() }, "|")
        if feedKey ~= state.feedKey then
            state.feedKey = feedKey
            pcall(feedToday, cand)
        end
        local key = table.concat({ state.mode, state.sort, m and m.min or "-", tostring(state.includeStale),
            tostring(state.includeHighSkill), tostring(state.skill), state.candKey, P.DealIndex.memoGen() }, "|")
        if key == state.viewKey then D.paint() return end
        if state.mode == "vendor" then
            rows = P.Deals.buildVendor(cand.below, { includeStale = state.includeStale, margin = m })
        elseif state.mode == "flip" then
            rows = P.Deals.buildFlip(cand.flips, nil, { includeStale = state.includeStale, margin = m, deposit = deposit })
        else
            rows = P.Deals.build(cand.de, matPrice, { includeStale = state.includeStale, includeHighSkill = state.includeHighSkill,
                skill = state.skill, margin = m, memo = memo(), matDays = matDays })
        end
        rows = P.Deals.sort(rows, state.sort)
        -- memoGen may have moved while building (the memo expired): read the key after
        state.viewKey = table.concat({ state.mode, state.sort, m and m.min or "-", tostring(state.includeStale),
            tostring(state.includeHighSkill), tostring(state.skill), state.candKey, P.DealIndex.memoGen() }, "|")
    end
    state.rebuilds = state.rebuilds + 1
    if #rows > P.Config.DEALS_MAX_ROWS then for i = #rows, P.Config.DEALS_MAX_ROWS + 1, -1 do rows[i] = nil end end
    state.rows = rows
    D.texts()
    D.paint()
end

-- Header, status, totals and the empty sentence.
function D.texts()
    local f = state.frame
    if not f then return end
    local rows, lots, flip = state.rows, state.mode == "lots", state.mode == "flip"
    f.heads.roi.sortKey = flip and "score" or "roi"
    for _, h in pairs(f.heads) do
        if h.sortKey then h:SetText(LABEL[h.sortKey] .. (h.sortKey == state.sort and " v" or "")) end
    end
    f.getsHead:SetText(state.mode == "vendor" and "Vendor" or (flip and "Relist" or "Gets"))
    for m, b in pairs(f.modes) do b:SetSelected(m == state.mode) end
    f.refresh:SetText(lots and "Scan AH" or "Recalculate")
    f.mat:SetShown(lots)
    f.mat:SetText(D.materialText())
    local job = state.build
    f.source:SetText(P.DealIndex.sourceText(P.db, zugData(), job))
    local msg
    if lots then
        local lj = state.lots.job
        msg = not lj and "Press Scan AH to scan the auction house."
            or ((lj:done() and (lj.stopped and ("Stopped: " .. lj.stopped .. ". ") or "Done. ") or "Scanning... ") .. lj:status())
    else
        local pr = state.prices
        local zugN = 0
        for _, p in ipairs(pr and pr.list or {}) do if p.src == "zugdaq" then zugN = zugN + 1 end end
        local gave = job and job.scan.gaveUp > 0 and (" " .. job.scan.gaveUp .. " item" .. (job.scan.gaveUp == 1 and "" or "s")
            .. " never answered and were skipped.") or ""
        msg = #rows .. (state.mode == "vendor" and " item" or (flip and " flip" or " deal")) .. (#rows == 1 and "" or "s")
            .. ". Buy prices: Auctionator's last scan" .. (zugN > 0 and (", ZugDAQ's lowest for " .. zugN .. " more") or "")
            .. "." .. gave
    end
    f.status:SetText(msg)
    f.total:SetText(P.Deals.totalText(rows))
    f.empty:SetShown(#rows == 0)
    if #rows == 0 and lots then
        f.empty:SetText(state.lots.job and not state.lots.job:done() and "Scanning..." or EMPTY)
    elseif #rows == 0 then
        local noPrices = not state.prices or state.prices.n == 0
        local building = job and not job:done() and not P.DealIndex.warm(P.db, job.key) and not P.DealIndex.items(P.db)
        f.empty:SetText(noPrices and "No buy prices: Auctionator has no scan data and ZugDAQ has no snapshot (scan the auction house first)."
            or (building and "Building the deal index..." or EMPTY))
    end
end

-- Paints the VISIBLE row buttons from the scroll offset. No lookups beyond a missing name.
function D.paint()
    local f = state.frame
    if not f then return end
    state.paints = state.paints + 1
    local rows, lots = state.rows, state.mode == "lots"
    local n = #rows
    local maxOff = math.max(0, n - VISIBLE)
    if state.offset > maxOff then state.offset = maxOff end
    f.content:SetHeight(math.max(1, n * (ROW_H + 1)))
    for slot = 1, VISIBLE do
        local i = state.offset + slot
        local r = rows[i]
        local b = f.rows[slot]
        if not r then
            b.row, b.index = nil, nil
            b:SetShown(false)
        else
            b.row, b.index = r, i
            b.selTex:SetShown(lots and P.UI.Workflow and P.UI.Workflow.isSelected(r, i) or false)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 1))
            b.icon:SetTexture(P.UI.itemIcon(r.id))
            b.flag:SetText(r.weak and "!" or "")
            local nm = r.name or nameFor(r) or ("Item " .. r.id)
            if r.group then nm = (state.lots.expanded[r.key] and "[-] " or "[+] ") .. nm .. " (" .. r.count .. " lot" .. (r.count == 1 and "" or "s") .. ")"
            elseif r.lot then nm = "      x" .. r.qty .. " lot" end
            if r.needSkill then nm = nm .. " (needs " .. r.needSkill .. ")" end
            b.name:SetText(nm)
            if r.weak then b.name:SetTextColor(0.6, 0.6, 0.6) else b.name:SetTextColor(P.UI.qualityColour(r.quality)) end
            b.buy:SetText(money(r.buy))
            b.gets:SetText(money(r.gets))
            b.profit:SetText((r.weak and "|cff6a8f6a+" or "|cff40ff40+") .. money(r.profit) .. "|r")
            if r.kind == "flip" then b.roi:SetText(money(r.score)) else b.roi:SetText("+" .. r.roi .. "%") end
            b.age:SetText(((r.age or 0) > stale() and "|cffff8800" or "") .. ageText(r.age))
            b:SetShown(true)
        end
    end
    if P.UI.Workflow and lots then pcall(P.UI.Workflow.refresh) end
end

-- The index build, in the background on its own frame (it keeps going when the panel closes; it is bounded per frame).
local indexFrame = CreateFrame("Frame")
D.indexFrame = indexFrame
local function indexTick(self, dt)
    local job = state.build
    if not job then self:SetScript("OnUpdate", nil) return end
    dt = tonumber(dt) or 0
    job:step(P.DealIndex.STEP, P.DealIndex.stopper())
    job:tick(dt)
    state.indexSince = (state.indexSince or 0) + dt
    local shown = state.frame and state.frame:IsShown()
    if job:done() then
        P.DealIndex.finish(P.db, job)
        state.build = nil
        state.indexGen = state.indexGen + 1
        self:SetScript("OnUpdate", nil)
        if shown then D.rebuild() end
    elseif shown and not P.DealIndex.items(P.db) and state.indexSince >= P.Config.DEALS_REBUILD_SECS then
        -- first build: show what is indexed so far (at most every DEALS_REBUILD_SECS)
        state.indexSince = 0
        state.indexGen = state.indexGen + 1
        D.rebuild()
    elseif shown and state.indexSince >= 1 then
        state.indexSince = 0
        if state.frame.source then state.frame.source:SetText(P.DealIndex.sourceText(P.db, zugData(), job)) end
    end
end

local function startIndex()
    local job = P.DealIndex.ensure(P.db, state.prices)
    state.build = job
    state.indexSince = 0
    if job then indexFrame:SetScript("OnUpdate", indexTick) end
end

-- Recalculate (Disenchant, Flip, Vendor): re-read the buy prices, drop the DE memo, make sure the index fits (a rebuild only when
-- its key changed, a top-up for new items). Scan AH in Live lots.
function D.refresh()
    local f = state.frame
    if not f then return end
    P.DealIndex.dropMemo()
    if state.mode == "lots" then D.startLots() return end
    state.skill = P.Adapters.enchantingSkill()
    local okL, listed = pcall(P.Adapters.listedItems)
    state.prices = P.DealIndex.prices(okL and listed or {}, zugData())
    state.pricesGen = state.pricesGen + 1
    startIndex()
    D.rebuild()
end

function D.onItemInfo(id, success)
    if not P.Mod.on("deals") then return end
    local job = state.build
    if job then job:onInfo(id, success) end
end

-- Rescan watched: the button label, and the job driven one tick per frame on its own frame. Searching is only started by a click.
function D.rescanLabel()
    local f = state.frame
    if not f then return end
    if P.Rescan.running() then
        f.rescan:SetText("Cancel rescan")
    else
        local okN, list = pcall(P.Rescan.watchedList)
        local n = okN and math.min(#list, P.Config.RESCAN_MAX) or 0
        f.rescan:SetText("Rescan watched (" .. n .. ")")
    end
    local job = P.Rescan.job
    f.rescanStatus:SetText(state.rescanMsg or (job and job:status()) or "")
end

local function rescanTick(self, dt)
    local job = P.Rescan.job
    if not job or job:done() then
        self:SetScript("OnUpdate", nil)
        D.rescanLabel()
        return
    end
    pcall(job.tick, job, dt)
    D.rescanLabel()
end

function D.toggleRescan()
    if not state.frame or not P.Mod.on("market") then return end
    state.rescanMsg = nil
    if P.Rescan.running() then
        P.Rescan.stop()
    else
        local ok, job, why = pcall(P.Rescan.start)
        if not ok or not job then state.rescanMsg = (ok and why) or "Rescan failed to start." end
        if ok and job then state.driver:SetScript("OnUpdate", rescanTick) end
    end
    D.rescanLabel()
end

-- Position the panel beside the auction house frame (or the screen centre when there is none, e.g. /pricewatch deals).
local function anchor()
    local f, ah = state.frame, ahFrame()
    f:ClearAllPoints()
    if ah then f:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0) else f:SetPoint("CENTER") end
end

function D.show()
    if not P.Mod.on("deals") then return end -- switched off in NectarKit
    local f = state.frame or build()
    anchor()
    f:Show()
    D.layout()
    D.refresh()
    pcall(D.rescanLabel)
end

function D.hide()
    if state.frame then
        pcall(P.Rescan.stop)
        pcall(D.stopLots, "the panel was closed")
        if state.driver then state.driver:SetScript("OnUpdate", nil) end
        state.frame:Hide()
    end
end

function D.toggle()
    if state.frame and state.frame:IsShown() then D.hide() else D.show() end
end

-- Called when the auction house opens: adds the button once. Never errors when the frame is missing.
function D.attach()
    if not P.Mod.on("deals") then return false end
    if state.button then return true end
    local ah = ahFrame()
    if not ah then return false end
    local ok, b = pcall(P.UI.button, ah, "Deals", 90, 22)
    if not ok or not b then return false end
    b:SetPoint("TOPRIGHT", ah, "TOPRIGHT", -34, -28)
    b:SetScript("OnClick", D.toggle)
    state.button = b
    return true
end

function D.onShow() P.DealIndex.dropMemo() pcall(D.attach) end
function D.onClose() P.DealIndex.dropMemo() pcall(D.hide) end
function D.onRegen() if state.layoutPending then pcall(D.layout) end end

-- NectarKit switches, live. Deals off: the panel closes (stopping its scans) and the AH button goes; on: the button is back at
-- once when the auction house is open. Sold tracker off: the Rescan button and its status line go.
P.Mod.listen("deals", function(on)
    if not on then
        pcall(D.hide)
        if state.button then state.button:SetShown(false) end
    else
        if state.button then
            state.button:SetShown(true)
        else
            local ah = ahFrame()
            if ah and ah.IsShown and ah:IsShown() then pcall(D.attach) end
        end
    end
end)
P.Mod.listen("market", function(on)
    local f = state.frame
    if f then
        f.rescan:SetShown(on)
        f.rescanStatus:SetShown(on)
        pcall(D.rescanLabel)
    end
end)

-- ---------------------------------------------------------------------------------------------------------------------
-- Live lots (P.LotScan). One job at a time, ticked by its own frame; results arrive through the AH events below. Any other
-- browse or item search (the player, Auctionator, a row click) stops it, as Disenchantry does: they would mix their results.
-- The rows are rebuilt at most once a second, and only when the job's numbers changed (Job:signature).
local L = state.lots
local lotEvents = CreateFrame("Frame")
D.lotEvents = lotEvents
for _, e in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE", "ITEM_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_ADDED", "PLAYER_REGEN_ENABLED" }) do pcall(lotEvents.RegisterEvent, lotEvents, e) end
lotEvents:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then D.onRegen() return end
    local job = L.job
    if not job or job:done() then return end
    if event == "AUCTION_HOUSE_BROWSE_FAILURE" then job:cancel("the auction house refused the browse (try again)"); pcall(D.rebuild)
    elseif event:find("BROWSE", 1, true) then pcall(job.onBrowse, job)
    else
        local id = type(arg1) == "table" and arg1.itemID or nil
        pcall(job.onSearch, job, id)
    end
end)

local function lotsTick(self, dt)
    local job = L.job
    if not job then self:SetScript("OnUpdate", nil) return end
    dt = tonumber(dt) or 0
    local ok = pcall(job.tick, job, dt, (type(GetTime) == "function" and GetTime()) or nil)
    if not ok then job:cancel("internal error") end
    L.since = L.since + dt
    if job:done() or L.since >= 1 then
        L.since = 0
        local okS, sig = pcall(job.signature, job)
        sig = okS and sig or nil
        if job:done() or sig ~= L.sig then L.sig = sig; if state.mode == "lots" then pcall(D.rebuild) end end
    end
    if job:done() then self:SetScript("OnUpdate", nil) end
end

local hookedAH = false
local function hookOthers()
    if hookedAH or type(hooksecurefunc) ~= "function" or type(C_AuctionHouse) ~= "table" then return end
    hookedAH = true
    for _, name in ipairs({ "SendBrowseQuery", "SendSearchQuery", "SendSellSearchQuery", "RequestMoreBrowseResults",
        "RequestMoreItemSearchResults", "ReplicateItems" }) do
        if type(C_AuctionHouse[name]) == "function" then
            pcall(hooksecurefunc, C_AuctionHouse, name, function()
                if P.Adapters.lotOwn then return end
                if L.job and not L.job:done() then L.job:cancel("another search started (press Scan AH to go on)"); pcall(D.rebuild) end
            end)
        end
    end
end

function D.startLots()
    if not P.Mod.on("deals") then return false end
    if L.job and not L.job:done() then L.job:cancel("restarted") end
    local client = P.Adapters.lotClient()
    if not client then L.job = nil; pcall(D.rebuild) return false end
    hookOthers()
    P.DealIndex.dropMemo()
    local okD, deps = pcall(P.LotScan.deps, L.material)
    if not okD then return false end
    L.job = P.LotScan.new(client, deps, { now = (type(GetTime) == "function" and GetTime()) or 0 })
    L.since, L.sig = 0, nil
    L.driver = L.driver or CreateFrame("Frame")
    L.driver:SetScript("OnUpdate", lotsTick)
    pcall(D.rebuild)
    return true
end

function D.stopLots(why)
    if L.job and not L.job:done() then L.job:cancel(why) end
    if L.driver then L.driver:SetScript("OnUpdate", nil) end
end

function D.toggleGroup(key)
    if not key then return end
    L.expanded[key] = not L.expanded[key] or nil
    D.rebuild()
end

function D.materialText()
    if not L.material then return "Mat: All" end
    local n = matName(L.material)
    return "Mat: " .. (n or ("item " .. L.material))
end

-- Steps the material filter (+1 next, -1 previous; All sits between the last and the first) and rescans: the filter decides
-- which items are searched at all. Cached results stay valid per item, so a rescan is cheap.
function D.cycleMaterial(step)
    local mats = P.LotScan.materials()
    local at = 0
    for i, id in ipairs(mats) do if id == L.material then at = i end end
    at = (at + (step or 1)) % (#mats + 1)
    L.material = at > 0 and mats[at] or nil
    if state.frame and state.frame.mat then state.frame.mat:SetText(D.materialText()) end
    D.startLots()
end
