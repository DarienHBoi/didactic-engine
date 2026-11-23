local _, P = ...
-- Disenchant workflow on the Deals panel (owner 2026-11-21): Scan (Live lots) -> Buy next -> Disenchant next -> Post mats.
-- Hard limits: nothing happens without a click; one purchase, one cast or one post per hardware click; nothing protected runs
-- from a timer. This file is pure (the AH client is injected); UI/Workflow.lua owns the buttons.
P.Workflow = {}
local W = P.Workflow

-- The buy queue: every lot of a Live lots pass that beats its buyout by the Min profit and passes the skill gate, best profit
-- first, one entry per auction. rows = LotScan job rows; opts = { margin, includeHighSkill }.
function W.queue(rows, opts)
    opts = opts or {}
    local out, seen = {}, {}
    for _, r in ipairs(rows or {}) do
        if r.auctionID and not seen[r.auctionID] and P.LotScan.keep(r, opts) then
            seen[r.auctionID] = true
            out[#out + 1] = r
        end
    end
    table.sort(out, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.auctionID < b.auctionID
    end)
    return out
end

-- opts.cap = spend cap in copper (nil = none, the owner's default).
function W.new(queue, opts)
    opts = opts or {}
    return { queue = queue or {}, cap = opts.cap, spent = 0, expected = 0, bought = {}, boughtN = 0, posted = 0, last = nil }
end

local function drop(st) table.remove(st.queue, 1) end

-- One click of "Buy next". client: current(itemKey) -> loaded search results for that key or nil, search(itemKey),
-- placeBid(auctionID, copper), getMoney(). Returns "empty", "cap", "money", "checking" (searched; click again), "gone",
-- "pricier" (both dropped, nothing bought), "bought" or "error". At most one PlaceBid per call.
function W.buyStep(st, client)
    local lot = st.queue[1]
    if not lot then st.last = "empty" return "empty" end
    local okR, list = pcall(client.current, lot.itemKey)
    if not okR then st.last = "error" return "error" end
    if type(list) ~= "table" then
        local okS = pcall(client.search, lot.itemKey)
        st.last = okS and "checking" or "error"
        return st.last
    end
    local found
    for _, info in ipairs(list) do
        if type(info) == "table" and info.auctionID == lot.auctionID then found = info break end
    end
    if not found or type(found.buyoutAmount) ~= "number" then drop(st) st.last = "gone" return "gone" end
    local price = found.buyoutAmount
    if price > lot.buy then drop(st) st.last = "pricier" return "pricier" end
    if st.cap and st.spent + price > st.cap then st.last = "cap" return "cap" end
    local okM, money = pcall(client.getMoney)
    if okM and type(money) == "number" and money < price then st.last = "money" return "money" end
    local okB, placed = pcall(client.placeBid, lot.auctionID, price)
    if not okB or placed == false then st.last = "error" return "error" end
    drop(st)
    st.spent = st.spent + price
    st.expected = st.expected + (lot.gets - price)
    st.bought[lot.id] = (st.bought[lot.id] or 0) + (lot.qty or 1)
    st.boughtN = st.boughtN + 1
    st.last = "bought"
    return "bought"
end

local LAST_TEXT = { gone = "last lot was gone, skipped", pricier = "price went up, skipped", cap = "spend cap reached",
    money = "not enough gold", error = "the auction house refused (try again)", checking = "checking the price: click again",
    bought = "bought" }

function W.buyLabel(st)
    local lot = st.queue[1]
    if not lot then return "Buy next: queue empty" end
    if st.cap and st.spent + lot.buy > st.cap then return "Buy next: spend cap reached" end
    return ("Buy next: %s x%d for %s (+%s)"):format(lot.name or ("Item " .. lot.id), lot.qty or 1, P.Money.format(lot.buy),
        P.Money.format(lot.gets - lot.buy))
end

function W.summary(st)
    local cap = st.cap and (" of cap " .. P.Money.format(st.cap)) or ""
    local last = st.last and LAST_TEXT[st.last] and (" Last: " .. LAST_TEXT[st.last] .. ".") or ""
    return ("Spent %s%s on %d lot%s, expected +%s after disenchanting. %d queued.%s"):format(P.Money.format(st.spent), cap,
        st.boughtN, st.boughtN == 1 and "" or "s", P.Money.format(st.expected), #st.queue, last)
end

-- The next bag item bought this cycle (bags = { { bag, slot, itemID } } in bag order), or nil.
function W.deTarget(bags, bought)
    for _, b in ipairs(bags or {}) do
        if bought and (bought[b.itemID] or 0) > 0 then return b end
    end
    return nil
end

function W.macro(t) return "/cast Disenchant\n/use " .. t.bag .. " " .. t.slot end

-- Post price for one mat: 1c under the lowest listing, never below floorPct (0.9) of the reference (the mat consensus price).
-- When the AH is under that floor: the floor (opts.atFloor, default) or nil (skip). Nothing listed: the reference.
function W.postPrice(lowest, ref, opts)
    opts = opts or {}
    local pct = opts.floorPct or P.Config.POST_FLOOR
    local atFloor = opts.atFloor ~= false
    local floor = ref and math.max(1, math.floor(ref * pct + 0.5)) or nil
    if not lowest then return ref end
    local under = math.max(1, lowest - 1)
    if not floor or under >= floor then return under end
    return atFloor and floor or nil
end

-- One click of "Post mats". client: nextMat() -> { bag, slot, itemID, count } or nil, lowest(itemID) -> loaded lowest unit
-- price or nil, searchCommodity(itemID), ref(itemID), post(bag, slot, count, unitPrice). Returns "none", "checking", "skip",
-- "noprice", "posted" or "error". At most one post per call.
function W.postStep(st, client, opts)
    local okN, mat = pcall(client.nextMat)
    if not okN then return "error" end
    if not mat then st.last = "none" return "none" end
    local okL, lowest = pcall(client.lowest, mat.itemID)
    if not okL then return "error" end
    if lowest == nil and not st.searched then
        st.searched = mat.itemID
        local okS = pcall(client.searchCommodity, mat.itemID)
        return okS and "checking" or "error"
    end
    st.searched = nil
    local okF, ref = pcall(client.ref, mat.itemID)
    local price = W.postPrice(lowest, okF and ref or nil, opts)
    if not price then return (okF and ref) and "skip" or "noprice" end
    local okP, done = pcall(client.post, mat.bag, mat.slot, mat.count, price)
    if not okP or done == false then return "error" end
    st.posted = (st.posted or 0) + mat.count * price
    st.lastPost = { itemID = mat.itemID, count = mat.count, price = price }
    return "posted"
end

-- Multi-buy (owner 2026-11-21: "Click and shift click, then prompted with a buy multiple"). Selection over Live lots view rows:
-- a click selects one row, shift-click the range from the last clicked row, ctrl-click toggles one. Group heads stand for all
-- their lots. The batch then buys ONE lot per click of its Buy button through the same re-check as Buy next (W.buyStep).
local function rowKey(r, i)
    if r.group then return "g:" .. tostring(r.key) end
    if r.auctionID then return "a:" .. tostring(r.auctionID) end
    return "i:" .. i
end

function W.newSelection() return { keys = {}, anchor = nil } end

function W.isSelected(sel, r, i) return sel.keys[rowKey(r, i)] == true end

-- mod = nil (plain click), "shift" or "ctrl".
function W.select(sel, rows, i, mod)
    local r = rows[i]
    if not r then return end
    if mod == "ctrl" then
        local k = rowKey(r, i)
        sel.keys[k] = not sel.keys[k] or nil
        sel.anchor = i
    elseif mod == "shift" and sel.anchor and rows[sel.anchor] then
        sel.keys = {}
        local a, b = math.min(sel.anchor, i), math.max(sel.anchor, i)
        for j = a, b do sel.keys[rowKey(rows[j], j)] = true end
    else
        sel.keys = { [rowKey(r, i)] = true }
        sel.anchor = i
    end
end

function W.clearSelection(sel) sel.keys, sel.anchor = {}, nil end

-- The lots behind the selection (group heads bring all their lots), once each, best profit first.
function W.selectedLots(sel, rows)
    local out, seen = {}, {}
    local function add(l)
        if l.auctionID and not seen[l.auctionID] then seen[l.auctionID] = true; out[#out + 1] = l end
    end
    for i, r in ipairs(rows or {}) do
        if W.isSelected(sel, r, i) then
            if r.group then for _, l in ipairs(r.lots or {}) do add(l) end else add(r) end
        end
    end
    table.sort(out, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.auctionID < b.auctionID
    end)
    return out
end

-- The prompt: lots in order while they fit what is left of the spend cap (opts.cap - opts.spent) and the gold (opts.money).
function W.batchPlan(lots, opts)
    opts = opts or {}
    local room = opts.cap and (opts.cap - (opts.spent or 0)) or nil
    local plan = { lots = {}, n = 0, total = 0, expected = 0, trimmed = 0, trimmedBy = nil }
    for _, l in ipairs(lots or {}) do
        local t = plan.total + l.buy
        if room and t > room then plan.trimmed, plan.trimmedBy = plan.trimmed + 1, plan.trimmedBy or "cap"
        elseif opts.money and t > opts.money then plan.trimmed, plan.trimmedBy = plan.trimmed + 1, plan.trimmedBy or "money"
        else
            plan.lots[#plan.lots + 1] = l
            plan.n, plan.total, plan.expected = plan.n + 1, t, plan.expected + (l.gets - l.buy)
        end
    end
    return plan
end

function W.batchText(plan, b)
    local s = ("Buy %d lot%s for %s total, expected +%s after disenchanting."):format(plan.n, plan.n == 1 and "" or "s",
        P.Money.format(plan.total), P.Money.format(plan.expected))
    if plan.trimmed > 0 then
        s = s .. (" %d left out (%s)."):format(plan.trimmed, plan.trimmedBy == "cap" and "spend cap" or "not enough gold")
    end
    if b and (b.bought > 0 or b.skipped > 0) then
        s = s .. (" %d bought, %d skipped."):format(b.bought, b.skipped)
    end
    return s
end

-- A batch runs on the main workflow state's cycle: spend, expected, cap and the Disenchant next list are shared with it.
function W.newBatch(plan, main)
    local q = {}
    for i, l in ipairs(plan.lots or {}) do q[i] = l end
    return { plan = plan, main = main, queue = q, bought = 0, skipped = 0, last = nil }
end

function W.batchDone(b) return #b.queue == 0 end

-- One click of the batch's Buy button: at most one PlaceBid (W.buyStep on a view of the main cycle).
function W.batchStep(b, client)
    local m = b.main
    local view = { queue = b.queue, cap = m.cap, spent = m.spent, expected = m.expected, bought = m.bought, boughtN = m.boughtN }
    local lot = b.queue[1]
    local r = W.buyStep(view, client)
    m.spent, m.expected, m.boughtN, m.last = view.spent, view.expected, view.boughtN, r
    if r == "bought" then
        b.bought = b.bought + 1
        for i = #m.queue, 1, -1 do if m.queue[i].auctionID == lot.auctionID then table.remove(m.queue, i) end end
    elseif r == "gone" or r == "pricier" then
        b.skipped = b.skipped + 1
    end
    b.last = r
    return r
end

function W.batchLabel(b)
    local lot = b.queue[1]
    if not lot then return "Done" end
    if b.last == "cap" then return "Spend cap reached" end
    if b.last == "money" then return "Not enough gold" end
    return ("Buy %d of %d (%s)"):format(b.bought + b.skipped + 1, b.plan.n, P.Money.format(lot.buy))
end
