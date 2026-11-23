-- Clean up the quest log (owner, Oct 15): drop the quests the guide never uses, on the player's say-so.
-- A quest is only offered for dropping when no route of any loaded pack has a step for it (so one picked up early for
-- a later leg, a dungeon guide or a class chain stays), it isn't finished (a finished quest is worth handing in), it
-- isn't above the levels the loaded routes reach (the guide can't speak for what comes after it), and the game lets it
-- be abandoned. Nothing is dropped without the confirmation that lists the quests by name, and never in combat.
local _, ns = ...
local L = ns.L
local Cleanup = {}
ns.Cleanup = Cleanup
local clean = ns.clean

--- every quest any loaded pack knows: its routes' quest steps and its quest table
local function known()
  local ids, top = {}, 0
  for _, pack in pairs(ns.Packs.byId or {}) do
    for id in pairs(pack.quests or {}) do ids[id] = true end
    for _, r in ipairs(pack.routes or {}) do
      if not r.kd and type(r.lv) == 'table' and (r.lv[2] or 0) > top then top = r.lv[2] end
      for _, s in ipairs(r.steps) do
        if s.o == 'accept' or s.o == 'turnin' or s.o == 'complete' or s.o == 'abandon' then
          for _, id in ipairs(type(s.id) == 'table' and s.id or { s.id }) do ids[id] = true end
        end
        if s.q then ids[s.q] = true end
      end
    end
  end
  return ids, top
end

--- the quests in the log the guide has no use for: { { id, title, level }, ... }, and why the others stay
function Cleanup.Candidates()
  local ids, top = known()
  local out, kept = {}, { guide = 0, ready = 0, above = 0, locked = 0 }
  if not next(ids) then return out, kept end               -- no pack loaded: the guide can't judge anything
  local n = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
  for i = 1, n do
    local info = C_QuestLog.GetInfo(i)
    local id = info and not info.isHeader and not info.isHidden and clean(info.questID)
    if id then
      local level = clean(info.level)
      local ready = clean(C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id))
      if ready == nil then ready = clean(C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)) end
      if ids[id] then kept.guide = kept.guide + 1
      elseif ready then kept.ready = kept.ready + 1
      elseif level and top > 0 and level > top + 2 then kept.above = kept.above + 1
      elseif C_QuestLog.CanAbandonQuest and clean(C_QuestLog.CanAbandonQuest(id)) == false then kept.locked = kept.locked + 1
      else
        out[#out + 1] = { id = id, title = clean(info.title) or (L.cleanupQuest:format(id)), level = level }
      end
    end
  end
  return out, kept
end

--- drop them (the confirmed list); returns how many
function Cleanup.Drop(list)
  if InCombatLockdown and InCombatLockdown() then ns.say(L.cleanupCombat) return 0 end
  if not (C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest) then
    ns.say(L.cleanupNoApi)
    return 0
  end
  local n = 0
  for _, q in ipairs(list) do
    C_QuestLog.SetSelectedQuest(q.id)
    C_QuestLog.SetAbandonQuest()
    -- (the game's own check that the selection took: never drop anything but the quest named)
    local picked = C_QuestLog.GetAbandonQuest and clean(C_QuestLog.GetAbandonQuest())
    if picked == nil or picked == q.id then
      C_QuestLog.AbandonQuest()
      n = n + 1
    end
  end
  ns.say(ns.count('cleanupDone', n))
  return n
end

local function names(list)
  local t = {}
  for i, q in ipairs(list) do
    if i > 12 then t[#t + 1] = L.cleanupMore:format(#list - 12) break end
    t[#t + 1] = q.title
  end
  return table.concat(t, '\n')
end

--- the settings button and /bofg cleanup: say what would go and ask
function Cleanup.Ask()
  local list, kept = Cleanup.Candidates()
  if #list == 0 then
    ns.say(kept.guide + kept.ready + kept.above + kept.locked > 0 and L.cleanupNothing or L.cleanupEmpty)
    return list
  end
  Cleanup.pending = list
  if StaticPopupDialogs and StaticPopup_Show then
    StaticPopupDialogs.BOFGUIDE_CLEANUP = StaticPopupDialogs.BOFGUIDE_CLEANUP or {
      text = '%s', button1 = YES or 'Yes', button2 = NO or 'No', timeout = 0, whileDead = false, hideOnEscape = true,
      OnAccept = function() ns.safecall('cleanup', Cleanup.Drop, Cleanup.pending or {}) Cleanup.pending = nil end,
      OnCancel = function() Cleanup.pending = nil end,
    }
    StaticPopup_Show('BOFGUIDE_CLEANUP', ns.count('cleanupAsk', #list, names(list)))
  else
    ns.say(ns.count('cleanupList', #list, (names(list):gsub('\n', ', '))))
  end
  return list
end
