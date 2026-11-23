local _, P = ...

-- Loot log: what you loot, where (zone) and from what (fishing, mining, herbs, skinning, mobs, objects), for gold per hour per spot.
-- PricewatchDB.loot = { v = 1, spots = { ["zone|source"] = { zone, source, loots, secs, copper, last (unix), items = { [id] = units } } } }.
-- Only the slots you actually take count (LOOT_SLOT_CLEARED); coins = money gained while the window was open. Time at a spot = the
-- gaps between its loots, each at most GAP_CAP; after a longer break the spot's average gap so far is counted instead.
-- Disenchant / milling / prospecting loot and opened containers (item GUID) are not spots.
P.Loot = {}
local L = P.Loot
L.FISH_WINDOW = 30     -- seconds: a Fishing cast this recent makes the loot window a fishing loot (the bobber takes up to ~20 s)
L.GATHER_WINDOW = 5    -- seconds: mining, herb gathering, skinning
L.GAP_CAP = 300        -- seconds: a longer gap between two loots at a spot is a break, not farming time
L.START_SECS = 30      -- seconds counted for a break when the spot has no average yet
L.MIN_SECS = 600       -- a spot needs this much logged time before it gets a gold-per-hour figure
L.MAX_SPOTS = 100
L.MAX_ITEMS = 40       -- item kinds kept per spot (the rarest makes room)
L.TOP = 3              -- items named per spot in the view

-- Gathering spells by name (any rank) and by id (Classic rank ids, for when the name cannot be read). INFERRED ids.
local BY_NAME = { ["Fishing"] = "fishing", ["Mining"] = "mining", ["Herb Gathering"] = "herbs", ["Skinning"] = "skinning",
    ["Disenchant"] = "skip", ["Milling"] = "skip", ["Prospecting"] = "skip", ["Pick Lock"] = "skip", ["Opening"] = "skip" }
local BY_ID = { [7620] = "fishing", [7731] = "fishing", [7732] = "fishing", [18248] = "fishing",
    [2575] = "mining", [2576] = "mining", [3564] = "mining", [10248] = "mining",
    [2366] = "herbs", [2368] = "herbs", [3570] = "herbs", [11993] = "herbs",
    [8613] = "skinning", [8617] = "skinning", [8618] = "skinning", [10768] = "skinning",
    [13262] = "skip", [1804] = "skip" }
local LABELS = { fishing = "Fishing", mining = "Mining", herbs = "Herbs", skinning = "Skinning", mob = "Mobs", object = "Objects", other = "Other" }

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function posInt(v) return type(v) == "number" and v >= 1 and v == math.floor(v) and v < 2 ^ 53 end
local function plain(v) if secret(v) then return nil end return v end

function L.spellKind(spellID, name)
    name = plain(name)
    if type(name) == "string" and BY_NAME[name] then return BY_NAME[name] end
    spellID = plain(spellID)
    return type(spellID) == "number" and BY_ID[spellID] or nil
end

function L.sourceLabel(s) return LABELS[s] or tostring(s) end

-- lastSpell = { spell = kind, t } or nil; guid = the loot's source GUID (GetLootSourceInfo). Returns a source, or nil = not a spot.
function L.source(lastSpell, now, guid)
    if type(lastSpell) == "table" and type(now) == "number" and type(lastSpell.t) == "number" then
        local age = now - lastSpell.t
        if lastSpell.spell == "fishing" and age <= L.FISH_WINDOW then return "fishing" end
        if age <= L.GATHER_WINDOW then
            if lastSpell.spell == "skip" then return nil end
            if lastSpell.spell == "mining" or lastSpell.spell == "herbs" or lastSpell.spell == "skinning" then return lastSpell.spell end
        end
    end
    guid = plain(guid)
    if type(guid) == "string" then
        if guid:find("^Creature%-") or guid:find("^Vehicle%-") then return "mob" end
        if guid:find("^GameObject%-") then return "object" end
        if guid:find("^Item%-") then return nil end
    end
    return "other"
end

local function store(db)
    if type(db) ~= "table" then return nil end
    if type(db.loot) ~= "table" or type(db.loot.spots) ~= "table" then db.loot = { v = 1, spots = {} } end
    return db.loot
end

-- One loot window. items = { [id] = units }, copper = coins (0 or more). false when nothing to record.
function L.record(db, zone, source, items, copper, now)
    if type(zone) ~= "string" or zone == "" or type(source) ~= "string" or type(items) ~= "table" or type(now) ~= "number" then return false end
    copper = posInt(copper) and copper or 0
    local any = copper > 0
    for id, q in pairs(items) do
        if not posInt(id) or not posInt(q) then return false end
        any = true
    end
    if not any then return false end
    local lo = store(db)
    if not lo then return false end
    local key = zone .. "|" .. source
    local sp = lo.spots[key]
    if not sp then
        local n, oldestKey, oldest = 0, nil, nil
        for k, s in pairs(lo.spots) do
            n = n + 1
            if not oldest or (s.last or 0) < oldest then oldest, oldestKey = s.last or 0, k end
        end
        if n >= L.MAX_SPOTS and oldestKey then lo.spots[oldestKey] = nil end
        sp = { zone = zone, source = source, loots = 0, secs = 0, copper = 0, items = {} }
        lo.spots[key] = sp
    end
    if sp.last then
        local gap = now - sp.last
        if gap >= 0 and gap <= L.GAP_CAP then sp.secs = sp.secs + gap
        elseif gap > L.GAP_CAP then sp.secs = sp.secs + (sp.loots > 0 and sp.secs > 0 and math.floor(sp.secs / sp.loots + 0.5) or L.START_SECS) end
    end
    sp.loots = sp.loots + 1
    sp.last = now
    sp.copper = sp.copper + copper
    for id, q in pairs(items) do
        if not sp.items[id] then
            local n, rareId, rareQ = 0, nil, nil
            for i, x in pairs(sp.items) do
                n = n + 1
                if not rareQ or x < rareQ or (x == rareQ and i < rareId) then rareId, rareQ = i, x end
            end
            if n >= L.MAX_ITEMS and rareId then sp.items[rareId] = nil end
        end
        sp.items[id] = (sp.items[id] or 0) + q
    end
    return true
end

-- The Gather view's spot rows, best gold per hour first (spots under MIN_SECS last, no rate).
-- deps = { price(id) -> AH price (copper) or nil, vendor(id) -> vendor sell price or nil }; each unit is worth the higher of its
-- price after the AH cut and its vendor price. Row: { zone, source, loots, secs, copper, value (items + coins), perHour, top = { {id, units, value} } }.
function L.spots(db, deps)
    local out = {}
    local lo = type(db) == "table" and type(db.loot) == "table" and type(db.loot.spots) == "table" and db.loot.spots or {}
    local function unit(id)
        local okP, p = pcall(deps.price, id)
        local okV, v = pcall(deps.vendor, id)
        local a = okP and type(p) == "number" and p > 0 and P.Reco.net(p) or 0
        local b = okV and type(v) == "number" and v > 0 and v or 0
        return math.max(a, b)
    end
    for _, sp in pairs(lo) do
        if type(sp) == "table" and type(sp.items) == "table" then
            local value, top = sp.copper or 0, {}
            for id, q in pairs(sp.items) do
                local v = unit(id) * q
                value = value + v
                top[#top + 1] = { id = id, units = q, value = v }
            end
            table.sort(top, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.id < b.id end)
            while #top > L.TOP do table.remove(top) end
            local secs = sp.secs or 0
            local perHour = secs >= L.MIN_SECS and math.floor(value * 3600 / secs + 0.5) or nil
            out[#out + 1] = { zone = sp.zone, source = sp.source, loots = sp.loots, secs = secs, copper = sp.copper or 0,
                value = value, perHour = perHour, top = top, last = sp.last or 0 }
        end
    end
    table.sort(out, function(a, b)
        if (a.perHour ~= nil) ~= (b.perHour ~= nil) then return a.perHour ~= nil end
        if a.perHour and a.perHour ~= b.perHour then return a.perHour > b.perHour end
        if a.value ~= b.value then return a.value > b.value end
        return (a.zone .. a.source) < (b.zone .. b.source)
    end)
    return out
end

-- "40 loots in 30 min: Raw Fish x40, ..." for a spot row. nameOf(id) -> name or nil.
function L.reason(row, nameOf)
    local mins = math.floor((row.secs or 0) / 60 + 0.5)
    local parts = {}
    for _, t in ipairs(row.top or {}) do
        local okN, nm = pcall(nameOf or function() end, t.id)
        parts[#parts + 1] = ((okN and type(nm) == "string") and nm or ("Item " .. t.id)) .. " x" .. t.units
    end
    local s = row.loots .. " loots in " .. mins .. " min"
    if (row.copper or 0) > 0 then s = s .. ", coins " .. P.Money.format(row.copper) end
    if #parts > 0 then s = s .. ": " .. table.concat(parts, ", ") end
    return s
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Capture. deps = { zone() -> name, sourceGUID() -> GUID of the loot, loot() -> { {id, qty, slot} }, money() -> copper }.
local lastSpell, session

function L.onSpell(name, now, spellID)
    local kind = L.spellKind(spellID, name)
    lastSpell = kind and { spell = kind, t = now } or nil
end

local function call(fn) local ok, v = pcall(fn) if ok then return v end return nil end

function L.onOpened(now, deps)
    session = nil
    local zone = call(deps.zone)
    if type(zone) ~= "string" or zone == "" or secret(zone) then return end
    local src = L.source(lastSpell, now, call(deps.sourceGUID))
    if not src then return end
    local slots = {}
    local list = call(deps.loot)
    for _, e in ipairs(type(list) == "table" and list or {}) do
        if type(e) == "table" and posInt(e.slot) and posInt(e.id) and posInt(e.qty) then slots[e.slot] = e end
    end
    local m = plain(call(deps.money))
    session = { zone = zone, source = src, slots = slots, taken = {}, money = type(m) == "number" and m or nil }
end

function L.onSlotCleared(slot)
    slot = plain(slot)
    if session and type(slot) == "number" and session.slots[slot] then session.taken[slot] = session.slots[slot] end
end

function L.onClosed(now, deps)
    local s = session
    session = nil
    if not s then return false end
    local items = {}
    for _, e in pairs(s.taken) do items[e.id] = (items[e.id] or 0) + e.qty end
    local copper = 0
    local m = plain(call(deps.money))
    if s.money and type(m) == "number" and m > s.money then copper = m - s.money end
    return L.record(P.db, s.zone, s.source, items, copper, now) == true
end

-- The live dependencies, all guarded.
function L.deps()
    return {
        zone = function()
            if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
                local id = C_Map.GetBestMapForUnit("player")
                local info = type(id) == "number" and C_Map.GetMapInfo(id)
                if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
            end
            if type(GetRealZoneText) == "function" then return GetRealZoneText() end
        end,
        sourceGUID = function()
            if type(GetLootSourceInfo) ~= "function" then return nil end
            local n = type(GetNumLootItems) == "function" and GetNumLootItems() or 0
            for i = 1, n do
                local guid = GetLootSourceInfo(i)
                if type(guid) == "string" then return guid end
            end
        end,
        loot = function() return P.Adapters.lootItems() end,
        money = function() return type(GetMoney) == "function" and GetMoney() or nil end,
    }
end

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id) if ok and n then return n end end
    if type(GetSpellInfo) == "function" then local ok, n = pcall(GetSpellInfo, id) if ok then return n end end
end

-- Client events from Main.lua (module 'gather' off = ignored).
function L.onEvent(event, ...)
    if not P.Mod.on("gather") then return end
    local now = type(GetTime) == "function" and GetTime() or 0
    if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit, _, spellID = ...
        if secret(unit) or unit ~= "player" or secret(spellID) then return end
        L.onSpell(spellName(spellID), now, spellID)
    elseif event == "LOOT_OPENED" then
        L.onOpened(now, L.deps())
    elseif event == "LOOT_SLOT_CLEARED" then
        L.onSlotCleared((...))
    elseif event == "LOOT_CLOSED" then
        L.onClosed(type(time) == "function" and time() or now, L.deps())
    end
end
