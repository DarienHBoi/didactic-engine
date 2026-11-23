local _, P = ...
-- The disenchant workflow bar under the Live lots list: Buy (selected or top lot) / Disenchant next / Post mats + Spend cap
-- (P.Workflow). Shown in Live lots only.
-- Every action is one hardware click: Buy next calls C_AuctionHouse.PlaceBid at most once per click (after the item's search
-- results show the same auction at the same or a lower buyout); Disenchant next is a SecureActionButton whose macro is set only
-- out of combat (Blizzard runs the cast on the click); Post mats calls C_AuctionHouse.PostCommodity at most once per click.
-- Nothing protected runs from a timer or an event. Disenchant outcomes are logged by P.DELog as before.
P.UI = P.UI or {}
local U = {}
P.UI.Workflow = U
local W = P.Workflow
local st = { wf = W.new({}, {}), jobSeen = nil, loadedItem = nil, loadedCommodity = nil, macro = nil, target = nil, post = {},
    sel = W.newSelection(), batch = nil, bags = nil, bagScans = 0 }
U.state = st

local DISENCHANT = 13262

local function plain(v)
    if v == nil then return nil end
    if type(issecretvalue) == "function" then
        local ok, s = pcall(issecretvalue, v)
        if not ok or s then return nil end
    end
    return v
end

local function AH() return type(C_AuctionHouse) == "table" and C_AuctionHouse or nil end

local function capCopper()
    local c = type(P.db) == "table" and type(P.db.opts) == "table" and P.db.opts.wfCap
    return type(c) == "number" and c > 0 and c or nil
end

-- every bag slot { bag, slot, itemID, count } (bags 0-4; Forever's C_Container, else the old globals)
local function bagItems()
    local out = {}
    local C = type(C_Container) == "table" and C_Container or nil
    local num = C and C.GetContainerNumSlots or GetContainerNumSlots
    local info = C and C.GetContainerItemInfo
    for bag = 0, 4 do
        local okN, n = pcall(num or function() return 0 end, bag)
        for slot = 1, (okN and plain(n) or 0) do
            local okI, i = pcall(info or function() return nil end, bag, slot)
            if okI and type(i) == "table" and plain(i.itemID) then
                out[#out + 1] = { bag = bag, slot = slot, itemID = i.itemID, count = plain(i.stackCount) or 1 }
            end
        end
    end
    return out
end

-- The bag contents, read once per BAG_UPDATE_DELAYED (and after our own post or disenchant), not on every redraw.
local function bags()
    if not st.bags then st.bags = bagItems(); st.bagScans = st.bagScans + 1 end
    return st.bags
end
function U.bagsChanged() st.bags = nil end

-- the Live lots queue: rebuilt when a new pass has finished (spent, cap and the bought list carry over)
local function syncQueue()
    local D = P.UI.Deals
    local job = D and D.state and D.state.lots and D.state.lots.job
    if not job or not job:done() or st.jobSeen == job then return end
    st.jobSeen = job
    st.wf.queue = W.queue(job.rows, { margin = P.Deals.margin(D.minProfit()), includeHighSkill = D.state.includeHighSkill })
end

local buyClient = {
    current = function(key)
        if st.loadedItem ~= key.itemID then return nil end
        local c = P.Adapters.lotClient()
        return c and c.searchResults(key) or nil
    end,
    search = function(key)
        local c = P.Adapters.lotClient()
        if not c then error("no auction house") end
        st.loadedItem = nil
        return c.search(key)
    end,
    placeBid = function(auctionID, price)
        local ah = AH()
        if not ah or type(ah.PlaceBid) ~= "function" then return false end
        ah.PlaceBid(auctionID, price)
        return true
    end,
    getMoney = function() return type(GetMoney) == "function" and GetMoney() or nil end,
}

local postClient = {
    nextMat = function()
        for _, b in ipairs(bags()) do if P.DE.MATS[b.itemID] then return b end end
    end,
    lowest = function(id)
        if st.loadedCommodity ~= id then return nil end
        local ah = AH()
        local okN, n = pcall(ah.GetNumCommoditySearchResults, id)
        if not okN or not plain(n) or n < 1 then return nil end
        local okR, r = pcall(ah.GetCommoditySearchResultInfo, id, 1)
        return okR and type(r) == "table" and plain(r.unitPrice) or nil
    end,
    searchCommodity = function(id)
        local ah = AH()
        local sortOrder = type(Enum) == "table" and type(Enum.AuctionHouseSortOrder) == "table" and Enum.AuctionHouseSortOrder.Price or 0
        st.loadedCommodity = nil
        P.Adapters.lotOwn = true
        local ok, err = pcall(ah.SendSearchQuery, ah.MakeItemKey(id), { { sortOrder = sortOrder, reverseSort = false } }, false)
        P.Adapters.lotOwn = false
        if not ok then error(err, 0) end
        return true
    end,
    ref = function(id) return (P.Value.matPrice(id)) end,
    post = function(bag, slot, count, price)
        local ah = AH()
        if not ah or type(ah.PostCommodity) ~= "function" or type(ItemLocation) ~= "table" then return false end
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        ah.PostCommodity(loc, 2, count, price) -- 2 = 24 hours
        return true
    end,
}

-- Disenchant next: the macro for the next bought item in the bags, set only out of combat (secure attributes).
function U.refreshDE()
    local b = st.deButton
    if not b then return end
    st.target = W.deTarget(bags(), st.wf.bought)
    local text = st.target and ("Disenchant next (bag " .. st.target.bag .. " slot " .. st.target.slot .. ")")
        or "Disenchant next: nothing bought in bags"
    if b.label then pcall(b.label.SetText, b.label, text) end
    local okC, combat = pcall(InCombatLockdown or function() return false end)
    if okC and combat then return end
    local macro = st.target and W.macro(st.target) or ""
    if macro ~= st.macro then
        pcall(b.SetAttribute, b, "type", "macro")
        pcall(b.SetAttribute, b, "macrotext", macro)
        st.macro = macro
    end
end

-- The one Buy button (deals rework R8): with a selection it buys the selected lots, one PlaceBid per click; without one it buys
-- the top queued lot. Its label says which.
function U.buyLabel()
    local b = st.batch
    if b and not W.batchDone(b) then return W.batchLabel(b) end
    return W.buyLabel(st.wf)
end

function U.refresh()
    local f = st.frame
    if not f then return end
    syncQueue()
    pcall(f.wfBuy.SetText, f.wfBuy, U.buyLabel())
    local post = st.post.last and (" Post: " .. st.post.last .. ".") or ""
    pcall(f.wfSummary.SetText, f.wfSummary, W.summary(st.wf) .. post)
    pcall(U.refreshDE)
end

local function repaint()
    local D = P.UI.Deals
    if D and D.paint then pcall(D.paint) end
end

function U.buy()
    if not P.Mod.on("deals") then return end
    syncQueue()
    local b = st.batch
    local okB, r
    if b then
        okB, r = pcall(W.batchStep, b, buyClient)
        if W.batchDone(b) then
            W.clearSelection(st.sel)
            st.batch = nil
            repaint()
        end
    else
        okB, r = pcall(W.buyStep, st.wf, buyClient)
    end
    if okB and r == "bought" then st.bags = nil end -- the purchase lands in the bags; read them again
    U.refresh()
    U.refreshMulti()
end

function U.postMats()
    if not P.Mod.on("deals") then return end
    local okP, r = pcall(W.postStep, st.post, postClient)
    st.post.last = okP and r or "error"
    if r == "posted" then st.bags = nil end
    U.refresh()
end

-- Multi-buy: selection over the Live lots rows; the line above the Buy button says what the selection buys.
local function modifier()
    local okS, shift = pcall(IsShiftKeyDown or function() return false end)
    if okS and shift then return "shift" end
    local okC, ctrl = pcall(IsControlKeyDown or function() return false end)
    if okC and ctrl then return "ctrl" end
    return nil
end

local function liveRows()
    local D = P.UI.Deals
    return D and D.state and D.state.mode == "lots" and D.state.rows or {}
end

function U.isSelected(r, i) return W.isSelected(st.sel, r, i) end

U.SELECT_HINT = "Select lots to buy several: click a row, shift-click a range, ctrl-click to add or remove."
function U.refreshMulti()
    local f = st.frame
    if not f or not f.wfSel then return end
    local b = st.batch
    if not b or W.batchDone(b) then
        pcall(f.wfSel.SetText, f.wfSel, U.SELECT_HINT)
        f.wfClear:SetShown(false)
    else
        pcall(f.wfSel.SetText, f.wfSel, W.batchText(b.plan, b))
        f.wfClear:SetShown(true)
    end
    pcall(f.wfBuy.SetText, f.wfBuy, U.buyLabel())
end

local function newPlan()
    syncQueue()
    local lots = W.selectedLots(st.sel, liveRows())
    local okM, money = pcall(GetMoney or function() return nil end)
    local plan = W.batchPlan(lots, { cap = st.wf.cap, spent = st.wf.spent, money = okM and plain(money) or nil })
    st.batch = plan.n > 0 and W.newBatch(plan, st.wf) or nil
end

-- A row click selects and repaints; it never rebuilds the rows.
function U.rowClick(i)
    W.select(st.sel, liveRows(), i, modifier())
    newPlan()
    U.refreshMulti()
    repaint()
end

function U.multiCancel()
    W.clearSelection(st.sel)
    st.batch = nil
    U.refreshMulti()
    repaint()
end

function U.setCap(text)
    if type(P.db) ~= "table" then return end
    P.db.opts = P.db.opts or {}
    P.db.opts.wfCap = P.Deals.parseGold(text)
    st.wf.cap = capCopper()
    st.wf.spent, st.wf.expected, st.wf.boughtN = 0, 0, 0 -- a new cap starts a new cycle
    U.refresh()
end

-- Live lots only (UI/Deals.lua D.layout, never in combat: the bar holds a secure button).
function U.setShown(on)
    local f = st.frame
    if f and f.bar then f.bar:SetShown(on and true or false) end
end

-- Called by UI/Deals.lua's build(): the bar under the list, at `top` (Live lots only; hidden in the other modes).
function U.build(f, top)
    st.frame = f
    st.wf.cap = capCopper()
    local bar = CreateFrame("Frame", nil, f)
    bar:SetSize(600, 90)
    bar:SetPoint("TOPLEFT", 0, top or -448)
    f.bar = bar
    f.wfBuy = P.UI.button(bar, "Buy next", 260, 22)
    f.wfBuy:SetPoint("TOPLEFT", 12, 0)
    f.wfBuy:SetScript("OnClick", function() U.buy() end)
    f.wfBuy:SetScript("OnEnter", function(self)
        if P.UI.Deals and P.UI.Deals.tip then
            P.UI.Deals.tip(self, "Buy", U.BUY_TIP)
        end
    end)
    f.wfBuy:SetScript("OnLeave", P.UI.hideTip)
    local b = CreateFrame("Button", "PricewatchDisenchantNext", bar, "SecureActionButtonTemplate")
    b:SetSize(190, 22)
    b:SetPoint("LEFT", f.wfBuy, "RIGHT", 6, 0)
    pcall(b.RegisterForClicks, b, "AnyUp") -- one cast per click (not on both down and up)
    if P.UI.cardStyle then pcall(P.UI.cardStyle, b) end
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.label:SetWidth(180)
    b.label:SetWordWrap(false)
    st.deButton = b
    f.wfDE = b
    f.wfPost = P.UI.button(bar, "Post mats", 110, 22)
    f.wfPost:SetPoint("LEFT", b, "RIGHT", 6, 0)
    f.wfPost:SetScript("OnClick", function() U.postMats() end)
    f.wfSel = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.wfSel:SetPoint("TOPLEFT", 16, -28)
    f.wfSel:SetWidth(500)
    f.wfSel:SetJustifyH("LEFT")
    f.wfSel:SetWordWrap(false)
    f.wfClear = P.UI.button(bar, "Clear", 60, 18)
    f.wfClear:SetPoint("TOPRIGHT", -14, -25)
    f.wfClear:SetScript("OnClick", function() U.multiCancel() end)
    f.wfClear:SetShown(false)
    f.wfCapLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.wfCapLabel:SetPoint("TOPLEFT", 16, -50)
    f.wfCapLabel:SetText("Spend cap (gold, blank = none)")
    f.wfCap = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    f.wfCap:SetSize(60, 20)
    f.wfCap:SetPoint("LEFT", f.wfCapLabel, "RIGHT", 12, 0)
    f.wfCap:SetAutoFocus(false)
    f.wfCap:SetMaxLetters(9)
    f.wfCap:SetText(capCopper() and P.Deals.formatGold(capCopper()) or "")
    f.wfCap:SetScript("OnEnterPressed", function(self) U.setCap(self:GetText()); self:ClearFocus() end)
    f.wfCap:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.wfSummary = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.wfSummary:SetPoint("TOPLEFT", 16, -74)
    f.wfSummary:SetWidth(568)
    f.wfSummary:SetJustifyH("LEFT")
    bar:SetShown(false)
    U.refresh()
    U.refreshMulti()
end
U.BUY_TIP = "One purchase per click. With rows selected it buys those lots (best first); without a selection it buys the top"
    .. " lot. Each lot is checked again first: gone or pricier lots are skipped."

local ev = CreateFrame("Frame")
U.frame = ev
for _, e in ipairs({ "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED", "BAG_UPDATE_DELAYED",
    "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_SUCCEEDED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "ITEM_SEARCH_RESULTS_UPDATED" then
        st.loadedItem = type(a1) == "table" and plain(a1.itemID) or nil
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        st.loadedCommodity = plain(a1)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- combat values can be secret on Forever: never compare them unchecked
        local unit, spell = plain(a1), plain(a3)
        if unit == "player" and spell == DISENCHANT and st.target then
            local id = st.target.itemID
            if (st.wf.bought[id] or 0) > 0 then st.wf.bought[id] = st.wf.bought[id] - 1 end
            st.bags = nil
        end
        return
    end
    if event == "BAG_UPDATE_DELAYED" then st.bags = nil end
    if st.frame then pcall(U.refresh) end
end)
