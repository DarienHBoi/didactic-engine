-- Ring the Bell: pure record logic (no client calls).
local addonName, RB = ...
local L = {}
RB.L = L

L.HISTORY_CAP = 50

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

-- class token (^[A-Z]+$, <= 20) and fight seconds (integer 1..86400); anything else is nil
function L.validClass(c)
    if type(c) == "string" and not L.isSecret(c) and #c <= 20 and c:match("^[A-Z]+$") then return c end
    return nil
end

function L.validSecs(s)
    if isNum(s) and s == math.floor(s) and s >= 1 and s <= 86400 then return s end
    return nil
end

function L.classColor(class)
    local ok, c = pcall(function() return RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] end)
    if ok and type(c) == "table" then
        local rr, gg, bb = c.r, c.g, c.b
        if isNum(rr) and isNum(gg) and isNum(bb) then return rr, gg, bb end
    end
    return 1, 0.82, 0
end

function L.newId(player, t, amount)
    return string.format("%s:%d:%d", tostring(player), math.floor(t or 0), math.floor(amount or 0))
end

function L.beats(a, b)
    if b == nil then return true end
    if a.amount ~= b.amount then return a.amount > b.amount end
    return (a.t or 0) < (b.t or 0)
end

-- best record per player (key = lowercase name without realm), so the leaderboard outlives the 50-entry history
local function bestKey(player) return (player:match("^([^-]*)") or player):lower() end

local function noteBest(db, rec)
    db.best = db.best or {}
    local k = bestKey(rec.player)
    if k == "" then return false end
    if L.beats(rec, db.best[k]) then db.best[k] = rec; return true end
    return false
end

function L.leaderboard(db)
    local out = {}
    for _, r in pairs((db and db.best) or {}) do out[#out + 1] = r end
    table.sort(out, function(a, b) return L.beats(a, b) end)
    return out
end

function L.merge(db, rec)
    local changed = noteBest(db, rec)
    if L.beats(rec, db.record) then db.record = rec; changed = true end
    db.history = db.history or {}
    for _, h in ipairs(db.history) do
        if h.id == rec.id then return changed end
    end
    local pos = #db.history + 1  -- newest first by t; ties keep the existing entry ahead
    for i, h in ipairs(db.history) do
        if (h.t or 0) < (rec.t or 0) then pos = i break end
    end
    table.insert(db.history, pos, rec)
    while #db.history > L.HISTORY_CAP do table.remove(db.history) end
    return true
end

local function validRec(r)
    if type(r) == "table" and isNum(r.amount) and type(r.player) == "string" then
        r.class, r.secs = L.validClass(r.class), L.validSecs(r.secs)
        return true
    end
    return false
end

function L.sanitize(db)
    if type(db) ~= "table" then db = {} end
    if not validRec(db.record) then db.record = nil end
    local hist = {}
    if type(db.history) == "table" then
        for _, h in ipairs(db.history) do
            if validRec(h) then hist[#hist + 1] = h end
        end
    end
    db.history = hist
    local best = {}
    if type(db.best) == "table" then
        for _, r in pairs(db.best) do
            if validRec(r) then
                local k = bestKey(r.player)
                if k ~= "" and L.beats(r, best[k]) then best[k] = r end
            end
        end
    end
    db.best = best
    if db.record then noteBest(db, db.record) end
    for _, h in ipairs(hist) do noteBest(db, h) end
    if type(db.options) ~= "table" then db.options = {} end
    local o = db.options
    if o.sound == nil then o.sound = true end
    if o.popup == nil then o.popup = true end
    if o.pip == nil then o.pip = true end
    if type(o.friends) ~= "table" then o.friends = {} end
    if type(db.pip) ~= "table" then db.pip = {} end
    if db.pip.angle == nil then db.pip.angle = 200 end
    if type(db.popup) ~= "table" then db.popup = {} end
    return db
end

local function cap(s) return (s:sub(1, 1):upper() .. s:sub(2):lower()) end

function L.normName(name, myRealm)
    if type(name) ~= "string" then return nil end
    name = name:gsub("%-$", "")
    if name == "" then return nil end
    local n, r = name:match("^([^-]+)-(.+)$")
    if not n then
        if name:sub(1, 1) == "-" then return nil end
        n, r = name, myRealm
    end
    r = tostring(r or ""):gsub("%s", "")
    return cap(n) .. "-" .. r
end

-- Same character? Names must match; realms only count when both are known (Forever can report an empty realm).
function L.sameName(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    local an, ar = a:lower():match("^([^-]*)%-?(.*)$")
    local bn, br = b:lower():match("^([^-]*)%-?(.*)$")
    if not an or an == "" or an ~= bn then return false end
    return ar == "" or br == "" or ar == br
end

-- "Hoops-" (unknown realm) shows as "Hoops"; a real realm stays.
function L.displayName(name)
    if type(name) ~= "string" then return "" end
    return (name:gsub("%-$", ""))
end

function L.versionNewer(a, b)
    local function parse(v)
        if type(v) ~= "string" then return nil end
        local t = {}
        for part in (v .. "."):gmatch("([^.]*)%.") do
            if not part:match("^%d+$") then return nil end
            t[#t + 1] = tonumber(part)
        end
        return t
    end
    local pa, pb = parse(a), parse(b)
    if not pa or not pb then return false end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end
