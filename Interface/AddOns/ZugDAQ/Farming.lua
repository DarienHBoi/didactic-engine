local _, ns = ...

-- Farming sessions: everything looted (items and coin) while a session runs, timed, and saved under a
-- route name so runs of the same route can be compared. Item values are worked out with today's
-- prices, so old runs stay comparable as the market moves.

local MAX_SESSIONS = 500

local function zoneName()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local info = mapID and C_Map.GetMapInfo(mapID)
    return (info and info.name) or (GetRealZoneText and GetRealZoneText()) or "Unknown"
end

function ns.ActiveSession() return ns.db and ns.db.active end

function ns.SessionElapsed(s)
    if not s then return 0 end
    local t = s.elapsed or 0
    if s.runningSince then t = t + (time() - s.runningSince) end
    return t
end

-- value of a session's loot: items (at today's prices) plus coin
function ns.SessionValue(s)
    local items = 0
    for itemID, count in pairs(s.items or {}) do
        items = items + ns.Value(itemID) * count
    end
    return items + (s.coin or 0), items
end

function ns.PerHour(value, seconds)
    if not seconds or seconds < 60 then return nil end
    return value / seconds * 3600
end

function ns.StartSession(route)
    if ns.db.active then
        ns.Print("a session is already running (%s). Stop it first.", ns.db.active.route)
        return
    end
    local zone = zoneName()
    ns.db.active = {
        route = route or zone,
        char = ns.charKey,
        started = time(),
        elapsed = 0,
        runningSince = time(),
        coin = 0,
        items = {},
        zones = { [zone] = true },
        loots = 0,
    }
    ns.Print("farming session started: |cffffffff%s|r. /zug farm stop when you're done.", ns.db.active.route)
    ns.Fire("SESSION")
    ns.RequestRefresh()
end

function ns.PauseSession(quiet)
    local s = ns.db.active
    if not s or not s.runningSince then return end
    s.elapsed = (s.elapsed or 0) + (time() - s.runningSince)
    s.runningSince = nil
    s.pausedAt = time()
    if not quiet then ns.Print("session paused.") end
    ns.Fire("SESSION")
    ns.RequestRefresh()
end

function ns.ResumeSession(quiet)
    local s = ns.db.active
    if not s or s.runningSince then return end
    s.runningSince = time()
    s.pausedAt, s.autoPaused = nil, nil
    if not quiet then ns.Print("session resumed.") end
    ns.Fire("SESSION")
    ns.RequestRefresh()
end

function ns.StopSession()
    local s = ns.db.active
    if not s then
        ns.Print("no farming session is running.")
        return
    end
    ns.PauseSession(true)
    ns.db.active = nil
    local zones = {}
    for z in pairs(s.zones or {}) do zones[#zones + 1] = z end
    table.sort(zones)
    local value = ns.SessionValue(s)
    local record = {
        route = s.route, char = s.char, started = s.started, duration = s.elapsed,
        coin = s.coin, items = s.items, zones = zones, loots = s.loots,
        valueAtEnd = value,
    }
    if record.duration >= 60 or value > 0 then
        table.insert(ns.db.sessions, 1, record)
        while #ns.db.sessions > MAX_SESSIONS do table.remove(ns.db.sessions) end
        local gph = ns.PerHour(value, record.duration)
        ns.Print("session saved: %s in %s = %s%s", record.route, ns.Duration(record.duration), ns.Money(value),
            gph and (" (" .. ns.Money(gph) .. " per hour)") or "")
    else
        ns.Print("session was too short to keep.")
    end
    ns.Fire("SESSION")
    ns.RequestRefresh()
end

function ns.CancelSession()
    if not ns.db.active then return end
    ns.db.active = nil
    ns.Print("session discarded.")
    ns.Fire("SESSION")
    ns.RequestRefresh()
end

function ns.DeleteSession(index)
    table.remove(ns.db.sessions, index)
    ns.RequestRefresh()
end

function ns.RenameRoute(old, new)
    if not new or new == "" then return end
    for _, s in ipairs(ns.db.sessions) do
        if s.route == old then s.route = new end
    end
    if ns.db.active and ns.db.active.route == old then ns.db.active.route = new end
    ns.RequestRefresh()
end

-- ---------------------------------------------------------------- loot

-- "You receive loot: %sx%d." -> "^You receive loot: (.+)x(%d+)%.$"
local function lootPattern(fmt)
    if type(fmt) ~= "string" then return end
    local p = fmt:gsub("%%%d?%$?([sd])", function(kind) return kind == "s" and "\001" or "\002" end)
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("\001", "(.+)")
    p = p:gsub("\002", "(%%d+)")
    return "^" .. p .. "$"
end

local LOOT
local function lootPatterns()
    if not LOOT then
        LOOT = {}
        for _, fmt in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF }) do
            local p = lootPattern(fmt)
            if p then LOOT[#LOOT + 1] = p end
        end
        if #LOOT == 0 then
            LOOT = { "^You receive loot: (.+)x(%d+)%.$", "^You receive loot: (.+)%.$" }
        end
    end
    return LOOT
end

local function parseLoot(text)
    for _, p in ipairs(lootPatterns()) do
        local link, count = text:match(p)
        if link then return link, tonumber(count) or 1 end
    end
end

-- "You receive loot" lines are only ever your own loot; other people's read "X receives loot"
ns.On("CHAT_MSG_LOOT", function(text)
    if not ns.db then return end
    local ok, link, count = pcall(parseLoot, text)
    if not ok or not link then return end
    local itemID = ns.ItemIDFromLink(link)
    if not itemID then return end
    ns.Fire("LOOT", itemID, count) -- the always-on activity tracker counts every loot by zone
    local s = ns.db.active
    if not s or not s.runningSince then return end
    s.items[itemID] = (s.items[itemID] or 0) + count
    s.loots = (s.loots or 0) + 1
    ns.RequestRefresh()
end)

ns.Listen("MONEY", function(cat, amount)
    local s = ns.db.active
    if s and s.runningSince and cat == "Looted coin" and amount > 0 then
        s.coin = (s.coin or 0) + amount
    end
end)

ns.On("ZONE_CHANGED_NEW_AREA", function()
    local s = ns.db and ns.db.active
    if s then s.zones[zoneName()] = true end
end)

-- logging out pauses the session; a quick /reload picks it straight back up
ns.On("PLAYER_LOGOUT", function()
    local s = ns.db and ns.db.active
    if s and s.runningSince then
        ns.PauseSession(true)
        s.autoPaused = true
    end
end)

ns.OnLogin(function()
    local s = ns.db.active
    if not s then return end
    if s.autoPaused and s.pausedAt and time() - s.pausedAt < 180 and s.char == ns.charKey then
        ns.ResumeSession(true)
    elseif s.autoPaused then
        ns.Print("your farming session \"%s\" is paused. /zug farm resume to carry on, or stop to save it.", s.route)
    end
end)

-- ---------------------------------------------------------------- routes

-- per-route summary of finished sessions, with values at today's prices
function ns.RouteStats()
    local routes, list = {}, {}
    for _, s in ipairs(ns.db.sessions) do
        local r = routes[s.route]
        if not r then
            r = { route = s.route, runs = 0, time = 0, value = 0, best = nil, last = 0, items = {}, coin = 0 }
            routes[s.route] = r
            list[#list + 1] = r
        end
        local value = ns.SessionValue(s)
        r.runs = r.runs + 1
        r.time = r.time + (s.duration or 0)
        r.value = r.value + value
        r.coin = r.coin + (s.coin or 0)
        r.last = math.max(r.last, s.started or 0)
        local gph = ns.PerHour(value, s.duration)
        if gph and (not r.best or gph > r.best) then r.best = gph end
        for itemID, count in pairs(s.items or {}) do
            r.items[itemID] = (r.items[itemID] or 0) + count
        end
    end
    for _, r in ipairs(list) do r.gph = ns.PerHour(r.value, r.time) end
    return list
end

-- items sorted by total value, for tooltips: { {itemID, count, value}, ... }
function ns.TopItems(items, limit)
    local out = {}
    for itemID, count in pairs(items or {}) do
        out[#out + 1] = { itemID = itemID, count = count, value = ns.Value(itemID) * count }
    end
    table.sort(out, function(a, b) return a.value > b.value end)
    if limit then
        for i = #out, limit + 1, -1 do out[i] = nil end
    end
    return out
end
