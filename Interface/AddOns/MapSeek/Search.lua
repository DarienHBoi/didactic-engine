--------------------------------------------------------------------------------
-- Matching. A search is one of:
--   quest givers  "quests": NPCs and objects with a quest for your level you can pick up now,
--                 in your zone (or the one named), and the zones with more
--   objects       "mailbox", "forge", "anvil", "campfire", "meeting stone": the whole search
--                 names one (so "cooking" finds cooks, not every campfire in the world)
--   NPCs          every word typed must match: either its name or title contains the word
--                 ("fishing" -> "Fishing Trainer"), or the word names a service the NPC offers
--                 ("repair" -> any NPC with the repair flag, whatever its title says)
--   + items       the vendors who sell an item whose name matches ("simple flour")
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local Search = {}
ns.Search = Search

local band = bit.band
local find, lower = string.find, string.lower

local MAX_MATCHES = 1500   -- NPCs (or objects) whose spawns are read for one search
local ITEM_MAX = 40        -- items whose vendors a search shows, when no name matches exactly
local SELLS_MAX = 3        -- items searched for listed on one vendor

-- words that also mean "has this service" (npcFlags names from QuestieDB)
local SERVICES = {
	repair = "REPAIR", repairs = "REPAIR",
	innkeeper = "INNKEEPER", inn = "INNKEEPER",
	flight = "FLIGHT_MASTER", flightmaster = "FLIGHT_MASTER", fp = "FLIGHT_MASTER",
	bank = "BANKER", banker = "BANKER",
	auction = "AUCTIONEER", auctioneer = "AUCTIONEER", ah = "AUCTIONEER",
	stable = "STABLEMASTER", stablemaster = "STABLEMASTER",
	trainer = "TRAINER",
	vendor = "VENDOR", merchant = "VENDOR",
	battlemaster = "BATTLEMASTER",
	tabard = "TABARD_DESIGNER",
	charter = "PETITIONER",
}

-- profession words: they also match that profession's trainers, whatever their title says
-- ("alchemy trainer" -> "Journeyman Alchemist"). Skill IDs as Index.lua keeps them on trainers
local PROFESSIONS = {
	alchemy = 171, alchemist = 171, blacksmithing = 164, blacksmith = 164, armorsmith = 164,
	weaponsmith = 164, bs = 164, lw = 165, leatherworking = 165, leatherworker = 165, tailoring = 197, tailor = 197,
	enchanting = 333, enchanter = 333, engineering = 202, engineer = 202, herbalism = 182,
	herbalist = 182, mining = 186, miner = 186, skinning = 393, skinner = 393, cooking = 185,
	cook = 185, fishing = 356, fisherman = 356, jewelcrafting = 755, jeweler = 755,
	inscription = 773, scribe = 773, riding = 762,
}

-- short words that would match inside too many names ("inn" in Quinn): the service only
local SERVICE_ONLY = { inn = true, ah = true, fp = true }

-- whole searches that mean objects (the kinds Index.lua keeps), or quest givers
local OBJECTS = {
	mail = "MAILBOX", mailbox = "MAILBOX", mailboxes = "MAILBOX",
	forge = "FORGE", forges = "FORGE",
	anvil = "ANVIL", anvils = "ANVIL",
	campfire = "COOKING", campfires = "COOKING", fire = "COOKING", ["cooking fire"] = "COOKING",
	["cooking fires"] = "COOKING", fires = "COOKING", bonfire = "COOKING", bonfires = "COOKING",
	stove = "COOKING", stoves = "COOKING",
	["meeting stone"] = "MEETING_STONE", ["meeting stones"] = "MEETING_STONE",
	["summoning stone"] = "MEETING_STONE", ["summoning stones"] = "MEETING_STONE",
}
-- skill book searches ("first aid book", "cooking books", "skill books"): every word one of
-- these, with at least one book word. Profession words -> the recipe subclass of its books
local BOOK_WORDS = { book = true, books = true, manual = true, manuals = true, cookbook = true,
	cookbooks = true, skillbook = true, skillbooks = true, expert = true, artisan = true }
local BOOK_PROFS = { first = 7, aid = 7, firstaid = 7, bandage = 7, bandages = 7, cooking = 5, cook = 5,
	cookbook = 5, cookbooks = 5, fishing = 9, fish = 9 }
local BOOK_FILLER = { skill = true, skills = true, level = true, leveling = true, levelling = true,
	profession = true, professions = true, the = true, ["for"] = true, to = true, past = true, up = true,
	cap = true, raise = true, my = true }
Search.BOOK_NAMES = { [5] = L["Cooking"], [7] = L["First Aid"], [9] = L["Fishing"] }

local QUESTS = { quest = true, quests = true, ["quest giver"] = true, ["quest givers"] = true }
-- whole searches that mean Forever's transports (Route.lua lists the docks and towers)
local TRANSPORTS = { boat = "boat", boats = "boat", ship = "boat", ships = "boat", ferry = "boat", harbor = "boat",
	harbour = "boat", dock = "all", docks = "all", zeppelin = "zeppelin", zeppelins = "zeppelin", zep = "zeppelin",
	zeps = "zeppelin", tram = "tram", ["deeprun tram"] = "tram", skycutter = "skycutter", transport = "all",
	transports = "all", ["boats and zeppelins"] = "all" }
local TRANSPORT_NAMES = { boat = L["Boat to %s"], zeppelin = L["Zeppelin to %s"], tram = L["Tram to %s"],
	portal = L["Portal to %s"], skycutter = L["Skycutter to %s"] }
local TRANSPORT_ICON = { boat = "Interface\\Icons\\Spell_Frost_SummonWaterElemental", zeppelin = "Interface\\Icons\\INV_Misc_Bomb_04",
	tram = "Interface\\Icons\\INV_Misc_Gear_01", portal = "Interface\\Icons\\Spell_Arcane_PortalStormWind",
	skycutter = "Interface\\Icons\\Ability_Hunter_EagleEye" }

local Canon   -- (keywords split or run together, put right: below)
Search.OBJECTS = OBJECTS

-- the main professions (two at most): trainers of the others are left out once both are known
local PRIMARY = { [164] = true, [165] = true, [171] = true, [182] = true, [186] = true, [197] = true,
	[202] = true, [333] = true, [393] = true, [755] = true, [773] = true }

local function FlagBit(word)
	local enum = _G.LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.npcFlags
	local key = SERVICES[word]
	if not (enum and key and enum[key]) then return nil end
	-- "vendor": anyone you can sell to, repairers among them (a few repairers aren't flagged
	-- as vendors too)
	if key == "VENDOR" and enum.REPAIR then return bit.bor(enum.VENDOR, enum.REPAIR) end
	return enum[key]
end

local function Questie(name)
	if not QuestieLoader then return end
	local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
	return ok and type(mod) == "table" and mod or nil
end

--------------------------------------------------------------------------------
-- Zones (AreaID in Questie's data -> UiMapID for the map), cached
--------------------------------------------------------------------------------

local zoneCache = {}
local ZoneDB
-- QuestieDB's own zone tables (its support data: areas to maps, the dungeons' entrances): what
-- Questie's ZoneDB reads, and there without Questie. nil when this QuestieDB hasn't them
function Search.ZoneData()
	local S = _G.LibQuestieDB and LibQuestieDB.Support
	if not (S and S.Get) then return end
	local ok, mod = pcall(S.Get, "ZoneDB")
	return ok and type(mod) == "table" and type(mod.private) == "table" and mod.private or nil
end

-- QuestieDB's areas to maps, as one table: it keeps them as text ("return { ... }", read when
-- they're wanted, as Questie reads them), with a second of corrections to lay over the first.
-- false when this QuestieDB hasn't them, or they can't be read
function Search.AreaMaps()
	if Search.areaMaps ~= nil then return Search.areaMaps end
	local zd = Search.ZoneData()
	local function Read(v)
		if type(v) == "table" then return v end
		if type(v) ~= "string" or not loadstring then return end
		local f = loadstring(v)
		local ok, t = pcall(f or error)
		return ok and type(t) == "table" and t or nil
	end
	local base = zd and Read(zd.areaIdToUiMapId)
	local out = false
	if base then
		out = {}
		for area, ui in pairs(base) do out[area] = ui end
		for area, ui in pairs(Read(zd.areaIdToUiMapIdOverride) or {}) do out[area] = ui end
	end
	Search.areaMaps = out
	return out
end

function ns.UiMapFor(areaId)
	local hit = zoneCache[areaId]
	if hit ~= nil then return hit or nil end
	local id
	-- (QuestieDB's table first: the data itself, and no word from Questie about an area it
	-- hasn't. Then Questie's ZoneDB, for a QuestieDB that keeps its tables elsewhere)
	local maps = Search.AreaMaps()
	local own = maps and maps[areaId]
	if type(own) == "number" and own > 0 then id = own end
	if not maps then
		ZoneDB = ZoneDB or Questie("ZoneDB")
		if ZoneDB and ZoneDB.GetUiMapIdByAreaId then
			local ok, r = pcall(ZoneDB.GetUiMapIdByAreaId, ZoneDB, areaId)
			if ok and type(r) == "number" and r > 0 then id = r end
		end
	end
	zoneCache[areaId] = id or false
	return id
end

-- zone-only: is this map the one the world map shows, or inside it?
local function InsideOf(shown)
	local cache = {}
	return function(ui)
		local v = cache[ui]
		if v ~= nil then return v end
		local id, guard = ui, 0
		v = false
		while id and id > 0 and guard < 12 do
			if id == shown then v = true break end
			local info = C_Map.GetMapInfo(id)
			id = info and info.parentMapID
			guard = guard + 1
		end
		cache[ui] = v
		return v
	end
end

--------------------------------------------------------------------------------

local function FactionOk(fac)
	if ns.db.otherFaction or not fac or fac == "AH" then return true end
	return (ns.faction == "Alliance" and fac == "A") or (ns.faction == "Horde" and fac == "H")
end
Search.FactionOk = FactionOk

-- the words for a bag: any one finds them all ("herb bag" finds the Herb Pouch)
local BAG_WORDS = { bag = true, bags = true, pouch = true, pouches = true, pack = true, packs = true,
	sack = true, sacks = true, satchel = true, satchels = true, knapsack = true, rucksack = true,
	backpack = true }
local BAG_LIST = { "bag", "pouch", "pack", "sack", "satchel" }   -- (knapsack, backpack: "sack", "pack")

local function AnyBag(lname)
	for i = 1, #BAG_LIST do
		if find(lname, BAG_LIST[i], 1, true) then return true end
	end
	return false
end

-- what makes a thing rather than being it: a recipe for a "herb bag" search comes after the bag
local function IsRecipe(lname)
	return find(lname, "^pattern: ") or find(lname, "^recipe: ") or find(lname, "^plans: ")
		or find(lname, "^schematic: ") or find(lname, "^formula: ") or find(lname, "^manual: ")
end

local function Tokens(query)
	local out = {}
	for word in query:gmatch("%S+") do
		local alt = (#word > 3 and word:sub(-1) == "s") and word:sub(1, -2) or nil   -- "trainers" -> "trainer"
		local flag = FlagBit(word) or (alt and FlagBit(alt))
		out[#out + 1] = { word = word, alt = alt, bit = flag, only = flag and SERVICE_ONLY[word],
			bag = BAG_WORDS[word],
			service = flag and (SERVICES[word] or SERVICES[alt]),
			prof = PROFESSIONS[word] or (alt and PROFESSIONS[alt]) }
	end
	return out
end

-- a word found in a name or title at the start of one of its words: a word that means a
-- service ("stable", "flight", "bank") isn't the middle of a name (Constable, Farflight)
Search.TWO_WORDS = { flightmaster = "flight master", stablemaster = "stable master", battlemaster = "battle master" }
function Search.WordIn(hay, w)
	local at = 1
	while true do
		local s = find(hay, w, at, true)
		if not s then return false end
		if s == 1 or not hay:sub(s - 1, s - 1):find("%a") then return true end
		at = s + 1
	end
end

local function Matches(e, tokens)
	for i = 1, #tokens do
		local t = tokens[i]
		local In = t.bit and Search.WordIn or nil
		if t.only then
			if band(e.flags, t.bit) == 0 then return false end
		elseif In then
			-- (a title in two words too: "Flight Master", on one the data hasn't marked as one)
			local two = Search.TWO_WORDS[t.word]
			if not (In(e.hay, t.word) or (t.alt and In(e.hay, t.alt)) or (two and In(e.hay, two))
				or band(e.flags, t.bit) ~= 0 or (t.prof and e.prof == t.prof)) then
				return false
			end
		elseif not (find(e.hay, t.word, 1, true)
			or (t.alt and find(e.hay, t.alt, 1, true))
			or (t.bit and band(e.flags, t.bit) ~= 0)
			or (t.prof and e.prof == t.prof)) then
			return false
		end
	end
	return true
end

-- the places as { ui, x, y } (x, y 0..100). NPCs: one per map, its first spawn there (an NPC who
-- walks about is listed at every point of his walk; his path is drawn instead, Pins.lua).
-- Objects (all = true): every spawn, a city has many mailboxes. nil when none can be placed
local function Points(DB, id, all, zoneOk)
	local spawns = ns.Index.Spawns(DB, id)
	if not spawns then return end
	local pts, seen
	for areaId, list in pairs(spawns) do
		local ui = type(list) == "table" and ns.UiMapFor(areaId)
		if ui and zoneOk and not zoneOk(ui) then ui = nil end
		if ui and (all or not (seen and seen[ui])) then
			for _, s in ipairs(list) do
				local x, y = s[1], s[2]
				if type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 then
					pts, seen = pts or {}, seen or {}
					pts[#pts + 1] = { ui = ui, x = x, y = y }
					seen[ui] = true
					if not all then break end
				end
			end
		end
	end
	return pts
end

--------------------------------------------------------------------------------
-- The searches
--------------------------------------------------------------------------------

local function Add(ctx, e, pts, extra)
	local near = false
	for _, p in ipairs(pts) do if ctx.priority[p.ui] then near = true break end end
	local lname = lower(e.name):gsub("'", "")
	local q = ctx.query
	local lsq, qsq = ns.Squash(lname), ns.Squash(q)
	local r = { entry = e, points = pts, near = near,
		rank = ((lname == q or lsq == qsq) and 0) or ((lname:sub(1, #q) == q or lsq:sub(1, #qsq) == qsq) and 1) or 2 }
	if extra then for k, v in pairs(extra) do r[k] = v end end
	ctx.results[#ctx.results + 1] = r
	ctx.byId[e.id] = r
	return r
end

local function NpcOk(ctx, e)
	return (ctx.hunter or not e.pet) and FactionOk(e.fac)
end

-- a plain "trainer" search: your class's trainers only, and the trainers of the professions you
-- have (or could still pick up). A search that says more ("mage trainer") shows what it says.
local function TrainerOk(ctx, e)
	if e.class and ns.db.ownClass and e.class ~= ctx.class then return false end
	if e.prof and ns.db.ownProfs and PRIMARY[e.prof] and ctx.profsFull and not ctx.profs[e.prof] then
		return false
	end
	return true
end

local function Npcs(ctx)
	local NpcDB, tokens = ctx.NpcDB, ctx.tokens
	local trainerOnly = ctx.generic and ctx.services.TRAINER
	for _, e in ipairs(ns.Index.entries) do
		-- (run together, for a name typed so: not a service's word, "stable" in Unstable or Constable)
		if NpcOk(ctx, e) and (Matches(e, tokens) or (not ctx.generic and ctx.qsq and e.sq and find(e.sq, ctx.qsq, 1, true)))
			and (not trainerOnly or TrainerOk(ctx, e)) then
			local pts = Points(NpcDB, e.id, false, ctx.zoneOk)
			if pts then
				Add(ctx, e, pts)
				if #ctx.results >= MAX_MATCHES then return end
			end
		end
	end
end

-- a search for flight masters: the game's own flight points too, where the data has no flight
-- master standing (a town of WoW Forever's own, its flight master not in Questie's data, or not
-- marked as one). Your faction's and the neutral ones, unless the other faction's are shown
local function FlightPoints(ctx)
	local FLIGHT_NEAR = 3   -- of a map's 100: a flight master this near a flight point is its own
	if not (ns.Route and ns.Route.FlightNodes) then return end
	local ok, nodes = pcall(ns.Route.FlightNodes)
	if not ok or type(nodes) ~= "table" then return end
	local had = {}
	for _, r in ipairs(ctx.results) do
		for _, p in ipairs(r.points or {}) do had[#had + 1] = p end
	end
	for i, n in ipairs(nodes) do
		local f = n.faction
		local ours = type(f) ~= "number" or f == 0 or (f == 1 and ns.faction == "Horde") or (f == 2 and ns.faction == "Alliance")
		if n.ui and n.x and n.y and type(n.name) == "string" and (ours or (ns.db and ns.db.otherFaction))
			and (not ctx.zoneOk or ctx.zoneOk(n.ui)) then
			local x, y = n.x * 100, n.y * 100
			local taken = false
			for _, p in ipairs(had) do
				if p.ui == n.ui and math.abs(p.x - x) <= FLIGHT_NEAR and math.abs(p.y - y) <= FLIGHT_NEAR then taken = true break end
			end
			if not taken then
				local r = Add(ctx, { id = -(2000000 + i), name = n.name, sub = L["Flight point"], obj = true, flags = 0 },
					{ { ui = n.ui, x = x, y = y } }, { kind = "FLIGHT_MASTER", label = L["Flight point"] })
				r.rank = 2
				if #ctx.results >= MAX_MATCHES then return end
			end
		end
	end
end

-- whole searches that mean NPCs by a word in their title, however it's put: "reagent vendor"
-- finds Reagent Vendors, Merchants, Suppliers, "Reagents & Poisons" ... (and "regents vendor",
-- as it's often typed). A bare "regent" stays a name search (Ravenclaw Regent)
local TITLES = {}
for _, word in ipairs({ "reagent", "reagents", "regent", "regents", "reagant", "reagants" }) do
	for _, kind in ipairs({ "", " vendor", " vendors", " merchant", " merchants", " seller", " supplier", " supplies", " shop" }) do
		if not (kind == "" and word == "regent") then TITLES[word .. kind] = "reagent" end
	end
end
-- (the mount sellers go by their beasts: "Kodo Mounts", "Horse Breeder", "Saber Handler"; the
-- ammunition sellers by "Bowyer", "Gunsmith", "Bow Merchant" ...)
local MOUNT_TITLES = { "mounts", "mount vendor", "mount merchant", "breeder", "saber handler", "mechanostrider" }
local AMMO_TITLES = { "bowyer", "gunsmith", "arrow", "bullet", "ammo", "ammunition", "bow merchant", "gun merchant" }
for _, q in ipairs({ "mount", "mounts", "mount vendor", "mount vendors", "mount merchant", "mounts vendor", "mount seller", "buy a mount" }) do
	TITLES[q] = MOUNT_TITLES
end
for _, q in ipairs({ "ammo", "ammunition", "ammo vendor", "ammo vendors", "ammunition vendor", "arrows and bullets", "bullets and arrows" }) do
	TITLES[q] = AMMO_TITLES
end
Search.TITLES = TITLES

--- whether a search is (part of) any real name: an NPC's name or title, or an item's, sold or not.
--- GM Island's made-up wares only answer a search that's none of these
function Search.InRealNames(query)
	local q = lower(strtrim(query or ""))
	if q == "" then return false end
	if find(ns.Index.unsold or "", q, 1, true) then return true end
	for _, it in ipairs(ns.Index.items) do
		if find(it.lname, q, 1, true) then return true end
	end
	for _, e in ipairs(ns.Index.entries) do
		if find(e.hay, q, 1, true) then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- Your group: where your party or raid are now (from the game, not Questie's data)
--------------------------------------------------------------------------------

local GROUP_WORDS = {}
for w in ("party,group,raid,my party,my group,my raid,party members,group members,raid members,"
	.. "party member,group member,raid member,groupmates,partymembers,raidmembers"):gmatch("[^,]+") do
	GROUP_WORDS[w] = true
end
Search.GROUP_WORDS = GROUP_WORDS

--- the units of the others in your group: raid1.. in a raid, party1.. in a party; none alone
function Search.GroupUnits()
	local units = {}
	if _G.IsInRaid and IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local u = "raid" .. i
			if UnitExists(u) and not UnitIsUnit(u, "player") then units[#units + 1] = u end
		end
	elseif _G.IsInGroup and IsInGroup() then
		for i = 1, GetNumSubgroupMembers() do
			local u = "party" .. i
			if UnitExists(u) then units[#units + 1] = u end
		end
	end
	return units
end

--- a search for your group ("party", "raid", "group") or one of them by their whole name: each
--- one's marker where they are now, a look of their class. nil when the
--- search isn't one of these; nil and why, when it is but none can be shown (not in a group;
--- all in a dungeon or offline). results.missing: those that can't be
function Search.Group(query)
	local q = lower(strtrim(query or ""))
	local units = Search.GroupUnits()
	local word = GROUP_WORDS[q]
	local only
	if not word then
		-- (MapSeek's own words stay what they are: a "Repair" in your party isn't "repair")
		if #units == 0 or Search.KnownWord(q) then return end
		-- (their whole name only: "bob" isn't Bobbert)
		only = {}
		for _, u in ipairs(units) do
			local name = UnitName(u)
			if name and lower(name) == q then only[u] = true end
		end
		if not next(only) then return end
	end
	if #units == 0 then return nil, L["You're not in a group."] end
	local results, missing = {}, {}
	for _, u in ipairs(units) do
		local name = UnitName(u)
		if name and (not only or only[u]) then
			local ui = C_Map and C_Map.GetBestMapForUnit(u)
			local pos = ui and UnitIsConnected(u) and C_Map.GetPlayerMapPosition(ui, u)
			local x, y
			if pos then
				if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
			end
			if x and y and (x > 0 or y > 0) then
				local className, class = UnitClass(u)
				local level = UnitLevel(u)
				local sub = className
				if level and level > 0 then sub = (_G.UNIT_LEVEL_TEMPLATE or "Level %d"):format(level) .. " " .. (className or "") end
				results[#results + 1] = { entry = { id = 0, name = name, sub = sub, obj = true, flags = 0 },
					kind = class and ns.LOOKS and ns.LOOKS["MEMBER_" .. class] and ("MEMBER_" .. class) or "GROUP",
					points = { { ui = ui, x = x * 100, y = y * 100 } }, rank = 0, near = false, member = true }
			else
				missing[#missing + 1] = name
			end
		end
	end
	table.sort(results, function(a, b) return a.entry.name < b.entry.name end)
	table.sort(missing)
	if #results == 0 then return nil, L["Not on the map (in a dungeon, or offline): %s"]:format(table.concat(missing, ", ")) end
	results.group, results.missing = true, missing
	return results
end

--- a word MapSeek's own searches know: a service, object, title search, bag or profession word,
--- or a place's name ("inn", "org"). The spelling fix leaves these be: "inn" isn't "ink"
function Search.KnownWord(w)
	return (SERVICES[w] or PROFESSIONS[w] or OBJECTS[w] or QUESTS[w] or BAG_WORDS[w] or TITLES[w] or GROUP_WORDS[w]
		or FlagBit(w) or Search.Place(w)) and true or false
end

local function TitleNpcs(ctx, words)
	local NpcDB = ctx.NpcDB
	if type(words) == "string" then words = { words } end
	for _, e in ipairs(ns.Index.entries) do
		-- (in the title: hay is the name and title, lower case; the name mustn't be what has it)
		local hit = false
		if e.sub and NpcOk(ctx, e) then
			local from = #(e.name:gsub("'", "")) + 1
			for _, w in ipairs(words) do
				if find(e.hay, w, from, true) then hit = true break end
			end
		end
		if hit then
			local pts = Points(NpcDB, e.id, false, ctx.zoneOk)
			if pts then
				Add(ctx, e, pts)
				if #ctx.results >= MAX_MATCHES then return end
			end
		end
	end
end

-- the vendors of the items whose name matches: an exact name if there is one, else up to ITEM_MAX
local Drops, QuestRewards, QuestGives, QuestsNeeding   -- (an item no vendor sells: where it drops; the quests that reward, give or need it. Below)
local MadeBy   -- (... or who sells the pattern a profession makes it from. Below)

local function Items(ctx)
	local q, tokens = ctx.query, ctx.tokens
	local qsq = ns.Squash(q)
	local exact, partial = {}, {}
	for _, it in ipairs(ns.Index.items) do
		if it.lname == q or it.sq == qsq then
			exact[#exact + 1] = it
		elseif #partial < ITEM_MAX then
			local ok = true
			for _, t in ipairs(tokens) do
				if not (find(it.lname, t.word, 1, true) or (t.alt and find(it.lname, t.alt, 1, true))
					or (t.bag and AnyBag(it.lname))) then
					ok = false
					break
				end
			end
			-- (or typed run together, or split where it isn't: "brownbag", "heavy brownbag")
			if not ok and ctx.qsq and it.sq and find(it.sq, ctx.qsq, 1, true) then ok = true end
			if ok then partial[#partial + 1] = it end
		end
	end
	-- an item no vendor sells ("linen cloth", or "mithril casings" of Mithril Casing): say so,
	-- rather than show the vendors of other things with the name in them
	if #exact == 0 then
		local one = q:match("^(.-)e?s$")
		local oneSq = qsq:match("^(.-)e?s$")
		local unsold = ns.Index.Unsold(q) and q
			or (one and ns.Index.Unsold(one) and one) or (q:sub(-1) == "s" and ns.Index.Unsold(q:sub(1, -2)) and q:sub(1, -2))
			-- (spaces or not: "mage weave cloth", "linencloth", "rune cloths")
			or ns.Index.UnsoldSquashed(qsq) or (oneSq and ns.Index.UnsoldSquashed(oneSq))
			or (qsq:sub(-1) == "s" and ns.Index.UnsoldSquashed(qsq:sub(1, -2)))
		if unsold then
			ctx.unsold = unsold
			Drops(ctx, unsold)
			QuestRewards(ctx, unsold)
			QuestGives(ctx, unsold)
			if #ctx.results == 0 then MadeBy(ctx, unsold) end
			return 0
		end
		-- (part of an unsold item's name, and nothing sold has it: that item, when it's one of a few)
		if #partial == 0 and #q >= 4 then
			local found = {}
			for name in ns.Index.unsold:gmatch("\n([^\1\n]+)\1") do
				local ok = true
				for _, t in ipairs(tokens) do
					if not (find(name, t.word, 1, true) or (t.alt and find(name, t.alt, 1, true))) then ok = false break end
				end
				if ok then
					found[#found + 1] = name
					if #found > 4 then break end
				end
			end
			if #found >= 1 and #found <= 4 then
				table.sort(found, function(a, b) return #a < #b end)
				-- (the first that's found somewhere; else the shortest, for "no vendor sells")
				for _, name in ipairs(found) do
					local had = #ctx.results
					ctx.unsold = name
					Drops(ctx, name)
					QuestRewards(ctx, name)
					QuestGives(ctx, name)
					if #ctx.results == had then MadeBy(ctx, name) end
					if #ctx.results > had then return 0 end
				end
				ctx.unsold = found[1]
				return 0
			end
		end
	end
	local list = #exact > 0 and exact or partial
	for _, it in ipairs(list) do
		for _, id in ipairs(it.vendors) do
			local r = ctx.byId[id]
			if not r then
				local e = ns.Index.byId[id]
				local pts = e and NpcOk(ctx, e) and Points(ctx.NpcDB, id, false, ctx.zoneOk)
				if pts then r = Add(ctx, e, pts, { kind = "VENDOR" }) end
			end
			if r then
				r.sells = r.sells or {}         -- { { id, name }, ... }: the items searched for it sells
				local have = false
				for _, s in ipairs(r.sells) do if s.name == it.name then have = true break end end
				if #r.sells < SELLS_MAX and not have then r.sells[#r.sells + 1] = { id = it.id, name = it.name, book = it.book } end
				r.rank = math.min(r.rank, it.lname == q and 0 or (IsRecipe(it.lname) and not IsRecipe(q)) and 2 or 1)
			end
			if #ctx.results >= MAX_MATCHES then return end
		end
	end
	-- (the item named, a herb or ore: its plants or veins too, beside who sells it)
	if #exact > 0 then
		local ids = {}
		for i, it in ipairs(exact) do ids[i] = it.id end
		Drops(ctx, exact[1].lname, ids, true)
	end
	return #list
end

--------------------------------------------------------------------------------
-- Bags by kind: "herb bag", "mining bag", "reagent bag" (every gathering and crafting bag),
-- "soul bag". Bags vendors sell: their vendors; bags a profession makes: who sells the pattern
--------------------------------------------------------------------------------

local BAG_KIND = { SOUL = 1, HERB = 2, ENCHANTING = 3, ENGINEERING = 4, MINING = 6, SKINNING = 7, REAGENT = 11 }
local K = BAG_KIND
local REAGENT_KINDS = { K.HERB, K.ENCHANTING, K.ENGINEERING, K.MINING, K.SKINNING, K.REAGENT }
local BAG_KIND_WORDS = {
	herb = { K.HERB }, herbs = { K.HERB }, herbing = { K.HERB }, herbalism = { K.HERB }, herbalist = { K.HERB },
	mining = { K.MINING }, mine = { K.MINING }, miner = { K.MINING }, ore = { K.MINING },
	skinning = { K.SKINNING }, skinner = { K.SKINNING },
	enchanting = { K.ENCHANTING }, enchant = { K.ENCHANTING }, enchanter = { K.ENCHANTING },
	engineering = { K.ENGINEERING }, engineer = { K.ENGINEERING },
	soul = { K.SOUL }, shard = { K.SOUL }, shards = { K.SOUL },
	reagent = REAGENT_KINDS, reagents = REAGENT_KINDS, regent = REAGENT_KINDS, regents = REAGENT_KINDS,
	reagant = REAGENT_KINDS, reagants = REAGENT_KINDS, profession = REAGENT_KINDS, professions = REAGENT_KINDS,
	tradeskill = REAGENT_KINDS, crafting = REAGENT_KINDS, gathering = REAGENT_KINDS, materials = REAGENT_KINDS,
	mats = REAGENT_KINDS,
}
local BAG_FILLER = { a = true, the = true, ["for"] = true, where = true, buy = true, to = true, my = true }
local RECIPE_PREFIXES = { "pattern: ", "formula: ", "schematic: ", "plans: ", "recipe: " }

--- the kinds of bag a search asks for ({ subclass, ... }), or nil: a bag word, a kind word, nothing else
local function BagQuery(query)
	local kinds, bag = nil, false
	for w in query:gmatch("%S+") do
		if BAG_WORDS[w] or w == "sack" or w == "sacks" or w == "satchel" or w == "satchels" then
			bag = true
		elseif BAG_KIND_WORDS[w] then
			if kinds and kinds ~= BAG_KIND_WORDS[w] then return end   -- (two kinds: not this)
			kinds = BAG_KIND_WORDS[w]
		elseif not BAG_FILLER[w] then
			return
		end
	end
	return bag and kinds or nil
end
Search.BagQuery = BagQuery

-- the vendors of a sold item, as results (each with what it sells)
local function SellItem(ctx, it, rank)
	for _, id in ipairs(it.vendors) do
		local r = ctx.byId[id]
		if not r then
			local e = ns.Index.byId[id]
			local pts = e and NpcOk(ctx, e) and Points(ctx.NpcDB, id, false, ctx.zoneOk)
			if pts then r = Add(ctx, e, pts, { kind = "VENDOR" }) r.rank = rank end
		end
		if r then
			r.sells = r.sells or {}
			local have = false
			for _, s in ipairs(r.sells) do if s.name == it.name then have = true break end end
			if not have and #r.sells < SELLS_MAX then r.sells[#r.sells + 1] = { id = it.id, name = it.name } end
			r.rank = math.min(r.rank, rank)
		end
	end
end

-- the sold items by name (lower case, apostrophes gone), once the index is built
local soldByName
local function SoldByName()
	if not soldByName then
		soldByName = {}
		for _, it in ipairs(ns.Index.items) do soldByName[it.lname] = it end
	end
	return soldByName
end

-- an item no vendor sells that a profession makes ("mechanical squirrel box"): who sells the
-- pattern, recipe, schematic or plans for it. True when one's found
MadeBy = function(ctx, lname)
	local byName = SoldByName()
	local found = false
	for _, pre in ipairs(RECIPE_PREFIXES) do
		local recipe = byName[pre .. lname]
		if recipe then
			SellItem(ctx, recipe, 1)
			found = true
		end
	end
	-- (a bar an alchemist transmutes: "Recipe: Transmute Arcanite" for Arcanite Bar)
	local metal = lname:match("^(.+) bars?$")
	local transmute = metal and byName["recipe: transmute " .. metal]
	if transmute then
		SellItem(ctx, transmute, 1)
		found = true
	end
	return found
end

-- the bags of those kinds: who sells each, or who sells the pattern for it
local function Bags(ctx, kinds)
	local want = {}
	for _, k in ipairs(kinds) do want[k] = true end
	local byName = SoldByName()
	local function Sell(it, rank) SellItem(ctx, it, rank) end
	local found = 0
	for _, b in ipairs(ns.Index.bags) do
		if want[b.kind] then
			if b.item then
				Sell(b.item, 0)
				found = found + 1
			else
				for _, pre in ipairs(RECIPE_PREFIXES) do
					local recipe = byName[pre .. b.lname]
					if recipe then
						Sell(recipe, 1)
						found = found + 1
					end
				end
			end
		end
		if #ctx.results >= MAX_MATCHES then break end
	end
	return found
end

-- a skill book search? Returns the subclass asked for (false: any skill), or nil if it isn't one
local function BookQuery(query)
	local sub, book = false, false
	for word in query:gmatch("%S+") do
		if BOOK_WORDS[word] then book = true end
		local p = BOOK_PROFS[word]
		if p then
			if sub and sub ~= p then return nil end
			sub = p
		elseif not (BOOK_WORDS[word] or BOOK_FILLER[word] or word:match("^%d+$")) then
			return nil
		end
	end
	if book then return sub end
end

-- the vendors of the skill books (of one skill, or all)
local function Books(ctx, sub)
	for _, b in ipairs(ns.Index.skillBooks) do
		if not sub or b.sub == sub then
			for _, id in ipairs(b.vendors) do
				local r = ctx.byId[id]
				if not r then
					local e = ns.Index.byId[id]
					local pts = e and NpcOk(ctx, e) and Points(ctx.NpcDB, id, false, ctx.zoneOk)
					if pts then r = Add(ctx, e, pts, { kind = "VENDOR" }) r.rank = 0 end
				end
				if r then
					r.sells = r.sells or {}
					r.sells[#r.sells + 1] = { id = b.id, name = b.name, book = b }
				end
			end
		end
	end
end

-- Forever's transports ("boat", "zeppelin"): the docks and towers, each named for where it goes
-- (a city's zone: "zeppelin to orgrimmar" is the one to the tower in Durotar)
local CITY_HOME = { [1454] = 1411, [1458] = 1420, [1456] = 1412, [1453] = 1429, [1455] = 1426, [1457] = 1438 }
local function Transports(ctx, which, dest)
	local legs = ns.Route and ns.Route.LEGS
	if not legs then return end
	local side = ns.faction == "Alliance" and "A" or ns.faction == "Horde" and "H" or nil
	local seen = {}
	local destZone = dest and (dest.kind == "city" and CITY_HOME[dest.id] or dest.id)
	local destName = dest and lower(dest.name)
	for i, l in ipairs(legs) do
		if (which == "all" or l[7] == which) and (not l[8] or l[8] == side) then
			local key = ("%d:%.1f:%.1f:%d"):format(l[1], l[2], l[3], l[4])
			local where = ns.Route.PlaceName and ns.Route.PlaceName(l[4], l[5] / 100, l[6] / 100) or ns.ZoneName(l[4]) or "?"
			-- (to somewhere: the ones that land there, in that town or zone)
			local goes = not dest or l[4] == destZone or lower(where) == destName
			if goes and not seen[key] and (not ctx.zoneOk or ctx.zoneOk(l[1])) then
				seen[key] = true
				local name = (TRANSPORT_NAMES[l[7]] or TRANSPORT_NAMES.boat):format(where)
				local r = Add(ctx, { obj = true, id = -(7000000 + i), name = name }, { { ui = l[1], x = l[2], y = l[3] } },
					{ kind = "TRANSPORT", label = ns.ZoneName(l[1]), icon = TRANSPORT_ICON[l[7]] })
				r.rank = 0
			end
		end
	end
end

local function Objects(ctx, kind)
	local ObjDB = ns.Index.ObjectDB()
	if not ObjDB then return end
	for _, o in ipairs(ns.Index.objects) do
		if o.kind == kind then
			local pts = Points(ObjDB, o.id, true, ctx.zoneOk)
			if pts then Add(ctx, o, pts, { kind = kind }) end
			if #ctx.results >= MAX_MATCHES then return end
		end
	end
end

-- Quests by name: who starts them ("theldurin the lost", "quest the lost pilot"). A quest an
-- item starts: what drops the item. The names are read from QuestieDB the first time a quest
-- is searched for

local QUEST_MAX = 30         -- quests matched at most (a vaguer search: say so)
local DROPS_MAX = 12         -- NPCs or objects shown for an item that starts a quest
-- the races of each faction (requiredRaces): a quest for the other faction's left out
local RACES = { Alliance = 1 + 4 + 8 + 64 + 1024, Horde = 2 + 16 + 32 + 128 + 512 }

local questNames             -- { { normalised name, name, { ids } }, ... }

local function QuestDB() return _G.QuestDB or (_G.LibQuestieDB and _G.LibQuestieDB.Quest) end

-- a name as compared: lower case, apostrophes gone, anything else not a letter or digit a space
local function QuestNorm(s)
	s = lower(s):gsub("'", ""):gsub("[^%w]+", " ")
	return strtrim(s)
end

local function QuestNames()
	if questNames then return questNames end
	local QDB = QuestDB()
	if not (QDB and QDB.GetAllIds and QDB.Get) then return {} end
	questNames = {}
	local byName = {}
	for _, id in ipairs(QDB.GetAllIds()) do
		local ok, name = pcall(QDB.Get, id, "name")
		if ok and type(name) == "string" and name ~= "" then
			local n = QuestNorm(name)
			local q = byName[n]
			if q then
				q[3][#q[3] + 1] = id
			else
				q = { n, name, { id }, ns.Squash(n) }
				byName[n] = q
				questNames[#questNames + 1] = q
			end
		end
	end
	return questNames
end

-- the quests whose names match: the whole name (exact), or each word typed starting a word of it
local function QuestMatches(query, exactOnly)
	local n = QuestNorm(query)
	if #n < 3 then return {}, {} end
	local words = {}
	for w in n:gmatch("%S+") do words[#words + 1] = w end
	local exact, partial = {}, {}
	local nsq = ns.Squash(n)
	for _, q in ipairs(QuestNames()) do
		if q[1] == n or q[4] == nsq then
			exact[#exact + 1] = q
		elseif not exactOnly then
			local hay, all = " " .. q[1], true
			for _, w in ipairs(words) do
				if not find(hay, " " .. w, 1, true) then all = false break end
			end
			-- (or typed run together, or split where it isn't: "lostpilot", "mid night")
			if not all and #nsq >= 6 and find(q[4], nsq, 1, true) then all = true end
			if all then partial[#partial + 1] = q end
		end
	end
	-- (nothing like it: the names a slip or two off the whole of it, the closest)
	if #exact == 0 and #partial == 0 and not exactOnly and #n >= 6 and ns.Suggest and ns.Suggest.Distance then
		local cap = #n >= 14 and 3 or 2
		local best, n1 = cap + 1, n:byte(1)
		for _, q in ipairs(QuestNames()) do
			local l = q[1]
			if l:byte(1) == n1 and math.abs(#l - #n) <= cap then
				local d = ns.Suggest.Distance(n, l, cap)
				if d < best then best, exact = d, { q }
				elseif d == best and d <= cap then exact[#exact + 1] = q end
			end
		end
		if best > cap then exact = {} end
	end
	return exact, partial
end

-- a quest's for your faction (or either)
local function QuestForYou(QDB, id)
	if ns.db.otherFaction then return true end
	local mask = RACES[ns.faction]
	local ok, races = pcall(QDB.Get, id, "requiredRaces")
	if not (mask and ok and type(races) == "number" and races > 0) then return true end
	local okB, both = pcall(band, races % 4294967296, mask)   -- (newer races sit above 32 bits)
	return not okB or both ~= 0
end

Search.QuestForYou = QuestForYou

-- a search that's a place, or as like one or more as to be offered ("plaguelands": Western and
-- Eastern): part of a quest's name doesn't win over it
local function LikeAPlace(query)
	if Search.Place(query) or Search.PlaceStarting(query) then return true end
	local Sg = ns.Suggest
	if not (Sg and Sg.LikePlace) then return false end
	local one, several = Sg.LikePlace(query)
	return one ~= nil or several ~= nil
end

-- a list of ids as read (one id alone, as a number, too)
local function Ids(v)
	if type(v) == "number" then return { v } end
	return type(v) == "table" and v or {}
end

-- a quest on a marker: its title, as the tooltip lists it ("[42] Krol'dok Moulding", "The Lost
-- Pilot: Faded Journal drops, which starts it"), once; and with it the quest's plain name, to
-- show the quest by on a right-click (Pins.lua), as searching for it does. name: the title's own
-- when it isn't given
-- (on Search, not a local of the file's: Lua's limits on a chunk's locals and upvalues)
function Search.TitleQuest(r, title, name)
	r.quests = r.quests or {}
	for _, t in ipairs(r.quests) do if t == title then return false end end
	r.quests[#r.quests + 1] = title
	r.questNames = r.questNames or {}
	r.questNames[#r.quests] = name or title
	return true
end

-- who starts the quests in list (and what drops the items that do): on the map, each with the
-- quests' names. rank: the results' (0 for the quest named in full). A quest's entry: { its name
-- normalised, its title, { ids }, …, name = its plain name when the title says more }
local function QuestStarters(ctx, list, rank)
	local QDB, ItemDB, ObjDB = QuestDB(), ns.Index.ItemDB(), ns.Index.ObjectDB()
	local found = 0
	local function Put(e, isObj, id, title, name)
		local r = ctx.byId[e.id]
		if not r then
			local pts = Points(isObj and ObjDB or ctx.NpcDB, id, isObj, ctx.zoneOk)
			if not pts then return end
			r = Add(ctx, e, pts, { kind = "QUEST", quests = {} })
			r.rank = rank
		end
		r.kind, r.questStart = "QUEST", true
		r.rank = math.min(r.rank, rank)
		if Search.TitleQuest(r, title, name) then found = found + 1 end
	end
	local function Npc(id, title, name)
		local e = ns.Index.byId[id]
		if e and NpcOk(ctx, e) then Put(e, false, id, title, name) end
	end
	local function Obj(id, title, name)
		if not ObjDB then return end
		local ok, oname = pcall(ObjDB.Get, id, "name")
		if ok and type(oname) == "string" then
			Put(ctx.byId[-id] and ctx.byId[-id].entry or { obj = true, id = -id, objectId = id, name = oname }, true, id, title, name)
		end
	end
	for _, q in ipairs(list) do
		local name = q.name or q[2]
		for _, id in ipairs(q[3]) do
			local ok, by = pcall(QDB.Get, id, "startedBy")
			local mine = QuestForYou(QDB, id)
			if not mine then ctx.otherSide = q[2] end
			if ok and type(by) == "table" and mine then
				for _, nid in ipairs(Ids(by[1])) do Npc(nid, q[2], name) end
				for _, oid in ipairs(Ids(by[2])) do Obj(oid, q[2], name) end
				-- (an item starts it: what drops the item)
				for _, iid in ipairs(ItemDB and Ids(by[3]) or {}) do
					local okN, item = pcall(ItemDB.Get, iid, "name")
					local title = L["%s: %s drops, which starts it"]:format(q[2], okN and type(item) == "string" and item or "?")
					local okD, npcs = pcall(ItemDB.Get, iid, "npcDrops")
					local n = 0
					for _, nid in ipairs(okD and Ids(npcs) or {}) do
						if n >= DROPS_MAX then break end
						n = n + 1
						Npc(nid, title, name)
					end
					local okO, objs = pcall(ItemDB.Get, iid, "objectDrops")
					for _, oid in ipairs(okO and Ids(objs) or {}) do
						if n >= DROPS_MAX then break end
						n = n + 1
						Obj(oid, title, name)
					end
				end
			end
		end
		if #ctx.results >= MAX_MATCHES then break end
	end
	return found
end

--------------------------------------------------------------------------------
-- An item no vendor sells: where it's found. Gathered (ore, herbs): every vein or plant of it in
-- a zone, the zone with the most near you. Dropped: its mobs' spawns gathered into areas (the
-- more often a mob drops it, the more it counts), one drawn on the map as a quest's area is
-- (Areas.lua): of the big ones, the nearest you
--------------------------------------------------------------------------------

local DROP_SOURCES = 6        -- named in its tooltip at most
local DROP_ZONES = 4          -- other zones it drops in, named
local SPOTS_MAX = 6           -- areas drawn in the zone at most (each with its marker) ...
local SPOT_SHARE = 0.25       -- ... each at least this much of the best one's score ...
local SPOT_MIN = 5            -- ... and this many spawns
-- (an object with one of these in its name holds random loot: not where an item's found)
local CONTAINERS = { "chest", "box", "crate", "footlocker", "coffer", "grave", "trunk", "cache", "barrel" }

local RATE_FLOOR = 5          -- %: mobs that drop it less often than this left out ...
local RATE_SHARE = 0.25       -- (... or than this share of the best rate, when that's lower)

-- how often each mob drops each item (Wowhead's, as QuestieDB keeps it for Questie):
-- { [itemId] = { [npcId] = percent } }, or false. Questie's decoded copy when it has one, else
-- read once from QuestieDB's
local dropRates, dropRatesOwn   -- (own: read out of QuestieDB's text by MapSeek, and so MapSeek's to keep or let go)
local function DropRates()
	if dropRates ~= nil then return dropRates end
	dropRates = false
	local loader = _G.QuestieLoader
	if loader and loader.ImportModule then
		local ok, mod = pcall(loader.ImportModule, loader, "DropDB")
		if ok and type(mod) == "table" and type(mod.tableWowhead) == "table" then
			dropRates = mod.tableWowhead
			return dropRates
		end
	end
	local S = _G.LibQuestieDB and LibQuestieDB.Support
	local mod = S and S.Get and S.Get("QuestieClassicItemDrops")
	if mod and type(mod.wowheadData) == "string" and loadstring then
		local fn = loadstring(mod.wowheadData)
		local ok, t = false, nil
		if fn then ok, t = pcall(fn) end
		if ok and type(t) == "table" then dropRates, dropRatesOwn = t, true end
	end
	return dropRates
end

Search.DropRates = function() return DropRates() end

local function Container(l)
	for _, w in ipairs(CONTAINERS) do if find(l, w, 1, true) then return true end end
	return false
end

-- ids: the items (else the unsold ones of the name); sold: a vendor sells it, so only where it's
-- gathered is added (a herb's plants, beside its vendors)
local dropCache, dropCacheN = {}, 0   -- lname -> { pts = {...}, clusters = {...} } (no zone limit, this faction)
local DROP_CACHE_MAX = 3

--- what searches have kept to be quick a second time, let go (the map's been closed a while):
--- where things drop, and the drop chances when they're MapSeek's own copy. Read again when asked
function Search.Release()
	dropCache, dropCacheN = {}, 0
	-- (the drop rates MapSeek read out of QuestieDB's text itself: let go only when Questie's
	-- there to hand over its own copy next time. Without Questie that's a megabyte of text read
	-- again, a pause on the next item searched for)
	if dropRatesOwn and _G.QuestieLoader then dropRates, dropRatesOwn = nil, nil end
	if ns.Index and ns.Index.ReleaseSpawns then ns.Index.ReleaseSpawns() end
end

Drops = function(ctx, lname, ids, sold)
	local ItemDB, ObjDB = ns.Index.ItemDB(), ns.Index.ObjectDB()
	if not (ItemDB and ns.Areas and ns.Index.UnsoldIds) then return end
	local cacheKey = not ctx.zoneOk and (lname .. "|" .. tostring(ns.faction) .. "|" .. tostring(sold)) or nil
	local cached = cacheKey and dropCache[cacheKey]
	local nodes, title, itemId, nodePts, mobPts, rated
	if cached then
		nodes, title, itemId, nodePts, mobPts, rated = cached.nodes, cached.title, cached.itemId, cached.nodePts, cached.mobPts, cached.rated
	else
		local objs, npcs = {}, {}
		nodes, title, itemId = {}, nil, nil
		local rateOf = {}
		rated = false
		local seenN, seenO = {}, {}
		local rates = DropRates()
		for _, iid in ipairs(ids or ns.Index.UnsoldIds(lname)) do
			local okN, name = pcall(ItemDB.Get, iid, "name")
			if okN and type(name) == "string" and not title then title, itemId = name, iid end
			-- (the mobs it drops from: with how often, when that's known; else as QuestieDB lists them)
			local known = rates and type(rates[iid]) == "table" and rates[iid]
			if known then
				for id, rate in pairs(known) do
					if type(id) == "number" and id > 0 and type(rate) == "number" then
						rated = true
						if not seenN[id] then seenN[id] = true npcs[#npcs + 1] = id end
						rateOf[id] = math.max(rateOf[id] or 0, rate)
					end
				end
			end
			local okD, list = pcall(ItemDB.Get, iid, "npcDrops")
			for _, id in ipairs(okD and Ids(list) or {}) do
				if not seenN[id] then seenN[id] = true npcs[#npcs + 1] = id end
			end
			local okO, olist = pcall(ItemDB.Get, iid, "objectDrops")
			local boxes, others = 0, {}
			for _, id in ipairs(okO and ObjDB and Ids(olist) or {}) do
				if not seenO[id] then
					seenO[id] = true
					local ok, oname = pcall(ObjDB.Get, id, "name")
					if ok and type(oname) == "string" then
						local l = lower(oname):gsub("'", "")
						if Container(l) then
							boxes = boxes + 1
						elseif find(l, "vein", 1, true) or find(l, "deposit", 1, true) or find(ns.Squash(l), ns.Squash(lname), 1, true) then
							nodes[#nodes + 1] = { id, oname }   -- (a vein, or a herb: what it's gathered from)
						else
							others[#others + 1] = { id, oname }
						end
					end
				end
			end
			-- (mostly in chests: it's random loot, as cloth is; the odd other object listed is too)
			if boxes <= #others then
				for _, o in ipairs(others) do objs[#objs + 1] = o end
			end
		end

		local function Take(DB, id, name, wt, into)
			for _, p in ipairs(Points(DB, id, true, ctx.zoneOk) or {}) do
				p.src, p.wt, p.id, p.rate = name, wt, id, rated and wt or nil
				into[#into + 1] = p
			end
		end
		-- gathered (ore, herbs): every vein or plant of it
		nodePts = {}
		for _, o in ipairs(nodes) do Take(ObjDB, o[1], o[2], 1, nodePts) end
		-- dropped (by mobs, or things not chests): their spawns, for the areas. Mobs friendly to
		-- you are left out (you can't kill them); so are those it seldom drops from. (A herb a
		-- vendor sells: its plants are enough. An ore's mobs, when how often's unknown: the long
		-- tail of what drops it once in a while, "heavy stone: panthers"; its deposits are enough)
		mobPts = {}
		if not sold and (#nodePts == 0 or rated) then
			local best = 0
			for _, id in ipairs(npcs) do best = math.max(best, rateOf[id] or 0) end
			-- (with plants or veins of it, a mob has to drop it fairly often to be worth it at all)
			local floorRate = #nodePts > 0 and RATE_FLOOR or math.min(RATE_FLOOR, best * RATE_SHARE)
			local mine = ns.faction == "Alliance" and "A" or ns.faction == "Horde" and "H" or nil
			for _, id in ipairs(npcs) do
				local rate = rateOf[id]
				if not rated or (rate and rate >= floorRate) then
					local ok, name = pcall(ctx.NpcDB.Get, id, "name")
					local okF, friend = pcall(ctx.NpcDB.Get, id, "friendlyToFaction")
					-- (friendly to your side only: "AH", to both, is the data's word for a neutral
					-- beast too, a yellow one you can kill: Tirisfal's bats)
					local friendly = mine and okF and friend == mine
					if ok and type(name) == "string" and not friendly then Take(ctx.NpcDB, id, name, rate or 1, mobPts) end
				end
			end
			if #mobPts == 0 and #nodePts == 0 then
				for _, o in ipairs(objs) do Take(ObjDB, o[1], o[2], 1, mobPts) end
			end
		end
		if cacheKey then
			dropCacheN = dropCacheN + 1
			if dropCacheN > DROP_CACHE_MAX then dropCache, dropCacheN = {}, 1 end
			cached = { nodes = nodes, title = title, itemId = itemId, nodePts = nodePts, mobPts = mobPts, rated = rated }
			dropCache[cacheKey] = cached
		end
	end
	if #nodePts == 0 and #mobPts == 0 then return end
	-- (its own icon: the game's for any item, read or not yet. None known: the drop marker's own)
	local icon = itemId and ns.ItemIcon and ns.ItemIcon(itemId) or nil
	if icon == 134400 then icon = nil end
	local info = { name = title or lname }

	-- gathered: a marker on each vein or plant in the zone picked (yours, when it has a fair number)
	if #nodePts > 0 then
		local zone, zones = ns.Areas.PickZone(nodePts)
		if zone then
			local byObj, placed = {}, 0
			for _, p in ipairs(nodePts) do
				if p.ui == zone then
					local r = byObj[p.id]
					if not r then
						local e = ctx.byId[-p.id] and ctx.byId[-p.id].entry or { obj = true, id = -p.id, objectId = p.id, name = p.src }
						local qlines, forQuest
						if not ctx.forQuest then qlines, forQuest = QuestsNeeding(itemId) end
						r = Add(ctx, e, {}, { kind = "DROPS", label = L["Gathered: %s"]:format(title or lname), icon = icon, gathered = true,
							lines = qlines })
						r.rank, r.quest = 0, forQuest
						byObj[p.id] = r
					end
					r.points[#r.points + 1] = { ui = p.ui, x = p.x, y = p.y }
					placed = placed + 1
				end
			end
			for _, r in pairs(byObj) do
				for _, p in ipairs(r.points) do if ctx.priority[p.ui] then r.near = true break end end
			end
			info.nodes, info.zone, info.nodeMore = placed, ns.ZoneName(zone) or "?", zones - 1
		end
	end

	-- dropped: the areas, of the big ones the nearest you, every good spot in that zone
	if #mobPts > 0 then
		local clusters = cached and cached.clusters
		if not clusters then
			clusters = ns.Areas.Clusters(mobPts)
			if cached then cached.clusters = clusters end
		end
		local c = ns.Areas.Pick(clusters)
		if c then
			-- the other zones it drops in, the most first
			local inZone, others = {}, {}
			for _, k in ipairs(clusters) do inZone[k.ui] = (inZone[k.ui] or 0) + k.wt end
			for ui, n in pairs(inZone) do if ui ~= c.ui then others[#others + 1] = { ui = ui, n = n } end end
			table.sort(others, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.ui < b.ui end)
			-- the other good spots in that zone too, to go between: the best first
			local spots = { c }
			for _, k in ipairs(clusters) do
				if k ~= c and k.ui == c.ui and #k.pts >= SPOT_MIN and k.score >= c.score * SPOT_SHARE then spots[#spots + 1] = k end
			end
			table.sort(spots, function(a, b) return a.score > b.score end)
			for i = SPOTS_MAX + 1, #spots do spots[i] = nil end
			local also
			if #others > 0 then
				local z = {}
				for i = 1, math.min(DROP_ZONES, #others) do z[i] = ns.ZoneName(others[i].ui) or "?" end
				also = table.concat(z, ", ")
				if #others > DROP_ZONES then also = also .. " " .. L["and %d more"]:format(#others - DROP_ZONES) end
			end
			for i, k in ipairs(spots) do
				-- what it drops from there, the most first (and how often, when known)
				local count, names, rateBy = {}, {}, {}
				for _, p in ipairs(k.pts) do
					if not count[p.src] then names[#names + 1] = p.src count[p.src] = 0 end
					count[p.src] = count[p.src] + p.wt
					if rated then rateBy[p.src] = p.rate end
				end
				table.sort(names, function(a, b) if count[a] ~= count[b] then return count[a] > count[b] end return a < b end)
				local lines, forQuest   -- (the quests it's for first, then the mobs)
				if not ctx.forQuest then lines, forQuest = QuestsNeeding(itemId) end
				lines = lines or {}
				lines[#lines + 1] = { " " }
				lines[#lines + 1] = { L["Drops from:"], 1, 0.82, 0.1 }
				for j, n in ipairs(names) do
					if j > DROP_SOURCES then
						lines[#lines + 1] = { "  " .. L["and %d more"]:format(#names - DROP_SOURCES), 0.8, 0.8, 0.8 }
						break
					end
					local rate = rateBy[n]
					lines[#lines + 1] = { "  " .. n .. (rate and (" (%d%%)"):format(math.floor(rate + 0.5)) or ""), 1, 1, 1 }
				end
				if also then
					lines[#lines + 1] = { " " }
					lines[#lines + 1] = { L["Also drops in: %s"]:format(also), 0.75, 0.75, 0.75 }
				end
				local mid = ns.Areas.Middle(k)
				local e = { obj = true, id = -(1000000 * i + (itemId or 0)), name = title or lname }
				k.outline = k.outline or ns.Areas.Outline(k)
				local area = {}
				for kk, v in pairs(k.outline) do area[kk] = v end
				area.best = i == 1 and #spots > 1   -- (the best of several: drawn purple)
				-- (what it's called when pinned: the item, its main mobs there, its middle; and a key to
				-- know it again by)
				area.name, area.icon, area.mid = title or lname, icon, { mid.x, mid.y }
				area.label = table.concat({ names[1], names[2] }, ", ")
				area.key = ("%d:%.2f:%.2f:%d"):format(k.ui, area.verts[1] or 0, area.verts[2] or 0, itemId or 0)
				local r = Add(ctx, e, { { ui = k.ui, x = mid.x, y = mid.y } }, { kind = "DROPS", lines = lines, area = area,
					label = (i == 1 and #spots > 1) and L["Dropped: %s (most here)"]:format(title or lname) or L["Dropped: %s"]:format(title or lname),
					icon = icon })
				r.rank, r.quest = 0, forQuest
			end
			info.spots, info.spotZone, info.spotMore = #spots, ns.ZoneName(c.ui) or "?", #others
		end
	end
	if info.nodes or info.spots then
		if not sold then ctx.unsold = nil end
		ctx.drops = info
	end
end

-- the quests each item is for: the ones that need it (an objective) and the ones that hand it
-- out (their giver gives it with the quest). Read from every quest the first time it's wanted
local questNeeds, questGives, questStarts   -- [itemId] = { questId, ... }
local function QuestItems()
	if questNeeds then return questNeeds, questGives, questStarts end
	questNeeds, questGives, questStarts = {}, {}, {}
	local QDB = QuestDB()
	if not (QDB and QDB.GetAllIds and QDB.Get) then return questNeeds, questGives, questStarts end
	for _, id in ipairs(QDB.GetAllIds()) do
		local ok, obj = pcall(QDB.Get, id, "objectives")
		local items = ok and type(obj) == "table" and obj[3]
		if type(items) == "table" then
			for _, it in ipairs(items) do
				local iid = type(it) == "table" and it[1] or it
				if type(iid) == "number" then
					questNeeds[iid] = questNeeds[iid] or {}
					questNeeds[iid][#questNeeds[iid] + 1] = id
				end
			end
		end
		local okS, src = pcall(QDB.Get, id, "sourceItemId")
		if okS and type(src) == "number" and src > 0 then
			questGives[src] = questGives[src] or {}
			questGives[src][#questGives[src] + 1] = id
		end
		-- (a quest an item starts, read and accepted: a letter, a crate's manifest)
		local okB, by = pcall(QDB.Get, id, "startedBy")
		local starters = okB and type(by) == "table" and by[3]
		if type(starters) == "table" then
			for _, iid in ipairs(starters) do
				if type(iid) == "number" then
					questStarts[iid] = questStarts[iid] or {}
					questStarts[iid][#questStarts[iid] + 1] = id
				end
			end
		end
	end
	return questNeeds, questGives, questStarts
end

-- tooltip lines naming the quests an item is for ("Quest item for:", "Starts the quest:"),
-- each with where you are with it (what the game says of it in your log, or that it's done), or
-- nil; and the quest to show for it (the one in your log, else the first)
QuestsNeeding = function(itemId)
	if not itemId then return end
	local needs, _, starts = QuestItems()
	local QDB = QuestDB()
	if not (QDB and (needs[itemId] or starts[itemId])) then return end
	local ItemDB = ns.Index.ItemDB()
	local okI, itemName = false, nil
	if ItemDB then okI, itemName = pcall(ItemDB.Get, itemId, "name") end
	itemName = okI and type(itemName) == "string" and itemName or nil
	local lines, n, seen, pick, pickOn = {}, 0, {}, nil, false
	for _, group in ipairs({ { needs[itemId], L["Quest item for:"] }, { starts[itemId], L["Starts the quest:"] } }) do
		local list, headed = group[1], false
		for _, qid in ipairs(list or {}) do
			if QuestForYou(QDB, qid) then
				local ok, name = pcall(QDB.Get, qid, "name")
				-- (a chain's quests with one name: once)
				if ok and type(name) == "string" and not seen[name] then
					seen[name] = true
					n = n + 1
					if n > 6 then lines[#lines + 1] = { "  " .. L["and %d more"]:format(#list - 6), 0.8, 0.8, 0.8 } break end
					if not headed then
						headed = true
						lines[#lines + 1] = { " " }
						lines[#lines + 1] = { group[2], 1, 0.82, 0.1 }
					end
					lines[#lines + 1] = { "  " .. name, 1, 1, 1 }
					local state, on = nil, false
					if Search.QuestItemState then state, on = Search.QuestItemState(qid, itemName) end
					if state then lines[#lines + 1] = { "    " .. state, 0.8, 0.8, 0.8 } end
					if not pick or (on and not pickOn) then pick, pickOn = { id = qid, name = name }, on end
				end
			end
		end
	end
	return n > 0 and lines or nil, pick
end

-- an item no vendor sells that a quest hands you ("marshal mcbride's documents"): who gives
-- that quest, named for it
QuestGives = function(ctx, lname)
	local ItemDB, QDB = ns.Index.ItemDB(), QuestDB()
	if not (ItemDB and QDB and ns.Index.UnsoldIds) then return end
	local _, gives = QuestItems()
	local list, seen = {}, {}
	for _, iid in ipairs(ns.Index.UnsoldIds(lname)) do
		local okN, item = pcall(ItemDB.Get, iid, "name")
		for _, qid in ipairs(gives[iid] or {}) do
			if not seen[qid] then
				seen[qid] = true
				local okT, qname = pcall(QDB.Get, qid, "name")
				if okT and type(qname) == "string" then
					local title = L["%s (gives %s)"]:format(qname, okN and type(item) == "string" and item or lname)
					list[#list + 1] = { QuestNorm(qname), title, { qid }, name = qname }
				end
			end
		end
	end
	if #list > 0 then QuestStarters(ctx, list, 1) end
end

-- an item no vendor sells that a quest rewards ("nat pagle's extreme angler fc-5000"): who
-- starts that quest, the quest named for it
-- quests the data doesn't link to the item they reward (item id -> quest ids)
local REWARD_FIXES = {
	[19022] = { 6607 },   -- Nat Pagle's Extreme Angler FC-5000: Nat Pagle's own quest (the data has the Horde one only)
}

QuestRewards = function(ctx, lname)
	local ItemDB, QDB = ns.Index.ItemDB(), QuestDB()
	if not (ItemDB and QDB and ns.Index.UnsoldIds) then return end
	local list, seen = {}, {}
	for _, iid in ipairs(ns.Index.UnsoldIds(lname)) do
		local okN, item = pcall(ItemDB.Get, iid, "name")
		local okQ, quests = pcall(ItemDB.Get, iid, "questRewards")
		local qids = okQ and Ids(quests) or {}
		for _, extra in ipairs(REWARD_FIXES[iid] or {}) do qids[#qids + 1] = extra end
		for _, qid in ipairs(qids) do
			if not seen[qid] then
				seen[qid] = true
				local okT, qname = pcall(QDB.Get, qid, "name")
				if okT and type(qname) == "string" then
					local title = L["%s (rewards %s)"]:format(qname, okN and type(item) == "string" and item or lname)
					list[#list + 1] = { QuestNorm(qname), title, { qid }, name = qname }
				end
			end
		end
	end
	if #list > 0 then QuestStarters(ctx, list, 1) end
end

-- who a quest's handed in to ("turn in the lost pilot"): on the map, each with the quests' names
local function QuestEnders(ctx, list, rank)
	local QDB, ObjDB = QuestDB(), ns.Index.ObjectDB()
	for _, q in ipairs(list) do
		local title = q[2]
		local function Put(e, isObj, id)
			local r = ctx.byId[e.id]
			if not r then
				local pts = Points(isObj and ObjDB or ctx.NpcDB, id, isObj, ctx.zoneOk)
				if not pts then return end
				r = Add(ctx, e, pts, { kind = "QUEST_END", quests = {}, questEnd = true })
				r.rank = rank
			end
			Search.TitleQuest(r, title, q.name or title)
		end
		for _, id in ipairs(q[3]) do
			local ok, by = pcall(QDB.Get, id, "finishedBy")
			local mine = QuestForYou(QDB, id)
			if not mine then ctx.otherSide = title end
			if ok and type(by) == "table" and mine then
				for _, nid in ipairs(Ids(by[1])) do
					local e = ns.Index.byId[nid]
					if e and NpcOk(ctx, e) then Put(e, false, nid) end
				end
				for _, oid in ipairs(ObjDB and Ids(by[2]) or {}) do
					local okN, name = pcall(ObjDB.Get, oid, "name")
					if okN and type(name) == "string" then
						Put(ctx.byId[-oid] and ctx.byId[-oid].entry or { obj = true, id = -oid, objectId = oid, name = name }, true, oid)
					end
				end
			end
		end
		if #ctx.results >= MAX_MATCHES then break end
	end
end

-- "turn in the lost pilot", "hand in ...", "where do i turn in ...", "the lost pilot turn in":
-- the quest's name, or nil
local function TurnInQuery(query)
	local q = query:gsub("^where do i ", ""):gsub("^where to ", ""):gsub("^where ", "")
	local name = q:match("^turn ?ins? (.+)$") or q:match("^hand ?ins? (.+)$")
		or q:match("^(.+) turn ?ins?$") or q:match("^(.+) hand ?ins?$")
	if not name then return end
	name = name:gsub("^the quest ", ""):gsub("^quest ", "")
	return #name >= 3 and name or nil
end

--- every quest's name (each once): { { normalised name, name, { ids } }, ... }
function Search.QuestNames() return QuestNames() end

--- quests whose names start with or hold what's typed, for the suggestions: { name, ... }
function Search.QuestSuggest(text, max)
	local n = QuestNorm(text or "")
	if #n < 4 or not QuestDB() then return {} end
	local out = {}
	for _, q in ipairs(QuestNames()) do
		if q[1]:sub(1, #n) == n then
			out[#out + 1] = q[2]
			if #out >= max then break end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Weapon skills: who teaches them ("staff trainer", "polearm training", "2h sword trainer").
-- The weapon masters of the cities, and the weapons each teaches (item subclasses of weapons:
-- the game names them in your language)
--------------------------------------------------------------------------------

local W = { AXE1 = 0, AXE2 = 1, BOW = 2, GUN = 3, MACE1 = 4, MACE2 = 5, POLEARM = 6, SWORD1 = 7, SWORD2 = 8,
	STAFF = 10, FIST = 13, DAGGER = 15, THROWN = 16, CROSSBOW = 18 }
local WEAPON_NAMES = { [0] = "One-Handed Axes", "Two-Handed Axes", "Bows", "Guns", "One-Handed Maces",
	"Two-Handed Maces", "Polearms", "One-Handed Swords", "Two-Handed Swords", [10] = "Staves",
	[13] = "Fist Weapons", [15] = "Daggers", [16] = "Thrown", [18] = "Crossbows" }

local WEAPON_MASTERS = {
	[11867] = { W.CROSSBOW, W.DAGGER, W.SWORD1, W.SWORD2, W.POLEARM, W.STAFF },          -- Woo Ping, Stormwind
	[13084] = { W.DAGGER, W.CROSSBOW, W.THROWN },                                         -- Bixi Wobblebonk, Ironforge
	[11865] = { W.GUN, W.AXE1, W.AXE2, W.MACE1, W.MACE2, W.FIST },                        -- Buliwyf Stonehand, Ironforge
	[11866] = { W.DAGGER, W.FIST, W.STAFF, W.BOW, W.THROWN },                             -- Ilyenia Moonfire, Darnassus
	[2704] = { W.BOW, W.THROWN, W.AXE1, W.AXE2, W.STAFF },                                -- Hanashi, Orgrimmar
	[11868] = { W.BOW, W.THROWN, W.AXE1, W.AXE2, W.DAGGER, W.FIST },                      -- Sayoc, Orgrimmar
	[11869] = { W.GUN, W.MACE1, W.MACE2, W.STAFF },                                       -- Ansekhwa, Thunder Bluff
	[11870] = { W.CROSSBOW, W.DAGGER, W.SWORD1, W.SWORD2, W.POLEARM },                    -- Archibald, Undercity
}

-- the words for each weapon (an axe, mace or sword: both kinds, unless one- or two-handed is said)
local WEAPON_WORDS = {
	staff = { W.STAFF }, staves = { W.STAFF }, staffs = { W.STAFF },
	polearm = { W.POLEARM }, polearms = { W.POLEARM }, spear = { W.POLEARM },
	bow = { W.BOW }, bows = { W.BOW }, archery = { W.BOW },
	crossbow = { W.CROSSBOW }, crossbows = { W.CROSSBOW }, xbow = { W.CROSSBOW },
	gun = { W.GUN }, guns = { W.GUN },
	dagger = { W.DAGGER }, daggers = { W.DAGGER },
	fist = { W.FIST }, fists = { W.FIST },
	thrown = { W.THROWN }, throwing = { W.THROWN },
	axe = { W.AXE1, W.AXE2 }, axes = { W.AXE1, W.AXE2 },
	mace = { W.MACE1, W.MACE2 }, maces = { W.MACE1, W.MACE2 },
	sword = { W.SWORD1, W.SWORD2 }, swords = { W.SWORD1, W.SWORD2 },
}
local ONE_HAND = { ["1h"] = true, one = true, ["one-handed"] = true, ["one-hand"] = true, onehanded = true, onehand = true }
local TWO_HAND = { ["2h"] = true, two = true, ["two-handed"] = true, ["two-hand"] = true, twohanded = true, twohand = true }
local HANDED = { handed = true, hand = true }
-- what makes it a search for training, not for the weapon itself ("staff" alone: the staves sold)
local TRAIN_WORDS = { trainer = true, trainers = true, training = true, train = true, skill = true, skills = true,
	master = true, masters = true, teacher = true, teaches = true, learn = true }
local WEAPON_FILLER = { weapon = true, weapons = true, ["in"] = true, the = true, a = true, to = true, where = true }

--- the weapon a search asks to be taught: { subclass, ... }, or "all" ("weapon trainer"), or nil
local function WeaponQuery(query)
	-- (words players split: "pole arm", "cross bow", "2 handed", "1 hand")
	query = (" " .. query .. " "):gsub(" pole ?arms? ", " polearm "):gsub(" cross ?bows? ", " crossbow ")
		:gsub(" ([12]) ?h(and?e?d?) ", " %1h ")
	local skills, train, hands, weaponWord = nil, false, nil, false
	for w in query:gmatch("%S+") do
		if TRAIN_WORDS[w] then train = true
		elseif ONE_HAND[w] then hands = 1
		elseif TWO_HAND[w] then hands = 2
		elseif HANDED[w] then -- ("two handed")
		elseif w == "weapon" or w == "weapons" then weaponWord = true
		elseif WEAPON_WORDS[w] then
			if skills then return end   -- (two weapons: not this)
			skills = WEAPON_WORDS[w]
		elseif not WEAPON_FILLER[w] then
			return
		end
	end
	-- (a weapon by its hands, "two handed axe", is the skill: taught; a bare "sword" is sold)
	if not train and not (hands and skills) then return end
	if not skills then return weaponWord and "all" or nil end
	if hands and #skills == 2 then skills = { skills[hands] } end
	return skills
end
Search.WeaponQuery = WeaponQuery

--- a weapon's name, in your language when the game has it
function Search.WeaponName(sub)
	local name = GetItemSubClassInfo and GetItemSubClassInfo(2, sub)
	return (type(name) == "string" and name ~= "") and name or WEAPON_NAMES[sub] or "?"
end

-- the weapon masters who teach what's asked ("all": any of them), each with all it teaches
local function WeaponMasters(ctx, skills)
	for id, teaches in pairs(WEAPON_MASTERS) do
		local ok = skills == "all"
		if not ok then
			for _, t in ipairs(teaches) do
				for _, want in ipairs(skills) do if t == want then ok = true end end
			end
		end
		local e = ok and ns.Index.byId[id]
		if e and NpcOk(ctx, e) then
			local pts = Points(ctx.NpcDB, id, false, ctx.zoneOk)
			if pts then
				local names = {}
				for i, t in ipairs(teaches) do names[i] = Search.WeaponName(t) end
				local r = Add(ctx, e, pts)
				r.teaches = table.concat(names, ", ")
				r.rank = 0
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Profession specialisations and ranks: who teaches them. "goblin engineering", "dragonscale",
-- "armorsmith", "master swordsmith": the trainers of that specialisation (found by their titles,
-- WoW Forever's own included, and a few by who they are). "artisan tailoring", "expert
-- leatherworker trainer": the trainers of that profession who teach up to that rank or higher
--------------------------------------------------------------------------------

local TRAINER_FLAG = 16
-- what's asked -> { the name, title words (a trainer's), NPCs by id (titled otherwise, or not at all) }
local SPECIALTIES = {
	{ name = L["Goblin Engineering"], words = { "goblin engineering", "goblin engineer", "goblin" }, subs = { "goblin engineer" } },
	{ name = L["Gnomish Engineering"], words = { "gnomish engineering", "gnome engineering", "gnomish engineer", "gnome engineer", "gnomish" },
		subs = { "gnome engineer", "gnomish engineer" } },
	{ name = L["Dragonscale Leatherworking"], words = { "dragonscale leatherworking", "dragonscale leatherworker", "dragonscale" },
		subs = { "dragonscale leatherwork" } },
	{ name = L["Elemental Leatherworking"], words = { "elemental leatherworking", "elemental leatherworker" },
		subs = { "elemental leatherwork" } },
	{ name = L["Tribal Leatherworking"], words = { "tribal leatherworking", "tribal leatherworker", "tribal" },
		subs = { "tribal leatherwork" } },
	{ name = L["Shadoweave Tailoring"], words = { "shadoweave tailoring", "shadoweave tailor", "shadoweave" },   -- (WoW Forever's own)
		subs = { "shadoweave tailor" } },
	{ name = L["Armorsmithing"], words = { "armorsmith", "armorsmithing", "armor smith", "armor smithing", "armoursmith", "armoursmithing" },
		subs = { "armorsmith", "armor crafter" }, trainer = true },
	{ name = L["Weaponsmithing"], words = { "weaponsmith", "weaponsmithing", "weapon smith", "weapon smithing" },
		subs = { "weaponsmith", "special weapon crafter" }, trainer = true },
	{ name = L["Hammersmithing"], words = { "hammersmith", "hammersmithing" }, ids = { 11191 } },   -- Lilith the Lithe, Everlook
	{ name = L["Axesmithing"], words = { "axesmith", "axesmithing" }, ids = { 11192 } },             -- Kilram, Everlook
	{ name = L["Swordsmithing"], words = { "swordsmith", "swordsmithing" }, ids = { 11193 } },       -- Seril Scourgebane, Everlook
}
local SPEC_FILLER = { trainer = true, trainers = true, training = true, train = true, teacher = true, teaches = true,
	teach = true, learn = true, master = true, who = true, where = true, is = true, the = true, a = true, ["to"] = true,
	spec = true, specialisation = true, specialization = true, specialty = true, ["for"] = true, can = true, i = true }

local function Rest(query, filler)
	local words = {}
	for w in query:gmatch("%S+") do if not filler[w] then words[#words + 1] = w end end
	return table.concat(words, " ")
end

local ASK_ONLY = { weaponsmith = true, ["weapon smith"] = true, armorsmith = true, ["armor smith"] = true, armoursmith = true }

--- the specialisation a search asks for (a SPECIALTIES row), or nil
local function SpecialtyQuery(query)
	local rest = Rest(query, SPEC_FILLER)
	if rest == "" then return end
	-- (a bare "goblin", "tribal": only said with a word that asks for a teacher; and a bare
	-- "weaponsmith" may be a weapon seller wanted: "weaponsmithing", or "weaponsmith trainer")
	local asked = rest ~= query
	if not asked and ASK_ONLY[rest] then return end
	for _, s in ipairs(SPECIALTIES) do
		for i, w in ipairs(s.words) do
			if rest == w and (asked or i < #s.words or #s.words == 1 or w:find(" ", 1, true)) then return s end
		end
	end
end
Search.SpecialtyQuery = SpecialtyQuery

local function Specialists(ctx, s)
	local seen = {}
	local function Take(e)
		if seen[e.id] or not NpcOk(ctx, e) then return end
		seen[e.id] = true
		local pts = Points(ctx.NpcDB, e.id, false, ctx.zoneOk)
		if pts then
			local r = Add(ctx, e, pts)
			r.teaches, r.rank = s.name, 0
		end
	end
	for _, id in ipairs(s.ids or {}) do
		local e = ns.Index.byId[id]
		if e then Take(e) end
	end
	if s.subs then
		for _, e in ipairs(ns.Index.entries) do
			local sub = e.sub and lower(e.sub)
			if sub and (not s.trainer or band(e.flags or 0, TRAINER_FLAG) ~= 0) then
				for _, p in ipairs(s.subs) do
					if find(sub, p, 1, true) then Take(e) break end
				end
			end
		end
	end
end

-- the ranks, as trainers' titles say them (a Master's teaches all an Artisan's does)
local RANKS = { journeyman = 1, expert = 2, artisan = 3, master = 3 }
local RANK_NAMES = { L["Journeyman"], L["Expert"], L["Artisan"] }
local PROF_WORDS = {
	tailor = 197, tailoring = 197, leatherworker = 165, leatherworking = 165, lw = 165, blacksmith = 164, blacksmithing = 164,
	bs = 164, engineer = 202, engineering = 202, alchemist = 171, alchemy = 171, enchanter = 333, enchanting = 333,
	cook = 185, cooking = 185, ["first aid"] = 129, fishing = 356, fisherman = 356, mining = 186, miner = 186,
	herbalism = 182, herbalist = 182, skinning = 393, skinner = 393,
}
local PROF_NAMES = { [197] = L["Tailoring"], [165] = L["Leatherworking"], [164] = L["Blacksmithing"], [202] = L["Engineering"],
	[171] = L["Alchemy"], [333] = L["Enchanting"], [185] = L["Cooking"], [129] = L["First Aid"], [356] = L["Fishing"], [186] = L["Mining"],
	[182] = L["Herbalism"], [393] = L["Skinning"] }
local NOT_RANK = { "goblin", "gnom", "dragonscale", "elemental", "tribal", "shadoweave" }   -- (a specialist's "Master")

local TitleRank   -- (below)
local hasRanks = {}
local function HasRanks(prof)
	if hasRanks[prof] == nil then
		hasRanks[prof] = false
		for _, e in ipairs(ns.Index.entries) do
			if e.prof == prof and TitleRank(e.sub) then hasRanks[prof] = true break end
		end
	end
	return hasRanks[prof]
end

--- a search for a profession's trainers of a rank ("artisan tailoring"): the profession, the rank (1..3)
local function RankQuery(query)
	local rank
	for w in query:gmatch("%S+") do
		if RANKS[w] and w ~= "master" then rank = RANKS[w] end
	end
	if not rank then return end
	local rest = Rest(query:gsub("%f[%a]journeyman%f[%A]", ""):gsub("%f[%a]expert%f[%A]", ""):gsub("%f[%a]artisan%f[%A]", ""), SPEC_FILLER)
	local prof = PROF_WORDS[rest]
	if prof and HasRanks(prof) then return prof, rank end
end
Search.RankQuery = RankQuery

-- a trainer's rank by its title (nil: not said)
TitleRank = function(sub)
	sub = lower(sub or "")
	for _, w in ipairs(NOT_RANK) do if find(sub, w, 1, true) then return end end
	for w, n in pairs(RANKS) do
		if find(sub, "%f[%a]" .. w .. "%f[%A]") then return n end
	end
end

local function RankedTrainers(ctx, prof, rank)
	for _, e in ipairs(ns.Index.entries) do
		if e.prof == prof and band(e.flags or 0, TRAINER_FLAG) ~= 0 and NpcOk(ctx, e) then
			local r = TitleRank(e.sub)
			if r and r >= rank then
				local pts = Points(ctx.NpcDB, e.id, false, ctx.zoneOk)
				if pts then
					local res = Add(ctx, e, pts)
					res.rank = r == rank and 0 or 1   -- (the rank asked first, then the higher)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Training past a skill's cap: "how do i train past 225 first aid", "tailoring 150", "train
-- cooking" (past the cap you have now). Up to 75, any trainer. Past 75, 150 and 225, the rank
-- that goes on: from the trainers who teach it, or for first aid, cooking and fishing, Expert's
-- book (its vendors) and Artisan's quest (who starts it, and the one who sends you there)
--------------------------------------------------------------------------------
do
local TP_FILLER = { how = true, ["do"] = true, i = true, train = true, training = true, past = true, beyond = true,
	above = true, over = true, ["to"] = true, get = true, learn = true, level = true, skill = true, raise = true,
	my = true, cap = true, the = true, a = true, after = true, from = true, at = true, go = true, can = true,
	where = true, is = true, higher = true, max = true, up = true, more = true, than = true, unlock = true,
	increase = true, rank = true, next = true, ["in"] = true, of = true, what = true, whats = true, ["for"] = true }
-- (words that ask it, with no number: past the cap you have now)
local TP_ASK = { train = true, training = true, past = true, beyond = true, above = true, over = true, higher = true,
	next = true, unlock = true, increase = true, raise = true, cap = true, max = true }
local TP_BOOK = { [129] = 7, [185] = 5, [356] = 9 }   -- (first aid, cooking, fishing: their books' subclass)
local TP_ARTISAN = 225                                 -- (the skill Artisan's quests ask)

--- a "train past" search: the profession (skill id) and the skill typed (nil: none), or nil
function Search.TrainPastQuery(query)
	local q = query:gsub("first aid", "firstaid")
	local prof, n, ask
	for w in q:gmatch("%S+") do
		local p = PROF_WORDS[w] or (w == "firstaid" and 129) or nil
		if p then
			if prof and prof ~= p then return end
			prof = p
		elseif w:match("^%d+$") then
			if n then return end
			n = tonumber(w)
		elseif TP_FILLER[w] then
			if TP_ASK[w] then ask = true end
		else
			return
		end
	end
	if prof and (n or ask) then return prof, n end
end

-- your skill in it, and its cap (nil: you don't have it, or the game won't say)
local function MySkill(prof)
	if not (GetNumSkillLines and GetSkillLineInfo) then return end
	local want = PROF_NAMES[prof]
	for i = 1, GetNumSkillLines() do
		local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
		if not header and name == want then return rank, max end
	end
end

-- every trainer of it (yours)
local function TrainersOf(ctx, prof)
	for _, e in ipairs(ns.Index.entries) do
		if e.prof == prof and band(e.flags or 0, TRAINER_FLAG) ~= 0 and NpcOk(ctx, e) then
			local pts = Points(ctx.NpcDB, e.id, false, ctx.zoneOk)
			if pts then Add(ctx, e, pts).rank = 0 end
		end
	end
end

local function Done(id)
	local f = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or _G.IsQuestFlaggedCompleted
	local ok, done = false, false
	if f then ok, done = pcall(f, id) end
	return ok and done
end

-- Artisan's quests (they ask 225 of it): who starts them, yours. The one to do first's name
local function ArtisanQuests(ctx, prof)
	local QDB = QuestDB()
	if not (QDB and QDB.GetAllIds) then return end
	local ids, set = {}, {}
	for _, id in ipairs(QDB.GetAllIds()) do
		local ok, s = pcall(QDB.Get, id, "requiredSkill")
		if ok and type(s) == "table" and s[1] == prof and s[2] == TP_ARTISAN and QuestForYou(QDB, id) then
			ids[#ids + 1] = id
			set[id] = true
		end
	end
	-- (the first of them: not the next of another; and not done, if one isn't)
	local led = {}
	for _, id in ipairs(ids) do
		local ok, nxt = pcall(QDB.Get, id, "nextQuestInChain")
		if ok and set[nxt] then led[nxt] = true end
	end
	local first
	for _, id in ipairs(ids) do
		if not led[id] and not Done(id) then first = id break end
	end
	first = first or ids[#ids]
	local list = {}
	for _, id in ipairs(ids) do
		local ok, name = pcall(QDB.Get, id, "name")
		if ok and type(name) == "string" then list[#list + 1] = { QuestNorm(name), name, { id } } end
	end
	QuestStarters(ctx, list, 0)
	local ok, name = false, nil
	if first then ok, name = pcall(QDB.Get, first, "name") end
	return ok and name or nil
end

--- the way past it, on the map. Returns what the status says; or nil and why there's none
function Search.TrainPast(ctx, prof, n)
	local pname = PROF_NAMES[prof] or "?"
	if not n then
		local _, cap = MySkill(prof)
		n = cap
	end
	if not n then
		TrainersOf(ctx, prof)
		return L["Say how far you've got, for example \"%s 150\"."]:format(lower(pname))
	end
	if n >= 300 then return nil, L["%s goes no higher than %d."]:format(pname, 300) end
	if n < 75 then
		TrainersOf(ctx, prof)
		return L["To train %s past %d: learn it from any of these trainers."]:format(pname, n)
	end
	local rank = (n < 150 and 1) or (n < 225 and 2) or 3
	local sub = TP_BOOK[prof]
	if sub and rank == 2 then
		Books(ctx, sub)
		local book
		for _, b in ipairs(ns.Index.skillBooks) do if b.sub == sub then book = b.name break end end
		return L["To train %s past %d: buy and read %s."]:format(pname, n, book or "?")
	end
	if sub and rank == 3 then
		local first = ArtisanQuests(ctx, prof)
		if first then return L["To train %s past %d: do the quest \"%s\"."]:format(pname, n, first) end
		return nil, L["No quest for your faction trains %s past %d."]:format(pname, n)
	end
	if not sub and HasRanks(prof) then RankedTrainers(ctx, prof, rank) else TrainersOf(ctx, prof) end
	return L["To train %s past %d: learn %s from these trainers."]:format(pname, n, RANK_NAMES[rank])
end
end

--------------------------------------------------------------------------------
-- Riding: "where to train riding", "mount training", "learn to ride", "riding". Your faction's
-- riding trainers (the gnomes' is a "Mechanostrider Pilot": by his skill, or his title)
--------------------------------------------------------------------------------
do
local RIDE = { riding = 1, ride = 1, mount = 2, mounts = 2, mounted = 2, train = 3, training = 3, trainer = 3,
	trainers = 3, learn = 3, skill = 3, lesson = 3, lessons = 3, instructor = 3, instructors = 3, teach = 3,
	teaches = 3, teacher = 3, where = 0, ["to"] = 0, ["do"] = 0, i = 0, can = 0, how = 0, get = 0, my = 0, a = 0,
	the = 0, is = 0, ["for"] = 0, who = 0, at = 0, of = 0 }
local RIDING, PILOT = 762, "mechanostrider pilot"

--- a riding search? ("riding", "ride" or "mount" with a word for learning it)
function Search.RidingQuery(query)
	local ride, mount, learn = false, false, false
	for w in query:gmatch("%S+") do
		local k = RIDE[w]
		if not k then return false end
		if k == 1 then ride = true elseif k == 2 then mount = true elseif k == 3 then learn = true end
	end
	return ride or (mount and learn)
end

function Search.RidingTrainers(ctx)
	for _, e in ipairs(ns.Index.entries) do
		if (e.prof == RIDING or (e.sub and lower(e.sub) == PILOT)) and NpcOk(ctx, e) then
			local pts = Points(ctx.NpcDB, e.id, false, ctx.zoneOk)
			if pts then Add(ctx, e, pts).rank = 0 end
		end
	end
end
end

--------------------------------------------------------------------------------
-- Class quests: "class quests" (yours you can take now, as Questie has them), "warlock quests"
-- (a class's: where each of its quest lines starts), "voidwalker quest", "bear form quest" (the
-- class quest lines whose quests' names or goals say it: where each starts)
--------------------------------------------------------------------------------

local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
local CLASS_WORDS = { warrior = "WARRIOR", warriors = "WARRIOR", paladin = "PALADIN", paladins = "PALADIN", pally = "PALADIN",
	hunter = "HUNTER", hunters = "HUNTER", rogue = "ROGUE", rogues = "ROGUE", priest = "PRIEST", priests = "PRIEST",
	shaman = "SHAMAN", shamans = "SHAMAN", mage = "MAGE", mages = "MAGE", warlock = "WARLOCK", warlocks = "WARLOCK",
	lock = "WARLOCK", druid = "DRUID", druids = "DRUID" }
local CQ_QUEST = { quest = true, quests = true, questline = true, chain = true }
local CQ_FILLER = { my = true, the = true, ["for"] = true, a = true, where = true, is = true, start = true, starts = true,
	get = true, how = true, ["to"] = true, ["do"] = true, i = true, find = true, of = true, me = true }
local CLASS_MAX = 3          -- a quest that this many classes may take, or fewer, is a class quest

local function ClassBit(class) local n = CLASS_IDS[class] return n and 2 ^ (n - 1) end
local function HasBit(mask, b) return b and mask % (b * 2) >= b end

local classQuests   -- { [id] = { name, mask, pre = { ids }, hay } }: the quests only a class or so may take
local function ClassQuests()
	if classQuests then return classQuests end
	classQuests = {}
	local QDB = QuestDB()
	if not (QDB and QDB.GetAllIds and QDB.Get) then return classQuests end
	for _, id in ipairs(QDB.GetAllIds()) do
		local ok, mask = pcall(QDB.Get, id, "requiredClasses")
		if ok and type(mask) == "number" and mask > 0 then
			local n = 0
			for _, c in pairs(CLASS_IDS) do if HasBit(mask, 2 ^ (c - 1)) then n = n + 1 end end
			local okN, name = pcall(QDB.Get, id, "name")
			if n >= 1 and n <= CLASS_MAX and okN and type(name) == "string" then
				local text = {}
				local okO, obj = pcall(QDB.Get, id, "objectivesText")
				if okO and type(obj) == "table" then
					for _, t in ipairs(obj) do if type(t) == "string" then text[#text + 1] = t end end
				end
				local pres = {}
				local okP, pre = pcall(QDB.Get, id, "preQuestSingle")
				local okG, preG = pcall(QDB.Get, id, "preQuestGroup")
				for _, p in ipairs(okP and Ids(pre) or {}) do pres[#pres + 1] = p end
				for _, p in ipairs(okG and Ids(preG) or {}) do pres[#pres + 1] = p end
				classQuests[id] = { name = name, mask = mask, pre = pres,
					hay = " " .. QuestNorm(name .. " " .. table.concat(text, " ")) }
			end
		end
	end
	return classQuests
end

-- where a class quest's line starts: back through the class quests it needs done first
local function ChainStart(id)
	local CQ = ClassQuests()
	for _ = 1, 25 do
		local back
		for _, p in ipairs(CQ[id] and CQ[id].pre or {}) do if CQ[p] then back = p break end end
		if not back then break end
		id = back
	end
	return id
end

--- a class quest search: "class" (and the class, nil: yours), or "topic", the class, the words
local function ClassQuestQuery(query)
	local words, quest, class, classWord = {}, false, nil, false
	for w in query:gsub("quest line", "questline"):gmatch("%S+") do
		if CQ_QUEST[w] then quest = true
		elseif CLASS_WORDS[w] then class = CLASS_WORDS[w]
		elseif w == "class" then classWord = true
		elseif not CQ_FILLER[w] then words[#words + 1] = w end
	end
	if not quest then return end
	if #words == 0 then
		if class or classWord then return "class", class end
		return
	end
	return "topic", class, words
end

local function Line(list, seen, id)
	local q = ClassQuests()[id]
	if q and not seen[id] then
		seen[id] = true
		list[#list + 1] = { QuestNorm(q.name), q.name, { id } }
	end
end

-- what players call a class quest line -> the names of its quests (as WoW Forever has them)
local CQ_TOPICS = {
	["bear form"] = { "Heeding the Call", "Body and Heart" }, bear = { "Heeding the Call", "Body and Heart" },
	["aquatic form"] = { "A Lesson to Learn", "Aquatic Form" }, aquatic = { "A Lesson to Learn", "Aquatic Form" },
	["cure poison"] = { "Lessons Anew", "Power over Poison" },
	["defensive stance"] = { "Veteran Uzzek", "Bartleby the Drunk" }, defensive = { "Veteran Uzzek", "Bartleby the Drunk" },
	["berserker stance"] = { "The Islander" }, berserker = { "The Islander" },
	whirlwind = { "Whirlwind Weapon" }, ["whirlwind axe"] = { "Whirlwind Weapon" }, ["whirlwind weapon"] = { "Whirlwind Weapon" },
	poison = { "The Touch of Zanzil", "Mission: Possible But Not Probable" }, poisons = { "The Touch of Zanzil", "Mission: Possible But Not Probable" },
	["rogue poison"] = { "The Touch of Zanzil", "Mission: Possible But Not Probable" },
	pet = { "Taming the Beast" }, ["pet taming"] = { "Taming the Beast" }, taming = { "Taming the Beast" },
}

-- the class quest lines a topic's words are in: where each starts. Your class's and your
-- faction's first, when there are any; by name before by what the quests ask
local function ClassTopic(words, class)
	local CQ, QDB = ClassQuests(), QuestDB()
	local want = ClassBit(class or select(2, UnitClass("player")))
	local hits = {}
	local named = CQ_TOPICS[table.concat(words, " ")]
	if named then
		local set = {}
		for _, n in ipairs(named) do set[QuestNorm(n)] = true end
		-- (a class said: only its quests of the name, "druid poison" isn't the rogues' poisons)
		for id, q in pairs(CQ) do
			if set[QuestNorm(q.name)] and (not class or HasBit(q.mask, want)) then hits[#hits + 1] = id end
		end
	end
	for _, field in ipairs({ "name", "hay" }) do
		if #hits > 0 then break end
		for id, q in pairs(CQ) do
			local hay = field == "name" and (" " .. QuestNorm(q.name)) or q.hay
			local all = true
			for _, w in ipairs(words) do
				if not find(hay, " " .. w, 1, true) then all = false break end
			end
			if all then hits[#hits + 1] = id end
		end
	end
	-- (yours: your class's, then your faction's, when there are any)
	local function Keep(ok)
		local kept = {}
		for _, id in ipairs(hits) do if ok(id) then kept[#kept + 1] = id end end
		if #kept > 0 then hits = kept end
	end
	Keep(function(id) return HasBit(CQ[id].mask, want) end)
	if class then
		local kept = {}
		for _, id in ipairs(hits) do if HasBit(CQ[id].mask, want) then kept[#kept + 1] = id end end
		hits = kept
	end
	Keep(function(id) return QuestForYou(QDB, id) end)
	table.sort(hits)
	local seen, list = {}, {}
	for _, id in ipairs(hits) do Line(list, seen, ChainStart(id)) end
	return list
end

-- a class's quests: yours you can take now (true: Questie's list was asked); another's, or
-- before Questie's list is ready, where each of its quest lines starts
local function ClassQuestGivers(ctx, class)
	local mine = select(2, UnitClass("player"))
	local want = ClassBit(class or mine)
	local CQ, list, seen = ClassQuests(), {}, {}
	if (class or mine) == mine then
		local AQ = Questie("AvailableQuests")
		local avail = AQ and AQ.__availableQuests
		if type(avail) == "table" then
			local ids = {}
			for qid in pairs(avail) do
				if CQ[qid] and HasBit(CQ[qid].mask, want) then ids[#ids + 1] = qid end
			end
			table.sort(ids)
			for _, id in ipairs(ids) do Line(list, seen, id) end
			QuestStarters(ctx, list, 0)
			return true
		end
	end
	local ids = {}
	for id, q in pairs(CQ) do if HasBit(q.mask, want) then ids[#ids + 1] = id end end
	table.sort(ids)
	for _, id in ipairs(ids) do Line(list, seen, ChainStart(id)) end
	QuestStarters(ctx, list, 0)
	return false
end

--------------------------------------------------------------------------------
-- Reputation quartermasters: "argent dawn quartermaster", "timbermaw rep", "zandalar rewards".
-- The vendors whose titles name the faction (their wares on their markers' cards)
--------------------------------------------------------------------------------

local VENDOR_FLAG = 4
local QM_WORDS = { quartermaster = true, quartermasters = true, qm = true, rep = true, reputation = true,
	rewards = true, reward = true }
local QM_FILLER = { vendor = true, vendors = true, the = true, ["for"] = true, where = true, is = true, of = true }
local QM_ALIASES = { ad = "argent dawn", cc = "cenarion circle", tb = "thorium brotherhood", ["zandalar tribe"] = "zandalar",
	zg = "zandalar", ["wintersaber trainers"] = "wintersaber", aq = "cenarion circle" }
local QM_IDS = { timbermaw = { 11557 } }   -- (Meilosh, Timbermaw Hold: no title to find him by)

--- a quartermaster search: the faction's words ("argent dawn"), or nil
local function RepQuery(query)
	local asked, words = false, {}
	for w in query:gmatch("%S+") do
		if QM_WORDS[w] then asked = true elseif not QM_FILLER[w] then words[#words + 1] = w end
	end
	if not asked or #words == 0 then return end
	local rest = table.concat(words, " ")
	return QM_ALIASES[rest] or rest
end

local function RepVendors(ctx, faction)
	local seen = {}
	local function Take(e)
		if not e or seen[e.id] or not NpcOk(ctx, e) then return end
		seen[e.id] = true
		local pts = Points(ctx.NpcDB, e.id, false, ctx.zoneOk)
		if pts then Add(ctx, e, pts, { kind = "VENDOR" }).rank = 0 end
	end
	for key, ids in pairs(QM_IDS) do
		if find(faction, key, 1, true) then for _, id in ipairs(ids) do Take(ns.Index.byId[id]) end end
	end
	local words = {}
	for w in faction:gmatch("%S+") do words[#words + 1] = w end
	for _, e in ipairs(ns.Index.entries) do
		if e.sub and band(e.flags or 0, VENDOR_FLAG) ~= 0 then
			local sub = " " .. lower(e.sub):gsub("'", "")
			local all = true
			for _, w in ipairs(words) do
				if not find(sub, " " .. w, 1, true) then all = false break end
			end
			if all then Take(e) end
		end
	end
end

--------------------------------------------------------------------------------
-- Rare mobs: "rares", "rare spawns" (the ones around your level), "rares in feralas" (all
-- of a zone's). Each where it may spawn, with its level
--------------------------------------------------------------------------------

local RARE_BELOW, RARE_ABOVE = 10, 5   -- levels below and above yours that count as around it
local RARE_FILLER = { spawn = true, spawns = true, mob = true, mobs = true, elite = true, elites = true, near = true,
	nearby = true, me = true, around = true, ["for"] = true, my = true, level = true, all = true, the = true,
	named = true, show = true, where = true, are = true }

local function RareQuery(query)
	local rare = false
	for w in query:gmatch("%S+") do
		if w == "rare" or w == "rares" then rare = true
		elseif not RARE_FILLER[w] then return end
	end
	return rare
end

local function Rares(ctx)
	local me = UnitLevel("player") or 1
	for _, e in ipairs(ns.Index.entries) do
		if e.rare and FactionOk(e.fac) then
			local okL, lo = pcall(ctx.NpcDB.Get, e.id, "minLevel")
			local okH, hi = pcall(ctx.NpcDB.Get, e.id, "maxLevel")
			lo = okL and tonumber(lo) or 0
			hi = okH and tonumber(hi) or lo
			if ctx.zoneOk or (lo <= me + RARE_ABOVE and hi >= me - RARE_BELOW) then
				local pts = Points(ctx.NpcDB, e.id, true, ctx.zoneOk)
				if pts then
					local levels = (hi > lo) and ("%d-%d"):format(lo, hi) or tostring(lo)
					local r = Add(ctx, e, pts)
					r.rank = 0
					r.lines = { { (e.rare == 2 and L["Level %s rare elite"] or L["Level %s rare"]):format(levels), 1, 0.82, 0.1 } }
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Spirit healers: "graveyard", "spirit healer". Every graveyard's, the nearest marked
--------------------------------------------------------------------------------

local SPIRIT_HEALER = 6491
local SPIRIT = { graveyard = true, graveyards = true, gy = true, ["spirit healer"] = true, ["spirit healers"] = true,
	angel = true, rez = true, res = true, resurrect = true, ["spirit rez"] = true, ["spirit res"] = true }

-- the zone you're in (its zone's map, not a town's or a cave's)
local function ZoneHere()
	local id = ns.PlayerMap and ns.PlayerMap()
	for _ = 1, 5 do
		local info = id and C_Map.GetMapInfo(id)
		if not info then return end
		if info.mapType == 3 then return id end
		id = info.parentMapID
	end
end

--- coordinates typed as a search ("59.3, 44.6", "59 44"): a marker there, on the zone named with
--- them (`within`, a zone's map: "barrens 59 44"), or the zone the world map shows, or the one
--- you're in. nil when the search isn't coordinates; nil and why, when it is but can't be shown
function Search.Coords(query, within)
	local q = lower(strtrim(query or ""))
	local sx, sy = q:match("^(%d+%.?%d*)%s*[,;/ ]%s*(%d+%.?%d*)$")
	local x, y = tonumber(sx), tonumber(sy)
	if not (x and y) then return end
	if x > 100 or y > 100 then return nil, L["Coordinates run from 0 to 100."] end
	local function Zone(id)
		local info = id and C_Map and C_Map.GetMapInfo(id)
		return info and info.mapType == 3 and info or nil
	end
	local shown = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
	local info = Zone(within) or Zone(shown) or Zone(ZoneHere())
	if not info then return nil, L["Open a zone's map, or name the zone: \"barrens 52 30\"."] end
	local name = ("%.1f, %.1f"):format(x, y)
	local results = { { entry = { id = 0, name = name, sub = info.name, obj = true, flags = 0 }, kind = "TOWN",
		points = { { ui = info.mapID, x = x, y = y } }, rank = 0, near = false } }
	results.coords = true
	results.questNow = info.name .. " " .. name
	return results
end

-- dead: where the game will put you when you release (the server's own pick: what the map's
-- ghost shows), as (map, x, y 0..100) on your zone's map or the one you're on; nil alive, or when
-- the game won't say
local function ReleaseSpot()
	if not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then return end
	local f = C_DeathInfo and C_DeathInfo.GetDeathReleasePosition
	if not f then return end
	for _, id in ipairs({ ZoneHere(), ns.PlayerMap and ns.PlayerMap() }) do
		local ok, pos = pcall(f, id)
		if ok and pos then
			local x, y
			if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
			if x and y and (x > 0 or y > 0) then return id, x * 100, y * 100 end
		end
	end
end

-- every spirit healer; and the one you'd come back at, a marker of its own (the one the ring
-- and the nearest go to): dead, the game's word for it; alive, the nearest in your zone (the
-- server sends you to one of your zone's graveyards, mostly the nearest: not always)
local function SpiritHealers(ctx)
	local e = ns.Index.byId[SPIRIT_HEALER]
	local pts = e and Points(ctx.NpcDB, SPIRIT_HEALER, true, ctx.zoneOk)
	if not pts then return end
	local r = Add(ctx, e, pts)
	r.rank = 0
	local ui, x, y = ReleaseSpot()
	local line
	if ui then
		line = L["Where you'll come back when you release"]
	else
		ui = ZoneHere()
		if not ui then return end
		line = L["Most likely where you'd come back if you died in this zone"]
	end
	-- (the spirit healer there: dead, the one at the game's spot; alive, your zone's nearest you)
	local best, bd
	for i, p in ipairs(pts) do
		if p.ui == ui then
			local d
			if x then d = (p.x - x) ^ 2 + (p.y - y) ^ 2
			else d = ns.Pins and ns.Pins.Distance and ns.Pins.Distance(p) end
			if d and (not bd or d < bd) then best, bd = i, d end
		end
	end
	local at
	if best and (not x or bd <= 9) then   -- (dead: a spirit healer within 3 of the map's 100)
		at = table.remove(pts, best)
	elseif x then
		at = { ui = ui, x = x, y = y }       -- (the game's spot, a spirit healer there or not)
	end
	if not at then return end
	local mine = { id = e.id, name = e.name, sub = e.sub, flags = e.flags, fac = e.fac, hay = e.hay, sq = e.sq }
	local m = Add(ctx, mine, { at })
	m.rank, m.near, m.pick = 0, true, true
	m.lines = { { line, 0.5, 1, 0.5 } }
	ctx.byId[e.id] = r
end

-- dungeon quests, attunements, food and ammunition (below): reached through this
local Extra = {}
do
-- a quest you've done (the game keeps it; nil: it can't say)
local function QuestDone(id)
	local f = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or _G.IsQuestFlaggedCompleted
	if not f then return false end
	local ok, done = pcall(f, id)
	return ok and done and true or false
end

-- a quest your class may take (any class, or yours among them)
local function ClassMayTake(QDB, id, class)
	local ok, mask = pcall(QDB.Get, id, "requiredClasses")
	if not (ok and type(mask) == "number" and mask > 0) then return true end
	local b = ClassBit(class)
	return not b or HasBit(mask, b)
end

-- (quests you're on, and quest lines: a block of their own, for Lua's count of locals)
do
-- (the markers for a quest you're on: a mob to kill, a thing to use, a place to find)
local QN_KILL = "Interface\\Icons\\Ability_DualWield"
local QN_USE = "Interface\\Icons\\INV_Misc_Gear_01"
local QN_GO = "Interface\\Icons\\INV_Misc_Map_01"

--------------------------------------------------------------------------------
-- A quest searched by name that you're on: where to go for it now. Done (all it asks), who it's
-- handed in to; not yet, where what it asks is (the mobs to kill, the things to use or loot, the
-- place to find), what's done of it left out. Not on it: of a line of quests with the one name,
-- the step you're up to (the first you haven't done whose quests before it you have)
--------------------------------------------------------------------------------

local QN_SPOTS = 4   -- areas drawn for a mob to kill, at most (the nearest's zone)

-- where a quest is in your log (nil: not in it)
local function LogIndex(id)
	local f = (C_QuestLog and C_QuestLog.GetLogIndexForQuestID) or _G.GetQuestLogIndexByID
	if not f then return end
	local ok, i = pcall(f, id)
	if ok and type(i) == "number" and i > 0 then return i end
end

-- the game's objectives for a quest in your log: { { text, finished }, ... }
local function LogObjectives(id, index)
	local out = {}
	local f = C_QuestLog and C_QuestLog.GetQuestObjectives
	local ok, list = false, nil
	if f then ok, list = pcall(f, id) end
	if ok and type(list) == "table" then
		for _, o in ipairs(list) do
			if type(o) == "table" and type(o.text) == "string" then out[#out + 1] = { o.text, o.finished and true or false } end
		end
		return out
	end
	if _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard then
		local okN, n = pcall(GetNumQuestLeaderBoards, index)
		for i = 1, okN and n or 0 do
			local okL, text, _, done = pcall(GetQuestLogLeaderBoard, i, index)
			if okL and type(text) == "string" then out[#out + 1] = { text, done and true or false } end
		end
	end
	return out
end

-- a quest in your log is done (all it asks), ready to hand in
local function LogComplete(id, index, objs)
	if C_QuestLog and C_QuestLog.IsComplete then
		local ok, done = pcall(C_QuestLog.IsComplete, id)
		if ok and done then return true end
	end
	if _G.IsQuestComplete then
		local ok, done = pcall(_G.IsQuestComplete, id)
		if ok and done then return true end
	end
	if _G.GetQuestLogTitle then
		local ok, _, _, _, _, _, complete = pcall(GetQuestLogTitle, index)
		if ok and (complete == 1 or complete == true) then return true end
	end
	if #objs == 0 then return false end
	for _, o in ipairs(objs) do if not o[2] then return false end end
	return true
end

-- the game's objective about this name (its text, done or not), or nil
local function ObjectiveFor(objs, name)
	if type(name) ~= "string" or name == "" then return end
	local l = lower(name)
	for _, o in ipairs(objs) do
		if find(lower(o[1]), l, 1, true) then return o end
	end
end

--- where you are with a quest an item's for, for the item's tooltip: what the game says of the
--- item in your log ("Boar Tusk: 3/8"), that the quest's done and to be handed in, that it's in
--- your log, or that you've done it; nil when none of those. And whether it's in your log
function Search.QuestItemState(qid, itemName)
	local index = LogIndex(qid)
	if index then
		local objs = LogObjectives(qid, index)
		if LogComplete(qid, index, objs) then return L["You've done all it asks: hand it in."], true end
		local o = ObjectiveFor(objs, itemName)
		if o then return o[1], true end
		return L["In your quest log"], true
	end
	if QuestDone(qid) then return L["Done"], false end
end

-- a mob to kill (one or more ids): the areas it's in, the nearest's zone, as an item's are
local function KillAreas(ctx, ids, name, lines)
	local pts = {}
	for _, id in ipairs(ids) do
		local okN, n = pcall(ctx.NpcDB.Get, id, "name")
		for _, p in ipairs(Points(ctx.NpcDB, id, true, ctx.zoneOk) or {}) do
			p.src, p.wt, p.id = okN and type(n) == "string" and n or name, 1, id
			pts[#pts + 1] = p
		end
	end
	if #pts == 0 or not ns.Areas then return 0 end
	local clusters = ns.Areas.Clusters(pts)
	local c = ns.Areas.Pick(clusters)
	if not c then return 0 end
	local spots = { c }
	for _, k in ipairs(clusters) do
		if k ~= c and k.ui == c.ui and #k.pts >= SPOT_MIN and k.score >= c.score * SPOT_SHARE then spots[#spots + 1] = k end
	end
	table.sort(spots, function(a, b) return a.score > b.score end)
	for i = QN_SPOTS + 1, #spots do spots[i] = nil end
	for i, k in ipairs(spots) do
		local mid = ns.Areas.Middle(k)
		k.outline = k.outline or ns.Areas.Outline(k)
		local area = {}
		for kk, v in pairs(k.outline) do area[kk] = v end
		area.best = i == 1 and #spots > 1
		area.name, area.icon, area.mid, area.label = name, QN_KILL, { mid.x, mid.y }, name
		area.key = ("%d:%.2f:%.2f:q%d"):format(k.ui, area.verts[1] or 0, area.verts[2] or 0, ids[1])
		local e = { obj = true, id = -(1000000 * i + 500000 + ids[1]), name = name }
		local r = Add(ctx, e, { { ui = k.ui, x = mid.x, y = mid.y } }, { kind = "DROPS", lines = lines, area = area,
			label = L["Kill: %s"]:format(name), icon = QN_KILL })
		r.rank = 0
	end
	return #spots
end

-- markers for an object to use or loot, every one of it (in the zones allowed)
local function UseObject(ctx, oid, lines)
	local ObjDB = ns.Index.ObjectDB()
	if not ObjDB then return 0 end
	local ok, name = pcall(ObjDB.Get, oid, "name")
	if not (ok and type(name) == "string") then return 0 end
	local pts = Points(ObjDB, oid, true, ctx.zoneOk)
	if not pts then return 0 end
	local e = ctx.byId[-oid] and ctx.byId[-oid].entry or { obj = true, id = -oid, objectId = oid, name = name }
	local r = Add(ctx, e, pts, { kind = "DROPS", lines = lines, icon = QN_USE, label = L["For your quest: %s"]:format(name) })
	r.rank = 0
	return 1
end

-- where a quest in your log asks you to go (its triggerEnd): a marker on each spot
local function GoThere(ctx, id, title, lines)
	local QDB = QuestDB()
	local ok, t = pcall(QDB.Get, id, "triggerEnd")
	if not (ok and type(t) == "table" and type(t[2]) == "table") then return 0 end
	local pts = {}
	for areaId, list in pairs(t[2]) do
		local ui = type(list) == "table" and ns.UiMapFor(areaId)
		if ui and not (ctx.zoneOk and not ctx.zoneOk(ui)) then
			for _, xy in ipairs(list) do
				if type(xy) == "table" and type(xy[1]) == "number" and type(xy[2]) == "number" then
					pts[#pts + 1] = { ui = ui, x = xy[1], y = xy[2] }
				end
			end
		end
	end
	if #pts == 0 then return 0 end
	local name = type(t[1]) == "string" and t[1] or title
	local r = Add(ctx, { obj = true, id = -(900000000 + id), name = name }, pts,
		{ kind = "DROPS", lines = lines, icon = QN_GO, label = L["For your quest: %s"]:format(name) })
	r.rank = 0
	return 1
end

-- who a quest in your log is handed in to: its markers, said so
local function HandIn(ctx, id, title, line)
	local before = #ctx.results
	QuestEnders(ctx, { { nil, title, { id } } }, 0)
	for i = before + 1, #ctx.results do
		local r = ctx.results[i]
		r.rank = 0
		if line then r.lines = { { line, 0.5, 1, 0.5 } } end
	end
	return #ctx.results - before
end

-- a quest in your log: where to go for it now. Returns how many markers it put
local function QuestInLog(ctx, id, title, index)
	local QDB = QuestDB()
	local objs = LogObjectives(id, index)
	if LogComplete(id, index, objs) then
		ctx.questNow = ctx.questNow or L["\"%s\" is done: hand it in."]:format(title)
		return HandIn(ctx, id, title, L["You've done all it asks: hand it in here."])
	end
	local function Lines(o)
		local l = { { L["For your quest:"], 1, 0.82, 0.1 }, { "  " .. title, 1, 1, 1 } }
		if o then l[#l + 1] = { "  " .. o[1], 0.8, 0.8, 0.8 } end
		return l
	end
	local ok, ob = pcall(QDB.Get, id, "objectives")
	ob = ok and type(ob) == "table" and ob or {}
	local put = 0
	-- (mobs to kill)
	for _, c in ipairs(type(ob[1]) == "table" and ob[1] or {}) do
		local nid = type(c) == "table" and c[1] or c
		if type(nid) == "number" then
			local okN, name = pcall(ctx.NpcDB.Get, nid, "name")
			name = okN and type(name) == "string" and name or (type(c) == "table" and c[2]) or "?"
			local o = ObjectiveFor(objs, name) or ObjectiveFor(objs, type(c) == "table" and c[2])
			if not (o and o[2]) then put = put + KillAreas(ctx, { nid }, name, Lines(o)) end
		end
	end
	-- (kills that count for another: any of these mobs)
	local kc = ob[5]
	if type(kc) == "table" and type(kc[1]) == "table" and type(kc[1][1]) == "number" then kc = { kc } end
	for _, c in ipairs(type(kc) == "table" and kc or {}) do
		local ids = type(c) == "table" and type(c[1]) == "table" and c[1]
		if ids and #ids > 0 then
			local okN, base = pcall(ctx.NpcDB.Get, c[2] or ids[1], "name")
			base = okN and type(base) == "string" and base or nil
			local name = (type(c[3]) == "string" and c[3]) or base or "?"
			local o = ObjectiveFor(objs, name) or ObjectiveFor(objs, base)
			if not (o and o[2]) then put = put + KillAreas(ctx, ids, name, Lines(o)) end
		end
	end
	-- (things to use or loot)
	local ObjDB = ns.Index.ObjectDB()
	for _, c in ipairs(type(ob[2]) == "table" and ob[2] or {}) do
		local oid = type(c) == "table" and c[1] or c
		if type(oid) == "number" then
			local okN, name = false, nil
			if ObjDB then okN, name = pcall(ObjDB.Get, oid, "name") end
			local o = ObjectiveFor(objs, okN and name) or ObjectiveFor(objs, type(c) == "table" and c[2])
			if not (o and o[2]) then put = put + UseObject(ctx, oid, Lines(o)) end
		end
	end
	-- (items to get: where they drop, as an item search shows it)
	local ItemDB = ns.Index.ItemDB()
	for _, c in ipairs(type(ob[3]) == "table" and ob[3] or {}) do
		local iid = type(c) == "table" and c[1] or c
		if type(iid) == "number" and ItemDB then
			local okN, name = pcall(ItemDB.Get, iid, "name")
			if okN and type(name) == "string" then
				local o = ObjectiveFor(objs, name)
				if not (o and o[2]) then
					local before = #ctx.results
					ctx.forQuest = true
					Drops(ctx, (lower(name):gsub("'", "")), { iid }, false)
					ctx.forQuest = nil
					for i = before + 1, #ctx.results do
						local r = ctx.results[i]
						local l = Lines(o)
						for _, x in ipairs(r.lines or {}) do l[#l + 1] = x end
						r.lines, r.rank = l, 0
					end
					put = put + #ctx.results - before
				end
			end
		end
	end
	-- (a place to find)
	put = put + GoThere(ctx, id, title, Lines(nil))
	-- (nothing on the map for it, a talk or an escort: who it's handed in to)
	if put == 0 then put = HandIn(ctx, id, title) end
	ctx.questNow = ctx.questNow or L["Where to go for \"%s\"."]:format(title)
	return put
end

-- a quest's quests before it are done (any of preQuestSingle, all of preQuestGroup)
local function PreDone(QDB, id)
	local ok1, single = pcall(QDB.Get, id, "preQuestSingle")
	local ok2, group = pcall(QDB.Get, id, "preQuestGroup")
	single, group = ok1 and Ids(single) or {}, ok2 and Ids(group) or {}
	if #single > 0 then
		local any = false
		for _, p in ipairs(single) do if QuestDone(p) then any = true break end end
		if not any then return false end
	end
	for _, p in ipairs(group) do if not QuestDone(p) then return false end end
	return true
end

--- quests searched by name ({ { norm, name, { ids } }, ... }): the ones you're on shown (where to
--- go for them now); of the rest, each name's step you're up to, returned for their starters.
--- (A name whose every quest you've done: ctx.allDone, the name)
function Extra.QuestNow(ctx, list)
	local QDB = QuestDB()
	if not QDB then return list end
	local rest = {}
	for _, q in ipairs(list) do
		local onIt
		for _, id in ipairs(q[3]) do
			local index = LogIndex(id)
			if index then
				onIt = true
				QuestInLog(ctx, id, q[2], index)
				if #list == 1 then ctx.chainSeed = id end
			end
		end
		if not onIt then
			local mine, open, ready = {}, {}, {}
			for _, id in ipairs(q[3]) do
				if QuestForYou(QDB, id) then
					mine[#mine + 1] = id
					if not QuestDone(id) then
						open[#open + 1] = id
						if PreDone(QDB, id) then ready[#ready + 1] = id end
					end
				end
			end
			if #mine == 0 then
				rest[#rest + 1] = q   -- (the other faction's: the starters say so)
			elseif #open == 0 then
				ctx.allDone = ctx.allDone or q[2]
				if #list == 1 and Extra.Chain(mine[#mine]) then
					ctx.chainSeed = mine[#mine]
					rest[#rest + 1] = { q[1], q[2], { mine[#mine] }, q[4] }
					ctx.questNow = L["You've done \"%s\"."]:format(q[2])
				end
			else
				local ids = #ready > 0 and ready or open
				rest[#rest + 1] = { q[1], q[2], ids, q[4] }
				if #list == 1 then ctx.chainSeed = ids[1] end
			end
		end
	end
	return rest
end

--------------------------------------------------------------------------------
-- A quest's line: the quests before it and after it, as one list (each step's quest before it
-- and the one after it, of those you could take: your faction's and class's), and where you are
-- on it. For the drop-down, to show each step: to help a friend to the start of it, too
--------------------------------------------------------------------------------

local CHAIN_MAX = 40   -- steps each way at most (a loop in the data: no further)

local nextOf, prevOf   -- { [questId] = { the quests that need it done first } }; and { [questId] =
                       -- { the quests whose next it is } }, read once
local function NextOf(QDB)
	if nextOf then return nextOf, prevOf end
	nextOf, prevOf = {}, {}
	for _, id in ipairs(QDB.GetAllIds()) do
		local okN, nxt = pcall(QDB.Get, id, "nextQuestInChain")
		if okN and type(nxt) == "number" and nxt > 0 then
			prevOf[nxt] = prevOf[nxt] or {}
			prevOf[nxt][#prevOf[nxt] + 1] = id
		end
		for _, f in ipairs({ "preQuestSingle", "preQuestGroup" }) do
			local ok, pre = pcall(QDB.Get, id, f)
			for _, p in ipairs(ok and Ids(pre) or {}) do
				nextOf[p] = nextOf[p] or {}
				nextOf[p][#nextOf[p] + 1] = id
			end
		end
	end
	return nextOf, prevOf
end

local function QName(QDB, id)
	local ok, n = pcall(QDB.Get, id, "name")
	return ok and type(n) == "string" and n or nil
end

-- of a few quests, the one to follow: one you could take; of those, one of the same name as this
-- one (a line's steps share it often), then one for any class (a class's quest branching off a
-- line is a side line), then the lowest id
local function Follow(QDB, ids, name, class)
	local best, bestKey
	for _, id in ipairs(ids) do
		if QName(QDB, id) and QuestForYou(QDB, id) and ClassMayTake(QDB, id, class) then
			local okC, mask = pcall(QDB.Get, id, "requiredClasses")
			local anyClass = not (okC and type(mask) == "number" and mask > 0)
			local key = (QName(QDB, id) == name and 0 or 2) + (anyClass and 0 or 1)
			if not best or key < bestKey or (key == bestKey and id < best) then best, bestKey = id, key end
		end
	end
	return best
end

--- the line a quest is in: { steps = { { id, name, level, done, inLog }, ... }, at = the step
--- you're up to (nil: all done), look = the step asked for (nil: none) }, or nil when it's alone
function Extra.Chain(seed, look)
	local QDB = QuestDB()
	if not (QDB and seed and QName(QDB, seed)) then return end
	local class = select(2, UnitClass("player"))
	local ids, seen = { seed }, { [seed] = true }
	-- (back to its start)
	local id = seed
	for _ = 1, CHAIN_MAX do
		local ok1, single = pcall(QDB.Get, id, "preQuestSingle")
		local ok2, group = pcall(QDB.Get, id, "preQuestGroup")
		local pre = {}
		for _, p in ipairs(ok1 and Ids(single) or {}) do pre[#pre + 1] = p end
		for _, p in ipairs(ok2 and Ids(group) or {}) do pre[#pre + 1] = p end
		if #pre == 0 then pre = select(2, NextOf(QDB))[id] or {} end   -- (only the one before says it leads here)
		local p = Follow(QDB, pre, QName(QDB, id), class)
		if not p or seen[p] then break end
		seen[p] = true
		table.insert(ids, 1, p)
		id = p
	end
	-- (on to its end)
	id = seed
	for _ = 1, CHAIN_MAX do
		local ok, nxt = pcall(QDB.Get, id, "nextQuestInChain")
		local n = ok and type(nxt) == "number" and nxt > 0 and QName(QDB, nxt) and QuestForYou(QDB, nxt)
			and ClassMayTake(QDB, nxt, class) and nxt or nil
		n = n or Follow(QDB, (NextOf(QDB))[id] or {}, QName(QDB, id), class)
		if not n or seen[n] then break end
		seen[n] = true
		ids[#ids + 1] = n
		id = n
	end
	if #ids < 2 then return end
	local chain = { steps = {} }
	for i, q in ipairs(ids) do
		local okL, lv = pcall(QDB.Get, q, "questLevel")
		local s = { id = q, name = QName(QDB, q), level = okL and tonumber(lv) or nil, done = QuestDone(q),
			inLog = LogIndex(q) ~= nil }
		chain.steps[i] = s
		if not chain.at and (s.inLog or not s.done) then chain.at = i end
		if q == look then chain.look = i end
	end
	return chain
end

--- one step of a line, picked in the drop-down ("quest #422"): you're on it, where to go for it
--- now; else who starts it, done or not (for a friend)
function Extra.QuestStep(ctx, id)
	local QDB = QuestDB()
	local name = QDB and QName(QDB, id)
	if not name then return end
	local index = LogIndex(id)
	if index then
		QuestInLog(ctx, id, name, index)
	else
		if not QuestForYou(QDB, id) then ctx.otherSide = name end
		QuestStarters(ctx, { { QuestNorm(name), name, { id } } }, 0)
	end
	ctx.chainSeed, ctx.chainLook = id, id
	return name
end

--------------------------------------------------------------------------------
-- Quests for your level: "quests", "quests here", "quests in the barrens". Who starts the quests
-- you could pick up now (your faction's and class's; not done, not on; the quests before them
-- done; not grey, unless "all quests"), in the zone you're in or the one named. And the zones
-- with the most of the rest, to go on to
--------------------------------------------------------------------------------
do
-- 1: a quest word (one is needed); 2: grey ones too; 0: filler
local QH_WORDS = { quest = 1, quests = 1, giver = 0, givers = 0, here = 0, nearby = 0, near = 0, me = 0, ["for"] = 0,
	my = 0, level = 0, available = 0, around = 0, pick = 0, up = 0, can = 0, i = 0, ["to"] = 0, ["do"] = 0, what = 0,
	all = 2, grey = 2, gray = 2, trivial = 2, low = 2 }
-- holidays and events (their givers are there only while it's on), books and reputation
-- turn-ins (an item you hand in, not a quest to go and do): left out
local QH_EVENT = { [-284] = true, [-367] = true, [-404] = true, [-402] = true, [-378] = true, [-376] = true, [-375] = true, [-374] = true,
	[-370] = true, [-369] = true, [-366] = true, [-364] = true, [-41] = true, [-22] = true, [-21] = true,
	[-368] = true, [-365] = true, [-1000] = true }
local QH_ZONES = 3   -- other zones named, at most
local QH_ABOVE = 5   -- levels above yours a quest may be (red, at that)

--- a "quests here" search: { grey = all of them, grey ones too }, or nil
function Extra.QuestsHereQuery(query)
	local quest, grey = false, false
	for w in query:gmatch("%S+") do
		local k = QH_WORDS[w]
		if not k then return end
		if k == 1 then quest = true elseif k == 2 then grey = true end
	end
	if quest then return { grey = grey } end
end

local qhList   -- { { id, questLevel, requiredLevel, startedBy }, ... }: quests an NPC or thing starts, read once
local function QhList(QDB)
	if qhList then return qhList end
	qhList = {}
	for _, id in ipairs(QDB.GetAllIds()) do
		local ok, by = pcall(QDB.Get, id, "startedBy")
		local okZ, z = pcall(QDB.Get, id, "zoneOrSort")
		local okF, flags = pcall(QDB.Get, id, "specialFlags")
		local again = okF and type(flags) == "number" and flags % 2 == 1   -- (repeatable: turn-ins, mostly)
		if ok and type(by) == "table" and (#Ids(by[1]) > 0 or #Ids(by[2]) > 0) and not (okZ and QH_EVENT[z]) and not again then
			local okL, lv = pcall(QDB.Get, id, "questLevel")
			local okR, rq = pcall(QDB.Get, id, "requiredLevel")
			qhList[#qhList + 1] = { id, okL and tonumber(lv) or 0, okR and tonumber(rq) or 0, by }
		end
	end
	return qhList
end

-- your standing with a faction meets a quest's { factionId, value } (at least; or under, for most)
local function RepOk(rep, most)
	if type(rep) ~= "table" or not rep[1] then return true end
	if not GetFactionInfoByID then return false end
	local ok, name, _, _, _, _, value = pcall(GetFactionInfoByID, rep[1])
	if not (ok and name and type(value) == "number") then return most and true or false end
	if most then return value < rep[2] end
	return value >= rep[2]
end

-- a quest you could pick up now (its level and faction aside)
local function Takeable(QDB, ctx, id, me)
	if not (QuestForYou(QDB, id) and ClassMayTake(QDB, id, ctx.class)) then return false end
	if QuestDone(id) or LogIndex(id) or not PreDone(QDB, id) then return false end
	local function F(k) local ok, v = pcall(QDB.Get, id, k) if ok then return v end end
	for _, x in ipairs(Ids(F("exclusiveTo"))) do if QuestDone(x) or LogIndex(x) then return false end end
	for _, x in ipairs(Ids(F("disabledByQuest"))) do if QuestDone(x) then return false end end
	local parent = F("parentQuest")
	if type(parent) == "number" and parent > 0 and not LogIndex(parent) then return false end
	local leadsTo = F("breadcrumbForQuestId")   -- (a breadcrumb: not once its quest's taken)
	if type(leadsTo) == "number" and leadsTo > 0 and (QuestDone(leadsTo) or LogIndex(leadsTo)) then return false end
	local most = tonumber(F("requiredMaxLevel"))
	if most and most > 0 and me > most then return false end
	local skill = F("requiredSkill")   -- (a profession's: only if you have it)
	if type(skill) == "table" and skill[1] and not ctx.profs[skill[1]] then return false end
	return RepOk(F("requiredMinRep")) and RepOk(F("requiredMaxRep"), true)
end

local zoneOf = {}
-- the zone a map's in (its own, a town's or a cave's parent); nil: a dungeon's, or above a zone
local function ZoneOf(ui)
	local v = zoneOf[ui]
	if v == nil then
		v = false
		local id = ui
		for _ = 1, 6 do
			local info = id and C_Map.GetMapInfo(id)
			if not info or info.mapType == 4 or info.mapType < 3 then break end
			if info.mapType == 3 then v = id break end
			id = info.parentMapID
		end
		zoneOf[ui] = v
	end
	return v or nil
end

-- "[12] Name", the level in the game's colour for how hard it is for you
local function Tagged(lv, name)
	local tag = ("[%d]"):format(lv)
	local ok, c = false, nil
	if GetQuestDifficultyColor then ok, c = pcall(GetQuestDifficultyColor, lv) end
	if ok and type(c) == "table" and c.r then
		tag = ("|cff%02x%02x%02x%s|r"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), tag)
	end
	return tag .. " " .. name
end

--- the quests to pick up in a zone (zone: its map; nil, the one you're in), on the map. Returns how
--- many, the other zones with the most ("The Barrens (14), Stonetalon Mountains (6)") or nil, and
--- the zone's map; or nil and why not
function Extra.QuestsHere(ctx, opts, zone)
	local QDB = QuestDB()
	if not (QDB and QDB.GetAllIds and QDB.Get) then return nil, L["QuestieDB's quest data isn't available."] end
	zone = zone or (not ctx.zoneOk and ZoneHere()) or nil
	local inside = ctx.zoneOk or (zone and function(ui) return ZoneOf(ui) == zone end)
	if not inside then return nil, L["Can't tell which zone you're in."] end
	local me = UnitLevel("player") or 1
	local okG, green = false, nil
	if GetQuestGreenRange then okG, green = pcall(GetQuestGreenRange, "player") end
	green = okG and tonumber(green) or 5
	local ObjDB = ns.Index.ObjectDB()
	local givers, order, counts, n = {}, {}, {}, 0
	for _, q in ipairs(QhList(QDB)) do
		local id, lv, rq = q[1], q[2], q[3]
		if lv <= 0 then lv = me end   -- (one of your level, whatever it is)
		if rq <= me and lv <= me + QH_ABOVE and (opts.grey or me - lv <= green) and Takeable(QDB, ctx, id, me) then
			local okN, name = pcall(QDB.Get, id, "name")
			local title = Tagged(lv, okN and type(name) == "string" and name or "?")
			local zones, here = {}, false
			for i = 1, 2 do
				local isObj = i == 2
				for _, gid in ipairs((isObj and not ObjDB) and {} or Ids(q[4][i])) do
					local e
					if isObj then
						local okO, oname = pcall(ObjDB.Get, gid, "name")
						if okO and type(oname) == "string" then
							e = ctx.byId[-gid] and ctx.byId[-gid].entry or { obj = true, id = -gid, objectId = gid, name = oname }
						end
					else
						e = ns.Index.byId[gid]
						if e and not NpcOk(ctx, e) then e = nil end
					end
					local pts = e and Points(isObj and ObjDB or ctx.NpcDB, gid, isObj)
					local mine = {}
					for _, p in ipairs(pts or {}) do
						local z = ZoneOf(p.ui)
						if z then zones[z] = true end
						if inside(p.ui) then mine[#mine + 1] = p end
					end
					if #mine > 0 then
						here = true
						local g = givers[e.id]
						if not g then
							g = { e = e, pts = mine, quests = {} }
							givers[e.id] = g
							order[#order + 1] = g
						end
						g.quests[#g.quests + 1] = { lv, title, name }
					end
				end
			end
			if here then
				n = n + 1
			else
				for z in pairs(zones) do if z ~= zone then counts[z] = (counts[z] or 0) + 1 end end
			end
		end
	end
	for _, g in ipairs(order) do
		table.sort(g.quests, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
		local r = Add(ctx, g.e, g.pts, { kind = "QUEST", quests = {}, questStart = true })
		for _, t in ipairs(g.quests) do Search.TitleQuest(r, t[2], t[3]) end   -- (one name twice, a quest for each race: once)
		r.rank = 0
	end
	local best = {}
	for z, c in pairs(counts) do best[#best + 1] = { z, c, ns.ZoneName(z) or "?" } end
	table.sort(best, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[3] < b[3] end)
	local more = {}
	for i = 1, math.min(QH_ZONES, #best) do more[i] = ("%s (%d)"):format(best[i][3], best[i][2]) end
	return n, #more > 0 and table.concat(more, ", ") or nil, zone
end
Extra.RepOk = RepOk
end

-- (reputation turn-ins: a block of their own, for Lua's count of locals)
do
local RepOk = Extra.RepOk

--------------------------------------------------------------------------------
-- Reputation turn-ins: "timbermaw rep" (with its quartermaster), "rep farms" (every faction's).
-- Who takes the repeatable quests that raise a faction, those you could hand in now (your
-- faction's and class's, your level, your standing in its range: not once it stops paying), with
-- what to bring on the marker; and the things to bring, for the drop-down: where each drops, and
-- a loop to farm it
--------------------------------------------------------------------------------

-- the factions with turn-ins, by id: their names in English, to find them by (the game's own
-- name, in your language, as well)
local REP_NAMES = {
	[21] = "Booty Bay", [47] = "Ironforge", [54] = "Gnomeregan Exiles", [59] = "Thorium Brotherhood",
	[68] = "Undercity", [69] = "Darnassus", [72] = "Stormwind", [76] = "Orgrimmar", [81] = "Thunder Bluff",
	[169] = "Steamwheedle Cartel", [270] = "Zandalar Tribe", [349] = "Ravenholdt", [369] = "Gadgetzan",
	[470] = "Ratchet", [471] = "Wildhammer Clan", [509] = "League of Arathor", [510] = "The Defilers",
	[529] = "Argent Dawn", [530] = "Darkspear Trolls", [576] = "Timbermaw Hold", [577] = "Everlook",
	[589] = "Wintersaber Trainers", [609] = "Cenarion Circle", [729] = "Frostwolf Clan", [730] = "Stormpike Guard",
	[809] = "Shen'dralar", [889] = "Warsong Outriders", [890] = "Silverwing Sentinels", [910] = "Brood of Nozdormu",
}
local REP_SKIP = { [909] = true }   -- (the Darkmoon Faire: its people are there only while it's in town)
local REP_ITEMS = 6                 -- things to bring in the drop-down, at most

local repIndex   -- { [factionId] = { quest ids } }: the repeatable quests that raise it, read once
local function RepIndex(QDB)
	if repIndex then return repIndex end
	repIndex = {}
	for _, id in ipairs(QDB.GetAllIds()) do
		local okF, flags = pcall(QDB.Get, id, "specialFlags")
		if okF and type(flags) == "number" and flags % 2 == 1 then
			local okR, rr = pcall(QDB.Get, id, "reputationReward")
			for _, r in ipairs(okR and type(rr) == "table" and rr or {}) do
				local fid = type(r) == "table" and r[1]
				if type(fid) == "number" and not REP_SKIP[fid] and (tonumber(r[2]) or 1) > 0 then
					repIndex[fid] = repIndex[fid] or {}
					local t = repIndex[fid]
					if t[#t] ~= id then t[#t + 1] = id end
				end
			end
		end
	end
	return repIndex
end

-- a faction's name: the game's (your language), else ours
local function RepName(fid)
	if GetFactionInfoByID then
		local ok, name = pcall(GetFactionInfoByID, fid)
		if ok and type(name) == "string" and name ~= "" then return name end
	end
	return REP_NAMES[fid]
end

-- the factions with turn-ins whose names have every word asked ("argent dawn", "timbermaw")
local function RepFactions(words)
	local list = {}
	local want = {}
	for w in words:gmatch("%S+") do want[#want + 1] = w end
	for fid in pairs(RepIndex(QuestDB())) do
		for _, n in ipairs({ REP_NAMES[fid] or "", RepName(fid) or "" }) do
			local l = " " .. lower(n):gsub("'", "")
			local all = n ~= ""
			for _, w in ipairs(want) do
				if not find(l, " " .. w, 1, true) then all = false break end
			end
			if all then list[#list + 1] = fid break end
		end
	end
	table.sort(list)
	return list
end

-- a turn-in you could do now (your faction's and class's, your level, your profession if it asks one,
-- your standing in its range; the quests before it done, unless anyPre). false, "pre": all but
-- the quests before it
local function RepTakeable(QDB, ctx, id, me, anyPre)
	if not (QuestForYou(QDB, id) and ClassMayTake(QDB, id, ctx.class)) then return false end
	local function F(k) local ok, v = pcall(QDB.Get, id, k) if ok then return v end end
	if (tonumber(F("requiredLevel")) or 0) > me then return false end
	local most = tonumber(F("requiredMaxLevel"))
	if most and most > 0 and me > most then return false end
	local skill = F("requiredSkill")
	if type(skill) == "table" and skill[1] and not ctx.profs[skill[1]] then return false end
	if not (RepOk(F("requiredMinRep")) and RepOk(F("requiredMaxRep"), true)) then return false end
	if not anyPre and not PreDone(QDB, id) then return false, "pre" end
	return true
end

-- the first quest to do before a turn-in opens (back through the ones before it, yours, not done)
local function FirstToDo(QDB, id)
	for _ = 1, 10 do
		local back
		for _, k in ipairs({ "preQuestSingle", "preQuestGroup" }) do
			local ok, v = pcall(QDB.Get, id, k)
			for _, p in ipairs(ok and Ids(v) or {}) do
				if QuestForYou(QDB, p) and not QuestDone(p) then back = p break end
			end
			if back then break end
		end
		if not back then return id end
		id = back
	end
end

--- the turn-ins for these factions, on the map. Returns how many (by name), and the things to
--- bring, the most asked for first: { { itemId, name, icon }, ... }
function Extra.RepTurnIns(ctx, factions)
	local QDB, ItemDB, ObjDB = QuestDB(), ns.Index.ItemDB(), ns.Index.ObjectDB()
	if not (QDB and QDB.GetAllIds) then return 0, {} end
	local me = UnitLevel("player") or 1
	local idx = RepIndex(QDB)
	local names, n, items, itemList = {}, 0, {}, {}
	for _, fid in ipairs(factions) do
		for _, id in ipairs(idx[fid] or {}) do
			-- (one that opens only after another quest: that one, to do first)
			local okT, why = RepTakeable(QDB, ctx, id, me)
			local show = okT and id or nil
			if why == "pre" then
				local first = FirstToDo(QDB, id)
				if first and first ~= id and RepTakeable(QDB, ctx, first, me, true) then show = first end
			end
			if show then
				local okN, name = pcall(QDB.Get, id, "name")
				name = okN and type(name) == "string" and name or "?"
				local okO, objs = pcall(QDB.Get, id, "objectives")
				local bring = {}
				for _, it in ipairs((show == id and okO and type(objs) == "table" and type(objs[3]) == "table") and objs[3] or {}) do
					local iid = type(it) == "table" and it[1]
					local okI, iname = false, nil
					if iid and ItemDB then okI, iname = pcall(ItemDB.Get, iid, "name") end
					if okI and type(iname) == "string" then bring[#bring + 1] = { iid, iname } end
				end
				local bringNames = {}
				for i, b in ipairs(bring) do bringNames[i] = b[2] end
				local title = #bring > 0 and L["%s: bring %s"]:format(name, table.concat(bringNames, ", ")) or name
				local showName = name   -- (the quest the marker shows on a right-click: the one it starts)
				if show ~= id then
					local okF, fname = pcall(QDB.Get, show, "name")
					showName = okF and type(fname) == "string" and fname or name
					title = L["%s: do it first, to open %s"]:format(showName, name)
				end
				local okB, by = pcall(QDB.Get, show, "startedBy")
				local put = false
				for i = 1, 2 do
					local isObj = i == 2
					for _, gid in ipairs((okB and type(by) == "table" and not (isObj and not ObjDB)) and Ids(by[i]) or {}) do
						local e
						if isObj then
							local okG, oname = pcall(ObjDB.Get, gid, "name")
							if okG and type(oname) == "string" then
								e = ctx.byId[-gid] and ctx.byId[-gid].entry or { obj = true, id = -gid, objectId = gid, name = oname }
							end
						else
							e = ns.Index.byId[gid]
							if e and not NpcOk(ctx, e) then e = nil end
						end
						-- (one marked already, a quartermaster who takes them too: on its marker)
						local r = e and ctx.byId[e.id]
						if e and not r then
							local pts = Points(isObj and ObjDB or ctx.NpcDB, gid, isObj, ctx.zoneOk)
							if pts then
								r = Add(ctx, e, pts, { kind = "QUEST" })
								r.rank = 0
							end
						end
						if r then
							r.questStart = true
							Search.TitleQuest(r, title, showName)
							put = true
						end
					end
				end
				if put and not names[name] then names[name] = true n = n + 1 end
				-- (what it asks for, of one that's on the map, that something drops: for the drop-down)
				for _, b in ipairs(put and bring or {}) do
					local t = items[b[1]]
					if t == nil then
						local okD, npcs = pcall(ItemDB.Get, b[1], "npcDrops")
						local okO2, objs2 = pcall(ItemDB.Get, b[1], "objectDrops")
						if #(okD and Ids(npcs) or {}) + #(okO2 and Ids(objs2) or {}) == 0 then
							t = false
							items[b[1]] = false
						end
					end
					if t == nil then
						local icon
						if GetItemIcon then local okC, c = pcall(GetItemIcon, b[1]) if okC then icon = c end end
						t = { b[1], b[2], icon, 0 }
						items[b[1]] = t
						itemList[#itemList + 1] = t
					end
					if t then t[4] = t[4] + 1 end
				end
			end
		end
	end
	table.sort(itemList, function(a, b) if a[4] ~= b[4] then return a[4] > b[4] end return a[2] < b[2] end)
	local out = {}
	for i = 1, math.min(REP_ITEMS, #itemList) do out[i] = itemList[i] end
	return n, out
end

--- the factions asked for by a quartermaster search's words ("timbermaw"), with turn-ins
Extra.RepFactions = RepFactions
Extra.RepName = RepName

local REP_FARM_WORDS = { rep = 1, reputation = 1, farm = 2, farms = 2, farming = 2, grind = 2, grinds = 2,
	grinding = 2, turnins = 2, ["turn-ins"] = 2, repeatable = 2, repeatables = 2, turn = 0, ins = 0, ["in"] = 0,
	quests = 0, quest = 0, my = 0, ["for"] = 0, all = 0, where = 0, can = 0, i = 0, best = 0 }
--- "rep farms", "reputation turn-ins", "rep grinds": true
function Extra.RepFarmsQuery(query)
	local rep, farm = false, false
	for w in query:gmatch("%S+") do
		local k = REP_FARM_WORDS[w]
		if not k then return end
		if k == 1 then rep = true elseif k == 2 then farm = true end
	end
	return rep and farm
end

--- every faction you could hand turn-ins in to now: their givers on the map; and the factions,
--- for the drop-down ({ { name, how many }, ... }, the most first)
function Extra.RepFarms(ctx)
	local QDB = QuestDB()
	if not (QDB and QDB.GetAllIds) then return {} end
	local list = {}
	for fid in pairs(RepIndex(QDB)) do
		local name = RepName(fid)
		if name then
			local n = Extra.RepTurnIns(ctx, { fid })
			if n > 0 then list[#list + 1] = { name, n } end
		end
	end
	table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
	return list
end
end
end

--------------------------------------------------------------------------------
-- A dungeon's quests: "deadmines quests", "quests for brd", "sm quests". Who starts each quest
-- filed under that dungeon that you could still take (your faction, your class, not done): to
-- pick them all up before you go in. Of a line of them, the first you haven't done
--------------------------------------------------------------------------------

local DQ_LEAD = { "for", "in", "at", "from" }

--- a dungeon quest search: the dungeon (a place with its area), or nil
local function DungeonQuestQuery(query)
	local rest, n = query:gsub("%f[%a]quests?%f[%A]", "")
	if n == 0 then return end
	rest = strtrim(rest:gsub("%s+", " "))
	for _, w in ipairs(DQ_LEAD) do
		if rest:sub(1, #w + 1) == w .. " " then rest = rest:sub(#w + 2) break end
	end
	rest = strtrim(rest:gsub("^dungeon ", ""):gsub(" dungeon$", ""))
	if rest == "" then return end
	local p = Search.Place(rest)
	if p and p.kind == "dungeon" and (p.area or p.quests) then return p end
end
Search.DungeonQuestQuery = DungeonQuestQuery

local questsByArea   -- { [areaId] = { quest ids } }, read once
local function QuestsIn(p)
	local QDB = QuestDB()
	if not (QDB and QDB.GetAllIds and QDB.Get) then return {} end
	if not questsByArea then
		questsByArea = {}
		for _, id in ipairs(QDB.GetAllIds()) do
			local ok, z = pcall(QDB.Get, id, "zoneOrSort")
			if ok and type(z) == "number" and z > 0 then
				local t = questsByArea[z]
				if not t then t = {} questsByArea[z] = t end
				t[#t + 1] = id
			end
		end
	end
	local ids, seen = {}, {}
	local function Take(id) if not seen[id] then seen[id] = true ids[#ids + 1] = id end end
	for _, a in ipairs({ p.area, unpack(p.alts or {}) }) do
		for _, id in ipairs(questsByArea[a] or {}) do Take(id) end
	end
	-- (a dungeon whose quests the data files under no zone: the ids kept by hand, those the data has)
	for _, id in ipairs(p.quests or {}) do
		local ok, name = pcall(QDB.Get, id, "name")
		if ok and type(name) == "string" then Take(id) end
	end
	table.sort(ids)
	return ids
end

local function DungeonQuests(ctx, p)
	local QDB = QuestDB()
	local mine = {}
	-- (why none, when there are none: how many it has, the other faction's, other classes', done)
	local why = { all = 0, faction = 0, class = 0, done = 0 }
	for _, id in ipairs(QuestsIn(p)) do
		why.all = why.all + 1
		if not QuestForYou(QDB, id) then why.faction = why.faction + 1
		elseif not ClassMayTake(QDB, id, ctx.class) then why.class = why.class + 1
		elseif QuestDone(id) then why.done = why.done + 1
		else mine[id] = true end
	end
	-- (a step of a line whose earlier step is still to do: that earlier one's starter shows it)
	local list = {}
	for id in pairs(mine) do
		local later = false
		for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
			local ok, v = pcall(QDB.Get, id, key)
			for _, pre in ipairs(ok and Ids(v) or {}) do
				if mine[pre] then later = true break end
			end
			if later then break end
		end
		if not later then
			local okN, name = pcall(QDB.Get, id, "name")
			local okL, level = pcall(QDB.Get, id, "questLevel")
			if okN and type(name) == "string" then
				level = okL and tonumber(level)
				list[#list + 1] = { QuestNorm(name), level and level > 0 and ("[%d] %s"):format(level, name) or name, { id },
					level or 0, name = name }
			end
		end
	end
	table.sort(list, function(a, b) if a[4] ~= b[4] then return a[4] < b[4] end return a[1] < b[1] end)
	QuestStarters(ctx, list, 0)
	return why
end

--------------------------------------------------------------------------------
-- Attunements and keys: "mc attunement", "onyxia attunement", "ubrs key", "attunements" (all of
-- them). Where each line starts, or the first step of it you haven't done
--------------------------------------------------------------------------------

local ATTUNE_WORDS = { attunement = true, attunements = true, attune = true, attuned = true, key = true, keys = true }
local ATTUNE_FILLER = { the = true, ["for"] = true, ["to"] = true, quest = true, quests = true, chain = true,
	questline = true, line = true, get = true, how = true, where = true, ["do"] = true, i = true, my = true,
	all = true, start = true, starts = true, raid = true, dungeon = true }
-- the dungeon (lower case, apostrophes gone) -> the quests that attune you or give its key (the
-- last of the line: walked back to where it starts), by id: WoW Forever's, checked against its data
local ATTUNEMENTS = {
	{ "molten core", { 7848 } },             -- Attunement to the Core
	{ "onyxias lair", { 6502, 6602 } },      -- Drakefire Amulet; Blood of the Black Dragon Champion
	{ "blackwing lair", { 7761 } },          -- Blackhand's Command (an item that drops starts it)
	{ "blackrock spire", { 4743 } },         -- Seal of Ascension (Upper Blackrock Spire)
	{ "blackrock depths", { 3802 } },        -- Dark Iron Legacy (the Shadowforge Key)
	{ "scholomance", { 5505, 5511 } },       -- The Key to Scholomance
	{ "naxxramas", { 9121, 9122, 9123 } },   -- The Dread Citadel - Naxxramas
}

--- an attunement search: the ATTUNEMENTS rows asked for (all of them for "attunements"), or nil
local function AttuneQuery(query)
	local asked, words = false, {}
	for w in query:gmatch("%S+") do
		if ATTUNE_WORDS[w] then asked = true elseif not ATTUNE_FILLER[w] then words[#words + 1] = w end
	end
	if not asked then return end
	if #words == 0 then
		if query:find("attun", 1, true) then return ATTUNEMENTS end
		return
	end
	local rest = table.concat(words, " ")
	local p = Search.Place(rest)
	local l = p and p.kind == "dungeon" and lower(p.name):gsub("'", "")
	for _, a in ipairs(ATTUNEMENTS) do
		if a[1] == l then return { a } end
	end
	-- (the start of its name: "onyxia")
	if #rest >= 4 then
		for _, a in ipairs(ATTUNEMENTS) do
			if a[1]:sub(1, #rest) == rest then return { a } end
		end
	end
end
Search.AttuneQuery = AttuneQuery

-- where a line ending in id starts for you: back through the steps before it (yours), to the
-- first not done. nil when the last is done
local function LineStart(QDB, id)
	if QuestDone(id) then return end
	for _ = 1, 30 do
		local back
		for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
			local ok, v = pcall(QDB.Get, id, key)
			for _, pre in ipairs(ok and Ids(v) or {}) do
				if QuestForYou(QDB, pre) and not QuestDone(pre) then back = pre break end
			end
			if back then break end
		end
		if not back then return id end
		id = back
	end
	return id
end

-- the starts of the lines asked for; how many you've done all of, and the first start's name
local function Attunements(ctx, rows)
	local QDB = QuestDB()
	local list, seen, done, first = {}, {}, 0, nil
	for _, a in ipairs(rows) do
		local p = Search.Place(a[1])
		local any, all = false, true
		for _, id in ipairs(a[2]) do
			if QuestForYou(QDB, id) then
				any = true
				local start = LineStart(QDB, id)
				if start then
					all = false
					local ok, name = pcall(QDB.Get, start, "name")
					if ok and type(name) == "string" and not seen[start] then
						seen[start], first = true, first or name
						list[#list + 1] = { QuestNorm(name), L["%s, for %s"]:format(name, p and p.name or a[1]), { start }, name = name }
					end
				end
			end
		end
		if any and all then done = done + 1 end
	end
	QuestStarters(ctx, list, 0)
	return done, first
end

--------------------------------------------------------------------------------
-- Food, water and ammunition: "water", "food", "arrows", "bullets", "ammo". The vendors of the
-- best you can use at your level (each kind of food's best, for "food"; for "ammo", what your
-- ranged weapon shoots). The vendors' own wares, WoW Forever's, by id
--------------------------------------------------------------------------------

local SUPPLIES = {
	water = { 159, 1179, 1205, 1708, 1645, 8766 },     -- Refreshing Spring Water .. Morning Glory Dew
	bread = { 4540, 4541, 4542, 4544, 4601, 8950 },    -- Tough Hunk of Bread .. Homemade Cherry Pie
	meat = { 117, 2287, 3770, 3771, 4599, 8952 },      -- Tough Jerky .. Roasted Quail
	cheese = { 2070, 414, 422, 1707, 3927, 8932 },     -- Darnassian Bleu .. Alterac Swiss
	fruit = { 4536, 4537, 4538, 4539, 4602, 8953 },    -- Shiny Red Apple .. Deep Fried Plantains
	fish = { 787, 4592, 4593, 4594, 21552, 8957 },     -- Slitherskin Mackerel .. Spinefin Halibut
	fungus = { 4604, 4605, 4606, 4607, 4608, 8948 },   -- Forest Mushroom Cap .. Dried King Bolete
	arrow = { 2512, 2515, 3030, 11285 },               -- Rough Arrow .. Jagged Arrow
	bullet = { 2516, 2519, 3033, 11284 },              -- Light Shot .. Accurate Slugs
}
local FOODS = { "bread", "meat", "cheese", "fruit", "fish", "fungus" }
local SUPPLY_WORDS = { water = { "water" }, drink = { "water" }, drinks = { "water" }, food = FOODS,
	arrow = { "arrow" }, arrows = { "arrow" }, bullet = { "bullet" }, bullets = { "bullet" },
	ammo = "ammo", ammunition = "ammo" }
local SUPPLY_FILLER = { best = true, my = true, ["for"] = true, level = true, vendor = true, vendors = true,
	buy = true, where = true, ["to"] = true, i = true, can = true, ["and"] = true, some = true, good = true,
	sells = true, seller = true, sellers = true, get = true, me = true, ["&"] = true }

-- what your ranged weapon shoots: { "arrow" } or { "bullet" }; nil when none or it can't be told
local function AmmoKinds()
	local id = GetInventoryItemID and GetInventoryItemID("player", 18)
	if not (id and GetItemInfoInstant) then return end
	local _, _, _, _, _, class, sub = GetItemInfoInstant(id)
	if class ~= 2 then return end
	if sub == 2 or sub == 18 then return { "arrow" } end   -- (bows, crossbows)
	if sub == 3 then return { "bullet" } end              -- (guns)
end

--- a supply search: the SUPPLIES kinds asked for, or nil
local function SupplyQuery(query)
	local kinds, seen = {}, {}
	for w in query:gmatch("%S+") do
		local k = SUPPLY_WORDS[w]
		if k == "ammo" then k = AmmoKinds() or { "arrow", "bullet" } end
		if k then
			for _, x in ipairs(k) do if not seen[x] then seen[x] = true kinds[#kinds + 1] = x end end
		elseif not SUPPLY_FILLER[w] then
			return
		end
	end
	if #kinds > 0 then return kinds end
end
Search.SupplyQuery = SupplyQuery

local soldById
local function SoldById(id)
	if not soldById then
		soldById = {}
		for _, it in ipairs(ns.Index.items) do soldById[it.id] = it end
	end
	return soldById[id]
end

-- the vendors of the best of each kind you can use; the names of those bests
local function Supplies(ctx, kinds)
	local level, names = UnitLevel("player") or 1, {}
	local ItemDB = ns.Index.ItemDB()
	for _, k in ipairs(kinds) do
		local best, bestLevel
		for _, id in ipairs(SUPPLIES[k]) do
			local it = SoldById(id)
			local ok, need = pcall(ItemDB.Get, id, "requiredLevel")
			need = ok and tonumber(need) or 1
			if it and need <= level and (not bestLevel or need >= bestLevel) then best, bestLevel = it, need end
		end
		if best then
			names[#names + 1] = best.name
			SellItem(ctx, best, 0)
		end
	end
	return names
end

Extra.DungeonQuestQuery, Extra.DungeonQuests = DungeonQuestQuery, DungeonQuests
Extra.AttuneQuery, Extra.Attunements = AttuneQuery, Attunements
Extra.SupplyQuery, Extra.Supplies = SupplyQuery, Supplies
end   -- (one block: Search.lua is near Lua's limit of locals at its top level)

-- the professions you have (Questie keeps them), and whether both main ones are taken
local function Professions()
	local profs, n = {}, 0
	local QP = Questie("QuestieProfessions")
	local ok, list = false, nil
	if QP and QP.GetPlayerProfessions then ok, list = pcall(QP.GetPlayerProfessions, QP) end
	if ok and type(list) == "table" then
		for id in pairs(list) do
			profs[id] = true
			if PRIMARY[id] then n = n + 1 end
		end
		return profs, n >= 2
	end
	return profs, false   -- (unknown: leave none out)
end

--- Returns a sorted list of { entry, points, near, rank, kind?, sells?, quests? } (or nil, a
--- message, nil, and true when it simply found nothing), and the service the query asks for (an npcFlags name, e.g. "REPAIR"), if any:
--- the markers' icon.
-- found nothing in the zone the map shows ("only the zone" on): how many there are elsewhere, and
-- where ("12 in Westfall, Duskwood and Redridge Mountains"), or nil when there are none anywhere
local function Elsewhere(query)
	local all = Search.Run(query, true)
	if not all then return end
	local zones, names = {}, {}
	for _, r in ipairs(all) do
		for _, p in ipairs(r.points) do
			if not zones[p.ui] then
				zones[p.ui] = true
				names[#names + 1] = ns.ZoneName(p.ui) or "?"
			end
		end
	end
	local where
	if #names <= 3 then
		where = #names == 1 and names[1] or L["%s and %s"]:format(table.concat(names, ", ", 1, #names - 1), names[#names])
	else
		where = L["%d other zones"]:format(#names)
	end
	return L["%d in %s"]:format(#all, where)
end

--- everywhere: leave out "only the zone the map shows" (to count what's elsewhere)
--------------------------------------------------------------------------------
-- Places: the continents, zones, cities and dungeons with a map of their own, by name. A search
-- that names one takes the map there (UI.lua) rather than looking for NPCs
--------------------------------------------------------------------------------

local AZEROTH = 947
local CITIES = { ["stormwind city"] = true, orgrimmar = true, ironforge = true, ["thunder bluff"] = true,
	darnassus = true, undercity = true }
-- dungeons, raids and battlegrounds by the short names players use (their names in lower case, as
-- Questie has them). "dm" is the Deadmines, as it was in Classic; Dire Maul has its wings'
local PLACE_SHORT = {
	-- the cities, and towns players shorten
	orgrimmar = "org,ogri", ["stormwind city"] = "sw", ironforge = "if", ["thunder bluff"] = "tb",
	undercity = "uc", darnassus = "darn", ["the crossroads"] = "xroads,xr", ["booty bay"] = "bb",
	-- the zones players shorten
	["stranglethorn vale"] = "stv", ["eastern plaguelands"] = "epl", ["western plaguelands"] = "wpl",
	["hillsbrad foothills"] = "hf,hb,hills", ["thousand needles"] = "tn,1k needles,1000 needles",
	["dustwallow marsh"] = "dwm,dustwallow", ["stonetalon mountains"] = "stm,stonetalon",
	["searing gorge"] = "sg", ["burning steppes"] = "steppes", ["blasted lands"] = "bl", ["swamp of sorrows"] = "sos",
	["redridge mountains"] = "rr,rrm,redridge", ["loch modan"] = "lm", ["elwynn forest"] = "ef,elwynn",
	["deadwind pass"] = "dwp", ["westfall"] = "wf", ["wetlands"] = "wl", ["silverpine forest"] = "spf,silverpine",
	["tirisfal glades"] = "tg,tirisfal", ["the hinterlands"] = "hl,hinterlands", ["alterac mountains"] = "alterac",
	["arathi highlands"] = "arathi", ["un'goro crater"] = "ungoro,un goro", ["the barrens"] = "barrens",

	["ragefire chasm"] = "rfc", ["wailing caverns"] = "wc", ["the deadmines"] = "dm,vc",
	["shadowfang keep"] = "sfk", ["blackfathom deeps"] = "bfd", ["the stockade"] = "stocks,stormwind stockade",
	["gnomeregan"] = "gnomer", ["razorfen kraul"] = "rfk", ["scarlet monastery"] = "sm",
	["razorfen downs"] = "rfd", ["uldaman"] = "ulda,uld", ["zul'farrak"] = "zf,zulfarrak", ["maraudon"] = "mara",
	["the temple of atal'hakkar"] = "st,sunken temple,atal'hakkar", ["blackrock depths"] = "brd",
	["blackrock spire"] = "brs,lbrs,ubrs,lower blackrock spire,upper blackrock spire",
	["dire maul"] = "dme,dmw,dmn,dm east,dm west,dm north",
	["stratholme"] = "strat,strath", ["scholomance"] = "scholo", ["molten core"] = "mc",
	["onyxia's lair"] = "ony", ["blackwing lair"] = "bwl", ["zul'gurub"] = "zg,zulgurub",
	["ruins of ahn'qiraj"] = "aq20,raq", ["temple of ahn'qiraj"] = "aq40,taq", ["naxxramas"] = "naxx",
	["alterac valley"] = "av", ["warsong gulch"] = "wsg", ["arathi basin"] = "ab", ["karazhan"] = "kara",
	["deeprun tram"] = "tram",
	-- WoW Forever's
	["the drowned city"] = "drowned,dc", ["krol'dok stronghold"] = "kroldok,krol'dok,ks",
	["alcaz island prison"] = "alcaz prison,ap", ["the shaper's terrace"] = "shaper's terrace,shapers terrace",
}

-- WoW Forever's own dungeons that Questie's list hasn't: name, the zone's map, the entrance (0..100).
-- (Entrances as FojjiCore's dungeon journal has them, from Warcraft Tavern)
-- dungeons of later expansions, which Questie's list (one for every expansion) and the game's maps
-- have but WoW Forever hasn't: never offered, though their entrances are in zones Forever has
local NOT_IN_FOREVER = {}
for name in ([[utgarde keep;utgarde pinnacle;the black morass;old hillsbrad foothills;hellfire ramparts;
hyjal summit;serpentshrine cavern;serpentshire cavern;the blood furnace;the shattered halls;the steamvault;
the underbog;the slave pens;shadow labyrinth;auchenai crypts;sethekk halls;mana-tombs;zul'aman;
magtheridon's lair;tempest keep;the botanica;the arcatraz;the mechanar;gruul's lair;black temple;
sunwell plateau;the culling of stratholme;magisters' terrace;drak'tharon keep;the oculus;halls of stone;
the nexus;halls of lightning;ulduar;azjol-nerub;the violet hold;gundrak;the obsidian sanctum;
ahn'kahet: the old kingdom;the eye of eternity;vault of archavon;trial of the crusader;
trial of the champion;the forge of souls;icecrown citadel;pit of saron;halls of reflection;
blackrock caverns;grim batol;halls of origination;the ruby sanctum;throne of the tides;
the vortex pinnacle;the stonecore;blackwing descent;the bastion of twilight;lost city of the tol'vir;
baradin hold;throne of the four winds;firelands;molten front;well of eternity;end time;
hour of twilight;darkmoon faire island;dragon soul;shado-pan monastery;temple of the jade serpent;
stormstout brewery;gate of the setting sun;scarlet halls;terrace of endless spring;mogu'shan vaults;
mogu'shan palace;siege of niuzao temple;heart of fear;brawl'gar arena;bizmo's brawlpub;
throne of thunder;siege of orgrimmar]]):gmatch("[^;]+") do
	NOT_IN_FOREVER[strtrim(name)] = true
end

-- { name, uiMapID, x, y, area, quests }: area is the dungeon's own area id, which QuestieDB files
-- a quest under when it knows to (The Shaper's Terrace's are); quests are the ids of its quests
-- kept by hand where QuestieDB files them under no zone at all (the data has neither the
-- dungeon's area on the quests nor its mobs' spawns, as of QuestieDB 1.1.1). The hand lists are
-- the quests whose targets are mobs the data places nowhere (inside, then) and the chain steps
-- around them; both factions' versions. Drop a list once QuestieDB files that dungeon's quests
local FOREVER_DUNGEONS = {
	{ "The Drowned City", 1434, 21.4, 27.9, nil,    -- Stranglethorn Vale: Sunken Hollow, past the Vile Reef (QuestieDB knows no area for it)
		{ 95775, 95787, 95788, 96774, 97130,           -- (the tablets, the fetish, the idol: Kin'weelay's and Loremaster Dibbs's)
		  95789, 95791, 95776 } },                     -- (the Saltseers and Var'Taka: Booty Bay's and Grom'gol's; unplaced mobs, taken as inside)
	{ "Krol'dok Stronghold", 2548, 37.5, 37.5, 17780,   -- Riverglades: the cave west of the fortress gates
		{ 94969, 94973, 94980, 94968, 94982, 94972, 94984, 94975, 94983 } },
	{ "Alcaz Island Prison", 1445, 75.5, 13.7, nil,  -- Dustwallow Marsh (QuestieDB knows no area for the prison)
		{ 95262, 95263, 96381, 96335, 96337, 96377,    -- (Sully McCleary's, Alliance)
		  95309, 95454, 96369, 96332, 96334, 96376,    -- (Sergeant Ulka's, Horde)
		  96379 } },                                   -- (Booty Bay's, both)
	{ "The Shaper's Terrace", 1449, 48.1, 6.1, 16985 },   -- Un'Goro Crater
	{ "Manor Mistmantle", 1431, 74.4, 33.7, 17191 },      -- Duskwood: the manor's own area (no entrance recorded; no quests in the data yet)
	{ "Blackmaw Hold", 1447, 39.6, 32.7, 1216,            -- Azshara: the middle of the hold's own area (no entrance recorded)
		{ 92069, 97173, 97198, 97327, 96246, 92065, 92066 } },
}

local places, placeList            -- lower-case name -> place; and each place once
local placesPartial                -- built before Questie's dungeons could be read: again, once they can

-- A place: { id = uiMapID, name, kind = "continent" | "zone" | "city" | "dungeon" | "town" }. One that's
-- a spot (or a few) inside a zone, rather than a map of its own, has points = { { ui, x, y }, ... }
-- (x, y 0..1): a town, a dungeon's entrances. Those are marked, and the map goes to the nearest
local function BuildPlaces()
	places, placeList = {}, {}
	local function Put(l, p)
		if p.kind == "dungeon" and NOT_IN_FOREVER[l] then return end
		places[l] = p
		placeList[#placeList + 1] = p
		-- ("stormwind" is Stormwind City, "deadmines" The Deadmines; and run together, as it's often
		-- typed: "diremaul", "zulfarrak", "thunderbluff")
		local base = l:match("^the (.+)$") or l
		for _, short in ipairs({ l:match("^(.-) city$") or "", l:match("^the (.+)$") or "",
			(base:gsub("[%s'%-:]", "")) }) do
			if short ~= "" and #short >= 3 and short ~= l and not places[short] then places[short] = p end
		end
	end
	local function AddMap(info, dungeons)
		if not (info and info.name and info.name ~= "" and info.mapID) then return end
		local t, l = info.mapType, lower(info.name)
		local kind = (t == 2 and "continent") or (t == 3 and (CITIES[l] and "city" or "zone")) or (t == 4 and "dungeon")
		if not kind or places[l] or (kind == "dungeon") ~= (dungeons or false) then return end
		Put(l, { id = info.mapID, name = info.name, kind = kind })
	end
	if not C_Map then return end
	local maps = {}
	local ok, kids = pcall(C_Map.GetMapChildrenInfo, AZEROTH, nil, true)
	if ok and type(kids) == "table" and #kids > 0 then
		maps = kids
		table.sort(maps, function(a, b)
			if (a.mapType or 9) ~= (b.mapType or 9) then return (a.mapType or 9) < (b.mapType or 9) end
			return (a.mapID or 0) < (b.mapID or 0)
		end)
	else
		for id = 1, 2000 do
			local info = C_Map.GetMapInfo(id)
			if info then maps[#maps + 1] = info end
		end
	end
	for _, info in ipairs(maps) do AddMap(info) end

	-- the dungeons (and raids, battlegrounds), from Questie: their entrances, on their zones' maps.
	-- (A dungeon named as its zone ("Blackrock Mountain") is the zone)
	ZoneDB = ZoneDB or Questie("ZoneDB")
	local list
	if ZoneDB and ZoneDB.GetDungeons then
		local ok, got = pcall(ZoneDB.GetDungeons, ZoneDB)
		if ok then list = got end
	end
	if type(list) ~= "table" then list = ZoneDB and ZoneDB.private and ZoneDB.private.dungeons end
	-- (no Questie: QuestieDB's own list, the one Questie's is)
	local zd = Search.ZoneData()
	if type(list) ~= "table" and zd then list = zd.dungeons end
	-- (built again later only while neither is there yet: without the list is as good as it
	-- gets, and building on every search would be slow)
	placesPartial = not ZoneDB and type(list) ~= "table"
	if type(list) == "table" then
		-- (keyed by the dungeon's area, which its quests are filed under: some under another of
		-- its areas, listed with it. A dungeon listed again under another area (a wing, a later
		-- version): the first, by area, is the place, and the others' areas are its too)
		local areas = {}
		for area in pairs(list) do areas[#areas + 1] = area end
		table.sort(areas, function(a, b)
			if type(a) == type(b) then return a < b end
			return type(a) == "number"
		end)
		for _, area in ipairs(areas) do
			local d = list[area]
			local name = type(d) == "table" and d[1]
			local l = type(name) == "string" and lower(name)
			local had = l and places[l]
			if had and had.kind == "dungeon" and had.area and type(area) == "number" and area ~= had.area then
				had.alts = had.alts and { unpack(had.alts) } or {}
				had.alts[#had.alts + 1] = area
				for _, a in ipairs(type(d[2]) == "table" and d[2] or {}) do had.alts[#had.alts + 1] = a end
			end
			if l and not places[l] and type(d[4]) == "table" then
				local pts = {}
				for _, at in ipairs(d[4]) do
					local ui = type(at) == "table" and at[1] and ns.UiMapFor(at[1])
					if ui and at[2] and at[3] then pts[#pts + 1] = { ui = ui, x = at[2] / 100, y = at[3] / 100 } end
				end
				if #pts > 0 then
					Put(l, { id = pts[1].ui, name = name, kind = "dungeon", points = pts,
						area = type(area) == "number" and area or nil, alts = type(d[2]) == "table" and d[2] or nil })
				end
			end
		end
	end
	-- a dungeon's entrance, added (or, for one already known, another of its entrances, if it's
	-- somewhere new)
	local function AddEntrance(name, ui, x, y, area, quests)
		if not (name and name ~= "" and ui and x and y) then return end
		local l = lower(name)
		local p = places[l]
		if p and p.kind == "dungeon" and p.points then
			local known = false
			for _, at in ipairs(p.points) do
				if at.ui == ui and math.abs(at.x - x) < 0.02 and math.abs(at.y - y) < 0.02 then known = true break end
			end
			if not known then p.points[#p.points + 1] = { ui = ui, x = x, y = y } end
		elseif not p then
			p = { id = ui, name = name, kind = "dungeon", points = { { ui = ui, x = x, y = y } } }
			Put(l, p)
		end
		-- (its quests: the area they're filed under, or the ids kept by hand)
		if p and p.kind == "dungeon" then
			p.area = p.area or area
			p.quests = p.quests or quests
		end
	end
	-- WoW Forever's own dungeons, which Questie's list hasn't (yet): where their entrances are
	for _, d in ipairs(FOREVER_DUNGEONS) do AddEntrance(d[1], d[2], d[3] / 100, d[4] / 100, d[5], d[6]) end
	-- and the game's own list of entrances, zone by zone, where the client has one: any dungeon
	-- neither knows, new ones included as Forever adds them
	if C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap then
		for _, info in ipairs(maps) do
			if info.mapType == 3 then
				local ok, list = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, info.mapID)
				if ok and type(list) == "table" then
					for _, e in ipairs(list) do
						local pos = e.position
						local x, y
						if pos then
							if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
						end
						AddEntrance(e.name, info.mapID, x, y)
					end
				end
			end
		end
	end
	-- (the game's own dungeon maps, for any Questie hasn't: the map goes to the dungeon's map)
	for _, info in ipairs(maps) do AddMap(info, true) end

	-- the towns and other named areas inside zones (Towns.lua). A map or dungeon of the same name is
	-- the place ("Thunder Bluff" the city, not its piece of Mulgore's map)
	for name, ui, x, y in (ns.TOWNS or ""):gmatch("([^\n|]+)|(%d+)|(%d+)|(%d+)") do
		local l = lower(name)
		if not places[l] then
			ui = tonumber(ui)
			Put(l, { id = ui, name = name, kind = "town",
				points = { { ui = ui, x = tonumber(x) / 1000, y = tonumber(y) / 1000 } } })
		end
	end
	-- the towns with a flight master and no piece of map art of their own ("Splintertree Post"):
	-- by the game's own flight points, "Splintertree Post, Ashenvale", where the flight master is
	if ns.Route and ns.Route.FlightNodes then
		local ok, nodes = pcall(ns.Route.FlightNodes)
		for _, n in ipairs(ok and type(nodes) == "table" and nodes or {}) do
			local name = type(n.name) == "string" and strtrim(n.name:match("^([^,]+)") or "")
			local l = name and lower(name)
			if l and #l >= 3 and not places[l] and n.ui and n.x and n.y then
				Put(l, { id = n.ui, name = name, kind = "town", points = { { ui = n.ui, x = n.x, y = n.y } } })
			end
		end
	end
	-- the short names players use ("sm" is Scarlet Monastery, "org" Orgrimmar)
	for name, shorts in pairs(PLACE_SHORT) do
		local p = places[name]
		if p then
			for short in shorts:gmatch("[^,]+") do
				if not places[short] then places[short] = p end
			end
		end
	end
end

local function Places()
	if not places or (placesPartial and (Questie("ZoneDB") or Search.ZoneData())) then BuildPlaces() end
end

--- the place a search names (as above), or nil
function Search.Place(query)
	Places()
	local q = lower(strtrim(query or ""))
	-- ("the" or not: "the lower wilds" is Lower Wilds; "deadmines" The Deadmines, as built; and
	-- split where the name isn't: "org rimmar", "thunder bluff" alike; run together is built in)
	local p = places[q] or places[q:match("^the (.+)$") or ""]
	if p or not q:find(" ", 1, true) then return p end
	local sq = (q:match("^the (.+)$") or q):gsub("[%s'%-:]", "")
	p = #sq >= 4 and places[sq] or nil
	if p then return p end
	-- ("blackmaw entrance", "deadmines instance": a dungeon, named whole or in part)
	local base = q:match("^(.-)%s+entrances?$") or q:match("^(.-)%s+instance$") or q:match("^(.-)%s+dungeon$")
	if base and #base >= 3 then
		local d = Search.Place(base) or Search.PlaceStarting(base)
		if d and d.kind == "dungeon" then return d end
	end
end

--- every place, once each
function Search.Places()
	Places()
	return placeList
end

--- the one place whose name starts with what's typed, or a word of it does ("elwynn"); nil
--- when none or several do
--- a place named at the start or end of a search ("herb trainer org", "org herb trainer",
--- "herb trainer in the crossroads"): what's left to search for, and the place; nil when none is.
--- Longest names first ("stormwind city" before "city"); not dungeons (an entrance isn't
--- somewhere to look for vendors)
--- "boat to ratchet", "zeppelin to orgrimmar": the kind of transport, the place it's to go to, and
--- the word typed for it; nil when it isn't one
local function TransportTo(query)
	local first, rest = query:match("^(%S+) to (.+)$")
	local which = first and TRANSPORTS[first]
	if not which then return end
	-- (or a place named in part, "menethil", "gromgol")
	local p = Search.Place(rest) or Search.PlaceStarting(rest)
	if p then return which, p, first end
end
Search.TransportTo = TransportTo

function Search.SplitPlace(query)
	query = lower(strtrim(query or "")):gsub("[%?%!%.%s]+$", "")
	if TransportTo(query) then return end
	local words = {}
	for w in query:gmatch("%S+") do words[#words + 1] = w end
	local n = #words
	for k = n - 1, 1, -1 do
		local p = Search.Place(table.concat(words, " ", n - k + 1, n))
		if p and p.kind ~= "dungeon" then
			local last = n - k
			if last > 1 and (words[last] == "in" or words[last] == "at" or words[last] == "near") then last = last - 1 end
			return table.concat(words, " ", 1, last), p
		end
		p = Search.Place(table.concat(words, " ", 1, k))
		if p and p.kind ~= "dungeon" then return table.concat(words, " ", k + 1, n), p end
	end
end

function Search.PlaceStarting(query)
	local q = lower(strtrim(query or ""))
	q = q:match("^the (.+)$") or q
	if #q < 3 then return end
	local found
	for _, p in ipairs(Search.Places()) do
		local l = lower(p.name)
		-- (or run together, apostrophes gone: "gromgol" starts Grom'gol Base Camp)
		if l:sub(1, #q) == q or find(l, " " .. q, 1, true) or l:gsub("[%s'%-:]", ""):sub(1, #q) == q then
			if found then return end
			found = p
		end
	end
	return found
end

--- within: a uiMapID to search inside only (a place named in the search: "herb trainer org")
--------------------------------------------------------------------------------
-- Keywords split or run together, put right before anything else reads the search:
-- "firstaid trainer", "black smithing trainer", "mail box", "meetingstone", "camp fire"
--------------------------------------------------------------------------------

local keywordSq   -- a keyword run together -> the keyword as the tables have it
-- (the keywords of more than one word: these win over a one-word form, "first aid" over "firstaid")
local PHRASES = { "first aid", "quest giver", "quest givers", "meeting stone",
	"meeting stones", "summoning stone", "summoning stones", "cooking fire", "cooking fires",
	"weapon master", "weapon masters", "fist weapon", "fist weapons" }
local function Keywords()
	if keywordSq then return keywordSq end
	keywordSq = {}
	local function Put(k, force)
		local sq = ns.Squash(k)
		if sq ~= "" and (force or not keywordSq[sq]) then keywordSq[sq] = k end
	end
	for _, t in ipairs({ SERVICES, PROFESSIONS, OBJECTS, BOOK_WORDS, BOOK_PROFS, QUESTS, TITLES, WEAPON_WORDS,
		TRAIN_WORDS }) do
		for k in pairs(t) do Put(k) end
	end
	for _, k in ipairs(PHRASES) do Put(k, true) end
	return keywordSq
end

-- other ways of saying a keyword
local SYNONYMS = {
	{ "auction house", "auction" }, { "auctionhouse", "auction" }, { "auction hall", "auction" },
	{ "flight path", "flight" }, { "flight paths", "flight" }, { "flightpath", "flight" }, { "flight point", "flight" },
	{ "flight points", "flight" }, { "taxi", "flight" }, { "gryphon", "flight" }, { "wind rider", "flight" },
	{ "hearthstone", "innkeeper" }, { "set hearth", "innkeeper" }, { "hearth", "innkeeper" }, { "bind", "innkeeper" },
	{ "innkeeper", "innkeeper" }, { "post box", "mailbox" }, { "postbox", "mailbox" }, { "post office", "mailbox" },
	{ "mail box", "mailbox" }, { "mail boxes", "mailbox" }, { "mail", "mailbox" }, { "bank vault", "bank" }, { "vault", "bank" },
	{ "fishing rod", "fishing pole" }, { "fishing rods", "fishing pole" },
	{ "class trainer", "trainer" }, { "profession trainer", "trainer" }, { "battlegrounds", "battlemaster" },
	{ "battleground", "battlemaster" }, { "soul shard bag", "soul bag" }, { "shard bag", "soul bag" }, { "mage portal", "portal trainer" },
}
table.sort(SYNONYMS, function(a, b) return #a[1] > #b[1] end)

--- the search with its keywords whole: two or three words that run together into one, joined
--- ("mail box" -> "mailbox"); one that's a keyword of several words run together, split
--- ("firstaid" -> "first aid"); and other ways of saying one ("auction house": auction)
function Canon(query)
	local padded = " " .. query .. " "
	for _, syn in ipairs(SYNONYMS) do
		local a, b = " " .. syn[1] .. " ", " " .. syn[2] .. " "
		if find(padded, a, 1, true) then padded = padded:gsub(a:gsub("%p", "%%%0"), b) end
	end
	query = strtrim(padded)
	local K = Keywords()
	local w = {}
	for x in query:gmatch("%S+") do w[#w + 1] = x end
	local out, i = {}, 1
	while i <= #w do
		local took = false
		for n = 3, 2, -1 do
			if i + n - 1 <= #w then
				local k = K[table.concat(w, "", i, i + n - 1)]
				if k then
					out[#out + 1] = k
					i, took = i + n, true
					break
				end
			end
		end
		if not took then
			out[#out + 1] = K[w[i]] or w[i]
			i = i + 1
		end
	end
	return table.concat(out, " ")
end
Search.Canon = function(q) return Canon(q) end

--------------------------------------------------------------------------------
-- Dungeons: "dungeon" (or "dungeons", "instances") puts a marker on every dungeon's entrance,
-- with its levels; "dungeons for my level" only the ones for you; "raids" the raids. In a
-- zone too ("dungeon in westfall"). The ones open in WoW Forever: the classic dungeons, and
-- Forever's own (their levels not known here)
--------------------------------------------------------------------------------

local DUNGEON_LEVELS = {
	["ragefire chasm"] = { 13, 18 }, ["wailing caverns"] = { 17, 24 }, ["the deadmines"] = { 17, 26 },
	["shadowfang keep"] = { 22, 30 }, ["blackfathom deeps"] = { 24, 32 }, ["the stockade"] = { 24, 32 },
	["gnomeregan"] = { 29, 38 }, ["razorfen kraul"] = { 29, 38 }, ["scarlet monastery"] = { 30, 45 },
	["razorfen downs"] = { 37, 46 }, ["uldaman"] = { 41, 51 }, ["zul'farrak"] = { 44, 54 },
	["maraudon"] = { 46, 55 }, ["the temple of atal'hakkar"] = { 50, 60 }, ["blackrock depths"] = { 52, 60 },
	["blackrock spire"] = { 55, 60 }, ["upper blackrock spire"] = { 58, 60 }, ["dire maul"] = { 55, 60 },
	["scholomance"] = { 58, 60 }, ["stratholme"] = { 58, 60 },
	-- (WoW Forever's own)
	["ruins of lordaeron"] = true, ["city of dalaran"] = true, ["excavation site: wetlands"] = true,
	["the hall of thanes"] = true, ["the drowned city"] = true, ["krol'dok stronghold"] = true,
	["alcaz island prison"] = true, ["the shaper's terrace"] = true, ["manor mistmantle"] = true,
}
local RAID_LEVELS = {
	["molten core"] = { 60, 60 }, ["onyxia's lair"] = { 60, 60 }, ["blackwing lair"] = { 60, 60 },
	["zul'gurub"] = { 60, 60 }, ["ruins of ahn'qiraj"] = { 60, 60 }, ["temple of ahn'qiraj"] = { 60, 60 },
	["naxxramas"] = { 60, 60 },
}
local DUNGEON_WORDS = { dungeon = "dungeon", dungeons = "dungeon", instance = "dungeon", instances = "dungeon",
	raids = "raid" }
local DUNGEON_FILLER = { ["for"] = true, the = true, a = true, all = true, near = true, nearby = true,
	entrance = true, entrances = true, ["5"] = true, man = true, ["5man"] = true, ["5-man"] = true }
local DUNGEON_MINE = { my = true, me = true, level = true, mine = true }   -- ("for my level": yours only)
local FITS = 2      -- levels below or above a dungeon's that still count as yours

--- a dungeon search: "dungeon" or "raid", and whether only the ones for your level; or nil
local function DungeonQuery(query)
	local which, mine, raidWord = nil, false, false
	for w in query:gmatch("%S+") do
		if DUNGEON_WORDS[w] then
			which = which or DUNGEON_WORDS[w]
		elseif w == "raid" then
			raidWord = true   -- ("raid instance", "raid entrance"; "raid" alone is your group)
		elseif DUNGEON_MINE[w] then
			mine = true
		elseif not DUNGEON_FILLER[w] then
			return
		end
	end
	if raidWord then
		if which == "dungeon" or query:find("entrance", 1, true) then which = "raid" else return end
	end
	if not which then return end
	return which, mine
end
Search.DungeonQuery = DungeonQuery

-- the entrances of the dungeons (or raids) asked for
local function Dungeons(ctx, which, mine)
	local table_ = which == "raid" and RAID_LEVELS or DUNGEON_LEVELS
	local level = UnitLevel("player") or 1
	for i, p in ipairs(Search.Places()) do
		local lv = p.kind == "dungeon" and p.points and table_[lower(p.name)]
		if lv then
			local lo, hi = type(lv) == "table" and lv[1], type(lv) == "table" and lv[2]
			local fits = lo and level >= lo - FITS and level <= hi + FITS
			if not mine or fits then
				local pts = {}
				for _, at in ipairs(p.points) do
					if not ctx.zoneOk or ctx.zoneOk(at.ui) then pts[#pts + 1] = { ui = at.ui, x = at.x * 100, y = at.y * 100 } end
				end
				if #pts > 0 then
					local label = which == "raid" and L["Raid entrance"] or L["Dungeon entrance"]
					if lo then label = (lo == hi and L["%s, level %d"]:format(label, lo) or L["%s, level %d-%d"]:format(label, lo, hi)) end
					local r = Add(ctx, { obj = true, id = -(6000000 + i), name = p.name }, pts, { kind = "DUNGEON", label = label })
					r.rank = fits and 0 or 1
				end
			end
		end
	end
end

local FILLER = { "where is the", "where is a", "where is an", "where is", "where are the", "where are", "wheres the", "wheres",
	"where can i find the", "where can i find a", "where can i find", "where can i buy", "where do i buy", "where to buy",
	"where to find", "how do i get to the", "how do i get to", "how to get to", "find me the", "find me a", "find me", "find the",
	"find a", "find", "the nearest", "the closest", "nearest", "closest", "show me the", "show me", "take me to the",
	"take me to", "go to the", "go to", "goto", "the", "a", "an", "my",
	-- (questions: "is there a herb trainer in org", "who sells linen cloth", "what drops silk cloth")
	"is there a", "is there an", "is there any", "is there", "are there any", "are there", "do you know where", "do you know",
	"can i find a", "can i find", "can i buy a", "can i buy", "can i get a", "can i get", "where can i get", "where can i",
	"where do i find", "where do i get", "where do i", "where does", "where do", "how do i find", "how do i",
	"how can i", "who sells", "who has", "what drops", "what sells", "which npc sells", "which",
	"what", "who", "any", "some", "i need a", "i need", "i want a", "i want", "im looking for a", "im looking for",
	"looking for a", "looking for", "please", "pls", "plz", "can i", "where", "is", "does", "do", "i" }
table.sort(FILLER, function(a, b) return #a > #b end)
-- (... and at the end: "where does linen cloth drop", "mailbox near me", "herb trainer please")
local TRAIL = { "near me", "nearby", "around here", "please", "pls", "plz", "drop", "drops", "dropped", "drop from",
	"sold", "for sale", "located", "at", "from", "to" }
table.sort(TRAIL, function(a, b) return #a > #b end)
-- ("learn fishing", "teaches polearm": its trainer)
local LEARN = { "learn", "learning", "teaches", "teach", "train", "trains" }

-- the search without its filler words at either end ("where is the inn": inn; "where does linen
-- cloth drop": linen cloth), a question's "?" gone, "learn fishing" as "fishing trainer"; or nil
-- when it has none of those
local function StripFiller(q)
	local out, changed = q, false
	if out:find("[%?%!%.]+$") then out, changed = out:gsub("[%?%!%.%s]+$", ""), true end
	for _ = 1, 4 do
		local hit = false
		for _, f in ipairs(FILLER) do
			if out:sub(1, #f + 1) == f .. " " then out, hit, changed = out:sub(#f + 2), true, true break end
		end
		if not hit then break end
	end
	for _ = 1, 2 do
		local hit = false
		for _, t in ipairs(TRAIL) do
			if #out > #t + 1 and out:sub(-(#t + 1)) == " " .. t then out, hit, changed = out:sub(1, -(#t + 2)), true, true break end
		end
		if not hit then break end
	end
	for _, l in ipairs(LEARN) do
		if out:sub(1, #l + 1) == l .. " " and not out:find(" trainer", 1, true) then
			out, changed = out:sub(#l + 2) .. " trainer", true
			break
		end
	end
	return changed and out or nil
end

Search.StripFiller = function(q) return StripFiller(lower(strtrim(q or ""))) end

local RunOnce

-- the NPCs of the other faction, by name run together ("marshalmcbride"): the one a search names,
-- or nil. (Gathered once: not a walk of every NPC each time a search finds nothing)
local otherNames
local function OtherFaction(query)
	if not otherNames then
		otherNames = {}
		for _, e in ipairs(ns.Index.entries) do
			if e.fac and not FactionOk(e.fac) then otherNames[ns.Squash((lower(e.name):gsub("'", "")))] = e end
		end
	end
	return otherNames[ns.Squash(query)]
end

--- the search: as typed; when that finds nothing, without its filler ("where is the inn")
--------------------------------------------------------------------------------
-- Learning to make something: "where to learn heavy mageweave bandages", "learn heavy silk
-- bandage", "recipe for elixir of fortitude". Its recipe, when there's one (a manual, pattern,
-- plans...: who sells it, what drops it, the quest that gives it), as its own search. A first aid
-- bandage that has none: the trainers who teach it, and the skill it asks
--------------------------------------------------------------------------------
do
local LEARN_ASK = { "where to learn how to make ", "where do i learn how to make ", "where can i learn how to make ",
	"where to learn to make ", "where do i learn to make ", "where can i learn to make ", "how do i learn to make ",
	"how to learn to make ", "where do i learn ", "where can i learn ", "where to learn ", "how do i learn ",
	"how to learn ", "learn how to make ", "learn to make ", "recipe for ", "learn ",
	"where do i train ", "where can i train ", "where to train ", "how do i train ", "how to train ", "train " }
local LEARN_TAIL = { " training", " trainer", " trainers", " train", " recipe", " learn", " learning" }
local RECIPE = { "manual", "recipe", "pattern", "plans", "schematic", "formula", "design", "technique", "book",
	"tome", "codex", "guide", "handbook" }
-- (first aid's bandages no manual teaches: the skill each asks; true: of the Trauma Surgeon, once
-- you're an Artisan)
local BANDAGE = { ["linen bandage"] = { 1 }, ["heavy linen bandage"] = { 40 }, ["wool bandage"] = { 80 },
	["heavy wool bandage"] = { 115 }, ["anti-venom"] = { 80 }, ["silk bandage"] = { 150 },
	["heavy mageweave bandage"] = { 240, true }, ["runecloth bandage"] = { 260, true },
	["heavy runecloth bandage"] = { 290, true } }

local function Has(l)
	if ns.Index.UnsoldIds and #ns.Index.UnsoldIds(l) > 0 then return true end
	for _, it in ipairs(ns.Index.items or {}) do if it.lname == l then return true end end
	return false
end

--- what a search asks to learn to make: its recipe's name (a search of its own), or nil; and the
--- thing itself (nil: it's not such a search)
function Search.LearnQuery(query)
	local q = lower(strtrim(query or ""))
	local thing
	for _, a in ipairs(LEARN_ASK) do
		if q:sub(1, #a) == a then thing = strtrim(q:sub(#a + 1)) break end
	end
	-- ("heavy mageweave bandage training", "heavy silk bandage recipe": asked at the end)
	if not thing then
		for _, a in ipairs(LEARN_TAIL) do
			if #q > #a and q:sub(-#a) == a then thing = strtrim(q:sub(1, -#a - 1)) break end
		end
	end
	if not thing or #thing < 3 or not ns.Index or not ns.Index.done then return end
	local tries = { thing }
	if thing:sub(-1) == "s" then tries[2] = thing:sub(1, -2) end
	-- ("train heavy mageweave first aid", "learn heavy mageweave": the bandage)
	local aid = thing:gsub("%f[%a]first aid%f[%A]", ""):gsub("%f[%a]firstaid%f[%A]", ""):gsub("%s+", " ")
	aid = strtrim(aid)
	if #aid >= 3 and not aid:find("bandage") then
		tries[#tries + 1] = aid .. " bandage"
	elseif aid ~= thing and #aid >= 3 then
		tries[#tries + 1] = aid
		if aid:sub(-1) == "s" then tries[#tries + 1] = aid:sub(1, -2) end
	end
	for _, t in ipairs(tries) do
		for _, pre in ipairs(RECIPE) do
			local l = pre .. ": " .. t
			if Has(l) or Has((l:gsub("'", ""))) then return l, t end
		end
	end
	for _, t in ipairs(tries) do if BANDAGE[t] then return nil, t, BANDAGE[t] end end
	return nil, tries[1]
end
end

function Search.Run(query, everywhere, within)
	query = (query or ""):gsub("[%?%!%.%s]+$", "")
	-- ("where to learn heavy mageweave bandages": its recipe, or who teaches it)
	local recipe, learnt, bandage = Search.LearnQuery(query)
	if recipe then
		local r0, m0, s0, e0, w0 = RunOnce(recipe, everywhere, within)
		if r0 then return r0, m0, s0, e0, w0 end
	elseif bandage then
		local r0, m0, s0, e0, w0 = RunOnce(bandage[2] and "trauma surgeon" or "first aid trainer", everywhere, within)
		if r0 then
			local name = learnt:gsub("(%a)([%w'-]*)", function(a, b) return a:upper() .. b end)
			r0.questNow = (bandage[2] and L["%s: taught by the Trauma Surgeon at First Aid %d, once you're an Artisan."]
				or L["%s: taught by first aid trainers, at First Aid %d."]):format(name, bandage[1])
			return r0, m0, s0, e0, w0
		end
	end
	local r, m, s, e, w = RunOnce(query, everywhere, within)
	if r then return r, m, s, e, w end
	local stripped = StripFiller(lower(strtrim(query or "")))
	if stripped and #stripped >= 2 then
		local r2, m2, s2, e2, w2 = RunOnce(stripped, everywhere, within)
		-- (found: a word or two left of two letters only as a keyword, "ah", not "am i" of "where am
		-- i" matching half the world; or at least said something of it: "Marshal McBride is Alliance")
		local short = stripped:find("^%S%S?$") or stripped:find("^%S%S? ") or stripped:find(" %S%S? ") or stripped:find(" %S%S?$")
		if r2 and (s2 or not short) then return r2, m2, s2, e2, w2 end
		if not r2 and e and m2 then return r2, m2, s2, e2, w2 end
	end
	-- (a farm of what isn't a vein or herb: "linen cloth farm", "large fang farming". The thing
	-- itself: where it drops, its mobs' areas, with its own icon)
	local thing = ns.Farm and ns.Farm.Parse and ns.Farm.Parse(query)
	if thing and thing ~= lower(strtrim(query)) and #thing >= 2 then
		local r3, m3, s3, e3, w3 = RunOnce(thing, everywhere, within)
		if r3 then return r3, m3, s3, e3, w3 end
	end
	return r, m, s, e, w
end

RunOnce = function(query, everywhere, within)
	query = lower(strtrim(query or ""))
	if #query < 2 then return nil, L["Type at least 2 letters."] end
	-- (a step of a quest line, picked in the drop-down: "quest #422")
	local stepId = tonumber(query:match("^quests? #(%d+)$"))
	-- (your group, or one of them by name: where they are now. Not Questie's data, so not waiting
	-- on it; and nowhere but where they are, so no zone to keep to)
	local group, why = Search.Group(query)
	if group or why then return group, why, nil, false end
	-- (coordinates: a spot on a zone's map. Not Questie's data either)
	local spot, whyNot = Search.Coords(query, within)
	if spot or whyNot then return spot, whyNot, nil, false end
	if not ns.Index.done then
		return nil, L["Still reading Questie's data (%d%%)..."]:format(ns.Index.progress * 100)
	end
	query = query:gsub("'", "")
	if #query < 2 then return nil, L["Type at least 2 letters."] end

	query = Canon(query)
	local tokens = Tokens(query)
	local qsq = ns.Squash(query)
	local ctx = {
		query = query, tokens = tokens, results = {}, byId = {},
		-- (the search run together, for names typed so or split: long enough not to match everything)
		qsq = #qsq >= 5 and qsq or nil,
		NpcDB = ns.Index.DB(), priority = ns.PriorityMaps(),
		hunter = select(2, UnitClass("player")) == "HUNTER",
		class = select(2, UnitClass("player")),
		services = {}, generic = true,
	}
	for _, t in ipairs(tokens) do
		if t.service then ctx.services[t.service] = true else ctx.generic = false end
	end
	ctx.profs, ctx.profsFull = Professions()
	local shown = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
	if ns.db.zoneOnly and shown and not everywhere then ctx.zoneOk = InsideOf(shown) end
	if within then ctx.zoneOk = InsideOf(within) end

	local bookSub = BookQuery(query)
	local bagKinds = BagQuery(query)
	local hereOpts = QuestDB() and Extra.QuestsHereQuery(query)
	local questQuery = not QUESTS[query] and not hereOpts and query:match("^quests? (.+)$")
	local specialty = SpecialtyQuery(query)
	local cqMode, cqClass, cqWords = ClassQuestQuery(query)
	local cqList = cqMode == "topic" and not hereOpts and QuestDB() and ClassTopic(cqWords, cqClass)
	if cqMode == "topic" and not (cqList and #cqList > 0) then cqMode = nil end
	if hereOpts then cqMode = nil end   -- ("quests here": not a class's quests about "here")
	local repFaction = RepQuery(query)
	local repFarms = QuestDB() and Extra.RepFarmsQuery(query)
	local rares = RareQuery(query)
	local rankProf, rankN = RankQuery(query)
	local weapons = WeaponQuery(query)
	local turnQuery = TurnInQuery(query)
	local dqPlace = QuestDB() and Extra.DungeonQuestQuery(query)
	local attune = QuestDB() and Extra.AttuneQuery(query)
	local supplies = Extra.SupplyQuery(query)
	local dungeonKind, dungeonMine = DungeonQuery(query)
	local trainProf, trainN = Search.TrainPastQuery(query)
	local riding = Search.RidingQuery(query)
	if stepId then
		if not QuestDB() then return nil, L["QuestieDB's quest data isn't available."] end
		local name = Extra.QuestStep(ctx, stepId)
		if #ctx.results == 0 and not ctx.zoneOk then
			if ctx.otherSide then return nil, L["\"%s\" is a quest for the other faction."]:format(ctx.otherSide) end
			return nil, L["No one on the map starts \"%s\"."]:format(name or "?")
		end
	elseif riding then
		-- ("where to train riding", "mount training": the riding trainers)
		Search.RidingTrainers(ctx)
		ctx.service = "TRAINER"
		if #ctx.results == 0 and not ctx.zoneOk then return nil, L["No riding trainer of your faction is on the map."] end
	elseif trainProf then
		-- ("how do i train past 225 first aid": the book, quest or trainers that take it further)
		local say, why = Search.TrainPast(ctx, trainProf, trainN)
		if not say then return nil, why end
		if #ctx.results == 0 and not ctx.zoneOk then return nil, say end
		ctx.questNow = say
	elseif dungeonKind then
		Dungeons(ctx, dungeonKind, dungeonMine)
		ctx.service = "DUNGEON"   -- (a list of places, not a name: not taken for a place's)
		if #ctx.results == 0 and not ctx.zoneOk then
			return nil, dungeonMine and L["No dungeons for your level (%d)."]:format(UnitLevel("player") or 1)
				or L["Nothing found for \"%s\"."]:format(query)
		end
	elseif turnQuery then
		-- ("turn in the lost pilot": who it's handed in to)
		if not QuestDB() then return nil, L["QuestieDB's quest data isn't available."] end
		ctx.query = turnQuery
		local exact, partial = QuestMatches(turnQuery)
		local list = #exact > 0 and exact or partial
		if #list == 0 then return nil, L["No quest is called \"%s\"."]:format(turnQuery) end
		if #list > QUEST_MAX then
			return nil, L["Over %d quests have \"%s\" in their names: say more of the name."]:format(QUEST_MAX, turnQuery)
		end
		QuestEnders(ctx, list, #exact > 0 and 0 or 1)
		if #ctx.results == 0 and not ctx.zoneOk then
			if ctx.otherSide then return nil, L["\"%s\" is a quest for the other faction."]:format(ctx.otherSide) end
			return nil, L["No one on the map takes \"%s\" in."]:format(list[1][2])
		end
	elseif dqPlace then
		-- ("deadmines quests": who starts the quests for it you could still take)
		local why = Extra.DungeonQuests(ctx, dqPlace)
		if #ctx.results == 0 and not ctx.zoneOk then
			-- (none: why. Its quests all the other faction's ("deadmines quests", as Horde), all
			-- done, or none at all)
			if why.all == 0 then return nil, L["No quests are filed under %s."]:format(dqPlace.name) end
			if why.faction == why.all then
				local side = ns.faction == "Horde" and (_G.FACTION_ALLIANCE or "Alliance") or (_G.FACTION_HORDE or "Horde")
				return nil, L["Every quest for %s is for the %s."]:format(dqPlace.name, side)
			end
			if why.done > 0 and why.done + why.faction + why.class == why.all then
				return nil, L["You've done every quest for %s that you can take."]:format(dqPlace.name)
			end
			return nil, L["No quests for %s that you could still take."]:format(dqPlace.name)
		end
	elseif attune then
		-- ("mc attunement": where its line starts, or goes on)
		local done, first = Extra.Attunements(ctx, attune)
		if #ctx.results == 0 and not ctx.zoneOk then
			if done > 0 and done == #attune then
				return nil, #attune == 1 and L["You've done it already."] or L["You've done them all already."]
			end
			return nil, L["No one on the map starts \"%s\"."]:format(first or query)
		end
	elseif SPIRIT[query] then
		-- ("graveyard": every spirit healer)
		SpiritHealers(ctx)
	elseif rares then
		-- ("rares": the rare mobs around your level; in a zone, all of its)
		Rares(ctx)
		if #ctx.results == 0 and not ctx.zoneOk then
			return nil, L["No rare mobs around your level (%d)."]:format(UnitLevel("player") or 1)
		end
	elseif cqMode == "class" then
		-- ("class quests", "warlock quests")
		if not QuestDB() then return nil, L["QuestieDB's quest data isn't available."] end
		local mine = select(2, UnitClass("player"))
		local asked = ClassQuestGivers(ctx, cqClass)
		if #ctx.results == 0 and not ctx.zoneOk then
			if asked then return nil, L["No class quests for you to pick up right now."] end
			local cname = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cqClass or mine] or (cqClass or mine)
			return nil, L["No %s quests your faction can take."]:format(cname)
		end
	elseif cqMode == "topic" then
		-- ("voidwalker quest": where its class quest line starts)
		-- (a quest of that name you're on, a class's or not: where to go for it, first)
		local names = QuestMatches(strtrim((query:gsub("^quests? ", ""):gsub(" quests?$", ""))), true)
		for _, q in ipairs(cqList) do
			for _, e in ipairs((QuestMatches(q[2], true))) do names[#names + 1] = e end
		end
		Extra.QuestNow(ctx, names)
		ctx.allDone = nil
		if not ctx.questNow then QuestStarters(ctx, Extra.QuestNow(ctx, cqList), 0) end
		if #ctx.results == 0 and ctx.allDone then return nil, L["You've done \"%s\"."]:format(ctx.allDone) end
		if #ctx.results == 0 and not ctx.zoneOk then
			if ctx.otherSide then return nil, L["\"%s\" is a quest for the other faction."]:format(ctx.otherSide) end
			return nil, L["No one on the map starts \"%s\"."]:format(cqList[1][2])
		end
	elseif repFarms then
		-- ("rep farms": every faction you could hand turn-ins in to now, to pick one)
		local list = Extra.RepFarms(ctx)
		if #list == 0 and not ctx.zoneOk then return nil, L["No reputation turn-ins you can do right now."] end
		ctx.questNow = L["Reputation turn-ins you can do: pick a faction below."]
		ctx.choices = {}
		for _, f in ipairs(list) do
			ctx.choices[#ctx.choices + 1] = { text = lower(f[1]) .. " rep", label = f[1], hint = L["turn-ins: %d"]:format(f[2]) }
		end
	elseif repFaction then
		-- ("argent dawn quartermaster": the faction's vendors; and who takes its turn-ins, with
		-- the things to bring in the drop-down: where they drop, and a loop to farm them)
		RepVendors(ctx, repFaction)
		local facs = QuestDB() and Extra.RepFactions(repFaction) or {}
		local n, items = 0, {}
		if #facs > 0 then n, items = Extra.RepTurnIns(ctx, facs) end
		if #ctx.results == 0 and not ctx.zoneOk then
			return nil, L["No quartermaster found for \"%s\"."]:format(repFaction)
		end
		if n > 0 then
			ctx.questNow = (#items > 0 and L["%s: %d turn-ins. Pick a thing to bring below to see where it drops."]
				or L["%s: %d turn-ins."]):format(Extra.RepName(facs[1]) or repFaction, n)
			ctx.choices = {}
			for _, it in ipairs(items) do
				local name = lower(it[2]):gsub("'", "")
				ctx.choices[#ctx.choices + 1] = { text = name, label = it[2], hint = L["where it drops"], icon = it[3] }
				ctx.choices[#ctx.choices + 1] = { text = name .. " farm", label = L["Farm %s"]:format(it[2]),
					hint = L["a farming loop"], icon = it[3] }
			end
		end
	elseif specialty then
		-- ("goblin engineering", "armorsmith": who teaches it)
		Specialists(ctx, specialty)
		if #ctx.results == 0 and not ctx.zoneOk then
			return nil, L["No one of your faction teaches %s."]:format(specialty.name)
		end
	elseif rankProf then
		-- ("artisan tailoring": the trainers who teach up to it)
		RankedTrainers(ctx, rankProf, rankN)
		if #ctx.results == 0 and not ctx.zoneOk then
			return nil, L["No trainer of your faction teaches %s up to %s."]:format(PROF_NAMES[rankProf], RANK_NAMES[rankN])
		end
	elseif weapons then
		WeaponMasters(ctx, weapons)
		if #ctx.results == 0 and not ctx.zoneOk then
			local what = weapons ~= "all" and Search.WeaponName(weapons[1]) or L["weapon skills"]
			return nil, L["None of your faction's weapon masters teach %s."]:format(what)
		end
	elseif supplies then
		-- ("water", "arrows": the vendors of the best you can use)
		local names = Extra.Supplies(ctx, supplies)
		ctx.service = "VENDOR"
		if #ctx.results == 0 and not ctx.zoneOk then
			return nil, L["No vendor sells \"%s\"."]:format(names[1] or query)
		end
	elseif hereOpts or QUESTS[query] then
		-- ("quests", "quests here", "quests in the barrens": the ones to pick up, for your level)
		local n, more, zone = Extra.QuestsHere(ctx, hereOpts or {}, within or (ctx.zoneOk and shown) or nil)
		if not n then return nil, more end
		local zname = zone and ns.ZoneName(zone) or "?"
		if n == 0 then
			if more then return nil, L["No quests to pick up in %s for your level. Most are in: %s."]:format(zname, more) end
			return nil, L["No quests to pick up in %s for your level."]:format(zname)
		end
		ctx.questNow = (more and not within) and L["%d quests to pick up here. More in: %s."]:format(n, more)
			or L["%d quests to pick up."]:format(n)
	elseif questQuery then
		-- ("quest the lost pilot": quests only, by name)
		if not QuestDB() then return nil, L["QuestieDB's quest data isn't available."] end
		ctx.query = questQuery
		local exact, partial = QuestMatches(questQuery)
		local list = #exact > 0 and exact or partial
		if #list > QUEST_MAX then
			return nil, L["Over %d quests have \"%s\" in their names: say more of the name."]:format(QUEST_MAX, questQuery)
		end
		QuestStarters(ctx, Extra.QuestNow(ctx, list), #exact > 0 and 0 or 1)
		if #ctx.results == 0 and ctx.allDone then
			return nil, L["You've done \"%s\"."]:format(ctx.allDone)
		end
		if #ctx.results == 0 and #list > 0 and not ctx.zoneOk then
			return nil, L["No one on the map starts \"%s\"."]:format(list[1][2])
		end
	elseif bagKinds then
		-- ("herb bag", "reagent bag": bags of that kind, sold or their patterns)
		Bags(ctx, bagKinds)
		if #ctx.results == 0 and not ctx.zoneOk then
			return nil, L["No vendor sells a bag of that kind, or its pattern."]
		end
	elseif bookSub ~= nil then
		Books(ctx, bookSub)
		if #ctx.results == 0 and not ctx.zoneOk then
			return nil, bookSub and L["No vendor sells a %s book."]:format(Search.BOOK_NAMES[bookSub] or L["skill"])
				or L["No vendor sells skill books."]
		end
	elseif TRANSPORTS[query] then
		Transports(ctx, TRANSPORTS[query])
		ctx.service = "TRANSPORT"
		if #ctx.results == 0 and not ctx.zoneOk then return nil, L["None of those your faction can take."] end
	elseif TransportTo(query) then
		local which, place, word = TransportTo(query)
		Transports(ctx, which, place)
		ctx.service = "TRANSPORT"
		if #ctx.results == 0 and not ctx.zoneOk then return nil, L["No %s goes to %s."]:format(word, place.name) end
	elseif OBJECTS[query] then
		Objects(ctx, OBJECTS[query])
	elseif TITLES[query] then
		TitleNpcs(ctx, TITLES[query])
		ctx.service = "VENDOR"   -- (the sellers asked for: not a place that starts the same, "mount")
	else
		Npcs(ctx)
		if ctx.generic and ctx.services.FLIGHT_MASTER and #ctx.results < MAX_MATCHES then FlightPoints(ctx) end
		if #query >= 3 and not ctx.generic and #ctx.results < MAX_MATCHES then Items(ctx) end
		-- (a quest's name: who starts it. Its whole name, always; part of it, when nothing else
		-- was found: "the lost pilot", "lost pilot")
		if not ctx.generic and QuestDB() and #ctx.results < MAX_MATCHES then
			local had = #ctx.results
			local exact, partial = QuestMatches(query, had > 0)
			if #exact > 0 then
				QuestStarters(ctx, Extra.QuestNow(ctx, exact), 0)
				-- (one you're on: where to go for it, not the NPCs that happen to share a word)
				if ctx.questNow and had > 0 then
					local keep = {}
					for i = had + 1, #ctx.results do keep[#keep + 1] = ctx.results[i] end
					ctx.results = keep
				end
			elseif had == 0 and #partial > 0 and #partial <= QUEST_MAX and not LikeAPlace(query) then
				QuestStarters(ctx, Extra.QuestNow(ctx, partial), 1)
			end
			if had == 0 and #ctx.results > 0 then ctx.unsold = nil end
		end
	end

	local results = ctx.results
	table.sort(results, function(a, b)
		if a.near ~= b.near then return a.near end
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.entry.name < b.entry.name
	end)
	if #results == 0 then
		-- (an NPC of the other faction, by name: said so, the setting that'd show them named)
		local e = not ns.db.otherFaction and OtherFaction(query)
		if e then
			local side = e.fac == "A" and (_G.FACTION_ALLIANCE or "Alliance") or (_G.FACTION_HORDE or "Horde")
			return nil, L["%s is %s. Turn on \"Include the other faction's NPCs\" to find them."]:format(e.name, side), nil, false
		end
		if ctx.unsold then return nil, L["No vendor sells \"%s\"."]:format(ctx.unsold) end
		if ctx.otherSide then return nil, L["\"%s\" is a quest for the other faction."]:format(ctx.otherSide) end
		if ctx.allDone then return nil, L["You've done \"%s\"."]:format(ctx.allDone) end
		if within then return nil, L["No \"%s\" in %s."]:format(query, ns.ZoneName(within) or L["that place"]), nil, true end
		if ctx.zoneOk then
			-- (none here, but some elsewhere: say so, so it doesn't read as none at all; and it's
			-- spelled right, so no spelling fix is tried)
			local other = Elsewhere(query)
			if other then
				return nil, L["None in %s. %s (only-this-zone is on)."]:format(
					ns.ZoneName(shown), other), nil, false
			end
			return nil, L["Nothing for \"%s\" in %s."]:format(query, ns.ZoneName(shown)), nil, true
		end
		return nil, L["Nothing found for \"%s\"."]:format(query), nil, true
	end
	results.drops = ctx.drops   -- (an item's area: what the status says)
	results.questNow = ctx.questNow   -- (a quest you're on: what the status says)
	results.choices = ctx.choices     -- (searches to go on to, for the drop-down: { { text, label, hint, icon } })
	-- (a quest in a line: the line, for the drop-down; a step of it picked, the status says which)
	results.chain = ctx.chainSeed and Extra.Chain(ctx.chainSeed, ctx.chainLook) or nil
	local c = results.chain
	if c and c.look and not ctx.questNow then
		results.questNow = L["Step %d of %d: %s"]:format(c.look, #c.steps, c.steps[c.look].name)
	end
	local service = ctx.service
	for _, t in ipairs(tokens) do if not service and t.service then service = t.service break end end
	return results, nil, service
end
