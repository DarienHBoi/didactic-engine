local _, P = ...
P.Rate = {}
local R = P.Rate

-- The personal sale rate (from Salesman's mail log): sold / (sold + expired + cancelled) over 30 days.
-- o = { sold, expired, cancelled, units14 } as SalesmanAPI.outcomes returns it. Same cutoffs as Salesman's Best crafts.
R.MIN, R.GOOD, R.OK = 5, 0.30, 0.10

-- rate (0 to 1) and the outcome count; rate is nil when there are fewer than MIN outcomes or the table is not numbers.
function R.of(o)
    if type(o) ~= "table" then return nil, 0 end
    local sold, expired, cancelled = tonumber(o.sold), tonumber(o.expired) or 0, tonumber(o.cancelled) or 0
    if not sold then return nil, 0 end
    local total = sold + expired + cancelled
    if total < R.MIN then return nil, total end
    return sold / total, total
end

-- "green" from 30%, "yellow" from 10%, else "grey" (also for an unknown rate).
function R.tone(rate)
    if type(rate) ~= "number" then return "grey" end
    if rate >= R.GOOD - 1e-9 then return "green" end
    if rate >= R.OK - 1e-9 then return "yellow" end
    return "grey"
end

function R.text(rate)
    if type(rate) ~= "number" then return "-" end
    return math.floor(rate * 100 + 0.5) .. "%"
end

-- Units sold per day over the last 14 days.
function R.perDay(o)
    if type(o) ~= "table" then return 0 end
    return (tonumber(o.units14) or 0) / 14
end

function R.tip(o)
    if type(o) ~= "table" then return "No sales or expiries logged in the last 30 days (open your mailbox to log them)." end
    return ("%d sold, %d expired, %d cancelled (30 days), %s/day"):format(tonumber(o.sold) or 0, tonumber(o.expired) or 0,
        tonumber(o.cancelled) or 0, tostring(math.floor(R.perDay(o) * 10 + 0.5) / 10))
end

-- RGB for a tone name (green = good, yellow = middling, grey = low or unknown).
R.COLOURS = { green = { 0.25, 1, 0.25 }, yellow = { 1, 0.82, 0.25 }, grey = { 0.6, 0.6, 0.6 } }
