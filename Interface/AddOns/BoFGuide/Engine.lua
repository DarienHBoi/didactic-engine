-- Glue: reads the game when it changes, picks the route, asks the evaluator where you are, draws the window and sets
-- the waypoint. Steps that only get you somewhere (vendor, trainer, hearth, campfire, goto, fly) are marked done when
-- you do them while they're on screen, and kept per character by their stable keys.
--
-- Three kinds of route: leveling routes, dungeon guides and profession guides. Inside a dungeon its guide takes over
-- the window; outside, a dungeon guide shows when you pin it (/bofg dungeon), then a pinned profession guide
-- (/bofg prof), then the leveling route, which comes back when the others are closed or done.
local _, ns = ...

local Engine = {}
ns.Engine = Engine
local st, E = ns.st, ns.Evaluator
local route, leveling, view, order   -- route: the one on screen; leveling: the leveling route
local levView                        -- the leveling route's own view while another guide is on screen
local levRoute                       -- and that leveling route
local marks, markedStop              -- what the Waymark is told after this refresh; the lead stop it was told last
local loginAt, ticker
local focused, announce, stops
local naturalLead   -- the step the guide leads with before any click (a click steers the arrow only until it changes)
local heldLead, heldFor   -- the keys of the stop the card last led with, and the card (naturalLead) it was for
local SWITCH_NEARER = 0.6 -- another stop on the card leads only when it's this much nearer than the one leading
local ARRIVE_YARDS, FLY_ARRIVE_YARDS, LOOP_YARDS, PATH_YARDS = 20, 80, 40, 15
local PATH_SIDE_YARDS = 40   -- a walk's point passed to the side: this close and nearer the next point than it is
local HEARTH_ARRIVE_YARDS = 300   -- walked to where a hearth lands: as good as there (Evaluator HOME_YARDS)
local ARRIVED_YARDS = 250   -- this close to where a flight behind your place lands, you got there (Evaluator LANDED_YARDS)
local HEARTH_NAME = 'Hearthstone'
local HEARTHSTONE_ITEM = 6948
-- by spell ID, so any client language counts them (the names are the English fallback; i18n, Oct 16): the
-- Hearthstone's casts, and the Campfire and Camp Tent spells
local HEARTH_IDS = { [8690] = true, [1303762] = true, [1315212] = true }
local CAMP_IDS = { [1229736] = true, [1229432] = true, [1229487] = true, [1255248] = true, [1307230] = true }

--- the level a party goes by: the lowest whole level in it, yours included (nil alone, in a raid, or when nobody in
--- it is within two levels of you: a friend you're helping through a low zone doesn't bring your old steps back).
--- Nov 11, the owner (21) and their daughter (20) on the docks of Lakeshire: a step planned more than a level below
--- you is left behind, so one guide said Darkshire and the other said stay. Whole levels, because the game tells only
--- that much about anyone else, and both guides must count from the same number
local PACE_LEVELS = 2
function Engine.PartyPace()
  if not (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) or not UnitLevel then return nil end
  local mine, low = st.level or 1, nil
  for i = 1, 4 do
    local l = ns.clean(UnitLevel('party' .. i))
    if type(l) == 'number' and l > 0 and math.abs(l - mine) <= PACE_LEVELS then low = math.min(low or mine, l) end
  end
  return low
end

function Engine.Who()
  local perks, profs = {}, {}
  for k, v in pairs(ns.settings.perks or {}) do perks[k] = v end
  for k, v in pairs(st.profs or {}) do profs[k] = v end
  for k, v in pairs(ns.settings.profs or {}) do profs[k] = v end
  -- optional group quests: shown in a party (or always, or never: the setting)
  local g = ns.settings.groupQuests or 'party'
  local solo = g == 'never' or (g == 'party' and not (IsInGroup and IsInGroup()))
  return { race = st.race, class = st.class, hc = st.hc, faction = st.faction, solo = solo,
           party = IsInGroup and IsInGroup() or false,
           noDungeons = ns.settings.dungeons == false, dq = ns.Packs.dungeonQuests,
           dOff = ns.settings.dungeonOff,   -- (dungeons switched off one by one in the guide book: FB-053)
           level = (st.level or 1) + (st.xp or 0) / (st.xpMax or 1), pace = Engine.PartyPace(),
           perks = perks, profs = profs }
end

function Engine.Route() return route end
--- the leveling route and its view while another guide is on screen (nil when leveling is the one shown)
function Engine.Under() if levView then return leveling, levView end end
--- the leveling route you're on, also while a dungeon or profession guide is on screen
function Engine.Leveling()
  return leveling or (ns.cdb and ns.cdb.route and ns.Packs.Get(ns.cdb.route)) or ns.Packs.Suggest(Engine.Who())
end
function Engine.View() return view end

local function prog()
  local c = ns.cdb
  c.passed = c.passed or {}
  -- (done: what you did or marked; passed: a walk, flight or hearth your place moved beyond, which no rule reading where
  -- you stand brings back. Nov 9, never stranded: the card leapt back to Westfall and Redridge's door as you walked)
  local done = setmetatable({}, { __index = function(_, k) return c.done[k] or c.passed[k] end })
  return { skip = c.skip, unskip = c.unskip, done = done, dropped = c.dropped, trained = c.trained }
end

-- ------------------------------------------------------------------------------------- places by where you stand
-- A profession or gathering guide is written once per start: where that start trains, buys, fishes and mines, on the
-- assumption that you took the profession up at level 1 on that start's own road. Which start's places you got was
-- your race (the owner's Night Elf leveling in Redridge was sent to fish in Darkshore), then the road you level on
-- (Nov 10 morning; the quality review the same day: a profession taken up late on a Skyborne road led back to Zephras
-- Isle, where nothing sails). Now it's where you stand: of every start's next place still to do at your skill and
-- level, the nearest on your own continent; across the sea only when nothing is nearer; a place no way goes to only
-- when there is no other. The choice holds until that place is done, you gain a level, you cross the sea or you open
-- the guide again, so the card holds still while you walk.
local SIDES = { alliance = { 1, 3, 4, 7, 95 }, horde = { 2, 5, 6, 8, 96 } }
local PLACE_NEARER = 0.75   -- another start's place wins over yours (or your road's) only when it's this much nearer
local PLACE_AGAIN = 5       -- seconds before looking again when no start had a place left

local function asRace(who, race)
  if who.race == race then return who end
  local w = {}
  for k, v in pairs(who) do w[k] = v end
  w.race = race
  return w
end

--- who the guide is read for: you, and on a profession guide the start whose places it shows now
function Engine.WhoFor(r, who)
  who = who or Engine.Who()
  local pl = r and r.kd == 'profession' and ns.cdb and ns.cdb.profPlace
  if pl and pl.r == r.id and pl.race then return asRace(who, pl.race) end
  return who
end

--- the first level above yours at which a guide has something to do that it holds back now: part of it waits behind
--- a level (a Night Elf smith's Journeyman trainer is in Ironforge, which their road reaches at 23)
local function opensLater(r, who)
  local levels, seen = {}, {}
  for _, s in ipairs(r.steps) do
    local l = s.lmin
    if l and l > (who.level or 0) and not seen[l] then seen[l] = true levels[#levels + 1] = l end
  end
  table.sort(levels)
  for _, l in ipairs(levels) do
    local w = {}
    for k, v in pairs(who) do w[k] = v end
    w.level = l
    if not E.evaluate(r, st, prog(), r.pack, w, { noPass = true }).done then return l end
  end
end

--- the level at which a guide that reads as finished goes on, or nil when it is finished. Without this a level-15
--- Night Elf smith at skill 75 was told the guide "ends at skill 225" and pointed at the full guide (the skill-kept
--- sweep, Nov 10)
function Engine.OpensAt(r, who)
  who = who or Engine.WhoFor(r)
  if not E.evaluate(r, st, prog(), r.pack, who, { noPass = true }).done then return nil end
  return opensLater(r, who)
end

--- the guide the level wait set aside, once you've reached that level and it has something to do: { id, name }, for
--- the window's plate. An offer only: the guide never switches by itself (owner, Nov 10). nil while a side guide or
--- a dungeon's guide is on screen
local backSig, backVal
function Engine.ProfBack()
  local wt = ns.cdb and ns.cdb.profWait
  if not wt or (st.level or 0) < (wt.lvl or 0) or not route or route ~= leveling then return nil end
  local sig = wt.r .. ':' .. (st.level or 0) .. ':' .. tostring(st.profs and st.profs[wt.pr])
  if sig ~= backSig then
    backSig, backVal = sig, nil
    local r = ns.Packs.Get(wt.r)
    if not r then
      if not ns.Paid.Busy() then ns.cdb.profWait = nil end   -- (a paid one still opening: kept)
      return nil
    end
    local who = wt.race and asRace(Engine.Who(), wt.race) or Engine.Who()
    if E.evaluate(r, st, prog(), r.pack, who, { noPass = true }).done then
      local later = opensLater(r, who)
      if later then wt.lvl = later else ns.cdb.profWait = nil end   -- (it waits again, or you finished it elsewhere)
      return nil
    end
    backVal = { id = r.id, name = ns.L.PROFS[r.pr] or r.pr or r.title }
  end
  return backVal
end

--- the plate's click: on with that guide (go), or put the offer away
function Engine.ProfBackTake(go)
  local wt = ns.cdb and ns.cdb.profWait
  if not wt then return end
  ns.cdb.profWait, backSig, backVal = nil, nil, nil
  if go then Engine.SetRoute(wt.r) else ns.MarkDirty('prof') end
end

--- the first place still to do on a guide as `who` reads it: the step's key and its spot
local function nextPlace(r, who)
  local pts = r.pack and r.pack.pts
  if not pts then return nil end
  local v = E.evaluate(r, st, prog(), r.pack, who, { noPass = true })
  for i = v.cursor or (#r.steps + 1), #r.steps do
    local s = r.steps[i]
    if v.status[i] == E.PENDING and s.p and pts[s.p] then return s.k, pts[s.p] end
  end
end

--- the start whose next place is the best from where you stand (its race, and that place's step), or nil when no
--- start has a place left or your own spot isn't known
local function pickPlace(r, who, rows)
  if not (ns.Travel and ns.Travel.Reach) then return nil end
  local races, seen = { who.race }, { [who.race] = true }
  local road = Engine.Leveling()
  for _, x in ipairs(road and road.rc or {}) do if not seen[x] then seen[x] = true races[#races + 1] = x end end
  for _, x in ipairs(SIDES[st.faction] or {}) do if not seen[x] then seen[x] = true races[#races + 1] = x end end
  local best, bestKey, bestReach
  for _, race in ipairs(races) do
    local k, p = nextPlace(r, asRace(who, race))
    local reach = k and ns.Travel.Reach(r, p, who.level)
    -- (yours first, then your road's: those two keep the guide's own run of trainer, vendor and ground together)
    local margin = (best and (best == who.race or (road and road.rc and best == road.rc[1]))) and PLACE_NEARER or 1
    if reach and (not bestReach or reach < bestReach * margin) then best, bestKey, bestReach = race, k, reach end
    if rows and k then rows[#rows + 1] = { race = race, k = k, p = p, reach = reach } end
  end
  -- (another start's place across the sea while part of your own start's guide waits for a level: yours, and wait.
  -- The planner holds a Night Elf smith's Journeyman rank until their road reaches Ironforge at 23, so a level-15 one
  -- in Darkshore isn't sent over the sea and through the Wetlands for it; Nov 6, kept under the place rule Nov 10)
  if best and best ~= who.race and bestReach >= 1e5 and opensLater(r, who) then return nil end
  return best, bestKey
end

--- /bofg place: every start's next place on the profession guide on screen, with what it costs to reach from where
--- you stand ({ race, k, p, reach, step }), the start the rule would pick now, and the place the card holds. Nil on
--- any other guide. Reads only: the card's place isn't touched
function Engine.Places()
  if not (route and route.kd == 'profession') then return nil end
  local rows = {}
  local best, bestKey = pickPlace(route, Engine.Who(), rows)
  local at = {}
  for i, s in ipairs(route.steps) do at[s.k] = i end
  for _, row in ipairs(rows) do row.step = route.steps[at[row.k]] end
  local pl = ns.cdb and ns.cdb.profPlace
  return rows, bestKey, pl and pl.r == route.id and pl.k or nil, best
end

-- ------------------------------------------------------------------------------------------- the card holds still
-- (Nov 9, the owner: "I came to the inn to log out and it abandoned the fly to Stormwind and now tells me to go back
-- to mongrels"; his daughter's card said "Fly to Sentinel Hill" at Lakeshire's flight master and the mongrels again
-- in the inn. RestedXP's step moves when its step is done. Ours was worked out again every second from where you
-- stand, and a dozen rules that read your position moved it as you walked: scripts/guide_dev/lead_sweep.py found 130
-- such spots on one leg.) Now the step the card leads with stays the lead while nothing in the game has changed: your
-- quests, their objectives, what's done or skipped, your level, bind, flight paths and bags. When something changes,
-- the guide decides again as before.
local function stateSig()
  local c, n, o, items = ns.cdb, 0, 0, 0
  for _ in pairs(st.completed or {}) do n = n + 1 end
  for q, e in pairs(st.log or {}) do
    o = o + q * 3 + (e.ready and 1 or 0)
    for k, ob in ipairs(e.obj or {}) do o = o + (ob.have or 0) * (k + 7) + (ob.fin and k or 0) end
  end
  for id, v in pairs(st.items or {}) do items = items + id % 997 * (v or 0) end
  local d, s, u, t = 0, 0, 0, 0
  for _ in pairs(c.done or {}) do d = d + 1 end
  for _ in pairs(c.skip or {}) do s = s + 1 end
  for _ in pairs(c.unskip or {}) do u = u + 1 end
  for _ in pairs(st.taxi or {}) do t = t + 1 end
  local no = 0
  for _ in pairs(c.notOffered or {}) do no = no + 1 end
  local set, who = ns.settings or {}, Engine.Who()
  return table.concat({ route and route.id or '', n, o, items, d, s, u, t, st.level or 0, c.bindNpc or 0,
                        st.inst or 0, c.jump and #c.jump or 0, c.focus or '', no, st.cash or 0,
                        tostring(set.groupQuests), tostring(set.dungeons), tostring(st.hc), tostring(who and who.party),
                        tostring(who and who.solo), tostring(who and who.pace) }, ':')
end

local keyIndex, keyIndexOf = nil, nil
local function indexOfKey(r, k)
  if keyIndexOf ~= r then
    keyIndex, keyIndexOf = {}, r
    for i, s in ipairs(r.steps) do if s.k then keyIndex[s.k] = i end end
  end
  return keyIndex[k]
end

function Engine.SetRoute(id)
  local r = ns.Packs.Get(id)
  if not r then return false end
  -- what you pick is what shows: a pinned guide that outranks it is unpinned. Inside an instance its dungeon guide
  -- comes first until you pick something else there (the QA pass, Oct 20: "Back to leveling" did nothing inside)
  if st.inst then
    local own = ns.Packs.DungeonFor(st.inst, Engine.Who())
    ns.cdb.outInst = (not own or r ~= own) and st.inst or nil
  end
  if r.kd == 'dungeon' then
    ns.cdb.dungeon = id
  elseif r.kd == 'profession' then
    ns.cdb.prof, ns.cdb.dungeon, ns.cdb.profPlace = id, nil, nil
    if ns.cdb.profWait and ns.cdb.profWait.r == id then ns.cdb.profWait = nil end   -- (you opened it yourself)
  elseif r.kd == 'legacy' then
    ns.cdb.legacy, ns.cdb.prof, ns.cdb.dungeon = id, nil, nil
  else
    leveling, ns.cdb.route, ns.cdb.dungeon, ns.cdb.prof, ns.cdb.legacy = r, id, nil, nil, nil
  end
  ns.MarkDirty('route')
  return true
end

--- the first route for a character the guide hasn't seen: the earliest leg that still has two or more of the quests
--- in your log to finish, if you're not far past it; else by level. (The owner's Night Elf, Oct 21: at level 12.7,
--- past Teldrassil's 12.5, the guide went to Darkshore with seven Teldrassil quests in the log)
local function byLog(who)
  for _, r in ipairs(ns.Packs.For(who)) do
    -- (never a leg that starts above you: a level 25 who carries Wetlands quests isn't sent to the 27-28 leg that
    -- hands them in; the join check, Oct 21)
    if not r.kd and r.lv and (who.level or 1) < r.lv[2] + 2 and r.lv[1] <= (who.level or 1) + 1 then
      local mine = {}
      local n = 0
      for _, s in ipairs(r.steps or {}) do
        if s.o == 'turnin' or s.o == 'complete' then
          for _, q in ipairs(E.quests(s)) do
            if st.log[q] and not mine[q] then mine[q] = true n = n + 1 end
          end
        end
      end
      if n >= 2 then return r end
    end
  end
end

local function chooseRoute(who)
  if leveling then return leveling end
  if ns.cdb.route and ns.Packs.Get(ns.cdb.route) then leveling = ns.Packs.Get(ns.cdb.route) return leveling end
  -- your route is in a paid pack still opening (a slice a frame), or a key waits for the BattleTag: show a pick, keep
  -- yours (it used to be swapped for the pick once the quest log was read)
  if ns.cdb.route and ns.Paid.Busy() then return ns.Packs.Suggest(who) end
  local pick = (st.ready and byLog(who)) or ns.Packs.Suggest(who)
  -- (kept only once the quest log has been read: a pick made before it would be by level alone, and stick)
  if pick and st.ready then leveling = pick ns.cdb.route = pick.id end
  return pick
end

--- which wing's guide, when several share the instance you're in (Nov 7, the paid dungeon walk: inside the Armory the
--- window switched to the Graveyard's guide, the first for map 189): the one you picked, else the one whose boss died
--- this run, else your leveling road's next dungeon stop, else the first you haven't finished
local function pickWing(all)
  for _, r in ipairs(all) do if r.id == ns.cdb.dungeon then return r end end
  local start, best, bestAt = ns.cdb.entered[st.inst] or 0, nil, nil
  for _, r in ipairs(all) do
    for _, s in ipairs(r.steps) do
      local t = s.o == 'boss' and ns.cdb.kills[s.id]
      if t and t >= start and (not bestAt or t > bestAt) then best, bestAt = r, t end
    end
  end
  if best then return best end
  if leveling and levView and levView.status then
    for i = levView.cursor or 1, #leveling.steps do
      local s = leveling.steps[i]
      if s.o == 'dungeon' and levView.status[i] == E.PENDING then
        for _, r in ipairs(all) do if r.id == s.dg then return r end end
      end
    end
  end
  for _, r in ipairs(all) do if not ns.cdb.dungeons[r.id] then return r end end
  return all[1]
end

--- the dungeon guide to show: the one for the instance you're in, else the one you pinned
--- a pinned guide that leads you through this instance on its way somewhere else: its place is at or after its own
--- `enter` for it (Nov 13, the Onyxia attunement guides: the Horde chain's Oculus run in Blackrock Spire, the
--- Alliance's Windsor part in Blackrock Depths; the instance's own guide took the window and had no step for them)
local function passesThrough(r, who)
  if not (r and r.kd == 'dungeon' and st.inst and r.inst ~= st.inst) then return false end
  local has = false
  for _, s in ipairs(r.steps) do if s.o == 'enter' and s.id == st.inst then has = true break end end
  if not has then return false end
  local v = E.evaluate(r, st, prog(), r.pack, who, { noPass = true })
  local c = v and v.cursor
  if not c then return false end
  for i = c, 1, -1 do
    local s = r.steps[i]
    if s.o == 'enter' then return s.id == st.inst end
  end
  return false
end
Engine.PassesThrough = passesThrough

local function chooseDungeon(who)
  if not st.inst then ns.cdb.outInst = nil end
  local pinned0 = ns.cdb.dungeon and ns.Packs.Get(ns.cdb.dungeon)
  if pinned0 and ns.cdb.outInst ~= st.inst and passesThrough(pinned0, who) then return pinned0 end
  if st.inst and ns.cdb.outInst ~= st.inst then
    local all = ns.Packs.DungeonsFor(st.inst, who)
    if #all > 0 then return #all == 1 and all[1] or pickWing(all) end
  end
  -- a ghost out of the dungeon it died in: the game gives no spot for a body inside, so its guide stays and its way in
  -- leads to the door (Nov 9, the RestedXP arrow study's #10: the window went back to the leveling road)
  if not st.inst and ns.cdb.diedIn then
    if UnitIsGhost and ns.clean(UnitIsGhost('player')) then
      local all = ns.Packs.DungeonsFor(ns.cdb.diedIn, who)
      if #all > 0 then return #all == 1 and all[1] or pickWing(all) end
    else
      ns.cdb.diedIn = nil
    end
  end
  local pinned = ns.cdb.dungeon and ns.Packs.Get(ns.cdb.dungeon)
  if pinned and pinned.kd == 'dungeon' then return pinned end
  if ns.cdb.dungeon and not pinned and ns.Paid.Busy() then return nil end   -- (a paid one still opening: kept)
  ns.cdb.dungeon = nil
  return nil
end

--- the profession guide you pinned (the pin stays while its import isn't loaded yet, e.g. the BattleTag hidden at login)
local function chooseProfession()
  local r = ns.cdb.prof and ns.Packs.Get(ns.cdb.prof)
  if r and r.kd == 'profession' then return r end
  return nil
end

--- the Legacy guide you pinned
local function chooseLegacy()
  local r = ns.cdb.legacy and ns.Packs.Get(ns.cdb.legacy)
  if r and r.kd == 'legacy' then return r end
  return nil
end

--- the next dungeon stop on the route on screen (leveling or Legacy), for /bofg dungeon with nothing after it
function Engine.StopAhead()
  if not (route and (route == leveling or route.kd == 'legacy') and view and view.status) then return nil end
  for i = view.cursor or 1, #route.steps do
    local s = route.steps[i]
    if s.o == 'dungeon' and view.status[i] == E.PENDING then return s.dg end
  end
  return nil
end

--- the steps on screen right now (current and sticky)
local function onScreen()
  local out = {}
  if not view then return out end
  for _, i in ipairs(view.current) do out[#out + 1] = i end
  for _, i in ipairs(view.sticky) do out[#out + 1] = i end
  return out
end

--- is the step on the card now (where you join its walk or loop is kept only then: Nov 8, the RestedXP arrow study,
--- a hearth card 600 yards off fixed the next walk as done)
local function shown(s)
  for _, i in ipairs(onScreen()) do if route and route.steps[i] == s then return true end end
  return false
end

-- ------------------------------------------------------------------------------------------------------- looking back
-- /bofg back shows the step before the one on screen, and each call one further (owner, Oct 15: testers go back to
-- screenshot a card they missed). Nothing is undone: the steps behind keep what the game and your clicks say. While
-- you look back the window stays on that step, the automation and the arrival and visit marks wait, and only
-- /bofg forward (one step at a time) or /bofg resume brings the guide back to where you are.
local function peekIndex()
  local k = ns.cdb and ns.cdb.peek
  if not (k and route) then return nil end
  for i, s in ipairs(route.steps) do if s.k == k then return i end end
  return nil
end
function Engine.Peeking() return peekIndex() ~= nil end

local function liveIndex()   -- where you really are (the look-back's copy of the view keeps it as `live`)
  if view and view.peek then return view.live or (route and #route.steps + 1) end
  return view and view.cursor or (route and #route.steps + 1)
end

function Engine.Back()
  if not route then return false end
  local who, from = Engine.WhoFor(route), peekIndex() or liveIndex()
  for i = (from or 1) - 1, 1, -1 do
    if E.applies(route.steps[i], who) then
      ns.cdb.peek = route.steps[i].k
      ns.say(ns.L.peekBack)
      ns.MarkDirty('peek')
      return true
    end
  end
  ns.say(ns.L.peekStart)
  return false
end

function Engine.Forward()
  local p = peekIndex()
  if not p then return false end
  local who, live = Engine.WhoFor(route), liveIndex()
  for i = p + 1, #route.steps do
    if i >= (live or i) then break end
    if E.applies(route.steps[i], who) then
      ns.cdb.peek = route.steps[i].k
      ns.MarkDirty('peek')
      return true
    end
  end
  return Engine.Resume()
end

function Engine.Resume()
  if not (ns.cdb and ns.cdb.peek) then return false end
  ns.cdb.peek = nil
  ns.say(ns.L.peekResume)
  ns.MarkDirty('peek')
  return true
end

--- looking back ends by itself when the game moves on (FB-064, Nov 13, a Korean Warlock: a look back left days before
--- held the leg's first card, Underground Assault, already in the log, and read as "the guide doesn't see my quest"):
--- a quest taken or handed in, a level, a new session
local function endPeek()
  if ns.cdb and ns.cdb.peek then
    ns.cdb.peek = nil
    ns.MarkDirty('peek')
  end
end
Engine.EndPeek = endPeek

--- mark on-screen steps of this kind done (vendor at this npc, a hearth, a campfire...)
--- the trainer window open now is a class trainer's (not a craft's or a pet's): C_Trainer.GetTrainerType, 0 = General;
--- nil when the game doesn't say
local function classTrainerOpen()
  if not (C_Trainer and C_Trainer.GetTrainerType) then return nil end
  local ok, t = pcall(C_Trainer.GetTrainerType)
  if not ok or t == nil or (issecretvalue and issecretvalue(t)) then return nil end
  return t == 0
end

--- training seen or skipped: the trainer stops after it wait until your class has spells of a higher level for you
--- (the owner at 22, Nov 11: "a train your spells step pop up 3 times in the last 10 minutes I've had to skip ... because
--- I don't have enough money". Stormwind's two Priest trainers, then Goldshire's, each a stop for the same spells)
local function trainedTo(s)
  if not (s and s.o == 'train' and s.sp) then return end
  local top = 0
  for _, sp in ipairs(E.TrainSpells(s, Engine.Who())) do
    if sp[1] <= (st.level or 0) and sp[1] > top then top = sp[1] end
  end
  if top > (ns.cdb.trained or 0) then ns.cdb.trained = top end
end

function Engine.Latch(op, npc)
  if not route or peekIndex() then return end
  local hit = false
  for _, i in ipairs(onScreen()) do
    local s = route.steps[i]
    -- a training step is done once you've seen the trainer: what you buy is yours to choose (owner, Nov 7: four skips in
    -- a row for spells left untrained). Its own trainer, or any class trainer when the game says that's who it is.
    -- (A vendor step with a buy list stays until your bags hold it)
    local who = not npc or not s.npc or s.npc == npc
    -- (no one behind the window and the game says it isn't a class trainer: Beast Training, a pet's. Nov 8, the RestedXP
    -- client study: a Hunter's class training step ticked when they opened pet training)
    if s.o == op and op == 'train' and not npc and classTrainerOpen() == false then who = false end
    if s.o == op and op == 'train' and s.sp and not who and npc and classTrainerOpen() then who = true end
    if s.o == op and not s.buy and who then ns.cdb.done[s.k] = true hit = true trainedTo(s) end
  end
  if hit then ns.MarkDirty('latch') end
end

function Engine.OnScreen() return onScreen() end

--- quest items for the steps on screen and just after: a `use` step's item, or the item a quest gives you to use
local function wantedItems()
  local out, seen = {}, {}
  local steps = onScreen()
  local now = {}
  for _, i in ipairs(steps) do now[i] = true end
  for _, i in ipairs(view.upcoming or {}) do steps[#steps + 1] = i end
  for _, i in ipairs(steps) do
    local s = route.steps[i]
    local items = {}
    if (s.o == 'use' or s.o == 'equip') and s.id then items[1] = s.id end   -- a button equips gear when clicked
    if s.o == 'accept' and s.fi then items[#items + 1] = s.fi end           -- right-click it to start the quest
    -- a hearth on the card: the Hearthstone on a button, one click (the RestedXP audit, Oct 18)
    if s.o == 'hearth' and now[i] then items[#items + 1] = HEARTHSTONE_ITEM end
    for _, q in ipairs(E.quests(s)) do
      local info = route.pack.quests and route.pack.quests[q]
      if info and info.si and st.log[q] then items[#items + 1] = info.si end
      if info and info.ui and st.log[q] then   -- other items used for it (a Flare Gun, a Cleansing Bowl)
        for _, u in ipairs(info.ui) do items[#items + 1] = u end
      end
    end
    for _, id in ipairs(items) do
      if not seen[id] then seen[id] = true out[#out + 1] = id end
    end
  end
  return out
end

--- is the quest log's objective called `name` (lon) finished? ("10/10 Mottled Boar slain", "8/8 Scorpid Tail")
local function namedDone(s, name)
  for _, q in ipairs(E.quests(s)) do
    if st.completed[q] then return true end
    local e = st.log[q]
    for _, o in ipairs(e and e.obj or {}) do
      if ns.Text.ObjectiveName(o) == name then return o.fin end
    end
  end
  return false
end

--- a stop still worth walking to: one of the objectives it's for (lo) isn't done yet (stops with no list always are)
local function stopWanted(s, j)
  local tags = s.lo and s.lon and s.lo[j]
  if not tags or #tags == 0 then return true end
  for _, t in ipairs(tags) do
    if s.lon[t] and not namedDone(s, s.lon[t]) then return true end
  end
  return false
end

--- from stop j round the loop, the first still worth walking to (j when none is: then every stop counts)
local function nextWanted(s, j)
  local n = #s.lp
  for k = 0, n - 1 do
    local i = (j - 1 + k) % n + 1
    if stopWanted(s, i) then return i end
  end
  return j
end

--- a loop drawn as a line: its last stop is far from its first (the owner in Redridge, Nov 11: at the east end of the
--- goretusks' line the arrow turned 90 degrees to its first stop, 350 yards west over the hill). Such a loop is walked
--- there and back; a ring goes round
local AREA_OP = { complete = true, kill = true, collect = true, use = true }
local AREA_LEAVE, AREA_LEAVE_YARDS = 0.5, 250
local openLoops = setmetatable({}, { __mode = 'k' })
local OPEN_GAP_YARDS, OPEN_GAP_LEGS = 150, 1.5
local function openLoop(s)
  local v = openLoops[s]
  if v == nil then
    v = false
    local pts, n = route.pack.pts, #s.lp
    if n >= 3 then
      local longest = 0
      for j = 1, n - 1 do longest = math.max(longest, ns.Geo.Between(pts[s.lp[j]], pts[s.lp[j + 1]]) or math.huge) end
      local gap = ns.Geo.Between(pts[s.lp[n]], pts[s.lp[1]])
      v = gap ~= nil and gap > OPEN_GAP_YARDS and gap > longest * OPEN_GAP_LEGS
    end
    openLoops[s] = v
  end
  return v
end

--- the stop after `past`: round a ring, there and back along a line
local function onward(s, past)
  local n = #s.lp
  if not openLoop(s) then return nextWanted(s, past % n + 1) end
  local dir = ns.cdb.loopDir[s.k] or 1
  if past >= n then dir = -1 elseif past <= 1 then dir = 1 end
  ns.cdb.loopDir[s.k] = dir
  local j, d = past, dir
  for _ = 1, 2 * n do
    j = j + d
    if j > n then d, j = -1, n - 1 elseif j < 1 then d, j = 1, 2 end
    if stopWanted(s, j) then return j end
  end
  return math.max(1, math.min(n, past + dir))
end

--- the loop stop a step is at (kept per character): the nearest one the first time, then round the loop, leaving out
--- the stops for objectives already done
local LOOP_FOLD = 2   -- a stop ahead is passed when the loop's way to it is at most this many straight lines long
local LOOP_REJOIN_YARDS = 150   -- this far from a loop's marked stop, a stop half as far takes over
local function loopStop(s)
  if not (s.lp and #s.lp > 0) then return nil end
  local i = ns.cdb.loops[s.k]
  -- (rejoined from elsewhere, or walked the other way round: a stop much nearer than the marked one takes over;
  -- Nov 8, the RestedXP arrow study, sent 265 yards across a ring with the nearest stop 100 yards off)
  if i and i <= #s.lp then
    local here = ns.Geo.YardsTo(route.pack.pts[s.lp[i]])
    if here and here > LOOP_REJOIN_YARDS then
      local bj, bd
      for j, pi in ipairs(s.lp) do
        local d = stopWanted(s, j) and ns.Geo.YardsTo(route.pack.pts[pi])
        if d and (not bd or d < bd) then bj, bd = j, d end
      end
      -- (not the stop you stand at: arriving there moves the marker on, checkArrival)
      if bj and bd and bd > LOOP_YARDS and bd < here / 2 then i = bj end
    end
  end
  if not i or i > #s.lp then
    local bd
    i = 1
    for j, pi in ipairs(s.lp) do
      local d = stopWanted(s, j) and ns.Geo.YardsTo(route.pack.pts[pi])
      if d and (not bd or d < bd) then i, bd = j, d end
    end
  end
  i = nextWanted(s, i)
  if shown(s) then ns.cdb.loops[s.k] = i end
  return i
end
Engine.LoopStop = loopStop

--- where to join a step's walked path: at its point nearest you (someone arriving from another side isn't sent back to
--- its first point), or straight to the step's spot when that's nearer than any of them. A climb (every point close
--- round the spot: a ramp up a tree, stairs, a cave mouth) is taken from its first point, since where you stand on the
--- map says nothing of which floor you're on, unless you're at the spot already (Oct 11: Aldrassil's ramps)
local CLIMB_YARDS, AT_SPOT_YARDS = 100, 6
local JUMP_YARDS, JUMP_FROM_YARDS = 300, 60   -- a leap this far in a moment is a portal or a teleport; from this close
                                             -- to a walk's stop, it went through that stop
local OFF_WALK_YARDS = 150   -- this far off a walk's line, and nearer its end than its stop: you went another way
local FAR_PAST_YARDS = 600   -- this far from a walk's stop and nearer its end than the stop is: gone past it (a boat)
--- every point of the path close round the spot: stairs or a ramp up to it, not a way across the land
-- a walk that may lead indoors (a mine, a cave, a building): its last point stands well off its end, and you're outdoors.
-- Close to its end on the map then isn't there: the end can lie under your feet (Nov 8, the owner on the Gold Coast
-- Quarry's floor, 17 yards from the Riverpaw Miners below by the map: the walk into the mine counted as done and the
-- arrow pointed down at them from above). Indoors, near the end is near the end.
local ABOVE_YARDS = 60     -- this close to a walk's end by the map, outdoors, you may be over it, not at it
local function leadsIn(s)
  -- (only a step the route marks [inside]: guessed from the walk's shape it took 1,100 outdoor walks for caves and sent
  -- players 241 yards back, the RestedXP arrow study, Nov 8; and a person you talk to is reached where you stand, FB-028)
  if not (s.ind and s.p and s.pa and #s.pa > 0) then return false end
  if IsIndoors and ns.clean(IsIndoors()) then return false end
  local pts = route.pack.pts
  local d = ns.Geo.Between(pts[s.pa[#s.pa]], pts[s.p])
  local you = ns.Geo.YardsTo(pts[s.p])
  return d ~= nil and you ~= nil and d > ARRIVE_YARDS and you <= ABOVE_YARDS and you < d
end

local function climbing(s)
  local pts = route.pack.pts
  if not s.p then return false end
  for _, pi in ipairs(s.pa) do
    local dd = ns.Geo.Between(pts[pi], pts[s.p])
    if not dd or dd > CLIMB_YARDS then return false end
  end
  return true
end

-- A walk's doors (s.pd: a portal, a lift's end; links.yaml `doors`): the way on is only through them. The arrow never
-- joins a walk past a door you aren't through, nor counts one passed for being far off and nearer the end, nor for
-- standing beside it: it's behind you once you stand where it lets out (the pack's `doors` regions) or leap away from
-- beside it (checkArrival). Nov 5, the owner in Dolanaar: Rut'theran's flight master, at the tree's foot, was nearer
-- than the portal in Darnassus, so the arrow joined the walk past the portal and pointed down the tree.
local function inBox(b, x, y) return x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] end

--- you stand in a region (links.yaml specs: map, box, outside, except)
local function standIn(specs)
  local pos = st.pos
  if not (specs and pos and pos.map) then return false end
  for _, d in ipairs(specs) do
    if d.map == pos.map then
      if not (d.box or d['except']) then return true end
      if pos.x then
        local inside = not d.box or inBox(d.box, pos.x, pos.y)
        if d.box and d.outside then inside = not inside end
        for _, e in ipairs(d['except'] or {}) do
          if inside and inBox(e, pos.x, pos.y) then inside = false end
        end
        if inside then return true end
      end
    end
  end
  return false
end

local function isDoor(s, j) return s.pd ~= nil and s.pd[j] ~= nil end

--- through the walk's door j: you stand where it lets out
local function through(s, j)
  local into = s.pd and s.pd[j]
  return into ~= nil and standIn(route.pack.doors and route.pack.doors[into])
end

--- in through a way in (a city's gate): the walk's next point is on another map than this one, and you're on that map
--- now (Nov 5: Darnassus's gate, on Teldrassil's map, once you're in the city)
local function entered(s, j)
  local pos, pts = st.pos, route.pack.pts
  local a = pts[s.pa[j]]
  local b = s.pa[j + 1] and pts[s.pa[j + 1]] or (s.p and pts[s.p])
  return (a and b and pos and pos.map and a[1] ~= b[1] and pos.map == b[1] and pos.map ~= a[1]) and true or false
end

--- a door ahead of j (j itself too) you aren't through
local function doorAhead(s, j)
  if not s.pd then return false end
  for k = j, #s.pa do
    if isDoor(s, k) and not through(s, k) then return true end
  end
  return false
end

local function pathEntry(s)
  local pts = route.pack.pts
  local direct = s.p and ns.Geo.YardsTo(pts[s.p])
  if direct and direct <= AT_SPOT_YARDS and not leadsIn(s) then return #s.pa + 1 end
  local climb = s.p and true
  for _, pi in ipairs(s.pa) do
    local d = s.p and ns.Geo.Between(pts[pi], pts[s.p])
    if not d or d > CLIMB_YARDS then climb = false break end
  end
  if climb then return 1 end
  -- the stretch you're on: after the last door you're through, up to the first one you aren't
  local lo, hi, door = 1, #s.pa, false
  if s.pd then
    for j = #s.pa, 1, -1 do if isDoor(s, j) and through(s, j) then lo = j + 1 break end end
    for j = lo, #s.pa do if isDoor(s, j) then hi, door = j, true break end end
  end
  if lo > #s.pa then return #s.pa + 1 end
  local best, bestD = lo, nil
  for j = lo, hi do
    local d = ns.Geo.YardsTo(pts[s.pa[j]])
    if not d then return lo end
    if not bestD or d <= bestD then best, bestD = j, d end
  end
  if not door and direct and bestD and direct < bestD and not leadsIn(s) then return #s.pa + 1 end
  return best
end

--- the next point of a step's walked path (kept per character), or nil once you've been through them all
local function pathStop(s)
  if not (s.pa and #s.pa > 0) then return nil end
  ns.cdb.paths = ns.cdb.paths or {}
  local i = ns.cdb.paths[s.k]
  if not i then
    i = pathEntry(s)
    if not shown(s) then return i <= #s.pa and i or nil end   -- (looked at ahead of its card: not kept)
    ns.cdb.paths[s.k] = i
    -- where you joined it: past its first stop, the walk's own words (written from its start) don't fit (Nov 7, the
    -- owner's daughter in Elwynn: "Leave Stormwind by the main gate" when she was never in Stormwind)
    ns.cdb.pathJoin = ns.cdb.pathJoin or {}
    ns.cdb.pathJoin[s.k] = i
    if i > 1 and i <= #s.pa and s.sy then ns.MarkDirty('path') end   -- (the card drawn before this had its words)
  end
  if i > #s.pa then return nil end
  -- already at the person, whatever way you came: the rest of the way is moot (FB-028, Oct 18: beside Grund Drokda,
  -- the arrow still led round to Anvilmar's door, 108 yd off). Close by and nearer the spot than the next point
  -- counts too, except on a climb, where the floor above can be a few yards off on the map
  local pts = route.pack.pts
  local direct = s.p and ns.Geo.YardsTo(pts[s.p])
  if direct and not leadsIn(s) and (direct <= AT_SPOT_YARDS or (direct <= ARRIVE_YARDS and not climbing(s)
      and direct < (ns.Geo.YardsTo(pts[s.pa[i]]) or math.huge))) then
    ns.cdb.paths[s.k] = #s.pa + 1
    ns.MarkDirty('path')
    return nil
  end
  -- behind you: a door you're through, a way in you're in through, or a stop you were carried past (a boat, a flight:
  -- far from it and nearer the walk's end than it is; with a door ahead you aren't through, nearer the next point than
  -- it is, since the land beyond a door can lie anywhere, Teldrassil's foot right under its top)
  local moved = i
  while i <= #s.pa do
    local pass
    if isDoor(s, i) then
      pass = through(s, i)
    else
      pass = entered(s, i)
      if not pass and direct then
        local here = ns.Geo.YardsTo(pts[s.pa[i]])
        local ahead = doorAhead(s, i + 1) and s.pa[i + 1]
        local nxt = ahead and ns.Geo.YardsTo(pts[ahead])
        local left = ns.Geo.Between(pts[s.pa[i]], pts[ahead or s.p])
        pass = here and left and here > FAR_PAST_YARDS and (nxt or direct) < left
        -- or you went another way: well off the walk's line from this point on, and nearer its end than the point is
        -- (Nov 8, FB-047: the walk to Theocritus over the hills east of Northshire, joined there; a player who took
        -- the road by Goldshire was pulled back to the hillside, "the marker is in the wrong spot, there is no npc
        -- here". A cave's mouth stays: outside it you're on the walk's line)
        if not pass and not ahead and here and left and direct < left and not leadsIn(s) then
          local off = ns.Geo.YardsToLine(pts[s.pa[i]], pts[s.pa[i + 1] or s.p])
          pass = off ~= nil and off > OFF_WALK_YARDS
        end
      end
    end
    if not pass then break end
    i = i + 1
  end
  if i ~= moved then ns.cdb.paths[s.k] = i ns.MarkDirty('path') end
  if i > #s.pa then return nil end
  return i
end
Engine.PathStop = pathStop

--- a walk whose stops are all behind you (its own words were about the way there)
--- the step a walk leads to: the next one still to do, when it stands where the walk ends (a talk at the walk's end)
local WALK_END_YARDS = 40
function Engine.WalkLeadsTo(s)
  if not (route and view and view.status and s and s.p) then return nil end
  local pts = route.pack.pts
  local i = view.cursor
  if not (i and route.steps[i] == s) then return nil end   -- (only the walk you're on: Up Next keeps its own rows)
  for j = i + 1, math.min(#route.steps, i + 6) do
    local n, v = route.steps[j], view.status[j]
    if v == E.PENDING and not (n.opt or n.sticky or n.tl or n.wn) then
      if n.p and pts[n.p] and pts[s.p] and (ns.Geo.Between(pts[n.p], pts[s.p]) or 1e9) <= WALK_END_YARDS then return n end
      return nil
    end
  end
  return nil
end

function Engine.PathDone(s)
  local i = s and s.pa and #s.pa > 0 and ns.cdb and ns.cdb.paths and ns.cdb.paths[s.k]
  return i and i > #s.pa or false
end

-- ------------------------------------------------------------------------------------------- a faster way there
-- When the step in front of you is a long way off on foot, the card offers a faster way, worked out where you stand:
-- your Hearthstone when it's ready and lands much nearer, else a flight between flight paths you know (Nov 5, the
-- owner in Darnassus after a detour to Auberdine: Denalan 1,626 yd away on foot, Dolanaar's inn 405 yd from him, the
-- stone ready, and the guide never said so). Quiet when the route plans a hearth or a flight of its own just ahead.
local FAR_YARDS, SAVES_YARDS, LANDS_NEAR_YARDS, FM_NEAR_YARDS, AHEAD_STEPS = 1200, 800, 1200, 800, 15

local function stepIndex(s)
  local index = route.keyIndex
  if not index then
    index = {}
    for j, t in ipairs(route.steps) do index[t.k] = j end
    route.keyIndex = index
  end
  return index[s.k]
end

--- flight node -> { pt = its flight master's spot, name }: every flight master the game has (each pack's `fm`, from
--- TaxiNodes), with the routes' own flight steps first (their spots are the ones the routes walk to). From every loaded
--- pack, not only this guide's: until Nov 13 a guide knew only the flight masters its own pack's routes stepped to, and
--- the fishing guide at Booty Bay's flight master walked 5,788 yards to Redridge (the owner; the free packs had no
--- Booty Bay, the professions pack no flight master at all)
local spotsRev, spotsAll
local function nodeSpots(pack)
  local rev = (ns.Packs.namesRev or 0) .. ':' .. tostring(ns.st and ns.st.faction)
  if spotsAll and spotsRev == rev then return spotsAll end
  local out = {}
  local function steps(pk)
    for _, r in ipairs(pk.routes or {}) do
      for _, t in ipairs(r.steps or {}) do
        if (t.o == 'fp' or t.o == 'fly') and type(t.id) == 'number' and t.p and pk.pts and pk.pts[t.p] and not out[t.id] then
          out[t.id] = { pt = pk.pts[t.p], name = t.name or ns.L.node:format(t.id) }
        end
      end
    end
  end
  -- (only your side's and both sides': the Horde's Booty Bay flight master stands beside the Alliance's)
  local mine = ns.st and ns.st.faction
  mine = mine == 'alliance' and 'A' or mine == 'horde' and 'H' or nil
  local function masters(pk)
    for _, f in ipairs(pk.fm or {}) do
      local id = tonumber(f[1])
      if id and not out[id] and f[2] and (not mine or not f[6] or f[6] == 'B' or f[6] == mine) then
        out[id] = { pt = { f[2], f[3], f[4] }, name = (f[5] ~= '' and f[5]) or ns.L.node:format(id) }
      end
    end
  end
  if pack then steps(pack) end
  for _, pk in pairs(ns.Packs.byId or {}) do steps(pk) end
  if pack then masters(pack) end
  for _, pk in pairs(ns.Packs.byId or {}) do masters(pk) end
  spotsAll, spotsRev = out, rev
  return out
end
Engine.NodeSpots = nodeSpots

--- where your Hearthstone lands: the inn the route bound you at (its sethome step), if it's in this pack
local function homeSpot(pack)
  local npc = st.bindNpc
  if not npc then return nil end
  for _, r in ipairs(pack.routes or {}) do
    for _, t in ipairs(r.steps or {}) do
      if t.o == 'sethome' and t.npc == npc and t.p and pack.pts[t.p] then return pack.pts[t.p] end
    end
  end
  return nil
end

local function stoneReady()
  local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(HEARTHSTONE_ITEM)) or 0
  return (ns.clean(n) or 0) > 0 and not ns.Text.HearthLeft()
end

--- the faster way to this step, in words, or nil
function Engine.FasterWay(s)
  if not (route and s and s.p) or s.o == 'fly' or s.o == 'fp' or s.o == 'hearth' or s.o == 'enter' then return nil end
  local pack = route.pack
  local target = pack.pts[s.p]
  local far = target and ns.Geo.YardsTo(target)
  if not far or far < FAR_YARDS then return nil end
  local i = stepIndex(s)
  local who = Engine.Who()
  -- the route's own way: a flight just ahead, or a planned hearth within the stone's hour (it keeps the stone for it;
  -- the hour by the plan's levels at about the pace of play, a level 10-60 taking 45 to 220 minutes)
  local hold, cur = false, s.pl or who.level or 1
  for j = i or 1, #route.steps do
    local t = route.steps[j]
    -- (only the road's flights and hearths still to come: a flight taken on an earlier pass kept the card quiet in
    -- Ironforge, 5,666 yards from Salma Saldean with Sentinel Hill's flight known; the owner, Nov 7)
    local left = not (view and view.status and view.status[j]) or view.status[j] == E.PENDING
    if left and E.applies(t, who) then
      if t.o == 'fly' and j <= (i or 1) + AHEAD_STEPS then return nil end
      if t.o == 'hearth' then
        hold = not t.pl or (t.pl - cur) * (cur < 7 and 18 or 10 + 3.5 * cur) < 60
        break
      end
    end
  end
  local home = homeSpot(pack)
  local fromHome = home and ns.Geo.Between(home, target)
  if not hold and fromHome and far - fromHome >= SAVES_YARDS and stoneReady() then
    return ns.L.fasterHearth:format(st.bind or ns.L.hearthAny, math.floor(fromHome / 10 + 0.5) * 10)
  end
  local land, landYards, depart, departYards
  for id, spot in pairs(nodeSpots(pack)) do
    if st.taxi and st.taxi[id] then
      local a, b = ns.Geo.Between(spot.pt, target), ns.Geo.YardsTo(spot.pt)
      if a and (not landYards or a < landYards) then land, landYards = id, a end
      if b and (not departYards or b < departYards) then depart, departYards = id, b end
    end
  end
  -- (a long trip counts a flight master further off: a dungeon guide opened a zone or two away, Nov 6; a guide's own
  -- trip card flies you when a flight is worth it, from the land you're in, so the card doesn't offer one: Nov 7)
  if not route.kd and land and depart and land ~= depart and landYards <= LANDS_NEAR_YARDS
      and ((departYards <= FM_NEAR_YARDS and far - landYards >= SAVES_YARDS)
        or (departYards <= far / 3 and far - landYards - departYards >= SAVES_YARDS)) then
    return ns.L.fasterFly:format(nodeSpots(pack)[land].name, math.floor(departYards / 10 + 0.5) * 10)
  end
  -- no quicker way: say it's a trip to another zone, so nobody walks 2,000 yards not knowing where to (Nov 7)
  local mine = st.pos and st.pos.map
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(target[1])
  local zone = not (info and ns.clean(info.mapType) and ns.clean(info.mapType) <= 2)   -- (a continent's map: no name)
  if mine and zone and not st.inst and target[1] ~= mine and ns.Text.Map(target[1]) ~= ''
      and ns.Text.Map(target[1]) ~= ns.Text.Map(mine) then
    return ns.L.travelWalk:format(ns.Text.Map(target[1]), math.floor(far / 10 + 0.5) * 10)
  end
  return nil
end

--- a flight as a part of a guide's trip (Nov 7, the owner's Deadmines guide in Stormwind: Alba Fairmoon 1,942 yards
--- off through the city wall, no word of Westfall, no flight): to a spot far off on your continent, between flight
--- paths you know, leaving from the land you stand in. { point = the flight master's spot, name = where you land },
--- { flying = true, name } while you're in the air, or nil. `myLand` and `landOf(p)` from Nav/Travel.lua
function Engine.FlightLeg(goal, myLand, landOf, goalLand, landAt)
  if not (route and goal and ns.Geo) then return nil end
  local pack = route.pack
  local far = ns.Geo.YardsTo(goal)
  if not far or far < FAR_YARDS then return nil end
  local land, landYards, depart, departYards
  for id, spot in pairs(nodeSpots(pack)) do
    if st.taxi and st.taxi[id] then
      local a, b = ns.Geo.Between(spot.pt, goal), ns.Geo.YardsTo(spot.pt)
      -- (it lands in the stop's own land: Ratchet is 1,154 yards from Sen'jin across the river, and the walk from
      -- there went north by the road, back to a flight master, and round again; the dungeon walk, Nov 7)
      if a and (not landYards or a < landYards) and (not goalLand or landAt(spot.pt) == goalLand) then
        land, landYards = id, a
      end
      if b and (not departYards or b < departYards) and (not myLand or landOf(spot.pt) == myLand) then
        depart, departYards = id, b
      end
    end
  end
  -- (on a long trip the landing may be further from the stop: Camp Mojache for a spot deep in Feralas, 6,470 yards
  -- on foot otherwise; the savings below still have to hold)
  if not (land and depart and land ~= depart and landYards <= math.max(LANDS_NEAR_YARDS, far / 2)) then return nil end
  local name = nodeSpots(pack)[land].name
  if UnitOnTaxi and ns.clean(UnitOnTaxi('player')) then return { flying = true, name = name } end
  if (departYards <= FM_NEAR_YARDS and far - landYards >= SAVES_YARDS)
      or (departYards <= far / 3 and far - landYards - departYards >= SAVES_YARDS) then
    return { point = nodeSpots(pack)[depart].pt, name = name, land = nodeSpots(pack)[land].pt, node = land }
  end
  return nil
end

--- a flight path you don't know yet, close by: a guide stops for it on the way (Nov 7, the owner: "the guide should
--- always have a player grab a new FP when near it and utilize it"; their Night Elf walked past Sentinel Hill's).
--- { point, name, id } or nil
-- (and one near the stop you've come to, though the road in didn't pass it: Lakeshire's flight master is across the
-- town from Wiley's inn; the owner, Nov 7, "I had to manually grab the FP")
local LEARN_FP_YARDS, LEARN_AT_STOP_YARDS = 250, 700
function Engine.NearbyFlightPath(goal)
  if not (route and ns.Geo) then return nil end
  local atStop = goal and ns.Geo.YardsTo(goal)
  atStop = atStop and atStop <= LEARN_AT_STOP_YARDS
  local best, bestYards
  for id, spot in pairs(nodeSpots(route.pack)) do
    if not (st.taxi and st.taxi[id]) then
      local d = ns.Geo.YardsTo(spot.pt)
      local near = d and (d <= LEARN_FP_YARDS
        or (atStop and d <= LEARN_AT_STOP_YARDS + LEARN_FP_YARDS
            and (ns.Geo.Between(spot.pt, goal) or math.huge) <= LEARN_AT_STOP_YARDS))
      if near and (not bestYards or d < bestYards) then best, bestYards = id, d end
    end
  end
  return best and { point = nodeSpots(route.pack)[best].pt, name = nodeSpots(route.pack)[best].name, id = best } or nil
end

--- a quest your leveling road takes, its giver beside you, while another guide leads (a dungeon, profession or Legacy
--- guide): take it as you pass (Nov 9, the owner's daughter on the Deadmines guide walked past Guard Parker at
--- Redridge's door on the way to Lakeshire; her Redridge leg later sent her back for Encroaching Gnolls). The road's own
--- view says what it can offer now; one you skipped stays skipped. { point, npc, quest, quests } or nil
local PASS_BY_YARDS = 80
function Engine.PassByQuest()
  if not (levRoute and levView and levView.status and ns.Geo and route and route ~= levRoute) then return nil end
  local level = ns.clean(UnitLevel and UnitLevel('player')) or 0
  local passed = ns.cdb.passBy or {}
  local profs = Engine.Who().profs or {}
  -- (a craft's quest that asks for more skill than you have waits on the road, so it isn't offered here either: FB-071,
  -- Nov 14, a Mage on the Library guide was sent to Doctor Gustaf VanHowzen for Triage, First Aid 225)
  local function skillShort(s)
    if not s.skr then return false end
    local p = type(s.prof) == 'table' and s.prof[1] or s.prof
    local rank = p and profs[p]
    return not (type(rank) == 'number' and rank >= s.skr)
  end
  local function near(r, s)
    local pts = r.pack and r.pack.pts
    return s.o == 'accept' and s.p and pts and pts[s.p] and not (s.opt or s.grp) and not skillShort(s)
      and ns.Geo.YardsTo(pts[s.p]) or nil
  end
  local function scan(r, v)
    local best, bestYards
    for i, s in ipairs(r.steps) do
      local d = v.status[i] == E.PENDING and near(r, s)
      if d and d <= PASS_BY_YARDS and (not bestYards or d < bestYards) then
        local ok = true
        for _, q in ipairs(E.quests(s)) do
          local info = r.pack.quests and r.pack.quests[q]
          if st.log[q] or st.completed[q] or passed[q] or (info and info.min and info.min > level) then ok = false end
          -- (only what the giver offers you now: its quests before it done. Guard Parker's Visit the Herbalist waits
          -- for A Watchful Eye; QuestieDB's negative one is "in your log")
          local function have(p) if p < 0 then return st.log[-p] or st.completed[-p] end return st.completed[p] end
          for _, p in ipairs(info and info.pre or {}) do if not have(p) then ok = false end end
          if info and info.pre1 and #info.pre1 > 0 then
            local one = false
            for _, p in ipairs(info.pre1) do if have(p) then one = true end end
            if not one then ok = false end
          end
        end
        if ok then best, bestYards = i, d end
      end
    end
    return best
  end
  local r, best = levRoute, scan(levRoute, levView)
  -- (and the leg after yours, read only when one of its givers is close: the Deadmines errands come on the Westfall
  -- leg, Guard Parker's quest on the Redridge leg after it)
  local nxt = not best and levRoute.nx and ns.Packs.Get(levRoute.nx)
  if nxt then
    local close = false
    for _, s in ipairs(nxt.steps) do
      local d = near(nxt, s)
      if d and d <= PASS_BY_YARDS then close = true break end
    end
    if close then
      local v = E.evaluate(nxt, st, prog(), nxt.pack, Engine.Who(), { upcoming = 0 })
      if v and v.status then r, best = nxt, scan(nxt, v) end
    end
  end
  if not best then return nil end
  local s = r.steps[best]
  local qs = E.quests(s)
  -- (the giver is the step's `who`, a list: Nov 13, the tour's example showed the card had never named anyone)
  local giver = (s.who and s.who[1]) or s.npc
  return { point = r.pack.pts[s.p], npc = giver and ns.Text.Npc(giver, r.pack) or nil,
           quest = ns.Text.Quest(qs[1], r.pack), quests = qs }
end

--- a flight path to learn where the route doesn't fly from it next: you'll use it later (Nov 5, the owner flew to
--- Auberdine from Rut'theran when the route only came for the flight path)
function Engine.FlyLater(s)
  if not (route and s and s.o == 'fp') then return false end
  local i = stepIndex(s)
  if not i then return false end
  local who, seen = Engine.Who(), 0
  for j = i + 1, #route.steps do
    local t = route.steps[j]
    if E.applies(t, who) then
      if t.o == 'fly' then return false end
      seen = seen + 1
      if seen >= 4 then break end
    end
  end
  return true
end

--- a hand-in of a quest in your log that isn't done yet: the route's step that does its objectives (the last one
--- before the hand-in that isn't an as-you-go line, else any), where the arrow goes first
local function finishStep(i)
  local s = route.steps[i]
  local q = s and s.o == 'turnin' and ((type(s.id) == 'table' and s.id[1]) or s.id)
  local e = q and st.log[q]
  if not (e and not e.ready) then return nil end
  local best, any
  for j = 1, #route.steps do
    local t = route.steps[j]
    if t.o == 'complete' and (t.p or t.lp) then
      for _, id in ipairs(ns.list(t.id)) do
        if id == q then
          any = any or j
          if j < i and not t.sticky then best = j end
        end
      end
    end
  end
  return best or any, q
end

--- where a flight leaves from: its flight master's spot, until you're in the air (Nov 7, the Skyborne pass: in Thunder
--- Bluff "Fly to Orgrimmar" pointed 5,211 yards north-east over the bluff's edge, not at Tal across the rise)
local function flyFrom(s)
  if not (s and s.o == 'fly' and s.dp and route and route.pack.pts[s.dp]) then return nil end
  if UnitOnTaxi and ns.clean(UnitOnTaxi('player')) then return nil end
  return route.pack.pts[s.dp]
end
Engine.FlyFrom = flyFrom

local function waypointFor(i)
  local s = i and route.steps[i]
  if not s then return nil end
  local fin, fq = finishStep(i)
  if fin then   -- not done yet: to its objective first, named so
    local t = waypointFor(fin)
    if t then t.name = ns.L.finishArrow:format(ns.plain(ns.Text.Quest(fq, route.pack))) return t end
  end
  local via = pathStop(s)
  if via then   -- the way there first, point by point
    local p = route.pack.pts[s.pa[via]]
    return p and { key = s.k .. ':p' .. via, map = p[1], x = p[2], y = p[3], name = ns.Text.Step(s, route.pack),
                   reach = PATH_YARDS, pass = true } or nil
  end
  local stop = loopStop(s)
  if stop then
    local p = route.pack.pts[s.lp[stop]]
    return p and { key = s.k .. ':' .. stop, map = p[1], x = p[2], y = p[3], name = ns.Text.Step(s, route.pack),
                   reach = LOOP_YARDS, pass = true } or nil
  end
  local from = flyFrom(s)
  if from then
    return { key = s.k .. ':from', map = from[1], x = from[2], y = from[3],
             name = s.dn and ns.Text.Npc(s.dn, route.pack) or ns.Text.Step(s, route.pack), reach = 10 }
  end
  local p = s.p and route.pack.pts[s.p]
  if s.o == 'hearth' and not p then
    -- a hearth has no spot of its own: the arrow points where it takes you, the next step's spot, so a player whose
    -- stone is cooling down, or who'd rather walk, still has a way (FB-019: on "Hearth to Camp Narache" it went away).
    -- The first one there still to do: a giver you've already seen is behind you (Nov 5, Returning Home done early)
    local first
    for j = i + 1, math.min(#route.steps, i + 40) do
      local n = route.steps[j]
      if n.o == 'hearth' then break end
      local v = view and view.status and view.status[j]
      if n.p and route.pack.pts[n.p] and v ~= E.NA then
        first = first or j
        if v == nil or v == E.PENDING then first = j break end
      end
    end
    local t = first and waypointFor(first)
    if t then t.key, t.name, t.hearth = s.k, ns.Text.Step(s, route.pack), true return t end
  end
  local quest = s.q or ((s.o == 'complete') and (type(s.id) == 'table' and s.id[1] or s.id)) or nil
  -- (an escort's or a defend's step: to where it ends, ours. The game's quest marker stays where it starts, so the
  -- arrow pointed back into Ban'ethil Barrow Den all the way out with Lynessa; Nov 5)
  local info = quest and route.pack.quests and route.pack.quests[quest]
  local target = { key = s.k, quest = quest,
                   hybrid = quest ~= nil and (s.ev or 0) >= 3 and s.o ~= 'turnin' and not (info and info.ne) }
  if p then target.map, target.x, target.y = p[1], p[2], p[3] end
  -- for the arrow: who or what is there, and how close counts as there
  local who = (s.who and s.who[1]) or s.npc
  target.name = who and ns.Text.Npc(who, route.pack) or ns.Text.Step(s, route.pack)
  target.reach = s.o == 'fly' and FLY_ARRIVE_YARDS or (s.o == 'goto' and (s.r or ARRIVE_YARDS)) or 10
  -- someone who walks: how far from this spot (Kashi's FB-020, FB-022: the arrow said "You're here" while Brave
  -- Windfeather was across the camp)
  target.walk = who and route.pack.walks and route.pack.walks[who] or nil
  if not p and not target.hybrid then return nil end
  return target
end

--- the person a talk stop is for, for the Waymark, with the pin of what's next at them
local MARK_ROLE = { accept = 'quest', turnin = 'turnin', vendor = 'vendor', train = 'trainer', rank = 'trainer',
                    sethome = 'inn', fp = 'flight' }
local function markPerson(stop)
  if not (stop and stop.kind == 'talk' and stop.who) then return nil end
  local first = ns.Stops.Pending(stop, view)[1] or stop.lead
  return { id = stop.who, name = route.pack.npcs and route.pack.npcs[stop.who], role = MARK_ROLE[route.steps[first].o] or 'quest',
           key = route.steps[stop.lead].k }
end

--- what the Waymark should show (only worked out when it's on): the one you need, the one after, and the enemies the
--- steps ask for, so an elite you're sent at gets no warning. finished: the last lead's steps are all done
local function markWants(leadStop, current, upcoming, targets)
  local out = { lead = markPerson(leadStop), fight = {} }
  for _, t in ipairs(targets) do if t.enemy then out.fight[#out.fight + 1] = t end end
  for _, list in ipairs({ current, upcoming }) do
    for _, stop in ipairs(list) do
      local p = stop ~= leadStop and markPerson(stop)
      if p and not out.nxt and not (out.lead and p.id == out.lead.id) then out.nxt = p end
    end
  end
  out.finished = markedStop ~= nil and markedStop.route == route.id
  if out.finished then
    for _, i in ipairs(markedStop.steps) do if view.status[i] == E.PENDING then out.finished = false end end
  end
  markedStop = leadStop and { route = route.id, steps = leadStop.steps } or nil
  return out
end

--- everyone the steps on screen name, for the Targets panel: the lead stop's first, then the rest; people to talk to
--- and enemies to kill (an objective already done drops its enemies, and an item's two nearest droppers count)
local function wantedTargets(leadStop)
  local out, seen = {}, {}
  local pack = route.pack
  -- role: what the socket's medallion says until a portrait shows (quest, turnin, vendor, trainer, inn, enemy, elite)
  local function add(id, enemy, name, role)
    name = name or (id and pack.npcs and pack.npcs[id])
    if not name or seen[name] then return end
    seen[name] = true
    if enemy then
      local lv = id and pack.npcl and pack.npcl[id]
      role = (lv and lv[3] and lv[3] > 0 and lv[3] ~= 4) and 'elite' or 'enemy'
    end
    out[#out + 1] = { name = name, enemy = enemy and true or false, id = id, role = role or 'quest' }
  end
  local ROLE = { accept = 'quest', turnin = 'turnin', vendor = 'vendor', train = 'trainer', sethome = 'inn' }
  local function objectives(q)
    local info = pack.quests and pack.quests[q]
    if not (info and info.how) then return end
    local e = st.log[q]
    local how = ns.Text.How(q, pack)
    local live = {}
    if e then   -- only what's still to do: each unfinished objective's how-to line
      for _, o in ipairs(e.obj) do
        if not o.fin then
          local h = ns.Text.HowFor(how, o, e.obj)
          for k, x in ipairs(how) do if x == h then live[k] = true end end
        end
      end
    end
    for k, h in ipairs(info.how) do
      if not e or live[k] then
        if h[1] == 'kill' then add(h[2], true)
        elseif h[1] == 'loot' then for j, sid in ipairs(h[3] or {}) do if j <= 2 then add(sid, true) end end end
      end
    end
  end
  local function fromStep(s)
    if s.tg then
      for _, id in ipairs(s.tg) do add(id, s.o ~= 'accept' and s.o ~= 'turnin' and s.o ~= 'vendor', nil, ROLE[s.o]) end
    end
    if s.o == 'kill' then for _, id in ipairs(ns.list(s.id)) do add(id, true) end
    elseif s.o == 'boss' then add(nil, true, s.name)
    elseif s.o == 'use' and s.on then add(s.on, true)
    elseif (s.o == 'accept' or s.o == 'turnin') and s.who then add(s.who[1], false, nil, ROLE[s.o])
    elseif s.npc and ROLE[s.o] then add(s.npc, false, nil, ROLE[s.o]) end
    if s.o == 'complete' or s.o == 'kill' or s.o == 'collect' or s.o == 'use' then
      for _, q in ipairs(E.quests(s)) do objectives(q) end
    end
  end
  local done = {}
  if leadStop then
    if leadStop.kind == 'talk' and leadStop.who then   -- the person; a turn-in waiting shows the ?
      local role = 'quest'
      for _, i in ipairs(leadStop.steps) do
        local o = route.steps[i].o
        if o == 'turnin' then role = 'turnin' break elseif ROLE[o] and o ~= 'accept' then role = ROLE[o] end
      end
      add(leadStop.who, false, nil, role)
    end
    for _, i in ipairs(leadStop.steps) do done[i] = true fromStep(route.steps[i]) end
  end
  for _, i in ipairs(onScreen()) do if not done[i] then fromStep(route.steps[i]) end end
  return out
end

--- arrival: goto and fly steps on screen are done once you're there
local lastSpot   -- where the ticker saw you a moment ago (world position) and when
local function checkArrival()
  if not (route and view) or peekIndex() then return end
  ns.State.Position()
  -- through a portal (or any teleport) from beside a walk's stop: that stop is behind you (Nov 5, the owner through
  -- Rut'theran's portal: the portal stop was never reached on foot, and the arrow pointed back down to it)
  local pos, jumpFrom = st.pos, nil
  local c, wx, wy
  if pos and pos.x then c, wx, wy = ns.Geo.World(pos.map, pos.x, pos.y) end
  if c and lastSpot and lastSpot.c == c and GetTime() - lastSpot.t <= 3
      and math.sqrt((wx - lastSpot.x) ^ 2 + (wy - lastSpot.y) ^ 2) > JUMP_YARDS then
    jumpFrom = lastSpot
  end
  lastSpot = c and { c = c, x = wx, y = wy, t = GetTime() } or nil
  if jumpFrom then
    for _, i in ipairs(onScreen()) do
      local s = route.steps[i]
      local k = s.pa and ns.cdb.paths and ns.cdb.paths[s.k]
      local p = k and s.pa[k] and route.pack.pts[s.pa[k]]
      local pc, px, py
      if p then pc, px, py = ns.Geo.World(p[1], p[2], p[3]) end
      if pc == jumpFrom.c and math.sqrt((px - jumpFrom.x) ^ 2 + (py - jumpFrom.y) ^ 2) <= JUMP_FROM_YARDS then
        ns.cdb.paths[s.k] = k + 1
        ns.MarkDirty('path')
      end
    end
  end
  for _, i in ipairs(onScreen()) do
    local s = route.steps[i]
    if (s.o == 'goto' or s.o == 'fly') and s.p then
      local d = ns.Geo.YardsTo(route.pack.pts[s.p])
      local reach = s.o == 'fly' and FLY_ARRIVE_YARDS or (s.r or ARRIVE_YARDS)
      if d and d <= reach then ns.cdb.done[s.k] = true ns.MarkDirty('arrived') end
    end
    -- a hearth you walked instead: done once you're where it lands (the arrow's spot), the stone kept for later
    if s.o == 'hearth' and not ns.cdb.done[s.k] then
      local t = waypointFor(i)
      local d = t and t.map and ns.Geo.YardsTo({ t.map, t.x, t.y })
      if d and d <= HEARTH_ARRIVE_YARDS then ns.cdb.done[s.k] = true ns.MarkDirty('arrived') end
    end
    local via = pathStop(s)
    if via and not isDoor(s, via) then   -- through a path point: on to the next (a door: once you're through it)
      local pts = route.pack.pts
      local d = ns.Geo.YardsTo(pts[s.pa[via]])
      -- (or walked past it to the side: close, and nearer the next point than it is. Nov 8, the RestedXP arrow study:
      -- 25 yards beside a walk, the arrow pointed back for 200 yards; their authors gave points 20-80 yard radii)
      local nxt = pts[s.pa[via + 1] or s.p]
      local past = d and nxt and d <= PATH_SIDE_YARDS and (ns.Geo.YardsTo(nxt) or math.huge) < (ns.Geo.Between(pts[s.pa[via]], nxt) or 0)
      if d and (d <= PATH_YARDS or past) then ns.cdb.paths[s.k] = via + 1 ns.MarkDirty('path') end
    end
    local stop = loopStop(s)
    if stop then   -- at a loop stop, or past it ahead of the marker: on to the next, round and round until it's done
      local n, past = #s.lp, nil
      local open, dir = openLoop(s), ns.cdb.loopDir[s.k] or 1
      local pts, last = route.pack.pts, nil
      -- (measured from the stop before the marked one, where you came from; a loop's first stop has none)
      local from = open and stop - dir or (stop - 2) % n + 1
      if from < 1 or from > n or n < 3 then from = stop end
      local way = from ~= stop and ns.Geo.Between(pts[s.lp[from]], pts[s.lp[stop]]) or 0
      -- (far from the marked stop you aren't on your way to it: you joined the loop here, and the stop you stand at
      -- counts, as a stop half as far does in loopStop)
      local joined = from == stop or (ns.Geo.YardsTo(pts[s.lp[stop]]) or math.huge) > LOOP_REJOIN_YARDS
      for k = 0, math.min(3, n - 1) do   -- a few stops ahead: an out-and-back loop keeps its far end
        local j = open and stop + dir * k or (stop - 1 + k) % n + 1
        if j < 1 or j > n then break end
        if last then way = way + (ns.Geo.Between(pts[s.lp[last]], pts[s.lp[j]]) or 0) end
        last = j
        local d = ns.Geo.YardsTo(pts[s.lp[j]])
        -- (a stop ahead counts only when the loop runs on to it about as straight as you could have walked: where
        -- the loop folds back beside itself the stop next to you is the far side's, and the stops between are still
        -- to walk. FB-061, Nov 12: among Stranglethorn's young tigers the arrow said 85 yards west, then 350 east)
        local straight = k > 0 and ns.Geo.Between(pts[s.lp[from]], pts[s.lp[j]])
        if d and d <= LOOP_YARDS and (k == 0 or joined or (straight and way <= straight * LOOP_FOLD)) then past = j end
      end
      if past then ns.cdb.loops[s.k] = onward(s, past) ns.MarkDirty('loop') end
    end
  end
end

local function needsTicker()
  for _, i in ipairs(onScreen()) do
    local o = route.steps[i].o
    if o == 'goto' or o == 'fly' or o == 'hearth' or route.steps[i].blk or route.steps[i].lp or route.steps[i].pa then
      return true
    end
  end
  return false
end

-- whether each walk on screen still shows its own words (Text.WayDone: they stay while you stand at its last stop, the
-- zeppelin tower or the portal); the card is drawn again the moment that changes, as you step off or through
local lastWords
local function wordsShown()
  local sig = {}
  for _, i in ipairs(onScreen()) do
    local s = route.steps[i]
    if s.sy and s.pa then sig[#sig + 1] = ns.Text.WayDone(s) and '1' or '0' end
  end
  return table.concat(sig)
end

local function updateTicker()
  local want = route and view and not view.done and needsTicker() and ns.settings.shown
  if want and not ticker then
    ticker = C_Timer.NewTicker(1, function() ns.safecall('tick', function()
      local before = st.pos and st.pos.x
      checkArrival()
      if view and #view.current > 1 and st.pos.x ~= before then ns.MarkDirty('pos') end
      local words = view and wordsShown()
      if words and lastWords and words ~= lastWords then ns.MarkDirty('path') end
      lastWords = words
    end) end)
  elseif not want and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

--- the step you clicked, while it's still current, sticky or next: a current one moves to the front of order.
--- Returns its index, or nil (and forgets it) once it's gone from the screen.
focused = function(order)
  local key = ns.cdb.focus
  if not key then return nil end
  for pos, i in ipairs(order) do
    if route.steps[i].k == key then
      table.remove(order, pos)
      table.insert(order, 1, i)
      return i
    end
  end
  for _, list in ipairs({ view.sticky, view.upcoming }) do
    for _, i in ipairs(list) do if route.steps[i].k == key then return i end end
  end
  ns.cdb.focus = nil
  return nil
end

-- the done plate: a quest handed in, or its objectives finished, among the steps that were on screen last time.
-- "Ready to hand in" only for a quest the game says is (Skyborne testers, Oct 11: an as-you-go line is done when the
-- step it runs beside is, and one objective of several can be done; The Problem With Prideclaws showed it at 4 of
-- 10), and once while it stays ready
local lastShown, lastRoute, saidReady = {}, nil, {}
announce = function()
  local now = {}
  for _, i in ipairs(view.current) do now[route.steps[i].k] = i end
  for _, i in ipairs(view.sticky) do now[route.steps[i].k] = i end
  for q in pairs(saidReady) do
    local e = ns.st.log[q]
    if not (e and e.ready) then saidReady[q] = nil end
  end
  if lastRoute == route then
    for key, i in pairs(lastShown) do
      local s = route.steps[i]
      if s and s.k == key and view.status[i] == E.DONE then
        local q = E.quests(s)[1]
        local name = ns.Text.Quest(q or 0, route.pack)
        if s.o == 'turnin' then ns.Toast.Show({ kind = 'quest', label = ns.L.toastQuest, text = name })
        elseif s.o == 'complete' and q then
          local ready = true
          for _, x in ipairs(E.quests(s)) do
            local e = ns.st.log[x]
            if not (e and e.ready) then ready = false end
          end
          if ready and not saidReady[q] then
            saidReady[q] = true
            ns.Toast.Show({ kind = 'ready', label = ns.L.toastReady, text = name })
          end
        end
      end
    end
  end
  lastShown, lastRoute = now, route
end

--- the zone a step on screen is in: where the arrow would point for it, else its own spot (Show on map, FB-035)
function Engine.MapOf(key)
  if not route then return nil end
  for i, s in ipairs(route.steps) do
    if s.k == key then
      local t = waypointFor(i)
      if t and t.map then return t.map end
      local p = s.p and route.pack.pts[s.p]
      return p and p[1] or nil
    end
  end
end

--- point the arrow (and the map pin) at a step on screen
function Engine.Focus(key)
  ns.cdb.focus, ns.cdb.focusFrom = key, naturalLead
  ns.MarkDirty('focus')
end

-- --------------------------------------------------------------------------------------- the free guide's end at 30
-- Owner, Oct 16 (the sales pass): the free guide ends the moment a player reaches level 30, wherever they are on the
-- route, and the full guide takes over from there. No free taste of 30-60: levels 1 to 30 are the taste.
local CRAFTS = { alchemy = true, blacksmithing = true, enchanting = true, engineering = true, leatherworking = true,
                 tailoring = true, cooking = true, firstaid = true }

--- the free pack the player levels with (its `np`: where the paid road starts, and the dungeons it guides)
local function freePack(who)
  for _, r in ipairs(ns.Packs.For(who)) do
    if r.pack and r.pack.tier ~= 'paid' and r.pack.np then return r.pack end
  end
end

local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

--- the level-30 card's words: what the guide did with this character, and where the road goes next
function Engine.FinishText(pack)
  local L = ns.L
  local stats = ns.cdb and ns.cdb.stats or {}
  local lines = {}
  local quests = count(st.completed)
  if quests > 0 then lines[#lines + 1] = ns.count('finishQuests', quests) end
  local dungeons = count(ns.cdb and ns.cdb.dungeons)
  if dungeons == 1 then lines[#lines + 1] = L.finishDungeon elseif dungeons > 1 then lines[#lines + 1] = L.finishDungeons:format(dungeons) end
  local warned = count(stats.warned)
  if warned > 0 then lines[#lines + 1] = ns.count('finishWarned', warned) end
  local secs = tonumber(stats.secs) or 0
  if secs >= 3600 then lines[#lines + 1] = L.finishTime:format(math.floor(secs / 3600), math.floor(secs % 3600 / 60)) end
  -- (someone who reached 30 before the guide saw much of them didn't "make it with" it; the QA pass, Oct 20)
  local out = { (tonumber(stats.secs) or 0) >= 1800 and L.finishHead or L.finishHeadNew }
  if #lines > 0 then
    for i, t in ipairs(lines) do lines[i] = '·  ' .. t end
    out[#out + 1] = table.concat(lines, '\n')
  end
  local np = pack and pack.np
  if np and np.maps and np.lv then
    local names = {}
    for _, m in ipairs(np.maps) do
      local name = ns.Text.Map(m)
      if name ~= '' then names[#names + 1] = name end
    end
    if #names > 0 then
      local where = #names > 1 and (table.concat(names, ', ', 1, #names - 1) .. ' ' .. L['and'] .. ' ' .. names[#names])
        or names[1]
      out[#out + 1] = L.finishNext:format(where, np.lv[1], np.lv[2]) .. ' ' .. L.finishFull
    end
  else
    out[#out + 1] = L.finishFull
  end
  return table.concat(out, '\n\n')
end

--- level 30 without the full guide: the card instead of steps, no arrow, no automation
local function showFinish(who)
  ns.Window.Finish((who.level or 30) > 30 and ns.L.finishTitleUp or ns.L.finishTitle, Engine.FinishText(freePack(who)),
    ns.L.finishButton,
    function() ns.Link.FullGuide('card') end)
  ns.Waypoint.Clear()
  ns.Arrow.Set(nil)
  updateTicker()
end

local function freeEnded(who, r)
  return who and (who.level or 0) >= 30 and not ns.Link.HasFullGuide()
    and (not r or (not r.kd and r.pack and r.pack.tier ~= 'paid'))
end

--- the level-30 card is up (the seal's menu then leaves out what does nothing there: Look back, the free legs)
function Engine.FreeEnded() return freeEnded(Engine.Who(), route) and true or false end

--- the full guide just added at level 30 or later: its route for your level takes over from the free leg you were on
--- (the QA pass, Oct 20: the window went back to the free 28-30 leg)
function Engine.AfterImport(pack)
  if not (pack and pack.tier == 'paid') then return end
  local who = Engine.Who()
  local cur = Engine.Leveling()
  if not (who and (who.level or 0) >= 30 and cur and cur.pack and cur.pack.tier ~= 'paid') then return end
  for _, r in ipairs(ns.Packs.For(who)) do
    if not r.kd and r.pack and r.pack.tier == 'paid' and who.level < (r.lv and r.lv[2] or 60) then
      return Engine.SetRoute(r.id)
    end
  end
end

--- once each, when it matters (never in combat): a crafting profession learned (the first one only), a dungeon the
--- full guide covers walked into
local function hints(who)
  local c = ns.cdb
  if not c or ns.Link.HasFullGuide() or (InCombatLockdown and InCombatLockdown()) then return end
  -- a crafting profession: the ones the character has the first time the guide sees them are noted quietly
  local profs = st.profs or {}
  if not c.profSeen then
    c.profSeen = {}
    for name in pairs(profs) do c.profSeen[name] = true end
  else
    for name in pairs(profs) do
      if not c.profSeen[name] then
        c.profSeen[name] = true
        if CRAFTS[name] and not c.profHinted and not ns.Packs.byId['bof-professions'] then
          c.profHinted, c.lastHint = true, 'prof'
          ns.say(ns.L.fullProfHint:format(ns.L.PROFS and ns.L.PROFS[name] or name))
        end
      end
    end
  end
  -- a dungeon whose guide is in the full guide
  local inst = st.inst
  if inst then
    c.dungeonHints = c.dungeonHints or {}
    local pack = freePack(who)
    if not c.dungeonHints[inst] and pack and pack.np then
      for _, id in ipairs(pack.np.inst or {}) do
        if id == inst then
          c.dungeonHints[inst], c.lastHint = true, 'dungeon'
          local name = ns.clean((GetInstanceInfo()))
          ns.say(ns.L.fullDungeonHint:format(name or ''))
          break
        end
      end
    end
  end
end


--- the skip button on a trip card (Nov 8, FB-049: a trip card had no way past it)
-- ---------------------------------------------------------------------------------------- your quests here first
-- (Nov 9, the owner and his daughter at Redridge's mongrels and poachers: his Night Elf road's next stop was a hand-in
-- in Stormwind, and mid-objective the card said to fly there. The guide knew only his road; these quests were from hers.)
-- Quests in your log that your road doesn't take, being done round you, lead while your road's next stop is far; the
-- road comes back once they're done, you've left, or you skip them
local LOCAL_YARDS, ROAD_FAR_YARDS, LOCAL_SHOWN = 700, 1500, 4
local spotsByQuest, spotsFrom
local function questSpots()
  local n = #(ns.Packs.order or {})
  if spotsByQuest and spotsFrom == n then return spotsByQuest end
  spotsByQuest, spotsFrom = {}, n
  for _, id in ipairs(ns.Packs.order or {}) do
    local r = ns.Packs.routes[id]
    local pts = r and r.pack and r.pack.pts
    if pts and not r.kd then
      for _, s in ipairs(r.steps) do
        if (s.o == 'complete' or s.o == 'turnin') and s.p and pts[s.p] then
          for _, q in ipairs(E.quests(s)) do
            local t = spotsByQuest[q] or {}
            spotsByQuest[q] = t
            t[#t + 1] = { o = s.o, pt = pts[s.p] }
            -- (and its loop's points: the mongrels and poachers range over half of Redridge, the step's spot is one)
            for _, li in ipairs(s.lp or {}) do
              if pts[li] then t[#t + 1] = { o = s.o, pt = pts[li] } end
            end
          end
        end
      end
    end
  end
  return spotsByQuest
end

--- the quests your road takes: every leg of it, first to last (quests carried from an earlier leg are the road's too),
--- and every dungeon guide (their quests ride on the road)
local roadCache, roadCacheOf, roadCacheN
local function roadQuests(r)
  local packs = #(ns.Packs.order or {})
  if roadCacheOf == r and roadCacheN == packs then return roadCache end
  local out, prevOf = {}, {}
  for _, id in ipairs(ns.Packs.order or {}) do
    local x = ns.Packs.routes[id]
    if x and x.nx then prevOf[x.nx] = x end
    if x and x.kd == 'dungeon' then
      for _, s in ipairs(x.steps) do for _, q in ipairs(E.quests(s)) do out[q] = true end end
    end
  end
  local head, seen = r, {}
  while prevOf[head.id] and not seen[head.id] do seen[head.id] = true head = prevOf[head.id] end
  seen = {}
  local x = head
  while x and not seen[x.id] do
    seen[x.id] = true
    for _, s in ipairs(x.steps) do for _, q in ipairs(E.quests(s)) do out[q] = true end end
    x = x.nx and ns.Packs.Get(x.nx)
  end
  roadCache, roadCacheOf, roadCacheN = out, r, packs
  return out
end

local localShown
--- the quests to lead with here, nearest first: { { q, ready, pt, yards } }, or nil
function Engine.LocalQuests(r, v)
  if not (r and v and v.cursor and ns.Geo) or r.kd or st.inst then return nil end
  local cur = r.steps[v.cursor]
  local roadPt = cur and cur.p and r.pack.pts[cur.p]
  local roadYards = roadPt and ns.Geo.YardsTo(roadPt)
  if roadYards and roadYards < ROAD_FAR_YARDS then return nil end
  local spots, mine, skip = questSpots(), roadQuests(r), ns.cdb.localSkip or {}
  local list = {}
  for q, e in pairs(st.log) do
    if not mine[q] and not skip[q] and spots[q] then
      local want = e.ready and 'turnin' or 'complete'
      local at, yards
      for _, sp in ipairs(spots[q]) do
        if sp.o == want then
          local d = ns.Geo.YardsTo(sp.pt)
          if d and d <= LOCAL_YARDS and (not yards or d < yards) then at, yards = sp.pt, d end
        end
      end
      if at then list[#list + 1] = { q = q, ready = e.ready, pt = at, yards = yards } end
    end
  end
  if #list == 0 then return nil end
  table.sort(list, function(a, b) return a.yards < b.yards end)
  return list
end

local function localCard(r, v)
  local list = Engine.LocalQuests(r, v)
  localShown = list
  if not list then return false end
  local lines = {}
  for k = 1, math.min(#list, LOCAL_SHOWN) do
    local it = list[k]
    local title = ns.Text.Quest(it.q, r.pack)
    if it.ready then
      lines[#lines + 1] = ns.L.localTurnin:format(title)
    else
      local obj = ns.Text.Objectives(it.q)
      lines[#lines + 1] = title .. (obj and ('\n' .. ns.Skin.Hex(ns.Skin.C.faint) .. obj .. '|r') or '')
    end
  end
  lines[#lines + 1] = ns.Skin.Hex(ns.Skin.C.faint) .. ns.L.localThen .. '|r'
  ns.Window.Message(ns.L.localTitle, table.concat(lines, '\n'))
  ns.Window.MessageSkip(function()
    ns.cdb.localSkip = ns.cdb.localSkip or {}
    for _, it in ipairs(localShown or {}) do ns.cdb.localSkip[it.q] = true end
    ns.say(ns.L.localSkipped)
    ns.MarkDirty('local')
  end, ns.L.localSkipTip)
  local p = list[1].pt
  local target = { map = p[1], x = p[2], y = p[3], name = ns.Text.Quest(list[1].q, r.pack) }
  ns.Waypoint.Set(target)
  ns.Arrow.Set(target)
  return true
end

--- skip the quests the card leads with now (/bofg skip): your road comes back
function Engine.LocalSkip()
  if not localShown then return false end
  ns.cdb.localSkip = ns.cdb.localSkip or {}
  for _, it in ipairs(localShown) do ns.cdb.localSkip[it.q] = true end
  localShown = nil
  ns.MarkDirty('local')
  return true
end

local function tripSkip()
  ns.Window.MessageSkip(function()
    if ns.Travel and ns.Travel.Skip() then ns.say(ns.L.tripSkipped) end
  end, ns.L.tripSkipTip)
end

-- a dungeon guide's quests it leaves out because a quest before them isn't done (and this guide doesn't give it): said
-- once a session in chat, with what opens each (Nov 9, the owner's daughter: "our DM dungeon guide didn't include
-- Destruction in Deadmines? Why not". The guide hid it without a word; Stockades' Bazil Thredd waits on the Deadmines'
-- Unsent Letter, Scarlet Monastery's Hearts of Zeal on Razorfen Kraul's guano the same way)
local leftSaid = {}
local LEFT_NAMES = 3   -- quests named in one line; the rest counted
-- a quest's facts from any pack loaded (a chain starts in another guide), and the pack that has them
local function questInfo(q, first)
  if first and first.quests and first.quests[q] then return first.quests[q], first end
  for _, pk in pairs(ns.Packs.byId) do
    if pk.quests and pk.quests[q] then return pk.quests[q], pk end
  end
  return nil, first
end
-- the first quest of a missing chain you can take: walk back through what it needs until nothing before it is missing
local function chainStart(q, pack)
  local function have(x) return st.completed[x] or st.log[x] end
  for _ = 1, 12 do
    local info = questInfo(q, pack)
    local nextQ
    for _, x in ipairs(info and info.pre or {}) do if x > 0 and not have(x) then nextQ = x break end end
    if not nextQ and info and info.pre1 and #info.pre1 > 0 then
      local one = false
      for _, x in ipairs(info.pre1) do if x > 0 and have(x) then one = true end end
      if not one then for _, x in ipairs(info.pre1) do if x > 0 then nextQ = x break end end end
    end
    if not nextQ then return q end
    q = nextQ
  end
  return q
end
-- where a quest is handed in: a dungeon guide's name, else the zone of its hand-in on any road
local function handedInWhere(q)
  local zone
  for _, rt in pairs(ns.Packs.routes) do
    for _, t in ipairs(rt.steps or {}) do
      if t.o == 'turnin' then
        for _, x in ipairs(ns.list(t.id)) do
          if x == q then
            if rt.kd == 'dungeon' then return ns.L.leftOutGuide:format(rt.title or '') end
            local pt = t.p and rt.pack.pts and rt.pack.pts[t.p]
            zone = zone or (pt and ns.Text.Map(pt[1]))
          end
        end
      end
    end
  end
  return (zone and zone ~= '') and ns.L.leftOutIn:format(zone) or ''
end
-- a dungeon guide's quests it leaves out because a quest before them isn't done and this guide doesn't give it: said
-- once a session in chat, grouped by the quest that opens them, which is named with where it's handed in (Nov 9, the
-- owner's daughter: "our DM dungeon guide didn't include Destruction in Deadmines? Why not". The guide hid it without a
-- word; the RestedXP study 7 then asked for the quests you lose by name, the chain's real start and where it is)
local function leftOut(r)
  if leftSaid[r.id] or not st.ready then return end
  leftSaid[r.id] = true
  local pack, given = r.pack, {}
  for _, s in ipairs(r.steps) do
    if s.o == 'accept' then for _, q in ipairs(ns.list(s.id)) do given[q] = true end end
  end
  local function have(x) return st.completed[x] or st.log[x] end
  -- the missing quest outside this guide that holds q back, or nil
  local function outsideRoot(q, depth)
    if depth > 12 then return nil end
    local info = questInfo(q, pack)
    local cands = {}
    for _, x in ipairs(info and info.pre or {}) do if x > 0 and not have(x) then cands[#cands + 1] = x end end
    if info and info.pre1 and #info.pre1 > 0 then
      local one = false
      for _, x in ipairs(info.pre1) do if x > 0 and have(x) then one = true end end
      if not one then for _, x in ipairs(info.pre1) do if x > 0 then cands[#cands + 1] = x break end end end
    end
    for _, x in ipairs(cands) do
      if not given[x] then return x end
      local deeper = outsideRoot(x, depth + 1)
      if deeper then return deeper end
    end
    return nil
  end
  local who = Engine.Who()
  local byRoot, order, seen = {}, {}, {}
  for i, s in ipairs(r.steps) do
    if s.o == 'accept' and (view.status[i] == E.SKIPPED or view.status[i] == E.NA) and E.applies(s, who) then
      for _, q in ipairs(ns.list(s.id)) do
        if not seen[q] and not have(q) then
          seen[q] = true
          local root = outsideRoot(q, 0)
          if root then
            if not byRoot[root] then byRoot[root] = {} order[#order + 1] = root end
            table.insert(byRoot[root], q)
          end
        end
      end
    end
  end
  for _, root in ipairs(order) do
    -- (the ones finished inside the dungeon first, the last of a chain before its errands: Destruction in Deadmines,
    -- The Stockade Riots; one name once, a chain's parts share it)
    local qs, names, said, ranked = byRoot[root], {}, {}, {}
    for k = #qs, 1, -1 do ranked[#ranked + 1] = { q = qs[k], k = #ranked + 1 } end
    table.sort(ranked, function(a, b)   -- (Lua's sort isn't stable: the chain's order breaks ties)
      local ia, ib = ns.Packs.dungeonQuests[a.q] and 1 or 0, ns.Packs.dungeonQuests[b.q] and 1 or 0
      if ia ~= ib then return ia > ib end
      return a.k < b.k
    end)
    local unique = {}
    for _, x in ipairs(ranked) do
      local n = ns.Text.Quest(x.q, pack)
      if not said[n] then said[n] = true unique[#unique + 1] = n end
    end
    for k = 1, math.min(LEFT_NAMES, #unique) do names[k] = unique[k] end
    qs = unique
    local list
    if #qs > LEFT_NAMES then
      list = table.concat(names, ', ') .. ns.L.leftOutMore:format(#qs - LEFT_NAMES)
    elseif #names > 1 then
      list = table.concat(names, ', ', 1, #names - 1) .. ns.L.andWord .. names[#names]
    else
      list = names[1]
    end
    local start = chainStart(root, pack)
    local _, sp = questInfo(start, pack)
    ns.say(ns.L.leftOut:format(r.title or '', list, ns.Text.Quest(start, sp), handedInWhere(start)))
  end
end

local function refresh(parts)
  if not ns.db then return end
  if parts.all or parts.completed then ns.State.Completed() end
  ns.State.Player()
  ns.State.Log()
  ns.State.Position()
  ns.State.Bind()
  ns.State.Taxi()
  ns.State.Professions()
  ns.State.Instance()
  local who = Engine.Who()
  route = chooseDungeon(who) or chooseProfession() or chooseLegacy() or chooseRoute(who)
  -- (quests under a collapsed header: the route's own, asked one by one; Nov 8, the RestedXP client study)
  if route and st.logHidden then
    if not route.questIds then
      local ids, seen = {}, {}
      for _, s in ipairs(route.steps) do
        for _, q in ipairs(E.quests(s)) do if not seen[q] then seen[q] = true ids[#ids + 1] = q end end
      end
      route.questIds = ids
    end
    ns.State.LogFill(route.questIds)
  end
  ns.safecall('hints', hints, who)
  if (route or freePack(who)) and freeEnded(who, route) then return showFinish(who) end
  if not route then
    -- past every route you have (a level 35 installing the free guide): say where they end and what else there is
    local top = 0
    for _, r in ipairs(ns.Packs.For(who)) do top = math.max(top, r.lv and r.lv[2] or 0) end
    ns.Window.Message(nil, (top > 0 and who.level >= top) and ns.L.pastRoutes:format(top) or ns.L.noRoute)
    return
  end
  local dungeon, prof, legacy = route.kd == 'dungeon', route.kd == 'profession', route.kd == 'legacy'
  if legacy or route.ach then ns.State.Achievements(route) end
  st.runStart = dungeon and route.inst and ns.cdb.entered[route.inst] or 0
  ns.State.Items(route.items)
  if route.cash then ns.State.Cash() end
  ns.State.Equipped(route.equips)
  ns.State.Known(route.spells)   -- a profession guide's recipes, a leveling route's class spells
  -- (how far a step's spot is: a player ahead of the plan does a nearby objective planned for a level reached)
  local pts = route.pack.pts
  local function nearYards(pi) local p = pts and pts[pi] return p and ns.Geo.YardsTo(p) end
  local function between(a, b) return pts and ns.Geo.Between(pts[a], pts[b]) end
  -- (a flight's end: known, not known, or nil when this continent's flight master's map hasn't been read since install)
  local function flyKnown(s)
    local p = pts and s.p and pts[s.p]
    if not (p and s.id and ns.cdb.taxiRead) then return nil end
    local c = ns.Geo.World(p[1], p[2], p[3])
    if not (c and ns.cdb.taxiRead[c]) then return nil end
    return st.taxi[s.id] and true or false
  end
  local myLand, landOf
  if not (dungeon or prof or legacy) and ns.Travel and ns.Travel.Lands then myLand, landOf = ns.Travel.Lands(route) end
  -- (continents: yours, and a step's point's)
  local pos = st.pos
  local myCont = pos and pos.x and ns.Geo.World(pos.map, pos.x, pos.y) or nil
  local function contOf(pi) local p = pts and pi and pts[pi] return p and ns.Geo.World(p[1], p[2], p[3]) or nil end
  -- the card each road last held, by road (Nov 10, the owner in the guide book: he picked another leg, then Redridge
  -- again, and its card went from the mongrels to "Fly to Stormwind": one lock for one road was dropped by the other's)
  local leads = ns.cdb.leads or {}
  ns.cdb.leads = leads
  if ns.cdb.lead and ns.cdb.lead.r and not leads[ns.cdb.lead.r] then leads[ns.cdb.lead.r] = ns.cdb.lead end
  local sig, lock = stateSig(), leads[route.id]
  -- (a leveling road only: a dungeon, profession or Legacy guide reads its own world, kills and skills)
  local same = not route.kd and lock and lock.r == route.id and indexOfKey(route, lock.k) or nil
  local hold = same and lock.sig == sig and same or nil
  -- (a profession guide is read as the start whose places it shows now: places by where you stand, above)
  local rwho = Engine.WhoFor(route, who)
  local function read(w, h, pv)
    return E.evaluate(route, st, prog(), route.pack, w, { upcoming = 12, noPass = dungeon or prof or legacy,
                                                          near = not (dungeon or prof or legacy) and nearYards or nil,
                                                          pickNear = dungeon and nearYards or nil,
                                                          between = between, here = myLand, landOf = landOf,
                                                          myCont = myCont, contOf = contOf, flyKnown = flyKnown,
                                                          hold = h, prev = pv })
  end
  view = read(rwho, hold, same)
  if prof then
    local pl = ns.cdb.profPlace
    if pl and pl.r ~= route.id then pl = nil end
    local at = pl and pl.k and indexOfKey(route, pl.k)
    local now = GetTime and GetTime() or 0
    local keep = pl and pl.lv == st.level and (not myCont or pl.cont == myCont)
                 and ((at and view.status[at] == E.PENDING) or (not pl.k and now - (pl.t or 0) < PLACE_AGAIN))
    if not keep and myCont then
      local race, key = pickPlace(route, who)
      ns.cdb.profPlace = { r = route.id, race = race or who.race, k = key, cont = myCont, lv = st.level, t = now }
      local w = Engine.WhoFor(route, who)
      if w.race ~= rwho.race then rwho = w view = read(rwho) end
    end
  end
  -- your place moved beyond a walk, flight or hearth: it stays behind you (not a mark of yours: Back still shows it)
  if view.cursor and not view.peek then
    for i = 1, view.cursor - 1 do
      local s = route.steps[i]
      if (s.o == 'goto' or s.o == 'fly' or s.o == 'hearth') and view.status[i] ~= E.NA and not ns.cdb.done[s.k]
          and not ns.cdb.passed[s.k] then
        ns.cdb.passed[s.k] = true
      end
    end
    leads[route.id] = { r = route.id, k = route.steps[view.cursor].k, sig = sig }
    ns.cdb.lead = leads[route.id]
  end
  -- standing where a flight behind your place lands: you got there, and it's done for good. Arriving can't be undone,
  -- so no rule that reads where you stand can send you back for it (Nov 9, the chaos bot: "Fly to The Sepulcher" at
  -- Tarren Mill, then at The Sepulcher the next card back at Tarren Mill, round and round)
  if view.cursor and not (dungeon or prof or legacy) and pts then
    local landed = false
    for i = 1, view.cursor - 1 do
      local s = route.steps[i]
      if s.o == 'fly' and s.p and pts[s.p] and view.status[i] ~= E.NA and not ns.cdb.done[s.k] and not ns.cdb.passed[s.k] then
        local d = ns.Geo.YardsTo(pts[s.p])
        if d and d <= ARRIVED_YARDS then ns.cdb.passed[s.k] = true landed = true end
      end
    end
    if landed then ns.MarkDirty('landed') end
  end
  -- a buy list once held in full stays bought: one arrow shot after the flight brought the arrow vendor back (Nov 8,
  -- the RestedXP items study: 21 buy stops with a hearth or flight before the next step). A quest that still needs a
  -- bought item keeps its stop through the evaluator (buysForQuest), not this
  if view.status then
    for i, s in ipairs(route.steps) do
      if s.o == 'vendor' and type(s.buy) == 'table' and #s.buy > 0 and view.status[i] == E.DONE and not ns.cdb.done[s.k] then
        local all = true
        for _, b in ipairs(s.buy) do
          if type(b) == 'table' and (st.items[b[1]] or 0) < (b[2] or 1) then all = false break end
        end
        if all then ns.cdb.done[s.k] = true end
      end
    end
  end
  -- the quests the window is about to show, checked one by one with the game: the completed list can come late and
  -- short after a login, and a quest you handed in came back as a step to do (FB-031, Oct 22: Distracting Jarven)
  if C_QuestLog.IsQuestFlaggedCompleted and view.status then
    local found = false
    for i = view.cursor or 1, math.min(#route.steps, (view.cursor or 1) + 16) do
      local s = route.steps[i]
      if view.status[i] == E.PENDING and (s.o == 'accept' or s.o == 'turnin' or s.o == 'complete') then
        for _, q in ipairs(E.quests(s)) do
          if not st.completed[q] and not st.log[q] and ns.clean(C_QuestLog.IsQuestFlaggedCompleted(q)) then
            st.completed[q], found = true, true
          end
        end
      end
    end
    if found then view = read(rwho) end
  end
  if dungeon and view.status and not view.waiting then leftOut(route) end
  -- under a pinned guide the leveling route goes on: automation still takes and hands in its quests (Oct 11: a
  -- gathering guide on screen switched quest automation off)
  local lev = route.kd and chooseRoute(who)
  levView = (lev and lev ~= route) and E.evaluate(lev, st, prog(), lev.pack, who, { upcoming = 0 }) or nil
  levRoute = levView and lev or nil
  if view.waiting then ns.Window.Message(route.title, ns.L.waiting) return end
  -- the way there first, one card at a time (Nav/Travel.lua; Batch 3, Oct 19): another start's road across the sea,
  -- and since Nov 6 any guide whose next stop is in another land (the owner opened Hall of Thanes in Darkshore: one
  -- arrow 3,188 yards over the sea, no boat, no tram) or a leveling road you've wandered from
  -- your quests here first: quests in your log your road doesn't take, being done round you, while its next stop is far
  if not route.kd and localCard(route, view) then
    if ns.Travel then ns.Travel.Tick(false) end
    updateTicker()
    return
  end
  local trip = ns.Travel and ns.Travel.Now(route, view, route.kd ~= nil or ns.Travel.Off(route, view))
  if ns.Travel then ns.Travel.Tick(trip and true or false) end
  if trip and trip.learn then
    -- a flight path beside you that you don't know (Nov 7): learn it, and the trips after this can use it
    local p = trip.point
    local where = ('%s %.1f, %.1f'):format(ns.Text.Map(p[1]), p[2], p[3])
    local away = ns.Text.Away(p)
    if away then where = where .. '  ·  ' .. away end
    ns.Window.Message(ns.L.learnFpTitle, ns.L.learnFp:format(trip.learn.name) .. '\n' .. ns.Skin.Hex(ns.Skin.C.faint) .. where .. '|r')
    tripSkip()
    local target = { map = p[1], x = p[2], y = p[3], name = ns.L.learnFpArrow:format(trip.learn.name) }
    ns.Waypoint.Set(target)
    ns.Arrow.Set(target)
    updateTicker()
    return
  end
  if trip and trip.pickup then
    -- your leveling road's quest, its giver beside you (Nov 9): take it as you pass
    local pb, p = trip.pickup, trip.point
    local where = ('%s %.1f, %.1f'):format(ns.Text.Map(p[1]), p[2], p[3])
    local away = ns.Text.Away(p)
    if away then where = where .. '  ·  ' .. away end
    local line = pb.npc and ns.L.passBy:format(pb.quest, pb.npc) or ns.L.passByNoNpc:format(pb.quest)
    ns.Window.Message(ns.L.passByTitle, line .. '\n' .. ns.Skin.Hex(ns.Skin.C.faint) .. where .. '|r')
    tripSkip()
    local target = { map = p[1], x = p[2], y = p[3], name = pb.npc or pb.quest }
    ns.Waypoint.Set(target)
    ns.Arrow.Set(target)
    updateTicker()
    return
  end
  -- what waits at the end of the way, so a trip card says why it takes you there (Nov 10, the owner at Lakeshire's
  -- flight master: "Fly to Stormwind" alone, "there isn't a preview of what I'm doing following this")
  local function there()
    local s = view and view.cursor and route.steps[view.cursor]
    if not s then return '' end
    local ok, main = pcall(ns.Text.Step, s, route.pack)
    main = ok and main and ns.plain(main) or nil
    return main and main ~= '' and ('\n' .. ns.L.travelThere:format(main)) or ''
  end
  if trip and trip.fly then
    -- a flight on the way (Nov 7): to the flight master, then nothing to point at while you're in the air
    local title = ns.L.travelTitle:format(ns.Text.Map(trip.to[1]))
    if trip.fly.flying then
      ns.Window.Message(title, ns.L.travelFlying:format(trip.fly.name) .. there())
      ns.Waypoint.Clear()
      ns.Arrow.Set(nil)
    else
      local p = trip.point
      -- (the spot on the map you stand on: Stormwind's flight master is written on Elwynn Forest's map)
      local q = (st.pos and st.pos.map and ns.Geo.OnMap(p, st.pos.map)) or p
      local where = ('%s %.1f, %.1f'):format(ns.Text.Map(q[1]), q[2], q[3])
      local away = ns.Text.Away(p)
      if away then where = where .. '  ·  ' .. away end
      ns.Window.Message(title, ns.L.travelFly:format(trip.fly.name) .. there() .. '\n' .. ns.Skin.Hex(ns.Skin.C.faint) .. where .. '|r')
      tripSkip()
      local target = { map = p[1], x = p[2], y = p[3], name = ns.L.travelFlyArrow:format(trip.fly.name) }
      ns.Waypoint.Set(target)
      ns.Arrow.Set(target)
    end
    updateTicker()
    return
  end
  if trip then
    -- (where and how far, as every card says it; the arrow's label without the closing period; the QA pass, Oct 20)
    local p = trip.point
    local where = ('%s %.1f, %.1f'):format(ns.Text.Map(p[1]), p[2], p[3])
    local away = ns.Text.Away(p)
    if away then where = where .. '  ·  ' .. away end
    ns.Window.Message(ns.L.travelTitle:format(ns.Text.Map(trip.to[1])),
      trip.way.say .. there() .. '\n' .. ns.Skin.Hex(ns.Skin.C.faint) .. where .. '|r',
      trip.left > 1 and ns.count('travelMore', trip.left - 1) or nil)
    tripSkip()
    local target = { map = p[1], x = p[2], y = p[3], name = (ns.plain(trip.way.say):gsub('%.$', '')) }
    ns.Waypoint.Set(target)
    ns.Arrow.Set(target)
    updateTicker()
    return
  end
  if view.done and dungeon then
    ns.cdb.dungeons[route.id] = ns.cdb.dungeons[route.id] or time()
    if ns.cdb.dungeon == route.id then ns.cdb.dungeon = nil end
    if not st.inst then ns.MarkDirty('dungeon') return end   -- outside: back to the leveling route
    ns.Window.Message(route.title, ns.L.dungeonDone)
    ns.Waypoint.Clear()
    ns.Arrow.Set(nil)
    updateTicker()
    return
  end
  if view.done and legacy then   -- every challenge here earned: say so once, and the leveling route comes back
    ns.cdb.legacy = nil
    ns.say(ns.L.legacyDone)
    ns.MarkDirty('legacy')
    return
  end
  if view.done and prof then   -- at the top: say so once, and the leveling route comes back
    -- (the free guide's part ends at 225, the most a level-30 character can train: the full guide's part goes on when
    -- it's installed; owner, Oct 16)
    local name = ns.L.PROFS[route.pr] or route.pr or route.title
    local opens = Engine.OpensAt(route, rwho)
    if opens then   -- not at the top: the rest waits for a level, so neither the next part nor "done" is true
      ns.cdb.prof = nil
      -- (remembered: at that level the window offers it again, Engine.ProfBack)
      ns.cdb.profWait, backSig = { r = route.id, lvl = opens, race = rwho.race, pr = route.pr }, nil
      ns.say(ns.L.profOpens:format(name, opens))
      ns.MarkDirty('prof')
      return
    end
    local nx = route.nx and ns.Packs.Get(route.nx)
    if nx then
      ns.cdb.prof = nx.id
      Engine.SetRoute(nx.id)
      return
    end
    ns.cdb.prof = nil
    if route.nx and route.pack and route.pack.tier ~= 'paid' and not ns.Link.HasFullGuide() then
      ns.cdb.lastHint = 'prof'
      ns.say(ns.L.profFree:format(name))
    else
      ns.say(ns.L.profDone:format(name))
    end
    ns.MarkDirty('prof')
    return
  end
  if view.done and not peekIndex() then
    local nx = route.nx and ns.Packs.Get(route.nx)
    if nx then
      Engine.SetRoute(nx.id)
      return
    end
    -- the end of a chain with nothing named next: the route that picks up from here, when one is installed (the 30-60
    -- packs follow every start's free routes; Oct 15)
    local after = not route.nx and route.lv and ns.Packs.Suggest(Engine.Who())
    if after and after.id ~= route.id and after.lv and after.lv[1] >= route.lv[2] - 0.5 then
      Engine.SetRoute(after.id)
      return
    end
    -- (the free routes' end at 30, without the full guide: where it goes on; owner, Oct 16)
    local free = route.pack and route.pack.tier ~= 'paid' and route.lv and route.lv[2] and route.lv[2] >= 29.5
      and not ns.Link.HasFullGuide()
    ns.Window.Message(route.title, route.nx and ns.L.nextMissing:format(route.nx)
      or (free and ns.L.routeDoneFree:format(route.lv[2]))
      or (route.lv and route.lv[2] and ns.L.routeDoneAt:format(route.lv[2])) or ns.L.routeDone)
    ns.Waypoint.Clear()
    ns.Arrow.Set(nil)
    updateTicker()
    return
  end
  local peek = peekIndex()
  if peek and peek >= (view.cursor or #route.steps + 1) then ns.cdb.peek, peek = nil, nil end   -- (caught up)
  if peek then
    -- looking back: that step's card as it read then (pending), the few after it, nothing marked or automated
    local pv = { status = {}, current = { peek }, sticky = {}, upcoming = {}, cursor = peek, done = false,
                 peek = peek, live = view.cursor }
    for i, v in pairs(view.status) do pv.status[i] = v end
    local who2, n = Engine.WhoFor(route), 0
    pv.status[peek] = E.PENDING
    for i = peek + 1, #route.steps do
      if n >= 4 or i >= (view.cursor or i + 1) then break end
      if E.applies(route.steps[i], who2) then
        pv.status[i] = E.PENDING
        pv.upcoming[#pv.upcoming + 1] = i
        n = n + 1
      end
    end
    view = pv
  else
    announce()
  end
  -- (an objective with a loop is as far as its loop's nearest stop, where its arrow starts, not as its one data
  -- spot: in Redridge the goretusks' and the spiders' spots lay 300 yards west, a few yards apart in distance, and a
  -- step south swapped which one led; Nov 11)
  local function loopSpot(i)
    local s = route.steps[i]
    if not (s.lp and #s.lp > 0 and ns.Geo) then return nil end
    local best, bd
    for j, pi in ipairs(s.lp) do
      local d = stopWanted(s, j) and ns.Geo.YardsTo(route.pack.pts[pi])
      if d and (not bd or d < bd) then best, bd = route.pack.pts[pi], d end
    end
    return best
  end
  order = E.order(view.current, route, st.pos, route.pack.pts, ns.Geo and ns.Geo.YardsTo, loopSpot)
  naturalLead = view.cursor and route.steps[view.cursor] and route.steps[view.cursor].k or nil   -- (your place: progress moves it, walking doesn't)
  -- a click on a row points the arrow there until the guide moves on to a new card (Oct 11: a click on Lotheluum
  -- Starbreeze's row kept the arrow on him while the card said to collect masks 900 yards away)
  if ns.cdb.focus and ns.cdb.focusFrom and ns.cdb.focusFrom ~= naturalLead then
    ns.cdb.focus, ns.cdb.focusFrom = nil, nil
  end
  local focus = focused(order)
  -- the steps in front of you as stops (Core/Stops.lua); the one holding the focused step leads
  local pts = route.pack.pts
  local function near(i, j)
    local a, b = route.steps[i], route.steps[j]
    local pa, pb = a.p and pts[a.p], b.p and pts[b.p]
    if not (pa and pb) then return nil end
    local c1, ax, ay = ns.Geo.World(pa[1], pa[2], pa[3])
    local c2, bx, by = ns.Geo.World(pb[1], pb[2], pb[3])
    if not (c1 and c2) or c1 ~= c2 then return nil end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
  end
  -- the objective an area card leads with stays its lead until it's done (Nov 11, the owner in Redridge: "the guide
  -- changes and tells me to now go 306 yards in a hard 90 degree angle". The card's place held, but which of its
  -- objectives led was the nearest at every refresh, so the arrow and the rows moved as he walked)
  local al = not view.peek and ns.cdb.areaLead
  local hold = al and al.r == route.id and indexOfKey(route, al.k) or nil
  if hold and view.status[hold] ~= E.PENDING then hold = nil end
  -- ... or until the game says you're busy elsewhere: something changed (a kill, an item) and another objective is
  -- less than half as far, the held one a long way off. Walking alone never moves it
  if hold and al.sig ~= stateSig() and ns.Geo then
    local function reach(i)
      local s = route.steps[i]
      local p = loopSpot(i) or (s.p and route.pack.pts[s.p])
      return p and ns.Geo.YardsTo(p)
    end
    local mine = reach(hold)
    for _, i in ipairs(order) do
      local s = route.steps[i]
      if i ~= hold and AREA_OP[s.o] and not s.wn then
        local d = reach(i)
        if mine and d and mine > AREA_LEAVE_YARDS and d < mine * AREA_LEAVE then hold = nil end
        break
      end
    end
  end
  local current, sticky, upcoming = ns.Stops.Build(route, view, order,
    { near = near, inLog = function(q) return st.log[q] ~= nil end, hold = hold })
  -- the stop that led a moment ago keeps the lead until another is clearly nearer (Oct 11, two sisters on Zephras Isle:
  -- walking between a person to talk to and a kill area on one card swapped the lead, and the arrow, back and forth)
  if heldFor ~= naturalLead then heldLead = nil end
  if heldLead and #current > 1 then
    local function yards(stop)
      local s = route.steps[stop.lead]
      local p = s and s.p and pts[s.p]
      return p and ns.Geo.YardsTo(p)
    end
    local k
    for n, stop in ipairs(current) do
      for _, i in ipairs(stop.steps) do if heldLead[route.steps[i].k] then k = k or n end end
    end
    if k and k > 1 then
      local was, now = yards(current[k]), yards(current[1])
      if was and now and now > was * SWITCH_NEARER then
        table.insert(current, 1, table.remove(current, k))
        for n, stop in ipairs(current) do stop.as = n == 1 and 'now' or 'here' end
      end
    end
  end
  if not view.peek then
    local a = current[1]
    ns.cdb.areaLead = a and a.kind == 'area' and { r = route.id, k = route.steps[a.lead].k, sig = stateSig() } or nil
  end
  heldLead, heldFor = {}, naturalLead
  for _, i in ipairs(current[1] and current[1].steps or {}) do heldLead[route.steps[i].k] = true end
  stops = { current = current, sticky = sticky, upcoming = upcoming }
  local leadStop = current[1] or sticky[1]
  if focus then
    for _, list in ipairs({ current, sticky, upcoming }) do
      for _, stop in ipairs(list) do
        for _, i in ipairs(stop.steps) do if i == focus then leadStop = stop end end
      end
    end
  end
  ns.Window.Render(view, route, stops)
  local aim = focus or (leadStop and leadStop.lead) or order[1]
  -- a walk the stop holds before its lead (into a cave by its mouth) goes first: the arrow takes its path, not a
  -- straight line through the hill to the boss (FB-027, Oct 18: Grik'nir the Cold)
  if not focus and leadStop and view.status then
    for _, i in ipairs(leadStop.steps) do
      local s = route.steps[i]
      if i < aim and s.o == 'goto' and (s.pa or s.p) and view.status[i] == E.PENDING then aim = i break end
    end
  end
  ns.Panels.Want(wantedItems())
  local targets = wantedTargets(leadStop)
  ns.Panels.Targets(targets)
  local target = waypointFor(aim)
  if target and leadStop and not finishStep(aim) then target.name = ns.plain(ns.Text.StopTitle(leadStop, route, true)) end
  if target then ns.Waypoint.Set(target) else ns.Waypoint.Clear() end
  ns.Arrow.Set(target)
  if ns.settings.marks == true and not view.peek then marks = markWants(leadStop, current, upcoming, targets) end
  updateTicker()
  if ns.Party then ns.safecall('party', ns.Party.Send) end   -- (your party's guides hear what you're on; throttled)
end

--- every way out of the refresh above ends with the Waymark told: nothing set means nobody to mark
function ns.Refresh(parts)
  marks = nil
  refresh(parts)
  ns.safecall('marks', ns.Marks.Set, marks)
end

--- the stops on screen, for /bofg report and tests
function Engine.Stops() return stops end

--- what the shown (or pinned) profession guide still needs up to its next rank (all: to the end): its pending crafts'
--- reagents, less what the guide makes along the way and what's in your bags; something you make yourself counts as
--- its own reagents
function Engine.Shopping(all)
  local r = (route and route.kd == 'profession' and route) or chooseProfession()
  if not r then ns.say(ns.L.shoppingNoGuide) return nil end
  ns.State.Items(r.items)
  local v = (r == route and view) or E.evaluate(r, st, prog(), r.pack, Engine.WhoFor(r), { noPass = true })
  local stop, upto = #r.steps + 1, 0
  if not all then
    -- up to your current cap: a rank still to train rides along as you go from the skill it asks for (Oct 11), so its
    -- place in the list isn't where the crafts stop; the first craft past the cap is
    local rank
    for i, s in ipairs(r.steps) do
      if s.o == 'rank' and v.status and v.status[i] == E.PENDING then rank = s break end
    end
    if rank then
      local cap = (st.profMax and st.profMax[rank.sk]) or ((rank.rk or 75) - 75)
      for i, s in ipairs(r.steps) do
        if s.o == 'craft' and (s.un or 0) > cap and v.status and v.status[i] == E.PENDING then stop = i break end
      end
    end
  end
  local need, made, makers, order = {}, {}, {}, {}
  local function add(item, n)
    if not need[item] then need[item] = 0 order[#order + 1] = item end
    need[item] = need[item] + n
  end
  for i, s in ipairs(r.steps) do
    if s.o == 'craft' and s.mk then makers[s.mk[1]] = makers[s.mk[1]] or s end
    if s.o == 'craft' and i < stop and v.status and v.status[i] == E.PENDING then
      local left = ns.Text.CraftsLeft(s)
      upto = math.max(upto, s.un or 0)
      for _, rg in ipairs(s.rg or {}) do add(rg[1], rg[2] * left) end
      if s.mk then made[s.mk[1]] = (made[s.mk[1]] or 0) + s.mk[2] * left end
    end
  end
  local expanded, out = {}, {}
  local i = 1
  while i <= #order do   -- order grows as made items turn into their reagents
    local item = order[i]
    local short = need[item] - (made[item] or 0) - (st.items[item] or 0)
    local maker = makers[item]
    if short > 0 and maker and not expanded[item] then
      expanded[item] = true
      local crafts = math.ceil(short / (maker.mk[2] or 1))
      for _, rg in ipairs(maker.rg or {}) do add(rg[1], rg[2] * crafts) end
    elseif short > 0 and not maker then
      out[#out + 1] = { item = item, n = short, have = st.items[item] or 0 }
    end
    i = i + 1
  end
  if #out == 0 then ns.say(ns.L.shoppingNone) return out end
  ns.say((all and ns.L.shopping or ns.L.shoppingTo):format(r.title or r.id, upto))
  for _, x in ipairs(out) do ns.say(ns.L.shoppingLine:format(x.n, ns.Text.Item(x.item, r.pack), x.have)) end
  return out
end

--- a click on a step line: skip, un-skip, or mark done
--- start from this step: the ones before it that still wait are skipped, kept as one jump you can undo (the RestedXP
--- audit, Oct 18: for a player the guide misreads, rather than skipping one card at a time)
function Engine.JumpTo(key)
  if not (route and view and view.status) then return 0 end
  local jumped = {}
  for i, s in ipairs(route.steps) do
    if s.k == key then break end
    if view.status[i] == E.PENDING then ns.cdb.skip[s.k], ns.cdb.unskip[s.k] = true, nil jumped[#jumped + 1] = s.k end
  end
  if #jumped == 0 then return 0 end
  ns.cdb.jump = jumped
  ns.say(ns.count('jumped', #jumped))
  ns.MarkDirty('jump')
  return #jumped
end

function Engine.UndoJump()
  for _, k in ipairs(ns.cdb.jump or {}) do ns.cdb.skip[k] = nil end
  ns.cdb.jump = nil
  ns.say(ns.L.jumpUndone)
  ns.MarkDirty('jump')
end

--- the quest a step is about, when you could share it with your party now: in your log, in a party, and one the game
--- lets you share (the step's right-click menu; a click, as Blizzard's own Share is)
function Engine.ShareableQuest(key)
  if not (IsInGroup and IsInGroup()) then return nil end
  for _, s in ipairs(route and route.steps or {}) do
    if s.k == key then
      for _, q in ipairs(ns.Evaluator.quests(s)) do
        if st.log[q] and C_QuestLog.IsPushableQuest and ns.clean(C_QuestLog.IsPushableQuest(q)) then return q end
      end
    end
  end
  return nil
end

function Engine.ShareQuest(q)
  local idx = C_QuestLog.GetLogIndexForQuestID and ns.clean(C_QuestLog.GetLogIndexForQuestID(q))
  if idx and QuestLogPushQuest then pcall(QuestLogPushQuest, idx) end
end

function Engine.Click(key, button, shift)
  local c = ns.cdb
  local text, step = key, nil
  for _, s in ipairs(route and route.steps or {}) do if s.k == key then text, step = ns.Text.Step(s, route.pack), s end end
  -- "Mark it done" on a quest still in progress: the hand-in after it couldn't be done either, so it's a skip (the QA
  -- pass, Oct 20: at 2/8 the next card was "Turn in" that quest)
  local objective = step and (step.o == 'complete' or step.o == 'kill' or step.o == 'collect' or step.o == 'use')
  if shift and objective then
    local open = {}
    for _, q in ipairs(E.quests(step)) do if st.log[q] and not st.log[q].ready then open[q] = true end end
    if next(open) then
      shift, button = false, 'LeftButton'
      ns.say(ns.L.markedNotDone)
      for _, s in ipairs(route.steps) do   -- (and its hand-in: the game won't take it unfinished)
        if s.o == 'turnin' then
          for _, q in ipairs(E.quests(s)) do if open[q] then c.skip[s.k] = true end end
        end
      end
    end
  end
  if shift then
    c.done[key] = true
    ns.say(ns.L.marked:format(text))
  elseif button == 'RightButton' then
    c.skip[key], c.done[key], c.unskip[key] = nil, nil, true
    if c.passed then c.passed[key] = nil end
    if c.lastSkip == key then c.lastSkip = nil end
    ns.say(ns.L.unskipped:format(text))
  else
    c.skip[key], c.unskip[key] = true, nil
    c.lastSkip = key
    trainedTo(step)
    ns.say(ns.L.skipped:format(text))
  end
  ns.MarkDirty('click')
end

--- the step you skipped last that's still skipped (for "Bring back the skipped step"), or nil
function Engine.LastSkipped()
  local c = ns.cdb
  if not (c and route) then return nil end
  if c.lastSkip and c.skip[c.lastSkip] then return c.lastSkip end
  for i = #route.steps, 1, -1 do
    local k = route.steps[i].k
    if c.skip[k] then return k end
  end
  return nil
end

function Engine.UnskipLast()
  local k = Engine.LastSkipped()
  if k then Engine.Click(k, 'RightButton') else ns.say(ns.L.nothingSkipped) end
end

-- ------------------------------------------------------------------------------------------------------------ events
-- imports kept from earlier sessions: the BattleTag can be hidden for a moment after login, so retry a few times
local importsWaiting = 0
local function loadImports()
  importsWaiting = ns.Packs.LoadImports() + ns.Paid.Load()   -- (and the paid packs a saved key opens: Core/Paid.lua)
  if importsWaiting > 0 then ns.MarkDirty('packs') end
end

-- joining or leaving a party brings the optional group quests in or out
ns.On('GROUP_ROSTER_UPDATE', function() ns.MarkDirty('group') end)
-- someone in the party levelled: the level the party goes by may have moved (Engine.PartyPace)
ns.On('UNIT_LEVEL', function(unit) if unit ~= 'player' and IsInGroup and IsInGroup() then ns.MarkDirty('group') end end)

ns.On('PLAYER_LOGIN', function()
  ns.InitDB()
  if ns.freshChar then C_Timer.After(3, function() ns.say(ns.L.freshChar) end) end
  ns.safecall('lang', ns.Lang.Apply)   -- (the chosen language's words before any window is made)
  -- the names in the game's Key Bindings (Bindings.xml: the Quest Items and Targets buttons; the RestedXP audit, Oct 18)
  ns.safecall('bindings', function()
    _G.BINDING_HEADER_BOFGUIDE = 'Bind on Forever Guide'
    for i = 1, 4 do _G['BINDING_NAME_CLICK BoFGuideItem' .. i .. ':LeftButton'] = ns.L.bindItem:format(i) end
    for i = 1, 6 do
      _G['BINDING_NAME_CLICK BoFGuideTarget' .. (i == 1 and '' or i) .. ':LeftButton'] = ns.L.bindTarget:format(i)
    end
  end)
  ns.State.Player()
  ns.Window.Create()
  ns.safecall('options', ns.Options.Register)
  ns.safecall('minimap', ns.MinimapButton.Create)
  ns.Packs.LoadFor(st.faction)
  ns.Paid.Collect(st.faction)        -- (this character's locked paid packs, kept for a key to open)
  ns.Packs.DropDeferred()            -- (the other faction's routes and the other languages: let go)
  loadImports()
  loginAt = GetTime()
  -- the folders older versions shipped (one BoFGuide folder since 0.9.72): an app removes them; a hand install keeps
  -- them, so say once which can go (they do nothing now)
  C_Timer.After(6, function()
    -- a chosen language that didn't load says so (owner, Oct 16: Spanish chosen, the cards stayed English)
    if ns.Lang.why and ns.settings and ns.settings.lang then ns.say(ns.L.langFailed:format(ns.Lang.why)) end
    local old = {}
    for _, n in ipairs({ 'BoFGuide_Alliance', 'BoFGuide_Horde', 'BoFGuide_deDE', 'BoFGuide_esMX' }) do
      if C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(n) then old[#old + 1] = n end
    end
    if #old > 0 and ns.db and ns.db.oldFoldersSaid ~= ns.VERSION then
      ns.db.oldFoldersSaid = ns.VERSION
      ns.say(ns.L.oldFolders:format(table.concat(old, ', ')))
    end
  end)
end)
-- near the end of the free routes, once per character: where levels 30 to 60 are (no price, no pop-up)
if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(60, function()
    local c, who = ns.cdb, ns.db and Engine.Who()
    if c and route and not route.kd and route.pack and route.pack.tier ~= 'paid' and who and (who.level or 0) < 30 then
      c.stats = c.stats or {}
      c.stats.secs = (tonumber(c.stats.secs) or 0) + 60
    end
  end)
end
ns.On('PLAYER_LEVEL_UP', function(level)
  level = ns.clean(level)
  if type(level) == 'number' and level >= 27 and level < 30 and ns.cdb and not ns.cdb.fullHint
      and not ns.Link.HasFullGuide() and route and route.pack and route.pack.tier ~= 'paid' then
    ns.cdb.fullHint, ns.cdb.lastHint = true, 'hint27'
    ns.say(ns.L.fullGuideSoon)
  end
end)
ns.On('PLAYER_ENTERING_WORLD', function(login, reload)
  if login then endPeek() end   -- (a new session starts where you are; a /reload keeps the look, Oct 15)
  if importsWaiting > 0 then
    loadImports()
    C_Timer.After(5, function() if importsWaiting > 0 then loadImports() end end)
  end
  ns.MarkDirty('all')
  -- the completed-quest list can arrive late after login; wait for the quest log, or 3 seconds at most
  C_Timer.After(3, function() if not st.ready then st.ready = true ns.MarkDirty('all') end end)
  -- and read it again a little later, in case it came short (FB-031)
  C_Timer.After(10, function() ns.MarkDirty('completed') end)
  C_Timer.After(30, function() ns.MarkDirty('completed') end)
end)
local function questLog() if not st.ready and loginAt then st.ready = true ns.MarkDirty('all') else ns.MarkDirty('log') end end
ns.On('QUEST_LOG_UPDATE', questLog)
ns.On('UNIT_QUEST_LOG_CHANGED', function(unit) if unit == 'player' then questLog() end end)
ns.On('QUEST_ACCEPTED', function(q)
  q = ns.clean(q)
  if q and ns.cdb and ns.cdb.dropped then ns.cdb.dropped[q] = nil end   -- (taken again: back on the road)
  endPeek()
  ns.MarkDirty('log')
end)
-- a quest gone from the log without a turn-in was abandoned: the route's abandon steps for it are done for good, so
-- its earlier steps don't come back
ns.On('QUEST_REMOVED', function(q)
  q = ns.clean(q)
  -- (and the quest itself is one you dropped: left out with what follows from it, not taken again; Nov 8, the RestedXP
  -- ahead/behind study: its pick-up came back as the next card, trip cards and all, for three levels)
  if q and not st.completed[q] then
    ns.cdb.dropped = ns.cdb.dropped or {}
    ns.cdb.dropped[q] = true
  end
  if q and route and not st.completed[q] then
    for _, s in ipairs(route.steps) do
      if s.o == 'abandon' then
        for _, id in ipairs(ns.list(s.id)) do if id == q then ns.cdb.done[s.k] = true end end
      end
    end
  end
  ns.MarkDirty('log')
end)
ns.On('QUEST_TURNED_IN', function(q)
  q = ns.clean(q)
  if q then st.completed[q] = true end
  endPeek()
  ns.MarkDirty('log')
end)
ns.On('PLAYER_LEVEL_UP', function() endPeek() ns.MarkDirty('player') end)
ns.On('PLAYER_XP_UPDATE', function() ns.MarkDirty('player') end)
ns.On('ZONE_CHANGED_NEW_AREA', function() ns.MarkDirty('pos') end)
-- (into a town or out of one: a hearth to the town you're standing in is left out, RestedXP's way)
ns.On('ZONE_CHANGED', function() ns.MarkDirty('pos') end)
ns.On('ZONE_CHANGED_INDOORS', function() ns.MarkDirty('pos') end)
ns.On('BAG_UPDATE_DELAYED', function() ns.MarkDirty('items') end)
ns.On('PLAYER_MONEY', function() ns.MarkDirty('items') end)
ns.On('PLAYER_EQUIPMENT_CHANGED', function() ns.MarkDirty('items') end)
ns.On('PLAYER_REGEN_ENABLED', function() ns.MarkDirty('combat') end)
ns.On('SKILL_LINES_CHANGED', function() ns.MarkDirty('skills') end)
ns.On('CHAT_MSG_SKILL', function() ns.MarkDirty('skills') end)
ns.On('LEARNED_SPELL_IN_SKILL_LINE', function() ns.MarkDirty('skills') end)
ns.On('NEW_RECIPE_LEARNED', function() ns.MarkDirty('skills') end)
ns.On('ACHIEVEMENT_EARNED', function() ns.MarkDirty('legacy') end)
ns.On('CRITERIA_UPDATE', function() ns.MarkDirty('legacy') end)
-- taking off and landing: a flight's arrow turns from the flight master to where you land
ns.On('PLAYER_CONTROL_LOST', function() ns.MarkDirty('taxi') end)
ns.On('PLAYER_CONTROL_GAINED', function() ns.MarkDirty('taxi') end)

ns.On('TAXIMAP_OPENED', function()
  ns.State.ReadTaxiMap()
  ns.MarkDirty('taxi')
end)
-- a flight path the game gives you while you talk to its flight master another way (his quests, through the quest
-- window: his map never opens; Nov 5, Vesprystus): the game says "New flight path discovered!" or changes a flight
-- point's status, and the flight-path step on screen for the flight master beside you is done. (Not the world map's
-- list, `C_TaxiMap.GetTaxiNodesForMap`: Forever marks every flight point on it discovered, 0.9.106's mistake)
local FP_HERE_YARDS = 60
local function learnedHere(close)
  if not route then return end
  ns.State.Position()   -- (a flight-path card runs no position ticker: where you stand now)
  for _, i in ipairs(onScreen()) do
    local s = route.steps[i]
    if s.o == 'fp' and type(s.id) == 'number' and not ns.cdb.taxi[s.id] then
      local p = s.p and route.pack.pts[s.p]
      local d = p and ns.Geo.YardsTo(p)
      if d and d <= close then
        ns.cdb.taxi[s.id] = true
        st.taxi = ns.cdb.taxi
        ns.MarkDirty('taxi')
        return
      end
    end
  end
  -- (and the flight master you stand beside, whatever card sent you: a guide's "A new flight path" card is a trip, not
  -- a route step. Nov 9, the owner's daughter on the Deadmines guide at Lakeshire: she learned it, and the card stayed
  -- until she opened the flight map)
  local best, bestYards
  for id, spot in pairs(nodeSpots(route.pack)) do
    if not ns.cdb.taxi[id] then
      local d = ns.Geo.YardsTo(spot.pt)
      if d and d <= close and (not bestYards or d < bestYards) then best, bestYards = id, d end
    end
  end
  if best then
    ns.cdb.taxi[best] = true
    st.taxi = ns.cdb.taxi
    ns.MarkDirty('taxi')
  end
end
ns.On('UI_INFO_MESSAGE', function(_, msg)
  if ERR_NEWTAXIPATH and ns.clean(msg) == ERR_NEWTAXIPATH then learnedHere(FP_HERE_YARDS) end
end)
ns.On('TAXI_NODE_STATUS_CHANGED', function() learnedHere(FP_HERE_YARDS / 2) end)
-- a quest the route takes from someone who doesn't offer it to you yet (Oct 10: Valreaa Valewind had no Aggressive
-- Encroachment at 3.9; Forever holds quests back for reasons no data shows): it waits like a quest your level can't
-- take, the guide goes on, and it comes back for it after your next level or hand-in
--- the quests one must hand in first that you haven't, in words ("A or B", "A and B"), or nil: a giver who doesn't
--- offer a quest yet names what opens it (the RestedXP audit, Oct 18)
function Engine.MissingFirst(q, pack)
  local info = pack and pack.quests and pack.quests[q]
  if not info then return nil end
  local function name(x) return ns.Text.Quest(x, pack) end
  local one, all = {}, {}
  local anyDone = false
  for _, x in ipairs(info.pre1 or {}) do
    if x > 0 then
      if st.completed[x] then anyDone = true else one[#one + 1] = name(x) end
    end
  end
  for _, x in ipairs(info.pre or {}) do
    if x > 0 and not st.completed[x] then all[#all + 1] = name(x) end
  end
  local parts = {}
  if not anyDone and #one > 0 then parts[#parts + 1] = table.concat(one, ns.L.orWord) end
  if #all > 0 then parts[#parts + 1] = table.concat(all, ns.L.andWord) end
  if #parts == 0 then return nil end
  return table.concat(parts, ns.L.andWord)
end

local function checkOffers(avail)
  local npc, route, view = ns.npcID('npc'), Engine.Route(), Engine.View()
  if not (npc and route and view and view.status) then return end
  local pack = route.pack
  for i, s in ipairs(route.steps) do
    if s.o == 'accept' and view.status[i] == 'pending' then
      local from = false
      for _, id in ipairs(ns.list(s.who)) do if id == npc then from = true end end
      for _, q in ipairs(from and ns.list(s.id) or {}) do
        if not avail[q] and not st.log[q] and not st.completed[q] and not (ns.cdb.notOffered or {})[q] then
          ns.cdb.notOffered = ns.cdb.notOffered or {}
          ns.cdb.notOffered[q] = true
          local first = Engine.MissingFirst(q, pack)
          if first then ns.say(ns.L.notOfferedNeeds:format(ns.Text.Npc(npc, pack), ns.Text.Quest(q, pack), first))
          else ns.say(ns.L.notOffered:format(ns.Text.Npc(npc, pack), ns.Text.Quest(q, pack))) end
          ns.MarkDirty('offers')
        end
      end
    end
  end
end
ns.On('GOSSIP_SHOW', function()
  local avail = {}
  for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
    local q = ns.clean(info.questID)
    if q then avail[q] = true end
  end
  checkOffers(avail)
end)
ns.On('QUEST_GREETING', function()
  local avail = {}
  for i = 1, ns.clean(GetNumAvailableQuests and GetNumAvailableQuests()) or 0 do
    local q = GetAvailableQuestInfo and ns.clean((select(5, GetAvailableQuestInfo(i))))
    if q then avail[q] = true end
  end
  checkOffers(avail)
end)
local function offersAgain()
  if ns.cdb and ns.cdb.notOffered and next(ns.cdb.notOffered) then
    ns.cdb.notOffered = nil
    ns.MarkDirty('offers')
  end
end
ns.On('PLAYER_LEVEL_UP', offersAgain)
-- a hand-in opens what that same person gives next; one to someone else changes nothing about them (Oct 11, two sisters
-- on Zephras Isle: every hand-in anywhere put Talaanis Shadowsong's What Comes Next back on top, and the arrow swung
-- back to her between every other stop)
ns.On('QUEST_TURNED_IN', function()
  local held, npc, r = ns.cdb and ns.cdb.notOffered, ns.npcID('npc') or ns.npcID('questnpc'), Engine.Route()
  if not (held and next(held) and npc and r) then return end
  for _, s in ipairs(r.steps) do
    if s.o == 'accept' then
      local from = false
      for _, id in ipairs(ns.list(s.who)) do if id == npc then from = true end end
      for _, q in ipairs(from and ns.list(s.id) or {}) do
        if held[q] then held[q] = nil ns.MarkDirty('offers') end
      end
    end
  end
  if not next(held) then ns.cdb.notOffered = nil end
end)

-- the innkeeper: "Make this inn your home" asks to confirm while you're still talking to them, and the conversation
-- has closed by the time the bind lands (Oct 10: the step to set your hearth never ticked)
local binder
ns.On('CONFIRM_BINDER', function() binder = ns.npcID('npc') or binder end)
ns.On('HEARTHSTONE_BOUND', function()
  ns.cdb.bindNpc = ns.npcID('npc') or binder
  binder = nil
  ns.MarkDirty('bind')
end)
ns.On('MERCHANT_SHOW', function() Engine.Latch('vendor', ns.npcID('npc')) end)
-- a boss killed: kept per character with the time, so a later run starts the bosses over; the last boss of a dungeon
-- guide marks that dungeon done for the leveling route's stop, whatever quests are left
ns.On('ENCOUNTER_END', function(id, _, _, _, success)
  id, success = ns.clean(id), ns.clean(success)
  if not (id and success == 1) then return end
  ns.cdb.kills[id] = time()
  local wings = st.inst and ns.Packs.DungeonsFor(st.inst, Engine.Who()) or {}
  for _, r in ipairs(ns.Packs.Dungeons(Engine.Who())) do
    local last, has
    for _, s in ipairs(r.steps) do if s.o == 'boss' then last = s.id has = has or s.id == id end end
    -- a boss of another wing in the same instance: you're in that wing, so its guide comes up
    if has and #wings > 1 and r.inst == st.inst and ns.cdb.dungeon ~= r.id then
      local mine = false
      for _, s in ipairs((ns.cdb.dungeon and ns.Packs.Get(ns.cdb.dungeon) or {}).steps or {}) do
        if s.o == 'boss' and s.id == id then mine = true end
      end
      if not mine then ns.cdb.dungeon = r.id end
    end
    if last == id then
      ns.cdb.dungeons[r.id] = ns.cdb.dungeons[r.id] or time()
      if r.inst then ns.cdb.cleared[r.inst] = time() end   -- the run is over: going back in starts a new one
    end
  end
  ns.MarkDirty('boss')
end)
-- the last moment inside (a logout or a portal out), so time spent outside is measured from when you left
ns.On('PLAYER_LEAVING_WORLD', function()
  local c = ns.cdb
  if c and c.inInst then c.seen[c.inInst] = time() end
end)
-- "<dungeon> has been reset.": the next time in is a new run
local function resetPattern()
  local fmt = type(INSTANCE_RESET_SUCCESS) == 'string' and INSTANCE_RESET_SUCCESS
  if not fmt then return nil end
  local p = fmt:gsub('([%(%)%.%+%-%*%?%[%]%^%$%%])', '%%%1')
  return '^' .. (p:gsub('%%%%s', '.+')) .. '$'
end
ns.On('CHAT_MSG_SYSTEM', function(msg)
  msg = ns.clean(msg)
  local pat = resetPattern()
  if ns.cdb and pat and type(msg) == 'string' and msg:find(pat) then ns.cdb.reset = time() end
end)
ns.On('BN_CONNECTED', function() if importsWaiting > 0 then loadImports() end end)
ns.On('TRAINER_SHOW', function() Engine.Latch('train', ns.npcID('npc')) end)
ns.On('UNIT_SPELLCAST_SUCCEEDED', function(unit, _, spell)
  if unit ~= 'player' then return end
  local id = ns.clean(spell)
  local name = ns.clean(C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
  if HEARTH_IDS[id] or name == HEARTH_NAME then Engine.Latch('hearth')
  elseif CAMP_IDS[id] or (name and (name:find('Campfire') or name:find('Camp Tent'))) then Engine.Latch('camp') end
end)

-- where you died, while it's a dungeon (chooseDungeon keeps its guide for the ghost outside)
ns.On('PLAYER_DEAD', function()
  ns.State.Instance()
  ns.cdb.diedIn = st.inst or nil
end)
ns.On('PLAYER_UNGHOST', function() ns.cdb.diedIn = nil ns.MarkDirty('unghost') end)
