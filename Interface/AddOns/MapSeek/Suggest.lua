--------------------------------------------------------------------------------
-- Type-ahead and spelling.
--   Suggest.For(text):    up to 8 things worth searching that start with (or have words
--                         starting with) what's typed: search words ("repair", "mailbox"),
--                         titles ("Fishing Trainer"), items vendors sell, NPC names
--   Suggest.Correct(text): the search with each misspelled word swapped for the closest word
--                         Questie's data has ("fishng trainr" -> "fishing trainer"), or nil
-- Built from the index on first use (after login), rebuilt when the faction setting changes.
--------------------------------------------------------------------------------

local _, ns = ...
local Suggest = {}
ns.Suggest = Suggest

local find, lower, sub, byte = string.find, string.lower, string.sub, string.byte
local min, abs = math.min, math.abs

local MAX = 8

-- what each kind of suggestion is, in the list (and its order there, among equally good ones).
-- (ns.L in full in this file: L is a field's index below)
local HINTS = { search = ns.L["search"], title = ns.L["title"], item = ns.L["item"], npc = ns.L["NPC"],
	zone = ns.L["zone"], city = ns.L["city"], continent = ns.L["continent"], dungeon = ns.L["dungeon"] }   -- (a town's: its zone)
local ORDER = { search = 0, city = 0.5, zone = 0.5, continent = 0.5, dungeon = 0.6, town = 0.7, title = 1, item = 2, npc = 3 }

-- the search words worth offering (Search.lua knows them all)
local KEYWORDS = {
	"repair", "innkeeper", "flight master", "banker", "auctioneer", "trainer", "vendor",
	"battlemaster", "tabard", "quests", "mailbox", "forge", "anvil", "campfire", "meeting stone",
	"skill books", "first aid book", "cooking book", "fishing book", "reagent vendor",
	"party", "raid", "dungeons", "dungeons for my level", "raids",
}

-- each thing worth offering: { text, lower-case text, hint, NPC id(s) }, as an array (a quarter
-- of the memory of named fields, over thousands of them). The id(s): one id, or a list of them
local TEXT, L, HINT, IDS = 1, 2, 3, 4
local vocab
local wordList, wordCount         -- every word (3+ letters) in the data, and how often it comes up
local placeable = {}              -- npcId -> has a spawn we could mark

function Suggest.Reset() vocab = nil end

--- let the vocabulary go (the map closed a while ago: it's the biggest thing MapSeek keeps, and
--- only wanted while typing). Built again the next time something's typed
function Suggest.Release()
	vocab, wordList, wordCount = nil, nil, nil
	wipe(placeable)
end

--- edits from a to b, or cap + 1 once it's more (below)
local Distance

local function Build()
	vocab, wordCount = {}, {}
	local seen = {}
	local hunter = select(2, UnitClass("player")) == "HUNTER"

	local function Words(l)
		for w in l:gsub("'", ""):gmatch("%a+") do
			if #w >= 3 then wordCount[w] = (wordCount[w] or 0) + 1 end
		end
	end
	local function Add(text, hint, id)
		local l = lower(text):gsub("'", "")
		local v = seen[l]
		if v then
			local ids = v[IDS]
			if id and ids then
				if type(ids) == "number" then v[IDS] = { ids, id }
				elseif #ids < 8 then ids[#ids + 1] = id end
			end
			return
		end
		v = { text, l, hint, id }
		seen[l] = v
		vocab[#vocab + 1] = v
		Words(l)
	end

	for _, k in ipairs(KEYWORDS) do Add(k, "search") end
	if hunter then Add("stable master", "search") end
	-- (the places: picked, the map goes there)
	for _, p in ipairs(ns.Search.Places()) do Add(p.name, p.kind, p.kind == "town" and p.id or nil) end
	for w in pairs(ns.Search.OBJECTS) do Words(w) end
	for _, e in ipairs(ns.Index.entries) do
		if (hunter or not e.pet) and ns.Search.FactionOk(e.fac) then
			if e.sub then Add(e.sub, "title") end
		end
	end
	for _, it in ipairs(ns.Index.items) do Add(it.name, "item") end
	for _, e in ipairs(ns.Index.entries) do
		if (hunter or not e.pet) and ns.Search.FactionOk(e.fac) then Add(e.name, "npc", e.id) end
	end

	-- (the words of the items no vendor sells, and of the quests, are words too: a search for
	-- "studies" isn't "fixed" to "studded")
	for w in ns.Index.unsold:gmatch("%a+") do
		if #w >= 3 then wordCount[w] = (wordCount[w] or 0) + 1 end
	end
	for _, q in ipairs(ns.Search.QuestNames()) do Words(lower(q[2])) end

	wordList = {}
	for w in pairs(wordCount) do wordList[#wordList + 1] = w end
end

-- an NPC name is only worth offering if one of its NPCs can be put on the map
local function Placed(v)
	if v[HINT] ~= "npc" then return true end
	local NpcDB = ns.Index.DB()
	local ids = v[IDS]
	for _, id in ipairs(type(ids) == "table" and ids or { ids }) do
		local c = placeable[id]
		if c == nil then
			local ok, s = pcall(NpcDB.Get, id, "spawns")
			c = ok and type(s) == "table" and next(s) ~= nil or false
			placeable[id] = c
		end
		if c then return true end
	end
	return false
end

--- up to MAX { text, hint } for what's typed
function Suggest.For(text)
	if not ns.Index.done then return {} end
	if not vocab then Build() end
	local q = lower(strtrim(text or "")):gsub("'", "")
	if #q < 2 then return {} end
	local toks = {}
	for w in q:gmatch("%S+") do toks[#toks + 1] = w end
	local noThe = q:match("^the (.+)$")   -- ("the lower wi": Lower Wilds, a place named without it)
	local qsq = #q >= 4 and ns.Squash(q) or nil   -- ("peace bl", "simpleflo": spaces or not)

	local hits, scores = {}, {}
	for _, v in ipairs(vocab) do
		local l = v[L]
		if l ~= q then
			local score
			if sub(l, 1, #q) == q then
				score = 0                                         -- starts with it
			else
				-- (each word typed starts a word of it: at its start, or after a space)
				local all = true
				for _, t in ipairs(toks) do
					if sub(l, 1, #t) ~= t and not find(l, " " .. t, 1, true) then all = false break end
				end
				if all then score = 1                             -- every word starts a word
				elseif #q >= 3 and find(l, q, 1, true) then score = 2 end   -- in it somewhere
			end
			if not score and noThe and sub(l, 1, #noThe) == noThe then score = 1 end
			if not score and qsq then
				local lsq = v.sq
				if not lsq then lsq = ns.Squash(l) v.sq = lsq end
				if sub(lsq, 1, #qsq) == qsq then score = 1 elseif find(lsq, qsq, 1, true) then score = 2 end
			end
			if score then
				scores[v] = score
				hits[#hits + 1] = v
			end
		end
	end
	table.sort(hits, function(a, b)
		local sa, sb = scores[a], scores[b]
		if sa ~= sb then return sa < sb end
		if a[HINT] ~= b[HINT] then return ORDER[a[HINT]] < ORDER[b[HINT]] end
		local la, lb = a[L], b[L]
		if #la ~= #lb then return #la < #lb end
		return la < lb
	end)

	local out = {}
	-- (a short name for a place ("sm", "stocks"): the place it stands for, first)
	local place = ns.Search.Place(q)
	local placeL = place and lower(place.name):gsub("'", "")
	if place and placeL ~= q then
		out[1] = { text = place.name, kind = place.kind,
			hint = place.kind == "town" and (ns.ZoneName(place.id) or ns.L["place"]) or HINTS[place.kind] or place.kind }
	end
	for _, v in ipairs(hits) do
		if Placed(v) and not (placeL and v[L] == placeL and out[1]) then
			local hint = HINTS[v[HINT]]
			if v[HINT] == "town" then
				local ui = v[IDS]
				hint = ns.ZoneName(type(ui) == "table" and ui[1] or ui) or ns.L["place"]
			end
			out[#out + 1] = { text = v[TEXT], hint = hint, kind = v[HINT] }
			if #out >= MAX then break end
		end
	end
	local have = {}
	for _, o in ipairs(out) do have[lower(o.text)] = true end
	-- (the items no vendor sells, after the rest: searched, where they drop, or the quest
	-- that rewards them: "nat pagle's extreme angler fc-5000")
	if #out < MAX then
		for _, name in ipairs(ns.Index.UnsoldSuggest(q, MAX - #out)) do
			local l = lower(name):gsub("'", "")
			if not have[l] then
				have[l] = true
				out[#out + 1] = { text = name, hint = HINTS.item }
			end
		end
	end
	-- (quests by name, after the rest: picked, who starts it)
	if #out < MAX then
		for _, name in ipairs(ns.Search.QuestSuggest(q, MAX - #out + 4)) do
			if #out >= MAX then break end
			if not have[lower(name)] then
				have[lower(name)] = true
				out[#out + 1] = { text = name, hint = ns.L["quest"], kind = "quest" }
			end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Spelling
--------------------------------------------------------------------------------

-- edits from a to b (insert, delete, change, or swap two letters side by side), or cap + 1
-- once it's sure to be more than cap. (Three rows, reused: this runs over every word.)
local rowA, rowB, rowC = {}, {}, {}
function Distance(a, b, cap)
	local la, lb = #a, #b
	if abs(la - lb) > cap then return cap + 1 end
	local prev2, prev, cur = rowC, rowA, rowB
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		cur[0] = i
		local best = i
		local ai = byte(a, i)
		for j = 1, lb do
			local bj = byte(b, j)
			local v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ai == bj and 0 or 1))
			if i > 1 and j > 1 and ai == byte(b, j - 1) and byte(a, i - 1) == bj then
				v = min(v, prev2[j - 2] + 1)
			end
			cur[j] = v
			if v < best then best = v end
		end
		if best > cap then return cap + 1 end
		prev2, prev, cur = prev, cur, prev2
	end
	return prev[lb]
end

local CANDIDATES = 4   -- words tried for each misspelled one, closest first

-- the closest words to a misspelled one, closest first (up to CANDIDATES): whole words, or (while
-- you're still typing it) the start of one. Ties go to the word the data uses most
local function Closest(tok)
	local cap = #tok <= 4 and 1 or 2
	local found = {}
	local t1, t2 = byte(tok, 1), byte(tok, 2)
	for _, w in ipairs(wordList) do
		-- (a slip keeps the first letter, or swaps the first two: the rest can't be close enough
		-- to be worth the time)
		local w1 = byte(w, 1)
		local d = cap + 1
		if w1 == t1 or (w1 == t2 and byte(w, 2) == t1) then
			d = Distance(tok, w, cap)
			if d > cap and #tok >= 4 and #w > #tok then
				d = Distance(tok, sub(w, 1, #tok), cap) + 0.5  -- (the start of a word: a little worse)
			end
		end
		if d <= cap then found[#found + 1] = { w, d, wordCount[w] } end
	end
	table.sort(found, function(a, b)
		if a[2] ~= b[2] then return a[2] < b[2] end
		if a[3] ~= b[3] then return a[3] > b[3] end
		return a[1] < b[1]
	end)
	local out = {}
	for i = 1, min(CANDIDATES, #found) do out[i] = found[i][1] end
	return out
end

-- the plural of a word that ends in y, spelled with -ys ("supplys"), or a plural that's a slip
-- from one ("studdies": studies). nil when there's no such plural in the data
local function Plural(tok)
	local ies = tok:match("^(.+[^aeiou])ys$")
	if ies and wordCount[ies .. "ies"] then return ies .. "ies" end
	if sub(tok, -3) == "ies" or sub(tok, -2) == "ys" then
		local best, bestD
		for _, w in ipairs(wordList) do
			if sub(w, -3) == "ies" and byte(w, 1) == byte(tok, 1) then
				local d = Distance(tok, w, 2)
				if d <= 2 and (not bestD or d < bestD) then best, bestD = w, d end
			end
		end
		return best
	end
end

-- does a search find anything: a place, or matches (anywhere, or in a place named in it)?
-- "unsold" when it names an item no vendor sells
local function Finds(text)
	local S = ns.Search
	if S.Place(text) then return true end
	if S.Run(text, true) then return true end
	local rest, p = S.SplitPlace(text)
	if rest ~= nil and #rest >= 2 and S.Run(rest, true, p.id) ~= nil then return true end
	if ns.Index.Unsold(text) or (text:sub(-1) == "s" and ns.Index.Unsold(text:sub(1, -2))) then return "unsold" end
	return false
end

-- a search of a few words that finds nothing as a whole ("heavy rod", "guild bank"): without
-- one of them, when that finds something: the first word dropped first (the last is mostly the
-- thing itself: a rod, a bank), then the last, then the rest. Only whole words of some length
-- are kept ("am i" isn't offered for "where am i"), and not a search that names a place: "herb
-- trainer org" finding nothing is an answer. The search to offer ("did you mean"), or nil
local function DropWord(words)
	if #words < 2 or #words > 4 then return end
	if ns.Search.SplitPlace(table.concat(words, " ")) then return end
	local order = { 1, #words }
	for i = 2, #words - 1 do order[#order + 1] = i end
	for _, skip in ipairs(order) do
		local out, ok = {}, true
		for i, w in ipairs(words) do
			if i ~= skip then
				if #w < 3 then ok = false break end
				out[#out + 1] = w
			end
		end
		if ok then
			local fix = table.concat(out, " ")
			if Finds(fix) == true then return fix end
		end
	end
end

local TRIES = 8   -- fixed searches tried at most, to find one that finds something

Suggest.Distance = function(a, b, cap) return Distance(a, b, cap) end

--- the search with its misspelled words fixed, or nil when none are (or none can be). Only a
--- fix that finds something: the closest words first, then the next closest, a word at a time.
--- Failing that, one naming an item no vendor sells, and true ("mithril cassing": say no vendor
--- sells Mithril Casing)
function Suggest.Correct(text)
	if not ns.Index.done then return end
	if not vocab then Build() end
	local q = lower(strtrim(text or ""))
	local words, cands = {}, {}   -- (cands[i]: the words to try for word i, when it's misspelled)
	for word in q:gsub("'", ""):gmatch("%S+") do
		words[#words + 1] = word
		if #word >= 3 and word:find("^%a+$") and not wordCount[word] and not ns.Search.KnownWord(word) then
			-- (a plural with a slip in it first: "supplys" is supplies, "studdies" studies,
			-- before a closer word that isn't a plural, "supply" or "studded")
			local list, seen = {}, {}
			local plural = Plural(word)
			if plural then list[1], seen[plural] = plural, true end
			for _, w in ipairs(Closest(word)) do
				if not seen[w] then seen[w] = true list[#list + 1] = w end
			end
			if #list > 0 then cands[#words] = list end
		end
	end
	if not next(cands) then return DropWord(words) end
	-- (each misspelled word its closest; then one word at a time its next closest)
	local pick = {}
	for i in pairs(cands) do pick[i] = 1 end
	local unsold
	local function Try()
		local out = {}
		for i, w in ipairs(words) do out[i] = cands[i] and cands[i][pick[i]] or w end
		local fix = table.concat(out, " ")
		if fix == q:gsub("'", "") then return end
		local found = Finds(fix)
		if found == "unsold" then unsold = unsold or fix
		elseif found then return fix end
	end
	local tries = 1
	local fix = Try()
	if fix then return fix end
	for i, list in pairs(cands) do
		for j = 2, #list do
			if tries >= TRIES then return unsold, unsold and true end
			pick[i] = j
			tries = tries + 1
			fix = Try()
			if fix then return fix end
		end
		pick[i] = 1
	end
	if unsold then return unsold, true end
	return DropWord(words)
end

--- the place whose name is a letter or two off what's typed ("elwyn forest", "orgrimar"), the
--- closest; nil when none is that close
function Suggest.ClosestPlace(text)
	local q = (lower(strtrim(text or "")):gsub("^the ", ""))
	if #q < 4 then return end
	local cap = #q <= 6 and 1 or 2
	local best, bestD
	for _, p in ipairs(ns.Search.Places()) do
		local d = Distance(q, (lower(p.name):gsub("^the ", "")), cap)
		if d <= cap and (not bestD or d < bestD) then best, bestD = p, d end
	end
	return best or Suggest.LikePlace(text)
end

-- how far a typed word is from a place's word: a slip or two, or the start of it ("drown" of
-- "drowned"; a little worse). full: whether it's (nearly) the whole word, not just its start
local function WordOff(q, w)
	local cap = #q <= 4 and 1 or 2
	local d = Distance(q, w, cap)
	if d <= cap then return d, true end
	if #q >= 3 and #w > #q then
		-- (a slip in the start of a word only from 5 letters: "zzzz" isn't the start of anything)
		local c = #q >= 5 and 1 or 0
		local s = Distance(q, sub(w, 1, #q), c)
		if s <= c then return s + 0.5, #q >= #w * 0.8 end
	end
end

local KIND_RANK = { city = 0, zone = 0, dungeon = 0, continent = 1, town = 2 }

--- the place a search is a misspelling or the start of, word by word: "drown ciuty" is The Drowned
--- City, "krol dok" Krol'dok Stronghold, "westfal" Westfall. Each word is a slip or two off the
--- place's word in its place, from its first word. sure: only a zone, city or dungeon the search
--- all but names ("stranglethorn", "blackfathom", "deadmine"; not a town, not just its start),
--- and only when it's the one; for a search that found something else, which this wins over
function Suggest.LikePlace(text, sure)
	local q = (lower(strtrim(text or "")):gsub("^the ", ""))
	if #q < (sure and 5 or 4) then return end
	local qw = {}
	for w in q:gsub("[':%-]", ""):gmatch("%S+") do qw[#qw + 1] = w end
	local qj = table.concat(qw)
	local best, bestS, bestR
	for _, p in ipairs(ns.Search.Places()) do
		local r = KIND_RANK[p.kind] or 2
		-- (sure: not a dungeon's own map with no entrance to show, "Darkmoon Faire Island")
		if not (sure and (r > 0 or (p.kind == "dungeon" and not p.points))) then
			local name = (lower(p.name):gsub("^the ", ""):gsub("[':]", ""):gsub("%-", " "))
			local pw = {}
			for w in name:gmatch("%S+") do pw[#pw + 1] = w end
			local score, full
			-- (from its first word; or, not sure, a later one, a little worse: "ahn qiraj")
			for s = 0, sure and 0 or #pw - #qw do
				local sc, fu = s > 0 and 0.5 or 0, true
				for i = 1, #qw do
					local d, f
					if pw[s + i] then d, f = WordOff(qw[i], pw[s + i]) end
					if not d then sc = nil break end
					sc, fu = sc + d, fu and f
				end
				if sc and (not score or sc < score) then score, full = sc, fu end
			end
			-- (or run together, or split where the name isn't: "krol dok", "un goro", "zulfarrak")
			if not score and #qj >= 5 then
				local joined = ""
				for k = 1, #pw do
					joined = joined .. pw[k]
					local d, f = WordOff(qj, joined)
					if d and (not score or d < score) then score, full = d, f end
				end
			end
			if score and sure and (score > 1 or not full) then score = nil end
			if score and (not bestS or score < bestS or (score == bestS and r < bestR)) then
				best, bestS, bestR = { p }, score, r
			elseif score and score == bestS and r == bestR and p ~= best[#best] then
				best[#best + 1] = p
			end
		end
	end
	if not best then return end
	-- (two or more as close, as good: which isn't known. They're offered: Suggest.PlaceChoices)
	if #best > 1 then return nil, best end
	return best[1]
end

--- the places a search could as well be, when it's as like more than one ("razorfen": Kraul and
--- Downs; "plaguelands": Western and Eastern), by name, up to 6; nil when it's like one or none
function Suggest.PlaceChoices(text, sure)
	local one, several = Suggest.LikePlace(text, sure)
	if one or not several then return end
	table.sort(several, function(a, b) return a.name < b.name end)
	for i = #several, 7, -1 do several[i] = nil end
	return several
end

--- what a place is, beside its name in a list: a town's or dungeon's zone, or what kind it is
function Suggest.PlaceHint(p)
	if p.points and p.points[1] then return ns.ZoneName(p.points[1].ui) or HINTS[p.kind] or ns.L["place"] end
	return HINTS[p.kind] or p.kind
end
