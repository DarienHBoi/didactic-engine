local _, P = ...

-- Best move now: one line with the highest expected gain across the money finder's sources. Every gain is already net of the AH
-- cut and weighted by the chance of selling: Today rows (craft, Buy + DE, bag sale; Hold is not a move), flips (score = profit x
-- p(sell)), cooking from the raw mats in your bags (gain per craft x crafts), and the best farming spot (gold per hour = one hour).
-- Shown at the top of the Today tab and in NectarKit's minimap button tooltip.
P.Best = {}
local B = P.Best
B.CACHE_SECS = 60
local ORDER = { craft = 1, deal = 2, flip = 3, cook = 4, bag = 5, farm = 6 }

-- Whole crafts you can make from the raw (non-vendor) mats in your bags, at most P.Config.BAG_UNITS.
function B.cookCount(row, bagCount)
    local n
    for _, g in ipairs(type(row) == "table" and type(row.parts) == "table" and row.parts or {}) do
        if type(g) == "table" and not g.vendor and type(g.qty) == "number" and g.qty > 0 then
            local ok, have = pcall(bagCount, g.id)
            have = (ok and type(have) == "number") and have or 0
            local k = math.floor(have / g.qty)
            if not n or k < n then n = k end
        end
    end
    return math.min(n or 0, P.Config.BAG_UNITS)
end

local function num(v) return type(v) == "number" and v == v and v > 0 and v < math.huge end

-- src = { today = rows, flips = rows, cook = rows, bagCount(id), spots = rows }. Returns { kind, id, zone, name, gain, ... }.
function B.candidates(src)
    local out = {}
    src = type(src) == "table" and src or {}
    local function list(t) return type(t) == "table" and t or {} end
    for _, r in ipairs(list(src.today)) do
        if type(r) == "table" and ORDER[r.kind] and r.kind ~= "farm" and num(r.gain) then
            out[#out + 1] = { kind = r.kind, id = r.id, name = r.name, gain = r.gain }
        end
    end
    for _, r in ipairs(list(src.flips)) do
        if type(r) == "table" and num(r.score) then
            out[#out + 1] = { kind = "flip", id = r.id, name = r.name, gain = r.score, buy = r.buy }
        end
    end
    for _, r in ipairs(list(src.cook)) do
        if type(r) == "table" and r.action == "cook" and num(r.gain) then
            local n = type(src.bagCount) == "function" and B.cookCount(r, src.bagCount) or 0
            if n > 0 then out[#out + 1] = { kind = "cook", id = r.itemID, name = r.name, gain = r.gain * n, count = n } end
        end
    end
    for _, s in ipairs(list(src.spots)) do
        if type(s) == "table" and num(s.perHour) and type(s.zone) == "string" then
            out[#out + 1] = { kind = "farm", zone = s.zone, source = s.source, name = s.zone, gain = s.perHour }
        end
    end
    return out
end

function B.pick(src)
    local best
    for _, c in ipairs(B.candidates(src)) do
        if not best or c.gain > best.gain or (c.gain == best.gain and (ORDER[c.kind] < ORDER[best.kind]
            or (ORDER[c.kind] == ORDER[best.kind] and tostring(c.name) < tostring(best.name)))) then
            best = c
        end
    end
    return best
end

function B.line(c)
    if type(c) ~= "table" then return "Best move: nothing yet (scan the AH with Auctionator)" end
    local m = P.Money.format(c.gain)
    local name = c.name or ("Item " .. tostring(c.id))
    if c.kind == "craft" then return "Best move: Craft " .. name .. "  +" .. m end
    if c.kind == "deal" then return "Best move: Buy " .. name .. " and disenchant  +" .. m end
    if c.kind == "bag" then return "Best move: Sell " .. name .. " on the AH  +" .. m end
    if c.kind == "flip" then return "Best move: Flip " .. name .. " (buy at " .. P.Money.format(c.buy or 0) .. ")  +" .. m end
    if c.kind == "cook" then return "Best move: Cook " .. (c.count or 1) .. "x " .. name .. "  +" .. m end
    if c.kind == "farm" then return "Best move: " .. P.Loot.sourceLabel(c.source) .. " in " .. name .. "  +" .. m .. "/h" end
    return "Best move: " .. name .. "  +" .. m
end

-- Cached pick: live() builds the sources at most once per CACHE_SECS (the minimap tooltip may be hovered often).
local cache
function B.reset() cache = nil end
function B.get(now, live)
    if cache and type(now) == "number" and now - cache.t < B.CACHE_SECS then return cache.best end
    local ok, src = pcall(live)
    local best = ok and B.pick(src) or nil
    cache = { t = type(now) == "number" and now or 0, best = best }
    return best
end

-- The live sources, each guarded and each behind its NectarKit module.
function B.live()
    local src = {}
    if P.Mod.on("today") then
        local ok, res = pcall(function() return P.Today.build(P.Today.live()) end)
        src.today = ok and res and res.rows or nil
    end
    if P.Mod.on("deals") then src.flips = P.Deals.lastFlips end
    if P.Mod.on("gather") then
        local okC, rows = pcall(P.Cook.rows, P.Adapters.salesmanRecipes(), P.Cook.deps())
        src.cook = okC and rows or nil
        local counts = {}
        for _, e in ipairs(P.Adapters.bagItems()) do counts[e.id] = (counts[e.id] or 0) + (e.count or 0) end
        src.bagCount = function(id) return counts[id] or 0 end
        local okS, spots = pcall(P.Loot.spots, P.db, {
            price = function(id) return (P.Value.price(id)) end,
            vendor = function(id) return P.Adapters.itemInfo(id).vendor end,
        })
        src.spots = okS and spots or nil
    end
    return src
end

function B.now()
    return B.get(type(GetTime) == "function" and GetTime() or 0, B.live)
end

-- NectarKit's minimap button: one line under its own. Hooked once (HookScript keeps NectarKit's handler).
function B.hookMinimap()
    if B.hooked then return true end
    local btn = _G.NectarKitMinimapButton
    if type(btn) ~= "table" or type(btn.HookScript) ~= "function" then return false end
    B.hooked = true
    pcall(btn.HookScript, btn, "OnEnter", function()
        if not P.Mod.on("best") or not GameTooltip then return end
        pcall(function()
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(B.line(B.now()), 0.25, 1, 0.25)
            GameTooltip:Show()
        end)
    end)
    return true
end
