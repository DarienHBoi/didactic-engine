-- Bind on Forever Guide: the drowning warning (the RestedXP audit, Oct 18). Below a fifth of your breath the screen's
-- edges glow red and a warning sounds once; it clears when you surface. The game's breath timer (MIRROR_TIMER_*,
-- GetMirrorTimerProgress) can be secret to addons: then nothing shows. Setting: settings.breath.
local _, ns = ...
local Breath = {}
ns.Breath = Breath

local LOW = 0.2          -- a fifth of your breath left
local glow, ticker, maxValue, warned

local function show(on)
  if on and not glow then
    glow = CreateFrame('Frame', 'BoFGuideBreathGlow', UIParent)
    glow:SetAllPoints(UIParent)
    glow:SetFrameStrata('FULLSCREEN_DIALOG')
    glow:EnableMouse(false)
    local t = glow:CreateTexture(nil, 'BACKGROUND')
    t:SetAllPoints()
    t:SetTexture('Interface/FullScreenTextures/LowHealth')
    t:SetVertexColor(1, 0.15, 0.1)
    t:SetBlendMode('ADD')
    glow.tex = t
    if glow.CreateAnimationGroup then
      local ag = glow:CreateAnimationGroup()
      ag:SetLooping('BOUNCE')
      local a = ag:CreateAnimation('Alpha')
      a:SetFromAlpha(1)
      a:SetToAlpha(0.35)
      a:SetDuration(0.6)
      glow.pulse = ag
    end
  end
  if not glow then return end
  glow:SetShown(on)
  if glow.pulse then
    if on and not glow.pulse:IsPlaying() then glow.pulse:Play() elseif not on then glow.pulse:Stop() end
  end
end

--- how much breath is left, 0 to 1, or nil when the game doesn't say
function Breath.Left()
  local now = GetMirrorTimerProgress and ns.clean(GetMirrorTimerProgress('BREATH'))
  if not (now and maxValue and maxValue > 0) then return nil end
  return now / maxValue
end

local function check()
  local left = Breath.Left()
  local low = left ~= nil and left <= LOW and ns.settings and ns.settings.breath == true
  show(low)
  if low and not warned then
    warned = true
    -- (its own switch only: "Pop-up sound" is the done plate's chime, and muted this too; the QA pass, Oct 20)
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING or 8959, 'Master') end
  elseif not low then
    warned = false
  end
end

local function stop()
  if ticker then ticker:Cancel() ticker = nil end
  maxValue, warned = nil, false
  show(false)
end

ns.On('MIRROR_TIMER_START', function(name, value, max)
  if ns.clean(name) ~= 'BREATH' then return end
  maxValue = ns.clean(max)
  if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(0.5, function() ns.safecall('breath', check) end) end
  check()
end)
ns.On('MIRROR_TIMER_STOP', function(name)
  if ns.clean(name) == 'BREATH' then stop() end
end)
ns.On('PLAYER_DEAD', stop)
