-- MapSeek: farm lists. A list of things to farm and how many of each (your own, kept by name).
-- Started, the trip's worked out: the farms in the order that's least riding between them, each
-- thing in the zone that suits the way round; and where the bags would fill, a stop at a mailbox
-- or bank to empty them, one after every big farm so two never run together. Then it takes you
-- round it: to each farm, on once you have enough, to each stop, on once the bags are emptied.
local _, ns = ...
local L = ns.L

local List = {}
ns.FarmList = List

local HBD = ns.MapLib and ns.MapLib("HBD", "GetWorldCoordinatesFromZone") or (LibStub and LibStub("HereBeDragons-2.0", true))

local MAX_ITEMS = 20        -- things in one list at most
local MAX_LISTS = 12
local FREE_AFTER = 4        -- bag slots more than when you got there, free again: the bags are emptied
local WANT_MOST = 9999
local RIDE = 9              -- yards a second, between farms: as the crow flies, a rough count
local SEA = 780             -- seconds for a place on another continent
local LARGE = 0.5           -- a farm that fills this share of your free bags: a stop to empty them after it
local ZONES = 3             -- a thing's zones weighed for the way round, the best of them
local ZONE_SHARE = 0.6      -- (one this much as good as its best, at least)
local GROUP_ZONES = 8       -- a thing's zones weighed for farming it where another of the list's is farmed
local GROUP_SHARE = 0.35    -- (one this much as good as its best, at least)

--------------------------------------------------------------------------------
-- What's kept (ns.db.lists): all = { { name, items = { { id, name, want }, ... } }, ... },
-- at (the list shown), bagStop ("mail", "bank", "off"), bagFree (slots left that count as
-- nearly full), bank (the bank's counted too), running (the list's being farmed), pos
--------------------------------------------------------------------------------

local function DB()
	local db = ns.db
	db.lists = db.lists or {}
	local d = db.lists
	d.all = d.all or {}
	if #d.all == 0 then d.all[1] = { name = L["My list"], items = {} } end
	d.at = math.min(math.max(tonumber(d.at) or 1, 1), #d.all)
	d.bagStop = d.bagStop or "mail"
	d.bagFree = tonumber(d.bagFree) or 2
	return d
end

local function Cur()
	local d = DB()
	return d.all[d.at]
end

--- how many of an item you have (your bags; the bank's too, when that's counted)
local function Count(id)
	local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	if not (f and id) then return 0 end
	local ok, n = pcall(f, id, DB().bank and true or false)
	return ok and tonumber(n) or 0
end
List.Count = Count

--- free slots in your bags (the ones anything goes in: not a quiver, a herb bag)
local function FreeSlots()
	local f = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
	if not f then return 99 end
	local free = 0
	for bag = 0, 4 do
		local ok, n, family = pcall(f, bag)
		if ok and tonumber(n) and (not family or family == 0) then free = free + n end
	end
	return free
end
List.FreeSlots = FreeSlots

-- how many of an item go in one slot
local function Stack(id)
	local f = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if f then
		local ok, _, _, _, _, _, _, _, stack = pcall(f, id)
		if ok and tonumber(stack) and stack > 0 then return stack end
	end
	return 20
end

local function Say(text) ns.Print(text) end

--------------------------------------------------------------------------------
-- The trip: worked out from where you are
--------------------------------------------------------------------------------

local state = { plan = nil, at = 1, riding = nil, mine = false }
local none = {}        -- (things there's no farm for: passed over)
local Refresh          -- (below: the window, when it's up)

-- a place on a zone's map (x, y 0..100) as the world has it
local function Place(ui, x, y, name)
	if not (HBD and HBD.GetWorldCoordinatesFromZone and ui and x and y) then return end
	local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(x / 100, y / 100, ui)
	if not wx then return end
	return { wx = wx, wy = wy, inst = inst, ui = ui, x = x, y = y, name = name }
end

-- seconds from one place to another, roughly: riding straight; far more to another continent
local function Travel(a, b)
	if not (a and b) then return SEA end
	if a.inst ~= b.inst then return SEA end
	return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2) / RIDE
end

-- a thing's farms to choose between for the way round: its best few zones for you, each with
-- its loop, what it's of, what's marked for it, and where it is (the middle of its loop)
local function Choices(it)
	if not (ns.Farm and ns.Farm.Parse and ns.Index and ns.Index.done) then return {} end
	local thing, kind = ns.Farm.Parse(it.name .. " farm")
	if not thing then return {} end
	local opts, title, nodes = ns.Farm.Options(thing, kind)
	local out = {}
	local function Take(o)
		local sx, sy, n = 0, 0, 0
		for _, s in ipairs(o.spots or {}) do
			if s.x and s.y then sx, sy, n = sx + s.x, sy + s.y, n + 1 end
		end
		out[#out + 1] = { o = o, title = o.title or title, nodes = o.own or nodes,
			at = n > 0 and Place(o.ui, sx / n, sy / n) or nil }
	end
	-- (wide: a zone only worth it for farming two of the list's things in the one place)
	local top, narrow = nil, 0
	for _, o in ipairs(opts or {}) do
		if not o.more and not o.high then
			local rate = o.rate or 0
			top = top or rate
			if #out < GROUP_ZONES and rate >= top * GROUP_SHARE then
				Take(o)
				local c = out[#out]
				c.share = top > 0 and rate / top or 1
				if narrow < ZONES and rate >= top * ZONE_SHARE then narrow = narrow + 1 else c.wide = true end
			end
		end
	end
	-- (none for your level: its first all the same, said to be above you when it's ridden)
	if #out == 0 and opts and opts[1] and not opts[1].more then Take(opts[1]) end
	return out
end

-- every mailbox (or bank) there is, as places
local function Stops(kind)
	local query = kind == "bank" and "bank" or "mailbox"
	local ok, results = pcall(ns.Search.Run, query, true)
	local out = {}
	for _, r in ipairs(ok and type(results) == "table" and results or {}) do
		for _, p in ipairs(r.points or {}) do
			local s = Place(p.ui, p.x, p.y, r.entry and r.entry.name or query)
			if s then out[#out + 1] = s end
		end
	end
	return out
end

local function Here()
	if not (HBD and HBD.GetPlayerWorldPosition) then return end
	local px, py, inst = HBD:GetPlayerWorldPosition()
	return px and { wx = px, wy = py, inst = inst } or nil
end

-- the stop that adds least to the way from one place on to another
local function BestStop(stops, from, toward)
	local best, least
	for _, s in ipairs(stops) do
		local secs = Travel(from, s) + (toward and Travel(s, toward) or 0)
		if not least or secs < least then best, least = s, secs end
	end
	return best
end

--- the trip for the list shown, from where you stand: { { kind = "farm", it, o, title, nodes,
--- zone, high, slots }, { kind = "empty", to, zone }, ... }. The farms the nearest next, each
--- time; a stop to empty the bags before a farm that wouldn't fit in what's left of them, and
--- after any farm that's a big share of them
local function BuildPlan()
	local d = DB()
	local cur = Cur()
	local todo, held = {}, 0
	for _, it in ipairs(cur.items) do
		local have = Count(it.id)
		if have > 0 then held = held + math.ceil(have / Stack(it.id)) end
		if have < it.want then
			local ch = Choices(it)
			if #ch > 0 then
				none[it] = nil
				todo[#todo + 1] = { it = it, choices = ch, slots = math.ceil((it.want - have) / Stack(it.id)) }
			else
				none[it] = true
			end
		end
	end
	local steps = {}
	local pos = Here()
	local stops = (d.bagStop ~= "off" and #todo > 1) and Stops(d.bagStop) or {}
	-- (room in the bags: what's free now; emptied, what's free with the list's own things gone too)
	local free = FreeSlots()
	local capNow = math.max(1, free - d.bagFree)
	local capFull = math.max(capNow, free + held - d.bagFree)
	local cap, used = capNow, 0
	-- things farmed in the one zone, together: the zone the most of what's left can be farmed in,
	-- taken for all of those (two at least); then again with the rest, till no zone has two
	local units = {}
	while true do
		local zones, best = {}, nil
		for _, t in ipairs(todo) do
			if not t.c then
				local seen = {}
				for _, c in ipairs(t.choices) do
					local ui = c.o.ui
					if ui and not seen[ui] then
						seen[ui] = true
						local z = zones[ui]
						if not z then z = { ui = ui, n = 0, share = 0, picks = {} } zones[ui] = z end
						z.n, z.share = z.n + 1, z.share + (c.share or 1)
						z.picks[#z.picks + 1] = { t = t, c = c }
					end
				end
			end
		end
		for _, z in pairs(zones) do
			if z.n >= 2 and (not best or z.n > best.n or (z.n == best.n and (z.share > best.share
				or (z.share == best.share and z.ui < best.ui)))) then best = z end
		end
		if not best then break end
		local u = { group = true, slots = 0, members = {} }
		local sx, sy, n, inst = 0, 0, 0, nil
		for _, pk in ipairs(best.picks) do
			pk.t.c = pk.c
			u.members[#u.members + 1] = { t = pk.t, c = pk.c, u = u }
			u.slots = u.slots + pk.t.slots
			if pk.c.at then sx, sy, n, inst = sx + pk.c.at.wx, sy + pk.c.at.wy, n + 1, pk.c.at.inst end
		end
		if n > 0 then u.at = { wx = sx / n, wy = sy / n, inst = inst } end
		units[#units + 1] = u
	end
	-- (the rest, each by itself: its own best few zones to choose between)
	for _, t in ipairs(todo) do
		if not t.c then
			local u = { slots = t.slots, choices = {} }
			for _, c in ipairs(t.choices) do
				if not c.wide then u.choices[#u.choices + 1] = c end
			end
			if #u.choices == 0 then u.choices[1] = t.choices[1] end
			u.members = { { t = t, u = u } }
			units[#units + 1] = u
		end
	end
	-- their order. First each time the nearest of what's left (a thing by itself with several
	-- zones: whichever of them is nearest); then that order turned about, a stretch of it at a
	-- time, wherever that makes the whole way round shorter
	local start = pos
	local uorder = {}
	for _ = 1, #units do
		local bi, bc, bt
		for i, u in ipairs(units) do
			if u.group then
				local secs = (pos and u.at) and Travel(pos, u.at) or (pos and SEA or 0)
				if not bt or secs < bt then bi, bc, bt = i, nil, secs end
			else
				for _, c in ipairs(u.choices) do
					local secs = (pos and c.at) and Travel(pos, c.at) or (pos and SEA or 0)
					if not bt or secs < bt then bi, bc, bt = i, c, secs end
				end
			end
		end
		local u = table.remove(units, bi)
		if bc then u.members[1].c, u.at = bc, bc.at end
		uorder[#uorder + 1] = u
		if u.at then pos = u.at end
	end
	local function Whole()
		local sum, at = 0, start
		for _, u in ipairs(uorder) do
			if at and u.at then sum = sum + Travel(at, u.at) end
			at = u.at or at
		end
		return sum
	end
	local n = #uorder
	for _ = 1, 20 do
		local better = false
		for i = 1, n - 1 do
			for j = i + 1, n do
				local before = Whole()
				local lo, hi = i, j
				while lo < hi do uorder[lo], uorder[hi] = uorder[hi], uorder[lo] lo, hi = lo + 1, hi - 1 end
				if Whole() < before - 1 then
					better = true
				else
					lo, hi = i, j
					while lo < hi do uorder[lo], uorder[hi] = uorder[hi], uorder[lo] lo, hi = lo + 1, hi - 1 end
				end
			end
		end
		if not better then break end
	end
	-- (laid out: a zone's things one after another, the nearest next each time)
	local order = {}
	pos = start
	for _, u in ipairs(uorder) do
		local left = {}
		for _, m in ipairs(u.members) do left[#left + 1] = m end
		while #left > 0 do
			local bi, bt
			for i, m in ipairs(left) do
				local secs = (pos and m.c.at) and Travel(pos, m.c.at) or 0
				if not bt or secs < bt then bi, bt = i, secs end
			end
			local m = table.remove(left, bi)
			order[#order + 1] = m
			if m.c.at then pos = m.c.at end
		end
	end
	-- the stops: before a farm that wouldn't fit in what's left of the bags (before a zone's
	-- things all together, when they'd fit emptied: not between them); and after a big one, a
	-- zone's things counted as the one farm
	pos = start
	local function Stop(toward)
		local s = pos and BestStop(stops, pos, toward)
		if not s then return false end
		steps[#steps + 1] = { kind = "empty", to = { ui = s.ui, x = s.x, y = s.y, name = s.name },
			zone = ns.ZoneName(s.ui) or "?" }
		pos, used, cap = s, 0, capFull
		return true
	end
	for k, f in ipairs(order) do
		local t, c, u = f.t, f.c, f.u
		local prev, nxt = order[k - 1], order[k + 1]
		local first = not (prev and prev.u == u)
		if used > 0 and (used + t.slots > cap
			or (first and used + u.slots > cap and u.slots <= capFull)) then Stop(c.at) end
		steps[#steps + 1] = { kind = "farm", it = t.it, o = c.o, title = c.title, nodes = c.nodes,
			zone = c.o.zone, high = c.o.high, slots = t.slots, with = u.group and u or nil }
		if c.at then pos = c.at end
		used = used + t.slots
		if nxt and nxt.u ~= u and u.slots >= capFull * LARGE then Stop(nxt.c.at) end
	end
	return steps
end
List.BuildPlan = BuildPlan

--- the trip, as worked out last (for the window); worked out now when there's none yet
function List.Plan()
	if not state.plan and ns.Index and ns.Index.done then
		state.plan, state.at, state.riding = BuildPlan(), 1, nil
	end
	return state.plan, state.at
end

local function Forget()
	state.plan, state.at, state.riding = nil, 1, nil
end

local function GoTo(step)
	state.mine = true
	local ok, started
	if step.kind == "farm" then
		ok, started = pcall(ns.UI.RideFarm, step.o, step.title, step.nodes, step.it.name:lower() .. " farm")
	else
		ok, started = pcall(ns.Route.Start, step.to)
		-- (a few steps away: no route, a waypoint)
		if not (ok and started) and ns.Pins.SetWaypoint then pcall(ns.Pins.SetWaypoint, step.to, true) end
		ok, started = true, true
	end
	state.mine = false
	if ok and started then state.riding = step end
	return ok and started
end

--- on with the trip: past what's done, to what's next; the list done at its end
function List.Next()
	local d = DB()
	if not d.running then return end
	local steps = List.Plan()
	if not steps then return end
	local active = ns.Route.Active and ns.Route.Active()
	for _ = 1, 80 do
		local step = steps[state.at]
		if not step then break end
		if step.kind == "farm" then
			local have = Count(step.it.id)
			if have >= step.it.want then
				if step.begun then Say(L["Farm list: that's %d %s."]:format(have, step.it.name)) end
				state.at = state.at + 1
			elseif d.bagStop ~= "off" and FreeSlots() <= d.bagFree and not step.noStop then
				-- (the bags nearly full all the same: a stop not planned for, the nearest, then back to this)
				local here = Here()
				local s = here and BestStop(Stops(d.bagStop), here)
				if s then
					table.insert(steps, state.at, { kind = "empty", to = { ui = s.ui, x = s.x, y = s.y, name = s.name },
						zone = ns.ZoneName(s.ui) or "?", full = true })
				else
					step.noStop = true
					Say(L["Farm list: your bags are nearly full, and there's no %s to be found on this continent. Empty them and it goes on."]
						:format(d.bagStop == "bank" and L["bank"] or L["mailbox"]))
				end
			else
				if state.riding ~= step or not active then
					if GoTo(step) then
						step.begun = true
						Say(L["Farm list: %s, %d of %d. Farming it in %s."]:format(step.it.name, have, step.it.want, step.zone or "?")
							.. (step.high and ("  |cffff6040" .. L["It's level %d and up there, above yours."]:format(step.high) .. "|r") or ""))
					else
						none[step.it] = true
						Say(L["Farm list: there's no farm for %s. Passed over."]:format(step.it.name))
						state.at = state.at + 1
						active = ns.Route.Active and ns.Route.Active()
					end
				end
				if state.riding == step then
					if Refresh then Refresh() end
					return
				end
			end
		else
			if step.done then
				state.at = state.at + 1
			else
				if not step.going then
					step.going, step.free0 = true, FreeSlots()
					GoTo(step)
					Say((step.full and L["Farm list: your bags are nearly full. Heading to %s to empty them; it goes on once they are."]
						or L["Farm list: next, %s, to empty your bags before the next farm."]):format(step.to.name))
				end
				if Refresh then Refresh() end
				return
			end
		end
	end
	-- (the trip's end)
	d.running = nil
	Forget()
	state.mine = true
	if ns.Route.Active and ns.Route.Active() then pcall(ns.Route.Stop) end
	state.mine = false
	Say(L["Farm list done: %s."]:format(Cur().name))
	if Refresh then Refresh() end
end

function List.Start()
	local d = DB()
	if #Cur().items == 0 then
		Say(L["Farm list: add something to farm first."])
		return
	end
	if not (ns.Index and ns.Index.done) then
		Say(L["Farm list: MapSeek is still reading its data. Try again in a moment."])
		return
	end
	wipe(none)
	Forget()
	d.running = true
	local steps = List.Plan() or {}
	local farms, empties = 0, 0
	for _, s in ipairs(steps) do
		if s.kind == "farm" then farms = farms + 1 else empties = empties + 1 end
	end
	if farms > 0 then
		Say((empties > 0 and L["Farm list: %d to farm, with %d stops to empty your bags on the way."]
			or L["Farm list: %d to farm."]):format(farms, empties))
	end
	List.Next()
	if Refresh then Refresh() end
end

function List.Stop(quiet)
	local d = DB()
	local was = d.running
	d.running = nil
	Forget()
	state.mine = true
	if was and ns.Route.Active and ns.Route.Active() then pcall(ns.Route.Stop) end
	state.mine = false
	if was and not quiet then Say(L["Farm list stopped."]) end
	if Refresh then Refresh() end
end

function List.Running() return DB().running and true or false end

--- the step you're on, passed: a stop taken as done, a farm left as it is
function List.Skip()
	local d = DB()
	if not (d.running and state.plan) then return end
	local step = state.plan[state.at]
	if not step then return end
	if step.kind == "empty" then step.done = true else state.at = state.at + 1 end
	List.Next()
	if Refresh then Refresh() end
end

--- a route stopped (its X, /seek stop): not by the list itself, the list's paused. One to a
--- mailbox, come to its end: the list waits there for the bags
function List.RouteStopped()
	if state.mine then return end
	local d = ns.db and ns.db.lists
	if not (d and d.running) then return end
	local step = state.plan and state.plan[state.at]
	if step and step.kind == "empty" then return end
	d.running = nil
	state.riding = nil
	Say(L["Farm list paused. Start it again from its window."])
	if Refresh then Refresh() end
end

-- what's in the bags changed, or the mailbox or bank was closed: a stop's done once the bags
-- have room again; then on
local function Check(event)
	local d = ns.db and ns.db.lists
	if not d then return end
	if d.running and state.plan then
		local step = state.plan[state.at]
		if step and step.kind == "empty" and step.going and not step.done then
			if event == "MAIL_CLOSED" or event == "BANKFRAME_CLOSED" or FreeSlots() >= (step.free0 or 0) + FREE_AFTER then
				step.done = true
			end
		end
		List.Next()
	end
	if Refresh then Refresh() end
end
List.Check = Check

-- the list changed: the trip worked out again (and, being farmed, taken up from where you are)
local function Changed()
	Forget()
	if DB().running then List.Next() end
	if Refresh then Refresh() end
end

--------------------------------------------------------------------------------
-- The lists themselves
--------------------------------------------------------------------------------

--- what's typed, or an item's link: its id and name; nil when it's no item
local function Resolve(text)
	text = strtrim(text or "")
	if text == "" then return end
	local id = tonumber(text:match("|Hitem:(%d+)"))
	if id then
		local name = text:match("|h%[(.-)%]|h")
		if name then return id, name end
	end
	if not (ns.Farm and ns.Farm.ItemNamed) then return end
	local id2, name2 = ns.Farm.ItemNamed(text)
	if id2 then return id2, name2 end
	-- (not an item's whole name: the one meant by it, "copper" the ore, as the search has it)
	if ns.Farm.ItemLike then return ns.Farm.ItemLike(text) end
end

--- a thing added to the list shown (or, there already, its count changed): true, or false and why
function List.Add(text, want)
	local id, name = Resolve(text)
	if not id then return false, L["Farm list: no item called \"%s\"."]:format(strtrim(text or "")) end
	want = math.min(WANT_MOST, math.max(1, math.floor(tonumber(want) or 20)))
	local items = Cur().items
	for _, it in ipairs(items) do
		if it.id == id then
			it.want = want
			Changed()
			return true
		end
	end
	if #items >= MAX_ITEMS then return false, L["Farm list: a list holds %d things at most."]:format(MAX_ITEMS) end
	items[#items + 1] = { id = id, name = name, want = want }
	Changed()
	return true
end

function List.Remove(it)
	local items = Cur().items
	for i = #items, 1, -1 do
		if items[i] == it then table.remove(items, i) end
	end
	none[it] = nil
	Changed()
end

function List.Want(it, by)
	it.want = math.min(WANT_MOST, math.max(1, it.want + by))
	Changed()
end

function List.BagStop(kind)
	DB().bagStop = kind
	Changed()
end

function List.Pick(i)
	local d = DB()
	if not d.all[i] or i == d.at then return end
	List.Stop(true)
	d.at = i
	if Refresh then Refresh() end
end

function List.New(name)
	local d = DB()
	name = strtrim(name or "")
	if name == "" then return end
	if #d.all >= MAX_LISTS then Say(L["Farm list: %d lists at most."]:format(MAX_LISTS)) return end
	List.Stop(true)
	d.all[#d.all + 1] = { name = name:sub(1, 40), items = {} }
	d.at = #d.all
	if Refresh then Refresh() end
end

function List.Rename(name)
	name = strtrim(name or "")
	if name == "" then return end
	Cur().name = name:sub(1, 40)
	if Refresh then Refresh() end
end

function List.Delete()
	local d = DB()
	List.Stop(true)
	table.remove(d.all, d.at)
	DB()
	if Refresh then Refresh() end
end

--------------------------------------------------------------------------------
-- The window: the list's name (a menu of them all); the trip, step by step, each farm with how
-- many you have of how many you want, the stops to empty your bags between them; a line to add
-- a thing; and Start. Its own window, there with the map closed, dragged where you like
--------------------------------------------------------------------------------

do
local WIDTH, PAD, ROW = 340, 10, 22
local panel, rows = nil, {}
local STOPS = { "mail", "bank", "off" }
local STOP_ICON = { mail = "Interface\\Icons\\INV_Letter_15", bank = "Interface\\Icons\\INV_Misc_Bag_10" }

local function StopText(kind)
	return kind == "bank" and L["Emptying your bags: at a bank"] or kind == "off" and L["Emptying your bags: no stops"]
		or L["Emptying your bags: at a mailbox"]
end

local function NamePrompt(title, text, onAccept)
	if not StaticPopupDialogs then return end
	StaticPopupDialogs["MAPSEEK_LIST_NAME"] = {
		text = title, button1 = ACCEPT or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, maxLetters = 40,
		timeout = 0, whileDead = true, hideOnEscape = true,
		OnShow = function(self)
			local box = self.editBox or self.EditBox
			if box then box:SetText(text or "") box:HighlightText() box:SetFocus() end
		end,
		OnAccept = function(self)
			local box = self.editBox or self.EditBox
			if box then onAccept(box:GetText()) end
		end,
		EditBoxOnEnterPressed = function(box)
			onAccept(box:GetText())
			local parent = box:GetParent()
			if parent and parent.Hide then parent:Hide() end
		end,
		EditBoxOnEscapePressed = function(box)
			local parent = box:GetParent()
			if parent and parent.Hide then parent:Hide() end
		end,
	}
	StaticPopup_Show("MAPSEEK_LIST_NAME")
end

local function ListMenu(owner)
	local d = DB()
	local items = { { title = L["Farm lists"] } }
	for i, l in ipairs(d.all) do
		items[#items + 1] = { text = l.name, radio = true, checked = function() return DB().at == i end,
			func = function() List.Pick(i) end }
	end
	items[#items + 1] = { divider = true }
	items[#items + 1] = { text = L["New list..."], func = function()
		NamePrompt(L["A name for the new farm list:"], "", List.New)
	end }
	items[#items + 1] = { text = L["Rename this list..."], func = function()
		NamePrompt(L["A new name for this farm list:"], Cur().name, List.Rename)
	end }
	if #d.all > 1 then
		items[#items + 1] = { text = L["Delete this list"], func = function() List.Delete() end }
	end
	ns.OpenMenu(owner, items)
end

local function Tip(frame, title, text)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title, 1, 0.82, 0.1)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Small(parent, w, texture)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, w)
	local t = b:CreateTexture(nil, "ARTWORK")
	t:SetAllPoints()
	t:SetTexture(texture)
	t:SetAlpha(0.75)
	b.tex = t
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	return b
end

local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, panel)
	r:SetHeight(ROW)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(16, 16)
	r.icon:SetPoint("LEFT", 0, 0)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- (at its right: off the list, and the count)
	r.off = Small(r, 14, "Interface\\Buttons\\UI-StopButton")
	r.off:SetPoint("RIGHT", 0, 0)
	r.off:SetScript("OnClick", function() if r.it then List.Remove(r.it) end end)
	if ns.SkinClose then ns.SkinClose(r.off, r.off.tex) end
	Tip(r.off, L["Take it off the list"])
	r.count = CreateFrame("Button", nil, r)
	r.count:SetSize(74, ROW)
	r.count:SetPoint("RIGHT", r.off, "LEFT", -4, 0)
	r.count:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r.count.text = ns.Text(r.count, "GameFontHighlightSmall")
	r.count.text:SetPoint("RIGHT", 0, 0)
	r.count:SetScript("OnClick", function(_, button)
		if not r.it then return end
		local step = IsShiftKeyDown() and 1 or 10
		List.Want(r.it, button == "RightButton" and -step or step)
	end)
	Tip(r.count, L["How many you have, of how many you want"],
		L["Click for 10 more, right-click for 10 fewer. With Shift: one at a time."])
	r.name = ns.Text(r, "GameFontHighlightSmall")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
	r.name:SetPoint("RIGHT", r.count, "LEFT", -4, 0)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	if ns.SkinText then ns.SkinText(r.name, r.count.text) end
	rows[i] = r
	return r
end

local function Build()
	local ok, f = pcall(CreateFrame, "Frame", "MapSeekFarmList", UIParent, "BackdropTemplate")
	if not ok or not f then f = CreateFrame("Frame", "MapSeekFarmList", UIParent) end
	f:SetWidth(WIDTH)
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint(1)
		if point then DB().pos = { point, x, y } end
	end)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		f:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
		f:SetBackdropBorderColor(1, 0.82, 0.1, 0.8)
	else
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.9)
		f.plainBg = bg
	end
	local at = DB().pos
	if type(at) == "table" and at[1] then f:SetPoint(at[1], UIParent, at[1], at[2] or 0, at[3] or 0)
	else f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 0) end

	local title = ns.Text(f, "GameFontNormal")
	title:SetPoint("TOPLEFT", PAD, -8)
	title:SetText(L["Farm list"])
	f.title = title
	local close = Small(f, 14, "Interface\\Buttons\\UI-StopButton")
	close:SetPoint("TOPRIGHT", -6, -7)
	close:SetScript("OnClick", function() f:Hide() end)
	if ns.SkinClose then ns.SkinClose(close, close.tex) end

	-- the list's name: a menu of them all
	local name = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	name:SetHeight(20)
	name:SetPoint("TOPLEFT", PAD, -26)
	name:SetPoint("TOPRIGHT", -PAD, -26)
	name:SetScript("OnClick", function(self) ListMenu(self) end)
	Tip(name, L["Farm lists"], L["Click for your other lists, a new one, or to rename or delete this one."])
	f.name = name

	-- a thing to add: its name (or its link, shift-clicked in), how many, Add
	local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	add:SetSize(44, 20)
	add:SetText(L["Add"])
	f.add = add
	local qty = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	qty:SetSize(38, 20)
	qty:SetAutoFocus(false)
	qty:SetNumeric(true)
	qty:SetMaxLetters(4)
	qty:SetText("20")
	f.qty = qty
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetHeight(20)
	box:SetAutoFocus(false)
	f.box = box
	local hint = ns.Text(f, "GameFontDisableSmall")
	hint:SetPoint("LEFT", box, "LEFT", 2, 0)
	hint:SetText(L["Item name, or shift-click one"])
	f.hint = hint
	box:SetScript("OnTextChanged", function(self) hint:SetShown((self:GetText() or "") == "") end)
	local function AddIt()
		local okA, why = List.Add(box:GetText(), tonumber(qty:GetText()))
		if okA then
			box:SetText("")
			box:ClearFocus()
		elseif why then
			Say(why)
		end
	end
	add:SetScript("OnClick", AddIt)
	box:SetScript("OnEnterPressed", AddIt)
	qty:SetScript("OnEnterPressed", AddIt)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	qty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	-- (an item shift-clicked while the box has the cursor: its link in it. The game's own call
	-- for a link, by whichever name this game has; and the split-a-stack window it goes on to, closed)
	do
		local last = 0
		local function Take(link)
			if not (box:IsVisible() and box:HasFocus() and type(link) == "string" and link:find("|Hitem:", 1, true)) then return end
			local now = GetTime()
			if now - last < 0.1 then return end
			last = now
			box:SetText(link)
			local function Back()
				if StackSplitFrame and StackSplitFrame:IsShown() then StackSplitFrame:Hide() end
				if box:IsVisible() then qty:SetFocus() qty:HighlightText() end
			end
			Back()
			C_Timer.After(0, Back)
			C_Timer.After(0.15, Back)
		end
		if hooksecurefunc then
			if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
				hooksecurefunc(ChatFrameUtil, "InsertLink", Take)
			end
			if type(ChatEdit_InsertLink) == "function" then hooksecurefunc("ChatEdit_InsertLink", Take) end
		end
	end

	-- where the bags are emptied on the way: a click goes round the choices
	local stop = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	stop:SetHeight(20)
	stop:SetScript("OnClick", function()
		local d = DB()
		local at = 1
		for i, k in ipairs(STOPS) do if k == d.bagStop then at = i end end
		List.BagStop(STOPS[at % #STOPS + 1])
	end)
	Tip(stop, L["Emptying your bags on the way"],
		L["The trip stops at a mailbox or a bank wherever your bags would fill, and after every big farm. Click to change which, or to have no stops."])
	f.stop = stop

	local go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	go:SetHeight(22)
	go:SetScript("OnClick", function()
		if List.Running() then List.Stop() else List.Start() end
	end)
	f.go = go
	local skip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	skip:SetSize(96, 22)
	skip:SetText(L["Next step"])
	skip:SetScript("OnClick", function() List.Skip() end)
	Tip(skip, L["Next step"], L["On to the next step now: a stop taken as done, a farm left as it is."])
	f.skip = skip

	local status = ns.Text(f, "GameFontHighlightSmall")
	status:SetJustifyH("LEFT")
	status:SetWordWrap(true)
	f.status = status
	if ns.SkinText then ns.SkinText(title, hint, status) end
	if ns.SkinPanel then ns.SkinPanel(f) end
	-- (EUI: its buttons and boxes)
	if ns.OnSkin then
		ns.OnSkin(function(S)
			for _, b in ipairs({ name, add, stop, go, skip }) do if S.Button then pcall(S.Button, b) end end
			for _, e in ipairs({ qty, box }) do if S.EditBox then pcall(S.EditBox, e) end end
		end)
	end
	f:Hide()
	panel = f
	return f
end

Refresh = function()
	if not (panel and panel:IsShown()) then return end
	local d = DB()
	local cur = Cur()
	panel.name:SetText(cur.name)
	-- the rows: the trip's steps in order; then what's on the list and not on the trip (had
	-- already, or with no farm)
	local steps, at = List.Plan()
	local shown, lines = {}, {}
	for i, s in ipairs(steps or {}) do
		lines[#lines + 1] = { step = s, i = i }
		if s.kind == "farm" then shown[s.it] = true end
	end
	for _, it in ipairs(cur.items) do
		if not shown[it] then lines[#lines + 1] = { it = it } end
	end
	local y = -52
	for n, line in ipairs(lines) do
		local r = Row(n)
		local s = line.step
		local it = s and s.it or line.it
		r.it = it
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", PAD, y)
		r:SetPoint("TOPRIGHT", -PAD, y)
		local col = { 1, 1, 1 }
		if s and d.running and line.i == at then col = { 1, 0.82, 0.1 }
		elseif s and d.running and line.i < at then col = { 0.55, 0.55, 0.55 } end
		if it then
			local have = Count(it.id)
			r.icon:SetTexture(ns.ItemIcon and ns.ItemIcon(it.id) or 134400)
			r.name:SetText(s and ("%s  |cff999999%s|r"):format(it.name, s.zone or "") or it.name)
			r.count.text:SetText(("%d / %d"):format(have, it.want))
			if have >= it.want then col = { 0.5, 1, 0.5 }
			elseif none[it] then col = { 0.6, 0.6, 0.6 }
			elseif s and s.high and not (d.running and line.i < at) then col = { 1, 0.5, 0.35 } end
			r.count:Show()
			r.off:Show()
		else
			r.icon:SetTexture(STOP_ICON[d.bagStop] or STOP_ICON.mail)
			r.name:SetText(("%s  |cff999999%s|r"):format(L["Empty your bags: %s"]:format(s.to.name or "?"), s.zone or ""))
			r.count.text:SetText("")
			r.count:Hide()
			r.off:Hide()
		end
		r.name:SetTextColor(col[1], col[2], col[3])
		r.count.text:SetTextColor(col[1], col[2], col[3])
		r:Show()
		y = y - ROW
	end
	for i = #lines + 1, #rows do rows[i]:Hide() end
	y = y - 6
	panel.add:ClearAllPoints()
	panel.add:SetPoint("TOPRIGHT", -PAD, y)
	panel.qty:ClearAllPoints()
	panel.qty:SetPoint("RIGHT", panel.add, "LEFT", -6, 0)
	panel.box:ClearAllPoints()
	panel.box:SetPoint("TOPLEFT", PAD + 6, y)
	panel.box:SetPoint("RIGHT", panel.qty, "LEFT", -10, 0)
	y = y - 28
	panel.stop:ClearAllPoints()
	panel.stop:SetPoint("TOPLEFT", PAD, y)
	panel.stop:SetPoint("TOPRIGHT", -PAD, y)
	panel.stop:SetText(StopText(d.bagStop))
	y = y - 24
	panel.go:ClearAllPoints()
	panel.go:SetPoint("TOPLEFT", PAD, y)
	panel.skip:ClearAllPoints()
	panel.skip:SetPoint("TOPRIGHT", -PAD, y)
	panel.skip:SetShown(d.running and true or false)
	if d.running then panel.go:SetPoint("RIGHT", panel.skip, "LEFT", -6, 0)
	else panel.go:SetPoint("TOPRIGHT", -PAD, y) end
	panel.go:SetText(d.running and L["Stop"] or L["Start farming the list"])
	y = y - 28
	-- what it's doing
	local step = d.running and steps and steps[at]
	local text
	if step and step.kind == "empty" then
		text = L["Emptying your bags at %s. It goes on once they have room, or press Next step."]:format(step.to.name or "?")
	elseif step then
		text = L["Farming %s in %s."]:format(step.it.name, step.zone or "?")
	elseif #cur.items == 0 then
		text = L["Add what you want to farm, and how many of each."]
	elseif not (ns.Index and ns.Index.done) then
		text = L["MapSeek is still reading its data."]
	else
		local farms, empties = 0, 0
		for _, s in ipairs(steps or {}) do
			if s.kind == "farm" then farms = farms + 1 else empties = empties + 1 end
		end
		text = farms == 0 and L["You have everything on this list."]
			or empties > 0 and L["The trip from here: %d to farm, %d stops to empty your bags."]:format(farms, empties)
			or L["The trip from here: %d to farm."]:format(farms)
	end
	panel.status:ClearAllPoints()
	panel.status:SetPoint("TOPLEFT", PAD, y)
	panel.status:SetPoint("TOPRIGHT", -PAD, y)
	panel.status:SetText(text)
	y = y - math.max(14, math.ceil(panel.status:GetStringHeight() or 14)) - 8
	panel:SetHeight(-y)
end

function List.Toggle()
	if not panel then Build() end
	if panel:IsShown() then panel:Hide() return end
	-- (opened: the trip from where you are now, when it isn't being ridden)
	if not DB().running then Forget() end
	panel:Show()
	Refresh()
end

function List.Shown() return panel and panel:IsShown() or false end
end

--------------------------------------------------------------------------------
-- Watching the bags; and a list that was being farmed when you logged out, taken up again
--------------------------------------------------------------------------------

local watch = CreateFrame("Frame")
watch:RegisterEvent("BAG_UPDATE_DELAYED")
watch:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(watch.RegisterEvent, watch, "MAIL_CLOSED")
pcall(watch.RegisterEvent, watch, "BANKFRAME_CLOSED")
watch:SetScript("OnEvent", function(_, event)
	if not ns.db then return end
	if event == "PLAYER_ENTERING_WORLD" then
		-- (once the data's read: what was being farmed, on again)
		local tries = 0
		local function Resume()
			local d = ns.db and ns.db.lists
			if not (d and d.running) then return end
			if ns.Index and ns.Index.done then List.Next() return end
			tries = tries + 1
			if tries < 30 then C_Timer.After(2, Resume) end
		end
		C_Timer.After(3, Resume)
		return
	end
	Check(event)
end)
