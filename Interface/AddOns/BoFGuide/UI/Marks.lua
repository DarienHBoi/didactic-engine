-- The Waymark (owner, Oct 30): the bronze pin from the window and the map hangs over the person whose turn it is, so
-- you can pick them out of a busy town. Off until it has been seen in the real game: /bofg mark on.
--   on the way in  on the game's own waypoint (C_Navigation.GetFrame), so no setting is needed: the pin sits on the
--                  game's marker and covers it (owner, Oct 31: the emblem alone is enough). The game floats that point
--                  higher the further off you are, and drops it as you arrive (SuperTrackedFrame clears a user
--                  waypoint), so this one stops a little short of them.
--   close to them  on their nameplate, when friendly NPC nameplates are on: exact, and it walks with them. The next
--                  person gets a small dim pin.
--   done           the pin stamps down and burns off, and a spark runs to the next person.
--   elites         the crowned skull over an elite the steps don't ask for: who not to touch. Hostile nameplates only.
-- A spark leaves the arrow when a person's pin comes into reach, because movement finds the eye in a crowd.
-- Frames of our own, anchored to the game's: they take no clicks, and no Blizzard frame or setting is touched (the
-- nameplate settings change only when the player types /bofg mark plates). Everything read goes through ns.clean: a
-- nameplate's identity can be secret, and then that plate just gets no pin. The worst it can do is show nothing: three
-- errors and it stands down until the next login, and the guide goes on without it.
local _, ns = ...

local Marks = {}
ns.Marks = Marks
local Skin = ns.Skin

local PIN, NEXT_SCALE, NEXT_ALPHA, DANGER_SCALE = 44, 0.62, 0.62, 0.8
local SHOW_YARDS, FAR_SCALE, NEAR_YARDS = 150, 0.6, 30   -- the pin on the waypoint: from here, this small, full size here
local SPARK_YARDS = 40
local PLATE_GAP = 2                                       -- above a nameplate
local FAILS = 3                  -- errors before it stands down for this login
local CLEAR, BESIDE = 25, 3      -- /bofg mark test: yards clear of the spot; the game's duel range, about 10 yards
local OCCLUDED = 0.6             -- the game's own pin fades this far behind a wall
local TICK, RUN, ARC, TRAIL = 0.03, 0.45, 34, 0.07        -- the spark: seconds, its bow, the lag of each ghost behind it
local EMBERS, BURN = 6, 0.75
local OUTLEVEL = 3               -- you're this many levels above an elite: no longer worth a warning (as UI/Danger.lua)
local ELITE = { elite = true, rareelite = true, worldboss = true }
Marks.ART = { quest = 'pin-quest', turnin = 'pin-turnin', vendor = 'pin-vendor', trainer = 'pin-trainer', inn = 'pin-inn',
              flight = 'pin-flight', danger = 'med-boss' }
Marks.SCALE = { 0.5, 2 }         -- settings.markScale

local want                       -- what the engine asked for last: { lead, nxt, fight, finished }
local started, driver, wasShown = false, nil, nil
local units = {}                 -- nameplate tokens on screen
local pins = {}                  -- nameplate token -> its pin
local navPin, navFrame           -- the pin on the waypoint, and the game's point it hangs from
local pool = {}
local sparked = {}               -- the people whose spark has run, until they stop being the one you need
local sparkFrame
local burning = 0                -- pins stamped and still fading
local broken, failures = false, 0
local try                        -- /bofg mark test is running: { wasOn, who, map, x, y, clear }
local stop, placeTry, trySample

local function on() return ns.settings.marks == true and not broken end
local function keyOf(who) return who.id or who.name end
local function same(a, b) return a and b and keyOf(a) == keyOf(b) end
local function size() return ns.settings.markScale or 1 end
local function lift() return ns.settings.markLift or 0 end

--- run one of ours; errors are kept as ever, and the third stands it down
local function guard(tag, fn, ...)
  if ns.safecall(tag, fn, ...) then return end
  failures = failures + 1
  if failures >= FAILS and not broken then
    broken = true
    ns.safecall('mark-stop', stop)
  end
end

--- a frame's middle, in UIParent's units; nil when the game keeps it from us. Never asked of a pin on a nameplate: the game
--- answers that with an error (Can't measure restricted regions, retail, Oct 31), and three of those stand the Waymark down
local function centre(f)
  if f.mode == 'plate' then return nil end
  local x, y = f:GetCenter()
  x, y = ns.clean(x), ns.clean(y)
  local mine, ui = ns.clean(f:GetEffectiveScale()), ns.clean(UIParent:GetEffectiveScale())
  if not (x and y and mine and ui) or ui == 0 then return nil end
  return x * mine / ui, y * mine / ui
end

-- ------------------------------------------------------------------------------------------------------------- pins
local function fadeOf(group, target, from, to, secs)
  local a = group:CreateAnimation('Alpha')
  a:SetTarget(target)
  a:SetFromAlpha(from)
  a:SetToAlpha(to)
  a:SetDuration(secs)
  return a
end

local made = 0
local function newPin()
  made = made + 1
  local f = CreateFrame('Frame', 'BoFGuideMark' .. made, UIParent)
  f:SetFrameStrata('LOW')          -- (over the game's marker, which is BACKGROUND)
  f:SetSize(PIN, PIN)
  f.halo = Skin.Tex(f, 'glow', 'BACKGROUND')
  f.halo:SetSize(PIN * 2, PIN * 2)
  f.halo:SetPoint('CENTER', f, 'CENTER', 0, 2)
  f.halo:SetBlendMode('ADD')
  f.art = Skin.Tex(f, nil, 'ARTWORK')
  f.art:SetAllPoints(f)
  -- the lead pin's light breathes
  f.breath = f.halo:CreateAnimationGroup()
  fadeOf(f.breath, f.halo, 0.75, 0.3, 1.5):SetSmoothing('IN_OUT')
  f.breath:SetLooping('BOUNCE')
  -- a spark landing
  f.land = f.halo:CreateAnimationGroup()
  local grow = f.land:CreateAnimation('Scale')
  grow:SetTarget(f.halo)
  grow:SetScaleFrom(2.1, 2.1)
  grow:SetScaleTo(1, 1)
  grow:SetDuration(0.4)
  grow:SetSmoothing('OUT')
  -- the stamp: down hard like the oath's seal, then it burns off
  f.drop = f:CreateAnimationGroup()
  local fall = f.drop:CreateAnimation('Scale')
  fall:SetScaleFrom(1.5, 1.5)
  fall:SetScaleTo(1, 1)
  fall:SetDuration(0.16)
  fall:SetSmoothing('IN')
  fadeOf(f.drop, f, 1, 0, 0.48):SetStartDelay(0.22)
  f.embers = {}
  for i = 1, EMBERS do
    local e = Skin.Tex(f, 'mark-spark', 'OVERLAY')
    e:SetSize(10, 10)
    e:SetPoint('CENTER', f, 'BOTTOM', (i - EMBERS / 2 - 0.5) * 5, PIN * 0.34)
    e:SetBlendMode('ADD')
    e:Hide()
    e.rise = e:CreateAnimationGroup()
    local go = e.rise:CreateAnimation('Translation')
    go:SetTarget(e)
    go:SetOffset((i - EMBERS / 2 - 0.5) * 7, 26 + (i * 13) % 24)
    go:SetDuration(BURN - 0.1)
    go:SetSmoothing('OUT')
    fadeOf(e.rise, e, 1, 0, BURN - 0.1)
    f.embers[i] = e
  end
  return f
end

local function take()
  local f = table.remove(pool) or newPin()
  f.gone, f.who, f.style, f.mode = nil, nil, nil, nil
  f:SetAlpha(1)
  f:SetScale(1)
  for _, e in ipairs(f.embers) do e:Hide() end
  return f
end

local function give(f)
  if not f or f.gone then return end
  f.gone = true
  if f.breath:IsPlaying() then f.breath:Stop() end
  f:ClearAllPoints()
  f:Hide()
  pool[#pool + 1] = f
end

--- the pin's picture and how strong it stands
local function dress(f, who, style)
  local was = f.who
  f.who, f.style = who, style
  f.art:SetTexture(Skin.MEDIA .. (Marks.ART[who.role] or Marks.ART.quest))
  if style == 'next' then f.halo:SetVertexColor(0.9, 0.62, 0.32) elseif style == 'danger' then f.halo:SetVertexColor(1, 0.3, 0.2)
  else f.halo:SetVertexColor(1, 0.8, 0.45) end
  if style == 'lead' then
    if not f.breath:IsPlaying() then f.breath:Play() end
    if was and was.role ~= who.role then f.land:Play() end   -- (one line done at this person, on to the next)
  elseif f.breath:IsPlaying() then
    f.breath:Stop()
  end
  f.halo:SetAlpha(style == 'next' and 0.3 or 0.6)
end

--- one on a nameplate
local function seat(f, plate, style)
  f.mode = 'plate'
  f:SetScale((style == 'next' and NEXT_SCALE or style == 'danger' and DANGER_SCALE or 1) * size())
  f:SetAlpha(style == 'next' and NEXT_ALPHA or 1)
  f:ClearAllPoints()
  f:SetPoint('BOTTOM', plate, 'TOP', 0, PLATE_GAP + lift())
  f:Show()
end

-- ------------------------------------------------------------------------------------------------------------ spark
local function sparkPart(parent, sz, alpha)
  local t = Skin.Tex(parent, 'mark-spark', 'OVERLAY')
  t:SetSize(sz, sz)
  t:SetBlendMode('ADD')
  t:SetAlpha(alpha)
  return t
end

local function sparkAt(t, x, y)
  t:ClearAllPoints()
  t:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', x, y)
end

local function sparkTick(_, e)
  local s = sparkFrame
  s.t = s.t + e / RUN
  local to = s.to
  local x, y
  if to and not to.gone then x, y = centre(to) end
  if not x or s.t >= 1 then
    s:Hide()
    if x and to.land then to.land:Play() end
    return
  end
  for i, part in ipairs(s.parts) do
    local t = math.max(0, s.t - (i - 1) * TRAIL)
    t = t * t * (3 - 2 * t)
    sparkAt(part, s.x + (x - s.x) * t, s.y + (y - s.y) * t + math.sin(t * math.pi) * ARC)
  end
end

--- a spark from a point on the screen to a pin
local function fly(x, y, f)
  if not (x and y and f) then return end
  if not sparkFrame then
    sparkFrame = CreateFrame('Frame', 'BoFGuideMarkSpark', UIParent)
    sparkFrame:SetFrameStrata('LOW')
    sparkFrame:SetSize(1, 1)
    sparkFrame:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 0, 0)
    sparkFrame.parts = { sparkPart(sparkFrame, 30, 1), sparkPart(sparkFrame, 20, 0.6), sparkPart(sparkFrame, 13, 0.35) }
    sparkFrame:SetScript('OnUpdate', function(self, e) guard('mark-spark', sparkTick, self, e) end)
  end
  sparkFrame.x, sparkFrame.y, sparkFrame.to, sparkFrame.t = x, y, f, 0
  for _, part in ipairs(sparkFrame.parts) do sparkAt(part, x, y) end
  sparkFrame:Show()
end

--- this person's pin has come into reach: once, the spark from the arrow
local function reached(f)
  local k = keyOf(f.who)
  if sparked[k] then return end
  sparked[k] = true
  if f.mode == 'plate' then         -- (a spark can't aim at a pin that can't be measured: it lights up where it is)
    Marks.Note('on the nameplate, ' .. tostring(ns.clean(C_Navigation.GetDistance())) .. ' yards from the waypoint')
    return f.land:Play()
  end
  local x, y = ns.Arrow.Point()
  fly(x, y, f)
end

--- the pin leaves where it stands: it stops following its anchor, stamps and burns off (on a nameplate it does that where
--- it hangs). Returns where it was, if the game will say.
local function stamp(f)
  local x, y = centre(f)
  if x then
    local s = f:GetScale()
    f:ClearAllPoints()
    f:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', x / s, y / s)
  end
  if f.breath:IsPlaying() then f.breath:Stop() end
  f.drop:Play()
  for _, e in ipairs(f.embers) do e:Show() e.rise:Play() end
  burning = burning + 1
  C_Timer.After(BURN, function()
    burning = burning - 1
    give(f)
  end)
  return x, y
end

-- ------------------------------------------------------------------------------------------------------- who is who
local function friendsShow()
  return ns.settings.shown ~= false and not (InCombatLockdown and InCombatLockdown()) and want ~= nil
end

--- an elite to stay away from: hostile, outdoors, not yet outlevelled, and not one the steps send you at
local function danger(unit, id, name)
  if ns.st and ns.st.inst then return nil end
  if not (UnitCanAttack and ns.clean(UnitCanAttack('player', unit))) then return nil end
  if not ELITE[ns.clean(UnitClassification(unit))] or ns.clean(UnitIsDead(unit)) then return nil end
  local lv, me = ns.clean(UnitLevel(unit)), ns.st and ns.st.level or 1
  if lv and lv > 0 and me >= lv + OUTLEVEL then return nil end
  for _, t in ipairs(want and want.fight or {}) do
    if (id and t.id == id) or (name and t.name == name) then return nil end
  end
  return { id = id, name = name, role = 'danger' }
end

local function styleOf(unit)
  local id, name = ns.npcID(unit), ns.clean(UnitName(unit))
  local function is(who) return who and ((id and who.id == id) or (name and who.name == name)) end
  if friendsShow() then
    if is(want.lead) then return 'lead', want.lead end
    if is(want.nxt) then return 'next', want.nxt end
  end
  local d = danger(unit, id, name)
  if d then return 'danger', d end
end

--- is the game on a waypoint of the player's? (both: a cleared one can leave it saying yes)
local function tracked()
  return ns.clean(C_Map.HasUserWaypoint()) and ns.clean(C_SuperTrack.IsSuperTrackingUserWaypoint())
end

--- every nameplate on screen, then the waypoint for the person with none
local function sync()
  if not started then return end
  navFrame = C_Navigation and C_Navigation.GetFrame and C_Navigation.GetFrame() or nil   -- (the event alone can miss it)
  local leadSeated = false
  for unit in pairs(units) do
    local plate = C_NamePlate.GetNamePlateForUnit(unit)    -- (nil for the ones addons may not touch, as in dungeons)
    local style, who
    if plate then style, who = styleOf(unit) end
    if style then
      local f = pins[unit] or take()
      pins[unit] = f
      dress(f, who, style)
      seat(f, plate, style)
      if style == 'lead' then
        leadSeated = true
        reached(f)
      end
    elseif pins[unit] then
      give(pins[unit])
      pins[unit] = nil
    end
  end
  -- (asked each time: placing a waypoint of your own runs no refresh, and the pin must not stay on yours)
  local aimed = friendsShow() and not leadSeated and want.lead and navFrame
  if aimed and try then aimed = tracked()
  elseif aimed then aimed = ns.Waypoint.Aimed(want.lead.key) end
  if aimed then
    navPin = navPin or take()
    dress(navPin, want.lead, 'lead')
    navPin.mode = 'nav'
    Marks.NavTick()
  elseif navPin then
    give(navPin)
    navPin = nil
  end
end

--- the pin on the waypoint follows its point by itself; each moment it's sized and lifted for how far off it is
function Marks.NavTick()
  local f = navPin
  if not (f and navFrame) then return end
  local d = ns.clean(C_Navigation.GetDistance())
  local state, N = ns.clean(C_Navigation.GetTargetState()), Enum and Enum.NavigationState or {}
  local why = not d and 'no distance' or d > SHOW_YARDS and 'too far'
    or not ns.clean(C_Navigation.HasValidScreenPosition()) and 'no place on the screen'
    or ns.clean(C_Navigation.WasClampedToScreen()) and 'off the screen'
    or state == N.Disabled and 'switched off' or nil
  Marks.hiddenBy = why
  if why then
    f:Hide()
    return
  end
  local near = math.max(0, math.min(1, (SHOW_YARDS - d) / (SHOW_YARDS - NEAR_YARDS)))
  local scale = (FAR_SCALE + (1 - FAR_SCALE) * near) * size()
  f:SetScale(scale)
  f:SetAlpha(math.min(1, (SHOW_YARDS - d) / 30) * (state == N.Occluded and OCCLUDED or 1))
  f:ClearAllPoints()
  f:SetPoint('CENTER', navFrame, 'CENTER', 0, lift() / scale)
  f:Show()
  if d <= SPARK_YARDS then reached(f) elseif try then sparked[keyOf(f.who)] = nil end   -- (the test: out and back, again)
end

local function scanPlates()
  for k in pairs(units) do units[k] = nil end
  for i = 1, 40 do
    local unit = 'nameplate' .. i
    if ns.clean(UnitExists(unit)) then units[unit] = true end
  end
end

local function start()
  if started then return end
  started = true
  if not driver then
    driver = CreateFrame('Frame', nil, UIParent)
    local since = 0
    driver:SetScript('OnUpdate', function(_, e)
      since = since + e
      if since < TICK then return end
      since = 0
      -- (the window hidden or shown, which no event of ours says)
      local shown = ns.settings.shown ~= false
      if shown ~= wasShown then wasShown = shown guard('mark-sync', sync) end
      guard('mark-tick', Marks.NavTick)
      if try then
        guard('mark-try', placeTry)
        ns.safecall('mark-record', trySample)   -- (the record stands apart: its errors don't stand the Waymark down)
      end
    end)
  end
  driver:Show()
  wasShown = ns.settings.shown ~= false
  navFrame = C_Navigation and C_Navigation.GetFrame and C_Navigation.GetFrame() or nil
  scanPlates()
end

stop = function()
  started = false
  if driver then driver:Hide() end
  if sparkFrame then sparkFrame:Hide() end
  for unit, f in pairs(pins) do give(f) pins[unit] = nil end
  give(navPin)
  navPin, want = nil, nil
  for k in pairs(sparked) do sparked[k] = nil end
end

-- ---------------------------------------------------------------------------------------------------------- the API
--- what the engine wants marked now: { lead = { id, name, role, key = its step }, nxt = the next person, fight = the
--- enemies the steps want killed, finished = the last lead's steps are all done }. nil: nothing
local function set(new)
  start()
  local old = want
  local oldLead, newLead = old and old.lead, new and new.lead
  want = new
  local fromX, fromY
  if oldLead and not same(oldLead, newLead) then
    sparked[keyOf(oldLead)] = nil
    if new and new.finished then
      for unit, f in pairs(pins) do
        if f.style == 'lead' then fromX, fromY = stamp(f) pins[unit] = nil end
      end
      if navPin then
        local x, y = stamp(navPin)
        fromX, fromY, navPin = fromX or x, fromY or y, nil
      end
    end
  end
  sync()
  if fromX and newLead then
    local f = navPin
    for _, p in pairs(pins) do if p.style == 'lead' then f = p end end
    if f and f:IsShown() then
      sparked[keyOf(newLead)] = true
      fly(fromX, fromY, f)
    end
  end
end

function Marks.Set(new)
  if on() and not try then guard('marks', set, new) end
end

--- /bofg mark on|off
function Marks.Enable(v)
  ns.settings.marks = v and true or false
  if v then
    start()
    ns.MarkDirty('marks')
  else
    stop()
  end
end

function Marks.SetScale(v)
  v = math.max(Marks.SCALE[1], math.min(Marks.SCALE[2], math.floor(v * 100 + 0.5) / 100))
  ns.settings.markScale = v
  guard('mark-sync', sync)
  return v
end

function Marks.SetLift(v)
  ns.settings.markLift = v
  guard('mark-sync', sync)
  return v
end

-- (the bit is Enum.NamePlateSimplifiedType.FriendlyNpc, passed as is: Blizzard's Settings.GetCVarMask does the same)
local FRIENDLY, SMALL, SMALL_BIT = 'nameplateShowFriendlyNpcs', 'nameplateSimplifiedTypes', 4

--- /bofg mark plates on|small|off: the game's own setting, changed only because the player typed it. small = the
--- game's simplified plates for friendly NPCs (smaller, no name). Returns false in a fight.
function Marks.Plates(how)
  if InCombatLockdown and InCombatLockdown() then return false end
  C_CVar.SetCVar(FRIENDLY, how == 'off' and '0' or '1')
  if C_CVar.GetCVarBitfield and ns.clean(C_CVar.GetCVar(SMALL)) then
    pcall(C_CVar.SetCVarBitfield, SMALL, SMALL_BIT, how == 'small')
  end
  return true
end

-- --------------------------------------------------------------------------------------------------------- try it
local function endTry()
  if not try then return end
  local was = try.wasOn
  try = nil
  ns.Waypoint.paused = nil
  ns.Waypoint.owned = nil
  ns.Waypoint.setting = true
  C_Map.ClearUserWaypoint()
  ns.Waypoint.setting = false
  ns.Arrow.held = nil
  ns.Arrow.Set(nil)
  want = nil
  Marks.Enable(was)
  if was then guard('mark-sync', sync) end
  ns.MarkDirty('marks')   -- (the route's own waypoint and arrow come back)
end

--- where you stand: map and fractions; nil where the game won't say
local function here()
  local map = ns.clean(C_Map.GetBestMapForUnit('player'))
  local pos = map and C_Map.GetPlayerMapPosition(map, 'player')
  local x, y = pos and ns.clean(pos.x), pos and ns.clean(pos.y)
  if x and y then return map, x, y end
end

--- the test's waypoint goes down once you're clear of the spot, and again each time you leave it: the game ends a
--- waypoint as you reach it, so one put under your feet is over before you've moved
placeTry = function()
  if tracked() then
    if not navPin then sync() end
    return
  end
  local map, x, y = here()
  local yards = map and ns.Geo.Between({ map, x * 100, y * 100 }, { try.map, try.x * 100, try.y * 100 })
  if not yards or yards < try.clear then return end
  ns.Waypoint.setting = true
  C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(try.map, try.x, try.y))
  C_SuperTrack.SetSuperTrackedUserWaypoint(true)
  ns.Waypoint.setting = false
  Marks.Note('waypoint down, ' .. math.floor(yards) .. ' yards from the spot')
  ns.say('Waymark test: waypoint down. Turn and look.')
  sync()
end

--- the record of a test, for reading afterwards from the saved file (BoFGuideDB.markProbe): what the game's point is doing
--- each second, and everything it says. What the code can't see from here is exactly what a test is for.
function Marks.Note(line)
  if not try then return end
  local log = ns.db.markProbe
  if #log >= 600 then table.remove(log, 1) end
  log[#log + 1] = ('%.1f %s'):format(GetTime() - try.began, line)
end

trySample = function()
  if GetTime() < try.next then return end
  try.next = GetTime() + 1
  local nav, s = C_Navigation.GetFrame(), tostring
  local nx, ny
  if nav then nx, ny = nav:GetCenter() end
  local px, py
  if navPin then px, py = navPin:GetCenter() end
  local map, x, y = here()
  local why = navPin and Marks.hiddenBy or nil
  local now = table.concat({ s(ns.clean(C_Map.HasUserWaypoint())), s(ns.clean(C_SuperTrack.IsSuperTrackingUserWaypoint())),
    s(nav ~= nil), s(ns.clean(C_Navigation.GetTargetState())), s(navPin ~= nil), s(why) }, ' ')
  if now ~= try.was or GetTime() >= try.due then
    try.was, try.due = now, GetTime() + 15
    Marks.Note(('from spot %s; waypoint %s tracking %s; frame %s at %s,%s; distance %s valid %s clamped %s state %s; pin %s visible %s alpha %s at %s,%s art %s; hidden by %s; lead %s fight %s shown %s'):format(
      s(map and ns.Geo.Between({ map, x * 100, y * 100 }, { try.map, try.x * 100, try.y * 100 })),
      s(ns.clean(C_Map.HasUserWaypoint())), s(ns.clean(C_SuperTrack.IsSuperTrackingUserWaypoint())), s(nav ~= nil),
      s(ns.clean(nx)), s(ns.clean(ny)), s(ns.clean(C_Navigation.GetDistance())), s(ns.clean(C_Navigation.HasValidScreenPosition())),
      s(ns.clean(C_Navigation.WasClampedToScreen())), s(ns.clean(C_Navigation.GetTargetState())), s(navPin ~= nil),
      s(navPin and navPin:IsVisible()), s(navPin and navPin:GetAlpha()), s(ns.clean(px)), s(ns.clean(py)),
      s(navPin and navPin.art:GetTexture()), s(why), s(want and want.lead ~= nil), s(InCombatLockdown and InCombatLockdown()),
      s(ns.settings.shown)))
  end
  if why ~= try.said then
    try.said = why
    if why then ns.say('Waymark test: the pin is hiding: ' .. why .. '.') end
  end
end

--- /bofg mark test: the Waymark anywhere the game has waypoints, with no route. Stand beside someone, target them and
--- type it: your spot is theirs and they become the person you need; walk away and the waypoint comes up there. It runs
--- on retail too, whose navigation and nameplate code is the same as Forever's, so it can be judged there before launch.
--- A role (quest, turnin, vendor, trainer, inn, flight) picks the pin; done stamps it; off ends it. Returns what happened
function Marks.Try(word)
  if word == 'off' then
    guard('mark-try', endTry)
    return 'off'
  end
  if word == 'done' then
    if not try then return 'nothing' end
    guard('marks', set, { fight = {}, finished = true })
    return 'done'
  end
  local role = Marks.ART[word] and word ~= 'danger' and word or 'turnin'
  if try then                     -- (another pin on the same person, from wherever you are)
    try.who.role = role
    guard('marks', set, { fight = {}, lead = try.who })
    return 'pin'
  end
  if ns.clean(UnitExists('target')) and ns.clean(CheckInteractDistance('target', BESIDE)) == false then return 'far' end
  local map, x, y = here()
  if not map or not C_Map.CanSetUserWaypointOnMap(map) then return 'nowhere' end
  local name = ns.clean(UnitName('target')) or ''
  try = { wasOn = ns.settings.marks == true, who = { id = ns.npcID('target') or 0, name = name, role = role },
          map = map, x = x, y = y, clear = CLEAR, began = GetTime(), next = 0, due = 0 }
  ns.db.markProbe = ns.db.markProbe or {}
  Marks.Note('test on map ' .. map)
  ns.settings.marks = true
  broken, failures = false, 0
  ns.Waypoint.paused = true
  ns.Waypoint.setting = true
  C_Map.ClearUserWaypoint()       -- (the route's: the pin is for this spot alone)
  ns.Waypoint.setting = false
  ns.Arrow.held = { map = map, x = x * 100, y = y * 100, name = name }
  ns.Arrow.Set(ns.Arrow.held)
  guard('marks', set, { fight = {}, lead = try.who })
  return 'on'
end

-- ------------------------------------------------------------------------------------------------- what we can't see
--- how close the game was when it dropped the waypoint: the one number the code can't tell us (the last few, for
--- /bofg selftest)
local function arrival(isWaypoint)
  if not started then return end
  local d = ns.clean(C_Navigation.GetDistance())
  ns.db.markArrivals = ns.db.markArrivals or {}
  local log = ns.db.markArrivals
  log[#log + 1] = { yards = d and math.floor(d * 10 + 0.5) / 10, stop = ns.clean(isWaypoint) and true or false }
  while #log > 5 do table.remove(log, 1) end
  if try then
    try.clear = math.max(try.clear, (d or 0) + 5)   -- (the next one goes down outside the game's reach)
    ns.say('Waymark test: the game says you reached it at ' .. tostring(d) .. ' yards.')
  end
end

function Marks.ProbeNav()
  if not (C_Navigation and C_Navigation.GetFrame) then return false, 'no C_Navigation.GetFrame' end
  local f = C_Navigation.GetFrame()
  local got = {}
  for _, a in ipairs(ns.db.markArrivals or {}) do got[#got + 1] = tostring(a.yards) end
  local cameUp = #got > 0 and ('; dropped at ' .. table.concat(got, ', ') .. ' yd') or ''
  if not f then return true, 'nothing tracked now' .. cameUp end
  local x, y = f:GetCenter()
  return true, ('centre %s,%s; valid %s; clamped %s; state %s; %s yd%s'):format(tostring(ns.clean(x)), tostring(ns.clean(y)),
    tostring(ns.clean(C_Navigation.HasValidScreenPosition())), tostring(ns.clean(C_Navigation.WasClampedToScreen())),
    tostring(ns.clean(C_Navigation.GetTargetState())), tostring(ns.clean(C_Navigation.GetDistance())), cameUp)
end

function Marks.ProbePlates()
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return false, 'no C_NamePlate' end
  local function cv(name) return tostring(C_CVar and ns.clean(C_CVar.GetCVar(name))) end
  local seen, read, friends, plates = 0, 0, 0, 0
  for i = 1, 40 do
    local unit = 'nameplate' .. i
    if ns.clean(UnitExists(unit)) then
      seen = seen + 1
      if ns.npcID(unit) then read = read + 1 end
      if C_NamePlate.GetNamePlateForUnit(unit) then plates = plates + 1 end
      if not (UnitCanAttack and ns.clean(UnitCanAttack('player', unit))) then friends = friends + 1 end
    end
  end
  return true, ('friendly NPCs %s, enemies %s, simplified %s, range %s; on screen %d (%d not hostile), who they are read on %d, ours to use %d'):format(
    cv(FRIENDLY), cv('nameplateShowEnemies'), cv(SMALL), cv('nameplateMaxDistance'), seen, friends, read, plates)
end

--- for tests: what the engine last asked for; how many pins are burning off; a spark in the air
function Marks.Wanted() return want end
function Marks.Burning() return burning end
function Marks.Sparking() return sparkFrame and sparkFrame:IsShown() and true or false end

--- what's up, for tests: { { style, mode, id, role, shown, alpha } }
function Marks.State()
  local out = {}
  local function add(f)
    if f and f.who then
      out[#out + 1] = { style = f.style, mode = f.mode, id = f.who.id, role = f.who.role, shown = f:IsShown(),
                        alpha = f:GetAlpha() }
    end
  end
  for _, f in pairs(pins) do add(f) end
  add(navPin)
  return out
end

ns.On('NAME_PLATE_UNIT_ADDED', function(unit)
  if not started then return end
  units[unit] = true
  guard('mark-sync', sync)
end)
ns.On('NAME_PLATE_UNIT_REMOVED', function(unit)
  if not started then return end
  units[unit] = nil
  if pins[unit] then give(pins[unit]) pins[unit] = nil end
  guard('mark-sync', sync)
end)
-- (not while the guide itself is moving the waypoint: the refresh that moves it tells us next, and the pin of a person
-- you've just finished with has to be there for the stamp)
local function resync()
  if started and not ns.Waypoint.setting then guard('mark-sync', sync) end
end
ns.On('NAVIGATION_FRAME_CREATED', function()
  if not started then return end
  navFrame = C_Navigation.GetFrame()
  resync()
end)
ns.On('NAVIGATION_FRAME_DESTROYED', function()
  if not started then return end
  navFrame = nil
  resync()
end)
ns.On('NAVIGATION_DESTINATION_REACHED', arrival)
for _, ev in ipairs({ 'NAVIGATION_FRAME_CREATED', 'NAVIGATION_FRAME_DESTROYED', 'NAVIGATION_DESTINATION_REACHED',
                      'SUPER_TRACKING_CHANGED', 'USER_WAYPOINT_UPDATED' }) do
  ns.On(ev, function(a) Marks.Note(ev .. ' ' .. tostring(ns.clean(a))) end)
end
ns.On('SUPER_TRACKING_CHANGED', resync)
ns.On('USER_WAYPOINT_UPDATED', resync)
ns.On('PLAYER_REGEN_DISABLED', resync)
ns.On('PLAYER_REGEN_ENABLED', resync)
