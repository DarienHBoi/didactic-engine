-- MapSeek: farming loops. "copper farm", "peacebloom route": the zones with the most veins or
-- plants of it, each as a loop through them to ride round and round. A loop picked is followed as
-- a route is (Route.lua), but at its end it starts again, until you stop it.
-- (The loops are worked out here from where the veins and plants grow, as Questie's data has
-- them: no other site's or addon's routes)
local _, ns = ...
local L = ns.L
local Farm = {}
ns.Farm = Farm

local HBD = ns.MapLib and ns.MapLib("HBD", "GetWorldCoordinatesFromZone") or (LibStub and LibStub("HereBeDragons-2.0", true))
local floor, sqrt, max, min, huge = math.floor, math.sqrt, math.max, math.min, math.huge
local find, lower, gsub = string.find, string.lower, string.gsub

local SAME = 15              -- yards: spawns this close are one (the data has a few twice)
local CELL = 150             -- yards: the loop's spots gather the spawns in squares this big ...
local SPOTS_MAX = 60         -- ... made bigger until there are at most this many
local LONELY = 3             -- a spot with one spawn, this many squares from any other: left out
local ZONE_MIN = 8           -- spawns a zone needs for a loop
local ZONE_SHARE = 0.25      -- (and this share of the zone with the most)
local OPTIONS = 5            -- loops offered
-- the zones each faction holds: the other faction's left out (its guards, its towns), unless
-- "the other faction" is on in the settings or there's nowhere else
local HELD = {
	Alliance = { [1429] = true, [1426] = true, [1438] = true, [1439] = true, [1436] = true, [1432] = true,
		[1433] = true, [1431] = true, [1437] = true },
	Horde = { [1411] = true, [1412] = true, [1420] = true, [1421] = true, [1413] = true },
}
local DETOUR = 1.25          -- riding is this much longer than the straight line
local NET_RIDE = 11.2        -- yards a second the terrain's loops were timed at (FarmNet.lua: a 60% mount)
local LAP_YARDS = 6000       -- a lap this long at most (about 9 minutes on a 60% mount) ...
local KILL_SECS = 12         -- seconds a mob farm's mob takes, killed and looted
local CAMPS_MIN = 3          -- (a mob farm's lap: as few camps as this, when they're big)
local SPOTS_MIN = 6          -- ... unless it'd have fewer spots than this

-- the words of a farming search, and the ones that only say what kind it is
local FARM_WORDS = { farm = true, farming = true, farms = true, loop = true, loops = true }
local ROUTE_WORDS = { route = true, routes = true, path = true, run = true }
local KIND_WORDS = { ore = "ore", ores = "ore", mining = "ore", mine = "ore", vein = "ore", veins = "ore",
	deposit = "ore", deposits = "ore", node = true, nodes = true, herb = "herb", herbs = "herb",
	herbalism = "herb", herbing = "herb", bar = "ore", bars = "ore", spot = true, spots = true }
local FILLER = { a = true, an = true, the = true, ["for"] = true, best = true, good = true, me = true,
	show = true, find = true, where = true, is = true, ["to"] = true, ["of"] = true, ["?"] = true }

-- Lockpicking: the boxes a rogue practises on. Each: its objects' ids, the Lockpicking it asks
-- (the least of its ids; and the most, when they differ). Classic's; WoW Forever's may differ
local LOCKS = {
	{ { 178244, 178246 }, 1 },             -- Practice Lockbox (Redridge)
	{ { 123330, 123331, 123333 }, 1 },     -- Buccaneer's Strongbox (off Ratchet)
	{ { 179486, 179488 }, 70, 110 },       -- Battered Footlocker
	{ { 179487, 179489 }, 70, 110 },       -- Waterlogged Footlocker
	{ { 179490 }, 150 },                   -- Battered Footlocker (Badlands)
	{ { 179491 }, 150 },                   -- Waterlogged Footlocker (Desolace)
	{ { 179492 }, 175 },                   -- Dented Footlocker (Badlands)
	{ { 179493 }, 175 },                   -- Mossy Footlocker
	{ { 179494 }, 200 },                   -- Dented Footlocker (Searing Gorge)
	{ { 179496 }, 225 },                   -- Dented Footlocker (Searing Gorge, Tanaris)
	{ { 179497 }, 225 },                   -- Mossy Footlocker (Azshara)
	{ { 179498 }, 250 },                   -- Scarlet Footlocker
}
local LOCK_MIN = 2   -- boxes a zone needs for a loop

-- Waylaid Crates (WoW Forever's): what mobs of a band of levels drop, by tier and what's in them.
-- Each: its tier, its kind, its item's name (lower case)
local CRATE_TIERS = { "apprentice", "journeyman", "expert", "artisan" }
local CRATE_KINDS = { "herbs", "ore", "textiles", "curiosities", "fabrics", "ingots", "parts" }
local CRATE_TIER, CRATE_KIND = {}, { herb = "herbs", ores = "ore", textile = "textiles", curiosity = "curiosities",
	fabric = "fabrics", ingot = "ingots", part = "parts" }
local CRATES = {}
for _, t in ipairs(CRATE_TIERS) do
	CRATE_TIER[t] = t
	for _, k in ipairs(CRATE_KINDS) do
		CRATE_KIND[k] = k
		-- (the higher tiers' herbs come in two crates)
		if k == "herbs" and (t == "expert" or t == "artisan") then
			CRATES[#CRATES + 1] = { tier = t, kind = k, name = "waylaid crate: earthly " .. t .. " herbs" }
			CRATES[#CRATES + 1] = { tier = t, kind = k, name = "waylaid crate: flowering " .. t .. " herbs" }
		else
			CRATES[#CRATES + 1] = { tier = t, kind = k, name = "waylaid crate: " .. t .. " " .. k }
		end
	end
end
-- "quest item farm": the things quests ask for that anyone can sell (a murloc's eye, a page of a
-- book: not a quest's own item, which only drops for those on it)
local QITEM_WORDS = { ["quest item"] = true, ["quest items"] = true, ["questitem"] = true, ["questitems"] = true,
	["hand in"] = true, ["hand ins"] = true, ["handin"] = true, ["handins"] = true, ["hand-in"] = true,
	["hand-ins"] = true, ["turn in"] = true, ["turn ins"] = true, ["turnin"] = true, ["turnins"] = true,
	["quest hand in"] = true, ["quest hand ins"] = true, ["quest turn in"] = true, ["quest turn ins"] = true }
-- "money makers": the farms that might make the most at auction, of every list's. By that name
-- or as "gold makers" ("gold" alone is the ore's)
local GOLD_WORDS = { ["money makers"] = true }
-- (each list, and the kind of farming its rows are: said on a money maker's row)
local GOLD_LISTS = { { "ore", "ore", how = "mine" }, { "herb", "herb", how = "herb" }, { "cloth", how = "mobs" },
	{ "leather", how = "skin" }, { "quest item", how = "mobs" } }
local GOLD_ROWS = 20
local QITEM_TRY, QITEM_ROWS = 120, 20   -- (looked at, the dearest or most asked for; rows shown)
local ITEM_QUEST = 12                  -- (an item's class: a quest's own)
local PICK_MIN = 3     -- spots a zone needs for a loop of something picked up off the ground
local RARE_MIN = 0.05  -- drops a lap a rare thing's loop needs
local LOCK_CORE = { lockpicking = true, lockpick = true, lockpicks = true, footlocker = true, footlockers = true,
	lockbox = true, lockboxes = true }
local LOCK_MORE = { training = true, train = true, level = true, leveling = true, levelling = true, guide = true,
	practice = true, rogue = true, boxes = true, skill = true, up = true, how = true, i = true, ["do"] = true }

--- "copper ore farm" -> "copper"; nil when it isn't a farming search
function Farm.Parse(query)
	local q = lower(query or ""):gsub("[%?!%.,]", " "):gsub("'", "")
	-- ("lockpicking", "lockpicking training", "level lock picking", "footlockers": the boxes a
	-- rogue learns on, with or without "farm")
	do
		local core, lock, pick, other = false, false, false, false
		for w in q:gmatch("%S+") do
			if LOCK_CORE[w] then core = true
			elseif w == "lock" or w == "locks" then lock = true
			elseif w == "pick" or w == "picking" then pick = true
			elseif not (LOCK_MORE[w] or FARM_WORDS[w] or ROUTE_WORDS[w] or FILLER[w]) then other = true end
		end
		if (core or (lock and pick)) and not other then return "lockpicking" end
	end
	-- ("money makers", "money maker", "gold makers", with "farm" or not: the farms that might make the most)
	do
		local money, makers, other = false, false, false
		for w in q:gmatch("%S+") do
			if w == "money" or w == "gold" then money = true
			elseif w == "makers" or w == "maker" or w == "making" then makers = true
			elseif w == "moneymakers" or w == "moneymaker" or w == "goldmakers" or w == "goldmaker" then money, makers = true, true
			elseif not (FARM_WORDS[w] or ROUTE_WORDS[w] or FILLER[w]) then other = true end
		end
		if money and makers and not other then return "money makers" end
	end
	-- ("waylaid crate farm", "waylaid crates", "expert ore crate farm": the crates, by tier and
	-- what's in them)
	do
		local way, crate, tier, ckind, farmed = false, false, nil, nil, false
		for w in q:gmatch("%S+") do
			w = w:gsub(":", "")
			if w == "waylaid" then way = true
			elseif w == "crate" or w == "crates" then crate = true
			elseif CRATE_TIER[w] then tier = w
			elseif CRATE_KIND[w] then ckind = CRATE_KIND[w]
			elseif FARM_WORDS[w] or ROUTE_WORDS[w] then farmed = true end
		end
		if (way and (crate or farmed)) or (crate and tier and farmed) then
			return "waylaid" .. (tier and (" " .. tier) or "") .. (ckind and (" " .. ckind) or "")
		end
	end
	local words, farm, route, kind = {}, false, false, nil
	for w in q:gmatch("%S+") do
		if FARM_WORDS[w] then farm = true
		elseif ROUTE_WORDS[w] then route = true
		elseif KIND_WORDS[w] then if KIND_WORDS[w] ~= true then kind = KIND_WORDS[w] end
		else words[#words + 1] = w end
	end
	-- (small words at either end go, "the best copper", "copper for me"; inside a name they
	-- stay: "essence of water")
	while words[1] and FILLER[words[1]] do table.remove(words, 1) end
	while words[#words] and FILLER[words[#words]] do table.remove(words) end
	-- ("route" alone may be a route somewhere: it's a farm only when the rest names a vein or herb,
	-- Farm.Options says)
	if not (farm or route) then return end
	-- ("ore farm", "herbing route": every ore's, every herb's)
	if #words == 0 then
		if farm and (kind == "ore" or kind == "herb") then return kind, kind end
		return
	end
	return table.concat(words, " "), kind
end

-- Veins and plants you've gathered where the data has none: kept (MapSeekDB.nodes: by the
-- node's name, then the zone's map, { x, y (0..100), 1 } each) and farmed with the data's own.
-- One of a kind the data doesn't have at all gets an id of its own, past the game's
local LEARN_ID = 9000000
local function Learned()
	ns.db.nodes = ns.db.nodes or {}
	ns.db.nodeNames = ns.db.nodeNames or {}
	return ns.db.nodes
end

-- every vein and plant: the data's { id, name }, then the kinds only you have found
local function Gather()
	local list, have = {}, {}
	for i, g in ipairs(ns.Index.gather or {}) do
		list[i] = g
		have[g[2]] = true
	end
	Learned()
	for i, name in ipairs(ns.db.nodeNames) do
		if not have[name] then list[#list + 1] = { LEARN_ID + i, name } end
	end
	return list
end

-- an area of the data's, or a zone's map of your own finds (kept under its map's id, negative)
local function UiFor(areaId)
	if type(areaId) == "number" and areaId < 0 then return -areaId end
	return ns.UiMapFor(areaId)
end

-- the veins or plants of what's named: { { id, name }, ... }, and the name to show
local function Nodes(thing, kind)
	local words = {}
	for w in thing:gmatch("%S+") do words[#words + 1] = (w:gsub("%p", "%%%0")) end
	-- (whole words first: "silver" is Silver Vein, not Silverleaf; failing that, the start of
	-- one: "khadgar" is Khadgar's Whisker)
	for _, ends in ipairs({ "%f[%W]", "" }) do
		local out, title = {}, nil
		for _, g in ipairs(Gather()) do
			local l = lower(g[2]):gsub("'", "")
			local ore = find(l, "%f[%a]vein$") or find(l, "%f[%a]deposit$")
			if not (kind == "ore" and not ore) and not (kind == "herb" and ore) then
				local all = true
				for _, w in ipairs(words) do
					if not find(l .. " ", "%f[%w]" .. w .. ends) then all = false break end
				end
				if all then
					out[#out + 1] = g
					-- (named for the plainest: "Copper Vein", not "Ooze Covered ...")
					if not title or #g[2] < #title then title = g[2] end
				end
			end
		end
		if #out > 0 then return out, title end
	end
	return {}, nil
end

local nameOfNode
local function Spawns(id)
	local ObjDB = ns.Index.ObjectDB and ns.Index.ObjectDB()
	local data = id < LEARN_ID and ObjDB and ns.Index.Spawns(ObjDB, id) or nil
	-- (and your own finds of it, each zone's under its map's id, negative)
	if not nameOfNode then
		nameOfNode = {}
		for _, g in ipairs(ns.Index.gather or {}) do nameOfNode[g[1]] = g[2] end
	end
	local name = id >= LEARN_ID and ns.db.nodeNames and ns.db.nodeNames[id - LEARN_ID] or nameOfNode[id]
	local mine = name and Learned()[name]
	if not mine then return data end
	local out = {}
	for k, v in pairs(data or {}) do out[k] = v end
	for ui, list in pairs(mine) do out[-ui] = list end
	return out
end

local function Speed()
	return ns.Route and ns.Route.GroundSpeed and ns.Route.GroundSpeed() or 7
end

local function Len(a, b) return sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2) end

-- the shortest way round the spots that's easily found: nearest first, then any two crossing
-- legs untangled (2-opt), until none are
local function Tour(spots)
	local n = #spots
	if n < 3 then return spots end
	local left, order = {}, { spots[1] }
	for i = 2, n do left[i - 1] = spots[i] end
	while #left > 0 do
		local last, bi, bd = order[#order], 1, huge
		for i, s in ipairs(left) do
			local d = Len(last, s)
			if d < bd then bi, bd = i, d end
		end
		order[#order + 1] = table.remove(left, bi)
	end
	for _ = 1, 40 do
		local better = false
		for i = 1, n - 2 do
			local a, b = order[i], order[i + 1]
			for j = i + 2, (i == 1) and (n - 1) or n do
				local c, d = order[j], order[j % n + 1]
				if Len(a, c) + Len(b, d) < Len(a, b) + Len(c, d) - 0.5 then
					-- (the legs between turned round)
					local x, y = i + 1, j
					while x < y do order[x], order[y] = order[y], order[x] x, y = x + 1, y - 1 end
					a, b = order[i], order[i + 1]
					better = true
				end
			end
		end
		if not better then break end
	end
	return order
end

-- a zone's spawns as a loop: { ui, spots = { { x, y (0..100), X, Y, n }, ... }, nodes, yards, secs }
local function Loop(ui, pts, again, camp)
	-- (each spawn once: a vein's or plant's. A mob's, each: two may stand together)
	local seen, P = {}, {}
	for _, p in ipairs(pts) do
		local k = floor(p.X / SAME) * 65536 + floor(p.Y / SAME)
		if camp or not seen[k] then seen[k] = true P[#P + 1] = p end
	end
	-- (in squares, made bigger until there are few enough: a mob farm's, its camps)
	local base = camp or CELL
	local cell, cells, list = base, nil, nil
	for _ = 1, 20 do
		cells, list = {}, {}
		for _, p in ipairs(P) do
			local k = floor(p.X / cell) * 65536 + floor(p.Y / cell)
			local c = cells[k]
			if not c then
				c = { X = 0, Y = 0, x = 0, y = 0, n = 0, k = 0, cx = floor(p.X / cell), cy = floor(p.Y / cell) }
				cells[k] = c
				list[#list + 1] = c
			end
			-- (n: what it's worth, a spawn each; a mob's, its chance to drop it. k: how many)
			c.X, c.Y, c.x, c.y = c.X + p.X, c.Y + p.Y, c.x + p.x, c.y + p.y
			c.n, c.k = c.n + (p.w or 1), c.k + 1
			c.pts = c.pts or {}
			c.pts[#c.pts + 1] = p
		end
		if #list <= SPOTS_MAX then break end
		cell = cell * 1.25
	end
	local spots, nodes = {}, 0
	for _, c in ipairs(list) do
		c.X, c.Y, c.x, c.y = c.X / c.k, c.Y / c.k, c.x / c.k, c.y / c.k
	end
	-- (a lone spawn far from the rest isn't worth the ride)
	for _, c in ipairs(list) do
		local keep = c.k > 1
		if not keep then
			for _, o in ipairs(list) do
				if o ~= c and math.abs(o.cx - c.cx) <= LONELY and math.abs(o.cy - c.cy) <= LONELY then keep = true break end
			end
		end
		if keep then
			spots[#spots + 1] = c
			nodes = nodes + c.n
		end
	end
	if #spots < 2 then return end
	spots = Tour(spots)
	local function Around()
		local y = 0
		for i = 1, #spots do y = y + Len(spots[i], spots[i % #spots + 1]) end
		return y * DETOUR
	end
	-- (a mob farm's lap: the killing too, each mob as long as riding this far)
	local kill = camp and KILL_SECS * NET_RIDE or 0
	local function Kills()
		local k = 0
		if camp then for _, c in ipairs(spots) do k = k + c.k end end
		return k
	end
	-- (too long a lap: the spots that cost the most riding (and killing) for what they're worth
	-- left out, one by one, until it's short enough; what's left is where they're thickest)
	local yards = Around()
	local fewest = camp and CAMPS_MIN or SPOTS_MIN
	while yards + Kills() * kill > LAP_YARDS and #spots > fewest do
		local worst, wv = nil, -1
		local n = #spots
		for i = 1, n do
			local a, s, b = spots[(i - 2) % n + 1], spots[i], spots[i % n + 1]
			local v = (Len(a, s) + Len(s, b) - Len(a, b) + s.k * kill) / s.n
			if v > wv then worst, wv = i, v end
		end
		nodes = nodes - spots[worst].n
		table.remove(spots, worst)
		yards = Around()
	end
	-- (the squares were made big for the whole zone: what's left, in small ones again)
	if not again and cell > base * 1.01 then
		local left = {}
		for _, c in ipairs(spots) do for _, p in ipairs(c.pts) do left[#left + 1] = p end end
		local finer = Loop(ui, left, true, camp)
		if finer then return finer end
	end
	if #spots >= 4 then spots = Tour(spots) yards = Around() end   -- (untangled again, with fewer)
	local kills = Kills()
	return { ui = ui, spots = spots, nodes = nodes, yards = yards, kills = kills,
		secs = yards / Speed() + kills * KILL_SECS }
end

local cache = {}   -- thing -> { loops (every zone's that's worth it), title, nodes }

--------------------------------------------------------------------------------
-- Mob farms: an item mobs drop ("linen cloth farm", "large fang farm"): a loop from camp to camp
-- of the mobs that drop it, each camp counted by its mobs' chances to drop it; each hop's way
-- over the ground by the travel network (round cliffs and walls). Mobs friendly to anyone (a
-- town's, a guard), elites and ones well over your level, left out
--------------------------------------------------------------------------------

local CAMP = 120           -- yards: a camp (mobs this close, one)
local DROPS_MIN = 2        -- drops a lap (as chances add up) a zone's loop needs
local RATE_MIN = 3         -- percent: mobs that drop it less often, left out
local RATE_GUESS = 10      -- percent: a mob's, when the item's chances aren't known
-- what skinning gives (lower case, apostrophes gone), the commonest first: "leather farm" lists
-- a loop for each the data has beasts for
local SKINS = { "light leather", "medium leather", "heavy leather", "thick leather", "rugged leather",
	"ruined leather scraps", "light hide", "medium hide", "heavy hide", "thick hide", "rugged hide",
	"deviate scale", "perfect deviate scale", "deviate hide", "thin kodo leather", "raptor hide", "thick wolfhide",
	"shadowcat hide", "turtle scale", "scorpid scale", "heavy scorpid scale", "worn dragonscale",
	"green dragonscale", "blue dragonscale", "red dragonscale", "black dragonscale", "chimera leather",
	"devilsaur leather", "frostsaber leather", "warbear leather", "core leather", "thick yeti hide" }
local SKINNED = {}
for _, n in ipairs(SKINS) do SKINNED[n] = true end
local SKIN_WORDS = { leather = true, leathers = true, skinning = true, skin = true, skins = true, hide = true, hides = true }
-- "cloth farm", "ore farm", "herb farm": each kind's row, in the order you'd learn them
local CLOTHS = { "linen cloth", "wool cloth", "silk cloth", "mageweave cloth", "runecloth", "felcloth" }
local CLOTH_WORDS = { cloth = true, cloths = true, tailoring = true }
local KIND_LISTS = {
	ore = { "copper", "tin", "silver", "iron", "gold", "mithril", "truesilver", "thorium", "dark iron" },
	herb = { "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn", "stranglekelp", "bruiseweed",
		"wild steelbloom", "grave moss", "kingsblood", "liferoot", "fadeleaf", "goldthorn", "khadgars whisker",
		"wintersbite", "firebloom", "purple lotus", "arthas tears", "sungrass", "blindweed", "ghost mushroom",
		"gromsblood", "golden sansam", "dreamfoil", "mountain silversage", "plaguebloom", "icecap", "black lotus" },
}
local SKIN_MOST, SKIN_LEAST = 60, 15   -- percent: what's skinned, from its likeliest beast and its least
local MOB_UNKNOWN = 55      -- the level a mob's taken to be, when the data doesn't say
local MOB_ABOVE = 3        -- levels over yours a mob may be

-- the items of a name (lower case, apostrophes gone)
local function ItemsNamed(l)
	local ids = {}
	for _, id in ipairs(ns.Index.UnsoldIds and ns.Index.UnsoldIds(l) or {}) do ids[#ids + 1] = id end
	for _, it in ipairs(ns.Index.items or {}) do if it.lname == l then ids[#ids + 1] = it.id end end
	return ids
end

-- the mobs that drop an item, and how often: { [npcId] = percent }; and the item's name
local function Droppers(thing, ids)
	local l = lower(thing):gsub("'", "")
	ids = ids or ItemsNamed(l)
	if #ids == 0 then return end
	local skin = SKINNED[l]
	local rates = ns.Search and ns.Search.DropRates and ns.Search.DropRates()
	local ItemDB, NpcDB = ns.Index.ItemDB(), ns.Index.DB()
	local mobs, name = {}, nil
	-- (mobs too high for you: kept aside, offered, with a warning, when there are no others)
	local over, levels = {}, {}
	-- (mobs that seldom drop it: kept aside too, the loop when there's no likelier)
	local rareMobs, rareOver, seen = {}, {}, {}
	local guessed = true   -- (no chances known for any of it)
	local me = UnitLevel("player") or 1
	for _, id in ipairs(ids) do
		local okN, n = pcall(ItemDB.Get, id, "name")
		if okN and type(n) == "string" then name = name or n end
		-- (who drops it: the drop chances' mobs, cloth's among them, which the item's own list
		-- often hasn't; and that list's, where a chance is known)
		local byMob = rates and type(rates[id]) == "table" and rates[id] or {}
		local list = {}
		for npc in pairs(byMob) do list[#list + 1] = npc end
		local okD, own = pcall(ItemDB.Get, id, "npcDrops")
		for _, npc in ipairs(okD and type(own) == "table" and own or {}) do
			if not byMob[npc] then list[#list + 1] = npc end
		end
		-- (no chances known for it at all: its mobs' each counted as a modest one)
		local guess = next(byMob) == nil and RATE_GUESS or nil
		if not guess then guessed = false end
		for _, npc in ipairs(list) do
			local rate = tonumber(byMob[npc]) or guess
			if rate and rate > 0 and not seen[npc] then
				seen[npc] = true
				local low = not skin and rate < RATE_MIN
				local okF, fr = pcall(NpcDB.Get, npc, "friendlyToFaction")
				local okR, rank = pcall(NpcDB.Get, npc, "rank")
				local okL, lo = pcall(NpcDB.Get, npc, "minLevel")
				-- (friendly to your side only: "AH", to both, is the data's word for a yellow beast
				-- you can kill too)
				local mine = ns.faction == "Alliance" and "A" or ns.faction == "Horde" and "H" or nil
				local friendly = okF and mine and fr == mine
				local elite = okR and tonumber(rank) and tonumber(rank) ~= 0
				-- (a level the data doesn't say: taken for a high one, not for one anyone can fight)
				-- (and one the data gives a wide range, 8 to 48: its top, less a little. The low end's a slip)
				local level = okL and tonumber(lo) or MOB_UNKNOWN
				local okH, hi = pcall(NpcDB.Get, npc, "maxLevel")
				if okH and tonumber(hi) and tonumber(hi) - level > 6 then level = tonumber(hi) - 2 end
				if not friendly and not elite then
					local high = level > me + MOB_ABOVE
					if low then
						if high then rareOver[npc] = rate else rareMobs[npc] = rate end
					elseif high then over[npc] = rate else mobs[npc] = rate end
					levels[npc] = level
				end
			end
		end
	end
	local rare = false
	if not next(mobs) and not next(over) then mobs, over, rare = rareMobs, rareOver, true end
	if not next(mobs) and not next(over) then return end
	-- (what's skinned: the chances the data has are of every kill, by anyone, skinner or not, and
	-- so are tiny. Its beasts are the right ones all the same: counted against the likeliest of
	-- them, which a skinner gets it from more often than not)
	if skin then
		-- (the likeliest: nine in ten are no likelier. Not the one odd thing at the top, a target
		-- dummy the data has at 50%)
		local all = {}
		for _, set in ipairs({ mobs, over }) do
			for _, rate in pairs(set) do all[#all + 1] = rate end
		end
		table.sort(all)
		local most = all[max(1, math.ceil(#all * 0.9))] or 0
		for _, set in ipairs({ mobs, over }) do
			for npc, rate in pairs(set) do set[npc] = max(SKIN_LEAST, min(SKIN_MOST, rate / max(most, 0.01) * SKIN_MOST)) end
		end
	end
	-- (the mobs for your level; those too high for you, kept apart; every one's level; and what's
	-- to be said of the loops: rare (seldom dropped), unknown (its chances a guess))
	return mobs, name, over, levels, { item = ids[1], rare = rare or nil, unknown = guessed or nil, least = rare and RARE_MIN or nil,
		rareMobs = not rare and rareMobs or nil, rareOver = not rare and rareOver or nil }
end

-- each zone's loop of a mob farm, from the mobs' spawns
local function MobLoops(mobs, least)
	local NpcDB = ns.Index.DB()
	local byZone, zones, of = {}, {}, {}
	for npc, rate in pairs(mobs) do
		for areaId, list in pairs(ns.Index.Spawns(NpcDB, npc) or {}) do
			local ui = type(list) == "table" and ns.UiMapFor(areaId)
			if ui then
				for _, s in ipairs(list) do
					local x, y = s[1], s[2]
					if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
						local X, Y = HBD:GetWorldCoordinatesFromZone(x / 100, y / 100, ui)
						-- (a spawn in a town of the other faction: not one to ride to)
						if X and not (ns.Route and ns.Route.FoeNear and ns.Route.FoeNear(ui, x, y)) then
							local z = byZone[ui]
							if not z then z = {} byZone[ui] = z zones[#zones + 1] = ui of[ui] = {} end
							z[#z + 1] = { x = x, y = y, X = X, Y = Y, w = rate / 100 }
							of[ui][npc] = rate
						end
					end
				end
			end
		end
	end
	local loops = {}
	for _, ui in ipairs(zones) do
		local loop = Loop(ui, byZone[ui], false, CAMP)
		if loop and loop.nodes >= (least or DROPS_MIN) then
			loop.zone, loop.count, loop.mob, loop.mobs = ns.ZoneName(ui) or "?", #byZone[ui], true, of[ui]
			loop.rate = loop.nodes / max(loop.secs, 60) * 60   -- (drops a minute's riding passes)
			loops[#loops + 1] = loop
		end
	end
	return loops
end

-- a mob farm's hops over the ground (worked out once it's offered: the network's ways)
local function MobWays(loop)
	if loop.legs or not (ns.Route and ns.Route.GroundWay) then return end
	local legs, total, n = {}, 0, #loop.spots
	for i, a in ipairs(loop.spots) do
		local b = loop.spots[i % n + 1]
		local via, secs = ns.Route.GroundWay(loop.ui, a.x, a.y, b.x, b.y)
		secs = secs or Len(a, b) * DETOUR / NET_RIDE
		legs[i] = { secs = secs, via = via or {} }
		total = total + secs
	end
	loop.legs = legs
	loop.yards = total * NET_RIDE
	loop.secs = total * NET_RIDE / Speed() + (loop.kills or 0) * KILL_SECS
	loop.rate = loop.nodes / max(loop.secs, 60) * 60
end

-- a vein's or herb's loops' name in FarmNet.lua: "Small Thorium Vein", "Rich ..." and "Ooze
-- Covered ..." are Thorium Vein's ("thorium vein"). (tools/terrain/farms.py's farm_key: the same)
local PREFIXES = { "small ", "rich ", "poor ", "ooze covered " }
local function FarmKey(name)
	local k = lower(name or ""):gsub("'", "")
	local again = true
	while again do
		again = false
		for _, p in ipairs(PREFIXES) do
			if k:sub(1, #p) == p then k, again = k:sub(#p + 1), true end
		end
	end
	return k
end

-- a lap of spots that crosses itself (one leg over another, as the crow flies)
local function Crosses(spots)
	local n = #spots
	local function Side(a, b, c) return (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X) end
	for i = 1, n - 2 do
		local a, b = spots[i], spots[i + 1]
		for j = i + 2, (i == 1) and (n - 1) or n do
			local c, d = spots[j], spots[j % n + 1]
			if Side(a, b, c) * Side(a, b, d) < 0 and Side(c, d, a) * Side(c, d, b) < 0 then return true end
		end
	end
	return false
end

-- how many times one hop's way runs over the others' (the ways as they're ridden, not as the
-- crow flies)
local function Over(spots, legs, m)
	local n = #spots
	local function Way(i)
		local w = { spots[i] }
		for _, pt in ipairs(legs[i].via) do w[#w + 1] = pt end
		w[#w + 1] = spots[i % n + 1]
		return w
	end
	local function Side(a, b, c) return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) end
	local mine, count = Way(m), 0
	for i = 1, n do
		if i ~= m then
			local w = Way(i)
			for p = 1, #mine - 1 do
				local a, b = mine[p], mine[p + 1]
				for q = 1, #w - 1 do
					local c, d = w[q], w[q + 1]
					if Side(a, b, c) * Side(a, b, d) < 0 and Side(c, d, a) * Side(c, d, b) < 0 then count = count + 1 end
				end
			end
		end
	end
	return count
end

-- the same spots with any two crossing legs untangled (the spots between them turned round),
-- until none cross
local function Untangle(spots)
	local order, n = {}, #spots
	for i, sp in ipairs(spots) do order[i] = sp end
	for _ = 1, 40 do
		local better = false
		for i = 1, n - 2 do
			local a, b = order[i], order[i + 1]
			for j = i + 2, (i == 1) and (n - 1) or n do
				local c, d = order[j], order[j % n + 1]
				if Len(a, c) + Len(b, d) < Len(a, b) + Len(c, d) - 0.5 then
					local x, y = i + 1, j
					while x < y do order[x], order[y] = order[y], order[x] x, y = x + 1, y - 1 end
					a, b = order[i], order[i + 1]
					better = true
				end
			end
		end
		if not better then break end
	end
	return order
end

-- a lap's hops for a new order of its spots: a hop kept as it was, or turned round, keeps its
-- way; a new one gets the network's. (spots, legs: as they were.) The legs, and their seconds
local function Relink(ui, order, spots, legs)
	local nextOf = {}
	for i, sp in ipairs(spots) do nextOf[sp] = { spots[i % #spots + 1], legs[i] } end
	local legs2, total = {}, 0
	for i, a in ipairs(order) do
		local b = order[i % #order + 1]
		local na, nb = nextOf[a], nextOf[b]
		local leg
		if na and na[1] == b then
			leg = na[2]
		elseif nb and nb[1] == a then
			local old, via = nb[2], {}
			for k = #old.via, 1, -1 do via[#via + 1] = old.via[k] end
			leg = { secs = old.secs, via = via }
		else
			local via, secs = nil, nil
			if ns.Route and ns.Route.GroundWay then via, secs = ns.Route.GroundWay(ui, a.x, a.y, b.x, b.y) end
			leg = { secs = secs or Len(a, b) * DETOUR / NET_RIDE, via = via or {} }
		end
		legs2[i] = leg
		total = total + leg.secs
	end
	return legs2, total
end

local DEAD_SECS = 60       -- a ride round a town this long (a 60% mount), with nothing on it: the lap's cut there
local SMALL_SPOTS = 4      -- spots, at least, to a half that's kept
local SMALL_NODES = 8      -- and veins or herbs
local SMALL_SHARE = 0.4    -- and this much of the whole lap's
local SMALL_GAIN = 1.1     -- times the whole lap's a minute, at least
local LEARN_APART = 80     -- yards: a find of yours this near a spot of the loop is that spot

-- a loop worked out over the terrain (FarmNet.lua): its spots, each on a spawn, and each hop's
-- way from one to the next, round cliffs and over what can be ridden. nil: none to read
local function Baked(ui, b, pts)
	if not (b and b.spots and b.hops) then return end
	local spots, nodes = {}, 0
	for x, y, n in b.spots:gmatch("(-?[%d%.]+),(-?[%d%.]+),(%d+)") do
		x, y, n = tonumber(x), tonumber(y), tonumber(n)
		local X, Y = HBD:GetWorldCoordinatesFromZone(x / 100, y / 100, ui)
		if not X then return end
		spots[#spots + 1] = { x = x, y = y, n = n, X = X, Y = Y }
		nodes = nodes + n
	end
	local legs, total = {}, 0
	for h in b.hops:gmatch("[^;]+") do
		local f = {}
		for v in h:gmatch("-?[%d%.]+") do f[#f + 1] = tonumber(v) end
		local via = {}
		for k = 2, #f - 1, 2 do via[#via + 1] = { ui = ui, x = f[k], y = f[k + 1] } end
		legs[#legs + 1] = { secs = f[1] or 0, via = via }
		total = total + (f[1] or 0)
	end
	if #spots < 2 or #legs ~= #spots then return end
	local altered = false
	-- (the other faction's towns: their spots left out, and a hop through one gone round, by the
	-- network's way)
	local Foe = ns.Route and ns.Route.FoeNear
	if Foe then
		local kept, changed = {}, false
		for i, sp in ipairs(spots) do
			if Foe(ui, sp.x, sp.y) then changed = true else kept[#kept + 1] = i end
		end
		local dirty = {}
		for i, leg in ipairs(legs) do
			for _, pt in ipairs(leg.via) do
				if Foe(ui, pt.x, pt.y) then dirty[i], changed = true, true break end
			end
		end
		if changed then
			altered = true
			if #kept < 2 then return end
			local spots2, legs2, chains = {}, {}, {}
			nodes, total = 0, 0
			for m, i in ipairs(kept) do
				local j = kept[m % #kept + 1]
				local a, b = spots[i], spots[j]
				local leg = (j == i % #spots + 1 and not dirty[i]) and legs[i] or nil
				if not leg and ns.Route.RoundTowns then
					-- (the loop's own way from the one to the other, through the spots left out, with
					-- what's in the town taken round its edge)
					local chain, k = { a }, i
					repeat
						for _, pt in ipairs(legs[k].via) do chain[#chain + 1] = pt end
						k = k % #spots + 1
						chain[#chain + 1] = spots[k]
					until k == j
					local via, yards = ns.Route.RoundTowns(ui, chain)
					if via then leg = { secs = yards / NET_RIDE, via = via } end
					chains[m] = chain
				end
				if not leg then
					local via, secs = ns.Route.GroundWay(ui, a.x, a.y, b.x, b.y)
					leg = { secs = secs or Len(a, b) / NET_RIDE, via = via or {} }
				end
				spots2[m], legs2[m] = a, leg
				nodes = nodes + a.n
				total = total + leg.secs
			end
			spots, legs = spots2, legs2
			-- (a way round a town that runs over the rest of the lap: the town's other side, or the
			-- network's way, when that runs over less of it)
			for m, chain in pairs(chains) do
				local over = Over(spots, legs, m)
				if over > 0 then
					local was = legs[m]
					local best, least = was, over
					local a, b = spots[m], spots[m % #spots + 1]
					local via, yards = ns.Route.RoundTowns(ui, chain, true)
					local v2, s2 = ns.Route.GroundWay(ui, a.x, a.y, b.x, b.y)
					for _, try in ipairs({ via and { secs = yards / NET_RIDE, via = via } or false,
						v2 and { secs = s2, via = v2 } or false }) do
						if try then
							legs[m] = try
							local o = Over(spots, legs, m)
							if o < least then best, least = try, o end
						end
					end
					legs[m] = best
					total = total - was.secs + best.secs
				end
			end
			-- (a long ride round a town with nothing to gather on it: the lap cut in two there, and
			-- the half kept that passes more a minute, when it's clearly more than the whole lap's)
			local long
			for m in pairs(chains) do
				if legs[m].secs >= DEAD_SECS and (not long or legs[m].secs > legs[long].secs) then long = m end
			end
			local n = #spots
			if long and n >= SMALL_SPOTS * 2 then
				local function At(t) return (long + t - 1) % n + 1 end   -- (the lap, from after the long ride)
				local accN, accS, sN, sS = {}, {}, 0, 0
				for t = 1, n do
					local i = At(t)
					sN = sN + spots[i].n
					accN[t], accS[t] = sN, sS
					if t < n then sS = sS + legs[i].secs end
				end
				local function Est(a, b) return Len(spots[a], spots[b]) * DETOUR / NET_RIDE end
				local need = max(SMALL_NODES, sN * SMALL_SHARE)
				local cands = {}
				for c = SMALL_SPOTS, n - SMALL_SPOTS do
					-- (the lap's first c spots, and the rest: each closed from its last to its first)
					local nA, sA = accN[c], accS[c] + Est(At(c), At(1))
					local nB, sB = sN - accN[c], accS[n] - accS[c + 1] + Est(At(n), At(c + 1))
					if nA >= need then cands[#cands + 1] = { 1, c, nA / sA } end
					if nB >= need then cands[#cands + 1] = { c + 1, n, nB / sB } end
				end
				table.sort(cands, function(a, b) return a[3] > b[3] end)
				local bestRate, pick = nodes / total * SMALL_GAIN, nil
				for k = 1, min(#cands, 4) do
					local c = cands[k]
					local sp, lg, nn, tt = {}, {}, 0, 0
					for t = c[1], c[2] do
						local i = At(t)
						sp[#sp + 1] = spots[i]
						nn = nn + spots[i].n
						if t < c[2] then lg[#lg + 1] = legs[i] tt = tt + legs[i].secs end
					end
					local a, b = sp[#sp], sp[1]
					local via, secs = ns.Route.GroundWay(ui, a.x, a.y, b.x, b.y)
					lg[#sp] = { secs = secs or Len(a, b) * DETOUR / NET_RIDE, via = via or {} }
					tt = tt + lg[#sp].secs
					if nn / tt > bestRate and Over(sp, lg, #sp) == 0 then
						bestRate, pick = nn / tt, { sp, lg, nn, tt }
					end
				end
				if pick then spots, legs, nodes, total = pick[1], pick[2], pick[3], pick[4] end
			end
		end
	end
	-- (your own finds in the zone, not on the loop: each put in where it adds the least riding)
	local found = {}
	for _, p in ipairs(pts or {}) do
		if p.learned then
			local near = false
			for _, sp in ipairs(spots) do if Len(sp, p) <= LEARN_APART then near = true break end end
			for _, q in ipairs(found) do if Len(q, p) <= LEARN_APART then near = true break end end
			if not near then found[#found + 1] = { x = p.x, y = p.y, X = p.X, Y = p.Y, n = 1, learned = true } end
		end
	end
	if #found > 0 then
		altered = true
		local order = {}
		for i, sp in ipairs(spots) do order[i] = sp end
		for _, f in ipairs(found) do
			local at, least = 1, huge
			for i = 1, #order do
				local a, c = order[i], order[i % #order + 1]
				local more = Len(a, f) + Len(f, c) - Len(a, c)
				if more < least then at, least = i, more end
			end
			table.insert(order, at + 1, f)
			nodes = nodes + 1
		end
		legs, total = Relink(ui, order, spots, legs)
		spots = order
	end
	-- (a lap that's been changed here (a town's spots left out, finds of yours put in) and runs
	-- over itself: untangled, when the new lap's ways run over each other less than the old's.
	-- One as it was worked out over the terrain is left alone: its ways go round what the crow
	-- flies over)
	if altered and #spots >= 4 and Crosses(spots) then
		local function Tangles(sp, lg)
			local c = 0
			for m = 1, #sp do c = c + Over(sp, lg, m) end
			return c
		end
		local order = Untangle(spots)
		local legs2, total2 = Relink(ui, order, spots, legs)
		if Tangles(order, legs2) < Tangles(spots, legs) then spots, legs, total = order, legs2, total2 end
	end
	return { ui = ui, spots = spots, legs = legs, nodes = nodes, yards = total * NET_RIDE,
		secs = total * NET_RIDE / Speed(), terrain = true }
end

-- the zone you're in (its zone map, not a town's or a cave's)
local function HereZone()
	local here = ns.PlayerMap and ns.PlayerMap()
	for _ = 1, 5 do
		local info = here and C_Map.GetMapInfo(here)
		if not info then return end
		if info.mapType == 3 then return here end
		here = info.parentMapID
	end
end

-- of a farm's loops, the ones to offer: the zone you're in first, then your side's zones (the
-- other's after them, when they're offered), the most a minute's riding passes first
local function Offer(loops)
	local theirs = HELD[ns.faction == "Horde" and "Alliance" or "Horde"]
	local here = HereZone()
	-- (enough of it to be worth a loop: a share of the most any zone of your side has, the zone
	-- you're in whatever)
	local mine, most = {}, 0
	for _, l in ipairs(loops) do
		if ns.db.otherFaction or not theirs[l.ui] then mine[#mine + 1] = l most = max(most, l.count) end
	end
	if #mine == 0 then
		for _, l in ipairs(loops) do mine[#mine + 1] = l most = max(most, l.count) end
	end
	local need = min(most, max(ZONE_MIN, most * ZONE_SHARE))
	local list = {}
	for _, l in ipairs(mine) do
		if l.count >= need or l.ui == here then list[#list + 1] = l end
	end
	-- (the other faction's, when they're offered at all, after all of your side's)
	table.sort(list, function(a, b)
		if (a.ui == here) ~= (b.ui == here) then return a.ui == here end
		if (theirs[a.ui] or false) ~= (theirs[b.ui] or false) then return not theirs[a.ui] end
		if a.rate ~= b.rate then return a.rate > b.rate end
		return a.ui < b.ui
	end)
	local out = {}
	for i = 1, math.min(OPTIONS, #list) do out[i] = list[i] end
	return out
end

--- the loops for a farming search, the best first: { { ui, zone, spots, nodes, secs, ... }, ... },
--- what's farmed ("Copper Vein"), and the veins or plants' ids. nil when there's nothing of it
--------------------------------------------------------------------------------
-- Two or three things farmed together ("copper and tin farm"): one loop a zone through the
-- spawns of them all, its hops by the travel network's ways, and how much of it is each (by its
-- spawns). And a zone's farms ("hillsbrad farm", "hillsbrad ore farm"): every vein and herb with
-- enough spawns there for a loop, the most a minute's riding passes first
--------------------------------------------------------------------------------

local MIX_MAX = 3          -- things farmed together at most
local MIX_SHARE = 5        -- percent of a loop's spawns a thing needs to count as part of it

-- a zone's spawns of some veins or plants ({ { id, name }, ... }), each tagged
local function ZonePoints(nodes, tag, into, only)
	for _, g in ipairs(nodes) do
		for areaId, list in pairs(Spawns(g[1]) or {}) do
			local ui = type(list) == "table" and UiFor(areaId)
			if ui and (not only or ui == only) then
				for _, s in ipairs(list) do
					local x, y = s[1], s[2]
					if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
						local X, Y = HBD:GetWorldCoordinatesFromZone(x / 100, y / 100, ui)
						if X and not (ns.Route and ns.Route.FoeNear and ns.Route.FoeNear(ui, x, y)) then
							into[ui] = into[ui] or {}
							tinsert(into[ui], { x = x, y = y, X = X, Y = Y, tag = tag, learned = s[3] == 1 })
						end
					end
				end
			end
		end
	end
end

-- "copper and tin", "copper, tin & iron": the things named, or nil when it's one
local function Parts(thing)
	local t = (" " .. thing .. " "):gsub(" and ", "|"):gsub("&", "|"):gsub("%+", "|"):gsub(",", "|")
	local parts = {}
	for part in t:gmatch("[^|]+") do
		part = strtrim(part)
		if part ~= "" then parts[#parts + 1] = part end
	end
	if #parts >= 2 and #parts <= MIX_MAX then return parts end
end

local function Mixed(parts, kind)
	local groups, all = {}, {}
	for i, part in ipairs(parts) do
		local nodes, title = Nodes(part, kind)
		if #nodes == 0 then return end
		-- (as a farm of it alone: its own kinds, "iron" not Dark Iron's)
		local fkey, mine = FarmKey(title), {}
		for _, g in ipairs(nodes) do if FarmKey(g[2]) == fkey then mine[#mine + 1] = g end end
		if #mine > 0 then nodes = mine end
		groups[i] = { nodes = nodes, title = title }
		for _, g in ipairs(nodes) do all[#all + 1] = g end
	end
	local byZone = {}
	for i, g in ipairs(groups) do ZonePoints(g.nodes, i, byZone) end
	local options, names = {}, {}
	for i, g in ipairs(groups) do names[i] = g.title end
	for ui, pts in pairs(byZone) do
		if #pts >= ZONE_MIN then
			local loop = Loop(ui, pts)
			if loop and loop.nodes >= ZONE_MIN then
				local count, total = {}, 0
				for _, c in ipairs(loop.spots) do
					for _, p in ipairs(c.pts or {}) do
						count[p.tag] = (count[p.tag] or 0) + 1
						total = total + 1
					end
				end
				for _, c in ipairs(loop.spots) do c.pts = nil end   -- (counted: not kept)
				local mix, text, kinds = {}, {}, 0
				for i, g in ipairs(groups) do
					local pct = total > 0 and floor((count[i] or 0) / total * 100 + 0.5) or 0
					mix[i] = { title = g.title, pct = pct }
					if pct >= MIX_SHARE then
						kinds = kinds + 1
						text[#text + 1] = ("%d%% %s"):format(pct, g.title)
					end
				end
				-- (a zone with one of them alone isn't the two together: that's its own farm)
				if kinds >= 2 then
					loop.zone, loop.count = ns.ZoneName(ui) or "?", #pts
					loop.ways, loop.mix, loop.mixText = true, mix, table.concat(text, ", ")
					loop.rate = loop.nodes / max(loop.secs, 60) * 60
					options[#options + 1] = loop
				end
			end
		end
	end
	if #options == 0 then return end
	return options, table.concat(names, " + "), all
end

-- the zone a farming search names: in full or by its short name ("stv"), else the one zone whose
-- name starts with it or has a word that does ("hillsbrad": the Foothills, not the town of the
-- same name, nor Hillsbrad Fields)
local function ZoneNamed(thing)
	local S = ns.Search
	if not (S and S.Place and S.Places) then return end
	local p = S.Place(thing)
	if p and p.kind == "zone" then return p end
	local q = lower(thing):gsub("^the ", "")
	local found
	for _, z in ipairs(S.Places()) do
		if z.kind == "zone" then
			local l = lower(z.name):gsub("'", "")
			if l:sub(1, #q) == q or find(l, " " .. q, 1, true) then
				if found and found ~= z then return end
				found = z
			end
		end
	end
	return found
end

-- a zone's farms: each vein and herb with a loop there
local function ZoneFarms(ui, kind)
	local groups, order = {}, {}
	for _, g in ipairs(Gather()) do
		local l = lower(g[2])
		local ore = find(l, "%f[%a]vein$") or find(l, "%f[%a]deposit$")
		if not (kind == "ore" and not ore) and not (kind == "herb" and ore) then
			local fkey = FarmKey(g[2])
			local grp = groups[fkey]
			if not grp then
				grp = { key = fkey, nodes = {}, title = g[2] }
				groups[fkey] = grp
				order[#order + 1] = grp
			end
			grp.nodes[#grp.nodes + 1] = g
			if #g[2] < #grp.title then grp.title = g[2] end
		end
	end
	local options = {}
	for _, grp in ipairs(order) do
		local byZone = {}
		ZonePoints(grp.nodes, 1, byZone, ui)   -- (that zone's alone: not every spawn in the world, for each)
		local pts = byZone[ui]
		if pts and #pts >= ZONE_MIN then
			local baked = ns.FARM_NET and ns.FARM_NET[grp.key]
			local loop = baked and baked[ui] and Baked(ui, baked[ui], pts) or Loop(ui, pts)
			if loop and loop.nodes >= ZONE_MIN then
				loop.zone, loop.count = ns.ZoneName(ui) or "?", #pts
				loop.title, loop.own, loop.label = grp.title, grp.nodes, grp.title
				loop.rate = loop.nodes / max(loop.secs, 60) * 60
				options[#options + 1] = loop
			end
		end
	end
	if #options == 0 then return end
	table.sort(options, function(a, b) if a.rate ~= b.rate then return a.rate > b.rate end return a.title < b.title end)
	return options
end

-- a mob farm's loops to offer: those for your level first; then, to plan ahead, a few of those
-- only mobs too high for you are in (in zones not offered already), the lowest first. Each with
-- its mobs' lowest level (lo)
local HIGH_EXTRA = 3
local MobOffer
MobOffer = function(mobs, over, levels, say)
	say = say or {}
	local function Lowest(l)
		local lo = huge
		for npc in pairs(l.mobs or {}) do lo = min(lo, levels[npc] or MOB_UNKNOWN) end
		l.lo = lo < huge and lo or MOB_UNKNOWN
	end
	local out, seen = {}, {}
	if next(mobs) then
		for _, l in ipairs(Offer(MobLoops(mobs, say.least))) do Lowest(l) out[#out + 1] = l seen[l.ui] = true end
	end
	if next(over) then
		local hi = Offer(MobLoops(over, say.least))
		for _, l in ipairs(hi) do Lowest(l) end
		table.sort(hi, function(a, b)
			if a.lo ~= b.lo then return a.lo < b.lo end
			return a.rate > b.rate
		end)
		local n = 0
		for _, l in ipairs(hi) do
			if not seen[l.ui] and n < HIGH_EXTRA then out[#out + 1] = l n = n + 1 end
		end
	end
	-- (no loop with enough of it: with the mobs that seldom drop it too, as a rare thing's)
	if #out == 0 and not say.rare and (say.rareMobs or say.rareOver) then
		local m2, o2 = {}, {}
		for npc, rate in pairs(mobs) do m2[npc] = rate end
		for npc, rate in pairs(say.rareMobs or {}) do m2[npc] = rate end
		for npc, rate in pairs(over) do o2[npc] = rate end
		for npc, rate in pairs(say.rareOver or {}) do o2[npc] = rate end
		return MobOffer(m2, o2, levels, { item = say.item, rare = true, unknown = say.unknown, least = RARE_MIN })
	end
	for _, l in ipairs(out) do l.rare, l.unknown, l.item = say.rare, say.unknown, say.item end
	return out
end

local Options   -- (below)
--- the loops for a farming search: { loops }, the title, the veins or plants. A zone named with
--- the things ("hillsbrad copper tin", "copper and tin in hillsbrad"): that zone's loop alone
local lastAsked
--- the loops worked out, let go (the map's been closed a while)
function Farm.Release()
	wipe(cache)
	lastAsked = nil
end

-- each loop too high for you, said (high: the level): a mob farm's by its mobs' lowest level;
-- a vein's or herb's by the zone's
local function Mark(opts)
	local most = (UnitLevel("player") or 1) + MOB_ABOVE
	for _, o in ipairs(opts) do
		local lo = o.lo
		if not lo and not o.mob and ns.Route and ns.Route.ZoneMin then lo = ns.Route.ZoneMin(o.ui) end
		o.high = lo and lo > most and lo or nil
	end
	return opts
end

-- a list of things' rows: those for your level first, as they were; then the ones too high for
-- you, the lowest first
local function ForYouFirst(loops)
	Mark(loops)
	local mine, later = {}, {}
	for _, l in ipairs(loops) do tinsert(l.high and later or mine, l) end
	table.sort(later, function(a, b) return a.high < b.high end)
	wipe(loops)
	for _, l in ipairs(mine) do loops[#loops + 1] = l end
	for _, l in ipairs(later) do loops[#loops + 1] = l end
end

--------------------------------------------------------------------------------
-- What a farm might make: its item's price at auction (TradeSkillMaster's, else Auctionator's or
-- Auctioneer's, whichever is there), by how much of it an hour's laps would bring
--------------------------------------------------------------------------------
do
local NODE_UP = 0.3      -- the share of a vein's or herb's spawn points that have one at a time
local LAPS_MOST = 10     -- laps an hour at most that count: what's taken needs time to come back
local PRICE_KEEP = 300   -- seconds a price read is kept
local prices = {}        -- [itemId] = { low, high, at }

-- an item's price at auction, in copper: the least it's likely to go for, and the most; nil
-- when no addon knows
local function Price(id)
	local now = GetTime and GetTime() or 0
	local c = prices[id]
	if c and now - c[3] < PRICE_KEEP then return c[1] or nil, c[2] or nil end
	local got = {}
	local function Put(v) if type(v) == "number" and v > 0 then got[#got + 1] = v end end
	local T = _G.TSM_API
	if T and T.GetCustomPriceValue then
		for _, src in ipairs({ "dbminbuyout", "dbmarket" }) do
			local ok, v = pcall(T.GetCustomPriceValue, src, "i:" .. id)
			if ok then Put(v) end
		end
	end
	if #got == 0 then
		local A = _G.Auctionator and Auctionator.API and Auctionator.API.v1
		if A and A.GetAuctionPriceByItemID then
			local ok, v = pcall(A.GetAuctionPriceByItemID, "MapSeek", id)
			if ok then Put(v) end
		end
	end
	if #got == 0 then
		local A = _G.AucAdvanced and AucAdvanced.API
		local info = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
		local link
		if info then local ok, _, l = pcall(info, id) link = ok and l or nil end
		if A and A.GetMarketValue and link then
			local ok, v = pcall(A.GetMarketValue, link)
			if ok then Put(v) end
		end
	end
	local low, high
	for _, v in ipairs(got) do low, high = min(low or v, v), max(high or v, v) end
	prices[id] = { low or false, high or false, now }
	return low, high
end

Farm.Price = Price

--- what an hour of a loop might bring at auction, in copper: the least and the most; nil when
--- its item has no price, or how often it drops isn't known
function Farm.Worth(o, title)
	if o.lock or o.unknown or o.mix then return end
	local id = o.item
	if not id and not o.mob then id = Farm.ItemOf(o.title or title) end
	if not id then return end
	local low, high = Price(id)
	if not low then return end
	local lap = o.mob and o.nodes or o.nodes * NODE_UP
	local laps = min(3600 / max(o.secs or 60, 60), LAPS_MOST)
	return floor(low * lap * laps), floor(high * lap * laps)
end
end

--- a search that's a list of farms (every cloth's, every crate's, the gold farms), not worked out
--- yet: its name. Those take a moment, and so wait for Enter. nil: not one, or worked out already
function Farm.Slow(thing, kind)
	if not thing or cache[thing .. "|" .. tostring(kind)] then return end
	if thing == "waylaid" or thing:sub(1, 8) == "waylaid " then return L["Waylaid Crates"] end
	if kind then return KIND_LISTS[thing] and kind == thing and (thing == "ore" and L["Ore farms"] or L["Herb farms"]) or nil end
	if SKIN_WORDS[thing] then return L["Leather farms"] end
	if CLOTH_WORDS[thing] then return L["Cloth farms"] end
	if QITEM_WORDS[thing] then return L["Quest items to sell"] end
	-- (the money makers need prices)
	if GOLD_WORDS[thing] and (_G.TSM_API or _G.Auctionator or _G.AucAdvanced) then return L["Money makers"] end
end

--- an item by its name, as typed: its id, and its name as the data has it; nil when there's none
function Farm.ItemNamed(name)
	local l = lower(strtrim(name or "")):gsub("'", "")
	if l == "" or not (ns.Index and ns.Index.done) then return end
	local id = ItemsNamed(l)[1]
	if not id then return end
	local ItemDB = ns.Index.ItemDB()
	local ok, n = pcall(ItemDB.Get, id, "name")
	return id, ok and type(n) == "string" and n or strtrim(name)
end

--- an item by part of its name, as "<it> farm" is typed in the search: "copper" the ore, "linen"
--- the cloth, "scorpid scale" whichever scale there's a farm for. Its id and name; nil when none
local LIKE_ENDS = { " ore", " cloth", " leather", " hide", " scale" }
local LIKE_TRY = 6
function Farm.ItemLike(text)
	local l = lower(strtrim(text or "")):gsub("'", "")
	if l == "" or not (ns.Index and ns.Index.done) then return end
	local id, name = Farm.ItemNamed(l)
	if id then return id, name end
	for _, tail in ipairs(LIKE_ENDS) do
		id, name = Farm.ItemNamed(l .. tail)
		if id then return id, name end
	end
	-- (every word typed the start of one of the name's: the shortest such names, and of those the
	-- first there's a farm for)
	local words = {}
	for w in l:gmatch("%S+") do words[#words + 1] = w end
	local found, seen = {}, {}
	for _, it in ipairs(ns.Index.items or {}) do
		local n = it.lname
		if type(n) == "string" and not seen[n] then
			local all = true
			for _, w in ipairs(words) do
				if not (n:sub(1, #w) == w or n:find(" " .. w, 1, true)) then all = false break end
			end
			if all then
				seen[n] = true
				found[#found + 1] = n
			end
		end
	end
	table.sort(found, function(x, y)
		local sx, sy = x:sub(1, #l) == l, y:sub(1, #l) == l
		if sx ~= sy then return sx end
		if #x ~= #y then return #x < #y end
		return x < y
	end)
	for i = 1, math.min(LIKE_TRY, #found) do
		local ok, opts = pcall(Farm.Options, found[i], nil)
		if ok and opts and opts[1] and not opts[1].more then return Farm.ItemNamed(found[i]) end
	end
end

--- your Lockpicking, or nil (not a rogue, or not learned)
function Farm.LockSkill()
	if not (GetNumSkillLines and GetSkillLineInfo) then return end
	for i = 1, GetNumSkillLines() do
		local name, header, _, rank = GetSkillLineInfo(i)
		if not header and (name == L["Lockpicking"] or name == "Lockpicking") then return tonumber(rank) end
	end
end

--------------------------------------------------------------------------------
-- A list of farms (the money makers, every ore's, every herb's) is every loop of every thing in
-- it worked out, for a row of each: a second or two, and a hundred MB let go on the way. So it's
-- worked out a little each frame, the game going on, and the collector kept up with it
--------------------------------------------------------------------------------

Farm.SLICE_MS = 6      -- of working out a frame, about (a frame at 60 a second is 16)
Farm.SLICE_GC = 400    -- the collector's step after each: enough to keep up with what's let go

--- between two things of a list being worked out (Farm.Work): the frame's had its share, so the
--- rest waits for the next. Nothing, called any other time
function Farm.Breathe()
	local job = Farm.job
	if not (job and coroutine.running() == job.co) then return end
	if not debugprofilestop or debugprofilestop() - job.t0 >= Farm.SLICE_MS then coroutine.yield() end
end

--- how far a list being worked out has got: thing i of its n is next. whole: the list is one of
--- lists (the money makers': ore, herbs, cloth...), each a share of the whole; else the things
--- of the list being gone through, a share of its list's share
function Farm.At(i, n, whole)
	local job = Farm.job
	if not (job and n and n > 0 and coroutine.running() == job.co) then return end
	if whole then
		job.from, job.span = (i - 1) / n, 1 / n
		job.frac = job.from
	else
		job.frac = (job.from or 0) + (job.span or 1) * (i - 1) / n
	end
end

--- whether a list is being worked out now (this one, when named)
function Farm.Working(thing, kind)
	local job = Farm.job
	return job ~= nil and (not thing or job.key == thing .. "|" .. tostring(kind))
end

--- work out the loops for a farming search over the frames to come, then call done() (the loops
--- are there for Farm.Options to give at once). Another asked for meanwhile: this one's dropped.
--- tick(how far, 0 to 1): called each frame on the way
function Farm.Work(thing, kind, done, tick)
	local me = { key = thing .. "|" .. tostring(kind), frac = 0 }
	me.co = coroutine.create(function() Farm.Options(thing, kind) end)
	Farm.job = me
	local function Step()
		if Farm.job ~= me then return end
		me.t0 = debugprofilestop and debugprofilestop() or 0
		local ok, err = coroutine.resume(me.co)
		if coroutine.status(me.co) == "dead" then
			Farm.job = nil
			if not ok and geterrorhandler then geterrorhandler()(err) end
			if ns.Sweep then ns.Sweep() end
			done()
		else
			collectgarbage("step", Farm.SLICE_GC)
			if tick then tick(me.frac or 0) end   -- (how far it's got, 0 to 1: a bar of it)
			C_Timer.After(0, Step)
		end
	end
	C_Timer.After(0, Step)
end

function Farm.Options(thing, kind)
	-- (another thing asked for than the last: the last one's loops let go. Each farm's are a few
	-- megabytes, every zone's; the one being ridden is the route's own, kept by it)
	local asked = thing .. "|" .. tostring(kind)
	if asked ~= lastAsked then
		wipe(cache)
		lastAsked = asked
	end
	local opts, title, nodes = Options(thing, kind)
	if opts then return Mark(opts), title, nodes end
	local words = {}
	for w in thing:gmatch("%S+") do if w ~= "in" then words[#words + 1] = w end end
	for n = math.min(3, #words - 1), 1, -1 do
		for _, front in ipairs({ true, false }) do
			local zw, rest = {}, {}
			for i, w in ipairs(words) do
				local inZone = front and i <= n or (not front and i > #words - n)
				tinsert(inZone and zw or rest, w)
			end
			local zone = ZoneNamed(table.concat(zw, " "))
			if zone and #rest > 0 then
				-- (what's left: one thing; else each word one, "copper tin")
				local tries = { table.concat(rest, " ") }
				if #rest >= 2 and not tries[1]:find("[&,+]") and not tries[1]:find(" and ", 1, true) then
					tries[2] = table.concat(rest, " and ")
				end
				for _, t in ipairs(tries) do
					local _, t2, n2 = Options(t, kind)
					local c = cache[t .. "|" .. tostring(kind)]
					local only = {}
					for _, o in ipairs(c and c.loops or {}) do if o.ui == zone.id then only[#only + 1] = o end end
					if #only > 0 then return Mark(only), t2, n2 end
				end
			end
		end
	end
end

Options = function(thing, kind)
	if not (HBD and HBD.GetWorldCoordinatesFromZone and ns.Index.done) then return end
	Farm.Breathe(thing)   -- (a list being worked out over frames: between its things)
	local key = thing .. "|" .. tostring(kind)
	local c = cache[key]
	if c then return c.asIs and c.loops or Offer(c.loops), c.title, c.nodes end
	-- ("money makers": every list's rows, ore, herbs, cloth, leather, quest items, the ones an
	-- hour of might make the most at auction first. Only with prices)
	if GOLD_WORDS[thing] and not kind then
		local rows, seen = {}, {}
		for li, lst in ipairs(GOLD_LISTS) do
			Farm.At(li, #GOLD_LISTS, true)
			local sub = Options(lst[1], lst[2])
			cache[lst[1] .. "|" .. tostring(lst[2])] = nil
			for _, o in ipairs(sub or {}) do
				local _, worth = Farm.Worth(o, o.title)
				if worth and worth > 0 and not seen[o.title] then
					seen[o.title] = true
					o.worth, o.how = worth, lst.how
					rows[#rows + 1] = o
				end
			end
		end
		if #rows > 0 then
			table.sort(rows, function(a, b)
				if a.worth ~= b.worth then return a.worth > b.worth end
				return a.label < b.label
			end)
			-- (those for your level first, the best of them; then what's too high yet)
			ForYouFirst(rows)
			for i = #rows, GOLD_ROWS + 1, -1 do rows[i] = nil end
			local gtitle = L["Money makers"]
			cache[key] = { loops = rows, title = gtitle, nodes = {}, asIs = true }
			return rows, gtitle, {}
		end
		return
	end
	-- ("quest item farm": the things quests ask for that can be sold, a row each with its best
	-- loop; what an hour might make the most first, when prices are known, else the most asked for)
	if QITEM_WORDS[thing] and not kind then
		local QDB = _G.QuestDB or (_G.LibQuestieDB and _G.LibQuestieDB.Quest)
		local ItemDB = ns.Index.ItemDB()
		if not (QDB and QDB.GetAllIds and ItemDB) then return end
		local rates = ns.Search and ns.Search.DropRates and ns.Search.DropRates()
		local ForYou = ns.Search and ns.Search.QuestForYou
		local want, list = {}, {}
		for _, qid in ipairs(QDB.GetAllIds()) do
			local ok, obj = pcall(QDB.Get, qid, "objectives")
			local items = ok and type(obj) == "table" and obj[3]
			if type(items) == "table" and (not ForYou or ForYou(QDB, qid)) then
				for _, it in ipairs(items) do
					local iid = type(it) == "table" and it[1] or it
					if type(iid) == "number" then
						local w = want[iid]
						if w == nil then
							-- (one anyone can sell, that mobs drop)
							local okC, class = pcall(ItemDB.Get, iid, "class")
							local okN, name = pcall(ItemDB.Get, iid, "name")
							local okD, own = pcall(ItemDB.Get, iid, "npcDrops")
							local drops = (okD and type(own) == "table" and #own > 0) or (rates and type(rates[iid]) == "table")
							-- (not cloth, leather, ore or bars: those have lists of their own)
							local ln = okN and type(name) == "string" and lower(name):gsub("'", "") or ""
							local goods = SKINNED[ln] or ln:find(" cloth$") or ln == "runecloth" or ln == "felcloth"
								or ln:find(" bar$") or ln:find(" ore$") or ln:find(" leather$") or ln:find(" hide$")
							if okC and class ~= ITEM_QUEST and ln ~= "" and drops and not goods then
								w = { id = iid, name = name, n = 0, quest = qid }
								list[#list + 1] = w
							else
								w = false
							end
							want[iid] = w
						end
						if w then w.n = w.n + 1 end
					end
				end
			end
		end
		if #list == 0 then return end
		-- (the dearest first, when there are prices; else the most asked for)
		local priced = false
		for _, w in ipairs(list) do
			local _, high = Farm.Price(w.id)
			w.price = high or 0
			if high then priced = true end
		end
		table.sort(list, function(a, b)
			if priced and a.price ~= b.price then return a.price > b.price end
			if a.n ~= b.n then return a.n > b.n end
			return a.name < b.name
		end)
		local rows = {}
		for i = 1, min(#list, QITEM_TRY) do
			Farm.At(i, min(#list, QITEM_TRY))
			local w = list[i]
			local t = lower(w.name):gsub("'", "")
			local opts, title, nodes = Options(t, nil)
			cache[t .. "|nil"] = nil
			-- (a herb's or a vein's: the herb and ore lists' business)
			if opts and #opts > 0 and opts[1].mob then
				Mark(opts)
				local best
				for _, o in ipairs(opts) do if not o.high then best = o break end end
				best = best or opts[1]
				best.title, best.label, best.own = title, ("%s, %s"):format(title, best.zone), best.mobs
				best.wanted = w.n
				best.more = lower(w.name) .. " farm"
				local okQ, qname = pcall(QDB.Get, w.quest, "name")
				best.wantedBy = okQ and type(qname) == "string" and qname or nil
				local _, worth = Farm.Worth(best, title)
				best.worth = worth or 0
				rows[#rows + 1] = best
			end
		end
		if #rows == 0 then return end
		table.sort(rows, function(a, b)
			if a.worth ~= b.worth then return a.worth > b.worth end
			return a.wanted > b.wanted
		end)
		for i = #rows, QITEM_ROWS + 1, -1 do rows[i] = nil end
		ForYouFirst(rows)
		local qtitle = L["Quest items to sell"]
		cache[key] = { loops = rows, title = qtitle, nodes = {}, asIs = true }
		return rows, qtitle, {}
	end
	-- ("ore farm", "herb farm": each ore's or herb's best loop, a row. What each worked out is let
	-- go but that loop)
	if KIND_LISTS[thing] and kind == thing then
		local loops = {}
		for ti, t in ipairs(KIND_LISTS[thing]) do
			Farm.At(ti, #KIND_LISTS[thing])
			local opts, title, nodes = Options(t, kind)
			cache[t .. "|" .. tostring(kind)] = nil
			if opts and #opts > 0 then
				Mark(opts)
				local best
				for _, o in ipairs(opts) do if not o.high then best = o break end end
				if not best then
					for _, o in ipairs(opts) do if not best or o.high < best.high then best = o end end
				end
				best.title, best.label, best.own = title, ("%s, %s"):format(title, best.zone), nodes
				best.more = t .. (thing == "ore" and " ore farm" or " herb farm")
				loops[#loops + 1] = best
			end
		end
		if #loops == 0 then return end
		Mark(loops)
		ForYouFirst(loops)
		local ktitle = thing == "ore" and L["Ore farms"] or L["Herb farms"]
		cache[key] = { loops = loops, title = ktitle, nodes = {}, asIs = true }
		return loops, ktitle, {}
	end
	-- ("waylaid crate farm": the crates. A tier and a kind named: that crate's loops, zone by zone.
	-- A tier: its crates, a row each. Else each tier (of the kind named, or all its crates'), a row)
	if thing == "waylaid" or thing:sub(1, 8) == "waylaid " then
		local tier, ckind
		for w in thing:gmatch("%S+") do
			if CRATE_TIER[w] then tier = w elseif CRATE_KIND[w] then ckind = w end
		end
		local function Cap(w) return (w:gsub("^%l", string.upper)) end
		-- (the crates asked for, in groups: a group a row)
		local groups, byKey = {}, {}
		for _, c in ipairs(CRATES) do
			if (not tier or c.tier == tier) and (not ckind or c.kind == ckind) then
				local k = (tier and ckind) and "all" or tier and c.name or c.tier
				local g = byKey[k]
				if not g then
					g = { ids = {}, tier = c.tier, kind = (tier or ckind) and c.kind or nil }
					-- (a tier's crates, a row each: named as the item is)
					if not (tier and not ckind) then g.label = Cap(c.tier) .. (ckind and (" " .. Cap(ckind)) or "") end
					byKey[k] = g
					groups[#groups + 1] = g
				end
				for _, id in ipairs(ItemsNamed(c.name)) do g.ids[#g.ids + 1] = id end
			end
		end
		local wtitle = L["Waylaid Crates"]
		local rows = {}
		for _, g in ipairs(groups) do
			local mobs, name, over, levels, say = Droppers("waylaid crate", g.ids)
			if mobs then
				say.unknown = true
				local loops = MobOffer(mobs, over, levels, say)
				-- (the item's own name, when the row's one crate: "Waylaid Crate: Apprentice Ore")
				local gtitle = g.label and (wtitle .. ": " .. g.label) or name
				if tier and ckind then
					if #loops == 0 then return end
					cache[key] = { loops = loops, title = gtitle, nodes = mobs, asIs = true }
					return loops, gtitle, mobs
				end
				local best = loops[1]
				if best then
					best.title, best.own, best.label = gtitle, best.mobs, ("%s, %s"):format(gtitle, best.zone)
					-- (picked: a tier's crates, a row each; a crate's loops, zone by zone)
					best.more = "waylaid " .. g.tier .. (g.kind and (" " .. g.kind .. " crate farm") or " crates")
					rows[#rows + 1] = best
				end
			end
		end
		if #rows == 0 then return end
		ForYouFirst(rows)
		cache[key] = { loops = rows, title = wtitle, nodes = {}, asIs = true }
		return rows, wtitle, {}
	end
	-- ("lockpicking": each kind of box, zone by zone, a row; the least skill first)
	if thing == "lockpicking" then
		local ObjDB = ns.Index.ObjectDB and ns.Index.ObjectDB()
		if not ObjDB then return end
		local loops = {}
		for _, lk in ipairs(LOCKS) do
			local byZone, zones, own, name = {}, {}, {}, nil
			for _, id in ipairs(lk[1]) do
				local okN, n = pcall(ObjDB.Get, id, "name")
				if okN and type(n) == "string" then
					name = name or n
					own[#own + 1] = { id, n }
					for areaId, list in pairs(Spawns(id) or {}) do
						local ui = type(list) == "table" and UiFor(areaId)
						if ui then
							for _, sp in ipairs(list) do
								local x, y = sp[1], sp[2]
								if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
									local X, Y = HBD:GetWorldCoordinatesFromZone(x / 100, y / 100, ui)
									if X and not (ns.Route and ns.Route.FoeNear and ns.Route.FoeNear(ui, x, y)) then
										local z = byZone[ui]
										if not z then z = {} byZone[ui] = z zones[#zones + 1] = ui end
										z[#z + 1] = { x = x, y = y, X = X, Y = Y }
									end
								end
							end
						end
					end
				end
			end
			table.sort(zones)
			for _, ui in ipairs(zones) do
				local pts = byZone[ui]
				local loop = #pts >= LOCK_MIN and Loop(ui, pts)
				-- (all in one place, a ship's hold, a camp: the one stop)
				if #pts >= LOCK_MIN and not (loop and loop.nodes >= LOCK_MIN) then
					local c = { x = 0, y = 0, X = 0, Y = 0, n = #pts }
					for _, q in ipairs(pts) do
						c.x, c.y, c.X, c.Y = c.x + q.x / #pts, c.y + q.y / #pts, c.X + q.X / #pts, c.Y + q.Y / #pts
					end
					loop = { ui = ui, spots = { c }, nodes = #pts, yards = 0, secs = 60 }
				end
				if loop and loop.nodes >= LOCK_MIN then
					loop.zone, loop.count = ns.ZoneName(ui) or "?", #byZone[ui]
					loop.rate = loop.nodes / max(loop.secs, 60) * 60
					loop.title, loop.own, loop.label = name, own, ("%s, %s"):format(name, loop.zone)
					loop.skill, loop.skillTo, loop.lock = lk[2], lk[3], true
					loops[#loops + 1] = loop
				end
			end
		end
		if #loops == 0 then return end
		local ltitle = L["Lockpicking"]
		cache[key] = { loops = loops, title = ltitle, nodes = {}, asIs = true }
		return loops, ltitle, {}
	end
	-- ("copper and tin": the two together)
	local parts = Parts(thing)
	if parts then
		local loops, mtitle, mnodes = Mixed(parts, kind)
		if not loops then return end
		cache[key] = { loops = loops, title = mtitle, nodes = mnodes }
		return Offer(loops), mtitle, mnodes
	end
	local nodes, title = Nodes(thing, kind)
	local need = ZONE_MIN   -- (spots a zone needs for a loop)
	if #nodes == 0 then
		-- (a zone's name: its farms, each a row)
		local place = ZoneNamed(thing)
		if place then
			local loops = ZoneFarms(place.id, kind)
			if not loops then return end
			local ztitle = L["Farms in %s"]:format(ns.ZoneName(place.id) or place.name or "?")
			cache[key] = { loops = loops, title = ztitle, nodes = {}, asIs = true }
			return loops, ztitle, {}
		end
		-- ("leather farm", "skinning farm": every leather, hide and scale there's a loop for, each
		-- a row: its best loop for you)
		local drops = SKIN_WORDS[thing] and SKINS or CLOTH_WORDS[thing] and CLOTHS
		if drops then
			local loops = {}
			for di, item in ipairs(drops) do
				Farm.At(di, #drops)
				Farm.Breathe(item)   -- (the list worked out over frames: between its things)
				local mobs, name, over, levels, say = Droppers(item)
				local best = mobs and MobOffer(mobs, over, levels, say)[1]
				if best then
					best.title, best.own, best.label = name, best.mobs, ("%s, %s"):format(name, best.zone)
					best.more = lower(name) .. " farm"   -- (picked: its loops, zone by zone)
					loops[#loops + 1] = best
				end
			end
			if #loops == 0 then return end
			local stitle = drops == SKINS and L["Leather farms"] or L["Cloth farms"]
			ForYouFirst(loops)
			cache[key] = { loops = loops, title = stitle, nodes = {}, asIs = true }
			return loops, stitle, {}
		end
		-- (not a vein or herb: an item mobs drop, a loop round their camps)
		if kind then return end
		local mobs, name, over, levels, say = Droppers(thing)
		local loops = mobs and MobOffer(mobs, over, levels, say) or {}
		if #loops > 0 then
			local all = {}
			for _, set in ipairs({ mobs, over }) do for npc, rate in pairs(set) do all[npc] = rate end end
			cache[key] = { loops = loops, title = name, nodes = all, asIs = true }
			return loops, name, all
		end
		-- (nothing drops it: something picked up off the ground, a quest's moss, a chest's. Where
		-- its things stand, a loop as a herb's)
		local ItemDB, ObjDB = ns.Index.ItemDB(), ns.Index.ObjectDB and ns.Index.ObjectDB()
		local picked, pname, had = {}, nil, {}
		for _, id in ipairs(ObjDB and ItemsNamed((lower(thing):gsub("'", ""))) or {}) do
			local okN, n = pcall(ItemDB.Get, id, "name")
			local okO, objs = pcall(ItemDB.Get, id, "objectDrops")
			for _, oid in ipairs(okO and type(objs) == "table" and objs or {}) do
				local okG, oname = pcall(ObjDB.Get, oid, "name")
				if okG and type(oname) == "string" and not had[oid] then
					had[oid] = true
					picked[#picked + 1] = { oid, oname }
					pname = pname or (okN and type(n) == "string" and n) or oname
				end
			end
		end
		if #picked == 0 then return end
		nodes, title, need = picked, pname, PICK_MIN
	end
	-- (the loops over the terrain, where they've been worked out: of the vein or herb named,
	-- and its kinds alone, "iron" Iron Deposits and not Dark Iron's)
	local fkey = FarmKey(title)
	local baked = ns.FARM_NET and ns.FARM_NET[fkey]
	if baked then
		local mine = {}
		for _, g in ipairs(nodes) do if FarmKey(g[2]) == fkey then mine[#mine + 1] = g end end
		if #mine > 0 then nodes = mine end
	end
	-- (every spawn, zone by zone, in yards too)
	local byZone, zones = {}, {}
	for _, g in ipairs(nodes) do
		for areaId, list in pairs(Spawns(g[1]) or {}) do
			local ui = type(list) == "table" and UiFor(areaId)
			if ui then
				for _, s in ipairs(list) do
					local x, y = s[1], s[2]
					if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
						local X, Y = HBD:GetWorldCoordinatesFromZone(x / 100, y / 100, ui)
						-- (a spawn in a town of the other faction: not one to ride to)
						if X and not (ns.Route and ns.Route.FoeNear and ns.Route.FoeNear(ui, x, y)) then
							local z = byZone[ui]
							if not z then z = {} byZone[ui] = z zones[#zones + 1] = ui end
							z[#z + 1] = { x = x, y = y, X = X, Y = Y, learned = s[3] == 1 }
						end
					end
				end
			end
		end
	end
	-- (every zone's with enough for a loop: which are offered is up to where you are, Offer)
	local options = {}
	for _, ui in ipairs(zones) do
		if #byZone[ui] >= need then
			local loop = baked and baked[ui] and Baked(ui, baked[ui], byZone[ui]) or Loop(ui, byZone[ui])
			if loop and loop.nodes >= need then
				loop.zone, loop.count = ns.ZoneName(ui) or "?", #byZone[ui]
				loop.rate = loop.nodes / max(loop.secs, 60) * 60   -- (spawns a minute's riding passes)
				options[#options + 1] = loop
			end
		end
	end
	if #options == 0 then return end
	cache[key] = { loops = options, title = title, nodes = nodes }
	return Offer(options), title, nodes
end

-- what a vein or plant gives: the item's id ("Peacebloom" -> Peacebloom; "Copper Vein", "Small
-- Thorium Vein", "Incendicite Mineral Vein" -> their ore), or nil. Kept once found
local itemOf = {}
function Farm.ItemOf(title)
	if not title then return end
	if itemOf[title] ~= nil then return itemOf[title] or nil end
	local name = title
	local base = title:match("^(.-) Vein$") or title:match("^(.-) Deposit$")
	if base then
		base = base:gsub("^Small ", ""):gsub("^Rich ", ""):gsub("^Poor ", ""):gsub("^Ooze Covered ", ""):gsub(" Mineral$", "")
		name = base .. " Ore"
	end
	local id
	local ItemDB = ns.Index.ItemDB and ns.Index.ItemDB()
	if ItemDB and ItemDB.IdsByName then
		local ok, ids = pcall(ItemDB.IdsByName, name)
		if ok and type(ids) == "table" then id = ids[1] end
	end
	if not id then
		-- (no lookup by name: MapSeek's own lists, the unsold items and the sold)
		local l = lower(name):gsub("'", "")
		id = ns.Index.UnsoldIds and ns.Index.UnsoldIds(l)[1]
		if not id then
			for _, it in ipairs(ns.Index.items or {}) do
				if it.lname == l then id = it.id break end
			end
		end
	end
	itemOf[title] = id or false
	return id
end

--- the icon for a vein's or plant's markers and its drop-down row: the item it gives
--- (Peacebloom's own, Copper Ore's), else the profession's
function Farm.Icon(title)
	local tl = lower(title or "")
	if find(tl, "footlocker$") or find(tl, "lockbox$") or find(tl, "strongbox$") or title == L["Lockpicking"] then
		return "Interface\\Icons\\Spell_Nature_MoonKey"
	end
	if find(tl, "^waylaid crate") or title == L["Waylaid Crates"] or (title or ""):sub(1, #L["Waylaid Crates"]) == L["Waylaid Crates"] then
		local cid = Farm.ItemOf(title)
		local cicon = cid and ns.ItemIcon and ns.ItemIcon(cid)
		return cicon and cicon ~= 134400 and cicon or "Interface\\Icons\\INV_Crate_01"
	end
	local id = Farm.ItemOf(title)
	if id and ns.ItemIcon then
		local icon = ns.ItemIcon(id)
		if icon and icon ~= 134400 then return icon end
	end
	local l = lower(title or "")
	return (find(l, "vein$") or find(l, "deposit$")) and "Interface\\Icons\\Trade_Mining"
		or "Interface\\Icons\\Trade_Herbalism"
end

--- a loop's hops over the ground, worked out now if they weren't (a mob farm's: when it's looked
--- at or ridden, not for every one offered)
function Farm.Ways(opt)
	if opt and (opt.mob or opt.ways) then MobWays(opt) end
end

--- the markers for a loop's zone: every vein or plant of it there, as a search's results
function Farm.Results(opt, nodes, title)
	local results = {}
	if opt.mob then
		-- (the mobs' camps, each an area drawn on the map with one marker at its middle, as a
		-- search for the thing shows where it drops: not a marker on every mob)
		local icon, NpcDB = Farm.Icon(title), ns.Index.DB()
		local item = opt.item or 0
		local pts = {}
		for npc, rate in pairs(opt.mobs or {}) do
			local e = ns.Index.byId[npc]
			local okN, mname = pcall(NpcDB.Get, npc, "name")
			mname = (e and e.name) or (okN and type(mname) == "string" and mname) or "?"
			for areaId, list in pairs(ns.Index.Spawns(NpcDB, npc) or {}) do
				if type(list) == "table" and UiFor(areaId) == opt.ui then
					for _, sp in ipairs(list) do
						if type(sp[1]) == "number" and type(sp[2]) == "number" and sp[1] >= 0 then
							pts[#pts + 1] = { ui = opt.ui, x = sp[1], y = sp[2], src = mname, wt = rate / 100, rate = rate }
						end
					end
				end
			end
		end
		if #pts == 0 or not (ns.Areas and ns.Areas.Clusters) then return results end
		local clusters = ns.Areas.Clusters(pts)
		table.sort(clusters, function(x, y) return (x.wt or 0) > (y.wt or 0) end)
		-- (a mob standing alone, when there are camps: left off, not a marker for each stray)
		local camps = false
		for _, k in ipairs(clusters) do if #k.pts >= 2 then camps = true break end end
		for i, k in ipairs(clusters) do
			if not camps or #k.pts >= 2 then
			-- (what drops it there, the most first, and how often when that's known)
			local count, names, rateBy = {}, {}, {}
			for _, q in ipairs(k.pts) do
				if not count[q.src] then names[#names + 1] = q.src count[q.src] = 0 end
				count[q.src] = count[q.src] + 1
				rateBy[q.src] = q.rate
			end
			table.sort(names, function(x, y) if count[x] ~= count[y] then return count[x] > count[y] end return x < y end)
			local lines = { { L["Drops from:"], 1, 0.82, 0.1 } }
			for j, n in ipairs(names) do
				if j > 6 then
					lines[#lines + 1] = { "  " .. L["and %d more"]:format(#names - 6), 0.8, 0.8, 0.8 }
					break
				end
				lines[#lines + 1] = { "  " .. n .. ((not opt.unknown and rateBy[n]) and (" (%d%%)"):format(floor(rateBy[n] + 0.5)) or ""), 1, 1, 1 }
			end
			local mid = ns.Areas.Middle(k)
			local area
			if #k.pts >= 2 then
				local okO, outline = pcall(ns.Areas.Outline, k)
				if okO and type(outline) == "table" and outline.verts then
					area = {}
					for kk, v in pairs(outline) do area[kk] = v end
					area.name, area.icon, area.mid = title or "?", icon, { mid.x, mid.y }
					area.label = table.concat({ names[1], names[2] }, ", ")
					area.key = ("%d:%.2f:%.2f:%d"):format(k.ui, area.verts[1] or 0, area.verts[2] or 0, item)
				end
			end
			results[#results + 1] = { entry = { obj = true, id = -(3000000 * i + item), name = title or "?" },
				points = { { ui = k.ui, x = mid.x, y = mid.y } }, near = true, rank = 0, kind = "DROPS",
				label = L["Farming: %s"]:format(title or "?"), icon = icon, farm = true, lines = lines, area = area }
			end
		end
		return results
	end
	local icon = Farm.Icon(title)
	for _, g in ipairs(nodes) do
		-- (things farmed together: each its own icon, and its own name on its markers)
		local own = opt.mix and Farm.Icon(g[2]) or icon
		local pts = {}
		for areaId, list in pairs(Spawns(g[1]) or {}) do
			if type(list) == "table" and UiFor(areaId) == opt.ui then
				for _, s in ipairs(list) do
					if type(s[1]) == "number" and type(s[2]) == "number" and s[1] >= 0 then
						pts[#pts + 1] = { ui = opt.ui, x = s[1], y = s[2] }
					end
				end
			end
		end
		if #pts > 0 then
			results[#results + 1] = { entry = { obj = true, id = -g[1], objectId = g[1], name = g[2] }, points = pts,
				near = true, rank = 0, kind = "DROPS", label = L["Farming: %s"]:format(opt.mix and g[2] or title or g[2]), gathered = true,
				icon = own, farm = true }
		end
	end
	return results
end

--- go round a loop, starting at its spot nearest you
local FIRST_TRIES = 6   -- spots about a loop the way to which is timed, for where it's begun
function Farm.Start(opt, title)
	if not (ns.Route and ns.Route.StartLoop) then return end
	Farm.Ways(opt)
	local first, bd = 1, huge
	if HBD and HBD.GetPlayerWorldPosition then
		local px, py = HBD:GetPlayerWorldPosition()
		if px then
			for i, s in ipairs(opt.spots) do
				local d = (s.X - px) ^ 2 + (s.Y - py) ^ 2
				if d < bd then first, bd = i, d end
			end
		end
	end
	-- (from another zone: begun at the spot the way there comes to soonest, not one across the
	-- loop from where it comes in, ridden to through the rest. A few of them about the loop
	-- timed, then the best of those' neighbours)
	local here = ns.PlayerMap and ns.PlayerMap()
	if here ~= opt.ui and ns.Route.Plan and #opt.spots > 1 then
		local nS = #opt.spots
		local timed, best, least = {}, nil, nil
		local function Time(i)
			i = (i - 1) % nS + 1
			if timed[i] == nil then
				local s = opt.spots[i]
				local ok, _, secs = pcall(ns.Route.Plan, { ui = opt.ui, x = s.x, y = s.y }, true)
				timed[i] = ok and tonumber(secs) or false
			end
			if timed[i] and (not least or timed[i] < least) then best, least = i, timed[i] end
		end
		local stride = math.max(1, floor(nS / FIRST_TRIES))
		for i = 1, nS, stride do Time(i) end
		if best then
			local mid = best
			for k = 1, stride - 1 do Time(mid + k) Time(mid - k) end
			first = best
		end
	end
	local speed, n = Speed(), #opt.spots
	local steps = {}
	for i, s in ipairs(opt.spots) do
		local prev = opt.spots[(i - 2) % n + 1]
		-- (the hop here: over the terrain, its way drawn, when the loop was worked out so)
		local leg = opt.legs and opt.legs[(i - 2) % n + 1]
		-- (a town of the other faction near the hop: said on the step)
		local way = {}
		for _, v in ipairs(leg and leg.via or {}) do way[#way + 1] = v end
		if #way == 0 then way[1] = { ui = opt.ui, x = prev.x, y = prev.y } end
		way[#way + 1] = { ui = opt.ui, x = s.x, y = s.y }
		local town = ns.Route.FoeOnWay and ns.Route.FoeOnWay(way)
		steps[i] = { kind = "farm", to = { ui = opt.ui, x = s.x, y = s.y }, foe = town,
			secs = leg and leg.secs * NET_RIDE / speed or Len(prev, s) * DETOUR / speed,
			via = leg and #leg.via > 0 and leg.via or nil,
			text = L["%s: spot %d of %d"]:format(opt.zone, i, n)
				.. (town and ("  |cffff6040" .. L["careful: passes %s"]:format(town) .. "|r") or "") }
	end
	return ns.Route.StartLoop({ steps = steps, first = first, total = opt.secs,
		name = ("%s, %s"):format(title or "?", opt.zone) })
end

--------------------------------------------------------------------------------
-- Learning: a vein mined or a herb picked where neither the data nor you had one. Kept, and in
-- that zone's loops from then on. (What was gathered: the cast's target, as the game names it;
-- where: where you stood. Only Mining's and Herb Gathering's casts.)
--------------------------------------------------------------------------------

local KNOWN_YARDS = 30     -- a spawn of its kind this near: that one, not a new one
local MINING = { [2575] = true, [2576] = true, [3564] = true, [10248] = true, [366260] = true }
local HERBING = { [2366] = true, [2368] = true, [3570] = true, [11993] = true, [366252] = true }

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, id)
		if ok and n then return n end
	end
	if GetSpellInfo then
		local ok, n = pcall(GetSpellInfo, id)
		if ok and type(n) == "string" then return n end
	end
end

-- "ore" or "herb" when a spell is the gathering of one; else nil
local function GatherKind(spellID)
	if MINING[spellID] then return "ore" end
	if HERBING[spellID] then return "herb" end
	local n = spellID and SpellName(spellID)
	if not n then return end
	if n == SpellName(2575) then return "ore" end
	if n == SpellName(2366) then return "herb" end
end

local function Learn(name)
	if not (name and name ~= "" and HBD and HBD.GetPlayerWorldPosition and ns.Index.done) then return end
	local px, py = HBD:GetPlayerWorldPosition()
	local zone = HereZone()
	if not (px and zone) then return end
	local x, y = HBD:GetZoneCoordinatesFromWorld(px, py, zone, true)
	if not x then return end
	-- (its kind as the data names it, when it has it: "Tin Vein")
	local key, store = FarmKey(name), nil
	for _, g in ipairs(Gather()) do
		if FarmKey(g[2]) == key then
			store = store or g[2]
			if lower(g[2]) == lower(name) then store = g[2] end
			for areaId, list in pairs(Spawns(g[1]) or {}) do
				if type(list) == "table" and UiFor(areaId) == zone then
					for _, sp in ipairs(list) do
						if type(sp[1]) == "number" and type(sp[2]) == "number" then
							local X, Y = HBD:GetWorldCoordinatesFromZone(sp[1] / 100, sp[2] / 100, zone)
							if X and (X - px) ^ 2 + (Y - py) ^ 2 <= KNOWN_YARDS * KNOWN_YARDS then return end
						end
					end
				end
			end
		end
	end
	local all = Learned()
	if not store then
		store = name
		local have = false
		for _, n in ipairs(ns.db.nodeNames) do if n == name then have = true break end end
		if not have then tinsert(ns.db.nodeNames, name) end
	end
	all[store] = all[store] or {}
	all[store][zone] = all[store][zone] or {}
	tinsert(all[store][zone], { floor(x * 1000 + 0.5) / 10, floor(y * 1000 + 0.5) / 10, 1 })
	wipe(cache)   -- (the loops: worked out again, with it)
	ns.Print(L["New spot learned: %s, %s. It's in your farming loops from now on."]:format(store, ns.ZoneName(zone) or "?"))
end

local casting   -- the gathering cast under way: { guid, name }
local learner = CreateFrame("Frame")
learner:RegisterEvent("UNIT_SPELLCAST_SENT")
learner:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
learner:RegisterEvent("UNIT_SPELLCAST_FAILED")
learner:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
learner:SetScript("OnEvent", function(_, event, unit, a, b, c)
	if unit ~= "player" then return end
	pcall(function()
		if event == "UNIT_SPELLCAST_SENT" then
			-- (unit, target, cast, spell)
			casting = nil
			if GatherKind(c) then
				local name = type(a) == "string" and a ~= "" and a or nil
				if not name and GameTooltip:IsShown() and GameTooltipTextLeft1 then name = GameTooltipTextLeft1:GetText() end
				casting = { guid = b, name = name }
			end
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			-- (unit, cast, spell)
			if casting and (casting.guid == a or GatherKind(b)) then
				local name = casting.name
				casting = nil
				Learn(name)
			end
		else
			casting = nil
		end
	end)
end)
