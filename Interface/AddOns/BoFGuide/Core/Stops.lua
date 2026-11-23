-- Stops: what the window shows as one card. A route is a list of single actions; a player thinks in stops: "talk to
-- Rorian: hand in one, take one", "in the meadow: kill these and loot those". So the steps the evaluator puts in front
-- of you are grouped (no API calls here; tested as is):
--   talk   consecutive steps for the same person (accept, turn in, vendor, train, bind, flight path): the ones already
--          done stay on the card ticked, the ones right after are pulled in from "next"
--   area   the objectives of a block (steps the route does together, `blk`) in one card, quest by quest
--   single anything else, one step to a card
-- A stop: { kind, steps = { step indices in route order }, lead = the index the waypoint and target use, who, kindOf }
local _, ns = ...

local Stops = {}
ns.Stops = Stops
local E = ns.Evaluator

local NPC_OPS = { vendor = true, train = true, sethome = true, fp = true, rank = true }   -- (rank: at its trainer)
local AREA_OPS = { complete = true, kill = true, collect = true, use = true }

--- the person a step is about, if it's a talking step: an npc id, or nil
function Stops.Person(s)
  if (s.o == 'accept' or s.o == 'turnin') and s.who then return s.who[1] end
  if NPC_OPS[s.o] and s.npc then return s.npc end
  return nil
end

--- the talk stop around step i: the run of steps for the same person, done ones before it, pending ones after it
local function talkRun(route, view, i, who)
  local steps, status = route.steps, view.status
  -- the person's steps on either side, stepping over ones that aren't for you (another class's quest from the same
  -- npc doesn't split the stop); a step for anyone else ends it
  local first, last = i, i
  while first > 1 and Stops.Person(steps[first - 1]) == who do first = first - 1 end
  while last < #steps and Stops.Person(steps[last + 1]) == who do last = last + 1 end
  local unheld = view.unheld or {}
  local taking = {}   -- quests this run takes: their turn-in here comes after
  for j = first, last do
    if steps[j].o == 'accept' and status[j] == E.PENDING then
      for _, q in ipairs(type(steps[j].id) == 'table' and steps[j].id or { steps[j].id }) do taking[q] = true end
    end
  end
  local function takenHere(j)
    for _, q in ipairs(type(steps[j].id) == 'table' and steps[j].id or { steps[j].id }) do
      if taking[q] then return true end
    end
    return false
  end
  local run = {}
  for j = first, last do
    -- a turn-in for a quest you don't have, that this run doesn't give you, isn't for now (Tome of Divinity here
    -- before you've been offered it)
    local skip = status[j] == E.PENDING and steps[j].o == 'turnin' and unheld[j] and not takenHere(j) and j ~= i
    if not skip and (status[j] == E.PENDING or (status[j] == E.DONE and j < i)) then run[#run + 1] = j end
  end
  -- at a person you hand quests in before you take new ones (the next often needs the last one done), so the card
  -- lists turn-ins first, whatever order a draft put them in; one for a quest taken right here comes after the taking
  local rank = { turnin = 1, accept = 2 }
  local pos = {}
  for k, j in ipairs(run) do pos[j] = k end
  local function rk(j)
    if steps[j].o == 'turnin' and unheld[j] then return 3 end
    return rank[steps[j].o] or 3
  end
  table.sort(run, function(a, b)
    local ra, rb = rk(a), rk(b)
    if ra ~= rb then return ra < rb end
    return pos[a] < pos[b]
  end)
  return run
end

local NEAR, AHEAD = 120, 20   -- yards an objective may be from the area to join it; steps ahead to look through
local ONE_SPOT = 250          -- yards: a one-spot objective this close to the nearest one is done before a kill loop

--- the order the current steps lead in: nearest first, but a "with next" step never leads (it's done on the way to
--- the step it rides beside), and in an area a one-spot objective (a named creature, an object) comes before a kill
--- loop near it, the way RestedXP sends you to the queen and lets the clusters ride along
local function leadOrder(steps, order, near)
  local out = {}
  for _, i in ipairs(order) do if not steps[i].wn then out[#out + 1] = i end end
  for _, i in ipairs(order) do if steps[i].wn then out[#out + 1] = i end end
  local first = out[1]
  if first and AREA_OPS[steps[first].o] and steps[first].lp and near then
    for k = 2, #out do
      local j = out[k]
      local s = steps[j]
      if s.wn then break end
      if AREA_OPS[s.o] and not s.lp then
        local d = near(first, j)
        if d and d <= ONE_SPOT then table.remove(out, k) table.insert(out, 1, j) end
        break
      end
    end
  end
  return out
end

--- group the evaluator's view into stops. order = the current steps nearest first (Engine's order, focus first).
--- opts.near(i, j) = yards between two steps' spots (or nil), opts.inLog(q) = the quest is in your log: with both,
--- an area also takes the objectives just ahead whose quests you have and that lie within NEAR yards (kill these on
--- the way), the way a player does them.
--- Returns current stops (the first is "now", the rest "also here"), sticky stops, and the upcoming stops.
function Stops.Build(route, view, order, opts)
  opts = opts or {}
  local steps, used = route.steps, {}
  local function stopFor(i, kind)
    local s = steps[i]
    local who = Stops.Person(s)
    if who then
      local run = talkRun(route, view, i, who)
      for _, j in ipairs(run) do used[j] = true end
      local lead
      for _, j in ipairs(run) do if view.status[j] == E.PENDING then lead = lead or j end end
      return { kind = 'talk', steps = run, lead = lead or i, who = who, as = kind }
    end
    used[i] = true
    return { kind = 'single', steps = { i }, lead = i, as = kind }
  end
  local current, sticky, upcoming = {}, {}, {}
  order = leadOrder(steps, order or view.current, opts.near)
  if opts.hold then   -- the objective the area led with a moment ago stays first among its objectives
    local at, firstArea
    for n, i in ipairs(order) do
      if AREA_OPS[steps[i].o] then firstArea = firstArea or n end
      if i == opts.hold and AREA_OPS[steps[i].o] and not steps[i].wn then at = n end
    end
    if at and firstArea < at then table.remove(order, at) table.insert(order, firstArea, opts.hold) end
  end
  -- the objectives in front of you together (one area), then each talking or single step
  local area
  for _, i in ipairs(order) do
    if not used[i] and AREA_OPS[steps[i].o] then
      area = area or { kind = 'area', steps = {}, lead = i, as = 'now' }
      table.insert(area.steps, i)
      used[i] = true
    end
  end
  for _, i in ipairs(order) do
    if not used[i] then
      local stop = stopFor(i, #current == 0 and not area and 'now' or 'here')
      current[#current + 1] = stop
    end
  end
  if area and opts.near and opts.inLog then
    -- the objectives just ahead: never an as-you-go step (those show under As you go when their turn comes), never
    -- an objective the card already has, nor one riding along as you go right now (the windstones stay there while
    -- the queen's card is up)
    local have, riding = {}, {}
    for _, i in ipairs(area.steps) do
      for _, q in ipairs(E.quests(steps[i])) do have[q .. ':' .. (steps[i].ob or 0)] = true end
    end
    for _, i in ipairs(view.sticky) do
      for _, q in ipairs(E.quests(steps[i])) do riding[q] = true end
    end
    local cursor = view.cursor or area.lead
    for j = cursor + 1, math.min(#steps, cursor + AHEAD) do
      local s = steps[j]
      local ride = false
      for _, q in ipairs(E.quests(s)) do if riding[q] then ride = true end end
      if not used[j] and not ride and view.status[j] == E.PENDING and AREA_OPS[s.o] and not s.sticky and not s.wn then
        local mine, dup = false, false
        for _, q in ipairs(E.quests(s)) do
          if opts.inLog(q) then mine = true end
          if have[q .. ':' .. (s.ob or 0)] or have[q .. ':0'] then dup = true end
        end
        local d = mine and not dup and opts.near(area.lead, j)
        if d and d <= NEAR then
          table.insert(area.steps, j) used[j] = true
          for _, q in ipairs(E.quests(s)) do have[q .. ':' .. (s.ob or 0)] = true end
        end
      end
    end
  end
  if area then
    -- the rows hold still: the lead first, the rest in the route's order (they were nearest first, and moved as you
    -- walked), steps done on the way last
    -- (a quest's objectives stay together, under its one heading: the goulash's spider and condor meat stood under
    -- "Assessing the Threat")
    local lead = area.lead
    local first = {}
    for _, i in ipairs(area.steps) do
      local q = steps[i].id or i
      if not steps[i].wn and (not first[q] or i < first[q]) then first[q] = i end
    end
    first[steps[lead].id or lead] = 0
    table.sort(area.steps, function(a, b)
      if (a == lead) ~= (b == lead) then return a == lead end
      local wa, wb = steps[a].wn and 1 or 0, steps[b].wn and 1 or 0
      if wa ~= wb then return wa < wb end
      local fa, fb = first[steps[a].id or a] or a, first[steps[b].id or b] or b
      if fa ~= fb then return fa < fb end
      return a < b
    end)
    -- the objectives done where the arrow leads: the lead's own loop, or spots beside its spot. The title and the
    -- arrow name these first (area.with; nil when that's all of them)
    if opts.near then
      local function lpKey(s) return s.lp and table.concat(s.lp, ',') or nil end
      local L, with, all = steps[lead], {}, true
      for _, i in ipairs(area.steps) do
        local s = steps[i]
        local same = i == lead
        if not same and L.lp then same = lpKey(s) == lpKey(L)
        elseif not same and not s.lp then same = (opts.near(lead, i) or math.huge) <= NEAR end
        with[i] = same or nil
        if not same then all = false end
      end
      if not all then area.with = with end
    end
    -- the area leads when the nearest current step is one of its objectives
    local first = order[1]
    local leads = false
    for _, i in ipairs(area.steps) do if i == first then leads = true end end
    if leads then table.insert(current, 1, area) else area.as = 'here' current[#current + 1] = area end
    for k, st in ipairs(current) do st.as = k == 1 and 'now' or 'here' end
  end
  -- as you go: each once (an objective already on a current card isn't listed again)
  local shown = {}
  for _, stop in ipairs(current) do
    for _, j in ipairs(stop.steps) do
      if AREA_OPS[steps[j].o] then
        for _, q in ipairs(E.quests(steps[j])) do shown[q .. ':' .. (steps[j].ob or 0)] = true end
      end
    end
  end
  for _, i in ipairs(view.sticky) do
    local s = steps[i]
    local dup = false
    if AREA_OPS[s.o] then
      for _, q in ipairs(E.quests(s)) do if shown[q .. ':' .. (s.ob or 0)] or shown[q .. ':0'] then dup = true end end
    end
    if not used[i] and not dup and s.cash and (ns.st.cash or 0) < s.cash then
      -- the coin for a trainer, gathered as you go: a line of its own with how far along you are (not a talk stop yet)
      used[i] = true
      sticky[#sticky + 1] = { kind = 'single', steps = { i }, lead = i, as = 'sticky' }
    elseif not used[i] and not dup then
      sticky[#sticky + 1] = stopFor(i, 'sticky')
      if AREA_OPS[s.o] then   -- (two of a route's as-you-go lines for one objective can ride at once for a class)
        for _, q in ipairs(E.quests(s)) do shown[q .. ':' .. (s.ob or 0)] = true end
      end
    end
  end
  -- up next: the stops to come, a person's steps together; an as-you-go step isn't a stop of its own (it shows under
  -- As you go when its turn comes), and the same quest's objectives one after another make one row
  for _, i in ipairs(view.upcoming) do
    local s = steps[i]
    if not used[i] and not s.sticky then
      local who = Stops.Person(s)
      local last = upcoming[#upcoming]
      local lastS = last and steps[last.lead]
      if who and last and last.who == who then
        table.insert(last.steps, i)
      elseif not who and last and not last.who and AREA_OPS[s.o] and AREA_OPS[lastS.o]
          and E.quests(s)[1] and E.quests(s)[1] == E.quests(lastS)[1] then
        table.insert(last.steps, i)
      else
        upcoming[#upcoming + 1] = { kind = who and 'talk' or 'single', steps = { i }, lead = i, who = who, as = 'next' }
      end
      used[i] = true
    end
  end
  return current, sticky, upcoming
end

--- the steps of a stop still to do
function Stops.Pending(stop, view)
  local out = {}
  for _, i in ipairs(stop.steps) do if view.status[i] == E.PENDING then out[#out + 1] = i end end
  return out
end
