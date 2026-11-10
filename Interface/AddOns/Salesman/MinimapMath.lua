local _, S = ...
S.MinimapMath = {}

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end

-- Offset from the minimap centre for a button at angle (degrees, 0 = right, 90 = up).
function S.MinimapMath.position(angleDeg, radius)
    local a = math.rad(angleDeg)
    return math.cos(a) * radius, math.sin(a) * radius
end

-- Angle in degrees (0..360) from the centre (cx, cy) to the cursor (mx, my).
function S.MinimapMath.angleFromCursor(cx, cy, mx, my)
    local deg = math.deg(atan2(my - cy, mx - cx))
    if deg < 0 then deg = deg + 360 end
    return deg
end
