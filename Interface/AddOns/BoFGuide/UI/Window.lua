-- The guide window, in the Forged Relic look (UI/Skin.lua).
--   header:  the seal (click for the menu), the route's name, your level against the plan (a profession guide: your
--            skill and its cap), the AUTO switch, collapse and close; under it the route's progress.
--   now:     the current step as a raised card: its pin, what to do, who and where (with the distance and the way
--            to go), the live objectives with counts and bars, warnings (always shown) and the route's tips.
--   also:    other steps you can do right here, and the ones you carry along, as smaller cards.
--   next:    the next few steps, one line each.
-- Click a step to point the arrow at it, right-click for its menu, shift-click to mark it done; the » on a card
-- skips it. Collapsed, the window keeps the header and the current step only. Our own frames only.
local _, ns = ...

local Window = {}
ns.Window = Window
local L = ns.L
local Skin = ns.Skin
local C = Skin.C
local PAD, HEAD_H, ICON, ICON_S, ROW_H = 12, 94, 30, 20, 20
local MAX_CARDS, OBJ_BAR = 4, 3

local frame, seal, title, sub, autoBtn, backBtnReturn, gearBtn, collapseBtn, closeBtn, rule, message, nextLabel, finishBtn, haveBtn
local cards, rows = {}, {}
local shown = {}   -- what's on screen, in order: { key, text, detail, kind }

local function width() return ns.settings.width or 340 end

local function savePosition()
  local point, _, rel, x, y = frame:GetPoint()
  if point then ns.db.frames.main = { point, rel, x, y } end
end

--- the window hangs from its top-left corner, so a taller or shorter window grows and shrinks downward and the top
--- stays put (FB-072, Nov 14: held by its middle, a new install's spot, or by its bottom, where the game anchors a
--- window let go low on the screen, its top jumped with every card). Not in a fight: the panels' secure buttons hang
--- from it
local function holdTop()
  if not frame or (InCombatLockdown and InCombatLockdown()) then return false end
  local point, _, rel = frame:GetPoint()
  if point == 'TOPLEFT' and rel == 'BOTTOMLEFT' then return false end
  local l, t = frame:GetLeft(), frame:GetTop()
  if not (l and t) then return false end
  frame:ClearAllPoints()
  frame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', l, t)
  return true
end

local function setHeight(h)
  holdTop()
  frame:SetHeight(h)
end

local function tip(owner, lines) Skin.Tooltip(owner, lines, 'ANCHOR_LEFT') end

-- where a new install opens (no saved spot): of the places players expect a guide, the one that covers least of the
-- game's own frames on this screen (the competitor pass, Oct 24: the old fixed spot opened over the quest tracker,
-- where Questie's tracker sits too, and no fixed spot fits every UI scale). Only read, never moved: the game's frames.
local SPOTS = { { 'RIGHT', 'RIGHT', -40, 60 }, { 'LEFT', 'LEFT', 40, 35 }, { 'TOPLEFT', 'TOPLEFT', 40, -130 } }
local GAME_FRAMES = { 'ChatFrame1', 'PlayerFrame', 'TargetFrame', 'MinimapCluster' }
local TALL = 460      -- the window with its lead card and next steps, before the first draw has sized it

local function rectOf(f)
  local l, b, r, t = f:GetLeft(), f:GetBottom(), f:GetRight(), f:GetTop()
  if not (l and b and r and t) then return nil end
  local s = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  return { l * s, b * s, r * s, t * s }
end

--- the spot for a new install: { point, relativePoint, x, y }
function Window.FirstSpot()
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local s = ns.settings.scale or 1
  local ww, hh = width() * s, math.max(frame and frame:GetHeight() or 0, TALL) * s
  local taken = {}
  for _, name in ipairs(GAME_FRAMES) do
    local f = rawget(_G, name)
    local r = f and f.IsShown and f:IsShown() and rectOf(f)
    if r then taken[#taken + 1] = r end
  end
  -- the quest tracker's column counts even when an addon hid it (Questie puts its own tracker there); where it isn't
  -- placed, Blizzard's default spot (Edit Mode: 110 in from the right, 275 down, about 40% of the screen tall)
  local ot = rawget(_G, 'ObjectiveTrackerFrame')
  taken[#taken + 1] = (ot and rectOf(ot)) or { W - 370, H - 275 - 0.4 * H, W - 110, H - 275 }
  local best, least
  for _, sp in ipairs(SPOTS) do
    local x, y = sp[3] * s, sp[4] * s
    local l = sp[1] == 'RIGHT' and (W + x - ww) or x
    local b = sp[1] == 'TOPLEFT' and (H + y - hh) or (H / 2 + y - hh / 2)
    local r, t = l + ww, b + hh
    -- what it covers, and whatever would hang off the screen counts as covered too
    local cover = ww * hh - math.max(0, math.min(r, W) - math.max(l, 0)) * math.max(0, math.min(t, H) - math.max(b, 0))
    for _, g in ipairs(taken) do
      cover = cover + math.max(0, math.min(r, g[3]) - math.max(l, g[1])) * math.max(0, math.min(t, g[4]) - math.max(b, g[2]))
    end
    if not least or cover < least then best, least = sp, cover end
  end
  return best
end

--- how tall a font string's text is at its width. The game wraps text only for a region that is shown and placed;
--- one that isn't placed yet measures a wrapped line as a single line, and whatever is drawn under it overlaps
--- (Oct 9: "Accept Aggressive Encroachment" over the quest's own words). So: place it, show it, then measure.
-- every height measured in a draw: the game can measure a font string's new text by the old text's lines until the
-- next frame (Skyborne testers, Oct 11: Among the Faithful's three-line text was measured as two, and its objective
-- sat on the third line). The frame after a draw measures again and draws once more if a line grew
local measured = {}
local function heightOf(fs, fallback)
  fs:Show()
  local h = fs:GetStringHeight() or fallback or 12
  fs.bofH = h
  measured[#measured + 1] = fs
  return h
end
local function plain(t) return t and (t:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')) or nil end
local function untip() if GameTooltip then GameTooltip:Hide() end end

-- ------------------------------------------------------------------------------------------------------ the menus
local function stepMenu(owner, key)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateButton(L.menuFocus, function() ns.Engine.Focus(key) end)
    local map = ns.Engine.MapOf and ns.Engine.MapOf(key)
    if map then root:CreateButton(L.menuShowMap, function() ns.Waypoint.ShowOnMap(map) end) end
    root:CreateButton(L.menuSkip, function() ns.Engine.Click(key, 'LeftButton', false) end)
    root:CreateButton(L.menuDone, function() ns.Engine.Click(key, 'LeftButton', true) end)
    if ns.cdb and ns.cdb.skip[key] then
      root:CreateButton(L.menuBack, function() ns.Engine.Click(key, 'RightButton', false) end)
    end
    root:CreateButton(L.menuJump, function() ns.Engine.JumpTo(key) end)
    if ns.cdb and ns.cdb.jump then root:CreateButton(L.menuUndoJump, function() ns.Engine.UndoJump() end) end
    root:CreateDivider()
    if owner.asks then
      root:CreateButton(L.menuAnswer, function() ns.Feedback.Show('other', key, L.askWords .. ' ') end)
    end
    local q = ns.Engine.ShareableQuest and ns.Engine.ShareableQuest(key)
    if q then root:CreateButton(L.menuShare, function() ns.Engine.ShareQuest(q) end) end
    root:CreateButton(L.menuReportStep, function() ns.Feedback.Show('step', key) end)
  end)
end

-- the seal's menu (owner, Nov 10: short, with the guide book for the rest): where you are, the book's two doors, this
-- step's back-and-forth, the quick switches, the tools, and the full guide. Every guide and every setting lives in the
-- book (UI/Book.lua); the long route lists and settings submenus that grew here since October moved there
function Window.Menu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle('Bind on Forever Guide')
    -- a dungeon, profession or Legacy guide on screen: the leveling route is one click away (items[2], kept first)
    local cur, lev = ns.Engine.Route(), ns.Engine.Leveling()
    if cur and cur.kd and lev and lev ~= cur then
      root:CreateButton(L.menuToLeveling:format(Window.ShortTitle(lev.title or lev.id)), function() ns.Engine.SetRoute(lev.id) end)
    end
    -- the book: its guides page for what's on screen, and its settings
    local page = cur and (cur.kd == 'dungeon' and 'dungeons' or cur.kd == 'profession' and 'professions'
      or cur.kd == 'legacy' and 'legacy') or 'leveling'
    -- (FB-051, Nov 11: a player missed picking the kind of guide at the seal. Hovering "Guides..." lists the
    -- book's guide pages, one click each; the click on "Guides..." itself still opens the book)
    local guides = root:CreateButton(L.menuGuides, function() ns.Book.Open(page) end)
    local doors = { { 'leveling', L.bookLeveling }, { 'dungeons', L.bookDungeons },
                    { 'professions', L.bookProfessions }, { 'legacy', L.bookLegacy } }
    if ns.Talents and ns.Talents.Enabled and ns.Talents.Enabled() then doors[#doors + 1] = { 'talents', L.bookTalents } end
    for _, d in ipairs(doors) do
      local id = d[1]
      guides:CreateButton(d[2], function() ns.Book.Open(id) end)
    end
    root:CreateButton(L.menuSettings, function() ns.Book.Open('questing') end)
    root:CreateButton(L.menuTour, function() ns.Tour.Start() end)   -- (owner, Nov 13: how the guide works)
    -- this step: looking back and forth, and what you skipped
    local ended = ns.Engine.FreeEnded and ns.Engine.FreeEnded()
    root:CreateDivider()
    if not ended then root:CreateButton(L.menuLookBack, function() ns.safecall('back', ns.Engine.Back) end) end
    if ns.Engine.Peeking() then
      root:CreateButton(L.menuForward, function() ns.safecall('forward', ns.Engine.Forward) end)
      root:CreateButton(L.menuResume, function() ns.safecall('resume', ns.Engine.Resume) end)
    end
    if ns.Engine.LastSkipped() then
      root:CreateButton(L.menuUnskip, function() ns.safecall('unskip', ns.Engine.UnskipLast) end)
    end
    -- the quick switches: what you reach for while you play
    root:CreateDivider()
    local auto = root:CreateButton(L.menuAuto)
    for _, k in ipairs({ 'accept', 'turnin', 'gossip', 'taxi' }) do
      auto:CreateCheckbox(L.AUTO[k], function() return ns.settings.auto[k] end,
        function() ns.settings.auto[k] = not ns.settings.auto[k] Window.Header() end)
    end
    root:CreateCheckbox(L.menuArrow, function() return ns.settings.arrow ~= false end,
      function() ns.Arrow.Enable(ns.settings.arrow == false) end)
    root:CreateCheckbox(L.menuLock, function() return ns.settings.locked end,
      function() ns.settings.locked = not ns.settings.locked end)
    -- tools
    root:CreateDivider()
    root:CreateButton(L.optCleanup, function() ns.safecall('cleanup', ns.Cleanup.Ask) end)
    root:CreateButton(L.menuReport, function() ns.safecall('levellog', ns.LevelLog.Say) end)
    root:CreateButton(L.menuFeedback, function() ns.Feedback.Show('bug') end)
    -- the full guide: where it is, quietly, not for someone who has it; and adding the one you bought
    root:CreateDivider()
    if not ns.Link.HasFullGuide() then root:CreateButton(L.menuFullGuide, function() ns.Link.FullGuide() end) end
    root:CreateButton(L.menuImport, function() ns.Import.Show() end)
  end)
end

-- ------------------------------------------------------------------------------------------------------- the frame
-- the header: the nameplate across the top (guides/art/guide-header-1.png) holds the seal and the route's name; under
-- it one row with your pace (your level against the level the route expects here) on the left and the switches on
-- the right; then the clasp
-- (the plate is cut tight to the painting since Oct 10: 34 high, its dark band about 23, the seal's middle at -30)
local PLATE_H, PLATE_Y, ROW_Y, ROW_H, RULE_Y = 34, -13, -57, 20, -84
local TITLE_LEFT, TITLE_RIGHT = 9 + 40 + 6, 40   -- the seal on the left, the plate's curl on the right

--- the route's name for the header: without a closing parenthesis (the full name is in the seal's tooltip)
function Window.ShortTitle(t)
  t = t or ''
  -- (plain spaces, not %s: Lua's %s can take the last byte of a Korean syllable, 0x85 or 0xA0, for a space under some
  -- C locales, and cut the name mid-letter; Nov 10, the Korean preview of "연금술 1-225")
  local short = t:gsub(' *%b() *$', '')
  return short ~= '' and short or t
end

--- the name on the plate: the title font, stepping down a size or two before the game cuts it short
local function setTitle(text)
  local room = width() - TITLE_LEFT - TITLE_RIGHT
  for _, style in ipairs({ 'Title', 'TitleS', 'TitleXS' }) do
    title:SetFontObject(Skin.Font[style])
    title:SetText(text)
    if (title:GetStringWidth() or 0) <= room then return end
  end
end

function Window.Create()
  if frame then return frame end
  Skin.Fonts()
  local s = ns.settings
  frame = CreateFrame('Frame', 'BoFGuideFrame', UIParent)
  frame:SetSize(width(), TALL)   -- (the first spot is worked out for a window this tall; it hangs from its top after)
  frame:SetFrameStrata('MEDIUM')
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag('LeftButton')
  -- not in combat: the panels' secure buttons hang under this window (from their dock, Panels.Dock), and the game
  -- locks them in a fight
  frame:SetScript('OnDragStart', function(self) if not ns.settings.locked and not InCombatLockdown() then self:StartMoving() end end)
  frame:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing() holdTop() savePosition()
    if ns.Panels and ns.Panels.Dock then ns.Panels.Dock() end
  end)
  -- Ctrl and the mouse wheel size the window (out of combat, unless it's locked)
  frame:EnableMouseWheel(true)
  frame:SetScript('OnMouseWheel', function(_, delta)
    if not (IsControlKeyDown and IsControlKeyDown()) or ns.settings.locked or InCombatLockdown() then return end
    Window.SetScale((ns.settings.scale or 1) + delta * 0.05)
  end)
  local pos = ns.db.frames.main
  if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    local sp = Window.FirstSpot()
    frame:SetPoint(sp[1], UIParent, sp[2], sp[3], sp[4])
  end
  frame:SetScale(s.scale or 1)
  frame.skin = Skin.Panel(frame)
  Window.SetOpacity(s.opacity or 0.6)

  frame.plate = Skin.ThreeSlice(frame, 'header', PLATE_H, 32, 'BORDER', 2)
  frame.plate:Place(frame, 7, -7, PLATE_Y)

  seal = CreateFrame('Button', 'BoFGuideSeal', frame)
  seal:SetSize(40, 40)
  seal:SetPoint('TOPLEFT', frame, 'TOPLEFT', 9, -10)
  seal:SetFrameLevel((frame:GetFrameLevel() or 1) + 3)
  seal.tex = Skin.Tex(seal, 'seal', 'ARTWORK')
  seal.tex:SetAllPoints(seal)
  seal.glow = Skin.Tex(seal, 'glow', 'BACKGROUND')
  seal.glow:SetPoint('CENTER', seal, 'CENTER', 0, 0)
  seal.glow:SetSize(64, 64)
  seal.glow:SetAlpha(0.18)
  seal:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  seal:SetScript('OnClick', function(self) Window.Menu(self) end)
  seal:SetScript('OnEnter', function(self)
    local route = ns.Engine and ns.Engine.Route()
    tip(self, { route and (route.title or route.id) or L.sealTip, L.sealHelp })
    seal.glow:SetAlpha(0.4)
  end)
  seal:SetScript('OnLeave', function() untip() seal.glow:SetAlpha(0.18) end)

  -- the route's name, centred in the plate's dark band
  frame.titleBox = CreateFrame('Frame', nil, frame)
  frame.titleBox:SetPoint('TOPLEFT', frame, 'TOPLEFT', TITLE_LEFT, PLATE_Y - 3)
  frame.titleBox:SetPoint('BOTTOMRIGHT', frame, 'TOPRIGHT', -TITLE_RIGHT, PLATE_Y - 28)
  title = Skin.String(frame.titleBox, 'Title', 'OVERLAY', C.gold)
  title:SetAllPoints(frame.titleBox)
  title:SetJustifyV('MIDDLE')
  title:SetWordWrap(false)

  -- the row under the plate: your level against the plan, and the switches
  frame.row = CreateFrame('Frame', nil, frame)
  frame.row:SetHeight(ROW_H)
  frame.row:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD + 4, ROW_Y)
  frame.row:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -PAD - 2, ROW_Y)
  closeBtn = Skin.IconButton(frame, 18, 'btn-close', function() Window.Toggle() end, 'BoFGuideClose', L.closeTip)
  closeBtn:SetPoint('RIGHT', frame.row, 'RIGHT', 0, 0)
  collapseBtn = Skin.IconButton(frame, 18, 'btn-collapse', function()
    ns.settings.collapsed = not ns.settings.collapsed
    ns.MarkDirty('collapse')
  end, 'BoFGuideCollapse')
  collapseBtn:SetPoint('RIGHT', closeBtn, 'LEFT', -4, 0)
  -- the gear: the seal's menu, where everyone looks for settings (the owner, Nov 12: players didn't know the seal at
  -- the top left is the menu). Our painted gear, the same plate as the close and collapse buttons; the seal still works
  gearBtn = Skin.IconButton(frame, 18, 'btn-settings', function() Window.Menu(gearBtn) end, 'BoFGuideGear', L.gearTip)
  gearBtn:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  gearBtn:SetPoint('RIGHT', collapseBtn, 'LEFT', -4, 0)
  autoBtn = Skin.Button(frame, 42, 18, L.autoOn, function()
    local on = not Window.AutoOn()
    for k in pairs(ns.settings.auto) do ns.settings.auto[k] = on end
    if on then ns.AutoResume() end   -- (the player says try again)
    ns.say(on and L.autoNowOn or L.autoNowOff)
    Window.Header()
    if GameTooltip and GameTooltip:IsOwned(autoBtn) then Skin.Tooltip(autoBtn, autoBtn.tip) end
  end, 'BoFGuideAuto')
  autoBtn:SetPoint('RIGHT', gearBtn, 'LEFT', -6, 0)
  -- looking back (the seal's "Look back one step"): a plate in AUTO's place takes you back to where you are (FB-064,
  -- Nov 13: the only ways back were the menu and /bofg resume, and a player thought the guide had lost their quest)
  backBtnReturn = Skin.Button(frame, 64, 18, L.peekReturn, function() ns.Engine.Resume() end, 'BoFGuideReturn')
  backBtnReturn:SetPoint('RIGHT', gearBtn, 'LEFT', -6, 0)
  backBtnReturn:SetWidth(math.max(64, (backBtnReturn.text and backBtnReturn.text:GetStringWidth() or 40) + 22))
  backBtnReturn.tip = { L.menuResume, L.peekTip }
  backBtnReturn:Hide()
  -- on: an ember halo breathing round the lit plate, gold lettering; off: a grey, dimmed plate
  autoBtn.halo = Skin.Tex(autoBtn, 'glow', 'BACKGROUND', -8)
  autoBtn.halo:SetBlendMode('ADD')
  autoBtn.halo:SetVertexColor(C.ember[1], C.ember[2], C.ember[3])
  autoBtn.halo:SetPoint('CENTER', autoBtn, 'CENTER', 0, 0)
  autoBtn.halo:SetSize(92, 50)
  autoBtn.breath = autoBtn.halo:CreateAnimationGroup()
  if autoBtn.breath.SetLooping then autoBtn.breath:SetLooping('BOUNCE') end
  local breath = autoBtn.breath:CreateAnimation('Alpha')
  breath:SetFromAlpha(0.55)
  breath:SetToAlpha(1)
  breath:SetDuration(1.6)
  autoBtn.restyle = function(self, hover)
    local on = self.on
    if on and not hover then self.bg:SetTexture(Skin.MEDIA .. 'btn-plate-hover') end
    if self.bg.SetDesaturated then self.bg:SetDesaturated(not on) end
    local v = on and 1 or 0.55
    self.bg:SetVertexColor(v, v, v)
    local c = on and C.gold or C.faint
    self.text:SetTextColor(c[1], c[2], c[3], on and 1 or 0.7)
  end
  autoBtn.tip = function() return Window.AutoTip() end
  sub = Skin.String(frame.row, 'Small', 'OVERLAY', C.dim)
  sub:SetPoint('LEFT', frame.row, 'LEFT', 0, 0)
  sub:SetPoint('RIGHT', autoBtn, 'LEFT', -8, 0)
  sub:SetJustifyV('MIDDLE')
  sub:SetWordWrap(false)
  -- the pace line explains itself on hover; motion only, so the window still drags from here
  frame.paceHit = CreateFrame('Frame', nil, frame)
  frame.paceHit:SetAllPoints(sub)
  frame.paceHit:EnableMouse(true)
  if frame.paceHit.SetMouseClickEnabled then frame.paceHit:SetMouseClickEnabled(false) end
  frame.paceHit:SetScript('OnEnter', function(self) if frame.paceTip then Skin.Tooltip(self, frame.paceTip, 'ANCHOR_BOTTOMLEFT') end end)
  frame.paceHit:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)

  rule = Skin.Hairline(frame, true)
  rule:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, RULE_Y)
  rule:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -PAD, RULE_Y)

  message = Skin.String(frame, 'Body', 'OVERLAY', C.text)
  message:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD + 4, -HEAD_H - 4)
  message:SetWidth(width() - 2 * PAD - 8)

  nextLabel = Skin.String(frame, 'Label', 'OVERLAY', C.faint)
  nextLabel:SetText(ns.upper(L.upNext))

  frame:SetShown(s.shown)
  Window.Header()
  return frame
end

--- the header's parts, for the layout tests
function Window.Parts()
  return { frame = frame, title = title, sub = sub, auto = autoBtn, collapse = collapseBtn, close = closeBtn,
           seal = seal, row = frame and frame.row, titleBox = frame and frame.titleBox }
end

--- the progress fill: shows the first `frac` of the painted ember-to-gold run
local function setFill(tex, full, frac)
  frac = math.max(0, math.min(1, frac or 0))
  tex:SetWidth(math.max(1, full * frac))
  tex:SetTexCoord(0, math.max(0.01, frac), 0, 1)
  tex:SetShown(frac > 0)
end

--- Hardcore wears blackened iron corners and ember light
function Window.Theme(hc)
  if not frame or frame.hc == (hc and true or false) then return end
  frame.hc = hc and true or false
  Skin.Hardcore(frame.skin, hc)
  for _, k in ipairs({ 'l', 'm', 'r' }) do
    if hc then frame.plate[k]:SetVertexColor(0.78, 0.62, 0.55) else frame.plate[k]:SetVertexColor(1, 1, 1) end
  end
  seal.glow:SetAlpha(hc and 0.35 or 0.18)
end

Window.SCALE = { 0.3, 1.6 }   -- the window's size, from quite small to large (settings.scale)

function Window.SetScale(v)
  v = math.max(Window.SCALE[1], math.min(Window.SCALE[2], math.floor(v * 100 + 0.5) / 100))
  ns.settings.scale = v
  if frame and not InCombatLockdown() then
    -- (sized about its top-left corner, which stays where it is on screen)
    holdTop()
    local _, _, _, x, y = frame:GetPoint()
    local old = frame:GetScale() or 1
    frame:SetScale(v)
    if x and y then
      frame:ClearAllPoints()
      frame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', x * old / v, y * old / v)
      if ns.db.frames.main then savePosition() end
    end
    if ns.Panels and ns.Panels.Dock then ns.Panels.Dock() end
  else
    Window.scaleWaits = true   -- (applied when the fight ends: it was saved and said, then never applied; Oct 20)
  end
  return v
end

--- how solid the stone behind the steps is (0 to 1); the bronze frame and the text stay
function Window.SetOpacity(v)
  v = math.max(0, math.min(1, v))
  ns.settings.opacity = v
  if frame and frame.skin then
    frame.skin.bg:SetAlpha(v)
    frame.skin.shade:SetAlpha(v)
    if frame.skin.glow then frame.skin.glow:SetAlpha(0.16 * v) end
  end
  if ns.Panels and ns.Panels.SetOpacity then ns.Panels.SetOpacity(v) end   -- the panels match the window
  return v
end

function Window.AutoOn()
  for _, v in pairs(ns.settings.auto or {}) do if v then return true end end
  return false
end

local AUTO_PARTS = { 'accept', 'turnin', 'gossip', 'taxi' }

--- the AUTO switch's tooltip: whether it's on (all of it, or which parts), what it does, and how to use it
function Window.AutoTip()
  local a = ns.settings.auto or {}
  local on, parts = 0, {}
  for _, k in ipairs(AUTO_PARTS) do if a[k] then on = on + 1 parts[#parts + 1] = L.AUTO_SHORT[k] end end
  local lines = {}
  if on == #AUTO_PARTS then lines[1] = { L.autoTitleOn, C.done[1], C.done[2], C.done[3] }
  elseif on > 0 then lines[1] = { L.autoTitleSome:format(table.concat(parts, ', ')), C.gold[1], C.gold[2], C.gold[3] }
  else lines[1] = { L.autoTitleOff, C.faint[1], C.faint[2], C.faint[3] } end
  lines[#lines + 1] = L.autoWhat
  lines[#lines + 1] = on > 0 and L.autoClickOff or L.autoClickOn
  if on > 0 then lines[#lines + 1] = L.autoHold end
  if on > 0 and ns.settings.readNew then lines[#lines + 1] = L.autoReadNew end
  lines[#lines + 1] = { L.autoParts, 0.65, 0.65, 0.65 }
  return lines
end

--- a plate hanging under the AUTO switch, once, after a new install's setup: reading every quest is the default, and
--- a player who clicked through it must still find the switch (owner, Oct 30). Gone on a click or after a while
local coach
function Window.Coach(text)
  if not autoBtn then return end
  if not coach then
    coach = CreateFrame('Button', 'BoFGuideCoach', autoBtn)
    coach:SetFrameStrata('DIALOG')
    coach.fill = coach:CreateTexture(nil, 'BACKGROUND')
    coach.fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.96)
    coach.fill:SetAllPoints(coach)
    coach.line = coach:CreateTexture(nil, 'BORDER')
    coach.line:SetColorTexture(C.ember[1], C.ember[2], C.ember[3], 1)
    coach.line:SetPoint('TOPLEFT', coach, 'TOPLEFT', 0, 0)
    coach.line:SetPoint('TOPRIGHT', coach, 'TOPRIGHT', 0, 0)
    coach.line:SetHeight(2)
    coach.text = Skin.String(coach, 'Small', 'OVERLAY', C.text)
    coach.text:SetPoint('TOPLEFT', coach, 'TOPLEFT', 10, -9)
    coach.text:SetWidth(210)
    coach:SetPoint('TOPRIGHT', autoBtn, 'BOTTOMRIGHT', 0, -6)
    coach:SetScript('OnClick', function(self) self:Hide() end)
    autoBtn:HookScript('OnClick', function() coach:Hide() end)
  end
  coach.text:SetText(text)
  coach:SetSize(230, (coach.text:GetStringHeight() or 28) + 18)
  coach:Show()
  autoBtn.halo:Show()
  autoBtn.breath:Play()
  C_Timer.After(25, function()
    coach:Hide()
    Window.Header()
  end)
end

--- a plate over the first card: the profession guide the level wait set aside can go on now (Engine.ProfBack). A
--- click goes on with it, the cross puts the offer away; the guide never switches by itself (owner, Nov 10).
--- Returns the height it takes
local backBtn
local function backPlate(back, y)
  if not back then
    if backBtn then backBtn:Hide() end
    return 0
  end
  if not backBtn then
    backBtn = Skin.Button(frame, 100, 26, '', function() ns.Engine.ProfBackTake(true) end, 'BoFGuideBack')
    backBtn.text:ClearAllPoints()
    backBtn.text:SetPoint('LEFT', backBtn, 'LEFT', 14, 0)
    backBtn.text:SetPoint('RIGHT', backBtn, 'RIGHT', -30, 0)
    backBtn.close = Skin.IconButton(backBtn, 14, 'btn-close', function() ns.Engine.ProfBackTake(false) end,
                                    'BoFGuideBackClose', { L.profBackLater, L.profBackLaterTip })
    backBtn.close:SetPoint('RIGHT', backBtn, 'RIGHT', -9, 0)
  end
  backBtn.tip = { L.profBack:format(back.name), L.profBackTip }
  backBtn.text:SetText(L.profBack:format(back.name))
  local w = width() - 2 * PAD
  backBtn.text:SetWidth(w - 44)
  local h = math.max(26, heightOf(backBtn.text, 12) + 12)
  backBtn:SetSize(w, h)
  backBtn:ClearAllPoints()
  backBtn:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, y - 2)
  backBtn:Show()
  return h + 10
end
function Window.BackShown() return backBtn and backBtn:IsShown() and backBtn.text:GetText() or nil end   -- (tests)

--- the header's switches, after a setting changes
function Window.Header()
  if not frame then return end
  local on = Window.AutoOn()
  autoBtn.on = on
  autoBtn:restyle(false)
  autoBtn.halo:SetShown(on)
  if on then autoBtn.breath:Play() else autoBtn.breath:Stop() end
  collapseBtn.icon:SetRotation(ns.settings.collapsed and math.pi or 0)
  collapseBtn.tip = ns.settings.collapsed and { L.expandTitle, L.expandTip } or { L.collapseTitle, L.collapseTip }
end

-- stories opened or closed with a click this session; the setting (settings.storyOpen) is the rest
local storyOpen = {}

--- the "Show quest stories" setting changed: it applies to every quest again, clicked or not
function Window.ResetStories() wipe(storyOpen) end

local function words(v)
  local lv = math.floor(v)
  local pct = math.floor((v - lv) * 100 + 0.5)
  if pct < 5 then return L.levelExact:format(lv) end
  if pct > 95 then return L.levelExact:format(lv + 1) end
  return L.levelPart:format(lv, pct, lv + 1)
end

--- your pace: your level against the level the route expects at this step, in words, with a tooltip that says more
--- (behind is where danger starts, so it's colored)
function Window.Pace(level, plan, hc)
  if not plan then return L.levelOnly:format(math.floor(level)), nil end
  local d = level - plan
  local n = math.floor(math.abs(d) + 0.5)
  local lv = ns.count('levelCount', math.max(1, n))
  local text, color, why
  if math.abs(d) < 0.5 then text, color, why = L.paceOn, C.dim, L.paceOnWhy
  elseif d > 0 then text, color, why = L.paceAhead:format(lv), C.done, L.paceAheadWhy
  else
    text, color = L.paceBehind:format(lv), d <= -1.5 and C.danger or C.ember
    why = hc and L.paceBehindWhyHC or L.paceBehindWhy
  end
  local tipLines = { L.paceTitle, L.paceYou:format(words(level)), L.paceGuide:format(words(plan)), why }
  return Skin.Hex(color) .. text .. '|r', tipLines
end

function Window.Toggle()
  Window.Create()
  ns.settings.shown = not frame:IsShown()
  frame:SetShown(ns.settings.shown)
  if ns.Arrow then ns.Arrow.Set(ns.Arrow.target) end
  if ns.Panels then ns.Panels.Shown() end
end

local function hideBody()
  if backBtn then backBtn:Hide() end
  for _, cd in ipairs(cards) do cd.stepKey = nil cd:Hide() end
  for _, r in ipairs(rows) do r.stepKey = nil r:Hide() end
  nextLabel:Hide()
end

function Window.MessageText() return message and message:GetText() end   -- (tests)
function Window.SubText() return sub and sub:GetText() end   -- (tests: the line beside AUTO)

--- the free guide's end at level 30 (owner, Oct 16: the free guide ends when you reach 30, the full guide takes over
--- from there): what the guide did with you, where the road goes next, and one button to the full guide. It lives in
--- the window the player already looks at; nothing pops up
function Window.Finish(head, text, button, onClick)
  Window.Create()
  if not finishBtn then
    finishBtn = Skin.Button(frame, 180, 26, '', function() if finishBtn.go then finishBtn.go() end end, 'BoFGuideFinish')
    finishBtn.text:SetFontObject(Skin.Font.Button)
  end
  message:Show()
  autoBtn:Hide()   -- (nothing for it to do on the card or a message; the QA pass, Oct 20)
  setTitle(head)
  sub:SetText(L.finishSub or '')   -- (the line beside AUTO isn't left empty; Oct 17)
  message:SetText(text or '')
  hideBody()
  wipe(shown)
  finishBtn.go = onClick
  finishBtn.text:SetText(button or '')
  finishBtn:SetWidth(math.max(160, (finishBtn.text:GetStringWidth() or 0) + 48))
  finishBtn:ClearAllPoints()
  finishBtn:SetPoint('TOPLEFT', message, 'BOTTOMLEFT', -2, -12)
  finishBtn:Show()
  if not haveBtn then
    haveBtn = Skin.Button(frame, 150, 26, '', function() ns.Import.Show() end, 'BoFGuideFinishHave')
    haveBtn.text:SetFontObject(Skin.Font.Button)   -- (the same lettering as See the full guide beside it; Oct 18)
  end
  haveBtn.text:SetText(L.finishHave)
  haveBtn:SetWidth(math.max(120, (haveBtn.text:GetStringWidth() or 0) + 40))
  haveBtn:ClearAllPoints()
  -- side by side when they fit, else the quieter one under the first (German at 150% text ran past the edge)
  local room = width() - 2 * PAD - 8
  local stacked = finishBtn:GetWidth() + 8 + haveBtn:GetWidth() > room
  if stacked then
    haveBtn:SetPoint('TOPLEFT', finishBtn, 'BOTTOMLEFT', 0, -6)
  else
    haveBtn:SetPoint('LEFT', finishBtn, 'RIGHT', 8, 0)
  end
  haveBtn:Show()
  setHeight(HEAD_H + 16 + math.max(16, heightOf(message, 16)) + 12 + 26 + (stacked and 32 or 0) + 14)
end

function Window.FinishShown() return finishBtn and finishBtn:IsShown() and true or false end   -- (tests)

local msgSkip
--- the skip button on a message card (a trip: FB-049); hidden on every other message
function Window.MessageSkip(onClick, tip)
  if not msgSkip then
    msgSkip = Skin.Button(frame, 18, 18, '»', function(self) if self.go then self.go() end end, 'BoFGuideMessageSkip')
    msgSkip.text:SetFontObject(Skin.Font.Body)
    msgSkip:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -PAD, -HEAD_H + 2)
  end
  msgSkip.go, msgSkip.tip = onClick, tip
  msgSkip:SetShown(onClick ~= nil)
end

function Window.Message(head, text, detail)
  Window.Create()
  if Window.demo and not Window.drawingDemo then return end   -- (the tour's example is on screen: UI/Tour.lua)
  if msgSkip then msgSkip:Hide() end
  if finishBtn then finishBtn:Hide() end
  if haveBtn then haveBtn:Hide() end
  message:Show()
  autoBtn:Hide()
  setTitle(Window.ShortTitle(head or 'Bind on Forever Guide'))
  sub:SetText(detail or '')
  message:SetText(text or '')
  hideBody()
  wipe(shown)
  setHeight(HEAD_H + 16 + math.max(16, heightOf(message, 16)))
end

-- --------------------------------------------------------------------------------------------------- the cards
local function cardClick(self, button)
  if not self.stepKey then return end
  if IsShiftKeyDown and IsShiftKeyDown() then return ns.Engine.Click(self.stepKey, 'LeftButton', true) end
  if button == 'RightButton' then return stepMenu(self, self.stepKey) end
  -- Ctrl-click: the world map at the step (FB-035)
  if IsControlKeyDown and IsControlKeyDown() then return ns.Waypoint.ShowOnMap(ns.Engine.MapOf(self.stepKey)) end
  ns.Engine.Focus(self.stepKey)
end

local function cardEnter(self)
  self.skip:Show()
  self.edge[1]:SetColorTexture(C.frameHi[1], C.frameHi[2], C.frameHi[3], 1)
  local lines = { self.title:GetText() or '' }
  for _, t in ipairs(self.tips or {}) do lines[#lines + 1] = t end
  lines[#lines + 1] = { L.cardHelp, 0.6, 0.6, 0.6 }
  tip(self, lines)
end

local function cardLeave(self)
  if not self:IsMouseOver() then self.skip:Hide() end
  self.edge[1]:SetColorTexture(C.frame[1], C.frame[2], C.frame[3], 1)
  untip()
end

local function newCard(i)
  local cd = CreateFrame('Button', 'BoFGuideLine' .. i, frame)
  cd:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  cd.bg = cd:CreateTexture(nil, 'BACKGROUND')
  cd.bg:SetAllPoints(cd)
  cd.bg:SetColorTexture(C.surface2[1], C.surface2[2], C.surface2[3], 0.88)
  cd.edge = {}
  for j, side in ipairs({ 'TOP', 'BOTTOM' }) do
    local t = cd:CreateTexture(nil, 'BORDER')
    t:SetColorTexture(C.frame[1], C.frame[2], C.frame[3], 1)
    t:SetHeight(1)
    t:SetPoint(side .. 'LEFT', cd, side .. 'LEFT', 0, 0)
    t:SetPoint(side .. 'RIGHT', cd, side .. 'RIGHT', 0, 0)
    cd.edge[j] = t
  end
  cd.accent = cd:CreateTexture(nil, 'BORDER')
  cd.accent:SetWidth(2)
  cd.accent:SetPoint('TOPLEFT', cd, 'TOPLEFT', 0, 0)
  cd.accent:SetPoint('BOTTOMLEFT', cd, 'BOTTOMLEFT', 0, 0)
  cd.glow = Skin.Tex(cd, 'glow', 'BACKGROUND', 1)
  cd.glow:SetBlendMode('ADD')
  cd.glow:SetAlpha(0.12)
  cd.icon = cd:CreateTexture(nil, 'ARTWORK')
  cd.label = Skin.String(cd, 'Label', 'OVERLAY', C.faint)
  cd.title = Skin.String(cd, 'Body', 'OVERLAY', C.text)
  cd.lines, cd.objs, cd.marks, cd.els, cd.folds = {}, {}, {}, {}, {}
  cd.skip = Skin.Button(cd, 18, 18, '»', function(self)
    local key = self:GetParent().stepKey
    if key then ns.Engine.Click(key, 'LeftButton', false) end
  end)
  cd.skip:SetPoint('TOPRIGHT', cd, 'TOPRIGHT', -4, -4)
  cd.skip.text:SetFontObject(Skin.Font.Body)
  cd.skip.tip = L.skipTip
  cd.skip:Hide()
  _G['BoFGuideLine' .. i .. 'Skip'] = cd.skip
  cd.fade = cd:CreateAnimationGroup()
  local a = cd.fade:CreateAnimation('Alpha')
  a:SetFromAlpha(0)
  a:SetToAlpha(1)
  a:SetDuration(0.25)
  cd:SetScript('OnClick', cardClick)
  cd:SetScript('OnEnter', cardEnter)
  cd:SetScript('OnLeave', cardLeave)
  cards[i] = cd
  return cd
end

local function pooled(list, i, make)
  local x = list[i]
  if not x then x = make() list[i] = x end
  x:Show()
  return x
end

local cardTextIn

--- a text line inside a card, anchored under y; returns the new y
local function cardText(cd, n, style, text, color, left, y, w)
  local fs = cd.lines[n] or Skin.String(cd, style, 'OVERLAY')
  cd.lines[n] = fs
  fs:SetFontObject(Skin.Font[style])
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  fs:ClearAllPoints()
  fs:SetPoint('TOPLEFT', cd, 'TOPLEFT', left, y)
  fs:SetWidth(w)
  fs:SetText(text)
  return y - heightOf(fs, 12) - 2
end

--- a text line from one of the card's other pools (cd[pool]), so sub-lines don't disturb the main line count
cardTextIn = function(cd, pool, n, style, text, color, left, y, w)
  cd[pool] = cd[pool] or {}
  local fs = cd[pool][n]
  if not fs then fs = Skin.String(cd, style, 'OVERLAY') cd[pool][n] = fs end
  fs:SetFontObject(Skin.Font[style])
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  fs:ClearAllPoints()
  fs:SetPoint('TOPLEFT', cd, 'TOPLEFT', left, y)
  fs:SetWidth(w)
  fs:SetText(text)
  return y - heightOf(fs, 10) - 2
end

--- an objective: check, text, count, and a thin bar under it
local function cardObjective(cd, n, ob, left, y, w)
  local row = cd.objs[n]
  if not row then
    row = {}
    row.check = Skin.Tex(cd, 'check-done', 'OVERLAY')
    row.check:SetSize(13, 13)
    row.box = Skin.Tex(cd, 'check-empty', 'ARTWORK')
    row.box:SetSize(13, 13)
    row.text = Skin.String(cd, 'Text', 'OVERLAY')
    row.count = Skin.String(cd, 'Small', 'OVERLAY', C.dim)
    row.count:SetJustifyH('RIGHT')
    row.count:SetWordWrap(false)
    row.track = cd:CreateTexture(nil, 'ARTWORK')
    row.track:SetHeight(OBJ_BAR)
    row.fill = Skin.Tex(cd, 'bar-fill-m', 'OVERLAY')
    row.fill:SetHeight(OBJ_BAR)
    cd.objs[n] = row
  end
  local done = ob.fin or (ob.need > 0 and ob.have >= ob.need)
  row.box:ClearAllPoints()
  row.box:SetPoint('TOPLEFT', cd, 'TOPLEFT', left, y)
  row.check:ClearAllPoints()
  row.check:SetPoint('CENTER', row.box, 'CENTER', 0, 0)
  row.check:SetShown(done)
  row.box:SetShown(not done)
  row.text:ClearAllPoints()
  row.text:SetPoint('TOPLEFT', cd, 'TOPLEFT', left + 19, y)
  row.text:SetWidth(w - 19 - 44)
  row.text:SetText(ob.text)
  local tc = done and C.done or C.text
  row.text:SetTextColor(tc[1], tc[2], tc[3])
  row.count:ClearAllPoints()
  row.count:SetPoint('TOPRIGHT', cd, 'TOPLEFT', left + w, y)
  row.count:SetWidth(44)
  row.count:SetText(ob.need > 1 and ('%d/%d'):format(ob.have, ob.need) or '')
  local h = heightOf(row.text, 12)
  row.count:Show()
  y = y - h - 2
  if ob.need > 1 and not done then
    row.track:ClearAllPoints()
    row.track:SetPoint('TOPLEFT', cd, 'TOPLEFT', left + 19, y)
    row.track:SetWidth(w - 19)
    row.track:SetColorTexture(C.well[1], C.well[2], C.well[3], 1)
    row.fill:ClearAllPoints()
    row.fill:SetPoint('TOPLEFT', row.track, 'TOPLEFT', 0, 0)
    row.track:Show()
    setFill(row.fill, w - 19, ob.have / ob.need)
    y = y - OBJ_BAR - 3
  else
    row.track:Hide() row.fill:Hide()
  end
  return y
end

--- a warning, a tip, where in a place or an action with an item: a small mark and the text. Each kind has its own
--- look (owner, Oct 11: things to do must stand out): an action in gold, semibold, with the item's own icon; where
--- in ember with the way mark; a danger in red; a tip in parchment
local MARK_COLOR = { tip = 'text', where = 'ember', use = 'gold', ask = 'gold' }
local function cardMark(cd, n, kind, text, left, y, w, item)
  local m = cd.marks[n]
  if not m then
    m = { icon = cd:CreateTexture(nil, 'OVERLAY'), text = Skin.String(cd, 'Text', 'OVERLAY') }
    cd.marks[n] = m
  end
  m.icon:ClearAllPoints()
  m.text:ClearAllPoints()
  local itemIcon = kind == 'use' and item and C_Item and C_Item.GetItemIconByID and ns.clean(C_Item.GetItemIconByID(item))
  if itemIcon then m.icon:SetTexture(itemIcon) else m.icon:SetTexture(Skin.MEDIA .. (Skin.MARK[kind] or Skin.MARK.danger)) end
  m.icon:SetSize(kind == 'use' and 16 or 14, kind == 'use' and 16 or 14)
  m.icon:SetPoint('TOPLEFT', cd, 'TOPLEFT', left - 1, y + 1)
  m.text:SetFontObject(Skin.Font[kind == 'use' and 'Body' or 'Text'] or Skin.Fonts()[kind == 'use' and 'Body' or 'Text'])
  local tc = C[MARK_COLOR[kind] or 'danger']
  m.text:SetTextColor(tc[1], tc[2], tc[3])
  local pad = kind == 'use' and 19 or 15
  m.text:SetPoint('TOPLEFT', cd, 'TOPLEFT', left + pad, y)
  m.text:SetWidth(w - pad)
  m.text:SetText(text)
  m.kind = kind
  m.icon:Show()
  return y - math.max(heightOf(m.text, 12), kind == 'use' and 16 or 0) - 2
end

local function hideFrom(list, n, fields)
  for i = n, #list do
    local x = list[i]
    if fields then for _, f in ipairs(fields) do x[f]:Hide() end else x:Hide() end
  end
end

--- the tour's examples (UI/Tour.lua; owner, Nov 13: "pre-built cards that are relevant"): a sample in the window,
--- drawn with the guide's own pieces and words and marked Example, while the guide's own drawing waits; nil puts the
--- guide's own card back. d = { message = { head, text } } or { icon, title, lines = { { text, color } } }
function Window.Demo(d)
  Window.Create()
  if not d then
    if Window.demo then
      Window.demo = nil
      if cards[1] then cards[1].stepKey = nil end
      ns.MarkDirty('demo')
    end
    return
  end
  Window.demo = true
  if d.message then
    Window.drawingDemo = true
    Window.Message(d.message[1], d.message[2], d.message[3] and (Skin.Hex(C.gold) .. ns.upper(d.message[3]) .. '|r'))
    Window.drawingDemo = nil
    return
  end
  message:Hide()
  if msgSkip then msgSkip:Hide() end
  if finishBtn then finishBtn:Hide() end
  hideBody()
  wipe(shown)
  local cd = cards[1] or newCard(1)
  cd:Show()
  cd.stepKey = nil
  local w = width() - 2 * PAD
  local left = 10 + ICON + 8
  local textW = w - left - 26
  cd:ClearAllPoints()
  cd:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, -HEAD_H)
  cd:SetWidth(w)
  cd.accent:SetColorTexture(C.ember[1], C.ember[2], C.ember[3], 1)
  cd.glow:Show()
  cd.glow:ClearAllPoints()
  cd.glow:SetPoint('CENTER', cd, 'LEFT', 36, 0)
  cd.glow:SetSize(72, 72)
  cd.icon:SetTexture(Skin.MEDIA .. (d.icon or 'med-goto'))
  cd.icon:SetSize(ICON, ICON)
  cd.icon:ClearAllPoints()
  cd.icon:SetPoint('TOPLEFT', cd, 'TOPLEFT', 9, -10)
  local y = -8
  cd.label:ClearAllPoints()
  cd.label:SetPoint('TOPLEFT', cd, 'TOPLEFT', left, y)
  cd.label:SetText(ns.upper(L.tourExample))
  cd.label:Show()
  y = y - heightOf(cd.label, 10) - 2
  cd.title:SetFontObject(Skin.Font.Big)
  cd.title:ClearAllPoints()
  cd.title:SetPoint('TOPLEFT', cd, 'TOPLEFT', left, y)
  cd.title:SetWidth(textW)
  cd.title:SetText(d.title or '')
  cd.title:SetTextColor(C.text[1], C.text[2], C.text[3])
  y = y - heightOf(cd.title, 14) - 4
  local n = 0
  for _, ln in ipairs(d.lines or {}) do
    n = n + 1
    y = cardText(cd, n, 'Small', ln[1], ln[2] or C.dim, left, y, textW)
  end
  for k = n + 1, #cd.lines do cd.lines[k]:Hide() end
  for _, pool in ipairs({ 'subs', 'stories', 'whys' }) do for _, fs in ipairs(cd[pool] or {}) do fs:Hide() end end
  for _, f in ipairs(cd.folds) do f:Hide() end
  for _, e in ipairs(cd.els) do e:Hide() end
  for _, r in ipairs(cd.objs) do r.check:Hide() r.box:Hide() r.text:Hide() r.count:Hide() r.track:Hide() r.fill:Hide() end
  hideFrom(cd.marks, 1, { 'icon', 'text' })
  local h = math.max(-y + 8, ICON + 20)
  cd:SetHeight(h)
  setHeight(HEAD_H + h + 16)
end

--- one action line in a talk stop: socket (ticked when done), the game's own mark, the action. A button, so a click
--- points the arrow at it and a right-click opens its menu.
local function stopLine(cd, n, step, pack, done, left, y, w)
  local el = cd.els[n]
  if not el then
    el = CreateFrame('Button', cd:GetName() .. 'El' .. n, cd)
    el:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    el.box = Skin.Tex(el, 'check-empty', 'ARTWORK')
    el.box:SetSize(13, 13)
    el.box:SetPoint('TOPLEFT', el, 'TOPLEFT', 0, 0)
    el.check = Skin.Tex(el, 'check-done', 'OVERLAY')
    el.check:SetSize(13, 13)
    el.check:SetPoint('CENTER', el.box, 'CENTER', 0, 0)
    el.mark = el:CreateTexture(nil, 'ARTWORK')
    el.mark:SetSize(14, 14)
    el.mark:SetPoint('TOPLEFT', el, 'TOPLEFT', 17, 0)
    el.text = Skin.String(el, 'Text', 'OVERLAY', C.text)
    el.text:SetPoint('TOPLEFT', el, 'TOPLEFT', 35, 0)
    el:SetScript('OnClick', cardClick)
    el:SetScript('OnEnter', function(self) if self.tips then tip(self, self.tips) end end)
    el:SetScript('OnLeave', untip)
    cd.els[n] = el
  end
  local ready = not (step.o == 'turnin' and ns.st.log[(type(step.id) == 'table' and step.id[1]) or step.id]
    and not ns.st.log[(type(step.id) == 'table' and step.id[1]) or step.id].ready)
  el.mark:SetTexture(Skin.GAME[(step.o == 'turnin' and not ready) and 'notready' or step.o] or Skin.GAME.talk)
  el.check:SetShown(done)
  el.box:SetShown(not done)
  el:ClearAllPoints()
  el:SetPoint('TOPLEFT', cd, 'TOPLEFT', left, y)
  el:SetSize(w, 15)
  el:Show()
  el.text:SetWidth(w - 35)
  local main = ns.Text.Step(step, pack, true)
  if step.sy and main == step.sy and cd.titleWords == step.sy then
    main = ns.Text.Step({ o = step.o, id = step.id, npc = step.npc, buy = step.buy, p = step.p }, pack, true)
  end   -- the route's words are the card's title already: the line says what to do there
  local function bare(t) return (t or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '') end
  if step.o == 'train' and bare(main) == bare(cd.titleWords) then main = L.trainRow end   -- (not "Train at X" twice; Oct 17)
  if not ready and not done then main = main .. ' ' .. Skin.Hex(C.ember) .. '(' .. L.notReadyShort .. ')|r' end
  el.text:SetText(main)
  local c = done and C.faint or C.text
  el.text:SetTextColor(c[1], c[2], c[3])
  el.text:SetAlpha(done and 0.7 or 1)
  local h = math.max(15, heightOf(el.text, 13))
  el:SetHeight(h)
  el.stepKey = step.k
  el.tips = { el.text:GetText() or '', { L.cardHelp, 0.6, 0.6, 0.6 } }
  return y - h - 3
end

--- a quest's name over its objectives, when an area stop holds more than one quest
local function questLabel(cd, n, text, left, y, w)
  return cardText(cd, n, 'Label', ns.upper(text), C.faint, left, y, w)
end

--- a quest's "Story" fold: a small toggle, and the story under it when open; returns the new y
local function storyFold(cd, n, q, pack, left, y, w)
  local inLog = ns.st.log[q] ~= nil
  local info = pack.quests and pack.quests[q]
  if not (inLog or (info and info.st)) then return y, n end
  local f = cd.folds[n]
  if not f then
    f = CreateFrame('Button', cd:GetName() .. 'Story' .. n, cd)
    f.text = Skin.String(f, 'Small', 'OVERLAY', C.goldSoft)
    f.text:SetPoint('TOPLEFT', f, 'TOPLEFT', 0, 0)
    f:SetScript('OnClick', function(self)
      storyOpen[self.quest] = not self.open
      ns.MarkDirty('story')
    end)
    f:SetScript('OnEnter', function(self)
      self.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
      tip(self, { self.open and L.storyHide or L.storyShow, L.storySetting })
    end)
    f:SetScript('OnLeave', function(self) self.text:SetTextColor(C.goldSoft[1], C.goldSoft[2], C.goldSoft[3]) untip() end)
    cd.folds[n] = f
  end
  local open = storyOpen[q]
  if open == nil then open = ns.settings.storyOpen and true or false end
  f.quest, f.open = q, open
  f.text:SetText((open and '- ' or '+ ') .. L.story)
  f:ClearAllPoints()
  f:SetPoint('TOPLEFT', cd, 'TOPLEFT', left, y)
  f:Show()
  local fh = math.max(13, heightOf(f.text, 12))   -- as tall as its text, at any text size
  f:SetSize(math.max(40, (f.text:GetStringWidth() or 40) + 6), fh)
  y = y - fh - 1
  if open then
    cd.storyN = cd.storyN + 1
    local text = ns.Text.Story(q, pack) or (inLog and L.storyWait or L.storyNone)
    y = cardTextIn(cd, 'stories', cd.storyN, 'Small', text, C.dim, left + 8, y, w - 8)
  end
  return y, n + 1
end

--- fill one stop's card; returns its height. stop.as = now | here | sticky
local function fillStop(cd, stop, route, view, top)
  local pack = route.pack
  local w = width() - 2 * PAD
  local big = stop.as == 'now'
  local icon = big and ICON or ICON_S
  local left = 10 + icon + 8
  local textW = w - left - 26
  local lead = route.steps[stop.lead]
  cd:ClearAllPoints()
  cd:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, top)
  cd:SetWidth(w)
  local accent = big and C.ember or (stop.as == 'sticky' and C.frame or C.goldSoft)
  cd.accent:SetColorTexture(accent[1], accent[2], accent[3], 1)
  cd.glow:SetShown(big)
  cd.glow:ClearAllPoints()
  cd.glow:SetPoint('CENTER', cd, 'LEFT', 36, 0)
  cd.glow:SetSize(72, 72)
  cd.icon:SetTexture(Skin.PinFor(lead))
  cd.icon:SetSize(icon, icon)
  cd.icon:ClearAllPoints()
  cd.icon:SetPoint('TOPLEFT', cd, 'TOPLEFT', 9, big and -10 or -7)
  local y = big and -8 or -6
  if not big then
    cd.label:ClearAllPoints()
    cd.label:SetPoint('TOPLEFT', cd, 'TOPLEFT', left, y)
    cd.label:SetText(ns.upper(stop.as == 'sticky' and L.asYouGo or L.alsoHere))
    y = y - heightOf(cd.label, 10) - 2
  else
    cd.label:Hide()
  end
  -- the instruction: who to talk to, what to kill or collect, or the step's own line
  local tag = lead.opt and (' ' .. Skin.Hex(C.faint) .. L.optional .. '|r') or ''
  cd.title:SetFontObject(big and Skin.Font.Big or Skin.Font.Body)
  cd.title:ClearAllPoints()
  cd.title:SetPoint('TOPLEFT', cd, 'TOPLEFT', left, y)
  cd.title:SetWidth(textW)
  cd.titleWords = ns.Text.StopTitle(stop, route)   -- (without the optional tag: the lines below compare with it)
  cd.title:SetText(cd.titleWords .. tag)
  cd.title:SetTextColor(C.text[1], C.text[2], C.text[3])
  y = y - heightOf(cd.title, 14) - 4
  -- why it's optional, faint under the title (Nov 7, the owner at Ozwin Ironsprocket's "(optional)")
  local why = lead.opt and ns.Text.Why(lead, pack)
  if why then
    y = cardTextIn(cd, 'whys', 1, 'Small', why, C.faint, left, y, textW) - 2
    cd.whys[1]:Show()
  elseif cd.whys and cd.whys[1] then
    cd.whys[1]:Hide()
  end
  local n, o, e, sn, fn = 0, 0, 0, 0, 1
  cd.storyN = 0
  local warn, kinds, tips, seen = {}, {}, {}, {}
  local acts, wheres, asks = {}, {}, {}
  local sub = w - left - 10
  local function subLine(text, indent, color)   -- a small line under an action or an objective
    if not text or text == '' then return end
    sn = sn + 1
    y = cardTextIn(cd, 'subs', sn, 'Small', text, color or C.dim, left + indent, y, sub - indent)
  end
  local function gather(step)
    local wl, wk = ns.Text.Warnings(step, pack)
    for k, t in ipairs(wl) do if not seen[t] then seen[t] = true warn[#warn + 1] = t kinds[#kinds + 1] = wk[k] end end
    -- (the level-30 card counts the steps the guide warned about: once each)
    if #wl > 0 and step.k and ns.cdb and not view.peek then
      ns.cdb.stats = ns.cdb.stats or {}
      ns.cdb.stats.warned = ns.cdb.stats.warned or {}
      ns.cdb.stats.warned[step.k] = true
    end
    local card = ns.Text.Card(step, pack)
    for _, t in ipairs(card.tips) do if not seen[t] then seen[t] = true tips[#tips + 1] = t end end
    for _, t in ipairs(card.wheres or {}) do if not seen[t] then seen[t] = true wheres[#wheres + 1] = t end end
    for _, a in ipairs(card.uses or {}) do if not seen[a.text] then seen[a.text] = true acts[#acts + 1] = a end end
    for _, t in ipairs(card.asks or {}) do if not seen[t] then seen[t] = true asks[#asks + 1] = t end end
    return card
  end
  local function record(step, card, more)
    local detail = {}
    for _, ln in ipairs(card.lines) do detail[#detail + 1] = ln[2] end
    for _, t in ipairs(more or {}) do detail[#detail + 1] = t end
    for _, x in ipairs(card.train or {}) do detail[#detail + 1] = (x.known and '[x] ' or '[ ] ') .. ns.Text.TrainLine(x) end
    for _, ob in ipairs(card.obj) do detail[#detail + 1] = ob.need > 1 and ('%s %d/%d'):format(ob.text, ob.have, ob.need) or ob.text end
    for _, t in ipairs(card.warn) do detail[#detail + 1] = t end
    for _, t in ipairs(card.wheres or {}) do detail[#detail + 1] = t end
    for _, a in ipairs(card.uses or {}) do detail[#detail + 1] = a.text end
    for _, t in ipairs(card.tips) do detail[#detail + 1] = t end
    shown[#shown + 1] = { key = step.k, text = card.main, detail = #detail > 0 and table.concat(detail, '\n') or nil,
                          kind = stop.as, stop = cd.title:GetText() }
  end
  if stop.kind == 'talk' then
    for _, i in ipairs(stop.steps) do
      local step = route.steps[i]
      local done = view.status[i] ~= 'pending'
      e = e + 1
      y = stopLine(cd, e, step, pack, done, left, y, w - left - 10)
      local card = gather(step)
      if not done then
        -- under a quest to take: what it asks in its own words, and its story (folded); under a trainer: the spells
        local q = step.o == 'accept' and ((type(step.id) == 'table' and step.id[1]) or step.id)
        if q then
          subLine(ns.Text.Says(q, pack), 35)
          if big then y, fn = storyFold(cd, fn, q, pack, left + 35, y, sub - 35) end
        end
        -- a hand-in that isn't done yet: what's left of it, in its own words, with the live objectives
        local tq = step.o == 'turnin' and ((type(step.id) == 'table' and step.id[1]) or step.id)
        local tlog = tq and ns.st.log[tq]
        if tlog and not tlog.ready then
          subLine(L.finishFirst, 35, C.ember)
          subLine(ns.Text.Says(tq, pack), 35)
          for _, ob in ipairs(tlog.obj) do
            if not ob.fin then
              o = o + 1
              y = cardObjective(cd, o, { text = ns.Text.ObjectiveName(ob) or ob.text or '', have = ob.have,
                                         need = ob.need, fin = false }, left + 35, y, sub - 35)
            end
          end
        end
        for _, x in ipairs(card.train or {}) do
          o = o + 1
          y = cardObjective(cd, o, { text = ns.Text.TrainLine(x), have = x.known and 1 or 0, need = 1, fin = x.known },
                            left + 17, y, sub - 17)
          if x.later then cd.objs[o].text:SetTextColor(C.faint[1], C.faint[2], C.faint[3]) end
        end
        record(step, card)
      end
    end
  elseif stop.kind == 'area' then
    local quests = {}
    for _, i in ipairs(stop.steps) do
      local step = route.steps[i]
      local q = (step.o == 'complete') and ((type(step.id) == 'table' and step.id[1]) or step.id) or step.q
      quests[#quests + 1] = { step = step, q = q }
    end
    local saidFor = {}
    for _, x in ipairs(quests) do
      local card = gather(x.step)
      local more = {}
      if #quests > 1 and x.q and not saidFor[x.q] then
        n = n + 1 y = questLabel(cd, n, ns.Text.Quest(x.q, pack), left, y - (next(saidFor) and 5 or 1), textW)
      end
      -- the quest's own words once per quest, on the card you're working (its place: "in Thendal Grove")
      if big and x.q and not saidFor[x.q] then
        local says = ns.Text.Says(x.q, pack)
        subLine(says, 0)
        more[#more + 1] = says
      end
      local how = x.q and ns.Text.How(x.q, pack) or {}
      local log = x.q and ns.st.log[x.q]
      for k, ob in ipairs(card.obj) do
        -- the live objective, with the creature's level; under an item, where it drops
        local raw = log and log.obj[(x.step.o == 'complete' and x.step.ob) or (x.step.qo) or k]
        local h = raw and ns.Text.HowFor(how, raw, log.obj)
        local lv = h and h.kind == 'kill' and ns.Text.MobLevel(h.id, pack)
        if lv then ob = { text = ob.text .. ' ' .. lv, have = ob.have, need = ob.need, fin = ob.fin } end
        o = o + 1
        y = cardObjective(cd, o, ob, left, y - 1, w - left - 10)
        if lv then more[#more + 1] = ob.text end
        if h and h.from and not ob.fin then
          subLine(h.from, 19)
          more[#more + 1] = ob.text .. ': ' .. h.from
        end
      end
      if #card.obj == 0 then
        local said = {}   -- (a place to be has no how-to line of its own: its objective's words say where)
        for _, h in ipairs(how) do if h.text then said[#said + 1] = h end end
        if #said > 0 then
          for _, h in ipairs(said) do n = n + 1 y = cardText(cd, n, 'Text', h.text, C.text, left, y, textW) more[#more + 1] = h.text end
        else
          local words = ns.Text.Step(x.step, pack, true)
          if x.step.sy and words == x.step.sy and cd.titleWords == x.step.sy then   -- the title says it already
            words = ns.Text.Step({ o = x.step.o, id = x.step.id, on = x.step.on, q = x.step.q, p = x.step.p }, pack, true)
          end
          n = n + 1 y = cardText(cd, n, 'Text', words, C.text, left, y, textW)
        end
      end
      if big and x.q and not saidFor[x.q] then y, fn = storyFold(cd, fn, x.q, pack, left, y, sub) end
      if x.q then saidFor[x.q] = true end
      record(x.step, card, more)
    end
  else
    local card = gather(lead)
    local more = {}
    for _, ln in ipairs(card.lines) do
      if big or ln[1] ~= 'Small' then n = n + 1 y = cardText(cd, n, ln[1], ln[2], ln[3] or C.dim, left, y, textW) end
    end
    for _, ob in ipairs(card.obj) do
      o = o + 1
      y = cardObjective(cd, o, ob, left, y - 1, w - left - 10)
    end
    if lead.o == 'xp' then   -- how many kills it takes, live from your XP
      local g = ns.Text.Grind(lead, route, stop.lead)
      if g then n = n + 1 y = cardText(cd, n, 'Text', g, C.text, left, y, textW) more[#more + 1] = g end
    end
    if big and lead.o == 'accept' then
      y, fn = storyFold(cd, fn, (type(lead.id) == 'table' and lead.id[1]) or lead.id, pack, left, y, sub)
    end
    record(lead, card, more)
  end
  -- where, and how far (the lead step's spot)
  if big then
    local where = ns.Text.Card(lead, pack).where
    if where then n = n + 1 y = cardText(cd, n, 'Small', where, C.faint, left, y - 1, textW) end
  end
  for k = n + 1, #cd.lines do cd.lines[k]:Hide() end
  for k = e + 1, #cd.els do cd.els[k]:Hide() end
  for k = sn + 1, #(cd.subs or {}) do cd.subs[k]:Hide() end
  for k = cd.storyN + 1, #(cd.stories or {}) do cd.stories[k]:Hide() end
  for k = fn, #cd.folds do cd.folds[k]:Hide() end
  for k = o + 1, #cd.objs do
    local r = cd.objs[k]
    r.check:Hide() r.box:Hide() r.text:Hide() r.count:Hide() r.track:Hide() r.fill:Hide()
  end
  local m = 0
  -- where in the place first (it matters most once you're there), then what to do with an item, then warnings, tips
  for _, t in ipairs(wheres) do m = m + 1 y = cardMark(cd, m, 'where', t, left, y - 1, w - left - 10) end
  for _, a in ipairs(acts) do m = m + 1 y = cardMark(cd, m, 'use', a.text, left, y - 1, w - left - 10, a.item) end
  for k, t in ipairs(warn) do m = m + 1 y = cardMark(cd, m, kinds[k] or 'danger', t, left, y - 1, w - left - 10) end
  -- (an as-you-go card never becomes the big one, so its tips show on it: Nov 5, the owner's Electropellers card said
  -- only "Complete Electropellers", and the line saying where to fish sat unseen in the hover)
  if big or stop.as == 'sticky' then
    for _, t in ipairs(tips) do m = m + 1 y = cardMark(cd, m, 'tip', t, left, y - 1, w - left - 10) end
  end
  -- what we still need to learn here, always shown (owner, Oct 16: the first player to reach it tells us, through
  -- Send feedback): the question, then how to send the answer
  for _, t in ipairs(asks) do
    m = m + 1
    y = cardMark(cd, m, 'ask', L.askLabel .. ' ' .. t .. ' ' .. L.askHow, left, y - 1, w - left - 10)
  end
  cd.asks = #asks > 0 and asks or nil
  hideFrom(cd.marks, m + 1, { 'icon', 'text' })
  local h = math.max(-y + 8, icon + (big and 20 or 14))
  cd:SetHeight(h)
  cd.stepKey = lead.k
  cd.stop = stop
  cd.tips = {}
  for _, t in ipairs(wheres) do cd.tips[#cd.tips + 1] = { t, C.ember[1], C.ember[2], C.ember[3] } end
  for _, a in ipairs(acts) do cd.tips[#cd.tips + 1] = { a.text, C.gold[1], C.gold[2], C.gold[3] } end
  for _, t in ipairs(warn) do cd.tips[#cd.tips + 1] = { t, C.danger[1], C.danger[2], C.danger[3] } end
  for _, t in ipairs(tips) do cd.tips[#cd.tips + 1] = { t, 0.9, 0.9, 0.8 } end
  local ev = ns.Text.Evidence(lead, pack)
  if ev then cd.tips[#cd.tips + 1] = { ev, 0.6, 0.75, 0.6 } end
  return h
end

-- ----------------------------------------------------------------------------------------------- the next rows
local function newRow(i)
  local r = CreateFrame('Button', 'BoFGuideNext' .. i, frame)
  r:SetHeight(ROW_H)
  r:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  r.icon = r:CreateTexture(nil, 'ARTWORK')
  r.icon:SetSize(15, 15)
  r.icon:SetPoint('LEFT', r, 'LEFT', 2, 0)
  r.icon:SetAlpha(0.75)
  r.text = Skin.String(r, 'Text', 'OVERLAY', C.faint)
  r.text:SetPoint('LEFT', r.icon, 'RIGHT', 7, 0)
  r.text:SetPoint('RIGHT', r, 'RIGHT', -2, 0)
  r.text:SetJustifyV('MIDDLE')
  r.text:SetWordWrap(false)
  r.hl = r:CreateTexture(nil, 'BACKGROUND')
  r.hl:SetAllPoints(r)
  r.hl:SetColorTexture(C.frameHi[1], C.frameHi[2], C.frameHi[3], 0.08)
  r.hl:Hide()
  r:SetScript('OnClick', cardClick)
  r:SetScript('OnEnter', function(self)
    self.hl:Show()
    self.text:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lines = { self.text:GetText() or '' }
    for _, t in ipairs(self.each or {}) do lines[#lines + 1] = { '  ' .. t, 0.9, 0.9, 0.85 } end   -- what you'll do there
    for _, t in ipairs(self.warn or {}) do lines[#lines + 1] = { t, C.danger[1], C.danger[2], C.danger[3] } end
    lines[#lines + 1] = { L.cardHelp, 0.6, 0.6, 0.6 }
    tip(self, lines)
  end)
  r:SetScript('OnLeave', function(self)
    self.hl:Hide()
    self.text:SetTextColor(C.faint[1], C.faint[2], C.faint[3], 1)
    untip()
  end)
  rows[i] = r
  return r
end

-- -------------------------------------------------------------------------------------------------- the render
--- draw a view from the evaluator, grouped into stops (Core/Stops.lua): stops = { current, sticky, upcoming }
local recheckQueued, redraws = false, 0
local function recheck()
  recheckQueued = false
  for _, fs in ipairs(measured) do
    if fs:IsVisible() and (fs:GetStringHeight() or 0) > (fs.bofH or 0) + 0.5 then
      if redraws < 2 then redraws = redraws + 1 ns.MarkDirty('layout') end   -- (twice at most in a row)
      return
    end
  end
  redraws = 0
end

function Window.Render(view, route, stops)
  Window.Create()
  if Window.demo then return end   -- (the tour's example is on screen; the guide draws again when it goes)
  if autoBtn then autoBtn:Show() end
  wipe(measured)
  if not recheckQueued then recheckQueued = true C_Timer.After(0, recheck) end
  local pack = route.pack
  ns.Text.ResetBudget()
  message:Hide()
  if msgSkip then msgSkip:Hide() end   -- (a trip's skip goes with its card)
  if finishBtn then finishBtn:Hide() end
  if haveBtn then haveBtn:Hide() end
  wipe(shown)
  setTitle(Window.ShortTitle(route.title or route.id))
  local cur = view.cursor and route.steps[view.cursor]
  local st = ns.st
  local level = (st.level or 1) + (st.xp or 0) / (st.xpMax or 1)
  local line, paceTip
  if route.kd == 'dungeon' then
    line = L.dungeonLine:format(route.lv and route.lv[1] or '?', route.lv and route.lv[2] or '?', math.floor(level))
  elseif route.kd == 'legacy' then
    local have, all = 0, 0
    for i, s in ipairs(route.steps) do
      if s.o == 'legacy' and view.status[i] ~= ns.Evaluator.NA then
        all = all + 1
        if view.status[i] == ns.Evaluator.DONE then have = have + 1 end
      end
    end
    line = L.legacyLine:format(have, all)
  elseif route.kd == 'profession' then
    local name = L.PROFS[route.pr] or route.pr or ''
    local rank, cap = st.profs[route.pr], st.profMax[route.pr]
    line = rank and L.profLine:format(name, rank, cap or rank) or L.profNone:format(name, name)
  else
    line, paceTip = Window.Pace(level, cur and cur.pl, st.hc)
  end
  if backBtnReturn then
    backBtnReturn:SetShown(view.peek and true or false)
    if view.peek and autoBtn then autoBtn:Hide() end
  end
  if view.peek then   -- looking back (/bofg back): say so where the pace line goes
    local behind = 0
    for i = view.peek, (view.live or view.peek) - 1 do
      if view.status[i] ~= ns.Evaluator.NA then behind = behind + 1 end
    end
    line, paceTip = Skin.Hex(C.gold) .. ns.count('peekLine', behind) .. '|r', { { L.peekTip } }
  end
  -- a talent point to spend and your talent plan's next talent (Core/Talents.lua): that line, for now
  local talent = ns.Talents and ns.Talents.Line and ns.Talents.Line()
  if talent then
    line = Skin.Hex(C.gold) .. talent .. '|r'
    paceTip = { { talent, C.gold[1], C.gold[2], C.gold[3] } }   -- (the whole line on the mouse, when it's cut short below)
  end
  local hcPre = st.hc and (Skin.Hex(C.ember) .. L.hardcore .. '|r  ·  ') or ''
  if st.hc then
    line = hcPre .. line
    if paceTip then paceTip[#paceTip + 1] = { L.hardcoreNote, C.ember[1], C.ember[2], C.ember[3] } end
  end
  -- your party's guides: what each one is on (Party.lua)
  local party = ns.Party and ns.Party.Lines() or {}
  if #party > 0 then
    paceTip = paceTip or {}
    paceTip[#paceTip + 1] = { L.partyTitle, C.gold[1], C.gold[2], C.gold[3] }
    for _, ln in ipairs(party) do paceTip[#paceTip + 1] = ln end
  end
  frame.paceTip = paceTip
  Window.Theme(st.hc)
  sub:SetText(line)
  -- a long talent name in a long language: the talent's icon and name only, so the name isn't cut off
  if talent and (sub:GetWidth() or 0) > 0 and (sub:GetStringWidth() or 0) > sub:GetWidth() then
    sub:SetText(hcPre .. Skin.Hex(C.gold) .. ns.Talents.Line(true) .. '|r')
  end
  Window.Header()

  local y = -HEAD_H
  y = y - backPlate(ns.Engine.ProfBack and ns.Engine.ProfBack() or nil, y)
  local collapsed = ns.settings.collapsed
  local list = {}
  for _, stop in ipairs(stops.current) do list[#list + 1] = stop end
  for _, stop in ipairs(stops.sticky) do list[#list + 1] = stop end
  local maxCards = collapsed and 1 or (ns.settings.cards or MAX_CARDS)
  local n = 0
  for _, stop in ipairs(list) do
    if n >= maxCards then break end
    n = n + 1
    local cd = cards[n] or newCard(n)
    local isNew = cd.stepKey ~= route.steps[stop.lead].k
    cd:Show()
    y = y - fillStop(cd, stop, route, view, y) - 6
    if isNew and n == 1 and cd.fade then cd.fade:Play() end
  end
  for i = n + 1, #cards do cards[i].stepKey = nil cards[i]:Hide() end
  -- the stops past the last card lead Up Next (Skyborne testers, Oct 11: "+1 more steps here" said nothing and
  -- couldn't be clicked), and no row says again what a card or a row above it says
  local nexts, said = {}, {}
  for k = 1, n do said[plain(cards[k].title:GetText())] = true end
  if not collapsed then
    local function add(stop)
      local s = route.steps[stop.lead]
      -- a person with several things to do says what they are ("Talk to Yala: hand in 1, accept 1"; owner and his
      -- daughter, Oct 9: "(2 steps)" said nothing); an area already names what's in it ("Kill A and B")
      local main = #stop.steps > 1 and ns.Text.StopTitle(stop, route) or ns.Text.Step(s, pack, true)
      if #stop.steps > 1 and stop.kind == 'talk' then main = L.stopDo:format(main, ns.Text.StopSummary(stop, route)) end
      local key = plain(main)
      if #nexts < (ns.settings.upcoming or 4) and not said[key] then
        said[key] = true
        nexts[#nexts + 1] = { stop = stop, main = main }
      end
    end
    for k = n + 1, #list do add(list[k]) end
    for _, stop in ipairs(stops.upcoming) do add(stop) end
  end
  local r = 0
  if #nexts > 0 then
    nextLabel:ClearAllPoints()
    nextLabel:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD + 2, y - 2)
    y = y - heightOf(nextLabel, 10) - 6
    for _, x in ipairs(nexts) do
      local stop, main = x.stop, x.main
      r = r + 1
      local row = rows[r] or newRow(r)
      local s = route.steps[stop.lead]
      row:ClearAllPoints()
      row:SetPoint('TOPLEFT', frame, 'TOPLEFT', PAD, y)
      row:SetWidth(width() - 2 * PAD)
      row.each = nil
      if #stop.steps > 1 then
        row.each = {}
        for _, i in ipairs(stop.steps) do row.each[#row.each + 1] = ns.Text.Step(route.steps[i], pack, true) end
      end
      local warn, kinds = {}, {}
      for _, i in ipairs(stop.steps) do
        local wl, wk = ns.Text.Warnings(route.steps[i], pack)
        for k, t in ipairs(wl) do warn[#warn + 1] = t kinds[#kinds + 1] = wk[k] end
      end
      row.warn = #warn > 0 and warn or nil
      row.icon:SetTexture(row.warn and (Skin.MEDIA .. (Skin.MARK[kinds[1]] or Skin.MARK.danger)) or Skin.PinFor(s))
      -- (a row is a label: a sentence's closing period dropped, a name's "..." kept; the QA pass, Oct 20)
      local tail = main:match('|r$') and '|r' or ''
      local body = tail ~= '' and main:sub(1, -3) or main
      if body:sub(-1) == '.' and body:sub(-2, -2) ~= '.' then main = body:sub(1, -2) .. tail end
      row.text:SetText(main)
      -- (the warning mark says it; red text turned only the verb red, "Sprich mit" red and the name white; Oct 20)
      row.text:SetTextColor(C.faint[1], C.faint[2], C.faint[3], 1)
      row.stepKey = s.k
      row:Show()
      shown[#shown + 1] = { key = s.k, text = main, kind = 'next', detail = row.warn and table.concat(warn, '\n') or nil }
      local rh = math.max(ROW_H, heightOf(row.text, 14) + 6)   -- a taller row for larger text
      row:SetHeight(rh)
      y = y - rh
    end
  else
    nextLabel:Hide()
  end
  for i = r + 1, #rows do rows[i].stepKey = nil rows[i]:Hide() end
  frame:SetWidth(width())
  setHeight(-y + 16)   -- room for the frame's bottom bar
  if ns.Panels and ns.Panels.Dock then ns.Panels.Dock() end   -- (the panels follow it, out of a fight)
end

-- in a fight the window steps back (settings.combatFade); it comes back when the fight ends
ns.On('PLAYER_REGEN_DISABLED', function() if frame and ns.settings.combatFade then frame:SetAlpha(0.35) end end)
ns.On('PLAYER_REGEN_ENABLED', function()
  if frame then frame:SetAlpha(1) end
  if Window.scaleWaits and frame then Window.scaleWaits = nil Window.SetScale(ns.settings.scale or 1) end
end)

--- the parts the tour points at (UI/Tour.lua), only those on screen: frame, seal, pace, auto, gear, card (the top
--- card), obj (its first objective), marks (its warnings, tips and where lines), story (its "+ Story"), skip (its »),
--- nexts (Up next and its rows)
function Window.TourParts()
  local p = {}
  if not (frame and frame:IsShown()) then return p end
  local function on(r) return r and r:IsShown() and r or nil end
  p.frame, p.seal, p.pace, p.auto, p.gear = frame, on(seal), on(sub), on(autoBtn), on(gearBtn)
  local cd = on(cards[1])
  if cd then
    p.card = cd
    p.skip = cd.skip   -- (shown only while the mouse is on the card: the tour shows it for its slide)
    for _, o in ipairs(cd.objs) do
      if o.text:IsShown() then p.obj = { o.text, o.count } break end
    end
    local marks = {}
    for _, m in ipairs(cd.marks) do if m.text:IsShown() then marks[#marks + 1] = m.icon marks[#marks + 1] = m.text end end
    if #marks > 0 then p.marks = marks end
    for _, f in ipairs(cd.folds) do if f:IsShown() then p.story = f break end end
  end
  if message:IsShown() then p.message = message end
  if nextLabel:IsShown() then
    local list = { nextLabel }
    for _, r in ipairs(rows) do if r:IsShown() then list[#list + 1] = r end end
    p.nexts = list
  end
  return p
end

--- what the window shows, for /bofg report and tests: { key, text, detail, kind } in screen order
function Window.Lines()
  local out = {}
  for _, x in ipairs(shown) do
    out[#out + 1] = { key = x.key, text = plain(x.text), detail = plain(x.detail), kind = x.kind, stop = plain(x.stop) }
  end
  return out
end
