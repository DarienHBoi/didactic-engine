local _, P = ...

-- NectarKit module switches. State lives here (default on unless the entry says default = false; nothing needs NectarKit);
-- NectarKit's callback only flips it.
-- Features ask P.Mod.on(key) at the point of use and listen for changes to start or stop their own work.
P.Mod = { state = {}, listeners = {} }
local M = P.Mod

M.LIST = {
    { key = "tooltip", label = "Item tooltip lines" },
    { key = "deals", label = "Deals panel and AH button" },
    { key = "today", label = "Today tab" },
    { key = "market", label = "Sold tracker and Rescan watched" },
    { key = "disenchant", label = "Disenchant estimate in views" },
    { key = "zugdaq", label = "Use ZugDAQ data" },
    { key = "delog", label = "Log your disenchants (rates)" },
    { key = "gather", label = "Loot log and Gather tab (gold/hour, cook or raw)", default = false }, -- ZugDAQ Farming wins (owner 2026-11-21)
    { key = "best", label = "Best move line (Today and minimap tooltip)" },
    { key = "ahrows", label = "Disenchant value on AH buy-list rows" },
}

local function default(key)
    for _, m in ipairs(M.LIST) do if m.key == key then return m.default ~= false end end
    return true
end

function M.on(key)
    local v = M.state[key]
    if v == nil then return default(key) end
    return v ~= false
end

function M.listen(key, fn)
    M.listeners[key] = M.listeners[key] or {}
    table.insert(M.listeners[key], fn)
end

function M.set(key, on)
    on = on and true or false
    M.state[key] = on
    for _, fn in ipairs(M.listeners[key] or {}) do pcall(fn, on) end
end

-- At PLAYER_LOGIN. Returns "registered", "queued" or "failed". Without NectarKit every module simply stays on.
function M.register()
    local direct = NectarKit_RegisterModule
    if type(direct) == "function" then
        for _, m in ipairs(M.LIST) do
            local key = m.key
            local ok = pcall(direct, "Pricewatch", key, m.label, m.default ~= false, function(on) M.set(key, on) end)
            if not ok then return "failed" end
        end
        return "registered"
    end
    NectarKit_Queue = NectarKit_Queue or {}
    for _, m in ipairs(M.LIST) do
        local key = m.key
        table.insert(NectarKit_Queue, { addon = "Pricewatch", key = key, label = m.label, default = m.default ~= false,
            onToggle = function(on) M.set(key, on) end })
    end
    return "queued"
end
