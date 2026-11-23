-- Pure logic for AscendXP_Tweaks (no game API): sizes, colours, offsets and the per-element settings.
local _, A = ...

local JUSTIFY = { LEFT = true, CENTER = true, RIGHT = true }

-- Group scale: 0.5x to 3x in steps of 0.05.
function A.clampScale(v)
    if type(v) ~= "number" or v ~= v then return nil end
    v = math.floor(v * 20 + 0.5) / 20
    return math.max(0.5, math.min(3, v))
end

-- "ff8000" or "#FF8000" -> r, g, b in 0..1; nil when it is not six hex digits.
function A.parseHex(s)
    if type(s) ~= "string" then return nil end
    local h = s:gsub("^#", "")
    if #h ~= 6 or h:find("%X") then return nil end
    return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end

function A.toHex(r, g, b)
    local function c(v) return string.format("%02x", math.floor(math.max(0, math.min(1, v or 0)) * 255 + 0.5)) end
    return c(r) .. c(g) .. c(b)
end

function A.keyOf(frameName, ordinal) return frameName .. ":" .. ordinal end

-- A short readable label for a text element: colour codes removed, long text cut.
function A.describe(text)
    if type(text) ~= "string" then return "(empty)" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if text == "" then return "(empty)" end
    if #text > 24 then return text:sub(1, 24) .. "..." end
    return text
end

-- A drag measured in screen units becomes an offset in the text's own frame, whose scale may differ.
function A.screenToFrame(dxScreen, dyScreen, uiScale, frameScale)
    local k = uiScale / frameScale
    return dxScreen * k, dyScreen * k
end

-- One group's saved settings. Fields: dx, dy (offset), hidden, justify, scale, r/g/b.
function A.cfg(db, key)
    db.elements = db.elements or {}
    local c = db.elements[key]
    if not c then c = { dx = 0, dy = 0, hidden = false }; db.elements[key] = c end
    return c
end

function A.isDefault(c)
    return c.dx == 0 and c.dy == 0 and not c.hidden and c.justify == nil and (c.scale == nil or c.scale == 1) and c.r == nil
end

function A.reset(db, key)
    if db.elements then db.elements[key] = nil end
end

function A.setJustify(c, j)
    if not JUSTIFY[j] then return false end
    c.justify = j
    return true
end

function A.setScale(c, v)
    local s = A.clampScale(v)
    if not s then return false end
    c.scale = s
    return true
end

function A.setColor(c, hex)
    local r, g, b = A.parseHex(hex)
    if not r then return false end
    c.r, c.g, c.b = r, g, b
    return true
end

-- Groups: texts in the same column of the same frame (a label and its value) are one group.
-- items = { {root=, x=}, ... } -> list of groups, each a list of item indices; frames in order of first appearance, columns left to right.
function A.groupByColumn(items, tol)
    local order, byRoot = {}, {}
    for i, it in ipairs(items) do
        if not byRoot[it.root] then byRoot[it.root] = {}; order[#order + 1] = it.root end
        local list = byRoot[it.root]
        list[#list + 1] = i
    end
    local groups = {}
    for _, root in ipairs(order) do
        local list = byRoot[root]
        table.sort(list, function(a, b)
            if items[a].x ~= items[b].x then return items[a].x < items[b].x end
            return a < b
        end)
        local cur, startX
        for _, i in ipairs(list) do
            if not cur or items[i].x - startX > tol then
                cur, startX = {}, items[i].x
                groups[#groups + 1] = cur
            end
            cur[#cur + 1] = i
        end
    end
    return groups
end

-- Where a member's anchor goes: the group's offset, plus its distance from the group's first text grown by the scale.
function A.groupOffset(c, px, py, ox, oy)
    local k = (c.scale or 1) - 1
    return (c.dx or 0) + (px - ox) * k, (c.dy or 0) + (py - oy) * k
end

function A.scaledSize(c, base) return base * (c.scale or 1) end

-- Snap to the top of the screen: the gap in pixels below the edge (negative moves the bar above the edge, so its art sits flush).
function A.clampGap(v)
    if type(v) ~= "number" or v ~= v then return nil end
    return math.max(-40, math.min(60, math.floor(v + 0.5)))
end

-- snap = { on, x, gap }. Turning it on remembers where the bar sits left to right; the gap starts flush.
function A.setSnap(snap, on, x)
    if type(snap) ~= "table" then return false end
    snap.on = on and true or false
    if on then
        if type(x) == "number" then snap.x = x end
        snap.gap = snap.gap or 0
    end
    return true
end

function A.nudgeGap(snap, delta)
    if type(snap) ~= "table" then return false end
    local g = A.clampGap((snap.gap or 0) + (delta or 0))
    if not g then return false end
    snap.gap = g
    return true
end

-- Offsets for a TOP anchor on the screen's top edge; nil when snapping is off.
function A.snapOffset(snap)
    if not (snap and snap.on) then return nil end
    return snap.x or 0, -(snap.gap or 0)
end

-- Left/right position of the snapped bar, in pixels from the screen's centre.
function A.nudgeX(snap, delta)
    if type(snap) ~= "table" or type(delta) ~= "number" then return false end
    snap.x = math.max(-3000, math.min(3000, (snap.x or 0) + delta))
    return true
end

function A.stepFor(shift) return shift and 10 or 1 end
