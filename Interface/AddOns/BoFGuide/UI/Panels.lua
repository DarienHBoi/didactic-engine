-- Two small panels of their own, in the window's look, each moved and sized on its own: drag one to move it, scroll
-- over it to make it bigger or smaller ("Lock the window" in the settings locks them too).
--   Targets      a round socket for each person and enemy the steps on screen name: click one to target them (a
--                /targetexact macro, so no target scanning). Until the game has drawn that creature for you (your
--                target, your mouseover or a nameplate) a medallion says what they are: ! a quest giver, ? a turn-in,
--                the vendor's coins, the trainer's book, the inn's mug, crossed swords an enemy, a skull an elite.
--                Enemies' rings glow red.
--   Quest Items  the quest items the steps on screen need, in bronze frames: click one to use it.
-- Their buttons are the game's secure action buttons, so a click works in combat; the game doesn't let addons change
-- them in a fight, so a change that comes up mid-fight waits for PLAYER_REGEN_ENABLED. The same goes for showing,
-- hiding, moving and sizing the panels (a frame holding secure buttons is locked in combat too).
local _, ns = ...

local Panels = {}
ns.Panels = Panels
ns.ItemBar = Panels   -- the name the engine and the tests have used since 0.5
local L = ns.L
local Skin = ns.Skin
local C = Skin.C
local MAX_TARGETS, MAX_ITEMS = 6, 4
local SIZE, RING, GAP, PAD, CORNER = 36, 1.32, 14, 15, 16   -- socket, ring over it, between sockets, inside, frame
local TAB_H = 27

local targets, items          -- the two panels
local targetBtns, itemBtns = {}, {}
local wantTargets, hasTargets, pendingTargets = nil, {}, nil
local killTargets = {}   -- every target the steps name, the panel shown or not (the skull's list)
local hasItems, pendingItems = {}, nil
local portraits = {}          -- name -> a texture the game drew that creature's portrait into (this session)
local holder                  -- a hidden frame the portraits wait on while no socket shows them
local dock                    -- where the panels hang under the window (Panels.Dock)

Panels.SCALE = { 0.5, 2 }
local FACES = { quest = 'face-quest', turnin = 'face-turnin', vendor = 'face-vendor', trainer = 'face-trainer',
                inn = 'face-inn', flight = 'face-flight', enemy = 'med-kill', elite = 'med-danger' }

local function count(id)
  local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id))
  return ns.clean(n) or 0
end

local function locked() return ns.settings.locked or InCombatLockdown() end

local function savePosition(f)
  local point, _, rel, x, y = f:GetPoint()
  if point then ns.db.frames[f.key] = { point, rel, x, y } end
end

--- both panels' size (settings.panelScale), from the Size and look panel, the settings page or the mouse wheel
function Panels.SetScale(v)
  v = math.max(Panels.SCALE[1], math.min(Panels.SCALE[2], math.floor(v * 100 + 0.5) / 100))
  ns.settings.panelScale = v
  if targets and not InCombatLockdown() then targets:SetScale(v) items:SetScale(v) end
  return v
end

--- how solid the stone behind the sockets is: the window's Background opacity, so the three read as one set
function Panels.SetOpacity(v)
  for _, f in ipairs({ targets, items }) do
    if f then f.skin.bg:SetAlpha(v) f.skin.shade:SetAlpha(v) end
  end
end

--- a panel: the window's stone and bronze, a title tab riding its top edge (like RestedXP's), moved by a drag
--- anywhere on it and sized by the mouse wheel
local function panel(name, key, title, help, place)
  local f = CreateFrame('Frame', name, UIParent)
  f.key = key
  f:SetSize(PAD * 2 + SIZE, PAD * 2 + SIZE)
  f:SetFrameStrata('MEDIUM')
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag('LeftButton')
  f:SetScript('OnDragStart', function(self) if not locked() then self:StartMoving() end end)
  f:SetScript('OnDragStop', function(self) self:StopMovingOrSizing() savePosition(self) end)
  f:EnableMouseWheel(true)
  f:SetScript('OnMouseWheel', function(_, delta)
    if locked() then return end
    Panels.SetScale((ns.settings.panelScale or 1) + delta * 0.05)
  end)
  f.tip = { title, help, { L.panelHelp, 0.65, 0.65, 0.65 } }
  f:SetScript('OnEnter', function(self) Skin.Tooltip(self, self.tip, 'ANCHOR_TOP') end)
  f:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  f.skin = Skin.Panel(f, { corner = CORNER, glow = false })
  -- the title tab: the window's nameplate in small, half over the top edge
  f.tab = CreateFrame('Frame', nil, f)
  f.tab:SetHeight(TAB_H)
  f.tab:SetPoint('BOTTOMLEFT', f, 'TOPLEFT', 12, -11)
  f.tab:SetFrameLevel(f:GetFrameLevel() + 4)
  f.tab.plate = Skin.ThreeSlice(f.tab, 'header', TAB_H, 18, 'ARTWORK')
  f.tab.plate:Place(f.tab, 0, 0, 0)
  f.tab.text = Skin.String(f.tab, 'Tab', 'OVERLAY', C.gold)
  f.tab.text:SetPoint('CENTER', f.tab, 'CENTER', 0, 0)
  f.tab.text:SetText(ns.upper(title))
  f.tab:SetWidth(math.floor((f.tab.text:GetStringWidth() or 60) + 40))
  f.tab:EnableMouse(true)
  f.tab:RegisterForDrag('LeftButton')
  f.tab:SetScript('OnDragStart', function() if not locked() then f:StartMoving() end end)
  f.tab:SetScript('OnDragStop', function() f:StopMovingOrSizing() savePosition(f) end)
  f.tab:EnableMouseWheel(true)
  f.tab:SetScript('OnMouseWheel', f:GetScript('OnMouseWheel'))
  f.tab:SetScript('OnEnter', function() Skin.Tooltip(f.tab, f.tip, 'ANCHOR_TOP') end)
  f.tab:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
  local pos = ns.db.frames[key]
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else place(f) end
  f:SetScale(ns.settings.panelScale or 1)
  f:Hide()
  return f
end

--- a drag that starts on a button moves its panel; the wheel over it sizes the panel
local function carry(b)
  b:RegisterForDrag('LeftButton')
  b:SetScript('OnDragStart', function(self) local p = self:GetParent() if not locked() then p:StartMoving() end end)
  b:SetScript('OnDragStop', function(self) local p = self:GetParent() p:StopMovingOrSizing() savePosition(p) end)
  b:EnableMouseWheel(true)
  b:SetScript('OnMouseWheel', function(self, delta) self:GetParent():GetScript('OnMouseWheel')(self:GetParent(), delta) end)
end

--- where the n-th button sits: a row inside the frame, the ring's overhang inside the padding
local function slot(f, b, i)
  b:SetPoint('TOPLEFT', f, 'TOPLEFT', PAD + (i - 1) * (SIZE + GAP), -PAD)
end

--- the spot under the guide window the panels hang from when they haven't been moved. It's a frame of its own, set on
--- the screen where the window's bottom left corner is, and never anchored to the window: the game locks whatever a
--- secure button hangs on in a fight, and the window has to grow and shrink then (FB-018: "the game blocked
--- BoFGuideFrame:SetWidth()" mid-fight, and automation paused). Out of a fight it follows the window again.
function Panels.Dock()
  if not dock or InCombatLockdown() then return end
  local w = BoFGuideFrame
  local l, b = w and w:GetLeft(), w and w:GetBottom()
  dock:ClearAllPoints()
  if l and b then
    local s = (w:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    dock:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', l * s, b * s)
  else
    dock:SetPoint('TOPLEFT', UIParent, 'CENTER', 0, 0)
  end
end

function Panels.Create()
  if targets then return end
  holder = CreateFrame('Frame', nil, UIParent)
  holder:Hide()
  dock = CreateFrame('Frame', nil, UIParent)
  dock:SetSize(1, 1)
  Panels.Dock()
  targets = panel('BoFGuideTargets', 'targets', L.targetsTitle, L.targetsHelp, function(f)
    f:SetPoint('TOPLEFT', dock, 'TOPLEFT', 0, -22)
  end)
  items = panel('BoFGuideItemBar', 'items', L.itemsTitle, L.itemsHelp, function(f)
    f:SetPoint('TOPLEFT', targets, 'BOTTOMLEFT', 0, -26)
  end)
  for i = 1, MAX_TARGETS do
    local b = CreateFrame('Button', i == 1 and 'BoFGuideTarget' or ('BoFGuideTarget' .. i), targets,
      'SecureActionButtonTemplate')
    b:SetSize(SIZE, SIZE)
    slot(targets, b, i)
    b:RegisterForClicks('AnyUp', 'AnyDown')
    b:SetAttribute('type', 'macro')
    carry(b)
    -- a hollow in the stone, the portrait or a medallion in it, the bronze ring over it
    b.well = Skin.Tex(b, 'disc', 'BACKGROUND')
    b.well:SetAllPoints(b)
    b.face = Skin.Tex(b, nil, 'ARTWORK')
    b.face:SetPoint('CENTER', b, 'CENTER', 0, 0)
    b.face:SetSize(SIZE * 0.96, SIZE * 0.96)
    b.ring = Skin.Tex(b, 'ring', 'OVERLAY')
    b.ring:SetPoint('CENTER', b, 'CENTER', 0, 0)
    b.ring:SetSize(SIZE * RING, SIZE * RING)
    b.halo = Skin.Tex(b, 'glow', 'BACKGROUND', -1)   -- an enemy's red light, behind the ring
    b.halo:SetBlendMode('ADD')
    b.halo:SetPoint('CENTER', b, 'CENTER', 0, 0)
    b.halo:SetSize(SIZE * 2.1, SIZE * 2.1)
    b.halo:SetVertexColor(C.red[1], C.red[2], C.red[3])
    b.halo:SetAlpha(0.55)
    b.hl = Skin.Tex(b, 'glow', 'HIGHLIGHT')
    b.hl:SetBlendMode('ADD')
    b.hl:SetPoint('CENTER', b, 'CENTER', 0, 0)
    b.hl:SetSize(SIZE * 2, SIZE * 2)
    b:SetScript('OnEnter', function(self)
      if not self.t then return end
      local c = self.t.enemy and C.red or C.text
      Skin.Tooltip(self, { { self.t.name, c[1], c[2], c[3] }, L.TARGET_ROLES[self.t.role] or L.targetPerson,
                           L.targetClick, not portraits[self.t.name] and { L.targetPortrait, 0.6, 0.6, 0.6 } or nil })
    end)
    b:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    b:Hide()
    targetBtns[i] = b
  end
  for i = 1, MAX_ITEMS do
    local b = CreateFrame('Button', 'BoFGuideItem' .. i, items, 'SecureActionButtonTemplate')
    b:SetSize(SIZE, SIZE)
    slot(items, b, i)
    b:RegisterForClicks('AnyUp', 'AnyDown')
    b:SetAttribute('type', 'item')
    carry(b)
    -- the item's icon (its own border trimmed) inside the bronze socket frame
    b.frame = Skin.Tex(b, 'check-empty', 'BACKGROUND')
    b.frame:SetPoint('CENTER', b, 'CENTER', 0, 0)
    b.frame:SetSize(SIZE * 1.22, SIZE * 1.22)
    b.icon = b:CreateTexture(nil, 'ARTWORK')
    b.icon:SetPoint('CENTER', b, 'CENTER', 0, 0)
    b.icon:SetSize(SIZE * 0.84, SIZE * 0.84)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.hl = Skin.Tex(b, 'glow', 'HIGHLIGHT')
    b.hl:SetBlendMode('ADD')
    b.hl:SetPoint('CENTER', b, 'CENTER', 0, 0)
    b.hl:SetSize(SIZE * 2, SIZE * 2)
    b.count = b:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
    b.count:SetPoint('BOTTOMRIGHT', b, 'BOTTOMRIGHT', -1, 1)
    b:SetScript('OnEnter', function(self)
      if not (self.itemID and GameTooltip) then return end
      GameTooltip:SetOwner(self, 'ANCHOR_TOP')
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
      GameTooltip:AddLine(L.itemClick, 0.6, 0.85, 0.6, true)
      GameTooltip:Show()
    end)
    b:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    b:Hide()
    itemBtns[i] = b
  end
  Panels.SetOpacity(ns.settings.opacity or 0.6)
end

--- the panel round n buttons, never narrower than its title tab
local function fit(f, n)
  local w = PAD * 2 + n * SIZE + math.max(n - 1, 0) * GAP
  f:SetWidth(math.max(w, (f.tab:GetWidth() or 0) + 28))
  f:SetHeight(PAD * 2 + SIZE)
end

-- --------------------------------------------------------------------------------------------------------- targets
--- the portrait for a name if the game has drawn it this session, else the medallion for what they are
local function dress(b)
  local t = b.t
  if b.portrait and b.portrait ~= portraits[t and t.name] then
    b.portrait:SetParent(holder) b.portrait:Hide() b.portrait = nil
  end
  local face = t and portraits[t.name]
  if face then
    face:SetParent(b)
    face:SetDrawLayer('ARTWORK', 1)
    face:ClearAllPoints()
    face:SetPoint('CENTER', b, 'CENTER', 0, 0)
    face:SetSize(SIZE * 0.9, SIZE * 0.9)
    face:Show()
    b.portrait = face
  end
  b.face:SetShown(not face)
  if t then
    b.face:SetTexture(Skin.MEDIA .. (FACES[t.role] or (t.enemy and FACES.enemy or FACES.quest)))
    -- an enemy's ring takes on its red light; a person's stays bronze
    if t.enemy then b.ring:SetVertexColor(1, 0.72, 0.62) else b.ring:SetVertexColor(1, 1, 1) end
    b.halo:SetShown(t.enemy)
  end
end

local function applyTargets(list)
  hasTargets = list
  for i = 1, MAX_TARGETS do
    local b, t = targetBtns[i], list[i]
    b.t = t
    if t then
      b:SetAttribute('macrotext', '/cleartarget\n/targetexact ' .. t.name)
      b:Show()
    else
      b:SetAttribute('macrotext', nil)
      b:Hide()
    end
    dress(b)
  end
  fit(targets, #list)
  targets:SetShown(#list > 0 and ns.settings.targets ~= false and ns.settings.shown ~= false)
end

local function sameList(a, b, key)
  if #a ~= #b then return false end
  for i = 1, #a do
    if key then
      if a[i][key] ~= b[i][key] or a[i].role ~= b[i].role then return false end
    elseif a[i] ~= b[i] then return false end
  end
  return true
end

--- the people and enemies to offer now: { { name, enemy, role, id }, ... } (at most 6, in order); applied at once out
--- of combat, after the fight otherwise
function Panels.Targets(list)
  Panels.Create()
  killTargets = list or {}
  local want = {}
  if ns.settings.targets ~= false then
    for _, t in ipairs(list or {}) do if #want < MAX_TARGETS and t.name then want[#want + 1] = t end end
  end
  wantTargets = want
  if sameList(want, hasTargets, 'name') then pendingTargets = nil return end
  if InCombatLockdown() then pendingTargets = want return end
  applyTargets(want)
end

--- one target (older callers): the same as a list of one
function Panels.Target(t) Panels.Targets(t and { t } or {}) end

--- a unit the game can draw (your target, your mouseover, a nameplate): keep its portrait if a target wants it
local function capture(unit)
  if not (unit and UnitExists and ns.clean(UnitExists(unit))) or not SetPortraitTexture then return end
  local name = ns.clean(UnitName and UnitName(unit))
  if not name or portraits[name] then return end
  local wanted = false
  for _, t in ipairs(wantTargets or {}) do if t.name == name then wanted = true break end end
  if not wanted then return end
  local tex = holder:CreateTexture(nil, 'ARTWORK')
  SetPortraitTexture(tex, unit)
  portraits[name] = tex
  for _, b in ipairs(targetBtns) do if b.t and b.t.name == name then dress(b) end end
end

-- no skull on the creature to kill (0.9.86 to 0.9.95): live Forever forbids SetRaidTarget to addons, and every try
-- put up the game's "blocked from an action only available to the Blizzard UI" box (the owner, launch day, Nov 4:
-- eight in Shadowglen, logged as forbidden UNKNOWN()). Raid markers are the player's to place
ns.On('PLAYER_TARGET_CHANGED', function() capture('target') end)
ns.On('UPDATE_MOUSEOVER_UNIT', function() capture('mouseover') end)
ns.On('NAME_PLATE_UNIT_ADDED', function(unit) capture(unit) end)

-- ----------------------------------------------------------------------------------------------------------- items
local function applyItems(list)
  hasItems = list
  for i = 1, MAX_ITEMS do
    local b, id = itemBtns[i], list[i]
    if id then
      b:SetAttribute('item', 'item:' .. id)
      b.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
      b.itemID = id
      b:Show()
    else
      b:SetAttribute('item', nil)
      b.itemID = nil
      b:Hide()
    end
  end
  fit(items, #list)
  items:SetShown(#list > 0 and ns.settings.items ~= false and ns.settings.shown ~= false)
end

--- the items to offer now (at most 4, in your bags); applied at once out of combat, after the fight otherwise
function Panels.Want(list)
  Panels.Create()
  local have = {}
  if ns.settings.items ~= false then
    for _, id in ipairs(list or {}) do
      if #have < MAX_ITEMS and count(id) > 0 then have[#have + 1] = id end
    end
  end
  for i = 1, MAX_ITEMS do   -- counts are plain text: fine to update in combat
    local b = itemBtns[i]
    if b.itemID then b.count:SetText(count(b.itemID) > 1 and tostring(count(b.itemID)) or '') end
  end
  if sameList(have, hasItems) then pendingItems = nil return end
  if InCombatLockdown() then pendingItems = have return end
  applyItems(have)
end

--- the guide window shown or hidden: the panels go with it (out of combat)
function Panels.Shown()
  if not targets or InCombatLockdown() then return end
  targets:SetShown(#hasTargets > 0 and ns.settings.targets ~= false and ns.settings.shown ~= false)
  items:SetShown(#hasItems > 0 and ns.settings.items ~= false and ns.settings.shown ~= false)
end

--- what the panels hold, for tests and /bofg report
function Panels.Items() return hasItems, pendingItems end
function Panels.TargetName() return hasTargets[1] and hasTargets[1].name or nil end
function Panels.TargetNames()
  local out = {}
  for _, t in ipairs(hasTargets) do out[#out + 1] = t.name end
  return out
end
function Panels.Portrait(name) return portraits[name] ~= nil end

ns.On('PLAYER_REGEN_ENABLED', function()
  if pendingTargets then
    local p = pendingTargets
    pendingTargets = nil
    applyTargets(p)
  end
  if pendingItems then
    local p = pendingItems
    pendingItems = nil
    applyItems(p)
  end
  if targets then Panels.SetScale(ns.settings.panelScale or 1) end
  Panels.Dock()                  -- (under the window again, as it grew or shrank in the fight)
  Panels.Shown()
end)
