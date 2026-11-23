-- The pieces around the window:
--   Options  a page in the game's own Settings (Esc > Options > AddOns > Bind on Forever Guide), built with the
--            Settings API, so it looks and works like every other options page
--   Minimap  the seal on the minimap's edge (drag to move it round; click: show or hide the guide; right-click: menu),
--            and the same in the addon compartment
--   Toast    the done plate: slides in when a quest is handed in or ready to hand in, with a quiet sound
--   Look     the size and look panel (seal menu > Size and look...): live sliders for the window, the arrow, the
--            text and the background
local _, ns = ...

local L = ns.L
local Skin = ns.Skin
local C = Skin.C

-- ------------------------------------------------------------------------------------------------------- options
local Options = {}
ns.Options = Options

local function setting(category, key, kind, name, default, tip, onChange, tbl, var)
  local s = Settings.RegisterAddOnSetting(category, var or ('BoFGuide_' .. key), key, tbl or ns.settings, kind, name,
    default)
  if s and s.SetValueChangedCallback and onChange then s:SetValueChangedCallback(function() onChange() end) end
  return s
end

function Options.Register()
  if Options.category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local category = Settings.RegisterVerticalLayoutCategory('Bind on Forever Guide')
  local redraw = function() ns.MarkDirty('settings') end
  -- the page grouped by topic, in this order (the QA pass, Oct 20: 29 controls in the order they were built). No
  -- section headings: they'd be initializers of our own on Blizzard's page, which the Oct 15 rule keeps out (the test
  -- test_the_settings_page_adds_no_initializers_of_its_own)
  local function check(key, name, tip, onChange, tbl, var, default)
    local s = setting(category, key, type(true), name, default == nil and ns.DEFAULTS[key] or default, tip,
      onChange or redraw, tbl, var)
    if s and Settings.CreateCheckbox then Settings.CreateCheckbox(category, s, tip) end
  end
  local function slider(key, name, tip, lo, hi, step, fmt, onChange)
    local s = setting(category, key, type(1), name, ns.DEFAULTS[key], tip, onChange or redraw)
    if s and Settings.CreateSlider and Settings.CreateSliderOptions then
      local o = Settings.CreateSliderOptions(lo, hi, step)
      if o.SetLabelFormatter and MinimalSliderWithSteppersMixin then
        o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
      end
      Settings.CreateSlider(category, s, o, tip)
    end
  end
  local function dropdown(key, name, tip, keys, labels, onChange)
    local s = setting(category, key, type(''), name, ns.DEFAULTS[key], tip, onChange or redraw)
    if s and Settings.CreateDropdown and Settings.CreateControlTextContainer then
      Settings.CreateDropdown(category, s, function()
        local c = Settings.CreateControlTextContainer()
        for _, k in ipairs(keys) do c:Add(k, labels[k]) end
        return c:GetData()
      end, tip)
    end
  end
  local pct = function(v) return ('%d%%'):format(v * 100 + 0.5) end

  dropdown('hc', L.optHardcore, L.optHardcoreTip, { 'auto', 'on', 'off' }, L.HC_MODES,
    function() ns.State.Player() ns.MarkDirty('hc') end)
  dropdown('groupQuests', L.optGroupQuests, L.optGroupQuestsTip, { 'party', 'always', 'never' }, L.GROUP_QUESTS,
    function() ns.MarkDirty('group') end)
  check('dungeons', L.optDungeons, L.optDungeonsTip, function() ns.MarkDirty('dungeons') end)

  local autoDefaults = ns.DEFAULTS.auto or {}
  for _, k in ipairs({ 'accept', 'turnin', 'gossip', 'taxi' }) do
    check(k, L.AUTO[k], L.optAutoTip, function() if ns.Window.Header then ns.Window.Header() end end,
      ns.settings.auto, 'BoFGuide_auto_' .. k, autoDefaults[k] ~= false)
  end
  check('readNew', L.optReadNew, L.optReadNewTip)
  check('sellGrays', L.optSellGrays, L.optSellGraysTip)

  check('breath', L.optBreath, L.optBreathTip)
  check('rareAlert', L.optRareAlert, L.optRareAlertTip)
  check('airTimer', L.optAirTimer, L.optAirTimerTip)
  check('dangerMap', L.optDangerMap, L.optDangerMapTip)
  check('nextMap', L.optNextMap, L.optNextMapTip)

  check('collapsed', L.optCollapsed, L.optCollapsedTip)
  check('locked', L.optLocked, L.optLockedTip)
  check('combatFade', L.optCombatFade, L.optCombatFadeTip)
  check('storyOpen', L.optStoryOpen, L.optStoryOpenTip, function() ns.Window.ResetStories() redraw() end)
  check('toasts', L.optToasts, L.optToastsTip)
  check('sounds', L.optSounds, L.optSoundsTip)
  check('minimap', L.optMinimap, L.optMinimapTip, function() ns.MinimapButton.Apply() end)
  slider('upcoming', L.optUpcoming, L.optUpcomingTip, 0, 8, 1, function(v) return ('%d'):format(v) end)

  check('arrow', L.optArrow, L.optArrowTip, function() ns.Arrow.Set(ns.Arrow.target) end)
  check('arrowText', L.arrowText, L.optArrowTextTip, function() ns.Arrow.ApplyLook() end)
  local looks = {}
  for _, look in ipairs(ns.Arrow.LOOKS) do looks[look] = L.ARROW_LOOKS[look] end
  dropdown('arrowLook', L.arrowStyle, L.optArrowStyleTip, ns.Arrow.LOOKS, looks, function() ns.Arrow.ApplyLook() end)

  check('targets', L.optTargets, L.optTargetsTip, function() ns.Panels.Targets({}) redraw() end)
  check('items', L.optItems, L.optItemsTip, function() ns.Panels.Want({}) redraw() end)

  slider('scale', L.optScale, L.optScaleTip, ns.Window.SCALE[1], ns.Window.SCALE[2], 0.01, pct,
    function() ns.Window.SetScale(ns.settings.scale) end)
  slider('width', L.optWidth, L.optWidthTip, 280, 480, 10, function(v) return ('%d'):format(v) end)
  slider('textScale', L.lookText, L.optTextTip, 0.7, 1.5, 0.05, pct, function() ns.Look.ApplyText() end)
  slider('opacity', L.optOpacity, L.optOpacityTip, 0, 1, 0.02, pct, function() ns.Window.SetOpacity(ns.settings.opacity) end)
  slider('arrowScale', L.optArrowScale, L.optArrowScaleTip, ns.Arrow.SCALE[1], ns.Arrow.SCALE[2], 0.01, pct,
    function() ns.Arrow.SetScale(ns.settings.arrowScale) end)
  slider('panelScale', L.optPanelScale, L.optPanelScaleTip, ns.Panels.SCALE[1], ns.Panels.SCALE[2], 0.01, pct,
    function() ns.Panels.SetScale(ns.settings.panelScale) end)
  -- (no "Clean up my quest log" button here: added to the page's layout, it ran in the Settings search, and typing
  -- "nam" got BoFGuide blamed for Discord's IsUserOAuthed() in the results, 38 times; the owner, Oct 15. The clean-up
  -- is on the seal's menu and /bofg cleanup)
  -- "Add a purchased guide": a subpage drawn as our own panel. A button on Blizzard's searchable page runs in the
  -- Settings search (the clean-up button, Oct 15); a canvas page doesn't. The same place RestedXP keeps its import
  -- (owner, Oct 16: no slash commands to remember)
  if Settings.RegisterCanvasLayoutSubcategory then
    local page = CreateFrame('Frame')
    local head = Skin.String(page, 'Heading', 'OVERLAY', C.gold)
    head:SetPoint('TOPLEFT', page, 'TOPLEFT', 16, -16)
    head:SetText(ns.upper(L.importTitle))
    local words = Skin.String(page, 'Text', 'OVERLAY', C.text)
    words:SetPoint('TOPLEFT', head, 'BOTTOMLEFT', 0, -12)
    words:SetWidth(520)
    words:SetJustifyH('LEFT')
    words:SetText(L.importSettings)
    local open = Skin.Button(page, 220, 28, L.importOpen, function()
      if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
          if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
          ns.Import.Show()
        end)
      else
        ns.Import.Show()
      end
    end, 'BoFGuideSettingsImport')
    open.text:SetFontObject(Skin.Font.Button)
    open:SetWidth(math.max(220, (open.text:GetStringWidth() or 0) + 48))
    open:SetPoint('TOPLEFT', words, 'BOTTOMLEFT', -2, -16)
    Options.importPage = Settings.RegisterCanvasLayoutSubcategory(category, page, L.importOpen:gsub('%.%.%.$', ''))
  end
  Settings.RegisterAddOnCategory(category)
  Options.category = category
  -- whatever changed on the page shows as soon as it closes (each setting also applies the moment it's changed)
  if SettingsPanel and SettingsPanel.HookScript then SettingsPanel:HookScript('OnHide', redraw) end
end

function Options.Open()
  Options.Register()
  if Options.category and Settings.OpenToCategory then
    Settings.OpenToCategory(Options.category.GetID and Options.category:GetID() or Options.category)
  end
end

-- ------------------------------------------------------------------------------------------------------- minimap
local Minimap_ = {}
ns.MinimapButton = Minimap_
local RADIUS_PAD = 10

local function place(b)
  local a = math.rad(ns.settings.minimapAngle or 215)
  local r = (Minimap:GetWidth() or 140) / 2 + RADIUS_PAD
  b:ClearAllPoints()
  b:SetPoint('CENTER', Minimap, 'CENTER', math.cos(a) * r, math.sin(a) * r)
end

local function menu(owner) ns.Window.Menu(owner) end

function Minimap_.Create()
  if Minimap_.button or not Minimap then return end
  local b = CreateFrame('Button', 'BoFGuideMinimapButton', Minimap)
  b:SetSize(32, 32)
  b:SetFrameStrata('MEDIUM')
  b:SetFrameLevel(8)
  b:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  b:RegisterForDrag('LeftButton')
  b.seal = Skin.Tex(b, 'seal', 'ARTWORK')
  b.seal:SetSize(21, 21)
  b.seal:SetPoint('CENTER', b, 'CENTER', 0, 0)
  b.ring = Skin.Tex(b, 'ring', 'OVERLAY')
  b.ring:SetAllPoints(b)
  b.glow = Skin.Tex(b, 'glow', 'BACKGROUND')
  b.glow:SetSize(44, 44)
  b.glow:SetPoint('CENTER', b, 'CENTER', 0, 0)
  b.glow:SetAlpha(0)
  b:SetScript('OnClick', function(self, button)
    if button == 'RightButton' then return menu(self) end
    ns.Window.Toggle()
  end)
  b:SetScript('OnEnter', function(self)
    self.glow:SetAlpha(0.35)
    if GameTooltip then
      GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
      GameTooltip:AddLine('Bind on Forever Guide', C.gold[1], C.gold[2], C.gold[3])
      GameTooltip:AddLine(L.minimapHelp, 0.85, 0.85, 0.85, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript('OnLeave', function(self) self.glow:SetAlpha(0) if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript('OnDragStart', function(self)
    self:SetScript('OnUpdate', function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      if mx and cx then ns.settings.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx)) % 360 place(self) end
    end)
  end)
  b:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
  place(b)
  b:SetShown(ns.settings.minimap ~= false)
  Minimap_.button = b
end

--- the setting changed: show or hide the seal (the window's own seal and the game's addon menu still open the guide)
function Minimap_.Apply()
  if Minimap_.button then Minimap_.button:SetShown(ns.settings.minimap ~= false) end
end

-- the addon compartment (the game's addon menu by the minimap), set in the .toc
function BoFGuide_OnAddonCompartmentClick(_, button)
  if button == 'RightButton' then return ns.Book.Open('questing') end
  ns.Window.Toggle()
end

-- --------------------------------------------------------------------------------------------------------- toast
local Toast = { queue = {} }
ns.Toast = Toast
-- on screen this long (held while the mouse is over it), then a slow fade; it slides down into place as it appears
local SHOW, FADE, IN, RISE, TOP = 4.5, 0.8, 0.3, 14, -190
local W, H = 360, 76
-- the plate's medallion, by what happened: the reward chest for a quest handed in, ? for one ready to hand in
local MEDALLION = { quest = 'med-reward', ready = 'face-turnin', step = 'face-quest' }
local plate

local function make()
  -- the painted plate (guides/art/guide-toast-1.png): ember light rising behind a bronze plaque. Its dark leather sits
  -- in the lower three quarters, so what's on it centres 11px below the plate's middle.
  plate = CreateFrame('Frame', 'BoFGuideToast', UIParent)
  plate:SetSize(W, H)
  plate:SetFrameStrata('HIGH')
  plate:SetPoint('TOP', UIParent, 'TOP', 0, TOP)
  plate:EnableMouse(true)
  plate.art = Skin.ThreeSlice(plate, 'toast', H, 50, 'BACKGROUND')
  plate.art:Place(plate, 0, 0, 0)
  plate.icon = Skin.Tex(plate, nil, 'ARTWORK')
  plate.icon:SetSize(38, 38)
  plate.icon:SetPoint('CENTER', plate, 'LEFT', 66, -11)
  plate.glow = Skin.Tex(plate, 'glow', 'BORDER')   -- the medallion lit from behind
  plate.glow:SetBlendMode('ADD')
  plate.glow:SetVertexColor(C.ember[1], C.ember[2], C.ember[3])
  plate.glow:SetSize(86, 86)
  plate.glow:SetPoint('CENTER', plate.icon, 'CENTER', 0, 0)
  plate.glow:SetAlpha(0.7)
  -- what happened, small; then the quest's name in the title face and gold
  plate.label = Skin.String(plate, 'ToastLabel', 'OVERLAY', C.goldSoft)
  plate.label:SetPoint('BOTTOMLEFT', plate.icon, 'RIGHT', 13, 2)
  plate.text = Skin.String(plate, 'ToastTitle', 'OVERLAY', C.gold)
  plate.text:SetPoint('TOPLEFT', plate.label, 'BOTTOMLEFT', 0, -3)
  plate.text:SetWidth(W - 66 - 19 - 13 - 48)   -- up to the plate's right curl
  plate.text:SetWordWrap(false)
  plate:SetScript('OnEnter', function(self) self.held = true self:SetAlpha(1) end)
  plate:SetScript('OnLeave', function(self) self.held = false end)
  plate:SetScript('OnMouseUp', function(self) if (self.t or 0) < SHOW then self.t = SHOW end end)   -- a click: fade now
  plate:Hide()
  plate:SetScript('OnUpdate', function(self, e)
    if self.held then return end
    self.t = (self.t or 0) + e
    local t, alpha, drop = self.t, 1, 0
    if t > SHOW + FADE then
      self:Hide()
      Toast.Next()
      return
    elseif t > SHOW then
      alpha = 1 - (t - SHOW) / FADE
    elseif t < IN then
      local k = t / IN
      alpha, drop = k, (1 - k) * (1 - k) * RISE   -- eases down into place
    end
    self:SetAlpha(alpha)
    self:ClearAllPoints()
    self:SetPoint('TOP', UIParent, 'TOP', 0, TOP + drop)
  end)
end

function Toast.Next()
  local item = table.remove(Toast.queue, 1)
  if not item then return end
  if not plate then make() end
  plate.icon:SetTexture(Skin.MEDIA .. (MEDALLION[item.kind] or 'face-quest'))
  plate.label:SetText(ns.upper(item.label or L.toastDone))
  plate.text:SetText(item.text or '')
  plate.t, plate.held = 0, false
  plate:SetAlpha(0)
  plate:Show()
  if ns.settings.sounds and PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or 0, 'SFX') end
end

--- something done: { kind = 'quest' | 'ready' | 'step', label, text }
function Toast.Show(item)
  if not (ns.settings and ns.settings.toasts) then return end
  if #Toast.queue >= 3 then table.remove(Toast.queue, 1) end
  Toast.queue[#Toast.queue + 1] = item
  if not (plate and plate:IsShown()) then Toast.Next() end
end

function Toast.Shown() return plate and plate:IsShown() and plate.text:GetText() or nil end

-- ---------------------------------------------------------------------------------------------- size and look
local Look = {}
ns.Look = Look
local panel

--- re-make the fonts at the new text size and lay the window out again
function Look.ApplyText()
  Skin.Fonts()
  Look.Layout()
  ns.MarkDirty('settings')
end

--- one slider: the painted bar as its track, a rivet for its thumb, the value as a percentage; it applies as you drag
local function slider(parent, i, label, lo, hi, get, set)
  local y = -52 - (i - 1) * 50
  local name = Skin.String(parent, 'Label', 'OVERLAY', C.gold)
  name:SetPoint('TOPLEFT', parent, 'TOPLEFT', 22, y)
  name:SetText(ns.upper(label))
  local value = Skin.String(parent, 'Small', 'OVERLAY', C.text)
  value:SetPoint('TOPRIGHT', parent, 'TOPRIGHT', -22, y)
  value:SetJustifyH('RIGHT')
  local s = CreateFrame('Slider', nil, parent)
  s:SetOrientation('HORIZONTAL')
  s:SetHeight(18)
  s:SetPoint('TOPLEFT', parent, 'TOPLEFT', 20, y - 16)
  s:SetPoint('TOPRIGHT', parent, 'TOPRIGHT', -20, y - 16)
  s.track = Skin.ThreeSlice(s, 'bar-track', 12, 12, 'BACKGROUND')
  s.track:Place(s, 0, 0, -3)
  local thumb = s:CreateTexture(nil, 'OVERLAY')
  thumb:SetTexture(Skin.MEDIA .. 'rivet')   -- (it was the empty checkbox, which read as a checkbox; Oct 20)
  thumb:SetSize(16, 16)
  s:SetThumbTexture(thumb)
  s:SetMinMaxValues(lo, hi)
  s:SetValueStep(0.01)
  s:SetObeyStepOnDrag(true)
  s:EnableMouseWheel(true)
  s:SetScript('OnMouseWheel', function(self, delta) self:SetValue((self:GetValue() or lo) + delta * 0.05) end)
  s:SetScript('OnValueChanged', function(_, v)
    v = set(v) or v
    value:SetText(('%d%%'):format(v * 100 + 0.5))
  end)
  s.refresh = function() s:SetValue(get()) value:SetText(('%d%%'):format(get() * 100 + 0.5)) end
  s.name, s.value = name, value
  return s
end

function Look.Create()
  if panel then return panel end
  panel = CreateFrame('Frame', 'BoFGuideLook', UIParent)
  ns.Escapable(panel)
  panel:SetSize(300, 272)
  panel:SetFrameStrata('DIALOG')
  panel:SetPoint('CENTER', UIParent, 'CENTER', 0, 60)
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag('LeftButton')
  panel:SetScript('OnDragStart', panel.StartMoving)
  panel:SetScript('OnDragStop', panel.StopMovingOrSizing)
  panel.skin = Skin.Panel(panel)
  local head = Skin.String(panel, 'Heading', 'OVERLAY', C.gold)
  head:SetPoint('TOPLEFT', panel, 'TOPLEFT', 22, -20)
  head:SetText(ns.upper(L.lookTitle))
  panel.head = head
  local close = Skin.IconButton(panel, 18, 'btn-close', function() panel:Hide() end, 'BoFGuideLookClose')
  close:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', -20, -18)
  local st = ns.settings
  panel.sliders = {
    window = slider(panel, 1, L.lookWindow, ns.Window.SCALE[1], ns.Window.SCALE[2],
      function() return st.scale or 1 end, ns.Window.SetScale),
    arrow = slider(panel, 2, L.lookArrow, ns.Arrow.SCALE[1], ns.Arrow.SCALE[2],
      function() return st.arrowScale or 1 end, ns.Arrow.SetScale),
    panels = slider(panel, 3, L.lookPanels, ns.Panels.SCALE[1], ns.Panels.SCALE[2],
      function() return st.panelScale or 1 end, ns.Panels.SetScale),
    text = slider(panel, 4, L.lookText, 0.7, 1.5, function() return st.textScale or 1 end, function(v)
      v = math.floor(v * 100 + 0.5) / 100
      if v ~= st.textScale then st.textScale = v Look.ApplyText() end
      return v
    end),
    background = slider(panel, 5, L.lookBackground, 0, 1, function() return st.opacity or 0.6 end, ns.Window.SetOpacity),
  }
  local help = Skin.String(panel, 'Small', 'OVERLAY', C.faint)
  help:SetPoint('TOPLEFT', panel.sliders.background, 'BOTTOMLEFT', 2, -16)
  help:SetWidth(256)
  help:SetJustifyH('LEFT')
  help:SetText(L.lookHelp)
  panel.help = help
  panel:Hide()
  return panel
end

--- the panel's size: as wide as its longest slider name and its value side by side (and the title beside the close
--- button: German at 150% text ran "Größe von Zielen und Gegenständen" into its 100%, Oct 16), then as tall as the
--- sliders and the help text under them (it grows with the text size). Measured once shown
function Look.Layout()
  if not panel then return end
  panel.help:SetFontObject(Skin.Font.Small)
  local w = math.max(300, (panel.head:GetStringWidth() or 0) + 22 + 50)
  for _, s in pairs(panel.sliders) do
    w = math.max(w, 22 + (s.name:GetStringWidth() or 0) + 16 + math.max(s.value:GetStringWidth() or 0, 36) + 22)
  end
  panel:SetWidth(w)
  panel.help:SetWidth(w - 44)
  panel:SetHeight(52 + 4 * 50 + 16 + 18 + 16 + (panel.help:GetStringHeight() or 24) + 24)   -- five sliders
end

function Look.Show()
  Look.Create()
  for _, s in pairs(panel.sliders) do s.refresh() end
  Look.Layout()
  panel:Show()
  Look.Layout()
  if C_Timer and C_Timer.After then C_Timer.After(0, function() if panel:IsShown() then Look.Layout() end end) end
end

function Look.Sliders() Look.Create() return panel.sliders end
