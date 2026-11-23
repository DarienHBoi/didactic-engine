-- /bofg               show or hide the window
-- /bofg list          routes installed for this character; /bofg route <id> switches
-- /bofg dungeons      dungeon guides for this character; /bofg dungeon [name|off] shows one (the next stop's with no
--                     name) or closes it. Inside a dungeon its guide shows by itself.
-- /bofg prof [name|off]  profession guides: lists them, shows one, or closes it
-- /bofg shopping [all]  what the shown profession guide still needs, up to its next rank (all: to the end)
-- /bofg import        paste window for an import string (the paid packs); /bofg import forget <pack> drops a kept one
-- /bofg packs         the packs loaded, where from and their version
-- /bofg skip | unskip skip the current step, or bring back the last one you skipped
-- /bofg back | forward | resume   look back at earlier steps one at a time (nothing is undone), step forward again,
--                     or jump back to where you are
-- /bofg waypoint blizzard|off
-- /bofg hc auto|on|off
-- /bofg auto [accept|turnin|gossip|taxi|all] [on|off]   automation for the route's own quests (all on by default)
-- /bofg arrow [on|off|reset|<size %>]  the waypoint arrow: show, hide, back to the top, or its size (e.g. 130)
-- /bofg collapse     only the current step (again: the whole plan)
-- /bofg size <percent>  the window's size (30 to 160); /bofg look opens the size and look panel
-- /bofg options      the settings page
-- /bofg items on|off  the Quest Items panel; /bofg targets on|off the Targets panel
-- /bofg mark test [role|done|off]  try the Waymark on your target, with no route, on retail too (UI/Marks.lua)
-- /bofg mark [on|off]  the Waymark, off for now (UI/Marks.lua); /bofg mark size <percent>, /bofg mark lift <pixels>;
--                     /bofg mark plates on|small|off  the game's friendly NPC nameplates, changed only when typed here
-- /bofg selftest      checks every game function the guide relies on, on this client (results saved for us)
-- /bofg report        a line to copy into a bug report: route, step, build, level, spot
-- /bofg feedback      Send feedback: a kind, your words, then a link to our feedback page with where you are
-- /bofg feedback last the last feedback link again
-- /bofg reset         forget this character's skips and marks
local _, ns = ...

local L = ns.L

-- -------------------------------------------------------------------------------------------------------- selftest
local function probe(results, name, fn)
  local ok, res, detail = pcall(fn)
  if not ok then results[#results + 1] = { name = name, ok = false, detail = tostring(res) } return end
  results[#results + 1] = { name = name, ok = res and true or false, detail = detail and tostring(detail) or nil }
end

function ns.SelfTest()
  local r = {}
  local clean = ns.clean
  probe(r, 'client', function()
    local v, b, _, iface = GetBuildInfo()
    return (iface or 0) >= 16000, ('%s.%s interface %s'):format(v, b, tostring(iface))
  end)
  probe(r, 'secret values', function() return type(issecretvalue) == 'function' end)
  probe(r, 'quest log', function()
    local n = C_QuestLog.GetNumQuestLogEntries()
    local first
    for i = 1, n do local info = C_QuestLog.GetInfo(i) if info and not info.isHeader then first = info.questID break end end
    if first then
      local objs = C_QuestLog.GetQuestObjectives(first)
      return type(objs) == 'table', ('%d entries; quest %s has %d objectives'):format(n, tostring(first), #objs)
    end
    return true, ('%d entries (take a quest and run again to test objectives)'):format(n)
  end)
  probe(r, 'completed quests', function()
    local ids = C_QuestLog.GetAllCompletedQuestIDs()
    return type(ids) == 'table', #ids .. ' completed'
  end)
  probe(r, 'quest titles', function()
    local t = clean(C_QuestLog.GetTitleForQuestID(363))
    if not t then C_QuestLog.RequestLoadQuestByID(363) end
    return true, t or 'requested; run again in a second'
  end)
  probe(r, 'position', function()
    local map = C_Map.GetBestMapForUnit('player')
    local p = map and C_Map.GetPlayerMapPosition(map, 'player')
    return p ~= nil and clean(p.x) ~= nil, ('map %s %s'):format(tostring(map), p and ('%.1f, %.1f'):format((clean(p.x) or 0) * 100, (clean(p.y) or 0) * 100) or 'none')
  end)
  probe(r, 'world position', function()
    local map = C_Map.GetBestMapForUnit('player')
    local c, pos = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(0.5, 0.5))
    return pos ~= nil, ('continent %s'):format(tostring(c))
  end)
  probe(r, 'waypoint', function()
    local map = C_Map.GetBestMapForUnit('player')
    if not C_Map.CanSetUserWaypointOnMap(map) then return false, 'not allowed on map ' .. tostring(map) end
    if C_Map.HasUserWaypoint() then return true, 'you have a waypoint set; not touched' end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, 0.5, 0.5))
    local ok = C_Map.HasUserWaypoint()
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    local tracked = C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()
    local dist = C_Navigation and C_Navigation.GetDistance and clean(C_Navigation.GetDistance())
    C_Map.ClearUserWaypoint()
    return ok, ('set %s, super-tracked %s, distance %s'):format(tostring(ok), tostring(tracked), tostring(dist))
  end)
  probe(r, 'quest super-track', function() return type(C_SuperTrack.SetSuperTrackedQuestID) == 'function' end)
  -- the Waymark (Oct 30): what it hangs from, on this client. Run it on a step with the arrow up, in a town
  probe(r, 'waymark waypoint', ns.Marks.ProbeNav)
  probe(r, 'waymark nameplates', ns.Marks.ProbePlates)
  probe(r, 'flight map', function() return C_TaxiMap and type(C_TaxiMap.GetAllTaxiNodes) == 'function' end)
  -- (the route to a flight's end, worked out before taking it, as Blizzard's map does on a hover: does the client have
  -- it, and what it says for each reachable flight with a flight master's map open; Nov 8, the RestedXP client study)
  probe(r, 'flight routes', function()
    if type(GetNumRoutes) ~= 'function' then return true, 'GetNumRoutes: not on this client' end
    local n = type(NumTaxiNodes) == 'function' and NumTaxiNodes() or 0
    if n == 0 then return true, 'GetNumRoutes is here (open a flight master to test it)' end
    local out = {}
    for i = 1, math.min(n, 12) do local ok, k = pcall(GetNumRoutes, i) out[#out + 1] = ok and tostring(ns.clean(k)) or 'x' end
    return true, 'GetNumRoutes per node: ' .. table.concat(out, ' ')
  end)
  -- Show on map (FB-035): the world map really opens at your zone, then closes again (not in a fight)
  probe(r, 'show on map', function()
    if InCombatLockdown() then return true, 'skipped in combat' end
    local here = clean(C_Map.GetBestMapForUnit('player'))
    local was = WorldMapFrame and WorldMapFrame:IsShown()
    if not ns.Waypoint.ShowOnMap(here) then return false, 'could not open' end
    local shown = WorldMapFrame and WorldMapFrame:IsShown()
    local at = WorldMapFrame and WorldMapFrame.GetMapID and clean(WorldMapFrame:GetMapID())
    if shown and not was and HideUIPanel then HideUIPanel(WorldMapFrame) end
    return shown and at == here, ('map %s, shown at %s'):format(tostring(here), tostring(at))
  end)
  probe(r, 'hearth', function() local b = clean(GetBindLocation()) return b ~= nil, b end)
  -- the talent calls talent plans read (Core/Talents.lua): the active config, its tree, points to spend, and what a
  -- node of your class's first plan says (ranks bought, max ranks); its window's button, once that window has loaded
  probe(r, 'talents', function()
    local ok, cfg = pcall(C_ClassTalents.GetActiveConfigID)
    cfg = ok and clean(cfg)
    if not cfg then return false, 'no config' end
    local ok2, info = pcall(C_Traits.GetConfigInfo, cfg)
    local tree = ok2 and type(info) == 'table' and info.treeIDs and info.treeIDs[1]
    local plan = ns.Talents and ns.Talents.Plans()[1]
    local node = plan and plan.picks[1]
    local ni = node and select(2, pcall(C_Traits.GetNodeInfo, cfg, node))
    local f = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    local btn = f and f.GetTalentButtonByNodeID and node and f:GetTalentButtonByNodeID(node)
    return true, ('config %s, tree %s, %d to spend; node %s: %s of %s; button %s'):format(tostring(cfg), tostring(tree),
      ns.Talents and ns.Talents.Unspent() or -1, tostring(node), tostring(type(ni) == 'table' and clean(ni.ranksPurchased)),
      tostring(type(ni) == 'table' and clean(ni.maxRanks)), btn and 'found' or (f and 'not found' or 'window not loaded'))
  end)
  -- what the world map's flight point list says on this map (0.9.106 read it as the flight paths you know; on Forever
  -- it marks every one discovered, so the guide doesn't use it: kept here to see if that changes)
  probe(r, 'map flights', function()
    local map = clean(C_Map.GetBestMapForUnit('player'))
    local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, map)
    if not ok or type(nodes) ~= 'table' then return false, 'no answer' end
    local known, all = 0, 0
    for _, n in ipairs(nodes) do
      all = all + 1
      if clean(n.isUndiscovered) == false then known = known + 1 end
    end
    local mine = 0
    for _ in pairs(ns.cdb and ns.cdb.taxi or {}) do mine = mine + 1 end
    return true, ('%d of %d marked discovered on map %s; the guide knows %d'):format(known, all, tostring(map), mine)
  end)
  probe(r, 'items', function()
    local n = clean(C_Item.GetItemCount(6948))
    return n ~= nil, 'Hearthstone x' .. tostring(n)
  end)
  probe(r, 'facing', function() local f = clean(GetPlayerFacing()) return f ~= nil, f end)
  -- the arrow's distance two ways: through the map transform (what it uses) and UnitPosition (to see how far apart)
  probe(r, 'arrow distance', function()
    local d = ns.Arrow and ns.Arrow.Distances and ns.Arrow.Distances()
    if not d then return true, 'no target' end
    return d.map ~= nil, ('map %s yd, UnitPosition %s yd'):format(d.map and math.floor(d.map + 0.5) or '?',
      d.unit and math.floor(d.unit + 0.5) or '?')
  end)
  probe(r, 'inflate', function()
    -- the same text, deflated raw (what our import strings use) and zlib-wrapped: our decoder must read the raw one;
    -- the game's own C_EncodingUtil.DecompressString is tried on both, to learn which it takes (a faster path later)
    local want = 'Bind on Forever Guide. Bind on Forever Guide. Bind on Forever Guide.'
    local raw = "\115\202\204\75\81\200\207\83\112\203\47\74\45\75\45\82\112\47\205\76\73\213\83\112\34\69\24\0"
    local wrapped = "\120\218" .. raw .. "\35\174\23\78"
    local ok, got = pcall(ns.Codec.InflateText, raw)
    local native = 'absent'
    if C_EncodingUtil and C_EncodingUtil.DecompressString then
      local okR, r1 = pcall(C_EncodingUtil.DecompressString, raw)
      local okW, r2 = pcall(C_EncodingUtil.DecompressString, wrapped)
      native = ('raw %s, zlib %s'):format(okR and r1 == want and 'same' or 'no', okW and r2 == want and 'same' or 'no')
    end
    local ms = {}
    for id, v in pairs(ns.db.importMs or {}) do ms[#ms + 1] = id .. ' ' .. v .. ' ms' end
    return ok and got == want, ('ours %s; native %s%s'):format(ok and got == want and 'ok' or tostring(got), native,
      #ms > 0 and ('; last imports: ' .. table.concat(ms, ', ')) or '')
  end)
  probe(r, 'battletag for imports', function()
    local _, tag = BNGetInfo()
    if issecretvalue and issecretvalue(tag) then return false, 'secret: imports cannot be unlocked' end
    return tag ~= nil, tag and 'readable' or 'none'
  end)
  probe(r, 'skill caps', function()
    -- every profession this character has, on Forever's child line and on the classic one: which one moves is what
    -- the profession guides need to know
    local parts = {}
    for id, name in pairs(ns.State.PROFESSIONS) do
      local child = ns.State.CHILD[id]
      local cr, cc = ns.State.SkillLine(child)
      local pr, pc = ns.State.SkillLine(id)
      if cr or pr then
        parts[#parts + 1] = ('%s %d: %s/%s, %d: %s/%s'):format(name, child, tostring(cr), tostring(cc), id, tostring(pr),
          tostring(pc))
      end
    end
    if #parts == 0 then return true, 'no professions on this character' end
    table.sort(parts)
    return true, table.concat(parts, '; ')
  end)
  probe(r, 'recipe known', function()
    -- Linen Bandage and Charred Wolf Meat: the first recipes of First Aid and Cooking
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local a, b = clean(C_SpellBook.IsSpellKnown(3275, bank)), clean(C_SpellBook.IsSpellKnown(2538, bank))
    return a ~= nil, ('Linen Bandage %s, Charred Wolf Meat %s'):format(tostring(a), tostring(b))
  end)
  probe(r, 'restrictions', function()
    return C_RestrictedActions and type(C_RestrictedActions.IsAddOnRestrictionActive) == 'function'
  end)
  probe(r, 'hardcore flag', function()
    return C_GameRules and type(C_GameRules.IsHardcoreActive) == 'function', tostring(C_GameRules.IsHardcoreActive())
  end)
  probe(r, 'instance', function()
    local name, itype, _, _, _, _, _, id = GetInstanceInfo()
    return itype ~= nil, ('%s, %s, map %s'):format(tostring(clean(name)), tostring(clean(itype)), tostring(clean(id)))
  end)
  probe(r, 'party levels', function()
    -- the level a party goes by (Engine.PartyPace, 0.9.136): does the game tell each member's level, near and far?
    if not (IsInGroup and IsInGroup()) then return true, 'not in a party (join one and run again)' end
    local parts, all = {}, true
    for i = 1, 4 do
      local u = 'party' .. i
      if clean(UnitExists(u)) then
        local l = clean(UnitLevel(u))
        if type(l) ~= 'number' or l <= 0 then all = false end
        parts[#parts + 1] = ('%s level %s%s'):format(u, tostring(l), clean(UnitIsVisible and UnitIsVisible(u)) and '' or ' (far)')
      end
    end
    return all, ('%s; the party goes by %s'):format(table.concat(parts, ', '), tostring(ns.Engine.PartyPace()))
  end)
  probe(r, 'route pack', function()
    local n = 0
    for _ in pairs(ns.Packs.routes) do n = n + 1 end
    return n > 0, n .. ' routes'
  end)
  local v, b = GetBuildInfo()
  ns.db.selftest = { at = time(), build = v .. '.' .. tostring(b), addon = ns.VERSION, results = r }
  local failed = {}
  for _, x in ipairs(r) do if not x.ok then failed[#failed + 1] = x.name end end
  ns.say(('selftest: %d of %d ok%s. Saved for the next /reload.'):format(#r - #failed, #r,
    #failed > 0 and (', failed: ' .. table.concat(failed, ', ')) or ''))
  return r
end

-- ---------------------------------------------------------------------------------------------------------- report
function ns.Report()
  local route, view = ns.Engine.Route(), ns.Engine.View()
  local st = ns.st
  local s = route and view and view.cursor and route.steps[view.cursor]
  local v, b = GetBuildInfo()
  local pos = st.pos or {}
  local line = ('BoFG %s | %s.%s | %s | %s %s %s | lvl %s | map %s %.1f,%.1f | log %d | pack %s'):format(
    ns.VERSION, v, tostring(b), route and route.id or '-', s and s.k or '-', s and s.o or '-',
    s and tostring(s.id or '') or '', ns.fmtLevel(st.level + (st.xp or 0) / (st.xpMax or 1)),
    tostring(pos.map), pos.x or 0, pos.y or 0, st.logCount or 0, route and tostring(route.pack.ver) or '-')
  local blocked = ns.LastBlocked(true)
  if blocked then line = line .. ' | ' .. blocked end
  local auto = ns.Auto and ns.Auto.LastLine()   -- (the last quest window automation saw: FB-037, FB-038)
  if auto then line = line .. ' | auto ' .. auto end
  local held = ns.AutoHeld and ns.AutoHeld()
  if held then line = line .. ' | auto ' .. held end
  ns.db.lastReport = line
  ns.say(line)
  return line
end

-- ----------------------------------------------------------------------------------------------------------- slash
--- a route's name with its levels, as the seal's menu writes it ("Westfall (levels 14 to 18)")
local function levelsOf(r)
  local t = r.title or r.id
  if not r.lv then return t end
  local lo, hi = math.floor(r.lv[1]), math.floor(r.lv[2] + 0.5)
  if lo == hi then return L.menuGuideLevel:format(t, lo) end
  return L.menuGuideLevels:format(t, lo, hi)
end

SLASH_BOFGUIDE1 = '/bofg'
SlashCmdList.BOFGUIDE = function(msg)
  msg = (msg or ''):match('^%s*(.-)%s*$')
  local cmd, arg = msg:match('^(%S*)%s*(.-)$')
  cmd = (cmd or ''):lower()
  if not ns.db then return ns.say(L.notLoaded) end
  if cmd == '' then return ns.Window.Toggle() end
  if cmd == 'selftest' then return ns.SelfTest() end
  if cmd == 'place' or cmd == 'places' then
    -- (places by where you stand, said out loud: what a profession guide weighed, how far each is, which it shows)
    local rows, best, held = ns.Engine.Places()
    local r = ns.Engine.Route()
    if not rows then return ns.say(L.placeNeed) end
    if #rows == 0 then return ns.say(best == nil and held == nil and L.placeNone or L.placeNoSpot) end
    local known
    for _, row in ipairs(rows) do known = known or row.reach end
    if not known then return ns.say(L.placeNoSpot) end
    ns.say(L.placeHead:format(L.PROFS[r.pr] or r.pr or r.title))
    local seen = {}
    for _, row in ipairs(rows) do
      if not seen[row.k] then
        seen[row.k] = true
        local far = row.reach or 0
        far = far >= 1e9 and L.placeNoWay or far >= 1e5 and L.placeSea
              or L.placeYards:format(math.floor(far / 10 + 0.5) * 10)
        local words = row.step and ns.Text.Step(row.step, r.pack) or ''
        local line = ('  %s, %s: %s'):format(ns.Text.Map(row.p[1]), far, words)
        if row.k == held then line = line .. ' ' .. L.placeShown
        elseif row.k == best then line = line .. ' ' .. L.placeBest end
        ns.say(line)
      end
    end
    if held and best and held ~= best then ns.say(L.placeHeld) end
    return
  end
  if cmd == 'talents' or cmd == 'talent' then
    -- (talent plans while they're tested: on, off, list, or a plan to pick by its name or id)
    local T, a = ns.Talents, (arg or ''):lower()
    if a == 'on' or a == 'off' then
      T.SetEnabled(a == 'on')
      return ns.say(a == 'on' and L.talentsOn or L.talentsOff)
    end
    if not T.Enabled() then return ns.say(L.talentsOffHint) end
    local plans = T.Plans()
    if a == '' or a == 'list' then
      local names = {}
      for _, p in ipairs(plans) do names[#names + 1] = T.Title(p) .. ' (' .. p.id .. ')' end
      ns.say(L.talentsList:format(#names > 0 and table.concat(names, ', ') or L.menuTalentsNone))
      local cur, nxt = T.Plan(), T.Next()
      if cur then ns.say(L.talentsPicked:format(T.Title(cur))) end
      if nxt then ns.say(L.talentsNext:format(T.Name(nxt), nxt.rank, nxt.level)) end
      return
    end
    for _, p in ipairs(plans) do
      if p.id == a or p.name:lower() == a or T.Title(p):lower() == a then
        T.SetPlan(p.id) return ns.say(L.talentsPicked:format(T.Title(p)))
      end
    end
    return ns.say(L.talentsNoSuch:format(arg))
  end
  if cmd == 'report' then return ns.Report() end
  if cmd == 'autolog' then   -- what automation saw and did at the last quest windows (FB-038)
    for _, e in ipairs(ns.db.autoLog or {}) do ns.say(ns.Auto.Line(e)) end
    return
  end
  if cmd == 'language' or cmd == 'lang' or cmd == 'welcome' then return ns.Welcome.Show() end
  if cmd == 'oath' or cmd == 'setup' then return ns.Welcome.Oath() end
  if cmd == 'tour' then   -- (/bofg tour, /bofg tour 2 for one chapter, /bofg tour offer: the new install's offer again)
    if arg == 'offer' then
      if ns.db.tour then ns.db.tour.offered = nil end
      return ns.Tour.Offer()
    end
    return ns.Tour.Start(tonumber(arg))
  end
  if cmd == 'feedback' or cmd == 'bug' or cmd == 'problem' then
    if (arg or ''):lower():match('^last') then return ns.Feedback.Last() end
    return ns.Feedback.Show(cmd == 'bug' and 'bug' or nil)
  end
  if cmd == 'list' then
    for _, r in ipairs(ns.Packs.For(ns.Engine.Who())) do
      ns.say(L.listLine:format(r.id, levelsOf(r), ns.Engine.Route() == r and L.listCurrent or ''))
    end
    return
  end
  if cmd == 'dungeons' then
    for _, r in ipairs(ns.Packs.Dungeons(ns.Engine.Who())) do
      ns.say(L.listLine:format(r.id, levelsOf(r), ns.cdb.dungeons[r.id] and L.listDone or ''))
    end
    return
  end
  if cmd == 'dungeon' then
    if arg == 'off' then ns.cdb.dungeon = nil ns.MarkDirty('route') return ns.say(L.dungeonOff) end
    local want = arg ~= '' and arg:lower() or ns.Engine.StopAhead()
    if want then
      for _, r in ipairs(ns.Packs.Dungeons(ns.Engine.Who())) do
        if r.id == want or r.id:find(want, 1, true) or (r.title or ''):lower():find(want, 1, true) then
          ns.Engine.SetRoute(r.id)
          return ns.say(L.dungeonShown:format(r.title or r.id))
        end
      end
    end
    if arg == '' then return ns.say(L.dungeonName) end
    return ns.say(L.dungeonNone:format(arg))
  end
  if cmd == 'prof' then
    if arg == 'off' then ns.cdb.prof = nil ns.MarkDirty('route') return ns.say(L.profOff) end
    local list = ns.Packs.Professions(ns.Engine.Who())
    if arg == '' then
      if #list == 0 then return ns.say(L.profNoGuides) end
      for _, r in ipairs(list) do
        local rank = ns.st.profs[r.pr]
        ns.say(('%s  %s%s%s'):format(r.id, r.title or '', rank and L.profYou:format(rank) or '',
          ns.cdb.prof == r.id and L.profShownMark or ''))
      end
      return
    end
    local want = arg:lower()
    for _, r in ipairs(list) do
      local nice = (L.PROFS[r.pr] or ''):lower()
      if r.id == want or r.pr == want or nice == want or r.id:find(want, 1, true) or (nice ~= '' and nice:find(want, 1, true)) then
        ns.Engine.SetRoute(r.id)
        local function say() local now = ns.Engine.Route() ns.say(L.profShown:format(now and now.title or r.title or r.id)) end
        if C_Timer and C_Timer.After then return C_Timer.After(0.2, say) end
        return say()
      end
    end
    return ns.say(L.profPick:format(arg))
  end
  if cmd == 'legacy' then
    if arg == 'off' then ns.cdb.legacy = nil ns.MarkDirty('route') return ns.say(L.legacyOff) end
    local r = ns.Packs.Legacy(ns.Engine.Who())
    if not r then return ns.say(L.legacyNone) end
    ns.Engine.SetRoute(r.id)
    return ns.say(L.legacyShown)
  end
  if cmd == 'shopping' then return ns.Engine.Shopping(arg == 'all') end
  if cmd == 'import' then
    local sub_, id = arg:match('^(%S*)%s*(.-)$')
    if sub_ == 'forget' then
      if ns.Packs.Forget(id) then return ns.say(L.importForgot:format(id)) end
      return ns.say(L.importNone:format(id))
    end
    return ns.Import.Show()
  end
  if cmd == 'packs' then
    local ids = {}
    for id in pairs(ns.Packs.byId) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids == 0 then return ns.say(L.noPacks) end
    for _, id in ipairs(ids) do
      local p = ns.Packs.byId[id]
      local n = 0
      for _ in ipairs(p.routes) do n = n + 1 end
      ns.say(L.packLine:format(id, p.title or id, ns.count('guideCount', n), p.source or '?', tostring(p.ver or '?'),
        p.stamp and p.stamp.build or '?'))
    end
    return
  end
  if cmd == 'route' then
    local id = arg
    if not ns.Packs.Get(id) and arg ~= '' then   -- (a name works too: /bofg route westfall)
      for _, r in ipairs(ns.Packs.For(ns.Engine.Who())) do
        if (r.title or ''):lower():find(arg:lower(), 1, true) then id = r.id break end
      end
    end
    if arg ~= '' and ns.Engine.SetRoute(id) then
      local r = ns.Packs.Get(id)
      return ns.say(L.routeNow:format(r and r.title or id))
    end
    return ns.say(arg == '' and L.routeName or L.routeNone:format(arg))
  end
  if cmd == 'back' or cmd == 'prev' then return ns.Engine.Back() end   -- (look back one step; again for the one before)
  if (cmd == 'forward' or cmd == 'next' or cmd == 'resume' or cmd == 'now') and not ns.Engine.Peeking() then
    return ns.say(L.notPeeking)
  end
  if cmd == 'forward' or cmd == 'next' then return ns.Engine.Forward() end
  if cmd == 'resume' or cmd == 'now' then return ns.Engine.Resume() end
  if cmd == 'unskip' then return ns.Engine.UnskipLast() end
  if cmd == 'skip' then
    if ns.Engine.LocalSkip and ns.Engine.LocalSkip() then ns.say(L.localSkipped) return end   -- (your quests here: Nov 9)
    if ns.Travel and ns.Travel.Active() and ns.Travel.Skip() then ns.say(L.tripSkipped) return end   -- (FB-049)
    local view, route = ns.Engine.View(), ns.Engine.Route()
    if view and view.cursor then return ns.Engine.Click(route.steps[view.cursor].k, 'LeftButton') end
    return
  end
  if cmd == 'waypoint' then
    if arg == 'blizzard' or arg == 'on' or arg == 'off' then
      ns.settings.waypoint = arg == 'off' and 'off' or 'blizzard'
      if arg == 'off' then ns.Waypoint.Clear() end
      ns.MarkDirty('settings')
    end
    ns.say(L.waypointSet:format(ns.settings.waypoint == 'off' and L.off or L.on))
    if arg ~= 'blizzard' and arg ~= 'on' and arg ~= 'off' then ns.say(L.waypointUsage) end
    return
  end
  if cmd == 'hc' then
    if arg == 'auto' or arg == 'on' or arg == 'off' then
      ns.settings.hc = arg
      ns.State.Player()
      ns.MarkDirty('settings')
    end
    ns.say(L.hcSet:format(L.HC_MODES[ns.settings.hc or 'auto'] or ns.settings.hc))
    if arg ~= 'auto' and arg ~= 'on' and arg ~= 'off' then ns.say(L.hcUsage) end
    return
  end
  if cmd == 'auto' then
    local kind, state = arg:match('^(%S*)%s*(%S*)$')
    if (kind == 'on' or kind == 'off') and state == '' then kind, state = 'all', kind end   -- /bofg auto off: all of it
    local a = ns.settings.auto
    if kind == '' then
      local parts = {}
      for _, k in ipairs({ 'accept', 'turnin', 'gossip', 'taxi' }) do
        parts[#parts + 1] = L.AUTO_SHORT[k] .. ' ' .. (a[k] and L.on or L.off)
      end
      ns.say(L.autoState:format(table.concat(parts, ', ')))
      return ns.say(L.autoStateHow)
    end
    if (state == 'on' or state == 'off') and (a[kind] ~= nil or kind == 'all') then
      for _, k in ipairs({ 'accept', 'turnin', 'gossip', 'taxi' }) do
        if kind == 'all' or kind == k then a[k] = state == 'on' end
      end
      if state == 'on' then ns.AutoResume() end
      if ns.Window.Header then ns.Window.Header() end
      return ns.say(L.autoSet:format(kind == 'all' and L.autoAll or L.AUTO_SHORT[kind], state == 'on' and L.on or L.off))
    end
    return ns.say(L.autoUsage)
  end
  if cmd == 'items' or cmd == 'targets' then
    if arg == 'on' or arg == 'off' then
      ns.settings[cmd] = arg == 'on'
      if cmd == 'items' then ns.Panels.Want({}) else ns.Panels.Targets({}) end
      ns.MarkDirty('settings')
    end
    ns.say((cmd == 'items' and L.itemsSet or L.targetsSet):format(ns.settings[cmd] == false and L.off or L.on))
    if arg ~= 'on' and arg ~= 'off' then ns.say(L.panelUsage:format(cmd)) end
    return
  end
  if cmd == 'mark' then
    local word, rest = arg:match('^(%S*)%s*(.-)$')
    word = (word or ''):lower()
    if word == 'test' then   -- (a test tool, like /bofg selftest: its lines stay in English)
      local got = ns.Marks.Try(rest:lower())
      return ns.say(({ on = 'Waymark test: walk 25 yards away and look back: the pin comes up on this spot. /bofg mark test vendor changes the pin, done stamps it, off ends it.',
        far = 'Waymark test: stand right beside them first: the pin goes where you stand.', pin = 'Waymark test: pin changed.',
        done = 'Waymark test: stamped.', off = 'Waymark test over.', nothing = 'No Waymark test running.',
        nowhere = 'Waymark test: the game has no waypoints here.' })[got])
    end
    if word == 'size' and tonumber(rest) then return ns.say(L.markSized:format(ns.Marks.SetScale(tonumber(rest) / 100) * 100)) end
    if word == 'lift' and tonumber(rest) then return ns.say(L.markLifted:format(ns.Marks.SetLift(tonumber(rest)))) end
    if word == 'plates' and (rest == 'on' or rest == 'small' or rest == 'off') then
      if not ns.Marks.Plates(rest) then return ns.say(L.markCombat) end
      return ns.say(L.markPlates:format(UNIT_NAMEPLATES_SHOW_FRIENDLY_NPCS or 'nameplateShowFriendlyNpcs',
        rest == 'small' and L.markSmall or L[rest]))
    end
    local v = ns.settings.marks ~= true
    if word == 'on' then v = true elseif word == 'off' then v = false end
    ns.Marks.Enable(v)
    return ns.say(v and L.markOn or L.markOff)
  end
  if cmd == 'arrow' and tonumber(arg) then   -- /bofg arrow 130: the size in percent
    return ns.say(L.arrowSized:format(ns.Arrow.SetScale(tonumber(arg) / 100) * 100))
  end
  if cmd == 'arrow' and arg == 'reset' then ns.Arrow.ResetPosition() return ns.say(L.arrowResetDone) end
  if cmd == 'size' then   -- /bofg size 60: the window's size in percent
    if tonumber(arg) then return ns.say(L.windowSized:format(ns.Window.SetScale(tonumber(arg) / 100) * 100)) end
    ns.say(L.windowSized:format((ns.settings.scale or 1) * 100 + 0.5))
    return ns.say(L.sizeUsage)
  end
  if cmd == 'look' then return ns.Look.Show() end
  if cmd == 'book' or cmd == 'guides' then return ns.Book.Open(cmd == 'guides' and 'leveling' or nil) end
  if cmd == 'arrow' then
    -- (any other word hid it: "/bofg arrow show" hid the arrow; the QA pass, Oct 20)
    local on
    if arg == 'on' or arg == 'show' then on = true
    elseif arg == 'off' or arg == 'hide' then on = false
    elseif arg == '' then on = ns.settings.arrow == false
    else return ns.say(L.arrowUsage) end
    ns.Arrow.Enable(on)
    return ns.say(on and L.arrowShown or L.arrowHidden)
  end
  if cmd == 'collapse' then
    ns.settings.collapsed = not ns.settings.collapsed
    ns.MarkDirty('collapse')
    return
  end
  if cmd == 'cleanup' then
    if arg == 'go' then return ns.Cleanup.Drop((ns.Cleanup.Candidates())) end
    return ns.Cleanup.Ask()
  end
  if cmd == 'options' or cmd == 'settings' or cmd == 'config' then
    return ns.Book.Open('questing')
  end
  if cmd == 'reset' then
    wipe(ns.cdb.skip) wipe(ns.cdb.unskip) wipe(ns.cdb.done) if ns.cdb.passed then wipe(ns.cdb.passed) end ns.cdb.lead = nil ns.cdb.leads = nil
    ns.MarkDirty('all')
    return ns.say(L.resetDone)
  end
  for _, line in ipairs(L.help) do ns.say(line) end
end
