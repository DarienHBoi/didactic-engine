-- "Send feedback" (the seal's menu, /bofg feedback, or a step card's right-click, "Something's wrong with this step"):
-- what kind, a few words if you like, then one line to copy: a link to bindonforever.com/feedback with where you are
-- packed in it after the # (the guide's version, the route and step on screen, your level, class and race, the spot,
-- the quests in your log). The page shows all that as a card, takes a screenshot and sends it; nothing leaves the game
-- but what you paste. Addons can't open a browser or reach the internet, so copying is the way out. The contract with
-- the site: docs/feedback-pipeline.md (payload v1). The note is kept (BoFGuideDB.feedback, the newest 50, with its id,
-- so the same note sent and also found in the saved data counts once).
local _, ns = ...

local Feedback = {}
ns.Feedback = Feedback
local L = ns.L
local Skin = ns.Skin
local C = Skin.C
local WIDTH, HEIGHT, KEEP = 440, 360, 50
local MAX_LINE = 1500

local frame, title, help, edit, button, status, nextLine, wordsLabel, scroll
local kindButtons = {}
local stage = 'write'   -- write: kind and words; copy: the link, selected
local chosen, forKey = 'step', nil

-- --------------------------------------------------------------------------------------------- the payload (v1)
local ORDER = { 'id', 'k', 'w', 'v', 'g', 'loc', 'p', 'r', 'rt', 's', 'sk', 'o', 'st', 'bk', 'lv', 'c', 'ra', 'f', 'm',
                'x', 'y', 'q', 'b', 't' }
local DECIMAL = { lv = true, x = true, y = true }
local KINDS = { 'step', 'bug', 'idea', 'other' }

local function jsonString(s)
  local out = s:gsub('[%z\1-\31"\\]', function(c)
    if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' elseif c == '\n' then return '\\n'
    elseif c == '\r' then return '\\r' elseif c == '\t' then return '\\t' end
    return ('\\u%04x'):format(c:byte())
  end)
  return '"' .. out .. '"'
end

local function jsonValue(k, v)
  if type(v) == 'string' then return jsonString(v) end
  if type(v) == 'table' then
    local parts = {}
    for i, n in ipairs(v) do parts[i] = ('%d'):format(n) end
    return '[' .. table.concat(parts, ',') .. ']'
  end
  if type(v) == 'boolean' then return v and '1' or '0' end
  if DECIMAL[k] then return ('%.1f'):format(v) end
  return ('%d'):format(v)
end

--- JSON with the keys in the contract's order, no spaces (what the page's decoder and the test vectors expect)
function Feedback.Encode(t)
  local parts = {}
  for _, k in ipairs(ORDER) do
    if t[k] ~= nil then parts[#parts + 1] = jsonString(k) .. ':' .. jsonValue(k, t[k]) end
  end
  return '{' .. table.concat(parts, ',') .. '}'
end

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
--- base64url (RFC 4648 section 5), no padding
function Feedback.Base64Url(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local chars = c and 4 or (b and 3 or 2)
    for j = 1, chars do
      local v = math.floor(n / 2 ^ (18 - 6 * (j - 1))) % 64
      out[#out + 1] = B64:sub(v + 1, v + 1)
    end
  end
  return table.concat(out)
end

--- at most n bytes, never cutting a character in two (a German note's umlauts)
local function cap(s, n)
  if not s or #s <= n then return s end
  s = s:sub(1, n)
  local i = #s
  while i > 0 and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do i = i - 1 end
  local lead = i > 0 and s:byte(i) or 0
  local need = lead >= 0xF0 and 4 or lead >= 0xE0 and 3 or lead >= 0xC0 and 2 or 1
  if i > 0 and i + need - 1 > #s then s = s:sub(1, i - 1) end
  return s
end

local function round1(v) return v and math.floor(v * 10 + 0.5) / 10 end

local function newId()
  local abc, out = 'abcdefghijklmnopqrstuvwxyz0123456789', {}
  for i = 1, 10 do
    local r = math.random(1, #abc)
    out[i] = abc:sub(r, r)
  end
  return table.concat(out)
end

--- what the guide knows, for the page's card: never a name, realm, BattleTag, guild or chat
function Feedback.Payload(kind, words, key)
  local st = ns.st
  local route, view = ns.Engine.Route(), ns.Engine.View()
  local idx = view and view.cursor
  if key and route then
    for i, s in ipairs(route.steps) do if s.k == key then idx = i break end end
  end
  local s = route and idx and route.steps[idx]
  local v, b = GetBuildInfo()
  local pos = st.pos or {}
  local q = {}
  for id in pairs(st.log or {}) do q[#q + 1] = id end
  table.sort(q)
  while #q > 25 do table.remove(q) end
  local _, class = UnitClass('player')
  local _, race = UnitRace('player')
  words = (words or ''):gsub('^%s+', ''):gsub('%s+$', '')
  return {
    id = newId(), k = kind, w = words ~= '' and cap(words, 600) or nil, v = ns.VERSION,
    g = ('%s.%s'):format(tostring(v), tostring(b)), loc = GetLocale and ns.clean(GetLocale()) or nil,
    p = route and route.pack and route.pack.id or nil, r = route and route.id or nil,
    rt = route and cap(ns.plain(route.title or route.id), 80) or nil, s = s and idx or nil, sk = s and s.k or nil,
    o = s and s.o or nil, st = s and cap(ns.plain(ns.Text.Step(s, route.pack)), 200) or nil,
    bk = ns.Engine.Peeking() and 1 or 0, lv = round1((st.level or 1) + (st.xp or 0) / (st.xpMax or 1)),
    c = ns.clean(class), ra = ns.clean(race), f = st.faction, m = pos.map, x = round1(pos.x), y = round1(pos.y),
    q = #q > 0 and q or nil, b = ns.LastBlocked(), t = time(),
  }
end

--- the line to copy: the page in the client's language, the payload after the #, under MAX_LINE characters
function Feedback.Link(t)
  -- (the page in the guide's language when that site is up, else the English one: ns.SiteURL)
  local function build() return ns.SiteURL('/feedback') .. '#v1.' .. Feedback.Base64Url(Feedback.Encode(t)) end
  local link = build()
  while #link > MAX_LINE and t.w and #t.w > 0 do        -- (the words first, then the step's text)
    t.w = cap(t.w, #t.w - 60)
    link = build()
  end
  while #link > MAX_LINE and t.st and #t.st > 0 do
    t.st = cap(t.st, #t.st - 60)
    link = build()
  end
  if #link > MAX_LINE then t.q, t.b = nil, nil link = build() end
  return link
end

--- where you are, as plain lines a person can read (the /bofg report and the old notes' context)
function Feedback.Context()
  local st = ns.st
  local route, view = ns.Engine.Route(), ns.Engine.View()
  local s = route and view and view.cursor and route.steps[view.cursor]
  local v, b = GetBuildInfo()
  local level = (st.level or 1) + (st.xp or 0) / (st.xpMax or 1)
  local pos = st.pos or {}
  local race = ns.clean(UnitRace and (UnitRace('player'))) or ''
  local class = ns.clean(UnitClass and (UnitClass('player'))) or ''
  local where = pos.map and (pos.x and ('%s %.1f, %.1f'):format(ns.Text.Map(pos.map), pos.x, pos.y)
    or ns.Text.Map(pos.map)) or '?'
  local step = s and ns.plain(ns.Text.Step(s, route.pack)) or '-'
  local lines = {
    ('BoF Guide %s, game %s.%s'):format(ns.VERSION, tostring(v), tostring(b)),
    ('Route: %s (%s)'):format(route and (route.title or route.id) or '-', route and route.id or '-'),
    ('Step: %s [%s]'):format(step, s and s.k or '-'),
    ('Level %s %s %s, %s'):format(ns.fmtLevel(level), race, class, ((st.faction or '?'):gsub('^%l', string.upper))),
    ('Where: %s'):format(where),
    ('When: %s'):format(date('%Y-%m-%d %H:%M')),
  }
  local blocked = ns.LastBlocked()
  if blocked then lines[#lines + 1] = 'Blocked: ' .. blocked end   -- (FB-012: the action the game stopped)
  return lines
end

-- ------------------------------------------------------------------------------------------------------ the box
local function paintKinds()
  for i, b in ipairs(kindButtons) do
    Skin.Choose(b, KINDS[i] == chosen)
  end
end

--- the four kind buttons as wide as the longest label, the box widened to hold them (German and French run long:
--- "Etwas funktioniert nicht", "Quelque chose est cassé"); measured once shown, when the text has its real size
local function fitKinds()
  local need = 0
  for _, b in ipairs(kindButtons) do need = math.max(need, (b.text:GetStringWidth() or 0) + 28) end
  local bw = math.max((WIDTH - 44 - 8) / 2, need)
  local w = math.max(WIDTH, bw * 2 + 8 + 44)
  frame:SetWidth(w)
  help:SetWidth(w - 44)
  nextLine:SetWidth(w - 48)
  edit:SetWidth(w - 72)
  for i, b in ipairs(kindButtons) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    b:SetWidth(bw)
    b:ClearAllPoints()
    b:SetPoint('TOPLEFT', help, 'BOTTOMLEFT', col * (bw + 8), -10 - row * 28)
  end
end

local function show(which)
  stage = which
  local writing = which == 'write'
  -- the box: under its label while you write, under the help for the link; above the line at the bottom either way
  -- (what happens next while you write; with the link, that an email left on the page brings word of the fix)
  scroll:ClearAllPoints()
  if writing then
    scroll:SetPoint('TOPLEFT', wordsLabel, 'BOTTOMLEFT', 0, -10)
  else
    scroll:SetPoint('TOPLEFT', help, 'BOTTOMLEFT', 2, -14)
  end
  scroll:SetPoint('BOTTOMRIGHT', nextLine, 'TOPRIGHT', -20, 12)
  for _, b in ipairs(kindButtons) do b:SetShown(writing) end
  nextLine:SetText(writing and L.feedbackNext or L.feedbackEmail)
  wordsLabel:SetShown(writing)
  status:SetText('')
  -- your words stop at 600 letters; the link is longer than that and must stay whole (FB-055: the box cut it at 600
  -- and the page opened empty)
  edit:SetMaxLetters(writing and 600 or 0)
  if writing then
    title:SetText(ns.upper(L.feedbackTitle))
    help:SetText(L.feedbackHelp)
    button.text:SetText(L.feedbackMake)
    edit:SetText('')
    paintKinds()
    edit:SetFocus()
  else
    help:SetText(L.feedbackCopyHelp)
    button.text:SetText(L.feedbackDone)
    edit:SetText(frame.note or '')
    edit:SetFocus()
    edit:HighlightText()
  end
end

--- the window's lines as shown (for tests, like Window.Lines)
function Feedback.Lines()
  local out = {}
  for _, s in ipairs({ title, help, wordsLabel, nextLine, status }) do
    if s and s:IsShown() and (s:GetText() or '') ~= '' then out[#out + 1] = s:GetText() end
  end
  return out
end

--- your kind and words into the link: kept, and shown selected to copy
function Feedback.Make(words)
  local t = Feedback.Payload(chosen, words, forKey)
  local link = Feedback.Link(t)
  ns.db.feedback = ns.db.feedback or {}
  table.insert(ns.db.feedback, { id = t.id, at = t.t, kind = t.k, words = t.w or '', link = link,
                                 route = t.r, step = t.sk })
  while #ns.db.feedback > KEEP do table.remove(ns.db.feedback, 1) end
  frame.note = link
  show('copy')
  ns.say(L.feedbackSaved)
  return link
end

function Feedback.Create()
  if frame then return frame end
  frame = CreateFrame('Frame', 'BoFGuideFeedback', UIParent)
  ns.Escapable(frame)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 60)
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
  local close = Skin.IconButton(frame, 18, 'btn-close', function() frame:Hide() end, 'BoFGuideFeedbackClose',
    { L.feedbackClose })
  close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -20, -18)
  help = Skin.String(frame, 'Small', 'OVERLAY', C.dim)
  help:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -6)
  help:SetWidth(WIDTH - 44)
  help:SetJustifyH('LEFT')

  -- the four kinds, two by two
  local bw = (WIDTH - 44 - 8) / 2
  for i, kind in ipairs(KINDS) do
    local b = Skin.Button(frame, bw, 24, L['feedbackKind_' .. kind], function()
      chosen = kind
      paintKinds()
    end, 'BoFGuideFeedbackKind' .. i)
    b.text:SetFontObject(Skin.Font.Small or Skin.Font.Button)
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    b:SetPoint('TOPLEFT', help, 'BOTTOMLEFT', col * (bw + 8), -10 - row * 28)
    kindButtons[i] = b
  end
  wordsLabel = Skin.String(frame, 'Small', 'OVERLAY', C.text)
  wordsLabel:SetPoint('TOPLEFT', kindButtons[3], 'BOTTOMLEFT', 2, -12)
  wordsLabel:SetText(L.feedbackWords)

  scroll = CreateFrame('ScrollFrame', 'BoFGuideFeedbackScroll', frame, 'UIPanelScrollFrameTemplate')
  local well = frame:CreateTexture(nil, 'ARTWORK')
  well:SetPoint('TOPLEFT', scroll, 'TOPLEFT', -6, 6)
  well:SetPoint('BOTTOMRIGHT', scroll, 'BOTTOMRIGHT', 6, -6)
  well:SetColorTexture(C.well[1], C.well[2], C.well[3], 0.9)
  Skin.Edge(frame, well)
  edit = CreateFrame('EditBox', 'BoFGuideFeedbackEdit', scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(Skin.Font.Text or ChatFontNormal)
  edit:SetWidth(WIDTH - 72)
  edit:SetMaxLetters(600)
  edit:SetScript('OnEscapePressed', function(self) self:ClearFocus() frame:Hide() end)
  -- in the copy stage the link stays whole and selected: typing there can't change it
  edit:SetScript('OnTextChanged', function(self, user)
    if user and stage == 'copy' then self:SetText(frame.note or '') self:HighlightText() end
  end)
  scroll:SetScrollChild(edit)
  scroll:SetScript('OnMouseDown', function() edit:SetFocus() end)

  nextLine = Skin.String(frame, 'Small', 'OVERLAY', C.dim)
  nextLine:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 24, 54)
  nextLine:SetWidth(WIDTH - 48)
  nextLine:SetJustifyH('LEFT')
  nextLine:SetText(L.feedbackNext)

  status = Skin.String(frame, 'Small', 'OVERLAY', C.danger)
  status:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 24, 22)
  status:SetWidth(WIDTH - 180)
  status:SetJustifyH('LEFT')
  button = Skin.Button(frame, 120, 26, '', function()
    if stage == 'write' then
      Feedback.Make(edit:GetText())
    else
      frame:Hide()
    end
  end, 'BoFGuideFeedbackButton')
  button.text:SetFontObject(Skin.Font.Button)
  button:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -22, 18)
  frame:Hide()
  return frame
end

-- never in combat: the box waits for the fight to end
local waiter
local function afterCombat(kind, key, words)
  waiter = waiter or CreateFrame('Frame')
  waiter.kind, waiter.key, waiter.words = kind, key, words   -- (the words too: a "Help us" answer was lost; Oct 20)
  waiter:RegisterEvent('PLAYER_REGEN_ENABLED')
  waiter:SetScript('OnEvent', function(self)
    self:UnregisterEvent('PLAYER_REGEN_ENABLED')
    Feedback.Show(self.kind, self.key, self.words)
  end)
end

--- open the box: `kind` preselected (a step card's right-click: 'step', for that card's `key`); `words` to start
--- from (the answer to a step's "Help us" question)
function Feedback.Show(kind, key, words)
  if InCombatLockdown and InCombatLockdown() then
    ns.say(L.feedbackCombat)
    return afterCombat(kind, key, words)
  end
  Feedback.Create()
  chosen, forKey = kind or 'step', key
  frame.note = nil
  frame:Show()
  fitKinds()
  show('write')
  if words then
    edit:SetText(words)
    edit:SetCursorPosition(#words)
  end
end

--- the last link made, again (/bofg feedback last)
function Feedback.Last()
  local list = ns.db.feedback
  local last = list and list[#list]
  if not (last and last.link) then return ns.say(L.feedbackNoLast) end
  Feedback.Create()
  frame.note = last.link
  frame:Show()
  title:SetText(ns.upper(L.feedbackTitle))
  show('copy')
end
