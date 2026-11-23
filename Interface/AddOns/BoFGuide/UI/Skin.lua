-- The look: Forged Relic, the same as bindonforever.com. Warm stone and dark bronze, ember and gold light, Cinzel
-- capitals over Inter. Restraint is the rule: ornament lives on the rivets, the clasp and the hairlines, and the game's
-- own colors (quest gold, quality, the green of a done objective) are never restyled.
--
-- Fonts ship in Media/Fonts (SIL Open Font License). Cinzel has no Cyrillic and neither has Korean or Chinese, so
-- those clients get Inter or the game's own font instead (settings.font = 'game' forces the game's fonts everywhere).
local _, ns = ...

local Skin = {}
ns.Skin = Skin
local MEDIA = 'Interface\\AddOns\\BoFGuide\\Media\\'
Skin.MEDIA = MEDIA

local function rgb(hex, a)
  return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, a or 1 }
end
-- the site's tokens (site/src/styles/global.css)
Skin.C = {
  bg = rgb('0b0907'), surface = rgb('17120d'), surface2 = rgb('201810'), well = rgb('0d0a07'),
  line = rgb('3a2c1c'), lineSoft = rgb('271d13'), frame = rgb('5c4429'), frameHi = rgb('b9883e'),
  -- dim and faint are lifted from the site's tokens (ab9c84, 8f806a): over a see-through background in the game
  -- world they faded out (owner, Oct 9). Same warm parchment family, three steps: text, dim, faint
  text = rgb('efe4cf'), dim = rgb('d6c8ad'), faint = rgb('bcab8e'),
  ember = rgb('e8964a'), gold = rgb('f0c35a'), goldSoft = rgb('b9883e'),
  questGold = rgb('ffd100'), green = rgb('1eff00'), red = rgb('ff4646'), danger = rgb('ff7359'),
  done = rgb('8ccf8c'), shadow = rgb('000000', 0.9), emberDeep = rgb('8a3a1a'),
}
--- a color as a |c escape
function Skin.Hex(c) return ('|cff%02x%02x%02x'):format(c[1] * 255, c[2] * 255, c[3] * 255) end

-- ----------------------------------------------------------------------------------------------------------- fonts
local FONT = { title = 'Cinzel-Bold.ttf', body = 'Inter-SemiBold.ttf', text = 'Inter-Regular.ttf',
  mono = 'JetBrainsMono-Regular.ttf' }   -- mono: a BattleTag to copy, where I and l must look apart (Oct 19)
-- name -> { kind, size, fixed }. Text drawn on painted art (the nameplate, a panel's tab, a button's plate, the done
-- plate) is `fixed`: the art doesn't grow with the Text size setting, so neither does its lettering (owner, Oct 9:
-- the title and the TARGETS tab overflowed their plates at 115%). tests/test_guide_fit.py measures every such label
-- with the real fonts at the largest text size.
local STYLES = {
  Title = { 'title', 11.5, true }, TitleS = { 'title', 10.5, true }, TitleXS = { 'title', 9.5, true },
  Tab = { 'title', 9, true }, Button = { 'title', 9.5, true }, Badge = { 'title', 15, true },
  ToastLabel = { 'title', 9, true }, ToastTitle = { 'title', 13.5, true },
  Heading = { 'title', 15 }, Label = { 'title', 10 }, Display = { 'title', 27 }, Vow = { 'title', 12.5 },
  Body = { 'body', 12.5 }, Text = { 'text', 11.5 }, Small = { 'text', 10.5 }, Number = { 'body', 13 },
  Big = { 'body', 15 }, Mono = { 'mono', 12 },
  -- the guide book (UI/Book.lua): its own sizes, fixed like the lettering on art. Its rows and cards are laid out to
  -- them; the game's UI scale makes the whole book bigger, the guide's Text size is for the guide window
  BookDisplay = { 'title', 27, true }, BookLabel = { 'title', 10, true }, BookBody = { 'body', 12.5, true },
  BookText = { 'text', 11.5, true }, BookSmall = { 'text', 10.5, true }, BookNumber = { 'body', 13, true },
}
Skin.Font = {}

local function fontFor(kind)
  if kind == 'mono' then return MEDIA .. 'Fonts\\' .. FONT.mono end   -- in every language and font setting
  local locale = GetLocale and GetLocale() or 'enUS'
  local game = (ns.settings and ns.settings.font == 'game') or locale == 'koKR' or locale == 'zhCN' or locale == 'zhTW'
  if game then
    -- one face for headings and text: the game's standard font. Never DAMAGE_TEXT_FONT: on a Korean client that is
    -- K_Damage, the brush face of the floating combat numbers, and headings in it beside body text in 2002 looked so
    -- mismatched that a Korean player couldn't use the guide (FB-063, Nov 12). On Western clients both are Friz Quadrata
    return STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
  end
  if kind == 'title' and locale == 'ruRU' then kind = 'body' end   -- Cinzel has no Cyrillic
  return MEDIA .. 'Fonts\\' .. FONT[kind]
end

--- (re)make the font objects; called at login and when the font setting changes
function Skin.Fonts()
  for name, spec in pairs(STYLES) do
    local f = Skin.Font[name] or CreateFont('BoFGuideFont' .. name)
    local size = spec[3] and spec[2] or spec[2] * ((ns.settings and ns.settings.textScale) or 1)
    -- SetFont on a font object returns nothing; what loaded is read back with GetFont (nil when the file didn't)
    f:SetFont(fontFor(spec[1]), size, '')
    if not f:GetFont() then f:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', size, '') end
    f:SetShadowColor(0, 0, 0, 0.85)
    f:SetShadowOffset(1, -1)
    Skin.Font[name] = f
  end
  return Skin.Font
end

--- a thin bronze line round a box's well: the well is nearly the panel's own color, so without it a paste box or a
--- link box read as an empty band (website session's preview check, Oct 19)
function Skin.Edge(parent, region)
  local c = Skin.C.goldSoft
  local function line(a1, a2, w, h)
    local t = parent:CreateTexture(nil, 'ARTWORK', nil, 1)
    t:SetColorTexture(c[1], c[2], c[3], 0.55)
    t:SetPoint(a1, region, a1, 0, 0)
    t:SetPoint(a2, region, a2, 0, 0)
    if w then t:SetWidth(w) else t:SetHeight(h) end
  end
  line('TOPLEFT', 'TOPRIGHT', nil, 1)
  line('BOTTOMLEFT', 'BOTTOMRIGHT', nil, 1)
  line('TOPLEFT', 'BOTTOMLEFT', 1, nil)
  line('TOPRIGHT', 'BOTTOMRIGHT', 1, nil)
end

--- a BattleTag shown to copy (owner's test, Oct 19: in Inter "lluminoctis" read as "Illuminoctis" and a copy was bound
--- to the wrong account): a read-only box in a monospace face where I, l and 1 differ; a click selects it all for Ctrl+C.
--- A tag with letters the mono face lacks (Hangul) uses the text face. box:SetTag(tag) fills it and sizes it.
function Skin.TagBox(parent, name)
  local box = CreateFrame('EditBox', name, parent)
  box:SetAutoFocus(false)
  box:SetHeight(24)
  box:SetTextInsets(8, 8, 0, 0)
  local well = box:CreateTexture(nil, 'BACKGROUND')
  well:SetAllPoints(box)
  well:SetColorTexture(Skin.C.well[1], Skin.C.well[2], Skin.C.well[3], 0.9)
  Skin.Edge(box, well)
  local measure = parent:CreateFontString(nil, 'OVERLAY')
  measure:Hide()
  box:SetScript('OnTextChanged', function(self, user)
    if user then self:SetText(self.tag or '') self:HighlightText() end
  end)
  box:SetScript('OnEditFocusGained', function(self) self:HighlightText() end)
  box:SetScript('OnEditFocusLost', function(self) self:HighlightText(0, 0) end)
  box:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
  box:SetScript('OnMouseUp', function(self) self:SetFocus() self:HighlightText() end)
  function box:SetTag(tag)
    self.tag = tag
    local font = (tag and tag:find('[\128-\255]')) and (Skin.Font.Text or Skin.Fonts().Text)
      or (Skin.Font.Mono or Skin.Fonts().Mono)
    self:SetFontObject(font)
    self:SetTextColor(Skin.C.gold[1], Skin.C.gold[2], Skin.C.gold[3], 1)
    measure:SetFontObject(font)
    measure:SetText(tag or '')
    self:SetWidth(math.max(120, (measure:GetStringWidth() or 0) + 24))
    self:SetText(tag or '')
    self:SetCursorPosition(0)
  end
  return box
end

--- a font string in one of our styles
-- Korean particles after a name the game fills in: the translation writes both forms, "사비스와(과)"; the guide
-- picks the one the name's last syllable takes (a final consonant: 과, 을, 이, 은, 으로; none: 와, 를, 가, 는, 로).
-- Names that end in a Latin letter or a digit keep both. (The QA pass, Oct 20: "와(과)" showed on every Talk to line.)
local PARTICLES = { { '와(과)', '과', '와' }, { '을(를)', '을', '를' }, { '이(가)', '이', '가' }, { '은(는)', '은', '는' },
                    { '(으)로', '으로', '로', rieul = true } }
local function lastSyllable(s, stop)
  local i = stop
  if s:sub(i - 1, i) == '|r' then i = i - 2 end     -- a colored name: "|cffffffff사비스|r와(과)"
  if i < 3 then return nil end
  local b1, b2, b3 = s:byte(i - 2, i)
  if not (b1 and b1 >= 0xEA and b1 <= 0xED) then return nil end
  local cp = (b1 % 16) * 4096 + (b2 % 64) * 64 + (b3 % 64)
  if cp < 0xAC00 or cp > 0xD7A3 then return nil end
  return (cp - 0xAC00) % 28                          -- 0: no final consonant; 8: ㄹ
end
function Skin.Particles(s)
  if type(s) ~= 'string' or not s:find('(', 1, true) then return s end
  for _, p in ipairs(PARTICLES) do
    local start = 1
    while true do
      local a, b = s:find(p[1], start, true)
      if not a then break end
      local fin = lastSyllable(s, a - 1)
      local pick
      if fin ~= nil then
        if p.rieul then pick = (fin == 0 or fin == 8) and p[3] or p[2] else pick = fin == 0 and p[3] or p[2] end
      end
      if pick then s = s:sub(1, a - 1) .. pick .. s:sub(b + 1) start = a + #pick else start = b + 1 end
    end
  end
  return s
end

function Skin.String(parent, style, layer, color)
  local fs = parent:CreateFontString(nil, layer or 'OVERLAY')
  fs:SetFontObject(Skin.Font[style] or Skin.Fonts()[style])
  local c = color or Skin.C.text
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  fs:SetJustifyH('LEFT')
  fs:SetJustifyV('TOP')
  fs:SetWordWrap(true)
  if ns.Lang and ns.Lang.Current and ns.Lang.Current() == 'koKR' then   -- (our own font string: its SetText, wrapped)
    local set = fs.SetText
    fs.SetText = function(self, t) return set(self, Skin.Particles(t)) end
  end
  return fs
end

-- -------------------------------------------------------------------------------------------------------- textures
function Skin.Tex(parent, file, layer, sub)
  local t = parent:CreateTexture(nil, layer or 'ARTWORK', nil, sub)
  if file then t:SetTexture(MEDIA .. file) end
  return t
end

local function solid(parent, layer, sub, c, a)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  t:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1)
  return t
end

--- frame a panel: stone, a darker fall toward the bottom, an ember glow from below, a bronze frame with a dark
--- channel and a lit inner hairline, and rivets on the top corners. Returns the parts (bg, frame, rivets) so callers
--- can fade or recolor them.
function Skin.Panel(f, opts)
  opts = opts or {}
  local C = Skin.C
  local p = {}
  p.bg = f:CreateTexture(nil, 'BACKGROUND', nil, -8)
  p.bg:SetTexture(MEDIA .. 'stone', 'REPEAT', 'REPEAT')   -- tiling needs the repeat wrap mode
  -- the painted bars sit inside their textures (measured in Media/frame-*.tga, out of 44: the bronze starts 5 in at
  -- the top and left, 14 and 15 in at the bottom and right). The stone and its shade stop under the bronze, so no
  -- dark strip shows past the frame's outer edge on bright ground (owner, Oct 9)
  local k = (opts.corner or 22) / 44
  -- the bronze art's right and bottom bars sit 9 and 8 (of 44) further in than its left and top ones, so the right
  -- column and the bottom row are moved out by that much and the frame reads the same on all four sides (owner,
  -- Oct 17: "out of whack on the right hand side"; the card ran into the right bar, Hardcore's corners sat off it)
  local dx, dy = 9 * k, -8 * k
  local il, it, ir, ib = (5 + 3) * k, (5 + 3) * k, (15 - 9 + 3) * k, (14 - 8 + 3) * k
  p.bg:SetPoint('TOPLEFT', f, 'TOPLEFT', il, -it)
  p.bg:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -ir, ib)
  p.bg:SetHorizTile(true)
  p.bg:SetVertTile(true)
  p.shade = solid(f, 'BACKGROUND', -7, C.bg, 1)
  p.shade:SetPoint('TOPLEFT', f, 'TOPLEFT', il, -it)
  p.shade:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -ir, ib)
  if p.shade.SetGradient and CreateColor then
    p.shade:SetColorTexture(1, 1, 1, 1)
    p.shade:SetGradient('VERTICAL', CreateColor(0.02, 0.015, 0.01, 0.55), CreateColor(0.09, 0.07, 0.05, 0.0))
  else
    p.shade:SetAlpha(0.3)
  end
  if opts.glow ~= false then
    p.glow = Skin.Tex(f, 'glow', 'BACKGROUND', -6)
    p.glow:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', il, ib)
    p.glow:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -ir, ib)
    p.glow:SetHeight(opts.glowHeight or 60)
    p.glow:SetTexCoord(0, 1, 0.5, 1)
    p.glow:SetAlpha(0.16)
  end
  -- the painted frame (guides/art/guide-frame-1.png): four corners kept as drawn, four bars that stretch
  local cs = opts.corner or 22
  p.corners, p.edges = {}, {}
  for i, k in ipairs({ 'tl', 'tr', 'bl', 'br' }) do
    local t = Skin.Tex(f, 'frame-' .. k, 'OVERLAY', 5)
    t:SetSize(cs, cs)
    p.corners[i] = t
  end
  -- the bars hang off the frame itself (not the corners), so either set of corners can sit where its art needs
  local top = Skin.Tex(f, 'frame-t', 'OVERLAY', 4)
  top:SetPoint('TOPLEFT', f, 'TOPLEFT', cs, 0)
  top:SetPoint('TOPRIGHT', f, 'TOPRIGHT', dx - cs, 0)
  top:SetHeight(cs)
  local bottom = Skin.Tex(f, 'frame-b', 'OVERLAY', 4)
  bottom:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', cs, dy)
  bottom:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', dx - cs, dy)
  bottom:SetHeight(cs)
  p.edges[1], p.edges[2] = top, bottom
  local l = Skin.Tex(f, 'frame-l', 'OVERLAY', 4)
  l:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -cs)
  l:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 0, cs + dy)
  l:SetWidth(cs)
  local r = Skin.Tex(f, 'frame-r', 'OVERLAY', 4)
  r:SetPoint('TOPRIGHT', f, 'TOPRIGHT', dx, -cs)
  r:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', dx, cs + dy)
  r:SetWidth(cs)
  p.edges[3], p.edges[4] = l, r
  -- the bronze corners follow the bars; Hardcore's iron ones are drawn even on every side and keep the frame's corners
  function p.place(hc)
    local x, y = hc and 0 or dx, hc and 0 or dy
    local c = p.corners
    c[1]:ClearAllPoints() c[1]:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, 0)
    c[2]:ClearAllPoints() c[2]:SetPoint('TOPRIGHT', f, 'TOPRIGHT', x, 0)
    c[3]:ClearAllPoints() c[3]:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 0, y)
    c[4]:ClearAllPoints() c[4]:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', x, y)
  end
  p.place(false)
  return p
end

--- Hardcore's iron corners and darker bars, or back to bronze
function Skin.Hardcore(p, hc)
  for i, k in ipairs({ 'tl', 'tr', 'bl', 'br' }) do
    p.corners[i]:SetTexture(Skin.MEDIA .. (hc and 'frame-hc-' or 'frame-') .. k)
  end
  if p.place then p.place(hc) end
  for _, e in ipairs(p.edges) do
    if hc then e:SetVertexColor(0.62, 0.5, 0.46) else e:SetVertexColor(1, 1, 1) end
  end
  if p.glow then p.glow:SetAlpha(hc and 0.32 or 0.16) end
end

--- a horizontal painted piece in three parts (name-l, name-m, name-r): the ends keep their shape, the middle stretches
function Skin.ThreeSlice(parent, name, height, capWidth, layer, sub)
  local t = {}
  t.l = Skin.Tex(parent, name .. '-l', layer or 'ARTWORK', sub)
  t.m = Skin.Tex(parent, name .. '-m', layer or 'ARTWORK', sub)
  t.r = Skin.Tex(parent, name .. '-r', layer or 'ARTWORK', sub)
  t.l:SetSize(capWidth, height)
  t.r:SetSize(capWidth, height)
  t.m:SetHeight(height)
  t.m:SetPoint('TOPLEFT', t.l, 'TOPRIGHT', 0, 0)
  t.m:SetPoint('TOPRIGHT', t.r, 'TOPLEFT', 0, 0)
  function t:Place(rel, x1, x2, y)
    self.l:ClearAllPoints()
    self.r:ClearAllPoints()
    self.l:SetPoint('TOPLEFT', rel, 'TOPLEFT', x1, y)
    self.r:SetPoint('TOPRIGHT', rel, 'TOPRIGHT', x2, y)
  end
  function t:SetShown(v) self.l:SetShown(v) self.m:SetShown(v) self.r:SetShown(v) end
  return t
end

-- ----------------------------------------------------------------------------------------- the ornate frame
local CORNER, BAR, CREST_W, CREST_H = 140, 24, 172, 60   -- half the painted sheet's size
--- the ornate frame, cut from one painted sheet (guides/art/setup-frame-1.png) so it keeps its shape at any height
function Skin.Ornate(f, opts)
  opts = opts or {}
  local HERO_H = opts.hero or 300
  local C = Skin.C
  local bg = f:CreateTexture(nil, 'BACKGROUND', nil, -8)
  bg:SetTexture(MEDIA .. 'stone', 'REPEAT', 'REPEAT')
  bg:SetPoint('TOPLEFT', f, 'TOPLEFT', 8, -8)
  bg:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -8, 8)
  bg:SetHorizTile(true)
  bg:SetVertTile(true)
  local shade = f:CreateTexture(nil, 'BACKGROUND', nil, -7)
  shade:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.93)
  shade:SetAllPoints(bg)
  local hero = Skin.Tex(f, 'setup-hero', 'BACKGROUND', -6)
  hero:SetPoint('TOPLEFT', f, 'TOPLEFT', 8, -8)
  hero:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -8, -8)
  hero:SetHeight(HERO_H)
  if opts.crop then hero:SetTexCoord(0, 1, opts.crop[1], opts.crop[2]) end
  -- the painting's foot darkens behind the title, so the words read on the road
  local dusk = f:CreateTexture(nil, 'BACKGROUND', nil, -5)
  dusk:SetColorTexture(1, 1, 1, 1)
  local duskTop = opts.dusk or 70
  dusk:SetPoint('TOPLEFT', f, 'TOPLEFT', 8, -duskTop)
  dusk:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -8, -duskTop)
  dusk:SetHeight(HERO_H + 8 - duskTop)
  if dusk.SetGradient and CreateColor then
    dusk:SetGradient('VERTICAL', CreateColor(0.03, 0.025, 0.02, 0.86), CreateColor(0.03, 0.025, 0.02, 0))
  else
    dusk:SetAlpha(0)
  end
  local glow = Skin.Tex(f, 'glow', 'BACKGROUND', -5)
  glow:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 10, 10)
  glow:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -10, 10)
  glow:SetHeight(90)
  glow:SetTexCoord(0, 1, 0.5, 1)
  glow:SetAlpha(0.1)

  local function piece(file, sub) return Skin.Tex(f, file, 'OVERLAY', sub or 4) end
  local run = CORNER - 26       -- how far along a bar a corner's art reaches
  local top = piece('setup-t')
  top:SetPoint('TOPLEFT', f, 'TOPLEFT', run, 0)
  top:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -run, 0)
  top:SetHeight(BAR)
  local bottom = piece('setup-b')
  bottom:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', run, 0)
  bottom:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -run, 0)
  bottom:SetHeight(BAR - 3)
  local left = piece('setup-l')
  left:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, -run)
  left:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 0, run)
  left:SetWidth(BAR)
  local right = piece('setup-r')
  right:SetPoint('TOPRIGHT', f, 'TOPRIGHT', 0, -run)
  right:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', 0, run)
  right:SetWidth(BAR)
  --- the bars show as much of their long strip as they need: it repeats, it never smears
  function f.bars(w, h)
    top:SetTexCoord(0, (w - 2 * run) / 1024, 0, 1)
    bottom:SetTexCoord(0, (w - 2 * run) / 1024, 0, 1)
    left:SetTexCoord(0, 1, 0, (h - 2 * run) / 1024)
    right:SetTexCoord(0, 1, 0, (h - 2 * run) / 1024)
  end
  -- (the corners reach past the window's edge: the bars run along it, and the ornament stands proud)
  for _, c in ipairs({ { 'setup-tl', 'TOPLEFT', -14, 16 }, { 'setup-tr', 'TOPRIGHT', 15, 16 },
                       { 'setup-bl', 'BOTTOMLEFT', -14, -17 }, { 'setup-br', 'BOTTOMRIGHT', 15, -17 } }) do
    local t = piece(c[1], 5)
    t:SetSize(CORNER, CORNER)
    t:SetPoint(c[2], f, c[2], c[3], c[4])
  end
  local crest = piece('setup-crest', 5)
  crest:SetSize(CREST_W, CREST_H)
  crest:SetPoint('TOP', f, 'TOP', 0, 15)
  local foot = piece('setup-crest-b', 5)
  foot:SetSize(114, 41)
  foot:SetPoint('BOTTOM', f, 'BOTTOM', 0, -9)
  -- the guide's seal, set in the crest's shield
  f.seal = piece('seal', 6)
  f.seal:SetSize(38, 38)
  f.seal:SetPoint('CENTER', crest, 'CENTER', 0, 1)
end


--- a square painted button (btn-close, btn-collapse, btn-settings, btn-lock) that lights up under the mouse
--- a tooltip in one style everywhere: the first line is the title (gold), the rest plain text. `lines` is a string,
--- a list (an entry may be { text, r, g, b } for a colored line) or a function returning either.
function Skin.Tooltip(owner, lines, anchor)
  if not GameTooltip or not lines then return end
  if type(lines) == 'function' then lines = lines(owner) end
  if type(lines) == 'string' then lines = { lines } end
  if type(lines) ~= 'table' or #lines == 0 then return end
  GameTooltip:SetOwner(owner, anchor or 'ANCHOR_TOP')
  for i, t in ipairs(lines) do
    if type(t) == 'table' then GameTooltip:AddLine(t[1], t[2] or 0.85, t[3] or 0.85, t[4] or 0.85, true)
    elseif i == 1 then GameTooltip:AddLine(t, 1, 0.82, 0.35, true)
    else GameTooltip:AddLine(t, 0.85, 0.85, 0.85, true) end
  end
  GameTooltip:Show()
end

function Skin.IconButton(parent, size, tex, onClick, name, tipText)
  local b = CreateFrame('Button', name, parent)
  b:SetSize(size, size)
  b.icon = Skin.Tex(b, tex, 'ARTWORK')
  b.icon:SetAllPoints(b)
  b.hl = Skin.Tex(b, 'glow', 'HIGHLIGHT')
  b.hl:SetPoint('CENTER', b, 'CENTER', 0, 0)
  b.hl:SetSize(size * 1.8, size * 1.8)
  b.hl:SetBlendMode('ADD')
  b.hl:SetAlpha(0.45)
  b.tip = tipText
  b:SetScript('OnEnter', function(self) Skin.Tooltip(self, self.tip) end)
  b:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  if onClick then b:SetScript('OnClick', onClick) end
  return b
end

--- a hairline across a frame (fades out at both ends), optionally with the clasp in the middle
function Skin.Hairline(parent, clasp)
  local C = Skin.C
  local h = CreateFrame('Frame', nil, parent)
  h:SetHeight(clasp and 14 or 1)
  local left, right = solid(h, 'ARTWORK', 0, C.frameHi, 1), solid(h, 'ARTWORK', 0, C.frameHi, 1)
  left:SetHeight(1)
  right:SetHeight(1)
  left:SetPoint('LEFT', h, 'LEFT', 0, 0)
  left:SetPoint('RIGHT', h, 'CENTER', clasp and -16 or 0, 0)
  right:SetPoint('LEFT', h, 'CENTER', clasp and 16 or 0, 0)
  right:SetPoint('RIGHT', h, 'RIGHT', 0, 0)
  if left.SetGradient and CreateColor then
    local g = C.frameHi
    left:SetColorTexture(1, 1, 1, 1)
    right:SetColorTexture(1, 1, 1, 1)
    left:SetGradient('HORIZONTAL', CreateColor(g[1], g[2], g[3], 0), CreateColor(g[1], g[2], g[3], 0.6))
    right:SetGradient('HORIZONTAL', CreateColor(g[1], g[2], g[3], 0.6), CreateColor(g[1], g[2], g[3], 0))
  end
  if clasp then
    h.clasp = Skin.Tex(h, 'clasp', 'OVERLAY')
    h.clasp:SetSize(36, 18)
    h.clasp:SetPoint('CENTER', h, 'CENTER', 0, 0)
  end
  return h
end

--- a small bronze-framed button with a Cinzel label (or a glyph). b.tip is its tooltip (see Skin.Tooltip); b.restyle,
--- when set, runs after every press and hover so a switch can keep showing its own state.
-- a button's plate, in three pieces (scripts/guide_assets.py): the ends keep their painted shape at any height and only the
-- middle runs, so the rivets stay round (owner, Oct 31: one picture stretched to 7:1 squashed them). As shares of the plate's
-- height: the painted glow round it, and of the whole piece's height: an end's width and the middle's length
local PLATE_GLOW, PLATE_CAP, PLATE_RUN = 6 / 190, 18 / 64, 8
local SIDES = { 'l', 'm', 'r' }

--- the three pieces, answering like one texture: SetTexture takes the plate's name
local function plateOf(b)
  local bg = {}
  for _, side in ipairs(SIDES) do bg[side] = Skin.Tex(b, 'btn-plate-' .. side, 'BACKGROUND') end
  function bg:SetTexture(file) for _, side in ipairs(SIDES) do self[side]:SetTexture(file .. '-' .. side) end end
  function bg:SetDesaturated(v) for _, side in ipairs(SIDES) do self[side]:SetDesaturated(v) end end
  function bg:SetVertexColor(r, g, b2) for _, side in ipairs(SIDES) do self[side]:SetVertexColor(r, g, b2) end end
  return bg
end

--- the pieces on the button: the middle shows as much of its strip as it has room for, so its grain isn't squeezed
local function fitPlate(b)
  local bg, w, h = b.bg, b:GetWidth(), b:GetHeight()
  local glow = h * PLATE_GLOW
  local tall = h + 2 * glow
  local cap = tall * PLATE_CAP
  bg.l:ClearAllPoints()
  bg.l:SetPoint('TOPLEFT', b, 'TOPLEFT', -glow, glow)
  bg.l:SetPoint('BOTTOMLEFT', b, 'BOTTOMLEFT', -glow, -glow)
  bg.l:SetWidth(cap)
  bg.r:ClearAllPoints()
  bg.r:SetPoint('TOPRIGHT', b, 'TOPRIGHT', glow, glow)
  bg.r:SetPoint('BOTTOMRIGHT', b, 'BOTTOMRIGHT', glow, -glow)
  bg.r:SetWidth(cap)
  bg.m:ClearAllPoints()
  bg.m:SetPoint('TOPLEFT', bg.l, 'TOPRIGHT', 0, 0)
  bg.m:SetPoint('BOTTOMRIGHT', bg.r, 'BOTTOMLEFT', 0, 0)
  bg.m:SetTexCoord(0, math.max(0.01, math.min(1, (w + 2 * glow - 2 * cap) / tall / PLATE_RUN)), 0, 1)
end

function Skin.Button(parent, w, h, label, onClick, name)
  local C = Skin.C
  local b = CreateFrame('Button', name, parent)
  b.bg = plateOf(b)
  b:SetScript('OnSizeChanged', fitPlate)
  b:SetSize(w, h)
  fitPlate(b)
  b.edge = {}
  b.text = Skin.String(b, 'Button', 'OVERLAY', C.gold)
  b.text:SetPoint('CENTER', b, 'CENTER', 0, 0)
  b.text:SetJustifyH('CENTER')
  b.text:SetJustifyV('MIDDLE')
  b.text:SetText(label or '')
  local function plate(self, file, hover)
    self.bg:SetTexture(Skin.MEDIA .. file)
    if self.restyle then self:restyle(hover) end
  end
  b:SetScript('OnMouseDown', function(self) plate(self, 'btn-plate-down', true) end)
  b:SetScript('OnMouseUp', function(self) plate(self, 'btn-plate-hover', true) end)
  b:SetScript('OnEnter', function(self)
    plate(self, 'btn-plate-hover', true)
    Skin.Tooltip(self, self.tip)
  end)
  b:SetScript('OnLeave', function(self)
    plate(self, self.selected and 'btn-plate-hover' or 'btn-plate', false)
    if GameTooltip then GameTooltip:Hide() end
  end)
  if onClick then b:SetScript('OnClick', onClick) end
  return b
end

--- one of a row of choices (a language, a kind of feedback): the chosen one lit, gold; the rest plain and dimmer
--- (the QA pass, Oct 20: gold text alone on an identical plate didn't read as chosen)
function Skin.Choose(b, on)
  b.selected = on and true or false
  b.bg:SetTexture(Skin.MEDIA .. (on and 'btn-plate-hover' or 'btn-plate'))
  b.text:SetTextColor(unpack(on and Skin.C.gold or Skin.C.dim))
  b:SetAlpha(on and 1 or 0.6)
end

--- the icon for a step: the painted medallions (guides/art), and the site's map pins for the kinds with no
--- medallion yet (accept, turn-in, flights, inn, trainer, vendor, dungeon)
Skin.ICON = {
  accept = 'pin-quest', turnin = 'pin-turnin', complete = 'pin-quest', kill = 'med-kill', collect = 'med-collect',
  ['goto'] = 'med-goto', fp = 'pin-flight', fly = 'pin-flight', hearth = 'med-hearth', sethome = 'pin-inn',
  vendor = 'pin-vendor', train = 'pin-trainer', learn = 'pin-trainer', rank = 'pin-trainer', camp = 'med-camp',
  xp = 'med-xp', skill = 'med-craft', use = 'med-use', boss = 'med-boss', enter = 'pin-dungeon',
  dungeon = 'pin-dungeon', craft = 'med-craft', gather = 'med-gather', skin = 'med-gather', fish = 'med-fish',
}
Skin.PIN = Skin.ICON
function Skin.PinFor(step)
  return Skin.MEDIA .. (Skin.ICON[step.o] or 'med-goto')
end
--- the game's own icons for each line of a stop (the gossip marks players know)
Skin.GAME = {
  accept = 'Interface\\GossipFrame\\AvailableQuestIcon', turnin = 'Interface\\GossipFrame\\ActiveQuestIcon',
  notready = 'Interface\\GossipFrame\\IncompleteQuestIcon', vendor = 'Interface\\GossipFrame\\VendorGossipIcon',
  train = 'Interface\\GossipFrame\\TrainerGossipIcon', fp = 'Interface\\GossipFrame\\TaxiGossipIcon',
  fly = 'Interface\\GossipFrame\\TaxiGossipIcon', sethome = 'Interface\\MINIMAP\\TRACKING\\Innkeeper',
  talk = 'Interface\\GossipFrame\\GossipGossipIcon',
}
--- the mark beside a warning or a tip, by kind
Skin.MARK = { group = 'med-group', elite = 'med-boss', level = 'med-watch', danger = 'med-danger', tip = 'med-story',
             where = 'med-goto', use = 'med-use', ask = 'med-story' }
