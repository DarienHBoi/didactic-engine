-- Works out every step's status from the game state alone (no API calls here, so tests run it as is).
--
--   done      the game says it's done (quest taken, turned in, objective finished, flight known, level reached),
--             or you marked it, or a later step is done and this one only got you there (goto, fly, hearth, ...)
--   pending   still to do
--   skipped   you skipped it, or it belongs to a quest whose start you skipped (and quests that need that quest)
--   passed    before your place in the route and not about a quest you have: shown on request, never in the way
--   na        not for this race, class, mode or level
--
-- A step marked "with next" (wn) rides beside the step after it: it shows with it and is done once that one is.
-- An as-you-go step with an end (tl, RestedXP's "do this while doing the next steps") shows under As you go until the
-- step it names is done, then it's done too, finished or not: a later step finishes what's left.
--
-- Your place: the first pending step whose planned level is within a level of yours. Everything earlier that isn't
-- about a quest in your log is passed, which is what lets a character join a route at any level.
local _, ns = ...

local E = {}
ns.Evaluator = E

E.DONE, E.PENDING, E.SKIPPED, E.PASSED, E.NA = 'done', 'pending', 'skipped', 'passed', 'na'
local DONE, PENDING, SKIPPED, PASSED, NA = E.DONE, E.PENDING, E.SKIPPED, E.PASSED, E.NA

-- steps that only move you somewhere: done once anything after them is done
E.TRANSIENT = { ['goto'] = true, fly = true, hearth = true, vendor = true, train = true, camp = true, enter = true,
                learn = true, equip = true }
-- steps whose quest must be in your log for them to matter
local QUEST_STEP = { turnin = true, complete = true }
local PICK_NEAR_YARDS, PICK_FAR_YARDS = 600, 3000   -- a dungeon guide's pick-up this close goes before one across the sea or this far (FB-067)
local STICKY_BEHIND = 3   -- levels
local STICKY_AWAY_YARDS = 400   -- off an as-you-go step's map, this far from its spot it waits (yards)
local PULL_OPS = { complete = true, kill = true, collect = true }   -- objective steps a player ahead can do early
local PULL_SCAN = 120   -- steps: how far down the route such an objective is looked for
local PULL_YARDS = 300  -- yards: how close it must be
local PULL_AHEAD = 1    -- levels: how far past the plan of the stop in front of you you must be
local STOP_AT_HAND_YARDS = 500   -- yards: a flight path, inn or trainer this close is kept a while when you're ahead
local ACCEPT_BEHIND = 3   -- levels: a quest to take stays on until you're this far past its place (a level or two ahead
                          -- of the plan is normal; Oct 10, a level 3 Human lost Investigate Echo Ridge at 1)
local TRAVEL_BACK_YARDS, AT_FEET_YARDS = 1200, 400   -- the way back to a far step: from the last step at your feet
local FLY_BACK_YARDS, LANDS_NEAR_YARDS = 1000, 600   -- a passed flight: far from both ends; its landing near the next
local HOME_SCAN = 40      -- steps: how far past a hearth its town's steps are looked for
local FM_WALK_YARDS = 60   -- yards: a walk ending this close to a flight's flight master is the walk to it
local LANDED_YARDS = 250   -- yards: this close to where a flight lands, you're there (the next stop over the sea)
local HEARTH_AWAY_YARDS = 200   -- yards: a hearth landing this much farther from the next stop than you are is skipped
local HOME_YARDS = 300    -- yards: the next thing to do this close to where a hearth lands is "at home"; you this close
                          -- are there already

local function list(v) if type(v) == 'table' then return v end if v == nil then return {} end return { v } end
local function has(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end return false end

--- quests a step is about: its own ids for accept/turnin/complete, the linked quest (q) for kill/collect/use
function E.quests(step)
  if step.o == 'accept' or step.o == 'turnin' or step.o == 'complete' or step.o == 'abandon' then return list(step.id) end
  if step.q then return { step.q } end
  return {}
end

--- a training step's spells for your race: { level, spell, rank, races? }
function E.TrainSpells(step, who)
  local out = {}
  for _, sp in ipairs(step.sp or {}) do
    if not sp[4] or has(sp[4], who.race) then out[#out + 1] = sp end
  end
  return out
end

--- who = { race, class, hc, level, perks = set, profs = set }
function E.applies(step, who)
  if step.rc and not has(step.rc, who.race) then return false end
  if step.nrc and has(step.nrc, who.race) then return false end
  if step.cls and not has(step.cls, who.class) then return false end
  if step.ncls and has(step.ncls, who.class) then return false end
  if step.hc == 1 and not who.hc then return false end
  if step.hc == 0 and who.hc then return false end
  if step.lmin and (who.level or 0) < step.lmin then return false end
  if step.lmax and (who.level or 0) > step.lmax then return false end
  for _, p in ipairs(step.perk or {}) do if not (who.perks and who.perks[p]) then return false end end
  for _, p in ipairs(step.prof or {}) do if not (who.profs and who.profs[p]) then return false end end
  return true
end

--- an optional group quest's step while you're on your own (who.solo: not in a party, or the setting says never),
--- unless the quest is already in your log or done: you took it anyway, so it shows (the RestedXP audit, Oct 18:
--- RestedXP hides group quests unless asked; ours come back the moment you're in a party)
function E.soloHidden(step, st, who)
  if step.o == 'dungeon' and (who.noDungeons or (who.dOff and step.dg and who.dOff[step.dg])) then
    return true   -- (no dungeon runs: settings.dungeons; or this one switched off in the guide book, FB-053)
  end
  if not (who.solo and step.grp and step.opt) then return false end
  for _, q in ipairs(E.quests(step)) do
    if st.log[q] or st.completed[q] then return false end
  end
  return true
end

function E.routeApplies(route, who)
  if route.rc and not has(route.rc, who.race) then return false end
  if route.cls and not has(route.cls, who.class) then return false end
  return true
end

local function objectiveDone(st, q, ob)
  if st.completed[q] then return true end
  local e = st.log[q]
  if not e then return false end
  if ob then
    local o = e.obj[ob]
    return (o and o.fin) or false
  end
  return e.ready
end

--- what the game state alone says about a step: DONE or PENDING
function E.check(step, st, who)
  local o = step.o
  if o == 'accept' then
    for _, q in ipairs(list(step.id)) do if not (st.completed[q] or st.log[q]) then return PENDING end end
    return DONE
  elseif o == 'turnin' then
    for _, q in ipairs(list(step.id)) do if not st.completed[q] then return PENDING end end
    return DONE
  elseif o == 'complete' then
    for _, q in ipairs(list(step.id)) do if not objectiveDone(st, q, step.ob) then return PENDING end end
    return DONE
  elseif o == 'kill' or o == 'use' then
    if step.q and objectiveDone(st, step.q, step.qo) then return DONE end
    -- an item used on its own (a book that teaches Mining): done once it has left your bags, or was never there
    if o == 'use' and not step.q and step.id and (st.items[step.id] or 0) == 0 then return DONE end
    return PENDING
  elseif o == 'collect' then
    if step.q and objectiveDone(st, step.q, step.qo) then return DONE end
    -- in the bags: done (a piece for a quest too, a Sea Lion pendant half, though the quest waits for the other)
    if step.id and (st.items[step.id] or 0) >= (step.n or 1) then return DONE end
    return PENDING
  elseif o == 'fp' then
    return st.taxi[step.id] and DONE or PENDING
  elseif o == 'abandon' then   -- gone from your log (never taken counts too: there's nothing to drop)
    for _, q in ipairs(list(step.id)) do if st.log[q] then return PENDING end end
    return DONE
  elseif o == 'equip' then
    return (st.equipped and st.equipped[step.id]) and DONE or PENDING
  elseif o == 'vendor' and step.buy then   -- a buy list: done once your bags hold it all
    for _, b in ipairs(step.buy) do
      -- one you wear counts too (the Fishing Pole in your hands, Nov 5: the count in your bags is 0 then)
      local have = type(b) == 'table' and ((st.items[b[1]] or 0) + ((st.equipped and st.equipped[b[1]]) and 1 or 0))
      if type(b) == 'table' and have < (b[2] or 1) then return PENDING end
    end
    return DONE
  elseif o == 'sethome' then
    return (step.npc and st.bindNpc == step.npc) and DONE or PENDING
  elseif o == 'xp' then
    return (who.level or 0) >= (step.lv or 0) and DONE or PENDING
  elseif o == 'skill' then
    local rank = who.profs and who.profs[step.sk]
    return (type(rank) == 'number' and rank >= (step.rk or 1)) and DONE or PENDING
  elseif o == 'enter' then
    return st.inst == step.id and DONE or PENDING
  elseif o == 'boss' then   -- killed since you last went in (a new run starts the bosses over)
    local t = st.kills and st.kills[step.id]
    return (t and t >= (st.runStart or 0)) and DONE or PENDING
  elseif o == 'dungeon' then
    if step.ac and st.crit and st.crit[step.ac .. '.' .. step.cr] then return DONE end
    return (st.dungeons and st.dungeons[step.dg]) and DONE or PENDING
  elseif o == 'legacy' then   -- a Legacy challenge (an account achievement)
    return (st.ach and st.ach[step.id]) and DONE or PENDING
  elseif o == 'craft' or o == 'gather' or o == 'skin' or o == 'fish' then   -- profession guides: the skill's mark
    local rank = st.profs and st.profs[step.sk]
    return (type(rank) == 'number' and rank >= (step.un or 1)) and DONE or PENDING
  elseif o == 'learn' then
    return (st.known and st.known[step.id]) and DONE or PENDING
  elseif o == 'train' and step.sp then   -- the class spells you can learn now, all known
    local any = false
    for _, sp in ipairs(E.TrainSpells(step, who)) do
      if sp[1] <= (who.level or 0) then
        any = true
        if not (st.known and st.known[sp[2]]) then return PENDING end
      end
    end
    return any and DONE or PENDING
  elseif o == 'rank' then   -- the next rank trained: the skill's cap is at least that high
    local cap = st.profMax and st.profMax[step.sk]
    -- the first rank is learning the profession at all (Cooking at Zarrin on a leveling route, Oct 11): known is
    -- enough, whatever cap the server gives Forever's child skill line
    if (step.rk or 0) <= 75 and type(st.profs and st.profs[step.sk]) == 'number' then return DONE end
    return (type(cap) == 'number' and cap >= (step.rk or 0)) and DONE or PENDING
  end
  return PENDING
end

--- every quest that needs one of these (and isn't in your log or done) joins them
local function closeOver(out, st, pack)
  local quests = pack and pack.quests or {}
  local changed = true
  while changed do
    changed = false
    for q, info in pairs(quests) do
      if not out[q] and not st.log[q] and not st.completed[q] then
        local blocked = false
        if info.pre then for _, p in ipairs(info.pre) do if out[p] then blocked = true end end end
        if info.pre1 and #info.pre1 > 0 then
          local all = true
          for _, p in ipairs(info.pre1) do if not out[p] then all = false end end
          if all then blocked = true end
        end
        if blocked then out[q] = true changed = true end
      end
    end
  end
  return out
end

--- quests whose start you skipped (and are neither in your log nor done), quests you gave up (an objective or the
--- hand-in skipped while the quest isn't ready), plus every quest that needs one of them. FB-012, Oct 12: a tester
--- skipped The Emerald Dreamcatcher's objective as undoable and the guide kept serving its hand-in and the next quests
local function skippedQuests(route, st, prog, pack, who)
  local out = {}
  -- (quests you dropped from your log: their pick-up doesn't come back, nor what follows from them)
  for q in pairs(prog.dropped or {}) do
    if not (st.log[q] or st.completed[q]) then out[q] = true end
  end
  -- (a pick-up you skipped (the step's Skip, /bofg skip), the quest neither in your log nor done: its objectives and
  -- hand-in go with it. Nov 9, the chaos bot skipped Ashenvale Outrunners' pick-up and its two objectives and hand-in
  -- stayed on the card. Marked done by hand is "I have it": that keeps them)
  for _, s in ipairs(route.steps) do
    if s.o == 'accept' and prog.skip and prog.skip[s.k] and not (prog.unskip and prog.unskip[s.k]) then
      for _, q in ipairs(list(s.id)) do
        if not (st.log[q] or st.completed[q]) then out[q] = true end
      end
    end
  end
  -- (optional group quests while you're on your own: left out, and so are the quests that need them)
  if who and who.solo then
    for _, s in ipairs(route.steps) do
      if s.grp and s.opt then
        for _, q in ipairs(list(s.id)) do if not (st.log[q] or st.completed[q]) then out[q] = true end end
      end
    end
  end
  -- (no dungeon runs on your road: the quests done inside a dungeon are left out, and what follows from them)
  -- (and a dungeon switched off in the guide book leaves out the quests only it finishes: FB-053, Nov 12)
  -- (never in a dungeon's own guide: you opened it to run it, and its quests are what it's for. FB-067, Nov 13: a Korean
  -- Undead who levels on their own opened Razorfen Kraul in the Undercity; it hid all its pick-ups and sent them to
  -- the Orgrimmar zeppelin past Faranell's Going, Going, Guano!)
  if who and who.dq and (who.noDungeons or who.dOff) and route.kd ~= 'dungeon' then
    local function off(set)
      if who.noDungeons then return true end
      for id in pairs(set) do if not who.dOff[id] then return false end end
      return true
    end
    for _, s in ipairs(route.steps) do
      for _, q in ipairs(E.quests(s)) do
        local set = who.dq[q]
        if set and not (st.log[q] or st.completed[q]) and off(set) then out[q] = true end
      end
    end
  end
  -- (Hardcore, not in a party: an optional step with an elite to kill leaves its quest out, hand-in and follow-ups too;
  -- Vagash, Tharil'zun, Pyrewood's elites. The step's menu brings it back)
  if who and who.hc and not who.party then
    for _, s in ipairs(route.steps) do
      if s.opt and s.el and not s.grp and not prog.unskip[s.k] then
        for _, q in ipairs(E.quests(s)) do
          local e = st.log[q]
          if not st.completed[q] and not (e and e.ready) then out[q] = true end
        end
      end
    end
  end
  local quests = pack and pack.quests or {}
  -- (a guide's quest whose quest before it you haven't done, and that this guide doesn't give you either: nobody
  -- offers it to you. Nov 7, the owner's Deadmines guide sent them to Alba Fairmoon for Destruction in Deadmines
  -- without Sprite Jumpsprocket's errands done; she had only her low-level quests)
  if route.kd then
    local given = {}
    for _, s in ipairs(route.steps) do
      if s.o == 'accept' then for _, q in ipairs(list(s.id)) do given[q] = true end end
    end
    -- (a negative one is QuestieDB's "in your log": taken counts; Nov 9, the RestedXP study 7)
    local function have(p) if p < 0 then p = -p end return st.completed[p] or st.log[p] or given[p] end
    for _, s in ipairs(route.steps) do
      if s.o == 'accept' then
        for _, q in ipairs(list(s.id)) do
          local info = quests[q]
          if info and not (st.log[q] or st.completed[q]) then
            local missing = false
            for _, p in ipairs(info.pre or {}) do if not have(p) then missing = true end end
            if info.pre1 and #info.pre1 > 0 then
              local one = false
              for _, p in ipairs(info.pre1) do if have(p) then one = true end end
              if not one then missing = true end
            end
            if missing then out[q] = true end
          end
        end
      end
    end
  end
  -- (a quest whose other version you took or finished: the game offers only one of them. Hot and Itchy instead of An
  -- Imp's Request sent you to the giver, and the card came back after every level-up; Nov 9, the RestedXP study 7)
  for q, info in pairs(quests) do
    if info.ex and not (st.log[q] or st.completed[q]) then
      for _, x in ipairs(info.ex) do
        if x > 0 and (st.log[x] or st.completed[x]) then out[q] = true break end
      end
    end
  end
  -- (a breadcrumb whose quest you already hold or finished, or one further down its chain: the game no longer offers
  -- it, and its steps would wait for ever; Nov 5, the owner in Darnassus: Tears of the Moon taken from A'moora on the
  -- way, Sister Aquinne had no Temple of the Moon to give and the card waited for it)
  for q, info in pairs(quests) do
    if info.bc and not (st.log[q] or st.completed[q]) then
      local t, hops = info.bc, 0
      while t and hops < 5 do
        if st.log[t] or st.completed[t] then out[q] = true break end
        t, hops = quests[t] and quests[t].bc, hops + 1
      end
    end
  end
  for _, s in ipairs(route.steps) do
    if prog.skip[s.k] then
      if s.o == 'accept' then
        for _, q in ipairs(list(s.id)) do if not (st.log[q] or st.completed[q]) then out[q] = true end end
      elseif s.o == 'complete' or s.o == 'turnin' then
        for _, q in ipairs(list(s.id)) do
          local e = st.log[q]
          if not st.completed[q] and not (e and e.ready) then out[q] = true end   -- (done after all: it comes back)
        end
      end
    end
  end
  return closeOver(out, st, pack)
end

--- the full picture for one route: status of every step, your place, what to show now and next
--- a step that rides along beside the current one: a sticky step, except a rank to train once your skill is at its
--- cap (Oct 11: ranks ride along from the skill they ask for; at the cap, training is the next thing to do)
function E.asYouGo(step, st)
  if not step.sticky then return false end
  if step.o == 'rank' then
    local rank, cap = st.profs and st.profs[step.sk], st.profMax and st.profMax[step.sk]
    if type(rank) == 'number' and type(cap) == 'number' and rank >= cap then return false end
  end
  return true
end

function E.evaluate(route, st, prog, pack, who, opts)
  opts = opts or {}
  local steps = route.steps
  local n = #steps
  local status = {}
  local view = { status = status, current = {}, sticky = {}, upcoming = {}, cursor = nil, done = false }
  if not st.ready then view.waiting = true return view end
  local skipQ = skippedQuests(route, st, prog, pack, who)
  -- an item that starts one of the route's quests (`accept ... from=item`): getting it is done once that quest is taken,
  -- though the item leaves your bags on the accept or the hand-in (Nov 6, the Horde eyeglass pass: Ashenvale's named
  -- hunts get a step to kill the mob for its drop, which would otherwise call you back to it after the quest)
  local starts = route.startsQ
  if not starts then
    starts = {}
    for _, s in ipairs(steps) do
      if s.o == 'accept' and s.fi then
        starts[s.fi] = starts[s.fi] or {}
        for _, q in ipairs(list(s.id)) do table.insert(starts[s.fi], q) end
      end
    end
    route.startsQ = starts
  end

  for i = 1, n do
    local s = steps[i]
    local v
    if not E.applies(s, who) then v = NA
    elseif E.soloHidden(s, st, who) then v = NA
    elseif prog.done[s.k] then v = DONE
    else
      v = E.check(s, st, who)
      if v ~= DONE and s.o == 'collect' and s.id and starts[s.id] then
        for _, q in ipairs(starts[s.id]) do if st.log[q] or st.completed[q] then v = DONE end end
      end
      -- training you saw or skipped a moment ago: this trainer's stop waits until it has a spell of a higher level
      -- for you (Nov 11; a right-click on its line brings it back)
      if v ~= DONE and s.o == 'train' and s.sp and prog.trained and not prog.unskip[s.k] then
        local new = false
        for _, sp in ipairs(E.TrainSpells(s, who)) do
          if sp[1] > prog.trained and sp[1] <= (who.level or 0) and not (st.known and st.known[sp[2]]) then new = true end
        end
        if not new then v = DONE end
      end
      if v ~= DONE then
        if prog.skip[s.k] then v = SKIPPED
        elseif not prog.unskip[s.k] then
          for _, q in ipairs(E.quests(s)) do if skipQ[q] then v = SKIPPED end end
        end
      end
    end
    status[i] = v
  end

  -- a step that only gets you somewhere is done once the step it leads to is (the next one for you that isn't another
  -- move, an optional step or an as-you-go line); a stop that waits for coin (sell your junk, then train) only once the
  -- training after it is: killing on while you gather the coin doesn't pass it. Oct 11, two sisters side by side with
  -- the same quest log: it used to be "once anything later is done", so a flight path one of them had picked up early
  -- passed her hearth and the guide sent her walking while it told her sister to hearth
  -- a quest that starts from a drop you haven't got doesn't stand in the way either (Nov 7, the Skyborne pass: An Old
  -- History Book's hand-in after the Hunter's Stormwind trainer; at 26 in Darkshire the window pointed 2,712 yards
  -- back to the trainer)
  local unheld = {}
  for i = 1, n do
    local s = steps[i]
    if s.o == 'accept' and s.fi and not s.p and (st.items[s.fi] or 0) == 0 then
      for _, q in ipairs(list(s.id)) do
        if not st.log[q] and not st.completed[q] then unheld[q] = true end
      end
    end
  end
  local function dropQuest(s)
    local qs = E.quests(s)
    if #qs == 0 then return false end
    for _, q in ipairs(qs) do if not unheld[q] then return false end end
    return true
  end
  -- a stop to buy what a quest in your log still asks for stays until you have it: taking the quest after it doesn't
  -- pass it, nor does being above its level (Nov 8, the owner two levels ahead at Gilbert Gray with Fishin' Time taken
  -- and no Nightcrawlers: the stop at Catherine Leland was passed, and the hand-in card waited with the arrow on
  -- Gilbert, "You're here")
  local needBuy
  for q, e in pairs(st.log) do
    local info = not e.ready and pack and pack.quests and pack.quests[q]
    for _, h in ipairs(info and info.how or {}) do
      if h[1] == 'buy' and h[2] then needBuy = needBuy or {} needBuy[h[2]] = true end
    end
  end
  local function buysForQuest(s)
    if not (needBuy and s.o == 'vendor' and type(s.buy) == 'table') then return false end
    for _, b in ipairs(s.buy) do
      if type(b) == 'table' and needBuy[b[1]] and (st.items[b[1]] or 0) < (b[2] or 1) then return true end
    end
    return false
  end
  local nextDone, trainedLater = false, false
  local bossAfter, bossesDone = false, true   -- (the bosses after this point, and whether all of them died this run)
  for i = n, 1, -1 do
    local s, v = steps[i], status[i]
    if v == DONE and s.o == 'train' and s.sp then trainedLater = true end
    if s.o == 'boss' and not s.opt and v ~= NA then bossAfter, bossesDone = true, bossesDone and v == DONE end
    -- the way in: you're in, or every boss after it died this run. Quests handed in on an earlier run don't take you
    -- in (Nov 7, the dungeon walk: a second run of the Hall of Thanes lost its way in and led with Faldrim, no arrow)
    if s.o == 'enter' and bossAfter and v == PENDING and bossesDone then status[i], v = DONE, DONE end
    -- (only the guide's own way in waits for its bosses: an `enter` for an instance it passes through is passed like a
    -- walk. Nov 13, the Onyxia guides: out of the Spire with its part handed in, the card went back to the Spire's door)
    local ownWay = s.o == 'enter' and bossAfter and (not route.inst or s.id == route.inst)
    local transient = (E.TRANSIENT[s.o] and not ownWay)
      or (s.o == 'use' and not s.q)   -- (a book you keep doesn't hold you up)
      or (s.o == 'boss' and s.opt)   -- a rare boss that didn't spawn this run (Miner Johnson): passed by the next one
    local aside = s.opt or s.sticky or s.tl or s.wn or (v == PENDING and dropQuest(s))
    if not transient and v ~= NA and not (aside and v ~= DONE) then
      nextDone = v == DONE or v == SKIPPED or v == PASSED   -- (the step a move before it leads to)
    elseif s.o == 'enter' and v == DONE then
      nextDone = true                                        -- being inside counts
    end
    if ownWay then nextDone = v == DONE end   -- (the walk to the door waits for the way in)
    if v == PENDING and transient and (s.cash and trainedLater or not s.cash and nextDone) and not buysForQuest(s) then
      status[i] = DONE
    end
  end

  -- inside the guide's own dungeon, its "before you go" part (everything before the way in) is passed while you're in:
  -- summoned or invited in without the pick-ups, the card said "Accept Collecting Memories" in Stormwind, 21 steps
  -- before the first boss (Nov 9, the RestedXP study 7). Out again, it comes back
  if route.kd == 'dungeon' and route.inst and st.inst == route.inst then
    for i = 1, n do
      if steps[i].o == 'enter' then break end
      if status[i] == PENDING then status[i] = PASSED end
    end
  end

  -- a quest you abandoned where the route says to: its earlier steps are done with (they'd come back otherwise)
  for i = n, 1, -1 do
    if steps[i].o == 'abandon' and prog.done[steps[i].k] then
      for _, q in ipairs(list(steps[i].id)) do
        for j = 1, i - 1 do
          if status[j] ~= DONE and status[j] ~= NA and has(E.quests(steps[j]), q) then status[j] = DONE end
        end
      end
    end
  end

  -- as-you-go steps with an end: done once the step they name is (or, when that one isn't for you, once the first step
  -- after it that is for you is done)
  local index
  for i = 1, n do
    local s = steps[i]
    if s.tl and status[i] == PENDING then
      if not index then
        index = route.keyIndex
        if not index then
          index = {}
          for j = 1, n do index[steps[j].k] = j end
          route.keyIndex = index
        end
      end
      local j = index[s.tl]
      while j and j <= n and status[j] == NA do j = j + 1 end
      if j and j <= n and (status[j] == DONE or status[j] == SKIPPED) then status[i] = DONE end
    end
  end

  -- "with next": done once the next step for you is
  for i = n, 1, -1 do
    if steps[i].wn and status[i] == PENDING then
      for j = i + 1, n do
        if status[j] ~= NA then
          if status[j] == DONE then status[i] = DONE end
          break
        end
      end
    end
  end

  -- your place: steps planned well below your level are passed, unless they're about a quest you have (dungeon and
  -- profession guides pass nothing: an over-levelled run still has every boss to kill)
  -- (in a party the count starts from the lowest level in it, who.pace: two people levelling together get the same
  -- steps. Nov 11, the owner at 21 beside a level 20 hunter: one guide left the Darkshire trip behind, the other led
  -- to it. What a quest or a trainer asks of you still goes by your own level)
  local level = who.level or 1
  local pace = math.min(who.pace or level, level)
  local floor_ = n + 1
  for i = 1, n do
    if opts.noPass or (status[i] == PENDING and (steps[i].pl or 0) >= pace - 1) then floor_ = i break end
  end
  for i = 1, floor_ - 1 do
    if status[i] == PENDING then
      local keep = false
      if QUEST_STEP[steps[i].o] or steps[i].q then
        for _, q in ipairs(E.quests(steps[i])) do if st.log[q] then keep = true end end
      end
      if buysForQuest(steps[i]) then keep = true end
      -- "as you go" steps ride along a while longer before they count as left behind, and so do quests to take
      if steps[i].sticky and (steps[i].pl or 0) >= pace - STICKY_BEHIND then keep = true end
      if steps[i].o == 'accept' and (steps[i].pl or 0) >= pace - ACCEPT_BEHIND then keep = true end
      -- and so do a flight path to learn, an inn to bind at and a trainer to visit: dropped for being a level behind you,
      -- nothing brought them back, and every later "Fly to" pointed at a flight path never learned (Nov 8, the RestedXP
      -- ahead/behind study: 36 of 97 flight paths, 18 of 54 binds and 348 trainer visits at 1.5 levels ahead)
      local o = steps[i].o
      -- (only one at hand, as you reach its town: one in a land behind you isn't a reason to go back; the FB-046
      -- lighthouse test, Lakeshire's flight path from Westfall)
      if (o == 'fp' or o == 'sethome' or o == 'train') and (steps[i].pl or 0) >= pace - ACCEPT_BEHIND then
        local d = opts.near and steps[i].p and opts.near(steps[i].p)
        if d and d <= STOP_AT_HAND_YARDS then keep = true end
      end
      -- a hand-in that asks for a craft's skill (Camping 101's 20) is left behind like any step, though you carry the
      -- quest: it doesn't call you back across the world when the skill comes later (Oct 12, the Human second pass)
      if steps[i].skr then keep = false end
      if not keep then status[i] = PASSED end
    end
  end
  -- a walk that leads to a step you still have (the cave's mouth before its boss, for a quest in your log) stays with
  -- it: a player a level ahead lost the way in and the arrow went straight through the hill (FB-027, Oct 18)
  local kept = floor_ <= n and status[floor_] == PENDING
  for i = floor_ - 1, 1, -1 do
    local s, v = steps[i], status[i]
    if v ~= NA then
      if s.o == 'goto' and (s.pa or s.p) then
        if v == PASSED and kept then status[i] = PENDING end
      elseif s.o == 'fly' or s.o == 'hearth' then
        -- (a walk before a flight or a hearth leads to it, not to the step after it: Nov 8, a Skyborne Horde player ahead
        -- of the plan flew back and forth between Orgrimmar and Thunder Bluff, the walk to Thunder Bluff's gryphons
        -- revived for the Orgrimmar bind kept at hand)
        kept = false
      elseif not E.TRANSIENT[s.o] and not (s.opt or s.sticky or s.tl or s.wn) then
        kept = v == PENDING
      end
    end
  end
  -- a quest whose taking was left behind (and isn't in your log): its objectives and turn-in go with it, wherever the
  -- route puts them, and so do the quests that need it. So does one an earlier route gave you (this one has no step
  -- taking it) that you don't have: an item that never dropped, a quest you skipped there
  local gone, taken = {}, {}
  for i = 1, n do
    if steps[i].o == 'accept' then
      for _, q in ipairs(list(steps[i].id)) do
        taken[q] = true
        if status[i] == PASSED and not (st.log[q] or st.completed[q]) then gone[q] = true end
      end
    end
  end
  for i = 1, n do
    if status[i] == PENDING and (QUEST_STEP[steps[i].o] or steps[i].q) then
      for _, q in ipairs(E.quests(steps[i])) do
        if not taken[q] and not st.log[q] and not st.completed[q] then gone[q] = true end
      end
    end
  end
  -- and a quest to take whose quest before it you don't have, when this route doesn't give it to you either (an earlier
  -- leg did): its giver won't offer it (FB-050, Nov 9: Howling in the Hills on the Duskwood leg, A Baying of Gnolls on
  -- the Redridge leg, for a level 27 Mage who never did it). One in your log, not handed in, waits instead (below)
  local preQ = pack and pack.quests or {}
  local function have(p) return st.completed[p] or st.log[p] or (taken[p] and not gone[p]) end
  for i = 1, n do
    local s = steps[i]
    if s.o == 'accept' and status[i] == PENDING then
      for _, q in ipairs(list(s.id)) do
        local info = preQ[q]
        if info and not st.log[q] and not st.completed[q] then
          local missing = false
          for _, p in ipairs(info.pre or {}) do if p > 0 and not have(p) then missing = true end end
          if info.pre1 and #info.pre1 > 0 then
            local one = false
            for _, p in ipairs(info.pre1) do if p > 0 and have(p) then one = true end end
            for _, p in ipairs(info.pre1) do if p < 0 and (st.log[-p] or st.completed[-p]) then one = true end end
            if not one then missing = true end
          end
          if missing then gone[q] = true end
        end
      end
    end
  end
  if next(gone) then
    closeOver(gone, st, pack)
    for i = 1, n do
      if status[i] == PENDING then
        local left, mine = false, false   -- (a turn-in for two quests stays while you carry one of them)
        for _, q in ipairs(E.quests(steps[i])) do
          if gone[q] then left = true end
          if st.log[q] then mine = true end
        end
        if left and not mine then status[i] = PASSED end
      end
    end
  end

  -- a quest your level can't take yet waits, and so does what hangs on it (its objectives and turn-in, quests that
  -- need it): the guide goes on with what you can do and comes back to it when you've levelled (Oct 9: a level 1
  -- Hunter stopped dead at Brotherhood of Thieves, a level 2 quest)
  -- a required hand-in steps aside too, like an optional one you haven't finished (`unfinished` below), when nothing on
  -- the route gets you what it asks for: no step to complete it, no stop to buy it (Nov 8, after Fishin' Time: the Paladin's Tome of Divinity, taken and handed in on the spot, waited
  -- for 10 Linen Cloth with the arrow on John Turner, "You're here"; Root Samples in Ratchet short of herbs). The
  -- guide goes on, and the hand-in comes back once you have it all
  local wayTo
  local function noWay(q)
    if not wayTo then
      wayTo = {}
      local buys = {}
      for j = 1, n do
        local t = steps[j]
        -- (any step that works toward it: complete, or a collect, kill or use `for` it: the Sunken Temple's
        -- Kalimdor Kocktail parts)
        if t.o ~= 'accept' and t.o ~= 'turnin' and t.o ~= 'abandon' then
          for _, c in ipairs(E.quests(t)) do wayTo[c] = true end
        end
        if t.o == 'vendor' and type(t.buy) == 'table' then
          for _, b in ipairs(t.buy) do if type(b) == 'table' then buys[b[1]] = true end end
        end
      end
      for c in pairs(st.log) do
        local info = pack and pack.quests and pack.quests[c]
        for _, h in ipairs(info and info.how or {}) do
          if h[1] == 'buy' and buys[h[2]] then wayTo[c] = true end
        end
      end
    end
    return not wayTo[q]
  end
  local waitQ, itemQ = {}, {}
  local quests = pack and pack.quests or {}
  for i = 1, n do
    local s = steps[i]
    if s.o == 'accept' and status[i] == PENDING then
      for _, q in ipairs(list(s.id)) do
        local info = quests[q]
        if info and info.min and level < info.min and not st.log[q] and not st.completed[q] then waitQ[q] = true end
        -- its giver didn't offer it to you: waits until your next level or hand-in, like the one above
        if st.notOffered and st.notOffered[q] and not st.log[q] and not st.completed[q] then waitQ[q] = true end
        -- taken as you go and not taken yet: its own stop later on the road waits until it's in your log (Nov 5, the
        -- owner fishing for Electropellers: the pool below Cliffspring Falls is where they are, but only for someone
        -- who has the quest by then)
        if s.sticky and not st.log[q] and not st.completed[q] then waitQ[q] = true end
        -- started from an item that drops: waits until it's in your bags (and never holds the route up); one lying in
        -- one spot (a step with its own p) is the step to go to (the Dirt-stained Map on the Bristleback cave's floor)
        if s.fi and not s.p and (st.items[s.fi] or 0) == 0 and not st.log[q] and not st.completed[q] then
          waitQ[q] = true
          itemQ[q] = true
        end
      end
    end
  end
  -- a hand-in that steps aside (below): the quests that need it wait with it, so the next card isn't a quest its giver
  -- won't offer yet (the second Tome of Divinity)
  for i = 1, n do
    local s = steps[i]
    if s.o == 'turnin' and status[i] == PENDING then
      for _, q in ipairs(list(s.id)) do
        local e = st.log[q]
        if e and not e.ready and (s.opt or noWay(q)) then waitQ[q] = true end
      end
    end
  end
  if next(waitQ) then
    local changed = true
    while changed do
      changed = false
      for q, info in pairs(quests) do
        if not waitQ[q] and not st.log[q] and not st.completed[q] then
          for _, p in ipairs(info.pre or {}) do
            if waitQ[p] then waitQ[q] = true itemQ[q] = itemQ[p] changed = true end
          end
          for _, p in ipairs(info.pre1 or {}) do
            if waitQ[p] and not waitQ[q] then waitQ[q] = true itemQ[q] = itemQ[p] changed = true end
          end
        end
      end
    end
  end
  -- not enough coin yet for a stop that waits for it, and the steps right after it at the same person (taking the
  -- Warlock's Beginnings from the trainer happens when you go to train)
  local poor = {}
  for i = 1, n do
    local s = steps[i]
    if s.cash and status[i] == PENDING and (st.cash or 0) < s.cash then
      poor[i] = true
      local who = s.npc
      for j = i + 1, n do
        local t = steps[j]
        local at = t.npc or (type(t.who) == 'table' and t.who[1]) or t.who
        if status[j] == NA then
        elseif who and at == who and not t.cash then poor[j] = true
        else break end
      end
    end
  end
  -- gear to put on that isn't in your bags (you picked another reward, or it hasn't dropped): it waits
  local function noGear(i)
    local s = steps[i]
    return s.o == 'equip' and s.id and (st.items[s.id] or 0) == 0 and not (st.equipped and st.equipped[s.id])
  end
  -- a hand-in that asks for more skill in its craft than you have (Camping 101's 20): it waits, and the route goes on
  local function lowSkill(i)
    local s = steps[i]
    if not s.skr then return false end
    local p = type(s.prof) == 'table' and s.prof[1] or s.prof
    local rank = who.profs and p and who.profs[p]
    return not (type(rank) == 'number' and rank >= s.skr)
  end
  -- an optional hand-in of a quest you carry but haven't finished (a dungeon's, the run skipped): it waits and comes
  -- back once the quest is ready, instead of holding the card until you skip it (Nov 7, the Horde eyeglass pass:
  -- Thunder Bluff's Wailing Caverns hand-ins for a player who didn't go in)
  local function unfinished(i)
    local s = steps[i]
    if s.o ~= 'turnin' then return false end
    for _, q in ipairs(E.quests(s)) do
      local e = st.log[q]
      if e and not e.ready and (s.opt or noWay(q)) then return true end
    end
    return false
  end
  local function waits(i)
    if poor[i] or noGear(i) or lowSkill(i) or unfinished(i) then return true end
    for _, q in ipairs(E.quests(steps[i])) do if waitQ[q] and not st.log[q] then return true end end
    return false
  end
  -- a hearth home stays while the next thing for you is at home and you aren't, though the step right after it was
  -- done earlier in another order: it has only "got you there" once you're there (cast it or walked). Nov 5, the owner
  -- in Darnassus with Tears of the Moon: he'd taken and handed in Returning Home before going up, so the hearth to
  -- Dolanaar before it counted as done and the card sent him walking 1,531 yards to Corithras Moonrage. Standing in
  -- the town your hearth is set to counts as there too, by the game's own place name (RestedXP's hearth steps are
  -- left out in their town the same way)
  local inBind = st.bind and st.bind ~= '' and (st.sub == st.bind or st.zone == st.bind)
  if inBind then
    for i = 1, n do if steps[i].o == 'hearth' and status[i] == PENDING then status[i] = DONE end end
  end
  -- where your stone lands: the inn you're bound to, from its innkeeper's stop anywhere in the pack (Nov 8, the
  -- owner at Stormwind's harbor bound in Goldshire: the hearth after the Jangolode Mine came back as "Hearth to
  -- Goldshire", because the route's first spot after it, in Stormwind, was taken for where it lands)
  local inn
  if st.bindNpc and pack and pack.routes then
    for _, r in ipairs(pack.routes) do
      for _, t in ipairs(r.steps or {}) do
        if t.o == 'sethome' and t.npc == st.bindNpc and t.p then inn = t.p break end
      end
      if inn then break end
    end
  end
  if opts.near and opts.between and not inBind then
    for i = 1, n do
      local s = steps[i]
      if s.o == 'hearth' and status[i] == DONE and not prog.done[s.k] then
        local home, nextUp = inn, nil
        for j = i + 1, math.min(n, i + HOME_SCAN) do
          local t, v = steps[j], status[j]
          if t.o == 'hearth' or t.o == 'fly' then break end
          if v ~= NA then
            home = home or t.p   -- (else where it takes you: the first spot after it, done or not)
            if v == PENDING and t.p and not (t.opt or t.sticky or t.tl or t.wn) and not waits(j)
                and not E.TRANSIENT[t.o] then
              nextUp = j
              break
            end
          end
        end
        if home and nextUp then
          local close, away = opts.between(steps[nextUp].p, home), opts.near(home)
          if close and close <= HOME_YARDS and (away == nil or away > HOME_YARDS) then status[i] = PENDING end
        end
      end
    end
  end

  -- a hearth that takes you farther from the next stop than you already are is skipped, the way RestedXP writes
  -- `.bindlocation` exits on its hearth steps (Nov 8, the owner at Stormwind's harbor bound in Goldshire: "Hearth to
  -- Goldshire" with the next stop in Stormwind; the bot then found the same on twenty more hearths in every faction,
  -- where the inn you're bound to isn't the one the route expects). Only with the inn known: your own bind
  local away = {}   -- (hearths skipped for leading away: the travel sweep below leaves them be)
  local function hearthsAway()
    if inn and opts.near and opts.between then
      for i = 1, n do
        local s = steps[i]
        -- (a passed one too: it stays passed, and the travel sweep below doesn't bring it back)
        -- (only bound somewhere other than the inn the route bound you at: its own hearth stands, as RestedXP's
        -- `.bindlocation` reads it; the Stonetalon legs' hearth to the Crossroads)
        -- (the route's own hearth too, once it would bring you no nearer: Nov 9, the chaos bot walked back to Razor Hill
        -- and stood at its trainers under "Hearth to Razor Hill")
        local own = s.bn and st.bindNpc == s.bn
        if s.o == 'hearth' and (status[i] == PENDING or (status[i] == DONE and not own)) and not prog.done[s.k] then
          for j = i + 1, math.min(n, i + HOME_SCAN) do
            local t, v = steps[j], status[j]
            if v == PENDING and t.p and t.o ~= 'hearth' and not (t.opt or t.sticky or t.tl or t.wn)
                and not E.asYouGo(t, st) and not waits(j) then
              local you, home = opts.near(t.p), opts.between(inn, t.p)
              -- (your own hearth before a flight is one journey, hearth then fly: Un'Goro's hearth to Gadgetzan for the
              -- flight to Thunder Bluff. Straight lines would pass it)
              if you and home and (home > you + HEARTH_AWAY_YARDS or (own and t.o ~= 'fly' and home >= you)) then
                status[i] = DONE
                away[i] = true
              end
              break
            end
          end
        end
      end
    end
  end
  hearthsAway()

  -- a flight to where you already are is done, the way RestedXP's `.zoneskip` exits its flight steps (Nov 8, the bot
  -- that walks instead of flying: at the next stop, the card still said "Fly to ..." on seven 1-30 roads and a hundred
  -- times on the 30-60 ones). Done when you're nearer its landing than its flight master is, and nearer the next stop
  -- than the landing is. At the flight master the first never holds (the Crossroads to Ratchet keeps its card)
  if opts.near and opts.between then
    for i = 1, n do
      local s = steps[i]
      if s.o == 'fly' and s.p and status[i] == PENDING and not prog.done[s.k] then
        local you, span = opts.near(s.p), s.dp and opts.between(s.dp, s.p)
        -- nearer where it lands than its flight master: walking on is never longer than going back to fly (Nov 9, the
        -- never-stranded pass: a player who walked into the Wetlands kept "Fly to Menethil Harbor" from Darkshire)
        local toDep = s.dp and opts.near(s.dp)
        -- (or you've already done something where it lands, on foot: Nov 9, the chaos bot trained in Orgrimmar under
        -- "Fly to Orgrimmar")
        local beenThere = false
        for j = i + 1, math.min(n, i + HOME_SCAN) do
          local t = steps[j]
          if t.o == 'fly' or t.o == 'hearth' then break end
          local d = t.p and prog.done[t.k] and opts.between(s.p, t.p)
          if d and d <= LANDS_NEAR_YARDS then beenThere = true break end
        end
        -- (clearly on the landing's side: within half the flight's length too. Straight lines ignore the land between:
        -- western Tirisfal is nearer the Sepulcher than Undercity's flight master as the crow flies, not on foot)
        if beenThere or (you and toDep and you < toDep and (not span or you < span * 0.5)) then
          status[i] = DONE
          away[i] = true
        -- (a flight with no flight master of its own, a leg's first "Fly to Orgrimmar" from wherever you are: there when
        -- you're nearer the next stop than its landing is. Nov 9, the chaos bot walking to Orgrimmar kept the card)
        elseif you and ((span and you < span) or not s.dp) then
          for j = i + 1, math.min(n, i + HOME_SCAN) do
            local t, v = steps[j], status[j]
            if v == PENDING and t.p and t.o ~= 'fly' and t.o ~= 'hearth' and t.o ~= 'goto'
                and not (t.opt or t.sticky or t.tl or t.wn) and not waits(j) then
              local toNext, landNext = opts.near(t.p), opts.between(s.p, t.p)
              if toNext and landNext and toNext < landNext then status[i] = DONE
              -- (the next stop over the sea, where no yards reach: standing where it lands is enough. Nov 9, at
              -- Auberdine's dock on the 30-60 road: "Go to Astranaar's flight master" to fly back to Auberdine)
              elseif not (toNext and landNext) and you <= LANDED_YARDS then status[i] = DONE end
              break
            end
          end
        end
        -- (and the walk to its flight master just before it: a walk that goes nowhere else)
        if status[i] == DONE then
          for k = i - 1, math.max(1, i - 4), -1 do
            if status[k] ~= NA then
              local u = steps[k]
              local d = u.o == 'goto' and u.p and opts.between(u.p, s.dp)
              if d and d <= FM_WALK_YARDS and status[k] == PENDING and not prog.done[u.k] then status[k] = DONE end
              break
            end
          end
        end
      end
    end
  end

  -- a flight to a flight path you don't know, on a continent whose flight master's map we've read, can't be taken:
  -- passed, and the steps after it lead you there another way (Nov 8, the bot a level and a half ahead: the stops that
  -- teach Morgan's Vigil, Cenarion Hold and Talonbranch were behind it, and "Fly to" pointed at them anyway)
  if opts.flyKnown then
    for i = 1, n do
      local s = steps[i]
      if s.o == 'fly' and status[i] ~= NA and not prog.done[s.k] and opts.flyKnown(s) == false then
        status[i] = DONE
        away[i] = true   -- (and nothing below brings it back)
      end
    end
  end

  -- a flight taken to walk to a flight path you already know is passed, and the walk with it: the road wrote them to
  -- learn it (FB-055, Nov 12: Farholde Keep learned on an earlier version's road at 34; at 38 the road said "Fly to
  -- Lakeshire" and walked you there again). The steps after it lead, and a trip flies you straight there
  for i = 1, n do
    local s = steps[i]
    if s.o == 'fp' and s.id and st.taxi[s.id] and status[i] ~= NA then
      local f
      for j = i - 1, 1, -1 do
        local t = steps[j]
        if status[j] ~= NA then
          if t.o == 'fly' then f = j break end
          if t.o ~= 'goto' then break end
        end
      end
      if f and not prog.done[steps[f].k] then
        for j = f, i - 1 do
          if status[j] ~= NA and not prog.done[steps[j].k] then status[j] = DONE away[j] = true end
        end
      end
    end
  end

  -- a flight that lands farther from the next stop than you already are is passed too, like a hearth that leads away
  -- (Nov 8, the bot that walks instead of flying: two Barrens flights still on the card with the next stop nearer on
  -- foot). Not on a journey of several legs (another flight or a hearth before the next stop), and only one the route
  -- planned before where you stand: at its flight master with the next stop beyond the landing it stays
  if opts.near and opts.between then
    for i = 1, n do
      local s = steps[i]
      if s.o == 'fly' and s.p and status[i] == PENDING and not prog.done[s.k] then
        for j = i + 1, math.min(n, i + HOME_SCAN) do
          local t, v = steps[j], status[j]
          if v == PENDING and (t.o == 'fly' or t.o == 'hearth') then break end
          -- (a walk after the flight counts: it's the route saying where it goes from the landing)
          if v == PENDING and t.p and not (t.opt or t.sticky or t.tl or t.wn) and not E.asYouGo(t, st)
              and not waits(j) then
            local you, land = opts.near(t.p), opts.between(s.p, t.p)
            if you and land and land > you + HEARTH_AWAY_YARDS then status[i] = DONE away[i] = true end
            break
          end
        end
      end
    end
  end

  -- (and again: a walk and flight after a hearth the rules above passed leave the hearth leading away. Nov 9, the
  -- horde-30 bot in Feralas: "Hearth to Gadgetzan" for the flight to Thunder Bluff, Camp Mojache's flight at hand)
  hearthsAway()

  -- a flight passed because a quest after it was handed in earlier (Return to Nessa, done on an earlier visit), while
  -- you stand in neither the land it lands in nor the land the road goes on in: the flight and the walk to its flight
  -- master come back (Nov 7, the owner in Auberdine: the card said "Take the portal in Rut'theran" 3,849 yards off,
  -- with no flight to get there)
  -- The same on one land, by distance: far from where it lands and from the next step, which is near the landing (Nov 7,
  -- a Human Hunter at Sentinel Hill: "Talk to Osric Strang" 2,011 yards off in Stormwind, the flight right beside her)
  if (opts.here and opts.landOf) or (opts.near and opts.between) then
    for i = 1, n do
      local s = steps[i]
      if s.o == 'fly' and s.p and status[i] == DONE and not prog.done[s.k] and not away[i] then
        local nextUp
        for j = i + 1, math.min(n, i + HOME_SCAN) do
          local t, v = steps[j], status[j]
          if t.o == 'hearth' or t.o == 'fly' then break end
          if v == PENDING and t.p and not (t.opt or t.sticky or t.tl or t.wn) and not waits(j) then nextUp = j break end
        end
        local landed = opts.landOf and opts.landOf(s.p)
        local goal = nextUp and opts.landOf and opts.landOf(steps[nextUp].p)
        local across = opts.here and landed and goal and opts.here ~= landed and opts.here ~= goal
        local far = false
        if not across and nextUp and opts.near and opts.between then
          local near, fromLanding, toLanding = opts.near(steps[nextUp].p), opts.between(s.p, steps[nextUp].p), opts.near(s.p)
          -- (and only when its flight master is nearer you than the next step: Nov 8, FB-046, a player at the Westfall
          -- lighthouse after The Coastal Menace, who hadn't taken the road's flight from Darkshire: the card said "Fly
          -- to Sentinel Hill" and pointed back to Duskwood, to fly into the land they stood in)
          local dep = s.dp
          if not dep then
            for k = i - 1, math.max(1, i - 4), -1 do
              if status[k] ~= NA then if steps[k].o == 'goto' then dep = steps[k].p end break end
            end
          end
          local toDep = dep and opts.near(dep)
          far = near and fromLanding and toLanding and toDep and near > FLY_BACK_YARDS and toLanding > FLY_BACK_YARDS
            and fromLanding <= LANDS_NEAR_YARDS and toDep < near or false
        end
        if across or far then
          status[i] = PENDING
          for k = i - 1, math.max(1, i - 4), -1 do   -- (the walk to the flight master, just before it)
            if status[k] ~= NA then
              if steps[k].o == 'goto' and status[k] == DONE and not prog.done[steps[k].k] then status[k] = PENDING end
              break
            end
          end
        end
      end
    end
  end

  -- a journey over the sea and back is passed: with the next real stop on your continent, the walks and flights before
  -- it that touch another continent (Nov 9: the 30-60 road opens at Astranaar's flight master, flies to Auberdine and
  -- sails to Stormwind; a character who opened it in Stormwind or Ironforge was sent to Astranaar to sail back). By
  -- continent, not by the trip planner's lands: those know no flights, and the Barrens leg's flight from Zoram'gar
  -- through Orgrimmar to Thunder Bluff isn't off your way. Only walks and flights; a hearth stops it
  if opts.myCont and opts.contOf then
    local first
    for i = 1, n do
      if status[i] == PENDING and not E.asYouGo(steps[i], st) and not waits(i) then first = i break end
    end
    local fs = first and steps[first]
    if fs and (fs.o == 'goto' or fs.o == 'fly') then
      local c
      for j = first, math.min(n, first + HOME_SCAN) do
        local t, v = steps[j], status[j]
        if t.o == 'hearth' and v ~= NA then break end
        if v == PENDING and t.o ~= 'goto' and t.o ~= 'fly' and t.p and not (t.opt or t.sticky or t.tl or t.wn)
            and not E.asYouGo(t, st) then
          c = j
          break
        end
      end
      if c and opts.contOf(steps[c].p) == opts.myCont then
        local function other(pi)
          local k = pi and opts.contOf(pi)
          return k ~= nil and k ~= opts.myCont
        end
        local last
        for j = first, c - 1 do
          local t = steps[j]
          if status[j] == PENDING and (t.o == 'goto' or t.o == 'fly') then
            local off = other(t.p) or (t.o == 'fly' and other(t.dp))
            if not off and t.pa then for _, pi in ipairs(t.pa) do if other(pi) then off = true break end end end
            if off then last = j end
          end
        end
        for j = first, last or 0 do
          local t = steps[j]
          if status[j] == PENDING and (t.o == 'goto' or t.o == 'fly') and not prog.done[t.k] then
            status[j] = DONE
            away[j] = true
          end
        end
      end
    end
  end

  -- The rule behind both: the step you'd lead with is far off (or on another continent) and the way there was passed by
  -- quests handed in earlier: every walk, flight and hearth between the last step at your feet and it comes back, and
  -- the card leads you through them (Nov 7, the travel sweep: in Darnassus with its business done on an earlier visit,
  -- "Go to Darkshore 36.4, 45.6" pointed 4,060 yards over the sea, the portal and the flight passed)
  if opts.near then
    local c
    for i = 1, n do if status[i] == PENDING and not E.asYouGo(steps[i], st) and not waits(i) then c = i break end end
    local cs = c and steps[c]
    if cs and cs.p and cs.o ~= 'fly' and cs.o ~= 'hearth' then   -- (a far walk too: the way to it comes first)
      local d = opts.near(cs.p)
      local from
      if d == nil or d > TRAVEL_BACK_YARDS then
        for j = c - 1, 1, -1 do
          local u = steps[j]
          if u.p and status[j] ~= NA then
            local dj = opts.near(u.p)
            if dj and dj <= AT_FEET_YARDS then from = j break end
          end
        end
      end
      if from then
        for j = from + 1, c - 1 do
          local u = steps[j]
          -- (not a hearth to the route's inn while you're bound at another: it isn't the way there. Nov 9, the bot a
          -- level and a half ahead, bound at Camp Taurajo: "Hearth" came back on the way to the Crossroads' flight)
          local elsewhere = u.o == 'hearth' and u.bn and st.bindNpc and st.bindNpc ~= u.bn
          if (u.o == 'goto' or u.o == 'fly' or u.o == 'hearth') and status[j] == DONE and not prog.done[u.k]
              and not away[j] and not elsewhere then
            status[j] = PENDING
          end
        end
      end
    end
  end

  -- your place is the first pending step that isn't an "as you go" one (those ride along beside it) or waiting
  for i = 1, n do
    if status[i] == PENDING and not E.asYouGo(steps[i], st) and not waits(i) then view.cursor = i break end
  end
  if not view.cursor then
    -- only waiting steps are left: a quest your level can't take yet still shows; one waiting for an item that may
    -- never drop doesn't hold the route up
    local function onlyItem(i)
      local qs = E.quests(steps[i])
      if #qs == 0 then return false end
      for _, q in ipairs(qs) do if not (itemQ[q] and not st.log[q]) then return false end end
      return true
    end
    -- (nor an optional hand-in you haven't finished: at Stonetalon's end, Leaders of the Fang without the gems came
    -- back as the last card, 2,406 yards off in Thunder Bluff; nor a step that rides along, like the Washte Pawne hunt
    -- 3,370 yards south: Nov 7, the Skyborne pass)
    for i = 1, n do
      if status[i] == PENDING and not onlyItem(i) and not noGear(i) and not unfinished(i)
          and not E.asYouGo(steps[i], st) then
        view.cursor = i break
      end
    end
  end
  -- a dungeon guide's "before you go" pick-up beside you comes before a trip across the sea (or 3,000 yd) for the one
  -- listed above it (FB-067, Nov 13: in the Undercity, Razorfen Kraul's guide sent a player to the Orgrimmar
  -- zeppelin for Thunder Bluff's A Vengeful Fate, past Faranell's Going, Going, Guano! a few steps away)
  if opts.pickNear and view.cursor and steps[view.cursor].p and steps[view.cursor].o ~= 'enter' then
    local enter
    for i = view.cursor, n do if steps[i].o == 'enter' then enter = i break end end
    local here = opts.pickNear(steps[view.cursor].p)
    if enter and not (here and here <= PICK_FAR_YARDS) then   -- (across the sea, or a long way: a town's own next door stays in order)
      -- (only one you can do now: a quest to take whose quests before it are done, or a step for a quest in your log.
      -- Deadmines' Defias chain hands in in Stormwind halfway: not before Westfall's start of it)
      local quests = pack and pack.quests or {}
      local function have(q) if q < 0 then q = -q end return st.completed[q] or st.log[q] end
      local function doable(s)
        for _, q in ipairs(E.quests(s)) do
          if s.o == 'accept' then
            if st.log[q] or st.completed[q] then return false end
            local info = quests[q]
            for _, pq in ipairs(info and info.pre or {}) do if not have(pq) then return false end end
            if info and info.pre1 and #info.pre1 > 0 then
              local one = false
              for _, pq in ipairs(info.pre1) do if have(pq) then one = true end end
              if not one then return false end
            end
          elseif not st.log[q] then
            return false
          end
        end
        return true
      end
      local best, bestYards
      for i = view.cursor + 1, enter - 1 do
        local s = steps[i]
        if status[i] == PENDING and s.p and (s.o == 'accept' or QUEST_STEP[s.o]) and not E.asYouGo(s, st)
            and not waits(i) and doable(s) then
          local d = opts.pickNear(s.p)
          if d and d <= PICK_NEAR_YARDS and (not bestYards or d < bestYards) then best, bestYards = i, d end
        end
      end
      if best then view.cursor = best end
    end
  end
  -- a walk, flight or hearth before the step the card last led with never leads again, even after something changed
  -- (Nov 9: a kill in Menethil, and "Go to Darkshire's flight master", the leg's first step, came back). Quest steps
  -- can: a quest dropped or a giver that won't offer it yet sends you back for real
  local prev = opts.prev
  if prev and view.cursor and view.cursor < prev then
    local moved = false
    for i = view.cursor, prev - 1 do
      local s = steps[i]
      local o = s.o
      if status[i] == PENDING and (o == 'goto' or o == 'fly' or o == 'hearth') then status[i] = DONE moved = true
      end
    end
    if moved then
      local was = view.cursor
      view.cursor = nil
      for i = 1, n do
        if status[i] == PENDING and not E.asYouGo(steps[i], st) and not waits(i) then view.cursor = i break end
      end
      -- (nothing else to do now: the step it last led with, rather than a walk behind it)
      -- (never a step you've done or marked: that one is behind you for good)
      if not view.cursor then
        if status[prev] ~= NA and not prog.done[steps[prev].k] and not (prog.skip and prog.skip[steps[prev].k]) then
          view.cursor = prev
          status[prev] = PENDING
        else
          view.cursor = was
        end
      end
    end
  end
  -- a dungeon guide is done once only optional steps are left: the run behind you, an [opt] pick-up you never finished
  -- (Down the Scarlet Path's Crusaders in Desolace) held the Library's guide open for good, one card and no Up next,
  -- with the window looking stuck on "Show only the current step" (FB-070, Nov 14: a German Skyborne Mage at 38). An
  -- optional quest you did finish still has its hand-in shown
  if view.cursor and route.kd == 'dungeon' then
    local function ready(s)
      if s.o ~= 'turnin' then return false end
      for _, q in ipairs(E.quests(s)) do if st.log[q] and st.log[q].ready then return true end end
      return false
    end
    local left = false
    for i = 1, n do
      if status[i] == PENDING and (not steps[i].opt or ready(steps[i])) then left = true break end
    end
    if not left then view.cursor = nil end
  end
  if not view.cursor then view.done = true return view end

  -- the card holds still: the step it led with stays the lead while it's still to do and nothing in the game has changed
  -- (the engine passes it as opts.hold; Nov 9, never stranded). Arriving still moves it on: a walk, flight or hearth
  -- you've got to is done, and the engine keeps it behind you
  local hold = opts.hold
  if hold and steps[hold] and status[hold] == PENDING and hold > view.cursor then
    -- (only forward of where the rules now put you: the card never goes back to a step before it by your position)
    view.cursor, view.held = hold, true
  elseif hold and hold == view.cursor then
    view.held = true
  elseif hold and steps[hold] and view.cursor < hold then
    -- (the step it led with got done where you stand, by arriving: on from it, never back)
    local found = false
    for i = hold + 1, n do
      if status[i] == PENDING and not E.asYouGo(steps[i], st) and not waits(i) then view.cursor, view.held, found = i, true, true break end
    end
    -- (nothing ahead to do now and the rules point back at a walk, flight or hearth: the card stays where it was)
    local o = steps[view.cursor].o
    if not found and (o == 'goto' or o == 'fly' or o == 'hearth') and status[hold] ~= NA
        and not prog.done[steps[hold].k] and not (prog.skip and prog.skip[steps[hold].k]) then
      status[hold], view.cursor, view.held = PENDING, hold, true
    end
  end

  -- ahead of the plan: a later objective of a quest already in your log, planned for a level you've reached, a short
  -- walk away and nearer than your place, comes first while you're here (owner, Oct 14, a Night Elf three levels ahead:
  -- after Mist the guide sent him to Darnassus and left The Enchanted Glade's belts for its planned visit at 10)
  -- Ahead means a level past the stop in front of you, and a quest to take close by still comes first (Nov 5, the
  -- owner's Priest at 13 in Auberdine, planned at 12.9: the beach's crawler legs, nearer than Tharnariun, jumped the
  -- queue, and the town's pick-ups and the hearth never showed)
  local front = steps[view.cursor]
  local pickup = front.o == 'accept' and front.p and opts.near and opts.near(front.p)
  if not view.held and opts.near and pace > 0 and (front.pl or 0) <= pace - PULL_AHEAD
      and not (pickup and pickup <= PULL_YARDS) then
    local here = steps[view.cursor].p and opts.near(steps[view.cursor].p)
    -- not one the route does side by side with a quest you can't have yet: it waits for its pair (Nov 11, the owner in
    -- Redridge a level ahead: the gnolls' rivets and pikes came early, alone, and A Baying of Gnolls, the same camps'
    -- brutes and mystics, opened three hand-ins later, so the camps were cleared twice). Its pair: the objective steps
    -- right beside it on the route, or in its block, for a quest whose pick-up is still to come
    local toTake
    local function pairWaits(j)
      if not toTake then
        toTake = {}
        for i = 1, n do
          if steps[i].o == 'accept' and status[i] == PENDING then
            for _, q in ipairs(list(steps[i].id)) do
              if not st.log[q] and not st.completed[q] then toTake[q] = true end
            end
          end
        end
      end
      local function later(i)
        for _, q in ipairs(E.quests(steps[i])) do if toTake[q] then return true end end
        return false
      end
      for dir = -1, 1, 2 do
        local i = j + dir
        while i >= 1 and i <= n do
          local t = steps[i]
          if status[i] ~= NA and not E.asYouGo(t, st) then
            if not PULL_OPS[t.o] then break end
            -- (a pair is done in one place: the other one is round here too, or on the same loop)
            local y = t.p and opts.near(t.p)
            if later(i) and ((y and y <= PULL_YARDS * 2) or (t.lp and steps[j].lp and t.lp[1] == steps[j].lp[1])) then
              return true
            end
          end
          i = i + dir
        end
      end
      local blk = steps[j].blk
      if blk then
        for i = 1, n do if i ~= j and steps[i].blk == blk and status[i] ~= NA and later(i) then return true end end
      end
      return false
    end
    for j = view.cursor + 1, math.min(n, view.cursor + PULL_SCAN) do
      local s = steps[j]
      if status[j] == PENDING and PULL_OPS[s.o] and s.p and s.pl and s.pl <= pace and not waits(j)
          and not E.asYouGo(s, st) and not pairWaits(j) then
        local q = s.q or (type(s.id) == 'table' and s.id[1] or s.id)
        local y = q and st.log[q] and opts.near(s.p)
        if y and y <= PULL_YARDS and (not here or y < here) then
          -- the walk the route puts just before it comes with it (into the cave by its mouth: FB-027, Oct 18, a
          -- player a level ahead was sent straight at Grik'nir the Cold through the hill)
          local k = j - 1
          while k > view.cursor and status[k] == NA do k = k - 1 end
          if k > view.cursor and steps[k].o == 'goto' and (steps[k].pa or steps[k].p) and status[k] == PENDING then j = k end
          view.cursor, view.pulled = j, true
          break
        end
      end
    end
  end

  -- steps about quests you don't have yet (their pick-up still to come): a card shows them after that pick-up
  local unheld = {}
  for i = 1, n do
    if status[i] == PENDING and (QUEST_STEP[steps[i].o] or steps[i].q) then
      local any = false
      for _, q in ipairs(E.quests(steps[i])) do if st.log[q] or st.completed[q] then any = true end end
      if not any then unheld[i] = true end
    end
  end
  view.unheld = unheld
  local cur = steps[view.cursor]
  local inCurrent = {}
  if cur.blk then
    for i = 1, n do
      if steps[i].blk == cur.blk and status[i] == PENDING and (not unheld[i] or i == view.cursor) then
        table.insert(view.current, i) inCurrent[i] = true
      end
    end
  else
    view.current[1] = view.cursor
    inCurrent[view.cursor] = true
  end
  -- a "with next" step shows with the step it rides beside (and a run of them with the first that doesn't)
  if cur.wn then
    for j = view.cursor + 1, n do
      if status[j] == PENDING then
        if not inCurrent[j] then table.insert(view.current, j) inCurrent[j] = true end
        if not steps[j].wn then break end
      end
    end
  end
  -- an as-you-go step rides along while you're in its part of the world: off its map and away from its spot (another
  -- zone, a city, the tram) it waits, kept, until you're back (Nov 7, the owner's daughter on the Deeprun Tram: "Collect
  -- Elmpaw's Head", a wolf in Elwynn, rode along under-ground to Ironforge)
  local function hereFor(s)
    if not (opts.near and s.p and pack and pack.pts and pack.pts[s.p]) then return true end
    local d = opts.near(s.p)
    if d == nil then return false end
    local p = pack.pts[s.p]
    return d <= STICKY_AWAY_YARDS or (st.pos and st.pos.map == p[1])
  end
  for i = 1, view.cursor - 1 do
    if E.asYouGo(steps[i], st) and status[i] == PENDING and not inCurrent[i] and hereFor(steps[i]) then
      table.insert(view.sticky, i)
    end
  end
  -- the coin you're gathering rides along as you go (the first stop waiting for it: its trainer comes after)
  for i = 1, n do
    if steps[i].cash and status[i] == PENDING and waits(i) and not inCurrent[i] then
      table.insert(view.sticky, i)
      break
    end
  end
  local want = opts.upcoming or 3
  for i = view.cursor + 1, n do
    if #view.upcoming >= want then break end
    if status[i] == PENDING and not inCurrent[i] and not waits(i) then table.insert(view.upcoming, i) end
  end
  if cur.pl then view.behind = level - cur.pl end
  return view
end

--- the current steps nearest first, in yards when `yards(p)` is given (a city's map and its zone's compare: Nov 9, the
--- RestedXP arrow study's #7, at Stormwind's gate a stop 40 yd inside the city ranked behind one 600 yd down the road),
--- else on your own map only; the ones not measured keep their order at the end
function E.order(indices, route, pos, pts, yards, spotOf)
  local function dist(i)
    local p = (spotOf and spotOf(i)) or (route.steps[i].p and pts[route.steps[i].p])
    if not p then return math.huge end
    if yards then
      local d = yards(p)
      return d and d * d or math.huge   -- (one unit for all: yards, never mixed with map percent)
    end
    if not (pos and pos.map and pos.x and p[1] == pos.map) then return math.huge end
    local dx, dy = p[2] - pos.x, p[3] - pos.y
    return dx * dx + dy * dy
  end
  local sorted = {}
  for k, i in ipairs(indices) do sorted[k] = { i = i, d = dist(i), k = k } end
  table.sort(sorted, function(a, b) if a.d == b.d then return a.k < b.k end return a.d < b.d end)
  local out = {}
  for k, x in ipairs(sorted) do out[k] = x.i end
  return out
end
