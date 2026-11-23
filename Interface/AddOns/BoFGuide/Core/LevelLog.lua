-- Bind on Forever Guide: your leveling, level by level (Batch 4 of the RestedXP audit, Oct 18): minutes played at each
-- level, quests handed in and deaths, kept per character (BoFGuideCharDB.levels) and said in chat from the seal's menu
-- ("My leveling so far"). Minutes count while you're logged in, a minute at a time.
local _, ns = ...
local LevelLog = {}
ns.LevelLog = LevelLog

local function levels()
  local c = ns.cdb
  if not c then return nil end
  c.levels = c.levels or {}
  return c.levels
end

local function current()
  local lv = levels()
  local level = ns.st and ns.st.level
  if not (lv and type(level) == 'number') then return nil end
  lv[level] = lv[level] or { s = ns.cdb.played or 0, q = 0, d = 0 }
  return lv[level]
end

if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(60, function()
    if ns.cdb then current() ns.cdb.played = (ns.cdb.played or 0) + 60 end
  end)
end

ns.On('PLAYER_ENTERING_WORLD', function() current() end)   -- (the level you log in at starts counting now)
ns.On('PLAYER_LEVEL_UP', function(level)
  level = ns.clean(level)
  local lv = levels()
  if lv and type(level) == 'number' then lv[level] = lv[level] or { s = ns.cdb.played or 0, q = 0, d = 0 } end
end)
ns.On('QUEST_TURNED_IN', function() local e = current() if e then e.q = e.q + 1 end end)
ns.On('PLAYER_DEAD', function() local e = current() if e then e.d = e.d + 1 end end)

--- the lines to say: one per level you've had, oldest first
function LevelLog.Lines()
  local lv = levels() or {}
  local nums = {}
  for k in pairs(lv) do if type(k) == 'number' then nums[#nums + 1] = k end end
  table.sort(nums)
  local out = {}
  for i, n in ipairs(nums) do
    local e, nxt = lv[n], lv[nums[i + 1]]
    local secs = ((nxt and nxt.s) or ns.cdb.played or 0) - (e.s or 0)
    local mins = math.max(0, math.floor(secs / 60 + 0.5))
    local line = ns.L.reportLevel:format(n, mins, ns.count('questCount', e.q or 0))
    if (e.d or 0) > 0 then line = line .. ns.L.reportDeaths:format(e.d) end
    if not nxt then line = line .. ns.L.reportSoFar end
    out[#out + 1] = line
  end
  return out
end

function LevelLog.Say()
  local lines = LevelLog.Lines()
  if #lines == 0 then return ns.say(ns.L.reportNone) end
  ns.say(ns.L.reportTitle)
  for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage('  ' .. l) end
end
