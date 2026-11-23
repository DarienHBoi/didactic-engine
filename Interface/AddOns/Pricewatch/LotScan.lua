local _, P = ...
-- Live lot scan for the Deals panel's "Live lots" mode, ported from Disenchantry's AH scanner (study: side notes
-- disenchantry-study.md) but with Pricewatch's maths: logged Forever rates (P.DE.outcomes via DELog) and the 5% AH cut.
-- One pass: browse uncommon-epic armor/weapons -> candidates (lowest price under the per-unit disenchant value) -> one item
-- search per candidate -> every lot (one auction x quantity) valued. A key whose browse signature (lowest price, quantity,
-- value) is unchanged since its last clean search is not searched again; one such key per pass is re-checked when its check is
-- AUDIT_SECS old (equal price and count can hide replaced auctions). Pure: the client and the value lookups are injected.
P.LotScan = {}
local L = P.LotScan

local TIMEOUT, AUDIT_SECS, FILTER_STEP = 30, 120, 100
L.cache = {} -- key -> { sig, at, rows }; lives for the session, shared by every pass

local function plainNum(v)
    if type(v) ~= "number" then return nil end
    if type(issecretvalue) == "function" then
        local ok, s = pcall(issecretvalue, v)
        if not ok or s then return nil end
    end
    return v
end

local function keyString(k)
    if type(k) ~= "table" then return nil end
    local id = plainNum(k.itemID)
    if not id then return nil end
    return id .. ":" .. (plainNum(k.itemLevel) or 0) .. ":" .. (plainNum(k.itemSuffix) or 0)
end
L.keyString = keyString

-- True when the outcomes can give `mat` (chance above 0); no mat = every item.
function L.matches(outcomes, mat)
    if not mat then return true end
    for _, o in ipairs(outcomes or {}) do if o.id == mat and (o.chance or 0) > 0 then return true end end
    return false
end

-- Every disenchant material Pricewatch knows (the table's), sorted by id.
function L.materials()
    local out = {}
    for id in pairs(P.DE.MATS) do out[#out + 1] = id end
    table.sort(out)
    return out
end

-- Item info per item link (or id) for the session: a lot's detailed item level does not change, and a pass asks for the same
-- links again and again. Only answered lookups are kept; bounded.
L.infoCache, L.infoN = {}, 0
local INFO_MAX = 4000
function L.itemInfo(id, link)
    local k = type(link) == "string" and link or id
    local c = L.infoCache[k]
    if c then return c end
    local ii = P.Adapters.itemInfo(id, link)
    if type(ii) == "table" and ii.quality ~= nil then
        if L.infoN >= INFO_MAX then L.infoCache, L.infoN = {}, 0 end
        L.infoCache[k] = ii
        L.infoN = L.infoN + 1
    end
    return ii
end

-- The in-game value lookups. material = an item id to keep only items that can give it (nil = all). An item's quality and
-- class come from the deal index when it has them (no client call), the item level from the AH key; values from P.DE.unitValue
-- with the shared memo (P.DealIndex.memo, via AHRows.deps).
function L.deps(material)
    local ah = P.AHRows.deps()
    ah.itemInfo = L.itemInfo
    local items = P.DealIndex and P.DealIndex.items(P.db) or nil
    return {
        unit = function(id, itemKey)
            local it = items and items[id]
            local q, cls, base
            if type(it) == "table" and it.q and it.c then
                q, cls, base = it.q, it.c, it.l
            else
                local ii = L.itemInfo(id)
                if type(ii) ~= "table" or ii.quality == nil then P.Adapters.requestItem(id) return "await" end
                q, cls, base = plainNum(ii.quality), plainNum(ii.classID), plainNum(ii.ilvl)
            end
            local ilvl = plainNum(itemKey and itemKey.itemLevel)
            if not ilvl or ilvl == 0 then ilvl = plainNum(base) end
            if not (q and cls and ilvl) or q < 2 or q > 4 or (cls ~= 2 and cls ~= 4) then return nil end
            local u = P.DE.unitValue(q, cls, ilvl, { price = ah.price, memo = ah.memo })
            if not u or not L.matches(u.outcomes, material) then return nil end
            return { de = u.de, outcomes = u.outcomes }
        end,
        memo = ah.memo,
        evaluate = function(info, id) return P.AHRows.evaluate(info, ah, id) end,
        name = function(id)
            local it = items and items[id]
            if type(it) == "table" and it.n then return it.n end
            local ok, ii = pcall(L.itemInfo, id)
            return ok and type(ii) == "table" and ii.name or nil
        end,
    }
end

local Job = {}
Job.__index = Job

-- opts: cache (default L.cache), now (seconds).
function L.new(client, deps, opts)
    opts = opts or {}
    local j = setmetatable({ client = client, deps = deps, cache = opts.cache or L.cache, now = opts.now or 0,
        phase = "browse", waiting = false, answered = false, wait = 0, filterAt = 1, summaries = {}, cands = {},
        index = 1, rows = {}, audited = false,
        stats = { keys = 0, candidates = 0, lots = 0, filtered = 0, awaiting = 0, missing = 0, unchanged = 0 } }, Job)
    return j
end

function Job:done() return self.phase == "done" end
function Job:cancel(why) if self.phase ~= "done" then self.stopped = why or "cancelled"; self.phase = "done" end end
function Job:currentKey() local c = self.cands[self.index] return c and c.itemKey end
function Job:onBrowse() if self.phase == "browse" and self.waiting then self.answered = true end end
function Job:onSearch(itemID)
    local k = self:currentKey()
    if self.phase == "search" and self.waiting and k and (itemID == nil or itemID == k.itemID) then self.answered = true end
end

local function call(self, name, ...)
    local fn = self.client[name]
    if type(fn) ~= "function" then return false, "no " .. name end
    return pcall(fn, ...)
end

-- Changes whenever the rows or counters change (Live lots rebuilds only when it does, at most once a second).
function Job:signature()
    local s = self.stats
    return table.concat({ self.phase, #self.rows, self.index, s.lots, s.missing, s.awaiting, s.filtered, s.unchanged, s.keys,
        tostring(self.stopped) }, ":")
end

function Job:status()
    local s = self.stats
    return ("Candidates %d/%d, Lots %d, Profitable %d, Missing prices %d, Awaiting data %d, Filtered %d, Unchanged %d, Keys %d"):format(
        math.min(self.index - 1, #self.cands), #self.cands, s.lots, #self.rows, s.missing, s.awaiting, s.filtered, s.unchanged, s.keys)
end

-- Sends `name` once the client is ready; returns true when sent.
function Job:send(name, ...)
    local okR, ready = call(self, "ready")
    if not okR then self:cancel("client error: " .. tostring(ready)) return false end
    if not ready then return false end
    local ok, err = call(self, name, ...)
    if not ok then self:cancel("client error: " .. tostring(err)) return false end
    self.waiting, self.answered, self.wait = true, false, 0
    return true
end

function Job:filterStep()
    for _ = 1, FILTER_STEP do
        local s = self.summaries[self.filterAt]
        if not s then self.phase = "search"; self.stats.candidates = #self.cands; return end
        self.filterAt = self.filterAt + 1
        local key = keyString(s.itemKey)
        if key then
            self.stats.keys = self.stats.keys + 1
            local okU, u = pcall(self.deps.unit, s.itemKey.itemID, s.itemKey)
            if not okU or u == nil then self.stats.filtered = self.stats.filtered + 1
            elseif u == "await" then self.stats.awaiting = self.stats.awaiting + 1
            elseif u.de == nil then self.stats.missing = self.stats.missing + 1
            else
                local minPrice = plainNum(s.minPrice)
                if minPrice and minPrice >= u.de then self.stats.filtered = self.stats.filtered + 1
                else
                    local sig = tostring(minPrice) .. ":" .. tostring(plainNum(s.totalQuantity)) .. ":" .. u.de
                    local c = self.cache[key]
                    local same = c and c.sig == sig
                    if same and (self.now - c.at < AUDIT_SECS or self.audited) then
                        self.stats.unchanged = self.stats.unchanged + 1
                        for _, r in ipairs(c.rows) do self.rows[#self.rows + 1] = r end
                    else
                        if same then self.audited = true end
                        self.cands[#self.cands + 1] = { itemKey = s.itemKey, key = key, sig = sig }
                    end
                end
            end
        end
    end
end

function Job:readLots(cand)
    local okL, list = call(self, "searchResults", cand.itemKey)
    if not okL or type(list) ~= "table" then self.stats.missing = self.stats.missing + 1 return end
    local rows, clean = {}, true
    for _, info in ipairs(list) do
        if type(info) == "table" and not info.containsOwnerItem and not info.containsAccountItem then
            local okE, e = pcall(self.deps.evaluate, info, cand.itemKey.itemID)
            if okE and e and e.lot then
                self.stats.lots = self.stats.lots + 1
                if not e.de then clean = false; self.stats.missing = self.stats.missing + 1
                else
                    local value = e.de * e.qty
                    if value > e.lot then
                        local okN, name = pcall(self.deps.name, e.id)
                        rows[#rows + 1] = { id = e.id, key = cand.key, name = okN and name or nil, quality = e.quality,
                            auctionID = info.auctionID, qty = e.qty, buy = e.lot, gets = value, de = value,
                            profit = value - e.lot, roi = math.floor((value - e.lot) / e.lot * 100 + 0.5), kind = "de",
                            needSkill = e.needSkill, outcomes = e.outcomes, age = 0, itemKey = cand.itemKey }
                    end
                end
            elseif okE and e == nil then
                clean = false -- item info not loaded for this lot
            end
        end
    end
    for _, r in ipairs(rows) do self.rows[#self.rows + 1] = r end
    if clean then self.cache[cand.key] = { sig = cand.sig, at = self.now, rows = rows } else self.cache[cand.key] = nil end
end

function Job:tick(dt, now)
    if self:done() then return end
    self.now = now or (self.now + (dt or 0))
    if self.waiting then
        self.wait = self.wait + (dt or 0)
        if not self.answered then
            if self.wait >= TIMEOUT then
                self.waiting = false
                if self.phase == "browse" then
                    local ok, list = call(self, "browseResults")
                    if ok and type(list) == "table" and #list > 0 then self.summaries, self.phase = list, "filter"
                    else self:cancel("the auction house did not answer") end
                else
                    local c = self.cands[self.index]
                    if c then self.cache[c.key] = nil end
                    self.stats.missing = self.stats.missing + 1
                    self.index = self.index + 1
                end
            end
            return
        end
        self.waiting, self.answered = false, false
        if self.phase == "browse" then
            local okF, full = call(self, "browseFull")
            if okF and not full then
                local okM, err = call(self, "browseMore")
                if not okM then self:cancel("client error: " .. tostring(err)) return end
                self.waiting, self.wait = true, 0
                return
            end
            local ok, list = call(self, "browseResults")
            self.summaries = (ok and type(list) == "table") and list or {}
            self.phase = "filter"
        elseif self.phase == "search" then
            local c = self.cands[self.index]
            local okF, full = call(self, "searchFull", c.itemKey)
            if okF and not full then
                local okM = call(self, "searchMore", c.itemKey)
                if okM then self.waiting, self.wait = true, 0 return end
            end
            self:readLots(c)
            self.index = self.index + 1
        end
        return
    end
    if self.phase == "browse" then self:send("browse")
    elseif self.phase == "filter" then self:filterStep()
    elseif self.phase == "search" then
        local c = self.cands[self.index]
        if not c then self.phase = "done" return end
        local okK, kr = call(self, "keyReady", c.itemKey)
        if okK and kr == false then
            self.wait = self.wait + (dt or 0)
            if self.wait >= TIMEOUT then self.wait = 0; self.stats.awaiting = self.stats.awaiting + 1; self.index = self.index + 1 end
            return
        end
        self:send("search", c.itemKey)
    end
end

-- Display rows: one group per item (its best lot), and its lots under it when expanded. A lot shows only when it beats its buyout
-- by the Min profit (P.Reco.beats, per lot) and, unless includeHighSkill, your Enchanting is high enough.
-- opts: margin, expanded = { [key] = true }, sort (Deals sort key), includeHighSkill.
-- The one lot filter (the view here and the Workflow buy queue): beats its buyout by the Min profit and, unless includeHighSkill,
-- your Enchanting is high enough. opts: margin, includeHighSkill.
function L.keep(r, opts)
    opts = opts or {}
    return P.Reco.beats(r.gets, r.buy, opts.margin) and (opts.includeHighSkill or not r.needSkill) and true or false
end

function L.view(rows, opts)
    opts = opts or {}
    local groups, order = {}, {}
    for _, r in ipairs(rows or {}) do
        if L.keep(r, opts) then
            local g = groups[r.key]
            if not g then g = { lots = {} }; groups[r.key] = g; order[#order + 1] = r.key end
            g.lots[#g.lots + 1] = r
        end
    end
    local heads = {}
    for _, k in ipairs(order) do
        local g = groups[k]
        table.sort(g.lots, function(a, b)
            if a.profit ~= b.profit then return a.profit > b.profit end
            return (a.auctionID or 0) < (b.auctionID or 0)
        end)
        local h = {}
        for f, v in pairs(g.lots[1]) do h[f] = v end
        h.group, h.count, h.lots, h.lot = true, #g.lots, g.lots, nil
        heads[#heads + 1] = h
    end
    heads = P.Deals.sort(heads, opts.sort or "profit")
    local out = {}
    for _, h in ipairs(heads) do
        out[#out + 1] = h
        if opts.expanded and opts.expanded[h.key] then
            for _, r in ipairs(h.lots) do
                local x = {}
                for f, v in pairs(r) do x[f] = v end
                x.lot = true
                out[#out + 1] = x
            end
        end
    end
    return out
end
