-- The only place that reads the game. It builds one plain table (ns.st) that the evaluator works from:
--   ready        false until the quest log has been read once after login (the completed list can be empty before)
--   level, xp, xpMax, race, class, faction ('horde'|'alliance'), hc
--   completed    [questID] = true (full read at login, then each turn-in as it happens)
--   log          [questID] = { ready = bool, obj = {{ fin, have, need, text }} }, logCount, logMax
--   pos          { map, x, y } in percent; zone, sub: the zone and place names the game shows (for "you're in
--                the town your hearth is set to", as RestedXP's hearth steps check)
--   taxi         [nodeID] = true (kept per character; read whenever the flight map opens)
--   bind, bindNpc  hearth location name and the innkeeper it was set at
--   items        [itemID] = count, for the items the active route asks for
--   cash         your money plus what your gray items sell for, in copper (only for a route with a stop that waits
--                for coin)
--   profs        [profession] = rank ('cooking', 'herbalism', ...); profMax [profession] = the current cap (75, 150 ...)
--   known        [spellID] = true for the recipes the shown profession guide teaches
--   inst         the instance map you're in (nil outside); runStart: when you last went into the shown guide's
--                instance; kills [encounterID] = time of the last kill; dungeons [guide route id] = time it was done
-- A value the game hides (secret) keeps its last known value, and that part is marked stale; stale data never
-- completes a step.
local _, ns = ...

local clean = ns.clean
local st = { ready = false, completed = {}, log = {}, logCount = 0, logMax = 40, pos = {}, taxi = {}, items = {},
             profs = {}, profMax = {}, known = {}, stale = {}, level = 1, xp = 0, xpMax = 1 }
ns.st = st
local State = {}
ns.State = State

local FACTIONS = { Horde = 'horde', Alliance = 'alliance' }

function State.Player()
  st.level = clean(UnitLevel('player')) or st.level
  st.xp = clean(UnitXP('player')) or st.xp
  st.xpMax = clean(UnitXPMax('player')) or st.xpMax
  if st.xpMax == 0 then st.xpMax = 1 end
  st.race = select(3, UnitRace('player'))
  st.class = select(3, UnitClass('player'))
  st.faction = FACTIONS[clean((UnitFactionGroup('player')))] or st.faction
  local mode = ns.settings and ns.settings.hc or 'auto'
  if mode == 'on' then st.hc = true
  elseif mode == 'off' then st.hc = false
  else st.hc = (C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive()) and true or false end
end

function State.Completed()
  local ids = C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()
  if type(ids) ~= 'table' then st.stale.completed = true return end
  local done = {}
  for _, id in ipairs(ids) do
    id = clean(id)
    if id then done[id] = true end
  end
  -- turn-ins seen this session stay, even if the server's list hasn't caught up yet
  for id in pairs(st.completed) do done[id] = true end
  st.completed = done
  st.stale.completed = nil
end

-- one quest's entry: ready to hand in, and its objectives (stale: an objective the game hasn't sent yet)
local function readEntry(id, i)
  local e, stale = { obj = {}, index = i }, false
  local ready = clean(C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id))
  if ready == nil then ready = clean(C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)) end
  e.ready = ready and true or false
  local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
  if type(objs) == 'table' then
    for k, o in ipairs(objs) do
      local fin, have, need = clean(o.finished), clean(o.numFulfilled), clean(o.numRequired)
      if fin == nil then stale = true end
      e.obj[k] = { fin = fin and true or false, have = have or 0, need = need or 1, text = clean(o.text),
                   type = clean(o.type) }
    end
  end
  return e, stale
end

function State.Log()
  local n, total = 0, nil
  if C_QuestLog.GetNumQuestLogEntries then n, total = C_QuestLog.GetNumQuestLogEntries() end
  n, total = clean(n) or 0, clean(total)
  local log, count, stale = {}, 0, false
  for i = 1, n do
    local info = C_QuestLog.GetInfo(i)
    local id = info and not info.isHeader and clean(info.questID)
    if id then
      count = count + 1
      local e, late = readEntry(id, i)
      if late then stale = true end
      log[id] = e
    end
  end
  st.log, st.logCount = log, math.max(count, total or 0)
  -- quests under a collapsed header aren't among the shown entries (retail's quest log, Forever's): the route's own
  -- are asked about one by one (State.LogFill), or a collapsed zone's quests read as dropped (Nov 8, the RestedXP
  -- client study: their guide expands the headers before every read; we leave the player's quest log as it is)
  st.logHidden = (total and total > count) and (total - count) or nil
  st.logMax = (C_QuestLog.GetMaxNumQuestsCanAccept and clean(C_QuestLog.GetMaxNumQuestsCanAccept())) or 40
  st.stale.log = stale or nil
end

--- the quests a collapsed header hid, among `ids` (the route's): asked one by one, never by changing the quest log
function State.LogFill(ids)
  if not st.logHidden then return end
  for _, id in ipairs(ids or {}) do
    if not st.log[id] and clean(C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id)) then
      st.log[id] = readEntry(id, nil)
    end
  end
end

function State.Position()
  st.zone = clean(GetZoneText and GetZoneText()) or st.zone
  st.sub = clean(GetSubZoneText and GetSubZoneText())
  local map = clean(C_Map.GetBestMapForUnit('player'))
  if not map then st.stale.pos = true return end
  local ok, p = pcall(C_Map.GetPlayerMapPosition, map, 'player')
  local x, y = ok and p and clean(p.x), ok and p and clean(p.y)
  if x and y and (x > 0 or y > 0) then
    st.pos = { map = map, x = x * 100, y = y * 100 }
    st.stale.pos = nil
  else
    st.pos = { map = map }   -- in an instance or a cave: we know the map, not the spot
    st.stale.pos = true
  end
end

function State.Bind()
  st.bind = clean(GetBindLocation and GetBindLocation()) or st.bind
  st.bindNpc = ns.cdb and ns.cdb.bindNpc
  st.notOffered = ns.cdb and ns.cdb.notOffered   -- quests their giver didn't offer you (Engine: checkOffers)
end

function State.Taxi()
  st.taxi = ns.cdb and ns.cdb.taxi or st.taxi
end

-- profession skill lines (client SkillLine IDs) -> the names routes use in [prof=...] and skill steps
State.PROFESSIONS = { [129] = 'firstaid', [164] = 'blacksmithing', [165] = 'leatherworking', [171] = 'alchemy',
                      [182] = 'herbalism', [185] = 'cooking', [186] = 'mining', [197] = 'tailoring', [202] = 'engineering',
                      [333] = 'enchanting', [356] = 'fishing', [393] = 'skinning' }
-- Forever splits each profession the retail way: a child line under the classic one (SkillLine.ParentSkillLineID,
-- build 70245). Recipes give their points to the child (SkillLineAbility.SkillupSkillLineID) and Forever's own rank
-- spells raise it, so the child is read first and the classic line is the fallback.
State.CHILD = { [129] = 2942, [164] = 2938, [165] = 2945, [171] = 2937, [182] = 2944, [185] = 2939, [186] = 2946,
                [197] = 2948, [202] = 2941, [333] = 2940, [356] = 2943, [393] = 2947 }

--- rank and cap of one skill line, or nil when the character doesn't have it (or the game hides it)
function State.SkillLine(id)
  local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, id)
  local rank = ok and info and clean(info.rank)
  if rank and rank > 0 then return rank, clean(info.maxRank) end
  return nil
end

--- st.profs[name] = rank and st.profMax[name] = its cap, for the professions this character has;
--- st.profLine[name] = the skill line they were read from
function State.Professions()
  if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return end
  local profs, caps, lines = {}, {}, {}
  for id, name in pairs(State.PROFESSIONS) do
    local line = State.CHILD[id]
    local rank, cap = State.SkillLine(line)
    if not rank then line = id rank, cap = State.SkillLine(id) end
    if rank then
      profs[name], lines[name] = rank, line
      -- a rank from a book can raise the classic line's cap while the child's stays (Expert First Aid - Under Wraps):
      -- the higher of the two (Oct 11, the profession review)
      local _, other = State.SkillLine(line == id and State.CHILD[id] or id)
      caps[name] = math.max(cap or 0, other or 0) > 0 and math.max(cap or 0, other or 0) or st.profMax[name]
    end
  end
  st.profs, st.profMax, st.profLine = profs, caps, lines
end

local BANK_PLAYER = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
--- st.known[spell] for a profession guide's recipes; a hidden answer keeps the last one
function State.Known(ids)
  local known = {}
  for id in pairs(ids or {}) do
    local v
    if C_SpellBook and C_SpellBook.IsSpellKnown then
      local ok, r = pcall(C_SpellBook.IsSpellKnown, id, BANK_PLAYER)
      if ok then v = clean(r) end
    end
    if v == nil and IsPlayerSpell then
      local ok, r = pcall(IsPlayerSpell, id)
      if ok then v = clean(r) end
    end
    if v == nil then known[id] = st.known[id] else known[id] = v and true or false end
  end
  st.known = known
end

local FP_UNREACHABLE = (Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable) or 2
--- when the flight map is open: every node this character can fly to is known
function State.ReadTaxiMap()
  if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
  local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, clean(C_Map.GetBestMapForUnit('player')))
  if not ok or type(nodes) ~= 'table' then return end
  local wide = false
  for _, n in ipairs(nodes) do
    local id, state = clean(n.nodeID), clean(n.state)
    if id and state ~= FP_UNREACHABLE then ns.cdb.taxi[id] = true end
    local px, py = n.position and clean(n.position.x), n.position and clean(n.position.y)
    if px and py and (px < 0 or px > 1 or py < 0 or py > 1) then wide = true end
  end
  -- (the whole continent's flight paths read, which the game shows by listing ones beyond the map you're on: a flight
  -- to one not listed is one you can't take. Only then; a list of your zone's alone says nothing of the rest. Nov 8)
  local c = wide and ns.Geo and ns.Geo.World(clean(C_Map.GetBestMapForUnit('player')), 50, 50)
  if c then ns.cdb.taxiRead = ns.cdb.taxiRead or {} ns.cdb.taxiRead[c] = true end
  st.taxi = ns.cdb.taxi
end

--- item counts for the items a route asks for
function State.Items(ids)
  local items = {}
  for id in pairs(ids or {}) do
    local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id))
    items[id] = clean(n) or st.items[id] or 0
  end
  st.items = items
end

--- your money and what your gray items sell for (copper): a "sell your junk, then train" stop waits for this
function State.Cash()
  local money = clean(GetMoney and GetMoney()) or 0
  local junk = 0
  local C = C_Container
  if C and C.GetContainerNumSlots and C.GetContainerItemInfo then
    for bag = 0, (NUM_BAG_SLOTS or 4) do
      for slot = 1, clean(C.GetContainerNumSlots(bag)) or 0 do
        local info = C.GetContainerItemInfo(bag, slot)
        local id = info and clean(info.itemID)
        if id and clean(info.quality) == 0 and not clean(info.hasNoValue) then
          local price = C_Item and C_Item.GetItemInfo and clean(select(11, C_Item.GetItemInfo(id)))
          if type(price) == 'number' then junk = junk + price * (clean(info.stackCount) or 1) end
        end
      end
    end
  end
  st.cash = money + junk
end

--- which of the items a route has you equip you're wearing
function State.Equipped(ids)
  local out = {}
  for id in pairs(ids or {}) do
    local worn = (C_Item and C_Item.IsEquippedItem and C_Item.IsEquippedItem(id))
      or (IsEquippedItem and IsEquippedItem(id))
    out[id] = clean(worn) and true or nil
  end
  st.equipped = out
end

--- the instance you're in, and when this run of it began (kept per character, so a /reload inside isn't a new run).
--- Going back in after a death, a wipe or a trip out to repair is the same run: a new one starts only once the last
--- boss died, the game said the dungeon was reset, or you've been out of it for RUN_GAP (Nov 7: the Hall of Thanes
--- dropped Faldrim and Infurnus from a run when the owner went back in halfway)
State.RUN_GAP = 30 * 60
function State.Instance()
  local _, itype, _, _, _, _, _, id = GetInstanceInfo()
  local inst = (itype == 'party' or itype == 'raid') and clean(id) or nil
  local c = ns.cdb
  if c then
    local now = time()
    if inst and c.inInst ~= inst then
      local start, seen = c.entered[inst], c.seen[inst]
      if not (start and seen) or now - seen > State.RUN_GAP or (c.cleared[inst] or 0) >= start
          or (c.reset or 0) >= start then
        c.entered[inst] = now
      end
    end
    if inst then c.seen[inst] = now end
    c.inInst = inst
    st.kills, st.dungeons = c.kills, c.dungeons
  end
  st.inst = inst
end

--- the Legacy challenges (account achievements) a route's steps name: ach [id] = done; crit ['id.n'] = done. A
--- criteria is found by its words first (the order the client lists them in is its own), then by its place.
function State.Achievements(route)
  local ach, crit = {}, {}
  local function done(id)
    if ach[id] == nil then
      local ok, _, _, _, completed = pcall(GetAchievementInfo, id)
      ach[id] = ok and clean(completed) == true
    end
    return ach[id]
  end
  for _, s in ipairs(route and route.steps or {}) do
    if s.o == 'legacy' and s.id then done(s.id) end
    if s.ac and s.cr then
      local key = s.ac .. '.' .. s.cr
      if done(s.ac) then
        crit[key] = true
      else
        local okN, n = pcall(GetAchievementNumCriteria, s.ac)
        n = okN and clean(n) or 0
        local hit
        for i = 1, n do
          local okC, text, _, completed = pcall(GetAchievementCriteriaInfo, s.ac, i)
          if okC and s.ct and clean(text) == s.ct then hit = clean(completed) == true end
        end
        if hit == nil then
          local okC, _, _, completed = pcall(GetAchievementCriteriaInfo, s.ac, s.cr)
          hit = okC and clean(completed) == true
        end
        crit[key] = hit
      end
    end
  end
  st.ach, st.crit = ach, crit
end

function State.All(itemIDs)
  State.Player()
  State.Completed()
  State.Log()
  State.Position()
  State.Bind()
  State.Taxi()
  State.Professions()
  State.Instance()
  State.Items(itemIDs)
end
