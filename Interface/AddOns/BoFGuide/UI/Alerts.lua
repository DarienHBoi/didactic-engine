-- Bind on Forever Guide: two Hardcore aids from the RestedXP audit (Oct 18).
--   Walk on Air (the Skyborne racial, a 10 second glide): a bar with the seconds left, red with one warning sound in
--     its last 3; falling when it ends can kill a Hardcore character. Read from your own aura (C_UnitAuras), which the
--     game may keep secret: then no bar. Setting: settings.airTimer.
--   A rare's nameplate: named once in chat, with a sound (UnitClassification on the nameplate unit, which Forever
--     doesn't keep secret; the name can be, so it falls back to "a rare creature"). Setting: settings.rareAlert.
-- (A low-health highlight isn't possible: Forever keeps UnitHealth secret from addons. Blizzard's own red glow stays.)
local _, ns = ...
local Alerts = {}
ns.Alerts = Alerts

local WALK_ON_AIR = 1259416
local WARN_AT = 3

-- (a warning's sound follows its own switch, not "Pop-up sound", which is the done plate's chime; the QA pass, Oct 20)
local function sound(kit)
  if PlaySound and SOUNDKIT then PlaySound(kit or 8959, 'Master') end
end

-- ------------------------------------------------------------------------------------------------------ Walk on Air
local bar, airTicker, airWarned

local function makeBar()
  if bar then return bar end
  -- in the guide's own look: the painted bar's track and fill, the guide's lettering (it was a plain game bar; Oct 20)
  local Skin = ns.Skin
  bar = CreateFrame('StatusBar', 'BoFGuideAirBar', UIParent)
  bar:SetSize(220, 14)
  bar:SetPoint('TOP', UIParent, 'TOP', 0, -170)
  bar:SetFrameStrata('HIGH')
  bar:SetMinMaxValues(0, 10)
  bar:SetStatusBarTexture(Skin.MEDIA .. 'bar-fill-m')
  bar:SetStatusBarColor(0.94, 0.76, 0.35)
  local bg = bar:CreateTexture(nil, 'BACKGROUND')
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.55)
  bar.track = Skin.ThreeSlice(bar, 'bar-track', 14, 12, 'BACKGROUND', 1)
  bar.track:Place(bar, -4, 4, 0)
  bar.text = Skin.String(bar, 'Small', 'OVERLAY', Skin.C.text)
  bar.text:SetJustifyH('CENTER')
  bar.text:SetPoint('BOTTOM', bar, 'TOP', 0, 3)
  bar:Hide()
  return bar
end

--- seconds of Walk on Air left, or nil (not gliding, or the game keeps it secret)
function Alerts.AirLeft()
  local a = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(WALK_ON_AIR)
  if not a then return nil end
  local ends, dur = ns.clean(a.expirationTime), ns.clean(a.duration)
  if not ends or ends == 0 then return nil end
  local left = ends - GetTime()
  if left <= 0 then return nil end
  return left, dur
end

local function airTick()
  local left, dur = Alerts.AirLeft()
  if not left or ns.settings.airTimer == false then
    if bar then bar:Hide() end
    if airTicker then airTicker:Cancel() airTicker = nil end
    airWarned = false
    return
  end
  makeBar()
  bar:SetMinMaxValues(0, dur and dur > 0 and dur or 10)
  bar:SetValue(left)
  local low = left <= WARN_AT
  bar:SetStatusBarColor(low and 1 or 0.94, low and 0.25 or 0.76, low and 0.2 or 0.35)
  local tc = low and ns.Skin.C.danger or ns.Skin.C.text
  bar.text:SetTextColor(tc[1], tc[2], tc[3])
  bar.text:SetText(ns.count('airLeft', math.ceil(left)))
  bar:Show()
  if low and not airWarned then airWarned = true sound(SOUNDKIT and SOUNDKIT.RAID_WARNING) end
end

ns.On('UNIT_AURA', function(unit)
  if unit ~= 'player' then return end
  if Alerts.AirLeft() and not airTicker and C_Timer and C_Timer.NewTicker then
    airTicker = C_Timer.NewTicker(0.1, function() ns.safecall('air', airTick) end)
  end
  airTick()
end)

-- ------------------------------------------------------------------------------------------------------- rare alert
local seen = {}   -- [guid or name] = time said

ns.On('NAME_PLATE_UNIT_ADDED', function(unit)
  if not unit or ns.settings.rareAlert == false then return end
  local class = ns.clean(UnitClassification and UnitClassification(unit))
  if class ~= 'rare' and class ~= 'rareelite' then return end
  if UnitIsDead and ns.clean(UnitIsDead(unit)) then return end
  if UnitCanAttack and ns.clean(UnitCanAttack('player', unit)) == false then return end
  local name = ns.clean(UnitName(unit))
  local key = ns.clean(UnitGUID(unit)) or name or 'rare'
  local now = GetTime()
  if seen[key] and now - seen[key] < 300 then return end   -- (once in five minutes for the same one)
  seen[key] = now
  local level = ns.clean(UnitLevel(unit))
  local who = name and (level and level > 0 and ns.L.rareNamed:format(name, level) or name) or ns.L.rareSomeone
  ns.say((class == 'rareelite' and ns.L.rareEliteNear or ns.L.rareNear):format(who))
  sound(SOUNDKIT and SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING)
end)

-- your bags are full: said once a minute at most (Nov 8, the RestedXP items study: a quest drop that won't loot and a
-- buy that doesn't fit got no word from the guide)
local bagsSaid = -60
ns.On('UI_ERROR_MESSAGE', function(_, msg)
  msg = ns.clean(msg)
  if msg ~= (ERR_INV_FULL or 'Inventory is full.') or GetTime() - bagsSaid < 60 then return end
  bagsSaid = GetTime()
  ns.say(ns.L.bagsFull)
end)

-- an elite near you, in Hardcore mode (Nov 8, the RestedXP death/Hardcore study: no live warning when an elite came
-- near). The same nameplate read as the rare alert; outside a dungeon, one you could lose a fight to (no more than 3
-- levels below you), once per creature in five minutes and one alert in 30 seconds, so an elite camp isn't a stream
local eliteSeen, eliteLast = {}, 0
ns.On('NAME_PLATE_UNIT_ADDED', function(unit)
  if not unit or ns.settings.rareAlert == false or not (ns.st and ns.st.hc) then return end
  if IsInInstance and ns.clean(IsInInstance()) then return end
  local class = ns.clean(UnitClassification and UnitClassification(unit))
  if class ~= 'elite' and class ~= 'worldboss' then return end
  if UnitIsDead and ns.clean(UnitIsDead(unit)) then return end
  if UnitCanAttack and ns.clean(UnitCanAttack('player', unit)) == false then return end
  local level = ns.clean(UnitLevel(unit))
  local mine = ns.clean(UnitLevel('player')) or 1
  if level and level > 0 and level < mine - 3 then return end
  local name = ns.clean(UnitName(unit))
  local key = ns.clean(UnitGUID(unit)) or name or 'elite'
  local now = GetTime()
  if (eliteSeen[key] and now - eliteSeen[key] < 300) or now - eliteLast < 30 then return end
  eliteSeen[key], eliteLast = now, now
  local who = name and (level and level > 0 and ns.L.rareNamed:format(name, level) or name) or ns.L.eliteSomeone
  ns.say(ns.L.eliteNear:format(who))
  sound(SOUNDKIT and SOUNDKIT.RAID_WARNING)
end)
