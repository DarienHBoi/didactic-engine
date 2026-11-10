-- Prediction.lua (1.8.0-dev)
-- Expected disenchant value of a bag item, computed from what YOUR disenchants
-- produced (Learning.lua) and the current material prices (PriceProviders.lua).
--
--   expected value = sum over materials of  chance * average quantity * price
--
-- where chance = (disenchants that dropped the material) / (all disenchants of
-- that kind of item). Nothing here is invented: with no recorded data for an
-- item level the answer is "no data yet", and a material without a price is
-- left out and reported - never counted as 0.
--
-- EraReference is a weak starting prior on Era/Forever only. Observations stay
-- separate in SavedVariables and progressively outweigh the provisional table.

local _, ns = ...
ns.L = ns.L or {}
local L = ns.L

local Pred = {}
ns.Prediction = Pred

Pred.AH_CUT = 0.05        -- auction house cut used for the "sell instead" comparison

local MAX_MATERIAL_LINES = 12
local MAX_PREVIEW_MATERIALS = 3

-- A small prior is four provisional observations, never four real samples.
-- Union the material IDs: an unexpected observed material must appear at once.
local function Blend(obs, prior)
    if not prior then return obs end
    local n, weight, map = obs and obs.n or 0, prior.weight, {}
    local function add(m, amount)
        local entry = map[m.id]
        if not entry then
            entry = {id=m.id,c=0,qtySum=0,minQty=m.minQty,maxQty=m.maxQty}
            map[m.id] = entry
        end
        local occurrences = m.chance * amount
        entry.c = entry.c + occurrences
        entry.qtySum = entry.qtySum + occurrences * m.avgQty
        entry.minQty = math.min(entry.minQty,m.minQty)
        entry.maxQty = math.max(entry.maxQty,m.maxQty)
    end
    for _,m in ipairs(prior.mats) do add(m,weight) end
    for _,m in ipairs(obs and obs.mats or {}) do add(m,n) end
    local mats = {}
    for _,m in pairs(map) do
        mats[#mats+1] = {id=m.id,chance=m.c/(n+weight),avgQty=m.qtySum/m.c,minQty=m.minQty,maxQty=m.maxQty}
    end
    table.sort(mats,function(a,b) if a.chance~=b.chance then return a.chance>b.chance end return a.id<b.id end)
    return {n=n,mats=mats}
end

-- Ask for the reagent tier, not the item's uncommon/rare/epic rarity.
-- Blizzard provides the correct atlas for the current expansion's tier scheme;
-- do not guess bronze/silver/gold from a hardcoded rank number.
function Pred.MaterialQualityIcon(id, size)
    local api=C_TradeSkillUI
    if not api then return "" end
    local function readable(value) return not (issecretvalue and issecretvalue(value)) end
    local function validRank(value)
        return readable(value) and type(value)=="number" and value>0 and value<100 and value==math.floor(value)
    end
    if api.GetItemReagentQualityInfo then
        local ok,info=pcall(api.GetItemReagentQualityInfo,id)
        if ok and readable(info) and type(info)=="table" and validRank(info.quality) then
            for _,field in ipairs({"iconChat","iconSmall","icon"}) do
                local atlas=info[field]
                if readable(atlas) and type(atlas)=="string" and atlas~="" and not atlas:find("[|:%c]") then
                    return " |A:"..atlas..":"..(size or 14)..":"..(size or 14).."|a"
                end
            end
            return " "..string.format(L["MATERIAL_QUALITY_RANK"],info.quality)
        end
    end
    if api.GetItemReagentQualityByItemInfo then
        local ok,rank=pcall(api.GetItemReagentQualityByItemInfo,id)
        if ok and validRank(rank) then return " "..string.format(L["MATERIAL_QUALITY_RANK"],rank) end
    end
    return "" -- Classic/unranked materials stay exactly as before.
end

function Pred.MaterialIcon(id, size)
    local texture
    local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if getIcon then
        local ok, icon = pcall(getIcon,id)
        if ok then texture = icon end
    end
    if not texture then
        local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if instant then
            local ok, _, _, _, _, icon = pcall(instant,id)
            if ok then texture = icon end
        end
    end
    return "|T" .. tostring(texture or 134400) .. ":" .. (size or 14) .. ":" .. (size or 14) .. "|t"
        .. Pred.MaterialQualityIcon(id,size)
end

function Pred.Percent(chance)
    if chance > 0 and chance < 0.001 then return "<0.1%" end
    if chance < 1 and chance > 0.999 then return ">99.9%" end
    return string.format("%.1f",chance*100):gsub("%.0$","") .. "%"
end

-- ---------------------------------------------------------------------------
-- Prices
-- ---------------------------------------------------------------------------
local function MaterialPrice(id)
    local Prices = ns.Prices
    if not (Prices and Prices.GetValue) then return nil end
    local link
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getInfo then
        local ok, _, l = pcall(getInfo, id)
        if ok and type(l) == "string" then link = l end
    end
    if not link then
        -- Not cached yet: ask the client for it so the next hover has a link.
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, id)
        end
        link = "item:" .. tostring(id)
    end
    local ok, copper = pcall(Prices.GetValue, link)
    if ok and type(copper) == "number" then return copper end
    return nil
end

Pred.MaterialPrice = MaterialPrice

-- ---------------------------------------------------------------------------
-- Estimate
-- ---------------------------------------------------------------------------
-- Returns nil when the item cannot be classified; otherwise a table:
--   n        number of recorded disenchants behind the numbers (0 = none)
--   mats     materials, most likely first (chance, avgQty, price or nil)
--   ev       expected value in copper, or nil when no material has a price
--   missing  number of materials without a price
--   sell     the item's own market value after the AH cut (copper) or nil
function Pred.Estimate(item)
    if not (ns.Learn and ns.Learn.Classify and ns.Learn.GetObserved) then return nil end
    local snap = ns.Learn.Classify(item)
    if not snap then return nil end

    local result = { n = 0, mats = {}, missing = 0, ilvl = snap.ilvl }

    -- The item's own market value does not depend on recorded data.
    if ns.Prices and ns.Prices.GetValue and item.link then
        local ok, own = pcall(ns.Prices.GetValue, item.link)
        if ok and type(own) == "number" then
            result.sell = own * (1 - Pred.AH_CUT)
        end
    end

    local prior = ns.EraReference and ns.EraReference.Lookup(snap.quality,snap.kind,snap.ilvl)
    local obs = Blend(ns.Learn.GetObserved(snap.quality, snap.kind, snap.ilvl),prior)
    if prior then
        result.priorWeight = prior.weight
        result.foreverAssumption = prior.client == "forever"
    end
    if not obs then return result end

    result.n = obs.n
    local total, known = 0, false
    for _, m in ipairs(obs.mats) do
        local price = MaterialPrice(m.id)
        result.mats[#result.mats + 1] = {
            id = m.id, chance = m.chance, avgQty = m.avgQty,
            minQty = m.minQty, maxQty = m.maxQty, price = price,
        }
        if price then
            known = true
            total = total + m.chance * m.avgQty * price
        else
            result.missing = result.missing + 1
        end
    end
    if known then result.ev = total end
    return result
end

-- ---------------------------------------------------------------------------
-- Tooltip lines
-- ---------------------------------------------------------------------------
local function Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper)
    end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return tostring(copper) .. " c"
end

Pred.Money = Money

local function QtyText(m)
    if m.minQty and m.maxQty and m.minQty ~= m.maxQty then
        return m.minQty .. "-" .. m.maxQty
    end
    return tostring(m.maxQty or m.minQty or 1)
end

-- Embedded game textures keep the preview small and avoid bundled media files.
function Pred.BuildPreview(est)
    if not est or #est.mats == 0 then return L["EV_PREVIEW_EMPTY"] end
    local parts = {}
    for i=1,math.min(MAX_PREVIEW_MATERIALS,#est.mats) do
        local m=est.mats[i]
        parts[#parts+1] = Pred.MaterialIcon(m.id) .. " " .. Pred.Percent(m.chance) .. " x" .. QtyText(m)
    end
    if #est.mats>MAX_PREVIEW_MATERIALS then parts[#parts+1]="+"..(#est.mats-MAX_PREVIEW_MATERIALS) end
    local basis = est.priorWeight and "≈ " or "~ "
    return basis .. table.concat(parts,"   ")
end

-- Plain data -> list of { text, right, r, g, b } lines (no UI calls: testable).
-- `right` (optional) makes it a two-column line, so numbers line up on the
-- right edge instead of running into the label.
local HEADER_COLOR = { 0.49, 0.83, 0.99 }   -- same blue as the addon's chat prefix

function Pred.BuildLines(est)
    local lines = {}
    local function add(text, right, color)
        color = color or { 1, 1, 1 }
        lines[#lines + 1] = { text = text, right = right, r = color[1], g = color[2], b = color[3] }
    end

    if not est then return lines end
    add(L["EV_HEADER"], nil, HEADER_COLOR)

    if est.n == 0 and #est.mats == 0 then
        add(string.format(L["EV_NO_DATA"], est.ilvl or 0), nil, { 0.6, 0.6, 0.6 })
        return lines
    end

    local cutPct = math.floor(Pred.AH_CUT * 100 + 0.5)
    local netMaterials = est.ev and est.ev * (1 - Pred.AH_CUT)
    if est.ev then
        add(string.format(L["EV_ROW_DE"], cutPct), Money(netMaterials), { 1, 0.6, 0.2 })
    else
        add(L["EV_NO_PRICE"], nil, { 1, 0.5, 0.1 })
    end

    for i = 1, math.min(MAX_MATERIAL_LINES, #est.mats) do
        local m = est.mats[i]
        local name = (ns.Learn and ns.Learn.MaterialName and ns.Learn.MaterialName(m.id)) or ("#" .. m.id)
        add(Pred.MaterialIcon(m.id) .. " " .. name, string.format(L["EV_MAT_RIGHT"], Pred.Percent(m.chance), QtyText(m)),
            { 0.7, 0.7, 0.7 })
    end
    if #est.mats>MAX_MATERIAL_LINES then
        add(string.format(L["EV_MORE_MATERIALS"],#est.mats-MAX_MATERIAL_LINES),nil,{0.7,0.7,0.7})
    end

    if est.sell then
        add(string.format(L["EV_ROW_SELL"], cutPct), Money(est.sell))
    end
    if est.missing == 0 and est.sell and netMaterials then
        local diff = netMaterials - est.sell
        if diff >= 0 then
            add(string.format(L["EV_BETTER_DE"], Money(diff)), nil, { 0.3, 1, 0.3 })
        else
            add(string.format(L["EV_BETTER_SELL"], Money(-diff)), nil, { 1, 0.4, 0.4 })
        end
    end
    return lines
end

-- Appends the estimate to a tooltip. Never throws (called inside OnEnter).
function Pred.AppendToTooltip(tooltip, item)
    local ok = pcall(function()
        local est = Pred.Estimate(item)
        local lines = Pred.BuildLines(est)
        if #lines == 0 then return end
        tooltip:AddLine(" ")
        for _, line in ipairs(lines) do
            if line.right then
                tooltip:AddDoubleLine(line.text, line.right, line.r, line.g, line.b, 1, 1, 1)
            else
                tooltip:AddLine(line.text, line.r, line.g, line.b, true)
            end
        end
    end)
    return ok
end
