local _, P = ...
P.Rescan = {}
local R = P.Rescan

-- "Rescan watched": one search per watched item, one at a time, only when the client's throttle allows, with a
-- timeout per item and a cancel. The results arrive through the client's search events (Main.lua), which feed
-- P.Market and call job:onResult. Pure: the client is injected:
-- client = { key(id) -> itemKey, keyReady(key) -> bool, ready() -> bool, send(key) -> bool,
--   requestMore(id, key, kind) -> bool }. Every call to the server (send, requestMore) waits for ready() first.

-- Watched ids, never-scanned first, then the oldest scan; at most max.
function R.order(ids, db, max)
    local market = type(db) == "table" and type(db.market) == "table" and db.market or {}
    local list = {}
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        if type(id) == "number" then
            local e = market[id]
            list[#list + 1] = { id = id, t = type(e) == "table" and type(e.last) == "table" and tonumber(e.last.t) or 0 }
        end
    end
    table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
    local out = {}
    for i = 1, math.min(#list, max or P.Config.RESCAN_MAX) do out[i] = list[i].id end
    return out
end

local function try(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    local ok, r = pcall(fn, ...)
    return ok, r
end

local Job = {}
Job.__index = Job

function R.new(ids, client)
    return setmetatable({ ids = ids or {}, client = client or {}, index = 1, phase = "key", wait = 0, pages = 0,
        answered = 0, gaveUp = 0, cancelled = false }, Job)
end

function Job:done() return self.cancelled or self.index > #self.ids end
function Job:current() return not self:done() and self.ids[self.index] or nil end

function Job:next(answered)
    if answered then self.answered = self.answered + 1 else self.gaveUp = self.gaveUp + 1 end
    self.index = self.index + 1
    self.phase, self.wait, self.pages, self.key, self.kind = "key", 0, 0, nil, nil
end

-- One frame. Waits on the item key and the throttle; a sent search that gets no answer within RESCAN_TIMEOUT is given up.
function Job:tick(dt)
    if self:done() then return end
    dt = tonumber(dt) or 0
    local c, id = self.client, self:current()
    if self.phase == "key" then
        self.wait = self.wait + dt
        if not self.key then
            local ok, k = try(c.key, id)
            self.key = ok and k or nil
        end
        local ok, readyKey = try(c.keyReady, self.key)
        if self.key and ok and readyKey then
            self.phase, self.wait = "throttle", 0
        elseif self.wait > P.Config.RESCAN_TIMEOUT then
            self:next(false)
            return
        else
            return
        end
    end
    if self.phase == "throttle" then
        local ok, ready = try(c.ready)
        if not (ok and ready) then return end -- the throttle can be slow; never times out
        local okS, sent = try(c.send, self.key)
        self.phase, self.wait = "sent", 0
        if not okS or sent == false then self.wait = P.Config.RESCAN_TIMEOUT end -- a failed send times out at once
        return
    end
    if self.phase == "more" then
        -- another page, through the same throttle gate as a search (never from inside the result event)
        local ok, ready = try(c.ready)
        if not (ok and ready) then return end
        local okM, sent = try(c.requestMore, id, self.key, self.kind)
        self.phase, self.wait = "sent", 0
        if not okM or sent == false then self.wait = P.Config.RESCAN_TIMEOUT end
        return
    end
    if self.phase == "sent" then
        self.wait = self.wait + dt
        if self.wait > P.Config.RESCAN_TIMEOUT then self:next(false) end
    end
end

-- A search result for item id arrived (full = the client has all of it; kind = "item" or "commodity"; recorded =
-- the tracker used it). A partial one asks for another page on the next ready tick, at most RESCAN_PAGES; after the
-- last page the item counts as answered only when the tracker could use what came.
function Job:onResult(id, full, kind, recorded)
    if self:done() or id ~= self:current() or self.phase ~= "sent" then return end
    if kind then self.kind = kind end
    if full then
        self:next(true)
    elseif self.pages < P.Config.RESCAN_PAGES then
        self.pages = self.pages + 1
        self.phase, self.wait = "more", 0
    else
        self:next(recorded == true)
    end
end

function Job:cancel() self.cancelled = true end

function Job:status()
    local n = #self.ids
    if self.cancelled then return ("Rescan cancelled (%d of %d answered)"):format(self.answered, n) end
    if self:done() then
        return ("Rescan done: %d of %d answered%s"):format(self.answered, n,
            self.gaveUp > 0 and (", " .. self.gaveUp .. " gave no answer") or "")
    end
    return ("Rescanning %d/%d..."):format(self.index, n)
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Live side: the client's search events feed the tracker (also passively, from searches made in Auctionator or the
-- Blizzard UI), and the current Rescan job. Watched items only.
R.job = nil
R.lastRaw = {} -- id -> plain copy of the first result row of the last search (for /pricewatch market why)
R.seen = 0     -- results recorded this session

local watchCache, watchAt
function R.watchSet()
    local now = type(time) == "function" and time() or 0
    if watchCache and watchAt and now - watchAt < 300 then return watchCache end
    local set = {}
    local ok, list = pcall(function() return P.Watch.build(P.Watch.live()) end)
    for _, id in ipairs(ok and type(list) == "table" and list or {}) do set[id] = true end
    watchCache, watchAt = set, now
    return set
end
function R.resetWatch() watchCache = nil end

function R.watchedList()
    local out = {}
    for id in pairs(R.watchSet()) do out[#out + 1] = id end
    table.sort(out)
    return out
end

local function plainCopy(row)
    local out = {}
    for k, v in pairs(type(row) == "table" and row or {}) do
        if issecretvalue and issecretvalue(v) then out[k] = "<secret>"
        elseif type(v) == "table" then
            local parts = {}
            for i, x in ipairs(v) do
                if i > 3 then break end
                parts[#parts + 1] = (issecretvalue and issecretvalue(x)) and "<secret>" or tostring(x)
            end
            out[k] = "{" .. table.concat(parts, ",") .. (#v > 3 and ",..." or "") .. "}"
        else out[k] = v end
    end
    return out
end

local function record(id, list, full, sig, kind)
    if not P.Mod.on("market") or not P.db or not R.watchSet()[id] then return end
    if list[1] then R.lastRaw[id] = plainCopy(list[1]); R.lastRaw[id]._kind = kind end
    local t = time()
    local d = P.Market.record(P.db, id, list, t, P.Days.dayOf(t, P.Days.epoch0()), full == true, sig)
    if d then R.seen = R.seen + 1 end
    if R.job then R.job:onResult(id, full, kind, d ~= nil) end
end

-- ITEM_SEARCH_RESULTS_UPDATED (itemKey)
function R.onItemResults(itemKey)
    if not P.Mod.on("market") then return end
    local id = type(itemKey) == "table" and itemKey.itemID
    if issecretvalue and issecretvalue(id) then return end
    if type(id) ~= "number" then return end
    if not R.watchSet()[id] then return end
    local list, full = P.Adapters.itemResults(itemKey)
    record(id, list, full, P.Adapters.keySig(itemKey), "item")
end

-- COMMODITY_SEARCH_RESULTS_UPDATED (itemID)
function R.onCommodityResults(id)
    if not P.Mod.on("market") then return end
    if issecretvalue and issecretvalue(id) then return end
    if type(id) ~= "number" or not R.watchSet()[id] then return end
    local list, full = P.Adapters.commodityResults(id)
    record(id, list, full, "c", "commodity")
end

-- Starts a rescan of the watched items (oldest first, at most RESCAN_MAX); nil and a reason when it cannot.
function R.start()
    if not P.Mod.on("market") then return nil, "The sold tracker is switched off in NectarKit." end
    local client = P.Adapters.searchClient()
    if not client then return nil, "This client has no auction house search calls." end
    R.resetWatch()
    local ids = R.order(R.watchedList(), P.db, P.Config.RESCAN_MAX)
    if #ids == 0 then return nil, "Nothing watched yet." end
    R.job = R.new(ids, client)
    return R.job
end

function R.stop()
    if R.job then R.job:cancel() end
end

function R.running() return R.job ~= nil and not R.job:done() end

-- Switched off in NectarKit: a running rescan is cancelled.
P.Mod.listen("market", function(on) if not on then R.stop() end end)

-- /pricewatch market why <id>
function R.diagnose(id)
    local out = {}
    if type(id) ~= "number" then return { "usage: /pricewatch market why <item id or link>" } end
    out[#out + 1] = "item " .. id .. ": watched " .. tostring(R.watchSet()[id] == true) .. ", " .. R.seen .. " results recorded this session"
    local today = P.Days.dayOf(time(), P.Days.epoch0())
    local s = P.Market.summary(P.db, id, today)
    out[#out + 1] = ("tracked: %d scans, %d comparisons on %d days, sold %d, expired %d, cancelled %d, unknown %d%s"):format(s.scans, s.cmp, s.days,
        s.sold, s.exp, s.cxl, s.unk, s.thin and " (thin)" or "")
    out[#out + 1] = "text: " .. tostring(P.Market.text(s))
    local e = P.db and P.db.market and P.db.market[id]
    if e and e.last then
        local n = 0
        for _ in pairs(e.last.rows or {}) do n = n + 1 end
        out[#out + 1] = ("last scan: %d listings, %ds ago, key %s"):format(n, time() - (e.last.t or 0), tostring(e.last.sig))
    end
    local raw = R.lastRaw[id]
    if raw then
        local keys = {}
        for k in pairs(raw) do keys[#keys + 1] = k end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            if k ~= "itemKey" and k ~= "itemLink" then parts[#parts + 1] = k .. "=" .. tostring(raw[k]) end
        end
        out[#out + 1] = "first result row: " .. table.concat(parts, " ")
    else
        out[#out + 1] = "no search result seen for it this session (search it on the AH, or Rescan watched)"
    end
    return out
end
