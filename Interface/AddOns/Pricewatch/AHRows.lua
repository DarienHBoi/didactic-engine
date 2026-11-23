local _, P = ...
-- Disenchant value on the rows of the auction house item buy list (AuctionHouseFrame.ItemBuyFrame.ItemList).
-- This file is the pure part (what a row shows); the hook that draws it is UI/AHRows.lua. Same maths as the Deals panel:
-- de = P.DE.unitValue(...).de (the one DE maths, shared with Deals and Live lots); profitable when P.Reco.beats(de, buy, Deals Min profit).
P.AHRows = {}
local R = P.AHRows

local GOOD, DIM, UNKNOWN, SKILL = { 0.25, 1, 0.25 }, { 0.6, 0.6, 0.6 }, { 0.45, 0.45, 0.45 }, { 1, 0.5, 0.1 }

-- A plain number we may compare (combat-era values can be secret on Forever: never compare those).
local ARROW = " |TInterface\\Buttons\\Arrow-Down-Up:0|t" -- trend guard: a mat in this disenchant is falling

local function plain(v)
    if type(v) ~= "number" then return nil end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end

local function plainString(v)
    if type(v) ~= "string" then return nil end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end

-- The sources a row uses in game: Pricewatch's item info adapter (C_Item; no global GetItemInfo on Forever), its mat prices
-- and the Deals panel's Min profit (default when the panel file is not loaded).
function R.deps()
    local minProfit = P.Config.DEALS_MIN_PROFIT
    local D = P.UI and P.UI.Deals
    if D and type(D.minProfit) == "function" then
        local ok, v = pcall(D.minProfit)
        if ok and type(v) == "number" then minProfit = v end
    end
    return {
        itemInfo = function(id, link) return P.Adapters.itemInfo(id, link) end,
        -- memoised per deps (one refresh or one scan pass): every row asks for the same few mats (lag fix 2026-11-21)
        price = (function()
            local memo = {}
            return function(id)
                local m = memo[id]
                if m == nil then m = { P.Value.price(id) }; memo[id] = m end
                return m[1], m[2]
            end
        end)(),
        -- trend guard (owner 2026-11-21), memoised in the same pass: { falling, now, avg7 } per mat (P.Value.matTrend)
        trend = (function()
            local memo = {}
            return function(id)
                local t = memo[id]
                if t == nil then
                    local ok, r = pcall(P.Value.matTrend, id)
                    t = ok and type(r) == "table" and r or false
                    memo[id] = t
                end
                return t or nil
            end
        end)(),
        -- one DE.unitValue memo per index key, shared with Deals and Live lots (deals rework 2026-11-21)
        memo = P.DealIndex and P.DealIndex.memo() or nil,
        margin = P.Deals.margin(minProfit),
        skill = (function() local ok, s = pcall(P.Adapters.enchantingSkill) return ok and s or nil end)(),
        nameOf = function(id) local ok, ii = pcall(P.Adapters.itemInfo, id) return ok and type(ii) == "table" and ii.name or nil end,
    }
end

-- info = one C_AuctionHouse.GetItemSearchResultInfo table. fallbackID = the buy frame's itemKey.itemID.
-- Returns nil when the row has nothing to show (not armor/weapon green-epic, item not cached, no id), else
-- { id, de (after the cut, nil when a mat has no price), buy (per unit, nil without a plain buyout), qty, profit, good, outcomes }.
function R.evaluate(info, deps, fallbackID)
    if type(info) ~= "table" then return nil end
    local key = type(info.itemKey) == "table" and info.itemKey or nil
    local id = plain(key and key.itemID) or plain(fallbackID)
    if not id then return nil end
    local okI, ii = pcall(deps.itemInfo, id, plainString(info.itemLink))
    if not okI or type(ii) ~= "table" then return nil end
    local q, cls, ilvl = plain(ii.quality), plain(ii.classID), plain(ii.ilvl)
    local keyIlvl = plain(key and key.itemLevel) -- the AH key's item level (the Level column) beats the base one
    if keyIlvl and keyIlvl > 0 then ilvl = keyIlvl end
    if q == nil then return nil, "await" end -- item info not cached yet (GET_ITEM_INFO_RECEIVED will follow)
    if not (q and cls and ilvl) or q < 2 or q > 4 or (cls ~= 2 and cls ~= 4) then return nil end
    local u = P.DE.unitValue(q, cls, ilvl, { price = deps.price, memo = deps.memo })
    if not u then return nil end
    local outcomes, source, de = u.outcomes, u.source, u.de
    local qty = plain(info.quantity)
    if not qty or qty < 1 then qty = 1 end
    local buyout = plain(info.buyoutAmount)
    local buy = (buyout and buyout > 0) and math.floor(buyout / qty + 0.5) or nil
    local e = { id = id, de = de, buy = buy, lot = (buyout and buyout > 0) and buyout or nil, qty = qty, quality = q,
        outcomes = outcomes, source = source, good = false, wouldProfit = false }
    -- trend guard: the mats of this disenchant that are falling (valued at the lower of now and the 7-day; P.Value.price)
    if type(deps.trend) == "function" then
        for _, o in ipairs(outcomes) do
            if o.id and (o.chance or 0) > 0 then
                local okT, t = pcall(deps.trend, o.id)
                if okT and type(t) == "table" and t.falling then
                    e.falling = e.falling or {}
                    e.falling[#e.falling + 1] = { id = o.id, now = t.now, avg7 = t.avg7, valued = t.valued }
                elseif okT and type(t) == "table" and t.noHistory then
                    e.noHistory = true
                end
            end
        end
    end
    -- Enchanting skill gate (unknown skill = no gate, as in the Deals panel)
    local need, have = u.need, plain(deps.skill)
    if need and have and need > have then e.needSkill, e.haveSkill = need, have end
    if de and buy then
        e.profit = de - buy
        e.wouldProfit = P.Reco.beats(de, buy, deps.margin) and true or false
        e.good = e.wouldProfit and not e.needSkill
    end
    return e
end

-- Label text and colour for a row: green "DE 2g 10s +80s" when buy + disenchant beats the Min profit, else grey "DE 2g 10s".
function R.label(e)
    if not e.de then return "DE ?", UNKNOWN end
    local text = "DE " .. P.Money.format(e.de) .. (e.falling and ARROW or "")
    if e.needSkill then return text .. " (skill " .. e.needSkill .. ")", SKILL end
    if e.good then return text .. " +" .. P.Money.format(e.profit), GOOD end
    return text, DIM
end

-- One tooltip line for the hovered row.
function R.tipLine(e)
    if not e.de then return "Disenchant: a material has no price yet", UNKNOWN end
    local each = e.qty > 1 and " each" or ""
    if not e.buy then return "Disenchant ~" .. P.Money.format(e.de) .. each .. " after the cut (no buyout)", DIM end
    if e.good then
        return "Buy + disenchant: profit " .. P.Money.format(e.profit) .. each .. " (DE ~" .. P.Money.format(e.de) .. " after the cut)", GOOD
    end
    return "Disenchant ~" .. P.Money.format(e.de) .. each .. " after the cut: no profit at this price", DIM
end

-- The hover breakdown: { { text, colour }, ... }: the main line, what a disenchant gives (most likely mats, with the rate
-- source: your logged disenchants or the estimate table) and, when your Enchanting is too low, the skill it needs.
function R.tipLines(e, nameOf)
    local text, color = R.tipLine(e)
    if e.needSkill and e.wouldProfit then text, color = "Would profit " .. P.Money.format(e.profit) .. " with the skill", SKILL end
    local lines = { { text, color } }
    if not e.de then return lines end
    local gives = P.Deals.givesText(e.outcomes, nameOf)
    if gives then
        local src = type(e.source) == "table" and e.source or {}
        local tag = (src.source == "own" or src.source == "dh") and ("your " .. (src.n or 0)) or "est."
        lines[#lines + 1] = { gives .. " (" .. tag .. ")", DIM }
    end
    local top = e.outcomes and e.outcomes[1] and e.outcomes[1].id
    local okN, note = pcall(P.Value.matNote, top)
    lines[#lines + 1] = { "Mats priced at " .. (okN and note or "Pricewatch Market") .. ", cross-checked: ZugDAQ, scan, Auctionator,"
        .. " ZugHistory (other addons may differ)", UNKNOWN }
    for _, f in ipairs(e.falling or {}) do
        local okM, name = pcall(nameOf or function() return nil end, f.id)
        name = okM and name or ("Item " .. f.id)
        lines[#lines + 1] = { name .. " falling: " .. P.Money.format(f.now) .. " now, " .. P.Money.format(f.avg7)
            .. " 7-day avg, valued at " .. P.Money.format(f.valued), UNKNOWN }
    end
    if e.noHistory and not e.falling then lines[#lines + 1] = { "Trend: not enough history yet", UNKNOWN } end
    if e.needSkill then
        lines[#lines + 1] = { "Needs Enchanting " .. e.needSkill .. " (you have " .. e.haveSkill .. ")", SKILL }
    end
    return lines
end

-- Browse Auctions rows (one item key at its lowest price): summary = a C_AuctionHouse.GetBrowseResults entry.
-- Returns nil when there is nothing to show (not armor/weapon green-epic, uncached, no key), else the evaluate result plus
-- state: "good" (buy at minPrice + disenchant beats it by the margin), "bad" (disenchanting loses against the price) or
-- "ignore" (mat unpriced, Enchanting too low, no price, or inside the margin).
local BAD = { 1, 0.3, 0.3 }
function R.browse(summary, deps)
    if type(summary) ~= "table" or type(summary.itemKey) ~= "table" then return nil end
    local e, why = R.evaluate({ itemKey = summary.itemKey, buyoutAmount = summary.minPrice, quantity = 1 }, deps)
    if not e then return nil, why end
    if not e.de or not e.buy or e.needSkill then e.state = "ignore"
    elseif e.good then e.state = "good"
    elseif e.de < e.buy then e.state = "bad"
    else e.state = "ignore" end
    return e
end

function R.browseLabel(e)
    if not e.de then return "DE ?", UNKNOWN end
    local text = "DE " .. P.Money.format(e.de) .. (e.falling and ARROW or "")
    if e.state == "good" then return text, GOOD end
    if e.state == "bad" then return text, BAD end
    return text, DIM
end
