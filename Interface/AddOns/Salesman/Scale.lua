local _, S = ...
S.Scale = { MIN = 0.7, MAX = 1.5, STEP = 0.1 }

function S.Scale.clamp(v)
    if type(v) ~= "number" or v ~= v then return 1 end
    return math.min(S.Scale.MAX, math.max(S.Scale.MIN, v))
end

-- One step up (dir = 1) or down (dir = -1), rounded to one decimal so repeated steps do not drift.
function S.Scale.step(v, dir)
    v = S.Scale.clamp(v)
    local n = math.floor((v + dir * S.Scale.STEP) * 10 + 0.5) / 10
    return S.Scale.clamp(n)
end

function S.Scale.label(v)
    return string.format("%d%%", math.floor(S.Scale.clamp(v) * 100 + 0.5))
end
