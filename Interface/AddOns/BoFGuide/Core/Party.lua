-- Bind on Forever Guide: your party's guides (Batch 4 of the RestedXP audit, Oct 18; "leveling with friends").
-- In a party the guide tells the others which version it is and what it's on now (an addon message to the party, at
-- most every 10 seconds, never in the game's chat lockdown); theirs come back. A newer version than yours is said
-- once (update on CurseForge), and the window's pace line lists each member's step in its tooltip.
local _, ns = ...
local Party = { members = {} }
ns.Party = Party

local PREFIX = 'BoFGuide'
local EVERY = 10
local lastSent, lastText, saidVersion = 0, nil, {}

local function vnum(v)
  local a, b, c = tostring(v or ''):match('^(%d+)%.(%d+)%.(%d+)')
  return a and (tonumber(a) * 1e6 + tonumber(b) * 1e3 + tonumber(c)) or 0
end

local function inParty() return IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) end

--- what we tell the party now: "1|<version>|<route>|<step words>" (under the 255 a message may carry)
function Party.Message()
  local route, view = ns.Engine.Route(), ns.Engine.View()
  local words = ''
  if route and view and view.cursor then
    local s = route.steps[view.cursor]
    words = ns.plain(ns.Text.Step(s, route.pack)) or ''
  end
  return ('1|%s|%s|%s'):format(ns.VERSION or '?', route and route.id or '-', words:gsub('|', '/'):sub(1, 180))
end

function Party.Send(force)
  if not inParty() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
  local now, text = GetTime(), Party.Message()
  if not force and (text == lastText or now - lastSent < EVERY) then return end
  lastSent, lastText = now, text
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, 'PARTY')
end

ns.On('CHAT_MSG_ADDON', function(prefix, text, _, sender)
  if prefix ~= PREFIX or type(text) ~= 'string' then return end
  local me = UnitName and ns.clean(UnitName('player'))
  local who = ns.clean(sender)
  if not who or (me and (who == me or who:match('^' .. me .. '%-'))) then return end
  local fmt, ver, route, words = text:match('^(%d+)|([^|]*)|([^|]*)|(.*)$')
  if fmt ~= '1' then return end
  local name = who:match('^([^%-]+)') or who
  Party.members[name] = { ver = ver, route = route, words = words, at = GetTime() }
  if vnum(ver) > vnum(ns.VERSION) and not saidVersion[ver] then
    saidVersion[ver] = true
    ns.say(ns.L.partyNewer:format(name, ver))
  end
  ns.MarkDirty('party')
end)

--- the tooltip lines for the pace line: { { text }, ... } for the members heard from in the last few minutes
function Party.Lines()
  local out, now = {}, GetTime()
  for name, m in pairs(Party.members) do
    if now - m.at < 300 and m.words ~= '' then out[#out + 1] = { ns.L.partyOn:format(name, m.words) } end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

ns.On('PLAYER_LOGIN', function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
end)
ns.On('GROUP_ROSTER_UPDATE', function()
  if not inParty() then Party.members = {} return end
  Party.Send(true)
end)
