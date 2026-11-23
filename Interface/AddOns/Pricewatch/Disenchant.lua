local _, P = ...
P.DE = {}
local DE = P.DE
DE.LABEL = "Disenchant (estimate)"

-- RATES PORTED FROM DisenchantBuddy v2.8.0 (DisenchantResults/{Uncommon,Rare,Epic}.lua), the branch it runs on WoW Forever
-- (IsClassic-or-IsForever where it has one, the non-MoP quantity where it has IsMoP). Data only: nothing here calls
-- DisenchantBuddy. Average quantity = (min + max) / 2; chance = probability / 100. Brackets that need TBC+ materials
-- (which DisenchantBuddy does not define on Forever) are left out, so those item levels have no outcome.
-- Each bracket: { minIlvl, maxIlvl, { {matID, chance, avgQty}, ... } } with chances adding up to 1.
local function b(lo, hi, ...) return { lo, hi, { ... } } end
local GREEN_ARMOR = {
    b(1, 15, { 10940, 0.8, 1.5 }, { 10938, 0.2, 1.5 }),
    b(16, 20, { 10940, 0.75, 2.5 }, { 10939, 0.2, 1.5 }, { 10978, 0.05, 1 }),
    b(21, 25, { 10940, 0.75, 5 }, { 10998, 0.15, 1.5 }, { 10978, 0.1, 1 }),
    b(26, 30, { 11083, 0.75, 1.5 }, { 11082, 0.2, 1.5 }, { 11084, 0.05, 1 }),
    b(31, 35, { 11083, 0.75, 3.5 }, { 11134, 0.2, 1.5 }, { 11138, 0.05, 1 }),
    b(36, 40, { 11137, 0.75, 1.5 }, { 11135, 0.2, 1.5 }, { 11139, 0.05, 1 }),
    b(41, 45, { 11137, 0.75, 3.5 }, { 11174, 0.2, 1.5 }, { 11177, 0.05, 1 }),
    b(46, 50, { 11176, 0.75, 1.5 }, { 11175, 0.2, 1.5 }, { 11178, 0.05, 1 }),
    b(51, 55, { 11176, 0.75, 4 }, { 16202, 0.2, 1.5 }, { 14343, 0.05, 1 }),
    b(56, 60, { 16204, 0.75, 1.5 }, { 16203, 0.2, 1.5 }, { 14344, 0.05, 1 }),
    b(61, 65, { 16204, 0.75, 3.5 }, { 16203, 0.2, 2.5 }, { 14344, 0.05, 1 }),
}
local GREEN_WEAPON = {
    b(1, 15, { 10938, 0.8, 1.5 }, { 10940, 0.2, 1.5 }),
    b(16, 20, { 10939, 0.75, 1.5 }, { 10940, 0.2, 2.5 }, { 10978, 0.05, 1 }),
    b(21, 25, { 10939, 0.75, 1.5 }, { 10940, 0.15, 5 }, { 10978, 0.1, 1 }),
    b(26, 30, { 10939, 0.75, 1.5 }, { 11083, 0.2, 1.5 }, { 11084, 0.05, 1 }),
    b(31, 35, { 11134, 0.75, 1.5 }, { 11083, 0.2, 3.5 }, { 11138, 0.05, 1 }),
    b(36, 40, { 11135, 0.75, 1.5 }, { 11137, 0.2, 1.5 }, { 11139, 0.05, 1 }),
    b(41, 45, { 11174, 0.75, 1.5 }, { 11137, 0.2, 3.5 }, { 11177, 0.05, 1 }),
    b(46, 50, { 11175, 0.75, 1.5 }, { 11176, 0.2, 1.5 }, { 11178, 0.05, 1 }),
    b(51, 55, { 16202, 0.75, 1.5 }, { 11176, 0.2, 3.5 }, { 14343, 0.05, 1 }),
    b(56, 60, { 16203, 0.75, 1.5 }, { 16204, 0.2, 1.5 }, { 14344, 0.05, 1 }),
    b(61, 65, { 16203, 0.75, 2.5 }, { 16204, 0.2, 3.5 }, { 14344, 0.05, 1 }),
}
local RARE = {
    b(1, 25, { 10978, 1, 1 }),
    b(26, 30, { 11084, 1, 1 }),
    b(31, 35, { 11138, 1, 1 }),
    b(36, 40, { 11139, 1, 1 }),
    b(41, 45, { 11177, 1, 1 }),
    b(46, 50, { 11178, 1, 1 }),
    b(51, 55, { 14343, 1, 1 }),
    b(56, 74, { 14344, 0.995, 1 }, { 20725, 0.005, 1 }),
    b(75, 86, { 14344, 0.995, 1 }, { 20725, 0.005, 1 }),
}
local EPIC = {
    b(1, 45, { 11177, 1, 3 }),
    b(46, 50, { 11178, 1, 3 }),
    b(51, 55, { 14343, 1, 3 }),
    b(56, 60, { 20725, 1, 1 }),
    b(61, 92, { 20725, 0.33, 1 }, { 20725, 0.67, 2 }),
}

-- Armor and weapons are kept apart (DisenchantBuddy differs for green items); rare and epic are the same for both.
local BY_CLASS = {
    [4] = { [2] = GREEN_ARMOR, [3] = RARE, [4] = EPIC },
    [2] = { [2] = GREEN_WEAPON, [3] = RARE, [4] = EPIC },
}

-- Every mat the tables can produce (watched so their prices are in the history).
DE.MATS = {}
for _, byQuality in pairs(BY_CLASS) do
    for _, tbl in pairs(byQuality) do
        for _, br in ipairs(tbl) do
            for _, o in ipairs(br[3]) do DE.MATS[o[1]] = true end
        end
    end
end

-- The table bracket { lo, hi, outcomes } an item falls in, or nil. classID 2 = weapon, 4 = armor (the client's item class ids).
local function findBracket(quality, classID, ilvl)
    local byQuality = BY_CLASS[classID]
    if not byQuality or type(ilvl) ~= "number" then return nil end
    local tbl = byQuality[quality]
    if not tbl then return nil end
    for _, br in ipairs(tbl) do
        if ilvl >= br[1] and ilvl <= br[2] then return br end
    end
    return nil
end

-- lo, hi of the bracket (the disenchant logger groups samples by it), or nil.
function DE.bracket(quality, classID, ilvl)
    local br = findBracket(quality, classID, ilvl)
    if br then return br[1], br[2] end
    return nil
end

-- The DisenchantBuddy table only.
function DE.tableOutcomes(quality, classID, ilvl)
    local br = findBracket(quality, classID, ilvl)
    if not br then return nil end
    local out = {}
    for _, o in ipairs(br[3]) do out[#out + 1] = { id = o[1], chance = o[2], avg = o[3] } end
    return out
end

-- What a disenchant gives: your own observed rates (P.DELog) once the bracket has P.Config.DE_MIN_SAMPLES samples, else the
-- table. Second value = { source = "own" | "dh" | "table", n = samples seen in the bracket }. Items outside the table: nil.
function DE.outcomes(quality, classID, ilvl)
    local tbl = DE.tableOutcomes(quality, classID, ilvl)
    if not tbl then return nil end
    local log = P.DELog
    if log and type(log.observed) == "function" then
        local ok, obs = pcall(log.observed, quality, classID, ilvl)
        if ok and type(obs) == "table" then
            if obs.n >= P.Config.DE_MIN_SAMPLES and #obs.out > 0 then return obs.out, { source = obs.source, n = obs.n } end
            return tbl, { source = "table", n = obs.n }
        end
    end
    return tbl, { source = "table", n = 0 }
end

-- Enchanting skill needed to disenchant by item level. DisenchantBuddy has no such table, so this is the usual
-- Classic ladder (INFERRED, not verified on Forever): { maxIlvl, skill }.
local SKILL = { { 20, 1 }, { 25, 25 }, { 30, 50 }, { 35, 75 }, { 40, 100 }, { 45, 125 }, { 50, 150 }, { 55, 175 }, { 60, 200 }, { 65, 225 } }
function DE.skillFor(quality, ilvl)
    if type(ilvl) ~= "number" or ilvl < 1 or not BY_CLASS[4][quality] then return nil end
    for _, s in ipairs(SKILL) do
        if ilvl <= s[1] then return s[2] end
    end
    return SKILL[#SKILL][2]
end

-- Expected copper per disenchant at the given mat prices; nil when a possible mat has no price.
function DE.value(outcomes, priceOf)
    if type(outcomes) ~= "table" or #outcomes == 0 or type(priceOf) ~= "function" then return nil end
    local total = 0
    for _, o in ipairs(outcomes) do
        if o.chance > 0 then
            local ok, p = pcall(priceOf, o.id)
            if not (ok and type(p) == "number" and p > 0) then return nil end
            total = total + o.chance * o.avg * p
        end
    end
    return math.floor(total + 0.5)
end

-- One pass for both values (audit step 3): the plain value (as DE.value) and the value with each mat's price x weightOf(id)
-- (its chance of selling), floored at 1e-6 so a 0% mat does not read as "no price". nil when a possible mat has no price.
function DE.valueEV(outcomes, priceOf, weightOf)
    if type(outcomes) ~= "table" or #outcomes == 0 or type(priceOf) ~= "function" then return nil end
    local total, ev = 0, 0
    for _, o in ipairs(outcomes) do
        if o.chance > 0 then
            local ok, p = pcall(priceOf, o.id)
            if not (ok and type(p) == "number" and p > 0) then return nil end
            local w = 1
            if type(weightOf) == "function" then
                local okw, v = pcall(weightOf, o.id)
                if okw and type(v) == "number" then w = v end
            end
            total = total + o.chance * o.avg * p
            ev = ev + o.chance * o.avg * math.max(p * w, 1e-6)
        end
    end
    return math.floor(total + 0.5), math.floor(ev + 0.5)
end

-- THE disenchant maths (deals rework 2026-11-21): the Deals panel, Live lots and the AH rows all value a disenchant here, so the
-- three can never disagree. src = { price(id) -> copper, age; days(id) -> scan days of that mat (optional); memo (optional table) }.
-- Returns nil outside the table (or not armor/weapon green-epic), else { de (per unit after the AH cut, nil when a possible mat
-- has no price), raw, outcomes, source, age (oldest mat price, scan days), days (thinnest mat history; only with src.days),
-- need (Enchanting skill this item level needs) }. The memo is per bracket (q:class:lo): every item of a bracket has the same
-- outcomes and mats, so a pass prices each mat once; `need` is per item level and never memoised.
function DE.unitValue(quality, classID, ilvl, src)
    src = src or {}
    local lo = DE.bracket(quality, classID, ilvl)
    if not lo then return nil end
    local memo = type(src.memo) == "table" and src.memo or nil
    local k = quality .. ":" .. classID .. ":" .. lo
    local m = memo and memo[k]
    if not m or (src.days and not m.hasDays) then
        local outcomes, source = DE.outcomes(quality, classID, ilvl)
        if not outcomes then return nil end
        local age, days = 0, nil
        local raw = DE.value(outcomes, function(id)
            local p, a = src.price(id)
            if type(p) == "number" and type(a) == "number" and a > age then age = a end
            if src.days then
                local okD, d = pcall(src.days, id)
                if not okD or type(d) ~= "number" then d = 0 end
                if not days or d < days then days = d end
            end
            return p
        end)
        m = { de = P.Reco.net(raw), raw = raw, outcomes = outcomes, source = source, age = age, days = days, hasDays = src.days ~= nil }
        if memo then memo[k] = m end
    end
    return { de = m.de, raw = m.raw, outcomes = m.outcomes, source = m.source, age = m.age, days = m.days,
        need = DE.skillFor(quality, ilvl) }
end
