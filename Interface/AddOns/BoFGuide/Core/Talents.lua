-- Bind on Forever Guide: talent plans (owner, Nov 5: "fully build out talent plans"). A plan is a leveling build for
-- your class, an ordered list of the 51 points from level 10 to 60 (guides/talents/<class>.yaml, written into
-- Data/Talents.lua by `forever guide-build`). The guide reads what you have bought (C_Traits.GetNodeInfo on the active
-- config) and works out your next talent: the first point of the plan you don't have yet, so a talent taken off-plan
-- just moves the plan on. On Blizzard's talent window (PlayerSpellsFrame.TalentsFrame, load-on-demand) a glow of ours
-- sits over that talent's button; with a point to spend, the guide says which. While the owner tests it, it's behind
-- his switch (`/bofg talents on`, BoFGuideDB.dev.talents): a release carries it off.
local _, ns = ...
local T = {}
ns.Talents = T

local byClass = {}   -- classFile -> { { id, name, about, picks = { nodeID, ... }, spells = { [nodeID] = spellID } } }

--- Data/Talents.lua hands the plans over here
function BoFGuide_RegisterTalentPlans(plans) byClass = plans or {} end

function T.Enabled() return ns.db and ns.db.dev and ns.db.dev.talents and true or false end

function T.SetEnabled(on)
  ns.db.dev = ns.db.dev or {}
  ns.db.dev.talents = on and true or nil
  T.Refresh()
end

local function classFile()
  local _, file = UnitClass('player')
  return ns.clean(file)
end

--- the plans for your class
function T.Plans() return byClass[classFile() or ''] or {} end

--- the plan you picked (none until you pick one)
function T.Plan()
  local id = ns.cdb and ns.cdb.talentPlan
  for _, p in ipairs(T.Plans()) do if p.id == id then return p end end
  return nil
end

--- a plan's name and what it's for, in the language the player reads the guide in (Data/Lang_<locale>.lua's lines)
function T.Title(p) return p and ns.Packs.Line(p.name) or '' end
function T.About(p) return p and p.about and ns.Packs.Line(p.about) or '' end

function T.SetPlan(id)
  ns.cdb.talentPlan = id
  T.Refresh()
end

local function config()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return nil end
  local ok, id = pcall(C_ClassTalents.GetActiveConfigID)
  return ok and ns.clean(id) or nil
end

--- ranks you have bought in a talent, or nil when the game doesn't say
local function bought(cfg, node)
  if not (C_Traits and C_Traits.GetNodeInfo) then return nil end
  local ok, info = pcall(C_Traits.GetNodeInfo, cfg, node)
  if not ok or type(info) ~= 'table' then return nil end
  return ns.clean(info.ranksPurchased) or ns.clean(info.currentRank)
end

--- the plan's next point: { node, rank, index, level, spell } (rank = the rank it brings that talent to), or nil when
--- there's no plan, the game doesn't say, or the plan is done
function T.Next()
  local plan, cfg = T.Plan(), config()
  if not (plan and cfg) then return nil end
  local want = {}
  for i, node in ipairs(plan.picks or {}) do
    want[node] = (want[node] or 0) + 1
    local have = bought(cfg, node)
    if have == nil then return nil end
    if have < want[node] then
      return { node = node, rank = want[node], index = i, level = 9 + i, spell = plan.spells and plan.spells[node] }
    end
  end
  return nil
end

--- the talent's name in your client's language (its spell), else the plan's English name
function T.Name(nxt)
  local name = nxt and nxt.spell and C_Spell and C_Spell.GetSpellName and ns.clean(C_Spell.GetSpellName(nxt.spell))
  if name then return name end
  local plan = T.Plan()
  return plan and plan.names and plan.names[nxt.node] or ns.L.talentUnknown
end

--- points you have to spend now
function T.Unspent()
  local cfg = config()
  if not (cfg and C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeCurrencyInfo) then return 0 end
  local ok, info = pcall(C_Traits.GetConfigInfo, cfg)
  local tree = ok and type(info) == 'table' and info.treeIDs and info.treeIDs[1]
  if not tree then return 0 end
  local ok2, list = pcall(C_Traits.GetTreeCurrencyInfo, cfg, tree, false)
  if not ok2 or type(list) ~= 'table' then return 0 end
  local n = 0
  for _, c in ipairs(list) do n = n + (ns.clean(c.quantity) or 0) end
  return n
end

-- ------------------------------------------------------------------------------------------- the talent window
local glow, hooked

local function talentsFrame() return PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame end

-- the mark on the next talent: the game's own "ready" glow, the gold border that runs round an action button when a
-- spell procs (UI-HUD-ActionBar-Proc-Loop-Flipbook, Blizzard_ActionBar's spell alert), square like the talent button,
-- and a small "Next" above it. (Nov 9, the owner: the action bar's thin border was too faint, then our round ring on
-- a square button looked homemade.) Without that atlas, the guide's gold ring and glow
local PROC_ATLAS, PROC_SCALE = 'UI-HUD-ActionBar-Proc-Loop-Flipbook', 1.4
local function makeGlow()
  local Skin, C = ns.Skin, ns.Skin.C
  glow = CreateFrame('Frame', 'BoFGuideTalentGlow', UIParent)
  glow:EnableMouse(false)
  local proc = glow:CreateTexture(nil, 'OVERLAY')
  proc:SetAllPoints()
  local native = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(PROC_ATLAS) ~= nil and proc.SetAtlas
  if native then proc:SetAtlas(PROC_ATLAS) end
  if native and glow.CreateAnimationGroup then
    local ag = glow:CreateAnimationGroup()
    ag:SetLooping('REPEAT')
    local fb = ag:CreateAnimation('FlipBook')
    if fb and fb.SetFlipBookRows then
      fb:SetTarget(proc)
      fb:SetFlipBookRows(6)
      fb:SetFlipBookColumns(5)
      fb:SetFlipBookFrames(30)
      fb:SetFlipBookFrameWidth(0)
      fb:SetFlipBookFrameHeight(0)
      fb:SetDuration(1)
      glow.pulse = ag
    end
    glow.scale = PROC_SCALE
  else
    proc:Hide()
    local halo = Skin.Tex(glow, 'glow', 'BACKGROUND')
    halo:SetPoint('TOPLEFT', -18, 18)
    halo:SetPoint('BOTTOMRIGHT', 18, -18)
    halo:SetVertexColor(C.ember[1], C.ember[2], C.ember[3], 1)
    halo:SetBlendMode('ADD')
    local ring = Skin.Tex(glow, 'ring', 'OVERLAY')
    ring:SetAllPoints()
    ring:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
    glow.scale = 1.25
  end
  glow.tex = proc
  local word = Skin.String(glow, 'Small', 'OVERLAY', C.gold)
  word:SetPoint('BOTTOM', glow, 'TOP', 0, -4)
  word:SetText(ns.L.talentNextMark)
  if word.SetShadowOffset then word:SetShadowOffset(1, -1) end
  glow.word = word
  glow:Hide()
end

local function hideGlow()
  if glow then
    glow:Hide()
    if glow.pulse then glow.pulse:Stop() end
  end
  T.glowing = nil
end

--- the glow on the next talent's button, while the talent window shows. The window lays its buttons out just after
--- it shows, so a button not there yet is asked for again a few times (Nov 9, the owner's Shadow Priest: asked once at
--- OnShow, before the tree was there, and no glow ever came)
local RETRIES, RETRY_EVERY = 10, 0.15
local tries = 0
function T.Glow()
  local f = talentsFrame()
  if not (T.Enabled() and f and f:IsShown()) then tries = 0 return hideGlow() end
  local nxt = T.Next()
  local button = nxt and f.GetTalentButtonByNodeID and f:GetTalentButtonByNodeID(nxt.node)
  if not button then
    hideGlow()
    if nxt and tries < RETRIES and C_Timer and C_Timer.After then
      tries = tries + 1
      C_Timer.After(RETRY_EVERY, function() ns.safecall('talents', T.Glow) end)
    end
    return
  end
  tries = 0
  if not glow then makeGlow() end
  -- (drawn inside the talent window, over the button: a frame of UIParent's could sit under the window)
  if glow:GetParent() ~= f then glow:SetParent(f) end
  local w, h = button:GetWidth(), button:GetHeight()
  glow:ClearAllPoints()
  glow:SetPoint('CENTER', button, 'CENTER')
  glow:SetSize((w or 40) * (glow.scale or 1.4), (h or 40) * (glow.scale or 1.4))
  glow:SetFrameStrata(f:GetFrameStrata() or 'HIGH')
  glow:SetFrameLevel((button:GetFrameLevel() or 1) + 10)
  glow:Show()
  if glow.pulse and not glow.pulse:IsPlaying() then glow.pulse:Play() end
  T.glowing = nxt.node
end

local function hook()
  local f = talentsFrame()
  if hooked or not f then return end
  hooked = true
  f:HookScript('OnShow', function() ns.safecall('talents', T.Glow) end)
  f:HookScript('OnHide', function() hideGlow() end)
end

--- everything that shows the plan, again (a point bought, a level, the switch or the plan changed)
function T.Refresh()
  ns.safecall('talents', function()
    hook()
    T.Glow()
    if ns.MarkDirty then ns.MarkDirty('talents') end
  end)
end

--- the window's line: a point to spend and the plan's next talent, or nil. Short: the talent's icon and name only, for
--- when the whole line doesn't fit beside AUTO (Nov 9: "Talentpunkt: Verbessertes Schattenwort: Schmerz" at 150%)
function T.Line(short)
  if not (T.Enabled() and T.Plan()) then return nil end
  if T.Unspent() <= 0 then return nil end
  local nxt = T.Next()
  if not nxt then return nil end
  if short then
    local icon = nxt.spell and C_Spell and C_Spell.GetSpellTexture and ns.clean(C_Spell.GetSpellTexture(nxt.spell))
    return (icon and ('|T' .. icon .. ':0|t ') or '') .. T.Name(nxt)
  end
  return ns.L.talentPoint:format(T.Name(nxt))
end

ns.On('ADDON_LOADED', function(name) if name == 'Blizzard_PlayerSpells' then T.Refresh() end end)
for _, ev in ipairs({ 'TRAIT_NODE_CHANGED', 'TRAIT_CONFIG_UPDATED', 'TRAIT_TREE_CURRENCY_INFO_UPDATED',
                      'PLAYER_TALENT_UPDATE' }) do
  ns.On(ev, function() T.Refresh() end)
end
ns.On('PLAYER_LEVEL_UP', function()
  -- (the point comes with the level: say which talent it's for, once)
  C_Timer.After(1, function()
    ns.safecall('talents', function()
      local line = T.Line()
      if line then ns.say(line) end
      T.Refresh()
    end)
  end)
end)
ns.On('PLAYER_ENTERING_WORLD', function() T.Refresh() end)
