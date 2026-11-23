-- The welcome window (owner, Oct 16): the first time the guide loads, before anything else, the player picks the
-- guide's language (their game's language preselected) and reads how the guide works in three lines. Reopened from
-- the seal's menu ("Language...") or /bofg language. Picking another language reloads the interface once.
--
-- The oath (owner, Oct 30): after the language, one painted tablet with the three choices that change how the guide
-- plays. How you quest comes first and loudest: reading every quest is the default, so a player who clicks straight
-- through must still see that automatic accept and turn-in exists and is off (the banner, the Seal button's page, then
-- the plate on the AUTO switch). Each choice is its setting at once; closing keeps them. Reopened from the seal's menu
-- ("Your oath...") or /bofg oath. Only a new install sees it unasked: everyone else keeps their settings.
local _, ns = ...

local Welcome = {}
ns.Welcome = Welcome
local L = ns.L
local Skin = ns.Skin
local C = Skin.C
local WIDTH, BODY = 720, 620            -- the window, and the column inside the frame's bars

local frame, title, langHead, langNote, start, oath, langPage
local buttons, how = {}, {}
local chosen
local firstRun = false
local entered = false
local SLAM, STAND, FADE = 0.28, 1.1, 0.55      -- the seal, in seconds: its fall, how long it stands, its fade
local SEAL_EMBERS = 14

-- ---------------------------------------------------------------------------------------------- the frame and stone
--- a thin line round a box, recolored when it's chosen
local function edges(box, c, a)
  box.edge = box.edge or {}
  for i, spec in ipairs({ { 'TOPLEFT', 'TOPRIGHT', 0, 1 }, { 'BOTTOMLEFT', 'BOTTOMRIGHT', 0, 1 },
                          { 'TOPLEFT', 'BOTTOMLEFT', 1, 0 }, { 'TOPRIGHT', 'BOTTOMRIGHT', 1, 0 } }) do
    local t = box.edge[i]
    if not t then
      t = box:CreateTexture(nil, 'OVERLAY', nil, 2)
      t:SetPoint(spec[1], box, spec[1], 0, 0)
      t:SetPoint(spec[2], box, spec[2], 0, 0)
      if spec[3] > 0 then t:SetWidth(spec[3]) else t:SetHeight(spec[4]) end
      box.edge[i] = t
    end
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
  end
end

--- never taller than the screen: a high UI scale leaves few units to draw in
local function fit()
  local room = (UIParent:GetHeight() or 768) * 0.94 - 34
  frame:SetScale(math.min(1, room / frame:GetHeight()))
  frame.bars(frame:GetWidth(), frame:GetHeight())
end

-- ------------------------------------------------------------------------------------------------- the first page
local function paint()
  for _, b in ipairs(buttons) do
    Skin.Choose(b, b.code == chosen)
  end
  -- the button in the language just clicked, so the player sees what the reload brings; as wide as its words
  start.text:SetText(ns.Lang.Word(chosen, chosen ~= ns.Lang.Current() and 'welcomeSwitch' or 'welcomeStart'))
  start:SetWidth(math.max(200, (start.text:GetStringWidth() or 0) + 64))
end

local function layout()
  local langs = ns.Lang.Available()
  -- the language buttons, three a row, each named in its own language
  for i, e in ipairs(langs) do
    local b = buttons[i]
    if not b then
      b = Skin.Button(langPage, 130, 28, '', function(self) chosen = self.code paint() end, 'BoFGuideWelcomeLang' .. i)
      b.text:SetFontObject(Skin.Font.Body or Skin.Font.Button)
      buttons[i] = b
    end
    b.code = e.code
    b.text:SetText(e.name)
    -- (Korean is offered on a Korean client only, Lang.Available, where the guide uses the game's own fonts)
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local x = (col - 1) * 142
    b:ClearAllPoints()
    b:SetPoint('TOP', langHead, 'BOTTOM', x, -12 - row * 34)
    b:Show()
  end
  for i = #langs + 1, #buttons do buttons[i]:Hide() end
  local rows = math.ceil(#langs / 3)
  langNote:ClearAllPoints()
  langNote:SetPoint('TOP', langHead, 'BOTTOM', 0, -18 - rows * 34)
  local y = langNote
  for i, t in ipairs(L.welcomeHow or {}) do
    local fs = how[i]
    if not fs then
      -- (the dot on its own, so a wrapped line hangs under the words, not under the dot; the QA pass, Oct 20)
      fs = Skin.String(langPage, 'Text', 'OVERLAY', C.text)
      fs:SetWidth(BODY - 60)
      fs:SetJustifyH('LEFT')
      fs.dot = Skin.String(langPage, 'Text', 'OVERLAY', C.gold)
      fs.dot:SetPoint('TOPRIGHT', fs, 'TOPLEFT', -6, 0)
      fs.dot:SetText('·')
      how[i] = fs
    end
    fs:ClearAllPoints()
    if i == 1 then fs:SetPoint('TOP', langNote, 'BOTTOM', 0, -22) else fs:SetPoint('TOPLEFT', y, 'BOTTOMLEFT', 0, -8) end
    fs:SetText(t)
    y = fs
  end
  local function sh(fs, d) return fs:GetStringHeight() or d end
  local h = 150 + sh(title, 28) + 18 + sh(langHead, 14) + 18 + rows * 34 + sh(langNote, 14) + 22
  for i, fs in ipairs(how) do h = h + (i == 1 and 0 or 8) + sh(fs, 14) end
  frame:SetHeight(h + 116)
  fit()
end

-- ------------------------------------------------------------------------------------------------- the oath's parts
local plates, rows = {}, {}
local readPlate, autoPlate, banner

--- is the guide acting for you? (the AUTO switch's own test)
local function autoOn() return ns.Window and ns.Window.AutoOn and ns.Window.AutoOn() end

local function paintOath()
  if not oath then return end
  local on = autoOn()
  for _, p in ipairs(plates) do
    local picked = (p.auto and on) or (not p.auto and not on)
    edges(p, picked and C.gold or C.frame, picked and 1 or 0.8)
    p.pic:SetDesaturated(not picked)
    p.pic:SetAlpha(picked and 1 or 0.72)
    if p.tag then p.tag:SetShown(not picked) end
    p.halo:SetShown(picked)
    p.check:SetShown(picked)
    p.name:SetTextColor(unpack(picked and C.gold or C.dim))
    p.line:SetTextColor(unpack(picked and C.text or C.faint))
  end
  banner.title:SetText(ns.upper(on and L.oathBannerOn or L.oathBannerOff))
  banner.title:SetTextColor(unpack(on and C.done or C.ember))
  banner.line:SetText(on and L.oathBannerOnLine or L.oathBannerOffLine)
  edges(banner, on and C.done or C.ember, on and 0.5 or 0.9)
  banner.fill:SetColorTexture(on and 0.1 or C.emberDeep[1], on and 0.2 or C.emberDeep[2], on and 0.1 or C.emberDeep[3],
    on and 0.3 or 0.42)
  banner.pulse:SetShown(not on)
  if on then banner.beat:Stop() else banner.beat:Play() end
  for _, r in ipairs(rows) do
    local a = r.value()
    Skin.Choose(r.a, a)
    Skin.Choose(r.b, not a)
  end
end

--- one of the two great choices: a painting, its name, a line, and a lit edge when it's yours
local function plate(parent, pic, name, line, auto)
  local p = CreateFrame('Button', 'BoFGuideOath' .. (auto and 'Auto' or 'Read'), parent)
  p.auto = auto
  p.halo = Skin.Tex(p, 'glow', 'BACKGROUND', -2)
  p.halo:SetBlendMode('ADD')
  p.halo:SetVertexColor(C.ember[1], C.ember[2], C.ember[3])
  p.halo:SetPoint('TOPLEFT', p, 'TOPLEFT', -14, 14)
  p.halo:SetPoint('BOTTOMRIGHT', p, 'BOTTOMRIGHT', 14, -14)
  p.halo:SetAlpha(0.5)
  local fill = p:CreateTexture(nil, 'BACKGROUND', nil, -1)
  fill:SetColorTexture(C.well[1], C.well[2], C.well[3], 1)
  fill:SetAllPoints(p)
  p.pic = Skin.Tex(p, pic, 'ARTWORK', 1)
  p.pic:SetPoint('TOPLEFT', p, 'TOPLEFT', 1, -1)
  p.pic:SetPoint('TOPRIGHT', p, 'TOPRIGHT', -1, -1)
  p.pic:SetHeight(100)
  if auto then
    p.tag = Skin.Button(p, 170, 26, ns.upper(L.oathSwitchOn), function() p:Click() end, 'BoFGuideOathAutoTag')
    p.tag.text:SetFontObject(Skin.Font.Button)
    Skin.Choose(p.tag, true)
    p.tag:SetPoint('BOTTOM', p.pic, 'BOTTOM', 0, 8)
    p.tag:SetWidth(math.max(170, (p.tag.text:GetStringWidth() or 0) + 44))
  end
  p.check = Skin.Tex(p, 'check-done', 'OVERLAY', 3)
  p.check:SetSize(30, 30)
  p.check:SetPoint('TOPRIGHT', p, 'TOPRIGHT', -8, -8)
  p.name = Skin.String(p, 'Vow', 'OVERLAY', C.gold)
  p.name:SetPoint('TOPLEFT', p.pic, 'BOTTOMLEFT', 12, -9)
  p.name:SetPoint('TOPRIGHT', p.pic, 'BOTTOMRIGHT', -12, -9)
  p.name:SetText(ns.upper(name))
  p.line = Skin.String(p, 'Small', 'OVERLAY', C.text)
  p.line:SetPoint('TOPLEFT', p.name, 'BOTTOMLEFT', 0, -5)
  p.line:SetPoint('TOPRIGHT', p.name, 'BOTTOMRIGHT', 0, -5)
  p.line:SetText(line)
  p:SetScript('OnClick', function()
    for k in pairs(ns.settings.auto) do ns.settings.auto[k] = auto end
    if auto then ns.AutoResume() end
    if ns.Window and ns.Window.Header then ns.Window.Header() end
    paintOath()
  end)
  p:SetScript('OnEnter', function(self) self.pic:SetAlpha(1) end)
  p:SetScript('OnLeave', function() paintOath() end)
  plates[#plates + 1] = p
  return p
end

--- a smaller vow: the question and its line on the left, two plates on the right
local function row(parent, ask, line, optA, optB, value, set, id)
  local r = { value = value }
  r.ask = Skin.String(parent, 'Vow', 'OVERLAY', C.gold)
  r.ask:SetText(ns.upper(ask))
  r.line = Skin.String(parent, 'Small', 'OVERLAY', C.dim)
  r.line:SetText(line)
  local function opt(label, v, suffix)
    local b = Skin.Button(parent, 144, 30, label, function() set(v) paintOath() end, 'BoFGuideOath' .. id .. suffix)
    b.text:SetFontObject(Skin.Font.Button)
    return b
  end
  r.a, r.b = opt(optA, true, 'Yes'), opt(optB, false, 'No')
  rows[#rows + 1] = r
  return r
end

local function buildOath()
  oath = CreateFrame('Frame', nil, frame)
  oath:SetAllPoints(frame)
  local o = {}
  o.title = Skin.String(oath, 'Display', 'OVERLAY', C.gold)
  o.title:SetJustifyH('CENTER')
  o.title:SetText(ns.upper(L.oathTitle))
  o.sub = Skin.String(oath, 'Text', 'OVERLAY', C.text)
  o.sub:SetJustifyH('CENTER')
  o.sub:SetText(L.oathSub)
  o.ask = Skin.String(oath, 'Vow', 'OVERLAY', C.gold)
  o.ask:SetJustifyH('CENTER')
  o.ask:SetText(ns.upper(L.oathQuest))
  readPlate = plate(oath, 'setup-read', L.oathRead, L.oathReadLine, false)
  autoPlate = plate(oath, 'setup-auto', L.oathAuto, L.oathAutoLine, true)

  -- the line nobody flies past: what's off, and how to have it
  banner = CreateFrame('Frame', 'BoFGuideOathBanner', oath)
  banner.fill = banner:CreateTexture(nil, 'BACKGROUND', nil, 1)
  banner.fill:SetAllPoints(banner)
  banner.pulse = Skin.Tex(banner, 'glow', 'BACKGROUND', 2)
  banner.pulse:SetBlendMode('ADD')
  banner.pulse:SetVertexColor(C.ember[1], C.ember[2], C.ember[3])
  banner.pulse:SetAllPoints(banner)
  banner.pulse:SetAlpha(0.2)
  banner.beat = banner.pulse:CreateAnimationGroup()
  banner.beat:SetLooping('BOUNCE')
  local beat = banner.beat:CreateAnimation('Alpha')
  beat:SetFromAlpha(0.15)
  beat:SetToAlpha(0.6)
  beat:SetDuration(0.9)
  banner.title = Skin.String(banner, 'Heading', 'OVERLAY', C.ember)
  banner.title:SetJustifyH('CENTER')
  banner.title:SetPoint('TOP', banner, 'TOP', 0, -10)
  banner.title:SetWidth(BODY - 28)
  banner.line = Skin.String(banner, 'Text', 'OVERLAY', C.text)
  banner.line:SetJustifyH('CENTER')
  banner.line:SetPoint('TOP', banner.title, 'BOTTOM', 0, -5)
  banner.line:SetWidth(BODY - 28)

  o.lives = row(oath, L.oathLives, L.oathLivesLine, L.oathOne, L.oathMany,
    function() return ns.settings.hc == 'on' end,
    function(v) ns.settings.hc = v and 'on' or 'auto' ns.State.Player() ns.MarkDirty('hc') end, 'Lives')
  o.dungeons = row(oath, L.oathDungeons, L.oathDungeonsLine, L.oathGroup, L.oathSolo,
    function() return ns.settings.dungeons ~= false end,
    function(v) ns.settings.dungeons = v ns.MarkDirty('dungeons') end, 'Dungeons')

  o.seal = Skin.Button(oath, 280, 38, ns.upper(L.oathSeal), function() Welcome.Seal() end, 'BoFGuideOathSeal')
  o.seal.text:SetFontObject(Skin.Font.Vow)
  Skin.Choose(o.seal, true)
  oath.o = o
end

--- the tablet, stacked from the top by what each part measures, so longer languages grow it instead of spilling
local function layoutOath()
  local o = oath.o
  local inner = BODY
  local pw = (inner - 16) / 2
  local function sh(fs, d) return fs:GetStringHeight() or d end
  local y = -118
  local function place(fs, gap)
    fs:ClearAllPoints()
    fs:SetPoint('TOP', oath, 'TOP', 0, y - (gap or 0))
    fs:SetWidth(inner)
    y = y - (gap or 0) - sh(fs, 14)
  end
  place(o.title, 0)
  place(o.sub, 6)
  place(o.ask, 18)
  y = y - 10
  local tall = 0
  for _, p in ipairs(plates) do
    p:SetSize(pw, 10)
    p.line:SetWidth(pw - 24)
    tall = math.max(tall, 100 + 9 + sh(p.name, 14) + 5 + sh(p.line, 14) + 12)
  end
  readPlate:ClearAllPoints()
  readPlate:SetPoint('TOPLEFT', oath, 'TOP', -inner / 2, y)
  autoPlate:ClearAllPoints()
  autoPlate:SetPoint('TOPRIGHT', oath, 'TOP', inner / 2, y)
  readPlate:SetHeight(tall)
  autoPlate:SetHeight(tall)
  y = y - tall - 12
  banner:ClearAllPoints()
  banner:SetPoint('TOPLEFT', oath, 'TOP', -inner / 2, y)
  banner:SetPoint('TOPRIGHT', oath, 'TOP', inner / 2, y)
  local bh = 10 + sh(banner.title, 16) + 5 + sh(banner.line, 14) + 12
  banner:SetHeight(bh)
  y = y - bh - 18
  local bw = 144                 -- (one width for both rows: their plates line up in every language)
  for _, r in ipairs(rows) do
    bw = math.max(bw, (r.a.text:GetStringWidth() or 0) + 40, (r.b.text:GetStringWidth() or 0) + 40)
  end
  for _, r in ipairs(rows) do
    r.a:SetWidth(bw)
    r.b:SetWidth(bw)
    local words = inner - 2 * bw - 32
    r.ask:SetWidth(words)
    r.line:SetWidth(words)
    r.ask:ClearAllPoints()
    r.ask:SetPoint('TOPLEFT', oath, 'TOP', -inner / 2, y)
    r.line:ClearAllPoints()
    r.line:SetPoint('TOPLEFT', r.ask, 'BOTTOMLEFT', 0, -3)
    r.b:ClearAllPoints()
    r.b:SetPoint('TOPRIGHT', oath, 'TOP', inner / 2, y - 2)
    r.a:ClearAllPoints()
    r.a:SetPoint('RIGHT', r.b, 'LEFT', -8, 0)
    y = y - math.max(34, sh(r.ask, 14) + 3 + sh(r.line, 14)) - 12
  end
  o.seal:SetWidth(math.max(280, (o.seal.text:GetStringWidth() or 0) + 80))
  o.seal:ClearAllPoints()
  o.seal:SetPoint('TOP', oath, 'TOP', 0, y - 8)
  frame:SetHeight(-y + 8 + 38 + 58)
  fit()
end

-- ---------------------------------------------------------------------- what the game does to a window that's open
--- Blizzard closes every window on entering the world and for a new character's opening cinematic (a full-screen panel:
--- CloseAllWindows, then UIParent hidden until it ends). The first window waits for those, and one the game takes comes
--- back: being closed by the game isn't the player having seen it (retail, Oct 31; Blizzard's code is the same on Forever,
--- whose races open on a cinematic too)
local function busy()
  return not entered or (CinematicFrame and CinematicFrame:IsShown()) or (MovieFrame and MovieFrame:IsShown())
end

local function wait()
  if busy() then return C_Timer.After(1, wait) end
  ns.safecall('welcome', Welcome.First)
end

--- the window has gone (asked a moment later: the cinematic's panel shows only after it has closed the windows). Still
--- shown means only the screen went, as with Alt-Z, and it comes back by itself. Otherwise it's the player's doing,
--- Escape included, unless the game is busy
local function closed()
  if frame:IsShown() then return end
  if busy() then return wait() end
  if ns.db then ns.db.welcomed = true end
  if firstRun and not Welcome.switching then
    firstRun = false
    -- (then the tour, once: owner, Nov 13. The AUTO plate comes when it ends, or after "Later")
    local function next() if ns.Tour then ns.Tour.Offer(Welcome.Coach) else Welcome.Coach() end end
    if Welcome.sealing then C_Timer.After(SLAM + STAND + FADE, next) else next() end
  end
  Welcome.sealing = nil
end

-- ---------------------------------------------------------------------------------------------------- the window
function Welcome.Create()
  if frame then return frame end
  frame = CreateFrame('Frame', 'BoFGuideWelcome', UIParent)
  ns.Escapable(frame)
  frame:SetSize(WIDTH, 560)
  frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 20)
  frame:SetFrameStrata('DIALOG')
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag('LeftButton')
  frame:SetScript('OnDragStart', frame.StartMoving)
  frame:SetScript('OnDragStop', frame.StopMovingOrSizing)
  Skin.Ornate(frame)
  -- (a way out without a choice: the language stays as it is; Escape does the same; the QA pass, Oct 20)
  local close = Skin.IconButton(frame, 20, 'btn-close', function() frame:Hide() end, 'BoFGuideWelcomeClose',
    { L.linkClose })
  close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -30, -34)
  close:SetFrameLevel(frame:GetFrameLevel() + 10)
  langPage = CreateFrame('Frame', nil, frame)
  langPage:SetAllPoints(frame)
  title = Skin.String(langPage, 'Display', 'OVERLAY', C.gold)
  title:SetPoint('TOP', langPage, 'TOP', 0, -150)
  title:SetWidth(BODY)
  title:SetJustifyH('CENTER')
  title:SetText(ns.upper(L.welcomeTitle))
  langHead = Skin.String(langPage, 'Body', 'OVERLAY', C.text)
  langHead:SetPoint('TOP', title, 'BOTTOM', 0, -18)
  langHead:SetWidth(BODY)
  langHead:SetJustifyH('CENTER')
  langHead:SetText(L.welcomeLang)
  langNote = Skin.String(langPage, 'Small', 'OVERLAY', C.dim)
  langNote:SetWidth(BODY)
  langNote:SetJustifyH('CENTER')
  langNote:SetText(L.welcomeLangNote)
  start = Skin.Button(langPage, 200, 34, '', function() Welcome.Done() end, 'BoFGuideWelcomeStart')
  start.text:SetFontObject(Skin.Font.Vow)
  start:SetPoint('BOTTOM', langPage, 'BOTTOM', 0, 56)
  frame:Hide()
  -- (set after that Hide: a new frame is shown, so it would fire before the player has seen anything)
  frame:SetScript('OnHide', function() C_Timer.After(0, closed) end)
  return frame
end

--- open the window (first load, the seal's menu, /bofg language)
function Welcome.Show()
  Welcome.Create()
  chosen = ns.Lang.Current()
  langPage:Show()
  if oath then oath:Hide() end
  layout()
  paint()
  frame:Show()
  -- (the texts measure their real height once shown: sized again then, and after the fonts settle)
  layout()
  paint()
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() if frame:IsShown() and langPage:IsShown() then layout() paint() end end)
  end
end

--- open the tablet (after the language on a new install, the seal's menu, /bofg oath)
function Welcome.Oath()
  Welcome.Create()
  if not oath then buildOath() end
  langPage:Hide()
  oath:Show()
  paintOath()
  layoutOath()
  frame:Show()
  layoutOath()
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() if frame:IsShown() and oath:IsShown() then layoutOath() end end)
  end
end

--- the language page's button: the language kept (and switched with one reload), and on a new install the tablet next
function Welcome.Done()
  local name = (ns.Lang.Entry(chosen) or {}).name or chosen
  local first = firstRun
  if first then
    ns.db.oathNext = true          -- (the reload brings the tablet in the language just chosen)
    if chosen ~= ns.Lang.Current() then Welcome.switching = true end
  end
  ns.db.welcomed = true
  if not ns.Lang.Set(chosen) then
    if first then
      ns.db.oathNext = nil
      Welcome.Oath()
    else
      if frame then frame:Hide() end
      ns.say(L.langSet:format(name))
    end
  end
end

-- ---------------------------------------------------------------------------------------------------------- the seal
local stamp

--- the seal, on a layer of its own over everything (owner, Oct 31: on the tablet it ran behind the plates, unseen)
local function buildStamp()
  stamp = CreateFrame('Frame', 'BoFGuideOathStamp', UIParent)
  stamp:SetFrameStrata('FULLSCREEN_DIALOG')
  stamp:SetSize(236, 236)
  stamp:SetPoint('CENTER', UIParent, 'CENTER', 0, 40)
  stamp:Hide()
  stamp.flash = Skin.Tex(stamp, 'glow', 'BACKGROUND')
  stamp.flash:SetBlendMode('ADD')
  stamp.flash:SetVertexColor(C.ember[1], C.ember[2], C.ember[3])
  stamp.flash:SetPoint('CENTER', stamp, 'CENTER', 0, 0)
  stamp.flash:SetSize(640, 640)
  stamp.flash:Hide()
  stamp.burst = stamp.flash:CreateAnimationGroup()
  local grow = stamp.burst:CreateAnimation('Scale')
  grow:SetScaleFrom(0.45, 0.45)
  grow:SetScaleTo(1, 1)
  grow:SetDuration(0.5)
  grow:SetSmoothing('OUT')
  local dim = stamp.burst:CreateAnimation('Alpha')
  dim:SetFromAlpha(1)
  dim:SetToAlpha(0)
  dim:SetDuration(STAND)
  dim:SetSmoothing('OUT')
  stamp.seal = Skin.Tex(stamp, 'seal-stamp', 'ARTWORK')
  stamp.seal:SetAllPoints(stamp)
  stamp.drop = stamp.seal:CreateAnimationGroup()
  local fall = stamp.drop:CreateAnimation('Scale')
  fall:SetScaleFrom(3, 3)
  fall:SetScaleTo(1, 1)
  fall:SetDuration(SLAM)
  fall:SetSmoothing('IN')
  local appear = stamp.drop:CreateAnimation('Alpha')
  appear:SetFromAlpha(0)
  appear:SetToAlpha(1)
  appear:SetDuration(SLAM * 0.6)
  stamp.embers = {}
  for i = 1, SEAL_EMBERS do
    local e = Skin.Tex(stamp, 'mark-spark', 'OVERLAY')
    local turn, far = (i / SEAL_EMBERS) * math.pi * 2, 150 + (i * 53) % 110
    e:SetSize(16 + (i * 7) % 14, 16 + (i * 7) % 14)
    e:SetPoint('CENTER', stamp, 'CENTER', math.cos(turn) * 96, math.sin(turn) * 96)
    e:SetBlendMode('ADD')
    e:Hide()
    e.fly = e:CreateAnimationGroup()
    local go = e.fly:CreateAnimation('Translation')
    go:SetOffset(math.cos(turn) * far, math.sin(turn) * far)
    go:SetDuration(STAND)
    go:SetSmoothing('OUT')
    local burn = e.fly:CreateAnimation('Alpha')
    burn:SetFromAlpha(1)
    burn:SetToAlpha(0)
    burn:SetDuration(STAND)
    stamp.embers[i] = e
  end
  stamp.out = stamp:CreateAnimationGroup()
  if stamp.out.SetToFinalAlpha then stamp.out:SetToFinalAlpha(true) end
  local leave = stamp.out:CreateAnimation('Alpha')
  leave:SetFromAlpha(1)
  leave:SetToAlpha(0)
  leave:SetDuration(FADE)
end

local function impact()
  stamp.flash:Show()
  stamp.burst:Play()
  for _, e in ipairs(stamp.embers) do
    e:Show()
    e.fly:Play()
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.UI_70_ARTIFACT_FORGE_APPEARANCE_APPEARANCE_CHANGE then
    PlaySound(SOUNDKIT.UI_70_ARTIFACT_FORGE_APPEARANCE_APPEARANCE_CHANGE)
  end
end

local function sealed()
  stamp:Hide()
  stamp.out:Stop()
  stamp.flash:Hide()
  for _, e in ipairs(stamp.embers) do e:Hide() end
  stamp:SetAlpha(1)
end

--- Seal my oath: the window goes first, and the seal comes down in the open, with nothing in front of it
function Welcome.Seal()
  Welcome.sealing = true
  frame:Hide()
  if not stamp then buildStamp() end
  stamp:SetAlpha(1)
  stamp:Show()
  stamp.drop:Play()
  C_Timer.After(SLAM, impact)
  C_Timer.After(SLAM + STAND, function() stamp.out:Play() end)
  C_Timer.After(SLAM + STAND + FADE, sealed)
end

--- the first time the guide loads on this account
function Welcome.First()
  if not ns.db or busy() or (frame and frame:IsShown()) then return end
  if firstRun and oath and oath:IsShown() then return Welcome.Oath() end   -- (the game took the tablet)
  if ns.db.oathNext then
    ns.db.oathNext = nil
    firstRun = true
    return Welcome.Oath()
  end
  if not ns.db.welcomed then
    firstRun = true
    Welcome.Show()
  end
end

--- after a new install's window closes, and automation is off: one plate on the AUTO switch itself
function Welcome.Coach()
  if autoOn() then return end
  ns.say(L.oathCoachChat)
  if ns.Window and ns.Window.Coach then ns.Window.Coach(L.oathCoach) end
end

-- the first time on this account: the welcome window, the language first (owner, Oct 16)
ns.On('PLAYER_ENTERING_WORLD', function()
  if entered then return end
  entered = true
  C_Timer.After(1, wait)
end)
