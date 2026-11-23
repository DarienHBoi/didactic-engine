-- Automation (on by default; /bofg auto ... or the AUTO switch turns it off). It only acts on what the route asks for:
--   accept   take a quest the route takes next (within the next 40 steps from your place; past 12, not a timed one
--            or one held for a level above yours)
--   turnin   hand in a quest the route turns in when there's no reward to choose (none, or just one). With several,
--            the choice is always yours (owner, Oct 11: it used to pick the route's or your class's item)
--   gossip   pick the route's quest in an NPC's list (turn-ins first), else the option a step on screen names
--            (gossip=N in the route). The list is either the conversation window (GOSSIP_SHOW) or, for an NPC with
--            only quests to offer, the quest greeting panel (QUEST_GREETING: "What do you need of me?")
--   taxi     fly to the route's flight step when the flight map opens
-- Never in combat, never while Shift, Ctrl or Alt is held (to do it yourself), and never again this session
-- after the game blocks an action.
local _, ns = ...

local Auto = {}
ns.Auto = Auto
local WINDOW = 40
local NEAR = 12   -- steps: within these, any quest the route takes; further, see farOk

--- whether automation may act now; when it may not, why ('off', 'combat', 'modifier', 'blocked', 'paused', 'peeking')
function Auto.Enabled(kind)
  local a = ns.settings and ns.settings.auto
  if not (a and a[kind]) then return false, 'off' end
  if InCombatLockdown() then return false, 'combat' end
  if IsModifierKeyDown and IsModifierKeyDown() then return false, 'modifier' end
  local held = ns.AutoHeld and ns.AutoHeld()
  if held then return false, held end
  if ns.Engine.Peeking and ns.Engine.Peeking() then return false, 'peeking' end   -- (looking back at an earlier step)
  return true
end

-- What automation saw and did at each quest window, the last 20 (BoFGuideDB.autoLog; /bofg report shows the last,
-- /bofg autolog the rest). Nov 5, FB-038: a tester's The Jasperlode Mine wasn't taken at Marshal Dughan, two hand-ins
-- and three quests to take, and nothing said why
local LOG_KEEP = 20

function Auto.Note(ev, q, did, why, seen)
  if not ns.db then return end
  local log = ns.db.autoLog or {}
  ns.db.autoLog = log
  log[#log + 1] = { at = time(), ev = ev, q = q, did = did, why = why, seen = seen }
  while #log > LOG_KEEP do table.remove(log, 1) end
end

--- one entry as a line: when, the window, the quest, what was done or why not, and what the NPC offered
function Auto.Line(e)
  if not e then return nil end
  return ('%s %s %s %s%s'):format(date('%H:%M:%S', e.at or 0), e.ev or '-', tostring(e.q or '-'),
    e.did or ('not: ' .. tostring(e.why or '?')), e.seen and (' [' .. e.seen .. ']') or '')
end

function Auto.LastLine() return Auto.Line(ns.db and ns.db.autoLog and ns.db.autoLog[#ns.db.autoLog]) end

--- a quest the route takes well ahead of your place (past NEAR steps): only one that isn't timed and isn't held for a
--- level above yours (Nov 8, the RestedXP automation study: met early, a timed quest like Scalding Mornbrew ran out
--- before the route got there, and a quest kept back for a higher level was taken at once)
local function farOk(route, s)
  local level = ns.st and ns.st.level or 1
  if (s.pl or 0) > level + 1 then return false end
  for _, ni in ipairs(s.nt or {}) do
    local note = route.pack and route.pack.notes and route.pack.notes[ni]
    if note and note.t and note.t:find('^Timed') then return false end
  end
  return true
end

--- quests the route wants taken and turned in from your place on
function Auto.Wanted()
  local take, give = {}, {}
  local function from(route, view)
    if not (route and view and view.status and view.cursor) then return end
    for i, s in ipairs(route.steps) do
      if view.status[i] == 'pending' then
        -- (Hardcore mode: a group quest or one with an elite to kill is left for you to read and decide; Nov 8, the
        -- RestedXP automation study: the Hardcore setting changed nothing in automation)
        local hcHold = ns.st and ns.st.hc and (s.grp or s.el)
        if s.o == 'accept' and not hcHold and i <= view.cursor + WINDOW and (i <= view.cursor + NEAR or farOk(route, s)) then
          for _, q in ipairs(ns.list(s.id)) do take[q] = true end
        elseif s.o == 'turnin' then
          for _, q in ipairs(ns.list(s.id)) do give[q] = true end
        end
      end
    end
  end
  from(ns.Engine.Route(), ns.Engine.View())
  from(ns.Engine.Under())          -- the leveling route under a pinned gathering, profession or Legacy guide
  return take, give
end

local function questID() return ns.clean(GetQuestID and GetQuestID()) end

--- 'Read new quests' (settings.readNew): a quest no character on this account has finished yet is left open for
--- you to read; the ones you've done before are taken as usual
function Auto.Unread(q)
  return ns.settings.readNew and not (ns.db.seen and ns.db.seen[q]) or false
end

ns.On('QUEST_DETAIL', function()
  local q = questID()
  local ok, why = Auto.Enabled('accept')
  if not ok then return Auto.Note('detail', q, nil, why) end
  if not q then return Auto.Note('detail', nil, nil, 'no quest id') end
  if not Auto.Wanted()[q] then return Auto.Note('detail', q, nil, 'not next in the route') end
  if Auto.Unread(q) then return Auto.Note('detail', q, nil, 'left to read') end
  if Auto.StartsEvent(q) then return Auto.Note('detail', q, nil, 'starts an escort') end
  AcceptQuest()
  Auto.Note('detail', q, 'accept')
end)

ns.On('QUEST_TURNED_IN', function(q)
  q = ns.clean(q)
  if q and ns.db then ns.db.seen = ns.db.seen or {} ns.db.seen[q] = true end
end)

ns.On('QUEST_PROGRESS', function()
  local q = questID()
  local ok, why = Auto.Enabled('turnin')
  if not ok then return Auto.Note('progress', q, nil, why) end
  local _, give = Auto.Wanted()
  if not (q and give[q]) then return Auto.Note('progress', q, nil, 'not a hand-in in the route') end
  if not (IsQuestCompletable and IsQuestCompletable()) then return Auto.Note('progress', q, nil, 'not finished') end
  CompleteQuest()
  Auto.Note('progress', q, 'continue')
end)

-- the reward the route picks for your class (RestedXP's picks, kept as facts: a quest's rwc): said in chat and outlined
-- in the reward window by a frame of ours over Blizzard's button; the pick stays yours (the RestedXP audit, Oct 18)
--- a quest whose taking starts an escort or an event (QuestieDB's event flag: Pyrewood Ambush, Missing In Action):
--- you take it when you're ready, never automation (the RestedXP audit, Oct 18)
function Auto.StartsEvent(q)
  for _, r in ipairs({ ns.Engine.Route(), ns.Engine.Leveling() }) do
    local info = r and r.pack and r.pack.quests and r.pack.quests[q]
    if info and info.ne then return true end
  end
  return false
end

local mark
function Auto.RewardPick(q)
  local route, who = ns.Engine.Route(), ns.Engine.Who()
  for _, r in ipairs({ route, ns.Engine.Leveling() }) do
    local info = r and r.pack and r.pack.quests and r.pack.quests[q]
    if info and info.rwc and info.rwc[who.class] then return info.rwc[who.class] end
  end
  return nil
end

local function markReward(q)
  if mark then mark:Hide() end
  local i = q and Auto.RewardPick(q)
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if not i or n < 2 or i > n then return end
  local link = GetQuestItemLink and GetQuestItemLink('choice', i)
  ns.say(ns.L.rewardPick:format(link or ns.L.rewardNumber:format(i)))
  local frame = QuestInfoFrame and QuestInfoFrame.rewardsFrame
  for _, b in ipairs(frame and frame.RewardButtons or {}) do
    if b.type == 'choice' and b.objectType == 'item' and b:GetID() == i and b:IsShown() then
      if not mark then
        mark = CreateFrame('Frame', 'BoFGuideRewardMark', UIParent, 'BackdropTemplate')
        mark:SetFrameStrata('DIALOG')
        if mark.SetBackdrop then
          mark:SetBackdrop({ edgeFile = 'Interface/Buttons/WHITE8X8', edgeSize = 2 })
          mark:SetBackdropBorderColor(0.94, 0.76, 0.35, 1)
        end
        mark:EnableMouse(false)
      end
      mark:ClearAllPoints()
      mark:SetPoint('TOPLEFT', b, 'TOPLEFT', -3, 3)
      mark:SetPoint('BOTTOMRIGHT', b, 'BOTTOMRIGHT', 3, -3)
      mark:Show()
    end
  end
end

ns.On('QUEST_FINISHED', function() if mark then mark:Hide() end end)

ns.On('QUEST_COMPLETE', function()
  -- (after Blizzard has drawn its reward buttons for the same event)
  local shown = questID()
  if C_Timer and C_Timer.After then C_Timer.After(0, function() ns.safecall('reward', markReward, shown) end) end
  local q = questID()
  local ok, why = Auto.Enabled('turnin')
  if not ok then return Auto.Note('reward', q, nil, why) end
  local _, give = Auto.Wanted()
  if not (q and give[q]) then return Auto.Note('reward', q, nil, 'not a hand-in in the route') end
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n > 1 then return Auto.Note('reward', q, nil, 'a reward to choose') end   -- several to choose from: yours to pick
  GetQuestReward(n)
  Auto.Note('reward', q, 'hand in')
end)

--- what an NPC's list holds, short: "in 62+ 40+ | new 91777 35 76" (+ ready to hand in)
local function listed(active, avail)
  local a, o = {}, {}
  for _, x in ipairs(active) do a[#a + 1] = tostring(x[1]) .. (x[2] and '+' or '') end
  for _, x in ipairs(avail) do o[#o + 1] = tostring(x) end
  return ('in %s | new %s'):format(#a > 0 and table.concat(a, ' ') or '-', #o > 0 and table.concat(o, ' ') or '-')
end

ns.On('GOSSIP_SHOW', function()
  local active, avail = {}, {}
  for _, info in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
    active[#active + 1] = { ns.clean(info.questID), ns.clean(info.isComplete) and true or false }
  end
  for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do avail[#avail + 1] = ns.clean(info.questID) or false end
  local seen = listed(active, avail)
  local ok, why = Auto.Enabled('gossip')
  if not ok then return Auto.Note('gossip', nil, nil, why, seen) end
  local take, give = Auto.Wanted()
  for _, x in ipairs(active) do
    if x[1] and give[x[1]] and x[2] then
      C_GossipInfo.SelectActiveQuest(x[1])
      return Auto.Note('gossip', x[1], 'pick to hand in', nil, seen)
    end
  end
  for _, q in ipairs(avail) do
    if q and take[q] then   -- opens the text; accepting waits if unread
      C_GossipInfo.SelectAvailableQuest(q)
      return Auto.Note('gossip', q, 'pick to take', nil, seen)
    end
  end
  if #active + #avail > 0 then Auto.Note('gossip', nil, nil, 'none of these next in the route', seen) end
  local route, want = ns.Engine.Route(), {}
  for _, i in ipairs(route and ns.Engine.OnScreen() or {}) do
    for _, g in ipairs(route.steps[i].gs or {}) do want[g] = true end
  end
  if not next(want) or not C_GossipInfo.GetOptions then return end
  for _, opt in ipairs(C_GossipInfo.GetOptions() or {}) do
    local id = ns.clean(opt.gossipOptionID)
    if id and want[id] then C_GossipInfo.SelectOption(id) return end
  end
end)

-- the quest greeting panel lists by position, not by quest: active quests first, then the ones on offer
ns.On('QUEST_GREETING', function()
  local active, avail = {}, {}
  for i = 1, ns.clean(GetNumActiveQuests and GetNumActiveQuests()) or 0 do
    local _, done = GetActiveTitle(i)
    active[i] = { ns.clean(GetActiveQuestID and GetActiveQuestID(i)), ns.clean(done) and true or false }
  end
  for i = 1, ns.clean(GetNumAvailableQuests and GetNumAvailableQuests()) or 0 do
    avail[i] = GetAvailableQuestInfo and ns.clean((select(5, GetAvailableQuestInfo(i)))) or false
  end
  local seen = listed(active, avail)
  local ok, why = Auto.Enabled('gossip')
  if not ok then return Auto.Note('greeting', nil, nil, why, seen) end
  local take, give = Auto.Wanted()
  for i, x in ipairs(active) do
    if x[1] and give[x[1]] and x[2] then
      SelectActiveQuest(i)
      return Auto.Note('greeting', x[1], 'pick to hand in', nil, seen)
    end
  end
  for i, q in ipairs(avail) do
    if q and take[q] then   -- opens the text; accepting waits if unread
      SelectAvailableQuest(i)
      return Auto.Note('greeting', q, 'pick to take', nil, seen)
    end
  end
  if #active + #avail > 0 then Auto.Note('greeting', nil, nil, 'none of these next in the route', seen) end
end)

local REACHABLE = (Enum and Enum.FlightPathState and Enum.FlightPathState.Reachable) or 1
ns.On('TAXIMAP_OPENED', function()
  -- (every way out is written to the automation log, /bofg autolog: the owner's flight to Lakeshire didn't start on
  -- Nov 11 and nothing said why)
  local on, why = Auto.Enabled('taxi')
  if not on then return Auto.Note('flight', nil, nil, why) end
  local route = ns.Engine.Route()
  local dest
  for _, i in ipairs(ns.Engine.OnScreen()) do
    local s = route.steps[i]
    if s.o == 'fly' then dest = s.id break end
  end
  -- a flight the guide worked out itself, on a "The way to ..." card, is no step of the route: it's taken too (Nov 11,
  -- the owner at Lakeshire: "The way to Westfall: Fly to Sentinel Hill" never started, a route's own flight beside
  -- them did)
  local trip = not dest and ns.Travel and ns.Travel.Active()
  if trip and trip.fly and not trip.fly.flying then dest = trip.fly.node end
  if not dest then return Auto.Note('flight', nil, nil, 'no flight on the card') end
  local map = ns.clean(C_Map.GetBestMapForUnit('player'))
  local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, map)
  if not ok or type(nodes) ~= 'table' then return Auto.Note('flight', dest, nil, 'no flight list for map ' .. tostring(map)) end
  local found
  for _, n in ipairs(nodes) do
    if ns.clean(n.nodeID) == dest then
      found = 'state ' .. tostring(ns.clean(n.state)) .. ', slot ' .. tostring(ns.clean(n.slotIndex))
      if ns.clean(n.state) == REACHABLE and n.slotIndex then
        -- (the route worked out first, as Blizzard's map does on a hover, so a flight with a change of flight master
        -- starts; only where the client has it, and never an error. Nov 8, the RestedXP client study; /bofg selftest
        -- reports what it says)
        if type(GetNumRoutes) == 'function' then pcall(GetNumRoutes, n.slotIndex) end
        TakeTaxiNode(n.slotIndex)
        return Auto.Note('flight', dest, 'taken, slot ' .. tostring(ns.clean(n.slotIndex)), nil, #nodes .. ' on map ' .. tostring(map))
      end
    end
  end
  Auto.Note('flight', dest, nil, found and ('not reachable: ' .. found) or 'not in the list', #nodes .. ' on map ' .. tostring(map))
end)
