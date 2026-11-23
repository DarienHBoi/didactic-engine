local _, ns = ...

-- Remembers the name, icon (texture file ID) and quality of every item the other tools need to show:
-- what's in bags, banks and the warbank, every recipe's reagents and results, vendor stock and your
-- auctions. ZugDAQ uses it for items the auction house API has no name or icon for.
-- Stored as ZugDAQDB.items[itemID] = { n = name, i = icon, q = quality }.

local function instantIcon(itemID)
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not info then return end
    local ok, _, _, _, _, icon = pcall(info, itemID)
    if ok then return icon end
end

local function wanted()
    local ids, db = {}, ns.db
    local function add(id) id = tonumber(id); if id and id > 0 then ids[id] = true end end
    local function addRecipes(list)
        for _, r in pairs(list or {}) do
            if type(r) == "table" then
                add(r.output)
                for _, slot in ipairs(r.slots or {}) do
                    for _, item in ipairs(slot.items or {}) do add(item) end
                end
            end
        end
    end
    for _, c in pairs(db.chars or {}) do
        for id in pairs(c.bags or {}) do add(id) end
        for id in pairs(c.bank or {}) do add(id) end
        addRecipes(c.recipes)
        addRecipes(c.unlearned)
    end
    for id in pairs((db.warbank and db.warbank.items) or {}) do add(id) end
    for _, m in pairs(db.merchants or {}) do
        for id in pairs(m.items or {}) do add(id) end
    end
    return ids
end

-- fills in what the client knows; asks the server for the rest so the next pass has them
local function record()
    if not ns.db then return end
    local store = ns.db.items or {}
    ns.db.items = store
    for id in pairs(wanted()) do
        local have = store[id]
        if not (have and have.n and have.i and have.q) then
            local name, _, quality = ns.GetItemInfo(id)
            local icon = instantIcon(id)
            if name then
                store[id] = { n = name, i = icon or (have and have.i), q = quality }
            else
                if icon and not have then store[id] = { i = icon } end
                ns.RequestItem(id)
            end
        end
    end
end

ns.OnLogin(function() C_Timer.After(8, record) end)
ns.On("TRADE_SKILL_CLOSE", function() ns.Debounce("iteminfo", 3, record) end)
ns.On("MERCHANT_CLOSED", function() ns.Debounce("iteminfo", 3, record) end)
ns.On("BANKFRAME_CLOSED", function() ns.Debounce("iteminfo", 3, record) end)
ns.On("PLAYER_LOGOUT", record)
