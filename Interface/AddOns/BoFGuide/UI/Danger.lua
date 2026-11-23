-- Bind on Forever Guide: dangerous creatures on the world map (Batch 2 of the RestedXP audit, Oct 18: their players'
-- top Hardcore aid). The packs carry the elites, rare elites and rares of the zones their free roads cross
-- (pack.danger, danger.py, QuestieDB's spawns until our captures replace them); this draws the ones of the map you're
-- looking at, on a frame of our own laid over the map's canvas (no Blizzard table or function is touched), the same
-- size on screen at any zoom, and leaves out the ones you've outlevelled. Hover one: its name, level and kind.
-- Setting: settings.dangerMap.
local _, ns = ...
local Danger = {}
ns.Danger = Danger

local SKULL = 'Interface/TargetingFrame/UI-TargetingFrame-Skull'
local COLOR = { e = { 1, 0.45, 0.2 }, re = { 0.8, 0.45, 1 }, r = { 0.85, 0.85, 0.95 } }
local OUTLEVEL = { e = 3, re = 3, r = 2 }   -- you're this many levels above it: no longer shown
local SIZE = 14

local layer, pins, ticker = nil, {}, nil
local spots = {}   -- the next stops' numbered marks
local shownMap, shownScale, shownLevel, shownSteps
local NEXT = 5
-- the next steps' badges: a socket in the guide's bronze ring, the number in gold, a faint ember glow, above the game's
-- own map pins (owner, Nov 6: the small yellow dots were easy to miss, and the game's destination pin hid the first).
-- One on the same spot as the destination pin sits up and to its right, so both show
local BADGE, ABOVE_PINS, BESIDE_PIN = 30, 1000, 1.2   -- size on screen; frame levels above the canvas; map percent

--- the marks for a map, from every loaded pack: { { x, y, npc, level, kind, pack }, ... }, outlevelled ones left out
function Danger.For(map, level)
  local out = {}
  for _, pack in pairs(ns.Packs.byId or {}) do
    for _, d in ipairs(pack.danger and pack.danger[map] or {}) do
      if not level or level < d[4] + (OUTLEVEL[d[5]] or 3) then
        out[#out + 1] = { d[1], d[2], d[3], d[4], d[5], pack }
      end
    end
  end
  return out
end

--- the guide's next stops on a map, in order: { { x, y, words }, ... }, at most NEXT (one per spot)
function Danger.NextSpots(map)
  local route, view = ns.Engine.Route(), ns.Engine.View()
  if not (route and view and route.pack and route.pack.pts) then return {} end
  local order = {}
  for _, i in ipairs(ns.Engine.OnScreen() or {}) do order[#order + 1] = i end
  for _, i in ipairs(view.upcoming or {}) do order[#order + 1] = i end
  local out, seen = {}, {}
  for _, i in ipairs(order) do
    local s = route.steps[i]
    -- (a flight's badge on its flight master, where you go for it, not where it lands; and a spot written on another
    -- map, a city's or its zone's or the continent's, shown on the one you look at: Nov 9, the RestedXP arrow study's #8)
    local pi = s and ((s.o == 'fly' and s.dp) or s.p)
    local pt = pi and route.pack.pts[pi]
    if pt and pt[1] ~= map and ns.Geo and ns.Geo.OnMap then pt = ns.Geo.OnMap(pt, map) end
    if pt and pt[1] == map and not seen[pi] then
      seen[pi] = true
      out[#out + 1] = { pt[2], pt[3], ns.plain(ns.Text.Step(s, route.pack)) or '' }
      if #out >= NEXT then break end
    end
  end
  return out
end

local function spot(i)
  local p = spots[i]
  if p then return p end
  p = CreateFrame('Button', nil, layer)
  local Skin, C = ns.Skin, ns.Skin.C
  p.glow = Skin.Tex(p, 'glow', 'BACKGROUND')
  p.glow:SetPoint('TOPLEFT', -12, 12)
  p.glow:SetPoint('BOTTOMRIGHT', 12, -12)
  p.glow:SetVertexColor(C.ember[1], C.ember[2], C.ember[3], 1)
  p.glow:SetBlendMode('ADD')
  p.well = Skin.Tex(p, 'disc', 'ARTWORK')
  p.well:SetPoint('TOPLEFT', 2, -2)
  p.well:SetPoint('BOTTOMRIGHT', -2, 2)
  p.tex = Skin.Tex(p, 'ring', 'OVERLAY')
  p.tex:SetAllPoints()
  p.num = p:CreateFontString(nil, 'OVERLAY')
  p.num:SetFontObject(Skin.Font.Badge or Skin.Font.Label)
  p.num:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  p.num:SetPoint('CENTER', 0, 0)
  p:SetScript('OnEnter', function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
    GameTooltip:AddLine(ns.L.nextSpot:format(self.n), 1, 0.82, 0)
    GameTooltip:AddLine(self.words or '', 1, 1, 1, true)
    GameTooltip:Show()
  end)
  p:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  spots[i] = p
  return p
end

local function canvas()
  local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
  return sc and sc.Child
end

local function pin(i)
  local p = pins[i]
  if p then return p end
  p = CreateFrame('Button', nil, layer)
  p:SetSize(SIZE, SIZE)
  p.tex = p:CreateTexture(nil, 'OVERLAY')
  p.tex:SetAllPoints()
  p.tex:SetTexture(SKULL)
  p:SetScript('OnEnter', function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
    GameTooltip:AddLine(self.name or '?', 1, 0.35, 0.3)
    GameTooltip:AddLine(ns.L.DANGER_KIND[self.kind]:format(self.level), 1, 0.82, 0)
    GameTooltip:AddLine(ns.L.dangerTip, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  p:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  pins[i] = p
  return p
end

function Danger.Draw()
  local child = canvas()
  if not child then return end
  if not layer then
    layer = CreateFrame('Frame', 'BoFGuideDangerLayer', child)
    layer:SetAllPoints(child)
    layer:SetFrameLevel((child:GetFrameLevel() or 1) + ABOVE_PINS)
  end
  local map = ns.clean(WorldMapFrame:GetMapID())
  local scale = child:GetEffectiveScale() or 1
  local level = ns.st and ns.st.level or 1
  local next = (map and ns.settings.nextMap ~= false) and Danger.NextSpots(map) or {}
  local sig = {}
  for _, d in ipairs(next) do sig[#sig + 1] = d[1] .. ',' .. d[2] end
  sig = table.concat(sig, ';')
  if map == shownMap and scale == shownScale and level == shownLevel and sig == shownSteps then return end
  shownMap, shownScale, shownLevel, shownSteps = map, scale, level, sig
  local list = (map and ns.settings.dangerMap ~= false) and Danger.For(map, level) or {}
  local w, h = child:GetWidth() or 0, child:GetHeight() or 0
  local k = (UIParent:GetEffectiveScale() or 1) / scale    -- the same size on screen at any zoom
  for i, d in ipairs(list) do
    local p = pin(i)
    p:ClearAllPoints()
    p:SetSize(SIZE * k, SIZE * k)
    p:SetPoint('CENTER', layer, 'TOPLEFT', d[1] / 100 * w, -d[2] / 100 * h)
    local c = COLOR[d[5]] or COLOR.e
    p.tex:SetVertexColor(c[1], c[2], c[3])
    p.name, p.level, p.kind = ns.Text.Npc(d[3], d[6]), d[4], d[5]
    p:Show()
  end
  for i = #list + 1, #pins do pins[i]:Hide() end
  local aim = ns.Arrow and ns.Arrow.target
  for i, d in ipairs(next) do
    local p = spot(i)
    p:ClearAllPoints()
    -- the whole badge is scaled to the screen, its number with it (Nov 8, the owner: sized on the map's canvas, the
    -- number grew with every zoom step while the disc stayed put, and overflowed it even zoomed out). A frame's
    -- anchor offsets are in its own scale, so the map spot is divided by it
    p:SetScale(k)
    p:SetSize(BADGE, BADGE)
    local beside = aim and aim.map == map and aim.x and math.abs(aim.x - d[1]) < BESIDE_PIN
      and math.abs(aim.y - d[2]) < BESIDE_PIN
    local dx, dy = beside and BADGE * 0.75 or 0, beside and BADGE * 0.75 or 0
    p:SetPoint('CENTER', layer, 'TOPLEFT', d[1] / 100 * w / k + dx, -d[2] / 100 * h / k + dy)
    p:SetFrameLevel(layer:GetFrameLevel() + 5)
    p.beside = beside and true or false
    p.num:SetText(tostring(i))
    p.n, p.words = i, d[3]
    p:Show()
  end
  for i = #next + 1, #spots do spots[i]:Hide() end
  layer:Show()
end

--- the numbered badges shown now, in order: true where one is set beside the game's destination pin (tests)
function Danger.Badges()
  local out = {}
  for _, p in ipairs(spots) do if p:IsShown() then out[#out + 1] = p.beside or false end end
  return out
end

--- how many marks are on the map now (tests, /bofg report)
function Danger.Shown()
  local n, m = 0, 0
  for _, p in ipairs(pins) do if p:IsShown() then n = n + 1 end end
  for _, p in ipairs(spots) do if p:IsShown() then m = m + 1 end end
  return n, m
end

local function start()
  if ticker or not (C_Timer and C_Timer.NewTicker) then return end
  shownMap = nil
  ticker = C_Timer.NewTicker(0.25, function() ns.safecall('danger', Danger.Draw) end)
  ns.safecall('danger', Danger.Draw)
end

local function stop()
  if ticker then ticker:Cancel() ticker = nil end
end

local hooked
function Danger.Attach()
  if hooked or not WorldMapFrame or not WorldMapFrame.HookScript then return end
  hooked = true
  WorldMapFrame:HookScript('OnShow', start)
  WorldMapFrame:HookScript('OnHide', stop)
  if WorldMapFrame:IsShown() then start() end
end

ns.On('PLAYER_LOGIN', function() ns.safecall('danger', Danger.Attach) end)
ns.On('ADDON_LOADED', function(name) if name == 'Blizzard_WorldMap' then ns.safecall('danger', Danger.Attach) end end)
