local _, P = ...

-- Cook or sell raw. For each Cooking recipe Salesman knows (SalesmanAPI.recipes, with reagents): the cooked item's price after the
-- AH cut x its chance of selling, against the raw reagents' price after the cut x their chance of selling, minus the vendor spices.
-- One craft makes one item (INFERRED: the saved recipes carry no yield). Vendor prices are recorded whenever a merchant window
-- shows them: PricewatchDB.vendor = { [itemID] = { c = copper per unit, t = unix time } }, at most MAX_VENDOR items.
P.Cook = {}
local C = P.Cook
C.MAX_VENDOR = 500

local function posInt(v) return type(v) == "number" and v >= 1 and v == math.floor(v) and v < 2 ^ 53 end

-- recipe = { itemID, name, reagents = { {id, qty} } }; deps = { price(id), p(id) -> 0..1, vendorCost(id) -> copper or nil }.
-- Returns { itemID, name, cooked, raw, spice, gain, action = "cook" | "raw" | "close", parts = { {id, qty, vendor = bool} } },
-- or nil plus the id that has no price.
function C.evaluate(recipe, deps)
    if type(recipe) ~= "table" or not posInt(recipe.itemID) or type(recipe.reagents) ~= "table" or #recipe.reagents == 0 then return nil end
    local function value(id)
        local okP, price = pcall(deps.price, id)
        if not okP or type(price) ~= "number" or price <= 0 then return nil end
        local okS, p = pcall(deps.p, id)
        p = (okS and type(p) == "number") and math.max(0, math.min(1, p)) or P.Config.SELL_DEFAULT
        return P.Reco.net(price) * p
    end
    local cooked = value(recipe.itemID)
    if not cooked then return nil, recipe.itemID end
    local raw, spice, parts = 0, 0, {}
    for _, g in ipairs(recipe.reagents) do
        if type(g) ~= "table" or not posInt(g.id) or not posInt(g.qty) then return nil end
        local okV, vc = pcall(deps.vendorCost, g.id)
        if okV and type(vc) == "number" and vc > 0 then
            spice = spice + vc * g.qty
            parts[#parts + 1] = { id = g.id, qty = g.qty, vendor = true }
        else
            local v = value(g.id)
            if not v then return nil, g.id end
            raw = raw + v * g.qty
            parts[#parts + 1] = { id = g.id, qty = g.qty }
        end
    end
    cooked, raw, spice = math.floor(cooked + 0.5), math.floor(raw + 0.5), math.floor(spice + 0.5)
    local back = cooked - spice
    local action, gain
    if P.Reco.beats(back, raw) then action, gain = "cook", back - raw
    elseif P.Reco.beats(raw, back) then action, gain = "raw", raw - back
    else action, gain = "close", math.abs(back - raw) end
    return { itemID = recipe.itemID, name = recipe.name, cooked = cooked, raw = raw, spice = spice, gain = gain, action = action, parts = parts }
end

local ORDER = { cook = 1, raw = 2, close = 3 }

-- Rows for the Cooking recipes in `recipes`: cook first, then sell raw, then close calls; best gain first inside each.
-- Returns rows and the number of Cooking recipes skipped for a missing price.
function C.rows(recipes, deps)
    local out, skipped = {}, 0
    for _, r in ipairs(type(recipes) == "table" and recipes or {}) do
        if type(r) == "table" and r.profession == "Cooking" then
            local row = C.evaluate(r, deps)
            if row then out[#out + 1] = row else skipped = skipped + 1 end
        end
    end
    table.sort(out, function(a, b)
        if ORDER[a.action] ~= ORDER[b.action] then return ORDER[a.action] < ORDER[b.action] end
        if a.gain ~= b.gain then return a.gain > b.gain end
        return tostring(a.name) < tostring(b.name)
    end)
    return out, skipped
end

local ACTION = { cook = "Cook", raw = "Sell raw", close = "Close call" }
function C.actionText(row) return ACTION[row.action] or "?" end

-- "raw 1x Zesty Clam Meat 1s 90c, spice 10c, cooked 9s 50c (after cut x chance to sell)". nameOf(id) -> name or nil.
function C.reason(row, nameOf)
    local names = {}
    for _, g in ipairs(row.parts or {}) do
        if not g.vendor then
            local okN, nm = pcall(nameOf or function() end, g.id)
            names[#names + 1] = g.qty .. "x " .. ((okN and type(nm) == "string") and nm or ("Item " .. g.id))
        end
    end
    local s = "raw " .. (#names > 0 and table.concat(names, ", ") or "-") .. " " .. P.Money.format(row.raw)
    if row.spice > 0 then s = s .. ", spice " .. P.Money.format(row.spice) end
    return s .. ", cooked " .. P.Money.format(row.cooked)
end

-- Merchant window rows { link, price, quantity, extended } -> PricewatchDB.vendor. Returns how many were recorded.
function C.recordMerchant(db, list, now)
    if type(db) ~= "table" or type(list) ~= "table" then return 0 end
    db.vendor = type(db.vendor) == "table" and db.vendor or {}
    local n = 0
    for _, e in ipairs(list) do
        local id = type(e) == "table" and type(e.link) == "string" and tonumber(e.link:match("item:(%d+)"))
        local qty = type(e) == "table" and posInt(e.quantity) and e.quantity or 1
        if id and not e.extended and type(e.price) == "number" and e.price > 0 then
            if not db.vendor[id] then
                local count, oldId, oldT = 0, nil, nil
                for k, v in pairs(db.vendor) do
                    count = count + 1
                    if not oldT or (v.t or 0) < oldT then oldId, oldT = k, v.t or 0 end
                end
                if count >= C.MAX_VENDOR and oldId then db.vendor[oldId] = nil end
            end
            db.vendor[id] = { c = math.floor(e.price / qty + 0.5), t = now }
            n = n + 1
        end
    end
    return n
end

function C.vendorCost(db, id)
    local v = type(db) == "table" and type(db.vendor) == "table" and db.vendor[id]
    return type(v) == "table" and v.c or nil
end

-- The open merchant window, guarded: { {link, price, quantity, extended} }.
function C.readMerchant()
    local out = {}
    if type(GetMerchantNumItems) ~= "function" or type(GetMerchantItemInfo) ~= "function" then return out end
    pcall(function()
        for i = 1, GetMerchantNumItems() or 0 do
            local _, _, price, quantity, _, _, extended = GetMerchantItemInfo(i)
            local link = type(GetMerchantItemLink) == "function" and GetMerchantItemLink(i) or nil
            out[#out + 1] = { link = link, price = price, quantity = quantity, extended = extended and true or false }
        end
    end)
    return out
end

-- Live deps: the tooltip's price and p(sell) sources, vendor costs from PricewatchDB.
function C.deps()
    local td = P.Tip.deps()
    return {
        price = function(id) return (P.Value.price(id)) end,
        p = function(id) return (P.Reco.pSell(id, td)) end,
        vendorCost = function(id) return C.vendorCost(P.db, id) end,
    }
end
