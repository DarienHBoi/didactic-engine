-- Bind on Forever Guide: getting to another start's road across the sea (Batch 3 of the RestedXP audit, Oct 19).
-- After you pick a road from "Another start's road", the guide looks where you are and where the road's next stop is.
-- When they're in different lands (Teldrassil and Stormwind, Durotar and Tirisfal), it plans the ways between them from
-- the pack's travel data (guides/travel.yaml: the Darnassus portal, the Rut'theran and Stormwind Harbor boats, the
-- Deeprun Tram, the zeppelins) and shows one way at a time on the window, the arrow along its points. Once you stand
-- in the road's land, the road takes over.
-- Nov 6, the owner in Darkshore opened the Hall of Thanes guide and got one arrow 3,188 yards across the sea to Dun
-- Morogh, no boat, no tram: the trip now runs by itself for every dungeon, profession and Legacy guide whose next stop
-- is in another land, and for a leveling road you've wandered away from (its last stop done is in another land than
-- you). It never runs while the road's own crossing is under way (you stand where its last stop was) or its hearth
-- is next.
local _, ns = ...
local Travel = {}
ns.Travel = Travel

local REACHED = 25   -- yards: a way's point you're this close to is behind you

local function data(route)
  if route and route.pack and route.pack.travel then return route.pack.travel end
  local r = ns.Engine.Leveling()
  if r and r.pack and r.pack.travel then return r.pack.travel end
  -- (a paid road's pack carries none: its faction's free pack does. Nov 9: on the 30-60 roads no trip card showed and
  -- no rule could tell one land from another)
  local f = (route and route.faction) or (r and r.faction)
  for _, id in ipairs(ns.Packs.order or {}) do
    local x = ns.Packs.routes[id]
    if x and x.pack and x.pack.travel and (not f or x.faction == f) then return x.pack.travel end
  end
end

local function inBox(def, map, x, y)
  if def.map ~= map then return false end
  if not def.box then return true end
  local b = def.box
  local inside = x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4]
  if def.outside then return not inside end
  return inside
end

--- the land of a flight master's spot, read on each land's own map when the spot is written on another (Stormwind's
--- flight master is on Elwynn Forest's map, inside the city's walls; Nov 7)
function Travel.SpotLand(t, p)
  if not (t and p) then return nil end
  for _, name in ipairs(t.order or {}) do
    for _, def in ipairs(t.lands[name] or {}) do
      -- (a land drawn on the spot's own map counts in its turn: Ironforge's flight master, on Ironforge's map, came
      -- out as Dun Morogh's from Dun Morogh's map further down the list, so no flight left from Ironforge; Nov 7)
      if def.map == p[1] and inBox(def, p[1], p[2], p[3]) then return name end
      -- (read on another map only for a city or a corner of a map: a whole zone's map rectangle overlaps its
      -- neighbours, and Thorium Point in Searing Gorge read as Loch Modan's; the dungeon walk, Nov 7)
      if def.map and def.map ~= p[1] and (def.box or (t.parts and t.parts[name])) and ns.Geo and ns.Geo.OnMap then
        local q = ns.Geo.OnMap(p, def.map)
        if q and inBox(def, q[1], q[2], q[3]) then return name end
      end
    end
  end
  return Travel.Land(t, p[1], p[2], p[3])
end

--- the land a spot is in (travel.yaml: the first that fits), or nil
function Travel.Land(t, map, x, y)
  if not (t and map and x) then return nil end
  local cont = ns.Geo and ns.Geo.World(map, x, y)
  for _, name in ipairs(t.order or {}) do
    for _, def in ipairs(t.lands[name] or {}) do
      if def.continent and cont == def.continent then return name end
      if def.map and inBox(def, map, x, y) then return name end
    end
  end
  return nil
end

local function cheapest(t, from, to, level)
  local cost, prev, done = { [from] = 0 }, {}, {}
  while true do
    local land, best
    for l, c in pairs(cost) do if not done[l] and (not best or c < best) then land, best = l, c end end
    if not land then return nil end
    if land == to then
      local out, at = {}, to
      while at ~= from do local step = prev[at] table.insert(out, 1, step) at = step.from end
      return out
    end
    done[land] = true
    for _, w in ipairs(t.ways or {}) do
      if w.from == land and not done[w.to] and not (level and w.min_level and level < w.min_level) then
        local c = best + (w.cost or 1)
        if not cost[w.to] or c < cost[w.to] then cost[w.to], prev[w.to] = c, w end
      end
    end
  end
end

--- the ways from one land to another, cheapest first ({ way, way, ... }), or nil when none goes there. A way through
--- ground above your level (`min_level`) is left out while another way goes there
function Travel.Plan(t, from, to, level)
  if not (t and from and to) or from == to then return {} end
  return (level and cheapest(t, from, to, level)) or cheapest(t, from, to)
end

local function here()
  local map = ns.clean(C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player'))
  if not map then return nil end
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, 'player')
  local x, y = ok and pos and ns.clean(pos.x), ok and pos and ns.clean(pos.y)
  if not (x and y) then return nil end
  return map, x * 100, y * 100
end

--- where the road goes next: { map, x, y } of the step in front of you, or of the first after it with a spot; nil
--- when its own hearth comes first (it gets you there itself)
local function target(route, view)
  local pts = route and route.pack and route.pack.pts
  if not (pts and view and view.status) then return nil end
  for i = view.cursor or 1, #route.steps do
    local s = route.steps[i]
    if view.status[i] == 'pending' then
      if s.o == 'hearth' then return nil end
      if s.p and pts[s.p] then return pts[s.p] end
    end
  end
  return nil
end

--- a leveling road you've wandered from: you're on another continent than both its last stop done and its next stop
--- (a dungeon guide took you across the sea, and you're back on the road). A road's own walks between lands on one
--- continent (Durotar and the Barrens, Dun Morogh and Loch Modan) and its own crossings are its own: the checks of Nov 6
--- caught a land-by-land test sending an Orc on a trip between the Barrens and Orgrimmar mid-road
local FAR_FROM_ROAD, DETOUR_YARDS = 1200, 2000
local function goalKey(g) return g and ('%d:%.1f:%.1f'):format(g[1], g[2], g[3]) end

function Travel.Off(route, view)
  local pts = route and route.pack and route.pack.pts
  if not (pts and view and view.status and view.cursor and ns.Geo) then return false end
  local map, x, y = here()
  if not map then return false end
  local goal = target(route, view)
  if not goal then return false end
  -- a trip begun for this stop goes on to its land: landed in Ironforge, out by the gate, not through the wall (Nov 7)
  if ns.cdb and ns.cdb.roadTrip and ns.cdb.roadTrip == goalKey(goal) then
    local t = data(route)
    local from, to = t and Travel.Land(t, map, x, y), t and Travel.Land(t, goal[1], goal[2], goal[3])
    if from and to and from ~= to then return true end
    ns.cdb.roadTrip = nil
  end
  -- the road's own flight or hearth behind you, never taken, and the next stop far: you need the way there (Nov 9, the
  -- card holds still: the come-back rules did this by putting the flight back on the card, which flipped it as you
  -- walked; FB-046). Looked for back past steps done on an earlier visit far from you, up to one you did here
  local toGoal = ns.Geo.YardsTo(goal)
  if toGoal == nil or toGoal >= FAR_FROM_ROAD then
    for i = view.cursor - 1, 1, -1 do
      local s = route.steps[i]
      if view.status[i] ~= 'na' then
        local passedOnly = ns.cdb.passed and ns.cdb.passed[s.k] and not ns.cdb.done[s.k]
        if passedOnly and (s.o == 'fly' or s.o == 'hearth') then return true end
        if view.status[i] == 'done' and s.p and pts[s.p] and not passedOnly then
          local d = ns.Geo.YardsTo(pts[s.p])
          if d and d < FAR_FROM_ROAD then break end
        end
      end
    end
  end
  for i = view.cursor - 1, 1, -1 do
    local s = route.steps[i]
    -- (a walk, flight or hearth only passed behind you, not taken, says nothing of where you are)
    local passedOnly = ns.cdb.passed and ns.cdb.passed[s.k] and not ns.cdb.done[s.k]
    if view.status[i] == 'done' and s.p and pts[s.p] and not passedOnly then
      if s.o == 'hearth' or s.o == 'fly' then return false end
      local p = pts[s.p]
      local mine, lastC, goalC = ns.Geo.World(map, x, y), ns.Geo.World(p[1], p[2], p[3]), ns.Geo.World(goal[1], goal[2], goal[3])
      if mine ~= nil and lastC ~= nil and goalC ~= nil and mine ~= lastC and mine ~= goalC then return true end
      -- or far from the road on its own continent: the owner back in Ironforge from Hall of Thanes with Salma Saldean
      -- next, 5,666 yards on foot past a flight they knew (Nov 7). Off by DETOUR_YARDS more than the road's own leg
      -- from its last stop to the next, so the road's own walks between lands stay its own
      local toGoal, toLast, leg = ns.Geo.YardsTo(goal), ns.Geo.YardsTo(p), ns.Geo.Between(p, goal)
      return toGoal ~= nil and toLast ~= nil and leg ~= nil and toGoal >= FAR_FROM_ROAD
        and toGoal + toLast - leg >= DETOUR_YARDS
    end
  end
  return false
end

local last   -- the way shown last: kept while you're somewhere no land covers (on the tram, at sea)

--- the way to show now, or nil (no trip, or you're there): { way = w, point = {map, x, y}, to = target, left = n }.
--- `auto`: without a pick from the menu (a dungeon, profession or Legacy guide; a road you wandered from)
function Travel.Now(route, view, auto)
  if not ns.cdb then return nil end
  local picked = ns.cdb.travel
  if not (picked or auto) then last = nil return nil end
  local t = data(route)
  local goal = target(route, view)
  local map, x, y = here()
  if not (t and goal and map) then last = nil return nil end   -- (nothing on screen: Active says so too)
  -- a trip you skipped: the step's own card, until the step it leads to changes (Nov 8, FB-049: "i cant skip a step";
  -- a trip card had no skip, and /bofg skip skipped the quest behind it while the trip card stayed)
  if ns.cdb.tripSkip then
    if ns.cdb.tripSkip == goalKey(goal) then last = nil return nil end
    ns.cdb.tripSkip = nil
  end
  local from, to = Travel.Land(t, map, x, y), Travel.Land(t, goal[1], goal[2], goal[3])
  -- a guide's trip on one continent: a flight between flight paths you know, from the land you're in (Nov 7, the
  -- owner's Deadmines guide in Stormwind pointed through the wall to Westfall), before any walk out of a city
  -- a flight path close by that you don't know: learn it first, so the trips after can fly (Nov 7)
  if auto and route and route.kd and ns.Engine.NearbyFlightPath and not (ns.st and ns.st.inst) then
    local fp = ns.Engine.NearbyFlightPath(goal)
    if fp then
      last = { learn = fp, point = fp.point, to = goal, left = 1 }
      return last
    end
  end
  -- your leveling road's quest, its giver beside you (Nov 9, Guard Parker at Redridge's door): taken as you pass. On a
  -- guide that walks you along the road (a dungeon's errands, the Legacy guide), never a profession guide: there you
  -- picked fishing or a craft, not the road (Nov 10, the owner fishing in Lakeshire was sent for Solomon's Law)
  if auto and route and (route.kd == 'dungeon' or route.kd == 'legacy') and ns.Engine.PassByQuest
     and not (ns.st and ns.st.inst) then
    local pb = ns.Engine.PassByQuest()
    if pb then
      last = { pickup = pb, point = pb.point, to = goal, left = 1 }
      return last
    end
  end
  local parts = t.parts or {}
  if auto and route and from and ns.Engine.FlightLeg then   -- (a guide, or a road you wandered from)
    local function spot(p) return Travel.SpotLand(t, p) end
    local fly = ns.Engine.FlightLeg(goal, from, spot, to, spot)
    if fly then
      if not route.kd then ns.cdb.roadTrip = goalKey(goal) end
      ns.cdb.travelWay, ns.cdb.travelVia = nil, nil
      last = { fly = fly, point = fly.point, to = goal, left = 1 }
      return last
    end
    -- (a flight master in the city you're outside of, or the town round the city you're in: Elwynn's road to
    -- Stormwind's gryphons; through the gate first, then the flight)
    local function up(l) return l and (parts[l] or l) end
    fly = ns.Engine.FlightLeg(goal, up(from), function(p) return up(spot(p)) end, to, spot)
    local dep = fly and fly.point and spot(fly.point)
    if dep and dep ~= from then
      local level = ns.clean(UnitLevel and UnitLevel('player'))
      local plan = Travel.Plan(t, from, dep, level)
      if plan and #plan > 0 then return Travel.Show(plan, goal) end
    end
    -- a flight into the land next door, then its way in (Nov 7, the owner at Saldean's Farm with Dun Morogh next:
    -- 5,220 yards on foot, when Sentinel Hill flies to Ironforge and Ironforge's gate opens on Dun Morogh). Only when
    -- the walk from the landing through the way stays close to the straight line: Ratchet's road north into Durotar
    -- once looped a trip back to Orgrimmar
    local level = ns.clean(UnitLevel and UnitLevel('player')) or 0
    local far = ns.Geo.YardsTo(goal)
    local best, bestWalk
    for _, w in ipairs(t.ways or {}) do
      if far and w.to == to and w.from ~= from and w.from ~= to and level >= (w.min_level or 0) and w.via and w.via[1] then
        local f = ns.Engine.FlightLeg(goal, from, spot, w.from, spot)
        if f and f.flying then best, bestWalk = f, 0 break end
        if f and f.land then
          local walk, at = 0, f.land
          for _, v in ipairs(w.via) do walk = walk + (ns.Geo.Between(at, v) or math.huge) at = v end
          walk = walk + (ns.Geo.Between(w.out or at, goal) or math.huge)
          local straight = ns.Geo.Between(f.land, goal) or 0
          if walk <= straight * 1.5 + 300 and far - walk >= 800 and (not bestWalk or walk < bestWalk) then
            best, bestWalk = f, walk
          end
        end
      end
    end
    if best then
      if not route.kd then ns.cdb.roadTrip = goalKey(goal) end
      ns.cdb.travelWay, ns.cdb.travelVia = nil, nil
      last = { fly = best, point = best.point, to = goal, left = 2 }
      return last
    end
    -- across the sea: a flight to where the boat, tram or zeppelin leaves (Nov 9, the owner fishing in Redridge with
    -- Darkshore next: "Go in through Stormwind's main gate", 2,713 yards on foot, with Lakeshire's flight master at
    -- hand). The way that leaves your continent is the one to reach; a flight there when it saves the walk
    if not far then
      local plan = to and from ~= to and Travel.Plan(t, from, to, level)
      for k, w in ipairs(plan or {}) do
        local dock = w.via and w.via[1]
        if dock and ns.Geo.YardsTo(dock) and not (w.out and ns.Geo.YardsTo(w.out)) then
          local f = ns.Engine.FlightLeg(dock, from, spot, w.from, spot)
          if f then
            ns.cdb.travelWay, ns.cdb.travelVia = nil, nil
            last = { fly = f, point = f.point, to = goal, left = #plan - k + 2 }
            return last
          end
          break
        end
      end
    end
  end
  if not from and last and not (ns.st and ns.st.inst) then return last end
  if not from or not to or from == to then ns.cdb.travel, ns.cdb.travelVia, last = nil, nil, nil return nil end
  local level = ns.clean(UnitLevel and UnitLevel('player'))
  local plan = Travel.Plan(t, from, to, level)
  if not plan or #plan == 0 then
    ns.cdb.travel, ns.cdb.travelVia, last = nil, nil, nil
    if picked then ns.say(ns.L.travelNone) end   -- (said for a road you picked; a guide's own arrow goes on)
    return nil
  end
  return Travel.Show(plan, goal)
end

--- the first way of a plan on screen, its next point kept as you go
function Travel.Show(plan, goal)
  local w = plan[1]
  -- the way's next point: the first one you aren't standing at yet, kept as you go (a point passed stays passed)
  local key = w.from .. '>' .. w.to
  if ns.cdb.travelWay ~= key then ns.cdb.travelWay, ns.cdb.travelVia = key, 1 end
  local i = ns.cdb.travelVia or 1
  while w.via[i + 1] and ns.Geo.YardsTo(w.via[i]) and ns.Geo.YardsTo(w.via[i]) <= REACHED do i = i + 1 end
  ns.cdb.travelVia = i
  last = { way = w, point = w.via[i], to = goal, left = #plan }
  return last
end

--- the land you stand in, and a function giving the land of one of the route's points (for the evaluator: a flight
--- passed by a quest handed in earlier comes back when you're in neither land it joins; Nov 7, Darkshore)
function Travel.Lands(route)
  local t = data(route)
  local pts = route and route.pack and route.pack.pts
  if not (t and pts) then return nil, nil end
  local map, x, y = here()
  -- (a land inside another counts as the bigger one here: Stormwind's walls are only the trip's business, Nov 7)
  local parts = t.parts or {}
  local mine = map and Travel.Land(t, map, x, y)
  return mine and (parts[mine] or mine), function(pi)
    local p = pi and pts[pi]
    local l = p and Travel.Land(t, p[1], p[2], p[3])
    return l and (parts[l] or l) or nil
  end
end

--- the trip on screen now, or nil (the test rig's bot follows it as a player follows the arrow)
function Travel.Active() return last end

--- skip the trip on screen: the window shows the step it led to, with the arrow straight there (FB-049)
function Travel.Skip()
  if not (last and last.to and ns.cdb) then return false end
  -- (a quest for your road skipped: that quest only, the guide's own way goes on)
  if last.pickup then
    ns.cdb.passBy = ns.cdb.passBy or {}
    for _, q in ipairs(last.pickup.quests or {}) do ns.cdb.passBy[q] = true end
    last = nil
    ns.MarkDirty('trip')
    return true
  end
  ns.cdb.tripSkip = goalKey(last.to)
  ns.cdb.roadTrip, ns.cdb.travel, ns.cdb.travelWay, ns.cdb.travelVia = nil, nil, nil, nil
  last = nil
  ns.MarkDirty('trip')
  return true
end

--- can you get from where you stand to a road's first spot (no sea in between that no way crosses: Zephras Isle)?
function Travel.Reachable(route)
  local t = route and route.pack and route.pack.travel
  local pts = route and route.pack and route.pack.pts
  if not (t and pts) then return true end
  local first
  for _, s in ipairs(route.steps or {}) do if s.p and pts[s.p] then first = pts[s.p] break end end
  local map, x, y = here()
  if not (first and map) then return true end
  local from, to = Travel.Land(t, map, x, y), Travel.Land(t, first[1], first[2], first[3])
  if not from or not to then return true end
  return Travel.Plan(t, from, to) ~= nil
end

--- how far a place is from where you stand, for choosing between places (a profession guide's places by where you
--- stand, Engine.lua): yards on your own continent, with each way between lands on it counted as a 500-yard walk;
--- 100,000 and up across the sea; a billion when no way goes there (Zephras Isle from the mainland). Nil while your
--- own spot isn't known
function Travel.Reach(route, p, level)
  local map, x, y = here()
  if not (p and map and ns.Geo) then return nil end
  local t = data(route)
  local from, to = t and Travel.Land(t, map, x, y), t and Travel.Land(t, p[1], p[2], p[3])
  local plan = from and to and Travel.Plan(t, from, to, level)
  if from and to and not plan then return 1e9 end
  local cost = 0
  for _, w in ipairs(plan or {}) do cost = cost + (w.cost or 1) end
  local yards = ns.Geo.YardsTo(p)
  if yards then return yards + 500 * cost end
  return 1e5 + 1e4 * cost
end

--- picked from "Another start's road": the trip starts (it ends by itself once you're in the road's land)
function Travel.Start(routeId)
  if ns.cdb then ns.cdb.travel, ns.cdb.travelVia, ns.cdb.travelWay = routeId, 1, nil end
end

local ticker
--- while a trip is on, look again every second (you walk, you board, you land)
function Travel.Tick(on)
  if on and not ticker and C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(1, function() ns.MarkDirty('travel') end)
  elseif not on and ticker then
    ticker:Cancel()
    ticker = nil
  end
end
