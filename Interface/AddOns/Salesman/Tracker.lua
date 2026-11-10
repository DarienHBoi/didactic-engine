local _, S = ...
S.Tracker = {}
local cur = nil

function S.Tracker.reset() cur = nil end

-- A trade window opened with partner (nil when the name could not be read, so nothing will be counted).
function S.Tracker.open(partner)
    cur = type(partner) == "string" and partner ~= "" and { partner = partner, gold = 0 } or nil
end

-- Gold the partner currently offers (copper).
function S.Tracker.setGold(copper)
    if cur and type(copper) == "number" and copper == copper and copper >= 0 then cur.gold = copper end
end

function S.Tracker.close() cur = nil end

-- Call when the client reports the trade went through. Returns the ledger result, or nil when no trade was open.
function S.Tracker.complete(db, now)
    if not cur then return nil end
    local t = cur
    cur = nil
    return S.Ledger.recordTrade(db, t.partner, t.gold, now)
end
