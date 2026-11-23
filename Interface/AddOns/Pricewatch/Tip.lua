local _, P = ...
P.Tip = {}
local T = P.Tip

local GREEN, WHITE, GREY = { 0.25, 1, 0.25 }, { 1, 1, 1 }, { 0.6, 0.6, 0.6 }
local CLOSE = { 0.85, 0.82, 0.6 } -- close call: neither side wins by the margin (light grey-yellow, not the confident white or green)
local LABEL = { 0.78, 0.72, 0.5 } -- grey-gold label colour of the detail lines
local OLD_DAYS = 3                -- a price older than this many scan days is shown grey with an age note

-- Pure: what the tooltip line should say for one item. deps = { info(id) -> {quality, classID, ilvl, vendor, bindType},
-- price(id) -> AH copper or nil, skill() -> enchanting skill or nil }.
-- Returns nil for items that cannot be disenchanted (no line), nil, "uncached" when the client has no item info yet,
-- else { action = disenchant | sell | vendor | nodata, gain, alt (what it was compared with), needSkill, de (estimate before
-- the cut), vendor, age (oldest price used, scan days) }. price(id) may return a second value, the price's age.
T.requested = {} -- ids the client was already asked to load (cleared when the info arrives or the cache is reset)

function T.evaluate(id, bound, deps, link)
    if type(id) ~= "number" then return nil end
    local ok, info = pcall(deps.info, id, link)
    -- No quality or class means the client has not cached the item yet: ask it once, remember nothing.
    if not ok or type(info) ~= "table" or info.quality == nil or info.classID == nil then
        if deps.request and not T.requested[id] then
            T.requested[id] = true
            pcall(deps.request, id)
        end
        return nil, "uncached"
    end
    local outcomes, deMeta = P.DE.outcomes(info.quality, info.classID, info.ilvl)
    if not outcomes then return nil end
    local age
    -- Per-evaluation memo (audit step 3): each id is priced and its p(sell) asked once, however often it is needed.
    local memoP, memoS = {}, {}
    local function price(x)
        local m = memoP[x]
        if m == nil then
            local okp, p, a = pcall(deps.price, x)
            m = (okp and type(p) == "number" and p > 0) and { p, a } or false
            memoP[x] = m
        end
        if not m then return nil end
        if type(m[2]) == "number" and (not age or m[2] > age) then age = m[2] end
        return m[1]
    end
    local function pOf(x)
        local v = memoS[x]
        if v == nil then v = (P.Reco.pSell(x, deps)) memoS[x] = v end
        return v
    end
    -- Disenchant side: every mat valued at its price x its own chance of selling (the cut is taken on the total, as before).
    -- de stays the plain estimate (what the Shift line shows). One pass gives both (P.DE.valueEV).
    local de, deEV = P.DE.valueEV(outcomes, price, pOf)
    -- AH side: price after the cut x p(sell) - deposit x (1 - p(sell)). Bound items cannot be listed: no p(sell), no deposit.
    local ah = (not bound) and price(id) or nil
    local pItem, deposit, ahEV
    if ah then
        pItem = pOf(id)
        deposit = P.Reco.deposit(id, info.vendor, deps)
        ahEV = P.Reco.ahValue(ah, pItem, deposit)
    end
    local action, gain, alt, close = P.Reco.decide(deEV, ah, info.vendor, bound, nil, ahEV)
    if close and gain and gain < 0 then action, gain, alt = "disenchant", -gain, action end -- disenchant leads, inside the margin
    local res = { action = action, gain = gain, alt = alt, close = close == true, de = de, deEV = P.Reco.net(deEV), ahEV = ahEV, pSell = pItem,
        deposit = deposit, vendor = info.vendor, age = age, deMeta = deMeta }
    local need = P.DE.skillFor(info.quality, info.ilvl)
    local okS, have = pcall(deps.skill)
    if need and okS and type(have) == "number" and need > have then res.needSkill = need end
    return res
end

local VS = { sell = "selling", vendor = "vendor", disenchant = "disenchant" }

-- The verdict line as left text, right text and a colour { r, g, b }, for a result from T.evaluate. A price older than
-- OLD_DAYS turns the line grey and gets an orange age note.
function T.parts(r)
    local left, right, c
    if r.action == "nodata" then
        left, c = "No price data", GREY
    else
        left = r.action == "disenchant" and "Disenchant" or (r.action == "sell" and "Sell on AH" or "Vendor")
        c = r.action == "disenchant" and GREEN or WHITE
        if r.close then
            left = "Close call: " .. (r.action == "sell" and "sell on AH" or r.action)
            c = CLOSE
            if r.gain and r.gain > 0 then right = "(+" .. P.Money.format(r.gain) .. ")" end
        elseif r.gain and r.gain > 0 then
            right = "+" .. P.Money.format(r.gain) .. " vs " .. (VS[r.alt] or "other")
        else
            right = "similar value"
        end
    end
    if r.needSkill then right = (right and (right .. " ") or "") .. "(needs enchanting " .. r.needSkill .. ")" end
    if r.action ~= "nodata" and type(r.age) == "number" and r.age > OLD_DAYS then
        c = GREY
        right = (right and (right .. " ") or "") .. "|cffff8800(" .. r.age .. "d old)|r"
    end
    return left, right, c
end

-- One string and colour for a result (the item window shows this): "Disenchant: +1g vs selling".
function T.format(r)
    local left, right, c = T.parts(r)
    local sep = r.close and " " or ": " -- "Close call: sell on AH (+2s 5c)"
    return right and (left .. sep .. right) or left, c[1], c[2], c[3]
end

-- "With Shift" (default), "Always" or "Never": when the number lines behind the verdict show. Saved in PricewatchDB.
local MODES = { shift = true, always = true, never = true }
function T.mode()
    local m = type(P.db) == "table" and type(P.db.opts) == "table" and P.db.opts.tipDetails
    return MODES[m] and m or "shift"
end
function T.setMode(m)
    if not MODES[m] or type(P.db) ~= "table" then return false end
    P.db.opts = P.db.opts or {}
    P.db.opts.tipDetails = m
    return true
end

-- "auto" (default), "on" or "off": whether the Shift Market price line shows. auto hides it for items ZugDAQ's own tooltip already
-- carries a market price for (the same number twice); the verdict line is never affected. Saved in PricewatchDB.
local MARKET_MODES = { auto = true, on = true, off = true }
function T.marketMode()
    local m = type(P.db) == "table" and type(P.db.opts) == "table" and P.db.opts.tipMarket
    return MARKET_MODES[m] and m or "auto"
end
function T.setMarketMode(m)
    if not MARKET_MODES[m] or type(P.db) ~= "table" then return false end
    P.db.opts = P.db.opts or {}
    P.db.opts.tipMarket = m
    return true
end

-- `/pricewatch tip market <arg>`: returns ok and the text to print.
function T.marketCommand(arg)
    arg = type(arg) == "string" and arg:lower():match("^%s*(%a*)") or ""
    if arg ~= "" then
        if not T.setMarketMode(arg) then return false, "Pricewatch: use /pricewatch tip market on, off or auto." end
        return true, "Pricewatch: tooltip Market line: " .. arg
    end
    return true, "Pricewatch: tooltip Market line is '" .. T.marketMode() .. "' (auto hides it where ZugDAQ shows its price). Use /pricewatch tip market on, off or auto."
end

local function shiftDown()
    if type(IsShiftKeyDown) ~= "function" then return false end
    local ok, down = pcall(IsShiftKeyDown)
    return ok and down == true
end

-- True when Auctionator's own tooltip already shows the vendor price (its setting; guarded, unknown counts as off).
local function vendorShownByAuctionator()
    local cfg = Auctionator and Auctionator.Config
    if type(cfg) ~= "table" or type(cfg.Get) ~= "function" or type(cfg.Options) ~= "table" or not cfg.Options.VENDOR_TOOLTIP then return false end
    local ok, v = pcall(cfg.Get, cfg.Options.VENDOR_TOOLTIP)
    return ok and v == true
end

-- The number lines shown with Shift: { { label, right text } }, at most five, in the order Market, Disenchant est.,
-- Vendor (when above zero and Auctionator is not showing it), You (3 or more outcomes), Market sold (3+ tracked scans). count = stack size (values x count).
-- deps.value(id) -> P.Value table or nil, deps.outcomes(id) -> { sold, expired, cancelled, avgSold } or nil.
function T.details(id, r, deps, count)
    local out = {}
    local mult = (type(count) == "number" and count > 1) and count or 1
    local x = mult > 1 and (" x" .. mult) or ""
    local okV, v = pcall(deps.value or function() return nil end, id)
    -- The Market price line: hidden for "off", and in "auto" when ZugDAQ's own tooltip already shows its price for this item.
    local mm = T.marketMode()
    local hide = mm == "off"
    if mm == "auto" and type(deps.zugShows) == "function" then
        local okZ, shows = pcall(deps.zugShows, id)
        hide = okZ and shows == true
    end
    if not hide and okV and type(v) == "table" and type(v.market) == "number" then
        local right = P.Money.coins(v.market * mult)
        local t = v.trendPct
        if type(t) == "number" and t ~= 0 then
            right = right .. (t > 0 and " |cff40ff40+" or " |cffff4040") .. t .. "%|r"
        end
        if type(r.pSell) == "number" then right = right .. "  Sells ~" .. math.floor(r.pSell * 100 + 0.5) .. "%" end
        local source = v.source == "zugdaq" and "ZugDAQ" or (P.Config.MARKET_DAYS .. "d scan")
        out[#out + 1] = { "Market (" .. source .. ")" .. x, right }
    elseif type(r.pSell) == "number" then
        out[#out + 1] = { "AH", "Sells ~" .. math.floor(r.pSell * 100 + 0.5) .. "%" }
    end
    local okH, zh = pcall(T.zugHistoryLine, id)
    if okH and zh then out[#out + 1] = zh end
    if type(r.de) == "number" then out[#out + 1] = { P.DELog.label(r.deMeta) .. x, P.Money.coins(r.de * mult) } end
    if type(r.vendor) == "number" and r.vendor > 0 and not vendorShownByAuctionator() then
        out[#out + 1] = { "Vendor" .. x, P.Money.coins(r.vendor * mult) }
    end
    local okO, o = pcall(deps.outcomes or function() return nil end, id)
    if okO and type(o) == "table" then
        local sold, expired, cancelled = tonumber(o.sold) or 0, tonumber(o.expired) or 0, tonumber(o.cancelled) or 0
        local total = sold + expired + cancelled
        if total >= 3 then
            local text = ("sold %d/%d (%d%%)"):format(sold, total, math.floor(sold / total * 100 + 0.5))
            if type(o.avgSold) == "number" and o.avgSold > 0 then text = text .. ", avg " .. P.Money.format(o.avgSold) end
            out[#out + 1] = { "You", text }
        end
    end
    -- Sold tracker: only with enough tracked scans (the rough figure lives in the item view, where it is labelled).
    local okM, m = pcall(deps.market or function() return nil end, id)
    if okM and type(m) == "table" and not m.thin then
        local text = P.Market.text(m)
        if text then out[#out + 1] = { "Market", text } end
    end
    return out
end

-- Per item, item level, bound flag and scan day: hovering the same item again costs nothing. An uncached item is not
-- remembered. get returns the result, or nil and the reason ("uncached", "no outcomes", "cached false").
-- map = { [id] = { ["ilvl" .. "b|u"] = result or false } }, so one item can be forgotten on its own (forget). hits and misses
-- count lookups since the last full reset (/pricewatch tip stats; audit step 2 wants a hit rate above 50%).
function T.newCache()
    local c = { day = nil, map = {}, hits = 0, misses = 0 }
    function c:get(id, bound, day, deps, link, ilvl)
        if self.day ~= day then self.day, self.map = day, {} end
        local sub = tostring(ilvl or "") .. (bound and "b" or "u")
        local per = id ~= nil and self.map[id] or nil
        local hit = nil
        if type(per) == "table" then hit = per[sub] end -- false (cached "no verdict") must survive
        if hit ~= nil then
            self.hits = (self.hits or 0) + 1
            if hit then return hit end
            return nil, "cached false"
        end
        self.misses = (self.misses or 0) + 1
        local r, why = T.evaluate(id, bound, deps, link)
        if why ~= "uncached" and id ~= nil then
            if type(per) ~= "table" then per = {} self.map[id] = per end
            per[sub] = r or false
        end
        return r, why or (not r and "no outcomes" or nil)
    end
    -- Forget every remembered verdict of one item (all item levels, bound or not).
    function c:forget(id)
        if id ~= nil and type(self.map) == "table" then self.map[id] = nil end
    end
    return c
end

-- Item id from an item link (a link, never tooltip text). Secret values (WoW Forever) are refused.
function T.idFromLink(link)
    if type(link) ~= "string" then return nil end
    if issecretvalue and issecretvalue(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function deps()
    return {
        info = P.Adapters.itemInfo,
        request = P.Adapters.requestItem,
        value = function(id) return P.Value.market(id) end,
        zugShows = P.Adapters.zugShows,
        zug = P.Adapters.zug,
        outcomes = P.Adapters.salesmanOutcomes,
        deposit = P.Adapters.auctionDeposit,
        price = function(id) return P.Value.price(id) end,
        skill = P.Adapters.enchantingSkill,
        market = function(id) if not P.Mod.on("market") then return nil end return P.Market.summary(P.db, id, P.Days.dayOf(time(), P.Days.epoch0())) end,
    }
end

T.deps = deps
local cache = T.newCache()
T.cache = cache
P.Mod.listen("tooltip", function() T.resetCache() end)
P.Mod.listen("market", function() T.resetCache() end)
P.Mod.listen("zugdaq", function() T.resetCache() end)

-- Shift details: ZugHistory's server-wide 30-day median with its range, from P.Config.ZUGH_MIN_N priced days; nil otherwise.
function T.zugHistoryLine(id)
    local h = P.Adapters.zugHistory(id, 30)
    if not h or (h.n or 0) < P.Config.ZUGH_MIN_N then return nil end
    local right = P.Money.coins(h.median)
    if h.low and h.high then right = right .. " (" .. P.Money.format(h.low) .. " - " .. P.Money.format(h.high) .. ")" end
    return { "Server " .. h.n .. "d median", right .. ", " .. h.n .. "d" }
end

-- Forget every remembered verdict (and, unless keepRequests, which items were asked for): called when prices, skills or item
-- info may have changed (auction house closed, skill lines changed, item info received).
function T.resetCache(keepRequests)
    cache.day, cache.map = nil, {}
    cache.hits, cache.misses = 0, 0
    if P.Value.resetMemo then P.Value.resetMemo() end
    if not keepRequests then T.requested = {} end
end

-- GET_ITEM_INFO_RECEIVED: only that item's own verdicts can change (a mat's item info never changes a price). Audit step 2:
-- this used to wipe the whole cache, thousands of times while browsing the AH.
function T.forgetItem(id)
    if type(id) == "number" then
        cache:forget(id)
        if P.Value.forget then P.Value.forget(id) end
    end
end

-- Lookups since the last full reset: { hits, misses, rate (percent, nil before any lookup) }.
function T.cacheStats()
    local h, m = cache.hits or 0, cache.misses or 0
    return { hits = h, misses = m, rate = (h + m) > 0 and math.floor(h / (h + m) * 100 + 0.5) or nil }
end

-- The client's item info arrived (GET_ITEM_INFO_RECEIVED). A success lets the item be requested again if it is ever
-- missed again; a failure keeps it marked, so a missing item is not asked for on every hover.
function T.onItemInfo(id, success)
    if type(id) == "number" and success ~= false then T.requested[id] = nil end
end

-- Soulbound-ness of the item under the tooltip, from the owner's bag and slot (bag buttons): true / false, or nil when it
-- cannot be told. Everything guarded; the slot must hold this very item.
local function ownerBound(tooltip, id)
    if not (tooltip and tooltip.GetOwner and ItemLocation and ItemLocation.CreateFromBagAndSlot and C_Item and C_Item.IsBound) then return nil end
    local okO, owner = pcall(tooltip.GetOwner, tooltip)
    if not okO or type(owner) ~= "table" then return nil end
    local bag, slot
    if type(owner.GetBagID) == "function" then
        local ok, v = pcall(owner.GetBagID, owner)
        if ok and type(v) == "number" then bag = v end
    end
    if bag == nil and type(owner.GetParent) == "function" then
        local okP, parent = pcall(owner.GetParent, owner)
        if okP and type(parent) == "table" and type(parent.GetID) == "function" then
            local ok, v = pcall(parent.GetID, parent)
            if ok and type(v) == "number" then bag = v end
        end
    end
    if type(owner.GetID) == "function" then
        local ok, v = pcall(owner.GetID, owner)
        if ok and type(v) == "number" then slot = v end
    end
    if not bag or not slot or slot < 1 then return nil end
    if C_Container and C_Container.GetContainerItemID then
        local okI, held = pcall(C_Container.GetContainerItemID, bag, slot)
        if okI and held ~= id then return nil end
    end
    local okL, loc = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
    if not okL or not loc then return nil end
    local okB, b = pcall(C_Item.IsBound, loc)
    if okB and type(b) == "boolean" then return b end
    return nil
end

-- Adds the line to a tooltip. id comes from the tooltip's item data/link; link (optional, may be a secret value that is
-- only ever checked, never read) gives the item level; bound from the bag item location when the data carries one,
-- else BoP from the item's bind type. Every early return records T.lastSkip (shown by /pricewatch why).
-- The verdict line is drawn larger and outlined (a bolder look). Tooltip lines are reused, so the normal font is put
-- back when the tooltip is cleared. Only font objects are touched, never the text.
T.BIG_EXTRA = 3
local bigLines = setmetatable({}, { __mode = "k" })
local restoreHooked = setmetatable({}, { __mode = "k" })

local function restore(tooltip)
    local list = bigLines[tooltip]
    if not list then return end
    for _, fs in ipairs(list) do pcall(fs.SetFontObject, fs, GameTooltipText) end
    bigLines[tooltip] = nil
end
T.restoreFonts = restore

function T.emphasize(tooltip, n)
    if not tooltip or not tooltip.GetName then return end
    local okName, name = pcall(tooltip.GetName, tooltip)
    if not okName or type(name) ~= "string" then return end
    local base = GameTooltipText and GameTooltipText.GetFont
    if not base then return end
    local okF, file, size = pcall(GameTooltipText.GetFont, GameTooltipText)
    if not okF or not file or type(size) ~= "number" then return end
    for _, side in ipairs({ "Left", "Right" }) do
        local fs = _G[name .. "Text" .. side .. n]
        if fs and fs.SetFont and pcall(fs.SetFont, fs, file, size + T.BIG_EXTRA, "OUTLINE") then
            bigLines[tooltip] = bigLines[tooltip] or {}
            table.insert(bigLines[tooltip], fs)
        end
    end
    if not restoreHooked[tooltip] and tooltip.HookScript and tooltip.HasScript then
        local okH, has = pcall(tooltip.HasScript, tooltip, "OnTooltipCleared")
        if okH and has then
            restoreHooked[tooltip] = true
            pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", restore)
        end
    end
end

function T.decorate(tooltip, id, guid, link, count)
    if not P.Mod.on("tooltip") then return end -- switched off in NectarKit: no lookups, no line
    id = plain(id)
    if type(id) ~= "number" then
        T.lastSkip = (link ~= nil and issecretvalue and issecretvalue(link)) and "secret link" or "no id"
        return
    end
    if not tooltip or not tooltip.AddLine then T.lastSkip = "no tooltip"; return end
    link = plain(link)
    if type(link) ~= "string" then link = nil end
    local bound
    guid = plain(guid)
    if type(guid) == "string" and C_Item and C_Item.GetItemLocation and C_Item.IsBound then
        local okL, loc = pcall(C_Item.GetItemLocation, guid)
        if okL and loc then
            local okB, b = pcall(C_Item.IsBound, loc)
            if okB and type(b) == "boolean" then bound = b end
        end
    end
    if type(count) ~= "number" and type(guid) == "string" and C_Item and C_Item.GetItemLocation and C_Item.GetStackCount then
        local okL, loc = pcall(C_Item.GetItemLocation, guid)
        local okC, n = pcall(C_Item.GetStackCount, okL and loc or nil)
        if okC and type(n) == "number" and n > 1 then count = n end
    end
    local info = P.Adapters.itemInfo(id, link)
    if bound == nil then bound = ownerBound(tooltip, id) end
    if bound == nil then bound = info.bindType == 1 end
    local day = P.Days.dayOf(time(), P.Days.epoch0())
    local d = deps()
    local r, why = cache:get(id, bound, day, d, link, link and info.ilvl or nil)
    if not r then T.lastSkip = why or "no outcomes"; return end
    T.lastSkip = nil
    local left, right, c = T.parts(r)
    if tooltip.AddDoubleLine and right then
        tooltip:AddDoubleLine(left, right, c[1], c[2], c[3], c[1], c[2], c[3])
    else
        tooltip:AddLine(right and (left .. ": " .. right) or left, c[1], c[2], c[3])
    end
    if tooltip.NumLines then
        local okN, n = pcall(tooltip.NumLines, tooltip)
        if okN and type(n) == "number" then T.emphasize(tooltip, n) end
    end
    local mode = T.mode()
    if r.action ~= "nodata" and tooltip.AddDoubleLine and (mode == "always" or (mode == "shift" and shiftDown())) then
        for _, l in ipairs(T.details(id, r, d, count)) do
            tooltip:AddDoubleLine(l[1], l[2], LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
        end
    end
    -- Resize, or the new line is clipped off the bottom of the tooltip.
    if tooltip.Show then pcall(tooltip.Show, tooltip) end
end

-- Shift went down or up (MODIFIER_STATE_CHANGED). Deliberately does nothing: calling GameTooltip:RefreshData() or the
-- owner's OnEnter from addon code taints the tooltip, and Blizzard's line code then errors on secret colours
-- (seen in game 2026-11-21, SharedTooltipTemplates.lua:167). The Shift lines show on the next hover.
function T.onModifier(key)
    return
end

-- Runs fn; an error is kept (for /pricewatch why) instead of thrown into the tooltip.
local function guarded(fn)
    local ok, err = pcall(fn)
    if not ok then T.lastError = tostring(err) end
end

-- Step-by-step report for one item (/pricewatch why <item link or id>): which hook, how often it fired, last error,
-- item info, disenchant outcomes, prices and the result.
function T.diagnose(id, link)
    local out = {}
    local function add(s) out[#out + 1] = s end
    add("hook: " .. tostring(T.path) .. ", fired " .. tostring(T.fires or 0) .. "x, last error: " .. tostring(T.lastError or "none"))
    add("skip: " .. tostring(T.lastSkip or "none (last hover added a line)"))
    if type(id) ~= "number" then add("no item id"); return out end
    local okI, info = pcall(P.Adapters.itemInfo, id, link)
    if not okI or type(info) ~= "table" then add("item info failed: " .. tostring(info)); return out end
    add(("item %d: quality %s, class %s, ilvl %s, vendor %s, bind %s"):format(id, tostring(info.quality),
        tostring(info.classID), tostring(info.ilvl), tostring(info.vendor), tostring(info.bindType)))
    local outcomes = P.DE.outcomes(info.quality, info.classID, info.ilvl)
    if not outcomes then add("no disenchant outcomes for this quality/class/ilvl"); return out end
    for _, o in ipairs(outcomes) do
        local okP, p = pcall(P.Value.price, o.id)
        add(("mat %d: %.0f%% x %.1f, Market %s"):format(o.id, o.chance * 100, o.avg, tostring(okP and p or "error")))
    end
    local okA, ah = pcall(P.Value.price, id)
    add("item AH price: " .. tostring(okA and ah or "error"))
    local r, why = T.evaluate(id, info.bindType == 1, deps(), link)
    add("result: " .. (r and (T.format(r)) or tostring(why or "no line")))
    return out
end

-- Hooks the item tooltips once. Every call is guarded: a missing or different tooltip API only means no line.
function T.install()
    if T.installed then return end
    T.installed = true
    -- WoW Forever has both APIs. Like DisenchantBuddy, use the old OnTooltipSetItem hook whenever the tooltip has it.
    local legacy = false
    if GameTooltip and GameTooltip.HasScript then
        local okH, has = pcall(GameTooltip.HasScript, GameTooltip, "OnTooltipSetItem")
        legacy = okH and has == true
    end
    T.path = legacy and "OnTooltipSetItem" or "none"
    if not legacy and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        T.path = "TooltipDataProcessor"
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip, data)
            T.fires = (T.fires or 0) + 1
            guarded(function()
                if type(data) ~= "table" then return end
                local id = plain(data.id) or T.idFromLink(plain(data.hyperlink))
                T.decorate(tooltip, id, data.guid, data.hyperlink)
            end)
        end)
        return
    end
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip.HookScript then
            pcall(tip.HookScript, tip, "OnTooltipSetItem", function(self)
                T.fires = (T.fires or 0) + 1
                guarded(function()
                    local _, link = self:GetItem()
                    T.decorate(self, T.idFromLink(plain(link)), nil, link)
                end)
            end)
        end
    end
end
