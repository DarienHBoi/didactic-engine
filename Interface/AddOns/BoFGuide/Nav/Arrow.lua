-- The waypoint arrow: our own frame, separate from the window, that points at the current step's spot.
--   heading:  the angle from you to the spot in world coordinates, less the way you face (GetPlayerFacing)
--   color:    gold when you're on course, ember when it's off to the side, red when it's behind you
--   look:     our painted arrow (settings.arrowLook = 'relic'), or a plain solid arrow (Media/arrow-solid) in one
--             colour, or one that turns green ahead, yellow to the side and red behind ('direction')
--   text:     the distance in yards and, while you're moving, about how long it takes; under it what's there (the
--             step, which the window shows too, so it can be turned off: settings.arrowText)
--   arrival:  a gold check inside the step's radius; the engine marks goto and fly steps done there
-- It hides itself where the game won't say where you are (instances, some caves), and when the target is on another
-- continent it says where to go instead of pointing. Drag to move (unless locked); right-click for its menu.
-- The game's own map pin (Nav/Waypoint.lua) stays: the arrow is beside it, not instead of it.
local _, ns = ...

local Arrow = { target = nil }
ns.Arrow = Arrow
local Skin = ns.Skin
local C = Skin.C
local SIZE, UPDATE, PI2 = 56, 0.033, math.pi * 2
local frame, art, halo, check, stone, label, dist, eta
local WALK_REACH = 100   -- yards: how far round someone who walks counts as there
local elapsed, lastYards, lastAt, speed = 0, nil, nil, nil

--- angle (radians, counter-clockwise from north, the way GetPlayerFacing counts) from world point a to b.
--- World coordinates: x grows north, y grows west (UnitPosition returns y, x), so north is +x and west is +y.
function Arrow.Bearing(ax, ay, bx, by)
  local dn, dw = bx - ax, by - ay
  return math.atan2(dw, dn) % PI2
end

--- where the arrow points, relative to the screen's up (radians, counter-clockwise), and the yards to go
function Arrow.Solve(px, py, facing, tx, ty)
  local yards = math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2)
  local rel = (Arrow.Bearing(px, py, tx, ty) - facing) % PI2
  return rel, yards
end

--- the plain arrow's colours (settings.arrowLook); 'direction' turns green ahead, yellow to the side, red behind
Arrow.LOOKS = { 'relic', 'gold', 'white', 'green', 'blue', 'purple', 'red', 'direction' }
local SOLID = { gold = { 1, 0.8, 0.22 }, white = { 1, 1, 1 }, green = { 0.3, 0.95, 0.35 }, blue = { 0.35, 0.65, 1 },
                purple = { 0.75, 0.45, 1 }, red = { 1, 0.3, 0.25 } }

--- gold on course, ember off to the side, red behind (rel in radians, counter-clockwise)
function Arrow.Tint(rel)
  local off = math.abs(rel > math.pi and rel - PI2 or rel)   -- 0 = dead ahead, pi = behind
  if off < 0.35 then return 1, 0.92, 0.7 end                 -- ~20 degrees
  if off < 1.6 then
    local t = (off - 0.35) / 1.25
    return 1, 0.92 - 0.32 * t, 0.7 - 0.32 * t
  end
  return 1, 0.42, 0.34
end

--- green ahead, yellow off to the side, red behind (the solid arrow's 'direction' colours)
function Arrow.Traffic(rel)
  local off = math.abs(rel > math.pi and rel - PI2 or rel) / math.pi   -- 0 ahead .. 1 behind
  if off < 0.5 then return 0.3 + 1.4 * off, 0.95, 0.3 end           -- green to yellow
  return 1, 0.95 - 1.3 * (off - 0.5), 0.3 - 0.1 * (off - 0.5)        -- yellow to red
end

--- the arrow's colour for a heading, in the look the player picked
function Arrow.Colour(rel)
  local look = ns.settings.arrowLook or 'relic'
  if look == 'relic' then return Arrow.Tint(rel) end
  if look == 'direction' then return Arrow.Traffic(rel) end
  local c = SOLID[look] or SOLID.gold
  return c[1], c[2], c[3]
end

local function fmtYards(y)
  -- one unit everywhere, the game's own (the card said "2653 yd" where the arrow said "2.4 km"; Oct 18)
  return (ns.L.yardsShort or '%d yd'):format(math.floor(y + 0.5))   -- ("126 m" on a German client, as the game says it)
end

local function fmtTime(sec)
  if not sec or sec ~= sec or sec <= 0 or sec > 3600 then return '' end
  sec = math.floor(sec + 0.5)
  return ('%d:%02d'):format(math.floor(sec / 60), sec % 60)
end

local function savePosition()
  local point, _, rel, x, y = frame:GetPoint()
  if point then ns.db.frames.arrow = { point, rel, x, y } end
end

Arrow.SCALE = { 0.25, 2.5 }   -- the arrow's size, from tiny to big (settings.arrowScale)

function Arrow.SetScale(v)
  v = math.max(Arrow.SCALE[1], math.min(Arrow.SCALE[2], math.floor(v * 100 + 0.5) / 100))
  ns.settings.arrowScale = v
  if frame then frame:SetScale(v) end
  return v
end

--- the painted arrow or a plain one, and the step text under it (settings.arrowLook, settings.arrowText)
function Arrow.ApplyLook()
  if not frame then return end
  local look = ns.settings.arrowLook or 'relic'
  art:SetTexture(Skin.MEDIA .. (look == 'relic' and 'arrow' or 'arrow-solid'))
  label:SetShown(ns.settings.arrowText ~= false)
  if Arrow.target then Arrow.Update(0) end
end

function Arrow.SetLook(look)
  ns.settings.arrowLook = look
  Arrow.ApplyLook()
end

--- the arrow's options, for its own right-click menu and the guide's menu
function Arrow.MenuItems(root)
  local L = ns.L
  root:CreateCheckbox(L.menuArrow, function() return ns.settings.arrow ~= false end,
    function() Arrow.Enable(ns.settings.arrow == false) end)
  root:CreateCheckbox(L.arrowText, function() return ns.settings.arrowText ~= false end,
    function() ns.settings.arrowText = ns.settings.arrowText == false Arrow.ApplyLook() end)
  local style = root:CreateButton(L.arrowStyle)
  for _, look in ipairs(Arrow.LOOKS) do
    style:CreateRadio(L.ARROW_LOOKS[look], function() return (ns.settings.arrowLook or 'relic') == look end,
      function() Arrow.SetLook(look) end)
  end
  root:CreateButton(L.menuSettings, function() ns.Book.Open('map') end)
  root:CreateCheckbox(L.arrowLock, function() return ns.settings.arrowLocked end,
    function() ns.settings.arrowLocked = not ns.settings.arrowLocked end)
  root:CreateButton(L.arrowReset, function() Arrow.ResetPosition() end)
end

local function menu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(ns.L.arrowTitle)
    local map = Arrow.target and Arrow.target.map
    if map then root:CreateButton(ns.L.menuShowMap, function() ns.Waypoint.ShowOnMap(map) end) end
    Arrow.MenuItems(root)
  end)
end

local DEFAULT_POINT = { 'TOP', 'TOP', 0, -140 }   -- top centre, where most players keep it

function Arrow.ResetPosition()
  ns.db.frames.arrow = nil
  if not frame then return end
  frame:ClearAllPoints()
  frame:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
end

function Arrow.Create()
  if frame then return frame end
  frame = CreateFrame('Button', 'BoFGuideArrow', UIParent)
  frame:SetSize(SIZE + 80, SIZE + 44)
  frame:SetFrameStrata('MEDIUM')
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag('LeftButton')
  frame:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  -- (a click that ended a drag isn't a click: the press clears the mark, the drag sets it)
  frame:SetScript('OnMouseDown', function(self) self.dragged = nil end)
  frame:SetScript('OnDragStart', function(self)
    self.dragged = true
    if not ns.settings.arrowLocked then self:StartMoving() end
  end)
  frame:SetScript('OnDragStop', function(self) self:StopMovingOrSizing() savePosition() end)
  -- right-click: its menu; a click: the world map where it points (FB-035 had Ctrl-click; FB-053, Nov 12: players
  -- asked for a click on the arrow to show the spot on the map, and nobody found Ctrl). A drag still moves it
  frame:SetScript('OnClick', function(self, button)
    if button == 'RightButton' then return menu(self) end
    if self.dragged then self.dragged = nil return end
    if Arrow.target then ns.Waypoint.ShowOnMap(Arrow.target.map) end
    if ns.Tour and ns.Tour.Did then ns.Tour.Did('map') end   -- (the tour's "try it" slide)
  end)
  local pos = ns.db.frames.arrow or DEFAULT_POINT
  frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  frame:SetScale(ns.settings.arrowScale or 1)
  -- the mouse wheel over the arrow makes it bigger or smaller (unless it's locked)
  frame:EnableMouseWheel(true)
  frame:SetScript('OnMouseWheel', function(_, delta)
    if ns.settings.arrowLocked then return end
    Arrow.SetScale((ns.settings.arrowScale or 1) + delta * 0.05)
  end)
  frame:SetScript('OnEnter', function(self) Skin.Tooltip(self, { ns.L.arrowTitle, ns.L.arrowHelp }, 'ANCHOR_BOTTOM') end)
  frame:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

  halo = Skin.Tex(frame, 'glow', 'BACKGROUND')
  halo:SetSize(SIZE * 1.9, SIZE * 1.9)
  halo:SetPoint('CENTER', frame, 'TOP', 0, -SIZE / 2 - 2)
  halo:SetAlpha(0.22)
  art = Skin.Tex(frame, 'arrow', 'ARTWORK')
  art:SetSize(SIZE, SIZE)
  art:SetPoint('CENTER', halo, 'CENTER', 0, 0)
  -- a hearth step with the stone ready: the Hearthstone itself, not a direction (owner, Nov 7)
  stone = frame:CreateTexture(nil, 'ARTWORK')
  stone:SetTexture('Interface\\Icons\\INV_Misc_Rune_01')
  stone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  stone:SetSize(SIZE * 0.74, SIZE * 0.74)
  stone:SetPoint('CENTER', halo, 'CENTER', 0, 0)
  if frame.CreateMaskTexture and stone.AddMaskTexture then   -- round, set in our bronze ring like the minimap seal
    local mask = frame:CreateMaskTexture()
    mask:SetTexture('Interface\\CharacterFrame\\TempPortraitAlphaMask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
    mask:SetAllPoints(stone)
    stone:AddMaskTexture(mask)
  end
  stone.ring = Skin.Tex(frame, 'ring', 'OVERLAY')
  stone.ring:SetSize(SIZE * 0.92, SIZE * 0.92)
  stone.ring:SetPoint('CENTER', stone, 'CENTER', 0, 0)
  stone.ring:Hide()
  stone:Hide()
  check = Skin.Tex(frame, 'arrived', 'ARTWORK')
  check:SetSize(SIZE * 0.8, SIZE * 0.8)
  check:SetPoint('CENTER', halo, 'CENTER', 0, 0)
  check:Hide()
  check.pulse = frame:CreateAnimationGroup()   -- the arrival mark breathes while you're there
  local grow = check.pulse:CreateAnimation('Scale')
  grow:SetTarget(check)
  grow:SetScaleFrom(1, 1)
  grow:SetScaleTo(1.12, 1.12)
  grow:SetDuration(0.6)
  grow:SetSmoothing('IN_OUT')
  check.pulse:SetLooping('BOUNCE')

  dist = Skin.String(frame, 'Number', 'OVERLAY', C.text)
  dist:SetPoint('TOP', art, 'BOTTOM', 0, -2)
  dist:SetJustifyH('CENTER')
  eta = Skin.String(frame, 'Small', 'OVERLAY', C.dim)
  eta:SetPoint('LEFT', dist, 'RIGHT', 6, 0)
  label = Skin.String(frame, 'Label', 'OVERLAY', C.gold)
  label:SetPoint('TOP', dist, 'BOTTOM', 0, -2)
  label:SetWidth(SIZE + 150)
  label:SetJustifyH('CENTER')
  label:SetWordWrap(true)
  if label.SetMaxLines then label:SetMaxLines(2) end

  Arrow.ApplyLook()
  frame:SetScript('OnUpdate', function(_, e)
    elapsed = elapsed + e
    if elapsed < UPDATE then return end
    local step = elapsed
    elapsed = 0
    ns.safecall('arrow', Arrow.Update, step)
  end)
  frame:Hide()
  return frame
end

--- the player's world position, through the same map transform as the target (C_Map.GetPlayerMapPosition, then
--- C_Map.GetWorldPosFromMapPos). UnitPosition isn't used: on Forever's new maps (Zephras Isle) it doesn't line up
--- with the maps' transform, and the arrow read kilometres for a spot 37 yards away. Both points through one
--- transform means any offset cancels, and the bearing stays true (a map transform only moves and scales).
local function player()
  local map = ns.clean(C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player'))
  if not map then return nil end
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, 'player')
  local x, y = ok and pos and ns.clean(pos.x), ok and pos and ns.clean(pos.y)
  if not (x and y) or (x == 0 and y == 0) then return nil end
  local c, wx, wy = ns.Geo.World(map, x * 100, y * 100)
  if not c then return nil end
  return wx, wy, c
end

--- both ways of measuring to the target, for /bofg selftest: { map = yards, unit = yards }
function Arrow.Distances()
  local t = Arrow.target
  if not (t and t.map and t.x) then return nil end
  local out = {}
  local tc, tx, ty = ns.Geo.World(t.map, t.x, t.y)
  local px, py = player()
  if tc and px then out.map = math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2) end
  if UnitPosition and tc then
    local uy, ux = UnitPosition('player')
    uy, ux = ns.clean(uy), ns.clean(ux)
    if ux and uy then out.unit = math.sqrt((tx - ux) ^ 2 + (ty - uy) ^ 2) end
  end
  return out
end

--- the target's world position: C_Map.GetWorldPosFromMapPos (Geo.World) gives the same axes as UnitPosition
local function targetWorld(t)
  local c, wx, wy = ns.Geo.World(t.map, t.x, t.y)
  if not c then return nil end
  return wx, wy, c
end

--- while you're a ghost: your body, on your map or the one above it (FB-029, Oct 18: "the arrow must point to the
--- corpse when the player is ghost"); nil otherwise
function Arrow.Corpse()
  if not (UnitIsGhost and ns.clean(UnitIsGhost('player'))) then return nil end
  if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return nil end
  local map = ns.clean(C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player'))
  for _ = 1, 4 do
    if not map or map == 0 then return nil end
    local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, map)
    local x, y = ok and pos and ns.clean(pos.x), ok and pos and ns.clean(pos.y)
    if x and y and not (x == 0 and y == 0) then
      return { map = map, x = x * 100, y = y * 100, name = ns.L.arrowBody, reach = 8, corpse = true }
    end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    map = info and ns.clean(info.parentMapID)
  end
  return nil
end

function Arrow.Update(step)
  local t = Arrow.Corpse() or Arrow.target
  if not (t and t.map and t.x) then frame:Hide() return end
  -- a hearth with the stone ready: show the stone (on cooldown it points where the hearth goes, for a player who walks)
  if t.hearth and not ns.Text.HearthLeft() then
    art:Hide() check:Hide()
    if check.pulse and check.pulse:IsPlaying() then check.pulse:Stop() end
    stone:Show() stone.ring:Show()
    halo:Show()
    halo:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    dist:SetText('')
    eta:SetText('')
    label:SetText(t.name or '')
    frame:EnableMouse(true)
    lastYards, speed = nil, nil
    return
  end
  stone:Hide() stone.ring:Hide()
  local px, py, pc = player()
  local tx, ty, tc = targetWorld(t)
  local facing = ns.clean(GetPlayerFacing and GetPlayerFacing())
  if not (px and tx and facing) then   -- instance, cave, or a secret position: nothing honest to point at, so nothing
    art:Hide() check:Hide() halo:Hide()
    dist:SetText('')
    eta:SetText('')
    label:SetText('')                  -- (the window has the step; words alone hang in the air, owner, Oct 31)
    frame:EnableMouse(false)           -- (and no dead patch of screen. Still running: it's back as soon as it can point)
    return
  end
  frame:EnableMouse(true)
  if pc ~= tc then   -- another continent: say where, don't point
    art:Hide() check:Hide() halo:Hide()
    dist:SetText(ns.L.arrowElsewhere:format(ns.Text.Map(t.map)))
    eta:SetText('')
    label:SetText(t.name or '')
    return
  end
  local rel, yards = Arrow.Solve(px, py, facing, tx, ty)
  -- (someone who walks: anywhere on their round is there, up to WALK_REACH; one who walks further is still pointed at)
  local reach = math.max(t.reach or 10, math.min(t.walk or 0, WALK_REACH))
  label:SetText(t.name or '')
  -- (a point on the way, or one spot of a loop: you're passing it, not there; the arrow keeps pointing while the guide
  -- moves it on. FB-032, Oct 22: "You're here" at every point of a walk read as "nothing here")
  if yards <= reach and not t.pass then
    art:Hide()
    check:Show()
    if check.pulse and not check.pulse:IsPlaying() then check.pulse:Play() end
    halo:Show()
    halo:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])
    dist:SetText(t.walk and ns.L.arrowWalks or ns.L.arrowHere)
    eta:SetText('')
    lastYards, speed = nil, nil
    return
  end
  check:Hide()
  if check.pulse and check.pulse:IsPlaying() then check.pulse:Stop() end
  art:Show()
  halo:Show()
  art:SetRotation(rel)
  local r, g, b = Arrow.Colour(rel)
  art:SetVertexColor(r, g, b)
  halo:SetVertexColor(r, g * 0.8, b * 0.6)
  halo:SetShown((ns.settings.arrowLook or 'relic') == 'relic')   -- the plain arrow stays plain
  dist:SetText(fmtYards(yards))
  -- speed toward the spot, smoothed; the time shows only while you're closing in
  local now = GetTime()
  if lastYards and lastAt and now > lastAt then
    local v = (lastYards - yards) / (now - lastAt)
    speed = speed and (speed * 0.85 + v * 0.15) or v
  end
  lastYards, lastAt = yards, now
  eta:SetText(speed and speed > 1.5 and fmtTime(yards / speed) or '')
end

--- point at target = { map, x, y, name, reach } (nil hides the arrow)
function Arrow.Set(target)
  Arrow.Create()
  target = Arrow.held or target   -- (/bofg mark test keeps it on its spot)
  local same = target and Arrow.target and target.map == Arrow.target.map and target.x == Arrow.target.x
    and target.y == Arrow.target.y
  Arrow.target = target
  if not same then lastYards, speed = nil, nil end
  local t = Arrow.Corpse() or target
  local on = t and t.map and t.x and ns.settings.arrow ~= false and ns.settings.shown
  frame:SetShown(on and true or false)
  if on then Arrow.Update(0) end
end

-- dying, letting go of the body and coming back: the arrow switches to your body and back
for _, ev in ipairs({ 'PLAYER_DEAD', 'PLAYER_ALIVE', 'PLAYER_UNGHOST' }) do
  ns.On(ev, function() if ns.db then Arrow.Set(Arrow.target) end end)
end

function Arrow.Enable(on)
  ns.settings.arrow = on and true or false
  Arrow.Set(Arrow.target)
end

--- where the arrow is on the screen, in UIParent's units (the Waymark's spark leaves from here); nil when it isn't up
function Arrow.Point()
  if not (frame and frame:IsShown() and halo:IsShown()) then return nil end
  local x, y = halo:GetCenter()
  x, y = ns.clean(x), ns.clean(y)
  local mine, ui = ns.clean(frame:GetEffectiveScale()), ns.clean(UIParent:GetEffectiveScale())
  if not (x and y and mine and ui) or ui == 0 then return nil end
  return x * mine / ui, y * mine / ui
end

--- what the arrow shows, for tests and /bofg report
function Arrow.State()
  if not frame then return nil end
  return { shown = frame:IsShown(), art = art:IsShown(), check = check:IsShown(), stone = stone:IsShown(), dist = dist:GetText(),
           label = label:GetText(), labelShown = label:IsShown(), rotation = art.__rotation, texture = art.__texture,
           color = art.__color }
end
