local _, ns = ...

local floor = math.floor

--- nil for anything the client marks secret (or nil); the value otherwise
function ns.clean(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

function ns.say(msg) DEFAULT_CHAT_FRAME:AddMessage('|cffd9a441BoF Guide:|r ' .. tostring(msg)) end

--- run fn in pcall; errors are saved (first 50) instead of breaking the addon
function ns.safecall(tag, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    local list = ns.db and ns.db.errors
    if list and #list < 50 then list[#list + 1] = tag .. ': ' .. tostring(err) end
  end
  return ok, err
end

--- a title in capitals: Latin letters only, any three-byte character (Korean, Chinese) left as it is (they have no
--- capitals, and string.upper works on bytes)
function ns.upper(s)
  s = tostring(s or '')
  if s:find('[\224-\239]') then return s end
  return s:upper()
end

function ns.set(list)
  local s = {}
  if type(list) == 'table' then for _, v in ipairs(list) do s[v] = true end elseif list ~= nil then s[list] = true end
  return s
end

function ns.list(v)
  if v == nil then return {} end
  if type(v) == 'table' then return v end
  return { v }
end

--- 1 guide, 3 guides
--- a pop-up window closes with Escape, like the game's own (UISpecialFrames; the QA pass, Oct 20)
function ns.Escapable(frame)
  local name = frame and frame.GetName and frame:GetName()
  if name and UISpecialFrames then
    for _, n in ipairs(UISpecialFrames) do if n == name then return end end
    table.insert(UISpecialFrames, name)
  end
end

--- a counted line in the guide's language: L[key .. '_1'] for one (it has no %d), L[key] with n first otherwise.
--- (ns.plural glued an English "s" onto every language: "2 Stufes"; the QA pass, Oct 20)
function ns.count(key, n, ...)
  local one = n == 1 and ns.L[key .. '_1']
  if one then return one:format(...) end
  return ns.L[key]:format(n, ...)
end

function ns.round(v, d) local m = 10 ^ (d or 0) return floor(v * m + 0.5) / m end

--- 4.5 -> "4.5", 5 -> "5"
function ns.fmtLevel(v)
  if not v then return '?' end
  local r = ns.round(v, 1)
  if r == floor(r) then return tostring(floor(r)) end
  return tostring(r)
end

--- npc ID from a unit's GUID ("Creature-0-1-2-3-<id>-<spawn>"), nil when hidden or not a creature
function ns.npcID(unit)
  local guid = ns.clean(UnitGUID and UnitGUID(unit))
  if type(guid) ~= 'string' then return nil end
  local kind, _, _, _, _, id = strsplit('-', guid)
  if kind == 'Creature' or kind == 'Vehicle' then return tonumber(id) end
  return nil
end

--- text without its |c color codes (chat, the arrow's caption)
function ns.plain(t)
  return t and (t:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')) or t
end
