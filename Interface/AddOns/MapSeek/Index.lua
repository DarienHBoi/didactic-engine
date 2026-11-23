--------------------------------------------------------------------------------
-- The search index, read once from QuestieDB after login, a few hundred rows per frame so it
-- never hitches:
--   NPCs:    name, title, service flags and faction (and which class or profession a trainer
--            trains, and whether it's for hunters only)
--   Objects: the useful ones only: mailboxes, forges, anvils, cooking fires, meeting stones
--   Items:   the ones vendors sell: name and vendors (and so, each vendor's wares, by kind);
--            and the names of the rest, to say "no vendor sells that"
-- Spawns are not kept here; they're read only for what a search matches.
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local Index = {
	entries = {},       -- NPCs
	byId = {},          -- npcId -> NPC entry
	objects = {},       -- { obj = true, id, name, kind }
	items = {},         -- { id, name, lname, vendors = { npcId, ... } }
	-- (what each vendor sells: Index.Wares(npcId), worked out when asked rather than kept)
	unsold = "",        -- items no vendor sells: "\n" .. lower-case name .. "\1" .. id, each (Index.Unsold)
	skillBooks = {},    -- books vendors sell that raise a skill's cap: { id, name, sub, from, to }
	gather = {},        -- ore veins and herbs, to farm (Farm.lua): { id, name }
	bags = {},          -- bags of a kind (herb, mining, reagent ...): { id, name, lname, kind (subclass), item? (sold) }
	done = false, running = false, progress = 0,
}
ns.Index = Index

local PER_FRAME = 300
local FIELDS = { "name", "subName", "npcFlags", "friendlyToFaction", "spawns", "rank" }
local find, lower, byte, sub = string.find, string.lower, string.byte, string.sub

function Index.DB()
	return _G.NpcDB or (_G.LibQuestieDB and _G.LibQuestieDB.Npc)
end
function Index.ObjectDB()
	return _G.ObjectDB or (_G.LibQuestieDB and _G.LibQuestieDB.Object)
end
function Index.ItemDB()
	return _G.ItemDB or (_G.LibQuestieDB and _G.LibQuestieDB.Item)
end

--- an entry's spawns ({ [areaId] = { { x, y }, ... } }), or nil. An Object's as stored when the
--- corrected ones are empty: Questie clears the gathering nodes' (Copper Vein, Peacebloom, ...)
--- for its own map, which never shows them, and so for every addon reading QuestieDB
-- (kept as read: QuestieDB makes a fresh copy of a table every time it's asked for one, and a
-- search as it's typed asks for the same hundreds of NPCs' at every letter. Read only, by all
-- who ask; let go with the rest when the map's been closed a while, or when there are many)
local spawnCache, spawnCount = {}, 0
local SPAWN_KEEP = 8000

function Index.ReleaseSpawns()
	spawnCache, spawnCount = {}, 0
end

function Index.Spawns(DB, id)
	local of = spawnCache[DB]
	if not of then of = {} spawnCache[DB] = of end
	local hit = of[id]
	if hit ~= nil then return hit or nil end
	local ok, spawns = pcall(DB.Get, id, "spawns")
	if not ok or type(spawns) ~= "table" then spawns = nil end
	if (not spawns or next(spawns) == nil) and DB == Index.ObjectDB() and DB.GetRaw then
		local okR, raw = pcall(DB.GetRaw, id, "spawns")
		if okR and type(raw) == "table" and next(raw) ~= nil then spawns = raw end
	end
	if spawnCount >= SPAWN_KEEP then
		spawnCache, spawnCount = {}, 0
		of = {}
		spawnCache[DB] = of
	end
	of[id] = spawns or false
	spawnCount = spawnCount + 1
	return spawns
end

--------------------------------------------------------------------------------
-- What a trainer trains, from its title
--------------------------------------------------------------------------------

-- profession skill IDs (Questie's professionKeys) by a word in the title. A trainer's title
-- often doesn't say "Trainer" ("Journeyman Blacksmith"): it's the trainer flag that says so.
local PROF_WORDS = {
	{ "first aid", 129 }, { "physician", 129 }, { "surgeon", 129 },
	{ "armorsmith", 164 }, { "weaponsmith", 164 }, { "blacksmith", 164 },
	{ "leather", 165 }, { "alchem", 171 }, { "herbalis", 182 }, { "cook", 185 },
	{ "mining", 186 }, { "miner", 186 }, { "tailor", 197 }, { "engineer", 202 },
	{ "enchant", 333 }, { "fish", 356 }, { "skinn", 393 }, { "jewel", 755 },
	{ "inscri", 773 }, { "riding", 762 },
}

-- class trainers: by the class's name in the title, plus the ones that don't name it
local CLASS_EXTRA = { ["demon trainer"] = "WARLOCK", ["portal"] = "MAGE" }
local classWords

local function ClassWords()
	if classWords then return classWords end
	classWords = {}
	for _, t in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE or {}, _G.LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
		for file, name in pairs(t) do classWords[#classWords + 1] = { lower(name), file } end
	end
	for word, file in pairs(CLASS_EXTRA) do classWords[#classWords + 1] = { word, file } end
	return classWords
end

local function TrainerOf(lsub)
	if lsub == "" then return end
	for _, w in ipairs(ClassWords()) do
		if find(lsub, w[1], 1, true) then return w[2], nil end
	end
	for _, w in ipairs(PROF_WORDS) do
		if find(lsub, w[1], 1, true) then return nil, w[2] end
	end
end

--------------------------------------------------------------------------------
-- Which objects are worth finding (by name)
--------------------------------------------------------------------------------

-- the fires you can cook at, by name. (Not every fire: braziers, event and quest fires, and
-- burnt-out ones are left out)
local COOK_FIRES = {}
for _, n in ipairs({ "campfire", "bonfire", "fire", "cozy fire", "blazing fire", "roaring fire",
	"warm fire", "small fire", "burning fire", "smoldering fire", "raging fire", "tribal fire",
	"bone fire", "bonefire", "dwarven fire", "dwarven campfire", "crackling campfire", "basic campfire",
	"bright campfire", "flickering campfire", "troll bonfire", "raging bonfire", "roaring bonfire",
	"fire pit", "firepit", "ogre firepit", "stove", "potbelly stove" }) do
	COOK_FIRES[n] = true
end

-- what's gathered: ore veins and deposits by name, the herbs by theirs
local HERBS = {}
for _, n in ipairs({ "peacebloom", "silverleaf", "earthroot", "mageroyal", "briarthorn", "stranglekelp", "bruiseweed",
	"wild steelbloom", "grave moss", "kingsblood", "liferoot", "fadeleaf", "goldthorn", "khadgars whisker", "wintersbite",
	"firebloom", "purple lotus", "arthas tears", "sungrass", "blindweed", "ghost mushroom", "gromsblood", "golden sansam",
	"dreamfoil", "mountain silversage", "plaguebloom", "icecap", "black lotus", "bloodthistle", "felweed", "dreaming glory",
	"terocone", "ragveil", "flame cap", "ancient lichen", "netherbloom", "nightmare vine", "mana thistle" }) do
	HERBS[n] = true
end
local function Gathered(lname)
	if find(lname, "doodad", 1, true) then return false end
	if find(lname, "%f[%a]vein$") or find(lname, "%f[%a]deposit$") then return true end
	return HERBS[(lname:gsub("'", ""))] or false
end

local function ObjectKind(lname)
	if lname == "mailbox" then return "MAILBOX" end
	if find(lname, "doodad", 1, true) then return end
	if find(lname, "%f[%a]forge$") then return "FORGE" end            -- (not Ironforge)
	if find(lname, "%f[%a]anvil$") then return "ANVIL" end            -- (not Anvilmar)
	if COOK_FIRES[lname] or find(lname, "^cooking ") then return "COOKING" end
	if find(lname, "meeting stone", 1, true) then return "MEETING_STONE" end
end

-- the skill books ("Expert First Aid - Under Wraps"): a recipe item whose name starts with a
-- rank, which lifts that skill's cap. Rank -> the cap it lifts from, and to
local BOOK_RANKS = { journeyman = { 75, 150 }, expert = { 150, 225 }, artisan = { 225, 300 } }

-- what a vendor's wares are, for its tooltip: item class (and subclass) -> a group, in order
Index.GROUPS = { L["Consumables"], L["Reagents"], L["Trade goods"], L["Ammo"], L["Recipes"], L["Weapons"], L["Armor"],
	L["Bags"], L["Mounts & pets"], L["Other"] }
local CLASS_GROUP = { [0] = 1, [5] = 2, [7] = 3, [6] = 4, [11] = 4, [9] = 5, [2] = 6, [4] = 7, [1] = 8 }

local function Group(class, sub)
	class, sub = tonumber(class) or 0, tonumber(sub) or 0
	if class == 15 then
		if sub == 1 then return 2 end                     -- (poison and spell reagents)
		if sub == 2 or sub == 5 then return 9 end         -- (pets, mounts)
	end
	return CLASS_GROUP[class] or 10
end

--------------------------------------------------------------------------------

--- whether no vendor sells an item by this (lower-case) name
local function ByGroup(a, b)
	if a.group ~= b.group then return a.group < b.group end
	return a.name < b.name
end

-- (a list per vendor, kept for all of them, was a megabyte; this is a look through the items,
-- a moment's work, for the few vendors whose tooltip or card is up. The last few are kept)
local waresCache, waresCount = {}, 0
local WARES_KEPT = 24

--- what NPC npcId sells: the items (id, name, group, book), by group then name; nil if nothing
function Index.Wares(npcId)
	if not npcId then return end
	if npcId < 0 then return ns.FakeWares and ns.FakeWares[npcId] end   -- (GM Island's: Pins.lua)
	local hit = waresCache[npcId]
	if hit ~= nil then return hit or nil end
	local list = {}
	for _, it in ipairs(Index.items) do
		for _, v in ipairs(it.vendors) do
			if v == npcId then list[#list + 1] = it break end
		end
	end
	table.sort(list, ByGroup)
	if waresCount >= WARES_KEPT then wipe(waresCache) waresCount = 0 end
	waresCache[npcId] = #list > 0 and list or false
	waresCount = waresCount + 1
	return #list > 0 and list or nil
end

--- a name or search without its spaces and hyphens: "peace bloom", "peacebloom" and
--- "Peacebloom" alike ("mid night", "midnight")
function ns.Squash(s) return (s:gsub("[%s%-]", "")) end

--- the name (as kept) of the item no vendor sells whose name, squashed, is this; or nil. Looked
--- for among the names that start as it does and are about as long: no table of them all kept
--- (that was two megabytes)
function Index.UnsoldSquashed(sq)
	if sq == "" then return nil end
	local first = sq:sub(1, 1):gsub("%W", "%%%0")
	local n = #sq
	for name in Index.unsold:gmatch("\n(" .. first .. "[^\1\n]*)\1") do
		local len = #name
		if len >= n and len <= n + 6 and ns.Squash(name) == sq then return name end
	end
	return nil
end

function Index.Unsold(lname)
	lname = lname:gsub("'", "")
	return lname ~= "" and not find(lname, "\n", 1, true)
		and find(Index.unsold, "\n" .. lname .. "\1", 1, true) ~= nil
end

--- the items no vendor sells whose names have what's typed (lower case, apostrophes gone): up to
--- max names, as the game spells them, the ones it starts first, then a word of it, then the rest.
--- (A walk of the hits in the one string: not of the thousands of names)
function Index.UnsoldSuggest(q, max)
	local out, seen, hits = {}, {}, {}
	local s = Index.unsold
	if not s or #q < 3 or find(q, "\n", 1, true) then return out end
	local ItemDB = Index.ItemDB()
	-- (the words typed: the longest looked for, the rest each start a word of the name)
	local toks, long = {}, ""
	for w in q:gmatch("%S+") do
		toks[#toks + 1] = w
		if #w > #long then long = w end
	end
	if long == "" then return out end
	local word = {}   -- (each word typed, as a word's start in a name: after a space or a dash)
	for i, t in ipairs(toks) do word[i] = "[ %-]" .. t:gsub("%W", "%%%0") end
	-- (how well a name fits: it starts with what's typed; each word typed starts a word of it;
	-- else they're in it somewhere)
	local function Fits(name)
		if sub(name, 1, #q) == q then return 0 end
		for i, t in ipairs(toks) do
			if sub(name, 1, #t) ~= t and not find(name, word[i]) then return 2 end
		end
		return 1
	end
	-- the hits of the word, in three looks: at a name's start, at a word's, anywhere; each
	-- stops once it has plenty
	for pass, pat in ipairs({ "\n" .. long, " " .. long, long }) do
		local at, n = 1, 0
		while n < 400 and #hits < max * 3 do
			local a, b = find(s, pat, at, true)
			if not a then break end
			n = n + 1
			if byte(s, a) == 10 then a = a + 1 end   -- (a hit at a name's start: the name, not the break)
			local ls = a   -- the line's start (a step back: the names are short)
			while ls > 1 and byte(s, ls - 1) ~= 10 do ls = ls - 1 end
			local e = find(s, "\1", ls, true)
			local nl = find(s, "\n", a, true)
			at = b + 1
			-- (the hit's in a name, not an id; and the other words typed are in that name too)
			local all = e and nl and e < nl and b < e
			if all then
				for _, t in ipairs(toks) do
					if t ~= long then
						local p = find(s, t, ls, true)
						if not (p and p < e) then all = false break end
					end
				end
			end
			if all then
				local name = sub(s, ls, e - 1)
				if not seen[name] then
					seen[name] = true
					local score = Fits(name)
					if score < 2 or pass == 3 then
						hits[#hits + 1] = { name = name, score = score, id = tonumber(sub(s, e + 1, nl - 1)) }
					end
				end
				at = nl
			end
		end
	end
	table.sort(hits, function(x, y)
		if x.score ~= y.score then return x.score < y.score end
		if #x.name ~= #y.name then return #x.name < #y.name end
		return x.name < y.name
	end)
	for _, h in ipairs(hits) do
		if #out >= max then break end
		local ok, name
		if ItemDB then ok, name = pcall(ItemDB.Get, h.id, "name") end
		out[#out + 1] = ok and type(name) == "string" and name or h.name
	end
	return out
end

--- the ids of the items no vendor sells with this name (lower case, apostrophes gone)
function Index.UnsoldIds(lname)
	local out, s, pat, at = {}, Index.unsold, "\n" .. lname .. "\1", 1
	while true do
		local _, b = find(s, pat, at, true)
		if not b then break end
		local e = find(s, "\n", b + 1, true) or (#s + 1)
		out[#out + 1] = tonumber(s:sub(b + 1, e - 1))
		at = e
	end
	return out
end

local function Steps(DB)
	return DB and DB.GetAllIds and DB.GetAllIds() or {}
end

function Index.Start()
	if Index.running or Index.done then return end
	local NpcDB = Index.DB()
	if not (NpcDB and NpcDB.GetAllIds and NpcDB.GetAll) then
		ns.Print(L["QuestieDB's NPC data isn't available, so there's nothing to search."])
		return
	end
	Index.running = true
	local ObjDB, ItemDB = Index.ObjectDB(), Index.ItemDB()
	local npcIds, objIds, itemIds = Steps(NpcDB), Steps(ObjDB), Steps(ItemDB)
	local enum = _G.LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.npcFlags
	local STABLE = enum and enum.STABLEMASTER
	local TRAINER = enum and enum.TRAINER
	local total = #npcIds + #objIds + #itemIds
	local step = 0

	local function Tick()
		step = step + 1
		if step % PER_FRAME == 0 then
			Index.progress = step / total
			coroutine.yield()
		end
	end

	local co = coroutine.create(function()
		local entries, byId = Index.entries, Index.byId
		for i = 1, #npcIds do
			local id = npcIds[i]
			local ok, v = pcall(NpcDB.GetAll, id, FIELDS)
			-- (only NPCs with a place in the world: one without can't be put on the map, and it's
			-- over a quarter of them)
			if ok and v and type(v[1]) == "string" and v[1] ~= "" and type(v[5]) == "table" and next(v[5]) ~= nil then
				local name, sub = v[1], v[2]
				if type(sub) ~= "string" or sub == "" then sub = nil end
				local lsub = sub and lower(sub) or ""
				local flags = tonumber(v[3]) or 0
				local stable = (STABLE and bit.band(flags, STABLE) ~= 0) or find(lsub, "stable master", 1, true)
					or find(lsub, "stablemaster", 1, true) or find(lsub, "stablehand", 1, true)
				local class, prof
				-- (by the trainer flag, or a title that says so: some, like warlocks' demon trainers,
				-- don't carry the flag)
				if (TRAINER and bit.band(flags, TRAINER) ~= 0) or find(lsub, "trainer", 1, true) then
					class, prof = TrainerOf(lsub)
				end
				-- (made with the fields every NPC has, and the rest only when it has them: a table
				-- made with room for every field takes twice the memory, and there are thousands)
				-- (hay: the name and title, lower case, apostrophes gone: "zulfarrak", "zul'farrak" alike)
				local e = { id = id, name = name, flags = flags, hay = (lower(sub and (name .. " " .. sub) or name):gsub("'", "")) }
				e.sq = ns.Squash(e.hay)   -- (its name and title run together: "edwinvancleef")
				if sub then e.sub = sub end
				-- the faction it's friendly to: "A" or "H" (both or neither: left out)
				local fac = v[4]
				if fac == "A" or fac == "H" then e.fac = fac end
				if v[6] == 2 or v[6] == 4 then e.rare = v[6] end   -- (a rare mob: 2 rare elite, 4 rare)
				if class then e.class = class end   -- the class file ("MAGE") a class trainer trains
				if prof then e.prof = prof end      -- the profession skill ID a profession trainer trains
				-- hunters only: pet trainers ("Pet Trainer", "Hunter Beast Trainer") and stable
				-- masters (by title or flag), but not one who also trains riding
				if find(lsub, "pet trainer", 1, true) or find(lsub, "beast trainer", 1, true)
					or (stable and not find(lsub, "riding", 1, true)) then
					e.pet = true
				end
				entries[#entries + 1] = e
				byId[id] = e
			end
			Tick()
		end

		local objects = Index.objects
		for i = 1, #objIds do
			local id = objIds[i]
			local ok, name = pcall(ObjDB.Get, id, "name")
			if ok and type(name) == "string" then
				local kind = ObjectKind(lower(name))
				if kind then objects[#objects + 1] = { obj = true, id = id, name = name, kind = kind } end
				if not kind and Gathered(lower(name)) then Index.gather[#Index.gather + 1] = { id, name } end
			end
			Tick()
		end

		local items, unsold = Index.items, {}
		local byId = Index.byId
		-- (only the vendors kept above, the ones with a place: the list as it is when that's all of them)
		local function Placed(vendors)
			for _, npc in ipairs(vendors) do
				if not byId[npc] then
					local out = {}
					for _, n in ipairs(vendors) do if byId[n] then out[#out + 1] = n end end
					return out
				end
			end
			return vendors
		end
		-- a bag of a kind (a container that isn't a plain bag): kept, sold or not
		local function Bag(id, name, class, sub, it)
			class, sub = tonumber(class), tonumber(sub)
			if class == 1 and sub and sub > 0 then
				Index.bags[#Index.bags + 1] = { id = id, name = name, lname = (lower(name):gsub("'", "")), kind = sub, item = it }
			end
		end
		for i = 1, #itemIds do
			local id = itemIds[i]
			local ok, vendors = pcall(ItemDB.Get, id, "vendors")
			local ok2, name = pcall(ItemDB.Get, id, "name")
			if ok2 and type(name) == "string" and name ~= "" then
				if ok and type(vendors) == "table" then vendors = Placed(vendors) end
				if ok and type(vendors) == "table" and #vendors > 0 then
					local _, class = pcall(ItemDB.Get, id, "class")
					local _, sub = pcall(ItemDB.Get, id, "subClass")
					local it = { id = id, name = name, lname = (lower(name):gsub("'", "")), vendors = vendors, group = Group(class, sub) }
					it.sq = ns.Squash(it.lname)
					items[#items + 1] = it
					Bag(id, name, class, sub, it)
					local rank = tonumber(class) == 9 and BOOK_RANKS[lower(name):match("^(%a+) ") or ""]
					if rank then
						local book = { id = id, name = name, sub = tonumber(sub), from = rank[1], to = rank[2],
							vendors = vendors }
						Index.skillBooks[#Index.skillBooks + 1] = book
						it.book = book
					end
				else
					unsold[#unsold + 1] = (lower(name):gsub("'", "")) .. "\1" .. id
					-- (a bag no vendor sells, made by a profession: its kind, to find its pattern by)
					local l = lower(name)
					if l:find("bag", 1, true) or l:find("pouch", 1, true) or l:find("sack", 1, true)
						or l:find("satchel", 1, true) or l:find("pack", 1, true) or l:find("box", 1, true) then
						local _, class = pcall(ItemDB.Get, id, "class")
						local _, sub = pcall(ItemDB.Get, id, "subClass")
						Bag(id, name, class, sub)
					end
				end
			end
			Tick()
		end
		-- (one string, not a table of thousands of names: a quarter of the memory)
		Index.unsold = "\n" .. table.concat(unsold, "\n") .. "\n"
	end)

	local driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(self)
		local ok, err = coroutine.resume(co)
		if not ok then
			self:SetScript("OnUpdate", nil)
			Index.running = false
			geterrorhandler()(err)
			return
		end
		if coroutine.status(co) == "dead" then
			self:SetScript("OnUpdate", nil)
			Index.running, Index.done, Index.progress = false, true, 1
			if ns.UI.OnIndexed then ns.UI.OnIndexed() end
		elseif ns.UI.OnIndexProgress then
			ns.UI.OnIndexProgress(Index.progress)
		end
	end)
end
