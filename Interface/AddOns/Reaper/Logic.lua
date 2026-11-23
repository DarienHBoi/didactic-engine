-- Reaper logic: pure functions, no frames and no client calls (all tested in reaper_tests/logic_test.lua).
-- Rule for everything in here: a value from the client may be a SECRET (issecretvalue). Never compare it or do
-- arithmetic on it; check issecretvalue first and treat it as unknown.
local _, R = ...
local L = {}
R.Logic = L

L.CAP = 25            -- most hits one learned average remembers (older hits fade), keeps saved data small
L.MAX_LEAD = 2        -- seconds
L.DEFAULT_LEAD = 0.6  -- reaction time plus one global cooldown
L.RATE_WINDOW = 3     -- seconds of damage taken that make the rate
L.HIT_WINDOW = 1.0    -- seconds after the cast succeeds in which its damage hit is looked for
L.SCHOOL_SHADOW = 32
L.ICON_MIN, L.ICON_MAX, L.DEFAULT_ICON = 12, 28, 17  -- SW:D icon on the plate, pixels
L.GCD = 1.5           -- a cooldown this short is the global cooldown, not SW:D's own

-- Class table. Add a class here to support it. mode "spell": a spell with ranks whose damage is learned.
-- mode "percent": a health percentage (Execute, Hammer of Wrath), not active yet.
L.CLASSES = {
    PRIEST = { active = true, name = "Priest", spell = "Shadow Word: Death", tag = "SW:D", mode = "spell",
        -- Forever ids, rank 1 (level 32) to rank 4. NOT the TBC id 32379.
        ids = { 1309595, 1309633, 1309635, 1309636 } },
    WARRIOR = { active = false, name = "Warrior", spell = "Execute", tag = "EX", mode = "percent", pct = 0.20, ids = {} },
}

local KNOWN_IDS = {}
for _, entry in pairs(L.CLASSES) do
    for _, id in ipairs(entry.ids) do KNOWN_IDS[id] = true end
end

-- Secret and number helpers ------------------------------------------------------------------------------
function L.isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, r = pcall(issecretvalue, v)
    return (ok and r) and true or false
end

local function isNum(v)
    if L.isSecret(v) or type(v) ~= "number" then return false end
    return v == v and v ~= math.huge and v ~= -math.huge
end
L.isNum = isNum

local function isKey(v)
    return not L.isSecret(v) and (type(v) == "string" or type(v) == "number")
end

-- Classes -----------------------------------------------------------------------------------------------
function L.classEntry(classFile)
    if type(classFile) ~= "string" then return nil end
    local e = L.CLASSES[classFile]
    if e and e.active then return e end
    return nil
end

function L.rankOfSpell(entry, spellId)
    if not entry or not isNum(spellId) then return nil end
    for i, id in ipairs(entry.ids) do
        if id == spellId then return i end
    end
    return nil
end

-- Rank to use. Forever (seen in game 2026-11-21) can call a rank known whose description is still EMPTY, so:
-- the highest known rank that has an amount (learned hits or estimates[id]); else the highest known rank; else the
-- highest learned rank. Second result: true while the highest known rank has no amount yet (keep asking for it).
-- A lower rank's number puts the kill line lower than it could be: the safe side.
function L.pickSpell(entry, isKnown, db, estimates)
    if not entry then return nil, false end
    local function hasAmount(id)
        if L.learnedAvg(db, id) then return true end
        local e = type(estimates) == "table" and estimates[id]
        return isNum(e) and e > 0
    end
    local top, best
    for i = #entry.ids, 1, -1 do
        local id = entry.ids[i]
        local ok, known = pcall(isKnown, id)
        if ok and known and not L.isSecret(known) then
            top = top or id
            if hasAmount(id) then best = id; break end
        end
    end
    if top then return best or top, best ~= top end
    for i = #entry.ids, 1, -1 do
        if L.learnedAvg(db, entry.ids[i]) then return entry.ids[i], false end
    end
    return nil, false
end

-- Description estimate ------------------------------------------------------------------------------------
-- "inflicts 450 to 500 Shadow damage" -> 475. First range, else first number.
function L.parseDescription(text)
    if L.isSecret(text) or type(text) ~= "string" then return nil end
    text = text:gsub("(%d),(%d)", "%1%2")
    local a, b = text:match("(%d+)%s+to%s+(%d+)")
    if not a then a, b = text:match("(%d+)%s*%-%s*(%d+)") end
    if a then return (tonumber(a) + tonumber(b)) / 2 end
    local one = text:match("%d+")
    return one and tonumber(one) or nil
end

-- Saved data ----------------------------------------------------------------------------------------------
local function cleanEntry(e)
    if type(e) ~= "table" then return nil end
    local out = { n = 0, sum = 0, cn = 0, csum = 0 }
    for _, pair in ipairs({ { "n", "sum" }, { "cn", "csum" } }) do
        local n, sum = e[pair[1]], e[pair[2]]
        if isNum(n) and isNum(sum) and n > 0 and sum > 0 then
            n = math.floor(n)
            if n > L.CAP then sum = sum * L.CAP / n; n = L.CAP end
            if n > 0 then out[pair[1]], out[pair[2]] = n, sum end
        end
    end
    return out
end

-- An icon size from the user: whole pixels clamped to ICON_MIN..ICON_MAX, nil for anything else.
function L.clampIcon(v)
    if not isNum(v) then return nil end
    return math.max(L.ICON_MIN, math.min(L.ICON_MAX, math.floor(v + 0.5)))
end

local ALLOWED = { leadTime = true, plateIcon = true, buttonFlash = true, tick = true, iconSize = true, learned = true }

-- Makes the saved table well formed and bounded: known keys only, numbers in range, counts capped.
-- Old keys (alertMode, alert, size, sound, colors) are dropped: the centre text and colour options are gone.
function L.sanitize(db)
    if type(db) ~= "table" then db = {} end
    for k in pairs(db) do
        if not ALLOWED[k] then db[k] = nil end
    end
    if isNum(db.leadTime) then db.leadTime = math.max(0, math.min(L.MAX_LEAD, db.leadTime)) else db.leadTime = L.DEFAULT_LEAD end
    for _, k in ipairs({ "plateIcon", "buttonFlash", "tick" }) do
        if type(db[k]) ~= "boolean" then db[k] = true end
    end
    db.iconSize = L.clampIcon(db.iconSize) or L.DEFAULT_ICON
    if type(db.learned) ~= "table" then db.learned = {} end
    for k, v in pairs(db.learned) do
        local e = KNOWN_IDS[k] and cleanEntry(v)
        db.learned[k] = e or nil
    end
    return db
end

function L.newDB() return L.sanitize({}) end

-- Learning ------------------------------------------------------------------------------------------------
-- Records one SW:D hit for a spell id. Crits are kept apart. Returns true if it was stored.
function L.learn(db, spellId, amount, isCrit)
    if type(db) ~= "table" or not KNOWN_IDS[spellId] or not isNum(amount) or amount <= 0 then return false end
    db.learned = db.learned or {}
    local e = db.learned[spellId]
    if not e then
        e = { n = 0, sum = 0, cn = 0, csum = 0 }
        db.learned[spellId] = e
    end
    local nk, sk = "n", "sum"
    if isCrit then nk, sk = "cn", "csum" end
    e[nk], e[sk] = (e[nk] or 0) + 1, (e[sk] or 0) + amount
    if e[nk] > L.CAP then
        e[sk] = e[sk] * L.CAP / e[nk]
        e[nk] = L.CAP
    end
    return true
end

local function avgOf(db, spellId, nk, sk)
    local e = type(db) == "table" and type(db.learned) == "table" and db.learned[spellId]
    if type(e) ~= "table" or not isNum(e[nk]) or e[nk] <= 0 or not isNum(e[sk]) then return nil end
    return e[sk] / e[nk]
end

function L.learnedAvg(db, spellId) return avgOf(db, spellId, "n", "sum") end
function L.learnedCritAvg(db, spellId) return avgOf(db, spellId, "cn", "csum") end

function L.learnedN(db, spellId)
    local e = type(db) == "table" and type(db.learned) == "table" and db.learned[spellId]
    return type(e) == "table" and isNum(e.n) and e.n or 0
end

-- Is a hit of this size plausibly the spell (and not a DoT tick that landed between cast and hit)?
function L.plausible(amount, reference)
    if not isNum(reference) or reference <= 0 then return true end
    return amount >= 0.5 * reference and amount <= 2.2 * reference
end

-- Expected SW:D damage: the learned average, else the description estimate, else nil.
function L.expectedSwd(db, spellId, estimate)
    if not spellId then return nil end
    local avg = L.learnedAvg(db, spellId)
    if avg then return avg end
    if isNum(estimate) and estimate > 0 then return estimate end
    return nil
end

-- Hit learner: UNIT_SPELLCAST_SUCCEEDED (onCast), then the next shadow WOUND on the target (onCombat) -------
local Learner = {}
Learner.__index = Learner

function L.newLearner(db, entry, estimateFn)
    return setmetatable({ db = db, entry = entry, estimateFn = estimateFn }, Learner)
end

function Learner:onCast(spellId, now)
    if not L.rankOfSpell(self.entry, spellId) or not isNum(now) then return false end
    self.pending = { id = spellId, t = now }
    return true
end

-- isTarget: the unit the hit landed on is the player's target. Returns true if a hit was stored.
function Learner:onCombat(isTarget, action, flag, amount, school, now)
    local p = self.pending
    if not p or not isTarget or not isNum(now) then return false end
    if L.isSecret(action) or action ~= "WOUND" then return false end
    if now - p.t > L.HIT_WINDOW then self.pending = nil; return false end
    if not isNum(amount) or amount <= 0 then return false end
    if not isNum(school) or school ~= L.SCHOOL_SHADOW then return false end
    local ref = L.learnedAvg(self.db, p.id)
    if not ref and self.estimateFn then
        local ok, est = pcall(self.estimateFn, p.id)
        if ok then ref = est end
    end
    if not L.plausible(amount, ref) then return false end
    local crit = not L.isSecret(flag) and flag == "CRITICAL"
    self.pending = nil
    return L.learn(self.db, p.id, amount, crit)
end

-- Damage-taken rate: sum of UNIT_COMBAT damage on a mob over a sliding window, per second ----------------------
local Rate = {}
Rate.__index = Rate

function L.newRate(window, maxEvents, maxKeys)
    return setmetatable({ window = window or L.RATE_WINDOW, maxEvents = maxEvents or 64, maxKeys = maxKeys or 64,
        events = {}, touch = {}, tick = 0, keys = 0 }, Rate)
end

function Rate:forget(key)
    if self.events[key] then
        self.events[key], self.touch[key] = nil, nil
        self.keys = self.keys - 1
    end
end

function Rate:add(key, t, amount, unit)
    if not isKey(key) or not isNum(t) or not isNum(amount) or amount <= 0 then return false end
    local ev = self.events[key]
    if not ev then
        if self.keys >= self.maxKeys then
            local oldest, oldestTouch
            for k, touch in pairs(self.touch) do
                if not oldestTouch or touch < oldestTouch then oldest, oldestTouch = k, touch end
            end
            if oldest ~= nil then self:forget(oldest) end
        end
        ev = {}
        self.events[key] = ev
        self.keys = self.keys + 1
    end
    -- One hit fires UNIT_COMBAT for target, nameplateN, ...: the same amount at the same instant from another token is it.
    local last = ev[#ev]
    if last and unit ~= nil and last.unit ~= nil and last.t == t and last.amount == amount and last.unit ~= unit then
        return false
    end
    self.tick = self.tick + 1
    self.touch[key] = self.tick
    ev[#ev + 1] = { t = t, amount = amount, unit = unit }
    while #ev > 0 and ev[1].t < t - self.window do table.remove(ev, 1) end
    while #ev > self.maxEvents do table.remove(ev, 1) end
    return true
end

function Rate:rate(key, now)
    if not isKey(key) or not isNum(now) then return 0 end
    local ev = self.events[key]
    if not ev then return 0 end
    local sum, from = 0, now - self.window
    for _, e in ipairs(ev) do
        if e.t > from and e.t <= now then sum = sum + e.amount end
    end
    return sum / self.window
end

-- Amounts ---------------------------------------------------------------------------------------------------
L.SOON = 2      -- seconds: the dim "soon" icon shows when SW:D comes into range within this
L.FINISH = 1.5  -- seconds (one GCD): when your DoTs kill it within this, SW:D is not worth pressing

-- DoT damage landing within t seconds from now. dots = DoesItDie.GetDoTs entries { damage (remaining), expiresAt }.
-- DoesItDie's API gives no tick times, so each DoT's remaining damage is spread evenly up to its expiry.
function L.dotDue(dots, now, t)
    if type(dots) ~= "table" or not isNum(now) or not isNum(t) or t <= 0 then return 0 end
    local sum = 0
    for _, d in ipairs(dots) do
        if type(d) == "table" and isNum(d.damage) and d.damage > 0 and isNum(d.expiresAt) then
            local left = d.expiresAt - now
            if left <= t then sum = sum + d.damage else sum = sum + d.damage * t / left end
        end
    end
    return sum
end

-- swd: expected SW:D damage; dots: DoesItDie.GetDoTs list (nil when absent); now: GetTime(); rate: damage taken per
-- second (all sources, DoT ticks included); lead: seconds until SW:D lands (reaction; the spell is instant).
-- Returns kill, soon, finish (nil without a SW:D amount). Each is a health amount, compared by the widgets:
--   kill   = health at or below which a cast now kills (DoT damage landing before it counts, later DoTs don't)
--   soon   = health at or below which it kills within L.SOON s (DoT projection or damage rate, the larger)
--   finish = health at or below which your DoTs alone kill it within L.FINISH s (then the icon stays off)
function L.amounts(swd, dots, now, rate, lead)
    if not isNum(swd) or swd <= 0 then return nil, nil, nil end
    local r = (isNum(rate) and rate > 0) and rate or 0
    local l = (isNum(lead) and lead >= 0) and lead or L.DEFAULT_LEAD
    local kill = swd + L.dotDue(dots, now, l)
    local soon = swd + math.max(L.dotDue(dots, now, L.SOON), r * L.SOON)
    return kill, math.max(kill, soon), L.dotDue(dots, now, L.FINISH)
end

-- DoesItDie.GetDoTs(unit), guarded. nil when DoesItDie is absent, broken or answers nonsense.
function L.dotsOf(api, unit)
    if type(api) ~= "table" or type(api.GetDoTs) ~= "function" then return nil end
    local ok, list = pcall(api.GetDoTs, unit)
    if ok and type(list) == "table" then return list end
    return nil
end

-- Usable gate ---------------------------------------------------------------------------------------------------
-- info = { usable, inRange, cdStart, cdDuration, onGCD, now } straight from the client (any may be nil or secret).
-- False only on a definite plain "no": not usable (no mana, not known), out of range, or on its own cooldown.
-- Anything unknown or secret keeps the signal (better a signal you cannot press than none when you can).
function L.usable(info)
    if type(info) ~= "table" then return true end
    if not L.isSecret(info.usable) and info.usable == false then return false end
    if not L.isSecret(info.inRange) and info.inRange == false then return false end
    local start, dur, t = info.cdStart, info.cdDuration, info.now
    if isNum(start) and isNum(dur) and isNum(t) and dur > L.GCD and start > 0 then
        local gcdOnly = not L.isSecret(info.onGCD) and info.onGCD == true
        if not gcdOnly and start + dur > t then return false end
    end
    return true
end
