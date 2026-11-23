-- Adding a purchased guide (owner, Oct 16: "I don't want to rely on memory for / commands at all"): our own window in
-- the guide's look, opened from the guide's Settings page, the seal's menu, the full guide's link window and the
-- level-30 card. It says what to do in three steps, which account the copy works on, takes the paste, and lists the
-- guides already added, each with a Remove button (and Reload now, since a removed guide stays until a reload).
--
-- A long paste arrives as one OnChar per character within a single frame; we collect those and keep only the start in
-- the edit box (SetMaxBytes), because laying out a long string in an edit box can stall the game (the paid pack is
-- 28 KB). The same trick the big import windows use. Typing or a short paste still goes through the edit box as usual.
local _, ns = ...

local Import = {}
ns.Import = Import
local L = ns.L
local Skin = ns.Skin
local C = Skin.C
local WIDTH, SHOWN_BYTES, MAX_ROWS = 440, 2000, 6

local frame, title, steps, account, tagBox, tagHint, scroll, edit, status, button, yours, empty, reload, find
local rows = {}
local buffer, count, pastedAt, pasted = {}, 0, nil, nil

local function setStatus(text, color)
  status:SetText(text or '')
  status:SetTextColor(unpack(color or C.text))
end

local function finishPaste(self)
  self:SetScript('OnUpdate', nil)
  local text = table.concat(buffer, '', 1, count)
  buffer, count = {}, 0
  if #text > SHOWN_BYTES then
    pasted = text
    edit:SetText(text:sub(1, SHOWN_BYTES))
    setStatus(L.importPasted:format(#text))
  else
    pasted = nil
  end
end

local function onChar(self, c)
  local now = GetTime()
  if pastedAt ~= now then
    buffer, count, pastedAt = {}, 0, now
    self:SetScript('OnUpdate', finishPaste)
  end
  count = count + 1
  buffer[count] = c
end

--- the guides added on this account, each with a Remove button; then the window's height from its parts
local function layout()
  if not frame then return end
  local ids, seen = {}, {}
  for id in pairs(ns.db and ns.db.imports or {}) do ids[#ids + 1], seen[id] = id, true end
  -- and the ones a key opened on this character (Core/Paid.lua)
  for id in pairs(ns.Paid and ns.Paid.loaded or {}) do if not seen[id] then ids[#ids + 1] = id end end
  table.sort(ids)
  local prev = yours
  for i = 1, MAX_ROWS do
    local r, id = rows[i], ids[i]
    if id then
      local p = ns.Packs.byId[id]
      r.text:SetText((p and p.title) or id)
      r.id = id
      r:ClearAllPoints()
      r:SetPoint('TOPLEFT', prev, 'BOTTOMLEFT', 0, i == 1 and -6 or -4)
      r:Show()
      prev = r
    else
      r:Hide()
    end
  end
  empty:SetShown(#ids == 0)
  local function sh(fs, d) return fs:GetStringHeight() or d end
  local h = 20 + sh(title, 20) + 10 + sh(steps, 40) + 6 + sh(account, 14) + (tagBox:IsShown() and (6 + 24 + 4 + sh(tagHint, 14)) or 0)
    + 12 + 96 + 10 + 28 + sh(status, 14) + 8 + sh(find, 14)
    + 18 + sh(yours, 14) + (#ids == 0 and (6 + sh(empty, 14)) or (2 + math.min(#ids, MAX_ROWS) * 26)) + 56
  frame:SetHeight(h)
end

--- the website's Find my order page in the guide's language, without https:// (it's read, then typed)
function Import.FindURL() return (ns.SiteURL('/guide/order/find'):gsub('^https?://', '')) end

--- add whatever was pasted; returns the pack or nil and why
function Import.Run(text)
  text = text or pasted or (edit and edit:GetText()) or ''
  -- a key (Core/Paid.lua): entered once, it opens the paid guides in this and every later download
  local short = text:gsub('%s+', ''):upper()
  if short:sub(1, 3) == 'BOF' and short:sub(1, 7) ~= '!BOFG1!' then
    -- (the packs open a slice a frame, about a second: Core/Paid.lua; what opened is said once they have)
    local ok, kwhy = ns.Paid.Add(text, function(titles, ids)
      local msg = #titles > 0 and L.keyAdded:format(table.concat(titles, ', ')) or L.keySaved
      ns.say(msg)
      if frame then
        pasted = nil
        edit:SetText('')
        setStatus(msg, C.good or { 0.55, 0.9, 0.55 })
        layout()
      end
      ns.MarkDirty('packs')
      for _, id in ipairs(ids) do
        local p = ns.Packs.byId[id]
        if p and ns.Engine.AfterImport then ns.safecall('afterImport', ns.Engine.AfterImport, p) end
      end
    end)
    if not ok then
      local msg = L['import_' .. (kwhy == 'notkey' and 'notpack' or tostring(kwhy))] or tostring(kwhy)
      if status then setStatus(msg, C.danger) end
      ns.say(msg)
      return nil, kwhy
    end
    return true
  end
  local pack, why = ns.Packs.Import(text)
  if not pack then
    local msg = L['import_' .. tostring(why)] or tostring(why)
    if status then setStatus(msg, C.danger) end
    ns.say(msg)
    return nil, why
  end
  local n = 0
  for _ in ipairs(pack.routes) do n = n + 1 end
  local msg = L.imported:format(pack.title or pack.id, ns.count('guideCount', n))
  ns.say(msg)
  if frame then
    pasted = nil
    edit:SetText('')
    setStatus(msg, C.good or { 0.55, 0.9, 0.55 })
    layout()
  end
  ns.MarkDirty('packs')
  if ns.Engine.AfterImport then ns.safecall('afterImport', ns.Engine.AfterImport, pack) end
  return pack
end

--- remove an added guide: it stays until the interface reloads, so the button to do that shows
function Import.Remove(id)
  if not ns.Packs.Forget(id) and not (ns.Paid and ns.Paid.Forget(id)) then return false end
  local p = ns.Packs.byId[id]
  local msg = L.importRemoved:format((p and p.title) or id)
  ns.say(msg)
  if frame then
    setStatus(msg)
    reload:Show()
    layout()
  end
  return true
end

function Import.Create()
  if frame then return frame end
  frame = CreateFrame('Frame', 'BoFGuideImportFrame', UIParent)
  ns.Escapable(frame)
  frame:SetSize(WIDTH, 380)
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
  title:SetWidth(WIDTH - 80)
  title:SetJustifyH('LEFT')
  title:SetText(ns.upper(L.importTitle))
  local close = Skin.IconButton(frame, 18, 'btn-close', function() frame:Hide() end, 'BoFGuideImportClose',
    { L.linkClose })
  close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -20, -18)

  steps = Skin.String(frame, 'Text', 'OVERLAY', C.text)
  steps:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -10)
  steps:SetWidth(WIDTH - 44)
  steps:SetJustifyH('LEFT')
  steps:SetText(L.importSteps)
  account = Skin.String(frame, 'Small', 'OVERLAY', C.dim)
  account:SetPoint('TOPLEFT', steps, 'BOTTOMLEFT', 0, -6)
  account:SetWidth(WIDTH - 44)
  account:SetJustifyH('LEFT')
  -- the BattleTag itself, in a face where I and l differ, to copy rather than retype (Oct 19)
  tagBox = Skin.TagBox(frame, 'BoFGuideImportTag')
  tagBox:SetPoint('TOPLEFT', account, 'BOTTOMLEFT', 0, -6)
  tagHint = Skin.String(frame, 'Small', 'OVERLAY', C.dim)
  tagHint:SetPoint('TOPLEFT', tagBox, 'BOTTOMLEFT', 0, -4)
  tagHint:SetWidth(WIDTH - 44)
  tagHint:SetJustifyH('LEFT')
  tagHint:SetText(L.tagCopy)

  scroll = CreateFrame('ScrollFrame', 'BoFGuideImportScroll', frame, 'UIPanelScrollFrameTemplate')
  scroll:SetPoint('TOPLEFT', account, 'BOTTOMLEFT', 4, -14)
  scroll:SetSize(WIDTH - 72, 92)
  local well = frame:CreateTexture(nil, 'ARTWORK')
  well:SetPoint('TOPLEFT', scroll, 'TOPLEFT', -6, 6)
  well:SetPoint('BOTTOMRIGHT', scroll, 'BOTTOMRIGHT', 6, -6)
  well:SetColorTexture(C.well[1], C.well[2], C.well[3], 0.9)
  Skin.Edge(frame, well)
  edit = CreateFrame('EditBox', 'BoFGuideImportEdit', scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(Skin.Font.Small or ChatFontNormal)
  edit:SetWidth(WIDTH - 76)
  edit:SetMaxBytes(SHOWN_BYTES)
  edit:SetScript('OnChar', onChar)
  edit:SetScript('OnEscapePressed', function(self) self:ClearFocus() frame:Hide() end)
  edit:SetScript('OnTextChanged', function(self, user)
    if user and not pasted then setStatus('') end
  end)
  scroll:SetScrollChild(edit)
  scroll:SetScript('OnMouseDown', function() edit:SetFocus() end)

  button = Skin.Button(frame, 140, 26, L.importButton, function() Import.Run() end, 'BoFGuideImportButton')
  button.text:SetFontObject(Skin.Font.Button)
  button:SetPoint('TOPLEFT', scroll, 'BOTTOMLEFT', -6, -12)
  button:SetWidth(math.max(140, (button.text:GetStringWidth() or 0) + 48))
  reload = Skin.Button(frame, 140, 26, L.importReload, function() ns.Reload() end, 'BoFGuideImportReload')
  reload.text:SetFontObject(Skin.Font.Button)
  reload:SetPoint('LEFT', button, 'RIGHT', 10, 0)
  reload:Hide()

  status = Skin.String(frame, 'Small', 'OVERLAY', C.text)
  status:SetPoint('TOPLEFT', button, 'BOTTOMLEFT', 6, -8)
  status:SetWidth(WIDTH - 44)
  status:SetJustifyH('LEFT')

  -- a lost key: the website's Find my order page sends it again (owner, Oct 28)
  find = Skin.String(frame, 'Small', 'OVERLAY', C.dim)
  find:SetPoint('TOPLEFT', status, 'BOTTOMLEFT', 0, -8)
  find:SetWidth(WIDTH - 44)
  find:SetJustifyH('LEFT')
  find:SetText(L.keyFind:format(Import.FindURL()))

  yours = Skin.String(frame, 'Label', 'OVERLAY', C.gold)
  yours:SetPoint('TOPLEFT', find, 'BOTTOMLEFT', 0, -18)
  yours:SetText(ns.upper(L.importYours))
  empty = Skin.String(frame, 'Small', 'OVERLAY', C.dim)
  empty:SetPoint('TOPLEFT', yours, 'BOTTOMLEFT', 0, -6)
  empty:SetText(L.importEmpty)
  for i = 1, MAX_ROWS do
    local r = CreateFrame('Frame', nil, frame)
    r:SetSize(WIDTH - 44, 22)
    r.text = Skin.String(r, 'Text', 'OVERLAY', C.text)
    r.text:SetPoint('LEFT', r, 'LEFT', 0, 0)
    r.remove = Skin.Button(r, 90, 20, L.importRemove, function() Import.Remove(r.id) end, 'BoFGuideImportRemove' .. i)
    r.remove.text:SetFontObject(Skin.Font.Small or Skin.Font.Button)
    r.remove:SetPoint('RIGHT', r, 'RIGHT', 0, 0)
    r:Hide()
    rows[i] = r
  end

  frame:SetScript('OnHide', function() pasted, buffer, count = nil, {}, 0 end)
  frame:Hide()
  return frame
end

--- open the window (the Settings page, the seal's menu, the full guide's window, the level-30 card, /bofg import)
function Import.Show()
  Import.Create()
  pasted = nil
  edit:SetText('')
  setStatus('')
  reload:Hide()
  local tag = ns.Packs.BattleTag()
  account:SetText(tag and L.importAccountOn or L.import_notag)
  tagBox:SetShown(tag and true or false)
  tagHint:SetShown(tag and true or false)
  if tag then tagBox:SetTag(tag) end
  scroll:ClearAllPoints()
  scroll:SetPoint('TOPLEFT', tag and tagHint or account, 'BOTTOMLEFT', 4, -14)
  frame:Show()
  layout()
  if C_Timer and C_Timer.After then C_Timer.After(0, function() if frame:IsShown() then layout() end end) end
  edit:SetFocus()
end

function Import.AccountText()   -- (tests) the line, then the tag in its box
  return account and (account:GetText() .. (tagBox:IsShown() and (' ' .. (tagBox:GetText() or '')) or ''))
end

--- (tests) the guides listed, by id
function Import.Listed()
  local out = {}
  for _, r in ipairs(rows) do if r:IsShown() then out[#out + 1] = r.id end end
  return out
end
