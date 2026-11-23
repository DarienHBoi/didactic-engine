local _, P = ...
P.Days = {}
local D = P.Days
local FALLBACK_ZERO = 1577836800 -- 2020-01-01 00:00 UTC, used when the client cannot build it

-- Auctionator's scan day 0 is local midnight 2020-01-01 (verified in Auctionator Constants/Main.lua).
local e0cache
function D.epoch0()
    if e0cache then return e0cache end
    local value = FALLBACK_ZERO
    if type(time) == "function" then
        local ok, t = pcall(time, { year = 2020, month = 1, day = 1, hour = 0 })
        if ok and type(t) == "number" then value = t end
    end
    e0cache = value
    return value
end

function D.dayOf(t, e0)
    if type(t) ~= "number" or t ~= t then return nil end
    return math.floor((t - (e0 or D.epoch0())) / 86400)
end

function D.tsOf(day, e0) return (e0 or D.epoch0()) + day * 86400 end

-- "03 Nov"; dateFn is the client's date(), injectable for tests.
function D.label(day, e0, dateFn)
    local f = dateFn or date
    local ok, s = pcall(f, "%d %b", D.tsOf(day, e0))
    return ok and s or tostring(day)
end
