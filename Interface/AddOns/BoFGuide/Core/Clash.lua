-- Bind on Forever Guide: other addons that fight the guide, said once (the RestedXP audit, Oct 18: their users report
-- the same clashes). Each notice comes once per account and again only after the clash went away and came back.
--   Questie's own quest automation (Questie.db.profile.autoAccept.enabled, .autocomplete): it takes every quest
--     offered, not only the route's. (Since Questie 12.2 it hands in only quests with no reward choice, so the
--     guide's pick holds; read Oct 24, docs/guide/competitors.md.)
--   Leatrix Plus's "Automate quests" (LeaPlusDB.AutomateQuests = 'On'; Oct 24, the competitor pass: the RestedXP guides
--     warn about it next to Questie's): the same, it takes every quest offered.
--   DialogueUI: its own quest window, where the guide's gold outline on the reward to take doesn't show.
local _, ns = ...
local Clash = {}
ns.Clash = Clash

local function loaded(name)
  return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) and true or false
end

--- the clashes now: { key = notice text }
function Clash.Find()
  local out = {}
  local q = rawget(_G, 'Questie')
  local p = type(q) == 'table' and type(q.db) == 'table' and type(q.db.profile) == 'table' and q.db.profile
  local ours = ns.settings and ns.settings.auto and (ns.settings.auto.accept or ns.settings.auto.turnin)
  if p and ours and ((type(p.autoAccept) == 'table' and p.autoAccept.enabled) or p.autocomplete) then
    out.questie = ns.L.clashQuestie
  end
  local lp = rawget(_G, 'LeaPlusDB')
  if ours and type(lp) == 'table' and lp.AutomateQuests == 'On' then out.leatrix = ns.L.clashLeatrix end
  if loaded('DialogueUI') then out.dialogueui = ns.L.clashDialogueUI end
  return out
end

function Clash.Check()
  if not ns.db then return end
  ns.db.clashSaid = ns.db.clashSaid or {}
  local now = Clash.Find()
  for key, text in pairs(now) do
    if not ns.db.clashSaid[key] then ns.say(text) ns.db.clashSaid[key] = true end
  end
  for key in pairs(ns.db.clashSaid) do if not now[key] then ns.db.clashSaid[key] = nil end end
end

ns.On('PLAYER_LOGIN', function()
  if C_Timer and C_Timer.After then C_Timer.After(8, function() ns.safecall('clash', Clash.Check) end) end
end)
