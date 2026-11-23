-- A link to copy (addons can't open a browser): a short text, then the address selected in a box. Used for levels 30
-- to 60 ("Levels 30 to 60" in the seal's menu, owner, Oct 16: no price, no pop-up; the page in the guide's language).
local _, ns = ...

local Link = {}
ns.Link = Link
local L = ns.L
local Skin = ns.Skin
local C = Skin.C
local WIDTH, HEIGHT = 420, 210

local frame, title, text, edit, hint, tagBox, tagHint

function Link.Create()
  if frame then return frame end
  frame = CreateFrame('Frame', 'BoFGuideLink', UIParent)
  ns.Escapable(frame)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 80)
  frame:SetFrameStrata('DIALOG')
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag('LeftButton')
  frame:SetScript('OnDragStart', frame.StartMoving)
  frame:SetScript('OnDragStop', frame.StopMovingOrSizing)
  frame.skin = Skin.Panel(frame, { glow = false })
  frame.skin.bg:SetAlpha(0.96)
  frame.skin.shade:SetAlpha(0.96)
  title = Skin.String(frame, 'Heading', 'OVERLAY', C.gold)
  title:SetPoint('TOPLEFT', frame, 'TOPLEFT', 22, -20)
  local close = Skin.IconButton(frame, 18, 'btn-close', function() frame:Hide() end, 'BoFGuideLinkClose', { L.linkClose })
  close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -20, -18)
  text = Skin.String(frame, 'Text', 'OVERLAY', C.text)
  text:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -10)
  text:SetWidth(WIDTH - 44)
  text:SetJustifyH('LEFT')
  local well = frame:CreateTexture(nil, 'ARTWORK')
  edit = CreateFrame('EditBox', 'BoFGuideLinkEdit', frame)
  edit:SetAutoFocus(false)
  edit:SetFontObject(Skin.Font.Text or ChatFontNormal)
  edit:SetHeight(24)
  edit:SetPoint('TOPLEFT', text, 'BOTTOMLEFT', 4, -14)
  edit:SetPoint('RIGHT', frame, 'RIGHT', -26, 0)
  well:SetPoint('TOPLEFT', edit, 'TOPLEFT', -6, 4)
  well:SetPoint('BOTTOMRIGHT', edit, 'BOTTOMRIGHT', 6, -4)
  well:SetColorTexture(C.well[1], C.well[2], C.well[3], 0.9)
  Skin.Edge(frame, well)
  -- the address stays whole and selected: typing can't change it
  edit:SetScript('OnTextChanged', function(self, user)
    if user then self:SetText(frame.url or '') self:HighlightText() end
  end)
  edit:SetScript('OnEscapePressed', function() frame:Hide() end)
  edit:SetScript('OnEditFocusGained', function(self) self:HighlightText() end)
  hint = Skin.String(frame, 'Small', 'OVERLAY', C.dim)
  hint:SetPoint('TOPLEFT', edit, 'BOTTOMLEFT', -4, -12)
  hint:SetWidth(WIDTH - 44)
  hint:SetJustifyH('LEFT')
  hint:SetText(L.linkCopy)
  -- the BattleTag the copy will work on, to copy at checkout rather than retype (Oct 19: I and l look alike in Inter)
  tagBox = Skin.TagBox(frame, 'BoFGuideLinkTag')
  tagBox:SetPoint('TOPLEFT', hint, 'BOTTOMLEFT', 0, -6)
  tagHint = Skin.String(frame, 'Small', 'OVERLAY', C.dim)
  tagHint:SetPoint('TOPLEFT', tagBox, 'BOTTOMLEFT', 0, -4)
  tagHint:SetWidth(WIDTH - 44)
  tagHint:SetJustifyH('LEFT')
  tagHint:SetText(L.tagCopy)
  -- (someone who bought it already: straight to the window that adds it)
  frame.have = Skin.Button(frame, 200, 26, L.linkHave, function() frame:Hide() ns.Import.Show() end, 'BoFGuideLinkHave')
  frame.have.text:SetFontObject(Skin.Font.Button)
  frame.have:SetWidth(math.max(200, (frame.have.text:GetStringWidth() or 0) + 48))
  frame.have:Hide()
  frame:Hide()
  return frame
end

--- the height: every part stacked from the top (the title, the words, the box, the hint), measured once shown
--- (a long language at 150% text ran the box and the hint out of the frame, Oct 16)
local function fit()
  local function sh(fs, d) return fs:GetStringHeight() or d end
  local extra = (frame.have:IsShown() and (12 + 26) or 0) + (tagBox:IsShown() and (6 + 24 + 4 + sh(tagHint, 14)) or 0)
  frame:SetHeight(math.max(HEIGHT, 20 + sh(title, 20) + 10 + sh(text, 40) + 14 + 24 + 12 + sh(hint, 14) + extra + 24))
end

--- show a link: a title, what it is, the address selected to copy; `tag`, a BattleTag shown under the note to copy
function Link.Show(head, words, url, note, have, tag)
  Link.Create()
  frame.have:SetShown(have and true or false)
  tagBox:SetShown(tag and true or false)
  tagHint:SetShown(tag and true or false)
  if tag then tagBox:SetTag(tag) end
  frame.have:ClearAllPoints()
  frame.have:SetPoint('TOPLEFT', tag and tagHint or hint, 'BOTTOMLEFT', -2, -12)
  frame.url = url
  title:SetText(ns.upper(head or ''))
  text:SetText(words or '')
  edit:SetText(url or '')
  hint:SetText(L.linkCopy .. (note and ('\n\n' .. note) or ''))
  frame:Show()
  fit()
  if C_Timer and C_Timer.After then C_Timer.After(0, function() if frame:IsShown() then fit() end end) end
  edit:SetFocus()
  edit:HighlightText()
end

function Link.HintText()   -- (tests) the note, then the tag in its box
  return hint and (hint:GetText() .. (tagBox:IsShown() and (' ' .. (tagBox:GetText() or '')) or ''))
end

--- the player's own BattleTag ("Name#1234"), when the game says it
function Link.BattleTag()
  if not BNGetInfo then return nil end
  local ok, _, tag = pcall(BNGetInfo)
  tag = ok and ns.clean(tag) or nil
  return type(tag) == 'string' and tag:find('#') and tag or nil
end

local function enc(v)
  return (tostring(v):gsub('[^%w%-%._~]', function(c) return ('%%%02X'):format(c:byte()) end))
end

--- the full guide's page, in the guide's language when that site is up. After the # (never sent to the server, read
--- by the page itself; like the feedback links): where the player came from in the guide (`src`: card, hint27,
--- prof, dungeon, menu), their faction and their BattleTag, so the page picks the faction and fills the BattleTag the
--- copy is bound to (owner, Oct 16: the sales pass)
function Link.FullGuide(src)
  local faction = UnitFactionGroup and ns.clean(UnitFactionGroup('player'))
  local tag = Link.BattleTag()
  local parts = { 'src=' .. enc(src or ns.cdb and ns.cdb.lastHint or 'menu') }
  if faction == 'Alliance' or faction == 'Horde' then parts[#parts + 1] = 'f=' .. faction:lower() end
  if tag then parts[#parts + 1] = 'bt=' .. enc(tag) end
  local words = L.fullGuideText
  Link.Show(L.fullGuideTitle, words, ns.SiteURL('/leveling-guide') .. '#' .. table.concat(parts, '&'),
    tag and L.linkYouOn or nil, true, tag)
end

--- the full guide is installed (an imported 30-60 pack): nothing to point at
function Link.HasFullGuide()
  for id, p in pairs(ns.Packs and ns.Packs.byId or {}) do
    if p.tier == 'paid' and id:match('%-30$') then return true end
  end
  return false
end
