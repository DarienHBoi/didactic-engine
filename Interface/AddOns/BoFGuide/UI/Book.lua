-- The guide book (owner, Nov 10: the settings and the guide menus were "a massive opportunity to improve the visual
-- presentation, organization, and just a deep professional polish overall"). One window in the oath's painted frame
-- (Skin.Ornate): a rail of pages on the left, grouped (the guides, the settings by topic, purchases and help), and the
-- page on the right, which scrolls when it runs long.
--   guides    your leveling road leg by leg (where you are, what's behind you, the full guide's part), other starting
--             zones folded under it; dungeon guides by how they fit your level; profession guides; Legacy; talents
--   settings  every setting of the game's Settings page, grouped by what it changes, each with what it does in plain
--             words under its name. A setting applies the moment it's changed, as on the game's page
--   more      the purchased guide and its key; help, feedback and the tools
-- Opened from the seal's menu, the addon menu by the minimap (right-click) and /bofg book. The game's own Settings
-- page stays as it was (it's searchable there). Our own frames only; Escape closes it.
local _, ns = ...

local Book = {}
ns.Book = Book
local L = ns.L
local Skin = ns.Skin
local C = Skin.C

local W, H = 920, 660
local MIN_H = H              -- (taller when the rail needs it: buildRail)
local HEAD = 128              -- the painted band at the top, with the page's title
local SIDE = 36               -- the space inside the frame's bars
local RAIL_W = 196
local GAP = 26
local BODY_L = SIDE + RAIL_W + GAP
local TOP = HEAD + 18         -- where the rail and the page begin
local FOOT = 44               -- above the bottom bar
local ENTRY = 30              -- a rail entry
local SCROLL_W = 12           -- the page's scroll bar
local CARD_H = 50             -- a guide's card
local STEP = 48               -- what one turn of the mouse wheel scrolls

local frame, rail, body, canvas, bar, thumb, title, subtitle, version
local current = 'leveling'
local scroll, extent = 0, 0
local open = {}               -- other starting zones unfolded this session
local entries, built = {}, {}

-- ------------------------------------------------------------------------------------------------------- helpers
local function who() return ns.Engine.Who() end
local function redraw() ns.MarkDirty('settings') end

local function solid(parent, layer, sub, c, a)
  local t = parent:CreateTexture(nil, layer or 'BACKGROUND', nil, sub)
  t:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1)
  return t
end

--- a soft band of light, strongest at the left (a lit rail entry, a chosen card)
local function sheen(parent, layer, sub, c, a)
  local t = parent:CreateTexture(nil, layer or 'BACKGROUND', nil, sub)
  t:SetColorTexture(1, 1, 1, 1)
  if t.SetGradient and CreateColor then
    t:SetGradient('HORIZONTAL', CreateColor(c[1], c[2], c[3], a), CreateColor(c[1], c[2], c[3], 0))
  else
    t:SetColorTexture(c[1], c[2], c[3], a / 2)
  end
  return t
end

--- a thin line round a box, recolored when it's chosen
local function edges(box, c, a)
  box.edge = box.edge or {}
  for i, spec in ipairs({ { 'TOPLEFT', 'TOPRIGHT', 0, 1 }, { 'BOTTOMLEFT', 'BOTTOMRIGHT', 0, 1 },
                          { 'TOPLEFT', 'BOTTOMLEFT', 1, 0 }, { 'TOPRIGHT', 'BOTTOMRIGHT', 1, 0 } }) do
    local t = box.edge[i]
    if not t then
      t = box:CreateTexture(nil, 'BORDER', nil, 2)
      t:SetPoint(spec[1], box, spec[1], 0, 0)
      t:SetPoint(spec[2], box, spec[2], 0, 0)
      if spec[3] > 0 then t:SetWidth(spec[3]) else t:SetHeight(spec[4]) end
      box.edge[i] = t
    end
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
  end
end

local function levels(lo, hi)
  lo, hi = math.floor(lo), math.floor(hi + 0.5)
  if lo == hi then return L.bookLevel:format(lo) end
  return L.bookLevels:format(lo, hi)
end

-- ------------------------------------------------------------------------------------------------- the page's parts
-- Each page is drawn into the canvas from the top down: every part takes the y it starts at and hands back the y under
-- it. Parts are made once per page and kept; a page shown again is laid out again with what's true now.
local Page = {}
Page.__index = Page

local function newPage(id)
  local p = setmetatable({ id = id, parts = {}, n = 0 }, Page)
  p.frame = CreateFrame('Frame', nil, canvas)
  p.frame:SetPoint('TOPLEFT', canvas, 'TOPLEFT', 0, 0)
  p.frame:SetPoint('TOPRIGHT', canvas, 'TOPRIGHT', 0, 0)
  p.frame:SetHeight(10)
  return p
end

function Page:width() return (W - BODY_L - SIDE) - SCROLL_W - 8 end

--- the next kept part of a kind, made the first time by `make`
function Page:part(kind, make)
  self.n = self.n + 1
  local k = self.parts[self.n]
  if not k or k.kind ~= kind then
    k = make()
    k.kind = kind
    if self.parts[self.n] and self.parts[self.n].Hide then self.parts[self.n]:Hide() end
    self.parts[self.n] = k
  end
  k:Show()
  return k
end

function Page:begin()
  self.n = 0
  self.cards = {}
  for _, k in ipairs(self.parts) do k:Hide() end
end

--- a few plain words across the page
function Page:words(y, text, color, style)
  local k = self:part('words', function()
    local f = CreateFrame('Frame', nil, self.frame)
    f.fs = Skin.String(f, style or 'BookText', 'OVERLAY', color or C.dim)
    f.fs:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, 0)
    return f
  end)
  k:ClearAllPoints()
  k:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, y)
  k:SetSize(self:width(), 10)
  k.fs:SetFontObject(Skin.Font[style or 'BookText'])
  k.fs:SetTextColor(unpack(color or C.dim))
  k.fs:SetWidth(self:width())
  k.fs:SetText(text)
  k:ClearAllPoints()
  k:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, y)
  k:SetSize(self:width(), 10)
  k.fs:Show()
  local h = k.fs:GetStringHeight() or 14
  k:SetHeight(h)
  return y - h
end

--- a heading with a hairline under it
function Page:section(y, text, aside)
  local k = self:part('section', function()
    local f = CreateFrame('Frame', nil, self.frame)
    f.fs = Skin.String(f, 'BookLabel', 'OVERLAY', C.gold)
    f.fs:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 0, 7)
    f.aside = Skin.String(f, 'BookSmall', 'OVERLAY', C.faint)
    f.aside:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', 0, 7)
    f.aside:SetJustifyH('RIGHT')
    f.line = Skin.Hairline(f)
    f.line:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 0, 0)
    f.line:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', 0, 0)
    return f
  end)
  y = y - (y < 0 and 18 or 0)
  k:ClearAllPoints()
  k:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, y)
  k:SetSize(self:width(), 26)
  k.fs:SetText(ns.upper(text))
  k.aside:SetText(aside or '')
  return y - 26 - 10
end

-- a setting's row: its name, what it does under it, and its control on the right (a tick box) or under the words
-- (choices, a slider). The whole row answers the mouse for a tick box.
local function rowFrame(page)
  local b = CreateFrame('Button', nil, page.frame)
  b.hl = sheen(b, 'HIGHLIGHT', 0, C.ember, 0.10)
  b.hl:SetAllPoints(b)
  b.name = Skin.String(b, 'BookBody', 'OVERLAY', C.text)
  b.name:SetPoint('TOPLEFT', b, 'TOPLEFT', 10, -8)
  b.desc = Skin.String(b, 'BookSmall', 'OVERLAY', C.faint)
  b.desc:SetPoint('TOPLEFT', b.name, 'BOTTOMLEFT', 0, -3)
  b.rule = solid(b, 'BACKGROUND', 1, C.lineSoft, 0.9)
  b.rule:SetHeight(1)
  b.rule:SetPoint('BOTTOMLEFT', b, 'BOTTOMLEFT', 0, 0)
  b.rule:SetPoint('BOTTOMRIGHT', b, 'BOTTOMRIGHT', 0, 0)
  return b
end

--- lays out a row's words in `room` and hands back their bottom, from the row's top
local function words(b, name, desc, room, page, y, x)
  b:ClearAllPoints()
  b:SetPoint('TOPLEFT', page.frame, 'TOPLEFT', x or 0, y)
  b:SetWidth(page:width() - (x or 0))
  b:SetHeight(40)
  b:Show()
  b.name:SetWidth(room)
  b.name:SetText(name)
  b.desc:SetWidth(room)
  b.desc:SetText(desc or '')
  b.name:Show()
  b.desc:Show()
  local h = 8 + (b.name:GetStringHeight() or 14)
  if desc and desc ~= '' then h = h + 3 + (b.desc:GetStringHeight() or 12) end
  return h
end

--- a tick box: get() is the setting, set(v) changes it and applies it
function Page:toggle(y, name, desc, get, set)
  local b = self:part('toggle', function()
    local r = rowFrame(self)
    r.box = Skin.Tex(r, 'check-empty', 'ARTWORK')
    r.box:SetSize(26, 26)
    r.box:SetPoint('RIGHT', r, 'RIGHT', -12, 0)
    r.state = Skin.String(r, 'BookLabel', 'OVERLAY', C.faint)
    r.state:SetPoint('RIGHT', r.box, 'LEFT', -8, 0)
    r.state:SetJustifyH('RIGHT')
    r:SetScript('OnClick', function(self)
      self.set(not self.get())
      self.paint()
      if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856) end
    end)
    r:SetScript('OnEnter', function(self) self.name:SetTextColor(unpack(C.gold)) end)
    r:SetScript('OnLeave', function(self) self.name:SetTextColor(unpack(C.text)) end)
    return r
  end)
  b.get, b.set = get, set
  b.paint = function()
    local on = b.get() and true or false
    b.box:SetTexture(Skin.MEDIA .. (on and 'check-done' or 'check-empty'))
    b.state:SetText(ns.upper(on and L.bookOn or L.bookOff))
    b.state:SetTextColor(unpack(on and C.gold or C.faint))
  end
  b.paint()
  local w = self:width()
  local h = words(b, name, desc, w - 130, self, y) + 10
  b:ClearAllPoints()
  b:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, y)
  b:SetSize(w, math.max(44, h))
  return y - math.max(44, h)
end

--- a choice of a few: plates in a row under the words, the chosen one lit (like the oath's)
function Page:choice(y, name, desc, keys, labels, get, set)
  local b = self:part('choice', function()
    local r = rowFrame(self)
    r:EnableMouse(false)
    r.hl:Hide()
    r.plates = {}
    return r
  end)
  local w = self:width()
  local h = words(b, name, desc, w - 20, self, y) + 10
  local x, line = 10, 0
  for i, k in ipairs(keys) do
    local p = b.plates[i]
    if not p then
      p = Skin.Button(b, 120, 26, '', function(self)
        self.owner.set(self.key)
        for _, q in ipairs(self.owner.plates) do Skin.Choose(q, q.key == self.key) end
      end)
      p.owner = b
      b.plates[i] = p
    end
    p.key = k
    p.text:SetText(labels[k] or k)
    p:SetWidth(math.max(110, (p.text:GetStringWidth() or 0) + 40))
    if x + p:GetWidth() > w - 10 and x > 10 then x, line = 10, line + 1 end
    p:ClearAllPoints()
    p:SetPoint('TOPLEFT', b, 'TOPLEFT', x, -h - line * 34)
    p:Show()
    x = x + p:GetWidth() + 10
  end
  for i = #keys + 1, #b.plates do b.plates[i]:Hide() end
  b.get, b.set = get, set
  local cur = get()
  for _, q in ipairs(b.plates) do if q:IsShown() then Skin.Choose(q, q.key == cur) end end
  h = h + (line + 1) * 34 + 6
  b:ClearAllPoints()
  b:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, y)
  b:SetSize(w, h)
  return y - h
end

--- a slider on the painted bar with a rivet for its thumb; the value on the right of the name. It applies as you drag
function Page:slider(y, name, desc, lo, hi, step, get, set, fmt)
  local b = self:part('slider', function()
    local r = rowFrame(self)
    r:EnableMouse(false)
    r.hl:Hide()
    r.value = Skin.String(r, 'BookNumber', 'OVERLAY', C.gold)
    r.value:SetPoint('TOPRIGHT', r, 'TOPRIGHT', -12, -8)
    r.value:SetJustifyH('RIGHT')
    local s = CreateFrame('Slider', nil, r)
    s:SetOrientation('HORIZONTAL')
    s:SetHeight(18)
    s.track = Skin.ThreeSlice(s, 'bar-track', 12, 12, 'BACKGROUND')
    s.track:Place(s, 0, 0, -3)
    s.fill = Skin.ThreeSlice(s, 'bar-fill', 8, 6, 'ARTWORK')
    s.knob = Skin.Tex(s, 'rivet', 'OVERLAY')
    s.knob:SetSize(20, 20)
    local th = s:CreateTexture(nil, 'OVERLAY')
    th:SetColorTexture(0, 0, 0, 0)
    th:SetSize(20, 20)
    s:SetThumbTexture(th)
    function s.paint(v)
      local a, z = s:GetMinMaxValues()
      local frac = (z > a) and math.max(0, math.min(1, ((v or a) - a) / (z - a))) or 0
      local span = (s.wide or 300) - 20
      s.knob:ClearAllPoints()
      s.knob:SetPoint('CENTER', s, 'LEFT', 10 + span * frac, 0)
      s.fill.l:ClearAllPoints()
      s.fill.l:SetPoint('LEFT', s, 'LEFT', 3, 0)
      s.fill.r:ClearAllPoints()
      s.fill.r:SetPoint('LEFT', s, 'LEFT', 3 + math.max(12, 10 + span * frac - 3), 0)
      s.fill.m:ClearAllPoints()
      s.fill.m:SetPoint('LEFT', s.fill.l, 'RIGHT', 0, 0)
      s.fill.m:SetPoint('RIGHT', s.fill.r, 'LEFT', 0, 0)
      s.fill:SetShown(frac > 0.01)
    end
    s:SetObeyStepOnDrag(true)
    s:EnableMouseWheel(true)
    s:SetScript('OnMouseWheel', function(self, delta)
      local a, z = self:GetMinMaxValues()
      self:SetValue(math.max(a, math.min(z, (self:GetValue() or a) + delta * (self.step or 0.05))))
    end)
    s:SetScript('OnValueChanged', function(self, v)
      if self.quiet then return end
      local got = r.set(v)
      r.value:SetText(r.fmt(got or v))
      self.paint(got or v)
    end)
    r.s = s
    return r
  end)
  b.set, b.fmt = set, fmt or function(v) return ('%d%%'):format(v * 100 + 0.5) end
  local w = self:width()
  local h = words(b, name, desc, w - 110, self, y) + 12
  local s = b.s
  s.step = step
  s.quiet = true
  s:SetMinMaxValues(lo, hi)
  s:SetValueStep(step)
  s:SetValue(get())
  s.quiet = nil
  b.value:SetText(b.fmt(get()))
  s:ClearAllPoints()
  s:SetPoint('TOPLEFT', b, 'TOPLEFT', 12, -h)
  s:SetPoint('TOPRIGHT', b, 'TOPRIGHT', -12, -h)
  s.wide = w - 24
  s.paint(get())
  h = h + 18 + 14
  b:ClearAllPoints()
  b:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, y)
  b:SetSize(w, h)
  return y - h
end

--- one of many, stepped through: ‹ the chosen one ›
function Page:stepper(y, name, desc, keys, labels, get, set)
  local b = self:part('stepper', function()
    local r = rowFrame(self)
    r:EnableMouse(false)
    r.hl:Hide()
    r.shown = Skin.String(r, 'BookBody', 'OVERLAY', C.gold)
    r.shown:SetJustifyH('CENTER')
    local function move(d)
      local i = 1
      for j, k in ipairs(r.keys) do if k == r.get() then i = j end end
      i = (i - 1 + d) % #r.keys + 1
      r.set(r.keys[i])
      r.shown:SetText(r.labels[r.keys[i]] or r.keys[i])
    end
    r.prev = Skin.IconButton(r, 26, 'btn-collapse', function() move(-1) end, nil, L.bookPrev)
    r.prev.icon:SetRotation(-math.pi / 2)
    r.next = Skin.IconButton(r, 26, 'btn-collapse', function() move(1) end, nil, L.bookNext)
    r.next.icon:SetRotation(math.pi / 2)
    r.well = solid(r, 'BACKGROUND', 1, C.well, 0.8)
    return r
  end)
  b.keys, b.labels, b.get, b.set = keys, labels, get, set
  local w = self:width()
  local h = words(b, name, desc, w - 20, self, y) + 10
  b.prev:ClearAllPoints()
  b.prev:SetPoint('TOPLEFT', b, 'TOPLEFT', 10, -h)
  b.next:ClearAllPoints()
  b.next:SetPoint('TOPLEFT', b, 'TOPLEFT', 10 + 26 + 340, -h)
  b.well:ClearAllPoints()
  b.well:SetPoint('TOPLEFT', b.prev, 'TOPRIGHT', 4, 0)
  b.well:SetPoint('BOTTOMRIGHT', b.next, 'BOTTOMLEFT', -4, 0)
  b.shown:ClearAllPoints()
  b.shown:SetPoint('LEFT', b.prev, 'RIGHT', 8, 0)
  b.shown:SetPoint('RIGHT', b.next, 'LEFT', -8, 0)
  b.shown:SetText(labels[get()] or get())
  h = h + 26 + 12
  b:ClearAllPoints()
  b:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, y)
  b:SetSize(w, h)
  return y - h
end

--- a row with a button on its right that does something (opens a window, runs a tool)
function Page:action(y, name, desc, label, run)
  local b = self:part('action', function()
    local r = rowFrame(self)
    r:EnableMouse(false)
    r.hl:Hide()
    r.go = Skin.Button(r, 150, 28, '', function(self) self.run() end)
    r.go:SetPoint('RIGHT', r, 'RIGHT', -10, 0)
    return r
  end)
  b.go.run = run
  b.go.text:SetText(label)
  b.go:SetWidth(math.max(130, (b.go.text:GetStringWidth() or 0) + 40))
  local w = self:width()
  local h = words(b, name, desc, w - b.go:GetWidth() - 40, self, y) + 10
  b:ClearAllPoints()
  b:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', 0, y)
  b:SetSize(w, math.max(48, h))
  return y - math.max(48, h)
end

--- a guide's card: its medallion, its name, a line under it, and a tag on the right (where you are, done, your level).
--- `o` = { icon, name, sub, tag, tagColor, chosen, dim, indent, click, tip }
function Page:card(y, o)
  local b = self:part('card', function()
    local r = CreateFrame('Button', nil, self.frame)
    r.bg = solid(r, 'BACKGROUND', 0, C.surface2, 0.55)
    r.bg:SetAllPoints(r)
    r.lit = sheen(r, 'BACKGROUND', 1, C.ember, 0.22)
    r.lit:SetAllPoints(r)
    r.hl = sheen(r, 'HIGHLIGHT', 0, C.gold, 0.10)
    r.hl:SetAllPoints(r)
    r.mark = solid(r, 'ARTWORK', 1, C.gold, 1)
    r.mark:SetWidth(3)
    r.mark:SetPoint('TOPLEFT', r, 'TOPLEFT', 0, 0)
    r.mark:SetPoint('BOTTOMLEFT', r, 'BOTTOMLEFT', 0, 0)
    r.icon = Skin.Tex(r, nil, 'ARTWORK')
    r.icon:SetSize(32, 32)
    r.icon:SetPoint('LEFT', r, 'LEFT', 12, 0)
    r.frameIcon = CreateFrame('Frame', nil, r)
    r.frameIcon:SetPoint('TOPLEFT', r.icon, 'TOPLEFT', -1, 1)
    r.frameIcon:SetPoint('BOTTOMRIGHT', r.icon, 'BOTTOMRIGHT', 1, -1)
    edges(r.frameIcon, C.frameHi, 0.9)
    r.up = solid(r, 'BORDER', 0, C.frame, 1)
    r.up:SetWidth(2)
    r.up:SetPoint('BOTTOM', r.icon, 'TOP', 0, 0)
    r.up:SetPoint('TOP', r, 'TOPLEFT', 28, 7)
    r.down = solid(r, 'BORDER', 0, C.frame, 1)
    r.down:SetWidth(2)
    r.down:SetPoint('TOP', r.icon, 'BOTTOM', 0, 0)
    r.down:SetPoint('BOTTOM', r, 'BOTTOMLEFT', 28, -1)
    r.name = Skin.String(r, 'BookBody', 'OVERLAY', C.text)
    r.name:SetPoint('TOPLEFT', r, 'TOPLEFT', 54, -9)
    r.name:SetWordWrap(false)
    r.sub = Skin.String(r, 'BookSmall', 'OVERLAY', C.faint)
    r.sub:SetPoint('TOPLEFT', r.name, 'BOTTOMLEFT', 0, -3)
    r.sub:SetWordWrap(false)
    r.tag = Skin.String(r, 'BookLabel', 'OVERLAY', C.gold)
    r.tag:SetPoint('RIGHT', r, 'RIGHT', -14, 0)
    r.tag:SetJustifyH('RIGHT')
    -- a switch at the card's right (a dungeon in your road or not: FB-053), its own click, not the card's
    r.sw = CreateFrame('Button', nil, r)
    r.sw:SetSize(22, 22)
    r.sw:SetPoint('RIGHT', r, 'RIGHT', -12, 0)
    r.sw.box = Skin.Tex(r.sw, 'check-empty', 'ARTWORK')
    r.sw.box:SetAllPoints(r.sw)
    r.sw.tick = Skin.Tex(r.sw, 'check', 'OVERLAY')
    r.sw.tick:SetAllPoints(r.sw)
    r.sw.hl = Skin.Tex(r.sw, 'glow', 'HIGHLIGHT')
    r.sw.hl:SetPoint('CENTER', r.sw, 'CENTER', 0, 0)
    r.sw.hl:SetSize(36, 36)
    r.sw.hl:SetBlendMode('ADD')
    r.sw.hl:SetAlpha(0.4)
    r.sw:SetScript('OnClick', function(self)
      local sw = self:GetParent().o.switch
      if sw then sw.set(not sw.get()) end
    end)
    r.sw:SetScript('OnEnter', function(self)
      local sw = self:GetParent().o.switch
      if sw and sw.tip then Skin.Tooltip(self, sw.tip, 'ANCHOR_RIGHT') end
    end)
    r.sw:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    r:SetScript('OnClick', function(self) if self.o.click then self.o.click(self) end end)
    r:SetScript('OnEnter', function(self)
      edges(self, C.frameHi, 0.9)
      if self.o.tip then Skin.Tooltip(self, self.o.tip, 'ANCHOR_RIGHT') end
    end)
    r:SetScript('OnLeave', function(self)
      edges(self, self.o.chosen and C.gold or C.line, self.o.chosen and 0.9 or 0.8)
      if GameTooltip then GameTooltip:Hide() end
    end)
    return r
  end)
  b.o = o
  self.cards[#self.cards + 1] = b
  local w = self:width() - (o.indent or 0)
  local game = type(o.icon) == 'number'
  b.icon:SetTexture(game and o.icon or o.icon and (o.icon:find('\\') and o.icon or Skin.MEDIA .. o.icon) or nil)
  if game then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else b.icon:SetTexCoord(0, 1, 0, 1) end
  b.icon:SetSize(game and 30 or 32, game and 30 or 32)
  b.frameIcon:SetShown(game)
  b.up:SetShown(o.road == 'mid' or o.road == 'last')
  b.down:SetShown(o.road == 'mid' or o.road == 'first')
  b.icon:SetDesaturated(o.dim and true or false)
  b.icon:SetAlpha(o.dim and 0.6 or 1)
  b.name:SetText(o.name or '')
  b.name:SetTextColor(unpack(o.chosen and C.gold or o.dim and C.dim or C.text))
  b.sub:SetText(o.sub or '')
  b.tag:SetText(o.tag and ns.upper(o.tag) or '')
  b.tag:SetTextColor(unpack(o.tagColor or C.faint))
  b.sw:SetShown(o.switch and true or false)
  if o.switch then b.sw.tick:SetShown(o.switch.get() and true or false) end
  b.tag:ClearAllPoints()
  if o.switch then b.tag:SetPoint('RIGHT', b.sw, 'LEFT', -8, 0) else b.tag:SetPoint('RIGHT', b, 'RIGHT', -14, 0) end
  local room = w - 54 - 20 - (o.tag and ((b.tag:GetStringWidth() or 0) + 16) or 0) - (o.switch and 30 or 0)
  b.name:SetWidth(room)
  b.sub:SetWidth(room)
  b.lit:SetShown(o.chosen and true or false)
  b.mark:SetShown(o.chosen and true or false)
  edges(b, o.chosen and C.gold or C.line, o.chosen and 0.9 or 0.8)
  b:ClearAllPoints()
  b:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', o.indent or 0, y)
  b:SetSize(w, o.height or CARD_H)
  return y - (o.height or CARD_H) - 6
end

-- ---------------------------------------------------------------------------------------------------- the pages
local PAGES = {}

local function choose(r, after)
  ns.Engine.SetRoute(r.id)
  if after then after(r) end
  Book.Refresh()
end

-- other quests where you stand (FB-053, Nov 12: players asked to explore each zone fully): the ones offered on this
-- map that your road doesn't take, near your level, nearest first. A click puts the game's waypoint on the giver; once
-- taken, "Your quests here" brings the quest onto the card when it's near
local OTHER_MAX, OTHER_BELOW, OTHER_ABOVE = 8, 4, 3
local function otherQuests(me)
  local pos = ns.st and ns.st.pos
  local map = pos and pos.map
  if not (map and pos.x) then return {} end
  local level = me.level or 1
  local st = ns.st
  local out = {}
  for _, o in ipairs(ns.Packs.ZoneQuests(map)) do
    if not ((st.completed and st.completed[o.q]) or (st.log and st.log[o.q])) and (o.lo or 1) <= level
        and o.lvl >= level - OTHER_BELOW and o.lvl <= level + OTHER_ABOVE then
      o.d = ns.Geo and ns.Geo.YardsTo({ map, o.x, o.y }) or 0
      o.map = map
      out[#out + 1] = o
    end
  end
  table.sort(out, function(a, b) return a.d < b.d end)
  while #out > OTHER_MAX do table.remove(out) end
  return out
end
Book.OtherQuests = otherQuests

local function otherTitle(o)
  local t = ns.clean(C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(o.q))
  if t and t ~= '' then return t end
  return (o.pack.zqn and o.pack.zqn[o.q]) or L.quest:format(o.q)
end

local function pinGiver(o, title, giver)
  local WP = ns.Waypoint
  if not (C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(o.map)) then return end
  WP.yieldedFor = WP.aim   -- (the player's own pick: the guide leaves the waypoint alone for this step)
  WP.owned = nil
  WP.setting = true
  local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(o.map, o.x / 100, o.y / 100))
  if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  WP.setting = false
  if ok then ns.say(L.bookOtherPinned:format(giver, title)) end
end

-- your road: each leg with its levels, where you are, what's behind you and what's next; the full guide's part when
-- you don't have it; then the other starting zones, folded
PAGES.leveling = function(p, y)
  local me = who()
  local lev = ns.Engine.Leveling()
  local ended = ns.Engine.FreeEnded and ns.Engine.FreeEnded()
  y = p:words(y, L.bookLevelingAbout)
  local legs = ended and {} or ns.Packs.For(me)
  y = p:section(y, L.bookYourRoad, #legs > 0 and ns.count('bookParts', #legs) or nil)
  if ended then y = p:words(y, L.bookFreeEnded, C.text) end
  local level = me.level or 1
  for i, r in ipairs(legs) do
    local lo, hi = r.lv and r.lv[1] or 1, r.lv and r.lv[2] or 60
    local here = lev == r
    local tag, color, dim
    if here then tag, color = L.bookHere, C.gold
    elseif hi <= level then tag, color, dim = L.bookBehind, C.faint, true
    elseif lo - 1 <= level then tag, color = L.bookYourLevel, C.ember
    end
    local paid = r.pack and r.pack.tier == 'paid'
    local road = #legs > 1 and (i == 1 and 'first' or i == #legs and 'last' or 'mid') or nil
    y = p:card(y, { icon = paid and 'seal' or 'med-xp', name = Book.Short(r.title or r.id),
      sub = levels(lo, hi), tag = tag, tagColor = color, chosen = here, dim = dim, road = road,
      click = function() choose(r) end,
      tip = { r.title or r.id, here and L.bookHereTip or L.bookPickTip } })
  end
  if not ns.Link.HasFullGuide() then
    y = p:card(y - 4, { icon = 'seal-stamp', name = L.bookFullName, sub = L.bookFullSub, tag = L.bookSee,
      tagColor = C.ember, click = function() ns.Link.FullGuide() end, tip = { L.bookFullName, L.bookFullTip } })
  end
  local here = otherQuests(me)
  y = p:section(y, L.bookOtherQuests, #here > 0 and tostring(#here) or nil)
  y = p:words(y, L.bookOtherQuestsAbout)
  y = y - 8
  if #here == 0 then y = p:words(y, L.bookOtherNone, C.text) end
  for _, o in ipairs(here) do
    local title = otherTitle(o)
    local giver = ns.Text.Npc(o.npc, o.pack)
    y = p:card(y, { icon = 'face-quest', name = title, height = 42,
      sub = L.bookOtherSub:format(o.lvl, giver, math.floor((o.d or 0) / 10 + 0.5) * 10),
      click = function() pinGiver(o, title, giver) end, tip = { title, L.bookOtherTip } })
  end
  local others = ended and {} or ns.Packs.OtherStarts(me)
  if #others > 0 then
    y = p:section(y, L.menuOtherStarts)
    y = p:words(y, L.bookOtherAbout)
    y = y - 8
    for _, s in ipairs(others) do
      local id = s.head.id
      local note = s.noTrainer and L.bookNoTrainer or s.trainsAt and L.bookTrainsAt:format(s.trainsAt) or nil
      local lo = s.legs[1] and s.legs[1].lv and s.legs[1].lv[1] or 1
      local last = s.legs[#s.legs]
      local hi = last and last.lv and last.lv[2] or 30
      y = p:card(y, { icon = 'med-goto', name = Book.Short(s.head.title or id),
        sub = note and (levels(lo, hi) .. '  ·  ' .. note) or levels(lo, hi), tag = open[id] and L.bookFold or L.bookUnfold,
        tagColor = C.faint, click = function() open[id] = not open[id] Book.Refresh() end })
      if open[id] then
        local picked = s.noTrainer and L.pickedNoTrainer or s.trainsAt and L.pickedTrainsAt:format(s.trainsAt)
        for _, r in ipairs(s.legs) do
          local here = lev == r
          y = p:card(y, { icon = 'med-xp', name = Book.Short(r.title or r.id), road = 'mid',
            sub = levels(r.lv and r.lv[1] or 1, r.lv and r.lv[2] or 60), chosen = here, indent = 28, height = 42,
            tag = here and L.bookHere or nil, tagColor = C.gold,
            click = function()
              choose(r, function()
                local away = ns.Packs.StartsAway(r)
                if away then ns.say(L.pickedAway:format(away)) end
                if ns.Travel then ns.Travel.Start(r.id) end
                if picked then ns.say(picked) end
              end)
            end })
        end
      end
    end
  end
  return y
end

-- dungeons: the ones for your level first, then the ones still to come, then the ones you've outlevelled
PAGES.dungeons = function(p, y)
  local me = who()
  local level = me.level or 1
  local done = ns.cdb and ns.cdb.dungeons or {}
  local cur = ns.Engine.Route()
  y = p:words(y, L.bookDungeonsAbout)
  local now, later, past = {}, {}, {}
  for _, r in ipairs(ns.Packs.Dungeons(me)) do
    local lo, hi = r.lv and r.lv[1] or 1, r.lv and r.lv[2] or 60
    if hi < level then past[#past + 1] = r elseif lo - 2 > level then later[#later + 1] = r else now[#now + 1] = r end
  end
  -- (FB-053, Nov 12: a switch per dungeon, in your road or not, and how many of its quests you carry)
  local roads = ns.settings.dungeons ~= false
  local st, E = ns.st, ns.Evaluator
  local function carried(r)
    local all, have, seen = 0, 0, {}
    for _, s in ipairs(r.steps or {}) do
      if s.o == 'accept' and E.applies(s, me) then
        for _, q in ipairs(type(s.id) == 'table' and s.id or { s.id }) do
          if not seen[q] and not (st.completed and st.completed[q]) then
            seen[q] = true
            all = all + 1
            if st.log and st.log[q] then have = have + 1 end
          end
        end
      end
    end
    return have, all
  end
  local function list(t, dim)
    for _, r in ipairs(t) do
      local lo, hi = r.lv and r.lv[1] or 1, r.lv and r.lv[2] or 60
      local here = cur == r
      local tag, color
      if here then tag, color = L.bookOpenNow, C.gold
      elseif done[r.id] then tag, color = L.bookDone, C.done end
      local sub = levels(lo, hi)
      local have, all = carried(r)
      if all > 0 and not done[r.id] then sub = sub .. '  ·  ' .. L.bookQuestsInLog:format(have, all) end
      local id = r.id
      local switch = roads and {
        get = function() return not (ns.settings.dungeonOff and ns.settings.dungeonOff[id]) end,
        set = function(v)
          ns.settings.dungeonOff = ns.settings.dungeonOff or {}
          ns.settings.dungeonOff[id] = (not v) or nil
          ns.MarkDirty('dungeons')
          Book.Refresh()
        end,
        tip = { L.bookDungeonInRoad, L.bookDungeonInRoadTip } } or nil
      y = p:card(y, { icon = 'pin-dungeon', name = Book.Short(r.title or r.id), sub = sub, tag = tag,
        tagColor = color, chosen = here, dim = dim and not here, click = function() choose(r) end,
        tip = { r.title or r.id, L.bookDungeonTip }, switch = switch })
    end
  end
  if #now > 0 then y = p:section(y, L.bookForYourLevel) list(now) end
  if #later > 0 then y = p:section(y, L.bookLater) list(later) end
  if #past > 0 then y = p:section(y, L.bookBelow) list(past, true) end
  if #now + #later + #past == 0 then y = p:words(y, L.bookNoneYet, C.text) end
  return y
end

-- the game's icons for each profession (SpellMisc of its spell, from the client)
local PROF_ICON = { mining = 136248, herbalism = 136065, skinning = 134366, fishing = 136245, alchemy = 136240,
  blacksmithing = 136241, enchanting = 136244, engineering = 136243, leatherworking = 133611, tailoring = 136249,
  cooking = 133971, firstaid = 135966 }
Book.PROF_ICON = PROF_ICON

PAGES.professions = function(p, y)
  local me = who()
  local cur = ns.Engine.Route()
  y = p:words(y, L.bookProfsAbout)
  local list = ns.Packs.Professions(me)
  y = p:section(y, L.menuProfs, #list > 0 and ns.count('bookGuidesN', #list) or nil)
  for _, r in ipairs(list) do
    local here = cur == r
    local paid = r.pack and r.pack.tier == 'paid'
    local name = Book.Short(r.title or r.id)
    local nm, a, z = name:match('^(.-) +(%d+)%-(%d+)$')   -- (plain spaces: see Window.ShortTitle)
    local sub = a and L.bookSkills:format(tonumber(a), tonumber(z)) or ''
    if a and r.nx and not ns.Packs.Get(r.nx) then sub = sub .. '  ·  ' .. L.bookArtisanLater:format(tonumber(z)) end
    if paid then sub = L.bookPaidSub end
    y = p:card(y, { icon = PROF_ICON[r.pr] or 'med-craft', name = nm or name,
      sub = sub, tag = here and L.bookOpenNow or nil, tagColor = C.gold,
      chosen = here, click = function() choose(r) end, tip = { r.title or r.id, L.bookProfTip } })
  end
  if #list == 0 then y = p:words(y, L.bookNoneYet, C.text) end
  return y
end

PAGES.legacy = function(p, y)
  local leg = ns.Packs.Legacy(who())
  y = p:words(y, L.bookLegacyAbout)
  y = y - 10
  if leg then
    local here = ns.Engine.Route() == leg
    y = p:card(y, { icon = 'med-reward', name = L.menuLegacy, sub = Book.Short(leg.title or leg.id),
      tag = here and L.bookOpenNow or nil, tagColor = C.gold, chosen = here, click = function() choose(leg) end })
  end
  return y
end

PAGES.talents = function(p, y)
  y = p:words(y, L.bookTalentsAbout)
  y = p:section(y, L.menuTalents)
  local cur = ns.Talents.Plan()
  y = p:card(y, { icon = 'check-empty', name = L.menuTalentsNone, chosen = cur == nil,
    click = function() ns.Talents.SetPlan(nil) Book.Refresh() end })
  for _, plan in ipairs(ns.Talents.Plans()) do
    local t, about = ns.Talents.Title(plan), ns.Talents.About(plan)
    y = p:card(y, { icon = 'med-story', name = t, sub = about, chosen = cur == plan,
      tip = about ~= '' and { t, about } or nil, click = function()
        ns.Talents.SetPlan(plan.id)
        ns.say(L.talentsPicked:format(t))
        Book.Refresh()
      end })
  end
  return y
end

local S = function() return ns.settings end
local function flag(key, after)
  return function() return S()[key] end, function(v)
    S()[key] = v
    local apply = after or redraw
    apply()
  end
end

PAGES.questing = function(p, y)
  y = p:section(y, L.bookSecRoad)
  y = p:choice(y, L.optHardcore, L.optHardcoreTip, { 'auto', 'on', 'off' }, L.HC_MODES,
    function() return S().hc or 'auto' end,
    function(v) S().hc = v ns.State.Player() ns.MarkDirty('hc') end)
  local g, s = flag('dungeons', function() ns.MarkDirty('dungeons') end)
  y = p:toggle(y, L.optDungeons, L.optDungeonsTip, g, s)
  y = p:choice(y, L.optGroupQuests, L.optGroupQuestsTip, { 'party', 'always', 'never' }, L.GROUP_QUESTS,
    function() return S().groupQuests or 'party' end, function(v) S().groupQuests = v ns.MarkDirty('group') end)
  y = p:section(y, L.bookSecSteps)
  g, s = flag('storyOpen', function() ns.Window.ResetStories() redraw() end)
  y = p:toggle(y, L.optStoryOpen, L.optStoryOpenTip, g, s)
  g, s = flag('collapsed', function() redraw() if ns.Window.Header then ns.Window.Header() end end)
  y = p:toggle(y, L.optCollapsed, L.optCollapsedTip, g, s)
  y = p:slider(y, L.optUpcoming, L.optUpcomingTip, 0, 8, 1, function() return S().upcoming or 4 end,
    function(v) v = math.floor(v + 0.5) S().upcoming = v redraw() return v end, function(v) return ('%d'):format(v) end)
  return y
end

PAGES.automation = function(p, y)
  y = p:words(y, L.bookAutoAbout)
  y = p:section(y, L.menuAuto)
  for _, k in ipairs({ 'accept', 'turnin', 'gossip', 'taxi' }) do
    y = p:toggle(y, L.AUTO[k], L.BOOK_AUTO[k], function() return S().auto[k] end,
      function(v) S().auto[k] = v if ns.Window.Header then ns.Window.Header() end end)
  end
  local g, s = flag('readNew')
  y = p:toggle(y, L.optReadNew, L.optReadNewTip, g, s)
  y = p:section(y, L.bookSecVendors)
  g, s = flag('sellGrays')
  y = p:toggle(y, L.optSellGrays, L.optSellGraysTip, g, s)
  return y
end

PAGES.map = function(p, y)
  y = p:section(y, L.arrowTitle)
  local g, s = flag('arrow', function() ns.Arrow.Set(ns.Arrow.target) end)
  y = p:toggle(y, L.optArrow, L.optArrowTip, g, s)
  g, s = flag('arrowText', function() ns.Arrow.ApplyLook() end)
  y = p:toggle(y, L.arrowText, L.optArrowTextTip, g, s)
  local looks = {}
  for _, look in ipairs(ns.Arrow.LOOKS) do looks[look] = L.ARROW_LOOKS[look] end
  y = p:stepper(y, L.arrowStyle, L.optArrowStyleTip, ns.Arrow.LOOKS, looks, function() return S().arrowLook or 'relic' end,
    function(v) ns.Arrow.SetLook(v) end)
  y = p:slider(y, L.optArrowScale, L.optArrowScaleTip, ns.Arrow.SCALE[1], ns.Arrow.SCALE[2], 0.01,
    function() return S().arrowScale or 1 end, ns.Arrow.SetScale)
  g, s = flag('arrowLocked')
  y = p:toggle(y, L.arrowLock, L.bookArrowLockTip, g, s)
  y = p:action(y, L.bookArrowPlace, L.arrowReset .. '.', L.bookMoveBack, function() ns.Arrow.ResetPosition() end)
  y = p:section(y, L.bookSecWorldMap)
  g, s = flag('nextMap')
  y = p:toggle(y, L.optNextMap, L.optNextMapTip, g, s)
  g, s = flag('dangerMap')
  y = p:toggle(y, L.optDangerMap, L.optDangerMapTip, g, s)
  y = p:section(y, L.bookSecPanels)
  g, s = flag('targets', function() ns.Panels.Targets({}) redraw() end)
  y = p:toggle(y, L.optTargets, L.optTargetsTip, g, s)
  g, s = flag('items', function() ns.Panels.Want({}) redraw() end)
  y = p:toggle(y, L.optItems, L.optItemsTip, g, s)
  y = p:slider(y, L.optPanelScale, L.optPanelScaleTip, ns.Panels.SCALE[1], ns.Panels.SCALE[2], 0.01,
    function() return S().panelScale or 1 end, ns.Panels.SetScale)
  return y
end

PAGES.window = function(p, y)
  y = p:section(y, L.bookSecSize)
  y = p:slider(y, L.optScale, L.optScaleTip, ns.Window.SCALE[1], ns.Window.SCALE[2], 0.01,
    function() return S().scale or 1 end, function(v) ns.Window.SetScale(v) return S().scale end)
  y = p:slider(y, L.optWidth, L.optWidthTip, 280, 480, 10, function() return S().width or 340 end,
    function(v) v = math.floor(v / 10 + 0.5) * 10 S().width = v redraw() return v end,
    function(v) return ('%d'):format(v) end)
  y = p:slider(y, L.lookText, L.optTextTip, 0.7, 1.5, 0.05, function() return S().textScale or 1 end, function(v)
    v = math.floor(v * 20 + 0.5) / 20
    if v ~= S().textScale then S().textScale = v ns.Look.ApplyText() end
    return v
  end)
  y = p:slider(y, L.optOpacity, L.optOpacityTip, 0, 1, 0.02, function() return S().opacity or 0.6 end,
    function(v) ns.Window.SetOpacity(v) return S().opacity end)
  y = p:section(y, L.bookSecBehaviour)
  local g, s = flag('locked')
  y = p:toggle(y, L.optLocked, L.optLockedTip, g, s)
  g, s = flag('combatFade')
  y = p:toggle(y, L.optCombatFade, L.optCombatFadeTip, g, s)
  g, s = flag('minimap', function() ns.MinimapButton.Apply() end)
  y = p:toggle(y, L.optMinimap, L.optMinimapTip, g, s)
  return y
end

PAGES.alerts = function(p, y)
  y = p:section(y, L.bookSecDone)
  local g, s = flag('toasts')
  y = p:toggle(y, L.optToasts, L.optToastsTip, g, s)
  g, s = flag('sounds')
  y = p:toggle(y, L.optSounds, L.optSoundsTip, g, s)
  y = p:section(y, L.bookSecDanger)
  g, s = flag('rareAlert')
  y = p:toggle(y, L.optRareAlert, L.optRareAlertTip, g, s)
  g, s = flag('breath')
  y = p:toggle(y, L.optBreath, L.optBreathTip, g, s)
  g, s = flag('airTimer')
  y = p:toggle(y, L.optAirTimer, L.optAirTimerTip, g, s)
  return y
end

-- the full guide: what's in it (the shop's own list, site/src/lib/shop.ts IN_PACK), then adding your key
PAGES.purchases = function(p, y)
  local has = ns.Link.HasFullGuide()
  y = p:words(y, has and L.bookOwnedAbout or L.bookBuyAbout)
  if not has then
    y = p:section(y, L.bookSecInside)
    local see = function() ns.Link.FullGuide() end
    for _, e in ipairs({ { 'med-goto', L.bookInRoad, L.bookInRoadSub }, { 'med-boss', L.bookInDungeons, L.bookInDungeonsSub },
                         { 'med-craft', L.bookInCrafts, L.bookInCraftsSub }, { 'med-reward', L.bookInLegacy, L.bookInLegacySub } }) do
      y = p:card(y, { icon = e[1], name = e[2], sub = e[3], click = see, tip = { e[2], L.bookFullTip } })
    end
    y = p:action(y - 4, L.bookFullName, L.bookFullTip, L.bookSee, see)
  end
  y = p:section(y, L.importTitle)
  y = p:action(y, L.importTitle, L.importSettings, L.bookAdd, function() Book.Hide() ns.Import.Show() end)
  return y
end

PAGES.help = function(p, y)
  -- the tour, whole or a chapter at a time (UI/Tour.lua)
  y = p:section(y, L.menuTour)
  y = p:action(y, L.tourWhole, L.tourWholeTip, L.tourStart, function() Book.Hide() ns.Tour.Start() end)
  for c = 1, ns.Tour.CHAPTERS do
    y = p:action(y, L.tourChapters[c], L.tourChapterTips[c], L.tourStart, function() Book.Hide() ns.Tour.Start(c) end)
  end
  y = p:section(y, L.bookSecHelp)
  y = p:action(y, L.bookFeedback, L.bookFeedbackTip, L.bookWrite, function() Book.Hide() ns.Feedback.Show('bug') end)
  y = p:action(y, L.menuReport, L.bookReportTip, L.bookShow, function() ns.safecall('levellog', ns.LevelLog.Say) end)
  y = p:section(y, L.bookSecTools)
  y = p:action(y, L.bookCleanup, L.bookCleanupTip, L.bookCleanupGo, function()
    Book.Hide()
    ns.safecall('cleanup', ns.Cleanup.Ask)
  end)
  y = p:section(y, L.bookSecStart)
  y = p:action(y, L.bookOath, L.bookOathTip, L.bookOpen, function() Book.Hide() ns.Welcome.Oath() end)
  y = p:action(y, L.bookLanguage, L.bookLanguageTip, L.bookOpen, function() Book.Hide() ns.Welcome.Show() end)
  y = p:words(y - 14, L.bookSlash, C.faint, 'BookSmall')
  return y
end

-- ------------------------------------------------------------------------------------------------------ the rail
--- the rail's pages for this character, in groups: { group = name } starts one
local function railList()
  local me = who()
  local out = {
    { group = L.bookGuides },
    { id = 'leveling', icon = 'med-xp', name = L.bookLeveling, title = L.bookLevelingTitle },
    { id = 'dungeons', icon = 'pin-dungeon', name = L.bookDungeons, title = L.menuDungeons },
    { id = 'professions', icon = 'med-craft', name = L.bookProfessions, title = L.menuProfs },
  }
  if ns.Packs.Legacy(me) then out[#out + 1] = { id = 'legacy', icon = 'med-reward', name = L.bookLegacy, title = L.menuLegacy } end
  if ns.Talents and ns.Talents.Enabled() and #ns.Talents.Plans() > 0 then
    out[#out + 1] = { id = 'talents', icon = 'med-story', name = L.bookTalents, title = L.menuTalents }
  end
  for _, e in ipairs({
    { group = L.bookSettings },
    { id = 'questing', icon = 'pin-quest', name = L.bookQuesting, title = L.bookQuestingTitle },
    { id = 'automation', icon = 'med-use', name = L.bookAutomation, title = L.menuAuto },
    { id = 'map', icon = 'med-goto', name = L.bookMap, title = L.bookMapTitle },
    { id = 'window', icon = 'btn-settings', name = L.bookWindow, title = L.bookWindowTitle },
    { id = 'alerts', icon = 'med-danger', name = L.bookAlerts, title = L.bookAlertsTitle },
    { group = L.bookMore },
    { id = 'purchases', icon = 'seal', name = L.bookPurchases, title = L.bookPurchasesTitle },
    { id = 'help', icon = 'med-story', name = L.bookHelp, title = L.bookHelpTitle },
  }) do out[#out + 1] = e end
  return out
end

local function paintRail()
  for _, e in ipairs(entries) do
    if e.id then
      local on = e.id == current
      e.lit:SetShown(on)
      e.mark:SetShown(on)
      e.text:SetTextColor(unpack(on and C.gold or C.dim))
      e.icon:SetAlpha(on and 1 or 0.75)
    end
  end
end

local function buildRail()
  local list = railList()
  local y = 0
  local n = 0
  for _, e in ipairs(entries) do e:Hide() end
  for i, spec in ipairs(list) do
    n = n + 1
    local e = entries[n]
    if spec.group then
      if not e or not e.isGroup then
        e = CreateFrame('Frame', nil, rail)
        e.isGroup = true
        e.text = Skin.String(e, 'BookLabel', 'OVERLAY', C.goldSoft)
        e.text:SetPoint('BOTTOMLEFT', e, 'BOTTOMLEFT', 6, 5)
        entries[n] = e
      end
      y = y - (i > 1 and 16 or 0)
      e:ClearAllPoints()
      e:SetPoint('TOPLEFT', rail, 'TOPLEFT', 0, y)
      e:SetSize(RAIL_W, 22)
      e.text:SetText(ns.upper(spec.group))
      e.id = nil
      y = y - 24
    else
      if not e or e.isGroup then
        e = CreateFrame('Button', 'BoFGuideBookPage' .. n, rail)
        e.lit = sheen(e, 'BACKGROUND', 0, C.ember, 0.28)
        e.lit:SetAllPoints(e)
        e.hl = sheen(e, 'HIGHLIGHT', 0, C.gold, 0.12)
        e.hl:SetAllPoints(e)
        e.mark = solid(e, 'ARTWORK', 1, C.gold, 1)
        e.mark:SetWidth(3)
        e.mark:SetPoint('TOPLEFT', e, 'TOPLEFT', 0, 0)
        e.mark:SetPoint('BOTTOMLEFT', e, 'BOTTOMLEFT', 0, 0)
        e.icon = Skin.Tex(e, nil, 'ARTWORK')
        e.icon:SetSize(20, 20)
        e.icon:SetPoint('LEFT', e, 'LEFT', 12, 0)
        e.text = Skin.String(e, 'BookBody', 'OVERLAY', C.dim)
        e.text:SetPoint('LEFT', e.icon, 'RIGHT', 10, 0)
        e.text:SetWidth(RAIL_W - 50)
        e.text:SetWordWrap(false)
        e:SetScript('OnClick', function(self)
          Book.Open(self.id)
          if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB or 841) end
        end)
        entries[n] = e
      end
      e.id, e.spec = spec.id, spec
      e:ClearAllPoints()
      e:SetPoint('TOPLEFT', rail, 'TOPLEFT', 0, y)
      e:SetSize(RAIL_W, ENTRY)
      e.icon:SetTexture(Skin.MEDIA .. spec.icon)
      e.text:SetText(spec.name)
      y = y - ENTRY - 2
    end
    e:Show()
  end
  Book.rail = list
  -- the version under the last entry (Nov 10, the owner's screenshot: pinned to the rail's foot, it sat on "Help" once
  -- the Talents page made the rail longer), and the window as tall as the rail and it need
  version:ClearAllPoints()
  version:SetPoint('TOPLEFT', rail, 'TOPLEFT', 6, y - 14)
  local need = TOP - y + 14 + 18 + FOOT
  local h = math.max(MIN_H, math.ceil(need))
  if h ~= H then
    H = h
    frame:SetHeight(H)
    frame.bars(W, H)
  end
  paintRail()
end

-- ----------------------------------------------------------------------------------------------------- scrolling
local function placeCanvas()
  local view = H - TOP - FOOT
  scroll = math.max(0, math.min(scroll, math.max(0, extent - view)))
  canvas:ClearAllPoints()
  canvas:SetPoint('TOPLEFT', body, 'TOPLEFT', 0, scroll)
  canvas:SetPoint('TOPRIGHT', body, 'TOPRIGHT', 0, scroll)
  canvas:SetHeight(math.max(extent, 1))
  local over = extent > view + 1
  bar:SetShown(over)
  if over then
    local th = math.max(30, view * view / extent)
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint('TOP', bar, 'TOP', 0, -(view - th) * scroll / (extent - view))
  end
end

function Book.Scroll(delta)
  scroll = scroll - delta * STEP
  placeCanvas()
end

-- ------------------------------------------------------------------------------------------------------ the frame
function Book.Short(t)
  return ns.Window and ns.Window.ShortTitle and ns.Window.ShortTitle(t) or t
end

function Book.Create()
  if frame then return frame end
  Skin.Fonts()
  frame = CreateFrame('Frame', 'BoFGuideBook', UIParent)
  frame:SetSize(W, H)
  frame:SetFrameStrata('DIALOG')
  frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 20)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag('LeftButton')
  frame:SetScript('OnDragStart', frame.StartMoving)
  frame:SetScript('OnDragStop', frame.StopMovingOrSizing)
  ns.Escapable(frame)
  -- the oath's frame, with a band of its painting across the top (the sky and the far peaks)
  Skin.Ornate(frame, { hero = HEAD, crop = { 0.16, 0.5 }, dusk = 30 })
  frame.bars(W, H)

  title = Skin.String(frame, 'BookDisplay', 'OVERLAY', C.gold)
  title:SetPoint('TOP', frame, 'TOP', 0, -54)
  title:SetJustifyH('CENTER')
  subtitle = Skin.String(frame, 'BookText', 'OVERLAY', C.text)
  subtitle:SetPoint('TOP', title, 'BOTTOM', 0, -6)
  subtitle:SetJustifyH('CENTER')
  subtitle:SetWidth(W - 200)

  local close = Skin.IconButton(frame, 22, 'btn-close', function() Book.Hide() end, 'BoFGuideBookClose', L.bookClose)
  close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -40, -38)

  -- the rail, on a darker well with a bronze line down its right side
  rail = CreateFrame('Frame', 'BoFGuideBookRail', frame)
  rail:SetPoint('TOPLEFT', frame, 'TOPLEFT', SIDE, -TOP)
  rail:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', SIDE, FOOT)
  rail:SetWidth(RAIL_W)
  local well = solid(frame, 'BACKGROUND', -4, C.well, 0.55)
  well:SetPoint('TOPLEFT', frame, 'TOPLEFT', SIDE - 6, -TOP + 8)
  well:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', SIDE - 6, FOOT - 8)
  well:SetWidth(RAIL_W + 12)
  local seam = solid(frame, 'ARTWORK', 0, C.frame, 0.9)
  seam:SetWidth(1)
  seam:SetPoint('TOPLEFT', well, 'TOPRIGHT', 0, 0)
  seam:SetPoint('BOTTOMLEFT', well, 'BOTTOMRIGHT', 0, 0)

  -- the page: clipped, scrolled by the mouse wheel; a thin bar on the right when it runs long
  body = CreateFrame('Frame', 'BoFGuideBookBody', frame)
  body:SetPoint('TOPLEFT', frame, 'TOPLEFT', BODY_L, -TOP)
  body:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -SIDE, FOOT)
  body:SetClipsChildren(true)
  body:EnableMouseWheel(true)
  body:SetScript('OnMouseWheel', function(_, d) Book.Scroll(d) end)
  canvas = CreateFrame('Frame', nil, body)
  canvas:SetPoint('TOPLEFT', body, 'TOPLEFT', 0, 0)
  canvas:SetPoint('TOPRIGHT', body, 'TOPRIGHT', 0, 0)
  canvas:SetHeight(10)
  bar = CreateFrame('Frame', nil, body)
  bar:SetPoint('TOPRIGHT', body, 'TOPRIGHT', 0, 0)
  bar:SetPoint('BOTTOMRIGHT', body, 'BOTTOMRIGHT', 0, 0)
  bar:SetWidth(4)
  local track = solid(bar, 'BACKGROUND', 0, C.line, 0.9)
  track:SetAllPoints(bar)
  thumb = solid(bar, 'ARTWORK', 0, C.goldSoft, 1)
  thumb:SetWidth(4)

  version = Skin.String(frame, 'BookSmall', 'OVERLAY', C.faint)
  version:SetWidth(RAIL_W - 12)
  version:SetText(L.bookVersion:format(ns.VERSION or ''))

  frame:Hide()
  return frame
end

--- lays the shown page out again from what's true now (after a pick, a setting, a level)
function Book.Refresh()
  if not frame then return end
  local spec
  for _, e in ipairs(Book.rail or {}) do if e.id == current then spec = e end end
  if not spec then current = 'leveling' return Book.Refresh() end
  title:SetText(ns.upper(spec.title or spec.name))
  subtitle:SetText(L.BOOK_SUB[current] or '')
  for id, p in pairs(built) do p.frame:SetShown(id == current) end
  local p = built[current]
  if not p then
    p = newPage(current)
    built[current] = p
  end
  p:begin()
  local bottom = PAGES[current](p, 0)
  extent = -bottom + 16
  p.frame:SetHeight(extent)
  placeCanvas()
  paintRail()
end

--- open the book at a page (default: the last one you looked at)
function Book.Open(id)
  Book.Create()
  if id and id ~= current then scroll = 0 end
  current = id or (ns.db and ns.db.bookPage) or current
  if ns.db then ns.db.bookPage = current end
  buildRail()
  frame:Show()
  Book.Refresh()
  -- (a high UI scale leaves few units to draw in: never taller than the screen)
  local room = (UIParent:GetHeight() or 768) * 0.94
  frame:SetScale(math.min(1, room / H))
end

function Book.Hide() if frame then frame:Hide() end end
function Book.Scrollable() return extent > (H - TOP - FOOT) + 1 end

--- the shown page's guide cards, in order (for tests and the bots): { name, sub, tag, chosen }
function Book.Cards()
  local p = built[current]
  local out = {}
  for i, b in ipairs(p and p.cards or {}) do
    out[i] = { name = b.o.name, sub = b.o.sub, tag = b.o.tag, chosen = b.o.chosen and true or false,
               switch = b.o.switch and b.o.switch.get() or nil }
  end
  return out
end

--- tick or untick the shown page's i-th card's switch, as the mouse would (a dungeon in your road: FB-053)
function Book.Switch(i)
  local p = built[current]
  local b = p and p.cards and p.cards[i]
  if b and b.sw and b.sw:IsShown() then b.sw:GetScript('OnClick')(b.sw) return true end
  return false
end

--- click the shown page's i-th guide card, as the mouse would
function Book.Click(i)
  local p = built[current]
  local b = p and p.cards and p.cards[i]
  if b then b:Click() end
end

--- the shown page's setting rows: { kind, name, on } (on: a tick box's state, or a choice's key)
function Book.Rows()
  local p = built[current]
  local out = {}
  for _, k in ipairs(p and p.parts or {}) do
    if k:IsShown() and k.name and k.name.GetText and k.kind ~= 'card' then
      local on
      if k.get then on = k.get() end
      if k.kind == 'toggle' then on = on and true or false end
      out[#out + 1] = { kind = k.kind, name = k.name:GetText(), on = on }
    end
  end
  return out
end

--- press a setting row by its name: a tick box flips, a choice takes `value` (its key), a slider moves to `value`,
--- an action's button is clicked
function Book.Press(name, value)
  local p = built[current]
  for _, k in ipairs(p and p.parts or {}) do
    if k:IsShown() and k.name and k.name.GetText and k.name:GetText() == name then
      if k.kind == 'toggle' then k:Click()
      elseif k.kind == 'choice' then
        for _, q in ipairs(k.plates) do if q:IsShown() and q.key == value then q:Click() end end
      elseif k.kind == 'slider' then k.s:SetValue(value)
      elseif k.kind == 'action' then k.go:Click()
      elseif k.kind == 'stepper' then (value == -1 and k.prev or k.next):Click() end
      return true
    end
  end
  error('no setting ' .. tostring(name))
end

--- click the shown page's card with this name (the first one)
function Book.ClickName(name)
  for i, c in ipairs(Book.Cards()) do if c.name == name then return Book.Click(i) end end
  error('no card ' .. tostring(name))
end
function Book.Shown() return frame and frame:IsShown() and current or nil end
function Book.Toggle(id) if Book.Shown() and (not id or id == current) then Book.Hide() else Book.Open(id) end end
