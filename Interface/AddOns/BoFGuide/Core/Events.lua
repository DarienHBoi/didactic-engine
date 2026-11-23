-- One event frame for the addon. Handlers subscribe with ns.On(event, fn); bursts of quest-log events are folded into
-- one refresh shortly after (ns.MarkDirty), so the guide does its work once per change, not once per event.
local _, ns = ...

local frame = CreateFrame('Frame')
local subs = {}
local dirty, queued = {}, false
local REFRESH_DELAY = 0.15

ns.restricted = {}   -- addon restriction states the game reported (combat, encounter...), and blocked actions

function ns.On(event, fn)
  if not subs[event] then
    subs[event] = {}
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then subs[event].refused = true end
  end
  table.insert(subs[event], fn)
end

frame:SetScript('OnEvent', function(_, event, ...)
  for _, fn in ipairs(subs[event] or {}) do ns.safecall(event, fn, ...) end
end)

--- note that part of the game state changed; one refresh runs shortly after, however many events arrive
function ns.MarkDirty(part)
  dirty[part or 'all'] = true
  if queued then return end
  queued = true
  C_Timer.After(REFRESH_DELAY, function()
    queued = false
    local parts = dirty
    dirty = {}
    if not ns.Refresh then return end
    local ok, err = ns.safecall('refresh', ns.Refresh, parts)
    if not ok and ns.Window and ns.Window.Message then
      -- never leave another route's steps on screen as if they were this one's: say so, and where the error went
      local route = ns.Engine and ns.Engine.Route()
      ns.safecall('refresh-message', ns.Window.Message, route and route.title, ns.L.refreshFailed, tostring(err))
    end
  end)
end

ns.On('ADDON_RESTRICTION_STATE_CHANGED', function(kind, state) if kind then ns.restricted[kind] = state end end)
-- the game tells every addon about a blocked action, naming the one it blames: only ours pauses automation (Oct 11:
-- another addon's block left Zenn's Bidding on its Continue panel until a /reload). FORBIDDEN is the one behind
-- Blizzard's own "only available to the Blizzard UI" popup. Ours are kept too, the last ten in BoFGuideDB.blocked,
-- for /bofg report and the feedback note (FB-012: the action the chat line named was lost with the chat)
local KEEP_BLOCKED = 10

local function where()
  local route, view = ns.Engine.Route(), ns.Engine.View()
  local s = route and view and view.cursor and route.steps[view.cursor]
  return route and route.id, s and ('%s %s %s'):format(s.k or '-', s.o or '-', tostring(s.id or '')) or nil
end

local function keep(kind, what)
  if not ns.db then return end
  local list = ns.db.blocked or {}
  ns.db.blocked = list
  local last = list[#list]
  if last and last.what == what and last.kind == kind and last.ver == ns.VERSION then
    last.n, last.at = (last.n or 1) + 1, time()
    return
  end
  local row = { what = what, kind = kind, at = time(), n = 1, ver = ns.VERSION, combat = InCombatLockdown() or nil }
  local ok, route, step = pcall(where)
  if ok then row.route, row.step = route, step end
  list[#list + 1] = row
  while #list > KEEP_BLOCKED do table.remove(list, 1) end
end

-- A blocked action pauses automation a short while, then it starts again by itself; only a third in one session stops
-- it until the player says to try again (the AUTO switch). Nov 5, FB-037: a tester's Back to Billy wasn't handed in
-- until a /reload, and "this is not the first time": one block used to stop automation for the whole session
local RESUME_SECS, STOP_AFTER = 20, 3

--- why automation is held after a blocked action ('blocked': stopped; 'paused': a short break), or nil
function ns.AutoHeld()
  local r = ns.restricted
  if r.blocked then return 'blocked' end
  if r.pausedAt and GetTime() - r.pausedAt < RESUME_SECS then return 'paused' end
  return nil
end

--- the player says try again (AUTO off and on, /bofg auto on, the oath's Automatic)
function ns.AutoResume()
  local r = ns.restricted
  r.blocked, r.blockedSaid, r.pausedAt, r.pauseSaid, r.blocks = nil, nil, nil, nil, nil
end

local function blocked(kind)
  return function(who, what)
    who = ns.clean(who)
    if type(who) ~= 'string' or not who:find('^BoFGuide') then return end
    what = tostring(ns.clean(what) or '?')
    local r = ns.restricted
    r.blocks = (r.blocks or 0) + 1
    r.pausedAt = GetTime()
    keep(kind, what)
    if r.blocks >= STOP_AFTER then
      r.blocked = true
      if not r.blockedSaid then
        r.blockedSaid = true
        ns.say(ns.L.blocked:format(what))
      end
    elseif not r.pauseSaid then
      r.pauseSaid = true
      ns.say(ns.L.blockedPause)
    end
  end
end
ns.On('ADDON_ACTION_BLOCKED', blocked('blocked'))
ns.On('ADDON_ACTION_FORBIDDEN', blocked('forbidden'))

--- reload the interface (a new language, an added guide); mid-fight it waits for the fight's end: the game blocks
--- Reload() in combat (the owner's saved data, Oct 16: "Reload() blocked" five times after a language pick)
function ns.Reload()
  if InCombatLockdown and InCombatLockdown() then
    if not ns.reloadWaits then ns.say(ns.L.reloadAfterFight) end
    ns.reloadWaits = true
    return false
  end
  ns.reloadWaits = nil
  if C_UI and C_UI.Reload then C_UI.Reload() elseif ReloadUI then ReloadUI() end
  return true
end
ns.On('PLAYER_REGEN_ENABLED', function() if ns.reloadWaits then ns.Reload() end end)

--- the last action the game blocked for us, in words for the report (short) or the feedback note; nil when none
function ns.LastBlocked(short)
  local list = ns.db and ns.db.blocked
  local b = list and list[#list]
  if not b then return nil end
  local when = date(short and '%m-%d %H:%M' or '%Y-%m-%d %H:%M', b.at)
  if short then
    return ('blocked %s %s x%d %s %s'):format(b.what, b.kind, b.n or 1, when, tostring(b.ver))
  end
  local times = (b.n or 1) == 1 and 'once' or ('%d times'):format(b.n)
  return ('%s (%s, %s, last %s, guide %s%s, step %s %s)'):format(b.what, b.kind, times, when, tostring(b.ver),
    b.combat and ', in combat' or '', b.route or '-', b.step or '-')
end
