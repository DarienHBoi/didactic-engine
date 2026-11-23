-- How the guide works: a short tour over the real window (owner, Nov 13). The screen dims, a gold ring lights the
-- part a slide is about, and a plate beside it says what it does in a line or two. It points at the guide's own
-- frames, so it shows the guide as it is today in every language, and a test plays every slide. The game's frames are
-- only read (where the minimap is), never changed. A fight ends it.
-- Offered once after a new install's setup (Welcome.lua), and from the gear menu, the book's Help page and /bofg tour.
-- Chapters: 1 reading the card, 2 finding your way, 3 the guide follows you.
local _, ns = ...

local Tour = {}
ns.Tour = Tour
local L = ns.L
local Skin = ns.Skin
local C = Skin.C

local PLATE_W, PAD, GAP, HOLE = 300, 20, 16, 5
local DIM = 0.6

-- each slide: ch (its chapter), id (its words: L.tour<Id> = { title, text }), at (the part to light, from
-- Window.TourParts(), or 'arrow' / 'minimap'; none: the plate in the middle), need (left out when that part isn't on
-- screen: a card with no objectives has no objective slide), try (something to do: the slide says so, then waits)
local SLIDES = {
  { ch = 1, id = 'Intro', at = 'frame' },
  { ch = 1, id = 'Card', at = 'card', need = true },
  { ch = 1, id = 'Obj', at = 'obj', need = true },
  { ch = 1, id = 'Marks', at = 'marks', need = true },
  { ch = 1, id = 'Story', at = 'story', need = true },
  { ch = 1, id = 'NextUp', at = 'nexts', need = true },
  { ch = 1, id = 'Skip', at = 'skip', need = true, reveal = true },
  { ch = 1, id = 'Pace', at = 'pace', need = true },
  { ch = 2, id = 'Arrow', at = 'arrow', need = true },
  { ch = 2, id = 'ArrowTry', at = 'arrow', need = true, try = 'map' },
  { ch = 2, id = 'Pin', at = 'minimap' },
  { ch = 2, id = 'Faster', at = 'card', demo = 'faster' },
  { ch = 2, id = 'Fp', at = 'message', demo = 'fp' },
  { ch = 3, id = 'Follows', at = 'frame' },
  { ch = 3, id = 'Holds', at = 'card' },
  { ch = 3, id = 'PassBy', at = 'message', demo = 'passBy' },
  { ch = 3, id = 'LookBack', at = 'gear', need = true },
  { ch = 3, id = 'Gear', at = 'gear', need = true },
}
Tour.SLIDES = SLIDES
Tour.CHAPTERS = 3

-- the examples a slide shows in the window instead of your own card (owner, Nov 13: the Faster and flight path slides
-- said what a card does beside a card that didn't do it). Drawn in the guide's own words, with your own places: the
-- zone you're in, your inn, the next quest your road takes
local function zone()
  local pos = ns.st and ns.st.pos
  return (pos and pos.map and ns.Text.Map(pos.map)) or ''
end
local DEMO = {}
function DEMO.faster()
  return { icon = 'med-goto', title = L['goto']:format(zone(), 52.4, 61.8), lines = {
    { ('%s 52.4, 61.8  ·  %s'):format(zone(), L.tourDemoFar), C.faint },
    { L.fasterHearth:format((ns.st and ns.st.bind) or zone(), 140), C.ember } } }
end
function DEMO.fp()
  return { message = { L.learnFpTitle, L.learnFp:format(zone()), L.tourExample } }
end
function DEMO.passBy()
  local quest, npc
  local lev = ns.Engine.Leveling and ns.Engine.Leveling()
  local st = ns.st or {}
  for _, s in ipairs(lev and lev.steps or {}) do
    local giver = s.o == 'accept' and s.who and s.who[1]
    if giver then
      local q = type(s.id) == 'table' and s.id[1] or s.id
      if q and not ((st.completed or {})[q] or (st.log or {})[q]) then
        quest, npc = ns.Text.Quest(q, lev.pack), ns.Text.Npc(giver, lev.pack)
        break
      end
    end
  end
  if not quest then return nil end
  return { message = { L.passByTitle, L.passBy:format(quest, npc), L.tourExample } }
end
Tour.DEMO = DEMO

local root, dims, ring, plate, offer
local list, idx, tried, kept, after, chapter

-- ------------------------------------------------------------------------------------------------------- the parts
local function shownFrame(name)
  local f = rawget(_G, name)
  return f and f.IsShown and f:IsShown() and f or nil
end

--- the region (or list of regions) a slide lights, or nil when it isn't on screen
local function part(at)
  if not at then return nil end
  if at == 'arrow' then return shownFrame('BoFGuideArrow') end
  if at == 'minimap' then return shownFrame('Minimap') end
  local p = ns.Window.TourParts and ns.Window.TourParts() or {}
  return p[at]
end
Tour.Part = part

--- where it is, in UIParent's units: { left, bottom, right, top }, round all its regions
local function rectOf(r)
  local regions = (type(r) == 'table' and not r.GetLeft) and r or { r }
  local us = UIParent:GetEffectiveScale() or 1
  local l, b, rt, t
  for _, x in ipairs(regions) do
    local xl, xb, xr, xt = x:GetLeft(), x:GetBottom(), x:GetRight(), x:GetTop()
    -- (a line of text placed by its top and width: as tall as its wrapped text)
    if xt and x.GetStringHeight and (x:GetStringHeight() or 0) > 0 then xb = math.min(xb or xt, xt - x:GetStringHeight()) end
    if xl and xb and xr and xt then
      local owner = x.GetEffectiveScale and x or (x.GetParent and x:GetParent())
      local s = ((owner and owner.GetEffectiveScale and owner:GetEffectiveScale()) or us) / us
      xl, xb, xr, xt = xl * s, xb * s, xr * s, xt * s
      l = l and math.min(l, xl) or xl
      b = b and math.min(b, xb) or xb
      rt = rt and math.max(rt, xr) or xr
      t = t and math.max(t, xt) or xt
    end
  end
  return l and { l - HOLE, b - HOLE, rt + HOLE, t + HOLE } or nil
end
Tour.RectOf = rectOf

-- ------------------------------------------------------------------------------------------------------ the frames
local function edge(parent, layer)
  local t = parent:CreateTexture(nil, layer or 'OVERLAY')
  t:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.95)
  return t
end

local function build()
  root = CreateFrame('Frame', 'BoFGuideTour', UIParent)
  root:SetAllPoints(UIParent)
  root:SetFrameStrata('FULLSCREEN_DIALOG')
  root:Hide()
  -- four dark panes round the lit part: the part itself stays bright and can be clicked (the "try it" slides)
  dims = {}
  for i = 1, 4 do
    local d = CreateFrame('Frame', 'BoFGuideTourDim' .. i, root)
    d:EnableMouse(true)
    d.t = d:CreateTexture(nil, 'BACKGROUND')
    d.t:SetAllPoints(d)
    d.t:SetColorTexture(0, 0, 0, DIM)
    dims[i] = d
  end
  -- the ring: a gold line round the part and a breathing ember glow
  ring = CreateFrame('Frame', 'BoFGuideTourRing', root)
  ring:SetFrameLevel(root:GetFrameLevel() + 5)
  ring.glow = Skin.Tex(ring, 'glow', 'BACKGROUND')
  ring.glow:SetBlendMode('ADD')
  ring.glow:SetVertexColor(C.ember[1], C.ember[2], C.ember[3])
  ring.glow:SetPoint('TOPLEFT', ring, 'TOPLEFT', -26, 26)
  ring.glow:SetPoint('BOTTOMRIGHT', ring, 'BOTTOMRIGHT', 26, -26)
  ring.glow:SetAlpha(0.35)
  local top, bottom, left, right = edge(ring), edge(ring), edge(ring), edge(ring)
  top:SetPoint('TOPLEFT', ring, 'TOPLEFT', 0, 0) top:SetPoint('TOPRIGHT', ring, 'TOPRIGHT', 0, 0) top:SetHeight(2)
  bottom:SetPoint('BOTTOMLEFT', ring, 'BOTTOMLEFT', 0, 0) bottom:SetPoint('BOTTOMRIGHT', ring, 'BOTTOMRIGHT', 0, 0)
  bottom:SetHeight(2)
  left:SetPoint('TOPLEFT', ring, 'TOPLEFT', 0, 0) left:SetPoint('BOTTOMLEFT', ring, 'BOTTOMLEFT', 0, 0) left:SetWidth(2)
  right:SetPoint('TOPRIGHT', ring, 'TOPRIGHT', 0, 0) right:SetPoint('BOTTOMRIGHT', ring, 'BOTTOMRIGHT', 0, 0)
  right:SetWidth(2)
  ring.breath = ring:CreateAnimationGroup()
  if ring.breath.SetLooping then ring.breath:SetLooping('BOUNCE') end
  local a = ring.breath:CreateAnimation('Alpha')
  a:SetFromAlpha(0.55)
  a:SetToAlpha(1)
  a:SetDuration(0.9)
  -- the plate: where we are, the slide's title and words, Back and Next, and a cross to stop
  plate = CreateFrame('Frame', 'BoFGuideTourPlate', root)
  plate:SetFrameLevel(root:GetFrameLevel() + 10)
  plate:SetWidth(PLATE_W)
  plate:EnableMouse(true)
  plate:SetClampedToScreen(true)
  plate.skin = Skin.Panel(plate)
  plate.label = Skin.String(plate, 'Label', 'OVERLAY', C.faint)
  plate.label:SetPoint('TOPLEFT', plate, 'TOPLEFT', PAD, -PAD)
  plate.label:SetPoint('RIGHT', plate, 'RIGHT', -PAD - 22, 0)
  plate.label:SetWordWrap(false)
  plate.title = Skin.String(plate, 'Heading', 'OVERLAY', C.gold)
  plate.title:SetWidth(PLATE_W - 2 * PAD)
  plate.text = Skin.String(plate, 'Text', 'OVERLAY', C.text)
  plate.text:SetWidth(PLATE_W - 2 * PAD)
  plate.close = Skin.IconButton(plate, 16, 'btn-close', function() Tour.Stop() end, 'BoFGuideTourClose', L.tourCloseTip)
  plate.close:SetPoint('TOPRIGHT', plate, 'TOPRIGHT', -PAD + 4, -PAD + 4)
  plate.next = Skin.Button(plate, 96, 24, L.tourNext, function() Tour.Go(1) end, 'BoFGuideTourNext')
  plate.next:SetPoint('BOTTOMRIGHT', plate, 'BOTTOMRIGHT', -PAD, PAD)
  plate.back = Skin.Button(plate, 80, 24, L.tourBack, function() Tour.Go(-1) end, 'BoFGuideTourBack')
  plate.back:SetPoint('RIGHT', plate.next, 'LEFT', -8, 0)
  -- (it follows its part: the window redraws, the arrow moves)
  local wait = 0
  root:SetScript('OnUpdate', function(_, dt)
    wait = wait + (dt or 0)
    if wait < 0.1 then return end
    wait = 0
    Tour.Place()
  end)
end

local function sizeButton(b, text, min)
  b.text:SetText(text)
  b:SetWidth(math.max(min, (b.text:GetStringWidth() or 40) + 26))
end

local function shows(slide)
  if slide.on ~= nil then return slide.on end   -- (settled when the tour starts: an example hides your card's parts)
  if slide.demo then return DEMO[slide.demo]() ~= nil end
  return not slide.need or part(slide.at) ~= nil
end

--- the slide's place among those that show now, and how many there are: "3 of 15"
local function position()
  local n, at = 0, 1
  for i, s in ipairs(list) do
    if shows(s) or i == idx then n = n + 1 end
    if i == idx then at = n end
  end
  return at, n
end

--- the plate's words for the slide on screen, and its size
local function fill(slide)
  local words = L['tour' .. slide.id] or { slide.id, '' }
  local text = words[2]
  if slide.try and tried == slide.try then text = L['tour' .. slide.id .. 'Done'] or text end
  local at, of = position()
  plate.label:SetText(ns.upper(L.tourChapters[slide.ch] or '') .. '  ·  ' .. L.tourStep:format(at, of))
  plate.title:ClearAllPoints()
  plate.title:SetPoint('TOPLEFT', plate.label, 'BOTTOMLEFT', 0, -8)
  plate.title:SetText(words[1])
  plate.text:ClearAllPoints()
  plate.text:SetPoint('TOPLEFT', plate.title, 'BOTTOMLEFT', 0, -8)
  plate.text:SetText(text)
  sizeButton(plate.next, idx >= #list and L.tourDone or L.tourNext, 96)
  sizeButton(plate.back, L.tourBack, 80)
  plate.back:SetShown(idx > 1)
  Tour.Size()
end

--- the plate as tall as its words: measured again each time it's placed, since the game can measure new text by the
--- old text's lines until the next frame (the German first slide's last line ran under Next)
function Tour.Size()
  local h = PAD + (plate.label:GetStringHeight() or 12) + 8 + (plate.title:GetStringHeight() or 16) + 8
    + (plate.text:GetStringHeight() or 30) + 18 + 24 + PAD
  if math.abs((plate:GetHeight() or 0) - h) > 0.5 then plate:SetHeight(h) end
end

local function placeDims(hole, W, H)
  local panes
  if hole then
    local l, b, r, t = math.max(0, hole[1]), math.max(0, hole[2]), math.min(W, hole[3]), math.min(H, hole[4])
    panes = { { 0, 0, W, b }, { 0, t, W, H }, { 0, b, l, t }, { r, b, W, t } }
  else
    panes = { { 0, 0, W, H } }
  end
  for i, d in ipairs(dims) do
    local p = panes[i]
    if p and p[3] > p[1] and p[4] > p[2] then
      d:ClearAllPoints()
      d:SetPoint('BOTTOMLEFT', root, 'BOTTOMLEFT', p[1], p[2])
      d:SetSize(p[3] - p[1], p[4] - p[2])
      d:Show()
    else
      d:Hide()
    end
  end
end

--- where everything goes now: the panes and the ring round the part, the plate beside it
function Tour.Place()
  if not (root and root:IsShown() and list and list[idx]) then return end
  local slide = list[idx]
  Tour.Size()
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local hole = rectOf(part(slide.at) or {})
  local open = slide.try and tried == slide.try   -- (done: the map it opened stays in plain sight)
  for _, d in ipairs(dims) do
    d.t:SetAlpha(open and 0 or 1)
    d:EnableMouse(not open)
  end
  placeDims(not open and hole or nil, W, H)
  if hole and not open then
    ring:ClearAllPoints()
    ring:SetPoint('BOTTOMLEFT', root, 'BOTTOMLEFT', hole[1], hole[2])
    ring:SetSize(hole[3] - hole[1], hole[4] - hole[2])
    ring:Show()
    if not ring.breath:IsPlaying() then ring.breath:Play() end
  else
    ring:Hide()
  end
  local pw, ph = plate:GetWidth(), plate:GetHeight()
  local x, y
  if hole and not open then
    -- beside the part: left of it if there's room, else right, else under or over it. A part of the guide window keeps
    -- the plate off the whole window (the gear's plate sat over the cards)
    local side = hole
    local win = rectOf(ns.Window.TourParts().frame or {})
    if win and hole[1] >= win[1] - 1 and hole[3] <= win[3] + 1 and hole[2] >= win[2] - 1 and hole[4] <= win[4] + 1 then
      side = { win[1], hole[2], win[3], hole[4] }
    end
    if side[1] - GAP - pw >= 8 then x = side[1] - GAP - pw
    elseif side[3] + GAP + pw <= W - 8 then x = side[3] + GAP end
    if x then
      y = (hole[2] + hole[4]) / 2 - ph / 2
    else
      x = math.min(math.max(8, hole[1]), W - pw - 8)
      y = hole[2] - GAP - ph
      if y < 8 then y = hole[4] + GAP end
    end
  else
    x, y = (W - pw) / 2, open and 60 or (H - ph) / 2
  end
  y = math.min(math.max(8, y), H - ph - 8)
  plate:ClearAllPoints()
  plate:SetPoint('BOTTOMLEFT', root, 'BOTTOMLEFT', x, y)
end

-- ---------------------------------------------------------------------------------------------------- the running
--- move on (1) or back (-1), past the slides whose part isn't on screen
function Tour.Go(dir)
  if not list then return end
  local i = idx + dir
  while list[i] and not shows(list[i]) do i = i + dir end
  if i > #list then return Tour.Stop(true) end
  if i < 1 then return end
  Tour.Unreveal()
  idx, tried = i, nil
  ns.Window.Demo(list[idx].demo and DEMO[list[idx].demo]() or nil)
  if list[idx].reveal then
    local r = part(list[idx].at)
    if r and r.Show then r:Show() end
  end
  fill(list[idx])
  Tour.Place()
end

--- a part shown for its slide only (the card's », shown on the mouse): hidden again unless the mouse is on it
function Tour.Unreveal()
  local slide = list and list[idx]
  if not (slide and slide.reveal) then return end
  local r = part(slide.at)
  local card = part('card')
  if r and r.Hide and not (card and card.IsMouseOver and card:IsMouseOver()) then r:Hide() end
end

--- something the slide asked for was done (the arrow clicked: 'map')
function Tour.Did(what)
  local slide = list and list[idx]
  if not (root and root:IsShown() and slide and slide.try == what) then return end
  tried = what
  fill(slide)
  Tour.Place()
end

--- start the tour: a chapter, or the three in a row. `andThen` runs when it ends, however it ends
function Tour.Start(ch, andThen)
  if InCombatLockdown and InCombatLockdown() then
    ns.say(L.tourNotInFight)
    if andThen then andThen() end
    return false
  end
  if not root then build() end
  if offer then offer:Hide() end
  ns.db.tour = ns.db.tour or {}
  ns.db.tour.offered = true
  chapter, after = ch, andThen
  -- the window open and unfolded for the tour, as it was again after it
  ns.Window.Create()
  kept = { collapsed = ns.settings.collapsed, hidden = not ns.settings.shown }
  if ns.settings.collapsed then
    ns.settings.collapsed = false
    ns.MarkDirty('collapse')
  end
  if kept.hidden then ns.Window.Toggle() end
  list = {}
  for _, s in ipairs(SLIDES) do if not ch or s.ch == ch then list[#list + 1] = s end end
  idx, tried = 0, nil
  Tour.running = true
  root:Show()
  -- (the window draws on the next frame: the first slide waits for it, behind a dimmed screen)
  placeDims(nil, UIParent:GetWidth(), UIParent:GetHeight())
  ring:Hide()
  plate:Hide()
  for _, s in ipairs(list) do s.on = nil end
  C_Timer.After(0.2, function()
    if not Tour.running then return end
    -- which slides this tour shows, read once from your own card (the count stays "3 of 15" from start to end)
    for _, s in ipairs(list) do
      local r = s.reveal and part(s.at)
      s.on = shows(s) or (r ~= nil)
    end
    plate:Show()
    Tour.Go(1)
  end)
  return true
end

--- end it: the window as it was; `finished` when the last slide's Done was pressed
function Tour.Stop(finished)
  if not Tour.running then return end
  Tour.Unreveal()
  Tour.running = false
  ns.Window.Demo(nil)   -- (your own card again)
  if root then root:Hide() end
  if kept then
    if kept.collapsed and not ns.settings.collapsed then
      ns.settings.collapsed = true
      ns.MarkDirty('collapse')
    end
    if kept.hidden and ns.settings.shown and not (InCombatLockdown and InCombatLockdown()) then ns.Window.Toggle() end
    kept = nil
  end
  if finished then
    ns.db.tour = ns.db.tour or {}
    ns.db.tour.seen = ns.db.tour.seen or {}
    for c = 1, Tour.CHAPTERS do if not chapter or c == chapter then ns.db.tour.seen[c] = true end end
    ns.say(L.tourFinished)
  end
  list, idx, tried = nil, 0, nil
  local fn = after
  after = nil
  if fn then fn() end
end

--- the slide on screen, for tests: { id, ch, n, of, title, text, lit } or nil
function Tour.Current()
  local slide = list and list[idx]
  if not (Tour.running and slide and plate and plate:IsShown()) then return nil end
  local at, of = position()
  return { id = slide.id, ch = slide.ch, n = at, of = of, title = plate.title:GetText(), text = plate.text:GetText(),
           lit = ring:IsShown() }
end

-- a fight ends it: the panes would sit over the world while you fight, and nothing here can wait
ns.On('PLAYER_REGEN_DISABLED', function()
  if Tour.running then
    Tour.Stop()
    ns.say(L.tourFight)
  end
  if offer and offer:IsShown() then offer:Hide() end
end)

-- -------------------------------------------------------------------------------------------------------- the offer
--- once, after a new install's setup: take the tour, or later. `andThen` runs after either (the AUTO plate)
function Tour.Offer(andThen)
  if not ns.db or (ns.db.tour and ns.db.tour.offered) or (InCombatLockdown and InCombatLockdown()) then
    if andThen then andThen() end
    return false
  end
  ns.db.tour = ns.db.tour or {}
  ns.db.tour.offered = true
  if not offer then
    offer = CreateFrame('Frame', 'BoFGuideTourOffer', UIParent)
    offer:SetFrameStrata('DIALOG')
    offer:SetWidth(PLATE_W + 40)
    offer:SetPoint('CENTER', UIParent, 'CENTER', 0, 80)
    offer:EnableMouse(true)
    offer:SetClampedToScreen(true)
    offer.skin = Skin.Panel(offer)
    offer.title = Skin.String(offer, 'Heading', 'OVERLAY', C.gold)
    offer.title:SetPoint('TOPLEFT', offer, 'TOPLEFT', PAD + 4, -PAD - 4)
    offer.title:SetWidth(PLATE_W)
    offer.text = Skin.String(offer, 'Text', 'OVERLAY', C.text)
    offer.text:SetPoint('TOPLEFT', offer.title, 'BOTTOMLEFT', 0, -8)
    offer.text:SetWidth(PLATE_W)
    offer.go = Skin.Button(offer, 140, 26, L.tourTake, function()
      offer:Hide()
      Tour.Start(nil, offer.after)
    end, 'BoFGuideTourTake')
    offer.later = Skin.Button(offer, 90, 26, L.tourLater, function()
      offer:Hide()
      ns.say(L.tourLaterChat)
      local fn = offer.after
      offer.after = nil
      if fn then fn() end
    end, 'BoFGuideTourLater')
    offer.go:SetPoint('BOTTOMRIGHT', offer, 'BOTTOMRIGHT', -PAD - 4, PAD + 4)
    offer.later:SetPoint('RIGHT', offer.go, 'LEFT', -8, 0)
  end
  offer.after = andThen
  offer.title:SetText(L.tourOfferTitle)
  offer.text:SetText(L.tourOfferText)
  sizeButton(offer.go, L.tourTake, 140)
  sizeButton(offer.later, L.tourLater, 90)
  offer:Show()
  offer:SetHeight(PAD + 4 + (offer.title:GetStringHeight() or 16) + 8 + (offer.text:GetStringHeight() or 30) + 20 + 26
    + PAD + 4)
  return true
end
