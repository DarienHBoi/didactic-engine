local _, S = ...

-- NectarKit module switches. State lives here (default on unless the entry says default = false; nothing needs NectarKit);
-- NectarKit's callback only flips it.
-- Features ask S.Mod.on(key) at the point of use and listen for changes to start or stop their own work.
S.Mod = { state = {}, listeners = {} }
local M = S.Mod

M.LIST = {
    { key = "adverts", label = "Adverts (posting to chat channels)" },
    { key = "maillog", label = "Mail log and Mail tab", default = false }, -- ZugDAQ Auctions wins (owner 2026-11-21)
    { key = "bestcrafts", label = "Best crafts tab" },
    { key = "customers", label = "Customers tab and whisper alerts" },
    { key = "trades", label = "Trade gold tracking (ledger)", default = false }, -- ZugDAQ Ledger wins (owner 2026-11-21)
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
            local ok = pcall(direct, "Salesman", key, m.label, m.default ~= false, function(on) M.set(key, on) end)
            if not ok then return "failed" end
        end
        return "registered"
    end
    NectarKit_Queue = NectarKit_Queue or {}
    for _, m in ipairs(M.LIST) do
        local key = m.key
        table.insert(NectarKit_Queue, { addon = "Salesman", key = key, label = m.label, default = m.default ~= false,
            onToggle = function(on) M.set(key, on) end })
    end
    return "queued"
end
