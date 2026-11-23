-- Distances in yards between map points, through the client's own map-to-world conversion.
local _, ns = ...

local Geo = {}
ns.Geo = Geo

--- world position of a point given in percent on a ui map: continent, x, y (nil when the map can't say)
function Geo.World(map, x, y)
  if not (map and x and y and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
  if not ok or not pos then return nil end
  local wx, wy = ns.clean(pos.x), ns.clean(pos.y)
  if not (wx and wy) then return nil end
  return continent, wx, wy
end

--- a { map, x, y } point on another ui map, in percent ({ map, x, y }), or nil when it lies outside that map
--- (Nov 7: Stormwind's flight master is written on Elwynn Forest's map, and the trip asks if it's in the city)
function Geo.OnMap(p, map)
  if not (p and map and C_Map.GetMapPosFromWorldPos) then return nil end
  if p[1] == map then return p end
  local c, wx, wy = Geo.World(p[1], p[2], p[3])
  if not c or Geo.World(map, 50, 50) ~= c then return nil end   -- (another continent's map: never)
  local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, c, CreateVector2D(wx, wy), map)
  local x, y = ok and pos and ns.clean(pos.x), ok and pos and ns.clean(pos.y)
  if not (x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return { map, x * 100, y * 100 }
end

--- yards between two { map, x, y } points; nil if either can't be placed or they're on different continents
function Geo.Between(a, b)
  if not (a and b) then return nil end
  local c1, ax, ay = Geo.World(a[1], a[2], a[3])
  local c2, bx, by = Geo.World(b[1], b[2], b[3])
  if not (c1 and c2) or c1 ~= c2 then return nil end
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

--- yards from the player (ns.st.pos) to a { map, x, y } point; nil if either isn't known or they're on different continents
function Geo.YardsTo(p)
  local pos = ns.st.pos
  if not (p and pos and pos.x) then return nil end
  local c1, ax, ay = Geo.World(pos.map, pos.x, pos.y)
  local c2, bx, by = Geo.World(p[1], p[2], p[3])
  if not (c1 and c2) or c1 ~= c2 then return nil end
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

--- yards from the player to the line between two { map, x, y } points (the nearest point on it); nil if not known
function Geo.YardsToLine(a, b)
  local pos = ns.st.pos
  if not (a and b and pos and pos.x) then return nil end
  local c0, px, py = Geo.World(pos.map, pos.x, pos.y)
  local c1, ax, ay = Geo.World(a[1], a[2], a[3])
  local c2, bx, by = Geo.World(b[1], b[2], b[3])
  if not (c0 and c1 and c2) or c0 ~= c1 or c1 ~= c2 then return nil end
  local dx, dy = bx - ax, by - ay
  local len2 = dx * dx + dy * dy
  local t = len2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
  return math.sqrt((px - ax - t * dx) ^ 2 + (py - ay - t * dy) ^ 2)
end
