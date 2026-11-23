-- Step text, built at run time from IDs so it follows the client's language: quest titles from the quest cache,
-- objective lines straight from the quest log, items and zones from the client. Titles the client hasn't cached yet
-- are requested (a few at a time) and the window refreshes when they arrive; until then the pack's English name shows.
local _, ns = ...

local Text = {}
ns.Text = Text
local L = ns.L
local requested, budget = {}, 0

local function list(v) if type(v) == 'table' then return v end if v == nil then return {} end return { v } end

function Text.ResetBudget() budget = 5 end

function Text.Quest(q, pack)
  local t = ns.clean(C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q))
  if t and t ~= '' then return t end
  if not requested[q] and budget > 0 and C_QuestLog.RequestLoadQuestByID then
    requested[q] = true
    budget = budget - 1
    C_QuestLog.RequestLoadQuestByID(q)
  end
  local info = pack and pack.quests and pack.quests[q]
  return (info and info.t) or L.quest:format(q)
end

--- coin as the game writes it: 1g 2s 3c
function Text.Money(c)
  c = math.floor(c or 0)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  -- (the game's own letters, in your client's language)
  local G, S, K = GOLD_AMOUNT_SYMBOL or ns.L.gold, SILVER_AMOUNT_SYMBOL or ns.L.silver, COPPER_AMOUNT_SYMBOL or ns.L.copper
  if g > 0 then out[#out + 1] = g .. G end
  if s > 0 then out[#out + 1] = s .. S end
  if k > 0 or #out == 0 then out[#out + 1] = k .. K end
  return table.concat(out, ' ')
end

--- what's left of a buy list comes to, in copper (vendors sell by the stack), or nil when no price is known
function Text.BuyCost(step)
  local total, known = 0, false
  for _, b in ipairs(step.buy or {}) do
    if type(b) == 'table' and b[3] and b[4] then
      local have = ns.st and ns.st.items and ns.st.items[b[1]] or 0
      local left = math.max(0, (b[2] or 1) - have)
      total = total + math.ceil(left / b[4]) * b[3]
      known = true
    end
  end
  return known and total or nil
end

function Text.Npc(id, pack)
  return (pack and pack.npcs and pack.npcs[id]) or L.npc:format(id)
end

function Text.Item(id, pack)
  local name = ns.clean(C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
  if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return name or (pack and pack.items and pack.items[id]) or L.item:format(id)
end

function Text.Map(map)
  local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return (info and ns.clean(info.name)) or ''
end

--- a recipe's name in the client's language, else the pack's
function Text.Spell(id, fallback)
  local name = ns.clean(C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
  return name or fallback or ('#' .. tostring(id))
end

--- about how many crafts a craft step still takes: its share of the planned crafts for the points left
function Text.CraftsLeft(step)
  local n, to, from = step.n or 0, step.un or 1, step.fr or 1
  local rank = ns.st.profs and ns.st.profs[step.sk]
  if type(rank) ~= 'number' or rank <= from or to <= from then return n end
  if rank >= to then return 0 end
  return math.ceil(n * (to - rank) / (to - from))
end

--- "Linen Cloth 12/40, Coarse Thread 3/10" for the crafts left
function Text.Reagents(step, left, pack)
  local parts = {}
  for _, rg in ipairs(step.rg or {}) do
    local have = ns.st.items[rg[1]] or 0
    local need = rg[2] * left
    local line = ('%s %d/%d'):format(Text.Item(rg[1], pack), math.min(have, need), need)
    parts[#parts + 1] = have >= need and ('|cff8ccf8c' .. line .. '|r') or line
  end
  return #parts > 0 and table.concat(parts, ', ') or nil
end

-- color by meaning, for the window (Text.Step(step, pack, true)): quest names in the tooltip's quest gold, people
-- in white, enemies in the game's hostile red, items in their quality color. Chat and the arrow get plain text.
local paint = false
local function Q(s) return paint and ('|cffffd100' .. s .. '|r') or s end
local function P(s) return paint and ('|cffffffff' .. s .. '|r') or s end
local function M(s) return paint and ('|cffff4646' .. s .. '|r') or s end
local function I(s, id)
  if not paint then return s end
  local q = id and C_Item and C_Item.GetItemQualityByID and ns.clean(C_Item.GetItemQualityByID(id))
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  return (c and c.hex or '|cffffffff') .. s .. '|r'
end
Text.Paint = { quest = function(s) return Q(s) end, person = function(s) return P(s) end }

local function quests(step, pack)
  local names = {}
  for _, q in ipairs(list(step.id)) do names[#names + 1] = Q(Text.Quest(q, pack)) end
  return table.concat(names, ', ')
end

local function npcs(ids, pack, enemy)
  local names = {}
  for _, id in ipairs(list(ids)) do names[#names + 1] = (enemy and M or P)(Text.Npc(id, pack)) end
  return table.concat(names, ', ')
end

--- objective lines for a quest in the log, as the client writes them ("Mindless Zombie slain: 3/8")
function Text.Objectives(q, ob)
  local e = ns.st.log[q]
  if not e then return nil end
  local out = {}
  for k, o in ipairs(e.obj) do
    if (not ob or ob == k) and o.text and not o.fin then out[#out + 1] = o.text end
  end
  return #out > 0 and table.concat(out, '\n') or nil
end

local function stepText(step, pack)
  local o, L_ = step.o, L
  local pts = pack.pts or {}
  local p = step.p and pts[step.p]
  if o == 'accept' and step.fi then return L_.acceptItem:format(quests(step, pack), I(Text.Item(step.fi, pack), step.fi))
  elseif o == 'accept' then return L_.accept:format(quests(step, pack))
  elseif o == 'turnin' then return L_.turnin:format(quests(step, pack))
  elseif o == 'complete' then
    local q = list(step.id)[1]
    return L_.complete:format(quests(step, pack)), Text.Objectives(q, step.ob)
  elseif o == 'kill' then
    if step.q then return L_.killFor:format(npcs(step.id, pack, true), Q(Text.Quest(step.q, pack))), Text.Objectives(step.q, step.qo) end
    return L_.kill:format(npcs(step.id, pack, true))
  elseif o == 'collect' then
    local name = I(Text.Item(step.id), step.id)
    local line = step.n and L_.collectN:format(step.n, name) or L_.collect:format(name)
    return line, step.q and Text.Objectives(step.q, step.qo) or nil
  elseif o == 'goto' then
    if step.npc then return L_.gotoNpc:format(P(Text.Npc(step.npc, pack))) end
    if p then return L_['goto']:format(Text.Map(p[1]), p[2], p[3]) end
    return L_.gotoNpc:format(L_.unknownPlace)
  elseif o == 'fp' then return L_.fp:format(step.name or L_.node:format(step.id))
  elseif o == 'fly' then
    local line = L_.fly:format(step.name or L_.node:format(step.id))
    -- (a flight path the guide hasn't seen you learn: say what happens if you don't have it. Nov 9, never stranded)
    if type(step.id) == 'number' and not (ns.st.taxi and ns.st.taxi[step.id]) then return line, L_.flyMaybe end
    return line
  elseif o == 'hearth' then
    local bind = ns.st.bind
    -- set somewhere else than the inn the route bound you at (and we saw where): it takes you there instead
    local bn, mine = step.bn, ns.st.bindNpc
    if bind and bn and mine and mine ~= bn then return L_.hearthElsewhere:format(bind), L_.hearthElsewhereWhy end
    return bind and L_.hearth:format(bind) or L_.hearthAny
  elseif o == 'sethome' then return L_.sethome:format(P(Text.Npc(step.npc, pack)))
  elseif o == 'vendor' then
    local line = L_.vendor:format(P(Text.Npc(step.npc, pack)))
    local buys = {}
    for _, b in ipairs(Text.Buys(step)) do
      -- (what you hold counted off: "buy 300 more", not 1,800 more on top of 1,500. Nov 8, the RestedXP items study)
      local have, need = ns.st and ns.st.items and ns.st.items[b[1]] or 0, b[2] or 1
      if have > 0 and have < need then
        buys[#buys + 1] = L_.buyMore:format(need - have, I(Text.Item(b[1], pack), b[1]))
      else
        buys[#buys + 1] = L_.buy:format(need, I(Text.Item(b[1], pack), b[1]))
      end
    end
    if #buys > 0 then line = line .. ', ' .. table.concat(buys, ', ') end
    -- what it comes to, and when you're short (Nov 9, never stranded: a buy stop with too little coin)
    local cost = Text.BuyCost(step)
    if cost and cost > 0 then
      line = line .. ' ' .. L_.buyCost:format(Text.Money(cost))
      local cash = ns.st and ns.st.cash
      if cash and cash < cost then return line, L_.buyShort:format(Text.Money(cash)) end
    end
    return line
  elseif o == 'abandon' then return L_.abandon:format(quests(step, pack))
  elseif o == 'equip' then return L_.equip:format(I(Text.Item(step.id, pack), step.id))
  elseif o == 'train' then return step.npc and L_.trainAt:format(P(Text.Npc(step.npc, pack))) or L_.train
  elseif o == 'camp' then return L_.camp
  elseif o == 'xp' then
    -- (a part level reads as one: "Reach level 7, 20% of the way to 8", not "7.2"; the QA pass, Oct 20)
    local lv = step.lv or 0
    local whole, part = math.floor(lv), math.floor((lv - math.floor(lv)) * 100 + 0.5)
    if part > 0 and part < 100 then return L_.xpPart:format(whole, part, whole + 1) end
    return L_.xp:format(tostring(math.floor(lv + 0.5)))
  elseif o == 'skill' then return L_.skill:format((L_.PROFS and L_.PROFS[step.sk]) or step.sk or '?', step.rk or 0)
  elseif o == 'use' then
    if step.on then return L_.useOn:format(I(Text.Item(step.id), step.id), M(Text.Npc(step.on, pack))) end
    return L_.use:format(I(Text.Item(step.id), step.id))
  elseif o == 'boss' then
    return (step.bv and L_.bossEvent or L_.boss):format(M(step.name or L_.npc:format(step.id or 0)))
  elseif o == 'enter' then return L_.enter:format(step.name or (p and Text.Map(p[1])) or '')
  elseif o == 'legacy' then
    if not step.name then return L_.legacyNext, step.desc end
    return L_.legacy:format(M(step.name)), step.desc
  elseif o == 'dungeon' then
    local r = ns.Packs.Get(step.dg)
    if not r then return L_.dungeonUnknown, L_.dungeonMissing end
    return L_.dungeon:format(r.title or r.id, r.lv and r.lv[1] or 0, r.lv and r.lv[2] or 0),
      step.an and L_.dungeonLegacy:format(step.an) or L_.dungeonHint
  elseif o == 'craft' then
    local name, left = Text.Spell(step.id, step.name), Text.CraftsLeft(step)
    local rank = ns.st.profs and ns.st.profs[step.sk]
    local main = (type(rank) == 'number' and left > 0) and L_.craftMore:format(name, step.un or 0, left)
      or L_.craft:format(name, step.un or 0)
    return main, Text.Reagents(step, left, pack)
  elseif o == 'gather' or o == 'skin' or o == 'fish' then
    local zone = Text.Map(step.zn)
    local main
    if o == 'fish' then main = L_.fish:format(zone, step.un or 0)
    else
      local verb = o == 'skin' and L_.skin or (step.sk == 'herbalism' and L_.pick or L_.mine)
      main = verb:format(step.name or '?', zone, step.un or 0)
    end
    -- the skill points left, read live from your skill (the owner, Nov 13: "about 186 to go" at 146 of 150 was a
    -- planned catch count, and catches per point vary anyway)
    local rank, to = ns.st.profs and ns.st.profs[step.sk], step.un or 0
    if type(rank) == 'number' and to > rank then main = main .. ' ' .. ns.count('skillToGo', to - rank) end
    local i = step.lp and ns.Engine and ns.Engine.LoopStop(step)
    return main, i and L_.loopStop:format(i, #step.lp) or nil
  elseif o == 'learn' then return L_.learn:format(Text.Spell(step.id, step.name))
  elseif o == 'rank' then
    local prof = L_.PROFS[step.sk] or step.sk or '?'
    if (step.rk or 0) <= 75 then return L_.learnProf:format(prof) end   -- "Learn Cooking", not "Train Apprentice"
    local rank = L_.RANKS[step.rk]
    return rank and L_.rank:format(rank, prof) or L_.rankAny:format(prof)
  end
  return o
end

--- a vendor step's buy list, { {item, count}, ... } (older packs carried one pair)
function Text.Buys(step)
  local b = step.buy
  if type(b) ~= 'table' then return {} end
  if type(b[1]) == 'number' then return { b } end
  return b
end

--- the main line for a step, plus an optional detail line; rich = names colored by meaning (the window). A route's
--- own `say` line is the main line when it has one.
function Text.Step(step, pack, rich)
  paint = rich and true or false
  local ok, main, detail = pcall(stepText, step, pack)
  paint = false
  if not ok then error(main, 0) end
  if step.sy and not Text.WayDone(step) then return step.sy, detail end
  -- a walk whose own words are behind you (the portal), ending at someone: the card names who you're walking to (Nov 7,
  -- Darnassus: "Talk to Chief Archaeologist Greywhisker" came only once the owner stood beside him)
  if step.o == 'goto' and step.sy and ns.Engine and ns.Engine.WalkLeadsTo then
    local to = ns.Engine.WalkLeadsTo(step)
    local who = to and ((to.who and to.who[1]) or to.npc)
    if who then
      paint = rich and true or false
      local name = P(Text.Npc(who, pack))
      paint = false
      return L.talkTo:format(name), detail
    end
  end
  return main, detail
end

--- a walk's own words are about the way there: once its stops are behind you they're stale (Nov 5: "Take the portal
--- in Rut'theran" stayed the title in Darnassus, after the portal). Not while you still stand at its last stop: that's
--- where you board the zeppelin or the boat, or step into the portal, and its words say what to do there (Nov 7, the
--- Horde eyeglass pass: at the tower the zeppelin card read only "Go to Durotar 50.8, 13.8")
local AT_LAST_STOP = 40   -- yards
function Text.WayDone(step)
  -- a say written for the walk's first stops gives way once you're past them (the portal, then the city beyond)
  local at = step.sw and ns.cdb and ns.cdb.paths and ns.cdb.paths[step.k]
  if at and at > step.sw then return true end
  -- ... and a say written from the walk's start gives way when you joined it further on (from Elwynn, a walk out of
  -- Stormwind's gate: the card says where to go instead)
  local join = step.pa and ns.cdb and ns.cdb.pathJoin and ns.cdb.pathJoin[step.k]
  if join and join > 1 and join <= #step.pa then return true end   -- (all of it skipped: below)
  if not (ns.Engine and ns.Engine.PathDone and ns.Engine.PathDone(step)) then return false end
  local route = ns.Engine.Route and ns.Engine.Route()
  local last = step.pa and step.pa[#step.pa]
  local pt = last and route and route.pack and route.pack.pts and route.pack.pts[last]
  local yards = pt and ns.Geo and ns.Geo.YardsTo(pt)
  if yards and yards <= AT_LAST_STOP then return false end
  return true
end

-- ------------------------------------------------------------------------------------------------- the step card
local WINDS = { 'north', 'north-west', 'west', 'south-west', 'south', 'south-east', 'east', 'north-east' }

--- "120 yd north-east" from where you stand to a pack point (world bearing, so it reads the same as the map)
function Text.Away(p)
  local pos = ns.st.pos
  if not (p and pos and pos.x) then return nil end
  local c1, ax, ay = ns.Geo.World(pos.map, pos.x, pos.y)
  local c2, bx, by = ns.Geo.World(p[1], p[2], p[3])
  if not (c1 and c2) or c1 ~= c2 then return nil end
  local yards = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
  if yards < 8 then return L.awayHere end
  local a = math.atan2(by - ay, bx - ax) % (2 * math.pi)   -- counter-clockwise from north (x north, y west)
  local wind = WINDS[math.floor(a / (math.pi / 4) + 0.5) % 8 + 1]
  return L.away:format(math.floor(yards + 0.5), L.WINDS[wind] or wind)
end

--- a quest level in the game's difficulty color for your level
function Text.QuestLevel(lv)
  if not lv then return nil end
  local c
  if GetQuestDifficultyColor then c = GetQuestDifficultyColor(lv) end
  if not (c and c.r) then
    local d = lv - (ns.st.level or 1)
    c = d >= 5 and { r = 1, g = 0.1, b = 0.1 } or d >= 3 and { r = 1, g = 0.5, b = 0.25 }
      or d >= -2 and { r = 1, g = 1, b = 0 } or { r = 0.25, g = 0.75, b = 0.25 }
  end
  return ('|cff%02x%02x%02x%s|r'):format(c.r * 255, c.g * 255, c.b * 255, L.questLevel:format(lv))
end

--- the objectives of a quest in your log, with counts: { text, have, need, fin }
function Text.ObjectiveList(q, only)
  local e = q and ns.st.log[q]
  local out = {}
  if not e then return out end
  for k, o in ipairs(e.obj) do
    if not only or only == k then
      local text = o.text or ''
      text = text:gsub('%s*:?%s*%d+%s*/%s*%d+%s*$', ''):gsub('^%d+%s*/%s*%d+%s*', '')   -- the count goes in its own column
      out[#out + 1] = { text = text, have = o.have or 0, need = o.need or 1, fin = o.fin }
    end
  end
  return out
end

local function addLine(c, style, text, color) if text and text ~= '' then c.lines[#c.lines + 1] = { style, text, color } end end

--- everything a step's card shows: the action, who and where, the live objectives, warnings and tips.
--- Returns { main, lines = {{style, text, color}}, obj = {{text, have, need, fin}}, warn = {...}, tips = {...} }
function Text.Card(step, pack)
  local Skin = ns.Skin
  local o = step.o
  local main, detail = Text.Step(step, pack, true)
  local c = { main = main, lines = {}, obj = {}, warn = {}, tips = {} }
  local cash = ns.st.cash or 0
  if step.cash and cash < step.cash then
    -- gathering the coin for a trainer: loot gray items as you go, then sell them (how far along, in copper)
    paint = true
    c.main = L.cashGather:format(P(Text.Npc(step.npc, pack)))
    paint = false
    c.obj[1] = { text = L.cashCopper, have = cash, need = step.cash, fin = false }
    -- and why (Oct 18, the owner's daughter: "Why are we collecting grays to sell to Brother Danil?")
    local cost = step.cash >= 100 and L.silverAmount:format(math.floor(step.cash / 100)) or L.copperAmount:format(step.cash)
    c.lines[#c.lines + 1] = { 'Text', L.cashWhy:format(cost, Text.Npc(step.npc, pack)) }
    return c
  end
  local qs = list(step.id)
  local info = pack.quests and pack.quests[qs[1]]
  -- who: the quest's giver or the npc it goes back to
  if step.who and (o == 'accept' or o == 'turnin') then
    paint = true
    local who = npcs(step.who, pack)
    paint = false
    addLine(c, 'Text', (o == 'accept' and L.whoFrom or L.whoTo):format(who), Skin.C.dim)
  elseif step.npc and (o == 'vendor' or o == 'train' or o == 'sethome' or o == 'goto') then
    -- the main line already names them
  end
  -- what kind of quest: its level (colored for you), and what it leads to; then what it asks, in its own words
  if o == 'accept' and info then
    local bits = { Text.QuestLevel(info.lv) }
    if info.nx and pack.quests[info.nx] then bits[#bits + 1] = L.leadsTo:format('|cffffd100' .. Text.Quest(info.nx, pack) .. '|r') end
    addLine(c, 'Small', table.concat(bits, '  ·  '), Skin.C.dim)
    addLine(c, 'Small', Text.Says(qs[1], pack), Skin.C.dim)
  end
  if o == 'train' and step.sp then c.train = Text.TrainList(step) end
  if o == 'hearth' then   -- the stone's hour isn't up yet: say when, so you can fly or walk instead
    local left = Text.HearthLeft()
    if left and left >= 60 then addLine(c, 'Small', L.hearthWait:format(math.ceil(left / 60)), Skin.C.ember) end
  end
  -- a long way on foot: your Hearthstone or a flight you know, when either is much quicker (Engine.FasterWay)
  local faster = ns.Engine and ns.Engine.FasterWay and ns.Engine.FasterWay(step)
  if faster then addLine(c, 'Small', faster, Skin.C.ember) end
  if o == 'fp' and ns.Engine and ns.Engine.FlyLater and ns.Engine.FlyLater(step) then
    addLine(c, 'Small', L.fpLater, Skin.C.dim)
  end
  -- objectives, live from the quest log
  if o == 'complete' then
    for _, q in ipairs(qs) do for _, x in ipairs(Text.ObjectiveList(q, step.ob)) do c.obj[#c.obj + 1] = x end end
  elseif (o == 'kill' or o == 'collect' or o == 'use') and step.q then
    c.obj = Text.ObjectiveList(step.q, step.qo)
  elseif o == 'vendor' and step.buy then   -- what to buy, counted from your bags
    for _, b in ipairs(Text.Buys(step)) do
      local have, need = ns.st.items[b[1]] or 0, b[2] or 1
      c.obj[#c.obj + 1] = { text = Text.Item(b[1], pack), have = math.min(have, need), need = need, fin = have >= need }
    end
  elseif o == 'craft' then
    local left = Text.CraftsLeft(step)
    for _, rg in ipairs(step.rg or {}) do
      local have, need = ns.st.items[rg[1]] or 0, rg[2] * left
      c.obj[#c.obj + 1] = { text = Text.Item(rg[1], pack), have = math.min(have, need), need = need, fin = have >= need }
    end
  elseif detail and o ~= 'turnin' and o ~= 'accept' then
    addLine(c, 'Text', detail, Skin.C.dim)
  end
  if o == 'turnin' and info and ns.st.log[qs[1]] and not ns.st.log[qs[1]].ready then
    addLine(c, 'Small', L.notReady, Skin.C.ember)
  end
  -- a step with no place: made with a profession, or not mapped by any data yet (BoFCapture maps it as you do it)
  if step.mw == 'fishing' then   -- (fish come from their own waters, never "wherever you are")
    addLine(c, 'Small', L.fishedWith, Skin.C.dim)
  elseif step.mw then
    addLine(c, 'Small', L.madeWith:format(L.PROFS[step.mw] or step.mw), Skin.C.dim)
  elseif not step.p and not step.fi and (o == 'complete' or o == 'accept' or o == 'turnin') then
    addLine(c, 'Small', L.notMapped, Skin.C.dim)
  end
  -- where, and how far from here
  local p = step.p and pack.pts and pack.pts[step.p]
  if step.lp and ns.Engine and ns.Engine.LoopStop then
    local i = ns.Engine.LoopStop(step)
    p = i and pack.pts[step.lp[i]] or p
  end
  local from = ns.Engine and ns.Engine.FlyFrom and ns.Engine.FlyFrom(step)
  if from then p = from end   -- (a flight: its flight master, until you're in the air)
  if p then
    local where = ('%s %.1f, %.1f'):format(Text.Map(p[1]), p[2], p[3])
    local away = Text.Away(p)
    c.where = away and (where .. '  ·  ' .. away) or where
  end
  c.warn, c.warnKind = Text.Warnings(step, pack)
  -- (Oct 11, the owner: "use the necklace" sat in a grey tip. An action with an item and where in a place each get
  -- their own line, above the tips: c.uses { item, text }, c.wheres)
  c.uses, c.wheres, c.asks = {}, {}, {}
  for _, ni in ipairs(step.nt or {}) do
    local note = pack.notes and pack.notes[ni]
    if note and note.y then   -- (why it's optional: under the card's title, Text.Why)
    elseif note and note.a then c.asks[#c.asks + 1] = note.t   -- (what we still need to learn here: Help us)
    elseif note and note.u then c.uses[#c.uses + 1] = { item = note.u, text = note.t }
    elseif note and note.w then c.wheres[#c.wheres + 1] = note.t
    elseif note and not note.d then c.tips[#c.tips + 1] = note.t end
  end
  return c
end

--- why an optional step is optional, in the pack's words (src/forever/guide/optwhy.py; the owner, Nov 7: "there isn't
--- much context provided as to why it's being labeled as optional"), or nil
function Text.Why(step, pack)
  if not (step and step.opt) then return nil end
  for _, ni in ipairs(step.nt or {}) do
    local note = pack and pack.notes and pack.notes[ni]
    if note and note.y and note.t then return note.t end
  end
  return nil
end

--- a step's warnings, shown wherever the step is (card or next row), every time: a group quest, elites, mobs above
--- the plan, and the route's danger notes
function Text.Warnings(step, pack)
  local out, kinds = {}, {}
  local function add(kind, text) out[#out + 1] = text kinds[#kinds + 1] = kind end
  if step.grp then
    local party = IsInGroup and IsInGroup()
    add('group', (party and L.groupParty or L.group):format(step.grp))
  end
  if step.o == 'accept' then
    for _, q in ipairs(ns.Evaluator.quests(step)) do
      local info = pack and pack.quests and pack.quests[q]
      if info and info.ne and not (ns.st and ns.st.log[q]) then add('event', L.eventQuest) break end
    end
  end
  -- a full quest log: taking the quest fails, and automation can't say why (the RestedXP audit, Oct 18)
  local st = ns.st
  if step.o == 'accept' and st and st.logMax and st.logMax > 0 and (st.logCount or 0) >= st.logMax then
    local mine = false
    for _, q in ipairs(ns.Evaluator.quests(step)) do if st.log[q] or st.completed[q] then mine = true end end
    if not mine then add('log', L.logFull:format(st.logCount, st.logMax)) end
  end
  if step.el then
    local names = {}
    for _, id in ipairs(step.el) do names[#names + 1] = Text.Npc(id, pack) end
    add('elite', L.elite:format(table.concat(names, ', ')))
  end
  -- (against your level, not the plan's: three or more above you)
  local mine = st and st.level or (UnitLevel and ns.clean(UnitLevel('player'))) or 1
  if step.mx and step.mx >= mine + 3 then add('level', L.mobLevel:format(step.mx)) end
  for _, ni in ipairs(step.nt or {}) do
    local note = pack.notes and pack.notes[ni]
    if note and note.d then add('danger', note.t) end
  end
  return out, kinds
end

-- --------------------------------------------------------------------------------------------------------- stops
--- seconds until your Hearthstone is ready, or nil when it is (or the game won't say)
function Text.HearthLeft()
  local get = C_Container and C_Container.GetItemCooldown
  if not get then return nil end
  local ok, start, dur = pcall(get, 6948)
  start, dur = ns.clean(start), ns.clean(dur)
  if not (ok and type(start) == 'number' and type(dur) == 'number' and start > 0 and dur > 2) then return nil end
  local left = start + dur - GetTime()
  return left > 0 and left or nil
end

--- the name in an objective line, using the game's own (localized) patterns. Forever writes them the retail way,
--- with numbered placeholders ("%2$d/%3$d %1$s slain": "4/8 Juvenile Vuldren slain"); Classic Era the old way
--- ("Juvenile Vuldren slain: 4/8"). Either gives "Juvenile Vuldren"
local function pattern(fmt)
  if type(fmt) ~= 'string' then return nil end
  fmt = fmt:gsub('%%%d+%$', '%%')   -- "%2$d" reads as "%d": the name is the only capture, so the order doesn't matter
  fmt = fmt:gsub('\194\160', ' ')   -- (French puts a no-break space before its colon; plain() makes it a space too)
  local pat = fmt:gsub('([%(%)%.%+%-%*%?%[%]%^%$])', '%%%1')   -- escape the magic characters (not the %s and %d)
  pat = pat:gsub('%%s', '(.+)'):gsub('%%d', '%%d+')
  return '^' .. pat .. '$'
end
-- the game's own first, then the Classic ones (a client that still writes them, or no strings at all)
local NAMES = {}
for _, fmt in ipairs({ QUEST_MONSTERS_KILLED or false, QUEST_OBJECTS_FOUND or false, '%s slain: %d/%d', '%s: %d/%d' }) do
  local ok, pat = pcall(pattern, fmt)
  if ok and pat and pcall(string.match, '', pat) then NAMES[#NAMES + 1] = pat end
end
-- a creature objective is a kill when it reads like one: the game's own "slain" line ("4/8 Mindless Zombie slain"), a
-- name ending in a word for it ("Risen dead destroyed"), or a creature's name and nothing else ("0/10 Rot Hide
-- Gnoll"). Forever also counts talking, looking and going somewhere as creature objectives, said in their own words:
-- "Speak with the Innkeeper" (Oct 10), "Learn about the cultists' plans" and "Check in on the Western Watchtower"
-- (Oct 11: the cards said "Kill Learn about...")
local TALK = { '^speak%s', '^talk%s', '^ask%s', '^listen%s', '^report%s' }
-- a text that starts with what to do is said as it is: "Find Fillion Flamebreeze" read as a creature's name (all
-- capitals) and the card said "Kill Find Fillion Flamebreeze" (Oct 11). A kill verb too ("Defeat Vulgara")
local VERBS = {}
for w in ([[find locate speak talk ask listen report check learn investigate search meet visit help escort protect defend
  guard rescue free discover explore inspect examine observe witness watch view follow track use place light read bring
  deliver return save heal cleanse calm comfort greet warn inform tell confront question interrogate convince recruit
  summon awaken wake revive release feed ride board enter reach survey scout mark plant gather collect obtain retrieve
  recover burn destroy defeat kill slay slaughter capture tame open loot fill purify activate assemble build repair
  test sample catch fish chase lure distract stop prevent hunt carry sit gain raise receive attend accompany approach
  consult contact cross climb descend dive swim travel take give hand offer pray extinguish ring sound play dance
  salute bow kneel cheer wave hug pet water harvest mine skin cook craft brew forge enchant bandage cure treat
  resurrect bless consecrate anoint banish seal unseal close unlock break smash poison sabotage steal plunder patrol
  survive hold endure win complete finish practice train study research decipher translate attune empower charge
  disrupt destabilize stabilize siphon drain collect drink eat taste smell listen dig excavate uncover reveal expose
  rally gather muster assist aid support]]):gmatch('%a+') do VERBS[w] = true end
-- ... and their past forms, as Forever writes progress ("Followed Kobold Tracks", "Rescued Prisoners"); the
-- irregular ones by name
local IRREGULAR = { found = true, met = true, lit = true, read = true, brought = true, caught = true, led = true,
                    fought = true, held = true, won = true, taken = true, given = true, ridden = true, spoken = true,
                    told = true, seen = true, freed = true, fed = true, built = true, dug = true, drunk = true, eaten = true }
local function verb(w)
  if VERBS[w] or IRREGULAR[w] then return true end
  if w:sub(-2) == 'ed' then
    return VERBS[w:sub(1, -3)] or VERBS[w:sub(1, -2)] or (w:sub(-3) == 'ied' and VERBS[w:sub(1, -4) .. 'y']) or false
  end
  return false
end
local SLAIN = {}
for _, fmt in ipairs({ QUEST_MONSTERS_KILLED or false, '%s slain: %d/%d' }) do
  local ok, pat = pcall(pattern, fmt)
  if ok and pat and pcall(string.match, '', pat) then SLAIN[#SLAIN + 1] = pat end
end
-- ending in what you did to them that isn't killing: said in its own words, never "Kill" (Oct 18, the owner's
-- daughter on Lazy Peons: "Kill Vile Familiar and Peons Awoken" made the peons look like enemies)
local SPARED = { 'awoken', 'awakened', 'woken', 'freed', 'rescued', 'saved', 'calmed', 'healed', 'cured', 'released',
                 'found', 'tamed', 'fed', 'revived', 'comforted', 'located', 'escorted', 'protected', 'blessed',
                 'interrogated', 'questioned', 'warned', 'informed', 'recruited', 'subdued', 'captured', 'tagged',
                 'marked', 'examined', 'inspected', 'treated', 'bandaged', 'returned', 'helped', 'consoled' }
local KILLED = { 'defeated', 'killed', 'slain', 'destroyed', 'exterminated', 'eliminated', 'vanquished', 'culled',
                 'felled', 'purged', 'dispatched', 'annihilated', 'banished', 'cleansed' }
-- small words a creature's name may have in lower case ("Vulgara the Insatiable", "Bride of Hogger")
local SMALL = { ['the'] = true, ['of'] = true, ['de'] = true, ['la'] = true, ['le'] = true, ['von'] = true,
                ['van'] = true, ['and'] = true }

local LOCALE = (GetLocale and GetLocale()) or 'enUS'
local ENGLISH = LOCALE:match('^en') ~= nil
-- Forever's kill lines on the other clients, from the owner's cache pulls (Oct 16): German "X getötet: 0/8", French
-- "X : 0/8 |4personnage tué:personnages tués;", Korean "0/8 X 처치", Spanish and Portuguese "0/8 X" with no word
-- at all. The words a kill line carries there (none for Spanish and Portuguese: their kills are known by name)
local KILL_WORDS = { deDE = { 'getötet' }, frFR = { 'tué' }, koKR = { '처치' } }
local localKill = KILL_WORDS[LOCALE] or {}

--- an objective line as plain words: the game's grammar codes ("|4one:many;") and no-break spaces gone
local function plain(text)
  return ((text or ''):gsub('|4[^;]*;', ''):gsub('\194\160', ' '))
end
Text.Plain = plain

--- a creature the guide knows by this name, in the client's language (the packs' names follow the client)
local known, knownRev
function Text.KnownCreature(name)
  if not name or name == '' then return false end
  local rev = ns.Packs and ns.Packs.namesRev or 0
  if rev ~= knownRev then
    known, knownRev = {}, rev
    for _, p in pairs(ns.Packs and ns.Packs.byId or {}) do
      for _, n in pairs(p.npcs or {}) do if type(n) == 'string' then known[n:lower()] = true end end
    end
  end
  return known[name:lower()] or false
end

function Text.IsKill(o)
  if o.type ~= 'monster' then return false end
  local raw = o.text or ''
  local text = plain(raw)
  local words = text:gsub('%s*:?%s*%d+%s*/%s*%d+%s*$', ''):gsub('^%s*%d+%s*/%s*%d+%s*', '')
  local low = words:lower()
  -- ending in a word for it is a kill whatever it starts with ("Enchanted Skyhopper Exterminated": not "enchant")
  for _, pat in ipairs(SLAIN) do if text:match(pat) then return true end end
  if not ENGLISH then
    -- (the word lists below are English. Another client: its own kill word, else a creature the guide knows by
    -- that name; "Hable con el posadero" is neither)
    local rawLow = raw:lower()
    for _, w in ipairs(localKill) do if rawLow:find(w, 1, true) then return true end end
    return Text.KnownCreature(Text.ObjectiveName(o))
  end
  for _, w in ipairs(KILLED) do
    if #low > #w + 1 and low:sub(-(#w + 1)) == ' ' .. w then return true end
  end
  for _, pat in ipairs(TALK) do if low:match(pat) then return false end end
  for _, w in ipairs(SPARED) do
    if #low > #w + 1 and low:sub(-(#w + 1)) == ' ' .. w then return false end
  end
  if verb(low:match('^(%a+)') or '') then return false end
  for word in words:gmatch('%S+') do
    if not (word:match('^%u') or SMALL[word]) then return false end
  end
  return words ~= ''
end

-- a creature objective written in other words than "slain": "0/6 Windshaper Novice Seer Defeated" (A Magical Affront,
-- Oct 10: the card said "Kill Windshaper Novice Seer Defeated"). The name is what comes before the word

--- a quest whose creature objectives are all places to be (credit markers: Eyes of the Sentinels' owls at the
--- Darnassus Bank), so none of them is a kill (Oct 14, the owner: "Kill Darnassus Bank")
function Text.SpotsOnly(q, pack)
  local info = pack and pack.quests and q and pack.quests[q]
  local spot = false
  for _, h in ipairs(info and info.how or {}) do
    if h[1] == 'kill' then return false end
    if h[1] == 'spot' then spot = true end
  end
  return spot
end

function Text.ObjectiveName(o)
  local text = plain(o.text)
  local name
  for _, pat in ipairs(NAMES) do
    name = text:match(pat)
    if name then break end
  end
  name = name or (text:gsub('%s*:?%s*%d+%s*/%s*%d+%s*$', ''):gsub('^%s*%d+%s*/%s*%d+%s*', ''))
  name = name:gsub('^%s+', ''):gsub('%s+$', '')
  if o.type == 'monster' then
    local low = name:lower()
    for _, w in ipairs(ENGLISH and KILLED or localKill) do
      if #name > #w + 1 and low:sub(-(#w + 1)) == ' ' .. w then return (name:sub(1, #name - #w - 1)) end
    end
  end
  return name
end

local function joinNames(names)
  if #names <= 1 then return names[1] or '' end
  return table.concat(names, ', ', 1, #names - 1) .. ' ' .. L['and'] .. ' ' .. names[#names]
end

--- a stop's instruction line: "Talk to Rorian the Dayseeker", "Kill Juvenile Vuldren and Pesky Cirrusfly",
--- "Collect Scavenger Paw", or the single step's own line
--- a talk stop whose pending steps are all hand-ins of quests in your log that aren't done yet: the first of them
function Text.NotReady(stop, route)
  local view = ns.Engine and ns.Engine.View and ns.Engine.View()
  local first
  for _, i in ipairs(stop.steps) do
    if not view or not view.status or view.status[i] == 'pending' then
      local s = route.steps[i]
      if s.o ~= 'turnin' then return nil end
      local q = (type(s.id) == 'table' and s.id[1]) or s.id
      local e = ns.st.log[q]
      if not (e and not e.ready) then return nil end
      first = first or q
    end
  end
  return first
end

--- leadOnly: just what's done where the arrow leads (the arrow's own words)
function Text.StopTitle(stop, route, leadOnly)
  local pack = route.pack
  local lead = route.steps[stop.lead]
  if lead and lead.cash and (ns.st.cash or 0) < lead.cash then return (Text.Card(lead, pack).main) end
  if lead and lead.sy and not Text.WayDone(lead) then return lead.sy end   -- the route's own words for it
  if stop.kind == 'talk' then
    paint = true
    local who = P(Text.Npc(stop.who, pack))
    paint = false
    local train = true   -- a stop that's only training says so
    for _, i in ipairs(stop.steps) do if route.steps[i].o ~= 'train' then train = false end end
    -- every hand-in here still has objectives left: that comes first
    local left = Text.NotReady(stop, route)
    if left then return L.finishThenTalk:format(P(Text.Quest(left, pack)), who) end
    return (train and L.trainAt or L.talkTo):format(who)
  end
  if stop.kind == 'area' then
    -- what the arrow leads to comes first, then the rest of the card (Nov 11, the owner in Redridge: the arrow led to
    -- the spiders under "Kill Redridge Mongrel and Redridge Poacher...")
    local parts, seen = {}, {}
    local kill, get, other
    local function add(list, name, color)
      if name and name ~= '' and not seen[name] then seen[name] = true list[#list + 1] = color .. name .. '|r' end
    end
    for pass = 1, (stop.with and not leadOnly) and 2 or 1 do
    kill, get, other = {}, {}, {}
    for _, i in ipairs(stop.steps) do
      local s = route.steps[i]
      if stop.with and ((stop.with[i] or false) ~= (pass == 1)) then   -- (not this pass's)
      elseif s.o == 'kill' then
        for _, id in ipairs(list(s.id)) do add(kill, Text.Npc(id, pack), '|cffff4646') end
      elseif s.o == 'collect' then
        add(get, Text.Item(s.id, pack), '|cffffffff')
      else
        for _, q in ipairs(s.o == 'complete' and list(s.id) or { s.q }) do
          local e = q and ns.st.log[q]
          for k, o in ipairs(e and e.obj or {}) do
            if not s.ob or s.ob == k then
              if Text.IsKill(o) and not Text.SpotsOnly(q, pack) then add(kill, Text.ObjectiveName(o), '|cffff4646')
              elseif o.type == 'item' then add(get, Text.ObjectiveName(o), '|cffffffff')
              elseif o.type == 'monster' then
                -- in its own words; with the item the quest gives for it ("use Foreman's Blackjack for Peons Awoken")
                local info = pack.quests and pack.quests[q]
                local name = Text.ObjectiveName(o)
                if info and info.si then name = L.useFor:format(Text.Item(info.si, pack), name) end
                add(other, name, '|cffffffff')
              end
            end
          end
        end
      end
    end
    if #kill > 0 then parts[#parts + 1] = (#parts > 0 and L.killAlso or L.kill):format(joinNames(kill)) end
    if #get > 0 then parts[#parts + 1] = (#parts > 0 and L.collectAlso or L.collect):format(joinNames(get)) end
    for _, words in ipairs(other) do parts[#parts + 1] = words end
    end
    if #parts > 0 then return table.concat(parts, ', ') end
  end
  return (Text.Step(lead, pack, true))
end

--- what a person stop holds, as the game's own marks: a ? for each quest to hand in, a ! for each one to take, and the
--- trainer's, vendor's or inn's mark (every player reads these; words cut off at large text sizes). The row's
--- tooltip says each one in words.
local SUMMARY = { 'turnin', 'accept', 'train', 'vendor', 'sethome' }
local MARKS = 6
function Text.StopSummary(stop, route)
  local n = {}
  for _, i in ipairs(stop.steps) do
    local o = route.steps[i].o
    n[o] = (n[o] or 0) + ((o == 'turnin' or o == 'accept') and #list(route.steps[i].id or { 0 }) or 1)
  end
  local marks, shown = {}, 0
  for _, o in ipairs(SUMMARY) do
    for _ = 1, math.min(n[o] or 0, (o == 'turnin' or o == 'accept') and MARKS or 1) do
      if shown < MARKS then
        shown = shown + 1
        marks[#marks + 1] = ('|T%s:13:13:0:0|t'):format(ns.Skin.GAME[o] or ns.Skin.GAME.talk)
      end
    end
  end
  return table.concat(marks, '')
end

-- ------------------------------------------------------------------------------------------- what a quest asks
--- the game's text tokens: $n name, $c class, $r race, $b new line, $g male:female; and $1oa, an objective's count
--- (Forever's new quests), from the quest log once you have the quest, else left out ("Slay Roiling Winds")
function Text.Tokens(s, q)
  if type(s) ~= 'string' then return s end
  local e = q and ns.st.log[q]
  s = s:gsub('%$(%d)oa%s?', function(n)
    local o = e and e.obj and e.obj[tonumber(n)]
    return o and o.need and (o.need .. ' ') or ''
  end)
  local name = ns.clean(UnitName and UnitName('player')) or ''
  local class = ns.clean(UnitClass and (UnitClass('player'))) or ''
  local race = ns.clean(UnitRace and (UnitRace('player'))) or ''
  local female = (ns.clean(UnitSex and UnitSex('player')) or 2) == 3
  s = s:gsub('%$[gG]%s*([^:;]*):([^;]*);', function(m, f) return female and f or m end)
  s = s:gsub('%$[bB]', '\n'):gsub('%$[nN]', name):gsub('%$[cC]', class):gsub('%$[rR]', race)
  return s
end

--- what a quest asks, in its own words ("Slay 8 Vuldren Juveniles in Thendal Grove."). The pack's text is English,
--- so other languages leave it out (their objective lines come from the quest log once the quest is taken).
function Text.Says(q, pack)
  local info = pack and pack.quests and pack.quests[q]
  if not (info and info.ot) then return nil end
  local loc = GetLocale and GetLocale() or 'enUS'
  if loc ~= 'enUS' and loc ~= 'enGB' then return nil end
  return Text.Tokens(info.ot, q)
end

--- a quest's story: from the quest log in the client's language once you have the quest, else the pack's copy of
--- Forever's text (our client cache). Forever's quest log is retail's: GetQuestLogQuestText takes the quest's place in
--- the log, and there's no SelectQuestLogEntry (Oct 9: calling the Classic pair left every story "not taken yet").
local stories = {}
function Text.Story(q, pack)
  if stories[q] then return stories[q] end
  local e = ns.st.log[q]
  if e and e.index and GetQuestLogQuestText then
    local ok, desc = pcall(GetQuestLogQuestText, e.index)
    desc = ok and ns.clean(desc)
    if type(desc) == 'string' and desc ~= '' then stories[q] = desc return desc end
    -- not sent yet: ask for it; QUEST_DATA_LOAD_RESULT redraws the window when it comes
    if C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, q) end
  end
  local info = pack and pack.quests and pack.quests[q]
  return info and info.st and Text.Tokens(info.st) or nil
end

local RANK = { [1] = 'rankElite', [2] = 'rankRareElite', [3] = 'rankBoss', [4] = 'rankRare' }
--- a creature's level for the window, colored against yours: "LvL. (3)", "LvL. (3-4)", "LvL. (9 Elite)"
function Text.MobLevel(id, pack)
  local lv = pack and pack.npcl and pack.npcl[id]
  if not lv then return nil end
  local lo, hi, rank = lv[1], lv[2], lv[3] or 0
  local text = lo ~= hi and ('%d-%d'):format(lo, hi) or tostring(hi)
  if RANK[rank] then text = text .. ' ' .. L[RANK[rank]] end
  local c = GetQuestDifficultyColor and GetQuestDifficultyColor(hi)
  if not (c and c.r) then
    local d = hi - (ns.st.level or 1)
    c = d >= 5 and { r = 1, g = 0.1, b = 0.1 } or d >= 3 and { r = 1, g = 0.5, b = 0.25 }
      or d >= -2 and { r = 1, g = 1, b = 0 } or { r = 0.25, g = 0.75, b = 0.25 }
  end
  return ('|cff%02x%02x%02x%s|r'):format(c.r * 255, c.g * 255, c.b * 255, L.levelTag:format(text))
end

local function mob(id, pack)
  local lv = Text.MobLevel(id, pack)
  return '|cffff4646' .. Text.Npc(id, pack) .. '|r' .. (lv and (' ' .. lv) or '')
end

local function objName(id, pack)
  return (pack and pack.objs and pack.objs[id]) or L.object:format(id)
end

local function orList(names)
  if #names <= 1 then return names[1] or '' end
  return table.concat(names, ', ', 1, #names - 1) .. ' ' .. L['or'] .. ' ' .. names[#names]
end

--- what to do for each of a quest's objectives: { text, name (what the quest log calls it), kind, elite }
---   "Kill Juvenile Vuldren (1-2)", "Loot Duskbat Wing from Duskbat (2) or Feral Duskbat (3)", "Click the Supply Crate"
function Text.How(q, pack)
  local info = pack and pack.quests and pack.quests[q]
  local out = {}
  for _, h in ipairs(info and info.how or {}) do
    local kind, id, from = h[1], h[2], h[3]
    local x = { kind = kind, id = id }
    if kind == 'kill' then
      x.name = Text.Npc(id, pack)
      x.text = L.howKill:format(mob(id, pack))
      local lv = pack.npcl and pack.npcl[id]
      x.elite = lv and lv[3] and lv[3] > 0 and lv[3] ~= 4
    elseif kind == 'talk' then   -- someone of your own side to find or speak with (Fillion Flamebreeze)
      x.name = Text.Npc(id, pack)
      x.text = L.howTalk:format('|cffffffff' .. x.name .. '|r')
    elseif kind == 'click' then
      x.name = objName(id, pack)
      x.text = L.howClick:format('|cffffffff' .. x.name .. '|r')
    elseif kind == 'spot' then
      -- a place to be (a credit marker): the objective's own words say where; nothing to kill or loot
    else
      x.name = Text.Item(id, pack)
      local srcs = {}
      for k, sid in ipairs(from or {}) do
        if k > 2 then break end
        srcs[#srcs + 1] = kind == 'open' and ('|cffffffff' .. objName(sid, pack) .. '|r')
          or kind == 'buy' and ('|cffffffff' .. Text.Npc(sid, pack) .. '|r') or mob(sid, pack)
      end
      paint = true
      local item = I(x.name, id)   -- in its quality color
      paint = false
      if #srcs == 0 then x.text = L.howGet:format(item)
      else
        x.from = (kind == 'buy' and L.howSoldBy or L.howFrom):format(orList(srcs))
        x.text = (kind == 'buy' and L.howBuy or L.howLoot):format(item, orList(srcs))
      end
      for _, sid in ipairs(from or {}) do
        local lv = pack.npcl and pack.npcl[sid]
        if kind == 'loot' and lv and lv[3] and lv[3] > 0 and lv[3] ~= 4 then x.elite = true end
      end
    end
    out[#out + 1] = x
  end
  return out
end

--- the how-to line that goes with a live objective: matched by the name the quest log uses, else, when the quest
--- has just one objective of that kind, by kind (the log may name a creature differently from its npc name)
local KINDS = { monster = { kill = true }, item = { loot = true, open = true, buy = true }, object = { click = true } }
function Text.HowFor(how, o, all)
  local name = Text.ObjectiveName(o)
  name = name and name:lower()
  for _, x in ipairs(how) do
    if x.name and name and (x.name:lower() == name or name:find(x.name:lower(), 1, true)) then return x end
  end
  local fits = KINDS[o.type or '']
  if not fits or (o.type == 'monster' and not Text.IsKill(o)) then return nil end   -- (talking to them isn't a kill)
  local same, match = 0, nil
  for _, other in ipairs(all or { o }) do if other.type == o.type then same = same + 1 end end
  for _, x in ipairs(how) do
    if fits[x.kind] then
      if match then return nil end
      match = x
    end
  end
  return same == 1 and match or nil
end

--- a training step's spells for you: { icon, name, rank, level, known, later }
function Text.TrainList(step)
  local out = {}
  local who = { race = ns.st.race, level = ns.st.level }
  for _, sp in ipairs(ns.Evaluator.TrainSpells(step, who)) do
    local lv, id, rank = sp[1], sp[2], sp[3]
    local known = ns.st.known and ns.st.known[id] or false
    -- a spell an earlier visit listed and you've learned since isn't listed again
    if not (known and lv < (step.lmin or 0)) then
      local icon = C_Spell and C_Spell.GetSpellTexture and ns.clean(C_Spell.GetSpellTexture(id))
      out[#out + 1] = { icon = icon, name = Text.Spell(id), rank = rank, level = lv,
                        known = known, later = lv > (ns.st.level or 1) }
    end
  end
  return out
end

--- "Fireball (Rank 2)" with the spell's icon, for the window
function Text.TrainLine(x)
  local line = x.name
  if x.rank and x.rank > 0 then line = line .. ' ' .. L.rankN:format(x.rank) end
  if x.later then line = line .. ' ' .. L.atLevel:format(x.level) end
  return x.icon and ('|T' .. tostring(x.icon) .. ':14:14:0:0:64:64:5:59:5:59|t ' .. line) or line
end

-- the game's kill XP (Classic's formula): a level-L mob gives L*5+45 at your level, 5% more per level above you,
-- less per level below over the zero-difference band, nothing once grey; elites double. Rested XP doubles kills
-- until the pool runs out. Forever may tune this: it's an estimate, said as "about".
local function zeroDiff(lv)
  if lv < 8 then return 5 elseif lv < 10 then return 6 elseif lv < 12 then return 7 elseif lv < 16 then return 8
  elseif lv < 20 then return 9 elseif lv < 30 then return 11 elseif lv < 40 then return 12 elseif lv < 45 then return 13
  elseif lv < 50 then return 14 elseif lv < 55 then return 15 elseif lv < 60 then return 16 end
  return 17
end
local function greyBelow(lv)
  if lv <= 5 then return 0 elseif lv <= 39 then return lv - 5 - math.floor(lv / 10) end
  return lv - 1 - math.floor(lv / 5)
end
function Text.KillXP(mobLevel, level, elite)
  if mobLevel <= greyBelow(level) then return 0 end
  local base = mobLevel * 5 + 45
  local xp
  if mobLevel >= level then xp = base * (1 + 0.05 * math.min(mobLevel - level, 4))
  else xp = base * (1 - (level - mobLevel) / zeroDiff(level)) end
  return math.max(0, math.floor(xp * (elite and 2 or 1)))
end

--- XP still to go before level n (the pack's client XP curve covers the levels between)
function Text.XPTo(n, pack)
  local st = ns.st
  local level = st.level or 1
  if n <= level then return 0 end
  local need = (st.xpMax or 0) - (st.xp or 0)
  for lv = level + 1, n - 1 do
    local step = pack and pack.xpc and pack.xpc[lv]
    if not step then return nil end
    need = need + step
  end
  return need
end

--- "about 9 more Juvenile Vuldren (1-2) to level 3": kills of the mob the route last sent you after
function Text.Grind(step, route, index)
  local pack = route.pack
  local need = Text.XPTo(step.lv or 0, pack)
  if not need or need <= 0 then return nil end
  local npc
  for _, id in ipairs(step.tg or {}) do   -- the creatures the grind names, first
    if pack.npcl and pack.npcl[id] then npc = id break end
  end
  for i = (index or 1) - 1, math.max(1, (index or 1) - 15), -1 do
    if npc then break end
    local s = route.steps[i]
    if s.o == 'kill' and s.id then npc = type(s.id) == 'table' and s.id[1] or s.id
    elseif s.o == 'complete' then
      local info = pack.quests and pack.quests[type(s.id) == 'table' and s.id[1] or s.id]
      for _, h in ipairs(info and info.how or {}) do if h[1] == 'kill' then npc = h[2] break end end
    end
    if npc and pack.npcl and pack.npcl[npc] then break end
    npc = nil
  end
  if not npc then return L.xpLeft:format(BreakUpLargeNumbers and BreakUpLargeNumbers(need) or need) end
  local lv = pack.npcl[npc]
  local per = Text.KillXP(math.floor((lv[1] + lv[2]) / 2 + 0.5), ns.st.level or 1, lv[3] == 1 or lv[3] == 2)
  if per <= 0 then return L.xpLeft:format(BreakUpLargeNumbers and BreakUpLargeNumbers(need) or need) end
  local rested = ns.clean(GetXPExhaustion and GetXPExhaustion()) or 0
  local kills = need <= 2 * rested and math.ceil(need / (2 * per)) or math.ceil((need - rested) / per)
  return ns.count('grind', kills, mob(npc, pack))
end

--- where a step's location came from, for the tooltip
function Text.Evidence(step, pack)
  local build = pack.stamp and pack.stamp.build or '?'
  if not step.ev then return nil end
  if step.ev >= 3 then return L.evClassic end
  if step.src == 'capture' then return L.evSeen:format(build) end
  if step.src == 'author' then return L.evAuthor end
  return L.evClient:format(build)
end

ns.On('QUEST_DATA_LOAD_RESULT', function() ns.MarkDirty('text') end)
ns.On('GET_ITEM_INFO_RECEIVED', function() ns.MarkDirty('text') end)
