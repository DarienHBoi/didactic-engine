local _, P = ...

-- Disenchant outcome logger. Your own disenchants are recorded by bracket (the DisenchantBuddy table's item level ranges):
-- PricewatchDB.de = { v = 1, total, b = { ["quality:A|W:lo"] = { n, m = { [matID] = { c = times seen, sum = units } } } } }.
-- DisenchantHelper is retired (audit step 7, owner 2026-11-21): its learned data (DisenchantHelperDB.learn) is imported ONCE at
-- login (DL.importDH; per bracket the bigger sample wins, never summed: both addons saw the same casts) and never read again.
-- P.DE.outcomes switches to the observed rates at P.Config.DE_MIN_SAMPLES.
-- Capture: UNIT_SPELLCAST_SENT (Disenchant; the item is the one picked from a bag while the spell was targeting, else the bag item
-- with the target's name) -> UNIT_SPELLCAST_SUCCEEDED (same cast id) -> the first LOOT_OPENED within LOOT_WINDOW seconds.
P.DELog = {}
local DL = P.DELog
DL.SPELL = 13262          -- Disenchant (DisenchantHelper uses the same id on Forever)
DL.CAST_WINDOW = 12       -- seconds: SENT -> SUCCEEDED
DL.LOOT_WINDOW = 3        -- seconds: SUCCEEDED -> LOOT_OPENED
DL.PICK_WINDOW = 2        -- seconds: a bag item clicked this soon before the cast was sent is its target (when the names agree)
DL.MATS_PER_BUCKET = 16
DL.MAX_BUCKETS = 400

local KIND = { [2] = "W", [4] = "A" }
local CLASS = { W = 2, A = 4 }

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function posInt(v) return type(v) == "number" and v >= 1 and v == math.floor(v) and v < 2 ^ 53 end

local cache = {}
function DL.reset() cache = {} end

local function store(db)
    if type(db) ~= "table" then return nil end
    if type(db.de) ~= "table" or type(db.de.b) ~= "table" then db.de = { v = 1, total = 0, b = {} } end
    return db.de
end

local function key(quality, classID, ilvl)
    local lo = P.DE.bracket(quality, classID, ilvl)
    if not lo or not KIND[classID] then return nil end
    return quality .. ":" .. KIND[classID] .. ":" .. lo
end

-- One disenchant: snap = { quality, classID, ilvl }, got = { [matID] = units }. Refused (false) outside the table, with empty or
-- odd counts, or past the bounds; the whole sample or nothing.
function DL.record(db, snap, got)
    if type(snap) ~= "table" or type(got) ~= "table" then return false end
    local k = key(snap.quality, snap.classID, snap.ilvl)
    local de = store(db)
    if not k or not de then return false end
    local any = false
    for id, qty in pairs(got) do
        if not posInt(id) or not posInt(qty) then return false end
        any = true
    end
    if not any then return false end
    local b = de.b[k]
    local nBuckets = 0
    if not b then
        for _ in pairs(de.b) do nBuckets = nBuckets + 1 end
        if nBuckets >= DL.MAX_BUCKETS then return false end
        b = { n = 0, m = {} }
    end
    local count, new = 0, 0
    for _ in pairs(b.m) do count = count + 1 end
    for id in pairs(got) do if not b.m[id] then new = new + 1 end end
    if count + new > DL.MATS_PER_BUCKET then return false end
    de.b[k] = b
    b.n = b.n + 1
    de.total = (de.total or 0) + 1
    for id, qty in pairs(got) do
        local m = b.m[id] or { c = 0, sum = 0 }
        b.m[id] = m
        m.c, m.sum = m.c + 1, m.sum + qty
    end
    cache = {}
    return true
end

-- One-time import of DisenchantHelper's learned buckets (dhdb = the DisenchantHelperDB global, passed in). Its exact item levels
-- are folded into our bracket keys; per bracket the bigger sample wins (replaces ours only when it has more samples). Returns
-- { brackets, samples } and marks db.de.dhImported, or nil when already imported or there is no usable data (then not marked,
-- so a later login with DisenchantHelper loaded still imports). Bounded like DL.record; never throws.
function DL.importDH(db, dhdb)
    local de = store(db)
    if not de or de.dhImported then return nil end
    local ok, res = pcall(function()
        local learn = type(dhdb) == "table" and dhdb.learn
        if type(learn) ~= "table" or type(learn.buckets) ~= "table" then return nil end
        local folded, any = {}, false
        for _, b in pairs(learn.buckets) do
            local k = type(b) == "table" and CLASS[b.k] and posInt(b.n) and type(b.m) == "table" and key(b.q, CLASS[b.k], b.l)
            if k then
                local out = folded[k] or { n = 0, m = {} }
                folded[k] = out
                out.n = out.n + b.n
                any = true
                for id, m in pairs(b.m) do
                    if posInt(id) and type(m) == "table" and posInt(m.c) and posInt(m.qtySum) then
                        local o = out.m[id] or { c = 0, sum = 0 }
                        out.m[id] = o
                        o.c, o.sum = o.c + m.c, o.sum + m.qtySum
                    end
                end
            end
        end
        if not any then return nil end
        local nBuckets = 0
        for _ in pairs(de.b) do nBuckets = nBuckets + 1 end
        local brackets, samples = 0, 0
        local keys = {}
        for k in pairs(folded) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local f, own = folded[k], de.b[k]
            local mats = 0
            for _ in pairs(f.m) do mats = mats + 1 end
            if (not own or f.n > own.n) and mats <= DL.MATS_PER_BUCKET and (own or nBuckets < DL.MAX_BUCKETS) then
                if not own then nBuckets = nBuckets + 1 end
                de.total = (de.total or 0) + f.n - (own and own.n or 0)
                de.b[k] = f
                brackets, samples = brackets + 1, samples + f.n
            end
        end
        return { brackets = brackets, samples = samples }
    end)
    if not ok or not res then return nil end
    de.dhImported = { t = type(time) == "function" and time() or 0, brackets = res.brackets, samples = res.samples }
    cache = {}
    return res
end

local function toOutcomes(b)
    local out = {}
    for id, m in pairs(b.m) do
        if m.c > 0 then out[#out + 1] = { id = id, chance = m.c / b.n, avg = m.sum / m.c } end
    end
    table.sort(out, function(a, c) if a.chance ~= c.chance then return a.chance > c.chance end return a.id < c.id end)
    return out
end

-- Observed outcomes for an item's bracket: { n, source = "own" | "dh", out = outcomes } (n = 0, out = {} when nothing seen), or nil
-- for items outside the table.
function DL.observed(quality, classID, ilvl)
    local k = key(quality, classID, ilvl)
    if not k then return nil end
    if cache[k] then return cache[k] end
    local own = type(P.db) == "table" and type(P.db.de) == "table" and type(P.db.de.b) == "table" and P.db.de.b[k] or nil
    local res = own and { n = own.n, source = "own", out = toOutcomes(own) } or { n = 0, source = "own", out = {} }
    cache[k] = res
    return res
end

-- The views' label for a disenchant value, from the outcomes meta (second value of P.DE.outcomes).
function DL.label(meta)
    if type(meta) == "table" and (meta.source == "own" or meta.source == "dh") and type(meta.n) == "number" then
        return "Disenchant (your " .. meta.n .. ")"
    end
    return "Disenchant est."
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Capture. deps = { info(id, link) -> {quality, classID, ilvl}, findByName(name) -> id, link, loot() -> { {id, qty} } }.
-- Every dependency call is guarded; secret values are never compared.
local pending, lastPick

function DL.picked(link, now)
    if type(link) == "string" and not secret(link) then lastPick = { link = link, t = now } end
end

local function snapOf(id, link, deps)
    local ok, info = pcall(deps.info, id, link)
    if not ok or type(info) ~= "table" then return nil end
    if type(info.quality) ~= "number" or type(info.classID) ~= "number" or type(info.ilvl) ~= "number" then return nil end
    if not key(info.quality, info.classID, info.ilvl) then return nil end
    return { quality = info.quality, classID = info.classID, ilvl = info.ilvl }
end

local function ours(unit, spellID)
    if secret(unit) or secret(spellID) then return false end
    return unit == "player" and spellID == DL.SPELL
end

function DL.onSent(unit, target, guid, spellID, now, deps)
    if not ours(unit, spellID) then return end
    pending = nil
    local snap
    local named = type(target) == "string" and not secret(target) and target ~= "" and target or nil
    if lastPick and type(now) == "number" and now - lastPick.t <= DL.PICK_WINDOW then
        local pickName = lastPick.link:match("%[(.-)%]")
        local id = tonumber(lastPick.link:match("item:(%d+)"))
        if id and (not named or not pickName or pickName == named) then snap = snapOf(id, lastPick.link, deps) end
    end
    lastPick = nil
    if not snap and named then
        local ok, id, link = pcall(deps.findByName, named)
        if ok and type(id) == "number" then snap = snapOf(id, link, deps) end
    end
    if not snap then return end
    snap.guid = (type(guid) == "string" and not secret(guid)) and guid or nil
    snap.sent = now
    pending = snap
end

function DL.onSucceeded(unit, guid, spellID, now)
    if not ours(unit, spellID) or not pending or pending.done then return end
    if type(now) ~= "number" or now - pending.sent > DL.CAST_WINDOW then pending = nil return end
    local g = (type(guid) == "string" and not secret(guid)) and guid or nil
    if pending.guid and g and pending.guid ~= g then pending = nil return end
    pending.done = now
end

function DL.onFailed(unit, guid, spellID)
    if not ours(unit, spellID) or not pending or pending.done then return end
    local g = (type(guid) == "string" and not secret(guid)) and guid or nil
    if not pending.guid or not g or pending.guid == g then pending = nil end
end

-- The first loot window after a finished disenchant. Returns true when a sample was recorded.
function DL.onLoot(now, deps)
    local snap = pending
    if not snap or not snap.done then return false end
    pending = nil
    if type(now) ~= "number" or now - snap.done > DL.LOOT_WINDOW then return false end
    local ok, list = pcall(deps.loot)
    if not ok or type(list) ~= "table" then return false end
    local got = {}
    for _, e in ipairs(list) do
        if type(e) == "table" and posInt(e.id) and posInt(e.qty) then got[e.id] = (got[e.id] or 0) + e.qty end
    end
    return DL.record(P.db, snap, got) == true
end

-- The live dependencies (Adapters, guarded there).
function DL.deps()
    return {
        info = function(id, link) return P.Adapters.itemInfo(id, link) end,
        findByName = function(name) return P.Adapters.bagItemByName(name) end,
        loot = function() return P.Adapters.lootItems() end,
    }
end

-- ---------------------------------------------------------------------------------------------------------------------
-- /pricewatch de: one line per bracket with samples (ours and DisenchantHelper's).
local QUALITY = { [2] = "green", [3] = "blue", [4] = "purple" }
function DL.report(db)
    local out, seen = {}, {}
    local keys = {}
    local function add(k) if not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
    for k in pairs(type(db) == "table" and type(db.de) == "table" and type(db.de.b) == "table" and db.de.b or {}) do add(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local q, kind, lo = k:match("^(%d+):(%a):(%d+)$")
        q, lo = tonumber(q), tonumber(lo)
        local _, hi = P.DE.bracket(q, CLASS[kind], lo)
        local own = db and db.de and db.de.b[k]
        local obs = DL.observed(q, CLASS[kind], lo)
        local used = obs and obs.n >= P.Config.DE_MIN_SAMPLES and "using yours" or "table still used"
        out[#out + 1] = ("%s %s %d-%d: %d yours (%s)"):format(QUALITY[q] or tostring(q),
            kind == "A" and "armor" or "weapon", lo, hi or lo, own and own.n or 0, used)
    end
    if #out == 0 then out[1] = "no disenchants logged yet" end
    local imp = type(db) == "table" and type(db.de) == "table" and db.de.dhImported
    if type(imp) == "table" then
        out[#out + 1] = ("imported from DisenchantHelper once: %d brackets, %d samples (it can be disabled now)"):format(imp.brackets or 0, imp.samples or 0)
    end
    return out
end

-- Bag clicks: when Disenchant is targeting, the clicked bag item is its target. hooksecurefunc runs after the click, so the
-- pick is noted for every click and trusted only when the cast is sent within PICK_WINDOW seconds with the same name.
-- Bag addons that use secure item buttons may not call these at all; then the target name (UNIT_SPELLCAST_SENT) is used.
function DL.installHooks()
    if DL.hooked or type(hooksecurefunc) ~= "function" then return end
    DL.hooked = true
    local function onPick(bag, slot)
        if not P.Mod.on("delog") then return end
        pcall(function()
            local link = C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
            if link == nil and type(GetContainerItemLink) == "function" then link = GetContainerItemLink(bag, slot) end
            DL.picked(link, GetTime())
        end)
    end
    if type(C_Container) == "table" then
        for _, name in ipairs({ "PickupContainerItem", "UseContainerItem" }) do
            if type(C_Container[name]) == "function" then pcall(hooksecurefunc, C_Container, name, onPick) end
        end
    end
    for _, name in ipairs({ "PickupContainerItem", "UseContainerItem" }) do
        if type(_G[name]) == "function" then pcall(hooksecurefunc, name, onPick) end
    end
end

-- Client events (Main.lua passes them on; module 'delog' off = ignored).
function DL.onEvent(event, ...)
    if not P.Mod.on("delog") then return end
    local now = type(GetTime) == "function" and GetTime() or 0
    if event == "UNIT_SPELLCAST_SENT" then
        local unit, target, guid, spellID = ...
        DL.onSent(unit, target, guid, spellID, now, DL.deps())
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, guid, spellID = ...
        DL.onSucceeded(unit, guid, spellID, now)
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit, guid, spellID = ...
        DL.onFailed(unit, guid, spellID)
    elseif event == "LOOT_OPENED" then
        if DL.onLoot(now, DL.deps()) and P.Tip and P.Tip.resetCache then pcall(P.Tip.resetCache, true) end
    end
end
